-- ###############

-- ## SOURCES  ###

-- ###############
require("hyprland-gui")
require("colors")
require("input")
require("keybindings")
require("altcodes")
require("monitors")
require("theme")
require("workspaces")

-- ##############

-- ## ACTIONS ###

-- ##############
hl.on("hyprland.start", function()
    hl.exec_cmd("[workspace special:background silent] tailscale down")
    hl.exec_cmd("[workspace special:background silent] hypridle")
    hl.exec_cmd("[workspace special:background silent] udiskie")
    hl.exec_cmd("[workspace special:background silent] sh -c '~/.local/bin/waybar-window-rules.py; ~/.local/bin/waybar-layout.sh init; exec waybar'")
    hl.exec_cmd("[workspace special:background silent] ~/.local/bin/memory-guard.sh")
    hl.exec_cmd("[workspace special:background silent] awww-daemon")
    hl.exec_cmd("[workspace special:background silent] swaync")
    hl.exec_cmd("[workspace special:background silent] nm-applet --indicator")
    hl.exec_cmd("[workspace special:background silent] copyq --start-server")
    hl.exec_cmd("[workspace special:background silent] elephant")
    hl.exec_cmd("[workspace special:background silent] walker --gapplication-service")
    hl.exec_cmd("[workspace special:background silent] localsend --hidden")
    hl.exec_cmd("[workspace special:background silent] xfce4-power-manager")
    hl.exec_cmd("[workspace special:mail silent] betterbird")
end)

-- ############################

-- ## ENVIRONMENT VARIABLES ###

-- ############################

-- See https://wiki.hypr.land/Configuring/Environment-variables/
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("QT_QPA_PLATFORMTHEME_QT6", "gtk3")

-- ##################

-- ## PERMISSIONS ###

-- ##################

-- See https://wiki.hypr.land/Configuring/Permissions/

-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly

-- for security reasons

-- ecosystem {

-- enforce_permissions = 1

-- }

-- permission = /usr/(bin|local/bin)/grim, screencopy, allow

-- permission = /usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland, screencopy, allow

-- permission = /usr/(bin|local/bin)/hyprpm, plugin, allow

-- ####################

-- ## LOOK AND FEEL ###

-- ####################

-- https://wiki.hypr.land/Configuring/Variables/#animations
hl.config({
    animations = {
        enabled = true,
    },
})

-- Gentle ease-out without overshoot: steeper curves spend their whole travel in the first few frames at 60 Hz
hl.curve("wind", { type = "bezier", points = { {0.22, 1}, {0.36, 1} } })
hl.curve("winIn", { type = "bezier", points = { {0.22, 1}, {0.36, 1} } })
hl.curve("winOut", { type = "bezier", points = { {0.4, 0}, {1, 1} } })
hl.curve("liner", { type = "bezier", points = { {1, 1}, {1, 1} } })
hl.animation({
    leaf = "windows",
    enabled = true,
    speed = 4,
    bezier = "wind",
    style = "slide",
})
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 4,
    bezier = "winIn",
    style = "slide",
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 3,
    bezier = "winOut",
    style = "slide",
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 4,
    bezier = "wind",
    style = "slide",
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 1,
    bezier = "liner",
})
-- Off: a looping angle redraws the whole screen every frame, even when idle
hl.animation({
    leaf = "borderangle",
    enabled = false,
})
hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 3,
    bezier = "default",
})
-- Layers: the same curves as windows; rofi grows into place instead of sliding from an edge
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 3,
    bezier = "wind",
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 1.5,
    bezier = "winOut",
})
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 3,
    bezier = "wind",
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 1.5,
    bezier = "winOut",
})
hl.layer_rule({
    name = "rofi-popin",
    match = { namespace = "^rofi$" },
    animation = "popin 92%",
})
hl.layer_rule({
    name = "walker-popin",
    match = { namespace = "^walker$" },
    animation = "popin 96%",
})
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 4,
    bezier = "wind",
})

-- Ref https://wiki.hypr.land/Configuring/Workspace-Rules/

-- "Smart gaps" / "No gaps when only"

-- uncomment all if you wish to use that.

-- workspace = w[tv1], gapsout:0, gapsin:0

-- workspace = f[1], gapsout:0, gapsin:0

-- windowrule = bordersize 0, floating:0, onworkspace:w[tv1]

-- windowrule = rounding 0, floating:0, onworkspace:w[tv1]

-- windowrule = bordersize 0, floating:0, onworkspace:f[1]

-- windowrule = rounding 0, floating:0, onworkspace:f[1]

-- See https://wiki.hypr.land/Configuring/Dwindle-Layout/ for more

-- dwindle {

-- pseudotile = true # Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below

-- preserve_split = true # You probably want this

-- }

-- See https://wiki.hypr.land/Configuring/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- Triple buffer when a frame runs late: keeps animations smooth on the iGPU
hl.config({
    render = {
        new_render_scheduling = true,
    },
})

-- https://wiki.hypr.land/Configuring/Variables/#misc
hl.config({
    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = false,
    },
})

hl.config({
    input = {
      kb_options = "scrolllock:mod3",
    }
})
