-- @noindex
local import=...;local Codec=import('codec');local Notes=import('pitch/notes');local Wave=import('pitch/waveform');local M={}
M.section='Vocaligner Pitch 1';M.key='P_EXT:VocalignerPitch1'
local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function validate_capture(records)
  if records==nil then return end
  assert(type(records)=='table' and #records<10000,'Invalid captured Curve notes')
  local count=0
  for _,q in ipairs(records)do
    assert(type(q.id)=='number' and type(q.start)=='number' and type(q.finish)=='number' and q.finish>q.start and type(q.points)=='table','Invalid captured Curve note')
    count=count+#q.points;assert(count<=8192,'Too many captured Curve anchors')
    for _,p in ipairs(q.points)do assert(type(p.t)=='number' and p.t==p.t and type(p.value)=='number' and math.abs(p.value)<=24,'Invalid captured Curve anchor')end
  end
end
local enc12,dec12
local function tables()
  if enc12 then return end
  enc12,dec12={},{}
  for v=0,4095 do
    local hi,lo=v>>6,v&63
    local pair=chars:sub(hi+1,hi+1)..chars:sub(lo+1,lo+1)
    enc12[v]=pair;dec12[(pair:byte(1)<<8)|pair:byte(2)]=v
  end
end
-- fx_envelopes[p].points (тысячи {t,v,shape,tension}) в сохранённом состоянии — одна бинарная строка:
-- кодек тратил на таблицы основное время чтения/записи. Старые состояния с таблицами читаются как раньше.
local function pack_points(value)
  local fe=type(value)=='table' and value.fx_envelopes
  if type(fe)~='table' then return value end
  local out={};for k,v in pairs(value) do out[k]=v end
  local fx={}
  for p,e in pairs(fe) do
    if type(e)=='table' and type(e.points)=='table' then
      local rows={};for i,q in ipairs(e.points) do rows[i]=string.pack('<ddbd',q.t,q.v,q.shape or 0,q.tension or 0) end
      local c={};for k,v in pairs(e) do c[k]=v end;c.points=nil;c.packed=table.concat(rows);c.count=#rows;fx[p]=c
    else fx[p]=e end
  end
  out.fx_envelopes=fx;return out
end
local function unpack_points(value)
  local fe=type(value)=='table' and value.fx_envelopes
  if type(fe)~='table' then return value end
  for _,e in pairs(fe) do
    if type(e)=='table' and type(e.packed)=='string' then
      assert(#e.packed%25==0 and #e.packed/25<=2000000,'Invalid Pitch envelope data')
      local pts={};for at=1,#e.packed,25 do
        local t,v,shape,tension=string.unpack('<ddbd',e.packed,at);pts[#pts+1]={t=t,v=v,shape=shape,tension=tension}
      end
      e.points=pts;e.packed=nil;e.count=nil
    end
  end
  return value
end
function M.encode(data,job)
  tables()
  local s=Codec.encode(pack_points(data),job);local out={};local n=#s;local full=n-n%3
  for i=1,full,3 do
    local v=string.unpack('>I3',s,i)
    out[#out+1]=enc12[v>>12]..enc12[v&4095]
    if job and i%3072==1 then job:checkpoint() end
  end
  local rest=n-full
  if rest==1 then local a=s:byte(full+1)<<16;out[#out+1]=enc12[a>>12]:sub(1,2)..'=='
  elseif rest==2 then local a,b=s:byte(full+1,full+2);local v=(a<<16)|(b<<8);out[#out+1]=enc12[v>>12]..enc12[(v&4095)]:sub(1,1)..'=' end
  return table.concat(out)
end
function M.decode(s)
  assert(#s<=8*1024*1024 and #s%4==0 and not s:find('[^%w+/=]'),'Invalid Pitch project data')
  tables()
  local out={};local n=#s;local last=n>=4 and n-3 or n+1
  for i=1,last-1,4 do
    local v1=dec12[string.unpack('>I2',s,i)];local v2=dec12[string.unpack('>I2',s,i+2)]
    assert(v1 and v2,'Invalid Pitch encoding')
    out[#out+1]=string.pack('>I3',(v1<<12)|v2)
  end
  if n>=4 then
    local a,b,c,d=s:byte(n-3,n)
    local map=M._map;if not map then map={};for i=1,#chars do map[chars:byte(i)]=i-1 end;M._map=map end
    assert(map[a] and map[b],'Invalid Pitch encoding')
    assert((map[c] or (c==61 and d==61)) and (map[d] or d==61),'Invalid Pitch padding')
    local v=(map[a]<<18)|(map[b]<<12)|((map[c] or 0)<<6)|(map[d] or 0)
    out[#out+1]=string.char((v>>16)&255)..(c~=61 and string.char((v>>8)&255) or '')..(d~=61 and string.char(v&255) or '')
  end
  return unpack_points(Codec.decode(table.concat(out)))
end
function M.hash(s)
  local h=2166136261;local n=#s;local full=n-n%8;local byte=string.byte
  for i=1,full,8 do
    local a,b,c,d,e,f,g,k=byte(s,i,i+7)
    h=((h~a)*16777619)&0xffffffff;h=((h~b)*16777619)&0xffffffff;h=((h~c)*16777619)&0xffffffff;h=((h~d)*16777619)&0xffffffff
    h=((h~e)*16777619)&0xffffffff;h=((h~f)*16777619)&0xffffffff;h=((h~g)*16777619)&0xffffffff;h=((h~k)*16777619)&0xffffffff
  end
  for i=full+1,n do h=((h~byte(s,i))*16777619)&0xffffffff end
  return string.format('%08x',h)
end
function M.raw(r,take)
  local ok,text=r.GetSetMediaItemTakeInfo_String(take,M.key,'',false)
  if not ok then return '' end
  return text or ''
end
function M.read(r,take)
  local ok,text=r.GetSetMediaItemTakeInfo_String(take,M.key,'',false)
  if not ok or text=='' then return nil,text or '' end
  local value=M.decode(text);assert(value.version==1 and type(value.notes)=='table','Unsupported Pitch state')
  assert(#value.notes<10000 and type(value.geometry)=='table','Invalid Pitch state')
  for _,n in ipairs(value.notes) do
    assert(type(n.start)=='number' and type(n.finish)=='number' and n.finish>=n.start and type(n.center)=='number'
      and math.abs(n.shift or 0)<=24 and math.abs(n.formant or 0)<=24 and #(n.anchors or {})<10000,'Invalid Pitch note')
  end
  assert(value.curve_version==nil or value.curve_version==1 or value.curve_version==2 or value.curve_version==3 or value.curve_version==4,'Unsupported correction version')
  if value.algorithm~=nil then assert(type(value.algorithm)=='number' and value.algorithm%1==0 and value.algorithm>=0 and value.algorithm<=0xffffffff,'Invalid Pitch algorithm') end
  if value.auto~=nil then assert(type(value.auto)=='table' and (value.auto.mode==nil or value.auto.mode=='key' or value.auto.mode=='reference'),'Invalid Pitch auto') end
  if value.scale then assert(type(value.scale)=='table' and value.scale.root>=0 and value.scale.root<=11 and value.scale.mode>=1 and value.scale.mode<=14,'Invalid Pitch scale') end
  local limits={visual_offset={-150,150},modulation={0,2},drift={0,2},flatten={0,1},flat_offset={-48,48},vibrato_depth={0,2},vibrato_rate={.5,12},vibrato_onset={0,1},vibrato_release={.005,1},vibrato_growth={-1,1},transition_amount={0,1},transition_shape={.25,4},transition_bias={-.75,.75}}
  for _,n in ipairs(value.notes) do
    for key,range in pairs(limits) do if n[key]~=nil then assert(type(n[key])=='number' and n[key]>=range[1] and n[key]<=range[2],'Invalid Pitch expression: '..key) end end
    assert(n.expression_version==nil or n.expression_version==2,'Invalid Pitch expression version')
    if n.split_group then assert(type(n.split_group)=='number' and n.split_group>=1 and n.split_group%1==0,'Invalid Pitch split group') end
    if n.transition_link~=nil then assert(type(n.transition_link)=='boolean','Invalid Pitch transition link') end
    if n.local_center~=nil then assert(type(n.local_center)=='boolean','Invalid Pitch local center') end
    if n.vibrato_replace~=nil then assert(type(n.vibrato_replace)=='boolean','Invalid vibrato mode') end
    if n.link then
      assert(value.curve_version==4 and type(n.link)=='table' and (n.link.version==1 or n.link.version==2 or n.link.version==3 or n.link.version==4 or n.link.version==5 or n.link.version==6 or n.link.version==7),'Invalid Pitch link version')
      assert(n.link.owner==nil or type(n.link.owner)=='number' and n.link.owner>=1 and n.link.owner%1==0,'Invalid Pitch link owner')
      local link_limits={bias={-.75,.75},shape={.25,4},mix={0,1},settle={0,1},overshoot={-2,2}}
      if n.link.version>=4 then link_limits={width={.02,.4},amount={0,1}}elseif n.link.version==1 then link_limits.width={.005,.3}else link_limits.scale={.25,2}end
      if n.link.version>=5 then validate_capture(n.link.curve_notes)end
      for key,range in pairs(link_limits)do
        local v=n.link[key];assert(type(v)=='number' and v>=range[1] and v<=range[2],'Invalid Pitch link: '..key)
      end
    end
    if n.drawings then
      assert(type(n.drawings)=='table' and #n.drawings<=64,'Too many pitch drawings')
      for _,s in ipairs(n.drawings) do
        if s.target~=nil then assert(value.curve_version==4 and s.target==true and type(s.id)=='number' and s.id>=1,'Invalid target drawing') end
        if s.support_version~=nil then assert(s.target and (s.support_version==2 or s.support_version==3),'Invalid Draw support version') end
        assert(type(s.start)=='number' and type(s.finish)=='number' and s.finish>s.start and type(s.points)=='table' and #s.points>=2 and #s.points<=2048,'Invalid pitch drawing')
        local previous=-math.huge
        for _,p in ipairs(s.points) do assert(type(p.t)=='number' and p.t>previous and p.t>=s.start and p.t<=s.finish and type(p.value)=='number' and math.abs(p.value)<=200,'Invalid drawing point');previous=p.t end
        assert(s.curve==nil or type(s.curve)=='table' and #s.curve<=8192,'Too many captured Curve points')
        if s.curve_linear~=nil then assert(s.curve_linear==true and s.target,'Invalid captured Curve interpolation') end
        for _,p in ipairs(s.curve or {})do assert(type(p.t)=='number' and p.t==p.t and type(p.value)=='number' and math.abs(p.value)<=24,'Invalid captured Curve point') end
        if s.curve_notes then
          assert(s.target,'Invalid captured Curve notes');validate_capture(s.curve_notes)
        end
      end
    end
    for _,p in ipairs(n.anchors or {}) do assert(type(p.t)=='number' and p.t==p.t and type(p.value)=='number' and math.abs(p.value)<=24,'Invalid Pitch anchor') end
    if n.target_anchors then assert(value.curve_version==4 and #n.target_anchors<10000,'Invalid target anchors') end
    for _,p in ipairs(n.target_anchors or {})do assert(type(p.t)=='number' and p.t==p.t and type(p.value)=='number' and math.abs(p.value)<=24,'Invalid target anchor') end
  end
  return value,text
end
function M.write(r,take,value)
  local text=value and M.encode(value) or ''
  local ok=r.GetSetMediaItemTakeInfo_String(take,M.key,text,true)
  -- REAPER может вернуть false при очистке ключа пустой строкой: проверяем по факту, что значение пропало
  if not ok and value==nil then local _,now=r.GetSetMediaItemTakeInfo_String(take,M.key,'',false);ok=now=='' or now==nil end
  assert(ok,'Could not save Pitch item state')
  return text
end
function M.geometry(s)
  return {render_key=s.render_key,source_key=s.source_key,offset=s.offset,len=s.len,rate=s.rate,guid=s.guid}
end
function M.save_analysis(r,s,data,job)
  local rows={}
  for i,f in ipairs(data.frames) do
    rows[i]=string.pack('<fffff',f.pitch,f.confidence,f.level_db,f.lo or 0,f.hi or 0)
    if job and i%256==0 then job:checkpoint() end
  end
  local key=s.pitch_key..'|'..data.model
  local packed=M.encode({version=1,key=key,geometry=M.geometry(s),hop=data.hop,len=data.len,model=data.model,frames=table.concat(rows),waveform=Wave.pack(data.waveform,job)},job)
  -- Immutable by content, so project Undo may leave an unused analysis, never
  -- overwrite the one referenced by another item or an earlier edit state.
  local id=M.hash(key)..'-'..M.hash(packed)
  local write=function()assert(r.SetProjExtState(s.project,M.section,id,packed)>0,'Could not save Pitch analysis') end
  if job then job:call(write) else write() end
  return id
end
function M.load_analysis(r,project,id)
  if not id then return nil end
  local ok,text=r.GetProjExtState(project,M.section,id);if ok==0 or text=='' then return nil end
  local v=M.decode(text);assert(v.version==1 and type(v.frames)=='string' and #v.frames%20==0,'Invalid Pitch analysis')
  assert(#v.frames/20<=40000 and v.hop==.016,'Unsupported Pitch analysis')
  local data={frames={},hop=v.hop,len=v.len,model=v.model,waveform=Wave.unpack(v.waveform,v.len)}
  for at=1,#v.frames,20 do
    local p,c,db,lo,hi=string.unpack('<fffff',v.frames,at)
    assert(p==p and p>=0 and p<=150 and c>=0 and c<=1 and db>=-160 and db<=60 and math.abs(lo)<1e6 and math.abs(hi)<1e6,'Invalid Pitch frame')
    data.frames[#data.frames+1]={t=(#data.frames)*data.hop,pitch=p,hz=440*2^((p-69)/12),confidence=c,level_db=db,rms=10^(db/20),lo=lo,hi=hi}
  end
  return data,v.geometry
end
function M.adapt(data,notes,old,current)
  if old.render_key~=current.render_key or old.source_key~=current.source_key then return nil,'Audio processing changed; analyze again.' end
  local delta=(current.offset-old.offset)/current.rate
  if delta<-.00001 or delta+current.len>old.len+.00001 then return nil,'The item exposes audio outside the saved analysis; analyze again.' end
  local out={frames={},hop=data.hop,len=current.len,model=data.model,_source=data,_offset=delta}
  for _,f in ipairs(data.frames) do if f.t>=delta-data.hop*.5 and f.t<delta+current.len then local v=Notes.copy(f);v.t=math.max(0,f.t-delta);out.frames[#out.frames+1]=v end end
  local adapted={}
  for _,n in ipairs(notes) do if n.finish>delta and n.start<delta+current.len then
    local v=Notes.copy(n);v.start=math.max(0,n.start-delta);v.finish=math.min(current.len,n.finish-delta)
    for _,p in ipairs(v.anchors or {}) do p.t=p.t-delta end
    for _,p in ipairs(v.target_anchors or {})do p.t=p.t-delta end
    for _,q in ipairs(v.link and v.link.curve_notes or {})do q.start=q.start-delta;q.finish=q.finish-delta;for _,p in ipairs(q.points)do p.t=p.t-delta end end
    for _,s in ipairs(v.drawings or {}) do s.start=s.start-delta;s.finish=s.finish-delta;for _,p in ipairs(s.points) do p.t=p.t-delta end;for _,p in ipairs(s.curve or {})do p.t=p.t-delta end end
    for _,s in ipairs(v.drawings or {})do for _,q in ipairs(s.curve_notes or {})do q.start=q.start-delta;q.finish=q.finish-delta;for _,p in ipairs(q.points)do p.t=p.t-delta end end end
    for _,key in ipairs({'phase_origin','expression_start','expression_finish'}) do if v[key] then v[key]=v[key]-delta end end
    v.first=math.max(1,math.floor(v.start/data.hop)+1);v.last=math.min(#out.frames,math.ceil(v.finish/data.hop))
    adapted[#adapted+1]=v
  end end
  return out,adapted
end
return M
