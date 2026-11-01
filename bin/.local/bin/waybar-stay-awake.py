#!/usr/bin/env python3
"""Waybar custom/stay-awake module: keep the screen on and the session unlocked.

Waybar's own idle_inhibitor lives on the bar's surface, so Hyprland ignores it while a
window is fullscreen, and it's gone in the layouts without the module. Instead a small
background process asks hypridle (lock) and xfce4-power-manager (screen off, auto suspend)
over D-Bus. They drop the request when it exits, so nothing is left behind by a crash.
Closing the lid still suspends.

    waybar-stay-awake.py [--status|--toggle]
"""

import json
import os
import signal
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

# --- Configuration ---
PID_FILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "waybar-stay-awake.pid")
SIGNAL = 12  # Matches "signal" in modules.jsonc
WHO = "Stay awake"
WHY = "Toggled from waybar"
# Service, object path, interface
INHIBITORS = [
    ("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver", "org.freedesktop.ScreenSaver"),
    (
        "org.freedesktop.PowerManagement",
        "/org/freedesktop/PowerManagement/Inhibit",
        "org.freedesktop.PowerManagement.Inhibit",
    ),
]


# --- Helpers ---
def holder_pid():
    """PID of the running holder, or None. Checks the command line in case the PID was reused."""
    try:
        with open(PID_FILE) as file:
            pid = int(file.read())
        with open(f"/proc/{pid}/cmdline", "rb") as file:
            return pid if b"--hold" in file.read() else None
    except (OSError, ValueError):
        return None


def refresh_bar():
    subprocess.run(["pkill", f"-RTMIN+{SIGNAL}", "-x", "waybar"], check=False)


# --- Actions ---
def hold():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    held = 0
    for service, path, interface in INHIBITORS:
        try:
            bus.call_sync(
                service, path, interface, "Inhibit", GLib.Variant("(ss)", (WHO, WHY)),
                GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1,
            )
            held += 1
        except GLib.Error as error:
            print(f"{service}: {error.message}", file=sys.stderr)
    if not held:
        sys.exit(1)

    with open(PID_FILE, "w") as file:
        file.write(str(os.getpid()))
    refresh_bar()
    signal.pause()  # Until --toggle ends this process, or the session does


def toggle():
    pid = holder_pid()
    if pid:
        os.kill(pid, signal.SIGTERM)
        os.remove(PID_FILE)
        refresh_bar()
    else:
        # Its own session: must outlive waybar restarts
        subprocess.Popen([os.path.abspath(__file__), "--hold"], start_new_session=True)


def status():
    on = holder_pid() is not None
    print(json.dumps({
        "alt": "on" if on else "off",
        "class": "on" if on else "off",
        "tooltip": "Staying awake · click to stop" if on else "Stay awake: off · click to start",
    }))


# --- Main ---
{"--hold": hold, "--toggle": toggle}.get(sys.argv[1] if len(sys.argv) > 1 else "", status)()
