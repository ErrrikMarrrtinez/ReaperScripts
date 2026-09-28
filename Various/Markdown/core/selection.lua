-- @noindex
-- Same selection silhouette as ReaCode: round only exposed corners, join neighbors.
local Selection = {}

function Selection.rectangles(layout, first, last, top, bottom)
  if first > last then first, last = last, first end
  local rects = {}
  if first == last then return rects end
  -- Include neighbors outside the viewport so clipping does not change rounding.
  for number = math.max(1, top - 1), math.min(layout:row_count(), bottom + 1) do
    local row, line = layout:row(number)
    if row then
      local a, b = line.start + row.a, line.start + row.b
      local l, r = math.max(first, a), math.min(last, b)
      local newline = row.b == #line.text and line.finish < #layout.document.text and
        first <= b and last > b
      if l < r or newline then
        local x1 = layout:x_at(row, line, math.min(b, l) - line.start)
        local x2 = layout:x_at(row, line, math.max(a, r) - line.start)
        if newline then x2 = x2 + math.max(2, layout.space) end
        rects[#rects + 1] = {x1 = x1, x2 = math.max(x1, x2),
          y1 = (number - 1) * layout.line_height, y2 = number * layout.line_height,
          row = number, visible = number >= top and number <= bottom}
      end
    end
  end
  local function joins(neighbor, rect, x)
    return neighbor and math.abs(neighbor.row - rect.row) == 1 and
      x >= neighbor.x1 - 0.01 and x <= neighbor.x2 + 0.01
  end
  for i, rect in ipairs(rects) do
    local prev, next = rects[i - 1], rects[i + 1]
    rect.tl, rect.tr = not joins(prev, rect, rect.x1), not joins(prev, rect, rect.x2)
    rect.bl, rect.br = not joins(next, rect, rect.x1), not joins(next, rect, rect.x2)
  end
  return rects
end

return Selection
