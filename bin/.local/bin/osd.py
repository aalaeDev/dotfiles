#!/usr/bin/env python3
"""A small popup showing the level when volume or brightness change.

It follows the levels themselves, not the keys, so the bar's scroll and the notification
center's sliders show it too. A key press that can't change the level anymore, like volume up
at the maximum, reports itself with a signal: SIGUSR1 for volume, SIGUSR2 for brightness.
Clicks go through to the windows below.
"""

import ctypes
import fcntl
import glob
import os
import re
import signal
import subprocess
import sys
import time

import cairo
import gi

gi.require_version("Gdk", "4.0")
gi.require_version("GLibUnix", "2.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, GLib, GLibUnix, Gtk  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

# Already loaded here. Inherited, every helper would load all of GTK first, taking 60 ms each.
os.environ.pop("LD_PRELOAD", None)

LOCK = f"{os.environ['XDG_RUNTIME_DIR']}/osd.lock"
COLORS = os.path.expanduser("~/.config/swaync/colors.css")
VISIBLE_MS = 1300
FADE_MS = 150
SETTLE_MS = 20      # A dragged slider sends bursts of events: read the level once per burst
KEY_QUIET_S = 0.1   # A key press reports itself: the audio event it also causes needs no second read
RESTART_MS = 2000   # Before starting a watcher again, e.g. when the audio server restarts
BOTTOM_MARGIN = 72
WIDTH = 260
PR_SET_PDEATHSIG = 1

VOLUME_ICONS = ("\U000F057F", "\U000F0580", "\U000F057E")
MUTED_ICON = "\U000F075F"
BRIGHTNESS_ICONS = ("\U000F00DE", "\U000F00DF", "\U000F00E0")

CSS = """
window.osd { background: transparent; }
.osd-pill {
    background: alpha(@background, 0.85);  /* The same as the bar's pills */
    border-radius: 11px;
    padding: 10px 14px;
    color: @on_surface;
    font-family: "JetBrainsMono NFP", "JetBrainsMono NF";
}
.osd-fading { opacity: 0; transition: opacity %dms ease-out; }
.osd-icon { font-size: 18px; color: @primary; }
.osd-value { font-size: 12px; font-weight: bold; min-width: 34px; }
progressbar trough, progressbar progress { min-height: 6px; border-radius: 3px; border: none; }
progressbar trough { background: @outline_variant; }
progressbar progress { background: @primary; }
.osd-muted .osd-icon, .osd-muted .osd-value { color: @on_surface_variant; }
.osd-muted progressbar progress { background: @on_surface_variant; }
""" % FADE_MS


def icon_for(icons, percent):
    return icons[min(percent * len(icons) // 100, len(icons) - 1)]


# The volume and whether it's muted: all a key press needs
READ_VOLUME = ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
# And the sink: without a key press, a new default sink must not count as a volume change
READ_VOLUME_AND_SINK = ["sh", "-c", "pactl get-default-sink; wpctl get-volume @DEFAULT_AUDIO_SINK@"]


# (percent, muted), None without a sink
def parse_volume(output):
    match = re.search(r"Volume: ([\d.]+)( \[MUTED\])?", output)
    return (round(float(match.group(1)) * 100), bool(match.group(2))) if match else None


# A closed pipe isn't enough: pactl subscribe stays around when its reader is gone
def die_with_parent():
    ctypes.CDLL(None).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)


def read_brightness(device):
    with open(f"{device}/brightness") as now, open(f"{device}/max_brightness") as maximum:
        return round(int(now.read()) * 100 / int(maximum.read()))


class Watcher:
    """Runs a command for as long as the popup lives, and calls back on the lines it prints."""

    def __init__(self, command, on_line):
        self.command = command
        self.on_line = on_line
        self.start()

    def start(self):
        self.process = subprocess.Popen(
            self.command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, preexec_fn=die_with_parent
        )
        self.buffer = b""
        GLib.io_add_watch(self.process.stdout.fileno(), GLib.IO_IN | GLib.IO_HUP, self.on_output)
        return False

    def on_output(self, fd, _condition):
        data = os.read(fd, 65536)
        if not data:
            self.process.stdout.close()
            self.process.wait()
            GLib.timeout_add(RESTART_MS, self.start)
            return False
        self.buffer += data
        *lines, self.buffer = self.buffer.split(b"\n")
        for line in lines:
            self.on_line(line.decode(errors="replace"))
        return True


class Osd(Gtk.ApplicationWindow):
    def __init__(self, app, lock):
        super().__init__(application=app)
        self.hide_timer = 0
        self.volume_pending = 0
        self.volume_reader = None
        self.read_again = False
        self.key_waiting = False
        self.last_key = 0
        self.brightness_pending = 0
        self.colors_changed = 0

        self.add_css_class("osd")
        LayerShell.init_for_window(self)
        LayerShell.set_namespace(self, "osd")
        LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
        LayerShell.set_exclusive_zone(self, -1)
        LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.NONE)
        LayerShell.set_anchor(self, LayerShell.Edge.BOTTOM, True)
        LayerShell.set_margin(self, LayerShell.Edge.BOTTOM, BOTTOM_MARGIN)

        self.icon = Gtk.Label(css_classes=["osd-icon"])
        self.bar = Gtk.ProgressBar(hexpand=True, valign=Gtk.Align.CENTER)
        self.value = Gtk.Label(css_classes=["osd-value"], xalign=1)
        self.pill = Gtk.Box(spacing=12, css_classes=["osd-pill"], width_request=WIDTH)
        for child in (self.icon, self.bar, self.value):
            self.pill.append(child)
        self.set_child(self.pill)
        self.connect("map", lambda _: self.get_surface().set_input_region(cairo.Region()))

        self.provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), self.provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        # What's already set when this starts is no news
        output = subprocess.run(READ_VOLUME_AND_SINK, capture_output=True, text=True).stdout
        self.sink = output.split("\n", 1)[0]
        self.volume = parse_volume(output)
        Watcher(["pactl", "subscribe"], self.on_audio_event)
        self.devices = glob.glob("/sys/class/backlight/*")
        if self.devices:
            self.brightness = read_brightness(self.devices[0])
            Watcher(["udevadm", "monitor", "--udev", "--subsystem-match=backlight"], self.on_backlight_event)

        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, self.on_volume_key)
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR2, self.on_brightness_key)
        # Only now: until the handlers are in place, a signal would kill this process
        lock.truncate(0)
        lock.write(f"{os.getpid()}\n")
        lock.flush()

    def on_audio_event(self, line):
        if "on sink #" not in line or self.volume_pending or time.monotonic() - self.last_key < KEY_QUIET_S:
            return
        self.volume_pending = GLib.timeout_add(SETTLE_MS, self.check_volume)

    def on_backlight_event(self, line):
        if "(backlight)" in line and not self.brightness_pending:
            self.brightness_pending = GLib.timeout_add(SETTLE_MS, self.check_brightness)

    def check_volume(self):
        self.volume_pending = 0
        self.read_volume(False)
        return False

    # Never waits, so a held key can't hold up drawing. One read at a time, repeated if asked for
    # meanwhile: however fast the key repeats, the popup ends on the latest level.
    def read_volume(self, key):
        self.key_waiting = self.key_waiting or key
        if self.volume_reader:
            self.read_again = True
            return
        key, self.key_waiting = self.key_waiting, False
        self.volume_reader = subprocess.Popen(
            READ_VOLUME if key else READ_VOLUME_AND_SINK, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        )
        GLib.io_add_watch(self.volume_reader.stdout.fileno(), GLib.IO_IN | GLib.IO_HUP, self.on_volume_read, key, [])

    def on_volume_read(self, fd, _condition, key, chunks):
        data = os.read(fd, 4096)
        if data:
            chunks.append(data)
            return True
        self.volume_reader.stdout.close()
        self.volume_reader.wait()
        self.volume_reader = None
        output = b"".join(chunks).decode()
        previous, self.volume = self.volume, parse_volume(output)
        if key:
            if self.volume:
                self.show_volume()
        else:
            # A new default sink is a device change, and a sink also reports going to sleep
            sink, self.sink = self.sink, output.split("\n", 1)[0]
            if self.volume and previous and sink == self.sink and self.volume != previous:
                self.show_volume()
        if self.read_again:
            self.read_again = False
            self.read_volume(False)
        return False

    def check_brightness(self):
        self.brightness_pending = 0
        percent = read_brightness(self.devices[0])
        if percent != self.brightness:
            self.brightness = percent
            self.show_brightness()
        return False

    def on_volume_key(self):
        self.last_key = time.monotonic()
        self.read_volume(True)
        return True

    def on_brightness_key(self):
        if self.devices:
            self.brightness = read_brightness(self.devices[0])
            self.show_brightness()
        return True

    def show_volume(self):
        percent, muted = self.volume
        self.show_level(MUTED_ICON if muted else icon_for(VOLUME_ICONS, percent), percent, muted)

    def show_brightness(self):
        self.show_level(icon_for(BRIGHTNESS_ICONS, self.brightness), self.brightness, False)

    def show_level(self, icon, percent, muted):
        # Follows the wallpaper's colors. Only on a change: loading restyles the whole popup.
        changed = os.stat(COLORS).st_mtime_ns
        if changed != self.colors_changed:
            self.colors_changed = changed
            with open(COLORS) as colors:
                self.provider.load_from_string(colors.read() + CSS)
        self.icon.set_label(icon)
        self.bar.set_fraction(min(percent, 100) / 100)
        self.value.set_label(f"{percent}%")
        if muted:
            self.pill.add_css_class("osd-muted")
        else:
            self.pill.remove_css_class("osd-muted")

        # Mapped anew each time, so it appears on the monitor in use
        self.pill.remove_css_class("osd-fading")
        self.set_visible(True)
        if self.hide_timer:
            GLib.source_remove(self.hide_timer)
        self.hide_timer = GLib.timeout_add(VISIBLE_MS, self.on_timeout)

    def on_timeout(self):
        self.pill.add_css_class("osd-fading")
        self.hide_timer = GLib.timeout_add(FADE_MS, self.on_faded)
        return False

    def on_faded(self):
        self.hide_timer = 0
        self.set_visible(False)
        return False


def main():
    lock = open(LOCK, "a")  # Not "w": a second instance would wipe the running one's pid
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0

    app = Gtk.Application()
    app.connect("activate", lambda app: (setattr(app, "osd", Osd(app, lock)), app.hold()))
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
