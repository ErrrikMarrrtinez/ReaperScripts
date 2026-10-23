-- @noindex
local import=...;local Store=import('pitch/store');local Notes=import('pitch/notes');local Analysis=import('pitch/analysis');local M={}
local section='Vocaligner Pitch View 1'
local function valid(r,project,item)return item and (not r.ValidatePtr2 or r.ValidatePtr2(project,item,'MediaItem*')) end
local function track_of(r,project,item)
  if not valid(r,project,item) then return nil end
  return r.GetMediaItemTrack and r.GetMediaItemTrack(item) or r.GetMediaItem_Track and r.GetMediaItem_Track(item)
end
local function audio_take(r,project,item)
  if not valid(r,project,item) then return nil end
  local take=r.GetActiveTake(item)
  if take and (not r.ValidatePtr2 or r.ValidatePtr2(project,take,'MediaItem_Take*')) and not r.TakeIsMIDI(take) then return take end
end
local function selection_key(r,project)
  local parts={tostring(r.GetLastTouchedTrack and r.GetLastTouchedTrack()),tostring(r.GetSelectedTrack and r.GetSelectedTrack(project,0))}
  for i=0,r.CountSelectedMediaItems(project)-1 do parts[#parts+1]=tostring(r.GetSelectedMediaItem(project,i))end
  return table.concat(parts,'|')
end
function M.scan(e,project)
  local r=e.r
  if not r.CountTracks or not r.GetTrack or not r.CountTrackMediaItems then return end
  local revision=r.GetProjectStateChangeCount(project)
  if e.workspace and e.workspace.project==project and e.workspace.revision==revision then return e.workspace end
  local old=e.workspace and e.workspace.project==project and e.workspace
  local began=r.time_precise()
  local ws={project=project,revision=revision,tracks={},items={},by_track={},by_item={}}
  for i=0,r.CountTracks(project)-1 do
    local track=r.GetTrack(project,i);local guid=r.GetTrackGUID(track);local _,name=r.GetTrackName(track,'')
    local _,visible=r.GetProjExtState(project,section,guid)
    local row={track=track,guid=guid,name=name~='' and name or ('Track '..(i+1)),index=i+1,items={},analyzed=0,visible=visible=='1'}
    for j=0,r.CountTrackMediaItems(track)-1 do
      local item=r.GetTrackMediaItem(track,j);local take=audio_take(r,project,item)
      if take then
        local entry={item=item,take=take,track=row,pos=r.GetMediaItemInfo_Value(item,'D_POSITION'),len=r.GetMediaItemInfo_Value(item,'D_LENGTH'),name=r.GetTakeName(take)}
        local _,text=r.GetSetMediaItemTakeInfo_String(take,Store.key,'',false)
        local prior=old and old.by_item[item]
        if prior and prior.take==take and prior.text==text then entry.state=prior.state
        elseif text and text~='' then local ok,state=pcall(Store.read,r,take);if ok then entry.state=state else entry.error=tostring(state) end end
        entry.text=text
        if entry.state and entry.state.analysis then row.analyzed=row.analyzed+1 end
        row.items[#row.items+1]=entry;ws.items[#ws.items+1]=entry;ws.by_item[item]=entry
      end
    end
    table.sort(row.items,function(a,b)return a.pos<b.pos end)
    ws.tracks[#ws.tracks+1]=row;ws.by_track[track]=row
  end
  e.workspace=ws;if e.measure then e:measure('workspace_scan',began) end;return ws
end
function M.focus(e,project)
  local r=e.r;local ws=M.scan(e,project);local selected={}
  for i=0,r.CountSelectedMediaItems(project)-1 do local item=r.GetSelectedMediaItem(project,i);local take=audio_take(r,project,item)
    if take then selected[#selected+1]=item end
  end
  if e.focus_track then
    local row=ws and ws.by_track[e.focus_track]
    if e.focus_project==project and row and e.focus_native==selection_key(r,project) then
      local item=e.focus_item
      if not valid(r,project,item) or not ws.by_item[item] or ws.by_item[item].track~=row then
        item=nil;for _,entry in ipairs(row.items)do if audio_take(r,project,entry.item)then item=entry.item;break end end
      end
      e.track=row.track;e.track_row=row;e.selected_items={};return item
    end
    e.focus_track=nil;e.focus_item=nil
  end
  local last=r.GetLastTouchedTrack and r.GetLastTouchedTrack()
  if ws and not ws.by_track[last] then last=nil end
  local track=last
  if #selected>0 then
    local found=false;for _,item in ipairs(selected)do if track_of(r,project,item)==last then found=true;break end end
    if not found then track=track_of(r,project,selected[1]) end
  elseif r.GetSelectedTrack then track=r.GetSelectedTrack(project,0) or track or e.track end
  local item
  if e.focus_item and e.focus_project==project and valid(r,project,e.focus_item) and (not track or track_of(r,project,e.focus_item)==track) then
    local changed=false;local signature={};for _,v in ipairs(selected)do signature[#signature+1]=tostring(v) end
    local sig=table.concat(signature,'|');changed=e.focus_selection and e.focus_selection~=sig
    if not changed then item=e.focus_item else e.focus_item=nil end
  end
  if not item and #selected==1 then item=selected[1] end
  local cursor=r.GetCursorPositionEx and r.GetCursorPositionEx(project) or 0
  if not item then
    if #selected>0 then
      -- несколько выделенных (в том числе с перекрытием на одном треке): проанализированный важнее, затем тот,
      -- что под курсором, затем уже открытый (чтобы окно не прыгало); при равенстве — первый по позиции
      local best,best_score,best_pos
      for _,v in ipairs(selected) do if not track or track_of(r,project,v)==track then
        local ent=ws and ws.by_item[v];local score=0
        if ent and ent.state and ent.state.analysis then score=score+4 end
        if ent and cursor>=ent.pos and cursor<ent.pos+ent.len then score=score+2 end
        if v==e.item then score=score+1 end
        local pos=ent and ent.pos or 0
        if not best or score>best_score or (score==best_score and pos<best_pos) then best,best_score,best_pos=v,score,pos end
      end end
      item=best
    elseif ws and ws.by_track[track] then
      for _,v in ipairs(ws.by_track[track].items) do
        if audio_take(r,project,v.item)then
          if not item or v.item==e.item then item=v.item end
          if cursor>=v.pos and cursor<v.pos+v.len then item=v.item;break end
        end
      end
    end
  end
  if not audio_take(r,project,item)then item=nil end
  if item then track=track_of(r,project,item) or track end
  e.track=track;e.track_row=ws and ws.by_track[track];e.selected_items=selected
  return item
end
function M.bounds(e)
  local s=e.snapshot;local row=e.track_row
  if not s then return 0,10 end
  local a,b=s.pos,s.pos+s.len
  if row then for _,v in ipairs(row.items)do a=math.min(a,v.pos);b=math.max(b,v.pos+v.len) end end
  if e.workspace and not (e.state and e.state.bypassed) then
    for _,track in ipairs(e.workspace.tracks)do if track.visible then for _,v in ipairs(track.items)do if v.state then a=math.min(a,v.pos);b=math.max(b,v.pos+v.len)end end end end
  end
  local extent=e.view_extent
  if extent and extent.item==e.item and extent.project==e.project and extent.pos==s.pos then
    a=math.min(a,s.pos+extent.a);b=math.max(b,s.pos+extent.b)
  end
  return a-s.pos,b-s.pos
end
function M.activate_track(e,row)
  if e:busy() or e.gesture then return end
  local r=e.r;local project=r.EnumProjects(-1);local cursor=r.GetCursorPositionEx and r.GetCursorPositionEx(project) or 0
  local item=row.items[1] and row.items[1].item
  for _,entry in ipairs(row.items)do if cursor>=entry.pos and cursor<entry.pos+entry.len then item=entry.item;break end end
  e.focus_track=row.track;e.focus_project=project;e.focus_native=selection_key(r,project);e.focus_item=item
  e:refresh(true)
end
function M.activate(e,item)
  if e:busy() or e.gesture then return end
  local r=e.r;local project=r.EnumProjects(-1);if not valid(r,project,item) then return end
  e.focus_item=item;e.focus_project=project;local signature={}
  for i=0,r.CountSelectedMediaItems(project)-1 do signature[#signature+1]=tostring(r.GetSelectedMediaItem(project,i)) end
  e.focus_selection=table.concat(signature,'|');e:refresh(true)
end
function M.restore_focus(e,project,guid)
  local r=e.r;if not guid or r.EnumProjects(-1)~=project then return false end
  -- Undo can recreate native item/take pointers. Rebind the edited take by
  -- its persistent GUID before normal selection/cursor fallback chooses a row.
  local function matches(item)
    local take=audio_take(r,project,item)
    if not take then return false end
    local ok,id=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
    return ok and id==guid
  end
  local item
  if matches(e.item)then item=e.item else
    local ws=M.scan(e,project)
    for _,entry in ipairs(ws and ws.items or {})do if matches(entry.item)then
      if item then return false end;item=entry.item
    end end
  end
  if not item then return false end
  e.focus_item=item;e.focus_project=project
  local signature={};for i=0,r.CountSelectedMediaItems(project)-1 do signature[#signature+1]=tostring(r.GetSelectedMediaItem(project,i))end
  e.focus_selection=table.concat(signature,'|')
  e.focus_track=track_of(r,project,item);e.focus_native=selection_key(r,project)
  return true
end
function M.targets(e,track)
  local r=e.r;local project=r.EnumProjects(-1)
  M.focus(e,project)
  local items={}
  -- A canvas/Tracks focus is for editing, not a replacement for REAPER's
  -- explicit batch selection. Capture every selected audio item at the click.
  if not track then for i=0,r.CountSelectedMediaItems(project)-1 do
    local item=r.GetSelectedMediaItem(project,i);local take=audio_take(r,project,item)
    if take then items[#items+1]=item end
  end end
  if #items==0 and e.track_row then for _,v in ipairs(e.track_row.items) do if audio_take(r,project,v.item)then items[#items+1]=v.item end end end
  if #items==0 and audio_take(r,project,e.item) then items={e.item} end
  return items
end
function M.visible(e,value,row)
  if not row then return end
  if e.view and e.snapshot then
    e.view_extent={item=e.item,project=e.project,pos=e.snapshot.pos,a=e.view.start,b=e.view.start+e.view.span}
  end
  e.r.SetProjExtState(e.project,section,row.guid,value and '1' or '0')
  row.visible=value
  e.r.MarkProjectDirty(e.project)
end
function M.visual(e,entry)
  if entry.visual~=nil then return entry.visual or nil end
  entry.visual=false
  if not entry.state or not entry.state.analysis then return end
  local ok,result=pcall(function()
    local s=Analysis.capture(e.r,e.project,entry.item,true);local state=entry.state
    e.cache=e.cache or {};e.cache[e.project]=e.cache[e.project] or {}
    local cached=e.cache[e.project][state.analysis]
    if not cached then
      local data,geometry=Store.load_analysis(e.r,e.project,state.analysis)
      if not data then return end
      cached={data=data,geometry=geometry}
      if e.remember then e:remember(e.project,state.analysis,cached) else e.cache[e.project][state.analysis]=cached end
    end
    local data,why=Store.adapt(cached.data,{},cached.geometry,s)
    if not data then entry.error=why;return end
    local _,notes=Store.adapt({frames={},hop=data.hop,len=state.geometry.len},state.notes,state.geometry,s)
    if type(notes)~='table' then entry.error=notes;return end
    return {data=data,notes=notes,version=state.curve_version or 1,glyphs={}}
  end)
  if ok then entry.visual=result or false else entry.error=tostring(result) end
  return entry.visual or nil
end
function M.notes(e,entry)
  if entry.view_notes~=nil then return entry.view_notes end
  entry.view_notes={}
  if not entry.state or not entry.state.analysis then return entry.view_notes end
  local ok,s=pcall(Analysis.capture,e.r,e.project,entry.item)
  if not ok then entry.error=tostring(s);return entry.view_notes end
  local state=entry.state
  local data,notes=Store.adapt({frames={},hop=.016,len=state.geometry.len},state.notes,state.geometry,s)
  if data then entry.view_notes=notes else entry.error=notes end
  return entry.view_notes
end
return M
