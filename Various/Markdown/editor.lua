-- @noindex
local load = ...
local U = load('core.utf8')
local Document = load('core.document')
local History = load('core.history')
local Layout = load('core.layout')
local Plain = load('core.projection')
local Editor = {}
Editor.__index = Editor

local defaults = {
  wrap = true, word_wrap = true, font_family = 'Consolas', font_size = 16,
  min_font_size = 10, max_font_size = 40, zoom_step = 2,
  tab_size = 4, tab_mode = 'line', insert_spaces = false, read_only = false,
  padding = 5, overscan = 10, selection_rounding = 3,
  history_limit = 1000, history_bytes = 16 * 1024 * 1024, merge_delay = 0.7,
  layout_budget = 12000, layout_seconds = 0.004,
  max_draw_units = 32768,
  double_click_time = 0.5, triple_click = 'all',
  background = 0x16191DFF, text_color = 0xF2F2F2FF,
  selection_color = 0x4169E1AA, inactive_selection_color = 0x4169E175,
  caret_color = 0xFFFFFFFF, current_row_color = 0xFFFFFF06,
}

function Editor.new(options)
  options = options or {}
  local config = {}
  for k, v in pairs(defaults) do config[k] = v end
  for k, v in pairs(options) do config[k] = v end
  if config.markdown then
    if options.font_family==nil then config.font_family='Arial' end
    if options.padding==nil then config.padding=20 end
    if options.markdown_max_width==nil then config.markdown_max_width=900 end
  end
  assert(config.tab_size >= 1 and config.layout_budget >= 1 and config.layout_seconds > 0)
  assert(config.min_font_size > 0 and config.max_font_size >= config.min_font_size)
  config.font_size = math.max(config.min_font_size, math.min(config.max_font_size, math.floor(config.font_size)))
  local document = Document.new(config.text or '')
  local self = setmetatable({options = config, document = document,
    history = History.new(config.history_limit, config.history_bytes, config.merge_delay),
    caret = 0, affinity = 'downstream', focused = false, scroll_x = 0, scroll_y = 0,
    blink_at = 0, clock = config.clock or (reaper and reaper.time_precise) or os.clock,
    last_render_revision = document.revision}, Editor)
  self.layout = config.markdown and load('markdown.layout').new(self) or Layout.new(document, config)
  return self
end

function Editor:get_text() return self.document.text end

function Editor:get_selection()
  return self.anchor, self.anchor and self.caret or nil
end

function Editor:get_selected_text()
  if not self.anchor then return '' end
  local a, b = math.min(self.anchor, self.caret), math.max(self.anchor, self.caret)
  return self.document.text:sub(a + 1, b)
end

function Editor:get_state()
  return {caret = self.caret, anchor = self.anchor, affinity = self.affinity,
    scroll_x = self.scroll_x, scroll_y = self.scroll_y, preferred_x = self.preferred_x}
end

function Editor:restore_state(state)
  self.scroll_target,self.scroll_align=nil,nil
  self.caret = U.clamp(self.document.text, state.caret)
  self.anchor = state.anchor and U.clamp(self.document.text, state.anchor) or nil
  self.affinity, self.preferred_x = state.affinity or 'downstream', state.preferred_x
  self.scroll_x, self.scroll_y = state.scroll_x or 0, state.scroll_y or 0
  self.pending_scroll = {self.scroll_x, self.scroll_y}
  self.blink_at, self.follow_caret = self.clock(), true
end

function Editor:selection_changed()
  self.history.epoch = self.history.epoch + 1
  self.blink_at, self.preferred_x, self.follow_caret = self.clock(), nil, true
end

function Editor:set_selection(anchor, head, affinity)
  self.anchor = anchor and U.clamp(self.document.text, anchor) or nil
  self.caret = U.clamp(self.document.text, head or anchor or self.caret)
  self.affinity = affinity or 'downstream'
  self:selection_changed()
end

function Editor:set_caret(pos, extend, affinity)
  local anchor = extend and (self.anchor or self.caret) or nil
  self:set_selection(anchor, pos, affinity)
end

function Editor:select_all()
  self:set_selection(0, #self.document.text)
  self.follow_caret = false
end

function Editor:replace_range(first, last, text, kind, after)
  if self.options.read_only then return false end
  local before = self:get_state()
  local edit = self.document:replace(first, last, text)
  if not edit then return false end
  if after then
    self.caret, self.anchor, self.affinity = after.caret, after.anchor, after.affinity or 'downstream'
  else
    self.caret, self.anchor, self.affinity = edit.at + #edit.inserted, nil, 'downstream'
  end
  self.preferred_x, self.blink_at, self.follow_caret = nil, self.clock(), true
  self.history:record(edit, before, self:get_state(), kind or 'replace', self.clock())
  if self.options.on_change then self.options.on_change(self, edit, kind or 'replace') end
  return true
end

function Editor:insert_text(text, kind)
  if self.options.markdown and (kind == 'typing' or kind == 'paste') then
    text = load('markdown.commands').prepare_text(self, text)
  end
  local a, b = self.anchor, self.caret
  local first = math.min(a or b,b)
  local changed = self:replace_range(a or b, b, text, kind or 'insert')
  if changed and self.options.markdown and kind == 'typing' then
    load('markdown.commands').smart_dashes(self,first,text)
  end
  if not changed and not self.options.read_only and a and a ~= b then
    self:set_caret(math.max(a, b))
  end
  return changed
end

function Editor:set_text(text, undoable)
  if undoable then return self:replace_range(0, #self.document.text, text, 'set_text', {caret = 0}) end
  local edit = self.document:replace(0, #self.document.text, text)
  self.history:clear()
  self:restore_state({caret = 0})
  if edit and self.options.on_change then self.options.on_change(self, edit, 'set_text') end
  return edit ~= nil
end

function Editor:delete(direction, word)
  if self.anchor and self.anchor ~= self.caret then return self:insert_text('', 'selection_delete') end
  local text, pos = self.document.text, self.caret
  local other = direction < 0 and (word and U.word_left(text, pos) or U.prev(text, pos)) or
    (word and U.word_right(text, pos) or U.next(text, pos))
  return self:replace_range(pos, other, '', word and 'word_delete' or direction < 0 and 'backspace' or 'delete')
end

function Editor:undo()
  if self.options.read_only then return false end
  local state = self.history:undo(self.document)
  if not state then return false end
  self:restore_state(state)
  if self.options.on_change then self.options.on_change(self, nil, 'undo') end
  return true
end

function Editor:redo()
  if self.options.read_only then return false end
  local state = self.history:redo(self.document)
  if not state then return false end
  self:restore_state(state)
  if self.options.on_change then self.options.on_change(self, nil, 'redo') end
  return true
end

function Editor:move(command, extend, word, page_rows)
  local text, pos, affinity = self.document.text, self.caret, 'downstream'
  local preferred
  if command == 'left' or command == 'right' then
    if not extend and self.anchor and self.anchor ~= pos then
      pos = command == 'left' and math.min(pos, self.anchor) or math.max(pos, self.anchor)
    elseif command == 'left' then pos = word and U.word_left(text, pos) or U.prev(text, pos)
    else pos = word and U.word_right(text, pos) or U.next(text, pos) end
  elseif word and (command == 'home' or command == 'end') then
    pos = command == 'home' and 0 or #text
  else
    if not self.layout.index then return false end
    self.layout:sync()
    local x, _, row_number = self.layout:position(pos, self.affinity)
    if not x then return false end
    if command == 'home' or command == 'end' then
      local row, line = self.layout:row(row_number)
      if command == 'end' and row.partial then return false end
      pos = line.start + (command == 'home' and row.a or row.b)
      affinity = command == 'end' and 'upstream' or 'downstream'
    else
      local delta = (command == 'up' or command == 'page_up') and -1 or 1
      if command == 'page_up' or command == 'page_down' then delta = delta * math.max(1, page_rows or 10) end
      local target = math.max(1, math.min(self.layout:row_count(), row_number + delta))
      preferred = self.preferred_x or x
      if self.layout.move_vertical then
        pos, affinity = self.layout:move_vertical(self.caret, self.affinity, delta, preferred)
      else pos, affinity = self.layout:hit_row(target, preferred) end
      if not pos then return false end
    end
  end
  self:set_caret(pos, extend, affinity)
  self.preferred_x = preferred
  return true
end

function Editor:indent(unindent)
  if self.options.read_only then return false end
  local doc, a, b = self.document, self.anchor or self.caret, self.caret
  local first, last = math.min(a, b), math.max(a, b)
  local from, left = doc:line_at(first)
  local to = doc:line_at(last)
  local multi = self.anchor and from ~= to
  local partial = self.anchor and from == to and (first > left.start or last < left.finish)
  if partial and unindent then
    local selected = self:get_selected_text()
    local stripped = selected:gsub('^%s*\t', '')
    if stripped == selected then stripped = selected:gsub('^' .. string.rep(' ', self.options.tab_size), '') end
    if stripped == selected then return false end
    local new_end = first + #stripped
    return self:replace_range(first, last, stripped, 'unindent',
      {anchor = a > b and new_end or first, caret = a > b and first or new_end})
  end
  if not unindent and (partial or (not self.anchor and self.options.tab_mode == 'insert')) then
    local insert = self.options.insert_spaces and string.rep(' ', self.options.tab_size) or '\t'
    return self:insert_text(insert, 'tab')
  end
  if multi and last == doc.lines[to].start then to = to - 1 end
  local parts, changes = {}, {}
  for i = from, to do
    local s = doc.lines[i].text
    local count = 0
    if unindent then
      if s:sub(1, 1) == '\t' then count = 1
      else count = math.min(self.options.tab_size, #(s:match('^ *') or '')) end
      parts[#parts + 1] = s:sub(count + 1)
      changes[#changes + 1] = {at = doc.lines[i].start, removed = count, added = 0}
    else
      local prefix = self.options.insert_spaces and string.rep(' ', self.options.tab_size) or '\t'
      parts[#parts + 1] = prefix .. s
      changes[#changes + 1] = {at = doc.lines[i].start, removed = 0, added = #prefix}
    end
  end
  local function map(p)
    local delta = 0
    for _, change in ipairs(changes) do
      if p >= change.at then delta = delta + change.added - math.min(change.removed, p - change.at) end
    end
    return p + delta
  end
  return self:replace_range(left.start, doc.lines[to].finish, table.concat(parts, '\n'),
    unindent and 'unindent' or 'indent', {caret = map(self.caret), anchor = self.anchor and map(self.anchor)})
end

function Editor:mouse_down(pos, affinity, clicks, shift, ctrl)
  if clicks >= 3 then
    if self.options.triple_click == 'line' then
      local _, line = self.document:line_at(pos)
      self:set_selection(line.start, math.min(#self.document.text, line.finish + 1))
      self.drag = {mode = 'line', first = self.anchor, last = self.caret}
    else self:select_all(); self.drag = {mode = 'all'} end
  elseif clicks == 2 then
    local first, last = U.word_bounds(self.document.text, pos)
    self:set_selection(first, last)
    self.drag = {mode = 'word', first = first, last = last}
  else
    local anchor = shift and (self.anchor or self.caret) or (ctrl and self.anchor or nil)
    self:set_selection(anchor, pos, affinity)
    self.drag = {mode = 'char', first = anchor or pos}
  end
  self.focused = true
  self.follow_caret = false
end

function Editor:mouse_drag(pos, affinity)
  local drag = self.drag
  if not drag or drag.mode == 'all' then return end
  if drag.mode == 'char' then self:set_selection(drag.first, pos, affinity)
  else
    local first, last
    if drag.mode == 'word' then first, last = U.word_bounds(self.document.text, pos)
    else
      local _, line = self.document:line_at(pos)
      first, last = line.start, math.min(#self.document.text, line.finish + 1)
    end
    if pos < drag.first then self:set_selection(drag.last, first)
    else self:set_selection(drag.first, math.max(drag.last, last)) end
  end
  -- Drag autoscroll is controlled by pointer distance, not by caret follow.
  self.follow_caret = false
end

function Editor:set_font_size(size)
  self.options.font_size = math.max(self.options.min_font_size,
    math.min(self.options.max_font_size, math.floor(size + 0.5)))
end

function Editor:set_wrap(enabled)
  self.options.wrap = not not enabled
end

function Editor:set_read_only(enabled)
  enabled=not not enabled
  if self.options.read_only==enabled then return end
  self.options.read_only=enabled
  self.drag,self.pending_motion=nil,nil
  self.follow_caret=false
  self.layout:invalidate()
end

function Editor:toggle_comment(prefix)
  return load('core.text_actions').toggle_comment(self, prefix or self.options.comment_prefix)
end

function Editor:find_all(query, options)
  return load('core.text_actions').find_all(self, query, options)
end

function Editor:replace_all(query, replacement, options)
  return load('core.text_actions').replace_all(self, query, replacement, options)
end

function Editor:set_projection(projection)
  assert(not self.options.markdown, 'Markdown manages its own projection; use source mode for a custom projection')
  self.layout.projection = projection or Plain
  self.layout:invalidate()
end

function Editor:set_markdown(enabled)
  enabled = not not enabled
  -- Like font changes, switching renderers takes effect before the next Begin.
  -- This also supports enabling Markdown in a field initially created as plain.
  if self.ui and not self.preparing then self.pending_markdown=enabled;return end
  if self.options.markdown == enabled then return end
  self.options.markdown = enabled
  self.layout = enabled and load('markdown.layout').new(self) or Layout.new(self.document, self.options)
  self.reflow_anchor = nil
  self.follow_caret = true
  if self.ui then self.ui.content = nil end
end

function Editor:format(command, value)
  return load('markdown.commands').run(self, command, value)
end

function Editor:focus()
  self.request_focus, self.follow_caret = true, true
end

function Editor:scroll_to(pos,align)
  self.scroll_target = U.clamp(self.document.text, pos)
  self.scroll_align=align
  self.pending_scroll,self.reflow_anchor=nil,nil
  self.follow_caret=false
end

function Editor:prepare(ctx, imgui)
  if self.pending_markdown~=nil then
    local enabled=self.pending_markdown;self.pending_markdown=nil
    self.preparing=true;self:set_markdown(enabled);self.preparing=nil
  end
  return load('ui.widget').prepare(self, ctx, imgui)
end

function Editor:render(ctx, label, width, height)
  return load('ui.widget').render(self, ctx, label, width, height)
end

function Editor:dispose()
  if self.ui then load('ui.widget').dispose(self) end
end

return Editor
