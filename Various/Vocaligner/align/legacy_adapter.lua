-- @noindex
local M={}
-- Delegation preserves the existing analysis, parameter scheduling, low-match
-- auto-apply and Restore code paths. No legacy DSP or warp formulas are copied.
for _,method in ipairs({'start','tick','settings_changed','control_released','apply','restore','cancel','diagnostics'})do
  M[method]=function(app,legacy,...)return legacy[method](app,...)end
end
return M
