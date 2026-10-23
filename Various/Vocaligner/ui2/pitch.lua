-- @noindex
-- Pitch editor в новом интерфейсе. Холст и логика правок — pitch/ui.lua и pitch/editor.lua (оригиналы работают как раньше);
-- здесь только панель инструментов, которая занимает место второго топбара (оболочка ui2.lua сжимает его вдвое),
-- и тело вкладки. Вместо прежнего ряда кнопок: кнопка «назад», Analyze, контейнер иконок-инструментов без отступов,
-- Tracks, Source и параметры инструмента, которые двигаются мышью в любом направлении. Подсказки — облачка оболочки.
local import=...;local PitchUI=import('pitch/ui');local Link=import('pitch/link');local Workspace=import('pitch/workspace')
local Curve=import('pitch/curve');local Scale=import('pitch/scale');local Progress=import('progress');local M={}
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
    if im.IsItemActivated(ctx) then activated=true;st.edited=false;st.value=value end
    if active then
      im.SetMouseCursor(ctx,im.MouseCursor_ResizeAll)
      local dx,dy=im.GetMouseDelta(ctx)
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

  -- Analyze: только пока item не проанализирован; полный сброс — в меню справа
  local now=e.r.time_precise()
  local freeze=(e.job~=nil and e.job.kind=='apply') or now<stable.until_t -- bypass/правка: кнопки не мигают
  if e.job~=nil and e.job.kind=='apply' then stable.until_t=now+0.3 end
  if not freeze then stable.analyzed=e.data~=nil and not e.stale and not e.no_selection end
  local analyzed=stable.analyzed
  local show_busy=busy and not freeze
  if not analyzed then
    im.SetCursorScreenPos(ctx,x,y)
    if show_busy then im.BeginDisabled(ctx,true) end
    if im.Button(ctx,'Analyze',0,fh) then e:analyze() end
    if show_busy then im.EndDisabled(ctx) end
    host.tooltip('pitch_analyze',im.IsItemHovered(ctx),(im.GetItemRectMin(ctx)+im.GetItemRectMax(ctx))/2,y+fh,'',
      'Analyze selected audio items; with no item selection, analyze the active track. Reanalysis keeps editor corrections when their source geometry still matches.',wx,ww)
    x=im.GetItemRectMax(ctx)+G
  end
  if e.job and not e.job.committed and e.job.kind=='analysis' then
    im.SetCursorScreenPos(ctx,x,y);if im.Button(ctx,'Cancel',0,fh) then e:cancel() end
    x=im.GetItemRectMax(ctx)+G
  end

  -- Bypass редактора (иконка питания, как в глобальном BYPASS ALL): показывает оригинальные ноты и отключает ReaPitch
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
  if e.tool=='curve' then right[#right+1]={'copy',button_w('Copy')};right[#right+1]={'paste',button_w('Paste')} end
  if e.twins and #e.twins>0 then right[#right+1]={'sync',fh} end -- есть копии открытого айтема
  right[#right+1]={'auto',button_w('ATune')}
  right[#right+1]={'scale',scale_w}
  local total=-6;for _,r in ipairs(right) do total=total+r[2]+6 end
  local count=#TOOLS+1;local cwid=count*BTN_W
  local rx=x0+w-G-total
  local cx0=math.max(x0+(w-cwid)/2,left_end+10)
  if cx0+cwid+12>rx then cx0=math.max(left_end+4,rx-cwid-12) end

  -- Контейнер инструментов по центру: одна плашка, кнопки впритык (выбранная — акцентная заливка)
  local locked=busy or e.gesture
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
  return {
    {label='Reset corrections',disabled=not can,action=function() e:reset_all(Workspace.targets(e)) end},
    {label='Reset full',disabled=not can,action=function() e:reset_all(Workspace.targets(e),true) end},
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
    for _,row in ipairs(e.workspace.tracks) do if (row.analyzed or 0)>0 then sel_w=math.max(sel_w,(im.CalcTextSize(ctx,short_name(row))))end end
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
    for _,row in ipairs(e.workspace.tracks) do if (row.analyzed or 0)>0 then
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
    for _,row in ipairs(e.workspace.tracks) do if (row.analyzed or 0)>0 then
      n=n+1;sel_w=math.max(sel_w,(im.CalcTextSize(ctx,short_name(row))))
    end end
  end
  local w=fh+6+sel_w+14
  local rows=n>0 and (n*fh+(n-1)*spacing) or im.GetTextLineHeight(ctx)
  return math.max(w,n==0 and (im.CalcTextSize(ctx,'No analyzed tracks')) or 0),fh+spacing+5+spacing+rows
end
function M.ghost_count(app)
  local n=0;local e=app.pitch
  if e.workspace then for _,row in ipairs(e.workspace.tracks) do if (row.analyzed or 0)>0 then n=n+1 end end end
  return math.max(n,1)
end

-- Тело вкладки: прогресс, сообщения и холст. Подсказки холста уводятся из-под курсора в облачко оболочки.
local tip_text,tip_last
local KEYS={'Key_1','Key_2','Key_3','Key_4','Key_5','Key_6'}
function M.body(host,im,ctx,app)
  local e=app.pitch
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
  PitchUI.options.icon=host.icon;PitchUI.options.ghost_icon=SP.ghost;PitchUI.options.aim_icons={SP.aim_on,SP.aim_off}
  tip_text=nil
  -- прокси ленивый: каждая функция берётся из im один раз и кладётся в прокси (без лишнего поиска на каждый вызов)
  local proxy=setmetatable({SetTooltip=function(_,text) tip_text=text end},{__index=function(t,k) local v=im[k];rawset(t,k,v);return v end})
  PitchUI.canvas(proxy,ctx,e,cw,ch)
  if tip_text then tip_last=tip_text end
  if tip_last then
    local mx,my=im.GetMousePos(ctx)
    host.tooltip('pitch_canvas',tip_text~=nil,mx+22,my+24,'',tip_last,host.window[1],host.window[2])
  end

  -- горячие клавиши оригинального редактора + 1..5 = инструменты контейнера
  if im.IsWindowFocused(ctx,im.FocusedFlags_RootAndChildWindows) and not im.IsAnyItemActive(ctx) and not e:busy() then
    local mods=im.GetKeyMods(ctx);local ctrl=(mods&im.Mod_Ctrl)~=0;local alt=(mods&im.Mod_Alt)~=0
    if mods==0 then
      for i,k in ipairs(KEYS) do if im[k] and im.IsKeyPressed(ctx,im[k],false) then e.tool=TOOLS[i][1] end end
    end
    -- W: курсор редактирования (и воспроизведения, если идёт play) — в начало тайм-селекшна
    if mods==0 and im.IsKeyPressed(ctx,im.Key_W,false) then
      -- W: в начало тайм-селекшна, а если его нет — в начало активного тейка
      local at=e.tsel and e.tsel[1] or (e.snapshot and e.snapshot.pos)
      if at then e.r.SetEditCurPos2(e.project or 0,at,true,true);e.goto_time=at-(e.snapshot and e.snapshot.pos or 0) end -- + скролл редактора к этому месту
    end
    -- Esc: сначала сбрасывается тайм-селекшн, затем выделение нот
    if im.IsKeyPressed(ctx,im.Key_Escape,false) then
      if e.tsel then e.r.GetSet_LoopTimeRange2(e.project or 0,true,false,0,0,false);e.tsel=nil
      elseif e:has_selection() then e.selected={} end
    end
    if ctrl and im.IsKeyPressed(ctx,im.Key_Z,false) then e:undo((mods&im.Mod_Shift)~=0) end
    if ctrl and im.IsKeyPressed(ctx,im.Key_A,false) then for _,n in ipairs(e.notes or {}) do e.selected[n.id]=true end end
    if im.IsKeyPressed(ctx,im.Key_Delete,false) then e:reset_selected() end
    if ctrl and im.IsKeyPressed(ctx,im.Key_C,false) then e:copy_shape()
    elseif im.IsKeyPressed(ctx,im.Key_C,false) then e.tool=e.tool=='notes' and 'curve' or 'notes' end
    if ctrl and im.IsKeyPressed(ctx,im.Key_V,false) then e:paste_shape(alt) end
    if im.IsKeyPressed(ctx,im.Key_UpArrow,false) then e:nudge(1,alt) end
    if im.IsKeyPressed(ctx,im.Key_DownArrow,false) then e:nudge(-1,alt) end
  end
end
return M
