-- @noindex
local import=...;local U=import('align/util');local Defaults=import('align/advanced/defaults');local M={}
local section='Vocaligner Align 1'
function M.load(r)
  local result={selected_engine='legacy_v012',advanced={}}
  if not r.GetExtState then return result end
  local text=r.GetExtState(section,'settings')or '';if #text>8192 then return result end
  local stored={};for k,v in text:gmatch('([^=;\r\n]+)=([^;\r\n]*)')do stored[k]=v end
  if stored.version~='1'then return result end
  result.selected_engine=stored.engine or 'legacy_v012'
  for _,k in ipairs(Defaults.settings_keys)do
    local v=stored['advanced.'..k]
    if k=='profile'then if v=='Vocal doubles'or v=='Harmony / different voice'or v=='Speech'or v=='Tight attacks'then result.advanced[k]=v end
    elseif k=='advanced_pitch'then result.advanced[k]=v=='true'
    elseif k=='matcher'then if v=='guided'or v=='strict'then result.advanced[k]=v end
    elseif v then local n=tonumber(v);if U.finite(n)then result.advanced[k]=n end end
  end
  local ok=pcall(Defaults.config,result.advanced);if not ok then result.advanced={}end
  return result
end
function M.save(r,selected,advanced)
  if not r.SetExtState then return end
  local rows={'version=1','engine='..selected}
  for _,k in ipairs(Defaults.settings_keys)do local v=advanced[k];if v~=nil then rows[#rows+1]='advanced.'..k..'='..tostring(v)end end
  table.sort(rows);r.SetExtState(section,'settings',table.concat(rows,';'),true)
end
return M
