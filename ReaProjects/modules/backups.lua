--@noindex
--NoIndex: true

function create_backups()
local dir_path = PROJECT_PATH_BACKUPS

local files_by_date = {}

local visible_widgets = {}
local entry_backups
local dates_texts={}
local hpadding_tree = 5
local max_visible = 150
local main_vbox_backups
local files_hbox_main
local buttons_boxes

local cyrillic_chars = {
    "а", "б", "в", "г", "д", "е", "ё", "ж", "з", "и", "й", "к", "л", "м", "н", "о", "п", "р", "с", "т", "у", "ф", "х", "ц", "ч", "ш", "щ", "ъ", "ы", "ь", "э", "ю", "я",
    "А", "Б", "В", "Г", "Д", "Е", "Ё", "Ж", "З", "И", "Й", "К", "Л", "М", "Н", "О", "П", "Р", "С", "Т", "У", "Ф", "Х", "Ц", "Ч", "Ш", "Щ", "Ъ", "Ы", "Ь", "Э", "Ю", "Я"
}

local month_names = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"} 

local sort_type = "date>"

local function get_file_info(file_path)
    local retval, size, _, modified_time, _, _, _, _, _, _, _, _ = reaper.JS_File_Stat(file_path)
    if retval == 0 then
        local year, month, day, hour, min, sec = string.match(modified_time, "(%d%d%d%d)%.(%d%d)%.(%d%d) (%d%d):(%d%d):(%d%d)")
        month = month_names[tonumber(month)]
        year = string.sub(year, 3)
        local modified_date = day .. " " .. month .. " " .. year .. ", " .. hour .. ":" .. min
        local total_size
        local size_clear = size
        if size >= 1024 * 1024 * 1024 then
            total_size = string.format("%.2f GB", size / (1024 * 1024 * 1024))
        elseif size >= 1024 * 1024 then
            total_size = string.format("%.2f MB", size / (1024 * 1024))
        else
            total_size = string.format("%.2f KB", size / 1024)
        end
        
        return total_size, modified_date, modified_time, size_clear
    else 
        return "", "" 
    end
end

local function process_directory(dir_path)
    local file_paths = {}
    local file_dates = {}
    local file_sizes = {}
    local file_sizes_clear = {}
    local clear_dates = {}
    local i = 0
    while true do
        local file_name = reaper.EnumerateFiles(dir_path, i)
        if file_name == nil then
            break
        end
        if string.match(file_name, "%.rpp%-bak$") then
            local file_path = dir_path .. "\\" .. file_name
            local total_size, modified_date, modified_time, size_clear = get_file_info(file_path)
            table.insert(file_paths, file_path)
            table.insert(file_dates, modified_date)
            table.insert(file_sizes, total_size)
            table.insert(file_sizes_clear, size_clear)
            table.insert(clear_dates, modified_time)
            
        end
        i = i + 1
    end
    
    i = 0
    while true do
        local dir_name = reaper.EnumerateSubdirectories(dir_path, i)
        if dir_name == nil then
            break
        end
        local sub_file_paths, sub_file_dates, sub_file_sizes, new_clear_dates, file_sizes_clear = process_directory(dir_path .. "\\" .. dir_name)
        for j = 1, #sub_file_paths do
            table.insert(file_paths, sub_file_paths[j])
            table.insert(file_dates, sub_file_dates[j])
            table.insert(file_sizes, sub_file_sizes[j])
        end
        i = i + 1
    end
    
    return file_paths, file_dates, file_sizes, clear_dates, file_sizes_clear
end

local function ent(self, event)
    self:attr('bg', "#7a7a7a")
    return true
end

local function lea(self, event)
    self:attr('bg', false)
    return true
end

local function get_or_create(t, ...)
    local keys = {...}
    for i = 1, #keys do
        local key = keys[i]
        if not t[key] then
            t[key] = {}
        end
        t = t[key]
    end
    return t
end

function split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

function extract_filename(str)
    local name = string.match(str, "^(.*)%-%d%d%d%d%-%d%d%-%d%d")
    if name then
        if name:sub(-1) == "-" then
            return name:sub(1, -2)
        else
            return name
        end
    else
        name = string.match(str, "^(.*)%-%d%d%d%d%-%d%d%-%d%d_%d%d%d%d")
        if name then
            if name:sub(-1) == "-" then
                return name:sub(1, -2)
            else
                return name
            end
        else
            return str
        end
    end
end

local function sorted_pairs(t)
    local keys = {}
    for k in pairs(t) do
        table.insert(keys, k)
    end
    local all_numeric = true
    for _, k in ipairs(keys) do
        if type(k) ~= "number" then
            all_numeric = false
            break
        end
    end
    if all_numeric then
        table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
    else
        table.sort(keys)
    end
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

function remove_str(inputstr)
    local parts = split(inputstr, "_")
    local depth = #parts
    if depth == 1 then
        return false
    else
        table.remove(parts)
        return table.concat(parts, "_")
    end
end

function collect_backups()

    local file_paths, file_dates, file_sizes, clear_dates, file_sizes_clear = process_directory(dir_path)
    
    for i = 1, #file_paths do
        local file_name = string.match(file_paths[i], "[^\\]+$")
        local clean_name = string.match(file_name, "^[^-]+")
        local day, month, year, time = string.match(file_dates[i], "(%d%d) (.*) (%d%d), (%d%d:%d%d)")
        local hour, minute = string.match(time, "(%d%d):(%d%d)")
        local files = get_or_create(files_by_date, year, month, day, hour)
        table.insert(files, {name = file_name, path = file_paths[i], size = file_sizes[i], time = minute, date = file_dates[i], date_cl = clear_dates[i], size_clear=file_sizes_clear[i]})
    end

end

local function add_file_to_widget(file, files_hbox_main, bol, filedate, clear_date)
    local text_file_box = files_hbox_main:add(rtk.HBox{onmouseenter=ent,onmouseleave=lea,})
    
    local text_name_file = text_file_box:add(rtk.Text{text=extract_filename(file.name)},{fillw=true})
    --local text_path_file = text_file_box:add(rtk.Text{minw=80,w=0.1,halign='right',text= file.path},{fillw=true})
    local text_date_file = text_file_box:add(rtk.Text{minw=110,w=0.1,halign='center',text=filedate},{})
    local text_size_file = text_file_box:add(rtk.Text{minw=75,w=0.1,text=file.size,halign='right'},{halign='right', align='right'})
    
    
    
    text_file_box.filenames = file.name 
    text_file_box.text = text_name_file.text 
    text_file_box.date = filedate 
    text_file_box.size = file.size
    text_file_box.clear_date = clear_date
    
    
    
    local menu = rtk.NativeMenu()
    
    menu:set({
        {'Open project       ', id='open_project'},
        {'Open project(recovery)', id='open_recovery'},
        {'Open path', id='project_path'},
        
        rtk.NativeMenu.SEPARATOR,
        {'Show all projects ' .. '"' .. text_name_file.text  .. '"' , id='project_all'},
    })
    
    text_file_box.onclick = function(self, event)
        if event.button == rtk.mouse.BUTTON_RIGHT then
            --menu:open_at_mouse():done(function(item)
            menu:open_at_widget(text_file_box, "center", "bottom"):done(function(item)
                if not item then
                    
                    return
                end
                if item.id == 'open_project' then
                    reaper.Main_openProject(file.path)
                elseif item.id == 'project_path' then
                    reaper.CF_LocateInExplorer(file.path)
                elseif item.id == 'open_recovery' then
                    open_project_recovery(file.path)
                elseif item.id == 'project_all' then
                
                    visible_widgets = {}
                    files_hbox_main:remove_all()
                    add_files_by_date_and_depth("")
                    
                    entry_backups:clear()
                    entry_backups:insert(text_name_file.text )
                    --tree_widgets()
                end
            end)
        end
    end
    table.insert(visible_widgets, text_file_box)
end

function string_to_time(date_string)
    local pattern = "(%d+)%.(%d+)%.(%d+) (%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = date_string:match(pattern)
    local pop =  os.time({year=year, month=month, day=day, hour=hour, min=min, sec=sec})
    return pop
end

function date_to_seconds(date_string)
    local pattern = "(%d+)%.(%d+)%.(%d+) (%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = date_string:match(pattern)
    local time_table = {year=tonumber(year), month=tonumber(month), day=tonumber(day), hour=tonumber(hour), min=tonumber(min), sec=tonumber(sec)}
    local time_in_seconds = os.time(time_table)
    return time_in_seconds
end

function sort_files_by_date(files)
    
    table.sort(files, function(a, b)
        
        return date_to_seconds(a.date_cl) > date_to_seconds(b.date_cl)
        
    end)
end

function sort_files_by_size(files)
    table.sort(files, function(a, b)
        return tonumber(a.size_clear) > tonumber(b.size_clear)
    end)
end
--az
function sort_files_by_name_asc(files)
    table.sort(files, function(a, b)
        return a.name < b.name
    end)
end
--za
function sort_files_by_name_desc(files)
    table.sort(files, function(a, b)
        return a.name > b.name
    end)
end

function sort_files_by_date_asc(files)
    table.sort(files, function(a, b)
        return date_to_seconds(a.date_cl) < date_to_seconds(b.date_cl)
    end)
end

function sort_files_by_date_desc(files)
    table.sort(files, function(a, b)
        return date_to_seconds(a.date_cl) > date_to_seconds(b.date_cl)
    end)
end

function sort_files_by_size_asc(files)
    table.sort(files, function(a, b)
        return tonumber(a.size_clear) < tonumber(b.size_clear)
    end)
end

function add_files_by_date_and_depth(target_date, unit, period)
    local current_date = {}
    local files_to_add = {}
    local current_depth = 1
    local date_part = {'year', 'month', 'day', 'hour'} 
    local current_time = os.time()
    local time_units = {second = 1, minute = 60, hour = 3600, day = 86400, month = 2592000, year = 31104000}
    local period_time = period and period * time_units[unit]

    local function recurse(files_by_date, current_depth)
        for key, value in sorted_pairs(files_by_date) do
            current_date[date_part[current_depth]] = key
            if current_depth == #date_part then

                if (target_date[1] == nil or current_date.year == target_date[1]) and
                   (target_date[2] == nil or current_date.month == target_date[2]) and
                   (target_date[3] == nil or current_date.day == target_date[3]) and
                   (target_date[4] == nil or current_date.hour == target_date[4]) then
                    for i = 1, #value do
                        local file = value[i]
                        local file_time = string_to_time(file.date_cl)
                        if period and current_time - file_time > period_time then
                            goto continue
                        end
                        
                        table.insert(files_to_add, file) 
                        ::continue::
                    end
                end
            else
                recurse(value, current_depth + 1)
            end
        end
    end
    recurse(files_by_date, current_depth)
    
    if sort_type == "date<" then
        sort_files_by_date_asc(files_to_add)
    elseif sort_type == "date>" then
        sort_files_by_date_desc(files_to_add)
    elseif sort_type == "size<" then
        sort_files_by_size_asc(files_to_add)
    elseif sort_type == "size>" then
        sort_files_by_size(files_to_add)
    elseif sort_type == "az" then
        sort_files_by_name_asc(files_to_add)
    elseif sort_type == "za" then
        sort_files_by_name_desc(files_to_add)
    end
    

    for i = 1, #files_to_add do
        add_file_to_widget(files_to_add[i], files_hbox_main, true, files_to_add[i].date, files_to_add[i].date_cl)
    end
end

function filter_widgets1(visible_widgets, time_unit, time_value)
    local current_time = os.time()

    -- Делаем видимыми все виджеты
    for i, ind in ipairs(visible_widgets) do
        ind:show()
    end

    -- Применяем критерии времени для фильтрации
    for i, ind in ipairs(visible_widgets) do
        local widget_time = date_to_seconds(ind.clear_date)
        local time_difference = os.difftime(current_time, widget_time)

        -- Переводим разницу во времени в нужные единицы
        if time_unit == "minute" then
            time_difference = time_difference / 60
        elseif time_unit == "hour" then
            time_difference = time_difference / 3600
        elseif time_unit == "day" then
            time_difference = time_difference / 86400
        elseif time_unit == "month" then
            time_difference = time_difference / (86400 * 30)
        elseif time_unit == "year" then
            time_difference = time_difference / (86400 * 365)
        end

        -- Скрываем виджет, если он не соответствует критериям
        if time_difference > tonumber(time_value) then
            ind:hide()
        end
    end
end


function create_onclick_checks(box, self, key)
    return function(self, event)
        if box ~= nil then 
            for iz, days in ipairs(box.children) do
                for za, eb in ipairs(days) do
                    if za < 2 and iz > 1 then
                        
                        eb:toggle()
                        self:get_child(1):attr('text', (eb.visible and ' ▼ ' or ' ▶ ')) 
                        
                    end
                end
            end
        end
        visible_widgets = {}
        files_hbox_main:remove_all()
        
        local tick_text = self:get_child(1) 
        local date_text = self:get_child(2) 
        if tick_text.text == " ▶ " then
            
            local new_key = remove_str(key)
            
            if not new_key then -- скрыты все года\показать всё
                add_files_by_date_and_depth("")
                tick_text:attr('bg', new_key)
                date_text:attr('bg', new_key)
            else --показать предыдущий уровень
                add_files_by_date_and_depth(split(new_key, "_"))
                tick_text:attr('bg', false)
                date_text:attr('bg', false)
                for i, blan in ipairs(dates_texts) do if blan then blan:attr('bg', false) end end
 
            end
        elseif tick_text.text == " ▼ " then
            tick_text:attr('bg', "#E4ABCA50")
            date_text:attr('bg', "#4a4a4a")
            add_files_by_date_and_depth(split(key, "_"))
            
        else
            
            add_files_by_date_and_depth(split(key, "_"))
            date_text = self:get_child(1) 
            
            table.insert(dates_texts, date_text)
            for i, blan in ipairs(dates_texts) do
                blan:attr('bg', false)
            end
            
            date_text:attr('bg', '#7a7a7a')
            --date_text:attr('text', date_text.text .. " ⏲" )
        end

        for j, kak in ipairs(visible_widgets) do
            --print(kak)
            
        end
        entry_backups:focus()
    end
end

function tree_widgets()
    buttons_boxes:remove_all()
    function create_boxes(parent, key, text, lmargin, arrow, h)
        local vbox = parent:add(rtk.VBox{spacing=2,ref=child},{})
        local hbox = vbox:add(rtk.HBox{onmouseenter=ent,onmouseleave=lea,border='#4a4a4a',lmargin=lmargin,},{})
        if arrow then
            hbox:add(rtk.Text{padding=hpadding_tree," ▶ "},{valign='center',alpha=0.1})
        end
        hbox:add(rtk.Text{spacing=20,halign=h,padding=hpadding_tree,text=text}, {fillw=true})
        
        hbox.onclick = create_onclick_checks(vbox, text, key)
        
        return vbox
    end
    
    for year, yearTable in sorted_pairs(files_by_date) do
        local VBOXY_YEAR = create_boxes(buttons_boxes, year, "20" .. year, 0, true, 'center')
        for month, monthTable in sorted_pairs(yearTable) do
            local VBOXY_MONTH = create_boxes(VBOXY_YEAR, year .. "_" .. month, month, 30, true, 'center')
            VBOXY_MONTH:toggle()
            for day, dayTable in sorted_pairs(monthTable) do
                local VBOXY_DAY = create_boxes(VBOXY_MONTH, year .. "_" .. month .. "_" .. day, day, 30*2, true, 'center')
                VBOXY_DAY:toggle()
                for hour, files in sorted_pairs(dayTable) do
                    local VBOXY_HOUR = create_boxes(VBOXY_DAY, year .. "_" .. month  .. "_" ..  day .. "_" .. hour, hour .. ":00", 30*3, false, 'center')
                    VBOXY_HOUR:toggle()
                end
            end
        end
    end
end

function toLowerCase(str)
    local lower_ru = {
        ["А"] = "а", ["Б"] = "б", ["В"] = "в", ["Г"] = "г", ["Д"] = "д", ["Е"] = "е", ["Ё"] = "ё", ["Ж"] = "ж", ["З"] = "з", ["И"] = "и", ["Й"] = "й", ["К"] = "к", ["Л"] = "л", ["М"] = "м", ["Н"] = "н", ["О"] = "о", ["П"] = "п", ["Р"] = "р", ["С"] = "с", ["Т"] = "т", ["У"] = "у", ["Ф"] = "ф", ["Х"] = "х", ["Ц"] = "ц", ["Ч"] = "ч", ["Ш"] = "ш", ["Щ"] = "щ", ["Ъ"] = "ъ", ["Ы"] = "ы", ["Ь"] = "ь", ["Э"] = "э", ["Ю"] = "ю", ["Я"] = "я"
    }
    local result = ""
    for uchar in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
        local l = lower_ru[uchar] or string.lower(uchar)
        result = result .. l
    end
    return result
end

function filterProjects(query)
    local filteredProjects = {}
    for _, project in ipairs(visible_widgets) do
        --print(project.date)
        local dataDateFind = toLowerCase(project.filenames):find(toLowerCase(query))
        local dirFind = toLowerCase(project.text):find(toLowerCase(query))
        local filenameFind = toLowerCase(project.date):find(toLowerCase(query))
        if (filenameFind and filenameFind > 0) or 
           (dirFind and dirFind > 0) or 
           (dataDateFind and dataDateFind > 0) then
            table.insert(filteredProjects, project)
        end
    end
    for i, project in ipairs(filteredProjects) do -- отфильтрованные п
        --print("Project " .. i .. ": " .. project.filename)
    end
    return filteredProjects
end

function update_widgets(filter)
    local filteredProjects = filterProjects(filter)
    for _, project in ipairs(visible_widgets) do
        if _ > max_visible and (filter == nil or filter == '') then
            project:hide()
        else
            project:hide()
        end
    end
    for _, project in ipairs(filteredProjects) do
        project:show()
    end
    return #filteredProjects
end

-- Ваш исходный код

--[[
local app = all_windows:add(rtk.Application())
--local settings = app.toolbar:add(rtk.Button{icon=gear,"Settings   →", flat=true})

local settings = app.toolbar:
     add(
         rtk.Button{
             minw=30,
             halign='center',
             textcolor2="#ffffff99",
             icon=gear,
             "a",
             },{
})  
]]
--[[
-- Добавление функционала
app:add_screen{
    name='main',
    init=function(app, screen)
        screen.widget = main_hbox_backups
        settings.onclick = function()
            app:push_screen('settings')
        end
    end,
}

app:add_screen{
    name='settings',
    init=function(app, screen)
        local vbox = rtk.VBox{}
        for i = 1, 10 do
            vbox:add(rtk.Button{tostring(i)})
        end
        screen.widget = vbox
        screen.toolbar = rtk.Button{'←   Back', flat=true}
        screen.toolbar.onclick = function()
            app:pop_screen()
        end
    end,
}



local win = rtk.Window{
    w=650, 
    h=600, 
    padding=10,
    opacity=0.98
} 

win:open()
]]


all_windows:remove_all()
local hisect = all_windows:add(rtk.HBox{h=30},{})


hisect:add(rtk.Box.FLEXSPACE)
hisect:add(rtk.Button{'X'})


local main_hbox_backups = all_windows:add(rtk.VBox{padding=10,spacing=5},{})

main_vbox_backups = main_hbox_backups:add(rtk.HBox{h=0.9,spacing=10},{})

local buttons_tree_container = main_vbox_backups:add(rtk.Container{h=0.8,minw=100,w=0.3,border='gray',},{})

local vbox_backups_list_container = main_vbox_backups:add(rtk.VBox{spacing=10},{})
local backups_list_container = vbox_backups_list_container:add(rtk.Container{border='gray',},{fillw=true,})

buttons_boxes = rtk.VBox{padding=2,spacing=2,},{fillw=true,}
files_hbox_main = rtk.VBox{},{fillw=true,}

local vp_tree_dates = buttons_tree_container:
        add(
            rtk.Viewport{
                child = buttons_boxes,
                vscrollbar = false, 
                hscrollbar = false,
                smoothscroll = false,
                scrollbar_size=4,
                h=1
                },{
}) 

local vp_backups = backups_list_container:
        add(
            rtk.Viewport{
                child = files_hbox_main,
                vscrollbar = false, 
                hscrollbar = false,
                smoothscroll = false,
                bg='#7c6a8c10',
                h=0.7
                },{
})



collect_backups()

add_files_by_date_and_depth("")

tree_widgets()


local vbox_down_part = vbox_backups_list_container:add(rtk.VBox{},{fillw=true})
local hbox_entries_line = vbox_down_part:add(rtk.HBox{spacing=5, h=30,},{halign='right',})

math.randomseed(os.time())
local random_day = math.random(1, 28)
local random_month = month_names[math.random(#month_names)]

local vbox_finder = hbox_entries_line:add(rtk.HBox{spacing=5,},{fillh=true,})
local text_per_last = vbox_finder:add(rtk.Text{'Show per last'},{valign='center'},{fillh=true,})
local option_box = vbox_finder:add(rtk.HBox{spacing=5,},{fillh=true,})

--hbox_entries_line:add(rtk.Box.FLEXSPACE)

entry_backups = hbox_entries_line:add(rtk.Entry{placeholder = string.format("%02d %s", random_day, random_month),},{fillw=true, fillh=true})entry_backups:focus()
--local find_backups_button = hbox_entries_line:add(rtk.Button{pading=3,"Find"},{fillh=true})


local sort_options = hbox_entries_line:add(rtk.OptionMenu{
    menu={
        {label=' ▲ Date', id='date<'},
        {label=' ▼ Date', id='date>'},
        {label=' ▲ Size', id='size<'},
        {label=' ▼ Size', id='size>'},
        --{label='Имя (A-Z)', id='az'},
        --{label='Имя (Z-A)', id='za'},
    },
    selected=sort_type,
    padding=3,
    x=5
}, {fillh=true})

sort_options.onchange = function(self, item)
    sort_type = item.id
    visible_widgets = {}
    files_hbox_main:remove_all()
    add_files_by_date_and_depth("")
end


entry_backups.onchange = function(self, event)
    query = self.value
    local result_time = filterProjects("")
    local filter_projects = update_widgets(query)
end

entry_backups.onkeypress = function(self, event)
     local new_char = utf8.char(("0x%08x"):format(event.keycode & 0x0000FFFF))
     for _, char in ipairs(cyrillic_chars) do
         if new_char == char then
             self:delete()
             self:insert(new_char)
             break
         end
     end
     if event.keycode == rtk.keycodes.BACKSPACE then
         local value = self.value
         if value and #value > 0 then
             local byteoffset = utf8.offset(value, -1)
             if byteoffset then
                 -- sub удаляет из чего-то что-то
                 value = value:sub(1, byteoffset)
                 self:attr('value', value)
             else
                 self:attr('value', "")
             end
         end
    end
end


local new_item = 1
local new_item_id = "hour"

local swap_modes_menu = {
    {label='minute', id='minute', single='minute', plural='minutes'},
    {label='hour', id='hour', single='hour', plural='hours'},
    {label='day', id='day', single='day', plural='days'},
    {label='month', id='month', single='month', plural='months'},
    {label='year', id='year', single='year', plural='years'},
}

local button_swap_modes = rtk.OptionMenu{w=90, menu=swap_modes_menu, selected='hour'}

local function update_label_pluralization(optionMenu, count)
    local item = swap_modes_menu[optionMenu.selected_index]
    optionMenu:attr('label', count <= 1 and item.single or item.plural)
    
end

local function cycle_option_menu_selection(menu, direction)
    local new_index = menu.selected_index + direction
    if new_index < 1 then
        new_index = #menu.menu
    elseif new_index > #menu.menu then
        new_index = 1
    end
    menu.selected_index = new_index
    menu:select(menu.menu[new_index].id)
end

local function add_mouse_wheel_handler(optionMenu)
    optionMenu.onmousewheel = function(self, event)
        local direction = event.wheel > 0 and -1 or 1
        cycle_option_menu_selection(self, direction)
        return true -- To indicate the event was handled
    end
end

function update_button_h_modes(mode)
    local h_modes_menu = {}
    local range = {minute=59, hour=24, day=30, month=12, year=17}
    for i=1, range[mode] or 0 do
        table.insert(h_modes_menu, {label=tostring(i), id=tostring(i)})
    end
    option_box:remove_all(2)
    local button_h_modes = rtk.OptionMenu{halign='center', w=63, menu=h_modes_menu, selected=h_modes_menu[1].id}
    
    button_h_modes.onchange = function(self, item)
        update_label_pluralization(button_swap_modes, tonumber(item.id))
        new_item = item.id 

        filter_widgets1(visible_widgets, new_item_id, new_item)
    end

    add_mouse_wheel_handler(button_h_modes)

    option_box:add(button_h_modes, {fillh=true})
    option_box:add(button_swap_modes, {fillh=true})
    
    update_label_pluralization(button_swap_modes, tonumber(button_h_modes.selected))
end

button_swap_modes.onchange = function(self, item)
    update_button_h_modes(item.id)
    new_item = 1
    new_item_id = item.id
    --print(new_item, item.id)
    --files_hbox_main:remove_all()
    --print(item.id)
    --add_files_by_date_and_depth("", item.id, new_item)
    filter_widgets1(visible_widgets, item.id, new_item)
    
end


add_mouse_wheel_handler(button_swap_modes)
add_mouse_wheel_handler(sort_options)


update_button_h_modes('hour')
end
