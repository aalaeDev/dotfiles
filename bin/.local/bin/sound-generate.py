#!/usr/bin/env python3

"""Synthesize the desktop sounds into the sounds package. Rerun after changing the table below.

Every note is a soft sine with a little overtone and a slow fade, all from the D major pentatonic
scale, so that any two sounds overlapping still sound fine.
"""

import math
import random
import subprocess
from pathlib import Path

# --- Configuration ---
OUTPUT = Path.home() / "dotfiles/sounds/.local/share/sounds/rice"
RATE = 48000
LEAD_IN = 0.04  # Seconds of silence: a sleeping audio device can swallow the very start of a sound
INSTANT = {"volume": 0.005, "menu": 0.005}  # Except where it has to feel attached to the key press
ATTACK = 0.006  # Seconds of fade in, any shorter and a note starts with a click
TAIL = 0.15     # Seconds that a note keeps fading after its length, to end on silence

D4, E4, FS4, A4, B4 = 293.66, 329.63, 369.99, 440.00, 493.88
D5, E5, FS5, A5 = 587.33, 659.25, 739.99, 880.00

# name: (peak in dBFS, [(frequency, start, length), ...])
SOUNDS = {
    # Alerts
    "notification":     (-23, [(A4, 0.00, 0.35), (D5, 0.09, 0.50)]),
    "critical":         (-22, [(A4, 0.00, 0.40), (E4, 0.13, 0.60)]),
    "athan":            (-20, [(D4, 0.00, 1.30), (A4, 0.45, 1.30), (D5, 0.90, 1.90)]),
    "warning":          (-23, [(E4, 0.00, 0.35), (E4, 0.22, 0.45)]),
    "battery-low":      (-23, [(FS4, 0.00, 0.50), (D4, 0.18, 0.70)]),
    "battery-critical": (-22, [(FS4, 0.00, 0.30), (D4, 0.16, 0.30), (FS4, 0.42, 0.30), (D4, 0.58, 0.60)]),
    # Connections
    "power-in":         (-25, [(D4, 0.00, 0.25), (FS4, 0.08, 0.40)]),
    "power-out":        (-25, [(FS4, 0.00, 0.25), (D4, 0.08, 0.40)]),
    "device-in":        (-25, [(A4, 0.00, 0.20), (E5, 0.08, 0.35)]),
    "device-out":       (-25, [(E5, 0.00, 0.20), (A4, 0.08, 0.35)]),
    # Actions
    "screenshot":       (-28, [(FS5, 0.00, 0.03), (A5, 0.05, 0.05)]),
    "record-start":     (-27, [(D5, 0.00, 0.10), (FS5, 0.09, 0.20)]),
    "record-stop":      (-27, [(FS5, 0.00, 0.10), (D5, 0.09, 0.20)]),
    "mic-on":           (-26, [(B4, 0.00, 0.08), (E5, 0.07, 0.16)]),
    "mic-off":          (-26, [(E5, 0.00, 0.08), (B4, 0.07, 0.16)]),
    "volume":           (-30, [(D5, 0.00, 0.05)]),
    "lock":             (-27, [(D5, 0.00, 0.22), (A4, 0.10, 0.45)]),
    "unlock":           (-27, [(A4, 0.00, 0.22), (D5, 0.10, 0.45)]),
    # Desktop
    "menu":             (-33, [(A5, 0.00, 0.04)]),
    "session-start":    (-24, [(D4, 0.00, 0.80), (A4, 0.25, 0.80), (E5, 0.50, 1.10)]),
    "session-end":      (-24, [(E5, 0.00, 0.30), (A4, 0.14, 0.40), (D4, 0.28, 0.60)]),
}


# --- Synthesis ---
def add_note(samples, lead_in, frequency, start, length):
    first = int((lead_in + start) * RATE)
    # The fade reaches -60 dB at the end of the note
    decay = math.log(1000) / (length + TAIL)
    for i in range(int((length + TAIL) * RATE)):
        t = i / RATE
        tone = (math.sin(2 * math.pi * frequency * t)
                + 0.12 * math.sin(4 * math.pi * frequency * t)
                + 0.03 * math.sin(6 * math.pi * frequency * t))
        samples[first + i] += tone * min(t / ATTACK, 1) * math.exp(-decay * t)


def render(lead_in, peak_db, notes):
    end = max(start + length for _, start, length in notes)
    samples = [0.0] * int((lead_in + end + TAIL + 0.01) * RATE)
    for note in notes:
        add_note(samples, lead_in, *note)
    scale = 10 ** (peak_db / 20) * 32767 / max(abs(s) for s in samples)
    # A little dither: long fades otherwise break into audible steps at these low levels
    return b"".join(
        round(s * scale + random.uniform(-0.5, 0.5)).to_bytes(2, "little", signed=True) for s in samples
    )


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, (peak_db, notes) in SOUNDS.items():
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
             "-c:a", "libvorbis", "-q:a", "5", str(OUTPUT / f"{name}.ogg")],
            input=render(INSTANT.get(name, LEAD_IN), peak_db, notes),
            check=True,
        )


if __name__ == "__main__":
    main()
