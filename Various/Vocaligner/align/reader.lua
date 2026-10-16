-- @noindex
local import=...;local U=import('align/util');local Audio=import('audio');local Features=import('align/advanced/features');local M={}
function M.analyze(r,s,cfg,job,label,baseline_id,guard,acoustic_cache)
  if s.len>cfg.max_seconds or math.ceil(s.len*100)>cfg.max_frames then U.fail('work_budget_exceeded','Audio exceeds Advanced analysis limits','features')end
  local valid,why=Audio.unchanged(r,s)
  if not valid then U.fail('baseline_features_unavailable','Restore captured timing, then Analyze to read this engine\'s baseline features. '..tostring(why),'features')end
  if guard then guard()end
  local sr,n,hop=32000,1024,320
  -- One accessor per item; a grouped role is read into one virtual timeline
  -- (silent gaps, summed crossfade overlaps), exactly like the Classic reader.
  local readers={}
  for i,p in ipairs(Audio.parts(s))do
    local accessor=U.call(job,r.CreateTakeAudioAccessor,p.take)
    if not accessor then U.fail('missing_audio','Could not create the take accessor','read')end
    job.resources[accessor]=r.DestroyAudioAccessor
    local start=U.call(job,r.GetAudioAccessorStartTime,accessor);local finish=U.call(job,r.GetAudioAccessorEndTime,accessor)
    if math.abs(start)>1e-4 then U.fail('unsupported_source_mapping','Unexpected take accessor origin','read')end
    local part_scale=1
    if math.abs(p.rate-1)>1e-6 and math.abs(finish-p.len*p.rate)<1e-4 and math.abs(finish-p.len)>1e-4 then part_scale=p.rate end
    local part_rate=math.floor(sr/part_scale+.5)
    if part_rate<1000 or part_rate>192000 or math.abs(part_rate*part_scale-sr)>.00001 then
      U.fail('unsupported_source_mapping','This play rate does not provide the fixed 32 kHz Advanced analysis grid','read')
    end
    readers[i]={aa=accessor,part=p,scale=part_scale,read_rate=part_rate,first=math.floor((p.pos-s.pos)*sr+.5),count=math.ceil(p.len*sr)}
  end
  local aa,scale,read_rate=readers[1].aa,readers[1].scale,readers[1].read_rate
  local reuse=cfg.advanced_pitch and acoustic_cache and acoustic_cache.pos==s.pos and acoustic_cache.len==s.len and Features.validate(acoustic_cache,cfg)
  local analyzer=not reuse and U.call(job,Features.analyzer,cfg,r)
  local pitch=cfg.advanced_pitch and U.call(job,import('align/advanced/pitch').new,r)
  local window=pitch and 2048 or n
  local batch=16;local total=math.ceil(s.len*sr);local num=math.max(1,math.ceil(total/hop))
  local buffer=U.call(job,r.new_array,((batch-1)*hop+window)*s.channels)
  local scratch=#readers>1 and U.call(job,r.new_array,((batch-1)*hop+window)*s.channels)or nil
  local raw={frames={},pitches=pitch and {} or nil,pos=s.pos,len=s.len,hop=.01,snapshot=s,accessor_scale=scale,baseline_id=baseline_id}
  local stats={backend=reuse and 'Cached acoustics + native FFT pitch'or analyzer.backend,acoustic_cache_hit=reuse==true,read_ms=0,feature_ms=0,pitch_ms=0,read_calls=0,nil_status=0,nonzero_blocks=0,
    native_buffer_bytes=((batch-1)*hop+window)*s.channels*8,content_fingerprint='host identity + file size; mtime unavailable'}
  raw.analysis_stats=stats
  local function timed(key,fn,...)
    local args=table.pack(...)
    return U.call(job,function()local t=r.time_precise();local out=table.pack(fn(table.unpack(args,1,args.n)));stats[key]=stats[key]+(r.time_precise()-t)*1000;return table.unpack(out,1,out.n)end)
  end
  local state_count=r.GetProjectStateChangeCount(s.project)
  for first=0,num-1,batch do
    for _,reader in ipairs(readers)do if not r.ValidatePtr2(s.project,reader.part.take,'MediaItem_Take*') then U.fail('source_changed','Captured take was deleted','read')end end
    local now=r.GetProjectStateChangeCount(s.project)
    if now~=state_count then
      local ok,msg=Audio.unchanged(r,s);if not ok then U.fail('source_changed',msg,'read')end
      if guard then guard()end;state_count=now
    end
    for _,reader in ipairs(readers)do if r.AudioAccessorStateChanged(reader.aa)then U.fail('source_changed','Audio changed during Advanced analysis','read')end end
    local count=math.min(batch,num-first)
    local read_start=math.max(0,first*hop-window//2)
    local read_end=math.min(total,(first+count-1)*hop+window//2)
    local read_count=math.max(0,read_end-read_start)
    local status,samples=timed('read_ms',function()
      buffer.clear()
      if #readers==1 then
        local result=r.GetAudioAccessorSamples(aa,read_rate,s.channels,read_start/sr*scale,read_count,buffer)
        return result,buffer.table(1,read_count*s.channels)
      end
      local any_one,any_nil,filled=false,false,read_start
      for _,reader in ipairs(readers)do
        local a=math.max(read_start,reader.first);local b=math.min(read_start+read_count,reader.first+reader.count)
        if b>a then
          scratch.clear()
          local st=r.GetAudioAccessorSamples(reader.aa,reader.read_rate,s.channels,(a-reader.first)/sr*reader.scale,b-a,scratch)
          if st~=nil and st~=1 then return st,{} end
          if st==1 then any_one=true else any_nil=true end
          local shared=math.min(b,filled)
          if shared>a then local base=(a-read_start)*s.channels;for k=1,(shared-a)*s.channels do buffer[base+k]=buffer[base+k]+scratch[k]end end
          local from=math.max(a,shared)
          if b>from then buffer.copy(scratch,(from-a)*s.channels+1,(b-from)*s.channels,(from-read_start)*s.channels+1)end
          filled=math.max(filled,b)
        end
      end
      -- A block entirely inside a gap is legitimate digital silence.
      local result=any_one and 1 or any_nil and nil or 1
      return result,buffer.table(1,read_count*s.channels)
    end)
    stats.read_calls=stats.read_calls+1
    if status==nil then stats.nil_status=stats.nil_status+1
    elseif status~=1 then U.fail('missing_audio','Accessor did not provide audio (status '..tostring(status)..')','read')end
    local peak=0
    for _,v in ipairs(samples)do if not U.finite(v)then U.fail('missing_audio','Nonfinite audio sample','read')end;peak=math.max(peak,math.abs(v))end
    if peak>1e-12 then stats.nonzero_blocks=stats.nonzero_blocks+1 end
    for k=0,count-1 do
      local center=(first+k)*hop
      local f
      if reuse then f=acoustic_cache.frames[first+k+1];assert(f and math.abs(f.t-center/sr)<1e-9,'Pitch cache grid mismatch')
      else f=timed('feature_ms',analyzer.frame,analyzer,samples,center-read_start-n//2,s.channels,read_count);f.t=center/sr end
      raw.frames[#raw.frames+1]=f
      if pitch and (first+k)%4==0 then
        local p=timed('pitch_ms',pitch.frame,pitch,samples,center-read_start-1024,s.channels,read_count)
        p.t=f.t;raw.pitches[#raw.pitches+1]=p
      end
      U.checkpoint(job,(first+k)/num*.85,(label or 'Reading Advanced features')..(pitch and ' + pitch evidence'or ''))
    end
  end
  for _,reader in ipairs(readers)do job.resources[reader.aa]=nil;U.call(job,r.DestroyAudioAccessor,reader.aa)end
  if stats.nil_status==stats.read_calls and stats.nonzero_blocks==0 then U.fail('missing_audio','The accessor returned no status and only empty buffers','read')end
  local ok,msg=Audio.unchanged(r,s);if not ok then U.fail('source_changed',msg,'read')end;if guard then guard()end
  local t=r.time_precise();local data=Features.normalize(raw,cfg,job:scope(.85,1,'Normalizing Advanced evidence'))
  stats.normalization_ms=(r.time_precise()-t)*1000
  stats.pitch_enabled=cfg.advanced_pitch==true;stats.pitch_samples=raw.pitches and #raw.pitches or 0
  stats.pitch_frames=0;stats.reliable_pitch_frames=0
  for _,f in ipairs(data.frames)do
    if f.pitch then stats.pitch_frames=stats.pitch_frames+1 end
    if f.pitch and f.pitch_reliability>=cfg.min_pair then stats.reliable_pitch_frames=stats.reliable_pitch_frames+1 end
  end
  return data
end
return M
