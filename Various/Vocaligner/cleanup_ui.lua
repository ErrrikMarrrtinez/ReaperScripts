-- @noindex
local M={}
-- Waveform colour conveys the core. Only hover exposes exact core/ramp times;
-- no tall boxes or invented visual tails outside the actual reduction curve.
function M.draw(im,ctx,draw,c,d,x,y,w,h)
  if not d.detected then return end
  local mx,my=im.GetMousePos(ctx)
  if not im.IsItemHovered(ctx) or my<y or my>y+h then return end
  local t=d.view.start-d.audio.pos+(mx-x)/w*d.view.span
  local event,span
  for _,e in ipairs((c.mode=='breath' and d.detected.breaths or d.detected.sibilants or {})) do
    if t>=e.start and t<=e.finish then event=e;break end
  end
  for _,e in ipairs(d.effect_regions or {}) do
    if t>=e.start and t<=e.finish then span=e;break end
  end
  if event then
    local label=string.format('%.3f–%.3f s · %.0f ms%s',d.audio.pos+event.start,
      d.audio.pos+math.min(d.audio.len,event.finish),(event.finish-event.start)*1000,event.excluded and ' · excluded' or '')
    if span then label=label..string.format('\n−%.1f dB · %.3f–%.3f s with ramps',span.reduction,d.audio.pos+span.start,d.audio.pos+span.finish) end
    if event.kind=='breath' and event.level_db then
      label=label..string.format('\nBreath score %.2f · source RMS %.1f dBFS',event.score,event.level_db)
    end
    im.SetTooltip(ctx,label)
    if im.IsMouseClicked(ctx,1) then c:toggle_region(d,event) end
  elseif span then
    im.SetTooltip(ctx,string.format('−%.1f dB · %.3f–%.3f s',span.reduction,d.audio.pos+span.start,d.audio.pos+span.finish))
  end
end
return M
