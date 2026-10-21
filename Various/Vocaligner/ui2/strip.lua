-- @noindex
-- Горизонтальная «ручка-полоска» на спрайте-плёнке (кадры по вертикали, значение 0..1 = кривая слева направо).
-- Спрайт и скрипты генерации лежат в ui-proto/knee-strip (knee_strip_gen.py, knee_strip.json): кадров 101, кадр 504x68 (@2x), показывается 252x34.
-- Первое применение — Ratio компрессора (проба). Механика как у кноба: относительное перетаскивание (Shift — точнее),
-- колесо, двойной клик — сброс; пока ручку держат, owner.gesture включён и живое обновление идёт тем же путём, что у кнобов.
local import=...;local Settings=import('compressor/settings');local W=import('ui2/widgets');local M={}
local here=debug.getinfo(1,'S').source:match([[^@(.+[\/])]])
M.file=here..'assets/knobs/ratio_strip.png'
M.frames=101
M.width,M.height=252,34       -- логический размер кадра (@2x-лист показывается вдвое меньше)
M.hit0,M.hit1=6,246           -- где в кадре начинается/кончается кривая (из knee_strip.json)

local function clamp(v,lo,hi) return v<lo and lo or (v>hi and hi or v) end
local img,img_ctx,sheet_w,sheet_h
local function sprite(im,ctx)
  if img_ctx~=ctx then img,img_ctx=nil,ctx end
  if img==false then return nil end
  if img then return img end
  local ok,i=pcall(im.CreateImage,M.file)
  if not ok or not i then img=false;return nil end
  im.Attach(ctx,i);local w,h=im.Image_GetSize(i);sheet_w,sheet_h=w,h;img=i
  return i
end
function M.available(im,ctx) return sprite(im,ctx)~=nil end

-- значение <-> 0..1; log=true — логарифмическая шкала (ratio 1..100 иначе занимала бы первые 3% хода)
local function to_t(v,lo,hi,log)
  if log then return clamp(math.log(math.max(v,lo)/lo)/math.log(hi/lo),0,1) end
  return clamp((v-lo)/(hi-lo),0,1)
end
local function from_t(t,lo,hi,log)
  if log then return lo*(hi/lo)^t end
  return lo+t*(hi-lo)
end
local drag={}
-- e = {key,label,lo,hi,fmt,tip,log=bool}; width — доступная ширина (кадр уменьшается, если не помещается)
function M.control(im,ctx,owner,e,width)
  local key,label,lo,hi,fmt,tip=e[1],e[2],e[3],e[4],e[5],e[6]
  local default=Settings.defaults[key];if default==nil then default=lo end
  local value=owner.cfg[key]
  local st=drag[key] or {};drag[key]=st
  im.BeginGroup(ctx)
  im.TextDisabled(ctx,label)
  local sp=sprite(im,ctx)
  local avail=width or im.GetContentRegionAvail(ctx)
  local s=clamp(avail/M.width,.5,1);local w,h=M.width*s,M.height*s
  local x,y=im.GetCursorScreenPos(ctx)
  im.InvisibleButton(ctx,'##strip_'..key,w,h)
  local hovered,active=im.IsItemHovered(ctx),im.IsItemActive(ctx)
  local changed,released=false,false
  local t=to_t(value,lo,hi,e.log)
  local span=(M.hit1-M.hit0)*s
  if im.IsItemActivated(ctx) or (active and not st.drag) then
    local mx=im.GetMousePos(ctx);st.drag={x=mx,t=t}
  end
  local d=st.drag
  if active and d then
    owner.gesture=true
    local mx=im.GetMousePos(ctx)
    local fine=(im.GetKeyMods(ctx)&im.Mod_Shift)~=0 and .1 or 1
    if d.fine~=fine then d.x,d.t,d.fine=mx,t,fine end -- смена Shift посреди жеста: считаем от текущей точки, без скачка
    local nt=clamp(d.t+(mx-d.x)/span*fine,0,1)
    if math.abs(nt-t)>1e-9 then t=nt;value=from_t(t,lo,hi,e.log);changed=true end
    im.SetMouseCursor(ctx,im.MouseCursor_ResizeEW)
  elseif hovered then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
  if st.was_active and not active then released=true;st.drag=nil end
  st.was_active=active
  if hovered then
    local wheel=im.GetMouseWheel(ctx)
    if wheel~=0 then
      local step=((im.GetKeyMods(ctx)&im.Mod_Shift)~=0 and .002 or .01)*wheel
      t=clamp(t+step,0,1);value=from_t(t,lo,hi,e.log);changed=true;st.release_at=reaper.time_precise()+.25
    end
    if im.IsMouseDoubleClicked(ctx,0) then value,changed=default,true;t=to_t(value,lo,hi,e.log);st.release_at=reaper.time_precise() end
  end
  if changed then owner.cfg[key]=value;W.changed(owner,key) end
  if st.release_at and not active and reaper.time_precise()>=st.release_at then st.release_at=nil;released=true end
  if released then owner:control_released() end
  local dl=im.GetWindowDrawList(ctx)
  if sp then
    local i=math.floor(t*(M.frames-1)+.5)
    local fh=sheet_h/M.frames
    local v0=i*fh/sheet_h
    im.DrawList_AddImage(dl,sp,x,y,x+w,y+h,0,v0,1,v0+fh/sheet_h)
  else -- нет спрайта: простая полоска
    im.DrawList_AddRectFilled(dl,x,y+h/2-2,x+w,y+h/2+2,0x3A3A40FF,2)
    im.DrawList_AddRectFilled(dl,x,y+h/2-2,x+w*t,y+h/2+2,0xFFB000FF,2)
  end
  if tip and hovered then im.SetTooltip(ctx,tip) end
  local text=fmt:format(value);local tw=im.CalcTextSize(ctx,text)
  im.SetCursorScreenPos(ctx,x+(w-tw)/2,y+h+1);im.Text(ctx,text)
  im.EndGroup(ctx)
end
return M
