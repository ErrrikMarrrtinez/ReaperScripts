--@noindex
--NoIndex: true

local f = dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'mrtnz_utils.lua')
local r = reaper

r.PreventUIRefresh(0)
r.Undo_BeginBlock()

f.ImportAllSubprojectTracksFromParent()

r.Undo_EndBlock("Импорт дабберов из родительского проекта", -1)
r.UpdateArrange()
r.PreventUIRefresh(-1)
