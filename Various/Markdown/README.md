# ReaMD - Markdown editor, project notes & Multiline input

A Lua multiline widget drawn with ReaImGui, with plain-text and live Markdown modes in the same editable surface. Embed it in your own script or use the included editor. Each instance owns its document, selection, layout caches and undo history; loading the library does not change globals or `package.path`.

## Install and run

1. In **Extensions → ReaPack → Import repositories**, add:

   ```text
   https://raw.githubusercontent.com/ErrrikMarrrtinez/ReaperScripts/master/index.xml
   ```

2. Synchronize packages and search for **ReaMD**. Install **ReaMD - Markdown editor, project notes and Multiline input library**. Install **ReaImGui: ReaScript binding for Dear ImGui** separately if needed; the scripts use its `0.9.2.3` compatibility API.
3. Search for **ReaMD** in the REAPER **Main** action list:
   - **mrtnz_ReaMD - Markdown editor.lua** — standalone Markdown files.
   - **mrtnz_ReaMD - Project notes.lua** — a Markdown note embedded in each REAPER project.
   - **mrtnz_ReaMD - Multiline input demo.lua** — the reusable plain-text input.

The package includes all three actions, library files and documentation. It does not need Python, a browser or JS_ReaScriptAPI. [SWS](https://www.sws-extension.org/) is optional for opening external HTTP links; internal heading and footnote links work without it. A host application can supply its own `on_open_link` callback.

For manual installation, keep this entire directory together and load a `mrtnz_ReaMD - *.lua` launcher through **Actions → ReaScript: Load**. Restart a running action after updating its modules. The package ID and library paths remain unchanged; the older launchers remain as compatibility files, while only the three ReaMD actions are registered by this release.

## Project notes

Run **ReaMD - Project notes** and start writing. Each project has one Markdown document; switching project tabs switches notes automatically. Open tabs retain independent undo/redo histories, selections and scroll positions while this action is running. A new project starts with an empty note.

Every text change immediately updates `GetProjExtState(project, 'ReaMD', 'notes')` through `SetProjExtState` and marks that project as modified. No external `.md` file is required. **Save project** or **Ctrl+S** saves the entire REAPER project, including the note, to its `.rpp`; **Ctrl+Shift+S** opens Save As. An untitled project must be saved before its notes can survive closing the project. Closing only the notes window leaves its edits in the open project. Undo history itself is kept only for the current script session.

Source/Reading modes, formatting shortcuts, tables, links and themes work like the standalone editor. Relative image paths resolve against the RPP directory (or the project recording directory before the first save). Running the action again closes the existing notes window instead of starting another writer.

## Embed a multiline field

This example loads the shared ReaPack installation. For a bundled copy, change `library_path` to your local `Markdown/init.lua`; keep its sibling modules together.

```lua
local library_path = reaper.GetResourcePath()
  .. '/Scripts/ReaperScripts/Various/Markdown/init.lua'
if not reaper.file_exists(library_path) or not reaper.ImGui_GetBuiltinPath then
  reaper.MB('Install ReaMD and ReaImGui through ReaPack.', 'Missing dependency', 0)
  return
end

local Multiline = dofile(library_path)
local im = dofile(reaper.ImGui_GetBuiltinPath() .. '/imgui.lua')('0.9.2.3')
local ctx = im.CreateContext('My editor')
local field = Multiline.new({
  text = 'Edit me',
  wrap = true,
  font_family = 'Arial',
  font_size = 18,
  -- markdown = true, -- enable the live Markdown projection
  -- markdown_shortcuts = true,
  on_change = function(editor, edit, action)
    -- The host owns persistence: editor:get_text() returns source text.
    -- edit is nil for undo/redo.
  end,
})

local function loop()
  field:prepare(ctx, im) -- every frame, BEFORE the first ImGui.Begin
  local visible, open = im.Begin(ctx, 'My editor', true)
  if visible then
    local changed, text = field:render(ctx, '##body', 0, 0)
    -- changed reports a document change since the previous render.
    im.End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.atexit(function() field:dispose() end)
reaper.defer(loop)
```

Use a separate field instance for each ImGui context. Prepare all fields before the first `Begin`, then render them with distinct IDs. Sizes follow `BeginChild`: zero fills available space, positive values set dimensions, negative values reserve space at the far edge.

All positions are **zero-based UTF-8 byte offsets**; ranges are **`[first, last)`**. Wrapping changes visual rows, never the underlying document. Selection direction, caret affinity at wrap boundaries and undo state remain attached to source positions.

| API | Purpose |
|---|---|
| `get_text()` / `set_text(text, undoable)` | Read or load source; `undoable=true` records one replacement |
| `insert_text(text, kind)` / `replace_range(a, b, text, kind)` | Undoable edits; reserve `kind='typing'` for keyboard-like input |
| `get_selection()` / `set_selection(anchor, head, affinity)` | Directed selection; `nil` anchor clears it |
| `get_selected_text()` / `set_caret(pos, extend, affinity)` | Source text and caret movement |
| `undo()` / `redo()` | Restore edits, selection and view state |
| `set_wrap(enabled)` / `set_font_size(size)` | Plain-text wrapping and zoom |
| `set_markdown(enabled)` | Switch projection, preserving text and history; applied at the next `prepare` after UI attachment |
| `set_read_only(enabled)` | Prevent edits while retaining selection, copy, scrolling and link navigation |
| `scroll_to(pos, align)` | Reveal a source position; `'start'` aligns it to the viewport top |
| `format(command, value)` | Markdown formatting and table insertion |
| `find_all(query, options)` / `replace_all(query, replacement, options)` | Search and replacement API |
| `focus()` / `dispose()` | Request keyboard focus / release widget resources |

For all options, methods, source projection and geometry details, see [API.md](API.md) (Russian). Formatting commands, tables and styles are documented in [MARKDOWN.md](MARKDOWN.md) (Russian). [PORTING_MAP.md](PORTING_MAP.md) records the original editor behavior carried into the library.

## Editing and reading

- Select **Reading** for ordinary-click links and a stable formatted view. Editing uses **Ctrl+click** to follow links. Select **Source** to edit raw Markdown. Both demos, their sample text, menus, tooltips and dialogs use English.
- **Ctrl+B / I / K / E**: bold / italic / link / inline code. **Ctrl+Z**, **Ctrl+Shift+Z** or **Ctrl+Y**: undo / redo. **Ctrl+wheel**: zoom.
- **Ctrl+O / S / Shift+S**: open / save / save as in the standalone editor. The compact toolbar keeps mode and theme controls; formatting remains accessible from the keyboard.
- Tables edit in place. **Tab / Shift+Tab** move between cells, **Enter** moves down, **Shift+Enter** inserts a cell line break. Hover borders for insertion controls or right-click for row/column actions. Checked tasks are struck through.
- Typing `--` produces `—`; undo restores the two hyphens. Code, math, link destinations and pasted text remain literal. Set `markdown_smart_dashes=false` to disable this.
- Code blocks keep literal text and have their own horizontal scrolling and `copy` control. **Shift+wheel** scrolls a long code line.

## Scope and performance

The widget supports lazy wrapping, viewport anchoring during resize/zoom, independent fields, configurable history, native task checkboxes, editable Markdown tables, headings, inline formatting, links, footnotes, callouts, local images and three themes. The original editor's geometry and selection behavior were adapted to wrapped rows and source-mapped Markdown.

This is an initial release, not a complete Obsidian/CommonMark implementation. Math is a small native subset, not MathJax/KaTeX. Mermaid supports small acyclic TD/TB/LR flowcharts with `-->` edges, up to 40 nodes. Unsupported diagrams stay as code. Remote images need a host-provided local resource resolver. Full HTML, vault/backlinks, Unicode grapheme segmentation and bidi are not implemented.

Layout work is budgeted and prioritizes the viewport; tests outside this repository cover 20,000-line resize behavior and very long lines. The Markdown block parser still scans the document on text changes. UI-model checks do not replace running the editor in REAPER; no test runtime is installed with the package.

## Package maintenance

`mrtnz_Markdown.lua` owns the ReaPack package. Its explicit `@provides` list registers only the two launchers in Main and installs the modules as `nomain`; helper Lua files carry `@noindex`. Increase its `@version` for a new release and include new runtime files in `@provides`. The repository's existing workflow regenerates `index.xml` after a push to `master`. Metadata follows the [official ReaPack packaging documentation](https://github.com/cfillion/reapack-index/wiki/Packaging-Documentation).
