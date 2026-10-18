-- Standalone sandbox entry. No envelope writes, external plugins, Python, or preference persistence.
local root=debug.getinfo(1,'S').source:match('^@(.+[\\/])')
local r=reaper
if not r.ImGui_GetBuiltinPath then r.MB('Install ReaImGui from ReaPack.','Click / Mouth research',0);return end
local im=dofile(r.ImGui_GetBuiltinPath()..'/imgui.lua')('0.9.3')
local import=dofile(root..'init.lua').import
local ctx=im.CreateContext('Vocaligner Click / Mouth · experimental')
local c=import('click/controller').new(r,import('click/engine').new(im,ctx,r),import('cleanup_dsp').new(im,ctx,r),import('click/repair').new(im,ctx,r))
local SE=import('click/sample_edits');local settings=import('click/settings')
r.atexit(function()c:cancel()end)
local function action(fn)local ok,why=xpcall(fn,debug.traceback);if not ok then c:fail(why) end end
local function loop()
 local ok,open=xpcall(function()
  c:tick();im.SetNextWindowSize(ctx,720,650,im.Cond_FirstUseEver)
  local visible,opened=im.Begin(ctx,'Click / Mouth · sample repair',true)
  if visible then
   im.TextWrapped(ctx,'Experimental detector and sample reconstruction. Analyze one WAV item, inspect candidates, then Apply. Changes are stored in the project; source files stay intact.')
   if not SE.supported(r.GetAppVersion())then im.TextWrapped(ctx,'Application unavailable: REAPER 7.71 or newer is required.')end
   if im.Button(ctx,'Analyze selected item')then action(function()c:analyze()end)end
   im.SameLine(ctx)
   if im.RadioButton(ctx,'Click',c.mode=='click')then c.mode='click';c:request()end
   im.SameLine(ctx)
   if im.RadioButton(ctx,'Mouth',c.mode=='mouth')then c.mode='mouth';c:request()end
   local width=im.GetContentRegionAvail(ctx);import('click/view').draw(im,ctx,c,width,220)
   for _,control in ipairs(settings.controls[c.mode])do
    local changed,value=im.SliderDouble(ctx,control[2],c.cfg[control[1]],control[3],control[4],control[5])
    if changed then c.cfg[control[1]]=value;c:request()end
    if im.IsItemHovered(ctx)then im.SetTooltip(ctx,control[6])end
   end
   im.BeginDisabled(ctx,not c.ready or c.job~=nil or not SE.supported(r.GetAppVersion()))
   if im.Button(ctx,'Apply sample repair')then action(function()c:apply(false)end)end
   im.EndDisabled(ctx);im.SameLine(ctx)
   im.BeginDisabled(ctx,not c.s or c.job~=nil or not SE.supported(r.GetAppVersion()))
   if im.Button(ctx,'Restore session original')then action(function()c:apply(true)end)end
   im.EndDisabled(ctx)
   if c.job then im.SameLine(ctx);if im.Button(ctx,'Cancel')then c:cancel()end;im.Text(ctx,c.job and c.job.label or 'Cancelled')end
   im.TextWrapped(ctx,c.message)
   if c.work_ms then im.Text(ctx,('Last job %.1f ms work; longest step %.1f ms'):format(c.work_ms,c.max_step_ms or 0))end
   if c.error then im.TextWrapped(ctx,c.error)end
   if im.Button(ctx,'Copy DeClick report')then im.SetClipboardText(ctx,c:diagnostics())end
   im.Separator(ctx)
   im.TextWrapped(ctx,'Checked candidates will be repaired. Switching modes replaces this session\'s repair when applied. Re-analyzing makes existing edits the new baseline.')
   im.BeginDisabled(ctx,c.job~=nil or not c.ready)
   for i=1,math.min(200,#c.events)do
    local e=c.events[i];local changed=im.Checkbox(ctx,('%03d  %.4f–%.4f s  score %.1f##event%d'):format(i,e.start,e.finish,e.score or 0,i),not e.excluded)
    if changed then c:exclude(i)end
   end
   im.EndDisabled(ctx)
   if #c.events>200 then im.Text(ctx,'Showing first 200 candidates. Split the item to inspect all candidates.')end
   im.End(ctx)
  end
  return opened
 end,debug.traceback)
 if not ok then c:cancel();r.ShowConsoleMsg(tostring(open)..'\n');return end
 if open then r.defer(loop)else c:cancel()end
end
r.defer(loop)
