-- @noindex
-- Standalone Lua 5.4 check: no REAPER process, project or audio device needed.
local import=...
if type(import)~='function' then
  local directory=assert(debug.getinfo(1,'S').source:match('^@(.+[/\\])'))
  local cache={}
  import=function(name)
    if not cache[name] then cache[name]=assert(loadfile(directory..'../../'..name..'.lua'))(import) end
    return cache[name]
  end
end
local N,C,E,L,T,S=import('pitch/notes'),import('pitch/curve'),import('pitch/expression'),import('pitch/link'),import('pitch/trace'),import('pitch/store')
local function near(a,b,eps)assert(math.abs(a-b)<(eps or 1e-8),a..' != '..b)end
local d={len=2,hop=.016,frames={}}
for i=0,124 do local t=i*.016;d.frames[#d.frames+1]={t=t,pitch=60+2*t+.6*math.sin(t*2*math.pi*12),confidence=.6,level_db=-45}end
-- A reliable quiet vowel must reach its requested target at full Flatten.
local flat={id=1,start=0,finish=2,center=62,shift=0,formant=0,flatten=1,transition=.08,anchors={}}
local legacy=C.evaluator({N.copy(flat)},'shift',4,d);local old_error=0
for i=100,1800 do local t=i/1000;old_error=math.max(old_error,math.abs(T.sample(d,t)+legacy(t)-62))end
assert(old_error>.1,'Saved expression behavior unexpectedly changed')
E.edit(flat);local flatten=C.evaluator({flat},'shift',4,d)
for i=100,1800 do local t=i/1000;near(T.sample(d,t)+flatten(t),62)end
local original=N.copy(flat);flat.expression_version=nil
assert(not N.same_curve(original,flat),'New expression policy did not invalidate the preparation cache')
flat=original
local text=S.encode({version=1,curve_version=4,notes={flat},geometry={}})
local loaded=S.read({GetSetMediaItemTakeInfo_String=function()return true,text end},{})
assert(loaded.notes[1].expression_version==2)
local unsafe=N.copy(d);for i=58,67 do unsafe.frames[i].confidence=.1 end
unsafe.frames[30].pitch=90;unsafe._trace=nil;unsafe._trend=nil;unsafe._trust=nil
near(E.extra(flat,.96,unsafe,0),0);near(E.extra(flat,29*.016,unsafe,0),0)
local ns={{id=1,start=.1,finish=1,center=61,shift=.2,formant=.4,transition=.08,anchors={}},
 {id=2,start=1,finish=1.9,center=63,shift=-.1,formant=-.3,transition=.08,anchors={}}}
local before=N.copy(ns);local old=C.evaluator(before,'shift',4,d)
local l=L.edit_tilt(ns[1],ns[2],d);assert(l.version==7);l.width=.3;l.amount=1
local after=C.evaluator(ns,'shift',4,d)
local prep=L.prepare_pair(ns[1],ns[2],d,function(_,t)return old(t)end)
local maxerr=0
for k=math.ceil((prep.lo+prep.fade)*10000),math.floor((prep.hi-prep.fade)*10000)do
 local t=k/10000;local target=prep.left+(prep.right-prep.left)*(t-prep.reflo)/(prep.refhi-prep.reflo)
 maxerr=math.max(maxerr,math.abs(T.sample(d,t)+after(t)-target))
end
assert(maxerr<1e-9,'Transition retains between-knot modulation')
local formant0=C.evaluator(before,'formant',4,d);local formant1=C.evaluator(ns,'formant',4,d)
for i=0,2000 do near(formant0(i*.001),formant1(i*.001))end
for _,t in ipairs({prep.lo,prep.hi})do
 near(after(t),old(t));local h=1e-6
 near((after(t+h)-old(t+h)-after(t)+old(t))/h,0,.001)
end
local points=C.points(ns,d.len,'shift',nil,4,d);local j,worst=1,0
for k=0,19999 do local t=k/10000
 while j<#points-1 and points[j+1].t<t do j=j+1 end
 local a,b=points[j],points[j+1];local v=a.value+(b.value-a.value)*(t-a.t)/(b.t-a.t)
 worst=math.max(worst,math.abs(v-after(t)))
end
assert(worst<.004,'Envelope mismatch '..worst)
-- Amount zero, half, split/join, trim and persistence use the same evaluator.
local reference={};for i=0,2000 do reference[i]=after(i/1000)end
l.amount=.5;local half=C.evaluator(ns,'shift',4,d)
for i=0,2000 do near(half(i/1000),old(i/1000)+(reference[i]-old(i/1000))*.5)end
l.amount=0;local zero=C.evaluator(ns,'shift',4,d)
for i=0,2000 do near(zero(i/1000),old(i/1000))end
l.amount=1
local split=N.copy(ns);assert(N.split(split,2,1.5,d,function(t)return T.sample(d,t)+after(t)end))
local sc=C.evaluator(split,'shift',4,d)
for i=0,1999 do near(sc(i/1000),reference[i])end
assert(N.join(split,2))
local geom={render_key='x',source_key='y',offset=0,len=2,rate=1};local trim=N.copy(geom);trim.offset=.2;trim.len=1.6
local part,mapped=S.adapt(d,ns,geom,trim);local tc=C.evaluator(mapped,'shift',4,part)
for i=100,1499 do local t=i/1000;near(tc(t),after(t+.2),1e-7)end
local state={version=1,curve_version=4,notes=ns,geometry={}};local text=S.encode(state)
local read=S.read({GetSetMediaItemTakeInfo_String=function()return true,text end},{})
assert(read.notes[2].link.version==7)
-- A hole has no fabricated F0 and no transition correction.
for i=59,68 do d.frames[i].confidence=0 end;d._trace=nil;d._link_windows=nil
local base=C.evaluator(before,'shift',4,d);local withgap=C.evaluator(ns,'shift',4,d)
for i=940,1050 do local t=i/1000;near(withgap(t),base(t));assert(T.sample(d,t)==nil)end
-- A steady glide must remain unchanged.
for _,f in ipairs(d.frames)do f.pitch=60+2*f.t;f.confidence=.99 end
d._trace=nil;d._link_windows=nil;ns[1].shift=0;ns[2].shift=0
local glide=C.evaluator(ns,'shift',4,d)
for i=0,1999 do near(glide(i/1000),0,1e-9)end
print(string.format('Pitch quality: Flatten, voiced gaps, transitions, envelope %.4f ct, persistence, Split/Join and trim passed',worst*100))
return {transition_target_max_cents=maxerr*100,envelope_max_cents=worst*100,envelope_points=#points}
