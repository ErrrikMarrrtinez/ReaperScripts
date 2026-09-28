-- @noindex
local Table = {}
local max_columns = 128

-- Source ranges include neither separators nor surrounding whitespace. Pipes
-- in code spans and escaped pipes belong to a cell, not to the grid structure.
function Table.cells(text)
  local cells, cuts, p, code = {}, {0}, 1, nil
  while p <= #text do
    local c = text:sub(p,p)
    if c == '\\' then p = p + 2
    elseif c == '`' then
      local run = text:match('^`+', p)
      if code == #run then code = nil elseif not code then code = #run end
      p = p + #run
    elseif c == '|' and not code then cuts[#cuts+1] = p; p = p + 1
    else p = p + 1 end
    if #cuts > max_columns+2 then return nil end
  end
  if #cuts < 2 then return nil end
  cuts[#cuts+1] = #text + 1
  for i=1,#cuts-1 do
    local a,b = cuts[i],cuts[i+1]-1
    if not ((i==1 or i==#cuts-1) and text:sub(a+1,b):match('^%s*$')) then
      local raw = text:sub(a+1,b)
      local left = #(raw:match('^%s*') or '')
      local right = #(raw:match('%s*$') or '')
      -- One surrounding space belongs to the pipe syntax. Additional spaces
      -- are editable content: trimming them all moves an end caret to the next cell.
      local first = a+math.min(1,left)
      local last = math.max(first,b-math.min(1,right))
      cells[#cells+1] = {a=first,b=last,raw_a=a,raw_b=b,text=text:sub(first+1,last)}
    end
  end
  return #cells>0 and #cells<=max_columns and cells or nil
end

function Table.separator(text)
  local cells = Table.cells(text)
  if not cells then return nil end
  local align = {}
  for i,c in ipairs(cells) do
    if not c.text:match('^:?-+:?$') or not c.text:find('%-%-') then return nil end
    align[i] = c.text:sub(1,1)==':' and (c.text:sub(-1)==':' and 'center' or 'left') or
      (c.text:sub(-1)==':' and 'right' or 'left')
  end
  return align
end

local function rows(e, group)
  local result = {}
  for _,i in ipairs(group.rows) do
    local cells = Table.cells(e.document.lines[i].text) or {}
    local row = {}
    for col=1,group.columns do row[col] = cells[col] and cells[col].text or '' end
    result[#result+1] = row
  end
  return result
end

local function commit(e, group, data, align, row, col, action)
  local parts, caret, offset = {}, 0, e.document.lines[group.first].start
  for i,cells in ipairs(data) do
    local text = '| ' .. table.concat(cells,' | ') .. ' |'
    if i==row then
      caret = offset + 2
      for j=1,(col or 1)-1 do caret = caret + #cells[j]+3 end
    end
    parts[#parts+1] = text; offset = offset + #text+1
    if i==1 then
      local separator = {}
      for j=1,#cells do separator[j] = align[j]=='center' and ':---:' or align[j]=='right' and '---:' or '---' end
      text = '| ' .. table.concat(separator,' | ') .. ' |'
      parts[#parts+1] = text; offset = offset+#text+1
    end
  end
  local changed = e:replace_range(e.document.lines[group.first].start,e.document.lines[group.last].finish,
    table.concat(parts,'\n'),action,{caret=caret})
  if changed then e:focus() end
  return changed
end

function Table.edit(e, group, operation, row, col, value)
  if e.options.read_only then return false end
  local data, align = rows(e,group), {table.unpack(group.align)}
  row, col = math.max(1,math.min(#data,row or 1)), math.max(1,math.min(group.columns,col or 1))
  if operation=='add_row' then
    row = math.max(2,math.min(#data+1,value or row+1))
    local blank = {}; for i=1,group.columns do blank[i]='' end
    table.insert(data,row,blank)
  elseif operation=='delete_row' then
    if row==1 then return false end
    table.remove(data,row); row=math.min(row,#data)
  elseif operation=='add_column' then
    if group.columns>=max_columns then return false end
    col=math.max(1,math.min(group.columns+1,value or col+1))
    for _,cells in ipairs(data) do table.insert(cells,col,'') end
    table.insert(align,col,'left')
  elseif operation=='delete_column' then
    if group.columns<=1 then return false end
    for _,cells in ipairs(data) do table.remove(cells,col) end
    table.remove(align,col); col=math.min(col,#align)
  elseif operation=='align' then align[col]=value
  elseif operation=='move_column' then
    local to=math.max(1,math.min(group.columns,col+value))
    for _,cells in ipairs(data) do table.insert(cells,to,table.remove(cells,col)) end
    table.insert(align,to,table.remove(align,col)); col=to
  elseif operation=='move_row' then
    if row==1 then return false end
    local to=math.max(2,math.min(#data,row+value))
    table.insert(data,to,table.remove(data,row)); row=to
  elseif operation=='sort' then
    local header=table.remove(data,1)
    table.sort(data,function(a,b)
      local x,y=tonumber(a[col]),tonumber(b[col])
      if not x or not y then x,y=a[col]:lower(),b[col]:lower() end
      return value=='descending' and x>y or value~='descending' and x<y
    end)
    table.insert(data,1,header); row=1
  else return false end
  return commit(e,group,data,align,row,col,'table_'..operation)
end

function Table.insert(e, columns, body_rows)
  columns,body_rows=math.max(1,math.min(max_columns,math.floor(columns or 3))),math.max(1,math.floor(body_rows or 2))
  local rows,header,separator={},{},{}
  for c=1,columns do header[c]='Column '..c; separator[c]='---' end
  rows[1]='| '..table.concat(header,' | ')..' |'
  rows[2]='| '..table.concat(separator,' | ')..' |'
  for i=1,body_rows do rows[#rows+1]='| '..string.rep(' | ',columns-1)..' |' end
  local _,line=e.document:line_at(e.caret)
  local prefix=line.text~='' and '\n\n' or ''
  return e:insert_text(prefix..table.concat(rows,'\n')..'\n','insert_table')
end

function Table.paste(e,group,row,col,text)
  if e.options.read_only then return false end
  local data,align=rows(e,group),{table.unpack(group.align)}
  text=text:gsub('\r\n','\n'):gsub('\r','\n'):gsub('\n$','')
  local r,columns=row,group.columns
  for source in (text..'\n'):gmatch('(.-)\n') do
    data[r]=data[r] or {}
    local c=col
    for value in (source..'\t'):gmatch('(.-)\t') do
      data[r][c]=value:gsub('\\?%|',function(pipe) return pipe=='|' and '\\|' or pipe end)
      columns=math.max(columns,c);c=c+1
      if columns>max_columns then return false end
    end
    r=r+1
  end
  for _,cells in ipairs(data) do for c=1,columns do if cells[c]==nil then cells[c]='' end end end
  for c=1,columns do align[c]=align[c] or 'left' end
  return commit(e,group,data,align,row,col,'table_paste')
end
return Table
