#!/usr/bin/env python3
"""Lines up tab-separated columns in a proportional font, for labels that can only hold one string.

Measures the text with Pango and fills each gap with spaces of different widths. It only lines up
if --font, --size and --weight match the CSS of whatever shows the result.

  pad-columns.py [options] < text     Rows of the same column count line up; other lines pass through
  pad-columns.py --json [options]     The same for every "actions" label in a swaync config

Columns: the first is left-aligned, the last right-aligned, unless --align says otherwise.
"""
import argparse
import json
import sys

import gi

gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
gi.require_foreign("cairo")
import cairo  # noqa: E402
from gi.repository import Pango, PangoCairo  # noqa: E402

SPACES = (" ", "\u2009", "\u200a")  # Normal, thin and hair: narrowest last, for the exact fit
GAP = 16  # Pixels between columns


class Ruler:
    def __init__(self, font, size, weight, fractional):
        self.context = PangoCairo.FontMap.get_default().create_context()
        self.description = Pango.FontDescription(font)
        self.description.set_absolute_size(size * Pango.SCALE)
        self.description.set_weight(weight)
        if fractional:  # GTK4 places glyphs at fractions of a pixel, GTK3 at whole ones
            self.context.set_round_glyph_positions(False)
            options = cairo.FontOptions()
            options.set_hint_metrics(cairo.HINT_METRICS_OFF)
            PangoCairo.context_set_font_options(self.context, options)
        self.space_widths = [self.width(space * 20) / 20 for space in SPACES]

    def width(self, text):
        layout = Pango.Layout(self.context)
        layout.set_font_description(self.description)
        layout.set_text(text, -1)
        return layout.get_extents()[1].width / Pango.SCALE

    def filler(self, gap):
        spaces = ""
        for space, width in zip(SPACES, self.space_widths):
            count = int(gap // width)
            spaces += space * count
            gap -= count * width
        return spaces + (SPACES[-1] if gap > self.space_widths[-1] / 2 else "")

    def place(self, text, cell, start):
        """Text, then the cell at x=start. Spaces before a fallback glyph (an icon) take that font's
        width, so when the sum misses, refill the gap with hair spaces, the finest step in any font."""
        before, after = self.width(text), self.width(cell)
        gap = start - before
        filled = self.filler(gap)
        if gap <= 0 or abs(self.width(text + filled + cell) - before - after - gap) <= self.space_widths[-1]:
            return text + filled + cell
        hair = SPACES[-1]
        count = round(gap / self.space_widths[-1])
        count = round(gap / ((self.width(text + hair * count + cell) - before - after) / count))
        return text + hair * count + cell


def line_up(rows, ruler, width, align):
    """One block of rows that all have the same number of columns."""
    cells = [row.split("\t") for row in rows]
    columns = len(cells[0])
    sizes = [max(ruler.width(row[i]) for row in cells) for i in range(columns)]
    aligns = align or "l" + "l" * (columns - 2) + "r"

    # Where each column ends, with the last one pushed out to the full width
    ends, x = [], 0
    for size in sizes:
        x += size + (GAP if x and size else 0)
        ends.append(x)
    if width:
        ends[-1] = max(width, ends[-1])

    lined_up = []
    for row in cells:
        text = ""
        for i, cell in enumerate(row):
            start = ends[i] - ruler.width(cell) if aligns[i] == "r" else ends[i] - sizes[i]
            text = ruler.place(text, cell, start)
        lined_up.append(text)
    return lined_up


def pad_rows(rows, ruler, width=None, align=None):
    """Keeps the rows in order; only rows sharing a column count line up with each other."""
    groups = {}
    for row in rows:
        if "\t" in row:
            groups.setdefault(row.count("\t"), []).append(row)
    done = {}
    for group in groups.values():
        done.update(zip(group, line_up(group, ruler, width, align)))
    return [done.get(row, row) for row in rows]


def pad_config(node, rows, head, width):
    if isinstance(node, list):
        for item in node:
            pad_config(item, rows, head, width)
    elif isinstance(node, dict):
        actions = node.get("actions")
        if isinstance(actions, list):
            labels = [action for action in actions if isinstance(action, dict) and "\t" in action.get("label", "")]
            for action in labels:  # A label of several lines is a block by itself, sized to its own text
                if "\n" in action["label"]:
                    action["label"] = "\n".join(pad_rows(action["label"].split("\n"), head))
            single = [action for action in labels if "\n" not in action["label"] and "\t" in action["label"]]
            for action, label in zip(single, pad_rows([action["label"] for action in single], rows, width)):
                action["label"] = label
        for value in node.values():
            pad_config(value, rows, head, width)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", required=True)
    parser.add_argument("--size", type=float, required=True, help="Pixels")
    parser.add_argument("--weight", type=int, default=400)
    parser.add_argument("--head-weight", type=int, default=500, help="--json: weight of labels of several lines")
    parser.add_argument("--width", type=float, help="Pixels from the left edge to the end of the last column")
    parser.add_argument("--align", help="One l or r per column")
    parser.add_argument("--fractional", action="store_true", help="The text is shown by GTK4, not GTK3")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    source = sys.stdin.read()
    ruler = Ruler(args.font, args.size, args.weight, args.fractional)
    if args.json:
        config = json.loads(source)
        pad_config(config, ruler, Ruler(args.font, args.size, args.head_weight, args.fractional), args.width)
        print(json.dumps(config, ensure_ascii=False, indent=2))
    else:
        print("\n".join(pad_rows(source.rstrip("\n").split("\n"), ruler, args.width, args.align)))


if __name__ == "__main__":
    main()
