-- ##################################

-- ## WINDOW SWITCHER (macOS style) ###

-- ##################################

-- While Super is held, a submap owns the keys. The keyboard stays with the app in use, and the
-- compositor sees the release in order with the rest, however quick the tap.
--
-- Commands reach ~/.local/bin/window-switcher.py through a FIFO: written from here they keep their
-- order, and no process starts per key press.

local runtime = os.getenv("XDG_RUNTIME_DIR")
local fifo = runtime .. "/window-switcher.fifo"
local lock = runtime .. "/window-switcher.lock"
local start_cmd = "LD_PRELOAD=libgtk4-layer-shell.so ~/.local/bin/window-switcher.py"
local submap = "window-switcher"

local function running()
    local file = io.open(lock)
    if not file then
        return false
    end
    local pid = file:read("l")
    file:close()
    local process = pid and pid ~= "" and io.open("/proc/" .. pid .. "/comm")
    if process then
        process:close()
        return true
    end
    return false
end

-- r+ never blocks waiting for a reader. Writing to a FIFO nobody reads would freeze the compositor
-- once full, which is why opening the switcher checks that it's alive first.
local function send(command)
    local file = io.open(fifo, "r+")
    if file then
        file:write(command .. "\n")
        file:close()
    end
end

local function open(command)
    return function()
        if running() then
            send(command)
            hl.dispatch(hl.dsp.submap(submap))
        else
            hl.exec_cmd(start_cmd)
        end
    end
end

local function command(name)
    return function()
        send(name)
    end
end

local function close(name)
    return function()
        send(name)
        hl.dispatch(hl.dsp.submap("reset"))
    end
end

hl.bind("SUPER + Tab", open("next"))
hl.bind("SUPER + SHIFT + Tab", open("prev"))
hl.bind("SUPER + code:49", open("same"))

hl.define_submap(submap, function()
    hl.bind("SUPER + Tab", command("next"), { repeating = true })
    hl.bind("SUPER + SHIFT + Tab", command("prev"), { repeating = true })
    hl.bind("SUPER + Right", command("next"), { repeating = true })
    hl.bind("SUPER + Left", command("prev"), { repeating = true })
    hl.bind("SUPER + code:49", command("grave"), { repeating = true })
    hl.bind("SUPER + SHIFT + code:49", command("shift-grave"), { repeating = true })
    hl.bind("SUPER + Up", command("toggle-view"))
    hl.bind("SUPER + Down", command("toggle-view"))
    hl.bind("SUPER + Q", command("quit"))
    hl.bind("SUPER + H", command("hide"))
    hl.bind("SUPER + Escape", close("cancel"))
    hl.bind("SUPER + code:60", close("cancel")) -- Super+. is Cmd+.
    hl.bind("SUPER + Return", close("commit"))

    -- Keeps every other Super shortcut from firing into the app underneath
    hl.bind("SUPER + catchall", hl.dsp.no_op())
end)

local function commit_if_open()
    if hl.get_current_submap() == submap then
        close("commit")()
    end
end

-- Super goes down before the submap starts, and Hyprland 0.57 only fires a release in the submap
-- of its press unless the bind is universal. Transparent is needed too, or it never fires on a
-- modifier. So these run on every release of Super, and must check.
local release = { release = true, transparent = true, submap_universal = true }
hl.bind("SUPER + Super_L", commit_if_open, release)
hl.bind("SUPER + Super_R", commit_if_open, release)

-- Those don't fire with another key down, and a fast tap lets go of Super while Tab is still down:
-- then the other key coming up finds Super gone. The event alone isn't enough, as Super's own
-- release reaches it before the key counts as up.
hl.on("input.keyboard.key", function()
    if not hl.is_key_down("Super_L") and not hl.is_key_down("Super_R") then
        commit_if_open()
    end
end)
