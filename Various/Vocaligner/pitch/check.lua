-- @noindex
-- Check: measured pitch from "JS: Vocaligner Pitch Meter", drawn beside the
-- prediction. The editor links only to an instance in the edited take's FX
-- chain or on the edited item's track, and only shows frames that the meter
-- stamped with this item's current state (take, geometry and saved edits).
local import=...;local Store=import('pitch/store');local FX=import('pitch/fx');local M={}
local NAME,NS='Vocaligner Pitch Meter','VocalignerPitchMeter'
local MAGIC,REG,REGSZ,NSLOT,DATA=5263437,64,64,8,1024
local F={id=0,hb=1,trk=3,flg=4,cpos=5,hop=6,org=7,cap=8,ver=9,ppos=10,pst=12,on=13,ctxgen=15,a4=20,offs=21,front=26,passes=29,jver=30,ready=32,capon=33}
local YELLOW,STALE,AMBIG=0xFFD54AE6,0xFFD54A50,0xE0A04A70

local function attach(r)
  if not r.gmem_attach then return false end
  r.gmem_attach(NS);return r.gmem_read(0)==MAGIC
end
local function read(r,i)return r.gmem_read(i)end

-- Item identity and audible state. Any commit changes the saved state text.
function M.gen(e)
  local s=e.snapshot;if not s then return 0 end
  local key=table.concat({s.guid or '',string.format('%.9f|%.9f|%.9f|%.9f',s.pos or 0,s.len or 0,s.offset or 0,s.rate or 1),e.saved_text or ''},'|')
  return tonumber(Store.hash(key),16)%2147483646+1
end

local function instance_id(get_name,get,count)
  for p=0,count-1 do
    local ok,name=get_name(p)
    if ok and name and name:find('Instance ID',1,true) then return math.floor((get(p) or 0)+.5) end
  end
end
local function scan(r,e)
  local s,state=e.snapshot,e.state;local found={}
  local reapitch=state and state.fx_guid and FX.find(r,s.take,state.fx_guid)
  for i=0,r.TakeFX_GetCount(s.take)-1 do
    local ok,name=r.TakeFX_GetFXName(s.take,i,'')
    if ok and name:find(NAME,1,true) then
      found[#found+1]={kind='take',index=i,enabled=r.TakeFX_GetEnabled(s.take,i),
        offline=r.TakeFX_GetOffline and r.TakeFX_GetOffline(s.take,i) or false,before=reapitch~=nil and i<reapitch,
        id=instance_id(function(p)return r.TakeFX_GetParamName(s.take,i,p,'')end,function(p)return r.TakeFX_GetParam(s.take,i,p)end,r.TakeFX_GetNumParams(s.take,i))}
    end
  end
  local track=r.GetMediaItem_Track(s.item)
  for i=0,(track and r.TrackFX_GetCount(track) or 0)-1 do
    local ok,name=r.TrackFX_GetFXName(track,i,'')
    if ok and name:find(NAME,1,true) then
      found[#found+1]={kind='track',index=i,enabled=r.TrackFX_GetEnabled(track,i),
        offline=r.TrackFX_GetOffline and r.TrackFX_GetOffline(track,i) or false,before=false,
        id=instance_id(function(p)return r.TrackFX_GetParamName(track,i,p,'')end,function(p)return r.TrackFX_GetParam(track,i,p)end,r.TrackFX_GetNumParams(track,i))}
    end
  end
  -- Prefer an active take FX after ReaPitch, then an active track FX.
  local best,score
  for _,c in ipairs(found)do
    local v=(c.enabled and not c.offline and 4 or 0)+(c.kind=='take' and 2 or 0)+(c.before and 0 or 1)
    if not best or v>score then best,score=c,v end
  end
  -- Other audible items under the edited one make a track FX measurement ambiguous.
  local overlaps={}
  if best and best.kind=='track' and track then
    local a,b=s.pos,s.pos+s.len
    for j=0,r.CountTrackMediaItems(track)-1 do
      local item=r.GetTrackMediaItem(track,j)
      if item~=s.item then
        local p=r.GetMediaItemInfo_Value(item,'D_POSITION');local q=p+r.GetMediaItemInfo_Value(item,'D_LENGTH')
        local muted=r.GetMediaItemInfo_Value(item,'B_MUTE_ACTUAL')~=0 or r.GetMediaItemInfo_Value(item,'B_MUTE')~=0
        local lane=r.GetMediaItemInfo_Value(item,'C_LANEPLAYS')
        if not muted and lane~=0 and q>a and p<b then overlaps[#overlaps+1]={math.max(p,a)-s.pos,math.min(q,b)-s.pos} end
      end
    end
  end
  return best,#found,overlaps
end

local function slot_of(r,id)
  if not id or id<1 then return nil end
  for e=0,NSLOT-1 do if read(r,REG+e*REGSZ+F.id)==id then return e end end
end

-- Track FX publish project time; take FX publish source time, including the
-- take start offset. Do not infer this from the UI playback cursor: take FX
-- may run ahead of it. The 20261005-145512 case proved a 5.900643 s mislabel.
local function to_host(c,s,T)
  if c.mode=='item' then return T-s.pos end
  if c.mode=='source' then return (T-s.pos)*s.rate+s.offset end
  return T
end
local function to_project(c,s,J)
  if c.mode=='item' then return J+s.pos end
  if c.mode=='source' then return (J-s.offset)/s.rate+s.pos end
  return J
end

function M.tick(e)
  local r,now=e.r,e.r.time_precise();local c=e.check or {};e.check=c
  local s=e.snapshot
  if not s then c.status='Select an analyzed item.';c.ok=false;return c end
  if not r.gmem_attach then c.status='This REAPER has no gmem API.';c.ok=false;return c end
  local alive=attach(r)
  if not c.scan_at or now>=c.scan_at or c.item~=s.item then
    c.scan_at=now+.5;c.item=s.item
    local best,count,overlaps=scan(r,e);c.inst=best;c.count=count;c.overlaps=overlaps
    if best then c.mode_id=best.id;c.mode=best.kind=='take' and 'source' or 'project' end
  end
  local inst=c.inst
  if not inst then c.ok=false;c.status='Add "JS: Vocaligner Pitch Meter" after ReaPitch in this take (or as first track FX).';return c end
  if not inst.enabled or inst.offline then c.ok=false;c.status='The Pitch Meter on this '..inst.kind..' is bypassed or offline.';return c end
  if not alive then c.ok=false;c.status='Pitch Meter is loading. Open its window once if this persists.';return c end
  local slot=slot_of(r,inst.id)
  if not slot then c.ok=false;c.status='Pitch Meter has no shared-memory slot yet (8 linked meters max).';return c end
  local eb=REG+slot*REGSZ;c.slot=slot;c.eb=eb
  -- Liveness from heartbeat changes, independent of the two clocks.
  local hb=read(r,eb+F.hb)
  if hb~=c.hb then c.hb=hb;c.hb_seen=now end
  c.alive=c.hb_seen and now-c.hb_seen<3
  local gen=M.gen(e);c.gen=gen
  if read(r,eb+F.ctxgen)~=gen then r.gmem_write(eb+F.ctxgen,gen) end
  c.hop=read(r,eb+F.hop);c.org=read(r,eb+F.org);c.cap=read(r,eb+F.cap);c.ver=read(r,eb+F.ver)
  c.a4=read(r,eb+F.a4);c.jsfx_version=read(r,eb+F.jver);c.capon=read(r,eb+F.capon)~=0;c.on=read(r,eb+F.on)~=0
  c.base=DATA+slot*3*c.cap
  c.ok=c.alive and c.hop>0 and c.cap>0
  if not c.alive then c.status='Pitch Meter is not running (REAPER 6.44+ keeps it alive with its window closed).'
  elseif not c.on then c.status='Pitch Meter analysis is Off.'
  elseif inst.before then c.status='Pitch Meter is BEFORE ReaPitch: it measures the source, not the result.'
  else c.status=nil end
  return c
end

-- Visible measured points in item time, cached by data version and view.
function M.points(e,t0,span,width)
  local c=e.check;local r=e.r;local s=e.snapshot
  if not (c and c.ok and c.org and c.org>=0 and s) then return {} end
  local mode=c.mode or 'project'
  local key=table.concat({c.ver,c.gen,c.slot,mode,t0,span,width,c.org},'|')
  if c.cache_key==key then return c.cache end
  local j0,j1=to_host(c,s,s.pos+math.max(0,t0)),to_host(c,s,s.pos+math.min(s.len,t0+span))
  if j1<j0 then j0,j1=j1,j0 end
  local i0=math.max(0,math.floor(j0/c.hop)-c.org-1);local i1=math.min(c.cap-1,math.ceil(j1/c.hop)-c.org+1)
  local stride=math.max(1,math.floor((i1-i0+1)/(width*1.5)))
  local shift=12*math.log((c.a4>0 and c.a4 or 440)/440,2)
  local pts={}
  for i=i0,i1,stride do
    local m=read(r,c.base+i);local g=read(r,c.base+2*c.cap+i)
    local t=to_project(c,s,(c.org+i)*c.hop)-s.pos
    if t>=0 and t<=s.len then
      if m>0 then
        local gen=g>=0 and g or -g-1
        local p={t=t,pitch=m+shift,current=gen==c.gen,provisional=g<0,conf=read(r,c.base+c.cap+i)}
        for _,o in ipairs(c.overlaps or {})do if t>=o[1] and t<=o[2] then p.ambiguous=true;break end end
        pts[#pts+1]=p
      else pts[#pts+1]={t=t} end
    end
  end
  c.cache_key=key;c.cache=pts;c.stats_due=true
  return pts
end

-- Measured minus predicted over the visible range (current, final frames).
local function predicted(display,t)
  local lo,hi=1,#display;if hi<2 then return end
  while hi-lo>1 do local mid=(lo+hi)//2;if display[mid].t<=t then lo=mid else hi=mid end end
  local a,b=display[lo],display[hi]
  if not (a.pitch and b.pitch and a.run and a.run==b.run and t>=a.t and t<=b.t) then return end
  return a.pitch+(b.pitch-a.pitch)*(t-a.t)/math.max(1e-9,b.t-a.t)
end
function M.stats(e,pts,display)
  local c=e.check;local now=e.r.time_precise()
  if not c or not display or (not c.stats_due and c.stats_at and now-c.stats_at<.5) then return c and c.stats end
  if c.stats_at and now-c.stats_at<.5 then return c.stats end
  c.stats_due=false;c.stats_at=now
  local function errors(shift)
    local out={}
    for _,p in ipairs(pts)do if p.pitch and p.current and not p.provisional and not p.ambiguous then
      local q=predicted(display,p.t+shift);if q then out[#out+1]=math.abs(p.pitch-q)*100 end
    end end
    table.sort(out);return out
  end
  local base=errors(0)
  if #base<20 then c.stats={n=#base};return c.stats end
  local function q(list,x)return list[math.max(1,math.min(#list,math.floor(#list*x+.5)))]end
  local st={n=#base,median=q(base,.5),p95=q(base,.95),seconds=#base*(c.hop or .005)}
  local best,lag=st.median,0
  for k=-12,12 do if k~=0 then local l=errors(k*.005);if #l>=#base*.8 then local m=q(l,.5);if m<best-1 then best,lag=m,k*.005 end end end end
  st.lag=lag;st.lag_median=best
  c.stats=st;return st
end

function M.draw(im,ctx,dl,e,v,tx,py,left,right,top,width,display)
  local c=M.tick(e)
  local pts=M.points(e,v.start,v.span,width)
  local prev
  for _,p in ipairs(pts)do
    if p.pitch and prev and prev.pitch and p.t-prev.t<.0151 then
      local col=(p.ambiguous or prev.ambiguous) and AMBIG or (p.current and prev.current) and (p.provisional and 0xFFE89AB0 or YELLOW) or STALE
      im.DrawList_AddLine(dl,tx(prev.t),py(prev.pitch),tx(p.t),py(p.pitch),col,(p.current and not p.ambiguous) and 1.7 or 1.1)
    end
    prev=p
  end
  local st=c.ok and M.stats(e,pts,display)
  local text
  if c.status then text='Check: '..c.status
  elseif st and st.median then
    text=string.format('Check: yellow measured / white target  median %.1f ct  p95 %.1f ct  (%.1f s)',st.median,st.p95,st.seconds)
    if st.lag~=0 then text=text..string.format('  · timing %+.0f ms fits better (%.1f ct)',st.lag*1000,st.lag_median) end
  elseif #pts>0 then text='Check: measured frames are from an older state or another item. Play this item again.'
  else text='Check: no measurement in view. Play this item.' end
  local stale=false;for _,p in ipairs(pts)do if p.pitch and not p.current then stale=true;break end end
  if stale and not c.status then text=text..'  · dim = before the last edit' end
  for _,o in ipairs(c.overlaps or {})do text=text..'  · other item audible on this track';break end
  local tw=im.CalcTextSize and im.CalcTextSize(ctx,text) or #text*7
  local x=math.max(left+4,right-tw-12)
  im.DrawList_AddRectFilled(dl,x-6,top+4,right-4,top+24,0x1A1C22D8,4)
  im.DrawList_AddText(dl,x,top+7,c.status and 0xF0B070FF or 0xFFD54AFF,text)
  return c
end

-- Every meter frame inside the item, for Export case. Read only.
function M.series(e)
  local c=M.tick(e);local s,r=e.snapshot,e.r;local inst=c.inst
  local out={found=inst~=nil,status=c.status or 'linked',kind=inst and inst.kind,index=inst and inst.index,id=inst and inst.id,
    before_reapitch=inst and inst.before,mode=c.mode or (inst and inst.kind=='take' and 'uncalibrated') or 'project',
    gen=c.gen,slot=c.slot,alive=c.alive,a4=c.a4,jsfx_version=c.jsfx_version,overlaps=c.overlaps,frames={}}
  if not (c.ok and c.org and c.org>=0 and s) then return out end
  local shift=12*math.log((c.a4>0 and c.a4 or 440)/440,2)
  local j0,j1=to_host(c,s,s.pos),to_host(c,s,s.pos+s.len);if j1<j0 then j0,j1=j1,j0 end
  local i0=math.max(0,math.floor(j0/c.hop)-c.org);local i1=math.min(c.cap-1,math.ceil(j1/c.hop)-c.org)
  for i=i0,i1 do
    local m=read(r,c.base+i)
    if m>=0 then
      local g=read(r,c.base+2*c.cap+i);local gen=g>=0 and g or -g-1
      local t=to_project(c,s,(c.org+i)*c.hop)-s.pos
      if t>=0 and t<=s.len then
        local f={t=t,midi=m>0 and m+shift or nil,conf=read(r,c.base+c.cap+i),current=gen==c.gen,provisional=g<0}
        for _,o in ipairs(c.overlaps or {})do if t>=o[1] and t<=o[2] then f.ambiguous=true;break end end
        out.frames[#out.frames+1]=f
      end
    end
  end
  return out
end
function M.report(e)
  local c=e.check;if not c then return 'Check: off' end
  local inst=c.inst
  return string.format('Check: %s | meter %s #%s id %s slot %s | mode %s | gen %s | alive %s | overlaps %d%s',
    c.status or 'linked',inst and inst.kind or 'none',inst and inst.index or '-',inst and inst.id or '-',c.slot or '-',c.mode or '?',
    c.gen or '-',tostring(c.alive),#(c.overlaps or {}),c.stats and c.stats.median and string.format(' | median %.1f ct p95 %.1f ct lag %+.0f ms',c.stats.median,c.stats.p95,(c.stats.lag or 0)*1000) or '')
end
return M
