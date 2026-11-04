-- @noindex
local import=...;local Wave=import('pitch/waveform');local M={budget=math.huge}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
-- Absolute pitch, independent of viewport and selection. Fractional pitch
-- changes interpolate between palette stops every five semitones.
local STOPS={{65,115,223},{154,83,216},{237,87,136},{233,68,64},{244,153,65}} -- палитра вынесена: без таблиц на каждый вызов
local floor=math.floor
function M.color(p,selected,alpha)
  local u=((p-48)/5)%8;if u>4 then u=8-u end
  local i=floor(u)+1;if i>4 then i=4 end;u=u-i+1;u=u*u*(3-2*u)
  local a,b=STOPS[i],STOPS[i+1];local v=1-u
  local c1,c2,c3=a[1]*v+b[1]*u,a[2]*v+b[2]*u,a[3]*v+b[3]*u
  if selected then c1,c2,c3=c1+(255-c1)*.23,c2+(255-c2)*.23,c3+(255-c3)*.23 end
  return floor(c1+.5)<<24|floor(c2+.5)<<16|floor(c3+.5)<<8|(alpha or 255)
end
-- уровень зависит только от масштаба вида: один log на кадр, а не на каждую ноту
local lv_span,lv_width,lv
local function level_of(span,width)
  if span~=lv_span or width~=lv_width then lv_span,lv_width=span,width;lv=floor(math.log(math.max(1e-4,span/width*3),2)+.5) end
  return lv
end
-- Cached silhouette per note. Samples sit on an absolute time grid whose step is quantised to a power of two
-- (about 3 px at the current zoom), so scrolling never invalidates it and zooming rebuilds it only when the
-- level changes. It covers one extra screen on each side of the view; drawing clips to the visible range.
function M.shape(cache,key,data,a,b,start,span,width,lite)
  local level=level_of(span,width)
  if lite then level=level+1 end -- пока вид едет, новые силуэты строятся вдвое грубее
  if level<-6 then level=-6 end -- приближение не уточняет силуэт: шаг не мельче ~16 мс (кадр анализа), блоки остаются упрощёнными
  -- проверка кэша — на каждом кадре для каждой видимой ноты: сравнения вместо math.max/min и без 2^level до промаха
  local lo,hi=a>start and a or start,b<start+span and b or start+span
  local prior=cache[key]
  local same=prior and prior.data==data and prior.frames==data.frames and prior.count==#data.frames and prior.a==a and prior.b==b
  if same and (prior.level==level or lite) and prior.w0<=lo+1e-9 and prior.w1>=hi-1e-9 then return prior end
  -- бюджет пересборок на кадр (M.budget, задаёт pitch/ui): исчерпан — рисуем прежний силуэт той же ноты, уточнится позже
  if same and M.budget<=0 then return prior end
  if M.budget<=0 then level=level+1 else M.budget=M.budget-1 end -- бюджета нет: грубый силуэт, уточнится при свободном бюджете
  local step=2^level
  local w0,w1=math.max(a,start-span),math.min(b,start+span*2)
  if w1<=w0 then w0,w1=lo,math.max(lo+1e-4,hi) end
  local lo_all,hi_all=Wave.range(data,a,b);local gain=1/math.max(.001,math.abs(lo_all),math.abs(hi_all))
  local times={w0}
  for i=math.ceil(w0/step+1e-9),math.floor(w1/step-1e-9) do local t=i*step;if t>w0+1e-9 and t<w1-1e-9 then times[#times+1]=t end end
  times[#times+1]=w1
  local n=#times;local raw={}
  for i=1,n do
    local t=times[i]
    local l,h=Wave.range(data,math.max(a,t-step*.65),math.min(b,t+step*.65))
    raw[i]={math.max(0,h)*gain,math.max(0,-l)*gain}
  end
  local out={data=data,frames=data.frames,count=#data.frames,a=a,b=b,level=level,w0=w0,w1=w1}
  local taper=step*1.17 -- закругление торцов ~3.5 px при создании
  for i=1,n do
    local upper,lower=0,0
    for k=-2,2 do local r=raw[math.max(1,math.min(n,i+k))];local w=3-math.abs(k);upper=upper+r[1]*w/9;lower=lower+r[2]*w/9 end
    local t=times[i]
    local edge=clamp(math.min(t-a,b-t)/taper,0,1)
    local cap=math.sqrt(math.max(0,1-(1-edge)^2))
    out[#out+1]={t=t,upper=upper*cap,lower=lower*cap}
  end
  cache[key]=out;return out
end
-- индексы точек силуэта для окна [vt0,vt1] (+ по точке за краями); без окна — весь силуэт
local function range(shape,vt0,vt1)
  local i0,i1=1,#shape
  if vt0 then
    local lo,hi=1,#shape
    while lo<hi do local mid=(lo+hi+1)//2;if shape[mid].t<=vt0 then lo=mid else hi=mid-1 end end
    i0=lo
    lo,hi=i0,#shape
    while lo<hi do local mid=(lo+hi)//2;if shape[mid].t>=vt1 then hi=mid else lo=mid+1 end end
    i1=hi
  end
  return i0,i1
end
-- Пределы силуэта (доли half сверху и снизу) по всем его точкам: для упрощённой отрисовки прямоугольником
local function extent(shape)
  local eu=shape.eu
  if not eu then
    local el=0;eu=0
    for i=1,#shape do local p=shape[i];if p.upper>eu then eu=p.upper end;if p.lower>el then el=p.lower end end
    shape.eu,shape.el=eu,el
  end
  return eu,shape.el
end
M.extent=extent
-- Упрощённый блок: прямоугольник по пределам силуэта (узкие ноты или «слишком много нот»). На ширине в 1–4 px
-- силуэт и так выглядит столбиком, а стоит один вызов вместо десятков точек пути.
function M.rect(im,dl,shape,ax,bx,yy,half,color,hover,outline,lw)
  if #shape<2 then return end
  local eu,el=extent(shape);if eu+el<1e-8 then return end
  local y0,y1=yy-eu*half,yy+el*half;if y1-y0<1 then local c=(y0+y1)*.5;y0,y1=c-.5,c+.5 end
  if bx-ax<1 then local c=(ax+bx)*.5;ax,bx=c-.5,c+.5 end
  if hover then im.DrawList_AddRect(dl,ax-1,y0-1,bx+1,y1+1,0xBEC5CEA0,1,0,2) end
  im.DrawList_AddRectFilled(dl,ax,y0,bx,y1,color,1)
  if outline then local o=(lw or 1)*.5;im.DrawList_AddRect(dl,ax-o,y0-o,bx+o,y1+o,outline,1,0,lw or 1) end -- наружу от края блока
end
local scratch={} -- общий буфер точек: r.new_array копирует его, поэтому таблица не создаётся на каждую ноту
-- Точки контура в экранных координатах (верх слева направо, низ справа налево) — те же, что клал путь:
-- повторы подряд и замыкающая точка, совпадающая с первой, пропускаются. nil — рисовать нечего.
-- Возвращает общий буфер: он действителен до следующего вызова.
local function outline_points(shape,tx,yy,half,i0,i1)
  local area=0
  for i=i0,i1 do local p=shape[i];area=area+p.upper+p.lower end
  if area<1e-8 then return nil end
  local pts=scratch;local k=0;local lx,ly,fx,fy
  local x0=tx(0);local kx=tx(1)-x0 -- tx линейна: без вызова замыкания на каждую точку
  for i=i0,i1 do local p=shape[i];local x,y=x0+kx*p.t,yy-p.upper*half
    if x~=lx or y~=ly then pts[k+1]=x;pts[k+2]=y;k=k+2;lx,ly=x,y;if not fx then fx,fy=x,y end end
  end
  for i=i1,i0,-1 do local p=shape[i];local x,y=x0+kx*p.t,yy+p.lower*half
    if (x~=lx or y~=ly) and not (i==i0 and x==fx and y==fy) then pts[k+1]=x;pts[k+2]=y;k=k+2;lx,ly=x,y end
  end
  for q=#pts,k+1,-1 do pts[q]=nil end
  return pts
end
M.outline_points=outline_points
-- r, stamp (необязательно): массив REAPER с контуром кэшируется в силуэте и переиспользуется, пока не меняются
-- вид (stamp), положение (tx(0), yy, half) и окно; тогда кадр стоит 1–3 вызова на ноту без обхода точек.
-- lw (необязательно): толщина обводки outline, по умолчанию 1 (выделенные ноты рисуются толще)
function M.draw(im,dl,shape,tx,yy,half,color,hover,outline,vt0,vt1,r,stamp,lw)
  if #shape<2 then return end
  local closed=im.DrawFlags_Closed or 1
  local fill=r and stamp and im.DrawList_AddConcavePolyFilled
  if fill then
    local x0=tx(0);local g=shape.geo
    if not (g and g.stamp==stamp and g.x0==x0 and g.yy==yy and g.half==half and g.vt0==vt0 and g.vt1==vt1) then
      local i0,i1=range(shape,vt0,vt1)
      local pts=i1-i0>=1 and outline_points(shape,tx,yy,half,i0,i1)
      if not g then g={};shape.geo=g end -- одна таблица на силуэт, поля обновляются на месте
      g.stamp,g.x0,g.yy,g.half,g.vt0,g.vt1=stamp,x0,yy,half,vt0,vt1;g.arr=pts and #pts>=4 and r.new_array(pts) or false
    end
    local arr=g.arr;if not arr then return end
    if hover then im.DrawList_AddPolyline(dl,arr,0xBEC5CEA0,closed,2) end
    local under=outline and lw and lw>1 and color&255==255 -- непрозрачная заливка закроет внутреннюю половину: толщина только наружу
    if under then im.DrawList_AddPolyline(dl,arr,outline,closed,lw*2) end
    fill(dl,arr,color)
    if outline and not under then im.DrawList_AddPolyline(dl,arr,outline,closed,lw or 1) end
    return
  end
  -- рисуем только видимый диапазон времени [vt0,vt1] (+ по точке за краем, чтобы контур был непрерывным)
  local i0,i1=range(shape,vt0,vt1)
  if i1-i0<1 then return end
  local area=0
  for i=i0,i1 do local p=shape[i];area=area+p.upper+p.lower end
  if area<1e-8 then return end
  -- путь кладётся прямо в drawlist: без таблицы точек и замыканий на каждый кадр
  local function path()
    im.DrawList_PathClear(dl)
    local lx,ly,fx,fy
    for i=i0,i1 do local p=shape[i];local x,y=tx(p.t),yy-p.upper*half
      if x~=lx or y~=ly then im.DrawList_PathLineTo(dl,x,y);lx,ly=x,y;if not fx then fx,fy=x,y end end
    end
    for i=i1,i0,-1 do local p=shape[i];local x,y=tx(p.t),yy+p.lower*half
      -- замыкающая точка, совпадающая с первой, даёт нулевой сегмент и «зубец» на толстой обводке: пропускаем
      if (x~=lx or y~=ly) and not (i==i0 and x==fx and y==fy) then im.DrawList_PathLineTo(dl,x,y);lx,ly=x,y end
    end
  end
  -- Halo behind the fill; unlike a rectangle it follows each rounded lobe.
  if hover then path();im.DrawList_PathStroke(dl,0xBEC5CEA0,closed,2) end
  local under=outline and lw and lw>1 and color&255==255
  if under then path();im.DrawList_PathStroke(dl,outline,closed,lw*2) end
  path();im.DrawList_PathFillConcave(dl,color)
  if outline and not under then path();im.DrawList_PathStroke(dl,outline,closed,lw or 1) end
end
return M
