-- @noindex
-- Fixed feature contract shared by the offline trainer and the runtime detector.
-- No level-dependent De-ess settings enter this cache.
local import=...;local DSP=import('dsp');local M={version=2,size=55,profile_size=19}
local log,exp=math.log,math.exp
local function step(job,i) if job and i%128==0 then job:checkpoint() end end
function M.build(data,job)
  if data.breath_features and data.breath_features.version==M.version then return data.breath_features end
  local rows,levels,prefix={},{},{[0]=0};local frames=data.frames
  local context={};for k=1,19 do context[k]={[0]=0} end
  local top=math.max(1e-9,data.level_top or .1)
  for i,f in ipairs(frames) do
    local bands=f.noise_bands or {};local sum=0
    for k=1,16 do sum=sum+(bands[k] or 0) end
    local row={};local floor=math.max(1e-20,sum*1e-6)
    for k=1,16 do row[k]=log(math.max(floor,bands[k] or 0)/math.max(1e-20,sum)) end
    row[17]=log(math.max(1e-8,math.min(1,f.breath_flat or f.flat or 0)))
    row[18]=log(math.max(1e-8,math.min(1,f.breath_tonal or 0)))
    row[19]=f.zcr or 0
    row[20]=DSP.clamp(20*log(math.max(1e-9,f.rms or 0)/top)/log(10),-100,30)
    rows[i]=row;levels[i]=row[20];prefix[i]=prefix[i-1]+levels[i]
    for k=1,19 do context[k][i]=context[k][i-1]+row[k] end
    step(job,i)
  end
  local n=#rows;local near=math.max(1,math.floor(.03/data.hop+.5))
  local far=math.max(near+1,math.floor(.25/data.hop+.5))
  local function mean(a,b,fallback)
    a,b=math.max(1,a),math.min(n,b)
    return b>=a and (prefix[b]-prefix[a-1])/(b-a+1) or fallback
  end
  for i,row in ipairs(rows) do
    row[21]=levels[i]-mean(i-near,i+near,levels[i])
    row[22]=mean(i+near,i+far,levels[i])-levels[i]
    row[23]=mean(i-far,i-near,levels[i])-levels[i]
    local a,b=rows[math.max(1,i-2)],rows[math.min(n,i+2)];local motion=0
    for k=1,16 do motion=motion+(b[k]-a[k])^2 end
    row[24]=math.sqrt(motion/16);step(job,i)
  end
  local local_radius=math.max(1,math.floor(.06/data.hop+.5))
  local context_radius=math.max(near+1,math.floor(.35/data.hop+.5))
  for i,row in ipairs(rows) do
    local a,b=math.max(1,i-local_radius),math.min(n,i+local_radius)
    for k=1,19 do row[24+k]=(context[k][b]-context[k][a-1])/(b-a+1) end
    for side=1,2 do
      local x=side==1 and math.max(1,i-context_radius) or i+near
      local y=side==1 and i-near or math.min(n,i+context_radius)
      for k=17,19 do row[49+(side-1)*3+k-16]=y>=x and (context[k][y]-context[k][x-1])/(y-x+1) or row[k] end
    end
    step(job,i)
  end
  -- Sliding extrema stay O(n), including the two-second context window.
  for band,seconds in ipairs({.15,.45,1}) do
    local radius=math.max(1,math.floor(seconds/data.hop+.5));local highs,lows={},{}
    local high_first,high_last,low_first,low_last,added=1,0,1,0,0
    for i,row in ipairs(rows) do
      local right=math.min(n,i+radius)
      for j=added+1,right do
        while high_last>=high_first and levels[highs[high_last]]<=levels[j] do high_last=high_last-1 end
        high_last=high_last+1;highs[high_last]=j
        while low_last>=low_first and levels[lows[low_last]]>=levels[j] do low_last=low_last-1 end
        low_last=low_last+1;lows[low_last]=j
      end
      added=right
      while highs[high_first]<i-radius do high_first=high_first+1 end
      while lows[low_first]<i-radius do low_first=low_first+1 end
      row[42+band*2]=levels[highs[high_first]]-levels[i]
      row[43+band*2]=levels[i]-levels[lows[low_first]]
      step(job,i)
    end
  end
  local result={version=M.version,rows=rows};data.breath_features=result
  return result
end
return M
