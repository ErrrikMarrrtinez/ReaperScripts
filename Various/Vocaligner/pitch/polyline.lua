-- @noindex
-- Cached polylines: a contour is split into runs once per view/data state and every frame costs one
-- DrawList_AddPolyline call per run instead of one AddLine per segment (and no per-point Lua work).
local M={}
local function same(c,list,view,offset,ykey)
  return c and c.list==list and c.n==#list and c.offset==offset and c.ykey==ykey and c.start==view.start and c.span==view.span
    and c.top==view.top and c.rows==view.rows and c.left==view.left and c.ty==view.ty and c.width==view.width and c.height==view.height
end
local function build(r,list,ykey,tx,py,thick_a,thick_b,vlo,vhi)
  -- список может покрывать несколько экранов: берём только видимый диапазон времени (+ по точке за краями)
  local i0,i1=1,#list
  if vlo then
    local lo,hi=1,#list
    while lo<hi do local mid=(lo+hi+1)//2;if (list[mid].t or 0)<=vlo then lo=mid else hi=mid-1 end end
    i0=lo
    lo,hi=i0,#list
    while lo<hi do local mid=(lo+hi)//2;if (list[mid].t or 0)>=vhi then hi=mid else lo=mid+1 end end
    i1=hi
  end
  local segs,cur,prev={},nil,nil
  local function close() if cur and #cur.pts>=4 then
    local arr=r.new_array(#cur.pts);for i,v in ipairs(cur.pts)do arr[i]=v end
    segs[#segs+1]={arr=arr,th=cur.th}
  end;cur=nil end
  for idx=i0,i1 do local p=list[idx]
    if prev and p.run and prev.run==p.run then
      local th=(ykey=='pitch' and p.supported and prev.supported) and thick_a or thick_b
      if not cur or cur.th~=th then
        close();cur={th=th,pts={tx(prev.t),py(prev[ykey])}}
      end
      local pts=cur.pts;pts[#pts+1]=tx(p.t);pts[#pts+1]=py(p[ykey])
    else close() end
    prev=p
  end
  close()
  return segs
end
-- cache: table owned by the caller (per slot); view: table with start,span,top,rows,left,ty,width,height of this frame.
-- ykey: 'pitch' or 'raw'. Returns false if the native polyline API is unavailable (caller falls back to AddLine).
function M.stroke(im,dl,r,cache,slot,list,view,offset,ykey,tx,py,col,thick_a,thick_b)
  if not (im.DrawList_AddPolyline and r.new_array) then return false end
  local c=cache[slot]
  if not same(c,list,view,offset,ykey) then
    c={list=list,n=#list,offset=offset,ykey=ykey,start=view.start,span=view.span,top=view.top,rows=view.rows,left=view.left,ty=view.ty,
      width=view.width,height=view.height,segs=build(r,list,ykey,tx,py,thick_a,thick_b,view.start-offset,view.start+view.span-offset)}
    cache[slot]=c
  end
  for _,s in ipairs(c.segs) do im.DrawList_AddPolyline(dl,s.arr,col,0,s.th) end
  return true
end
return M
