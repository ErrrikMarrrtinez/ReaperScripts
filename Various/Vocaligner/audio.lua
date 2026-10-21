-- @noindex
local import=...;local DSP=import('dsp');local Envelope=import('envelope');local M={}
local item_fields={'D_POSITION','D_LENGTH','B_LOOPSRC','B_MUTE','C_LOCK'}
local take_fields={'D_STARTOFFS','D_PLAYRATE','D_PITCH','B_PPITCH','I_CHANMODE','D_VOL','I_PITCHMODE','I_STRETCHFLAGS','F_STRETCHFADESIZE'}
function M.project_open(r,project)
  local i=0;while true do local p=r.EnumProjects(i);if not p then return false end;if p==project then return true end;i=i+1 end
end
function M.state(r,project,item)
  if not r.ValidatePtr2(project,item,'MediaItem*') then error('An item was deleted. Capture the selection again.',0) end
  local take=r.GetActiveTake(item)
  if not take or r.TakeIsMIDI(take) then error('Select audio items with active audio takes.',0) end
  local source=r.GetMediaItemTake_Source(take)
  local _,guid=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
  local s={item=item,take=take,source=source,guid=guid,project=project,name=r.GetTakeName(take),markers={}}
  s.item_gain=r.GetMediaItemInfo_Value(item,'D_VOL')
  s.fade_in=math.max(0,r.GetMediaItemInfo_Value(item,'D_FADEINLEN'),r.GetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO'))
  s.fade_out=math.max(0,r.GetMediaItemInfo_Value(item,'D_FADEOUTLEN'),r.GetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO'))
  local signature={guid,tostring(source)}
  for _,k in ipairs(item_fields) do s[k]=r.GetMediaItemInfo_Value(item,k);signature[#signature+1]=string.format('%.17g',s[k]) end
  for _,k in ipairs(take_fields) do s[k]=r.GetMediaItemTakeInfo_Value(take,k);signature[#signature+1]=string.format('%.17g',s[k]) end
  for i=0,r.GetTakeNumStretchMarkers(take)-1 do
    local _,p,src=r.GetTakeStretchMarker(take,i);local slope=r.GetTakeStretchMarkerSlope(take,i)
    s.markers[#s.markers+1]={pos=p,src=src,slope=slope}
    signature[#signature+1]=string.format('%.17g:%.17g:%.17g',p,src,slope)
  end
  s.volume_envelope=Envelope.read(r,take)
  s.volume_points=Envelope.describe(r,take)
  local filename=r.GetMediaSourceFileName and r.GetMediaSourceFileName(source) or tostring(source)
  local source_type=r.GetMediaSourceType and r.GetMediaSourceType(source) or ''
  local section=''
  if r.PCM_Source_GetSectionInfo then
    local yes,offset,length,reverse=r.PCM_Source_GetSectionInfo(source)
    if yes then section=string.format('|%.17g|%.17g|%s',offset,length,tostring(reverse)) end
  end
  local parent=source
  for _=1,8 do
    parent=r.GetMediaSourceParent and r.GetMediaSourceParent(parent)
    if not parent then break end
    local path=r.GetMediaSourceFileName and r.GetMediaSourceFileName(parent) or ''
    if path~='' then filename=path end
    if r.PCM_Source_GetSectionInfo then
      local yes,offset,length,reverse=r.PCM_Source_GetSectionInfo(parent)
      if yes then section=section..string.format('|%.17g|%.17g|%s',offset,length,tostring(reverse)) end
    end
  end
  if filename=='' then filename=tostring(source) end
  s.source_length=r.GetMediaSourceLength(source)
  s.source_rate=r.GetMediaSourceSampleRate(source)
  section=section..string.format('|%.17g|%.17g',s.source_length or 0,s.source_rate or 0)
  s.source_key=tostring(filename)..'|'..tostring(source_type)..section
  local render={s.source_key,tostring(s.B_LOOPSRC)}
  for _,k in ipairs(take_fields) do if k~='D_STARTOFFS' then render[#render+1]=k..'='..string.format('%.17g',s[k]) end end
  for _,m in ipairs(s.markers) do render[#render+1]=string.format('%.17g:%.17g:%.17g',m.pos,m.src,m.slope) end
  s.render_key=table.concat(render,'|')
  signature[#signature+1]=s.volume_envelope or ''
  s.signature=table.concat(signature,'|');s.pos=s.D_POSITION;s.len=s.D_LENGTH
  s.rate=s.D_PLAYRATE;s.offset=s.D_STARTOFFS
  s.source_overrun=math.max(0,s.offset+s.len*s.rate-(s.source_length or 0))
  return s
end
function M.capture(r,project,item,is_dub)
  local s=M.state(r,project,item)
  local source_only=is_dub=='cleanup' or is_dub=='pitch'
  s.cleanup_capture=source_only or nil
  if s.len<.06 or s.rate<=0 then error('The audio item is too short or has an invalid play rate.',0) end
  if s.B_MUTE~=0 and is_dub~='pitch' then error('Unmute '..s.name..' before capturing it.',0) end
  if is_dub and s.C_LOCK~=0 then error(s.name..' is locked.',0) end
  local length,is_qn=r.GetMediaSourceLength(s.source)
  if is_qn then error(s.name..': tempo-based (MIDI/QN) sources are not supported — only audio files measured in seconds.',0) end
  if not length or length<=0 then error(s.name..': the source reports no length (offline or missing media file, or an empty item). Relink the file or remove the item.',0) end
  local source_rate=r.GetMediaSourceSampleRate and r.GetMediaSourceSampleRate(s.source) or 0
  local edge_tolerance=2/(source_rate>0 and source_rate or 44100)
  local source_end=#s.markers>0 and s.markers[#s.markers].src or s.offset+s.len*s.rate
  s.source_length=length;s.source_rate=source_rate;s.source_overrun=source_end-length
  if not source_only and s.B_LOOPSRC~=0 and s.source_overrun>edge_tolerance then
    error(string.format('Looped source repetitions are not supported yet: %s plays %.1f ms past the end of its file, which repeats the file start (source %.9f s, end %.9f s, rate %.0f Hz). Press "Trim looped tails" or shorten the item.',
      s.name,s.source_overrun*1000,length,source_end,source_rate),0)
  end
  if not source_only and #s.markers>0 then
    for _,m in ipairs(s.markers) do if math.abs(m.slope)>1e-9 then error('Curved stretch markers are not supported yet: '..s.name,0) end end
    if math.abs(s.markers[1].pos)>1e-6 or math.abs(s.markers[#s.markers].pos-s.len*s.rate)>1e-5 then
      error('Existing stretch markers need explicit markers at both item edges: '..s.name,0)
    end
    for i=2,#s.markers do if s.markers[i].src<=s.markers[i-1].src then error('Non-monotonic source markers: '..s.name,0) end end
  end
  s.channels=r.GetMediaSourceNumChannels(s.source)
  if s.channels<1 or s.channels>8 then error('Supported sources have 1 to 8 audio channels.',0) end
  return s
end
-- Several consecutive items on one track act as one role (one timeline with
-- silent gaps). The composite keeps the first item's handles for read-only
-- inspection; every write path and every change check goes through `parts`.
local function compose(parts,project)
  table.sort(parts,function(a,b)return a.pos<b.pos end)
  local first,last=parts[1],parts[#parts]
  local s={composite=true,parts=parts,item=first.item,take=first.take,source=first.source,project=project,markers={},
    pos=first.pos,len=last.pos+last.len-first.pos,rate=1,offset=0,channels=first.channels,item_gain=1,
    source_overrun=0,B_LOOPSRC=0,B_MUTE=0,C_LOCK=0,D_PLAYRATE=1,D_STARTOFFS=0}
  s.D_POSITION=s.pos;s.D_LENGTH=s.len
  for _,k in ipairs({'D_PITCH','B_PPITCH','I_CHANMODE','D_VOL','I_PITCHMODE','I_STRETCHFLAGS','F_STRETCHFADESIZE'})do s[k]=first[k]end
  local guids,signature,source_key,render_key={},{},{},{}
  local reach,owner=-math.huge,nil;local overlap=0
  for i,p in ipairs(parts)do
    guids[i]=p.guid;signature[i]=p.signature;source_key[i]=p.source_key;render_key[i]=p.render_key
    -- Consecutive items may overlap like crossfaded edits: up to half of the
    -- shorter item and at most 2 s. Their audio is summed there, as REAPER
    -- plays it. A larger overlap looks like stacked takes, not a sequence.
    if owner and p.pos<reach-1e-9 then
      local amount=math.min(reach,p.pos+p.len)-p.pos;local shorter=math.min(owner.len,p.len)
      if amount>math.min(2,shorter*.5)+1e-9 then
        error(string.format('Selected items on one track overlap by %.2f s (%s and %s), more than consecutive edits allow (half the shorter item, at most 2 s). Select one take per position, or turn off "Group items per track".',amount,owner.name,p.name),0)
      end
      overlap=overlap+amount
    end
    if p.pos+p.len>reach then reach,owner=p.pos+p.len,p end
  end
  s.overlap_s=overlap
  s.guid='group:'..table.concat(guids,'+');s.name=string.format('%s +%d',first.name,#parts-1)
  s.signature=table.concat(signature,'||');s.source_key=table.concat(source_key,'||');s.render_key=table.concat(render_key,'||')
  return s
end
function M.capture_group(r,project,items,is_dub)
  if #items==1 then return M.capture(r,project,items[1],is_dub)end
  local parts={};local track
  for i,item in ipairs(items)do
    local s=M.capture(r,project,item,is_dub);parts[i]=s
    local t=r.GetMediaItemTrack and r.GetMediaItemTrack(item)
    if track and t~=track then error('Grouped items must be on one track: '..s.name,0)end;track=t
    if parts[1].channels~=s.channels then error('Grouped items must have the same channel count: '..s.name,0)end
  end
  local s=compose(parts,project);s.track=track;return s
end
-- Read the same items again (a role whose geometry changed since capture).
function M.recapture(r,s,is_dub)
  if s.composite then local items={};for i,p in ipairs(s.parts)do items[i]=p.item end;return M.capture_group(r,s.project,items,is_dub)end
  return M.capture(r,s.project,s.item,is_dub)
end
-- Current host state of a captured role, composite-aware.
function M.current(r,s)
  if not s.composite then return M.state(r,s.project,s.item)end
  local parts={};for i,p in ipairs(s.parts)do parts[i]=M.state(r,s.project,p.item);parts[i].channels=p.channels end
  return compose(parts,s.project)
end
function M.parts(s) return s.composite and s.parts or {s} end
-- Index of the first part containing a virtual time, or nil inside a gap.
function M.part_index(s,t)
  if not s.composite then return 1 end
  for k,p in ipairs(s.parts)do local a=p.pos-s.pos;if t>=a-1e-9 and t<=a+p.len+1e-9 then return k end end
end
-- The part holding a virtual time, with the time inside that part. A time in
-- a gap resolves to the nearest part edge.
function M.part_at(s,t)
  if not s.composite then return s,t,0 end
  local previous
  for _,p in ipairs(s.parts)do
    local a=p.pos-s.pos;local b=a+p.len
    if t<=b+1e-9 then
      if t>=a-1e-9 then return p,math.max(0,math.min(p.len,t-a)),a end
      if previous then return previous,previous.len,previous.pos-s.pos end
      return p,0,a
    end
    previous=p
  end
  return previous,previous.len,previous.pos-s.pos
end
function M.unchanged(r,s,expected)
  if not M.project_open(r,s.project) then return false,'The captured project was closed.' end
  local ok,current=pcall(M.current,r,s)
  if not ok then return false,current end
  if s.cleanup_capture and not expected then
    if current.guid==s.guid and current.source_key==s.source_key and current.render_key==s.render_key
      and math.abs(current.offset-s.offset)<1e-8 and math.abs(current.len-s.len)<1e-8 then return true end
    return false,'The source audio changed while reading '..s.name..'. Get the item again.'
  end
  if current.signature~=(expected or s.signature) then return false,'Captured audio changed: '..s.name..'. Capture again.' end
  return true
end
-- Accept our own applied states and the captured state after REAPER Undo/Redo.
-- An arbitrary manual edit still invalidates the cached analysis.
function M.check_dub(r,d)
  local s=d.snapshot
  if not M.project_open(r,s.project) then return false,'The captured project was closed.' end
  if d.hybrid_owner then local yes,why=import('align/hybrid/render').check(r,d);if yes~=nil then return yes,why end end
  local ok,current=pcall(M.current,r,s)
  if not ok then return false,current end
  if d.plan and d.plan.volume_only then return import('cleanup_state').check(r,d,current) end
  if current.signature==s.signature then
    d.applied=false;d.applied_plan=nil;d.applied_cleanup=nil;d.applied_cfg=nil;d.layers=nil
    local points=0
    for _,p in ipairs(M.parts(current))do
      local env=r.GetTakeEnvelopeByName and r.GetTakeEnvelopeByName(p.take,'Volume')
      points=points+(env and r.CountEnvelopePoints(env) or 0)
    end
    d.envelope_points=points
    return true
  end
  local output=d.outputs and d.outputs[current.signature]
  if output then
    d.applied=type(output)~='table'or output.timing_applied~=false
    if type(output)=='table' then
      d.applied_plan=output.plan;d.applied_cleanup=output.cleanup;d.envelope_points=output.envelope_points;d.layers=output.layers
      d.applied_cfg=output.cfg
      if output.timing_applied==false then d.applied_plan=nil end
    end
    return true
  end
  return false,'Captured audio changed: '..s.name..'. Capture again.'
end
-- t is heard time relative to the captured item; output is source media seconds.
function M.source_time(s,t)
  if s.composite then local part,local_t=M.part_at(s,t);return M.source_time(part,local_t)end
  local p=t*s.rate
  if #s.markers<2 then return s.offset+p end
  local a,b=s.markers[1],s.markers[#s.markers]
  local lo,hi=1,#s.markers
  while hi-lo>1 do local mid=(lo+hi)//2;if s.markers[mid].pos<=p then lo=mid else hi=mid end end
  a,b=s.markers[lo],s.markers[hi]
  return a.src+(b.src-a.src)*(p-a.pos)/(b.pos-a.pos)
end
-- Inverse of source_time: heard item time of a source media position.
function M.item_time(s,src)
  if #s.markers<2 then return (src-s.offset)/s.rate end
  local m=s.markers;local lo,hi=1,#m
  for i=2,#m do if m[i].src<=m[i-1].src then return (src-s.offset)/s.rate end end
  while hi-lo>1 do local mid=(lo+hi)//2;if m[mid].src<=src then lo=mid else hi=mid end end
  local a,b=m[lo],m[hi]
  return (a.pos+(b.pos-a.pos)*(src-a.src)/(b.src-a.src))/s.rate
end
-- Item gain is outside our source analysis. A gain-only edit may invalidate the
-- native accessor without changing its source/timing; accept only that case.
function M.validate_accessor(r,s,aa)
  if not r.AudioAccessorStateChanged(aa) then return end
  local current=M.current(r,s)
  if s.cleanup_capture and current.item_gain~=s.item_gain and current.signature==s.signature
    and current.source_key==s.source_key and current.render_key==s.render_key and r.AudioAccessorUpdate then
    r.AudioAccessorUpdate(aa);s.item_gain=current.item_gain;return
  end
  error('Audio changed during analysis. Capture again.',0)
end
function M.analyze(r,s,cfg,job,label,engine)
  if s.len>cfg.max_seconds then error('Capture sections shorter than '..cfg.max_seconds..' seconds.',0) end
  local valid,why=M.unchanged(r,s);if not valid then error(why,0) end
  -- One reader per item. A grouped role reads every item into one virtual
  -- timeline; the gaps between items stay digital silence.
  local readers={}
  for i,p in ipairs(M.parts(s)) do
    local aa=r.CreateTakeAudioAccessor(p.take);if not aa then error('Cannot read '..p.name,0) end
    job.resources[aa]=r.DestroyAudioAccessor
    readers[i]={aa=aa,part=p,first=math.floor((p.pos-s.pos)*cfg.sample_rate+.5),
      accessor_start=r.GetAudioAccessorStartTime(aa),accessor_end=r.GetAudioAccessorEndTime(aa)}
  end
  local primary=readers[1];local aa=primary.aa
  local analyzer=job:call(DSP.analyzer,cfg,r)
  local sr,hop,n=cfg.sample_rate,cfg.hop,cfg.fft_size
  local accessor_start=primary.accessor_start
  local accessor_end=primary.accessor_end
  -- Some accessor/source combinations expose take-rate time. Detect that domain from
  -- the advertised extent instead of multiplying both the audio and its timestamps.
  for _,reader in ipairs(readers) do
    local p=reader.part;reader.scale=1
    if math.abs(reader.accessor_start)>1e-4 then error('Unexpected take accessor time origin: '..p.name,0) end
    if math.abs(p.rate-1)>1e-6 and math.abs(reader.accessor_end-p.len*p.rate)<1e-4
      and math.abs(reader.accessor_end-p.len)>1e-4 then reader.scale=p.rate end
  end
  local time_scale=primary.scale
  local read_rate=math.floor(sr/time_scale+.5)
  if read_rate<1000 or read_rate>192000 then error('Unsupported accessor/play-rate combination.',0) end
  local effective_rate=read_rate*time_scale
  if math.abs(effective_rate-sr)>1e-8 then
    sr=effective_rate;local adjusted={};for k,v in pairs(cfg) do adjusted[k]=v end
    adjusted.sample_rate=sr;analyzer=job:call(DSP.analyzer,adjusted,r)
  end
  for _,reader in ipairs(readers) do
    reader.read_rate=math.floor(sr/reader.scale+.5);reader.count=math.ceil(reader.part.len*sr)
    if #readers>1 and math.abs(reader.read_rate*reader.scale-sr)>1e-8 then
      error('Grouped items need play rates that share one analysis grid: '..reader.part.name,0)
    end
  end
  local total=math.ceil(s.len*sr);local num=math.max(1,math.ceil(total/hop))
  local data={frames={},hop=hop/sr,len=s.len,pos=s.pos,snapshot=s,
    accessor_scale=time_scale,analysis_rate=sr}
  local fast=cfg.cleanup_only and cfg.fft_size==1024 and math.ceil(sr/1000)==32 and s.channels<=8
    and engine and engine.cleanup_dsp and engine.cleanup_dsp.fn and engine.cleanup_dsp or nil
  local stats={backend=fast and fast.label or 'Lua + native FFT',feature_ms=0,read_ms=0,validation_ms=0,kernel_ms=0}
  data.analysis_stats=stats
  local reads={calls=0,nil_status=0,no_audio=0,nonzero_blocks=0,peak=0,
    sample_rate=read_rate,channels=s.channels,start_time=accessor_start,end_time=accessor_end}
  s.read_diagnostics=reads;data.reads=reads
  -- Read more audio per accessor call (especially useful for stretched takes),
  -- but keep each EEL execution short enough to yield between feature blocks.
  local feature_batch=math.min(48,math.max(2,96//s.channels))
  local batch=fast and feature_batch*4 or 48
  local size=(batch-1)*hop+n;local buffer=job:call(r.new_array,size*s.channels)
  local scratch=#readers>1 and job:call(r.new_array,size*s.channels) or nil
  local function read_block(read_start,count)
    buffer.clear()
    if #readers==1 then
      local status=r.GetAudioAccessorSamples(aa,read_rate,s.channels,read_start/sr*time_scale,count,buffer)
      if status==0 then buffer.clear() end
      return status,fast and buffer or buffer.table(1,count*s.channels)
    end
    -- Sample-exact placement of every item inside the block; unread samples
    -- stay zero. Where consecutive items overlap their samples are summed.
    local status;local filled=read_start
    for _,reader in ipairs(readers) do
      local a=math.max(read_start,reader.first);local b=math.min(read_start+count,reader.first+reader.count)
      if b>a then
        scratch.clear()
        local st=r.GetAudioAccessorSamples(reader.aa,reader.read_rate,s.channels,(a-reader.first)/sr*reader.scale,b-a,scratch)
        if type(st)=='number' and st<0 then return st end
        if st~=0 then
          local shared=math.min(b,filled)
          if shared>a then
            local base=(a-read_start)*s.channels
            for k=1,(shared-a)*s.channels do buffer[base+k]=buffer[base+k]+scratch[k] end
          end
          local from=math.max(a,shared)
          if b>from then buffer.copy(scratch,(from-a)*s.channels+1,(b-from)*s.channels,(from-read_start)*s.channels+1) end
        end
        if type(st)=='number' then status=math.max(status or 0,st) end
        filled=math.max(filled,b)
      end
    end
    return status,fast and buffer or buffer.table(1,count*s.channels)
  end
  local state_count=r.GetProjectStateChangeCount(s.project)
  for first=0,num-1,batch do
    for _,reader in ipairs(readers) do
      if not r.ValidatePtr2(s.project,reader.part.take,'MediaItem_Take*') then error('Captured take was deleted.',0) end
      job:call(M.validate_accessor,r,reader.part,reader.aa)
    end
    local now=r.GetProjectStateChangeCount(s.project)
    if now~=state_count then local yes,msg=M.unchanged(r,s);if not yes then error(msg,0) end;state_count=now end
    local count=math.min(batch,num-first)
    local start=first*hop-n//2;local read_start=math.max(0,start)
    local read_end=math.min(total,start+(count-1)*hop+n)
    local read_count=math.max(0,read_end-read_start)
    -- The accessor already includes D_STARTOFFS; do not add it a second time here.
    local read_time=read_start/sr*time_scale
    reads.calls=reads.calls+1;reads.last_time=read_time;reads.last_count=read_count
    local result,samples=job:call(function()
      local at=r.time_precise();local result,values=read_block(read_start,read_count)
      stats.read_ms=stats.read_ms+(r.time_precise()-at)*1000;return result,values
    end)
    reads.last_status=tostring(result)
    -- Some Lua hosts fill the array without returning the documented numeric status.
    -- nil is not a success code: inspect the actual, freshly cleared buffer below.
    if type(result)=='number' then
      if result<0 then error(string.format('Audio read failed for %s at %.3f s (status %s).',s.name,read_time,result),0) end
      if result==0 then reads.no_audio=reads.no_audio+1 end
    elseif result==nil then reads.nil_status=reads.nil_status+1
    else error('Unexpected audio read status: '..tostring(result)..' ('..s.name..')',0) end
    local peak=0;local block
    if fast then
      block={}
      for part=0,count-1,feature_batch do
        local ok,values,input_peak=job:call(function()
          local at=r.time_precise();local kernel=fast.kernel_ms or 0
          local ok,values,input_peak=pcall(fast.execute,fast,samples,start-read_start+part*hop,s.channels,read_count,math.min(feature_batch,count-part),hop,sr,true,part>0)
          stats.feature_ms=stats.feature_ms+(r.time_precise()-at)*1000
          stats.kernel_ms=stats.kernel_ms+(fast.kernel_ms or 0)-kernel;return ok,values,input_peak
        end)
        if ok then
          for _,f in ipairs(values)do block[#block+1]=f end;peak=input_peak
        else
          fast.fn=nil;fast.reason=tostring(values);fast.label='Lua + native FFT';fast=nil;stats.backend='Lua fallback after EEL error'
          samples=job:call(function()return samples.table(1,read_count*s.channels)end);block=nil;break
        end
      end
    end
    if not block then
      local at=r.time_precise()
      for i=1,read_count*s.channels do
        local v=samples[i]
        if type(v)~='number' or v~=v or math.abs(v)>1000000 then error('Invalid PCM sample in '..s.name,0) end
        peak=math.max(peak,math.abs(v))
      end
      stats.validation_ms=stats.validation_ms+(r.time_precise()-at)*1000
    end
    reads.peak=math.max(reads.peak,peak)
    if peak>1e-12 then reads.nonzero_blocks=reads.nonzero_blocks+1 end
    for j=0,count-1 do
      local f=block and block[j+1] or job:call(function()
        local at=r.time_precise();local f=analyzer:frame(samples,start+j*hop-read_start,s.channels,read_count)
        stats.feature_ms=stats.feature_ms+(r.time_precise()-at)*1000;return f
      end)
      f.t=(first+j)*hop/sr;data.frames[#data.frames+1]=f
      if j%4==0 then job:checkpoint((first+j)/num,label) end
    end
  end
  for _,reader in ipairs(readers) do job.resources[reader.aa]=nil;r.DestroyAudioAccessor(reader.aa) end
  local yes,msg=M.unchanged(r,s);if not yes then error(msg,0) end
  if reads.nil_status==reads.calls and reads.nonzero_blocks==0 then
    error('No audio received for '..s.name..': the accessor returned nil and every buffer was zero. Copy report for read diagnostics.',0)
  end
  return DSP.normalize(data,cfg,job)
end
-- Fast read-only display from REAPER's existing peak cache, in project time.
-- DSP uses the accessor separately and never treats these display peaks as samples.
function M.peaks(r,s)
  if not r.GetMediaItemTake_Peaks then return nil end
  if s.composite then
    local n=math.min(8192,math.max(512,math.ceil(s.len*100)));local hop=s.len/n
    local values={};for i=1,n do values[i]={0,0} end;local peak=0
    for _,p in ipairs(s.parts) do
      local part=M.peaks(r,p);local level=part and part.peaks[1]
      for i,v in ipairs(level and level.values or {}) do
        local k=math.floor(((p.pos-s.pos)+(i-.5)*level.hop)/hop)+1
        if k>=1 and k<=n then local e=values[k];e[1]=math.min(e[1],v[1]);e[2]=math.max(e[2],v[2]);peak=math.max(peak,v[2],-v[1]) end
      end
    end
    return {pos=s.pos,len=s.len,hop=hop,peak=peak,peaks={{hop=hop,values=values}},quick=true}
  end
  local n=math.min(8192,math.max(512,math.ceil(s.len*100)))
  local channels=s.channels or r.GetMediaSourceNumChannels(s.source)
  if type(channels)~='number' or channels<1 or channels>8 then return nil end
  local buffer=r.new_array(n*channels*2)
  local ok,status=pcall(r.GetMediaItemTake_Peaks,s.take,n/s.len,s.pos,channels,n,0,buffer)
  if not ok or type(status)~='number' or status<0 or status%1~=0 then return nil end
  local count=math.min(n,status&0xfffff)
  if count==0 then return nil end
  local values={};local peak=0
  for i=1,count do
    local lo,hi=0,0
    for c=1,channels do
      local k=(i-1)*channels+c
      hi=math.max(hi,buffer[k]);lo=math.min(lo,buffer[n*channels+k])
    end
    values[i]={lo,hi};peak=math.max(peak,hi,-lo)
  end
  return {pos=s.pos,len=s.len,hop=s.len/n,peak=peak,peaks={{hop=s.len/n,values=values}},quick=true}
end
-- Пики только на видимое окно [t0,t1] (секунды от начала item) с нужной плотностью: для детализации при зуме.
-- Возвращает уровень {t0,t1,hop,values}; nil для составных (group) захватов или если пики недоступны.
function M.window_peaks(r,s,t0,t1,count)
  if not r.GetMediaItemTake_Peaks or s.composite or t1<=t0 then return nil end
  local channels=s.channels or r.GetMediaSourceNumChannels(s.source)
  if type(channels)~='number' or channels<1 or channels>8 then return nil end
  count=math.max(16,math.min(16384,math.floor(count)))
  local buffer=r.new_array(count*channels*2)
  local ok,status=pcall(r.GetMediaItemTake_Peaks,s.take,count/(t1-t0),s.pos+t0,channels,count,0,buffer)
  if not ok or type(status)~='number' or status<0 or status%1~=0 then return nil end
  local got=math.min(count,status&0xfffff)
  if got==0 then return nil end
  local values={}
  for i=1,got do
    local lo,hi=0,0
    for c=1,channels do
      local k=(i-1)*channels+c
      hi=math.max(hi,buffer[k]);lo=math.min(lo,buffer[count*channels+k])
    end
    values[i]={lo,hi}
  end
  local hop=(t1-t0)/count
  return {t0=t0,t1=t0+got*hop,hop=hop,values=values}
end
return M
