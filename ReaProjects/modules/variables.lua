--@noindex
--NoIndex: true

MAIN_PARAMS = {
    dock               = '',
    pinned             = false,
    wnd_w              = 700,
    wnd_h              = 800,
    last_x             = 50,
    last_y             = 50,
    last_sort          = {'opened', 1},
    individual_path    = "",
    current_media_path = true,
    general_media_path = {false, individual_path},
    individ_media_path = false,
    default_img_w      = 500,
    default_img_h      = 500,
    days_bef_reminder  = 5,
    dedline_warm_col   = "#e40a27",
    elevation_warming  = 13,
    last_h_list        = 20,
    last_type_opened   = 1, -- 0 its list mod, 1 - list

    def_round_rect_win = 14, --min 2 max 20
    other_roundrect_wd = 6,  --min 1 max 12
    global_animate     = true,

    max_visible_proj   = 150,
    key_touchscroll    = "ctrl+shift"
}

round_rect_window     = MAIN_PARAMS.def_round_rect_win
round_rect_list       = MAIN_PARAMS.other_roundrect_wd
GLOBAL_ANIMATE        = MAIN_PARAMS.global_animate
KEY_FOR_TOUCHSCROLL   = MAIN_PARAMS.key_touchscroll

max_visible           = MAIN_PARAMS.max_visible_proj

deadline_warning_color = MAIN_PARAMS.dedline_warm_col
elevation_warning      = MAIN_PARAMS.elevation_warming

DEF_IMG_W              = MAIN_PARAMS.default_img_w
DEF_IMG_H              = MAIN_PARAMS.default_img_h


INDIVIDUAL_path       = MAIN_PARAMS.individual_path
CURRENT_media_path    = MAIN_PARAMS.current_media_path
GENERAL_media_path    = MAIN_PARAMS.general_media_path
INDIVIDUAL_media_path = MAIN_PARAMS.individ_media_path


CUSTOM_IMAGE_local    = 'customImages' .. sep
CUSTOM_IMAGE_global   = cur_path .. CUSTOM_IMAGE_local
TYPE_module           = MAIN_PARAMS.last_type_opened