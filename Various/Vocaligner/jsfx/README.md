# Vocaligner Pitch Meter

An optional JSFX that measures the audio reaching it, passes the audio through
unchanged, and shares pitch frames with Vocaligner's **Check** view and export
action. It is separate from the editor's source-pitch prediction and ReaPitch
correction. It does not require SWS or any external process.

## Installation

The Vocaligner ReaPack manifest provides `Vocaligner Pitch Meter.jsfx` with the
`effect` type, so ReaPack installs it under REAPER's Effects directory. It is not
installed as an executable ReaScript action.

For manual installation, open **Options → Show REAPER resource path**, create
`Effects/Vocaligner`, and copy `Vocaligner Pitch Meter.jsfx` there. Refresh the
FX browser and search for **Vocaligner Pitch Meter**.

Add it after ReaPitch in the edited take's FX chain, or to that item's vocal
track. Enable Analyze in the meter and play the passage. A take meter before
ReaPitch measures the source; overlapping audible items can make a track meter
ambiguous. Check reports these conditions in the editor.

## Export

Run **Ruin Vocals - Export Pitch Meter** with the relevant items or track selected
after playing the passage through the meter. The action writes `frames.csv`,
`notes.csv` and `report.txt` next to the project and can create a MIDI item from
the detected notes. The meter publishes data through REAPER's built-in `gmem`
API; the export action writes the files.

`Vocaligner Pitch Meter - Export.lua` is the internal implementation. The Main
action launcher is `../mrtnz_Vocaligner - Export Pitch Meter.lua`.
