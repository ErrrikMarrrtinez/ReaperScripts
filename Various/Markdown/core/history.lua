-- @noindex
-- A transaction stores the edit, plus exact cursor/selection states on both sides.
-- No duplicate before/result snapshots and no special case for an empty document.
local History = {}
History.__index = History

function History.new(limit, byte_limit, merge_delay)
  return setmetatable({entries = {}, index = 0, bytes = 0, epoch = 0,
    limit = limit or 1000, byte_limit = byte_limit or 16 * 1024 * 1024,
    merge_delay = merge_delay or 0.7}, History)
end

function History:clear()
  self.entries, self.index, self.bytes = {}, 0, 0
  self.epoch = self.epoch + 1
end

function History:record(edit, before, after, kind, now)
  local entries = self.entries
  for i = #entries, self.index + 1, -1 do
    self.bytes = self.bytes - entries[i].cost
    entries[i] = nil
  end
  local prev = entries[self.index]
  local merge = prev and prev.kind == kind and prev.epoch == self.epoch and
    now - prev.time <= self.merge_delay and before.anchor == nil and
    prev.after.caret == before.caret and prev.after.affinity == before.affinity
  if merge and kind == 'typing' and edit.removed == '' and prev.removed == '' and
      edit.at == prev.at + #prev.inserted and not edit.inserted:find('\n', 1, true) then
    self.bytes = self.bytes - prev.cost
    prev.inserted = prev.inserted .. edit.inserted
  elseif merge and kind == 'backspace' and edit.inserted == '' and prev.inserted == '' and
      edit.at + #edit.removed == prev.at then
    self.bytes = self.bytes - prev.cost
    prev.at, prev.removed = edit.at, edit.removed .. prev.removed
  elseif merge and kind == 'delete' and edit.inserted == '' and prev.inserted == '' and edit.at == prev.at then
    self.bytes = self.bytes - prev.cost
    prev.removed = prev.removed .. edit.removed
  else
    prev = {at = edit.at, removed = edit.removed, inserted = edit.inserted,
      before = before, kind = kind, epoch = self.epoch}
    entries[#entries + 1] = prev
  end
  prev.after, prev.time = after, now
  prev.cost = #prev.removed + #prev.inserted
  self.bytes = self.bytes + prev.cost
  -- Retain at least the latest edit, even if a single paste exceeds the cap.
  while #entries > 1 and (#entries > self.limit or self.bytes > self.byte_limit) do
    self.bytes = self.bytes - entries[1].cost
    table.remove(entries, 1)
  end
  self.index = #entries
end

function History:undo(document)
  local edit = self.entries[self.index]
  if not edit then return nil end
  document:replace(edit.at, edit.at + #edit.inserted, edit.removed)
  self.index, self.epoch = self.index - 1, self.epoch + 1
  return edit.before
end

function History:redo(document)
  local edit = self.entries[self.index + 1]
  if not edit then return nil end
  document:replace(edit.at, edit.at + #edit.removed, edit.inserted)
  self.index, self.epoch = self.index + 1, self.epoch + 1
  return edit.after
end

return History
