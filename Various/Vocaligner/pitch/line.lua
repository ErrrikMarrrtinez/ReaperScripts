-- @noindex
-- Line: ручная коррекция точками, как Manual Correction в ReaTune. Линия — ломаная из опорных точек
-- (абсолютная высота во времени); на её отрезке голос ведётся ровно по прямым между точками.
-- Хранится как штрих Draw (target=true, line=true) в каждой ноте, которую задевает, со значениями минус n.shift —
-- поэтому применение, ReaPitch, Undo и сохранение идут тем же путём, что у Draw. Копии одной линии делят id.
local import=...;local Notes=import('pitch/notes');local Curve=import('pitch/curve');local M={}
M.FADE=.02 -- плавный вход/выход за крайними точками (с)
M.MIN_GAP=.005 -- минимум между соседними точками (с)
-- все линии: id -> {id, points (абсолютная высота), notes={ids}}
function M.collect(notes)
  local out,order={},{}
  for _,n in ipairs(notes or {}) do for _,s in ipairs(n.drawings or {}) do if s.line and s.id then
    local l=out[s.id]
    if not l then
      local pts={};for i,p in ipairs(s.points) do pts[i]={t=p.t,value=p.value+(n.shift or 0)} end
      l={id=s.id,points=pts,notes={}};out[s.id]=l;order[#order+1]=l
    end
    l.notes[#l.notes+1]=n.id
  end end end
  table.sort(order,function(a,b) return a.points[1].t<b.points[1].t end)
  return order,out
end
function M.next_id(notes)
  local serial=0;for _,n in ipairs(notes or {}) do for _,s in ipairs(n.drawings or {}) do serial=math.max(serial,s.id or 0) end end
  return serial+1
end
function M.remove(notes,id)
  for _,n in ipairs(notes or {}) do if n.drawings then
    for i=#n.drawings,1,-1 do if n.drawings[i].id==id then table.remove(n.drawings,i) end end
    if #n.drawings==0 then n.drawings=nil end
  end end
end
-- линейная высота линии в момент t (nil вне её)
function M.value(points,t)
  if t<points[1].t or t>points[#points].t then return nil end
  for i=2,#points do local a,b=points[i-1],points[i]
    if t<=b.t then local u=(t-a.t)/math.max(1e-9,b.t-a.t);return a.value+(b.value-a.value)*u end
  end
  return points[#points].value
end
-- записать линию id с точками points (абсолютная высота) во все ноты, которые она задевает.
-- false, причина — если линия не легла (нет нот под ней, лимит штрихов)
function M.place(notes,id,points,len)
  M.remove(notes,id)
  if #points<2 then return true end
  local start=math.max(0,points[1].t-M.FADE);local finish=points[#points].t+M.FADE;if len then finish=math.min(len,finish) end
  if finish<=start or points[#points].t-points[1].t<.01 then return false,'Line is too short' end
  local capture=Curve.capture_anchors(notes);local placed=false
  for _,n in ipairs(notes) do if finish>n.start and start<n.finish then
    if #(n.drawings or {})>=64 then return false,'Line: this note already has 64 drawings. Reset old ones first.' end
    local pts={};for i,p in ipairs(points) do pts[i]={t=p.t,value=p.value-(n.shift or 0)} end
    n.drawings=n.drawings or {}
    n.drawings[#n.drawings+1]={start=start,finish=finish,points=pts,target=true,line=true,support_version=3,id=id,curve_notes=capture}
    placed=true
  end end
  if not placed then return false,'Line must cross a note' end
  return true
end
-- попадание мышью: точка (r px) или отрезок (s px); tx/py — время/высота -> экран
function M.hit(lines,mx,my,tx,py,r,s)
  r=r or 7;s=s or 5
  local best,bd
  for _,l in ipairs(lines) do for i,p in ipairs(l.points) do
    local d=math.abs(mx-tx(p.t))+math.abs(my-py(p.value))
    if math.abs(mx-tx(p.t))<=r and math.abs(my-py(p.value))<=r and (not bd or d<bd) then best,bd={line=l,index=i},d end
  end end
  if best then return best end
  for _,l in ipairs(lines) do for i=2,#l.points do
    local a,b=l.points[i-1],l.points[i];local ax,ay,bx,by=tx(a.t),py(a.value),tx(b.t),py(b.value)
    local dx,dy=bx-ax,by-ay;local L=dx*dx+dy*dy
    local u=L>0 and math.max(0,math.min(1,((mx-ax)*dx+(my-ay)*dy)/L)) or 0
    local qx,qy=ax+dx*u,ay+dy*u
    if (mx-qx)^2+(my-qy)^2<=s*s then return {line=l,segment=i,t=a.t+(b.t-a.t)*u,value=a.value+(b.value-a.value)*u} end
  end end
end
return M
