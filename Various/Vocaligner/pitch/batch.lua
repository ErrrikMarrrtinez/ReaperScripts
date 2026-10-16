-- @noindex
local import=...;local Analysis=import('pitch/analysis');local Store=import('pitch/store');local Notes=import('pitch/notes')
local FX=import('pitch/fx');local Job=import('job');local M={}
local function inherited_notes(previous,s,data)
  -- Geometry is independent of the analysis processing fingerprint. A changed
  -- gain, stretch setting or take pitch may be deliberately reanalysed.
  local old=Notes.copy(previous.geometry)
  if old.source_key~=s.source_key or math.abs(old.rate-s.rate)>1e-9 then
    return nil,'Source or play rate changed. Use Reanalyze and reset corrections.'
  end
  old.render_key=s.render_key
  local mapped,notes=Store.adapt({frames={},hop=data.hop,len=old.len,model=data.model},previous.notes,old,s)
  if not mapped then return nil,'Item range changed. Use Reanalyze and reset corrections.' end
  for _,n in ipairs(notes) do n.first=math.max(1,math.floor(n.start/data.hop)+1);n.last=math.min(#data.frames,math.ceil(n.finish/data.hop)) end
  return notes
end
function M.start(e,mode,items)
  if e:busy() or e.gesture then return end
  local r=e.r;local project=r.EnumProjects(-1)
  items=items or {};if #items==0 then
    for i=0,r.CountSelectedMediaItems(project)-1 do items[#items+1]=r.GetSelectedMediaItem(project,i) end
  end
  if #items==0 and e.item then items={e.item} end
  if #items==0 then e:fail('Select audio items or a track with audio to analyze.');return end
  if not e.engine then e.engine=import('pitch/neural').new(nil,nil,r) end
  e.error=nil;e.partial=nil;e.batch_result=nil
  e.job=Job.new(r,function(job)
    local result={total=#items,completed=0,failed=0,errors={}}
    for i,item in ipairs(items) do
      local began=r.time_precise();local label=string.format('Pitch %d / %d',i,#items)
      local unit=job:scope((i-1)/#items,i/#items,label)
      local ok,why=pcall(function()
        local s=job:call(Analysis.capture,r,project,item)
        local previous,saved=job:call(Store.read,r,s.take);previous=previous or {version=1,geometry=Store.geometry(s),notes={}}
        e.engine.kernel_ms=0;e.engine.kernel_calls=0
        local data=Analysis.run(r,s,e.engine,unit:scope(0,.85,label),function(partial)if item==e.item then e.partial=partial end end)
        local separating=r.time_precise();local notes=Notes.segment(data,e.hold_ms,unit:scope(.85,.9,label))
        local stats={seconds=s.len,frames=#data.frames,notes=#notes,backend=e.engine.label,channel=data.channel,read_rate=data.read_rate,
          accessor_scale=data.accessor_scale,peak=data.peak,model=data.model,kernel_ms=e.engine.kernel_ms,kernel_calls=e.engine.kernel_calls,
          feature_ms=data.feature_ms,block_frames=data.block_frames,segmentation_elapsed_ms=(r.time_precise()-separating)*1000,segmentation='voiced-regions-v2',
          waveform_hop_ms=1,waveform_bins=#data.waveform.levels[1].lo}
        local state=Notes.copy(previous);local fx,reason=job:call(FX.owned,r,s,state);assert(not reason,reason)
        local retain=mode~='reset' and fx~=nil
        if retain then notes,reason=inherited_notes(previous,s,data);assert(notes,reason) end
        stats.notes=#notes
        state.notes=notes;state.version=1;state.curve_version=retain and (previous.curve_version or 1) or 4
        state.scale={root=e.root,mode=e.scale,snap=e.snap};state.hold_ms=e.hold_ms
        state.analysis=Store.save_analysis(r,s,data,unit:scope(.9,.94,label))
        stats.elapsed_through_cache_ms=(r.time_precise()-began)*1000;state.analysis_stats=stats
        local prepared;if retain then prepared=FX.prepare(notes,s.len,unit:scope(.94,.99,label),state.curve_version,data) end
        job:call(function()
          local current,err=Analysis.check(r,s);assert(current,err)
          local _,text=Store.read(r,s.take);assert(text==saved,'Pitch item changed during analysis')
          local captured,chunk=r.GetItemStateChunk(item,'',false);assert(captured,'Cannot snapshot Pitch reanalysis')
          r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
          local success,failure=xpcall(function()
            if retain then assert(FX.adopt(r,s,state),'Editor FX changed during analysis');FX.apply(r,s,state,prepared)
            else FX.remove(r,s,state) end
            state.geometry=Store.geometry(current);Store.write(r,s.take,state)
          end,debug.traceback)
          if not success and not r.SetItemStateChunk(item,chunk,false) then failure=failure..'\nRollback failed; use REAPER Undo.' end
          r.PreventUIRefresh(-1);r.Undo_EndBlock2(project,'Vocaligner: analyze pitch'..(retain and ' (keep corrections)' or ''),-1);r.UpdateArrange()
          assert(success,failure);r.MarkProjectDirty(project)
        end)
        e:remember(project,state.analysis,{data=data,geometry=Store.geometry(s)})
        if item==e.item then e.last_analysis=Notes.copy(stats);e.last_analysis.elapsed_ms=(r.time_precise()-began)*1000;e.last_analysis_id=state.analysis end
        result.completed=result.completed+1
      end)
      if not ok then
        job:call(job.close,job)
        result.failed=result.failed+1;result.errors[#result.errors+1]=label..': '..tostring(why);e.app:report(result.errors[#result.errors])
      end
      e.partial=nil;job:checkpoint(i/#items,label)
    end
    e.batch_result=result;e.fit_pending=true;e.prepared_cache=nil
    return result
  end,.010)
  e.job.kind='analysis'
end
return M
