-- @noindex
-- Private loader: does not modify package.path or publish global editor state.
local root = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
local modules = {}
local function load_module(name)
  if not modules[name] then
    local chunk = assert(loadfile(root .. name:gsub('%.', '/') .. '.lua'))
    modules[name] = chunk(load_module)
  end
  return modules[name]
end
return load_module('editor')
