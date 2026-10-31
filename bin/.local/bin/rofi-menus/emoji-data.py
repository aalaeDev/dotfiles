#!/usr/bin/env python3

"""Build the row files for emoji.sh from rofimoji's data: one per category, search terms kept hidden in meta."""

import glob
import os
import re

DATA = glob.glob("/usr/lib/python3*/site-packages/picker/data")[0]
OUT = os.path.expanduser("~/.cache/rofi-emoji")

EMOJI_FILES = {
    "smileys": "emojis_smileys_emotion",
    "people": "emojis_people_body",
    "nature": "emojis_animals_nature",
    "food": "emojis_food_drink",
    "travel": "emojis_travel_places",
    "activities": "emojis_activities",
    "objects": "emojis_objects",
    "symbols": "emojis_symbols",
    "flags": "emojis_flags",
}

# How people actually search, where Unicode's names and keywords don't get there
SYNONYMS = {
    "😂": "lol lmao haha funny crying laughing",
    "🤣": "rofl lol lmao haha funny",
    "😭": "sob bawling sad crying",
    "🥲": "bittersweet smiling tear",
    "😅": "phew nervous awkward sweat",
    "😊": "happy blush cute",
    "😍": "crush love heart eyes",
    "🥰": "love adore hearts",
    "😘": "kiss mwah",
    "😎": "cool sunglasses",
    "🤔": "hmm thinking wonder",
    "🙄": "whatever eyeroll annoyed",
    "😴": "tired sleep zzz",
    "🤯": "mindblown shocked wow",
    "😡": "angry mad rage",
    "🤷": "shrug idk dunno",
    "🤦": "facepalm smh",
    "🙏": "thanks thx please pray namaste",
    "👍": "yes ok like good agree thumbsup",
    "👎": "no dislike bad thumbsdown",
    "👌": "ok okay perfect",
    "👋": "hello hi bye wave",
    "👏": "congrats bravo applause",
    "💪": "strong gym flex muscle",
    "🎉": "party congrats celebrate tada",
    "🥳": "party birthday celebrate",
    "🔥": "fire lit hot awesome",
    "✨": "sparkle magic shiny new",
    "💯": "hundred perfect exactly",
    "❤️": "love heart red",
    "💔": "heartbreak sad",
    "💀": "dead skull dying",
    "👀": "eyes look watching",
    "🚀": "launch ship deploy fast",
    "🐛": "bug debug",
    "💡": "idea tip",
    "✅": "done check yes ok",
    "❌": "no wrong cross fail",
    "⚠️": "warning caution",
    "🔒": "lock secure private",
    "☕": "coffee cafe",
    "📌": "pin important",
}

# Kaomoji are tagged by mood: each tab is the tags that belong to it
KAOMOJI_TABS = {
    "happy": ("happy", "excited", "smile", "cheer", "dance", "joy"),
    "love": ("love", "kiss", "hug", "heart"),
    "sad": ("sad", "cry", "crying", "tears", "depressed", "sorry"),
    "angry": ("angry", "mad", "rage", "annoyed", "fight"),
    "flip": ("table flip", "flip"),
    "shrug": ("whatever", "shrug", "confused", "idk"),
    "hide": ("hide", "shy", "peek", "embarrassed"),
    "animal": ("animal", "bear", "bird", "cat", "dog", "fish", "rabbit", "pig", "monkey"),
}

EMOJI_LINE = re.compile(r"^(\S+) (.*?)(?: <small>\((.*)\)</small>)?$")
KAOMOJI_LINE = re.compile(r"^(.*?\S)\s+([a-z]+(?: [a-z]+)*(?:, [a-z]+(?: [a-z]+)*)*)$")


def row(text, meta):
    return f"{text}\0meta\x1f{meta}\n"


def write(name, rows):
    with open(os.path.join(OUT, f"{name}.rows"), "w", encoding="utf-8") as f:
        f.writelines(rows)


def emoji():
    every = []
    for tab, source in EMOJI_FILES.items():
        rows = []
        with open(os.path.join(DATA, f"{source}.csv"), encoding="utf-8") as f:
            for line in f:
                match = EMOJI_LINE.match(line.rstrip("\n"))
                if not match:
                    continue
                glyph, name, keywords = match.groups()
                # Lookups ignore the variation selector, so "❤" also finds "❤️"
                extra = SYNONYMS.get(glyph) or SYNONYMS.get(glyph.replace("️", ""), "")
                rows.append(row(glyph, f"{name} {(keywords or '').replace(',', '')} {extra} {tab}"))
        write(f"emoji-{tab}", rows)
        every += rows
    write("emoji-all", every)


def kaomoji():
    tabs = {tab: [] for tab in KAOMOJI_TABS}
    every = []
    seen = set()
    with open(os.path.join(DATA, "kaomoji.csv"), encoding="utf-8") as f:
        for line in f:
            match = KAOMOJI_LINE.match(line.rstrip("\n"))
            if not match or match.group(1) in seen:
                continue
            text, tags = match.groups()
            seen.add(text)
            tags = tags.split(", ")
            current = row(text, " ".join(tags))
            every.append(current)
            for tab, members in KAOMOJI_TABS.items():
                if any(tag in members for tag in tags):
                    tabs[tab].append(current)
    write("kaomoji-all", every)
    for tab, rows in tabs.items():
        write(f"kaomoji-{tab}", rows)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    emoji()
    kaomoji()
