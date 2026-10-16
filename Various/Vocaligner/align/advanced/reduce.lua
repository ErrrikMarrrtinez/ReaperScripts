-- @noindex
local import=...;local U=import('align/util');local Validate=import('align/advanced/validate');local M={}
function M.run(plan,cfg,budget)
  local points=plan.dense;local keep={[1]=true,[#points]=true};local boundaries={1};local composite=plan.snapshot and plan.snapshot.composite
  for i=2,#points-1 do if plan.problem.mandatory[i]then keep[i]=true;boundaries[#boundaries+1]=i end end
  boundaries[#boundaries+1]=#points
  local stack={};for i=2,#boundaries do stack[#stack+1]={boundaries[i-1],boundaries[i]}end
  while #stack>0 do
    local range=table.remove(stack);local a,b=points[range[1]],points[range[2]];local best,index=1,nil
    for i=range[1]+1,range[2]-1 do
      -- A grouped role restarts source time per item; its item edges are
      -- mandatory, so interpolating in virtual time is exact per item.
      local p=points[i];local target=composite and a.target+(b.target-a.target)*(p.t-a.t)/(b.t-a.t) or a.target+(b.target-a.target)*(p.source-a.source)/(b.source-a.source)
      local allowed=plan.problem.attack[i] and cfg.attack_error or cfg.map_error
      local error=math.abs(p.target-target)/allowed
      if error>best then best,index=error,i end
      budget:add('reduce',1);if i%128==0 then budget:checkpoint(nil,'Reducing timing markers')end
    end
    if index then keep[index]=true;stack[#stack+1]={range[1],index};stack[#stack+1]={index,range[2]}end
  end
  while true do
    local markers={};for i,p in ipairs(points)do if keep[i]then markers[#markers+1]=p end end
    if #markers>cfg.max_markers then return nil,U.error('render_budget_exceeded','Required timing knots exceed the marker budget','reduce')end
    plan.markers=markers
    local validation,why,indices=Validate.run(plan,cfg,budget)
    if validation then plan.validation=validation;return plan end
    local inserted=false
    for _,i in ipairs(indices or {})do if not keep[i]then keep[i]=true;inserted=true end end
    if not inserted then return nil,U.error('render_map_invalid',why,'validate')end
  end
end
return M
