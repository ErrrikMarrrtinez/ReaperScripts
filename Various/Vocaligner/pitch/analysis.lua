-- @noindex
local import=...;local Audio=import('audio');local Features=import('pitch/features');local Model=import('pitch/model');local Wave=import('pitch/waveform');local M={}
local function call(job,fn,...) return job:call(fn,...) end
function M.key(s)
  return s.render_key..string.format('|offset=%.12g|length=%.12g',s.offset,s.len)
end
function M.capture(r,project,item,read_only)
  if not read_only and r.GetPlayStateEx and (r.GetPlayStateEx(project)&4)~=0 then error('Stop recording before using Pitch.',0) end
  local s=read_only and Audio.state(r,project,item) or Audio.capture(r,project,item,'pitch')
  if s.len>600 then error('Pitch: select a section of up to 10 minutes.',0) end
  s.pitch_key=M.key(s)
  return s
end
function M.check(r,s)
  if not Audio.project_open(r,s.project) then return nil,'The Pitch project was closed.' end
  if r.EnumProjects(-1)~=s.project then return nil,'Activate the captured project before applying Pitch.' end
  local ok,current=pcall(M.capture,r,s.project,s.item)
  if not ok then return nil,current end
  if current.guid~=s.guid or current.pitch_key~=s.pitch_key then return nil,'Audio or timing changed. Analyze the item again.' end
  return current
end
function M.run(r,s,engine,job,on_partial)
  local aa=call(job,r.CreateTakeAudioAccessor,s.take);assert(aa,'Cannot open the selected audio take')
  job.resources[aa]=r.DestroyAudioAccessor
  local origin=r.GetAudioAccessorStartTime(aa);local finish=r.GetAudioAccessorEndTime(aa)
  if math.abs(origin)>1e-4 then error('Pitch: unsupported accessor time origin. Copy report.',0) end
  local scale=1
  if math.abs(s.rate-1)>1e-6 and math.abs(finish-s.len*s.rate)<1e-4 and math.abs(finish-s.len)>1e-4 then scale=s.rate end
  local read_rate=math.floor(16000/scale+.5)
  if math.abs(read_rate*scale-16000)>.01 then error('Pitch: this play rate cannot be mapped to 16 kHz exactly. Glue a copy first.',0) end
  local feature=call(job,Features.new,r)
  local n=math.max(1,math.floor(s.len*16000/256));local frames={};local rows={};local hop=.016
  local result={frames=frames,hop=hop,len=s.len,model=Model.version,accessor_scale=scale,read_rate=read_rate,reads=0,peak=0,channels=s.channels,waveform=Wave.new()}
  local state_count=r.GetProjectStateChangeCount(s.project)
  -- 126 frames including context fit the existing 128-frame tensor slots.
  -- Stereo keeps the original read boundaries/channel selection exactly.
  local block=engine.fast and s.channels==1 and 112 or 64
  result.block_frames=block
  local buffer=call(job,r.new_array,((block+16)*256+2048)*s.channels)
  local function read(first,count)
    buffer.clear();local status=r.GetAudioAccessorSamples(aa,read_rate,s.channels,first/16000*scale,count,buffer)
    if type(status)=='number' and status<0 then error('Pitch: audio read failed at '..first/16000,0) end
    if status==0 then buffer.clear() end
    return buffer.table(1,count*s.channels),status
  end
  for first=0,n-1,block do
    if r.EnumProjects then assert(Audio.project_open(r,s.project),'The Pitch project was closed.') end
    if r.ValidatePtr2 then assert(r.ValidatePtr2(s.project,s.take,'MediaItem_Take*'),'The Pitch take was deleted.') end
    local now=r.GetProjectStateChangeCount(s.project)
    if now~=state_count then local current,why=M.check(r,s);assert(current,why);state_count=now end
    if r.AudioAccessorStateChanged(aa) then error('Audio changed during Pitch analysis. Analyze again.',0) end
    local last=math.min(n-1,first+block-1)
    -- Seven neural-context frames each side, plus the centered 2048 FFT window.
    local left,right=math.max(0,first-7),math.min(n-1,last+7)
    local a=math.max(0,left*256-1024);local b=math.min(math.ceil(s.len*16000),right*256+1024)
    local interleaved,status=call(job,read,a,b-a);result.reads=result.reads+1
    local energies={};for ch=1,s.channels do energies[ch]=0 end
    local mono=s.channels==1;local peak=0
    for j=1,#interleaved do
      local x=interleaved[j];if x~=x or math.abs(x)==math.huge then error('Invalid audio samples',0) end
      if not result.channel then local ch=(j-1)%s.channels+1;energies[ch]=energies[ch]+x*x end
      if mono then peak=math.max(peak,math.abs(x)) end
    end
    local channel=result.channel or 1
    if not result.channel then
      for ch=2,s.channels do if energies[ch]>energies[channel] then channel=ch end end
      if energies[channel]>1e-8 then result.channel=channel end
    end
    local samples=mono and interleaved or {}
    if not mono then
      for j=0,b-a-1 do local x=interleaved[j*s.channels+channel];samples[j+1]=x;peak=math.max(peak,math.abs(x)) end
    end
    result.peak=math.max(result.peak,peak)
    -- Reuse the input read for the model. Each interval is added exactly once,
    -- including the final partial hop; context overlap is never duplicated.
    Wave.append(result.waveform,samples,a,first*256,last==n-1 and math.ceil(s.len*16000) or (last+1)*256)
    if status==nil and peak==0 then result.empty_nil=(result.empty_nil or 0)+1 end
    for index=left,right do
      if not rows[index] then rows[index]=call(job,function()
        local started=r.time_precise();local row=feature:frame(samples,index*256-a)
        result.feature_ms=(result.feature_ms or 0)+(r.time_precise()-started)*1000;return row
      end) end
      job:checkpoint(first/n,'Pitch spectrum')
    end
    local input={};local count=right-left+1
    for bin=1,384 do for index=left,right do input[#input+1]=rows[index][bin] end end
    job:checkpoint(first/n,'Pitch model')
    local predictions=engine:infer(input,count,job)
    for index=first,last do
      local p=predictions[index-left+1];local sum,pk,lo,hi=0,0,0,0
      for k=index*256,index*256+255 do local x=samples[k-a+1] or 0;pk=math.max(pk,math.abs(x)) end
      for k=index*256-256,index*256+255 do local x=samples[k-a+1] or 0;sum=sum+x*x;lo=math.min(lo,x);hi=math.max(hi,x) end
      local level=math.sqrt(sum/512)
      if pk<.001 then p.confidence=0 end
      p.t=index*hop;p.rms=level;p.level_db=20*math.log(math.max(level,1e-7),10);p.lo=lo;p.hi=hi
      p.pitch=69+12*math.log(p.hz/440,2);frames[#frames+1]=p
    end
    for index=left,right do if index<last-6 then rows[index]=nil end end
    if on_partial then on_partial(result) end
    job:checkpoint((last+1)/n,'Pitch analysis')
  end
  job.resources[aa]=nil;call(job,r.DestroyAudioAccessor,aa)
  local current,why=M.check(r,s);assert(current,why)
  if result.empty_nil==result.reads and result.peak==0 then error('Pitch: accessor supplied no audio. Copy report.',0) end
  return result
end
return M
