# Compressor, Gate and the cleanup chain

**Compressor** and **Gate** use the same Auto/Get, per-item controls, time selection and Remove workflow as De-ess and Breaths. They write one take-volume envelope. They do not insert a compressor FX or render audio.

Drag a cleanup tab onto another cleanup tab to move it before that stage. Processing follows the displayed order, from left to right. Align and Pitch remain separate. A moved tab changes processing, not just the layout. Each captured item retains its own order and parameters; a group control edit changes that control for the selected group. Merely capturing the group no longer copies the first item's settings to the rest.

The chain reevaluates downstream detectors when an earlier gain curve changes. Gain reductions add in dB; makeup gain is signed. The combined result multiplies the captured original envelope once. Remove rebuilds the remaining chain and restores the original envelope when the last stage is removed. Range edits retain recipes for the other sections. Curves from older cleanup caches have no recipes; they remain frozen until that stage is edited.

Unchanged stages reuse their complete curves, including Breath detection. The cache checks source analysis, upstream gain, recipes, exclusions, learned breath examples and dynamics input gain. New slider values cancel superseded previews; session saving runs separately and yields to edits. While dragging, analysis uses a 4 ms work budget; after release it uses 12 ms. Cleanup writes generated linear envelope points in one native update, with the original point API retained for preserved non-linear points. Detector resolution and envelope precision are unchanged.

## Controls

De-ess, Breaths, Compressor and Gate share a preset row: **Default**, **Save...**, and **Delete**. Default resets the current stage's numeric controls only. Named presets persist in REAPER's user preferences, including across REAPER restarts. Applying a preset updates all currently captured target items while preserving the other stages, processing order, selection range and learned breath examples. Per-item settings still use the existing project/session cache.

Auto skips selected empty and MIDI items and reports their count. A failed capture is attempted once per selection; use Get to retry after resolving the error.

The compressor carries all numerical controls from the installed Julian mod:

| Control | Range | Default |
| --- | --- | --- |
| Threshold | -60 to +6 dB | 0 |
| Ratio | 1:1 to 100:1 | 4:1 |
| Out gain | -24 to +18 dB | 0 |
| Attack | 0–200 ms | 10 |
| Release | 0–500 ms | 100 |
| Pre-comp | 0–1000 ms | 0 |
| Julian knee | 0–24 dB | 0 |
| RMS size | 0–2000 ms | 5 |
| Env interval | 0.5–100 ms | 5 |
| Detector HP | 0–20000 Hz | Off |
| Detector LP | 1–20000 Hz | Off at 20000 |

The gate has Threshold (-90 to +6 dB), Hysteresis (0–24 dB), Range (0–96 dB), Attack (0–200 ms), Hold and Release (0–2000 ms), Pre-open (0–1000 ms), plus RMS, interval and detector HP/LP. Hysteresis lowers the closing threshold relative to the opening threshold. Hold delays closing; Attack opens and Release closes the gate. Gate timing uses a 0.5 ms detector grid, followed by the requested envelope interval.

**Envelope active** and **Show envelope** control the shared native envelope. These are whole-chain controls. **RT Update** defaults off: parameter changes commit on release. When on, the existing deferred job scheduler coalesces live updates, with one Undo transaction per gesture. The update time includes deferred scheduling; it is not a plug-in latency measurement.

The green line inside Threshold shows the cached detector level at the REAPER play/edit cursor. It is a pre-FX measurement that includes item/take volume and earlier owned cleanup stages. It does not claim to measure the output of track FX or arbitrary existing automation. HP/LP filter only the detector.

## Runtime and persistence

`audio.lua` caches take-accessor PCM in native arrays, in bounded blocks. The cache holds at most 384 MiB of PCM across items; older PCM is evicted when necessary. The heard-time rate is at least 48 kHz, up to the source rate capped at 192 kHz, with accessor/play-rate conversion. Stereo/multichannel detection averages channel power, so inverted channels do not cancel each other.

`engine.lua` runs the filters, sliding RMS and compressor follower in private EEL VMs. Compressor threshold, ratio, knee and output gain reuse the follower. Gate threshold, hysteresis, range, attack, hold, release and interval reuse its filtered RMS cache. Filter/RMS changes and changes to the upstream curve invalidate the corresponding detector cache. PCM capture uses a separate lightweight waveform pass; entering Compressor or Gate alone does not start FFT or breath classification. Entering De-ess/Breaths later upgrades the analysis when needed.

Settings, processing order, ranges, recipes and original-envelope ownership use the existing per-project REAPER-session cache. They survive selecting other items and reopening the script during the same REAPER session. Raw PCM and detector buffers are memory-only and are rebuilt after reopening. Restarting REAPER starts a new cleanup session; Pitch project persistence remains separate.

`chain.lua` manages stage dependencies. De-ess/Breaths use their existing 10 ms features with upstream gain applied to RMS and band power; they do not rerun FFT on the envelope-modulated signal. This is an approximation around very fast gain edges. Adjusted features and breath inference are cached too. All native writes still pass through the existing transaction/rollback code.

## Legacy differences

- RMS actually reaches 2000 ms; the inspected legacy buffer capped it at one sample-rate's worth of samples (one second).
- Channel linking uses energy rather than arithmetic sample averaging.
- Pre-comp keeps the inspected script's time-advance convention, including the release portion. It is bounded to the captured item; it does not read beyond the item to anticipate a later phrase.
- There is no temporary play-rate or item-length mutation during analysis.
- Curves are sampled at Env interval, then simplified with a gain-error bound. Selection edges feather inward by at most 15 ms to preserve neighbouring edits and original automation.
- The gate is a new module, not a gate mode hidden in the legacy compressor.
- SWS, legacy GUI imports and preset files are not runtime dependencies. ReaImGui's EEL function API is required for dynamics.

## Fixes accompanying the chain

A missing peak-cache return is now handled as unavailable display data instead of applying a bitwise mask to nil. Cleanup snapshots retain their relaxed source-validation flag after state refresh. Group checks marshal native calls to the main deferred loop, and failed jobs clear pending apply flags so they do not retry the same write indefinitely. Ownership shortcuts are refreshed even when two different stage recipes produce an identical native envelope.

Cleanup FFT receives native arrays directly, with PCM validation in EEL. Its 1024-sample real spectrum now uses a 512-point complex transform; the Hann window, 10 ms grid and detector features stay the same. Audio reads cover four feature blocks, while each EEL block still yields separately and reuses the uploaded PCM. The Lua fallback remains available for De-ess/Breath analysis.

Changing overall item volume preserves the De-ess/Breath source analysis and owned envelope. During a read, an accessor invalidation is accepted only when the item gain changed and the captured source, timing and envelope still match; other source edits still stop the read. Active dynamics are recalculated for the new input gain. Reports include actual batch work/apply timings and the Breath cache used after upstream stages.

Align zoom-out stops at the full fitted range, and its Analyze/profile/display controls share a row when the width permits.

## Verification

Offline checks use the actual WDL EEL VM for the numerical kernels and mocked REAPER calls for orchestration. They cover the Julian knee, ratio/gain, two-second RMS, linked stereo, HP filtering, gate hysteresis/hold, direct-buffer FFT parity, per-item/group controls, cached updates, range retention, order-dependent detection, session reopening, Undo/Redo, single/group rollback, failure retry prevention, post-Align geometry, baseline restoration, and UI scope/drag-payload handling.

Native REAPER GUI, real accessor performance and listening have **not** been verified for this change. A first read, changed filters or changed upstream stage can still take measurable time. Cached numerical timings must not be presented as end-to-end REAPER timings.

Source attribution: [NOTICE.md](NOTICE.md).
