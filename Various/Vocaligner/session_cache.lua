-- @noindex
local import=...;local Codec=import('codec');local Config=import('config');local Envelope=import('envelope');local Pack=import('cache_packing');local M={}
local section='Vocaligner session v7'
local function pack_layers(layers,job)
  local out={}
  for mode,curve in pairs(layers or {}) do
    out[mode]=Pack.curve(curve,job)
  end
  return out
end
local function unpack_layers(layers,job)
  for _,curve in pairs(layers or {}) do if curve.packed then
    assert(#curve.packed%16==0 and #curve.packed<=3600001*16,'Invalid curve cache.')
    curve.points={};local previous=-math.huge
    for at=1,#curve.packed,16 do
      local t,db=string.unpack('<dd',curve.packed,at)
      assert(t==t and t>=previous and t<=1800 and db==db and db>=-72 and db<=240,'Invalid cached gain point.')
      curve.points[#curve.points+1]={t=t,db=db};previous=t
      if job and #curve.points%256==0 then job:checkpoint() end
    end
    curve.packed=nil
    local shapes={}
    for _,shape in ipairs(type(curve.shapes)=='table' and curve.shapes or {})do
      if type(shape)=='table' and type(shape.a)=='number' and type(shape.b)=='number' and type(shape.tension)=='number'
        and shape.b>shape.a and math.abs(shape.tension)<=1 then shapes[#shapes+1]=shape end
    end
    curve.shapes=#shapes>0 and shapes or nil
    if curve.frozen then unpack_layers({curve.frozen},job) end
  end end
  return layers
end
local function hydrate(value,job)
  for _,s in ipairs({value.snapshot,table.unpack(value.outputs or {})}) do
    if s.volume_packed then s.volume_points=Pack.read_points(s.volume_packed,job);s.volume_packed=nil end
    if s.baseline_packed then s.baseline_points=Pack.read_points(s.baseline_packed,job);s.baseline_packed=nil end
  end
  for _,b in ipairs(value.baselines or {})do
    if b.volume_packed then b.volume_points=Pack.read_points(b.volume_packed,job);b.volume_packed=nil end
  end
end
local function hash(s)
  local h=2166136261;for i=1,#s do h=((h~s:byte(i))*16777619)&0xffffffff end
  return string.format('%08x',h)
end
local function state(s,job)
  local out={};for k,v in pairs(s) do
    if k~='item' and k~='take' and k~='source' and k~='project' and k~='volume_points' then out[k]=v end
  end;out.volume_packed=Pack.points(s.volume_points,job);return out
end
-- Копия данных для кэша: только числа/строки/булевы/таблицы, бесконечности и NaN приводятся к конечным
-- (Codec отвергает нечисла), глубина ограничена. Результаты разбора стадий могут содержать -inf dB на тишине.
local function finite_copy(v,depth)
  local t=type(v)
  if t=='number' then
    if v~=v then return 0 end
    if v==math.huge then return 1e9 elseif v==-math.huge then return -1e9 end
    return v
  elseif t=='table' and depth<12 then
    local out={}
    for k,x in pairs(v) do
      local kt,xt=type(k),type(x)
      if (kt=='string' or kt=='number') and (xt=='number' or xt=='string' or xt=='boolean' or xt=='table') then out[k]=finite_copy(x,depth+1) end
    end
    return out
  end
  return v
end
-- Результаты предпросмотра в кэше сессии: события и регионы маленькие, а «levels» (огибающая детектора на сетке 0.5–5 мс) —
-- сотни тысяч точек на длинном item. Их сохранение/чтение занимало секунды (string.pack/unpack на каждом чтении и записи),
-- а нужны они только для индикатора уровня. Кладём прореженную копию (не более MAX_LEVELS точек).
local MAX_LEVELS=3000
local function thin_levels(levels)
  if type(levels)~='table' or #levels<=MAX_LEVELS then return levels end
  local out={};local step=#levels/MAX_LEVELS
  for i=0,MAX_LEVELS-1 do out[#out+1]=levels[math.floor(i*step)+1] end
  out[#out+1]=levels[#levels]
  return out
end
local function compact_previews(store)
  if type(store)~='table' then return nil end
  local out={}
  for mode,p in pairs(store) do
    if type(p)=='table' then
      local c={};for k,v in pairs(p) do c[k]=v end
      c.levels=thin_levels(c.levels)
      if type(c.detected)=='table' then -- у стадий динамики detected — это ещё и плотные points/levels
        local dd={};for k,v in pairs(c.detected) do dd[k]=v end
        dd.levels=thin_levels(dd.levels);dd.points=thin_levels(dd.points);c.detected=dd
      end
      out[mode]=c
    end
  end
  return finite_copy(out,0)
end
function M.new(r,project)
  if not (r.GetExtState and r.SetExtState and r.GetResourcePath and r.RecursiveCreateDirectory) then return nil end
  local token=r.GetExtState(section,'session')
  if token=='' then token=(r.genGuid and r.genGuid() or tostring(os.time())..tostring(r.time_precise()));r.SetExtState(section,'session',token,false) end
  local dir=r.GetResourcePath()..'/Cache/Vocaligner'
  r.RecursiveCreateDirectory(dir,0)
  local master=r.GetMasterTrack and r.GetMasterTrack(project)
  local project_id=tostring(project)..'|'..(master and r.GetTrackGUID and r.GetTrackGUID(master) or '')
  local self={r=r,token=token,dir=dir,key=hash(project_id),project=project,entries={},headers={}}
  local list=r.GetExtState(section,self.key)
  for id in list:gmatch('[%x]+') do if #id==16 then self.entries[id]=true end end
  return setmetatable(self,{__index=M})
end
function M:path(id,kind) return self.dir..'/'..self.key..'-'..id..'.'..kind end
function M:write(id,kind,value,job)
  local bytes=Codec.encode({token=self.token,value=value},job)
  local path=self:path(id,kind);local f=assert(io.open(path..'.tmp','wb'));local ok,why=f:write(bytes);f:close();assert(ok,why)
  -- On Windows rename cannot replace an existing file. The temp stays complete.
  os.remove(path);assert(os.rename(path..'.tmp',path))
end
function M:read(id,kind,job)
  local f=io.open(self:path(id,kind),'rb');if not f then return nil end
  local size=f:seek('end');if size>128*1024*1024 then f:close();return nil end
  f:seek('set');local bytes=f:read('*a');f:close()
  local ok,data=pcall(Codec.decode,bytes,job)
  if not ok or data.token~=self.token then return nil end
  return data.value
end
function M:save(d,job)
  local guid=d.snapshot.guid
  local identity=guid..'|'..d.snapshot.render_key..'|'..string.format('%.9f|%.9f',d.snapshot.offset,d.snapshot.len)
  local id=hash(identity)..hash(identity:reverse())
  if d.audio and (d.audio_dirty or not d.audio_file) then
    local audio=Pack.audio(d.audio,job)
    self:write(id,'audio',audio,job);d.audio_file=id;d.audio_dirty=nil
  end
  local value={snapshot=state(d.snapshot,job),stamp=self.r.time_precise(),cfg=Config.copy(d.cfg),range=d.range,selected=d.selected,view=d.view,
    exclusions=d.exclusions,edits=d.edits,edits_rev=d.edits_rev,breath_profile=d.breath_profile,audio_file=d.audio_file,processed_modes=d.processed_modes,outputs={},
    bypassed=pack_layers(d.bypassed,job),baselines={},previews=compact_previews(d.preview_store)}
  for i,b in ipairs(d.baselines or {})do value.baselines[i]={volume_envelope=b.volume_envelope,volume_packed=Pack.points(b.volume_points,job)} end
  local n=0;local ordered={}
  for _,out in pairs(d.outputs or {}) do if type(out)=='table' and out.volume_envelope then ordered[#ordered+1]=out end end
  table.sort(ordered,function(a,b) return (a.sequence or 0)>(b.sequence or 0) end)
  for _,out in ipairs(ordered) do
    n=n+1;if n<=12 then
      local saved={volume_envelope=out.volume_envelope,volume_packed=Pack.points(out.volume_points,job),layers=pack_layers(out.layers,job),cfg=out.cfg,
        envelope_points=out.envelope_points,sequence=out.sequence,bypassed=out.bypassed and pack_layers(out.bypassed,job) or nil}
      -- Most outputs share the snapshot baseline; store only a kept manual edit.
      if out.baseline and out.baseline.volume_envelope==d.snapshot.volume_envelope then saved.baseline_kind='snapshot'
      elseif out.baseline then saved.baseline_kind='own';saved.baseline_envelope=out.baseline.volume_envelope;saved.baseline_packed=Pack.points(out.baseline.volume_points,job) end
      value.outputs[#value.outputs+1]=saved
    end
  end
  self:write(id,'meta',value,job);self.entries[id]=true
  local header={stamp=value.stamp};for _,k in ipairs({'guid','source_key','render_key','offset','len','rate'}) do header[k]=d.snapshot[k] end
  self:write(id,'index',header,job);self.headers[id]=header
  local ids={};for key in pairs(self.entries) do ids[#ids+1]=key end
  self.r.SetExtState(section,self.key,table.concat(ids,','),false)
end
function M:find(s)
  local candidate,exact,ambiguous
  local ids={};local exact_id,exact_stamp
  for id in pairs(self.entries) do
    local h=self.headers[id] or self:read(id,'index')
    if type(h)~='table' or type(h.guid)~='string' or type(h.source_key)~='string' or type(h.stamp)~='number' then
      local v=self:read(id,'meta');h=v and v.snapshot
      if not h then return nil,'A session cache record is damaged. Recover the unprocessed envelope with Undo.' end
      h.stamp=v.stamp or 0
    end
    self.headers[id]=h
    if h.guid==s.guid and (not exact_stamp or h.stamp>exact_stamp) then exact_id=id;exact_stamp=h.stamp end
    if h.source_key==s.source_key then ids[#ids+1]=id end
  end
  if exact_id then ids={exact_id} end
  for _,id in ipairs(ids) do
    local v=self:read(id,'meta')
    if not (type(v)=='table' and type(v.snapshot)=='table' and type(v.snapshot.guid)=='string'
      and type(v.snapshot.source_key)=='string' and type(v.snapshot.render_key)=='string'
      and type(v.snapshot.len)=='number' and v.snapshot.len>0 and v.snapshot.len<=1800
      and type(v.outputs)=='table' and type(v.cfg)=='table') then
      return nil,'A session cache record is damaged. Recover the unprocessed envelope with Undo before starting a new REAPER session.'
    end
    if v and v.snapshot.guid==s.guid and (not exact or (v.stamp or 0)>(exact.stamp or 0)) then exact=v end
    if not exact_id and v and v.snapshot.source_key==s.source_key then
      hydrate(v)
      local a,b=v.snapshot.offset,v.snapshot.offset+v.snapshot.len*v.snapshot.rate
      if #s.markers==0 and #v.snapshot.markers==0 and s.offset>=a-1e-7 and s.offset+s.len*s.rate<=b+1e-7 then
        local shift=a-s.offset;local size=s.len*s.rate
        local matches=false
        for _,delta in ipairs({shift,0}) do
          if Envelope.equivalent(s.volume_envelope,Envelope.shift(v.snapshot.volume_envelope,delta),size,
            s.volume_points,Envelope.shift_points(v.snapshot.volume_points,delta)) then matches=true end
          for _,out in pairs(v.outputs or {}) do
            if Envelope.equivalent(s.volume_envelope,Envelope.shift(out.volume_envelope,delta),size,
              s.volume_points,Envelope.shift_points(out.volume_points,delta)) then matches=true;break end
          end
        end
        if matches and (not candidate or (v.stamp or 0)>(candidate.stamp or 0)) then candidate=v end
        if not matches and s.volume_envelope and #v.outputs>0 then ambiguous=v end
      end
    end
  end
  return exact or candidate or ambiguous
end
function M:attach(v,s,job)
  hydrate(v,job)
  local old=v.snapshot;old.item=s.item;old.take=s.take;old.source=s.source;old.project=s.project
  -- A record of another take (same source file) may lend its layers only when
  -- the envelope proves it, e.g. a split child. State.check reads this flag.
  local foreign=old.guid~=s.guid
  old.guid=s.guid
  local merged=Config.copy(Config.defaults);for k,val in pairs(v.cfg)do merged[k]=val end
  local d={snapshot=old,enabled=true,cfg=merged,range=v.range or {0,old.len},selected=v.selected,
    view=v.view,exclusions=v.exclusions or {},edits=v.edits or {},edits_rev=v.edits_rev,breath_profile=v.breath_profile,audio_file=v.audio_file,
    processed_modes=v.processed_modes,outputs=v.outputs or {},plan=import('cleanup_state').plan(old),foreign=foreign or nil,
    preview_store=type(v.previews)=='table' and compact_previews(v.previews) or nil}
  for _,out in pairs(d.outputs) do
    d.output_sequence=math.max(d.output_sequence or 0,out.sequence or 0);out.layers=unpack_layers(out.layers,job);out.cleanup=out
    if out.bypassed then out.bypassed=unpack_layers(out.bypassed,job) end
    if out.baseline_kind=='snapshot' then out.baseline={volume_envelope=old.volume_envelope,volume_points=old.volume_points}
    elseif out.baseline_kind=='own' then out.baseline={volume_envelope=out.baseline_envelope,volume_points=out.baseline_points} end
    out.baseline_kind=nil;out.baseline_envelope=nil;out.baseline_points=nil
  end
  if type(v.bypassed)=='table' and next(v.bypassed) then d.bypassed=unpack_layers(v.bypassed,job) end
  if type(v.baselines)=='table' and #v.baselines>0 then
    d.baselines={};for i,b in ipairs(v.baselines)do d.baselines[i]={volume_envelope=b.volume_envelope,volume_points=b.volume_points} end
  end
  if v.audio_file then
    local audio=self:read(v.audio_file,'audio',job)
    if audio then local cfg=Config.copy(d.cfg);cfg.cleanup_only=true;d.audio=import('dsp').normalize(Pack.read_audio(audio,job),cfg,job) end
  end
  return d
end
return M
