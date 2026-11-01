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

-- File pickers tile unless their app names a parent window, and GTK reopens them at the last tiled size
hl.window_rule({
    name = "portal-file-picker",
    match = {
        class = "xdg-desktop-portal-gtk",
    },
    float = true,
    center = true,
    size = "1000 700",
})

-- Pickers that apps draw themselves can only be told apart by title
hl.window_rule({
    name = "app-file-picker",
    match = {
        initial_title = "(Open|Save|Save As|File Upload|Add Folder to Workspace|Enter name of file to save to.*|(Open|Save|Select|Choose) (one or multiple )?([Ff]iles?|[Ff]olders?|[Dd]irectory)( .*)?)",
    },
    float = true,
    center = true,
    size = "1000 700",
})

-- OnlyOffice's message boxes use their own class and open in the corner of the monitor
hl.window_rule({
    name = "onlyoffice-dialogs",
    match = {
        class = "DesktopEditors",
    },
    center = true,
})

-- OnlyOffice's tooltips have a transparent margin for their shadow: xray blur fills it with wallpaper
hl.window_rule({
    name = "onlyoffice-no-blur",
    match = {
        class = "ONLYOFFICE",
    },
    no_blur = true,
})

-- VLC's menus are separate windows: fading them in shows the desktop through them for a moment
hl.window_rule({
    name = "vlc-no-anim",
    match = {
        class = "vlc",
    },
    no_anim = true,
})

-- Steam repaints its whole window on every change, and blurring behind it adds a pass each time
hl.window_rule({
    name = "steam-no-blur",
    match = {
        class = "steam",
    },
    no_blur = true,
})

-- Sushi, on Space in Nemo: it can't size itself here because GTK gets no monitor for its window on Hyprland
hl.window_rule({
    name = "quick-look",
    match = {
        class = "org.gnome.NautilusPreviewer",
    },
    float = true,
    center = true,
    size = "1100 800",
})
