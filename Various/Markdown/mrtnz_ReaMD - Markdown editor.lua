-- @noindex
-- @description ReaMD - Markdown editor
-- @author mrtnz
-- Installed as a Main action by mrtnz_Markdown.lua.
local root = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
dofile(root .. 'markdown_demo.lua')
