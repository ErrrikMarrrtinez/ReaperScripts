--@noindex
--NoIndex: true


  

MAIN_PARAMS = {
    dock               = '',
    pinned             = false,
    wnd_w              = 700,
    wnd_h              = 800,
    last_x             = 50,
    last_y             = 50,
    sort               = 'opened', --opened
    sort_dir           = 1,        --first last opened
    sort_type          = 7,        --table 'first>last'
    current_media_path = true,
    general_media_path = {false, ""},
    individ_media_path = false,
    default_img_w      = 500,
    default_img_h      = 500,
    days_bef_reminder  = 5,
    dedline_warm_col   = "#e40a27",
    elevation_warming  = 13,
    heigh_elems        = 24,
    last_type_opened   = 1, -- 0 its list mod, 1 - list

    def_round_rect_win = 14, --min 2 max 20
    other_roundrect_wd = 6,  --min 1 max 12
    global_animate     = true,

    max_visible_proj   = 150,
    key_touchscroll    = "ctrl+shift"
}

round_rect_window      = MAIN_PARAMS.def_round_rect_win
round_rect_list        = MAIN_PARAMS.other_roundrect_wd
GLOBAL_ANIMATE         = MAIN_PARAMS.global_animate
KEY_FOR_TOUCHSCROLL    = MAIN_PARAMS.key_touchscroll

max_visible            = MAIN_PARAMS.max_visible_proj

deadline_warning_color = MAIN_PARAMS.dedline_warm_col
elevation_warning      = MAIN_PARAMS.elevation_warming

DEF_IMG_W              = MAIN_PARAMS.default_img_w
DEF_IMG_H              = MAIN_PARAMS.default_img_h

--



CUSTOM_IMAGE_local     = 'customImages' .. sep
CUSTOM_IMAGE_global    = cur_path .. CUSTOM_IMAGE_local
local entry_find

COL0  = "#1a1a1a" -- main bg col \ def_bg_color
--list and header
COL1  = "transparent" --#5a5a5a" -- rect_bg_heading border\all border list \ #5a5a5a
COL2  = "#4a4a4a" -- bg heading  \ 4a4a4a
COL3  = "#2a2a2a" -- bg list \ 2a2a2a
--popup
COL4  = COL3..50 -- shadow bg
COL5  = COL1..75-- border \hex_darker(COL0, -1.2)
COL6  = COL1 -- bg \hex_darker(COL0, -0.7)
--ENTRY
COL7  = "#6a6a6a" -- border \6a6a6a
COL8  = "#2a2a2a" -- bg \3a3a3a
--ELEMENTS
COL9  = "#3a3a3a" -- odd \3a3a3a
COL10 = "#323232" --even \323232

COL11 = "#6a6a6a" -- mouseenter \6a6a6a
COl12 = "#9a9a9a" -- selected \9a9a9a

COL13 = COL0 .. 50 -- def pad color\ 
COL18 = "#3a3a3a"