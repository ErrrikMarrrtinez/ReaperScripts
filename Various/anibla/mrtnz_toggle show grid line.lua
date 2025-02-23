--@noindex
--NoIndex: true



                                                                                                                                                                                                                local r=reaper;if not r.SNM_SetIntConfigVar then r.ShowMessageBox("SWS Extension not installed or outdated","Error",0)return end;local c=r.SNM_GetIntConfigVar("rulerlayout",0);local b=32;local n=(c&b)==0 and (c|b) or (c&(~b));r.SNM_SetIntConfigVar("rulerlayout",n);r.TrackList_AdjustWindows(false);r.UpdateTimeline()
