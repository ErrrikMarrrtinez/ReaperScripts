-- @noindex
-- Positions are zero-based UTF-8 byte boundaries, ranges are [first, last).
local U = {}

function U.clamp(text, pos)
  pos = math.max(0, math.min(#text, math.floor(pos or 0)))
  while pos > 0 and pos < #text do
    local b = text:byte(pos + 1)
    if b < 128 or b >= 192 then break end
    pos = pos - 1
  end
  return pos
end

function U.next(text, pos)
  if pos >= #text then return #text end
  local b = text:byte(pos + 1)
  return math.min(#text, pos + (b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4))
end

function U.prev(text, pos)
  return U.clamp(text, math.max(0, pos - 1))
end

function U.normalize(text)
  assert(type(text) == 'string', 'text must be a string')
  text = text:gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('%z', '')
  if utf8.len(text) then return text end
  local out, p = {}, 0
  while p < #text do
    local n = U.next(text, p)
    local part = text:sub(p + 1, n)
    if utf8.len(part) == 1 then
      out[#out + 1], p = part, n
    else
      out[#out + 1], p = utf8.char(0xFFFD), p + 1
    end
  end
  return table.concat(out)
end

function U.class(char)
  if char == '' then return 'end' end
  if char:match('^%s$') or char == '\194\160' or char == '\227\128\128' then return 'space' end
  if char:match('^[%w_]$') or (char:byte() >= 128 and not char:match('^[\226\227]')) then return 'word' end
  -- General punctuation (U+2000..206F) is separate from Cyrillic/CJK words.
  local cp = utf8.codepoint(char)
  if cp >= 128 and not (cp >= 0x2000 and cp <= 0x206F) and
      not (cp >= 0x3000 and cp <= 0x303F) then return 'word' end
  return 'punct'
end

function U.word_bounds(text, pos)
  pos = U.clamp(text, pos)
  if pos == #text and pos > 0 then pos = U.prev(text, pos) end
  local first, last = pos, U.next(text, pos)
  local kind = U.class(text:sub(first + 1, last))
  while first > 0 do
    local p = U.prev(text, first)
    if U.class(text:sub(p + 1, first)) ~= kind then break end
    first = p
  end
  while last < #text do
    local p = U.next(text, last)
    if U.class(text:sub(last + 1, p)) ~= kind then break end
    last = p
  end
  return first, last
end

-- Preserve ReaCode's Ctrl+arrow behavior: move across non-whitespace, then spaces.
function U.word_left(text, pos)
  local p = pos
  while p > 0 do
    local q = U.prev(text, p)
    if U.class(text:sub(q + 1, p)) ~= 'space' then break end
    p = q
  end
  while p > 0 do
    local q = U.prev(text, p)
    if U.class(text:sub(q + 1, p)) == 'space' then break end
    p = q
  end
  return p
end

function U.word_right(text, pos)
  local p = pos
  while p < #text do
    local q = U.next(text, p)
    if U.class(text:sub(p + 1, q)) == 'space' then break end
    p = q
  end
  while p < #text do
    local q = U.next(text, p)
    if U.class(text:sub(p + 1, q)) ~= 'space' then break end
    p = q
  end
  return p
end

return U
