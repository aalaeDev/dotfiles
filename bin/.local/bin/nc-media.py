#!/usr/bin/env python3
"""The notification center's media card: colors, position and size, in a generated stylesheet.

swaync's player keeps its live text and buttons, and has no room for anything else. So the cover is
stretched behind it, and the progress bar and times are painted on its background. With several
players the panel can't say which one you've swiped to, so they share a neutral card with no bar.

    nc-media.py refresh    Update the stylesheet, if the panel would show the difference
    nc-media.py toggle     Switch between the expanded and the compact card
"""

import colorsys
import hashlib
import os
import subprocess
import sys
import urllib.parse

# --- Configuration ---
CACHE = os.path.join(os.environ.get("RICE_CACHE", os.path.expanduser("~/.cache/rice")), "nc-media")
CSS = os.path.expanduser("~/.config/swaync/media-bar.css")
STATE = os.path.join(CACHE, "size")
FONT = "SF-Pro-Text-Medium"
TIME_WIDTH = 40  # Pixels for each time, either side of the bar
TIME_HEIGHT = 16
NEUTRAL = ("#c3c6cf", "#1d2024")
OVERLAY = ".control-center .widget-mpris .widget-mpris-player .mpris-overlay"


# --- Helpers ---
def output(*command):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def panel_open():
    with subprocess.Popen(["swaync-client", "-swb"], stdout=subprocess.PIPE, text=True) as client:
        line = client.stdout.readline()
        client.kill()
    return "cc-open" in line


def read_player():
    """The only player's fields, or None without exactly one that knows its track."""
    players = output("playerctl", "-l").splitlines()
    if len(players) != 1:
        return None
    fields = output("playerctl", "-p", players[0], "metadata", "--format",
                    "{{position}}\t{{mpris:length}}\t{{mpris:artUrl}}").split("\t")
    return fields if len(fields) == 3 else None


def cover_file(url):
    if url.startswith("file://"):
        path = urllib.parse.unquote(url[len("file://"):])
        return path if os.path.exists(path) else None
    if not url.startswith(("http://", "https://")):
        return None
    path = os.path.join(CACHE, "cover-" + hashlib.sha1(url.encode()).hexdigest())
    if not os.path.exists(path):
        output("curl", "-sfL", "--max-time", "5", "-o", path, url)
    return path if os.path.exists(path) else None


def hex_color(hue, lightness, saturation):
    return "#%02x%02x%02x" % tuple(round(c * 255) for c in colorsys.hls_to_rgb(hue, lightness, saturation))


def accents(path):
    """A bright color for the text and bar, and a dark one for the card, from the cover's most vivid color."""
    best, best_score = None, 0
    histogram = output("magick", path, "-resize", "48x48!", "-colors", "12", "-depth", "8", "-format", "%c", "histogram:info:-")
    for line in histogram.splitlines():
        try:
            count = int(line.split(":")[0])
            code = line.split("#")[1][:6]
            red, green, blue = (int(code[i:i + 2], 16) / 255 for i in (0, 2, 4))
        except (IndexError, ValueError):
            continue
        hue, lightness, saturation = colorsys.rgb_to_hls(red, green, blue)
        if not 0.12 < lightness < 0.9:
            continue
        score = saturation * count ** 0.5
        if score > best_score:
            best, best_score = (hue, saturation), score
    if not best or best[1] < 0.15:
        return NEUTRAL
    hue, saturation = best
    return hex_color(hue, 0.74, max(saturation, 0.55)), hex_color(hue, 0.14, min(saturation, 0.4))


def cached_accents(url):
    """Colors for this cover. Read from a file, since it only changes with the track."""
    key = os.path.join(CACHE, "accent-" + hashlib.sha1(url.encode()).hexdigest())
    try:
        with open(key) as saved:
            return tuple(saved.read().split())
    except (OSError, ValueError):
        pass
    path = cover_file(url)
    colors = accents(path) if path else NEUTRAL
    with open(key, "w") as saved:
        saved.write(" ".join(colors))
    return colors


def clock(microseconds):
    seconds = microseconds // 1_000_000
    hours, minutes = seconds // 3600, seconds % 3600 // 60
    return f"{hours}:{minutes:02}:{seconds % 60:02}" if hours else f"{minutes}:{seconds % 60:02}"


def time_image(name, text, color, gravity):
    """GTK's CSS can't hold text, so a time is a picture. Written only when the panel would show it."""
    path = os.path.join(CACHE, name)
    output("magick", "-size", f"{TIME_WIDTH}x{TIME_HEIGHT}", "xc:none", "-font", FONT, "-pointsize", "11",
           "-fill", color, "-gravity", gravity, "-annotate", "+0+0", text, path)
    return path


def card_css(player, compact):
    position, length, url = player or ("", "", "")
    accent, tint = cached_accents(url) if url else NEUTRAL
    has_bar = position.isdigit() and length.isdigit() and int(length) > 0

    inset = 16
    top = 0 if compact else 132  # Where the cover ends and the card's color starts
    # Eased like a shadow: a straight ramp shows where it starts and ends
    start, end = top - 92, top + 8
    eased = ", ".join(f"alpha({tint}, {opacity}) {start + (end - start) * step // 8}px"
                      for step, opacity in enumerate((0, 0.04, 0.13, 0.27, 0.45, 0.64, 0.81, 0.94, 1)))
    fade = f"linear-gradient(to bottom, {eased}, {tint})"
    full = f"linear-gradient({tint}, {tint})"
    layers, sizes, places = [], [], []
    if has_bar:
        side = inset + TIME_WIDTH + 8
        percent = min(int(position) * 100 // int(length), 100)
        fill, track = f"linear-gradient({accent}, {accent})", f"linear-gradient(alpha({accent}, 0.22), alpha({accent}, 0.22))"
        bar_y = "calc(100% - 20px)"
        layers += [fill, track,
                   f'url("{time_image("elapsed.png", clock(int(position)), accent, "West")}")',
                   f'url("{time_image("total.png", clock(int(length)), accent, "East")}")']
        sizes += [f"calc((100% - {side * 2}px) * {percent} / 100) 3px", f"calc(100% - {side * 2}px) 3px",
                  f"{TIME_WIDTH}px {TIME_HEIGHT}px", f"{TIME_WIDTH}px {TIME_HEIGHT}px"]
        places += [f"{side}px {bar_y}", f"{side}px {bar_y}", f"{inset}px calc(100% - 14px)", f"calc(100% - {inset}px) calc(100% - 14px)"]
    layers.append(full if compact else fade)
    sizes.append("100% 100%")
    places.append("0 0")

    if compact:
        padding, art = f"10px {inset}px {36 if has_bar else 10}px", "-gtk-icon-size: 44px; margin: 0 10px 0 0; opacity: 1;"
    else:
        padding, art = f"{top + 10}px {inset}px {42 if has_bar else 14}px", "-gtk-icon-size: 0; margin: 0; opacity: 0; box-shadow: none;"
    button_size = 30 if compact else 36
    play_size = 34 if compact else 44
    base = f"{OVERLAY} > box > button"
    play = ",\n".join(f"{base}:nth-child({x}):nth-last-child({y})" for x, y in ((2, 2), (3, 2), (2, 3), (3, 3)))
    return f"""{OVERLAY} {{
    background-color: transparent;
    background-image: {", ".join(layers)};
    background-size: {", ".join(sizes)};
    background-position: {", ".join(places)};
    background-repeat: no-repeat;
    padding: {padding};
}}
.control-center .widget-mpris .widget-mpris-player .mpris-background {{ filter: none; opacity: {0 if compact else 1}; }}
{OVERLAY} .widget-mpris-album-art {{ {art} }}
{OVERLAY} .widget-mpris-title {{ color: {accent}; }}
{base} {{ min-width: {button_size}px; min-height: {button_size}px; color: {accent}; }}
{play} {{ min-width: {play_size}px; min-height: {play_size}px; background: {accent}; color: {tint}; }}
{".control-center .widget-menubar.playing > .menu-button-bar > .end button { color: @on_surface_variant; font-size: 14px; padding: 6px 12px; }" if player else ""}
"""


def refresh(force=False):
    os.makedirs(CACHE, exist_ok=True)
    try:
        with open(STATE) as saved:
            compact = saved.read().strip() == "compact"
    except OSError:
        compact = False
    # The times change every tick, so don't reload swaync's style for a panel nobody's looking at
    if not force and os.path.exists(CSS) and not panel_open():
        player = read_player()
        marker = os.path.join(CACHE, "track")
        track = player[2] if player else ""
        try:
            with open(marker) as saved:
                if saved.read() == track:
                    return
        except OSError:
            pass
        with open(marker, "w") as saved:
            saved.write(track)
    css = card_css(read_player(), compact)
    with open(f"{CSS}.tmp", "w") as new:
        new.write(css)
    os.replace(f"{CSS}.tmp", CSS)
    output("swaync-client", "-sw", "-rs")


# --- Actions ---
if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "refresh"
    if action == "toggle":
        os.makedirs(CACHE, exist_ok=True)
        try:
            with open(STATE) as saved:
                current = saved.read().strip()
        except OSError:
            current = "expanded"
        with open(STATE, "w") as saved:
            saved.write("expanded" if current == "compact" else "compact")
        refresh(force=True)
    elif action == "refresh":
        refresh()
    else:
        sys.exit(__doc__)
