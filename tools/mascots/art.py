"""The chart mascots: a buyer (girl) and a seller (boy) in nine animated moods, drawn as SVG.

Run build.py to write the files the web and the app use."""

SKIN_DEFS = """
<linearGradient id="skin" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff3ea"/><stop offset="1" stop-color="#ffd6c2"/></linearGradient>
<linearGradient id="hairGold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff0b0"/><stop offset=".35" stop-color="#f4c55a"/><stop offset="1" stop-color="#b9792a"/></linearGradient>
<linearGradient id="hairSilver" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset=".4" stop-color="#cdd3e6"/><stop offset="1" stop-color="#6d7391"/></linearGradient>
<linearGradient id="irisG" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#063d2e"/><stop offset=".55" stop-color="#11a77b"/><stop offset="1" stop-color="#8ff7d6"/></linearGradient>
<linearGradient id="irisR" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a0712"/><stop offset=".55" stop-color="#d42a40"/><stop offset="1" stop-color="#ffb0bb"/></linearGradient>
<linearGradient id="jackG" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1fd29d"/><stop offset=".5" stop-color="#0d8a65"/><stop offset="1" stop-color="#064d39"/></linearGradient>
<linearGradient id="jackR" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff5a6e"/><stop offset=".5" stop-color="#b8172e"/><stop offset="1" stop-color="#5e0815"/></linearGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff1b8"/><stop offset=".45" stop-color="#eebd4a"/><stop offset="1" stop-color="#a7771f"/></linearGradient>
<linearGradient id="tear" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e6f6ff" stop-opacity=".95"/><stop offset="1" stop-color="#6cc4ff" stop-opacity=".85"/></linearGradient>
<linearGradient id="cloud" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9aa3b8"/><stop offset="1" stop-color="#4b5266"/></linearGradient>
<filter id="stk" x="-20%" y="-20%" width="140%" height="140%">
  <feMorphology in="SourceAlpha" operator="dilate" radius="3" result="d"/>
  <feFlood flood-color="#e9bf5c"/><feComposite in2="d" operator="in" result="gold"/>
  <feMorphology in="SourceAlpha" operator="dilate" radius="1.6" result="d2"/>
  <feFlood flood-color="#fffaf0"/><feComposite in2="d2" operator="in" result="cream"/>
  <feGaussianBlur in="d" stdDeviation="3" result="b"/><feOffset in="b" dy="3" result="bo"/>
  <feFlood flood-color="#000" flood-opacity=".7"/><feComposite in2="bo" operator="in" result="sh"/>
  <feMerge><feMergeNode in="sh"/><feMergeNode in="gold"/><feMergeNode in="cream"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>
"""

INK = "#2a1630"


def star(x, y, r, fill="#fff", anim=True, dur="1.2s", begin="0s"):
    p = f'<path d="M{x} {y - r}Q{x + r * .18} {y - r * .18} {x + r} {y}Q{x + r * .18} {y + r * .18} {x} {y + r}Q{x - r * .18} {y + r * .18} {x - r} {y}Q{x - r * .18} {y - r * .18} {x} {y - r}z" fill="{fill}">'
    if anim:
        p += f'<animate attributeName="opacity" values="1;.2;1" dur="{dur}" begin="{begin}" repeatCount="indefinite"/>'
    return p + '</path>'


def eyes(state, iris):
    out = []
    for cx, side in ((66, -1), (94, 1)):
        if state == "cry":
            # squeezed shut: ">" and "<" pointing to the nose, a lash at the outer end
            tip, out_x = cx + side * -1 * -7 if False else cx - side * 7, cx + side * 8
            tip = cx - side * 6 if side < 0 else cx - side * 6
            tip = cx + 6 if side < 0 else cx - 6
            out.append(f'<path d="M{out_x - side * 16 if False else (cx - 8 if side < 0 else cx + 8)} 58 L{tip} 64.5 L{cx - 8 if side < 0 else cx + 8} 71" stroke="{INK}" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
            continue
        out.append(f'<ellipse cx="{cx}" cy="65" rx="8.6" ry="10.2" fill="#fff"/>')
        out.append(f'<ellipse cx="{cx}" cy="66" rx="7" ry="9" fill="url(#{iris})"/>')
        out.append(f'<ellipse cx="{cx}" cy="67.5" rx="3.2" ry="4.4" fill="#0b1712" opacity=".85"/>')
        if state == "happy":
            out.append(star(cx - 2.4, 62.5, 3.6, "#fff"))
            out.append(star(cx + 2.8, 70, 1.8, "#fff4c4", begin=".4s"))
        else:
            out.append(f'<ellipse cx="{cx - 2.6}" cy="62" rx="2.6" ry="3.2" fill="#fff"/><circle cx="{cx + 2.8}" cy="70.5" r="1.3" fill="#fff"/>')
        out.append(f'<path d="M{cx - 9.5} 60 Q{cx} 51 {cx + 9.5} 59.5" stroke="{INK}" stroke-width="2.8" fill="none" stroke-linecap="round"/>')
        out.append(f'<path d="M{cx + side * 9.5} {59.5 if side > 0 else 60} l{side * 3.2} -2.6" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>')
    return "".join(out)


def face(state, iris):
    f = ['<path d="M50 58 Q50 92 80 95 Q110 92 110 58 Q110 31 80 31 Q50 31 50 58Z" fill="url(#skin)"/>']
    f.append(eyes(state, iris))
    # brows
    if state == "cry":
        f.append(f'<path d="M58 49 Q64 46 72 50 M102 49 Q96 46 88 50" stroke="{INK}" stroke-width="2" fill="none" stroke-linecap="round" transform="rotate(0)"/>')
        f.append('<path d="M60 40v7M66 39v8M72 40v6M88 40v6M94 39v8M100 40v7" stroke="#7a6cc2" stroke-width="1.4" opacity=".55"/>')
    else:
        f.append(f'<path d="M58 48 Q64 45 72 47 M102 48 Q96 45 88 47" stroke="{INK}" stroke-width="1.8" fill="none" stroke-linecap="round"/>')
    # blush with anime hatching
    for bx in (60, 100):
        f.append(f'<ellipse cx="{bx}" cy="77" rx="6" ry="3.2" fill="#ff8fa6" opacity=".55"/><path d="M{bx - 3} 79l2-4M{bx} 79l2-4M{bx + 3} 79l2-4" stroke="#ff6d8d" stroke-width="1" opacity=".7"/>')
    # mouth
    if state == "happy":
        f.append('<path d="M70 79 Q80 94 90 79 Z" fill="#9b1d3a"/><path d="M73 86 Q80 91 87 86 Q80 83 73 86Z" fill="#ff8fa6"/><path d="M71 79.5 h18" stroke="#fff" stroke-width="2"/>')
    else:
        f.append('<path d="M67 91 Q68 77 80 77 Q92 77 93 91 Q80 87 67 91Z" fill="#7d1430"/><path d="M70 81 Q80 76.5 90 81" stroke="#fff" stroke-width="2.4" fill="none"/>'
                 '<path d="M72 89.5 Q80 85 88 89.5 Q80 88 72 89.5Z" fill="#ff8fa6"/>'
                 '<path d="M67 91 Q66 93 64.5 92 M93 91 Q94 93 95.5 92" stroke="#7d1430" stroke-width="1.4" fill="none" stroke-linecap="round"/>')
        f.append('<path d="M76 98 q4 6 8 0" stroke="#ff8fa6" stroke-width="0" fill="none"/>')
    return "".join(f)


def tears():
    out = []
    for x, s in ((57, -1), (103, 1)):
        # streams down the cheeks
        out.append(f'<path d="M{x} 66 Q{x + s * 7} 86 {x + s * 5} 112" stroke="url(#tear)" stroke-width="6.5" fill="none" stroke-linecap="round" stroke-dasharray="6 5">'
                   f'<animate attributeName="stroke-dashoffset" from="22" to="0" dur=".55s" repeatCount="indefinite"/></path>')
        # drops spraying out
        for i, (dx, dy, dur) in enumerate(((s * 10, 6, ".8s"), (s * 16, 0, "1s"), (s * 8, 14, ".9s"))):
            out.append(f'<path d="M{x} 64 q2.4 4 0 6.4 q-2.4 -2.4 0 -6.4z" fill="url(#tear)">'
                       f'<animateTransform attributeName="transform" type="translate" values="0 0; {dx} {dy + 6}; {dx * 1.4} {dy + 28}" dur="{dur}" begin="{i * .25}s" repeatCount="indefinite"/>'
                       f'<animate attributeName="opacity" values="1;1;0" dur="{dur}" begin="{i * .25}s" repeatCount="indefinite"/></path>')
    return "".join(out)


def hair(kind, front):
    if kind == "girl":
        if not front:
            return ('<g><animateTransform attributeName="transform" type="rotate" values="0 46 46; 8 46 46; 0 46 46" dur=".6s" repeatCount="indefinite" class="swing"/>'
                    '<path d="M46 44 C26 52 18 80 26 112 C30 124 22 132 14 134 C30 136 38 122 36 106 C34 86 40 66 52 56Z" fill="url(#hairGold)"/></g>'
                    '<g><animateTransform attributeName="transform" type="rotate" values="0 114 46; -8 114 46; 0 114 46" dur=".6s" repeatCount="indefinite"/>'
                    '<path d="M114 44 C134 52 142 80 134 112 C130 124 138 132 146 134 C130 136 122 122 124 106 C126 86 120 66 108 56Z" fill="url(#hairGold)"/></g>'
                    '<path d="M44 60 Q42 22 80 20 Q118 22 116 60 L116 92 Q108 80 108 64 L52 64 Q52 80 44 92Z" fill="url(#hairGold)"/>')
        return ('<path d="M47 60 Q44 24 80 22 Q116 24 113 60 L107 46 L102 62 L95 40 L88 58 L80 38 L72 58 L65 40 L58 62 L53 46Z" fill="url(#hairGold)"/>'
                '<path d="M60 32 Q80 24 100 32" stroke="#fff8d8" stroke-width="3" fill="none" opacity=".7" stroke-linecap="round"/>'
                # ribbons
                '<path d="M44 42 l-10 -8 l2 12z M44 42 l-6 10 l10 -2z" fill="url(#jackG)" stroke="url(#gold)" stroke-width="1"/><circle cx="44" cy="43" r="3" fill="url(#gold)"/>'
                '<path d="M116 42 l10 -8 l-2 12z M116 42 l6 10 l-10 -2z" fill="url(#jackG)" stroke="url(#gold)" stroke-width="1"/><circle cx="116" cy="43" r="3" fill="url(#gold)"/>')
    if not front:
        return '<path d="M46 62 Q42 22 80 20 Q118 22 114 62 L110 80 L104 62 L56 62 L50 80Z" fill="url(#hairSilver)"/>'
    return ('<path d="M46 62 Q40 20 80 18 Q120 20 114 62 L110 44 L106 60 L98 36 L92 56 L84 32 L78 54 L70 34 L64 56 L56 38 L52 60Z" fill="url(#hairSilver)"/>'
            '<path d="M84 18 l10 -10 l-2 12z M70 20 l-6 -10 l10 6z" fill="url(#hairSilver)"/>'
            '<path d="M58 30 Q80 22 102 30" stroke="#ffffff" stroke-width="3" fill="none" opacity=".75" stroke-linecap="round"/>'
            '<path d="M98 36 L92 56" stroke="#d42a40" stroke-width="2.4" opacity=".7"/>')


def body(kind, jacket, state):
    b = []
    # legs
    if kind == "girl":
        b.append('<path d="M70 128 L68 152 M90 128 L92 152" stroke="#2a2342" stroke-width="7.5" stroke-linecap="round"/>')
        b.append('<ellipse cx="67" cy="155" rx="6" ry="3.6" fill="#3a1a28"/><ellipse cx="93" cy="155" rx="6" ry="3.6" fill="#3a1a28"/>')
        b.append(f'<path d="M62 116 L98 116 L106 134 Q80 140 54 134Z" fill="url(#{jacket})"/>'
                 '<path d="M64 120 L60 134 M72 120 L70 137 M80 120 V138 M88 120 L90 137 M96 120 L100 134" stroke="#03261c" stroke-width="1" opacity=".5"/>')
    else:
        b.append('<path d="M72 120 L70 152 M88 120 L90 152" stroke="#232838" stroke-width="9" stroke-linecap="round"/>')
        b.append('<ellipse cx="69" cy="155" rx="7" ry="3.8" fill="#14171f"/><ellipse cx="91" cy="155" rx="7" ry="3.8" fill="#14171f"/>')
    # jacket + shirt + tie
    b.append(f'<path d="M58 96 Q80 88 102 96 L106 122 Q80 128 54 122Z" fill="url(#{jacket})"/>')
    b.append('<path d="M72 94 L80 106 L88 94Z" fill="#fff"/><path d="M80 98 l-3 4 3 12 3 -12z" fill="url(#gold)"/>')
    b.append('<path d="M58 97 L54 122 M102 97 L106 122" stroke="url(#gold)" stroke-width="1.6"/><circle cx="68" cy="112" r="1.8" fill="url(#gold)"/><circle cx="92" cy="112" r="1.8" fill="url(#gold)"/>')
    return "".join(b)


def arms(state, jacket, sign):
    if state == "happy":
        # both arms up, a sign in the right hand
        a = (f'<path d="M60 100 L44 76 L40 60" stroke="url(#{jacket})" stroke-width="8" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
             f'<path d="M100 100 L116 76 L120 58" stroke="url(#{jacket})" stroke-width="8" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
             '<circle cx="40" cy="57" r="5" fill="url(#skin)"/><circle cx="120" cy="55" r="5" fill="url(#skin)"/>')
        return a + sign_board(120, 40, sign)
    # crying: fists rubbing the eyes
    return (f'<path d="M60 100 Q46 92 52 74" stroke="url(#{jacket})" stroke-width="8" fill="none" stroke-linecap="round"/>'
            f'<path d="M100 100 Q114 92 108 74" stroke="url(#{jacket})" stroke-width="8" fill="none" stroke-linecap="round"/>'
            '<circle cx="54" cy="70" r="6" fill="url(#skin)"/><circle cx="106" cy="70" r="6" fill="url(#skin)"/>'
            '<path d="M51 68 h6 M103 68 h6" stroke="#e8b7a0" stroke-width="1"/>')


def sign_board(x, y, sign):
    up = sign == "BUY"
    c = "url(#jackG)" if up else "url(#jackR)"
    return (f'<path d="M{x} {y + 20} V{y - 6}" stroke="url(#gold)" stroke-width="2.4"/>'
            f'<rect x="{x - 2}" y="{y - 24}" width="36" height="18" rx="3" fill="{c}" stroke="url(#gold)" stroke-width="1.6"/>'
            f'<text x="{x + 16}" y="{y - 10.5}" text-anchor="middle" font-size="10" font-weight="900" fill="#fff" font-family="Arial Black, sans-serif">{sign}</text>')


def confetti():
    cols = ["#f2c14e", "#1fd29d", "#ff8fa6", "#7fb6ff", "#fff1b8"]
    out = []
    for i in range(14):
        x = 14 + i * 10.5
        c = cols[i % len(cols)]
        dur = 1.6 + (i % 4) * .35
        out.append(f'<rect x="{x}" y="-6" width="4" height="7" rx="1" fill="{c}">'
                   f'<animateTransform attributeName="transform" type="translate" values="0 0; {(-1) ** i * 8} 90; {(-1) ** i * 2} 170" dur="{dur}s" begin="{i * .13}s" repeatCount="indefinite"/>'
                   f'<animate attributeName="opacity" values="1;1;0" dur="{dur}s" begin="{i * .13}s" repeatCount="indefinite"/></rect>')
    return "".join(out)


def coins():
    out = []
    for i, (x, dx) in enumerate(((40, -18), (80, 4), (120, 20))):
        out.append(f'<g><animateTransform attributeName="transform" type="translate" values="0 0; {dx} -46; {dx * 1.4} -20" dur="1.3s" begin="{i * .35}s" repeatCount="indefinite"/>'
                   f'<animate attributeName="opacity" values="0;1;1;0" dur="1.3s" begin="{i * .35}s" repeatCount="indefinite"/>'
                   f'<circle cx="{x}" cy="130" r="6" fill="url(#gold)" stroke="#a7771f"/><text x="{x}" y="133.5" text-anchor="middle" font-size="8" font-weight="900" fill="#7d5714">$</text></g>')
    return "".join(out)


def rain_cloud():
    drops = "".join(f'<path d="M{x} 22 v6" stroke="#8fc8ff" stroke-width="1.6" stroke-linecap="round">'
                    f'<animateTransform attributeName="transform" type="translate" values="0 0; 0 22" dur=".7s" begin="{i * .17}s" repeatCount="indefinite"/>'
                    f'<animate attributeName="opacity" values="1;0" dur=".7s" begin="{i * .17}s" repeatCount="indefinite"/></path>' for i, x in enumerate((64, 74, 84, 94)))
    return ('<g><animateTransform attributeName="transform" type="translate" values="-3 0; 3 0; -3 0" dur="2.4s" repeatCount="indefinite"/>'
            '<path d="M58 18 q-10 0 -10 -8 q0 -9 11 -8 q4 -9 15 -6 q8 -7 17 0 q12 -1 11 9 q8 2 6 9 q-1 4 -8 4z" fill="url(#cloud)"/>' + drops + '</g>')


def character(kind, state):
    jacket = "jackG" if kind == "girl" else "jackR"
    iris = "irisG" if kind == "girl" else "irisR"
    sign = "BUY" if kind == "girl" else "SELL"
    inner = hair(kind, False) + body(kind, jacket, state) + arms(state, jacket, sign) + face(state, iris) + hair(kind, True)
    if state == "cry":
        inner += tears()
        motion = '<animateTransform attributeName="transform" type="translate" values="-1.4 4; 1.4 4; -1.4 4" dur=".18s" repeatCount="indefinite"/>'
        puddle = '<ellipse cx="80" cy="160" rx="34" ry="4" fill="#6cc4ff" opacity=".35"><animate attributeName="rx" values="26;36;26" dur="2s" repeatCount="indefinite"/></ellipse>'
        loss = '<text x="140" y="96" text-anchor="middle" font-size="12" font-weight="900" fill="#ff5a70" font-family="Georgia, serif">−$<animate attributeName="opacity" values="1;.3;1" dur="1s" repeatCount="indefinite"/></text>'
        return f'<g filter="url(#stk)">{puddle}<g>{motion}{inner}</g></g>{rain_cloud()}{loss}'
    motion = '<animateTransform attributeName="transform" type="translate" values="0 0; 0 -12; 0 0" keyTimes="0;.45;1" dur=".6s" calcMode="spline" keySplines=".2 .7 .4 1; .6 0 .8 .3" repeatCount="indefinite"/>'
    shadow = '<ellipse cx="80" cy="160" rx="26" ry="4" fill="#000" opacity=".35"><animate attributeName="rx" values="26;18;26" dur=".6s" repeatCount="indefinite"/></ellipse>'
    gain = '<text x="22" y="100" text-anchor="middle" font-size="12" font-weight="900" fill="#3df0b6" font-family="Georgia, serif">+$<animate attributeName="opacity" values="1;.3;1" dur="1s" repeatCount="indefinite"/></text>'
    sparks = star(18, 40, 5, "#f2c14e") + star(142, 86, 4, "#f2c14e", begin=".5s") + star(30, 130, 3.4, "#fff1b8", begin=".8s")
    return f'{confetti()}{shadow}<g filter="url(#stk)"><g>{motion}{inner}</g></g>{coins()}{sparks}{gain}'

EXTRA_DEFS = """
<filter id="gray"><feColorMatrix type="saturate" values=".12"/><feComponentTransfer><feFuncR type="linear" slope=".92"/><feFuncG type="linear" slope=".95"/><feFuncB type="linear" slope="1.05"/></feComponentTransfer></filter>
<linearGradient id="bill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b8f5c8"/><stop offset="1" stop-color="#3f9a5c"/></linearGradient>
<linearGradient id="tea" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d9a35b"/><stop offset="1" stop-color="#8a5422"/></linearGradient>
"""


# ---------- eyes ----------
def eyes(kind, iris):
    o = []
    for cx, side in ((66, -1), (94, 1)):
        lid = (f'<path d="M{cx - 9.5} 60 Q{cx} 51 {cx + 9.5} 59.5" stroke="{INK}" stroke-width="2.8" fill="none" stroke-linecap="round"/>'
               f'<path d="M{cx + side * 9.5} {59.5 if side > 0 else 60} l{side * 3.2} -2.6" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>')
        ball = (f'<ellipse cx="{cx}" cy="65" rx="8.6" ry="10.2" fill="#fff"/><ellipse cx="{cx}" cy="66" rx="7" ry="9" fill="url(#{iris})"/>'
                f'<ellipse cx="{cx}" cy="67.5" rx="3.2" ry="4.4" fill="#0b1712" opacity=".85"/>')
        shine = f'<ellipse cx="{cx - 2.6}" cy="62" rx="2.6" ry="3.2" fill="#fff"/><circle cx="{cx + 2.8}" cy="70.5" r="1.3" fill="#fff"/>'
        if kind == "starry":
            o.append(ball + star(cx - 2.4, 62.5, 3.6) + star(cx + 2.8, 70, 1.8, "#fff4c4", begin=".4s") + lid)
        elif kind == "dollar":
            o.append(f'<ellipse cx="{cx}" cy="65" rx="8.6" ry="10.2" fill="#fff"/>'
                     f'<text x="{cx}" y="71.5" text-anchor="middle" font-size="17" font-weight="900" fill="url(#gold)" stroke="#7d5714" stroke-width=".7" font-family="Georgia, serif">$'
                     f'<animate attributeName="font-size" values="17;20;17" dur=".5s" repeatCount="indefinite"/></text>' + lid)
        elif kind == "cry":
            o.append(f'<path d="M{cx - 8 if side < 0 else cx + 8} 58 L{cx + 6 if side < 0 else cx - 6} 64.5 L{cx - 8 if side < 0 else cx + 8} 71" stroke="{INK}" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
        elif kind == "joy":
            o.append(f'<path d="M{cx - 8} 68 Q{cx} 57 {cx + 8} 68" stroke="{INK}" stroke-width="3" fill="none" stroke-linecap="round"/>'
                     f'<path d="M{cx + side * 9} 66 q2 3.5 0 5.6 q-2 -2 0 -5.6z" fill="url(#tear)"/>')
        elif kind == "sleep":
            o.append(f'<path d="M{cx - 8} 65 Q{cx} 71 {cx + 8} 65" stroke="{INK}" stroke-width="2.6" fill="none" stroke-linecap="round"/>'
                     f'<path d="M{cx + side * 8} 65 l{side * 2.6} 1.6" stroke="{INK}" stroke-width="1.6" stroke-linecap="round"/>')
        elif kind == "shock":
            o.append(f'<ellipse cx="{cx}" cy="64" rx="9" ry="11" fill="#fff" stroke="{INK}" stroke-width="1.6"/>'
                     f'<circle cx="{cx}" cy="64" r="1.7" fill="{INK}"><animate attributeName="r" values="1.7;1.2;1.7" dur=".25s" repeatCount="indefinite"/></circle>')
        elif kind == "angry":
            cover = (f'{cx - 11},48 {cx + 11},48 {cx + 11},64 {cx - 11},57' if side < 0 else f'{cx - 11},48 {cx + 11},48 {cx + 11},57 {cx - 11},64')
            line = (f'M{cx - 11} 57 L{cx + 11} 63.5' if side < 0 else f'M{cx - 11} 63.5 L{cx + 11} 57')
            o.append(ball + f'<circle cx="{cx}" cy="67" r="1.6" fill="#fff"/><polygon points="{cover}" fill="url(#skin)"/>'
                     f'<path d="{line}" stroke="{INK}" stroke-width="3.2" stroke-linecap="round"/>')
        elif kind == "dart":
            o.append(f'<ellipse cx="{cx}" cy="65" rx="8.6" ry="10.2" fill="#fff"/><g>'
                     f'<animateTransform attributeName="transform" type="translate" values="-2.8 0; -2.8 0; 2.8 0; 2.8 0; -2.8 0" keyTimes="0;.3;.4;.8;1" dur="1.2s" repeatCount="indefinite"/>'
                     f'<ellipse cx="{cx}" cy="66" rx="5.6" ry="7.6" fill="url(#{iris})"/><ellipse cx="{cx}" cy="67" rx="2.6" ry="3.6" fill="#0b1712"/><circle cx="{cx - 2}" cy="63" r="1.8" fill="#fff"/></g>' + lid)
        elif kind == "blink":
            o.append(ball + shine + lid + f'<g opacity="0"><animate attributeName="opacity" values="0;0;1;0" keyTimes="0;.9;.95;1" dur="3.6s" repeatCount="indefinite"/>'
                     f'<ellipse cx="{cx}" cy="64" rx="10" ry="11.5" fill="url(#skin)"/><path d="M{cx - 8} 65 Q{cx} 70 {cx + 8} 65" stroke="{INK}" stroke-width="2.6" fill="none" stroke-linecap="round"/></g>')
        else:
            o.append(ball + shine + lid)
    return "".join(o)


def brows(kind):
    if kind in ("cry", "shock", "dart"):
        return f'<path d="M58 47 Q64 44 72 49 M102 47 Q96 44 88 49" stroke="{INK}" stroke-width="2" fill="none" stroke-linecap="round"/>'
    if kind == "angry":
        return f'<path d="M56 45 L72 52 M104 45 L88 52" stroke="{INK}" stroke-width="2.8" stroke-linecap="round"/>'
    if kind == "sleep":
        return f'<path d="M58 51 Q64 49 72 51 M102 51 Q96 49 88 51" stroke="{INK}" stroke-width="1.6" fill="none" stroke-linecap="round"/>'
    return f'<path d="M58 48 Q64 45 72 47 M102 48 Q96 45 88 47" stroke="{INK}" stroke-width="1.8" fill="none" stroke-linecap="round"/>'


MOUTHS = {
    "grin": '<path d="M70 79 Q80 94 90 79 Z" fill="#9b1d3a"/><path d="M73 86 Q80 91 87 86 Q80 83 73 86Z" fill="#ff8fa6"/><path d="M71 79.5 h18" stroke="#fff" stroke-width="2"/>',
    "wail": '<path d="M67 91 Q68 77 80 77 Q92 77 93 91 Q80 87 67 91Z" fill="#7d1430"/><path d="M70 81 Q80 76.5 90 81" stroke="#fff" stroke-width="2.4" fill="none"/><path d="M72 89.5 Q80 85 88 89.5 Q80 88 72 89.5Z" fill="#ff8fa6"/>',
    "smile": '<path d="M74 82 Q80 87 86 82" stroke="#7a1b2b" stroke-width="1.8" fill="none" stroke-linecap="round"/>',
    "o": '<ellipse cx="80" cy="84" rx="2.6" ry="3.2" fill="#7d1430"/>',
    "scream": '<ellipse cx="80" cy="85" rx="6" ry="9" fill="#5e0d22"/><ellipse cx="80" cy="90" rx="3.6" ry="3" fill="#ff8fa6"/>',
    "teeth": '<path d="M70 81 h20 v6 q-10 3 -20 0z" fill="#fff" stroke="#7a1b2b" stroke-width="1.4"/><path d="M75 81v7M80 81v8M85 81v7M70 84h20" stroke="#7a1b2b" stroke-width=".8"/>',
    "wavy": '<path d="M71 84 q2.2 -2.6 4.5 0 t4.5 0 t4.5 0 t4.5 0" stroke="#7a1b2b" stroke-width="1.8" fill="none" stroke-linecap="round"/>',
    "money": '<path d="M68 78 Q80 98 92 78 Z" fill="#9b1d3a"/><path d="M72 87 Q80 93 88 87 Q80 84 72 87Z" fill="#ff8fa6"/><path d="M69 78.5 h22" stroke="#fff" stroke-width="2.2"/><path d="M86 90 q2 5 -1 9" stroke="#bfe6ff" stroke-width="1.6" fill="none"/>',
}


def face(eye, mouth, iris):
    f = ['<path d="M50 58 Q50 92 80 95 Q110 92 110 58 Q110 31 80 31 Q50 31 50 58Z" fill="url(#skin)"/>', eyes(eye, iris), brows(eye)]
    if eye in ("cry", "shock"):
        f.append('<path d="M60 40v7M66 39v8M72 40v6M88 40v6M94 39v8M100 40v7" stroke="#7a6cc2" stroke-width="1.4" opacity=".55"/>')
    if eye == "angry":
        f.append('<path d="M52 56 Q80 50 108 56 L108 92 Q80 98 52 92Z" fill="#ff2a45" opacity=".16"/>')
    if eye != "shock":
        for bx in (60, 100):
            f.append(f'<ellipse cx="{bx}" cy="77" rx="6" ry="3.2" fill="#ff8fa6" opacity=".55"/><path d="M{bx - 3} 79l2-4M{bx} 79l2-4M{bx + 3} 79l2-4" stroke="#ff6d8d" stroke-width="1" opacity=".7"/>')
    f.append(MOUTHS[mouth])
    return "".join(f)


# ---------- arms ----------
def arms(pose, jacket, sign):
    J = f'stroke="url(#{jacket})" stroke-width="8" fill="none" stroke-linecap="round" stroke-linejoin="round"'
    hand = lambda x, y, r=5: f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#skin)"/>'
    if pose == "up":
        return f'<path d="M60 100 L44 76 L40 60" {J}/><path d="M100 100 L116 76 L120 58" {J}/>' + hand(40, 57) + hand(120, 55) + sign_board(120, 40, sign)
    if pose == "throw":
        bills = "".join(f'<g transform="translate({x} {y}) rotate({r})"><rect x="-7" y="-4" width="14" height="8" rx="1" fill="url(#bill)" stroke="#2d6a40" stroke-width=".6"/><text x="0" y="2.6" text-anchor="middle" font-size="6" font-weight="900" fill="#1f5a33">$</text></g>' for x, y, r in ((38, 52, -20), (122, 50, 24)))
        return f'<path d="M60 100 L44 76 L40 60" {J}/><path d="M100 100 L116 76 L120 58" {J}/>' + hand(40, 57) + hand(120, 55) + bills
    if pose == "rub":
        return (f'<path d="M60 100 Q46 92 52 74" {J}/><path d="M100 100 Q114 92 108 74" {J}/>' + hand(54, 70, 6) + hand(106, 70, 6))
    if pose == "cup":
        steam = "".join(f'<path d="M{x} 96 q-3 -5 0 -9 t0 -9" stroke="#fff" stroke-width="1.6" fill="none" opacity=".7" stroke-linecap="round">'
                        f'<animateTransform attributeName="transform" type="translate" values="0 4; 0 -6" dur="1.6s" begin="{i * .8}s" repeatCount="indefinite"/>'
                        f'<animate attributeName="opacity" values="0;.8;0" dur="1.6s" begin="{i * .8}s" repeatCount="indefinite"/></path>' for i, x in enumerate((77, 83)))
        return (f'<path d="M60 100 Q60 114 72 110" {J}/><path d="M100 100 Q100 114 88 110" {J}/>'
                + steam + '<path d="M71 99 h18 l-2.4 13 h-13.2z" fill="#fff8ee" stroke="url(#gold)" stroke-width="1.4"/><ellipse cx="80" cy="100" rx="8.4" ry="2" fill="url(#tea)"/>'
                '<path d="M89 102 q6 1 4 6 q-1 2 -4 1" stroke="url(#gold)" stroke-width="1.6" fill="none"/>' + hand(72, 109) + hand(88, 109))
    if pose == "nails":
        return f'<path d="M60 100 Q56 92 72 89" {J}/><path d="M100 100 Q104 92 88 89" {J}/>' + hand(74, 88, 4.6) + hand(86, 88, 4.6)
    if pose == "cheeks":
        return f'<path d="M60 100 Q46 94 52 82" {J}/><path d="M100 100 Q114 94 108 82" {J}/>' + hand(54, 79, 6) + hand(106, 79, 6)
    if pose == "fists":
        return (f'<g><animateTransform attributeName="transform" type="translate" values="0 0; 0 -3; 0 0" dur=".25s" repeatCount="indefinite"/>'
                f'<path d="M60 100 L50 116" {J}/><path d="M100 100 L110 116" {J}/>' + hand(49, 118, 6) + hand(111, 118, 6) + '</g>')
    if pose == "trophy":
        return (f'<path d="M60 100 L44 78 L58 36" {J}/><path d="M100 100 L116 78 L102 36" {J}/>'
                '<g><path d="M64 -10 h32 q0 22 -16 26 q-16 -4 -16 -26z" fill="url(#gold)" stroke="#a7771f"/>'
                '<path d="M64 -6 q-10 0 -8 8 q2 6 10 6 M96 -6 q10 0 8 8 q-2 6 -10 6" stroke="url(#gold)" stroke-width="2.4" fill="none"/>'
                '<rect x="76" y="16" width="8" height="8" fill="url(#gold)"/><rect x="68" y="24" width="24" height="6" rx="1.5" fill="#7d5714"/>'
                '<path d="M74 -4 q2 10 6 14" stroke="#fff" stroke-width="2" fill="none" opacity=".55"/></g>' + hand(58, 34) + hand(102, 34))
    # relaxed
    return f'<path d="M60 100 L56 120" {J}/><path d="M100 100 L104 120" {J}/>' + hand(56, 122) + hand(104, 122)


# ---------- effects ----------
def bills_rain():
    out = []
    for i in range(10):
        x = 12 + i * 15
        d = 1.8 + (i % 3) * .4
        out.append(f'<g><animateTransform attributeName="transform" type="translate" values="{x} -14; {x + (-1) ** i * 10} 80; {x} 175" dur="{d}s" begin="{i * .17}s" repeatCount="indefinite"/>'
                   f'<g><animateTransform attributeName="transform" type="rotate" values="0; {(-1) ** i * 180}; {(-1) ** i * 360}" dur="{d}s" begin="{i * .17}s" repeatCount="indefinite"/>'
                   '<rect x="-7" y="-4" width="14" height="8" rx="1" fill="url(#bill)" stroke="#2d6a40" stroke-width=".6"/><text x="0" y="2.6" text-anchor="middle" font-size="6" font-weight="900" fill="#1f5a33">$</text></g></g>')
    return "".join(out)


def burst(x, y, col, begin):
    rays = "".join(f'<path d="M0 0 L0 -14" transform="rotate({a})" stroke="{col}" stroke-width="2" stroke-linecap="round"/>' for a in range(0, 360, 30))
    return (f'<g transform="translate({x} {y})"><g>{rays}<animateTransform attributeName="transform" type="scale" values=".1;1.2;1.3" dur="1.4s" begin="{begin}" repeatCount="indefinite"/>'
            f'<animate attributeName="opacity" values="1;1;0" dur="1.4s" begin="{begin}" repeatCount="indefinite"/></g></g>')


def zzz():
    return "".join(f'<text x="118" y="40" font-size="{10 + i * 4}" font-weight="900" fill="#c9d6ff" font-family="Georgia, serif">Z'
                   f'<animateTransform attributeName="transform" type="translate" values="0 10; {8 + i * 6} -26" dur="2.4s" begin="{i * .8}s" repeatCount="indefinite"/>'
                   f'<animate attributeName="opacity" values="0;1;0" dur="2.4s" begin="{i * .8}s" repeatCount="indefinite"/></text>' for i in range(3))


def bubble():
    return ('<ellipse cx="88" cy="80" rx="4" ry="3.6" fill="#bfe6ff" fill-opacity=".45" stroke="#e6f6ff" stroke-width="1">'
            '<animate attributeName="rx" values="2;9;2" dur="2.4s" repeatCount="indefinite"/><animate attributeName="ry" values="2;8;2" dur="2.4s" repeatCount="indefinite"/>'
            '<animate attributeName="cx" values="86;92;86" dur="2.4s" repeatCount="indefinite"/></ellipse>')


def sweat():
    return "".join(f'<path d="M{x} 34 q3 5 0 8 q-3 -3 0 -8z" fill="#8fd3ff"><animateTransform attributeName="transform" type="translate" values="0 0; {dx} 22" dur="1s" begin="{i * .5}s" repeatCount="indefinite"/>'
                   f'<animate attributeName="opacity" values="1;0" dur="1s" begin="{i * .5}s" repeatCount="indefinite"/></path>' for i, (x, dx) in enumerate(((112, 6), (48, -6))))


def alert():
    return ('<text x="128" y="44" font-size="26" font-weight="900" fill="#ffcf4a" stroke="#a7771f" stroke-width=".8" font-family="Georgia, serif">!<animate attributeName="opacity" values="1;.15;1" dur=".5s" repeatCount="indefinite"/></text>'
            '<text x="24" y="40" font-size="20" font-weight="900" fill="#ffcf4a" font-family="Georgia, serif">!<animate attributeName="opacity" values=".15;1;.15" dur=".5s" repeatCount="indefinite"/></text>'
            '<g transform="translate(18 112)"><circle r="10" fill="url(#rBomb2)"/><path d="M6 -8 q4 -6 9 -3" stroke="#d8b26a" stroke-width="1.6" fill="none"/>'
            + star(16, -12, 3.4, "#ffb23f", dur=".4s") + '<text y="3.4" text-anchor="middle" font-size="7" font-weight="800" fill="url(#gold)" font-family="Georgia, serif">TIN</text></g>')


def soul():
    return ('<g opacity=".85"><animateTransform attributeName="transform" type="translate" values="0 10; 4 -28" dur="2.6s" repeatCount="indefinite"/>'
            '<animate attributeName="opacity" values="0;.9;0" dur="2.6s" repeatCount="indefinite"/>'
            '<path d="M80 0 q-12 0 -12 14 q0 10 4 14 q2 -4 4 0 q2 -4 4 0 q2 -4 4 0 q4 -4 4 -14 q0 -14 -12 -14z" fill="#f4f8ff"/>'
            '<circle cx="76" cy="12" r="1.6" fill="#7a86a8"/><circle cx="84" cy="12" r="1.6" fill="#7a86a8"/><ellipse cx="80" cy="18" rx="2" ry="2.4" fill="#7a86a8"/></g>')


def lightning():
    return ('<path d="M132 4 L118 40 L128 40 L114 76 L142 32 L130 32 L140 4Z" fill="#ffe36b" stroke="#a7771f">'
            '<animate attributeName="opacity" values="0;1;0;0;1;0" dur="1.4s" repeatCount="indefinite"/></path>'
            '<path d="M28 10 L18 36 L26 36 L16 60 L36 30 L28 30 L36 10Z" fill="#ffe36b" stroke="#a7771f" opacity="0">'
            '<animate attributeName="opacity" values="0;0;1;0;0" dur="1.4s" repeatCount="indefinite"/></path>')


def cracks():
    return '<path d="M64 42 l6 8 -4 6 7 8 M96 106 l-5 6 4 5 -6 7" stroke="#3a3f4c" stroke-width="1.6" fill="none"/>'


def steam_puffs():
    return "".join(f'<circle cx="{x}" cy="30" r="5" fill="#f2f2f2"><animate attributeName="r" values="3;9" dur="1s" begin="{i * .5}s" repeatCount="indefinite"/>'
                   f'<animateTransform attributeName="transform" type="translate" values="0 0; {dx} -20" dur="1s" begin="{i * .5}s" repeatCount="indefinite"/>'
                   f'<animate attributeName="opacity" values=".9;0" dur="1s" begin="{i * .5}s" repeatCount="indefinite"/></circle>' for i, (x, dx) in enumerate(((48, -10), (112, 10), (52, -6), (108, 6))))


def vein():
    return ('<g transform="translate(101 41)"><g><animateTransform attributeName="transform" type="scale" values="1;1.35;1" dur=".5s" repeatCount="indefinite"/>'
            '<path d="M-6 -2 q4 0 4 -4 M2 -6 q0 4 4 4 M6 2 q-4 0 -4 4 M-2 6 q0 -4 -4 -4" stroke="#e3243f" stroke-width="2.4" fill="none" stroke-linecap="round"/></g></g>')


def sl_stamp():
    return ('<g transform="translate(130 112) rotate(-14)"><rect x="-17" y="-10" width="34" height="20" rx="3" fill="none" stroke="#e3243f" stroke-width="2.4"/>'
            '<text y="5.5" text-anchor="middle" font-size="14" font-weight="900" fill="#e3243f" font-family="Arial Black, sans-serif">SL</text>'
            '<animateTransform attributeName="transform" type="scale" values="1.4;1;1" dur="1.2s" additive="sum" repeatCount="indefinite"/></g>')


# ---------- motions ----------
MOTIONS = {
    "hop": '<animateTransform attributeName="transform" type="translate" values="0 0; 0 -12; 0 0" keyTimes="0;.45;1" dur=".6s" calcMode="spline" keySplines=".2 .7 .4 1; .6 0 .8 .3" repeatCount="indefinite"/>',
    "dance": '<animateTransform attributeName="transform" type="rotate" values="-7 80 160; 7 80 160; -7 80 160" dur=".7s" repeatCount="indefinite"/>',
    "breathe": '<animateTransform attributeName="transform" type="translate" values="0 0; 0 1.6; 0 0" dur="2.6s" repeatCount="indefinite"/>',
    "nod": '<animateTransform attributeName="transform" type="rotate" values="0 80 150; 5 80 150; 0 80 150; 0 80 150" keyTimes="0;.4;.55;1" dur="2.4s" repeatCount="indefinite"/>',
    "tremble": '<animateTransform attributeName="transform" type="translate" values="-1 0; 1 .5; -1 0" dur=".09s" repeatCount="indefinite"/>',
    "shake": '<animateTransform attributeName="transform" type="translate" values="-1.4 4; 1.4 4; -1.4 4" dur=".18s" repeatCount="indefinite"/>',
    "frozen": '<animateTransform attributeName="transform" type="translate" values="0 0; 0 0; -2 0; 2 0; 0 0" keyTimes="0;.8;.86;.93;1" dur="1.6s" repeatCount="indefinite"/>',
    "stomp": '<animateTransform attributeName="transform" type="translate" values="0 0; 0 -4; 0 1; 0 0" dur=".35s" repeatCount="indefinite"/>',
}

# state: (eyes, mouth, arms, motion, gray, back effects, front effects)
STATES = {
    "rich":    ("dollar", "money", "throw", "dance", False, lambda k: bills_rain(), lambda k: coins() + burst(24, 30, "#f2c14e", "0s") + burst(138, 40, "#1fd29d", ".7s")),
    "happy":   ("starry", "grin", "up", "hop", False, lambda k: confetti(), lambda k: coins() + star(18, 40, 5, "#f2c14e") + star(142, 86, 4, "#f2c14e", begin=".5s")),
    "tea":     ("blink", "smile", "cup", "breathe", False, lambda k: "", lambda k: ""),
    "sleep":   ("sleep", "o", "relax", "nod", False, lambda k: "", lambda k: zzz() + bubble()),
    "nervous": ("dart", "wavy", "nails", "tremble", False, lambda k: "", lambda k: sweat() + alert()),
    "cry":     ("cry", "wail", "rub", "shake", False, lambda k: '<ellipse cx="80" cy="160" rx="30" ry="4" fill="#6cc4ff" opacity=".35"><animate attributeName="rx" values="24;34;24" dur="2s" repeatCount="indefinite"/></ellipse>', lambda k: tears() + rain_cloud()),
    "shock":   ("shock", "scream", "cheeks", "frozen", True, lambda k: lightning(), lambda k: soul() + cracks()),
    "angry":   ("angry", "teeth", "fists", "stomp", False, lambda k: "", lambda k: steam_puffs() + vein() + sl_stamp()),
    "trophy":  ("joy", "grin", "trophy", "hop", False, lambda k: burst(26, 26, "#f2c14e", "0s") + burst(136, 30, "#ff8fa6", ".5s") + burst(30, 110, "#1fd29d", ".9s"), lambda k: star(140, 96, 4, "#fff1b8")),
}

LABELS = {
    "rich": ("Lãi đậm", "tăng mạnh / lãi lớn"), "happy": ("Vui mừng", "giá đi đúng hướng"), "tea": ("Nhâm nhi trà", "giá đi ngang, chờ"),
    "sleep": ("Ngủ gật", "thị trường im lìm"), "nervous": ("Hồi hộp", "sắp có tin mạnh"), "cry": ("Khóc như mưa", "giá đi ngược"),
    "shock": ("Hồn lìa khỏi xác", "đi ngược rất mạnh"), "angry": ("Tức điên", "lệnh dính SL"), "trophy": ("Ăn mừng TP", "lệnh chạm TP"),
}


def character(kind, state):
    jacket = "jackG" if kind == "girl" else "jackR"
    iris = "irisG" if kind == "girl" else "irisR"
    sign = "BUY" if kind == "girl" else "SELL"
    eye, mouth, pose, motion, gray, back, front = STATES[state]
    # Hands at the mouth go over the face; the others behind it.
    front_hands = pose in ("nails",)
    inner = (hair(kind, False) + body(kind, jacket, state) + ("" if front_hands else arms(pose, jacket, sign))
             + face(eye, mouth, iris) + hair(kind, True) + (arms(pose, jacket, sign) if front_hands else ""))
    if gray:
        inner = f'<g filter="url(#gray)">{inner}</g>'
    return f'{back(kind)}<g filter="url(#stk)"><g>{MOTIONS[motion]}{inner}</g></g>{front(kind)}'
