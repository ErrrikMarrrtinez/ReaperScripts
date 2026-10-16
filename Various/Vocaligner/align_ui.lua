-- @noindex
local import=...;local DSP=import('dsp');local Config=import('config');local Controls=import('controls');local Progress=import('progress');local Transport=import('transport');local AdvancedUI=import('align/ui');local Warp=import('warp');local M={}
local knobs={
  {'strength','Strength',0,100,'%.0f%%','Blend captured timing with the matched timing. Zero restores the captured marker map.'},
  {'marker_density','Marker density',0,100,'%.0f%%','Fewer / more stretch markers. Edge anchors and existing source-map knots are always retained.'},
  {'smooth_ms','Timing smoothing',0,180,'%.0f ms','Smooth local changes in the timing map.'},
  {'tolerance_ms','Tolerance',0,80,'%.0f ms','Leave small timing differences alone.'},
  {'search_s','Search range',.05,5,'± %.2f s','Changing this rematches cached features. It does not read the audio again.'},
  {'max_ratio','Stretch limit',1.05,2.5,'%.2fx','Maximum local stretch or compression.'},
  {'fade_ms','Marker fade',2.5,30,'%.1f ms','Crossfade around stretch markers to soften joins.'},
}
local advanced_knobs={};for i,k in ipairs(knobs)do advanced_knobs[i]=k end
advanced_knobs[3]={'advanced_smooth','Timing smoothing',0,100,'%.0f%%','Regularize the timing map while preserving pins, protected intervals and local stretch limits.'}
local function canvas(im,ctx,app,w,h,color,wave)
  local count=#app.dubs+(app.ref and 1 or 0)
  if count==0 then return end
  local font=im.GetFontSize(ctx);local lane=math.max(font*5.5,(h-25)/count)
  h=25+lane*count
  local x,y=im.GetCursorScreenPos(ctx);local draw=im.GetWindowDrawList(ctx)
  if not app.view then
    local a,b=app.ref.pos,app.ref.pos+app.ref.len
    for _,d in ipairs(app.dubs) do
      a=math.min(a,d.snapshot.pos,d.plan and d.plan.pos or a)
      b=math.max(b,d.snapshot.pos+d.snapshot.len,d.plan and d.plan.pos+d.plan.len or b)
    end
    local span=math.max(.2,b-a);app.view={start=a-span*.025,span=span*1.05,full_start=a-span*.025,full_span=span*1.05}
  end
  local v=app.view
  if v.span>=v.full_span then v.start,v.span=v.full_start,v.full_span end
  im.InvisibleButton(ctx,'##all_waveforms',w,h)
  local hovered=im.IsItemHovered(ctx)
  if hovered then
    local wheel=im.GetMouseWheel(ctx)
    if wheel~=0 then
      local mx=im.GetMousePos(ctx);local f=DSP.clamp((mx-x)/w,0,1)
      local span=DSP.clamp(v.span*1.2^(-wheel),math.min(.15,v.full_span),v.full_span)
      v.start=v.start+f*(v.span-span);v.span=span
      if v.span>=v.full_span then v.start=v.full_start end
    end
    if im.IsMouseDoubleClicked(ctx,0) then v.start,v.span=v.full_start,v.full_span end
  end
  if im.IsItemActive(ctx) and im.IsMouseDragging(ctx,0,3) then
    app.wave_drag=true;local dx=im.GetMouseDelta(ctx);v.start=v.start-dx*v.span/w
  end
  if im.IsMouseReleased(ctx,0) then
    if hovered and not app.wave_drag and app.r.EnumProjects(-1)==app.project then
      local mx=im.GetMousePos(ctx);app.r.SetEditCurPos2(app.project,math.max(0,v.start+(mx-x)/w*v.span),false,false)
    end
    app.wave_drag=nil
  end
  local transport=Transport.read(app.r,app.project)
  Transport.follow(app,app.r,transport,v,0,v.full_start,v.full_start+v.full_span,im.IsItemActive(ctx) or hovered and im.GetMouseWheel(ctx)~=0)
  im.DrawList_AddRectFilled(draw,x,y,x+w,y+h,color.bg,5)
  im.DrawList_PushClipRect(draw,x,y,x+w,y+h,true)
  local step=10^math.floor(math.log(v.span/7,10))
  if v.span/step>14 then step=step*5 elseif v.span/step>8 then step=step*2 end
  for t=math.ceil(v.start/step)*step,v.start+v.span,step do
    local xx=x+(t-v.start)/v.span*w
    im.DrawList_AddLine(draw,xx,y+24,xx,y+h,0xFFFFFF0B)
    im.DrawList_AddText(draw,xx+3,y+4,color.muted,string.format(step<1 and '%.2fs' or '%.1fs',t))
  end
  for i=1,count do
    local d=app.dubs[i-1];local ref=i==1
    local s=ref and app.ref or d.snapshot
    local data
    if ref then data=app.ref_audio or app.ref_quick else data=d.audio or d.quick end
    local plan=not ref and AdvancedUI.plan(app,d)or nil
    local yy=y+25+(i-1)*lane;local top=yy+font+10;local height=lane-font-18
    local tint=ref and color.ref or (plan and color.after or color.dub)
    local status=not (ref and app.ref_audio or not ref and d.plan) and 'Unprocessed' or nil
    if not ref and d.plan and d.plan.review then status=d.applied and 'Applied · low match' or 'Low match' end
    if not ref and d.error then status='Skipped' end
    if not ref then status=AdvancedUI.status(app,d)or status end
    local reserved=status and im.CalcTextSize(ctx,status)+18 or 0
    im.DrawList_PushClipRect(draw,x,yy,x+math.max(20,w-reserved),yy+font+10,true)
    im.DrawList_AddText(draw,x+9,yy+4,tint,(ref and 'REF · ' or '')..s.name)
    im.DrawList_PopClipRect(draw)
    if status then
      local tw=im.CalcTextSize(ctx,status);im.DrawList_AddText(draw,x+w-tw-9,yy+4,color.muted,status)
    end
    if not ref then AdvancedUI.regions(im,draw,app,d,plan,x,top,w,height,v)end
    wave(im,ctx,draw,data,plan,x,top,w,height,v,tint)
    -- Item boundaries of a grouped role, at their planned position when previewing.
    if s.composite then for k,part in ipairs(s.parts) do
      for _,edge in ipairs({part.pos-s.pos,part.pos-s.pos+part.len}) do
        local t=plan and Warp.target(plan,edge) or s.pos+edge;local xx=x+(t-v.start)/v.span*w
        if xx>=x and xx<=x+w then im.DrawList_AddLine(draw,xx,yy+font+8,xx,yy+lane-4,0xFFFFFF40) end
      end
      if k==1 then local xx=x+((plan and plan.pos or s.pos)-v.start)/v.span*w;im.DrawList_AddText(draw,xx+4,yy+lane-font-6,color.muted,#s.parts..' items') end
    end end
    if plan then for _,p in ipairs(plan.markers) do
      local xx=x+(p.target-v.start)/v.span*w
      if xx>=x and xx<=x+w then im.DrawList_AddLine(draw,xx,top,xx,yy+lane-4,0x82B4E832) end
    end end
    im.DrawList_AddLine(draw,x,yy+lane,x+w,yy+lane,color.line)
  end
  Transport.draw(im,draw,transport,function(t)return x+(t-v.start)/v.span*w end,x,x+w,y+24,y+h)
  im.DrawList_PopClipRect(draw)
end
function M.draw(im,ctx,app,color,wave)
  local w=im.GetContentRegionAvail(ctx);local busy=app.job~=nil or app.cleaner.job~=nil or app.pitch.job~=nil
  local hard_busy=(app.job and not app.job.live) or app.cleaner.job~=nil or app.pitch.job~=nil or false
  app.gesture=false
  AdvancedUI.engine(im,ctx,app,busy)
  Controls.disabled(im,ctx,busy,not hard_busy)
  if im.Button(ctx,'Select reference',(w-8)/2) then app:reference_selected() end
  im.SameLine(ctx);im.BeginDisabled(ctx,not app.ref)
  if im.Button(ctx,'Select dubs',(w-8)/2) then app:dubs_selected() end
  im.EndDisabled(ctx)
  Controls.disabled(im,ctx,busy,not hard_busy)
  local grouped,group_value=im.Checkbox(ctx,'Group items per track',(app.cfg.group_items or 1)~=0)
  if grouped then app.cfg.group_items=group_value and 1 or 0;app:preferences_changed() end
  if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Consecutive selected items on one track act as one reference or one dub (one timeline with silent gaps). Off: every selected item is its own dub.') end
  im.EndDisabled(ctx)
  if app.loop_items then
    Controls.disabled(im,ctx,busy,not hard_busy)
    if im.Button(ctx,'Trim looped tails') then app:trim_loop_tails() end
    if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Shorten the selected items that play past the end of their audio file (Loop source on), so each ends exactly at its file end. The removed tail only repeated the file start. One Undo step restores it; the selection is then captured again.') end
    im.EndDisabled(ctx)
  end
  if app.edge_items then
    Controls.disabled(im,ctx,busy,not hard_busy)
    if im.Button(ctx,'Add edge anchors') then app:add_edge_anchors() end
    if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Add missing boundary markers to selected dubs using REAPER\'s current source map, then capture them. Undo restores the previous marker list.') end
    im.EndDisabled(ctx)
  end
  if #app.groups>0 then
    local g=app.group;local label=g and string.format('%s · %d dubs',g.ref.name,#g.dubs) or 'New group'
    im.SetNextItemWidth(ctx,math.max(80,w-38))
    if im.BeginCombo(ctx,'##groups',label) then
      for i,group in ipairs(app.groups) do
        local title=string.format('%d · %s · %d dubs · %.1f–%.1f s',group.id,group.ref.name,#group.dubs,group.ref.pos,group.ref.pos+group.ref.len)
        if im.Selectable(ctx,title,group==app.group) then app:select_group(i) end
      end
      im.EndCombo(ctx)
    end
    im.SameLine(ctx)
    if im.Button(ctx,'×##forget_group',30) then app:remove_group() end
    if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Forget this group cache; leave the project unchanged.') end
  end
  im.EndDisabled(ctx)
  if hard_busy then
    if im.Button(ctx,'Cancel') then if app.job then app:cancel() else app.cleaner:cancel() end end
  else
    Controls.disabled(im,ctx,busy or not app.ref or #app.dubs==0,app.ref and #app.dubs>0 and not hard_busy)
    if im.Button(ctx,'Analyze') then app:start() end
    im.EndDisabled(ctx)
  end
  if #app.dubs>0 then
    local applied=false;for _,d in ipairs(app.dubs) do applied=applied or d.applied end
    im.SameLine(ctx);Controls.disabled(im,ctx,busy or not applied,applied and not hard_busy)
    if im.Button(ctx,'Restore') then app:restore() end
    im.EndDisabled(ctx)
  end
  -- Status stays inside each existing waveform lane; finishing another dub
  -- must not insert a row and resize every waveform underneath the controls.
  im.BeginDisabled(ctx,hard_busy)
  local remaining=im.GetContentRegionAvail(ctx)
  if remaining>=570 then im.SameLine(ctx)end
  im.SetNextItemWidth(ctx,remaining>=340 and math.max(140,math.min(235,remaining-200))or -1)
  if im.BeginCombo(ctx,'##profile',app.cfg.profile) then
    for _,p in ipairs(Config.profiles) do
      if im.Selectable(ctx,p,app.cfg.profile==p) then
        app.cfg.profile=p
        if app.align_engine~='advanced_v1'then for k,v in pairs(Config.presets[p]) do app.cfg[k]=v end end
        app:settings_changed('profile');app:control_released()
      end
    end
    im.EndCombo(ctx)
  end
  im.EndDisabled(ctx)
  if app.align_engine~='advanced_v1'then
    if remaining>=340 then im.SameLine(ctx)end
    local changed,value=im.Checkbox(ctx,'Show aligned timing',app.preview~=false);if changed then app.preview=value end
  end
  local HybridUI=import('align/hybrid/ui')
  local hybrid=app.align_engine~='advanced_v1'and HybridUI.draw(im,ctx,app,busy)
  im.BeginDisabled(ctx,hard_busy)
  Controls.grid(im,ctx,app,'##align_controls',app.align_engine=='advanced_v1'and advanced_knobs or hybrid and HybridUI.knobs or knobs,3)
  if hybrid and im.CollapsingHeader(ctx,'Hybrid timing options')then Controls.grid(im,ctx,app,'##hybrid_options',HybridUI.options,3)end
  im.EndDisabled(ctx)
  if app.align_engine=='advanced_v1'then AdvancedUI.controls(im,ctx,app,busy)end
  if app.error then im.TextWrapped(ctx,(app.error:match('^[^\r\n]+') or app.error)) end
  Progress.draw(im,ctx,app.operation or (app.job and not app.job.live and app.job or nil),app.r)
  local cw,ch=im.GetContentRegionAvail(ctx)
  canvas(im,ctx,app,cw,math.max(160,ch-6),color,wave)
end
return M
