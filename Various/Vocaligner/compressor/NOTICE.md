# Source and license

The compressor transfer curve, circular Julian knee, RMS follower and attack/release equations in `engine.lua` are adapted from **Envelope-based Compressor v2 (Julian mod)**, version 2.20, by **EUGEN27771**. The source file declares **GPL v3**. The adapted code is provided under GNU GPL version 3; see [LICENSE_GPL3.txt](LICENSE_GPL3.txt).

Reference inspected: `2ReaperScripts/gen_Envelope-based Compressor v2 (Julian mod).eel` and `2ReaperScripts/inc/AudioFunctions.eel` in the user's installed `eugen_legacy` scripts. Original author page: <https://forum.cockos.com/member.php?u=50462>.

Modified 2026-10-03 for Vocaligner: private ReaImGui EEL functions, linked channel power, two-second RMS storage, cached PCM and detector passes, independent gate, bounded block execution and ordered gain composition. Legacy GUI, preset storage and SWS envelope activation calls are not included. Parameters and processing conventions are documented in [README.md](README.md).

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for details.
