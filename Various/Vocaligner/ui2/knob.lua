-- @noindex
-- Кноб на спрайте-плёнке для нового интерфейса. Механика 1 в 1 из KnobBrowser (тестовый скрипт владельца):
-- перетаскивание вверх/вниз без округления с накоплением дельты (на Windows с JS API курсор прячется и
-- возвращается в точку клика каждый кадр), колесо, Shift / Ctrl / Ctrl+Shift = точнее, двойной клик = сброс.
-- Поверх кноба рисуется кольцо-метр (спрайт с вырезанным телом): его дугу ведёт уровень детектора, а не значение.
-- Модуль устроен как набор независимых виджетов: сейчас используется для порога Compressor/Gate,
-- вернуть обычный слайдер = не вызывать Knob.control (в ui2/dynamics.lua остался прежний путь).
local import=...;local Settings=import('compressor/settings');local W=import('ui2/widgets');local M={}
local r=reaper
local here=debug.getinfo(1,'S').source:match([[^@(.+[\/])]])
M.dir=here..'assets/knobs/'

-- Что рисуем. Сменить кноб = поменять файл здесь (плёнка вертикальная, кадры квадратные; иначе задайте cellw/cellh/frames).
M.skin={file='BigGreen.png'}                 -- сам кноб
M.ring={file='BigBlue_ring.png'}             -- кольцо-метр поверх (nil = не рисовать). Строится ui-proto/build_knob_ring.py
M.scale=1                                    -- размер относительно спрайта (58 px при 1)
M.ring_scale=1                               -- размер кольца относительно кноба (1 = точно поверх)
M.ring_alpha=0.95
local CFG={dragSens=.25,dragFine=.025,wheelSens=1,wheelFine=.1,scaling=1,horizontal=false}

local function clamp(v,lo,hi) return v<lo and lo or (v>hi and hi or v) end
local IS_WIN=(r.GetOS() or ''):match('^Win')~=nil
local WARP=IS_WIN and r.JS_Mouse_SetPosition~=nil

-- ===== спрайты =====
local imgs,ctx_
local function layout(sp,hint)
  hint=hint or {};local w,h,n=sp.w,sp.h,hint.frames
  local vertical=h>=w;local fw,fh=hint.cellw,hint.cellh
  if not fw and not fh then
    if n then if vertical then fw,fh=w,h/n else fw,fh=w/n,h end else fw=math.min(w,h);fh=fw end
  elseif not fw then fw=vertical and w or (n and w/n or fh)
  elseif not fh then fh=(not vertical) and h or (n and h/n or fw) end
  sp.fw=clamp(math.floor(fw),1,w);sp.fh=clamp(math.floor(fh),1,h)
  sp.cols=math.max(1,w//sp.fw)
  local total=sp.cols*math.max(1,h//sp.fh);sp.frames=math.min(n or total,total)
end
local function sprite(im,ctx,def)
  if not def then return nil end
  if ctx_~=ctx then imgs={};ctx_=ctx end
  local e=imgs[def.file]
  if e then return e.img and e or nil end
  e={};imgs[def.file]=e
  local ok,img=pcall(im.CreateImage,M.dir..def.file)
  if not ok or not img then return nil end
  im.Attach(ctx,img)
  local w,h=im.Image_GetSize(img)
  e.img,e.w,e.h=img,math.floor(w),math.floor(h);layout(e,def)
  return e
end
local function frame(im,dl,sp,i,x1,y1,x2,y2,col)
  i=clamp(math.floor(i),0,sp.frames-1)
  local u0=(i%sp.cols)*sp.fw/sp.w;local v0=(i//sp.cols)*sp.fh/sp.h
  im.DrawList_AddImage(dl,sp.img,x1,y1,x2,y2,u0,v0,u0+sp.fw/sp.w,v0+sp.fh/sp.h,col or 0xFFFFFFFF)
end
function M.available(im,ctx) return sprite(im,ctx,M.skin)~=nil end

-- ===== кривая и чувствительность =====
-- c.log: логарифмическая шкала (ratio 1..100, частоты); иначе степенная кривая c.scaling
local function toCurve(v,c)
  if c.log then local lo=math.max(c.min,1e-6);return clamp(math.log(math.max(v,lo)/lo)/math.log(c.max/lo),0,1) end
  return clamp((v-c.min)/(c.max-c.min),0,1)^c.scaling
end
local function fromCurve(t,c)
  if c.log then local lo=math.max(c.min,1e-6);return lo*(c.max/lo)^t end
  return c.min+t^(1/c.scaling)*(c.max-c.min)
end
-- Shift = fine, Ctrl = fine*0.5, Ctrl+Shift = fine*0.25
local function sensitivity(im,ctx,normal,fine)
  local m,ctrl,shift=im.GetKeyMods(ctx),im.Mod_Ctrl,im.Mod_Shift
  if m==(ctrl|shift) then return fine*.25 end
  if m==ctrl then return fine*.5 end
  if m==shift then return fine end
  return normal
end

-- ===== виджет =====
local drag={}
-- e = {key,label,lo,hi,fmt,tip}; owner = cleaner (cfg, settings_changed, control_released, gesture);
-- meter() -> 0..1 или nil: уровень, которым ведётся кольцо поверх кноба. Возвращает ширину виджета.
-- o (необязательно): skin/ring — свои спрайты ({file=...}), scale, log=true | scaling=число, width — ширина ячейки
-- (кноб по центру), value_col — цвет значения, step — шаг значения (0.1 = десятые),
-- float=true — значение не строкой под кнобом, а плавающей плашкой под ним при наведении/движении (светлая плашка, тёмный текст),
-- below=true — подпись не над кнобом, а под ним. Без o — как раньше.
-- Светлая плашка значения (сверху всего): cx — центр по X, by — верх; small — чуть мельче. Общий стиль для кнобов и перетаскиваний.
function M.plate(im,ctx,cx,by,text,small,orange,above)
  local fg=im.GetForegroundDrawList and im.GetForegroundDrawList(ctx) or im.GetWindowDrawList(ctx)
  local th=im.GetFontSize(ctx);local fs=math.max(8,th-(small and 3 or 2));local tw=im.CalcTextSize(ctx,text)*fs/th
  local pd=small and 5 or 7
  local bw,bh=math.floor(tw+pd*2),math.floor(fs+(small and 6 or 8))
  local bx=math.floor(cx-bw/2);by=math.floor(above and by-bh or by) -- above: by — нижний край плашки
  im.DrawList_AddRectFilled(fg,bx,by,bx+bw,by+bh,0xE9E9E9FF,5)
  im.DrawList_AddRect(fg,bx,by,bx+bw,by+bh,0xB4B4B4FF,5)
  local col=orange and 0x7A3F00FF or 0x141414FF
  -- «жирный» текст: второй проход со сдвигом на долю пикселя
  for _,dx in ipairs({0,.7}) do
    if im.DrawList_AddTextEx and im.GetFont then im.DrawList_AddTextEx(fg,im.GetFont(ctx),fs,bx+pd+dx,by+(bh-fs)/2-2,col,text)
    else im.DrawList_AddText(fg,bx+pd+dx,by+(bh-th)/2-2,col,text) end
  end
end
-- Векторный кноб в стиле FL: тёмный диск, кольцо-дорожка и дуга значения, указатель; всё линиями ImGui (чётко при любом размере).
-- cx,cy,R — центр и радиус, t — значение 0..1 (дуга -135..135 градусов от 12 часов по часовой).
function M.vector(im,ctx,dl,cx,cy,R,t,o)
  local pi=math.pi;local a0,a1=-135*pi/180-pi/2,135*pi/180-pi/2
  local av=a0+(a1-a0)*t
  local th=math.max(2,R*.11)
  local rr=R-th/2-.5
  im.DrawList_PathArcTo(dl,cx,cy,rr,a0,a1);im.DrawList_PathStroke(dl,0x2C2C2CFF,0,th)            -- дорожка
  if t>0.003 then im.DrawList_PathArcTo(dl,cx,cy,rr,a0,av);im.DrawList_PathStroke(dl,o.arc_col or 0x8E8E8EFF,0,th) end -- значение
  local rb=R-th-R*.1
  im.DrawList_AddCircleFilled(dl,cx,cy,rb,0x242424FF,0)                                           -- корпус
  im.DrawList_AddCircle(dl,cx,cy,rb,0x383838FF,0,1)
  local sa,ca=math.cos(av),math.sin(av)
  im.DrawList_AddLine(dl,cx+sa*rb*.22,cy+ca*rb*.22,cx+sa*rb*.86,cy+ca*rb*.86,o.ptr_col or 0xCFCFCFFF,math.max(1.6,R*.07)) -- указатель
end
M.label_font=nil -- шрифт подписей под кнобами (ставит страница; nil — шрифт окна)
function M.available_skin(im,ctx,file) return sprite(im,ctx,{file=file})~=nil end
function M.control(im,ctx,owner,e,meter,o)
  o=o or {}
  -- o.vector=true: кноб рисуется векторно в ImGui (o.size — диаметр), спрайт не нужен
  local sp=not o.vector and sprite(im,ctx,o.skin or M.skin) or nil;if not sp and not o.vector then return 0 end
  local ring=meter and sprite(im,ctx,o.ring or M.ring) or nil
  local key,label,lo,hi,fmt,tip=e[1],e[2],e[3],e[4],e[5],e[6]
  local c={min=lo,max=hi,scaling=o.scaling or CFG.scaling,log=o.log or e.log}
  local default=Settings.defaults[key];if default==nil then default=lo end
  local value=owner.cfg[key]
  local scale=o.scale or M.scale
  local w,h=o.size or 0,o.size or 0
  if sp then w,h=math.floor(sp.fw*scale+.5),math.floor(sp.fh*scale+.5) end
  local text=fmt:format(value)
  local lw,vw=im.CalcTextSize(ctx,label),im.CalcTextSize(ctx,text)
  local cw=math.max(w,lw,o.float and 0 or vw,o.width or 70)
  local st=drag[key] or {};drag[key]=st

  im.BeginGroup(ctx)
  local x0,y0=im.GetCursorScreenPos(ctx)
  local ky
  if o.below then ky=math.floor(y0)
  else
    im.SetCursorScreenPos(ctx,x0+(cw-lw)/2,y0)
    im.TextDisabled(ctx,label)
    local _,ly=im.GetCursorScreenPos(ctx);ky=math.floor(ly+2)
  end
  local kx=math.floor(x0+(cw-w)/2)
  im.SetCursorScreenPos(ctx,kx,ky)
  im.InvisibleButton(ctx,'##knob_'..key,w,h)
  local hovered,active=im.IsItemHovered(ctx),im.IsItemActive(ctx)
  local changed,released=false,false

  -- старт жеста по активации элемента: срабатывает надёжно и в медленный кадр (IsItemClicked требует клика именно в этом кадре)
  if im.IsItemActivated(ctx) or (active and not st.drag) then
    local mx,my=r.GetMousePosition()
    st.drag={x=mx,y=my,t=toCurve(value,c)}
  end
  local d=st.drag
  if active and d then
    owner.gesture=true
    local dx,dy
    if WARP then -- Windows + JS: прячем курсор и возвращаем в точку клика каждый кадр
      im.SetMouseCursor(ctx,im.MouseCursor_None)
      local mx,my=r.GetMousePosition()
      dx,dy=mx-d.x,my-d.y
      r.JS_Mouse_SetPosition(d.x,d.y)
    else dx,dy=im.GetMouseDelta(ctx) end
    local delta=CFG.horizontal and dx or -dy
    if delta~=0 then
      d.t=clamp(d.t+delta/250*sensitivity(im,ctx,CFG.dragSens,CFG.dragFine),0,1) -- копим без округления
      value=fromCurve(d.t,c);changed=true
    end
  end
  if st.was_active and not active then released=true;st.drag=nil end
  st.was_active=active

  if hovered then
    local wheel=im.GetMouseWheel(ctx)
    if wheel~=0 then
      value=fromCurve(clamp(toCurve(value,c)+wheel*sensitivity(im,ctx,CFG.wheelSens,CFG.wheelFine)/45,0,1),c)
      changed=true;st.release_at=r.time_precise()+.25
    end
    if im.IsMouseDoubleClicked(ctx,0) then value,changed=default,true;st.release_at=r.time_precise() end
  end

  if changed and o.step then value=clamp(math.floor(value/o.step+.5)*o.step,lo,hi);changed=value~=owner.cfg[key] end
  if changed then owner.cfg[key]=value;W.changed(owner,key);st.flash=r.time_precise()+.8 end
  if st.release_at and not active and r.time_precise()>=st.release_at then st.release_at=nil;released=true end
  if released then owner:control_released() end

  local dl=im.GetWindowDrawList(ctx)
  -- при наведении кноб слегка вырастает (o.grow — доля размера, плавно)
  st.hv=(st.hv or 0)+(((hovered or active) and 1 or 0)-(st.hv or 0))*.3
  if math.abs((hovered or active) and 1-st.hv or st.hv)<.01 then st.hv=(hovered or active) and 1 or 0 end
  local gk=(o.grow or 0)*st.hv;local gw,gh=w*gk/2,h*gk/2
  -- o.animate: если значение сменилось не рукой (выбран другой айтем со своими настройками), кноб доворачивается
  -- плавно; свои движения (драг, колесо, двойной клик) — сразу. Анимируется только картинка, cfg не трогаем.
  local tt=toCurve(value,c);local tv=tt
  if o.animate then
    local now=r.time_precise();local adt=clamp(now-(st.vt or now),0,.1);st.vt=now
    if st.vis==nil or changed or active then st.vis=tt
    else st.vis=st.vis+(tt-st.vis)*math.min(1,adt*12);if math.abs(tt-st.vis)<.002 then st.vis=tt end end
    tv=st.vis
  end
  if o.vector then M.vector(im,ctx,dl,kx+w/2,ky+h/2,(w/2+gw),tv,o) end
  if sp then frame(im,dl,sp,tv*(sp.frames-1)+.5,kx-gw,ky-gh,kx+w+gw,ky+h+gh) end
  local pt=sp and (o.skin or M.skin).pointer
  if pt then -- полоска-указатель поверх спрайта: угол берём по тому же кадру, что и картинка (дуга -135..135 градусов, 0 — вверх)
    local i=clamp(math.floor(tv*(sp.frames-1)+.5),0,sp.frames-1)
    local a=math.rad(-135+270*i/(sp.frames-1));local sa,ca=math.sin(a),-math.cos(a)
    local R=(w/2+gw)*.99;local cx,cy=kx+w/2,ky+h/2
    im.DrawList_AddLine(dl,cx+sa*R*pt.r0,cy+ca*R*pt.r0,cx+sa*R*pt.r1,cy+ca*R*pt.r1,pt.col,math.max(1.5,w/28))
  end
  if ring then
    local level=meter()
    if level then
      local k=M.ring_scale;local dw,dh=w*k,h*k;local ox,oy=kx+(w-dw)/2,ky+(h-dh)/2
      frame(im,dl,ring,clamp(level,0,1)*(ring.frames-1)+.5,ox,oy,ox+dw,oy+dh,0xFFFFFF00|math.floor(255*M.ring_alpha))
    end
  end
  if tip and hovered and not active then im.SetTooltip(ctx,tip) end

  text=fmt:format(value)
  vw=im.CalcTextSize(ctx,text)
  if o.float then
    -- плавающая плашка значения под кнобом (поверх всего, в макет не входит)
    if hovered or active then -- сразу исчезает, как только мышь ушла
      M.plate(im,ctx,kx+w/2,ky-gh-4,text,w<50,o.value_col,true) -- над кнобом
    end
    if o.below then
      local lf=M.label_font;if lf then im.PushFont(ctx,lf) end
      local lw2=lf and im.CalcTextSize(ctx,label) or lw
      im.SetCursorScreenPos(ctx,x0+(cw-lw2)/2,ky+h+1);im.TextDisabled(ctx,label)
      if lf then im.PopFont(ctx) end
    else im.SetCursorScreenPos(ctx,x0,ky+h);im.Dummy(ctx,cw,0) end
  else
    im.SetCursorScreenPos(ctx,x0+(cw-vw)/2,ky+h+2)
    if o.value_col then im.TextColored(ctx,o.value_col,text) else im.Text(ctx,text) end
  end
  im.EndGroup(ctx)
  return cw
end
return M
