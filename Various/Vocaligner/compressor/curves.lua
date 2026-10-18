-- @noindex
local import=...;local Cleanup=import('cleanup');local M={}
M.value=Cleanup.value
function M.times(len,curves,extra)
 local all={0,len};for _,t in ipairs(extra or {})do all[#all+1]=t end
 for _,curve in pairs(curves or {}) do for _,p in ipairs(curve.points or {})do all[#all+1]=p.t end end
 table.sort(all);local out={};local previous=-1
 for _,t in ipairs(all)do if t>=0 and t<=len and t>previous+1e-9 then out[#out+1]=t;previous=t end end
 return out
end
-- First point index with t>a (binary search on sorted points).
local function after(points,a)
 local lo,hi=1,#points+1
 while lo<hi do local mid=(lo+hi)//2;if points[mid].t>a then hi=mid else lo=mid+1 end end
 return lo
end
-- A Bezier fade stays native only where every other stage is flat; there the
-- summed curve is that fade plus a constant. Otherwise Apply samples points.
local function shapes(layers)
 local out={}
 for kind,curve in pairs(layers)do for _,shape in ipairs(curve.shapes or {})do
  local clean=true
  for other,oc in pairs(layers)do if other~=kind and clean then
   local base=M.value(oc,shape.a)
   if math.abs(M.value(oc,shape.b)-base)>.01 then clean=false end
   local points=oc.points or {}
   for i=after(points,shape.a),#points do
    local p=points[i];if p.t>=shape.b or not clean then break end
    if math.abs(p.db-base)>.01 then clean=false end
   end
  end end
  if clean then out[#out+1]=shape end
 end end
 table.sort(out,function(a,b)return a.a<b.a end)
 return out
end
M.shapes=shapes
function M.sum(data,layers,job)
 local out={points={},max_db=0,hop=data.hop,sequential=true}
 for i,t in ipairs(M.times(data.len,layers))do
  local db=0;for _,curve in pairs(layers)do db=db+M.value(curve,t) end
  out.points[i]={t=t,db=db};out.max_db=math.max(out.max_db,math.abs(db))
  if job and i%256==0 then job:checkpoint() end
 end
 out.shapes=shapes(layers)
 return out
end
function M.patch(data,old,new,range,job)
 local a,b=range[1],range[2];local fade=math.min(.015,(b-a)/4)
 local out={points={},max_db=0,hop=new.hop}
 local extra={a,b,a+fade,b-fade}
 for i,t in ipairs(M.times(data.len,{old=old,new=new},extra))do
  local db=M.value(old,t)
  if t>=a and t<=b then
   local mix=fade>0 and math.max(0,math.min(1,(t-a)/fade,(b-t)/fade)) or 1
   local edge=M.value(old,t-a<=b-t and a or b)
   db=edge+(M.value(new,t)-edge)*mix
  end
  out.points[i]={t=t,db=db};out.max_db=math.max(out.max_db,math.abs(db))
  if job and i%256==0 then job:checkpoint() end
 end
 -- Bezier fades survive only where the patch leaves their curve untouched.
 local kept={}
 for _,shape in ipairs(old and old.shapes or {})do if shape.b<=a or shape.a>=b then kept[#kept+1]=shape end end
 for _,shape in ipairs(new.shapes or {})do if shape.a>=a+fade and shape.b<=b-fade or a<=0 and b>=data.len then kept[#kept+1]=shape end end
 if #kept>0 then table.sort(kept,function(x,y)return x.a<y.a end);out.shapes=kept end
 return out
end
function M.changed(data,a,b,job)
 for i,t in ipairs(M.times(data.len,{a=a,b=b}))do
  if math.abs(M.value(a,t)-M.value(b,t))>1e-6 then return true end
  if job and i%256==0 then job:checkpoint() end
 end
 return false
end
return M
