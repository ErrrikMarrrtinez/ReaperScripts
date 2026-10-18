-- @noindex
local import=...;local Presets=import('compressor/presets');local Config=import('config');local Settings=import('compressor/settings');local M={}
local function invoke(c,fn,...)
 local ok,result=pcall(fn,...)
 if not ok then c.preset_error=(tostring(result):gsub('^.-:%d+: ',''));return end
 c.preset_error=nil;c.preset_cache=nil;return result
end
-- Row layout: the caller may draw buttons before it on the same line.
function M.draw(im,ctx,c)
 local mode=c.mode
 local save_popup='Save cleanup preset##'..mode;local delete_popup='Delete cleanup preset##'..mode
 if not c.preset_cache or c.preset_cache.mode~=mode then
  local items,why=Presets.load(c.r,mode);c.preset_cache={mode=mode,items=items or {}};c.preset_error=why
 end
 c.preset_selected=c.preset_selected or {}
 local items=c.preset_cache.items;local selected=Presets.match(mode,c.cfg,items,c.preset_selected[mode])
 local custom_default=items[Presets.default]~=nil
 local w=im.GetContentRegionAvail(ctx);local actions=im.CalcTextSize(ctx,'Save...')+im.CalcTextSize(ctx,'Delete')+54
 im.SetNextItemWidth(ctx,math.max(95,w-actions))
 if im.BeginCombo(ctx,'##cleanup_preset_'..mode,selected)then
  if im.Selectable(ctx,Presets.default,selected==Presets.default)then c.preset_selected[mode]=nil;invoke(c,Presets.apply,c,Presets.defaults(mode,items))end
  local names={};for label in pairs(items)do if label~=Presets.default then names[#names+1]=label end end;table.sort(names)
  for _,label in ipairs(names)do if im.Selectable(ctx,label,selected==label)then c.preset_selected[mode]=label;invoke(c,Presets.apply,c,items[label])end end
  if custom_default then
   im.Separator(ctx)
   if im.Selectable(ctx,'Factory default',selected=='Factory default')then c.preset_selected[mode]=nil;invoke(c,Presets.apply,c,Config.defaults)end
  end
  im.EndCombo(ctx)
 end
 if im.IsItemHovered(ctx)then
  im.SetTooltip(ctx,'Presets for '..Settings.labels[mode]..'. Save as "Default" to replace this tool\'s default; Factory default stays available. A selection of items receives the same preset; other stages keep their settings.'
   ..(c.preset_error and '\n\n'..c.preset_error or ''))
 end
 im.SameLine(ctx)
 if im.Button(ctx,'Save...##cleanup_preset')then
  c.preset_name=items[selected] and selected or '';c.preset_save_mode=mode;c.preset_error=nil
  im.OpenPopup(ctx,save_popup)
 end
 im.SameLine(ctx);im.BeginDisabled(ctx,not items[selected])
 if im.Button(ctx,'Delete##cleanup_preset')then c.preset_delete_name=selected;c.preset_error=nil;im.OpenPopup(ctx,delete_popup)end
 im.EndDisabled(ctx)
 if im.BeginPopup(ctx,save_popup)then
  im.Text(ctx,'Save '..Settings.labels[mode]..' preset')
  im.SetNextItemWidth(ctx,230)
  local _,text=im.InputText(ctx,'Name',c.preset_name or '');c.preset_name=text
  local ok,label=pcall(Presets.name,text)
  local exists=ok and items[label]~=nil
  if ok and label==Presets.default then im.TextDisabled(ctx,'Replaces the default of this tool. Factory default stays in the list.')
  elseif exists then im.TextDisabled(ctx,'A saved preset with this name will be replaced.') end
  if im.Button(ctx,exists and 'Replace' or 'Save')then
   local saved=invoke(c,Presets.save,c.r,mode,text,c.cfg)
   if saved then c.preset_selected[mode]=saved~=Presets.default and saved or nil;im.CloseCurrentPopup(ctx)end
  end
  im.SameLine(ctx);if im.Button(ctx,'Cancel')then c.preset_error=nil;im.CloseCurrentPopup(ctx)end
  if c.preset_error then im.TextWrapped(ctx,c.preset_error)end
  im.EndPopup(ctx)
 end
 if im.BeginPopup(ctx,delete_popup)then
  local resetting=c.preset_delete_name==Presets.default
  im.Text(ctx,resetting and 'Return '..Settings.labels[mode]..' Default to the factory values?' or 'Delete '..tostring(c.preset_delete_name)..'?')
  if im.Button(ctx,resetting and 'Use factory default' or 'Delete saved preset')then
   invoke(c,Presets.delete,c.r,mode,c.preset_delete_name)
   if not c.preset_error then im.CloseCurrentPopup(ctx)end
  end
  im.SameLine(ctx);if im.Button(ctx,'Keep')then c.preset_error=nil;im.CloseCurrentPopup(ctx)end
  if c.preset_error then im.TextWrapped(ctx,c.preset_error)end
  im.EndPopup(ctx)
 end
end
return M
