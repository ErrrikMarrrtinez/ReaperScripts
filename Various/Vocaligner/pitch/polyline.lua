-- @noindex
-- Cached polylines: a contour is split into runs once per view/data state and every frame costs one
-- DrawList_AddPolyline call per run instead of one AddLine per segment (and no per-point Lua work).
local M={}
local floor=math.floor
-- Видимый диапазон списка, отсортированного по start (ноты не пересекаются, поэтому finish тоже растёт):
-- первый индекс с finish>=a и последний с start<=b; пусто — i1<i0. Вместо обхода всех нот с проверкой границ.
function M.range(list,a,b)
  local n=#list;local lo,hi=1,n+1
  while lo<hi do local mid=(lo+hi)//2;if list[mid].finish<a then lo=mid+1 else hi=mid end end
  local i0=lo;lo,hi=i0,n+1
  while lo<hi do local mid=(lo+hi)//2;if list[mid].start<=b then lo=mid+1 else hi=mid end end
  return i0,lo-1
end
-- Прореживание плоского списка {x1,y1,x2,y2,...} по пиксельным столбцам, на месте: в каждом столбце остаются
-- первая, нижняя, верхняя и последняя точки (в исходном порядке). На экране неотличимо, точек — не больше 4 на пиксель.
-- Запись всегда не правее чтения, поэтому новый список не нужен (меньше мусора при скролле).
function M.decimate(pts)
  local n=#pts//2;if n<=4 then return pts end
  local extent=pts[2*n-1]-pts[1];if extent<0 then extent=-extent end
  if n<=extent+2 then return pts end -- в среднем не больше точки на пиксель: прореживать нечего, лишний проход не нужен
  local k=0;local i=1
  while i<=n do
    local col=floor(pts[2*i-1]);local j=i
    while j<n and floor(pts[2*j+1])==col do j=j+1 end
    if j-i<=3 then
      if k~=2*i-2 then for q=i,j do pts[k+1],pts[k+2]=pts[2*q-1],pts[2*q];k=k+2 end else k=2*j end
    else
      local lo,hi=i,i;local ylo,yhi=pts[2*i],pts[2*i]
      for q=i+1,j do local y=pts[2*q];if y<ylo then lo,ylo=q,y end;if y>yhi then hi,yhi=q,y end end
      local a,b=lo,hi;if a>b then a,b=b,a end
      pts[k+1],pts[k+2]=pts[2*i-1],pts[2*i];k=k+2
      if a~=i and a~=j then pts[k+1],pts[k+2]=pts[2*a-1],pts[2*a];k=k+2 end
      if b~=i and b~=j and b~=a then pts[k+1],pts[k+2]=pts[2*b-1],pts[2*b];k=k+2 end
      pts[k+1],pts[k+2]=pts[2*j-1],pts[2*j];k=k+2
    end
    i=j+1
  end
  for q=#pts,k+1,-1 do pts[q]=nil end
  return pts
end
local function same(c,list,view,offset,ykey)
  return c and c.list==list and c.n==#list and c.offset==offset and c.ykey==ykey and c.start==view.start and c.span==view.span
    and c.top==view.top and c.rows==view.rows and c.left==view.left and c.ty==view.ty and c.width==view.width and c.height==view.height
end
local function build(r,list,ykey,tx,py,thick_a,thick_b,vlo,vhi)
  -- список может покрывать несколько экранов: берём только видимый диапазон времени (+ по точке за краями)
  local i0,i1=1,#list
  if vlo then
    local lo,hi=1,#list
    while lo<hi do local mid=(lo+hi+1)//2;if (list[mid].t or 0)<=vlo then lo=mid else hi=mid-1 end end
    i0=lo
    lo,hi=i0,#list
    while lo<hi do local mid=(lo+hi)//2;if (list[mid].t or 0)>=vhi then hi=mid else lo=mid+1 end end
    i1=hi
  end
  -- tx/py линейны: коэффициенты снимаются один раз, и точка стоит два умножения вместо двух вызовов замыканий
  local x0,y0=tx(0),py(0);local kx,ky=tx(1)-x0,py(1)-y0
  local segs,cur,prev={},nil,nil
  -- массив REAPER строится из готовой таблицы одним вызовом (а не записью каждого элемента через C)
  local function close() if cur and #cur.pts>=4 then
    segs[#segs+1]={arr=r.new_array(M.decimate(cur.pts)),th=cur.th}
  end;cur=nil end
  for idx=i0,i1 do local p=list[idx]
    if prev and p.run and prev.run==p.run then
      local th=(ykey=='pitch' and p.supported and prev.supported) and thick_a or thick_b
      if not cur or cur.th~=th then
        close();cur={th=th,pts={x0+kx*prev.t,y0+ky*prev[ykey]}}
      end
      local pts=cur.pts;local k=#pts;pts[k+1]=x0+kx*p.t;pts[k+2]=y0+ky*p[ykey]
    else close() end
    prev=p
  end
  close()
  return segs
end
-- cache: table owned by the caller (per slot); view: table with start,span,top,rows,left,ty,width,height of this frame.
-- ykey: 'pitch' or 'raw'. Returns false if the native polyline API is unavailable (caller falls back to AddLine).
function M.stroke(im,dl,r,cache,slot,list,view,offset,ykey,tx,py,col,thick_a,thick_b)
  if not (im.DrawList_AddPolyline and r.new_array) then return false end
  local c=cache[slot]
  if not same(c,list,view,offset,ykey) then
    c={list=list,n=#list,offset=offset,ykey=ykey,start=view.start,span=view.span,top=view.top,rows=view.rows,left=view.left,ty=view.ty,
      width=view.width,height=view.height,segs=build(r,list,ykey,tx,py,thick_a,thick_b,view.start-offset,view.start+view.span-offset)}
    cache[slot]=c
  end
  local segs=c.segs
  for i=1,#segs do local s=segs[i];im.DrawList_AddPolyline(dl,s.arr,col,0,s.th) end
  return true
end
return M
