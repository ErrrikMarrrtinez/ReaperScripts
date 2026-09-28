-- @noindex
local load = ...
local U = load('core.utf8')

-- Identity projection. Layout consumes display units with source byte ranges.
-- A future live Markdown projection can replace these units in THIS same view.
-- Changes of projection/active markup must invalidate layout via set_projection.
local Plain = {}
function Plain.next_unit(line, offset)
  local last = U.next(line.text, offset)
  return last, line.text:sub(offset + 1, last), nil
end

return Plain
