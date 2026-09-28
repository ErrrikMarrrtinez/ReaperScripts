-- @noindex
-- Native editable flowcharts for the common Mermaid graph/flowchart subset.
-- Unsupported grammar stays a readable fenced code block.
local Diagram={}
local function endpoint(s)
  s=s:match('^%s*(.-)%s*$')
  local id,label=s:match('^([%w_]+)%s*%[(.-)%]$')
  local shape='box'
  if not id then id,label=s:match('^([%w_]+)%s*%{(.-)%}$');shape='decision' end
  if not id then id,label=s:match('^([%w_]+)%s*%((.-)%)$');shape='round' end
  if not id then id=s:match('^([%w_]+)$');label=id end
  if label then label=label:gsub('^"',''):gsub('"$',''):gsub('<br%s*/?>','\n') end
  return id,label,shape
end
function Diagram.parse(lines,first,last)
  local nodes,order,edges={}, {}, {}
  local direction
  local function node(s)
    local id,label,shape=endpoint(s);if not id then return nil end
    if not nodes[id] then nodes[id]={id=id,label=label,shape=shape,level=0};order[#order+1]=nodes[id]
    elseif label~=id then nodes[id].label,nodes[id].shape=label,shape end
    return nodes[id]
  end
  for i=first,last do
    local s=lines[i].text:match('^%s*(.-)%s*$')
    if s~='' and not s:match('^%%%%') then
      local dir=s:match('^flowchart%s+(%u+)%s*;?$') or s:match('^graph%s+(%u+)%s*;?$')
      if dir then direction=dir
      else
        s=s:gsub(';%s*$','')
        local left,label,right=s:match('^(.-)%-%->%s*|([^|]*)|%s*(.-)$')
        if not left then left,right=s:match('^(.-)%-%->%s*(.-)$') end
        if left then
          local a,b=node(left),node(right)
          if not a or not b then return nil end
          edges[#edges+1]={from=a,to=b,label=label}
        elseif not node(s) then return nil end
      end
    end
  end
  if not direction or #order==0 or #order>40 then return nil end
  if direction~='TD' and direction~='TB' and direction~='LR' then return nil end
  for pass=1,#order do
    local changed=false
    for _,edge in ipairs(edges) do
      if edge.to.level<=edge.from.level then edge.to.level=edge.from.level+1;changed=true end
    end
    if not changed then break end
    if pass==#order then return nil end -- cycle: preserve code instead of a misleading layout
  end
  return {nodes=order,edges=edges,direction=direction}
end
function Diagram.geometry(graph,width,measure,font_size)
  font_size=font_size or 18
  local padding,gap=math.ceil(font_size*.65),math.ceil(font_size*1.6)
  local line_height=font_size*1.25
  local function text_width(s) return measure(s,{font='body'}) end
  local function fit(node,available)
    node.w=math.max(24,math.min(node.natural,available))
    local room=math.max(1,node.w-padding*2);local lines=0
    for part in (node.label..'\n'):gmatch('(.-)\n') do
      local x,count=0,1
      for word in part:gmatch('%S+%s*') do
        local w=text_width(word)
        if x>0 and x+w>room then count=count+1;x=0 end
        count=count+math.max(0,math.ceil(w/room)-1);x=(w>room and w%room or x+w)
      end
      lines=lines+count
    end
    node.h=lines*line_height+padding*2
  end
  local levels,maxlevel={},0
  for _,node in ipairs(graph.nodes) do
    local list=levels[node.level] or {};levels[node.level]=list;list[#list+1]=node
    maxlevel=math.max(maxlevel,node.level)
    local w=0
    for part in (node.label..'\n'):gmatch('(.-)\n') do w=math.max(w,text_width(part)) end
    node.natural=math.max(font_size*4,math.min(260,w+padding*2))
  end
  local columns,total={},padding*2+maxlevel*gap
  for level=0,maxlevel do
    local w=0;for _,node in ipairs(levels[level] or {}) do w=math.max(w,node.natural) end
    columns[level]=w;total=total+w
  end
  local horizontal=graph.direction=='LR' and total<=width
  local height=0
  if horizontal then
    local x=math.max(padding,(width-total)/2+padding)
    local stacks={}
    for level=0,maxlevel do
      local y=0
      for _,node in ipairs(levels[level] or {}) do
        fit(node,columns[level]);node.x=x+(columns[level]-node.w)/2;node.y=y
        y=y+node.h+gap
      end
      stacks[level]=math.max(0,y-gap);height=math.max(height,stacks[level]);x=x+columns[level]+gap
    end
    for _,node in ipairs(graph.nodes) do node.y=node.y+padding+(height-stacks[node.level])/2 end
    height=height+padding*2
  else
    local y=padding
    for level=0,maxlevel do
      local list=levels[level] or {}
      local count=math.max(1,math.min(#list,math.floor((width-padding*2+gap)/(font_size*5+gap))))
      local slot=math.max(24,(width-padding*2-(count-1)*gap)/count)
      for first=1,#list,count do
        local last=math.min(#list,first+count-1);local row_width,row_height=0,0
        for n=first,last do fit(list[n],slot);row_width=row_width+list[n].w;row_height=math.max(row_height,list[n].h) end
        row_width=row_width+(last-first)*gap
        local x=(width-row_width)/2
        for n=first,last do local node=list[n];node.x,node.y=x,y+(row_height-node.h)/2;x=x+node.w+gap end
        y=y+row_height+gap
      end
    end
    height=y-gap+padding
  end
  local left,right=width,0
  for _,node in ipairs(graph.nodes) do left=math.min(left,node.x-padding);right=math.max(right,node.x+node.w+padding) end
  graph.left,graph.right=math.max(0,left),math.min(width,right)
  graph.horizontal,graph.padding=horizontal,padding
  return height
end
return Diagram
