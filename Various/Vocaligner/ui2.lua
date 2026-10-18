-- @noindex
-- Новый интерфейс (оболочка): окно без системного заголовка, топбар с кнопками, плитки-вкладки из спрайта
-- с группами Artifacts / Dynamics, кастомные тултипы и модальное облачко Settings.
-- Тот же контракт, что у ui.lua: draw(im, ctx, app) -> open. Оригинальный ui.lua не тронут.
-- Новые страницы: Breath (ui2/breath.lua) и DeClick (ui2/declick.lua); остальные вкладки рисуются оригинальными телами.
local import=...;local Settings=import('compressor/settings');local CompUI=import('compressor/ui')
local CleanerUI=import('cleaner_ui');local AlignUI=import('align_ui');local PitchUI=import('pitch/ui');local Wave=import('waveform')
local Breath=import('ui2/breath');local Declick=import('ui2/declick');local Dynamics=import('ui2/dynamics');local Master=import('ui2/master');local Pitch2=import('ui2/pitch');local Sampler=import('ui2/sampler')
local root=debug.getinfo(1,'S').source:match([[^@(.+[\/])]])
local M={}
local ImGui,ctx,app -- выставляются в draw() на каждый кадр
local R             -- ресурсы (спрайты, шрифты): создаются один раз

-- ===== цвета и тема оригинальных тел (как в ui.lua) =====
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

-- ===== размеры и цвета оболочки =====
local S={tooltips=true,delay=0.35,smooth=true,anim=true,autoscroll=true,scroll_pos=1}
local dd={t=0,open=false} -- состояние универсального выпадающего списка (ниже) -- настройки интерфейса (облачко Settings); delay = задержка показа тултипа
local WRND=12 -- скругление окна
local PSZ=28 -- размер родителя, когда его группа раскрыта
local GP=7 -- боковой отступ внутри контейнера группы
local SZ,CSZ,GAP,CGAP,PAD,LBL,RND=50,44,9,8,9,17,0.15 -- SZ/CSZ: плитка верхнего ряда / внутри группы
local BYPASS_COL=0xE8955AFF -- включённый bypass (всё отключено)
local TOGC=0xD2D2DAFF -- цвет кнопки питания во включённом состоянии
local TGK=0.8 -- масштаб кнопки питания у дочерних плиток
local TGC=-1 -- добавка к отступу кнопки у дочерних плиток
local TG,TGY=10.5,10.5 -- отступ центра кнопки on/off от правого верхнего угла плитки: справа / сверху
local SWAP=0.8 -- при каком перекрытии слота соседа плитки меняются местами
local ACC_P,ACC_C=0x5AA9FFFF,0x5AA9FFFF -- акценты: родители / дочерние
local LINE,PANEL,BG=0x3A3A3AFF,0x232323FF,0x1A1A1AFF
local TBH,PW,PH=33,30,23 -- топбар: высота, размер плашек кнопок
local TB_BG,PILL=0x141414FF,0x262626FF
local TIPW=250 -- ширина облачка тултипа с текстом

-- ===== плитки: id = имя вкладки app.tab; mode = режим cleaner (для bypass) =====
local N={
  artifacts={label='Artifacts',icon=5,kids=true},
  dynamics={label='Dynamics',icon=4,kids=true},
  pitch={label='Pitch',icon=3,tab='pitch'},align={label='Align',icon=1,tab='align'},
  breath={label='Breath',icon=7,tab='breath',mode='breath'},declick={label='DeClick',icon=5,tab='declick'},
  compressor={label='Comp',icon=4,tab='compressor',mode='compressor'},
  deess={label='De-ess',icon=6,tab='deess',mode='deess'},gate={label='Gate',icon=2,tab='gate',mode='gate'},
}
local TOP={'artifacts','dynamics','pitch','align'} -- порядок фиксирован
local KIDS={artifacts={'breath','declick'},dynamics={'compressor','deess','gate'}}
local DRAG={dynamics=true} -- где можно менять порядок
for g,ks in pairs(KIDS) do for _,k in ipairs(ks) do N[k].child=true;N[k].parent=g end end
local hv,sel,ex,rel,ry,lift,tg,flag={},{},{},{},{},{},{},{}
for id,n in pairs(N) do
  hv[id],sel[id],lift[id],tg[id]=0,0,0,0
  if n.kids then ex[id]=0 end
end
local open={}
local cur,last,drag,late,inited
local dimv=0 -- затемнение остальных плиток на время драга (0..1)
local window_sized
local fps_last,fps_dt
local PBH=38 -- высота второго топбара на странице инструментов Pitch (вдвое ниже обычной)
local tb_in=0 -- появление панели Pitch в топбаре 0..1
local pitch_page,pbar,HOST='tools',0,nil -- страница Pitch: 'tools' | 'menu'; pbar 0..1 — сжатие бара; HOST — данные окна для Pitch
local lockv,locked=0,false -- затемнение и блокировка плиток при включённом bypass
local pop={open=false,t=0,ax=0,ay=0}
local ghost={open=false,t=0}
local pending,quit
local tips,TIP,wrapc={}, {}, {}
local phv={menu=0,close=0,report=0,master=0}
local NL=string.char(10)

local function lc(a,b,t)
  local o=0
  for s=24,0,-8 do
    local ca,cb=(a>>s)&255,(b>>s)&255
    o=(o<<8)|math.floor(ca+(cb-ca)*t+0.5)
  end
  return o
end
local function fa(c,a) return (c&~255)|math.floor((c&255)*a+0.5) end -- множитель альфы
local function ap(c,t,k) if S.anim==false then return t end return c+(t-c)*k end
local function ease(t) return 1-(1-t)^3 end
local function clampf(v,a,b) return math.max(a,math.min(b,v)) end
local function accent(id) return N[id].child and ACC_C or ACC_P end

-- ===== ресурсы =====
local function init()
  if R and R.ctx==ctx then return end
  R={ctx=ctx}
  R.sp={n=7,w=672,img=ImGui.CreateImage(root..'ui2/assets/icons.png')};ImGui.Attach(ctx,R.sp.img)
  R.ui={n=3,w=168,img=ImGui.CreateImage(root..'ui2/assets/ui.png')};ImGui.Attach(ctx,R.ui.img)
  R.pt={n=9,w=864,img=ImGui.CreateImage(root..'ui2/assets/pitch.png')};ImGui.Attach(ctx,R.pt.img) -- иконки Pitch: карандаш, навигация, повтор(+выкл), магнит(+выкл)
  local family=(reaper.GetOS() or ''):find('Win') and 'Segoe UI' or 'sans-serif'
  local function mk(sz,flags) local f=ImGui.CreateFont(family,sz,flags or 0);ImGui.Attach(ctx,f);return f end
  R.F_LBL,R.F_TIPB,R.F_TILE=mk(14),mk(14,ImGui.FontFlags_Bold),mk(12)
  R.F_TIPI=mk(12,ImGui.FontFlags_Italic)
end
local function sprite(dl,i,x1,y1,x2,y2,col,rnd)
  local e=0.5/R.sp.w -- полтекселя внутрь, чтобы не тянуло соседнюю иконку
  ImGui.DrawList_AddImageRounded(dl,R.sp.img,x1,y1,x2,y2,(i-1)/R.sp.n+e,0,i/R.sp.n-e,1,col,rnd)
end
local function pitch_icon(dl,i,cx,cy,size,col) -- иконка из pitch.png (белая, тонируется col); size — сторона ячейки
  local h,e=size/2,0.5/R.pt.w
  ImGui.DrawList_AddImage(dl,R.pt.img,cx-h,cy-h,cx+h,cy+h,(i-1)/R.pt.n+e,0,i/R.pt.n-e,1,col)
end
local function uisprite(dl,i,cx,cy,size,col) -- ячейка = плашка иконки, сам глиф занимает ~60%
  local h,e=size/2,0.5/R.ui.w
  ImGui.DrawList_AddImage(dl,R.ui.img,cx-h,cy-h,cx+h,cy+h,(i-1)/R.ui.n+e,0,i/R.ui.n-e,1,col)
end

-- ===== состояние вкладок и связь с app =====
local function dyn_order() -- порядок обработки из конфига (breath здесь не участвует)
  local out={}
  for _,key in ipairs(Settings.parse(app.cleaner.cfg.chain_order)) do if key~='breath' then out[#out+1]=key end end
  return out
end
-- включена ли плитка: для стадий cleaner это «не в bypass», для остальных локальный флаг
local function is_on(id)
  local n=N[id]
  if n.mode then local c=app.cleaner;return not c:bypassed(c:current(),n.mode) end
  if id=='declick' then return Declick.is_on() end
  return flag[id]~=false
end
local function lit(id) -- группа «горит», если включён хоть один потомок
  if not N[id].kids then return is_on(id) end
  for _,k in ipairs(KIDS[id]) do if is_on(k) then return true end end
  return false
end
local function go(id) -- выбрать плитку: обновляет app.tab
  local n=N[id]
  cur=id
  if id=='pitch' then pitch_page='tools' end -- вход в Pitch показывает его инструменты
  if n.parent then last[n.parent]=id end
  if n.tab and app.tab~=n.tab then
    if app.tab=='pitch' and n.tab~='pitch' then app.pitch:cancel() end
    app.tab=n.tab
  end
end
-- Тоггл плитки = Bypass на стадии cleaner. Для стадии не из текущей вкладки сначала переходим на неё.
local function toggle(id)
  local n=N[id]
  if n.mode then
    local c=app.cleaner;local bypass=is_on(id)
    if app.tab==n.mode and c.mode==n.mode then
      if c:can_bypass(c:current()) then c:set_bypass(bypass) end
    else
      pending={mode=n.mode,bypass=bypass,t=reaper.time_precise()};go(id)
    end
  elseif id=='declick' then Declick.toggle()
  else flag[id]=not is_on(id) end
end
local function apply_pending()
  if not pending then return end
  local c=app.cleaner
  if reaper.time_precise()-pending.t>2 then pending=nil;return end
  if c.mode==pending.mode then
    if c:can_bypass(c:current()) then c:set_bypass(pending.bypass) end
    pending=nil
  end
end
local function sync() -- первая синхронизация и внешняя смена app.tab
  if cur and N[cur] and N[cur].tab==app.tab then return end
  for id,n in pairs(N) do if n.tab==app.tab then cur=id end end
  cur=cur or 'align'
  local p=N[cur].parent
  if p then open[p]=true end
  if not inited then
    inited=true;last={};late={}
    for g in pairs(KIDS) do ex[g]=open[g] and 1 or 0 end
  end
end
-- Итоговый порядок Dynamics после драга -> cleaner:reorder (один раз при отпускании)
local function commit_order(grp,start,final)
  if grp~='dynamics' then return end
  local c,list=app.cleaner,{table.unpack(start)}
  for i=1,#final do
    if list[i]~=final[i] then
      c:reorder(N[final[i]].tab,N[list[i]].tab)
      for k,v in ipairs(list) do if v==final[i] then table.remove(list,k);break end end
      table.insert(list,i,final[i])
    end
  end
end

-- центр кнопки питания: привязан к углу иконки с учётом её роста/подъёма при выделении и драге
local function tpos(id,x,y,sz)
  local sl,lf=sel[id],lift[id]
  local h=sz/2*(1+0.08*lf+0.04*sl+0.022*hv[id]*(1-sl))
  local ex_=N[id].child and TGC or 0
  return x+sz/2+h-TG-ex_,y+sz/2-2*sl-4*lf-h+TGY+ex_
end

-- отрисовка плитки в позиции x,y: скруглённая иконка, «мутная» в покое, яркая при выделении
-- clip = {x1,y1,x2,y2}: рисунок не выходит за контейнер
local function paint(id,x,y,a,sz,clip,lab)
  local dl,n,ACC=ImGui.GetWindowDrawList(ctx),N[id],accent(id)
  if clip then ImGui.DrawList_PushClipRect(dl,clip[1],clip[2],clip[3],clip[4],true) end
  local sl,lf=sel[id],lift[id]
  local s=1+0.08*lf+0.04*sl+0.022*hv[id]*(1-sl) -- при наведении лёгкий рост, при выделении больше
  local cx,cy,h=x+sz/2,y+sz/2-2*sl-4*lf,sz/2*s
  local x1,y1,x2,y2,rnd=cx-h,cy-h,cx+h,cy+h,sz*RND*s
  local on=is_on(id)
  if lf>0.01 then
    for k=1,5 do -- тень приподнятой плитки
      ImGui.DrawList_AddRectFilled(dl,x1-k*2,y1-k*2+7,x2+k*2,y2+k*2+7,fa(0x000000FF,0.08*lf*a),rnd+k*2)
    end
  end
  local dm=(1-0.5*dimv*(1-lf))*(1-0.6*lockv) -- остальные плитки темнее, пока что-то тащат; при bypass все как залоченные
  local b=(0.8+0.2*sl+0.1*hv[id]*(1-sl))*dm
  if not lit(id) then b=b*0.4 end
  local g=math.floor(math.min(b,1)*255+0.5)
  sprite(dl,n.icon,x1,y1,x2,y2,fa((g<<24)|(g<<16)|(g<<8)|255,a),rnd)
  ImGui.DrawList_AddRectFilled(dl,x1,y1,x2,y2,fa(BG,0.18*(1-sl)*a),rnd) -- дымка
  if sl>0.01 then ImGui.DrawList_AddRect(dl,x1,y1,x2,y2,fa(ACC,sl*a),rnd,0,1.5)
  elseif hv[id]>0.01 then ImGui.DrawList_AddRect(dl,x1,y1,x2,y2,fa(0xFFFFFFFF,0.22*hv[id]*a),rnd,0,1) end

  ImGui.PushFont(ctx,R.F_TILE)
  local tw=ImGui.CalcTextSize(ctx,n.label)
  local tc=lc(0x7A7A86FF,0xFFFFFFFF,math.max(sl,hv[id]*0.6))
  ImGui.DrawList_AddText(dl,x+(sz-tw)/2,y+sz+3,fa(tc,a*dm*(lab or 1)),n.label)
  ImGui.PopFont(ctx)

  local ta=a*math.max(hv[id],lf)*(1-dimv)*(1-lockv) -- кнопка питания видна, только когда курсор в плитке
  if not n.kids and ta>0.01 then
    local tx,ty=tpos(id,x,y,sz)
    local k=n.child and TGK or 1 -- в группах кнопка меньше
    local tr=(6.5+tg[id])*k
    a=ta
    ImGui.DrawList_AddRectFilled(dl,tx-tr,ty-tr,tx+tr,ty+tr,fa(0x0E0E12FF,0.85*a),3)
    ImGui.DrawList_AddRect(dl,tx-tr,ty-tr,tx+tr,ty+tr,fa(on and TOGC or 0x4A4A55FF,a),3,0,0.8)
    local gc,q=fa(on and lc(TOGC,0xFFFFFFFF,0.35) or 0x70707CFF,a),-math.pi/2
    ImGui.DrawList_PathArcTo(dl,tx,ty,(2.7+tg[id]*0.4)*k,q+0.65,q+2*math.pi-0.65)
    ImGui.DrawList_PathStroke(dl,gc,0,1.2)
    ImGui.DrawList_PathLineTo(dl,tx,ty-3.7*k) -- через Path, как и дуга: без полупиксельного сдвига AddLine
    ImGui.DrawList_PathLineTo(dl,tx,ty-0.6)
    ImGui.DrawList_PathStroke(dl,gc,0,1.2)
  end
  if clip then ImGui.DrawList_PopClipRect(dl) end
end

-- плитка: кнопка + анимации + старт драга. canDrag = id группы, где можно менять порядок. Возвращает activated
local function tile(id,x,y,a,sz,clip,canDrag,lab)
  local n,act=N[id],false
  local dragging=drag and drag.id==id
  sel[id]=ap(sel[id],((n.kids and open[id]) or (not n.kids and cur==id)) and 1 or 0,0.18)
  lift[id]=ap(lift[id],dragging and 1 or 0,0.25)
  if a>0.9 and not locked then
    ImGui.SetCursorScreenPos(ctx,x,y)
    ImGui.InvisibleButton(ctx,'##t_'..id,sz,sz+LBL*(lab or 1))
    local hov,active=ImGui.IsItemHovered(ctx),ImGui.IsItemActive(ctx)
    hv[id]=ap(hv[id],hov and 1 or 0,0.25)
    if dragging then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_ResizeAll)
    elseif hov or active then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_Hand) end
    act=ImGui.IsItemActivated(ctx)
    local tx,ty=tpos(id,x,y,sz)
    local k0=n.child and TGK or 1
    local onTg=not n.kids and not drag and hv[id]>0.3 and ImGui.IsMouseHoveringRect(ctx,tx-8*k0,ty-8*k0,tx+8*k0,ty+8*k0)
    tg[id]=ap(tg[id],onTg and 1 or 0,0.3)
    if act and onTg then toggle(id);act=false end
    if canDrag and active and not drag and ImGui.IsMouseDragging(ctx,0,4) then
      local mx,my=ImGui.GetMousePos(ctx)
      drag={id=id,grp=canDrag,gx=mx-x,gy=my-y,start={table.unpack(KIDS[canDrag])}} -- gx,gy: за какую точку схватили
    end
  else hv[id]=hv[id]*0.8 end
  if lift[id]>0.02 or dragging then late[#late+1]={id,x,y,a,sz,clip,lab} else paint(id,x,y,a,sz,clip,lab) end
  return act
end

-- рамка подконтейнера: тонкая линия, слева «носик» как у скобки «{», указывающий на родителя
local function brace(dl,L,T,Rr,B,col)
  local rr,Mid,pi=10,(T+B)/2,math.pi
  ImGui.DrawList_PathArcTo(dl,L+rr,T+rr,rr,pi,1.5*pi)
  ImGui.DrawList_PathArcTo(dl,Rr-rr,T+rr,rr,1.5*pi,2*pi)
  ImGui.DrawList_PathArcTo(dl,Rr-rr,B-rr,rr,0,0.5*pi)
  ImGui.DrawList_PathArcTo(dl,L+rr,B-rr,rr,0.5*pi,pi)
  ImGui.DrawList_PathLineTo(dl,L,Mid+10)
  ImGui.DrawList_PathBezierQuadraticCurveTo(dl,L,Mid+3,L-6,Mid)
  ImGui.DrawList_PathBezierQuadraticCurveTo(dl,L,Mid-3,L,Mid-10)
  ImGui.DrawList_PathStroke(dl,col,1,1)
end

-- ===== кастомный тултип: облачко под элементом с «носиком» вверх, всплывает с анимацией =====
-- tooltip(key,hovered,ax,ay,title,text,wx,ww,delay,speed): ax,ay = точка под элементом, куда смотрит носик;
-- wx,ww = границы окна. Вызывать каждый кадр; рисуется в конце кадра (draw_tips). text пустой = компактное облачко.
local function wrap(text,w) -- перенос по словам с учётом переводов строк, мерим текущим шрифтом
  local k=w..'|'..text
  if wrapc[k] then return wrapc[k] end
  local lines={}
  for para in (text..NL):gmatch('(.-)'..NL) do
    local cl=''
    for word in para:gmatch('%S+') do
      local try=cl=='' and word or cl..' '..word
      if cl~='' and ImGui.CalcTextSize(ctx,try)>w then lines[#lines+1]=cl;cl=word else cl=try end
    end
    lines[#lines+1]=cl
  end
  wrapc[k]=lines
  return lines
end
local function tooltip(key,hov,ax,ay,title,text,wx,ww,delay,speed)
  local st=TIP[key] or {t=0,h=0}
  TIP[key]=st
  if not S.tooltips or (key=='menu' and (pop.open or pop.t>0)) or dd.open or dd.t>0.01 then st.t,st.h=0,0;return end
  if hov and ImGui.IsMouseClicked(ctx,0) then st.t,st.h=0,0;return end -- клик по кнопке гасит её подсказку сразу
  st.h=hov and st.h+ImGui.GetDeltaTime(ctx) or 0
  st.t=ap(st.t,st.h>(delay or S.delay) and 1 or 0,speed or 0.2)
  if st.t<0.01 then st.t=0;return end
  tips[#tips+1]={st.t,ax,ay,title,text,wx,ww,key}
end
-- облачко: тень, заливка, носик вверх (в точке nx), тонкий контур. Клип/анимацию задаёт вызывающий
local function bubble(dl,L,T,Rr,B,nx,e,plain)
  local rr,pi=10,math.pi
  if plain then -- без тени и обводки (подсказки инструментов): просто плашка с носиком
    local fill=fa(PILL,e)
    ImGui.DrawList_AddRectFilled(dl,L,T,Rr,B,fill,rr)
    ImGui.DrawList_PathLineTo(dl,nx-10,T+1);ImGui.DrawList_PathBezierQuadraticCurveTo(dl,nx-3,T,nx,T-6)
    ImGui.DrawList_PathBezierQuadraticCurveTo(dl,nx+3,T,nx+10,T+1);ImGui.DrawList_PathFillConvex(dl,fill)
    return
  end
  for k=1,8 do ImGui.DrawList_AddRectFilled(dl,L-k,T-k+3,Rr+k,B+k+3,fa(0x000000FF,0.016*e),rr+k) end -- мягкая тень
  local fill,line=fa(PILL,e),fa(0x3E3E4AFF,e) -- цвет и обводка как у кнопок топбара
  ImGui.DrawList_AddRectFilled(dl,L,T,Rr,B,fill,rr)
  ImGui.DrawList_PathLineTo(dl,nx-10,T+1) -- носик: заливка
  ImGui.DrawList_PathBezierQuadraticCurveTo(dl,nx-3,T,nx,T-6)
  ImGui.DrawList_PathBezierQuadraticCurveTo(dl,nx+3,T,nx+10,T+1)
  ImGui.DrawList_PathFillConvex(dl,fill)
  ImGui.DrawList_PathArcTo(dl,L+rr,T+rr,rr,pi,1.5*pi) -- контур
  ImGui.DrawList_PathLineTo(dl,nx-10,T)
  ImGui.DrawList_PathBezierQuadraticCurveTo(dl,nx-3,T,nx,T-6)
  ImGui.DrawList_PathBezierQuadraticCurveTo(dl,nx+3,T,nx+10,T)
  ImGui.DrawList_PathArcTo(dl,Rr-rr,T+rr,rr,1.5*pi,2*pi)
  ImGui.DrawList_PathArcTo(dl,Rr-rr,B-rr,rr,0,0.5*pi)
  ImGui.DrawList_PathArcTo(dl,L+rr,B-rr,rr,0.5*pi,pi)
  ImGui.DrawList_PathStroke(dl,line,1,0.75)
end
local function draw_tips()
  -- Облачка рисуются в foreground-списке: он поверх всех окон, включая дочернее окно с холстом редактора.
  -- Заголовков нет: показывается только текст (у коротких подсказок — их единственная строка).
  local dl=ImGui.GetForegroundDrawList(ctx)
  ImGui.PushFont(ctx,R.F_TILE)
  local lh=ImGui.GetTextLineHeight(ctx)+2
  for _,t in ipairs(tips) do
    local p,ax,ay,title,text,wx,ww,tkey=table.unpack(t)
    local plain=tkey~=nil and tkey:sub(1,11)=='pitch_tool_'
    local e=ease(p)
    local body=(text~=nil and text~='') and text or title
    -- «Имя	хоткей»: хоткей рисуется курсивом, приглушённо, сразу после имени
    local keyhint;do local main,k=body:match('^(.-)	(.+)$');if k then body,keyhint=main,k end end
    local tw=ImGui.CalcTextSize(ctx,body)
    local nw=tw;local kw=0
    if keyhint then ImGui.PushFont(ctx,R.F_TIPI);kw=ImGui.CalcTextSize(ctx,keyhint);ImGui.PopFont(ctx);tw=tw+6+kw end
    local compact=tw+20<=TIPW and not body:find(NL,1,true)
    local W=compact and tw+20 or TIPW
    local lines=compact and {body} or wrap(body,W-20)
    local H=#lines*lh+10
    local L=math.floor(clampf(ax-W*(compact and 0.5 or 0.8),wx+6,wx+ww-6-W)+0.5) -- целые пиксели: текст не «дрожит»
    local Rr,T=L+W,math.floor(ay+8)
    local B=T+H
    local nx=clampf(ax,L+14,Rr-14)
    ImGui.DrawList_PushClipRect(dl,L-14,T-10,Rr+14,T-10+(H+34)*e,true)
    bubble(dl,L,T,Rr,B,nx,e,plain)
    for i,ln in ipairs(lines) do ImGui.DrawList_AddText(dl,L+10,T+5+(i-1)*lh,fa(0xE2E2EAFF,e*e),ln) end
    if keyhint then
      ImGui.PushFont(ctx,R.F_TIPI);ImGui.DrawList_AddText(dl,L+10+nw+6,T+5,fa(0x8E8EA8FF,e*e),keyhint);ImGui.PopFont(ctx)
    end
    ImGui.DrawList_PopClipRect(dl)
  end
  ImGui.PopFont(ctx)
  for i=#tips,1,-1 do tips[i]=nil end
end

-- Модальное облачко как два дочерних окна, отправленных ПОСЛЕ тела вкладки (поэтому они поверх холста и виджетов):
-- (1) затемнение всего окна, оно же перехватывает клики; (2) само облачко с живыми виджетами.
-- cfg: ax,ay (куда смотрит носик), W,H (итоговый размер), dim, content(dl,L,T,Rr,B,e,ca), from_w/from_h (размер тултипа
-- кнопки: облачко вырастает из него), anchor (доля ширины слева от носика).
local MARGIN=18
local function modal(st,id,cfg)
  st.t=ap(st.t,st.open and 1 or 0,0.22)
  if st.t<0.01 then st.t=0;return end
  local wx,wy=ImGui.GetWindowPos(ctx);local ww,wh=ImGui.GetWindowSize(ctx)
  local e=ease(st.t)
  -- NoMove: клики внутри облачка не должны таскать окно скрипта
  local base=ImGui.WindowFlags_NoScrollbar|ImGui.WindowFlags_NoScrollWithMouse|ImGui.WindowFlags_NoMove
  if cfg.dim then
    ImGui.SetCursorScreenPos(ctx,wx,wy)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,0,0);ImGui.PushStyleVar(ctx,ImGui.StyleVar_ChildRounding,WRND)
    ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,fa(0x000000FF,0.55*e))
    if ImGui.BeginChild(ctx,'##dim_'..id,ww,wh,0,base) then
      if st.t>0.5 and ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx,0) then st.open=false end
      ImGui.EndChild(ctx)
    end
    ImGui.PopStyleColor(ctx);ImGui.PopStyleVar(ctx,2)
  end
  local W1,H1=cfg.W,cfg.H
  local L1=math.floor(clampf(cfg.ax-W1*(cfg.anchor or 0.5),wx+8,wx+ww-8-W1)+0.5)
  local T=math.floor(cfg.ay+8)
  local W0,H0=cfg.from_w or W1,cfg.from_h or H1
  local L0=math.floor(clampf(cfg.ax-W0/2,wx+6,wx+ww-6-W0)+0.5)
  local L,W,H=ap(L0,L1,e),ap(W0,W1,e),ap(H0,H1,e)
  local Rr,B=L+W,T+H
  ImGui.SetCursorScreenPos(ctx,L1-MARGIN,T-MARGIN)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,0,0)
  ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,0)
  if ImGui.BeginChild(ctx,'##bubble_'..id,W1+2*MARGIN,H1+2*MARGIN+4,0,base|ImGui.WindowFlags_NoBackground) then
    local dl=ImGui.GetWindowDrawList(ctx)
    local from=ease(st.from or 0)
    bubble(dl,L,T,Rr,B,clampf(cfg.ax,L+14,Rr-14),from+(1-from)*math.min(1,e*3))
    cfg.content(dl,L,T,Rr,B,e,clampf((e-0.55)/0.45,0,1),L1)
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleColor(ctx);ImGui.PopStyleVar(ctx)
  -- закрытие: клик мимо облачка (если нет затемнения) или Esc; первые кадры игнорируем, чтобы открывающий клик не закрыл
  if st.t>0.5 and ((not cfg.dim and ImGui.IsMouseClicked(ctx,0) and not ImGui.IsMouseHoveringRect(ctx,L,T-8,Rr,B,false) and not (cfg.keep and cfg.keep()))
    or ImGui.IsKeyPressed(ctx,ImGui.Key_Escape,false)) then st.open=false end
end

-- Settings: облачко вырастает из компактного тултипа кнопки; внутри общие настройки Dynamics и интерфейса
local function settings_modal()
  ImGui.PushFont(ctx,R.F_LBL)
  local tw=ImGui.CalcTextSize(ctx,'Settings')
  ImGui.PopFont(ctx)
  modal(pop,'settings',{ax=pop.ax,ay=pop.ay,W=330,H=320,anchor=0.85,dim=true,from_w=tw+20,from_h=26,
    content=function(dl,L,T,Rr,B,e,ca,L1)
      ImGui.PushFont(ctx,R.F_TIPB)
      ImGui.DrawList_AddText(dl,math.floor(ap(L+10,L1+16,e)),math.floor(ap(T+4,T+12,e)),0xFFFFFFFF,'Settings')
      ImGui.PopFont(ctx)
      if ca>0.02 then
        ImGui.PushStyleVar(ctx,ImGui.StyleVar_Alpha,ca)
        -- содержимое в собственном прокручиваемом окне (колесо работает, клик внутри не двигает окно скрипта)
        ImGui.SetCursorScreenPos(ctx,L1+8,T+38)
        ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,0);ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,8,0)
        if ImGui.BeginChild(ctx,'##settings_scroll',330-16,320-46,0,ImGui.WindowFlags_NoMove|ImGui.WindowFlags_NoBackground) then
          ImGui.TextDisabled(ctx,'Dynamics')
          CompUI.settings(ImGui,ctx,app) -- те же общие настройки, что в оригинальном окне
          ImGui.Spacing(ctx)
          ImGui.TextDisabled(ctx,'Interface')
          local _,v=ImGui.Checkbox(ctx,'Show tooltips',S.tooltips);S.tooltips=v
          ImGui.SetNextItemWidth(ctx,330-48)
          _,v=ImGui.SliderDouble(ctx,'Tooltip delay',S.delay,0,1,'%.2f s');S.delay=v
          _,v=ImGui.Checkbox(ctx,'Animations (interface)',S.anim);S.anim=v
          ImGui.Spacing(ctx)
          ImGui.TextDisabled(ctx,'Pitch editor')
          _,v=ImGui.Checkbox(ctx,'Smooth scroll and zoom',S.smooth);S.smooth=v
          _,v=ImGui.Checkbox(ctx,'Auto-scroll (with Aim)',S.autoscroll);S.autoscroll=v
          -- где стоит курсор при автоскролле: слева (22%), по центру (50%) или справа (78%)
          ImGui.TextDisabled(ctx,'Cursor position');ImGui.SameLine(ctx)
          if ImGui.RadioButton(ctx,'Left',S.scroll_pos==1) then S.scroll_pos=1 end
          ImGui.SameLine(ctx);if ImGui.RadioButton(ctx,'Center',S.scroll_pos==2) then S.scroll_pos=2 end
          ImGui.SameLine(ctx);if ImGui.RadioButton(ctx,'Right',S.scroll_pos==3) then S.scroll_pos=3 end
          if ImGui.Button(ctx,'Hotkeys…') then S.hotkeys_open=true;pop.open=false end
          ImGui.Spacing(ctx)
          ImGui.TextDisabled(ctx,'Diagnostics')
          local profiling=Sampler.running()
          if profiling then ImGui.BeginDisabled(ctx,true) end
          if ImGui.Button(ctx,profiling and 'Profiling…' or 'Profile Lua 6 s → console') then Sampler.start(6,1000) end
          if profiling then ImGui.EndDisabled(ctx) end
          ImGui.EndChild(ctx)
        end
        ImGui.PopStyleVar(ctx,2);ImGui.PopStyleColor(ctx)
      end
    end})
end


-- ===== универсальный стилевой выпадающий список (облачко): items = {{label,checked,disabled,action}|{sep=true}} =====
local DD={id=nil,items=nil,ax=0,ay=0}
local function open_dropdown(id,ax,ay,items)
  if dd.open and DD.id==id then dd.open=false;return end -- повторный клик по той же кнопке закрывает
  DD.id,DD.items,DD.ax,DD.ay=id,items,ax,ay
  if dd.open then dd.t=0 end -- переключение с другого списка: клик не должен тут же закрыть новый
  dd.open=true;dd.cw,dd.ch=nil,nil
end
local function dropdown_modal()
  if app.tab~='pitch' then dd.open=false end
  if not DD.items or (dd.t<0.01 and not dd.open) then return end
  local items=DD.items;local PAD=5
  -- точный размер считаем заранее тем же шрифтом, которым рисуем: облачко открывается сразу нужного размера
  ImGui.PushFont(ctx,R.F_TILE)
  local rh=ImGui.GetTextLineHeight(ctx)+5;local mw=0;local total=0
  for i,it in ipairs(items) do
    if it.label then mw=math.max(mw,(ImGui.CalcTextSize(ctx,it.label))) end
    total=total+(it.sep and 5 or rh)+(i>1 and 1 or 0)
  end
  ImGui.PopFont(ctx)
  local rw=mw+28 -- слева место под галочку
  modal(dd,'dd',{ax=DD.ax,ay=DD.ay,W=rw+2*PAD,H=total+2*PAD,anchor=0.5,dim=false,
    content=function(dl,L,T,Rr,B,e_,ca,L1)
      if ca<=0.02 then return end
      ImGui.PushFont(ctx,R.F_TILE)
      ImGui.PushStyleVar(ctx,ImGui.StyleVar_Alpha,ca);ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,0,1)
      ImGui.SetCursorScreenPos(ctx,L1+PAD,T+PAD)
      ImGui.BeginGroup(ctx)
      for i,it in ipairs(items) do
        if it.sep then
          local sx,sy=ImGui.GetCursorScreenPos(ctx);ImGui.Dummy(ctx,rw,5)
          ImGui.DrawList_AddLine(dl,sx+4,sy+2,sx+rw-4,sy+2,0xFFFFFF22,1)
        else
          local bx,by=ImGui.GetCursorScreenPos(ctx)
          ImGui.InvisibleButton(ctx,'##dd_'..i,rw,rh)
          local hov=ImGui.IsItemHovered(ctx) and not it.disabled
          if hov then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_Hand);ImGui.DrawList_AddRectFilled(dl,bx,by,bx+rw,by+rh,0x434C60FF,6) end
          if it.checked then
            ImGui.DrawList_PathLineTo(dl,bx+6,by+rh/2);ImGui.DrawList_PathLineTo(dl,bx+9,by+rh/2+3);ImGui.DrawList_PathLineTo(dl,bx+14,by+rh/2-3)
            ImGui.DrawList_PathStroke(dl,0xF29A5AFF,0,1.8)
          end
          ImGui.DrawList_AddText(dl,bx+20,by+(rh-ImGui.GetTextLineHeight(ctx))/2,it.disabled and 0x6A6A76FF or 0xE6E6F0FF,it.label)
          if hov and ImGui.IsItemClicked(ctx,0) then dd.open=false;if it.action then it.action() end end
        end
      end
      ImGui.EndGroup(ctx)
      ImGui.PopStyleVar(ctx,2);ImGui.PopFont(ctx)
    end})
end

-- ghost (Pitch): компактный список фоновых дорожек — чекбокс отрисовки и короткое имя для прыжка
local function ghost_modal()
  local e=app.pitch
  if e.ghost_toggle then e.ghost_toggle=nil;ghost.open=not ghost.open end
  e.ghost_open=ghost.open
  if app.tab~='pitch' then ghost.open=false end
  local b=e.ghost_btn
  if not b then return end
  -- размер считаем заранее теми же шрифтом и стилями, что у содержимого: без «раздувания» на первом кадре
  local PADX,PADY=6,9 -- по бокам поля меньше, чем сверху и снизу
  ImGui.PushFont(ctx,R.F_TILE);ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,2,1)
  local gw,gh=Pitch2.ghost_size(ImGui,ctx,app,4)
  ImGui.PopStyleVar(ctx);ImGui.PopFont(ctx)
  local W,H=gw+2*PADX,gh+2*PADY
  modal(ghost,'ghost',{ax=b.x+b.w/2,ay=b.y+b.h,W=W,H=H,anchor=0.2,dim=false,keep=function() return dd.open or dd.t>0.01 end,
    content=function(dl,L,T,Rr,B,e_,ca,L1)
      if ca>0.02 then
        ImGui.PushFont(ctx,R.F_TILE)
        ImGui.PushStyleVar(ctx,ImGui.StyleVar_Alpha,ca);ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,6,4)
        ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,2,1);ImGui.PushStyleVar(ctx,ImGui.StyleVar_FrameRounding,4)
        ImGui.PushStyleColor(ctx,ImGui.Col_FrameBg,0x2C323DFF);ImGui.PushStyleColor(ctx,ImGui.Col_FrameBgHovered,0x38404FFF)
        ImGui.PushStyleColor(ctx,ImGui.Col_FrameBgActive,0x444D60FF);ImGui.PushStyleColor(ctx,ImGui.Col_CheckMark,0xF29A5AFF)
        ImGui.PushStyleColor(ctx,ImGui.Col_Header,0x3A4254FF);ImGui.PushStyleColor(ctx,ImGui.Col_HeaderHovered,0x434C60FF)
        ImGui.SetCursorScreenPos(ctx,L1+PADX,T+PADY)
        ImGui.BeginGroup(ctx);Pitch2.ghost_rows(ImGui,ctx,app,open_dropdown);ImGui.EndGroup(ctx)
        ImGui.PopStyleColor(ctx,6);ImGui.PopStyleVar(ctx,4);ImGui.PopFont(ctx)
      end
    end})
end

-- кастомный топбар: слева пустая зона, справа скруглённые кнопки (report, settings, закрыть)
local function titlebar()
  local dl=ImGui.GetWindowDrawList(ctx)
  local wx,wy=ImGui.GetWindowPos(ctx)
  local ww=ImGui.GetWindowSize(ctx)
  ImGui.DrawList_AddRectFilled(dl,wx,wy,wx+ww,wy+TBH,TB_BG,WRND,ImGui.DrawFlags_RoundCornersTop)
  -- Редактор Pitch: плитки навигации скрыты, вся панель инструментов едет в глобальный топбар (без BYPASS ALL, fps и Report)
  local editor=app.tab=='pitch' and pitch_page=='tools' and HOST~=nil -- кнопки навигации и BYPASS ALL/fps/Report уходят сразу
  -- BYPASS слева: включённый bypass выключает ВСЁ, что скрипт внёс в проект (Cleanup, DeClick, Pitch, Align),
  -- чтобы сравнить с оригиналом; повторный клик возвращает. Подробности — ui2/master.lua.
  if not editor then
    ImGui.PushFont(ctx,R.F_TIPB)
    local tw=ImGui.CalcTextSize(ctx,'BYPASS ALL')
    ImGui.PopFont(ctx)
    local mw,mx,my=31+tw+12,wx+7,wy+(TBH-PH)/2
    ImGui.SetCursorScreenPos(ctx,mx,my)
    ImGui.InvisibleButton(ctx,'##tb_master',mw,PH)
    -- Рисуется по выделенным айтемам: есть изменения скрипта — кнопка активна, включённый bypass — оранжевая,
    -- иначе (нет выделения или в айтеме нет изменений скрипта) кнопка приглушена и не нажимается
    local engaged,available=Master.is_off(),Master.available()
    local live=available or engaged
    local mhov=ImGui.IsItemHovered(ctx) and live
    phv.master=ap(phv.master,mhov and 1 or 0,0.25)
    if mhov then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_Hand) end
    if live and ImGui.IsItemClicked(ctx,0) then Master.toggle(app) end
    local h=phv.master
    ImGui.DrawList_AddRectFilled(dl,mx,my,mx+mw,my+PH,lc(live and PILL or 0x1E1E1EFF,0x363636FF,h),8)
    if engaged then ImGui.DrawList_AddRect(dl,mx,my,mx+mw,my+PH,fa(BYPASS_COL,0.6),8,0,1) end
    local col=engaged and lc(BYPASS_COL,0xFFFFFFFF,0.25*h) or (live and lc(0x8A8A96FF,0xFFFFFFFF,0.7*h) or 0x484852FF)
    local gx,gy,q=mx+17,my+PH/2,-math.pi/2
    ImGui.DrawList_PathArcTo(dl,gx,gy,5.4,q+0.65,q+2*math.pi-0.65)
    ImGui.DrawList_PathStroke(dl,col,0,1.7)
    ImGui.DrawList_PathLineTo(dl,gx,gy-6.6);ImGui.DrawList_PathLineTo(dl,gx,gy-1.4)
    ImGui.DrawList_PathStroke(dl,col,0,1.7)
    ImGui.PushFont(ctx,R.F_TIPB)
    ImGui.DrawList_AddText(dl,mx+31,math.floor(my+(PH-ImGui.GetTextLineHeight(ctx))/2-1.5),col,'BYPASS ALL') -- по центру кнопки, текст приподнят на пару пикселей
    ImGui.PopFont(ctx)
    -- счётчик кадров правее BYPASS: частота кадров главного цикла, сглаженная
    local now=app.r.time_precise()
    if fps_last then local dt=now-fps_last;if dt>0 and dt<1 then fps_dt=fps_dt and fps_dt+(dt-fps_dt)*0.05 or dt end end
    fps_last=now
    local label=fps_dt and string.format('%d fps',math.floor(1/fps_dt+0.5)) or '– fps'
    ImGui.PushFont(ctx,R.F_TIPB)
    local fw=ImGui.CalcTextSize(ctx,'000 fps')+8
    local fx=mx+mw+6
    ImGui.DrawList_AddRectFilled(dl,fx,my,fx+fw,my+PH,PILL,8)
    local lw=ImGui.CalcTextSize(ctx,label)
    ImGui.DrawList_AddText(dl,math.floor(fx+(fw-lw)/2),math.floor(my+(PH-ImGui.GetTextLineHeight(ctx))/2-1.5),0x8A8A96FF,label)
    ImGui.PopFont(ctx)
  end
  -- в редакторе Pitch кнопки справа той же высоты и ширины, что виджеты панели (одинаковая высота во всём баре)
  local ph_=editor and math.min(TBH-8,ImGui.GetFrameHeight(ctx)+2) or PH
  local pw_=editor and ph_ or PW
  local cx=wx+ww-7-pw_ -- края 7 px, зазоры между кнопками 6 px, высота у всех ph_
  local btns={ -- key, ячейка спрайта, x, заголовок тултипа
    {'close',2,cx},
    {'menu',1,cx-6-pw_,'Settings'},
  }
  if not editor then btns[#btns+1]={'report',3,cx-2*(6+pw_),'Report'}
  else btns[#btns+1]={'pmenu',false,cx-2*(6+pw_),'Menu'} end -- меню редактора слева от Settings
  if editor and tb_in>0.02 then
    -- панель Pitch появляется мягко: небольшой сдвиг сверху и проявление поверх фона топбара
    local avail=ww-(3*pw_+2*6+7+10)
    ImGui.DrawList_PushClipRect(dl,wx,wy,wx+avail,wy+TBH,true)
    Pitch2.toolbar(HOST,ImGui,ctx,app,wx,wy-(1-tb_in)*6,avail,TBH)
    ImGui.DrawList_PopClipRect(dl)
    if tb_in<0.99 then ImGui.DrawList_AddRectFilled(dl,wx,wy,wx+avail,wy+TBH,fa(TB_BG,1-tb_in),0) end
  end
  local rbx,rby
  for _,b in ipairs(btns) do
    local key,ico,bx=b[1],b[2],b[3]
    local by=wy+(TBH-ph_)/2
    ImGui.SetCursorScreenPos(ctx,bx,by)
    ImGui.InvisibleButton(ctx,'##tb_'..key,pw_,ph_)
    local hov=ImGui.IsItemHovered(ctx)
    phv[key]=ap(phv[key] or 0,hov and 1 or 0,0.25)
    if hov then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_Hand) end
    if ImGui.IsItemClicked(ctx,0) then
      if key=='close' then quit=true
      elseif key=='pmenu' then HOST.dropdown('menu',bx+pw_/2,by+ph_,Pitch2.menu_items(ImGui,ctx,app))
      elseif key=='menu' then
        if not pop.open then pop.from=TIP.menu and TIP.menu.t or 0 end -- облачко-модалка вырастает из тултипа
        pop.open=not pop.open
      else ImGui.OpenPopup(ctx,'Vocaligner report') end
    end
    if key=='menu' then pop.ax,pop.ay=bx+pw_/2,by+ph_ end
    if key=='report' then rbx,rby=bx,by+ph_ end
    local h=phv[key]
    local base=key=='close' and lc(PILL,0x6A2A30FF,h) or lc(PILL,0x363636FF,h)
    ImGui.DrawList_AddRectFilled(dl,bx,by,bx+pw_,by+ph_,base,8)
    if ico then uisprite(dl,ico,bx+pw_/2,by+ph_/2,25+2*h,lc(0xA8A8B6FF,0xFFFFFFFF,h)) -- глиф при наведении чуть крупнее
    else
      local gc=lc(0xA8A8B6FF,0xFFFFFFFF,h);local mcx,mcy,k=bx+pw_/2,by+ph_/2,1+0.12*h
      for dy=-1,1 do ImGui.DrawList_AddLine(dl,mcx-5.5*k,mcy+dy*4.5*k,mcx+5.5*k,mcy+dy*4.5*k,gc,1.7) end
    end
    if b[4] then tooltip(key,hov and not pop.open and not ImGui.IsPopupOpen(ctx,'Vocaligner report'),bx+pw_/2,by+ph_,b[4],'',wx,ww,0.08,0.4) end
  end
  -- меню Report: то же содержимое, что в оригинальном окне
  if rbx then ImGui.SetNextWindowPos(ctx,rbx,rby+4,ImGui.Cond_Appearing) end -- в редакторе Pitch кнопки Report нет
  if rbx and ImGui.BeginPopup(ctx,'Vocaligner report') then
    if ImGui.Selectable(ctx,'Copy report') then
      local report=app:diagnostics();ImGui.SetClipboardText(ctx,report);app.r.ShowConsoleMsg(report..'\n')
    end
    if app.tab=='pitch' then
      ImGui.BeginDisabled(ctx,app.pitch:busy() or not app.pitch.data or app.pitch.no_selection==true)
      if ImGui.Selectable(ctx,'Export case') then app.pitch:export_case() end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx,'Exports the time selection inside this item, or the whole item if there is no time selection. CSV times stay relative to the item start.') end
      ImGui.EndDisabled(ctx)
    end
    if app.tab=='align' then
      ImGui.BeginDisabled(ctx,app.job~=nil or not app.ref or #app.dubs==0)
      if ImGui.Selectable(ctx,'Export Align case') then app:export_align_case() end
      ImGui.EndDisabled(ctx)
    end
    ImGui.EndPopup(ctx)
  end
  ImGui.SetCursorScreenPos(ctx,wx+8,wy+TBH+((app.tab=='pitch' and pitch_page=='tools') and 0 or 4)) -- в редакторе Pitch зазор = полю виджета в топбаре
end

-- тело вкладки: Breath — новая страница, остальные — оригинальные тела
local function body(bx,by,bw,bh,flat)
  ImGui.SetCursorScreenPos(ctx,bx,by)
  if flat then ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,0);ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,0,0) end
  -- WindowFlags_NoMove: тянуть окно за фон этой области нельзя — иначе слайдеры, кнобы и волна «спорят» с перемещением окна
  if ImGui.BeginChild(ctx,'##tool_body',bw,bh,0,ImGui.WindowFlags_NoMove) then
    local wave=function(a,b,c,d,e,f,g,h,i,j,k,l,m) Wave.draw(a,b,c,d,e,f,g,h,i,j,k,l,m,app.legacy_wave) end
    if app.tab=='declick' then Declick.draw(ImGui,ctx,app,color)
    elseif Settings.is_tool(app.tab) then
      app.cleaner:set_mode(app.tab);apply_pending()
      if app.tab=='breath' then Breath.draw(ImGui,ctx,app,color,wave)
      else Dynamics.draw(ImGui,ctx,app,color,wave) end -- De-ess / Compressor / Gate
    elseif app.tab=='pitch' then Pitch2.body(HOST,ImGui,ctx,app)
    else AlignUI.draw(ImGui,ctx,app,color,wave) end
    if app.tab~='pitch' and ImGui.BeginPopupContextWindow(ctx,'##wave_style',ImGui.PopupFlags_MouseButtonRight|ImGui.PopupFlags_NoOpenOverItems) then
      if ImGui.Selectable(ctx,'Waveform: Outline',not app.legacy_wave) then app.legacy_wave=false end
      if ImGui.Selectable(ctx,'Waveform: Legacy',app.legacy_wave==true) then app.legacy_wave=true end
      ImGui.EndPopup(ctx)
    end
    ImGui.EndChild(ctx)
  end
  if flat then ImGui.PopStyleVar(ctx);ImGui.PopStyleColor(ctx) end
  if ImGui.IsWindowFocused(ctx,ImGui.FocusedFlags_RootAndChildWindows) then
    if ImGui.IsKeyPressed(ctx,ImGui.Key_Space,false) and not ImGui.IsAnyItemActive(ctx) then app.r.Main_OnCommandEx(40044,0,app.r.EnumProjects(-1)) end
    if ImGui.IsKeyPressed(ctx,ImGui.Key_Escape,false) and not pop.open then
      if app.tab=='pitch' then if app.pitch:busy() or app.pitch.gesture then app.pitch:cancel() end elseif app.tab=='declick' then Declick.clear_range(app) else app.cleaner:clear_range() end
    end
  end
end

-- ряд плиток, подконтейнеры групп и панель под ним
local function bar()
  local dl=ImGui.GetWindowDrawList(ctx)
  local x0,y0=ImGui.GetCursorScreenPos(ctx)
  local aw,ah=ImGui.GetContentRegionAvail(ctx)
  local bhf=SZ+LBL+PAD*2 -- полная высота бара с плитками
  local want=(app.tab=='pitch' and pitch_page=='tools') and 1 or 0
  pbar=ap(pbar,want,0.2);if math.abs(pbar-want)<0.01 then pbar=want end
  local bh=ap(bhf,0,ease(pbar)) -- в редакторе Pitch бар сворачивается в ноль (инструменты переехали в топбар)
  local show_tiles=not (app.tab=='pitch' and pitch_page=='tools') -- плитки исчезают сразу, без анимации; сворачивается только фон
  local barclip={x0,y0,x0+aw,y0+bh}
  if bh>0.5 then ImGui.DrawList_AddRectFilled(dl,x0,y0,x0+aw,y0+bh,BG,10) end
  if drag and not ImGui.IsMouseDown(ctx,0) then commit_order(drag.grp,drag.start,KIDS[drag.grp]);drag=nil end
  if not drag then KIDS.dynamics=dyn_order() end -- порядок Dynamics всегда из конфига, пока не тащим
  dimv=ap(dimv,drag and 1 or 0,0.2)
  locked=Master.is_off();lockv=ap(lockv,locked and 1 or 0,0.2)
  for i=#late,1,-1 do late[i]=nil end

  local tw_=-GAP -- ширина ряда плиток: считаем заранее, чтобы выровнять по центру
  for _,id in ipairs(TOP) do
    local ks,ee=KIDS[id],0
    if ks then
      local tgt=open[id] and 1 or 0
      ex[id]=math.abs(ex[id]-tgt)<0.003 and tgt or ap(ex[id],tgt,0.16)
      ee=ease(ex[id])
      tw_=tw_+(10+GP*2+#ks*CSZ+(#ks-1)*CGAP)*ee
    end
    tw_=tw_+SZ-(SZ-PSZ)*ee+GAP
  end
  local x,y=x0+math.max(PAD,(aw-tw_)/2),y0+PAD
  for _,id in ipairs(show_tiles and TOP or {}) do
    local ks=KIDS[id]
    local e,ee=0,0
    if ks then e=ex[id];ee=ease(e) end
    -- родитель ужимается и встаёт по центру бара, подпись гаснет; «{» смотрит ему в центр
    local psz=SZ-(SZ-PSZ)*ee
    local py_=ap(y,y0+bhf/2-psz/2,ee)
    if tile(id,x,py_,1,psz,barclip,nil,1-ee) then
      if N[id].kids then
        open[id]=not open[id]
        if open[id] then go(last[id] or ks[1]) end
      else go(id) end
    end
    local px=x
    x=x+psz+GAP
    if ks and e>0 then -- подконтейнер растёт вправо от родителя, дети «вылетают» из него
      local bx=px+psz+10*ee
      local full=GP*2+#ks*CSZ+(#ks-1)*CGAP
      local T,B=y0+5,y0+bhf-5
      local cy=T+(B-T-CSZ-LBL)/2+1 -- плитки по центру контейнера
      local cclip={bx-10,T,bx+full*ee,B}
      ImGui.DrawList_AddRectFilled(dl,bx,T,bx+full*ee,B,fa(0x202020FF,e),12)
      brace(dl,bx,T,bx+full*ee,B,fa(lc(LINE,ACC_P,0.2),e))
      local dr=drag and drag.grp==id and drag.id
      local mx,my=ImGui.GetMousePos(ctx)
      for i,cid in ipairs(ks) do
        local tr=GP+(i-1)*(CSZ+CGAP)
        rel[cid],ry[cid]=rel[cid] or tr,ry[cid] or 0
        if cid==dr then -- тянется за курсором с лёгким запаздыванием
          rel[cid],ry[cid]=ap(rel[cid],mx-drag.gx-bx,0.4),ap(ry[cid],my-drag.gy-cy,0.4)
          local gx,rr=bx+tr,CSZ*RND -- призрак: куда встанет плитка
          ImGui.DrawList_AddRectFilled(dl,gx,cy,gx+CSZ,cy+CSZ,fa(ACC_C,0.10),rr)
          sprite(dl,N[cid].icon,gx,cy,gx+CSZ,cy+CSZ,0x48484848,rr)
          ImGui.DrawList_AddRect(dl,gx,cy,gx+CSZ,cy+CSZ,fa(ACC_C,0.55),rr,0,1)
        else rel[cid],ry[cid]=ap(rel[cid],tr,0.3),ap(ry[cid],0,0.3) end
        local dx=ap(px,bx+rel[cid],ee)
        if tile(cid,dx,cy+ry[cid],e,CSZ,cid==dr and barclip or cclip,DRAG[id] and id) then go(cid) end
      end
      if dr then -- меняем с соседом, когда плитка перекрыла его слот на SWAP (80%)
        local k
        for i,c in ipairs(ks) do if c==dr then k=i end end
        local dl_,pitch,ov=bx+rel[dr],CSZ+CGAP,(1-SWAP)*CSZ
        local function sl_(i) return bx+GP+(i-1)*pitch end -- левый край слота
        if k>1 and dl_<=sl_(k-1)+ov then ks[k],ks[k-1]=ks[k-1],ks[k]
        elseif k<#ks and dl_>=sl_(k+1)-ov then ks[k],ks[k+1]=ks[k+1],ks[k] end
      end
      x=bx+full*ee+GAP
    end
  end
  for _,t in ipairs(late) do paint(table.unpack(t)) end -- перетаскиваемая плитка поверх всех

  if app.tab=='pitch' and HOST then
    if pitch_page=='menu' and pbar==0 then -- «Вперёд»: вернуться к инструментам Pitch, справа по центру
      local bs=28;local fx,fy=x0+aw-PAD-bs,y0+bhf/2-bs/2
      ImGui.SetCursorScreenPos(ctx,fx,fy);ImGui.InvisibleButton(ctx,'##pitch_forward',bs,bs)
      local fh=ImGui.IsItemHovered(ctx)
      if fh then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_Hand) end
      if ImGui.IsItemClicked(ctx,0) then pitch_page='tools' end
      ImGui.DrawList_AddRectFilled(dl,fx,fy,fx+bs,fy+bs,fh and 0x363636FF or PILL,8)
      local col=fh and 0xFFFFFFFF or 0xA8A8B6FF
      ImGui.DrawList_AddLine(dl,fx+bs/2-3,fy+bs/2-6,fx+bs/2+3,fy+bs/2,col,2);ImGui.DrawList_AddLine(dl,fx+bs/2+3,fy+bs/2,fx+bs/2-3,fy+bs/2+6,col,2)
    end
  end

  local py=y0+bh+(pbar>=1 and 0 or 8) -- панель контента (в редакторе Pitch бара нет — холст сразу под топбаром)
  if app.tab=='pitch' then
    body(x0,py,aw,ah-(py-y0)-8,true) -- редактор Pitch: без подложки; поля со всех сторон по 8 px, как зазор виджетов в топбаре
  else
    ImGui.DrawList_AddRectFilled(dl,x0,py,x0+aw,y0+ah-1,PANEL,10)
    body(x0+8,py+8,aw-16,ah-(py-y0)-17)
  end
end


-- ===== окно «Hotkeys»: отдельное ImGui-окно в стиле основного (открывается из Settings) =====
local HOTKEYS={
  {'Tools',{{'1 … 6','Edit, Transition, Modulation, Curve, Split, Draw'},{'C','Toggle Edit / Curve'},{'S','Split the note at the cursor'},{'J','Join the note with the next one'}}},
  {'View',{{'F','Focus: note centered, cursor at the autoscroll position; press again: fit everything'},
    {'W','Edit cursor to the start of the time selection (or of the active take)'},{'Esc','Clear time selection, then note selection'},
    {'Wheel','Zoom in / out around the cursor'},{'Shift / Alt + wheel','Scroll horizontally'},{'Ctrl + wheel','Vertical zoom'},
    {'Middle drag','Pan'},{'Double click on ruler','Clear time selection'}}},
  {'Edit',{{'Ctrl + A','Select all notes'},{'Ctrl + Z','Undo (with Shift: redo)'},{'Delete','Reset selected notes'},
    {'↑ / ↓','Nudge selected notes (Alt: fine)'},{'Ctrl + C / Ctrl + V','Copy / paste the curve shape (Alt: relative)'},
    {'Alt + drag','Bypass snap while dragging'},{'Shift + drag','Fine adjustment'},{'Right drag','Rectangle selection'}}},
  {'Global',{{'Space','Play / stop'}}},
}
local function hotkeys_window()
  if not S.hotkeys_open then return end
  ImGui.SetNextWindowSize(ctx,470,540,ImGui.Cond_FirstUseEver)
  ImGui.SetNextWindowSizeConstraints(ctx,360,260,900,1000)
  ImGui.PushStyleColor(ctx,ImGui.Col_WindowBg,TB_BG)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowRounding,WRND)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowBorderSize,0)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,0,0)
  local visible,open_=ImGui.Begin(ctx,'Vocaligner · Hotkeys',true,ImGui.WindowFlags_NoScrollbar|ImGui.WindowFlags_NoScrollWithMouse|ImGui.WindowFlags_NoTitleBar)
  if visible then
    ImGui.PushFont(ctx,R.F_LBL)
    local dl=ImGui.GetWindowDrawList(ctx);local wx,wy=ImGui.GetWindowPos(ctx);local ww,wh=ImGui.GetWindowSize(ctx)
    ImGui.DrawList_AddRectFilled(dl,wx,wy,wx+ww,wy+TBH,TB_BG,WRND,ImGui.DrawFlags_RoundCornersTop)
    ImGui.PushFont(ctx,R.F_TIPB)
    ImGui.DrawList_AddText(dl,wx+14,wy+(TBH-ImGui.GetTextLineHeight(ctx))/2,0xFFFFFFFF,'Hotkeys')
    ImGui.PopFont(ctx)
    -- закрыть: та же плашка, что в основном топбаре
    local bx,by=wx+ww-7-PW,wy+(TBH-PH)/2
    ImGui.SetCursorScreenPos(ctx,bx,by);ImGui.InvisibleButton(ctx,'##hk_close',PW,PH)
    local hov=ImGui.IsItemHovered(ctx)
    if hov then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_Hand) end
    if ImGui.IsItemClicked(ctx,0) then S.hotkeys_open=false end
    ImGui.DrawList_AddRectFilled(dl,bx,by,bx+PW,by+PH,hov and 0x6A2A30FF or PILL,8)
    uisprite(dl,2,bx+PW/2,by+PH/2,25,hov and 0xFFFFFFFF or 0xA8A8B6FF)
    ImGui.DrawList_AddRectFilled(dl,wx+8,wy+TBH,wx+ww-8,wy+wh-8,PANEL,10)
    ImGui.SetCursorScreenPos(ctx,wx+8,wy+TBH+8)
    ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,0);ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,12,6)
    if ImGui.BeginChild(ctx,'##hk_body',ww-16,wh-TBH-16,0,ImGui.WindowFlags_NoMove) then
      for gi,group in ipairs(HOTKEYS) do
        if gi>1 then ImGui.Dummy(ctx,1,6) end
        ImGui.TextDisabled(ctx,group[1])
        for _,row in ipairs(group[2]) do
          local x,y=ImGui.GetCursorScreenPos(ctx)
          local kw=ImGui.CalcTextSize(ctx,row[1])+16;local rh=ImGui.GetTextLineHeight(ctx)+8
          ImGui.DrawList_AddRectFilled(dl,x,y,x+kw,y+rh,PILL,7)
          ImGui.DrawList_AddText(dl,x+8,y+4,0xE6E6F0FF,row[1])
          ImGui.SetCursorScreenPos(ctx,x+150,y+4)
          ImGui.PushTextWrapPos(ctx,ImGui.GetCursorPosX(ctx)+ (ww-16-12-150-12))
          ImGui.TextColored(ctx,0xB8B8C4FF,row[2])
          ImGui.PopTextWrapPos(ctx)
          local _,ey=ImGui.GetCursorScreenPos(ctx)
          ImGui.SetCursorScreenPos(ctx,x,math.max(y+rh+4,ey+4))
        end
      end
      ImGui.EndChild(ctx)
    end
    ImGui.PopStyleVar(ctx);ImGui.PopStyleColor(ctx)
    ImGui.DrawList_AddRect(ImGui.GetForegroundDrawList(ctx),wx+.5,wy+.5,wx+ww-.5,wy+wh-.5,0x4A4A4AFF,WRND,0,1)
    ImGui.PopFont(ctx)
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx,3);ImGui.PopStyleColor(ctx)
  if not open_ then S.hotkeys_open=false end
end

function M.draw(im,c,a)
  ImGui,ctx,app=im,c,a
  Sampler.tick()
  init()
  Master.install() -- запоминаем оригинал айтемов перед первой записью скрипта
  app.gesture=false;app.cleaner.gesture=false
  Declick.tick()
  sync()
  if not window_sized then window_sized=true;ImGui.SetNextWindowSize(ctx,860,680,ImGui.Cond_FirstUseEver) end -- размер по умолчанию достаточно задать один раз
  ImGui.SetNextWindowSizeConstraints(ctx,app.tab=='pitch' and 880 or 520,400,2400,2400)
  for _,entry in ipairs(theme) do ImGui.PushStyleColor(ctx,ImGui[entry[1]],entry[2]) end
  ImGui.PushStyleColor(ctx,ImGui.Col_WindowBg,TB_BG)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FrameRounding,5)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_GrabRounding,4)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,8,4)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,8,6)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowRounding,WRND)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowBorderSize,0) -- штатную обводку убираем: рисуем свою лёгкую серую ниже
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ChildBorderSize,0)
  local flags=ImGui.WindowFlags_NoScrollbar|ImGui.WindowFlags_NoScrollWithMouse|ImGui.WindowFlags_NoTitleBar -- перемещение штатное
  local visible,open_=ImGui.Begin(ctx,'Vocaligner · Lua',true,flags)
  if visible then
    ImGui.PushFont(ctx,R.F_LBL)
    do local wx0=ImGui.GetWindowPos(ctx);local ww0=ImGui.GetWindowSize(ctx)
      HOST=HOST or {dropdown=open_dropdown,icon=pitch_icon,settings=S,tooltip=tooltip,window={0,0},back=function() pitch_page='menu' end,pill=PILL,pill_hover=0x363636FF,accent_fill=fa(ACC_P,0.35)}
      HOST.window[1],HOST.window[2]=wx0,ww0 end
    local blocked=pop.t>0.01 -- пока открыто модальное облачко, остальное неинтерактивно
    if blocked then ImGui.BeginDisabled(ctx,true) end
    local editor_want=app.tab=='pitch' and pitch_page=='tools'
    local tbh_t=editor_want and 44 or 33 -- в редакторе Pitch топбар выше: панель инструментов с отступами; высота меняется плавно
    TBH=ap(TBH,tbh_t,0.3);if math.abs(TBH-tbh_t)<0.5 then TBH=tbh_t end
    tb_in=ap(tb_in,(editor_want and pbar>=0.8) and 1 or 0,0.2);if tb_in<0.01 then tb_in=0 elseif tb_in>0.99 then tb_in=1 end
    titlebar()
    bar()
    if blocked then ImGui.EndDisabled(ctx) end
    settings_modal()
    if app.tab=='pitch' then ghost_modal();dropdown_modal() else ghost.open=false;ghost.t=0;dd.open=false;dd.t=0 end
    do -- общая обводка окна: тонкая светло-серая, поверх содержимого (редактор Pitch идёт вплотную к краям)
      local wx1,wy1=ImGui.GetWindowPos(ctx);local ww1,wh1=ImGui.GetWindowSize(ctx)
      ImGui.DrawList_AddRect(ImGui.GetForegroundDrawList(ctx),wx1+0.5,wy1+0.5,wx1+ww1-0.5,wy1+wh1-0.5,0x4A4A4AFF,WRND,0,1)
    end
    draw_tips()
    ImGui.PopFont(ctx)
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx,7);ImGui.PopStyleColor(ctx,#theme+1)
  hotkeys_window()
  return open_ and not quit
end
return M
