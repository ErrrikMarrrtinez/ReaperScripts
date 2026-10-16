-- @noindex
local import=...;local Curve=import('pitch/curve');local Notes=import('pitch/notes');local Trace=import('pitch/trace');local M={}
-- Display support is independent of correction DSP. Never draw a pitch path
-- through low-confidence noise merely because the model emitted a number.
local function runs(data)local _,ids=Trace.runs(data);return ids end
function M.sample(data,t)return Trace.sample(data,t)end
-- Source is a projection of measured frame knots, never the target curve's
-- adaptive sample grid. Retain extrema when several knots share a pixel.
function M.source(data,start,span,width,previous)
  if previous and previous.data==data and previous.frames==data.frames and previous.count==#data.frames and previous.start==start and previous.span==span and previous.width==width then return previous end
  local out={data=data,frames=data.frames,count=#data.frames,start=start,span=span,width=width}
  local source,offset=data,0
  while source._source do offset=offset+(source._offset or 0);source=source._source end
  local ids=runs(source);local frames=source.frames;local bucket={};local bin,run
  local a,b=math.max(0,start),math.min(data.len,start+span)
  if b<a then return out end
  local raw,id=M.sample(data,a);out[#out+1]={t=a,raw=raw,run=id}
  local function flush()
    if #bucket==0 then return end
    local low,high=1,1
    for i,p in ipairs(bucket)do if p.raw<bucket[low].raw then low=i end;if p.raw>bucket[high].raw then high=i end end
    local keep={[1]=true,[#bucket]=true,[low]=true,[high]=true}
    for i,p in ipairs(bucket)do if keep[i]then out[#out+1]=p end end
    bucket={}
  end
  local first=math.max(1,math.floor((start+offset)/(source.hop or .016)))
  local last=math.min(#frames,math.ceil((start+span+offset)/(source.hop or .016))+2)
  for i=first,last do local f=frames[i];local t=f.t-offset
    if t>a and t<b then
      local pixel=math.floor((t-start)/span*width)
      if pixel~=bin or ids[i]~=run or not ids[i]then flush();bin=pixel;run=ids[i] end
      if ids[i]then
        bucket[#bucket+1]={t=t,raw=f.pitch,run=ids[i]}
        if ids[i]~=ids[i+1] then
          local finish=math.min(f.t+(source.hop or .016),frames[i+1] and frames[i+1].t or math.huge,source.len or math.huge)-offset
          -- Left limit of the frame end, before the next untrusted/jump knot.
          if finish>t+1e-8 and finish<b then flush();out[#out+1]={t=finish-1e-8,raw=f.pitch,run=ids[i]} end
        end
      else out[#out+1]={t=t} end
    end
  end
  flush();raw,id=M.sample(data,b);out[#out+1]={t=b,raw=raw,run=id};return out
end
function M.build(data,notes,version,start,span,width,pitch_per_pixel,previous)
  local out={start=start,span=span,width=width,pitch_per_pixel=pitch_per_pixel};local count=math.max(2,math.min(4096,math.ceil(width/1.5)))
  local tolerance=math.max(.0025,(pitch_per_pixel or 0)*.35);local cache={}
  local resolved=Notes.resolve(notes);local evaluate=Curve.evaluator(resolved,'shift',version,data)
  local valid=previous and previous._data==data and previous._version==version and previous._frames==data.frames and previous.frame_count==#data.frames
  local dirty=valid and Notes.changed_ranges(previous._notes,resolved) or nil
  local reused=0
  local function point(t)
    if cache[t] then return cache[t] end
    local old=valid and previous._samples[t]
    if old then
      for _,range in ipairs(dirty)do if t>=range[1] and t<=range[2] then old=nil;break end end
      if old then cache[t]=old;reused=reused+1;return old end
    end
    local raw,run=M.sample(data,t)
    local p={t=t,run=run,raw=raw}
    if raw then p.pitch=raw+evaluate(t);p.supported=Notes.at(notes,t)~=nil end
    cache[t]=p;return p
  end
  local function append(a,b,depth)
    if a.run and a.run==b.run and depth<9 and #out<8192 then
      local split=false;local mid
      for j=1,3 do
        local p=point(a.t+(b.t-a.t)*j/4);if j==2 then mid=p end
        if not p.run or p.run~=a.run or math.abs(p.pitch-(a.pitch+(b.pitch-a.pitch)*j/4))>tolerance then split=true end
      end
      if split then append(a,mid,depth+1);append(mid,b,depth+1);return end
    end
    out[#out+1]=b
  end
  out[1]=point(start)
  local step=span/count
  -- Anchor the seed grid to item time. Panning reuses the same samples rather
  -- than shifting every sample time along with the viewport.
  for i=math.floor(start/step)+1,math.ceil((start+span)/step)-1 do
    append(out[#out],point(i*step),0)
  end
  append(out[#out],point(start+span),0)
  out._samples=cache;out._notes=Notes.copy(resolved);out._data=data;out._version=version;out.reused_samples=reused
  out._frames=data.frames;out.frame_count=#data.frames
  return out
end
return M
