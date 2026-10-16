-- @noindex
local import=...;local DSP=import('dsp');local M={}
-- Local linear regression preserves a steady delay and gradual phrase acceleration.
-- It smooths displacement, not absolute times, and never connects distant phrases.
function M.smooth(points,radius,job)
  if radius<=0 then return end
  local result={};local first,last=1,1
  for i,p in ipairs(points) do
    while first<i and points[first].t<p.t-radius do first=first+1 end
    while last<#points and points[last+1].t<=p.t+radius do last=last+1 end
    local sw,sx,sy,sxx,sxy,gain,cost=0,0,0,0,0,0,0
    for j=first,last do
      local q=points[j];local x=q.t-p.t;local u=math.abs(x)/radius
      local w=(1-u*u)^2*math.max(.08,1-q.cost)^2*(1+math.min(1,q.onset or 0))
      sw=sw+w;sx=sx+w*x;sy=sy+w*q.shift;sxx=sxx+w*x*x;sxy=sxy+w*x*q.shift
      gain=gain+w*(q.gain or 1);cost=cost+w*q.cost
    end
    local denom=sw*sxx-sx*sx
    local shift=denom>1e-12 and (sy*sxx-sx*sxy)/denom or sy/math.max(1e-12,sw)
    -- Near identity, require a consistent local advantage before moving anything.
    -- One noisy MFCC frame no longer alternates the displacement between zero/full.
    if math.abs(shift)<.08 and p.gain then shift=shift*DSP.clamp((gain/sw-.015)/.045,0,1) end
    local trust=DSP.clamp((.8-cost/sw)/.3,0,1)
    result[i]=shift*trust;p.trust=trust
    if job and i%256==0 then job:checkpoint() end
  end
  for i,p in ipairs(points) do p.shift=result[i] end
end
return M
