-- @noindex
-- Reconstruction: LSAR at the joins + pitch-period copy in the body (see lsar_code); the older
-- independent bidirectional AR extrapolation (M.code) is kept for rollback via M.method. It estimates
-- missing audio; it cannot guarantee recovery of the original signal.
local M={};M.__index=M
M.code=[[
// Each side is ordered from distant context toward the gap.
side=0;limit=0;memset(output,0,length);
loop(2,
 src=side==0 ? left : right;n=side==0 ? nl : nr;
 memset(corr,0,order+1);k=0;
 loop(order+1,
  i=k;v=0;loop(max(0,n-k),v+=src[i]*src[i-k];i+=1;);
  corr[k]=v;k+=1;
 );
 // Ridge regularization and bounded reflection coefficients keep prediction stable.
 error=corr[0]*1.001+0.000000000001;memset(coeff,0,order+1);
 k=1;
 loop(order,
  v=corr[k];j=1;loop(k-1,v-=coeff[j]*corr[k-j];j+=1;);
  reflection=max(-0.98,min(0.98,v/error));
  memcpy(previous,coeff,order+1);j=1;
  loop(k-1,coeff[j]=previous[j]-reflection*previous[k-j];j+=1;);
  coeff[k]=reflection;error=max(0.000000000001,error*(1-reflection*reflection));k+=1;
 );
 cap=0;i=0;loop(n,cap=max(cap,abs(src[i]));i+=1;);limit=max(limit,cap);
 k=0;loop(order,history[k]=k<n ? src[n-1-k] : 0;k+=1;);
 i=0;loop(length,
  v=0;k=1;loop(order,v+=coeff[k]*history[k-1];k+=1;);
  v=max(-2*cap,min(2*cap,v));
  k=order-1;loop(order-1,history[k]=history[k-1];k-=1;);history[0]=v;
  at=side==0 ? i : length-1-i;t=(i+1)/(length+1);
  weight=1-t*t*t*(10+t*(-15+6*t));output[at]+=weight*v;i+=1;
 );side+=1;
);
]]
-- LSAR (least-squares AR interpolation, Janssen / Godsill-Rayner): одна AR-модель по обеим сторонам,
-- пропуск решается как минимум энергии ошибки предсказания по всему отрезку [левый контекст | пропуск | правый].
-- В отличие от двух экстраполяций с весами, оба края совпадают с сигналом по построению (нет щелчка на стыке)
-- и амплитуда не «тает» к середине. Система Q·x = -b тёплицева и ленточная (ширина = порядок AR):
-- ленточный Холецкий, O(n·p²). left: от дальнего к пропуску; right: от дальнего к пропуску (обратный порядок).
M.lsar_code=[[
p=order;N=nl+length+nr;
// x: левый контекст, нули на месте пропуска, правый контекст в естественном порядке
i=0;loop(nl,x[i]=left[i];i+=1;);
i=0;loop(length,x[nl+i]=0;i+=1;);
i=0;loop(nr,x[nl+length+i]=right[nr-1-i];i+=1;);
// автокорреляция по обоим контекстам (пропуск не участвует) и коэффициенты AR (Левинсон, ограниченные отражения)
memset(corr,0,p+1);k=0;
loop(p+1,
 v=0;i=k;loop(max(0,nl-k),v+=x[i]*x[i-k];i+=1;);
 i=nl+length+k;loop(max(0,nr-k),v+=x[i]*x[i-k];i+=1;);
 corr[k]=v;k+=1;
);
error=corr[0]*1.001+0.000000000001;memset(coeff,0,p+1);
k=1;
loop(p,
 v=corr[k];j=1;loop(k-1,v-=coeff[j]*corr[k-j];j+=1;);
 reflection=max(-0.98,min(0.98,v/error));
 memcpy(previous,coeff,p+1);j=1;
 loop(k-1,coeff[j]=previous[j]-reflection*previous[k-j];j+=1;);
 coeff[k]=reflection;error=max(0.000000000001,error*(1-reflection*reflection));k+=1;
);
// Тело пропуска: AR порядка ≤48 (≈1 мс) не видит период основного тона и к середине «тает»,
// поэтому тело — копия периода (лаг 2.5–12.5 мс по нормированной корреляции последних 4 мс контекста).
// Обе стороны — плавный переход между копиями; если с одной стороны контекста мало — копия с другой.
pitched=0;have_f=0;have_b=0;
sr>0 && length>=floor(sr*0.0015) ? (
 win=floor(sr*0.004);tmin=floor(sr*0.0025);s=0;
 loop(2,
  src=s==0 ? left : right;cnt=s==0 ? nl : nr;dst=s==0 ? fwd : bwd;
  tmax=min(floor(sr*0.0125),cnt-win);best=-2;lag=0;
  tmax>tmin ? (
   T=tmin;
   loop(tmax-tmin,
    dot=0;ea=0;eb=0;i=0;
    loop(win,va=src[cnt-win+i];vb=src[cnt-win-T+i];dot+=va*vb;ea+=va*va;eb+=vb*vb;i+=1;);
    c=dot/(sqrt(ea*eb)+0.000000000001);
    c>best ? (best=c;lag=T;);
    T+=1;
   );
  );
  lag>0 ? (
   i=0;loop(length,dst[i]=i-lag<0 ? src[cnt+i-lag] : dst[i-lag];i+=1;);
   pitched+=1;s==0 ? have_f=1 : have_b=1;
  );
  s+=1;
 );
);
pitched>0 ? (
 // Края (0.5 мс): AR-экстраполяция с каждой стороны (O(n·p), без тяжёлой ленточной системы) — точно
 // продолжает сигнал у стыка; дальше — тело из копий периода.
 s=0;
 loop(2,
  src=s==0 ? left : right;cnt=s==0 ? nl : nr;dst=s==0 ? e : rhs;
  cap=0;i=0;loop(cnt,cap=max(cap,abs(src[i]));i+=1;);
  k=0;loop(p,z[k]=k<cnt ? src[cnt-1-k] : 0;k+=1;);
  i=0;loop(length,
   v=0;k=1;loop(p,v+=coeff[k]*z[k-1];k+=1;);
   v=max(-2*cap,min(2*cap,v));
   k=p-1;loop(p-1,z[k]=z[k-1];k-=1;);z[0]=v;dst[i]=v;i+=1;
  );
  s+=1;
 );
 K=max(2,min(floor(length/3),floor(sr*0.0005)));
 i=0;loop(length,
  t=i/max(1,length-1);w=t*t*t*(10+t*(-15+6*t));
  body=have_f && have_b ? (1-w)*fwd[i]+w*bwd[length-1-i] : (have_f ? fwd[i] : bwd[length-1-i]);
  edge=(1-w)*e[i]+w*rhs[length-1-i];
  u=min(1,i/K);ea=u*u*u*(10+u*(-15+6*u));
  u=min(1,(length-1-i)/K);eb=u*u*u*(10+u*(-15+6*u));
  mixw=ea*eb;output[i]=(1-mixw)*edge+mixw*body;
  i+=1;
 );
) : (
 // Короткий пропуск (< 1.5 мс) или нет периода: LSAR (Janssen / Godsill-Rayner) — минимум энергии ошибки
 // предсказания по всему отрезку; ленточная тёплицева система, ленточный Холецкий O(n·p²).
 a[0]=1;k=1;loop(p,a[k]=-coeff[k];k+=1;);
 d=0;loop(p+1,v=0;k=0;loop(p+1-d,v+=a[k]*a[k+d];k+=1;);ra[d]=v;d+=1;);
 t=0;loop(length+p,at=nl+t;v=0;k=0;loop(p+1,v+=a[k]*x[at-k];k+=1;);e[t]=v;t+=1;);
 m=0;loop(length,v=0;d=0;loop(p+1,v+=a[d]*e[m+d];d+=1;);rhs[m]=-v;m+=1;);
 ridge=ra[0]*0.000000001+0.000000000000001;
 i=0;loop(length,
  j=max(0,i-p);
  loop(i-j+1,
   v=ra[i-j]+(i==j ? ridge : 0);
   k=max(0,i-p);loop(j-k,v-=band[i*(p+1)+(i-k)]*band[j*(p+1)+(j-k)];k+=1;);
   i==j ? (band[i*(p+1)]=sqrt(max(v,0.000000000000001));) : (band[i*(p+1)+(i-j)]=v/band[j*(p+1)];);
   j+=1;
  );
  i+=1;
 );
 i=0;loop(length,v=rhs[i];k=max(0,i-p);loop(i-k,v-=band[i*(p+1)+(i-k)]*z[k];k+=1;);z[i]=v/band[i*(p+1)];i+=1;);
 i=length-1;loop(length,v=z[i];k=i+1;loop(min(length-1,i+p)-i,v-=band[k*(p+1)+(k-i)]*output[k];k+=1;);output[i]=v/band[i*(p+1)];i-=1;);
);
cap=0;i=0;loop(nl,cap=max(cap,abs(left[i]));i+=1;);i=0;loop(nr,cap=max(cap,abs(right[i]));i+=1;);
i=0;loop(length,output[i]=max(-2*cap,min(2*cap,output[i]));i+=1;);
]]
M.method='lsar' -- 'lsar' | 'extrapolate' (прежний метод, оставлен для отката)
function M.new(im,ctx,r)
 local self=setmetatable({im=im,r=r},M)
 self.fn=im.CreateFunctionFromEEL(M.code);im.Attach(ctx,self.fn)
 for k,v in pairs({left=0,right=16384,output=32768,corr=49152,coeff=49408,previous=49664,history=49920})do im.Function_SetValue(self.fn,k,v)end
 -- LSAR: пропуск до 16384, порядок до 48 → лента 16384*49 ≈ 803k
 self.lsar=im.CreateFunctionFromEEL(M.lsar_code);im.Attach(ctx,self.lsar)
 for k,v in pairs({left=0,right=16384,output=32768,corr=49152,coeff=49408,previous=49664,a=49920,ra=50176,
   x=65536,e=131072,rhs=163840,z=196608,band=262144,fwd=1100000,bwd=1120000})do im.Function_SetValue(self.lsar,k,v)end
 return self
end
function M:predict(left,right,n,sr)
 assert(#left>=4 and #right>=4 and #left<=16384 and #right<=16384 and n>0 and n<=16384,'Insufficient repair context')
 local im=self.im;local lsar=M.method=='lsar'
 local fn=lsar and self.lsar or self.fn
 local order=math.min(48,math.floor(math.min(#left,#right)/4))
 if lsar then order=math.max(1,math.min(order,#left,#right)) end
 for k,v in pairs({nl=#left,nr=#right,length=n,order=order,sr=sr or 0})do im.Function_SetValue(fn,k,v)end
 im.Function_SetValue_Array(fn,'left',self.r.new_array(left));im.Function_SetValue_Array(fn,'right',self.r.new_array(right))
 im.Function_Execute(fn);local a=self.r.new_array(n);im.Function_GetValue_Array(fn,'output',a);return a.table()
end
local function smooth(t)t=math.max(0,math.min(1,t));return t*t*t*(10+t*(-15+6*t))end
function M.regions(events,cfg,mode,sr,count)
 local out={};local widen=math.floor(cfg[mode..'_widen_ms']*sr/1000+.5)
 local fade=math.max(2,math.floor(cfg[mode..'_fade_ms']*sr/1000+.5))
 for _,e in ipairs(events)do if not e.excluded then
  local a=math.max(0,math.floor(e.start*sr)-widen-fade);local b=math.min(count-1,math.ceil(e.finish*sr)+widen+fade)
  local prev=out[#out]
  if prev and a<=prev.b+1 then prev.b=math.max(prev.b,b)
  else out[#out+1]={a=a,b=b,fade=fade}end
 end end
 return out
end
-- read(first,count) returns immutable interleaved baseline SOURCE samples.
-- Участки идут слева направо; левый контекст может заходить на предыдущие участки — там берутся уже
-- исправленные значения, поэтому соседей в серии не нужно склеивать (чистый звук между щелчками не трогается).
-- cache (необязательно): прогнозы участков по ключу (границы, контекст, сила, переход, зависимость от соседа);
-- при движении слайдеров пересчитываются только изменившиеся участки.
function M.build(engine,read,events,cfg,mode,sr,channels,count,source_first,job,cache)
 local regions=M.regions(events,cfg,mode,sr,count);local patch={};local skipped=0
 local strength=(cfg[mode..'_strength'] or 100)/100;assert(strength>=0 and strength<=1)
 if strength==0 then return patch,0 end
 local used={};local context=math.min(16384,math.floor(sr*.030));local prevkey=''
 for k,e in ipairs(regions)do
  local n=e.b-e.a+1
  local left=math.max(e.a-context,0)
  local right=math.min(e.b+context,k<#regions and regions[k+1].a-1 or count-1)
  if e.a-left<32 or right-e.b<32 or n>math.min(16384,math.floor(sr*.080))then skipped=skipped+1;prevkey=''
  else
   local depends=k>1 and regions[k-1].b>=left and prevkey or ''
   local key=table.concat({e.a,e.b,left,right,e.fade,strength,depends},':')
   local input=read(left,right-left+1);local nl,nr=e.a-left,right-e.b
   for ch=0,channels-1 do
    patch[ch]=patch[ch] or {};local done=patch[ch]
    local ckey=key..':'..ch;local predicted=cache and cache[ckey]
    if not predicted then
     local a,b={},{}
     for i=0,nl-1 do a[#a+1]=done[source_first+left+i] or input[i*channels+ch+1] end
     for i=right-left,e.b-left+1,-1 do b[#b+1]=input[i*channels+ch+1]end
     predicted=job:call(engine.predict,engine,a,b,n,sr)
    end
    if cache then used[ckey]=predicted end
    for i=0,n-1 do
     local wet=strength*smooth(i/e.fade)*smooth((n-1-i)/e.fade)
     if wet>0 then
      local original=input[(nl+i)*channels+ch+1];local value=original+wet*(predicted[i+1]-original)
      assert(value==value and math.abs(value)<1000000,'Invalid reconstruction')
      done[source_first+e.a+i]=value
     end
    end
   end
   prevkey=key
  end
  job:checkpoint(k/math.max(1,#regions),'Reconstructing samples')
 end
 if cache then for k in pairs(cache) do cache[k]=nil end;for k,v in pairs(used) do cache[k]=v end end
 return patch,skipped
end
return M
