-- @description Window
-- @author mrtnz
-- @noindex  

local via = {}
local r=reaper
local script_path = (select(2, reaper.get_action_context())):match('^(.*[/\\])')
local functions_path = script_path .. "../libs/Functions.lua"
local func = dofile(functions_path)


local _, _, section_id = r.get_action_context()
function via.print(msg) r.ShowConsoleMsg(tostring(msg) .. '\n') end
via.my_shortcuts = {}

via.my_shortcuts['Ctrl+Shift+X'] = function() print('Another one!') end
via.my_shortcuts['Ctrl+Shift+C'] = function() print('And another one!') end
via.special_chars = {}
via.special_chars[8] = 'Backspace'
via.special_chars[9] = 'Tab'
via.special_chars[13] = 'Enter'
via.special_chars[27] = 'ESC'
via.special_chars[32] = 'Space'
via.special_chars[176] = '°'
via.special_chars[26161] = 'F1'
via.special_chars[26162] = 'F2'
via.special_chars[26163] = 'F3'
via.special_chars[26164] = 'F4'
via.special_chars[26165] = 'F5'
via.special_chars[26166] = 'F6'
via.special_chars[26167] = 'F7'
via.special_chars[26168] = 'F8'
via.special_chars[26169] = 'F9'
via.special_chars[6697264] = 'F10'
via.special_chars[6697265] = 'F11'
via.special_chars[6697266] = 'F12'
via.special_chars[65105] = '﹑'
via.special_chars[65106] = '﹒'
via.special_chars[6579564] = 'Delete'
via.special_chars[6909555] = 'Insert'
via.special_chars[1752132965] = 'Home'
via.special_chars[6647396] = 'End'
via.special_chars[1885828464] = 'Page Up'
via.special_chars[1885824110] = 'Page Down'
function via.ConvertCharToShortcut(char, is_ctrl, is_shift, is_alt)
    local key

    if not (is_ctrl and char <= 26) then key = via.special_chars[char] end

    if not key then
        if char >= 1 and char <= 26 then char = char + 64 end
        if char >= 257 and char <= 282 then char = char - 192 end
        key = string.char(char & 0xFF):upper()
    end

    if is_shift and key ~= key:lower() then key = 'Shift+' .. key end
    if is_alt then key = 'Alt+' .. key end
    if is_ctrl then key = 'Ctrl+' .. key end

    return key
end

function via.GetCommandByShortcut(section_id, shortcut)
    local version = tonumber(r.GetAppVersion():match('[%d.]+'))
    if version < 6.71 then return end
    local is_macos = r.GetOS():match('OS')
    if is_macos then
        shortcut = shortcut:gsub('Ctrl%+', 'Cmd+', 1)
        shortcut = shortcut:gsub('Alt%+', 'Opt+', 1)
    end
    local sec = r.SectionFromUniqueID(section_id)
    local i = 0
    repeat
        local cmd = r.kbd_enumerateActions(sec, i)
        if cmd ~= 0 then
            for n = 0, r.CountActionShortcuts(sec, cmd) - 1 do
                local _, desc = r.GetActionShortcutDesc(sec, cmd, n, '')
                if desc == shortcut then return cmd, n end
            end
        end
        i = i + 1
    until cmd == 0
end





function via.onkeypressHandler(via, func, context)
    return function(self, event)
        local is_ctrl = event.ctrl
        local is_shift = event.shift
        local is_alt = event.alt
        local shortcut = via.ConvertCharToShortcut(event.keycode, is_ctrl, is_shift, is_alt)
        
        if shortcut == 'Ctrl+Alt+C' then
            func.msg('My custom script shortcut!')
        elseif via.my_shortcuts[shortcut] then
            via.my_shortcuts[shortcut]()
        else
            if context == "main" then
                local cmd = via.GetCommandByShortcut(0, shortcut)
                if cmd then 
                    reaper.Main_OnCommand(cmd, 0)
                end
            elseif context == "midi" then
                local midi_editor = reaper.MIDIEditor_GetActive()
                if midi_editor then
                    local cmd = via.GetCommandByShortcut(32060, shortcut) -- 32060 is the section ID for the MIDI editor
                    if cmd then 
                        reaper.MIDIEditor_OnCommand(midi_editor, cmd)
                    end
                end
            end
        end
        return true
    end
end






return via