-- @noindex
-- Lossless doubles for large, regular arrays; legacy table caches remain readable.
local M={}
local packed=setmetatable({},{__mode='k'})
local function checkpoint(job,i) if job and i%256==0 then job:checkpoint() end end
function M.points(points,job)
  if not points then return nil end
  if packed[points] then return packed[points] end
  local out={};for i,p in ipairs(points) do
    out[i]=string.pack('<dddd',p.t,p.v,p.shape,p.tension);checkpoint(job,i)
  end
  local bytes=table.concat(out);packed[points]=bytes;return bytes
end
function M.read_points(bytes,job)
  assert(#bytes%32==0 and #bytes<2000000*32,'Invalid envelope cache.')
  local out={};local previous=-math.huge
  for at=1,#bytes,32 do
    local t,v,shape,tension=string.unpack('<dddd',bytes,at)
    assert(t==t and math.abs(t)<math.huge and t>=previous and v==v and v>=0 and v<math.huge
      and shape%1==0 and shape>=0 and shape<math.huge and tension==tension and math.abs(tension)<math.huge,'Invalid envelope point.')
    out[#out+1]={t=t,v=v,shape=shape,tension=tension};previous=t;checkpoint(job,#out)
  end
  packed[out]=bytes;return out
end
function M.curve(curve,job)
  local bytes=packed[curve.points]
  if not bytes then
    local out={};for i,p in ipairs(curve.points) do out[i]=string.pack('<dd',p.t,p.db);checkpoint(job,i) end
    bytes=table.concat(out);packed[curve.points]=bytes
  end
  return {packed=bytes,max_db=curve.max_db,hop=curve.hop,detail=curve.detail,recipes=curve.recipes,
    frozen=curve.frozen and M.curve(curve.frozen,job) or nil}
end
local fields={'t','rms','zcr','noise_flat','breath_flat','breath_tonal','air','low','flat','min','max','flux'}
local allowed={noise_bands=true,cep=true,spec=true,chroma=true}
for _,k in ipairs(fields) do allowed[k]=true end
local format='<'..string.rep('d',#fields+32)
function M.audio(data,job)
  local out={};for _,k in ipairs({'hop','len','analysis_rate','accessor_scale','reads','analysis_stats','dynamics_only'}) do out[k]=data[k] end
  local bytes={}
  for i,f in ipairs(data.frames) do
    -- Full alignment data or future extra fields use the original generic codec.
    for k in pairs(f) do if not allowed[k] then out.frames=data.frames;return out end end
    if #(f.cep or {})>0 or #(f.spec or {})>0 or #(f.chroma or {})>0 or #(f.noise_bands or {})~=32 then
      out.frames=data.frames;return out
    end
    local row={};for j,k in ipairs(fields) do
      if type(f[k])~='number' then out.frames=data.frames;return out end;row[j]=f[k]
    end
    for b=1,32 do row[#fields+b]=f.noise_bands[b] end
    bytes[i]=string.pack(format,table.unpack(row));checkpoint(job,i)
  end
  out.frame_bytes=table.concat(bytes);out.frame_format=1;return out
end
function M.read_audio(data,job)
  if not data.frame_bytes then return data end
  local bytes=data.frame_bytes;local stride=(#fields+32)*8
  assert(data.frame_format==1 and #bytes%stride==0 and #bytes<=120000*stride,'Invalid audio cache.')
  data.frames={}
  for at=1,#bytes,stride do
    local row={string.unpack(format,bytes,at)};local f={cep={},spec={},chroma={},noise_bands={}}
    for j=1,#fields+32 do assert(row[j]==row[j] and math.abs(row[j])<math.huge,'Invalid cached feature.') end
    for j,k in ipairs(fields) do f[k]=row[j] end
    for b=1,32 do f.noise_bands[b]=row[#fields+b] end
    data.frames[#data.frames+1]=f;checkpoint(job,#data.frames)
  end
  data.frame_bytes=nil;data.frame_format=nil;return data
end
return M
