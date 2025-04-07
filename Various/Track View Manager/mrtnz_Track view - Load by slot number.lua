-- @noindex


local r = reaper
function print(...) local t = {...} for i = 1, select('#', ...) do t[i] = tostring(t[i]) end r.ShowConsoleMsg(table.concat(t, '\t') .. '\n') end
package.path = package.path .. ";" .. string.match(({r.get_action_context()})[2], "(.-)([^\\/]-%.?([^%.\\/]*))$") .. "?.lua"
require "json"
require "rtk"
local f = require "functions"
local q = rtk.quit

local x, y = r.GetMousePosition()
local wnd = rtk.Window{
    opacity = 0.975,
    resizable = false,
    border = '#5a5a5a',
    borderless = true,
    title = 'Track View Loader',
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

local lastBackspaceTime = 0
local backspaceCount = 0

local function processInput(input)
    local selected_slots = {}
    for value in input:gmatch("[^,%.]+") do
        value = value:match("^%s*(.-)%s*$") -- Trim whitespace
        if value:find("-") then
            local start, stop = value:match("(%d+)-(%d+)")
            start, stop = tonumber(start), tonumber(stop)
            if start and stop then
                for i = start, stop do
                    selected_slots[i] = true
                end
            end
        else
            local num = tonumber(value)
            if num then
                selected_slots[num] = true
            end
        end
    end
    return selected_slots
end

inputContainer.onkeypress = function(self, event)
    local char = event.char
    local currentTime = r.time_precise()
    if event.keycode == rtk.keycodes.BACKSPACE then
        if header.text == "" then
            if currentTime - lastBackspaceTime < 0.3 then
                backspaceCount = backspaceCount + 1
                if backspaceCount == 2 then
                    f.setAllVisibleTracks()
                    rtk.callafter(0.3, q)
                    return true
                end
            else
                backspaceCount = 1
            end
            lastBackspaceTime = currentTime
        else
            header:attr('text', header.text:sub(1, -2))
        end
    elseif event.keycode == rtk.keycodes.ENTER then
        local input = header.text
        if input:find("[,%.%-]") then
            local selected_slots = processInput(input)
            if next(selected_slots) then
                header:attr('fontsize', 35)
                header:attr('valign', 'center')
                header:attr('text', "Loading...")
                
                f.main_loader(selected_slots)
                rtk.callafter(0.19, q) -- Даем время на выполнение скроллинга
            else
                header:attr('fontsize', 35)
                header:attr('valign', 'center')
                header:attr('text', "Invalid input")
                rtk.callafter(0.22, q)
            end
        else
            local value = tonumber(input)
            if value then
                header:attr('fontsize', 35)
                header:attr('valign', 'center')
                header:attr('text', "Loading...")
                
                local er = f.restoreVisibleTracksSnapshot(value)
                if er ~= nil then
                    header:attr('fontsize', 35)
                    header:attr('valign', 'center')
                    header:attr('text', er)
                    inputContainer.onkeypress = function(self, event)
                        if event.keycode == rtk.keycodes.ENTER then
                            q()
                        end
                    end
                    rtk.callafter(0.15, q)
                else
                    rtk.callafter(0.19, q) -- Даем время на выполнение скроллинга
                end
            end
        end
    elseif f.isInteger(char) or char == ',' or char == '.' or char == '-' then
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
    rtk.callafter(0.3, q)
end

wnd:open()
