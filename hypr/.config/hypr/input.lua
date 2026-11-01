-- ############

-- ## INPUT ###

-- ############

-- https://wiki.hypr.land/Configuring/Variables/#input
hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "devastator:map_sclk",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
            -- Clickpad without physical buttons: finger count picks the button, not a corner zone
            clickfinger_behavior = true,
            scroll_factor = 0.6,
        },
    },
    gestures = {
        workspace_swipe_distance = 500,
        workspace_swipe_cancel_ratio = 0.25,
        workspace_swipe_forever = true,
    },
    cursor = {
        hide_on_key_press = true,
    },
})

-- See https://wiki.hypr.land/Configuring/Gestures
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})
hl.gesture({
    fingers = 3,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.exec_cmd("pkill -x rofi; ~/.local/bin/sound.sh walker; walker -m windows"))
    end,
})
hl.gesture({
    fingers = 3,
    direction = "down",
    action = "special",
    workspace_name = "special",
})
hl.gesture({
    fingers = 4,
    direction = "up",
    action = "fullscreen",
})
hl.gesture({
    fingers = 4,
    direction = "down",
    action = "float",
})

-- See https://wiki.hypr.land/Configuring/Keywords/#per-device-input-configs for more
hl.device({
    name = "elan0511:00-04f3:303f-touchpad",
    accel_profile = "adaptive",
    sensitivity = 0.2,
})
hl.device({
    name = "mi-silent-mouse",
    accel_profile = "adaptive",
    sensitivity = 0,
})
hl.device({
    name = "semico-usb-keyboard",
    numlock_by_default = true,
})
