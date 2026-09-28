-- @noindex
local load = ...
local U = load('core.utf8')
local Inline = {}
local entities={amp='&',lt='<',gt='>',quot='"',apos="'",nbsp=' ',mdash='—',ndash='–',hellip='…',copy='©'}
local greek={alpha='α',beta='β',gamma='γ',delta='δ',theta='θ',lambda='λ',mu='μ',pi='π',sigma='σ',phi='φ',omega='ω',
  Delta='Δ',Sigma='Σ',Omega='Ω',times='×',cdot='·',pm='±',leq='≤',geq='≥',neq='≠',infty='∞',rightarrow='→',sum='∑',int='∫',sqrt='√'}
local superscript={['0']='⁰',['1']='¹',['2']='²',['3']='³',['4']='⁴',['5']='⁵',['6']='⁶',['7']='⁷',['8']='⁸',['9']='⁹',n='ⁿ',i='ⁱ',['+']='⁺',['-']='⁻'}
function Inline.math(text)
  text=text:gsub('\\([%a]+)',function(name) return greek[name] or ('\\'..name) end)
  text=text:gsub('%^%{([%d+%-ni]+)%}',function(s) return (s:gsub('.',superscript)) end)
  return (text:gsub('%^([%d+%-ni])',superscript))
end
local function style(parent, extra)
  local r={}; for k,v in pairs(parent or {}) do r[k]=v end
  for k,v in pairs(extra or {}) do r[k]=v end
  r.font = r.superscript and 'small' or r.code and 'code' or r.heading and 'h'..r.heading or
    r.bold and (r.italic and 'bold_italic' or 'bold') or r.italic and 'italic' or 'body'
  return r
end
Inline.style=style

function Inline.parse(text, options)
  options=options or {}
  local spans,missing={},{}
  local normal=style(options.style)
  local marker=style(normal,{muted=true})
  local function emit(a,b,role,hidden,display)
    if b>a then spans[#spans+1]={a=a,b=b,role=role,hidden=hidden and not options.active,display=display} end
  end
  local function syntax(a,b) emit(a,b,marker,true) end
  local function closing(delimiter,start,limit)
    if missing[delimiter] then return nil end
    local q=text:find(delimiter,start,true)
    while q and q<=limit do
      local slashes,k=0,q-1
      while k>=1 and text:sub(k,k)=='\\' do slashes=slashes+1;k=k-1 end
      if slashes%2==0 then return q end
      q=text:find(delimiter,q+#delimiter,true)
    end
    if not q then missing[delimiter]=true end
    return nil
  end
  local scan
  scan=function(first,last,role,depth)
    local p=first
    if depth>20 then emit(first-1,last,role); return end
    while p<=last do
      local special=text:find('[\\`*_~=%[%]!<&$#^%%]',p)
      local url_start=text:find('https?://',p)
      if url_start and (not special or url_start<special) then special=url_start end
      if not special or special>last then emit(p-1,last,role); break end
      if special>p then emit(p-1,special-1,role);p=special end
      local c=text:sub(p,p); local handled=false
      if url_start==p then
        local value=text:sub(p,last):match('^https?://[^%s<>]+')
        value=value and value:gsub('[.,;]+$','')
        if value then emit(p-1,p+#value-1,style(role,{link=value}));p=p+#value;handled=true end
      elseif c=='\\' and p<last and text:sub(p+1,p+1):match('%p') then
        syntax(p-1,p);emit(p,p+1,role);p=p+2;handled=true
      elseif c=='`' then
        local delimiter=text:match('^`+',p)
        local q=closing(delimiter,p+#delimiter,last)
        if q then
          syntax(p-1,p+#delimiter-1);emit(p+#delimiter-1,q-1,style(role,{code=true}))
          syntax(q-1,q+#delimiter-1);p=q+#delimiter;handled=true
        end
      elseif text:sub(p,p+1)=='%%' then
        local q=closing('%%',p+2,last)
        if q then emit(p-1,q+1,marker,true);p=q+2;handled=true end
      elseif c=='*' or c=='_' or text:sub(p,p+1)=='~~' or text:sub(p,p+1)=='==' then
        local run=text:match('^%*+',p) or text:match('^_+',p)
        local count=run and math.min(3,#run) or 2
        local delim=text:sub(p,p+count-1)
        local q=closing(delim,p+count,last)
        local intraword=c=='_' and p>first and text:sub(p-1,p-1):match('[%w]')
        if q and q>p+count and not intraword and not text:sub(p+count,p+count):match('%s') then
          local extra= c=='~' and {strike=true} or c=='=' and {highlight=true} or
            count==3 and {bold=true,italic=true} or count==2 and {bold=true} or {italic=true}
          syntax(p-1,p+count-1);scan(p+count,q-1,style(role,extra),depth+1)
          syntax(q-1,q+count-1);p=q+count;handled=true
        end
      elseif c=='[' or (c=='!' and text:sub(p+1,p+1)=='[') then
        local image=c=='!';local open=image and p+1 or p
        local checkbox=options.checkboxes and not image and text:sub(p,p+2):match('^%[([ xX])%]$')
        if checkbox then
          emit(p-1,p+2,style(role,{checkbox=true,checked=checkbox~=' ',widget_width=options.checkbox_width or 24}),false,'\1checkbox')
          role=style(role,{strike=checkbox~=' ',muted=checkbox~=' '})
          p=p+3;handled=true
        elseif text:sub(open,open+1)=='[[' then
          local q=closing(']]',open+2,last)
          if q then
            local inner=text:sub(open+2,q-1);local pipe=inner:find('|',1,true)
            local url=pipe and inner:sub(1,pipe-1) or inner
            local label=pipe and open+pipe+2 or open+2
            syntax(p-1,label-1)
            scan(label,q-1,style(role,{link=url,wiki=true,image=image}),depth+1)
            syntax(q-1,q+1);p=q+2;handled=true
          end
        else
          local q=closing(']',open+1,last)
          if q then
            local label=text:sub(open+1,q-1)
            local footnote=label:sub(1,1)=='^' and options.footnotes and options.footnotes[label:sub(2)]
            if footnote and not options.active then
              emit(p-1,q,style(role,{link='#^'..label:sub(2),superscript=true}),false,tostring(footnote.number))
              p=q+1;handled=true
            end
            if not handled then
            local finish,url=q,nil
            if text:sub(q+1,q+1)=='(' then
              local level,k=1,q+2
              while k<=last and level>0 do
                local ch=text:sub(k,k)
                if ch=='\\' then k=k+1 elseif ch=='(' then level=level+1 elseif ch==')' then level=level-1 end
                k=k+1
              end
              if level==0 then finish=k-1;url=text:sub(q+2,k-2):match('^<?(.-)>?%s+"') or text:sub(q+2,k-2):gsub('^<',''):gsub('>$','') end
            elseif text:sub(q+1,q+1)=='[' then
              local ending=closing(']',q+2,last)
              if ending then
                local name=text:sub(q+2,ending-1); if name=='' then name=text:sub(open+1,q-1) end
                local ref=options.references and options.references[name:lower()]
                if ref then url=ref.url;finish=ending end
              end
            else
              local label=text:sub(open+1,q-1)
              local ref=options.references and options.references[label:lower()]
              if ref then url=ref.url end
              if label:sub(1,1)=='^' then url='#^'..label:sub(2) end
            end
            if url then
              syntax(p-1,open);scan(open+1,q-1,style(role,{link=url,image=image}),depth+1)
              syntax(q-1,finish);p=finish+1;handled=true
            end
            end
          end
        end
      elseif c=='<' then
        if text:sub(p,p+3)=='<!--' then
          local close=closing('-->',p+4,last)
          if close then emit(p-1,close+2,marker,true);p=close+3;handled=true end
        end
        if not handled then
        local ending=text:find('>',p+1,true)
        if ending and ending<=last then
          local inside=text:sub(p+1,ending-1)
          if inside:match('^https?://') or inside:match('^[^%s]+@[^%s]+%.[^%s]+$') then
            syntax(p-1,p);emit(p,ending-1,style(role,{link=inside:find('@',1,true) and 'mailto:'..inside or inside}))
            syntax(ending-1,ending);p=ending+1;handled=true
          else
            local tag=inside:lower()
            local tags={b={bold=true},strong={bold=true},i={italic=true},em={italic=true},s={strike=true},del={strike=true},
              mark={highlight=true},code={code=true},kbd={kbd=true},u={underline=true},sup={muted=true},sub={muted=true}}
            local extra=tags[tag];local close=extra and closing('</'..tag..'>',ending+1,last)
            if close then
              syntax(p-1,ending);scan(ending+1,close-1,style(role,extra),depth+1)
              syntax(close-1,close+#tag+2);p=close+#tag+3;handled=true
            elseif tag=='br' or tag=='br/' or tag=='br /' then
              emit(p-1,ending,style(role,{break_line=not options.active}),false,not options.active and '' or nil);p=ending+1;handled=true
            end
          end
        end
        end
      elseif c=='&' then
        local entity=text:match('^&([#%w]+);',p)
        if entity then
          local value=entities[entity]
          local number=entity:match('^#(%d+)$') or entity:match('^#x(%x+)$')
          if number then
            local n=tonumber(number,entity:sub(1,2)=='#x' and 16 or 10)
            if n and n>0 and n<=0x10FFFF and not (n>=0xD800 and n<=0xDFFF) then value=utf8.char(n) end
          end
          if value then emit(p-1,p+#entity+1,role,false,not options.active and value or nil);p=p+#entity+2;handled=true end
        end
      elseif c=='$' then
        local count=text:sub(p,p+1)=='$$' and 2 or 1
        local q=closing(string.rep('$',count),p+count,last)
        if q then
          syntax(p-1,p+count-1)
          emit(p+count-1,q-1,style(role,{italic=true,math=true}),false,not options.active and Inline.math(text:sub(p+count,q-1)) or nil)
          syntax(q-1,q+count-1);p=q+count;handled=true
        end
      elseif c=='#' and (p==first or text:sub(p-1,p-1):match('%s')) then
        local tag=text:match('^#[^%s#.,;:!%?%[%]%(%)<>]+',p)
        if tag then emit(p-1,p+#tag-1,style(role,{tag=true}));p=p+#tag;handled=true end
      end
      if not handled then emit(p-1,p,role);p=p+1 end
    end
  end
  if options.literal then emit(0,#text,normal)
  else scan(1,#text,normal,0) end
  for _,span in ipairs(spans) do
    local role=span.role
    if not span.hidden and not options.literal and (role.code or role.tag or role.kbd) then
      local padding=(options.font_size or 18)*(role.tag and .23 or .22)
      local gap=role.tag and (options.font_size or 18)*.15 or 0
      span.first_role=style(role,{pad_left=padding+gap,outer_left=gap})
      span.last_role=style(role,{pad_right=padding+gap,outer_right=gap})
      span.only_role=style(role,{pad_left=padding+gap,pad_right=padding+gap,outer_left=gap,outer_right=gap})
    end
  end
  local current=1
  local function next_unit(line,pos)
    local span=spans[current]
    if not span or pos<span.a or pos>=span.b then
      local lo,hi=1,#spans
      while lo<hi do local mid=(lo+hi)//2;if spans[mid].b<=pos then lo=mid+1 else hi=mid end end
      current=lo;span=spans[lo]
    end
    if not span then return U.next(line.text,pos),line.text:sub(pos+1,U.next(line.text,pos)),normal end
    if span.hidden then return span.b,'',span.role end
    if span.display and pos==span.a then return span.b,span.display,span.role end
    local last=math.min(span.b,U.next(line.text,pos))
    local role=span.role
    if span.first_role then
      role=pos==span.a and (last==span.b and span.only_role or span.first_role) or last==span.b and span.last_role or role
    end
    return last,line.text:sub(pos+1,last),role
  end
  return {next_unit=next_unit,spans=spans}
end
return Inline
