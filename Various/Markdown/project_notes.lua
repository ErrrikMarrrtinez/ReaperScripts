-- @noindex
-- One Markdown note per REAPER project, embedded in its RPP via ProjExtState.
local r = reaper
if not r or not r.ImGui_GetBuiltinPath then
  if r then r.MB('Install ReaImGui through ReaPack, then run this script again.', 'ReaMD', 0) end
  return
end
local root = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
local im = dofile(r.ImGui_GetBuiltinPath() .. '/imgui.lua')('0.9.2.3')
local Multiline = dofile(root .. 'init.lua')
local Session = dofile(root .. 'notes/session.lua')
local notes = Session.new(r, Multiline, {markdown=true, markdown_shortcuts=true,
  font_family='Arial', font_size=18, padding=24, markdown_theme='graphite',
  markdown_max_width=900, tab_mode='insert'})
local ctx = im.CreateContext('ReaMD - Project notes')
local themes, theme = {'graphite', 'paper', 'sand'}, 0
local guarded_loop

-- A second invocation toggles this action off instead of creating two writers.
if r.set_action_options then r.set_action_options(1) end
local _, _, section, command = r.get_action_context()
if section and command and command > 0 then
  r.SetToggleCommandState(section, command, 1)
  r.RefreshToolbar2(section, command)
end

local function loop()
  local state = notes:current()
  local e = state and state.editor
  if e then
    e.options.markdown_theme = themes[theme + 1]
    e:prepare(ctx, im)
  end
  im.SetNextWindowSize(ctx, 1000, 780, im.Cond_FirstUseEver)
  local visible, keep = im.Begin(ctx, 'ReaMD - Project notes', true)
  if visible then
    if e then
      local save = im.Button(ctx, 'Save project')
      local shortcut = im.IsWindowFocused(ctx, im.FocusedFlags_RootAndChildWindows)
        and im.IsKeyDown(ctx, im.Mod_Ctrl) and im.IsKeyPressed(ctx, im.Key_S, false)
      if save or shortcut then
        notes:save_project(state, shortcut and im.IsKeyDown(ctx, im.Mod_Shift))
      end
      im.SameLine(ctx)
      local changed, source = im.Checkbox(ctx, 'Source', not e.options.markdown)
      if changed then e:set_markdown(not source); if source then e:set_read_only(false) end end
      im.SameLine(ctx)
      local reading_changed, reading = im.Checkbox(ctx, 'Reading', e.options.read_only)
      if reading_changed then e:set_read_only(reading); if reading then e:set_markdown(true) end end
      im.SameLine(ctx)
      im.SetNextItemWidth(ctx, 120)
      local theme_changed, next_theme = im.Combo(ctx, '##theme', theme, 'Graphite\0Paper\0Sand\0')
      if theme_changed then theme = next_theme end
      im.TextDisabled(ctx, state.name .. (r.IsProjectDirty(state.project) ~= 0 and ' *' or ''))
      local _, h = im.GetContentRegionAvail(ctx)
      e:render(ctx, '##project_note_' .. state.id, 0, math.max(80, h - im.GetTextLineHeightWithSpacing(ctx) * 1.7))
      local hint = state.path == '' and 'New project · Save project to keep these notes in an RPP.'
        or r.IsProjectDirty(state.project) ~= 0 and 'Notes updated · Ctrl+S saves the project, including notes.'
        or 'Notes saved with project · Ctrl+wheel to zoom'
      im.TextDisabled(ctx, hint)
    else
      im.TextDisabled(ctx, 'Open a project to write notes.')
    end
    im.End(ctx)
  end
  if keep then r.defer(guarded_loop) end
end

guarded_loop = function()
  local ok, err = xpcall(loop, debug.traceback)
  if not ok then r.ShowConsoleMsg('\nReaMD - Project notes:\n' .. tostring(err) .. '\n') end
end
r.atexit(function()
  notes:dispose()
  if section and command and command > 0 then
    r.SetToggleCommandState(section, command, 0)
    r.RefreshToolbar2(section, command)
  end
end)
r.defer(guarded_loop)
