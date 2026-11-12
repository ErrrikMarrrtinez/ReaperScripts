-- @noindex
-- @description Ruin Vocals - Detect key and tempo of selected items
-- @author mrtnz
-- Installed as a Main action by mrtnz_Ruin Vocals - vocal align, breath&pitch detect and editor, envelope dynamic.lua.
-- Polyphonic analysis (C++ extension "Vocaligner Native") of every selected audio item: key, tempo, chords and
-- detected notes. Key and tempo are written into the item notes ("Ruin Vocals: Key … | Tempo … BPM"); the full
-- result is kept for the Pitch editor (Polyphonic mode) like an analysis started there.
local r=reaper
local root=debug.getinfo(1,'S').source:match('^@?(.*[\\/])')
local cache={}
local function import(name)
  if not cache[name] then cache[name]=assert(loadfile(root..name..'.lua'))(import) end
  return cache[name]
end
local Poly,Export,Job=import('pitch/poly'),import('pitch/poly_export'),import('job')
local ok,why=Poly.available(r)
if not ok then r.ShowMessageBox(why,'Ruin Vocals',0);return end
local project=r.EnumProjects(-1)
local items={}
for i=0,r.CountSelectedMediaItems(project)-1 do
  local item=r.GetSelectedMediaItem(project,i);local take=r.GetActiveTake(item)
  if take and not r.TakeIsMIDI(take) then items[#items+1]=item end
end
if #items==0 then r.ShowMessageBox('Select one or more audio items.','Ruin Vocals',0);return end
local lines={}
local job=Job.new(r,function(j)
  for i,item in ipairs(items) do
    local good,rec,s=pcall(Poly.analyze_item,r,project,item,j:scope((i-1)/#items,i/#items),'Analyzing')
    if good then
      j:call(function()
        Poly.save(r,s.take,rec)
        r.Undo_BeginBlock2(project);Export.write_item_note(r,item,rec);r.Undo_EndBlock2(project,'Ruin Vocals: detect key and tempo',-1)
      end)
      lines[#lines+1]=s.name..': '..Export.item_note(rec):gsub('^Ruin Vocals: ','')
    else lines[#lines+1]='failed: '..tostring(rec) end
  end
end,.02)
local function loop()
  job:step()
  if not job.done then r.defer(loop);return end
  if job.error then r.ShowConsoleMsg('Ruin Vocals: '..tostring(job.error)..'\n');return end
  r.ShowConsoleMsg('Ruin Vocals — key and tempo:\n  '..table.concat(lines,'\n  ')..'\n')
  r.UpdateArrange()
end
loop()
