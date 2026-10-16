-- @noindex
local import=...;local Presets=import('compressor/presets');local Config=import('config');local Settings=import('compressor/settings');local M={}
local function invoke(c,fn,...)
 local ok,result=pcall(fn,...)
 if not ok then c.preset_error=tostring(result);return end
 c.preset_error=nil;c.preset_cache=nil;return result
end
function M.draw(im,ctx,c)
 local mode=c.mode
 local save_popup='Save cleanup preset##'..mode;local delete_popup='Delete cleanup preset##'..mode
 if not c.preset_cache or c.preset_cache.mode~=mode then
  local items,why=Presets.load(c.r,mode);c.preset_cache={mode=mode,items=items or {}};c.preset_error=why
 end
 c.preset_selected=c.preset_selected or {}
 local items=c.preset_cache.items;local selected=Presets.match(mode,c.cfg,items,c.preset_selected[mode])
 local w=im.GetContentRegionAvail(ctx);local actions=im.CalcTextSize(ctx,'Save...')+im.CalcTextSize(ctx,'Delete')+54
 im.SetNextItemWidth(ctx,math.max(95,w-actions))
 if im.BeginCombo(ctx,'##cleanup_preset_'..mode,selected)then
  if im.Selectable(ctx,'Default',selected=='Default')then c.preset_selected[mode]=nil;invoke(c,Presets.apply,c,Config.defaults)end
  local names={};for label in pairs(items)do names[#names+1]=label end;table.sort(names)
  for _,label in ipairs(names)do if im.Selectable(ctx,label,selected==label)then c.preset_selected[mode]=label;invoke(c,Presets.apply,c,items[label])end end
  im.EndCombo(ctx)
 end
 if im.IsItemHovered(ctx)then im.SetTooltip(ctx,'Presets for '..Settings.labels[mode]..'. Default resets only this tool. A selection of items receives the same preset; other stages keep their settings.')end
 im.SameLine(ctx)
 if im.Button(ctx,'Save...##cleanup_preset')then
  c.preset_name=items[selected] and selected or '';c.preset_save_mode=mode
  im.OpenPopup(ctx,save_popup)
 end
 im.SameLine(ctx);im.BeginDisabled(ctx,not items[selected])
 if im.Button(ctx,'Delete##cleanup_preset')then c.preset_delete_name=selected;im.OpenPopup(ctx,delete_popup)end
 im.EndDisabled(ctx)
 if im.BeginPopup(ctx,save_popup)then
  im.Text(ctx,'Save '..Settings.labels[mode]..' preset')
  im.SetNextItemWidth(ctx,230)
  local _,text=im.InputText(ctx,'Name',c.preset_name or '');c.preset_name=text
  local exists=items[text:match('^%s*(.-)%s*$')]~=nil
  if exists then im.TextDisabled(ctx,'A saved preset with this name will be replaced.')end
  if im.Button(ctx,exists and 'Replace' or 'Save')then
   local label=invoke(c,Presets.save,c.r,mode,text,c.cfg)
   if label then c.preset_selected[mode]=label;im.CloseCurrentPopup(ctx)end
  end
  im.SameLine(ctx);if im.Button(ctx,'Cancel')then im.CloseCurrentPopup(ctx)end
  im.EndPopup(ctx)
 end
 if im.BeginPopup(ctx,delete_popup)then
  im.Text(ctx,'Delete '..tostring(c.preset_delete_name)..'?')
  if im.Button(ctx,'Delete saved preset')then
   invoke(c,Presets.delete,c.r,mode,c.preset_delete_name);im.CloseCurrentPopup(ctx)
  end
  im.SameLine(ctx);if im.Button(ctx,'Keep')then im.CloseCurrentPopup(ctx)end
  im.EndPopup(ctx)
 end
 if c.preset_error then im.TextWrapped(ctx,c.preset_error)end
end
return M
