-- @noindex
local load=...
local Theme,Table,Commands=load('markdown.theme'),load('markdown.table'),load('markdown.commands')
local View={}

function View.prepare(e,ctx,im)
  local ui=e.ui
  ui.markdown=ui.markdown or {fonts={},glyphs={},images={},asset_queue={}}
  local md=ui.markdown
  local theme=Theme.get(e.options.markdown_theme)
  md.theme=theme
  e.options.background,e.options.text_color,e.options.caret_color=theme.background,theme.text,theme.accent
  e.options.selection_color,e.options.inactive_selection_color=theme.selection,theme.selection & 0xFFFFFF55
  md.current={};local metrics={}
  for name,scale in pairs(Theme.font_scales) do
    local family=name=='code' and (e.options.code_font_family or 'Consolas') or e.options.font_family
    local size=math.max(8,math.floor(e.options.font_size*scale+.5))
    local flags=0
    if name=='bold' or name=='bold_italic' or name:match('^h%d') then flags=flags|im.FontFlags_Bold end
    if name=='italic' or name=='bold_italic' then flags=flags|im.FontFlags_Italic end
    local key=family..':'..size..':'..flags
    if not md.fonts[key] then local font=im.CreateFont(family,size,flags);im.Attach(ctx,font);md.fonts[key]=font end
    md.current[name]={font=md.fonts[key],size=size,key=key}
    metrics[name]={height=math.max(size+2,math.ceil(size*(e.options.line_spacing or 1.2))),size=size}
  end
  e.layout.font_metrics=metrics
  e.layout.rich_measure=function(text,role)
    local font=md.current[role and role.font or 'body'] or md.current.body
    local cache=md.glyphs[font.key];if not cache then cache={};md.glyphs[font.key]=cache end
    if cache[text]==nil then
      im.PushFont(ctx,font.font)
      cache[text]=#text<=4 and im.CalcTextSize(ctx,string.rep(text,128))/128 or im.CalcTextSize(ctx,text)
      im.PopFont(ctx)
    end
    return cache[text]
  end
  local asset_source=e.options.markdown_base_path or ''
  local asset_source_changed=md.asset_source~=asset_source or md.asset_resolver~=e.options.resolve_image
  if asset_source_changed then
    for _,asset in pairs(md.images) do if asset.handle then im.Detach(ctx,asset.handle) end end
    md.images={};md.asset_source=asset_source;md.asset_resolver=e.options.resolve_image
    e.layout:invalidate()
  end
  local parsed=e.layout.parser:sync()
  if parsed or asset_source_changed then
    md.asset_queue={}
    md.asset_lines={}
    for i,m in ipairs(e.layout.parser.lines) do
      if m.kind=='image' then
        if not md.asset_lines[m.path] then
          md.asset_lines[m.path]={}
          if not md.images[m.path] then md.asset_queue[#md.asset_queue+1]=m.path end
        end
        local lines=md.asset_lines[m.path];lines[#lines+1]=e.document.lines[i]
      end
    end
  end
  -- Native resources are attached outside Begin, like fonts. Never run network
  -- requests or a renderer process from the UI frame.
  for _=1,2 do
    local path=table.remove(md.asset_queue,1);if not path then break end
    local resolved=path:match('^(.-)%s+"') or path
    resolved=resolved:match('^(.-)|%d') or resolved
    if e.options.resolve_image then resolved=e.options.resolve_image(e,path) end
    if resolved and not resolved:match('^%a+://') then
      if not resolved:match('^%a:[/\\]') and not resolved:match('^[/\\]') then
        resolved=(e.options.markdown_base_path or '')..resolved
      end
      local ok,handle=pcall(im.CreateImage,resolved)
      if ok and handle then
        im.Attach(ctx,handle)
        local w,h=im.Image_GetSize(handle)
        md.images[path]={handle=handle,width=w,height=h,path=resolved}
      else md.images[path]={error=tostring(handle)} end
    else md.images[path]={external=true,path=resolved} end
    for _,line in ipairs(md.asset_lines[path] or {}) do
      local entry=e.layout.cache[line]
      if entry then e.layout:invalidate_line(entry.number) end
    end
  end
  e.layout.images=md.images
end
function View.dispose(e)
  local ui=e.ui;local md=ui.markdown
  for _,font in pairs(md.fonts) do ui.im.Detach(ui.ctx,font) end
  for _,asset in pairs(md.images) do if asset.handle then ui.im.Detach(ui.ctx,asset.handle) end end
  ui.markdown=nil
end
local function text(im,dl,md,key,x,y,color,value)
  local f=md.current[key] or md.current.body
  im.DrawList_AddTextEx(dl,f.font,f.size,x,y,color,value)
end
local function inside(x,y,rect)
  return x>=rect.x1 and x<=rect.x2 and y>=rect.y1 and y<=rect.y2
end
local function zones(e,view,mx,my)
  local l,o=e.layout,e.options
  local ox,oy=view.x+o.padding+(l.offset_x or 0)-e.scroll_x,view.y+o.padding-e.scroll_y
  local result,code_groups={},{};local first,last=l:line_at_y(math.max(0,e.scroll_y-o.padding)),l:line_at_y(e.scroll_y+view.h)
  for i=first,last do
    local entry=l.entries[i];local m=entry.meta
    if entry.generation==l.generation and not entry.hidden then
      local y,h=oy+l:line_y(i),entry.estimate_height
      local block=m.code_group
      if block and not entry.diagram and not code_groups[block] then
        code_groups[block]=true
        local top,bottom=oy+l:line_y(block.first),oy+l:line_y(block.last)+l.heights.counts[block.last]
        result[#result+1]={kind='code',block=block,x1=ox,y1=top,x2=ox+l.width,y2=bottom}
        local state=l:code_state(block)
        if state.max>0 then
          local track=l.width-28;local thumb=math.max(24,track*track/(track+state.max))
          result[#result+1]={kind='code_scroll',block=block,track=track,thumb=thumb,
            x1=ox+14,y1=bottom-11,x2=ox+l.width-14,y2=bottom-1}
        end
      end
      if entry.diagram then
        result[#result+1]={kind='diagram',block=m.block,x1=ox+entry.diagram.left,y1=y,x2=ox+entry.diagram.right,y2=y+h}
      elseif entry.fence_label then
        local font=e.ui.markdown.current.small
        local ch=font.size+6;local cw=l.rich_measure('copy',{font='small'})+14
        local body=l.entries[math.min(#l.entries,i+1)]
        local cy=oy+l:line_y(math.min(#l.entries,i+1))+(body.pad_top or 1)+((body.segments and body.segments[1].height or l.line_height)-ch)/2
        result[#result+1]={kind='code_copy',block=m.block,x1=ox+l.width-14-cw,y1=cy,x2=ox+l.width-14,y2=cy+ch}
      elseif m.kind=='callout' then
        local cy=y+entry.pad_top+entry.segments[1].height/2
        result[#result+1]={kind='callout_fold',block=m.callout,x1=ox+5,y1=cy-11,x2=ox+25,y2=cy+11}
      elseif m.kind=='task' then
        local top=y+entry.pad_top+(entry.segments[1].height-o.font_size-4)/2
        result[#result+1]={kind='task',line=i,x1=ox+(m.indent or 0)*l.space,y1=top,
          x2=ox+(m.indent or 0)*l.space+o.font_size+4,y2=top+o.font_size+4}
      elseif m.kind=='table' and not entry.raw_table then
        for c,seg in ipairs(entry.segments) do
          result[#result+1]={kind='cell',group=m.table,row=m.table_row,col=c,
            x1=ox+seg.cell_left,y1=y,x2=ox+seg.cell_left+seg.cell_width,y2=y+h}
        end
        if mx>=ox-16 and mx<=ox+l.width+16 then
          local boundary=math.abs(my-y)<8 and y or math.abs(my-y-h)<8 and y+h or nil
          if boundary and not (m.table_row==1 and boundary==y) then
            local row=m.table_row+(boundary==y+h and 1 or 0)
            result[#result+1]={kind='add_row',group=m.table,row=m.table_row,value=row,x1=ox-16,y1=boundary-8,x2=ox+2,y2=boundary+8,guide=boundary}
          end
        end
        if m.table_row==1 and my>=y-16 and my<=y+12 then
          for c,seg in ipairs(entry.segments) do
            local x=ox+seg.cell_left
            if math.abs(mx-x)<12 then result[#result+1]={kind='add_column',group=m.table,col=c,value=c,x1=x-8,x2=x+8,y1=y-14,y2=y+2};break end
          end
          if math.abs(mx-ox-l.width)<14 then
            result[#result+1]={kind='add_column',group=m.table,col=m.table.columns,value=m.table.columns+1,
              x1=ox+l.width-8,x2=ox+l.width+8,y1=y-14,y2=y+2}
          end
        end
        if m.table_row==1 and my>y+12 and my<y+h then
          for c=1,#entry.segments-1 do
            local seg=entry.segments[c];local x=ox+seg.cell_left+seg.cell_width
            if math.abs(mx-x)<4 then result[#result+1]={kind='resize_column',group=m.table,col=c,x1=x-4,x2=x+4,y1=y+12,y2=y+h};break end
          end
        end
      elseif m.kind=='table' and entry.raw_table then
        result[#result+1]={kind='cell',group=m.table,row=m.table_row,col=1,x1=ox,y1=y,x2=ox+l.width,y2=y+h}
      end
    end
  end
  l:each_visible(e.scroll_y-o.padding,view.h,function(row,line)
    l:visible_units(row,line,0,l.width,function(_,x,_,role,a)
      if role and role.checkbox then
        local top=oy+row.y+(row.height-o.font_size-4)/2
        result[#result+1]={kind='task_cell',checked=role.checked,check_at=a+1,
          x1=ox+x,y1=top,x2=ox+x+o.font_size+4,y2=top+o.font_size+4}
      end
    end)
  end)
  return result
end
local function anchor_key(value)
  value=value:gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end)
  value=load('core.utf8').normalize(value):gsub('[ \t]+#+[ \t]*$','')
  local projection=load('markdown.inline').parse(value)
  local p,parts=0,{}
  while p<#value do local q,display=projection.next_unit({text=value},p);parts[#parts+1]=display;p=q end
  value=table.concat(parts);parts={}
  for _,cp in utf8.codes(value) do
    -- Lua's byte-based lower/%p depend on the host locale and can corrupt UTF-8.
    if cp>=65 and cp<=90 or cp>=0x410 and cp<=0x42F then cp=cp+32
    elseif cp==0x401 then cp=0x451 end
    if cp==45 or cp==95 or cp==0xA0 or cp>=9 and cp<=13 then cp=32 end
    local punctuation=cp>=33 and cp<=47 or cp>=58 and cp<=64 or
      cp>=91 and cp<=96 or cp>=123 and cp<=126
    if not punctuation then parts[#parts+1]=utf8.char(cp) end
  end
  return table.concat(parts):gsub(' +',' '):match('^ *(.-) *$')
end
local function open_link(e,url)
  e.layout.parser:sync()
  if url:sub(1,2)=='#^' then
    local target=url:sub(3):gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end)
    for i,m in ipairs(e.layout.parser.lines) do if m.kind=='footnote' and m.label==target then e:scroll_to(e.document.lines[i].start,'start');return end end
  elseif url:sub(1,1)=='#' then
    local target=anchor_key(url:sub(2))
    for _,h in ipairs(e.layout.parser.headings) do
      if anchor_key(h.text)==target then e:scroll_to(e.document.lines[h.line].start,'start');return end
    end
  end
  e.last_link=url
  if e.options.on_open_link then e.options.on_open_link(e,url)
  elseif reaper and reaper.CF_ShellExecute and url:match('^https?://') then reaper.CF_ShellExecute(url) end
end
local function table_menu(e,im,ctx,zone)
  if not im.BeginPopup(ctx,'##markdown_table') then return false end
  local consumed=false
  local function item(label,operation,value)
    if im.MenuItem(ctx,label) then
      Table.edit(e,zone.group,operation,zone.row,zone.col,value);consumed=true
    end
  end
  im.TextDisabled(ctx,'Таблица')
  item('Строка выше','add_row',math.max(2,zone.row));item('Строка ниже','add_row',zone.row+1)
  item('Колонка слева','add_column',zone.col);item('Колонка справа','add_column',zone.col+1)
  im.Separator(ctx)
  item('Выровнять слева','align','left');item('По центру','align','center');item('Справа','align','right')
  im.Separator(ctx)
  item('Строку вверх','move_row',-1);item('Строку вниз','move_row',1)
  item('Колонку влево','move_column',-1);item('Колонку вправо','move_column',1)
  item('Сортировать по возрастанию','sort','ascending');item('По убыванию','sort','descending')
  im.Separator(ctx)
  item('Удалить строку','delete_row');item('Удалить колонку','delete_column')
  local raw=e.markdown_raw_tables and e.markdown_raw_tables[zone.group.key]
  if im.MenuItem(ctx,raw and 'Показать таблицей' or 'Исходник таблицы') then
    e.markdown_raw_tables=e.markdown_raw_tables or {};e.markdown_raw_tables[zone.group.key]=not raw
    for i=zone.group.first,zone.group.last do e.layout:invalidate_line(i) end
    e:set_caret(e.document.lines[zone.group.rows[zone.row]].start);consumed=true
  end
  im.EndPopup(ctx);return consumed
end
function View.before_layout(e,im,ctx)
  local md=e.ui.markdown
  if md.code_drag then
    if im.IsMouseReleased(ctx,im.MouseButton_Left) then md.code_drag=nil
    else
      local r=md.code_drag;local mx=im.GetMousePos(ctx);local state=e.layout:code_state(r.block)
      state.x=math.max(0,math.min(state.max,(mx-r.x1-r.grab)/math.max(1,r.track-r.thumb)*state.max))
      e.follow_caret=false
    end
  end
  if md.resize then
    if im.IsMouseReleased(ctx,im.MouseButton_Left) then md.resize=nil;return end
    local mx=im.GetMousePos(ctx)
    if md.resize.last_x==mx then return end
    md.resize.last_x=mx
    local r=md.resize;local delta=(mx-r.x)/math.max(1,e.layout.width)*r.sum
    local weights={table.unpack(r.weights)};local minimum=math.min(.25,r.sum/r.group.columns/3)
    weights[r.col]=math.max(minimum,math.min(r.weights[r.col]+r.weights[r.col+1]-minimum,r.weights[r.col]+delta))
    weights[r.col+1]=r.weights[r.col]+r.weights[r.col+1]-weights[r.col]
    e.markdown_column_widths=e.markdown_column_widths or {};e.markdown_column_widths[r.group.key]=weights
    for i=r.group.first,r.group.last do e.layout:invalidate_line(i) end
  end
end
function View.mouse(e,im,ctx,view,hovered,clicked)
  local md=e.ui.markdown
  local mx,my=im.GetMousePos(ctx);md.zones=zones(e,view,mx,my)
  local link
  if hovered and (e.options.read_only or im.IsKeyDown(ctx,im.Mod_Ctrl)) then
    local l=e.layout
    local x,y=mx-view.x-e.options.padding-(l.offset_x or 0)+e.scroll_x,my-view.y-e.options.padding+e.scroll_y
    l:each_visible(y,1,function(row,line)
      if y>=row.y and y<row.y+row.height and not row.entry.hide_text then
        l:visible_units(row,line,x,x,function(_,left,width,role)
          if role and role.link and x>=left and x<left+width then link=role.link;return false end
        end)
      end
    end)
  end
  md.hover_link=link
  if link then im.SetTooltip(ctx,link) end
  if md.pending_link then
    local pending=md.pending_link
    if math.abs(mx-pending.x)>4 or math.abs(my-pending.y)>4 then pending.cancelled=true end
    if im.IsMouseReleased(ctx,im.MouseButton_Left) then
      md.pending_link=nil
      if not pending.cancelled and link==pending.url then
        e.drag=nil;e.follow_caret=false;open_link(e,link);return true
      end
    end
  end
  if link and clicked and not im.IsKeyDown(ctx,im.Mod_Shift) then
    md.pending_link={url=link,x=mx,y=my}
    if not e.options.read_only then return true end
  end
  if md.table_context and table_menu(e,im,ctx,md.table_context) then return true end
  if md.code_drag then return true end
  if md.resize then im.SetMouseCursor(ctx,im.MouseCursor_ResizeEW);return true end
  if not hovered then return false end
  for n=#md.zones,1,-1 do
    local z=md.zones[n]
    if inside(mx,my,z) then
      if z.kind=='code_copy' then
        im.SetMouseCursor(ctx,im.MouseCursor_Hand)
        if clicked then
          local first=e.document.lines[z.block.first+1]
          local last=e.document.lines[z.block.last-(z.block.closed and 1 or 0)]
          im.SetClipboardText(ctx,first and last and first.start<=last.finish and e.document.text:sub(first.start+1,last.finish) or '')
          md.copied_block,md.copied_at=z.block.key,e.clock();return true
        end
      elseif z.kind=='code_scroll' and clicked then
        local state=e.layout:code_state(z.block)
        local start=z.x1+(z.track-z.thumb)*state.x/state.max
        z.grab=mx>=start and mx<=start+z.thumb and mx-start or z.thumb/2
        state.x=math.max(0,math.min(state.max,(mx-z.x1-z.grab)/math.max(1,z.track-z.thumb)*state.max))
        md.code_drag=z;e.drag=nil;e.follow_caret=false;return true
      elseif z.kind=='code' and not im.IsKeyDown(ctx,im.Mod_Ctrl) then
        local wheel,horizontal=im.GetMouseWheel(ctx)
        local delta=horizontal+(im.IsKeyDown(ctx,im.Mod_Shift) and wheel or 0)
        if delta~=0 then
          local state=e.layout:code_state(z.block)
          state.x=math.max(0,math.min(state.max,state.x-delta*e.options.font_size*3))
          e.follow_caret=false;return true
        end
      elseif z.kind=='cell' and not e.options.read_only and im.IsMouseClicked(ctx,im.MouseButton_Right) then
        md.table_context=z;im.OpenPopup(ctx,'##markdown_table');return true
      elseif z.kind=='resize_column' and not e.options.read_only then
        im.SetMouseCursor(ctx,im.MouseCursor_ResizeEW)
        if clicked then
          local weights={};local sum=0
          for c=1,z.group.columns do weights[c]=e.markdown_column_widths and e.markdown_column_widths[z.group.key] and e.markdown_column_widths[z.group.key][c] or 1;sum=sum+weights[c] end
          md.resize={group=z.group,col=z.col,weights=weights,sum=sum,x=mx}
        end
        return true
      elseif z.kind=='add_row' or z.kind=='add_column' then
        if not e.options.read_only then
          im.SetMouseCursor(ctx,im.MouseCursor_Hand)
          if clicked then Table.edit(e,z.group,z.kind,z.row,z.col,z.value);return true end
        end
      elseif z.kind=='diagram' and clicked and not e.options.read_only then
        e:set_caret(e.document.lines[z.block.first+1].start);e:focus();return true
      elseif z.kind=='callout_fold' and clicked then
        if e.layout.active_line and e.layout.active_line>z.block.first and e.layout.active_line<=z.block.last then
          e:set_caret(e.document.lines[z.block.first].start);e.follow_caret=false
        end
        e.layout:toggle_callout(z.block);return true
      elseif z.kind=='task' or z.kind=='task_cell' then
        -- The native Checkbox submitted after painting owns this pointer area.
        return clicked
      end
    end
  end
  return false
end
function View.draw(e,im,ctx,view,focused)
  local md,l,o=e.ui.markdown,e.layout,e.options
  local t,dl=md.theme,im.GetWindowDrawList(ctx)
  local ox,oy=view.x+o.padding+(l.offset_x or 0)-e.scroll_x,view.y+o.padding-e.scroll_y
  local first,last=l:line_at_y(math.max(0,e.scroll_y-o.padding)),l:line_at_y(e.scroll_y+view.h)
  local mx,my=im.GetMousePos(ctx)
  if md.hover_link then im.SetMouseCursor(ctx,im.MouseCursor_Hand) end
  local callouts,code_groups={},{}
  im.DrawList_PushClipRect(dl,view.x+1,view.y+1,view.x+view.w,view.y+view.h,true)
  for i=first,last do
    local entry=l.entries[i];local m=entry.meta
    if entry.generation==l.generation and not entry.hidden then
      local y,h=oy+l:line_y(i),entry.estimate_height
      if entry.diagram then
        local graph=entry.diagram
        im.DrawList_AddRectFilled(dl,ox+graph.left,y,ox+graph.right,y+h,t.panel,6)
        for _,edge in ipairs(graph.edges) do
          local a,b=edge.from,edge.to
          local x1,y1,x2,y2
          if graph.horizontal then x1,y1,x2,y2=ox+a.x+a.w,y+a.y+a.h/2,ox+b.x,y+b.y+b.h/2
          else x1,y1,x2,y2=ox+a.x+a.w/2,y+a.y+a.h,ox+b.x+b.w/2,y+b.y end
          im.DrawList_AddLine(dl,x1,y1,x2,y2,t.muted,1.5)
          local angle=math.atan(y2-y1,x2-x1)
          for _,sign in ipairs({-1,1}) do
            im.DrawList_AddLine(dl,x2,y2,x2-8*math.cos(angle+sign*.45),y2-8*math.sin(angle+sign*.45),t.muted,1.5)
          end
          if edge.label then text(im,dl,md,'small',(x1+x2)/2+4,(y1+y2)/2,t.muted,edge.label) end
        end
        for _,node in ipairs(graph.nodes) do
          local x1,y1=ox+node.x,y+node.y
          im.DrawList_AddRectFilled(dl,x1,y1,x1+node.w,y1+node.h,t.table_header,node.shape=='round' and 18 or 5)
          im.DrawList_AddRect(dl,x1,y1,x1+node.w,y1+node.h,t.accent,node.shape=='round' and 18 or 5)
          local f=md.current.body
          local pad=graph.padding
          im.DrawList_AddTextEx(dl,f.font,f.size,x1+pad,y1+pad,t.text,node.label,node.w-pad*2,x1+4,y1+4,x1+node.w-4,y1+node.h-4)
        end
      elseif m.code_group then
        local block=m.code_group
        if not code_groups[block] then
          code_groups[block]=true
          local top,bottom=oy+l:line_y(block.first),oy+l:line_y(block.last)+l.heights.counts[block.last]
          im.DrawList_AddRectFilled(dl,ox,top,ox+l.width,bottom,t.code_bg,5)
        end
      elseif m.kind=='math' then
        im.DrawList_AddRectFilled(dl,ox,y,ox+l.width,y+h,t.code_bg,0)
      elseif m.kind=='callout' or m.callout then
        local block=m.callout
        if not callouts[block] then
          callouts[block]=true
          local top,bottom=oy+l:line_y(block.first),oy+l:line_y(block.last)+l.heights.counts[block.last]
          local accent=(block.kind=='tip' or block.kind=='success') and t.success or
            (block.kind=='warning' or block.kind=='caution') and t.warning or t.accent
          im.DrawList_AddRectFilled(dl,ox,top,ox+l.width,bottom,(accent & 0xFFFFFF00)|0x18,5)
          im.DrawList_AddRectFilled(dl,ox,top,ox+3,bottom,accent)
          local header=l.entries[block.first]
          local cy=top+(header.pad_top or 8)+(header.segments and header.segments[1].height or l.line_height)/2
          if l:callout_collapsed(block) then
            im.DrawList_AddLine(dl,ox+12,cy-4,ox+16,cy,t.muted,1.5)
            im.DrawList_AddLine(dl,ox+16,cy,ox+12,cy+4,t.muted,1.5)
          else
            im.DrawList_AddLine(dl,ox+10,cy-2,ox+14,cy+2,t.muted,1.5)
            im.DrawList_AddLine(dl,ox+14,cy+2,ox+18,cy-2,t.muted,1.5)
          end
        end
      elseif m.kind=='quote' then im.DrawList_AddRectFilled(dl,ox+4,y,ox+7,y+h,t.border)
      elseif m.kind=='table' and not entry.raw_table then
        local bg=m.table_row==1 and t.table_header or m.table_row%2==0 and t.table_alt or t.background
        im.DrawList_AddRectFilled(dl,ox,y,ox+l.width,y+h,bg)
        im.DrawList_AddRect(dl,ox,y,ox+l.width,y+h,t.border)
        for c=2,#entry.segments do
          local x=ox+entry.segments[c].cell_left;im.DrawList_AddLine(dl,x,y,x,y+h,t.border)
        end
      elseif m.kind=='rule' and l.active_line~=i then
        im.DrawList_AddLine(dl,ox,y+h/2,ox+l.width,y+h/2,t.border)
      elseif m.kind=='image' and l.active_line~=i then
        im.DrawList_AddRectFilled(dl,ox,y,ox+l.width,y+h,t.panel,6)
        if entry.image and entry.image.handle then
          local w=math.min(l.width,entry.image.width,(h-l.line_height-12)*entry.image.width/entry.image.height)
          local ih=w*entry.image.height/entry.image.width
          im.DrawList_AddImage(dl,entry.image.handle,ox+(l.width-w)/2,y+4,ox+(l.width+w)/2,y+4+ih)
        else text(im,dl,md,'body',ox+14,y+12,t.muted,'Изображение · '..(m.alt or m.path)) end
        text(im,dl,md,'code',ox+14,y+h-l.line_height-2,t.muted,m.path)
      end
      if m.kind=='list' and l.active_line~=i then
        local x=ox+(m.indent or 0)*l.space
        text(im,dl,md,'body',x+4,y+2,t.muted,m.bullet:match('%d') and m.bullet or '•')
      end
    end
  end
  -- Inline backgrounds belong BELOW selection, just like block backgrounds.
  l:each_visible(e.scroll_y-o.padding,view.h,function(row,line)
    local kind=row.entry.meta.kind
    if row.entry.hide_text or row.code_group or ((kind=='rule' or kind=='image') and l.active_line~=row.entry.number) then return end
    local left,right,color,keycap
    local function fill()
      if left then
        im.DrawList_AddRectFilled(dl,ox+left,oy+row.y+1,ox+right,oy+row.y+row.height-1,color,3)
        if keycap then im.DrawList_AddRect(dl,ox+left,oy+row.y+1,ox+right,oy+row.y+row.height-1,t.border,3) end
      end
      left,right,color,keycap=nil,nil,nil,nil
    end
    l:visible_units(row,line,e.scroll_x-o.padding,e.scroll_x+view.w,function(_,x,width,r)
      local bg=r and (r.highlight and t.highlight or r.tag and t.hover or r.code and t.code_bg or r.kbd and t.panel)
      if width>0 then
        if bg~=color or (right and math.abs(right-x)>.1) then fill() end
        if bg then left,right,color,keycap=left or x+(r.outer_left or 0),x+width-(r.outer_right or 0),bg,r.kbd end
      end
    end)
    fill()
  end)
  local selected={};local a,b=e.anchor,e.caret
  if a and a~=b then
    if a>b then a,b=b,a end
    l:each_visible(e.scroll_y-o.padding,view.h,function(row,line)
      local left,right=math.max(a,line.start+row.a),math.min(b,line.start+row.b)
      local newline=row.b==#line.text and line.finish<#e.document.text and a<=line.finish and b>line.finish
      if left<right or newline then
        local x1=l:x_at(row,line,math.min(line.start+row.b,left)-line.start)
        local x2=l:x_at(row,line,math.max(line.start+row.a,right)-line.start)+(newline and l.space or 0)
        if row.code_group then x1,x2=math.max(14,x1),math.min(row.code_right,x2) end
        if x2>x1 then selected[#selected+1]={x1=x1,x2=x2,y1=row.y,y2=row.y+row.height} end
      end
    end)
  end
  local minx,miny,maxx,maxy=math.huge,math.huge,-math.huge,-math.huge
  for _,r in ipairs(selected) do
    local flags=im.DrawFlags_RoundCornersTopLeft|im.DrawFlags_RoundCornersTopRight|im.DrawFlags_RoundCornersBottomLeft|im.DrawFlags_RoundCornersBottomRight
    for _,n in ipairs(selected) do
      if math.abs(n.y2-r.y1)<.1 then
        if r.x1>=n.x1 and r.x1<=n.x2 then flags=flags & ~im.DrawFlags_RoundCornersTopLeft end
        if r.x2>=n.x1 and r.x2<=n.x2 then flags=flags & ~im.DrawFlags_RoundCornersTopRight end
      elseif math.abs(n.y1-r.y2)<.1 then
        if r.x1>=n.x1 and r.x1<=n.x2 then flags=flags & ~im.DrawFlags_RoundCornersBottomLeft end
        if r.x2>=n.x1 and r.x2<=n.x2 then flags=flags & ~im.DrawFlags_RoundCornersBottomRight end
      end
    end
    im.DrawList_AddRectFilled(dl,ox+r.x1,oy+r.y1,ox+r.x2,oy+r.y2,t.selection,o.selection_rounding,flags==0 and im.DrawFlags_RoundCornersNone or flags)
    minx,miny,maxx,maxy=math.min(minx,ox+r.x1),math.min(miny,oy+r.y1),math.max(maxx,ox+r.x2),math.max(maxy,oy+r.y2)
  end
  e.selection_coords=minx<math.huge and {x=minx,y=miny,w=maxx-minx,h=maxy-miny} or nil
  local drawn,calls=0,0
  l:each_visible(e.scroll_y-o.padding,view.h,function(row,line)
    local entry=row.entry;local kind=entry.meta.kind
    if entry.hide_text or ((kind=='rule' or kind=='image') and l.active_line~=entry.number) then return end
    if row.code_group then im.DrawList_PushClipRect(dl,ox+14,oy+row.y,ox+row.code_right,oy+row.y+row.height,true) end
    local run,runx,role={},nil,nil
    local function flush()
      if #run==0 then return end
      local value=table.concat(run);local color=t.text
      if role then
        color=role.muted and t.muted or role.link and t.link or role.heading and t.heading or role.tag and t.accent or color
        if role.token then
          color=role.token=='keyword' and t.accent or role.token=='string' and t.success or role.token=='number' and t.warning or role.token=='comment' and t.muted or t.text
        elseif role.code then color=t.code end
      end
      local font=md.current[role and role.font or 'body'] or md.current.body
      local y=oy+row.y+(row.height-font.size)/2
      if role and role.code and not row.code_group then y=y+font.size*(o.inline_code_offset or .1) end
      if role and role.superscript then y=y-row.height*.23 end
      text(im,dl,md,role and role.font or 'body',ox+runx,y,color,value);calls=calls+1;run={}
    end
    l:visible_units(row,line,e.scroll_x-o.padding,e.scroll_x+view.w,function(display,x,width,r)
      if drawn>=o.max_draw_units then return false end
      if r~=role or #run>=64 or display=='' or display=='\t' or (r and r.checkbox) then flush() end
      if display~='' and display~='\t' and not (r and r.checkbox) then
        if #run==0 then runx,role=x+(r and r.pad_left or 0),r end
        run[#run+1]=display
        if r and (r.strike or r.underline or (r.link and not r.superscript)) then
          local y=oy+row.y+row.height*(r.strike and .48 or .86)
          im.DrawList_AddLine(dl,ox+x,y,ox+x+width,y,r.link and t.link or t.muted)
        end
      end
      drawn=drawn+1
    end)
    flush()
    if row.code_group then im.DrawList_PopClipRect(dl) end
    return drawn<o.max_draw_units
  end)
  local cx,cy,cn,ch=l:position(e.caret,e.affinity)
  local caret_row=cn and l:row(cn)
  if focused and not o.read_only and cx and (not caret_row.code_group or (cx>=14 and cx<=caret_row.code_right)) and (e.clock()-e.blink_at)%1<.5 then
    im.DrawList_AddLine(dl,ox+cx,oy+cy,ox+cx,oy+cy+(ch or view.line_height),t.accent,1.5)
  end
  md.zones=zones(e,view,mx,my)
  for _,z in ipairs(md.zones) do
    if z.kind=='code_copy' then
      local hover=inside(mx,my,z)
      local copied=md.copied_block==z.block.key and e.clock()-(md.copied_at or 0)<1
      im.DrawList_AddRectFilled(dl,z.x1,z.y1,z.x2,z.y2,hover and t.border or t.panel,3)
      text(im,dl,md,'small',z.x1+7,z.y1+3,copied and t.success or hover and t.text or t.muted,'copy')
      local language=z.block.language or ''
      local w=l.rich_measure(language,{font='small'})
      if w+10+z.x2-z.x1<=l:code_controls_width(z.block) then
        text(im,dl,md,'small',z.x1-w-10,z.y1+3,t.muted,language)
      end
    elseif z.kind=='code_scroll' then
      local state=l:code_state(z.block);local x=z.x1+(z.track-z.thumb)*state.x/state.max
      im.DrawList_AddRectFilled(dl,z.x1,z.y1+3,z.x2,z.y2-3,t.panel,2)
      im.DrawList_AddRectFilled(dl,x,z.y1+3,x+z.thumb,z.y2-3,t.muted,2)
    elseif z.kind=='diagram' and not o.read_only and inside(mx,my,z) then
      im.SetTooltip(ctx,'Кликните для редактирования Mermaid')
    end
  end
  if not o.read_only then for _,z in ipairs(md.zones) do
    if z.kind=='add_row' or z.kind=='add_column' then
      local x,y=(z.x1+z.x2)/2,(z.y1+z.y2)/2
      if z.guide then im.DrawList_AddLine(dl,ox,z.guide,ox+l.width,z.guide,t.accent) end
      im.DrawList_AddCircleFilled(dl,x,y,8,t.accent)
      im.DrawList_AddLine(dl,x-3,y,x+3,y,t.background,1.5)
      im.DrawList_AddLine(dl,x,y-3,x,y+3,t.background,1.5)
    end
  end end
  im.DrawList_PopClipRect(dl)
  -- Real ImGui controls, with their own hover/press behavior and rounded frames.
  im.PushStyleVar(ctx,im.StyleVar_FrameRounding,4)
  im.PushStyleVar(ctx,im.StyleVar_FramePadding,2,2)
  im.PushStyleColor(ctx,im.Col_FrameBg,t.panel)
  im.PushStyleColor(ctx,im.Col_FrameBgHovered,t.border)
  im.PushStyleColor(ctx,im.Col_FrameBgActive,t.border)
  im.PushStyleColor(ctx,im.Col_CheckMark,t.success)
  im.BeginDisabled(ctx,o.read_only)
  for _,z in ipairs(md.zones) do
    if z.kind=='task' or z.kind=='task_cell' then
      local m=z.line and l.parser.lines[z.line];local line=z.line and e.document.lines[z.line]
      local check_at=z.check_at or line.start+m.check_pos
      local checked=z.checked
      if z.kind=='task' then checked=m.checked end
      im.SetCursorScreenPos(ctx,z.x1,z.y1)
      local changed,value=im.Checkbox(ctx,'##md_task_'..check_at,checked)
      if changed then
        e:replace_range(check_at,check_at+1,value and 'x' or ' ','toggle_task',e:get_state())
        e.follow_caret,e.focused,e.request_focus=false,true,true
      end
    end
  end
  im.EndDisabled(ctx)
  im.PopStyleColor(ctx,4);im.PopStyleVar(ctx,2)
  local fr,lr=l:visible_range(e.scroll_y-o.padding,view.h)
  e.metrics={first_row=fr,last_row=lr,rows=l:row_count(),pending_lines=l.pending,drawn_units=drawn,draw_calls=calls,
    width=l.width,line_height=view.line_height,logical_lines=#e.document.lines}
end
return View
