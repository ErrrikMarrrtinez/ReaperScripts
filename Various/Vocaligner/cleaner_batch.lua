-- @noindex
local import=...;local Job=import('job');local Config=import('config');local Audio=import('audio');local Apply=import('apply')
local M={}
function M.start(c,explicit,remove)
  if c.job or c.app.job then return end
  local targets={};for _,d in ipairs(c.targets or {})do targets[#targets+1]=d end
  if #targets<2 then return end
  local revision=c.revision;local mode=c.mode;local configs={};local total=0
  for i,d in ipairs(targets)do configs[i]=Config.copy(d.cfg);total=total+math.max(.01,d.snapshot.len) end
  local transaction=c.edit_transaction
  c.pending=nil;c.error=nil
  c.job=Job.new(c.r,function(job)
    local results={};local elapsed=0
    for i,d in ipairs(targets)do
      local a,b=elapsed/total,(elapsed+math.max(.01,d.snapshot.len))/total;elapsed=b*total
      local part=job:scope(a*.94,b*.94)
      local ok,why=true,nil
      if not d.restore_value then ok,why=job:call(Audio.check_dub,c.r,d) end
      if not ok then d.stale=true;d.want_apply=false;error(why,0) end
      if not d.audio or d.audio.dynamics_only and not import('compressor/settings').dynamic(mode) then c:read_audio(d,part:scope(0,.72)) else d.analysis_reuses=(d.analysis_reuses or 0)+1 end
      part:checkpoint(.72,'Processing '..i..' / '..#targets)
      -- Loaded session settings precede the explicit current group controls.
      local cfg=configs[i]
      local range={d.range[1],d.range[2]}
      if d~=c:current() then
        local x,y=c.r.GetSet_LoopTimeRange2(c.project,false,false,0,0,false)
        if y>x and y>d.snapshot.pos and x<d.snapshot.pos+d.snapshot.len then
          range={math.max(0,x-d.snapshot.pos),math.min(d.snapshot.len,y-d.snapshot.pos)}
        else range={0,d.snapshot.len} end
      end
      local out;local started=c.r.time_precise()
      if remove then
        out=c:build_preview(d,cfg,mode,range,part,true)
      else out=c:build_preview(d,cfg,mode,range,part:scope(.72,1)) end
      d.compute_ms=(c.r.time_precise()-started)*1000;results[i]=out;part:checkpoint(1,'Processed '..i..' / '..#targets)
    end
    if revision~=c.revision then return end -- controls moved during the read; keep its cache, discard the stale preview
    job:checkpoint(.95,'Applying '..#targets..' items')
    job:call(function()
      if revision~=c.revision then return end
      for _,d in ipairs(targets)do
        local ok,why,geometry,gain_changed=Audio.check_dub(c.r,d);assert(ok,why)
        if geometry or gain_changed and d.layers and (d.layers.compressor or d.layers.gate) then
          c:request(true);return -- rebuild changed input before any native write
        end
      end
      c.job.writing=true
      local changed={};local before={};local detail=0
      for i,d in ipairs(targets)do
        local out=results[i];c:accept_preview(d,out,revision)
        if out.changed then
          before[d]={cleanup=d.cleanup,cfg=d.cleanup_cfg}
          d.cleanup=out.combined;d.next_layers=out.layers;d.cleanup_cfg=out.cfg
          for kind,layer in pairs(out.layers)do detail=math.max(detail,layer.detail or out.cfg[kind..'_detail'] or 70)end
          changed[#changed+1]=d
        end
      end
      if #changed>0 then
        local cfg=Config.copy(configs[1]);cfg.envelope_detail=detail
        local started=c.r.time_precise()
        local n,why=Apply.run(c.r,c.project,nil,changed,cfg,transaction)
        c.job.apply_ms=(c.r.time_precise()-started)*1000
        for _,d in ipairs(changed)do d.next_layers=nil end
        if not n then
          for _,d in ipairs(changed)do d.cleanup=before[d].cleanup;d.cleanup_cfg=before[d].cfg end
          error(why,0)
        end
      end
      for _,d in ipairs(targets)do
        d.want_apply=false;d.preview_changed=false;d.preview_valid=revision==c.revision
        d.processed_modes=d.processed_modes or {};d.processed_modes[mode]=not remove;d.save_pending=true
      end
      c.project_state=c.r.GetProjectStateChangeCount(c.project)
    end)
    -- Persistence is a separate, cancellable idle job; a new slider value must
    -- not wait for old metadata to finish saving before it reaches the audio.
    if explicit then c.app:report(string.format('%s: processed %d selected items.',mode,#targets))end
  end,.004)
  c.job.kind='batch';c.job.dub=c:current();c.job.mode=mode;c.job.live=not explicit;c.job.revision=revision;c.job.item_count=#targets
  for _,d in ipairs(targets)do if not d.audio then c.job.live=false end end
end
return M
