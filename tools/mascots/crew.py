"""Trade characters: the angler (BUY, fishes the price up to the TP) and the hauler (SELL, drags it down to the TP).

Each stands with its feet (local y 156) on the TP; the line starts at ROD_TIP / HAULER_HAND (local coordinates of the
172 × 206 picture whose viewBox starts at -6, -34)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import art  # noqa: E402
from art import SKIN_DEFS, EXTRA_DEFS, INK, star, eyes, brows, MOUTHS, tears, rain_cloud, coins, MOTIONS  # noqa: E402

DEFS = SKIN_DEFS + EXTRA_DEFS + """
<radialGradient id="rBomb2" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="#5a6272"/><stop offset="1" stop-color="#07090d"/></radialGradient>
<linearGradient id="olive" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a3ad6a"/><stop offset="1" stop-color="#4f5a2a"/></linearGradient>
<linearGradient id="khaki" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e2c98f"/><stop offset="1" stop-color="#9c7f45"/></linearGradient>
<linearGradient id="lens" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2b5b66"/><stop offset=".55" stop-color="#0b1a22"/><stop offset="1" stop-color="#04090c"/></linearGradient>
<linearGradient id="navyHair" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3c4f7a"/><stop offset="1" stop-color="#151c33"/></linearGradient>
<linearGradient id="silverHair" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset=".45" stop-color="#cdd3e6"/><stop offset="1" stop-color="#6d7391"/></linearGradient>
<linearGradient id="cooler" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4f8dff"/><stop offset="1" stop-color="#1c4fb8"/></linearGradient>
<linearGradient id="boot" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3f5a33"/><stop offset="1" stop-color="#1d2a17"/></linearGradient>
<linearGradient id="tank" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a3f4c"/><stop offset="1" stop-color="#121418"/></linearGradient>
<linearGradient id="cargo" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5c6650"/><stop offset="1" stop-color="#2c3326"/></linearGradient>
<linearGradient id="glove" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e0b27a"/><stop offset="1" stop-color="#9a6a35"/></linearGradient>
<linearGradient id="bandana" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff5a6e"/><stop offset="1" stop-color="#a3132a"/></linearGradient>
"""


def rot(p, a, c):
    r = math.radians(a)
    dx, dy = p[0] - c[0], p[1] - c[1]
    return (round(c[0] + dx * math.cos(r) - dy * math.sin(r), 1), round(c[1] + dx * math.sin(r) + dy * math.cos(r), 1))


def skin_face():
    return '<path d="M50 58 Q50 92 80 95 Q110 92 110 58 Q110 31 80 31 Q50 31 50 58Z" fill="url(#skin)"/>'


def blush():
    return "".join(f'<ellipse cx="{x}" cy="78" rx="5.5" ry="3" fill="#ff8fa6" opacity=".5"/>' for x in (60, 100))


# ======================= the angler (BUY) =======================
ROD_TIP = (14, 40)


def angler_head(state):
    back = '<path d="M48 64 Q46 32 80 30 Q114 32 112 64 L110 78 L104 64 L56 64 L50 78Z" fill="url(#navyHair)"/>'
    bangs = '<path d="M53 44 L57 55 L61 45 L66 57 L71 45 L77 55 L83 45 L89 56 L95 45 L100 55 L106 44Z" fill="url(#navyHair)"/>'
    hat = ('<path d="M53 42 Q55 15 80 14 Q105 15 107 42Z" fill="url(#olive)"/><rect x="54" y="33" width="52" height="5" fill="url(#gold)"/>'
           '<ellipse cx="80" cy="43" rx="40" ry="8.5" fill="url(#olive)" stroke="#3e4720" stroke-width=".8"/>'
           '<path d="M44 42 Q80 51 116 42" stroke="#c9d08f" stroke-width="1" fill="none" opacity=".5"/>'
           # a fly lure pinned to the hat
           '<path d="M104 28 l6 -4 M104 28 l7 1 M104 28 l5 4" stroke="#ff8a3d" stroke-width="1.6" stroke-linecap="round"/><circle cx="104" cy="28" r="1.8" fill="url(#gold)"/>')
    face = [skin_face(), blush()]
    if state in ("win", "lose", "money"):
        # aviator sunglasses
        glint = ('<path d="M60 60 l5 -3" stroke="#fff" stroke-width="1.6" stroke-linecap="round" opacity=".8"><animate attributeName="opacity" values=".1;.9;.1" dur="1.6s" repeatCount="indefinite"/></path>'
                 if state == "win" else "")
        lens = "url(#lens)"
        face.append(f'<path d="M55 59 h21 q1 10 -9 12 q-11 1 -12 -12z M84 59 h21 q-1 13 -12 12 q-10 -2 -9 -12z" fill="{lens}" stroke="url(#gold)" stroke-width="1.6"/>'
                    '<path d="M76 61 q4 -3 8 0" stroke="url(#gold)" stroke-width="1.6" fill="none"/><path d="M55 60 l-5 -2 M105 60 l5 -2" stroke="url(#gold)" stroke-width="1.4"/>' + glint)
        if state == "money":
            face.append('<text x="66" y="69" text-anchor="middle" font-size="9" font-weight="900" fill="url(#gold)" font-family="Georgia, serif">$</text>'
                        '<text x="94" y="69" text-anchor="middle" font-size="9" font-weight="900" fill="url(#gold)" font-family="Georgia, serif">$</text>')
        face.append(f'<path d="M57 53 Q65 50 73 53 M103 53 Q95 50 87 53" stroke="{INK}" stroke-width="1.8" fill="none" stroke-linecap="round"/>' if state != "lose"
                    else f'<path d="M57 52 Q64 49 73 55 M103 52 Q96 49 87 55" stroke="{INK}" stroke-width="1.8" fill="none" stroke-linecap="round"/>')
        face.append({"win": MOUTHS["smirk"] if "smirk" in MOUTHS else MOUTHS["grin"], "lose": MOUTHS["wavy"], "money": MOUTHS["grin"]}[state])
    else:  # snapped: the glasses knocked down the nose, crying eyes
        face.append(eyes("cry", "irisG") + brows("cry") + MOUTHS["wail"])
        face.append('<g transform="rotate(-16 80 80)"><path d="M58 76 h17 q1 8 -8 9 q-9 1 -9 -9z M85 76 h17 q-1 10 -9 9 q-9 -1 -8 -9z" fill="url(#lens)" stroke="url(#gold)" stroke-width="1.4"/></g>')
    return back + "".join(face) + bangs + hat


def angler_body(rod="whole"):
    cooler = ('<rect x="46" y="132" width="68" height="24" rx="3" fill="url(#cooler)" stroke="#123a8a" stroke-width=".8"/>'
              '<rect x="44" y="128" width="72" height="7" rx="2.5" fill="#f4f7fb" stroke="#9aa3b2" stroke-width=".6"/>'
              '<path d="M66 140 h28" stroke="#9fc0ff" stroke-width="2" stroke-linecap="round"/><text x="80" y="151" text-anchor="middle" font-size="6" font-weight="800" fill="#cfe0ff" font-family="sans-serif" letter-spacing="1">ICE</text>')
    legs = ('<path d="M74 128 L55 131" stroke="#3b4a6b" stroke-width="9" stroke-linecap="round"/><path d="M84 129 L64 133" stroke="#3b4a6b" stroke-width="9" stroke-linecap="round"/>'
            '<path d="M55 131 L53 154 M64 133 L64 155" stroke="url(#boot)" stroke-width="10" stroke-linecap="round"/>'
            '<ellipse cx="51" cy="156" rx="7" ry="3.2" fill="#1d2a17"/><ellipse cx="62" cy="157" rx="7" ry="3.2" fill="#1d2a17"/>'
            '<path d="M49 140 h10 M60 142 h9" stroke="#5d7a4c" stroke-width="1.4"/>')
    shirt = '<path d="M58 96 Q80 88 102 96 L106 124 Q80 130 54 124Z" fill="#0f5b45"/>'
    vest = ('<path d="M58 97 Q68 92 74 94 L76 126 Q64 127 55 124Z M102 97 Q92 92 86 94 L84 126 Q96 127 105 124Z" fill="url(#khaki)" stroke="#8a6d38" stroke-width=".7"/>'
            '<rect x="59" y="106" width="11" height="8" rx="1" fill="#b39257" stroke="#7d6232" stroke-width=".6"/><rect x="90" y="106" width="11" height="8" rx="1" fill="#b39257" stroke="#7d6232" stroke-width=".6"/>'
            '<rect x="60" y="116" width="10" height="7" rx="1" fill="#b39257" stroke="#7d6232" stroke-width=".6"/><rect x="90" y="116" width="10" height="7" rx="1" fill="#b39257" stroke="#7d6232" stroke-width=".6"/>'
            '<path d="M59 106 h11 M90 106 h11" stroke="#7d6232" stroke-width="1.4"/><circle cx="96" cy="100" r="2" fill="url(#gold)"/><path d="M96 102 l2 5 -3 1" stroke="#cfd6e2" stroke-width="1" fill="none"/>')
    if rod == "whole":
        stick = (f'<path d="M72 124 L{ROD_TIP[0]} {ROD_TIP[1]}" stroke="#1b1e25" stroke-width="2.8" stroke-linecap="round"/>'
                 f'<path d="M72 124 L{ROD_TIP[0]} {ROD_TIP[1]}" stroke="#7d8796" stroke-width=".7" opacity=".7"/>'
                 '<path d="M40 76 l1.5 -1 M28 60 l1.5 -1" stroke="url(#gold)" stroke-width="2.4"/>')
    else:
        stick = '<path d="M72 124 L44 82" stroke="#1b1e25" stroke-width="2.8" stroke-linecap="round"/><path d="M44 82 l-5 -2 m5 2 l-1 -6" stroke="#7d8796" stroke-width="1.4" stroke-linecap="round"/>'
    reel = '<circle cx="64" cy="114" r="5" fill="url(#gold)" stroke="#a7771f" stroke-width=".6"/><circle cx="64" cy="114" r="2" fill="#5a4210"/><path d="M64 114 l5 -3" stroke="#3a2e12" stroke-width="1.4" stroke-linecap="round"/>'
    arms = ('<path d="M60 100 Q52 106 54 104" stroke="#0f5b45" stroke-width="8" fill="none" stroke-linecap="round"/><path d="M100 100 Q90 120 66 114" stroke="#0f5b45" stroke-width="8" fill="none" stroke-linecap="round"/>'
            '<circle cx="54" cy="103" r="4.6" fill="url(#skin)"/><circle cx="66" cy="114" r="4.6" fill="url(#skin)"/>')
    return cooler, legs + shirt + vest, stick + reel, arms


def angler(state):
    cooler, body, rod, arms = angler_body("broken" if state == "snap" else "whole")
    if state == "money":
        stack = "".join(f'<rect x="{62 + i % 2 * 2}" y="{118 - i * 5}" width="36" height="7" rx="1.2" fill="url(#bill)" stroke="#2d6a40" stroke-width=".7"/>' for i in range(5))
        stack += '<rect x="76" y="96" width="8" height="30" fill="url(#gold)"/>'
        hug = ('<path d="M60 100 Q50 116 64 122" stroke="#0f5b45" stroke-width="8" fill="none" stroke-linecap="round"/><path d="M100 100 Q110 116 96 122" stroke="#0f5b45" stroke-width="8" fill="none" stroke-linecap="round"/>'
               '<circle cx="65" cy="121" r="4.6" fill="url(#skin)"/><circle cx="95" cy="121" r="4.6" fill="url(#skin)"/>')
        inner = cooler + body + stack + hug + angler_head("money")
        return art.bills_rain() + f'<g filter="url(#stk)"><g>{MOTIONS["hop"]}{inner}</g></g>' + coins() + art.burst(26, 30, "#f2c14e", "0s") + art.burst(136, 30, "#1fd29d", ".6s")
    if state == "snap":
        inner = cooler + f'<g transform="rotate(-16 80 130)">{body}{rod}{arms}{angler_head("snap")}</g>'
        return f'<g filter="url(#stk)"><g>{MOTIONS["shake"]}{inner}</g></g>' + tears() + rain_cloud()
    inner = cooler + body + rod + arms + angler_head(state)
    extra = (star(130, 66, 4, "#f2c14e") + star(124, 110, 3, "#fff1b8", begin=".6s")) if state == "win" else art.sweat()
    return f'<g filter="url(#stk)"><g>{MOTIONS["breathe"]}{inner}</g></g>{extra}'


# ======================= the hauler (SELL) =======================
LEAN, FEET = 14, (80, 156)
HAULER_HAND = rot((44, 84), LEAN, FEET)


def hauler_head(state):
    back = '<path d="M46 62 Q42 24 80 22 Q118 24 114 62 L110 80 L104 62 L56 62 L50 80Z" fill="url(#silverHair)"/>'
    spikes = ('<path d="M47 50 Q42 20 80 18 Q118 20 113 50 L108 40 L104 52 L97 34 L92 50 L84 30 L78 48 L70 32 L64 50 L57 36 L52 52Z" fill="url(#silverHair)"/>'
              '<path d="M84 18 l10 -11 l-2 13z M70 20 l-7 -10 l11 6z" fill="url(#silverHair)"/>')
    band = ('<path d="M47 44 Q80 34 113 44 L113 51 Q80 41 47 51Z" fill="url(#bandana)"/>'
            '<path d="M112 46 q10 -2 16 6 q-8 -2 -14 0z M112 49 q8 4 10 13 q-6 -6 -11 -9z" fill="url(#bandana)"/>'
            '<circle cx="62" cy="46" r="1" fill="#fff" opacity=".7"/><circle cx="78" cy="42.5" r="1" fill="#fff" opacity=".7"/><circle cx="96" cy="44" r="1" fill="#fff" opacity=".7"/>')
    face = [skin_face(), blush()]
    if state == "snap":
        face.append(eyes("cry", "irisR") + brows("cry") + MOUTHS["wail"])
    else:
        eye, mouth = {"win": ("angry", "teeth"), "lose": ("dart", "wavy"), "money": ("dollar", "money")}[state]
        face.append(eyes(eye, "irisR") + brows(eye) + MOUTHS[mouth])
    face.append('<path d="M98 80 l6 -5 M100 82 l1 -6" stroke="#c9787a" stroke-width="1.2" stroke-linecap="round"/>')  # a small scar
    return back + "".join(face) + spikes + band


def hauler_body(arms_kind):
    legs = ('<path d="M72 122 L60 154 M88 122 L102 154" stroke="url(#cargo)" stroke-width="10" stroke-linecap="round"/>'
            '<rect x="88" y="132" width="7" height="6" rx="1" fill="#3a4330" transform="rotate(-24 91 135)"/>'
            '<path d="M52 155 h14 v-6 h-10z M98 155 h14 l-4 -6 h-10z" fill="#111317"/>')
    belt = '<rect x="56" y="118" width="48" height="5" rx="1.5" fill="#3a2a1a"/><rect x="76" y="117" width="8" height="7" rx="1" fill="url(#gold)"/>'
    tank = ('<path d="M62 96 Q80 92 98 96 L104 120 Q80 125 56 120Z" fill="url(#tank)"/>'
            '<path d="M66 96 Q80 104 94 96" stroke="#e3243f" stroke-width="2" fill="none"/>'
            '<path d="M62 96 L58 100 M98 96 L102 100" stroke="#e3243f" stroke-width="2"/>')
    coil = ('<g fill="none" stroke="#c9a46a" stroke-width="1.8"><ellipse cx="100" cy="122" rx="8" ry="6"/><ellipse cx="101" cy="123" rx="6.5" ry="4.8"/>'
            '<ellipse cx="102" cy="124" rx="5" ry="3.6"/></g>')
    if arms_kind == "pull":
        arms = ('<path d="M61 100 Q50 94 45 86" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/>'
                '<path d="M99 100 Q72 102 52 92" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/>'
                '<path d="M86 101 q4 -4 8 -1" stroke="#e8b7a0" stroke-width="1.2" fill="none"/>'
                '<circle cx="44" cy="84" r="5.6" fill="url(#glove)"/><circle cx="51" cy="91" r="5.6" fill="url(#glove)"/>'
                '<path d="M44 84 L51 91 Q60 104 98 118" stroke="#c9a46a" stroke-width="1.8" fill="none"/>')
    elif arms_kind == "hug":
        arms = ('<path d="M61 100 Q50 116 64 122" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/><path d="M99 100 Q110 116 96 122" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/>'
                '<circle cx="65" cy="121" r="5" fill="url(#glove)"/><circle cx="95" cy="121" r="5" fill="url(#glove)"/>')
    else:  # fallen, rope slack in hand
        arms = ('<path d="M61 100 Q50 100 46 94" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/><path d="M99 100 Q112 92 108 76" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/>'
                '<circle cx="46" cy="93" r="5.4" fill="url(#glove)"/><circle cx="108" cy="73" r="5.4" fill="url(#glove)"/>'
                '<path d="M46 93 q-10 -4 -8 -14 q2 -8 -8 -12" stroke="#c9a46a" stroke-width="1.8" fill="none" stroke-linecap="round"/>')
    return legs + belt + tank + coil + arms


def hauler(state):
    if state == "money":
        stack = "".join(f'<rect x="{62 + i % 2 * 2}" y="{116 - i * 5}" width="36" height="7" rx="1.2" fill="url(#bill)" stroke="#2d6a40" stroke-width=".7"/>' for i in range(5))
        stack += '<rect x="76" y="94" width="8" height="30" fill="url(#gold)"/>'
        inner = hauler_body("none").split('<path d="M61 100')[0] + stack + hauler_body("hug")[hauler_body("hug").index('<path d="M61 100'):] + hauler_head("money")
        return art.bills_rain() + f'<g filter="url(#stk)"><g>{MOTIONS["hop"]}{inner}</g></g>' + coins() + art.burst(26, 30, "#f2c14e", "0s") + art.burst(136, 30, "#ff8fa6", ".6s")
    if state == "snap":
        inner = f'<g transform="rotate(-22 80 150) translate(0 6)">{hauler_body("fallen")}{hauler_head("snap")}</g>'
        return f'<g filter="url(#stk)"><g>{MOTIONS["shake"]}{inner}</g></g>' + tears() + rain_cloud()
    tug = '<animateTransform attributeName="transform" type="rotate" values="0 80 156; 3 80 156; 0 80 156" dur=".7s" repeatCount="indefinite"/>'
    inner = hauler_body("pull") + hauler_head(state)
    extra = art.sweat() if state == "lose" else star(134, 58, 4, "#f2c14e")
    dust = '<path d="M48 160 q-6 -4 -12 0 M114 160 q6 -4 12 0" stroke="#9aa3b2" stroke-width="1.4" fill="none" opacity=".6"/>'
    return f'{dust}<g filter="url(#stk)"><g transform="rotate({LEAN} {FEET[0]} {FEET[1]})"><g>{tug}{inner}</g></g></g>{extra}'


# ======================= pulling with more or less effort =======================
EFFORTS = ("easy", "effort", "strain", "brace")
HOT = """<linearGradient id="hotHair" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff2d3d"/><stop offset=".45" stop-color="#ff9a6b"/><stop offset="1" stop-color="#cdd3e6"/></linearGradient>
<linearGradient id="hotNavy" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff2d3d"/><stop offset=".5" stop-color="#7a3a7a"/><stop offset="1" stop-color="#151c33"/></linearGradient>"""
DEFS += HOT


def bez(b, c, t, k):
    return tuple(round((1 - k) ** 2 * b[i] + 2 * (1 - k) * k * c[i] + k ** 2 * t[i], 1) for i in range(2))


def red_face():
    return '<path d="M52 56 Q80 50 108 56 L108 92 Q80 98 52 92Z" fill="#ff2a45" opacity=".24"/>'


def aura(cx=80, cy=104, r=58):
    out = ['<ellipse cx="{0}" cy="{1}" rx="{2}" ry="{3}" fill="#ff4a2a" opacity=".12"><animate attributeName="opacity" values=".06;.2;.06" dur=".5s" repeatCount="indefinite"/></ellipse>'.format(cx, cy, r, r * .9)]
    for i in range(10):
        a = math.radians(i * 36 + 8)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r * .9
        x2, y2 = cx + math.cos(a) * (r + 10), cy + math.sin(a) * (r + 10) * .9
        out.append(f'<path d="M{x:.1f} {y:.1f} L{x2:.1f} {y2:.1f}" stroke="#ff7a3a" stroke-width="2.4" stroke-linecap="round">'
                   f'<animate attributeName="opacity" values="1;.1;1" dur=".4s" begin="{i * .04:.2f}s" repeatCount="indefinite"/></path>')
    return "".join(out)


# Arms twitching on the rod / the rope: slow at ease, quick and jerky when pulling hard.
TWITCH = {"easy": ("0 0; -.6 .4; 0 0", "2.2s"), "effort": ("0 0; -1.4 1; .6 -.4; 0 0", ".8s"),
          "strain": ("0 0; -2.2 1.6; .8 -.8; -1.6 1.2; 0 0", ".42s"), "brace": ("0 0; -2.8 2; 1.2 -1; -2.2 1.6; .6 -.4; 0 0", ".26s")}


def twitch(state, inner):
    values, dur = TWITCH[state]
    return f'<g><animateTransform attributeName="transform" type="translate" values="{values}" dur="{dur}" repeatCount="indefinite"/>{inner}</g>'


def note():
    return ('<text x="116" y="56" font-size="14" fill="#f2c14e" font-family="Georgia, serif">&#9834;'
            '<animateTransform attributeName="transform" type="translate" values="0 6; 8 -14" dur="2s" repeatCount="indefinite"/>'
            '<animate attributeName="opacity" values="0;1;0" dur="2s" repeatCount="indefinite"/></text>')


ANGLER = {"easy": dict(lean=-2, tip=(16, 42), bend=0), "effort": dict(lean=4, tip=(20, 52), bend=7),
          "strain": dict(lean=10, tip=(26, 64), bend=14), "brace": dict(lean=13, tip=(28, 70), bend=18)}
SEAT = (80, 130)


def angler_face(state):
    face = [skin_face(), blush()]
    if state == "brace":
        face.append(red_face())
    face.append('<path d="M55 59 h21 q1 10 -9 12 q-11 1 -12 -12z M84 59 h21 q-1 13 -12 12 q-10 -2 -9 -12z" fill="url(#lens)" stroke="url(#gold)" stroke-width="1.6"/>'
                '<path d="M76 61 q4 -3 8 0" stroke="url(#gold)" stroke-width="1.6" fill="none"/><path d="M55 60 l-5 -2 M105 60 l5 -2" stroke="url(#gold)" stroke-width="1.4"/>')
    if state == "easy":
        face.append('<path d="M60 60 l5 -3" stroke="#fff" stroke-width="1.6" stroke-linecap="round"><animate attributeName="opacity" values=".1;.9;.1" dur="2s" repeatCount="indefinite"/></path>')
        face.append(f'<path d="M57 53 Q65 50 73 53 M103 53 Q95 50 87 53" stroke="{INK}" stroke-width="1.8" fill="none" stroke-linecap="round"/>' + MOUTHS["smile"])
    elif state == "effort":
        face.append(f'<path d="M57 52 L73 55 M103 52 L87 55" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>' + MOUTHS["smile"].replace("Q80 87", "Q80 85"))
    else:
        face.append(f'<path d="M55 50 L73 56 M105 50 L87 56" stroke="{INK}" stroke-width="2.6" stroke-linecap="round"/>' + MOUTHS["teeth"])
    return "".join(face)


def angler_hair_hat(state):
    back = '<path d="M48 64 Q46 32 80 30 Q114 32 112 64 L110 78 L104 64 L56 64 L50 78Z" fill="url(#navyHair)"/>'
    hat = ('<path d="M53 42 Q55 15 80 14 Q105 15 107 42Z" fill="url(#olive)"/><rect x="54" y="33" width="52" height="5" fill="url(#gold)"/>'
           '<ellipse cx="80" cy="43" rx="40" ry="8.5" fill="url(#olive)" stroke="#3e4720" stroke-width=".8"/>'
           '<path d="M104 28 l6 -4 M104 28 l7 1 M104 28 l5 4" stroke="#ff8a3d" stroke-width="1.6" stroke-linecap="round"/><circle cx="104" cy="28" r="1.8" fill="url(#gold)"/>')
    if state != "brace":
        bangs = '<path d="M53 44 L57 55 L61 45 L66 57 L71 45 L77 55 L83 45 L89 56 L95 45 L100 55 L106 44Z" fill="url(#navyHair)"/>'
        return back, bangs + hat
    # Powering up: the hat blows off, the hair stands up glowing red.
    spikes = ('<path d="M47 52 Q42 22 80 20 Q118 22 113 52 L108 30 L103 50 L97 14 L91 46 L84 6 L78 44 L70 10 L64 48 L57 18 L52 50Z" fill="url(#hotNavy)"/>')
    flying = f'<g transform="translate(-10 -30) rotate(-22 80 30)">{hat}</g>'
    return back, spikes + flying


def angler_pull(state):
    cfg = ANGLER[state]
    cooler, body, _, _ = angler_body("whole")
    b, t = (72, 124), cfg["tip"]
    m = ((b[0] + t[0]) / 2, (b[1] + t[1]) / 2)
    c = (m[0] - cfg["bend"] * .4, m[1] - cfg["bend"])
    rod = (f'<path d="M{b[0]} {b[1]} Q{c[0]:.1f} {c[1]:.1f} {t[0]} {t[1]}" stroke="#1b1e25" stroke-width="2.8" fill="none" stroke-linecap="round"/>'
           f'<path d="M{b[0]} {b[1]} Q{c[0]:.1f} {c[1]:.1f} {t[0]} {t[1]}" stroke="#7d8796" stroke-width=".7" fill="none" opacity=".7"/>')
    for k in (.45, .7):
        x, y = bez(b, c, t, k)
        rod += f'<circle cx="{x}" cy="{y}" r="1.6" fill="url(#gold)"/>'
    reel_at = bez(b, c, t, .14)
    rod += (f'<circle cx="{reel_at[0]}" cy="{reel_at[1]}" r="5" fill="url(#gold)" stroke="#a7771f" stroke-width=".6"/><circle cx="{reel_at[0]}" cy="{reel_at[1]}" r="2" fill="#5a4210"/>'
            f'<path d="M{reel_at[0]} {reel_at[1]} l5 -3" stroke="#3a2e12" stroke-width="1.4" stroke-linecap="round"/>')
    near, far = bez(b, c, t, .2), bez(b, c, t, .42)
    arm = lambda sx, hx, hy: f'<path d="M{sx} 100 Q{(sx + hx) / 2} {max(hy, 100) + 6} {hx} {hy}" stroke="#0f5b45" stroke-width="8" fill="none" stroke-linecap="round"/><circle cx="{hx}" cy="{hy}" r="4.8" fill="url(#skin)"/>'
    if state == "easy":
        arms = arm(100, near[0], near[1]) + '<path d="M60 100 Q54 116 62 124" stroke="#0f5b45" stroke-width="8" fill="none" stroke-linecap="round"/><circle cx="63" cy="124" r="4.8" fill="url(#skin)"/>'
    else:
        arms = arm(60, far[0], far[1]) + arm(100, near[0], near[1])
    back, front = angler_hair_hat(state)
    person = body + twitch(state, rod + arms) + back + angler_face(state) + front
    if state in ("strain", "brace"):
        person += art.vein()
    motion = {"easy": MOTIONS["breathe"],
              "effort": '<animateTransform attributeName="transform" type="rotate" values="0 80 130; 1.5 80 130; 0 80 130" dur=".9s" repeatCount="indefinite"/>',
              "strain": MOTIONS["tremble"], "brace": MOTIONS["tremble"]}[state]
    inner = cooler + f'<g transform="rotate({cfg["lean"]} {SEAT[0]} {SEAT[1]})"><g>{motion}{person}</g></g>'
    extra = {"easy": note(), "effort": "", "strain": art.sweat(), "brace": art.steam_puffs()}[state]
    under = aura(80, 100, 56) if state == "brace" else ""
    return f'{under}<g filter="url(#stk)">{inner}</g>{extra}'


HAULER = {"easy": dict(lean=5, hand=(54, 94)), "effort": dict(lean=11, hand=(46, 86)),
          "strain": dict(lean=18, hand=(42, 82)), "brace": dict(lean=22, hand=(42, 82))}


def hauler_face(state):
    face = [skin_face(), blush()]
    if state == "brace":
        face.append(red_face())
    if state == "easy":
        face.append(eyes("blink", "irisR") + brows("normal") + MOUTHS["smile"])
    elif state == "effort":
        face.append(eyes("normal", "irisR") + f'<path d="M57 48 L72 52 M103 48 L88 52" stroke="{INK}" stroke-width="2.2" stroke-linecap="round"/>' + MOUTHS["smile"])
    else:
        face.append(eyes("angry", "irisR") + brows("angry") + MOUTHS["teeth"])
    face.append('<path d="M98 80 l6 -5 M100 82 l1 -6" stroke="#c9787a" stroke-width="1.2" stroke-linecap="round"/>')
    return "".join(face)


def hauler_pull(state):
    cfg = HAULER[state]
    hx, hy = cfg["hand"]
    back = '<path d="M46 62 Q42 24 80 22 Q118 24 114 62 L110 80 L104 62 L56 62 L50 80Z" fill="url(#silverHair)"/>'
    hair = "url(#hotHair)" if state == "brace" else "url(#silverHair)"
    spikes = (f'<path d="M47 50 Q42 20 80 18 Q118 20 113 50 L108 40 L104 52 L97 34 L92 50 L84 30 L78 48 L70 32 L64 50 L57 36 L52 52Z" fill="{hair}"/>'
              f'<path d="M84 18 l10 -11 l-2 13z M70 20 l-7 -10 l11 6z" fill="{hair}"/>')
    if state == "brace":
        spikes += '<path d="M58 30 L52 4 L68 26 M78 24 L80 -2 L90 22 M98 28 L110 6 L104 32" fill="url(#hotHair)"/>'
    band = ('<path d="M47 44 Q80 34 113 44 L113 51 Q80 41 47 51Z" fill="url(#bandana)"/>'
            '<path d="M112 46 q10 -2 16 6 q-8 -2 -14 0z M112 49 q8 4 10 13 q-6 -6 -11 -9z" fill="url(#bandana)"/>')
    body = hauler_body("none").split('<path d="M61 100')[0]
    if state == "easy":
        arms = (f'<path d="M99 100 Q76 104 {hx + 2} {hy + 2}" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/><circle cx="{hx}" cy="{hy}" r="5.6" fill="url(#glove)"/>'
                '<path d="M61 100 Q52 112 62 118" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/><circle cx="63" cy="118" r="5.2" fill="url(#glove)"/>')
    else:
        hx2, hy2 = hx + 7, hy + 7
        arms = (f'<path d="M61 100 Q50 94 {hx + 1} {hy + 2}" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/>'
                f'<path d="M99 100 Q72 102 {hx2 + 1} {hy2 + 1}" stroke="url(#skin)" stroke-width="8" fill="none" stroke-linecap="round"/>'
                f'<circle cx="{hx}" cy="{hy}" r="5.6" fill="url(#glove)"/><circle cx="{hx2}" cy="{hy2}" r="5.6" fill="url(#glove)"/>')
    arms += f'<path d="M{hx} {hy} Q70 106 98 118" stroke="#c9a46a" stroke-width="1.3" fill="none"/>'
    person = body + twitch(state, arms) + back + hauler_face(state) + spikes + band
    if state in ("strain", "brace"):
        person += art.vein()
    motion = {"easy": '<animateTransform attributeName="transform" type="rotate" values="0 80 156; 1.2 80 156; 0 80 156" dur="2.4s" repeatCount="indefinite"/>',
              "effort": '<animateTransform attributeName="transform" type="rotate" values="0 80 156; 3 80 156; 0 80 156" dur=".9s" repeatCount="indefinite"/>',
              "strain": '<animateTransform attributeName="transform" type="rotate" values="0 80 156; 3 80 156; 0 80 156" dur=".45s" repeatCount="indefinite"/>',
              "brace": MOTIONS["tremble"]}[state]
    dust = '<path d="M48 160 q-6 -4 -12 0 M114 160 q6 -4 12 0" stroke="#9aa3b2" stroke-width="1.4" fill="none" opacity=".6"/>' if state != "easy" else ""
    under = aura(80, 104, 58) if state == "brace" else ""
    extra = {"easy": note(), "effort": "", "strain": art.sweat(), "brace": art.steam_puffs()}[state]
    return f'{under}{dust}<g filter="url(#stk)"><g transform="rotate({cfg["lean"]} {FEET[0]} {FEET[1]})"><g>{motion}{person}</g></g></g>{extra}'


PICTURES = {}
for st in EFFORTS:
    PICTURES[f"angler-{st}"] = angler_pull(st)
    PICTURES[f"hauler-{st}"] = hauler_pull(st)
PICTURES.update({"angler-money": angler("money"), "angler-snap": angler("snap"), "hauler-money": hauler("money"), "hauler-snap": hauler("snap")})

# Where the line starts in each picture (picture coordinates; the feet stand at y 156).
POINTS = {"angler": {st: rot(ANGLER[st]["tip"], ANGLER[st]["lean"], SEAT) for st in EFFORTS},
          "hauler": {st: rot(HAULER[st]["hand"], HAULER[st]["lean"], FEET) for st in EFFORTS}}
