-- @noindex
-- Горячие клавиши: реестр действий, настраиваемые привязки (Settings → Hotkeys), сохранение в ExtState.
-- Привязка = клавиша + модификаторы (Ctrl, Shift, Alt); значение 'none' — действие без клавиши.
-- Остальной код спрашивает не «нажата ли S», а «нажато ли действие split»: H.pressed(im,ctx,'split').
local M={}
local SECTION,KEY='Vocaligner ui','hotkeys'
-- id, группа, подпись, привязка по умолчанию; alt=true — Alt допустим как дополнительный модификатор (точная правка/относительная вставка)
M.ACTIONS={
  {'tool1','Tools','Tool: Edit','1'},{'tool2','Tools','Tool: Transition','2'},{'tool3','Tools','Tool: Modulation','3'},
  {'tool4','Tools','Tool: Curve','4'},{'tool5','Tools','Tool: Split','5'},{'tool6','Tools','Tool: Draw','6'},
  {'tool_drift','Tools','Tool: Drift','none'},{'tool_flatten','Tools','Tool: Flatten','none'},{'tool_vibrato','Tools','Tool: Vibrato','none'},
  {'tool_toggle','Tools','Toggle Edit / Curve','C'},{'split','Tools','Split the note at the cursor','S'},{'join','Tools','Join the note with the next one','J'},
  {'fit','View','Focus the note; again: fit everything','F'},{'cursor_start','View','Edit cursor to the start of the time selection / take','W'},
  {'clear','View','Clear time selection, then note selection','Escape'},
  {'select_all','Edit','Select all notes','Ctrl+A'},{'undo','Edit','Undo','Ctrl+Z'},{'redo','Edit','Redo','Ctrl+Shift+Z'},
  {'reset_notes','Edit','Reset selected notes','Delete'},{'copy_shape','Edit','Copy the curve shape','Ctrl+C'},
  {'paste_shape','Edit','Paste the curve shape (Alt: relative)','Ctrl+V',alt=true},
  {'nudge_up','Edit','Nudge selected notes up (Alt: fine)','Up',alt=true},{'nudge_down','Edit','Nudge selected notes down (Alt: fine)','Down',alt=true},
  {'deess_fit','De-ess','Fit the whole item','F'},{'deess_undo','De-ess','Undo manual edit','Ctrl+Z'},{'deess_redo','De-ess','Redo manual edit','Ctrl+Y'},
  {'play','Global','Play / stop','Space'},
}
local byid={};for _,a in ipairs(M.ACTIONS) do byid[a[1]]=a end
M.byid=byid
local MODS={Ctrl=1,Shift=2,Alt=4}
local ALIAS={Up='UpArrow',Down='DownArrow',Left='LeftArrow',Right='RightArrow'} -- имена ImGui
local function imkey(im,name) return im['Key_'..(ALIAS[name] or name)] end
M.imkey=imkey
local function parse(text)
  if not text or text=='' or text=='none' then return nil end
  local b={mods=0}
  for part in tostring(text):gmatch('[^+]+') do if MODS[part] then b.mods=b.mods|MODS[part] else b.key=part end end
  return b.key and b or nil
end
local function format(b)
  if not b then return 'none' end
  local t={};if b.mods&1~=0 then t[#t+1]='Ctrl' end;if b.mods&2~=0 then t[#t+1]='Shift' end;if b.mods&4~=0 then t[#t+1]='Alt' end
  t[#t+1]=b.key;return table.concat(t,'+')
end
M.format=format;M.parse=parse
local bindings -- id -> {key,mods} | false (нет клавиши)
local function load(r)
  bindings={}
  for _,a in ipairs(M.ACTIONS) do bindings[a[1]]=parse(a[4]) or false end
  local text=r and r.GetExtState and r.GetExtState(SECTION,KEY) or ''
  for id,v in tostring(text):gmatch('([%w_]+)=([^;]*)') do if byid[id] then bindings[id]=parse(v) or false end end
end
local function save(r)
  local parts={};for _,a in ipairs(M.ACTIONS) do
    local cur,def=format(bindings[a[1]] or nil),format(parse(a[4]))
    if cur~=def then parts[#parts+1]=a[1]..'='..cur end
  end
  r.SetExtState(SECTION,KEY,table.concat(parts,';'),true)
end
function M.init(r) if not bindings then load(r) end end
function M.get(r,id) M.init(r);return bindings[id] or nil end
function M.label(r,id) return format(M.get(r,id)) end
function M.is_default(r,id) return format(M.get(r,id))==format(parse(byid[id][4])) end
-- сколько клавиш пользователь поменял (для кнопки Reset all)
function M.changed(r) local n=0;for _,a in ipairs(M.ACTIONS) do if not M.is_default(r,a[1]) then n=n+1 end end;return n end
function M.set(r,id,b)
  M.init(r)
  if b then -- та же комбинация у другого действия той же группы: у него она снимается (две команды на одну клавишу не живут)
    for _,a in ipairs(M.ACTIONS) do
      local o=bindings[a[1]]
      if a[1]~=id and o and o.key==b.key and o.mods==b.mods and a[2]==byid[id][2] then bindings[a[1]]=false end
    end
  end
  bindings[id]=b or false;save(r)
end
function M.reset(r,id) if id then M.set(r,id,parse(byid[id][4])) else bindings=nil;r.SetExtState(SECTION,KEY,'',true);load(r) end end
-- нажато ли действие в этом кадре (точное совпадение модификаторов; Alt допустим сверх привязки у действий с alt=true)
function M.pressed(im,ctx,id)
  local r=reaper;M.init(r)
  local b=bindings[id];if not b then return false end
  local key=imkey(im,b.key);if not key or not im.IsKeyPressed(ctx,key,false) then return false end
  local m=im.GetKeyMods(ctx);local have=0
  if m&im.Mod_Ctrl~=0 then have=have|1 end;if m&im.Mod_Shift~=0 then have=have|2 end;if m&im.Mod_Alt~=0 then have=have|4 end
  if byid[id].alt then have=have&~4;return have==(b.mods&~4) end
  return have==b.mods
end
-- Alt зажат? (для действий с alt=true: точная правка / относительная вставка)
function M.alt(im,ctx) return im.GetKeyMods(ctx)&im.Mod_Alt~=0 end
-- Какую комбинацию нажал пользователь в этот кадр (захват новой привязки); nil — ничего. Одни модификаторы не считаются.
local CAPTURE={}
for c=65,90 do CAPTURE[#CAPTURE+1]=string.char(c) end
for d=0,9 do CAPTURE[#CAPTURE+1]=tostring(d) end
for f=1,12 do CAPTURE[#CAPTURE+1]='F'..f end
for _,n in ipairs({'Up','Down','Left','Right','Delete','Backspace','Space','Enter','Tab','Home','End','PageUp','PageDown','Insert','Escape'}) do CAPTURE[#CAPTURE+1]=n end
function M.capture(im,ctx)
  for _,name in ipairs(CAPTURE) do
    local key=imkey(im,name)
    if key and im.IsKeyPressed(ctx,key,false) then
      local m=im.GetKeyMods(ctx);local mods=0
      if m&im.Mod_Ctrl~=0 then mods=mods|1 end;if m&im.Mod_Shift~=0 then mods=mods|2 end;if m&im.Mod_Alt~=0 then mods=mods|4 end
      return {key=name,mods=mods}
    end
  end
end
function M.groups()
  local out,idx={},{}
  for _,a in ipairs(M.ACTIONS) do
    local g=idx[a[2]];if not g then g={a[2],{}};idx[a[2]]=g;out[#out+1]=g end
    g[2][#g[2]+1]=a
  end
  return out
end
return M
