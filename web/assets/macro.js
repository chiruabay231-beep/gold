/* Macro — the times of day when gold moves the most, found in the 1m bars from 28 Jan to 6 Nov 2026
 * (each 5-minute range against the day's median). Each window is set in the clock of the market that makes
 * it (New York, London, or Vietnam / Asia, which has no summer time), so in Vietnam time it moves by an
 * hour by itself when the US / UK change their clocks. Shown as shaded bands with their numbers, and the
 * next window with a countdown. */
(() => {
  "use strict";

  const WINDOWS = [
    { name: "CME mở lại", tz: "America/New_York", from: "18:00", to: "18:25", ses: "asia", stat: "2.1× · 81% ngày (đông)", note: "spread giãn, có gap" },
    { name: "Tokyo mở", tz: "Asia/Ho_Chi_Minh", from: "07:00", to: "07:10", ses: "asia", stat: "1.6–1.75× · ~40% ngày" },
    { name: "Thượng Hải mở", tz: "Asia/Ho_Chi_Minh", from: "08:00", to: "08:45", ses: "asia", stat: "1.8× · 88% ngày", strong: true },
    { name: "Thượng Hải chiều", tz: "Asia/Ho_Chi_Minh", from: "12:30", to: "12:40", ses: "asia", stat: "1.4–1.7× · 16–55% ngày" },
    { name: "London mở", tz: "Europe/London", from: "08:00", to: "08:15", ses: "london", stat: "1.1–1.25× (yếu)", weak: true },
    { name: "COMEX + tin 8:30", tz: "America/New_York", from: "08:20", to: "08:45", ses: "ny", stat: "2× · 62–72% ngày" },
    { name: "Mỹ mở cửa", tz: "America/New_York", from: "09:30", to: "09:45", ses: "ny", stat: "2.3–2.6× · 83–94% ngày", strong: true },
    { name: "Tin 10:00", tz: "America/New_York", from: "09:50", to: "10:10", ses: "ny", stat: "2.2× · 78–87% ngày", strong: true },
    { name: "Sau tin", tz: "America/New_York", from: "10:10", to: "11:10", ses: "ny", stat: "1.8×", weak: true },
  ];

  function defaults() {
    return { asia: true, london: true, ny: true, weak: true, labels: true, countdown: true, maxTf: 3600, colAsia: "#f2c14e", colLondon: "#2962ff", colNy: "#e91e63" };
  }
  function merge(saved) {
    const d = defaults();
    if (!saved || typeof saved !== "object") return d;
    Object.keys(d).forEach((k) => { if (saved[k] !== undefined && typeof saved[k] === typeof d[k]) d[k] = saved[k]; });
    return d;
  }

  // Offset of a time zone (seconds east of UTC) at a moment, through Intl.
  const FMT = new Map();
  function offset(tz, t) {
    let f = FMT.get(tz);
    if (!f) { f = new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" }); FMT.set(tz, f); }
    const p = Object.fromEntries(f.formatToParts(new Date(t * 1000)).map((x) => [x.type, x.value]));
    return (Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour % 24, +p.minute, +p.second) / 1000) - t;
  }
  /** UTC seconds of a wall-clock time `hm` on the day `y-m-d` of zone `tz`. */
  function at(tz, y, m, d, hm) {
    const [h, mi] = hm.split(":").map(Number), guess = Date.UTC(y, m - 1, d, h, mi) / 1000;
    let t = guess - offset(tz, guess);
    t = guess - offset(tz, t);
    return t;
  }
  /** The calendar day (in `tz`) of a moment. */
  function dayIn(tz, t) {
    const s = new Date((t + offset(tz, t)) * 1000);
    return [s.getUTCFullYear(), s.getUTCMonth() + 1, s.getUTCDate()];
  }

  /** The windows that overlap [t0, t1] (UTC seconds), on weekdays only. */
  function windows(t0, t1, cfg) {
    const out = [];
    const on = (w) => cfg[w.ses] && (cfg.weak || !w.weak);
    for (let t = t0 - 86400; t <= t1 + 86400; t += 86400) {
      WINDOWS.filter(on).forEach((w) => {
        const [y, m, d] = dayIn(w.tz, t);
        const a = at(w.tz, y, m, d, w.from), b = at(w.tz, y, m, d, w.to);
        const wd = new Date((a + offset(w.tz, a)) * 1000).getUTCDay();
        // Trading days: the CME reopen is Sunday to Thursday evening in New York, the rest Monday to Friday.
        const ok = w.name === "CME mở lại" ? wd >= 0 && wd <= 4 : wd >= 1 && wd <= 5;
        if (ok && b >= t0 && a <= t1 && !out.some((x) => x.w === w && x.a === a)) out.push({ w, a, b });
      });
    }
    return out.sort((x, y) => x.a - y.a);
  }

  const vn = (t) => new Date((t + 7 * 3600) * 1000).toISOString().slice(11, 16);

  function compute(bars, sec, cfg, now = Date.now() / 1000) {
    if (!bars || !bars.length || sec > (cfg.maxTf || 3600)) return null;
    const t0 = bars[0].time, t1 = Math.max(bars[bars.length - 1].time + sec, now) + 2 * 86400;
    return { list: windows(t0, t1, cfg), sec };
  }

  function rgba(hex, a) {
    const h = (hex || "#787b86").replace("#", "");
    return `rgba(${parseInt(h.slice(0, 2), 16)}, ${parseInt(h.slice(2, 4), 16)}, ${parseInt(h.slice(4, 6), 16)}, ${a})`;
  }
  const colorOf = (w, cfg) => (w.ses === "asia" ? cfg.colAsia : w.ses === "london" ? cfg.colLondon : cfg.colNy);

  /** Bands under the candles, `T(time)` → x. */
  function draw(g, o, cfg, T, w, h) {
    if (!o) return;
    g.save();
    g.font = "600 10px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif"; g.textBaseline = "top";
    let lastLabel = -Infinity;
    o.list.forEach(({ w: m, a, b }) => {
      const xa = T(a), xb = T(b);
      if (xa == null || xb == null || xb < 0 || xa > w) return;
      const c = colorOf(m, cfg), x0 = Math.max(0, xa), x1 = Math.min(w, xb);
      g.fillStyle = rgba(c, m.strong ? 0.16 : m.weak ? 0.06 : 0.1);
      g.fillRect(x0, 0, Math.max(1, x1 - x0), h);
      g.strokeStyle = rgba(c, 0.55); g.lineWidth = 1;
      g.beginPath(); g.moveTo(Math.round(xa) + 0.5, 0); g.lineTo(Math.round(xa) + 0.5, h); g.stroke();
      if (cfg.labels && xa >= 0 && xa - lastLabel > 150) {
        lastLabel = xa;
        g.fillStyle = rgba(c, 0.95); g.textAlign = "left";
        g.fillText(`${vn(a)} ${m.name} · ${m.stat}`, xa + 3, 6);
      }
    });
    g.restore();
  }

  /** The window running now or the next one, with a countdown, at the top middle. */
  function drawStatus(g, o, cfg, w, now = Date.now() / 1000) {
    if (!o || !cfg.countdown) return;
    const cur = o.list.find((x) => x.a <= now && x.b > now), next = o.list.find((x) => x.a > now);
    const pick = cur || next;
    if (!pick) return;
    const left = Math.max(0, Math.round((cur ? cur.b : next.a) - now));
    const hh = Math.floor(left / 3600), mm = Math.floor((left % 3600) / 60), ss = left % 60;
    const clock = `${hh ? hh + ":" : ""}${String(mm).padStart(hh ? 2 : 1, "0")}:${String(ss).padStart(2, "0")}`;
    const text = cur ? `⏱ ĐANG MACRO ${cur.w.name} ${vn(cur.a)}–${vn(cur.b)} · còn ${clock}` : `⏱ Macro tới: ${next.w.name} ${vn(next.a)}–${vn(next.b)} · sau ${clock}`;
    g.save();
    g.font = "700 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif"; g.textBaseline = "middle";
    const tw = g.measureText(text).width + 16, x = Math.max(8, w / 2 - tw / 2), y = 34;
    g.fillStyle = cur ? rgba(colorOf(cur.w, cfg), 0.92) : "rgba(15, 20, 30, 0.85)";
    g.beginPath(); g.roundRect(x, y - 10, tw, 20, 10); g.fill();
    g.fillStyle = "#ffffff"; g.textAlign = "left"; g.fillText(text, x + 8, y + 0.5);
    g.restore();
  }

  window.MACRO = { WINDOWS, defaults, merge, compute, draw, drawStatus, windows };
})();
