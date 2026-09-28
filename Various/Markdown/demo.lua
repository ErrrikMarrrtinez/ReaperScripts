-- @noindex
-- Load this file in REAPER: Actions > Show action list > ReaScript: Load.
local r = reaper
if not r or not r.ImGui_GetBuiltinPath then
  if r then r.MB('Install ReaImGui through ReaPack, then run this script again.', 'Multiline', 0) end
  return
end
local root = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
local im = dofile(r.ImGui_GetBuiltinPath() .. '/imgui.lua')('0.9.2.3')
local Multiline = dofile(root .. 'init.lua')
local ctx = im.CreateContext('ReaMD - Multiline input demo')
local sample = [[A standalone multiline input based on ReaCode.

Wrapping only changes how text is displayed. Try narrowing the window, selecting several visual rows, changing the font size, and undoing a replacement of selected text.

Double-click selects a word. Triple-click selects all text, as in the original editor.
Shift + arrows / click extends the selection. Ctrl + arrows moves by word.
Ctrl+C / X / V copies, cuts, or pastes. Ctrl+Z / Y / Shift+Z navigates history.
Ctrl + wheel changes the font size. Tab / Shift+Tab indents or unindents.

# Plain text mode
This demo displays plain text. Open the Markdown demo to try live formatting.

UTF-8 examples: naïve, café, →, 🙂.
]]
local editor = Multiline.new({text = sample})
local second = Multiline.new({text = 'A second independent field with its own history, caret, and selection.', font_family = 'Arial'})
local show_second = false

local function loop()
  -- Font creation/attachment is deliberately outside an active ImGui frame.
  editor:prepare(ctx, im)
  second:prepare(ctx, im)
  im.SetNextWindowSize(ctx, 940, 700, im.Cond_FirstUseEver)
  local visible, open = im.Begin(ctx, 'ReaMD - Multiline input demo', true)
  if visible then
    if im.Button(ctx, 'Sample') then editor:set_text(sample, true); editor:focus() end
    im.SameLine(ctx)
    if im.Button(ctx, '20,000 lines') then
      local lines = {}
      for i = 1, 20000 do lines[i] = ('Line %d: sample text for wrapping and selection.'):format(i) end
      editor:set_text(table.concat(lines, '\n'), true); editor:focus()
    end
    im.SameLine(ctx)
    if im.Button(ctx, 'Long line') then
      editor:set_text(string.rep('long_unbroken_line_', 40000), true); editor:focus()
    end
    im.SameLine(ctx)
    if im.Button(ctx, 'Undo') then editor:undo(); editor:focus() end
    im.SameLine(ctx)
    if im.Button(ctx, 'Redo') then editor:redo(); editor:focus() end
    local changed, wrap = im.Checkbox(ctx, 'Word wrap', editor.options.wrap)
    if changed then editor:set_wrap(wrap) end
    im.SameLine(ctx)
    changed, show_second = im.Checkbox(ctx, 'Two fields', show_second)
    im.SameLine(ctx)
    local readonly_changed, readonly = im.Checkbox(ctx, 'Read-only', editor.options.read_only)
    if readonly_changed then editor.options.read_only = readonly end
    im.SameLine(ctx)
    if im.SmallButton(ctx, 'A-') then editor:set_font_size(editor.options.font_size - 2) end
    im.SameLine(ctx)
    if im.SmallButton(ctx, 'A+') then editor:set_font_size(editor.options.font_size + 2) end
    local _, available_h = im.GetContentRegionAvail(ctx)
    local status_h = im.GetTextLineHeightWithSpacing(ctx) * 2
    local editor_h = math.max(40, available_h - status_h - (show_second and 130 or 0))
    editor:render(ctx, '##main', 0, editor_h)
    if show_second then second:render(ctx, '##second', 0, 120) end
    local metrics = editor.metrics
    if metrics then
      im.Text(ctx, ('Lines: %d | Visual rows%s: %d | Font: %d | History: %d/%d'):format(
        metrics.logical_lines, metrics.pending_lines > 0 and ' ≈' or '', metrics.rows,
        editor.options.font_size, editor.history.index, #editor.history.entries))
      im.Text(ctx, metrics.pending_lines > 0 and ('Layout: ' .. metrics.pending_lines .. ' lines remaining') or
        ('Caret: ' .. editor.caret .. ' bytes | Selected: ' .. #editor:get_selected_text() .. ' bytes'))
    end
    im.End(ctx)
  end
  if open then r.defer(loop) end
end

r.atexit(function()
  editor:dispose()
  second:dispose()
end)
r.defer(loop)
