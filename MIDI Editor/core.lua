
--@noindex
--NoIndex: true

local tk = {

    touchscroll = false,

    smoothscroll = true,

    touch_activate_delay = 0.1,

    long_press_delay = 0.5,
    double_click_delay = 0.5,
    tooltip_delay = 0.5,
    light_luma_threshold = 0.6,
    debug = false,
    window = nil,
    has_js_reascript_api = (reaper.JS_Window_GetFocus ~= nil),
    has_sws_extension = (reaper.BR_Win32_GetMonitorRectFromRect ~= nil),
    script_path = nil,
    reaper_hwnd = nil,
    tick = 0,
    fps = 30,
    focused_hwnd = nil,
    focused = nil,

    theme = nil,

    _dest_stack = {},
    _image_paths = {},
    _animations = {},
    _animations_len = 0,
    _easing_functions = {},
    _frame_count = 0,
    _frame_time = nil,
    _modal = nil,
    _touch_activate_event = nil,
    _last_traceback = nil,
    _last_error = nil,
    _quit = false,
    _refs = setmetatable({}, {__mode='v'}),
    _run_soon = nil,
    _reactive_attr = {},
}


tk.scale = setmetatable({
    user = nil,
    _user = 1.0,
    system = nil,
    reaper = 1.0,
    framebuffer = nil,
    value = 1.0,

    _discover = function()
        local inifile = reaper.get_ini_file()
        local ini, err = tk.file.read(inifile)
        if not err then
            tk.scale.reaper = ini:match('uiscale=([^\n]*)') or 1.0
        end
        local ok, dpi = reaper.ThemeLayout_GetLayout("mcp", -3)
        if not ok then
            return
        end
        dpi = math.ceil(tonumber(dpi) / tk.scale.reaper)
        tk.scale.system = dpi / 256.0
        if not tk.scale.framebuffer then
            if tk.os.mac and dpi == 512 then
                tk.scale.framebuffer = 2
            else
                tk.scale.framebuffer = 1
            end
        end
        tk.scale._calc()
    end,
    _calc = function()
        local value = tk.scale.user * tk.scale.system * tk.scale.reaper
        tk.scale.value = math.ceil(value * 100) / 100.0
    end,
}, {
    __index=function(t, key)
        return key == 'user' and t._user or nil
    end,
    __newindex=function(t, key, value)
        if key == 'user' then
            if value ~= t._user then
                t._user = value
                tk.scale._calc()
                if tk.window then
                    tk.window:queue_reflow()
                end
            end
        else
            rawset(t, key, value)
        end
    end
})

tk.dnd = {
    dragging = nil,
    droppable = nil,
    dropping = nil,
    arg = nil,
    buttons = nil,
}

local _os = reaper.GetOS():lower():sub(1, 3)
tk.os = {
    mac = (_os == 'osx' or _os == 'mac'),
    windows = (_os == 'win'),
    linux = (_os == 'lin' or _os == 'oth'),
    bits = 32,
}

tk.mouse = {
    BUTTON_LEFT = 1,
    BUTTON_MIDDLE = 64,
    BUTTON_RIGHT = 2,
    BUTTON_MASK = (1 | 2 | 64),
    x = 0,
    y = 0,
    down = 0,
    state = {order={}, latest=nil},
    last = {},
}

local _load_cursor
if tk.has_js_reascript_api then
    function _load_cursor(cursor)
        return reaper.JS_Mouse_LoadCursor(cursor)
    end
else
    function _load_cursor(cursor)
        return cursor
    end
end

tk.mouse.cursors = {
    UNDEFINED = 0,
    POINTER = _load_cursor(32512),
    BEAM = _load_cursor(32513),
    LOADING = _load_cursor(32514),
    CROSSHAIR = _load_cursor(32515),
    UP_ARROW = _load_cursor(32516),
    SIZE_NW_SE = _load_cursor(tk.os.linux and 32643 or 32642),
    SIZE_SW_NE = _load_cursor(tk.os.linux and 32642 or 32643),
    SIZE_EW = _load_cursor(32644),
    SIZE_NS = _load_cursor(32645),
    MOVE = _load_cursor(32646),
    INVALID = _load_cursor(32648),
    HAND = _load_cursor(32649),
    POINTER_LOADING = _load_cursor(32650),
    POINTER_HELP = _load_cursor(32651),
    REAPER_FADEIN_CURVE = _load_cursor(105),
    REAPER_FADEOUT_CURVE = _load_cursor(184),
    REAPER_CROSSFADE = _load_cursor(463),
    REAPER_DRAGDROP_COPY = _load_cursor(182),
    REAPER_DRAGDROP_RIGHT = _load_cursor(1011),
    REAPER_POINTER_ROUTING = _load_cursor(186),
    REAPER_POINTER_MOVE = _load_cursor(187),
    REAPER_POINTER_MARQUEE_SELECT = _load_cursor(488),
    REAPER_POINTER_DELETE = _load_cursor(464),
    REAPER_POINTER_LEFTRIGHT = _load_cursor(465),
    REAPER_POINTER_ARMED_ACTION = _load_cursor(434),
    REAPER_MARKER_HORIZ = _load_cursor(188),
    REAPER_MARKER_VERT = _load_cursor(189),
    REAPER_ADD_TAKE_MARKER = _load_cursor(190),
    REAPER_TREBLE_CLEF = _load_cursor(191),
    REAPER_BORDER_LEFT = _load_cursor(417),
    REAPER_BORDER_RIGHT = _load_cursor(418),
    REAPER_BORDER_TOP = _load_cursor(419),
    REAPER_BORDER_BOTTOM = _load_cursor(421),
    REAPER_BORDER_LEFTRIGHT = _load_cursor(450),
    REAPER_VERTICAL_LEFTRIGHT = _load_cursor(462),
    REAPER_GRID_RIGHT = _load_cursor(460),
    REAPER_GRID_LEFT = _load_cursor(461),
    REAPER_HAND_SCROLL = _load_cursor(429),
    REAPER_FIST_LEFT = _load_cursor(430),
    REAPER_FIST_RIGHT = _load_cursor(431),
    REAPER_FIST_BOTH = _load_cursor(453),
    REAPER_PENCIL = _load_cursor(185),
    REAPER_PENCIL_DRAW = _load_cursor(433),
    REAPER_ERASER = _load_cursor(472),
    REAPER_BRUSH = _load_cursor(473),
    REAPER_ARP = _load_cursor(502),
    REAPER_CHORD = _load_cursor(503),
    REAPER_TOUCHSEL = _load_cursor(515),
    REAPER_SWEEP = _load_cursor(517),
    REAPER_FADEIN_CURVE_ALT = _load_cursor(525),
    REAPER_FADEOUT_CURVE_ALT = _load_cursor(526),
    REAPER_XFADE_WIDTH = _load_cursor(528),
    REAPER_XFADE_CURVE = _load_cursor(529),
    REAPER_EXTMIX_SECTION_RESIZE = _load_cursor(530),
    REAPER_EXTMIX_MULTI_RESIZE = _load_cursor(531),
    REAPER_EXTMIX_MULTISECTION_RESIZE = _load_cursor(532),
    REAPER_EXTMIX_RESIZE = _load_cursor(533),
    REAPER_EXTMIX_ALLSECTION_RESIZE = _load_cursor(534),
    REAPER_EXTMIX_ALL_RESIZE = _load_cursor(535),
    REAPER_ZOOM = _load_cursor(1009),
    REAPER_INSERT_ROW = _load_cursor(1010),

    REAPER_RAZOR = _load_cursor(599),
    REAPER_RAZOR_MOVE = _load_cursor(600),
    REAPER_RAZOR_ADD = _load_cursor(601),
    REAPER_RAZOR_ENVELOPE_VERTICAL = _load_cursor(202),
    REAPER_RAZOR_ENVELOPE_RIGHT_TILT = _load_cursor(203),
    REAPER_RAZOR_ENVELOPE_LEFT_TILT = _load_cursor(204),
}


local FONT_FLAG_BOLD = string.byte('b')
local FONT_FLAG_ITALICS = string.byte('i') << 8
local FONT_FLAG_UNDERLINE = string.byte('u') << 16

tk.font = {
    BOLD = FONT_FLAG_BOLD,
    ITALICS = FONT_FLAG_ITALICS,
    UNDERLINE = FONT_FLAG_UNDERLINE,
    multiplier = 1.0
}


tk.keycodes = {
    UP = 30064,
    DOWN = 1685026670,
    LEFT = 1818584692,
    RIGHT = 1919379572,
    RETURN = 13,
    ENTER = 13,
    SPACE = 32,
    BACKSPACE = 8,
    ESCAPE = 27,
    TAB = 9,
    HOME = 1752132965,
    END = 6647396,
    INSERT = 6909555,
    DELETE = 6579564,
    F1 = 26161,
    F2 = 26162,
    F3 = 26163,
    F4 = 26164,
    F5 = 26165,
    F6 = 26166,
    F7 = 26167,
    F8 = 26168,
    F9 = 26169,
    F10 = 6697264,
    F11 = 6697265,
    F12 = 6697266,
}

tk.themes = {
    dark = {
        name = 'dark',
        dark = true,
        light = false,
        bg = '#252525',
        default_font = {'Calibri', 18},

        accent = '#47abff',
        accent_subtle = '#306088',

        tooltip_bg = '#ffffff',
        tooltip_text = '#000000',
        tooltip_font = {'Segoe UI (TrueType)', 16},

        text = '#ffffff',
        text_faded = '#bbbbbb',
        text_font = nil,

        button = '#555555',
        heading = nil,
        heading_font = {'Calibri', 26},
        button_label = '#ffffff',
        button_font = nil,
        button_gradient_mul = 1,
        button_tag_alpha = 0.32,
        button_normal_gradient = -0.37,
        button_normal_border_mul = 0.7,
        button_hover_gradient = 0.17,
        button_hover_brightness = 0.9,
        button_hover_mul = 1,
        button_hover_border_mul = 1.1,
        button_clicked_gradient = 0.47,
        button_clicked_brightness = 0.9,
        button_clicked_mul = 0.85,
        button_clicked_border_mul = 1,

        entry_font = nil,
        entry_bg = '#5f5f5f7f',
        entry_placeholder = '#ffffff7f',
        entry_border_hover = '#3a508e',
        entry_border_focused = '#4960b8',
        entry_selection_bg = '#0066bb',

        popup_bg = nil,
        popup_overlay = '#00000040',
        popup_bg_brightness = 1.3,
        popup_shadow = '#11111166',
        popup_border = '#385074',

        slider = '#2196f3',
        slider_track = '#5a5a5a',
        slider_font = nil,
        slider_tick_label = nil,
    },
    light = {
        name = 'light',
        light = true,
        dark = false,
        accent = '#47abff',
        accent_subtle = '#a1d3fc',
        bg = '#dddddd',
        default_font = {'Calibri', 18},
        tooltip_font = {'Segoe UI (TrueType)', 16},
        tooltip_bg = '#ffffff',
        tooltip_text = '#000000',
        button = '#dedede',
        button_label = '#000000',
        button_gradient_mul = 1,
        button_tag_alpha = 0.15,
        button_normal_gradient = -0.28,
        button_normal_border_mul = 0.85,
        button_hover_gradient = 0.12,
        button_hover_brightness = 1,
        button_hover_mul = 1,
        button_hover_border_mul = 0.9,
        button_clicked_gradient = 0.3,
        button_clicked_brightness = 1.0,
        button_clicked_mul = 0.9,
        button_clicked_border_mul = 0.7,
        text = '#000000',
        text_faded = '#555555',
        heading_font = {'Calibri', 26},
        entry_border_hover = '#3a508e',
        entry_border_focused = '#4960b8',
        entry_bg = '#00000020',
        entry_placeholder = '#0000007f',
        entry_selection_bg = '#9fcef4',
        popup_bg = nil,
        popup_bg_brightness = 1.5,
        popup_shadow = '#11111122',
        popup_border = '#385074',
        slider = '#2196f3',
        slider_track = '#5a5a5a',
    }
}

local function _postprocess_theme()
    local iconstyle = tk.color.get_icon_style(tk.theme.bg)
    tk.theme.iconstyle = iconstyle
    for k, v in pairs(tk.theme) do
        if type(v) == 'string' and v:byte(1) == 35 then
            tk.theme[k] = {tk.color.rgba(v)}
        end
    end
end

function tk.add_image_search_path(path, iconstyle)
    path = path:gsub('[/\\]$', '') .. '/'
    if not path:match('^%a:') and not path:match('^[\\/]') then
        path = tk.script_path .. path
    end
    if iconstyle then
        assert(iconstyle == 'dark' or iconstyle == 'light', 'iconstyle must be either light or dark')
    else
        iconstyle = 'nostyle'
    end
    local paths = tk._image_paths[iconstyle]
    if not paths then
        paths = {}
        tk._image_paths[iconstyle] = paths
    end
    paths[#paths+1] = path
end

function tk.set_theme(name, overrides)
    name = name or tk.theme.name
    assert(tk.themes[name], 'tk: theme "' .. name .. '" does not exist in tk.themes')
    tk.theme = {}
    table.merge(tk.theme, tk.themes[name])
    if overrides then
        table.merge(tk.theme, overrides)
    end
    _postprocess_theme()
end

function tk.set_theme_by_bgcolor(color, overrides)
    local name = tk.color.luma(color) > tk.light_luma_threshold and 'light' or 'dark'
    overrides = overrides or {}
    overrides.bg = color
    tk.set_theme(name, overrides)
end

function tk.set_theme_overrides(overrides)
    for _, name in ipairs({'dark', 'light'}) do
        if overrides[name] then
            tk.themes[name] = table.merge(tk.themes[name], overrides[name])
            if tk.theme[name] then
                tk.theme = table.merge(tk.theme, overrides[name])
            end
            overrides[name] = nil
        end
    end
    tk.themes.dark = table.merge(tk.themes.dark, overrides)
    tk.themes.light = table.merge(tk.themes.light, overrides)
    tk.theme = table.merge(tk.theme, overrides)
    _postprocess_theme()
end

function tk.new_theme(name, base, overrides)
    assert(not base or tk.themes[base], string.format('base theme %s not found', base))
    assert(not tk.themes[name], string.format('theme %s already exists', name))
    local theme = base and table.shallow_copy(tk.themes[base]) or {}
    tk.themes[name] = table.merge(theme, overrides or {})
end


function tk.add_modal(...)
    if tk._modal == nil then
        tk._modal = {}
    end
    local state = tk.mouse.state[tk.mouse.state.latest]
    if state then
        state.modaltick = tk.tick
    end
    local widgets = {...}
    for _, widget in ipairs(widgets) do
        tk._modal[widget.id] = {widget, tk.tick}
    end
end

function tk.is_modal(widget)
    if widget == nil then
        return tk._modal ~= nil
    elseif tk._modal then
        local w = widget
        while w do
            if tk._modal[w.id] ~= nil then
                return true
            end
            w = w.parent
        end
    end
    return false
end

function tk.reset_modal()
    tk._modal = nil
end

function tk.pushdest(dest)
    tk._dest_stack[#tk._dest_stack + 1] = gfx.dest
    gfx.dest = dest
end

function tk.popdest()
    gfx.dest = table.remove(tk._dest_stack, #tk._dest_stack)
end

local function _handle_error(err)
    tk._last_error = err
    tk._last_traceback = debug.traceback()
end

function tk.call(func, ...)
    if tk._quit then
        return
    end
    local ok, result = xpcall(func, _handle_error, ...)
    if not ok then
        --tk.onerror(tk._last_error, tk._last_traceback)
        return
    end
    return result
end

function tk.defer(func, ...)
    if tk._quit then
        return
    end
    local args = table.pack(...)
    reaper.defer(function()
        tk.call(func, table.unpack(args, 1, args.n))
    end)
end

function tk.callsoon(func, ...)
    if not tk.window or not tk.window.running then
        return tk.defer(func, ...)
    end
    local funcs = tk._soon_funcs
    if not funcs then
        funcs = {}
        tk._soon_funcs = funcs
    end
    funcs[#funcs+1] = {func, table.pack(...)}
end

function tk._run_soon()
    local funcs = tk._soon_funcs
    tk._soon_funcs = nil
    for i = 1, #funcs do
        local func, args = table.unpack(funcs[i])
        func(table.unpack(args, 1, args.n))
    end

end

function tk.callafter(duration, func, ...)
    local args = table.pack(...)
    local start = reaper.time_precise()
    local function sched()
        if reaper.time_precise() - start >= duration then
            tk.call(func, table.unpack(args, 1, args.n))
        elseif not tk._quit then
            reaper.defer(sched)
        end
    end
    sched()
end

function tk.quit()
    if tk.ctx then 
        
    end
    if tk.window and tk.window.running then
        tk.window:close()
    end
    tk._quit = true
end

return tk