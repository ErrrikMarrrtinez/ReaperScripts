-- @noindex
-- Fenwick tree: logical line <-> global visual row in O(log n).
local Index = {}
Index.__index = Index
function Index.new(counts)
  local self = setmetatable({counts = counts, tree = {}, n = #counts}, Index)
  for i = 1, #counts do self.tree[i] = counts[i] end
  for i = 1, #counts do
    local parent = i + (i & -i)
    if parent <= #counts then self.tree[parent] = self.tree[parent] + self.tree[i] end
  end
  return self
end
function Index:prefix(i)
  local sum = 0
  while i > 0 do sum, i = sum + self.tree[i], i - (i & -i) end
  return sum
end
function Index:set(i, count)
  local delta = count - self.counts[i]
  if delta == 0 then return end
  self.counts[i] = count
  while i <= self.n do self.tree[i], i = self.tree[i] + delta, i + (i & -i) end
end
function Index:find(row)
  row = math.min(self:prefix(self.n), math.max(1, math.floor(row)))
  local i, sum, step = 0, 0, 1
  while step * 2 <= self.n do step = step * 2 end
  while step > 0 do
    local j = i + step
    -- Heights can be fractional: differently ordered sums may differ by a few
    -- ulps at the bottom. Never advance past the final entry (also for <1px totals).
    if j < self.n and sum + self.tree[j] < row then i, sum = j, sum + self.tree[j] end
    step = step // 2
  end
  return i + 1, row - sum
end
return Index
