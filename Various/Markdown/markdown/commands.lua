-- @noindex
local load=...
local Table=load('markdown.table')
local Commands={}
local function selection(e)
  return math.min(e.anchor or e.caret,e.caret),math.max(e.anchor or e.caret,e.caret)
end
function Commands.cell(e)
  if not e.options.markdown or not e.layout.parser then return nil end
  e.layout.parser:sync()
  local i,line=e.document:line_at(e.caret);local m=e.layout.parser.lines[i]
  if not m or not m.table or m.kind~='table' then return nil end
  if e.markdown_raw_tables and e.markdown_raw_tables[m.table.key] then return nil end
  local offset=e.caret-line.start
  for col,cell in ipairs(m.cells) do
    if offset<=(cell.raw_b or cell.b) or col==#m.cells then return m.table,m.table_row,col,cell,m end
  end
end
function Commands.prepare_text(e,text)
  if Commands.cell(e) then
    -- A literal pipe/newline must not accidentally destroy the table structure.
    text=text:gsub('\r\n','\n'):gsub('\r','\n'):gsub('\n','<br>')
    text=text:gsub('\\?%|',function(pipe) return pipe=='|' and '\\|' or pipe end)
  end
  return text
end
-- Typographic replacement is its own history entry: Undo restores the two
-- literal hyphens. Pasted/loaded text never passes through this command.
function Commands.smart_dashes(e,first,inserted)
  local previous=e.markdown_last_dash;e.markdown_last_dash=nil
  if e.options.markdown_smart_dashes==false or not inserted:find('-',1,true) then return end
  local doc=e.document
  -- A third hyphen at the start of a line must still create Markdown's rule.
  if previous and previous.revision==doc.revision-1 and previous.epoch==e.history.epoch and
    first==previous.at+#'—' and inserted=='-' and doc.text:sub(previous.at+1,first)=='—' then
    e:replace_range(previous.at,first+1,'---','smart_dash');return
  end
  local i,line=doc:line_at(first)
  local parser=e.layout.parser;parser:sync()
  local m=parser.lines[i]
  if m.code_group or m.kind=='math' or m.kind=='math_fence' or m.kind=='comment' or
    m.kind=='reference' or m.kind=='rule' or m.kind=='underline' or m.kind=='table_separator' then return end
  local text=line.text
  local from=math.max(1,first-line.start);local stop=first-line.start+#inserted
  local projection=load('markdown.inline').parse(text,{active=true})
  local function literal(at)
    local prefix=text:sub(1,at-1)
    if prefix:match('<[^>]*$') or prefix:match('%]%([^)]*$') or prefix:match('https?://%S*$') then return true end
    local p,code,math_delimiter=1,nil,nil
    while p<at do
      local c=text:sub(p,p)
      if c=='\\' then p=p+2
      elseif c=='`' then
        local run=text:match('^`+',p)
        if code==#run then code=nil elseif not code then code=#run end
        p=p+#run
      elseif c=='$' and not code then
        local run=text:match('^%$+',p)
        if math_delimiter==#run then math_delimiter=nil elseif not math_delimiter then math_delimiter=#run end
        p=p+#run
      else p=p+1 end
    end
    if code or math_delimiter then return true end
    for _,span in ipairs(projection.spans) do
      if at-1>=span.a and at-1<span.b then
        local r=span.role
        return r.code or r.kbd or r.math or r.link or span.hidden
      end
    end
  end
  local edits={};local p=from
  while p<=stop do
    local a,b=text:find('%-%-+',p)
    if not a or a>stop then break end
    if b-a==1 and b<=stop and text:sub(a-1,a-1)~='-' and text:sub(a-1,a-1)~='\\' and not literal(a) then
      edits[#edits+1]={a=a,b=b}
    end
    p=b+1
  end
  if #edits==0 then return end
  local start,finish=edits[1].a,edits[#edits].b
  local parts,cursor={},start
  for _,edit in ipairs(edits) do parts[#parts+1]=text:sub(cursor,edit.a-1)..'—';cursor=edit.b+1 end
  local replacement=table.concat(parts)
  local state=e:get_state();state.caret=state.caret+#edits;state.anchor=nil
  e:replace_range(line.start+start-1,line.start+finish,replacement,'smart_dash',state)
  if #edits==1 and text:sub(1,start-1):match('^[%s>]*$') and text:sub(finish+1):match('^%s*$') then
    e.markdown_last_dash={at=line.start+start-1,revision=doc.revision,epoch=e.history.epoch}
  end
end
local function wrap(e,left,right)
  right=right or left
  local a,b=selection(e);local text=e.document.text
  local selected=text:sub(a+1,b)
  local first,last,insert=a,b,left..selected..right
  local anchor,caret=a+#left,b+#left
  if a>=#left and text:sub(a-#left+1,a)==left and text:sub(b+1,b+#right)==right then
    first,last,insert=a-#left,b+#right,selected;anchor,caret=first,first+#selected
  elseif #selected>=#left+#right and selected:sub(1,#left)==left and selected:sub(-#right)==right then
    insert=selected:sub(#left+1,#selected-#right);anchor,caret=a,a+#insert
  end
  if a==b then anchor=nil;caret=first+#left
  elseif e.anchor and e.anchor>e.caret then anchor,caret=caret,anchor end
  return e:replace_range(first,last,insert,'format',{anchor=anchor,caret=caret})
end
local function lines(e,transform)
  local a,b=selection(e);local from,left=e.document:line_at(a);local to=e.document:line_at(b)
  if to>from and b==e.document.lines[to].start then to=to-1 end
  local parts,changes={},{}
  for i=from,to do
    local line=e.document.lines[i]
    local text,removed,added=transform(line.text,i-from+1)
    parts[#parts+1]=text;changes[#changes+1]={at=line.start,removed=removed,added=added}
  end
  local function map(p)
    local delta=0
    for _,c in ipairs(changes) do if p>=c.at then delta=delta+c.added-math.min(c.removed,p-c.at) end end
    return p+delta
  end
  return e:replace_range(left.start,e.document.lines[to].finish,table.concat(parts,'\n'),'format_lines',
    {caret=map(e.caret),anchor=e.anchor and map(e.anchor)})
end
function Commands.run(e,command,value)
  if e.options.read_only then return false end
  if command=='bold' then return wrap(e,'**')
  elseif command=='italic' then return wrap(e,'*')
  elseif command=='strike' then return wrap(e,'~~')
  elseif command=='highlight' then return wrap(e,'==')
  elseif command=='code' then return wrap(e,'`')
  elseif command=='code_block' then return wrap(e,'```'..(value or '')..'\n','\n```')
  elseif command=='math' then return wrap(e,'$')
  elseif command=='link' or command=='image' then
    local a,b=selection(e);local label=e.document.text:sub(a+1,b)
    if label=='' then label=command=='image' and 'image' or 'link' end
    local prefix=(command=='image' and '!' or '')..'['..label..']('
    local target=value or 'https://'
    return e:replace_range(a,b,prefix..target..')','format_link',{anchor=a+#prefix,caret=a+#prefix+#target})
  elseif command=='heading' then
    local prefix=string.rep('#',math.max(1,math.min(6,value or 1)))..' '
    return lines(e,function(text)
      local old=text:match('^#+%s+') or ''
      local new=old==prefix and '' or prefix
      return new..text:sub(#old+1),#old,#new
    end)
  elseif command=='task' and Commands.cell(e) then return e:insert_text('[ ] ','insert_checkbox')
  elseif command=='bullet' or command=='ordered' or command=='task' or command=='quote' then
    return lines(e,function(text,n)
      local old=text:match('^%s*[-+*]%s+%[.%]%s+') or text:match('^%s*[-+*]%s+') or text:match('^%s*%d+[.)]%s+') or text:match('^%s*>%s*') or ''
      local prefix=command=='bullet' and '- ' or command=='ordered' and n..'. ' or command=='task' and '- [ ] ' or '> '
      local new=old==prefix and '' or prefix
      return new..text:sub(#old+1),#old,#new
    end)
  elseif command=='rule' then return e:insert_text('\n\n---\n\n','format_rule')
  elseif command=='callout' then return e:insert_text('> [!note] Note\n> Note text\n','format_callout')
  elseif command=='table' then return Table.insert(e,value or 3,2)
  elseif command=='toggle_task' then
    local _,line=e.document:line_at(e.caret)
    local prefix,check=line.text:match('^(%s*[-+*]%s+%[)(.)%]')
    if not prefix then return Commands.run(e,'task') end
    return e:replace_range(line.start+#prefix,line.start+#prefix+1,check==' ' and 'x' or ' ','toggle_task',e:get_state())
  end
  return false
end
function Commands.next_cell(e,direction,vertical)
  local group,row,col=Commands.cell(e);if not group then return false end
  if vertical then row=row+direction
  else
    col=col+direction
    if col>group.columns then col=1;row=row+1 elseif col<1 then col=group.columns;row=row-1 end
  end
  if row>#group.rows then
    if e.options.read_only then return true end
    Table.edit(e,group,'add_row',#group.rows,col,#group.rows+1)
    e.layout.parser:sync();group=e.layout.parser.lines[group.first].table
  end
  if row<1 then
    e:set_caret(math.max(0,e.document.lines[group.first].start-1));return true
  end
  local line=e.document.lines[group.rows[row]]
  local cell=Table.cells(line.text)[col]
  e:set_caret(line.start+cell.a);return true
end
local function enter(e,shift)
  if Commands.cell(e) then
    if shift then e:insert_text('<br>','table_break') else Commands.next_cell(e,1,true) end
    return true
  end
  if shift then return false end
  local _,line=e.document:line_at(e.caret)
  local prefix=line.text:match('^%s*[-+*]%s+%[.%]%s+') or line.text:match('^%s*[-+*]%s+') or
    line.text:match('^%s*%d+[.)]%s+') or line.text:match('^%s*>%s*')
  if not prefix then return false end
  if line.text:sub(#prefix+1):match('^%s*$') then
    e:replace_range(line.start,line.finish,'','end_list');return true
  end
  prefix=prefix:gsub('%[.%]','[ ]')
  prefix=prefix:gsub('(%d+)([.)])',function(n,c) return tonumber(n)+1 .. c end,1)
  e:insert_text('\n'..prefix,'continue_list');return true
end
function Commands.keyboard(e,im,ctx)
  local ctrl,shift,alt=im.IsKeyDown(ctx,im.Mod_Ctrl),im.IsKeyDown(ctx,im.Mod_Shift),im.IsKeyDown(ctx,im.Mod_Alt)
  local function key(name) return im.IsKeyPressed(ctx,im['Key_'..name],false) end
  local group,row,col,cell=Commands.cell(e)
  if group and ctrl and not alt and key('V') then
    local value=im.GetClipboardText(ctx)
    if value and value:find('\t',1,true) then Table.paste(e,group,row,col,value);return true end
  end
  if group and ctrl and shift and key('Backspace') then Table.edit(e,group,'delete_row',row,col);return true end
  if group and ctrl and shift and key('Delete') then Table.edit(e,group,'delete_column',row,col);return true end
  if group and ctrl and key('Enter') then
    local last=e.document.lines[group.last]
    e:replace_range(last.finish,last.finish,'\n\n','exit_table');return true
  end
  if group and not ctrl and not alt and (not e.anchor or e.anchor==e.caret) then
    local _,line=e.document:line_at(e.caret)
    if key('Backspace') and e.caret<=line.start+cell.a then
      local cells=Table.cells(line.text);local empty=true
      for _,c in ipairs(cells) do if not c.text:match('^%s*$') then empty=false;break end end
      if empty and col==1 and row>1 then Table.edit(e,group,'delete_row',row,col)
      elseif col>1 or row>1 then Commands.next_cell(e,-1) end
      return true
    elseif key('Delete') and e.caret>=line.start+cell.b then
      -- Structural separators are managed by the table commands.
      return true
    end
  end
  if ctrl then
    local command
    if alt then
      for i=1,6 do if key(tostring(i)) then Commands.run(e,'heading',i);return true end end
    elseif shift then
      local bindings={{'X','strike'},{'H','highlight'},{'C','code_block'},{'Q','quote'},{'7','ordered'},{'8','bullet'},{'9','task'}}
      for _,pair in ipairs(bindings) do if key(pair[1]) then command=pair[2];break end end
    else
      local bindings={{'B','bold'},{'I','italic'},{'K','link'},{'E','code'},{'Enter','toggle_task'}}
      for _,pair in ipairs(bindings) do if key(pair[1]) then command=pair[2];break end end
    end
    if command then Commands.run(e,command);return true end
  end
  if not ctrl and not alt then
    if key('Tab') and Commands.cell(e) then Commands.next_cell(e,shift and -1 or 1);return true end
    if key('Enter') or key('KeypadEnter') then return enter(e,shift) end
    if key('Backspace') and not e.anchor then
      local _,line=e.document:line_at(e.caret)
      local prefix=line.text:match('^%s*[-+*]%s+%[.%]%s+') or line.text:match('^%s*[-+*]%s+') or line.text:match('^%s*%d+[.)]%s+')
      if prefix and e.caret==line.start+#prefix then e:replace_range(line.start,e.caret,'','remove_list');return true end
    end
  end
  return false
end
return Commands
