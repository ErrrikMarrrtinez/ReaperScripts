-- @noindex
local import=...;local Registry=import('align/registry');local U=import('align/util');local Audio=import('audio');local Warp=import('warp');local M={}
function M.engine(im,ctx,app,busy)
  im.BeginDisabled(ctx,busy);im.SetNextItemWidth(ctx,-1)
  local current=Registry.get(app.align_engine)
  if im.BeginCombo(ctx,'##align_engine',current and current.display_name or 'Unsupported: '..tostring(app.align_engine))then
    for _,e in ipairs(Registry.entries)do if im.Selectable(ctx,e.display_name,app.align_engine==e.id)then app:select_engine(e.id)end end
    im.EndCombo(ctx)
  end
  im.EndDisabled(ctx)
end
function M.plan(app,d)
  if app.align_engine~='advanced_v1'then return app.preview~=false and d.plan or nil end
  if app.align_view=='Captured'then return nil end
  if app.align_view=='Applied'then return d.applied_plan end
  return d.plan
end
function M.status(app,d)
  if d.plan and d.plan.hybrid and not d.error then
    local s=d.plan.summary
    return string.format('%s · %d moved / %d compressed / %d stretched',d.hybrid_active and 'Applied Hybrid' or 'Hybrid',s.moved,s.compressed,s.stretched)
  end
  if app.align_engine~='advanced_v1'then return end
  local job=app.job
  if job and app.dubs[job.align_dub or 0]==d then
    local detail=job.align_budget and job.align_budget.detail
    local phase=job.label~=''and job.label or 'Analyzing'
    if detail and detail.candidate then phase=string.format('%s · %d/%d',phase,detail.candidate,detail.candidates)end
    local native=job.align_budget and job.align_budget.native_solver
    return string.format('%s · %s · %.1f s',phase,native and native.fn and 'EEL'or 'Lua',app.r.time_precise()-job.created_at)
  end
  if job and d.status=='Analyzing'then return 'Waiting for analysis'end
  local label=d.status or 'Unprocessed'
  local c=d.correspondence
  if c and c.diagnostics then label=label..string.format(' · %.0f%% accepted',100*(c.diagnostics.coverage or 0))end
  if d.applied_plan and d.applied_plan~=d.plan then label=label..' · previous timing audible' end
  return label
end
function M.regions(im,draw,app,d,plan,x,y,w,h,view)
  if plan and plan.hybrid then
    for _,p in ipairs(plan.pieces)do
      local a=x+(p.pos-view.start)/view.span*w;local b=x+(p.pos+p.len-view.start)/view.span*w
      if b>x and a<x+w then
        local tint=(p.min_ratio or p.ratio)<1-1e-6 and 0xE8BC7322 or (p.max_ratio or p.ratio)>1+1e-6 and 0xB3A0D322 or 0x78C8AD18
        im.DrawList_AddRectFilled(draw,math.max(x,a),y,math.min(x+w,b),y+h,tint)
        if a>=x and a<=x+w then im.DrawList_AddLine(draw,a,y,a,y+h,0xFFFFFF70)end
      end
    end
    return
  end
  if app.align_engine~='advanced_v1'then return end
  local function px(u)local t=plan and Warp.target(plan,u)or d.snapshot.pos+u;return x+(t-view.start)/view.span*w end
  local function region(a,b,color)
    if a and b then local left,right=math.max(x,px(a)),math.min(x+w,px(b));if right>left then im.DrawList_AddRectFilled(draw,left,y,right,y+h,color)end end
  end
  local c=d.correspondence
  if c then
    for _,s in ipairs(c.segments or {})do region(s.start_s,s.end_s,0x78C8AD20)end
    for _,s in ipairs(c.unmatched or {})do region(s.start_s,s.end_s,s.status=='ambiguous'and 0xE8BC7332 or s.status=='interpolated'and 0x82B4E818 or 0xF29A9118)end
  end
  if plan then for _,s in ipairs(plan.regions or {})do if s.status=='background_shoulder'then region(s.start_s,s.end_s,0x82B4E832)end end end
  for _,p in ipairs(app.alignment.constraints[d.snapshot.guid]or {})do
    if p.kind=='sync'or p.kind=='soft_sync'then
      local xx=px(p.dub_s);im.DrawList_AddLine(draw,xx,y,xx,y+h,p.kind=='sync'and 0xFFE394FF or 0xFFE39480,2)
    else region(p.start_s,p.end_s,p.kind=='protect_absolute'and 0xB3A0D340 or 0x989FAA38)end
  end
end
local function edit(app,d,kind,index)
  local old=app.alignment.constraints[d.snapshot.guid]or {};local selected=old[index or 0]
  local pin=kind=='sync'or kind=='soft_sync'
  local first=selected and (pin and selected.dub_s or selected.start_s)or math.min(d.snapshot.len,math.max(0,app.r.GetCursorPositionEx(app.project)-d.snapshot.pos))
  local second=selected and (pin and selected.guide_project_s or selected.end_s)or (pin and app.ref.pos+first or math.min(d.snapshot.len,first+.1))
  local yes,value=app.r.GetUserInputs(pin and 'Align: synchronization point' or 'Align: interval',2,
    pin and 'Dub time from captured start (s),Guide project time (s)'or 'Start from captured dub start (s),End from captured dub start (s)',string.format('%.6f,%.6f',first,second))
  if not yes then return end
  local a,b=value:match('^%s*([^,]+),%s*([^,]+)%s*$');a,b=tonumber(a),tonumber(b)
  if not U.finite(a)or not U.finite(b)then app:fail('Enter two finite times in seconds.');return end
  local list={};for i,c in ipairs(old)do list[i]=c end
  local c={kind=kind,id=selected and selected.id or string.format('manual-%d',app.alignment.constraints_revision+1)}
  if pin then c.dub_s=a;c.guide_project_s=b;c.source_s=Audio.source_time(d.snapshot,a);c.guide_guid=app.ref.guid
  else c.start_s=a;c.end_s=b;c.source_start_s=Audio.source_time(d.snapshot,a);c.source_end_s=Audio.source_time(d.snapshot,b)end
  list[index or #list+1]=c;app:set_align_constraints(d,list)
end
local matcher_labels={guided='Matcher: Classic path (guided)',strict='Matcher: strict candidates (experimental)'}
function M.controls(im,ctx,app,busy)
  im.BeginDisabled(ctx,busy)
  im.SetNextItemWidth(ctx,-1)
  local matcher=app.cfg.matcher or 'guided'
  if im.BeginCombo(ctx,'##align_matcher',matcher_labels[matcher]or matcher)then
    for _,id in ipairs({'guided','strict'})do
      if im.Selectable(ctx,matcher_labels[id],matcher==id)then app.cfg.matcher=id;app:settings_changed('matcher');app:control_released()end
    end
    im.EndCombo(ctx)
  end
  if im.IsItemHovered(ctx)then im.SetTooltip(ctx,'Guided: the Classic alignment path drives the Advanced planner (rate limits, pins, protected intervals, fades, verified writes). Strict: the experimental candidate search that declares similar phrases ambiguous and leaves them unmoved.')end
  local change,value=im.Checkbox(ctx,'Pitch evidence (optional)',app.cfg.advanced_pitch==true)
  if change then app.cfg.advanced_pitch=value;app:settings_changed('advanced_pitch');app:control_released()end
  if im.IsItemHovered(ctx)then im.SetTooltip(ctx,'Adds independent pitch evidence. Harmony profile gives it no matching weight. Enabling it may require Restore and Analyze.')end
  im.SameLine(ctx)
  if im.Button(ctx,'Refresh source')then app:refresh_align_source()end
  im.EndDisabled(ctx)
  im.SetNextItemWidth(ctx,-1)
  if im.BeginCombo(ctx,'##align_timing_view',app.align_view or 'Planned')then
    for _,v in ipairs({'Planned','Captured','Applied'})do if im.Selectable(ctx,v,(app.align_view or 'Planned')==v)then app.align_view=v end end
    im.EndCombo(ctx)
  end
  if im.CollapsingHeader(ctx,'Manual timing constraints')then
    im.BeginDisabled(ctx,busy or #app.dubs==0)
    local selected=app.dubs[app.constraint_dub or 1]
    if im.BeginCombo(ctx,'##constraint_dub',selected and selected.snapshot.name or 'Select dubs')then
      for i,d in ipairs(app.dubs)do if im.Selectable(ctx,d.snapshot.name..'##'..i,d==selected)then app.constraint_dub=i;selected=d end end
      im.EndCombo(ctx)
    end
    if selected then
      local width=im.GetContentRegionAvail(ctx)
      for i,k in ipairs({{'Pin','sync'},{'Soft pin','soft_sync'},{'Protect','protect_absolute'},{'Exclude match','exclude_match'}})do
        if i>1 and (width>=450 or i%2==0)then im.SameLine(ctx)end
        if im.Button(ctx,k[1])then edit(app,selected,k[2])end
      end
      for i,c in ipairs(app.alignment.constraints[selected.snapshot.guid]or {})do
        local pin=c.kind=='sync'or c.kind=='soft_sync'
        im.Text(ctx,pin and string.format('%s: %.3f → %.3f s',c.kind,c.dub_s,c.guide_project_s)or string.format('%s: %.3f–%.3f s',c.kind,c.start_s,c.end_s))
        im.SameLine(ctx);if im.SmallButton(ctx,'Edit##constraint'..i)then edit(app,selected,c.kind,i)end
        im.SameLine(ctx);if im.SmallButton(ctx,'×##constraint'..i)then local list={};for j,p in ipairs(app.alignment.constraints[selected.snapshot.guid])do if j~=i then list[#list+1]=p end end;app:set_align_constraints(selected,list);break end
      end
    end
    im.EndDisabled(ctx)
    im.TextWrapped(ctx,'Times refer to the captured dub; Guide times are absolute. Protect keeps timing fixed. Exclude removes matching evidence. Pins follow Strength and bypass Tolerance.')
  end
end
return M
