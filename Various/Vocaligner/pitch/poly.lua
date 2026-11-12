-- @noindex
-- Polyphonic (song) analysis: полифонические ноты (только для показа/подсветки, не для правки и не для ATune),
-- аккорды, тональность и темп. Всё считает C++ (reaper_vocaligner_native: VN_Poly*); здесь — чтение айтема порциями
-- в DLL, задача, хранение результата и подпись звука. Запись хранится на тейке (P_EXT, в .rpp) или только в памяти
-- сессии — Settings → «Polyphonic analysis: store in the project». Время в записи — секунды от начала айтема.
local import=...;local Store=import('pitch/store');local Audio=import('audio');local M={}
M.KEY='P_EXT:VocalignerPoly1';M.FLAG='P_EXT:VocalignerPoly1f'
M.VERSION=2 -- tonal peak assignment / percussion rejection; old results require reanalysis
M.NAMES={'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'}
M.QUALITY={'','m','7','maj7','m7','dim','aug','sus4','sus2'} -- порядок = poly.hpp qualities()
-- Полные названия для показа (в тональности C: Cmaj, Amin, G7, Cmaj7, Amin7 …): мажор/минор не прячутся за пустым суффиксом
M.QUALITY_LONG={'maj','min','7','maj7','min7','dim','aug','sus4','sus2'}
M.TONES={{0,4,7},{0,3,7},{0,4,7,10},{0,4,7,11},{0,3,7,10},{0,3,6},{0,4,8},{0,5,7},{0,2,7}}
local API={'VN_PolyVersion','VN_PolyCreate','VN_PolyAppend','VN_PolySeal','VN_PolyPoll','VN_PolyError','VN_PolyRelease','VN_PolyInfo','VN_PolyNotes','VN_PolyChords','VN_PolyBeats'}
local checked
function M.available(r)
  if checked then return checked[1],checked[2] end
  for _,name in ipairs(API) do if type(r[name])~='function' then checked={false,'Polyphonic analysis needs the "Vocaligner Native" extension (ReaPack). Install it and restart REAPER.'};return false,checked[2] end end
  local ok,v=pcall(r.VN_PolyVersion);if not ok or v~=2 then checked={false,'Polyphonic analysis: extension version mismatch. Update "Vocaligner Native" and restart REAPER.'} else checked={true} end
  return checked[1],checked[2]
end
function M.store_in_project(r)return r.GetExtState('Vocaligner ui','poly_store')~='0' end
function M.set_store_in_project(r,on)r.SetExtState('Vocaligner ui','poly_store',on and '1' or '0',true)end
local session={} -- RAM: GUID тейка -> запись (когда в проект не пишем)
local function signature(s) return table.concat({tostring(s.render_key),string.format('%.9f|%.9f|%.9f',s.offset or 0,s.len or 0,s.rate or 1)},'|') end
M.signature=signature

function M.chord_name(c,short)
  if not c.root or c.root<0 then return 'N.C.' end
  local name=M.NAMES[c.root+1]..((short and M.QUALITY or M.QUALITY_LONG)[(c.quality or 0)+1] or '')
  if c.bass and c.bass>=0 then name=name..'/'..M.NAMES[c.bass+1] end
  return name
end
function M.key_name(k) if not k or k.root<0 then return 'unknown' end;return M.NAMES[k.root+1]..(k.mode==1 and ' minor' or ' major') end
-- тональность записи как (root, scale id pitch/scale.lua): мажор = 2 (Major), минор = 3 (Minor)
function M.key_scale(k) if not k or k.root<0 then return nil end;return k.root,k.mode==1 and 3 or 2 end

-- ---- хранение: компактная запись (ноты и доли — бинарные строки)
local function pack(rec)
  local notes={};for i,n in ipairs(rec.notes) do notes[i]=string.pack('<ffBBB',n.s,n.e,n.p,math.floor(n.c*255+.5),math.floor(n.v+.5)) end
  local beats={};for i,t in ipairs(rec.beats) do beats[i]=string.pack('<f',t) end
  local chords={};for i,c in ipairs(rec.chords) do chords[i]={c.s,c.e,c.root,c.quality,c.bass,c.c} end
  return {version=M.VERSION,sig=rec.sig,len=rec.len,bpm=rec.bpm,bpm_conf=rec.bpm_conf,bpm_alt=rec.bpm_alt,tuning=rec.tuning,keys=rec.keys,
    chords=chords,notes=table.concat(notes),beats=table.concat(beats),stats=rec.stats}
end
local function unpack_rec(v)
  if type(v)~='table' or v.version~=M.VERSION or type(v.notes)~='string' or #v.notes%11~=0 or type(v.beats)~='string' or #v.beats%4~=0 then return nil end
  local rec={sig=v.sig,len=v.len,bpm=v.bpm,bpm_conf=v.bpm_conf,bpm_alt=v.bpm_alt or {},tuning=v.tuning,keys=v.keys or {},stats=v.stats,notes={},chords={},beats={}}
  for at=1,#v.notes,11 do local s,e,p,c,vel=string.unpack('<ffBBB',v.notes,at);rec.notes[#rec.notes+1]={s=s,e=e,p=p,c=c/255,v=vel} end
  for at=1,#v.beats,4 do rec.beats[#rec.beats+1]=(string.unpack('<f',v.beats,at)) end
  for i,c in ipairs(v.chords or {}) do rec.chords[i]={s=c[1],e=c[2],root=c[3],quality=c[4],bass=c[5],c=c[6]} end
  return rec
end
local function guid(r,take) local _,g=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false);return g end
function M.has(r,take)
  if not take then return false end
  local ok,f=r.GetSetMediaItemTakeInfo_String(take,M.FLAG,'',false)
  return (ok and f=='1') or session[guid(r,take)]~=nil
end
-- запись тейка, если она про тот же звук (s — снимок Audio.state/capture); иначе nil — нужен (ре)анализ
function M.load(r,take,s)
  if not take then return nil end
  local rec=session[guid(r,take)]
  if not rec then
    local ok,text=r.GetSetMediaItemTakeInfo_String(take,M.KEY,'',false)
    if ok and text~='' then local good,v=pcall(Store.decode,text);if good then rec=unpack_rec(v) end end
  end
  if rec and s and rec.sig~=signature(s) then return nil,'changed' end
  return rec
end
function M.save(r,take,rec)
  if M.store_in_project(r) then
    Store.put_take(r,take,M.KEY,pack(rec));r.GetSetMediaItemTakeInfo_String(take,M.FLAG,'1',true)
    session[guid(r,take)]=nil
  else session[guid(r,take)]=rec end
end

-- забыть Polyphonic-анализ тейка (и в проекте, и в памяти сессии)
function M.clear(r,take)
  session[guid(r,take)]=nil
  r.GetSetMediaItemTakeInfo_String(take,M.KEY,'',true);r.GetSetMediaItemTakeInfo_String(take,M.FLAG,'',true)
end

-- ---- анализ одного айтема: accessor порциями -> DLL; тот же разбор play rate, что у Align
local Handle={};Handle.__index=Handle
Handle.__gc=function(h)if not h.released then h.released=true;pcall(h.r.VN_PolyRelease,h.id)end end
function Handle:release()if not self.released then self.released=true;self.r.VN_PolyRelease(self.id)end end
-- range (необязательно) — {a,b} в секундах проекта: только этот кусок айтема (темп по фрагменту); запись не сохраняется
function M.analyze_item(r,project,item,job,label,range)
  local s=Audio.state(r,project,item)
  s.channels=r.GetMediaSourceNumChannels(s.source)
  if s.len<.1 or s.rate<=0 then error('The item is too short to analyze: '..s.name,0) end
  if not s.channels or s.channels<1 or s.channels>8 then error('Supported sources have 1 to 8 audio channels: '..s.name,0) end
  local aa=r.CreateTakeAudioAccessor(s.take);if not aa then error('Cannot read '..s.name,0) end
  job.resources[aa]=r.DestroyAudioAccessor
  local SR=22050;local scale=1
  local a0,a1=r.GetAudioAccessorStartTime(aa),r.GetAudioAccessorEndTime(aa)
  if math.abs(a0)>1e-4 then error('Unexpected take accessor time origin: '..s.name,0) end
  if math.abs(s.rate-1)>1e-6 and math.abs(a1-s.len*s.rate)<1e-4 and math.abs(a1-s.len)>1e-4 then scale=s.rate end
  local read_rate=math.floor(SR/scale+.5);local sr=read_rate*scale
  local t0,t1=0,s.len
  if range then t0=math.max(0,range[1]-s.pos);t1=math.min(s.len,range[2]-s.pos);if t1-t0<3 then error('Select at least 3 seconds of the item to detect its tempo',0) end end
  local total=math.ceil((t1-t0)*sr);local ch=s.channels;local block=math.min(65536,math.floor(131072/ch))
  local h=job:call(function()
    local id=r.VN_PolyCreate(r.new_array({22050,ch,total}));if not id or id<=0 then error(r.VN_PolyError(0),0) end
    return setmetatable({r=r,id=id},Handle)
  end)
  job.resources[h]=Handle.release
  local buffer=job:call(r.new_array,block*ch)
  for at=0,total-1,block do
    local count=math.min(block,total-at)
    job:call(function()
      buffer.clear()
      local st=r.GetAudioAccessorSamples(aa,read_rate,ch,(t0+at/sr)*scale,count,buffer)
      if type(st)=='number' and st<0 then error('Audio read failed for '..s.name,0) end
      if r.VN_PolyAppend(h.id,buffer,count)~=1 then error(tostring(r.VN_PolyError(0))..' ('..s.name..')',0) end
    end)
    job:checkpoint(at/total*.6,label)
  end
  job.resources[aa]=nil;r.DestroyAudioAccessor(aa)
  job:call(function()if r.VN_PolySeal(h.id)~=1 then error(r.VN_PolyError(0),0) end end)
  while true do
    local st=r.VN_PolyPoll(h.id)
    if st==-1 then error(tostring(r.VN_PolyError(h.id)),0) end
    if st==1 then break end
    job:checkpoint(.65,label);coroutine.yield()
  end
  local rec=job:call(function()
    local a=r.new_array(19);assert(r.VN_PolyInfo(h.id,a)==19,'Polyphonic result is not ready');local v=a.table()
    local rec={sig=signature(s),len=s.len,bpm=v[4],bpm_conf=v[5],tuning=v[6],keys={},bpm_alt={},notes={},chords={},beats={},
      stats={ms=v[7],frames=v[8],seconds=s.len}}
    for k=0,2 do if v[9+3*k]>=0 then rec.keys[#rec.keys+1]={root=math.tointeger(v[9+3*k]),mode=math.tointeger(v[10+3*k]),score=v[11+3*k]} end end
    for k=18,19 do if v[k]>0 then rec.bpm_alt[#rec.bpm_alt+1]=v[k] end end
    local function rows(fn,n,width,make)
      local buf=r.new_array(math.max(1,math.min(n,8192))*width)
      for first=0,n-1,8192 do local got=fn(h.id,first,buf);local x=buf.table(1,got*width);for k=0,got-1 do make(x,k*width) end end
    end
    rows(r.VN_PolyNotes,math.tointeger(v[1]),5,function(x,b) rec.notes[#rec.notes+1]={s=x[b+1],e=x[b+2],p=math.tointeger(x[b+3]),c=x[b+4],v=x[b+5]} end)
    rows(r.VN_PolyChords,math.tointeger(v[2]),6,function(x,b) rec.chords[#rec.chords+1]={s=x[b+1],e=x[b+2],root=math.tointeger(x[b+3]),quality=math.tointeger(x[b+4]),bass=math.tointeger(x[b+5]),c=x[b+6]} end)
    rows(r.VN_PolyBeats,math.tointeger(v[3]),1,function(x,b) rec.beats[#rec.beats+1]=x[b+1] end)
    return rec
  end)
  job.resources[h]=nil;h:release()
  return rec,s
end
-- Пачка: выбранные айтемы по очереди (каждый — свой анализ в пуле DLL); результат сохраняется сразу
function M.start(e,items)
  local ok,why=M.available(e.r);if not ok then e:fail(why);return end
  if e:busy() or e.gesture then return end
  if not items or #items==0 then e:fail('Select audio items to analyze.');return end
  local r=e.r;local project=r.EnumProjects(-1)
  e.error=nil
  e.job=import('job').new(r,function(job)
    local done,failed=0,0
    for i,item in ipairs(items) do
      local label=string.format('Polyphonic %d / %d',i,#items)
      local good,rec_or,s=pcall(M.analyze_item,r,project,item,job:scope((i-1)/#items,i/#items),label)
      if good then
        job:call(M.save,r,s.take,rec_or);done=done+1
        if item==e.item then e.poly=rec_or;e:apply_detected_key(rec_or) end
      else failed=failed+1;e.app:report('Polyphonic: '..tostring(rec_or)) end
    end
    e.message=string.format('Polyphonic: analyzed %d / %d items%s',done,#items,failed>0 and ('; '..failed..' failed — Copy report') or '')
  end,.012)
  e.job.kind='analysis'
end
return M
