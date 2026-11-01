#!/usr/bin/env python3
"""Dashed border and timer around a screen recording, for screenshot.sh.

    screenshot-overlay.py "x,y WxH"

Everything is drawn outside the region, so none of it ends up in the recording.
Clicks go through to the windows below. Quits with its parent.
"""

import os
import re
import sys
import time

import cairo
import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

COLORS = os.path.expanduser("~/.config/rofi/colors.rasi")
GAP = 3  # From the region to the middle of the border. Must stay above half of OUTLINE_WIDTH.
BORDER_WIDTH = 2
OUTLINE_WIDTH = 4
DASHES = [10, 6]
LABEL_FONT = "SF Pro Text Bold 10"
LABEL_MARGIN = 8
LABEL_PADDING = (10, 5)
RED = (1.0, 0.33, 0.33)


def theme_color(name, fallback):
    with open(COLORS) as colors:
        match = re.search(rf"^\s*{name}:\s*#([0-9a-fA-F]{{6}})", colors.read(), re.M)
    value = match.group(1) if match else fallback
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4))


def monitor_at(x, y):
    monitors = Gdk.Display.get_default().get_monitors()
    for index in range(monitors.get_n_items()):
        monitor = monitors.get_item(index)
        area = monitor.get_geometry()
        if area.x <= x < area.x + area.width and area.y <= y < area.y + area.height:
            return monitor
    return monitors.get_item(0)


class Overlay(Gtk.ApplicationWindow):
    def __init__(self, app, x, y, width, height):
        super().__init__(application=app)
        self.monitor = monitor_at(x, y)
        area = self.monitor.get_geometry()
        self.region = (x - area.x, y - area.y, width, height)
        self.started = time.monotonic()
        self.parent_pid = os.getppid()
        self.accent = theme_color("selected", "a3c9fe")
        self.background = theme_color("background", "111418")
        self.foreground = theme_color("foreground", "e1e2e8")

        LayerShell.init_for_window(self)
        LayerShell.set_namespace(self, "screenshot-overlay")
        LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
        LayerShell.set_monitor(self, self.monitor)
        LayerShell.set_exclusive_zone(self, -1)
        LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.NONE)
        for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM, LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(self, edge, True)

        provider = Gtk.CssProvider()
        provider.load_from_string("window { background: transparent; }")
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.canvas = Gtk.DrawingArea()
        self.canvas.set_draw_func(self.draw)
        self.set_child(self.canvas)
        self.connect("map", lambda _: self.get_surface().set_input_region(cairo.Region()))
        GLib.timeout_add(250, self.tick)

    def tick(self):
        if os.getppid() != self.parent_pid:
            self.get_application().quit()
            return False
        self.canvas.queue_draw()
        return True

    def draw(self, _area, cr, canvas_width, canvas_height):
        x, y, width, height = self.region
        cr.rectangle(x - GAP, y - GAP, width + GAP * 2, height + GAP * 2)
        path = cr.copy_path()

        # A dark outline under the dashes, so they show on any wallpaper
        cr.set_source_rgba(0, 0, 0, 0.55)
        cr.set_line_width(OUTLINE_WIDTH)
        cr.stroke()

        cr.append_path(path)
        cr.set_source_rgb(*self.accent)
        cr.set_line_width(BORDER_WIDTH)
        cr.set_dash(DASHES)
        cr.stroke()
        cr.set_dash([])

        self.draw_label(cr, canvas_width, canvas_height)

    def draw_label(self, cr, canvas_width, canvas_height):
        x, y, width, height = self.region
        elapsed = int(time.monotonic() - self.started)
        layout = PangoCairo.create_layout(cr)
        layout.set_font_description(Pango.FontDescription(LABEL_FONT))
        layout.set_text(f"●  {elapsed // 60}:{elapsed % 60:02d}", -1)
        text_width, text_height = layout.get_pixel_size()
        label_width = text_width + LABEL_PADDING[0] * 2
        label_height = text_height + LABEL_PADDING[1] * 2
        offset = GAP + LABEL_MARGIN

        # The first side with room. A region filling the screen has none: the timer would be recorded.
        left = min(max(x, 0), canvas_width - label_width)
        top = min(max(y, 0), canvas_height - label_height)
        if y - offset - label_height >= 0:
            position = (left, y - offset - label_height)
        elif y + height + offset + label_height <= canvas_height:
            position = (left, y + height + offset)
        elif x + width + offset + label_width <= canvas_width:
            position = (x + width + offset, top)
        elif x - offset - label_width >= 0:
            position = (x - offset - label_width, top)
        else:
            return

        cr.new_sub_path()
        radius = label_height / 2
        cr.arc(position[0] + label_width - radius, position[1] + radius, radius, -1.5708, 1.5708)
        cr.arc(position[0] + radius, position[1] + radius, radius, 1.5708, 4.7124)
        cr.close_path()
        cr.set_source_rgb(*self.background)
        cr.fill()

        cr.move_to(position[0] + LABEL_PADDING[0], position[1] + LABEL_PADDING[1])
        cr.set_source_rgb(*self.foreground)
        PangoCairo.show_layout(cr, layout)

        # The dot in red, over the same text
        dot = PangoCairo.create_layout(cr)
        dot.set_font_description(Pango.FontDescription(LABEL_FONT))
        dot.set_text("●", -1)
        cr.move_to(position[0] + LABEL_PADDING[0], position[1] + LABEL_PADDING[1])
        cr.set_source_rgb(*RED)
        PangoCairo.show_layout(cr, dot)


def main():
    x, y, width, height = map(int, re.fullmatch(r"(-?\d+),(-?\d+) (\d+)x(\d+)", sys.argv[1]).groups())
    app = Gtk.Application()
    app.connect("activate", lambda app: Overlay(app, x, y, width, height).present())
    app.run([])


if __name__ == "__main__":
    main()
