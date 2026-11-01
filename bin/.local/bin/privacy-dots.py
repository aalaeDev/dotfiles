#!/usr/bin/env python3
"""Waybar custom/privacy module: iPhone style dots for what's recording you.

Orange is the microphone, green the camera, red the screen, blue the location. The bar gets one dot
each, with who's using it in the tooltip. The notification center names them at the end of the prayer row,
through a generated stylesheet because its text can't change while the panel is open.

Location goes through geoclue, the only thing that reports it: apps that find it some other way don't show.

    privacy-dots.py [--once]
"""

import glob
import html
import json
import os
import subprocess
import sys
import time

# --- Configuration ---
INTERVAL = 2  # Seconds between checks
CSS = os.path.expanduser("~/.config/swaync/privacy.css")
# The order matches buttons#privacy in nc-daemon.sh. These colors mean the same as on an
# iPhone whatever the wallpaper is, so they don't follow the theme.
DOTS = {
    "mic": ("Microphone", "#ff9f0a"),
    "camera": ("Camera", "#30d158"),
    "screen": ("Screen", "#ff453a"),
    "location": ("Location", "#0a84ff"),
}
RECORDERS = ("wf-recorder", "wl-screenrec", "gpu-screen-recorder")
# pavucontrol's level meters open the mic for as long as its window is up, without recording anything
IGNORED_STREAMS = {"Peak detect"}


# --- Helpers ---
def output(*command):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def pipewire_users():
    """Who's in each dot's set, from PipeWire: streams count only while running and linked to a real source."""
    users = {name: set() for name in DOTS}
    try:
        objects = json.loads(output("pw-dump") or "[]")
    except json.JSONDecodeError:
        return users
    nodes = {o["id"]: o for o in objects if o.get("type") == "PipeWire:Interface:Node"}
    links = [o["info"] for o in objects if o.get("type") == "PipeWire:Interface:Link"]

    def props(node):
        return node["info"].get("props") or {}

    def source_of(node_id):
        for link in links:
            if link.get("input-node-id") == node_id and link.get("output-node-id") in nodes:
                yield props(nodes[link["output-node-id"]])

    for node_id, node in nodes.items():
        info = props(node)
        kind = info.get("media.class", "")
        app = info.get("application.name") or info.get("node.name") or "Unknown"
        # The portal's stream only exists during a share, and idles whenever the picture isn't changing
        if str(info.get("node.name", "")).startswith("xdph") or kind == "Stream/Output/Video":
            users["screen"].add("Screen share")
        if node["info"].get("state") != "running":
            continue
        if kind == "Stream/Input/Audio" and info.get("media.name") not in IGNORED_STREAMS:
            if any(s.get("media.class", "").startswith("Audio/Source") for s in source_of(node_id)):
                users["mic"].add(app)
        elif kind == "Stream/Input/Video":
            for source in source_of(node_id):
                if source.get("device.api") in ("v4l2", "libcamera"):
                    users["camera"].add(app)
    return users


def camera_users():
    """Apps that open the camera directly, which PipeWire doesn't see."""
    devices = glob.glob("/dev/video*")
    names = set()
    for pid in output("fuser", *devices).split() if devices else []:
        try:
            with open(f"/proc/{pid}/comm") as comm:
                names.add(comm.read().strip())
        except OSError:
            pass
    return names - {"pipewire", "wireplumber"}


def check():
    users = pipewire_users()
    users["camera"] |= camera_users()
    for recorder in RECORDERS:
        if output("pgrep", "-x", recorder):
            users["screen"].add(recorder)
    # Only when it's running: asking would start the service, and asking every check would keep it up
    if output("pgrep", "-x", "geoclue") and "true" in output(
        "busctl", "--system", "get-property", "org.freedesktop.GeoClue2",
        "/org/freedesktop/GeoClue2/Manager", "org.freedesktop.GeoClue2.Manager", "InUse"):
        users["location"].add("An app")
    return {name: sorted(apps) for name, apps in users.items() if apps}


def bar_module(active):
    if not active:
        return {"text": "", "tooltip": "", "class": "idle"}
    dots = " ".join(f"<span color='{DOTS[name][1]}'>●</span>" for name in DOTS if name in active)
    tooltip = "\n".join(f"{DOTS[name][0]}: {html.escape(', '.join(active[name]))}" for name in DOTS if name in active)
    return {"text": dots, "tooltip": tooltip, "class": "active"}


def panel_css(active):
    """Selectors outrank style.css, which comes after this file, and which keeps the idle ones at no size."""
    rules = []
    for row, (name, (_, color)) in enumerate(DOTS.items(), 1):
        button = f".control-center .widget-menubar.athan-state > .menu-button-bar > .end button:nth-child({row})"
        if name in active:
            rules.append(f"{button} {{ font-size: 12px; padding: 4px 0 4px 12px; }}")
            rules.append(f"{button} label {{ color: {color}; }}")
    return "\n".join(rules) + "\n"


def write_panel_css(active):
    css = panel_css(active)
    try:
        with open(CSS) as current:
            if current.read() == css:
                return
    except OSError:
        pass
    with open(f"{CSS}.tmp", "w") as new:
        new.write(css)
    os.replace(f"{CSS}.tmp", CSS)
    output("swaync-client", "-sw", "-rs")


# --- Actions ---
if __name__ == "__main__":
    if "--once" in sys.argv:
        print(json.dumps(bar_module(check())))
        sys.exit()

    parent = os.getppid()
    previous = None
    # An idle module never writes, so a closed pipe alone wouldn't end it when waybar goes away
    while os.getppid() == parent:
        active = check()
        if active != previous:
            previous = active
            write_panel_css(active)
            print(json.dumps(bar_module(active)), flush=True)
        time.sleep(INTERVAL)
