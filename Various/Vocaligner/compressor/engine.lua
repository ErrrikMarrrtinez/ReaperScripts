-- @noindex
-- Compressor transfer and RMS/envelope follower adapted from EUGEN27771's
-- gen_Envelope-based Compressor v2 (Julian mod), v2.20. GPL-3.0-only.
-- See NOTICE.md. Audio I/O and the ordered envelope pipeline are independent.
local M={};M.__index=M
M.transfer_code=[[
slope=1/max(1,ratio);xL=threshold-knee;
xH=threshold+sqrt(2)*knee*cos(atan(slope));yH=threshold+slope*(xH-threshold);
ratio>1 && knee>0 ? (xC=(yH-2*xL+ratio*xH)/(ratio-1);yC=2*xL-xC;
 radius2=(yC-xL)^2+(xC-xL)^2;);
i=0;loop(count,
 level=input[i];db=0;
 ratio>1 ? (knee<=0 ? db=max(0,(1-slope)*(level-threshold)) : (
 level>=xH ? db=(1-slope)*(level-threshold) : level>xL ? db=level-yC-sqrt(max(0,radius2-(level-xC)^2));));
 output[i]=db-makeup;i+=1;
);
]]
M.gate_code=[[
reset ? (opened=0;holdleft=0;gain_db=range;);
ga=attack>0 ? exp(-dt/attack) : 0;gr=release>0 ? exp(-dt/release) : 0;
i=0;loop(count,
 level=input[i];
 level>=threshold ? (opened=1;holdleft=hold_steps;) : (
  level>=threshold-hysteresis && opened ? holdleft=hold_steps : (holdleft>0 ? holdleft-=1 : opened=0;);
 );
 target=opened ? 0 : range;gain_db=target+(target<gain_db ? ga : gr)*(gain_db-target);
 output[i]=gain_db;i+=1;
);
]]
M.code=[[
function coeff(freq,high,base) local(k,n) (
 k=tan($pi*min(sr*.49,max(1,freq))/sr);n=1/(1+sqrt(2)*k+k*k);
 base[0]=high ? n : k*k*n;base[1]=high ? -2*n : 2*base[0];base[2]=base[0];
 base[3]=2*(k*k-1)*n;base[4]=(1-sqrt(2)*k+k*k)*n;
);
function filter(x,c,s) local(y) (
 y=c[0]*x+s[0];s[0]=c[1]*x-c[3]*y+s[1];s[1]=c[2]*x-c[4]*y;y;
);
reset ? (
 memset(states,0,64);memset(ring,0,rms_size);rpos=0;sum=0;follower=0;opened=0;holdleft=0;gate_db=range;
 sample_index=0;next_emit=0;lo=0;hi=0;energy=0;energy_n=0;acc=0;acc_n=0;
 coeff(lp,0,coef);coeff(hp,1,coef+8);
 ga=attack>0 ? exp(-1/(sr*attack)) : 0;gr=release>0 ? exp(-1/(sr*release)) : 0;
 threshold_amp=10^(threshold/20);close_amp=10^((threshold-hysteresis)/20);
 slope=1/max(1,ratio);xL=threshold-knee;
 xH=threshold+sqrt(2)*knee*cos(atan(slope));yH=threshold+slope*(xH-threshold);
 ratio>1 && knee>0 ? (xC=(yH-2*xL+ratio*xH)/(ratio-1);yC=2*xL-xC;
 radius2=(yC-xL)^2+(xC-xL)^2;);
);
i=0;written=0;invalid=0;input_peak=0;
mode==2 ? (
 loop(count,
  ch=0;loop(channels,
   x=input[i*channels+ch];!(abs(x)<=1000000) ? (invalid=1;x=0;);
   input_peak=max(input_peak,abs(x));
   lo=min(lo,x);hi=max(hi,x);energy+=x*x;ch+=1;
  );energy_n+=1;
  sample_index>=next_emit ? (
   row=output+written*6;row[0]=sample_index/sr;row[1]=0;row[2]=0;row[3]=lo;row[4]=hi;
   row[5]=sqrt(energy/max(1,energy_n*channels));written+=1;next_emit+=interval;
   lo=0;hi=0;energy=0;energy_n=0;
  );sample_index+=1;i+=1;
 );
) : (loop(count,
 t=sample_index/sr;u=i/up_step;ui=floor(u);mix=u-ui;
 gain=(upstream[ui]+(upstream[ui+1]-upstream[ui])*mix)*input_gain;
 power=0;ch=0;
 loop(channels,
  x=input[i*channels+ch];
  x*=gain;lp<19999 ? x=filter(x,coef,states+ch*4);
  hp>1 ? x=filter(x,coef+8,states+ch*4+2);
  power+=x*x;ch+=1;
 );
 power/=channels;
 sum=max(0,sum+power-ring[rpos]);ring[rpos]=power;rpos=(rpos+1)%rms_size;
 rms=sqrt(sum/rms_size);
 mode ? (
  rms>=threshold_amp ? (opened=1;holdleft=hold_samples;) : (
   rms>=close_amp && opened ? holdleft=hold_samples : (
    holdleft>0 ? holdleft-=1 : opened=0;
   );
  );
  target=opened ? 0 : range;
  gate_db=target+(target<gate_db ? ga : gr)*(gate_db-target);
 ) : follower=rms+(rms>follower ? ga : gr)*(follower-rms);
 // окно Env interval: среднее огибающей за окно, а не мгновенное значение в точке выборки.
 // Иначе выборка «попадает» в пульсацию огибающей с частотой основного тона, и мелкий сдвиг интервала резко меняет кривую.
 acc+=mode ? rms : follower;acc_n+=1;
 sample_index>=next_emit ? (
  n_=max(1,acc_n);level=20*log10(max(0.000000000001,acc/n_));t=(sample_index-(n_-1)*.5)/sr;acc=0;acc_n=0; // время — середина окна
  mode ? db=gate_db : (
  db=0;
  ratio>1 ? (
   knee<=0 ? db=max(0,(1-slope)*(level-threshold)) : (
    level>=xH ? db=(1-slope)*(level-threshold) : level>xL ?
      db=level-yC-sqrt(max(0,radius2-(level-xC)^2));
   );
  );
  db-=makeup;
  );
  row=output+written*6;row[0]=t;row[1]=db;row[2]=level;row[3]=lo;row[4]=hi;
  row[5]=sqrt(energy/max(1,energy_n));written+=1;next_emit+=interval;
  lo=0;hi=0;energy=0;energy_n=0;
 );
 sample_index+=1;i+=1;
));
]]
function M.new(im,ctx,r)
 local self=setmetatable({im=im,r=r},M)
 local ok,why=pcall(function()
  self.fn=im.CreateFunctionFromEEL(M.code);im.Attach(ctx,self.fn)
  for k,v in pairs({input=0,upstream=65536,output=100000,states=170000,coef=170100,ring=180000}) do im.Function_SetValue(self.fn,k,v) end
  self.transfer_fn=im.CreateFunctionFromEEL(M.transfer_code);im.Attach(ctx,self.transfer_fn)
  im.Function_SetValue(self.transfer_fn,'input',0);im.Function_SetValue(self.transfer_fn,'output',8192)
  self.gate_fn=im.CreateFunctionFromEEL(M.gate_code);im.Attach(ctx,self.gate_fn)
  im.Function_SetValue(self.gate_fn,'input',0);im.Function_SetValue(self.gate_fn,'output',8192)
 end)
 if not ok then self.fn=nil;self.reason=tostring(why) end
 return self
end
function M:transfer(levels,cfg,job)
 local points={};local im,fn=self.im,self.transfer_fn
 for first=1,#levels,4096 do
  local count=math.min(4096,#levels-first+1);local input={}
  for i=first,first+count-1 do input[#input+1]=levels[i].db end
  local values=job:call(function()
   for k,v in pairs({count=count,threshold=cfg.compressor_threshold,ratio=cfg.compressor_ratio,knee=cfg.compressor_knee,makeup=cfg.compressor_gain})do im.Function_SetValue(fn,k,v) end
   im.Function_SetValue_Array(fn,'input',self.r.new_array(input));im.Function_Execute(fn)
   local out=self.r.new_array(count);im.Function_GetValue_Array(fn,'output',out);return out.table()
  end)
  for i,v in ipairs(values)do points[#points+1]={t=levels[first+i-1].t,db=v} end
  job:checkpoint()
 end
 return points
end
function M:gate(levels,cfg,job)
 local points={};local im,fn=self.im,self.gate_fn
 local dt=levels[2] and levels[2].t-levels[1].t or .0005
 local every=math.max(1,math.floor(cfg.gate_interval_ms/1000/dt+.5))
 for first=1,#levels,4096 do
  local count=math.min(4096,#levels-first+1);local input={}
  for i=first,first+count-1 do input[#input+1]=levels[i].db end
  local values=job:call(function()
   for k,v in pairs({count=count,reset=first==1 and 1 or 0,dt=dt,threshold=cfg.gate_threshold,hysteresis=cfg.gate_hysteresis,
    range=cfg.gate_range,hold_steps=math.floor(cfg.gate_hold_ms/1000/dt+.5),attack=cfg.gate_attack_ms/1000,release=cfg.gate_release_ms/1000})do im.Function_SetValue(fn,k,v)end
   im.Function_SetValue_Array(fn,'input',self.r.new_array(input));im.Function_Execute(fn)
   local out=self.r.new_array(count);im.Function_GetValue_Array(fn,'output',out);return out.table()
  end)
  for i,v in ipairs(values)do local index=first+i-1
   if (index-1)%every==0 or index==#levels then points[#points+1]={t=levels[index].t,db=v}end
  end
  job:checkpoint()
 end
 return points
end
function M:run(buffer,n,ch,sr,cfg,mode,up,up_step,reset)
 assert(self.fn,'Dynamics EEL engine unavailable: '..tostring(self.reason))
 local im,fn=self.im,self.fn;local p=mode..'_'
 local vars={count=n,channels=ch,sr=sr,reset=reset and 1 or 0,mode=cfg.capture_wave and 2 or mode=='gate' and 1 or 0,
  rms_size=math.max(1,math.floor(sr*(cfg[p..'rms_ms'] or 5)/1000+.5)),
  threshold=cfg[p..'threshold'],ratio=cfg.compressor_ratio,knee=cfg.compressor_knee,makeup=cfg.compressor_gain,
  attack=cfg[p..'attack_ms']/1000,release=cfg[p..'release_ms']/1000,
  range=cfg.gate_range,hysteresis=cfg.gate_hysteresis,hold_samples=math.floor(sr*cfg.gate_hold_ms/1000),
  hp=cfg[p..'hp'],lp=cfg[p..'lp'],interval=math.max(1,math.floor(sr*cfg[p..'interval_ms']/1000+.5)),
  input_gain=cfg.input_gain or 1,up_step=up_step}
 assert(n*ch<=65536 and #up<=32768 and vars.rms_size<=384000,'Dynamics block exceeds memory bounds')
 for k,v in pairs(vars) do im.Function_SetValue(fn,k,v) end
 im.Function_SetValue_Array(fn,'input',buffer);im.Function_SetValue_Array(fn,'upstream',self.r.new_array(up))
 im.Function_Execute(fn)
 assert(im.Function_GetValue(fn,'invalid')==0,'Invalid PCM sample in dynamics analysis')
 local count=im.Function_GetValue(fn,'written');assert(count>=0 and count<=11000,'Invalid EEL output count')
 local peak=im.Function_GetValue(fn,'input_peak')
 if count==0 then return {},peak end
 local out=self.r.new_array(count*6);im.Function_GetValue_Array(fn,'output',out);return out.table(),peak
end
return M
