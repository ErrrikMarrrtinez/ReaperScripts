--@noindex
--NoIndex: true

icon_color="#9a9a9a"
icons_row1 = {'angry', 'sad', 'indiff', 'happin', 'happy'}
icons_cols = {'#ff4330', '#ff9000', '#ffea03', '#98bb19' ,'#03b81a'}
pack = rtk.ImagePack():add{src='smile.png',style='light', {w=251, h=251, names=icons_row1, size='medium', density=1}}:register_as_icons()

audio_formats = {"wav", "aiff", "flac","mp3", "aac", "ogg"}

month_names = {
    "Jan", 
    "Feb", 
    "Mar", 
    "Apr", 
    "May", 
    "Jun", 
    "Jul", 
    "Aug", 
    "Sep", 
    "Oct", 
    "Nov", 
    "Dec"
}

function lerp(a, b, t)
    return a + (b - a) * t
end

function norm(value, min, max)
    return (value - min) / (max - min)
end

function concat(str)
    if not str then return end
    return table.concat(str, "  ")
end

function table_remove(tbl, val)
    for i, v in ipairs(tbl) do
        if v == val then
            table.remove(tbl, i)
            break
        end
    end
end

function get_modifier_value(modifiers)
    local total_value = 0
    for modifier in string.gmatch(modifiers, "%a+") do
        total_value = total_value + ({ctrl = 4, shift = 8, alt = 16})[modifier] or 0
    end
    return total_value
end

function hex_darker(color, amount)
    local r, g, b = color:match("#(%x%x)(%x%x)(%x%x)")
    r = math.floor(math.max(0, math.min(255, tonumber(r, 16) * (1 - amount))))
    g = math.floor(math.max(0, math.min(255, tonumber(g, 16) * (1 - amount))))
    b = math.floor(math.max(0, math.min(255, tonumber(b, 16) * (1 - amount))))
    return string.format("#%02x%02x%02x", r, g, b)
end

function shift_color(color, delta_hue, delta_saturation, delta_value)
    local h, s, l, a = rtk.color.hsl(color)
    h = (h + delta_hue) % 1
    s = rtk.clamp(s * delta_saturation, 0, 1)
    l = rtk.clamp(l * delta_value, 0, 1)
    local r, g, b = rtk.color.hsl2rgb(h, s, l)
    return rtk.color.rgba2hex(r, g, b, a)
end

function replace_mounth(short_dates)
    local short_date_num = short_dates
    for i, month in ipairs(month_names) do
        if short_dates:find(month) then
            local monthNumber = string.format("%02d", i)
            short_date_num = short_dates:gsub(month, monthNumber)
            break
        end
    end
    return short_date_num
end

function shorten_path(path, sep)
    local parts = {}
    for part in string.gmatch(path, "[^"..sep.."]+") do
        table.insert(parts, part)
    end

    if #parts > 2 then
        return "F:\\" .. " ... \\" .. table.concat(parts, "\\", #parts-1)
    else
        return path
    end
end

function format_size(size)
    local total_size

    if size >= 1024 * 1024 * 1024 then
        total_size = string.format("%.2f GB", size / (1024 * 1024 * 1024))
    elseif size >= 1024 * 1024 then
        total_size = string.format("%.2f MB", size / (1024 * 1024))
    else
        total_size = string.format("%.2f KB", size / 1024)
    end
    
    return total_size
end

function get_file_info(file_path)
    local retval, size, _, modified_time, _, _, _, _, _, _, _, _ = reaper.JS_File_Stat(file_path)
    if retval == 0 then
        local year, month, day, hour, min, sec = string.match(modified_time, "(%d%d%d%d)%.(%d%d)%.(%d%d) (%d%d):(%d%d):(%d%d)")
        month = month_names[tonumber(month)]
        year = string.sub(year, 3)
        local modified_date = day .. " " .. month .. " " .. year .. ", " .. hour .. ":" .. min
        local total_size = format_size(size)
        return total_size, modified_date, modified_time, size
    else 
        return nil
    end
end

function extract_name(filePath)
    local path = filePath:match("(.*[/\\])")
    local filename = filePath:match("([^/\\]+)$")
    local clean_name = filename:match("(.+)%..+%.") or filename:match("(.+)%.")
    return clean_name, path
end

function get_recent_projects(ini_path)
    local p = 0
    local index = 1
    local all_paths_list = {} -- создаем новый список
    repeat
        p = p + 1
        local _, value = reaper.BR_Win32_GetPrivateProfileString("recent", "recent" .. string.format("%02d", p), "noEntry", ini_path)
    until value == "noEntry"
    -- iterate through recent entries from newest to oldest
    for i = p - 1, 1, -1 do
        local _, path = reaper.BR_Win32_GetPrivateProfileString("recent", "recent" .. string.format("%02d", i), "", ini_path)
        
        
        local form_size, form_date, clean_date, clean_size = get_file_info(path) 

        if form_size ~= nil then
        
            table.insert(all_paths_list, path) -- добавляем путь в список
            
            local clean_name, directory = extract_name(path)
            all_paths[path] = {
                idx = index,
                path = path,
                dir = directory,
                filename = clean_name,
                form_size = form_size,
                clean_size = clean_size,
                form_date = form_date,
                clean_date = clean_date,
                hbox = hbox,
                DATA = get_parameter(path)
            }
            index = index + 1
        end
    end
    return all_paths, all_paths_list 
end

function sort_paths(new_paths, all_paths_list, sort_type, direction)
    table.sort(all_paths_list, function(a, b)
        if sort_type == "date" then
            if direction == 1 then
                return new_paths[a].clean_date > new_paths[b].clean_date
            else
                return new_paths[a].clean_date < new_paths[b].clean_date
            end
        elseif sort_type == "opened" then
            if direction == 1 then
                return new_paths[a].idx > new_paths[b].idx
            else
                return new_paths[a].idx < new_paths[b].idx
            end
        elseif sort_type == "az" then
            if direction == 1 then
                return new_paths[a].filename > new_paths[b].filename
            else
                return new_paths[a].filename < new_paths[b].filename
            end
        elseif sort_type == "size" then
            if direction == 1 then
                return new_paths[a].clean_size > new_paths[b].clean_size
            else
                return new_paths[a].clean_size < new_paths[b].clean_size
            end
        end
    end)
    return all_paths_list
end

function create_shadow(parent, bgcol, borcol, dim, new_spacer)
    local spacer = new_spacer or parent:add(rtk.Spacer{margin=5,z=-4},{fillw=true,fillh=true})
    local shadow = rtk.Shadow(borcol)
    local dim =  dim * rtk.scale.reaper    

    --reset deep
    if bgcol == "transparent" and borcol == "transparent" then
        parent:attr('z', 0)
        parent:get_child(1):attr('z', -5)
        
    else
        parent:attr('z', 3)
        parent:get_child(1):attr('z', -1)
    end

    spacer.onreflow = function(self)
        shadow:set_rectangle(math.round(self.calc.w), math.round(self.calc.h), dim)
    end

    spacer.ondraw = function(self, offx, offy, alpha)
        shadow:draw(math.round(self.calc.x + offx), math.round(self.calc.y) + offy, alpha)
    end
    
    return spacer
end

function create_spacer(parent, bgcol, borcol, rval, externalSpacer, text)
    local spacer = externalSpacer or parent:add(rtk.Spacer{w=1, z=-5},{fillw=true,fillh=true})
    bgcol = bgcol or spacer.bgcol
    borcol = borcol or bgcol
    
    spacer.ondraw = function(self, offx, offy, alpha, event)
        self:setcolor(bgcol, alpha)
        rtk.gfx.roundrect(
            math.round(offx + self.calc.x-1),
            math.round(offy + self.calc.y-1),
            math.round(self.calc.w+2),
            math.round(self.calc.h+2),
            rval,
            1, -- fill
            true  -- antialias
        )
        self:setcolor(borcol, alpha)
        rtk.gfx.roundrect(
            math.round(offx + self.calc.x),
            math.round(offy + self.calc.y),
            math.round(self.calc.w),
            math.round(self.calc.h),
            rval-2,
            0.5, -- fill
            true  -- antialias
        )
    end
    if text then
        local pad_procent = parent:add(
            rtk.Text{
                bg=bgcol,
                margin=2,
                padding=-4,
                text.."%",
                y=-1,
                valign='center'}
                ,{
                fillh=true,
                halign='center'
        })

        spacer.text=pad_procent

    end
    spacer.col=bgcol
    spacer.borcol=borcol
    spacer.round=rval
    return spacer, text
end

function recolor(spacer, bgcol, borcol, text)
    bgcol = bgcol or spacer.bgcol
    borcol = borcol or bgcol
    spacer.ondraw = function(self, offx, offy, alpha, event)
        self:setcolor(borcol, alpha)
        rtk.gfx.roundrect(
            math.round(offx + self.calc.x),
            math.round(offy + self.calc.y),
            math.round(self.calc.w),
            math.round(self.calc.h),
            self.round-2,
            0.5, -- fill
            true  -- antialias
        )
        self:setcolor(bgcol, alpha)
        rtk.gfx.roundrect(
            math.round(offx + self.calc.x-1),
            math.round(offy + self.calc.y-1),
            math.round(self.calc.w+2),
            math.round(self.calc.h+2),
            self.round,
            1, -- fill
            true  -- antialias
        )

        
    end
    if text then
        spacer.text:attr('text', text .. "%")
        spacer.text:attr('bg', borcol)
    end
    spacer.col=bgcol
    spacer.borcol=borcol
    return spacer
end


function loadIcons(directory)
    local icons = {}
    local img = {}
    local i = 0
    while true do
        local filename = reaper.EnumerateFiles(directory, i)
        if not filename then break end
        if filename then
            local clear_name = filename:match("%.png$")
            local icon = rtk.Image():load(filename):scale(120,120,22,6):recolor(icon_color)
            local imgBox = rtk.ImageBox{image=icon}
            if icon then
                local key = filename:match("(.+)%..+")
                icons[key] = icon
                img[key] = imgBox
            end
        end
        i = i + 1
    end
    return icons, img
end

function icons_raiting(scale, cols)
    local rait_icons = {}
    for i, icon_name in ipairs(icons_row1) do
        local icon = rtk.Image.icon(icon_name):scale(scale):recolor(cols[i])

        rait_icons[icon_name] = icon
    end
    return rait_icons
end

function loadIniFiles(directory)
    local iniFiles = {}
    local i = 0
    while true do
        local filename = reaper.EnumerateFiles(directory, i)
        if not filename then break end
        if filename:match("%.ini$") then
            local key = filename:match("(.+)%..+")
            iniFiles[key] = directory .. sep.. filename
        end
        i = i + 1
    end
    return iniFiles
end

function update_window(self, w, h)
     for i, blan in ipairs(sorted_paths) do
         local n = new_paths[blan]
         local date = n.hbox.refs.date
         local full_date = n.form_date
         local short_date = n.form_date_1 --full_date:gsub(" %d+, %d+:%d+", "")
         local short_date_2 = n.form_date_2 --full_date:gsub(", %d%d:%d%d", "")
         
         short_date_num = replace_mounth(short_date)
         short_date_num = short_date_num:gsub(" ", ".")
         
         if self.w <= 660 and self.w > 550 then
             date:attr('text', short_date_2)
         elseif self.w <= 460 and self.w > 350 then
             date:attr('text', short_date)
         elseif self.w <= 340 and self.w > 250 then
             date:attr('text', short_date_num)
         elseif self.w > 490 then
             date:attr('text', full_date)
         end
     end
end





------------------------------------------------------------------------
------------FILE-FUNCTIONS----------------FILE-FUNCTIONS----------------
------------------------------------------------------------------------




-- Функция для чтения и декодирования данных из файла
-- @param file_path Путь к файлу для чтения (необязательно)
function read_and_decode2(file_path)
    file_path = file_path or params_file
    local file = io.open(file_path, "r")
    local data = file:read("*all")
    file:close()

    local decoded_data = {}
    if data ~= "" then
        decoded_data = json.decode(data)
    end

    return decoded_data
end

-- Функция для сохранения параметра в файл
-- @param param Параметр для сохранения
-- @param value Значение параметра для сохранения
-- @param file_path Путь к файлу для сохранения (необязательно)
function save_parameter(param, value, file_path)
    file_path = file_path or params_file
    local decoded_data = read_and_decode2(file_path)
    decoded_data[param] = value
    local updated_data = json.encode(decoded_data)

    local file = io.open(file_path, "w")
    file:write(updated_data)
    file:close()
end

-- Функция для получения параметра из файла
-- @param param Параметр для получения
-- @param file_path Путь к файлу для чтения (необязательно)
function get_parameter(param, file_path)
    file_path = file_path or params_file
    local decoded_data = read_and_decode2(file_path)
    return decoded_data[param]
end

-- Функция для удаления параметра из файла
-- @param param Имя параметра для удаления
-- @param file_path Путь к файлу для обновления (необязательно)
function clear_parameter(param, file_path)
    file_path = file_path or params_file
    local decoded_data = read_and_decode(file_path)
    decoded_data[param] = nil
    local updated_data = json.encode(decoded_data)
    local file = io.open(file_path, "w")
    file:write(updated_data)
    file:close()
end

-- Функция для чтения и декодирования данных из файла
-- @param file_path Путь к файлу для чтения (необязательно)
function read_and_decode(file_path)
    file_path = file_path or params_data
    local file = io.open(file_path, "r")
    local data = file:read("*all")
    file:close()
    local decoded_data = {}
    if data ~= "" then
        decoded_data = json.decode(data)
    end

    return decoded_data
end

-- Функция для сохранения массива в файл
-- @param name Имя массива для сохранения
-- @param array Массив для сохранения
-- @param file_path Путь к файлу для сохранения (необязательно)
function save_array(name, array, file_path)
    file_path = file_path or params_data
    local decoded_data = read_and_decode(file_path)
    decoded_data[name] = array
    local updated_data = json.encode(decoded_data)
    local file = io.open(file_path, "w")
    file:write(updated_data)
    file:close()
end

-- Функция для получения массива из файла
-- @param name Имя массива для получения
-- @param file_path Путь к файлу для чтения (необязательно)
function get_array(name, file_path)
    file_path = file_path or params_data
    local decoded_data = read_and_decode(file_path)
    return decoded_data[name]
end

-- Функция для удаления массива из файла
-- @param name Имя массива для удаления
-- @param file_path Путь к файлу для обновления (необязательно)
function delete_array(name, file_path)
    file_path = file_path or params_data
    local decoded_data = read_and_decode(file_path)
    decoded_data[name] = nil
    local updated_data = json.encode(decoded_data)
    local file = io.open(file_path, "w")
    file:write(updated_data)
    file:close()
end

-- Функция для получения всех имен из файла
-- @param file_path Путь к файлу для чтения (необязательно)
function get_all_names(file_path)
    file_path = file_path or params_data
    local saved_paths = {}
    local decoded_data = read_and_decode(file_path)
    for name, _ in pairs(decoded_data) do
        table.insert(saved_paths, name)
    end
    return saved_paths
end


------------------------------------------------------------------------
------------------------------------------------------------------------
------------------------------------------------------------------------

function get_selected_path()
    reaper.ClearConsole()
    for i, path in ipairs(sorted_paths) do
        local n = new_paths[path]
        if n.sel == 1 then print(n.path) end
    end
end

function unselect_all_path()
    for i, path in ipairs(sorted_paths) do
        local n = new_paths[path]
        local odd_col_bg = i % 2 == 0 and '#3a3a3a' or '#323232'
        recolor(n.cont.refs.bg_spacer, odd_col_bg, odd_col_bg)
        n.sel = 0
    end                  
end

local new_h = 0

function update_heigh_list(dir)
    for _, blan in ipairs(sorted_paths) do
        local n = new_paths[blan]
        local h = n.cont.h 

        local text_name = n.hbox.refs.text_name
        local text_name2 = n.hbox.refs.path_box.refs.paths
             
        local wrap = new_h > 45
        text_name:attr('wrap', wrap)
        text_name2:attr('wrap', wrap)

        new_h = math.floor( math.min(math.max(h + 15 * dir, 20), 100) )
        n.cont:animate{'h',dst=new_h,duration=0.1, easing="in-quad"} --in quad --out-elastic

    end
end


function pitchMode()
  return ps_modes[ps_mode].v == -1 and -1 or (ps_modes[ps_mode].v << 16)
end

function start()
  local source = reaper.PCM_Source_CreateFromFile(file)
  if not source then return end

  if preview then reaper.CF_Preview_Stop(preview) end
  preview = reaper.CF_CreatePreview(source)
  reaper.CF_Preview_SetValue(preview, 'I_OUTCHAN', output_chan)
  reaper.CF_Preview_SetValue(preview, 'B_LOOP', loop and 1 or 0)
  reaper.CF_Preview_SetValue(preview, 'D_VOLUME', volume)
  reaper.CF_Preview_SetValue(preview, 'D_PITCH', pitch)
  reaper.CF_Preview_SetValue(preview, 'B_PPITCH', preserve_pitch and 1 or 0)
  reaper.CF_Preview_Play(preview)
  reaper.PCM_Source_Destroy(source)
end

function get_play_info(preview)
    local ret, position = reaper.CF_Preview_GetValue(preview, 'D_POSITION')
    local length = select(2, reaper.CF_Preview_GetValue(preview, 'D_LENGTH'))
    want_pos = reaper.format_timestr(length, '')
    time = reaper.format_timestr(position, '')
    return time, want_pos, position, length
end

function rtk_Entry(parent, borcol, bgcol, round, placeholder)
    local borcol_act = hex_darker(borcol, -0.5)
    local bgcol_act = hex_darker(bgcol, -0.2)
    local round = round or round_rect_window
    local container_entry = parent:add(rtk.Container{cursor=rtk.mouse.cursors.BEAM, h=35}, {fillw=true, halign='right'})
    local bg_entry = create_spacer(container_entry, borcol, bgcol, round)
    
    local entry = container_entry:add(Entry{placeholder=placeholder, hotzone=5, lhotzone=10, rhotzone=10, tpadding=2, fontscale=1.2, lmargin=10,rmargin=10, w=container_entry.calc.w, h=container_entry.calc.h-8, bg=bgcol},{valign='center', })
    
    entry.onfocus = function(self, event)
        bg_entry = recolor(bg_entry, hex_darker(borcol_act, -0.2), hex_darker(bgcol_act, -0.3))
        self:attr('bg', bg_entry.bg)
        self.FOCUSED = true
        return true
    end
    
    entry.onblur = function(self, event)
        bg_entry = recolor(bg_entry, borcol, bgcol)
        self:attr('bg', bgcol)
        self.FOCUSED = false
    end
    
    entry.onmouseleave = function(self, event)
        if not self.FOCUSED then
            bg_entry = recolor(bg_entry, borcol, bgcol)
            self:attr('bg', bgcol)
        end
    end
    
    entry.onmouseenter = function(self, event)
        if not self.FOCUSED then
            bg_entry = recolor(bg_entry, borcol_act , bgcol_act)
            self:attr('bg', bgcol_act)
        end
    end

    container_entry.onclick = function(self, event)
        entry:focus()
    end

    entry:onmouseenter()
    entry:onmouseleave()
    return entry, container_entry
end



function tolower(str, mode)
    local lower_ru = {
        ["А"] = "а", ["Б"] = "б", ["В"] = "в", ["Г"] = "г", ["Д"] = "д", ["Е"] = "е", ["Ё"] = "ё", ["Ж"] = "ж", ["З"] = "з", ["И"] = "и", ["Й"] = "й", ["К"] = "к", ["Л"] = "л", ["М"] = "м", ["Н"] = "н", ["О"] = "о", ["П"] = "п", ["Р"] = "р", ["С"] = "с", ["Т"] = "т", ["У"] = "у", ["Ф"] = "ф", ["Х"] = "х", ["Ц"] = "ц", ["Ч"] = "ч", ["Ш"] = "ш", ["Щ"] = "щ", ["Ъ"] = "ъ", ["Ы"] = "ы", ["Ь"] = "ь", ["Э"] = "э", ["Ю"] = "ю", ["Я"] = "я"
    }
    local result = ""
    if mode == 1 then
        for uchar in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
            local l = lower_ru[uchar] or string.lower(uchar)
            result = result .. l
        end
    elseif mode == 2 then
        for p, c in utf8.codes(str) do
            local char = utf8.char(c)
            local lower = lower_ru[char] or string.lower(char)
            result = result .. lower
        end
    end
    return result
end

function find_exact_match(str1, str2)
    str1 = string.gsub(tolower(str1, 1), "%p", " ")
    str2 = string.gsub(tolower(str2, 1), "%p", " ")

    words1 = {}
    for word in string.gmatch(str1, "%S+") do
        table.insert(words1, word)
    end

    words2 = {}
    for word in string.gmatch(str2, "%S+") do
        table.insert(words2, word)
    end

    for i, word1 in ipairs(words1) do
        for j, word2 in ipairs(words2) do
            if word1 == word2 then
                return true
            end
        end
    end

    return false
end


function scan_dir(dirPath)
    local i = 0
    local files = {}

    if CURRENT_media_path then
        local dirPath = dirPath:match("(.*[/\\])")

        while true do
            local fileName = reaper.EnumerateFiles(dirPath, i)
            if fileName == nil then
                break
            end

            local fileExtension = fileName:match("^.+(%..+)$")
            
            if fileExtension then
                fileExtension = fileExtension:lower()
                for _, audioFormat in ipairs(audio_formats) do
                    if fileExtension == "." .. audioFormat then
                        local filePath = dirPath .. "\\" .. fileName
                        local _, _, _, modified_time, _, _, _, _, _, _, _, _ = reaper.JS_File_Stat(filePath)
                        files[filePath] = modified_time
                        break
                    end
                end
            end
            i = i + 1
        end
    end

    if GENERAL_media_path[1] then
        local fileName = dirPath:match("^.+\\(.+)%..+$")
        local dirPath = GENERAL_media_path[2]
        
        
        if fileName == nil then
            return {}
        end
        local i = 0
        while true do
            local file = reaper.EnumerateFiles(dirPath, i)
            
            if file == nil then
                break
            end
            if find_exact_match(file, fileName) then
                local filePath = dirPath .. sep .. file
                local _, _, _, modified_time, _, _, _, _, _, _, _, _ = reaper.JS_File_Stat(filePath)
                files[filePath] = modified_time
            end
            i = i + 1
        end
    end
    
    if INDIVIDUAL_media_path then
        data = get_parameter(dirPath)
        return data
    end

    local sortedFilePaths = {}
    for filePath, _ in pairs(files) do
        table.insert(sortedFilePaths, filePath)
    end
    table.sort(sortedFilePaths, function(a, b) return files[a] > files[b] end)

    return sortedFilePaths
end

function resize_image(path, save_directory, filename, new_width, new_height)
    local src_bmp
    local ext = string.lower(string.match(path, "%.([^%.]+)$"))
    local final_path = save_directory .. sep .. filename
    if ext == "png" then
        src_bmp = reaper.JS_LICE_LoadPNG(path)
    elseif ext == "jpg" or ext == "jpeg" then
        src_bmp = reaper.JS_LICE_LoadJPG(path)
    end
    if src_bmp then
        local src_w = reaper.JS_LICE_GetWidth(src_bmp)
        local src_h = reaper.JS_LICE_GetHeight(src_bmp)
        local start_x, start_y = 0, 0
        -- if not square
        if math.abs(src_w - src_h) > 30 then
            if src_w > src_h then
                local diff = (src_w - src_h) / 2
                start_x = diff
                src_w = src_h
            else
                local diff = (src_h - src_w) / 2
                start_y = diff
                src_h = src_w
            end
        end
        local dest_bmp = reaper.JS_LICE_CreateBitmap(true, new_width, new_height)
        local src_dc = reaper.JS_LICE_GetDC(src_bmp)
        local dest_dc = reaper.JS_LICE_GetDC(dest_bmp)
        reaper.JS_LICE_ScaledBlit(dest_bmp, 0, 0, new_width, new_height, src_bmp, start_x, start_y, src_w, src_h, 1, "COPY")

--[[        -- Add rounded corners
        local corner_radius = 100 -- Adjust this to change the roundness of the corners
        local color = 0x00000000 -- Transparent color
        reaper.JS_LICE_RoundRect(dest_bmp, 0, 0, new_width, new_height, corner_radius, color, 1, "COPY", true)]]

        reaper.JS_LICE_WritePNG(final_path, dest_bmp, 1)
        reaper.JS_LICE_DestroyBitmap(src_bmp)
        reaper.JS_LICE_DestroyBitmap(dest_bmp)
        return final_path, filename
    else
        print("error" .. path)
    end
end


function unmatch_images(dir_path, filename_proj)
    local i = 0
    while true do
        local filename = reaper.EnumerateFiles(dir_path, i)
        if filename == nil then
            break
        end
        local split_filename = filename:split('_')
        if split_filename[1] == filename_proj then
            local file_path = dir_path .. '/' .. filename
            os.remove(file_path)
        end
        i = i + 1
    end
end

function rename_file(img_path)
    local _, filename = img_path:match("(.-)([^\\/]-%.?[^%.\\/]*)$")
    local new_filename = filename:gsub("_", " ")
    local new_path = img_path:gsub(filename, new_filename)
    os.rename(img_path, new_path)
    return new_path
end

function update_image(all_info, img_path, img, data)
    img_path = rename_file(img_path)
    local filename = img_path:match("\\([^\\]-)$") 
    filename = string.match(filename, "(.+)%..+") .. ".png"
    local filename_proj = all_info.filename
    local merge_filename = filename_proj .. "_" .. filename
    unmatch_images(CUSTOM_IMAGE_global, filename_proj)
    GLOBAL_img_path, data.img = resize_image(img_path, CUSTOM_IMAGE_global, merge_filename, DEF_IMG_W, DEF_IMG_H)
    save_parameter(all_info.path, data)
    img:attr('image',CUSTOM_IMAGE_local..merge_filename)
end

function create_container(params, parent, txt)
    local container = parent:add(rtk.Container(params))
    local vbox = container:add(rtk.VBox{ref='VBOX', fillw=true},{})
    local heading = vbox:add(rtk.Container{ref='HEAD', margin=0,h=40},{fillw=true})
    if txt then heading:add(rtk.Text{fontsize=18,fontflags=rtk.font.BOLD,y=heading.calc.h/5,txt,halign='center',h=1,w=1}) end
    local rect_heading = create_spacer(heading, COL1, COL2, round_rect_window)
    local hiden_bottom = heading:add(rtk.Spacer{margin=0,y=32,h=35,w=1,bg=COL3})
    local bg_roundrect = create_spacer(container, COL1, COL3, round_rect_window)
    bg_roundrect:attr('ref','BG')
    local vp_vbox = rtk.VBox{spacing=def_spacing, padding=2, margin=2,w=1}
    local viewport = vbox:add(rtk.Viewport{child = vp_vbox, smoothscroll = true,scrollbar_size = 2,z=2})
    
    return container, heading, vp_vbox, viewport
end

function create_b_set(ref, text)
    return rtk.Button{tagalpha=0.1, color='#3a3a3a20',tagged=true, cursor=rtk.mouse.cursors.HAND,gradient=0, padding=1,fontsize=21, ref="cur", icon=ic_off, w=1, h=1, flat=true, text}
end

function create_b(CONT, txt, w, h, bparms, icon, animate)
    animate = animate == nil and true or animate
    local b_ref = txt:gsub(" ", "_"):gsub("%W", "_")
    local container = CONT:add(rtk.Container{cursor=rtk.mouse.cursors.HAND, hotzone=3, h=h, w=w, halign='center'},{halign='center'})
    local b_spacer = create_spacer(container, COL8, COL18, round_rect_list); b_spacer:attr('ref', b_ref); b_spacer:attr('w', w)
    
    local function animate_or_attr(self, attr, value)
        if animate then
            if GLOBAL_ANIMATE then
                self:animate{attr, dst=value, duration=0.05}
            else
                self:attr(attr, value)
            end
        end
    end

    local txt_v
    if bparms then
        txt_v = container:add(rtk.Button{tpadding=3.5,lpadding=7.5,disabled=true,surface=false, icon=icon, fontsize=18, w=container.calc.w, h=container.calc.h, ref=b_ref},{ valign='center', halign='center'})
    else
        txt_v = container:add(rtk.Text{fontsize=18, w=1, h=1, ref=b_ref, txt, valign='center', halign='center'})
    end

    container.onmouseenter = function(self, event)
        animate_or_attr(self, 'h', h+(h/6))
        animate_or_attr(txt_v, 'fontscale', 1.1)
        b_spacer = recolor(b_spacer, COL4, COL7)
        return true
    end

    container.onmouseleave = function(self, event)
        animate_or_attr(self, 'h', h)
        animate_or_attr(txt_v, 'fontscale', 1.0)
        b_spacer = recolor(b_spacer, COL18, COL18)
        return true
    end

    container.onmousedown = function(self, event)
        animate_or_attr(txt_v, 'fontscale', 1.01)
        b_spacer = recolor(b_spacer, COL18, COl12)
        return true
    end

    container.onmouseup = container.onmouseenter
    return container
end


function ENTER(self, event)
    self:attr('bg', COL18)
    return true
end

function LEAVE(self, event)
    self:attr('bg', "transparent")
end


function create_state_updater()
    local LEFT_MOUSE_BUTTON = 1
    local waiting_for_release = false
    local started_outside = false
    local drag_started = false

    local function reset_all(img)
        waiting_for_release = false
        started_outside = false
        drag_started = false
        img:attr('border', 'transparent')
    end

    return function(vp_images2, wnd, img)
        local state = reaper.JS_Mouse_GetState(1)
        local x, y = reaper.GetMousePosition()

        local is_in_container = rtk.point_in_box(x, y, vp_images2.clientx + wnd.x, vp_images2.clienty + wnd.y, vp_images2.calc.w, vp_images2.calc.h)
        if state == LEFT_MOUSE_BUTTON and not is_in_container then
            started_outside = true
        end

        if state == LEFT_MOUSE_BUTTON and is_in_container and started_outside then
            if not drag_started then
                drag_started = true
            else
                waiting_for_release = true
                img:attr('border', '5px red#30')
            end
        elseif waiting_for_release and not is_in_container then
            img:attr('border', 'transparent')
        elseif waiting_for_release and state ~= LEFT_MOUSE_BUTTON and is_in_container then
            --reaper.ShowConsoleMsg("DROP.\n")
            --RESET ALL--
            reset_all(img)
        end
    end
end

update_state = create_state_updater()