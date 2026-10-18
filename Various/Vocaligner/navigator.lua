-- @noindex
local import=...;local Cleanup=import('cleanup');local DSP=import('dsp');local Transport=import('transport');local M={}
-- Overview coordinates always cover the whole item, independently of main zoom.
function M.draw(im,ctx,d,w,h,r,project)
  local x,y=im.GetCursorScreenPos(ctx);local draw=im.GetWindowDrawList(ctx)
  im.InvisibleButton(ctx,'##deess_overview',w,h)
  im.DrawList_AddRectFilled(draw,x,y,x+w,y+h,0x171A2060,4)
  if not d or not (d.audio or d.quick) or not d.view then return end
  local data,v=d.audio or d.quick,d.view;local scale=math.max(3,d.tool_preview and d.tool_preview.max_db or 0)
  -- Reduction overview: a light 5 px blur and an antialiased outline instead
  -- of one hard bar per pixel.
  local n=math.floor(w);local raw={}
  if d.tool_preview then for px=0,n-1 do raw[px]=math.max(0,Cleanup.value(d.tool_preview,data.len*(px+.5)/w)) end end
  local previous,previous_db
  for px=0,n-1 do
    local sum,count=0,0
    for k=-2,2 do local value=raw[px+k];if value then sum=sum+value;count=count+1 end end
    local db=count>0 and sum/count or 0
    local top=y+h-2-(h-4)*math.min(1,db/scale)
    if db>.01 then im.DrawList_AddLine(draw,x+px+.5,top,x+px+.5,y+h-2,0xD8AC7748) end
    if previous and (db>.01 or previous_db>.01) then im.DrawList_AddLine(draw,x+px-1,previous,x+px,top,0xE6BC88D0,1.2) end
    previous,previous_db=top,db
  end
  local a=x+(v.start-data.pos)/data.len*w;local b=a+v.span/data.len*w
  if im.IsItemHovered(ctx) and im.IsMouseClicked(ctx,0) then
    local mx=im.GetMousePos(ctx)
    d.overview_grab=mx>=a and mx<=b and (mx-a)/w*data.len or v.span/2
  end
  if im.IsItemActive(ctx) and im.IsMouseDown(ctx,0) and d.overview_grab then
    if r then Transport.hold(d,r) end
    local mx=im.GetMousePos(ctx)
    v.start=DSP.clamp(data.pos+(mx-x)/w*data.len-d.overview_grab,data.pos,data.pos+data.len-v.span)
    a=x+(v.start-data.pos)/data.len*w;b=a+v.span/data.len*w
  end
  if im.IsItemHovered(ctx) and im.IsMouseDoubleClicked(ctx,0) then v.start=data.pos;v.span=data.len;a=x;b=x+w end
  if not im.IsMouseDown(ctx,0) then d.overview_grab=nil end
  im.DrawList_AddRectFilled(draw,a,y+1,b,y+h-1,0xC6D4E51A,3)
  im.DrawList_AddRect(draw,a,y+1,b,y+h-1,0xB6C7DC80,3)
  if r then Transport.draw(im,draw,Transport.read(r,project),function(t)return x+(t-data.pos)/data.len*w end,x,x+w,y,y+h) end
end
return M
