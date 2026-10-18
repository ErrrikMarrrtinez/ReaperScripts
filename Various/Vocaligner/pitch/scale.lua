-- @noindex
local M={}
M.roots={'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'}
M.scales={
  {'Chromatic',{0,1,2,3,4,5,6,7,8,9,10,11}},
  {'Major',{0,2,4,5,7,9,11}}, {'Minor',{0,2,3,5,7,8,10}},
  {'Harmonic minor',{0,2,3,5,7,8,11}}, {'Melodic minor',{0,2,3,5,7,9,11}},
  {'Dorian',{0,2,3,5,7,9,10}}, {'Phrygian',{0,1,3,5,7,8,10}},
  {'Lydian',{0,2,4,6,7,9,11}}, {'Mixolydian',{0,2,4,5,7,9,10}},
  {'Locrian',{0,1,3,5,6,8,10}}, {'Major pentatonic',{0,2,4,7,9}},
  {'Minor pentatonic',{0,3,5,7,10}}, {'Blues',{0,3,5,6,7,10}},
  {'Whole tone',{0,2,4,6,8,10}},
}
-- Короткие имена ладов и бемольная запись: бемоли, если мажорный аналог тональности — бемольный (F, Bb, Eb, Ab, Db).
M.short={'Chrom','Maj','Min','Harm min','Mel min','Dor','Phryg','Lyd','Mixo','Locr','Maj pent','Min pent','Blues','Whole'}
local FLAT_NAMES={'C','Db','D','Eb','E','F','Gb','G','Ab','A','Bb','B'}
local TO_MAJOR={0,0,3,3,3,-2,-4,-5,-7,-11,0,3,3,0} -- смещение от тоники лада к тонике относительного мажора
local FLAT_MAJOR={[1]=true,[3]=true,[5]=true,[8]=true,[10]=true}
function M.flat(root,scale) return FLAT_MAJOR[((root or 0)+(TO_MAJOR[scale or 1] or 0))%12]==true end
function M.root_name(root,scale) root=(root or 0)%12;return (M.flat(root,scale) and FLAT_NAMES or M.roots)[root+1] end
function M.label(root,scale) return M.root_name(root,scale)..' '..(M.short[scale or 1] or M.scales[scale or 1][1]) end
function M.contains(p,root,scale)
  local pc=(math.floor(p+.5)-(root or 0))%12
  for _,v in ipairs((M.scales[scale or 1] or M.scales[1])[2]) do if pc==v then return true end end
  return false
end
function M.nearest(p,root,scale,lo,hi)
  local best,distance=nil,math.huge
  for n=math.floor(p)-12,math.ceil(p)+12 do if M.contains(n,root,scale) and (not lo or n>=lo) and (not hi or n<=hi) then
    local d=math.abs(n-p);if d<distance-1e-9 or math.abs(d-distance)<1e-9 and n>best then best,distance=n,d end
  end end
  return best
end
function M.pitch(e,p,alt) return e.snap and not alt and M.nearest(p,e.root,e.scale) or p end
function M.center(n) return n.center+(n.visual_offset or 0)+(n.flat_offset or 0)*(n.flatten or 0) end
function M.shift(e,n,value,alt,step,original)
  value=math.max(-24,math.min(24,value));local center=M.center(n)
  if e.snap and not alt then value=M.nearest(center+value,e.root,e.scale,center-24,center+24)-center
  elseif step and not alt then original=original or n.shift or 0;value=original+math.floor(value-original+.5) end
  return math.max(-24,math.min(24,value))
end
function M.next(p,direction,root,scale)
  local n=direction>0 and math.floor(p+1e-6)+1 or math.ceil(p-1e-6)-1
  while not M.contains(n,root,scale) do n=n+direction end;return n
end
return M
