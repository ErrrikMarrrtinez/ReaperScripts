-- @noindex
-- Project persistence belongs to the host, not to the reusable input widget.
local Session = {}
Session.__index = Session
Session.section, Session.key = 'ReaMD', 'notes'

local function identity(r, project)
  -- The master-track GUID also detects a different RPP opened in the same tab.
  return r.GetTrackGUID(r.GetMasterTrack(project))
end

local function read(r, project)
  local found, text = r.GetProjExtState(project, Session.section, Session.key)
  return found > 0 and text or ''
end

function Session.new(r, Multiline, options)
  return setmetatable({r=r, Multiline=Multiline, options=options or {}, states={}, serial=0}, Session)
end

function Session:write(state)
  local r, project = self.r, state.project
  if state.loading or not r.ValidatePtr(project, 'ReaProject*') or
      identity(r, project) ~= state.identity then return end
  local text = state.editor:get_text()
  if text == state.text then return end
  -- Write synchronously on every edit, including undo/redo, before a project can
  -- be saved or closed. No deferred write may accidentally target the next tab.
  r.SetProjExtState(project, Session.section, Session.key, text)
  r.MarkProjectDirty(project)
  state.text = text
  state.change_count = r.GetProjectStateChangeCount(project)
end

function Session:current()
  local r = self.r
  local project, path = r.EnumProjects(-1, '')
  for handle, state in pairs(self.states) do
    if not r.ValidatePtr(handle, 'ReaProject*') then
      state.editor:dispose()
      self.states[handle] = nil
    end
  end
  if not project then return nil end
  local token = identity(r, project)
  local state = self.states[project]
  if state and state.identity ~= token then
    state.editor:dispose()
    self.states[project], state = nil, nil
  end
  if not state then
    self.serial = self.serial + 1
    state = {project=project, identity=token, text=read(r, project), id=self.serial}
    local options = {}
    for k, v in pairs(self.options) do options[k] = v end
    options.text = state.text
    options.on_change = function() self:write(state) end
    state.editor = self.Multiline.new(options)
    self.states[project] = state
  end
  local changed_tab = self.active ~= state
  if changed_tab then
    if self.active then
      self.active.editor.drag = nil
      self.active.editor.focused = false
    end
    self.active = state
    state.editor.pending_scroll = {state.editor.scroll_x, state.editor.scroll_y}
    state.editor.follow_caret = false
  end
  local count = r.GetProjectStateChangeCount(project)
  if changed_tab or state.change_count ~= count then
    local text = read(r, project)
    if text ~= state.text then
      -- Reload host-side changes (including REAPER undo) without writing them
      -- back or retaining an undo history belonging to an obsolete document.
      state.text, state.loading = text, true
      state.editor:set_text(text)
      state.loading = false
    end
    state.change_count = count
  end
  state.path = path or ''
  state.name = state.path:match('([^/\\]+)$') or 'Untitled project'
  local base = state.path:match('^(.*[/\\])') or r.GetProjectPathEx(project, '')
  if base ~= '' and not base:match('[/\\]$') then base = base .. '/' end
  state.editor.options.markdown_base_path = base
  return state
end

function Session:save_project(state, save_as)
  -- Always use the originating project handle, never the active-project alias 0.
  if not self.r.ValidatePtr(state.project, 'ReaProject*') or
      identity(self.r, state.project) ~= state.identity then return end
  self:write(state)
  self.r.Main_SaveProject(state.project, not not save_as)
end

function Session:dispose()
  -- Changes already live in ProjExtState. Do not rewrite stale state at exit:
  -- the project might have been closed or reverted since the last UI frame.
  for _, state in pairs(self.states) do state.editor:dispose() end
  self.states, self.active = {}, nil
end

return Session
