-- @noindex
-- Scores are interpretable DSP heuristics, NOT trained/calibrated probabilities.
local M={version=1}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function percentile(v,q)
 if #v==0 then return 0 end
 table.sort(v);return v[math.max(1,math.ceil(#v*q))]
end
function M.features(pcm,engine,job)
 if pcm.click_features and pcm.click_features.version==M.version then return pcm.click_features end
 local out={version=M.version,rows={},hop=math.max(1,math.floor(pcm.sr*.00025+.5))/pcm.sr,len=pcm.len,sr=pcm.sr}
 for index,b in ipairs(pcm.blocks)do
  local values=job:call(engine.run,engine,b.buffer,b.count,pcm.channels,pcm.sr,index==1,index==#pcm.blocks)
  for i=1,#values,8 do
   out.rows[#out.rows+1]={values[i],values[i+1],values[i+2],values[i+3],values[i+4],values[i+5],values[i+6],values[i+7]/pcm.sr}
  end
  job:checkpoint(index/#pcm.blocks,'Analyzing click transients')
 end
 pcm.click_features=out;return out
end
-- Statistics sampled symmetrically outside a guard around the current bin.
-- Use the louder side to protect sustained attacks; percentile resists a lone click.
function M.score(data,mode,skew,protect,job,engine)
 local rows,h=data.rows,data.hop;local result={};local weights={}
 weights[1]=10^(-skew/10);weights[2]=mode=='mouth' and 1.6 or 1;weights[3]=10^(skew/10)
 local span=math.max(4,math.floor((mode=='mouth' and .080 or .030)/h));local guard=math.max(2,math.floor((mode=='mouth' and .025 or .003)/h));local stride=math.max(1,math.floor(.001/h))
 data.contexts=data.contexts or {};local context=data.contexts[mode]
 if not context then
 if engine then context=engine:context(data,mode,job)
 else context={};for i=1,#rows,4 do
  local base={};local left_energy,right_energy=0,0
  for k=1,6 do
   local left,right={},{}
   for d=guard,span,stride do
    if rows[i-d] then left[#left+1]=rows[i-d][k] end
    if rows[i+d] then right[#right+1]=rows[i+d][k] end
   end
   local a,b=percentile(left,.65),percentile(right,.65)
   base[k]=math.max(a,b,1e-7)
   if k==1 then left_energy=a;right_energy=b end
  end
  base[7]=left_energy;base[8]=right_energy
  for j=i,math.min(#rows,i+3)do context[j]=base end
  if (i-1)%128==0 then job:checkpoint() end
 end end
 data.contexts[mode]=context
 end
 for i,f in ipairs(rows)do
  local base=context[i];local left_energy,right_energy=base[7],base[8]
  local sharp=f[3]/base[3];local pred=f[2]/base[2]
  local band=0;local active=0
  for k=1,3 do local ratio=f[k+3]/base[k+3]
   band=math.max(band,ratio*weights[k]);if ratio>2 then active=active+1 end
  end
  -- Agreement between independent views is required; skew alone cannot create a candidate.
  local score=math.sqrt(math.max(sharp,pred)*math.max(1,math.min(band,math.max(sharp,pred)*1.5)))
  local onset=right_energy/(left_energy+1e-7)
  if onset>2 and right_energy>f[1]*.2 then score=score/(1+(onset-2)*protect/100) end
  if mode=='mouth' and active==1 and f[4]>f[5]*2 then score=score*.5 end
  if f[7]<1e-5 or i<=2 or i>=#rows-1 then score=0 end
  result[i]={score=score,sharp=sharp,pred=pred,band=band,base=base[1],onset=onset}
  if i%128==0 then job:checkpoint() end
 end
 -- Repeated comparable pulses on both sides indicate glottal/instrument excitation.
 if protect>0 then
  local lo,hi=math.ceil(.0025/h),math.floor(.016/h)
  local valley=math.max(1,math.floor(.001/h))
  for i,f in ipairs(result)do if f.score>2 and f.sharp>2
   and result[i-valley] and result[i+valley]
   and math.max(result[i-valley].sharp,result[i+valley].sharp)<f.sharp*.6 then
   local repeat_score=0
   for lag=lo,hi do
    local a,b,c,d=result[i-lag],result[i+lag],result[i-lag*2],result[i+lag*2]
    if a and b and c and d then repeat_score=math.max(repeat_score,math.min(a.sharp,b.sharp,c.sharp,d.sharp)/math.max(1,f.sharp)) end
   end
   f.score=f.score/(1+clamp(repeat_score,0,1)*protect/25)
  end;if i%256==0 then job:checkpoint() end end
 end
 return result
end
-- ===== Mouth: короткий локальный контраст (2026-10) =====
-- Прежний Mouth требовал подтверждения спектральной новизной (FFT 1024, окно 23 мс): щелчки внутри голоса
-- в таком окне тонут, а шипящие (ровный ВЧ-шум 30+ мс) давали ложные срабатывания. Здесь щелчок — узкий
-- всплеск ВЧ-энергии и остатка предсказания относительно медианы соседей ±0.75..6 мс; шипящие ровные и
-- отношения ~1 не дают. Близкие всплески (≤3 мс) склеиваются в одно событие (серии, «бульки»), границы
-- тянутся по затухающему хвосту (до 8 мс), чтобы не оставалось слышимого остатка.
-- Защита (Protect attacks): периодические импульсы голоса (L и 2L по обе стороны, у края голоса — с одной) и атака слова,
-- когда голос начинается сразу (≤4 мс) за всплеском. Щелчок губ, отделённый от голоса паузой, не защищается.
M.mouth_method='transient' -- 'transient' | 'spectral' (прежний путь через click/spectral.lua)
local G,SPAN,MERGE,LEFT,TAIL=3,24,12,6,32 -- в кадрах по 0.25 мс
local function percentile_sample(rows,k,q)
 local v={};for i=1,#rows,8 do v[#v+1]=rows[i][k] end
 table.sort(v);return v[math.max(1,math.ceil(#v*q))] or 0
end
local function median(rows,k,a,b)
 local v={};for i=math.max(1,a),math.min(#rows,b) do v[#v+1]=rows[i][k] end
 if #v==0 then return 0 end
 table.sort(v);local n=#v
 return n%2==1 and v[(n+1)//2] or .5*(v[n//2]+v[n//2+1])
end
function M.mouth_events(data,cfg,exclusions,job,engine)
 local rows=data.rows;local n=#rows;local h=data.hop
 local tr=data.transient
 if not tr then
  local fh=math.max(percentile_sample(rows,6,.2),10^(-90/20));local fr=math.max(percentile_sample(rows,2,.2),10^(-90/20))
  local rh,rp=engine:transient(data,G,SPAN,fh,fr,job);tr={rh=rh,rp=rp};data.transient=tr
 end
 local skew=cfg.mouth_skew or 0;local wh=clamp(.5+skew/20,0,1)
 local protect=cfg.mouth_protect or 0;local T=12*2^(-(cfg.mouth_sensitivity or 50)/30)
 local score={}
 for i=1,n do score[i]=math.max(tr.rh[i],1e-9)^wh*math.max(tr.rp[i],1e-9)^(1-wh) end
 local function at(k) if k<1 or k>n then return 0 end;return math.max(score[math.max(1,k-1)],score[k],score[math.min(n,k+1)]) end
 local events={};local i=1
 while i<=n do
  if score[i]<T then i=i+1
  else
   local a,b,j=i,i,i
   while j<=n do
    if score[j]>=T then b=j;j=j+1 elseif j-b<=MERGE then j=j+1 else break end
   end
   local peak=a;for k=a,b do if score[k]>score[peak] then peak=k end end
   local s0,s1=a,b
   while s0>1 and a-s0<LEFT and score[s0-1]>1.4 do s0=s0-1 end
   while s1<n and s1-b<TAIL and score[s1+1]>1.4 do s1=s1+1 end
   local why
   if (b-a+1)*h>.025 then why='long' end
   if not why and protect>0 then
    local rep=0
    -- повтор с тем же шагом по обе стороны (L и 2L); если с одной стороны тишина (край голоса) — достаточно другой
    local el,er=median(rows,1,peak-100,peak-4),median(rows,1,peak+4,peak+100)
    local quiet_l,quiet_r=el<.15*er,er<.15*el
    for lag=10,50 do
     local l,r=math.min(at(peak-lag),at(peak-2*lag)),math.min(at(peak+lag),at(peak+2*lag))
     rep=math.max(rep,math.min(l,r),quiet_r and l or 0,quiet_l and r or 0)
    end
    if rep>=math.max(.5*(1-protect/200)*score[peak],.7*T) and score[peak]<3*T then why='periodic' end
   end
   if not why and protect>=50 then
    local before=median(rows,1,a-120,a-8);local after=median(rows,1,b+4,b+120)
    local lo_after=median(rows,4,b+4,b+160);local voiced=b+1
    while voiced<math.min(n,b+160) and rows[voiced][4]<.5*lo_after do voiced=voiced+1 end
    if after>8*(before+1e-6) and before<.004 and voiced-b<=16 then why='attack' end
   end
   if not why then
    local f=rows[peak]
    local e={kind='mouth',start=(s0-1)*h,finish=math.min(data.len,s1*h),peak=f[8],score=score[peak],
     level_db=20*math.log(math.max(f[1],1e-12),10),contrast=score[peak]}
    for _,x in ipairs(exclusions or {})do if x.kind=='mouth' and x.finish>e.start and x.start<e.finish then e.excluded=true end end
    events[#events+1]=e
   end
   i=j
  end
  if i%2048==0 then job:checkpoint() end
 end
 return events
end
function M.events(data,scores,cfg,mode,exclusions,job)
 local h=data.hop;local threshold=14*2^(-cfg[mode..'_sensitivity']/35)
 local tail=math.max(1.6,threshold*.32);local events={};local i=1
 local gap=math.max(1,math.floor((mode=='mouth' and .002 or .0005)/h))
 while i<=#scores do
  if scores[i].score>=threshold then
   local a,b=i,i;local peak=i
   local function supported(index)
    local f=scores[index]
    return f and (f.score>=tail or mode=='mouth' and f.band>=tail*1.5 and f.pred>=1.5 and f.onset<4)
   end
   while a>1 and supported(a-1) do a=a-1 end
   local scan,miss=b+1,0
   while scan<=#scores and miss<gap do
    if supported(scan) then b=scan;miss=0;if scores[b].score>scores[peak].score then peak=b end
    else miss=miss+1 end
    scan=scan+1
   end
   local duration=(b-a+1)*h
   if duration<=(mode=='mouth' and .050 or .020) then
    local start,finish=(a-1)*h,math.min(data.len,b*h)
    local f=data.rows[peak];local e={kind=mode,start=start,finish=finish,peak=f[8],score=scores[peak].score,
     level_db=20*math.log(math.max(f[1],1e-12),10),contrast=f[1]/math.max(scores[peak].base,1e-7)}
    for _,x in ipairs(exclusions or {})do if x.kind==mode and x.finish>start and x.start<finish then e.excluded=true end end
    local old=events[#events]
    if old and old.finish>=e.start and old.excluded==e.excluded then
     old.finish=math.max(old.finish,e.finish);old.score=math.max(old.score,e.score);old.contrast=math.max(old.contrast,e.contrast)
    else events[#events+1]=e end
   end
   i=b+1
  else i=i+1 end
  if i%256==0 then job:checkpoint() end
 end
 return events
end
return M
