-- @noindex
local M={};M.__index=M
function M.new(r,operation)
 return setmetatable({r=r,operation=operation,entries={},snapshots={},started=r.time_precise(),last=r.time_precise()},M)
end
function M:mark(stage)
 local now=self.r.time_precise()
 if self.stage then self.entries[#self.entries+1]=('%s: %.1f ms elapsed'):format(self.stage,(now-self.last)*1000)end
 self.stage=stage;self.last=now
end
function M:summary()
 local out={'CLICK / MOUTH: '..self.operation,'REAPER: '..(self.r.GetAppVersion and self.r.GetAppVersion() or 'test host'),'stage: '..tostring(self.stage)}
 for _,v in ipairs(self.entries)do out[#out+1]=v end
 if self.detail then out[#out+1]=self.detail end
 if self.directory then out[#out+1]='Diagnostic files: '..self.directory end
 if self.save_error then out[#out+1]='Diagnostic save error: '..self.save_error end
 return table.concat(out,'\n')
end
function M:save(error_text)
 self:mark('failed');self.detail=tostring(error_text)
 if self.r.GetResourcePath and self.r.RecursiveCreateDirectory then
  local ok,why=pcall(function()
   self.directory=self.r.GetResourcePath()..'/Vocaligner-click-diagnostics/'..os.date('%Y%m%d-%H%M%S')..'-'..math.floor(self.started*1000000)
   self.r.RecursiveCreateDirectory(self.directory,0)
   for name,value in pairs(self.snapshots)do
    local f=assert(io.open(self.directory..'/'..name..'.txt','wb'));assert(f:write(value));f:close()
   end
   local f=assert(io.open(self.directory..'/report.txt','wb'));assert(f:write(self:summary()));f:close()
  end)
  if not ok then self.save_error=tostring(why)end
 end
 self.snapshots={}
end
function M.difference(a,b)
 local x,y={},{};for line in (a..'\n'):gmatch('(.-)\n')do x[#x+1]=line end;for line in (b..'\n'):gmatch('(.-)\n')do y[#y+1]=line end
 for i=1,math.max(#x,#y)do if x[i]~=y[i]then return ('Chunk difference at line %d\nExpected: %s\nActual: %s'):format(i,tostring(x[i]),tostring(y[i]))end end
 return 'No text difference'
end
return M
