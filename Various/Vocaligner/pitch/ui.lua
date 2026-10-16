-- @noindex
local import=...;local Notes=import('pitch/notes');local Curve=import('pitch/curve');local Link=import('pitch/link');local FX=import('pitch/fx');local Scale=import('pitch/scale');local Expression=import('pitch/expression');local Progress=import('progress');local Contour=import('pitch/contour');local Draw=import('pitch/draw');local Wave=import('pitch/waveform');local Algorithm=import('pitch/algorithm');local Workspace=import('pitch/workspace');local Glyph=import('pitch/glyph');local Transport=import('transport');local Check=import('pitch/check');local M={}
local colors={bg=0x181A1FFF,black=0x15171CFF,row=0x20232AFF,line=0x2D3038FF,text=0xD6DBE5FF,muted=0x7E8695FF,
  blue=0x4269DFFF,purple=0x9D4EDCFF,selected=0xDC77E9FF,curve=0xF6F3FFFF,raw=0xAAAAAF60,accent=0x7FCCCBFF}
local black={[1]=true,[3]=true,[6]=true,[8]=true,[10]=true}
local names={'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function name(p)local n=math.floor(p+.5);return names[n%12+1]..tostring(n//12-1)end
local function tip(im,ctx,text)if im.IsItemHovered(ctx) then im.SetTooltip(ctx,text) end end
function M.fit(e,w,h)
  e.view_extent=nil
  local samples,total={},0;local ghost_lo,ghost_hi
  for _,n in ipairs(e.notes or {}) do local weight=n.finish-n.start;samples[#samples+1]={p=Scale.center(n)+(n.shift or 0),w=weight};total=total+weight end
  if #samples==0 then for _,f in ipairs(e.data and e.data.frames or {}) do if f.confidence>=.8 then samples[#samples+1]={p=f.pitch,w=1};total=total+1 end end end
  if e.workspace and not (e.state and e.state.bypassed) then
    for _,row in ipairs(e.workspace.tracks)do if row.visible and row~=e.track_row then
      for _,entry in ipairs(row.items)do local visual=Workspace.visual(e,entry)
        for _,n in ipairs(visual and visual.notes or {})do
          local pitch=Scale.center(n)+(n.shift or 0);local weight=n.finish-n.start
          samples[#samples+1]={p=pitch,w=weight};total=total+weight
          ghost_lo=math.min(ghost_lo or pitch,pitch);ghost_hi=math.max(ghost_hi or pitch,pitch)
        end
      end
    end end
  end
  table.sort(samples,function(a,b)return a.p<b.p end)
  local lo,hi=60,72
  if #samples>0 then
    lo,hi=samples[1].p,samples[#samples].p;local sum=0;local found=false
    for _,sample in ipairs(samples) do sum=sum+sample.w
      if not found and sum>=total*.05 then lo=sample.p;found=true end
      if sum>=total*.95 then hi=sample.p;break end
    end
  end
  if ghost_lo then lo=math.min(lo,ghost_lo);hi=math.max(hi,ghost_hi)end
  local range=math.max(10,hi-lo+4);local center=(lo+hi)/2
  local a,b=Workspace.bounds(e);local len=b-a
  local span=e.fit_pending=='all' and len or math.min(len,8)
  e.view={start=e.fit_pending=='all' and a or clamp(0,a,math.max(a,b-span)),span=span,top=center+range/2,rows=range};e.fit_pending=nil
end
local function raw_at(e,t) return Contour.sample(e.data,t) or Expression.sample(e.data,t) end
local function snap_shift(e,n,value,alt,shift,original) return Scale.shift(e,n,value,alt,not shift,original) end
local tools={{'notes','Notes'},{'curve','Curve'},{'draw','Draw'},{'transition','Transition'},{'modulation','Modulation'},
  {'drift','Drift'},{'flatten','Flatten'},{'vibrato','Vibrato'},{'bounds','Bounds'}}
local tooltips={notes='Drag: relative semitones. Shift / Alt: fine pitch. Double-click: original pitch.',
  curve='Drag to edit pitch points. Selected notes receive the same pitch change at matching relative times. Double-click a point to remove it. Ctrl+C/V: copy/paste shape.',
  draw='Draw the final pitch. Selected notes receive the same relative shape. Cyan marks the painted span; noise breaks the stroke. Alt+double-click: erase drawings.',
  transition='Drag up to join the measured tail and onset; sideways for width on each side. Applies to incoming links of selected notes. White shows the result. Double-click: reset.',
  modulation='Drag vertically: depth of fast pitch variations. 100% = original, 0% = no fast variation.',
  drift='Drag vertically: slow pitch drift. 100% = original, 0% = stable trend; vibrato remains.',
  flatten='Drag up to pull the whole selection towards one pitch. 100% = flat on reliable voiced sections; uncertain gaps stay untouched. Alt: free target.',
  vibrato='Drag up: vibrato depth. Horizontal: rate. Modulation can remove the old vibrato first.',
  bounds='Drag note edges in time. S: split, J: join next. Noise is not automatically made into a voiced note.'}
local function selection(e,id,add)
  if not add and not e.selected[id] then e.selected={} end
  if add then e.selected[id]=not e.selected[id] else e.selected[id]=true end
end
local Group=import('pitch/group')
local Controls=import('controls')
local function update_drag(e,mx,my,alt,shift)
  local d=e.drag;if not d then return end
  -- No new pointer/modifier input: retain the current preview and its cache.
  local vertical=d.kind=='notes'
  if (vertical or d.last_x==mx) and d.last_y==my and d.last_alt==alt and d.last_shift==shift then return end
  d.last_x,d.last_y,d.last_alt,d.last_shift=mx,my,alt,shift
  if d.kind=='notes' and math.abs(my-d.y)>2 then d.moved=true end
  local lower,upper=Workspace.bounds(e)
  if d.kind=='pan' then e.view.start=clamp(d.start-(mx-d.x)*d.seconds,lower,math.max(lower,upper-e.view.span));e.view.top=d.top+(my-d.y)*d.semitones
  elseif d.kind=='overview' then e.view.start=clamp(d.start+(mx-d.x)*d.seconds,lower,math.max(lower,upper-e.view.span))
  elseif d.kind=='vertical' then e.view.top=clamp(d.top+(my-d.y)*d.semitones,0,140)
  elseif d.kind=='select' then
    e.selected=Notes.copy(d.selected)
    local ta,tb=math.min(d.time,d.time+(mx-d.x)*d.seconds),math.max(d.time,d.time+(mx-d.x)*d.seconds)
    local pa,pb=math.min(d.pitch,d.pitch-(my-d.y)*d.semitones),math.max(d.pitch,d.pitch-(my-d.y)*d.semitones)
    for _,n in ipairs(e.notes or {}) do local p=Scale.center(n)+n.shift;local pad=d.pitch_padding or 0;if n.finish>=ta and n.start<=tb and p+pad>=pa and p-pad<=pb then e.selected[n.id]=true end end
  elseif d.before then
    e.notes=Notes.copy(d.base or d.before.notes);e.state.notes=e.notes
    local delta=-(my-d.y)*d.semitones
    local grouped=Group.count(e.selected)>1
    if (vertical and math.abs(my-d.y)<=2) or (not vertical and not d.valid and math.abs(mx-d.x)+math.abs(my-d.y)<=2) then d.changed=false;e.display=nil;return end
    if d.kind=='notes' then
      for _,n in ipairs(e.notes) do if e.selected[n.id] then n.shift=snap_shift(e,n,n.shift+delta,alt,shift,n.shift) end end
    elseif d.kind=='curve' then
      if grouped then Group.curve(e,d,mx,delta,alt)else
      for _,n in ipairs(e.notes) do if n.id==d.note then
        local at=clamp(d.time+(d.anchor and (mx-d.x)*d.seconds or 0),n.start,n.finish)
        if d.anchor and d.target_anchor then table.remove(n.target_anchors,d.anchor) end
        local raw=raw_at(e,d.time)
        local initial=d.target or ((raw or n.center)+Curve.at(d.base or d.before.notes,d.time,'shift',d.before.curve_version or 3,e.data))
        e.state.curve_version=4
        Curve.set_target(e.notes,n,at,Scale.pitch(e,initial+delta,alt),e.data)
      end end
      end
    elseif d.kind=='draw' then
      local t=d.time+(mx-d.x)*d.seconds
      local n,index=Draw.owner(e.notes,t)
      local run=n and Draw.support(e.data,t)
      d.segments=d.segments or {{points=d.points or {},last=d.last,run=d.run}}
      local segment=d.segments[#d.segments]
      if run then
        local continuous=segment.run==run and segment.last~=nil
        if n and segment.note and n.id~=segment.note then
          local a,b=segment.note_index,index;if a>b then a,b=b,a end
          for j=a,b-1 do if not Curve.can_link(e.notes[j],e.notes[j+1]) then continuous=false end end
        end
        if not continuous then segment={points={},run=run};d.segments[#d.segments+1]=segment end
        local pitch=clamp(Scale.pitch(e,d.pitch-(my-d.y)*d.semitones,alt),0,150)
        segment.last=Draw.paint(segment.points,segment.last,t,pitch)
        if n then segment.note=n.id;segment.note_index=index;segment.owners=segment.owners or {};segment.owners[n.id]=true end
      else segment.last=nil end
      d.valid=false;d.invalid=false;e.state.curve_version=4
      local serial=d.serial or 1
      if grouped then Group.draw(e,d)else
      for si,part in ipairs(d.segments)do
        local stroke=Draw.stroke(part.points,{start=0,finish=e.data.len})
        if stroke then
          local curve_notes=Curve.capture_anchors(d.before.notes)
          if #stroke.points>2048 then d.invalid=true end
          for _,note in ipairs(e.notes)do if stroke.finish>note.start and stroke.start<note.finish or part.owners and part.owners[note.id] then
            if #(note.drawings or {})>=64 then d.invalid=true else
              local copy=Notes.copy(stroke);copy.target=true;copy.support_version=3;copy.id=serial+si;copy.curve_notes=curve_notes
              for _,point in ipairs(copy.points)do point.value=point.value-note.shift end
              note.drawings=note.drawings or {};note.drawings[#note.drawings+1]=copy;d.valid=true
            end
          end end
        end
      end
      end
      if d.invalid then d.valid=false;e.notes=Notes.copy(d.before.notes);e.state.notes=e.notes end
    elseif d.kind=='transition' then
      for i,n in ipairs(e.notes)do if (n.id==d.note or grouped and e.selected[n.id]) and Curve.can_link(e.notes[i-1],n)then
        local link=Link.edit_tilt(e.notes[i-1],n,e.data);local dy=my-d.y;local dx=mx-d.x
        local original_width,original_amount=Link.settings(d.before.notes[i]);link.curve_notes=Curve.capture_anchors(d.before.notes)
        d.axis=d.axis or (math.abs(dx)>math.abs(dy) and 'width' or 'amount')
        if d.axis=='width' then
          link.width=clamp(original_width+dx*d.seconds,.02,.4)
          link.amount=original_amount>0 and original_amount or .5
        else link.amount=clamp(original_amount-dy/100,0,1)end
        e.state.curve_version=4
      end end
    elseif d.kind=='bounds' then
      for i,n in ipairs(e.notes) do if n.id==d.note then
        Expression.initialize(n)
        if d.edge=='start' then n.start=clamp(d.time+(mx-d.x)*d.seconds,e.notes[i-1] and e.notes[i-1].finish or 0,n.finish-math.min(.032,n.finish-n.start))
        else n.finish=clamp(d.time+(mx-d.x)*d.seconds,n.start+math.min(.032,n.finish-n.start),e.notes[i+1] and e.notes[i+1].start or e.data.len) end
        n.first=math.max(1,math.floor(n.start/.016)+1);n.last=math.min(#e.data.frames,math.ceil(n.finish/.016))
      end end
    elseif d.kind=='modulation' or d.kind=='drift' or d.kind=='flatten' then
      e:parameter(d.kind,clamp(d.value+(d.y-my)*.01,0,d.kind=='flatten' and 1 or 2),alt,d.before)
    elseif d.kind=='vibrato' then
      e:parameter('vibrato_depth',clamp(d.value+(d.y-my)*.005,0,2),alt,d.before)
      e:parameter('vibrato_rate',clamp(d.rate+(mx-d.x)*.02,.5,12),alt,d.before)
    end
    e.display=nil;d.changed=d.kind=='draw' and d.valid or d.kind=='transition' and math.abs(mx-d.x)+math.abs(my-d.y)>2 or d.kind~='draw' and d.kind~='transition' and math.abs(mx-d.x)+math.abs(my-d.y)>2
    if d.kind=='notes' then
      d.changed=false;for i,n in ipairs(e.notes)do if n.shift~=(d.base or d.before.notes)[i].shift then d.changed=true;break end end
    end
  end
end
function M.canvas(im,ctx,e,w,h)
  local canvas_started=e.r.time_precise()
  local x,y=im.GetCursorScreenPos(ctx);local dl=im.GetWindowDrawList(ctx)
  w=math.max(180,w);h=math.max(140,h)
  local keyw,ruler,overview,bar=46,26,42,12
  local left,right,top,bottom=x+keyw,x+w-bar,y+ruler,y+h-overview-bar
  local width,height=math.max(1,right-left),math.max(1,bottom-top)
  if e.data and not e.display then
    local evaluate=Curve.evaluator(e.notes or {},'shift',e.state and e.state.curve_version or 1,e.data)
    for _,n in ipairs(e.notes or {}) do if n.local_center then
      local center=Notes.visual_center(n,e.data,function(t)
        return (raw_at(e,t) or n.center)+evaluate(t)
      end)
      if center then n.visual_offset=center-n.center-(n.shift or 0)-(n.flat_offset or 0)*(n.flatten or 0) end
    end end
  end
  if not e.view or e.fit_pending then M.fit(e,width,height) end
  local lower,upper=Workspace.bounds(e);local maxlen=upper-lower
  local v=e.view;v.span=clamp(v.span,.15,maxlen);v.rows=clamp(v.rows,3,100)
  v.start=clamp(v.start,lower,math.max(lower,upper-v.span))
  local function tx(t)return left+(t-v.start)/v.span*width end
  local function py(p)return top+(v.top-p)/v.rows*height end
  local function time(px)return v.start+(px-left)/width*v.span end
  local mx,my=im.GetMousePos(ctx);local mt=time(mx)
  local mods=im.GetKeyMods(ctx);local shift=(mods&im.Mod_Shift)~=0;local ctrl=(mods&im.Mod_Ctrl)~=0;local alt=(mods&im.Mod_Alt)~=0
  im.InvisibleButton(ctx,'##pitch_canvas',w,h,im.ButtonFlags_MouseButtonLeft|im.ButtonFlags_MouseButtonRight|im.ButtonFlags_MouseButtonMiddle)
  local hovered=im.IsItemHovered(ctx);local active=im.IsItemActive(ctx)
  if e.drag then update_drag(e,mx,my,alt,shift) end
  local transport=Transport.read(e.r,e.project)
  Transport.follow(e,e.r,transport,v,e.snapshot and e.snapshot.pos or 0,lower,upper,e.drag~=nil or hovered and (im.GetMouseWheel(ctx)~=0 or im.IsMouseClicked(ctx,0)))
  mt=time(mx)
  im.DrawList_AddRectFilled(dl,x,y,x+w,y+h,colors.bg,5)
  im.DrawList_PushClipRect(dl,x,y,x+w,y+h,true)
  im.DrawList_AddRectFilled(dl,x+2,y+2,x+22,y+22,0x353C49FF,3)
  im.DrawList_AddRectFilled(dl,x+24,y+2,x+44,y+22,0x353C49FF,3)
  im.DrawList_AddText(dl,x+7,y+3,colors.text,'+')
  im.DrawList_AddText(dl,x+30,y+3,colors.text,'-')
  for p=math.floor(v.top-v.rows)-1,math.ceil(v.top)+1 do
    local yy,zz=py(p+.5),py(p-.5)
    if zz>top and yy<bottom then
      yy,zz=math.max(top,yy),math.min(bottom,zz)
      im.DrawList_AddRectFilled(dl,left,yy,right,zz,black[p%12] and colors.black or colors.row)
      im.DrawList_AddRectFilled(dl,x+1,yy,left-2,zz,black[p%12] and 0x242731FF or 0x343943FF)
      if (e.scale or 1)>1 and Scale.contains(p,e.root,e.scale) then
        im.DrawList_AddRectFilled(dl,left,yy,right,zz,p%12==(e.root or 0) and 0x62BAB522 or 0x62BAB50D)
        im.DrawList_AddRectFilled(dl,x+1,yy,x+4,zz,p%12==(e.root or 0) and colors.accent or 0x62BAB588)
      end
      im.DrawList_AddLine(dl,x,zz,right,zz,colors.line)
      if (p%12==0 or height/v.rows>=20) and py(p)>=top+7 and py(p)<=bottom-7 then
        im.DrawList_AddText(dl,x+5,py(p)-6,p%12==0 and colors.text or colors.muted,name(p))
      end
    end
  end
  local step=10^math.floor(math.log(math.max(.02,v.span/8),10));if v.span/step>14 then step=step*2 end;if v.span/step>14 then step=step*2.5 end
  for t=math.floor(v.start/step)*step,v.start+v.span+step,step do local xx=tx(t)
    if xx>=left and xx<=right then
      im.DrawList_AddLine(dl,xx,top,xx,bottom,colors.line)
      im.DrawList_AddLine(dl,xx,y+19,xx,top,colors.muted)
      im.DrawList_AddText(dl,xx+4,y+5,colors.muted,string.format(v.span<4 and '%.2f' or '%.1f',t+(e.track_row and e.snapshot and e.snapshot.pos or 0)))
    end
  end
  local data=e.data or e.partial;local frames=data and data.frames or {}
  local peak=Wave.peak(data)
  im.DrawList_PushClipRect(dl,left,top,right,bottom,true)
  -- One faint, smoothed silhouette: overlapping thick lines made the old
  -- background accumulate opacity and compete with notes at close zoom.
  local wave={};local step_px=4
  for px=0,width+step_px,step_px do
    local at=clamp(math.floor(time(left+px)/.016)+1,1,math.max(1,#frames));local sum,weight=0,0
    for j=math.max(1,at-4),math.min(#frames,at+4) do local w=5-math.abs(j-at);sum=sum+(frames[j].rms or 0)*w;weight=weight+w end
    local t=time(left+px);wave[#wave+1]={x=left+px,a=weight>0 and t>=0 and t<=(e.snapshot and e.snapshot.len or 0) and math.sqrt(sum/weight/peak)*height*.10 or 0}
  end
  im.DrawList_PathClear(dl)
  for _,p in ipairs(wave) do im.DrawList_PathLineTo(dl,p.x,(top+bottom)*.5-p.a) end
  for i=#wave,1,-1 do local p=wave[i];im.DrawList_PathLineTo(dl,p.x,(top+bottom)*.5+p.a) end
  if #frames>0 then im.DrawList_PathFillConcave(dl,0xFFFFFF04) else im.DrawList_PathClear(dl) end
  local bypassed=e.state and e.state.bypassed==true
  local workspace_hit
  if not bypassed and e.workspace and e.snapshot then
    for _,row in ipairs(e.workspace.tracks)do
      local same=row==e.track_row
      if same or row.visible then for _,entry in ipairs(row.items)do if entry.item~=e.item then
        local offset=entry.pos-e.snapshot.pos
        if offset+entry.len>=v.start and offset<=v.start+v.span then
          local ax,bx=math.max(left,tx(offset)),math.min(right,tx(offset+entry.len))
          if same then
            im.DrawList_AddLine(dl,ax,top,bx,top,0x7FCCCB50,2)
            if bx-ax>60 then im.DrawList_AddText(dl,ax+4,top+3,0x7FCCCB90,entry.name) end
            if mx>=ax and mx<=bx and my>=top and my<=top+18 then workspace_hit=entry end
          end
          local visual=Workspace.visual(e,entry)
          if visual then
            local function gx(t)return tx(offset+t)end
            local used={}
            for _,n in ipairs(visual.notes)do if offset+n.finish>=v.start and offset+n.start<=v.start+v.span then
              local a,b=math.max(left,gx(n.start)),math.min(right,gx(n.finish))
              local yy=py(Scale.center(n)+(n.shift or 0));local half=clamp(height/v.rows*.32,5,25)
              if b>a and yy+half>=top and yy-half<=bottom then
                used[n.id]=true
                local shape=Glyph.shape(visual.glyphs,n.id,visual.data,n.start,n.finish,v.start-offset,v.span,width)
                Glyph.draw(im,dl,shape,gx,yy,half,same and 0x8494C342 or 0x9898C52D,false,same and 0x9EAAD060 or 0xAAA3CE45)
                if same and mx>=a and mx<=b and math.abs(my-yy)<=half+3 then workspace_hit=entry end
              end
            end end
            for id in pairs(visual.glyphs)do if not used[id]then visual.glyphs[id]=nil end end
            local c=visual.contour
            if not c or c.start~=v.start-offset or c.span~=v.span or c.width~=width or c.pitch_per_pixel~=v.rows/height then
              c=Contour.build(visual.data,visual.notes,visual.version,v.start-offset,v.span,width,v.rows/height,c);visual.contour=c
            end
            local previous
            for _,p in ipairs(c)do
              if p.run and previous and previous.run==p.run then
                im.DrawList_AddLine(dl,gx(previous.t),py(previous.pitch),gx(p.t),py(p.pitch),same and 0xA9BCEB85 or 0xB9A5E570,1)
              end
              previous=p
            end
          end
        else entry.visual=nil
        end
      end end else for _,entry in ipairs(row.items)do entry.visual=nil end end
    end
  end
  if bypassed and e.data then
    if not e.original_ghost or e.original_ghost.data~=e.data then
      e.original_ghost={data=e.data,notes=Notes.segment(e.data,e.state.hold_ms or e.hold_ms or 100),glyphs={}}
    end
    local original=e.original_ghost
    for _,n in ipairs(original.notes)do if n.finish>=v.start and n.start<=v.start+v.span then
      local yy=py(n.center);local half=clamp(height/v.rows*.4,7,36)
      if yy+half>=top and yy-half<=bottom then
        local shape=Glyph.shape(original.glyphs,n.id,e.data,n.start,n.finish,v.start,v.span,width)
        Glyph.draw(im,dl,shape,tx,yy,half,0xB4BFCE58,false,0xB4BFCE90)
      end
    end end
    original.source=Contour.source(e.data,v.start,v.span,width,original.source)
    local prior
    for _,p in ipairs(original.source)do
      if p.run and prior and prior.run==p.run then im.DrawList_AddLine(dl,tx(prior.t),py(prior.raw),tx(p.t),py(p.raw),0xCCD6E3B0,1.2)end
      prior=p
    end
  else e.original_ghost=nil end
  e.glyphs=e.glyphs or {};local glyph_used={};local badge
  local hit,index,transition,boundary,anchor_hit
  for k,n in ipairs(e.notes or {}) do if n.finish>=v.start and n.start<=v.start+v.span then
    local ax,bx=tx(n.start),tx(n.finish);local inset=math.min(1.25,(bx-ax)*.1);ax,bx=ax+inset,bx-inset;local center=Scale.center(n)+(n.shift or 0);local yy=py(center);local half=clamp(height/v.rows*.40,7,36)
    local selected=e.selected[n.id];local col=Glyph.color(center,selected,bypassed and 80 or 255)
    local near=hovered and mx>=ax-3 and mx<=bx+3 and math.abs(my-yy)<math.max(9,half+4)
    if near then hit,index=n,k end
    if data and yy+half>=top and yy-half<=bottom then
      glyph_used[n.id]=true
      local shape=Glyph.shape(e.glyphs,n.id,data,n.start,n.finish,v.start,v.span,width)
      Glyph.draw(im,dl,shape,tx,yy,half,col,near or e.drag and e.drag.note==n.id,selected and (bypassed and 0xEDF3FF70 or 0xEDF3FFE0) or nil)
      if e.drag and e.drag.kind=='notes' and e.drag.note==n.id and e.drag.moved and im.IsMouseDown(ctx,0) then
        local extent=0;for _,p in ipairs(shape)do extent=math.max(extent,p.upper*half)end
        badge={x=clamp((ax+bx)*.5,left+40,right-40),y=math.max(top+3,yy-extent-29),text=string.format('%+.2f st',n.shift or 0)}
      elseif bx-ax>65 and height/v.rows>=28 then im.DrawList_AddText(dl,ax+8,yy-half-15,selected and colors.text or 0xB5BEDBA0,name(center)) end
    end
    if selected and e.tool=='bounds' then
      for _,side in ipairs({'start','finish'}) do
        local hx=tx(n[side]);local near=math.abs(mx-hx)<14 and math.abs(my-yy)<half+15
        if near or e.drag and e.drag.note==n.id then
          im.DrawList_AddLine(dl,hx,yy-half-5,hx,yy+half+5,colors.accent,2)
          if near then boundary={note=n,edge=side} end
        end
      end
    end
  end end
  for id in pairs(e.glyphs)do if not glyph_used[id]then e.glyphs[id]=nil end end
  local display=e.display
  if data and (not display or display._data~=data or display._frames~=data.frames or display.frame_count~=#data.frames or display.start~=v.start or display.span~=v.span or display.width~=width or display.pitch_per_pixel~=v.rows/height) then
    local began=e.r.time_precise()
    display=Contour.build(data,e.notes or {},e.state and e.state.curve_version or 1,v.start,v.span,width,v.rows/height,e.contour_cache);e.display=display;e.contour_cache=display
    if e.measure then e:measure('contour',began) end
  end
  if e.show_source and data and not bypassed then
    e.source_display=Contour.source(data,v.start,v.span,width,e.source_display)
    local prior
    for _,p in ipairs(e.source_display)do
      if p.run and prior and prior.run==p.run then im.DrawList_AddLine(dl,tx(prior.t),py(prior.raw),tx(p.t),py(p.raw),0xAAAAAF48,1) end
      prior=p
    end
  end
  local previous
  for _,p in ipairs(display or {}) do
    if p.run and previous and previous.run==p.run then
      local ax,bx=tx(previous.t),tx(p.t)
      im.DrawList_AddLine(dl,ax,py(previous.pitch),bx,py(p.pitch),bypassed and 0xF6F3FF65 or colors.curve,p.supported and previous.supported and 1.6 or 1.2)
    end
    previous=p
  end
  -- Yellow: what the Pitch Meter actually measured after ReaPitch.
  if e.check_on and data and e.snapshot then Check.draw(im,ctx,dl,e,v,tx,py,left,right,top,width,display) end
  -- The small orange connector selects two blocks. Only the white curve
  -- represents pitch; never invent a voiced path across missing F0.
  e.transition_handles={}
  if data and not bypassed and e.tool=='transition' then
    local function distance(px,py,ax,ay,bx,by)
      local dx,dy=bx-ax,by-ay;local u=clamp(((px-ax)*dx+(py-ay)*dy)/math.max(1e-9,dx*dx+dy*dy),0,1)
      return (px-ax-u*dx)^2+(py-ay-u*dy)^2
    end
    for i=2,#(e.notes or {})do
      local a,b=e.notes[i-1],e.notes[i]
      if Curve.can_link(a,b) and b.start>=v.start and a.finish<=v.start+v.span then
        local wa,amount=Link.settings(b);local lo,hi
        if Link.active(b)then lo,hi=Link.window(a,b,data)else lo,hi=Link.pair_window(a,b,data,wa,true)end
        local ax=tx(a.finish)-math.min(12,(a.finish-a.start)/v.span*width*.3)
        local bx=tx(b.start)+math.min(12,(b.finish-b.start)/v.span*width*.3)
        local ay,by=py(Scale.center(a)+(a.shift or 0)),py(Scale.center(b)+(b.shift or 0))
        local points={};local near=false
        for j=0,24 do local u=j/24;local power=1+2*amount;local rise,fall=u^power,(1-u)^power
          local p={x=ax+(bx-ax)*u,y=ay+(by-ay)*Curve.ease(rise/(rise+fall))}
          if j>0 then local q=points[#points];if distance(mx,my,q.x,q.y,p.x,p.y)<64 then near=true end end
          points[#points+1]=p
        end
        near=near and not e.stale and not e.no_selection
        local moving=e.drag and e.drag.kind=='transition' and e.drag.note==b.id
        local grip=points[13];local col=(near or moving) and 0xFFD582FF or amount>0 and 0xF5AB55BD or 0xF5AB5570
        if e.stale then col=0x7E869550 end
        for j=2,#points do local p,q=points[j-1],points[j];im.DrawList_AddLine(dl,p.x,p.y,q.x,q.y,col,near and 2.2 or 1.5)end
        im.DrawList_AddRectFilled(dl,grip.x-5,grip.y-2,grip.x+5,grip.y+2,col,2)
        e.transition_handles[#e.transition_handles+1]={x=grip.x,y=grip.y,note=b.id,lo=lo,hi=hi,points=points}
        if near or moving then
          local painted=false
          for _,n in ipairs({a,b})do for _,stroke in ipairs(n.drawings or {})do if stroke.target and stroke.finish>lo and stroke.start<hi then painted=true end end end
          local label=Link.active(b) and b.link.version<6 and 'Saved transition · drag to soften' or string.format('Amount %.0f%% · Width %.0f ms',amount*100,wa*1000)
          badge={x=clamp(grip.x,left+130,right-130),y=clamp(grip.y-28,top,bottom-24),text=label..(painted and ' · Draw owns paint' or '')}
        end
        if near then transition={note=b,lo=lo,hi=hi}end
      end
    end
  end
  -- Draw owns the final trajectory. Show the ownership instead of silently
  -- allowing an orange control to appear responsible for the painted pitch.
  if not bypassed then local prior
    for _,p in ipairs(display or {})do
      local owner=Draw.owner(e.notes or {},p.t);local drawn=false
      if owner then for _,s in ipairs(owner.drawings or {})do if s.target and p.t>=s.points[1].t and p.t<=s.points[#s.points].t then drawn=true;break end end end
      if drawn and prior and prior.drawn and p.run and p.run==prior.run then im.DrawList_AddLine(dl,tx(prior.t),py(prior.pitch),tx(p.t),py(p.pitch),0x7FCCCBFF,2.5) end
      prior={t=p.t,pitch=p.pitch,run=p.run,drawn=drawn}
    end
  end
  if e.tool=='curve' then for _,n in ipairs(e.notes or {}) do if e.selected[n.id] then for j,p in ipairs((e.state.curve_version==4 and n.target_anchors or n.anchors) or {}) do
    local f=raw_at(e,p.t);if f and p.t>=n.start and p.t<=n.finish then
      local ax,ay=tx(p.t),py(f+Curve.at(e.notes,p.t,'shift',e.state and e.state.curve_version or 1,e.data))
      im.DrawList_AddCircleFilled(dl,ax,ay,4,colors.accent)
      if math.abs(mx-ax)<9 and math.abs(my-ay)<9 then anchor_hit={note=n,index=j,target=e.state.curve_version==4} end
    end
  end end end end
  if e.drag and e.drag.kind=='select' then
    local d=e.drag;im.DrawList_AddRectFilled(dl,math.min(mx,d.x),math.min(my,d.y),math.max(mx,d.x),math.max(my,d.y),0x7FCCCB22)
    im.DrawList_AddRect(dl,math.min(mx,d.x),math.min(my,d.y),math.max(mx,d.x),math.max(my,d.y),colors.accent)
  end
  if e.snapshot then Transport.draw(im,dl,transport,function(t)return tx(t-e.snapshot.pos)end,left,right,top,bottom) end
  if badge then
    local tw=im.CalcTextSize and im.CalcTextSize(ctx,badge.text) or #badge.text*7
    local a,b=badge.x-tw*.5-9,badge.x+tw*.5+9
    im.DrawList_AddRectFilled(dl,a+1,badge.y+2,b+1,badge.y+24,0x00000038,5)
    im.DrawList_AddRectFilled(dl,a,badge.y,b,badge.y+22,0x343946F5,5)
    im.DrawList_AddRect(dl,a,badge.y,b,badge.y+22,0xA6ADBA40,5)
    im.DrawList_AddText(dl,a+9,badge.y+3,0xF0EAF6FF,badge.text)
  end
  im.DrawList_PopClipRect(dl)
  -- Full-item overview doubles as a horizontal scrollbar.
  local oy=bottom+bar;im.DrawList_AddRectFilled(dl,left,oy,right,y+h,0x20242BFF)
  im.DrawList_PushClipRect(dl,left,oy,right,y+h,true)
  local viewa=left+(v.start-lower)/maxlen*width;local viewb=left+(v.start+v.span-lower)/maxlen*width
  if e.track_row and e.snapshot then for _,entry in ipairs(e.track_row.items)do
    local a=left+(entry.pos-e.snapshot.pos-lower)/maxlen*width;local b=a+entry.len/maxlen*width
    im.DrawList_AddRectFilled(dl,a,oy+4,b,y+h-4,entry.item==e.item and 0x82B4E830 or 0x7898B61C,2)
  end end
  for i=1,#frames,math.max(1,math.floor(#frames/width)) do local f=frames[i];local xx=left+(f.t-lower)/maxlen*width
    local a=math.min(overview*.45,math.sqrt(math.max(0,f.rms or 0)/math.max(peak,.001))*overview*.32)
    im.DrawList_AddLine(dl,xx,oy+overview*.5-a,xx,oy+overview*.5+a,0x7898B660)
  end
  im.DrawList_AddRectFilled(dl,viewa,oy,viewb,y+h,0x82B4E814,3)
  im.DrawList_AddRect(dl,viewa,oy,viewb,y+h,0x82B4E899,3)
  if e.snapshot then Transport.draw(im,dl,transport,function(t)return left+(t-e.snapshot.pos-lower)/maxlen*width end,left,right,oy,y+h) end
  im.DrawList_PopClipRect(dl)
  im.DrawList_AddRectFilled(dl,right+2,top,x+w,bottom,0x111318FF,4)
  local vh=math.max(18,height*v.rows/128);local vy=top+(128-v.top)/128*height
  im.DrawList_AddRectFilled(dl,right+3,clamp(vy,top,bottom-vh),x+w-1,clamp(vy,top,bottom-vh)+vh,0x5D6878FF,4)
  im.DrawList_PopClipRect(dl)
  if hovered and not e.drag then
    local wheel=im.GetMouseWheel(ctx)
    if wheel~=0 then
      if ctrl or mx<left or mx>=right then local pitch=v.top-(my-top)/height*v.rows;v.rows=clamp(v.rows*math.exp(-wheel*.20),3,100);v.top=pitch+(my-top)/height*v.rows
      elseif shift or alt then v.start=clamp(v.start-wheel*v.span*.12,lower,math.max(lower,upper-v.span))
      else local anchor=time(mx);v.span=clamp(v.span*math.exp(-wheel*.2),.15,maxlen);v.start=clamp(anchor-(mx-left)/width*v.span,lower,math.max(lower,upper-v.span)) end
    end
    if im.IsMouseClicked(ctx,1) and mx>=left and mx<right and my>=top and my<bottom then
      e.drag={kind='select',button=1,x=mx,y=my,time=mt,pitch=v.top-(my-top)/height*v.rows,
        seconds=v.span/width,semitones=v.rows/height,pitch_padding=clamp(height/v.rows*.40,7,36)*v.rows/height,
        selected=(ctrl or shift) and Notes.copy(e.selected) or {}}
    elseif im.IsMouseClicked(ctx,2) then e.drag={kind='pan',button=2,x=mx,y=my,start=v.start,top=v.top,seconds=v.span/width,semitones=v.rows/height}
    elseif im.IsMouseClicked(ctx,0) then
      if mx<left and my<top then
        local center=v.top-v.rows*.5;v.rows=clamp(v.rows*(mx<x+23 and .8 or 1.25),3,100);v.top=center+v.rows*.5
      elseif mx<left then e.drag={kind='vertical',x=mx,y=my,top=v.top,semitones=v.rows/height,button=0}
      elseif my>=oy then
        if mx<viewa or mx>viewb then v.start=clamp(lower+(mx-left)/width*maxlen-v.span*.5,lower,math.max(lower,upper-v.span)) end
        e.drag={kind='overview',x=mx,y=my,start=v.start,seconds=maxlen/width,button=0}
      elseif mx>=right then e.drag={kind='vertical',x=mx,y=my,top=v.top,semitones=-128/height,button=0}
      elseif my<top then
        if e.snapshot then e.r.SetEditCurPos2(e.project,e.snapshot.pos+clamp(mt,lower,upper),false,false) end
      elseif transition then
        local n=transition.note;selection(e,n.id,false);local before=e:begin_edit()
        if before then
          if im.IsMouseDoubleClicked(ctx,0) then
            for _,q in ipairs(e.notes)do if e.selected[q.id]then q.link=nil;q.transition=.08;q.transition_amount=nil;q.transition_shape=nil;q.transition_bias=nil;q.transition_link=nil end end
            e:commit(before,'restore pitch transition')
          else
            local a;for i,q in ipairs(e.notes)do if q==n then a=e.notes[i-1];break end end
            local link_width,amount=Link.settings(n)
            e.drag={kind='transition',before=before,note=n.id,width=link_width,amount=amount,x=mx,y=my,seconds=v.span/width,semitones=v.rows/height}
          end
        end
      elseif boundary then
        local n=boundary.note;local before=e:begin_edit()
        if before then e.drag={kind='bounds',before=before,note=n.id,edge=boundary.edge,time=n[boundary.edge],x=mx,y=my,seconds=v.span/width,semitones=v.rows/height} end
      elseif anchor_hit or hit or (e.tool=='curve' and Notes.at(e.notes or {},mt)) or (e.tool=='draw' and Draw.owner(e.notes or {},mt) and Contour.sample(e.data,mt)) then
        local n=anchor_hit and anchor_hit.note or hit or (e.tool=='draw' and Draw.owner(e.notes,mt) or Notes.at(e.notes,mt));selection(e,n.id,ctrl)
        if im.IsMouseDoubleClicked(ctx,0) then
          local edited=e.tool=='notes' and (n.shift~=0 or #n.anchors>0 or Expression.edited(n)) or
            e.tool=='curve' and anchor_hit or e.tool=='modulation' and (n.modulation or 1)~=1 or
            e.tool=='drift' and (n.drift or 1)~=1 or e.tool=='flatten' and (n.flatten or 0)~=0 or
            e.tool=='vibrato' and (n.vibrato_depth or 0)~=0 or e.tool=='draw' and (#(n.drawings or {})>0 or Expression.edited(n) or n.shift~=0 or #n.anchors>0 or #(n.target_anchors or {})>0 or n.link~=nil)
          local before=(edited or Group.count(e.selected)>1) and e:begin_edit()
          if before then
            local anchor_time=anchor_hit and (anchor_hit.target and n.target_anchors or n.anchors)[anchor_hit.index].t
            for _,q in ipairs(e.notes)do if e.selected[q.id]then
              if e.tool=='curve' and anchor_hit then
                local at=q.start+(q.finish-q.start)*(anchor_time-n.start)/math.max(1e-9,n.finish-n.start)
                local points=anchor_hit.target and q.target_anchors or q.anchors
                for i=#(points or {}),1,-1 do if math.abs(points[i].t-at)<.001 then table.remove(points,i)end end
              elseif e.tool=='modulation' then q.modulation=1
              elseif e.tool=='drift' then q.drift=1
              elseif e.tool=='flatten' then q.flatten=0
              elseif e.tool=='vibrato' then q.vibrato_depth=0
              elseif e.tool=='draw' then if alt then q.drawings=nil else Expression.reset(q) end
              elseif e.tool=='notes' then Expression.reset(q)end
            end end
            if before then e:commit(before,'restore pitch '..e.tool) end
          end
        elseif e.tool=='draw' then
          if #(n.drawings or {})>=64 then e:fail('Draw: reset old strokes before adding more (64 per note).')
          elseif Contour.sample(e.data,mt) then
            local before=e:begin_edit()
            if before then
              local owner_index;for i,q in ipairs(e.notes)do if q==n then owner_index=i;break end end
              local p=clamp(v.top-(my-top)/height*v.rows,0,150);local value=Scale.pitch(e,p,alt)
              local serial=0;for _,note in ipairs(e.notes)do for _,stroke in ipairs(note.drawings or {})do serial=math.max(serial,stroke.id or 0) end end
              local run=Draw.support(e.data,mt)
              e.drag={kind='draw',serial=serial+1,run=run,before=before,note=n.id,time=mt,pitch=p,x=mx,y=my,seconds=v.span/width,semitones=v.rows/height,
                points={{t=mt,value=value}},last={t=mt,value=value},segments={{points={{t=mt,value=value}},last={t=mt,value=value},run=run,note=n.id,note_index=owner_index,owners={[n.id]=true}}}}
            end
          end
        elseif e.tool~='bounds' and e.tool~='transition' then
          local before=e:begin_edit()
          local at=anchor_hit and (anchor_hit.target and n.target_anchors or n.anchors)[anchor_hit.index].t or clamp(mt,n.start,n.finish)
          local value=e.tool=='vibrato' and (n.vibrato_depth or 0) or e.tool=='flatten' and (n.flatten or 0) or (n[e.tool] or 1)
          if e.tool=='curve' then value=Curve.anchor(n,at) end
          if before then e.drag={kind=e.tool,before=before,note=n.id,center=n.center+n.shift,x=mx,y=my,time=at,value=value,rate=n.vibrato_rate or 5.5,anchor=anchor_hit and anchor_hit.index,target_anchor=anchor_hit and anchor_hit.target,target=(raw_at(e,at) or n.center)+Curve.at(before and before.notes or e.notes,at,'shift',before and before.curve_version or 3,e.data),base=Notes.copy(e.notes),semitones=v.rows/height,seconds=v.span/width} end
        end
      elseif workspace_hit and e.activate then e:activate(workspace_hit.item)
      elseif ctrl then
        e.drag={kind='select',button=0,x=mx,y=my,time=mt,pitch=v.top-(my-top)/height*v.rows,seconds=v.span/width,semitones=v.rows/height,selected=Notes.copy(e.selected)}
      else
        e.selected={}
        if e.snapshot then e.r.SetEditCurPos2(e.project,e.snapshot.pos+clamp(mt,lower,upper),false,false) end
        e.drag={kind='pan',button=0,x=mx,y=my,start=v.start,top=v.top,seconds=v.span/width,semitones=v.rows/height}
      end
    end
    if im.IsKeyPressed(ctx,im.Key_S,false) and not ctrl then e:split(mt) end
    if im.IsKeyPressed(ctx,im.Key_J,false) and index then e:join(index) end
  end
  if e.drag then
    local began=e.r.time_precise()
    update_drag(e,mx,my,alt,shift)
    if e.measure then e:measure('drag',began) end
    if not im.IsMouseDown(ctx,e.drag.button or 0) then
      local d=e.drag;e.drag=nil;e.gesture=false
      if d.before and d.invalid then
        e.state=d.before;e.notes=d.before.notes;e.display=nil;e:fail('Draw stroke is too dense. Draw a shorter section or reset old strokes.')
      elseif d.before and d.changed then
        local mode;if d.kind=='bounds' and not e.state.fx_guid then mode='metadata' end
        e:commit(d.before,'edit pitch '..d.kind,mode)
      elseif d.kind=='select' then
    e.selected=Notes.copy(d.selected)
    local ta,tb=math.min(d.time,d.time+(mx-d.x)*d.seconds),math.max(d.time,d.time+(mx-d.x)*d.seconds)
    local pa,pb=math.min(d.pitch,d.pitch-(my-d.y)*d.semitones),math.max(d.pitch,d.pitch-(my-d.y)*d.semitones)
    for _,n in ipairs(e.notes or {}) do local p=Scale.center(n)+n.shift;local pad=d.pitch_padding or 0;if n.finish>=ta and n.start<=tb and p+pad>=pa and p-pad<=pb then e.selected[n.id]=true end end
  elseif d.before then e.state=d.before;e.notes=d.before.notes;e.display=nil end
    end
  end
  if hovered and not e.drag and mx<left then im.SetTooltip(ctx,'Wheel or +/-: row height; drag: pitch range') end
  if e.measure then e:measure('canvas',canvas_started) end
end
local function combo(im,ctx,label,current,items,width)
  im.SetNextItemWidth(ctx,width);local choice
  if im.BeginCombo(ctx,label,current) then
    for i,v in ipairs(items) do if im.Selectable(ctx,type(v)=='table' and v[1] or v,current==(type(v)=='table' and v[1] or v)) then choice=i end end
    im.EndCombo(ctx)
  end
  return choice
end
function M.draw(im,ctx,app)
  local e=app.pitch;local w=im.GetContentRegionAvail(ctx)
  local error=e.error and e.error:match('^[^\r\n]+'):gsub('^.*:%d+: ','')
  local active;for _,n in ipairs(e.notes or {}) do if e.selected[n.id] then active=n;break end end
  if e.tool=='transition' then
    active=nil
    for i,n in ipairs(e.notes or {})do if i>1 and e.selected[n.id] and Curve.can_link(e.notes[i-1],n)then active=n;break end end
  end
  local specs
  if e.tool=='modulation' then specs={{'Depth','modulation',0,200,'%.0f%%',100,1}}
  elseif e.tool=='drift' then specs={{'Drift','drift',0,200,'%.0f%%',100,1}}
  elseif e.tool=='flatten' then specs={{'Flatten','flatten',0,100,'%.0f%%',100,0}}
  elseif e.tool=='vibrato' then specs={{'Depth','vibrato_depth',0,200,'%.0f ct',100,0},{'Rate','vibrato_rate',.5,12,'%.2f Hz',1,5.5},{'Onset','vibrato_onset',0,100,'%.0f%%',100,.25},{'Release','vibrato_release',5,1000,'%.0f ms',1000,.02},{'Growth','vibrato_growth',-100,100,'%.0f%%',100,0}}
  elseif e.tool=='transition' then specs={{'Amount','link_amount',0,100,'%.0f%%',100,0},{'Width','link_width',20,400,'%.0f ms',1000,.08}}
  elseif e.tool~='bounds' and e.tool~='draw' then specs={{'Shift','shift',-24,24,'%.2f st',1,0},{'Formant','formant',-12,12,'%.2f st',1,0}} end
  local toolbar_child=im.BeginChild~=nil
  local function text_width(label)return im.CalcTextSize and im.CalcTextSize(ctx,label) or #label*7 end
  local toolbar_width=92+140+2*(im.GetFrameHeight and im.GetFrameHeight(ctx) or 24)+text_width('Source')+text_width('Check')+8+16+8*4
  for _,label in ipairs({'Analyze','Bypass','Render vocal','Reset','Tracks...','Cancel'})do toolbar_width=toolbar_width+text_width(label)+16 end
  if e.tool=='curve' then toolbar_width=toolbar_width+text_width('Copy')+text_width('Paste')+40 end
  for _,spec in ipairs(specs or {})do toolbar_width=toolbar_width+(spec[1]=='Formant' and 100 or 85)+4 end
  local toolbar_height=(im.GetFrameHeight and im.GetFrameHeight(ctx) or 24)+4+(w<toolbar_width and 16 or 0)
  if toolbar_child then im.BeginChild(ctx,'##pitch_toolbar',0,toolbar_height,0,im.WindowFlags_HorizontalScrollbar or 0) end
  if im.PushStyleVar then im.PushStyleVar(ctx,im.StyleVar_ItemSpacing,4,0) end
  local busy=e:busy();local quiet=e.gesture or e.job and e.job.kind=='apply'
  if busy then Controls.disabled(im,ctx,true,quiet) end
  if im.Button(ctx,'Analyze') then e:analyze() end
  tip(im,ctx,'Analyze selected audio items; with no item selection, analyze the active track. Reanalysis keeps editor corrections when their source geometry still matches.')
  im.SameLine(ctx)
  local bypassed=e.state and e.state.bypassed==true
  if bypassed and im.PushStyleColor then im.PushStyleColor(ctx,im.Col_Button,0x63755CFF) end
  if im.Button(ctx,'Bypass') then e:compare() end
  if bypassed and im.PopStyleColor then im.PopStyleColor(ctx) end
  tip(im,ctx,'Bypass ReaPitch: show original notes and temporarily hide other ghosts. Click again to restore the edited sound and track ghosts.')
  im.SameLine(ctx)
  local render_disabled=not e.vocal_origin and (not e.data or e.stale or e.gesture or e.no_selection)
  if render_disabled then im.BeginDisabled(ctx)end
  if im.Button(ctx,e.vocal_origin and 'Edit source' or 'Render vocal')then
    if e.vocal_origin then e:edit_vocal_source()else e:render_vocal(im,ctx)end
  end
  if render_disabled then im.EndDisabled(ctx)end
  tip(im,ctx,e.vocal_origin and 'Return to the original take and its editable Pitch notes. The rendered take remains available in REAPER.' or
    'Experimental vocal renderer: bake the target pitch into a new take. Original audio and edits remain available; Undo removes the new take. Mono, normal speed, no explicit Formant edits. No Python or monitoring FX required.')
  if im.BeginPopup then
    im.SameLine(ctx);if im.Button(ctx,'Reset') then im.OpenPopup(ctx,'Reset pitch corrections') end
    if im.BeginPopup(ctx,'Reset pitch corrections') then
      im.BeginDisabled(ctx,not e:has_selection() or e.stale==true)
      if im.Selectable(ctx,'Selected notes') then e:reset_selected();im.CloseCurrentPopup(ctx) end
      im.EndDisabled(ctx)
      if im.Selectable(ctx,'Current item') then e:reset_all();im.CloseCurrentPopup(ctx) end
      if im.Selectable(ctx,'Selected items') then e:reset_all(Workspace.targets(e));im.CloseCurrentPopup(ctx) end
      im.TextWrapped(ctx,'Reset pitch, formants, curves and vibrato. Item reset removes the editor ReaPitch; saved source analysis and other FX remain. REAPER Undo restores the changes.')
      im.EndPopup(ctx)
    end
  else
    im.SameLine(ctx);if im.Button(ctx,'Remove') then e:remove() end
  end
  -- Fit button temporarily hidden; canvas navigation and fit logic remain.
  -- im.SameLine(ctx);if im.Button(ctx,'Fit') then e.fit_pending='all' end
  local current='Notes';local labels={}
  for _,v in ipairs(tools) do labels[#labels+1]=v[2];if e.tool==v[1] then current=v[2] end end
  im.SameLine(ctx);local tool=combo(im,ctx,'##pitch_tool',current,labels,92)
  if tool then e.tool=tools[tool][1] end;tip(im,ctx,tooltips[e.tool])
  if busy then im.EndDisabled(ctx) end
  if e.job and not e.job.committed and (e.job.kind=='analysis' or e.job.kind=='vocal_render') then im.SameLine(ctx);if im.Button(ctx,'Cancel') then e:cancel() end end
  -- Settings are metadata-only and never quantize existing notes on toggle.
  local locked=e:busy() or e.gesture;if locked then Controls.disabled(im,ctx,true,quiet) end
  im.SameLine(ctx)
  local key_label=Scale.roots[(e.root or 0)+1]..' '..Scale.scales[e.scale or 1][1]
  if im.Button(ctx,key_label..'##pitch_key',140) then im.OpenPopup(ctx,'Pitch scale') end
  tip(im,ctx,'Root and Mode: highlight the key without retuning notes.')
  if im.BeginPopup(ctx,'Pitch scale') then
    if im.BeginMenu(ctx,'Root') then
      for i,label in ipairs(Scale.roots)do
        if im.MenuItem(ctx,label,nil,i-1==(e.root or 0)) and not locked then e:set_scale(i-1,e.scale or 1,false) end
      end
      im.EndMenu(ctx)
    end
    if im.BeginMenu(ctx,'Mode') then
      for i,scale in ipairs(Scale.scales)do
        if im.MenuItem(ctx,scale[1],nil,i==(e.scale or 1)) and not locked then e:set_scale(e.root or 0,i,false) end
      end
      im.EndMenu(ctx)
    end
    im.EndPopup(ctx)
  end
  im.SameLine(ctx);local source_changed,source=im.Checkbox(ctx,'Source',e.show_source==true)
  if source_changed then e.show_source=source end
  tip(im,ctx,'Серая линия — исходный F0; белая — целевая высота. Flatten 100% делает цель ровной; выход ReaPitch может отклоняться. Жёлтая линия Check измеряет выход после воспроизведения. Оранжевая связь выбирает пару нот.')
  im.SameLine(ctx);local check_changed,check=im.Checkbox(ctx,'Check',e.check_on==true)
  if check_changed then e.check_on=check;e.check=nil end
  tip(im,ctx,(e.check and e.check.status and ('Сейчас: '..e.check.status..'\n\n') or '')..'Жёлтая линия — реально измеренная высота после ReaPitch (JS: Vocaligner Pitch Meter в take FX после ReaPitch или первым на треке). Показываются только кадры этого айтема в его текущем состоянии; тусклые — до последней правки. Воспроизведи участок, чтобы обновить.')
  if e.workspace and im.BeginPopup then
    im.SameLine(ctx);if im.Button(ctx,'Tracks...') then im.OpenPopup(ctx,'Pitch ghost tracks') end
    if im.BeginPopup(ctx,'Pitch ghost tracks') then
      local count=0
      for _,row in ipairs(e.workspace.tracks)do if (row.analyzed or 0)>0 then
        count=count+1
        local changed,on=im.Checkbox(ctx,'##pitch_ghost_'..row.guid,row.visible)
        if changed then Workspace.visible(e,on,row) end
        im.SameLine(ctx)
        if im.Selectable(ctx,string.format('%d · %s##pitch_track_%s',row.index,row.name,row.guid),row.track==e.track) then Workspace.activate_track(e,row) end
        local why
        for _,entry in ipairs(row.items)do if entry.error then why=entry.error;break end end
        tip(im,ctx,why or 'Click the name to edit this track. The checkbox controls ghost visibility.')
      end end
      if count==0 then im.TextDisabled(ctx,'No analyzed tracks') end
      im.EndPopup(ctx)
    end
  end
  if e.tool=='curve' then
    im.SameLine(ctx);if im.Button(ctx,'Copy') then e:copy_shape() end;tip(im,ctx,'Copy the first selected note\'s pitch shape.')
    im.SameLine(ctx);if im.Button(ctx,'Paste') then e:paste_shape((im.GetKeyMods(ctx)&im.Mod_Alt)~=0) end;tip(im,ctx,'Fit copied shape to selected notes; preserve its expression. Alt: free center.')
  end
  if e.tool=='vibrato' and active then
    im.SameLine(ctx)
    if im.Button(ctx,active.vibrato_replace and 'Replace' or 'Add') then
      local before=e:begin_edit();if before then e:parameter('vibrato_replace',not active.vibrato_replace,false,before);e:commit(before,'change vibrato mode') end
    end
    tip(im,ctx,'Add preserves source modulation. Replace removes it while generated vibrato is active; the Modulation setting is retained.')
  end
  if locked then im.EndDisabled(ctx) end
  --[[ Algorithm controls temporarily hidden.
  local modes=Algorithm.modes(e.r)
  if #modes>0 then
    local value=e.algorithm_value;local current_mode;local mode_names={}
    for _,mode in ipairs(modes) do
      mode_names[#mode_names+1]=mode.label
      if value and mode.id==value>>16 then current_mode=mode end
    end
    local disabled=e:busy() or e.gesture or e.stale or e.no_selection or not e.data or e.algorithm_error
    if disabled then im.BeginDisabled(ctx) end
    im.TextDisabled(ctx,'ReaPitch');im.SameLine(ctx)
    local selected=combo(im,ctx,'##pitch_algorithm',current_mode and current_mode.label or 'Algorithm unavailable',mode_names,240)
    tip(im,ctx,e.algorithm_error or 'Алгоритм ReaPitch для этого айтема. Для нового эффекта: elastique Soloist. Выбор сохраняется в проекте; исходный анализ не меняется.')
    if selected and not disabled then e:set_algorithm(modes[selected].id<<16) end
    if current_mode and #current_mode.submodes>1 then
      local sub_names={};local selected_name='Unknown mode'
      for _,sub in ipairs(current_mode.submodes) do sub_names[#sub_names+1]=sub.label;if sub.id==(value&65535) then selected_name=sub.label end end
      if w>600 then im.SameLine(ctx) end
      local sub=combo(im,ctx,'##pitch_algorithm_parameter',selected_name,sub_names,210)
      tip(im,ctx,'Параметр выбранного алгоритма ReaPitch. Названия доступны из REAPER.')
      if sub and not disabled and not selected then e:set_algorithm((current_mode.id<<16)|current_mode.submodes[sub].id) end
    end
    if disabled then im.EndDisabled(ctx) end
  end
  ]]
  if active and e.data and specs then
    local disabled=e:busy() or e.stale or e.no_selection;if disabled then Controls.disabled(im,ctx,true,quiet and not e.stale and not e.no_selection) end
    for i,spec in ipairs(specs) do
      im.SameLine(ctx)
      im.SetNextItemWidth(ctx,spec[1]=='Formant' and 100 or 85)
      local parameter=active[spec[2]]
      if spec[2]:sub(1,5)=='link_' then local wa,amount=Link.settings(active);parameter=spec[2]=='link_width' and wa or amount end
      local changed,value=im.DragDouble(ctx,'##pitch_'..spec[1],(parameter or spec[7])*spec[6],spec[6]>1 and 1 or .01,spec[3],spec[4],spec[1]..' '..spec[5])
      if im.IsItemActivated(ctx) and not disabled then e.control_before=e:begin_edit();e.control_key=spec[2] end
      if changed and not disabled then
        if not e.control_before then e.control_before=e:begin_edit();e.control_key=spec[2] end
        if e.control_before then
          e:parameter(spec[2],clamp(value,spec[3],spec[4])/spec[6],(im.GetKeyMods(ctx)&im.Mod_Alt)~=0,e.control_before)
          if spec[2]=='link_width' and select(2,Link.settings(active))==0 then e:parameter('link_amount',.5,false,e.control_before)end
        end
      end
      if im.IsItemDeactivatedAfterEdit(ctx) and e.control_key==spec[2] then local before=e.control_before;e.control_before=nil;e.control_key=nil;e:commit(before,'adjust '..spec[1]:lower())
      elseif im.IsItemDeactivated(ctx) and e.control_key==spec[2] then
        if e.control_before then e.state=e.control_before;e.notes=e.state.notes;e.display=nil end
        e.control_before=nil;e.control_key=nil;e.gesture=false
      end

    end
    if disabled then im.EndDisabled(ctx) end
  elseif e.tool=='transition' and e.data then
    im.SameLine(ctx);im.TextDisabled(ctx,'Select an orange link')
  end
  if im.PopStyleVar then im.PopStyleVar(ctx) end
  if toolbar_child then im.EndChild(ctx) end
  Progress.draw(im,ctx,e.job,e.r)
  if e.stale then im.TextWrapped(ctx,'Saved analysis is out of date. Click Analyze to edit this item.')
  elseif error then im.TextWrapped(ctx,error..' · Report...') end
  local cw,ch=im.GetContentRegionAvail(ctx);M.canvas(im,ctx,e,cw,ch)
  if im.IsWindowFocused(ctx,im.FocusedFlags_RootAndChildWindows) and not im.IsAnyItemActive(ctx) and not e:busy() then
    local mods=im.GetKeyMods(ctx);local ctrl=(mods&im.Mod_Ctrl)~=0;local alt=(mods&im.Mod_Alt)~=0
    if ctrl and im.IsKeyPressed(ctx,im.Key_Z,false) then e:undo((mods&im.Mod_Shift)~=0) end
    if ctrl and im.IsKeyPressed(ctx,im.Key_A,false) then for _,n in ipairs(e.notes or {}) do e.selected[n.id]=true end end
    if im.IsKeyPressed(ctx,im.Key_Delete,false) then e:reset_selected() end
    if ctrl and im.IsKeyPressed(ctx,im.Key_C,false) then e:copy_shape()
    elseif im.IsKeyPressed(ctx,im.Key_C,false) then e.tool=e.tool=='notes' and 'curve' or 'notes' end
    if ctrl and im.IsKeyPressed(ctx,im.Key_V,false) then e:paste_shape(alt) end
    if im.IsKeyPressed(ctx,im.Key_UpArrow,false) then e:nudge(1,alt) end
    if im.IsKeyPressed(ctx,im.Key_DownArrow,false) then e:nudge(-1,alt) end
  end
end
return M
