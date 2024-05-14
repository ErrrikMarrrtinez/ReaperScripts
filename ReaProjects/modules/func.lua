--@noindex
--NoIndex: true

icon_color="#9a9a9a"
icons_row1 = {'angry', 'sad', 'indiff', 'happin', 'happy'}
icons_cols = {'#ff4330', '#ff9000', '#ffea03', '#98bb19' ,'#03b81a'}
pack = rtk.ImagePack():add{src='smile.png',style='light', {w=251, h=251, names=icons_row1, size='medium', density=1}}:register_as_icons()

audio_formats = {
    "wav", 
    "aiff", 
    "flac",
    "mp3", 
    "aac", 
    "ogg"
}

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

data_files = {
        "archives.ini",
        "collections.ini",
        "data_path.ini",
        "params.ini",
        "saved_projects.ini",
        "settings.ini",
        "workspaces.ini"
}

function check_and_install_extension(extension_name, filter_name)
    local has_extension = (extension_name == "JS_ReaScriptAPI") and rtk.has_js_reascript_api or rtk.has_sws_extension
    if not has_extension then
      local retval = reaper.MB(extension_name .. " is not installed. Click OK to open ReaPack and install it. After ReaPack opens, find '" .. filter_name .. "' in the list and click 'Install' or 'Update'.", "Attention", 1)
      if retval == 1 then
        reaper.ReaPack_AddSetRepository("ReaTeam Extensions", "https://github.com/ReaTeam/Extensions/raw/master/index.xml", true, 2)
        reaper.ReaPack_ProcessQueue(true)
        reaper.ReaPack_BrowsePackages(filter_name)
        return true
      end
    end
    return false
end
  
function check_exts()
    local js_installed = check_and_install_extension("JS_ReaScriptAPI", "JS_ReaScriptAPI")
    local sws_installed = check_and_install_extension("SWS", "SWS")
    return js_installed or sws_installed
end

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

function update_params(old_params, settings_file)
    local new_params = get_parameter("MAIN", settings_file)
    if new_params == nil then
        return old_params
    end
    for k, v in pairs(new_params) do
        if old_params[k] ~= nil then
            old_params[k] = v
        end
    end
    return old_params
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

function get_param_ini(param)
    local param_val = ""
    if rtk.os.windows then
        _, param_val = reaper.BR_Win32_GetPrivateProfileString("REAPER", param, "", ini_path) --defrenderpath or autosavedir
    elseif rtk.os.mac or rtk.os.linux then
        _, param_val = reaper.get_config_var_string(param)
    end
    return param_val
end

function get_recent_projects(ini_path)
    local p = 0
    local all_paths_list = {}
    repeat
        p = p + 1
        local _, value = reaper.BR_Win32_GetPrivateProfileString("recent", "recent" .. string.format("%02d", p), "noEntry", ini_path)
    until value == "noEntry"
    for i = p - 1, 1, -1 do
        local _, path = reaper.BR_Win32_GetPrivateProfileString("recent", "recent" .. string.format("%02d", i), "", ini_path)
        local form_size, form_date, clean_date, clean_size = get_file_info(path) 
        if form_size ~= nil then
            table.insert(all_paths_list, path)
        end
    end
    return all_paths_list
end

function get_all_paths(all_paths_list)
    local all_paths = {}
    local index = 1
    for _, path in ipairs(all_paths_list) do
        local clean_name, directory = extract_name(path)
        local form_size, form_date, clean_date, clean_size = get_file_info(path) 
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
                return new_paths[a].idx < new_paths[b].idx
            else
                return new_paths[a].idx > new_paths[b].idx
            end
        elseif sort_type == "az" then
            if direction == 1 then
                return new_paths[a].filename:lower() < new_paths[b].filename:lower()
            else
                return new_paths[a].filename:lower() > new_paths[b].filename:lower()
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

function update_defrender_path()
    local defrender_path = MAIN_PARAMS.general_media_path[2]
    local param_ini = get_param_ini('defrenderpath')
    if (defrender_path == nil or defrender_path == "") and param_ini ~= nil and param_ini ~= "" then
        MAIN_PARAMS.general_media_path[2] = param_ini
        defrender_path = MAIN_PARAMS.general_media_path[2]
    end
    return defrender_path
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

function check_rpp_files(dirPath)
    local rppFiles = {}
    local i, j = 0, 0

    while true do
        local fileName = reaper.EnumerateFiles(dirPath, i)
        if fileName then
            if fileName:lower():match("%.rpp$") then
                local filePath = dirPath .. "\\" .. fileName
                table.insert(rppFiles, filePath)
            end
            i = i + 1
        else
            local dirName = reaper.EnumerateSubdirectories(dirPath, j)
            if dirName then
                local subDirPath = dirPath .. "\\" .. dirName
                if reaper.EnumerateFiles(subDirPath, 0) or reaper.EnumerateSubdirectories(subDirPath, 0) then
                    local subDirFiles = check_rpp_files(subDirPath)
                    for _, file in ipairs(subDirFiles) do
                        table.insert(rppFiles, file)
                    end
                end
                j = j + 1
            else
                break
            end
        end
    end
    return rppFiles
end



function check_and_create_files(dirPath)
    for _, fileName in ipairs(data_files) do
        local filePath = dirPath .. "\\" .. fileName
        local file = io.open(filePath, "r")

        if file then
            file:close()
        else
            file = io.open(filePath, "w")
            if file then
                print("Файл " .. filePath .. " успешно создан.")
                file:close()
            else
                print("Не удалось создать файл " .. filePath)
            end
        end
    end
end
------------------------------------------------------------------------
------------------------------------------------------------------------
------------------------------------------------------------------------

function get_selected_path()
    local selected_paths = {}
    for i, path in ipairs(sorted_paths) do
        local n = new_paths[path]
        if n.sel == 1 then 
            table.insert(selected_paths, n.path)
        end
    end
    return selected_paths
end


function unselect_all_path(BG_COL)
    for i, path in ipairs(sorted_paths) do
        local n = new_paths[path]
        local odd_col_bg = i % 2 == 0 and '#3a3a3a' or '#323232'
        recolor(n.cont.refs.bg_spacer, odd_col_bg, odd_col_bg)
        n.sel = 0
    end                  
end

local new_h = 0

function update_heigh_list(dir)
    if TYPE_module == 1 then
        for _, blan in ipairs(sorted_paths) do
            local n = new_paths[blan]
            local h = n.cont.h 
    
            local text_name = n.hbox.refs.text_name
            local text_name2 = n.hbox.refs.path_box.refs.paths
                 
            local wrap = new_h > 45
            text_name:attr('wrap', wrap)
            text_name2:attr('wrap', wrap)
    
            MAIN_PARAMS.heigh_elems = math.floor( math.min(math.max(h + 15 * dir, 20), 100) )
            
            n.cont:animate{'h',dst=MAIN_PARAMS.heigh_elems, duration=0.1, easing="in-quad"} --in quad --out-elastic
            
        end
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
    local cur_mp = CURRENT_media_path
    local gen_mp = GENERAL_media_path[1]
    
    if cur_mp then
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

    if gen_mp then
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
    --print( next(files) )
    --[[
    if INDIVIDUAL_media_path then
        data = get_parameter(dirPath)
        return data
    end]]

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
    GLOBAL_img_path, all_info.DATA.img = resize_image(img_path, CUSTOM_IMAGE_global, merge_filename, DEF_IMG_W, DEF_IMG_H)
    save_parameter(all_info.path, all_info.DATA)
    img:attr('image',CUSTOM_IMAGE_local..merge_filename)
end



function ENTER(self, event)
    self:attr('bg', COL18)
    return true
end

function LEAVE(self, event)
    self:attr('bg', "transparent")
end

function LBM(event)
    if event then
        return event.button == lbm 
    else
        return true 
    end
end

function RBM(event)
    if event then
        return event.button == rbm 
    else
        return true 
    end
end

function update_visibility(data, query, new_paths)
    query = tolower(query, 1)
    local first_visible = nil
    for i, item in ipairs(data) do
        local n = new_paths and new_paths[item] or item
        local path = n.path and tolower(n.path, 1)
        local filename = n.filename and tolower(n.filename, 1)
        local date = n.form_date and tolower(n.form_date, 1)
        n.sel = 0
        
        local tags, comments
        if new_paths then
            tags = n.DATA.tags and tolower(table.concat(n.DATA.tags), 1) or ""
            comments = n.DATA.comments and lower(n.DATA.comments, 1) or ""
        end
        -- find matching
        if path:find(query)
          or filename:find(query)
          or date:find(query)
          or (tags and tags:find(query))
          or (comments and comments:find(query)) then
            if new_paths then
                n.cont:show()
            else
                item:show()
            end
            if not first_visible then
                first_visible = n
            end
        else
            if new_paths then
                n.cont:hide()
            else
                item:hide()
            end
        end
    end
    
    if first_visible then
        update_player(first_visible)
        unselect_all_path()
        first_visible.sel = 1
        recolor(first_visible.cont.refs.bg_spacer, "#8a8a8a", hex_darker("#8a8a8a", 0.2))
    end
end

function get_backups_folder(folder)
    if BACKUPS_CURRENT then
        local folder_name = get_param_ini('autosavedir')
        return folder..folder_name
    end
end

--- function to process a reaper file.
-- @param source_file path to the source file.
-- @return true if the process was successfully completed, otherwise false.
function open_project_recovery(source_file)
    local target_file = string.gsub(source_file, ".rpp$", "[recovery mode].rpp")
    --if not target_file:match("%.rpp$") or target_file:match("%.RPP$") then return false end

    -- copy file
    local source = assert(io.open(source_file, "rb"))
    local content = source:read("*all")
    source:close()
    local target = assert(io.open(target_file, "wb"))
    target:write(content)
    target:close()

    -- modify bypass attribute
    local file = assert(io.open(target_file, "r+"))
    local lines = {}
    local bypass_found = false
    for line in file:lines() do
        if line:match("BYPASS %d %d %d") then
            line = line:gsub("BYPASS %d %d %d", "BYPASS 0 1 0")
            bypass_found = true
        end
        table.insert(lines, line)
    end

    -- if bypass line not found, open file in reaper and exit function
    if not bypass_found then
        reaper.Main_openProject(target_file)
        return false
    end
    -- write updated content back to file
    reaper.Main_OnCommand(41929, 0)
    file:seek("set")
    for _, line in ipairs(lines) do file:write(line, "\n") end
    file:close()
    
    -- open file in reaper and delete it
    reaper.Main_openProject(target_file)
    os.remove(target_file)

    return true
end


