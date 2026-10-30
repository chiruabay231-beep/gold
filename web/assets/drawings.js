/* Drawing tools on the web chart, like the app's (TradingView-style): trend
 * lines, rays, horizontal / vertical lines, Fibonacci, patterns, long / short
 * positions, price range, volume profiles, shapes and text. Points are kept as
 * {t: UTC seconds, p: price} so drawings stay put across timeframes; they are
 * saved per symbol in this browser and painted inside the chart's render pass.
 * Each drawing carries its own look (line, fill, text, Fibonacci levels, the
 * timeframes it shows on), edited in the settings panel like TradingView's. */
(() => {
  "use strict";

  const COLORS = ["#2962ff", "#f23645", "#089981", "#ff9800", "#9c27b0", "#787b86", "#e8ecf3"];
  const TOOLS = {
    trendLine: { name: "Đường xu hướng", n: 2 },
    trendRay: { name: "Tia xu hướng", n: 2 },
    horizontalLine: { name: "Đường nằm ngang", n: 1 },
    horizontalRay: { name: "Tia nằm ngang", n: 1 },
    verticalLine: { name: "Đường thẳng đứng", n: 1 },
    fibRetracement: { name: "Fib thoái lui (OTE)", n: 2 },
    fibExtension: { name: "Fib mở rộng theo xu hướng", n: 3 },
    elliottImpulse: { name: "Sóng đẩy Elliott (1·2·3·4·5)", n: 6, labels: ["0", "1", "2", "3", "4", "5"] },
    elliottCorrection: { name: "Sóng điều chỉnh Elliott (A·B·C)", n: 4, labels: ["0", "A", "B", "C"] },
    headShoulders: { name: "Đầu và vai", n: 7, labels: ["", "Vai trái", "", "Đầu", "", "Vai phải", ""] },
    trianglePattern: { name: "Mô hình tam giác", n: 4, labels: ["A", "B", "C", "D"] },
    longPosition: { name: "Vị thế Mua", n: 2 },
    shortPosition: { name: "Vị thế Bán", n: 2 },
    fixedRangeVolume: { name: "Khối lượng phạm vi cố định", n: 2 },
    anchoredVolume: { name: "Khối lượng được neo", n: 1 },
    priceRange: { name: "Đo giá", n: 2 },
    brush: { name: "Cọ vẽ", n: -1 },
    rectangle: { name: "Hình chữ nhật", n: 2 },
    arrow: { name: "Mũi tên", n: 2 },
    ellipse: { name: "Hình elip", n: 2 },
    path: { name: "Đường dẫn", n: 12 },
    arrowMarker: { name: "Mũi tên đánh dấu", n: 2 },
    text: { name: "Văn bản", n: 1 },
  };
  const CATEGORIES = [
    ["Công cụ xu hướng", ["trendLine", "trendRay", "horizontalLine", "horizontalRay", "verticalLine"]],
    ["Gann và Fibonacci", ["fibRetracement", "fibExtension"]],
    ["Mô hình", ["elliottImpulse", "elliottCorrection", "headShoulders", "trianglePattern"]],
    ["Dự đoán và đo lường", ["longPosition", "shortPosition", "fixedRangeVolume", "anchoredVolume", "priceRange"]],
    ["Hình học", ["brush", "rectangle", "arrow", "ellipse", "path", "arrowMarker"]],
    ["Lưu ý", ["text"]],
  ];
  // Fibonacci levels: ICT's OTE (0.62–0.79) and targets below 0, like the app; the rest can be turned on.
  const FIB_LEVELS = [
    [1, true, "#787b86"], [0.886, false, "#787b86"], [0.79, true, "#f23645"], [0.705, true, "#089981"], [0.62, true, "#ff9800"],
    [0.5, true, "#4caf50"], [0.382, false, "#00bcd4"], [0.236, false, "#f23645"], [0, true, "#787b86"],
    [-0.27, true, "#2962ff"], [-0.62, true, "#9c27b0"], [-1, true, "#e91e63"], [-1.618, false, "#f23645"], [-2.618, false, "#9c27b0"],
  ];
  const FIB_EXT_LEVELS = [
    [0, true, "#787b86"], [0.382, false, "#f23645"], [0.5, false, "#4caf50"], [0.618, true, "#089981"], [0.786, false, "#00bcd4"],
    [1, true, "#787b86"], [1.272, true, "#2962ff"], [1.618, true, "#f23645"], [2, true, "#9c27b0"], [2.618, true, "#e91e63"], [3.618, false, "#ff9800"],
  ];
  const DASH = { solid: [], dashed: [6, 4], dotted: [1.5, 3] };
  // Line tools that straighten to level when let go nearly level.
  const FLAT_TOOLS = ["trendLine", "trendRay", "arrow"];
  const TFS = ["5s", "10s", "15s", "30s", "1m", "5m", "15m", "30m", "1h", "4h", "1d"];

  const alpha = (hex, a) => (hex || "#787b86").slice(0, 7) + Math.round(Math.max(0, Math.min(1, a)) * 255).toString(16).padStart(2, "0");
  const isPos = (t) => t === "longPosition" || t === "shortPosition";
  const hasFill = (t) => ["rectangle", "ellipse", "headShoulders", "trianglePattern", "fibRetracement", "fibExtension", "longPosition", "shortPosition", "priceRange"].includes(t);

  class Drawings {
    /** host: { chart, series, bars(), sec(), interval(), digits(), symbol(), store, magnet(), onChange(), onEdit(d, isNew) } */
    constructor(host) {
      this.host = host;
      this.list = [];
      this.tool = null;
      this.pending = null; // the drawing being placed
      this.selected = null;
      this.gesture = null;
      // Toolbar switches: keep the tool after a drawing, lock all, hide all.
      this.keepTool = host.store.get("aurum.keepTool") === "1";
      this.lockAll = host.store.get("aurum.lockAll") === "1";
      this.hidden = false;
      this.styles = {};
      try { this.styles = JSON.parse(host.store.get("aurum.drawStyles") || "{}"); } catch { /* none */ }
      const self = this;
      this.primitive = {
        attached(p) { self.requestUpdate = p.requestUpdate; },
        detached() {},
        updateAllViews() {},
        paneViews() {
          return [{
            zOrder: () => "top",
            // Painted on the device pixels (scaled back to CSS pixels) so lines snap to whole pixels: sharp.
            renderer: () => ({ draw: (target) => target.useBitmapCoordinateSpace(({ context, bitmapSize, horizontalPixelRatio: hr, verticalPixelRatio: vr }) => {
              self.dpr = hr || 1;
              context.save();
              context.scale(hr, vr);
              self.paint(context, bitmapSize.width / hr, bitmapSize.height / vr);
              context.restore();
            }) }),
          }];
        },
      };
      host.series.attachPrimitive(this.primitive);
    }

    static get tools() { return TOOLS; }
    static get categories() { return CATEGORIES; }
    static get colors() { return COLORS; }
    static get timeframes() { return TFS; }
    static isPosition(t) { return isPos(t); }
    static hasFill(t) { return hasFill(t); }

    update() { if (this.requestUpdate) this.requestUpdate(); }

    /* ----- storage ----- */

    key() { return "aurum.draw." + (this.host.symbol() || "XAUUSD"); }
    load() {
      try { this.list = JSON.parse(this.host.store.get(this.key()) || "[]").map((d) => this.upgrade(d)); } catch { this.list = []; }
      this.selected = null; this.pending = null;
      this.update();
      this.host.onChange();
    }
    save() {
      try { this.host.store.set(this.key(), JSON.stringify(this.list)); } catch { /* full */ }
      this.host.onChange();
    }

    /** Drawings saved by an earlier version get the options added since. */
    upgrade(d) {
      const base = this.defaults(d.tool);
      for (const k of Object.keys(base)) if (d[k] === undefined) d[k] = base[k];
      if (isPos(d.tool) && d.pts.length === 2) d.pts.push({ t: d.pts[1].t, p: this.target(d) });
      return d;
    }

    /* ----- coordinates: time ↔ logical index ↔ pixels ----- */

    timeToLogical(t) {
      const b = this.host.bars(), n = b.length, sec = this.host.sec();
      if (!n) return null;
      if (t <= b[0].time) return (t - b[0].time) / sec;
      if (t >= b[n - 1].time) return n - 1 + (t - b[n - 1].time) / sec;
      let lo = 0, hi = n - 1;
      while (hi - lo > 1) { const m = (lo + hi) >> 1; if (b[m].time <= t) lo = m; else hi = m; }
      return lo + (t - b[lo].time) / (b[hi].time - b[lo].time);
    }
    logicalToTime(l) {
      const b = this.host.bars(), n = b.length, sec = this.host.sec();
      if (!n) return null;
      if (l <= 0) return b[0].time + l * sec;
      if (l >= n - 1) return b[n - 1].time + (l - (n - 1)) * sec;
      const i = Math.floor(l);
      return b[i].time + (l - i) * (b[i + 1].time - b[i].time);
    }
    x(t) {
      const l = this.timeToLogical(t);
      if (l == null) return null;
      const ts = this.host.chart.timeScale();
      const i = Math.floor(l), a = ts.logicalToCoordinate(i), b = ts.logicalToCoordinate(i + 1);
      if (a == null || b == null) return null;
      return a + (b - a) * (l - i);
    }
    y(p) { return this.host.series.priceToCoordinate(p); }
    point(x, y, snap) {
      const ts = this.host.chart.timeScale();
      let l = ts.coordinateToLogical(x);
      if (l == null) return null;
      const a = ts.logicalToCoordinate(l), b = ts.logicalToCoordinate(l + 1);
      if (!snap && a != null && b != null && b !== a) l = l + (x - a) / (b - a);
      let p = this.host.series.coordinateToPrice(y);
      if (p == null) return null;
      // Magnet: snap to the nearest open/high/low/close of the bar under the finger.
      if (snap) {
        const bar = this.host.bars()[Math.round(l)];
        if (bar) {
          const near = [bar.open, bar.high, bar.low, bar.close].map((v) => [v, Math.abs(this.y(v) - y)]).sort((m, k) => m[1] - k[1])[0];
          if (near[1] < 18) p = near[0];
        }
      }
      return { t: this.logicalToTime(l), p: +p.toFixed(this.host.digits()) };
    }

    /* ----- creating ----- */

    /** Layers of other charts that share the picked tool (two-chart layouts). */
    link(peers) { this.peers = peers.filter((p) => p !== this); }

    setTool(tool, fromPeer) {
      this.tool = tool;
      this.pending = null;
      this.selected = null;
      this.update();
      if (!fromPeer) (this.peers || []).forEach((p) => p.setTool(tool, true));
      this.host.onChange();
    }

    /** The look of a new drawing of `tool`: the user's saved default over the built-in one. */
    /** A tool's look for a new drawing: the app's own, under the look last given to that tool (`own` false:
     *  the app's own only). */
    defaults(tool, own = true) {
      const color = tool === "longPosition" ? COLORS[2] : tool === "shortPosition" ? COLORS[1] : tool === "text" ? "#ff9800" : COLORS[0];
      const base = {
        color, width: tool === "brush" ? 2 : 1, style: "solid", rr: 2, locked: false,
        // Line ends / box extension: "none" | "left" | "right" | "both".
        extend: "none",
        mid: false, midColor: "#787b86", midStyle: "dashed",
        fill: hasFill(tool), fillColor: color, fillOpacity: tool === "headShoulders" || tool === "trianglePattern" ? 10 : 15,
        text: "", textColor: tool === "text" ? "#ff9800" : color, fontSize: tool === "text" ? 18 : 12, bold: false, italic: false,
        textBg: false, textBgColor: "#2a3449", textBorder: false, textBorderColor: "#787b86", wrap: false,
        textV: "top", textH: "center",
        targetColor: "#089981", stopColor: "#f23645",
        hideOn: {},
      };
      if (tool === "fibRetracement" || tool === "fibExtension") {
        base.fib = {
          levels: (tool === "fibExtension" ? FIB_EXT_LEVELS : FIB_LEVELS).map(([v, on, c]) => ({ v, on, color: c })),
          oneColorOn: false, oneColor: "#2962ff", bg: true, bgOpacity: 10, reverse: false, prices: true, values: true,
          labelSide: tool === "fibExtension" ? "right" : "left", fontSize: 11, trend: true, extendLeft: false, extendRight: false,
        };
      }
      const saved = own ? this.styles[tool] : null;
      return saved ? Object.assign(base, JSON.parse(JSON.stringify(saved))) : base;
    }

    newDrawing(tool) {
      return Object.assign({ id: Math.random().toString(36).slice(2, 10), tool, pts: [] }, this.defaults(tool));
    }

    /** The look just given to a drawing becomes its tool's look for the next ones (like TradingView),
     * with no need to save it by hand. Position tools keep their own R:R per drawing. */
    remember(d) {
      if (!d || !d.tool) return;
      this.saveAsDefault(d);
      (this.peers || []).forEach((p) => { p.styles = this.styles; });
    }

    /** Remembers the look of `d` as the default for its tool (the "Bản mẫu" menu). */
    saveAsDefault(d) {
      const keep = JSON.parse(JSON.stringify(d));
      ["id", "tool", "pts", "text", "locked", "_box"].forEach((k) => delete keep[k]);
      this.styles[d.tool] = keep;
      try { this.host.store.set("aurum.drawStyles", JSON.stringify(this.styles)); } catch { /* full */ }
    }
    /* Named templates per tool ("Lưu bản mẫu vẽ dưới dạng…"), like TradingView. */
    templates(tool) {
      try { return (JSON.parse(this.host.store.get("aurum.drawTpl") || "{}")[tool]) || {}; } catch { return {}; }
    }
    saveTemplate(d, name) {
      let all = {};
      try { all = JSON.parse(this.host.store.get("aurum.drawTpl") || "{}"); } catch { /* new */ }
      const keep = JSON.parse(JSON.stringify(d));
      ["id", "tool", "pts", "text", "locked", "_box"].forEach((k) => delete keep[k]);
      (all[d.tool] = all[d.tool] || {})[name] = keep;
      try { this.host.store.set("aurum.drawTpl", JSON.stringify(all)); } catch { /* full */ }
    }
    deleteTemplate(tool, name) {
      let all = {};
      try { all = JSON.parse(this.host.store.get("aurum.drawTpl") || "{}"); } catch { return; }
      if (all[tool]) delete all[tool][name];
      try { this.host.store.set("aurum.drawTpl", JSON.stringify(all)); } catch { /* full */ }
    }
    /** Applies a named template (or, `name` null, the app's own look for the tool) to `d`; that look is then
     *  the tool's look for the next drawings too, as any look given by hand is. */
    applyTemplate(d, name) {
      const style = name ? this.templates(d.tool)[name] : this.defaults(d.tool, false);
      if (!style) return;
      const keep = { id: d.id, tool: d.tool, pts: d.pts, text: d.text, locked: d.locked };
      Object.keys(d).forEach((k) => delete d[k]);
      Object.assign(d, this.defaults(d.tool, false), JSON.parse(JSON.stringify(style)), keep);
      this.changed(d);
      this.remember(d);
    }

    resetDefault(tool) {
      delete this.styles[tool];
      try { this.host.store.set("aurum.drawStyles", JSON.stringify(this.styles)); } catch { /* full */ }
    }

    finish() {
      const d = this.pending;
      this.pending = null;
      this.tool = d && this.keepTool ? d.tool : null;
      if (!d) return;
      // Drawn with two taps as well as with a drag.
      this.flatten(d, d.pts.length - 1, this.raw);
      this.raw = null;
      if (isPos(d.tool)) { if (d.pts.length < 3) d.pts.push({ t: d.pts[1].t, p: this.target(d) }); this.fixPosition(d, 1); }
      this.list.push(d);
      (this.peers || []).forEach((p) => { if (!p.pending) { p.tool = this.tool; p.update(); } });
      this.selected = this.tool ? null : d.id;
      this.hidden = false;
      this.save();
      this.update();
      // A new text opens its editor straight away, like TradingView.
      if (d.tool === "text" && this.host.onEdit) { this.selected = d.id; this.host.onEdit(d, true); }
    }

    /**
     * Long: stop below and target above the entry; short the other way. A handle
     * cannot drag a position inside out. The stop and target share their right edge.
     */
    fixPosition(d, moved) {
      const [e, s, t] = d.pts;
      // The closest a stop or target may come to the entry (one hundredth of a percent, at least a tick).
      const tick = Math.max(Math.pow(10, -this.host.digits()), Math.abs(e.p) * 0.0001);
      const long = d.tool === "longPosition";
      if (moved === 0 && t) {
        // The entry stays between the stop and the target.
        e.p = long ? Math.min(Math.max(e.p, s.p + tick), t.p - tick) : Math.max(Math.min(e.p, s.p - tick), t.p + tick);
      }
      s.p = long ? Math.min(s.p, e.p - tick) : Math.max(s.p, e.p + tick);
      if (t) {
        t.p = long ? Math.max(t.p, e.p + tick) : Math.min(t.p, e.p - tick);
        if (moved === 2) s.t = t.t; else t.t = s.t;
        d.rr = Math.round(Math.abs(t.p - e.p) / Math.abs(e.p - s.p) * 100) / 100;
      }
      [e, s, t].forEach((p) => { if (p) p.p = +p.p.toFixed(this.host.digits()); });
    }

    /* ----- pointer: returns true when the drawing layer takes the gesture ----- */

    down(x, y, e) {
      const touch = e.pointerType !== "mouse";
      if (this.tool) {
        const spec = TOOLS[this.tool];
        const pt = this.point(x, y, e.shiftKey === false && this.host.magnet());
        if (!pt) return true;
        if (!this.pending) {
          this.pending = this.newDrawing(this.tool);
          this.pending.pts = [pt];
          if (spec.n === 1) { this.finish(); return true; }
          this.pending.pts.push(Object.assign({}, pt));
          this.gesture = { kind: "create", x, y, moved: false };
          this.raw = [[x, y], [x, y]];
        } else {
          // Next click of a multi-point tool.
          const pts = this.pending.pts;
          pts[pts.length - 1] = pt;
          if (this.raw) this.raw[1] = [x, y];
          const last = pts[pts.length - 2];
          const closing = this.tool === "path" && last && Math.hypot(this.x(last.t) - x, this.y(last.p) - y) < 10;
          if (closing || pts.length >= spec.n) { if (closing) pts.pop(); this.finish(); return true; }
          pts.push(Object.assign({}, pt));
          this.gesture = { kind: "create", x, y, moved: false };
        }
        this.update();
        return true;
      }
      const hit = this.hitTest(x, y, touch ? 14 : 8);
      if (!hit) {
        if (this.selected) { this.selected = null; this.update(); this.host.onChange(); return "deselect"; }
        return false;
      }
      this.selected = hit.d.id;
      (this.peers || []).forEach((p) => { if (p.selected) { p.selected = null; p.update(); } });
      if (!hit.d.locked && !this.lockAll) {
        this.gesture = { kind: hit.handle != null ? "handle" : "move", d: hit.d, handle: hit.handle, x, y,
          start: hit.d.pts.map((p) => Object.assign({}, p)), anchor: this.point(x, y, false), moved: false };
      }
      this.update();
      this.host.onChange();
      return true;
    }

    move(x, y) {
      const g = this.gesture;
      if (!g) {
        if (this.pending && this.pending.pts.length) {
          const pt = this.point(x, y, this.host.magnet());
          if (pt) { this.pending.pts[this.pending.pts.length - 1] = pt; this.constrain(this.pending, this.pending.pts.length - 1); this.update(); }
          if (this.raw) this.raw[1] = [x, y];
        }
        return false;
      }
      g.lastX = x; g.lastY = y;
      if (Math.hypot(x - g.x, y - g.y) > 4) g.moved = true;
      if (g.kind === "create") {
        if (this.raw) this.raw[1] = [x, y];
        const pt = this.point(x, y, this.host.magnet());
        if (!pt) return true;
        const d = this.pending;
        if (d.tool === "brush") { if (g.moved) d.pts.push(pt); } else { d.pts[d.pts.length - 1] = pt; this.constrain(d, d.pts.length - 1); }
      } else if (g.kind === "handle") {
        const pt = this.point(x, y, this.host.magnet());
        if (pt) { g.d.pts[g.handle] = pt; this.constrain(g.d, g.handle); }
      } else if (g.kind === "move" && g.anchor) {
        const now = this.point(x, y, false);
        if (!now) return true;
        const dl = this.timeToLogical(now.t) - this.timeToLogical(g.anchor.t), dp = now.p - g.anchor.p;
        g.d.pts = g.start.map((p) => ({ t: this.logicalToTime(this.timeToLogical(p.t) + dl), p: +(p.p + dp).toFixed(this.host.digits()) }));
      }
      this.update();
      return true;
    }

    constrain(d, index) {
      if (isPos(d.tool) && d.pts.length >= 2) this.fixPosition(d, index);
      if ((d.tool === "horizontalLine" || d.tool === "horizontalRay") && d.pts.length) d.pts[0].p = +d.pts[0].p.toFixed(this.host.digits());
    }

    /** A trend line let go almost level (6° or less on screen, so a sideways drag that wandered a little)
     * becomes exactly level: measuring between two candles. A line drawn along a trend, steeper than that,
     * is left as drawn. `moved` is the point dragged (the other end keeps its price). */
    flatten(d, moved, raw) {
      if (!d || !FLAT_TOOLS.includes(d.tool) || d.pts.length < 2) return;
      const [a, b] = d.pts, xa = this.x(a.t), xb = this.x(b.t), ya = this.y(a.p), yb = this.y(b.p);
      if ([xa, xb, ya, yb].some((v) => v == null)) return;
      if (ya === yb) return;
      // Judged by where the finger went (`raw`: the fixed end and the finger), not the points the magnet
      // pulled onto candle highs and lows, which tilt a sideways drag.
      const [p0, p1] = raw || [[xa, ya], [xb, yb]];
      const dx = Math.abs(p1[0] - p0[0]), dy = Math.max(Math.abs(p1[1] - p0[1]), 0.0001);
      if (dy > 0 && dx >= 20 && dy <= dx * Math.tan(6 * Math.PI / 180)) {
        if (moved === 0) a.p = b.p; else b.p = a.p;
      }
    }

    up() {
      const g = this.gesture;
      this.gesture = null;
      if (!g) return false;
      if (g.kind === "handle" && g.moved && g.d.pts.length === 2 && g.lastX != null) {
        // The other end stays put; the finger is where this one went.
        const o = g.d.pts[1 - g.handle];
        this.flatten(g.d, g.handle, [[this.x(o.t), this.y(o.p)], [g.lastX, g.lastY]]);
      }
      if (g.kind === "create") {
        const spec = TOOLS[this.pending.tool];
        // Dragged out a two-point tool (or a brush stroke): done. A tap waits for the next tap.
        if (spec.n === -1 || (g.moved && spec.n === 2)) this.finish();
        else if (g.moved && this.pending.pts.length >= spec.n) this.finish();
        else if (g.moved) { this.pending.pts.push(Object.assign({}, this.pending.pts[this.pending.pts.length - 1])); }
      } else if (g.moved) {
        this.save();
      }
      this.update();
      return true;
    }

    cancel(fromPeer) {
      this.pending = null; this.tool = null; this.gesture = null;
      this.update();
      if (!fromPeer) (this.peers || []).forEach((p) => p.cancel(true));
      this.host.onChange();
    }

    get current() { return this.list.find((d) => d.id === this.selected) || null; }

    /** The drawing under the mouse (labels of positions light up). */
    hover(id) {
      if (id === this.hoverId) return;
      this.hoverId = id;
      this.update();
    }

    remove(id) {
      this.list = this.list.filter((d) => d.id !== id);
      if (this.selected === id) this.selected = null;
      this.save(); this.update();
    }
    clear() { this.list = []; this.selected = null; this.save(); this.update(); }

    /** Changes the selected drawing (from the floating bar or the settings panel). */
    restyle(changes) {
      const d = this.current;
      if (!d) return;
      Object.assign(d, changes);
      if (changes.color && hasFill(d.tool) && !changes.fillColor) d.fillColor = changes.color;
      this.changed(d);
      this.remember(d);
    }
    changed(d) {
      if (isPos(d.tool) && d.pts.length >= 3) this.fixPosition(d, 1);
      this.save(); this.update();
    }

    shownNow(d) {
      const tf = this.host.interval ? this.host.interval() : null;
      return !(tf && d.hideOn && d.hideOn[tf]);
    }

    /* ----- hit testing ----- */

    hitTest(x, y, tol) {
      if (this.hidden) return null;
      for (let k = this.list.length - 1; k >= 0; k--) {
        const d = this.list[k];
        if (!this.shownNow(d)) continue;
        const pts = d.pts.map((p) => [this.x(p.t), this.y(p.p)]);
        if (pts.some(([a, b]) => a == null || b == null)) continue;
        if (d.id === this.selected) {
          const h = this.handles(d, pts).findIndex(([a, b]) => Math.hypot(a - x, b - y) <= tol);
          if (h >= 0) return { d, handle: h };
        }
        if (this.near(d, pts, x, y, tol)) return { d, handle: null };
      }
      return null;
    }

    handles(d, pts) {
      if (d.tool === "brush") return [];
      if (isPos(d.tool) && pts.length >= 3) return [pts[0], pts[1], [pts[1][0], pts[2][1]]];
      return pts;
    }

    near(d, pts, x, y, tol) {
      const seg = (a, b) => {
        const dx = b[0] - a[0], dy = b[1] - a[1], len = dx * dx + dy * dy;
        const t = len ? Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / len)) : 0;
        return Math.hypot(a[0] + t * dx - x, a[1] + t * dy - y) <= tol;
      };
      const inBox = (a, b) => x >= Math.min(a[0], b[0]) - tol && x <= Math.max(a[0], b[0]) + tol && y >= Math.min(a[1], b[1]) - tol && y <= Math.max(a[1], b[1]) + tol;
      const [p0, p1] = pts;
      switch (d.tool) {
        case "horizontalLine": return Math.abs(y - p0[1]) <= tol;
        case "horizontalRay": return Math.abs(y - p0[1]) <= tol && x >= p0[0] - tol;
        case "verticalLine": return Math.abs(x - p0[0]) <= tol;
        case "text": { const b = d._box; return b ? x >= b.x - 4 && x <= b.x + b.w + 4 && y >= b.y - 4 && y <= b.y + b.h + 4 : Math.hypot(x - p0[0], y - p0[1]) < 14; }
        case "anchoredVolume": return Math.abs(x - p0[0]) <= tol || (x >= p0[0] && Math.abs(y - p0[1]) < 40);
        case "trendRay": return seg(p0, [p0[0] + (p1[0] - p0[0]) * 1000, p0[1] + (p1[1] - p0[1]) * 1000]);
        case "rectangle": case "ellipse": {
          // The outline only (inside too when filled), so the chart can still be dragged from an empty box.
          if (d.fill && inBox(p0, p1) && d.tool === "rectangle") return true;
          const box = [[p0[0], p0[1]], [p1[0], p0[1]], [p1[0], p1[1]], [p0[0], p1[1]], [p0[0], p0[1]]];
          for (let i = 1; i < box.length; i++) if (seg(box[i - 1], box[i])) return true;
          return false;
        }
        case "priceRange": case "fixedRangeVolume": case "fibRetracement": return inBox(p0, p1);
        case "longPosition": case "shortPosition": {
          const right = Math.max(p0[0], p1[0], p0[0] + 40);
          const yT = pts[2] ? pts[2][1] : this.y(this.target(d));
          return inBox(p0, [right, p1[1]]) || inBox(p0, [right, yT]);
        }
        default:
          for (let i = 1; i < pts.length; i++) if (seg(pts[i - 1], pts[i])) return true;
          return pts.length === 1 && Math.hypot(p0[0] - x, p0[1] - y) <= tol;
      }
    }

    target(d) {
      if (d.pts[2]) return d.pts[2].p;
      const [a, b] = d.pts;
      return a.p + (a.p - b.p) * (d.rr || 2);
    }

    /* ----- painting ----- */

    paint(g, w, h) {
      const shown = this.hidden ? [] : this.list.filter((d) => this.shownNow(d));
      const all = this.pending ? shown.concat([this.pending]) : shown;
      if (!all.length) return;
      g.save();
      all.forEach((d) => {
        const pts = d.pts.map((p) => [this.x(p.t), this.y(p.p)]);
        if (pts.some(([a, b]) => a == null || b == null)) return;
        g.save();
        try { this.paintOne(g, d, pts, w, h); } catch { /* skip a broken drawing */ }
        g.restore();
        if (d.id === this.selected || d === this.pending) {
          // Handles: a soft halo, then a ring in the drawing's colour on the chart's background.
          const light = document.documentElement.dataset.theme === "light";
          this.handles(d, pts).forEach(([a, b]) => {
            g.setLineDash([]);
            g.fillStyle = alpha(d.color, 0.18);
            g.beginPath(); g.arc(a, b, 8, 0, Math.PI * 2); g.fill();
            g.fillStyle = light ? "#ffffff" : "#0b0f17"; g.strokeStyle = d.color; g.lineWidth = 2;
            g.beginPath(); g.arc(a, b, 4.5, 0, Math.PI * 2); g.fill(); g.stroke();
          });
        }
      });
      g.restore();
    }

    font(d, size) {
      return `${d.italic ? "italic " : ""}${d.bold ? "700 " : "500 "}${size || d.fontSize || 12}px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif`;
    }

    /** Lines of `text` that fit `max` pixels when wrapping. */
    lines(g, text, max) {
      const out = [];
      String(text).split("\n").forEach((para) => {
        if (!max) { out.push(para); return; }
        let line = "";
        para.split(" ").forEach((word) => {
          const next = line ? line + " " + word : word;
          if (line && g.measureText(next).width > max) { out.push(line); line = word; } else line = next;
        });
        out.push(line);
      });
      return out;
    }

    /** A text block at (x, y) with the drawing's font, background and border; returns its box. */
    textBlock(g, d, text, x, y, align = "left", base = "top", maxWidth = 0) {
      if (!text) return null;
      g.save();
      g.setLineDash([]);
      g.font = this.font(d);
      const size = d.fontSize || 12, lh = Math.round(size * 1.3), pad = d.textBg || d.textBorder ? 6 : 0;
      const rows = this.lines(g, text, d.wrap ? Math.max(60, maxWidth || 240) : 0);
      const tw = Math.max(...rows.map((r) => g.measureText(r).width)), th = rows.length * lh;
      const bx = align === "center" ? x - tw / 2 - pad : align === "right" ? x - tw - pad * 2 : x;
      const by = base === "middle" ? y - th / 2 - pad : base === "bottom" ? y - th - pad * 2 : y;
      if (d.textBg) { g.fillStyle = d.textBgColor; g.fillRect(bx, by, tw + pad * 2, th + pad * 2); }
      if (d.textBorder) { g.strokeStyle = d.textBorderColor; g.lineWidth = 1; g.strokeRect(bx + 0.5, by + 0.5, tw + pad * 2, th + pad * 2); }
      g.fillStyle = d.textColor || d.color; g.textBaseline = "top"; g.textAlign = "left";
      rows.forEach((r, i) => g.fillText(r, bx + pad, by + pad + i * lh + (lh - size) / 2));
      g.restore();
      return { x: bx, y: by, w: tw + pad * 2, h: th + pad * 2 };
    }

    /** A line width of at least one device pixel, in whole device pixels (a 0.5px line on a normal
     * screen was a blurred half pixel). */
    lw(width) {
      const dpr = this.dpr || 1;
      return Math.max(1, Math.round((width || 1) * dpr)) / dpr;
    }

    paintOne(g, d, pts, w, h) {
      const dg = this.host.digits();
      const color = d.color;
      const width = this.lw(d.width);
      g.strokeStyle = color; g.fillStyle = color; g.lineWidth = width; g.setLineDash(DASH[d.style] || []);
      g.lineCap = "butt"; g.lineJoin = "round";
      g.font = "11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif"; g.textBaseline = "bottom"; g.textAlign = "left";
      // Points on the device pixel grid (centred on a pixel for an odd number of pixels): sharp lines.
      const dpr = this.dpr || 1, odd = Math.round(width * dpr) % 2 === 1;
      const px = (v) => (Math.round(v * dpr - (odd ? 0.5 : 0)) + (odd ? 0.5 : 0)) / dpr;
      const lineTo = (pp) => { g.beginPath(); g.moveTo(px(pp[0][0]), px(pp[0][1])); pp.slice(1).forEach((p) => g.lineTo(px(p[0]), px(p[1]))); g.stroke(); };
      // A label: rounded, a hair of shadow, the text centred in it. (x, y) = its bottom-left as before.
      const tag = (text, x, y, bg, fg = "#fff", align = "left") => {
        g.save(); g.setLineDash([]); g.font = "600 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
        const tw = g.measureText(text).width + 14, th = 19;
        const left = align === "right" ? x - tw : align === "center" ? x - tw / 2 : x, top = y - th + 1;
        g.shadowColor = "rgba(0, 0, 0, 0.28)"; g.shadowBlur = 6; g.shadowOffsetY = 1;
        g.fillStyle = bg; g.beginPath(); g.roundRect(left, top, tw, th, 5); g.fill();
        g.shadowColor = "transparent";
        g.strokeStyle = "rgba(255, 255, 255, 0.14)"; g.lineWidth = 1; g.stroke();
        g.fillStyle = fg; g.textAlign = "left"; g.textBaseline = "middle"; g.fillText(text, left + 7, top + th / 2 + 0.5);
        g.restore();
      };
      const arrowHead = (a, b, size = 10) => {
        const ang = Math.atan2(b[1] - a[1], b[0] - a[0]);
        g.save(); g.setLineDash([]); g.beginPath();
        g.moveTo(b[0], b[1]);
        g.lineTo(b[0] - size * Math.cos(ang - 0.45), b[1] - size * Math.sin(ang - 0.45));
        g.lineTo(b[0] - size * Math.cos(ang + 0.45), b[1] - size * Math.sin(ang + 0.45));
        g.closePath(); g.fill(); g.restore();
      };
      // The drawing's own text, placed by its "Văn bản" options.
      const caption = (l, t, r, b) => {
        if (!d.text || d.tool === "text") return;
        const x = d.textH === "left" ? l + 4 : d.textH === "right" ? r - 4 : (l + r) / 2;
        const y = d.textV === "bottom" ? b + 4 : d.textV === "middle" ? (t + b) / 2 : t - 4;
        this.textBlock(g, d, d.text, x, y, d.textH === "left" ? "left" : d.textH === "right" ? "right" : "center", d.textV === "bottom" ? "top" : d.textV === "middle" ? "middle" : "bottom", Math.abs(r - l));
      };
      const [p0, p1] = pts;
      switch (d.tool) {
        case "trendLine": case "arrow": case "arrowMarker": {
          let a = p0, b = p1;
          if (d.tool === "trendLine" && d.extend !== "none") {
            const dx = b[0] - a[0], dy = b[1] - a[1], k = dx || dy ? 4000 / Math.hypot(dx, dy) : 0;
            if (d.extend === "left" || d.extend === "both") a = [a[0] - dx * k, a[1] - dy * k];
            if (d.extend === "right" || d.extend === "both") b = [b[0] + dx * k, b[1] + dy * k];
          }
          lineTo([a, b]);
          if (d.tool !== "trendLine") arrowHead(p0, p1, d.tool === "arrowMarker" ? 14 : 10);
          if (d.mid) { g.strokeStyle = d.midColor; g.setLineDash(DASH[d.midStyle]); const mx = (p0[0] + p1[0]) / 2, my = (p0[1] + p1[1]) / 2; lineTo([[mx - 6, my], [mx + 6, my]]); }
          caption(Math.min(p0[0], p1[0]), Math.min(p0[1], p1[1]), Math.max(p0[0], p1[0]), Math.max(p0[1], p1[1]));
          break;
        }
        case "trendRay": {
          const dx = p1[0] - p0[0], dy = p1[1] - p0[1], k = dx || dy ? 4000 / Math.hypot(dx, dy) : 0;
          lineTo([p0, [p0[0] + dx * k, p0[1] + dy * k]]);
          caption(Math.min(p0[0], p1[0]), Math.min(p0[1], p1[1]), Math.max(p0[0], p1[0]), Math.max(p0[1], p1[1]));
          break;
        }
        case "horizontalLine": lineTo([[0, p0[1]], [w, p0[1]]]); tag(d.pts[0].p.toFixed(dg), w - 4, p0[1] - 1, color, "#fff", "right"); caption(0, p0[1], w, p0[1]); break;
        case "horizontalRay": lineTo([p0, [w, p0[1]]]); tag(d.pts[0].p.toFixed(dg), w - 4, p0[1] - 1, color, "#fff", "right"); caption(p0[0], p0[1], w, p0[1]); break;
        case "verticalLine": lineTo([[p0[0], 0], [p0[0], h]]); caption(p0[0], 20, p0[0], 20); break;
        case "rectangle": {
          let l = Math.min(p0[0], p1[0]), r = Math.max(p0[0], p1[0]);
          const t = Math.min(p0[1], p1[1]), b = Math.max(p0[1], p1[1]);
          if (d.extend === "left" || d.extend === "both") l = 0;
          if (d.extend === "right" || d.extend === "both") r = w;
          if (d.fill) { g.fillStyle = alpha(d.fillColor, d.fillOpacity / 100); g.fillRect(l, t, r - l, b - t); }
          g.strokeRect(px(l), px(t), Math.round(r - l), Math.round(b - t));
          if (d.mid) { g.strokeStyle = d.midColor; g.setLineDash(DASH[d.midStyle]); lineTo([[l, (t + b) / 2], [r, (t + b) / 2]]); }
          caption(l, t, r, b);
          break;
        }
        case "ellipse": {
          g.beginPath(); g.ellipse((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, Math.abs(p1[0] - p0[0]) / 2, Math.abs(p1[1] - p0[1]) / 2, 0, 0, Math.PI * 2);
          if (d.fill) { g.fillStyle = alpha(d.fillColor, d.fillOpacity / 100); g.fill(); }
          g.stroke();
          caption(Math.min(p0[0], p1[0]), Math.min(p0[1], p1[1]), Math.max(p0[0], p1[0]), Math.max(p0[1], p1[1]));
          break;
        }
        case "path": case "brush":
          g.lineJoin = "round"; g.lineCap = "round"; lineTo(pts); break;
        case "elliottImpulse": case "elliottCorrection": case "headShoulders": case "trianglePattern": {
          if (d.fill && pts.length >= 3) {
            g.beginPath(); g.moveTo(pts[0][0], pts[0][1]); pts.slice(1).forEach((p) => g.lineTo(p[0], p[1])); g.closePath();
            g.fillStyle = alpha(d.fillColor, d.fillOpacity / 100); g.fill();
          }
          lineTo(pts);
          const labels = TOOLS[d.tool].labels;
          g.font = this.font(d);
          pts.forEach((p, i) => {
            if (!labels[i]) return;
            const up = i === 0 ? p[1] > (pts[1] || p)[1] : p[1] <= pts[i - 1][1];
            g.textAlign = "center"; g.textBaseline = up ? "bottom" : "top"; g.fillStyle = d.textColor || color;
            g.fillText(labels[i], p[0], up ? p[1] - 4 : p[1] + 4);
          });
          g.strokeStyle = color;
          if (d.tool === "trianglePattern" && pts.length >= 4) { g.setLineDash([4, 3]); lineTo([pts[0], pts[2]]); lineTo([pts[1], pts[3]]); }
          if (d.tool === "headShoulders" && pts.length >= 5) { g.setLineDash([4, 3]); lineTo([pts[2], pts[4]]); }
          break;
        }
        case "fibRetracement": case "fibExtension": this.paintFib(g, d, pts, w, lineTo); break;
        case "longPosition": case "shortPosition": this.paintPosition(g, d, pts, lineTo, tag, width); break;
        case "priceRange": {
          const a = d.pts[0].p, b = d.pts[1].p, diff = b - a;
          const bars = Math.round(this.timeToLogical(d.pts[1].t) - this.timeToLogical(d.pts[0].t));
          const c = diff >= 0 ? "#2962ff" : "#f23645";
          if (d.fill) { g.fillStyle = alpha(c, d.fillOpacity / 100); g.fillRect(p0[0], p0[1], p1[0] - p0[0], p1[1] - p0[1]); }
          g.strokeStyle = alpha(c, 0.85); g.setLineDash([]); g.lineWidth = this.lw(1);
          lineTo([[p0[0], p0[1]], [p1[0], p0[1]]]); lineTo([[p0[0], p1[1]], [p1[0], p1[1]]]);
          g.strokeStyle = c; g.lineWidth = width;
          lineTo([[(p0[0] + p1[0]) / 2, p0[1]], [(p0[0] + p1[0]) / 2, p1[1]]]);
          g.fillStyle = c; arrowHead([(p0[0] + p1[0]) / 2, p0[1]], [(p0[0] + p1[0]) / 2, p1[1]], 8);
          tag(`${diff >= 0 ? "+" : ""}${diff.toFixed(dg)} (${(diff / a * 100).toFixed(2)}%)  ·  ${bars} nến`, (p0[0] + p1[0]) / 2, Math.max(p0[1], p1[1]) + 24, c, "#fff", "center");
          break;
        }
        case "fixedRangeVolume": case "anchoredVolume": this.paintVolume(g, d, pts, w); break;
        case "text": {
          d._box = this.textBlock(g, d, d.text || "Văn bản", p0[0], p0[1], "left", "middle", 240);
          break;
        }
        default: lineTo(pts);
      }
    }

    /** Fibonacci levels with their own colours, background bands, prices and values. */
    /** How the market went after a position's entry, up to the box's right edge: where price is
     * (or the TP / SL it reached first) and when. Bars are taken as filled at the entry bar. */
    positionProgress(d, target) {
      const bars = this.host.bars ? this.host.bars() : [];
      if (!bars.length) return null;
      const long = d.tool === "longPosition", entry = d.pts[0].p, stop = d.pts[1].p;
      const t0 = d.pts[0].t;
      let i = bars.length - 1;
      while (i > 0 && bars[i - 1].time >= t0) i--;
      if (bars[i].time < t0) return null;
      let price = null, end = null;
      // On to the newest bar while neither is hit: the box grows with the candles.
      for (; i < bars.length; i++) {
        const b = bars[i];
        const hitStop = long ? b.low <= stop : b.high >= stop;
        const hitTarget = long ? b.high >= target : b.low <= target;
        if (hitStop || hitTarget) {
          // Both inside one bar: the level nearer its open came first.
          const first = hitStop && hitTarget ? (Math.abs(b.open - stop) <= Math.abs(b.open - target) ? "stop" : "target") : hitStop ? "stop" : "target";
          return { start: t0, end: b.time, price: first === "stop" ? stop : target, status: first };
        }
        price = b.close; end = b.time;
      }
      return price == null ? null : { start: t0, end, price, status: "run", entry };
    }

    /** Long / short position: one design mirrored for both. A rounded box, the target and stop zones
     * deepening towards their edges, the stretch price has already travelled lit up, a "now" dot,
     * a thin R:R gauge on the right edge, and labels outside the box. */
    paintPosition(g, d, pts, lineTo, tag, width) {
      const dg = this.host.digits();
      const long = d.tool === "longPosition";
      const entry = d.pts[0].p, stop = d.pts[1].p, target = this.target(d);
      const [p0, p1] = pts, ye = p0[1], ys = p1[1], yt = this.y(target);
      if (yt == null) return;
      const prog = this.positionProgress(d, target);
      // Until TP or SL is hit the box stretches with the new candles (and ends at the hit bar).
      const reach = prog ? this.x(prog.end) : null;
      const left = Math.min(p0[0], p1[0]), right = Math.max(p0[0], p1[0], p0[0] + 40, reach != null ? reach + 4 : -Infinity), bw = right - left;
      const top = Math.min(yt, ys), bottom = Math.max(yt, ys);
      const tc = d.targetColor, sc = d.stopColor, side = long ? "#2962ff" : "#f23645";
      const op = d.fill ? d.fillOpacity / 100 : 0;
      const light = document.documentElement.dataset.theme === "light";
      g.setLineDash([]);
      g.save();
      g.beginPath(); g.roundRect(left, top, bw, bottom - top, 7); g.clip();
      // Zones: faint at the entry, deeper at the target / stop edge.
      const zone = (y, c) => {
        const grad = g.createLinearGradient(0, ye, 0, y);
        grad.addColorStop(0, alpha(c, op * 0.35)); grad.addColorStop(1, alpha(c, Math.min(0.9, op * 1.7)));
        g.fillStyle = grad; g.fillRect(left, Math.min(ye, y), bw, Math.abs(y - ye));
      };
      zone(yt, tc); zone(ys, sc);
      // The way price has gone since the entry: lit up between the entry and where price is now.
      let nowX = null, nowY = null;
      if (prog) {
        const x0 = Math.max(left, this.x(prog.start) ?? left), x1 = Math.min(right, (this.x(prog.end) ?? right) + 3);
        nowY = this.y(prog.price);
        if (nowY != null && x1 > x0) {
          const good = long ? prog.price >= entry : prog.price <= entry;
          const c = good ? tc : sc;
          const grad = g.createLinearGradient(x0, 0, x1, 0);
          grad.addColorStop(0, alpha(c, 0.16)); grad.addColorStop(1, alpha(c, 0.5));
          g.fillStyle = grad; g.fillRect(x0, Math.min(ye, nowY), x1 - x0, Math.abs(nowY - ye));
          g.strokeStyle = alpha(c, 0.95); g.lineWidth = this.lw(1); lineTo([[x0, nowY], [x1, nowY]]);
          nowX = x1;
        }
      }
      g.restore();
      // Frame and the target / stop edges.
      g.strokeStyle = light ? "rgba(0, 0, 0, 0.10)" : "rgba(255, 255, 255, 0.10)"; g.lineWidth = 1;
      g.beginPath(); g.roundRect(left + 0.5, top + 0.5, bw - 1, bottom - top - 1, 7); g.stroke();
      g.lineWidth = this.lw(1);
      g.strokeStyle = tc; lineTo([[left + 6, yt], [right - 6, yt]]);
      g.strokeStyle = sc; lineTo([[left + 6, ys], [right - 6, ys]]);
      // Entry: the side's colour, ends rounded off with dots.
      g.strokeStyle = side; g.lineWidth = Math.max(width, this.lw(1.5)); lineTo([[left, ye], [right, ye]]);
      g.fillStyle = side;
      [left, right].forEach((x) => { g.beginPath(); g.arc(x, ye, 2.5, 0, Math.PI * 2); g.fill(); });
      // R:R gauge on the right edge: reward above / below, risk on the other side, joined at the entry.
      const gx = right - 6;
      g.lineCap = "round"; g.lineWidth = 3;
      g.strokeStyle = alpha(tc, 0.95); g.beginPath(); g.moveTo(gx, ye); g.lineTo(gx, yt + (yt < ye ? 4 : -4)); g.stroke();
      g.strokeStyle = alpha(sc, 0.95); g.beginPath(); g.moveTo(gx, ye); g.lineTo(gx, ys + (ys < ye ? 4 : -4)); g.stroke();
      g.lineCap = "butt";
      // Now: a dot with a halo where price is (or where it hit TP / SL).
      if (nowX != null && nowY != null) {
        const c = prog.status === "stop" ? sc : prog.status === "target" ? tc : (long ? prog.price >= entry : prog.price <= entry) ? tc : sc;
        g.fillStyle = alpha(c, 0.25); g.beginPath(); g.arc(nowX, nowY, 7, 0, Math.PI * 2); g.fill();
        g.fillStyle = c; g.beginPath(); g.arc(nowX, nowY, 3.5, 0, Math.PI * 2); g.fill();
        g.strokeStyle = light ? "#fff" : "#0b0f17"; g.lineWidth = 1.5; g.stroke();
      }
      // Labels outside the box, the same way round for buys and sells: short, no prices, and faint
      // unless the position is picked or under the mouse.
      const risk = Math.abs(entry - stop), reward = Math.abs(target - entry);
      const rr = risk ? reward / risk : 0;
      const pct = (v) => (v / entry * 100).toFixed(2) + "%";
      const mid = (left + right) / 2;
      const outside = (y, up) => (up ? y - 7 : y + 26);
      const active = d.id === this.selected || d.id === this.hoverId || d === this.pending;
      g.globalAlpha = active ? 1 : 0.42;
      tag(`▲ +${reward.toFixed(dg)}  (${pct(reward)})`, mid, outside(yt, yt < ye), tc, "#fff", "center");
      tag(`▼ −${risk.toFixed(dg)}  (${pct(risk)})`, mid, outside(ys, ys < ye), sc, "#fff", "center");
      // Entry pill: the side, the price, R:R, and how it is going.
      let status = "", statusColor = null;
      if (prog) {
        const moved = long ? prog.price - entry : entry - prog.price;
        const r = risk ? moved / risk : 0;
        if (prog.status === "target") { status = `✓ TP  +${rr.toFixed(2)}R`; statusColor = tc; }
        else if (prog.status === "stop") { status = "✕ SL  −1R"; statusColor = sc; }
        else { status = `${moved >= 0 ? "+" : "−"}${Math.abs(moved).toFixed(dg)}  ·  ${r >= 0 ? "+" : "−"}${Math.abs(r).toFixed(2)}R`; statusColor = moved >= 0 ? tc : sc; }
      }
      g.save();
      g.globalAlpha = active ? 1 : 0.42;
      g.font = "600 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
      g.textBaseline = "middle";
      const sideText = long ? "MUA" : "BÁN", body = `R:R ${rr.toFixed(2)}`;
      const sw = g.measureText(sideText).width + 14, bwid = g.measureText(body).width + 16, stw = status ? g.measureText(status).width + 14 : 0;
      const total = sw + bwid + stw, h = 20, px = mid - total / 2, py = ye - h / 2;
      g.shadowColor = "rgba(0, 0, 0, 0.3)"; g.shadowBlur = 8; g.shadowOffsetY = 1;
      g.fillStyle = light ? "rgba(255, 255, 255, 0.96)" : "rgba(18, 23, 34, 0.94)";
      g.beginPath(); g.roundRect(px, py, total, h, 10); g.fill();
      g.shadowColor = "transparent";
      g.strokeStyle = alpha(side, 0.55); g.lineWidth = 1; g.stroke();
      g.fillStyle = side; g.beginPath(); g.roundRect(px + 2, py + 2, sw - 4, h - 4, 8); g.fill();
      g.fillStyle = "#fff"; g.fillText(sideText, px + 7, py + h / 2 + 0.5);
      g.fillStyle = light ? "#1d2330" : "#e8ecf3"; g.fillText(body, px + sw + 8, py + h / 2 + 0.5);
      if (status) {
        g.fillStyle = alpha(statusColor, 0.18); g.beginPath(); g.roundRect(px + sw + bwid, py + 2, stw - 2, h - 4, 8); g.fill();
        g.fillStyle = statusColor; g.fillText(status, px + sw + bwid + 7, py + h / 2 + 0.5);
      }
      g.restore();
    }

    paintFib(g, d, pts, w, lineTo) {
      const dg = this.host.digits();
      const f = d.fib || this.defaults(d.tool).fib;
      let price, left, right;
      if (d.tool === "fibRetracement") {
        const a = d.pts[0].p, b = d.pts[1].p;
        price = (lv) => (f.reverse ? a + (b - a) * lv : b + (a - b) * lv);
        left = Math.min(pts[0][0], pts[1][0]); right = Math.max(pts[0][0], pts[1][0]);
        if (f.trend) { g.save(); g.setLineDash([3, 3]); g.strokeStyle = alpha(d.color, 0.6); g.lineWidth = this.lw(1); lineTo([pts[0], pts[1]]); g.restore(); }
      } else {
        lineTo(pts.slice(0, 3));
        if (pts.length < 3) return;
        const [a, b, c] = d.pts.map((p) => p.p);
        price = (lv) => (f.reverse ? c - (b - a) * lv : c + (b - a) * lv);
        left = Math.min(pts[2][0], pts[1][0]); right = Math.max(pts[2][0], pts[1][0]) + 60;
      }
      // "Kéo dài": the levels run to the left and/or right edge of the chart.
      if (f.extendLeft) left = 0;
      if (f.extendRight) right = w;
      const levels = f.levels.filter((l) => l.on).sort((m, n) => m.v - n.v);
      const colorOf = (l) => (f.oneColorOn ? f.oneColor : l.color);
      if (f.bg) {
        for (let i = 1; i < levels.length; i++) {
          const y1 = this.y(price(levels[i - 1].v)), y2 = this.y(price(levels[i].v));
          if (y1 == null || y2 == null) continue;
          g.fillStyle = alpha(colorOf(levels[i]), f.bgOpacity / 100);
          g.fillRect(left, Math.min(y1, y2), right - left, Math.abs(y2 - y1));
        }
      }
      g.font = `${f.fontSize || 11}px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif`;
      levels.forEach((l) => {
        const v = price(l.v), yy = this.y(v);
        if (yy == null) return;
        g.strokeStyle = colorOf(l); g.lineWidth = this.lw(d.width); g.setLineDash(DASH[d.style] || []);
        lineTo([[left, yy], [right, yy]]);
        const label = [f.values ? String(l.v) : "", f.prices ? `(${v.toFixed(dg)})` : ""].filter(Boolean).join(" ");
        if (!label) return;
        g.fillStyle = colorOf(l); g.textBaseline = "middle";
        if (f.labelSide === "right") {
          if (f.extendRight) { g.textAlign = "right"; g.fillText(label, w - 4, yy - 7); } else { g.textAlign = "left"; g.fillText(label, right + 4, yy); }
        } else if (f.extendLeft) { g.textAlign = "left"; g.fillText(label, 4, yy - 7); } else { g.textAlign = "right"; g.fillText(label, left - 4, yy); }
      });
    }

    /** Volume by price over the bars between the points (to the last bar when anchored). */
    paintVolume(g, d, pts, w) {
      const bars = this.host.bars();
      const l0 = Math.max(0, Math.round(this.timeToLogical(d.pts[0].t)));
      const l1 = d.tool === "anchoredVolume" ? bars.length - 1 : Math.min(bars.length - 1, Math.round(this.timeToLogical(d.pts[1].t)));
      const from = Math.min(l0, l1), to = Math.max(l0, l1);
      if (to - from < 1) return;
      let hi = -Infinity, lo = Infinity;
      for (let i = from; i <= to; i++) { hi = Math.max(hi, bars[i].high); lo = Math.min(lo, bars[i].low); }
      const rows = 24, step = (hi - lo) / rows || 1, vol = new Array(rows).fill(0), up = new Array(rows).fill(0);
      for (let i = from; i <= to; i++) {
        const b = bars[i], v = b.volume || (b.high - b.low) || 1;
        const r0 = Math.max(0, Math.floor((b.low - lo) / step)), r1 = Math.min(rows - 1, Math.floor((b.high - lo) / step));
        for (let r = r0; r <= r1; r++) { vol[r] += v / (r1 - r0 + 1); if (b.close >= b.open) up[r] += v / (r1 - r0 + 1); }
      }
      const max = Math.max(...vol), poc = vol.indexOf(max);
      const left = this.host.chart.timeScale().logicalToCoordinate(from), right = d.tool === "anchoredVolume" ? w : this.host.chart.timeScale().logicalToCoordinate(to);
      if (left == null || right == null) return;
      const width = Math.max(30, (right - left) * 0.35);
      g.setLineDash([]);
      for (let r = 0; r < rows; r++) {
        const yTop = this.y(lo + (r + 1) * step), yBot = this.y(lo + r * step);
        if (yTop == null || yBot == null) continue;
        const len = vol[r] / max * width, upLen = up[r] / max * width;
        g.fillStyle = alpha("#2962ff", r === poc ? 0.75 : 0.4); g.fillRect(left, yTop + 0.5, upLen, yBot - yTop - 1);
        g.fillStyle = alpha("#f23645", r === poc ? 0.75 : 0.4); g.fillRect(left + upLen, yTop + 0.5, len - upLen, yBot - yTop - 1);
      }
      const yPoc = this.y(lo + (poc + 0.5) * step);
      g.strokeStyle = "#ff9800"; g.lineWidth = 1; g.beginPath(); g.moveTo(left, yPoc); g.lineTo(right, yPoc); g.stroke();
      if (d.tool === "fixedRangeVolume") { g.strokeStyle = alpha(d.color, 0.6); g.setLineDash([3, 3]); g.strokeRect(left, this.y(hi), right - left, this.y(lo) - this.y(hi)); }
      else { g.strokeStyle = d.color; g.beginPath(); g.moveTo(pts[0][0], pts[0][1] - 30); g.lineTo(pts[0][0], pts[0][1] + 30); g.stroke(); }
    }
  }

  window.AurumDrawings = Drawings;
})();
