hl.config({
    general = {
        gaps_in = 3,
        gaps_out = 8,
        border_size = 2,
        col = {
            active_border = {
                colors = {var_primary, var_secondary},
                angle = 45,
            },
            inactive_border = var_outline_variant,
        },
        layout = "dwindle",
        resize_on_border = true,
    },
    decoration = {
        rounding = 8,
        blur = {
            enabled = true,
            size = 6,
            passes = 2,
            new_optimizations = true,
            ignore_opacity = true,
            xray = true,
        },
    },
})
