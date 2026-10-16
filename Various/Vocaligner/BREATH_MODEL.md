# Breath detector in Vocaligner 0.7.0

The detector considers surrounding audio as well as the current spectrum. This addresses the reported short marks at the beginning of a breath and confusion with consonants. Version 0.9.5 preserves this model and its settings while moving the initial cleanup DSP into a checked private EEL kernel, with Lua/REAPER FFT as fallback. The application starts no Python process or network request.

## Using it

Open **Breaths** and select one item with **Auto** enabled. Analysis and application follow automatically. With Auto off, **Get** performs both steps. Start a comparison with **Sensitivity 50, Minimum duration 80 ms, Join gaps 160 ms, Find edges 120 ms**. Existing saved knob values are retained; 0.6 settings around sensitivity 100 are substantially more permissive with this model.

- Sensitivity changes which sounds qualify. It is independent of Reduction and De-ess.
- Reduction uses one fixed gain per breath. Target level instead lowers the event's 80th-percentile source RMS toward the target, limited by Max cut, without boosting quieter audio. This measurement excludes take volume, FX and the master chain.
- Join gaps connects fragments only when the intervening sound has compatible spectrum and level.
- Find edges searches around each seed, stopping at silence, protected sounds, acoustic changes or insufficient model support. It cannot guarantee phonetic boundaries.
- Minimum duration counts the detected seed plus supported boundary extension. Empty joined gaps do not count. A 20 ms minimum seed is required before any extension.
- Fade in/out remain inside the event. One joined breath has one gain and two outside fades, avoiding a series of confidence-dependent dips.

Drag the **top time ruler**, not the waveform body, to select a processing interval. Existing work outside it is preserved. Escape clears scope; Get or a released control can then update the full item. A global selection outside the item no longer creates an empty processing range.

## Adapting a take and retaining work

Select 40 ms to 2 seconds of one clear sound and use **Learn breath** or **Keep sound**. These alter similar sounds in the take; **Reset learning** removes the examples. Right-click a candidate to exclude only that occurrence. Poor or mixed examples can make detection worse.

Up to eight positive and eight negative spectral examples are saved per take GUID in project ExtState. This intentional project data survives saving/reopening the project. It contains statistics, not audio, and is independent of envelope Undo.

The analysis, settings and original/layer envelopes additionally survive closing/reopening 0.7 **within the same REAPER session**. They are separated by project and can be inherited by a verified split child that uses the same covered source. REAPER restart ends this session cache. See [README.md](README.md) for the 0.6 upgrade boundary and cache details.

De-ess and Breaths own separate layers. Final reduction is `max(deess, breath)`, multiplied by the original envelope; cuts do not add. Remove affects only the active tool. Each layer keeps its requested point detail, including existing work outside a partial edit.

## Features and model

The 32 kHz analysis uses a centered 1024-sample periodic Hann window and a 320-sample hop (10 ms). The 55-feature contract contains:

1. The previous 24 features: sixteen normalized log energy bands below 8 kHz, flatness, tonal peak fraction, zero-crossing rate, relative RMS, short level change, past/future 250 ms level context and spectral motion.
2. Nineteen local spectrum/flatness/tonality/ZCR averages over 130 ms.
3. Six relative level extrema over centered 310, 910 and 2010 ms windows.
4. Six preceding/following flatness, tonality and ZCR context averages.

`breath-context-2` contains 160 boosted trees, 4,630 nodes, at most 15 leaves and depth five per tree. Default entry threshold is 0.55; sensitivity changes it on a logit scale. Scores are classifier outputs, not calibrated probabilities. The coefficients are in `breath_model.lua`; scikit-learn is only an offline training dependency.

EEL evaluates blocks of at most 128 frames. Feature construction, model scores, per-take adaptation and event grouping are separately cached. Changing gain, target or fades does not rerun classification. Lua evaluates the same trees if the EEL self-check or execution fails. Sliding context extrema use linear-time queues.

## Data and evaluation

The base corpus remains the manually annotated Respiro-en dev-clean subset of LibriTTS-R: 520 clips, 38 speakers and 284,028 frames. The existing split has 26 training, six validation and six internal regression-test speakers. Training adds the five locally supplied recordings with explicit intervals: three Ture recordings, one Leila and one Dastan recording. Their intervals contain **33 distinct breaths** after merging the overlapping labels in `-551.wav`. Times were treated as item-relative and read with the supplied source offsets. The separately marked exhale is excluded from negative training/evaluation. Unlabelled `-38-glued.wav` is inspected but never treated as an all-negative training example.

User annotation frames receive weight eight relative to corpus frames. Architecture and processing choices were checked during development; the following figures are development/regression results, not an untouched benchmark.

Matching uses one-to-one event IoU of at least 0.30. Covered-time measurements also expose incomplete and overlong boundaries.

| Five annotated user recordings | Matched / 33 | Unmatched events | Reference time covered | Marked time outside reference |
| --- | ---: | ---: | ---: | ---: |
| 0.6 defaults: sensitivity 50, minimum 80 ms | 12 | 3 | 42.2% | 1.18 s |
| 0.6 report settings: sensitivity 100, minimum 40 ms, join 69 ms, edges 25 ms | 23 | 44 | 70.5% | 6.00 s |
| 0.7 defaults, model fitted using these annotations | 33 | 0 | 99.5% | 0.77 s |
| 0.7 development cross-validation, each speaker excluded from fitting | 29 | 4 | 73.7% | 0.72 s |

The 33/33 result is a fit check on supplied examples, not proof of generalization. In cross-validation all three Ture clips are excluded together; adjacent frames and recordings of that voice do not leak into its fit. This uses only three user speakers and is still a small development set. At the old permissive 100/40/69/25 settings, the final 0.7 model finds all 33 but also adds 15 unmatched events.

The unchanged internal corpus test contains 70 reference breaths in 69 clips from six speakers never included in fitting. Compared using the complete detectors at defaults:

| Internal corpus regression | Matched | Unmatched | Event precision / recall | Covered-time precision / recall |
| --- | ---: | ---: | ---: | ---: |
| 0.6 | 68 / 70 | 20 | 77.3% / 97.1% | 85.6% / 87.1% |
| 0.7 | 69 / 70 | 21 | 76.7% / 98.6% | 82.1% / 94.2% |

The new detector covers more of the annotated breath duration. On this corpus it also marks more time outside annotations: 5.76 s versus 4.11 s. Those totals measure the whole marked range, not audio receiving more than 1 dB attenuation. There is no universal accuracy gain: consonants, noise and boundaries still need review. Singing, arbitrary microphones/effects, inhale versus exhale and a controlled listening comparison against RX/Waves remain unverified.

## Reproduction and checks

Research scripts, manual labels, frozen split IDs, predictions and metrics are under `L:/Projects/vocaligner-research/breath-v07`; the unchanged corpus and earlier model are in `breath-v06`. Main files are `context_study.py`, `export_model.py`, `final_evaluation.py`, `final_metrics.json`, `final_user_events.json`, `validate_model.py` and `validate_integration.py`.

- Actual Lua FFT and all 55 runtime features match offline extraction, including item edges.
- scikit-learn, Lua and an actual Cockos WDL EEL VM agree on 4,099 real feature rows; maximum EEL difference is 1.11e-16.
- Offline checks cover fixed gain, target/no boost, exclusions, learning, cancellation, both layer orders, original envelopes, rollback and Undo/Redo.
- Workflow tests cover Auto/Get, cache reload, move, trim, split with a new take GUID, envelope display flags, outside time selection, project/session isolation and rejection of executable-looking or truncated cache data.
- UI call-model tests verify ruler-only time selection, waveform click/pan and independent overview navigation.

These tests do not constitute native REAPER playback, listening or GUI verification. No REAPER process or project action was launched during implementation.

Sources: [Respiro-en annotations](https://github.com/ydqmkkx/Respiro-en), [LibriTTS-R / OpenSLR 141](https://www.openslr.org/141/) and [third-party notices](THIRD_PARTY_NOTICES.txt). Corpus annotation SHA-256: `9f785ff4bc78839ea18df2a66d20c6de2ed49019e3d85b2533553335a4df8f00`. Audio recordings are not shipped with the application.
