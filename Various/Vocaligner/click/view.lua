-- @noindex
-- Overview uses cached peak features; sample zoom reads only the visible PCM.
local M={}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
function M.focus(c,index)
 local e=c.events[index];if not e or not c.s then return end
 c.selected_event=index;c.wave_view={span=math.min(c.s.pcm.len,math.max(.006,(e.finish-e.start)*2.5))}
 c.wave_view.start=clamp((e.start+e.finish-c.wave_view.span)/2,0,c.s.pcm.len-c.wave_view.span)
end
local function samples(s,first,last)
 local out={}
 for bi=math.floor(first/s.pcm.block_size)+1,math.floor(last/s.pcm.block_size)+1 do
  local b=s.pcm.blocks[bi]
  if b then
   local a,z=math.max(first,b.first),math.min(last,b.first+b.count-1)
   local values=b.buffer.table((a-b.first)*s.channels+1,(z-a+1)*s.channels)
   for i=a,z do out[i]=values[(i-a)*s.channels+1]end
  end
 end
 return out
end
function M.draw(im,ctx,c,width,height)
 local s=c.s
 if not s then im.TextDisabled(ctx,'Analyze an item to display the waveform and detected regions.');return end
 if c.wave_source~=s then c.wave_source=s;c.wave_view={start=0,span=s.pcm.len};c.wave_cache=nil end
 local v=c.wave_view
 if im.Button(ctx,'Fit waveform')then v.start=0;v.span=s.pcm.len end
 im.SameLine(ctx)
 if im.Button(ctx,'Previous click')then M.focus(c,math.max(1,(c.selected_event or 2)-1));v=c.wave_view end
 im.SameLine(ctx)
 if im.Button(ctx,'Next click')then M.focus(c,math.min(#c.events,(c.selected_event or 0)+1));v=c.wave_view end
 im.TextDisabled(ctx,'Wheel: zoom | middle drag: pan | double click a zone: focus | right click: keep sound')
 im.TextDisabled(ctx,'Grey: original linked peaks | green: replacement on channel 1 | sample zoom: channel 1')
 local x,y=im.GetCursorScreenPos(ctx);local dl=im.GetWindowDrawList(ctx)
 width=math.max(100,width)
 im.InvisibleButton(ctx,'##click_wave',width,height,im.ButtonFlags_MouseButtonLeft|im.ButtonFlags_MouseButtonRight|im.ButtonFlags_MouseButtonMiddle)
 local hover=im.IsItemHovered(ctx);local mx=im.GetMousePos(ctx)
 if hover then
  local wheel=im.GetMouseWheel(ctx)
  if wheel~=0 then local f=clamp((mx-x)/width,0,1);local span=clamp(v.span*1.5^(-wheel),16/s.sr,s.pcm.len);v.start=v.start+f*(v.span-span);v.span=span end
 end
 if im.IsItemActive(ctx) and im.IsMouseDragging(ctx,2,2)then local dx=im.GetMouseDelta(ctx);v.start=v.start-dx*v.span/width end
 v.start=clamp(v.start,0,s.pcm.len-v.span)
 im.DrawList_AddRectFilled(dl,x,y,x+width,y+height,0x171B22FF,5)
 im.DrawList_PushClipRect(dl,x,y,x+width,y+height,true)
 local function px(t)return x+(t-v.start)/v.span*width end
 local hit
 for i,e in ipairs(c.events)do if e.finish>=v.start and e.start<=v.start+v.span then
  local a,b=px(e.start),px(e.finish);local tint=e.excluded and 0x77777744 or c.mode=='mouth' and 0xE5AC5544 or 0x609FE944
  im.DrawList_AddRectFilled(dl,a,y+20,math.max(a+2,b),y+height,tint)
  if i==c.selected_event then im.DrawList_AddRect(dl,a,y+20,math.max(a+2,b),y+height,0xF0C878FF)end
  if mx>=a and mx<=math.max(a+3,b)then hit=i end
 end end
 local key=('%s:%.12f:%.12f:%d'):format(tostring(s),v.start,v.span,math.floor(width))
 if not c.wave_cache or c.wave_cache.key~=key then
  local cache={key=key,peaks={}};c.wave_cache=cache
  if v.span*s.sr<=width*2 then
   cache.first=math.max(0,math.floor(v.start*s.sr));cache.last=math.min(s.count-1,math.ceil((v.start+v.span)*s.sr));cache.samples=samples(s,cache.first,cache.last)
  else
   for col=0,math.floor(width)-1 do
    local a=math.max(1,math.floor((v.start+col*v.span/width)/s.data.hop)+1)
    local b=math.min(#s.data.rows,math.ceil((v.start+(col+1)*v.span/width)/s.data.hop));local peak=0
    for i=a,b do peak=math.max(peak,s.data.rows[i][7])end;cache.peaks[col]=peak
   end
  end
 end
 local cache=c.wave_cache;local peak=.01
 if cache.samples then for _,value in pairs(cache.samples)do peak=math.max(peak,math.abs(value))end
 else for _,value in pairs(cache.peaks)do peak=math.max(peak,value)end end
 local mid=y+height*.55;local gain=(height-35)*.45/peak
 im.DrawList_AddLine(dl,x,mid,x+width,mid,0xFFFFFF20)
 local patch=c.ready and c.patch and c.patch[0] or nil
 if cache.samples then
  for i=cache.first+1,cache.last do
   local a,b=cache.samples[i-1],cache.samples[i];local xa,xb=px((i-1)/s.sr),px(i/s.sr)
   im.DrawList_AddLine(dl,xa,mid-a*gain,xb,mid-b*gain,0xA7B1C5FF,1)
   if patch then local pa,pb=patch[s.first+i-1],patch[s.first+i]
    if pa~=nil or pb~=nil then im.DrawList_AddLine(dl,xa,mid-(pa or a)*gain,xb,mid-(pb or b)*gain,0x64D9A3FF,2)end
   end
  end
 else
  for col,value in pairs(cache.peaks)do im.DrawList_AddLine(dl,x+col,mid-value*gain,x+col,mid+value*gain,0xA7B1C5AA)end
  if patch then
   local bins={}
   for index,value in pairs(patch)do local col=math.floor((index-s.first-s.sr*v.start)/(s.sr*v.span)*width)
    if col>=0 and col<width then local b=bins[col];if b then b[1]=math.min(b[1],value);b[2]=math.max(b[2],value)else bins[col]={value,value}end end
   end
   for col,b in pairs(bins)do im.DrawList_AddLine(dl,x+col,mid-b[1]*gain,x+col,mid-b[2]*gain+.5,0x64D9A3FF,1)end
  end
 end
 for i=0,5 do local t=v.start+v.span*i/5;im.DrawList_AddText(dl,x+width*i/5+3,y+3,0xBDC6D8FF,('%.4f s'):format(t))end
 im.DrawList_PopClipRect(dl)
 if hover and hit then
  local e=c.events[hit];im.SetTooltip(ctx,('%s #%d  %.4f–%.4f s  score %.2f%s'):format(c.mode,hit,e.start,e.finish,e.score or 0,e.excluded and ' (kept)' or ''))
  if im.IsMouseClicked(ctx,0)then c.selected_event=hit end
  if im.IsMouseDoubleClicked(ctx,0)then M.focus(c,hit)end
  if c.ready and not c.job and im.IsMouseClicked(ctx,1)then c:exclude(hit)end
 end
end
return M
