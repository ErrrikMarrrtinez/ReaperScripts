-- @noindex
-- ATune пачкой: те же настройки (скейл или реф, Speed, Transitions, Amount…) — на все выделенные проанализированные
-- айтемы на любых треках, кроме открытого (он уже применён обычной правкой) и айтемов самого реф-трека.
-- Для каждого айтема — свой слой Auto по его анализу и ручным правкам (заморозки уважаются) и своя запись ReaPitch;
-- одно действие Undo на айтем, сбой одного айтема откатывает только его.
local import=...;local Analysis=import('pitch/analysis');local Store=import('pitch/store');local Auto=import('pitch/auto')
local FX=import('pitch/fx');local Job=import('job');local M={}
local function copy(t)local out={};for k,v in pairs(t or {})do out[k]=v end;return out end
-- айтемы для пачки: выделенные аудио с Melodic-анализом, без открытого и без айтемов реф-трека
function M.targets(e,a)
  local r=e.r;local project=r.EnumProjects(-1);local out={}
  local ws=e.workspace
  if a.mode=='reference' and not a.ref_track then return out end
  for i=0,r.CountSelectedMediaItems(project)-1 do
    local item=r.GetSelectedMediaItem(project,i)
    local entry=ws and ws.by_item[item]
    if item~=e.item and entry and entry.state and entry.state.analysis then
      if not (a.mode=='reference' and entry.track and entry.track.guid==a.ref_track) then out[#out+1]=item end
    end
  end
  return out
end
local function apply_one(e,item,a,job,label)
  local r=e.r;local project=r.EnumProjects(-1)
  local s=job:call(Analysis.capture,r,project,item)
  local state,saved=job:call(Store.read,r,s.take);assert(state and state.analysis,'Analyze the item first: '..s.name)
  e.cache=e.cache or {};e.cache[project]=e.cache[project] or {}
  local cached=e.cache[project][state.analysis]
  if not cached then
    local data,geometry=Store.load_analysis(r,project,state.analysis,job);assert(data,'Saved analysis is missing: '..s.name)
    cached={data=data,geometry=geometry};e:remember(project,state.analysis,cached)
  end
  local data,why=Store.adapt(cached.data,{},cached.geometry,s);assert(data,why)
  local _,notes=Store.adapt({frames={},hop=data.hop,len=state.geometry.len,model=data.model},state.notes,state.geometry,s)
  assert(type(notes)=='table',notes)
  for _,n in ipairs(notes)do n.last=math.min(#data.frames,math.ceil(n.finish/data.hop)) end
  state.notes=notes;state.auto=copy(a);state.curve_version=4 -- как begin_edit у обычной правки
  -- слой Auto этого айтема: тональность проекта, реф-трек из общего workspace
  local ctx={r=r,project=project,item=item,data=data,snapshot=s,notes=notes,state=state,root=e.root,scale=e.scale,auto_mask=e.auto_mask,
    workspace=e.workspace,cache=e.cache,remember=function(_,...)return e:remember(...)end}
  local frozen=false;for _,n in ipairs(notes)do if n.auto_freeze then frozen=true;break end end
  data._frozen=frozen or nil;data._auto=nil
  local cfg=Auto.config(state)
  if cfg.on and (cfg.mode=='reference' or (e.scale or 1)>1) then
    local layer=job:call(Auto.build,ctx,cfg);assert(layer,'ATune could not be built for '..s.name)
    if layer.stats and layer.stats.error then error(layer.stats.error..': '..s.name,0) end
    layer.amount=math.max(0,math.min(1,(cfg.amount or 100)/100));data._auto=layer
  end
  job:checkpoint(nil,label)
  local prepared=FX.prepare(notes,s.len,job,state.curve_version,data,nil)
  job:call(function()
    local current,err=Analysis.check(r,s);assert(current,err)
    assert(Store.raw(r,s.take)==saved,'Pitch item changed before applying: '..s.name)
    local ok,chunk=r.GetItemStateChunk(item,'',false);assert(ok,'Cannot snapshot '..s.name)
    r.Undo_BeginBlock2(project);r.PreventUIRefresh(1)
    local success,failure=xpcall(function()
      FX.apply(r,s,state,prepared);state.geometry=Store.geometry(current);Store.write(r,s.take,state)
    end,debug.traceback)
    if not success and not r.SetItemStateChunk(item,chunk,false) then failure=failure..'\nRollback failed; use REAPER Undo.' end
    r.PreventUIRefresh(-1);r.Undo_EndBlock2(project,'Vocaligner: ATune on selected items',-1);r.UpdateArrange()
    assert(success,failure)
  end)
end
function M.start(e,items,a)
  if #items==0 or e:busy() then return false end
  e.job=Job.new(e.r,function(job)
    local done,failed=0,{}
    for i,item in ipairs(items) do
      local label=string.format('ATune %d / %d',i,#items)
      local ok,why=pcall(apply_one,e,item,a,job:scope((i-1)/#items,i/#items,label),label)
      if ok then done=done+1 else failed[#failed+1]=tostring(why);e.app:report('ATune: '..tostring(why)) end
    end
    job.auto_batch={done=done,failed=failed}
  end,.010)
  e.job.kind='apply';e.error=nil
  return true
end
return M
