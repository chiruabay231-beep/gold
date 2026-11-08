/* Two indicators of the ICT toolkit, on the chart's own timeframe:
 *  UNICORN — the unicorn model: a breaker block (a swing high / low that price swept past, then broke the
 *            other way) overlapped by the fair value gap of the move that broke it. The overlap is the
 *            entry zone; stop beyond the breaker's sweep, target 2R. Each zone shows its state (waiting,
 *            touched → won / lost, broken) and the chart keeps the record.
 *  BBOB    — order blocks (the last opposite candle before a displacement that breaks a swing), breaker
 *            blocks (an order block that failed: closed through, it turns into the other side), and strong
 *            CISD (a close through the open of the opposite run, at a swept swing, with a big body).
 * Everything at a bar is worked out from the bars up to it. */
(() => {
  "use strict";

  const rgba = (hex, a) => { const h = (hex || "#787b86").replace("#", ""); return `rgba(${parseInt(h.slice(0, 2), 16)}, ${parseInt(h.slice(2, 4), 16)}, ${parseInt(h.slice(4, 6), 16)}, ${a})`; };
  const merge = (d, saved) => { if (saved && typeof saved === "object") Object.keys(d).forEach((k) => { if (saved[k] !== undefined && typeof saved[k] === typeof d[k]) d[k] = saved[k]; }); return d; };
  const bodyTop = (b) => Math.max(b.open, b.close), bodyBot = (b) => Math.min(b.open, b.close);
  function avgRange(c, n) { const o = new Array(c.length).fill(0); let s = 0; c.forEach((b, i) => { s += b.high - b.low; if (i >= n) s -= c[i - n].high - c[i - n].low; o[i] = s / Math.min(i + 1, n); }); return o; }
  function pivots(c, len) {
    const hi = [], lo = [];
    for (let i = len; i + len < c.length; i++) {
      let h = true, l = true;
      for (let k = 1; k <= len; k++) { if (c[i - k].high >= c[i].high || c[i + k].high > c[i].high) h = false; if (c[i - k].low <= c[i].low || c[i + k].low < c[i].low) l = false; }
      if (h) hi.push(i); if (l) lo.push(i);
    }
    return { hi, lo };
  }
  const font = (g, s = 10.5) => { g.font = `600 ${s}px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif`; g.textBaseline = "middle"; };
  function pill(g, text, x, y, bg) { const tw = g.measureText(text).width + 10; g.fillStyle = bg; g.beginPath(); g.roundRect(x, y - 8, tw, 16, 4); g.fill(); g.fillStyle = "#fff"; g.textAlign = "left"; g.fillText(text, x + 5, y + 0.5); }
  function box(g, x0, x1, y0, y1, fill, stroke, dash) {
    const top = Math.min(y0, y1), hh = Math.max(1, Math.abs(y1 - y0));
    g.fillStyle = fill; g.fillRect(x0, top, Math.max(1, x1 - x0), hh);
    if (stroke) { g.strokeStyle = stroke; g.lineWidth = 1; g.setLineDash(dash || []); g.strokeRect(Math.round(x0) + 0.5, Math.round(top) + 0.5, Math.max(1, Math.round(x1 - x0)), Math.round(hh)); g.setLineDash([]); }
  }

  /* ----- breakers (shared): swing H, the low before it L, a lower low sweeping L, then a close above H ----- */
  function breakers(c, len) {
    const { hi, lo } = pivots(c, len), out = [];
    const zone = (i) => { const a = c[Math.max(0, i - 1)], b = c[i]; return { top: Math.max(bodyTop(a), bodyTop(b)), bottom: Math.min(bodyBot(a), bodyBot(b)) }; };
    for (const dir of [1, -1]) {
      const A = dir > 0 ? hi : lo, B = dir > 0 ? lo : hi;
      for (const h of A) {
        let l = null;
        for (let k = B.length - 1; k >= 0; k--) if (B[k] < h) { l = B[k]; break; }
        if (l == null || h - l > 40) continue;
        let swept = -1, broke = -1, ext = null;
        for (let k = h + 1; k < Math.min(c.length, h + 80); k++) {
          if (swept < 0) {
            if (dir > 0 ? c[k].close > c[h].high : c[k].close < c[h].low) break;
            if (dir > 0 ? c[k].low < c[l].low : c[k].high > c[l].high) { swept = k; ext = dir > 0 ? c[k].low : c[k].high; }
            continue;
          }
          ext = dir > 0 ? Math.min(ext, c[k].low) : Math.max(ext, c[k].high);
          if (dir > 0 ? c[k].close > c[h].high : c[k].close < c[h].low) { broke = k; break; }
        }
        if (broke < 0) continue;
        const z = zone(h);
        // The fair value gap of the move that broke it (from the sweep to the break), overlapping the breaker.
        let uni = null, fvg = null;
        for (let j = swept + 2; j <= Math.min(c.length - 1, broke + 1); j++) {
          const gTop = dir > 0 ? c[j].low : c[j - 2].low, gBot = dir > 0 ? c[j - 2].high : c[j].high;
          if (gTop <= gBot) continue;
          if (!fvg) fvg = { top: gTop, bottom: gBot, at: j - 1, born: j };
          const top = Math.min(gTop, z.top), bottom = Math.max(gBot, z.bottom);
          if (top > bottom) { uni = { top, bottom, at: j - 1, born: j, fvg: { top: gTop, bottom: gBot } }; break; }
        }
        out.push({ dir, from: h, swept, broke, ext, top: z.top, bottom: z.bottom, fvg, uni });
      }
    }
    return out.sort((a, b) => a.broke - b.broke);
  }

  /* ===================== UNICORN ===================== */

  const UNI_DEFAULTS = () => ({ swingLen: 2, count: 3, rr: 2, maxWait: 120, spread: 0.3, panel: true, bull: "#089981", bear: "#f23645", uni: "#e91e63" });

  function uniCompute(c, sec, cfg) {
    if (!c || c.length < 40) return null;
    const n = c.length, spread = +cfg.spread || 0;
    const list = breakers(c, Math.max(1, cfg.swingLen | 0)).filter((b) => b.uni).map((b) => {
      const u = b.uni, d = b.dir, start = Math.max(b.broke, u.born) + 1;
      const s = { ...b, status: "wait", touchAt: null, res: null };
      // Entry: a limit at the near edge of the overlap; stop beyond the sweep's extreme; target `rr` R.
      const entry = d > 0 ? u.top : u.bottom, stop = d > 0 ? b.ext - spread : b.ext + spread, risk = (entry - stop) * d;
      s.entry = entry; s.stop = stop; s.risk = risk; s.target = entry + d * risk * (+cfg.rr || 2);
      if (!(risk > 0)) { s.status = "skip"; return s; }
      for (let k = start; k < n && k <= start + (+cfg.maxWait || 120); k++) {
        const x = c[k];
        if (d > 0 ? x.close < u.bottom - risk * 0.01 && x.low < stop : x.close > u.top && x.high > stop) { s.status = "broken"; s.endAt = k; break; }
        if (d > 0 ? x.high >= s.target : x.low <= s.target) { s.status = "missed"; s.endAt = k; break; }
        if (d > 0 ? x.low <= entry : x.high >= entry) { s.touchAt = k; break; }
      }
      if (s.touchAt == null) { if (s.status === "wait" && start + (+cfg.maxWait || 120) < n) { s.status = "expired"; s.endAt = start + cfg.maxWait; } return s; }
      s.status = "open";
      for (let k = s.touchAt; k < n; k++) {
        const x = c[k];
        if (d > 0 ? x.low <= stop : x.high >= stop) { s.status = "loss"; s.endAt = k; s.res = -1 - spread / risk; break; }
        if (k > s.touchAt && (d > 0 ? x.high >= s.target : x.low <= s.target)) { s.status = "win"; s.endAt = k; s.res = (+cfg.rr || 2) - spread / risk; break; }
      }
      return s;
    });
    const done = list.filter((s) => s.res != null);
    const w = done.filter((s) => s.res > 0).length, R = done.reduce((a, s) => a + s.res, 0);
    return { list, lastIdx: n - 1, stats: done.length ? `🦄 Unicorn trên chart: ${done.length} lệnh · ${w} thắng / ${done.length - w} thua · ${R >= 0 ? "+" : ""}${R.toFixed(1)}R (TP ${cfg.rr}R)` : "🦄 Unicorn: chưa có lệnh khớp trên chart" };
  }

  const UNI_STATUS = { wait: "chờ giá về", open: "đã khớp", win: "✓ thắng", loss: "✕ thua", broken: "hỏng", missed: "chạy mất", expired: "hết hạn", skip: "" };

  function uniDraw(g, o, cfg, X, Y, w, h, fmt) {
    if (!o) return;
    g.save(); font(g);
    o.list.slice(-Math.max(1, cfg.count | 0)).forEach((s) => {
      const c = s.dir > 0 ? cfg.bull : cfg.bear;
      const xb = X(s.from), xe = s.endAt != null ? X(s.endAt) : w, xu = X(s.uni.at);
      if (xb == null || xe == null || xe < 0) return;
      // The breaker (dashed), the fair value gap (thin), the unicorn overlap (filled).
      const yt = Y(s.top), yb = Y(s.bottom);
      if (yt != null && yb != null) box(g, Math.max(0, xb), xe, yt, yb, rgba(c, 0.06), rgba(c, 0.6), [4, 3]);
      const f = s.uni.fvg, ft = Y(f.top), fb = Y(f.bottom);
      if (xu != null && ft != null && fb != null) box(g, Math.max(0, xu), xe, ft, fb, rgba(c, 0.05), rgba(c, 0.35), [2, 2]);
      const ut = Y(s.uni.top), ub = Y(s.uni.bottom);
      if (xu != null && ut != null && ub != null) {
        box(g, Math.max(0, xu), xe, ut, ub, rgba(cfg.uni, 0.3), rgba(cfg.uni, 0.9));
        const res = s.res != null ? ` ${s.res >= 0 ? "+" : ""}${s.res.toFixed(1)}R` : "";
        pill(g, `🦄 ${s.dir > 0 ? "MUA" : "BÁN"} · ${UNI_STATUS[s.status]}${res}`, Math.max(2, xu), (s.dir > 0 ? Math.max(ut, ub) : Math.min(ut, ub)) + (s.dir > 0 ? 12 : -12), rgba(cfg.uni, 0.9));
      }
      // Entry / stop / target lines once there is a trade (or while it waits).
      if (["wait", "open", "win", "loss"].includes(s.status)) {
        const x0 = s.touchAt != null ? X(s.touchAt) : xu;
        [[s.stop, cfg.bear, `SL ${fmt(s.stop)}`], [s.target, cfg.bull, `TP ${fmt(s.target)}`]].forEach(([p, col, lab]) => {
          const y = Y(p);
          if (y == null || x0 == null) return;
          g.strokeStyle = rgba(col, 0.8); g.setLineDash([3, 3]); g.beginPath(); g.moveTo(Math.max(0, x0), y); g.lineTo(xe, y); g.stroke(); g.setLineDash([]);
          g.fillStyle = col; g.textAlign = "left"; g.fillText(lab, Math.max(2, x0) + 2, y + (p === s.stop ? (s.dir > 0 ? 8 : -8) : (s.dir > 0 ? -8 : 8)));
        });
      }
    });
    g.restore();
  }

  /* ===================== BB / OB / strong CISD ===================== */

  const BBOB_DEFAULTS = () => ({ ob: true, obStrongOnly: true, bb: true, cisd: true, swingLen: 3, dispAtr: 1.5, cisdAtr: 1.0, count: 3, bull: "#089981", bear: "#f23645", bbColor: "#9c6bff", cisdColor: "#ff9800" });

  function bbobCompute(c, sec, cfg) {
    if (!c || c.length < 40) return null;
    const n = c.length, rng = avgRange(c, 14), len = Math.max(2, cfg.swingLen | 0), piv = pivots(c, len);
    const obs = [];
    // Order blocks: a candle k whose next (or next-but-one) candle closes beyond the last confirmed swing
    // the other way, with a displacement; the block is the last opposite candle before that move.
    for (let k = len * 2 + 2; k < n; k++) {
      for (const d of [1, -1]) {
        const list = d > 0 ? piv.hi : piv.lo;
        // last swing confirmed before k
        let sw = null;
        for (let q = list.length - 1; q >= 0; q--) if (list[q] + len < k) { sw = list[q]; break; }
        if (sw == null || k - sw > 60) continue;
        const lvl = d > 0 ? c[sw].high : c[sw].low;
        if (!(d > 0 ? c[k].close > lvl && c[k - 1].close <= lvl : c[k].close < lvl && c[k - 1].close >= lvl)) continue;
        // the last opposite candle before the move that broke it
        let j = k;
        while (j > sw && (d > 0 ? c[j].close >= c[j].open : c[j].close <= c[j].open)) j--;
        if (j <= sw - 1 || j < 1) continue;
        const move = Math.abs(c[k].close - (d > 0 ? c[j].low : c[j].high)), disp = move >= cfg.dispAtr * rng[k] * 2;
        let gap = false;
        for (let q = j + 2; q <= Math.min(n - 1, k + 1); q++) if (d > 0 ? c[q].low > c[q - 2].high : c[q].high < c[q - 2].low) { gap = true; break; }
        const strong = disp && gap;
        if (cfg.obStrongOnly && !strong) continue;
        if (obs.some((o) => o.at === j && o.dir === d)) continue;
        obs.push({ dir: d, at: j, born: k, top: c[j].high, bottom: c[j].low, strong, broke: lvl });
      }
    }
    // Mitigation and failure: a close through the far side turns the order block into a breaker block.
    const bbs = [];
    obs.forEach((o) => {
      o.end = null;
      for (let k = o.born + 1; k < n; k++) {
        if (o.dir > 0 ? c[k].close < o.bottom : c[k].close > o.top) {
          o.end = k;
          const bb = { dir: -o.dir, at: o.at, born: k, top: o.top, bottom: o.bottom, end: null };
          for (let q = k + 1; q < n; q++) if (bb.dir > 0 ? c[q].close < bb.bottom : c[q].close > bb.top) { bb.end = q; break; }
          bbs.push(bb);
          break;
        }
        if (o.touch == null && (o.dir > 0 ? c[k].low <= o.top : c[k].high >= o.bottom)) o.touch = k;
      }
    });
    // Strong CISD: a close through the open of the run of opposite candles that took a swing, big body.
    const cisd = [];
    let up = null, dn = null;
    const swept = (i, d) => {
      const list = d < 0 ? piv.hi : piv.lo;
      for (let q = list.length - 1; q >= 0; q--) {
        const p = list[q];
        if (p + len > i) continue;
        if (i - p > 60) break;
        if (d < 0 ? c[i].high > c[p].high : c[i].low < c[p].low) return true;
      }
      return false;
    };
    for (let i = 1; i < n; i++) {
      const b = c[i];
      if (b.close > b.open) { if (up && up.end === i - 1) { up.end = i; up.ext = Math.max(up.ext, b.high); up.extAt = b.high >= up.ext ? i : up.extAt; } else up = { start: i, end: i, level: b.open, ext: b.high, extAt: i, used: false }; }
      else if (b.close < b.open) { if (dn && dn.end === i - 1) { dn.end = i; dn.ext = Math.min(dn.ext, b.low); dn.extAt = b.low <= dn.ext ? i : dn.extAt; } else dn = { start: i, end: i, level: b.open, ext: b.low, extAt: i, used: false }; }
      const body = Math.abs(b.close - b.open);
      if (up && !up.used && i > up.end && b.close < up.level) {
        up.used = true;
        if (body >= cfg.cisdAtr * rng[i] && swept(up.extAt, -1)) cisd.push({ dir: -1, at: i, from: up.start, level: up.level, ext: up.ext });
      }
      if (dn && !dn.used && i > dn.end && b.close > dn.level) {
        dn.used = true;
        if (body >= cfg.cisdAtr * rng[i] && swept(dn.extAt, 1)) cisd.push({ dir: 1, at: i, from: dn.start, level: dn.level, ext: dn.ext });
      }
    }
    return { obs, bbs, cisd, lastIdx: n - 1 };
  }

  function bbobDraw(g, o, cfg, X, Y, w, h, fmt) {
    if (!o) return;
    g.save(); font(g);
    const recent = (list) => list.slice(-Math.max(1, cfg.count | 0) * 2);
    if (cfg.ob) {
      // the live ones first, then the last few that ended
      const live = o.obs.filter((x) => x.end == null).slice(-cfg.count), past = o.obs.filter((x) => x.end != null).slice(-1);
      [...past, ...live].forEach((x) => {
        const c = x.dir > 0 ? cfg.bull : cfg.bear, x0 = X(x.at), x1 = x.end != null ? X(x.end) : w, y0 = Y(x.top), y1 = Y(x.bottom);
        if (x0 == null || x1 == null || y0 == null || y1 == null || x1 < 0) return;
        box(g, Math.max(0, x0), x1, y0, y1, rgba(c, x.end != null ? 0.05 : 0.14), rgba(c, 0.7));
        g.fillStyle = c; g.textAlign = "left"; g.fillText(`OB ${x.dir > 0 ? "tăng" : "giảm"}${x.strong ? " mạnh" : ""}`, Math.max(2, x0) + 3, Math.min(y0, y1) + 7);
      });
    }
    if (cfg.bb) {
      const live = o.bbs.filter((x) => x.end == null).slice(-cfg.count);
      live.forEach((x) => {
        const x0 = X(x.born), y0 = Y(x.top), y1 = Y(x.bottom);
        if (x0 == null || y0 == null || y1 == null) return;
        box(g, Math.max(0, x0), w, y0, y1, rgba(cfg.bbColor, 0.12), rgba(cfg.bbColor, 0.85), [5, 3]);
        g.fillStyle = cfg.bbColor; g.textAlign = "left"; g.fillText(`BB ${x.dir > 0 ? "tăng (hỗ trợ)" : "giảm (kháng cự)"}`, Math.max(2, x0) + 3, Math.min(y0, y1) + 7);
      });
    }
    if (cfg.cisd) {
      recent(o.cisd).slice(-cfg.count).forEach((x) => {
        const x0 = X(x.from), x1 = X(x.at), y = Y(x.level);
        if (x0 == null || x1 == null || y == null || x1 < 0) return;
        g.strokeStyle = cfg.cisdColor; g.lineWidth = 2; g.beginPath(); g.moveTo(Math.max(0, x0), y); g.lineTo(x1 + 6, y); g.stroke();
        pill(g, `CISD ${x.dir > 0 ? "tăng" : "giảm"} mạnh`, x1 + 8, y, rgba(cfg.cisdColor, 0.9));
      });
    }
    g.restore();
  }

  window.UNICORN = { defaults: UNI_DEFAULTS, merge: (s) => merge(UNI_DEFAULTS(), s), compute: uniCompute, draw: uniDraw, breakers };
  window.BBOB = { defaults: BBOB_DEFAULTS, merge: (s) => merge(BBOB_DEFAULTS(), s), compute: bbobCompute, draw: bbobDraw };
})();
