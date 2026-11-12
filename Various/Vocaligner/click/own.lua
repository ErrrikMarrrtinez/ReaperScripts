-- @noindex
-- Какие точки правок сэмплов (SAMPLEEDITS) поставил DeClick — компактная запись в тейке (P_EXT), переживает
-- перезапуск REAPER. Сама сессия DeClick (анализ, настройки) в проект не пишется: после перезахода нужен новый анализ,
-- но сброс снимает именно наши правки, а правки пользователя (и то, что было под нашими точками) остаются.
-- Значения наших точек не дублируются (они и так лежат в айтеме): хранятся прогоны индексов и хэш каждых 64 значений.
-- При чтении точка считается нашей, только если её блок совпал по хэшу: блок, тронутый руками, — уже пользователя.
local import=...;local Pack=import('pack');local Codec=import('codec');local M={}
M.KEY='P_EXT:VocalignerClickOwn1'
M.BLOCK=64
local function block_hash(vals)
  local t={};for i,v in ipairs(vals) do t[i]=string.pack('<d',v) end
  return string.pack('<i8',Pack.hash64i(table.concat(t)))
end
-- owned: {[ch]={[idx]=наше значение}}; base: {[ch]={[idx]=что было под нашей точкой у пользователя}} (обычно пусто)
function M.encode(path,owned,base)
  local chs={}
  for ch,pts in pairs(owned or {}) do
    local idx={};for i in pairs(pts) do idx[#idx+1]=i end;table.sort(idx)
    if #idx>0 then
      local runs,hashes,b={},{},{};local prev=-1;local i=1
      while i<=#idx do
        local j=i;while j<#idx and idx[j+1]==idx[j]+1 do j=j+1 end
        runs[#runs+1]=Pack.varint(idx[i]-prev-1)..Pack.varint(j-i+1);prev=idx[j];i=j+1
      end
      for k=1,#idx,M.BLOCK do
        local vals={};for m=k,math.min(#idx,k+M.BLOCK-1) do vals[#vals+1]=pts[idx[m]] end
        hashes[#hashes+1]=block_hash(vals)
      end
      local bc=base and base[ch]
      if bc then for _,x in ipairs(idx) do if bc[x]~=nil then b[#b+1]=Pack.varint(x)..string.pack('<d',bc[x]) end end end
      chs[#chs+1]={ch=ch,runs=table.concat(runs),hashes=table.concat(hashes),base=table.concat(b)}
    end
  end
  if #chs==0 then return nil end
  return Codec.encode({v=1,path=path,chs=chs})
end
-- get(ch,idx) -> текущее значение точки в айтеме или nil
function M.decode(bytes,get)
  local v=Codec.decode(bytes);assert(type(v)=='table' and v.v==1 and type(v.chs)=='table','Invalid DeClick ownership record')
  local owned,base={},{}
  for _,c in ipairs(v.chs) do
    local idx={};local at=1;local prev=-1
    while at<=#c.runs do
      local d,cnt;d,at=Pack.read_varint(c.runs,at);cnt,at=Pack.read_varint(c.runs,at)
      assert(cnt<=10000000,'Invalid DeClick ownership run')
      local s=prev+1+d;for k=s,s+cnt-1 do idx[#idx+1]=k end;prev=s+cnt-1
    end
    local o={};local bi=0
    for k=1,#idx,M.BLOCK do
      local vals={};local ok=true
      for m=k,math.min(#idx,k+M.BLOCK-1) do local x=get(c.ch,idx[m]);if x==nil then ok=false;break end;vals[#vals+1]=x end
      if ok and block_hash(vals)==c.hashes:sub(bi*8+1,bi*8+8) then
        for m=k,math.min(#idx,k+M.BLOCK-1) do o[idx[m]]=vals[m-k+1] end
      end
      bi=bi+1
    end
    local b={};local at2=1
    while at2<=#c.base do local x,val;x,at2=Pack.read_varint(c.base,at2);val,at2=string.unpack('<d',c.base,at2);if o[x]~=nil then b[x]=val end end
    if next(o) then owned[c.ch]=o;base[c.ch]=b end
  end
  return {path=v.path,owned=owned,base=base}
end
function M.save(r,take,path,owned,base)
  local bytes=M.encode(path,owned,base)
  if not bytes then r.GetSetMediaItemTakeInfo_String(take,M.KEY,'',true);return end
  Pack.put_take(r,take,M.KEY,bytes)
end
-- parsed — разбор текущего chunk (click/sample_edits.parse); SE — модуль sample_edits
function M.load(r,take,parsed,SE)
  local ok,text=r.GetSetMediaItemTakeInfo_String(take,M.KEY,'',false)
  if not ok or text=='' or not Pack.is_wrapped(text) then return nil end
  local good,rec=pcall(function() return M.decode(Pack.unwrap(text),function(ch,idx) return SE.get(parsed,ch,idx) end) end)
  return good and rec or nil
end
return M
