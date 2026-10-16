-- @noindex
-- Experimental offline, pitch-synchronous overlap-add. No external runtime.
-- Source periods are aligned by normalized waveform correlation, using the
-- existing F0 only as a search prior. One native call handles one pulse/grain.
local M={};M.__index=M
M.version=1
M.max_samples=1048576
M.code=[[
function read_sample(at) local(i,u) (
  i=floor(at);u=at-i;
  i>=0 && i+1<count ? pcm[i]*(1-u)+pcm[i+1]*u : 0;
);
mode==0 ? (
  memset(sum,0,count);memset(weight,0,count);
) : mode==1 ? (
  best=-1;at=first;loop(last-first+1,
    abs(pcm[at])>best ? (best=abs(pcm[at]);result[0]=at;);at+=1;
  );
) : mode==2 ? (
  size=2*half+1;i=0;mean=0;
  loop(size,reference[i]=read_sample(current+i-half);mean+=reference[i];i+=1;);
  mean/=size;energy=0;i=0;
  loop(size,reference[i]-=mean;energy+=reference[i]^2;i+=1;);
  best=-2;best_at=first;at=first;
  loop(last-first+1,
    dot=0;sx=0;ss=0;i=0;
    loop(size,v=pcm[at-half+i];dot+=reference[i]*v;sx+=v;ss+=v*v;i+=1;);
    c=dot/sqrt(max(0.00000000000000000001,(ss-sx*sx/size)*energy));correlations[at-first]=c;
    c>best ? (best=c;best_at=at;);at+=1;
  );
  sub=0;k=best_at-first;
  best_at>first && best_at<last ? (
    a=correlations[k-1];b=correlations[k];c=correlations[k+1];den=a-2*b+c;
    den<0 ? sub=max(-0.5,min(0.5,0.5*(a-c)/den));
  );
  result[0]=best_at+sub;result[1]=best;
) : mode==3 ? (
  at=max(0,ceil(destination-period));last=min(count-1,floor(destination+period));
  loop(max(0,last-at+1),u=at-destination;w=0.5+0.5*cos($pi*u/period);
    sum[at]+=read_sample(source+u)*w;weight[at]+=w;at+=1;
  );
) : mode==4 ? (
  // Normalize the mean overlap density, not every sample. Pointwise division
  // removes the amplitude pattern which establishes a lower fundamental.
  a=normalization_first;b=a;density=0;i=0;
  loop(count,
    center=max(normalization_first,min(normalization_last,i));
    limit=min(normalization_last+1,center+normalization+1);
    while(b<limit)(density+=weight[b];b+=1;);
    limit=max(normalization_first,center-normalization);
    while(a<limit)(density-=weight[a];a+=1;);
    average=density/max(1,b-a);
    sum[i]=average>0.000001 ? sum[i]/average : pcm[i];i+=1;
  );
);
]]
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function invoke(job,fn,...)if job then return job:call(fn,...)end;return fn(...)end
local function checkpoint(job,progress,label)if job then job:checkpoint(progress,label)end end
local function at(points,t,key)
  local a,b=1,#points
  if t<=points[1].t then return points[1][key]end
  if t>=points[b].t then return points[b][key]end
  while b-a>1 do local m=(a+b)//2;if points[m].t<=t then a=m else b=m end end
  local x,y=points[a],points[b];local u=(t-x.t)/(y.t-x.t)
  return x[key]+(y[key]-x[key])*u
end
M.sample=at
function M.new(im,ctx,r)
  assert(im and im.CreateFunctionFromEEL,'Vocal render requires ReaImGui with EEL support.')
  local self=setmetatable({im=im,ctx=ctx,r=r},M)
  self.fn=im.CreateFunctionFromEEL(M.code);assert(self.fn,'Cannot compile the vocal renderer.')
  im.Attach(ctx,self.fn)
  self.result=r.new_array(2)
  for key,value in pairs({pcm=0,sum=1048576,weight=2097152,reference=3145728,correlations=3149824,result=3153920})do im.Function_SetValue(self.fn,key,value)end
  return self
end
function M:close()
  if self.fn and self.im.Detach then self.im.Detach(self.ctx,self.fn)end;self.fn=nil
end
function M:execute(mode,values,read,job)
  return invoke(job,function()
    local im,fn=self.im,self.fn
    for k,v in pairs(values or {})do im.Function_SetValue(fn,k,v)end
    im.Function_SetValue(fn,'mode',mode);im.Function_Execute(fn)
    if read then im.Function_GetValue_Array(fn,'result',self.result);return self.result[1],self.result[2]end
  end)
end
function M:upload(samples,job)
  assert(#samples<=M.max_samples,'A continuous voiced region is too long for vocal render. Split the item at a pause.')
  invoke(job,function()
    self.im.Function_SetValue(self.fn,'count',#samples)
    self.im.Function_SetValue_Array(self.fn,'pcm',self.r.new_array(samples))
  end)
end
local function regions(guide)
  local out,first={},nil
  for i=1,#guide+1 do local f=guide[i]
    if f and f.voiced then first=first or i
    elseif first then
      if i-first>=4 then
        local hop=guide[i-1].t-guide[i-2].t
        out[#out+1]={lo=guide[first].t,hi=guide[i-1].t+hop*.5}
      end;first=nil
    end
  end
  return out
end
local function edit_regions(target)
  local out,first={},nil
  for i=1,#target+1 do local f=target[i]
    if f and math.abs(f.q)>1e-6 then first=first or f.t
    elseif first then
      local lo,hi=first-.025,target[i-1].t+.025;local last=out[#out]
      if last and lo<=last.hi then last.hi=hi else out[#out+1]={lo=lo,hi=hi}end;first=nil
    end
  end
  return out
end
local function gate(edits,t)
  for _,v in ipairs(edits)do
    if t<v.lo then return 0 end
    if t<=v.hi then return clamp(math.min(t-v.lo,v.hi-t)/.025,0,1)end
  end
  return 0
end
function M:render(pcm,sr,guide,target,job)
  assert(sr>=32000 and sr<=96000 and sr%1==0,'Vocal render supports sample rates from 32 to 96 kHz.')
  assert(#guide>1 and #target>1,'Vocal render requires an existing Pitch analysis.')
  local output={};for i,v in ipairs(pcm)do output[i]=v;if i%8192==0 then checkpoint(job,nil,'Vocal render: preparing audio')end end
  local spans=regions(guide);local edits=edit_regions(target)
  local stats={version=M.version,regions=0,source_pulses=0,output_pulses=0,changed_samples=0,edited_regions=#edits}
  for index,span in ipairs(spans)do
    local needed=false;for _,v in ipairs(edits)do if v.hi>span.lo and v.lo<span.hi then needed=true;break end end
    if needed then
      -- Integer source sample coordinates; interpolation happens only within a
      -- grain. Never resample or time-stretch the item itself.
      local first=math.max(0,math.floor((span.lo-.04)*sr));local last=math.min(#pcm-1,math.ceil((span.hi+.04)*sr))
      local samples={};for i=first,last do samples[#samples+1]=pcm[i+1];if i%8192==0 then checkpoint(job)end end
      self:upload(samples,job)
      local lo,hi=span.lo*sr-first,span.hi*sr-first;local mid=(lo+hi)*.5
      local period=sr/at(guide,(mid+first)/sr,'hz')
      local center=self:execute(1,{first=math.max(0,math.floor(mid-period*.5)),last=math.min(#samples-1,math.floor(mid+period*.5))},true,job)
      local left,right={},{}
      for _,direction in ipairs({-1,1})do
        local current=center;local found=direction<0 and left or right
        local limit=math.ceil((hi-lo)/sr*1000)+4
        for _=1,limit do
          period=sr/at(guide,(current+first)/sr,'hz');local half=math.floor(period*.5)
          local expected=current+direction*period;local a,b=math.floor(expected-period*.25),math.floor(expected+period*.25)
          if a-half<0 or b+half>=#samples then break end
          local next,correlation=self:execute(2,{current=current,half=half,first=a,last=b},true,job)
          if correlation<.5 or next<lo or next>hi or (next-current)*direction<period*.5 then break end
          found[#found+1]=next;current=next
          checkpoint(job,nil,'Vocal render: aligning voice periods')
        end
      end
      local pulses={};for i=#left,1,-1 do pulses[#pulses+1]=left[i]end;pulses[#pulses+1]=center
      for _,p in ipairs(right)do pulses[#pulses+1]=p end
      if #pulses>4 then
        stats.regions=stats.regions+1;stats.source_pulses=stats.source_pulses+#pulses
        self:execute(0,nil,false,job)
        local destination=pulses[1];local cursor=2;local last_destination=destination
        while destination<pulses[#pulses]do
          while cursor<#pulses-1 and math.abs(pulses[cursor+1]-destination)<math.abs(pulses[cursor]-destination)do cursor=cursor+1 end
          local source=pulses[cursor];period=math.max(source-pulses[cursor-1],pulses[cursor+1]-source)
          self:execute(3,{destination=destination,source=source,period=period},false,job)
          last_destination=destination
          local hz=at(target,(destination+first)/sr,'hz');assert(hz>=45 and hz<=2100,'Target pitch is outside the vocal render range.')
          destination=destination+sr/hz;stats.output_pulses=stats.output_pulses+1
          checkpoint(job,nil,'Vocal render: synthesizing voice periods')
        end
        self:execute(4,{normalization=math.floor(sr*.02),normalization_first=math.ceil(pulses[1]),normalization_last=math.floor(last_destination)},false,job)
        local result=invoke(job,function()
          local buffer=self.r.new_array(#samples);self.im.Function_GetValue_Array(self.fn,'sum',buffer);return buffer.table()
        end)
        local start_time,finish_time=(pulses[1]+first)/sr,(pulses[#pulses]+first)/sr
        for i,value in ipairs(result)do
          local t=(first+i-1)/sr
          local gain=gate(edits,t)*clamp(math.min(t-start_time,finish_time-t)/.01,0,1)
          if gain>0 then
            assert(value==value and math.abs(value)<100,'Invalid vocal render output.')
            local at_sample=first+i;output[at_sample]=pcm[at_sample]+(value-pcm[at_sample])*gain
            stats.changed_samples=stats.changed_samples+1
          end
          if i%4096==0 then checkpoint(job)end
        end
      end
    end
    checkpoint(job,index/#spans,'Vocal render')
  end
  return output,stats
end
return M
