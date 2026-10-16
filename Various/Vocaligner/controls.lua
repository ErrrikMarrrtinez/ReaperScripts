-- @noindex
local M={}
-- A short parameter commit still blocks conflicting actions, without making
-- the whole panel flash grey. Persistent unavailable controls keep their tint.
function M.disabled(im,ctx,disabled,quiet)
  local stable=disabled and quiet and im.PushStyleVar and im.StyleVar_DisabledAlpha
  if stable then im.PushStyleVar(ctx,im.StyleVar_DisabledAlpha,1)end
  im.BeginDisabled(ctx,disabled==true)
  if stable then im.PopStyleVar(ctx)end
end
function M.slider(im,ctx,owner,key,label,lo,hi,fmt,width,tip)
  -- Group both items: a table cell must align the whole control, not the slider's baseline.
  im.BeginGroup(ctx)
  im.TextDisabled(ctx,label);im.SetNextItemWidth(ctx,width or -1)
  local changed,value=im.SliderDouble(ctx,'##'..key,owner.cfg[key],lo,hi,fmt)
  if im.IsItemActive(ctx) then owner.gesture=true end
  if changed then owner.cfg[key]=value;owner:settings_changed(key) end
  if im.IsItemDeactivatedAfterEdit(ctx) then owner:control_released() end
  if tip and im.IsItemHovered(ctx) then im.SetTooltip(ctx,tip) end
  im.EndGroup(ctx)
end
function M.grid(im,ctx,owner,id,entries,max_columns)
  local w=im.GetContentRegionAvail(ctx)
  local columns=math.max(1,math.min(max_columns or 3,math.floor(w/145)))
  if im.BeginTable(ctx,id,columns,im.TableFlags_SizingStretchSame) then
    for _,e in ipairs(entries) do
      im.TableNextColumn(ctx)
      M.slider(im,ctx,owner,e[1],e[2],e[3],e[4],e[5],-1,e[6])
    end
    im.EndTable(ctx)
  end
end
return M
