-- @noindex
-- Компрессор / Gate / De-esser, вторая морда (проба; файл остался comp2.lua). Откат на прежние страницы: COMP_V2=false в ui2/dynamics.lua.
-- Режимы описаны таблицей SPECS ниже (диапазон dB, передаточная кривая, кнобы слева и в ряду по семплеру).
-- Слева панель: Threshold / Ratio / Knee крупно, Out gain / Pre-comp, внизу детектор (HP/LP узлами, RMS, интервал).
-- Справа «плеер» вплотную к краям страницы (левый край плавно уходит в фон): волна в dB вокруг плей/эдит-курсора
-- (едет плавно во время воспроизведения), сверху вниз — линия снижения (как в обзорной полосе старой страницы),
-- поверх — честная передаточная кривая (порог, ratio, круговое колено Julian 1 в 1 с compressor/engine.lua),
-- у правого края — шкала dB и метр уровня детектора; Attack/Release — кнобы внутри по нижнему краю.
-- Вся связь с cleaner та же, что у старой страницы: cfg[key] + W.changed + control_released + gesture.
local import=...;local Settings=import('compressor/settings');local W=import('ui2/widgets');local Knob=import('ui2/knob')
local Transport=import('transport');local Cleanup=import('cleanup');local Progress=import('progress');local Canvas=import('ui2/canvas');local M={}

local DB_LO,DB_HI=-60,3 -- вертикаль «плеера»; у режима свой диапазон (SP.lo/SP.hi), задаётся в M.draw
local METER_W=6          -- метр у самого правого края
local LABEL_W=22         -- подписи dB левее метра (поверх волны, без фона)
local FADE=120           -- ширина плавного перехода левого края «плеера» в фон страницы
local DIM_H=230          -- высота затемнения у нижнего края «плеера»
local NAV=22             -- полоса снижения сверху (высота как у обзорной полосы)
local GREEN=0x78C8ADFF
local BG=0x1A1A1AFF      -- нейтральный фон «плеера»
-- Спрайты кнобов Ratio_<px>.png: кадр ровно того размера, в котором кноб показывается (68/52/42), 56 кадров, сжато из
-- ratio_knob_strip 128 px × 101. Без масштабирования при показе края зубцов остаются чёткими (раньше «рябили»).
-- Стиль кнобов: false — спрайты (Sp_*), true — векторные кнобы в стиле FL, нарисованные линиями ImGui (чёткие при любом размере)
local KNOB_VECTOR=false
local PT={r0=.58,r1=.82,col=0x3B312BE6} -- полоска-указатель рисуется в ImGui по центру блика
local skins={}
-- Sp_<px>.png (Timb_SSpot2018Control-006, обесцвечен до серого; крупный 1:1, кадр 58 px); Dk_ — прежний (Timb_DarkaGain-1: кадр 64 px, крупный 1:1; прежний вариант Tj_ — 111TJATEST: кадр 64 px, крупный показывается 1:1 без масштабирования) — четвёртый вариант; Tan_/ Gold_/Ratio_ — прежние (у спрайта свой указатель, полоска ImGui не нужна); вернуть прежний: 'Ratio_' и pointer=PT
local function skin(px) skins[px]=skins[px] or {file='Sp_'..px..'.png'};return skins[px] end

-- De-ess: те же параметры и подписи, что у прежней страницы (ui2/dynamics.lua)
local DEESS={
  {'deess_threshold','Threshold',-60,-6,'%.1f dBFS'},{'deess_hz','Frequency',2000,14000,'%.0f Hz'},
  {'deess_amount','Reduction',0,100,'%.0f%%'},{'deess_max_db','Max cut',0,18,'-%.1f dB'},
  {'deess_pre_ms','Pre-open',0,75,'%.0f ms'},{'deess_release_ms','Release',0,200,'%.0f ms'},
  {'deess_detail','Detail',0,100,'%.0f%%'},
}
local E={}
for _,list in ipairs({Settings.compressor,Settings.gate,DEESS}) do for _,e in ipairs(list) do E[e[1]]=e end end
local function entry(key,label,tip) local e=E[key];return {e[1],label or e[2],e[3],e[4],e[5],tip} end
local function clamp(v,lo,hi) return v<lo and lo or (v>hi and hi or v) end
local function fa(col,k) return (col&0xFFFFFF00)|math.floor((col&255)*clamp(k,0,1)) end

-- Снижение (dB) статической кривой для уровня детектора level — та же формула, что в EEL (compressor/engine.lua).
local function reduction(cfg,level)
  local thr,ratio,knee=cfg.compressor_threshold,cfg.compressor_ratio,cfg.compressor_knee
  if ratio<=1 then return 0 end
  local slope=1/ratio
  if knee<=0 then return math.max(0,(1-slope)*(level-thr)) end
  local xL=thr-knee;local xH=thr+math.sqrt(2)*knee*math.cos(math.atan(slope));local yH=thr+slope*(xH-thr)
  if level>=xH then return (1-slope)*(level-thr) end
  if level<=xL then return 0 end
  local xC=(yH-2*xL+ratio*xH)/(ratio-1);local yC=2*xL-xC;local r2=(yC-xL)^2+(xC-xL)^2
  return level-yC-math.sqrt(math.max(0,r2-(level-xC)^2))
end
M.reduction=reduction
local function knee_span(cfg)
  local thr,ratio,knee=cfg.compressor_threshold,cfg.compressor_ratio,cfg.compressor_knee
  if knee<=0 or ratio<=1 then return thr,thr end
  return thr-knee,thr+math.sqrt(2)*knee*math.cos(math.atan(1/ratio))
end

-- ===== режимы =====
-- lo/hi — вертикаль «плеера», dB; thr — ключ порога; gain(cfg) — добавка выхода; out(cfg,in) — выход статической кривой;
-- lines(cfg) — ломаные кривой {pts={{in,out},...},hot={lo,hi}|nil,faint=bool}; dots(cfg) — входные уровни точек на кривой;
-- big/mini — левая панель (две большие ручки над парой мелких); row — ряд по семплеру; filter — префикс HP/LP детектора или nil.
local function sample(cfg,f,lo,hi,n)
  local pts={};for i=0,n do local x=lo+(hi-lo)*i/n;pts[#pts+1]={x,f(cfg,x)} end;return pts
end
local SPECS={
  compressor={lo=-60,hi=3,thr='compressor_threshold',tip='compressor',
    gain=function(cfg) return cfg.compressor_gain or 0 end,
    out=function(cfg,x) return x-reduction(cfg,x)+(cfg.compressor_gain or 0) end,
    lines=function(cfg)
      local kl,kh=knee_span(cfg)
      return {{pts=sample(cfg,function(cf,x) return x-reduction(cf,x)+(cf.compressor_gain or 0) end,-60,3,264),hot=kh>kl and {kl,kh} or nil}}
    end,
    dots=function(cfg) local kl,kh=knee_span(cfg);local t={cfg.compressor_threshold};if kh>kl then t[2],t[3]=kl,kh end;return t end,
    big={{'compressor_threshold'},{'compressor_ratio',nil,{log=true}}},
    mini={{'compressor_rms_ms','RMS',{scaling=.4}},{'compressor_interval_ms','Env interval',{scaling=.5}}},
    row={{'compressor_attack_ms',nil,'big',{scaling=.5}},{'compressor_release_ms',nil,'big',{scaling=.5}},
         {'compressor_knee','Knee','mid',{scaling=.7}},{'compressor_pre_ms',nil,'mid',{scaling=.5,step=.1}},
         {'compressor_gain','Output','mid',{}}},
    filter='compressor_'},
  -- Gate: кривая + полоса гистерезиса (между порогом открытия и закрытия) + след детектора во времени
  gate={lo=-90,hi=3,thr='gate_threshold',trace=true,
    band=function(cfg) return cfg.gate_threshold-cfg.gate_hysteresis,cfg.gate_threshold end,
    gain=function() return 0 end,
    out=function(cfg,x) if x>=cfg.gate_threshold then return x end return x-cfg.gate_range end,
    lines=function(cfg)
      local t,hy,r=cfg.gate_threshold,cfg.gate_hysteresis,cfg.gate_range
      return {{pts={{-90,-90-r},{t,t-r}}},{pts={{t,t-r},{t,t}},faint=true},{pts={{t,t},{3,3}}}}
    end,
    dots=function(cfg) return {cfg.gate_threshold} end,
    big={{'gate_threshold'},{'gate_range','Range'}},
    mini={{'gate_rms_ms','RMS',{scaling=.4}},{'gate_interval_ms','Env interval',{scaling=.5}}},
    row={{'gate_attack_ms',nil,'big',{scaling=.5}},{'gate_hold_ms',nil,'big',{scaling=.4}},{'gate_release_ms',nil,'big',{scaling=.4}},
         {'gate_pre_ms',nil,'mid',{scaling=.4}},{'gate_hysteresis',nil,'mid',{}}},
    filter='gate_'},
  -- De-ess: зависимости вход→выход нет (порог — по мощности ВЧ-детектора), поэтому вместо кривой — линия порога,
  -- след уровня детектора во времени и подсветка волны там, где идёт подавление
  deess={lo=-72,hi=3,thr='deess_threshold',highlight=true,hf=true,editable=true,
    gain=function() return 0 end,
    out=function(cfg,x) return x-math.min(cfg.deess_max_db,math.max(0,x-cfg.deess_threshold)*cfg.deess_amount/100) end,
    big={{'deess_threshold'},{'deess_amount','Reduction'}},
    mini={{'deess_hz','Frequency',{scaling=1}},{'deess_max_db','Max cut',{scaling=1}}},
    row={{'deess_release_ms',nil,'big',{scaling=.5}},{'deess_pre_ms',nil,'mid',{scaling=.5}},{'deess_detail',nil,'mid',{}}}},
}
local SP=SPECS.compressor
function M.supports(mode) return SPECS[mode]~=nil end

-- мелкий текст в drawlist (размер fs при текущем шрифте); ширина — для выравнивания
local function small(im,ctx,dl,x,y,col,s,fs)
  if im.DrawList_AddTextEx and im.GetFont then im.DrawList_AddTextEx(dl,im.GetFont(ctx),fs,x,y,col,s)
  else im.DrawList_AddText(dl,x,y,col,s) end
end
local function small_w(im,ctx,s,fs) return im.CalcTextSize(ctx,s)*fs/im.GetFontSize(ctx) end

-- ===== плавное время вида =====
-- Плей-позиция REAPER приходит ступеньками аудиоблоков; вид едет по своим часам и мягко подтягивается к ней.
local S={span=4,t=nil,last=nil,meter=nil}
M.state=S
local function view_time(c,tr,now)
  local target=tr.play or tr.edit or 0
  local dt=clamp(now-(S.last or now),0,.1);S.last=now
  if not S.t or math.abs(target-S.t)>S.span*3 then S.t=target;return S.t end
  if tr.running and tr.play then
    local rate=c.r.Master_GetPlayRate and c.r.Master_GetPlayRate(c.project) or 1
    S.t=S.t+dt*rate
    local err=target-S.t
    if math.abs(err)>.3 then S.t=target else S.t=S.t+err*math.min(1,dt*6) end
  else
    S.t=S.t+(target-S.t)*math.min(1,dt*14)
    if math.abs(target-S.t)<1e-4 then S.t=target end
  end
  return S.t
end

local function level_at(d,t)
  local data=d and (d.audio or d.quick)
  if SP and SP.hf then -- De-ess: мощность ВЧ-детектора по кадрам анализа
    local f=data and data.detector_features;if not f or not f.db or not data.hop then return nil end
    local i=math.floor(t/data.hop)+1;if i<1 or i>#f.db then return nil end
    return f.db[i]
  end
  local levels=d and d.detector_levels
  if not levels or #levels==0 or t<levels[1].t or t>levels[#levels].t+.05 then return nil end
  local a,b=1,#levels
  while a<b do local m=(a+b+1)//2;if levels[m].t<=t then a=m else b=m-1 end end
  return levels[a].db
end

-- ===== «плеер» =====
-- opt.edit: ручной режим — без перехода слева и затемнения снизу, сверху линейка, вид по d.view (а не по курсору)
local function player(im,ctx,c,d,x,y,w,h,color,round,opt)
  local EDIT=opt and opt.edit;local FD=EDIT and 0 or FADE
  local dl=im.GetWindowDrawList(ctx);local cfg=c.cfg;local font=im.GetFontSize(ctx)
  local fs=math.max(8,font-5)
  local now=c.r.time_precise()
  im.DrawList_PushClipRect(dl,x,y,x+w,y+h,false) -- до краёв страницы, включая её поля
  -- фон: слева плавно из прозрачного, без ровной границы с панелью кнобов
  im.DrawList_AddRectFilled(dl,x+FD,y,x+w,y+h,BG,round,im.DrawFlags_RoundCornersRight)
  if im.DrawList_AddRectFilledMultiColor then
    im.DrawList_AddRectFilledMultiColor(dl,x,y,x+FD+1,y+h,fa(BG,0),BG,BG,fa(BG,0))
  end
  local function fade(xx) if FD<=0 then return 1 end return clamp((xx-x)/FD,0,1) end
  local px0,pw=x,w
  local py0=y+4;local ph=y+h-py0 -- верх шкалы почти у края, низ — по нижнему
  local function ydb(db) return py0+ph*(DB_HI-db)/(DB_HI-DB_LO) end
  -- передаточная кривая — в правых 60% (левее её закрывают кнобы)
  local cx0,cx1=px0+pw*.4,px0+pw-METER_W-LABEL_W
  local function xdb(db) return cx0+(cx1-cx0)*(db-DB_LO)/(DB_HI-DB_LO) end
  local tr=Transport.read(c.r,c.project)
  local vt=view_time(c,tr,now)
  local start=vt-S.span*.35 -- запас: треть окна позади курсора, две трети впереди
  local pt=S.span/pw
  if EDIT and opt.view then start=opt.view.start;pt=opt.view.span/pw end
  local data=d and (d.audio or d.quick)
  for db=0,DB_LO+12,-12 do
    local yy=ydb(db)
    if im.DrawList_AddRectFilledMultiColor then
      im.DrawList_AddRectFilledMultiColor(dl,x,yy,x+FD,yy+1,0xFFFFFF00,0xFFFFFF07,0xFFFFFF07,0xFFFFFF00)
    end
    im.DrawList_AddLine(dl,x+FD,yy,px0+pw,yy,0xFFFFFF07)
  end
  local thr=cfg[SP.thr];local ty=ydb(thr)
  local sx=px0+pw-METER_W-LABEL_W -- левый край подписей шкалы
  -- волна: столбцы привязаны к сетке времени (а не к пикселям окна), поэтому при движении вида картинка
  -- сдвигается целиком на дробные пиксели и не «мерцает»
  local live
  if false and EDIT and data and data.peaks and data.peaks[1] then -- (симметричная волна — отключена)
    local level=data.peaks[1]
    for _,l in ipairs(data.peaks) do if l.hop<=pt then level=l end end
    local rel=start-data.pos;local k0=math.floor(rel/pt)
    local curve=d.tool_preview;local mid=py0+ph*.5;local gk=.46*ph/math.max(1e-6,data.peak or 1)
    local pt_,pb_
    for k=k0,k0+math.ceil(pw)+1 do
      local ta,tb=k*pt,(k+1)*pt;local xx=px0+(ta-rel)/pt
      if tb>=0 and ta<=data.len then
        local first=math.max(1,math.floor(ta/level.hop)+1);local last=math.min(#level.values,math.floor(tb/level.hop)+1)
        local lo,hi=0,0
        for i=first,last do local p=level.values[i];if p[1]<lo then lo=p[1] end;if p[2]>hi then hi=p[2] end end
        local red=curve and Cleanup.value(curve,(ta+tb)*.5) or 0;local gain=10^(-red/20)
        local top,bot=mid-hi*gain*gk,mid-lo*gain*gk;if bot<top+1 then bot=top+1 end
        local lit=red>.05
        im.DrawList_AddLine(dl,xx+.5,top,xx+.5,bot,lit and 0xE8C27A44 or 0xB4B4B440)
        if pt_ then
          local ec=lit and 0xF0CC88D8 or 0xC8C8C8C8
          im.DrawList_AddLine(dl,xx-.5,pt_,xx+.5,top,ec);im.DrawList_AddLine(dl,xx-.5,pb_,xx+.5,bot,ec)
        end
        pt_,pb_=top,bot
      else pt_=nil end
    end
    im.DrawList_AddLine(dl,px0,mid,px0+pw,mid,0xFFFFFF10)
    live=level_at(d,vt-data.pos)
  elseif data and data.peaks and data.peaks[1] then
    local level=data.peaks[1]
    for _,l in ipairs(data.peaks) do if l.hop<=pt then level=l end end
    local rel=start-data.pos;local k0=math.floor(rel/pt)
    -- при зуме — пики видимого окна у REAPER (как у DeClick / старой волны): детальнее базовых
    local origin=0
    if EDIT and Canvas.detail then
      Canvas.detail(c,d,data,{start=start,span=pw*pt},pw)
      local det=data.detail
      if det and det.hop<level.hop and det.t0<=rel and det.t1>=rel+pw*pt then level=det;origin=det.t0 end
    end
    local curve=d.tool_preview;local prev,prev_o
    local red_col={} -- снижение по столбцам для полосы сверху
    for k=k0,k0+math.ceil(pw)+1 do
      local ta,tb=k*pt,(k+1)*pt
      local xx=px0+(ta-rel)/pt
      if tb>=0 and ta<=data.len then
        local red=curve and Cleanup.value(curve,(ta+tb)*.5) or 0
        red_col[k]=math.max(0,red+SP.gain(cfg))
        local first=math.max(1,math.floor((ta-origin)/level.hop)+1);local last=math.min(#level.values,math.floor((tb-origin)/level.hop)+1)
        local amp=0
        for i=first,last do local p=level.values[i];amp=math.max(amp,-p[1],p[2]) end
        if amp>1e-6 then
          local db=20*math.log(amp,10)
          local out=db-red
          local yi,yo=clamp(ydb(db),py0,py0+ph),clamp(ydb(out),py0,py0+ph)
          local f=fade(xx)
          local lit=SP.highlight and red>.05 -- De-ess: столбец подсвечен, если здесь идёт подавление
          im.DrawList_AddLine(dl,xx,py0+ph,xx,yo,fa(lit and 0xE8C27A55 or 0xB4B4B420,f))
          if yo>yi+.5 and not EDIT then im.DrawList_AddLine(dl,xx,yi,xx,yo,fa(0xF29A5A26,f)) end -- то, что срезано (тускло; в правке не рисуем)
          if prev then
            im.DrawList_AddLine(dl,xx-1,prev_o,xx,yo,fa(lit and 0xF0CC88F0 or 0xD2D2D2D0,f))
          end
          prev,prev_o=yi,yo
        else prev=nil end
      else prev=nil end
    end
    -- полоса снижения сверху вниз: та же лёгкая размытость на 5 столбцов и контур, что у обзорной полосы старой страницы
    local scale=math.max(3,d.tool_preview and d.tool_preview.max_db or 0)
    local pdb,py_
    for k=k0,EDIT and k0-1 or k0+math.ceil(pw)+1 do
      local sum,n=0,0
      for j=-2,2 do local v=red_col[k+j];if v then sum=sum+v;n=n+1 end end
      local db=n>0 and sum/n or 0
      local xx=px0+(k*pt-rel)/pt;local f=fade(xx)
      local yb=y+4+(NAV-6)*math.min(1,db/scale) -- на 4 px ниже края: толщина линии не обрезается
      if py_ and (db>.01 or pdb>.01) then im.DrawList_AddLine(dl,xx-1,py_,xx,yb,fa(0xE06A64C8,f),1.3) end
      py_,pdb=yb,db
    end
    live=level_at(d,vt-data.pos)
  end
  -- De-ess: след уровня ВЧ-детектора во времени; выше порога — ярче (именно там включается подавление)
  if SP.trace and data and ((d.detector_levels and #d.detector_levels>0) or (SP.hf and data.detector_features)) then
    local rel=start-data.pos;local prv,pab
    for i=0,math.floor(pw),2 do
      local lv=level_at(d,rel+i*pt)
      if lv then
        local yy=clamp(ydb(lv),py0,py0+ph);local ab=lv>thr;local xx=px0+i
        if prv then im.DrawList_AddLine(dl,xx-2,prv,xx,yy,fa((ab or pab) and 0x9FE3C8E0 or 0x78C8AD60,fade(xx)),(ab or pab) and 1.6 or 1) end
        prv,pab=yy,ab
      else prv=nil end
    end
  end
  -- Gate: полоса гистерезиса — гейт открывается на верхней границе, закрывается на нижней
  if SP.band then
    local b0,b1=SP.band(cfg)
    if b1>b0 then
      local ya,yb=ydb(b1),ydb(b0)
      if im.DrawList_AddRectFilledMultiColor then
        im.DrawList_AddRectFilledMultiColor(dl,x,ya,x+FD,yb,0x78C8AD00,0x78C8AD12,0x78C8AD12,0x78C8AD00)
      end
      im.DrawList_AddRectFilled(dl,x+FD,ya,sx-4,yb,0x78C8AD12)
      for xx=px0+FD*.5,sx-4,7 do im.DrawList_AddLine(dl,xx,yb,math.min(sx-4,xx+3),yb,fa(0x78C8AD70,fade(xx))) end
    end
  end
  -- порог: у компрессора/гейта тусклый пунктир, у De-ess — явная сплошная линия; ярче при наведении/перетаскивании
  local hot_=S.thr_hot or S.thr_drag
  if SP.highlight then im.DrawList_AddLine(dl,px0+pw-METER_W-1,ty,px0+pw,ty,0xF2B15AFF,2) end -- порог поперёк метра: видно, когда детектор его пересекает
  if SP.highlight then
    local tcol=hot_ and 0xF2B15AFF or 0xF2B15AB0
    im.DrawList_AddLine(dl,x,ty,sx-4,ty,fa(tcol,.9),hot_ and 2 or 1.5)
  else
    local tcol=hot_ and 0xFFFFFF90 or 0xFFFFFF30
    for xx=px0,sx-4,9 do im.DrawList_AddLine(dl,xx,ty,math.min(sx-4,xx+5),ty,fa(tcol,math.max(.4,fade(xx)))) end
  end
  -- передаточная кривая по диагонали: вход — по горизонтали, выход — по той же шкале dB, что и волна
  for _,ln in ipairs(SP.lines and SP.lines(cfg) or {}) do
    local px_,py_,pin
    for _,pt in ipairs(ln.pts) do
      local cx,cy=xdb(pt[1]),ydb(pt[2])
      if px_ then
        local f=clamp((cx-x)/36,0,1) -- кривая проступает раньше, чем волна
        local hot=ln.hot and pt[1]>ln.hot[1] and pin<ln.hot[2]
        if ln.faint then im.DrawList_AddLine(dl,px_,py_,cx,cy,fa(0xFFFFFF30,f),1)
        elseif hot then im.DrawList_AddLine(dl,px_,py_,cx,cy,fa(0xF2B15AFF,f),2)
        else im.DrawList_AddLine(dl,px_,py_,cx,cy,fa(0xFFFFFF14,f),6);im.DrawList_AddLine(dl,px_,py_,cx,cy,fa(0xE8ECF2E0,f),1.6) end
      end
      px_,py_,pin=cx,cy,pt[1]
    end
  end
  -- точки на кривой: порог (и края колена у компрессора)
  for i,inp in ipairs(SP.dots and SP.dots(cfg) or {}) do
    im.DrawList_AddCircleFilled(dl,xdb(inp),ydb(SP.out(cfg,inp))+1,i==1 and 3.2 or 3,0xF2B15AFF)
  end
  -- живая точка: где сейчас детектор на кривой
  if live and SP.lines then
    im.DrawList_AddCircleFilled(dl,xdb(clamp(live,DB_LO,DB_HI)),ydb(clamp(SP.out(cfg,live),DB_LO,DB_HI))+1,3,GREEN)
  end
  local ny=y+NAV+2
  if d and c:bypassed(d) then im.DrawList_AddText(dl,x+FD*.5,ny+font+2,color.warn,'Bypassed')
  elseif not data then im.DrawList_AddText(dl,x+FD*.5,ny,color.muted,'Select an audio item') end
  -- затемнение низа под кнобами: на всю ширину «плеера», начинается высоко и нарастает плавно (ease);
  -- слева гасится тем же переходом, что и сам «плеер», чтобы не было ступеньки
  local kb=y+h-DIM_H
  if not EDIT and im.DrawList_AddRectFilledMultiColor then
    local N=16
    for j=0,N-1 do
      local t0,t1=j/N,(j+1)/N
      local a0,a1=.92*t0*t0*(3-2*t0),.92*t1*t1*(3-2*t1)
      local ya,yb=kb+DIM_H*t0,kb+DIM_H*t1
      im.DrawList_AddRectFilledMultiColor(dl,x,ya,x+FD,yb,fa(BG,0),fa(BG,a0),fa(BG,a1),fa(BG,0))
      im.DrawList_AddRectFilledMultiColor(dl,x+FD,ya,x+w,yb,fa(BG,a0),fa(BG,a0),fa(BG,a1),fa(BG,a1))
    end
  end
  -- подписи dB и метр у самого правого края, поверх волны
  local mx1=px0+pw;local mx0=mx1-METER_W
  local step=ph/((DB_HI-DB_LO)/6)>=fs+3 and 6 or 12
  for db=DB_HI-(DB_HI%step),DB_LO+step,-step do
    local yy=ydb(db);local s=string.format('%d',db)
    small(im,ctx,dl,mx0-3-small_w(im,ctx,s,fs),yy-fs/2,0xC8C8C8B0,s,fs)
  end
  local dt=clamp(now-(S.meter_at or now),0,.1);S.meter_at=now
  local lv=live or DB_LO-10
  S.meter=(not S.meter or lv>S.meter) and lv or math.max(lv,S.meter-dt*30) -- быстро вверх, плавно вниз
  if S.meter>DB_LO then
    im.DrawList_AddRectFilled(dl,mx0,ydb(math.min(S.meter,DB_HI)),mx1,y+h,0x78C8ADC0)
  end
  im.DrawList_PopClipRect(dl)
  return {px0=px0,py0=py0,pw=pw,ph=ph,ty=ty,start=start,pt=pt,data=data,sx=sx,kb=kb,right=px0+pw-METER_W-LABEL_W,ydb=ydb}
end

-- взаимодействие с «плеером»: колесо — ширина окна, клик — переход курсора, порог тянется за пунктир.
-- Без своего ImGui-элемента: вызывается ПОСЛЕ всех кнобов и кнопок страницы и реагирует, только если мышь не над
-- каким-либо элементом (кнобы, кнопка Filter и её панель) — иначе клик «проваливался» бы сквозь них в семплер.
local function player_input(im,ctx,c,d,x,y,w,h,g,dis)
  local mx,my=im.GetMousePos(ctx)
  local pn=S.panel
  local inside=mx>=x and mx<x+w and my>=y and my<y+h and not (pn and mx>=pn[1] and mx<pn[1]+pn[3] and my>=pn[2] and my<pn[2]+pn[4])
  local hovered=inside and im.IsWindowHovered(ctx) and not im.IsAnyItemHovered(ctx) and not im.IsAnyItemActive(ctx)
  local near=not dis and math.abs(my-g.ty)<6 and mx<g.sx
  S.thr_hot=(hovered and near) or S.thr_drag and true or nil
  if hovered then
    local wheel=im.GetMouseWheel(ctx)
    if wheel~=0 then S.span_t=clamp((S.span_t or S.span)*1.2^(-wheel),1,30) end -- цель зума; сам вид доезжает в M.draw
    if im.IsMouseDoubleClicked(ctx,0) then S.span_t=4 end
    if near then im.SetMouseCursor(ctx,im.MouseCursor_ResizeNS) end
    if im.IsMouseClicked(ctx,0) then
      S.press=true;S.thr_drag=near and {y=my,v=c.cfg[SP.thr]} or nil;S.click_x=mx;S.moved=false
    end
  end
  if S.press then
    if im.IsMouseDown(ctx,0) then
      if S.thr_drag then
        c.gesture=true
        local fine=(im.GetKeyMods(ctx)&im.Mod_Shift)~=0 and .1 or 1
        local e=E[SP.thr]
        local v=clamp(S.thr_drag.v-(my-S.thr_drag.y)*(DB_HI-DB_LO)/g.ph*fine,e[3],e[4])
        if math.abs(v-c.cfg[SP.thr])>1e-9 then c.cfg[SP.thr]=v;W.changed(c,SP.thr) end
        im.SetMouseCursor(ctx,im.MouseCursor_ResizeNS)
        Knob.plate(im,ctx,mx,g.ty+10,string.format('Threshold %.1f dB',v))
      elseif S.click_x and math.abs(mx-S.click_x)>3 then S.moved=true end
    else
      if S.thr_drag then c:control_released()
      elseif not S.moved and g.data and d then
        local t=g.start+(mx-g.px0)*g.pt-g.data.pos
        if t>=0 and t<=g.data.len then c:seek(t) end
      end
      S.press=nil;S.thr_drag=nil;S.click_x=nil
    end
  end
end

-- ===== фильтр детектора: кривая HP/LP с узлами =====
local F_LO,F_HI=20,20000
local MAG_LO=-24 -- ниже этого кривую не рисуем (а не прижимаем к низу)
local function fx(f,x,w) return x+w*math.log(clamp(f,F_LO,F_HI)/F_LO)/math.log(F_HI/F_LO) end
local function xf(px,x,w) return F_LO*(F_HI/F_LO)^clamp((px-x)/w,0,1) end
local fdrag
local MIN_SEP=1.5 -- HP и LP не сходятся ближе, чем в 1.5 раза по частоте
local HPK,LPK='compressor_hp','compressor_lp' -- ключи HP/LP текущего режима (ставятся в M.draw)
local function filter_graph(im,ctx,c,x,y,w,h)
  local dl=im.GetWindowDrawList(ctx);local cfg=c.cfg;local font=im.GetFontSize(ctx)
  local fs=math.max(8,font-3)
  im.SetCursorScreenPos(ctx,x,y);im.InvisibleButton(ctx,'##comp2_filter',w,h)
  local hovered,active=im.IsItemHovered(ctx),im.IsItemActive(ctx)
  local mx=im.GetMousePos(ctx)
  local function pos(key) -- узел: частота (выключенный стоит на краю)
    local f=cfg[key]
    if key==HPK then return f>1 and f or F_LO end
    return f<19999 and f or F_HI
  end
  -- 1) ввод до отрисовки: узел и кривая в этом же кадре уже на новом месте (без отставания и дёрганья)
  local hot
  if hovered and not fdrag then
    local best=12
    for i,key in ipairs({HPK,LPK}) do
      local dd=math.abs(mx-fx(pos(key),x,w));if dd<best then best,hot=dd,i end
    end
    if not hot then hot=mx<x+w/2 and 1 or 2 end
  end
  if im.IsItemActivated(ctx) and hot then fdrag=hot end
  if active and fdrag then
    c.gesture=true
    local f=xf(mx,x,w)
    local key=fdrag==1 and HPK or LPK
    if fdrag==1 then
      local lp=cfg[LPK]<19999 and cfg[LPK] or F_HI
      f=math.min(f,lp/MIN_SEP);if f<=F_LO*1.05 then f=0 end
    else
      local hp=cfg[HPK]>1 and cfg[HPK] or F_LO
      f=math.max(f,hp*MIN_SEP);if f>=F_HI*.97 then f=20000 end
    end
    if f~=cfg[key] then cfg[key]=f;W.changed(c,key) end
    im.SetMouseCursor(ctx,im.MouseCursor_ResizeEW)
  end
  if im.IsItemDeactivated(ctx) and fdrag then fdrag=nil;c:control_released() end
  if hovered and hot and im.IsMouseDoubleClicked(ctx,0) then
    local key=hot==1 and HPK or LPK
    cfg[key]=Settings.defaults[key];W.changed(c,key);c:control_released()
  end
  -- 2) рисунок
  for _,f in ipairs({100,1000,10000}) do local gx=fx(f,x,w);im.DrawList_AddLine(dl,gx,y+3,gx,y+h-3,0xFFFFFF0A) end
  local hp_on,lp_on=cfg[HPK]>1,cfg[LPK]<19999
  local top,bot=y+16,y+h -- заливка до нижнего края панели, подписи лежат поверх
  local function mag(f) -- 2-й порядок (биквад в engine.lua), dB
    local m=0
    if hp_on then local r=(f/cfg[HPK])^4;m=m+10*math.log(r/(1+r),10) end
    if lp_on then local r=(f/cfg[LPK])^4;m=m-10*math.log(1+r,10) end
    return m
  end
  local function ym(m) return top+(bot-top)*clamp(-m/-MAG_LO,0,1) end
  local px_,py_
  for i=0,math.floor(w)-1 do
    local m=mag(xf(x+i,x,w))
    if m>MAG_LO then
      local yy=ym(m)
      im.DrawList_AddLine(dl,x+i,yy,x+i,bot,0x82716330)
      if px_ then im.DrawList_AddLine(dl,px_,py_,x+i,yy,0x827163F0,1.5) end
      px_,py_=x+i,yy
    else px_=nil end
  end
  local function hz(f,on) return on and (f>=1000 and string.format('%.1fk',f/1000) or string.format('%d',math.floor(f+.5))) or 'off' end
  for i,key in ipairs({HPK,LPK}) do
    local on=i==1 and hp_on or lp_on;local f=pos(key);local name=i==1 and 'HP' or 'LP'
    local nx=clamp(fx(f,x,w),x+8,x+w-8);local ny=ym(clamp(mag(f),MAG_LO,0)) -- центр узла — ровно на линии
    local lit=hot==i or fdrag==i
    im.DrawList_AddCircleFilled(dl,nx,ny,lit and 6 or 5,on and (lit and 0xB8A292FF or 0x827163FF) or 0x9AA3AFA0)
    im.DrawList_AddCircle(dl,nx,ny,lit and 6 or 5,0x14161AFF,0,1.5)
    local s=name..' '..hz(f,on)
    local sw=small_w(im,ctx,s,fs)
    small(im,ctx,dl,math.floor(i==1 and x+14 or x+w-sw-14),math.floor(y+h-fs-12),lit and 0xE8ECF2FF or 0x9AA3AFC0,s,fs)
    if fdrag==i then Knob.plate(im,ctx,nx,ny+12,name..' '..(on and (hz(f,on)..' Hz') or 'off'),true) end
  end
end

local function section(im,dl,x,y,w,h)
  im.DrawList_AddRectFilled(dl,x,y,x+w,y+h,0xFFFFFF07,8)
end

function M.available(im,ctx) if KNOB_VECTOR then return true end return Knob.available_skin(im,ctx,'Sp_58.png') and Knob.available_skin(im,ctx,'Sp_48.png') and Knob.available_skin(im,ctx,'Sp_40.png') end

-- dis — ручки недоступны (нет данных, bypass, идёт анализ Align); job — задача для прогресс-бара
-- Всё лежит в своём child без прокрутки: страница не «гуляет» колесом на пару пикселей.
local function filter_overlay(im,ctx,c,g,ix,y)
  local dl=im.GetWindowDrawList(ctx);local font=im.GetFontSize(ctx)
  S.panel=nil
  local bw,bh=38,24;local bx=g.right-bw-10;local by=y+4
  local pn=S.panel_prev;local mx_,my_=im.GetMousePos(ctx)
  local under=S.filter_open and pn and mx_>=pn[1] and mx_<pn[1]+pn[3] and my_>=pn[2] and my_<pn[2]+pn[4]
  -- под открытой панелью кнопка не существует: иначе она (поданная раньше) перехватывает мышь у правого узла в углу
  local hov=false
  if not under then
    im.SetCursorScreenPos(ctx,bx,by);im.InvisibleButton(ctx,'##comp2_filter_btn',bw,bh)
    hov=im.IsItemHovered(ctx)
    if im.IsItemClicked(ctx,0) then S.filter_open=not S.filter_open;S.opened_at=c.r.time_precise() end
  end
  local on=S.filter_open
  im.DrawList_AddRectFilled(dl,bx,by,bx+bw,by+bh,(on or hov) and 0x78787890 or 0x6A6A6A68,bh/2)
  local fs=math.max(8,font-3);local tw=small_w(im,ctx,'Filter',fs)
  small(im,ctx,dl,bx+(bw-tw)/2,math.floor(by+(bh-fs)/2-2.5),on and 0xFFFFFFE8 or 0xFFFFFFB8,'Filter',fs)
  if not S.filter_open then return end
  -- «модалка» поверх кнопки (правый верхний угол панели совпадает с углом кнопки), небольшая; закрывается крестиком,
  -- Esc или кликом мимо панели. Внутренние отступы 8 px.
  local pw,ph=220,96;local px,py=bx+bw-pw,by -- правый верхний угол панели = угол кнопки
  S.panel={px,py,pw,ph};S.panel_prev=S.panel
  im.DrawList_AddRectFilled(dl,px,py,px+pw,py+ph,0x1E1E1EF6,10)
  im.DrawList_AddRect(dl,px,py,px+pw,py+ph,0xFFFFFF30,10)
  filter_graph(im,ctx,c,px,py,pw,ph) -- график заливает панель до краёв; отступы только у подписей и узлов
  -- потеря фокуса: клик мимо панели (кроме самой кнопки) или Esc
  local mx,my=im.GetMousePos(ctx)
  local outside=not (mx>=px and mx<px+pw and my>=py and my<py+ph)
  local on_btn=mx>=bx and mx<bx+bw and my>=by and my<by+bh
  if S.filter_open and c.r.time_precise()>(S.opened_at or 0)+.05 and ((outside and not on_btn and im.IsMouseClicked(ctx,0))
     or im.IsKeyPressed(ctx,im.Key_Escape,false)) then S.filter_open=false end
end


-- ===== кнопки-«пилюли» поверх семплера =====
local function pill(im,ctx,id,bx,by,bw,bh,on,draw_glyph)
  local dl=im.GetWindowDrawList(ctx)
  im.SetCursorScreenPos(ctx,bx,by);im.InvisibleButton(ctx,id,bw,bh)
  local hov=im.IsItemHovered(ctx);local clicked=im.IsItemClicked(ctx,0)
  im.DrawList_AddRectFilled(dl,bx,by,bx+bw,by+bh,on and 0x8A5A2CB0 or ((hov) and 0x78787890 or 0x6A6A6A68),bw==bh and 6 or bh/2) -- квадратная — со скруглением 6
  draw_glyph(dl,bx+bw/2,by+bh/2,(on or hov) and 0xFFFFFFF0 or 0xFFFFFFB8)
  return clicked,hov
end
local function power_glyph(im,dl,cx,cy,r,col)
  local q=-math.pi/2
  im.DrawList_PathArcTo(dl,cx,cy,r,q+0.65,q+2*math.pi-0.65);im.DrawList_PathStroke(dl,col,0,1.5)
  im.DrawList_PathLineTo(dl,cx,cy-r-1.2);im.DrawList_PathLineTo(dl,cx,cy-r*.25);im.DrawList_PathStroke(dl,col,0,1.5)
end

-- ===== скрыть/показать огибающую громкости айтемов (кнопка Hide) =====
local function volume_envs(c)
  local out={};local r=c.r
  for _,d in ipairs(c.targets or {c:current()}) do
    local s=d and d.snapshot
    if s and r.ValidatePtr2(c.project,s.item,'MediaItem*') then
      local take=r.GetActiveTake(s.item);local env=take and r.GetTakeEnvelopeByName(take,'Volume')
      if env then out[#out+1]=env end
    end
  end
  return out
end
local function env_visible(c)
  local now=c.r.time_precise()
  if S.vis_at and now<S.vis_at+.5 and S.vis_target==c:current() then return S.vis end
  local vis=false
  for _,env in ipairs(volume_envs(c)) do
    local ok,ch=c.r.GetEnvelopeStateChunk(env,'',false)
    if ok and (tonumber(ch:match('\nVIS%s+(%d)')) or 1)~=0 then vis=true;break end
  end
  S.vis,S.vis_at,S.vis_target=vis,now,c:current();return vis
end
local function env_set_visible(c,on)
  local r=c.r;r.Undo_BeginBlock2(c.project)
  for _,env in ipairs(volume_envs(c)) do
    local ok,ch=r.GetEnvelopeStateChunk(env,'',false)
    if ok then
      local nch=ch:gsub('\nVIS%s+%d',on and '\nVIS 1' or '\nVIS 0',1)
      if nch~=ch then r.SetEnvelopeStateChunk(env,nch,false) end
    end
  end
  r.Undo_EndBlock2(c.project,on and 'Vocaligner: show volume envelope' or 'Vocaligner: hide volume envelope',-1)
  r.UpdateArrange();S.vis_at=nil
end
-- кнопка Hide под кнобами левой панели (общая для Compressor / Gate / De-ess; Breath зовёт M.hide_button)
function M.hide_button(im,ctx,c,x,y,w)
  local vis=env_visible(c);local label=vis and 'Hide' or 'Show'
  local bw,bh=math.min(w,88),24
  im.SetCursorScreenPos(ctx,x+(w-bw)/2,y)
  if im.Button(ctx,label..'##vol_env_vis',bw,bh) then env_set_visible(c,not vis) end
  if im.IsItemHovered(ctx) then im.SetTooltip(ctx,vis and 'Hide the volume envelope of the processed items in REAPER' or 'Show the volume envelope again') end
end

-- ===== ручной режим (De-ess): правка отдельных сибилянтов =====
-- Колесо — зум вокруг мыши, средняя кнопка / Shift+перетаскивание — сдвиг; линейка сверху ставит курсор.
-- Над сибилянтом: середина — тянуть вверх/вниз (слабее/сильнее), края — тянуть влево/вправо, иконка — вкл/выкл,
-- двойной клик — сбросить правку. Ctrl — видна применённая огибающая; Ctrl+перетаскивание — нарисовать свою.
local function rdp(pts,eps)
  if #pts<3 then return pts end
  local keep={[1]=true,[#pts]=true}
  local function walk(i,j)
    local a,b=pts[i],pts[j];local best,bi=0
    for k=i+1,j-1 do
      local p=pts[k];local f=(p.t-a.t)/math.max(1e-9,b.t-a.t);local dv=math.abs(p.db-(a.db+(b.db-a.db)*f))
      if dv>best then best,bi=dv,k end
    end
    if bi and best>eps then keep[bi]=true;walk(i,bi);walk(bi,j) end
  end
  walk(1,#pts)
  local out={};for i,p in ipairs(pts) do if keep[i] then out[#out+1]=p end end;return out
end
-- Область события на экране: ядро (с ручными границами) вместе с рампами Pre-open / Release — то, что реально
-- подсвечено как подавление; edge_shift — насколько рампа выходит за ядро слева/справа (для перетаскивания края)
local function ev_range(e) local x=e.edit;return (x and x.a) or e.start,(x and x.b) or e.finish end
local function ev_span(d,e)
  local a,b=ev_range(e);local ea,eb=a,b
  for _,r in ipairs(d.effect_regions or {}) do if r.start<b and r.finish>a then ea=math.min(ea,r.start);eb=math.max(eb,r.finish) end end
  return ea,eb,a-ea,eb-b
end
local function edit_page(im,ctx,c,d,color,dis,x,y,aw,ah,wx,wy,ww,wh,round)
  local dl=im.GetWindowDrawList(ctx)
  local data=d and (d.audio or d.quick)
  local NAVB=14
  local top,bottom=wy,y+ah-NAVB-4 -- «плеер» от верха страницы до обзорной полосы
  local left,right=wx,wx+ww
  if data then
    d.view=d.view or {start=data.pos,span=data.len}
    local v=d.view;v.span=clamp(v.span,.05,data.len);v.start=clamp(v.start,data.pos,data.pos+data.len-v.span)
  end
  local v=d and d.view
  local tr=Transport.read(c.r,c.project)
  if v and data then Transport.follow(d,c.r,tr,v,0,data.pos,data.pos+data.len,S.ed~=nil) end
  local g=player(im,ctx,c,d,left,top,right-left,bottom-top,color,round,{edit=true,view=v})
  local function tx(t) return g.px0+(t-g.start)/g.pt end -- t — время проекта
  local function tt(px) return g.start+(px-g.px0)*g.pt end
  local mx,my=im.GetMousePos(ctx)
  local events=d and d.detected and d.detected.sibilants or {}
  local inside=mx>=x and mx<x+aw and my>=y and my<bottom
  local free=inside and im.IsWindowHovered(ctx) and not im.IsAnyItemHovered(ctx) and not im.IsAnyItemActive(ctx) and not dis
  local ctrl=(im.GetKeyMods(ctx)&im.Mod_Ctrl)~=0
  local wy0,wy1=g.py0,g.py0+g.ph
  local now=c.r.time_precise();local dt=clamp(now-(S.ed_t or now),0,.1);S.ed_t=now
  S.glow=S.glow or {}
  local hot,hot_part
  S.thr_near=free and not S.ed and math.abs(my-g.ty)<6 and mx<g.sx -- пунктир порога: тянется и в ручном режиме
  S.thr_hot=S.thr_near or (S.ed and S.ed.kind=='thr') or nil
  if data then
    for _,e in ipairs(events) do
      local ea,eb=ev_span(d,e)
      local xa,xb=tx(data.pos+ea),tx(data.pos+eb)
      if xb>g.px0 and xa<g.right then
        local over=free and not S.ed and not S.thr_near and mx>=xa-4 and mx<=xb+4
        if over then
          hot=e
          if not ctrl and math.abs(mx-xa)<=4 then hot_part='L' elseif not ctrl and math.abs(mx-xb)<=4 then hot_part='R' else hot_part='G' end
        end
        -- подсветка: мягкая, плавно нарастает к основанию события; у активного — ярче; выключенные — серые
        local want=((over or (S.ed and S.ed.e==e)) and 1 or 0)
        local gv=S.glow[e] or 0;gv=gv+(want-gv)*math.min(1,dt*14);S.glow[e]=gv
        local base=e.excluded and 0x80808000 or 0xE8B06A00
        local a0=e.excluded and .10 or (.05+.10*gv);local a1=e.excluded and .02 or (.0+.05*gv)
        if im.DrawList_AddRectFilledMultiColor then
          im.DrawList_AddRectFilledMultiColor(dl,xa,wy0,xb,wy1,fa(base|255,a1),fa(base|255,a1),fa(base|255,a0),fa(base|255,a0))
          if gv>.02 then -- лёгкое «распылённое» свечение по бокам
            for k=1,3 do local sp=k*4;local al=.035*gv/k
              im.DrawList_AddRectFilledMultiColor(dl,xa-sp,wy0,xa,wy1,fa(base|255,0),fa(base|255,al*.3),fa(base|255,al),fa(base|255,0))
              im.DrawList_AddRectFilledMultiColor(dl,xb,wy0,xb+sp,wy1,fa(base|255,al*.3),fa(base|255,0),fa(base|255,0),fa(base|255,al))
            end
          end
        end
        if e.edit then im.DrawList_AddLine(dl,xa,wy1-1,xb,wy1-1,0xF2B15A90,2) end -- метка: у события есть ручная правка
      end
    end
  end
  -- Ctrl: применённая огибающая (снижение вниз от 0 dB по шкале справа)
  if data and (ctrl or (S.ed and S.ed.kind=='draw')) then
    local curve=d.tool_preview;local prv
    for px=math.floor(g.px0),math.floor(g.right),2 do
      local r_=curve and Cleanup.value(curve,tt(px)-data.pos) or 0
      local yy=clamp(g.ydb(-r_),wy0,wy1)
      if prv then im.DrawList_AddLine(dl,px-2,prv,px,yy,0xF29A5AE0,1.5) end
      prv=yy
    end
  end
  if S.ed and S.ed.kind=='draw' and data then
    local p=S.ed.pts
    for i=2,#p do im.DrawList_AddLine(dl,tx(data.pos+p[i-1].t),clamp(g.ydb(-p[i-1].db),wy0,wy1),tx(data.pos+p[i].t),clamp(g.ydb(-p[i].db),wy0,wy1),0xFFFFFFF0,2) end
  end
  Transport.draw(im,dl,tr,tx,g.px0,g.right,wy0,wy1)
  -- горячие клавиши ручного режима: F — весь айтем, Ctrl+Z / Ctrl+Shift+Z (Ctrl+Y) — отмена/повтор правок событий
  if data and v and im.IsWindowFocused(ctx,im.FocusedFlags_RootAndChildWindows) and not im.IsAnyItemActive(ctx) then
    local mods=im.GetKeyMods(ctx)
    if im.IsKeyPressed(ctx,im.Key_F,false) and mods==0 then v.start=data.pos;v.span=data.len;Transport.hold(d,c.r) end
    if (mods&im.Mod_Ctrl)~=0 and im.IsKeyPressed(ctx,im.Key_Z,false) then c:edits_undo(d,(mods&im.Mod_Shift)~=0) end
    if (mods&im.Mod_Ctrl)~=0 and im.IsKeyPressed(ctx,im.Key_Y,false) then c:edits_undo(d,true) end
  end
  -- ввод
  if free and v then
    local wheel=im.GetMouseWheel(ctx)
    if wheel~=0 then
      local f=clamp((mx-g.px0)/(g.right-g.px0),0,1);local span=clamp(v.span*1.2^(-wheel),.05,data.len)
      v.start=v.start+f*(v.span-span);v.span=span;Transport.hold(d,c.r)
    end
    if S.thr_near then im.SetMouseCursor(ctx,im.MouseCursor_ResizeNS)
    elseif hot_part=='L' or hot_part=='R' then im.SetMouseCursor(ctx,im.MouseCursor_ResizeEW)
    elseif hot_part=='G' and not ctrl then im.SetMouseCursor(ctx,im.MouseCursor_ResizeNS) end
    local shift=(im.GetKeyMods(ctx)&im.Mod_Shift)~=0
    if im.IsMouseClicked(ctx,2) then S.ed={kind='pan',btn=2}
    elseif hot and im.IsMouseClicked(ctx,1) then c:edits_push(d);c:toggle_region(d,hot) -- ПКМ: вкл/выкл, как раньше
    elseif shift and im.IsMouseClicked(ctx,0) then S.ed={kind='pan',btn=0}
    elseif hot and hot_part=='G' and not ctrl and im.IsMouseDoubleClicked(ctx,0) then
      if hot.edit then c:edits_push(d);c:edit_region(d,hot,function() return false end) end;S.ed=nil
    elseif im.IsMouseClicked(ctx,0) then
      if S.thr_near then S.ed={kind='thr',y0=my,v0=c.cfg[SP.thr]}
      elseif ctrl and hot then -- Ctrl: рисуем снижение в пределах этого события; база — то, что применено сейчас
        local ea,eb=ev_span(d,hot);local pad=math.max(.08,(eb-ea)*.5);ea=math.max(0,ea-pad);eb=math.min(data.len,eb+pad) -- с запасом по краям
        local n=math.max(8,math.floor((tx(data.pos+eb)-tx(data.pos+ea))/3))
        local pts={};for i=0,n do local t=ea+(eb-ea)*i/n;pts[#pts+1]={t=t,db=d.tool_preview and Cleanup.value(d.tool_preview,t) or 0} end
        c:edits_push(d);S.ed={kind='draw',e=hot,pts=pts,a=ea,b=eb}
      elseif hot and hot_part=='G' then
        local g0=(hot.edit and hot.edit.gain) or 1;c:edits_push(d);S.ed={kind='G',e=hot,y0=my,g0=g0,g=g0}
      elseif hot and (hot_part=='L' or hot_part=='R') then
        local a,b=ev_range(hot);local ea,eb,sl,sr=ev_span(d,hot);c:edits_push(d)
        S.ed={kind=hot_part,e=hot,t=hot_part=='L' and a or b,off=hot_part=='L' and sl or sr}
      else S.ed={kind='click',x0=mx} end
    end
  end
  if S.ed and data then
    local e=S.ed.e
    if im.IsMouseDown(ctx,S.ed.btn or 0) then
      c.gesture=true
      local rel=tt(mx)-data.pos
      if S.ed.kind=='thr' then
        local e_=E[SP.thr];local fine=(im.GetKeyMods(ctx)&im.Mod_Shift)~=0 and .1 or 1
        local val=clamp(S.ed.v0-(my-S.ed.y0)*(DB_HI-DB_LO)/g.ph*fine,e_[3],e_[4])
        if math.abs(val-c.cfg[SP.thr])>1e-9 then c.cfg[SP.thr]=val;W.changed(c,SP.thr) end
        im.SetMouseCursor(ctx,im.MouseCursor_ResizeNS)
        Knob.plate(im,ctx,mx,g.ty-8,string.format('Threshold %.1f dB',val),false,nil,true)
      elseif S.ed.kind=='pan' then local dx=im.GetMouseDelta(ctx);v.start=clamp(v.start-dx*g.pt,data.pos,data.pos+data.len-v.span);Transport.hold(d,c.r)
      elseif S.ed.kind=='G' then -- вверх — слабее, вниз — сильнее; применяется сразу
        local gnew=clamp(S.ed.g0*2^((my-S.ed.y0)/16),0,8) -- 16 px на удвоение, до ×8
        do -- направляющая: шкала множителя с отметками ×1 (по умолчанию) и пределов, бегунок — текущее
          local ea,eb=ev_span(d,e);local gx=(tx(data.pos+ea)+tx(data.pos+eb))/2
          local function gy(gv) return S.ed.y0+16*(math.log(math.max(gv,1/64),2)-math.log(math.max(S.ed.g0,1/64),2)) end
          local y8,y1,y0_=gy(8),gy(1),gy(1/8)
          im.DrawList_AddLine(dl,gx,math.min(y8,y0_),gx,math.max(y8,y0_),0xFFFFFF50,1)
          for _,m in ipairs({{y8,'×8'},{y1,'×1'},{y0_,'0'}}) do im.DrawList_AddLine(dl,gx-5,m[1],gx+5,m[1],0xFFFFFFA0,1);small(im,ctx,dl,gx+8,m[1]-6,0xFFFFFFA0,m[2],11) end
          im.DrawList_AddCircleFilled(dl,gx,gy(gnew),4,0xF2B15AFF)
        end
        im.SetMouseCursor(ctx,im.MouseCursor_ResizeNS)
        if math.abs(gnew-S.ed.g)>.004 then S.ed.g=gnew;c:edit_region(d,e,function(xe) xe.gain=gnew end) end
        Knob.plate(im,ctx,mx,my-12,string.format('×%.2f',S.ed.g),true,nil,true)
      elseif S.ed.kind=='L' or S.ed.kind=='R' then -- край тянется вместе с рампой; ядро сдвигается на ту же величину
        local a,b=ev_range(e);local k=S.ed.kind
        local tnew=k=='L' and clamp(rel+S.ed.off,0,b-.005) or clamp(rel-S.ed.off,a+.005,data.len)
        im.SetMouseCursor(ctx,im.MouseCursor_ResizeEW)
        if math.abs(tnew-S.ed.t)>g.pt*.5 then S.ed.t=tnew;c:edit_region(d,e,function(xe) if k=='L' then xe.a=tnew else xe.b=tnew end end) end
      elseif S.ed.kind=='draw' then -- кисть: от прошлой точки мыши до текущей, только внутри события
        local db=clamp(-(DB_HI-(my-g.py0)/g.ph*(DB_HI-DB_LO)),0,36)
        local t=clamp(rel,S.ed.a,S.ed.b);local p0t,p0d=S.ed.lt or t,S.ed.ld or db
        local lo_,hi_=math.min(p0t,t),math.max(p0t,t);local changed=false
        for _,p in ipairs(S.ed.pts) do
          if p.t>=lo_-g.pt and p.t<=hi_+g.pt then
            local f=hi_>lo_ and (p.t-p0t)/(t-p0t) or 1;local val=p0d+(db-p0d)*clamp(f,0,1)
            if math.abs(p.db-val)>.01 then p.db=val;changed=true end
          end
        end
        S.ed.lt,S.ed.ld=t,db
      end
    else -- отпустили
      local k=S.ed.kind
      if k=='thr' then
      elseif k=='draw' then
        local detail=c.cfg.deess_detail or 85
        c:add_curve(d,'sibilant',rdp(S.ed.pts,.05+(100-detail)/100*.6)) -- точность упрощения от Detail
      elseif k=='click' and math.abs(mx-S.ed.x0)<3 then c:seek(tt(mx)-data.pos) end
      c.gesture=false;c:control_released()
      S.ed=nil
    end
  elseif S.ed and not im.IsMouseDown(ctx,S.ed.btn or 0) then S.ed=nil end
  -- обзорная полоса снизу (узкая): весь айтем, снижение, рамка вида — тянется
  im.SetCursorScreenPos(ctx,x,y+ah-NAVB)
  Canvas.navigator(im,ctx,d,aw,NAVB,c.r,c.project)
  return g
end

-- плавное приближение значения: раскладка не «прыгает» при смене айтема/режима, а доезжает
local function ease_to(key,target,dt)
  local cur=S.lay[key]
  if cur==nil or math.abs(target-cur)<.4 then S.lay[key]=target;return target end
  cur=cur+(target-cur)*math.min(1,dt*12);S.lay[key]=cur;return cur
end
S.lay={}

function M.draw(im,ctx,c,color,dis,job)
  SP=SPECS[c.mode] or SPECS.compressor;DB_LO,DB_HI=SP.lo,SP.hi
  local editing=S.edit and SP.editable;if editing then DB_HI=6 end -- в правке шкала до +6 dB: детальнее
  if SP.filter then HPK,LPK=SP.filter..'hp',SP.filter..'lp' end
  if S.mode~=c.mode then S.mode=c.mode;S.meter=nil;S.filter_open=false end
  local d=c:current()
  local x,y=im.GetCursorScreenPos(ctx);local aw,ah=im.GetContentRegionAvail(ctx)
  -- «плеер» уходит до правого, верхнего и нижнего края страницы (поверх её полей)
  local wx,wy=im.GetWindowPos(ctx);local ww,wh=im.GetWindowSize(ctx)
  local round=im.StyleVar_ChildRounding and im.GetStyleVar(ctx,im.StyleVar_ChildRounding) or 0
  if type(round)~='number' then round=0 end
  local child=im.BeginChild and im.WindowFlags_NoScrollbar
  if child then
    im.PushStyleVar(ctx,im.StyleVar_WindowPadding,0,0)
    im.BeginChild(ctx,'##comp2',aw,ah,0,im.WindowFlags_NoScrollbar|im.WindowFlags_NoScrollWithMouse|im.WindowFlags_NoBackground)
    im.PopStyleVar(ctx)
  end
  if S.font_ctx~=ctx then -- шрифт подписей под кнобами (создаётся один раз на контекст)
    S.font_ctx=ctx;Knob.label_font=nil
    local ok,f=pcall(im.CreateFont,(reaper.GetOS() or ''):find('Win') and 'Segoe UI Semibold' or 'sans-serif',12)
    if ok and f then im.Attach(ctx,f);Knob.label_font=f end
  end
  local font=im.GetFontSize(ctx);local dl=im.GetWindowDrawList(ctx)
  if editing then
    local g=edit_page(im,ctx,c,d,color,dis,x,y,aw,ah,wx,wy,ww,wh,round)
    local ui=c.app and c.app.ui_icon
    if pill(im,ctx,'##comp2_edit',g.right-34,y+4,24,24,true,function(dl_,cx,cy,col) if ui then ui(dl_,1,cx,cy,17,col) end end) then S.edit=false;S.ed=nil end
    im.SetCursorScreenPos(ctx,x,y);im.Dummy(ctx,1,1)
    if child then im.EndChild(ctx) end
    return
  end
  local BIGPX,MIDPX,MINIPX=58,48,40 -- размеры кнобов
  local PX={big=BIGPX,mid=MIDPX}
  local cellh=BIGPX+font+2 -- кноб + подпись под ним (вплотную)
  local pw=math.floor(math.max(190,aw*.3)) -- панель кнобов слева
  -- высота и верх страницы доезжают плавно: при выборе айтема (появилась/исчезла кнопка Get и т.п.) кнобы не прыгают
  local now_=c.r.time_precise();local dt=clamp(now_-(S.lay_t or now_),0,.1);S.lay_t=now_
  -- зум семплера колесом: плавно, как в редакторе нот (Settings → Smooth scroll and zoom), иначе сразу
  if S.span_t then
    if c.app and c.app.ui_smooth==false then S.span=S.span_t
    else S.span=S.span*(S.span_t/S.span)^math.min(1,dt*14) end -- в логарифме: шаги зума выглядят одинаково
    if math.abs(S.span/S.span_t-1)<.002 then S.span=S.span_t;S.span_t=nil end
  end
  -- плавно доезжает только отступ страницы от верха окна (кнопка Get и т.п.); перемещение и размер окна — сразу
  local y0=y;local top=ease_to('top',y-wy,dt);y=wy+top
  local h=math.max(80,ah-Progress.height-2+(y0-y))
  local sx0=x+pw-96;local sx1=wx+ww;local sy1=wy+wh -- «плеер» заходит под панель кнобов: волна видна за ними
  local g=player(im,ctx,c,d,sx0,wy,sx1-sx0,sy1-wy,color,round)
  local ix=math.max(sx0,x+pw)
  -- ряд кнобов по центру ВИДИМОЙ части семплера (от панели до шкалы dB)
  im.BeginDisabled(ctx,dis)
  local total=0;for _,k in ipairs(SP.row) do k.w=PX[k[3]]+20;total=total+k.w end
  local kx=ix+(g.sx-ix-total)/2
  local ky_bottom=math.min(y+h,sy1-8)-font-18 -- низ кнобов (над подписью и краем)
  for _,k in ipairs(SP.row) do
    local px=PX[k[3]]
    im.SetCursorScreenPos(ctx,kx,ky_bottom-px)
    local o={skin=skin(px),scale=1,grow=.05,animate=true,vector=KNOB_VECTOR,size=px,width=k.w,float=true,below=true};for kk,v in pairs(k[4]) do o[kk]=v end
    Knob.control(im,ctx,c,entry(k[1],k[2]),nil,o)
    kx=kx+k.w
  end
  im.EndDisabled(ctx)

  -- панель слева: две большие ручки над парой мелких по центру между ними; блок чуть выше середины высоты страницы
  local lx=x+10
  if pw>=170 then
    im.BeginDisabled(ctx,dis)
    local cwm=74 -- колонка мелкого кноба (влезает подпись «Env interval»)
    local cw=cwm*2+2
    local smallh=MINIPX+font+2
    local mgap=6;local rowg=14
    local total_h=cellh*2+rowg+mgap+smallh
    local sy=y+math.max(4,(h-total_h)/2-14)
    local function knob(cx,cy,k,px,wd)
      im.SetCursorScreenPos(ctx,cx,cy)
      local o={skin=skin(px),scale=1,grow=.05,animate=true,vector=KNOB_VECTOR,size=px,width=wd,float=true,below=true};for kk,v in pairs(k[3] or {}) do o[kk]=v end
      Knob.control(im,ctx,c,entry(k[1],k[2]),nil,o)
    end
    knob(lx,sy,SP.big[1],BIGPX,cw)
    knob(lx,sy+cellh+rowg,SP.big[2],BIGPX,cw)
    local sy2=sy+cellh*2+rowg+mgap
    knob(lx,sy2,SP.mini[1],MINIPX,cwm)
    knob(lx+cwm+2,sy2,SP.mini[2],MINIPX,cwm)
    M.hide_button(im,ctx,c,lx,sy2+smallh+18,cw)
    im.EndDisabled(ctx)
    if dis then W.catch(im,ctx,x,y,pw,h,'##comp2_catch') end
  end
  if SP.filter then filter_overlay(im,ctx,c,g,ix,y) else S.panel=nil end
  if SP.editable then -- кнопка ручного режима (карандаш) в правом верхнем углу семплера
    local ui=c.app and c.app.ui_icon
    if pill(im,ctx,'##comp2_edit',g.right-34,y+4,24,24,false,function(dl_,cx,cy,col) if ui then ui(dl_,1,cx,cy,17,col) end end) then S.edit=true;S.ed=nil end
    if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Manual edit: adjust single sibilants') end
  end
  player_input(im,ctx,c,d,ix,y,x+aw-ix,h,g,dis) -- последним: реагирует, только когда мышь не над элементом
  -- прогресс-бар под панелью кнопок
  local now=c.r.time_precise();local ph_=Progress.height
  if Progress.visible(job,now) then
    local p=math.max(0,math.min(1,job.progress or 0))
    local a,b
    if p>0 then a,b=0,p else local f=(now-job.created_at)*.65%1;a=(1-math.abs(f*2-1))*.84;b=a+.16 end
    im.DrawList_AddRectFilled(dl,x+pw*a,y0+h+2,x+pw*b,y0+h+2+ph_,0x78C8ADCC,2)
  end
  im.SetCursorScreenPos(ctx,x,y0);im.Dummy(ctx,1,1)
  if child then im.EndChild(ctx) end
end
return M
