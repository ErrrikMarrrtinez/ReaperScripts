-- @noindex
local load = ...
local U = load('core.utf8')
local Actions = {}

local function escape(s) return (s:gsub('([^%w])', '%%%1')) end

function Actions.toggle_comment(e, prefix)
  if e.options.read_only then return false end
  assert(type(prefix) == 'string' and prefix ~= '' and not prefix:find('\n', 1, true), 'provide a comment prefix')
  local doc = e.document
  local a, b = e.anchor or e.caret, e.caret
  local first, last = math.min(a, b), math.max(a, b)
  local from, line = doc:line_at(first)
  local to = doc:line_at(last)
  local marker = prefix:gsub(' +$', '')
  assert(marker ~= '', 'comment prefix must contain a non-space character')
  local pattern = '^(%s*)' .. escape(marker) .. ' ?'
  local function selected_state(x, y)
    return {anchor = a > b and y or x, caret = a > b and x or y}
  end
  if e.anchor and from == to and (first > line.start or last < line.finish) then
    local selected = doc.text:sub(first + 1, last)
    local preceding = doc.text:sub(math.max(0, first - #prefix) + 1, first)
    local remove = preceding:sub(-#prefix) == prefix and #prefix or
      preceding:sub(-#marker) == marker and #marker or 0
    if remove > 0 then
      return e:replace_range(first - remove, first, '', 'comment', selected_state(first - remove, last - remove))
    end
    local stripped, count = selected:gsub(pattern, '%1', 1)
    local result = count > 0 and stripped or prefix .. selected
    return e:replace_range(first, last, result, 'comment', selected_state(first, first + #result))
  end
  if e.anchor and to > from and last == doc.lines[to].start then to = to - 1 end
  local all_commented = true
  for i = from, to do
    local s = doc.lines[i].text
    if s:match('%S') and not s:match(pattern) then all_commented = false; break end
  end
  local parts, changes = {}, {}
  for i = from, to do
    local s = doc.lines[i].text
    if all_commented then
      local stripped = s:gsub(pattern, '%1', 1)
      local indent = s:match('^%s*') or ''
      parts[#parts + 1] = stripped
      changes[#changes + 1] = {at = doc.lines[i].start + #indent, removed = #s - #stripped, added = 0}
    else
      parts[#parts + 1] = prefix .. s
      changes[#changes + 1] = {at = doc.lines[i].start, removed = 0, added = #prefix}
    end
  end
  local function map(pos)
    local delta = 0
    for _, c in ipairs(changes) do
      if pos >= c.at then delta = delta + c.added - math.min(c.removed, pos - c.at) end
    end
    return pos + delta
  end
  return e:replace_range(doc.lines[from].start, doc.lines[to].finish, table.concat(parts, '\n'),
    'comment', {caret = map(e.caret), anchor = e.anchor and map(e.anchor)})
end

function Actions.find_all(e, query, options)
  local opts, text = options or {}, e.document.text
  if query == '' then return {} end
  local a, b = opts.first or 0, opts.last or #text
  if opts.in_selection and e.anchor then a, b = math.min(e.anchor, e.caret), math.max(e.anchor, e.caret) end
  a, b = U.clamp(text, a), U.clamp(text, b)
  if a > b then a, b = b, a end
  local haystack = text:sub(a + 1, b)
  if opts.use_pattern and #haystack > (opts.pattern_byte_limit or 15000) then
    return {}, 'Lua patterns are limited to 15000 bytes by default; use literal search for large documents'
  end
  -- Lua lower() handles ASCII case. Unicode text is preserved and exact search works.
  if not opts.use_pattern and not opts.case_sensitive then haystack, query = haystack:lower(), query:lower() end
  local results, offset, limit = {}, 1, math.max(1, opts.limit or 10000)
  while offset <= #haystack + 1 and #results <= limit do
    local ok, first, last = pcall(string.find, haystack, query, offset, not opts.use_pattern)
    if not ok then return {}, 'Invalid Lua pattern: ' .. tostring(first) end
    if not first then break end
    local source_a, source_b = a + first - 1, a + last
    local valid = U.clamp(text, source_a) == source_a and U.clamp(text, source_b) == source_b
    if valid and opts.whole_word then
      local prev, next = U.prev(text, source_a), U.next(text, source_b)
      valid = U.class(text:sub(prev + 1, source_a)) ~= 'word' and U.class(text:sub(source_b + 1, next)) ~= 'word'
    end
    if valid then results[#results + 1] = {first = source_a, last = source_b, line = e.document:line_at(source_a)} end
    if opts.use_pattern and query:sub(1, 1) == '^' then break end
    -- Empty matches (e.g. ^ or a*) must also advance. Never split UTF-8 on replacement.
    offset = math.max(last + 1, first + 1, offset + 1)
  end
  if #results > limit then results[#results] = nil; return results, nil, true end
  return results
end

function Actions.replace_all(e, query, replacement, options)
  if e.options.read_only then return 0 end
  local matches, err, truncated = Actions.find_all(e, query, options)
  if err or #matches == 0 then return 0, err end
  if truncated then return 0, 'Match limit exceeded; increase options.limit before replacing all' end
  replacement = U.normalize(replacement)
  local first, last, text = matches[1].first, matches[#matches].last, e.document.text
  local parts, p = {}, first
  for _, match in ipairs(matches) do
    parts[#parts + 1] = text:sub(p + 1, match.first)
    parts[#parts + 1], p = replacement, match.last
  end
  local function map(pos)
    local delta = 0
    for _, match in ipairs(matches) do
      if pos < match.first then break end
      if pos <= match.last then return match.first + delta + #replacement end
      delta = delta + #replacement - (match.last - match.first)
    end
    return pos + delta
  end
  local changed = e:replace_range(first, last, table.concat(parts), 'replace_all',
    {caret = map(e.caret), anchor = e.anchor and map(e.anchor)})
  return changed and #matches or 0
end

return Actions
