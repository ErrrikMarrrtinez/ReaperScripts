-- @noindex
local load = ...
local Index = load('core.row_index')
local Plain = load('core.projection')
local Layout = {}
Layout.__index = Layout

function Layout.new(document, options)
  return setmetatable({document = document, options = options, cache = {}, entries = {},
    revision = -1, generation = 0, pending = 0, max_width = 0, background = 1,
    projection = Plain, glyphs = {}, work_units = 0}, Layout)
end

function Layout:configure(width, line_height, measure, font_key)
  width = math.max(1, math.floor(width))
  local o = self.options
  local changed = (o.wrap and self.width ~= width) or self.font_key ~= font_key or
    self.wrap ~= o.wrap or self.tab_size ~= o.tab_size or self.word_wrap ~= o.word_wrap
  self.measure, self.line_height = measure, line_height
  if self.font_key ~= font_key then self.glyphs, self.styled_glyphs = {}, nil end
  self.width, self.font_key = width, font_key
  self.wrap, self.tab_size, self.word_wrap = o.wrap, o.tab_size, o.word_wrap
  self.space = self:advance(' ', 0)
  if changed then self:invalidate() end
  self:sync()
end

function Layout:invalidate()
  -- Width changes must be O(1), even during a continuous window resize. Keep
  -- the line index and its last row counts; replace geometry lazily on access.
  self.generation = self.generation + 1
  self.pending, self.background, self.max_width = #self.entries, 1, 0
end

function Layout:advance(display, x, role)
  if role and role.widget_width then return role.widget_width end
  local glyphs = self.glyphs
  if role and role.font then
    self.styled_glyphs = self.styled_glyphs or {}
    glyphs = self.styled_glyphs[role.font]
    if not glyphs then glyphs = {}; self.styled_glyphs[role.font] = glyphs end
  end
  if display == '\t' then
    local stop = (glyphs[' '] or self.measure(' ', role)) * self.tab_size
    return stop - x % stop
  end
  local width = glyphs[display]
  if width == nil then
    width = display == '' and 0 or math.max(0, self.measure(display, role))
    glyphs[display] = width
  end
  return width + (role and role.pad_left or 0) + (role and role.pad_right or 0)
end

function Layout:unit(line, pos, x)
  local last, display, role = self.projection.next_unit(line, pos)
  assert(last > pos and last <= #line.text, 'projection must consume a source range')
  return last, display, self:advance(display, x, role), role
end

function Layout:sync()
  if self.revision == self.document.revision then return end
  local counts, entries, cache = {}, {}, {}
  self.max_width, self.pending, self.background = 0, 0, 1
  for i, line in ipairs(self.document.lines) do
    local entry = self.cache[line]
    if not entry then
      entry = {rows = {}, done = false, generation = self.generation,
        estimate = self.wrap and math.max(1, math.ceil(utf8.len(line.text) * self.space / self.width)) or 1}
      local change = self.document.last_change
      if change and change.previous_revision == self.revision and change.new_line == line then
        self:reuse_prefix(entry, self.cache[change.old_line], change.prefix_bytes)
      end
    end
    if entry.generation ~= self.generation or not entry.done then self.pending = self.pending + 1 end
    if entry.generation == self.generation then
      self.max_width = math.max(self.max_width, entry.max_width or 0)
    end
    entries[i], cache[line] = entry, entry
    counts[i] = entry.done and #entry.rows or math.max(entry.estimate, #entry.rows + 1)
  end
  self.entries, self.cache, self.index = entries, cache, Index.new(counts)
  self.revision = self.document.revision
end

-- Editing near the end of a huge logical line must not relayout its entire prefix
-- on every keystroke. Rewind one extra visual row for word-wrap lookahead.
function Layout:reuse_prefix(entry, previous, offset)
  if not previous or previous.generation ~= self.generation or offset == 0 then return end
  if self.wrap then
    local rows, lo, hi = previous.rows, 1, #previous.rows
    while lo < hi do
      local mid = (lo + hi) // 2
      if rows[mid].b < offset then lo = mid + 1 else hi = mid end
    end
    local keep = math.max(0, math.min(#rows, lo - 2))
    for i = 1, keep do entry.rows[i] = rows[i] end
    if keep > 0 then
      local p = rows[keep].b
      entry.job = {pos = p, first = p, x = 0, units = 0, chunks = {{p = p, x = 0}}}
      entry.max_width = previous.max_width
    end
  else
    local old = previous.rows[1] or previous.job
    if not old then return end
    local chunks, keep = old.chunks, 1
    local lo, hi = 1, #chunks
    while lo < hi do
      local mid = (lo + hi + 1) // 2
      if chunks[mid].p < offset then lo = mid else hi = mid - 1 end
    end
    keep = math.max(1, lo - 1)
    local prefix = {}
    for i = 1, keep do prefix[i] = chunks[i] end
    local c = chunks[keep]
    entry.job = {pos = c.p, first = 0, x = c.x, units = 0, chunks = prefix}
    entry.max_width = c.x
  end
end

local function reset_job(entry, pos)
  entry.job = {pos = pos, first = pos, x = 0, units = 0, chunks = {{p = pos, x = 0}}}
end

function Layout:finish_row(entry, last, width)
  local job = entry.job
  while #job.chunks > 1 and job.chunks[#job.chunks].p >= last do
    job.chunks[#job.chunks] = nil
  end
  entry.rows[#entry.rows + 1] = {a = job.first, b = last, width = width, chunks = job.chunks}
  entry.max_width = math.max(entry.max_width or 0, width)
  self.max_width = math.max(self.max_width, width)
  reset_job(entry, last)
end

function Layout:work_line(i, budget, target_row, target_pos)
  local entry, line = self.entries[i], self.document.lines[i]
  if not entry or budget.left <= 0 or budget.clock() >= budget.deadline then return end
  if entry.generation ~= self.generation then
    entry = {rows = {}, done = false, generation = self.generation, estimate = self.index.counts[i]}
    self.entries[i], self.cache[line] = entry, entry
  end
  if entry.done then return end
  if not entry.job then reset_job(entry, 0) end
  while budget.left > 0 do
    if target_row and #entry.rows >= target_row then break end
    if target_pos and #entry.rows > 0 and entry.rows[#entry.rows].b > target_pos then break end
    if budget.left % 128 == 0 and budget.clock() >= budget.deadline then break end
    local job = entry.job
    if job.pos == #line.text then
      self:finish_row(entry, job.pos, job.x)
      entry.done, entry.job = true, nil
      self.pending = self.pending - 1
      break
    end
    local last, display, advance, role = self:unit(line, job.pos, job.x)
    budget.left, self.work_units = budget.left - 1, self.work_units + 1
    if role and role.break_line then
      self:finish_row(entry, last, job.x)
    elseif self.wrap and job.x > 0 and job.x + advance > self.width then
      local boundary = self.word_wrap and job.break_pos or nil
      local width = boundary and job.break_x or job.x
      self:finish_row(entry, boundary or job.pos, width)
    else
      if job.units > 0 and job.units % 128 == 0 then
        job.chunks[#job.chunks + 1] = {p = job.pos, x = job.x}
      end
      job.pos, job.x, job.units = last, job.x + advance, job.units + 1
      if display == ' ' or display == '\t' or display == '-' then
        job.break_pos, job.break_x = last, job.x
      end
    end
  end
  self.index:set(i, entry.done and #entry.rows or math.max(entry.estimate, #entry.rows + 1))
  if entry.job then self.max_width = math.max(self.max_width, entry.job.x) end
end

-- One shared budget for viewport, caret and background work, including huge lines.
function Layout:tick(first_row, row_count, caret, clock, units, seconds, anchor)
  self:sync()
  local budget = {left = units or self.options.layout_budget, clock = clock,
    deadline = clock() + (seconds or self.options.layout_seconds)}
  -- Resolve the SOURCE position before choosing the viewport in the new index.
  -- Old pixel row numbers can refer to entirely different text after wrapping.
  if anchor then
    local i, line = self.document:line_at(anchor.pos)
    self:work_line(i, budget, nil, anchor.pos - line.start)
    local _, y = self:position(anchor.pos, 'downstream')
    if y then first_row = math.max(1, math.floor(y / self.line_height + anchor.fraction) + 1) end
  end
  if caret then
    local i, line = self.document:line_at(caret)
    self:work_line(i, budget, nil, caret - line.start)
    local _, _, row = self:position(caret, 'downstream')
    if row and row < first_row then first_row = row
    elseif row and row >= first_row + row_count then first_row = math.max(1, row - row_count + 1) end
  end
  local first_line, local_row = self.index:find(first_row)
  self:work_line(first_line, budget, local_row + row_count + self.options.overscan)
  local i = first_line + 1
  local bottom = first_row + row_count + self.options.overscan
  while i <= #self.entries and self.index:prefix(i - 1) < bottom and budget.left > 0 do
    self:work_line(i, budget, bottom - self.index:prefix(i - 1))
    i = i + 1
  end
  while self.background <= #self.entries and budget.left > 0 and clock() < budget.deadline do
    self:work_line(self.background, budget)
    local entry = self.entries[self.background]
    if entry.generation ~= self.generation or not entry.done then break end
    self.background = self.background + 1
  end
  return budget.left
end

function Layout:row_count()
  return self.index:prefix(#self.entries)
end

function Layout:height() return self:row_count() * self.line_height end
function Layout:row_y(number) return (number - 1) * self.line_height end
function Layout:row_height() return self.line_height end
function Layout:row_at_y(y) return math.max(1, math.floor(y / self.line_height) + 1) end

function Layout:row(number)
  if number < 1 or number > self:row_count() then return nil end
  local i, j = self.index:find(number)
  local entry = self.entries[i]
  if entry.generation ~= self.generation then return nil, self.document.lines[i], i, j end
  local row = entry.rows[j]
  -- No-wrap can already display the measured prefix of an enormous line.
  if not row and not self.wrap and entry.job and j == 1 then
    row = {a = 0, b = entry.job.pos, width = entry.job.x, chunks = entry.job.chunks, partial = true}
  end
  return row, self.document.lines[i], i, j
end

local function chunk_at(chunks, value, key)
  local lo, hi = 1, #chunks
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if chunks[mid][key] <= value then lo = mid else hi = mid - 1 end
  end
  return chunks[lo]
end

function Layout:x_at(row, line, offset)
  offset = math.max(row.a, math.min(row.b, offset))
  local chunk = chunk_at(row.chunks, offset, 'p')
  local pos, x = chunk.p, chunk.x
  while pos < offset do
    local last, _, width = self:unit(line, pos, x)
    if last > offset then break end
    pos, x = last, x + width
  end
  return x
end

function Layout:hit_row(number, x)
  local row, line = self:row(number)
  if not row then return nil end
  if x <= 0 then return line.start + row.a, 'downstream' end
  if x >= row.width then
    if row.partial then return nil end
    return line.start + row.b, row.b < #line.text and 'upstream' or 'downstream'
  end
  local chunk = chunk_at(row.chunks, x, 'x')
  local pos, px = chunk.p, chunk.x
  while pos < row.b do
    local last, _, width = self:unit(line, pos, px)
    if x <= px + width / 2 then return line.start + pos, 'downstream' end
    if x < px + width then
      return line.start + last, last == row.b and row.b < #line.text and 'upstream' or 'downstream'
    end
    pos, px = last, px + width
  end
  return line.start + row.b, 'upstream'
end

function Layout:position(pos, affinity)
  local i, line = self.document:line_at(pos)
  local entry, offset = self.entries[i], pos - line.start
  if not entry or entry.generation ~= self.generation then return nil end
  local rows = entry.rows
  local lo, hi = 1, #rows
  while lo < hi do
    local mid = (lo + hi) // 2
    if rows[mid].b < offset or (rows[mid].b == offset and affinity ~= 'upstream') then
      lo = mid + 1
    else hi = mid end
  end
  local row = rows[lo]
  if not row and not self.wrap then row = self:row(self.index:prefix(i - 1) + 1) end
  if not row or offset > row.b or (offset == row.b and not entry.done and affinity ~= 'upstream') then return nil end
  if offset < row.a then return nil end
  local number = self.index:prefix(i - 1) + lo
  return self:x_at(row, line, offset), (number - 1) * self.line_height, number
end

-- Iterate only the horizontal slice being painted; never submit an enormous string.
function Layout:visible_units(row, line, left, right, callback)
  local chunk = chunk_at(row.chunks, math.max(0, left), 'x')
  local pos, x = chunk.p, chunk.x
  while pos < row.b and x <= right do
    local last, display, width, role = self:unit(line, pos, x)
    if x + width >= left then
      if callback(display, x, width, role, line.start + pos, line.start + last) == false then break end
    end
    pos, x = last, x + width
  end
end

function Layout:visible_range(scroll_y, height, overscan)
  local n, h = self:row_count(), self.line_height
  overscan = overscan or self.options.overscan
  return math.max(1, math.floor(scroll_y / h) + 1 - overscan),
    math.min(n, math.ceil((scroll_y + height) / h) + overscan)
end

return Layout
