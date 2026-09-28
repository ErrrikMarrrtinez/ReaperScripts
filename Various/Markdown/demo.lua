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
local ctx = im.CreateContext('Multiline — ReaCode core')
local sample = [[Это отдельное многострочное поле на основе ReaCode.

Переносы меняют только отображение. Попробуйте сузить окно, выделить несколько экранных рядов, изменить размер шрифта и отменить замену выделенного текста.

Двойной клик — слово. Тройной — весь текст, как в исходном редакторе.
Shift + стрелки / клик — выделение. Ctrl + стрелки — слова.
Ctrl+C / X / V — буфер. Ctrl+Z / Y / Shift+Z — история.
Ctrl + колесо — размер шрифта. Tab / Shift+Tab — отступы.

# Здесь позже появится Markdown
Пока это обычный текст в едином редактируемом поле.

UTF-8: русский, English, 日本語, 🙂.
]]
local editor = Multiline.new({text = sample})
local second = Multiline.new({text = 'Второй независимый экземпляр. Своя история, курсор и выделение.', font_family = 'Arial'})
local show_second = false

local function loop()
  -- Font creation/attachment is deliberately outside an active ImGui frame.
  editor:prepare(ctx, im)
  second:prepare(ctx, im)
  im.SetNextWindowSize(ctx, 940, 700, im.Cond_FirstUseEver)
  local visible, open = im.Begin(ctx, 'Multiline — ReaCode core', true)
  if visible then
    if im.Button(ctx, 'Пример') then editor:set_text(sample, true); editor:focus() end
    im.SameLine(ctx)
    if im.Button(ctx, '20 000 строк') then
      local lines = {}
      for i = 1, 20000 do lines[i] = ('Строка %d: текст для проверки переноса и выделения.'):format(i) end
      editor:set_text(table.concat(lines, '\n'), true); editor:focus()
    end
    im.SameLine(ctx)
    if im.Button(ctx, 'Длинная строка') then
      editor:set_text(string.rep('длинная_строка_', 40000), true); editor:focus()
    end
    im.SameLine(ctx)
    if im.Button(ctx, 'Undo') then editor:undo(); editor:focus() end
    im.SameLine(ctx)
    if im.Button(ctx, 'Redo') then editor:redo(); editor:focus() end
    local changed, wrap = im.Checkbox(ctx, 'Перенос строк', editor.options.wrap)
    if changed then editor:set_wrap(wrap) end
    im.SameLine(ctx)
    changed, show_second = im.Checkbox(ctx, 'Два поля', show_second)
    im.SameLine(ctx)
    local readonly_changed, readonly = im.Checkbox(ctx, 'Только чтение', editor.options.read_only)
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
      im.Text(ctx, ('Строк: %d | Экранных рядов%s: %d | Шрифт: %d | История: %d/%d'):format(
        metrics.logical_lines, metrics.pending_lines > 0 and ' ≈' or '', metrics.rows,
        editor.options.font_size, editor.history.index, #editor.history.entries))
      im.Text(ctx, metrics.pending_lines > 0 and ('Раскладка: осталось строк ' .. metrics.pending_lines) or
        ('Курсор: ' .. editor.caret .. ' байт | Выделено: ' .. #editor:get_selected_text() .. ' байт'))
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
