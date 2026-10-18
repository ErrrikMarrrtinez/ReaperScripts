-- @noindex
local M={last_t=0,fade=0}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
function M.read(r,project)
  if not project or r.EnumProjects and r.EnumProjects(-1)~=project then return {} end
  local state=r.GetPlayStateEx and r.GetPlayStateEx(project) or 0
  return {edit=r.GetCursorPositionEx and r.GetCursorPositionEx(project),
    play=state~=0 and r.GetPlayPositionEx and r.GetPlayPositionEx(project) or nil,
    running=state&5~=0 and state&2==0}
end
function M.hold(owner,r)
  owner.follow_after=(r.time_precise and r.time_precise() or 0)+.8
end
-- View-only follow: never seek, scroll REAPER, or modify project state.
-- A moved edit cursor is followed once while stopped, not on every frame.
function M.follow(owner,r,state,v,origin,lower,upper,manual)
  if manual then M.hold(owner,r) end
  local moved=state.edit~=owner.transport_edit
  local stopped=owner.transport_play~=nil and state.play==nil
  owner.transport_edit=state.edit
  owner.transport_play=state.play
  local t=state.running and state.play or not state.play and (moved or stopped) and state.edit
  if not t or manual or (r.time_precise and r.time_precise() or 0)<(owner.follow_after or 0) then return end
  t=t-(origin or 0)
  if t<lower or t>upper then return end
  if t<v.start or t>v.start+v.span then
    v.start=clamp(t-v.span*.12,lower,math.max(lower,upper-v.span))
  end
end
function M.draw(im,dl,state,tx,left,right,top,bottom)
  local function line(t,color,weight)
    if t==nil then return end
    local xx=tx(t);if xx>=left and xx<=right then im.DrawList_AddLine(dl,xx,top,xx,bottom,color,weight) end
  end
  line(state.edit,0xC3CAD48C,1)
  -- Плей-курсор: тонкая оранжевая линия, мягкое многослойное свечение и прозрачный хвост слева; всё плавно проявляется
  -- при старте воспроизведения и слабо «дышит» во время игры
  if state.play~=nil then
    local xx=tx(state.play)
    if xx>=left and xx<=right then
      local now=(reaper and reaper.time_precise and reaper.time_precise()) or 0
      local dt=math.max(0,math.min(.1,now-M.last_t));M.last_t=now
      M.fade=M.fade+((state.running and 1 or 0)-M.fade)*math.min(1,dt*5) -- плавное появление/затухание хвоста и пульса
      local fade=M.fade
      local pulse=fade*(0.5+0.5*math.sin(now*3.2))
      local tail=math.min(64,xx-left)
      if fade>0.01 and tail>2 and im.DrawList_AddRectFilledMultiColor then
        local a=math.floor(0x16*fade)
        im.DrawList_AddRectFilledMultiColor(dl,xx-tail,top,xx,bottom,0xF29A5A00,0xF29A5A00|a,0xF29A5A00|a,0xF29A5A00)
      end
      local g=0.7+0.3*fade -- в паузе свечение слабее
      im.DrawList_AddLine(dl,xx,top,xx,bottom,0xF29A5A00|math.floor((5+4*pulse)*g),11)
      im.DrawList_AddLine(dl,xx,top,xx,bottom,0xF29A5A00|math.floor((9+5*pulse)*g),7)
      im.DrawList_AddLine(dl,xx,top,xx,bottom,0xF29A5A00|math.floor((18+7*pulse)*g),3.6)
      im.DrawList_AddLine(dl,xx,top,xx,bottom,0xFFB878E6,1.0)
    end
  end
end
return M
