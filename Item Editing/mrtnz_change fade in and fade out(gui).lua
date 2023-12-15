-- @description Change fade in and fade out or crop(gui) 
-- @author mrtnz
-- @version 1.01
-- @about
--   Modification. If you highlight an item,
--   then run the script, then you have
--   script window with a redrawn item,
--   and also which takes into itself
--   the following features:
--       Change the fade-in and fade-out using pinch and drag
--       Mouse cursor in a vertical and horizontal way.
--       By holding down shift, you can slow down this effect.
--
--       Or you can right-click and trim the item according to the set marks
--
--   !!!!!Install MVarious first!!!!!!


local script_path = (select(2, reaper.get_action_context())):match('^(.*[/\\])')
local x, y = reaper.GetMousePosition()
local img_path = script_path .. "../images/cursor.cur"
local rtk_path = script_path .. "../libs/rtk.lua"
local null_cursor = reaper.JS_Mouse_LoadCursorFromFile(img_path)
local rtk = dofile(rtk_path)

SimpleSlider = rtk.class('SimpleSlider', rtk.Spacer)
SimpleSlider.register{
    value = rtk.Attribute{default=0.5},
    color = rtk.Attribute{type='color', default='crimson'},
    minw = 0,
    w=1.0,
    h = 1.0,
    autofocus = true,
}
function SimpleSlider:initialize(attrs, ...)
    rtk.Spacer.initialize(self, attrs, SimpleSlider.attributes.defaults, ...)
end
function get_item_peaks(item, disp_w)
  local take = reaper.GetMediaItemTake(item, 0)
  local source = reaper.GetMediaItemTake_Source(take)
  local nch = reaper.GetMediaSourceNumChannels(source)  
  local pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
  local len = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local disp_w = disp_w < 1 and 1 or disp_w
  local ns = disp_w
  local pr = disp_w/len
  local buf = reaper.new_array(ns * nch * 3)
  local retval = reaper.GetMediaItemTake_Peaks(take, pr, pos, 1, ns, 0, buf)
  local spl_cnt  = (retval & 0xfffff)        
  local ext_type = (retval & 0x1000000)>>24  
  local out_mode = (retval & 0xf00000)>>20   
  return buf, spl_cnt
end

function SimpleSlider:set_from_mouse_y(y)
    local h = self.calc.h - (y - self.clienty)
    self:sync('value', rtk.clamp(h / self.calc.h, 0, 1))
end
function SimpleSlider:set_from_mouse_x(x)
    local w = self.calc.w - (x - self.clientx)
    local value = rtk.clamp(w / self.calc.w, 0, 1)
    
    if math.abs(self.start_value - value) < math.abs(self.end_value - value) then
        self.start_value = value
    else
        self.end_value = value
    end
    
    self:sync('value', value)
end
local item = reaper.GetSelectedMediaItem(0,0)
SimpleSlider.start_value = 0
SimpleSlider.end_value = 1

local function factorial(n)
    local res = 1
    for i = 2, n do
        res = res * i
    end
    return res
end
local function comb(n, k)
    return factorial(n) / (factorial(k) * factorial(n - k))
end
function evaluate_bezier(t)
    local x, y = 0, 0
    local points_to_use = {}
    
    if v_thumb ~= false and v_thumb ~= nil then
        table.insert(points_to_use, self.points[1])
    end
    
    if main_thumb ~= false and main_thumb ~= nil then
        for i = 2, #self.points - 1 do
            table.insert(points_to_use, self.points[i])
        end
    end
    
    if v_thumb ~= false and v_thumb ~= nil then
        table.insert(points_to_use, self.points[#self.points])
    end

    local n = #points_to_use - 1

    for i, point in ipairs(points_to_use) do
        local coef = comb(n, i-1) * (t^(i-1)) * ((1-t)^(n-i+1))
        x = x + coef * point[1]
        y = y + coef * point[2]
    end

    return x, y
end

function SimpleSlider:_handle_draw(offx, offy, alpha, event)
    local calc = self.calc
    local x = offx + calc.x
    local y = offy + calc.y
    self:setcolor(calc.color)
    gfx.a = 0.2
    gfx.rect(x, y, calc.w, calc.h)
    gfx.a = 1.0
    if item then
        local peaks, spl_cnt = get_item_peaks(item, calc.w)
        for i=1,spl_cnt do
            local peak = peaks[i]
            local peak_height_top = (1 - peak) * calc.h / 2
            local peak_height_bottom = (1 + peak) * calc.h / 2
            gfx.line(x + i, y + calc.h - peak_height_top, x + i, y + calc.h - peak_height_bottom)
        end
        gfx.set(1, 0, 0, 0.2)
        gfx.rect(x, y, self.start_value * calc.w, calc.h)
        gfx.rect(x + self.end_value * calc.w, y, (1 - self.end_value) * calc.w, calc.h) 
        
        gfx.set(1, 0, 0) 
        -- Draw cubic curves instead of lines
        local t_start = self.start_value / calc.w
        local t_end = self.end_value / calc.w
        local x_start, y_start = evaluate_bezier(t_start)
        local x_end, y_end = evaluate_bezier(t_end)
        gfx.line(x + x_start * calc.w, y + y_start * calc.h, x + x_end * calc.w, y + y_end * calc.h)
        
        gfx.set(1.0)
        local pos_start = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local len_item = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        
        
        local pos_end = pos_start + len_item
        gfx.x=x+5
        gfx.y=y+5 
       -- gfx.drawstr("Start: " .. string.format("%.3f", pos_start)) 
        gfx.x=x+calc.w-170 
        gfx.y=y+calc.h-20 
       -- gfx.drawstr("End: " .. string.format("%.3f", pos_end)) 
        gfx.x=x+calc.w/2-175 
        gfx.y=y+calc.h/2+95 
        --gfx.drawstr("Length: " .. string.format("%.3f", len_item)) 
        local fade_in_len = reaper.GetMediaItemInfo_Value(item, 'D_FADEINLEN')
        local fade_out_len = reaper.GetMediaItemInfo_Value(item, 'D_FADEOUTLEN')
        gfx.x=x+5 
        gfx.y=y+20 
        gfx.drawstr("Fade In: " .. string.format("%.3f", fade_in_len)) 
        gfx.x=x+calc.w-170 
        gfx.y=y+calc.h-35 
        gfx.drawstr("Fade Out: " .. string.format("%.3f", fade_out_len)) 
    end
end




SimpleSlider.vx = 0
SimpleSlider.vy = 0
SimpleSlider.ax = 0
SimpleSlider.ay = 0


local win=rtk.Window{w=300, h=120, borderless=true, padding=5,expand=2}

new_y = y - (win.h/2)
new_x = x - (win.w/2)
win:attr('x', new_x)
win:attr('y', new_y)

local vbox=win:add(rtk.VBox{y=15,expand=1},{fillh=true,fillw=true})
local a = vbox:add(SimpleSlider{color='gray'}, {fillh=true,fillw=true})
win:open()

function SimpleSlider:_handle_dragmousemove(event, arg)
    local dx = (event.x - arg.lastx) / self.calc.w / 3.5
    local dy = (event.y - arg.lasty) / self.calc.h / 3.5 
    if event.shift then
        dx = dx / 4
        dy = dy / 5
    end
    self.vx = dx
    self.vy = dy
    self.ax = dx 
    self.ay = dy 
    local new_start_value = rtk.clamp(self.start_value + self.vx - self.vy, 0, 1)
    local new_end_value = rtk.clamp(self.end_value + self.vx + self.vy, 0, 1)
    if new_start_value < new_end_value then
        self.start_value = new_start_value
        self.end_value = new_end_value
    else
        self.start_value = new_end_value
        self.end_value = new_start_value
    end
    self:ondraw()
    self:animate{
        attr = 'start_value',
        dst = self.start_value,
        duration = 0.01,
        easing = rtk.easing.quadratic_in_out
    }
    self:animate{
        attr = 'end_value',
        dst = self.end_value,
        duration = 0.01,
        easing = rtk.easing.quadratic_in_out
    }
    arg.lastx = event.x
    arg.lasty = event.y
    if item then
        local len_item = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local fade_in_len = self.start_value * len_item
        local fade_out_len = (1 - self.end_value) * len_item
        reaper.SetMediaItemInfo_Value(item, 'D_FADEINLEN', fade_in_len)
        reaper.SetMediaItemInfo_Value(item, 'D_FADEOUTLEN', fade_out_len)
        reaper.UpdateArrange()
    end
    
end

function SimpleSlider:_handle_dragstart(event, x, y)
    local more_x, more_y = reaper.GetMousePosition()
    more_x1, more_y1 =  more_x, more_y 
    self:attr('cursor', null_cursor)
    return {lastx=x, lasty=y, shift=event.shift}, false 
end 



function SimpleSlider:_handle_dragend(event, arg) 
    self.dragstartx = nil 
    
    reaper.JS_Mouse_SetPosition(more_x1, more_y1)
    if event.button == rtk.mouse.BUTTON_RIGHT then
        if item then
            local pos_item = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
            local len_item = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
            local fade_in_len = self.start_value * len_item
            local fade_out_len = (1 - self.end_value) * len_item
            local new_pos_item = pos_item + fade_in_len
            local new_len_item = len_item - fade_in_len - fade_out_len
           win:close()
            -- Разделяем айтем на две части по границам fade in и fade out
            local item_start = reaper.SplitMediaItem(item, pos_item + fade_in_len)
            local item_end = reaper.SplitMediaItem(item_start, pos_item + fade_in_len + new_len_item)
 
            -- Удаляем ненужные части
            reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), item)
            if item_end then
                reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item_end), item_end)
            end
            item = false
            reaper.SetMediaItemInfo_Value(item_start, 'D_FADEINLEN', 0)
            reaper.SetMediaItemInfo_Value(item_start, 'D_FADEOUTLEN', 0)
            reaper.UpdateArrange()
        end
     end
     win:close()
 end
 