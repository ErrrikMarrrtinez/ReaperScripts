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

-- State to track whether we're inputting slot number or custom name
local isInputtingName = false
local slotNumber = nil
local customName = ""

local function setHeaderText(text, fontSize, valign)
    header:attr('text', text)
    header:attr('fontsize', fontSize or 100)
    header:attr('valign', valign or 'top')
end

local function performSave(value, isOverwrite, customName)
    local data = f.loadSlotData(value)
    f.saveVisibleTracks(value)
    
    if isOverwrite then
        if data then
            f.saveSlotData(value, customName or data.name, data and data.hideAllTracks or false)
        else
            f.saveSlotData(value, customName)
        end
        inputContainer.onkeypress = function(self, event)
            if event.keycode == rtk.keycodes.ENTER then
                q()
            end
        end
    else
        f.saveSlotData(value, customName or f.formatDate(), true)
    end
    
    local currentValue = r.gmem_read(0)
    local newValue = currentValue == 0 and 1 or 0
    r.gmem_write(0, newValue)
    setHeaderText("Success", 35, 'center')
    f.closeAfterDelay(0.3)
end

local function handleSaveAction(value, customName)
    local retval, _ = r.GetProjExtState(0, "VisibleTracksSnapshot", "data*" .. value)
    if retval ~= 0 then
        setHeaderText("Overwrite existing?", 35, 'center')
        inputContainer.onkeypress = function(self, event)
            if event.keycode == rtk.keycodes.ENTER then
                performSave(value, true, customName)
            elseif event.keycode == rtk.keycodes.ESCAPE then
                q()
            end
        end
    else
        performSave(value, false, customName)
    end
end

inputContainer.onkeypress = function(self, event)
    if event.keycode == rtk.keycodes.ESCAPE then
        q()
        return true
    end

    if not isInputtingName then
        -- Mode: Inputting slot number
        if event.keycode == rtk.keycodes.BACKSPACE then
            header:attr('text', header.text:sub(1, -2))
            return true
        elseif event.keycode == rtk.keycodes.SPACE then
            -- Switch to name input mode if we have a valid number
            local value = tonumber(header.text)
            if value and value >= 0 and value <= 1025 then
                slotNumber = value
                isInputtingName = true
                customName = ""
                setHeaderText(tostring(value) .. " ", 35, 'center')
                return true
            end
        elseif event.keycode == rtk.keycodes.ENTER then
            -- Handle number-only input (using date as name)
            local value = tonumber(header.text)
            if value then
                if value < 0 or value > 1025 then
                    setHeaderText("Value exceeds range", 35, 'center')
                    f.closeAfterDelay(0.65)
                else
                    handleSaveAction(value)
                end
            end
        elseif f.isInteger(event.char) then
            header:attr('text', header.text .. event.char)
        end
    else
        -- Mode: Inputting custom name
        if event.keycode == rtk.keycodes.BACKSPACE then
            if #customName > 0 then
                customName = customName:sub(1, -2)
                header:attr('text', tostring(slotNumber) .. " " .. customName)
            end
        elseif event.keycode == rtk.keycodes.ENTER and slotNumber then
            -- Save with custom name
            handleSaveAction(slotNumber, customName ~= "" and customName or nil)
        elseif event.char then
            customName = customName .. event.char
            header:attr('text', tostring(slotNumber) .. " " .. customName)
        end
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