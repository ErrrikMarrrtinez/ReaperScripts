-- @noindex
local import=...;local DSP=import('dsp');local Features=import('breath_features')
local Engine=import('breath_engine');local Model=import('breath_model');local Profile=import('breath_profile')
local Regions=import('breath_regions')
local M={};local clamp=DSP.clamp
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
function M.build(data,cfg,job,exclusions,engine,profile)
  local templates,scores=detect(data,cfg,profile,job,engine);local events,values={},{}
  for i=1,#data.frames do values[i]=0;step(job,i) end
  for j,e in ipairs(templates) do
    local out={};for k,v in pairs(e) do out[k]=v end;events[j]=out
    out.excluded=false
    for _,excluded in ipairs(exclusions or {}) do
      if excluded.kind=='breath' and excluded.start<e.finish and excluded.finish>e.start then out.excluded=true;break end
    end
    local depth=cfg.breath_db or 4
    if (cfg.breath_mode or 0)>=.5 then depth=math.min(depth,math.max(0,e.level_db-(cfg.breath_target or -34))) end
    out.reduction=out.excluded and 0 or depth
    -- One constant gain per event. Fades stay INSIDE its boundaries: no pre-open
    -- across the previous word and no release tail over the next consonant.
    local duration=e.finish-e.start
    local fadein=math.min(duration/2,math.max(data.hop,(cfg.breath_pre_ms or 10)/1000))
    local fadeout=math.min(duration/2,math.max(data.hop,(cfg.breath_release_ms or 20)/1000))
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
  for i=2,#data.frames do
    out.points[#out.points+1]={t=data.frames[i].t,db=values[i]};out.max_db=math.max(out.max_db,values[i]);step(job,i)
  end
  out.points[#out.points+1]={t=data.len,db=0};return out
end
return M
