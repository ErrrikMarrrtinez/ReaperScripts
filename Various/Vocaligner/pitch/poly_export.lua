-- @noindex
-- Экспорт результата Polyphonic: регионы аккордов, трек с текстовыми айтемами аккордов, MIDI аккордов (раскладка
-- голосов: бас в 2-й октаве + трезвучие/септаккорд от C3 — название аккорда само октав не задаёт) и MIDI найденных нот.
-- Время записи — секунды от начала айтема; в проект — позиция айтема + t (айтем играет в реальном времени проекта).
-- Темп проекта не меняется: PPQ считается по карте темпа проекта (MIDI_GetPPQPosFromProjTime). Один Undo на экспорт.
local import=...;local Poly=import('pitch/poly');local M={}
local function within(list,range,a_key,b_key)
  local out={}
  for _,x in ipairs(list) do
    local a,b=x[a_key],x[b_key]
    if not range or (b>range[1] and a<range[2]) then
      out[#out+1]={src=x,a=range and math.max(a,range[1]) or a,b=range and math.min(b,range[2]) or b}
    end
  end
  return out
end
local function undo(r,project,label,fn)
  r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
  local ok,why=xpcall(fn,debug.traceback)
  r.PreventUIRefresh(-1);r.Undo_EndBlock2(project,'Vocaligner: '..label,-1);r.UpdateArrange()
  if not ok then error(why,0) end
end
local function new_track(r,project,after,name)
  local index=after and math.floor(r.GetMediaTrackInfo_Value(after,'IP_TRACKNUMBER')) or r.CountTracks(project)
  r.InsertTrackAtIndex(index,true);local track=r.GetTrack(project,index)
  r.GetSetMediaTrackInfo_String(track,'P_NAME',name,true);return track
end
-- e: редактор (snapshot, project, track, poly); range: {a,b} в секундах айтема или nil (весь анализ)
function M.regions(e,range)
  local r,rec,s=e.r,e.poly,e.snapshot;local list=within(rec.chords,range,'s','e');local n=0
  undo(r,e.project,'export chord regions',function()
    for _,c in ipairs(list) do if c.src.root>=0 and c.b-c.a>.05 then
      local idx=r.AddProjectMarker2(e.project,true,s.pos+c.a,s.pos+c.b,Poly.chord_name(c.src),-1,0)
      assert(idx>=0,'REAPER refused a region');n=n+1
    end end
  end)
  return n
end
function M.text_track(e,range)
  local r,rec,s=e.r,e.poly,e.snapshot;local list=within(rec.chords,range,'s','e');local n=0
  undo(r,e.project,'export chord text track',function()
    local track=new_track(r,e.project,e.track,'Chords · '..s.name)
    for _,c in ipairs(list) do if c.b-c.a>.05 then
      local item=r.AddMediaItemToTrack(track)
      r.SetMediaItemInfo_Value(item,'D_POSITION',s.pos+c.a);r.SetMediaItemInfo_Value(item,'D_LENGTH',c.b-c.a)
      r.GetSetMediaItemInfo_String(item,'P_NOTES',Poly.chord_name(c.src),true);n=n+1
    end end
  end)
  return n
end
-- MIDI-айтем на весь диапазон; ноты кладутся по карте темпа проекта
local function midi_item(r,track,a,b)
  local item=r.CreateNewMIDIItemInProj(track,a,b,false);assert(item,'REAPER could not create a MIDI item')
  return item,r.GetActiveTake(item)
end
local function put(r,take,a,b,pitch,vel)
  local p0=r.MIDI_GetPPQPosFromProjTime(take,a);local p1=r.MIDI_GetPPQPosFromProjTime(take,b)
  if p1>p0 then r.MIDI_InsertNote(take,false,false,p0,p1,0,math.max(0,math.min(127,pitch)),math.max(1,math.min(127,math.floor(vel+.5))),true) end
end
-- Раскладка аккорда: бас от C2 (36+) и голоса от C3 (48+) — одна и для экспорта, и для рисования цельных блоков
function M.chord_pitches(ch)
  local out={{36+((ch.bass and ch.bass>=0) and ch.bass or ch.root),84}}
  for _,iv in ipairs(Poly.TONES[(ch.quality or 0)+1] or Poly.TONES[1]) do out[#out+1]={48+ch.root+iv,76} end
  return out
end
-- Перетаскивание аккорда из полосы в проект: MIDI-айтем с этим аккордом в позиции at (секунды проекта) на треке track
-- (nil — новый трек в конце). Длина — длина региона аккорда. Один Undo, новый айтем выделяется.
function M.drop_chord(e,chord,at,track)
  local r=e.r;local project=e.project;local item
  undo(r,project,'drop chord '..Poly.chord_name(chord),function()
    track=track or new_track(r,project,nil,'Chords')
    local len=math.max(.1,chord.e-chord.s)
    local it,take=midi_item(r,track,at,at+len);item=it
    for _,p in ipairs(M.chord_pitches(chord)) do put(r,take,at,at+len,p[1],p[2]) end
    r.MIDI_Sort(take);r.GetSetMediaItemTakeInfo_String(take,'P_NAME',Poly.chord_name(chord),true)
    r.SelectAllMediaItems(project,false);r.SetMediaItemSelected(it,true)
  end)
  return item
end
function M.chord_midi(e,range)
  local r,rec,s=e.r,e.poly,e.snapshot;local list=within(rec.chords,range,'s','e');local n=0
  if #list==0 then return 0 end
  undo(r,e.project,'export chord MIDI',function()
    local track=new_track(r,e.project,e.track,'Chord MIDI · '..s.name)
    local item,take=midi_item(r,track,s.pos+list[1].a,s.pos+list[#list].b)
    for _,c in ipairs(list) do local ch=c.src;if ch.root>=0 and c.b-c.a>.05 then
      local a,b=s.pos+c.a,s.pos+c.b;local tones=Poly.TONES[ch.quality+1] or Poly.TONES[1]
      for _,p in ipairs(M.chord_pitches(ch)) do put(r,take,a,b,p[1],p[2]) end -- бас от C2, голоса от C3
      n=n+1
    end end
    r.MIDI_Sort(take);r.GetSetMediaItemTakeInfo_String(take,'P_NAME','Chords · '..s.name,true)
  end)
  return n
end
function M.notes_midi(e,range)
  local r,rec,s=e.r,e.poly,e.snapshot;local list=within(rec.notes,range,'s','e');local n=0
  if #list==0 then return 0 end
  undo(r,e.project,'export detected notes MIDI',function()
    local track=new_track(r,e.project,e.track,'Notes MIDI · '..s.name)
    local a,b=math.huge,-math.huge;for _,x in ipairs(list) do a=math.min(a,x.a);b=math.max(b,x.b) end
    local item,take=midi_item(r,track,s.pos+a,s.pos+b)
    for _,x in ipairs(list) do put(r,take,s.pos+x.a,s.pos+x.b,x.src.p,x.src.v);n=n+1 end
    r.MIDI_Sort(take);r.GetSetMediaItemTakeInfo_String(take,'P_NAME','Notes · '..s.name,true)
  end)
  return n
end
-- Итог для айтема: строка «Key | Tempo» в заметках айтема (отдельный экшен и меню полосы аккордов)
function M.item_note(rec)
  local k=rec.keys and rec.keys[1];local alt=rec.keys and rec.keys[2]
  local key=k and Poly.key_name(k) or 'unknown'
  local text=string.format('Ruin Vocals: Key %s%s | Tempo %.1f BPM',key,alt and (' (alt. '..Poly.key_name(alt)..')') or '',rec.bpm or 0)
  return text
end
function M.write_item_note(r,item,rec)
  local _,old=r.GetSetMediaItemInfo_String(item,'P_NOTES','',false);old=old or ''
  local lines={};for line in (old..'\n'):gmatch('([^\n]*)\n') do if not line:match('^Ruin Vocals: Key ') then lines[#lines+1]=line end end
  while #lines>0 and lines[#lines]=='' do lines[#lines]=nil end
  lines[#lines+1]=M.item_note(rec)
  r.GetSetMediaItemInfo_String(item,'P_NOTES',table.concat(lines,'\n'),true)
end
return M
