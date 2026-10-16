# Ruin Vocals

Vocal timing, take-volume cleanup and pitch editing in one ReaImGui window.
Includes Classic Align, experimental Advanced and Hybrid timing, De-ess,
Breaths, Compressor and Gate. Pitch edits use a dedicated take ReaPitch.

## Install and run

Version **0.13.8** is the first public ReaPack release.

1. In **Extensions → ReaPack → Import repositories**, add:

   ```text
   https://raw.githubusercontent.com/ErrrikMarrrtinez/ReaperScripts/master/index.xml
   ```

2. Synchronize packages and search for **Ruin Vocals**.
   Install **Ruin Vocals: vocal align, breath&pitch detect and editor, envelope dynamic**.
   Install **ReaImGui: ReaScript binding for Dear ImGui** separately; the editor
   uses its `0.9.3` compatibility API. Use REAPER 7 with its bundled ReaPitch.
3. The package registers two **Main** actions:
   - **Ruin Vocals: vocal align, breath&pitch detect and editor, envelope dynamic** (`mrtnz_Ruin Vocals - vocal align, breath&pitch detect and editor, envelope dynamic.lua`) opens the complete editor.
   - **Ruin Vocals - Export Pitch Meter** (`mrtnz_Ruin Vocals - Export Pitch Meter.lua`) exports an optional Pitch
     Meter measurement as CSV/text and can create MIDI notes.

For manual installation, keep this entire folder together and load the
`mrtnz_Ruin Vocals - vocal align, breath&pitch detect and editor, envelope dynamic.lua`
script through **Actions → ReaScript: Load**.
ReaPack installs the internal modules, model weights, documentation and license
notices with the package. No Python, SWS or JS_ReaScriptAPI is required.

The optional **Vocaligner Pitch Meter** JSFX provides measured output for the
Pitch editor's **Check** display. ReaPack installs it as an effect. For manual
installation, copy `jsfx/Vocaligner Pitch Meter.jsfx` into a `Vocaligner` folder
inside **Options → Show REAPER resource path → Effects**. Place it after
ReaPitch in the edited take, or on the vocal track. See [Pitch Meter setup](jsfx/README.md).
The editor can analyze and edit pitch without the meter; Check and the export
action require an active meter. Its Lua link uses REAPER's built-in `gmem` API.

Restart a running action after updating its modules. Cleanup caches stay under
REAPER's `Cache/Vocaligner`; pitch edits stay in project/take metadata, so moving
this script folder does not relocate project audio or change those storage keys.
Align captures and applied-edit ownership are held in the running window: use
Restore before closing if you need to preserve its pre-Align baseline for a new
capture. The next capture otherwise starts from the current item state.

## Implementation history

0.13.2 moves Advanced's acoustic pair costs and dynamic programming into a bounded EEL kernel, with Lua fallback. Close competing paths can now retain regions where all eligible placements agree within 20 ms for at least 150 ms; disputed regions keep captured timing. The supplied two-dub feature export now produces valid partial plans with 33% and 36% accepted content. This is an offline result, not a listening verdict. Pitch evidence reuses cached acoustic features, reports its own timing and reliable-frame counts, and clears old pitch fields when switched off. [Algorithm, measurements and validation limits](align/README.md).

0.13.1 fixed Advanced's premature 98% progress, kept completed feature reads available in exports after Cancel, and added current-dub/candidate/elapsed diagnostics. That version still rejected both supplied dubs as ambiguous and took too long; 0.13.2 addresses the native computation path and partial acceptance separately.

**Pitch Transition:** the merged v6 policy extends smoothing farther into both adjacent notes, with continuous blending where transitions overlap. Increasing Amount makes the orange connector steeper while keeping its endpoints and centre grip fixed. Saved v1–v5 transitions retain their existing sound until edited. [Transition behavior and validation](pitch/CURVE_V4.md).

0.13.0 adds **Advanced Align (experimental)** beside **Classic**. Choose the engine in Align; each keeps its own settings and cached analysis. Switching engines does not change project timing. Advanced accepts supported phrase matches, leaves ambiguous/unmatched material at captured timing, and applies parameter edits on release. Both engines preserve verified cleanup gain when timing changes or is restored. [Advanced controls, supported sources and validation](align/README.md).

**Cleanup dynamics:** separate Compressor and Gate tabs, draggable processing order, per-item session settings, EEL PCM/detector caches and optional RT Update. All four cleanup tabs have saved presets and a Default reset. Auto skips empty/MIDI items in mixed selections and no longer crashes or retries continuously after failed group capture. [Controls, legacy differences and validation limits](compressor/README.md). The nil peak-cache crash is fixed; Align zoom-out stops at Fit.

0.12.1 makes **Transition** connect the measured tail of the left note to the onset of the right note, including its first pitch point. **Amount** controls the correction; **Width** sets its reach on each side (20–400 ms), limited to the facing halves of the notes. This also works across short gaps without drawing pitch in unvoiced audio. Existing saved transitions keep their previous sound until edited.

Select notes with the right mouse button to edit them together. **Curve** applies the same pitch change at matching relative times; **Draw** repeats the shape while preserving the intervals between notes. **Transition** edits the incoming links of selected notes. These gestures preserve selection and commit as one Undo step. Parameter updates no longer briefly grey out the control panels.

ReaPitch insertion and window hiding share one UI-refresh lock. The new effect's floating window is checked again after initialization, and an error during rollback still releases the lock.

0.12.0 introduced the two Transition controls and tool-specific orange block connectors. The white line shows the corrected pitch. Amount 0 adds no correction; double-click restores the transition.

Fast, consistent pitch glides no longer disappear just because adjacent frames differ by 3.5 semitones. The model and measured F0 are unchanged; uncertain audio and isolated spikes still leave gaps. Glue no longer sends deleted item pointers to native item/track calls. Saved v1–v3 links and older Draw strokes keep their previous equations until edited. [Behavior and validation](pitch/CURVE_V4.md). Native playback of this release remains unverified.

Curve, cross-note Draw, explicit vibrato Add/Replace/Release/Growth, complete REAPER item selection for Analyze, and native envelope readback/rollback from 0.11.0 are retained.

**0.10.2** — Align, De-ess, Breaths and an experimental **Pitch** editor in one REAPER window. Pitch analyzes a selected vocal with a compact neural model, displays notes and a continuous contour, and writes smooth pitch/formant corrections to a dedicated take ReaPitch. Analysis and edits persist in the saved project. Lua controls the workflow, with REAPER FFT and embedded ReaImGui EEL kernels for numerical work. No Python, background process, sockets, gmem or SWS dependency at runtime.

0.10.2 adds a Root/Mode key menu, persistent selected-note outlines, five-semitone palette stops through blue, violet, rose, red and orange, and right-drag marquee selection (Ctrl/Shift adds; middle-drag pans). Tracks lists analyzed tracks only. Toggling ghosts preserves the current scroll and zoom, including a view outside the active item. Cleanup processes every item captured by multi-selection. Cached cleanup and Align controls update during dragging with a 35 ms coalescing interval and one Undo step per gesture; heavy Align rematching still waits for release. Progress spans the complete analysis and uses fixed layout space. Learn breath calibrates Sensitivity from the positive example while preserving Keep sound vetoes. The Auto/Get/Remove/item controls occupy one row. Cross-tool reapplication is recorded in the next-phase plan and remains deferred.

0.10.1 condenses Pitch controls into one horizontal row. Report... contains Copy report and Export case. Tracks... separates ghost visibility checkboxes from active-track selection by name. Bypass temporarily shows the original notes and hides other ghosts without changing track choices. Locked items can be displayed read-only; enabling a ghost includes its time range and pitch register in Fit. Hover uses a thinner joined outline; blue-to-rose color now spans twelve semitones and reverses smoothly through the next octave. Fit and algorithm controls are temporarily hidden; +/− are unchanged.

0.10.0 draws filled, softened note waveforms with a continuous blue–violet–rose pitch palette. Hover adds a subtle outline; dragging shows a compact Shift badge. Tracks... controls ghost waveforms and their predicted contours directly. Source follows measured frame knots independently of target edits or window width. Pitch, Align, De-ess and Breaths show separate edit/play cursors and follow playback past the visible range, with a short hold while navigating manually. New ReaPitch effects default to Soloist; saved choices and existing effects retain their algorithm. Scale highlighting remains; Snap is disabled, including saved Snap settings. [Next phase](pitch/NEXT_PHASE.md) records the proposed unvoiced/gain/MIDI work.

0.9.10 fixes a Pitch crash when the selected track contains no audio items. The canvas accepts a track without an active item snapshot; leaving audio focus clears unfinished preview gestures and stale item details while keeping saved analysis available when returning. This covers empty tracks, MIDI-only tracks and deleting the last audio item.

0.9.9 applies every valid Align result automatically to the captured dubs, including low-match results. Match confidence is informational; there are no Apply buttons or per-dub enable checkboxes. The reference is unchanged. Releasing settings applies the updated timing, and Restore/REAPER Undo remains available. Pitch also fixes a crash when a running job was passed to ReaImGui where a boolean was required; idle and same-frame analysis-start paths are covered by a stricter API fixture.

0.9.8 adds batch Pitch analysis, a project-time view of the active track and optional ghost notes from other analyzed tracks. Analyze can rebuild the source analysis while keeping compatible editor corrections; its menu also offers a full correction reset. Native ReaPitch algorithm, mix and bypass changes no longer block the editor. Align can recapture externally changed items. Its initial manual low-match application controls are superseded by 0.9.9. These paths passed offline host/UI checks; native REAPER behavior and audio still need a listening pass.

0.9.7 adds a per-item ReaPitch algorithm selector with available engine parameters. New effects default to elastique 3.3.3 Soloist; existing effects keep their current algorithm. Selection is saved without creating an FX until the first edit, and changing an existing FX preserves its envelopes and analysis. The guarded VST-state update is checked against supplied native Pro/Soloist captures and supports Undo/Redo and rollback. Actual native switching remains to be verified in REAPER. Pitch detection and transition processing are unchanged.

0.9.6 preserves short voiced regions during note segmentation and displays measured input waveforms inside the notes. Ordinary vertical note dragging now moves by relative semitones; Shift gives fine movement and Alt also gives fine movement. Analyze an unedited source again to get the new boundaries and 1 ms waveform cache; existing edits are not rebuilt automatically. The supplied case improves from 333/502 to 501/502 confident frames covered by notes, with 56 blocks versus the reference MIDI's 47. This does not establish pitch-detection or audible output accuracy. Transition processing is unchanged.

0.9.5 speeds up the first cleanup analysis and session-cache writes. De-ess/Breaths now keep an in-progress shared read when switching tabs; controls accept edits during that read and apply the latest values when ready. Cleanup uses a checked EEL implementation of the existing DSP, with the original Lua/native-FFT path as fallback. The model, 10 ms grid and detection settings are unchanged. Six supplied WAV segments produce identical breath-model decisions, event boundaries and gain curves within rounding tolerance in offline checks. Actual REAPER latency still needs a native check; **Copy report** separates accessor, feature, model, preview, apply and cache timings.

0.9.4 fixes a stale streaming-analysis cache that could hide most of the pitch line until the script was reopened. The neural calculation now uses native dot products with the same model and sample resolution; an older EEL path remains available if the new kernel fails its startup check. Offline measurements show about 2.4x faster neural evaluation, not a guaranteed 2.4x reduction in total Analyze time. **Export case** saves the full edit, measured input F0 and actual ReaPitch envelope for a controlled before/after test. See [the test workflow](pitch/TEST_CASE.md).

The displayed curve is a prediction, not a measurement of the ReaPitch output. The reported Flatten/Draw mismatch after Glue is still under investigation. ReaPitch, Draw/Flatten formulas and segmentation thresholds were preserved. Transition interaction and smoothing after Split also remain open.

Close and rerun the script after replacing its files. Use the vocal editor action
described above; the interface requests ReaImGui's `0.9.3` compatibility API.
Publication is handled by the repository's ReaPack indexing workflow after the
package changes are committed and pushed.

**Upgrading from an open 0.6 window:** remove its cleanup layers before closing it, or recover the unprocessed state with Undo/a project copy. Version 0.6 kept the original envelope only in that window's memory; 0.7 cannot recover an original that the old script has already discarded. Subsequent 0.7 window restarts reuse the session cache.

## Align

The following workflow describes **Classic**, the default engine. See [Advanced Align](align/README.md) for its different matching and release-only update policy.

1. Select one reference item in REAPER and press **Select reference**.
2. Select the dub items and press **Select dubs**. The reference can remain selected; it is excluded automatically.
3. Press **Analyze**. Usable results are automatically applied together in one Undo step. Low-match results are also applied automatically. Confidence below 40%, coverage below 55%, or support below 65% adds a warning to the status, without disabling the dub. Invalid timing maps and native write errors are still rejected. The reference remains unchanged even when it is included in the selected items.

All dubs appear below the reference. Peaks are requested immediately when captured, before analysis. **Show aligned timing** changes the drawing, not what is applied. Click to position REAPER's edit cursor; drag to pan, wheel to zoom, double-click to fit. Additional lanes scroll inside the window; tabs and **Copy report** stay at the top.

Cached timing controls update the captured group while dragging, at a minimum 35 ms scheduling interval. The last value is flushed on release, with one Undo step for the whole gesture. Intermediate live states are coalesced so a long drag does not retain every temporary curve. **Strength** blends the existing timing map. **Marker density**, smoothing, tolerance and stretch limits rebuild the map from cached correspondences. **Search range** and profile changes wait for release, then rematch cached features; they still require computation but do not reread audio or repeat FFT. **Marker fade** controls the stretch-marker crossfade. Reducing density gives a simpler timing map but can lose local detail.

The group dropdown retains reference, dubs, settings, waveforms, matching results and zoom. Groups are selected manually. **Restore** returns that group's processed takes to their captured state. The small × forgets a group without changing the project. Starting with another reference creates another group. Reusing the same ordered reference/dub set recalls its existing group when its captured state is still valid. Explicit **Analyze** recaptures changed items; **Restore** then uses that new capture. Applying timing targets the captured group, even if the current REAPER selection changes during analysis. Use **Select dubs** to change that group; **Restore** undoes its applied timing.

Items do not need equal lengths, common start times or Glue. The algorithm retains source endpoints instead of forcing the dub to fit the reference's entire duration. Existing source-map anchors and safe local stretch limits are retained even at low marker density. An overlapping group or external edit that changes a captured take invalidates its old baseline; it is not silently overwritten. Press **Analyze** explicitly to recapture it. If manually added stretch markers lack edge anchors, **Select dubs** offers **Add edge anchors**. This inserts the missing boundaries through REAPER's current source map in one Undo step, then captures the dubs. Curved markers remain unsupported.

## Pitch

Select one or more audio items, open **Pitch**, and press **Analyze**. With no item selection, selecting a track analyzes its audio items. The editor shows the active track in project time; click another item's notes to switch. **Tracks...** lists analyzed tracks: the checkbox selects a ghost, and its name switches editor focus. These ghost choices are saved in the project. Ghosts display saved waveforms and predicted contours without editing another track or running analysis. **Notes** moves centers; **Curve** edits movable anchors; **Transition** shapes note boundaries; **Modulation**, **Drift**, **Flatten** and **Vibrato** edit the target contour. Key/scale highlighting is visual only. Drag moves by relative semitones; **Shift** or **Alt** gives fine movement. Changing a scale never retunes existing notes. The editor writes target-minus-source corrections to ReaPitch when the edit is committed.

All tool panels reserve a fixed progress slot. Jobs below 350 ms never flash a progress fill; longer jobs use the same space without resizing the waveform/editor.

**Bypass** compares the owned ReaPitch with its original notes and temporarily hides other ghosts; **Reset** clears selected notes, the current item, or the selected items. Item reset removes the owned FX and all editor corrections while keeping analysis and unrelated FX. Analyze re-reads the source before FX; it keeps edits when source/rate/range remain compatible. For an incompatible source, use Reset and then Analyze. Muted items remain editable without changing their mute state. Ordinary project saving retains the analysis and take metadata; saved FX automation plays without the editor. This persistence is separate from the older cleanup session cache described below. Closing the script or changing tabs cancels unfinished Pitch computation/gestures.

See [Pitch workflow and native test guide](pitch/README.md), [research and measured results](pitch/RESEARCH.md), and [remaining native checks and a possible future JSFX backend](pitch/ROADMAP.md). The new editor has numerical and mocked-host checks, but still needs the user's native REAPER/listening pass.

## De-ess and Breaths

With **Auto** enabled, select one or several audio items in REAPER while either cleanup tab is open. After an 80 ms selection debounce, it displays the waveform, loads or computes analysis, and applies the active tool. You can adjust the controls while a new analysis is reading. Switching De-ess/Breaths retains that read and processes the final active tab. Turn Auto off for manual acquisition: **Get** captures all selected items and analyzes/applies them as a group in one action. Capturing a group retains each item's saved settings. Moving a control applies that parameter to every captured item. The dropdown focuses one cached item and its own controls. Auto, Get, Remove and the dropdown share one row.

After the first read, controls use cached features. Dragging updates the preview and take-volume envelope at a minimum 35 ms scheduling interval; release flushes the final value and closes one Undo step. **Remove** removes only the current tool's layer from the captured item or group. De-ess, Breaths, Compressor and Gate retain separate stage recipes but compose one envelope in the displayed tab order. Earlier stages feed the later detectors; changing or removing a stage rebuilds the downstream result. The original envelope is multiplied once. A unity stage may retain an envelope so its settings and dependencies remain recoverable. Curves from older caches remain frozen until that stage is edited.

The first visit to Breaths also computes its contextual features and tree scores, which are then reused in that window. This is separate from reading audio. Align uses richer features and reference/dub matching; its first analysis is separate. Pitch uses its own neural analysis. There is no single universal analysis shared by every tool. Compressor/Gate can begin with a lightweight PCM/waveform cache and request spectral analysis only when a spectral cleanup stage is needed.

**Breaths uses a trained detector** with its own controls, with acoustic grouping and boundary refinement. It still makes mistakes on consonants, room noise and recordings outside its training domain. Select a clear example and use **Learn breath** or **Keep sound** to adapt the take. After Learn breath, Sensitivity is calibrated from the adapted scores of the selected example, bounded to 5–95. Too little usable sound or a conflicting Keep sound example leaves it unchanged. Keep sound itself does not retune Sensitivity. Examples and item settings are retained in the saved project. [BREATH_MODEL.md](BREATH_MODEL.md) explains the controls, training data, measured accuracy and limitations.

### De-ess controls

| Control | Effect |
| --- | --- |
| Threshold | High-frequency detector level in dBFS. Lower values catch quieter sounds, including background noise. |
| Detector frequency | Frequency weighting of cached power bands, not a filter applied to the output audio. |
| Reduction | Percentage of the above-threshold level to attenuate. |
| Max cut | Maximum allowed dip, e.g. −9 dB. It does not force every event to that depth. |
| Pre-open | Ramp before a candidate; zero adds no pre-open. |
| Release | Finite return to original volume after the last active detector frame. 20 ms means two 10 ms steps, not a 20 ms exponential time constant. |
| Envelope detail | Higher retains finer changes and more envelope points. Lower simplifies the curve. |

The lower **HF** trace uses its own calibrated −60…0 dBFS scale. It shows the high-frequency detector measurement, including preceding cleanup stages, and threshold; it is not a full-band waveform peak meter or a post-FX output meter. Drag in that strip to change the threshold. A detector that remains above threshold can keep reducing the level indefinitely, regardless of Release. FFT windows and the 10 ms analysis grid also limit time resolution.

Breaths offers fixed **Reduction** or **Target level / Max cut**, sensitivity, minimum duration, inward fades, envelope detail, **Join gaps** and **Find edges**. Joining requires compatible audio across the gap; a single breath then receives a stable gain rather than separate dips. Model/features stay cached when gain, target or fades change. The combined envelope preserves the higher detail requirement of both active tools.

### Waveform, scope and navigation

- **Space** invokes REAPER action **40044** when the window is focused and a control is not being edited.
- Click the waveform to position the edit cursor; drag its body to pan. Wheel zooms; Shift-drag or middle-drag also pans; double-click fits.
- Drag **only the top time ruler** to select a processing interval. It scopes the edit applied on release. External time-selection changes are reflected here. **Escape** clears both selections without immediately rewriting the envelope.
- Existing work outside a selected interval is retained. A global time selection that does not overlap this item is ignored: the whole item remains available for processing.
- Amber sections show detected candidates. Hover gives their actual core and reduction-ramp times. Right-click a candidate to exclude or include it.
- The bottom overview shows the current tool's reduction across the whole item. Click or drag its translucent viewport to navigate the zoom without changing the edit cursor or time selection.
- Right-click an empty area between controls to choose **Waveform: Outline** or **Waveform: Legacy**. Both render the same data. The new outline display is symmetric; Legacy retains separate positive and negative peaks.

REAPER's existing peak cache provides the initial waveform. If peaks are unavailable, audio analysis supplies it. The display remains a peak-envelope preview, not rendered time-stretched audio.

## Cache and project edits

The De-ess/Breaths cache lasts for the current **REAPER session**, separately for each open project. Closing and reopening the script retains controls, source features, layer ownership and the original volume envelope. A nonpersistent ExtState token indexes data-only files under REAPER's `Cache/Vocaligner` directory. Restarting REAPER discards the token/index; old files may remain on disk but are not loaded into the next session. Learned breath examples remain a separate, intentional project-ExtState feature.

Moving a cleanup item or changing envelope display/selection flags does not invalidate its audio analysis. Ordinary trims and split children can reuse a covered source interval, remapping layers and the baseline; reuse is on the 10 ms feature grid. Changed pitch, rate, source mapping or newly exposed audio triggers analysis while preserving a recognized original envelope. Complex stretch/loop edits may need a new read and are only accepted when envelope ownership can be verified. Unknown manual volume-envelope edits are blocked with one message rather than stacked into the baseline; Undo that edit to recover.

Repeated edits always replace the current tool's layer against the saved original. Undo/Redo recognizes known outputs without immediately undoing the user's Undo; up to 12 recent outputs per cached item geometry survive reopening the script. This is not a replacement for saving a project copy. Restarting **REAPER itself** intentionally ends ownership: remove layers before that restart if you want to retain the ability to remove them individually next time.

Align groups remain in memory until the script closes. The in-memory audio budget is 120,000 frames, about 20 minutes at a 10 ms hop. Closed-project entries are pruned when capturing again. Cache files contain numerical features and envelope data, not source audio, and are never executed as Lua.

Application checks the active project, recording state, item locks, active take and captured geometry before writing. A failed insertion rolls back the batch. Rollback failures are reported for recovery with REAPER Undo. Only the active take gets markers, but moving/resizing its item also affects the item containing inactive takes. Curved existing markers and true loop repetitions remain unsupported by Align; volume-only cleanup can accept them. Fractional Glue source overruns have a two-source-sample tolerance.

The program does not save projects, glue items, render media or start another REAPER instance. Take-accessor rate/offset handling, reverse/section sources and native GUI behavior still need testing in the user's REAPER session.

## Reports and checks

**Copy report** is a grey button at the top right. It copies the report and prints the same text in REAPER's console. It includes group/item geometry, settings, errors, cache state and read/preview/write timings. The diagnostic log is no longer shown as an interface section.

Offline checks cover real Lua DSP and DTW, the embedded kernel running in an actual Cockos WDL EEL VM, and native-API models for envelopes, rollback, Undo/Redo, groups, cached controls, selected ranges and interface calls. They are not an in-host listening test or native visual verification.

On this machine, synthetic cached 18 s / 180 s items took about **3 / 38 ms** for the Lua detector/scope/region pass, plus **4 / 39 ms** for envelope-point preparation in one release check. These measurements exclude native writes, cache serialization, drawing, deferred scheduling and the first audio read. Do not treat them as REAPER latency guarantees.

## Code

- `app.lua`, `cleaner.lua`: group and item workflows, caches and automatic application.
- `cleanup_state.lua`, `session_cache.lua`, `codec.lua`: source-relative cleanup ownership and bounded session-cache serialization.
- `audio.lua`, `dsp.lua`: snapshots, quick peaks, bounded reads, native FFT and features. Cleanup skips MFCC/chroma/matching vectors; FFT array transfers are batched.
- `dtw.lua`, `timing.lua`, `warp.lua`: matching, smoothing, marker density, limits and strength blending.
- `cleanup.lua`, `curves.lua`, `eel.lua`: detectors, finite ramps, scope, independent layers and embedded acceleration.
- `breath.lua`, `breath_regions.lua`: breath candidates, acoustic boundaries, grouping and stable event gain.
- `breath_features.lua`, `breath_model.lua`, `breath_engine.lua`, `breath_profile.lua`: cached features, trained coefficients, EEL/Lua inference and per-take examples.
- `apply.lua`, `envelope.lua`: transactional edits, original-envelope composition and restore.
- `ui.lua`, `align_ui.lua`, `cleaner_ui.lua`, `controls.lua`: tabs, responsive controls and workflow display.
- `waveform.lua`, `navigator.lua`, `cleanup_ui.lua`: outline/legacy rendering, overview and candidate interaction.
- `config.lua`, `job.lua`, `init.lua`: preferences, cooperative jobs and private loader.
- `pitch/`: audio pitch analysis, exported SwiftF0 weights, Lua/EEL inference, note/curve editor, ReaPitch take envelopes and project persistence.

[EEL_GUIDE.md](EEL_GUIDE.md) explains Lua/EEL array exchange and its limits. [RESEARCH.md](RESEARCH.md) records algorithm research and validation history. Research sources and test scripts are kept outside the product folder.

To embed the app in another ReaImGui script:

```lua
local V = dofile('/path/to/vocaligner/init.lua')
local app = V.new(reaper)
local UI = V.import('ui')
app.engine = V.import('eel').new(ImGui, ctx, reaper)
app.pitch.engine = V.import('pitch/neural').new(ImGui, ctx, reaper)
-- Inside the host's deferred loop:
app:tick()
local open = UI.draw(ImGui, ctx, app)
-- On shutdown: app:dispose()
```
