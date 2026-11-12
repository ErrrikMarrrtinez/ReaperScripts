-- @noindex
-- Кадры анализа Cleanup (De-ess / Breaths / Compressor / Gate) в колонках на массивах reaper_array вместо таблицы Lua
-- на кадр. Час аудио — 360 тысяч кадров по 100 в секунду; таблицами это ≈1,3 КБ на кадр (≈470 МБ кучи Lua, сотни
-- тысяч живых объектов для сборщика мусора, он и давал паузы по 50–300 мс), колонками — 352 байта на кадр вне кучи Lua.
-- Отдельных таблиц на кадр нет: `frames` — прокси (#, [i], ipairs, pairs), кадр — лёгкий объект, поля которого читаются из
-- колонок по обращению (t, rms, zcr, noise_flat, breath_flat, breath_tonal, air, low, flat, min, max, noise_bands[32],
-- cep/spec/chroma, flux) — тот же набор, что был в таблице кадра. Горячие пути (нормализация, признаки De-ess, ввод кадров
-- в Breaths, цепочка с upstream-кривой) работают блоками по 128 кадров напрямую с массивами и кадров-объектов не создают:
-- крупные временные таблицы (десятки тысяч чисел за раз) заставляют сборщик мусора платить долг одним долгим шагом.
-- Раскладка страницы p (кадры (p-1)*1024 .. p*1024-1):
--   spectrum: bands — 1024*32 полосы по 500 Гц; scal — 1024*10 (rms, zcr, noise_flat, breath_flat, breath_tonal, air, low,
--             flat, min, max) — ровно строка VN_DynSpectrum без полос, поэтому ввод — две копии на кадр;
--   wave: wave — 1024*4 (t, min, max, rms) — строка VN_DynRows режима захвата волны (лёгкий путь без спектра).
-- Время кадра считается тем же выражением, что при записи в таблицу: (индекс*hop)/sr.
local import=...;local M={}
M.PAGE=1024
M.CONV=128 -- кадров за одно преобразование массив -> таблица Lua
local PAGE,CONV=M.PAGE,M.CONV
local EMPTY=setmetatable({},{__newindex=function()error('frame field is read-only',2)end})
M.EMPTY=EMPTY -- общая пустая таблица для cep/spec/chroma у кадров (в Cleanup их никто не заполняет)
local SPEC={rms=1,zcr=2,noise_flat=3,breath_flat=4,breath_tonal=5,air=6,low=7,flat=8,min=9,max=10}
local WAVE={min=2,max=3,rms=4}
local function checkpoint(job,i,every) if job and i%(every or 1)==0 then job:checkpoint() end end

local Store={};Store.__index=Store
-- Кадр: лёгкий объект с ленивым чтением полей из колонок
local View={}
View.__index=function(f,k)
  local store,i=rawget(f,'_s'),rawget(f,'_i')
  if k=='t' then return store:time(i) end
  if k=='noise_bands' then return store:bands_of(i) end
  if k=='cep' or k=='spec' or k=='chroma' then return EMPTY end
  if k=='flux' then return 0 end
  local at=(store.kind=='wave' and WAVE or SPEC)[k]
  if at then return store:scalar(i,at) end
  return nil
end
local function materialise(f)
  local store,i=rawget(f,'_s'),rawget(f,'_i');local out={cep=EMPTY,spec=EMPTY,chroma=EMPTY,flux=0,t=store:time(i)}
  if store.kind=='wave' then out.noise_bands={} else out.noise_bands=store:bands_of(i) end
  for k,at in pairs(store.kind=='wave' and WAVE or SPEC) do out[k]=store:scalar(i,at) end
  return out
end
View.__pairs=function(f) return next,materialise(f),nil end
local function proxy(store)
  local last_i,last_f
  return setmetatable({},{
    __len=function()return store.n end,
    __index=function(_,i)
      i=math.tointeger(i);if not i or i<1 or i>store.n then return nil end
      if i==last_i then return last_f end -- data.frames[i] and data.frames[i].t: второй доступ без пересоздания
      last_i,last_f=i,setmetatable({_s=store,_i=i},View);return last_f
    end,
    __newindex=function()error('frames of a long item are read-only',2)end,
    __pairs=function(t)return function(_,i)i=(i or 0)+1;if i<=store.n then return i,t[i] end end,t,nil end})
end
-- kind 'spectrum' | 'wave'. count — число кадров; hop — отсчётов между кадрами, sr — частота анализа
-- (для wave время хранится в самих строках, hop/sr не нужны)
function M.new(r,kind,count,hop,sr)
  local self=setmetatable({r=r,kind=kind,n=count,hop=hop,sr=sr,pages=(count+PAGE-1)//PAGE,bands={},scal={},wave={},cache={}},Store)
  self.frames=proxy(self)
  return self
end
function M.of(data) return data and data.frame_store end
function Store:time(i) return (i-1)*self.hop/self.sr end
function Store:_array(set,p,size)
  local a=set[p];if not a then a=self.r.new_array(size);set[p]=a end;return a
end
function Store:count_in(p) return math.min(PAGE,self.n-(p-1)*PAGE) end
-- ---- ввод
-- Строки VN_DynSpectrum (42 значения на кадр: 10 скаляров и 32 полосы), count кадров, первый кадр first (0-based)
function Store:put_spectrum(out,count,first)
  for j=0,count-1 do
    local f=first+j;local p=f//PAGE+1;local slot=f%PAGE
    self:_array(self.bands,p,PAGE*32).copy(out,j*42+11,32,slot*32+1)
    self:_array(self.scal,p,PAGE*10).copy(out,j*42+1,10,slot*10+1)
  end
end
-- Строки VN_DynRows режима 2 (t, min, max, rms): got строк, первая строка — кадр first (0-based)
function Store:put_wave(rows,got,first)
  local f=first;local done=0
  while done<got do
    local p=f//PAGE+1;local slot=f%PAGE;local n=math.min(got-done,PAGE-slot)
    self:_array(self.wave,p,PAGE*4).copy(rows,done*4+1,n*4,slot*4+1);f=f+n;done=done+n
  end
end
-- ---- чтение: блок из CONV кадров переводится в таблицу Lua и держится, пока обращения идут по нему
-- Таблица значений блока c (0-based) колонки set со stride значений на кадр; возвращает таблицу и индекс первого кадра блока-1
function Store:_chunk(kind,set,stride,i)
  local c=(i-1)//CONV;local cached=self.cache[kind]
  if cached and cached.c==c then return cached.t,cached.base end
  local base=c*CONV;local p=base//PAGE+1;local slot=base%PAGE
  local count=math.min(CONV,self.n-base)
  local t=set[p].table(slot*stride+1,count*stride)
  self.cache[kind]={c=c,t=t,base=base};return t,base
end
function Store:scalar(i,at)
  if self.kind=='wave' then local t,base=self:_chunk('wave',self.wave,4,i);return t[(i-1-base)*4+at] end
  local t,base=self:_chunk('scal',self.scal,10,i);return t[(i-1-base)*10+at]
end
function Store:bands_of(i)
  local t,base=self:_chunk('bands',self.bands,32,i);local o=(i-1-base)*32;local out={}
  for k=1,32 do out[k]=t[o+k] end
  return out
end
-- Колонка скаляров по порядку кадров блоками: fn(table,count) получает таблицу значений блока (stride на кадр)
local function each_block(self,job,kind,stride,fn)
  local set=kind=='wave' and self.wave or self.scal
  local i=0
  while i<self.n do
    local count=math.min(CONV,self.n-i);local p=i//PAGE+1;local slot=i%PAGE
    fn(set[p].table(slot*stride+1,count*stride),count,i)
    i=i+count
    if job and (i//CONV)%8==0 then job:checkpoint() end
  end
end
local function stride_of(self)return self.kind=='wave' and 4 or 10 end
-- ---- свёртки для нормализации (DSP.normalize): rms всех кадров, пик, пары (min,max)
function Store:rms_table(job)
  local out={};local at=self.kind=='wave' and 4 or 1;local stride=stride_of(self)
  each_block(self,job,self.kind,stride,function(t,count,base)for s=0,count-1 do out[base+s+1]=t[s*stride+at] end end)
  return out
end
function Store:peak(job)
  local peak=0;local lo_f,hi_f=self.kind=='wave' and 2 or 9,self.kind=='wave' and 3 or 10;local stride=stride_of(self)
  each_block(self,job,self.kind,stride,function(t,count)
    for s=0,count-1 do
      local a,b=t[s*stride+lo_f],t[s*stride+hi_f]
      if a<0 then a=-a end;if b<0 then b=-b end
      if a>peak then peak=a end;if b>peak then peak=b end
    end
  end)
  return peak
end
-- Самый мелкий уровень пиков {min,max} по кадрам — прокси без таблицы на кадр; грубые уровни собираются таблицами
function Store:minmax(i)
  if self.kind=='wave' then local t,base=self:_chunk('wave',self.wave,4,i);local o=(i-1-base)*4;return t[o+2],t[o+3] end
  local t,base=self:_chunk('scal',self.scal,10,i);local o=(i-1-base)*10;return t[o+9],t[o+10]
end
function Store:base_values()
  local store=self;local last_i,last_v
  return setmetatable({},{__len=function()return store.n end,
    __index=function(_,i)
      i=math.tointeger(i);if not i or i<1 or i>store.n then return nil end
      if i~=last_i then local lo,hi=store:minmax(i);last_i,last_v=i,{lo,hi} end
      return last_v
    end,
    __pairs=function(t)return function(_,i)i=(i or 0)+1;if i<=store.n then return i,t[i] end end,t,nil end})
end
-- Следующий уровень пирамиды из самого мелкого: группы по 4 кадра, нижняя граница не выше 0, верхняя не ниже 0 — как в DSP.normalize
function Store:coarse_values(job)
  local out={};local lo,hi=0,0;local count=0
  local fmin,fmax=self.kind=='wave' and 2 or 9,self.kind=='wave' and 3 or 10;local stride=stride_of(self)
  each_block(self,job,self.kind,stride,function(t,n)
    for s=0,n-1 do
      local a,b=t[s*stride+fmin],t[s*stride+fmax]
      if a<lo then lo=a end;if b>hi then hi=b end;count=count+1
      if count==4 then out[#out+1]={lo,hi};lo,hi=0,0;count=0 end
    end
  end)
  if count>0 then out[#out+1]={lo,hi} end
  return out
end
-- ---- потребители признаков по страницам
-- Страница полос и пар (rms, noise_flat|flat) для VN_DynDeessFeatures. first — первый кадр страницы (1-based)
function Store:deess_block(first)
  local p=(first-1)//PAGE+1;local count=self:count_in(p)
  self.aux=self.aux or {};local aux=self.aux[p]
  if not aux then
    aux=self.r.new_array(count*2)
    for c=0,count-1,CONV do
      local n=math.min(CONV,count-c);local s=self.scal[p].table(c*10+1,n*10);local values={}
      for k=0,n-1 do values[2*k+1]=s[k*10+1];values[2*k+2]=s[k*10+3] end
      aux.copy(values,1,n*2,c*2+1)
    end
    self.aux[p]=aux
  end
  return self.bands[p],aux,count
end
-- Строки Breaths (t, rms, zcr, flat, tonal, полосы 1..16) для кадров first..last (1-based), плоской таблицей по 21 значению
function Store:breath_rows(first,last)
  local out={};local k=0;local i=first
  while i<=last do
    local base=i-1;local p=base//PAGE+1;local slot=base%PAGE
    local n=math.min(CONV-(base%CONV),last-i+1) -- блок не пересекает границу CONV, чтобы таблицы оставались небольшими
    local s=self.scal[p].table(slot*10+1,n*10);local b=self.bands[p].table(slot*32+1,n*32)
    for j=0,n-1 do
      local o,q=j*10,j*32
      out[k+1]=self:time(i+j);out[k+2]=s[o+1];out[k+3]=s[o+2];out[k+4]=s[o+4];out[k+5]=s[o+5]
      for z=1,16 do out[k+5+z]=b[q+z] end
      k=k+21
    end
    i=i+n
  end
  return out
end
-- Копия с усилением (upstream-кривая предыдущих стадий): rms/min/max умножаются на gain, полосы — на gain*gain, как в
-- цепочке для таблиц кадров. at(t) — значение кривой для возрастающих t. Остальные поля переносятся как есть.
function Store:derive(at,job)
  assert(self.kind=='spectrum','Only spectral frames carry upstream gain')
  local out=M.new(self.r,'spectrum',self.n,self.hop,self.sr)
  local i=0
  while i<self.n do
    local base=i;local p=base//PAGE+1;local slot=base%PAGE;local n=math.min(CONV,self.n-i)
    local s=self.scal[p].table(slot*10+1,n*10);local b=self.bands[p].table(slot*32+1,n*32)
    for j=0,n-1 do
      local gain=10^(-at(self:time(base+j+1))/20);local o,q=j*10,j*32
      s[o+1]=(s[o+1] or 0)*gain;s[o+9]=(s[o+9] or 0)*gain;s[o+10]=(s[o+10] or 0)*gain
      for k=1,32 do b[q+k]=b[q+k]*gain*gain end
    end
    out:_array(out.scal,p,PAGE*10).copy(s,1,n*10,slot*10+1)
    out:_array(out.bands,p,PAGE*32).copy(b,1,n*32,slot*32+1)
    i=i+n
    if job and (i//CONV)%4==0 then job:checkpoint() end
  end
  return out
end
-- Диагностика: байты колонок
function Store:bytes() return self.pages*PAGE*(self.kind=='wave' and 4 or 42)*8 end
return M
