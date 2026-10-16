# Hybrid timing (experimental)

In Classic, turn on **Hybrid edits**. It is off by default. The usual Classic
Stretch planner and Advanced remain available. Switching the checkbox restores
applied timing before building the other output, so edits do not accumulate.

Hybrid uses the cached Classic match path to choose how each phrase should move.
It can move a phrase without new stretch markers, shorten quiet shoulders, or
compress/expand its sustained parts using REAPER's stretcher. Detected attacks
keep their captured duration. It does not cut out voiced vowel interiors.

Choose **Natural**, **Balanced**, or **Tight**. These change the tradeoff between
timing error and deformation; they do not improve the underlying match evidence.
The three main controls are:

- **Strength**: follow the reference more closely. Zero restores the complete
  captured item state and original item count.
- **Compression**: make useful shortening less expensive and allow a larger
  shortening range. It does not shorten words that already fit. Low values favor
  moving intact phrases; high values can compress sustained parts much more often.
- **Stretch limit**: a hard bound on local duration changes. Compression cannot
  bypass it. Protected attacks retain rate 1 relative to the captured timing.

Tolerance, Search range and Marker fade are under **Hybrid timing options**.
Changing timing controls uses cached source features and applies on release.
Search/profile changes reuse the existing rematching flow. Lane colors distinguish
rigid moves, compression and expansion; counts describe the planned operations.

## How decisions are made

1. Find quiet pauses on the original frame grid. Natural requires 110 ms;
   Balanced 65 ms; Tight 45 ms and a less conservative low-energy threshold.
   Cuts preserve both sides. Trimming uses a separate, much stricter threshold
   and retains at least 35 ms of shoulder around detected content. Both thresholds
   are capped relative to the activity gate and loud level; this is not a speech classifier.
2. Keep a no-edit choice for every fragment. With enough reliable path samples,
   also fit rigid movement, two levels of duration change, and a local elastic map
   for continuous phrases. The fit gives onset evidence more weight. Detected
   attacks and captured item fades do not deform.
3. Score timing residual, deformation, movement and quiet trimming. Compression
   changes the penalty and lower duration bound independently of Strength.
4. Choose a compatible sequence by dynamic programming. Fragments may not overlap
   or start before project time zero, exceed Search range, or violate Stretch limit.
   Existing source-map knots remain in the elastic map. Compare the resulting
   edit with an intact-item alternative; quiet pauses do not force unnecessary splits.
5. Restore the captured items before each new apply, split in the original source
   timeline, then write the chosen moves and local maps. Pure rigid moves on
   previously unwarped takes use item position/offset/length without new markers.

This is a constrained heuristic, not phoneme recognition or a perceptual quality
predictor. Incorrect DTW evidence, missed attacks, quiet consonants and breaths
can still require manual correction. Tight is a stronger preference for timing
accuracy, not a promise that more processing will sound better.

The operation counter reports even small duration changes as compression or
expansion. In the initial 0.13.5 build, changes under 0.5% were incorrectly labelled
as movement. Version 0.13.6 fixes that label; a displayed REAPER ratio of 1.00x can
still conceal a small change due to rounding. "Moved" means rigid captured timing.

## State, compatibility and recovery

Take Volume is transported from the captured envelope. Split seams get short
fades inside the quiet shoulders. Full item chunks, item GUIDs and track identity
protect the transaction. A changed child, locked item or unknown native state is
rejected before another write. A failed split or marker write restores the state
from before that attempt; a rollback failure explicitly requests native Undo.

Restore works in the current captured session. Native Undo/Redo states are
recognized by GUID and complete item state even if REAPER recreates pointers.
The in-session history is bounded to 64 states and approximately 32 MiB per dub
(the captured and most recent states always remain). Older native Undo states may
require a new capture. Reopening the script does not reconstruct a Hybrid owner;
use REAPER Undo for edits from the previous script session.

The first version accepts single-take forward sources and non-overlapping grouped
items. Existing piecewise-linear source markers and captured take Volume are
supported. It refuses take FX, owned Pitch corrections, other take automation,
section/reverse sources and pre-existing overlapping groups. Those need separate
verified retiming support. Track processing stays on the track and track automation
stays in project time. Restore Hybrid before switching Align engines or doing
further Cleanup/Pitch work on the fragments. Cleaner recipe ownership is not
transported across the new fragment topology; capture again for that workflow.

## Research and validation

The design draws on Driedger and Mueller's *A Review of Time-Scale Modification
of Music Signals* (2016), especially transient preservation (section 4.3), the
different artifacts of time-domain and phase-vocoder stretching (4.2, 5.5), and
nonlinear time maps (7.1):
https://www.audiolabs-erlangen.de/content/resources/MIR/00_PCD_AudioLabs/2016_DriedgerMueller_TSMOverview_AppliedSciences_ePrint.pdf

The paper reviews audio stretching; it does not supply this edit-selection
objective. Hybrid does not implement its harmonic/percussive separation or a new
WSOLA/phase-vocoder engine. REAPER performs the actual elastic rendering.

External Lua fixtures check rigid and compressed phrases, protected attacks,
collision prevention, all integer Strength values, source rates and preview gaps.
Host mocks check envelope transport, exact zero/Restore, repeated application,
changed-child rejection, rollback failures and Undo/Redo with recreated pointers.
Existing Classic numerical, grouped-role, guided-Advanced and cleanup checks are
run against the combined tree. Native REAPER behavior and listening quality still
need verification on representative vocal material.
