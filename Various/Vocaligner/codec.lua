-- @noindex
-- Bounded data-only cache format. Never evaluates Lua from a cache file.
local M={}
function M.encode(value,job)
  local out={'VC7\0'};local count=0
  local function put(v,depth)
    assert(depth<32,'Cache nesting limit.');count=count+1
    if job and count%1024==0 then job:checkpoint() end
    local t=type(v)
    if t=='nil' then out[#out+1]='N'
    elseif t=='boolean' then out[#out+1]=v and 'Y' or 'F'
    elseif t=='number' then assert(v==v and math.abs(v)<math.huge);out[#out+1]='D'..string.pack('<d',v)
    elseif t=='string' then out[#out+1]='S'..string.pack('<I4',#v)..v
    elseif t=='table' then
      local n=0;for _ in pairs(v) do n=n+1 end
      if n==#v then
        out[#out+1]='A'..string.pack('<I4',n);for i=1,n do put(v[i],depth+1) end
      else
        out[#out+1]='T'..string.pack('<I4',n)
        for k,x in pairs(v) do assert(type(k)=='string' or type(k)=='number');put(k,depth+1);put(x,depth+1) end
      end
    else error('Unsupported cache value: '..t) end
  end
  put(value,0);return table.concat(out)
end
function M.decode(s,job)
  assert(#s<=128*1024*1024 and s:sub(1,4)=='VC7\0','Invalid cache header.')
  local at,count=5,0
  local function take(n) assert(at+n-1<=#s,'Truncated cache.');local x=s:sub(at,at+n-1);at=at+n;return x end
  local function get(depth)
    count=count+1;assert(depth<32 and count<24000000,'Cache size limit.')
    if job and count%1024==0 then job:checkpoint() end
    local tag=take(1)
    if tag=='N' then return nil elseif tag=='Y' then return true elseif tag=='F' then return false
    elseif tag=='D' then local n=string.unpack('<d',take(8));assert(n==n and math.abs(n)<math.huge);return n
    elseif tag=='S' then return take(string.unpack('<I4',take(4)))
    elseif tag=='T' or tag=='A' then
      local n=string.unpack('<I4',take(4));assert(n<2000000,'Cache table limit.');local v={}
      for i=1,n do
        local k=tag=='A' and i or get(depth+1);assert(type(k)=='string' or type(k)=='number');v[k]=get(depth+1)
      end
      return v
    end
    error('Invalid cache tag.')
  end
  local v=get(0);assert(at==#s+1,'Trailing cache data.');return v
end
return M
