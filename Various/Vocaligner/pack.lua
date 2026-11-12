-- @noindex
-- Компактное хранение данных скрипта в проекте (ProjExtState / P_EXT тейков).
--   * Сжатие: блочный LZ4 (стандартный формат, кодер и декодер на Lua; нативный кодер может писать тот же формат).
--   * Один слой кодирования. Длинные значения REAPER сам пишет в .rpp блоком <BIN> (base64 сырых байт; порог ~2 КБ,
--     проверено по файлам проектов), поэтому значение от 4 КБ отдаём ему сырыми байтами — экранируем только \0 и \1
--     (строки API нуль-терминированные). Короткие значения REAPER пишет строкой текста — их кодируем base64 сами.
--   * Запись проверяется чтением обратно; если байты не вернулись как были, значение переписывается в base64-режиме,
--     и до конца сессии сырые байты больше не используются.
-- Формат значения: 'VZ' + режим ('r' сырые байты | 'b' base64) + полезная нагрузка;
-- полезная нагрузка = varint(длина исходных данных) + LZ4-блок (или 'VZ'..режим..'0' + данные без сжатия).
local M={}
local RAW_MIN=4096
local raw_ok=true -- сырые байты прошли проверку чтением (сбрасывается при первом несовпадении)

-- ===== varint =====
function M.varint(n) local out={};repeat local b=n&127;n=n>>7;out[#out+1]=string.char(n>0 and b|128 or b) until n==0;return table.concat(out) end
function M.read_varint(s,at)
  local n,shift=0,0
  while true do
    local b=s:byte(at);assert(b,'Truncated varint');at=at+1
    n=n|((b&127)<<shift);if b<128 then return n,at end
    shift=shift+7;assert(shift<63,'Varint overflow')
  end
end

-- ===== LZ4 (block) =====
local function ext_len(n) -- байты продолжения длины (после 15)
  if n<15 then return '' end
  n=n-15;local out={};while n>=255 do out[#out+1]='\255';n=n-255 end;out[#out+1]=string.char(n);return table.concat(out)
end
-- job (необязательно): job:checkpoint() каждые ~64 КБ — длинные данные сжимаются в фоне без подвисания интерфейса
function M.lz_compress(s,job)
  local n=#s;local out={};local anchor=1
  local unpack,byte=string.unpack,string.byte
  local function emit(lit_end,off,ml)
    local ll=lit_end-anchor
    local token=(ll<15 and ll or 15)<<4
    if off then local m=ml-4;token=token|(m<15 and m or 15) end
    out[#out+1]=string.char(token)..ext_len(ll)..s:sub(anchor,lit_end-1)
    if off then out[#out+1]=string.pack('<I2',off)..ext_len(ml-4) end
  end
  if n>=13 then
    local hash={};local i=1;local limit=n-12;local misses=0;local next_check=65536
    while i<=limit do
      if job and i>=next_check then job:checkpoint();next_check=i+65536 end
      local v=unpack('<I4',s,i)
      local h=((v*2654435761)&0xffffffff)>>17
      local ref=hash[h];hash[h]=i
      if ref and i-ref<=65535 and unpack('<I4',s,ref)==v then
        -- длина совпадения: по 8 байт, затем побайтно
        local ml=4;local maxl=n-5-i+1 -- последние 5 байт — литералы (правило формата)
        while ml+8<=maxl and unpack('<i8',s,i+ml)==unpack('<i8',s,ref+ml) do ml=ml+8 end
        while ml<maxl and byte(s,i+ml)==byte(s,ref+ml) do ml=ml+1 end
        if ml>=4 then
          -- назад: литералы перед совпадением, которые тоже совпадают
          while i>anchor and ref>1 and byte(s,i-1)==byte(s,ref-1) do i=i-1;ref=ref-1;ml=ml+1 end
          emit(i,i-ref,ml);i=i+ml;anchor=i;misses=0
          if i-2>=1 and i-2<=limit then hash[((unpack('<I4',s,i-2)*2654435761)&0xffffffff)>>17]=i-2 end
        else i=i+1 end
      else
        misses=misses+1;i=i+1+math.min(misses>>6,31) -- несжимаемые участки проскакиваем быстрее
      end
    end
  end
  emit(n+1,nil)
  return table.concat(out)
end
-- rawlen — длина исходных данных (проверяется)
function M.lz_decompress(c,rawlen,job)
  local done={};local recent={};local ends={};local rlen=0;local total=0
  local byte,sub=string.byte,string.sub
  local function push(p)
    if #p==0 then return end
    recent[#recent+1]=p;rlen=rlen+#p;ends[#recent]=rlen;total=total+#p
    if #recent>=2048 then
      local r=table.concat(recent)
      if #r>131072 then done[#done+1]=sub(r,1,#r-65536);r=sub(r,-65536) end
      recent={r};ends={#r};rlen=#r
    end
  end
  local function get(from,len) -- from: смещение от начала recent (1-базовое)
    local lo,hi=1,#recent
    while lo<hi do local mid=(lo+hi)//2;if ends[mid]<from then lo=mid+1 else hi=mid end end
    local parts={};local need=len;local k=lo;local pos=from-(ends[k]-#recent[k])
    while need>0 do
      local p=recent[k];assert(p,'Invalid LZ4 match')
      local take=math.min(need,#p-pos+1);parts[#parts+1]=sub(p,pos,pos+take-1);need=need-take;k=k+1;pos=1
    end
    return table.concat(parts)
  end
  local at,n=1,#c;local steps=0
  while at<=n do
    steps=steps+1;if job and steps%4096==0 then job:checkpoint() end
    local token=byte(c,at);at=at+1
    local ll=token>>4
    if ll==15 then repeat local b=byte(c,at);assert(b,'Truncated LZ4');at=at+1;ll=ll+b until b<255 end
    assert(at+ll-1<=n,'Truncated LZ4 literals');push(sub(c,at,at+ll-1));at=at+ll
    if at>n then break end
    local off=string.unpack('<I2',c,at);at=at+2;assert(off>0 and off<=rlen,'Invalid LZ4 offset')
    local ml=(token&15)
    if ml==15 then repeat local b=byte(c,at);assert(b,'Truncated LZ4');at=at+1;ml=ml+b until b<255 end
    ml=ml+4
    local from=rlen-off+1
    if off>=ml then push(get(from,ml))
    else local pat=get(from,off);push(string.rep(pat,ml//off+1):sub(1,ml)) end
  end
  for _,p in ipairs(recent) do done[#done+1]=p end
  local out=table.concat(done);assert(#out==rawlen,'LZ4 length mismatch');return out
end

-- ===== хэш содержимого (FNV-1a 64) — ключ общего пула одинаковых блоков =====
function M.hash64i(s)
  local h=-3750763034362895579 -- 0xcbf29ce484222325
  local byte=string.byte;local n=#s
  for i=1,n-7,8 do
    local a,b,c,d,e,f,g,k=byte(s,i,i+7)
    h=(h~a)*1099511628211;h=(h~b)*1099511628211;h=(h~c)*1099511628211;h=(h~d)*1099511628211
    h=(h~e)*1099511628211;h=(h~f)*1099511628211;h=(h~g)*1099511628211;h=(h~k)*1099511628211
  end
  for i=n-(n%8)+1,n do h=(h~byte(s,i))*1099511628211 end
  return h
end
function M.hash64(s) return string.format('%016x',M.hash64i(s))..string.format('%x',#s) end
-- ===== base64 =====
local B64='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local enc,dec
local function tables()
  if enc then return end
  enc,dec={},{}
  for i=0,63 do enc[i]=B64:sub(i+1,i+1);dec[B64:byte(i+1)]=i end
end
function M.b64(s)
  tables();local out={};local n=#s
  for i=1,n-2,3 do local a,b,c=s:byte(i,i+2);local v=(a<<16)|(b<<8)|c;out[#out+1]=enc[v>>18]..enc[(v>>12)&63]..enc[(v>>6)&63]..enc[v&63] end
  local r=n%3
  if r==1 then local v=s:byte(n)<<16;out[#out+1]=enc[v>>18]..enc[(v>>12)&63]..'=='
  elseif r==2 then local a,b=s:byte(n-1,n);local v=(a<<16)|(b<<8);out[#out+1]=enc[v>>18]..enc[(v>>12)&63]..enc[(v>>6)&63]..'=' end
  return table.concat(out)
end
function M.unb64(s)
  tables();local out={};s=s:gsub('[^%w+/=]','')
  for i=1,#s,4 do
    local a,b,c,d=s:byte(i,i+3);local va,vb=dec[a],dec[b];assert(va and vb,'Invalid base64')
    local vc,vd=c and dec[c],d and dec[d]
    local v=(va<<18)|(vb<<12)|((vc or 0)<<6)|(vd or 0)
    out[#out+1]=string.char(v>>16)..(vc and string.char((v>>8)&255) or '')..(vd and string.char(v&255) or '')
  end
  return table.concat(out)
end

-- ===== значение для проекта =====
local ESC={['\0']='\1\2',['\1']='\1\3'};local UNESC={['\2']='\0',['\3']='\1'}
-- bytes -> строка для ProjExtState/P_EXT. force_b64 — без сырых байт.
function M.wrap(bytes,job,force_b64)
  local body
  local c=#bytes>=64 and M.lz_compress(bytes,job)
  if c and #c+8<#bytes then body=M.varint(#bytes)..c else body='\0'..bytes end -- '\0' первым: без сжатия (varint 0 невозможен при длине ≥1)
  if #bytes==0 then body='\0' end
  if not force_b64 and raw_ok and #body>=RAW_MIN then return 'VZr'..body:gsub('[\0\1]',ESC) end
  return 'VZb'..M.b64(body)
end
function M.is_wrapped(s) return type(s)=='string' and (s:sub(1,3)=='VZr' or s:sub(1,3)=='VZb') end
function M.unwrap(s,job)
  assert(M.is_wrapped(s),'Not a packed value')
  local body=s:sub(1,3)=='VZr' and s:sub(4):gsub('\1([\2\3])',UNESC) or M.unb64(s:sub(4))
  if body:byte(1)==0 then return body:sub(2) end
  local n,at=M.read_varint(body,1);assert(n<=256*1024*1024,'Packed value too large')
  return M.lz_decompress(body:sub(at),n,job)
end
-- Запись с проверкой: значение должно вернуться байт в байт, иначе — base64 (и сырые байты отключаются до конца сессии)
local function verified(set,get,text,bytes,job)
  set(text)
  if get()==text then return text end
  if text:sub(1,3)=='VZr' then
    raw_ok=false;local safe=M.wrap(bytes,job,true);set(safe)
    if get()==safe then return safe end
  end
  error('The project did not keep the saved value',0)
end
-- text — уже упакованное значение (упаковать заранее в фоне, а записать коротким вызовом)
function M.put_proj(r,project,section,key,bytes,job,text)
  text=text or M.wrap(bytes,job)
  return verified(function(v) r.SetProjExtState(project,section,key,v) end,
    function() local _,v=r.GetProjExtState(project,section,key);return v end,text,bytes,job)
end
function M.put_take(r,take,key,bytes,job)
  local text=M.wrap(bytes,job)
  return verified(function(v) r.GetSetMediaItemTakeInfo_String(take,key,v,true) end,
    function() local _,v=r.GetSetMediaItemTakeInfo_String(take,key,'',false);return v end,text,bytes,job)
end
function M._raw_ok(v) if v~=nil then raw_ok=v end;return raw_ok end
return M
