-- @noindex
local load = ...
local Input, Paint = load('ui.input'), load('ui.paint')
local Widget = {}

function Widget.prepare(e, ctx, imgui)
  if not e.ui then
    if not imgui then
      assert(reaper and reaper.ImGui_GetBuiltinPath, 'Multiline requires ReaImGui')
      imgui = dofile(reaper.ImGui_GetBuiltinPath() .. '/imgui.lua')('0.9.2.3')
    end
    e.ui = {ctx = ctx, im = imgui, fonts = {}}
  end
  local ui, o = e.ui, e.options
  assert(ui.ctx == ctx, 'use a separate editor instance for each ImGui context')
  local key = o.font_family .. ':' .. o.font_size
  if not ui.fonts[key] then
    local font = ui.im.CreateFont(o.font_family, o.font_size)
    ui.im.Attach(ctx, font)
    ui.fonts[key] = font
  end
  ui.font, ui.font_key = ui.fonts[key], key
  if o.markdown then load('markdown.view').prepare(e, ctx, ui.im) end
end

function Widget.dispose(e)
  if e.ui.markdown then load('markdown.view').dispose(e) end
  for _, font in pairs(e.ui.fonts) do e.ui.im.Detach(e.ui.ctx, font) end
  e.ui = nil
end

local function top_anchor(e, scroll)
  local layout = e.layout
  if not layout.index or layout.revision ~= e.document.revision then return nil end
  local n = layout:row_at_y(scroll - e.options.padding)
  local row, line = layout:row(n)
  if not row then return nil end
  return {pos = line.start + row.a, fraction =
    (scroll - e.options.padding - layout:row_y(n)) / layout:row_height(n)}
end

local function restore_anchor(e, im, ctx, view)
  if not e.reflow_anchor or e.follow_caret or e.scroll_target or e.pending_scroll then return end
  local _, y, row = e.layout:position(e.reflow_anchor.pos, 'downstream')
  if not y then return end
  local sy = math.max(0, math.min(y + e.options.padding + e.reflow_anchor.fraction * e.layout:row_height(row),
    math.max(0, e.layout:height() + e.options.padding * 2 - view.h)))
  if math.abs(sy - e.scroll_y) > 0.1 then im.SetScrollY(ctx, sy) end
  -- Keep the same source offset throughout successive resizes. Replacing it
  -- with each newly wrapped row's start would slowly drift up a long paragraph.
  e.scroll_y = sy
end

local function scroll_request(e, im, ctx, view)
  local sx, sy = e.scroll_x, e.scroll_y
  local layout, o = e.layout, e.options
  if e.pending_scroll then
    sx, sy = table.unpack(e.pending_scroll)
    e.pending_scroll, e.reflow_anchor = nil, nil
  end
  if e.follow_caret or e.scroll_target then
    if layout.reveal_position then layout:reveal_position(e.scroll_target or e.caret) end
    local x, y, row = layout:position(e.scroll_target or e.caret, e.scroll_target and 'downstream' or e.affinity)
    if x then
      x, y = x + o.padding, y + o.padding
      if e.scroll_target and e.scroll_align=='start' then sy=y-o.padding
      elseif y < sy + o.padding then sy = y - o.padding
      elseif y + layout:row_height(row) > sy + view.h - o.padding then sy = y + layout:row_height(row) - view.h + o.padding end
      if not o.wrap then
        if x < sx + o.padding then sx = x - o.padding
        elseif x + 2 > sx + view.w - o.padding then sx = x + 2 - view.w + o.padding end
      end
      e.follow_caret, e.scroll_target, e.reflow_anchor = false, nil, nil
      e.scroll_align=nil
    end
  end
  sx = o.wrap and 0 or math.max(0, math.min(sx, math.max(0, layout.max_width + o.padding * 2 + 2 - view.w)))
  sy = math.max(0, math.min(sy, math.max(0, layout:height() + o.padding * 2 - view.h)))
  if math.abs(sx - e.scroll_x) > 0.1 then im.SetScrollX(ctx, sx) end
  if math.abs(sy - e.scroll_y) > 0.1 then im.SetScrollY(ctx, sy) end
  -- Apply the same effective viewport to painting now and to the native scrollbar
  -- on its next frame. Background reflow is anchored BEFORE mouse hit-testing.
  e.scroll_x, e.scroll_y = sx, sy
end

function Widget.render(e, ctx, label, width, height)
  assert(e.ui and e.ui.ctx == ctx, 'call editor:prepare(ctx) BEFORE ImGui.Begin each frame')
  local ui, o, layout = e.ui, e.options, e.layout
  local im, start_time = ui.im, e.clock()
  im.PushFont(ctx, ui.font)
  im.PushStyleVar(ctx, im.StyleVar_WindowPadding, 0, 0)
  im.PushStyleVar(ctx, im.StyleVar_ChildRounding, 2)
  im.PushStyleVar(ctx, im.StyleVar_ChildBorderSize, 1)
  im.PushStyleColor(ctx, im.Col_ChildBg, o.background)
  local flags = im.WindowFlags_NoScrollWithMouse | im.WindowFlags_NoNavInputs
  if not o.wrap then flags = flags | im.WindowFlags_HorizontalScrollbar end
  if e.request_focus then im.SetNextWindowFocus(ctx) end
  if ui.content then im.SetNextWindowContentSize(ctx, ui.content[1], ui.content[2]) end
  local visible = im.BeginChild(ctx, label, width or 0, height or 0, im.ChildFlags_Border, flags)
  im.PopStyleColor(ctx)
  im.PopStyleVar(ctx, 3)
  if visible then
    local native_x, native_y = im.GetScrollX(ctx), im.GetScrollY(ctx)
    local cursor_x, cursor_y = im.GetCursorScreenPos(ctx)
    local ww, wh = im.GetWindowSize(ctx)
    local scrollbar = im.GetStyleVar(ctx, im.StyleVar_ScrollbarSize)
    local vertical_bar = im.GetScrollMaxY(ctx) > 0
    local horizontal_bar = not o.wrap and im.GetScrollMaxX(ctx) > 0
    local view = {x = cursor_x + native_x, y = cursor_y + native_y,
      w = math.max(1, ww - 2 - (vertical_bar and scrollbar or 0)),
      h = math.max(1, wh - 2 - (horizontal_bar and scrollbar or 0)),
      line_height = im.GetTextLineHeight(ctx)}
    -- ImGui may round a requested scroll to whole pixels. A native scrollbar
    -- move, explicit navigation or a text edit establishes a new source anchor.
    if math.abs(native_y - e.scroll_y) >= 1 or layout.revision ~= e.document.revision or
      e.follow_caret or e.scroll_target or e.pending_scroll then e.reflow_anchor = nil end
    if not (e.follow_caret or e.scroll_target or e.pending_scroll) then
      e.reflow_anchor = e.reflow_anchor or top_anchor(e, native_y)
    end
    e.scroll_x, e.scroll_y = native_x, native_y
    local content_width=math.max(1, view.w-o.padding*2)
    if o.markdown and o.markdown_max_width then content_width=math.min(content_width,o.markdown_max_width) end
    layout.offset_x=o.markdown and math.max(0,(view.w-o.padding*2-content_width)/2) or 0
    layout:configure(content_width, view.line_height,
      function(s)
        -- CalcTextSize rounds the final width. Averaging a repeated glyph keeps
        -- subpixel advances instead of adding one rounding error per character.
        -- Paint limits each native text run to 64 units (error remains < 1px).
        if #s <= 4 then return im.CalcTextSize(ctx, string.rep(s, 128)) / 128 end
        return im.CalcTextSize(ctx, s)
      end, ui.font_key .. ':' .. view.line_height)
    if o.markdown then load('markdown.view').before_layout(e, im, ctx) end
    local first_row = layout:row_at_y(native_y - o.padding)
    local page_rows = math.max(1, math.floor(view.h / view.line_height))
    local budget = layout:tick(first_row, page_rows,
      e.scroll_target or (e.follow_caret and e.caret), e.clock, nil,
      math.max(0, o.layout_seconds - (e.clock() - start_time)), e.reflow_anchor)
    -- Background refinement can change row counts ABOVE the view. Preserve its
    -- source anchor just as during a resize, unless input explicitly scrolls it.
    restore_anchor(e, im, ctx, view)
    im.SetCursorScreenPos(ctx, view.x, view.y)
    if o.markdown then im.SetNextItemAllowOverlap(ctx) end
    im.InvisibleButton(ctx, '##surface', view.w, view.h)
    local hovered, clicked = im.IsItemHovered(ctx), im.IsItemClicked(ctx)
    if e.request_focus then
      e.focused, e.request_focus = true, nil
      im.SetWindowFocus(ctx)
    end
    local handled = o.markdown and load('markdown.view').mouse(e, im, ctx, view, hovered, clicked)
    if not handled then Input.mouse(e, im, ctx, view, hovered, clicked) end
    local focused = e.focused and im.IsWindowFocused(ctx)
    if focused then
      im.SetNextFrameWantCaptureKeyboard(ctx, true)
      if e.pending_motion and e:move(table.unpack(e.pending_motion)) then e.pending_motion = nil end
      if not ((o.markdown or o.markdown_shortcuts) and load('markdown.commands').keyboard(e, im, ctx)) then
        Input.keyboard(e, im, ctx, page_rows)
      end
    end
    if layout.revision ~= e.document.revision then
      layout:sync()
      layout:tick(first_row, page_rows, e.caret, e.clock, budget,
        math.max(0, o.layout_seconds - (e.clock() - start_time)))
    end
    ui.content = {o.wrap and view.w or math.max(view.w, layout.max_width + o.padding * 2 + 2),
      math.max(view.h, layout:height() + o.padding * 2)}
    scroll_request(e, im, ctx, view)
    if o.markdown then load('markdown.view').draw(e, im, ctx, view, focused)
    else Paint.draw(e, im, ctx, view, focused) end
    im.SetCursorScreenPos(ctx, cursor_x, cursor_y)
    im.Dummy(ctx, ui.content[1], ui.content[2])
    im.EndChild(ctx)
  else
    e.drag, e.pending_motion = nil, nil
  end
  -- ReaImGui already calls EndChild internally when BeginChild returns false.
  im.PopFont(ctx)
  e.last_frame_time = e.clock()
  local changed = e.last_render_revision ~= e.document.revision
  e.last_render_revision = e.document.revision
  return changed, e.document.text
end

return Widget
