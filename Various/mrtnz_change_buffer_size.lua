-- @description Change yamaha buffer size (windows)
-- @author mrtnz
-- @version 1.00
-- @about
--  Change Yamaha Steinberg USB Driver buffer size via context menu

MENU_OPTIONS = {"2048","1536","1024","768","512","384","256","192","128","96","64","48","32"}

function get_buffers()
    local rv, buffer_size = reaper.GetAudioDeviceInfo("BSIZE")
    return rv and tostring(buffer_size) or nil
end

function show_context_menu()
    local current_size = get_buffers()
    local menu_items = {}
    for i, size in ipairs(MENU_OPTIONS) do
        menu_items[i] = (current_size == size and "!" or "") .. size
    end
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local choice = gfx.showmenu(table.concat(menu_items, "|"))
    return choice > 0 and MENU_OPTIONS[choice] or nil
end

function set_buffer_size(size)
    local command = string.format(
    'powershell -WindowStyle Hidden -Command "Set-ItemProperty -Path HKCU:\\Software\\Yamaha\\\'Yamaha Steinberg USB Driver\' -Name PeriodFrames -Value %d -Type DWord"',
      tonumber(size)
    )
    reaper.ExecProcess(command, 0)
end

function main()
    reaper.Main_OnCommand(1016, 0) -- stop
    
    local target_size = show_context_menu()
    if not target_size then return end
    
    local current_size = get_buffers()
    if current_size == target_size then return end
    set_buffer_size(target_size)

    reaper.Audio_Quit() 
    reaper.Audio_Init()
end

main()