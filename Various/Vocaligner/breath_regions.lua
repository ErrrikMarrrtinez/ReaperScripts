-- @noindex
local import=...;local Model=import('breath_model');local DSP=import('dsp');local M={}
local function step(job,i) if job and i%64==0 then job:checkpoint() end end
local function distance(a,b)
  local sum=0
  -- Ignore the lowest band: room hum must not dominate breath shape matching.
  for k=2,16 do sum=sum+math.min(16,((a[k]-b[k])/math.max(.5,Model.scale[k]))^2) end
  return sum/15
end
local function describe(e,data,rows)
  local mean,levels,tonal={},{},{}
  for k=1,19 do mean[k]=0 end
  for i=e.first,e.last do
    for k=1,19 do mean[k]=mean[k]+rows[i][k] end
    levels[#levels+1]=data.frames[i].rms;tonal[#tonal+1]=math.exp(rows[i][18])
  end
  for k=1,19 do mean[k]=mean[k]/(e.last-e.first+1) end
  e.shape=mean;e.rms=DSP.percentile(levels,.8);e.tonal=DSP.percentile(tonal,.5)
end
local function compatible(i,e,data,rows,veto)
  if veto[i] then return false end
  local f,row=data.frames[i],rows[i]
  if f.rms<math.max(1.8e-4,e.rms*.10) or f.rms>e.rms*2.8 then return false end
  -- A new voiced sound or a sharp spectral change is a boundary, even if two
  -- nearby candidates would otherwise fit inside the gap length limit.
  if math.exp(row[18])>math.max(.28,e.tonal*2.2) and math.exp(row[1])>.65 and row[19]<.08 then return false end
  return distance(row,e.shape)<1.5
end
function M.refine(candidates,data,rows,scores,veto,cfg,job,threshold)
  local join=math.floor((cfg.breath_join_ms or 160)/1000/data.hop+.5)
  local edge=math.floor((cfg.breath_edge_ms or 120)/1000/data.hop+.5)
  local edge_score=math.max(.03,(threshold or .55)*.18)
  local merged={}
  for j,e in ipairs(candidates) do
    e.core_frames=e.last-e.first+1
    describe(e,data,rows)
    local previous=merged[#merged];local link=previous and e.first-previous.last-1<=join
      and (e.last-previous.first+1)*data.hop<=3 and distance(previous.shape,e.shape)<1.2
    if link then
      for i=previous.last+1,e.first-1 do
        if not compatible(i,previous,data,rows,veto) and not compatible(i,e,data,rows,veto) then link=false;break end
      end
    end
    if link then
      previous.last=e.last;previous.score=math.max(previous.score,e.score);previous.parts=(previous.parts or 1)+1
      previous.core_frames=previous.core_frames+e.core_frames
      describe(previous,data,rows)
    else merged[#merged+1]=e end
    step(job,j)
  end
  -- Refine independently inside limits bounded by adjacent candidates. Expansion
  -- reads the ORIGINAL acoustic description; it cannot feed itself and run away.
  local out={}
  for j,e in ipairs(merged) do
    local first,last=e.first,e.last;e.core_start=data.frames[first].t;e.core_finish=math.min(data.len,data.frames[last].t+data.hop)
    -- A weak candidate dominated by low tonal energy may be the fading end of
    -- a word. Keep its model boundary instead of growing it deeper into speech.
    local grow=e.score<.65 and e.tonal>.28 and math.exp(e.shape[1])>.85 and e.shape[19]<.05 and 0 or edge
    local a=math.max(1,first-grow,merged[j-1] and merged[j-1].last+1 or 1)
    local b=math.min(#rows,last+grow,merged[j+1] and merged[j+1].first-1 or #rows)
    for i=first-1,a,-1 do
      if scores[i]<edge_score or not compatible(i,e,data,rows,veto) then break end;e.first=i
    end
    for i=last+1,b do
      if scores[i]<edge_score or not compatible(i,e,data,rows,veto) then break end;e.last=i
    end
    local supported=e.core_frames+(first-e.first)+(e.last-last)
    if supported*data.hop+1e-9>=(cfg.breath_min_ms or 80)/1000 then
      e.start=data.frames[e.first].t;e.finish=math.min(data.len,data.frames[e.last].t+data.hop)
      local levels={};for i=e.first,e.last do levels[#levels+1]=data.frames[i].rms end
      e.level_db=20*math.log(math.max(1e-9,DSP.percentile(levels,.8)),10)
      e.kind='breath';e.shape=nil;e.rms=nil;e.tonal=nil;out[#out+1]=e
    end
    step(job,j)
  end
  return out
end
return M
