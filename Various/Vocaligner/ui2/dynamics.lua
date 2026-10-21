-- @noindex
-- Страницы De-ess / Compressor / Gate нового интерфейса — та же раскладка, что у Breath (ui2/breath.lua):
-- Get (без Auto), слайдеры, волна + прогресс-бар + обзорная полоса вплотную. Логика 1 в 1 из cleaner_ui.lua и
-- compressor/ui.lua (оригиналы не тронуты). Пресеты скрыты, Bypass — тоггл на плитке, полоса HF-порога
-- De-ess под волной убрана (порог остаётся слайдером).
local import=...;local Settings=import('compressor/settings');local W=import('ui2/widgets')
local Canvas=import('ui2/canvas');local Progress=import('progress');local Knob=import('ui2/knob');local Strip=import('ui2/strip');local Comp2=import('ui2/comp2');local M={}
-- Новая морда компрессора (ui2/comp2.lua). false — вернуть прежнюю страницу (кноб порога + сетка + волна + обзор).
local COMP_V2=true
local NAV=22 -- высота обзорной полосы, как у Breath

local deess_knobs={
  {'deess_threshold','Threshold',-60,-6,'%.1f dBFS','Threshold in high-frequency detector power.'},
  {'deess_hz','Detector frequency',2000,14000,'%.0f Hz','Weights cached frequency bands. Does not EQ the audio.'},
  {'deess_amount','Reduction',0,100,'%.0f%%','Depth of reduction above the threshold, not the number of envelope points.'},
  {'deess_max_db','Max cut',0,18,'-%.1f dB','Maximum attenuation. For example, -9 dB limits the deepest dip to 9 dB.'},
  {'deess_pre_ms','Pre-open',0,75,'%.0f ms','Ramp before the detected sound. Zero adds no pre-open.'},
  {'deess_release_ms','Release',0,200,'%.0f ms','Time to return to original volume after the last detector frame. Analysis resolution: 10 ms.'},
  {'deess_detail','Envelope detail',0,100,'%.0f%%','More points / finer curve detail. Lower values keep the shape with fewer points.'},
}

-- Уровень детектора (0..1 в диапазоне параметра) в позиции воспроизведения/курсора; nil, если данных нет.
local function level(c,lo,hi)
  local d=c:current();local levels=d and d.detector_levels
  if not levels or #levels==0 then return nil end
  local r=c.r;local playing=r.GetPlayStateEx(c.project)&1~=0
  local time=(playing and r.GetPlayPositionEx(c.project) or r.GetCursorPositionEx(c.project))-d.snapshot.pos
  if time<0 or time>d.snapshot.len then return nil end
  local a,b=1,#levels
  while a<b do local m=(a+b+1)//2;if levels[m].t<=time then a=m else b=m-1 end end
  return math.max(0,math.min(1,(levels[a].db-lo)/(hi-lo)))
end
local TIP='Green bar: cached detector level at the play/edit cursor, including earlier cleanup stages. Detector HP/LP do not EQ the audio.'
-- Compressor / Gate: порог — кноб (кольцо-метр поверх ведёт уровень детектора), остальные параметры — сеткой справа.
-- Нет спрайта кноба -> прежний путь: слайдер во всю ширину с полоской уровня внутри.
local function dynamic_controls(im,ctx,c)
  local entries=Settings[c.mode];local e=entries[1]
  local knobs={};for i=2,#entries do knobs[#knobs+1]=entries[i] end
  -- Ratio — пробная ручка-полоска на спрайте (логарифмическая шкала); нет спрайта -> обычный слайдер
  if c.mode=='compressor' and Strip.available(im,ctx) then
    for i,k in ipairs(knobs) do if k[1]=='compressor_ratio' then
      knobs[i]={k[1],k[2],k[3],k[4],k[5],k[6],log=true,draw=function(im2,ctx2,owner,en) Strip.control(im2,ctx2,owner,en,im2.GetContentRegionAvail(ctx2)) end}
    end end
  end
  if Knob.available(im,ctx) then
    local used=Knob.control(im,ctx,c,{e[1],e[2],e[3],e[4],e[5]}, -- без тултипа
      function() return level(c,e[3],e[4]) end)
    im.SameLine(ctx,0,16)
    W.grid(im,ctx,c,'##dynamics_controls',knobs,3)
  else
    W.slider(im,ctx,c,e[1],e[2],e[3],e[4],e[5],-1,TIP)
    local v=level(c,e[3],e[4])
    if v then
      local x,y=im.GetItemRectMin(ctx);local xx,yy=im.GetItemRectMax(ctx)
      im.DrawList_AddRectFilled(im.GetWindowDrawList(ctx),x+2,yy-4,x+2+(xx-x-4)*v,yy-1,0x78C8ADCC)
    end
    W.grid(im,ctx,c,'##dynamics_controls',knobs,3)
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
  if COMP_V2 and Comp2.supports(c.mode) and Comp2.available(im,ctx) then
    local job=c.operation or (c.job and not c.job.live and c.job or nil)
    im.Dummy(ctx,1,4)
    Comp2.draw(im,ctx,c,color,ctl_disabled,job)
    return
  end
  local ctl_x,ctl_y=im.GetCursorScreenPos(ctx)
  im.BeginDisabled(ctx,ctl_disabled)
  -- (пресеты скрыты: import('compressor/preset_ui').draw(im,ctx,c) не вызывается)
  if Settings.dynamic(c.mode) then dynamic_controls(im,ctx,c)
  else W.grid(im,ctx,c,'##cleanup_controls',deess_knobs,3) end
  im.EndDisabled(ctx)
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
