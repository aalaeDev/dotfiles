#!/usr/bin/env python3
"""A macOS style app switcher, always running so it opens at once.

Hyprland owns the keys (see hypr/window-switcher.lua) and writes one command per line to a FIFO.
This never takes the keyboard: the app in use keeps its focus, and releasing Super can't be missed.

A quick Super+Tab switches without drawing anything. Apps are ordered by last use, and each
app's windows too.
"""

import fcntl
import json
import os
import socket
import stat
import sys

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gio", "2.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

# Already loaded here. Inherited, every grim would load all of GTK first.
os.environ.pop("LD_PRELOAD", None)

RUNTIME = os.environ["XDG_RUNTIME_DIR"]
LOCK = f"{RUNTIME}/window-switcher.lock"
FIFO = f"{RUNTIME}/window-switcher.fifo"
SOCKET = f"{RUNTIME}/hypr/{os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')}/.socket.sock"
COLORS = os.path.expanduser("~/.config/swaync/colors.css")

HIDDEN_WORKSPACE = "special:hidden"
IGNORED_WORKSPACES = {"special:background"}  # Where the session's background apps start
SHOW_DELAY_MS = 110  # A tap released within this switches without the popup showing
REFRESH_MS = 150     # After closing or hiding: the windows need a moment to go
ICON_SIZE = 88
MIN_ICON_SIZE = 40
CARD_WIDTH = 260
MIN_CARD_WIDTH = 120
CARD_RATIO = 0.6
SCREEN_FILL = 0.9
TILE_CHROME = 32     # Each tile's padding and spacing, around its icon or thumbnail
MAX_DOTS = 5
MOVE_THRESHOLD = 2   # Pixels. The pointer resting under the popup as it opens selects nothing.

CSS = """
/* The same language as Walker and rofi: a quiet surface, filled selection, primary only for what's active */
window.switcher { background: transparent; }
.panel {
    background: @surface;
    border: 1px solid @outline_variant;
    border-radius: 18px;
    padding: 12px;
    margin: 28px;  /* Room for the shadow, inside the surface */
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.35);
    color: @on_surface;
    font-family: "SF Pro Text", "JetBrainsMono NFP", "JetBrainsMono NF";
    font-feature-settings: "tnum";
    font-weight: 500;
}
.tile { padding: 8px; border-radius: 12px; }
.tile.selected { background: @primary_container; color: @on_primary_container; }
.tile.dimmed image { opacity: 0.45; }
.dots { min-height: 5px; }
.dot { min-width: 5px; min-height: 5px; border-radius: 3px; background: @outline_variant; }
.tile.selected .dot { background: @on_primary_container; }
.thumbnail { border-radius: 8px; background: @surface_container; }
.card-title { font-size: 11px; color: @on_surface_variant; }
.tile.selected .card-title { color: @on_primary_container; }
.space { font-size: 10px; color: @on_surface_variant; }
.tile.selected .space { color: @on_primary_container; }
.name { font-size: 13px; font-weight: 600; margin-top: 10px; }
.title { font-size: 11px; color: @on_surface_variant; margin-top: 2px; }
"""


def hypr(request):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.connect(SOCKET)
        connection.sendall(request.encode())
        chunks = []
        while chunk := connection.recv(65536):
            chunks.append(chunk)
    return b"".join(chunks)


def query(name):
    return json.loads(hypr(f"j/{name}"))


def dispatch(*commands):
    hypr("[[BATCH]]" + ";".join(f"dispatch {command}" for command in commands))


def focus_command(address):
    return f'hl.dsp.focus({{window="address:{address}"}})'


def move_command(address, workspace):
    return f'hl.dsp.window.move({{workspace="{workspace}",silent=true,window="address:{address}"}})'


def close_command(address):
    return f'hl.dsp.window.close({{window="address:{address}"}})'


RESET_SUBMAP = 'hl.dsp.submap("reset")'


class Desktop:
    """What the desktop files say about an app: Hyprland only gives its window class."""

    def __init__(self):
        self.monitor = Gio.AppInfoMonitor.get()
        self.monitor.connect("changed", lambda _: self.load())
        self.load()

    def load(self):
        self.by_class = {}
        for info in Gio.AppInfo.get_all():
            wm_class = info.get_startup_wm_class()
            if wm_class:
                self.by_class[wm_class.lower()] = info
            app_id = (info.get_id() or "").removesuffix(".desktop").lower()
            self.by_class.setdefault(app_id, info)

    def find(self, wm_class):
        key = wm_class.lower()
        return self.by_class.get(key) or self.by_class.get(key.rsplit(".", 1)[-1])


class App:
    def __init__(self, key, windows, desktop):
        self.key = key
        self.windows = windows
        self.info = desktop.find(key)
        self.name = self.info.get_name() if self.info else key
        self.icon = self.info.get_icon() if self.info else None
        self.hidden = all(window["workspace"]["name"] == HIDDEN_WORKSPACE for window in windows)


# In order of last use, whichever window of each app was used last deciding its place
def group_clients(clients, desktop):
    usable = [
        client
        for client in clients
        if client["mapped"] and client["class"] and client["workspace"]["name"] not in IGNORED_WORKSPACES
    ]
    usable.sort(key=lambda client: client["focusHistoryID"])
    groups = {}
    for client in usable:
        groups.setdefault(client["class"], []).append(client)
    return [App(key, windows, desktop) for key, windows in groups.items()]


def space_label(window):
    name = window["workspace"]["name"]
    if name.startswith("special:"):
        return name.removeprefix("special:").capitalize()
    return f"Space {name}"


def workspace_target(workspace):
    return workspace["id"] if workspace.get("id", -1) > 0 else workspace["name"]


class Switcher(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.desktop = Desktop()
        self.active = False
        self.apps = []
        self.index = 0
        self.showing_windows = False
        self.window_index = 0
        self.show_timer = 0
        self.refresh_timer = 0
        self.tiles = []
        self.thumbnails = {}
        self.generation = 0        # Thumbnails arriving from an earlier session are dropped
        self.origins = {}          # Where each hidden window goes back to
        self.monitor_area = None
        self.pointer_start = None
        self.pointer_moved = False
        self.colors_changed = 0

        self.add_css_class("switcher")
        LayerShell.init_for_window(self)
        LayerShell.set_namespace(self, "window-switcher")
        LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
        LayerShell.set_exclusive_zone(self, -1)
        LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.NONE)

        self.strip = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
        self.name_label = Gtk.Label(css_classes=["name"], ellipsize=Pango.EllipsizeMode.END)
        self.title_label = Gtk.Label(css_classes=["title"], ellipsize=Pango.EllipsizeMode.END)
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, css_classes=["panel"])
        for child in (self.strip, self.name_label, self.title_label):
            panel.append(child)
        self.set_child(panel)

        pointer = Gtk.EventControllerMotion()
        pointer.connect("enter", self.on_pointer_motion)
        pointer.connect("motion", self.on_pointer_motion)
        pointer.connect("leave", lambda _: setattr(self, "pointer_start", None))
        self.add_controller(pointer)

        self.provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), self.provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )
        self.load_colors()

        self.commands = {
            "next": lambda: self.step(1),
            "prev": lambda: self.step(-1),
            "grave": lambda: self.step(1 if self.showing_windows else -1),
            "shift-grave": lambda: self.step(-1 if self.showing_windows else 1),
            "toggle-view": self.toggle_view,
            "quit": self.quit_selected,
            "hide": self.hide_selected,
            "commit": self.commit,
            "cancel": self.finish,
        }

    # --- Commands ---

    def on_fifo(self, fd, _condition):
        for line in os.read(fd, 4096).decode().split():
            try:
                self.run_command(line)
            except (OSError, ValueError, KeyError) as error:
                # Hyprland restarting, a window gone: never worth taking the switcher down
                print(f"window-switcher: {line}: {error!r}", file=sys.stderr)
                self.finish()
        return True

    def run_command(self, command):
        if command in ("next", "prev", "same") and not self.active:
            self.begin(command)
        elif self.active and command in self.commands:
            self.commands[command]()

    def begin(self, command):
        clients = query("clients")
        self.apps = group_clients(clients, self.desktop)
        if not self.apps:
            return
        self.active = True
        self.generation += 1
        self.thumbnails = {}
        self.index = 0
        active = query("activewindow")
        active_class = active.get("class")
        current = next((i for i, app in enumerate(self.apps) if app.key == active_class), None)

        # Within one app there's nothing to switch to but its windows
        if command == "same" or len(self.apps) == 1:
            self.index = current or 0
            self.showing_windows = True
            self.window_index = -1 % len(self.apps[self.index].windows) if command == "prev" else 1 % len(self.apps[self.index].windows)
        else:
            self.showing_windows = False
            # Without a focused window, the app used last is a switch too
            start = 0 if current is None else current
            self.index = (start + (-1 if command == "prev" else 1)) % len(self.apps)
        self.show_timer = GLib.timeout_add(SHOW_DELAY_MS, self.on_show_timeout)

    def step(self, delta):
        if self.showing_windows:
            self.window_index = (self.window_index + delta) % len(self.selected_app().windows)
        else:
            self.index = (self.index + delta) % len(self.apps)
        self.show_now()
        self.update_selection()

    def toggle_view(self):
        self.showing_windows = not self.showing_windows
        self.window_index = 0
        self.show_now(rebuild=True)

    def commit(self):
        app, window = self.selected_app(), self.selected_window()
        commands = [focus_command(window["address"])]
        if window["workspace"]["name"] == HIDDEN_WORKSPACE:
            commands = self.unhide_commands(app) + commands
        self.finish()
        dispatch(*commands)

    def quit_selected(self):
        windows = [self.selected_window()] if self.showing_windows else self.selected_app().windows
        dispatch(*(close_command(window["address"]) for window in windows))
        self.schedule_refresh()

    def hide_selected(self):
        app = self.selected_app()
        if app.hidden:
            commands = self.unhide_commands(app)
        else:
            commands = []
            for window in app.windows:
                if window["workspace"]["name"] != HIDDEN_WORKSPACE:
                    self.origins[window["address"]] = workspace_target(window["workspace"])
                    commands.append(move_command(window["address"], HIDDEN_WORKSPACE))
        dispatch(*commands)
        self.schedule_refresh()

    def unhide_commands(self, app):
        # Not known after a restart of this: the workspace in use is as good as any
        fallback = query("activeworkspace")["id"]
        return [
            move_command(window["address"], self.origins.pop(window["address"], fallback))
            for window in app.windows
            if window["workspace"]["name"] == HIDDEN_WORKSPACE
        ]

    def schedule_refresh(self):
        self.show_now()
        if self.refresh_timer:
            GLib.source_remove(self.refresh_timer)
        self.refresh_timer = GLib.timeout_add(REFRESH_MS, self.on_refresh)

    def on_refresh(self):
        self.refresh_timer = 0
        if not self.active:
            return False
        key = self.selected_app().key
        self.apps = group_clients(query("clients"), self.desktop)
        if not self.apps:
            self.finish()
            dispatch(RESET_SUBMAP)
            return False
        keys = [app.key for app in self.apps]
        self.index = keys.index(key) if key in keys else min(self.index, len(keys) - 1)
        self.window_index = min(self.window_index, len(self.selected_app().windows) - 1)
        self.show_now(rebuild=True)
        return False

    def finish(self):
        self.active = False
        for timer in (self.show_timer, self.refresh_timer):
            if timer:
                GLib.source_remove(timer)
        self.show_timer = self.refresh_timer = 0
        self.set_visible(False)

    # --- Selection ---

    def selected_app(self):
        return self.apps[self.index]

    def selected_window(self):
        windows = self.selected_app().windows
        return windows[self.window_index % len(windows)] if self.showing_windows else windows[0]

    def update_selection(self):
        selected = self.window_index if self.showing_windows else self.index
        for index, tile in enumerate(self.tiles):
            if index == selected:
                tile.add_css_class("selected")
            else:
                tile.remove_css_class("selected")
        self.name_label.set_label(self.selected_app().name)
        title = self.selected_window()["title"]
        self.title_label.set_label(title)
        self.title_label.set_visible(title != self.selected_app().name)

    def select(self, index):
        if self.showing_windows:
            self.window_index = index
        else:
            self.index = index
        self.update_selection()

    # --- Drawing ---

    def on_show_timeout(self):
        self.show_timer = 0
        self.show_now()
        return False

    def show_now(self, rebuild=False):
        if self.show_timer:
            GLib.source_remove(self.show_timer)
            self.show_timer = 0
        first = not self.get_visible()
        if first:
            self.load_colors()
            self.place_on_focused_monitor()
            self.pointer_start = None
            self.pointer_moved = False
        if first or rebuild:
            self.build()
        self.update_selection()
        if first:
            self.set_visible(True)

    def load_colors(self):
        # Follows the wallpaper's colors. Only on a change: loading restyles everything.
        changed = os.stat(COLORS).st_mtime_ns
        if changed != self.colors_changed:
            self.colors_changed = changed
            with open(COLORS) as colors:
                self.provider.load_from_string(colors.read() + CSS)

    def place_on_focused_monitor(self):
        name = next(monitor["name"] for monitor in query("monitors") if monitor["focused"])
        monitors = Gdk.Display.get_default().get_monitors()
        for index in range(monitors.get_n_items()):
            monitor = monitors.get_item(index)
            if monitor.get_connector() == name:
                LayerShell.set_monitor(self, monitor)
                self.monitor_area = monitor.get_geometry()

    def available_width(self):
        return (self.monitor_area.width if self.monitor_area else 1920) * SCREEN_FILL

    def build(self):
        while child := self.strip.get_first_child():
            self.strip.remove(child)
        self.tiles = self.build_cards() if self.showing_windows else self.build_icons()
        width = int(self.available_width())
        for label in (self.name_label, self.title_label):
            label.set_max_width_chars(width // 10)
        for index, tile in enumerate(self.tiles):
            self.add_tile_controllers(tile, index)
            self.strip.append(tile)
        self.set_default_size(1, 1)  # Or it keeps the size of the longest strip so far

    def app_image(self, app, size):
        image = Gtk.Image(pixel_size=size)
        if app.icon:
            image.set_from_gicon(app.icon)
        else:
            image.set_from_icon_name(app.key.lower())
        return image

    def build_icons(self):
        size = int(self.available_width() / len(self.apps) - TILE_CHROME)
        size = max(MIN_ICON_SIZE, min(ICON_SIZE, size))
        tiles = []
        for app in self.apps:
            tile = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5, css_classes=["tile"])
            if app.hidden:
                tile.add_css_class("dimmed")
            tile.append(self.app_image(app, size))
            dots = Gtk.Box(spacing=3, halign=Gtk.Align.CENTER, css_classes=["dots"])
            if len(app.windows) > 1:
                for _ in range(min(len(app.windows), MAX_DOTS)):
                    dots.append(Gtk.Box(css_classes=["dot"]))
            tile.append(dots)
            tile.append(Gtk.Label(label=space_label(app.windows[0]), css_classes=["space"]))
            self.add_drop_target(tile, app)
            tiles.append(tile)
        return tiles

    def build_cards(self):
        app = self.selected_app()
        width = int(self.available_width() / len(app.windows) - TILE_CHROME)
        width = max(MIN_CARD_WIDTH, min(CARD_WIDTH, width))
        height = int(width * CARD_RATIO)
        tiles = []
        for window in app.windows:
            tile = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, css_classes=["tile"])
            frame = Gtk.Overlay(css_classes=["thumbnail"], overflow=Gtk.Overflow.HIDDEN)
            frame.set_size_request(width, height)
            frame.set_child(Gtk.Box())
            placeholder = self.app_image(app, height // 2)
            placeholder.set_halign(Gtk.Align.CENTER)
            placeholder.set_valign(Gtk.Align.CENTER)
            frame.add_overlay(placeholder)
            picture = Gtk.Picture(content_fit=Gtk.ContentFit.CONTAIN, visible=False)
            frame.add_overlay(picture)
            tile.append(frame)
            tile.append(
                Gtk.Label(
                    label=window["title"],
                    css_classes=["card-title"],
                    ellipsize=Pango.EllipsizeMode.END,
                    max_width_chars=1,
                    hexpand=True,
                )
            )
            tile.append(Gtk.Label(label=space_label(window), css_classes=["space"]))
            self.load_thumbnail(window, picture, placeholder, width)
            tiles.append(tile)
        return tiles

    # Runs apart from drawing: a capture takes as long as 20 frames
    def load_thumbnail(self, window, picture, placeholder, width):
        def show(texture):
            placeholder.set_visible(False)
            picture.set_paintable(texture)
            picture.set_visible(True)

        stable_id = window.get("stableId")
        if not stable_id:
            return
        if stable_id in self.thumbnails:
            show(self.thumbnails[stable_id])
            return

        generation = self.generation

        def on_done(process, result):
            try:
                ok, output, _ = process.communicate_finish(result)
                if not ok or not process.get_successful() or generation != self.generation:
                    return
                self.thumbnails[stable_id] = Gdk.Texture.new_from_bytes(output)
                show(self.thumbnails[stable_id])
            except GLib.Error:
                pass  # The window closed meanwhile, or nothing to capture: the icon stays

        scale = min(1, 2 * width / max(window["size"][0], 1))  # Twice over, to stay sharp when scaled up
        process = Gio.Subprocess.new(
            ["grim", "-T", stable_id, "-t", "jpeg", "-s", f"{scale:.3f}", "-"],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE,
        )
        process.communicate_async(None, None, on_done)

    # --- Pointer ---

    def on_pointer_motion(self, _controller, x, y):
        if self.pointer_start is None:
            self.pointer_start = (x, y)
        elif abs(x - self.pointer_start[0]) + abs(y - self.pointer_start[1]) > MOVE_THRESHOLD:
            self.pointer_moved = True

    def add_tile_controllers(self, tile, index):
        def on_hover(*_):
            if self.pointer_moved and self.active:
                self.select(index)

        def on_click(*_):
            if self.active:
                self.select(index)
                self.commit()
                dispatch(RESET_SUBMAP)  # Super is still held, and would commit again

        hover = Gtk.EventControllerMotion()
        hover.connect("enter", on_hover)
        hover.connect("motion", on_hover)
        tile.add_controller(hover)
        click = Gtk.GestureClick()
        click.connect("released", on_click)
        tile.add_controller(click)

    # Files dragged onto an app open with it
    def add_drop_target(self, tile, app):
        def on_drop(_target, files, _x, _y):
            if not app.info:
                return False
            app.info.launch(files.get_files(), None)
            self.finish()
            dispatch(RESET_SUBMAP)
            return True

        def on_enter(_target, _x, _y):
            if self.active:
                self.select(self.apps.index(app))
            return Gdk.DragAction.COPY

        target = Gtk.DropTarget.new(Gdk.FileList, Gdk.DragAction.COPY)
        target.connect("drop", on_drop)
        target.connect("enter", on_enter)
        tile.add_controller(target)


def open_fifo():
    try:
        if not stat.S_ISFIFO(os.stat(FIFO).st_mode):
            os.unlink(FIFO)
            os.mkfifo(FIFO, 0o600)
    except FileNotFoundError:
        os.mkfifo(FIFO, 0o600)
    # Read and write: with no writer left a read-only FIFO would report its end forever
    fd = os.open(FIFO, os.O_RDWR | os.O_NONBLOCK)
    try:
        os.read(fd, 65536)  # Commands left from a crash mean nothing now
    except BlockingIOError:
        pass
    return fd


def main():
    lock = open(LOCK, "a")  # Not "w": a second instance would wipe the running one's pid
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0

    def activate(app):
        app.hold()
        app.switcher = Switcher(app)
        GLib.io_add_watch(open_fifo(), GLib.PRIORITY_HIGH, GLib.IO_IN, app.switcher.on_fifo)
        # Only now: hypr/window-switcher.lua takes this as ready to read commands
        lock.truncate(0)
        lock.write(f"{os.getpid()}\n")
        lock.flush()

    app = Gtk.Application()
    app.connect("activate", activate)
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
