-- @noindex
-- @description ReaMD - Multiline input demo (legacy launcher)
-- @author mrtnz
-- Compatibility launcher; the registered action is mrtnz_ReaMD - Multiline input demo.lua.
local root = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
dofile(root .. 'demo.lua')
