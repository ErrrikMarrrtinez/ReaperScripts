-- @noindex
-- Read source PCM directly: item/take gain, FX and envelopes are never baked in.
local M={}
function M.open(path)
 local f=assert(io.open(path,'rb'),'Cannot open source WAV')
 local ok,w=pcall(function()
  local head=assert(f:read(12));assert(head:sub(1,4)=='RIFF' and head:sub(9,12)=='WAVE','Only RIFF WAV sources are supported in this prototype')
  local total=f:seek('end');f:seek('set',12);local out={path=path,file=f,size=total}
  while f:seek()+8<=total do
   local h=f:read(8);local n=string.unpack('<I4',h,5);local at=f:seek();assert(at+n<=total,'Truncated WAV chunk')
   if h:sub(1,4)=='fmt 'then
    assert(n>=16 and n<=4096,'Invalid WAV format chunk');local fmt=f:read(n)
    out.format,out.channels,out.sr,out.byte_rate,out.align,out.bits=string.unpack('<I2I2I4I4I2I2',fmt)
    if out.format==65534 then
     assert(n>=40 and string.unpack('<I2',fmt,17)>=22,'Invalid extensible WAV')
     local valid=string.unpack('<I2',fmt,19);assert(valid==0 or valid==out.bits,'Packed valid-bit WAV is unsupported')
     local guid=fmt:sub(25,40);assert(guid:sub(3)==string.char(0,0,0,0,16,0,128,0,0,170,0,56,155,113),'Unknown WAV subformat')
     out.format=string.unpack('<I2',guid)
    end
   elseif h:sub(1,4)=='data'then assert(not out.offset,'Multiple WAV data chunks unsupported');out.offset=at;out.bytes=n end
   f:seek('set',at+n+n%2)
  end
  assert(out.offset and out.format,'WAV lacks PCM data')
  assert(out.channels>=1 and out.channels<=8 and out.sr>=8000 and out.sr<=192000,'Unsupported source channels/sample rate')
  assert(out.format==1 and (out.bits==16 or out.bits==24 or out.bits==32) or out.format==3 and (out.bits==32 or out.bits==64),'Unsupported WAV encoding')
  assert(out.align==out.channels*out.bits/8 and out.bytes%out.align==0,'Invalid WAV frame layout')
  out.frames=out.bytes/out.align;return setmetatable(out,{__index=M})
 end)
 if not ok then f:close();error(w,0)end;return w
end
function M:close()if self.file then self.file:close();self.file=nil end end
function M:read_raw(first,count)
 assert(first>=0 and count>=0 and first%1==0 and count%1==0 and first+count<=self.frames,'Read outside source')
 self.file:seek('set',self.offset+first*self.align);local bytes=assert(self.file:read(count*self.align));assert(#bytes==count*self.align,'Source changed or truncated')
 return bytes
end
function M:read(first,count,edits)
 local bytes=self:read_raw(first,count);local a,p={},1
 for frame=first,first+count-1 do for ch=0,self.channels-1 do
  local v
  if self.format==3 then v,p=string.unpack(self.bits==32 and '<f' or '<d',bytes,p)
  elseif self.bits==16 then v,p=string.unpack('<i2',bytes,p);v=v/32768
  elseif self.bits==32 then v,p=string.unpack('<i4',bytes,p);v=v/2147483648
  else local x,y,z=bytes:byte(p,p+2);v=x+256*y+65536*z;if v>=8388608 then v=v-16777216 end;v=v/8388608;p=p+3 end
  local override=edits and edits.channels[ch] and edits.channels[ch][frame];if override~=nil then v=override end
  assert(v==v and math.abs(v)<1000000,'Non-finite or unreasonable source sample');a[#a+1]=v
 end end
 return a,bytes
end
return M
