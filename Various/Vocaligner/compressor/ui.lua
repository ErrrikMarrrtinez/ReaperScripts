-- @noindex
local import=...;local Settings=import('compressor/settings');local Controls=import('controls');local M={}
local function meter(im,ctx,c,lo,hi)
 local d=c:current();local levels=d and d.detector_levels
 if not levels or #levels==0 then return end
 local r=c.r;local playing=r.GetPlayStateEx(c.project)&1~=0
 local time=(playing and r.GetPlayPositionEx(c.project) or r.GetCursorPositionEx(c.project))-d.snapshot.pos
 if time<0 or time>d.snapshot.len then return end
 local a,b=1,#levels
 while a<b do local m=(a+b+1)//2;if levels[m].t<=time then a=m else b=m-1 end end
 local db=levels[a].db;local x,y=im.GetItemRectMin(ctx);local xx,yy=im.GetItemRectMax(ctx)
 local value=math.max(0,math.min(1,(db-lo)/(hi-lo)))
 local draw=im.GetWindowDrawList(ctx)
 im.DrawList_AddRectFilled(draw,x+2,yy-4,x+2+(xx-x-4)*value,yy-1,0x78C8ADCC)
end
-- Shared Dynamics options, drawn in the Settings window (ui.lua).
M.options={
 {'dynamics_rt','RT Update','Off: write the result after releasing a control. On: also write while dragging, but only when the measured update time (shown in brackets) is short: green — live, orange — slower, red — too slow, waits for release.'},
 {'chain_active','Envelope active','Off writes the take volume envelope bypassed (ACT 0), so it can be compared by ear.'},
 {'chain_visible','Show envelope','Show or hide the written take volume envelope lane in REAPER.'},
}
function M.settings(im,ctx,app)
 local c=app.cleaner
 local changed,auto=im.Checkbox(ctx,'Auto',c.auto)
 if changed then c:set_auto(auto) end
 if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Select one or several audio items in REAPER to analyze and apply the open Dynamics tab. Off: capture with Get.') end
 for _,entry in ipairs(M.options) do
  local label=entry[2];local col
  if entry[1]=='dynamics_rt' then
   -- как у Julian: в подписи видна задержка обновления; цвет — пойдёт ли RT во время жеста
   local lat=c:latency_ms()
   if lat then label=string.format('RT Update (%d ms)',math.floor(lat+.5))
    col=(c.cfg.dynamics_rt or 0)<.5 and 0x9A9AA8FF or lat<=120 and 0x8BD17CFF or lat<=c.rt_max_ms and 0xE8B65AFF or 0xE0625AFF end
  end
  if col then im.PushStyleColor(ctx,im.Col_Text,col) end
  local changed,on=im.Checkbox(ctx,label..'##'..entry[1],(c.cfg[entry[1]] or 0)>=.5)
  if col then im.PopStyleColor(ctx) end
  if changed then c.cfg[entry[1]]=on and 1 or 0;c:settings_changed(entry[1]);c:control_released() end
  if im.IsItemHovered(ctx) then im.SetTooltip(ctx,entry[3]) end
 end
 im.TextDisabled(ctx,'Drag the Dynamics tabs to change the processing order.')
end
function M.controls(im,ctx,c)
 local entries=Settings[c.mode];local e=entries[1]
 im.TextDisabled(ctx,e[2]);im.SetNextItemWidth(ctx,-1)
 local changed,v=im.SliderDouble(ctx,'##'..e[1],c.cfg[e[1]],e[3],e[4],e[5])
 if im.IsItemActive(ctx) then c.gesture=true end
 if changed then c.cfg[e[1]]=v;c:settings_changed(e[1]) end
 if im.IsItemDeactivatedAfterEdit(ctx) then c:control_released() end
 meter(im,ctx,c,e[3],e[4])
 if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Green bar: cached detector level at the play/edit cursor, including earlier cleanup stages. Detector HP/LP do not EQ the audio.') end
 local knobs={};for i=2,#entries do knobs[#knobs+1]=entries[i] end
 Controls.grid(im,ctx,c,'##dynamics_controls',knobs,3)
 -- RT Update, Envelope active and Show envelope moved to Settings.
 local d=c:current()
 if d and d.compute_ms then im.TextDisabled(ctx,string.format('Update %.1f ms · drag tabs to change processing order',d.compute_ms)) end
end
function M.tabs(im,ctx,app)
 local c=app.cleaner;local order=c.cfg.chain_order
 local entries={{'Align','align'}}
 for _,key in ipairs(Settings.parse(order))do entries[#entries+1]={Settings.labels[key],key} end
 entries[#entries+1]={'Pitch','pitch'}
 local reset=app.display_chain_order~=order;app.display_chain_order=order
 if im.BeginTabBar(ctx,'##tools:'..order) then
  local from,to
  for _,entry in ipairs(entries)do
   local flags=reset and app.tab==entry[2] and im.TabItemFlags_SetSelected or 0
   local visible=im.BeginTabItem(ctx,entry[1],nil,flags)
   if Settings.is_tool(entry[2]) then
    local busy=c.job and (c.job.kind=='apply' or c.job.kind=='batch') or app.job
    if not busy and im.BeginDragDropSource(ctx) then
     im.SetDragDropPayload(ctx,'VOCALIGNER_CHAIN',entry[2]);im.Text(ctx,'Move '..entry[1]);im.EndDragDropSource(ctx)
    end
    if not busy and im.BeginDragDropTarget(ctx) then
     local accepted,payload=im.AcceptDragDropPayload(ctx,'VOCALIGNER_CHAIN')
     if accepted then from,to=payload,entry[2] end
     im.EndDragDropTarget(ctx)
    end
    if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Processing runs left to right. Drag this tab onto another cleanup tab to move it before that stage.') end
   end
   if visible then
    if app.tab=='pitch' and entry[2]~='pitch' then app.pitch:cancel() end
    app.tab=entry[2];im.EndTabItem(ctx)
   end
  end
  im.EndTabBar(ctx)
  if from then c:reorder(from,to) end
 end
end
return M
