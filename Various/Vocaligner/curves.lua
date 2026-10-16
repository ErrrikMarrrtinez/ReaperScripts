-- @noindex
local import=...;local Cleanup=import('cleanup');local M={}
local function checkpoint(job,i) if job and i%256==0 then job:checkpoint() end end
local function value(curve,i) return curve and curve.points[i] and curve.points[i].db or 0 end
-- All layers share the original analysis grid. Replace just the chosen interval,
-- feathering inward so points outside it remain unchanged, including prior work.
function M.patch(data,previous,current,range,job)
  local a,b=range[1],range[2];local fade=math.min(.015,(b-a)/4)
  local left,right=Cleanup.value(previous,a),Cleanup.value(previous,b)
  local out={points={},max_db=0,hop=data.hop}
  for i=1,#data.frames+1 do
    local t=data.frames[i] and data.frames[i].t or data.len
    local db=value(previous,i)
    if t>=a and t<=b then
      local mix=fade>0 and math.min(1,(t-a)/fade,(b-t)/fade) or 0
      local edge=t-a<=b-t and left or right
      db=edge+(value(current,i)-edge)*math.max(0,mix)
    end
    out.points[i]={t=t,db=db};out.max_db=math.max(out.max_db,db)
    checkpoint(job,i)
  end
  return out
end
-- Compare this section with its applied layer, independently of the other tool.
-- A zero preview may still be a real edit: it can remove an earlier reduction.
function M.change(data,previous,current,range,job)
  local changed,peak=false,0
  local old_on=previous and previous.max_db>.01
  local new_on=current and current.max_db>.01
  for i=1,#data.frames+1 do
    local old=old_on and value(previous,i) or 0
    local new=new_on and value(current,i) or 0
    if math.abs(new-old)>1e-6 then changed=true end
    local t=data.frames[i] and data.frames[i].t or data.len
    if t>=range[1] and t<=range[2] then peak=math.max(peak,new) end
    checkpoint(job,i)
  end
  return changed,peak
end
-- Visible reduction extents, including pre-open/release. Interpolate crossings
-- on the same curve used by Apply instead of guessing tails from knob values.
function M.combine(data,layers,job)
  for _,curve in pairs(layers)do if curve.recipes then return import('compressor/curves').sum(data,layers,job) end end
  local out={points={},max_db=0,hop=data.hop}
  for i=1,#data.frames+1 do
    local db=math.max(value(layers.deess,i),value(layers.breath,i))
    out.points[i]={t=data.frames[i] and data.frames[i].t or data.len,db=db}
    out.max_db=math.max(out.max_db,db);checkpoint(job,i)
  end
  return out
end
function M.regions(curve,job)
  local out={};local start,peak;local previous={t=0,db=0};local threshold=.01
  for i,p in ipairs(curve and curve.points or {}) do
    if p.db>threshold then
      if not start then
        local mix=p.db~=previous.db and (threshold-previous.db)/(p.db-previous.db) or 0
        start=previous.t+(p.t-previous.t)*math.max(0,math.min(1,mix));peak=p.db
      else peak=math.max(peak,p.db) end
    elseif start then
      local mix=(previous.db-threshold)/(previous.db-p.db)
      out[#out+1]={start=start,finish=previous.t+(p.t-previous.t)*mix,reduction=peak}
      start=nil
    end
    previous=p;checkpoint(job,i)
  end
  if start then out[#out+1]={start=start,finish=previous.t,reduction=peak} end
  return out
end
return M
