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
function M.sum(data,layers,job)
 local out={points={},max_db=0,hop=data.hop,sequential=true}
 for i,t in ipairs(M.times(data.len,layers))do
  local db=0;for _,curve in pairs(layers)do db=db+M.value(curve,t) end
  out.points[i]={t=t,db=db};out.max_db=math.max(out.max_db,math.abs(db))
  if job and i%256==0 then job:checkpoint() end
 end
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
