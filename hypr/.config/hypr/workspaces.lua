-- #############################

-- ## WINDOWS AND WORKSPACES ###

-- #############################

-- See https://wiki.hypr.land/Configuring/Window-Rules/ for more

-- See https://wiki.hypr.land/Configuring/Workspace-Rules/ for workspace rules

-- windowrule{

-- name = center-dialogs

-- match:xwayland = true

-- center = on

-- pin = on

-- }
hl.window_rule({
    name = "transparent-code",
    match = {
        class = "com.microsoft.VSCode",
    },
    opacity = 0.9,
})

-- move = (cursor_x) (cursor_y)
hl.window_rule({
    name = "copy-q-popup",
    match = {
        class = "com.github.hluk.copyq",
    },
    float = true,
    size = "500 600",
    opacity = 0.95,
})
