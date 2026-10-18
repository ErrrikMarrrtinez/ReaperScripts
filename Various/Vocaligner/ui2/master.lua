-- @noindex
-- Общий BYPASS скрипта (кнопка слева в топбаре). Один быстрый переключатель вместо пересчёта стадий:
-- состояние chunk айтемов до скрипта хранится в проекте (ui2/snapshot.lua), bypass подменяет им текущее состояние
-- одной записью, выключение возвращает обработанное. Действует на выделенные айтемы и затрагивает всё сразу: Cleanup, DeClick, Pitch, Align.
local import=...;local Snap=import('ui2/snapshot');local M={}
local function project() return reaper.EnumProjects(-1) end
local function status() local ok,v=pcall(Snap.status,reaper,project());return ok and v or {engaged=false,available=false} end
-- Для выделенных айтемов: bypass включён / есть ли в них изменения скрипта (иначе кнопка неактивна)
function M.is_off() return status().engaged end
function M.available() return status().available end
function M.busy() return false end -- переключение мгновенное, очереди нет
function M.install() Snap.hook(reaper) end

function M.toggle(app)
  local r,p=reaper,project()
  if status().engaged then
    local restored,conflicts=Snap.release(r,p)
    app:report(('Bypass off: %d item(s) restored.%s'):format(restored,conflicts>0 and
      (' %d changed while bypassed and were left as is, process them again.'):format(conflicts) or ''))
    if conflicts>0 and r.ShowConsoleMsg then r.ShowConsoleMsg(('Vocaligner: %d item(s) were edited during bypass and were not restored; process them again.\n'):format(conflicts)) end
  else
    local reverted,failed=Snap.engage(r,p)
    app:report(('Bypass on: %d item(s) back to their original state.%s'):format(reverted,failed>0 and (' %d could not be switched.'):format(failed) or ''))
    if reverted==0 and r.ShowConsoleMsg then r.ShowConsoleMsg('Vocaligner: nothing to bypass: no stored original state for the items in this project yet (it is saved right before the first change the script makes).\n') end
  end
end
return M
