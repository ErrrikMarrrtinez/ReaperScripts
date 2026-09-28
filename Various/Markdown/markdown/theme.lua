-- @noindex
local Theme = {}
Theme.graphite={background=0x1C1D21FF,text=0xDEDDE5FF,muted=0x898795FF,heading=0xF1EFF8FF,
  accent=0xAB91EBFF,link=0xB6A0F1FF,border=0x3A3943FF,panel=0x24252AFF,code=0xD9B98CFF,
  code_bg=0x292A31FF,highlight=0xBE994344,selection=0x9472DB66,table_header=0x302C3AFF,
  table_alt=0x24242BFF,hover=0xAB91EB22,success=0x79B99BFF,warning=0xDFB976FF}
Theme.paper={background=0xFAF9F6FF,text=0x353340FF,muted=0x8B8594FF,heading=0x27222FFF,
  accent=0x7554AEFF,link=0x7754B9FF,border=0xDED9E4FF,panel=0xF0EDEFFF,code=0x9D5F30FF,
  code_bg=0xEEEAEFFF,highlight=0xF0CF7366,selection=0xA58AD45A,table_header=0xEDE7F2FF,
  table_alt=0xF4F1F6FF,hover=0x8663B91C,success=0x398363FF,warning=0xA7742CFF}
Theme.sand={background=0x24211EFF,text=0xDFD4C6FF,muted=0xA29787FF,heading=0xF3E7D7FF,
  accent=0xDCB682FF,link=0xDBC097FF,border=0x464035FF,panel=0x2D2924FF,code=0xDCA98DFF,
  code_bg=0x322C27FF,highlight=0xCDA85A44,selection=0xC49E6866,table_header=0x383027FF,
  table_alt=0x2A2622FF,hover=0xDCB68220,success=0xA5B58AFF,warning=0xE1B574FF}
function Theme.get(name) return type(name)=='table' and name or Theme[name or 'graphite'] or Theme.graphite end
return Theme
