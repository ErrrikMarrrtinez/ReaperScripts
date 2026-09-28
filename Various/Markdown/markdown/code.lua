-- @noindex
local load=...
local U=load('core.utf8')
local Code={}
local keywords={}
for word in ('and break do else elseif end false for function goto if in local nil not or repeat return then true until while '..
  'class def elif except finally from import is lambda None pass raise try with yield as async await True False '..
  'const let var new export default extends static this super switch case throw catch typeof void null undefined '..
  'select from where join left right inner outer on group by order limit insert update delete into values set create table'):gmatch('%S+') do keywords[word]=true end
function Code.projection(text,language)
  local spans,p={},1
  local roles={plain={font='code',code=true,token='plain'},keyword={font='code',code=true,token='keyword'},
    string={font='code',code=true,token='string'},number={font='code',code=true,token='number'},comment={font='code',code=true,token='comment'}}
  while p<=#text do
    local a,b=text:find('^%s+',p)
    local role=roles.plain
    if not a then
      local c=text:sub(p,p);local pair=text:sub(p,p+1)
      local comment=(language=='lua' and pair=='--') or pair=='//' or
        ((language=='python' or language=='py' or language=='bash' or language=='sh' or language=='yaml') and c=='#')
      if comment then a,b=p,#text;role=roles.comment
      elseif c=='"' or c=="'" or (c=='`' and language~='lua') then
        a,b=p,p;local q=p+1
        while q<=#text do
          if text:sub(q,q)=='\\' then q=q+2
          elseif text:sub(q,q)==c then b=q;break else q=q+1 end
          b=math.min(q,#text)
        end
        role=roles.string
      else
        a,b=text:find('^%d[%w%.]*',p)
        if a then role=roles.number
        else
          a,b=text:find('^[%a_][%w_]*',p)
          if a and (keywords[text:sub(a,b)] or keywords[text:sub(a,b):lower()]) then role=roles.keyword end
        end
      end
    end
    if not a then a,b=p,U.next(text,p-1) end
    spans[#spans+1]={a=a-1,b=b,role=role};p=b+1
  end
  local cursor=1
  return {spans=spans,next_unit=function(line,pos)
    local span=spans[cursor]
    if not span or pos<span.a or pos>=span.b then
      local lo,hi=1,#spans
      while lo<hi do local mid=(lo+hi)//2;if spans[mid].b<=pos then lo=mid+1 else hi=mid end end
      cursor=lo;span=spans[lo]
    end
    local last=U.next(line.text,pos)
    return last,line.text:sub(pos+1,last),span and span.role or roles.plain
  end}
end
return Code
