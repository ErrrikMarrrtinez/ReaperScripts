-- @noindex
local import=...;local Cleanup=import('cleanup');local M={}
M.value=Cleanup.value
-- Моменты всех точек кривых и extra, по возрастанию, без повторов (шаг 1e-9), только внутри [0,len].
-- Точки каждой кривой уже упорядочены по t, поэтому списки сливаются (k-way merge) вместо одной сортировки сотен тысяч
-- значений: table.sort — один неделимый вызов C (на часовом айтеме десятки–сотни мс подряд), слияние отдаёт кадр
-- интерфейсу через job:checkpoint(). Порядок и значения результата те же, что после сортировки; если вдруг какой-то
-- список не упорядочен, остаётся прежняя сортировка.
function M.times(len,curves,extra,job)
 local head={0,len};for _,t in ipairs(extra or {})do head[#head+1]=t end;table.sort(head)
 local lists={head};local sorted=true
 for _,curve in pairs(curves or {}) do
  local ts={};local previous=-math.huge
  for i,p in ipairs(curve.points or {})do
   local t=p.t;ts[i]=t;if t<previous then sorted=false end;previous=t
   if job and i%4096==0 then job:checkpoint() end
  end
  lists[#lists+1]=ts
 end
 local out={};local last=-1
 if not sorted then
  local all={};for _,list in ipairs(lists)do for _,t in ipairs(list)do all[#all+1]=t end end
  table.sort(all)
  for _,t in ipairs(all)do if t>=0 and t<=len and t>last+1e-9 then out[#out+1]=t;last=t end end
  return out
 end
 local k=#lists;local at={};for i=1,k do at[i]=1 end;local count=0
 while true do
  local best,from
  for i=1,k do local v=lists[i][at[i]];if v~=nil and (best==nil or v<best) then best,from=v,i end end
  if not from then break end
  at[from]=at[from]+1
  if best>=0 and best<=len and best>last+1e-9 then out[#out+1]=best;last=best end
  count=count+1;if job and count%1024==0 then job:checkpoint() end
 end
 return out
end
-- Значение кривой (cleanup.lua M.value) для возрастающих t: указатель идёт вперёд, а не двоичный поиск на каждой точке;
-- выбранная пара точек и формула те же (последняя точка с t<=момента, не дальше предпоследней).
local function cursor(curve)
 local p=curve and curve.points;local n=p and #p or 0;local lo=1
 return function(t)
  if n==0 then return 0 end
  if t<=0 or t>=p[n].t then return 0 end
  while lo+1<n and p[lo+1].t<=t do lo=lo+1 end
  local a=p[lo];local b=p[lo+1] or a -- одна точка: те же p[lo]/p[hi], что у двоичного поиска (NaN при 0 < t < p.t, как в Cleanup.value)
  return a.db+(b.db-a.db)*(t-a.t)/(b.t-a.t)
 end
end
M.cursor=cursor
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
 local times=M.times(data.len,layers,nil,job)
 local cursors={};for _,curve in pairs(layers)do cursors[#cursors+1]=cursor(curve) end -- порядок слагаемых как у pairs(layers)
 local points,peak,count=out.points,0,#cursors
 for i=1,#times do
  local t=times[i];local db=0;for c=1,count do db=db+cursors[c](t) end
  points[i]={t=t,db=db};local mag=db<0 and -db or db;if mag>peak then peak=mag end
  if job and i%256==0 then job:checkpoint() end
 end
 out.max_db=peak
 out.shapes=shapes(layers)
 return out
end
function M.patch(data,old,new,range,job)
 local a,b=range[1],range[2];local fade=math.min(.015,(b-a)/4)
 local out={points={},max_db=0,hop=new.hop}
 local extra={a,b,a+fade,b-fade}
 local times=M.times(data.len,{old=old,new=new},extra,job)
 local old_at,new_at=cursor(old),cursor(new);local at_a,at_b=M.value(old,a),M.value(old,b)
 local points,peak=out.points,0
 for i=1,#times do
  local t=times[i]
  local db=old_at(t)
  if t>=a and t<=b then
   local mix=fade>0 and math.max(0,math.min(1,(t-a)/fade,(b-t)/fade)) or 1
   local edge=t-a<=b-t and at_a or at_b
   db=edge+(new_at(t)-edge)*mix
  end
  points[i]={t=t,db=db};local mag=db<0 and -db or db;if mag>peak then peak=mag end
  if job and i%256==0 then job:checkpoint() end
 end
 out.max_db=peak
 -- Bezier fades survive only where the patch leaves their curve untouched.
 local kept={}
 for _,shape in ipairs(old and old.shapes or {})do if shape.b<=a or shape.a>=b then kept[#kept+1]=shape end end
 for _,shape in ipairs(new.shapes or {})do if shape.a>=a+fade and shape.b<=b-fade or a<=0 and b>=data.len then kept[#kept+1]=shape end end
 if #kept>0 then table.sort(kept,function(x,y)return x.a<y.a end);out.shapes=kept end
 return out
end
function M.changed(data,a,b,job)
 local times=M.times(data.len,{a=a,b=b},nil,job);local at_a,at_b=cursor(a),cursor(b)
 for i=1,#times do
  local t=times[i]
  if math.abs(at_a(t)-at_b(t))>1e-6 then return true end
  if job and i%256==0 then job:checkpoint() end
 end
 return false
end
return M
