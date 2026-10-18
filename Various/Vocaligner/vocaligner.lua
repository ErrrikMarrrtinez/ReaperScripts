-- @noindex
local root=debug.getinfo(1,'S').source:match('^@(.+[\\/])')
if not reaper.ImGui_GetBuiltinPath then
  reaper.MB('Install ReaImGui from ReaPack to use the interface. No Python or audio libraries are required.','Vocaligner',0)
  return
end
local ImGui=dofile(reaper.ImGui_GetBuiltinPath()..'/imgui.lua')('0.9.3')
local Vocaligner=dofile(root..'init.lua')
local app=Vocaligner.new(reaper)
local UI=Vocaligner.import('ui2')
local ctx=ImGui.CreateContext('mrtnz Vocaligner')
app.engine=Vocaligner.import('eel').new(ImGui,ctx,reaper)
app.pitch.engine=Vocaligner.import('pitch/neural').new(ImGui,ctx,reaper)
reaper.atexit(function() app:dispose() end)
local function loop()
  local ok,open=xpcall(function()
    app:tick()
    return UI.draw(ImGui,ctx,app)
  end,debug.traceback)
  if not ok then
    app:dispose()
    reaper.ShowConsoleMsg('Vocaligner error:\n'..tostring(open)..'\n')
    return
  end
  if open then reaper.defer(loop) else app:dispose() end
end
reaper.defer(loop)
