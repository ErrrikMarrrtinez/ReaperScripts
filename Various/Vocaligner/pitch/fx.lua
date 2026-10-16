-- @noindex
local import=...;local Curve=import('pitch/curve');local Store=import('pitch/store');local Envelope=import('envelope');local Algorithm=import('pitch/algorithm');local M={}
function M.find(r,take,guid)
  if not guid then return nil end
  for i=0,r.TakeFX_GetCount(take)-1 do if r.TakeFX_GetFXGUID(take,i)==guid then return i end end
end
local function number(s) return tonumber((s or ''):gsub(',','.'):match('[+-]?%d+%.?%d*')) end
function M.mapping(r,take,fx,param)
  local values={}
  for _,n in ipairs({0,.25,.5,.75,1}) do
    local ok,text=r.TakeFX_FormatParamValueNormalized(take,fx,param,n,'')
    local value=ok and number(text) or nil
    assert(value,'ReaPitch did not expose its semitone mapping');values[#values+1]=value
  end
  local lo,hi=values[1],values[5];assert(hi>lo and lo<=-12 and hi>=12,'Unsupported ReaPitch range')
  for i,v in ipairs(values) do assert(math.abs(v-(lo+(hi-lo)*(i-1)/4))<.011,'Nonlinear ReaPitch range is not supported') end
  assert(math.abs(values[3])<.011,'ReaPitch center is not zero')
  return {lo=lo,hi=hi}
end
function M.fingerprint(r,take,fx,static)
  local parts={tostring(r.TakeFX_GetEnabled(take,fx)),tostring(r.TakeFX_GetOffline(take,fx))}
  for p=0,r.TakeFX_GetNumParams(take,fx)-1 do
    if p~=3 and p~=7 then parts[#parts+1]=string.format('%d=%.9g',p,r.TakeFX_GetParamNormalized(take,fx,p)) end
    local env=r.TakeFX_GetEnvelope(take,fx,p,false)
    if env and not (static and (p==3 or p==7)) then
      if r.CountAutomationItems then assert(r.CountAutomationItems(env)==0,'Pitch does not own automation items') end
      local ok,chunk=r.GetEnvelopeStateChunk(env,'',false);assert(ok,'Cannot inspect Pitch envelope')
      parts[#parts+1]=p..':'..(chunk:match('\nACT ([^\r\n]+)') or '')
      for i=0,r.CountEnvelopePoints(env)-1 do
        local valid,t,v,shape,tension=r.GetEnvelopePoint(env,i);assert(valid,'Cannot inspect Pitch point')
        parts[#parts+1]=string.format('%.9g,%.9g,%d,%.9g',t,v,shape,tension)
      end
    end
  end
  return Store.hash(table.concat(parts,'|'))
end
function M.envelopes(r,take,fx)
  local result={}
  for _,p in ipairs({3,7}) do
    local env=r.TakeFX_GetEnvelope(take,fx,p,false)
    if env then
      local ok,chunk=r.GetEnvelopeStateChunk(env,'',false);assert(ok,'Cannot read Pitch envelope')
      local points={};for i=0,r.CountEnvelopePoints(env)-1 do
        local yes,t,v,shape,tension=r.GetEnvelopePoint(env,i);assert(yes,'Cannot read Pitch point')
        points[#points+1]={t=t,v=v,shape=shape,tension=tension}
      end
      result[p]={chunk=chunk,points=points}
    end
  end
  return result
end
function M.owned(r,s,state)
  local fx=M.find(r,s.take,state.fx_guid)
  if not fx and state.fx_guid and state.geometry.guid~=s.guid then
    for i=0,r.TakeFX_GetCount(s.take)-1 do
      local ok,name=r.TakeFX_GetFXName(s.take,i,'')
      if ok and name=='Vocaligner Pitch' then if fx then return nil,'Ambiguous copied Pitch FX' end;fx=i end
    end
  end
  return fx
end
function M.rebind(r,s,state)
  if not state.fx_guid then return true end
  local fx,reason=M.owned(r,s,state);local old=state.geometry
  if reason then return nil,reason end
  if not fx then return nil,'The editor ReaPitch was removed. Analyze again or Reset its saved corrections.' end
  state.bypassed=not r.TakeFX_GetEnabled(s.take,fx)
  local info=Algorithm.read(r,s.take,fx)
  -- Native algorithm, wet/dry and bypass controls may be used independently.
  -- Only changed correction envelopes need an explicit recovery action.
  if info then state.algorithm=info.value end
  if M.fingerprint(r,s.take,fx)==state.fx_fingerprint then state.fx_guid=r.TakeFX_GetFXGUID(s.take,fx);return true end
  if state.fx_envelopes and r.TakeFX_GetNumParams(s.take,fx)==15 then
    local current=M.envelopes(r,s.take,fx);local shift=old.offset-s.offset;local same=true
    for _,p in ipairs({3,7}) do
      local a,b=state.fx_envelopes and state.fx_envelopes[p],current[p]
      if not a or not b or not Envelope.equivalent(Envelope.shift(a.chunk,shift),b.chunk,s.len*s.rate,
        Envelope.shift_points(a.points,shift),b.points) then same=false;break end
    end
    if same then state.fx_guid=r.TakeFX_GetFXGUID(s.take,fx);state.fx_fingerprint=M.fingerprint(r,s.take,fx);state.fx_static=M.fingerprint(r,s.take,fx,true);state.fx_envelopes=current;return true end
  end
  return nil,'Pitch automation changed outside the editor. Reanalyze to rebuild it, or Reset corrections.'
end
function M.ensure(r,s,state)
  local fx=M.find(r,s.take,state.fx_guid)
  if state.fx_guid then
    assert(fx,'The editor ReaPitch was removed. Analyze again or Reset before editing.')
    if state.fx_fingerprint then assert(M.fingerprint(r,s.take,fx)==state.fx_fingerprint,'ReaPitch was edited outside Pitch. Undo that change before applying.') end
    local info,why=Algorithm.read(r,s.take,fx)
    if state.algorithm~=nil then assert(info,why);assert(info.value==state.algorithm,'ReaPitch algorithm was changed outside Pitch') end
    if info then state.algorithm=info.value end
    return fx
  end
  fx=r.TakeFX_AddByName(s.take,'VST: ReaPitch (Cockos)',-1000)
  assert(fx and fx>=0,'Could not add the bundled VST ReaPitch to this take')
  -- AddByName has no visibility argument. Hide both windows in the same
  -- UI-suppressed transaction; never change the user's global FX preferences.
  r.TakeFX_Show(s.take,fx,2)
  r.TakeFX_Show(s.take,fx,0)
  assert(r.TakeFX_GetNumParams(s.take,fx)==15,'ReaPitch must start with one shifter; check its default preset')
  for index,name in pairs({[3]='1: Shift (full range)',[7]='1: Formant adjust (full range)'}) do
    local ok,label=r.TakeFX_GetParamName(s.take,fx,index,'');assert(ok and label==name,'Unexpected ReaPitch parameter: '..tostring(label))
  end
  for p,v in pairs({[0]=.5,[1]=0,[2]=1,[3]=.5,[4]=.5,[5]=.5,[6]=.5,[7]=.5,[8]=.5,[9]=.5,[10]=.5,[11]=.5,[12]=0,[13]=1,[14]=0}) do
    assert(r.TakeFX_SetParamNormalized(s.take,fx,p,v),'Could not initialize ReaPitch')
  end
  r.TakeFX_SetNamedConfigParm(s.take,fx,'renamed_name','Vocaligner Pitch')
  state.algorithm=state.algorithm or Algorithm.default(r)
  assert(state.algorithm,'No elastique Soloist algorithm is available; select a supported algorithm first')
  Algorithm.write(r,s.take,fx,state.algorithm)
  -- Initialization also writes the VST state. Recheck only the new effect's
  -- float before the enclosing synchronous transaction releases UI refresh.
  if r.TakeFX_GetFloatingWindow and r.TakeFX_GetFloatingWindow(s.take,fx)then r.TakeFX_Show(s.take,fx,2)end
  state.fx_guid=r.TakeFX_GetFXGUID(s.take,fx)
  return fx
end
local function envelope(r,s,fx,param,points,map)
  local env=r.TakeFX_GetEnvelope(s.take,fx,param,true);assert(env,'Cannot create the ReaPitch take envelope')
  local expected,old={},{}
  for _,p in ipairs(points) do
    local normalized=(p.value-map.lo)/(map.hi-map.lo)
    assert(normalized>=0 and normalized<=1,'Pitch correction is outside the ReaPitch range')
    expected[#expected+1]={t=p.t*s.rate,v=normalized,shape=0,tension=0}
  end
  for i=0,r.CountEnvelopePoints(env)-1 do
    local ok,t,v,shape,tension=r.GetEnvelopePoint(env,i);assert(ok,'Cannot inspect owned pitch automation')
    old[#old+1]={t=t,v=v,shape=shape,tension=tension}
  end
  local function same(a,b)return a and b and math.abs(a.t-b.t)<1e-9 and math.abs(a.v-b.v)<1e-10 and a.shape==b.shape and math.abs(a.tension-b.tension)<1e-9 end
  local first=1
  while same(old[first],expected[first])do first=first+1 end
  local oldlast,newlast=#old,#expected
  while oldlast>=first and newlast>=first and same(old[oldlast],expected[newlast])do oldlast=oldlast-1;newlast=newlast-1 end
  if first>#old and first>#expected then return {inserted=0,deleted=0,total=#expected} end
  local lower,upper=-1e12,1e12
  if first>1 then
    local first_time=math.min(old[first] and old[first].t or math.huge,expected[first] and expected[first].t or math.huge)
    lower=(expected[first-1].t+first_time)*.5
  end
  if newlast<#expected then
    local last_time=math.max(old[oldlast] and oldlast>=first and old[oldlast].t or -math.huge,expected[newlast] and newlast>=first and expected[newlast].t or -math.huge)
    upper=(last_time+expected[newlast+1].t)*.5
  end
  -- Boundaries lie between retained and changed knots, so the host's boundary
  -- inclusion convention cannot remove a retained knot. Ownership was checked
  -- by ensure(); the enclosing editor transaction holds the full item rollback.
  if oldlast>=first then assert(r.DeleteEnvelopePointRange(env,lower,upper),'Could not replace Pitch point range') end
  for i=first,newlast do local p=expected[i]
    assert(r.InsertEnvelopePoint(env,p.t,p.v,0,0,false,true),'Could not insert a ReaPitch point')
  end
  r.Envelope_SortPoints(env)
  assert(r.CountEnvelopePoints(env)==#expected,'Pitch write readback: wrong point count')
  for i,p in ipairs(expected)do
    local ok,t,v,shape,tension=r.GetEnvelopePoint(env,i-1)
    assert(ok and same(p,{t=t,v=v,shape=shape,tension=tension}),'Pitch write readback mismatch')
  end
  return {inserted=math.max(0,newlast-first+1),deleted=math.max(0,oldlast-first+1),total=#expected}
end
function M.apply(r,s,state,prepared)
  local fx=M.ensure(r,s,state)
  local pitch=M.mapping(r,s.take,fx,3);local formant=M.mapping(r,s.take,fx,7)
  local pitch_write=envelope(r,s,fx,3,prepared.pitch,pitch)
  local formant_write=envelope(r,s,fx,7,prepared.formant,formant)
  state.fx_fingerprint=M.fingerprint(r,s.take,fx)
  state.fx_static=M.fingerprint(r,s.take,fx,true);state.fx_envelopes=M.envelopes(r,s.take,fx)
  state.mapping={pitch=pitch,formant=formant}
  return {pitch=pitch_write,formant=formant_write}
end
function M.set_algorithm(r,s,state,previous)
  -- Only an existing owned FX is changed. An unedited item stores its choice
  -- as metadata until the first pitch/formant edit creates the effect.
  if not state.fx_guid then return end
  local fx=M.ensure(r,s,previous)
  Algorithm.write(r,s.take,fx,state.algorithm)
  state.fx_guid=previous.fx_guid
  state.fx_fingerprint=M.fingerprint(r,s.take,fx);state.fx_static=M.fingerprint(r,s.take,fx,true)
  state.fx_envelopes=M.envelopes(r,s.take,fx)
end
function M.remove(r,s,state)
  local fx,why=M.owned(r,s,state);assert(not why,why)
  if fx then r.TakeFX_Delete(s.take,fx) end
  state.fx_guid=nil;state.fx_fingerprint=nil;state.fx_static=nil;state.fx_envelopes=nil;state.mapping=nil
end
function M.adopt(r,s,state)
  local fx,why=M.owned(r,s,state);assert(not why,why)
  if not fx then M.remove(r,s,state);return false end
  assert(r.TakeFX_GetNumParams(s.take,fx)==15,'Reanalyze cannot rebuild a ReaPitch with extra shifters. Remove editor FX first.')
  state.fx_guid=r.TakeFX_GetFXGUID(s.take,fx)
  local info=Algorithm.read(r,s.take,fx);state.algorithm=info and info.value or nil
  state.bypassed=not r.TakeFX_GetEnabled(s.take,fx)
  state.fx_fingerprint=M.fingerprint(r,s.take,fx);state.fx_static=M.fingerprint(r,s.take,fx,true);state.fx_envelopes=M.envelopes(r,s.take,fx)
  return true
end
function M.prepare(notes,len,job,version,data,previous) return import('pitch/prepare').run(notes,len,job,version,data,previous) end
return M
