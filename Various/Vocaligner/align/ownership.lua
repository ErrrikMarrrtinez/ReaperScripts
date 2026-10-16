-- @noindex
local import=...;local U=import('align/util');local Audio=import('audio');local Warp=import('warp');local M={}
local fade_fields={'D_FADEINLEN','D_FADEOUTLEN','D_FADEINLEN_AUTO','D_FADEOUTLEN_AUTO','D_FADEINDIR','D_FADEOUTDIR','C_FADEINSHAPE','C_FADEOUTSHAPE'}
local function subtree(chunk,name)
  local out,depth=nil,0
  for line in (chunk..'\n'):gmatch('(.-)\r?\n')do
    local text=line:match('^%s*(.-)%s*$')
    if not out and (text=='<'..name or text:match('^<'..name..'%s'))then out={};depth=0 end
    if out then
      out[#out+1]=line
      if text:sub(1,1)=='<' then depth=depth+1 elseif text=='>'then depth=depth-1 end
      if depth==0 then return table.concat(out,'\n')end
    end
  end
  return ''
end
local function file_identity(r,source)
  local path=r.GetMediaSourceFileName and r.GetMediaSourceFileName(source) or ''
  if path==''then return {available=false,assumption='media content identity unavailable'}end
  local file=io.open(path,'rb');if not file then return {available=false,path=path,assumption='media file stat unavailable'}end
  local size=file:seek('end');local head,tail='',''
  if size then file:seek('set',0);head=file:read(math.min(size,256)) or '';file:seek('set',math.max(0,size-256));tail=file:read(256)or ''end
  file:close()
  return {available=true,path=path,size=size,edge_hash=U.hash(head..tail),assumption='file size and edge fingerprint; same-size interior replacement requires Refresh source'}
end
local function nonempty(r,env)
  return r.CountEnvelopePoints(env)>0 or r.CountAutomationItems and r.CountAutomationItems(env)>0
end
function M.inspect(r,s,is_dub)
  local needed={'CountTakes','CountTakeEnvelopes','GetTakeEnvelope','GetItemStateChunk','TakeFX_GetCount','TakeFX_GetNumParams','TakeFX_GetEnvelope'}
  for _,name in ipairs(needed)do if type(r[name])~='function'then return nil,U.error('unsupported_take_automation','The host cannot inspect '..name,'preflight')end end
  if s.composite then
    -- A grouped role owns each of its items; the key covers all of them.
    local parts,keys,warnings,bytes={},{},{},0
    for i,p in ipairs(s.parts)do
      local own,why=M.inspect(r,p,is_dub);if not own then return nil,why end
      parts[i]=own.extra;keys[i]=own.key;bytes=bytes+own.chunk_bytes
      for _,w in ipairs(own.warnings)do local seen=false;for _,x in ipairs(warnings)do seen=seen or x==w end;if not seen then warnings[#warnings+1]=w end end
    end
    local extra={schema=1,composite=true,parts=parts,channels=s.channels,file={available=true,assumption=parts[1].file.assumption}}
    return {extra=extra,key=table.concat(keys,'||'),warnings=warnings,chunk_bytes=bytes}
  end
  if r.CountTakes(s.item)~=1 then return nil,U.error('unsupported_source_mapping','Advanced currently supports items with one take: '..s.name,'preflight')end
  local parent=r.GetMediaSourceParent and r.GetMediaSourceParent(s.source)
  local section=r.PCM_Source_GetSectionInfo and r.PCM_Source_GetSectionInfo(s.source)
  if parent or section then return nil,U.error('unsupported_source_mapping','Section/reverse sources need a separate verified adapter','preflight')end
  local channels=r.GetMediaSourceNumChannels(s.source)
  if channels<1 or channels>8 then return nil,U.error('unsupported_source_mapping','Supported channel count is 1 to 8','preflight')end
  local yes,chunk=r.GetItemStateChunk(s.item,'',false)
  if not yes or type(chunk)~='string' or #chunk>16*1024*1024 then return nil,U.error('work_budget_exceeded','Cannot capture a bounded item rollback snapshot','preflight')end
  local _,pitch=r.GetSetMediaItemTakeInfo_String(s.take,'P_EXT:VocalignerPitch1','',false)
  if is_dub and pitch and pitch~=''then
    local ok,state=pcall(import('pitch/store').read,r,s.take)
    if not ok then return nil,U.error('owned_pitch_retime_unavailable','Saved Pitch state cannot be verified','preflight')end
    if state and state.fx_guid then return nil,U.error('owned_pitch_retime_unavailable','This take has Pitch corrections; moving their time is not supported yet','preflight')end
  end
  local volume=r.GetTakeEnvelopeByName(s.take,'Volume');local envelopes={}
  for i=0,r.CountTakeEnvelopes(s.take)-1 do
    local env=r.GetTakeEnvelope(s.take,i)
    if env~=volume then
      local ok,text=r.GetEnvelopeStateChunk(env,'',false)
      if not ok then return nil,U.error('unsupported_take_automation','Cannot inspect a take envelope','preflight')end
      if is_dub and nonempty(r,env)then return nil,U.error('unsupported_take_automation','Only the take Volume envelope can follow Advanced timing','preflight')end
      envelopes[#envelopes+1]=text
    elseif r.CountAutomationItems and r.CountAutomationItems(env)>0 then return nil,U.error('unsupported_take_automation','Automation items in take Volume are unsupported','preflight')end
  end
  local params=0
  for fx=0,r.TakeFX_GetCount(s.take)-1 do
    local n=r.TakeFX_GetNumParams(s.take,fx);params=params+n
    if params>8192 then return nil,U.error('work_budget_exceeded','Take FX inspection exceeds its parameter budget','preflight')end
    for param=0,n-1 do
      local env=r.TakeFX_GetEnvelope(s.take,fx,param,false)
      if env and is_dub and nonempty(r,env)then return nil,U.error('unsupported_take_automation','A take FX has time-dependent automation; its timing adapter is not available','preflight')end
    end
  end
  local fades={};for _,name in ipairs(fade_fields)do fades[name]=r.GetMediaItemInfo_Value(s.item,name)end
  local file=file_identity(r,s.source)
  local extra={schema=1,channels=channels,source_key=s.source_key,file=file,fades=fades,fx=subtree(chunk,'TAKEFX'),
    other_envelopes=envelopes,pitch_metadata=pitch or '',take_count=1}
  local warnings={}
  if not file.available then warnings[#warnings+1]=file.assumption end
  if r.GetMediaItemTrack and r.CountTrackEnvelopes and r.GetTrackEnvelope then
    local track=r.GetMediaItemTrack(s.item)
    for i=0,r.CountTrackEnvelopes(track)-1 do if nonempty(r,r.GetTrackEnvelope(track,i))then warnings[#warnings+1]='Track automation stays in project time.';break end end
  end
  return {extra=extra,key=U.key(extra),warnings=warnings,chunk_bytes=#chunk}
end
function M.check(r,s,owner,is_dub)
  local now,why=M.inspect(r,s,is_dub);if not now then return nil,why end
  if owner and owner.key~=now.key then return nil,U.error('source_changed','Source, fades, Pitch or take automation changed since capture: '..s.name,'preflight')end
  return now
end
local function fade_lengths(f,len)
  local fi=math.max(0,f.D_FADEINLEN or 0,f.D_FADEINLEN_AUTO or 0)
  local fo=math.max(0,f.D_FADEOUTLEN or 0,f.D_FADEOUTLEN_AUTO or 0)
  return math.min(fi,len),math.min(fo,len)
end
function M.fades(plan,owner)
  if plan.unchanged then return true end
  local s=plan.snapshot
  if s.composite then
    -- Each item's fades must move rigidly with that item's own edges.
    for k,p in ipairs(s.parts)do
      local fi,fo=fade_lengths(owner.extra.parts[k].fades,p.len);local a=p.pos-s.pos;local b=a+p.len
      local start,finish=Warp.target(plan,a),Warp.target(plan,b)
      local times={a,a+fi,b-fo,b}
      for _,q in ipairs(plan.dense or plan.markers)do if q.t>=a and q.t<=b then times[#times+1]=q.t end end
      for _,t in ipairs(times)do
        if fi>0 and t<=a+fi and math.abs(Warp.target(plan,t)-start-(t-a))>1e-6 then return nil,U.error('unsupported_source_mapping','The timing map deforms the fade-in of '..p.name,'preflight')end
        if fo>0 and t>=b-fo and math.abs(finish-Warp.target(plan,t)-(b-t))>1e-6 then return nil,U.error('unsupported_source_mapping','The timing map deforms the fade-out of '..p.name,'preflight')end
      end
    end
    return true
  end
  local f=owner.extra.fades
  local fi=math.max(0,f.D_FADEINLEN or 0,f.D_FADEINLEN_AUTO or 0)
  local fo=math.max(0,f.D_FADEOUTLEN or 0,f.D_FADEOUTLEN_AUTO or 0)
  local times={0,math.min(s.len,fi),math.max(0,s.len-fo),s.len}
  for _,p in ipairs(plan.dense or plan.markers)do times[#times+1]=p.t end
  for _,t in ipairs(times)do
    if fi>0 and t<=fi and math.abs(Warp.target(plan,t)-plan.pos-t)>1e-6 then return nil,U.error('unsupported_source_mapping','The timing map deforms the item fade-in','preflight')end
    if fo>0 and t>=s.len-fo and math.abs(plan.pos+plan.len-Warp.target(plan,t)-(s.len-t))>1e-6 then return nil,U.error('unsupported_source_mapping','The timing map deforms the item fade-out','preflight')end
  end
  return true
end
function M.acquire(app)
  if app.mutation_lease or app.cleaner.job or app.pitch.job then return nil,U.error('source_changed','Another tool is updating this session','preflight')end
  local lease={project=app.project};app.mutation_lease=lease;return lease
end
function M.release(app,lease) if app.mutation_lease==lease then app.mutation_lease=nil end end
return M
