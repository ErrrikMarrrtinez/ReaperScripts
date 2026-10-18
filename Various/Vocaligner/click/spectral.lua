-- @noindex
-- Mouth candidates: simultaneous excess in independent frequency bands.
-- Uses the project's independently implemented FFT, not an RX binary or model.
local M={}
local function quantile(a)
 table.sort(a);return a[math.max(1,math.ceil(#a*.65))] or 0
end
local function read(pcm,first,count)
 local out={};local stop=first+count;local cursor=first
 while cursor<0 and cursor<stop do for c=1,pcm.channels do out[#out+1]=0 end;cursor=cursor+1 end
 for _,b in ipairs(pcm.blocks)do
  if b.first+b.count>cursor and b.first<stop then
   local a=math.max(cursor,b.first);local n=math.min(stop,b.first+b.count)-a
   local values=b.buffer.table((a-b.first)*pcm.channels+1,n*pcm.channels)
   for _,v in ipairs(values)do out[#out+1]=v end;cursor=a+n
  end
  if cursor>=stop then break end
 end
 while cursor<stop do for c=1,pcm.channels do out[#out+1]=0 end;cursor=cursor+1 end
 return out
end
-- Lua-эталон контраста (используется, если EEL-движок click недоступен). rows/контраст — плоские frames*bands.
local function lua_contrast(rows,frames,bands,near,far,job)
 local out={}
 for i=0,frames-1 do
  for band=1,bands do
   local left,right={},{}
   for d=near,far,4 do
    if i-d>=0 then left[#left+1]=rows[(i-d)*bands+band] end
    if i+d<frames then right[#right+1]=rows[(i+d)*bands+band] end
   end
   local base=math.max(quantile(left),quantile(right),1e-12)
   out[i*bands+band]=math.max(0,math.min(60,10*math.log(math.max(rows[i*bands+band],1e-12)/base,10)))
  end
  if i%32==0 then job:checkpoint() end
 end
 return out
end
-- click: EEL-движок click/engine (контраст полос). Без него — тот же расчёт на Lua.
function M.ensure(pcm,engine,job,click)
 if pcm.click_spectrum then return pcm.click_spectrum end
 assert(engine and engine.fn,'Mouth requires the EEL spectral engine')
 local hop=math.max(1,math.floor(pcm.sr*.002+.5));local frames=math.ceil(pcm.len*pcm.sr/hop)
 local data={hop=hop/pcm.sr,len=pcm.len,bands=math.min(24,math.floor(pcm.sr/1000)),frames=0}
 local rows={}
 for first=0,frames-1,24 do
  local count=math.min(24,frames-first);local n=(count-1)*hop+1024
  local values=job:call(function()
   local samples=read(pcm,first*hop-512,n)
   return engine:band_rows(samples,0,pcm.channels,n,count,hop,pcm.sr,data.bands)
  end)
  table.move(values,1,#values,#rows+1,rows);data.frames=data.frames+count
  job:checkpoint(first/frames,'Analyzing Mouth spectrum')
 end
 -- Cache contrast, so frequency bias / threshold edits do not repeat FFT or sorting.
 local near=math.ceil(.024/data.hop);local far=math.ceil(.080/data.hop)
 if click and click.contrast_fn then data.contrast=job:call(click.contrast,click,rows,data.frames,data.bands,near,far)
 else data.contrast=lua_contrast(rows,data.frames,data.bands,near,far,job) end
 pcm.click_spectrum=data;return data
end
function M.events(spectrum,fine,scores,cfg,exclusions,job)
 local novelty={};local skew=cfg.mouth_skew;local threshold=16-10*cfg.mouth_sensitivity/100
 local bands,contrast=spectrum.bands,spectrum.contrast
 local weights,weight={},0
 for b=1,bands do weights[b]=2^(skew/10*(2*b/bands-1));weight=weight+weights[b] end
 for i=1,spectrum.frames do
  local sum,at=0,(i-1)*bands
  for b=1,bands do sum=sum+contrast[at+b]*weights[b] end
  novelty[i]=sum/weight
 end
 local events={};local i=2
 while i<#novelty do
  if novelty[i]>=threshold then
   local a,b=i,i;local peak=i
   while a>1 and novelty[a-1]>=threshold*.55 do a=a-1 end
   while b<#novelty and novelty[b+1]>=threshold*.55 do b=b+1;if novelty[b]>novelty[peak]then peak=b end end
   if (b-a+1)*spectrum.hop<=.080 then
    -- FFT locates the area; the .25 ms waveform grid trims window smear.
    local lo=math.max(1,math.floor((a-1)*spectrum.hop/fine.hop)+1)
    local hi=math.min(#scores,math.ceil((b+1)*spectrum.hop/fine.hop))
    local start,finish,maxcontrast,maxscore,at=nil,nil,1,0,0
    for j=lo,hi do local s=scores[j];local f=fine.rows[j]
     if math.max(s.sharp,s.pred)>1.6 and f[1]>s.base*1.15 and s.onset<6 then
      start=start or j;finish=j
      if f[1]/s.base>maxcontrast then maxcontrast=f[1]/s.base;at=f[8]end
      maxscore=math.max(maxscore,s.score)
     end
    end
    if start and (finish-start)*fine.hop<=.060 and maxscore>=2 then
     local e={kind='mouth',start=(start-1)*fine.hop,finish=math.min(fine.len,finish*fine.hop),peak=at,
      score=novelty[peak],contrast=maxcontrast,spectral=true}
     for _,x in ipairs(exclusions or {})do if x.kind=='mouth' and x.finish>e.start and x.start<e.finish then e.excluded=true end end
     local old=events[#events]
     if old and old.finish>=e.start and old.excluded==e.excluded then old.finish=e.finish;old.contrast=math.max(old.contrast,e.contrast)
     else events[#events+1]=e end
    end
   end
   i=b+1
  else i=i+1 end
  if i%64==0 then job:checkpoint() end
 end
 return events
end
return M
