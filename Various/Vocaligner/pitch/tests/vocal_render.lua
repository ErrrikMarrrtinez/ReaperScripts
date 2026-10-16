-- @noindex
-- Lua-only host contract tests. DSP is additionally exercised in a real WDL VM
-- with generated and recorded WAVs by the research benchmark.
local import=...
if type(import)~='function' then
  local directory=assert(debug.getinfo(1,'S').source:match('^@(.+[/\\])'));local cache={}
  import=function(name)if not cache[name]then cache[name]=assert(loadfile(directory..'../../'..name..'.lua'))(import)end;return cache[name]end
end
local R=import('pitch/vocal_render');local S=import('pitch/store');local N=import('pitch/notes');local A=import('pitch/analysis')
local s={project={},item={},take={},source={},guid='original',name='voice',channels=1,len=1,source_rate=48000,source_overrun=0,
  rate=1,D_PITCH=0,markers={},I_CHANMODE=0,D_VOL=1}
local state={version=1,geometry={},notes={{id=1,start=0,finish=1,center=60,shift=1,formant=0}},fx_guid='ours'}
local saved=S.encode(state);local attached,active,balanced,takes,restored=0,nil,0,0,false
local r={
  GetMediaItemInfo_Value=function()return 0 end,
  GetTakeEnvelopeByName=function()end,TakeFX_GetCount=function()return 1 end,TakeFX_GetEnabled=function()return true end,
  TakeFX_GetFXGUID=function()return 'ours'end,TakeFX_GetFXName=function()return true,'ReaPitch'end,
  PCM_Source_GetSectionInfo=function()return false end,
  GetSetMediaItemTakeInfo_String=function(take,key,text,write)
    if key=='GUID' then return true,'new-guid'end
    if key==S.key then return true,saved end
    return true,''
  end,
  GetItemStateChunk=function()return true,'original chunk'end,
  SetItemStateChunk=function(_,text)assert(text=='original chunk');restored=true;takes=0;return true end,
  PCM_Source_CreateFromFile=function(path)return {path=path}end,
  PCM_Source_Destroy=function()end,
  Undo_BeginBlock2=function()balanced=balanced+1 end,Undo_EndBlock2=function()balanced=balanced-1 end,
  PreventUIRefresh=function(v)balanced=balanced+v end,UpdateArrange=function()end,
  AddTakeToMediaItem=function()takes=takes+1;return {}end,
  GetMediaItemTake_Source=function()end,
  SetMediaItemTake_Source=function()attached=attached+1;return true end,
  SetMediaItemTakeInfo_Value=function()return true end,
  GetMediaItemTakeInfo_Value=function(_,key)return key=='D_PANLAW'and -1 or .2 end,
  SetActiveTake=function(take)active=take end
}
local job={resources={},call=function(_,fn,...)return fn(...)end,checkpoint=function()end}
R.validate(r,s,state)
for _,change in ipairs({{channels=2},{rate=2},{D_PITCH=1},{D_VOL=.5},{I_CHANMODE=1},{source_rate=16000},{len=61},{markers={{pos=0}}},{source_overrun=.1}})do
  local changed=N.copy(s);for k,v in pairs(change)do changed[k]=v end
  assert(not pcall(R.validate,r,changed,state),'Unsupported source was accepted')
end
local changed=N.copy(state);changed.notes[1].formant=1;assert(not pcall(R.validate,r,s,changed))
local original_check=A.check;A.check=function()return s end
R.insert(r,s,state,saved,'test.wav',job)
assert(takes==1 and attached==1 and active and balanced==0 and not restored)
-- Insertion failures roll back the item and balance both native scopes.
restored=false;r.SetMediaItemTakeInfo_Value=function()return false end
assert(not pcall(R.insert,r,s,state,saved,'test.wav',job))
assert(restored and takes==0 and balanced==0)
local attempts=attached;saved='changed'
assert(not pcall(R.insert,r,s,state,'old saved text','test.wav',job));assert(attached==attempts)
A.check=original_check
local data={len=1,hop=.016,frames={}}
for i=0,62 do data.frames[#data.frames+1]={t=i*.016,pitch=60,confidence=.99,level_db=-20}end
local guide,target=R.controls(data,state)
assert(#guide==63 and #target==201)
assert(math.abs(target[101].hz-440*2^((61-69)/12))<1e-8)
for i=20,30 do data.frames[i].confidence=0 end;data._trace=nil
guide,target=R.controls(data,state)
assert(not guide[25].voiced and target[78].q==0,'Unknown pitch was not protected')
print('Vocal render: source guards, target, protected gaps, atomic insertion, rollback and stale-state checks passed')
return true
