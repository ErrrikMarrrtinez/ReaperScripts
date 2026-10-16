-- @noindex
local import=...;local U=import('align/util');local M={}
local function excluded(t,zones)
  for _,z in ipairs(zones or {})do if z.kind=='exclude_match' and t>=z.start_s and t<=z.end_s then return true end end
  return false
end
function M.find(data,constraints,job)
  local f=data.frames;local islands={};local start,last
  for i,a in ipairs(f)do
    local invalid=a.missing or excluded(a.t,constraints)
    if start and (invalid or a.t-f[last].t>.12000001)then
      islands[#islands+1]={first=start,last=last};start,last=nil,nil
    end
    if not invalid and (a.event>=.55 or start and a.event>=.30) then start=start or i;last=i end
    if i%128==0 then U.checkpoint(job)end
  end
  if start then islands[#islands+1]={first=start,last=last}end
  local phrases={}
  for _,island in ipairs(islands)do
    local previous=phrases[#phrases];local separate=not previous
    if previous then
      local continuous=0;local max_background=0;local invalid=false
      for k=previous.last+1,island.first-1 do
        local a=f[k];if a.missing or excluded(a.t,constraints)then invalid=true end
        if a.background>=.80 then continuous=continuous+a.mass*.01;max_background=math.max(max_background,continuous)else continuous=0 end
      end
      separate=invalid or max_background>=.30-1e-8
    end
    if separate then phrases[#phrases+1]={first=island.first,last=island.last,islands={island}}
    else previous.last=island.last;previous.islands[#previous.islands+1]=island end
  end
  for id,p in ipairs(phrases)do
    p.id=id;p.u0=f[p.first].t;p.u1=f[p.last].t;p.left=f[p.first].left;p.right=f[p.last].right
    p.mass=0;p.content_mass=0
    for i=p.first,p.last do p.mass=p.mass+f[i].mass;p.content_mass=p.content_mass+f[i].mass*f[i].event end
  end
  return phrases
end
-- Bounded landmark graph for the one optional segmental retry.
function M.landmarks(frames,first,last)
  local selected={};local candidates={}
  for i=first+1,last-1 do
    local a=frames[i];local onset=a.onset>=.65 and a.onset_reliability>=.65 and a.onset>=frames[i-1].onset and a.onset>frames[i+1].onset
    local change=a.change>=.70 and a.change>=frames[i-1].change and a.change>frames[i+1].change
    if not a.missing and (onset or change)then candidates[#candidates+1]={index=i,score=math.max(a.onset*a.onset_reliability,a.change*a.spectral_reliability)}end
  end
  table.sort(candidates,function(a,b)if a.score~=b.score then return a.score>b.score end;return a.index<b.index end)
  for _,a in ipairs(candidates)do
    local near=false;for _,b in ipairs(selected)do if math.abs(frames[a.index].t-frames[b.index].t)<.06-1e-8 then near=true;break end end
    if not near then selected[#selected+1]=a;if #selected==32 then break end end
  end
  selected[#selected+1]={index=first,score=1};selected[#selected+1]={index=last,score=1}
  table.sort(selected,function(a,b)return a.index<b.index end)
  local incoming={};local outgoing={}
  for k,a in ipairs(selected)do
    local choices={}
    for l=k+1,#selected do local b=selected[l];local duration=frames[b.index].t-frames[a.index].t
      if duration>=.08-1e-8 and duration<=.6+1e-8 then choices[#choices+1]={origin=a.index,destination=b.index,duration=duration,reliability=b.score}end
    end
    table.sort(choices,function(x,y)if x.duration~=y.duration then return x.duration<y.duration end;return x.reliability>y.reliability end)
    for i=1,math.min(3,#choices)do local e=choices[i];incoming[e.destination]=incoming[e.destination] or {};table.insert(incoming[e.destination],e)end
  end
  for destination,list in pairs(incoming)do
    table.sort(list,function(a,b)if a.duration~=b.duration then return a.duration<b.duration end;return a.origin<b.origin end)
    while #list>3 do table.remove(list)end
    for id,e in ipairs(list)do e.id=id;outgoing[e.origin]=math.max(outgoing[e.origin] or 0,destination)end
  end
  return {incoming=incoming,origins=outgoing,points=selected}
end
return M
