-- @noindex
local load = ...
local Table = load('markdown.table')
local Parser = {}
Parser.__index = Parser
function Parser.new(document) return setmetatable({document=document,revision=-1,lines={},references={},headings={}},Parser) end

function Parser:sync()
  local doc=self.document
  if self.revision==doc.revision then return false end
  local meta,refs,headings,tables={}, {}, {}, {}
  local fence,math_block,comment,front,callout
  local i=1
  while i<=#doc.lines do
    local line=doc.lines[i]; local s=line.text
    local m={kind='paragraph',prefix=0,line=i}
    meta[i]=m
    if fence then
      m.kind,m.language,m.block='code',fence.language,fence
      local marks=s:match('^%s*([`~]+)%s*$')
      if marks and marks:sub(1,1)==fence.char and #marks>=fence.length then
        m.kind='fence'; fence.last=i; fence.closed=true; fence=nil
      end
    elseif math_block then
      m.kind,m.block='math',math_block
      if s:match('^%s*%$%$%s*$') then m.kind='math_fence'; math_block.last=i; math_block=nil end
    elseif front then
      m.kind='frontmatter'
      if s:match('^%-%-%-%s*$') or s:match('^%.%.%.%s*$') then front=nil end
    elseif comment then
      m.kind='comment'
      if s:find('%%',1,true) then comment=nil end
    elseif i==1 and s:match('^%-%-%-%s*$') then m.kind='frontmatter'; front=true
    elseif s:match('^%s*%%%%%s*$') then m.kind='comment'; comment=true
    else
      local marks,lang=s:match('^%s*([`~]+)%s*([^%s]*)')
      if marks and #marks>=3 and (marks:match('^`+$') or marks:match('^~+$')) then
        fence={first=i,char=marks:sub(1,1),length=#marks,language=lang,last=#doc.lines,key=line}
        m.kind,m.language,m.block='fence',lang,fence
      elseif s:match('^%s*%$%$%s*$') then
        math_block={first=i,last=#doc.lines}; m.kind,m.block='math_fence',math_block
      elseif s:match('^%s*$') then m.kind='blank'; callout=nil
      else
        local align=doc.lines[i+1] and Table.separator(doc.lines[i+1].text)
        local cells=align and Table.cells(s)
        if cells and #cells==#align then
          local previous=self.tables and self.tables[line]
          local change=doc.last_change
          if not previous and change and change.new_line==line and change.previous_revision==self.revision then
            previous=self.tables and self.tables[change.old_line]
          end
          local group={first=i,last=i+1,columns=#cells,align=align,rows={i},key=previous and previous.key or line}
          tables[line]=group
          m.kind,m.table,m.cells,m.table_row='table',group,cells,1
          meta[i+1]={kind='table_separator',table=group,line=i+1}
          local j=i+2
          while j<=#doc.lines do
            local row=Table.cells(doc.lines[j].text)
            if not row or doc.lines[j].text:match('^%s*$') then break end
            for c=#row+1,group.columns do row[c]={a=#doc.lines[j].text,b=#doc.lines[j].text,text=''} end
            if #row>group.columns then break end
            group.rows[#group.rows+1]=j; group.last=j
            meta[j]={kind='table',table=group,cells=row,table_row=#group.rows,line=j}
            j=j+1
          end
          i=j-1
        else
          local hashes,space=s:match('^ ? ? ?(#+)(%s+)')
          local setext=doc.lines[i+1] and doc.lines[i+1].text:match('^ ? ? ?([=-]+)%s*$')
          if hashes and #hashes<=6 then
            m.kind,m.level,m.prefix='heading',#hashes,#(s:match('^ ? ? ?#+%s+'))
          elseif setext and (setext:match('^=+$') or setext:match('^%-+$')) then
            m.kind,m.level='heading',setext:sub(1,1)=='=' and 1 or 2
            meta[i+1]={kind='underline',line=i+1}; i=i+1
          else
            local compact=s:gsub('%s','')
            if #compact>=3 and (compact:match('^%-+$') or compact:match('^%*+$') or compact:match('^_+$')) then
              m.kind='rule'
            else
              local quote=s:match('^%s*>[%s>]*')
              if quote then
                m.kind,m.prefix,m.depth='quote',#quote,select(2,quote:gsub('>',''))
                local typ,fold,title=s:sub(#quote+1):match('^%[!([%w_-]+)%]([+-]?)%s*(.*)')
                if typ then
                  callout={kind=typ:lower(),title=title~='' and title or typ,title_start=#s-#title,first=m.line,last=m.line,fold=fold,key=line}
                  m.kind,m.callout='callout',callout
                else m.callout=callout;if callout then callout.last=m.line end end
              else
                callout=nil
                local indent,bullet,space=s:match('^(%s*)([-+*])(%s+)')
                if not bullet then indent,bullet,space=s:match('^(%s*)(%d+[.)])(%s+)') end
                if bullet then
                  m.kind,m.prefix,m.indent,m.bullet='list',#indent+#bullet+#space,#indent,bullet
                  local task=s:sub(m.prefix+1):match('^%[(.)%]%s+')
                  if task then
                    m.kind,m.checked,m.check_pos='task',task~=' ',m.prefix+1
                    m.prefix=m.prefix+#(s:sub(m.prefix+1):match('^%[.%]%s+'))
                  end
                elseif s:match('^    ') or s:match('^\t') then
                  m.kind,m.prefix='code',s:sub(1,1)=='\t' and 1 or 4
                end
              end
            end
          end
          if m.kind=='heading' then headings[#headings+1]={line=m.line,level=m.level,text=s:sub(m.prefix+1)} end
          if m.kind=='paragraph' then
            local name,url=s:match('^%s*%[([^%]]+)%]:%s*<?([^%s>]+)>?')
            if name then
              if name:sub(1,1)=='^' then
                m.kind,m.label='footnote',name:sub(2)
                m.prefix=#(s:match('^%s*%[%^[^%]]+%]:%s*') or '')
              else m.kind='reference'; refs[name:lower()]={url=url,line=m.line} end
            end
            local alt,path=s:match('^%s*!%[([^%]]*)%]%((.-)%)%s*$')
            if not path then path=s:match('^%s*!%[%[(.-)%]%]%s*$'); alt=path end
            if path then m.kind,m.alt,m.path='image',alt,path end
          end
        end
      end
    end
    i=i+1
  end
  local code_group
  for n,m in ipairs(meta) do
    if m.kind=='code' or m.kind=='fence' or m.kind=='frontmatter' then
      if m.block then m.code_group=m.block;code_group=nil
      else
        if not code_group or code_group.kind~=m.kind then code_group={first=n,last=n,key=doc.lines[n],kind=m.kind} end
        code_group.last=n;m.code_group=code_group
      end
    else code_group=nil end
  end
  local footnotes,count={},0
  for n,line in ipairs(doc.lines) do
    if meta[n].kind~='code' and meta[n].kind~='fence' then
      for label in line.text:gmatch('%[%^([^%]]+)%]') do
        if not footnotes[label] then count=count+1;footnotes[label]={number=count} end
        if meta[n].kind=='footnote' then footnotes[label].line=n;meta[n].footnote=footnotes[label].number end
      end
    end
  end
  local reference_parts={}
  for name,ref in pairs(refs) do reference_parts[#reference_parts+1]=name..'='..ref.url end
  for name,ref in pairs(footnotes) do reference_parts[#reference_parts+1]='^'..name..'='..ref.number end
  table.sort(reference_parts)
  local signature=table.concat(reference_parts,'\n')
  if self.reference_signature~=signature then self.reference_version=(self.reference_version or 0)+1 end
  self.reference_signature,self.tables=signature,tables
  self.lines,self.references,self.footnotes,self.headings,self.revision=meta,refs,footnotes,headings,doc.revision
  return true
end
return Parser
