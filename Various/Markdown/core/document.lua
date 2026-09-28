-- @noindex
local load = ...
local U = load('core.utf8')
local Document = {}
Document.__index = Document

local function split(text)
  local lines, p = {}, 1
  while true do
    local e = text:find('\n', p, true)
    lines[#lines + 1] = {text = text:sub(p, e and e - 1 or #text)}
    if not e then return lines end
    p = e + 1
  end
end

function Document.new(text)
  text = U.normalize(text or '')
  local self = setmetatable({text = text, lines = split(text), revision = 0}, Document)
  self:reindex(1)
  return self
end

function Document:reindex(first)
  local p = first > 1 and self.lines[first - 1].finish + 1 or 0
  for i = first, #self.lines do
    local line = self.lines[i]
    line.start, line.finish = p, p + #line.text
    p = line.finish + 1
  end
end

function Document:line_at(pos)
  local lo, hi = 1, #self.lines
  while lo < hi do
    local mid = (lo + hi) // 2
    if pos <= self.lines[mid].finish then hi = mid else lo = mid + 1 end
  end
  return lo, self.lines[lo]
end

function Document:replace(first, last, inserted)
  first, last = U.clamp(self.text, first), U.clamp(self.text, last)
  if first > last then first, last = last, first end
  inserted = U.normalize(inserted)
  local removed = self.text:sub(first + 1, last)
  if removed == inserted then return nil end
  local a, left = self:line_at(first)
  local b, right = self:line_at(last)
  local replacement = split(left.text:sub(1, first - left.start) .. inserted ..
    right.text:sub(last - right.start + 1))
  local lines = {}
  for i = 1, a - 1 do lines[#lines + 1] = self.lines[i] end
  for _, line in ipairs(replacement) do lines[#lines + 1] = line end
  for i = b + 1, #self.lines do lines[#lines + 1] = self.lines[i] end
  self.text = self.text:sub(1, first) .. inserted .. self.text:sub(last + 1)
  self.lines = lines
  self:reindex(a)
  self.revision = self.revision + 1
  local change = {at = first, removed = removed, inserted = inserted, first_line = a,
    old_line = left, new_line = replacement[1], prefix_bytes = first - left.start,
    previous_revision = self.revision - 1}
  self.last_change = change
  return change
end

return Document
