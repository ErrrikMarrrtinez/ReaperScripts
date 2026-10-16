-- @noindex
local import=...;local M={}
local entries={
  {id='legacy_v012',version=1,display_name='Classic',feature_schema='legacy_v012',renderer_id='reaper_stretch_v1',
    controller=import('align/legacy_adapter'),settings_keys={'profile','strength','tolerance_ms','search_s','max_ratio','detail_ms','smooth_ms','fade_ms','marker_density','hybrid','hybrid_preset','hybrid_compression'},
    capabilities={manual_sync=false,protected_intervals=false,pitch_evidence=false}},
  {id='advanced_v1',version=1,display_name='Advanced (experimental)',feature_schema='align_features_v2.1',renderer_id='reaper_stretch_v2',
    controller=import('align/controller'),settings_keys=import('align/advanced/defaults').settings_keys,
    capabilities={manual_sync=true,protected_intervals=true,pitch_evidence=true,multi_candidate=true}},
}
M.entries=entries
function M.get(id)for _,entry in ipairs(entries)do if entry.id==id then return entry end end end
return M
