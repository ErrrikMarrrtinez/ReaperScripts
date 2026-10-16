-- @noindex
local import=...;local U=import('align/util');local Audio=import('audio');local Envelope=import('envelope')
local Ownership=import('align/ownership');local Validate=import('align/advanced/validate');local Bridge=import('align/cleanup_bridge');local Warp=import('warp');local M={}
local take_fields={'D_STARTOFFS','D_PLAYRATE','B_PPITCH','D_PITCH','I_PITCHMODE','I_STRETCHFLAGS','F_STRETCHFADESIZE'}
local function mode(r)
  for i=0,64 do local yes,name=r.EnumPitchShiftModes(i);if not yes then break end
    if name and name:lower():find('lastique')and name:find('3')and name:lower():find('pro')then return i<<16 end
  end
  return -1
end
local function write_markers(r,take,markers)
  local n=r.GetTakeNumStretchMarkers(take);assert(r.DeleteTakeStretchMarkers(take,0,n)==n,'Could not remove timing markers')
  for _,m in ipairs(markers)do
    local index=r.SetTakeStretchMarker(take,-1,m.pos,m.src);assert(index>=0,'Native stretch-marker insertion failed')
    assert(r.SetTakeStretchMarkerSlope(take,index,m.slope or 0),'Native marker slope write failed')
  end
end
local function restore_state(r,s)
  if s.composite then for _,p in ipairs(s.parts)do restore_state(r,p)end;return end
  local take=r.GetActiveTake(s.item);local _,guid=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false);assert(guid==s.guid,'Active take changed')
  -- Remove the current map before changing item bounds so host clamps cannot
  -- make intermediate source/target knots constrain the restored baseline.
  local n=r.GetTakeNumStretchMarkers(take);assert(r.DeleteTakeStretchMarkers(take,0,n)==n)
  assert(r.SetMediaItemInfo_Value(s.item,'D_POSITION',s.pos));assert(r.SetMediaItemInfo_Value(s.item,'D_LENGTH',s.len))
  for _,k in ipairs(take_fields)do assert(r.SetMediaItemTakeInfo_Value(take,k,s[k]))end
  write_markers(r,take,s.markers);Envelope.restore(r,s,s.volume_envelope)
end
local function same_number(a,b,tolerance) return U.finite(a)and U.finite(b)and math.abs(a-b)<=tolerance end
local function verify_envelope(r,s,prepared)
  local take=r.GetActiveTake(s.item);local actual=Envelope.read(r,take)
  if type(prepared)~='table'then
    assert(Envelope.equivalent(prepared,actual,s.len*s.rate),'Volume envelope readback mismatch')
    return
  end
  local env=assert(r.GetTakeEnvelopeByName(take,'Volume'),'Written Volume envelope disappeared')
  assert(r.CountEnvelopePoints(env)==#prepared.points,'Volume envelope point count mismatch')
  for i,p in ipairs(prepared.points)do
    local yes,t,v,shape,tension=r.GetEnvelopePoint(env,i-1)
    assert(yes and same_number(t,p.time,1e-6)and same_number(v,p.value,1e-7+math.abs(p.value)*1e-7)
      and shape==(p.shape or 0)and same_number(tension,p.tension or 0,1e-7),'Volume point readback mismatch')
  end
end
local function verify_map(r,plan,expected,cfg)
  local s=plan.snapshot;local now=Audio.state(r,s.project,s.item);local tol=cfg.native_tolerance
  assert(now.guid==s.guid and now.source==s.source,'Native write changed the take/source')
  assert(same_number(now.pos,plan.pos,tol)and same_number(now.len,plan.len,tol),'Native item bounds mismatch')
  for _,k in ipairs(take_fields)do assert(same_number(now[k],expected[k],tol),'Native take setting mismatch: '..k)end
  assert(#now.markers==#expected.markers,'Native marker count mismatch')
  for i,m in ipairs(expected.markers)do local a=now.markers[i]
    assert(same_number(a.pos,m.pos,tol)and same_number(a.src,m.src,tol)and same_number(a.slope,m.slope or 0,1e-9),'Native marker readback mismatch')
  end
  return now
end
local function check_items(app,entries,restore,cfg)
  local r=app.r
  if r.EnumProjects(-1)~=app.project then return nil,U.error('source_changed','Switch back to the captured project','preflight')end
  if r.GetPlayStateEx(app.project)&4~=0 then return nil,U.error('source_changed','Stop recording before changing timing','preflight')end
  if app.ref then
    local ok,why=Audio.unchanged(r,app.ref);if not ok then return nil,U.error('source_changed',why,'preflight')end
    if app.alignment and app.alignment.guide_owner then ok,why=Ownership.check(r,app.ref,app.alignment.guide_owner,false);if not ok then return nil,why end end
  end
  for _,entry in ipairs(entries)do
    local d=entry.dub;local ok,why=Audio.check_dub(r,d);if not ok then return nil,U.error('source_changed',why,'preflight')end
    local now=Audio.current(r,d.snapshot)
    for _,part in ipairs(Audio.parts(now))do if part.C_LOCK~=0 then return nil,U.error('source_changed','The take is locked: '..part.name,'preflight')end end
    ok,why=Ownership.check(r,now,d.align_owner,true);if not ok then return nil,why end
    if not restore and not d.plan.unchanged then
      local valid,reason=Validate.run(d.plan,cfg)
      if not valid then return nil,U.error('render_map_invalid',reason,'preflight')end
      ok,why=Ownership.fades(d.plan,d.align_owner);if not ok then return nil,why end
    end
  end
  return true
end
function M.run(app,cfg,restore)
  local r=app.r;local entries={};local checked={};local operations=0
  for _,d in ipairs(app.dubs)do
    if restore then if d.original_state and d.applied then entries[#entries+1]={dub=d};checked[#checked+1]={dub=d}end
    elseif d.enabled and d.plan then
      checked[#checked+1]={dub=d}
      -- A validated plan already owning the current map is an exact repeated Apply.
      if (d.applied or not d.plan.unchanged)and not(d.applied_plan==d.plan and d.align_applied_fade==cfg.fade_ms)then entries[#entries+1]={dub=d}end
    end
  end
  local ok,why=check_items(app,checked,restore,cfg);if not ok then return nil,why end
  if #entries==0 then return 0 end
  local lease;lease,why=Ownership.acquire(app);if not lease then return nil,why end
  local undo,refresh=false,false;local rollback_errors={};local touched={}
  local success,err=xpcall(function()
    local bytes=0
    for _,entry in ipairs(entries)do
      entry.before=Audio.current(r,entry.dub.snapshot);entry.chunks={}
      for k,part in ipairs(Audio.parts(entry.before))do
        local yes,chunk=r.GetItemStateChunk(part.item,'',false);assert(yes and type(chunk)=='string','Cannot capture rollback snapshot')
        entry.chunks[k]={item=part.item,chunk=chunk};bytes=bytes+#chunk;operations=operations+#part.markers+32
      end
      operations=operations+(restore and #(entry.dub.original_state.markers)or #(entry.dub.plan.markers))*3
      local original=entry.dub.original_state or entry.dub.snapshot
      if original.volume_envelope then operations=operations+math.ceil(original.len/.01)+#(original.volume_points or {})*2 end
    end
    assert(bytes<=32*1024*1024,'Rollback snapshots exceed the transaction memory budget')
    assert(operations<=cfg.max_write_operations,'Native write set exceeds its operation budget')
    local current,reason=check_items(app,entries,restore,cfg);assert(current,tostring(reason))
    r.Undo_BeginBlock2(app.project);undo=true;r.PreventUIRefresh(1);refresh=true
    local renderer_mode=mode(r)
    for _,entry in ipairs(entries)do
      touched[#touched+1]=entry
      local d=entry.dub;local original=d.original_state or d.snapshot;local plan=d.plan
      if original.composite then
        -- Grouped role: every item returns to its captured state, then each
        -- receives its slice of the virtual map, verified by native readback.
        restore_state(r,original)
        if restore or plan.unchanged then
          local restored=Audio.current(r,original)
          assert(restored.signature==original.signature,'Exact captured-state restore mismatch')
          entry.after=restored;entry.envelope_points=0
        else
          entry.native_markers={};entry.envelope_points=0
          for k,piece in ipairs(Warp.slice(plan))do
            local part=original.parts[k];local take=r.GetActiveTake(part.item)
            local prepared=Envelope.prepare(r,part,piece,nil)
            local expected={markers={}}
            for _,key in ipairs(take_fields)do expected[key]=part[key]end
            expected.B_PPITCH=math.abs(part.rate-1)<1e-9 and 1 or part.B_PPITCH
            expected.I_PITCHMODE=renderer_mode;expected.I_STRETCHFLAGS=(part.I_STRETCHFLAGS&(~7))|2
            expected.F_STRETCHFADESIZE=cfg.fade_ms/1000
            local n=r.GetTakeNumStretchMarkers(take);assert(r.DeleteTakeStretchMarkers(take,0,n)==n)
            assert(r.SetMediaItemInfo_Value(part.item,'D_POSITION',piece.pos));assert(r.SetMediaItemInfo_Value(part.item,'D_LENGTH',piece.len))
            for _,key in ipairs(take_fields)do assert(r.SetMediaItemTakeInfo_Value(take,key,expected[key]))end
            for _,m in ipairs(piece.markers)do expected.markers[#expected.markers+1]={pos=(m.target-piece.pos)*part.rate,src=m.source,slope=0}end
            write_markers(r,take,expected.markers)
            entry.envelope_points=entry.envelope_points+Envelope.write(r,part,prepared);verify_envelope(r,part,prepared)
            entry.native_markers[k]=verify_map(r,piece,expected,cfg).markers
            r.UpdateItemInProject(part.item)
          end
          entry.after=Audio.current(r,original)
        end
        local owner,reason=Ownership.check(r,entry.after,d.align_owner,true);assert(owner,tostring(reason))
        goto next_entry
      end
      local bridge=d.align_volume_state or Bridge.find(app,d,entry.before)
      local prepared
      if bridge then
        local target=restore and import('align/advanced/plan').baseline(original,nil,cfg)or plan
        prepared=Bridge.prepare(app,entry,target,restore_state)
      end
      restore_state(r,original)
      if restore or plan.unchanged then
        if bridge then entry.envelope_points=Envelope.write(r,original,prepared);verify_envelope(r,original,prepared)end
        local restored=Audio.state(r,app.project,original.item)
        assert(bridge and Bridge.geometry(restored)==Bridge.geometry(original)or not bridge and restored.signature==original.signature,'Exact captured-state restore mismatch')
        entry.after=restored;entry.envelope_points=restored.volume_points and #restored.volume_points or 0
      else
        -- Native evaluation of the Volume baseline belongs inside rollback, with
        -- both its original geometry and original envelope present.
        if not bridge then prepared=Envelope.prepare(r,original,plan,nil)end
        local take=r.GetActiveTake(original.item)
        local expected={markers={}}
        for _,k in ipairs(take_fields)do expected[k]=original[k]end
        expected.B_PPITCH=math.abs(original.rate-1)<1e-9 and 1 or original.B_PPITCH
        expected.I_PITCHMODE=renderer_mode;expected.I_STRETCHFLAGS=(original.I_STRETCHFLAGS&(~7))|2
        expected.F_STRETCHFADESIZE=cfg.fade_ms/1000
        local n=r.GetTakeNumStretchMarkers(take);assert(r.DeleteTakeStretchMarkers(take,0,n)==n)
        assert(r.SetMediaItemInfo_Value(original.item,'D_POSITION',plan.pos));assert(r.SetMediaItemInfo_Value(original.item,'D_LENGTH',plan.len))
        for _,k in ipairs(take_fields)do assert(r.SetMediaItemTakeInfo_Value(take,k,expected[k]))end
        for _,m in ipairs(plan.markers)do expected.markers[#expected.markers+1]={pos=(m.target-plan.pos)*original.rate,src=m.source,slope=0}end
        write_markers(r,take,expected.markers)
        entry.envelope_points=Envelope.write(r,original,prepared);verify_envelope(r,original,prepared)
        entry.after=verify_map(r,plan,expected,cfg);entry.native_markers=entry.after.markers
      end
      local owner,reason=Ownership.check(r,entry.after,d.align_owner,true);assert(owner,tostring(reason))
      r.UpdateItemInProject(original.item)
      ::next_entry::
    end
    if app.ref then local same,reason=Audio.unchanged(r,app.ref);assert(same,reason)end
  end,function(e)return e end)
  if not success then
    for i=#touched,1,-1 do local entry=touched[i]
      local restored,reason=pcall(function()
        for _,saved in ipairs(entry.chunks)do assert(r.SetItemStateChunk(saved.item,saved.chunk,false),'Host rejected rollback snapshot')end
        local actual=Audio.current(r,entry.before)
        assert(actual.signature==entry.before.signature,'Rollback readback mismatch')
        local owner,why=Ownership.check(r,actual,entry.dub.align_owner,true);assert(owner,tostring(why))
      end)
      if not restored then rollback_errors[#rollback_errors+1]=entry.before.name..': '..tostring(reason)end
    end
  end
  if refresh then local done,e=pcall(r.PreventUIRefresh,-1);if not done then rollback_errors[#rollback_errors+1]=tostring(e)end end
  if undo then local done,e=pcall(r.Undo_EndBlock2,app.project,success and (restore and 'Vocaligner: restore captured timing' or 'Vocaligner: Advanced Align')or 'Vocaligner: rolled back Advanced Align',-1);if not done then rollback_errors[#rollback_errors+1]=tostring(e)end end
  Ownership.release(app,lease);if r.UpdateArrange then r.UpdateArrange()end
  if not success or #rollback_errors>0 then
    return nil,U.error(#rollback_errors>0 and 'rollback_failed' or 'native_write_failed',tostring(err or 'Host guard failed')..(#rollback_errors>0 and '\nRecovery required; use REAPER Undo.\n'..table.concat(rollback_errors,'\n')or ''),'commit')
  end
  -- No partially written output is visible to ownership/history before the
  -- whole batch and its readback have succeeded.
  for _,entry in ipairs(entries)do
    local d=entry.dub;d.envelope_points=entry.envelope_points
    if restore or d.plan.unchanged then
      d.applied=false;d.applied_plan=nil;d.applied_cleanup=nil;d.align_applied_fade=nil
      if entry.after.signature~=d.snapshot.signature then
        d.outputs=d.outputs or {};d.output_sequence=(d.output_sequence or 0)+1
        d.outputs[entry.after.signature]={timing_applied=false,native_state=entry.after,volume_origin=d.align_volume_state,volume_envelope=entry.after.volume_envelope,
          volume_points=entry.after.volume_points,envelope_points=entry.envelope_points,sequence=d.output_sequence}
      end
    else
      d.outputs=d.outputs or {};d.output_sequence=(d.output_sequence or 0)+1
      d.outputs[entry.after.signature]={plan=d.plan,envelope_points=entry.envelope_points,sequence=d.output_sequence,
          volume_envelope=entry.after.volume_envelope,volume_points=entry.after.volume_points,engine_id='advanced_v1',native_state=entry.after,volume_origin=d.align_volume_state}
      d.original_state=d.original_state or d.snapshot;d.applied=true;d.applied_plan=d.plan;d.applied_cleanup=nil;d.align_applied_fade=cfg.fade_ms
      d.plan.native_readback=entry.native_markers
    end
    Bridge.publish(entry)
  end
  return #entries
end
return M
