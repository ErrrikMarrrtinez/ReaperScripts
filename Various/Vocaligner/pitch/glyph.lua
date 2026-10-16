-- @noindex
local import=...;local Wave=import('pitch/waveform');local M={}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
-- Absolute pitch, independent of viewport and selection. Fractional pitch
-- changes interpolate between palette stops every five semitones.
function M.color(p,selected,alpha)
  local stops={{65,115,223},{154,83,216},{237,87,136},{233,68,64},{244,153,65}}
  local u=((p-48)/5)%8;if u>4 then u=8-u end
  local i=math.min(4,math.floor(u)+1);u=u-i+1;u=u*u*(3-2*u)
  local rgb={};for k=1,3 do local c=stops[i][k]*(1-u)+stops[i+1][k]*u;rgb[k]=math.floor(c+(selected and (255-c)*.23 or 0)+.5) end
  return rgb[1]<<24|rgb[2]<<16|rgb[3]<<8|(alpha or 255)
end
-- One small cached silhouette per visible note. Source min/max retains the
-- broad envelope; a short symmetric kernel removes screen-column ribbing.
function M.shape(cache,key,data,a,b,start,span,width)
  local prior=cache[key]
  if prior and prior.data==data and prior.frames==data.frames and prior.count==#data.frames and prior.a==a and prior.b==b and prior.start==start and prior.span==span and prior.width==width then return prior end
  local scale=width/span;local lo,hi=Wave.range(data,a,b);local gain=1/math.max(.001,math.abs(lo),math.abs(hi))
  local first,last=math.max(a,start),math.min(b,start+span)
  local length=math.max(0,(last-first)*scale);local count=math.max(2,math.ceil(length/3))
  local raw={};local step=(last-first)/count
  for i=-2,count+2 do
    local t=clamp(first+i*step,a,b)
    local l,h=Wave.range(data,math.max(a,t-step*.65),math.min(b,t+step*.65))
    raw[i]={math.max(0,h)*gain,math.max(0,-l)*gain}
  end
  local out={data=data,frames=data.frames,count=#data.frames,a=a,b=b,start=start,span=span,width=width}
  for i=0,count do
    local upper,lower=0,0
    for k=-2,2 do local w=3-math.abs(k);upper=upper+raw[i+k][1]*w/9;lower=lower+raw[i+k][2]*w/9 end
    local t=first+i*step
    -- Rounded end caps span only a few pixels; cuts at viewport edges do not taper.
    local edge=clamp(math.min((t-a)*scale,(b-t)*scale)/3.5,0,1)
    local cap=math.sqrt(math.max(0,1-(1-edge)^2))
    out[#out+1]={t=t,upper=upper*cap,lower=lower*cap}
  end
  cache[key]=out;return out
end
function M.draw(im,dl,shape,tx,yy,half,color,hover,outline)
  if #shape<2 then return end
  local points={};local area=0
  local function add(x,y)
    local p=points[#points];if not p or x~=p[1] or y~=p[2]then points[#points+1]={x,y}end
  end
  for _,p in ipairs(shape)do add(tx(p.t),yy-p.upper*half);area=area+p.upper+p.lower end
  for i=#shape,1,-1 do local p=shape[i];add(tx(p.t),yy+p.lower*half) end
  if #points>1 and points[1][1]==points[#points][1] and points[1][2]==points[#points][2]then table.remove(points)end
  if #points<3 or area<1e-8 then return end
  local function stroke(col,thick)
    if im.DrawList_PathStroke then
      im.DrawList_PathClear(dl);for _,p in ipairs(points)do im.DrawList_PathLineTo(dl,p[1],p[2])end
      im.DrawList_PathStroke(dl,col,im.DrawFlags_Closed or 1,thick)
    else
      for i=1,#points do local a,b=points[i],points[i%#points+1];im.DrawList_AddLine(dl,a[1],a[2],b[1],b[2],col,thick) end
    end
  end
  -- Halo behind the fill; unlike a rectangle it follows each rounded lobe.
  if hover then stroke(0xBEC5CEA0,2) end
  im.DrawList_PathClear(dl);for _,p in ipairs(points)do im.DrawList_PathLineTo(dl,p[1],p[2]) end
  im.DrawList_PathFillConcave(dl,color)
  if outline then stroke(outline,1) end
end
return M
