-- @noindex
local import=...;local U=import('align/util');local M={}
M.version=2;M.frontend='align_features_v2.1';M.objective='query_gaps_v2_local_consensus';M.planner='stretch_plan_v2.3'
M.values={sample_rate=32000,fft_size=1024,hop=320,mel_bands=32,profile='Vocal doubles',
  strength=90,tolerance_ms=12,search_s=1,max_ratio=1.6,marker_density=50,fade_ms=7.5,
  advanced_smooth=50,advanced_pitch=false,conservative=true,protect_unmatched=true,sparse_guide_context=true,matcher='guided',
  min_pair=.25,unknown_cost=.70,max_cost=1.5,missing_penalty=.12,silence_cost=.12,
  gap_floor=.15,gap_active=.70,gap_onset=.35,gap_open=.30,gap_close=.10,macro_open=.80,
  active_gap_s=.08,background_gap_s=.20,max_gap=20,macro_gap_s=.60,
  fine_band=.160,expanded_band=.400,coarse_hop=.04,candidate_count=4,candidate_expanded=8,
  candidate_near=.08,candidate_separation=.080,distinct_s=.060,margin_min=.04,
  consensus_s=.020,consensus_min_s=.150,local_replay_s=.320,
  accept_mean=.45,accept_coverage=.70,accept_gap=.20,sole_mean=.30,sole_coverage=.85,sole_gap=.10,
  min_support_s=.150,transient_ratio=1.20,shoulder_ratio=1.8,max_shoulder_s=.400,
  epsilon=1e-6,lambda=4096,rho=1,iterations=2000,primal_abs=1e-7,dual_abs=1e-7,residual_rel=1e-8,
  geometry_tolerance=1e-6,native_tolerance=1e-6,map_error=.003,attack_error=.0015,quantum=1e-6,
  max_states=60000000,max_trace_bytes=32*1024*1024,max_coarse_work=6000000,max_reduce_work=4000000,max_regularize_work=20000000,
  max_frames=120000,max_markers=8192,max_seconds=1800,frame_budget=.008,max_candidates_total=512,
  max_feature_bytes=384*1024*1024,max_pair_cache_bytes=64*1024*1024,max_write_operations=100000,abs_rate_min=0,abs_rate_max=0}
M.policy_keys={'strength','tolerance_ms','max_ratio','marker_density','fade_ms','advanced_smooth','abs_rate_min','abs_rate_max'}
M.match_keys={'search_s','profile','advanced_pitch','max_ratio','matcher'}
M.settings_keys={'profile','strength','tolerance_ms','search_s','max_ratio','marker_density','fade_ms','advanced_smooth','advanced_pitch','abs_rate_min','abs_rate_max','matcher'}
M.matchers={'guided','strict'}
function M.config(settings)
  local c=U.copy(M.values)
  for k,v in pairs(settings or {})do if c[k]~=nil then c[k]=v end end
  for k,v in pairs(c)do if type(M.values[k])=='number' then assert(U.finite(v),'Invalid Advanced setting: '..k) end end
  assert(c.strength>=0 and c.strength<=100 and c.tolerance_ms>=0 and c.search_s>0 and c.search_s<=5,'Invalid timing controls')
  assert(c.max_ratio>=1 and c.advanced_smooth>=0 and c.advanced_smooth<=100,'Invalid warp controls')
  assert(c.matcher=='guided' or c.matcher=='strict','Invalid Advanced matcher')
  assert(c.max_gap==20 and c.hop==320 and c.fft_size==1024 and c.sample_rate==32000 and c.mel_bands==32,'Unsupported frontend/state schema')
  -- Explicit low-level lambda overrides are useful to numerical fixtures, never UI persistence.
  if not settings or settings.lambda==nil then c.lambda=c.advanced_smooth==0 and 0 or 4096*2^((c.advanced_smooth-50)/12.5) end
  c.map_error=.003*2^((50-c.marker_density)/25);c.attack_error=c.map_error*.5
  c.feature_version=M.frontend;c.algorithm_version=M.version;c.objective_version=M.objective;c.planner_version=M.planner
  return c
end
function M.match_key(c,constraints)
  return U.key({engine=M.version,frontend=M.frontend,objective=M.objective,search=c.search_s,profile=c.profile,
    pitch=c.advanced_pitch,max_ratio=c.max_ratio,matcher=c.matcher,constraints=constraints or {},defaults=M.values})
end
return M
