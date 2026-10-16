-- @noindex
local M={delay=.35,height=4}
-- The slot always participates in layout; only the fill is delayed. A task
-- that finishes before the threshold never flashes or changes canvas height.
function M.visible(job,now)
  return job~=nil and not job.done and not job.cancelled and job.created_at~=nil and now-job.created_at>=M.delay
end
function M.draw(im,ctx,job,r)
  local w=im.GetContentRegionAvail(ctx);local x,y=im.GetCursorScreenPos(ctx)
  im.Dummy(ctx,w,M.height)
  local dl=im.GetWindowDrawList(ctx)
  im.DrawList_AddRectFilled(dl,x,y,x+w,y+M.height,0xFFFFFF08,2)
  local now=r.time_precise()
  if not M.visible(job,now) then return end
  local progress=math.max(0,math.min(1,job.progress or 0))
  if progress>0 then im.DrawList_AddRectFilled(dl,x,y,x+w*progress,y+M.height,0x78C8ADCC,2)
  else
    local fraction=(now-job.created_at)*.65%1;local pos=(1-math.abs(fraction*2-1))*.84
    im.DrawList_AddRectFilled(dl,x+w*pos,y,x+w*(pos+.16),y+M.height,0x78C8ADCC,2)
  end
end
return M
