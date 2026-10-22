-- @noindex
local import=...;local Dynamics=import('compressor/settings');local M = {}
M.defaults = {
  strength = 90, tolerance_ms = 12, search_s = 1.0, max_ratio = 1.6,
  detail_ms = 80, fade_ms = 7.5, profile = 'Vocal doubles',
  smooth_ms = 80, marker_density = 50, group_items = 1,
  hybrid = 0, hybrid_preset = 2, hybrid_compression = 45,
  deess_hz = 6500, deess_threshold = -32, deess_amount = 65,
  deess_max_db = 9, deess_pre_ms = 10, deess_release_ms = 60,
  deess_detail = 70, deess_rms_ms = 0,
  breath_sensitivity = 50, breath_db = 6, breath_min_ms = 80,
  breath_pre_ms = 10, breath_release_ms = 20, breath_detail = 70,
  breath_mode = 1, breath_target = -34, breath_curve = 50,
  breath_join_ms = 160, breath_edge_ms = 120,
  sample_rate = 32000, fft_size = 1024, hop = 320, mel_bands = 32,
  max_seconds = 1800, max_total_frames = 120000, max_cells = 24000000, frame_budget = 0.008,
}
M.profiles = {'Vocal doubles', 'Harmony / different voice', 'Speech', 'Tight attacks'}
M.presets = {
  ['Vocal doubles'] = {strength=90, tolerance_ms=12, max_ratio=1.6, detail_ms=80},
  ['Harmony / different voice'] = {strength=80, tolerance_ms=20, max_ratio=1.45, detail_ms=110},
  ['Speech'] = {strength=90, tolerance_ms=10, max_ratio=1.8, detail_ms=65},
  ['Tight attacks'] = {strength=100, tolerance_ms=3, max_ratio=1.5, detail_ms=55},
}
local bounds = {strength={0,100}, tolerance_ms={0,80}, search_s={0.05,5},
  hybrid={0,1},hybrid_preset={1,3},hybrid_compression={0,100},
  max_ratio={1.05,2.5}, detail_ms={40,250}, fade_ms={2.5,30},smooth_ms={0,180},group_items={0,1},
  deess_hz={2000,14000},deess_threshold={-60,-6},deess_amount={0,100},deess_max_db={0,18},
  deess_pre_ms={0,75},deess_release_ms={0,200},
  deess_detail={0,100},deess_rms_ms={0,100},marker_density={0,100},
  breath_sensitivity={0,100},breath_db={0,18},breath_min_ms={40,500},
  breath_pre_ms={0,100},breath_release_ms={0,300},breath_detail={0,100},breath_mode={0,1},breath_target={-80,-12},
  breath_join_ms={0,300},breath_edge_ms={0,250},breath_curve={0,100}}
for k,v in pairs(Dynamics.defaults)do M.defaults[k]=v end
for _,mode in ipairs({'compressor','gate'})do
  M[mode..'_keys']={}
  for _,e in ipairs(Dynamics[mode])do bounds[e[1]]={e[3],e[4]};M[mode..'_keys'][#M[mode..'_keys']+1]=e[1] end
end
for _,k in ipairs({'dynamics_rt','chain_active','chain_visible'})do bounds[k]={0,1}end
M.deess_keys={'deess_hz','deess_threshold','deess_amount','deess_max_db','deess_pre_ms','deess_release_ms','deess_detail','deess_rms_ms'}
M.breath_keys={'breath_sensitivity','breath_db','breath_min_ms','breath_pre_ms','breath_release_ms','breath_detail','breath_mode','breath_target','breath_join_ms','breath_edge_ms','breath_curve'}
-- Dynamics controls that are hidden for now. Every switch keeps the old code
-- path: set it back to restore the previous control and behaviour.
M.dynamics_ui={
  breath_target_only=true,   -- Target level is always on; its checkbox and Reduction are hidden
  breath_max_cut_db=25,      -- hidden Max cut used by Target level instead of breath_db
  breath_bezier=true,        -- Curve (Bezier fades) replaces Envelope detail for Breaths
}
function M.copy(t) local o={}; for k,v in pairs(t) do o[k]=v end; return o end
function M.load(r)
  local c=M.copy(M.defaults)
  local stored={}
  for key,value in r.GetExtState('mrtnz_Vocaligner','preferences'):gmatch('([^=;\r\n]+)=([^;\r\n]*)') do stored[key]=value end
  local function get(key) return stored[key] or r.GetExtState('mrtnz_Vocaligner',key) end
  for k,b in pairs(bounds) do
    local v=tonumber(get(k))
    if v and v==v then c[k]=math.max(b[1],math.min(b[2],v)) end
  end
  c.chain_order=table.concat(Dynamics.parse(get('chain_order') or c.chain_order),',')
  local p=get('profile'); if M.presets[p] then c.profile=p end
  return c
end
function M.save(r,c)
  local lines={}
  for k in pairs(bounds) do lines[#lines+1]=k..'='..tostring(c[k]) end
  lines[#lines+1]='profile='..c.profile
  lines[#lines+1]='chain_order='..c.chain_order
  table.sort(lines)
  r.SetExtState('mrtnz_Vocaligner','preferences',table.concat(lines,';'),true)
end
return M
