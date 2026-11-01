local var_mainMod = "SUPER"
local var_term = "kitty"
local var_file = "nemo"
local var_binPath = "~/.local/bin"

-- #########################

-- ##  GLOBAL VARIABLES  ###

-- #########################

-- ####################

-- ## SYSTEM BINDS  ###

-- ####################
hl.bind(var_mainMod .. " + Return", hl.dsp.exec_cmd(var_term))
hl.bind(var_mainMod .. " + E", hl.dsp.exec_cmd(var_file))
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd(var_term .. " -e btop"))
hl.bind("CTRL + Print", hl.dsp.exec_cmd(var_binPath .. "/screenshot.sh region"))
hl.bind("Print", hl.dsp.exec_cmd(var_binPath .. "/screenshot.sh output"))
hl.bind("CTRL + ALT + Print", hl.dsp.exec_cmd(var_binPath .. "/screenshot.sh window"))
hl.bind(var_mainMod .. " + Print", hl.dsp.exec_cmd(var_binPath .. "/rofi-menus/toggle.sh screenshot " .. var_binPath .. "/rofi-menus/screenshot.sh"))
hl.bind(var_mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd(var_binPath .. "/screenshot.sh gif"))
hl.bind(var_mainMod .. " + P", hl.dsp.exec_cmd("pavucontrol"))
hl.bind(var_mainMod .. " + V", hl.dsp.exec_cmd("pkill -x rofi; ~/.local/bin/sound.sh walker; walker -m clipboard"))
-- Walker toggles itself; rofi can't stay open under it
hl.bind(var_mainMod .. " + S", hl.dsp.exec_cmd("pkill -x rofi; ~/.local/bin/sound.sh walker; walker"))
hl.bind(var_mainMod .. " + A", hl.dsp.exec_cmd(var_binPath .. "/rofi-menus/toggle.sh apps rofi -show drun"))
hl.bind(var_mainMod .. " + X", hl.dsp.exec_cmd(var_binPath .. "/rofi-menus/toggle.sh power " .. var_binPath .. "/rofi-menus/powermenu.sh"))
hl.bind(var_mainMod .. " + R", hl.dsp.exec_cmd("sh " .. var_binPath .. "/launch.sh"))
hl.bind(var_mainMod .. " + C", hl.dsp.exec_cmd("hyprpicker -a"))
hl.bind(var_mainMod .. " + L", hl.dsp.exec_cmd(var_binPath .. "/lock.sh"))
hl.bind(var_mainMod .. " + W", hl.dsp.exec_cmd(var_binPath .. "/rofi-menus/toggle.sh wallpaper " .. var_binPath .. "/wallset.sh"))
hl.bind(var_mainMod .. " + B", hl.dsp.exec_cmd(var_binPath .. "/waybar-layout.sh toggle"))
hl.bind(var_mainMod .. " + code:60", hl.dsp.exec_cmd(var_binPath .. "/rofi-menus/toggle.sh emoji " .. var_binPath .. "/rofi-menus/emoji.sh"))
hl.bind(var_mainMod .. " + SHIFT + code:60", hl.dsp.exec_cmd(var_binPath .. "/rofi-menus/toggle.sh kaomoji " .. var_binPath .. "/rofi-menus/emoji.sh kaomoji"))

-- ######################

-- ## SYSTEM CONTROL  ###

-- ######################

-- ## VOLUME
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(var_binPath .. "/volume.sh down"), {
    locked = true,
    repeating = true,
})
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(var_binPath .. "/volume.sh up"), {
    locked = true,
    repeating = true,
})
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("pactl -- set-sink-mute 0 toggle; ~/.local/bin/sound.sh volume"), {
    locked = true,
})
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("pactl -- set-source-mute 0 toggle"), {
    locked = true,
})

-- ## PLAYER
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), {
    locked = true,
})
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), {
    locked = true,
})
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), {
    locked = true,
})
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), {
    locked = true,
})
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"), {
    locked = true,
})

-- ## BRIGHTNESS
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(var_binPath .. "/brightness.sh down"), {
    locked = true,
})
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(var_binPath .. "/brightness.sh up"), {
    locked = true,
})

-- ################

-- ## HYPRLAND  ###

-- ################

-- # Session actions
hl.bind(var_mainMod .. " + Delete", hl.dsp.exit())
hl.bind("CTRL + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))

-- # Window actions
hl.bind(var_mainMod .. " + Q", hl.dsp.window.close())
hl.bind(var_mainMod .. " + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind("F11", hl.dsp.window.fullscreen())
hl.bind(var_mainMod .. " + J", hl.dsp.layout("togglesplit"))

-- ## Move/Change window focus
hl.bind(var_mainMod .. " + Right", hl.dsp.focus({ direction = "right" }))
hl.bind(var_mainMod .. " + Left", hl.dsp.focus({ direction = "left" }))
hl.bind(var_mainMod .. " + Up", hl.dsp.focus({ direction = "up" }))
hl.bind(var_mainMod .. " + Down", hl.dsp.focus({ direction = "down" }))
hl.bind("ALT + Tab", hl.dsp.focus({ direction = "down" }))

-- ## Switch workspaces
hl.bind(var_mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(var_mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(var_mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(var_mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(var_mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind(var_mainMod .. " + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind(var_mainMod .. " + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind(var_mainMod .. " + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind(var_mainMod .. " + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind(var_mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))
hl.bind(var_mainMod .. "+CTRL + Right", hl.dsp.focus({ workspace = "r+1" }))
hl.bind(var_mainMod .. "+CTRL + Left", hl.dsp.focus({ workspace = "r-1" }))
hl.bind(var_mainMod .. "+CTRL + Down", hl.dsp.focus({ workspace = "empty" }))
hl.bind(var_mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+10" }))
hl.bind(var_mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-10" }))

-- ## Resize windows
hl.bind(var_mainMod .. "+SHIFT + Right", hl.dsp.window.resize({ x = 30, y = 0, relative = true }), {
    repeating = true,
})
hl.bind(var_mainMod .. "+SHIFT + Left", hl.dsp.window.resize({ x = -30, y = 0, relative = true }), {
    repeating = true,
})
hl.bind(var_mainMod .. "+SHIFT + Up", hl.dsp.window.resize({ x = 0, y = -30, relative = true }), {
    repeating = true,
})
hl.bind(var_mainMod .. "+SHIFT + Down", hl.dsp.window.resize({ x = 0, y = 30, relative = true }), {
    repeating = true,
})
hl.bind(var_mainMod .. " + mouse:273", hl.dsp.window.resize(), {
    mouse = true,
})

-- ## Move focused window to a workspace
hl.bind(var_mainMod .. "+SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind(var_mainMod .. "+SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind(var_mainMod .. "+SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
hl.bind(var_mainMod .. "+SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
hl.bind(var_mainMod .. "+SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
hl.bind(var_mainMod .. "+SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
hl.bind(var_mainMod .. "+SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
hl.bind(var_mainMod .. "+SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
hl.bind(var_mainMod .. "+SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
hl.bind(var_mainMod .. "+SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- ## Move focused window around the current workspace
hl.bind(var_mainMod .. "+SHIFT+CTRL + Right", hl.dsp.window.move({ direction = "right" }))
hl.bind(var_mainMod .. "+SHIFT+CTRL + Left", hl.dsp.window.move({ direction = "left" }))
hl.bind(var_mainMod .. "+SHIFT+CTRL + Up", hl.dsp.window.move({ direction = "up" }))
hl.bind(var_mainMod .. "+SHIFT+CTRL + Down", hl.dsp.window.move({ direction = "down" }))
hl.bind(var_mainMod .. " + mouse:272", hl.dsp.window.drag(), {
    mouse = true,
})

-- ## Silent workspaces
hl.bind(var_mainMod .. "+SHIFT + D", hl.dsp.window.move({ workspace = "special", silent = true }))
hl.bind(var_mainMod .. " + D", hl.dsp.workspace.toggle_special("special"))
hl.bind(var_mainMod .. "+SHIFT + M", hl.dsp.window.move({ workspace = "special:mail", silent = true }))
hl.bind(var_mainMod .. " + M", hl.dsp.workspace.toggle_special("mail"))
hl.bind(var_mainMod .. "+SHIFT + Y", hl.dsp.window.move({ workspace = "special:music", silent = true }))
hl.bind(var_mainMod .. " + Y", hl.dsp.workspace.toggle_special("music"))
