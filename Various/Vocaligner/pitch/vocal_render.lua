-- @noindex
local import=...;local Analysis=import('pitch/analysis');local Store=import('pitch/store');local Curve=import('pitch/curve')
local Trace=import('pitch/trace');local PSOLA=import('pitch/psola');local FX=import('pitch/fx');local M={}
M.key='P_EXT:VocalignerVocalRender1'
local function call(job,fn,...)return job:call(fn,...)end
function M.origin(r,take)
  local ok,text=r.GetSetMediaItemTakeInfo_String(take,M.key,'',false)
  if not ok or text=='' then return end
  local valid,value=pcall(Store.decode,text)
  if valid and type(value)=='table' and value.version==1 and type(value.source_guid)=='string' then return value.source_guid end
end
function M.find_source(r,item,guid)
  for i=0,r.CountTakes(item)-1 do
    local take=r.GetTake(item,i);local _,id=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
    if id==guid then return take end
  end
end
function M.validate(r,s,state)
  assert(r.GetMediaItemInfo_Value(s.item,'B_ALLTAKESPLAY')==0,'Disable Play all takes before creating a vocal render take.')
  assert(s.channels==1,'Experimental vocal render currently supports mono takes.')
  assert(s.len<=60 and s.len*s.source_rate<=2880000,'Vocal render: use a section of up to 60 seconds (30 seconds at 96 kHz).')
  assert(s.source_rate>=32000 and s.source_rate<=96000 and s.source_rate%1==0,'Vocal render supports 32–96 kHz sources.')
  assert(math.abs(s.rate-1)<1e-9 and math.abs(s.D_PITCH or 0)<1e-9 and #(s.markers or {})==0,
    'Vocal render needs rate 1, no take pitch and no stretch markers. Glue a copy first.')
  assert((s.I_CHANMODE or 0)==0,'Vocal render needs the normal take channel mode.')
  assert(math.abs((s.D_VOL or 1)-1)<1e-9,'Vocal render needs unity take volume; item and track volume are supported.')
  assert(s.source_overrun<=2/s.source_rate,'Vocal render does not support repeated source loops.')
  local source=s.source
  if r.PCM_Source_GetSectionInfo then
    local section=r.PCM_Source_GetSectionInfo(source)
    assert(not section,'Vocal render does not yet support reverse/section sources. Glue a copy first.')
  end
  for _,n in ipairs(state.notes)do assert(math.abs(n.formant or 0)<1e-9,'Vocal render preserves source formants; explicit Formant edits are not supported yet.')end
  for _,name in ipairs({'Volume','Pan','Pitch','Mute'})do
    local env=r.GetTakeEnvelopeByName(s.take,name)
    if env then
      local ok,chunk=r.GetEnvelopeStateChunk(env,'',false)
      assert(ok and not chunk:match('\nACT 1'), 'Vocal render does not bake the active take '..name..' envelope. Render or bypass it first.')
    end
  end
  for fx=0,r.TakeFX_GetCount(s.take)-1 do
    if r.TakeFX_GetEnabled(s.take,fx) and r.TakeFX_GetFXGUID(s.take,fx)~=state.fx_guid then
      local _,name=r.TakeFX_GetFXName(s.take,fx,'')
      assert(name and name:find('Vocaligner Pitch Meter',1,true),'Vocal render handles Pitch alone. Bypass other take FX before rendering.')
    end
  end
  if state.fx_guid and state.fx_fingerprint then
    local probe={};for k,v in pairs(state)do probe[k]=v end
    local owned,why=FX.rebind(r,s,probe);assert(owned,why)
  end
end
function M.controls(data,state,job)
  local guide,target={},{};local hop=data.hop or .016
  local evaluate=Curve.evaluator(state.notes,'shift',state.curve_version or 1,data)
  for i=0,math.floor(data.len/hop)do
    local t=i*hop;local raw,_,confidence=Trace.detail(data,t);local hz=raw and 440*2^((raw-69)/12)or 220
    guide[#guide+1]={t=t,hz=hz,voiced=raw~=nil and confidence>=.5 and hz>65 and hz<900}
  end
  for i=0,math.ceil(data.len/.005)do
    local t=math.min(data.len,i*.005);local raw=Trace.sample(data,t);local q=evaluate(t)
    assert(math.abs(q)<=12.000001,'Experimental vocal render supports corrections within one octave.')
    target[#target+1]={t=t,hz=raw and 440*2^((raw+q-69)/12)or 220,q=raw and q or 0}
    if job and i%128==0 then job:checkpoint(nil,'Vocal render: preparing target')end
  end
  return guide,target
end
function M.read(r,s,job)
  local aa=call(job,r.CreateTakeAudioAccessor,s.take);assert(aa,'Cannot read the vocal source.')
  job.resources[aa]=r.DestroyAudioAccessor
  local origin,finish=call(job,r.GetAudioAccessorStartTime,aa),call(job,r.GetAudioAccessorEndTime,aa)
  assert(math.abs(origin)<1e-6 and math.abs(finish-s.len)<2/s.source_rate,'Unsupported vocal accessor timing.')
  local count=math.floor(s.len*s.source_rate+.5);local pcm={};local block=16384
  local buffer=call(job,r.new_array,block)
  for first=0,count-1,block do
    local size=math.min(block,count-first)
    local values=call(job,function()
      assert(not r.AudioAccessorStateChanged(aa),'Source changed during vocal render.')
      local current,why=Analysis.check(r,s);assert(current,why)
      buffer.clear();local status=r.GetAudioAccessorSamples(aa,s.source_rate,1,first/s.source_rate,size,buffer)
      assert(type(status)=='number' and status>=0,'Could not read vocal source samples.')
      return buffer.table(1,size)
    end)
    for _,v in ipairs(values)do assert(v==v and math.abs(v)<100,'Invalid vocal source samples.');pcm[#pcm+1]=v end
    job:checkpoint((first+size)/count,'Vocal render: reading source')
  end
  call(job,r.DestroyAudioAccessor,aa);job.resources[aa]=nil
  return pcm
end
function M.write(path,pcm,sr,job)
  local tmp=path..'.part';local exists=io.open(path,'rb');if exists then exists:close();error('Vocal render file already exists.',0)end
  local file=assert(io.open(tmp,'wb'),'Cannot create vocal render WAV.')
  job.resources[file]=function(f)pcall(f.close,f);os.remove(tmp)end
  -- IEEE float keeps the original gain and headroom, without clipping or dither.
  local bytes=#pcm*4
  assert(file:write('RIFF'..string.pack('<I4',48+bytes)..'WAVEfmt '..string.pack('<I4I2I2I4I4I2I2',16,3,1,sr,sr*4,4,32)
    ..'fact'..string.pack('<I4I4',4,#pcm)..'data'..string.pack('<I4',bytes)))
  for first=1,#pcm,4096 do
    local parts={};for i=first,math.min(first+4095,#pcm)do parts[#parts+1]=string.pack('<f',pcm[i])end
    assert(file:write(table.concat(parts)),'Could not write vocal render WAV.')
    job:checkpoint(math.min(1,(first+4095)/#pcm),'Vocal render: saving audio')
  end
  assert(file:close());job.resources[file]=nil
  local ok,why=os.rename(tmp,path);if not ok then os.remove(tmp);error('Cannot finish vocal render WAV: '..tostring(why),0)end
end
function M.insert(r,s,state,saved,path,job)
  return call(job,function()
    local current,why=Analysis.check(r,s);assert(current,why)
    local _,text=Store.read(r,s.take);assert(text==saved,'Pitch edits changed during vocal render.')
    M.validate(r,current,state)
    local ok,chunk=r.GetItemStateChunk(s.item,'',false);assert(ok,'Cannot snapshot the original vocal item.')
    local source=assert(r.PCM_Source_CreateFromFile(path),'Cannot open the rendered vocal WAV.')
    local attached=false;local rendered_guid
    r.Undo_BeginBlock2(s.project);r.PreventUIRefresh(1)
    local success,err=xpcall(function()
      local take=assert(r.AddTakeToMediaItem(s.item),'Cannot add a vocal render take.')
      local old=r.GetMediaItemTake_Source(take)
      assert(r.SetMediaItemTake_Source(take,source),'Cannot attach the vocal render WAV.');attached=true
      if old and old~=source then r.PCM_Source_Destroy(old)end
      for key,value in pairs({D_STARTOFFS=0,D_PLAYRATE=1,D_PITCH=0,D_VOL=1,I_CHANMODE=0})do assert(r.SetMediaItemTakeInfo_Value(take,key,value),'Cannot set rendered take '..key)end
      -- Pan belongs to playback, not to the analysis/renderer signal.
      for _,key in ipairs({'D_PAN','D_PANLAW'})do assert(r.SetMediaItemTakeInfo_Value(take,key,r.GetMediaItemTakeInfo_Value(s.take,key)),'Cannot preserve take pan.')end
      assert(r.GetSetMediaItemTakeInfo_String(take,'P_NAME',s.name..' · Vocal render',true),'Cannot name the vocal take.')
      assert(r.GetSetMediaItemTakeInfo_String(take,M.key,Store.encode({version=1,source_guid=s.guid}),true),'Cannot identify the original vocal take.')
      local yes,guid=r.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
      assert(yes and guid~='','Cannot identify the rendered vocal take.');rendered_guid=guid
      r.SetActiveTake(take)
    end,debug.traceback)
    if not success then
      local restored,value=pcall(r.SetItemStateChunk,s.item,chunk,false)
      if not restored or not value then job.keep_render=true;err=tostring(err)..'\nRollback failed; use REAPER Undo.'end
      if not attached then r.PCM_Source_Destroy(source)end
    end
    r.PreventUIRefresh(-1);r.Undo_EndBlock2(s.project,'Vocaligner: render vocal to new take',-1);r.UpdateArrange()
    assert(success,err)
    job.committed=true
    return rendered_guid
  end)
end
function M.run(e,im,ctx,job)
  local r,s,state,saved=e.r,e.snapshot,e.state,e.saved_text
  call(job,M.validate,r,s,state)
  local guide,target=M.controls(e.data,state,job:scope(0,.05))
  local pcm=M.read(r,s,job:scope(.05,.2))
  local engine=call(job,PSOLA.new,im,ctx,r);job.resources[engine]=function(v)v:close()end
  local output,stats=engine:render(pcm,s.source_rate,guide,target,job:scope(.2,.85))
  assert(stats.edited_regions>0,'There are no pitch corrections to render.')
  assert(stats.changed_samples>0,'No reliable periodic voice was found in the edited regions.')
  local directory=call(job,r.GetProjectPathEx,s.project)
  if not directory or directory=='' then directory=r.GetResourcePath()..'/Data'end
  local folder=directory..'/Vocaligner Renders'
  call(job,r.RecursiveCreateDirectory,folder,0)
  local suffix=r.genGuid():gsub('[^%w]','')
  local path=folder..'/Vocal-'..os.date('%Y%m%d-%H%M%S')..'-'..suffix..'.wav'
  M.write(path,output,s.source_rate,job:scope(.85,.98))
  job.resources[path]=function(name)if not job.committed and not job.keep_render then os.remove(name)end end
  stats.rendered_guid=M.insert(r,s,state,saved,path,job)
  job.resources[path]=nil
  stats.source_guid=s.guid;stats.path=path;stats.sample_rate=s.source_rate;stats.samples=#output
  return stats
end
return M
