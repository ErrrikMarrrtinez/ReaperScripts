-- @noindex
local load = ...
local Selection = load('core.selection')
local Paint = {}

function Paint.draw(e, im, ctx, view, focused)
  local dl, layout, o = im.GetWindowDrawList(ctx), e.layout, e.options
  local ox, oy = view.x + o.padding - e.scroll_x, view.y + o.padding - e.scroll_y
  local first, last = layout:visible_range(math.max(0, e.scroll_y - o.padding), view.h)
  local caret_x, caret_y = layout:position(e.caret, e.affinity)
  im.DrawList_PushClipRect(dl, view.x + 1, view.y + 1, view.x + view.w, view.y + view.h, true)
  if focused and caret_y then
    im.DrawList_AddRectFilled(dl, view.x, oy + caret_y, view.x + view.w,
      oy + caret_y + view.line_height, o.current_row_color)
  end
  e.selection_coords = nil
  if e.anchor then
    local rectangles = Selection.rectangles(layout, e.anchor, e.caret, first, last)
    local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
    for _, rect in ipairs(rectangles) do
      if rect.visible then
        local flags = 0
        if rect.tl then flags = flags | im.DrawFlags_RoundCornersTopLeft end
        if rect.tr then flags = flags | im.DrawFlags_RoundCornersTopRight end
        if rect.bl then flags = flags | im.DrawFlags_RoundCornersBottomLeft end
        if rect.br then flags = flags | im.DrawFlags_RoundCornersBottomRight end
        if flags == 0 then flags = im.DrawFlags_RoundCornersNone end
        local x1, y1, x2, y2 = ox + rect.x1, oy + rect.y1, ox + rect.x2, oy + rect.y2
        im.DrawList_AddRectFilled(dl, x1, y1, x2, y2,
          focused and o.selection_color or o.inactive_selection_color, o.selection_rounding, flags)
        min_x, min_y, max_x, max_y = math.min(min_x, x1), math.min(min_y, y1), math.max(max_x, x2), math.max(max_y, y2)
      end
    end
    if min_x < math.huge then e.selection_coords = {x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y} end
  end
  local drawn, draw_calls = 0, 0
  for number = first, last do
    local row, line = layout:row(number)
    local y = oy + (number - 1) * view.line_height
    if y + view.line_height >= view.y and y <= view.y + view.h and drawn < o.max_draw_units then
      if row then
        local run, run_x, run_color = {}, nil, nil
        local function flush()
          if #run == 0 then return end
          im.DrawList_AddText(dl, ox + run_x, y, run_color, table.concat(run))
          draw_calls = draw_calls + 1
          run = {}
        end
        layout:visible_units(row, line, e.scroll_x - o.padding, e.scroll_x + view.w, function(display, x, _, role, a, b)
          if display ~= '\t' and display ~= '' then
            local color = o.text_color
            if o.color_for_range then color = o.color_for_range(e, a, b, role) or color end
            if color ~= run_color or #run >= 64 then flush() end
            if #run == 0 then run_x, run_color = x, color end
            run[#run + 1] = display
          else flush() end
          drawn = drawn + 1
          return drawn < o.max_draw_units
        end)
        flush()
      elseif layout.pending > 0 then
        im.DrawList_AddText(dl, view.x + o.padding, y, o.inactive_selection_color, '...')
      end
    end
  end
  if focused and caret_x and (e.clock() - e.blink_at) % 1 < 0.5 then
    im.DrawList_AddLine(dl, ox + caret_x, oy + caret_y, ox + caret_x, oy + caret_y + view.line_height, o.caret_color, 1)
  end
  im.DrawList_PopClipRect(dl)
  e.metrics = {first_row = first, last_row = last, rows = layout:row_count(),
    pending_lines = layout.pending, drawn_units = drawn, draw_calls = draw_calls, width = layout.width,
    line_height = view.line_height, logical_lines = #e.document.lines}
end

return Paint
