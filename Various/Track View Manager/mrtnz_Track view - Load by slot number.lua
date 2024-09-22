-- @noindex


local r = reaper ; function print(...) local t = {...} for i = 1, select('#', ...) do t[i] = tostring(t[i]) end r.ShowConsoleMsg(table.concat(t, '\t') .. '\n') end


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

inputContainer.onkeypress = function(self, event) 
    local char = event.char
    if event.keycode == rtk.keycodes.BACKSPACE then
        header:attr('text', header.text:sub(1, -2))
    elseif event.keycode == rtk.keycodes.ENTER then
        local value = tonumber(header.text)
        if value then
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
                rtk.callafter(0.9, q)
            else
                q()
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

wnd.onfocus=function()
    return true
end

wnd.onblur=function()
    rtk.callafter(0.3, q)
end

wnd:open()
