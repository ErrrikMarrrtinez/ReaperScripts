-- @noindex
local import=...;local Cleanup=import('cleanup');local M={}
local function inverse(plan,target)
  if plan.hybrid then return import('align/hybrid/plan').inverse(plan,target)end
  local a=plan.markers;local lo,hi=1,#a
  if target<=a[1].target then return a[1].t+target-a[1].target end
  if target>=a[#a].target then return a[#a].t+target-a[#a].target end
  while hi-lo>1 do local mid=(lo+hi)//2;if a[mid].target<=target then lo=mid else hi=mid end end
  return a[lo].t+(a[hi].t-a[lo].t)*(target-a[lo].target)/(a[hi].target-a[lo].target)
end

local function peaks(data)
  return data.peaks or {{hop=data.hop,values={}}}
end
local function legacy(im,ctx,draw,data,plan,x,y,w,h,view,tint,cleanup,highlight)
  if not data then return end
  local levels=peaks(data);local level=levels[1]
  for _,l in ipairs(levels) do if l.hop<=view.span/w then level=l end end
  local origin=0
  local det=data.detail -- детальный уровень на видимое окно (после зума): тоньше базовых пиков
  if det and det.hop<level.hop and det.t0<=view.start-data.pos and det.t1>=view.start+view.span-data.pos then level=det;origin=det.t0 end
  local half=highlight and highlight.half
  local gain=(half and .92 or .45)*h/math.max(.01,(highlight and highlight.peak) or data.peak);local mid=half and y+h or y+h*.5
  local events=highlight and highlight.events or {};local event_index=1
  for px=0,math.floor(w)-1 do
    local a=view.start+view.span*px/w;local b=view.start+view.span*(px+1)/w
    local ta=plan and inverse(plan,a) or a-data.pos;local tb=plan and inverse(plan,b) or b-data.pos
    if tb>=0 and ta<=data.len then
      local first=math.max(1,math.floor((ta-origin)/level.hop)+1);local last=math.min(#level.values,math.floor((tb-origin)/level.hop)+1)
      local lo,hi=0,0;for k=first,last do local p=level.values[k];lo=math.min(lo,p[1]);hi=math.max(hi,p[2]) end
      local reduction=cleanup and 10^(-Cleanup.value(cleanup,(ta+tb)*.5)/20) or 1
      local fill=tint
      while events[event_index] and events[event_index].finish<=ta do event_index=event_index+1 end
      local j=event_index
      while events[j] and events[j].start<tb do
        if not events[j].excluded then fill=highlight.tint;break end
        j=j+1
      end
      if half then hi,lo=math.max(hi,-lo),0 end
      if hi-lo>1e-7 then im.DrawList_AddRectFilled(draw,x+px,mid-hi*gain*reduction,x+px+1,mid-lo*gain*reduction,fill) end
    end
  end
end

function M.draw(im,ctx,draw,data,plan,x,y,w,h,view,tint,cleanup,highlight,use_legacy)
  if use_legacy then return legacy(im,ctx,draw,data,plan,x,y,w,h,view,tint,cleanup,highlight) end
  if not data then return end
  local level=data.peaks and data.peaks[1];if not level then return end
  for _,l in ipairs(data.peaks) do if l.hop<=view.span/w then level=l end end
  local origin=0
  local det=data.detail -- детальный уровень на видимое окно (после зума): тоньше базовых пиков
  if det and det.hop<level.hop and det.t0<=view.start-data.pos and det.t1>=view.start+view.span-data.pos then level=det;origin=det.t0 end
  -- half: one-sided amplitude from the bottom edge, using the full height.
  local half=highlight and highlight.half
  local gain=(half and .92 or .45)*h/math.max(.01,(highlight and highlight.peak) or data.peak);local mid=half and y+h or y+h*.5
  local limit=half and h*.96 or h*.48
  local events=highlight and highlight.events or {};local event_index=1;local prev
  for px=0,math.floor(w)-1 do
    local a=view.start+view.span*px/w;local b=view.start+view.span*(px+1)/w
    local ta=plan and inverse(plan,a) or a-data.pos;local tb=plan and inverse(plan,b) or b-data.pos
    if tb>=0 and ta<=data.len then
      local first=math.max(1,math.floor((ta-origin)/level.hop)+1);local last=math.min(#level.values,math.floor((tb-origin)/level.hop)+1)
      local amplitude=0
      for k=first,last do local p=level.values[k];amplitude=math.max(amplitude,-p[1],p[2]) end
      local reduction=cleanup and 10^(-Cleanup.value(cleanup,(ta+tb)*.5)/20) or 1
      local hh=math.min(limit,amplitude*gain*reduction);local fill=tint
      while events[event_index] and events[event_index].finish<=ta do event_index=event_index+1 end
      local j=event_index
      while events[j] and events[j].start<tb do
        if not events[j].excluded then fill=highlight.tint;break end
        j=j+1
      end
      local alpha=math.floor((fill&255)*.28);local inside=(fill&0xffffff00)|alpha
      im.DrawList_AddLine(draw,x+px,mid-hh,x+px,half and mid or mid+hh,inside)
      if prev then
        im.DrawList_AddLine(draw,x+px-1,mid-prev,x+px,mid-hh,fill)
        if not half then im.DrawList_AddLine(draw,x+px-1,mid+prev,x+px,mid+hh,fill) end
      end
      prev=hh
    else prev=nil end
  end
end
return M
