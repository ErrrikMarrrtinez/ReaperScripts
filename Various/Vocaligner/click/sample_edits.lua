-- @noindex
-- SAMPLEEDITS is a reverse-engineered chunk format, supplied by the user.
-- Refuse unfamiliar syntax rather than silently discard it. No envelope fallback.
local M={}
local function finite(x)return type(x)=='number' and x==x and math.abs(x)<math.huge end
function M.supported(version)
 local a,b=tostring(version):match('^(%d+)%.(%d+)');a,b=tonumber(a),tonumber(b)
 return a and (a>7 or a==7 and b>=71) or false
end
-- Один проход по строкам без таблицы на каждую строку (на 10+ тыс. точек SPL прежний разбор стоил ~60 мс).
-- Данные собираются по тейкам; ошибки формата учитываются только для целевого тейка, как и раньше.
function M.parse(chunk,guid)
 assert(type(chunk)=='string' and #chunk<32*1024*1024,'Item chunk is missing or too large')
 local n=#chunk;local pos=1;local depth,take,found,first=0,0,nil,nil
 local target='GUID '..guid;local buckets={};local block;local source
 local function bucket(t) local b=buckets[t];if not b then b={channels={},spans={}};buckets[t]=b end;return b end
 local function bad(b,why) b.err=b.err or why end
 while pos<=n do
  -- быстрый путь для строк SPL внутри блока: одно сопоставление прямо в chunk, без выделения строки
  if block then
   local idx,v,nxt=chunk:match('^[ \t]*SPL[ \t]+(%d+)[ \t]+([^%s]+)[ \t\r]*\n()',pos)
   idx,v=tonumber(idx),tonumber(v)
   if idx and idx<2^53 and finite(v) and block.values[idx]==nil then block.values[idx]=v;pos=nxt;goto continue end
  end
  local nl=chunk:find('\n',pos,true);local stop=nl or n
  local line=chunk:sub(pos,nl and nl-1 or n):match('^%s*(.-)%s*$')
  local before=depth
  if line=='>' then depth=depth-1;before=depth
  elseif line:sub(1,1)=='<' then depth=depth+1 end
  assert(depth>=0,'Malformed item chunk')
  first=first or line
  if source and before==1 and line=='>' then source.bk.source=chunk:sub(source.a,stop);source=nil end
  if block then
   if before==1 and line=='>' then
    block.bk.spans[#block.bk.spans+1]={block.a,stop};block.bk.insert=stop+1;block=nil
   else
    local idx,v=line:match('^SPL%s+(%d+)%s+(%S+)$');idx,v=tonumber(idx),tonumber(v)
    if not(before==2 and idx and idx<2^53 and finite(v)) then bad(block.bk,'Unrecognized sample edit')
    elseif block.values[idx]~=nil then bad(block.bk,'Duplicate sample index')
    else block.values[idx]=v end
   end
  elseif before==1 then
   if line=='TAKE' or line:match('^TAKE%s') then take=take+1 end
   if line==target then assert(not found,'Duplicate take GUID');found=take end
   local bk=bucket(take)
   if line:sub(1,11)=='SAMPLEEDITS' then
    if bk.rate then bad(bk,'Duplicate SAMPLEEDITS header') end
    local a,b,rate=line:match('^SAMPLEEDITS%s+(%d+)%s+(%d+)%s+(%d+)$')
    if not(a and tonumber(rate)>0) then bad(bk,'Unrecognized SAMPLEEDITS header')
    else bk.a,bk.b,bk.rate=a,b,tonumber(rate);bk.spans[#bk.spans+1]={pos,stop} end
   elseif line:sub(1,7)=='<SOURCE' then source={bk=bk,a=pos} -- текст блока источника: по нему видно, что файл тот же
   elseif line:sub(1,5)=='<SPLS' then
    local ch=tonumber(line:match('^<SPLS%s+(%d+)$'))
    if not(ch and ch<64) then bad(bk,'Unrecognized sample channel');ch=-1 end
    if bk.channels[ch] then bad(bk,'Duplicate sample channel') end
    local values={};if ch>=0 then bk.channels[ch]=values end
    block={values=values,a=pos,bk=bk}
   end
   bk.insert=stop+1
  end
  pos=stop+1
  ::continue::
 end
 assert(depth==0 and first=='<ITEM','Malformed item chunk')
 assert(found~=nil,'Target take GUID is absent')
 local e=bucket(found);assert(not e.err,e.err)
 assert(not(block and block.bk==e),'Unterminated sample edits')
 e.guid,e.chunk=guid,chunk
 assert(e.insert,'Empty take');assert(e.rate or next(e.channels)==nil,'Missing SAMPLEEDITS header')
 return e
end
function M.get(e,ch,index)return e.channels[ch] and e.channels[ch][index] end
-- REAPER хранит значения SPL с 9 знаками после точки и не принимает экспоненту вида 1e-008
-- (читает такие крошечные значения как 0). Пишем сразу в его формате.
local fmt9=string.format
function M.number(v)
 local text=fmt9('%.9f',v)
 if text:find(',',1,true) then text=text:gsub(',','.') end
 text=text:match('^(.-)0*$');if text:sub(-1)=='.' then text=text:sub(1,-2) end
 if text=='-0' then text='0' end
 return text
end
function M.gain_only(a,b)
 local function mask(chunk)
  local depth=0;local out={}
  for line in (chunk..'\n'):gmatch('(.-)\n')do
   local t=line:match('^%s*(.-)%s*$')
   if depth==1 then line=line:gsub('^(%s*VOLPAN%s+)[%+%-%.%deE]+', '%1<gain>')end
   -- Выделение item в REAPER не влияет на звук: SEL не считается изменением item.
   if depth==1 then line=line:gsub('^(%s*SEL%s+)%d+','%1<sel>')end
   if t=='>' then depth=depth-1 elseif t:sub(1,1)=='<' then depth=depth+1 end
   out[#out+1]=line
  end
  return table.concat(out,'\n')
 end
 return mask(a)==mask(b)
end
-- Тот же item для записи: правки SAMPLEEDITS адресуются по сэмплам ИСХОДНОГО файла, поэтому значение имеет только
-- источник целевого тейка (блок <SOURCE>). Огибающие, громкость, позиция/длина, выделение — не повод отказывать.
-- Чужие (ручные) точки защищает baseline, свои — ownership в build().
function M.same_item(a,b,guid)
 local ea,eb=M.parse(a,guid),M.parse(b,guid)
 return ea.source~=nil and ea.source==eb.source and (ea.rate==nil or eb.rate==nil or ea.rate==eb.rate)
end
-- Desired replaces ONLY the previous patch owned by this running session.
-- Baseline includes all pre-existing hand edits; no full-take clear operation exists.
function M.build(chunk,guid,rate,channels,frames,desired,owned,baseline)
 local e=M.parse(chunk,guid)
 assert(not e.rate or e.rate==rate,'Existing edits use a different sample rate')
 assert(not e.a or e.a=='1' and e.b=='1','Existing sample edits are disabled or use unsupported flags')
 for ch,pts in pairs(owned or {})do for index,value in pairs(pts)do
  -- Свои точки прошлой записи всегда заменяются (даже если их изменил REAPER Undo): возвращаем baseline.
  e.channels[ch]=e.channels[ch] or {}
  e.channels[ch][index]=baseline and M.get(baseline,ch,index) or nil
 end end
 local count=0
 for ch,pts in pairs(desired or {})do
  assert(ch%1==0 and ch>=0 and ch<channels,'Invalid patch channel');e.channels[ch]=e.channels[ch] or {}
  for index,value in pairs(pts)do
   assert(index%1==0 and index>=0 and index<frames and finite(value),'Invalid patch sample')
   e.channels[ch][index]=value;count=count+1
  end
 end
 assert(count<=1000000,'Patch exceeds one million samples')
 local out={};local ids={};for ch,pts in pairs(e.channels)do if next(pts)then ids[#ids+1]=ch end end;table.sort(ids)
 local header=#ids>0 or baseline and baseline.rate
 if header then
  out[1]=('SAMPLEEDITS %s %s %d'):format(e.a or '1',e.b or '1',rate)
  for _,ch in ipairs(ids)do
   out[#out+1]='<SPLS '..ch;local indices={};for index in pairs(e.channels[ch])do indices[#indices+1]=index end;table.sort(indices)
   for _,index in ipairs(indices)do out[#out+1]=('SPL %.0f '):format(index)..M.number(e.channels[ch][index])end
   out[#out+1]='>'
  end
 end
 local nl=chunk:find('\r\n',1,true) and '\r\n' or '\n';local text=#out>0 and table.concat(out,nl)..nl or ''
 local spans=e.spans;local insertion=spans[1] and spans[1][1] or e.insert
 local pieces={chunk:sub(1,insertion-1),text};local cursor=insertion
 for _,span in ipairs(spans)do pieces[#pieces+1]=chunk:sub(cursor,span[1]-1);cursor=span[2]+1 end
 pieces[#pieces+1]=chunk:sub(cursor);local result=table.concat(pieces)
 assert(#result<32*1024*1024,'Resulting item chunk exceeds the prototype limit')
 -- третий результат: что должно оказаться в тейке после записи (commit сверяет с ним без повторного разбора)
 local wanted={channels={},rate=header and rate or nil,a=header and (e.a or '1') or nil,b=header and (e.b or '1') or nil}
 for _,ch in ipairs(ids)do wanted.channels[ch]=e.channels[ch] end
 return result,count,wanted
end
-- No yield during write/readback/rollback; caller prepares everything beforehand.
function M.commit(r,project,item,expected,replacement,guid,desired,diagnostic,wanted)
 assert(M.supported(r.GetAppVersion()),'Sample repair requires REAPER 7.71 or newer')
 assert(r.ValidatePtr2(project,item,'MediaItem*'),'Item no longer exists')
 local ok,current=r.GetItemStateChunk(item,'',false);assert(ok and current==expected,'Item changed; analyze again before applying')
 if current==replacement then return current end
 if diagnostic then diagnostic.snapshots.before=current;diagnostic.snapshots.wanted=replacement;diagnostic:mark('SetItemStateChunk / readback')end
 r.Undo_BeginBlock2(project)
 local success,result=xpcall(function()
  assert(r.SetItemStateChunk(item,replacement,false),'REAPER rejected sample edits')
  local read,actual=r.GetItemStateChunk(item,'',false);assert(read,'Cannot verify sample edits')
  if diagnostic then diagnostic.snapshots.actual=actual;diagnostic:mark('verify parsed sample edits')end
  local e=M.parse(actual,guid)
  wanted=wanted or M.parse(replacement,guid)
  assert(e.rate==wanted.rate and e.a==wanted.a and e.b==wanted.b,'Sample edit header changed after write')
  for ch,pts in pairs(wanted.channels)do for idx,value in pairs(pts)do
   local got=M.get(e,ch,idx);local tolerance=math.max(5e-8,math.abs(value)*1e-6) -- 5e-8 < половины младшего бита 24-bit (-146 dBFS)
   assert(got and math.abs(got-value)<=tolerance,('Sample edit readback differs: channel=%d source_sample=%d wanted=%.17g actual=%s delta=%s tolerance=%.9g rate=%s'):format(ch,idx,value,got and ('%.17g'):format(got)or 'MISSING',got and ('%.9g'):format(got-value)or 'n/a',tolerance,tostring(e.rate)))
  end end
  for ch,pts in pairs(e.channels)do for idx in pairs(pts)do assert(M.get(wanted,ch,idx)~=nil,'Unexpected sample edit after write')end end
  r.UpdateItemInProject(item);return {actual,e}
 end,debug.traceback)
 if not success then
  if diagnostic then diagnostic:mark('rollback')end
  local restored=r.SetItemStateChunk(item,current,false);local read,actual=r.GetItemStateChunk(item,'',false)
  if diagnostic and read then diagnostic.snapshots.rollback=actual end
  if not restored or not read or actual~=current then result=result..'\nROLLBACK FAILED: use REAPER Undo and inspect this item.' end
  r.UpdateItemInProject(item)
 end
 r.Undo_EndBlock2(project,success and 'Vocaligner experimental sample repair' or 'Vocaligner repair rollback',-1)
 assert(success,result);return result[1],result[2]
end
return M
