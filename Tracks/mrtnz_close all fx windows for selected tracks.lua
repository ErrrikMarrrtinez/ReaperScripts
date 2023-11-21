-- @description Close all fx windows for selected tracks
-- @author mrtnz
-- @version 1.00
-- @about
--   Close all fx windows for selected tracks

function close_tr_fx(tr)
    local fx = reaper.TrackFX_GetCount(tr)
    for i = 0, fx-1 do
      if reaper.TrackFX_GetOpen(tr, i) then
        reaper.TrackFX_SetOpen(tr, i, 0)
      end
      if reaper.TrackFX_GetChainVisible(tr) ~= -1 then
        reaper.TrackFX_Show(tr, 0, 0)
      end
    end
  
    local rec_fx = reaper.TrackFX_GetRecCount(tr)
    for i = 0, rec_fx-1 do
      i_rec = i + 16777216
      if reaper.TrackFX_GetOpen(tr, i_rec) then
        reaper.TrackFX_SetOpen(tr, i_rec, 0)
      end
      if reaper.TrackFX_GetRecChainVisible(tr) ~= -1 then
        reaper.TrackFX_Show(tr, i_rec, 0)
      end
    end
  end
  
  local countSelTracks = reaper.CountSelectedTracks(0)
  
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  
  for i = 0, countSelTracks-1 do
    local tr = reaper.GetSelectedTrack(0, i)
    close_tr_fx(tr)
  end
  
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock('Close FX for selected tracks', 2)
  