-- @noindex
-- Independent multiband + robust adaptive-prediction front end. No FFT dependency.
local M={};M.__index=M
M.version=1
M.context_code=[[
// Identical two-sided percentile statistics to the Lua reference, in bounded blocks.
// Статистика считается каждые 4 кадра. При stride==4 окно за шаг сдвигается ровно на один отсчёт:
// вместо полной сортировки удаляем выходящее значение и вставляем входящее — то же мультимножество,
// тот же результат, но O(n) вместо O(n^2) на шаг. Иначе (другой stride) — полная сортировка, как раньше.
dmax=guard+stride*floor((span-guard)/stride);
f=0;
loop(frames,
 i=offset+f;
 f%4==0 ? (k=0;
 loop(6,
  s=0;base=0;
  loop(2,
   side=s==0 ? -1 : 1;arr=sorted+(k*2+s)*256;
   (f==0 || stride!=4 || force_full) ? (
    n=0;d=guard;
    while(d<=span)(
     at=i+side*d;
     at>=0 && at<total ? (
      v=input[at*8+k];j=n;
      while(j>0 && arr[j-1]>v)(arr[j]=arr[j-1];j-=1;);
      arr[j]=v;n+=1;
     );d+=stride;
    );
   ) : (
    n=counts[k*2+s];
    gone=side<0 ? i-4-dmax : i-4+guard;came=side<0 ? i-guard : i+dmax;
    gone>=0 && gone<total ? (
     v=input[gone*8+k];j=0;
     while(j<n && arr[j]!==v)(j+=1;); // !== точное сравнение: != в EEL сравнивает с допуском
     j<n ? (while(j<n-1)(arr[j]=arr[j+1];j+=1;);n-=1;);
    );
    came>=0 && came<total ? (
     v=input[came*8+k];j=n;
     while(j>0 && arr[j-1]>v)(arr[j]=arr[j-1];j-=1;);
     arr[j]=v;n+=1;
    );
   );
   counts[k*2+s]=n;
   v=n>0 ? arr[max(0,ceil(n*0.65)-1)] : 0;
   base=max(base,v);k==0 ? (side<0 ? left_energy=v : right_energy=v;);
   s+=1;
  );
  bases[k]=max(base,0.0000001);k+=1;
 ););
 out=output+f*8;k=0;loop(6,out[k]=bases[k];k+=1;);
 out[6]=left_energy;out[7]=right_energy;f+=1;
);
]]
-- Короткий локальный контраст для Mouth: ВЧ-энергия (row[5]) и остаток предсказания (row[1]) делятся на медиану
-- соседей i±guard..span (сам всплеск в окно не входит). Окно скользящее: на шаг с каждой стороны уходит одно
-- значение и приходит одно (точное сравнение !== при удалении). Выход: два отношения на кадр.
M.transient_code=[[
function ins(arr,cnt,v) local(j) (j=cnt;while(j>0 && arr[j-1]>v)(arr[j]=arr[j-1];j-=1;);arr[j]=v;cnt+1;);
function del(arr,cnt,v) local(j) (j=0;while(j<cnt && arr[j]!==v)(j+=1;);j<cnt ? (while(j<cnt-1)(arr[j]=arr[j+1];j+=1;);cnt-1;) : cnt;);
f=0;
loop(frames,
 i=offset+f;k=0;
 loop(2,
  col=k==0 ? 5 : 1;arr=sorted+k*256;
  f==0 ? (
   n=0;d=-span;
   loop(2*span+1,
    abs(d)>=guard ? (at=i+d;(at>=0 && at<total) ? (n=ins(arr,n,input[at*8+col]);););
    d+=1;
   );
  ) : (
   n=counts[k];
   at=i-1-span;(at>=0 && at<total) ? (n=del(arr,n,input[at*8+col]););
   at=i-1+guard;(at>=0 && at<total) ? (n=del(arr,n,input[at*8+col]););
   at=i-guard;(at>=0 && at<total) ? (n=ins(arr,n,input[at*8+col]););
   at=i+span;(at>=0 && at<total) ? (n=ins(arr,n,input[at*8+col]););
  );
  counts[k]=n;
  med=n<=0 ? 0 : (n%2 ? arr[(n-1)/2] : 0.5*(arr[n/2-1]+arr[n/2]));
  output[f*2+k]=input[i*8+col]/(med+(k==0 ? floor_h : floor_r));
  k+=1;
 );
 f+=1;
);
]]
-- Контраст полос Mouth (как Lua-эталон в spectral.lua): перцентиль 0.65 кадров i±near..far (шаг 4)
-- с каждой стороны, base=max(левый,правый,1e-12), контраст = clamp(10*log10(e/base),0,60).
M.contrast_code=[[
i=0;
loop(frames,
 b=0;
 loop(bands,
  s=0;base=0.000000000001;
  loop(2,
   side=s==0 ? -1 : 1;n=0;d=near;
   while(d<=far)(
    at=i+side*d;
    at>=0 && at<frames ? (
     v=rows[at*bands+b];j=n;
     while(j>0 && scratch[j-1]>v)(scratch[j]=scratch[j-1];j-=1;);
     scratch[j]=v;n+=1;
    );d+=4;
   );
   q=n>0 ? scratch[max(0,ceil(n*0.65)-1)] : 0;base=max(base,q);s+=1;
  );
  e=max(rows[i*bands+b],0.000000000001);
  output[i*bands+b]=max(0,min(60,10*log10(e/base)));
  b+=1;
 );
 i+=1;
);
]]
M.code=[[
reset ? (memset(state,0,1024);sample_index=0;bin_n=0;memset(acc,0,8););
invalid=0;written=0;i=0;
al=1-exp(-2*$pi*700/sr);am=1-exp(-2*$pi*4000/sr);
loop(count,
 ch=0;energy=0;residual=0;delta=0;lo=0;mi=0;hi=0;peak=0;
 loop(channels,
  s=state+ch*64; x=input[i*channels+ch];
  !(abs(x)<=1000000) ? (invalid=1;x=0;);
  s[0]+=al*(x-s[0]);s[1]+=am*(x-s[1]);
  low=s[0];mid=s[1]-s[0];high=x-s[1];
  prediction=0;norm=0;k=0;
  loop(12,prediction+=s[16+k]*s[32+k];norm+=s[32+k]^2;k+=1;);
  err=x-prediction;
  // Clip adaptation, never the measured residual. Impulses must not train the model.
  cap=max(0.000001,4*sqrt(s[4]));adapt=max(-cap,min(cap,err));
  s[4]=0.999*s[4]+0.001*min(err*err,cap*cap);
  mu=0.12*adapt/(norm+0.00000001);k=0;
  loop(12,s[16+k]=max(-2,min(2,s[16+k]+mu*s[32+k]));k+=1;);
  k=11;loop(11,s[32+k]=s[31+k];k-=1;);s[32]=x;
  energy=max(energy,x*x);residual=max(residual,err*err);
  delta=max(delta,abs(x-2*s[2]+s[3]));s[3]=s[2];s[2]=x;
  lo=max(lo,low*low);mi=max(mi,mid*mid);hi=max(hi,high*high);peak=max(peak,abs(x));ch+=1;
 );
 acc[0]+=energy;acc[1]+=residual;acc[2]=max(acc[2],delta);
 acc[3]+=lo;acc[4]+=mi;acc[5]+=hi;
 peak>acc[6] ? (acc[6]=peak;acc[7]=sample_index;);
 bin_n+=1;sample_index+=1;i+=1;
 (bin_n>=hop || (last && i==count)) ? (
  row=output+written*8;
  row[0]=sqrt(acc[0]/bin_n);row[1]=sqrt(acc[1]/bin_n);row[2]=acc[2];
  row[3]=sqrt(acc[3]/bin_n);row[4]=sqrt(acc[4]/bin_n);row[5]=sqrt(acc[5]/bin_n);
  row[6]=acc[6];row[7]=acc[7];written+=1;bin_n=0;memset(acc,0,8);
 );
);
]]
function M.new(im,ctx,r)
 local self=setmetatable({im=im,r=r},M)
 local ok,why=pcall(function()
  self.fn=im.CreateFunctionFromEEL(M.code);im.Attach(ctx,self.fn)
  for k,v in pairs({input=0,output=65536,state=330000,acc=331024}) do im.Function_SetValue(self.fn,k,v) end
  self.context_fn=im.CreateFunctionFromEEL(M.context_code);im.Attach(ctx,self.context_fn)
  for k,v in pairs({input=0,output=65536,scratch=100000,bases=100256,weights=100272,sorted=100400,counts=103600})do im.Function_SetValue(self.context_fn,k,v)end
  self.transient_fn=im.CreateFunctionFromEEL(M.transient_code);im.Attach(ctx,self.transient_fn)
  for k,v in pairs({input=0,output=65536,sorted=100000,counts=100600})do im.Function_SetValue(self.transient_fn,k,v)end
  self.contrast_fn=im.CreateFunctionFromEEL(M.contrast_code);im.Attach(ctx,self.contrast_fn)
  for k,v in pairs({rows=0,output=1000000,scratch=2000000})do im.Function_SetValue(self.contrast_fn,k,v)end
 end)
 if not ok then self.fn=nil;self.reason=tostring(why) end
 return self
end
function M:context(data,mode,job)
 local im,fn=self.im,self.context_fn;local h=data.hop;local result={}
 local span=math.max(4,math.floor((mode=='mouth' and .080 or .030)/h));local guard=math.max(2,math.floor((mode=='mouth' and .025 or .003)/h));local stride=math.max(1,math.floor(.001/h))
 for first=1,#data.rows,1024 do
  local last=math.min(#data.rows,first+1023);local a,b=math.max(1,first-span),math.min(#data.rows,last+span);local input={}
  for i=a,b do for k=1,8 do input[#input+1]=data.rows[i][k]end end
  local output=job:call(function()
   for k,v in pairs({offset=first-a,frames=last-first+1,total=b-a+1,global_first=first-1,global_total=#data.rows,
     span=span,guard=guard,stride=stride})do im.Function_SetValue(fn,k,v)end
   im.Function_SetValue_Array(fn,'input',self.r.new_array(input))
   im.Function_Execute(fn);local out=self.r.new_array((last-first+1)*8);im.Function_GetValue_Array(fn,'output',out);return out.table()
  end)
  for i=1,#output,8 do result[#result+1]={output[i],output[i+1],output[i+2],output[i+3],output[i+4],output[i+5],output[i+6],output[i+7]}end
  job:checkpoint()
 end
 return result
end
-- Отношения короткого контраста для всех кадров data.rows: rh (ВЧ) и rp (остаток предсказания), 1-based.
-- guard/span — в кадрах по 0.25 мс; floor_h/floor_r — пол знаменателя (тишина не даёт огромных отношений).
function M:transient(data,guard,span,floor_h,floor_r,job)
 local im,fn=self.im,self.transient_fn;local rows=data.rows;local rh,rp={},{}
 for first=1,#rows,4096 do
  local last=math.min(#rows,first+4095);local a,b=math.max(1,first-span),math.min(#rows,last+span);local input={}
  for i=a,b do local row=rows[i];for k=1,8 do input[#input+1]=row[k] end end
  local out=job:call(function()
   for k,v in pairs({offset=first-a,frames=last-first+1,total=b-a+1,guard=guard,span=span,floor_h=floor_h,floor_r=floor_r})do im.Function_SetValue(fn,k,v)end
   im.Function_SetValue_Array(fn,'input',self.r.new_array(input))
   im.Function_Execute(fn);local o=self.r.new_array((last-first+1)*2);im.Function_GetValue_Array(fn,'output',o);return o.table()
  end)
  for i=1,#out,2 do rh[#rh+1]=out[i];rp[#rp+1]=out[i+1] end
  job:checkpoint()
 end
 return rh,rp
end
-- rows: плоский массив энергий полос (frames*bands). Возвращает плоский массив контраста той же формы.
function M:contrast(rows,frames,bands,near,far)
 assert(self.contrast_fn and frames*bands<=1000000 and bands>=1,'Mouth contrast input exceeds the EEL buffer')
 local im,fn=self.im,self.contrast_fn
 for k,v in pairs({frames=frames,bands=bands,near=near,far=far})do im.Function_SetValue(fn,k,v)end
 im.Function_SetValue_Array(fn,'rows',self.r.new_array(rows));im.Function_Execute(fn)
 local out=self.r.new_array(frames*bands);im.Function_GetValue_Array(fn,'output',out);return out.table()
end
function M:run(buffer,n,ch,sr,reset,last)
 assert(self.fn,'Click EEL engine unavailable: '..tostring(self.reason))
 assert(n*ch<=32768 and ch>=1 and ch<=8 and sr>=8000 and sr<=192000,'Unsupported click PCM block')
 local im,fn=self.im,self.fn
 for k,v in pairs({count=n,channels=ch,sr=sr,hop=math.max(1,math.floor(sr*.00025+.5)),reset=reset and 1 or 0,last=last and 1 or 0})do im.Function_SetValue(fn,k,v) end
 im.Function_SetValue_Array(fn,'input',buffer);im.Function_Execute(fn)
 assert(im.Function_GetValue(fn,'invalid')==0,'Invalid PCM in click analysis')
 local count=im.Function_GetValue(fn,'written');assert(count>=0 and count*8<=262144,'Click output overflow')
 if count==0 then return {} end
 local out=self.r.new_array(count*8);im.Function_GetValue_Array(fn,'output',out);return out.table()
end
return M
