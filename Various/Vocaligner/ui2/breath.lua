-- @noindex
-- Страница Breath нового интерфейса. Содержимое 1 в 1 из cleaner_ui.lua (режим 'breath'), но:
--  * пресеты скрыты (код пресетов не тронут), Bypass заменён тоглом на плитке во вкладках;
--  * прогресс-бар (логика та же) стоит вплотную под волной, под ним обзорная полоса;
--  * слайдеры рисуются через ui2/widgets.lua; «Show envelope» временно вернулась в ряд с Learn.
local import=...;local Config=import('config');local Settings=import('compressor/settings')
local W=import('ui2/widgets');local Canvas=import('ui2/canvas');local Progress=import('progress');local Comp2=import('ui2/comp2');local M={}
local UI=Config.dynamics_ui
local NAV=22 -- высота обзорной полосы

local breath_knobs={
  {'breath_sensitivity','Sensitivity',0,100,'%.0f%%','Threshold of the trained breath detector. Higher catches more sounds. Learn a breath or keep-sound example to adapt this take.'},
  {'breath_db','Reduction',0,18,'-%.1f dB','Fixed attenuation per breath. Does not change which sounds are detected.'},
  {'breath_min_ms','Minimum duration',40,500,'%.0f ms','Ignore shorter breath candidates.'},
  {'breath_pre_ms','Fade in',0,100,'%.0f ms','Fade into attenuation inside the breath. Does not cut the previous word. Minimum one analysis step (10 ms).'},
  {'breath_release_ms','Fade out',0,300,'%.0f ms','Return to original level inside the breath, before the next word. Minimum one analysis step (10 ms).'},
  {'breath_detail','Envelope detail',0,100,'%.0f%%','More points / finer volume envelope.'},
  {'breath_join_ms','Join gaps',0,300,'%.0f ms','Join fragments only when the gap has compatible spectrum and level. Keeps one gain across the breath.'},
  {'breath_edge_ms','Find edges',0,250,'%.0f ms','Maximum boundary search around a detected breath. Stops at silence, protected sounds and sharp spectral or level changes.'},
}
local breath_target={'breath_target','Target',-80,-12,'%.1f dBFS','80th-percentile source RMS per breath. One gain for the whole breath; existing take volume and FX are not included.'}
local breath_curve={'breath_curve','Curve',0,100,'%.0f%%','Bezier strength of both fades. 0 is linear; higher values drop into the breath sooner and return later. Fade in/out set where each curve starts and ends.'}

local function controls(im,ctx,c,d)
  -- Target level is forced on for now (Config.dynamics_ui); the checkbox,
  -- Reduction and Max cut return when breath_target_only is switched off.
  if not UI.breath_target_only then
    local changed,target=im.Checkbox(ctx,'Target level',(c.cfg.breath_mode or 0)>=.5)
    if changed then c.cfg.breath_mode=target and 1 or 0;c:settings_changed('breath_mode');c:control_released() end
    if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Lower each detected breath toward one RMS target, limited by Max cut. Already quieter breaths stay unchanged.') end
  end
  local entries={};for i,e in ipairs(breath_knobs) do entries[i]=e end
  if UI.breath_target_only then entries[2]=breath_target
  elseif (c.cfg.breath_mode or 0)>=.5 then
    entries[2]=breath_target
    table.insert(entries,3,{'breath_db','Max cut',0,18,'-%.1f dB','Limit how much Target level can reduce a breath. It never boosts audio.'})
  end
  -- Envelope detail is kept for rollback; Curve replaces it with Bezier fades.
  if UI.breath_bezier then
    for i,e in ipairs(entries)do if e[1]=='breath_detail' then entries[i]=breath_curve end end
  end
  W.grid(im,ctx,c,'##breath_controls',entries,3)
  local length=d and d.range[2]-d.range[1] or 0
  local need=not d or not d.audio or not d.selected or length<.04 or length>2
  local why=(not d or not d.audio) and 'Select an audio item first.' or (not d.selected and 'Drag on the time ruler over one breath first (40 ms to 2 s).')
    or (length<.04 and 'The selection is shorter than 40 ms.') or (length>2 and 'The selection is longer than 2 s.') or nil
  im.BeginDisabled(ctx,need)
  if im.Button(ctx,'Learn breath') then c:learn_breath(1) end
  if im.IsItemHovered(ctx,im.HoveredFlags_AllowWhenDisabled) then im.SetTooltip(ctx,why or 'Select one clear breath on the time ruler (40 ms to 2 s). Learn its sound for this take. Escape clears the processing selection; Get then updates the whole item.') end
  im.SameLine(ctx)
  if im.Button(ctx,'Keep sound') then c:learn_breath(-1) end
  if im.IsItemHovered(ctx,im.HoveredFlags_AllowWhenDisabled) then im.SetTooltip(ctx,why or 'Learn a selected consonant or noise that should not be treated as a breath. Applies to similar sounds in this take.') end
  im.EndDisabled(ctx);im.SameLine(ctx)
  W.disabled(im,ctx,c.job~=nil or c.pending~=nil or not d or not d.breath_profile or #d.breath_profile.examples==0,
    d and d.breath_profile and #d.breath_profile.examples>0 and (not c.job or c.job.live or c.job.kind=='preview'))
  if im.Button(ctx,'Reset learning') then c:reset_breath_learning() end
  im.EndDisabled(ctx)
  -- Кнопки неактивны без выделения на линейке: подсказка работает и на неактивной кнопке, чтобы было ясно, чего не хватает.
  -- (Кнопка «Show envelope» убрана: её роль выполняет значок-глаз под ручками.)
  if im.IsItemHovered(ctx,im.HoveredFlags_AllowWhenDisabled) and not (d and d.breath_profile and #d.breath_profile.examples>0) then
    im.SetTooltip(ctx,'Nothing learned yet. Use Learn breath or Keep sound first.')
  end
end

function M.draw(im,ctx,app,color,wave)
  local c=app.cleaner;local d=c:current()
  local hard_busy=app.job~=nil or (c.job and c.job.kind~='preview' and not c.job.live) or false
  -- Auto lives in Settings. Get only matters while capture is manual.
  if not c.auto then
    im.BeginDisabled(ctx,hard_busy)
    if im.Button(ctx,'Get') then c:capture() end
    if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Capture the selected audio items and process this tab. Turn on Auto in Settings to follow the REAPER selection.') end
    im.EndDisabled(ctx)
  end
  d=c:current()
  -- Ручки блокируются только когда правка невозможна (идёт анализ Align, ждём выбор айтемов, нет данных).
  -- Фоновые задачи Cleanup (preview/apply/save) ручки не блокируют: settings_changed сам отменяет или переочередит работу.
  local knobs_busy=app.job~=nil or c.follow_due~=nil or false
  -- A bypassed stage keeps its settings untouched until it is brought back.
  local ctl_disabled=knobs_busy or not d or (d and d.stale) or c:bypassed(d) or false
  local ctl_x,ctl_y=im.GetCursorScreenPos(ctx)
  im.BeginDisabled(ctx,ctl_disabled)
  -- (пресеты скрыты: import('compressor/preset_ui').draw(im,ctx,c) не вызывается)
  controls(im,ctx,c,d)
  im.EndDisabled(ctx)
  do -- Hide/Show: огибающая громкости айтемов в REAPER (общая кнопка со страницами Dynamics)
    local hx,hy=im.GetCursorScreenPos(ctx);Comp2.hide_button(im,ctx,c,hx,hy)
  end
  if ctl_disabled then local _,ey=im.GetCursorScreenPos(ctx);W.catch(im,ctx,ctl_x,ctl_y,im.GetContentRegionAvail(ctx),ey-ctl_y,'##ctl_catch') end
  -- Errors go to the REAPER console and Report, not above the waveform.
  local job=c.operation or (c.job and not c.job.live and (c.job.kind~='preview' or Settings.dynamic(c.mode)) and c.job or nil)
  -- Волна, прогресс-бар и обзорная полоса стоят вплотную друг к другу.
  im.Dummy(ctx,1,4)
  local w,h=im.GetContentRegionAvail(ctx)
  im.PushStyleVar(ctx,im.StyleVar_ItemSpacing,0,0)
  Canvas.draw(im,ctx,c,w,math.max(100,h-NAV-Progress.height-2),color,wave)
  Progress.draw(im,ctx,job,c.r)
  Canvas.navigator(im,ctx,c:current(),w,NAV,c.r,c.project)
  im.PopStyleVar(ctx)
end
return M
