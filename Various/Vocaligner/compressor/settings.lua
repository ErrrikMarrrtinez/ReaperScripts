-- @noindex
local M={}
M.order={'deess','breath','compressor','gate'}
M.labels={deess='De-ess',breath='Breaths',compressor='Compressor',gate='Gate'}
M.defaults={chain_order='deess,breath,compressor,gate',dynamics_rt=0,
  compressor_threshold=0,compressor_gain=0,compressor_pre_ms=0,compressor_attack_ms=10,
  compressor_release_ms=100,compressor_ratio=4,compressor_knee=0,compressor_rms_ms=5,
  compressor_interval_ms=5,compressor_hp=0,compressor_lp=20000,compressor_detail=85,
  gate_threshold=-45,gate_hysteresis=6,gate_range=60,gate_attack_ms=2,gate_hold_ms=80,
  gate_release_ms=100,gate_pre_ms=0,gate_rms_ms=5,gate_interval_ms=5,gate_hp=0,gate_lp=20000,gate_detail=85,
  chain_active=1,chain_visible=1}
M.compressor={
 {'compressor_threshold','Threshold',-60,6,'%.1f dB'},
 {'compressor_ratio','Ratio',1,100,'%.2f : 1'},
 {'compressor_gain','Out gain',-24,18,'%+.1f dB'},
 {'compressor_attack_ms','Attack',0,200,'%.1f ms'},
 {'compressor_release_ms','Release',0,500,'%.1f ms'},
 {'compressor_pre_ms','Pre-comp',0,1000,'%.1f ms'},
 {'compressor_knee','Julian knee',0,24,'%.1f dB'},
 {'compressor_rms_ms','RMS size',0,2000,'%.1f ms'},
 {'compressor_interval_ms','Env interval',.5,100,'%.1f ms'},
 {'compressor_hp','Detector HP',0,20000,'%.0f Hz'},
 {'compressor_lp','Detector LP',1,20000,'%.0f Hz'},
}
M.gate={
 {'gate_threshold','Threshold',-90,6,'%.1f dB'},
 {'gate_hysteresis','Hysteresis',0,24,'%.1f dB'},
 {'gate_range','Range',0,96,'-%.1f dB'},
 {'gate_attack_ms','Attack',0,200,'%.1f ms'},
 {'gate_hold_ms','Hold',0,2000,'%.1f ms'},
 {'gate_release_ms','Release',0,2000,'%.1f ms'},
 {'gate_pre_ms','Pre-open',0,1000,'%.1f ms'},
 {'gate_rms_ms','RMS size',0,2000,'%.1f ms'},
 {'gate_interval_ms','Env interval',.5,100,'%.1f ms'},
 {'gate_hp','Detector HP',0,20000,'%.0f Hz'},
 {'gate_lp','Detector LP',1,20000,'%.0f Hz'},
}
function M.dynamic(mode) return mode=='compressor' or mode=='gate' end
function M.is_tool(mode) return M.labels[mode]~=nil end
function M.parse(text)
 local out,seen={},{}
 for key in tostring(text):gmatch('[a-z]+') do if M.labels[key] and not seen[key] then out[#out+1]=key;seen[key]=true end end
 for _,key in ipairs(M.order) do if not seen[key] then out[#out+1]=key end end
 return out
end
return M
