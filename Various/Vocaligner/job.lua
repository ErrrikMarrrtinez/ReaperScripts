-- @noindex
local M = {}; M.__index=M
function M.new(r, fn, budget)
  local self=setmetatable({r=r,budget=budget or 0.008,progress=0,label='',resources={},created_at=r.time_precise()},M)
  self.thread=coroutine.create(function() return fn(self) end)
  return self
end
function M:checkpoint(progress,label)
  if progress then self.progress=math.max(self.progress or 0,math.max(0,math.min(1,progress))) end
  if label then self.label=label end
  if self.cancelled then error('Cancelled',0) end
  if self.r.time_precise()>=self.deadline then coroutine.yield() end
end
-- Nested work owns a fixed portion of the parent bar. Audio reads and DTW
-- passes may each report 0..1 without resetting the whole operation.
function M:scope(first,last,label)
  local parent=self
  return setmetatable({checkpoint=function(_,progress,detail)
    parent:checkpoint(progress and first+(last-first)*math.max(0,math.min(1,progress)) or nil,detail or label)
  end},{__index=parent})
end
-- Marshal native array I/O through the deferred main loop. The coroutine only
-- requests it; nil return values are preserved instead of being mistaken for errors.
function M:call(fn,...)
  local result=coroutine.yield({call=fn,args=table.pack(...)})
  if not result[1] then error(result[2],0) end
  return table.unpack(result,2,result.n)
end
function M:close()
  for object,cleanup in pairs(self.resources) do pcall(cleanup,object) end
  self.resources={}
end
function M:step()
  if self.done then return end
  local started=self.r.time_precise()
  self.deadline=started+self.budget
  local reply=self.reply;self.reply=nil
  while true do
    local ok,value=coroutine.resume(self.thread,reply)
    if not ok then self.error=debug.traceback(self.thread,tostring(value));self.done=true;break end
    if coroutine.status(self.thread)=='dead' then self.result=value;self.done=true;self.progress=1;break end
    if type(value)~='table' or not value.call then break end
    reply=table.pack(pcall(value.call,table.unpack(value.args,1,value.args.n)))
    if self.r.time_precise()>=self.deadline then self.reply=reply;break end
  end
  if self.done then self:close();self.thread=nil end
  self.steps=(self.steps or 0)+1
  local elapsed=(self.r.time_precise()-started)*1000
  self.max_step_ms=math.max(self.max_step_ms or 0,elapsed)
  self.work_ms=(self.work_ms or 0)+elapsed
end
function M:cancel() self.cancelled=true;self.done=true;self.thread=nil;self.reply=nil;self:close() end
return M
