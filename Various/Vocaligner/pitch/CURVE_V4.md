# Pitch curves v4 · Vocaligner

## Extended Transition reach

New Transition gestures use `link.version = 6`; the item evaluator stays at v4. Width now reaches past each note's midpoint, up to the note edge and the measured run. The previous inner reference pitches still define the target line. Extending the correction therefore does not let a remote onset or tail outlier move the entire transition. The outer offset and its slope remain zero; Amount 0 remains exact identity.

When incoming and outgoing paired corrections overlap, a quintic crossfade joins their requested offsets across the shared span. Each side's Amount weights that crossfade, so a neighbour at zero has no effect. This prevents two full corrections from adding inside a short note. Saved v1–v5 links retain their equations until edited. Curve capture, Draw ownership, neutral Split/Join and trim continue to follow the existing rules.

The orange block connector now steepens as Amount increases. Its two connection points and centre grip stay fixed. It remains a control for the pair; the white curve shows the predicted pitch.

The isolated follow-up in `vocaligner-research/transition-widen-20261003` includes the five Lua changes, this document, a patch and a merge manifest. Offline checks cover 315,299 exact legacy comparisons, wider influence on both sides, fixed inner targets, overlap bounds and continuity, zero neighbours, proportional Amount, real Lua canvas gestures, persistence, trim/Split/Join and host-API-model Undo/Redo/rollback. The full 34-note case at Width 400 ms stays within 0.30 cent of the written linear envelope on a 0.1 ms grid. REAPER playback and native GUI were not exercised for this follow-up.

## Paired Transition and grouped editing in 0.12.1

Newly edited boundaries use `link.version = 5`; the item evaluator remains v4. The supplied 20261003-010354 case exposed two problems with v4: the 112 ms gap between notes 2 and 3 exceeded the 80 ms regression radius, and the old support gate excluded the right note's first measured point. The regression consequently changed the note body without connecting its onset to the preceding tail.

v5 finds the last measured run in the left note and the first in the right. Separate runs contribute their facing tips, including voiced extensions beyond the blocks; a continuous run uses the existing departure/arrival search. Width extends each side up to the note midpoint. A line between the existing corrected pitches at the outer limits supplies broad offset targets at the tips, neighboring hops and intermediate points. Quintic ramps join those offsets with zero outer value and slope. The measured fine contour remains between the anchors. Amount scales the added correction; zero is exact identity. A steady slope stays unchanged, and an equal-endpoint bend can still be softened.

The correction reaches full strength at the first and last measured point. Its support fades over 12 ms outside a measured run, where the displayed F0 stays blank. This short control-envelope margin avoids a jump at the voiced edge; the middle of a longer unvoiced gap remains uncorrected by the link. This replaces the former 25 ms taper inside voicing only for v5 links. Existing v1–v4 links and Draw support policies keep their saved equations.

A Transition edit captures the Curve anchor layer that existed when the gesture began. Later Curve edits remain independently editable even at Amount 100%. The capture follows persistence, trimming and neutral Split/Join. Draw still owns its painted absolute trajectory.

RMB selection now survives Curve, Draw and Transition gestures. Curve applies the same pitch delta at corresponding relative times; Draw repeats the stroke relative to each note's displayed pitch, stopping at its own voicing gaps and note bounds. An ordinary single-note Draw retains cross-note painting. Transition adjusts each selected right note's incoming link, including an eligible unselected predecessor. Group resets follow the selected tool; one gesture creates one commit. Temporary parameter-write locks retain full opacity in Align, cleanup and Pitch; the locks still prevent conflicting actions, while genuinely unavailable controls keep their disabled appearance.

On the supplied pair with its later manual Curve experiment reset, Amount 100%, Width 80 ms moves the first right pitch from MIDI 53.4647 to 52.6993. With the exact exported Curve edits retained, it moves 58.0219 to 54.4083. The right contour from 0.672 s onward is unchanged. The written linear envelope follows the evaluator within 0.29 cent on a 0.1 ms grid. All 126,119 sampled corrections in the unedited 34-note export are exactly unchanged from 0.12.0. Separate checks cover continuous bends, quiet gaps, group gestures, single commits, trim/Split/Join, persistence, native API-model Undo/Redo, formant isolation and rollback. Actual Lua canvas renders and numerical evidence are in `vocaligner-research/pitch-v0121`.

These are offline evaluator, UI and host-API-model checks. REAPER was not launched or controlled, and playback/native output has not been listened to or measured for this release. Reopen the script, then move Amount or Width on the saved link to adopt v5; a restart alone keeps its previous equation.

FX creation already runs in one synchronous `PreventUIRefresh(+1/-1)` transaction with `TakeFX_Show(..., 2)` and `TakeFX_Show(..., 0)` immediately after insertion. v0.12.1 also checks the new effect's floating window after VST initialization, before releasing refresh. A thrown rollback error can no longer bypass the matching refresh release and Undo close, for edits or Reset. No refresh lock crosses a deferred frame, no global FX preference is changed, and later edits do not close an existing FX window the user opened. These paths are checked with injected add, hide, initialize, write and rollback failures. [REAPER API contract](https://www.reaper.fm/sdk/reascript/reascripthelp.html#PreventUIRefresh).

The following sections describe older releases.

## Current Transition behavior in 0.12.0

The item evaluator remains `curve_version = 4`. New edits use `link.version = 4`, `amount` 0–1 and `width` 0.02–0.4 seconds per side. The two controls replace Shape, Bias, Settle, Mix, Overshoot and endpoint gestures. Up increases Amount; sideways changes Width. A width-only edit from Amount 0 starts at 50%. Links are small block-to-block controls, visible only in Transition. The white contour alone represents the predicted pitch.

An endpoint-difference ramp is insufficient when the endpoints already have similar pitch but the interior contains a bend. The new operation fits a local linear trend to the existing corrected F0 samples with compact quadratic weights `(1 - (dt / width)^2)^2`. It samples the resulting offset at the departure, arrival, their midpoint and the middle of each outer tail. Quintic ramps interpolate these offsets; the two outer offsets and slopes are zero. This adds a smooth correction to the original contour rather than replacing every measured point with a connector. A steady linear slope is unchanged; an equal-endpoint bump is softened. Width controls both the fit radius and the extra time on each side of the detected transition, bounded by each note's duration. This is our implementation, not a claim to reproduce Melodyne's private algorithm.

Display and newly authored edits use `pitch/trace.lua`: confidence >= 0.3, audible level > -60 dB, and at least two >= 0.5 seeds in a run. A one-frame spike is rejected when both neighbor differences are >= 3.5 st and the neighbors agree within 2 st. A consistent fast glide remains visible. Unknown intervals remain empty, and the additional correction has the existing 25 ms support taper. The neural model, measured frame pitches and note segmentation are unchanged. New Draw strokes carry `support_version = 3`; they remain absolute over a Transition edit. Existing link/stroke policies keep their equations. Opening a saved project does not rewrite its envelopes; editing a link migrates that link in one Undo transaction.

`target.csv` now uses the same source sampler as the canvas, leaving source/target blank on unsupported audio. Its trust column is the voiced support edge gate. `analysis.csv` still contains all original measurements. No measured ReaPitch output is implied.

The supplied 20261002-214127 case has 185 frames and 9 notes. Display support increases from 110 to 120 original frame knots, including the rapid descent at 0.528 s and tails at 0.624/0.656 s. No pitch is transposed to obtain that result. The original -02 source was also checked with Praat, which agrees with the approximately MIDI 53 low portion; an automatic +12 st repair would be unjustified from this evidence.

Offline checks cover all eight eligible pairs at Amount 50%, exact zero Amount/outside-window/unknown-audio behavior, envelope interpolation within 0.28 cent on a 0.1 ms grid, and 29,661 exactly unchanged saved correction samples. A synthetic equal-endpoint bump drops from MIDI 62.85 to 61.34 at Amount 100%, while a steady slope stays unchanged to numerical precision. The actual Lua UI, numeric controls, reset, stale lock, strict deleted-pointer Glue cases, Undo/Redo/reopen, formant isolation and rollback after a silent native write failure are checked in `vocaligner-research/pitch-v012`. Older UI expectations that required permanent links and six controls have been replaced by the new contract; their DSP fixtures remain.

REAPER was not launched or controlled. Playback quality and measured native output still require a listening/render pass. To try it, reopen the same script, select Transition and use Amount 50%, Width 80 ms on one boundary. Existing v1–v3 links retain their old effect until edited.

The sections below record previous versions and are historical; their UI instructions are superseded above.

## Link audit repairs in 0.11.2

New or edited links use `link.version = 3`; the item evaluator remains `curve_version = 4`. Existing v1/v2 links keep their exact previous support and window rules until that particular link is edited. New Draw strokes carry `support_version = 2`; old strokes retain their saved interpolation and 5 ms support. Opening a project does not rewrite its envelopes.

The new shared support ends at the last confident frame's time plus its hop, bounded by the next frame and item length. Its release is 25 ms. During that final hop the raw/trend sample holds the last trusted frame instead of interpolating toward unreliable F0. The next untrusted frame still has zero additional correction. Confidence >= 0.5, level > -60 dB and the 3.5 st jump/run break remain; isolated one-frame spikes retain no acoustic support. Contour and target.csv use the same trusted hold where available; analysis.csv retains every original frame unchanged.

Auto-window reference pitches now use the median of confident frames in the nearest 40% of each note body, with the existing interior margin. The 80th-percentile band uses distances from that local median, bounded to 0.5–1.5 st, with 0.6 st for fewer than three frames. Empty sides fall back to the saved center. Detection remains based on source F0, independent of shifts or visual offsets. On the supplied Split of note 7 at 1.504 s, the window is 1.488–1.536 s (48 ms), versus the prior 16 ms, despite both halves retaining the parent's `center`.

End dragging solves both Scale and Bias from the requested span. The opposite actual endpoint is fixed throughout the gesture; the moving endpoint stops at the geometry, 25–200% Scale and +/-75% Bias bounds. Numeric Width and Shift+vertical intentionally retain symmetric scaling. The badge says "Voiced tails only" when the endpoints do not belong to one voiced run. No F0 is created across the dotted gap.

Offline B1/B2/B3/B4 predictions and the separate fixed-window B4 support comparison are kept in `vocaligner-research/pitch-v0112`. These are requested-correction predictions, not measured ReaPitch output. The actual case, legacy evaluator equality, saved policy versions, both UI edge gestures and the native API model are checked before copying the release. Native playback and listening remain a user verification step.

## Link and Draw follow-up in 0.11.1

The supplied [LINK_SPEC.md](LINK_SPEC.md) is retained unchanged as the proposal. New links use `link.version = 2`, with `scale` 0.25–2 instead of a fixed width. Their window follows confident source frames leaving A's center band and entering B's band, clipped by the note midpoints. Center bands use the 80th percentile of interior pitch distance, bounded to 0.5–1.5 st. Each side owns its half of a gap: similar note centers cannot mistake the next onset for the preceding departure. Source geometry windows are cached separately from edits, with bounded cache size.

Endpoints search outward for confident frames within 32 ms. Missing endpoints make the acoustic link inactive. Endpoint trends plus the note correction form the finite target. The same confidence/level/run support used by Draw gates the additional link correction. At unsupported times that additional correction is exactly zero; this does not cancel other pre-existing note or expression edits. Mix 0 is exactly the existing evaluator without the new link: v2 is applied over the existing base, so even its connection/window cannot change that base at Mix 0.

Shape changes the value blend separately from the Hermite slope terms. The proposed power warp followed by a quintic has an unbounded endpoint derivative at Shape 0.25; a smooth interior gate confines that warp and retains finite endpoint slopes. The final joining gate retains the outer predicted curve and derivative. No confidence multiplier attenuates the requested correction inside full voiced support.

The UI shows each eligible pair within 300 ms regardless of tool/selection, except in Bypass. Solid orange follows the predicted contour. Dots join its actual visible endpoints across missing F0; they are a visual guide, not synthesized pitch or a measured output. The middle grip uses the window's exact time midpoint. End ticks show width; end grips appear when the window is at least 24 px wide. End dragging resizes the window, middle dragging chooses Shape vertically or Bias horizontally, Shift adjusts Width and Alt adjusts Settle. Curve/Draw use Ctrl on the middle grip. Numeric Width is a percentage with actual milliseconds beside it. A hover/gesture badge reports the actual duration, Shape, Bias and Settle; it identifies painted ownership or a guide without trusted endpoints.

Draw can begin on a voiced tail within 150 ms of its owning note. Unknown F0 interrupts it. Cyan marks the painted trajectory. New strokes capture the original target anchors and compare them using the current note geometry, rather than keeping a sampled offset tied to an old link window. A later link change therefore preserves the absolute painted pitch; a later Curve edit can still move it. Captured anchors follow save, trim and Split/Join. Existing strokes retain their saved interpolation until replaced.

v1 links and older evaluator versions open unchanged. Only editing that specific v1 link migrates it to v2, in the same transaction as the new envelope and metadata. Consequently a restart alone does not repair a previously saved v1 link; move its grip or use its numeric controls. Undo restores the old version and envelope. Formant automation stays independent.

The archived 20261002-175034 case reproduced a v1 link correction down to -13.10 st in a 96 ms gap, and +24 st in the following 112 ms gap. The earlier eight-note case also fails the old support-zero regression. New v2 tests on both actual analysis files verify zero additional correction at unsupported times, Mix-zero identity, trusted endpoints, C0/C1 edges for Shape 0.25/1/4, saved state, final Draw ownership and split neutrality. The new audio model is not verified by these tests. An audible synthetic link with Shape 0.25 and Overshoot 50 ct measured 0.2670 ct maximum envelope interpolation error on a 0.1 ms grid.

The native API model checks unchanged v1 opening, a single migration Undo step, exact Undo/Redo/reopen, formant isolation and full rollback after silent native write failure. Offline previews use the actual Lua canvas and the supplied case/source WAV. REAPER was not launched or controlled; the new native GUI and rendered/listened audio still need a user pass.

The sections below describe the original 0.11.0 work; the v2 link and new-stroke rules above supersede their corresponding controls and capture mechanism.

Implemented from the transition audit on 2026-10-02. The original [TRANSITIONS_PLAN.md](TRANSITIONS_PLAN.md) is retained as historical research. Its claims about a universal 20 ms delay, missing vibrato fade-out, trust affecting every edit, and a faster second-order model are not implementation assumptions.

## What changes

- Analyze captures all selected audio items directly from REAPER, even after focusing another track inside Pitch. With no audio-item selection it uses the editor's active track. The queue is fixed at the click; each item retains its own transaction and failure report. Progress covers the whole queue.
- Curve moves the effective target. New handles are a final correction layer; the gesture solves the actual evaluator at the pointer. Flatten, trust and transition blending do not use the old approximate inverse. Flatten is retained.
- New Draw strokes are absolute pitch targets relative to Notes Shift. They override the existing base, legacy Draw and transition inside their interval. Later Flatten/Modulation/Drift changes preserve these strokes. Later Curve gestures can move them. The stroke captures the existing final Curve offset to avoid double application.
- One Draw gesture can cross connected notes. Copies share one trajectory and only the outer fades. Unknown F0 interrupts the trajectory instead of interpolating across noise. Reliable support is confidence >= 0.5, audible level > -60 dB and no >= 3.5 st adjacent jump; a 5 ms support-edge taper remains. This is a voiced-support policy, not a claim that the estimated pitch is exact.
- Double-click in Draw restores the note's pitch/expression, manual points, drawings and incoming link, retaining formant. Alt + double-click removes only drawings. Reset does not directly clear the next note's incoming link.
- Orange links remain visible between connected notes. Clicking them does not switch the selected tool. In Curve and Draw, Ctrl + drag on the small orange grip accesses the link; ordinary dragging keeps the chosen tool.
- Transition: vertical movement adjusts Shape; horizontal movement adjusts Bias; Shift + vertical adjusts Width; Alt + vertical adjusts Settle. Width, Shape, Bias, Settle, Mix and optional Overshoot also have numeric controls. A gesture badge shows the current values.
- Vibrato adds Release and Growth, and an explicit Add/Replace button. Replace removes source modulation only while generated vibrato is active. It does not overwrite the Modulation knob. Depth remains 0–200 cents. Existing onset and 20 ms release defaults remain valid; Bounds retains the original expression span.

## Compatibility and state

Opening or reanalyzing a corrected item keeps its saved evaluator version. v1/v2/v3 remain readable. A new item uses v4; an acoustic edit adopts v4 in the same native transaction as its envelope and metadata. In v4, existing v3 anchors, drawings and transitions retain their legacy equations. New behavior is represented by new fields, so adopting v4 alone is neutral for v3.

New data: target_anchors, target-tagged drawings with a shared gesture ID and captured Curve offset, and a versioned link object on its right-hand note. A link keeps the owning note ID; splitting a note does not accidentally attach that link to the new internal boundary. Identical split siblings resolve as the original acoustic span and can be joined without changing it. Joining independently edited notes remains blocked rather than discarding curves. Time adaptation moves manual points and captured offsets together. New fields participate in cache comparisons, persistence, Reset and export.

Old v1/v2 items retain the established upgrade-on-acoustic-edit behavior; opening and metadata-only Split still preserve their saved version. Plain v3 -> v4 adoption is tested for exact equality with all legacy expression and drawings enabled. New Curve handles are shown separately from the preserved legacy anchor layer.

## Link calculation

A new link uses a finite monotone Hermite core with explicit endpoint target values and slope estimates from the resulting note curves. A smooth joining gate preserves the outer curve and its derivative at both window edges, including when core slopes are limited. Shape and Bias are independent of Width. Settle removes residual variation within the target blend; Mix controls that blend. Overshoot is a compact optional addition which vanishes with its derivative at the boundaries and defaults to zero.

The window is recomputed from current note geometry. Link coefficients are cached within each evaluation pass. Existing legacy links use the old formula until that specific link is edited. Pitch links do not change formant automation. This is an editor curve, not a physical model of a singer or a model of ReaPitch's output.

## Native writing and measurements

The editor checks ownership before applying. It compares the desired pitch/formant points with actual points, skips an unchanged channel, and replaces only the differing interval between retained knots. It reads back the complete result. A write/readback/save failure restores the complete item chunk through the existing transaction. The report includes inserted/removed/total point counts and recent timing p50/p95, alongside overall max.

No automatic delay compensation, slew limiter, forced modulation reset, or second-order transition model is enabled. The white/orange curve is the source estimate plus requested correction. It is not an audio-output measurement.

## Evidence and remaining audio check

Offline Lua tests cover the actual Curve/Draw handlers, trust 0/0.5/1, Flatten 0/0.8/1, linked edges, Draw over existing Curve, interrupted strokes, neutral v3/v4, Split/Join, native API model, Undo/Redo/reopen, partial writes, readback-failure rollback, formant isolation and Analyze selection precedence. A dense link scenario measured a maximum linear-envelope error of 0.272 cents on a 0.1 ms grid. This is a case result, not a universal error bound.

The archived 20261002 B/C pair was rechecked read-only, including its actual WAVs with Praat. Its saved envelope differs from target.csv by at most 0.2365 cents on the exported grid. A common-mask lag scan on original 16 ms analysis frames gives an 18 ms optimum for the short vibrato region, with 18/21 frames retained. The Draw-64 region prefers 0 ms; the Draw-63 common mask has only two frames and is inconclusive. This does not establish universal ReaPitch latency. Independent Praat and Swift estimates also disagree.

REAPER was not launched or controlled. The archived pair contains old v3 output; it cannot verify the new v4 sound. Complete the native pass with bypass, +1 st, one gentle/one steep link, and 0.4 st vibrato, using identical source/render boundaries and known processing rate. Check [TEST_CASE.md](TEST_CASE.md), native Undo/Redo, split/trim, listen to A/B, and export the new B/C pair before changing delay or slew policy.
