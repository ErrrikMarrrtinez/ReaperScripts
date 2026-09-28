-- @noindex
local load=...
local Base,Document,Index=load('core.layout'),load('core.document'),load('core.row_index')
local Parser,Inline=load('markdown.parser'),load('markdown.inline')
local Code,Diagram,Theme=load('markdown.code'),load('markdown.diagram'),load('markdown.theme')
local Layout={};Layout.__index=Layout
function Layout.new(editor)
  return setmetatable({editor=editor,document=editor.document,options=editor.options,parser=Parser.new(editor.document),
    entries={},cache={},revision=-1,generation=0,pending=0,background=1,max_width=0,work_units=0,
    line_height=22,width=600,space=8},Layout)
end
function Layout:invalidate()
  self.generation=self.generation+1;self.pending=#self.entries;self.background=1
end
function Layout:invalidate_line(i)
  local entry=self.entries[i]
  if entry and entry.generation==self.generation then
    if entry.done then self.pending=self.pending+1 end
    entry.generation=-1;self.background=math.min(self.background,i)
  end
end
function Layout:callout_collapsed(block)
  local value=self.editor.markdown_folded and self.editor.markdown_folded[block.key]
  if value==nil then return block.fold=='-' end
  return value
end
function Layout:toggle_callout(block)
  self.editor.markdown_folded=self.editor.markdown_folded or {}
  self.editor.markdown_folded[block.key]=not self:callout_collapsed(block)
  for i=block.first,block.last do self:invalidate_line(i) end
end
function Layout:set_active()
  local e=self.editor
  -- Do not move text under the pointer while selecting. Reveal only after a
  -- collapsed caret has settled; a selection retains the geometry it started in.
  if not e.options.read_only and (e.drag or (e.anchor and e.anchor~=e.caret)) then return end
  local i=e.focused and not e.options.read_only and self.document:line_at(e.caret) or nil
  local cell
  local m=i and self.parser.lines[i]
  if m and m.callout and i~=m.callout.first and self:callout_collapsed(m.callout) then self:toggle_callout(m.callout) end
  local block=m and m.block and m.block.language=='mermaid' and m.block or nil
  if self.active_block~=block then
    if self.active_block then for n=self.active_block.first,self.active_block.last do self:invalidate_line(n) end end
    if block then for n=block.first,block.last do self:invalidate_line(n) end end
    self.active_block=block
  end
  if m and m.cells then
    local p=e.caret-self.document.lines[i].start
    for c,v in ipairs(m.cells) do if p<=(v.raw_b or v.b) or c==#m.cells then cell=c;break end end
  end
  if self.active_line~=i or self.active_cell~=cell then
    self:invalidate_line(self.active_line);self:invalidate_line(i)
    self.active_line,self.active_cell=i,cell
  end
end
function Layout:configure(width,line_height,measure,font_key)
  width=math.max(1,math.floor(width))
  self.measure=measure
  if self.width~=width or self.font_key~=font_key or self.line_height~=line_height then
    self.width,self.font_key,self.line_height=width,font_key,line_height;self:invalidate()
  end
  self.space=measure(' ')
  self:sync();self:set_active()
end
function Layout:sync()
  if self.revision==self.document.revision then return end
  self.parser:sync()
  local cache,entries,counts,heights={},{},{},{}
  self.pending,self.background=0,1
  for i,line in ipairs(self.document.lines) do
    local m=self.parser.lines[i]
    local previous=self.parser.lines[i-1]
    if previous and previous.kind=='underline' then previous=self.parser.lines[i-2] end
    local after_heading=m.kind=='blank' and previous and previous.kind=='heading' or false
    local heading_blank=m.kind=='heading' and entries[i-1] and entries[i-1].after_heading or false
    local sig=table.concat({m.kind,m.level or 0,m.prefix or 0,m.language or '',m.table and m.table.columns or 0,
      m.table and table.concat(m.table.align,',') or '',self.parser.reference_version or 0},':')
    if m.callout then sig=sig..':'..tostring(m.callout.last==i) end
    if m.code_group then sig=sig..':code_end='..tostring(m.code_group.last==i) end
    if m.kind=='blank' or m.kind=='heading' then sig=sig..':gap='..tostring(after_heading or heading_blank) end
    if m.kind=='fence' and m.block.first==i then sig=sig..':'..tostring(m.block) end
    local old=self.cache[line]
    if not old or old.signature~=sig then old={generation=-1,estimate_rows=1,estimate_height=self.line_height,signature=sig} end
    old.meta=m;old.line=line;old.number=i
    old.after_heading,old.heading_blank=after_heading,heading_blank
    if m.code_group and old.segments then
      for _,seg in ipairs(old.segments) do
        local reserve=i==m.code_group.first+1 and m.code_group.language and self:code_controls_width(m.code_group) or 0
        m.code_group.width=math.max(m.code_group.width or 0,(seg.layout.max_width or 0)+reserve)
      end
      m.code_group.width_generation=self.generation
    end
    entries[i],cache[line]=old,old
    if old.generation~=self.generation or not old.done then self.pending=self.pending+1 end
    counts[i]=old.estimate_rows or 1;heights[i]=old.estimate_height or self.line_height
  end
  self.entries,self.cache=entries,cache
  self.index,self.heights=Index.new(counts),Index.new(heights)
  self.revision=self.document.revision
end
local function hidden(kind)
  return kind=='underline' or kind=='table_separator' or kind=='reference' or kind=='comment' or kind=='math_fence'
end
function Layout:build(i)
  local entry=self.entries[i];if entry.generation==self.generation then return entry end
  local m,line=entry.meta,entry.line
  local active=i==self.active_line
  local raw_table=not self.options.read_only and m.table and self.editor.markdown_raw_tables and self.editor.markdown_raw_tables[m.table.key]
  local projection_key=tostring(active)..':'..tostring(self.active_cell and active and self.active_cell)..':'..
    tostring(raw_table)..':'..self.options.font_size
  local old_segments=entry.projection_key==projection_key and entry.segments or {}
  entry.projection_key=projection_key
  entry.segments={};entry.generation=self.generation;entry.done=false
  entry.hide_text,entry.fence_label=false,nil
  entry.raw_table=raw_table
  entry.hidden=not active and hidden(m.kind) and not raw_table
  if m.callout and i>m.callout.first and self:callout_collapsed(m.callout) then entry.hidden=true end
  if m.kind=='fence' and not active then
    if m.block.first==i then entry.hide_text=true;entry.fence_label=m.language~='' and m.language or 'code'
    else entry.hide_text=true;entry.code_footer=true end
  end
  if m.kind~='fence' or m.block.first==i or active then entry.code_footer=nil end
  entry.diagram=nil
  if m.block and m.block.language=='mermaid' and self.active_block~=m.block then
    if not m.block.diagram_checked then
      m.block.diagram=Diagram.parse(self.document.lines,m.block.first+1,m.block.last-1)
      m.block.diagram_checked=true
    end
    if m.block.diagram then
      if m.block.first==i then
        entry.diagram=m.block.diagram;entry.diagram_height=Diagram.geometry(entry.diagram,self.width,self.rich_measure or self.measure,self.options.font_size)
        entry.hide_text,entry.fence_label=true,nil
      else entry.hidden=true end
    end
  end
  entry.pad_top,entry.pad_bottom=2,2
  if m.kind=='heading' then
    entry.pad_top,entry.pad_bottom=self.options.font_size*.5,self.options.font_size*.12
    -- A source blank keeps its own hit area but shares the next heading's margin.
    if entry.heading_blank then entry.pad_top=math.max(0,entry.pad_top-self.line_height*.3) end
  elseif m.kind=='table' and not raw_table then
    entry.pad_top,entry.pad_bottom=self.options.table_padding_y or 5,self.options.table_padding_y or 5
  elseif m.kind=='blank' then entry.pad_top,entry.pad_bottom=0,0
  elseif m.kind=='code' then entry.pad_top,entry.pad_bottom=1,1 end
  if m.kind=='task' or (m.kind=='list' and not m.bullet:match('%d')) then
    entry.pad_top=3
    entry.pad_bottom=3+math.max(0,self.options.list_item_spacing or self.options.font_size*.15)
  end
  if m.callout then
    entry.pad_top=m.callout.first==i and 8 or 0
    entry.pad_bottom=m.callout.last==i and 8 or 4
  end
  local function segment(a,b,x,width,sty,literal,selected,prefix,col)
    local old=old_segments and old_segments[#entry.segments+1]
    local layout,projection
    if old and old.offset==a and old.finish==b then
      layout,projection=old.layout,old.projection
    else
    local text=line.text:sub(a+1,b)
    local document=Document.new(text)
    projection=Inline.parse(text,{active=selected,literal=literal,style=sty,references=self.parser.references,footnotes=self.parser.footnotes,
      checkboxes=m.kind=='table',checkbox_width=self.options.font_size+8,font_size=self.options.font_size})
    if m.kind=='code' or m.kind=='frontmatter' then projection=Code.projection(text,m.language or (m.kind=='frontmatter' and 'yaml') or '') end
    if m.kind=='callout' and not selected and m.callout.title_start==#line.text then
      local role=Inline.style({bold=true})
      projection.next_unit=function(l,p) return #l.text,m.callout.title,role end
      prefix=0
    end
    if m.kind=='footnote' and not selected then
      local next_unit=projection.next_unit
      projection.next_unit=function(l,p)
        if p<m.prefix then return m.prefix,tostring(m.footnote or m.label)..'. ',Inline.style({muted=true}) end
        return next_unit(l,p)
      end
      prefix=0
    end
    if prefix and prefix>0 and (not selected or m.kind=='task') then
      local next_unit=projection.next_unit
      projection.next_unit=function(l,p)
        if p<prefix then return prefix,'',Inline.style(sty,{muted=true}) end
        return next_unit(l,p)
      end
    end
    local opts={wrap=not m.code_group,word_wrap=true,tab_size=self.options.tab_size,overscan=self.options.overscan,
      layout_budget=self.options.layout_budget,layout_seconds=self.options.layout_seconds}
    layout=Base.new(document,opts);layout.projection=projection
    end
    local font=Inline.style(sty).font
    local metrics=self.font_metrics and self.font_metrics[font]
    local lh=metrics and metrics.height or self.line_height*(sty.heading and Theme.font_scales[font] or 1)
    if m.kind=='task' or m.kind=='table' then lh=math.max(lh,self.options.font_size+4) end
    layout:configure(math.max(1,width),lh,self.rich_measure or self.measure,(self.font_key or '')..':'..font)
    local seg={layout=layout,offset=a,finish=b,x=x,width=width,height=lh,col=col,projection=projection}
    entry.segments[#entry.segments+1]=seg
  end
  if m.kind=='table' and not raw_table then
    local weights=self.editor.markdown_column_widths and self.editor.markdown_column_widths[m.table.key]
    local sum=0;for c=1,m.table.columns do sum=sum+(weights and weights[c] or 1) end
    local x=0
    for c,cell in ipairs(m.cells) do
      local width=self.width*(weights and weights[c] or 1)/sum
      local padding=self.options.table_padding_x or 8
      local a,b=cell.a,cell.b
      if active and self.active_cell==c then
        local caret=self.editor.caret-line.start
        a=math.min(a,math.max(cell.raw_a or a,caret));b=math.max(b,math.min(cell.raw_b or b,caret))
      end
      segment(a,b,x+padding,math.max(1,width-padding*2),{bold=m.table_row==1},false,active and self.active_cell==c,0,c)
      local seg=entry.segments[#entry.segments]
      seg.cell_left,seg.cell_width,seg.source_finish=x,width,cell.raw_b or cell.b
      x=x+width
    end
  else
    local x=0;local prefix=m.prefix or 0
    if not active or m.kind=='task' then
      if m.kind=='quote' then x=m.callout and math.max(30,self.options.font_size*1.6) or (m.depth or 1)*12+10
      elseif m.kind=='list' or m.kind=='task' then
        local marker_width=m.kind=='task' and self.options.font_size+12 or
          m.bullet:match('%d') and (self.rich_measure or self.measure)(m.bullet..' ',{font='body'})+6 or self.options.font_size*1.25
        x=(m.indent or 0)*self.space+marker_width
      end
    end
    if m.kind=='code' or m.kind=='frontmatter' or m.kind=='fence' or m.kind=='math' then x=14 end
    if m.kind=='callout' then x=math.max(30,self.options.font_size*1.6);prefix=m.callout.title_start end
    local sty={heading=m.kind=='heading' and m.level or nil,code=m.kind=='code' or m.kind=='frontmatter' or m.kind=='fence',
      bold=m.kind=='callout',muted=m.kind=='comment' or m.kind=='reference' or m.checked,strike=m.checked,italic=m.kind=='math'}
    segment(0,#line.text,x,math.max(1,self.width-x-6),sty,
      m.kind=='code' or m.kind=='frontmatter' or m.kind=='fence' or m.kind=='math' or entry.hidden,
      active,prefix)
  end
  return entry
end
function Layout:work_line(i,budget,target)
  local entry=self.entries[i]
  if not entry or budget.left<=0 or budget.clock()>=budget.deadline then return end
  if entry.generation==self.generation and entry.done then return end
  entry=self:build(i)
  local was_done=entry.done
  local rows,height,done=0,0,true
  for _,seg in ipairs(entry.segments) do
    local before=seg.layout.work_units
    seg.layout:work_line(1,budget,target)
    self.work_units=self.work_units+seg.layout.work_units-before
    rows=rows+seg.layout:row_count()
    height=math.max(height,seg.layout:row_count()*seg.height)
    done=done and seg.layout.pending==0
  end
  if entry.hidden then height=.01
  elseif entry.diagram then height=entry.diagram_height
  elseif entry.code_footer then height=8
  elseif entry.fence_label then height=4
  elseif entry.meta.kind=='blank' then
    height=self.line_height*(entry.after_heading and .3 or .65)
  elseif entry.meta.kind=='rule' and i~=self.active_line then height=self.line_height*1.5
  elseif entry.meta.kind=='image' and i~=self.active_line then
    local asset=self.images and self.images[entry.meta.path]
    entry.image=asset
    if asset and asset.handle then height=math.min(360,asset.height*math.min(self.width,asset.width)/math.max(1,asset.width))+self.line_height+12
    else height=self.line_height*2.5 end
  end
  entry.done=done;entry.estimate_rows=math.max(1,rows)
  local block=entry.meta.code_group
  if block then
    if block.width_generation~=self.generation then block.width=0;block.width_generation=self.generation end
    for _,seg in ipairs(entry.segments) do
      local reserve=i==block.first+1 and block.language and self:code_controls_width(block) or 0
      block.width=math.max(block.width or 0,(seg.layout.max_width or 0)+reserve)
    end
    if i==block.last and not entry.code_footer and not entry.diagram then entry.pad_bottom=12 end
  end
  entry.estimate_height=entry.hidden and .01 or height+entry.pad_top+entry.pad_bottom
  self.index:set(i,entry.estimate_rows);self.heights:set(i,entry.estimate_height)
  if done and not was_done then self.pending=self.pending-1 end
end
function Layout:height() return self.heights:prefix(#self.entries) end
function Layout:row_count() return self.index:prefix(#self.entries) end
function Layout:line_y(i) return self.heights:prefix(i-1) end
function Layout:line_at_y(y) return self.heights:find(math.max(1,y+1)) end
function Layout:row_at_y(y)
  local i=self:line_at_y(y);local entry=self.entries[i]
  local n=self.index:prefix(i-1)+1
  if entry and entry.generation==self.generation and entry.segments[1] then
    local seg=entry.segments[1]
    n=n+math.max(0,math.min(seg.layout:row_count()-1,math.floor((y-self:line_y(i)-entry.pad_top)/seg.height)))
  end
  return n
end
function Layout:row(number)
  if number<1 or number>self:row_count() then return nil end
  local i,j=self.index:find(number);local entry=self.entries[i]
  if entry.generation~=self.generation then return nil,entry.line,i,j end
  for _,seg in ipairs(entry.segments) do
    local count=seg.layout:row_count()
    if j<=count then
      local raw=seg.layout:row(j);if not raw then return nil,entry.line,i,j end
      local dx=0
      if seg.col and entry.meta.table.align[seg.col]~='left' and seg.layout.pending==0 then
        dx=math.max(0,seg.width-raw.width)*(entry.meta.table.align[seg.col]=='center' and .5 or 1)
      end
      local block=entry.meta.code_group
      local scroll=block and self:code_state(block).x or 0
      local code_right=self.width-14
      if block and block.language and i==block.first+1 and self.active_line~=block.first then code_right=code_right-self:code_controls_width(block) end
      local row_height=entry.meta.kind=='blank' and entry.estimate_height or seg.height
      return {a=seg.offset+raw.a,b=seg.offset+raw.b,width=raw.width,raw=raw,segment=seg,entry=entry,code_group=block,code_right=code_right,
        x=seg.x+dx-scroll,y=self:line_y(i)+entry.pad_top+(j-1)*seg.height,height=row_height,partial=raw.partial,
        number=number,hidden=entry.hidden},entry.line,i,j
    end
    j=j-count
  end
end
function Layout:row_y(number)
  local row,_,i=self:row(number)
  return row and row.y or self:line_y(i or 1)
end
function Layout:row_height(number) local row=self:row(number);return row and row.height or self.line_height end
function Layout:x_at(row,line,offset)
  return row.x+row.segment.layout:x_at(row.raw,row.segment.layout.document.lines[1],offset-row.segment.offset)
end
function Layout:position(pos,affinity)
  local i,line=self.document:line_at(pos);local entry=self.entries[i]
  if not entry or entry.generation~=self.generation then return nil end
  local offset=pos-line.start;local n=self.index:prefix(i-1)
  for c,seg in ipairs(entry.segments) do
    if offset<=(seg.source_finish or seg.finish) or c==#entry.segments then
      local localpos=math.max(0,math.min(seg.finish-seg.offset,offset-seg.offset))
      local x,_,j=seg.layout:position(localpos,affinity)
      if not x then return nil end
      local row=self:row(n+j)
      return row.x+x,row.y,n+j,row.height
    end
    n=n+seg.layout:row_count()
  end
end
function Layout:hit_row(number,x)
  local row,line=self:row(number);if not row then return nil end
  local p,aff=row.segment.layout:hit_row(select(4,self:row(number)),x-row.x)
  if p then return line.start+row.segment.offset+p,aff end
end
function Layout:hit(x,y)
  local i=self:line_at_y(y);local entry=self.entries[i]
  if not entry or entry.generation~=self.generation then return nil end
  local n=self.index:prefix(i-1)
  for c,seg in ipairs(entry.segments) do
    if not seg.col or x<(seg.cell_left+seg.cell_width) or c==#entry.segments then
      local j=math.max(1,math.min(seg.layout:row_count(),math.floor((y-self:line_y(i)-entry.pad_top)/seg.height)+1))
      return self:hit_row(n+j,x)
    end
    n=n+seg.layout:row_count()
  end
end
function Layout:visible_units(row,line,left,right,callback)
  line=row.entry.line
  if row.code_group then left,right=math.max(left,14),math.min(right,row.code_right) end
  row.segment.layout:visible_units(row.raw,row.segment.layout.document.lines[1],left-row.x,right-row.x,
    function(display,x,width,role,a,b)
      return callback(display,x+row.x,width,role,line.start+row.segment.offset+a,line.start+row.segment.offset+b)
    end)
end
function Layout:code_controls_width(block)
  local measure=self.rich_measure or self.measure
  local copy=measure('copy',{font='small'})+24
  local both=measure(block.language or '',{font='small'})+copy+10
  return math.min(self.width*.45,both<=self.width*.45 and both or copy)
end
function Layout:code_state(block)
  local e=self.editor
  e.markdown_code_scroll=e.markdown_code_scroll or setmetatable({},{__mode='k'})
  local state=e.markdown_code_scroll[block.key]
  if not state then state={x=0};e.markdown_code_scroll[block.key]=state end
  state.max=math.max(0,(block.width or 0)-math.max(1,self.width-28))
  state.x=math.max(0,math.min(state.max,state.x))
  return state
end
function Layout:reveal_position(pos)
  local x,_,n=self:position(pos,self.editor.affinity)
  if not n then return end
  local row=self:row(n);if not row or not row.code_group then return end
  local state=self:code_state(row.code_group)
  if x<14 then state.x=state.x+x-14
  elseif x>row.code_right-2 then state.x=state.x+x-row.code_right+2 end
  state.x=math.max(0,math.min(state.max,state.x))
end
function Layout:drag_horizontal(x,y,dt)
  local entry=self.entries[self:line_at_y(y)]
  local block=entry and entry.meta.code_group
  if not block or entry.diagram then return end
  local right=self.width-14
  if block.language and entry.number==block.first+1 then right=right-self:code_controls_width(block) end
  local dx=x<14 and x-14 or x>right and x-right or 0
  if dx~=0 then
    local state=self:code_state(block)
    state.x=math.max(0,math.min(state.max,state.x+math.max(-1800,math.min(1800,dx*12))*dt))
  end
end
function Layout:visible_range(scroll,height)
  local a,b=self:line_at_y(math.max(0,scroll)),self:line_at_y(scroll+height)
  return self.index:prefix(a-1)+1,self.index:prefix(b)
end
function Layout:each_visible(scroll,height,fn)
  local first,last=self:line_at_y(math.max(0,scroll-self.line_height)),self:line_at_y(scroll+height+self.line_height)
  for i=first,last do
    local entry=self.entries[i]
    if entry.generation==self.generation and not entry.hidden then
      local n=self.index:prefix(i-1)
      for _,seg in ipairs(entry.segments) do
        local a,b=seg.layout:visible_range(scroll-self:line_y(i)-entry.pad_top,height,1)
        for j=a,b do local row,line=self:row(n+j);if row and fn(row,line,n+j)==false then return end end
        n=n+seg.layout:row_count()
      end
    end
  end
end
function Layout:tick(first_row,row_count,caret,clock,units,seconds,anchor)
  self:sync();self:set_active()
  local budget={left=units or self.options.layout_budget,clock=clock,deadline=clock()+(seconds or self.options.layout_seconds)}
  local y=self:row_y(first_row)
  local target=caret or (anchor and anchor.pos)
  if target then
    local i=self.document:line_at(target)
    self:work_line(i,budget)
    local _,cy=self:position(target,'downstream')
    if cy then
      if anchor and not caret then y=cy+anchor.fraction*self:row_height(select(3,self:position(target,'downstream')))
      elseif cy<y then y=cy elseif cy>y+row_count*self.line_height then y=cy-row_count*self.line_height+self.line_height end
    end
  end
  local i=self:line_at_y(y)
  local bottom=y+(row_count+self.options.overscan)*self.line_height
  while i<=#self.entries and self:line_y(i)<bottom and budget.left>0 and clock()<budget.deadline do
    local local_rows=math.max(1,math.ceil((bottom-self:line_y(i))/self.line_height))
    self:work_line(i,budget,local_rows);i=i+1
  end
  while self.background<=#self.entries and budget.left>0 and clock()<budget.deadline do
    self:work_line(self.background,budget)
    local entry=self.entries[self.background]
    if entry.generation~=self.generation or not entry.done then break end
    self.background=self.background+1
  end
  self.max_width=self.width
  return budget.left
end
function Layout:move_vertical(pos,affinity,delta,x)
  local cx,y,n,h=self:position(pos,affinity);if not cx then return nil end
  x=x or cx
  local target=delta<0 and y-.5 or y+h+.5
  if math.abs(delta)>1 then target=y+delta*self.line_height end
  return self:hit(x,math.max(0,math.min(self:height()-1,target)))
end
return Layout
