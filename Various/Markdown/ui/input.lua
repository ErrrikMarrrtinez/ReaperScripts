-- @noindex
local Input = {}
local navigation = {
  {'LeftArrow', 'left'}, {'RightArrow', 'right'}, {'UpArrow', 'up'}, {'DownArrow', 'down'},
  {'Home', 'home'}, {'End', 'end'}, {'PageUp', 'page_up'}, {'PageDown', 'page_down'},
}

function Input.keyboard(e, im, ctx, page_rows)
  local ctrl, shift, alt = im.IsKeyDown(ctx, im.Mod_Ctrl), im.IsKeyDown(ctx, im.Mod_Shift), im.IsKeyDown(ctx, im.Mod_Alt)
  local function pressed(key, repeat_key) return im.IsKeyPressed(ctx, im['Key_' .. key], repeat_key ~= false) end
  if ctrl and not alt then
    if pressed('A', false) then e:select_all(); return
    elseif pressed('C', false) or pressed('X', false) then
      local selected = e:get_selected_text()
      if selected ~= '' then
        im.SetClipboardText(ctx, selected)
        if pressed('X', false) then e:insert_text('', 'cut') end
      end
      return
    elseif pressed('V', false) then
      local text = im.GetClipboardText(ctx)
      if text and text ~= '' then e:insert_text(text, 'paste') end
      return
    elseif pressed('Z') then if shift then e:redo() else e:undo() end; return
    elseif pressed('Y') then e:redo(); return end
    if e.options.comment_prefix and pressed('Slash', false) then e:toggle_comment(); return end
  end
  for _, nav in ipairs(navigation) do
    if pressed(nav[1]) then
      if not e:move(nav[2], shift, ctrl and not alt, page_rows) then
        e.pending_motion = {nav[2], shift, ctrl and not alt, page_rows}
      else e.pending_motion = nil end
      break
    end
  end
  if pressed('Backspace') then e:delete(-1, ctrl and not alt)
  elseif pressed('Delete') then e:delete(1, ctrl and not alt)
  elseif pressed('Enter') or pressed('KeypadEnter') then e:insert_text('\n', 'newline')
  elseif pressed('Tab') then e:indent(shift)
  elseif pressed('Escape', false) then e:set_selection(nil, e.caret) end

  if ctrl and not alt then return end -- AltGr (Ctrl+Alt) may supply text.
  local chars, i = {}, 0
  while true do
    local ok, cp = im.GetInputQueueCharacter(ctx, i)
    if not ok then break end
    if cp >= 32 and cp ~= 127 and cp <= 0x10FFFF and not (cp >= 0xD800 and cp <= 0xDFFF) then
      chars[#chars + 1] = utf8.char(cp)
    end
    i = i + 1
  end
  if #chars > 0 then e:insert_text(table.concat(chars), 'typing') end
end

function Input.mouse(e, im, ctx, view, hovered, clicked)
  local mx, my = im.GetMousePos(ctx)
  local function hit()
    if e.layout.hit then
      return e.layout:hit(mx - view.x + e.scroll_x - e.options.padding - (e.layout.offset_x or 0),
        my - view.y + e.scroll_y - e.options.padding)
    end
    local row = math.max(1, math.min(e.layout:row_count(),
      math.floor((my - view.y + e.scroll_y - e.options.padding) / view.line_height) + 1))
    return e.layout:hit_row(row, mx - view.x + e.scroll_x - e.options.padding)
  end
  if hovered then im.SetMouseCursor(ctx, im.MouseCursor_TextInput) end
  if clicked then
    local pos, affinity = hit()
    e.focused = true
    im.SetWindowFocus(ctx)
    if pos then
      local now, previous = e.clock(), e.last_click
      local count = previous and now - previous.time <= e.options.double_click_time and
        math.abs(mx - previous.x) <= 5 and math.abs(my - previous.y) <= 5 and
        (previous.count % 3 + 1) or 1
      e.last_click = {time = now, x = mx, y = my, count = count}
      e:mouse_down(pos, affinity, count, im.IsKeyDown(ctx, im.Mod_Shift), im.IsKeyDown(ctx, im.Mod_Ctrl))
    end
  end
  if hovered and im.IsMouseClicked(ctx, im.MouseButton_Right) then
    e.focused = true
    im.SetWindowFocus(ctx)
  end
  if e.drag and im.IsMouseDragging(ctx, im.MouseButton_Left) then
    local dt = math.min(0.05, math.max(0.001, e.clock() - (e.last_frame_time or e.clock())))
    if e.layout.drag_horizontal then
      e.layout:drag_horizontal(mx-view.x+e.scroll_x-e.options.padding-(e.layout.offset_x or 0),
        my-view.y+e.scroll_y-e.options.padding,dt)
    end
    local pos, affinity = hit()
    if pos then e:mouse_drag(pos, affinity) end
    local dy = my < view.y and my - view.y or my > view.y + view.h and my - view.y - view.h or 0
    local dx = mx < view.x and mx - view.x or mx > view.x + view.w and mx - view.x - view.w or 0
    local speed_y = math.max(-1800, math.min(1800, dy * 12))
    local speed_x = math.max(-1800, math.min(1800, dx * 12))
    if dy ~= 0 or (not e.options.wrap and dx ~= 0) then
      e.pending_scroll = {e.scroll_x + (e.options.wrap and 0 or speed_x * dt), e.scroll_y + speed_y * dt}
    end
  end
  if im.IsMouseReleased(ctx, im.MouseButton_Left) then e.drag = nil end
  if im.IsMouseClicked(ctx, im.MouseButton_Left) and not hovered and not im.IsWindowHovered(ctx) then
    e.focused, e.pending_motion = false, nil
  end
  if hovered or im.IsWindowHovered(ctx) then
    local wheel, horizontal = im.GetMouseWheel(ctx)
    if im.IsKeyDown(ctx, im.Mod_Ctrl) then
      if wheel ~= 0 then e:set_font_size(e.options.font_size + (wheel > 0 and 1 or -1) * e.options.zoom_step) end
    elseif wheel ~= 0 or horizontal ~= 0 then
      e.follow_caret, e.scroll_target = false, nil
      if im.IsKeyDown(ctx, im.Mod_Shift) and not e.options.wrap then
        e.pending_scroll = {e.scroll_x - wheel * view.line_height * 3 - horizontal * view.line_height * 3, e.scroll_y}
      else
        e.pending_scroll = {e.scroll_x - horizontal * view.line_height * 3, e.scroll_y - wheel * view.line_height * 3}
      end
    end
  end
end

return Input
