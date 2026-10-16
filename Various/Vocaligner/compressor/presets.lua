-- @noindex
local import=...;local Config=import('config');local Settings=import('compressor/settings');local Codec=import('codec');local M={}
local section='Vocaligner cleanup presets v1'
local maximum=64
local function keys(mode)
 local out={};for _,key in ipairs(Config[mode..'_keys'] or {})do out[#out+1]=key end
 if Settings.dynamic(mode)then out[#out+1]=mode..'_detail' end
 return out
end
local limits={
 deess_hz={2000,14000},deess_threshold={-60,-6},deess_amount={0,100},deess_max_db={0,18},
 deess_pre_ms={0,30},deess_release_ms={0,200},deess_detail={0,100},
 breath_sensitivity={0,100},breath_db={0,18},breath_min_ms={40,500},breath_pre_ms={0,100},breath_release_ms={0,300},
 breath_detail={0,100},breath_mode={0,1},breath_target={-60,-12},breath_join_ms={0,300},breath_edge_ms={0,250},
 compressor_detail={0,100},gate_detail={0,100}}
for _,mode in ipairs({'compressor','gate'})do for _,e in ipairs(Settings[mode])do limits[e[1]]={e[3],e[4]}end end
function M.capture(mode,cfg)
 assert(Settings.is_tool(mode),'Unknown cleanup preset type')
 local values={}
 for _,key in ipairs(keys(mode))do
  local v=cfg[key];local bound=limits[key]
  assert(type(v)=='number' and v==v and math.abs(v)<math.huge,'Invalid preset parameter: '..key)
  assert(not bound or v>=bound[1] and v<=bound[2],'Preset parameter out of range: '..key)
  values[key]=v
 end
 return values
end
local function name(text)
 text=tostring(text or ''):match('^%s*(.-)%s*$')
 assert(#text>0 and #text<=100 and not text:find('[%z\1-\31]'),'Use a name of 1–100 bytes without control characters.')
 assert(text:lower()~='default','Default is the built-in reset and cannot be replaced.')
 assert(text:lower()~='custom','Custom indicates modified controls; choose another preset name.')
 return text
end
local function hex(s)return (s:gsub('.',function(ch)return string.format('%02x',ch:byte())end))end
local function unhex(s)
 assert(#s<=512*1024 and #s%2==0 and not s:find('[^%x]'),'Invalid preset data')
 return (s:gsub('%x%x',function(pair)return string.char(tonumber(pair,16))end))
end
function M.load(r,mode)
 local text=r.GetExtState(section,mode)
 if text=='' then return {} end
 local ok,data=pcall(function()
  local value=Codec.decode(unhex(text));assert(type(value)=='table' and value.version==1 and type(value.items)=='table')
  local out,count={},0
  for label,values in pairs(value.items)do
   label=name(label);assert(type(values)=='table');out[label]=M.capture(mode,values);count=count+1;assert(count<=maximum)
  end
  return out
 end)
 if not ok then return nil,'Could not read saved '..Settings.labels[mode]..' presets: '..tostring(data) end
 return data
end
function M.write(r,mode,items)
 r.SetExtState(section,mode,hex(Codec.encode({version=1,items=items})),true)
end
function M.save(r,mode,label,cfg)
 label=name(label);local items,why=M.load(r,mode);assert(items,why)
 local n=0;for _ in pairs(items)do n=n+1 end
 assert(items[label] or n<maximum,'This tool already has 64 saved presets.')
 items[label]=M.capture(mode,cfg);M.write(r,mode,items);return label
end
function M.delete(r,mode,label)
 label=name(label);local items,why=M.load(r,mode);assert(items,why)
 assert(items[label],'Preset no longer exists.');items[label]=nil;M.write(r,mode,items)
end
function M.match(mode,cfg,items,preferred)
 local function same(values)
  for _,key in ipairs(keys(mode))do if type(cfg[key])~='number' or math.abs(cfg[key]-values[key])>1e-7 then return false end end
  return true
 end
 if preferred and items and items[preferred] and same(items[preferred])then return preferred end
 if same(M.capture(mode,Config.defaults))then return 'Default' end
 local names={};for label in pairs(items or {})do names[#names+1]=label end;table.sort(names)
 for _,label in ipairs(names)do if same(items[label])then return label end end
 return 'Custom'
end
function M.apply(c,values)
 local clean=M.capture(c.mode,values)
 -- Only numeric controls belonging to this stage participate. Do not reset
 -- chain order, learned breath examples, scope, another tool or transport state.
 for _,key in ipairs(keys(c.mode))do c.cfg[key]=clean[key];c:settings_changed(key)end
 c:control_released()
end
return M
