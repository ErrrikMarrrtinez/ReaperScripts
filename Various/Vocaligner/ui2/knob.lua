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
local function toCurve(v,c) return clamp((v-c.min)/(c.max-c.min),0,1)^c.scaling end
local function fromCurve(t,c) return c.min+t^(1/c.scaling)*(c.max-c.min) end
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
function M.control(im,ctx,owner,e,meter)
  local sp=sprite(im,ctx,M.skin);if not sp then return 0 end
  local ring=meter and sprite(im,ctx,M.ring) or nil
  local key,label,lo,hi,fmt,tip=e[1],e[2],e[3],e[4],e[5],e[6]
  local c={min=lo,max=hi,scaling=CFG.scaling}
  local default=Settings.defaults[key];if default==nil then default=lo end
  local value=owner.cfg[key]
  local w,h=sp.fw*M.scale,sp.fh*M.scale
  local text=fmt:format(value)
  local lw,vw=im.CalcTextSize(ctx,label),im.CalcTextSize(ctx,text)
  local cw=math.max(w,lw,vw,70)
  local st=drag[key] or {};drag[key]=st

  im.BeginGroup(ctx)
  local x0,y0=im.GetCursorScreenPos(ctx)
  im.SetCursorScreenPos(ctx,x0+(cw-lw)/2,y0)
  im.TextDisabled(ctx,label)
  local _,ly=im.GetCursorScreenPos(ctx)
  local kx,ky=math.floor(x0+(cw-w)/2),math.floor(ly+2)
  im.SetCursorScreenPos(ctx,kx,ky)
  im.InvisibleButton(ctx,'##knob_'..key,w,h)
  local hovered,active=im.IsItemHovered(ctx),im.IsItemActive(ctx)
  local changed,released=false,false

  if im.IsItemClicked(ctx,0) then
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
  elseif hovered then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
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

  if changed then owner.cfg[key]=value;W.changed(owner,key) end
  if st.release_at and not active and r.time_precise()>=st.release_at then st.release_at=nil;released=true end
  if released then owner:control_released() end

  local dl=im.GetWindowDrawList(ctx)
  frame(im,dl,sp,toCurve(value,c)*(sp.frames-1)+.5,kx,ky,kx+w,ky+h)
  if ring then
    local level=meter()
    if level then
      local k=M.ring_scale;local dw,dh=w*k,h*k;local ox,oy=kx+(w-dw)/2,ky+(h-dh)/2
      frame(im,dl,ring,clamp(level,0,1)*(ring.frames-1)+.5,ox,oy,ox+dw,oy+dh,0xFFFFFF00|math.floor(255*M.ring_alpha))
    end
  end
  if tip and hovered then im.SetTooltip(ctx,tip) end

  text=fmt:format(value)
  vw=im.CalcTextSize(ctx,text)
  im.SetCursorScreenPos(ctx,x0+(cw-vw)/2,ky+h+2)
  im.Text(ctx,text)
  im.EndGroup(ctx)
  return cw
end
return M
