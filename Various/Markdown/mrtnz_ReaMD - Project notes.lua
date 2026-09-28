-- @noindex
-- @description ReaMD - Project notes
-- @author mrtnz
-- Installed as a Main action by mrtnz_Markdown.lua.
local root = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
dofile(root .. 'project_notes.lua')
