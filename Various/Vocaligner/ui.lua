-- @noindex
local import=...;local DSP=import('dsp');local Config=import('config');local Cleanup=import('cleanup')
local CleanerUI=import('cleaner_ui');local AlignUI=import('align_ui');local Wave=import('waveform');local PitchUI=import('pitch/ui');local M={}
local color={bg=0x171A20FF,panel=0x20242BFF,ref=0x78C8ADFF,dub=0xD9AB78FF,after=0x82B4E8FF,
  text=0xE4E8EFFF,muted=0x989FAAFF,line=0x353B45FF,warn=0xE8BC73FF,error=0xF29A91FF}
local theme={
  {'Col_WindowBg',color.panel},{'Col_Text',color.text},{'Col_TextDisabled',color.muted},
  {'Col_Button',0x353C46FF},{'Col_ButtonHovered',0x47525FFF},{'Col_ButtonActive',0x536271FF},
  {'Col_FrameBg',0x2B313BFF},{'Col_FrameBgHovered',0x394350FF},{'Col_FrameBgActive',0x445465FF},
  {'Col_Header',0x303A45FF},{'Col_HeaderHovered',0x404C59FF},{'Col_HeaderActive',0x485969FF},
  {'Col_CheckMark',color.ref},{'Col_SliderGrab',0x7B9DBFFF},{'Col_SliderGrabActive',color.after},
  {'Col_Border',color.line},
}
function M.draw(im,ctx,app)
  im.SetNextWindowSize(ctx,860,680,im.Cond_FirstUseEver)
  im.SetNextWindowSizeConstraints(ctx,app.tab=='pitch' and 640 or 340,400,2400,2400)
  for _,entry in ipairs(theme) do im.PushStyleColor(ctx,im[entry[1]],entry[2]) end
  im.PushStyleVar(ctx,im.StyleVar_FrameRounding,5)
  im.PushStyleVar(ctx,im.StyleVar_GrabRounding,4)
  im.PushStyleVar(ctx,im.StyleVar_FramePadding,8,4)
  im.PushStyleVar(ctx,im.StyleVar_ItemSpacing,8,6)
  local visible,open=im.Begin(ctx,'Vocaligner · Lua',true,im.WindowFlags_NoScrollbar|im.WindowFlags_NoScrollWithMouse)
  if visible then
    app.gesture=false;app.cleaner.gesture=false
    -- A separate header child reserves a real rectangle for the fixed report button.
    local w=im.GetContentRegionAvail(ctx);local report_w=im.CalcTextSize(ctx,'Report')+18
    local settings_w=im.CalcTextSize(ctx,'Settings')+18
    local header_h=im.GetFrameHeight(ctx)+4
    im.PushStyleVar(ctx,im.StyleVar_WindowPadding,0,0)
    if im.BeginChild(ctx,'##tool_tabs',math.max(100,w-report_w-settings_w-16),header_h,0,
      im.WindowFlags_NoScrollbar|im.WindowFlags_NoScrollWithMouse) then
      import('compressor/ui').tabs(im,ctx,app)
      im.EndChild(ctx)
    end
    im.PopStyleVar(ctx)
    im.SameLine(ctx)
    if im.Button(ctx,'Settings',settings_w) then im.OpenPopup(ctx,'Settings##vocaligner') end
    if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Shared settings for the Dynamics tabs: De-ess, Breaths, Compressor and Gate.') end
    if im.BeginPopupModal(ctx,'Settings##vocaligner',true,im.WindowFlags_AlwaysAutoResize) then
      im.TextDisabled(ctx,'Dynamics')
      im.Separator(ctx)
      import('compressor/ui').settings(im,ctx,app)
      im.Spacing(ctx)
      if im.Button(ctx,'Close') or im.IsKeyPressed(ctx,im.Key_Escape,false) then im.CloseCurrentPopup(ctx) end
      im.EndPopup(ctx)
    end
    im.SameLine(ctx)
    if im.Button(ctx,'Report',report_w) then im.OpenPopup(ctx,'Vocaligner report') end
    if im.BeginPopup(ctx,'Vocaligner report') then
      if im.Selectable(ctx,'Copy report') then
        local report=app:diagnostics();im.SetClipboardText(ctx,report);app.r.ShowConsoleMsg(report..'\n')
      end
      if app.tab=='pitch' then
        im.BeginDisabled(ctx,app.pitch:busy() or not app.pitch.data or app.pitch.no_selection==true)
        if im.Selectable(ctx,'Export case') then app.pitch:export_case() end
        if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Exports the time selection inside this item, or the whole item if there is no time selection. CSV times stay relative to the item start.') end
        im.EndDisabled(ctx)
      end
      if app.tab=='align'then
        im.BeginDisabled(ctx,app.job~=nil or not app.ref or #app.dubs==0)
        if im.Selectable(ctx,'Export Align case')then app:export_align_case()end
        im.EndDisabled(ctx)
      end
      im.EndPopup(ctx)
    end
    local wave=function(a,b,c,d,e,f,g,h,i,j,k,l,m) Wave.draw(a,b,c,d,e,f,g,h,i,j,k,l,m,app.legacy_wave) end
    if im.BeginChild(ctx,'##tool_body',0,0) then
      if import('compressor/settings').is_tool(app.tab) then
        app.cleaner:set_mode(app.tab);CleanerUI.draw(im,ctx,app,color,nil,wave)
      elseif app.tab=='pitch' then PitchUI.draw(im,ctx,app)
      else AlignUI.draw(im,ctx,app,color,wave) end
      if app.tab~='pitch' and im.BeginPopupContextWindow(ctx,'##wave_style',im.PopupFlags_MouseButtonRight|im.PopupFlags_NoOpenOverItems) then
        if im.Selectable(ctx,'Waveform: Outline',not app.legacy_wave) then app.legacy_wave=false end
        if im.Selectable(ctx,'Waveform: Legacy',app.legacy_wave==true) then app.legacy_wave=true end
        im.EndPopup(ctx)
      end
      im.EndChild(ctx)
    end
    if im.IsWindowFocused(ctx,im.FocusedFlags_RootAndChildWindows) then
      if im.IsKeyPressed(ctx,im.Key_Space,false) and not im.IsAnyItemActive(ctx) then app.r.Main_OnCommandEx(40044,0,app.r.EnumProjects(-1)) end
      if im.IsKeyPressed(ctx,im.Key_Escape,false) and not im.IsPopupOpen(ctx,'Settings##vocaligner') then
        if app.tab=='pitch' then app.pitch:cancel() else app.cleaner:clear_range() end
      end
    end
    im.End(ctx)
  end
  im.PopStyleVar(ctx,4);im.PopStyleColor(ctx,#theme)
  return open
end
return M
