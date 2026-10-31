#!/usr/bin/env python3
"""Close rofi when clicking away from it.

Rofi's surface is only as big as its menu, so it never hears about clicks outside it.
While rofi is open this puts an invisible layer over the windows and bar, below rofi,
and any click on it closes the menu. It follows Hyprland's layer events, so every menu
is covered without its script knowing.

The notification center covers everything but the bar and closes itself on a click away,
so while it's open only the bar gets a layer like this.
"""

import fcntl
import os
import socket
import subprocess
import sys

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

RUNTIME = os.environ["XDG_RUNTIME_DIR"]
EVENTS = f"{RUNTIME}/hypr/{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}/.socket2.sock"
LOCK = f"{RUNTIME}/rofi-backdrop.lock"
# Not fully transparent: GTK then never draws a buffer, and the surface never maps
BAR_HEIGHT = 36
CSS = "window.rofi-backdrop { background: rgba(0, 0, 0, 0.01); }"


class Backdrop:
    def __init__(self, app):
        self.app = app
        self.windows = []
        self.bar_windows = []
        self.buffer = b""
        self.events = socket.socket(socket.AF_UNIX)
        self.events.connect(EVENTS)
        GLib.io_add_watch(self.events.fileno(), GLib.IO_IN | GLib.IO_HUP, self.on_events)

        provider = Gtk.CssProvider()
        provider.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def on_events(self, _fd, _condition):
        data = self.events.recv(65536)
        if not data:  # Hyprland is gone
            self.app.quit()
            return False
        self.buffer += data
        *lines, self.buffer = self.buffer.split(b"\n")
        for line in lines:
            if line == b"openlayer>>rofi":
                self.show()
            elif line == b"closelayer>>rofi":
                self.hide()
            elif line == b"openlayer>>swaync-control-center":
                self.show_bar()
            elif line == b"closelayer>>swaync-control-center":
                self.hide_bar()
        return True

    def show(self):
        if self.windows:
            return
        monitors = Gdk.Display.get_default().get_monitors()
        for index in range(monitors.get_n_items()):
            self.windows.append(self.cover(monitors.get_item(index), self.on_click))

    def hide(self):
        for window in self.windows:
            window.destroy()
        self.windows = []

    def show_bar(self):
        if self.bar_windows:
            return
        monitors = Gdk.Display.get_default().get_monitors()
        for index in range(monitors.get_n_items()):
            self.bar_windows.append(self.cover(monitors.get_item(index), self.on_bar_click, BAR_HEIGHT))

    def hide_bar(self):
        for window in self.bar_windows:
            window.destroy()
        self.bar_windows = []

    def cover(self, monitor, on_click, height=None):
        window = Gtk.ApplicationWindow(application=self.app)
        window.add_css_class("rofi-backdrop")
        LayerShell.init_for_window(window)
        LayerShell.set_namespace(window, "rofi-backdrop")
        # Rofi lives on the overlay layer, so this stays below it and above everything else
        LayerShell.set_layer(window, LayerShell.Layer.TOP)
        LayerShell.set_monitor(window, monitor)
        LayerShell.set_exclusive_zone(window, -1)
        LayerShell.set_keyboard_mode(window, LayerShell.KeyboardMode.NONE)
        for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM, LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(window, edge, edge != LayerShell.Edge.BOTTOM or height is None)
        if height is not None:
            window.set_size_request(-1, height)

        click = Gtk.GestureClick(button=0)  # Any button
        click.connect("pressed", on_click)
        window.add_controller(click)
        window.present()
        return window

    # Hides right away too, so a missed close event can never leave the screen unclickable
    def on_click(self, *_args):
        subprocess.run(["pkill", "-x", "rofi"], check=False)
        self.hide()

    def on_bar_click(self, *_args):
        subprocess.run(["swaync-client", "-sw", "-cp"], stdout=subprocess.DEVNULL, check=False)
        self.hide_bar()


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0

    app = Gtk.Application()
    app.connect("activate", lambda app: (setattr(app, "backdrop", Backdrop(app)), app.hold()))
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
