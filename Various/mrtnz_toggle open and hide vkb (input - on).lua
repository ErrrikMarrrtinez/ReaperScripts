-- @description Toggle open and hide VKB (input - on-off)
-- @author mrtnz
-- @version 1.00
-- @about
--   open or hide vbk

function getCommandState(commandId)
    local _, _, sectionId = reaper.get_action_context()
    return reaper.GetToggleCommandStateEx(sectionId, commandId)
  end
  
 
  function ensureCommandState(commandId, activateIfOff)
    local currentState = getCommandState(commandId)
    if (currentState == 0 and activateIfOff) or (currentState == 1 and not activateIfOff) then
      reaper.Main_OnCommand(commandId, 0)
    end
  end
  
  ensureCommandState(40637, true)
  ensureCommandState(40377, true)
  
  function msg(s) reaper.ShowConsoleMsg(tostring(s).."\n") end
  
  local _, _, section_id, command_id = reaper.get_action_context()
  
  function ToolbarButton(enable)
    reaper.SetToggleCommandState(section_id, command_id, enable)
    reaper.RefreshToolbar2(section_id, command_id)
  end
  
  function setVKBPositionAndSize(newX, newY, windowWidth, windowHeight)
    local vkbTitles = {"Virtual MIDI keyboard", "Виртуальная MIDI-клавиатура"}
    for _, title in ipairs(vkbTitles) do
      local vkb = reaper.JS_Window_Find(title, true)
      if vkb then
        reaper.JS_Window_SetPosition(vkb, newX, newY, windowWidth, windowHeight)
        return
      end
    end
    ensureCommandState(40377, true)
  end
  
  function Exit()
    setVKBPositionAndSize(400, 400, 380, 210)
    ensureCommandState(40637, false)
    ensureCommandState(40377, false)
    ToolbarButton(0)
  end
  
  function updateVKBPositionAndSize()
    local toggleState = reaper.GetToggleCommandStateEx(section_id, command_id)
    if toggleState == 1 then
      setVKBPositionAndSize(-200, 100, 110, 28)
    end
  end
  
  function Main()
    updateVKBPositionAndSize()
    reaper.defer(Main)
  end
  
  if reaper.GetToggleCommandStateEx(section_id, command_id) == 0 then
    reaper.atexit(Exit)
    ToolbarButton(1)
    Main()
    reaper.UpdateArrange()
  else
    ToolbarButton(0)
    Exit()
  end