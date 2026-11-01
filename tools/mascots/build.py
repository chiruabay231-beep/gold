"""Writes the mascot SVGs (girl / boy × nine moods) for the web and the app.

    python3 tools/mascots/build.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from art import SKIN_DEFS, EXTRA_DEFS, character, STATES  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = [os.path.join(ROOT, "web", "assets", "mascots"), os.path.join(ROOT, "App", "GoldBacktest", "Resources", "Mascots")]
BOMB = '<radialGradient id="rBomb2" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="#5a6272"/><stop offset="1" stop-color="#07090d"/></radialGradient>'

for folder in OUT:
    os.makedirs(folder, exist_ok=True)
for kind in ("girl", "boy"):
    for state in STATES:
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-6 -34 172 206" width="172" height="206">'
               f'<defs>{SKIN_DEFS}{EXTRA_DEFS}{BOMB}</defs>{character(kind, state)}</svg>')
        for folder in OUT:
            with open(os.path.join(folder, f"{kind}-{state}.svg"), "w") as f:
                f.write(svg)
print("wrote", 2 * len(STATES), "mascots to", len(OUT), "folders")
