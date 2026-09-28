-- @noindex
-- ReaScript entry point: one editable Markdown surface, native ReaImGui.
local r=reaper
if not r or not r.ImGui_GetBuiltinPath then
  if r then r.MB('Install ReaImGui through ReaPack, then run this script again.','ReaMD',0) end
  return
end
local root=debug.getinfo(1,'S').source:match('^@?(.*[\\/])')
local im=dofile(r.ImGui_GetBuiltinPath()..'/imgui.lua')('0.9.2.3')
local Multiline=dofile(root..'init.lua')
local function read(path)
  local f=io.open(path,'rb');if not f then return nil end
  local s=f:read('*a');f:close();return s
end
local sample=read(root..'markdown/sample.md') or '# New note\n\n'
local e=Multiline.new({text=sample,markdown=true,markdown_shortcuts=true,font_family='Arial',font_size=18,padding=24,
  markdown_theme='graphite',markdown_max_width=900,markdown_base_path=root,tab_mode='insert'})
local ctx=im.CreateContext('ReaMD - Markdown editor')
local path,clean_text,status=nil,sample,''
local theme=0
local pending_markdown
local function save(as_new)
  if not path or as_new then
    local ok,name=r.GetUserInputs('Save Markdown',1,'Full path to .md,extrawidth=260',path or (root..'Note.md'))
    if not ok or name=='' then return end
    if name~=path and read(name) and r.MB('Replace the existing file?\n'..name,'Save',4)~=6 then return end
    path=name
  end
  local f,err=io.open(path,'wb')
  if not f then status='Could not save: '..tostring(err);return end
  local ok,message=f:write(e:get_text());f:close()
  if not ok then status='Write error: '..tostring(message);return end
  clean_text=e:get_text();status='Saved: '..path
end
local function open()
  if e:get_text()~=clean_text and r.MB('This note has unsaved changes. Open another file?','Open',4)~=6 then return end
  local ok,name=r.GetUserFileNameForRead(path or root,'Open Markdown','.md')
  if not ok then return end
  local value=read(name)
  if not value then status='Could not open the file';return end
  e:set_text(value);path,clean_text=name,value
  e.options.markdown_base_path=name:match('^(.*[\\/])') or root
  status=name
end
local formats={{'Bold','bold','Ctrl+B'},{'Italic','italic','Ctrl+I'},{'Strikethrough','strike','Ctrl+Shift+X'},
  {'Highlight','highlight','Ctrl+Shift+H'},{'Inline code','code','Ctrl+E'},{'Code block','code_block','Ctrl+Shift+C'},
  {'Link','link','Ctrl+K'},{'Image','image'},{'Bullet list','bullet','Ctrl+Shift+8'},
  {'Numbered list','ordered','Ctrl+Shift+7'},{'Task list','task','Ctrl+Shift+9'},{'Quote','quote','Ctrl+Shift+Q'},
  {'Callout','callout'},{'Horizontal rule','rule'},{'Formula','math'}}
local guarded_loop
local function loop()
  if pending_markdown~=nil then e:set_markdown(pending_markdown);pending_markdown=nil end
  e:prepare(ctx,im)
  im.SetNextWindowSize(ctx,1100,850,im.Cond_FirstUseEver)
  local visible,keep=im.Begin(ctx,'ReaMD - Markdown editor',true)
  if visible then
    local ctrl=im.IsKeyDown(ctx,im.Mod_Ctrl)
    if ctrl and im.IsKeyPressed(ctx,im.Key_S,false) then save(im.IsKeyDown(ctx,im.Mod_Shift)) end
    if ctrl and im.IsKeyPressed(ctx,im.Key_O,false) then open() end
    --[[if im.Button(ctx,'Open') then open() end
    im.SameLine(ctx);if im.Button(ctx,'Save') then save(false) end
    im.SameLine(ctx);if im.Button(ctx,'Format') then im.OpenPopup(ctx,'format') end
    if im.BeginPopup(ctx,'format') then
      for _,f in ipairs(formats) do if im.MenuItem(ctx,f[1],f[3]) then e:format(f[2]);e:focus() end end
      im.Separator(ctx)
      for level=1,6 do if im.MenuItem(ctx,'Heading '..level,'Ctrl+Alt+'..level) then e:format('heading',level);e:focus() end end
      im.EndPopup(ctx)
    end
    im.SameLine(ctx);if im.Button(ctx,'+ Table') then e:format('table');e:focus() end
    im.SameLine(ctx);if im.SmallButton(ctx,'Undo') then e:undo();e:focus() end
    im.SameLine(ctx);if im.SmallButton(ctx,'Redo') then e:redo();e:focus() end
    im.SameLine(ctx);if im.SmallButton(ctx,'A−') then e:set_font_size(e.options.font_size-1) end
    im.SameLine(ctx);if im.SmallButton(ctx,'A+') then e:set_font_size(e.options.font_size+1) end]]
    local changed,source=im.Checkbox(ctx,'Source',not e.options.markdown)
    if changed then pending_markdown=not source;if source then e:set_read_only(false) end end
    im.SameLine(ctx)
    local reading_changed,reading=im.Checkbox(ctx,'Reading',e.options.read_only)
    if reading_changed then e:set_read_only(reading);if reading then pending_markdown=true end end
    im.SameLine(ctx);im.SetNextItemWidth(ctx,140)
    local theme_changed,next_theme=im.Combo(ctx,'##theme',theme,'Graphite\0Paper\0Sand\0')
    if theme_changed then theme=next_theme;e.options.markdown_theme=({'graphite','paper','sand'})[theme+1] end
    --im.SameLine(ctx);im.TextDisabled(ctx,(path and path:match('[^\\/]+$') or 'Untitled')..(e:get_text()~=clean_text and ' *' or ''))
    --im.Separator(ctx)
    local _,h=im.GetContentRegionAvail(ctx)
    e:render(ctx,'##markdown',0,math.max(80,h-im.GetTextLineHeightWithSpacing(ctx)*1.7))
    local group,row,col
    if e.options.markdown and e.layout.parser then group,row,col=(function()
      local i=e.document:line_at(e.caret);local m=e.layout.parser.lines[i]
      if m and m.cells then
        local p=e.caret-e.document.lines[i].start
        for c,v in ipairs(m.cells) do if p<=(v.raw_b or v.b) then return m.table,m.table_row,c end end
      end
    end)() end
    local hint=e.options.read_only and 'Reading · Click links to open · Ctrl+C to copy selection' or group and ('Cell '..tostring(row)..':'..tostring(col)..' · Tab / Shift+Tab · Enter to move down · Right-click for actions') or
      'Ctrl+B  ·  Ctrl+I  ·  Ctrl+K  ·  Ctrl+Z  ·  Ctrl+wheel to zoom'
    im.TextDisabled(ctx,status~='' and status or e.last_link or hint)
    im.End(ctx)
  end
  if not keep and e:get_text()~=clean_text then
    local answer=r.MB('Save changes before closing?','ReaMD',3)
    if answer==6 then save(false);keep=e:get_text()~=clean_text elseif answer==2 then keep=true end
  end
  if keep then r.defer(guarded_loop) end
end
guarded_loop=function()
  local ok,err=xpcall(loop,debug.traceback)
  if not ok then r.ShowConsoleMsg('\nReaMD - Markdown editor:\n'..tostring(err)..'\n') end
end
r.atexit(function() e:dispose() end)
r.defer(guarded_loop)
