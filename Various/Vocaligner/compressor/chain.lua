-- @noindex
local import=...;local Settings=import('compressor/settings');local Curves=import('compressor/curves')
local Config=import('config');local Cleanup=import('cleanup');local PCM=import('compressor/audio');local M={}
local function recipes(old,cfg,range)
 local out={}
 for _,r in ipairs(old and old.recipes or {})do
  if r.a<range[1] then out[#out+1]={a=r.a,b=math.min(r.b,range[1]),cfg=r.cfg} end
  if r.b>range[2] then out[#out+1]={a=math.max(r.a,range[2]),b=r.b,cfg=r.cfg} end
 end
 out[#out+1]={a=range[1],b=range[2],cfg=Config.copy(cfg)}
 return out
end
local function fingerprint(curve,job)
 local parts={}
 for i,p in ipairs(curve and curve.points or {})do
  parts[i]=string.pack('<dd',p.t,p.db);if i%512==0 then job:checkpoint() end
 end
 return table.concat(parts)
end
local function stage_key(layer,kind,upstream,d,gain,job)
 local upstream_key=fingerprint(upstream,job)
 local parts={string.pack('<I4I4d',#upstream_key,#layer.recipes,gain or 1),upstream_key}
 for _,r in ipairs(layer.recipes)do
  parts[#parts+1]=string.pack('<dd',r.a,r.b)
  for _,key in ipairs(Config[kind..'_keys'])do parts[#parts+1]=string.pack('<d',r.cfg[key]) end
 end
 -- Exclusions are edited in place; table identity alone cannot validate them.
 for _,e in ipairs(d.exclusions or {})do if e.kind==kind then parts[#parts+1]=string.pack('<dd',e.start,e.finish) end end
 return table.concat(parts)
end
local function features(d,kind,data,upstream,job)
 if not upstream or upstream.max_db<1e-9 then return data end
 local key=fingerprint(upstream,job);d.chain_inputs=d.chain_inputs or {};local cached=d.chain_inputs[kind]
 if cached and cached.data==data and cached.key==key then return cached.audio end
 local out=Config.copy(data);out.frames={};out.detector_blocks=nil;out.detector_features=nil
 out.breath_features=nil;out.breath_model_scores=nil;out.breath_adapted=nil;out.breath_events=nil
 for i,f in ipairs(data.frames) do
  local gain=10^(-Curves.value(upstream,f.t)/20);local n=Config.copy(f)
  n.rms=(f.rms or 0)*gain;n.min=(f.min or 0)*gain;n.max=(f.max or 0)*gain
  n.noise_bands={};for b,v in ipairs(f.noise_bands or {})do n.noise_bands[b]=v*gain*gain end
  out.frames[i]=n;if job and i%256==0 then job:checkpoint() end
 end
 out=import('dsp').normalize(out,{cleanup_only=true},job)
 d.chain_inputs[kind]={data=data,key=key,audio=out};return out
end
function M.dynamic(c,d,cfg,mode,upstream,job)
 local pcm=PCM.ensure(c,d,job);local engine=c.app.engine.dynamics
 local out={points={},max_db=0,hop=cfg[mode..'_interval_ms']/1000,levels={}}
 local s=d.snapshot;local run_cfg=Config.copy(cfg)
 run_cfg.input_gain=job:call(function()return math.abs(c.r.GetMediaItemInfo_Value(s.item,'D_VOL')*c.r.GetMediaItemTakeInfo_Value(s.take,'D_VOL'))end)
 local run_mode=mode
 if mode=='gate' then
  -- Cache the filtered RMS on the finest envelope grid. Threshold, hold,
  -- hysteresis and fades then run in a separate tiny EEL pass.
  run_mode='compressor';run_cfg.compressor_rms_ms=cfg.gate_rms_ms
  run_cfg.compressor_hp=cfg.gate_hp;run_cfg.compressor_lp=cfg.gate_lp
  run_cfg.compressor_attack_ms=0;run_cfg.compressor_release_ms=0;run_cfg.compressor_interval_ms=.5
  run_cfg.compressor_ratio=1;run_cfg.compressor_gain=0;run_cfg.compressor_knee=0
 end
 local follower_key={pcm.key,tostring(run_cfg.input_gain)}
 local keys=mode=='gate' and {'rms_ms','hp','lp'} or {'rms_ms','attack_ms','release_ms','hp','lp','interval_ms'}
 for _,key in ipairs(keys)do follower_key[#follower_key+1]=tostring(cfg[mode..'_'..key]) end
 -- Use the complete upstream curve. Threshold/gain-only edits reuse the follower,
 -- but an earlier stage's timing or level change must invalidate it.
 local fingerprint={}
 for i,p in ipairs(upstream and upstream.points or {})do
  fingerprint[i]=string.pack('<dd',p.t,p.db);if i%512==0 then job:checkpoint() end
 end
 follower_key[#follower_key+1]=table.concat(fingerprint);follower_key=table.concat(follower_key,'|')
 local cache_name=mode..'_follower';local cached=d[cache_name]
 if cached and cached.key==follower_key then
  out.levels=cached.levels
  if mode=='compressor' then out.points=engine:transfer(out.levels,cfg,job)end
  d.follower_reuses=(d.follower_reuses or 0)+1
 else
 local step=math.max(1,math.floor(pcm.sr*.0005))
 for index,block in ipairs(pcm.blocks)do
  local up={};for i=0,math.ceil(block.count/step)+1 do up[#up+1]=10^(-Curves.value(upstream,(block.first+i*step)/pcm.sr)/20) end
  local values=job:call(engine.run,engine,block.buffer,block.count,pcm.channels,pcm.sr,run_cfg,run_mode,up,step,index==1)
  for j=1,#values,6 do
   out.points[#out.points+1]={t=values[j],db=values[j+1]}
   out.levels[#out.levels+1]={t=values[j],db=values[j+2]}
  end
  job:checkpoint(nil,'Processing '..Settings.labels[mode]..' · '..s.name)
 end
 d[cache_name]={key=follower_key,levels=out.levels}
 end
 if mode=='gate' then out.points=engine:gate(out.levels,cfg,job)end
 -- Legacy pre-comp advances the emitted curve, including its release. Keep that
 -- audible convention so settings transfer predictably; always bound to the item.
 local pre=cfg[mode..'_pre_ms']/1000
 local raw={points=out.points};local shifted={}
 if pre>0 then
  shifted[1]={t=0,db=Curves.value(raw,pre)}
  for _,p in ipairs(out.points)do if p.t>pre then shifted[#shifted+1]={t=p.t-pre,db=p.db} end end
  out.points=shifted
 end
 out.points[#out.points+1]={t=d.audio.len,db=out.points[#out.points] and out.points[#out.points].db or 0}
 for _,p in ipairs(out.points)do out.max_db=math.max(out.max_db,math.abs(p.db)) end
 return out
end
function M.build(c,d,cfg,mode,range,job,remove)
 local layers=Config.copy(d.layers or {});local original=layers[mode]
 if remove then layers[mode]=nil
 else layers[mode]={recipes=recipes(original,cfg,range),frozen=original and original.frozen or original and not original.recipes and original or nil} end
 local resolved,stage_cache={},{};local detected={sibilants={},breaths={}};local current,hf
 for _,kind in ipairs(Settings.parse(cfg.chain_order)) do
  local layer=layers[kind]
  if layer then
   local upstream=Curves.sum(d.audio,resolved,job)
   if layer.recipes then
    local gain
    if Settings.dynamic(kind) then gain=job:call(function()
     return math.abs(c.r.GetMediaItemInfo_Value(d.snapshot.item,'D_VOL')*c.r.GetMediaItemTakeInfo_Value(d.snapshot.take,'D_VOL'))
    end) end
    local key=stage_key(layer,kind,upstream,d,gain,job)
    local profile=kind=='breath' and d.breath_profile or nil
    local revision=profile and profile.revision or 0
    local cached=d.stage_cache and d.stage_cache[kind]
    if cached and cached.audio==d.audio and cached.key==key and cached.frozen==layer.frozen
      and cached.profile==profile and cached.revision==revision then
     stage_cache[kind]=cached;resolved[kind]=cached.layer
     if kind==mode then detected=cached.current;current=cached.current;hf=cached.hf end
     d.stage_reuses=(d.stage_reuses or 0)+1
     goto next_stage
    end
    local curve=layer.frozen;local detail=0
    local stage_current,stage_hf,stage_input
    for _,r in ipairs(layer.recipes)do
     local candidate
     if Settings.dynamic(kind) then candidate=M.dynamic(c,d,r.cfg,kind,upstream,job)
     else
      assert(not d.audio.dynamics_only,'Spectral analysis is required for De-ess / Breaths')
      local input=features(d,kind,d.audio,upstream,job)
      stage_input=input
      candidate=Cleanup.build(input,r.cfg,job,d.exclusions,c.app.engine,kind,d.breath_profile)
      if kind=='deess' then stage_hf=input.detector_features end
     end
     stage_current=candidate
     if kind==mode then detected=candidate;current=candidate;hf=stage_hf end
     curve=Curves.patch(d.audio,curve,candidate,{r.a,r.b},job)
     detail=math.max(detail,r.cfg[kind..'_detail'] or 85)
    end
    curve=curve or {points={},max_db=0,hop=d.audio.hop}
    curve.recipes=layer.recipes;curve.frozen=layer.frozen;curve.detail=detail;layer=curve
    stage_cache[kind]={audio=d.audio,key=key,frozen=curve.frozen,profile=profile,revision=revision,
     layer=curve,current=stage_current,hf=stage_hf,input=stage_input}
   end
   resolved[kind]=layer
  end
  ::next_stage::
 end
 d.stage_cache=stage_cache
 local combined=Curves.sum(d.audio,resolved,job);combined.force_envelope=next(resolved)~=nil;combined.chain_active=cfg.chain_active;combined.chain_visible=cfg.chain_visible
 local changed=Curves.changed(d.audio,d.applied_cleanup and d.applied_cleanup.points and d.applied_cleanup or import('curves').combine(d.audio,d.layers or {},job),combined,job)
 -- Even a unity stage has a recipe; keep it so later upstream edits can activate it.
 changed=changed or (original~=nil)~=(resolved[mode]~=nil) or cfg.chain_order~=(d.applied_cfg or {}).chain_order
 if original and original.recipes and not remove then
  local found=false
  for _,recipe in ipairs(original.recipes)do
   if math.abs(recipe.a-range[1])<1e-8 and math.abs(recipe.b-range[2])<1e-8 then
    found=true;for _,key in ipairs(Config[mode..'_keys'] or {})do if recipe.cfg[key]~=cfg[key] then changed=true end end
   end
  end
  if not found then changed=true end
 end
 if d.applied_cfg then changed=changed or cfg.chain_active~=d.applied_cfg.chain_active or cfg.chain_visible~=d.applied_cfg.chain_visible end
 return {detected=detected,layers=resolved,combined=combined,curve=resolved[mode],regions=import('curves').regions(resolved[mode],job),
  changed=changed,peak=resolved[mode] and resolved[mode].max_db or 0,cfg=cfg,levels=current and current.levels,hf_features=hf}
end
return M
