-- @noindex
local import=...;local Wave=import('pitch/waveform');local M={}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
-- Absolute pitch, independent of viewport and selection. Fractional pitch
-- changes interpolate between palette stops every five semitones.
function M.color(p,selected,alpha)
  local stops={{65,115,223},{154,83,216},{237,87,136},{233,68,64},{244,153,65}}
  local u=((p-48)/5)%8;if u>4 then u=8-u end
  local i=math.min(4,math.floor(u)+1);u=u-i+1;u=u*u*(3-2*u)
  local rgb={};for k=1,3 do local c=stops[i][k]*(1-u)+stops[i+1][k]*u;rgb[k]=math.floor(c+(selected and (255-c)*.23 or 0)+.5) end
  return rgb[1]<<24|rgb[2]<<16|rgb[3]<<8|(alpha or 255)
end
-- Cached silhouette per note. Samples sit on an absolute time grid whose step is quantised to a power of two
-- (about 3 px at the current zoom), so scrolling never invalidates it and zooming rebuilds it only when the
-- level changes. It covers one extra screen on each side of the view; drawing clips to the visible range.
function M.shape(cache,key,data,a,b,start,span,width,lite)
  local step_t=math.max(1e-4,span/width*3)
  local level=math.floor(math.log(step_t,2)+.5)
  if lite then level=level+1 end -- пока вид едет, новые силуэты строятся вдвое грубее
  level=math.max(level,-6) -- приближение не уточняет силуэт: шаг не мельче ~16 мс (кадр анализа), блоки остаются упрощёнными
  local step=2^level
  local lo,hi=math.max(a,start),math.min(b,start+span)
  local prior=cache[key]
  if prior and prior.data==data and prior.frames==data.frames and prior.count==#data.frames and prior.a==a and prior.b==b
    and (prior.level==level or lite) and prior.w0<=lo+1e-9 and prior.w1>=hi-1e-9 then return prior end
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
function M.draw(im,dl,shape,tx,yy,half,color,hover,outline,vt0,vt1)
  if #shape<2 then return end
  -- рисуем только видимый диапазон времени [vt0,vt1] (+ по точке за краем, чтобы контур был непрерывным)
  local i0,i1=1,#shape
  if vt0 then
    local lo,hi=1,#shape
    while lo<hi do local mid=(lo+hi+1)//2;if shape[mid].t<=vt0 then lo=mid else hi=mid-1 end end
    i0=lo
    lo,hi=i0,#shape
    while lo<hi do local mid=(lo+hi)//2;if shape[mid].t>=vt1 then hi=mid else lo=mid+1 end end
    i1=hi
  end
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
  local closed=im.DrawFlags_Closed or 1
  -- Halo behind the fill; unlike a rectangle it follows each rounded lobe.
  if hover then path();im.DrawList_PathStroke(dl,0xBEC5CEA0,closed,2) end
  path();im.DrawList_PathFillConcave(dl,color)
  if outline then path();im.DrawList_PathStroke(dl,outline,closed,1) end
end
return M
