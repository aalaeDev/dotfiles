#!/usr/bin/env python3

# Space in Nemo: answers Nemo's org.nemo.Preview calls and shows the file in Sushi.
# Started by D-Bus (see nemo/.local/share/dbus-1/services) and exits once idle.

import os
import re

from gi.repository import Gio, GLib

SUSHI = ("org.gnome.NautilusPreviewer", "/org/gnome/NautilusPreviewer", "org.gnome.NautilusPreviewer2")
IDLE_SECONDS = 30
# GtkDirectionType values Sushi sends for the arrow keys
UP, DOWN, LEFT, RIGHT = 2, 3, 4, 5

INTERFACE = Gio.DBusNodeInfo.new_for_xml("""
<node>
  <interface name="org.nemo.Preview">
    <method name="ShowFile">
      <arg type="s" direction="in" name="uri"/>
      <arg type="i" direction="in" name="xid"/>
      <arg type="b" direction="in" name="closeIfAlreadyShown"/>
    </method>
    <method name="Close"/>
  </interface>
</node>
""").interfaces[0]

loop = GLib.MainLoop()
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
current = None
idle_timer = 0


def call_sushi(method, args):
    bus.call(*SUSHI, method, args, None, Gio.DBusCallFlags.NONE, -1, None, None)


def show(uri, close_if_shown=False):
    global current
    current = uri
    # Empty handle and token: a Wayland client has no parent window to pass from Nemo's xid of 0
    call_sushi("ShowFile", GLib.Variant("(ssbs)", (uri, "", close_if_shown, "")))


def natural_key(name):
    return [int(part) if part.isdigit() else part.casefold() for part in re.split(r"(\d+)", name)]


def step(direction):
    """Show the file before or after the current one: Nemo offers no way to read its own order."""
    file = Gio.File.new_for_uri(current)
    path = file.get_path()
    if path is None:
        return
    folder, name = os.path.split(path)
    with os.scandir(folder) as entries:
        visible = [e for e in entries if not e.name.startswith(".")]
    names = [e.name for e in sorted(visible, key=lambda e: (not e.is_dir(), natural_key(e.name)))]
    if name not in names:
        return
    target = names.index(name) + (-1 if direction in (UP, LEFT) else 1)
    if 0 <= target < len(names):
        show(Gio.File.new_for_path(os.path.join(folder, names[target])).get_uri())


def set_idle(idle):
    global idle_timer
    if idle_timer:
        GLib.source_remove(idle_timer)
        idle_timer = 0
    if idle:
        idle_timer = GLib.timeout_add_seconds(IDLE_SECONDS, loop.quit)


def on_method_call(_bus, _sender, _path, _iface, method, params, invocation):
    if method == "ShowFile":
        uri, _xid, close_if_shown = params.unpack()
        set_idle(False)
        show(uri, close_if_shown)
    else:
        call_sushi("Close", None)
    invocation.return_value(None)


def on_selection(_bus, _sender, _path, _iface, _signal, params):
    step(params.unpack()[0])


def on_properties(_bus, _sender, _path, _iface, _signal, params):
    changed = params.unpack()[1]
    if "Visible" in changed:
        set_idle(not changed["Visible"])


bus.register_object("/org/nemo/Preview", INTERFACE, on_method_call, None, None)
bus.signal_subscribe(SUSHI[0], SUSHI[2], "SelectionEvent", SUSHI[1], None, Gio.DBusSignalFlags.NONE, on_selection)
bus.signal_subscribe(SUSHI[0], "org.freedesktop.DBus.Properties", "PropertiesChanged", SUSHI[1], SUSHI[2],
                     Gio.DBusSignalFlags.NONE, on_properties)
Gio.bus_own_name_on_connection(bus, "org.nemo.Preview", Gio.BusNameOwnerFlags.NONE, None, lambda *_: loop.quit())
set_idle(True)
loop.run()
