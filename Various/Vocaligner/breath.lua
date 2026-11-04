-- @noindex
local import=...;local DSP=import('dsp');local Features=import('breath_features')
local Engine=import('breath_engine');local Model=import('breath_model');local Profile=import('breath_profile')
local Regions=import('breath_regions');local UI=import('config').dynamics_ui
local M={};local clamp=DSP.clamp
-- REAPER Bezier tension signs for the fade into and out of a breath. Both are
-- meant to bow toward full attenuation: drop early, return late. Flip one sign
-- here if REAPER draws that side the other way.
M.tension_in=-1;M.tension_out=1
local function step(job,i) if job and i%128==0 then job:checkpoint() end end
function M.threshold(sensitivity)
  local logit=math.log(Model.threshold/(1-Model.threshold))+(50-(sensitivity or 50))*.05
  return 1/(1+math.exp(-logit))
end
local function classify(data,profile,job,engine)
  local cached=data.breath_adapted
  if cached and cached.profile==profile and cached.revision==(profile and profile.revision or 0) then return cached.scores end
  local features=Features.build(data,job);local base=Engine.scores(data,features,job,engine)
  local raw,scores,veto={},{},{}
  for i,row in ipairs(features.rows) do
    local negative;raw[i],negative=Profile.adjust(row,base[i],profile);veto[i]=(negative or 0)>.55;step(job,i)
  end
  for i=1,#raw do
    local a,b,c=raw[math.max(1,i-1)],raw[i],raw[math.min(#raw,i+1)]
    scores[i]=a+b+c-math.min(a,b,c)-math.max(a,b,c)
    if veto[i] or data.frames[i].rms<1.8e-4 then scores[i]=0 end -- explicit keep-sound examples and near silence
    step(job,i)
  end
  data.breath_adapted={profile=profile,revision=profile and profile.revision or 0,scores=scores,veto=veto}
  return scores
end
local function detect(data,cfg,profile,job,engine)
  local scores=classify(data,profile,job,engine)
  local threshold=M.threshold(cfg.breath_sensitivity);local low=threshold*.60
  local key=string.format('%.9g:%.9g:%.9g:%.9g',threshold,cfg.breath_min_ms or 80,cfg.breath_join_ms or 160,cfg.breath_edge_ms or 120)
  local cache=data.breath_events
  if cache and cache.scores==scores and cache.key==key then return cache.events,scores end
  local events={};local first,last,peak,seed
  local function finish()
    if first and seed then
      local duration=(last-first+1)*data.hop
      if duration>=.02 and duration<=3 then
        events[#events+1]={first=first,last=last,score=peak}
      end
    end
    first,last,peak,seed=nil,nil,nil,nil
  end
  for i,score in ipairs(scores) do
    if data.breath_adapted.veto[i] then finish()
    elseif score>=low then first=first or i;last=i;peak=math.max(peak or 0,score);seed=seed or score>=threshold
    elseif first and i-last>2 then finish() end
    step(job,i)
  end
  finish()
  events=Regions.refine(events,data,data.breath_features.rows,scores,data.breath_adapted.veto,cfg,job,threshold)
  data.breath_events={scores=scores,key=key,events=events}
  return events,scores
end
-- Calibrate only after an explicit positive example. Use the adapted cached
-- scores of its audible frames; negative examples retain their hard veto.
-- A lower-tail sample avoids tuning to one unusually strong frame.
function M.calibrate(data,profile,range,current,job,engine)
  local scores=classify(data,profile,job,engine);local positive={}
  for i,score in ipairs(scores)do
    local t=data.frames[i].t
    if t>=range[1] and t<=range[2] and data.frames[i].rms>=1.8e-4
      and not data.breath_adapted.veto[i] then positive[#positive+1]=score end
    step(job,i)
  end
  if #positive<3 then return current,'The learned range has too few unprotected frames.' end
  table.sort(positive)
  local support=positive[math.max(1,math.ceil(#positive*.35))]
  if support<.05 then return current,'The example conflicts with Keep sound or is too uncertain.' end
  local threshold=clamp(support*.85,.02,.97)
  local logit=math.log(threshold/(1-threshold))
  local sensitivity=50+(math.log(Model.threshold/(1-Model.threshold))-logit)/.05
  return math.floor(clamp(sensitivity,5,95)*10+.5)/10
end
-- Depth of one event. Target level lowers the breath toward the target only;
-- the hidden Max cut replaces Reduction while Target level is forced on.
function M.depth(cfg,e)
  local target=UI.breath_target_only or (cfg.breath_mode or 0)>=.5
  local depth=UI.breath_target_only and UI.breath_max_cut_db or cfg.breath_db or 4
  if target then
    -- Target на максимуме (−12 dBFS) — «ничего не снижать»: кривые обнуляются полностью
    if (cfg.breath_target or -34)>=-12+1e-6 then return 0 end
    depth=math.min(depth,math.max(0,(e.level_db or -120)-(cfg.breath_target or -34)))
  end
  -- ослабление меньше 0.05 дБ неслышно: не рисуем ради него отдельные участки и точки
  if depth<.05 then return 0 end
  return depth
end
-- Quadratic Bezier from (0,0) to (1,1). k>0 rises early, k<0 late, 0 is linear.
-- It models the native Bezier fade for the preview and the following stages.
function M.bend(u,k)
  u=clamp(u,0,1);if math.abs(k)<1e-6 then return u end
  local c=.5-.5*k;local s=(-2*c+math.sqrt(4*c*c+4*k*u))/(2*k)
  return 2*s*(1-s)*(1-c)+s*s
end
-- Границы события с учётом ручной правки (e.a/e.b — тянули края в ручном режиме)
local function span(e) return e.a or e.start,e.b or e.finish end
local function fades(data,cfg,e)
  local a,b=span(e);local duration=b-a
  return math.min(duration/2,math.max(data.hop,(cfg.breath_pre_ms or 10)/1000)),
    math.min(duration/2,math.max(data.hop,(cfg.breath_release_ms or 20)/1000))
end
-- One gain per event and two fades inside it, written as exact points. With
-- isolated events each fade becomes one native Bezier segment (curve.shapes).
local function bezier(data,cfg,events,job)
  local k=clamp((cfg.breath_curve or 50)/100,0,1);local active={}
  for _,e in ipairs(events)do if not e.excluded and e.reduction>0 then active[#active+1]=e end end
  table.sort(active,function(a,b)return (a.a or a.start)<(b.a or b.start) end)
  -- сила фейдов: своя у события (ручная правка fin/fout, 0..1), иначе общая Curve
  local function kin(e) return e.fin or k end
  local function kout(e) return e.fout or k end
  local function at(e,t)
    local fadein,fadeout=fades(data,cfg,e);local a,b=span(e)
    if t<=a or t>=b then return 0 end
    if t<a+fadein then return e.reduction*M.bend((t-a)/fadein,kin(e)) end
    if t>b-fadeout then return e.reduction*(1-M.bend((t-b+fadeout)/fadeout,-kout(e))) end
    return e.reduction
  end
  local times={0,data.len};local shapes={}
  for j,e in ipairs(active)do
    local fadein,fadeout=fades(data,cfg,e);local ea,eb=span(e)
    for side,ramp in ipairs({{ea,fadein},{eb-fadeout,fadeout}})do
      -- точки по кривой Безье: не чаще, чем раз в 15 мс и не больше 8 на фейд (раньше каждые 5 мс — цепочки лишних точек)
      local kk=side==1 and kin(e) or kout(e)
      local n=kk>.01 and math.min(8,math.max(3,math.ceil(ramp[2]/.015))) or 1
      for i=0,n do times[#times+1]=ramp[1]+ramp[2]*i/n end
    end
    local pa=active[j-1] and select(2,span(active[j-1]));local nb=active[j+1] and span(active[j+1])
    local isolated=(not pa or pa<=ea+1e-9) and (not nb or nb>=eb-1e-9)
    if isolated then
      if kin(e)>.01 then shapes[#shapes+1]={a=ea,b=ea+fadein,tension=M.tension_in*kin(e)} end
      if kout(e)>.01 then shapes[#shapes+1]={a=eb-fadeout,b=eb,tension=M.tension_out*kout(e)} end
    end
    step(job,j)
  end
  table.sort(times)
  local points,peak,previous={},0,-1
  for i,t in ipairs(times)do if t>=0 and t<=data.len and t>previous+1e-9 then
    local db=0;for _,e in ipairs(active)do local ea,eb=span(e);if ea<t and eb>t then db=math.max(db,at(e,t)) end end
    points[#points+1]={t=t,db=db};peak=math.max(peak,db);previous=t
    step(job,i)
  end end
  return points,peak,shapes
end
M._bezier=bezier -- для тестов
function M.build(data,cfg,job,exclusions,engine,profile,edits)
  local find_edit=import('cleanup').find_edit
  local templates,scores=detect(data,cfg,profile,job,engine);local events,values={},{}
  for i=1,#data.frames do values[i]=0;step(job,i) end
  for j,e in ipairs(templates) do
    local out={};for k,v in pairs(e) do out[k]=v end;events[j]=out
    out.excluded=false
    for _,excluded in ipairs(exclusions or {}) do
      if excluded.kind=='breath' and excluded.start<e.finish and excluded.finish>e.start then out.excluded=true;break end
    end
    out.kind='breath'
    local depth=M.depth(cfg,e)*(cfg.breath_strength or 100)/100 -- Strength — общая сила всех дыханий
    -- ручная правка этого дыхания (ui2/comp2 ручной режим): сила ×gain, свои края a/b, сила фейдов fin/fout
    local x=not out.excluded and edits and find_edit(edits,'breath',e.start,e.finish)
    if x then
      out.edit=x;depth=depth*(x.gain or 1)
      if x.a then out.a=math.max(0,math.min(x.a,(x.b or e.finish)-.005)) end
      if x.b then out.b=math.min(data.len,math.max(x.b,(x.a or e.start)+.005)) end
      out.fin,out.fout=x.fin,x.fout
    end
    depth=math.min(depth,48)
    out.reduction=out.excluded and 0 or depth
    -- One constant gain per event. Fades stay INSIDE its boundaries: no pre-open
    -- across the previous word and no release tail over the next consonant.
    local fadein,fadeout=fades(data,cfg,e)
    if not out.excluded and depth>0 then
      for i=e.first,e.last do
        local t=data.frames[i].t
        local f=math.min(clamp((t-e.start)/fadein,0,1),clamp((e.finish-t)/fadeout,0,1))
        values[i]=math.max(values[i],depth*(.5-.5*math.cos(math.pi*f)));step(job,i)
      end
    end
  end
  values[1]=0
  local out={sibilants={},sib_score={},sib_db={},breaths=events,breath_score=scores,breath_db=values,
    points={{t=0,db=0}},max_db=0,hop=data.hop,model=Model.version,threshold=M.threshold(cfg.breath_sensitivity)}
  if UI.breath_bezier then
    out.points,out.max_db,out.shapes=bezier(data,cfg,events,job)
    return out
  end
  -- Envelope detail path (sampled raised-cosine fades), kept for rollback.
  for i=2,#data.frames do
    out.points[#out.points+1]={t=data.frames[i].t,db=values[i]};out.max_db=math.max(out.max_db,values[i]);step(job,i)
  end
  out.points[#out.points+1]={t=data.len,db=0};return out
end
return M
