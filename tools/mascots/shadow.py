"""Trade characters drawn as realistic silhouettes with a golden rim light: a kneeling angler (BUY) whose line
hooks the price, and a hauler (SELL) with the rope over his shoulder.

Same picture box as the anime ones (172 × 206, viewBox from -6, -34; feet on y 156) and the same states:
easy / effort / strain / brace while pulling, money at the TP, snap at the SL. POINTS gives where the line starts."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import art  # noqa: E402
from art import coins  # noqa: E402
from crew import aura  # noqa: E402

DEFS = art.SKIN_DEFS + art.EXTRA_DEFS + """
<linearGradient id="shade" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#262c3a"/><stop offset=".5" stop-color="#0e1118"/><stop offset="1" stop-color="#030406"/></linearGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff1b8"/><stop offset=".45" stop-color="#eebd4a"/><stop offset="1" stop-color="#a7771f"/></linearGradient>
<radialGradient id="backlight" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#fff4cf" stop-opacity=".55"/><stop offset="1" stop-color="#fff4cf" stop-opacity="0"/></radialGradient>
<filter id="rim" x="-25%" y="-25%" width="150%" height="150%">
  <feMorphology in="SourceAlpha" operator="dilate" radius="1" result="d"/>
  <feFlood flood-color="#f6cf6a"/><feComposite in2="d" operator="in" result="edge"/>
  <feGaussianBlur in="edge" stdDeviation="2.2" result="glow"/>
  <feMerge><feMergeNode in="glow"/><feMergeNode in="edge"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
<filter id="rimHot" x="-25%" y="-25%" width="150%" height="150%">
  <feMorphology in="SourceAlpha" operator="dilate" radius="1.4" result="d"/>
  <feFlood flood-color="#ff4a2a"/><feComposite in2="d" operator="in" result="edge"/>
  <feGaussianBlur in="edge" stdDeviation="3.2" result="glow"/>
  <feMerge><feMergeNode in="glow"/><feMergeNode in="glow"/><feMergeNode in="edge"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
"""
F = 'fill="url(#shade)"'


def rot(p, a, c):
    r = math.radians(a)
    dx, dy = p[0] - c[0], p[1] - c[1]
    return (round(c[0] + dx * math.cos(r) - dy * math.sin(r), 1), round(c[1] + dx * math.sin(r) + dy * math.cos(r), 1))


def grass(x0, x1, y):
    out = []
    for i, x in enumerate(range(x0, x1, 3)):
        h = 6 + (i * 7) % 7
        lean = ((i * 5) % 7) - 3
        out.append(f'<path d="M{x - 1} {y} Q{x + lean * .4} {y - h * .6} {x + lean} {y - h} Q{x + lean * .3 + .8} {y - h * .5} {x + 1.2} {y}Z" {F}/>')
    return "".join(out)


def effects(state):
    if state == "easy":
        return ('<text x="18" y="40" font-size="15" fill="#f2c14e" font-family="Georgia, serif">&#9834;'
                '<animateTransform attributeName="transform" type="translate" values="0 6; -8 -14" dur="2s" repeatCount="indefinite"/>'
                '<animate attributeName="opacity" values="0;1;0" dur="2s" repeatCount="indefinite"/></text>')
    if state == "strain":
        return art.sweat()
    if state == "brace":
        return art.steam_puffs()
    return ""


TWITCH = {"easy": ("0 0; -.5 .3; 0 0", "2.2s"), "effort": ("0 0; -1.2 .9; .5 -.4; 0 0", ".8s"),
          "strain": ("0 0; -2 1.4; .7 -.7; -1.4 1; 0 0", ".42s"), "brace": ("0 0; -2.6 1.8; 1 -.9; -2 1.4; .5 -.4; 0 0", ".26s")}
SWAY = {"effort": ("1.2", ".9s"), "strain": ("2", ".45s"), "brace": ("2.4", ".22s")}


def twitch(state, inner):
    values, dur = TWITCH[state]
    return f'<g><animateTransform attributeName="transform" type="translate" values="{values}" dur="{dur}" repeatCount="indefinite"/>{inner}</g>'


def sway(state, c):
    if state not in SWAY:
        return art.MOTIONS["breathe"]
    amp, dur = SWAY[state]
    return f'<animateTransform attributeName="transform" type="rotate" values="0 {c[0]} {c[1]}; {amp} {c[0]} {c[1]}; 0 {c[0]} {c[1]}" dur="{dur}" repeatCount="indefinite"/>'


# ======================= the angler: kneeling on the right knee, facing the chart (left) =======================
KNEE = (98, 152)
ROD_BUTT = (78, 105)
ANGLER = {"easy": dict(lean=-2, tip=(4, 46)), "effort": dict(lean=3, tip=(6, 56)),
          "strain": dict(lean=8, tip=(10, 66)), "brace": dict(lean=11, tip=(13, 72))}


def ground():
    return (f'<path d="M30 156 Q32 149 44 148 L134 147 Q146 148 148 156 Z" {F}/>' + grass(30, 60, 150) + grass(112, 150, 150)
            + '<path d="M28 158 H150" stroke="#f6cf6a" stroke-width=".6" opacity=".35"/>')


def angler_body():
    head = (f'<ellipse cx="70" cy="60" rx="9" ry="10.2" {F}/>'
            f'<path d="M72 68 Q78 72 82 74 L74 80 Q70 74 70 70Z" {F}/>'
            # cap: crown, brim to the left, a button on top
            f'<path d="M60.5 58 Q60 45.5 71.5 45 Q82.5 45.5 81.5 57.5 Q71 54 60.5 58Z" {F}/>'
            f'<path d="M62 56.5 Q53 56.5 46.5 60.2 Q55 61.4 63.5 59.4Z" {F}/><circle cx="71.5" cy="45" r="1.6" {F}/>'
            f'<path d="M78 62 q2.6 1 2.2 4" stroke="#262c3a" stroke-width="1.2" fill="none"/>')
    torso = (f'<path d="M67 72 Q59 84 61 98 Q63 109 72 115 L93 118 Q101 113 103 102 Q107 86 99 73 Q91 65 79 66 Q72 67 67 72Z" {F}/>'
             # hood bunched at the neck
             f'<path d="M78 66 Q86 60 94 66 Q92 72 84 72Z" {F}/>')
    pack = (f'<path d="M97 75 Q112 72 115 83 L117 105 Q116 113 105 113 L99 111 Q101 92 97 75Z" {F}/>'
            f'<path d="M101 73 q6 -6 11 1" stroke="url(#shade)" stroke-width="2.2" fill="none"/>'
            f'<path d="M98 80 Q90 92 88 104" stroke="#262c3a" stroke-width="1.4" fill="none"/>'
            f'<path d="M104 92 h9 M104 100 h10" stroke="#262c3a" stroke-width="1.1"/>')
    front_leg = (f'<path d="M71 104 Q59 100 50 103 Q44 109 51 116 Q62 119 75 118Z" {F}/>'
                 f'<path d="M45 108 Q43 127 45.5 145 L56 145 Q56 127 58.5 110Z" {F}/>'
                 f'<path d="M40 146 Q40 140 48 140 L58 141 Q61 150 58.5 156 L37 156 Q35 150 40 146Z" {F}/>')
    back_leg = (f'<path d="M84 111 Q97 111 101 120 Q105 136 103 150 L90 152 Q88 132 82 118Z" {F}/>'
                f'<path d="M92 145 Q112 143 128 145 L130 154 Q110 156 92 155Z" {F}/>'
                f'<path d="M126 143 Q137 145 139 154 L128 155Z" {F}/>')
    return head, torso, pack, front_leg, back_leg


FLEX = {"easy": (1.5, "2.2s"), "effort": (3, ".9s"), "strain": (4.5, ".45s"), "brace": (5.5, ".28s")}


def flexing(paths, state):
    """Arm outlines that bend at the elbow and back, in time with the pull: `paths(e)` gives them for a bend e."""
    if state not in FLEX:
        return "".join(f'<path d="{d}" {F}/>' for d in paths(0))
    amp, dur = FLEX[state]
    rest, bent = paths(0), paths(amp)
    return "".join(f'<path d="{a}" {F}><animate attributeName="d" values="{a};{b};{a}" dur="{dur}" repeatCount="indefinite"/></path>' for a, b in zip(rest, bent))


def rod_and_arms(tip, broken=False, state=None):
    b = ROD_BUTT
    straight = (4, 46)
    # hands on the straight part; the rod bends beyond them toward the (lower) tip
    h1 = (b[0] + (straight[0] - b[0]) * .26, b[1] + (straight[1] - b[1]) * .26)
    h2 = (b[0] + (straight[0] - b[0]) * .42, b[1] + (straight[1] - b[1]) * .42)
    ctrl = (b[0] + (straight[0] - b[0]) * .7, b[1] + (straight[1] - b[1]) * .7)
    def paths(e):
        # e bends the elbows: the upper arm bulges out, the forearms bow down toward the pull
        return [f"M85 74 Q{92 + e:.1f} {86 + e * .4:.1f} 85 97 Q80 101 74 99 Q{77 + e * .6:.1f} 88 77 79Z",
                f"M80 92 Q{70 - e * .3:.1f} {h1[1] - 1 + e:.1f} {h1[0]:.1f} {h1[1] - 3:.1f} L{h1[0] - 1:.1f} {h1[1] + 4:.1f} Q{70 - e * .3:.1f} {h1[1] + 6 + e:.1f} 81 100Z",
                f"M77 71 Q{63 - e * .2:.1f} {h2[1] - 4 + e * 1.2:.1f} {h2[0] + 1:.1f} {h2[1] - 3:.1f} L{h2[0]:.1f} {h2[1] + 3:.1f} Q{64 - e * .2:.1f} {h2[1] + 2 + e * 1.2:.1f} 79 79Z"]
    arms = (flexing(paths, state) + f'<ellipse cx="{h1[0]:.1f}" cy="{h1[1]:.1f}" rx="4.6" ry="4.2" {F}/>'
            f'<ellipse cx="{h2[0]:.1f}" cy="{h2[1]:.1f}" rx="4.2" ry="3.8" {F}/>')
    if broken:
        rod = (f'<path d="M{b[0]} {b[1]} L{h2[0] - 10:.1f} {h2[1] - 8:.1f}" stroke="#05060a" stroke-width="2.4" stroke-linecap="round"/>'
               f'<path d="M{h2[0] - 10:.1f} {h2[1] - 8:.1f} l-5 -1 m5 1 l-2 -6" stroke="#05060a" stroke-width="1.4" stroke-linecap="round"/>')
    else:
        rod = (f'<path d="M{b[0]} {b[1]} Q{ctrl[0]:.1f} {ctrl[1]:.1f} {tip[0]} {tip[1]}" stroke="#05060a" stroke-width="2.6" fill="none" stroke-linecap="round"/>'
               f'<path d="M{b[0]} {b[1]} Q{ctrl[0]:.1f} {ctrl[1]:.1f} {tip[0]} {tip[1]}" stroke="#f6cf6a" stroke-width=".5" fill="none" opacity=".45"/>')
        for k in (.55, .75, .9):
            x = (1 - k) ** 2 * b[0] + 2 * (1 - k) * k * ctrl[0] + k * k * tip[0]
            y = (1 - k) ** 2 * b[1] + 2 * (1 - k) * k * ctrl[1] + k * k * tip[1]
            rod += f'<circle cx="{x:.1f}" cy="{y + 1.6:.1f}" r="1.3" fill="none" stroke="#0e1118" stroke-width=".9"/>'
    reel = (f'<path d="M{b[0] - 9:.1f} {b[1] - 6:.1f} l-1 5" stroke="#0e1118" stroke-width="2"/>'
            f'<circle cx="{b[0] - 10:.1f}" cy="{b[1] - .5:.1f}" r="4.4" {F}/><path d="M{b[0] - 10:.1f} {b[1] - .5:.1f} l-5 3" stroke="#0e1118" stroke-width="1.6" stroke-linecap="round"/>')
    return rod + reel + arms


def angler(state):
    head, torso, pack, front_leg, back_leg = angler_body()
    if state in ANGLER:
        cfg = ANGLER[state]
        person = back_leg + pack + torso + front_leg + twitch(state, rod_and_arms(cfg["tip"], state=state)) + head
        body = f'<g transform="rotate({cfg["lean"]} {KNEE[0]} {KNEE[1]})"><g>{sway(state, KNEE)}{person}</g></g>'
        rim = "rimHot" if state == "brace" else "rim"
        under = aura(84, 100, 56) if state == "brace" else '<ellipse cx="84" cy="96" rx="44" ry="40" fill="url(#backlight)"/>'
        return f'{under}<g filter="url(#{rim})">{ground()}{body}</g>{effects(state)}'
    if state == "money":
        arm_up = (f'<path d="M77 71 Q66 56 60 40 L66 37 Q72 54 82 70Z" {F}/><ellipse cx="62" cy="37" rx="4.4" ry="4" {F}/>'
                  f'<path d="M85 74 Q92 86 85 97 Q80 101 74 99 Q77 88 77 79Z" {F}/>')
        bag = ('<path d="M62 36 q-13 2 -13 -14 q0 -12 13 -14 q13 2 13 14 q0 16 -13 14z" fill="url(#gold)" stroke="#a7771f"/>'
               '<path d="M56 9 q6 -6 12 0" stroke="#a7771f" stroke-width="2" fill="none"/><text x="62" y="28" text-anchor="middle" font-size="13" font-weight="900" fill="#7d5714" font-family="Georgia, serif">$</text>')
        hop = art.MOTIONS["hop"]
        person = back_leg + pack + torso + front_leg + arm_up + head
        return (art.bills_rain() + f'<g filter="url(#rim)">{ground()}<g>{hop}{person}</g></g><g>{hop}{bag}</g>'
                + coins() + art.burst(28, 30, "#f2c14e", "0s") + art.burst(138, 34, "#1fd29d", ".6s"))
    person = back_leg + pack + torso + front_leg + rod_and_arms((4, 46), broken=True) + head
    body = f'<g transform="rotate(30 104 150)"><g>{art.MOTIONS["shake"]}{person}</g></g>'
    return f'<g filter="url(#rim)">{ground()}{body}</g>' + '<text x="40" y="36" font-size="26" font-weight="900" fill="#ff5a70" font-family="Georgia, serif">!</text>' + art.rain_cloud()


# ======================= the hauler: rope over the shoulder, walking away from the chart (right) =======================
FEET = (84, 156)
HAULER = {"easy": 6, "effort": 15, "strain": 24, "brace": 30}
ROPE_FROM = (80, 57)


def hauler_body(arms="rope", state=None):
    head = (f'<ellipse cx="89" cy="47" rx="9" ry="10.2" {F}/>'
            f'<path d="M84 55 Q86 60 85 64 L93 62 Q93 58 94 55Z" {F}/>'
            # knit cap with a folded band
            f'<path d="M79.5 45 Q79 33 89.5 32.5 Q100 33 99 45 Q89 42 79.5 45Z" {F}/><path d="M80 44.5 Q89 41.5 99 44.5" stroke="#262c3a" stroke-width="1.6" fill="none"/>'
            f'<path d="M98 49 q2.4 1 2 3.6" stroke="#262c3a" stroke-width="1.1" fill="none"/>')
    torso = (f'<path d="M80 60 Q72 74 73 92 Q75 105 80 111 L99 111 Q103 96 101 80 Q99 64 91 58Z" {F}/>'
             f'<path d="M80 60 Q76 56 81 54 Q88 54 91 58Z" {F}/>')
    back_leg = (f'<path d="M79 104 Q73 114 66 126 L74.5 132 Q83 120 89 110Z" {F}/>'
                f'<path d="M66 124 Q60 138 54 150 L62.5 153.5 Q68 140 74.5 130Z" {F}/>'
                f'<path d="M47 151 Q49 146.5 57 147 L64 150 L62.5 156 L45.5 156Z" {F}/>')
    front_leg = (f'<path d="M86 106 Q99 112 109 122 L102.5 130.5 Q94 120 84 115Z" {F}/>'
                 f'<path d="M100.5 122 Q104.5 138 100.5 152 L108.5 152 Q112.5 138 108.5 124Z" {F}/>'
                 f'<path d="M96.5 150 L112 150 Q119 152 119 156 L96.5 156Z" {F}/>')
    if arms == "rope":
        def paths(e):
            # e bends the elbows out as he hauls the rope down over his shoulder
            return [f"M93 62 Q{104 + e:.1f} {66 + e * .5:.1f} 104 77 Q100 81 96.5 79 Q{98.5 + e * .6:.1f} 71 90 67Z",
                    f"M86 64 Q{94 - e * .4:.1f} {74 + e:.1f} 98.5 82 L94.5 86 Q{88 - e * .4:.1f} {78 + e:.1f} 82 70Z"]
        arm = (flexing(paths, state) + f'<ellipse cx="102.5" cy="77.5" rx="4.4" ry="4" {F}/><ellipse cx="97.5" cy="84.5" rx="4.2" ry="3.8" {F}/>')
        rope = (f'<path d="M{ROPE_FROM[0]} {ROPE_FROM[1]} Q90 52 96 60 Q101 68 102.5 77.5 L98 85 Q100 98 108 112 Q112 120 110 132" stroke="#c9a46a" stroke-width="1.7" fill="none" stroke-linecap="round"/>'
                f'<path d="M{ROPE_FROM[0]} {ROPE_FROM[1]} Q90 52 96 60 Q101 68 102.5 77.5" stroke="#6b4a1f" stroke-width="1.7" fill="none" stroke-dasharray="1 2" opacity=".7"/>')
        return back_leg + torso + front_leg + arm + head, rope
    if arms == "money":
        arm = (f'<path d="M93 62 Q106 52 110 36 L116 38 Q112 56 98 68Z" {F}/><ellipse cx="113" cy="36" rx="4.4" ry="4" {F}/>'
               f'<path d="M86 64 Q80 76 84 88 L89 86 Q86 76 91 67Z" {F}/>')
        return back_leg + torso + front_leg + arm + head, ""
    arm = f'<path d="M93 62 Q106 58 116 50 L118 55 Q108 64 96 68Z" {F}/><path d="M86 64 Q78 76 70 80 L68 75 Q76 70 82 62Z" {F}/>'
    return back_leg + torso + front_leg + arm + head, '<path d="M70 78 q-8 -6 -6 -16 q2 -8 -8 -12" stroke="#c9a46a" stroke-width="1.7" fill="none"/>'


def hauler(state):
    if state in HAULER:
        lean = HAULER[state]
        person, rope = hauler_body(state=state)
        a0 = person.index('<path d="M93 62')
        twitchy = twitch(state, person[a0:person.index('<ellipse cx="89"')])
        person = person[:a0] + twitchy + person[person.index('<ellipse cx="89"'):]
        body = f'<g transform="rotate({lean} {FEET[0]} {FEET[1]})"><g>{sway(state, FEET)}{person}{rope}</g></g>'
        rim = "rimHot" if state == "brace" else "rim"
        dust = ('<path d="M36 160 q-6 -4 -12 0 M46 162 q-4 -6 -10 -4" stroke="#9aa3b2" stroke-width="1.4" fill="none" opacity=".6"/>' if state != "easy" else "")
        under = aura(84, 104, 56) if state == "brace" else '<ellipse cx="88" cy="98" rx="40" ry="46" fill="url(#backlight)"/>'
        return f'{under}{dust}<g filter="url(#{rim})">{body}</g>{effects(state)}'
    if state == "money":
        person, _ = hauler_body("money")
        bag = ('<path d="M113 34 q-13 2 -13 -14 q0 -12 13 -14 q13 2 13 14 q0 16 -13 14z" fill="url(#gold)" stroke="#a7771f"/>'
               '<text x="113" y="26" text-anchor="middle" font-size="13" font-weight="900" fill="#7d5714" font-family="Georgia, serif">$</text>')
        hop = art.MOTIONS["hop"]
        return (art.bills_rain() + f'<g filter="url(#rim)"><g>{hop}{person}</g></g><g>{hop}{bag}</g>'
                + coins() + art.burst(28, 30, "#f2c14e", "0s") + art.burst(138, 34, "#ff8fa6", ".6s"))
    person, rope = hauler_body("fallen")
    body = f'<g transform="translate(-42 2) rotate(58 84 156)"><g>{art.MOTIONS["shake"]}{person}{rope}</g></g>'
    return f'<g filter="url(#rim)">{body}</g>' + '<text x="120" y="70" font-size="26" font-weight="900" fill="#ff5a70" font-family="Georgia, serif">!</text>' + art.rain_cloud()


EFFORTS = ("easy", "effort", "strain", "brace")
PICTURES = {}
for st in EFFORTS + ("money", "snap"):
    PICTURES[f"angler-{st}"] = angler(st)
    PICTURES[f"hauler-{st}"] = hauler(st)

POINTS = {"angler": {st: rot(ANGLER[st]["tip"], ANGLER[st]["lean"], KNEE) for st in EFFORTS},
          "hauler": {st: rot(ROPE_FROM, HAULER[st], FEET) for st in EFFORTS}}
