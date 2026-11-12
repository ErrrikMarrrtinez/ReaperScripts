-- @noindex
-- DeClick на C++ (reaper_vocaligner_native: VN_Declick*). Тот же расчёт, что EEL/Lua в click/engine.lua,
-- click/detector.lua и click/repair.lua (бит в бит, см. native/test_declick.py), но признаки идут потоком,
-- обнаружение — кусками в пуле потоков, восстановление независимых участков — пачкой в пуле.
-- Нет расширения / другая версия / не прошёл самотест / ExtState 'Vocaligner declick','native'='0' -> nil,
-- и вызывающий код идёт прежним путём EEL/Lua.
local M={VERSION=1}
local API={'VN_DeclickVersion','VN_DeclickSelfTest','VN_DeclickCreate','VN_DeclickAppend','VN_DeclickSeal','VN_DeclickPoll',
  'VN_DeclickInfo','VN_DeclickError','VN_DeclickRelease','VN_DeclickRows','VN_DeclickPeaks','VN_DeclickScore','VN_DeclickEvents',
  'VN_DeclickMouth','VN_DeclickEventRows','VN_DeclickPredict','VN_DeclickBatch','VN_DeclickBatchAdd','VN_DeclickBatchRead'}
-- Чтение WAV в C++ (declick_io.hpp): разбор файла, декодирование, пики обзора, отсчёты по требованию, проверка исходника.
-- Нужны все функции и их самотест; нет — признаки по-прежнему идут в C++, а файл читает Lua (click/wave.lua).
local IO_API={'VN_DeclickIOVersion','VN_DeclickIOSelfTest','VN_DeclickSrcOpen','VN_DeclickSrcEdits','VN_DeclickSrcAnalyze',
  'VN_DeclickViewPeaks','VN_DeclickRead','VN_DeclickSrcVerify','VN_DeclickIOStats'}
M.IO_VERSION=1
local cache=setmetatable({},{__mode='k'}) -- r -> {native}|false
M.reason=nil
function M.get(r)
  if type(r)~='table' then return nil end
  -- функции расширения живут в глобальной таблице reaper; подменённый r (офлайн-хосты) их может не иметь
  if type(r.VN_DeclickVersion)~='function' and type(reaper)=='table' and type(reaper.VN_DeclickVersion)=='function' then r=reaper end
  local c=cache[r];if c~=nil then return c or nil end
  local ok=pcall(function()
    for _,name in ipairs(API) do assert(type(r[name])=='function') end
    if type(r.GetExtState)=='function' and r.GetExtState('Vocaligner declick','native')=='0' then error('disabled') end
    assert(r.VN_DeclickVersion()==M.VERSION and r.VN_DeclickSelfTest()==1)
  end)
  local io=false
  if ok then
    io=pcall(function()
      for _,name in ipairs(IO_API) do assert(type(r[name])=='function') end
      -- ExtState 'Vocaligner declick','nativeio'='0' выключает только чтение файла в C++ (для сравнения путей)
      if type(r.GetExtState)=='function' and r.GetExtState('Vocaligner declick','nativeio')=='0' then error('disabled') end
      assert(r.VN_DeclickIOVersion()==M.IO_VERSION and r.VN_DeclickIOSelfTest()==1)
    end)
  end
  c=ok and setmetatable({r=r,io=io},{__index=M}) or false
  if not ok then M.reason='C++ DeClick unavailable (extension missing, old or disabled); using EEL/Lua' end
  cache[r]=c;return c or nil
end
-- Ручка C++: освобождается явно или сборщиком мусора (Release не ждёт рабочих).
local Handle={};Handle.__index=Handle
Handle.__gc=function(h) if not h.released then h.released=true;pcall(h.r.VN_DeclickRelease,h.id) end end
function Handle:release() if not self.released then self.released=true;self.r.VN_DeclickRelease(self.id) end end
local function handle(r,id,what)
  if not id or id<=0 then error((what or 'Native DeClick')..': '..tostring(r.VN_DeclickError(0)),0) end
  return setmetatable({r=r,id=id},Handle)
end
-- Ждать, не блокируя REAPER: внутри задачи (корутина) — уступаем кадр; вне её (офлайн-тесты) — просто опрашиваем.
local function idle(job,progress,label)
  if coroutine.isyieldable() then
    if job and job.checkpoint then job:checkpoint(progress,label) end
    coroutine.yield()
  end
end
function M:wait(job,h,progress,label,plain)
  local r=self.r
  while true do
    local st=r.VN_DeclickPoll(h.id)
    if st==1 then return end
    if st~=0 then error((plain and '' or 'Native DeClick: ')..tostring(r.VN_DeclickError(h.id)),0) end
    local p=progress and progress[1]
    if progress then
      local a=r.new_array(3);local n=r.VN_DeclickInfo(h.id,a)
      if n>=3 then local v=a.table();if v[3]>0 then p=progress[1]+(progress[2]-progress[1])*math.min(1,v[2]/v[3]) end end
    end
    idle(job,p,label)
  end
end
local function own(job,h) if job and job.resources then job.resources[h]=Handle.release end end
local function disown(job,h) if job and job.resources then job.resources[h]=nil end end

-- ---- признаки: поток PCM-блоков (pcm.blocks[i].buffer — reaper.array) в C++, пока Lua читает файл
function M:coefficients(engine,sr)
  -- коэффициенты фильтров признаков считает сам EEL-движок (тот же exp, что у EEL-пути), без него — Lua
  if engine and engine.coefficients then local ok,al,am=pcall(engine.coefficients,engine,sr);if ok and al and am then return al,am end end
  return 1-math.exp(-2*math.pi*700/sr),1-math.exp(-2*math.pi*4000/sr)
end
local Stream={};Stream.__index=Stream
function M:stream(engine,pcm,job)
  local r=self.r;local hop=math.max(1,math.floor(pcm.sr*.00025+.5))
  local frames=pcm.frames;if not frames then frames=0;for _,b in ipairs(pcm.blocks) do frames=frames+b.count end end
  local al,am=self:coefficients(engine,pcm.sr)
  local h=handle(r,r.VN_DeclickCreate(r.new_array({pcm.sr,pcm.channels,frames,al,am,hop})),'DeClick analysis')
  own(job,h)
  return setmetatable({native=self,h=h,hop=hop,frames=frames,pushed=0,job=job},Stream)
end
function Stream:push(b)
  local r=self.native.r
  local st=r.VN_DeclickAppend(self.h.id,b.buffer,b.count)
  if st==0 then error('Native DeClick: '..tostring(r.VN_DeclickError(0)),0) end
  self.pushed=self.pushed+b.count
  if st==2 then idle(self.job) end -- очередь C++ длинная: дать рабочему потоку догнать
end
-- Все блоки отданы -> ждать признаки. Возвращает data для detector.lua (строки остаются в C++).
function Stream:finish(pcm,job)
  local r=self.native.r
  if r.VN_DeclickSeal(self.h.id)~=1 then error('Native DeClick: '..tostring(r.VN_DeclickError(self.h.id)),0) end
  self.native:wait(job,self.h,{.9,1},'Analyzing click transients')
  local a=r.new_array(11);r.VN_DeclickInfo(self.h.id,a);local v=a.table()
  disown(job,self.h)
  return M.data(self.native,self.h,math.tointeger(v[2]) or math.floor(v[2]),self.hop,pcm)
end
-- data совместима с прежней: data.rows (таблицы по 8 значений) строится лениво, только если её кто-то попросит
-- (прежние пути: спектральный Mouth, отладка); основные пути читают строки прямо в C++.
function M.data(native,h,frames,hop,pcm)
  local data={version=1,hop=hop/pcm.sr,len=pcm.len,sr=pcm.sr,frames=frames,native=native,handle=h}
  return setmetatable(data,{__index=function(t,k)
    if k~='rows' then return nil end
    local rows=native:rows(t);rawset(t,'rows',rows);return rows
  end})
end
function M:rows(data)
  local r=self.r;local rows={};local per=8192;local buf=r.new_array(per*8)
  for first=0,data.frames-1,per do
    local n=r.VN_DeclickRows(data.handle.id,first,buf);local v=buf.table(1,n*8)
    for i=0,n-1 do local o=i*8;rows[#rows+1]={v[o+1],v[o+2],v[o+3],v[o+4],v[o+5],v[o+6],v[o+7],v[o+8]/data.sr} end
  end
  return rows
end
-- Пики (колонка 7) диапазонов кадров для обзора волны: pairs = {a1,b1,a2,b2,...} (1-based, включительно)
function M:peaks(data,pairs)
  local r=self.r;if #pairs==0 then return {} end
  local io=r.new_array(pairs);local n=r.VN_DeclickPeaks(data.handle.id,io);return io.table(1,n)
end

-- ---- файл в C++: открыть WAV, поток «файл -> признаки», пики обзора, отсчёты по требованию, проверка исходника
-- Lua не держит PCM: всё читается из файла в рабочих потоках, а нужные куски (зум, контекст восстановления) — по запросу.
-- Открыть. nil — API нет, файл не открылся или не разобрался: вызывающий код идёт прежним Lua-чтением (оно же даст
-- прежний текст ошибки). Ручка источника нужна только до Analyze: дальше файл держит ручка признаков.
function M:open(path,job)
  if not self.io then return nil end
  local r=self.r
  local ok,id=pcall(r.VN_DeclickSrcOpen,path)
  if not ok or not id or id<=0 then return nil end
  local h=setmetatable({r=r,id=id},Handle);own(job,h)
  local a=r.new_array(9);local n=r.VN_DeclickInfo(id,a);local v=a.table(1,9)
  if n<9 then h:release();disown(job,h);return nil end
  return {h=h,format=v[2],channels=math.tointeger(v[3]) or math.floor(v[3]),sr=math.tointeger(v[4]) or math.floor(v[4]),bits=v[5],
    frames=math.tointeger(v[6]) or math.floor(v[6]),path=path,native=self}
end
-- edits: плоский список {канал, кадр файла, значение, ...}; first/count — окно анализа в кадрах файла.
-- Возвращает ручку признаков (обычную: Rows/Score/Mouth/... работают с ней) и hop. Чтение и пики уже идут в пуле.
function M:analyze_source(engine,src,first,count,edits,job)
  local r=self.r
  if edits and #edits>0 then
    local n=r.VN_DeclickSrcEdits(src.h.id,r.new_array(edits))
    if not n or n<=0 then error('Native DeClick: '..tostring(r.VN_DeclickError(0)),0) end
  end
  local hop=math.max(1,math.floor(src.sr*.00025+.5));local al,am=self:coefficients(engine,src.sr)
  local h=handle(r,r.VN_DeclickSrcAnalyze(src.h.id,r.new_array({first,count,al,am,hop})),'DeClick analysis')
  own(job,h);h.channels=src.channels;h.native=self
  src.h:release();disown(job,src.h) -- файл дальше держит ручка признаков
  return h,hop
end
-- Ждать признаки (прогресс — по готовым строкам); data — как у Stream:finish.
function M:finish_source(job,h,hop,pcm)
  local r=self.r
  self:wait(job,h,{0,1},'Reading and analyzing click transients')
  local a=r.new_array(11);r.VN_DeclickInfo(h.id,a);local v=a.table(1,11)
  disown(job,h)
  return M.data(self,h,math.tointeger(v[2]) or math.floor(v[2]),hop,pcm)
end
-- Сводка по чтению/пикам: {status, chunks_done, chunks, peak, fed_frames}; status: 0 идёт, 1 готово, -1 ошибка.
function M:source_info(h)
  local r=self.r;local a=r.new_array(18);local n=r.VN_DeclickInfo(h.id,a);if n<15 then return nil end
  local v=a.table(1,18);return {status=v[12],done=v[13],chunks=v[14],peak=v[15],fed=v[16]}
end
-- Столбцы обзора: пары {min,max} моно-суммы для w столбцов по spp кадров, начиная с кадра base (окно анализа).
-- Возвращает плоскую таблицу из 2w чисел (пустой столбец: min>max) или nil.
function M:view_peaks(h,base,spp,w)
  local r=self.r;w=math.floor(w);if w<1 then return nil end
  local io=r.new_array(math.max(3,2*w));io[1]=base;io[2]=spp;io[3]=w
  local n=r.VN_DeclickViewPeaks(h.id,io);if not n or n<=0 then return nil end
  return io.table(1,2*w)
end
-- Отсчёты окна анализа с правками SAMPLEEDITS. mode: -2 interleaved (count*channels), -1 моно-сумма, >=0 один канал.
function M:read(h,first,count,mode)
  local r=self.r;local per=mode==-2 and (h.channels or 1) or 1
  local out=r.new_array(count*per);local n=r.VN_DeclickRead(h.id,first,count,mode,out)
  if not n or n<=0 then error('Native DeClick: '..tostring(r.VN_DeclickError(0)),0) end
  return out.table(1,count*per)
end
-- Проверка, что исходный файл не менялся с анализа (тексты ошибок — прежние: 'Source audio changed; analyze again' ...).
function M:verify(h,job)
  local r=self.r;local id=r.VN_DeclickSrcVerify(h.id)
  if not id or id<=0 then error(tostring(r.VN_DeclickError(0)),0) end
  local v=setmetatable({r=r,id=id},Handle);own(job,v)
  self:wait(job,v,{0,1},'Verifying source',true)
  disown(job,v);v:release()
end

-- ---- Click: оценки (контекст + защита повторов) и события
local function settings(h,mode,skew,protect)
  local span=math.max(4,math.floor((mode=='mouth' and .080 or .030)/h));local guard=math.max(2,math.floor((mode=='mouth' and .025 or .003)/h))
  local stride=math.max(1,math.floor(.001/h))
  local lo,hi=math.ceil(.0025/h),math.floor(.016/h);local valley=math.max(1,math.floor(.001/h))
  return {10^(-skew/10),mode=='mouth' and 1.6 or 1,10^(skew/10),protect,span,guard,stride,lo,hi,valley}
end
function M:score(data,mode,skew,protect,job)
  local r=self.r
  local h=handle(r,r.VN_DeclickScore(data.handle.id,r.new_array(settings(data.hop,mode,skew,protect))),'DeClick scores')
  own(job,h);self:wait(job,h,{0,.6},'Scoring click candidates');disown(job,h)
  return {native=self,handle=h,mode=mode,data=data}
end
local function event_rows(self,h)
  local r=self.r;local a=r.new_array(6);r.VN_DeclickInfo(h.id,a);local count=math.floor(a.table()[5])
  local out={};local per=4096;local buf=r.new_array(per*8)
  for first=0,count-1,per do
    local n=r.VN_DeclickEventRows(h.id,first,buf);local v=buf.table(1,n*8)
    for i=0,n-1 do local o=i*8;out[#out+1]={v[o+1],v[o+2],v[o+3],v[o+4],v[o+5],v[o+6],v[o+7],v[o+8]} end
  end
  return out
end
-- detector.lua M.events (mode 'click'); exclusions — как там: только своего вида
function M:events(scores,cfg,mode,exclusions,job)
  local r=self.r;local data=scores.data;local h=data.hop
  local threshold=14*2^(-cfg[mode..'_sensitivity']/35);local tail=math.max(1.6,threshold*.32)
  local gap=math.max(1,math.floor((mode=='mouth' and .002 or .0005)/h))
  local s={threshold,tail,gap,mode=='mouth' and .050 or .020,data.len,h,0}
  for _,x in ipairs(exclusions or {}) do if x.kind==mode then s[#s+1]=x.start;s[#s+1]=x.finish;s[7]=s[7]+1 end end
  local eh=handle(r,r.VN_DeclickEvents(scores.handle.id,r.new_array(s)),'DeClick events')
  own(job,eh);self:wait(job,eh,{.6,.8},'Locating click candidates');disown(job,eh)
  local events={}
  for _,v in ipairs(event_rows(self,eh)) do
    events[#events+1]={kind=mode,start=v[1],finish=v[2],peak=v[3]/data.sr,score=v[4],
      level_db=20*math.log(math.max(v[5],1e-12),10),contrast=v[6],excluded=v[7]~=0 or nil}
  end
  eh:release();return events
end
-- detector.lua mouth_candidates (метод 'transient'): кандидаты без исключений, доверие amount — здесь, как в Lua
local function smooth(x) x=math.max(0,math.min(1,x));return x*x*(3-2*x) end
function M:mouth(data,cfg,job)
  local r=self.r;local skew=cfg.mouth_skew or 0;local wh=math.max(0,math.min(1,.5+skew/20))
  local protect=cfg.mouth_protect or 0;local T=12*2^(-(cfg.mouth_sensitivity or 50)/30)
  local eh=handle(r,r.VN_DeclickMouth(data.handle.id,r.new_array({T,wh,protect,10^(-90/20),data.len,data.hop})),'Mouth detection')
  own(job,eh);self:wait(job,eh,{0,.6},'Mouth transient contrast');disown(job,eh)
  local events={}
  for _,v in ipairs(event_rows(self,eh)) do
    local score,protection=v[4],v[8]
    local amount=smooth((score/T-1)/2)*(1-math.max(0,math.min(1,protect/100))*protection)^2
    events[#events+1]={kind='mouth',start=v[1],finish=v[2],peak=v[3]/data.sr,score=score,
      level_db=20*math.log(math.max(v[5],1e-12),10),contrast=score,amount=amount,protection=protection}
  end
  eh:release();return events
end

-- ---- восстановление: одно предсказание синхронно; независимые участки — пачкой в пуле
local function pack(left,right,n,sr,safe,method)
  local t={#left,#right,n,sr or 0,safe and 1 or 0,method=='extrapolate' and 1 or 0}
  table.move(left,1,#left,7,t);table.move(right,1,#right,7+#left,t);return t
end
M.pack=pack
function M:predict(left,right,n,sr,safe,method)
  local r=self.r;local out=r.new_array(n)
  local st=r.VN_DeclickPredict(r.new_array(pack(left,right,n,sr,safe,method)),out)
  if st<=0 then error('Native DeClick repair: '..tostring(r.VN_DeclickError(0)),0) end
  return out.table(1,n),st-1
end
local Batch={};Batch.__index=Batch
function M:batch(job)
  local r=self.r;local h=handle(r,r.VN_DeclickBatch(),'DeClick repair batch');own(job,h)
  return setmetatable({native=self,h=h,slots={},job=job},Batch)
end
function Batch:add(key,left,right,n,sr,safe,method)
  local r=self.native.r
  local slot=r.VN_DeclickBatchAdd(self.h.id,r.new_array(pack(left,right,n,sr,safe,method)))
  if slot<=0 then error('Native DeClick repair: '..tostring(r.VN_DeclickError(0)),0) end
  self.slots[key]={slot,n}
end
function Batch:take(key)
  local s=self.slots[key];if not s then return nil end
  self.slots[key]=nil
  local r=self.native.r;local out=r.new_array(s[2])
  while true do
    local n=r.VN_DeclickBatchRead(self.h.id,s[1],out)
    if n>0 then return out.table(1,n) end
    if n<0 then error('Native DeClick repair: '..tostring(r.VN_DeclickError(0)),0) end
    idle(self.job)
  end
end
function Batch:close() disown(self.job,self.h);self.h:release() end
return M
