/* Drawing tools on the web chart, like the app's (TradingView-style): trend
 * lines, rays, horizontal / vertical lines, Fibonacci, patterns, long / short
 * positions, price range, volume profiles, shapes and text. Points are kept as
 * {t: UTC seconds, p: price} so drawings stay put across timeframes; they are
 * saved per symbol in this browser and painted inside the chart's render pass. */
(() => {
  "use strict";

  const COLORS = ["#2962ff", "#f23645", "#089981", "#ff9800", "#9c27b0", "#787b86", "#e8ecf3"];
  const TOOLS = {
    trendLine: { name: "Đường xu hướng", icon: "╱", n: 2 },
    trendRay: { name: "Tia xu hướng", icon: "↗", n: 2 },
    horizontalLine: { name: "Đường nằm ngang", icon: "—", n: 1 },
    horizontalRay: { name: "Tia nằm ngang", icon: "→", n: 1 },
    verticalLine: { name: "Đường thẳng đứng", icon: "│", n: 1 },
    fibRetracement: { name: "Hồi quy Fib (OTE)", icon: "≡", n: 2 },
    fibExtension: { name: "Fib mở rộng theo xu hướng", icon: "≣", n: 3 },
    elliottImpulse: { name: "Sóng đẩy Elliott (1·2·3·4·5)", icon: "⌇", n: 6, labels: ["0", "1", "2", "3", "4", "5"] },
    elliottCorrection: { name: "Sóng điều chỉnh Elliott (A·B·C)", icon: "⌇", n: 4, labels: ["0", "A", "B", "C"] },
    headShoulders: { name: "Mô hình Đầu Vai", icon: "⛰", n: 7, labels: ["", "Vai trái", "", "Đầu", "", "Vai phải", ""] },
    trianglePattern: { name: "Mô hình tam giác", icon: "△", n: 4, labels: ["A", "B", "C", "D"] },
    longPosition: { name: "Vị thế Mua", icon: "▲", n: 2 },
    shortPosition: { name: "Vị thế Bán", icon: "▼", n: 2 },
    fixedRangeVolume: { name: "Khối lượng phạm vi cố định", icon: "▤", n: 2 },
    anchoredVolume: { name: "Khối lượng được neo", icon: "▥", n: 1 },
    priceRange: { name: "Đo giá", icon: "↕", n: 2 },
    brush: { name: "Cọ vẽ", icon: "✎", n: -1 },
    rectangle: { name: "Hình chữ nhật", icon: "▭", n: 2 },
    arrow: { name: "Mũi tên", icon: "➚", n: 2 },
    ellipse: { name: "Hình elip", icon: "◯", n: 2 },
    path: { name: "Đường dẫn", icon: "〰", n: 12 },
    arrowMarker: { name: "Mũi tên đánh dấu", icon: "➤", n: 2 },
    text: { name: "Văn bản", icon: "T", n: 1 },
  };
  const CATEGORIES = [
    ["Công cụ xu hướng", ["trendLine", "trendRay", "horizontalLine", "horizontalRay", "verticalLine"]],
    ["Gann và Fibonacci", ["fibRetracement", "fibExtension"]],
    ["Mô hình", ["elliottImpulse", "elliottCorrection", "headShoulders", "trianglePattern"]],
    ["Dự đoán và đo lường", ["longPosition", "shortPosition", "fixedRangeVolume", "anchoredVolume", "priceRange"]],
    ["Hình học", ["brush", "rectangle", "arrow", "ellipse", "path", "arrowMarker"]],
    ["Lưu ý", ["text"]],
  ];
  const FIB = [1, 0.79, 0.705, 0.62, 0.5, 0, -0.27, -0.62, -1];
  const FIB_EXT = [0, 0.618, 1, 1.272, 1.618, 2, 2.618];
  const DASH = { solid: [], dashed: [6, 4], dotted: [2, 3] };

  const alpha = (hex, a) => hex + Math.round(Math.max(0, Math.min(1, a)) * 255).toString(16).padStart(2, "0");

  class Drawings {
    /** host: { chart, series, bars(), sec(), digits(), symbol(), store, onChange(), toolbar element } */
    constructor(host) {
      this.host = host;
      this.list = [];
      this.tool = null;
      this.pending = null; // the drawing being placed
      this.selected = null;
      this.gesture = null;
      this.hover = null;
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
            renderer: () => ({ draw: (target) => target.useMediaCoordinateSpace(({ context, mediaSize }) => self.paint(context, mediaSize.width, mediaSize.height)) }),
          }];
        },
      };
      host.series.attachPrimitive(this.primitive);
    }

    static get tools() { return TOOLS; }
    static get categories() { return CATEGORIES; }
    static get colors() { return COLORS; }

    update() { if (this.requestUpdate) this.requestUpdate(); }

    /* ----- storage ----- */

    key() { return "aurum.draw." + (this.host.symbol() || "XAUUSD"); }
    load() {
      try { this.list = JSON.parse(this.host.store.get(this.key()) || "[]"); } catch { this.list = []; }
      this.selected = null; this.pending = null;
      this.update();
      this.host.onChange();
    }
    save() {
      try { this.host.store.set(this.key(), JSON.stringify(this.list)); } catch { /* full */ }
      this.host.onChange();
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

    setTool(tool) {
      this.tool = tool;
      this.pending = null;
      this.selected = null;
      this.update();
      this.host.onChange();
    }

    newDrawing(tool) {
      const st = this.styles[tool] || {};
      return {
        id: Math.random().toString(36).slice(2, 10), tool, pts: [],
        color: st.color || (tool === "longPosition" ? COLORS[2] : tool === "shortPosition" ? COLORS[1] : COLORS[0]),
        width: st.width || (tool === "brush" ? 2 : 1.5), style: st.style || "solid", rr: st.rr || 2, text: "", locked: false,
      };
    }

    finish() {
      const d = this.pending;
      this.pending = null;
      this.tool = null;
      if (!d) return;
      if (d.tool === "text" && !d.text) {
        const text = prompt("Nội dung:", "");
        if (!text) { this.update(); this.host.onChange(); return; }
        d.text = text;
      }
      this.list.push(d);
      this.selected = d.id;
      this.save();
      this.update();
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
        } else {
          // Next click of a multi-point tool.
          const pts = this.pending.pts;
          pts[pts.length - 1] = pt;
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
      if (!hit.d.locked) {
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
          if (pt) { this.pending.pts[this.pending.pts.length - 1] = pt; this.update(); }
        }
        return false;
      }
      if (Math.hypot(x - g.x, y - g.y) > 4) g.moved = true;
      if (g.kind === "create") {
        const pt = this.point(x, y, this.host.magnet());
        if (!pt) return true;
        const d = this.pending;
        if (d.tool === "brush") { if (g.moved) d.pts.push(pt); } else d.pts[d.pts.length - 1] = pt;
      } else if (g.kind === "handle") {
        const pt = this.point(x, y, this.host.magnet());
        if (pt) g.d.pts[g.handle] = pt;
      } else if (g.kind === "move" && g.anchor) {
        const now = this.point(x, y, false);
        if (!now) return true;
        const dl = this.timeToLogical(now.t) - this.timeToLogical(g.anchor.t), dp = now.p - g.anchor.p;
        g.d.pts = g.start.map((p) => ({ t: this.logicalToTime(this.timeToLogical(p.t) + dl), p: +(p.p + dp).toFixed(this.host.digits()) }));
      }
      this.update();
      return true;
    }

    up() {
      const g = this.gesture;
      this.gesture = null;
      if (!g) return false;
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

    cancel() {
      this.pending = null; this.tool = null; this.gesture = null;
      this.update(); this.host.onChange();
    }

    get current() { return this.list.find((d) => d.id === this.selected) || null; }

    remove(id) {
      this.list = this.list.filter((d) => d.id !== id);
      if (this.selected === id) this.selected = null;
      this.save(); this.update();
    }
    clear() { this.list = []; this.selected = null; this.save(); this.update(); }

    restyle(changes) {
      const d = this.current;
      if (!d) return;
      Object.assign(d, changes);
      this.styles[d.tool] = { color: d.color, width: d.width, style: d.style, rr: d.rr };
      try { this.host.store.set("aurum.drawStyles", JSON.stringify(this.styles)); } catch { /* full */ }
      this.save(); this.update();
    }

    /* ----- hit testing ----- */

    hitTest(x, y, tol) {
      for (let k = this.list.length - 1; k >= 0; k--) {
        const d = this.list[k];
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

    handles(d, pts) { return d.tool === "brush" ? [] : pts; }

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
        case "text": return Math.abs(x - p0[0]) < 80 && Math.abs(y - p0[1]) < 14;
        case "anchoredVolume": return Math.abs(x - p0[0]) <= tol || (x >= p0[0] && Math.abs(y - p0[1]) < 40);
        case "trendRay": {
          const far = [p0[0] + (p1[0] - p0[0]) * 1000, p0[1] + (p1[1] - p0[1]) * 1000];
          return seg(p0, far);
        }
        case "rectangle": case "ellipse": {
          // The outline only, so the chart can still be dragged from inside a big box.
          const box = [[p0[0], p0[1]], [p1[0], p0[1]], [p1[0], p1[1]], [p0[0], p1[1]], [p0[0], p0[1]]];
          for (let i = 1; i < box.length; i++) if (seg(box[i - 1], box[i])) return true;
          return false;
        }
        case "priceRange": case "fixedRangeVolume": case "fibRetracement": return inBox(p0, p1);
        case "longPosition": case "shortPosition": return inBox(p0, p1) || inBox(p0, [p1[0], this.y(this.target(d))]);
        default:
          for (let i = 1; i < pts.length; i++) if (seg(pts[i - 1], pts[i])) return true;
          return pts.length === 1 && Math.hypot(p0[0] - x, p0[1] - y) <= tol;
      }
    }

    target(d) { const [a, b] = d.pts; return a.p + (a.p - b.p) * (d.rr || 2); }

    /* ----- painting ----- */

    paint(g, w, h) {
      const all = this.pending ? this.list.concat([this.pending]) : this.list;
      if (!all.length) return;
      g.save();
      all.forEach((d) => {
        const pts = d.pts.map((p) => [this.x(p.t), this.y(p.p)]);
        if (pts.some(([a, b]) => a == null || b == null)) return;
        try { this.paintOne(g, d, pts, w, h); } catch { /* skip a broken drawing */ }
        if (d.id === this.selected || d === this.pending) {
          this.handles(d, pts).forEach(([a, b]) => {
            g.setLineDash([]); g.fillStyle = "#0b0f17"; g.strokeStyle = d.color; g.lineWidth = 1.5;
            g.beginPath(); g.arc(a, b, 4.5, 0, Math.PI * 2); g.fill(); g.stroke();
          });
        }
      });
      g.restore();
    }

    paintOne(g, d, pts, w, h) {
      const dg = this.host.digits();
      const color = d.color;
      g.strokeStyle = color; g.fillStyle = color; g.lineWidth = d.width; g.setLineDash(DASH[d.style] || []);
      g.font = "11px Be Vietnam Pro, system-ui, sans-serif"; g.textBaseline = "bottom"; g.textAlign = "left";
      const lineTo = (pp) => { g.beginPath(); g.moveTo(pp[0][0], pp[0][1]); pp.slice(1).forEach((p) => g.lineTo(p[0], p[1])); g.stroke(); };
      const tag = (text, x, y, bg, fg = "#fff", align = "left") => {
        g.save(); g.setLineDash([]);
        const tw = g.measureText(text).width + 8;
        const left = align === "right" ? x - tw : align === "center" ? x - tw / 2 : x;
        g.fillStyle = bg; g.fillRect(left, y - 15, tw, 16);
        g.fillStyle = fg; g.textAlign = "left"; g.fillText(text, left + 4, y - 2);
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
      const [p0, p1] = pts;
      switch (d.tool) {
        case "trendLine": lineTo(pts); break;
        case "arrow": case "arrowMarker": lineTo(pts); arrowHead(p0, p1, d.tool === "arrowMarker" ? 14 : 10); break;
        case "trendRay": {
          const dx = p1[0] - p0[0], dy = p1[1] - p0[1], k = dx || dy ? 4000 / Math.hypot(dx, dy) : 0;
          lineTo([p0, [p0[0] + dx * k, p0[1] + dy * k]]); break;
        }
        case "horizontalLine": lineTo([[0, p0[1]], [w, p0[1]]]); tag(d.pts[0].p.toFixed(dg), w - 4, p0[1] - 1, color, "#fff", "right"); break;
        case "horizontalRay": lineTo([p0, [w, p0[1]]]); tag(d.pts[0].p.toFixed(dg), w - 4, p0[1] - 1, color, "#fff", "right"); break;
        case "verticalLine": lineTo([[p0[0], 0], [p0[0], h]]); break;
        case "rectangle":
          g.fillStyle = alpha(color, 0.15); g.fillRect(p0[0], p0[1], p1[0] - p0[0], p1[1] - p0[1]);
          g.strokeRect(p0[0], p0[1], p1[0] - p0[0], p1[1] - p0[1]); break;
        case "ellipse":
          g.beginPath(); g.ellipse((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, Math.abs(p1[0] - p0[0]) / 2, Math.abs(p1[1] - p0[1]) / 2, 0, 0, Math.PI * 2);
          g.fillStyle = alpha(color, 0.12); g.fill(); g.stroke(); break;
        case "path": case "brush":
          g.lineJoin = "round"; g.lineCap = "round"; lineTo(pts); break;
        case "elliottImpulse": case "elliottCorrection": case "headShoulders": case "trianglePattern": {
          lineTo(pts);
          const labels = TOOLS[d.tool].labels;
          pts.forEach((p, i) => {
            if (!labels[i]) return;
            const up = i === 0 ? p[1] > (pts[1] || p)[1] : p[1] <= pts[i - 1][1];
            g.textAlign = "center"; g.textBaseline = up ? "bottom" : "top"; g.fillStyle = color;
            g.fillText(labels[i], p[0], up ? p[1] - 4 : p[1] + 4);
          });
          if (d.tool === "trianglePattern" && pts.length >= 4) { g.setLineDash([4, 3]); lineTo([pts[0], pts[2]]); lineTo([pts[1], pts[3]]); }
          if (d.tool === "headShoulders" && pts.length >= 5) { g.setLineDash([4, 3]); lineTo([pts[2], pts[4]]); }
          break;
        }
        case "fibRetracement": {
          const a = d.pts[0].p, b = d.pts[1].p;
          const left = Math.min(p0[0], p1[0]), right = Math.max(p0[0], p1[0]);
          const yOf = (lv) => this.y(b + (a - b) * lv);
          const y62 = yOf(0.62), y79 = yOf(0.79);
          if (y62 != null && y79 != null) { g.fillStyle = alpha("#089981", 0.12); g.fillRect(left, Math.min(y62, y79), right - left, Math.abs(y79 - y62)); }
          FIB.forEach((lv) => {
            const yy = yOf(lv);
            if (yy == null) return;
            const c = lv === 0.705 ? "#089981" : lv < 0 ? "#f23645" : lv === 0.5 ? "#787b86" : color;
            g.strokeStyle = c; g.setLineDash(lv === 0.5 ? [4, 3] : DASH[d.style] || []);
            g.beginPath(); g.moveTo(left, yy); g.lineTo(right, yy); g.stroke();
            g.fillStyle = c; g.textAlign = "right"; g.textBaseline = "bottom";
            g.fillText(`${lv} (${(b + (a - b) * lv).toFixed(dg)})`, left - 3, yy + 5);
          });
          g.setLineDash([3, 3]); g.strokeStyle = alpha(color, 0.5); lineTo([p0, p1]);
          break;
        }
        case "fibExtension": {
          lineTo(pts.slice(0, 3));
          if (pts.length < 3) break;
          const [a, b, c] = d.pts.map((p) => p.p);
          const left = Math.min(pts[2][0], pts[1][0]), right = Math.max(pts[2][0], pts[1][0]) + 60;
          FIB_EXT.forEach((lv) => {
            const price = c + (b - a) * lv, yy = this.y(price);
            if (yy == null) return;
            g.strokeStyle = color; g.setLineDash(lv === 1 ? [] : [4, 3]);
            g.beginPath(); g.moveTo(left, yy); g.lineTo(right, yy); g.stroke();
            g.fillStyle = color; g.textAlign = "left"; g.fillText(`${lv} (${price.toFixed(dg)})`, right + 3, yy + 5);
          });
          break;
        }
        case "longPosition": case "shortPosition": {
          const entry = d.pts[0].p, stop = d.pts[1].p, target = this.target(d);
          const ye = p0[1], ys = p1[1], yt = this.y(target);
          const left = Math.min(p0[0], p1[0]), right = Math.max(p0[0], p1[0], p0[0] + 40);
          g.setLineDash([]);
          g.fillStyle = alpha("#f23645", 0.18); g.fillRect(left, Math.min(ye, ys), right - left, Math.abs(ys - ye));
          if (yt != null) { g.fillStyle = alpha("#089981", 0.18); g.fillRect(left, Math.min(ye, yt), right - left, Math.abs(yt - ye)); }
          g.strokeStyle = "#787b86"; g.lineWidth = 1; lineTo([[left, ye], [right, ye]]);
          const risk = Math.abs(entry - stop);
          tag(`Mục tiêu ${target.toFixed(dg)} (${(Math.abs(target - entry)).toFixed(dg)})`, left, Math.min(yt, ye) - 2, "#089981");
          tag(`Dừng ${stop.toFixed(dg)} (${risk.toFixed(dg)})`, left, Math.max(ys, ye) + 16, "#f23645");
          tag(`${d.tool === "longPosition" ? "MUA" : "BÁN"} ${entry.toFixed(dg)} · R:R ${d.rr}`, left, ye - 2, "#2a3449");
          break;
        }
        case "priceRange": {
          const a = d.pts[0].p, b = d.pts[1].p, diff = b - a;
          const bars = Math.round(this.timeToLogical(d.pts[1].t) - this.timeToLogical(d.pts[0].t));
          const c = diff >= 0 ? "#2962ff" : "#f23645";
          g.fillStyle = alpha(c, 0.15); g.fillRect(p0[0], p0[1], p1[0] - p0[0], p1[1] - p0[1]);
          g.strokeStyle = c; g.setLineDash([]);
          lineTo([[(p0[0] + p1[0]) / 2, p0[1]], [(p0[0] + p1[0]) / 2, p1[1]]]);
          g.fillStyle = c; arrowHead([(p0[0] + p1[0]) / 2, p0[1]], [(p0[0] + p1[0]) / 2, p1[1]], 8);
          tag(`${diff >= 0 ? "+" : ""}${diff.toFixed(dg)} (${(diff / a * 100).toFixed(2)}%) · ${bars} nến`, (p0[0] + p1[0]) / 2, Math.max(p0[1], p1[1]) + 18, c, "#fff", "center");
          break;
        }
        case "fixedRangeVolume": case "anchoredVolume": this.paintVolume(g, d, pts, w); break;
        case "text": {
          g.font = "600 13px Be Vietnam Pro, system-ui, sans-serif"; g.fillStyle = color; g.textAlign = "left"; g.textBaseline = "middle";
          g.fillText(d.text || "Văn bản", p0[0], p0[1]); break;
        }
        default: lineTo(pts);
      }
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
