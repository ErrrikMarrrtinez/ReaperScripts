-- @noindex
local M={defaults={},controls={}}
for _,mode in ipairs({'click','mouth'}) do
 local p=mode..'_'
 M.defaults[p..'sensitivity']=50;M.defaults[p..'reduction']=12;M.defaults[p..'strength']=100
 M.defaults[p..'skew']=mode=='mouth' and 2 or 0
 M.defaults[p..'widen_ms']=.5;M.defaults[p..'fade_ms']=.6
 M.defaults[p..'protect']=70;M.defaults[p..'detail']=100
 M.controls[mode]={
  {p..'sensitivity','Sensitivity',0,100,'%.0f%%','Higher finds weaker candidates. Does not change reconstruction strength.'},
  {p..'strength','Repair strength',0,100,'%.0f%%','Blend the original samples with bidirectional prediction. Zero restores this session\'s original samples.'},
  {p..'skew','Frequency skew',-10,10,'%+.1f','Bias detection toward lower or higher frequency transients. Does not EQ the audio.'},
  {p..'widen_ms','Widen',0,8,'%.2f ms','Extend the reconstructed core on both sides. Long repairs can remove useful voice too.'},
  {p..'fade_ms','Join',.1,5,'%.2f ms','Smooth sample-level transitions into the reconstructed waveform.'},
  {p..'protect','Protect attacks',0,100,'%.0f%%','Reduce scores for repeating voice pulses and sustained note/consonant onsets. Zero disables this protection.'},
 }
end
return M
