"""Writes the mascot SVGs (girl / boy × nine moods) for the web and the app.

    python3 tools/mascots/build.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from art import SKIN_DEFS, EXTRA_DEFS, character, STATES  # noqa: E402
import crew  # noqa: E402

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
# The trade characters (angler / hauler) in each effort, and where their line starts.
import json  # noqa: E402

# (Web only for now: the app copies every resource into one folder, so two sets with the same file names clash.)
CREW = [os.path.join(ROOT, "web", "assets", "crew")]
for folder in CREW:
    os.makedirs(folder, exist_ok=True)
    for old in os.listdir(folder):
        if old.endswith(".svg"):
            os.remove(os.path.join(folder, old))
for name, picture in crew.PICTURES.items():
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-6 -34 172 206" width="172" height="206">'
           f'<defs>{crew.DEFS}</defs>{picture}</svg>')
    for folder in CREW:
        with open(os.path.join(folder, f"{name}.svg"), "w") as f:
            f.write(svg)
# The same characters as silhouettes with a golden rim light.
import shadow  # noqa: E402

SHADOW = [os.path.join(ROOT, "web", "assets", "crew2")]
for folder in SHADOW:
    os.makedirs(folder, exist_ok=True)
for name, picture in shadow.PICTURES.items():
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-6 -34 172 206" width="172" height="206">'
           f'<defs>{shadow.DEFS}</defs>{picture}</svg>')
    for folder in SHADOW:
        with open(os.path.join(folder, f"{name}.svg"), "w") as f:
            f.write(svg)
points = dict(crew.POINTS, shadow=shadow.POINTS)
with open(os.path.join(ROOT, "web", "assets", "crew", "points.js"), "w") as f:
    f.write("// Made by tools/mascots/build.py: where each trade character's line starts (picture coordinates).\n")
    f.write("window.CREW_POINTS = " + json.dumps(points) + ";\n")
print("wrote", 2 * len(STATES), "mascots,", len(crew.PICTURES), "anime and", len(shadow.PICTURES), "silhouette trade characters")
