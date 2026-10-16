-- @noindex
local import=...;local DSP=import('dsp');local Regions=import('cleanup_ui');local Navigator=import('navigator')
local Controls=import('controls');local Progress=import('progress');local Transport=import('transport');local M={}
local function canvas(im,ctx,c,w,h,color,wave)
  local d=c:current();local x,y=im.GetCursorScreenPos(ctx);local draw=im.GetWindowDrawList(ctx)
  local font=im.GetFontSize(ctx)
  im.InvisibleButton(ctx,'##cleanup_wave',w,h,im.ButtonFlags_MouseButtonLeft|im.ButtonFlags_MouseButtonRight|im.ButtonFlags_MouseButtonMiddle)
  local hovered=im.IsItemHovered(ctx)
  im.DrawList_AddRectFilled(draw,x,y,x+w,y+h,color.bg,6)
  if not d then return end
  local data=d.audio or d.quick
  if not data then im.DrawList_AddText(draw,x+10,y+8,color.muted,'Unprocessed');return end
  d.view=d.view or {start=data.pos,span=data.len}
  local v=d.view;local mx,my=im.GetMousePos(ctx);local top=y+font*1.8
  local function time(px) return DSP.clamp(v.start+v.span*(px-x)/w-data.pos,0,data.len) end
  if hovered then
    local wheel=im.GetMouseWheel(ctx)
    if wheel~=0 then
      local f=DSP.clamp((mx-x)/w,0,1);local span=DSP.clamp(v.span*1.2^(-wheel),math.min(.15,data.len),data.len)
      v.start=v.start+f*(v.span-span);v.span=span
    end
    if im.IsMouseClicked(ctx,0) then
      d.drag_start=time(mx);d.drag_ruler=my<top;d.drag_moved=false;d.click_seek=im.GetKeyMods(ctx)&im.Mod_Shift==0
    end
    if im.IsMouseDoubleClicked(ctx,0) then v.start=data.pos;v.span=data.len;d.click_seek=false end
  end
  if im.IsItemActive(ctx) then
    c.gesture=true
    if im.IsMouseDragging(ctx,2,2) or (im.GetKeyMods(ctx)&im.Mod_Shift~=0 and im.IsMouseDragging(ctx,0,2)) then
      local dx=im.GetMouseDelta(ctx);v.start=v.start-dx*v.span/w;d.drag_start=nil;d.click_seek=false
    elseif d.drag_start and im.IsMouseDragging(ctx,0,3) then
      d.drag_moved=true
      if d.drag_ruler then c:set_range(d.drag_start,time(mx),true)
      else local dx=im.GetMouseDelta(ctx);v.start=v.start-dx*v.span/w;d.click_seek=false end
    end
  end
  v.start=DSP.clamp(v.start,data.pos,data.pos+data.len-v.span)
  if im.IsMouseReleased(ctx,0) and d.drag_start then
    if d.drag_moved and d.drag_ruler then c:control_released()
    elseif hovered and d.click_seek then c:seek(time(mx)) end
  end
  if not im.IsMouseDown(ctx,0) then d.drag_start=nil;d.click_seek=nil end
  local transport=Transport.read(c.r,c.project)
  Transport.follow(d,c.r,transport,v,0,data.pos,data.pos+data.len,im.IsItemActive(ctx) or d.overview_grab~=nil or hovered and im.GetMouseWheel(ctx)~=0)
  local function xpos(t) return x+(data.pos+t-v.start)/v.span*w end
  im.DrawList_PushClipRect(draw,x,y,x+w,y+h,true)
  local height=h-font*2.2
  local step=10^math.floor(math.log(v.span/7,10))
  if v.span/step>14 then step=step*5 elseif v.span/step>8 then step=step*2 end
  for t=math.ceil(v.start/step)*step,v.start+v.span,step do
    local xx=x+(t-v.start)/v.span*w
    im.DrawList_AddLine(draw,xx,y+24,xx,y+h,0xFFFFFF0B)
    im.DrawList_AddText(draw,xx+3,y+4,color.muted,string.format(step<1 and '%.2fs' or '%.1fs',t))
  end
  local events=d.detected and (c.mode=='breath' and d.detected.breaths or d.detected.sibilants or {}) or {}
  wave(im,ctx,draw,data,nil,x,top,w,height,v,0xA0AABA30)
  wave(im,ctx,draw,data,nil,x,top,w,height,v,0xA3AFBFD0,d.preview,{events=events,tint=0xEBC080FF})
  if not (d.processed_modes and d.processed_modes[c.mode]) and not (d.layers and d.layers[c.mode]) then
    local label='Unprocessed';local tw=im.CalcTextSize(ctx,label)
    im.DrawList_AddText(draw,x+w-tw-8,y+26,color.muted,label)
  end
  Regions.draw(im,ctx,draw,c,d,x,top,w,height)
  if d.selected then
    local a,b=xpos(d.range[1]),xpos(d.range[2])
    if a>x then im.DrawList_AddRectFilled(draw,x,y+25,math.min(x+w,a),y+h,0x171A2090) end
    if b<x+w then im.DrawList_AddRectFilled(draw,math.max(x,b),y+25,x+w,y+h,0x171A2090) end
    for _,xx in ipairs({a,b}) do im.DrawList_AddLine(draw,xx,y+25,xx,y+h,color.after,1) end
  end
  Transport.draw(im,draw,transport,function(t)return x+(t-v.start)/v.span*w end,x,x+w,y+24,y+h)
  im.DrawList_PopClipRect(draw)
end
local deess_knobs={
  {'deess_threshold','Threshold',-60,-6,'%.1f dBFS','Threshold in high-frequency detector power, shown in the graph below.'},
  {'deess_hz','Detector frequency',2000,14000,'%.0f Hz','Weights cached frequency bands. Does not EQ the audio.'},
  {'deess_amount','Reduction',0,100,'%.0f%%','Depth of reduction above the threshold, not the number of envelope points.'},
  {'deess_max_db','Max cut',0,18,'-%.1f dB','Maximum attenuation. For example, -9 dB limits the deepest dip to 9 dB.'},
  {'deess_pre_ms','Pre-open',0,30,'%.0f ms','Ramp before the detected sound. Zero adds no pre-open.'},
  {'deess_release_ms','Release',0,200,'%.0f ms','Time to return to original volume after the last detector frame. Analysis resolution: 10 ms.'},
  {'deess_detail','Envelope detail',0,100,'%.0f%%','More points / finer curve detail. Lower values keep the shape with fewer points.'},
}
local breath_knobs={
  {'breath_sensitivity','Sensitivity',0,100,'%.0f%%','Threshold of the trained breath detector. Higher catches more sounds. Learn a breath or keep-sound example to adapt this take.'},
  {'breath_db','Reduction',0,18,'-%.1f dB','Fixed attenuation per breath. Does not change which sounds are detected.'},
  {'breath_min_ms','Minimum duration',40,500,'%.0f ms','Ignore shorter breath candidates.'},
  {'breath_pre_ms','Fade in',0,100,'%.0f ms','Fade into attenuation inside the breath. Does not cut the previous word. Minimum one analysis step (10 ms).'},
  {'breath_release_ms','Fade out',0,300,'%.0f ms','Return to original level inside the breath, before the next word. Minimum one analysis step (10 ms).'},
  {'breath_detail','Envelope detail',0,100,'%.0f%%','More points / finer volume envelope.'},
  {'breath_join_ms','Join gaps',0,300,'%.0f ms','Join fragments only when the gap has compatible spectrum and level. Keeps one gain across the breath.'},
  {'breath_edge_ms','Find edges',0,250,'%.0f ms','Maximum boundary search around a detected breath. Stops at silence, protected sounds and sharp spectral or level changes.'},
}
local function breath_controls(im,ctx,c,d)
  local changed,target=im.Checkbox(ctx,'Target level',(c.cfg.breath_mode or 0)>=.5)
  if changed then c.cfg.breath_mode=target and 1 or 0;c:settings_changed('breath_mode');c:control_released() end
  if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Lower each detected breath toward one RMS target, limited by Max cut. Already quieter breaths stay unchanged.') end
  local entries={};for i,e in ipairs(breath_knobs) do entries[i]=e end
  if (c.cfg.breath_mode or 0)>=.5 then
    entries[2]={'breath_target','Target',-60,-12,'%.1f dBFS','80th-percentile source RMS per breath. One gain for the whole breath; existing take volume and FX are not included.'}
    table.insert(entries,3,{'breath_db','Max cut',0,18,'-%.1f dB','Limit how much Target level can reduce a breath. It never boosts audio.'})
  end
  Controls.grid(im,ctx,c,'##breath_controls',entries,3)
  local length=d and d.range[2]-d.range[1] or 0
  im.BeginDisabled(ctx,not d or not d.audio or not d.selected or length<.04 or length>2)
  if im.Button(ctx,'Learn breath') then c:learn_breath(1) end
    if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Select one clear breath on the time ruler (40 ms to 2 s). Learn its sound for this take. Escape clears the processing selection; Get then updates the whole item.') end
  im.SameLine(ctx)
  if im.Button(ctx,'Keep sound') then c:learn_breath(-1) end
  if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Learn a selected consonant or noise that should not be treated as a breath. Applies to similar sounds in this take.') end
  im.EndDisabled(ctx);im.SameLine(ctx)
  Controls.disabled(im,ctx,c.job~=nil or c.pending~=nil or not d or not d.breath_profile or #d.breath_profile.examples==0,
    d and d.breath_profile and #d.breath_profile.examples>0 and (not c.job or c.job.live or c.job.kind=='preview'))
  if im.Button(ctx,'Reset learning') then c:reset_breath_learning() end
  im.EndDisabled(ctx)
end
-- Separate calibrated dB axis: full-band waveform peaks are not HF detector power.
local function detector(im,ctx,c,w,h,color)
  if c.mode~='deess' then return end
  local d=c:current()
  local x,y=im.GetCursorScreenPos(ctx);local draw=im.GetWindowDrawList(ctx)
  im.InvisibleButton(ctx,'##detector_threshold',w,h)
  im.DrawList_AddRectFilled(draw,x,y,x+w,y+h,0x171A2070,4)
  local f=d and (d.hf_features or d.audio and d.audio.detector_features)
  if not f or not d.view then return end
  local function yy(db) return y+4+(h-8)*(1-DSP.clamp((db+60)/60,0,1)) end
  local active=im.IsItemActive(ctx)
  if active then
    c.gesture=true;d.threshold_drag=true
    local _,my=im.GetMousePos(ctx);local v=DSP.clamp(-60+(y+h-4-my)/(h-8)*60,-60,-6)
    if math.abs(v-c.cfg.deess_threshold)>.05 then c.cfg.deess_threshold=v;c:settings_changed('deess_threshold') end
  elseif d.threshold_drag then d.threshold_drag=nil;c:control_released() end
  im.DrawList_AddRectFilled(draw,x,y,x+w,y+h,0x171A2070,4)
  local previous
  for px=0,math.floor(w)-1 do
    local t=d.view.start-d.audio.pos+d.view.span*px/w
    local i=math.floor(t/d.audio.hop)+1;local db=f.db[i]
    if db then
      local pos=yy(db)
      if previous then im.DrawList_AddLine(draw,x+px-1,previous,x+px,pos,0x78C8ADCC) end
      previous=pos
    else previous=nil end
  end
  local threshold=yy(c.cfg.deess_threshold)
  im.DrawList_AddLine(draw,x,threshold,x+w,threshold,0xE8BC73D0)
  im.DrawList_AddText(draw,x+5,y+3,color.muted,string.format('HF  %.1f dBFS',c.cfg.deess_threshold))
  if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'High-frequency detector level and threshold. Drag to set threshold.') end
end
function M.draw(im,ctx,app,color,slider,wave)
  local c=app.cleaner;local d=c:current()
  local hard_busy=app.job~=nil or (c.job and c.job.kind~='preview' and not c.job.live) or false
  im.BeginDisabled(ctx,hard_busy)
  local changed,auto=im.Checkbox(ctx,'Auto',c.auto)
  if changed then c:set_auto(auto) end
  if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Select one or several audio items in REAPER to analyze and apply this tab. Turn off to capture only with Get.') end
  im.SameLine(ctx)
  if im.Button(ctx,'Get') then c:capture() end
  im.SameLine(ctx)
  Controls.disabled(im,ctx,c.job~=nil or c.pending~=nil or not d or not (d.layers and d.layers[c.mode]),
    not hard_busy and d and d.layers and d.layers[c.mode])
  if im.Button(ctx,'Remove') then c:apply(true) end
  im.EndDisabled(ctx)
  d=c:current()
  im.SameLine(ctx)
  local width=im.GetContentRegionAvail(ctx);im.SetNextItemWidth(ctx,math.max(70,width))
  local count=c.targets and #c.targets or 0
  local label=d and ((count>1 and count..' items · ' or '')..d.snapshot.name) or 'Select items'
  if im.BeginCombo(ctx,'##cleanup_item',label) then
    for i,item in ipairs(c.items) do if im.Selectable(ctx,item.snapshot.name..'##'..i,i==c.focus) then c:select_item(i) end end
    im.EndCombo(ctx)
  end
  if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Get captures all selected items. Choosing an item here focuses its own controls.') end
  im.EndDisabled(ctx)
  local knobs_busy=app.job~=nil or c.follow_due~=nil or (c.job and not c.job.live and c.job.kind~='preview' and c.job.kind~='read' and c.job.kind~='batch') or false
  im.BeginDisabled(ctx,knobs_busy or not d or (d and d.stale) or false)
  import('compressor/preset_ui').draw(im,ctx,c)
  if import('compressor/settings').dynamic(c.mode) then import('compressor/ui').controls(im,ctx,c)
  elseif c.mode=='breath' then breath_controls(im,ctx,c,d)
  else Controls.grid(im,ctx,c,'##cleanup_controls',deess_knobs,3) end
  im.EndDisabled(ctx)
  if c.error then im.TextWrapped(ctx,(c.error:match('^[^\r\n]+') or c.error))
  end
  Progress.draw(im,ctx,c.operation or (c.job and not c.job.live and (c.job.kind~='preview' or import('compressor/settings').dynamic(c.mode)) and c.job or nil),c.r)
  local w,h=im.GetContentRegionAvail(ctx);local nav=38
  local meter=c.mode=='deess' and 52 or 0
  canvas(im,ctx,c,w,math.max(100,h-nav-meter-16),color,wave)
  if meter>0 then detector(im,ctx,c,w,meter,color) end
  Navigator.draw(im,ctx,c:current(),w,nav,c.r,c.project)
end
return M
