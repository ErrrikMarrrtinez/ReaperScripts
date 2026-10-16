-- @noindex
-- One gesture, applied at matching relative times in the selected notes.
local import=...;local Notes=import('pitch/notes');local Curve=import('pitch/curve');local Draw=import('pitch/draw');local Trace=import('pitch/trace');local Scale=import('pitch/scale');local M={}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
function M.count(selected)local count=0;for _,yes in pairs(selected)do if yes then count=count+1 end end;return count end
function M.curve(e,d,mx,delta,alt)
  local original=d.base or d.before.notes;local ref;for _,n in ipairs(original)do if n.id==d.note then ref=n;break end end
  local span=math.max(1e-9,ref.finish-ref.start);local u=(d.time-ref.start)/span
  local moved=clamp(u+(d.anchor and (mx-d.x)*d.seconds/span or 0),0,1)
  local evaluate=Curve.evaluator(original,'shift',d.before.curve_version or 3,e.data);local requests={}
  for _,n in ipairs(e.notes)do if e.selected[n.id] then
    local at=n.start+(n.finish-n.start)*u;local raw=Trace.sample(e.data,at)
    if raw then
      if d.anchor and d.target_anchor then
        for i=#(n.target_anchors or {}),1,-1 do if math.abs(n.target_anchors[i].t-at)<.001 then table.remove(n.target_anchors,i)end end
      end
      requests[#requests+1]={note=n,t=n.start+(n.finish-n.start)*moved,pitch=Scale.pitch(e,raw+evaluate(at)+delta,alt)}
    end
  end end
  e.state.curve_version=4
  -- Adjacent endpoint anchors share a blend. Iterate their small linear solve
  -- together so the last note does not undo the preceding note's target.
  for pass=1,12 do
    local error=0
    for _,q in ipairs(requests)do
      local raw=Trace.sample(e.data,q.t)
      if raw then
        local residual=math.abs(raw+Curve.at(e.notes,q.t,'shift',4,e.data)-q.pitch);error=math.max(error,residual)
        if residual>=.0001 then Curve.set_target(e.notes,q.note,q.t,q.pitch,e.data)end
      end
    end
    if error<.0001 then break end
  end
end
function M.draw(e,d)
  local ref;for _,n in ipairs(d.before.notes)do if n.id==d.note then ref=n;break end end
  local span=math.max(1e-9,ref.finish-ref.start);local captured=Curve.capture_anchors(d.before.notes)
  local serial=d.serial or 1;d.valid=false;d.invalid=false
  for _,note in ipairs(e.notes)do if e.selected[note.id] then
    local ratio=(note.finish-note.start)/span
    local pitch_delta=Scale.center(note)+note.shift-Scale.center(ref)-ref.shift
    for _,part in ipairs(d.segments)do if #part.points>=2 then
      local first,last=part.points[1].t,part.points[#part.points].t
      first=math.max(ref.start,first);last=math.min(ref.finish,last)
      local points,run={},nil
      local function flush()
        local stroke=Draw.stroke(points,note)
        if stroke then
          if #(note.drawings or {})>=64 or #stroke.points>2048 then d.invalid=true;return end
          serial=serial+1;stroke.target=true;stroke.support_version=3;stroke.id=serial;stroke.curve_notes=captured
          for _,p in ipairs(stroke.points)do p.value=p.value-note.shift end
          note.drawings=note.drawings or {};note.drawings[#note.drawings+1]=stroke;d.valid=true
        end
        points={}
      end
      if last>first then
        local count=math.max(1,math.ceil((last-first)*ratio/.008));local index=1
        for j=0,count do
          local t=first+(last-first)*j/count
          while index<#part.points-1 and part.points[index+1].t<t do index=index+1 end
          local a,b=part.points[index],part.points[index+1]
          local value=a.value+(b.value-a.value)*(t-a.t)/math.max(1e-9,b.t-a.t)+pitch_delta
          local at=note.start+(t-ref.start)*ratio;local id=Draw.support(e.data,at)
          if id~=run then flush();run=id end
          if id then points[#points+1]={t=at,value=value}end
        end
        flush()
      end
    end end
  end end
end
return M
