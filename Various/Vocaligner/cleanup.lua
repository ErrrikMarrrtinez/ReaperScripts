-- @noindex
local import=...;local DSP=import('dsp');local M={}
local clamp=DSP.clamp
local function step(job,i) if job and i%256==0 then job:checkpoint() end end
local function regions(scores,hop,min_seconds,max_seconds,threshold,job)
  local result={};local first,last,peak
  local function finish()
    if first and (last-first+1)*hop>=min_seconds and (not max_seconds or (last-first+1)*hop<=max_seconds) then
      result[#result+1]={first=first,last=last,start=(first-1)*hop,finish=last*hop,score=peak}
    end
    first,last,peak=nil,nil,nil
  end
  for i=1,#scores do
    step(job,i)
    if scores[i]>=threshold then first=first or i;last=i;peak=math.max(peak or 0,scores[i])
    elseif first and i-last>2 then finish() end
  end
  finish();return result
end
local function contains(exclusions,kind,a,b)
  for _,e in ipairs(exclusions or {}) do if e.kind==kind and e.start<b and e.finish>a then return true end end
end
local function mask_regions(events,values,excluded,kind,hop,n,job)
  local mask={};for i=1,n do mask[i]=0;step(job,i) end
  for j,e in ipairs(events) do
    step(job,j)
    e.kind=kind;e.excluded=contains(excluded,kind,e.start,e.finish) or false
    e.reduction=0
    for i=e.first,e.last do
      if not e.excluded then mask[i]=values[i];e.reduction=math.max(e.reduction,values[i]) end
      step(job,i)
    end
  end
  return mask
end
local function soften(values,hop,pre,release,job)
  -- Finite ramps: Release is the time to unity, not an exponential time constant.
  -- Read only the raw curve, so a generated tail cannot start another tail.
  local raw={};for i,v in ipairs(values) do raw[i]=v end
  local before,after=math.ceil(pre/hop),math.ceil(release/hop)
  for i=1,#values do
    local v=raw[i]
    if v>0 then
      for k=1,math.min(after,#raw-i) do values[i+k]=math.max(values[i+k],v*math.max(0,1-k*hop/math.max(hop,release))) end
      for k=1,math.min(before,i-1) do values[i-k]=math.max(values[i-k],v*math.max(0,1-k*hop/math.max(hop,pre))) end
    end
    step(job,i)
  end
end
-- Ручные правки De-ess (d.edits): {kind='sibilant',start,finish — где было найдено событие (для сопоставления после
-- пересчёта), gain — множитель снижения, a/b — свои границы, с; curve={{t,db},...} — нарисованное снижение}.
-- Сопоставление по перекрытию, как у исключений: смена порога/параметров не теряет правку, пока событие на месте.
-- правка достаётся тому событию, с которым перекрывается больше всего (два близких сибилянта не «делят» одну правку)
local function find_edit(edits,kind,a,b)
  local best,bo
  for _,x in ipairs(edits or {}) do
    if x.kind==kind and x.start<b and x.finish>a then
      local o=math.min(b,x.finish)-math.max(a,x.start)
      if not bo or o>bo then best,bo=x,o end
    end
  end
  return best
end
M.find_edit=find_edit
-- до рамп (Pre-open / Release): свои границы и множитель
local function apply_edits(events,mask,edits,kind,hop,n)
  if not edits or #edits==0 then return end
  for _,e in ipairs(events) do
    local x=not e.excluded and find_edit(edits,kind,e.start,e.finish)
    if x then
      e.edit=x
      local a,b=e.first,e.last
      if x.a or x.b then
        local na=x.a and clamp(math.floor(x.a/hop)+1,1,n) or a
        local nb=x.b and clamp(math.floor(x.b/hop+.5),1,n) or b
        if nb<na then nb=na end
        local old={};for i=a,b do old[i]=mask[i];mask[i]=0 end
        -- форма снижения растягивается на новые границы (как при смене rate): та же огибающая, другая длина
        local on=b-a;local nn=nb-na
        for i=na,nb do
          local f=nn>0 and (i-na)/nn or 0;local src=a+f*on;local i0=math.floor(src);local fr=src-i0
          local v0,v1=old[i0] or old[a] or 0,old[i0+1] or old[b] or old[i0] or 0
          mask[i]=math.max(mask[i],v0+(v1-v0)*fr)
        end
        a,b=na,nb
      end
      if x.gain and x.gain~=1 then for i=a,b do mask[i]=math.min(36,mask[i]*x.gain) end end
      -- подъём / наклон (lift_l, lift_r, dB громкости: + — громче): от начала к концу линейно; у границ события
      -- плавно сходит на нет (20% длины), чтобы не поднять сами края
      local ll,lr=x.lift_l or 0,x.lift_r or 0
      if ll~=0 or lr~=0 then
        local m=math.max(1,math.floor((b-a)*.2))
        for i=a,b do
          local f=b>a and (i-a)/(b-a) or .5;local k=math.min(1,(i-a)/m,(b-i)/m);k=k*k*(3-2*k)
          mask[i]=clamp(mask[i]-(ll+(lr-ll)*f)*k,0,36)
        end
      end
    end
  end
end
-- после рамп: нарисованная кривая заменяет снижение на своём отрезке
local function apply_curves(mask,frames,edits,kind,hop,n)
  for _,x in ipairs(edits or {}) do
    local c=x.kind==kind and x.curve
    if c and #c>1 then
      local i0=clamp(math.floor(c[1].t/hop)+1,1,n);local i1=clamp(math.floor(c[#c].t/hop)+1,1,n);local k=1
      for i=i0,i1 do
        local t=frames[i].t
        while k<#c-1 and c[k+1].t<=t do k=k+1 end
        local p,q=c[k],c[k+1];local f=q.t>p.t and clamp((t-p.t)/(q.t-p.t),0,1) or 0
        mask[i]=math.max(0,p.db+(q.db-p.db)*f)
      end
    end
  end
end
-- Cached bands are source-level power, not an audio high-pass filter. The cutoff
-- changes the detector weighting; attenuation is broadband take volume.
function M.features(data,cutoff,job,engine)
  local cached=data.detector_features
  if cached and cached.cutoff==cutoff then return cached end
  local out={cutoff=cutoff,db={},shape={}}
  local power=engine and engine:power(data,cutoff,job)
  local weights={};for b=1,32 do weights[b]=1/(1+(cutoff/((b-.5)*500))^4) end
  for i,f in ipairs(data.frames) do
    local high=power and power[i] or 0
    if not power then for b,e in ipairs(f.noise_bands or {}) do high=high+e*(weights[b] or 0) end end
    local noisy=clamp(((f.noise_flat or f.flat or 0)-.015)/.12,0,1)
    out.db[i]=10*math.log(math.max(1e-15,high),10)
    out.shape[i]=clamp((high/math.max(1e-12,f.rms*f.rms)-.12)/.48,0,1)*noisy
    step(job,i)
  end
  data.detector_features=out
  return out
end
function M.build(data,cfg,job,exclusions,engine,mode,profile,edits)
  if mode=='breath' then return import('breath').build(data,cfg,job,exclusions,engine and engine.breath,profile) end
  local frames=data.frames;local n=#frames;local hop=data.hop
  local sib,sd={},{}
  local features=M.features(data,cfg.deess_hz,job,engine)
  -- RMS детектора (De-ess): мощность ВЧ усредняется окном RMS (по центру кадра) — короткие всплески не
  -- срабатывают, сибилянт определяется по «средней» яркости. 0 — без усреднения (как раньше).
  local fdb=features.db
  local k=math.floor((cfg.deess_rms_ms or 0)/1000/hop+.5)
  if k>=2 then
    local pre={[0]=0};for i=1,n do pre[i]=pre[i-1]+10^((fdb[i] or -150)/10) end
    local h=k//2;local sm={}
    for i=1,n do local a,b=math.max(1,i-h),math.min(n,i-h+k-1);sm[i]=10*math.log(math.max(1e-15,(pre[b]-pre[a-1])/(b-a+1)),10) end
    fdb=sm
  end
  for i=1,n do
    local db,shape=fdb[i],features.shape[i]
    sib[i]=shape*clamp((db-cfg.deess_threshold+6)/12,0,1)
    sd[i]=math.min(cfg.deess_max_db,math.max(0,db-cfg.deess_threshold)*cfg.deess_amount/100*shape)
    if job and i%512==0 then job:checkpoint() end
  end
  local ss=regions(sib,hop,.02,nil,.20,job)
  local sc=mask_regions(ss,sd,exclusions,'sibilant',hop,n,job)
  apply_edits(ss,sc,edits,'sibilant',hop,n)
  soften(sc,hop,cfg.deess_pre_ms/1000,cfg.deess_release_ms/1000,job)
  apply_curves(sc,frames,edits,'sibilant',hop,n)
  -- An excluded candidate remains completely untouched, including release tails
  -- from its neighbours. Its visual region stays available for re-enabling.
  for _,e in ipairs(ss) do if e.excluded then
    for i=e.first,e.last do sc[i]=0;step(job,i) end
  end end
  local out={sibilants=ss,sib_score=sib,sib_db=sc,breaths={},breath_score={},breath_db={},
    points={{t=0,db=0}},max_db=0,hop=hop}
  for i=2,n do
    step(job,i)
    local db=sc[i]
    out.max_db=math.max(out.max_db,db);out.points[#out.points+1]={t=frames[i].t,db=db}
  end
  out.points[#out.points+1]={t=data.len,db=0}
  return out
end
function M.value(cleanup,t)
  if not cleanup or #cleanup.points==0 then return 0 end
  local p=cleanup.points;local lo,hi=1,#p
  if t<=0 or t>=p[hi].t then return 0 end
  while hi-lo>1 do local mid=(lo+hi)//2;if p[mid].t<=t then lo=mid else hi=mid end end
  return p[lo].db+(p[hi].db-p[lo].db)*(t-p[lo].t)/(p[hi].t-p[lo].t)
end
function M.toggle(exclusions,event)
  for i=#exclusions,1,-1 do local e=exclusions[i]
    if e.kind==event.kind and e.start<event.finish and e.finish>event.start then table.remove(exclusions,i);return end
  end
  exclusions[#exclusions+1]={kind=event.kind,start=event.start,finish=event.finish}
end
return M
