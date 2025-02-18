--@noindex
--NoIndex: true

local f = dofile(debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]]) .. 'mrtnz_utils.lua')

f.AutoImportAllSubprojects()
