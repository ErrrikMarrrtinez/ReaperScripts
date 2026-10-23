-- @noindex
-- Auto: автоматическая подгонка высоты поверх анализа и ручных правок редактора нот.
--   mode='key'       — к ближайшей ноте выбранной тональности (кроме Chromatic);
--   mode='reference' — к мелодии другого (уже проанализированного) трека в том же времени проекта, с сохранением октавы.
-- Параметры как у автотюнов: speed — постоянная времени подстройки, мс (0 — мгновенно: жёсткий тюн; 20–40 —
-- плотно; 100+ — только центр ноты, вибрато нетронуто); transitions (0..250 ms) — мягкость смены целевой ноты (0 — скачок);
-- amount (0..100 %) — доля поправки. Т.е. 0 / 0 / 100% — максимальное применение, как у Auto-Tune / Waves Tune.
-- Humanize (0..100) — на длинных нотах подстройка мягче (как у Auto-Tune); Flex Tune (0..100) — правит только когда голос
-- уже близко к ноте, отклонения и глайды не трогает; Vibrato (−100..100) — ослабить/усилить естественное вибрато.
-- Эти три работают в режиме Key; в Reference цель — мелодия лида со всеми её нюансами.
-- Слой считается один раз по готовому анализу (сетка 8 мс) и кешируется; Amount только масштабирует готовую поправку.
-- Ручные правки главнее: где у ноты нарисованная/целевая кривая, Flatten или флаг auto_off — Auto плавно выключается.
local import=...;local Expression=import('pitch/expression');local Scale=import('pitch/scale');local Notes=import('pitch/notes')
local M={}
local HOP=.008
local function clamp(x,a,b) return x<a and a or (x>b and b or x) end
M.defaults={on=false,mode='key',speed=25,transitions=40,amount=100,humanize=0,flex=0,vibrato=0,speed_ms=true}
function M.config(state)
  local a=state and state.auto;local out={}
  for k,v in pairs(M.defaults) do out[k]=v end
  for k,v in pairs(a or {}) do out[k]=v end
  return out
end

-- Опорная мелодия: функция project_time -> (центр высоты без вибрато, доверие), по проанализированным айтемам трека
function M.reference(e,track_guid,item_guid)
  local Workspace=import('pitch/workspace')
  local ws=e.workspace;if not ws or not track_guid then return nil end
  local row;for _,r in ipairs(ws.tracks) do if r.guid==track_guid then row=r;break end end
  if not row then return nil end
  local entries={}
  for _,entry in ipairs(row.items) do
    local guid=item_guid and e.r.GetSetMediaItemInfo_String and select(2,e.r.GetSetMediaItemInfo_String(entry.item,'GUID','',false))
    if entry.state and entry.state.analysis and entry.item~=e.item and (not item_guid or guid==item_guid) then
      local vis=Workspace.visual(e,entry)
      if vis and vis.data then entries[#entries+1]={pos=entry.pos,len=entry.len,data=vis.data} end
    end
  end
  if #entries==0 then return nil end
  return function(P)
    for _,x in ipairs(entries) do
      if P>=x.pos and P<=x.pos+x.len then
        -- текущая высота референса, сглаженная на 24 мс (как база выбора ноты в режиме Key): даб следует
        -- и за вибрато, и за переходами лида; Speed/Transitions сглаживают так же, как в Key
        local t=P-x.pos;local raw,_,trust=Expression.sample(x.data,t)
        if raw then
          local sum,cnt=raw,1
          for _,dt in ipairs({-HOP,HOP}) do local r2=Expression.sample(x.data,t+dt);if r2 then sum=sum+r2;cnt=cnt+1 end end
          return sum/cnt,trust or 0
        end
      end
    end
  end,row
end

-- Подпись ручных правок: слой Auto зависит от них (поправка считается к высоте С учётом ручного сдвига)
function M.notes_sig(notes)
  local out={}
  for i,n in ipairs(notes or {}) do
    out[#out+1]=string.format('%d:%.4f,%.4f,%.3f,%.3f,%.3f,%d,%d',n.id or i,n.start or 0,n.finish or 0,n.shift or 0,n.flatten or 0,n.center or 0,
      #(n.anchors or {}),#(n.drawings or {}))
  end
  return table.concat(out,';')
end
-- Ключ пересчёта слоя (без Amount — он только масштабирует)
function M.key(e,a)
  local parts={a.mode,string.format('%.3f|%.3f|%.3f|%.3f|%.3f',a.speed or 0,a.transitions or 0,a.humanize or 0,a.flex or 0,a.vibrato or 0),tostring(e.state and e.state.analysis)}
  if a.mode=='reference' then parts[#parts+1]=tostring(a.ref_track);parts[#parts+1]=tostring(a.ref_item);parts[#parts+1]=tostring(a.octave)
    parts[#parts+1]=tostring(e.workspace and e.workspace.revision)
  else parts[#parts+1]=tostring(e.root);parts[#parts+1]=tostring(e.scale) end
  if e.auto_mask then local bits={};for i=0,11 do bits[#bits+1]=e.auto_mask[i] and '1' or '0' end;parts[#parts+1]='mask'..table.concat(bits) end
  parts[#parts+1]=tostring(#M.notes_sig(e.notes or (e.state and e.state.notes)))..':'..M.hash_sig(M.notes_sig(e.notes or (e.state and e.state.notes)))
  return table.concat(parts,'|')
end
function M.hash_sig(s) local h=5381;for i=1,#s do h=(h*33+s:byte(i))&0x7fffffff end;return h end

function M.build(e,a)
  local data=e.data;local s=e.snapshot;if not data or not s then return nil end
  local len=s.len;local n=math.floor(len/HOP)+1
  -- сэмплы анализа (высота, центр, доверие) и сглаженная база выбора ноты не зависят от параметров Auto:
  -- считаются один раз на анализ, дальше крутить ручки дёшево
  local base=data._auto_base
  if not base or base.n~=n or base.offset~=(data._offset or 0) or base.frames~=#(data.frames or data._source and data._source.frames or {}) then
    local raw,cen,tr={},{},{}
    for k=1,n do
      local p,c,q=Expression.sample(data,(k-1)*HOP)
      if p and q and q>.05 then raw[k]=p;cen[k]=c or p;tr[k]=q end
    end
    local basis={}
    for k=1,n do if raw[k] then local sum,cnt=0,0;for j=k-1,k+1 do if raw[j] then sum=sum+raw[j];cnt=cnt+1 end end;basis[k]=sum/cnt end end
    base={n=n,offset=data._offset or 0,frames=#(data.frames or data._source and data._source.frames or {}),raw=raw,cen=cen,tr=tr,basis=basis}
    data._auto_base=base
  end
  local raw,cen,tr=base.raw,base.cen,base.tr
  -- Ручные правки (сдвиг, Flatten, вибрато и т. п.) учитываются как часть голоса: Auto доводит до ноты/референса уже
  -- ИХ результат, а не сырой анализ — правка вручную не отменяет подгонку и не складывается с ней в перекор.
  -- Нарисованные цели и опорные точки (target) остаются за пользователем: см. manual_weight.
  local manual
  do
    local notes=e.notes or (e.state and e.state.notes)
    if notes and #notes>0 then
      local sig=M.notes_sig(notes)..'|'..tostring(e.state and e.state.curve_version)..'|'..n
      local cached=data._auto_manual
      if cached and cached.sig==sig then manual=cached.manual or nil
      else
        local Curve=import('pitch/curve')
        local keep=data._auto;data._auto=nil
        local ok,ev=pcall(Curve.evaluator,notes,'shift',e.state and e.state.curve_version or 1,data)
        if ok then
          manual={}
          for k=1,n do if raw[k] then local ok2,v=pcall(ev,(k-1)*HOP);if ok2 and v and v==v and math.abs(v)>1e-6 then manual[k]=v end end end
          if next(manual)==nil then manual=nil end
        end
        data._auto=keep
        data._auto_manual={sig=sig,manual=manual or false}
      end
    end
  end
  if manual then
    local r2,c2,b2={},{},{}
    for k=1,n do if raw[k] then local m=manual[k] or 0;r2[k]=raw[k]+m;c2[k]=cen[k]+m end end
    for k=1,n do if r2[k] then local sum,cnt=0,0;for j=k-1,k+1 do if r2[j] then sum=sum+r2[j];cnt=cnt+1 end end;b2[k]=sum/cnt end end
    raw,cen=r2,c2;base={n=n,raw=r2,cen=c2,tr=tr,basis=b2}
  end
  local T={};local weight={}
  local stats={mode=a.mode,frames=0,switches=0}
  if a.mode=='reference' then
    local ref=M.reference(e,a.ref_track,a.ref_item)
    if not ref then return {hop=HOP,n=n,c={},stats={mode=a.mode,error='No analysed reference on the chosen track'}} end
    local rt={}
    for k=1,n do if cen[k] then local v,q=ref(s.pos+(k-1)*HOP);if v and q>.25 then rt[k]=v;weight[k]=math.min(1,q*1.4) end end end
    -- октава: явная (a.octave) или по медиане разницы, округлённой до 12 полутонов — гармония не превращается в унисон
    local oct=a.octave
    if oct==nil or oct=='auto' then
      local diffs={};for k=1,n do if rt[k] then diffs[#diffs+1]=cen[k]-rt[k] end end
      table.sort(diffs);local med=#diffs>0 and diffs[math.ceil(#diffs/2)] or 0
      oct=math.floor(med/12+.5)
    end
    stats.octave=oct
    for k=1,n do if rt[k] then T[k]=rt[k]+12*oct end end
  else
    -- цель — ближайшая нота тональности к текущей высоте голоса (слегка сглаженной, 24 мс), как у автотюнов;
    -- переключение — если голос ближе к другой ноте на 0.2 полутона и держится так 30 мс (кадры ожидания доучитываются).
    -- Сверено с Waves Tune на 62-секундном кейсе (Speed 0 и 30): центр за 170 мс с удержанием 50 мс тянул голос
    -- не к той ноте в 19% кадров; «защита от дребезга» по центру тоже только отдаляла от Waves — её нет.
    local root,scale=e.root or 0,e.scale or 1
    -- e.auto_mask — разово включённые/выключенные ноты в окне ATune (не сохраняется в состоянии)
    local nearest=e.auto_mask and Scale.nearest_mask(e.auto_mask) or Scale.nearest_fn(root,scale)
    -- лёгкая защита от дребезга, зависящая от Speed: при 0 её нет (жёсткий тюн переключает по текущей высоте, как
    -- Waves), к 60 мс — полная: переход требует согласия центра без вибрато, либо голос уже дальше середины на g
    local g=clamp((a.speed or 25)/60,0,1)
    -- на самых быстрых Speed гистерезис и удержание почти исчезают: цель скачет за голосом — характерное «бульканье»
    -- жёсткого тюна на глайдах и вибрато; к 20 мс — прежние 0.2 полутона и 30 мс
    local g2=clamp((a.speed or 25)/20,0,1);local hyst,hold=.05+.15*g2,HOP+.022*g2
    local basis=base.basis
    local cur,pend,pc,gap=nil,nil,0,0
    for k=1,n do
      local b=basis[k]
      if b and cen[k] then
        gap=0
        local cand=nearest(b)
        if not cur then cur=cand
        elseif cand~=cur and math.abs(b-cand)<math.abs(b-cur)-hyst
          and (g<=0 or math.abs(cen[k]-cand)<math.abs(cen[k]-cur) or math.abs(b-cand)<math.abs(b-cur)-g) then
          if pend==cand then pc=pc+1 else pend,pc=cand,1 end
          if pc*HOP>=hold-1e-9 then cur=cand;stats.switches=stats.switches+1;for j=k-pc+1,k-1 do if T[j] then T[j]=cand end end;pend,pc=nil,0 end
        else pend,pc=nil,0 end
        T[k]=cur;weight[k]=1
      else gap=gap+1;if gap*HOP>.048 then cur,pend,pc=nil,nil,0 end end
    end
  end
  local Ts=T
  -- Speed: как у автотюнов — поправка есть сглаженная ошибка «нота − голос» с постоянной времени Speed (мс).
  -- 0 — мгновенно (жёсткий тюн, вибрато выпрямлено); ~25 мс — плотно, вибрато частично; 100+ — вибрато и
  -- нюансы почти не тронуты, выравнивается только центр. Вход в ноту — с нуля, как у живого певца.
  local ms=clamp(a.speed or 25,0,400)
  local alpha=ms<=0 and 1 or 1-math.exp(-HOP/(ms/1000))
  -- до ближайшей ноты тональности не больше полутона: больше 1.25 — это уже не подстройка, а перепевание (глайды, срывы)
  local lim=a.mode=='reference' and 12 or 1.25
  local key=a.mode~='reference'
  -- Humanize: нота держится дольше 120 мс — постоянная времени плавно растёт (за 250 мс) на humanize·3.5 мс
  local hum=key and clamp(a.humanize or 0,0,100)*.0035 or 0
  -- Flex Tune: полная поправка, пока центр голоса (без вибрато) ближе r/2 к ноте, к r — сходит на нет; 0 — выключено
  local fk=key and clamp(a.flex or 0,0,100)/100 or 0;local fr=1-.85*fk
  local vib=key and clamp(a.vibrato or 0,-100,100)/100 or 0
  local c={};local state=nil;local held,prevT=0,nil
  for k=1,n do
    if Ts[k] and raw[k] then
      if Ts[k]~=prevT then held=0 else held=held+HOP end;prevT=Ts[k]
      local al=alpha
      if hum>0 then local tau=ms/1000+hum*clamp((held-.12)/.25,0,1);al=tau<=0 and 1 or 1-math.exp(-HOP/tau) end
      local d=Ts[k]-raw[k] -- полная ошибка (raw уже с ручным сдвигом); её сглаживание и даёт сохранение вибрато на медленных Speed
      state=(state or 0)+(d-(state or 0))*al
      local fw=1;if fk>0 then fw=clamp((fr-math.abs(Ts[k]-cen[k]))/(fr*.5),0,1) end
      c[k]=clamp(state*fw*(weight[k] or 1)*math.min(1,(tr[k] or 0)*1.6)+vib*(raw[k]-cen[k]),-lim,lim)
      stats.frames=stats.frames+1
    else state=nil;prevT=nil end
  end
  -- Transitions: сама поправка сглаживается окном внутри непрерывного звучания — смена ноты без скачка
  local w=math.max(0,math.floor((a.transitions or 0)/1000/HOP+.5))
  if w>=1 then
    local sm={}
    for k=1,n do if c[k] then
      local sum,cnt=0,0
      for j=k-w//2,k+(w-w//2) do if c[j] then sum=sum+c[j];cnt=cnt+1 end end
      sm[k]=sum/cnt
    end end
    c=sm
  end
  -- конец звучания: поправка сходит на нет за 30 мс (без щелчка высоты на хвосте)
  local fade=math.max(1,math.floor(.03/HOP))
  for k=1,n do if c[k] and not c[k+1] then for j=0,fade-1 do if c[k-j] then c[k-j]=c[k-j]*(j+1)/(fade+1) end end end end
  local sum=0;for k=1,n do if c[k] then sum=sum+math.abs(c[k]) end end
  stats.mean_abs=stats.frames>0 and sum/stats.frames or 0
  return {hop=HOP,n=n,c=c,stats=stats}
end

-- Сколько Auto «уступает» ручной правке в момент t (1 — полностью ручная, Auto выключен)
local function manual_weight(n)
  if not n then return 0 end
  if n.auto_off then return 1 end
  if n.target_anchors and #n.target_anchors>0 then return 1 end
  for _,s in ipairs(n.drawings or {}) do if s.target then return 1 end end
  return 0 -- сдвиг, Flatten и прочие ручные правки не отключают подгонку: она доводит уже их результат
end
function M.value(layer,t)
  if not layer or not layer.c then return 0 end
  local x=t/layer.hop;local k=math.floor(x)+1;local u=x-(k-1)
  local a,b=layer.c[k],layer.c[k+1]
  if a==nil and b==nil then return 0 end
  return (a or 0)*(1-u)+(b or 0)*u
end
function M.at(layer,notes,t)
  local v=M.value(layer,t)*(layer.amount or 1)
  if v==0 then return 0 end
  local _,i=Notes.at(notes,t);local p=0
  for j=(i or 1)-1,(i or 1)+1 do
    local m=notes[j]
    if m then
      local pr=manual_weight(m)
      if pr>0 then
        local d=t<m.start and m.start-t or (t>m.finish and t-m.finish or 0)
        p=math.max(p,pr*clamp(1-d/.03,0,1))
      end
    end
  end
  return v*(1-p)
end
return M
