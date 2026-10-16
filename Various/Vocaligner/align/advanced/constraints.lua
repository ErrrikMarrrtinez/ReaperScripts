-- @noindex
local import=...;local U=import('align/util');local Audio=import('audio');local M={}
local allowed={sync=true,soft_sync=true,protect_absolute=true,exclude_match=true}
function M.validate(list,snapshot,guide,cfg)
  local out,pins={},{}
  for index,c in ipairs(list or {})do
    if not allowed[c.kind]then return nil,U.error('constraints_conflict','Unsupported constraint '..tostring(c.kind),'constraints')end
    local a=U.copy(c);a.id=tostring(a.id or index)
    if a.kind=='sync' or a.kind=='soft_sync' then
      if not U.finite(a.dub_s) or not U.finite(a.guide_project_s) or a.dub_s<0 or a.dub_s>snapshot.len or a.guide_project_s<guide.pos or a.guide_project_s>guide.pos+guide.len then
        return nil,U.error('constraints_conflict','Pin '..a.id..' is outside the captured audio','constraints')
      end
      if a.guide_guid and guide.guid and a.guide_guid~=guide.guid then return nil,U.error('constraints_conflict','Pin belongs to another Guide','constraints')end
      if a.source_s and math.abs(a.source_s-Audio.source_time(snapshot,a.dub_s))>1e-6 then return nil,U.error('constraints_conflict','Pin source anchor changed','constraints')end
      if math.abs(a.guide_project_s-snapshot.pos-a.dub_s)>cfg.search_s+1e-9 then return nil,U.error('constraints_conflict','Pin '..a.id..' exceeds Search range','constraints')end
      if a.kind=='sync'then pins[#pins+1]=a end
    else
      if not U.finite(a.start_s) or not U.finite(a.end_s) or a.start_s<0 or a.end_s>snapshot.len or a.end_s<=a.start_s then
        return nil,U.error('constraints_conflict','Invalid protected/excluded interval '..a.id,'constraints')
      end
      if a.source_start_s and math.abs(a.source_start_s-Audio.source_time(snapshot,a.start_s))>1e-6 or a.source_end_s and math.abs(a.source_end_s-Audio.source_time(snapshot,a.end_s))>1e-6 then
        return nil,U.error('constraints_conflict','Interval source anchors changed','constraints')
      end
    end
    out[#out+1]=a
  end
  table.sort(pins,function(a,b)return a.dub_s==b.dub_s and a.id<b.id or a.dub_s<b.dub_s end)
  for i,p in ipairs(pins)do
    local prev=pins[i-1]
    if prev and (p.dub_s==prev.dub_s and math.abs(p.guide_project_s-prev.guide_project_s)>1e-6 or p.dub_s>prev.dub_s and p.guide_project_s<=prev.guide_project_s)then
      return nil,U.error('constraints_conflict','Pins '..prev.id..' and '..p.id..' contradict their time order','constraints')
    end
    for _,c in ipairs(out)do if c.kind=='protect_absolute' and p.dub_s>=c.start_s and p.dub_s<=c.end_s and math.abs((p.guide_project_s-snapshot.pos-p.dub_s)*cfg.strength/100)>1e-6 then
      return nil,U.error('constraints_conflict','Pin '..p.id..' conflicts with protection '..c.id,'constraints')
    end end
  end
  table.sort(out,function(a,b)return a.id<b.id end)
  return out
end
function M.inside(list,u,kind)
  for _,c in ipairs(list or {})do if c.kind==kind and u>=c.start_s-1e-9 and u<=c.end_s+1e-9 then return c end end
end
function M.compile(list,dub,ref,first,last)
  local hard={};for _,c in ipairs(list or {})do if c.kind=='sync'then hard[#hard+1]=c end end
  local function forbidden_pair(i,j)
    local a,b=dub.frames[i],ref.frames[j];if not a or not b then return true end
    if M.inside(list,a.t,'exclude_match')then return true end
    for _,p in ipairs(hard)do
      local target=p.guide_project_s-ref.pos
      if a.right<p.dub_s-1e-9 and b.t>target+.005 or a.left>p.dub_s+1e-9 and b.t<target-.005 then return true end
      if p.dub_s>=a.left and p.dub_s<a.right and math.abs(b.t-target)>.01500001 then return true end
    end
    return false
  end
  local function prefix(data,is_dub)
    local p={missing={[0]=0},active={[0]=0},blocked={[0]=0},mass={[0]=0},gap={[0]=0}}
    for i,f in ipairs(data.frames)do
      local blocked=false
      for _,c in ipairs(list or {})do
        if c.kind=='sync' then local t=is_dub and c.dub_s or c.guide_project_s-ref.pos;if t>=f.left and t<f.right then blocked=true end
        elseif is_dub and c.kind=='protect_absolute' then if c.start_s>=f.left and c.start_s<f.right or c.end_s>=f.left and c.end_s<f.right then blocked=true end end
      end
      p.missing[i]=p.missing[i-1]+(f.missing and 1 or 0);p.active[i]=p.active[i-1]+(f.background<.80 and 1 or 0)
      p.blocked[i]=p.blocked[i-1]+(blocked and 1 or 0);p.mass[i]=p.mass[i-1]+f.mass
    end
    return p
  end
  local dp,rp=prefix(dub,true),prefix(ref,false)
  local function gap(side,a,b,cfg,macro)
    local p=side=='dub' and dp or rp
    if a<1 or b<a or not p.mass[b]then return false end
    if p.missing[b]-p.missing[a-1]>0 or p.blocked[b]-p.blocked[a-1]>0 then return false end
    local duration=(p.mass[b]-p.mass[a-1])*.01
    local cap=macro and cfg.macro_gap_s or p.active[b]-p.active[a-1]>0 and cfg.active_gap_s or cfg.background_gap_s
    return duration<=cap+1e-8
  end
  return {pair_forbidden=forbidden_pair,gap_allowed=gap,dub=dp,ref=rp}
end
return M
