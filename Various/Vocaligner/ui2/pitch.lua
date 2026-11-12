-- @noindex
-- Pitch editor в новом интерфейсе. Холст и логика правок — pitch/ui.lua и pitch/editor.lua (оригиналы работают как раньше);
-- здесь только панель инструментов, которая занимает место второго топбара (оболочка ui2.lua сжимает его вдвое),
-- и тело вкладки. Вместо прежнего ряда кнопок: кнопка «назад», Analyze, контейнер иконок-инструментов без отступов,
-- Tracks, Source и параметры инструмента, которые двигаются мышью в любом направлении. Подсказки — облачка оболочки.
local import=...;local PitchUI=import('pitch/ui');local Link=import('pitch/link');local Workspace=import('pitch/workspace')
local Curve=import('pitch/curve');local Scale=import('pitch/scale');local Progress=import('progress');local M={}
local Hotkeys=import('hotkeys');local Poly=import('pitch/poly');local PolyExport=import('pitch/poly_export');local Glyph=import('pitch/glyph');local Audio=import('audio')
local PolyRec,PolyEditor -- запись Polyphonic и редактор текущего кадра (для слоёв холста)
local VIEW_SECTION -- задаётся ниже, рядом с показом нот
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end

-- Инструменты: порядок и названия (id = e.tool); в «⋯» — остальные, Bounds пока недоступен
local TOOLS={{'notes','Edit'},{'transition','Transition'},{'modulation','Modulation'},{'curve','Curve'},{'split','Split'},{'draw','Draw'}}
local MORE={{'drift','Drift'},{'flatten','Flatten'},{'vibrato','Vibrato'},{'bounds','Bounds',true}}
local BTN_W=36

-- ===== иконки инструментов, рисуются векторно (k — масштаб; box ~20k px вокруг cx,cy) =====
local ICON={}
function ICON.transition(im,dl,cx,cy,col,k)
  im.DrawList_AddRectFilled(dl,cx-9*k,cy+1.5*k,cx-2*k,cy+4.5*k,col,1.5*k)
  im.DrawList_AddRectFilled(dl,cx+2*k,cy-4.5*k,cx+9*k,cy-1.5*k,col,1.5*k)
  im.DrawList_PathLineTo(dl,cx-2*k,cy+3*k);im.DrawList_PathBezierCubicCurveTo(dl,cx+1.5*k,cy+3*k,cx-1.5*k,cy-3*k,cx+2*k,cy-3*k)
  im.DrawList_PathStroke(dl,col,0,1.6*k)
end
function ICON.modulation(im,dl,cx,cy,col,k)
  for i=0,16 do im.DrawList_PathLineTo(dl,cx+(-8+i)*k,cy+math.sin(i/16*math.pi*3)*4.2*k) end
  im.DrawList_PathStroke(dl,col,0,1.7*k)
end
function ICON.curve(im,dl,cx,cy,col,k)
  im.DrawList_PathLineTo(dl,cx-8*k,cy+4.5*k);im.DrawList_PathBezierCubicCurveTo(dl,cx-2*k,cy-9*k,cx+2*k,cy+9*k,cx+8*k,cy-4.5*k)
  im.DrawList_PathStroke(dl,col,0,1.7*k)
  im.DrawList_AddCircleFilled(dl,cx-8*k,cy+4.5*k,2.1*k,col);im.DrawList_AddCircleFilled(dl,cx+8*k,cy-4.5*k,2.1*k,col)
end
function ICON.split(im,dl,cx,cy,col,k)
  im.DrawList_AddRectFilled(dl,cx-9*k,cy-2.5*k,cx-1.5*k,cy+2.5*k,col,1.5*k)
  im.DrawList_AddRectFilled(dl,cx+1.5*k,cy-2.5*k,cx+9*k,cy+2.5*k,col,1.5*k)
  im.DrawList_AddLine(dl,cx,cy-8*k,cx,cy+8*k,col,1.3*k)
end
function ICON.more(im,dl,cx,cy,col,k)
  for i=-1,1 do im.DrawList_AddCircleFilled(dl,cx+i*5.5*k,cy,1.8*k,col) end
end

-- ===== значение, которое двигается мышью в ЛЮБОМ направлении (вправо и вверх — больше, влево и вниз — меньше) =====
local drag_state={}
-- Возвращает changed, value, activated, released (released = закончили движение после изменения)
local function dragvalue(im,ctx,id,label,value,lo,hi,fmt,w,speed,disabled)
  local x,y=im.GetCursorScreenPos(ctx);local h=im.GetFrameHeight(ctx);local dl=im.GetWindowDrawList(ctx)
  im.InvisibleButton(ctx,id,w,h)
  local hovered,active=im.IsItemHovered(ctx),im.IsItemActive(ctx)
  local st=drag_state[id] or {};drag_state[id]=st
  local changed,activated,released=false,false,false
  if not disabled then
    if im.IsItemActivated(ctx) then activated=true;st.edited=false;st.value=value;st.anchor=import('ui2/drag').begin() end
    if active then
      im.SetMouseCursor(ctx,im.MouseCursor_ResizeAll)
      local dx,dy=import('ui2/drag').delta(im,ctx,st.anchor)
      local fine=(im.GetKeyMods(ctx)&im.Mod_Shift)~=0 and .1 or 1
      local delta=(dx-dy)*speed*fine
      if delta~=0 then st.value=clamp((st.value or value)+delta,lo,hi);value=st.value;changed=true;st.edited=true end
    elseif hovered then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
    if st.was_active and not active then released=st.edited==true;st.edited=false end
    st.was_active=active
  end
  local fill=disabled and 0x1E1E1EFF or (active and 0x3A4452FF or (hovered and 0x2E3640FF or 0x262B33FF))
  im.DrawList_AddRectFilled(dl,x,y,x+w,y+h,fill,5)
  local text=label..' '..fmt:format(value)
  local tw,th=im.CalcTextSize(ctx,text)
  im.DrawList_AddText(dl,x+(w-tw)/2,y+(h-th)/2,disabled and 0x5A5A64FF or 0xD6DBE5FF,text)
  return changed,value,activated,released
end

M.dragvalue=dragvalue -- для тестов

-- Плавное увеличение иконки при наведении (и обратно при уходе курсора): сглаженное по кадрам состояние на id
local grow_state={}
local grow_anim=true -- выключается настройкой Animations
local function grow(id,hov)
  local v=grow_state[id] or 0;v=grow_anim and v+((hov and 1 or 0)-v)*0.3 or (hov and 1 or 0)
  if math.abs(v)<0.001 then v=0 end
  grow_state[id]=v;return 1+0.14*v
end
-- выбранное/включённое состояние везде тёмно-оранжевое (инструмент, snap, repeat, aim)
local SEL_FILL,SEL_HOVER=0x944A10FF,0xA2530FFF
local function lerp_col(a,b,t)
  local function ch(sh) local x=(a>>sh)&255;local y=(b>>sh)&255;return math.floor(x+(y-x)*t+0.5)&255 end
  return (ch(24)<<24)|(ch(16)<<16)|(ch(8)<<8)|ch(0)
end
-- Состояния, которые не должны мигать, пока идёт запись bypass/правки: держим последние устойчивые значения ещё чуть после задачи
local stable={analyzed=false,can=false,engaged=false,until_t=0}
local bypass_v=0
-- Индексы иконок в ui2/assets/pitch.png (рисует оболочка: host.icon)
local SP={pencil=1,navigate=2,repeat_on=3,repeat_off=4,magnet=5,magnet_off=6,ghost=7,aim_on=8,aim_off=9}
local SPRITE_TOOL={notes=SP.navigate,draw=SP.pencil} -- инструменты, у которых иконка из спрайта
local ICON_PX=19 -- сторона ячейки иконки инструмента

-- Панель инструментов в прямоугольнике x0,y0,w,h (занимает место второго топбара).
-- Все элементы строки одной высоты. Слева: «назад», Analyze, Bypass, Play|Repeat. По центру: инструменты.
-- Справа: Copy/Paste (Curve), тональность (корень | лад | магнит) и меню. Выпадающие списки — стилевые облачка оболочки.
-- host: tooltip(key,hov,ax,ay,title,text,wx,ww,delay,speed), dropdown(id,ax,ay,items), icon(dl,i,cx,cy,size,col), back(),
--       window={x,w}, pill/pill_hover/accent_fill, settings
function M.toolbar(host,im,ctx,app,x0,y0,w,h)
  local e=app.pitch;local dl=im.GetWindowDrawList(ctx)
  grow_anim=host.settings==nil or host.settings.anim~=false
  local G=host.gap or 7
  local fh=math.min(h-2*G,im.GetFrameHeight(ctx)+2);local y=y0+(h-fh)/2
  local wx,ww=host.window[1],host.window[2]
  local function text_w(t) return (im.CalcTextSize(ctx,t)) end
  local function button_w(t) return text_w(t)+16 end
  local x=x0+G
  local busy=e:busy()
  local TIP_DELAY=0.45

  -- «Назад»
  im.SetCursorScreenPos(ctx,x,y);im.InvisibleButton(ctx,'##pitch_back',fh,fh)
  local bh=im.IsItemHovered(ctx)
  if bh then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
  if im.IsItemClicked(ctx,0) then host.back() end
  im.DrawList_AddRectFilled(dl,x,y,x+fh,y+fh,bh and host.pill_hover or host.pill,8)
  local col=bh and 0xFFFFFFFF or 0xA8A8B6FF
  local gk=grow('back',bh);local bcx,bcy=x+fh/2,y+fh/2
  im.DrawList_AddLine(dl,bcx+3*gk,bcy-6*gk,bcx-3*gk,bcy,col,2);im.DrawList_AddLine(dl,bcx-3*gk,bcy,bcx+3*gk,bcy+6*gk,col,2)
  host.tooltip('pitch_back',bh,bcx,y+fh,'Back to tools','',wx,ww,0.35,0.2)
  x=x+fh+G

  local now=e.r.time_precise()
  local freeze=(e.job~=nil and e.job.kind=='apply') or now<stable.until_t -- bypass/правка: кнопки не мигают
  if e.job~=nil and e.job.kind=='apply' then stable.until_t=now+0.3 end
  local poly=e.mode=='poly'
  -- Режим анализа вместо прежней Analyze: Melodic / Polyphonic. Сам анализ — большая кнопка поверх редактора
  -- (body); выбор режима при выделенном аудио сразу запускает свежий анализ в этом режиме
  do
    local label=poly and 'Polyphonic (no edit)' or 'Melodic'
    local bw=math.max(text_w('Polyphonic (no edit)'),text_w('Melodic'))+30
    im.SetCursorScreenPos(ctx,x,y);im.InvisibleButton(ctx,'##pitch_mode',bw,fh)
    local hv=im.IsItemHovered(ctx) and not busy
    if hv then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
    im.DrawList_AddRectFilled(dl,x,y,x+bw,y+fh,hv and host.pill_hover or host.pill,8)
    local tw,th=im.CalcTextSize(ctx,label)
    im.DrawList_AddText(dl,math.floor(x+10),math.floor(y+(fh-th)/2),busy and 0x8A8A96FF or 0xE6E6F0FF,label)
    local ax,ay=x+bw-12,y+fh/2;im.DrawList_AddTriangleFilled(dl,ax-3.5,ay-1.8,ax+3.5,ay-1.8,ax,ay+2.6,0xA8A8B6FF)
    if im.IsItemClicked(ctx,0) and not busy then
      local pa,why=Poly.available(e.r)
      host.dropdown('pitch_mode',x+bw/2,y+fh,{
        {label='Melodic',checked=not poly,action=function() e:set_mode('melodic') end},
        {label='Polyphonic (no edit)',checked=poly,disabled=not pa,action=function() e:set_mode('poly') end}})
    end
    x=x+bw+G
  end
  if e.job and not e.job.committed and e.job.kind=='analysis' then
    im.SetCursorScreenPos(ctx,x,y);if im.Button(ctx,'Cancel',0,fh) then e:cancel() end
    x=im.GetItemRectMax(ctx)+G
  end

  -- Bypass редактора (иконка питания, как в глобальном BYPASS ALL): показывает оригинальные ноты и отключает ReaPitch
  if not poly then
  if not freeze then
    stable.can=e.state~=nil and e.state.fx_guid~=nil and not e.stale and not e.no_selection and not busy and not e.gesture
    stable.engaged=e.state~=nil and e.state.bypassed==true
  end
  local can_bypass,engaged=stable.can,stable.engaged
  bypass_v=grow_anim and bypass_v+((engaged and 1 or 0)-bypass_v)*0.3 or (engaged and 1 or 0)
  if math.abs(bypass_v-(engaged and 1 or 0))<0.01 then bypass_v=engaged and 1 or 0 end
  im.SetCursorScreenPos(ctx,x,y);im.InvisibleButton(ctx,'##pitch_bypass',fh,fh)
  local byh=im.IsItemHovered(ctx)
  local byc=byh and can_bypass
  if byc then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
  if im.IsItemClicked(ctx,0) and can_bypass and not freeze then e:compare() end
  im.DrawList_AddRectFilled(dl,x,y,x+fh,y+fh,lerp_col(byc and host.pill_hover or host.pill,0xE8955A55,bypass_v),8)
  do
    local gx,gy,q,k=x+fh/2,y+fh/2,-math.pi/2,grow('bypass',byc)
    local idle=not can_bypass and 0x484852FF or (byc and 0xE0E0EAFF or 0x9A9AA8FF)
    local c=lerp_col(idle,0xE8955AFF,bypass_v)
    im.DrawList_PathArcTo(dl,gx,gy,5.4*k,q+0.65,q+2*math.pi-0.65);im.DrawList_PathStroke(dl,c,0,1.7)
    im.DrawList_PathLineTo(dl,gx,gy-6.6*k);im.DrawList_PathLineTo(dl,gx,gy-1.4*k);im.DrawList_PathStroke(dl,c,0,1.7)
  end
  host.tooltip('pitch_bypass',byh,x+fh/2,y+fh,'','Bypass',wx,ww,TIP_DELAY,0.2)
  x=x+fh+G
  end

  -- Транспорт одной секцией: Play/Pause (по реальному состоянию) | Repeat (тёмно-оранжевый, когда включён)
  local proj=e.project or 0
  local looping=e.r.GetSetRepeatEx and e.r.GetSetRepeatEx(proj,-1)==1
  local ps=e.r.GetPlayStateEx and e.r.GetPlayStateEx(proj) or 0
  local playing=(ps&1)~=0 and (ps&2)==0
  im.SetCursorScreenPos(ctx,x,y);im.InvisibleButton(ctx,'##pitch_play',fh,fh)
  local ph=im.IsItemHovered(ctx)
  if ph then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
  if im.IsItemClicked(ctx,0) then if playing then e.r.OnPauseButton() else e.r.OnPlayButton() end end
  im.DrawList_AddRectFilled(dl,x,y,x+fh,y+fh,ph and host.pill_hover or host.pill,8,im.DrawFlags_RoundCornersLeft)
  do
    local cx_,cy_,k=x+fh/2,y+fh/2,grow('play',ph);local c=ph and 0xFFFFFFFF or 0xC8C8D4FF
    if playing then
      im.DrawList_AddRectFilled(dl,cx_-4.2*k,cy_-5.2*k,cx_-1.2*k,cy_+5.2*k,c,1);im.DrawList_AddRectFilled(dl,cx_+1.2*k,cy_-5.2*k,cx_+4.2*k,cy_+5.2*k,c,1)
    else
      im.DrawList_AddTriangleFilled(dl,cx_-3.6*k,cy_-5.6*k,cx_-3.6*k,cy_+5.6*k,cx_+5.6*k,cy_,c)
    end
  end
  im.SetCursorScreenPos(ctx,x+fh,y);im.InvisibleButton(ctx,'##pitch_loop',fh,fh)
  local lh=im.IsItemHovered(ctx)
  if lh then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
  if im.IsItemClicked(ctx,0) and e.r.GetSetRepeatEx then e.r.GetSetRepeatEx(proj,looping and 0 or 1) end
  im.DrawList_AddRectFilled(dl,x+fh,y,x+2*fh,y+fh,looping and (lh and SEL_HOVER or SEL_FILL) or (lh and host.pill_hover or host.pill),8,im.DrawFlags_RoundCornersRight)
  im.DrawList_AddLine(dl,x+fh,y+6,x+fh,y+fh-6,0xFFFFFF10,0.5)
  local lk=grow('loop',lh)
  host.icon(dl,looping and SP.repeat_on or SP.repeat_off,x+fh*1.5-1.5,y+fh/2,(ICON_PX-1)*lk,looping and 0xFFFFFFFF or (lh and 0xE0E0EAFF or 0x9A9AA8FF))
  x=x+2*fh+G
  local left_end=x

  -- Правый блок считаем заранее и прижимаем к правому краю: Copy/Paste (Curve), тональность, меню
  local root_text=Scale.root_name(e.root,e.scale);local mode_text=Scale.scales[e.scale or 1][1] -- полное имя лада (Major, Minor, Dorian…)
  local root_w=math.max(text_w('C#'),text_w('Bb'))+14;local mode_w=math.max(text_w('Major'),text_w(mode_text))+20;local snap_w=fh+4 -- секция лада по ширине текста: имя помещается целиком
  local scale_w=root_w+mode_w+snap_w
  local right={}
  local bpm_src=(poly and e.poly and e.poly.bpm) or (not poly and (e.key_bpm or (e.poly and e.poly.bpm)))
  local bpm_text=bpm_src and bpm_src>0 and string.format('%.1f BPM',bpm_src) or (poly and '— BPM') or nil
  if poly then
    right[#right+1]={'bpm',button_w('000.0 BPM')} -- Polyphonic: тональность — в контроле скейла, темп — рядом
  else
    if e.tool=='curve' then right[#right+1]={'copy',button_w('Copy')};right[#right+1]={'paste',button_w('Paste')} end
    if e.twins and #e.twins>0 then right[#right+1]={'sync',fh} end -- есть копии открытого айтема
    right[#right+1]={'auto',button_w('ATune')}
    if bpm_text then right[#right+1]={'bpm',button_w('000.0 BPM')} end -- темп из анализа тональности
  end
  right[#right+1]={'scale',scale_w}
  local total=-6;for _,r in ipairs(right) do total=total+r[2]+6 end
  local count=#TOOLS+1;local cwid=count*BTN_W
  local rx=x0+w-G-total
  local cx0=math.max(x0+(w-cwid)/2,left_end+10)
  if cx0+cwid+12>rx then cx0=math.max(left_end+4,rx-cwid-12) end

  -- Контейнер инструментов по центру: одна плашка, кнопки впритык (выбранная — акцентная заливка)
  local locked=busy or e.gesture
  if not poly then
  im.DrawList_AddRectFilled(dl,cx0,y,cx0+cwid,y+fh,host.pill,8)
  if busy then im.BeginDisabled(ctx,true) end
  local in_more=false;for _,t in ipairs(MORE) do if e.tool==t[1] then in_more=true end end
  for i=1,count do
    local bx=cx0+(i-1)*BTN_W;local more=i==count;local tool=not more and TOOLS[i] or nil
    im.SetCursorScreenPos(ctx,bx,y);im.InvisibleButton(ctx,'##pitch_tool_'..i,BTN_W,fh)
    local hov=im.IsItemHovered(ctx)
    local selected=more and in_more or (tool and e.tool==tool[1])
    if selected then im.DrawList_AddRectFilled(dl,bx+1.5,y+1.5,bx+BTN_W-1.5,y+fh-1.5,SEL_FILL,7)
    elseif hov then im.DrawList_AddRectFilled(dl,bx+1.5,y+1.5,bx+BTN_W-1.5,y+fh-1.5,0xFFFFFF14,7) end
    local c=selected and 0xFFFFFFFF or (hov and 0xE0E0EAFF or 0x9A9AA8FF)
    local id=more and 'more' or tool[1]
    local gk2=grow('tool'..i,hov)
    if SPRITE_TOOL[id] then host.icon(dl,SPRITE_TOOL[id],bx+BTN_W/2,y+fh/2,ICON_PX*gk2,c)
    else ICON[id](im,dl,bx+BTN_W/2,y+fh/2,c,1.1*gk2) end
    if hov then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
    if im.IsItemClicked(ctx,0) then
      if more then
        local items={}
        for _,t in ipairs(MORE) do items[#items+1]={label=t[2],checked=e.tool==t[1],disabled=t[3],action=function() e.tool=t[1] end} end
        host.dropdown('more',bx+BTN_W/2,y+fh,items)
      else e.tool=tool[1] end
    end
    if more then host.tooltip('pitch_tool_more',hov,bx+BTN_W/2,y+fh,'','More tools',wx,ww,TIP_DELAY,0.2)
    else host.tooltip('pitch_tool_'..tool[1],hov,bx+BTN_W/2,y+fh,'',tool[2]..'\t'..i,wx,ww,TIP_DELAY,0.2) end
  end
  if busy then im.EndDisabled(ctx) end
  end

  for _,r in ipairs(right) do
    local kind=r[1];im.SetCursorScreenPos(ctx,rx,y)
    if kind=='scale' then
      -- тройная кнопка: корень | лад | магнит (snap). Одна плашка высотой и цветом как контейнер инструментов,
      -- секции подсвечиваются при наведении, разделители тонкие
      local a,b,c=rx,rx+root_w,rx+root_w+mode_w
      im.DrawList_AddRectFilled(dl,a,y,c+snap_w,y+fh,host.pill,8)
      local function section(id,x1,x2,label,on)
        im.SetCursorScreenPos(ctx,x1,y);im.InvisibleButton(ctx,id,x2-x1,fh)
        local hv=im.IsItemHovered(ctx)
        if hv then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
        if on then im.DrawList_AddRectFilled(dl,x1+1.5,y+1.5,x2-1.5,y+fh-1.5,SEL_FILL,7)
        elseif hv then im.DrawList_AddRectFilled(dl,x1+1.5,y+1.5,x2-1.5,y+fh-1.5,0xFFFFFF14,7) end
        if label then
          local tw,th=im.CalcTextSize(ctx,label)
          im.DrawList_AddText(dl,math.floor(x1+(x2-x1-tw)/2),math.floor(y+(fh-th)/2),0xE6E6F0FF,label)
        end
        return im.IsItemClicked(ctx,0),hv
      end
      local root_click=section('##pitch_root',a,b,root_text)
      local mode_click=section('##pitch_mode',b,c,mode_text)
      local snap_click,snap_hov=section('##pitch_snap',c,c+snap_w,nil,e.snap==true)
      im.DrawList_AddLine(dl,b,y+7,b,y+fh-7,0xFFFFFF10,0.5);im.DrawList_AddLine(dl,c,y+7,c,y+fh-7,0xFFFFFF10,0.5)
      host.icon(dl,e.snap and SP.magnet or SP.magnet_off,c+snap_w/2,y+fh/2,(ICON_PX-1)*grow('snap',snap_hov),e.snap and 0xFFFFFFFF or (snap_hov and 0xE0E0EAFF or 0x9A9AA8FF))
      if root_click then
        local items={}
        if e.poly and e.poly.keys and #e.poly.keys>0 then
          -- Polyphonic: найденные тональности (лучшая и альтернативы); выбор фиксирует её как ручную
          for k,key in ipairs(e.poly.keys) do local root,sc=Poly.key_scale(key)
            if root then items[#items+1]={label=(k==1 and 'Detected: ' or 'Alternative: ')..Poly.key_name(key),action=function() if not locked then e:set_scale(root,sc) end end} end
          end
          items[#items+1]={sep=true}
        end
        items[#items+1]={label='Analyze key…',action=function() e.key_modal={} end};items[#items+1]={sep=true}
        for i=1,12 do items[#items+1]={label=Scale.root_name(i-1,e.scale),checked=i-1==(e.root or 0),action=function() if not locked then e:set_scale(i-1,e.scale or 1) end end} end
        host.dropdown('root',(a+b)/2,y+fh,items)
      end
      if mode_click then
        local items={}
        for i,scale in ipairs(Scale.scales) do items[#items+1]={label=scale[1],checked=i==(e.scale or 1),action=function() if not locked then e:set_scale(e.root or 0,i) end end} end
        host.dropdown('mode',(b+c)/2,y+fh,items)
      end
      if snap_click and not locked then e:set_scale(e.root or 0,e.scale or 1,not e.snap) end
      host.tooltip('pitch_scale',snap_hov,c+snap_w/2,y+fh,'','Snap to the key',wx,ww,0.35,0.2)
    elseif kind=='bpm' then
      -- темп из Polyphonic; подсказка — уверенность и альтернативы (половинный/двойной темп)
      im.SetCursorScreenPos(ctx,rx,y);im.InvisibleButton(ctx,'##pitch_bpm',r[2],fh)
      local hv=im.IsItemHovered(ctx)
      im.DrawList_AddRectFilled(dl,rx,y,rx+r[2],y+fh,host.pill,8)
      local tw,th=im.CalcTextSize(ctx,bpm_text)
      im.DrawList_AddText(dl,math.floor(rx+(r[2]-tw)/2),math.floor(y+(fh-th)/2),e.poly and 0xE6E6F0FF or 0x8A8A96FF,bpm_text)
      local tip='Tempo of the analyzed item'
      if e.poly then
        local alts={};for _,b in ipairs(e.poly.bpm_alt or {}) do alts[#alts+1]=string.format('%.1f',b) end
        tip=string.format('Detected tempo, confidence %d%%%s. Key: %s%s.',math.floor((e.poly.bpm_conf or 0)*100+.5),#alts>0 and ('; also possible: '..table.concat(alts,', ')) or '',
          Poly.key_name(e.poly.keys and e.poly.keys[1]),e.scale_origin=='manual' and ' (the key control keeps your manual choice)' or '')
      end
      host.tooltip('pitch_bpm',hv,rx+r[2]/2,y+fh,'',tip..' Click: set the project tempo, note display.',wx,ww,TIP_DELAY,0.2)
      if hv then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
      if im.IsItemClicked(ctx,0) then
        local d=M.poly_detail(e.r)
        local items={}
        if (bpm_src or 0)>0 then
          local function tempo_item(bpm,label)
            local v=math.floor(bpm+.5)
            return {label=string.format(label,v),action=function()
              e.r.Undo_BeginBlock2(e.project or 0);e.r.SetCurrentBPM(e.project or 0,v,true);e.r.Undo_EndBlock2(e.project or 0,'Vocaligner: set project tempo',-1)
              e.r.UpdateTimeline();e.message=string.format('Project tempo set to %d BPM',v) end}
          end
          items[#items+1]=tempo_item(bpm_src,'Set project tempo: %d BPM')
          for _,alt in ipairs(e.poly and e.poly.bpm_alt or {}) do items[#items+1]=tempo_item(alt,'Set project tempo: %d BPM (alternative)') end
          items[#items+1]={sep=true}
        end
        for _,it in ipairs({
          {label='Notes: clean',checked=d=='clean',action=function() e.r.SetExtState(VIEW_SECTION,'poly_notes','clean',true) end},
          {label='Notes: all detected',checked=d=='all',action=function() e.r.SetExtState(VIEW_SECTION,'poly_notes','all',true) end}}) do items[#items+1]=it end
        host.dropdown('pitch_poly_notes',rx+r[2]/2,y+fh,items)
      end
    elseif kind=='sync' then
      -- Sync: правки открытого айтема применяются ко всем его копиям; зелёная, когда включена
      im.SetCursorScreenPos(ctx,rx,y);im.InvisibleButton(ctx,'##pitch_sync',fh,fh)
      local hv=im.IsItemHovered(ctx)
      if hv then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
      local on=e.sync_on==true
      im.DrawList_AddRectFilled(dl,rx,y,rx+fh,y+fh,on and (hv and 0x3AA865FF or 0x2F8F57FF) or (hv and host.pill_hover or host.pill),8)
      local c=on and 0xFFFFFFFF or 0xE6E6F0FF;local mx,my=rx+fh/2,y+fh/2
      im.DrawList_AddCircle(dl,mx-4,my,4.6,c,0,1.7);im.DrawList_AddCircle(dl,mx+4,my,4.6,c,0,1.7) -- два звена
      if im.IsItemClicked(ctx,0) then e:set_sync(not on) end
      host.tooltip('pitch_sync',hv,rx+fh/2,y+fh,'',(on and 'Sync on' or 'Sync off')..' · '..#e.twins..(#e.twins==1 and ' linked copy' or ' linked copies'),wx,ww,TIP_DELAY,0.2)
    elseif kind=='auto' then
      -- Auto: подгонка высоты под тональность / референс; открывает облачко с параметрами (ui2.lua)
      local a=import('pitch/auto').config(e.state)
      im.SetCursorScreenPos(ctx,rx,y);im.InvisibleButton(ctx,'##pitch_auto',r[2],fh)
      local hv=im.IsItemHovered(ctx)
      if hv then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
      im.DrawList_AddRectFilled(dl,rx,y,rx+r[2],y+fh,a.on and (hv and SEL_HOVER or SEL_FILL) or (hv and host.pill_hover or host.pill),8)
      local tw,th=im.CalcTextSize(ctx,'ATune')
      im.DrawList_AddText(dl,math.floor(rx+(r[2]-tw)/2),math.floor(y+(fh-th)/2),a.on and 0xFFFFFFFF or 0xE6E6F0FF,'ATune')
      e.auto_btn={x=rx,y=y,w=r[2],h=fh}
      if im.IsItemClicked(ctx,0) then e.auto_toggle=true end
      host.tooltip('pitch_auto',hv,rx+r[2]/2,y+fh,'','ATune',wx,ww,TIP_DELAY,0.2)
    elseif kind=='copy' then if im.Button(ctx,'Copy##pitch_copy',r[2],fh) then e:copy_shape() end
    elseif kind=='paste' then if im.Button(ctx,'Paste##pitch_paste',r[2],fh) then e:paste_shape((im.GetKeyMods(ctx)&im.Mod_Alt)~=0) end
    end
    rx=rx+r[2]+G
  end
end

-- Пункты меню редактора (кнопка-гамбургер в топбаре, слева от Settings): сбросы, отчёт, экспорт кейса
function M.menu_items(im,ctx,app)
  local e=app.pitch
  local can=e.data~=nil and not e.stale and not e.no_selection and not e:busy()
  -- Сброс нужен именно когда анализ устарел или правки не читаются (stale): ему данные редактора не нужны,
  -- только сохранённое состояние айтема
  local can_reset=e.snapshot~=nil and not e.no_selection and not e:busy()
  return {
    {label='Reset corrections',disabled=not can_reset,action=function() e:reset_all(Workspace.targets(e)) end},
    {label='Reset full',disabled=not can_reset,action=function() e:reset_all(Workspace.targets(e),true) end},
    {label='Reset analysis (selected takes)',disabled=not can_reset,action=function() e:reset_analysis() end},
    {label='Compact project data',disabled=e:busy(),action=function() e:compact_project() end},
    {label='Apply ATune to selected items',disabled=not can or e.mode=='poly',action=function() e:apply_auto_selected() end},
    {sep=true},
    {label='Copy report',action=function() im.SetClipboardText(ctx,e:diagnostics()) end},
    {label='Export case',disabled=not can,action=function() e:export_case() end},
    {sep=true},
    -- Pitch Meter (JSFX на айтеме): сравнить измеренную высоту выхода с целевой кривой
    {label='Pitch Meter (Check)',checked=e.check_on==true,disabled=e.no_selection or not e.snapshot,action=function() e:set_meter(not e.check_on) end},
  }
end

local function text_w_of(im,ctx,t) return (im.CalcTextSize(ctx,t)) end
-- Короткое имя дорожки для списка ghost: имя (обрезанное) или номер, если имени нет
local function short_name(row)
  local name=(row.name or ''):gsub('^%s+',''):gsub('%s+$','')
  if name=='' then return '#'..tostring(row.index) end
  if #name>14 then name=name:sub(1,13)..'…' end
  return name
end
-- Содержимое окошка ghost (рисуется оболочкой в стилевом облачке): чекбокс отрисовки фона и имя дорожки для прыжка
function M.ghost_rows(im,ctx,app,dropdown)
  local e=app.pitch;local count=0;local sel_w=text_w_of(im,ctx,'Source')
  if e.workspace then
    for _,row in ipairs(e.workspace.tracks) do if (row.analyzed or 0)+(row.poly or 0)>0 then sel_w=math.max(sel_w,(im.CalcTextSize(ctx,short_name(row))))end end
  end
  -- строка-кнопка со скруглением; цвет — по цвету трека REAPER; возвращает клик ЛКМ и клик ПКМ
  local function track_rgb(row)
    local r=e.r;if not (row and row.track and r.GetTrackColor and r.ColorFromNative) then return nil end
    local c=r.GetTrackColor(row.track);if (c or 0)==0 then return nil end
    local rr,gg,bb=r.ColorFromNative(c&0xFFFFFF);return rr,gg,bb
  end
  local function label_button(id,label,active,row)
    local fh=im.GetFrameHeight(ctx);local bx,by=im.GetCursorScreenPos(ctx);local bw=sel_w+14
    im.InvisibleButton(ctx,id,bw,fh,im.ButtonFlags_MouseButtonLeft|im.ButtonFlags_MouseButtonRight)
    local hov=im.IsItemHovered(ctx);local dl=im.GetWindowDrawList(ctx)
    if hov then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
    local rr,gg,bb=track_rgb(row)
    if rr then
      -- кнопка в цвете трека: приглушённо в покое, ярче при наведении, текущий трек — заметно ярче и с рамкой
      local a=active and 0xB0 or (hov and 0x70 or 0x42)
      im.DrawList_AddRectFilled(dl,bx,by,bx+bw,by+fh,(rr<<24)|(gg<<16)|(bb<<8)|a,6)
      if active then im.DrawList_AddRect(dl,bx+.5,by+.5,bx+bw-.5,by+fh-.5,0xFFFFFF70,6,0,1) end
    elseif active or hov then
      im.DrawList_AddRectFilled(dl,bx,by,bx+bw,by+fh,active and (hov and 0x5A6684FF or 0x4A5470FF) or 0x2E3442FF,6)
      if active then im.DrawList_AddRect(dl,bx+.5,by+.5,bx+bw-.5,by+fh-.5,0xFFFFFF50,6,0,1) end
    end
    im.DrawList_AddText(dl,bx+7,by+(fh-im.GetTextLineHeight(ctx))/2,active and 0xFFFFFFFF or 0xE0E0EAFF,label)
    return im.IsItemClicked(ctx,0),im.IsItemClicked(ctx,1)
  end
  -- Source: серая линия исходного F0 на холсте
  local changed,on=im.Checkbox(ctx,'##pitch_source',e.show_source==true)
  if changed then e.show_source=on end
  im.SameLine(ctx,0,6)
  if (label_button('##pitch_source_label','Source',false)) then e.show_source=not e.show_source end
  -- горизонтальный разделитель ровно по ширине строк (Separator тянулся бы на всю ширину окна)
  do
    local sx,sy=im.GetCursorScreenPos(ctx);local rw=im.GetFrameHeight(ctx)+6+sel_w+14
    im.Dummy(ctx,rw,5)
    im.DrawList_AddLine(im.GetWindowDrawList(ctx),sx,sy+2,sx+rw,sy+2,0xFFFFFF22,1)
  end
  if e.workspace then
    for _,row in ipairs(e.workspace.tracks) do if (row.analyzed or 0)+(row.poly or 0)>0 then
      count=count+1
      local changed,on=im.Checkbox(ctx,'##pitch_ghost_'..row.guid,row.visible)
      if changed then Workspace.visible(e,on,row) end
      im.SameLine(ctx,0,6)
      local click,rclick=label_button('##pitch_track_'..row.guid,short_name(row),row.track==e.track,row)
      if click then Workspace.activate_track(e,row) end
      if rclick and dropdown then
        -- контекстное меню трека: сдвиг ТОЛЬКО для отображения призрачных нот (сами ноты и звук не меняются)
        e.ghost_shift=e.ghost_shift or {}
        local cur=e.ghost_shift[row.guid] or 0
        local mx,my=im.GetMousePos(ctx)
        dropdown('ghost_'..row.guid,mx,my+10,{
          {label='Show one octave higher',checked=cur==12,action=function() e.ghost_shift[row.guid]=cur==12 and 0 or 12 end},
          {label='Show one octave lower',checked=cur==-12,action=function() e.ghost_shift[row.guid]=cur==-12 and 0 or -12 end},
          {sep=true},
          {label='Show at original pitch',disabled=cur==0,action=function() e.ghost_shift[row.guid]=0 end},
        })
      end
    end end
  end
  if count==0 then im.TextDisabled(ctx,'No analyzed tracks') end
  return count
end
-- Размер содержимого окна ghost (без полей): те же формулы, что в ghost_rows; вызывать с тем же шрифтом и FramePadding
-- ===== окно ATune (автоподгонка высоты): рисуется оболочкой ui2.lua в облачке =====
-- Слева — текущая нота под курсором, горизонтальный индикатор отклонения и ноты тональности; справа — кнобы
-- Speed/Transitions (крупные), Flex Tune/Humanize/Amount (мелкие) и слайдер Vibrato; внизу — вкл/выкл, Pitch Meter,
-- Key/Ref и выбор референса. Параметры идут через e:set_auto (драг — предпросмотр, отпускание — одна запись).
local Knob=import('ui2/knob')
local AT_W,AT_H=366,176
local BH=24 -- высота кнопок нижней панели
local AT_LEFT=196
local AT={dev=0,vt=nil}
local AT_KEYS={speed={'atune_speed','Speed',0,400,'%.0f ms'},transitions={'atune_transitions','Transitions',0,250,'%.0f ms'},
  flex={'atune_flex','Flex Tune',0,100,'%.0f'},humanize={'atune_humanize','Humanize',0,100,'%.0f'},amount={'atune_amount','Amount',0,100,'%.0f%%'}}
local NOTE_NAMES={'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'}
function M.auto_size(compact) return compact and AT_LEFT or AT_W,AT_H end
function M.auto_split() return AT_LEFT-8 end -- x границы правой секции от левого края содержимого
-- владелец для кнобов: тот же интерфейс, что у cleaner (cfg / settings_changed / control_released), поверх e:set_auto
local OWNER={cfg={},gesture=false}
local function knob_owner(e,a)
  local o=OWNER;o.e=e
  for f,k in pairs(AT_KEYS) do if not o.gesture or o.last~=f then o.cfg[k[1]]=a[f] end end
  function o:settings_changed(key) for f,k in pairs(AT_KEYS) do if k[1]==key then self.last=f;self.dirty=f;self.e:set_auto(f,self.cfg[key],false) end end end
  -- запись на отпускании только для ручки, которую действительно двигали: простой клик/наведение ничего не пишет
  function o:control_released() local f=self.dirty;self.dirty=nil;self.gesture=false;if f then self.e:set_auto(f,self.cfg[AT_KEYS[f][1]],true) end end
  return o
end
local function rgb_of(r,native)
  if not native or native==0 or not r.ColorFromNative then return nil end
  local rr,gg,bb=r.ColorFromNative(native&0xFFFFFF);return (rr<<24)|(gg<<16)|(bb<<8)|0xFF
end
local function short(s,n) s=(s or ''):gsub('^%s+',''):gsub('%s+$','');if #s>n then s=s:sub(1,n-1)..'…' end;return s end
local function guid_of(r,item) local _,g=r.GetSetMediaItemInfo_String(item,'GUID','',false);return g end
-- векторные иконки нижней панели
local function icon_power(im,dl,cx,cy,col)
  local pi=math.pi;im.DrawList_PathArcTo(dl,cx,cy+1,6,-pi/2+.75,3*pi/2-.75);im.DrawList_PathStroke(dl,col,0,1.8)
  im.DrawList_AddLine(dl,cx,cy-7,cx,cy-.5,col,1.8)
end
local function icon_curve(im,dl,cx,cy,col)
  for i=0,16 do im.DrawList_PathLineTo(dl,cx-8+i,cy+math.sin(i/16*math.pi*2)*4.5) end;im.DrawList_PathStroke(dl,col,0,1.7)
end
function M.auto_rows(im,ctx,app,x,y,fonts,host,compact)
  local y0=y
  local e=app.pitch;local r=e.r;local Auto=import('pitch/auto');local a=Auto.config(e.state)
  -- значения ручек, ещё не дошедшие до сохранённого состояния (идёт запись, очередь, предпросмотр): показываем их,
  -- иначе ручка на миг откатывается к старому значению, пока завершается предыдущая запись
  do
    local stored=Auto.config(e.state);local idle=not e.auto_before and not e.auto_queue and not e:busy()
    for k,v in pairs(e.auto_queue or {}) do if v==false then v=nil end;a[k]=v end
    for k,v in pairs(e.auto_ui or {}) do
      local vv=v;if vv==false then vv=nil end
      if idle and stored[k]==vv then e.auto_ui[k]=nil else a[k]=vv end
    end
  end
  local can=e.data~=nil and not e.stale and not e.no_selection
  local ref=a.mode=='reference'
  local dl=im.GetWindowDrawList(ctx)
  local ACC,ACC_SOFT=0xC8A85AFF,0x9C8446FF -- золотистый акцент окна (мягче оранжевого)
  local BTN,BTN_H=host.pill,host.pill_hover
  local lx,lw=x,AT_LEFT-14
  local AREA=AT_H-BH-8 -- высота левого блока над нижней панелью
  -- ===== левая часть: нота, индикатор, ноты тональности =====
  local s=e.snapshot;local P=(r.GetPlayState()&1)==1 and r.GetPlayPosition() or r.GetCursorPosition()
  local note,dev
  if e.data and s and P>=s.pos and P<=s.pos+s.len then
    local raw=import('pitch/expression').sample(e.data,P-s.pos)
    if raw then
      if ref then note=math.floor(raw+.5) else note=(e.auto_mask and Scale.nearest_mask(e.auto_mask) or Scale.nearest_fn(e.root or 0,e.scale or 1))(raw) end
      dev=clamp((raw-note)*100,-100,100)
    end
  end
  local now=r.time_precise();local dt=clamp(now-(AT.vt or now),0,.1);AT.vt=now
  AT.dev=AT.dev+((dev or 0)-AT.dev)*math.min(1,dt*14) -- плавный сдвиг индикатора
  do
    local ly=y+math.max(0,(AREA-112)/2) -- левый блок по центру высоты над нижней панелью
    im.PushFont(ctx,fonts.note)
    local name=note and NOTE_NAMES[note%12+1] or '–'
    local nw,nh=im.CalcTextSize(ctx,name)
    im.DrawList_AddText(dl,math.floor(lx+(lw-nw)/2),ly,note and 0xF2F2F2FF or 0x5A5A5AFF,name)
    im.PopFont(ctx)
    local by=ly+nh+6;local bh=10
    im.DrawList_AddRectFilled(dl,lx,by,lx+lw,by+bh,0x1C1C1CFF,3)
    local cx=lx+lw/2;local px=cx+AT.dev/100*(lw/2-2)
    if note then im.DrawList_AddRectFilled(dl,math.min(cx,px),by+1,math.max(cx,px)+1,by+bh-1,math.abs(AT.dev)<15 and ACC or ACC_SOFT,2) end
    im.DrawList_AddLine(dl,cx,by-3,cx,by+bh+3,0xFFFFFF90,1)
    for _,k in ipairs({-50,50}) do local tx=cx+k/100*(lw/2-2);im.DrawList_AddLine(dl,tx,by+bh,tx,by+bh+3,0xFFFFFF40,1) end
    -- ноты: 5 диезов сверху, 7 натуральных снизу; ноты тональности светлее, текущая — акцент
    local py=by+bh+12;local pw,ph,pg=22,18,3
    local function pill(i,px_,py_)
      local inkey=not ref and (e.auto_mask and e.auto_mask[i] or (e.auto_mask==nil and Scale.contains(i,e.root or 0,e.scale or 1)))
      local cur=note and note%12==i
      if not ref and can then -- клик по ноте: разово включить/выключить её для Auto (не сохраняется)
        im.SetCursorScreenPos(ctx,px_,py_);im.InvisibleButton(ctx,'##atune_pc_'..i,pw,ph)
        if im.IsItemHovered(ctx) then im.SetMouseCursor(ctx,im.MouseCursor_Hand);im.DrawList_AddRectFilled(dl,px_-1,py_-1,px_+pw+1,py_+ph+1,0xFFFFFF18,ph/2+1) end
        if im.IsItemClicked(ctx,0) then e:toggle_auto_note(i) end
      end
      local fill=cur and ACC or (inkey and 0x2E3A36FF or 0x1E1E1EFF)
      im.DrawList_AddRectFilled(dl,px_,py_,px_+pw,py_+ph,fill,ph/2)
      if inkey and not cur then im.DrawList_AddRect(dl,px_+.5,py_+.5,px_+pw-.5,py_+ph-.5,0x5C8C7CCC,ph/2,0,1) end
      local t=NOTE_NAMES[i+1];local tw,th=im.CalcTextSize(ctx,t)
      im.DrawList_AddText(dl,math.floor(px_+(pw-tw)/2),math.floor(py_+(ph-th)/2),cur and 0x1A1A1AFF or (inkey and 0xE0EFEAFF or 0x555555FF),t)
    end
    local nat={0,2,4,5,7,9,11};local tot=7*pw+6*pg;local ox=lx+(lw-tot)/2
    for k,i in ipairs(nat) do pill(i,ox+(k-1)*(pw+pg),py+ph+pg) end
    for _,sh in ipairs({{1,1},{3,2},{6,4},{8,5},{10,6}}) do pill(sh[1],ox+sh[2]*(pw+pg)-(pw+pg)/2,py) end
  end
  -- ===== правая часть: кнобы и Vibrato по центру высоты, без нижней панели =====
  if not compact then
    if not can then im.BeginDisabled(ctx,true) end
    local own=knob_owner(e,a)
    local rx=x+AT_LEFT;local rw=AT_W-AT_LEFT
    local BIG,SMALL,LBL=58,40,20
    local bigh,smallh,vh=BIG+LBL,SMALL+LBL,20
    local gap=5
    local total=bigh+smallh+vh+2*gap
    local ky1=y0+math.max(0,(AT_H-total)/2);local ky2=ky1+bigh+gap;local ky3=ky2+smallh+gap
    local function knob(field,kx,ky,px,width,locked)
      local k=AT_KEYS[field]
      if locked then
        -- недоступно в режиме референса: тонкое пустое кольцо и приглушённая подпись
        local cxk=kx+width/2
        im.DrawList_AddCircle(dl,cxk,ky+px/2,px/2-3,0x2E2E2EFF,0,1.5)
        local tw=im.CalcTextSize(ctx,k[2])
        im.DrawList_AddText(dl,math.floor(cxk-tw/2),ky+px+3,0x4A4A4AFF,k[2])
        return
      end
      im.SetCursorScreenPos(ctx,kx,ky)
      Knob.control(im,ctx,own,k,nil,{skin={file='Sp_'..px..'.png'},scale=1,grow=.04,animate=true,size=px,width=width,float=true,below=true})
    end
    local bw=rw/2;local sw=rw/3
    knob('speed',rx,ky1,BIG,bw);knob('transitions',rx+bw,ky1,BIG,bw)
    knob('flex',rx,ky2,SMALL,sw,ref);knob('humanize',rx+sw,ky2,SMALL,sw,ref);knob('amount',rx+2*sw,ky2,SMALL,sw)
    -- Vibrato: от центра влево (ослабить) и вправо (усилить); двойной клик — 0
    if ref then im.BeginDisabled(ctx,true) end
    im.SetCursorScreenPos(ctx,rx+6,ky3);im.SetNextItemWidth(ctx,rw-12)
    local vib=a.vibrato or 0
    local vch,vv=im.SliderDouble(ctx,'##atune_vibrato',vib,-100,100,math.abs(vib)<.5 and 'Vibrato' or 'Vibrato %+.0f')
    if vch then e:set_auto('vibrato',vv,false) end
    if im.IsItemDeactivatedAfterEdit(ctx) then e:set_auto('vibrato',(e.auto_queue and e.auto_queue.vibrato) or Auto.config(e.state).vibrato,true) end
    if im.IsItemHovered(ctx) and im.IsMouseDoubleClicked(ctx,0) then e:set_auto('vibrato',0,true) end
    if ref then im.EndDisabled(ctx) end
    if not can then im.EndDisabled(ctx) end
  end
  -- ===== нижняя панель — только под левой секцией: цвета исходной темы =====
  local fy=y0+AT_H-BH
  local bx=x
  local function button(id,w,draw,active,disabled,fill,fill_hover)
    im.SetCursorScreenPos(ctx,bx,fy)
    local clicked=im.InvisibleButton(ctx,id,w,BH);local hv=im.IsItemHovered(ctx)
    if hv and not disabled then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
    local col=fill and (hv and fill_hover or fill) or (active and (hv and SEL_HOVER or SEL_FILL) or (hv and BTN_H or BTN))
    im.DrawList_AddRectFilled(dl,bx,fy,bx+w,fy+BH,col,8)
    draw(bx,fy,w,disabled and 0x6A6A6AFF or (active and 0xFFFFFFFF or 0xE6E6F0FF))
    local x0=bx;bx=bx+w+5
    return clicked and not disabled,hv,x0
  end
  local function label(x0,y0_,w,col,t,pad)
    local tw,th=im.CalcTextSize(ctx,t)
    im.DrawList_AddText(dl,math.floor(x0+(pad and pad or (w-tw)/2)),math.floor(y0_+(BH-th)/2),col,t)
  end
  -- вкл/выкл с подписью «Auto»
  local atw=im.CalcTextSize(ctx,'Auto')
  local c1=button('##atune_on',BH+atw+10,function(x0,y0_,w,col)
    icon_power(im,dl,x0+BH/2+1,y0_+BH/2,0xFFFFFFFF);im.DrawList_AddText(dl,math.floor(x0+BH+1),math.floor(y0_+(BH-im.GetTextLineHeight(ctx))/2),0xFFFFFFFF,'Auto') end,a.on==true,not can,
    a.on and 0x2F8F57FF or 0xB8472AFF,a.on and 0x3AA865FF or 0xCC5634FF)
  if c1 then e:set_auto('on',not a.on,true) end
  -- Pitch Meter — по правому краю левой секции
  local mx_meter=x+lw-(BH+4)
  -- референсы: только айтемы, пересекающиеся по времени с текущим рабочим (над/под него), без соседних
  local rows={};local cur_row,cur_item
  local cur_a,cur_b=s and s.pos or 0,s and (s.pos+s.len) or 0
  local function overlaps(it) return it.pos<cur_b and it.pos+it.len>cur_a end
  for _,row in ipairs(e.workspace and e.workspace.tracks or {}) do
    if (row.analyzed or 0)>0 and row~=e.track_row then
      local near=false;for _,it in ipairs(row.items) do if it.state and it.state.analysis and it.item~=e.item and overlaps(it) then near=true;break end end
      if near or row.guid==a.ref_track then rows[#rows+1]=row end
      if row.guid==a.ref_track then cur_row=row
        if a.ref_item then for _,it in ipairs(row.items) do if guid_of(r,it.item)==a.ref_item then cur_item=it end end end
      end
    end
  end
  local function item_name(it) local tk=r.GetActiveTake(it.item);return short(tk and r.GetTakeName(tk) or '',14) end
  local function track_name(row) return short(row.name~='' and row.name or ('#'..tostring(row.index)),14) end
  local mlabel='Key';local mcol
  if ref then
    mlabel='Ref: '..(cur_row and (track_name(cur_row)..(cur_item and (' · '..item_name(cur_item)) or '')) or 'choose')
    if cur_row then mcol=rgb_of(r,r.GetTrackColor(cur_row.track)) end
    if e.auto_note then mlabel=mlabel..' — no analysis';mcol=0xE8B65AFF end -- «нет анализа референса» в той же строке
  else mlabel='Key ▾' end
  local mtw=im.CalcTextSize(ctx,mlabel)
  local mw=math.max(54,math.min(mtw+20,mx_meter-bx-5))
  local mc,_,mxx=button('##atune_mode',mw,function(x0,y0_,w,col)
    im.DrawList_PushClipRect(dl,x0+3,y0_,x0+w-3,y0_+BH,true)
    label(x0,y0_,w,mcol or col,mlabel,mtw>w-8 and 7 or nil)
    im.DrawList_PopClipRect(dl) end,false,not can)
  local function open_picker()
    local items={{label='Key — use the scale',checked=not ref,action=function() e:set_auto('mode','key',true) end},{sep=true}}
    if #rows==0 then items[#items+1]={label='No analyzed items here',disabled=true} end
    local function choose(row,item_guid) e:set_auto('mode','reference',false);e:set_auto('ref_item',item_guid,false);e:set_auto('ref_track',row.guid,true) end
    for _,row in ipairs(rows) do
      local an={};for _,it in ipairs(row.items) do if it.state and it.state.analysis and it.item~=e.item and overlaps(it) then an[#an+1]=it end end
      items[#items+1]={label=track_name(row),dot=rgb_of(r,r.GetTrackColor(row.track)),checked=ref and row.guid==a.ref_track and not a.ref_item,action=function() choose(row,nil) end}
      if #an>1 then
        for i,it in ipairs(an) do
          local g=guid_of(r,it.item);local nm=item_name(it)
          items[#items+1]={label=nm~='' and nm or ('Item '..i),indent=14,dot=rgb_of(r,r.GetDisplayedMediaItemColor and r.GetDisplayedMediaItemColor(it.item)) or rgb_of(r,r.GetTrackColor(row.track)),
            checked=ref and a.ref_item==g,action=function() choose(row,g) end}
        end
      end
    end
    host.dropdown('atune_ref',mxx+mw/2,fy,items,true) -- список поднимается над кнопкой (панель у нижнего края окна)
  end
  if mc then
    if not ref then e:set_auto('mode','reference',true);if not cur_row then open_picker() end
    else open_picker() end
  end
  bx=mx_meter
  local c2,h2,x2=button('##atune_meter',BH+4,function(x0,y0_,w,col) icon_curve(im,dl,x0+w/2,y0_+BH/2,col) end,e.check_on==true,e.no_selection or not e.snapshot)
  if c2 then e:set_meter(not e.check_on) end
  if h2 then Knob.plate(im,ctx,x2+(BH+4)/2,fy-4,'Pitch Meter FX',true,nil,true) end
end
function M.ghost_size(im,ctx,app,spacing)
  local e=app.pitch;local fh=im.GetFrameHeight(ctx);local sel_w=(im.CalcTextSize(ctx,'Source'));local n=0
  if e.workspace then
    for _,row in ipairs(e.workspace.tracks) do if (row.analyzed or 0)+(row.poly or 0)>0 then
      n=n+1;sel_w=math.max(sel_w,(im.CalcTextSize(ctx,short_name(row))))
    end end
  end
  local w=fh+6+sel_w+14
  local rows=n>0 and (n*fh+(n-1)*spacing) or im.GetTextLineHeight(ctx)
  return math.max(w,n==0 and (im.CalcTextSize(ctx,'No analyzed tracks')) or 0),fh+spacing+5+spacing+rows
end
function M.ghost_count(app)
  local n=0;local e=app.pitch
  if e.workspace then for _,row in ipairs(e.workspace.tracks) do if (row.analyzed or 0)+(row.poly or 0)>0 then n=n+1 end end end
  return math.max(n,1)
end

-- Тело вкладки: прогресс, сообщения и холст. Подсказки холста уводятся из-под курсора в облачко оболочки.
local tip_text,tip_last
local KEYS={'Key_1','Key_2','Key_3','Key_4','Key_5','Key_6'}
-- Polyphonic: показ найденных нот (анализ не меняется). Clean — то, что читается как партитура:
--  1) обрывки одной высоты с зазором до 1/8 доли (не меньше 60 мс) склеиваются в одну ноту;
--  2) короче 1/4 доли (не меньше 70 мс) и неуверенные, а также совсем слабые одиночки — прячутся;
--  3) роль ноты по аккорду в её середине: тон аккорда — цвет аккорда из полосы, бас (нижний тон аккорда) — ярче,
--     неаккордовые и ноты под N.C. — серым фоном. All — все найденные ноты без склейки, цвет по высоте.
VIEW_SECTION='Vocaligner Pitch View 1'
function M.poly_detail(r) return r.GetExtState(VIEW_SECTION,'poly_notes')=='all' and 'all' or 'clean' end
function M.poly_view(rec,detail)
  local key=detail;if rec._view and rec._view_key==key then return rec._view end
  local beat=(rec.bpm and rec.bpm>30) and 60/rec.bpm or .5
  local gap,min_d=math.max(.06,beat/8),math.max(.07,beat/4)
  local list={}
  if detail=='all' then
    for i,n in ipairs(rec.notes) do list[i]={s=n.s,e=n.e,p=n.p,c=n.c} end
  else
    local by={}
    for _,n in ipairs(rec.notes) do local l=by[n.p];if not l then l={};by[n.p]=l end;l[#l+1]=n end
    for _,l in pairs(by) do
      table.sort(l,function(x,y)return x.s<y.s end)
      local cur
      for _,n in ipairs(l) do
        if cur and n.s-cur.e<=gap then cur.e=math.max(cur.e,n.e);cur.c=math.max(cur.c,n.c);cur.parts=cur.parts+1
        else if cur then list[#list+1]=cur end;cur={s=n.s,e=n.e,p=n.p,c=n.c,parts=1} end
      end
      if cur then list[#list+1]=cur end
    end
    local kept={}
    for _,n in ipairs(list) do local d=n.e-n.s
      if not ((d<min_d and n.c<.6) or n.c<.2) then kept[#kept+1]=n end
    end
    list=kept
  end
  table.sort(list,function(x,y)return x.s<y.s or (x.s==y.s and x.p<y.p) end)
  -- роль по аккорду в середине ноты (аккорды отсортированы — бинарный поиск)
  local chords=rec.chords
  local function chord_at(t) local lo,hi=1,#chords
    while lo<=hi do local m=(lo+hi)//2;local c=chords[m];if t<c.s then hi=m-1 elseif t>=c.e then lo=m+1 else return c end end end
  local maxd=0
  for _,n in ipairs(list) do
    maxd=math.max(maxd,n.e-n.s)
    local c=chord_at((n.s+n.e)*.5);n.role='other'
    if c and c.root>=0 then
      local pc=n.p%12;local tones=Poly.TONES[(c.quality or 0)+1] or Poly.TONES[1]
      for _,iv in ipairs(tones) do if (c.root+iv)%12==pc then n.role='tone' end end
      local bass=(c.bass and c.bass>=0) and c.bass or c.root
      if n.role=='tone' and pc==bass and n.p<55 then n.role='bass' end
      n.chord=c
    elseif c then n.role='nc' end
  end
  rec._view,rec._view_key,rec._view_maxd=list,key,maxd
  return list
end
-- цвет аккорда (полоса и его ноты): палитра по корню, приглушённая к серому, чтобы не рябило
local function chord_color(root,alpha)
  local c=Glyph.color(60+root,false,255)
  local r,g,b=(c>>24)&255,(c>>16)&255,(c>>8)&255
  r,g,b=math.floor(r*.72+70*.28),math.floor(g*.72+70*.28),math.floor(b*.72+80*.28)
  return (r<<24)|(g<<16)|(b<<8)|alpha
end
M.chord_color=chord_color
-- Аккорды цельными блоками, как после экспорта в MIDI (бас от C2 и голоса от C3 — те же ноты, что в poly_export.chord_midi);
-- поверх них рисуются тонкие «шумные» линии найденных нот
function M.poly_chord_blocks(im,dl,rec,a,b,g,row)
  local h=math.max(3,row*.72)
  for _,c in ipairs(rec.chords or {}) do
    if c.root and c.root>=0 and c.e>=a and c.s<=b and c.e-c.s>.05 then
      local x1,x2=g.tx(c.s),g.tx(c.e)
      local function block(p,alpha)
        local yy=g.py(p)
        if yy+h>=g.top and yy-h<=g.bottom then
          im.DrawList_AddRectFilled(dl,x1+1,yy-h/2,math.max(x1+3,x2-1),yy+h/2,chord_color(c.root,alpha),3)
        end
      end
      block(36+((c.bass and c.bass>=0) and c.bass or c.root),0x70)
      for _,iv in ipairs(Poly.TONES[(c.quality or 0)+1] or Poly.TONES[1]) do block(48+c.root+iv,0x58) end
    end
  end
end
function M.poly_notes(im,dl,ctx,g)
  local rec=g.rec or PolyRec;if not rec then return end
  local v=g.v;local a,b=v.start,v.start+v.span
  local detail=g.detail or (PolyEditor and M.poly_detail(PolyEditor.r)) or 'clean'
  local notes=M.poly_view(rec,detail);local maxd=rec._view_maxd or 0
  local lo,hi=1,#notes+1;local from=a-maxd
  while lo<hi do local mid=(lo+hi)//2;if notes[mid].s<from then lo=mid+1 else hi=mid end end
  -- тонкие линии вместо блоков: длительность читается линией, атака — точкой в начале; бас толще, фон — тоньше
  local row=g.height/v.rows;local th=math.max(2,math.min(4.5,row*.22))
  M.poly_chord_blocks(im,dl,rec,a,b,g,row)
  for i=lo,#notes do local n=notes[i];if n.s>b then break end
    if n.e>=a then
      local x1,x2=g.tx(n.s),g.tx(n.e);local yy=g.py(n.p)
      if yy+th>=g.top and yy-th<=g.bottom then
        if x2-x1<2 then x2=x1+2 end
        local k=math.min(1,n.c);local col,w,dot
        if detail=='all' then col=Glyph.color(n.p,false,math.floor(70+140*k));w=th;dot=true
        elseif n.role=='bass' then col=chord_color(n.chord.root,math.floor(210+45*k));w=th*1.35;dot=true
        elseif n.role=='tone' then col=chord_color(n.chord.root,math.floor(140+90*k));w=th;dot=true
        else col=0x9A9AA600|math.floor(45+45*k);w=th*.6 end -- неаккордовые / под N.C. — фоном
        im.DrawList_AddRectFilled(dl,x1,yy-w/2,x2,yy+w/2,col,w/2)
        if dot and x2-x1>w*2 then im.DrawList_AddCircleFilled(dl,x1+w*.6,yy,w*.85,col|0xFF) end
      end
    end
  end
  -- доли: тонкие тики у нижнего края вида
  for _,t in ipairs(rec.beats) do if t>=a and t<=b then local xx=g.tx(t);im.DrawList_AddLine(dl,xx,g.bottom-6,xx,g.bottom,0xFFFFFF40,1) end end
end
-- Окно «Analyze key»: выделенный айтем (имя и волна), Analyze и Close. Быстрый Polyphonic-анализ: тональность
-- становится тональностью проекта (как ручной выбор), темп — в плашку BPM. Без подсказок и пояснений.
function M.key_modal(host,im,ctx,e,bx0,by0,cw,ch)
  local km=e.key_modal;local r=e.r;local dl=im.GetForegroundDrawList(ctx)
  local W,H=360,150;local X,Y=math.floor(bx0+(cw-W)/2),math.floor(by0+math.max(40,(ch-H)*.35))
  im.DrawList_AddRectFilled(dl,X-1000,Y-1000,X+W+1000,Y+H+1000,0x00000050)
  im.DrawList_AddRectFilled(dl,X,Y,X+W,Y+H,0x202020F8,12);im.DrawList_AddRect(dl,X+.5,Y+.5,X+W-.5,Y+H-.5,0x4A4A4AFF,12,0,1)
  im.DrawList_AddText(dl,X+16,Y+12,0xE6E6F0FF,'Analyze key')
  local project=r.EnumProjects(-1);local item
  for i=0,r.CountSelectedMediaItems(project)-1 do local it=r.GetSelectedMediaItem(project,i);local tk=r.GetActiveTake(it);if tk and not r.TakeIsMIDI(tk) then item=it;break end end
  local bx,by,bw,bh=X+16,Y+38,W-32,52
  im.DrawList_AddRectFilled(dl,bx,by,bx+bw,by+bh,item and 0x2C2C2CFF or 0x262626FF,8)
  if item then
    if km.item~=item then
      km.item=item;km.peaks=nil;km.name=r.GetTakeName(r.GetActiveTake(item))
      local ok,st=pcall(Audio.state,r,project,item);if ok then st.channels=r.GetMediaSourceNumChannels(st.source);local good,p=pcall(Audio.peaks,r,st);km.peaks=good and p or nil end
    end
    local lv=km.peaks and km.peaks.peaks and km.peaks.peaks[1];local vals=lv and lv.values
    if vals and #vals>1 then
      local top=math.max(1e-6,km.peaks.peak or 1);local mid=by+bh/2+6;local n=#vals;local cols=math.floor(bw-16)
      for c=0,cols-1,2 do local v=vals[math.min(n,math.floor(c/cols*n)+1)];local a=math.max(-v[1],v[2])/top*(bh/2-12)
        im.DrawList_AddLine(dl,bx+8+c,mid-a,bx+8+c,mid+a,0xE8955A90,1) end
    end
    im.DrawList_AddText(dl,bx+8,by+4,0xFFFFFFFF,km.name or 'item')
  else
    local t='Select an item';local tw=im.CalcTextSize(ctx,t);im.DrawList_AddText(dl,bx+(bw-tw)/2,by+bh/2-7,0x8A8A96FF,t)
  end
  local function button(id,x,label,enabled,accent)
    local w,h=96,28;local y=Y+H-40;local mx,my=im.GetMousePos(ctx)
    local hov=enabled and mx>=x and mx<=x+w and my>=y and my<=y+h
    im.DrawList_AddRectFilled(dl,x,y,x+w,y+h,not enabled and 0x2A2A2AFF or (accent and (hov and 0xC86A2AFF or 0xA9551EFF) or (hov and 0x3A3A3AFF or 0x303030FF)),8)
    local tw,th=im.CalcTextSize(ctx,label);im.DrawList_AddText(dl,x+(w-tw)/2,y+math.floor((h-th)/2),enabled and 0xFFFFFFFF or 0x6A6A74FF,label)
    if hov then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
    return hov and im.IsMouseClicked(ctx,0)
  end
  local running=e.key_job~=nil
  if button('close',X+W-16-96,'Close',true,false) then e.key_modal=nil;return end
  if button('analyze',X+W-16-96-8-96,running and '…' or 'Analyze',item~=nil and not running and not e:busy(),true) then
    local target=item
    -- вокал с Melodic-анализом: тональность по уже найденным нотам всех выделенных айтемов — мгновенно, без чтения звука.
    -- Полифонический анализ — только если нот нет (айтем не анализировался)
    local lists,ws={},e.workspace
    for i=0,r.CountSelectedMediaItems(project)-1 do
      local it=r.GetSelectedMediaItem(project,i)
      if it==e.item and e.notes and #e.notes>0 then lists[#lists+1]=e.notes
      else local entry=ws and ws.by_item[it];if entry and entry.state and entry.state.notes then lists[#lists+1]=entry.state.notes end end
    end
    local k=#lists>0 and import('pitch/key_detect').from_notes(lists)
    if k then
      local root,sc=Poly.key_scale(k);e:set_scale(root,sc)
      e.message=string.format('Key %s (from %d sung notes)',Poly.key_name(k),k.notes)
      e.key_modal=nil;return
    end
    if not Poly.available(r) then e:fail('Analyze the item (Melodic) first: the key is found from its pitch notes.');return end
    e.key_job=import('job').new(r,function(job)
      local rec,s=Poly.analyze_item(r,project,target,job,'Key')
      job:call(Poly.save,r,s.take,rec)
      return rec
    end,.012)
  end
  if e.key_job then
    local j=e.key_job;j:step()
    if j.done then
      e.key_job=nil
      if j.error then e:fail(j.error) else
        local rec=j.result;local root,sc=Poly.key_scale(rec.keys and rec.keys[1])
        if root then e:set_scale(root,sc) end
        e.key_bpm=rec.bpm;if item==e.item then e.poly=rec end
        e.message=string.format('Key %s · %.1f BPM',Poly.key_name(rec.keys and rec.keys[1]),rec.bpm or 0)
        e.key_modal=nil
      end
    end
  end
end
-- полоса аккордов над линейкой: регионы-плашки с именем; наведение — подсказка, ПКМ — меню экспорта
function M.poly_lane(im,dl,ctx,g)
  local rec=g.rec or PolyRec;if not rec or g.lane<=0 then return end
  -- верх полосы (5 px) свободен под соединительную линию тайм-селекшна: она идёт НАД аккордами
  local y1,y2=g.y+5,g.y+g.lane-1;local th=im.GetTextLineHeight(ctx) or 13;local hover
  im.DrawList_PushClipRect(dl,g.left,g.y,g.right,g.y+g.lane+1,true)
  for _,c in ipairs(rec.chords) do
    local x1,x2=g.tx(c.s),g.tx(c.e)
    if x2>=g.left and x1<=g.right then
      local nc=c.root<0
      local col=nc and 0x2E2E2EFF or chord_color(c.root,0xD8)
      im.DrawList_AddRectFilled(dl,x1+1,y1,x2-1,y2,col,4)
      local name=Poly.chord_name(c);local tw=im.CalcTextSize(ctx,name)
      if x2-x1<=tw+8 then name=Poly.chord_name(c,true);tw=im.CalcTextSize(ctx,name) end -- узкий регион: короткое имя
      if x2-x1>tw+8 then im.DrawList_AddText(dl,math.floor(math.max(x1+4,math.min(g.left+4,x2-tw-4))),math.floor(y1+(y2-y1-th)/2)-1,nc and 0x8A8A96FF or 0xF4F4F8FF,name) end
      if g.hovered and g.mx>=x1 and g.mx<=x2 and g.my>=y1 and g.my<=y2 then hover=c end
    end
  end
  im.DrawList_PopClipRect(dl)
  local ed=g.editor or PolyEditor
  if g.hovered and g.my>=g.y and g.my<=y2 and g.mx>=g.left and g.mx<=g.right and im.IsMouseClicked(ctx,1) then ed.chord_menu={x=g.mx,y=g.my} end
  -- левая кнопка на плашке: потянуть — аккорд уходит в проект MIDI-айтемом (M.chord_drag); клик без движения ничего не делает
  if hover and hover.root and hover.root>=0 and im.IsMouseClicked(ctx,0) and not ed.chord_press then
    ed.chord_press={chord=hover,x=g.mx,y=g.my,fresh=true}
  end
end
-- Перетаскивание аккорда: призрак MIDI-айтема (плашка с именем и мини-нотами) плавно едет за курсором и вырастает из плашки;
-- по отпусканию над таймлайном REAPER — MIDI-айтем в месте под курсором (трек под курсором, иначе новый трек).
local function ease(t) t=math.max(0,math.min(1,t));return 1-(1-t)*(1-t)*(1-t) end
function M.chord_drag(host,im,ctx,e)
  local cp=e.chord_press;if not cp then return end
  cp.fresh=nil
  local r=e.r;local mx,my=im.GetMousePos(ctx);local now=r.time_precise()
  if im.IsMouseDown(ctx,0) then
    if not cp.active and (math.abs(mx-cp.x)>5 or math.abs(my-cp.y)>5) then cp.active=true;cp.t0=now;cp.px,cp.py=cp.x,cp.y;cp.last=now end
    if cp.active then
      local dt=math.min(.05,now-(cp.last or now));cp.last=now
      local f=math.min(1,dt*16) -- пружина: призрак догоняет курсор
      cp.px=cp.px+(mx-cp.px)*f;cp.py=cp.py+(my-cp.py)*f
      local k=ease((now-cp.t0)/.16) -- появление: из размера плашки до полного
      local c=cp.chord;local pitches=PolyExport.chord_pitches(c)
      local W,H=math.floor(96+54*k),math.floor(22+40*k)
      local x,y=math.floor(cp.px+14),math.floor(cp.py+10)
      -- призрак — отдельное безрамочное окно: оно может выйти за пределы окна скрипта и ехать над таймлайном REAPER
      local flags=(im.WindowFlags_NoDecoration or 0)|(im.WindowFlags_NoInputs or 0)|(im.WindowFlags_NoSavedSettings or 0)|(im.WindowFlags_NoFocusOnAppearing or 0)|(im.WindowFlags_NoBackground or 0)|(im.WindowFlags_NoNav or 0)|(im.WindowFlags_TopMost or 0)
      im.SetNextWindowPos(ctx,x,y);im.SetNextWindowSize(ctx,W+8,H+8)
      local visible=im.Begin(ctx,'##vocaligner_chord_ghost',nil,flags)
      if visible then
        local dl=im.GetWindowDrawList(ctx);local wx,wy=im.GetWindowPos(ctx);wx,wy=wx+2,wy+2
        im.DrawList_AddRectFilled(dl,wx+3,wy+4,wx+W+3,wy+H+4,0x00000070,6)
        im.DrawList_AddRectFilled(dl,wx,wy,wx+W,wy+H,chord_color(c.root,0xE6),6)
        im.DrawList_AddRect(dl,wx+.5,wy+.5,wx+W-.5,wy+H-.5,0xFFFFFF90,6,0,1)
        im.DrawList_AddText(dl,wx+7,wy+3,0xFFFFFFFF,Poly.chord_name(c))
        -- мини-пианоролл: ноты аккорда полосками, как в MIDI-айтеме
        local lo,hi=1e9,-1e9;for _,p in ipairs(pitches) do lo=math.min(lo,p[1]);hi=math.max(hi,p[1]) end
        local top,bot=wy+20,wy+H-5;local span=math.max(12,hi-lo)
        if bot-top>8 then for _,p in ipairs(pitches) do
          local yy=bot-(p[1]-lo)/span*(bot-top-3)
          im.DrawList_AddRectFilled(dl,wx+6,yy-1.5,wx+W-6,yy+1.5,0xFFFFFFCC,1.5)
        end end
        im.End(ctx)
      end
    end
  else
    e.chord_press=nil
    if not cp.active then return end
    -- отпустили: внутри окна скрипта — отмена; над таймлайном REAPER — вставка
    local wx,wy=im.GetWindowPos(ctx);local ww,wh=im.GetWindowSize(ctx)
    if mx>=wx and mx<=wx+ww and my>=wy and my<=wy+wh then return end
    local sx,sy=r.GetMousePosition()
    local at
    if r.BR_PositionAtMouseCursor then at=r.BR_PositionAtMouseCursor(true);if at and at<0 then at=nil end end
    local track=r.GetTrackFromPoint and select(1,r.GetTrackFromPoint(sx,sy))
    if not at then
      if r.BR_PositionAtMouseCursor then e.message='Drop the chord onto the project timeline';return end
      at=r.GetCursorPositionEx(e.project or 0);e.message='Dropped at the edit cursor (install SWS for exact placement under the mouse)'
    end
    local good,why=pcall(PolyExport.drop_chord,e,cp.chord,at,track)
    if good then e.message=string.format('%s dropped at %.2f s',Poly.chord_name(cp.chord),at) else e:fail(why) end
  end
end
function M.body(host,im,ctx,app)
  local e=app.pitch
  local show_chords=e.r.GetExtState('Vocaligner Pitch View 1','show_chords')=='1'
  PolyRec=(e.mode=='poly' or show_chords) and e.poly or nil;PolyEditor=e
  local error=e.error and e.error:match('^[^\r\n]+'):gsub('^.*:%d+: ','')
  -- прогресс рисуем поверх верхнего края тела вкладки, не занимая места в раскладке
  do local wx,wy=im.GetWindowPos(ctx);local ww=im.GetWindowSize(ctx);local job=e.job
    if Progress.visible(job,e.r.time_precise()) then
      local dl=im.GetWindowDrawList(ctx);local now=e.r.time_precise();local pr=math.max(0,math.min(1,job.progress or 0))
      if pr>0 then im.DrawList_AddRectFilled(dl,wx,wy,wx+ww*pr,wy+3,0x78C8ADCC,0)
      else local f=(now-job.created_at)*.65%1;local pos=(1-math.abs(f*2-1))*.84;im.DrawList_AddRectFilled(dl,wx+ww*pos,wy,wx+ww*(pos+.16),wy+3,0x78C8ADCC,0) end
    end end
  if e.stale then im.TextWrapped(ctx,'Saved analysis is out of date. Click Analyze to edit this item.')
  elseif error then im.TextWrapped(ctx,error) end
  local cw,ch=im.GetContentRegionAvail(ctx)
  PitchUI.options.ghost_button=true
  PitchUI.options.autoscroll=host.settings~=nil and host.settings.autoscroll==true -- автоскролл как в FL (Settings)
  PitchUI.options.scroll_pos=({.22,.5,.78})[host.settings and host.settings.scroll_pos or 1] or .22
  PitchUI.options.smooth=host.settings==nil or host.settings.smooth~=false -- плавный скролл/зум (отключается в Settings)
  PitchUI.options.fast_motion=host.settings==nil or host.settings.fast_motion~=false -- лёгкая отрисовка во время зума (Settings)
  PitchUI.options.icon=host.icon;PitchUI.options.ghost_icon=SP.ghost;PitchUI.options.aim_icons={SP.aim_on,SP.aim_off}
  tip_text=nil
  -- прокси ленивый: каждая функция берётся из im один раз и кладётся в прокси (без лишнего поиска на каждый вызов)
  local proxy=setmetatable({SetTooltip=function(_,text) tip_text=text end},{__index=function(t,k) local v=im[k];rawset(t,k,v);return v end})
  local bx0,by0=im.GetCursorScreenPos(ctx)
  -- закреплённая «Analyze selected» поверх холста (не скроллится с нотами): только если выделенному аудио нужен анализ
  local selected=e.r.CountSelectedMediaItems(e.r.EnumProjects(-1))
  local show_analyze=selected>0 and e:needs_analysis() and not e:busy()
  local abw,abh=math.min(cw-40,260),40;local abx,aby=bx0+(cw-abw)/2,by0+math.max(70,ch*.32)
  local mx,my=im.GetMousePos(ctx)
  local over=show_analyze and mx>=abx and mx<=abx+abw and my>=aby and my<=aby+abh
  if e.key_modal then over=true end -- окно анализа тональности поверх: холст не принимает клики
  e.block_click=over
  do -- ПКМ по линейке (над сеткой): Show chords + экспорт; без анализа — ничего
    local rtop,rbot=by0,by0+26+(e.poly_lane or 0)
    if e.poly and not e.key_modal and mx>=bx0+42 and mx<=bx0+cw-12 and my>=rtop and my<=rbot and im.IsMouseClicked(ctx,1) and im.IsWindowHovered(ctx,im.HoveredFlags_ChildWindows or 0) then
      e.chord_menu={x=mx,y=my}
    end
  end
  local poly=e.mode=='poly'
  local saved
  if poly then
    -- Polyphonic: холст — только просмотр. Мелодические ноты/кривые и инструменты правки на время кадра скрыты;
    -- найденные ноты рисует слой poly_draw, аккорды — полоса над линейкой
    saved={e.data,e.notes,e.partial,e.state,e.display}
    e.data=nil;e.notes={};e.partial=nil;e.state=nil;e.display=nil
    e.poly_fit=e.poly and e.poly.notes or nil
    e.poly_lane=e.poly and #e.poly.chords>0 and 22 or 0
    e.poly_draw=M.poly_notes;e.poly_lane_draw=M.poly_lane
  else
    e.poly_draw=nil;e.poly_fit=nil
    -- Melodic: полоса аккордов, если у айтема есть Polyphonic-анализ и она включена (ПКМ по линейке)
    if show_chords and e.poly and #e.poly.chords>0 then e.poly_lane=22;e.poly_lane_draw=M.poly_lane else e.poly_lane=0;e.poly_lane_draw=nil end
  end
  local ok,err=pcall(PitchUI.canvas,proxy,ctx,e,cw,ch)
  M.chord_drag(host,im,ctx,e)
  if saved then e.data,e.notes,e.partial,e.state,e.display=saved[1],saved[2],saved[3],saved[4],saved[5] end
  if not ok then error(err,0) end
  -- плейхед ушёл в другой проанализированный айтем этого трека — он становится активным (не во время правки)
  do
    local proj=e.project or 0;local ps=e.r.GetPlayStateEx and e.r.GetPlayStateEx(proj) or 0
    if (ps&1)~=0 and e.snapshot and e.track_row and not e:busy() and not e.gesture and not e.drag then
      local t=e.r.GetPlayPositionEx(proj);local s=e.snapshot
      -- только при ВХОДЕ плейхеда в новый айтем: выбранный кликом айтем не перехватывается обратно тем, что под плейхедом
      local under
      for _,entry in ipairs(e.track_row.items) do
        if entry.state and entry.state.analysis and t>=entry.pos and t<entry.pos+entry.len and Workspace.same_lane(e,entry) then under=entry.item;break end
      end
      under=under or false
      if under~=e.follow_item then
        e.follow_item=under
        if under and under~=e.item and (t<s.pos-.02 or t>s.pos+s.len+.02) then e:activate(under) end
      end
    elseif (ps&1)==0 then e.follow_item=nil end
  end
  if show_analyze then
    local dl=im.GetWindowDrawList(ctx)
    im.DrawList_AddRectFilled(dl,abx+2,aby+3,abx+abw+2,aby+abh+3,0x00000060,12) -- тень
    im.DrawList_AddRectFilled(dl,abx,aby,abx+abw,aby+abh,over and 0xC86A2AFF or 0xA9551EFF,12)
    local label=(poly and 'Analyze selected · Polyphonic' or 'Analyze selected')..(selected>1 and string.format(' (%d)',selected) or '')
    local tw,th=im.CalcTextSize(ctx,label)
    im.DrawList_AddText(dl,math.floor(abx+(abw-tw)/2),math.floor(aby+(abh-th)/2),0xFFFFFFFF,label)
    if over then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
    if over and im.IsMouseClicked(ctx,0) then e:analyze_mode() end
  end
  if e.key_modal then M.key_modal(host,im,ctx,e,bx0,by0,cw,ch) end
  if e.chord_menu then
    -- ПКМ по полосе аккордов: экспорт (в пределах тайм-селекшна, если он есть, иначе весь анализ)
    local m=e.chord_menu;e.chord_menu=nil
    local range;if e.tsel and e.snapshot then range={e.tsel[1]-e.snapshot.pos,e.tsel[2]-e.snapshot.pos} end
    local suffix=range and ' (time selection)' or ''
    local function run(fn,what) local good,n=pcall(fn,e,range);if good then e.message=string.format('%s: %d exported',what,n) else e:fail(n) end end
    host.dropdown('pitch_chords',m.x,m.y,{
      {label='Show chords',checked=e.mode=='poly' or show_chords,disabled=e.mode=='poly',action=function() e.r.SetExtState('Vocaligner Pitch View 1','show_chords',show_chords and '0' or '1',true) end},
      {sep=true},
      {label='Export chords to regions'..suffix,action=function() run(PolyExport.regions,'Chord regions') end},
      {label='Export chords to a text track'..suffix,action=function() run(PolyExport.text_track,'Chord text items') end},
      {label='Export chords to a MIDI track'..suffix,action=function() run(PolyExport.chord_midi,'Chord MIDI') end},
      {sep=true},
      {label='Export detected notes to MIDI'..suffix,action=function() run(PolyExport.notes_midi,'Detected notes') end},
      {label='Write key and tempo to the item notes',action=function() local good,why=pcall(PolyExport.write_item_note,e.r,e.item,e.poly);if not good then e:fail(why) end end}})
  end
  if tip_text then tip_last=tip_text end
  if tip_last then
    local mx,my=im.GetMousePos(ctx)
    host.tooltip('pitch_canvas',tip_text~=nil,mx+22,my+24,'',tip_last,host.window[1],host.window[2])
  end

  -- горячие клавиши оригинального редактора + 1..5 = инструменты контейнера
  if im.IsWindowFocused(ctx,im.FocusedFlags_RootAndChildWindows) and not im.IsAnyItemActive(ctx) and not e:busy() then
    local alt=Hotkeys.alt(im,ctx)
    if e.mode~='poly' then
      for i=1,#TOOLS do if Hotkeys.pressed(im,ctx,'tool'..i) then e.tool=TOOLS[i][1] end end
    end
    -- W: курсор редактирования (и воспроизведения, если идёт play) — в начало тайм-селекшна
    if Hotkeys.pressed(im,ctx,'cursor_start') then
      -- W: в начало тайм-селекшна, а если его нет — в начало активного тейка
      local at=e.tsel and e.tsel[1] or (e.snapshot and e.snapshot.pos)
      if at then e.r.SetEditCurPos2(e.project or 0,at,true,true);e.goto_time=at-(e.snapshot and e.snapshot.pos or 0) end -- + скролл редактора к этому месту
    end
    -- Esc: сначала сбрасывается тайм-селекшн, затем выделение нот
    if Hotkeys.pressed(im,ctx,'clear') then
      if e.tsel then e.r.GetSet_LoopTimeRange2(e.project or 0,true,false,0,0,false);e.tsel=nil
      elseif e:has_selection() then e.selected={} end
    end
    if Hotkeys.pressed(im,ctx,'undo') then e:undo(false) elseif Hotkeys.pressed(im,ctx,'redo') then e:undo(true) end
    if Hotkeys.pressed(im,ctx,'select_all') then for _,n in ipairs(e.notes or {}) do e.selected[n.id]=true end end
    if Hotkeys.pressed(im,ctx,'reset_notes') then e:reset_selected() end
    if Hotkeys.pressed(im,ctx,'copy_shape') then e:copy_shape()
    elseif Hotkeys.pressed(im,ctx,'tool_toggle') then e.tool=e.tool=='notes' and 'curve' or 'notes' end
    if Hotkeys.pressed(im,ctx,'paste_shape') then e:paste_shape(alt) end
    if Hotkeys.pressed(im,ctx,'nudge_up') then e:nudge(1,alt) end
    if Hotkeys.pressed(im,ctx,'nudge_down') then e:nudge(-1,alt) end
  end
end
return M
