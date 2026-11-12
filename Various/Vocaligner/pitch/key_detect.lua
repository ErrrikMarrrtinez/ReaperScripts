-- @noindex
-- Тональность по нотам Melodic-анализа (вокал): гистограмма высотных классов, взвешенная длительностью,
-- корреляция с профилями Крумхансла–Кесслера для 24 тональностей. Без чтения звука — мгновенно.
local M={}
local MAJOR={6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88}
local MINOR={6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17}
local function corr(h,p,root)
  local mh,mp=0,0;for i=1,12 do mh=mh+h[i];mp=mp+p[i] end;mh,mp=mh/12,mp/12
  local sxy,sxx,syy=0,0,0
  for i=0,11 do local x=h[(i+root)%12+1]-mh;local y=p[i+1]-mp;sxy=sxy+x*y;sxx=sxx+x*x;syy=syy+y*y end
  if sxx<=0 or syy<=0 then return 0 end
  return sxy/math.sqrt(sxx*syy)
end
-- lists: массив списков нот ({start,finish,center,shift}); corrected=true — по высоте после правок
function M.from_notes(lists,corrected)
  local h={0,0,0,0,0,0,0,0,0,0,0,0};local count,total=0,0
  for _,notes in ipairs(lists) do for _,n in ipairs(notes or {}) do
    local d=(n.finish or 0)-(n.start or 0)
    if n.center and d>=.06 then
      local p=n.center+(corrected and (n.shift or 0) or 0)
      local pc=math.floor(p+.5)%12;local frac=math.abs(p-math.floor(p+.5))
      -- длинные ноты весомее, но не линейно (одна долгая нота не перебивает всю мелодию); фальшивые (между полутонами) — слабее
      local w=math.sqrt(math.min(d,2))*(1-frac)
      h[pc+1]=h[pc+1]+w;count=count+1;total=total+d
    end
  end end
  if count<4 then return nil,'Not enough pitch notes' end
  local best,second
  for root=0,11 do for mode=0,1 do
    local s=corr(h,mode==0 and MAJOR or MINOR,root)
    local k={root=root,mode=mode,score=s}
    if not best or s>best.score then second=best;best=k elseif not second or s>second.score then second=k end
  end end
  best.notes=count;best.seconds=total;best.second=second
  return best
end
return M
