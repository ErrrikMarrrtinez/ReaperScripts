-- @noindex
local import=...;local Model=import('pitch/model');local M={};M.__index=M
local section='Vocaligner Pitch native 1'
function M.available(r)
  for _,name in ipairs({'VN_Version','VN_Model','VN_SelfTest','VN_Begin','VN_Poll','VN_Read','VN_Release','VN_Error'})do
    if type(r[name])~='function' then return false,'Native extension is not installed. Restart REAPER after installation.' end
  end
  local ok,version=pcall(r.VN_Version);if not ok or version~=1 then return false,'Native extension ABI mismatch.' end
  local same,model=pcall(r.VN_Model);if not same or model~=Model.version then return false,'Native model does not match this script.' end
  return true
end
-- по умолчанию C++ (если расширение установлено и прошло проверку), иначе — прежний EEL; явный выбор EEL запоминается
function M.preference(r)return r.GetExtState(section,'backend')=='eel' and 'eel' or 'cpp' end
function M.select(r,value)r.SetExtState(section,'backend',value=='cpp' and 'cpp' or 'eel',true)end
function M.new(r)
  local ok,why=M.available(r);assert(ok,why)
  assert(r.VN_SelfTest()==1,'Native numerical self-test failed; select EEL in Settings.')
  return setmetatable({r=r,native_pcm=true,fast=true,label='C++ SwiftF0 (worker)',self_test=true,kernel_ms=0,kernel_calls=0},M)
end
function M.choose(r,existing)
  if M.preference(r)=='cpp' then
    local ok,why=M.available(r)
    if ok then
      local made,engine=pcall(M.new,r)
      if made then if existing then existing.native_fallback=nil end;return engine end
      why=tostring(engine)
    end
    if existing then existing.native_fallback=why end
  elseif existing then existing.native_fallback=nil end
  return existing
end
function M:analyze_pcm(samples,center,count,job)
  local r=self.r;local began=r.time_precise()
  -- Independent tensors overlap by the model's seven-frame receptive radius.
  -- Keep the original outer padding, discard only internal overlap, cap at two
  -- workers so analysis leaves CPU headroom for REAPER playback.
  local parts={{first=0,last=count-1,keep_first=0,keep_last=count-1}}
  if count>=64 and self.parallel~=false then
    local mid=math.floor(count/2)
    parts={{first=0,last=mid+6,keep_first=0,keep_last=mid-1},
      {first=mid-7,last=count-1,keep_first=mid,keep_last=count-1}}
  end
  job:call(function()
    local pcm=r.new_array(samples)
    for _,part in ipairs(parts) do
      part.count=part.last-part.first+1
      local id=r.VN_Begin(pcm,center+part.first*256,part.count)
      assert(id and id>0,r.VN_Error(0));part.handle=id
      -- Own each job before returning to the coroutine, including cancellation
      -- while the Begin reply is pending or while another Begin fails.
      job.resources[part]=function(v)r.VN_Release(v.handle)end
    end
  end)
  while true do
    local ready=job:call(function()
      local done=true
      for _,part in ipairs(parts) do
        local status=r.VN_Poll(part.handle)
        assert(status==0 or status==1,r.VN_Error(part.handle))
        done=done and status==1
      end
      return done
    end)
    if ready then break end
    job:checkpoint(nil,'Pitch C++ analysis (up to 2 workers)')
    coroutine.yield()
  end
  local out={}
  for _,part in ipairs(parts) do
    local values=job:call(function()
      local a=r.new_array(part.count*2+1)
      assert(r.VN_Read(part.handle,a)==part.count,'Incomplete native result')
      local values=a.table();r.VN_Release(part.handle);job.resources[part]=nil
      return values
    end)
    self.kernel_ms=self.kernel_ms+values[part.count*2+1];self.kernel_calls=self.kernel_calls+1
    for index=part.keep_first,part.keep_last do
      local i=index-part.first+1;local hz,confidence=values[i*2-1],values[i*2]
      assert(type(hz)=='number' and hz==hz and hz>0 and hz<10000 and confidence==confidence and confidence>=0 and confidence<=1,'Invalid native prediction')
      out[index+1]={hz=hz,confidence=confidence}
    end
  end
  self.worker_wait_ms=(self.worker_wait_ms or 0)+(r.time_precise()-began)*1000
  self.workers=math.max(self.workers or 1,#parts)
  return out
end
return M
