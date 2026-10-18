-- @noindex
-- Сессия DeClick на время работы REAPER (как сессии cleaner): переживает перезапуск скрипта, но не REAPER.
-- По GUID тейка хранятся настройки, режим, вкл/выкл, исключённые кандидаты и, главное, какие точки SAMPLEEDITS
-- записаны нами и что было под ними до нас (base). Без этого новый анализ после перезапуска принял бы
-- наши же правки за исходные, и снять или заменить их корректно было бы нельзя.
local M={}
local section='Vocaligner declick v1'
local function available(r) return r.GetExtState and r.SetExtState and r.GetResourcePath and r.RecursiveCreateDirectory end
local function token(r)
 local t=r.GetExtState(section,'session')
 if t=='' then t=r.genGuid and r.genGuid() or (tostring(os.time())..tostring(r.time_precise()));r.SetExtState(section,'session',t,false) end
 return (t:gsub('%W',''))
end
local function path(r,guid)
 local dir=r.GetResourcePath()..'/Cache/Vocaligner';r.RecursiveCreateDirectory(dir,0)
 return dir..'/declick-'..token(r)..'-'..guid:gsub('%W','')..'.lua'
end
-- Lua-литерал без функций и ссылок: числа с полной точностью, ключи — числа или строки.
local function dump(v,out)
 local t=type(v)
 if t=='number' then out[#out+1]=v==math.floor(v) and math.abs(v)<2^53 and ('%d'):format(v) or ('%.17g'):format(v)
 elseif t=='string' then out[#out+1]=('%q'):format(v)
 elseif t=='boolean' then out[#out+1]=tostring(v)
 elseif t=='table' then
  out[#out+1]='{'
  for k,x in pairs(v) do
   local kt=type(k);local xt=type(x)
   if (kt=='number' or kt=='string') and (xt=='number' or xt=='string' or xt=='boolean' or xt=='table') then
    out[#out+1]='[';dump(k,out);out[#out+1]=']=';dump(x,out);out[#out+1]=','
   end
  end
  out[#out+1]='}'
 else out[#out+1]='nil' end
end
function M.save(r,guid,state)
 if not available(r) or not guid then return false end
 local out={'return '};dump(state,out)
 local f=io.open(path(r,guid),'wb');if not f then return false end
 f:write(table.concat(out));f:close();return true
end
function M.load(r,guid)
 if not available(r) or not guid then return nil end
 local f=io.open(path(r,guid),'rb');if not f then return nil end
 local text=f:read('a');f:close()
 local chunk=load(text,'=declick session','t',{});if not chunk then return nil end
 local ok,value=pcall(chunk)
 if ok and type(value)=='table' and value.version==1 then return value end
end
-- Состояние для сохранения из контроллера (owned и base только по нашим индексам).
function M.state(c)
 local s=c.s;local base={}
 for ch,pts in pairs(s.owned or {}) do
  base[ch]={};local manual=s.baseline.channels[ch]
  for idx in pairs(pts) do base[ch][idx]=manual and manual[idx] or nil end
 end
 local cfg={};for k,v in pairs(c.cfg) do cfg[k]=v end
 return {version=1,path=s.path,first=s.first,mode=c.mode,cfg=cfg,bypassed=c.bypassed==true,excluded=c.excluded,owned=s.owned,base=base}
end
return M
