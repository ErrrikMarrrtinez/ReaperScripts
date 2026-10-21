-- @noindex
-- Общие виджеты нового интерфейса. Сейчас 1 в 1 повторяют controls.lua (оригинал не тронут),
-- но весь рисунок слайдеров/сетки собран здесь: дальше меняем только этот файл.
local import=...;local M={}
-- ===== живое применение с задержкой =====
-- Compressor/Gate по умолчанию считаются после отпускания контрола. Для «дешёвых» параметров (огибающая считается
-- по уже закэшированному детектору) расчёт и запись идут сразу во время движения, но с паузой после последнего
-- шага (live_delay): пока крутишь — ничего не пересчитывается, остановился на долю секунды — применилось.
-- «Тяжёлые» (меняют сам детектор: RMS, интервал, HP/LP) остаются по отпусканию, как раньше.
M.live_delay=.18
M.live={
  compressor_threshold=true,compressor_ratio=true,compressor_gain=true,compressor_attack_ms=true,compressor_release_ms=true,
  compressor_pre_ms=true,compressor_knee=true,compressor_detail=true,
  gate_threshold=true,gate_hysteresis=true,gate_range=true,gate_attack_ms=true,gate_hold_ms=true,
  gate_release_ms=true,gate_pre_ms=true,gate_detail=true,
}
-- Сообщить cleaner об изменении параметра: живой параметр во время жеста идёт по пути RT Update
-- (подготовка превью и запись), но стартует не сразу, а через live_delay после последнего изменения.
-- Недоступная область не должна «отдавать» клик окну (иначе оно начинает перетаскиваться): накрываем её невидимой кнопкой.
-- Вызывается после EndDisabled, x,y — левый верхний угол области, курсор возвращается в конец.
function M.catch(im,ctx,x,y,w,h,id)
  local ex,ey=im.GetCursorScreenPos(ctx)
  if h<=0 then return end
  im.SetCursorScreenPos(ctx,x,y);im.InvisibleButton(ctx,id or '##disabled_catch',w,h)
  im.SetCursorScreenPos(ctx,ex,ey)
end
function M.changed(owner,key)
  local rt=owner.cfg.dynamics_rt
  if M.live[key] and rt and rt<.5 and owner.gesture then
    owner.cfg.dynamics_rt=1
    local ok,err=pcall(owner.settings_changed,owner,key)
    owner.cfg.dynamics_rt=rt
    if not ok then error(err,0) end
    local now=reaper.time_precise()
    owner.live_until=now+.5 -- пока крутят «лёгкий» параметр, запись идёт по темпу измеренной задержки
    -- темп, а не «дебаунс»: ближайшее обновление не отодвигается при каждом движении слайдера, а стартует не позже live_delay
    if owner.pending then owner.pending=math.min(owner.pending,now+(owner.live_delay and owner:live_delay() or M.live_delay)) end
  else owner:settings_changed(key) end
end
-- A short parameter commit still blocks conflicting actions, without making
-- the whole panel flash grey. Persistent unavailable controls keep their tint.
function M.disabled(im,ctx,disabled,quiet)
  local stable=disabled and quiet and im.PushStyleVar and im.StyleVar_DisabledAlpha
  if stable then im.PushStyleVar(ctx,im.StyleVar_DisabledAlpha,1)end
  im.BeginDisabled(ctx,disabled==true)
  if stable then im.PopStyleVar(ctx)end
end
-- Один слайдер параметра cfg[key] владельца (cleaner): подпись сверху, значение внутри.
function M.slider(im,ctx,owner,key,label,lo,hi,fmt,width,tip)
  -- Group both items: a table cell must align the whole control, not the slider's baseline.
  im.BeginGroup(ctx)
  im.TextDisabled(ctx,label);im.SetNextItemWidth(ctx,width or -1)
  local changed,value=im.SliderDouble(ctx,'##'..key,owner.cfg[key],lo,hi,fmt)
  if im.IsItemActive(ctx) then owner.gesture=true end
  if changed then owner.cfg[key]=value;M.changed(owner,key) end
  if im.IsItemDeactivatedAfterEdit(ctx) then owner:control_released() end
  if tip and im.IsItemHovered(ctx) then im.SetTooltip(ctx,tip) end
  im.EndGroup(ctx)
end
-- Сетка слайдеров: entries = {{key,label,lo,hi,fmt,tip},...}
function M.grid(im,ctx,owner,id,entries,max_columns)
  local w=im.GetContentRegionAvail(ctx)
  local columns=math.max(1,math.min(max_columns or 3,math.floor(w/145)))
  if im.BeginTable(ctx,id,columns,im.TableFlags_SizingStretchSame) then
    for _,e in ipairs(entries) do
      im.TableNextColumn(ctx)
      if e.draw then e.draw(im,ctx,owner,e) -- свой виджет ячейки (например, ручка-полоска у Ratio)
      else M.slider(im,ctx,owner,e[1],e[2],e[3],e[4],e[5],-1,e[6]) end
    end
    im.EndTable(ctx)
  end
end
-- Чекбокс параметра cfg[key] (0/1) владельца.
function M.toggle(im,ctx,owner,key,label,tip)
  local changed,on=im.Checkbox(ctx,label,(owner.cfg[key] or 0)>=.5)
  if changed then owner.cfg[key]=on and 1 or 0;owner:settings_changed(key);owner:control_released() end
  if tip and im.IsItemHovered(ctx) then im.SetTooltip(ctx,tip) end
end
return M
