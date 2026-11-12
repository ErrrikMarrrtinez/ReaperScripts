-- @noindex
-- Measured min/max samples at 1 ms, with an incremental dyadic peak pyramid.
-- Rendering costs O(screen pixels * log bins), independent of audio length.
local M={}
function M.new()return {hop=.001,levels={{lo={},hi={}}},peak=0}end
function M.push(w,lo,hi)
  local level=1
  w.peak=math.max(w.peak,math.abs(lo),math.abs(hi))
  while true do
    local row=w.levels[level];if not row then row={lo={},hi={}};w.levels[level]=row end
    local n=#row.lo+1;row.lo[n]=lo;row.hi[n]=hi
    if n%2~=0 then break end
    lo=math.min(row.lo[n-1],lo);hi=math.max(row.hi[n-1],hi);level=level+1
  end
end
function M.append(w,samples,origin,first,finish)
  for at=first,finish-1,16 do
    local lo,hi=0,0
    for j=at,math.min(at+15,finish-1) do local x=samples[j-origin+1] or 0;lo=math.min(lo,x);hi=math.max(hi,x) end
    M.push(w,lo,hi)
  end
end
local function source(data)
  local offset=0
  while data and data._source do offset=offset+(data._offset or 0);data=data._source end
  return data and data.waveform,offset,data
end
function M.range(data,a,b)
  local w,offset,original=source(data)
  if not w then
    -- Old projects remain readable at their saved 16 ms resolution.
    local lo,hi=0,0;local frames=original and original.frames or {};local hop=original and original.hop or .016
    for i=math.max(1,math.floor((a+offset)/hop)+1),math.min(#frames,math.ceil((b+offset)/hop)) do
      lo=math.min(lo,frames[i].lo or 0);hi=math.max(hi,frames[i].hi or 0)
    end
    return lo,hi
  end
  local first=math.max(0,math.floor((a+offset)/w.hop+1e-8))
  local last=math.min(#w.levels[1].lo,math.ceil((b+offset)/w.hop-1e-8))
  local lo,hi=0,0
  while first<last do
    local level,size=1,1
    while w.levels[level+1] and first%(size*2)==0 and first+size*2<=last do level=level+1;size=size*2 end
    local row=w.levels[level];local i=first//size+1
    lo=math.min(lo,row.lo[i]);hi=math.max(hi,row.hi[i]);first=first+size
  end
  return lo,hi
end
function M.peak(data)
  local w,_,original=source(data);if w then return math.max(.001,w.peak) end
  if not original then return .001 end
  if not original._wave_peak then
    local peak=.001;for _,f in ipairs(original.frames) do peak=math.max(peak,math.abs(f.lo or 0),math.abs(f.hi or 0)) end
    original._wave_peak=peak
  end
  return original._wave_peak
end
function M.pack(w,job)
  if not w then return nil end
  local rows={};local base=w.levels[1]
  for i=1,#base.lo do rows[i]=string.pack('<ff',base.lo[i],base.hi[i]);if job and i%2048==0 then job:checkpoint() end end
  return table.concat(rows)
end
-- Компактная волна для проекта: 8 бит на lo и на hi (корень амплитуды от пика: разрешение ~ -96 дБ от пика —
-- для отрисовки с запасом), плоскости lo и hi раздельно — так их лучше сжимает LZ. Было 8 байт на миллисекунду, стало 2.
function M.pack_q(w,job)
  if not w then return nil end
  local base=w.levels[1];local n=#base.lo;local peak=0
  for i=1,n do local a,b=-base.lo[i],base.hi[i];if a>peak then peak=a end;if b>peak then peak=b end end
  peak=math.max(peak,1e-9)
  local char,floor,sqrt=string.char,math.floor,math.sqrt
  local lo,hi={},{}
  for i=1,n do
    lo[i]=char(floor(255*sqrt(math.max(0,-base.lo[i])/peak)+.5));hi[i]=char(floor(255*sqrt(math.max(0,base.hi[i])/peak)+.5))
    if job and i%4096==0 then job:checkpoint() end
  end
  return table.concat(lo)..table.concat(hi),peak
end
function M.unpack_q(bytes,peak,len,job)
  if not bytes then return nil end
  assert(type(bytes)=='string' and #bytes%2==0 and type(peak)=='number' and peak>0 and peak<1e6,'Invalid Pitch waveform')
  local n=#bytes//2;assert(n<=600001 and n<=math.ceil(len*1000)+1,'Invalid Pitch waveform')
  local w=M.new();local byte=string.byte;local k=peak/65025
  for i=1,n do
    if job and i%8192==0 then job:checkpoint() end
    local a,b=byte(bytes,i),byte(bytes,n+i)
    M.push(w,-a*a*k,b*b*k)
  end
  return w
end
function M.unpack(bytes,len,job)
  if not bytes then return nil end
  assert(type(bytes)=='string' and #bytes%8==0 and #bytes/8<=600001 and #bytes/8<=math.ceil(len*1000)+1,'Invalid Pitch waveform')
  local w=M.new()
  for at=1,#bytes,8 do
    if job and at%32768==1 then job:checkpoint() end
    local lo,hi=string.unpack('<ff',bytes,at)
    assert(lo<=0 and hi>=0 and lo>-1e6 and hi<1e6,'Invalid Pitch waveform peak');M.push(w,lo,hi)
  end
  return w
end
return M
