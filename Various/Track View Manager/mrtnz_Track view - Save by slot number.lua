-- @noindex


local r = reaper
function print(...) local t = {...} for i = 1, select('#', ...) do t[i] = tostring(t[i]) end r.ShowConsoleMsg(table.concat(t, '\t') .. '\n') end
package.path = package.path .. ";" .. string.match(({r.get_action_context()})[2], "(.-)([^\\/]-%.?([^%.\\/]*))$") .. "?.lua"
require "json"
require "rtk"
r.gmem_attach('Viewer')
local f = require "functions"
local q = rtk.quit
local x, y = r.GetMousePosition()
local wnd = rtk.Window{
    opacity = 0.975,
    resizable = false,
    border = '#5a5a5a',
    borderless = true,
    title = 'Track View Saver',
    w = 240,
    h = 170,
    x = x - 14,
    y = y - 16,
}
local fills = {fillw = true, fillh = true}
local container = wnd:add(rtk.VBox{}, fills)
f.createHeader(container)

local inputContainer = container:add(rtk.Container{autofocus=true})
local header = inputContainer:add(rtk.Heading{wrap=true, '', cell=fills, halign='center', fontsize=100})

local function setHeaderText(text, fontSize, valign)
    header:attr('text', text)
    header:attr('fontsize', fontSize or 100)
    header:attr('valign', valign or 'top')
end

local function performSave(value, isOverwrite)
    local data = f.loadSlotData(value)

    f.saveVisibleTracks(value)
    
    if isOverwrite then
        if data then
          f.saveSlotData(value, data.name, data and data.hideAllTracks or false)
          
        else
          f.saveSlotData(value)
        end
        inputContainer.onkeypress = function(self, event)
            if event.keycode == rtk.keycodes.ENTER then
                q()
            end
        end
    else
        f.saveSlotData(value, f.formatDate(), true)
    end
    
    local currentValue = r.gmem_read(0)
    local newValue = currentValue == 0 and 1 or 0
    r.gmem_write(0, newValue)
    setHeaderText("Success", 35, 'center')
    f.closeAfterDelay(0.3)
end

local function handleSaveAction(value)
    local retval, _ = r.GetProjExtState(0, "VisibleTracksSnapshot", "data_" .. value)

    if retval ~= 0 then
        setHeaderText("Overwrite existing?", 35, 'center')
        inputContainer.onkeypress = function(self, event)
            if event.keycode == rtk.keycodes.ENTER then
                performSave(value, true)
            elseif event.keycode == rtk.keycodes.ESCAPE then
                q()
            end
        end
    else
        performSave(value, false)
    end
end

inputContainer.onkeypress = function(self, event)
    local char = event.char
    if event.keycode == rtk.keycodes.BACKSPACE then
        header:attr('text', header.text:sub(1, -2))
    elseif event.keycode == rtk.keycodes.ENTER then
        local value = tonumber(header.text)
        if value then
            if value < 0 or value > 25 then
                setHeaderText("Value exceeds range", 35, 'center')
                f.closeAfterDelay(0.65)
            else
                handleSaveAction(value)
            end
        end
    elseif f.isInteger(char) then
        header:attr('text', header.text .. char)
    elseif event.keycode == rtk.keycodes.ESCAPE then
        q()
    end
    return true
end

wnd.onupdate = function()
    inputContainer:focus()
end

wnd.onfocus = function()
    return true
end

wnd.onblur = function()
    f.closeAfterDelay(0.5)
end

wnd:open()
