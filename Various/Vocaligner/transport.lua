-- @noindex
local M={}
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
  line(state.play,0x91DFCDFF,1.6)
end
return M
