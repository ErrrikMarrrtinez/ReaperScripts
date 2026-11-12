-- @noindex
-- Страница DeClick (Click / Mouth) нового интерфейса. Алгоритмы и запись — click/* (контроллер).
-- Раскладка как у остальных стадий: кнопка анализа и режим, слайдеры, волна + прогресс + обзорная полоса.
-- Холст общий (ui2/canvas.lua): зум, панорама, edit-курсор, выделение = time selection REAPER и ограничивает правку.
-- Волна своя: честно двусторонняя моно (min/max, без зеркала), при приближении — по отдельным отсчётам.
-- Применение живое: после анализа и каждого изменения слайдеров превью сразу пишется в проект (SAMPLEEDITS),
-- пока стадия включена тогглом на плитке; выключение снимает правку этой сессии.
local import=...;local Settings=import('click/settings');local SE=import('click/sample_edits');local W=import('ui2/widgets')
local Canvas=import('ui2/canvas');local Progress=import('progress');local Session=import('click/session');local M={}
local NAV=22
local im,ctx -- на кадр
local ctl,adapter,owner
local d,P,pv,built_for,pv_for -- состояние холста: d (как у cleaner), P пики, pv правленые отсчёты
local COL={fill=0xA3AFBF40,edge=0xA3AFBFD0,fixed=0x6FB6FFF0,zone=0xE8BC7326,zone_off=0xFFFFFF0A,mark=0xE6BC88C0,
  mark_off=0xFFFFFF30,zero=0xFFFFFF12,err=0xF29A91FF,warn=0xE8BC73FF,muted=0x989FAAFF}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function action(c,fn) local ok,why=xpcall(fn,debug.traceback);if not ok then c:fail(why) end end

-- ===== данные для отрисовки =====
-- Два источника данных. C++ (s.nio — ручка, которая держит файл): пирамида пиков строится в пуле во время чтения,
-- отсчёты для зума читаются из файла по запросу, Lua не хранит PCM. Без расширения/чтения файла в C++ — прежний путь:
-- пики считаются циклом по блокам s.pcm.blocks, отсчёты берутся из них же.
local function native_of(s) return s and s.nio and s.nio.native or nil end
-- моно-сумма отсчётов item-локальных кадров first..last (включительно): out[i]=значение.
-- C++: таблица-обёртка над одним чтением (значения не копируются в таблицу с огромными индексами); кеш по (first,last).
local sample_cache
local function samples(s,first,last)
  local pcm=s.pcm;local ch=pcm.channels;local out={}
  first=math.max(0,first);last=math.min(pcm.frames-1,last)
  if last<first then return out end
  local nat=native_of(s)
  if nat then
    local c=sample_cache
    if c and c.h==s.nio and c.first==first and c.last==last then return c.view end
    local vals=nat:read(s.nio,first,last-first+1,-1);local o=first-1
    local view=setmetatable({},{__index=function(_,i) return vals[i-o] end})
    sample_cache={h=s.nio,first=first,last=last,view=view}
    return view
  end
  for bi=first//pcm.block_size+1,last//pcm.block_size+1 do
    local b=pcm.blocks[bi]
    if b then
      local a,z=math.max(first,b.first),math.min(last,b.first+b.count-1)
      if z>=a then
        local vals=b.buffer.table((a-b.first)*ch+1,(z-a+1)*ch)
        for i=a,z do local v=0;for c=1,ch do v=v+vals[(i-a)*ch+c] end;out[i]=v/ch end
      end
    end
  end
  return out
end
-- пирамида пиков моно-суммы: уровни по 16, 128, 1024 кадров (min/max)
local function peaks(s)
  local pcm=s.pcm;local ch=pcm.channels;local H=16
  if native_of(s) then return {native=native_of(s),h=s.nio,sr=pcm.sr,frames=pcm.frames,peak=0,ready=false,done=0} end
  local mn,mx={},{};local lo,hi,cnt=math.huge,-math.huge,0;local peak=0
  for _,b in ipairs(pcm.blocks) do
    local vals=b.buffer.table()
    for f=0,b.count-1 do
      local v=0;for c=1,ch do v=v+vals[f*ch+c] end;v=v/ch
      if v<lo then lo=v end;if v>hi then hi=v end;cnt=cnt+1
      if cnt==H then mn[#mn+1]=lo;mx[#mx+1]=hi;lo,hi,cnt=math.huge,-math.huge,0 end
    end
  end
  if cnt>0 then mn[#mn+1]=lo;mx[#mx+1]=hi end
  for i=1,#mn do peak=math.max(peak,-mn[i],mx[i]) end
  local levels={{hop=H,mn=mn,mx=mx}}
  for _=1,2 do
    local src=levels[#levels];local a,b={},{}
    for i=1,#src.mn,8 do
      local l,h=math.huge,-math.huge
      for k=i,math.min(#src.mn,i+7) do l=math.min(l,src.mn[k]);h=math.max(h,src.mx[k]) end
      a[#a+1]=l;b[#b+1]=h
    end
    levels[#levels+1]={hop=src.hop*8,mn=a,mx=b}
  end
  return {sr=pcm.sr,frames=pcm.frames,levels=levels,peak=peak,ready=true}
end
-- C++: опрос готовности пирамиды (пока идёт чтение; потом не опрашиваем) и общий пик для масштаба по вертикали
local function peaks_progress(P)
  if not P or not P.native or P.ready then return end
  local info=P.native:source_info(P.h)
  if info then P.peak=info.peak;P.done=info.done;if info.status==1 then P.ready=true end end
end
-- правленые отсчёты (моно): map[i]=значение, idx — item-локальные индексы (порядок не важен: сортировать миллион точек
-- на каждое превью незачем — зум берёт значения из map, обзор только раскладывает по пикселям).
-- Значение кадра — сумма каналов/ch; канал без правки берёт исходный отсчёт (C++: читается из файла только для таких кадров).
local function patch_view(s,patch)
  local out={map={},idx={}};if not patch then return out end
  local ch=s.pcm.channels;local map,idx=out.map,out.idx;local first=s.first;local need={}
  if ch==1 then
    for index,v in pairs(patch[0] or {}) do local i=index-first;map[i]=v;idx[#idx+1]=i end
    return out
  end
  for c=0,ch-1 do
    local pts=patch[c]
    if pts then for index in pairs(pts) do
      local i=index-first
      if map[i]==nil then
        local sum,miss=0,false
        for k=0,ch-1 do local pk=patch[k];local v=pk and pk[index];if v==nil then miss=true;break end;sum=sum+v end
        idx[#idx+1]=i
        if miss then map[i]=false;need[#need+1]=i else map[i]=sum/ch end
      end
    end end
  end
  if #need>0 then -- редкий случай: не все каналы правлены в кадре
    table.sort(need)
    local nat=native_of(s);local k=1
    local function mix(i,vals,o)
      local sum=0;local index=i+first
      for c=0,ch-1 do local pk=patch[c];sum=sum+((pk and pk[index]) or vals[o+c+1] or 0) end
      map[i]=sum/ch
    end
    while k<=#need do
      if nat then -- близкие кадры читаются одним куском
        local a=need[k];local z=a;local j=k
        while j<#need and need[j+1]-z<=64 do j=j+1;z=need[j] end
        local vals=nat:read(s.nio,a,z-a+1,-2)
        for q=k,j do mix(need[q],vals,(need[q]-a)*ch) end
        k=j+1
      else
        local i=need[k];local orig=s.pcm.blocks[i//s.pcm.block_size+1]
        mix(i,orig and orig.buffer.table((i-orig.first)*ch+1,ch) or {},0);k=k+1
      end
    end
  end
  return out
end

-- ===== отрисовка волны (вызывается общим холстом) =====
local cur,cur_events -- что сейчас показано: источник (идущий анализ или готовый) и его кандидаты
local columns -- кеш столбцов обзора: пересчёт только при смене вида/готовности пирамиды
local function overview_columns(w,base,spp)
  -- C++: столбцы берутся из пирамиды одним вызовом; Lua: прежний перебор уровня (результат один и тот же)
  local nat=P.native
  if nat then
    local key=('%.17g:%.17g:%d:%d:%s'):format(base,spp,w,P.done or 0,tostring(P.h))
    if columns and columns.key==key then return columns.v end
    local v=nat:view_peaks(P.h,base,spp,w) or {}
    -- общий пик (масштаб по вертикали) не должен отставать от увиденных столбцов, пока пирамида ещё достраивается
    for i=1,#v,2 do local a,b=v[i],v[i+1];if a<=b then P.peak=math.max(P.peak,-a,b) end end
    columns={key=key,v=v};return v
  end
  return nil
end
local ocache -- кеш столбцов правки (исправленные отсчёты по пикселям)
local function patch_columns(w,base,spp)
  local key=('%.17g:%.17g:%d'):format(base,spp,w)
  if ocache and ocache.pv==pv and ocache.key==key then return ocache.lo,ocache.hi end
  local lo,hi={},{}
  for _,i in ipairs(pv.idx) do
    local px=math.floor((i-base)/spp)
    if px>=0 and px<w then local val=pv.map[i]
      lo[px]=math.min(lo[px] or val,val);hi[px]=math.max(hi[px] or val,val) end
  end
  ocache={pv=pv,key=key,lo=lo,hi=hi};return lo,hi
end
local function paint(draw,x,y,w,h,v)
  local s=cur;if not s or not P then return end
  peaks_progress(P)
  local sr,pos=P.sr,d.snapshot.pos
  local mid=y+h*.5
  local function X(t) return x+(pos+t-v.start)/v.span*w end
  for _,e in ipairs(cur_events) do -- зоны кандидатов под волной
    local a,b=X(e.start),X(e.finish)
    if b>=x and a<=x+w then im.DrawList_AddRectFilled(draw,a,y,math.max(a+2,b),y+h,e.excluded and COL.zone_off or COL.zone) end
  end
  im.DrawList_AddLine(draw,x,mid,x+w,mid,COL.zero)
  local spp=v.span*sr/w;local base=(v.start-pos)*sr
  local cols=spp>3 and overview_columns(math.floor(w),base,spp) or nil
  local g=.46*h/math.max(P.peak,1e-6)
  if spp>3 then -- обзор: min/max по пикселю
    local pt,pb
    local L=nil
    if not cols then L=P.levels[1];for _,l in ipairs(P.levels) do if l.hop<=spp then L=l end end end
    for px=0,math.floor(w)-1 do
      local lo,hi
      if cols then
        local a,b=cols[2*px+1],cols[2*px+2]
        if a and b and a<=b then lo,hi=a,b end
      else
        local i0=math.floor((base+px*spp)/L.hop)+1;local i1=math.floor((base+(px+1)*spp)/L.hop)+1
        if i1>=1 and i0<=#L.mn then
          i0=math.max(1,i0);i1=math.max(i0,math.min(#L.mn,i1))
          lo,hi=math.huge,-math.huge
          for k=i0,i1 do if L.mn[k]<lo then lo=L.mn[k] end;if L.mx[k]>hi then hi=L.mx[k] end end
        end
      end
      if lo then
        local top,bot=mid-hi*g,mid-lo*g
        im.DrawList_AddLine(draw,x+px+.5,top,x+px+.5,math.max(bot,top+1),COL.fill)
        if pt then
          im.DrawList_AddLine(draw,x+px-.5,pt,x+px+.5,top,COL.edge)
          im.DrawList_AddLine(draw,x+px-.5,pb,x+px+.5,bot,COL.edge)
        end
        pt,pb=top,bot
      else pt=nil end
    end
    if pv and #pv.idx>0 then -- исправленные отсчёты поверх: min/max правки по пикселю
      local lo,hi=patch_columns(math.floor(w),base,spp)
      for px,l in pairs(lo) do
        im.DrawList_AddLine(draw,x+px+.5,mid-hi[px]*g-.5,x+px+.5,mid-l*g+.5,COL.fixed)
      end
    end
  else -- по отсчётам: оригинал и поверх исправление; при ≥4 px на отсчёт — точки
    local first,last=math.floor(base)-1,math.ceil(base+w*spp)+1
    local S=samples(s,first,last)
    local function sx(i) return x+(i-base)/spp end
    for i=first,last-1 do
      local a,b=S[i],S[i+1]
      if a and b then im.DrawList_AddLine(draw,sx(i),mid-a*g,sx(i+1),mid-b*g,COL.edge,1.2) end
    end
    if pv then
      for i=first,last-1 do
        local a,b=pv.map[i],pv.map[i+1]
        if a or b then
          a=a or S[i];b=b or S[i+1]
          if a and b then im.DrawList_AddLine(draw,sx(i),mid-a*g,sx(i+1),mid-b*g,COL.fixed,1.6) end
        end
      end
    end
    if spp<.25 then
      for i=first,last do
        local val=pv and pv.map[i] or S[i]
        if val then im.DrawList_AddCircleFilled(draw,sx(i),mid-val*g,2,pv and pv.map[i] and COL.fixed or COL.edge) end
      end
    end
  end
end
local function status()
  if ctl.error then return 'Error · see Details',COL.err end
  if ctl.bypassed then return 'Bypassed',COL.warn end
  if ctl.job then return nil end
  local active=0;for _,e in ipairs(ctl.events) do if not e.excluded then active=active+1 end end
  if ctl.s and next(ctl.s.owned or {}) then return ('%d fixed'):format(active),COL.muted end
  return ('%d found'):format(active),COL.muted
end

-- ===== выделение = time selection REAPER =====
local function set_range(x,y,on)
  if d.range[1]~=x or d.range[2]~=y or d.selected~=on then
    -- ctl:request() во время анализа ничего не отменяет (см. controller.lua): диапазон применится к первому превью
    d.range={x,y};d.selected=on;ctl.range=on and {x,y} or nil;ctl:request()
  end
end
local function sync_range(r)
  if not d or owner.gesture or not owner.project or r.EnumProjects(-1)~=owner.project then return end
  local a,b=r.GetSet_LoopTimeRange2(owner.project,false,false,0,0,false)
  if owner.sel and math.abs(a-owner.sel[1])<1e-8 and math.abs(b-owner.sel[2])<1e-8 then return end
  owner.sel={a,b}
  local pos,len=d.snapshot.pos,d.snapshot.len
  local on=b>a and b>pos and a<pos+len;local x,y=0,len
  if on then x=clamp(a-pos,0,len);y=clamp(b-pos,x,len) end
  if y-x<.001 then x,y,on=0,len,false end
  set_range(x,y,on)
end

local function get(app)
  if ctl and ctl.ctx==ctx then return ctl end
  local r=app.r
  ctl=import('click/controller').new(r,import('click/engine').new(im,ctx,r),import('cleanup_dsp').new(im,ctx,r),import('click/repair').new(im,ctx,r))
  ctl.ctx=ctx;ctl.mode='mouth';ctl.auto_apply=true;app.click_cleanup=ctl
  -- W.grid правит owner.cfg[key] и зовёт settings_changed: адаптер превращает это в c:request().
  adapter={cfg=ctl.cfg,gesture=false,settings_changed=function() ctl:request() end,control_released=function() end}
  -- «владелец» для общего холста: тот же интерфейс, что у cleaner (current/set_range/seek/...)
  owner={r=r,mode='declick',gesture=false}
  function owner:current() return d end
  function owner:bypassed() return ctl.bypassed==true end
  function owner:control_released() end
  function owner:seek(t) if d and self.project then r.SetEditCurPos2(self.project,d.snapshot.pos+clamp(t,0,d.snapshot.len),false,false) end end
  function owner:set_range(a,b,sync)
    if not d then return end
    if a>b then a,b=b,a end
    a,b=clamp(a,0,d.snapshot.len),clamp(b,0,d.snapshot.len)
    if b-a<.001 then return end
    if sync and self.project and r.EnumProjects(-1)==self.project then
      local x,y=d.snapshot.pos+a,d.snapshot.pos+b
      r.GetSet_LoopTimeRange2(self.project,true,false,x,y,false);self.sel={x,y}
    end
    set_range(a,b,true)
  end
  function owner:toggle_region(_,event) for i,e in ipairs(ctl.events) do if e==event then ctl:exclude(i);return end end end
  r.atexit(function() ctl:cancel() end)
  return ctl
end
function M.tick() if ctl then ctl:tick() end end
function M.busy() return ctl~=nil and ctl.job~=nil end
-- Тоггл плитки: выкл снимает правку этой сессии, вкл снова применяет текущее превью.
function M.is_on() return not (ctl and ctl.bypassed) end
function M.toggle() if ctl and not ctl.job then ctl:set_bypass(not ctl.bypassed) end end
function M.clear_range(app)
  if not d or not owner.project or app.r.EnumProjects(-1)~=owner.project then return end
  app.r.GetSet_LoopTimeRange2(owner.project,true,false,0,0,false);sync_range(app.r)
end

local function details(c,app)
  im.SetNextWindowSizeConstraints(ctx,380,0,560,720)
  if im.BeginPopup(ctx,'##declick_details') then
    im.PushTextWrapPos(ctx,im.GetCursorPosX(ctx)+500)
    im.Text(ctx,c.message or '')
    if c.error then im.PushStyleColor(ctx,im.Col_Text,COL.err);im.TextWrapped(ctx,c.error);im.PopStyleColor(ctx) end
    if not SE.supported(app.r.GetAppVersion()) then im.TextWrapped(ctx,'Writing sample edits requires REAPER 7.71 or newer.') end
    if c.work_ms then im.TextDisabled(ctx,('Last job %.1f ms work · longest step %.1f ms'):format(c.work_ms,c.max_step_ms or 0)) end
    if c.skipped and c.skipped>0 then im.TextDisabled(ctx,('%d repairs skipped (short context or too long)'):format(c.skipped)) end
    im.PopTextWrapPos(ctx)
    im.Spacing(ctx)
    im.TextDisabled(ctx,('Candidates (%d) · unchecked are kept as is'):format(#c.events))
    if im.BeginChild(ctx,'##declick_list',500,math.min(260,24+#c.events*24)) then
      im.BeginDisabled(ctx,c.job~=nil or not c.ready)
      for i=1,math.min(400,#c.events) do
        local e=c.events[i]
        local label=('%03d  %.3f–%.3f s  score %.1f%s##ev%d'):format(i,e.start,e.finish,e.score or 0,e.outside and '  (outside selection)' or '',i)
        if im.Checkbox(ctx,label,not e.excluded) and not e.outside then c:exclude(i) end
      end
      im.EndDisabled(ctx)
      im.EndChild(ctx)
    end
    if im.Button(ctx,'Copy report') then im.SetClipboardText(ctx,c:diagnostics()) end
    im.EndPopup(ctx)
  end
end

function M.draw(im_,ctx_,app,color)
  im,ctx=im_,ctx_
  local c=get(app);local r=app.r
  owner.gesture=false
  -- после перезапуска скрипта: если для выделенного тейка есть сессия, продолжаем с того же места
  if not c.s and not c.job and not c.pending then
   local item=r.CountSelectedMediaItems(0)==1 and r.GetSelectedMediaItem(0,0)
   local take=item and r.GetActiveTake(item)
   local guid=take and select(2,r.GetSetMediaItemTakeInfo_String(take,'GUID','',false))
   if guid and guid~=c.resume_checked then
    c.resume_checked=guid
    local saved=Session.load(r,guid)
    if saved then action(c,function() c:resume(saved) end) end
   end
  end
  -- данные холста: пересобираются при новом анализе / новом превью. Пока идёт анализ C++, обзор волны открывается сразу
  -- (c.loading: пики готовы намного раньше признаков); кандидаты и правка появятся с готовым анализом.
  local shown=c.loading or c.s
  if shown~=built_for then
    built_for=shown;d,P,pv,pv_for,columns,ocache,sample_cache=nil,nil,nil,nil,nil,nil,nil
    if shown then
      local s=shown;P=peaks(s);owner.project=s.project;owner.sel=nil
      local name='item'
      if r.ValidatePtr2(s.project,s.item,'MediaItem*') then local take=r.GetActiveTake(s.item);if take then name=r.GetTakeName(take) end end
      d={snapshot={name=name,pos=s.pos,len=s.len},audio={pos=s.pos,len=s.len,hop=1/s.sr},range={0,s.len},selected=false,detected={sibilants={}},marks={}}
      c.range=nil
    end
  end
  cur=shown;cur_events=(c.loading and c.loading~=c.s) and {} or c.events
  if d then
    d.detected.sibilants=cur_events
    if c.loading and c.loading~=c.s then pv=nil;pv_for=nil
    elseif c.patch~=pv_for then pv_for=c.patch;pv=patch_view(c.s,c.patch) end
    if c.bypassed then pv=nil;pv_for=nil end
    local marks={};for _,e in ipairs(cur_events) do marks[#marks+1]={start=e.start,finish=e.finish,col=e.excluded and COL.mark_off or COL.mark} end
    d.marks=marks
    sync_range(r)
  end

  -- ряд: анализ, режим, справа Details
  if im.Button(ctx,'Analyze') then action(c,function() c:reset_and_analyze() end) end
  if im.IsItemHovered(ctx) then im.SetTooltip(ctx,'Start over: remove the fixes made in this session (the item returns to its original samples), then read the selected audio item (one take) and find clicks again. Fixes are written live while DeClick is on.') end
  im.SameLine(ctx)
  if im.RadioButton(ctx,'Mouth',c.mode=='mouth') then c.mode='mouth';c:request() end
  im.SameLine(ctx)
  if im.RadioButton(ctx,'Click',c.mode=='click') then c.mode='click';c:request() end
  im.SameLine(ctx)
  local bw=im.CalcTextSize(ctx,'Details')+18;local avail=im.GetContentRegionAvail(ctx)
  if avail>bw then im.Dummy(ctx,avail-bw,1);im.SameLine(ctx,0,0) end
  if c.error then im.PushStyleColor(ctx,im.Col_Text,COL.err) end
  if im.Button(ctx,'Details',bw) then im.OpenPopup(ctx,'##declick_details') end
  if c.error then im.PopStyleColor(ctx) end
  details(c,app)

  W.grid(im,ctx,adapter,'##declick_controls',Settings.controls[c.mode],3)
  local sliding=adapter.gesture;adapter.gesture=false
  if sliding then owner.gesture=true end

  -- волна, прогресс-бар и обзорная полоса вплотную
  im.Dummy(ctx,1,4)
  local w,h=im.GetContentRegionAvail(ctx)
  im.PushStyleVar(ctx,im.StyleVar_ItemSpacing,0,0)
  Canvas.draw(im,ctx,owner,w,math.max(100,h-NAV-Progress.height-2),color,nil,{min_span=.002,paint=paint,status=status})
  Progress.draw(im,ctx,c.job,r)
  Canvas.navigator(im,ctx,d,w,NAV,r,owner.project)
  im.PopStyleVar(ctx)
  -- пока тянут слайдер или выделение на волне — только превью, запись в проект после отпускания
  c.hold=sliding or owner.gesture
end
return M
