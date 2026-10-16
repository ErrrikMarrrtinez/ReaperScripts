-- @noindex
local M={}
-- Eight frequency rows at a time. The weights and samples are unchanged;
-- contiguous dot products move the inner multiply/add loop into WDL's native
-- mem_multiply_sum. Symmetric temporal taps use [left+right, center].
-- Memory: original weights <32768, packed weights <65536, feature/tensor
-- buffers <1048576; at most 8*128*12*7*3 scratch doubles above 1048576.
local pack=[[
 fo=first_f;loop(num_f,
  ci=0;loop(cin,k=0;loop(kf,
   fi=fo+k*dilation-padding;
   dst=1048576+(fo-first_f)*frames*kernel+(ci*kf+k)*kt;
   row=input+(ci*fin+fi)*frames;t=0;
   fi>=0 && fi<fin ? (
    kt==2 ? (
     pair=851968+(ci*fin+fi)*frames;loop(frames,dst[0]=pair[t];dst[1]=row[t];dst+=kernel;t+=1;);
    ) : kt==3 ? (
     loop(frames,dst[0]=t>0 ? row[t-1] : 0;dst[1]=row[t];dst[2]=t+1<frames ? row[t+1] : 0;dst+=kernel;t+=1;);
    ) : (loop(frames,dst[0]=row[t];dst+=kernel;t+=1;));
   ) : (loop(frames,memset(dst,0,kt);dst+=kernel;));
   k+=1;);ci+=1;);
  fo+=1;
 );
]]
local multiply=[[
 oc=0;loop(cout,fo=first_f;loop(num_f,
  dst=output+(oc*fout+fo)*frames;src=1048576+(fo-first_f)*frames*kernel;
  t=0;loop(frames,
   v=biases[oc]+(residual>=0 ? residual[(oc*fout+fo)*frames+t] : 0)+mem_multiply_sum(weights+oc*kernel,src,kernel);
   dst[t]=relu ? max(0,v) : v;src+=kernel;t+=1;
  );fo+=1;);oc+=1;
 );
]]
-- Packing and its dot products have no checkpoint between them. Execute both
-- in one VM call; the arithmetic and memory order are exactly unchanged.
M.code='mode==6 ? ('..pack..multiply..') : mode==4 ? ('..pack..') : mode==5 ? ('..multiply..') : '
function M.upload(self)
  local weights={};self.dot_offsets={}
  for i,l in ipairs(self.model.layers) do
    assert(l.kt==1 or l.kt==3,'Unsupported Pitch temporal kernel')
    local symmetric=self.offsets[i].symmetric
    self.dot_offsets[i]={weight=32768+#weights,kt=symmetric and 2 or l.kt}
    for j,v in ipairs(l.weight) do if not symmetric or j%3~=0 then weights[#weights+1]=v end end
  end
  assert(32768+#weights<=65536,'Packed Pitch weights exceed their buffer')
  self.im.Function_SetValue(self.fn,'weights',32768)
  self.im.Function_SetValue_Array(self.fn,'weights',self.r.new_array(weights))
end
function M.conv(self,x,index,fin,fout,n,residual,relu,job,dest)
  local im,fn,l=self.im,self.fn,self.model.layers[index];local packed=self.dot_offsets[index]
  local function native(f) if job then return job:call(f) else return f() end end
  local function execute()
    local started=self.r.time_precise();im.Function_Execute(fn)
    self.kernel_ms=(self.kernel_ms or 0)+(self.r.time_precise()-started)*1000
    self.kernel_calls=(self.kernel_calls or 0)+1
  end
  if packed.kt==2 then native(function()
    for k,v in pairs({mode=3,input=x,output=851968,frames=n,cin=l.cin,fin=fin}) do im.Function_SetValue(fn,k,v) end
    execute()
  end) end
  native(function()
    for k,v in pairs({input=x,output=dest,weights=packed.weight,biases=self.offsets[index].bias,
      residual=residual or -1,cin=l.cin,cout=l.cout,fin=fin,fout=fout,frames=n,kf=l.kf,kt=packed.kt,
      dilation=l.df,padding=l.pad,relu=relu and 1 or 0,kernel=l.cin*l.kf*packed.kt}) do im.Function_SetValue(fn,k,v) end
  end)
  for first=0,fout-1,8 do
    native(function()
      im.Function_SetValue(fn,'mode',6);im.Function_SetValue(fn,'first_f',first)
      im.Function_SetValue(fn,'num_f',math.min(8,fout-first));execute()
    end)
    if job then job:checkpoint() end
  end
  return dest
end
return M
