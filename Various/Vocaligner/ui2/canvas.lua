-- @noindex
-- Волна и обзорная полоса нового интерфейса. Логика 1 в 1 из cleaner_ui.lua / navigator.lua (оригиналы не тронуты);
-- отличия только визуальные: скругление только сверху у волны и только снизу у обзорной полосы,
-- подписи секунд по центру своих линий, линии идут под волной и не доходят до низа.
local import=...;local DSP=import('dsp');local Regions=import('cleanup_ui');local Transport=import('transport')
local Cleanup=import('cleanup');local Audio=import('audio');local M={}
local ROUND=8
-- opts (необязательно): min_span — минимальный видимый интервал, с; paint(draw,x,top,w,height,v,events) —
-- своя отрисовка волны вместо двух вызовов wave; status(d) — своя подпись состояния справа сверху (или nil).
-- Детализация при зуме: если базовые пики грубее пикселя, берём пики видимого окна у REAPER (кэш с запасом по краям).
-- Волна и после обработки остаётся односторонней: редукция применяется поверх детальных пиков в waveform.lua.
local function detail(c,d,data,v,w)
  local s=d.snapshot
  if not s or s.composite or not data.peaks or not data.peaks[1] then data.detail=nil;return end
  local need=v.span/w;local base=data.peaks[1].hop -- levels[1] — самый мелкий уровень базовых пиков
  if base<=need*1.15 then return end
  local det=data.detail;local rel0,rel1=v.start-data.pos,v.start+v.span-data.pos
  if det and det.t0<=rel0+1e-9 and det.t1>=rel1-1e-9 and det.hop<=need*1.3 and det.hop>=need/3 then return end
  local now=c.r.time_precise()
  if det and now<(det.at or 0)+0.05 then return end
  local pad=v.span*.5;local t0,t1=math.max(0,rel0-pad),math.min(data.len,rel1+pad)
  if t1<=t0 then return end
  local built=Audio.window_peaks(c.r,s,t0,t1,(t1-t0)/(need*.8))
  if built then built.at=now;data.detail=built elseif det then det.at=now end
end

M.detail=detail
function M.draw(im,ctx,c,w,h,color,wave,opts)
  local d=c:current();local x,y=im.GetCursorScreenPos(ctx);local draw=im.GetWindowDrawList(ctx)
  local font=im.GetFontSize(ctx)
  im.InvisibleButton(ctx,'##cleanup_wave',w,h,im.ButtonFlags_MouseButtonLeft|im.ButtonFlags_MouseButtonRight|im.ButtonFlags_MouseButtonMiddle)
  local hovered=im.IsItemHovered(ctx)
  im.DrawList_AddRectFilled(draw,x,y,x+w,y+h,color.bg,ROUND,im.DrawFlags_RoundCornersTop)
  if not d then return end
  local data=d.audio or d.quick
  if not data then im.DrawList_AddText(draw,x+10,y+8,color.muted,'Unprocessed');return end
  d.view=d.view or {start=data.pos,span=data.len}
  -- Несколько выбранных item на одном треке рисуются в одном виде (в разумных пределах: до 8 item и 15 минут).
  local lo,hi=data.pos,data.pos+data.len;local group={}
  if c.targets and #c.targets>1 and d.snapshot and c.r.GetMediaItemTrack then
    local trk=c.r.GetMediaItemTrack(d.snapshot.item)
    for _,t in ipairs(c.targets) do
      local td=t~=d and t.snapshot and not t.stale and (t.audio or t.quick)
      if td and #group<7 and c.r.ValidatePtr2(c.project,t.snapshot.item,'MediaItem*') and c.r.GetMediaItemTrack(t.snapshot.item)==trk
        and math.max(hi,td.pos+td.len)-math.min(lo,td.pos)<=900 then
        group[#group+1]=t;lo=math.min(lo,td.pos);hi=math.max(hi,td.pos+td.len)
      end
    end
  end
  d.bounds={lo,hi-lo};d.group=group
  local v=d.view;local mx,my=im.GetMousePos(ctx);local top=y+font*1.8
  local function time(px) return DSP.clamp(v.start+v.span*(px-x)/w-data.pos,0,data.len) end
  if hovered then
    local wheel=im.GetMouseWheel(ctx)
    if wheel~=0 then
      local f=DSP.clamp((mx-x)/w,0,1);local span=DSP.clamp(v.span*1.2^(-wheel),math.min(opts and opts.min_span or .15,hi-lo),hi-lo)
      v.start=v.start+f*(v.span-span);v.span=span
    end
    if im.IsMouseClicked(ctx,0) then
      d.drag_start=time(mx);d.drag_ruler=my<top;d.drag_moved=false;d.click_seek=im.GetKeyMods(ctx)&im.Mod_Shift==0
    end
    if im.IsMouseDoubleClicked(ctx,0) then v.start=lo;v.span=hi-lo;d.click_seek=false end
  end
  if im.IsItemActive(ctx) then
    c.gesture=true
    if im.IsMouseDragging(ctx,2,2) or (im.GetKeyMods(ctx)&im.Mod_Shift~=0 and im.IsMouseDragging(ctx,0,2)) then
      local dx=im.GetMouseDelta(ctx);v.start=v.start-dx*v.span/w;d.drag_start=nil;d.click_seek=false
    elseif d.drag_start and im.IsMouseDragging(ctx,0,3) then
      d.drag_moved=true
      if d.drag_ruler then c:set_range(d.drag_start,time(mx),true)
      else local dx=im.GetMouseDelta(ctx);v.start=v.start-dx*v.span/w;d.click_seek=false end
    end
  end
  v.start=DSP.clamp(v.start,lo,hi-v.span)
  if not (opts and opts.paint) then detail(c,d,data,v,w) end
  if im.IsMouseReleased(ctx,0) and d.drag_start then
    if d.drag_moved and d.drag_ruler then c:control_released()
    elseif hovered and d.click_seek then c:seek(time(mx)) end
  end
  if not im.IsMouseDown(ctx,0) then d.drag_start=nil;d.click_seek=nil end
  local transport=Transport.read(c.r,c.project)
  Transport.follow(d,c.r,transport,v,0,lo,hi,im.IsItemActive(ctx) or d.overview_grab~=nil or hovered and im.GetMouseWheel(ctx)~=0)
  local function xpos(t) return x+(data.pos+t-v.start)/v.span*w end
  im.DrawList_PushClipRect(draw,x,y,x+w,y+h,true)
  local height=h-font*2.2
  local step=10^math.floor(math.log(v.span/7,10))
  if v.span/step>14 then step=step*5 elseif v.span/step>8 then step=step*2 end
  -- Вертикальные линии рисуются первыми (под волной) и заканчиваются с запасом над нижним краем;
  -- подпись секунд центрирована на своей линии и не вылезает за края холста.
  for t=math.ceil(v.start/step)*step,v.start+v.span,step do
    local xx=x+(t-v.start)/v.span*w
    local label=string.format(step<1 and '%.2fs' or '%.1fs',t)
    local tw=im.CalcTextSize(ctx,label)
    im.DrawList_AddLine(draw,xx,y+22,xx,y+h-12,0xFFFFFF0B)
    im.DrawList_AddText(draw,math.max(x+2,math.min(x+w-tw-2,xx-tw/2)),y+4,color.muted,label)
  end
  local events=d.detected and (c.mode=='breath' and d.detected.breaths or d.detected.sibilants or {}) or {}
  local bypassed=c:bypassed(d)
  local status,status_col
  if opts and opts.paint then
    opts.paint(draw,x,top,w,height,v,events)
    if opts.status then status,status_col=opts.status(d) end
  else
    -- One-sided waveform: amplitude rises from the bottom edge, not mirrored.
    -- Общий peak: у нескольких item одинаковый масштаб по высоте.
    local gp=data.peak
    for _,g in ipairs(group) do gp=math.max(gp,(g.audio or g.quick).peak or 0) end
    for _,g in ipairs(group) do
      local gd=g.audio or g.quick
      wave(im,ctx,draw,gd,nil,x,top,w,height,v,0xA0AABA30,nil,{half=true,peak=gp})
      wave(im,ctx,draw,gd,nil,x,top,w,height,v,0xA3AFBFD0,g.preview or g.applied_cleanup,{tint=0xEBC080FF,half=true,peak=gp})
    end
    wave(im,ctx,draw,data,nil,x,top,w,height,v,0xA0AABA30,nil,{half=true,peak=gp})
    -- до первого пересчёта (например, после перезапуска скрипта) рисуем уже применённое снижение, без «прыжка» потом
    wave(im,ctx,draw,data,nil,x,top,w,height,v,0xA3AFBFD0,d.preview or d.applied_cleanup,{events=events,tint=0xEBC080FF,half=true,peak=gp})
    -- границы item: тонкие линии по началу и концу каждого
    for _,it in ipairs({d,table.unpack(group)}) do
      local idata=it.audio or it.quick
      for _,t in ipairs({idata.pos,idata.pos+idata.len}) do
        local xx=x+(t-v.start)/v.span*w
        if #group>0 and xx>x and xx<x+w then im.DrawList_AddLine(draw,xx,top,xx,top+height,0xFFFFFF22) end
      end
    end
    status=bypassed and 'Bypassed' or not (d.processed_modes and d.processed_modes[c.mode]) and not (d.layers and d.layers[c.mode]) and 'Unprocessed'
  end
  if status then
    local tw=im.CalcTextSize(ctx,status)
    im.DrawList_AddText(draw,x+w-tw-8,y+26,status_col or (bypassed and color.warn or color.muted),status)
  end
  local count=c.targets and #c.targets or 0
  im.DrawList_AddText(draw,x+8,y+26,color.muted,(count>1 and count..' items · ' or '')..d.snapshot.name)
  Regions.draw(im,ctx,draw,c,d,x,top,w,height)
  if d.selected then
    local a,b=xpos(d.range[1]),xpos(d.range[2])
    if a>x then im.DrawList_AddRectFilled(draw,x,y+25,math.min(x+w,a),y+h,0x171A2090) end
    if b<x+w then im.DrawList_AddRectFilled(draw,math.max(x,b),y+25,x+w,y+h,0x171A2090) end
    -- Only real scope edges; a selection clamped to the item start/end draws no line.
    if d.range[1]>1e-9 then im.DrawList_AddLine(draw,a,y+25,a,y+h,color.after,1) end
    if d.range[2]<data.len-1e-9 then im.DrawList_AddLine(draw,b,y+25,b,y+h,color.after,1) end
  end
  Transport.draw(im,draw,transport,function(t)return x+(t-v.start)/v.span*w end,x,x+w,y+24,y+h)
  im.DrawList_PopClipRect(draw)
end

-- Overview coordinates always cover the whole item, independently of main zoom.
-- Скруглены только нижние углы: полоса стоит вплотную под волной.
function M.navigator(im,ctx,d,w,h,r,project)
  local x,y=im.GetCursorScreenPos(ctx);local draw=im.GetWindowDrawList(ctx)
  im.InvisibleButton(ctx,'##deess_overview',w,h)
  im.DrawList_AddRectFilled(draw,x,y,x+w,y+h,0x171A2060,ROUND,im.DrawFlags_RoundCornersBottom)
  if not d or not (d.audio or d.quick) or not d.view then return end
  local data,v=d.audio or d.quick,d.view;local scale=math.max(3,d.tool_preview and d.tool_preview.max_db or 0)
  -- вид покрывает все выбранные item одного трека (d.bounds считает M.draw); реакция и маркеры — в области главного item
  local bpos,blen=data.pos,data.len;if d.bounds then bpos,blen=d.bounds[1],d.bounds[2] end
  local ix,iw=x+(data.pos-bpos)/blen*w,data.len/blen*w
  for _,g in ipairs(d.group or {}) do
    local gd=g.audio or g.quick
    im.DrawList_AddRectFilled(draw,x+(gd.pos-bpos)/blen*w,y+2,x+(gd.pos+gd.len-bpos)/blen*w,y+h-2,0x7898B61C,2)
  end
  -- Reduction overview: a light 5 px blur and an antialiased outline instead
  -- of one hard bar per pixel.
  local n=math.floor(iw);local raw={}
  if d.tool_preview then for px=0,n-1 do raw[px]=math.max(0,Cleanup.value(d.tool_preview,data.len*(px+.5)/iw)) end end
  local previous,previous_db
  for px=0,n-1 do
    local sum,count=0,0
    for k=-2,2 do local value=raw[px+k];if value then sum=sum+value;count=count+1 end end
    local db=count>0 and sum/count or 0
    local top=y+h-2-(h-4)*math.min(1,db/scale)
    if db>.01 then im.DrawList_AddLine(draw,ix+px+.5,top,ix+px+.5,y+h-2,0xD8AC7748) end
    if previous and (db>.01 or previous_db>.01) then im.DrawList_AddLine(draw,ix+px-1,previous,ix+px,top,0xE6BC88D0,1.2) end
    previous,previous_db=top,db
  end
  -- d.marks: отметки событий на обзорной полосе ({start,finish,col} в секундах от начала item)
  for _,m in ipairs(d.marks or {}) do
    local ma=ix+m.start/data.len*iw;local mb=math.max(ma+1,ix+m.finish/data.len*iw)
    im.DrawList_AddRectFilled(draw,ma,y+3,mb,y+h-3,m.col)
  end
  local a=x+(v.start-bpos)/blen*w;local b=a+v.span/blen*w
  if im.IsItemHovered(ctx) and im.IsMouseClicked(ctx,0) then
    local mx=im.GetMousePos(ctx)
    d.overview_grab=mx>=a and mx<=b and (mx-a)/w*blen or v.span/2
  end
  if im.IsItemActive(ctx) and im.IsMouseDown(ctx,0) and d.overview_grab then
    if r then Transport.hold(d,r) end
    local mx=im.GetMousePos(ctx)
    v.start=DSP.clamp(bpos+(mx-x)/w*blen-d.overview_grab,bpos,bpos+blen-v.span)
    a=x+(v.start-bpos)/blen*w;b=a+v.span/blen*w
  end
  if im.IsItemHovered(ctx) and im.IsMouseDoubleClicked(ctx,0) then v.start=bpos;v.span=blen;a=x;b=x+w end
  if not im.IsMouseDown(ctx,0) then d.overview_grab=nil end
  -- рамка вида — тёплым акцентом, как выделение в топбаре навигации
  im.DrawList_AddRectFilled(draw,a,y+1,b,y+h-1,0xCC7D361C,3)
  im.DrawList_AddRect(draw,a,y+1,b,y+h-1,0xCC7D36A0,3)
  if r then Transport.draw(im,draw,Transport.read(r,project),function(t)return x+(t-bpos)/blen*w end,x,x+w,y,y+h) end
end
return M
