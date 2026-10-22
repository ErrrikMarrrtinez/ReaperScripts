-- @noindex
local import=...;local Audio=import('audio');local Envelope=import('envelope');local Own=import('align/ownership');local M={}
local function guid(r,item)local ok,id=r.GetSetMediaItemInfo_String(item,'GUID','',false);assert(ok and id~='','Cannot identify Hybrid item');return id end
local function normalized(chunk)return chunk:gsub('\r',''):gsub('\nSEL [^\n]*','')end
local function read(r,item)
  local ok,chunk=r.GetItemStateChunk(item,'',false)
  assert(ok and type(chunk)=='string'and #chunk<16*1024*1024,'Cannot capture a bounded Hybrid rollback snapshot')
  return {guid=guid(r,item),item=item,track=r.GetMediaItemTrack(item),chunk=chunk,key=normalized(chunk)}
end
local function inventory(r,project,known)
  local found={}
  for i=0,r.CountMediaItems(project)-1 do local item=r.GetMediaItem(project,i);local id=guid(r,item)
    if known[id]then
      -- Два айтема с одним GUID (копия/вставка с сохранением GUID, сломанная отмена): берём тот, что захватывали
      -- (known[id] хранит его указатель); второго не трогаем. Раньше любая такая пара была ошибкой.
      local want=known[id]~=true and known[id] or nil
      if found[id] then
        if want and item==want then found[id]=read(r,item)
        elseif not (want and found[id].item==want) then assert(false,'Duplicate owned item GUID; capture again') end
      else found[id]=read(r,item) end
    end
  end
  return found
end
local function same(a,b)
  for id,v in pairs(a)do if not b[id]or v.key~=b[id].key or v.track~=b[id].track then return false end end
  for id in pairs(b)do if not a[id]then return false end end
  return true
end
local function remember(owner,state,plan)
  owner.history[#owner.history+1]={state=state,plan=plan}
  -- Bound complete Undo fingerprints by both count and bytes. The captured
  -- state always survives; older native Undo states remain recoverable in REAPER.
  local bytes=0;for _,h in ipairs(owner.history)do for _,s in pairs(h.state)do bytes=bytes+#s.chunk end end
  while #owner.history>2 and (#owner.history>64 or bytes>32*1024*1024)do
    local old=table.remove(owner.history,2);for _,s in pairs(old.state)do bytes=bytes-#s.chunk end
  end
end
local function rebind(r,d,found,baseline)
  for _,s in ipairs(Audio.parts(d.snapshot))do
    local p=found[d.hybrid_owner.part_ids[s]]
    if p then s.item=p.item;s.take=r.GetActiveTake(p.item);s.source=r.GetMediaItemTake_Source(s.take)
      if baseline then s.signature=Audio.state(r,s.project,s.item).signature end
    end
  end
  if d.snapshot.composite then
    local s=d.snapshot;local first=s.parts[1];s.item,s.take,s.source=first.item,first.take,first.source
    if baseline then s.signature=Audio.current(r,s).signature end
  end
end
function M.check(r,d)
  local owner=d.hybrid_owner;if not owner then return nil end
  local ok,found=pcall(inventory,r,d.snapshot.project,owner.known)
  if not ok then return false,tostring(found)end
  for i=#owner.history,1,-1 do local h=owner.history[i]
    if same(found,h.state)then
      d.hybrid_active=h.plan~=nil;d.applied=d.hybrid_active;d.applied_plan=h.plan
      rebind(r,d,found,not h.plan);return true
    end
  end
  for id in pairs(found)do if not owner.initial[id]then return false,'A Hybrid fragment changed. Use REAPER Undo or capture this edited selection again.'end end
  if d.hybrid_active then return false,'A Hybrid item changed. Use REAPER Undo or capture the edited selection again.'end
  return nil -- A later Classic/Cleaner write retains its own normal ownership.
end
local function initialize(r,d)
  if d.hybrid_owner then return d.hybrid_owner end
  if d.applied then error('Restore the currently applied timing before enabling Hybrid.',0)end
  local owner={initial={},known={},history={},part_ids={}}
  for _,s in ipairs(Audio.parts(d.snapshot))do
    local inspected,why=Own.inspect(r,s,true);assert(inspected,tostring(why and why.message or why))
    -- Split duplicates take FX state. Stateful processing can change at every
    -- seam, so this renderer requires FX to stay on the track or be rendered.
    assert(r.TakeFX_GetCount(s.take)==0,'Hybrid requires takes without take FX. Render them first or keep using Stretch.')
    local v=read(r,s.item);owner.initial[v.guid]=v;owner.known[v.guid]=v.item;owner.part_ids[s]=v.guid
  end
  remember(owner,owner.initial,nil);d.hybrid_owner=owner;return owner
end
local function replace(r,project,owner,target)
  local found=inventory(r,project,owner.known)
  for id,p in pairs(found)do if not target[id]then assert(r.DeleteTrackMediaItem(p.track,p.item),'Could not remove an owned Hybrid fragment')end end
  for id,p in pairs(target)do
    local item=found[id]and found[id].item
    if not item then item=assert(r.AddMediaItemToTrack(p.track),'Could not restore a Hybrid item')end
    assert(r.SetItemStateChunk(item,p.chunk,false),'Could not restore Hybrid item state')
    assert(guid(r,item)==id,'REAPER changed an item GUID during restore')
    r.UpdateItemInProject(item)
  end
  local actual=inventory(r,project,owner.known)
  assert(same(actual,target),'REAPER did not restore the complete Hybrid item state')
  return actual
end
local function mode(r)
  for i=0,64 do local ok,name=r.EnumPitchShiftModes(i);if not ok then break end
    if name and name:lower():find('lastique')and name:find('3')and name:lower():find('pro')then return i<<16 end
  end
  return -1
end
local function write_piece(r,d,item,p,cfg,pitchmode)
  local original=Audio.parts(d.snapshot)[p.part];local origin=original.pos-d.snapshot.pos
  local s=Audio.state(r,d.snapshot.project,item)
  local plan={snapshot=s,pos=p.pos,len=p.len,markers={},unchanged=false}
  for i,m in ipairs(p.markers)do plan.markers[i]={t=m.t-p.split_a,target=m.target,source=m.source}end
  -- Envelope preparation uses the split item's captured clock, including the
  -- quiet shoulders that will be trimmed. Its audible part maps to the same voice.
  local prepared=Envelope.prepare(r,s,plan,nil)
  local take=r.GetActiveTake(item);local count=r.GetTakeNumStretchMarkers(take)
  assert(r.DeleteTakeStretchMarkers(take,0,count)==count,'Could not clear Hybrid markers')
  assert(r.SetMediaItemInfo_Value(item,'D_POSITION',p.pos))
  assert(r.SetMediaItemInfo_Value(item,'D_LENGTH',p.len))
  assert(r.SetMediaItemTakeInfo_Value(take,'D_STARTOFFS',Audio.source_time(original,p.a-origin)))
  local elastic=p.local_edit or math.abs(p.ratio-1)>1e-9 or #original.markers>0
  if elastic then
    assert(r.SetMediaItemTakeInfo_Value(take,'B_PPITCH',math.abs(original.rate-1)<1e-9 and 1 or original.B_PPITCH))
    assert(r.SetMediaItemTakeInfo_Value(take,'I_PITCHMODE',pitchmode))
    assert(r.SetMediaItemTakeInfo_Value(take,'I_STRETCHFLAGS',(original.I_STRETCHFLAGS&(~7))|2))
    assert(r.SetMediaItemTakeInfo_Value(take,'F_STRETCHFADESIZE',cfg.fade_ms/1000))
  end
  for _,m in ipairs(elastic and p.markers or {})do
    local pos=(m.target-p.pos)*original.rate;local ix=r.SetTakeStretchMarker(take,-1,pos,m.source)
    assert(ix>=0 and r.SetTakeStretchMarkerSlope(take,ix,0),'Could not write Hybrid marker')
    local _,actual,source=r.GetTakeStretchMarker(take,ix)
    assert(math.abs(actual-pos)<1e-6 and math.abs(source-m.source)<1e-6,'REAPER constrained a Hybrid marker')
  end
  -- Internal fades sit exclusively inside the verified quiet shoulders.
  local fade=math.min(.005,p.len*.1)
  if p.split_a>origin+1e-8 then
    assert(r.SetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO',-1));assert(r.SetMediaItemInfo_Value(item,'D_FADEINLEN',fade))
  end
  if p.split_b<origin+original.len-1e-8 then
    assert(r.SetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO',-1));assert(r.SetMediaItemInfo_Value(item,'D_FADEOUTLEN',fade))
  end
  Envelope.write(r,s,prepared);r.UpdateItemInProject(item)
  assert(math.abs(r.GetMediaItemInfo_Value(item,'D_POSITION')-p.pos)<1e-7 and math.abs(r.GetMediaItemInfo_Value(item,'D_LENGTH')-p.len)<1e-7,'REAPER constrained Hybrid bounds')
end
local function render(r,d,cfg,pitchmode)
  local owner=d.hybrid_owner;local restored=replace(r,d.snapshot.project,owner,owner.initial)
  rebind(r,d,restored,true)
  if d.plan.unchanged then return end
  local s=d.snapshot
  for part_index,part in ipairs(Audio.parts(s))do
    local pieces={};for _,p in ipairs(d.plan.pieces)do if p.part==part_index then pieces[#pieces+1]=p end end
    local items={part.item};local current=part.item
    -- Split on the immutable source timeline before moving any fragment.
    for i=1,#pieces-1 do
      local child=assert(r.SplitMediaItem(current,s.pos+pieces[i].split_b),'Could not split a Hybrid pause')
      local id=guid(r,child);owner.known[id]=child;items[#items+1]=child;current=child
    end
    for i,p in ipairs(pieces)do write_piece(r,d,items[i],p,cfg,pitchmode)end
  end
end
function M.run(r,project,reference,dubs,cfg,restoring)
  if r.EnumProjects(-1)~=project then return nil,'Switch back to the captured project.'end
  if r.GetPlayStateEx(project)&4~=0 then return nil,'Stop recording before editing Hybrid timing.'end
  if not restoring and reference then local ok,why=Audio.unchanged(r,reference);if not ok then return nil,why end end
  local batch={};local total_bytes=0
  local ok,err=pcall(function()
    for _,name in ipairs({'GetSetMediaItemInfo_String','CountMediaItems','GetMediaItem','GetMediaItemTrack','SplitMediaItem','DeleteTrackMediaItem','AddMediaItemToTrack'})do assert(type(r[name])=='function','Hybrid API unavailable: '..name)end
    for _,d in ipairs(dubs)do
      if (restoring and d.hybrid_active)or (not restoring and d.enabled and d.plan)then
        local valid,why=Audio.check_dub(r,d);assert(valid,why)
        assert(restoring or d.plan.hybrid,'Restore Hybrid before switching to Stretch.')
        if not restoring then import('align/hybrid/plan').validate(d.plan,cfg)end
        local owner=initialize(r,d);local before=inventory(r,project,owner.known)
        for _,v in pairs(before)do
          assert(r.GetMediaItemInfo_Value(v.item,'C_LOCK')==0,'A Hybrid fragment is locked')
          total_bytes=total_bytes+#v.chunk
        end
        assert(total_bytes<=32*1024*1024,'Hybrid rollback exceeds 32 MB. Work on fewer items.')
        if restoring or (not d.plan.unchanged or d.hybrid_active)and d.applied_plan~=d.plan then batch[#batch+1]={dub=d,before=before,applied=d.applied_plan,active=d.hybrid_active}end
      elseif restoring and d.applied then error('This group also has Stretch edits. Restore those separately before Hybrid.',0)end
    end
  end)
  if not ok then return nil,tostring(err)end
  if #batch==0 then return 0 end
  r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
  local pitchmode=mode(r)
  ok,err=xpcall(function()
    for _,entry in ipairs(batch)do local d=entry.dub
      if restoring then replace(r,project,d.hybrid_owner,d.hybrid_owner.initial)else render(r,d,cfg,pitchmode)end
      entry.after=inventory(r,project,d.hybrid_owner.known)
    end
  end,debug.traceback)
  if not ok then for i=#batch,1,-1 do local e=batch[i]
    local yes,why=pcall(replace,r,project,e.dub.hybrid_owner,e.before)
    if not yes then err=err..'\nRollback needs REAPER Undo: '..tostring(why)end
    e.dub.applied=e.active;e.dub.hybrid_active=e.active;e.dub.applied_plan=e.applied
    if yes then rebind(r,e.dub,inventory(r,project,e.dub.hybrid_owner.known),not e.active)end
  end end
  r.PreventUIRefresh(-1);r.Undo_EndBlock2(project,ok and (restoring and 'Vocaligner: restore Hybrid takes' or 'Vocaligner: Hybrid timing')or 'Vocaligner: rolled back Hybrid edit',-1);r.UpdateArrange()
  if not ok then return nil,err end
  for _,e in ipairs(batch)do local d=e.dub;local plan=not restoring and not d.plan.unchanged and d.plan or nil
    remember(d.hybrid_owner,e.after,plan);d.hybrid_active=plan~=nil;d.applied=d.hybrid_active;d.applied_plan=plan
    d.original_state=d.original_state or d.snapshot;rebind(r,d,e.after,not plan)
  end
  return #batch
end
function M.active(dubs)
  for _,d in ipairs(dubs)do if d.hybrid_active then return true end end
  return false
end
return M
