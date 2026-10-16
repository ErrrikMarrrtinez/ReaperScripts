-- @noindex
-- Private loader: no package.path changes and no global module state.
local root = debug.getinfo(1, 'S').source:match('^@(.+[\\/])')
local cache = {}
local function import(name)
  if not cache[name] then cache[name] = assert(loadfile(root .. name .. '.lua'))(import) end
  return cache[name]
end
return {new = import('app').new, import = import, version = import('version').version}
