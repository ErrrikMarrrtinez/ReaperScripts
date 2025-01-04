--@noindex
--NoIndex: true

local Gui = require 'imgui' '0.9.2'
local tk = require 'other'
local r = reaper

tk.color = {}

function tk.clamp(value, min, max)
    if min and max then
        return math.max(min, math.min(max, value))
    elseif min then
        return math.max(min, value)
    elseif max then
        return math.min(max, value)
    else
        return value
    end
end

function tk.call(func, ...)
    if tk._quit then
        return
    end
    local ok, result = xpcall(func, _handle_error, ...)
    if not ok then
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

function tk.color.set(color, amul)
    local r, g, b, a = tk.color.rgba(color)
    if amul then
        a = a * amul
    end
    gfx.set(r, g, b, a)
end

function tk.color.rgba(color)
    local tp = type(color)
    if tp == 'table' then
        local r, g, b, a = table.unpack(color)
        return r, g, b, a or 1
    elseif tp == 'string' then
        local hash = color:find('#')
        if hash == 1 then
            return tk.color.hex2rgba(color)
        else
            local a
            if hash then
                a = (tonumber(color:sub(hash + 1), 16) or 0) / 255
                color = color:sub(1, hash - 1)
            end
            local resolved = tk.color.names[color:lower()]
            if not resolved then
                return 0, 0, 0, a or 1
            end
            local r, g, b, a2 = tk.color.hex2rgba(resolved)
            return r, g, b, a or a2
        end
    elseif tp == 'number' then
        local r, g, b = color & 0xff, (color >> 8) & 0xff, (color >> 16) & 0xff
        return r/255, g/255, b/255, 1
    else
        error('invalid type ' .. tp .. ' passed to tk.color.rgba()')
    end
end

function tk.color.luma(color, under)
    if not color then
        return under and tk.color.luma(under) or 0
    end
    local r, g, b, a = tk.color.rgba(color)
    local luma = (0.2126 * r + 0.7152 * g + 0.0722 * b)
    if a < 1.0 then
        luma = math.abs((luma * a) + (under and (tk.color.luma(under) * (1-a)) or 0))
    end
    return luma
end

function tk.color.hsv(color)
    local r, g, b, a = tk.color.rgba(color)
    local h, s, v

    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local delta = max - min
    if delta == 0 then
        h = 0
    elseif max == r then
        h = 60 * (((g - b) / delta) % 6)
    elseif max == g then
        h = 60 * (((b - r) / delta) + 2)
    elseif max == b then
        h = 60 * (((r - g) / delta) + 4)
    end
    s = (max == 0) and 0 or (delta / max)
    v = max
    return h/360.0, s, v, a
end

function tk.color.hsl(color)
    local r, g, b, a = tk.color.rgba(color)
    local h, s, l

    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    l = (max + min) / 2
    if max == min then
        h = 0
        s = 0
    else
        local delta = max - min
        if l > 0.5 then
            s = delta / (2 - max - min)
        else
            s = delta / (max + min)
        end
        if max == r then
            h = (g - b) / delta + (g < b and 6 or 0)
        elseif max == g then
            h = (b - r) / delta + 2
        else
            h = (r - g) / delta + 4
        end
        h = h / 6
    end
    return h, s, l, a
end

function tk.color.int(color, native)
    local r, g, b, _ = tk.color.rgba(color)
    local n = (r * 255) + ((g * 255) << 8) + ((b * 255) << 16)
    return native and tk.color.convert_native(n) or n
end

function tk.color.mod(color, hmul, smul, vmul, amul)
    local h, s, v, a = tk.color.hsv(color)
    return tk.color.hsv2rgb(
        tk.clamp(h * (hmul or 1), 0, 1),
        tk.clamp(s * (smul or 1), 0, 1),
        tk.clamp(v * (vmul or 1), 0, 1),
        tk.clamp(a * (amul or 1), 0, 1)
    )
end

function tk.color.convert_native(n)
    if tk.os.mac or tk.os.linux then
        return tk.color.flip_byte_order(n)
    else
        return n
    end
end

function tk.color.flip_byte_order(color)
    return ((color & 0xff) << 16) | (color & 0xff00) | ((color >> 16) & 0xff)
end

function tk.color.get_reaper_theme_bg()
    if reaper.GetThemeColor then
        local r = reaper.GetThemeColor('col_tracklistbg', 0)
        if r ~= -1 then
            return tk.color.int2hex(r)
        end
    end
    if reaper.GSC_mainwnd then
        local idx = (tk.os.mac or tk.os.linux) and 5 or 20
        return tk.color.int2hex(reaper.GSC_mainwnd(idx))
    end
end

function tk.color.get_icon_style(color, under)
    return tk.color.luma(color, under) > tk.light_luma_threshold and 'dark' or 'light'
end

function tk.color.hex2rgba(s)
    local r = tonumber(s:sub(2, 3), 16) or 0
    local g = tonumber(s:sub(4, 5), 16) or 0
    local b = tonumber(s:sub(6, 7), 16) or 0
    local a = tonumber(s:sub(8, 9), 16)
    return r / 255, g / 255, b / 255, a and a / 255 or 1.0
end

function tk.color.rgba2hex(r, g, b, a)
    r = math.ceil(r * 255)
    b = math.ceil(b * 255)
    g = math.ceil(g * 255)
    if not a or a == 1.0 then
        return string.format('#%02x%02x%02x', r, g, b)
    else
        return string.format('#%02x%02x%02x%02x', r, g, b, math.ceil(a * 255))
    end
end

function tk.color.int2hex(n, native)
    if native then
        n = tk.color.convert_native(n)
    end
    local r, g, b = n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff
    return string.format('#%02x%02x%02x', r, g, b)
end

function tk.color.hsv2rgb(h, s, v, a)
    if s == 0 then
        return v, v, v, a or 1.0
    end

    local i = math.floor(h * 6)
    local f = (h * 6) - i
    local p = v * (1 - s)
    local q = v * (1 - s*f)
    local t = v * (1 - s*(1-f))
    if i == 0 or i == 6 then
        return v, t, p, a or 1.0
    elseif i == 1 then
        return q, v, p, a or 1.0
    elseif i == 2 then
        return p, v, t, a or 1.0
    elseif i == 3 then
        return p, q, v, a or 1.0
    elseif i == 4 then
        return t, p, v, a or 1.0
    elseif i == 5 then
        return v, p, q, a or 1.0
    else
    end
end

local function hue2rgb(p, q, t)
    if t < 0 then
        t = t + 1
    elseif t > 1 then
        t = t - 1
    end
    if t < 1/6 then
        return p + (q - p) * 6 * t
    elseif t < 1/2 then
        return q
    elseif t < 2/3 then
        return p + (q - p) * (2/3 - t) * 6
    else
        return p
    end
end

function tk.color.hsl2rgb(h, s, l, a)
    local r, g, b
    if s == 0 then
        r, g, b = l, l, l
    else
        local q = (l < 0.5) and (l * (1 + s)) or (l+s - l*s)
        local p = 2 * l - q
        r = hue2rgb(p, q, h + 1/3)
        g = hue2rgb(p, q, h)
        b = hue2rgb(p, q, h - 1/3)
    end
    return r, g, b, a or 1.0
end

function tk.shift_color(color, hue, sat, val)
    local hue, sat, val = hue or 1, sat or 1, val or 1
    
    local h, s, l, a = tk.color.hsl(color)
    h = (h + hue) % 1
    s = tk.clamp(s * sat, 0, 1)
    l = tk.clamp(l * val, 0, 1)
    local r, g, b = tk.color.hsl2rgb(h, s, l)

    return  tk.color.rgba2hex(r, g, b, a)
end

tk.color.theme_names = {
    { k = 'col_main_bg2', v = 'Main window/transport background' },
    { k = 'col_main_text2', v = 'Main window/transport text' },
    { k = 'col_main_textshadow', v = 'Main window text shadow (ignored if too close to text color)' },
    { k = 'col_main_3dhl', v = 'Main window 3D highlight' },
    { k = 'col_main_3dsh', v = 'Main window 3D shadow' },
    { k = 'col_main_resize2', v = 'Main window pane resize mouseover' },
    { k = 'col_main_text', v = 'Themed window text' },
    { k = 'col_main_bg', v = 'Themed window background' },
    { k = 'col_main_editbk', v = 'Themed window edit background' },
    { k = 'col_nodarkmodemiscwnd', v = 'Do not use window theming on macOS dark mode' },
    { k = 'col_transport_editbk', v = 'Transport edit background' },
    { k = 'col_toolbar_text', v = 'Toolbar button text' },
    { k = 'col_toolbar_text_on', v = 'Toolbar button enabled text' },
    { k = 'col_toolbar_frame', v = 'Toolbar frame when floating or docked' },
    { k = 'toolbararmed_color', v = 'Toolbar button armed color' },
    { k = 'toolbararmed_drawmode', v = 'Toolbar button armed fill mode' },
    { k = 'io_text', v = 'I/O window text' },
    { k = 'io_3dhl', v = 'I/O window 3D highlight' },
    { k = 'io_3dsh', v = 'I/O window 3D shadow' },
    { k = 'genlist_bg', v = 'Window list background' },
    { k = 'genlist_fg', v = 'Window list text' },
    { k = 'genlist_grid', v = 'Window list grid lines' },
    { k = 'genlist_selbg', v = 'Window list selected row' },
    { k = 'genlist_selfg', v = 'Window list selected text' },
    { k = 'genlist_seliabg', v = 'Window list selected row (inactive)' },
    { k = 'genlist_seliafg', v = 'Window list selected text (inactive)' },
    { k = 'genlist_hilite', v = 'Window list highlighted text' },
    { k = 'genlist_hilite_sel', v = 'Window list highlighted selected text' },
    { k = 'col_buttonbg', v = 'Button background' },
    { k = 'col_tcp_text', v = 'Track panel text' },
    { k = 'col_tcp_textsel', v = 'Track panel (selected) text' },
    { k = 'col_seltrack', v = 'Selected track control panel background' },
    { k = 'col_seltrack2', v = 'Unselected track control panel background (enabled with a checkbox above)' },
    { k = 'tcplocked_color', v = 'Locked track control panel overlay color' },
    { k = 'tcplocked_drawmode', v = 'Locked track control panel fill mode' },
    { k = 'col_tracklistbg', v = 'Empty track list area' },
    { k = 'col_mixerbg', v = 'Empty mixer list area' },
    { k = 'col_arrangebg', v = 'Empty arrange view area' },
    { k = 'arrange_vgrid', v = 'Empty arrange view area vertical grid shading' },
    { k = 'col_fadearm', v = 'Fader background when automation recording' },
    { k = 'col_fadearm2', v = 'Fader background when automation playing' },
    { k = 'col_fadearm3', v = 'Fader background when in inactive touch/latch' },
    { k = 'col_tl_fg', v = 'Timeline foreground' },
    { k = 'col_tl_fg2', v = 'Timeline foreground (secondary markings)' },
    { k = 'col_tl_bg', v = 'Timeline background' },
    { k = 'col_tl_bgsel', v = 'Time selection color' },
    { k = 'timesel_drawmode', v = 'Time selection fill mode' },
    { k = 'col_tl_bgsel2', v = 'Timeline background (in loop points)' },
    { k = 'col_trans_bg', v = 'Transport status background' },
    { k = 'col_trans_fg', v = 'Transport status text' },
    { k = 'playrate_edited', v = 'Project play rate control when not 1.0' },
    { k = 'col_mi_label', v = 'Media item label' },
    { k = 'col_mi_label_sel', v = 'Media item label (selected)' },
    { k = 'col_mi_label_float', v = 'Floating media item label' },
    { k = 'col_mi_label_float_sel', v = 'Floating media item label (selected)' },
    { k = 'col_mi_bg', v = 'Media item background (odd tracks)' },
    { k = 'col_mi_bg2', v = 'Media item background (even tracks)' },
    { k = 'col_tr1_itembgsel', v = 'Media item background selected (odd tracks)' },
    { k = 'col_tr2_itembgsel', v = 'Media item background selected (even tracks)' },
    { k = 'itembg_drawmode', v = 'Media item background fill mode' },
    { k = 'col_tr1_peaks', v = 'Media item peaks (odd tracks)' },
    { k = 'col_tr2_peaks', v = 'Media item peaks (even tracks)' },
    { k = 'col_tr1_ps2', v = 'Media item peaks when selected (odd tracks)' },
    { k = 'col_tr2_ps2', v = 'Media item peaks when selected (even tracks)' },
    { k = 'col_peaksedge', v = 'Media item peaks edge highlight (odd tracks)' },
    { k = 'col_peaksedge2', v = 'Media item peaks edge highlight (even tracks)' },
    { k = 'col_peaksedgesel', v = 'Media item peaks edge highlight when selected (odd tracks)' },
    { k = 'col_peaksedgesel2', v = 'Media item peaks edge highlight when selected (even tracks)' },
    { k = 'cc_chase_drawmode', v = 'Media item MIDI CC peaks fill mode' },
    { k = 'col_peaksfade', v = 'Media item peaks when active in crossfade editor (fade-out)' },
    { k = 'col_peaksfade2', v = 'Media item peaks when active in crossfade editor (fade-in)' },
    { k = 'col_mi_fades', v = 'Media item fade/volume controls' },
    { k = 'fadezone_color', v = 'Media item fade quiet zone fill color' },
    { k = 'fadezone_drawmode', v = 'Media item fade quiet zone fill mode' },
    { k = 'fadearea_color', v = 'Media item fade full area fill color' },
    { k = 'fadearea_drawmode', v = 'Media item fade full area fill mode' },
    { k = 'col_mi_fade2', v = 'Media item edges of controls' },
    { k = 'col_mi_fade2_drawmode', v = 'Media item edges of controls blend mode' },
    { k = 'item_grouphl', v = 'Media item edge when selected via grouping' },
    { k = 'col_offlinetext', v = 'Media item "offline" text' },
    { k = 'col_stretchmarker', v = 'Media item stretch marker line' },
    { k = 'col_stretchmarker_h0', v = 'Media item stretch marker handle (1x)' },
    { k = 'col_stretchmarker_h1', v = 'Media item stretch marker handle (>1x)' },
    { k = 'col_stretchmarker_h2', v = 'Media item stretch marker handle (<1x)' },
    { k = 'col_stretchmarker_b', v = 'Media item stretch marker handle edge' },
    { k = 'col_stretchmarkerm', v = 'Media item stretch marker blend mode' },
    { k = 'col_stretchmarker_text', v = 'Media item stretch marker text' },
    { k = 'col_stretchmarker_tm', v = 'Media item transient guide handle' },
    { k = 'take_marker', v = 'Media item take marker' },
    { k = 'selitem_tag', v = 'Selected media item bar color' },
    { k = 'activetake_tag', v = 'Active media item take bar color' },
    { k = 'col_tr1_bg', v = 'Track background (odd tracks)' },
    { k = 'col_tr2_bg', v = 'Track background (even tracks)' },
    { k = 'selcol_tr1_bg', v = 'Selected track background (odd tracks)' },
    { k = 'selcol_tr2_bg', v = 'Selected track background (even tracks)' },
    { k = 'col_tr1_divline', v = 'Track divider line (odd tracks)' },
    { k = 'col_tr2_divline', v = 'Track divider line (even tracks)' },
    { k = 'col_envlane1_divline', v = 'Envelope lane divider line (odd tracks)' },
    { k = 'col_envlane2_divline', v = 'Envelope lane divider line (even tracks)' },
    { k = 'mute_overlay_col', v = 'Muted/unsoloed track/item overlay color' },
    { k = 'mute_overlay_mode', v = 'Muted/unsoloed track/item overlay mode' },
    { k = 'inactive_take_overlay_col', v = 'Inactive take overlay color' },
    { k = 'inactive_take_overlay_mode', v = 'Inactive take overlay mode' },
    { k = 'locked_overlay_col', v = 'Locked track/item overlay color' },
    { k = 'locked_overlay_mode', v = 'Locked track/item overlay mode' },
    { k = 'marquee_fill', v = 'Marquee fill' },
    { k = 'marquee_drawmode', v = 'Marquee fill mode' },
    { k = 'marquee_outline', v = 'Marquee outline' },
    { k = 'marqueezoom_fill', v = 'Marquee zoom fill' },
    { k = 'marqueezoom_drawmode', v = 'Marquee zoom fill mode' },
    { k = 'marqueezoom_outline', v = 'Marquee zoom outline' },
    { k = 'areasel_fill', v = 'Razor edit area fill' },
    { k = 'areasel_drawmode', v = 'Razor edit area fill mode' },
    { k = 'areasel_outline', v = 'Razor edit area outline' },
    { k = 'areasel_outlinemode', v = 'Razor edit area outline mode' },
    { k = 'col_cursor', v = 'Edit cursor' },
    { k = 'col_cursor2', v = 'Edit cursor (alternate)' },
    { k = 'playcursor_color', v = 'Play cursor' },
    { k = 'playcursor_drawmode', v = 'Play cursor fill mode' },
    { k = 'col_gridlines2', v = 'Grid lines (start of measure)' },
    { k = 'col_gridlines2dm', v = 'Grid lines (start of measure) - draw mode' },
    { k = 'col_gridlines3', v = 'Grid lines (start of beats)' },
    { k = 'col_gridlines3dm', v = 'Grid lines (start of beats) - draw mode' },
    { k = 'col_gridlines', v = 'Grid lines (in between beats)' },
    { k = 'col_gridlines1dm', v = 'Grid lines (in between beats) - draw mode' },
    { k = 'guideline_color', v = 'Editing guide line color' },
    { k = 'guideline_drawmode', v = 'Editing guide fill mode' },
    { k = 'region', v = 'Regions' },
    { k = 'region_lane_bg', v = 'Region lane background' },
    { k = 'region_lane_text', v = 'Region lane text' },
    { k = 'marker', v = 'Markers' },
    { k = 'marker_lane_bg', v = 'Marker lane background' },
    { k = 'marker_lane_text', v = 'Marker lane text' },
    { k = 'col_tsigmark', v = 'Time signature change marker' },
    { k = 'ts_lane_bg', v = 'Time signature lane background' },
    { k = 'ts_lane_text', v = 'Time signature lane text' },
    { k = 'timesig_sel_bg', v = 'Time signature marker selected background' },
    { k = 'col_routinghl1', v = 'Routing matrix row highlight' },
    { k = 'col_routinghl2', v = 'Routing matrix column highlight' },
    { k = 'col_vudoint', v = 'Theme has interlaced VU meters' },
    { k = 'col_vuclip', v = 'VU meter clip indicator' },
    { k = 'col_vutop', v = 'VU meter top' },
    { k = 'col_vumid', v = 'VU meter middle' },
    { k = 'col_vubot', v = 'VU meter bottom' },
    { k = 'col_vuintcol', v = 'VU meter interlace/edge color' },
    { k = 'col_vumidi', v = 'VU meter midi activity' },
    { k = 'col_vuind1', v = 'VU (indicator) - no signal' },
    { k = 'col_vuind2', v = 'VU (indicator) - low signal' },
    { k = 'col_vuind3', v = 'VU (indicator) - med signal' },
    { k = 'col_vuind4', v = 'VU (indicator) - hot signal' },
    { k = 'mcp_sends_normal', v = 'Sends text: normal' },
    { k = 'mcp_sends_muted', v = 'Sends text: muted' },
    { k = 'mcp_send_midihw', v = 'Sends text: MIDI hardware' },
    { k = 'mcp_sends_levels', v = 'Sends level' },
    { k = 'mcp_fx_normal', v = 'FX insert text: normal' },
    { k = 'mcp_fx_bypassed', v = 'FX insert text: bypassed' },
    { k = 'mcp_fx_offlined', v = 'FX insert text: offline' },
    { k = 'mcp_fxparm_normal', v = 'FX parameter text: normal' },
    { k = 'mcp_fxparm_bypassed', v = 'FX parameter text: bypassed' },
    { k = 'mcp_fxparm_offlined', v = 'FX parameter text: offline' },
    { k = 'tcp_list_scrollbar', v = 'List scrollbar (track panel)' },
    { k = 'tcp_list_scrollbar_mode', v = 'List scrollbar (track panel) - draw mode' },
    { k = 'tcp_list_scrollbar_mouseover', v = 'List scrollbar mouseover (track panel)' },
    { k = 'tcp_list_scrollbar_mouseover_mode', v = 'List scrollbar mouseover (track panel) - draw mode' },
    { k = 'mcp_list_scrollbar', v = 'List scrollbar (mixer panel)' },
    { k = 'mcp_list_scrollbar_mode', v = 'List scrollbar (mixer panel) - draw mode' },
    { k = 'mcp_list_scrollbar_mouseover', v = 'List scrollbar mouseover (mixer panel)' },
    { k = 'mcp_list_scrollbar_mouseover_mode', v = 'List scrollbar mouseover (mixer panel) - draw mode' },
    { k = 'midi_rulerbg', v = 'MIDI editor ruler background' },
    { k = 'midi_rulerfg', v = 'MIDI editor ruler text' },
    { k = 'midi_grid2', v = 'MIDI editor grid line (start of measure)' },
    { k = 'midi_griddm2', v = 'MIDI editor grid line (start of measure) - draw mode' },
    { k = 'midi_grid3', v = 'MIDI editor grid line (start of beats)' },
    { k = 'midi_griddm3', v = 'MIDI editor grid line (start of beats) - draw mode' },
    { k = 'midi_grid1', v = 'MIDI editor grid line (between beats)' },
    { k = 'midi_griddm1', v = 'MIDI editor grid line (between beats) - draw mode' },
    { k = 'midi_trackbg1', v = 'MIDI editor background color (naturals)' },
    { k = 'midi_trackbg2', v = 'MIDI editor background color (sharps/flats)' },
    { k = 'midi_trackbg_outer1', v = 'MIDI editor background color, out of bounds (naturals)' },
    { k = 'midi_trackbg_outer2', v = 'MIDI editor background color, out of bounds (sharps/flats)' },
    { k = 'midi_selpitch1', v = 'MIDI editor background color, selected pitch (naturals)' },
    { k = 'midi_selpitch2', v = 'MIDI editor background color, selected pitch (sharps/flats)' },
    { k = 'midi_selbg', v = 'MIDI editor time selection color' },
    { k = 'midi_selbg_drawmode', v = 'MIDI editor time selection fill mode' },
    { k = 'midi_gridhc', v = 'MIDI editor CC horizontal center line' },
    { k = 'midi_gridhcdm', v = 'MIDI editor CC horizontal center line - draw mode' },
    { k = 'midi_gridh', v = 'MIDI editor CC horizontal line' },
    { k = 'midi_gridhdm', v = 'MIDI editor CC horizontal line - draw mode' },
    { k = 'midi_ccbut', v = 'MIDI editor CC lane add/remove buttons' },
    { k = 'midi_ccbut_text', v = 'MIDI editor CC lane button text' },
    { k = 'midi_ccbut_arrow', v = 'MIDI editor CC lane button arrow' },
    { k = 'midioct', v = 'MIDI editor octave line color' },
    { k = 'midi_inline_trackbg1', v = 'MIDI inline background color (naturals)' },
    { k = 'midi_inline_trackbg2', v = 'MIDI inline background color (sharps/flats)' },
    { k = 'midioct_inline', v = 'MIDI inline octave line color' },
    { k = 'midi_endpt', v = 'MIDI editor end marker' },
    { k = 'midi_notebg', v = 'MIDI editor note, unselected (midi_note_colormap overrides)' },
    { k = 'midi_notefg', v = 'MIDI editor note, selected (midi_note_colormap overrides)' },
    { k = 'midi_notemute', v = 'MIDI editor note, muted, unselected (midi_note_colormap overrides)' },
    { k = 'midi_notemute_sel', v = 'MIDI editor note, muted, selected (midi_note_colormap overrides)' },
    { k = 'midi_itemctl', v = 'MIDI editor note controls' },
    { k = 'midi_ofsn', v = 'MIDI editor note (offscreen)' },
    { k = 'midi_ofsnsel', v = 'MIDI editor note (offscreen, selected)' },
    { k = 'midi_editcurs', v = 'MIDI editor cursor' },
    { k = 'midi_pkey1', v = 'MIDI piano key color (naturals background, sharps/flats text)' },
    { k = 'midi_pkey2', v = 'MIDI piano key color (sharps/flats background, naturals text)' },
    { k = 'midi_pkey3', v = 'MIDI piano key color (selected)' },
    { k = 'midi_noteon_flash', v = 'MIDI piano key note-on flash' },
    { k = 'midi_leftbg', v = 'MIDI piano pane background' },
    { k = 'midifont_col_light_unsel', v = 'MIDI editor note text and control color, unselected (light)' },
    { k = 'midifont_col_dark_unsel', v = 'MIDI editor note text and control color, unselected (dark)' },
    { k = 'midifont_mode_unsel', v = 'MIDI editor note text and control mode, unselected' },
    { k = 'midifont_col_light', v = 'MIDI editor note text and control color (light)' },
    { k = 'midifont_col_dark', v = 'MIDI editor note text and control color (dark)' },
    { k = 'midifont_mode', v = 'MIDI editor note text and control mode' },
    { k = 'score_bg', v = 'MIDI notation editor background' },
    { k = 'score_fg', v = 'MIDI notation editor staff/notation/text' },
    { k = 'score_sel', v = 'MIDI notation editor selected staff/notation/text' },
    { k = 'score_timesel', v = 'MIDI notation editor time selection' },
    { k = 'score_loop', v = 'MIDI notation editor loop points, selected pitch' },
    { k = 'midieditorlist_bg', v = 'MIDI list editor background' },
    { k = 'midieditorlist_fg', v = 'MIDI list editor text' },
    { k = 'midieditorlist_grid', v = 'MIDI list editor grid lines' },
    { k = 'midieditorlist_selbg', v = 'MIDI list editor selected row' },
    { k = 'midieditorlist_selfg', v = 'MIDI list editor selected text' },
    { k = 'midieditorlist_seliabg', v = 'MIDI list editor selected row (inactive)' },
    { k = 'midieditorlist_seliafg', v = 'MIDI list editor selected text (inactive)' },
    { k = 'midieditorlist_bg2', v = 'MIDI list editor background (secondary)' },
    { k = 'midieditorlist_fg2', v = 'MIDI list editor text (secondary)' },
    { k = 'midieditorlist_selbg2', v = 'MIDI list editor selected row (secondary)' },
    { k = 'midieditorlist_selfg2', v = 'MIDI list editor selected text (secondary)' },
  }
  

function tk.get_theme_path()
    tk.theme_path = r.GetLastColorThemeFile()
    return tk.theme_path
end

function tk.GetAllThemeColors(color_identifiers)
    local colors = {}
    for _, color_id in ipairs(color_identifiers) do
        local colorval = r.GetThemeColor(color_id.k)
        if colorval and colorval ~= -1 then
            colors[color_id.k] = tk.color.int2hex(colorval)
        end
    end
    return colors
end

function tk.get_all_theme_colors()
    if tk.all_theme_colors then 
        return tk.all_theme_colors 
    end

    tk.theme_var_descriptions = {}
    for _, entry in ipairs(tk.color.theme_names) do
        tk.theme_var_descriptions[entry.k] = entry.v
    end

    tk.all_theme_colors = tk.GetAllThemeColors(tk.color.theme_names)
    return tk.all_theme_colors
end

tk.color.names = {
    transparent = "#ffffff00",
    black = '#000000',
    silver = '#c0c0c0',
    gray = '#808080',
    white = '#ffffff',
    maroon = '#800000',
    red = '#ff0000',
    purple = '#800080',
    fuchsia = '#ff00ff',
    green = '#008000',
    lime = '#00ff00',
    olive = '#808000',
    yellow = '#ffff00',
    navy = '#000080',
    blue = '#0000ff',
    teal = '#008080',
    aqua = '#00ffff',
    orange = '#ffa500',
    aliceblue = '#f0f8ff',
    antiquewhite = '#faebd7',
    aquamarine = '#7fffd4',
    azure = '#f0ffff',
    beige = '#f5f5dc',
    bisque = '#ffe4c4',
    blanchedalmond = '#ffebcd',
    blueviolet = '#8a2be2',
    brown = '#a52a2a',
    burlywood = '#deb887',
    cadetblue = '#5f9ea0',
    chartreuse = '#7fff00',
    chocolate = '#d2691e',
    coral = '#ff7f50',
    cornflowerblue = '#6495ed',
    cornsilk = '#fff8dc',
    crimson = '#dc143c',
    cyan = '#00ffff',
    darkblue = '#00008b',
    darkcyan = '#008b8b',
    darkgoldenrod = '#b8860b',
    darkgray = '#a9a9a9',
    darkgreen = '#006400',
    darkgrey = '#a9a9a9',
    darkkhaki = '#bdb76b',
    darkmagenta = '#8b008b',
    darkolivegreen = '#556b2f',
    darkorange = '#ff8c00',
    darkorchid = '#9932cc',
    darkred = '#8b0000',
    darksalmon = '#e9967a',
    darkseagreen = '#8fbc8f',
    darkslateblue = '#483d8b',
    darkslategray = '#2f4f4f',
    darkslategrey = '#2f4f4f',
    darkturquoise = '#00ced1',
    darkviolet = '#9400d3',
    deeppink = '#ff1493',
    deepskyblue = '#00bfff',
    dimgray = '#696969',
    dimgrey = '#696969',
    dodgerblue = '#1e90ff',
    firebrick = '#b22222',
    floralwhite = '#fffaf0',
    forestgreen = '#228b22',
    gainsboro = '#dcdcdc',
    ghostwhite = '#f8f8ff',
    gold = '#ffd700',
    goldenrod = '#daa520',
    greenyellow = '#adff2f',
    grey = '#808080',
    honeydew = '#f0fff0',
    hotpink = '#ff69b4',
    indianred = '#cd5c5c',
    indigo = '#4b0082',
    ivory = '#fffff0',
    khaki = '#f0e68c',
    lavender = '#e6e6fa',
    lavenderblush = '#fff0f5',
    lawngreen = '#7cfc00',
    lemonchiffon = '#fffacd',
    lightblue = '#add8e6',
    lightcoral = '#f08080',
    lightcyan = '#e0ffff',
    lightgoldenrodyellow = '#fafad2',
    lightgray = '#d3d3d3',
    lightgreen = '#90ee90',
    lightgrey = '#d3d3d3',
    lightpink = '#ffb6c1',
    lightsalmon = '#ffa07a',
    lightseagreen = '#20b2aa',
    lightskyblue = '#87cefa',
    lightslategray = '#778899',
    lightslategrey = '#778899',
    lightsteelblue = '#b0c4de',
    lightyellow = '#ffffe0',
    limegreen = '#32cd32',
    linen = '#faf0e6',
    magenta = '#ff00ff',
    mediumaquamarine = '#66cdaa',
    mediumblue = '#0000cd',
    mediumorchid = '#ba55d3',
    mediumpurple = '#9370db',
    mediumseagreen = '#3cb371',
    mediumslateblue = '#7b68ee',
    mediumspringgreen = '#00fa9a',
    mediumturquoise = '#48d1cc',
    mediumvioletred = '#c71585',
    midnightblue = '#191970',
    mintcream = '#f5fffa',
    mistyrose = '#ffe4e1',
    moccasin = '#ffe4b5',
    navajowhite = '#ffdead',
    oldlace = '#fdf5e6',
    olivedrab = '#6b8e23',
    orangered = '#ff4500',
    orchid = '#da70d6',
    palegoldenrod = '#eee8aa',
    palegreen = '#98fb98',
    paleturquoise = '#afeeee',
    palevioletred = '#db7093',
    papayawhip = '#ffefd5',
    peachpuff = '#ffdab9',
    peru = '#cd853f',
    pink = '#ffc0cb',
    plum = '#dda0dd',
    powderblue = '#b0e0e6',
    rosybrown = '#bc8f8f',
    royalblue = '#4169e1',
    saddlebrown = '#8b4513',
    salmon = '#fa8072',
    sandybrown = '#f4a460',
    seagreen = '#2e8b57',
    seashell = '#fff5ee',
    sienna = '#a0522d',
    skyblue = '#87ceeb',
    slateblue = '#6a5acd',
    slategray = '#708090',
    slategrey = '#708090',
    snow = '#fffafa',
    springgreen = '#00ff7f',
    steelblue = '#4682b4',
    tan = '#d2b48c',
    thistle = '#d8bfd8',
    tomato = '#ff6347',
    turquoise = '#40e0d0',
    violet = '#ee82ee',
    wheat = '#f5deb3',
    whitesmoke = '#f5f5f5',
    yellowgreen = '#9acd32',
    rebeccapurple = '#663399',
}

function tk.set_color(color)
    local r, g, b, a = tk.color.rgba(color)
    return Gui.ColorConvertDouble4ToU32(r, g, b, a)
end

function tk.PushColor(flag, color)
    if type(color) == 'string' or type(color) == 'table' then
        color = tk.set_color(color)
    end
    if tk.ctx or ctx then
        Gui.PushStyleColor(tk.ctx or ctx, flag, color)
    end
end

return tk