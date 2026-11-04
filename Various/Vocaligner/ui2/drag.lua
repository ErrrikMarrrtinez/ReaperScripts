-- @noindex
-- Общее относительное перетаскивание «как у кноба» для всех виджетов нового интерфейса: пока тянут, курсор прячется
-- и каждый кадр возвращается в точку захвата (Windows + js_ReaScriptAPI), дельта копится без упора в край экрана.
-- Settings → «Hide cursor while dragging» (M.enabled): выключено — обычный курсор и дельта ImGui.
local M={}
local r=reaper
local CAN=(r.GetOS() or ''):match('^Win')~=nil and r.JS_Mouse_SetPosition~=nil
M.enabled=true
function M.active() return CAN and M.enabled~=false end
-- точка захвата: вызывать в кадре, когда виджет стал активным
function M.begin() local x,y=r.GetMousePosition();return {x=x,y=y} end
-- дельта этого кадра (dx, dy в пикселях экрана)
function M.delta(im,ctx,anchor)
  if M.active() and anchor then
    im.SetMouseCursor(ctx,im.MouseCursor_None)
    local x,y=r.GetMousePosition();local dx,dy=x-anchor.x,y-anchor.y
    if dx~=0 or dy~=0 then r.JS_Mouse_SetPosition(anchor.x,anchor.y) end
    return dx,dy
  end
  return im.GetMouseDelta(ctx)
end
return M
