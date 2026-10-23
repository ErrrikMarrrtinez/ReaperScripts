-- @noindex
local M={}
-- fx_envelopes (тысячи точек огибающей ReaPitch) только заменяются целиком, на месте не правятся: копии делят их по ссылке
local SHARED={fx_envelopes=true}
local function copy(x) if type(x)~='table' then return x end;local t={};for k,v in pairs(x) do if SHARED[k] then t[k]=v else t[k]=copy(v) end end;return t end
M.copy=copy
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function equal(a,b)
  if a==b then return true end
  if type(a)~=type(b) then return false end;if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end;return true
end
local voice_fields={'center','shift','formant','transition','modulation','drift','flatten','flat_offset','expression_version',
  'vibrato_depth','vibrato_rate','vibrato_onset','expression_start','expression_finish','phase_origin',
  'transition_amount','transition_shape','transition_bias','transition_link','vibrato_release','vibrato_growth','vibrato_replace'}
local function same_voice(a,b)
  if not a or not b or not a.split_group or a.split_group~=b.split_group or math.abs(a.finish-b.start)>1e-8 then return false end
  for _,key in ipairs(voice_fields) do if a[key]~=b[key] then return false end end
  local pa,pb=a.anchors or {},b.anchors or {};if #pa~=#pb then return false end
  for i,p in ipairs(pa) do if p.t~=pb[i].t or p.value~=pb[i].value then return false end end
  if not equal(a.drawings,b.drawings) or not equal(a.target_anchors,b.target_anchors) or not equal(a.link,b.link) then return false end
  return true
end
-- Identical children retain the parent's acoustic span. Splitting is a visual
-- / selection operation until one child is actually edited, including v1.
function M.voice_group(notes,index)
  local n=notes[index];if not n then return nil,index,index end
  if notes._resolved then return n,index,index end
  local first,last=index,index
  if n.split_group then
    while same_voice(notes[first-1],notes[first]) do first=first-1 end
    while same_voice(notes[last],notes[last+1]) do last=last+1 end
  end
  if first==last then return n,first,last end
  local group={};for k,v in pairs(notes[first]) do group[k]=v end
  group.finish=notes[last].finish;group.last=notes[last].last
  return group,first,last
end
-- Resolve split siblings once per immutable evaluation pass, not per sample.
-- This table is transient: never attach it to persisted note state.
function M.resolve(notes)
  if notes._resolved then return notes end
  local out={_resolved=true};local at=1
  while at<=#notes do local n,_,last=M.voice_group(notes,at);out[#out+1]=n;at=last+1 end
  return out
end
function M.same_curve(a,b)
  if not a or not b or a.start~=b.start or a.finish~=b.finish then return false end
  for _,key in ipairs(voice_fields)do if a[key]~=b[key]then return false end end
  return equal(a.anchors,b.anchors) and equal(a.drawings,b.drawings) and equal(a.target_anchors,b.target_anchors) and equal(a.link,b.link)
end
function M.changed_ranges(old,current)
  local ranges={}
  local function mark(list,i)
    local n=list[i];local a,b=list[i-1] or n,list[i+1] or n
    local pad=math.max(.3,n.transition or .08,a.transition or .08,b.transition or .08)
    ranges[#ranges+1]={a.start-pad,b.finish+pad}
  end
  local i,j=1,1
  while i<=#old or j<=#current do
    local a,b=old[i],current[j]
    if a and b and a.start==b.start then
      if not M.same_curve(a,b) then mark(old,i);mark(current,j) end;i=i+1;j=j+1
    elseif a and (not b or a.start<b.start) then mark(old,i);i=i+1
    else mark(current,j);j=j+1 end
  end
  table.sort(ranges,function(a,b)return a[1]<b[1]end)
  local merged={}
  for _,range in ipairs(ranges)do local last=merged[#merged]
    if last and range[1]<=last[2] then last[2]=math.max(last[2],range[2]) else merged[#merged+1]=range end
  end
  return merged
end
function M.visual_center(n,data,pitch_at)
  local samples,total={},0;local margin=math.min(.04,(n.finish-n.start)*.12)
  for _,threshold in ipairs({.65,.35}) do
    samples,total={},0
    local first=math.max(1,math.floor(n.start/data.hop))
    local last=math.min(#data.frames,math.ceil(n.finish/data.hop)+2)
    for i=first,last do local f=data.frames[i]
      if f.t>=n.start+margin and f.t<n.finish-margin and f.confidence>=threshold and (f.level_db or -20)>-60 then
        local p=pitch_at and pitch_at(f.t) or f.pitch+(n.shift or 0)+(n.flat_offset or 0)*(n.flatten or 0)
        local w=f.confidence^2
        samples[#samples+1]={p=p,w=w};total=total+w
      end
    end
    if #samples>=3 then break end
  end
  if #samples==0 then return nil end
  table.sort(samples,function(a,b)return a.p<b.p end)
  local sum=0;for _,v in ipairs(samples) do sum=sum+v.w;if sum>=total*.5 then return v.p end end
end
-- Detect voiced regions independently from note-center changes. A short voiced
-- island must not compete with a zero-cost gap in the change-point optimizer.
function M.segment(data,hold_ms,job)
  local frames,hop=data.frames,data.hop;local count=#frames;local mask={}
  local function audible(f)return f and (f.level_db or -160)>-60 end
  for i,f in ipairs(frames) do mask[i]=audible(f) and f.confidence>=.3 end
  -- Only bridge up to 32 ms with compatible voiced endpoints. Long low-trust
  -- tails remain unpitched; a breath/noise interval cannot seed a note.
  local i=1
  while i<=count do
    if mask[i] then i=i+1 else
      local first=i;while i<=count and not mask[i] do i=i+1 end
      if first>1 and i<=count and (i-first)*hop<=.032001 and math.abs(frames[first-1].pitch-frames[i].pitch)<=2 then
        local ok=true;for k=first,i-1 do if not audible(frames[k]) then ok=false end end
        if ok then for k=first,i-1 do mask[k]=true end end
      end
    end
  end
  local notes={};i=1
  while i<=count do
    if not mask[i] then i=i+1 else
      local first=i;local seeds=0
      while i<=count and mask[i] do if frames[i].confidence>=.5 then seeds=seeds+1 end;i=i+1 end
      local last=i-1
      if seeds>=2 and (last-first+1)*hop>=.031999 then
        local centers,seen={},{}
        for k=first,last do local f=frames[k]
          if f.confidence>=.5 then local q=math.floor(f.pitch*20+.5);if not seen[q] then centers[#centers+1]=q/20;seen[q]=true end end
        end
        table.sort(centers)
        local costs,starts,back,kind={},{},{},{};local best=0
        local beta=(hold_ms or 100)/1000/hop
        for j=1,#centers do costs[j]=math.huge end
        for t=first,last do local f=frames[t];local new=best+beta;local minvalue,minid=math.huge,1
          for j,center in ipairs(centers) do
            if new<costs[j] then costs[j]=new;starts[j]=t end
            -- Robust absolute distance: stable changes pay for a boundary,
            -- vibrato and isolated octave errors do not dominate the center.
            costs[j]=costs[j]+math.min(4,math.abs(f.pitch-center))*f.confidence
            if costs[j]<minvalue then minvalue,minid=costs[j],j end
          end
          best=minvalue;back[t]=starts[minid]-1;kind[t]=minid
          if job and t%16==0 then job:checkpoint(t/count,'Separating notes') end
        end
        local reverse={};local b=last
        while b>=first do local a=back[b]
          reverse[#reverse+1]={first=a+1,last=b,start=frames[a+1].t,finish=math.min(data.len,frames[b].t+hop),
            center=centers[kind[b]],shift=0,formant=0,transition=.08,anchors={}}
          b=a
        end
        for k=#reverse,1,-1 do local note=reverse[k];note.id=#notes+1;notes[#notes+1]=note end
      end
      if job then job:checkpoint(i/count,'Separating notes') end
    end
  end
  return notes
end
function M.at(notes,t)
  local lo,hi=1,#notes
  while lo<=hi do local mid=(lo+hi)//2;local n=notes[mid]
    if t<n.start then hi=mid-1 elseif t>=n.finish then lo=mid+1 else return n,mid end
  end
  return nil,lo
end
function M.split(notes,index,t,data,pitch_at)
  local n=notes[index];if not n or t-n.start<.032 or n.finish-t<.032 then return false end
  t=math.floor(t/data.hop+.5)*data.hop
  if t-n.start<.031999 or n.finish-t<.031999 then return false end
  n.expression_start=n.expression_start or n.start;n.expression_finish=n.expression_finish or n.finish;n.phase_origin=n.phase_origin or n.start
  local right=copy(n);right.start=t;right.first=math.floor(t/data.hop)+1
  right.id=0;for _,v in ipairs(notes) do right.id=math.max(right.id,v.id,v.split_group or 0) end;right.id=right.id+1
  n.split_group=n.split_group or right.id;right.split_group=n.split_group
  n.finish=t;n.last=right.first-1
  table.insert(notes,index+1,right)
  for _,child in ipairs({n,right}) do
    child.local_center=true
    local center=M.visual_center(child,data,pitch_at)
    if center then child.visual_offset=center-child.center-(child.shift or 0)-(child.flat_offset or 0)*(child.flatten or 0) end
  end
  return true,right
end
function M.join(notes,index)
  local a,b=notes[index],notes[index+1];if not a or not b or b.start-a.finish>.08 then return false end
  if same_voice(a,b) then a.finish=b.finish;a.last=b.last;table.remove(notes,index+1);return true end
  -- A joined note has one center/formant control. Do not silently flatten two
  -- different corrections or replace their smooth boundary with a tiny ramp.
  local expression=false
  for _,n in ipairs({a,b}) do if (n.modulation or 1)~=1 or (n.drift or 1)~=1 or (n.flatten or 0)~=0 or (n.vibrato_depth or 0)~=0 or (n.transition_amount or 0)~=0 or #(n.drawings or {})>0 or #(n.target_anchors or {})>0 or n.link~=nil then expression=true end end
  if expression or a.shift~=b.shift or a.formant~=b.formant or #(a.anchors or {})>0 or #(b.anchors or {})>0 then
    return false,'Reset the two notes before joining different pitch/curve/formant edits.'
  end
  a.finish=b.finish;a.last=b.last
  table.remove(notes,index+1);return true
end
return M
