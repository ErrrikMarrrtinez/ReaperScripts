-- @noindex
-- ReaPitch's own pitch engine, not the take's I_PITCHMODE. The VST-specific
-- payload is accessed through the documented named-config API. We accept only
-- the single-shifter layout verified from REAPER 7.73 Pro/Soloist exports.
local M={}
local catalogs=setmetatable({},{__mode='k'})
local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local map={};for i=1,#chars do map[chars:byte(i)]=i-1 end
function M.decode(text)
  assert(type(text)=='string' and #text<=4096 and #text%4==0 and not text:find('[^%w+/=]'),'Invalid ReaPitch chunk encoding')
  local out={}
  for i=1,#text,4 do
    local a,b,c,d=text:byte(i,i+3)
    assert(map[a] and map[b] and (map[c] or c==61 and d==61 and i==#text-3) and (map[d] or d==61 and i==#text-3),'Invalid ReaPitch chunk padding')
    local n=(map[a]<<18)|(map[b]<<12)|((map[c] or 0)<<6)|(map[d] or 0)
    out[#out+1]=string.char((n>>16)&255)..(c~=61 and string.char((n>>8)&255) or '')..(d~=61 and string.char(n&255) or '')
  end
  return table.concat(out)
end
function M.encode(bytes)
  local out={}
  for i=1,#bytes,3 do
    local a,b,c=bytes:byte(i,i+2);local n=(a<<16)|((b or 0)<<8)|(c or 0)
    out[#out+1]=chars:sub((n>>18)+1,(n>>18)+1)..chars:sub(((n>>12)&63)+1,((n>>12)&63)+1)..
      (b and chars:sub(((n>>6)&63)+1,((n>>6)&63)+1) or '=')..(c and chars:sub((n&63)+1,(n&63)+1) or '=')
  end
  return table.concat(out)
end
function M.parse(text)
  local bytes=M.decode(text)
  assert(#bytes==76,'Unsupported ReaPitch state size; algorithm was not changed')
  local version,value,shifters,size,record=string.unpack('<I4I4I4I4I4',bytes)
  assert(version==0 and shifters==1 and size==44 and record==2,'Unsupported ReaPitch state layout; algorithm was not changed')
  return {value=value,mode=value>>16,submode=value&65535},bytes
end
function M.modes(r)
  if catalogs[r] then return catalogs[r] end
  local out={};if not r.EnumPitchShiftModes then return out end
  for i=0,255 do
    local ok,label=r.EnumPitchShiftModes(i);if not ok then break end
    if label and label~='' then
      local mode={id=i,label=label,submodes={}}
      if r.EnumPitchShiftSubModes then for sub=0,255 do
        local name=r.EnumPitchShiftSubModes(i,sub);if not name or name=='' then break end
        mode.submodes[#mode.submodes+1]={id=sub,label=name}
      end end
      out[#out+1]=mode
    end
  end
  catalogs[r]=out;return out
end
function M.default(r)
  local fallback
  for _,mode in ipairs(M.modes(r)) do local label=mode.label:lower()
    if label:find('lastique',1,true) and label:find('soloist',1,true) then
      if label:find('3.3.3',1,true) then return mode.id<<16 end
      fallback=mode.id<<16
    end
  end
  return fallback
end
function M.valid(r,value)
  if type(value)~='number' or value%1~=0 or value<0 or value>0xffffff then return false end
  for _,mode in ipairs(M.modes(r)) do if mode.id==value>>16 then
    local sub=value&65535
    if #mode.submodes==0 then return sub==0 end
    for _,v in ipairs(mode.submodes) do if v.id==sub then return true end end
  end end
  return false
end
function M.label(r,value)
  if value==nil then return 'Algorithm unavailable' end
  for _,mode in ipairs(M.modes(r)) do if mode.id==value>>16 then
    for _,sub in ipairs(mode.submodes) do if sub.id==(value&65535) then return mode.label..' / '..sub.label end end
    return mode.label
  end end
  return string.format('Unknown algorithm %d / %d',value>>16,value&65535)
end
function M.read(r,take,fx)
  if not r.TakeFX_GetNamedConfigParm then return nil,'ReaPitch chunk API is unavailable' end
  local ok,text=r.TakeFX_GetNamedConfigParm(take,fx,'vst_chunk')
  if not ok then return nil,'Cannot read ReaPitch algorithm' end
  local yes,info,bytes=pcall(M.parse,text)
  if not yes then return nil,info end
  return info,bytes
end
function M.write(r,take,fx,value)
  assert(M.valid(r,value),'The selected ReaPitch algorithm is unavailable')
  local info,bytes=M.read(r,take,fx);assert(info,bytes)
  if info.value==value then return info end
  local guid=r.TakeFX_GetFXGUID(take,fx)
  -- Offset 4 of the VST payload, not offset 66 of REAPER's wrapped state.
  local changed=bytes:sub(1,4)..string.pack('<I4',value)..bytes:sub(9)
  assert(r.TakeFX_SetNamedConfigParm(take,fx,'vst_chunk',M.encode(changed)),'Could not set ReaPitch algorithm')
  local actual,why=M.read(r,take,fx);assert(actual,why)
  assert(actual.value==value and r.TakeFX_GetFXGUID(take,fx)==guid and r.TakeFX_GetNumParams(take,fx)==15,'ReaPitch algorithm readback failed')
  return actual
end
return M
