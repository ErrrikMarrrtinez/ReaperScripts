-- @noindex
local import=...;local U=import('align/util');local M={}
function M.weights(cfg)
  local pitch=cfg.advanced_pitch and cfg.profile~='Harmony / different voice' and cfg.profile~='Speech' and .05 or 0
  return {.42,.23,.20,.10,pitch,full=.95+pitch}
end
function M.pair(a,b,cfg,ap,bp,an,bn)
  if not a or not b or a.missing or b.missing then return math.huge,0,false end
  if a.background>=.90 and b.background>=.90 then return cfg.silence_cost,0,false end
  local w=cfg.weights or M.weights(cfg)
  local spec=U.clamp((1-U.dot(a.spec,b.spec))/2,0,1)
  local cep,delta=0,0
  for k=1,12 do cep=cep+math.min(((a.cep[k]-b.cep[k])/2)^2,1)/12 end
  if a.delta_valid and b.delta_valid then
    for k=1,6 do delta=delta+math.min(((a.delta[k]-b.delta[k])/.5)^2,1)/6 end
    cep=.70*cep+.30*delta
  end
  local rs=a.spectral_reliability*b.spectral_reliability
  local rc=a.cep_reliability*b.cep_reliability
  local context=ap and bp and an and bn and not ap.missing and not bp.missing and not an.missing and not bn.missing
  local ro=a.onset_reliability*b.onset_reliability*(context and 1 or .70)
  local re=a.energy_reliability*b.energy_reliability
  local rp=(a.pitch_reliability or 0)*(b.pitch_reliability or 0)
  local W=w[1]*rs+w[2]*rc+w[3]*ro+w[4]*re+w[5]*rp
  local cost=w[1]*rs*spec+w[2]*rc*cep+w[3]*ro*math.abs(a.onset-b.onset)+w[4]*re*math.abs(a.energy-b.energy)
  if w[5]>0 and rp>0 and a.pitch and b.pitch then
    local d=math.min(math.abs(a.pitch-b.pitch)/3,1)
    if a.pitch_delta and b.pitch_delta then d=.75*d+.25*math.min(math.abs(a.pitch_delta-b.pitch_delta)/2,1)end
    cost=cost+w[5]*rp*d
  end
  local reliability=W/w.full
  cost=reliability>=cfg.min_pair and cost/W or cfg.unknown_cost
  local class=.65*(a.event*b.background+a.background*b.event)
  if a.voicing_available and b.voicing_available then class=class+.10*math.abs(a.voiced-b.voiced)*(1-a.background)*(1-b.background)end
  local onset=context and .12*math.max(a.onset,b.onset)*(math.abs(ap.onset-bp.onset)+math.abs(an.onset-bn.onset))/2 or 0
  cost=U.clamp(cost+cfg.missing_penalty*(1-reliability)+class+onset,0,cfg.max_cost)
  return cost,reliability,reliability>=cfg.min_pair and a.trustworthy and b.trustworthy
end
function M.at(dub,ref,i,j,cfg)
  return M.pair(dub.frames[i],ref.frames[j],cfg,dub.frames[i-1],ref.frames[j-1],dub.frames[i+1],ref.frames[j+1])
end
return M
