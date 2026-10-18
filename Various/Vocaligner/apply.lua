-- @noindex
local import=...;local Audio=import('audio');local Envelope=import('envelope');local Warp=import('warp');local M={}
local function bridge_for(d,before)
  if not d.align_app or d.plan and d.plan.volume_only then return end
  local bridge=import('align/cleanup_bridge')
  if d.align_volume_state or bridge.find(d.align_app,d,before)then return bridge end
end
local settings={'D_POSITION','D_LENGTH'}
local take_settings={'D_PLAYRATE','B_PPITCH','D_PITCH','I_PITCHMODE','I_STRETCHFLAGS','F_STRETCHFADESIZE'}
local function pitch_mode(r)
  -- Resolve the user's elastique Pro setting by name; slot numbers vary by REAPER build.
  for i=0,64 do
    local yes,name=r.EnumPitchShiftModes(i)
    if not yes then break end
    if name and name:lower():find('lastique') and name:find('3') and name:lower():find('pro') then return i<<16 end
  end
  return -1
end
local function restore(r,b)
  local s=b.state
  if s.composite then for _,p in ipairs(s.parts) do restore(r,{state=p,volume_only=b.volume_only}) end;return end
  local take=r.GetActiveTake(s.item);local _,guid=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
  assert(guid==s.guid,'The active take changed before restore.')
  if b.volume_only then
    Envelope.restore(r,s,s.volume_envelope);r.UpdateItemInProject(s.item);return
  end
  for _,k in ipairs(settings) do assert(r.SetMediaItemInfo_Value(s.item,k,s[k])) end
  for _,k in ipairs(take_settings) do assert(r.SetMediaItemTakeInfo_Value(take,k,s[k])) end
  local count=r.GetTakeNumStretchMarkers(take)
  assert(r.DeleteTakeStretchMarkers(take,0,count)==count,'Could not remove stretch markers.')
  for _,m in ipairs(s.markers) do
    local ix=r.SetTakeStretchMarker(take,-1,m.pos,m.src)
    if ix<0 then error('Failed to restore a stretch marker: '..s.name,0) end
    assert(r.SetTakeStretchMarkerSlope(take,ix,m.slope),'Could not restore stretch slope.')
    local _,pos,src=r.GetTakeStretchMarker(take,ix)
    if math.abs(pos-m.pos)>1e-6 or math.abs(src-m.src)>1e-6 then error('REAPER constrained a restored marker.',0) end
  end
  Envelope.restore(r,s,s.volume_envelope)
  r.UpdateItemInProject(s.item)
end
-- Write one item's timing map: item bounds, take stretch settings, linear
-- markers and the transported volume envelope. Returns the envelope point count.
local function write_item(r,s,plan,prepared,mode,cfg)
  local take=r.GetActiveTake(s.item)
  local count=r.GetTakeNumStretchMarkers(take)
  assert(r.DeleteTakeStretchMarkers(take,0,count)==count,'Could not remove stretch markers.')
  assert(r.SetMediaItemInfo_Value(s.item,'D_POSITION',plan.pos))
  assert(r.SetMediaItemInfo_Value(s.item,'D_LENGTH',plan.len))
  -- Do not change an existing resampled take's pitch-preserve choice.
  assert(r.SetMediaItemTakeInfo_Value(take,'B_PPITCH',math.abs(s.rate-1)<1e-9 and 1 or s.B_PPITCH))
  assert(r.SetMediaItemTakeInfo_Value(take,'I_PITCHMODE',mode))
  assert(r.SetMediaItemTakeInfo_Value(take,'I_STRETCHFLAGS',(s.I_STRETCHFLAGS&(~7))|2))
  assert(r.SetMediaItemTakeInfo_Value(take,'F_STRETCHFADESIZE',cfg.fade_ms/1000))
  for _,m in ipairs(plan.markers) do
    local pos=(m.target-plan.pos)*s.rate
    local ix=r.SetTakeStretchMarker(take,-1,pos,m.source)
    if ix<0 then error('REAPER refused a marker in '..s.name,0) end
    assert(r.SetTakeStretchMarkerSlope(take,ix,0),'Could not set linear stretch slope.')
    local _,actual,source=r.GetTakeStretchMarker(take,ix)
    if math.abs(actual-pos)>1e-6 or math.abs(source-m.source)>1e-6 then error('REAPER constrained a marker unexpectedly in '..s.name,0) end
  end
  local points=Envelope.write(r,s,prepared)
  r.UpdateItemInProject(s.item)
  return points
end
function M.finish(r,transaction)
  if transaction and transaction.open then
    transaction.open=false
    r.Undo_EndBlock2(transaction.project,transaction.label or 'Vocaligner: adjust parameters',-1)
  end
  if transaction then transaction.outputs=nil end
end
function M.run(r,project,reference,dubs,cfg,transaction)
  if reference and ((cfg.hybrid or 0)~=0 or import('align/hybrid/render').active(dubs))then
    M.finish(r,transaction)
    return import('align/hybrid/render').run(r,project,reference,dubs,cfg,false)
  end
  if r.EnumProjects(-1)~=project then return nil,'Switch back to the captured project before applying.' end
  if r.GetPlayStateEx(project)&4~=0 then return nil,'Stop recording before applying alignment.' end
  local yes,msg=true,nil
  if reference then yes,msg=Audio.unchanged(r,reference);if not yes then return nil,msg end end
  local batch={}
  for _,d in ipairs(dubs) do
    if d.enabled and d.plan then
      yes,msg=Audio.check_dub(r,d);if not yes then return nil,msg end
    end
    if d.enabled and d.plan and (not d.plan.unchanged or d.applied or (d.cleanup and (d.cleanup.max_db>.01 or d.cleanup.force_envelope))) then
      for _,p in ipairs(Audio.parts(d.snapshot)) do
        if r.GetMediaItemInfo_Value(p.item,'C_LOCK')~=0 then return nil,'An item is locked: '..p.name end
      end
      local before=Audio.current(r,d.snapshot)
      batch[#batch+1]={dub=d,state=before,volume_only=d.plan.volume_only}
    end
  end
  -- Cleanup (без reference): если ни одному тейку нечего писать — это не ошибка, а «уже совпадает».
  -- Так бывает при нескольких выделенных айтемах, когда часть из них без найденных событий.
  if #batch==0 then
    if not reference then return 0 end
    return nil,'Nothing to apply. The enabled takes already match or have no usable result.'
  end
  local mode=reference and pitch_mode(r) or -1
  if transaction then
    if transaction.open and transaction.project~=project then return nil,'The edit belongs to another project.' end
    if not transaction.open then
      r.Undo_BeginBlock2(project);transaction.open=true;transaction.project=project
      transaction.label=reference and 'Vocaligner: adjust alignment' or 'Vocaligner: adjust cleanup'
    end
  else r.Undo_BeginBlock2(project) end
  r.PreventUIRefresh(1)
  local ok,err=xpcall(function()
    for _,entry in ipairs(batch) do
      local d=entry.dub;local plan=d.plan;local s=plan.snapshot
      local original=d.original_state or s
      if s.composite then
        -- Each part retains its own verified Cleaner baseline and recipes.
        -- Prepare its gain transport before restoring captured timing.
        local parts=Audio.parts(original);local points=0
        for k,piece in ipairs(Warp.slice(plan)) do
          local op=parts[k];local part={snapshot=s.parts[k],align_app=d.align_app,
            align_volume_state=d.align_volume_state and Audio.parts(d.align_volume_state)[k]}
          local child={dub=part,state=Audio.parts(entry.state)[k]};local bridge=bridge_for(part,child.state);local prepared
          if bridge then
            child.before=child.state;child.bridge=bridge
            prepared=bridge.prepare(d.align_app,child,piece,function(host,state)restore(host,{state=state})end)
            entry.children=entry.children or {};entry.children[#entry.children+1]=child
          else
            restore(r,{state=op});prepared=Envelope.prepare(r,op,piece,nil,nil)
          end
          restore(r,{state=op})
          if plan.unchanged then points=points+Envelope.write(r,piece.snapshot,prepared)
          else points=points+write_item(r,piece.snapshot,piece,prepared,mode,cfg) end
        end
        d.envelope_points=points
        goto next_dub
      end
      local bridge=bridge_for(d,entry.state);local prepared
      if bridge then
        entry.before=entry.state;entry.bridge=bridge
        prepared=bridge.prepare(d.align_app,entry,plan,function(host,state)restore(host,{state=state})end)
        restore(r,{state=original})
      else
        if original.volume_envelope then Envelope.restore(r,s,original.volume_envelope) end
        prepared=Envelope.prepare(r,original,plan,d.cleanup,plan.volume_only and (d.cleanup_cfg or cfg) or nil)
      end
      if plan.volume_only then
        d.envelope_points=Envelope.write(r,s,prepared)
        r.UpdateItemInProject(s.item)
        goto next_dub
      end
      if plan.unchanged then
        restore(r,{state=original})
        d.envelope_points=Envelope.write(r,s,prepared)
        goto next_dub
      end
      d.envelope_points=write_item(r,s,plan,prepared,mode,cfg)
      ::next_dub::
    end
  end,debug.traceback)
  local rollback_errors={}
  if not ok then
    for i=#batch,1,-1 do local restored,why=pcall(restore,r,batch[i]);if not restored then rollback_errors[#rollback_errors+1]=tostring(why) end end
  end
  r.PreventUIRefresh(-1)
  if not transaction then
    r.Undo_EndBlock2(project,ok and (reference and 'Vocaligner: align vocal takes' or 'Vocaligner: take volume cleanup') or 'Vocaligner: rolled back failed edit',-1)
  elseif not ok then M.finish(r,transaction) end
  r.UpdateArrange()
  if not ok then
    if #rollback_errors>0 then err=err..'\nRollback needs REAPER Undo:\n'..table.concat(rollback_errors,'\n') end
    return nil,err
  end
  for _,entry in ipairs(batch) do
    local d=entry.dub;local after=Audio.current(r,d.snapshot);local signature=after.signature
    -- Intermediate slider states share one native Undo entry. Keep its starting
    -- signatures and newest result, rather than retaining every frame's curves.
    d.outputs=d.outputs or {}
    if transaction then
      transaction.outputs=transaction.outputs or {}
      local history=transaction.outputs[d]
      if not history then
        history={known={}};for key in pairs(d.outputs)do history.known[key]=true end
        transaction.outputs[d]=history
      end
      if history.last and history.last~=signature and not history.known[history.last] then d.outputs[history.last]=nil end
      history.last=signature
    end
    d.output_sequence=(d.output_sequence or 0)+1
    -- Cleanup outputs remember their baseline (it can be a kept manual edit)
    -- and the bypassed stages, so Undo/Redo restores both.
    local base=d.plan.volume_only and (d.original_state or entry.state) or nil
    d.bypassed=d.next_bypassed or d.bypassed;d.next_bypassed=nil
    local bypassed={};for mode,layer in pairs(d.bypassed or {})do bypassed[mode]=layer end
    d.outputs[signature]={plan=d.plan,cleanup=d.cleanup,envelope_points=d.envelope_points,
      layers=d.next_layers or d.layers,cfg=d.cleanup_cfg,volume_envelope=after.volume_envelope,volume_points=after.volume_points,sequence=d.output_sequence,
      native_state=d.align_app and after or nil,volume_origin=d.align_volume_state,
      baseline=base and {volume_envelope=base.volume_envelope,volume_points=base.volume_points} or nil,
      bypassed=d.plan.volume_only and bypassed or nil}
    if d.align_app then d.outputs[signature].timing_applied=not d.plan.unchanged end
    -- Different recipes/order can produce the same native curve. Invalidate the
    -- ownership shortcut too, otherwise the next check resurrects old layers.
    d.verified_signature=signature;d.verified_output=d.outputs[signature]
    d.layers=d.next_layers or d.layers;d.next_layers=nil
    d.applied_plan=d.plan;d.applied_cleanup=d.cleanup
    d.applied_cfg=d.cleanup_cfg
    d.original_state=d.original_state or (entry.bridge and d.snapshot or entry.state);d.applied=true
    if d.plan.unchanged and not (d.cleanup and (d.cleanup.max_db>.01 or d.cleanup.force_envelope)) then d.applied=false end
    if entry.bridge then entry.after=after;entry.bridge.publish(entry)end
    for _,child in ipairs(entry.children or {})do child.after=Audio.state(r,project,child.dub.snapshot.item);child.bridge.publish(child)end
  end
  return #batch
end
function M.restore(r,project,dubs)
  if import('align/hybrid/render').active(dubs)then return import('align/hybrid/render').run(r,project,nil,dubs,{},true)end
  if r.EnumProjects(-1)~=project then return nil,'Switch back to the captured project.' end
  if r.GetPlayStateEx(project)&4~=0 then return nil,'Stop recording before restoring takes.' end
  local batch={}
  for _,d in ipairs(dubs) do if d.original_state then
    local ok,msg=Audio.check_dub(r,d);if not ok then return nil,msg end
    if d.applied then batch[#batch+1]={dub=d,state=d.original_state,current=Audio.current(r,d.snapshot),volume_only=d.plan and d.plan.volume_only} end
  end end
  if #batch==0 then return nil,'Nothing applied in this session.' end
  r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
  local ok,err=xpcall(function() for _,b in ipairs(batch) do
    local bridge=bridge_for(b.dub,b.current);local prepared
    if b.state.composite then
      for k,part in ipairs(b.state.parts)do
        local dub={snapshot=b.dub.snapshot.parts[k],align_app=b.dub.align_app,
          align_volume_state=b.dub.align_volume_state and Audio.parts(b.dub.align_volume_state)[k]}
        local child={dub=dub,before=Audio.parts(b.current)[k]};local part_bridge=bridge_for(dub,child.before)
        if part_bridge then
          local target=import('align/advanced/plan').baseline(part,nil,import('align/advanced/defaults').config())
          local gain=part_bridge.prepare(dub.align_app,child,target,function(host,state)restore(host,{state=state})end)
          restore(r,{state=part});Envelope.write(r,part,gain)
          child.after=Audio.state(r,project,part.item);child.bridge=part_bridge
          b.children=b.children or {};b.children[#b.children+1]=child
        else restore(r,{state=part})end
      end
      b.after=Audio.current(r,b.state)
      goto next_restore
    end
    if bridge then
      b.before=b.current;b.bridge=bridge
      local target=import('align/advanced/plan').baseline(b.state,nil,import('align/advanced/defaults').config())
      prepared=bridge.prepare(b.dub.align_app,b,target,function(host,state)restore(host,{state=state})end)
    end
    restore(r,b)
    if bridge then Envelope.write(r,b.state,prepared);b.after=Audio.state(r,project,b.state.item)end
    ::next_restore::
  end end,debug.traceback)
  if not ok then for _,b in ipairs(batch) do
    local restored,why=pcall(restore,r,{state=b.current,volume_only=b.volume_only})
    if not restored then err=err..'\nRollback needs REAPER Undo: '..tostring(why) end
  end end
  r.PreventUIRefresh(-1);r.Undo_EndBlock2(project,'Vocaligner: restore captured takes',-1);r.UpdateArrange()
  if not ok then return nil,err end
  for _,b in ipairs(batch) do
    local d=b.dub;d.applied=false;d.applied_plan=nil;d.applied_cleanup=nil
    if b.bridge then
      d.outputs=d.outputs or {};d.outputs[b.after.signature]={timing_applied=false,native_state=b.after,volume_origin=d.align_volume_state,
        volume_envelope=b.after.volume_envelope,volume_points=b.after.volume_points}
      b.bridge.publish(b)
    end
    if b.children then
      b.dub.outputs=b.dub.outputs or {};b.dub.outputs[b.after.signature]={timing_applied=false,native_state=b.after,
        volume_origin=b.dub.align_volume_state,volume_envelope=b.after.volume_envelope,volume_points=b.after.volume_points}
      for _,child in ipairs(b.children)do child.bridge.publish(child)end
    end
  end
  return #batch
end
return M
