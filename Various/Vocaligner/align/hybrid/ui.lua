-- @noindex
local import=...;local Controls=import('controls');local Planner=import('align/hybrid/plan');local M={}
function M.draw(im,ctx,app,busy)
  im.BeginDisabled(ctx,busy)
  local on=(app.cfg.hybrid or 0)~=0
  local changed,value=im.Checkbox(ctx,'Hybrid edits (experimental)',on)
  if changed then
    local applied=false;for _,d in ipairs(app.dubs)do applied=applied or d.applied end
    if applied then app:restore()end
    local remaining=false;for _,d in ipairs(app.dubs)do remaining=remaining or d.applied end
    if not remaining then app.cfg.hybrid=value and 1 or 0;app:settings_changed('hybrid');app:control_released();on=value end
  end
  if im.IsItemHovered(ctx)then im.SetTooltip(ctx,'Move fragments separated by quiet pauses, shorten only quiet shoulders, and compress sustained parts while protecting detected attacks. Switching restores the captured timing before replanning. Restore or native Undo returns the original items.')end
  if on then
    im.SameLine(ctx);im.SetNextItemWidth(ctx,150)
    local id=math.max(1,math.min(3,math.floor(app.cfg.hybrid_preset or 2)))
    if im.BeginCombo(ctx,'##hybrid_preset',Planner.presets[id].name)then
      for i,p in ipairs(Planner.presets)do if im.Selectable(ctx,p.name,i==id)then
        app.cfg.hybrid_preset=i;app.cfg.hybrid_compression=p.compression;app:settings_changed('hybrid_preset');app:control_released()
      end end
      im.EndCombo(ctx)
    end
  end
  im.EndDisabled(ctx)
  return on
end
M.knobs={
  {'strength','Strength',0,100,'%.0f%%','How far timing follows the reference. Zero restores the original number of items and their captured state.'},
  {'hybrid_compression','Compression',0,100,'%.0f%%','Allow more and stronger compression when it improves the match. Low values favor moving intact phrases. This never permits cuts through voice.'},
  {'max_ratio','Stretch limit',1.05,2.5,'%.2fx','Hard limit on local time compression or expansion, including between protected attacks.'},
}
M.options={
  {'tolerance_ms','Tolerance',0,80,'%.0f ms','Accept small timing differences without adding edits.'},
  {'search_s','Search range',.05,5,'± %.2f s','Maximum shift from captured timing. Changing this rematches cached features.'},
  {'fade_ms','Marker fade',2.5,30,'%.1f ms','REAPER crossfade around stretch markers. Split seams use short fades inside verified quiet pauses.'},
}
return M
