"""Trade characters drawn as silhouettes with a golden rim light: a kneeling angler (BUY) whose line hooks the
price, and a hauler (SELL) with the rope over his shoulder.

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
<linearGradient id="shade" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2a3142"/><stop offset=".55" stop-color="#11151e"/><stop offset="1" stop-color="#040508"/></linearGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff1b8"/><stop offset=".45" stop-color="#eebd4a"/><stop offset="1" stop-color="#a7771f"/></linearGradient>
<filter id="rim" x="-25%" y="-25%" width="150%" height="150%">
  <feMorphology in="SourceAlpha" operator="dilate" radius="1.3" result="d"/>
  <feFlood flood-color="#f2c14e"/><feComposite in2="d" operator="in" result="edge"/>
  <feGaussianBlur in="edge" stdDeviation="2.6" result="glow"/>
  <feMerge><feMergeNode in="glow"/><feMergeNode in="edge"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
<filter id="rimHot" x="-25%" y="-25%" width="150%" height="150%">
  <feMorphology in="SourceAlpha" operator="dilate" radius="1.6" result="d"/>
  <feFlood flood-color="#ff4a2a"/><feComposite in2="d" operator="in" result="edge"/>
  <feGaussianBlur in="edge" stdDeviation="3.4" result="glow"/>
  <feMerge><feMergeNode in="glow"/><feMergeNode in="glow"/><feMergeNode in="edge"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
"""
INK = 'fill="url(#shade)"'
LIMB = 'stroke="url(#shade)" stroke-linecap="round" stroke-linejoin="round" fill="none"'


def rot(p, a, c):
    r = math.radians(a)
    dx, dy = p[0] - c[0], p[1] - c[1]
    return (round(c[0] + dx * math.cos(r) - dy * math.sin(r), 1), round(c[1] + dx * math.sin(r) + dy * math.cos(r), 1))


def bez(b, c, t, k):
    return tuple(round((1 - k) ** 2 * b[i] + 2 * (1 - k) * k * c[i] + k ** 2 * t[i], 1) for i in range(2))


def grass(x0, x1, y):
    return "".join(f'<path d="M{x} {y} q{(-1) ** i * 2} -7 {(-1) ** i * 4} -10" stroke="url(#shade)" stroke-width="1.4" fill="none"/>' for i, x in enumerate(range(x0, x1, 5)))


def effects(state):
    if state == "easy":
        return ('<text x="20" y="40" font-size="15" fill="#f2c14e" font-family="Georgia, serif">&#9834;'
                '<animateTransform attributeName="transform" type="translate" values="0 6; -8 -14" dur="2s" repeatCount="indefinite"/>'
                '<animate attributeName="opacity" values="0;1;0" dur="2s" repeatCount="indefinite"/></text>')
    if state == "strain":
        return art.sweat()
    if state == "brace":
        return art.steam_puffs()
    return ""


TWITCH = {"easy": ("0 0; -.6 .4; 0 0", "2.2s"), "effort": ("0 0; -1.4 1; .6 -.4; 0 0", ".8s"),
          "strain": ("0 0; -2.2 1.6; .8 -.8; -1.6 1.2; 0 0", ".42s"), "brace": ("0 0; -2.8 2; 1.2 -1; -2.2 1.6; .6 -.4; 0 0", ".26s")}
SWAY = {"easy": ("0", "0"), "effort": ("1.2", ".9s"), "strain": ("2", ".45s"), "brace": ("2.4", ".22s")}


def twitch(state, inner):
    values, dur = TWITCH[state]
    return f'<g><animateTransform attributeName="transform" type="translate" values="{values}" dur="{dur}" repeatCount="indefinite"/>{inner}</g>'


# ======================= the angler: kneeling, facing the chart (left) =======================
KNEE = (92, 146)
ANGLER = {"easy": dict(lean=-3, tip=(12, 28), bend=0), "effort": dict(lean=4, tip=(16, 36), bend=8),
          "strain": dict(lean=10, tip=(22, 48), bend=16), "brace": dict(lean=14, tip=(26, 56), bend=20)}


def rock():
    return (f'<path d="M34 150 Q36 143 48 143 H134 Q143 143 145 150 V157 H34Z" {INK}/>' + grass(36, 70, 144) + grass(118, 144, 144))


def angler_figure(tip, bend, arms_up=False, rod=True, broken=False):
    b = (88, 116)
    t = tip
    m = ((b[0] + t[0]) / 2, (b[1] + t[1]) / 2)
    c = (m[0] - bend * .4, m[1] - bend)
    legs = (f'<path d="M98 118 L104 142 L132 146" stroke-width="12" {LIMB}/><path d="M132 146 l8 1 q2 -5 -4 -6z" {INK}/>'
            f'<path d="M90 118 L66 114 L66 145" stroke-width="12" {LIMB}/><path d="M58 147 h16 q1 -6 -8 -6 q-8 0 -8 6z" {INK}/>')
    torso = (f'<path d="M82 124 Q78 100 74 80 Q84 66 100 70 Q108 96 106 122 Z" {INK}/>'
             f'<rect x="98" y="76" width="22" height="34" rx="6" transform="rotate(-10 109 93)" {INK}/>'
             '<path d="M100 80 q-6 14 -4 30" stroke="#2a3142" stroke-width="1.4" fill="none"/>')
    head = (f'<path d="M78 72 l4 -6" stroke-width="7" {LIMB}/><circle cx="78" cy="58" r="10.5" {INK}/>'
            f'<path d="M67 56 Q68 42 80 42 Q91 43 90 56Z" {INK}/><path d="M69 53 L52 57 Q58 50 69 49Z" {INK}/>')
    stick = ""
    if rod:
        if broken:
            stick = f'<path d="M{b[0]} {b[1]} L54 70" stroke="#0b0d12" stroke-width="2.6" stroke-linecap="round"/><path d="M54 70 l-6 -2 m6 2 l-1 -7" stroke="#0b0d12" stroke-width="1.6" stroke-linecap="round"/>'
        else:
            stick = (f'<path d="M{b[0]} {b[1]} Q{c[0]:.1f} {c[1]:.1f} {t[0]} {t[1]}" stroke="#0b0d12" stroke-width="2.6" fill="none" stroke-linecap="round"/>'
                     + "".join(f'<circle cx="{x}" cy="{y}" r="1.5" {INK}/>' for x, y in (bez(b, c, t, .5), bez(b, c, t, .72))))
            r = bez(b, c, t, .18)
            stick += f'<circle cx="{r[0]}" cy="{r[1] + 4}" r="4.4" {INK}/><path d="M{r[0]} {r[1] + 4} l-5 3" stroke="#0b0d12" stroke-width="1.6" stroke-linecap="round"/>'
    if arms_up:
        arms = f'<path d="M86 78 L70 60 L62 40" stroke-width="7.5" {LIMB}/><path d="M94 80 L86 98 L76 104" stroke-width="7.5" {LIMB}/>'
    elif rod and not broken:
        h1, h2 = bez(b, c, t, .3), bez(b, c, t, .5)
        arms = (f'<path d="M86 78 Q78 96 {h1[0]} {h1[1]}" stroke-width="7.5" {LIMB}/><circle cx="{h1[0]}" cy="{h1[1]}" r="4" {INK}/>'
                f'<path d="M80 80 Q66 82 {h2[0]} {h2[1]}" stroke-width="7.5" {LIMB}/><circle cx="{h2[0]}" cy="{h2[1]}" r="4" {INK}/>')
    else:
        arms = f'<path d="M86 78 Q70 88 56 70" stroke-width="7.5" {LIMB}/><path d="M80 80 Q92 66 104 54" stroke-width="7.5" {LIMB}/>'
    return legs, torso, head, stick, arms


def angler(state):
    if state in ANGLER:
        cfg = ANGLER[state]
        legs, torso, head, stick, arms = angler_figure(cfg["tip"], cfg["bend"])
        amp, dur = SWAY[state]
        sway = (f'<animateTransform attributeName="transform" type="rotate" values="0 {KNEE[0]} {KNEE[1]}; {amp} {KNEE[0]} {KNEE[1]}; 0 {KNEE[0]} {KNEE[1]}" dur="{dur}" repeatCount="indefinite"/>'
                if state != "easy" else art.MOTIONS["breathe"])
        body = f'<g transform="rotate({cfg["lean"]} {KNEE[0]} {KNEE[1]})"><g>{sway}{legs}{torso}{twitch(state, stick + arms)}{head}</g></g>'
        rim = "rimHot" if state == "brace" else "rim"
        under = aura(84, 100, 54) if state == "brace" else ""
        return f'{under}<g filter="url(#{rim})">{rock()}{body}</g>{effects(state)}'
    if state == "money":
        legs, torso, head, _, arms = angler_figure((12, 28), 0, arms_up=True, rod=False)
        bag = ('<path d="M52 40 q-12 2 -12 -14 q0 -12 14 -14 q14 2 14 14 q0 16 -16 14z" fill="url(#gold)" stroke="#a7771f"/>'
               '<path d="M48 12 q6 -6 12 0" stroke="#a7771f" stroke-width="2" fill="none"/><text x="54" y="32" text-anchor="middle" font-size="13" font-weight="900" fill="#7d5714" font-family="Georgia, serif">$</text>')
        hop = art.MOTIONS["hop"]
        return (art.bills_rain() + f'<g filter="url(#rim)">{rock()}<g>{hop}{legs}{torso}{arms}{head}</g></g><g>{hop}{bag}</g>'
                + coins() + art.burst(28, 30, "#f2c14e", "0s") + art.burst(138, 34, "#1fd29d", ".6s"))
    # snap: knocked back off the rock, the rod broken
    legs, torso, head, stick, arms = angler_figure((12, 28), 0, rod=True, broken=True)
    body = f'<g transform="rotate(32 100 146)"><g>{art.MOTIONS["shake"]}{legs}{torso}{stick}{arms}{head}</g></g>'
    return f'<g filter="url(#rim)">{rock()}{body}</g>' + '<text x="42" y="40" font-size="26" font-weight="900" fill="#ff5a70" font-family="Georgia, serif">!</text>' + art.rain_cloud()


# ======================= the hauler: rope over the shoulder, walking away from the chart (right) =======================
FEET = (80, 154)
HAULER = {"easy": 4, "effort": 12, "strain": 20, "brace": 26}
SHOULDER = (90, 72)


def hauler_figure(arms="rope", rope=True):
    legs = (f'<path d="M76 112 L62 132 L46 150" stroke-width="12" {LIMB}/><path d="M38 152 h14 l2 -6 q-10 -2 -14 2z" {INK}/>'
            f'<path d="M84 112 L100 128 L102 150" stroke-width="12" {LIMB}/><path d="M96 152 h16 q1 -6 -9 -6 q-7 0 -7 6z" {INK}/>')
    torso = f'<path d="M70 118 Q72 94 84 72 Q98 64 106 74 Q98 98 92 120 Z" {INK}/>'
    head = (f'<path d="M100 72 l5 -6" stroke-width="7" {LIMB}/><circle cx="108" cy="58" r="10.5" {INK}/>'
            f'<path d="M97 56 Q97 42 108 42 Q120 42 120 54 Q109 51 97 56Z" {INK}/><circle cx="109" cy="41" r="2.6" {INK}/>')
    if arms == "rope":
        rope_body = (f'<path d="M{SHOULDER[0]} {SHOULDER[1]} Q100 70 104 80 L110 90 Q114 100 116 120" stroke="#c9a46a" stroke-width="1.6" fill="none"/>'
                     if rope else "")
        arm = (f'<path d="M100 76 Q108 84 110 90" stroke-width="7.5" {LIMB}/><circle cx="111" cy="91" r="4.2" {INK}/>'
               f'<path d="M94 78 Q100 88 106 84" stroke-width="7.5" {LIMB}/><circle cx="106" cy="83" r="4.2" {INK}/>')
        return legs, torso, head, arm, rope_body
    if arms == "money":
        arm = (f'<path d="M100 76 L114 58 L118 40" stroke-width="7.5" {LIMB}/><circle cx="118" cy="38" r="4.2" {INK}/>'
               f'<path d="M94 78 Q86 74 84 62" stroke-width="7.5" {LIMB}/>')
        return legs, torso, head, arm, ""
    arm = f'<path d="M100 76 Q112 70 122 62" stroke-width="7.5" {LIMB}/><path d="M94 78 Q82 90 74 84" stroke-width="7.5" {LIMB}/>'
    return legs, torso, head, arm, '<path d="M74 84 q-8 -6 -6 -16 q2 -8 -8 -12" stroke="#c9a46a" stroke-width="1.6" fill="none"/>'


def hauler(state):
    if state in HAULER:
        lean = HAULER[state]
        legs, torso, head, arm, rope = hauler_figure()
        amp, dur = SWAY[state]
        sway = (f'<animateTransform attributeName="transform" type="rotate" values="0 {FEET[0]} {FEET[1]}; {amp} {FEET[0]} {FEET[1]}; 0 {FEET[0]} {FEET[1]}" dur="{dur}" repeatCount="indefinite"/>'
                if state != "easy" else art.MOTIONS["breathe"])
        body = f'<g transform="rotate({lean} {FEET[0]} {FEET[1]})"><g>{sway}{legs}{torso}{rope}{twitch(state, arm)}{head}</g></g>'
        rim = "rimHot" if state == "brace" else "rim"
        dust = ('<path d="M34 160 q-6 -4 -12 0 M44 162 q-4 -6 -10 -4" stroke="#9aa3b2" stroke-width="1.4" fill="none" opacity=".6"/>' if state != "easy" else "")
        under = aura(82, 104, 56) if state == "brace" else ""
        return f'{under}{dust}<g filter="url(#{rim})">{body}</g>{effects(state)}'
    if state == "money":
        legs, torso, head, arm, _ = hauler_figure("money")
        bag = ('<path d="M118 36 q-14 2 -14 -14 q0 -12 14 -14 q14 2 14 14 q0 16 -14 14z" fill="url(#gold)" stroke="#a7771f"/>'
               '<text x="118" y="28" text-anchor="middle" font-size="13" font-weight="900" fill="#7d5714" font-family="Georgia, serif">$</text>')
        hop = art.MOTIONS["hop"]
        return (art.bills_rain() + f'<g filter="url(#rim)"><g>{hop}{legs}{torso}{arm}{head}</g></g><g>{hop}{bag}</g>'
                + coins() + art.burst(28, 30, "#f2c14e", "0s") + art.burst(138, 34, "#ff8fa6", ".6s"))
    legs, torso, head, arm, rope = hauler_figure("fallen")
    body = f'<g transform="rotate(-58 80 154) translate(-6 8)"><g>{art.MOTIONS["shake"]}{legs}{torso}{arm}{rope}{head}</g></g>'
    return f'<g filter="url(#rim)">{body}</g>' + '<text x="118" y="60" font-size="26" font-weight="900" fill="#ff5a70" font-family="Georgia, serif">!</text>' + art.rain_cloud()


EFFORTS = ("easy", "effort", "strain", "brace")
PICTURES = {}
for st in EFFORTS + ("money", "snap"):
    PICTURES[f"angler-{st}"] = angler(st)
    PICTURES[f"hauler-{st}"] = hauler(st)

POINTS = {"angler": {st: rot(ANGLER[st]["tip"], ANGLER[st]["lean"], KNEE) for st in EFFORTS},
          "hauler": {st: rot(SHOULDER, HAULER[st], FEET) for st in EFFORTS}}
