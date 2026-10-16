-- @noindex
-- Finite links are opt-in per boundary. Unedited v1-v5 boundaries keep their
-- original evaluator, including correction blending at zero transition mix.
local import=...;local Expression=import('pitch/expression');local Trace=import('pitch/trace');local M={}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function smooth(x)x=clamp(x,0,1);return x*x*(3-2*x)end
function M.active(n)return n~=nil and n.link~=nil and (n.link.owner==nil or n.link.owner==n.id)end
function M.legacy(n)return M.active(n) and n.link.version==1 end
local function frame_range(data,lo,hi,visit)
  local source,offset=data,0;while source._source do offset=offset+(source._offset or 0);source=source._source end
  local frames=source.frames or {};local a,b=1,#frames
  while a<=b do local mid=(a+b)//2;if frames[mid].t<lo+offset then a=mid+1 else b=mid-1 end end
  for i=a,#frames do local f=frames[i];local t=f.t-offset;if t>hi+1e-8 then break end;visit(f,t) end
end
function M.auto(a,b,data,policy)
  local hop=data and data.hop or .016
  if not data then return a.finish,math.max(a.finish+hop,b.start) end
  local frames=data.frames
  if not data._link_windows or data._link_frames~=frames or data._link_count~=#frames then
    data._link_windows={};data._link_frames=frames;data._link_count=#frames;data._link_cache_count=0
  end
  local key=table.concat({policy or 2,a.start,a.finish,a.center,b.start,b.finish,b.center},'|');local cached=data._link_windows[key]
  if cached then return cached[1],cached[2] end
  local function band(n,side)
    local m=math.min(.04,.12*(n.finish-n.start));local values={}
    local lo,hi=n.start+m,n.finish-m
    if policy~=1 then
      if side<0 then lo=math.max(lo,n.start+.6*(n.finish-n.start)) else hi=math.min(hi,n.start+.4*(n.finish-n.start)) end
    end
    frame_range(data,lo,hi,function(f)if Expression.confident(f)then values[#values+1]=f.pitch end end)
    local center=n.center
    if policy~=1 and #values>0 then
      table.sort(values);local mid=(#values+1)//2;center=#values%2==1 and values[mid] or (values[mid]+values[mid+1])*.5
    end
    if #values<3 then return .6,center end
    for i,p in ipairs(values)do values[i]=math.abs(p-center)end
    table.sort(values);return clamp(values[math.max(1,math.ceil(#values*.8))],.5,1.5),center
  end
  local ba,ca=band(a,-1);local bb,cb=band(b,1);local dep,arr
  -- Similar note centers must not make A's departure jump to B's onset across
  -- a silent gap. Each side owns its half of that gap.
  local gap_mid=(a.finish+b.start)*.5
  frame_range(data,(a.start+a.finish)*.5,gap_mid,function(f,t)if Expression.confident(f) and math.abs(f.pitch-ca)<=ba then dep=t end end)
  frame_range(data,gap_mid,(b.start+b.finish)*.5,function(f,t)if not arr and Expression.confident(f) and math.abs(f.pitch-cb)<=bb then arr=t end end)
  dep,arr=dep or a.finish,arr or b.start;if arr<=dep then arr=dep+hop end
  if data._link_cache_count>=512 then data._link_windows={};data._link_cache_count=0 end
  data._link_windows[key]={dep,arr};data._link_cache_count=data._link_cache_count+1
  return dep,arr
end
function M.window(a,b,data)
  if b.link and b.link.version>=5 then return M.pair_window(a,b,data,b.link.width,b.link.version>=6)end
  if b.link and b.link.version==4 then return M.tilt_window(a,b,data,b.link.width)end
  if b.link and b.link.version>=2 then
    local lo,hi=M.auto(a,b,data,b.link.version==2 and 1 or 2);local l=b.link;local mid=(lo+hi)*.5+l.bias*(hi-lo)*.5;local half=(l.scale or 1)*(hi-lo)*.5
    local left,right=(a.start+a.finish)*.5,(b.start+b.finish)*.5
    lo=clamp(mid-half,left,math.min(right,b.start+(data and data.hop or .016)))
    hi=clamp(mid+half,math.max(left,a.finish-(data and data.hop or .016)),right)
    if hi<=lo then lo=clamp(mid-.0005,left,right-.001);hi=lo+.001 end
    return lo,hi
  end
  local l=b.link;local gap=math.max(0,b.start-a.finish);local mid=(a.finish+b.start)*.5
  local width=math.min(l.width*.5,gap*.5+(a.finish-a.start)*.45,gap*.5+(b.finish-b.start)*.45)
  local bias=l.bias*width
  return math.max(mid-width+bias,a.start+(a.finish-a.start)*.5),math.min(mid+width+bias,b.start+(b.finish-b.start)*.5)
end
function M.initialize(n)
  if not M.active(n) then n.link={version=1,owner=n.id,width=n.transition or .08,bias=n.transition_bias or 0,
    shape=n.transition_shape or 1,mix=n.transition_amount or 0,settle=1,overshoot=0} end
  return n.link
end
function M.edit(a,b,data)
  if M.active(b) and b.link.version==3 then return b.link end
  local old=M.active(b) and b.link or nil;local lo,hi=M.auto(a,b,data)
  b.link={version=3,owner=b.id,scale=old and (old.version>=2 and old.scale or clamp((old.width or .08)/math.max(.001,hi-lo),.25,2)) or 1,
    bias=old and old.bias or b.transition_bias or 0,shape=old and old.shape or b.transition_shape or 1,
    mix=old and old.mix or b.transition_amount or 0,settle=old and old.settle or 1,overshoot=old and old.overshoot or 0}
  return b.link
end
function M.resize(a,b,data,l,side,t,fixed_lo,fixed_hi)
  local alo,ahi=M.auto(a,b,data);local width=math.max(.001,ahi-alo);local sum=alo+ahi
  local left,right=(a.start+a.finish)*.5,(b.start+b.finish)*.5;local hop=data and data.hop or .016
  local lo,hi=fixed_lo,fixed_hi;local lower,upper
  if side=='start' then
    lower=math.max(left,hi-2*width,sum-.75*width-hi)
    upper=math.min(right,b.start+hop,hi-.25*width,sum+.75*width-hi)
    if lower>upper then return end;lo=clamp(t,lower,upper)
  else
    lower=math.max(left,a.finish-hop,lo+.25*width,sum-.75*width-lo)
    upper=math.min(right,lo+2*width,sum+.75*width-lo)
    if lower>upper then return end;hi=clamp(t,lower,upper)
  end
  l.scale=clamp((hi-lo)/width,.25,2);l.bias=clamp((lo+hi-sum)/width,-.75,.75)
  return true
end
function M.voiced_bridge(data,lo,hi)
  local _,_,_,a=Expression.voiced_sample(data,lo+1e-8)
  local _,_,_,b=Expression.voiced_sample(data,hi-1e-8)
  return a~=nil and a==b
end
function M.prepare(a,b,lo,hi,sample,value)
  local pa,pb=sample(lo),sample(hi);if not pa or not pb or hi-lo<1e-7 then return nil end
  local h=hi-lo;local eps=math.min(.001,h*.01)
  local left,right=pa+value(a,lo),pb+value(b,hi)
  local function target(n,t)local raw=sample(t);return (raw or (n.center or 0))+value(n,t)end
  local ma=(target(a,lo+eps)-target(a,lo-eps))/(2*eps)
  local mb=(target(b,hi+eps)-target(b,hi-eps))/(2*eps)
  -- Monotone Hermite core. The joining gate retains the actual note derivative
  -- at each edge even where limiting the core's slopes was necessary.
  local d=(right-left)/h
  if math.abs(d)<1e-9 then ma,mb=0,0 else
    local alpha,beta=math.max(0,ma/d),math.max(0,mb/d)
    local length=math.sqrt(alpha*alpha+beta*beta)
    if length>3 then alpha,beta=alpha*3/length,beta*3/length end
    ma,mb=alpha*d,beta*d
  end
  return {lo=lo,hi=hi,left=left,right=right,ma=ma,mb=mb,raw_left=pa,raw_right=pb}
end
function M.at(c,l,t,raw,base)
  if not c or t<=c.lo or t>=c.hi or not raw then return base end
  local u=(t-c.lo)/(c.hi-c.lo);local x,y=u^l.shape,(1-u)^l.shape;local v=x/(x+y)
  local v2,v3=v*v,v*v*v;local h=c.hi-c.lo
  local target=(2*v3-3*v2+1)*c.left+(v3-2*v2+v)*h*c.ma+(-2*v3+3*v2)*c.right+(v3-v2)*h*c.mb
  local compact=16*u*u*(1-u)*(1-u)
  local residual=raw-(c.raw_left+(c.raw_right-c.raw_left)*u)
  target=target+(1-l.settle)*residual*compact+l.overshoot*compact*math.sin(2*math.pi*u)
  local join=smooth(u/.15)*smooth((1-u)/.15)
  return base+(target-raw-base)*l.mix*join
end
function M.prepare_v2(a,b,lo,hi,data,value)
  local pa,trend_a,ta,slope_a=Expression.trusted(data,lo,-1)
  local pb,trend_b,tb,slope_b=Expression.trusted(data,hi,1)
  if not pa or not pb or hi-lo<1e-7 then return nil end
  local h=hi-lo;local left,right=trend_a+value(a,ta),trend_b+value(b,tb)
  local eps=math.min(.001,h*.01)
  local ma=slope_a+(value(a,ta+eps)-value(a,ta-eps))/(2*eps)
  local mb=slope_b+(value(b,tb+eps)-value(b,tb-eps))/(2*eps)
  local d=(right-left)/h
  if math.abs(d)<1e-9 then ma,mb=0,0 else
    local alpha,beta=math.max(0,ma/d),math.max(0,mb/d);local length=math.sqrt(alpha*alpha+beta*beta)
    if length>3 then alpha,beta=alpha*3/length,beta*3/length end;ma,mb=alpha*d,beta*d
  end
  return {lo=lo,hi=hi,left=left,right=right,ma=ma,mb=mb,raw_left=pa,raw_right=pb,trusted_left=ta,trusted_right=tb}
end
function M.core(c,l,t)
  local u=clamp((t-c.lo)/(c.hi-c.lo),0,1);local x,y=u^l.shape,(1-u)^l.shape;local v=x/(x+y)
  local shaped=v*v*v*(v*(6*v-15)+10);local neutral=u*u*u*(u*(6*u-15)+10)
  -- For shape < 1/3 the power warp followed by a quintic still has an
  -- infinite endpoint derivative. Confine that warp to the interior.
  local g=neutral+(shaped-neutral)*smooth(u/.15)*smooth((1-u)/.15);local h=c.hi-c.lo
  return c.left+(c.right-c.left)*g+h*c.ma*(u*u*u-2*u*u+u)+h*c.mb*(u*u*u-u*u)
end
function M.at_v2(c,l,t,data,base)
  if not c or l.mix==0 or t<=c.lo or t>=c.hi then return base end
  local policy=l.version>=3 and 2 or 1
  local _,support=Expression.support(data,t,policy);if not support or support==0 then return base end
  local raw=policy==2 and Expression.voiced_sample(data,t) or Expression.sample(data,t);if not raw then return base end
  local u=(t-c.lo)/(c.hi-c.lo);local compact=16*u*u*(1-u)*(1-u)
  local residual=raw-(c.raw_left+(c.raw_right-c.raw_left)*u)
  local target=M.core(c,l,t)+(1-l.settle)*residual*compact+l.overshoot*compact*math.sin(2*math.pi*u)
  return base+(target-raw-base)*l.mix*smooth(u/.15)*smooth((1-u)/.15)*support
end

-- Amount/Width controls. Saved v4 uses the regression fit; v5/v6 use the
-- paired tail/onset below. v6 widens reach; new v7 evaluates a continuous
-- acoustic target so modulation between the old sparse anchors is removed.
function M.settings(n)
  if M.active(n) and n.link.version>=4 then return n.link.width,n.link.amount end
  return .08,0
end
function M.edit_tilt(a,b,data)
  if M.active(b) and b.link.version==7 then return b.link end
  local width,amount=M.settings(b)
  b.link={version=7,owner=b.id,width=width,amount=amount,curve_notes={}}
  return b.link
end
function M.tilt_window(a,b,data,width)
  local ta,tb=M.auto(a,b,data)
  ta=clamp(ta,(a.start+a.finish)*.5,a.finish)
  tb=clamp(tb,b.start,(b.start+b.finish)*.5)
  if tb<=ta then local hop=data and data.hop or .016;ta=ta-hop*.5;tb=tb+hop*.5 end
  return math.max(a.start,ta-width),math.min(b.finish,tb+width),ta,tb
end
local function quintic(x)x=clamp(x,0,1);return x*x*x*(x*(6*x-15)+10)end
function M.prepare_tilt(a,b,data,value)
  local lo,hi,ta,tb=M.tilt_window(a,b,data,b.link.width)
  if hi-lo<1e-6 then return nil end
  local radius=b.link.width;local samples={}
  frame_range(data,math.max(a.start,lo-radius),math.min(b.finish,hi+radius),function(f,t)
    if Trace.sample(data,t) then samples[#samples+1]={t=t,p=f.pitch+value(nil,t)}end
  end)
  -- Fit the existing corrected contour locally. Linear regression leaves a
  -- steady slope alone, unlike averaging at an onset. No note-center target,
  -- octave repair or fictional F0 is used. A bend with equal endpoints still
  -- has a correction, which a single endpoint-difference ramp cannot provide.
  local function offset(t)
    local raw=Trace.sample(data,t);if not raw then return nil end
    local w,x,y,xx,xy,count=0,0,0,0,0,0
    for _,p in ipairs(samples)do local dt=p.t-t;local u=dt/radius
      if math.abs(u)<1 then local weight=(1-u*u)^2
        w=w+weight;x=x+weight*dt;y=y+weight*p.p;xx=xx+weight*dt*dt;xy=xy+weight*dt*p.p;count=count+1
      end
    end
    local determinant=w*xx-x*x
    if count<3 or determinant<1e-12 then return nil end
    return (y*xx-x*xy)/determinant-raw-value(nil,t)
  end
  -- A few smooth additive ramps carry the broad bend. Original fine detail
  -- between these anchors remains in the source curve rather than being
  -- replaced by the fitted line. The outer offset and its slope are zero.
  local times={lo,(lo+ta)*.5,ta,(ta+tb)*.5,tb,(tb+hi)*.5,hi}
  table.sort(times);local points={{t=lo,value=0}}
  for _,t in ipairs(times)do if t>lo+1e-7 and t<hi-1e-7 and t>points[#points].t+1e-7 then
    local delta=offset(t);if delta then points[#points+1]={t=t,value=delta}end
  end end
  points[#points+1]={t=hi,value=0}
  if #points<3 then return nil end
  return {lo=lo,hi=hi,ta=ta,tb=tb,points=points}
end
function M.at_tilt(c,l,t,data,base)
  if not c or l.amount==0 or t<=c.lo or t>=c.hi then return base end
  if l.version>=7 and c.continuous then
    local raw,support=Trace.control(data,t);if not raw then return base end
    local u=(t-c.reflo)/(c.refhi-c.reflo)
    local target=c.left+(c.right-c.left)*u
    local join=quintic((t-c.lo)/c.fade)*quintic((c.hi-t)/c.fade)
    return base+(target-raw-c.value(nil,t))*l.amount*join*(support or 0)
  end
  local _,support=Trace.support(data,t);if l.version>=5 then support=Trace.edge_support(data,t)end
  if not support or support==0 then return base end
  for i=2,#c.points do local a,b=c.points[i-1],c.points[i]
    if t<=b.t then local u=quintic((t-a.t)/(b.t-a.t))
      return base+(a.value+(b.value-a.value)*u)*l.amount*support
    end
  end
  return base
end
function M.pair_window(a,b,data,width,wide)
  local sa,fa,ra=Trace.edge_span(data,a.start,a.finish,true)
  local sb,fb,rb=Trace.edge_span(data,b.start,b.finish,false)
  local ta,tb=M.auto(a,b,data)
  local left,right=(a.start+a.finish)*.5,(b.start+b.finish)*.5
  if ra and rb and ra~=rb then
    local mid=(a.finish+b.start)*.5
    ta=math.max(left,math.min(fa-1e-8,mid));tb=math.min(right,math.max(sb,mid))
  else ta=clamp(ta,left,a.finish);tb=clamp(tb,b.start,right)end
  if tb<=ta then local hop=data.hop or .016;ta=ta-hop*.5;tb=tb+hop*.5 end
  if wide then left,right=a.start,b.finish end
  return math.max(left,ta-width,sa or left),math.min(right,tb+width,(fb or right)-1e-8),ta,tb
end
function M.prepare_pair(a,b,data,value)
  local lo,hi,ta,tb=M.pair_window(a,b,data,b.link.width,b.link.version>=6)
  -- Keep the established inner references when reach grows past a midpoint.
  -- A remote onset/tail outlier must not pull the whole transition with it.
  local reflo,refhi=lo,hi
  if b.link.version>=6 then reflo,refhi=M.pair_window(a,b,data,b.link.width)end
  local pa,pb=Trace.sample(data,reflo),Trace.sample(data,refhi)
  if not pa or not pb or hi-lo<1e-6 or refhi-reflo<1e-6 then return end
  pa,pb=pa+value(nil,reflo),pb+value(nil,refhi)
  local _,left_run=Trace.sample(data,reflo);local _,right_run=Trace.sample(data,refhi)
  if b.link.version>=7 and left_run==right_run then
    -- Evaluate the acoustic target against measured F0 at every time. Sparse
    -- offset anchors used by v5/v6 leave between-anchor vibrato in the result.
    return {continuous=true,lo=lo,hi=hi,ta=ta,tb=tb,reflo=reflo,refhi=refhi,left=pa,right=pb,
      fade=math.min((hi-lo)*.2,math.max(.016,b.link.width*.5)),value=value}
  end
  -- Separate voiced runs keep the proven paired tip correction and its short
  -- outer release. A continuous target must not erase a consonant/noise gap.
  local points={{t=lo,value=0}}
  -- Include the measured hop next to each tip. A steep onset can settle in
  -- one frame; spanning it with a single broad ramp creates a new pitch dip.
  local hop=data.hop or .016
  local times={(lo+ta)*.5,ta-hop,ta,(ta+tb)*.5,tb,tb+hop,(tb+hi)*.5};table.sort(times)
  for _,t in ipairs(times)do
    local raw=Trace.sample(data,t)
    if raw and t>points[#points].t+1e-7 and t<hi-1e-7 then
      local target=pa+(pb-pa)*(t-reflo)/(refhi-reflo)
      points[#points+1]={t=t,value=target-raw-value(nil,t)}
    end
  end
  points[#points+1]={t=hi,value=0}
  return {lo=lo,hi=hi,ta=ta,tb=tb,points=points}
end
return M
