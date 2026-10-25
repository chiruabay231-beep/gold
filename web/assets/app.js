/* Aurum Pro website: the landing page and the members' web app.
 * Members sign in with their invite code only: the server's address is looked
 * up where the server posts it (ntfy.sh topic derived from the code), exactly
 * like the iPhone app, then /member/me and /member/signals are read with the code. */
(() => {
  "use strict";
  const SITE = window.SITE || {};
  const $ = (id) => document.getElementById(id);
  const RELAY = "https://ntfy.sh";
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* private mode */ } },
  };

  /* ---------------- landing ---------------- */

  $("year").textContent = new Date().getFullYear();
  if (SITE.contactUrl) {
    const b = $("contactBtn");
    b.href = SITE.contactUrl;
    b.target = "_blank";
    b.rel = "noopener";
    b.textContent = SITE.contactLabel || "Nhận mã mời";
  }
  const plansEl = $("plans-list");
  (SITE.plans || []).forEach((p) => {
    const el = document.createElement("article");
    el.className = "plan" + (p.highlight ? " hot" : "");
    el.innerHTML = `${p.highlight ? '<span class="tag">Phổ biến</span>' : ""}
      <h3></h3><div class="price"><span></span> <small></small></div><ul></ul>
      <a class="btn ${p.highlight ? "btn-gold" : "btn-ghost"}"></a>`;
    el.querySelector("h3").textContent = p.name;
    el.querySelector(".price span").textContent = p.price;
    el.querySelector(".price small").textContent = p.price === "Liên hệ" ? "" : (p.period || "");
    const ul = el.querySelector("ul");
    (p.features || []).forEach((f) => { const li = document.createElement("li"); li.textContent = f; ul.appendChild(li); });
    const a = el.querySelector("a");
    a.textContent = SITE.contactUrl ? "Đăng ký gói này" : "Đã có mã? Đăng nhập";
    a.href = SITE.contactUrl || "#member";
    if (SITE.contactUrl) { a.target = "_blank"; a.rel = "noopener"; }
    plansEl.appendChild(el);
  });

  // Decorative candles in the hero phone.
  (function heroChart() {
    const svg = $("heroChart");
    let p = 100, html = "";
    const bars = [];
    for (let i = 0; i < 34; i++) {
      const o = p, c = o + (Math.sin(i / 3) * 2 + (i / 12) + (Math.random() - .45) * 3);
      bars.push({ o, c, h: Math.max(o, c) + Math.random() * 1.6, l: Math.min(o, c) - Math.random() * 1.6 });
      p = c;
    }
    const hi = Math.max(...bars.map((b) => b.h)), lo = Math.min(...bars.map((b) => b.l));
    const y = (v) => 280 - (v - lo) / (hi - lo) * 260;
    html += `<rect x="0" y="${y(lo + (hi - lo) * .32)}" width="320" height="${y(lo + (hi - lo) * .22) - y(lo + (hi - lo) * .32)}" fill="rgba(20,184,138,.12)"/>`;
    html += `<line x1="0" x2="320" y1="${y(lo + (hi - lo) * .7)}" y2="${y(lo + (hi - lo) * .7)}" stroke="#f0455a" stroke-dasharray="6 4"/>`;
    bars.forEach((b, i) => {
      const x = 6 + i * 9.2, col = b.c >= b.o ? "#14b88a" : "#f0455a";
      html += `<line x1="${x}" x2="${x}" y1="${y(b.h)}" y2="${y(b.l)}" stroke="${col}"/>`;
      html += `<rect x="${x - 3}" y="${y(Math.max(b.o, b.c))}" width="6" height="${Math.max(1.5, Math.abs(y(b.o) - y(b.c)))}" fill="${col}" rx="1"/>`;
    });
    const last = bars[bars.length - 1];
    html += `<line x1="0" x2="320" y1="${y(last.c)}" y2="${y(last.c)}" stroke="#9b6bff" stroke-dasharray="2 3"/>`;
    svg.innerHTML = html;
  })();

  // Live gold price in the hero (Binance XAUUSDT futures).
  fetch("https://fapi.binance.com/fapi/v1/ticker/price?symbol=XAUUSDT")
    .then((r) => r.json()).then((d) => { if (d.price) $("heroPrice").textContent = Number(d.price).toFixed(2); })
    .catch(() => {});

  /* ---------------- routing ---------------- */

  function route() {
    const member = location.hash.startsWith("#member");
    $("landing").hidden = member;
    $("member").hidden = !member;
    document.body.classList.toggle("in-member", member);
    if (member) Member.show(); else Member.hide();
  }
  window.addEventListener("hashchange", route);

  /* ---------------- members & owner ---------------- */

  async function sha256(text) {
    const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
  }

  /** Where the server is now: it posts its address to an ntfy topic only the invite
   *  code (member) or the server password (owner) can work out — like the app. */
  async function lookupAddress(secret, owner) {
    const topic = "aurum-" + (owner
      ? await sha256("url:" + secret)
      : await sha256("murl:" + await sha256(secret))).slice(0, 24);
    const res = await fetch(`${RELAY}/${topic}/json?poll=1&since=all`);
    if (!res.ok) return null;
    let url = null;
    for (const line of (await res.text()).split("\n").filter(Boolean)) {
      try {
        const m = JSON.parse(line);
        if (m.event === "message" && /^https:\/\//.test((m.message || "").trim())) url = m.message.trim().replace(/\/+$/, "");
      } catch { /* not JSON */ }
    }
    return url;
  }

  class Unreachable extends Error {}

  async function api(base, secret, path, body) {
    let res;
    try {
      const init = { headers: { Authorization: "Bearer " + secret }, cache: "no-store" };
      if (body !== undefined) {
        init.method = "POST";
        init.headers["Content-Type"] = "application/json";
        init.body = JSON.stringify(body);
      }
      res = await fetch(base + path, init);
    } catch {
      throw new Unreachable("offline");
    }
    if (res.status === 502 || res.status === 530) throw new Unreachable(String(res.status));
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error(res.status === 401 ? "Sai mã hoặc mật khẩu" : (data.error || "Lỗi " + res.status));
      err.status = res.status;
      throw err;
    }
    return data;
  }

  const num = (v) => (v === "" || v == null || isNaN(+v) ? null : +v);
  const fmt = (v, d = 2) => (v == null ? "–" : Number(v).toFixed(d));
  const signed = (v, d = 2) => (v == null ? "–" : (v >= 0 ? "+" : "") + Number(v).toFixed(d));
  const money = (v) => (v == null ? "–" : Number(v).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
  const clock = (t) => {
    const date = new Date(t * 1000), today = new Date();
    return date.toDateString() === today.toDateString()
      ? date.toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" })
      : date.toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  };
  const fullTime = (t) => new Date(t * 1000).toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  // Members' messages never name the server.
  const plain = (s) => String(s || "").replace(/ trên VPS/g, "").replace(/ VPS/g, "").replace(/VPS/g, "hệ thống");
  const sideName = (side) => (side === "long" ? "BUY" : "SELL");
  const rgba = (hex, a) => { const n = parseInt(hex.slice(1), 16); return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`; };
  // The chart's time axis shows the viewer's local time: bars are fed shifted by the
  // local offset (lightweight-charts draws times as UTC). this.bars keep real UTC.
  const TZ = -new Date().getTimezoneOffset() * 60;
  const shown = (b) => Object.assign({}, b, { time: b.time + TZ });

  // The owner's password stays for this tab only, unless "Ghi nhớ" was ticked.
  const ownerStore = {
    get() { try { return sessionStorage.getItem("aurum.pass") || localStorage.getItem("aurum.pass"); } catch { return null; } },
    set(v, remember) {
      try {
        sessionStorage.removeItem("aurum.pass"); localStorage.removeItem("aurum.pass");
        if (v) (remember ? localStorage : sessionStorage).setItem("aurum.pass", v);
      } catch { /* private mode */ }
    },
  };

  /* ---------------- toast & sheet ---------------- */

  let toastTimer = null;
  function toast(text, bad) {
    const el = $("toast");
    el.textContent = text;
    el.className = "toast" + (bad ? " bad" : "");
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, bad ? 5000 : 2500);
  }

  const sheet = {
    open(html, bind) {
      const d = $("sheet");
      $("sheetBody").innerHTML = `<button class="sheet-x" type="button" data-close>✕</button>` + html;
      $("sheetBody").querySelectorAll("[data-close]").forEach((b) => (b.onclick = () => sheet.close()));
      if (!d.open) d.showModal();
      if (bind) bind($("sheetBody"));
    },
    close() { const d = $("sheet"); if (d.open) d.close(); },
  };
  $("sheet").addEventListener("click", (e) => { if (e.target === $("sheet")) sheet.close(); });

  /** Runs a server action from a button: busy state, toast, error message. */
  async function act(button, work, done) {
    // Buttons with inner parts (the chart's BUY/SELL with live prices) keep them and only dim.
    const rich = button && button.children.length > 0;
    const label = button ? button.textContent : "";
    if (button) { button.disabled = true; if (rich) button.classList.add("busy"); else button.textContent = "…"; }
    try {
      const result = await work();
      if (done) toast(done);
      return result;
    } catch (e) {
      toast(e instanceof Unreachable ? "Chưa kết nối được, thử lại" : plain(e.message), true);
      return null;
    } finally {
      if (button) { button.disabled = false; if (rich) button.classList.remove("busy"); else button.textContent = label; }
    }
  }

  /* ---------------- indicator switches ---------------- */

  const IND = [
    ["killzones", "ICT Killzones (phiên, đỉnh đáy phiên, giá mở cửa)"],
    ["daily", "Đỉnh đáy từng ngày"],
    ["fvg", "FVG & Volume Imbalance"],
    ["mss", "MSS (đổi cấu trúc)"],
    ["flow", "Dòng tiền cá mập"],
    ["smt", "SMT (khi mở 2 biểu đồ: so đỉnh/đáy với mã thứ 2)"],
  ];
  const showInd = (() => {
    let saved = {};
    try { saved = JSON.parse(store.get("aurum.ind") || "{}"); } catch { /* default */ }
    return Object.fromEntries(IND.map(([k]) => [k, saved[k] !== false]));
  })();

  const TFS = ["5s", "10s", "15s", "30s", "1m", "5m", "15m", "30m", "1h", "4h", "1d"];
  const TF_SECONDS = { "5s": 5, "10s": 10, "15s": 15, "30s": 30, "1m": 60, "5m": 300, "15m": 900, "30m": 1800, "1h": 3600, "4h": 14400, "1d": 86400 };
  const isSecTF = (tf) => TF_SECONDS[tf] < 60;

  /* ----- second bars (5s / 10s / 15s) from Binance: MT5 has nothing under one minute ----- */

  /** The Binance market for a symbol: gold and silver from the futures trades, crypto from the spot 1-second candles. */
  function binanceMarket(symbol) {
    const s = String(symbol || "XAUUSD").toUpperCase();
    if (/XAU|GOLD/.test(s)) return { name: "XAUUSDT", futures: true, digits: 2 };
    if (/XAG|SILVER/.test(s)) return { name: "XAGUSDT", futures: true, digits: 3 };
    const m = s.match(/^(BTC|ETH|SOL|BNB|XRP|DOGE|ADA|LTC|TRX|DOT|LINK|AVAX|TON)/);
    return m ? { name: m[1] + "USDT", futures: false, digits: null } : null;
  }

  /** Bars of `sec` seconds built from Binance, with older pages on demand and a live stream. */
  class SecondFeed {
    constructor(market, sec) {
      this.market = market; this.sec = sec; this.bars = []; this.offset = 0;
      this.oldestId = null; this.oldestMs = null; this.lastId = 0; this.noOlder = false;
    }

    /** One finished piece (a trade, or one 1-second candle) into its bar; true when it opened a new bar. */
    add(t, o, h, l, c, v, list) {
      const bars = list || this.bars, d = this.offset;
      const time = Math.floor(t / this.sec) * this.sec, last = bars[bars.length - 1];
      if (last && time < last.time) return false;
      if (last && last.time === time) {
        last.high = Math.max(last.high, h + d); last.low = Math.min(last.low, l + d); last.close = c + d; last.volume += v;
        return false;
      }
      bars.push({ time, open: o + d, high: h + d, low: l + d, close: c + d, volume: v });
      return true;
    }

    /** The second still trading: each update replaces what the previous one of that second put in. */
    addOpenSecond(t, o, h, l, c, v) {
      if (!this.snap || this.snap.t !== t) this.snap = { t, n: this.bars.length, bar: this.bars.length ? Object.assign({}, this.bars[this.bars.length - 1]) : null };
      else { this.bars.length = this.snap.n; if (this.snap.bar) this.bars[this.snap.n - 1] = Object.assign({}, this.snap.bar); }
      return this.add(t, o, h, l, c, v);
    }

    async page(older) {
      const m = this.market;
      if (m.futures) {
        let url = `https://fapi.binance.com/fapi/v1/aggTrades?symbol=${m.name}&limit=1000`;
        if (older) { if (this.oldestId == null || this.oldestId <= 0) return []; url += `&fromId=${Math.max(0, this.oldestId - 1000)}`; }
        const rows = (await (await fetch(url)).json()).filter((r) => this.oldestId == null || r.a < this.oldestId);
        if (rows.length) this.oldestId = rows[0].a;
        if (!older && rows.length) this.lastId = rows[rows.length - 1].a;
        return rows.map((r) => [r.T / 1000, +r.p, +r.p, +r.p, +r.p, +r.q]);
      }
      let url = `https://api.binance.com/api/v3/klines?symbol=${m.name}&interval=1s&limit=1000`;
      if (older) url += `&endTime=${this.oldestMs - 1}`;
      const rows = await (await fetch(url)).json();
      if (!Array.isArray(rows)) throw new Error("binance");
      if (rows.length) this.oldestMs = rows[0][0];
      return rows.map((r) => [r[0] / 1000, +r[1], +r[2], +r[3], +r[4], +r[5]]);
    }

    /** About `want` bars back from now (a few requests at most). */
    async history(want) {
      let pieces = [];
      for (let k = 0; k < 10; k++) {
        const got = await this.page(k > 0);
        if (!got.length) { this.noOlder = true; break; }
        pieces = got.concat(pieces);
        if (pieces[pieces.length - 1][0] - pieces[0][0] >= want * this.sec) break;
      }
      if (!pieces.length) throw new Error("no data");
      if (this.market.digits == null) {
        const p = pieces[pieces.length - 1][4];
        this.market.digits = p >= 100 ? 2 : p >= 1 ? 4 : 6;
      }
      // The newest 1-second candle may still be trading: the stream finishes it.
      const open = this.market.futures ? null : pieces.pop();
      pieces.forEach((x) => this.add(...x));
      if (open) this.addOpenSecond(...open);
    }

    /** Older bars put in front; how many bars were added. */
    async older() {
      if (this.noOlder || this.busy || !this.bars.length) return 0;
      this.busy = true;
      try {
        const got = await this.page(true);
        if (!got.length) { this.noOlder = true; return 0; }
        const list = [];
        got.forEach((x) => this.add(...x, list));
        const first = this.bars[0], tail = list[list.length - 1];
        if (tail && tail.time === first.time) {
          // The bar cut in two by the page edge.
          first.open = tail.open; first.high = Math.max(first.high, tail.high); first.low = Math.min(first.low, tail.low); first.volume += tail.volume;
          list.pop();
        }
        this.bars.unshift(...list);
        if (this.snap) this.snap.n += list.length;
        return list.length;
      } catch { this.noOlder = true; return 0; } finally { this.busy = false; }
    }

    /** Live: `onBar(newBar)` after every trade / candle update. */
    live(onBar) {
      const m = this.market;
      const ws = new WebSocket(m.futures
        ? `wss://fstream.binance.com/ws/${m.name.toLowerCase()}@aggTrade`
        : `wss://stream.binance.com:9443/ws/${m.name.toLowerCase()}@kline_1s`);
      ws.onmessage = (ev) => {
        const x = JSON.parse(ev.data);
        if (m.futures) {
          if (x.a == null || x.a <= this.lastId) return;
          this.lastId = x.a;
          onBar(this.add(x.T / 1000, +x.p, +x.p, +x.p, +x.p, +x.q));
        } else if (x.k) {
          const k = x.k;
          onBar(this.addOpenSecond(k.t / 1000, +k.o, +k.h, +k.l, +k.c, +k.v));
        }
      };
      this.ws = ws;
    }

    /** Moves every price by `d` (to sit on the broker's price), and what comes after too. */
    shift(d) {
      this.bars.forEach((b) => { b.open += d; b.high += d; b.low += d; b.close += d; });
      if (this.snap && this.snap.bar) ["open", "high", "low", "close"].forEach((k) => (this.snap.bar[k] += d));
      this.offset += d;
    }

    close() { if (this.ws) { this.ws.onmessage = null; this.ws.close(); } this.ws = null; }
  }

  /** Lots of one order: 0.01 to 200, two decimals. */
  const MAX_LOTS = 200;
  const clampLots = (v) => Math.min(MAX_LOTS, Math.max(0.01, Math.round((v || 0.01) * 100) / 100));

  /** Money on a line label: "+45.20 USD" style, short. */
  const money0 = (v) => (v == null || !isFinite(v) ? "" : (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(2));

  /** Bar index of a time, fractional between bars and past either end (by the bar length). */
  function timeToIndex(bars, t, sec) {
    const n = bars.length;
    if (!n) return null;
    if (t <= bars[0].time) return (t - bars[0].time) / sec;
    if (t >= bars[n - 1].time) return n - 1 + (t - bars[n - 1].time) / sec;
    let lo = 0, hi = n - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (bars[m].time <= t) lo = m; else hi = m; }
    return lo + (t - bars[lo].time) / (bars[hi].time - bars[lo].time);
  }
  function indexToTime(bars, l, sec) {
    const n = bars.length;
    if (!n) return null;
    if (l <= 0) return bars[0].time + l * sec;
    if (l >= n - 1) return bars[n - 1].time + (l - (n - 1)) * sec;
    const i = Math.floor(l);
    return bars[i].time + (l - i) * (bars[i + 1].time - bars[i].time);
  }

  /** The spread in points, as MT5 shows it. */
  const spreadText = (bid, ask, digits) => (bid != null && ask != null ? String(Math.round((ask - bid) * Math.pow(10, digits))) : "");

  /* ---------------- settings panel fields ---------------- */

  /** Compact TradingView-style inputs bound by path into `root` (see Member.bindPanel). */
  function fieldKit(root) {
    const get = (path) => path.split(".").reduce((o, k) => (o == null ? undefined : o[k]), root);
    const hm = (h) => { const m = Math.round(h * 60) % 1440; return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`; };
    const chk = (path) => `<input type="checkbox" data-p="${path}" data-t="bool" ${get(path) ? "checked" : ""}>`;
    const selI = (path, opts) => `<select data-p="${path}" data-t="${typeof opts[0][0] === "number" ? "num" : typeof opts[0][0] === "boolean" ? "boolsel" : "str"}">${opts.map(([v, n]) => `<option value="${v}" ${String(v) === String(get(path)) ? "selected" : ""}>${n}</option>`).join("")}</select>`;
    const sw = (path) => `<input type="color" class="sw" data-p="${path}" data-t="str" value="${String(get(path) || "#787b86").slice(0, 7)}">`;
    return {
      chk, selI, sw,
      tog: (path, label) => `<label class="fr">${chk(path)}<span>${label}</span></label>`,
      numf: (path, label, step = 1) => `<label class="fr"><span class="grow">${label}</span><input class="n" data-p="${path}" data-t="num" inputmode="decimal" step="${step}" value="${get(path)}"></label>`,
      sel: (path, label, opts) => `<label class="fr"><span class="grow">${label}</span>${selI(path, opts)}</label>`,
      color: (path, label) => `<label class="fr"><span class="grow">${label}</span>${sw(path)}</label>`,
      time: (path) => `<input class="t" data-p="${path}" data-t="time" value="${hm(get(path))}" placeholder="HH:MM" maxlength="5" inputmode="numeric">`,
      text: (path, cls = "nm") => `<input class="${cls}" data-p="${path}" data-t="str" value="${esc(get(path))}">`,
      head: (t) => `<div class="fp-sec">${t}</div>`,
      note: (t) => `<p class="fp-note">${t}</p>`,
    };
  }

  /** A UTC time as the value of a datetime-local input (the viewer's local time). */
  function localInput(t) {
    const d = new Date(t * 1000);
    const p = (v) => String(v).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  /* ---------------- backtest of the "Stop theo nến" bot ---------------- */

  /** The bot over past bars, the same rules as CandleStopBot.backtest in the app: the orders of each
   * closed bar wait during the next one (open, the extreme reached first, the other one, close),
   * fill at their stop price, SL/TP at their price, no spread; unfilled orders live one bar. */
  function stopBotBacktest(bars, c, value, spread = 0) {
    const sp = Math.max(+spread || 0, 0);
    const off = Math.max(+c.offset || 0, 0), rr = +c.rr || 0, dir = c.direction || "both";
    const minR = +c.minRange || 0, maxR = +c.maxRange || 0, fixed = c.stopMode === "fixed", dist = Math.max(+c.stopDistance || 0, 0);
    const ordersAfter = (b) => {
      const range = b.high - b.low, out = [];
      if (!(range > 0) || range < minR || (maxR > 0 && range > maxR)) return out;
      if (dir !== "short") {
        const entry = b.high + off, stop = fixed ? entry - dist : b.low - off;
        if (entry > stop) out.push({ side: "long", entry, stop, target: rr > 0 ? entry + rr * (entry - stop) : null });
      }
      if (dir !== "long") {
        const entry = b.low - off, stop = fixed ? entry + dist : b.high + off;
        if (stop > entry) out.push({ side: "short", entry, stop, target: rr > 0 ? entry - rr * (stop - entry) : null });
      }
      return out;
    };
    let pending = [], placed = 0;
    const positions = [], trades = [];
    const closeAt = (pos, exit, reason, b) => {
      positions.splice(positions.indexOf(pos), 1);
      trades.push(Object.assign({}, pos, { exit, reason, closeTime: b.time, profit: value(pos.side, pos.entry, exit) }));
    };
    bars.forEach((b, i) => {
      if (i > 0) {
        const path = b.close >= b.open ? [b.open, b.low, b.high, b.close] : [b.open, b.high, b.low, b.close];
        for (const p of path) {
          let opened = false;
          for (const o of pending.slice()) {
            // Bars are bid prices: buys fill on the ask (bid + spread), sells on the bid.
            const q = o.side === "long" ? p + sp : p;
            if (o.above ? q >= o.entry : q <= o.entry) {
              pending.splice(pending.indexOf(o), 1);
              positions.push(Object.assign({}, o, { openTime: b.time }));
              opened = true;
            }
          }
          for (const pos of positions.slice()) {
            // Buys close on the bid, sells on the ask.
            const long = pos.side === "long", q = long ? p : p + sp;
            if (long ? q <= pos.stop : q >= pos.stop) closeAt(pos, pos.stop, "stop", b);
            else if (pos.target != null && (long ? q >= pos.target : q <= pos.target)) closeAt(pos, pos.target, "target", b);
          }
          if (c.oco !== false && opened) pending = [];
        }
        pending = [];
      }
      if (c.onePosition !== false && positions.length) return;
      // Like PaperAccount.placePending: it triggers on the side of the entry the close was not.
      ordersAfter(b).forEach((o) => { o.above = o.entry > b.close; pending.push(o); placed++; });
    });
    const last = bars[bars.length - 1];
    if (last) positions.slice().forEach((pos) => closeAt(pos, pos.side === "long" ? last.close : last.close + sp, "end", last));
    return { trades, placed };
  }

  /* ---------------- "Cản & Hỗ trợ" bot: the same rules as SRBot on the server (bot_server.py) ---------------- */

  const SR_DEFAULTS = { symbol: "", interval: "1m", direction: "both", lots: 0.01, lookback: 300, swing: 3, zoneAtr: 0.3, minTouches: 2,
    wickRatio: 0.45, pattern: "both", slBufferAtr: 0.1, rr: 2, trail: true, trailStartR: 0.5 };

  function srAtr(bars, i, n = 14) {
    if (i < n) return null;
    let total = 0;
    for (let j = i - n + 1; j <= i; j++) {
      const b = bars[j], prev = bars[j - 1];
      total += Math.max(b.high - b.low, Math.abs(b.high - prev.close), Math.abs(b.low - prev.close));
    }
    return total / n;
  }

  /** Zones from the swing highs and lows confirmed before bar i: [{price, touches}]. */
  function srLevels(bars, i, cfg, atr) {
    const k = Math.max(1, Math.floor(cfg.swing)), start = Math.max(k, i - Math.floor(cfg.lookback));
    const prices = [];
    for (let j = start; j < i - k; j++) {
      const h = bars[j].high, l = bars[j].low;
      let hi = true, lo = true;
      for (let m = j - k; m < j; m++) { if (!(h > bars[m].high)) hi = false; if (!(l < bars[m].low)) lo = false; }
      for (let m = j + 1; m <= j + k; m++) { if (!(h >= bars[m].high)) hi = false; if (!(l <= bars[m].low)) lo = false; }
      if (hi) prices.push(h);
      if (lo) prices.push(l);
    }
    prices.sort((a, b) => a - b);
    const tol = atr * cfg.zoneAtr, levels = [];
    let group = [], sum = 0;
    for (const price of prices) {
      if (group.length && price - sum / group.length > tol) { levels.push({ price: sum / group.length, touches: group.length }); group = []; sum = 0; }
      group.push(price); sum += price;
    }
    if (group.length) levels.push({ price: sum / group.length, touches: group.length });
    return levels.filter((lv) => lv.touches >= Math.floor(cfg.minTouches));
  }

  /** The trade closed bar i calls for: {side, level, stop} or null. */
  function srSignal(bars, i, cfg) {
    const atr = srAtr(bars, i);
    if (!atr || i < 2) return null;
    const b = bars[i], p = bars[i - 1], rng = b.high - b.low;
    if (!(rng > 0)) return null;
    const bodyLo = Math.min(b.open, b.close), bodyHi = Math.max(b.open, b.close), wick = +cfg.wickRatio;
    const bullPin = (bodyLo - b.low) / rng >= wick && (b.close - b.low) / rng >= 0.5;
    const bearPin = (b.high - bodyHi) / rng >= wick && (b.high - b.close) / rng >= 0.5;
    const bullEng = b.close > b.open && p.close < p.open && b.close >= p.open && b.open <= p.close;
    const bearEng = b.close < b.open && p.close > p.open && b.close <= p.open && b.open >= p.close;
    let bull = (cfg.pattern !== "engulf" && bullPin) || (cfg.pattern !== "pin" && bullEng);
    let bear = (cfg.pattern !== "engulf" && bearPin) || (cfg.pattern !== "pin" && bearEng);
    if (cfg.direction === "short") bull = false;
    if (cfg.direction === "long") bear = false;
    if (bull === bear) return null;
    const tol = atr * cfg.zoneAtr, buffer = atr * cfg.slBufferAtr;
    let best = null;
    for (const lv of srLevels(bars, i, cfg, atr)) {
      let dist;
      if (bull && b.low <= lv.price + tol && b.low >= lv.price - 2 * tol && b.close > lv.price) dist = Math.abs(b.low - lv.price);
      else if (bear && b.high >= lv.price - tol && b.high <= lv.price + 2 * tol && b.close < lv.price) dist = Math.abs(b.high - lv.price);
      else continue;
      if (!best || lv.touches > best.touches || (lv.touches === best.touches && -dist > -best.dist)) best = { touches: lv.touches, dist, price: lv.price };
    }
    if (!best) return null;
    return bull ? { side: "long", level: best.price, stop: b.low - buffer } : { side: "short", level: best.price, stop: b.high + buffer };
  }

  /** The stop after closed bar i: behind that candle once price has moved trailStartR × risk. */
  function srTrail(bars, i, cfg, side, entry, firstStop, stop) {
    if (!cfg.trail) return stop;
    const atr = srAtr(bars, i);
    if (!atr) return stop;
    const b = bars[i], risk = Math.abs(entry - firstStop), buffer = atr * cfg.slBufferAtr;
    if (side === "long") {
      if (b.close - entry < cfg.trailStartR * risk) return stop;
      const c = b.low - buffer;
      return c > stop && c < b.close ? c : stop;
    }
    if (entry - b.close < cfg.trailStartR * risk) return stop;
    const c = b.high + buffer;
    return c < stop && c > b.close ? c : stop;
  }

  /** One position at a time, entered at the reaction candle's close (buys at the ask), SL/TP
   * through the next candles (open, the extreme reached first, the other one, close), the SL
   * trailed after each close. */
  function srBacktest(bars, cfg, value, spread = 0) {
    const sp = Math.max(+spread || 0, 0), trades = [];
    let pos = null, signals = 0;
    const close = (exit, reason, b) => { trades.push(Object.assign({}, pos, { exit, reason, closeTime: b.time, profit: value(pos.side, pos.entry, exit) })); pos = null; };
    for (let i = 0; i < bars.length; i++) {
      const b = bars[i];
      if (pos && i > pos.index) {
        const path = b.close >= b.open ? [b.open, b.low, b.high, b.close] : [b.open, b.high, b.low, b.close];
        for (const p of path) {
          const long = pos.side === "long", q = long ? p : p + sp;
          if (long ? q <= pos.sl : q >= pos.sl) { close(pos.sl, pos.sl !== pos.stop ? "trail" : "stop", b); break; }
          if (pos.target != null && (long ? q >= pos.target : q <= pos.target)) { close(pos.target, "target", b); break; }
        }
        if (pos) pos.sl = srTrail(bars, i, cfg, pos.side, pos.entry, pos.stop, pos.sl);
      }
      if (!pos && i >= 30) {
        const sig = srSignal(bars, i, cfg);
        if (sig) {
          signals++;
          const long = sig.side === "long", entry = long ? b.close + sp : b.close;
          const risk = long ? entry - sig.stop : sig.stop - entry;
          if (risk > 0) {
            pos = { side: sig.side, entry, stop: sig.stop, sl: sig.stop, level: sig.level, index: i, openTime: b.time,
              target: cfg.rr > 0 ? (long ? entry + cfg.rr * risk : entry - cfg.rr * risk) : null };
          }
        }
      }
    }
    const last = bars[bars.length - 1];
    if (pos && last) close(pos.side === "long" ? last.close : last.close + sp, "end", last);
    return { trades, placed: signals };
  }

  /* ---------------- voice alerts, as in the app: TP / SL hit and fills read out ---------------- */

  const VOICE_DEFAULTS = { enabled: true, lang: "vi-VN", voice: "", rate: 0.95, pitch: 1, volume: 1, chime: true, target: "", stop: "", entry: "", buy: "", sell: "", details: false, popup: true, notify: false };
  /** Default phrases in the voice's own language: an English phrase read by a Vietnamese voice sounds wrong. */
  const VOICE_PHRASES = {
    en: { target: "Target fill", stop: "Stop loss fill", entry: "Order filled", buy: "Buy signal", sell: "Sell signal", closed: "Position closed" },
    vi: { target: "Lệnh TP", stop: "Lệnh stoploss", entry: "Đã vào lệnh", buy: "Tín hiệu mua", sell: "Tín hiệu bán", closed: "Đã đóng lệnh" },
  };
  const Voice = {
    cfg: (() => { try { return Object.assign({}, VOICE_DEFAULTS, JSON.parse(store.get("aurum.voice") || "{}")); } catch { return Object.assign({}, VOICE_DEFAULTS); } })(),
    save() { store.set("aurum.voice", JSON.stringify(this.cfg)); },
    vi() { return this.cfg.lang.startsWith("vi"); },
    defaults() { return VOICE_PHRASES[this.vi() ? "vi" : "en"]; },
    phrase(key) { return String(this.cfg[key] || "").trim() || this.defaults()[key]; },

    /** The voices for the chosen language, the clearest first (natural / neural / enhanced ones). */
    voices() {
      if (!window.speechSynthesis) return [];
      const lang = this.cfg.lang.toLowerCase(), short = lang.slice(0, 2);
      const score = (v) => (/natural|neural/i.test(v.name) ? 40 : 0) + (/online/i.test(v.name) ? 10 : 0) + (/google/i.test(v.name) ? 25 : 0)
        + (/premium|enhanced|nâng cao|siri/i.test(v.name) ? 30 : 0) + (/^(linh|samantha|ava|allison|zoe)\b/i.test(v.name) ? 8 : 0)
        + (v.lang.replace("_", "-").toLowerCase() === lang ? 5 : 0) + (/compact|espeak/i.test(v.name) ? -30 : 0);
      return speechSynthesis.getVoices().filter((v) => v.lang.replace("_", "-").toLowerCase().startsWith(short)).sort((x, y) => score(y) - score(x));
    },
    pick() {
      const list = this.voices();
      return list.find((v) => v.name === this.cfg.voice) || list[0] || null;
    },

    /** A short two-note chime before the words, up for good news, down for bad. */
    chime(good) {
      const ctx = this.ctx;
      if (!ctx) return 0;
      if (ctx.state === "suspended") ctx.resume();
      const notes = good === false ? [784, 523] : [659, 988];
      notes.forEach((f, i) => {
        const o = ctx.createOscillator(), g = ctx.createGain(), t = ctx.currentTime + i * 0.14;
        o.type = "sine"; o.frequency.value = f;
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.25, t + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.35);
        o.connect(g).connect(ctx.destination); o.start(t); o.stop(t + 0.4);
      });
      return 380;
    },

    speak(text, force, good) {
      if ((!force && !this.cfg.enabled) || !text || !window.speechSynthesis) return;
      const say = () => {
        const u = new SpeechSynthesisUtterance(text);
        const voice = this.pick();
        u.lang = voice ? voice.lang : this.cfg.lang;
        if (voice) u.voice = voice;
        u.rate = +this.cfg.rate || 0.95; u.pitch = +this.cfg.pitch || 1; u.volume = this.cfg.volume != null ? +this.cfg.volume : 1;
        this.current = u; // Chrome drops an utterance nothing holds on to
        if (speechSynthesis.paused) speechSynthesis.resume();
        speechSynthesis.speak(u);
      };
      const go = () => { const wait = this.cfg.chime ? this.chime(good) : 0; if (wait) setTimeout(say, wait); else say(); };
      // The voice list loads late on first use: without it the browser reads with a voice of another language.
      if (!speechSynthesis.getVoices().length) {
        let done = false;
        const once = () => { if (!done) { done = true; go(); } };
        speechSynthesis.addEventListener("voiceschanged", once, { once: true });
        setTimeout(once, 800);
      } else go();
    },

    /** Phones only let a page make sound after a tap: the first tap opens the audio and voice. */
    unlock() {
      if (this.unlocked) return;
      this.unlocked = true;
      try { const AC = window.AudioContext || window.webkitAudioContext; if (AC) this.ctx = new AC(); } catch { /* no audio */ }
      if (!window.speechSynthesis) return;
      const u = new SpeechSynthesisUtterance(" ");
      u.volume = 0;
      speechSynthesis.speak(u);
    },

    /** How a symbol is said: "vàng" rather than X-A-U-U-S-D. */
    spokenSymbol(sym) {
      const s = String(sym || "").toUpperCase(), vi = this.vi();
      if (/XAU|GOLD/.test(s)) return vi ? "vàng" : "gold";
      if (/XAG|SILVER/.test(s)) return vi ? "bạc" : "silver";
      if (/BTC/.test(s)) return "bitcoin";
      if (/ETH/.test(s)) return "ethereum";
      if (/USTEC|NAS/.test(s)) return "Nasdaq";
      return s.replace(/M$/, "").replace(/^([A-Z]{3})([A-Z]{3})$/, "$1 $2");
    },
    /** A price as it is read: two decimals, with a comma in Vietnamese. */
    spokenPrice(v) {
      const t = (Math.round(v * 100) / 100).toFixed(2).replace(/\.?0+$/, "");
      return this.vi() ? t.replace(".", ",") : t;
    },
    spokenMoney(v) {
      const n = Math.round(Math.abs(v));
      return this.vi() ? `${v >= 0 ? "lời" : "lỗ"} ${n} đô` : `${v >= 0 ? "plus" : "minus"} ${n} dollars`;
    },

    /** Spoken, plus a toast and (with the tab in the background) a browser notification. */
    alert(spoken, title, body, good) {
      this.speak(spoken, false, good);
      if (this.cfg.popup) toast(`${title}: ${body}`, good === false);
      if (this.cfg.notify && document.hidden && window.Notification && Notification.permission === "granted") {
        try { new Notification(title, { body, icon: "favicon.svg" }); } catch { /* not allowed here */ }
      }
    },
  };
  if (window.speechSynthesis) speechSynthesis.getVoices(); // starts loading the list
  document.addEventListener("pointerdown", () => Voice.unlock(), { once: true, capture: true });

  /* ---------------- chart look and light / dark theme ---------------- */

  function defaultChartStyle() {
    return { theme: "dark", up: "#14b88a", down: "#f0455a", wickUp: "#14b88a", wickDown: "#f0455a", border: false, borderUp: "#14b88a", borderDown: "#f0455a",
      customBg: false, bg: "#151c2a", vGrid: true, hGrid: true, grid: "#1a2233", crosshairMagnet: false, seconds: false };
  }
  function loadChartStyle() {
    try { return Object.assign(defaultChartStyle(), JSON.parse(store.get("aurum.chartStyle") || "{}")); } catch { return defaultChartStyle(); }
  }
  function applyTheme(theme) {
    const dark = theme === "auto" ? !(window.matchMedia && matchMedia("(prefers-color-scheme: light)").matches) : theme !== "light";
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = dark ? "#0b0f17" : "#f5f6f8";
    const b = $("themeBtn");
    if (b) b.textContent = dark ? "☀︎" : "☾";
  }
  applyTheme(loadChartStyle().theme);

  /* ---------------- drawing toolbar icons ---------------- */

  const svg = (body) => `<svg viewBox="0 0 28 28" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
  const dot = (x, y) => `<circle cx="${x}" cy="${y}" r="1.8" fill="currentColor"/>`;
  const TOOL_ICON = {
    trendLine: svg(`<path d="M6 22 22 6"/>${dot(6, 22)}${dot(22, 6)}`),
    trendRay: svg(`<path d="M6 22 25 3"/>${dot(6, 22)}${dot(14, 14)}`),
    horizontalLine: svg(`<path d="M3 14h22"/>${dot(14, 14)}`),
    horizontalRay: svg(`<path d="M8 14h17"/>${dot(8, 14)}`),
    verticalLine: svg(`<path d="M14 3v22"/>${dot(14, 14)}`),
    arrow: svg(`<path d="M6 22 21 7"/><path d="M13 7h8v8"/>`),
    fibRetracement: svg(`<path d="M4 6h20M4 11h20M4 16h20M4 22h20"/>${dot(6, 22)}${dot(22, 6)}`),
    fibExtension: svg(`<path d="M4 6h20M4 12h20M4 19h20"/><path d="m5 24 6-8 5 5"/>`),
    elliottImpulse: svg(`<path d="m3 21 5-8 4 4 6-12 3 6 4-4"/>`),
    elliottCorrection: svg(`<path d="m4 7 7 12 6-7 7 10"/>`),
    headShoulders: svg(`<path d="m3 20 4-7 3 4 4-11 4 11 3-4 4 7"/>`),
    trianglePattern: svg(`<path d="m4 20 8-14 5 10 7-8"/><path d="M4 20 24 8" stroke-dasharray="2 2"/>`),
    path: svg(`<path d="M4 20c4-10 8 4 12-6s6-6 8-8"/>`),
    longPosition: svg(`<rect x="5" y="5" width="18" height="9" fill="currentColor" fill-opacity=".25"/><rect x="5" y="14" width="18" height="8"/><path d="M5 14h18"/>`),
    shortPosition: svg(`<rect x="5" y="6" width="18" height="8"/><rect x="5" y="14" width="18" height="9" fill="currentColor" fill-opacity=".25"/><path d="M5 14h18"/>`),
    priceRange: svg(`<path d="M14 4v20M10 8l4-4 4 4M10 20l4 4 4-4M6 4h16M6 24h16"/>`),
    fixedRangeVolume: svg(`<path d="M5 5v18M5 7h8M5 11h14M5 15h10M5 19h6"/>`),
    anchoredVolume: svg(`<path d="M5 5v18M5 9h12M5 13h16M5 17h9"/>${dot(5, 23)}`),
    brush: svg(`<path d="M5 22c3 0 4-2 4-4l9-11 3 3-11 9c-2 0-3 1-5 3Z"/>`),
    rectangle: svg(`<rect x="5" y="8" width="18" height="12"/>${dot(5, 8)}${dot(23, 20)}`),
    ellipse: svg(`<ellipse cx="14" cy="14" rx="10" ry="7"/>`),
    arrowMarker: svg(`<path d="M5 14h14M14 8l6 6-6 6"/>`),
    text: svg(`<path d="M7 7h14M14 7v15M11 22h6"/>`),
  };
  const RAIL_ICON = {
    cursor: svg(`<path d="M14 4v20M4 14h20"/>`),
    zoom: svg(`<circle cx="12" cy="12" r="7"/><path d="m17 17 6 6M12 9v6M9 12h6"/>`),
    magnet: svg(`<path d="M7 5v9a7 7 0 0 0 14 0V5h-4v9a3 3 0 0 1-6 0V5Z"/><path d="M7 9h4M17 9h4"/>`),
    keep: svg(`<path d="M6 21c2 0 3-1 3-3l8-9 2 2-8 8c-1 0-2 1-3 3Z"/><rect x="17" y="17" width="7" height="6" rx="1"/><path d="M18.5 17v-2a2 2 0 0 1 4 0v2"/>`),
    lock: svg(`<rect x="7" y="13" width="14" height="10" rx="2"/><path d="M10 13V9a4 4 0 0 1 8 0v4"/>`),
    unlock: svg(`<rect x="7" y="13" width="14" height="10" rx="2"/><path d="M10 13V9a4 4 0 0 1 8 0"/>`),
    eye: svg(`<path d="M3 14s4-7 11-7 11 7 11 7-4 7-11 7S3 14 3 14Z"/><circle cx="14" cy="14" r="3"/>`),
    eyeOff: svg(`<path d="M3 14s4-7 11-7 11 7 11 7-4 7-11 7S3 14 3 14Z"/><path d="m5 5 18 18"/>`),
    trash: svg(`<path d="M6 8h16M11 8V5h6v3M8 8l1 15h10l1-15"/>`),
  };
  /* Line icons of the drawing bar (18px, stroke = text colour). */
  const svgI = (d) => `<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
  const BAR_ICON = {
    tpl: svgI('<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><path d="M16.5 13.5v6M13.5 16.5h6"/>'),
    settings: svgI('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
    lock: svgI('<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>'),
    unlock: svgI('<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 7.5-2"/>'),
    del: svgI('<path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6.5 7l1 12a1.5 1.5 0 0 0 1.5 1.4h6a1.5 1.5 0 0 0 1.5-1.4l1-12M10 11v6M14 11v6"/>'),
    close: svgI('<path d="M6 6l12 12M18 6L6 18"/>'),
    chev: '<svg viewBox="0 0 10 6" width="9" height="6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M1 1l4 4 4-4"/></svg>',
  };
  /** The colours offered for drawings: TradingView-like rows, then a custom one. */
  const DRAW_PALETTE = ["#2962ff", "#089981", "#f23645", "#ff9800", "#9c27b0", "#00bcd4", "#e91e63", "#f2c14e",
    "#4caf50", "#673ab7", "#795548", "#ffeb3b", "#ffffff", "#b2b5be", "#787b86", "#131722"];
  const linePreview = (width, style) => `<svg width="34" height="10" viewBox="0 0 34 10"><line x1="1" y1="5" x2="33" y2="5" stroke="currentColor" stroke-width="${Math.max(1, width)}" stroke-linecap="round" ${style === "dashed" ? 'stroke-dasharray="6 4"' : style === "dotted" ? 'stroke-dasharray="1 4"' : ""}/></svg>`;

  const RAIL_GROUPS = [
    { id: "lines", title: "Công cụ đường", tools: ["trendLine", "trendRay", "horizontalLine", "horizontalRay", "verticalLine", "arrow"] },
    { id: "fib", title: "Gann và Fibonacci", tools: ["fibRetracement", "fibExtension"] },
    { id: "patterns", title: "Mô hình", tools: ["elliottImpulse", "elliottCorrection", "headShoulders", "trianglePattern", "path"] },
    { id: "forecast", title: "Dự đoán và đo lường", tools: ["longPosition", "shortPosition", "priceRange", "fixedRangeVolume", "anchoredVolume"] },
    { id: "shapes", title: "Hình học", tools: ["brush", "rectangle", "ellipse", "arrowMarker"] },
    { id: "text", title: "Văn bản", tools: ["text"] },
  ];

  /* ---------------- the terminal ---------------- */

  const Member = {
    role: store.get("aurum.role") || "member",
    secret: null,
    base: store.get("aurum.url"),
    loginMode: "member",
    lastLookup: 0,
    timers: [],
    tab: "chart",
    me: null,
    features: {},
    // chart
    chart: null, series: null, socket: null, pollTimer: null,
    source: "exness", interval: TFS.includes(store.get("aurum.tf")) ? store.get("aurum.tf") : "1m",
    symbol: store.get("aurum.sym"), digits: 2, bars: [], bid: null, ask: null,
    ict: null, loadingOlder: false, noOlder: false,
    lines: new Map(),
    // trading
    account: null, positions: [], orders: [], signals: [],
    selected: null, draft: null, drag: null,
    news: null, newsTime: 0,
    histRange: "today",

    init() {
      this.secret = this.role === "owner" ? ownerStore.get() : store.get("aurum.code");
    },

    show() {
      if (this.secret && this.base) this.openDash(); else this.openLogin();
    },
    hide() { this.stop(); },

    setLoginMode(mode) {
      this.loginMode = mode;
      const owner = mode === "owner";
      $("codeInput").hidden = owner;
      $("passInput").hidden = !owner;
      $("rememberRow").hidden = !owner;
      $("loginHint").textContent = owner ? "Chủ máy chủ: nhập mật khẩu máy chủ" : "Nhập mã mời để xem tín hiệu";
      $("loginBtn").textContent = owner ? "Vào trang chủ" : "Vào xem tín hiệu";
      $("modeBtn").textContent = owner ? "Tôi là thành viên (có mã mời)" : "Đăng nhập chủ";
      $("loginError").textContent = "";
      setTimeout(() => (owner ? $("passInput") : $("codeInput")).focus(), 50);
    },

    openLogin(message) {
      this.stop();
      $("logoutBtn").hidden = true;
      $("posPill").hidden = true;
      this.known = null; this.knownSignals = null;
      $("tabs").innerHTML = "";
      $("loginView").hidden = false;
      $("dashView").hidden = true;
      this.setLoginMode(this.loginMode);
      $("loginError").textContent = message || "";
    },

    async login() {
      const owner = this.loginMode === "owner";
      const secret = owner ? $("passInput").value.trim() : $("codeInput").value.trim().toUpperCase();
      if (!secret) return;
      const btn = $("loginBtn"), label = btn.textContent;
      btn.disabled = true;
      btn.textContent = "Đang kết nối…";
      $("loginError").textContent = "";
      try {
        const base = await lookupAddress(secret, owner);
        if (!base) throw new Error(owner ? "Không tìm thấy máy chủ với mật khẩu này" : "Mã mời không đúng (hoặc chưa được kích hoạt)");
        await api(base, secret, owner ? "/status" : "/member/me");
        this.role = owner ? "owner" : "member";
        this.secret = secret;
        this.base = base;
        store.set("aurum.role", this.role);
        store.set("aurum.url", base);
        if (owner) { ownerStore.set(secret, $("rememberInput").checked); store.set("aurum.code", null); }
        else { store.set("aurum.code", secret); ownerStore.set(null); }
        $("codeInput").value = ""; $("passInput").value = "";
        this.openDash();
      } catch (e) {
        $("loginError").textContent = e instanceof Unreachable ? "Chưa kết nối được, thử lại sau ít phút" : e.message;
      } finally {
        btn.disabled = false;
        btn.textContent = label;
      }
    },

    logout(message) {
      this.secret = null; this.base = null;
      store.set("aurum.code", null); store.set("aurum.url", null); store.set("aurum.role", null);
      ownerStore.set(null);
      this.role = "member";
      this.openLogin(message);
    },

    get owner() { return this.role === "owner"; },

    tabList() {
      if (this.owner) {
        return [["chart", "Biểu đồ"], ["trade", "Lệnh"], ["history", "Lịch sử"], ["news", "Tin tức"],
          ["autobot", "Bot"], ["copy", "Copy"], ["members", "Thành viên"], ["bot", "Máy chủ"]];
      }
      const f = this.features || {};
      return [["chart", "Biểu đồ"], ["signals", "Tín hiệu"]]
        .concat(f.news !== false ? [["news", "Tin tức"]] : [])
        .concat(this.me && this.me.role === "copy" ? [["copy", "Copy lệnh"]] : []);
    },

    renderTabs() {
      const list = this.tabList();
      if (!list.some(([k]) => k === this.tab)) this.tab = "chart";
      $("tabs").innerHTML = list.map(([k, name]) => `<button type="button" data-tab="${k}" class="${k === this.tab ? "on" : ""}">${name}</button>`).join("");
      $("tabs").querySelectorAll("button").forEach((b) => (b.onclick = () => this.setTab(b.dataset.tab)));
      document.querySelectorAll("#dashView .tab").forEach((el) => { el.hidden = el.dataset.tab !== this.tab; });
    },

    setTab(tab) {
      this.tab = tab;
      store.set("aurum.tab", tab);
      this.renderTabs();
      if (tab === "chart" && this.chart) requestAnimationFrame(() => this.redraw());
      this.loadTab(true);
    },

    async openDash() {
      $("logoutBtn").hidden = false;
      $("loginView").hidden = true;
      $("dashView").hidden = false;
      this.tab = store.get("aurum.tab") || "chart";
      this.me = null;
      this.selected = null;
      this.draft = null;
      $("ticket").hidden = !this.owner;
      $("chartSymbol").disabled = !this.owner;
      // Not investment advice: the same note for everyone, under every chart.
      $("chartNote").textContent = "Biểu đồ, chỉ báo, tín hiệu và bot chỉ để tham khảo, không phải lời khuyên đầu tư. Giao dịch vàng, ngoại hối, tiền số có đòn bẩy rủi ro cao và có thể mất toàn bộ vốn; bạn tự chịu trách nhiệm với quyết định của mình.";
      if (!this.owner) {
        try { await this.refreshMe(); } catch (e) { if (this.handleAuth(e)) return; }
      }
      this.renderTabs();
      this.buildChart();
      await this.refresh();
      this.loadTab(true);
      this.loadNews();
      this.stop(false);
      this.timers.push(setInterval(() => this.refresh(), this.owner ? 2000 : 5000));
      this.timers.push(setInterval(() => this.loadTab(false), 5000));
      if (!this.owner) this.timers.push(setInterval(() => this.refreshMe().catch((e) => this.handleAuth(e)), 30000));
      this.timers.push(setInterval(() => this.loadNews(), 5 * 60 * 1000));
      if (this.owner) {
        const badge = () => {
          this.call("/status").then((st) => { this.botStatus = st; this.renderBotBadge(); }).catch(() => {});
          this.call("/stopbot").then((st) => { this.stopStatus = st; this.renderBotBadge(); }).catch(() => {});
        };
        badge();
        this.timers.push(setInterval(badge, 15000));
      }
      this.timers.push(setInterval(() => this.updateFlow(), 1000));
    },

    stop(all = true) {
      this.timers.forEach(clearInterval);
      this.timers = [];
      if (all) {
        clearInterval(this.pollTimer); this.pollTimer = null;
        if (this.socket) { this.socket.close(); this.socket = null; }
      }
    },

    /** One call; when the address moved, find the new one and try again. */
    async call(path, body) {
      try {
        return await api(this.base, this.secret, path, body);
      } catch (e) {
        if (!(e instanceof Unreachable) || Date.now() - this.lastLookup < 20000) throw e;
        this.lastLookup = Date.now();
        const moved = await lookupAddress(this.secret, this.owner).catch(() => null);
        if (!moved || moved === this.base) throw e;
        this.base = moved;
        store.set("aurum.url", moved);
        return api(this.base, this.secret, path, body);
      }
    },

    /** Signed out when the password / code stops working. */
    handleAuth(e) {
      if (e.status === 401 || (!this.owner && e.status === 403 && /khoá|hết hạn/.test(e.message))) {
        this.logout(this.owner ? "Mật khẩu không còn đúng" : (e.status === 403 ? plain(e.message) : "Mã mời không còn dùng được"));
        return true;
      }
      return false;
    },

    showError(e) {
      if (this.handleAuth(e)) return;
      $("dashError").textContent = e instanceof Unreachable ? "Chưa kết nối được, đang thử lại…" : plain(e.message);
      $("dashError").hidden = false;
    },

    async refreshMe() {
      const me = await this.call("/member/me");
      const changed = !this.me || this.me.role !== me.role || JSON.stringify(this.features) !== JSON.stringify(me.features || {});
      this.me = me;
      this.features = me.features || {};
      $("whoName").textContent = me.name;
      const until = me.expires ? " · hết hạn " + new Date(me.expires * 1000).toLocaleDateString("vi-VN") : " · không hết hạn";
      $("whoRole").textContent = (me.role === "copy" ? "Xem tín hiệu + copy lệnh" : "Xem tín hiệu") + until;
      if (changed && this.chart) { this.renderTabs(); this.computeICT(); this.redraw(); }
    },

    async refresh() {
      if (!this.secret) return;
      try {
        if (this.owner) await this.refreshOwner(); else await this.refreshSignals();
        $("dashError").hidden = true;
        this.syncLines();
      } catch (e) {
        this.showError(e);
      }
    },

    /* ----- owner: account, positions, orders ----- */

    async refreshOwner() {
      const sym = this.symbol;
      const t = await this.call("/mt5/trading");
      this.account = t;
      this.positions = t.positions || [];
      this.orders = t.orders || [];
      this.watchTrades(t);
      if (this.selected && !this.findSelected()) this.selected = null;
      $("whoName").textContent = "Chủ máy chủ";
      $("whoRole").innerHTML = t.login
        ? `#${t.login} · ${esc(t.server || "")} <span class="acct ${t.mode === "real" ? "real" : ""}" title="${t.mode === "real" ? "Tài khoản thật" : "Tài khoản demo"}">✦</span>`
        : "MT5 chưa đăng nhập";
      const floating = this.positions.reduce((a, p) => a + p.profit, 0);
      $("headEquity").innerHTML = t.equity != null
        ? `<span class="muted small">Vốn</span> <b>${money(t.equity)}</b> <span class="${floating >= 0 ? "pos" : "neg"}">${signed(floating)}</span>` : "";
      if (!sym && !this.symbol) await this.ownerSymbol();
      this.renderPill(floating);
      this.renderSelBar();
      this.syncLines2();
      if (this.tab === "trade") this.renderTrade();
    },

    renderPill(floating) {
      const mine = this.positions;
      const pill = $("posPill");
      if (!this.owner || !mine.length || this.replay) { pill.hidden = true; return; }
      const lots = mine.reduce((a, p) => a + p.lots, 0);
      pill.hidden = false;
      this.placePill();
      pill.innerHTML = `<span class="grip" title="Kéo để di chuyển · bấm đúp để trả về biểu đồ">⋮⋮</span><span class="go">${mine.length} lệnh · ${fmt(lots, 2)} lot · <b class="${floating >= 0 ? "pos" : "neg"}">${signed(floating)}</b></span><button type="button" class="x" title="Đóng tất cả">✕</button>`;
      pill.querySelector(".go").onclick = () => { if (!this.pillMoved) this.setTab("trade"); };
      pill.querySelector(".x").onclick = (e) => this.closeAll(e.currentTarget);
    },

    /** The pill floats where it was dragged to (anywhere on the page), or sits on the chart. */
    placePill() {
      const pill = $("posPill");
      let pos = null;
      try { pos = JSON.parse(store.get("aurum.pillPos") || "null"); } catch { pos = null; }
      if (!pos) {
        if (pill.parentElement !== $("chartWrap")) $("chartWrap").appendChild(pill);
        pill.classList.remove("floating"); pill.style.left = pill.style.top = "";
        return;
      }
      if (pill.parentElement !== document.body) document.body.appendChild(pill);
      pill.classList.add("floating");
      const w = pill.offsetWidth || 200, h = pill.offsetHeight || 34;
      pill.style.left = Math.max(4, Math.min(window.innerWidth - w - 4, pos.x * window.innerWidth)) + "px";
      pill.style.top = Math.max(4, Math.min(window.innerHeight - h - 4, pos.y * window.innerHeight)) + "px";
    },

    bindPill() {
      const pill = $("posPill");
      pill.addEventListener("pointerdown", (e) => {
        if (e.target.closest(".x") || e.button > 0) return;
        const r = pill.getBoundingClientRect(), dx = e.clientX - r.left, dy = e.clientY - r.top, x0 = e.clientX, y0 = e.clientY;
        let moving = false;
        this.pillMoved = false;
        const move = (ev) => {
          if (!moving && Math.hypot(ev.clientX - x0, ev.clientY - y0) < 5) return;
          if (!moving) {
            moving = true; this.pillMoved = true;
            document.body.appendChild(pill);
            pill.classList.add("floating", "dragging");
          }
          ev.preventDefault();
          pill.style.left = Math.max(4, Math.min(window.innerWidth - r.width - 4, ev.clientX - dx)) + "px";
          pill.style.top = Math.max(4, Math.min(window.innerHeight - r.height - 4, ev.clientY - dy)) + "px";
        };
        const up = () => {
          window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); window.removeEventListener("pointercancel", up);
          if (!moving) return;
          pill.classList.remove("dragging");
          const b = pill.getBoundingClientRect();
          store.set("aurum.pillPos", JSON.stringify({ x: b.left / window.innerWidth, y: b.top / window.innerHeight }));
          // The click that ends a drag does not open the Lệnh tab.
          setTimeout(() => (this.pillMoved = false), 0);
        };
        window.addEventListener("pointermove", move, { passive: false }); window.addEventListener("pointerup", up); window.addEventListener("pointercancel", up);
      });
      pill.addEventListener("dblclick", (e) => {
        if (e.target.closest(".x")) return;
        store.set("aurum.pillPos", null);
        this.placePill();
      });
      window.addEventListener("resize", () => { if (pill.classList.contains("floating")) this.placePill(); });
    },

    async closeAll(button) {
      const list = this.positions.slice();
      if (!list.length || !confirm(`Đóng tất cả ${list.length} lệnh đang mở?`)) return;
      await act(button, async () => {
        for (const p of list) await this.call("/mt5/close", { ticket: p.ticket });
      }, "Đã đóng tất cả lệnh");
      this.refresh();
    },

    renderTrade() {
      const t = this.account || {};
      const cur = t.currency || "USD";
      const floating = this.positions.reduce((a, p) => a + p.profit, 0);
      $("accountStats").innerHTML = [
        [`Lãi/lỗ đang chạy`, `<span class="${floating >= 0 ? "pos" : "neg"}">${signed(floating)}</span>`],
        [`Số dư (${cur})`, money(t.balance)], [`Vốn (${cur})`, money(t.equity)],
        ["Ký quỹ", money(t.margin)], ["Ký quỹ trống", money(t.marginFree)],
        ["Mức ký quỹ", t.marginLevel ? fmt(t.marginLevel, 0) + "%" : "–"],
        ["Đòn bẩy", t.leverage ? "1:" + t.leverage : "–"],
        ["Đặt lệnh từ web", t.tradingEnabled ? '<span class="pos">Bật</span>' : '<span class="neg">Tắt</span>'],
      ].map(([k, v]) => `<div class="stat"><span>${k}</span><b>${v}</b></div>`).join("");
      $("openTitle").textContent = this.positions.length ? `Lệnh đang mở · ${this.positions.length}` : "Lệnh đang mở";
      $("closeAllBtn").hidden = !this.positions.length;
      $("openList").innerHTML = this.positions.length
        ? this.positions.map((p) => this.positionRow(p)).join("") : '<div class="empty">Không có lệnh đang mở</div>';
      $("openList").querySelectorAll("[data-ticket]").forEach((row) => {
        const p = this.positions.find((x) => x.ticket === +row.dataset.ticket);
        row.onclick = () => this.positionSheet(p);
        row.querySelector(".x").onclick = async (e) => {
          e.stopPropagation();
          await act(e.currentTarget, () => this.call("/mt5/close", { ticket: p.ticket }), "Đã đóng lệnh");
          this.refresh();
        };
      });
      $("ordersPanel").hidden = !this.orders.length;
      $("ordersList").innerHTML = this.orders.map((o) => this.orderRow(o)).join("");
      $("ordersList").querySelectorAll("[data-ticket]").forEach((row) => {
        const o = this.orders.find((x) => x.ticket === +row.dataset.ticket);
        row.onclick = () => this.orderSheet(o);
        row.querySelector(".x").onclick = async (e) => {
          e.stopPropagation();
          await act(e.currentTarget, () => this.call("/mt5/cancel", { ticket: o.ticket }), "Đã huỷ lệnh chờ");
          this.refresh();
        };
      });
    },

    positionRow(p) {
      const buy = p.side === "long";
      return `<div class="sig clickable" data-ticket="${p.ticket}">
        <div class="bar" style="background:${buy ? "#2b6bf3" : "var(--down)"}"></div>
        <div>
          <div class="top"><span class="sym">${esc(p.symbol)}</span><span class="side ${buy ? "buy" : "sell"}">${sideName(p.side)} ${p.lots}</span>
            <span class="muted small">${fmt(p.entry, this.digitsFor(p.symbol))} → ${fmt(p.price, this.digitsFor(p.symbol))}</span></div>
          <div class="lv">SL ${p.stop ? fmt(p.stop, this.digitsFor(p.symbol)) : "–"} · TP ${p.target ? fmt(p.target, this.digitsFor(p.symbol)) : "–"} · ${clock(p.time)}${p.bot ? " · bot" : ""}</div>
        </div>
        <div class="right"><div class="move ${p.profit >= 0 ? "pos" : "neg"}">${signed(p.profit)}</div></div>
        <button class="x" type="button" title="Đóng lệnh">✕</button>
      </div>`;
    },

    orderRow(o) {
      const buy = o.side === "long";
      return `<div class="sig clickable" data-ticket="${o.ticket}">
        <div class="bar" style="background:${buy ? "#2b6bf3" : "var(--down)"};opacity:.5"></div>
        <div>
          <div class="top"><span class="sym">${esc(o.symbol)}</span><span class="side ${buy ? "buy" : "sell"}">${sideName(o.side)} ${o.kind.toUpperCase()}</span>
            <span>${o.lots} lot @ ${fmt(o.entry, this.digitsFor(o.symbol))}</span></div>
          <div class="lv">SL ${o.stop ? fmt(o.stop, this.digitsFor(o.symbol)) : "–"} · TP ${o.target ? fmt(o.target, this.digitsFor(o.symbol)) : "–"} · ${clock(o.time)}</div>
        </div>
        <div class="right"></div>
        <button class="x" type="button" title="Huỷ lệnh chờ">✕</button>
      </div>`;
    },

    digitsFor(symbol) { return symbol === this.symbol ? this.digits : (/JPY/.test(symbol) ? 3 : (/XAU|XAG|US30|USTEC|NAS|BTC/.test(symbol) ? 2 : 5)); },

    positionSheet(p) {
      if (!p) return;
      const d = this.digitsFor(p.symbol);
      sheet.open(`<h3>${sideName(p.side)} ${p.lots} ${esc(p.symbol)} <span class="muted small">#${p.ticket}</span></h3>
        <p class="muted small">Vào ${fmt(p.entry, d)} · giá ${fmt(p.price, d)} · ${fullTime(p.time)}</p>
        <p class="big ${p.profit >= 0 ? "pos" : "neg"}">${signed(p.profit)} ${esc((this.account || {}).currency || "USD")}</p>
        <div class="fields two">
          <label>SL<input id="sStop" inputmode="decimal" value="${p.stop ? fmt(p.stop, d) : ""}" placeholder="không"></label>
          <label>TP<input id="sTarget" inputmode="decimal" value="${p.target ? fmt(p.target, d) : ""}" placeholder="không"></label>
        </div>
        <button class="btn btn-ghost wide" id="sSave">Lưu SL/TP</button>
        <h4>Đóng lệnh</h4>
        <div class="fields"><label>Số lot đóng<input id="sLots" inputmode="decimal" value="${p.lots}"></label></div>
        <div class="chips" id="sChips">${[0.25, 0.5, 0.75, 1].map((f) => `<button type="button" data-f="${f}">${f === 1 ? "Tất cả" : f * 100 + "%"}</button>`).join("")}</div>
        <button class="btn wide ${p.side === "long" ? "sellbg" : "buybg"}" id="sClose">Đóng ${p.lots} lot</button>`, (el) => {
        const lots = el.querySelector("#sLots"), closeBtn = el.querySelector("#sClose");
        const label = () => { closeBtn.textContent = `Đóng ${lots.value || 0} lot${+lots.value >= p.lots ? " (cả lệnh)" : ""}`; };
        lots.oninput = label;
        el.querySelectorAll("#sChips button").forEach((b) => (b.onclick = () => {
          lots.value = Math.max(0.01, Math.floor(p.lots * +b.dataset.f * 100 + 1e-9) / 100).toFixed(2);
          label();
        }));
        el.querySelector("#sSave").onclick = async (e) => {
          const wrong = this.stopsProblem(p, num(el.querySelector("#sStop").value), num(el.querySelector("#sTarget").value));
          if (wrong) return toast(wrong, true);
          const ok = await act(e.currentTarget, () => this.call("/mt5/modify", { ticket: p.ticket, stop: num(el.querySelector("#sStop").value), target: num(el.querySelector("#sTarget").value) }), "Đã lưu SL/TP");
          if (ok) { sheet.close(); this.refresh(); }
        };
        closeBtn.onclick = async (e) => {
          const v = num(lots.value);
          if (!v || v <= 0) return toast("Số lot không hợp lệ", true);
          const ok = await act(e.currentTarget, () => this.call("/mt5/close", { ticket: p.ticket, lots: Math.min(v, p.lots) }), v >= p.lots ? "Đã đóng lệnh" : `Đã đóng ${v} lot`);
          if (ok) { sheet.close(); this.refresh(); }
        };
      });
    },

    orderSheet(o) {
      if (!o) return;
      const d = this.digitsFor(o.symbol);
      sheet.open(`<h3>${sideName(o.side)} ${o.kind.toUpperCase()} ${o.lots} ${esc(o.symbol)} <span class="muted small">#${o.ticket}</span></h3>
        <div class="fields">
          <label>Giá<input id="oPrice" inputmode="decimal" value="${fmt(o.entry, d)}"></label>
          <label>SL<input id="oStop" inputmode="decimal" value="${o.stop ? fmt(o.stop, d) : ""}" placeholder="không"></label>
          <label>TP<input id="oTarget" inputmode="decimal" value="${o.target ? fmt(o.target, d) : ""}" placeholder="không"></label>
        </div>
        <button class="btn btn-gold wide" id="oSave">Lưu</button>
        <button class="btn btn-ghost wide" id="oCancel">Huỷ lệnh chờ</button>`, (el) => {
        el.querySelector("#oSave").onclick = async (e) => {
          const ok = await act(e.currentTarget, () => this.call("/mt5/modify", { ticket: o.ticket, price: num(el.querySelector("#oPrice").value), stop: num(el.querySelector("#oStop").value), target: num(el.querySelector("#oTarget").value) }), "Đã sửa lệnh chờ");
          if (ok) { sheet.close(); this.refresh(); }
        };
        el.querySelector("#oCancel").onclick = async (e) => {
          const ok = await act(e.currentTarget, () => this.call("/mt5/cancel", { ticket: o.ticket }), "Đã huỷ lệnh chờ");
          if (ok) { sheet.close(); this.refresh(); }
        };
      });
    },

    /* ----- order ticket ----- */

    lots() { return clampLots(num($("lotInput").value)); },

    /** − / + on a lot box: 0.01 a step under 1 lot, 0.1 under 10, then 1. */
    stepLots(input, dir, key) {
      const v = clampLots(num(input.value));
      const step = dir > 0 ? (v < 1 ? 0.01 : v < 10 ? 0.1 : 1) : (v <= 1 ? 0.01 : v <= 10 ? 0.1 : 1);
      input.value = clampLots(v + step * dir).toFixed(2);
      store.set(key, input.value);
      if (this.draft) this.updatePendingLabels();
    },

    /** Lot choices under a lot box, up to the most allowed (200 lot, or the server's limit). */
    lotMenu(input, key) {
      const menu = $("ctxMenu");
      const serverMax = this.owner && this.account && this.account.maxLots ? +this.account.maxLots : null;
      const max = Math.min(MAX_LOTS, serverMax || MAX_LOTS);
      const list = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200];
      const cur = clampLots(num(input.value));
      menu.innerHTML = `<div class="lot-menu">${list.map((v) => `<button type="button" data-v="${v}" class="${cur === v ? "on" : ""} ${v > max ? "over" : ""}" ${v > max ? `title="Vượt giới hạn máy chủ ${max} lot"` : ""}>${v}</button>`).join("")}
        <button type="button" data-v="${max}" class="max">MAX · ${max} lot</button></div>
        ${serverMax && serverMax < MAX_LOTS ? `<p class="muted small lot-note">Máy chủ đang cho tối đa ${serverMax} lot mỗi lệnh.</p><button type="button" class="lot-raise" data-raise>Nâng giới hạn máy chủ lên ${MAX_LOTS} lot</button>` : `<p class="muted small lot-note">Tối đa ${MAX_LOTS} lot mỗi lệnh.</p>`}`;
      menu.hidden = false;
      const r = input.getBoundingClientRect();
      menu.style.left = Math.max(8, Math.min(r.left - 60, window.innerWidth - menu.offsetWidth - 8)) + "px";
      menu.style.top = Math.min(r.bottom + 6, window.innerHeight - menu.offsetHeight - 8) + "px";
      menu.querySelectorAll("[data-v]").forEach((b) => (b.onclick = () => {
        input.value = clampLots(+b.dataset.v).toFixed(2);
        store.set(key, input.value);
        this.closeMenu();
        if (this.draft) this.updatePendingLabels();
        if (+b.dataset.v > max) toast(`Máy chủ chỉ cho tối đa ${max} lot mỗi lệnh: lệnh ${b.dataset.v} lot sẽ bị từ chối`, true);
      }));
      const raise = menu.querySelector("[data-raise]");
      if (raise) raise.onclick = async () => {
        if (!confirm(`Cho phép đặt tới ${MAX_LOTS} lot mỗi lệnh? Khối lượng lớn rủi ro rất cao.`)) return;
        const t = this.account || {};
        const res = await act(raise, () => this.call("/mt5/settings", { trading_enabled: !!t.tradingEnabled, allow_real_account: !!t.allowReal, max_lots: MAX_LOTS }), "Đã nâng giới hạn");
        if (res) { this.account = Object.assign({}, this.account, { maxLots: res.maxLots }); this.closeMenu(); if (res.maxLots < MAX_LOTS) toast(`Máy chủ chỉ nhận tới ${res.maxLots} lot: cập nhật máy chủ lên bản 3.0`, true); }
      };
    },

    async marketOrder(side, button, symbol = this.symbol, lots = this.lots()) {
      if (this.replay) return this.replayOrder(side);
      if (!symbol) return;
      const body = { symbol, side, type: "market", lots };
      const ok = await act(button, () => this.call("/mt5/order", body), `Đã ${side === "long" ? "MUA" : "BÁN"} ${body.lots} ${symbol}`);
      if (ok) this.refresh();
    },

    /** The pending draft is one purple line: under the price it buys, above it sells (a Stop order the other way). */
    draftSide(price) {
      const last = this.bars.length ? this.bars[this.bars.length - 1].close : price;
      const mid = this.bid != null && this.ask != null ? (this.bid + this.ask) / 2 : last;
      const below = price < mid;
      return $("pStopType").checked ? (below ? "short" : "long") : (below ? "long" : "short");
    },

    pendingKind(side) { return (side === "long" ? "BUY " : "SELL ") + ($("pStopType").checked ? "STOP" : "LIMIT"); },

    updatePendingLabels() {
      const price = num($("pPrice").value);
      if (price == null) return;
      const side = this.draftSide(price), kind = this.pendingKind(side);
      $("pendKind").textContent = kind;
      const b = $("pPlace");
      b.textContent = `Đặt ${kind} ${this.lots().toFixed(2)}`;
      b.className = "btn btn-small pend " + (side === "long" ? "buy" : "sell");
      this.renderDraftBar(price, side, kind);
    },

    /** The pending order being set up, confirmed right on the chart (the full form is under it). */
    renderDraftBar(price, side, kind) {
      const bar = $("draftBar");
      if (!this.draft || price == null) { bar.hidden = true; return; }
      const sl = num($("pStop").value), tp = num($("pTarget").value), lots = this.lots();
      const money = (lv) => (lv == null ? "" : ` <span class="${(this.valueAt(this.symbol, lots, side, price, lv) || 0) >= 0 ? "pos" : "neg"}">${money0(this.valueAt(this.symbol, lots, side, price, lv))}</span>`);
      bar.hidden = false;
      bar.innerHTML = `<span class="dk ${side === "long" ? "buy" : "sell"}">${kind}</span>
        <span><b>${lots.toFixed(2)}</b> @ <b>${fmt(price, this.digits)}</b></span>
        <span class="muted">SL ${sl != null ? fmt(sl, this.digits) + money(sl) : "–"} · TP ${tp != null ? fmt(tp, this.digits) + money(tp) : "–"}</span>
        <button type="button" class="go ${side === "long" ? "buy" : "sell"}" data-a="place">Đặt lệnh</button>
        <button type="button" class="x" data-a="cancel" title="Huỷ">✕</button>`;
      bar.querySelector("[data-a=place]").onclick = (e) => this.pendingOrder(e.currentTarget);
      bar.querySelector("[data-a=cancel]").onclick = () => this.togglePending(false);
    },

    /** SL and TP keep their distances from the entry, on the order's side. */
    placeDraftStops() {
      const price = num($("pPrice").value);
      if (price == null || !this.draftDist) return;
      const long = this.draftSide(price) === "long";
      $("pStop").value = this.draftDist.risk ? fmt(price + (long ? -1 : 1) * this.draftDist.risk, this.digits) : "";
      $("pTarget").value = this.draftDist.reward ? fmt(price + (long ? 1 : -1) * this.draftDist.reward, this.digits) : "";
    },

    readDraftDist() {
      const p = num($("pPrice").value), sl = num($("pStop").value), tp = num($("pTarget").value);
      this.draftDist = { risk: sl != null && p != null ? Math.abs(p - sl) : 0, reward: tp != null && p != null ? Math.abs(tp - p) : 0 };
    },

    async pendingOrder(button) {
      if (this.replay) return toast("Replay chỉ có lệnh thị trường (BUY/SELL trên thanh replay)", true);
      const price = num($("pPrice").value);
      if (!price) return toast("Kéo đường tím tới giá muốn đặt", true);
      const side = this.draftSide(price);
      const body = { symbol: this.symbol, side, type: "pending", price, lots: this.lots(), stop: num($("pStop").value), target: num($("pTarget").value) };
      const kind = this.pendingKind(side);
      const ok = await act(button, () => this.call("/mt5/order", body), `Đã đặt ${kind} ${body.lots} @ ${fmt(price, this.digits)}`);
      if (ok) { this.togglePending(false); this.refresh(); }
    },

    togglePending(open) {
      const box = $("pendingBox");
      open = open === undefined ? box.hidden : open;
      if (open && this.replay) return toast("Thoát replay để đặt lệnh chờ", true);
      box.hidden = !open;
      $("pendingToggle").classList.toggle("on", open);
      $("pendingLabel").textContent = open ? "Huỷ lệnh chờ" : "Lệnh chờ";
      if (open) {
        const tail = this.bars.slice(-30);
        const last = this.bars.length ? this.bars[this.bars.length - 1].close : null;
        const r = tail.length ? tail.reduce((a, b) => a + b.high - b.low, 0) / tail.length : (last || 1) * 0.0005;
        if (!num($("pPrice").value) && last) $("pPrice").value = fmt(last - r * 3, this.digits);
        if (!this.draftDist) this.draftDist = { risk: +(r * 3).toFixed(this.digits), reward: +(r * 6).toFixed(this.digits) };
        this.draft = true;
        this.placeDraftStops();
      } else {
        this.draft = null;
        $("pPrice").value = ""; $("pStop").value = ""; $("pTarget").value = "";
        $("draftBar").hidden = true;
      }
      this.updatePendingLabels();
      this.syncLines();
    },

    /* ----- members: signals ----- */

    async refreshSignals() {
      const list = await this.call("/member/signals?limit=80");
      this.signals = list.signals || [];
      this.watchSignals(this.signals);
      if (this.tab === "signals") this.renderSignals();
    },

    /* ----- voice alerts ----- */

    /** New fills and closes since the last look (the first look only learns what is there, like the app). */
    watchTrades(t) {
      const deals = t.deals || [], positions = t.positions || [];
      const known = this.known;
      this.known = { deals: new Set(deals.map((d) => d.ticket)), positions: new Set(positions.map((p) => p.ticket)) };
      if (!known || known.login !== t.login) { this.known.login = t.login; return; }
      this.known.login = t.login;
      const vi = Voice.vi(), d2 = (sym) => this.digitsFor(sym);
      positions.filter((p) => !known.positions.has(p.ticket)).forEach((p) => {
        let text = Voice.phrase("entry");
        if (Voice.cfg.details) text += `, ${p.side === "long" ? (vi ? "mua" : "buy") : (vi ? "bán" : "sell")} ${Voice.spokenSymbol(p.symbol)} ${Voice.spokenPrice(p.entry)}`;
        Voice.alert(text, "Lệnh đã khớp", `${sideName(p.side)} ${p.lots} lot ${p.symbol} @ ${fmt(p.entry, d2(p.symbol))}`, true);
      });
      deals.filter((d) => !known.deals.has(d.ticket)).forEach((d) => {
        const manual = d.reason !== "target" && d.reason !== "stop";
        let text = manual ? Voice.defaults().closed : Voice.phrase(d.reason);
        if (Voice.cfg.details) text += `, ${Voice.spokenSymbol(d.symbol)}, ${Voice.spokenMoney(d.profit)}`;
        const title = manual ? "Đã đóng lệnh" : d.reason === "target" ? "Chạm TP (Target fill)" : "Chạm SL (Stop loss fill)";
        Voice.alert(text, title, `${d.symbol} ${signed(d.profit)} ${t.currency || "USD"}`, d.profit >= 0);
      });
    },

    /** Members: a new signal, and a signal closing in profit (TP) or at a loss (SL). */
    watchSignals(list) {
      const before = this.knownSignals;
      this.knownSignals = new Map(list.map((x) => [x.id, x.status]));
      if (!before) return;
      const vi = Voice.vi();
      list.forEach((x) => {
        const was = before.get(x.id);
        if (was == null && x.status === "open") {
          Voice.alert(Voice.phrase(x.side === "long" ? "buy" : "sell") + (Voice.cfg.details ? `, ${Voice.spokenSymbol(x.symbol)} ${Voice.spokenPrice(x.entry)}` : ""), "Tín hiệu mới", `${x.side === "long" ? "MUA" : "BÁN"} ${x.symbol} @ ${fmt(x.entry)}`, true);
        } else if (was === "open" && x.status !== "open") {
          const win = (x.result || 0) > 0;
          let text = Voice.phrase(win ? "target" : "stop");
          if (Voice.cfg.details && x.result != null) text += `, ${Voice.spokenSymbol(x.symbol)}, ${vi ? (win ? "lời" : "lỗ") : (win ? "plus" : "minus")} ${Voice.spokenPrice(Math.abs(x.result))} ${vi ? "giá" : "points"}`;
          Voice.alert(text, win ? "Tín hiệu chạm TP" : "Tín hiệu chạm SL", `${x.symbol} ${x.result != null ? signed(x.result) : ""}`, win);
        }
      });
    },

    voiceSheet() {
      const c = Voice.cfg;
      const phraseRow = (key, label) => `<label class="fr"><span class="grow">${label}</span><input class="nm" data-p="${key}" data-t="str" value="${esc(c[key] || "")}" placeholder="${esc(Voice.defaults()[key])}"></label>`;
      const quality = (v) => (/natural|neural|premium|enhanced|nâng cao/i.test(v.name) ? " ★ tự nhiên" : /google|online/i.test(v.name) ? " ☆ trực tuyến" : "");
      const render = () => {
        const k = fieldKit(c);
        const can = !!window.speechSynthesis;
        const voices = Voice.voices();
        const best = voices[0];
        const voiceOpts = [["", `Tự chọn giọng rõ nhất${best ? ` (${best.name})` : ""}`]].concat(voices.map((v) => [v.name, `${v.name} · ${v.lang}${quality(v)}`]));
        const noVoice = can && speechSynthesis.getVoices().length && !voices.length;
        return k.head("Giọng nói") + (can ? "" : k.note("Trình duyệt này không đọc được giọng nói."))
          + k.tog("enabled", "Đọc cảnh báo bằng giọng nói")
          + `<label class="fr"><span class="grow">Ngôn ngữ</span>${k.selI("lang", [["vi-VN", "Tiếng Việt"], ["en-US", "Tiếng Anh (Mỹ)"], ["en-GB", "Tiếng Anh (Anh)"], ["en-AU", "Tiếng Anh (Úc)"]])}</label>`
          + `<label class="fr"><span class="grow">Giọng</span>${k.selI("voice", voiceOpts).replace("<select", '<select class="voice-sel"')}</label>`
          + (noVoice ? k.note("Máy này chưa có giọng cho ngôn ngữ này. Windows: Cài đặt → Thời gian & ngôn ngữ → Giọng nói → Thêm giọng. iPhone: Cài đặt → Trợ năng → Nội dung được đọc → Giọng nói (chọn bản Nâng cao). Android: Cài đặt → Chuyển văn bản thành giọng nói → Google.") : "")
          + k.sel("rate", "Tốc độ", [[0.75, "Rất chậm"], [0.85, "Chậm, rõ"], [0.95, "Vừa"], [1.05, "Hơi nhanh"], [1.2, "Nhanh"]])
          + k.sel("pitch", "Độ cao giọng", [[0.8, "Trầm"], [1, "Bình thường"], [1.2, "Cao"]])
          + k.sel("volume", "Âm lượng", [[0.5, "Nhỏ"], [0.8, "Vừa"], [1, "Lớn nhất"]])
          + k.tog("chime", "Chuông báo trước khi đọc (lên = tốt, xuống = xấu)")
          + `<div class="fr wrap"><button type="button" class="btn btn-ghost btn-small" data-try>▶ Nghe thử giọng này</button></div>`
          + k.note("Giọng có ★ đọc tự nhiên và rõ nhất. Trên máy tính, Edge có nhiều giọng tự nhiên nhất (cả tiếng Việt: HoaiMy, NamMinh); Chrome có giọng Google.")
          + k.head("Câu đọc khi")
          + phraseRow("target", "Chạm TP") + phraseRow("stop", "Chạm SL") + phraseRow("entry", "Lệnh khớp")
          + (this.owner ? "" : phraseRow("buy", "Tín hiệu MUA") + phraseRow("sell", "Tín hiệu BÁN"))
          + k.tog("details", "Đọc thêm mã, giá, số tiền lãi/lỗ")
          + `<div class="fr wrap">${["target", "stop", "entry"].map((key) => `<button type="button" class="btn btn-ghost btn-small" data-say="${key}">▶ ${esc(Voice.phrase(key))}</button>`).join("")}</div>`
          + k.head("Hiện thông báo")
          + k.tog("popup", "Hiện thông báo trên trang")
          + `<label class="fr"><input type="checkbox" data-p="notify" data-t="bool" data-ask ${c.notify ? "checked" : ""}><span>Thông báo của trình duyệt khi đang mở tab khác</span></label>`
          + k.note(this.owner
            ? "Áp dụng cho tài khoản MT5 đang đăng nhập trên máy chủ: lệnh khớp (kể cả lệnh chờ), chạm TP, chạm SL, đóng tay. Chỉ báo khi trang đang mở; lệnh cũ lúc mở trang không đọc lại. Điện thoại: chạm vào trang một lần để trình duyệt cho phát tiếng."
            : "Đọc khi có tín hiệu mới và khi tín hiệu đóng (lời = TP, lỗ = SL). Chỉ báo khi trang đang mở. Điện thoại: chạm vào trang một lần để trình duyệt cho phát tiếng.");
      };
      this.openPanel("Thông báo & giọng nói", [["voice", "Cài đặt"]], render, {
        root: c,
        onChange: () => Voice.save(),
        onReset: (redraw) => { Object.assign(c, VOICE_DEFAULTS); Voice.save(); redraw(); },
        afterDraw: (panel) => {
          Voice.unlock();
          const sample = () => (Voice.vi() ? `${Voice.phrase("target")}, vàng, lời 120 đô` : `${Voice.phrase("target")}, gold, plus 120 dollars`);
          panel.querySelector("[data-try]").onclick = () => Voice.speak(sample(), true, true);
          panel.querySelectorAll("[data-say]").forEach((b) => (b.onclick = () => Voice.speak(Voice.phrase(b.dataset.say), true, b.dataset.say !== "stop")));
          // Picking a voice reads with it straight away.
          panel.querySelector(".voice-sel").addEventListener("change", () => Voice.speak(sample(), true, true));
          // A new language: the voice picked for the old one no longer applies.
          panel.querySelector('[data-p="lang"]').addEventListener("change", () => { c.voice = ""; Voice.save(); if (this.panelDraw) this.panelDraw(); });
          const ask = panel.querySelector("[data-ask]");
          if (ask) ask.addEventListener("change", async () => {
            if (!ask.checked || !window.Notification) return;
            const r = Notification.permission === "default" ? await Notification.requestPermission() : Notification.permission;
            if (r !== "granted") { c.notify = false; Voice.save(); ask.checked = false; toast("Trình duyệt chưa cho phép thông báo", true); }
          });
          // The voice list arrives late the first time.
          if (window.speechSynthesis && !speechSynthesis.getVoices().length) {
            speechSynthesis.addEventListener("voiceschanged", () => { if (!panel.hidden && this.panelDraw) this.panelDraw(); }, { once: true });
          }
        },
      });
    },

    renderSignals() {
      const open = this.signals.filter((s) => s.status === "open");
      const closed = this.signals.filter((s) => s.status !== "open");
      const wins = closed.filter((s) => (s.result || 0) > 0).length;
      $("sigOpen").innerHTML = open.length ? open.map((s) => this.signalRow(s)).join("") : '<div class="empty">Chưa có lệnh đang mở</div>';
      $("closedTitle").textContent = closed.length ? `Đã đóng · thắng ${wins}/${closed.length}` : "Đã đóng";
      $("sigClosed").innerHTML = closed.length ? closed.slice(0, 60).map((s) => this.signalRow(s)).join("") : '<div class="empty">Chưa có</div>';
    },

    signalRow(s) {
      const buy = s.side === "long";
      const move = s.result != null ? s.result : (s.price != null ? (s.price - s.entry) * (buy ? 1 : -1) : null);
      const color = s.status === "open" ? "var(--purple)" : ((s.result || 0) > 0 ? "var(--up)" : ((s.result || 0) < 0 ? "var(--down)" : "#666"));
      let copy = "";
      if (s.copy) {
        copy = s.copy.lots > 0
          ? `<div class="copy">📋 Đã copy ${s.copy.lots} lot${s.copy.profit != null ? ` · <span class="${s.copy.profit >= 0 ? "pos" : "neg"}">${signed(s.copy.profit)} USD</span>` : ""}</div>`
          : `<div class="copy bad">⚠ Không copy được: ${esc(plain(s.copy.error))}</div>`;
      }
      return `<div class="sig">
        <div class="bar" style="background:${color}"></div>
        <div>
          <div class="top"><span class="sym">${esc(s.symbol)}</span>
            <span class="side ${buy ? "buy" : "sell"}">${buy ? "MUA" : "BÁN"}</span><span>${fmt(s.entry)}</span></div>
          <div class="lv">SL ${fmt(s.stop)} · TP ${fmt(s.target)}${s.status === "open" ? "" : " · ra " + fmt(s.exit)}</div>
          ${copy}
        </div>
        <div class="right">
          ${move != null ? `<div class="move ${move >= 0 ? "pos" : "neg"}">${signed(move)}</div>` : ""}
          <div class="muted small">${clock(s.status === "open" ? s.openTime : (s.closeTime || s.openTime))}</div>
        </div>
      </div>`;
    },

    /* ----- tabs that load on their own ----- */

    loadTab(first) {
      if (!this.secret) return;
      const t = this.tab;
      if (t === "trade" && first) this.renderTrade();
      if (t === "signals" && first) this.renderSignals();
      if (t === "history" && first) this.loadHistory();
      if (t === "news" && first) { this.renderNews(); this.loadNews(true); }
      if (t === "copy") this.loadCopy(first);
      if (t === "members" && first) this.loadMembers();
      if (t === "bot") this.loadBot(first);
      if (t === "autobot") { this.loadAutoBot(first); this.loadStopBot(first); this.loadSRBot(first); }
    },

    /* ----- history ----- */

    /** [from, to) in UTC seconds for a range of the viewer's local days. */
    rangeTimes(key) {
      const start = new Date(); start.setHours(0, 0, 0, 0);
      const day = start.getTime() / 1000, nowS = Date.now() / 1000 + 60;
      const monday = new Date(start); monday.setDate(start.getDate() - ((start.getDay() + 6) % 7));
      const first = new Date(start); first.setDate(1);
      if (key === "custom") {
        const f = $("histFrom").value, t = $("histTo").value;
        const a = f ? new Date(f + "T00:00:00") : start, b = t ? new Date(t + "T00:00:00") : start;
        b.setDate(b.getDate() + 1);
        return [a.getTime() / 1000, b.getTime() / 1000];
      }
      return {
        today: [day, nowS], yesterday: [day - 86400, day], thisweek: [monday.getTime() / 1000, nowS],
        thismonth: [first.getTime() / 1000, nowS], week: [day - 6 * 86400, nowS], month: [day - 29 * 86400, nowS],
      }[key] || [day, nowS];
    },

    async loadHistory() {
      const ranges = [["today", "Hôm nay"], ["yesterday", "Hôm qua"], ["thisweek", "Tuần này"], ["thismonth", "Tháng này"], ["week", "7 ngày"], ["month", "30 ngày"], ["custom", "Tùy chỉnh"]];
      $("histRange").innerHTML = ranges.map(([k, n]) => `<button type="button" data-r="${k}" class="${k === this.histRange ? "on" : ""}">${n}</button>`).join("");
      $("histRange").querySelectorAll("button").forEach((b) => (b.onclick = () => { this.histRange = b.dataset.r; this.histDay = null; this.loadHistory(); }));
      $("histCustom").hidden = this.histRange !== "custom";
      if (this.histRange === "custom") {
        const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
        if (!$("histFrom").value) { const d = new Date(); d.setDate(d.getDate() - 13); $("histFrom").value = iso(d); }
        if (!$("histTo").value) $("histTo").value = iso(new Date());
        $("histGo").onclick = () => { this.histDay = null; this.loadHistory(); };
      }
      $("histList").innerHTML = '<div class="empty">Đang tải…</div>';
      const [from, to] = this.rangeTimes(this.histRange);
      try {
        const h = await this.call(`/mt5/history?from=${Math.floor(from)}&to=${Math.ceil(to)}`);
        this.histData = { list: (h.positions || []).sort((a, b) => b.closeTime - a.closeTime), summary: h.summary || {} };
        this.renderHistory();
      } catch (e) {
        $("histList").innerHTML = `<div class="empty">${esc(plain(e.message))}</div>`;
      }
    },

    /** Totals of a list of closed positions. */
    histTotals(list) {
      const wins = list.filter((p) => p.profit > 0), losses = list.filter((p) => p.profit < 0);
      const gain = wins.reduce((a, p) => a + p.profit, 0), loss = -losses.reduce((a, p) => a + p.profit, 0);
      return {
        count: list.length, wins: wins.length, losses: losses.length, net: gain - loss, gain, loss,
        fees: list.reduce((a, p) => a + (p.commission || 0) + (p.swap || 0), 0),
        lots: list.reduce((a, p) => a + (p.lots || 0), 0),
        best: list.reduce((m, p) => (m == null || p.profit > m.profit ? p : m), null),
        worst: list.reduce((m, p) => (m == null || p.profit < m.profit ? p : m), null),
        tp: list.filter((p) => p.reason === "target").length, sl: list.filter((p) => p.reason === "stop").length,
      };
    },

    renderHistory() {
      const { list: all, summary } = this.histData || { list: [], summary: {} };
      const dayKey = (t) => { const d = new Date(t * 1000); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`; };
      const t = this.histTotals(all);
      const pct = t.count ? Math.round(t.wins / t.count * 100) + "%" : "–";
      const pf = t.loss > 0 ? (t.gain / t.loss).toFixed(2) : t.gain > 0 ? "∞" : "–";
      const stats = [
        ["Lãi/lỗ ròng", `<span class="${t.net >= 0 ? "pos" : "neg"}">${signed(t.net)}</span>`],
        ["Số lệnh", `${t.count} <small class="muted">· ${t.lots.toFixed(2)} lot</small>`],
        ["Thắng / thua", `${t.wins} / ${t.losses} <small class="muted">· ${pct}</small>`],
        ["Chạm TP / chạm SL", `${t.tp} / ${t.sl}`],
        ["Tổng lời / tổng lỗ", `<span class="pos">${signed(t.gain)}</span> / <span class="neg">${signed(-t.loss)}</span>`],
        ["Profit factor", pf],
        ["Lệnh lời nhất", t.best && t.best.profit > 0 ? `<span class="pos">${signed(t.best.profit)}</span>` : "–"],
        ["Lệnh lỗ nhất", t.worst && t.worst.profit < 0 ? `<span class="neg">${signed(t.worst.profit)}</span>` : "–"],
        ["Phí + swap", signed(t.fees)],
      ];
      if (summary.deposit) stats.push(["Nạp", `<span class="pos">${signed(summary.deposit)}</span>`]);
      if (summary.withdrawal) stats.push(["Rút", `<span class="neg">${signed(summary.withdrawal)}</span>`]);
      $("histStats").innerHTML = stats.map(([k, v]) => `<div class="stat"><span>${k}</span><b>${v}</b></div>`).join("");

      // One row per day, newest first, with a bar for the day's result.
      const byDay = new Map();
      all.forEach((p) => { const k = dayKey(p.closeTime); if (!byDay.has(k)) byDay.set(k, []); byDay.get(k).push(p); });
      const days = [...byDay.entries()].sort((a, b) => (a[0] < b[0] ? 1 : -1)).map(([k, l]) => [k, this.histTotals(l)]);
      const max = Math.max(1, ...days.map(([, d]) => Math.abs(d.net)));
      $("histDays").innerHTML = days.length ? days.map(([k, d]) => {
        const date = new Date(k + "T12:00:00").toLocaleDateString("vi-VN", { weekday: "short", day: "2-digit", month: "2-digit" });
        return `<button type="button" class="day-row ${this.histDay === k ? "on" : ""}" data-day="${k}">
          <span class="d">${date}</span>
          <span class="n">${d.count} lệnh · ${d.wins}T/${d.losses}B</span>
          <span class="barwrap"><span class="dbar ${d.net >= 0 ? "up" : "down"}" style="width:${Math.max(2, Math.abs(d.net) / max * 100)}%"></span></span>
          <b class="${d.net >= 0 ? "pos" : "neg"}">${signed(d.net)}</b></button>`;
      }).join("") : '<div class="empty">Không có lệnh đã đóng trong khoảng này</div>';
      $("histDays").querySelectorAll("[data-day]").forEach((b) => (b.onclick = () => {
        this.histDay = this.histDay === b.dataset.day ? null : b.dataset.day;
        this.renderHistory();
      }));

      const list = this.histDay ? all.filter((p) => dayKey(p.closeTime) === this.histDay) : all;
      $("histAll").hidden = !this.histDay;
      $("histAll").onclick = () => { this.histDay = null; this.renderHistory(); };
      $("histListTitle").textContent = this.histDay
        ? `Lệnh ngày ${new Date(this.histDay + "T12:00:00").toLocaleDateString("vi-VN")} · ${signed(this.histTotals(list).net)}`
        : `Lệnh đã đóng · ${list.length}`;
      $("histList").innerHTML = list.length ? list.map((p, i) => {
        const color = p.reason === "target" ? "var(--up)" : p.reason === "stop" ? "var(--down)" : "#5b6478";
        const d = p.digits || this.digitsFor(p.symbol);
        return `<div class="sig clickable" data-i="${i}">
          <div class="bar" style="background:${color}"></div>
          <div>
            <div class="top"><span class="sym">${esc(p.symbol)}</span><span class="side ${p.side === "long" ? "buy" : "sell"}">${sideName(p.side)} ${+p.lots.toFixed(2)}</span>
              <span class="muted small">${fmt(p.entry, d)} → ${fmt(p.exit, d)}</span></div>
            <div class="lv">${p.reason === "target" ? "Chạm TP" : p.reason === "stop" ? "Chạm SL" : "Đóng tay"} · ${clock(p.closeTime)}</div>
          </div>
          <div class="right"><div class="move ${p.profit >= 0 ? "pos" : "neg"}">${signed(p.profit)}</div></div>
        </div>`;
      }).join("") : '<div class="empty">Không có lệnh đã đóng</div>';
      $("histList").querySelectorAll("[data-i]").forEach((row) => (row.onclick = () => this.closedSheet(list[+row.dataset.i])));
    },

    closedSheet(p) {
      const d = p.digits || this.digitsFor(p.symbol);
      const sign = p.side === "long" ? 1 : -1;
      let slip = "";
      const level = p.reason === "stop" ? p.stop : p.reason === "target" ? p.target : null;
      if (level) {
        const diff = (p.exit - level) * sign;
        slip = `<div class="kv"><span>Trượt giá so với ${p.reason === "stop" ? "SL" : "TP"}</span><b class="${diff >= 0 ? "pos" : "neg"}">${signed(diff, d)}</b></div>`;
      }
      const row = (k, v) => `<div class="kv"><span>${k}</span><b>${v}</b></div>`;
      sheet.open(`<h3>${esc(p.symbol)} <span class="side ${p.side === "long" ? "buy" : "sell"}">${sideName(p.side)} ${+p.lots.toFixed(2)}</span></h3>
        <p class="muted small">${esc(p.description || "")} · #${p.ticket}</p>
        <p class="big ${p.profit >= 0 ? "pos" : "neg"}">${signed(p.profit)}</p>
        <div class="kvs">
          ${row("Mở", `${fmt(p.entry, d)} · ${fullTime(p.openTime)}`)}
          ${row("Đóng", `${fmt(p.exit, d)} · ${fullTime(p.closeTime)}`)}
          ${row("Lý do", p.reason === "target" ? "Chạm TP" : p.reason === "stop" ? "Chạm SL" : "Đóng tay")}
          ${row("SL lúc vào → lúc đóng", `${p.stopOpen ? fmt(p.stopOpen, d) : "–"} → ${p.stop ? fmt(p.stop, d) : "–"}`)}
          ${row("TP lúc vào → lúc đóng", `${p.targetOpen ? fmt(p.targetOpen, d) : "–"} → ${p.target ? fmt(p.target, d) : "–"}`)}
          ${slip}
          ${row("Phí", signed(p.commission || 0))}
          ${row("Swap", signed(p.swap || 0))}
          ${p.comment ? row("Ghi chú", esc(p.comment)) : ""}
        </div>`);
    },

    /* ----- news ----- */

    async loadNews(force) {
      if (!this.owner && this.features.news === false) return;
      if (!force && this.news && Date.now() - this.newsTime < 4 * 60 * 1000) return;
      try {
        this.news = await this.call(this.owner ? "/news" : "/member/news");
        this.newsTime = Date.now();
        if (this.tab === "news") this.renderNews();
      } catch (e) {
        if (this.tab === "news") $("newsList").innerHTML = `<div class="empty">${esc(plain(ServerTooOld(e) ? "Cập nhật máy chủ lên bản mới để xem tin tức" : e.message))}</div>`;
      }
    },

    goldEvents(minRank) {
      const rank = { High: 3, Medium: 2, Low: 1 };
      return ((this.news && this.news.events) || []).filter((e) => e.country === "USD" && (rank[e.impact] || 0) >= minRank);
    },

    /** Gold's move since a release (the chart's bars, timeframes up to 15 minutes). */
    reaction(event) {
      const sec = TF_SECONDS[this.interval];
      if (!this.bars.length || sec > 900 || event.time > Date.now() / 1000) return null;
      const i = this.bars.findIndex((b) => b.time + sec > event.time);
      if (i < 0) return null;
      const ref = this.bars[i].open;
      const later = this.bars.filter((b) => b.time <= event.time + 15 * 60);
      const price = later.length ? later[later.length - 1].close : this.bars[this.bars.length - 1].close;
      return { move: price - ref, ref };
    },

    verdict(move, price) {
      if (move == null) return { text: "Đang đo phản ứng giá…", cls: "" };
      if (Math.abs(move) < price * 0.0001) return { text: `Giá gần như đứng yên (${signed(move)}) → chưa rõ`, cls: "" };
      return move > 0 ? { text: `Tin XẤU cho USD → TỐT cho vàng (${signed(move)})`, cls: "pos" }
        : { text: `Tin TỐT cho USD → XẤU cho vàng (${signed(move)})`, cls: "neg" };
    },

    renderNews() {
      if (!this.newsFilter) this.newsFilter = 3;
      $("newsFilter").innerHTML = [[3, "Tin đỏ"], [2, "Đỏ + cam"]].map(([k, n]) => `<button type="button" data-k="${k}" class="${k === this.newsFilter ? "on" : ""}">${n}</button>`).join("");
      $("newsFilter").querySelectorAll("button").forEach((b) => (b.onclick = () => { this.newsFilter = +b.dataset.k; this.renderNews(); }));
      if (!this.news) { $("newsList").innerHTML = '<div class="empty">Đang tải…</div>'; return; }
      const nowS = Date.now() / 1000;
      const next = this.goldEvents(3).find((e) => e.time > nowS);
      $("nextNews").hidden = !next;
      if (next) {
        const left = next.time - nowS, h = Math.floor(left / 3600), m = Math.floor((left % 3600) / 60);
        $("nextNews").innerHTML = `<div class="next"><span class="dot high"></span><div><b>${esc(next.title)}</b>
          <div class="muted small">${clock(next.time)} · còn ${h ? h + " giờ " : ""}${m} phút · Dự báo ${esc(next.forecast || "–")} · Trước ${esc(next.previous || "–")}</div></div></div>`;
      }
      const events = this.goldEvents(this.newsFilter);
      let lastDay = "";
      $("newsList").innerHTML = events.length ? events.map((e) => {
        const day = new Date(e.time * 1000).toLocaleDateString("vi-VN", { weekday: "long", day: "2-digit", month: "2-digit" });
        const head = day !== lastDay ? `<div class="day">${day}</div>` : "";
        lastDay = day;
        const past = e.time <= nowS;
        let result = "";
        if (past && e.impact === "High") {
          const r = this.reaction(e);
          if (r) { const v = this.verdict(r.move, r.ref); result = `<div class="small ${v.cls}">${v.text}</div>`; }
        }
        return `${head}<div class="news-row ${past ? "past" : ""}">
          <span class="time">${new Date(e.time * 1000).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" })}</span>
          <span class="dot ${e.impact === "High" ? "high" : "med"}"></span>
          <div><b>${esc(e.title)}</b><div class="muted small">Dự báo ${esc(e.forecast || "–")} · Trước ${esc(e.previous || "–")}${e.actual ? " · Thực tế " + esc(e.actual) : ""}</div>${result}</div>
        </div>`;
      }).join("") : '<div class="empty">Không có tin USD tuần này</div>';
      const heads = this.news.headlines || [];
      $("headlineList").innerHTML = heads.length ? heads.slice(0, 25).map((h) => `<a class="headline" href="${esc(h.link)}" target="_blank" rel="noopener">
        <b>${esc(h.title)}</b><span class="muted small">${esc(h.source || "")}${h.time ? " · " + clock(h.time) : ""}</span></a>`).join("")
        : `<div class="empty">${esc(this.news.error || "Chưa có tin")}</div>`;
    },

    /* ----- copy trade ----- */

    async loadCopy(first) {
      if (!this.owner) return this.loadMemberCopy(first);
      if ($("sheet").open) return;
      try {
        const c = await this.call("/copy/status");
        const m = c.master || {};
        const followers = c.followers || [];
        $("copyPanel").innerHTML = `<div class="panel-head"><h3>Copy trade</h3>
            <label class="switch"><input type="checkbox" id="copyOn" ${c.enabled ? "checked" : ""}><span></span></label></div>
          <p class="muted small">${c.enabled ? "Đang copy mọi lệnh của tài khoản chính sang các tài khoản dưới." : "Đang tắt: bật để copy lệnh mới."}
            ${m.connected ? ` Tài khoản chính #${m.login} · ${m.positions} lệnh.` : (m.error ? " " + esc(m.error) : "")}</p>
          <div class="list">${followers.length ? followers.map((f) => {
            const st = f.status || {};
            return `<div class="sig clickable" data-id="${esc(f.id)}">
              <div class="bar" style="background:${st.connected ? "var(--up)" : "#5b6478"}"></div>
              <div><div class="top"><b>${esc(f.name || "#" + f.login)}</b>${f.member ? '<span class="badge mem">Thành viên</span>' : ""}${!f.enabled ? '<span class="badge off">Tắt</span>' : ""}</div>
                <div class="lv">#${f.login} · ${esc(f.server)} · ${f.fixedLots ? f.fixedLots + " lot cố định" : "×" + f.multiplier} · tối đa ${f.maxLots}</div>
                <div class="lv">${st.connected ? `Vốn ${money(st.equity)} · ${st.positions || 0} lệnh · <span class="${(st.profit || 0) >= 0 ? "pos" : "neg"}">${signed(st.profit || 0)}</span>` : esc(st.error || "Chưa kết nối")}</div></div>
              <div class="right"></div></div>`;
          }).join("") : '<div class="empty">Chưa có tài khoản copy</div>'}</div>
          <button class="btn btn-gold btn-small" id="addFollower">+ Thêm tài khoản copy</button>
          ${(c.events || []).length ? `<h4>Hoạt động</h4><div class="list log">${c.events.slice(0, 15).map((e) => `<div class="log-row"><span class="muted small">${clock(e.time)}</span> ${esc(e.text)}</div>`).join("")}</div>` : ""}`;
        $("copyOn").onchange = async (e) => {
          await act(null, () => this.call("/copy/settings", { enabled: e.target.checked }), e.target.checked ? "Đã bật copy trade" : "Đã tắt copy trade");
          this.loadCopy();
        };
        $("addFollower").onclick = () => this.followerSheet(null);
        $("copyPanel").querySelectorAll("[data-id]").forEach((row) => (row.onclick = () => this.followerSheet(followers.find((f) => f.id === row.dataset.id))));
      } catch (e) {
        if (first) $("copyPanel").innerHTML = `<div class="empty">${esc(e.message)}</div>`;
      }
    },

    followerForm(f, realAllowed) {
      f = f || { multiplier: 1, fixedLots: 0, maxLots: 0.1, enabled: true };
      return `<div class="fields two">
          <label>Số tài khoản MT5<input id="fLogin" inputmode="numeric" value="${esc(f.login || "")}"></label>
          <label>Server<input id="fServer" value="${esc(f.server || "")}" placeholder="Exness-MT5Trial14"></label>
        </div>
        <div class="fields"><label>Mật khẩu chính${f.hasPassword ? " (để trống = giữ nguyên)" : ""}<input id="fPass" type="password" autocomplete="new-password"></label></div>
        <div class="fields three">
          <label>Hệ số lot<input id="fMult" inputmode="decimal" value="${f.multiplier}"></label>
          <label>Lot cố định<input id="fFixed" inputmode="decimal" value="${f.fixedLots || ""}" placeholder="không"></label>
          <label>Lot tối đa<input id="fMax" inputmode="decimal" value="${f.maxLots}"></label>
        </div>
        ${realAllowed ? `<label class="check"><input type="checkbox" id="fReal" ${f.allowReal ? "checked" : ""}> Cho phép tài khoản THẬT</label>` : ""}
        <label class="check"><input type="checkbox" id="fOn" ${f.enabled !== false && f.memberEnabled !== false ? "checked" : ""}> Đang copy</label>`;
    },

    readFollower(el) {
      const body = {
        login: el.querySelector("#fLogin").value.trim(), server: el.querySelector("#fServer").value.trim(),
        multiplier: num(el.querySelector("#fMult").value) || 1, fixedLots: num(el.querySelector("#fFixed").value) || 0,
        maxLots: num(el.querySelector("#fMax").value) || 0.1, enabled: el.querySelector("#fOn").checked,
      };
      const pass = el.querySelector("#fPass").value;
      if (pass) body.password = pass;
      const real = el.querySelector("#fReal");
      body.allowReal = real ? real.checked : false;
      return body;
    },

    followerSheet(f) {
      sheet.open(`<h3>${f ? "Tài khoản copy " + esc(f.name || "#" + f.login) : "Thêm tài khoản copy"}</h3>
        ${f && !f.member ? "" : ""}
        <div class="fields"><label>Tên<input id="fName" value="${esc((f && f.name) || "")}" placeholder="vd. Tài khoản 2"></label></div>
        ${this.followerForm(f, true)}
        <p class="muted small">Mật khẩu chính (không phải investor), chỉ lưu trên máy chủ của bạn.</p>
        <button class="btn btn-gold wide" id="fSave">Lưu</button>
        ${f ? `<button class="btn btn-ghost wide" id="fCloseAll">Đóng các lệnh copy</button><button class="btn btn-ghost wide danger" id="fRemove">Xoá tài khoản này</button>` : ""}`, (el) => {
        el.querySelector("#fSave").onclick = async (e) => {
          const body = Object.assign(this.readFollower(el), { id: f ? f.id : "", name: el.querySelector("#fName").value.trim() });
          const ok = await act(e.currentTarget, () => this.call("/copy/follower", body), "Đã lưu");
          if (ok) { sheet.close(); this.loadCopy(); }
        };
        if (!f) return;
        el.querySelector("#fCloseAll").onclick = async (e) => {
          if (!confirm("Đóng mọi lệnh copy trên tài khoản này?")) return;
          await act(e.currentTarget, () => this.call("/copy/close", { id: f.id }), "Đã đóng lệnh copy");
        };
        el.querySelector("#fRemove").onclick = async (e) => {
          if (!confirm("Xoá tài khoản copy này? (lệnh đang mở trên nó vẫn giữ)")) return;
          const ok = await act(e.currentTarget, () => this.call("/copy/remove", { id: f.id, closePositions: false }), "Đã xoá");
          if (ok) { sheet.close(); this.loadCopy(); }
        };
      });
    },

    async loadMemberCopy(first) {
      if (!first) return;
      try {
        const c = await this.call("/member/copy");
        const f = c.follower;
        const st = (f && f.status) || {};
        const realAllowed = !!this.features.copyReal;
        $("copyPanel").innerHTML = `<h3>Copy lệnh vào MT5 của bạn</h3>
          <p class="muted small">Mỗi tín hiệu mới tự mở trên tài khoản của bạn theo hệ số lot bạn chọn, SL/TP và đóng lệnh theo người dẫn.
            ${c.ownerCopyOn ? "" : "<br><b>Người cung cấp đang tạm dừng copy.</b>"}</p>
          ${f ? `<div class="stat-line">${st.connected ? `✅ Đã kết nối #${f.login} · vốn ${money(st.equity)} · ${st.positions || 0} lệnh` : "⏳ " + esc(plain(st.error || "Đang kết nối…"))}</div>` : ""}
          ${this.followerForm(f, realAllowed)}
          ${realAllowed ? "" : '<p class="muted small">Chỉ copy được vào tài khoản demo.</p>'}
          <button class="btn btn-gold wide" id="mcSave">${f ? "Lưu" : "Bắt đầu copy"}</button>
          ${f ? '<button class="btn btn-ghost wide danger" id="mcRemove">Ngừng copy và xoá tài khoản</button>' : ""}`;
        const el = $("copyPanel");
        el.querySelector("#mcSave").onclick = async (e) => {
          const ok = await act(e.currentTarget, () => this.call("/member/copy", this.readFollower(el)), "Đã lưu");
          if (ok) this.loadMemberCopy(true);
        };
        if (f) el.querySelector("#mcRemove").onclick = async (e) => {
          if (!confirm("Ngừng copy lệnh?")) return;
          const ok = await act(e.currentTarget, () => this.call("/member/copy/remove", {}), "Đã ngừng copy");
          if (ok) this.loadMemberCopy(true);
        };
      } catch (e) {
        $("copyPanel").innerHTML = `<div class="empty">${esc(plain(e.message))}</div>`;
      }
    },

    /* ----- members ----- */

    async loadMembers() {
      try {
        const m = await this.call("/members");
        const nowS = Date.now() / 1000;
        $("membersTitle").textContent = `Thành viên · ${m.members.length}`;
        $("membersList").innerHTML = m.members.length ? m.members.map((x) => {
          const badge = !x.enabled ? '<span class="badge off">Khoá</span>' : (x.expires && x.expires <= nowS ? '<span class="badge exp">Hết hạn</span>' : "");
          return `<div class="member-row clickable" data-id="${esc(x.id)}"><div><b>${esc(x.name)}</b> ${badge}
            <div class="muted small">${x.role === "copy" ? "Tín hiệu + copy" : "Chỉ tín hiệu"}${x.expires ? " · đến " + new Date(x.expires * 1000).toLocaleDateString("vi-VN") : " · không hết hạn"}${x.hasCopy ? " · đã nối MT5" : ""}</div></div>
            <div class="muted small">${x.lastSeen ? clock(x.lastSeen) : "chưa vào"}</div></div>`;
        }).join("") : '<div class="empty">Chưa có thành viên. Bấm “+ Thêm” để tạo mã mời.</div>';
        $("membersList").querySelectorAll("[data-id]").forEach((row) => (row.onclick = () => this.memberSheet(m.members.find((x) => x.id === row.dataset.id))));
        const names = { news: "Tin tức", killzones: "Chỉ báo ICT Killzones (FVG, đỉnh đáy…)", sharkflow: "Dòng tiền cá mập", demo: "Nút BUY/SELL (giao dịch demo trong app)", indicators: "Tab Chỉ báo (tự viết chỉ báo)", backtest: "Tab Backtest", copyReal: "Cho copy vào tài khoản THẬT của thành viên" };
        $("featureList").innerHTML = Object.keys(names).map((k) => `<label class="toggle"><span>${names[k]}</span>
          <span class="switch"><input type="checkbox" data-f="${k}" ${m.features && m.features[k] ? "checked" : ""}><span></span></span></label>`).join("");
        $("featureList").querySelectorAll("input").forEach((i) => (i.onchange = async () => {
          await act(null, () => this.call("/members/features", { [i.dataset.f]: i.checked }), "Đã lưu");
        }));
      } catch (e) {
        $("membersList").innerHTML = `<div class="empty">${esc(e.message)}</div>`;
      }
    },

    memberSheet(x) {
      const nowS = Date.now() / 1000;
      const left = x && x.expires ? Math.max(0, Math.round((x.expires - nowS) / 86400)) : 0;
      sheet.open(`<h3>${x ? esc(x.name) : "Thêm thành viên"}</h3>
        <div class="fields"><label>Tên<input id="mName" value="${esc((x && x.name) || "")}" placeholder="vd. Anh Nam"></label></div>
        <div class="fields two">
          <label>Quyền<select id="mRole"><option value="signals">Chỉ xem tín hiệu</option><option value="copy" ${x && x.role === "copy" ? "selected" : ""}>Tín hiệu + copy lệnh</option></select></label>
          <label>Số ngày (0 = không hết hạn)<input id="mDays" inputmode="numeric" value="${x ? left : 30}"></label>
        </div>
        ${x ? `<p class="muted small">${x.expires ? "Hết hạn " + new Date(x.expires * 1000).toLocaleString("vi-VN") + " (còn " + left + " ngày). Lưu sẽ tính lại từ hôm nay." : "Không hết hạn."}</p>` : ""}
        <label class="check"><input type="checkbox" id="mOn" ${!x || x.enabled ? "checked" : ""}> Đang hoạt động (bỏ chọn = khoá)</label>
        <button class="btn btn-gold wide" id="mSave">${x ? "Lưu" : "Tạo mã mời"}</button>
        ${x ? '<button class="btn btn-ghost wide" id="mCode">Đổi mã mời (mã cũ hết dùng được)</button><button class="btn btn-ghost wide danger" id="mRemove">Xoá thành viên</button>' : ""}`, (el) => {
        el.querySelector("#mSave").onclick = async (e) => {
          const body = { id: x ? x.id : "", name: el.querySelector("#mName").value.trim(), role: el.querySelector("#mRole").value, enabled: el.querySelector("#mOn").checked };
          const days = num(el.querySelector("#mDays").value);
          if (!x || days !== left) body.days = days || 0;
          const r = await act(e.currentTarget, () => this.call("/members/save", body), x ? "Đã lưu" : null);
          if (!r) return;
          this.loadMembers();
          if (r.code) this.codeSheet(r.member, r.code); else sheet.close();
        };
        if (!x) return;
        el.querySelector("#mCode").onclick = async (e) => {
          if (!confirm("Tạo mã mới cho " + x.name + "? Mã cũ sẽ không dùng được nữa.")) return;
          const r = await act(e.currentTarget, () => this.call("/members/code", { id: x.id }));
          if (r && r.code) this.codeSheet(r.member, r.code);
        };
        el.querySelector("#mRemove").onclick = async (e) => {
          if (!confirm("Xoá " + x.name + "?")) return;
          const r = await act(e.currentTarget, () => this.call("/members/remove", { id: x.id }), "Đã xoá");
          if (r) { sheet.close(); this.loadMembers(); }
        };
      });
    },

    codeSheet(m, code) {
      const link = location.origin + location.pathname + "#member";
      const message = `Mã mời Aurum Pro của bạn: ${code}\nMở app Aurum Pro hoặc trang ${link} và nhập mã để xem tín hiệu.`;
      sheet.open(`<h3>Mã mời của ${esc(m ? m.name : "")}</h3>
        <div class="code">${esc(code)}</div>
        <p class="muted small">Mã chỉ hiện một lần — hãy gửi ngay cho thành viên. Họ chỉ cần nhập mã, không cần biết gì khác.</p>
        <button class="btn btn-gold wide" id="cCopy">Sao chép lời nhắn</button>
        ${navigator.share ? '<button class="btn btn-ghost wide" id="cShare">Chia sẻ…</button>' : ""}`, (el) => {
        el.querySelector("#cCopy").onclick = async () => {
          try { await navigator.clipboard.writeText(message); toast("Đã sao chép"); } catch { prompt("Sao chép lời nhắn:", message); }
        };
        const s = el.querySelector("#cShare");
        if (s) s.onclick = () => navigator.share({ text: message }).catch(() => {});
      });
    },

    /* ----- "Stop theo nến" bot on the server (buy stop above / sell stop below each closed candle) ----- */

    async loadStopBot(first) {
      const el = $("stopBotPanel");
      try {
        const st = await this.call("/stopbot");
        this.stopStatus = st;
        this.renderBotBadge();
        if (first || !el.querySelector("#sbForm") || !el.contains(document.activeElement)) this.renderStopBot(st);
        else this.renderStopBotLive(st);
        if (!$("stopBtPanel").firstChild) this.renderStopBt();
      } catch (e) {
        el.innerHTML = `<h3>🎯 Bot lệnh Stop theo nến</h3><p class="muted small">${ServerTooOld(e) ? "Cập nhật máy chủ lên bản 2.8 (tab Máy chủ → Cập nhật) để dùng bot này." : esc(plain(e.message))}</p>`;
      }
    },

    renderStopBot(st) {
      const c = st.config || {};
      const el = $("stopBotPanel");
      el.innerHTML = `<div class="panel-head"><h3>🎯 Bot lệnh Stop theo nến</h3><span class="badge ${c.running ? "on" : "off"}">${c.running ? "Đang chạy" : "Đang dừng"}</span></div>
        <p class="muted small">Mỗi khi một nến đóng: đặt <b>BUY STOP</b> trên đỉnh nến và <b>SELL STOP</b> dưới đáy nến, SL ở phía bên kia cây nến, TP = R:R × rủi ro.
          Lệnh không khớp trong nến sau thì huỷ và đặt lại; một bên khớp thì huỷ bên kia. Chạy trên máy chủ (đóng web vẫn chạy), đặt vào tài khoản MT5 đang đăng nhập — nên thử bằng tài khoản demo. <b>Cùng một bot với app điện thoại</b> (Bot → Bot Buy/Sell Stop → Máy chủ VPS, hoặc nút ▶︎/⏸ cạnh BUY/SELL): bật/tắt, đổi cài đặt ở đâu thì chỗ kia cũng thấy.</p>
        <div id="sbForm">
          <div class="fields three">
            <label>Mã<input id="sbSymbol" value="${esc(c.symbol || this.symbol || "XAUUSDm")}"></label>
            <label>Khung nến<select id="sbInterval">${["1m", "5m", "15m", "30m", "1h", "4h"].map((t) => `<option ${t === (c.interval || "1m") ? "selected" : ""}>${t}</option>`).join("")}</select></label>
            <label>Chiều<select id="sbDirection">${[["both", "Cả MUA và BÁN"], ["long", "Chỉ BUY STOP"], ["short", "Chỉ SELL STOP"]].map(([v, n]) => `<option value="${v}" ${v === c.direction ? "selected" : ""}>${n}</option>`).join("")}</select></label>
          </div>
          <div class="fields three">
            <label>Lot<input id="sbLots" inputmode="decimal" value="${c.lots}"></label>
            <label>R:R (TP = R:R × rủi ro, 0 = không TP)<input id="sbRR" inputmode="decimal" value="${c.rr}"></label>
            <label>Cách đỉnh/đáy (giá)<input id="sbOffset" inputmode="decimal" value="${c.offset}"></label>
          </div>
          <div class="fields three">
            <label>Đặt SL<select id="sbStopMode"><option value="candle" ${c.stopMode !== "fixed" ? "selected" : ""}>Bên kia cây nến</option><option value="fixed" ${c.stopMode === "fixed" ? "selected" : ""}>Cách giá vào cố định</option></select></label>
            <label>Khoảng SL cố định (giá)<input id="sbStopDist" inputmode="decimal" value="${c.stopDistance}"></label>
            <label>Bỏ nến nhỏ hơn / lớn hơn (giá)<span class="pair"><input id="sbMin" inputmode="decimal" value="${c.minRange}" placeholder="0"><input id="sbMax" inputmode="decimal" value="${c.maxRange}" placeholder="0 = không giới hạn"></span></label>
          </div>
          <label class="check"><input type="checkbox" id="sbOCO" ${c.oco !== false ? "checked" : ""}> Một bên khớp thì huỷ bên kia (OCO)</label>
          <label class="check"><input type="checkbox" id="sbOne" ${c.onePosition !== false ? "checked" : ""}> Đang có lệnh của bot thì không đặt thêm</label>
          <div class="row-btns">
            ${c.running ? '<button class="btn btn-ghost" id="sbStop">■ Tắt bot Stop</button><button class="btn btn-ghost" id="sbSave">Lưu cài đặt</button>' : '<button class="btn btn-gold" id="sbStart">▶ Bật bot Stop</button>'}
          </div>
        </div>
        <div id="sbLive"></div>`;
      const body = () => ({
        symbol: $("sbSymbol").value.trim(), interval: $("sbInterval").value, direction: $("sbDirection").value,
        lots: num($("sbLots").value) || 0.01, rr: num($("sbRR").value) ?? 2, offset: num($("sbOffset").value) || 0,
        stopMode: $("sbStopMode").value, stopDistance: num($("sbStopDist").value) || 5,
        minRange: num($("sbMin").value) || 0, maxRange: num($("sbMax").value) || 0,
        oco: $("sbOCO").checked, onePosition: $("sbOne").checked,
      });
      const send = async (button, extra, done) => {
        const r = await act(button, () => this.call("/stopbot", Object.assign(body(), extra)), done);
        if (r) { this.stopStatus = r; this.renderStopBot(r); this.renderBotBadge(); this.refresh(); }
      };
      const start = $("sbStart"), stop = $("sbStop"), save = $("sbSave");
      if (start) start.onclick = (e) => send(e.currentTarget, { running: true }, "Đã bật bot Stop: lệnh đầu tiên đặt khi nến tiếp theo đóng");
      if (stop) stop.onclick = (e) => send(e.currentTarget, { running: false }, "Đã tắt bot Stop và huỷ lệnh chờ của nó");
      if (save) save.onclick = (e) => send(e.currentTarget, {}, "Đã lưu");
      this.renderStopBotLive(st);
    },

    renderStopBotLive(st) {
      const live = $("sbLive");
      if (!live) return;
      const d = (sym) => this.digitsFor(sym);
      const s = st.stats || {};
      const rows = (list, pending) => list.map((o) => `<div class="sig"><div class="bar" style="background:${o.side === "long" ? "#2b6bf3" : "var(--down)"};${pending ? "opacity:.5" : ""}"></div>
        <div><div class="top"><span class="sym">${esc(o.symbol)}</span><span class="side ${o.side === "long" ? "buy" : "sell"}">${pending ? (o.side === "long" ? "BUY STOP" : "SELL STOP") : sideName(o.side)} ${o.lots}</span>
          <span class="muted small">@ ${fmt(o.entry, d(o.symbol))}</span></div>
          <div class="lv">SL ${o.stop ? fmt(o.stop, d(o.symbol)) : "–"} · TP ${o.target ? fmt(o.target, d(o.symbol)) : "–"}</div></div>
        <div class="right">${pending ? '<span class="muted small">chờ khớp</span>' : `<div class="move ${(o.profit || 0) >= 0 ? "pos" : "neg"}">${signed(o.profit || 0)}</div>`}</div></div>`).join("");
      live.innerHTML = `<div class="stats">
          <div class="stat"><span>Lệnh đã đóng</span><b>${s.trades || 0}</b></div>
          <div class="stat"><span>Thắng</span><b>${s.wins || 0}${s.trades ? ` (${Math.round(s.wins / s.trades * 100)}%)` : ""}</b></div>
          <div class="stat"><span>Lãi/lỗ</span><b class="${(s.profit || 0) >= 0 ? "pos" : "neg"}">${signed(s.profit || 0)}</b></div>
          <div class="stat"><span>Đang chờ / đang mở</span><b>${(st.orders || []).length} / ${(st.positions || []).length}</b></div>
        </div>
        ${st.error ? `<p class="warn">${esc(st.error)}</p>` : ""}
        <div class="list">${rows(st.positions || [], false)}${rows(st.orders || [], true)}</div>
        ${(st.events || []).length ? `<h4>Hoạt động</h4><div class="list log">${st.events.slice(0, 15).map((e) => `<div class="log-row"><span class="muted small">${clock(e.time)}</span> ${esc(e.text)}</div>`).join("")}</div>` : ""}`;
    },

    /* ----- the bot (owner only): run a strategy on the server, its trades and results ----- */

    /* ----- "Cản & Hỗ trợ" bot on the server: zones from swing highs/lows, entry on a reaction candle ----- */

    async loadSRBot(first) {
      const el = $("srBotPanel");
      let st = null, problem = "";
      try { st = await this.call("/srbot"); } catch (e) { problem = ServerTooOld(e) ? "Cập nhật máy chủ lên bản 3.1 (tab Máy chủ → Cập nhật) để chạy bot này; backtest ở dưới vẫn dùng được." : plain(e.message); }
      this.srStatus = st;
      if (first || !el.querySelector("#srForm") || !el.contains(document.activeElement)) this.renderSRBot(st, problem);
      else this.renderSRBotLive(st);
    },

    renderSRBot(st, problem) {
      const c = Object.assign({}, SR_DEFAULTS, (st && st.config) || {});
      if (!c.symbol) c.symbol = this.symbol || "XAUUSDm";
      const el = $("srBotPanel");
      const opt = (list, v) => list.map(([k, n]) => `<option value="${k}" ${String(k) === String(v) ? "selected" : ""}>${n}</option>`).join("");
      el.innerHTML = `<div class="panel-head"><h3>🧱 Bot Cản & Hỗ trợ (M1)</h3>${st ? `<span class="badge ${c.running ? "on" : "off"}">${c.running ? "Đang chạy" : "Đang tắt"}</span>` : ""}</div>
        <p class="muted small">Tìm vùng <b>cản / hỗ trợ</b> từ các đỉnh đáy gần đây (đỉnh cũ cũng làm hỗ trợ và ngược lại). Khi một nến đóng <b>phản ứng tại vùng</b> — râu nến từ chối giá hoặc nến nhấn chìm — bot vào lệnh ngay (chạm hỗ trợ bật lên = MUA, chạm cản bị đẩy xuống = BÁN), SL sau cây nến đó, TP = R:R × rủi ro. Mỗi nến đóng sau đó bot <b>dời SL theo đáy/đỉnh nến</b> khi lệnh đã lời. Chạy liên tục trên máy chủ, mỗi lúc một lệnh.</p>
        ${problem ? `<p class="warn">${esc(problem)}</p>` : ""}
        <div id="srForm">
          <div class="fields three">
            <label>Mã<input id="srSymbol" value="${esc(c.symbol)}"></label>
            <label>Khung nến<select id="srInterval">${opt(["1m", "5m", "15m", "30m", "1h"].map((t) => [t, t]), c.interval)}</select></label>
            <label>Chiều<select id="srDirection">${opt([["both", "Cả MUA và BÁN"], ["long", "Chỉ MUA ở hỗ trợ"], ["short", "Chỉ BÁN ở cản"]], c.direction)}</select></label>
          </div>
          <div class="fields three">
            <label>Lot<input id="srLots" inputmode="decimal" value="${c.lots}"></label>
            <label>R:R (TP = R:R × rủi ro, 0 = không TP)<input id="srRR" inputmode="decimal" value="${c.rr}"></label>
            <label>Nến phản ứng<select id="srPattern">${opt([["both", "Râu từ chối hoặc nhấn chìm"], ["pin", "Chỉ râu từ chối (pin bar)"], ["engulf", "Chỉ nến nhấn chìm"]], c.pattern)}</select></label>
          </div>
          <div class="fields three">
            <label>Râu tối thiểu (% cây nến)<input id="srWick" inputmode="decimal" value="${Math.round(c.wickRatio * 100)}"></label>
            <label>Độ rộng vùng (× ATR)<input id="srZone" inputmode="decimal" value="${c.zoneAtr}"></label>
            <label>Số lần chạm tối thiểu<input id="srTouches" inputmode="numeric" value="${c.minTouches}"></label>
          </div>
          <div class="fields three">
            <label>Số nến nhìn lại<input id="srLookback" inputmode="numeric" value="${c.lookback}"></label>
            <label>Đỉnh/đáy: số nến mỗi bên<input id="srSwing" inputmode="numeric" value="${c.swing}"></label>
            <label>Đệm SL (× ATR)<input id="srBuffer" inputmode="decimal" value="${c.slBufferAtr}"></label>
          </div>
          <label class="check"><input type="checkbox" id="srTrail" ${c.trail ? "checked" : ""}> Dời SL theo đáy (lệnh MUA) / đỉnh (lệnh BÁN) của từng nến đóng</label>
          <div class="fields three"><label>Bắt đầu dời khi lời (× rủi ro)<input id="srTrailStart" inputmode="decimal" value="${c.trailStartR}"></label></div>
          <div class="row-btns">
            ${!st ? "" : c.running ? '<button class="btn btn-ghost" id="srStop">■ Tắt bot</button><button class="btn btn-ghost" id="srSave">Lưu cài đặt</button>' : '<button class="btn btn-gold" id="srStart">▶ Bật bot Cản & Hỗ trợ</button>'}
          </div>
        </div>
        <div id="srLive"></div>`;
      const send = async (button, extra, done) => {
        const r = await act(button, () => this.call("/srbot", Object.assign(this.srSettings(), extra)), done);
        if (r) { this.srStatus = r; this.renderSRBot(r, ""); }
      };
      const start = $("srStart"), stop = $("srStop"), save = $("srSave");
      if (start) start.onclick = (e) => send(e.currentTarget, { running: true }, "Đã bật bot: bot xem từ nến đóng tiếp theo");
      if (stop) stop.onclick = (e) => send(e.currentTarget, { running: false }, "Đã tắt bot (lệnh đang mở giữ nguyên)");
      if (save) save.onclick = (e) => send(e.currentTarget, {}, "Đã lưu");
      this.renderSRBotLive(st);
    },

    renderSRBotLive(st) {
      const live = $("srLive");
      if (!live || !st) { if (live) live.innerHTML = ""; return; }
      const d = (sym) => this.digitsFor(sym), s = st.stats || {};
      live.innerHTML = `<div class="stats">
          <div class="stat"><span>Lệnh đã đóng</span><b>${s.trades || 0}</b></div>
          <div class="stat"><span>Thắng</span><b>${s.wins || 0}${s.trades ? ` (${Math.round(s.wins / s.trades * 100)}%)` : ""}</b></div>
          <div class="stat"><span>Lãi/lỗ</span><b class="${(s.profit || 0) >= 0 ? "pos" : "neg"}">${signed(s.profit || 0)}</b></div>
          <div class="stat"><span>Đang mở</span><b>${(st.positions || []).length}</b></div>
        </div>
        ${st.error ? `<p class="warn">${esc(st.error)}</p>` : ""}
        <div class="list">${(st.positions || []).map((o) => `<div class="sig"><div class="bar" style="background:${o.side === "long" ? "#2b6bf3" : "var(--down)"}"></div>
          <div><div class="top"><span class="sym">${esc(o.symbol)}</span><span class="side ${o.side === "long" ? "buy" : "sell"}">${sideName(o.side)} ${o.lots}</span><span class="muted small">@ ${fmt(o.entry, d(o.symbol))}</span></div>
          <div class="lv">SL ${o.stop ? fmt(o.stop, d(o.symbol)) : "–"} · TP ${o.target ? fmt(o.target, d(o.symbol)) : "–"}</div></div>
          <div class="right"><div class="move ${(o.profit || 0) >= 0 ? "pos" : "neg"}">${signed(o.profit || 0)}</div></div></div>`).join("")}</div>
        ${(st.events || []).length ? `<h4>Hoạt động</h4><div class="list log">${st.events.slice(0, 15).map((e) => `<div class="log-row"><span class="muted small">${clock(e.time)}</span> ${esc(e.text)}</div>`).join("")}</div>` : ""}`;
    },

    /** The Cản & Hỗ trợ bot's settings as its form shows them. */
    srSettings() {
      const c = Object.assign({}, SR_DEFAULTS, (this.srStatus && this.srStatus.config) || {});
      const v = (id) => ($(id) ? $(id).value : null);
      if ($("srSymbol")) {
        Object.assign(c, {
          symbol: v("srSymbol").trim(), interval: v("srInterval"), direction: v("srDirection"), pattern: v("srPattern"),
          lots: num(v("srLots")) || 0.01, rr: num(v("srRR")) ?? 2, wickRatio: (num(v("srWick")) ?? 45) / 100,
          zoneAtr: num(v("srZone")) || 0.3, minTouches: Math.max(1, Math.round(num(v("srTouches")) || 2)),
          lookback: Math.max(30, Math.round(num(v("srLookback")) || 300)), swing: Math.max(1, Math.round(num(v("srSwing")) || 3)),
          slBufferAtr: num(v("srBuffer")) ?? 0.1, trail: $("srTrail").checked, trailStartR: num(v("srTrailStart")) ?? 0.5,
        });
      }
      c.symbol = c.symbol || this.symbol || "XAUUSDm";
      return c;
    },

    /* ----- backtest of the bots: how they would have traded, with their trades on the chart ----- */

    /** The Stop bot's settings as the form above shows them (or as the server has them). */
    stopBotSettings() {
      const c = Object.assign({}, (this.stopStatus && this.stopStatus.config) || {});
      const v = (id) => ($(id) ? $(id).value : null);
      if ($("sbSymbol")) {
        Object.assign(c, {
          symbol: v("sbSymbol").trim(), interval: v("sbInterval"), direction: v("sbDirection"),
          lots: num(v("sbLots")) || 0.01, rr: num(v("sbRR")) ?? 2, offset: num(v("sbOffset")) || 0,
          stopMode: v("sbStopMode"), stopDistance: num(v("sbStopDist")) || 5,
          minRange: num(v("sbMin")) || 0, maxRange: num(v("sbMax")) || 0,
          oco: $("sbOCO").checked, onePosition: $("sbOne").checked,
        });
      }
      c.symbol = c.symbol || this.symbol || "XAUUSDm";
      c.interval = c.interval || "1m";
      return c;
    },

    renderStopBt() {
      const el = $("stopBtPanel");
      const days = +store.get("aurum.btDays") || 7;
      const bot = store.get("aurum.btBot") || "stop";
      el.innerHTML = `<div class="panel-head"><h3>🧪 Backtest bot</h3></div>
        <p class="muted small">Chạy bot đã chọn với đúng cài đặt ở ô của bot đó (phía trên) trên nến Exness đã qua: xem bot vào lệnh ở đâu, chạm TP hay SL, lời lỗ bao nhiêu. Lệnh MUA khớp ở giá Ask = giá nến + spread, đóng ở Bid; lệnh BÁN ngược lại. Chưa tính trượt giá và phí.</p>
        <div class="fields three">
          <label>Bot<select id="btBot"><option value="stop" ${bot === "stop" ? "selected" : ""}>🎯 Stop theo nến</option><option value="sr" ${bot === "sr" ? "selected" : ""}>🧱 Cản & Hỗ trợ</option></select></label>
          <label>Spread (giá, trống = spread hiện tại)<input id="btSpread" inputmode="decimal" placeholder="VD vàng 0.16" value="${esc(store.get("aurum.btSpread") || "")}"></label>
          <label>Thời gian<select id="btDays">${[1, 3, 7, 14, 30, 60].map((d) => `<option value="${d}" ${d === days ? "selected" : ""}>${d} ngày</option>`).join("")}</select></label>
          <label>Vốn ban đầu<input id="btBalance" inputmode="decimal" value="${esc(store.get("aurum.btBalance") || "10000")}"></label>
          <label>&nbsp;<button class="btn btn-gold" id="btRun" type="button">▶ Chạy backtest</button></label>
        </div>
        <p class="muted small" id="btInfo"></p>
        <div id="btResult"></div>`;
      $("btRun").onclick = () => this.runStopBt();
    },

    async runStopBt() {
      const bot = $("btBot").value;
      const c = bot === "sr" ? this.srSettings() : this.stopBotSettings();
      const days = +$("btDays").value, balance = num($("btBalance").value) || 10000;
      store.set("aurum.btDays", String(days)); store.set("aurum.btBalance", String(balance)); store.set("aurum.btBot", bot);
      store.set("aurum.btSpread", $("btSpread").value.trim());
      // Spread: as typed, or the live one when the backtest is on the chart's symbol.
      let spread = num($("btSpread").value);
      if (spread == null) spread = c.symbol === this.symbol && this.bid != null && this.ask != null ? Math.max(0, this.ask - this.bid) : 0;
      const sec = TF_SECONDS[c.interval] || 60, from = Date.now() / 1000 - days * 86400;
      const btn = $("btRun"), info = $("btInfo");
      btn.disabled = true;
      try {
        // Pages of 5000 bars back to the start; the newest bar is still forming.
        info.textContent = `Đang tải nến ${c.symbol} ${c.interval}…`;
        const path = (before) => `/mt5/candles?symbol=${encodeURIComponent(c.symbol)}&interval=${c.interval}&count=5000${before ? `&before=${before}` : ""}`;
        let bars = this.toBars((await this.call(path())).candles || []).slice(0, -1);
        for (let k = 0; k < 20 && bars.length && bars[0].time > from; k++) {
          info.textContent = `Đang tải nến ${c.symbol} ${c.interval}… ${bars.length} nến`;
          const older = this.toBars((await this.call(path(bars[0].time))).candles || []).filter((b) => b.time < bars[0].time);
          if (!older.length) break;
          bars = older.concat(bars);
        }
        bars = bars.filter((b) => b.time >= from);
        if (bars.length < 3) throw new Error(`MT5 chỉ trả ${bars.length} nến ${c.symbol} ${c.interval}`);
        const value = (side, entry, exit) => this.valueAt(c.symbol, c.lots, side, entry, exit);
        const r = bot === "sr" ? srBacktest(bars, c, value, spread) : stopBotBacktest(bars, c, value, spread);
        this.btShow = 30;
        this.btResult = { bot, spread, c, bars: bars.length, from: bars[0].time, to: bars[bars.length - 1].time + sec, balance, placed: r.placed, trades: r.trades, digits: this.digitsFor(c.symbol) };
        info.textContent = "";
        this.renderStopBtResult();
      } catch (e) {
        info.textContent = "Không chạy được: " + plain(e.message);
      } finally { btn.disabled = false; }
    },

    renderStopBtResult() {
      const R = this.btResult, el = $("btResult");
      if (!R) { el.innerHTML = ""; return; }
      const t = R.trades, d = R.digits;
      const wins = t.filter((x) => x.profit > 0), losses = t.filter((x) => x.profit < 0);
      const net = t.reduce((a, x) => a + x.profit, 0);
      const gp = wins.reduce((a, x) => a + x.profit, 0), gl = -losses.reduce((a, x) => a + x.profit, 0);
      let bal = R.balance, peak = bal, dd = 0;
      const curve = [bal];
      t.forEach((x) => { bal += x.profit; peak = Math.max(peak, bal); dd = Math.max(dd, peak - bal); curve.push(bal); });
      const tp = t.filter((x) => x.reason === "target").length, sl = t.filter((x) => x.reason === "stop").length;
      const day = (s) => new Date(s * 1000).toLocaleDateString("vi-VN", { day: "2-digit", month: "2-digit" });
      const stat = (k, v, cls = "") => `<div class="stat"><span>${k}</span><b class="${cls}">${v}</b></div>`;
      // Balance after each trade.
      const W = 600, H = 120, lo = Math.min(...curve), hi = Math.max(...curve), span = hi - lo || 1;
      const pts = curve.map((v, i) => `${(i / Math.max(curve.length - 1, 1) * W).toFixed(1)},${(H - 6 - (v - lo) / span * (H - 12)).toFixed(1)}`).join(" ");
      const color = net >= 0 ? "var(--up)" : "var(--down)";
      const reason = { target: "chạm TP", stop: "chạm SL", trail: "chạm SL đã dời", end: "đóng cuối test" };
      const sr = R.bot === "sr";
      el.innerHTML = `<p class="muted small">${sr ? "🧱 Cản & Hỗ trợ" : "🎯 Stop theo nến"} · ${esc(R.c.symbol)} ${R.c.interval} · spread ${fmt(R.spread, R.digits)} · ${day(R.from)} → ${day(R.to)} · ${R.bars} nến · ${R.c.lots} lot · R:R ${R.c.rr}${R.c.direction === "long" ? " · chỉ Buy" : R.c.direction === "short" ? " · chỉ Sell" : ""}</p>
        <div class="stats">
          ${stat("Lãi/lỗ ròng", signed(net), net >= 0 ? "pos" : "neg")}
          ${stat("Số lệnh", `${t.length} <span class="muted small">/ ${R.placed} ${sr ? "tín hiệu" : "lệnh chờ đặt"}</span>`)}
          ${stat("Thắng", t.length ? `${wins.length}/${t.length} · ${Math.round(wins.length / t.length * 100)}%` : "–")}
          ${stat("Chạm TP / SL", `${tp} / ${sl}${sr ? ` <span class="muted small">· ${t.filter((x) => x.reason === "trail").length} SL dời</span>` : ""}`)}
          ${stat("Profit factor", gl > 0 ? (gp / gl).toFixed(2) : gp > 0 ? "∞" : "–")}
          ${stat("Sụt giảm lớn nhất", dd ? "−" + money(dd) : "0", dd ? "neg" : "")}
          ${stat("Lời TB / lỗ TB", `${wins.length ? signed(gp / wins.length) : "–"} / ${losses.length ? signed(-gl / losses.length) : "–"}`)}
          ${stat("Vốn cuối", money(R.balance + net), net >= 0 ? "pos" : "neg")}
        </div>
        ${t.length ? `<svg class="bt-eq" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"><polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2" vector-effect="non-scaling-stroke"/></svg>` : ""}
        <div class="row-btns"><button class="btn btn-ghost" id="btChart" type="button" ${t.length ? "" : "disabled"}>📈 Xem các lệnh trên biểu đồ</button></div>
        <h4>Lệnh (mới nhất trước)</h4>
        <div class="list bt-trades">${t.length ? t.slice().reverse().slice(0, this.btShow || 30).map((x) => `<div class="sig"><div class="bar" style="background:${x.profit >= 0 ? "var(--up)" : "var(--down)"}"></div>
          <div><div class="top"><span class="side ${x.side === "long" ? "buy" : "sell"}">${sr ? (x.side === "long" ? "BUY" : "SELL") : x.side === "long" ? "BUY STOP" : "SELL STOP"}</span>
            <span class="muted small">${fmt(x.entry, d)} → ${fmt(x.exit, d)}</span></div>
            <div class="lv">${reason[x.reason]}${x.level != null ? ` · vùng ${fmt(x.level, d)}` : ""} · ${clock(x.openTime)} ${day(x.openTime)} · SL ${fmt(x.stop, d)} · TP ${x.target != null ? fmt(x.target, d) : "–"}</div></div>
          <div class="right"><div class="move ${x.profit >= 0 ? "pos" : "neg"}">${signed(x.profit)}</div></div></div>`).join("") : '<div class="empty">Bot không vào lệnh nào trong khoảng này</div>'}</div>
        ${t.length > (this.btShow || 30) ? `<button class="linkish" id="btMore" type="button">Xem thêm (${t.length - (this.btShow || 30)} lệnh nữa)</button>` : ""}`;
      $("btChart").onclick = () => this.showBtOnChart();
      if ($("btMore")) $("btMore").onclick = () => { this.btShow = (this.btShow || 30) + 50; this.renderStopBtResult(); };
    },

    /** Opens the chart on the backtest's symbol and timeframe with its trades marked. */
    showBtOnChart() {
      const R = this.btResult;
      if (!R) return;
      this.btView = R;
      if (this.owner) { this.symbol = R.c.symbol; store.set("aurum.sym", this.symbol); }
      this.interval = R.c.interval; store.set("aurum.tf", this.interval);
      this.setTab("chart");
      this.loadCandles();
    },

    /** ▲/▼ where the bot's backtest entered, ● where it left (TP green, SL red). */
    applyBtMarkers() {
      const R = this.btView, chip = $("btChip");
      const on = !!(R && this.series && (!this.owner || this.symbol === R.c.symbol) && this.interval === R.c.interval && this.bars.length);
      chip.hidden = !on;
      if (!this.series) return;
      if (!on) { if (this.btMarked) { this.series.setMarkers([]); this.btMarked = false; } return; }
      const first = this.bars[0].time, sec = TF_SECONDS[this.interval];
      const bar = (t) => Math.floor(t / sec) * sec;
      const marks = [];
      R.trades.forEach((x) => {
        if (x.openTime < first) return;
        const long = x.side === "long";
        marks.push({ time: bar(x.openTime) + TZ, position: long ? "belowBar" : "aboveBar", color: long ? "#2b6bf3" : "#f0455a", shape: long ? "arrowUp" : "arrowDown", text: long ? "B" : "S" });
        marks.push({ time: bar(x.closeTime) + TZ, position: long ? "aboveBar" : "belowBar", color: x.profit >= 0 ? "#14b88a" : "#f0455a", shape: "circle", text: (x.profit >= 0 ? "+" : "") + x.profit.toFixed(0) });
      });
      marks.sort((a, b) => a.time - b.time);
      try { this.series.setMarkers(marks); this.btMarked = true; } catch { /* bars not there */ }
      const net = R.trades.reduce((a, x) => a + x.profit, 0);
      const hidden = R.trades.filter((x) => x.openTime < first).length;
      chip.innerHTML = `<span>🧪 Backtest bot: ${R.trades.length} lệnh · <b class="${net >= 0 ? "pos" : "neg"}">${signed(net)}</b>${hidden ? ` <span class="muted small">(${hidden} lệnh cũ hơn: kéo sang trái)</span>` : ""}</span><button type="button" title="Ẩn">✕</button>`;
      chip.querySelector("button").onclick = () => { this.btView = null; this.applyBtMarkers(); };
    },

    async loadAutoBot(first) {
      try {
        const [st, hist] = await Promise.all([this.call("/status"), this.call("/history?limit=200")]);
        if (first && !this.samples) {
          const s = await this.call("/samples").catch(() => null);
          this.samples = (s && s.samples) || [];
        }
        this.botStatus = st;
        this.renderBotBadge();
        this.renderAutoStatus(st);
        if (first || !$("autoForm").innerHTML) this.renderAutoForm(st);
        this.renderBotTrades(st, (hist && hist.history) || []);
      } catch (e) {
        if (first) $("autoStatus").innerHTML = `<div class="empty">${esc(plain(e.message))}</div>`;
      }
    },

    renderBotBadge() {
      const st = this.botStatus, b = $("botBadge");
      if (!b) return;
      const parts = [];
      if (this.owner && st && st.running) { const s = st.settings || {}; parts.push(`🤖 Bot: ${s.strategyName || "chiến lược"} · ${s.symbol} ${s.interval}`); }
      const sb = this.stopStatus && this.stopStatus.config;
      if (this.owner && sb && sb.running) parts.push(`🎯 Bot Stop · ${sb.symbol} ${sb.interval}`);
      b.hidden = !parts.length;
      b.textContent = parts.join("  ·  ");
      b.onclick = () => this.setTab("autobot");
    },

    renderAutoStatus(st) {
      const s = st.settings || {}, acc = st.account || {};
      const live = s.broker === "mt5";
      $("autoStatus").innerHTML = `<div class="panel-head"><h3>Bot tự động</h3><span class="badge ${st.running ? "on" : "off"}">${st.running ? "Đang chạy" : "Đang dừng"}</span></div>
        <div class="stats">
          <div class="stat"><span>Chiến lược</span><b>${esc(s.strategyName || "–")}</b></div>
          <div class="stat"><span>Mã · khung</span><b>${esc(s.symbol || "–")} · ${esc(s.interval || "")}</b></div>
          <div class="stat"><span>Đặt lệnh</span><b>${live ? '<span class="neg">MT5 thật</span>' : "Demo trên máy chủ"}</b></div>
          <div class="stat"><span>${s.riskPercent ? "Rủi ro mỗi lệnh" : "Khối lượng"}</span><b>${s.riskPercent ? s.riskPercent + "%" : (s.lots || 0.01) + " lot"}</b></div>
          <div class="stat"><span>Số dư</span><b>${acc.balance != null ? money(acc.balance) : "–"}</b></div>
          <div class="stat"><span>Vốn</span><b>${acc.equity != null ? money(acc.equity) : "–"}</b></div>
          <div class="stat"><span>Lãi/lỗ đang chạy</span><b class="${(acc.openProfit || 0) >= 0 ? "pos" : "neg"}">${signed(acc.openProfit || 0)}</b></div>
          <div class="stat"><span>Nến mới nhất</span><b>${st.lastBarTime ? clock(st.lastBarTime) : "–"}</b></div>
        </div>
        ${st.error ? `<p class="warn">${esc(st.error)}</p>` : ""}
        ${acc.error ? `<p class="warn">${esc(acc.error)}</p>` : ""}
        <div class="row-btns">
          ${st.running ? '<button class="btn btn-ghost" id="abStop">■ Dừng bot</button>' : `<button class="btn btn-gold" id="abRestart" ${s.strategyName ? "" : "disabled"}>▶ Chạy lại như cũ</button>`}
          ${!live ? '<button class="btn btn-ghost" id="abReset">Đặt lại tài khoản demo</button>' : ""}
        </div>
        <p class="muted small">Dừng bot không đóng lệnh đang mở: lệnh vẫn giữ SL/TP. Chỉ chủ thấy tab này.</p>`;
      const stop = $("abStop"), restart = $("abRestart"), reset = $("abReset");
      if (stop) stop.onclick = async (e) => { await act(e.currentTarget, () => this.call("/stop", {}), "Đã dừng bot"); this.loadAutoBot(false); };
      if (restart) restart.onclick = async (e) => { await act(e.currentTarget, () => this.call("/start", {}), "Bot đã chạy"); this.loadAutoBot(false); };
      if (reset) reset.onclick = async (e) => {
        const v = prompt("Số dư demo mới (USD):", "10000");
        if (!v || !num(v)) return;
        await act(e.currentTarget, () => this.call("/reset", { balance: num(v) }), "Đã đặt lại tài khoản demo");
        this.loadAutoBot(false);
      };
    },

    renderAutoForm(st) {
      const s = st.settings || {};
      const current = s.strategyName && !s.sampleStrategy ? s.strategyName : null;
      const tfs = ["1m", "5m", "15m", "30m", "1h", "4h", "1d"];
      $("autoForm").innerHTML = `<h3>Chạy bot</h3>
        <div class="fields two">
          <label>Chiến lược<select id="abStrategy">
            ${current ? `<option value="">Đang dùng: ${esc(current)} (từ app)</option>` : ""}
            ${(this.samples || []).map((n) => `<option value="${esc(n)}" ${s.sampleStrategy === n ? "selected" : ""}>Mẫu: ${esc(n)}</option>`).join("")}
          </select></label>
          <label>Nguồn giá<select id="abSource">
            <option value="mt5" ${s.source === "mt5" ? "selected" : ""}>MT5 (Exness)</option>
            <option value="binance_futures" ${s.source === "binance_futures" ? "selected" : ""}>Binance Futures</option>
          </select></label>
        </div>
        <div class="fields three">
          <label>Mã<input id="abSymbol" value="${esc(s.symbol || this.symbol || "XAUUSDm")}"></label>
          <label>Khung<select id="abInterval">${tfs.map((t) => `<option ${t === s.interval ? "selected" : ""}>${t}</option>`).join("")}</select></label>
          <label>Đặt lệnh<select id="abBroker">
            <option value="paper" ${s.broker !== "mt5" ? "selected" : ""}>Demo trên máy chủ</option>
            <option value="mt5" ${s.broker === "mt5" ? "selected" : ""}>MT5 (tài khoản đang đăng nhập)</option>
          </select></label>
        </div>
        <div class="fields two">
          <label>Lot mỗi lệnh<input id="abLots" inputmode="decimal" value="${s.lots || 0.01}"></label>
          <label>Rủi ro % mỗi lệnh (0 = dùng lot)<input id="abRisk" inputmode="decimal" value="${s.riskPercent || 0}"></label>
        </div>
        <label class="check"><input type="checkbox" id="abLong" ${s.allowLong !== false ? "checked" : ""}> Cho phép MUA</label>
        <label class="check"><input type="checkbox" id="abShort" ${s.allowShort !== false ? "checked" : ""}> Cho phép BÁN</label>
        <label class="check"><input type="checkbox" id="abReverse" ${s.reverse !== false ? "checked" : ""}> Đóng và đảo chiều khi có tín hiệu ngược</label>
        <button class="btn btn-gold wide" id="abStart">▶ Chạy bot với cài đặt này</button>
        <p class="muted small">Chiến lược tự viết và quy tắc dừng lỗ nâng cao chọn trong app (Backtest → Bot). Đặt lệnh MT5 cần nguồn giá MT5 và bật "Cho phép đặt lệnh" ở tab Máy chủ.</p>`;
      $("abSource").onchange = () => {
        const mt5 = $("abSource").value === "mt5";
        if (!mt5) { $("abBroker").value = "paper"; if (/m$|XAUUSD$/.test($("abSymbol").value)) $("abSymbol").value = "XAUUSDT"; }
        else if ($("abSymbol").value === "XAUUSDT") $("abSymbol").value = this.symbol || "XAUUSDm";
      };
      $("abStart").onclick = async (e) => {
        const broker = $("abBroker").value, source = $("abSource").value;
        if (broker === "mt5" && source !== "mt5") return toast("Đặt lệnh MT5 cần nguồn giá MT5", true);
        if (broker === "mt5" && !confirm("Bot sẽ đặt lệnh THẬT trên tài khoản MT5 đang đăng nhập. Tiếp tục?")) return;
        const body = {
          source, symbol: $("abSymbol").value.trim(), interval: $("abInterval").value, broker,
          lots: num($("abLots").value) || 0.01, riskPercent: num($("abRisk").value) || 0,
          allowLong: $("abLong").checked, allowShort: $("abShort").checked, reverse: $("abReverse").checked,
        };
        if ($("abStrategy").value) body.sampleStrategy = $("abStrategy").value;
        const ok = await act(e.currentTarget, () => this.call("/start", body), "Bot đã chạy");
        if (ok) this.loadAutoBot(false);
      };
    },

    renderBotTrades(st, history) {
      const pos = st.positions || [];
      const d = (sym) => this.digitsFor(sym);
      $("botPosTitle").textContent = pos.length ? `Lệnh của bot · ${pos.length}` : "Lệnh của bot";
      $("botCloseAll").hidden = !pos.length;
      $("botCloseAll").onclick = async (e) => {
        if (!confirm(`Đóng ${pos.length} lệnh của bot?`)) return;
        await act(e.currentTarget, () => this.call("/close", { all: true }), "Đã đóng lệnh của bot");
        this.loadAutoBot(false);
      };
      $("botPositions").innerHTML = pos.length ? pos.map((p, i) => `<div class="sig" data-i="${i}">
          <div class="bar" style="background:${p.side === "long" ? "#2b6bf3" : "var(--down)"}"></div>
          <div><div class="top"><span class="sym">${esc(p.symbol)}</span><span class="side ${p.side === "long" ? "buy" : "sell"}">${sideName(p.side)} ${p.lots}</span><span class="muted small">vào ${fmt(p.entryPrice, d(p.symbol))}</span></div>
            <div class="lv">SL ${p.stop ? fmt(p.stop, d(p.symbol)) : "–"} · TP ${p.target ? fmt(p.target, d(p.symbol)) : "–"}${p.openTime ? " · " + clock(p.openTime) : ""}</div></div>
          <div class="right"><div class="move ${(p.profit || 0) >= 0 ? "pos" : "neg"}">${signed(p.profit || 0)}</div></div>
          <button class="x" type="button" title="Đóng lệnh">✕</button></div>`).join("") : '<div class="empty">Bot chưa có lệnh đang mở</div>';
      $("botPositions").querySelectorAll("[data-i]").forEach((row) => (row.querySelector(".x").onclick = async (e) => {
        const p = pos[+row.dataset.i];
        await act(e.currentTarget, () => this.call("/close", { id: p.id }), "Đã đóng lệnh");
        this.loadAutoBot(false);
      }));
      const total = history.reduce((a, t) => a + (t.profit || 0), 0);
      const wins = history.filter((t) => (t.profit || 0) > 0).length;
      $("botStats").innerHTML = [
        ["Lãi/lỗ", `<span class="${total >= 0 ? "pos" : "neg"}">${signed(total)}</span>`], ["Số lệnh", history.length],
        ["Thắng / thua", `${wins} / ${history.length - wins}`], ["Tỉ lệ thắng", history.length ? Math.round(wins / history.length * 100) + "%" : "–"],
      ].map(([k, v]) => `<div class="stat"><span>${k}</span><b>${v}</b></div>`).join("");
      $("botHistory").innerHTML = history.length ? history.slice(0, 80).map((t) => {
        const color = t.reason === "target" ? "var(--up)" : t.reason === "stop" ? "var(--down)" : "#5b6478";
        return `<div class="sig"><div class="bar" style="background:${color}"></div>
          <div><div class="top"><span class="sym">${esc(t.symbol)}</span><span class="side ${t.side === "long" ? "buy" : "sell"}">${sideName(t.side)} ${t.lots}</span>
            <span class="muted small">${t.entryPrice != null ? fmt(t.entryPrice, d(t.symbol)) + " → " : ""}${fmt(t.exitPrice, d(t.symbol))}</span></div>
            <div class="lv">${t.reason === "target" ? "Chạm TP" : t.reason === "stop" ? "Chạm SL" : t.reason === "reverse" ? "Đảo chiều" : "Đóng tay"} · ${t.exitTime ? clock(t.exitTime) : ""}</div></div>
          <div class="right"><div class="move ${(t.profit || 0) >= 0 ? "pos" : "neg"}">${signed(t.profit || 0)}</div></div></div>`;
      }).join("") : '<div class="empty">Chưa có lệnh đã đóng</div>';
    },

    /* ----- bot & server ----- */

    async loadBot(first) {
      if (!first && $("sheet").open) return;
      try {
        const [s, log] = await Promise.all([this.call("/status"), this.call("/log?limit=80")]);
        const st = s.settings || {};
        const acc = s.account || {};
        $("botPanel").innerHTML = `<div class="panel-head"><h3>Máy chủ</h3><button class="bot-badge" id="toBot" type="button">🤖 Bot: ${s.running ? "đang chạy" : "đang dừng"} · mở tab Bot</button></div>
          <p class="muted small">Telegram: ${s.telegram && s.telegram.configured ? (s.telegram.linked ? "đã nối" : "chưa nối chat") : "chưa cài"}.${st.strategyName ? " Chiến lược bot: " + esc(st.strategyName) + "." : ""}${acc.error ? " " + esc(acc.error) : ""}</p>
          <div class="kvs"><div class="kv"><span>Phiên bản</span><b>${esc(s.version)}</b></div>
            <div class="kv"><span>Chạy từ</span><b>${s.startedAt ? fullTime(s.startedAt) : "–"}</b></div>
            <div class="kv"><span>MT5</span><b>${s.mt5 && s.mt5.connected ? "Đã kết nối" : esc((s.mt5 && s.mt5.error) || "Chưa kết nối")}</b></div></div>
          <button class="btn btn-ghost wide" id="srvUpdate">Cập nhật máy chủ lên bản mới nhất</button>`;
        $("toBot").onclick = () => this.setTab("autobot");
        $("srvUpdate").onclick = async (e) => {
          if (!confirm("Cập nhật máy chủ? Máy chủ tự khởi động lại trong khoảng 1 phút.")) return;
          const r = await act(e.currentTarget, () => this.call("/update", {}));
          if (r) toast(r.message || (r.updated === false ? "Đã là bản mới nhất" : "Đang cập nhật, chờ khoảng 1 phút…"));
        };
        if (first || !$("mt5Panel").innerHTML) this.renderMt5Settings();
        $("logList").innerHTML = (log.log || []).map((l) => `<div class="log-row"><span class="muted small">${clock(l.time)}</span> ${esc(l.text)}</div>`).join("") || '<div class="empty">Trống</div>';
      } catch (e) {
        if (first) $("botPanel").innerHTML = `<div class="empty">${esc(e.message)}</div>`;
      }
    },

    renderMt5Settings() {
      const t = this.account || {};
      $("mt5Panel").innerHTML = `<h3>Đặt lệnh MT5</h3>
        <label class="toggle"><span>Cho phép đặt lệnh từ app / web</span><span class="switch"><input type="checkbox" id="tOn" ${t.tradingEnabled ? "checked" : ""}><span></span></span></label>
        <label class="toggle"><span>Cho phép tài khoản THẬT</span><span class="switch"><input type="checkbox" id="tReal" ${t.allowReal ? "checked" : ""}><span></span></span></label>
        <div class="fields"><label>Lot tối đa mỗi lệnh<input id="tMax" inputmode="decimal" value="${t.maxLots || 0.1}"></label></div>
        <button class="btn btn-ghost wide" id="tSave">Lưu</button>`;
      const save = async (button) => {
        const r = await act(button, () => this.call("/mt5/settings", { trading_enabled: $("tOn").checked, allow_real_account: $("tReal").checked, max_lots: num($("tMax").value) || 0.1 }), "Đã lưu");
        if (r) { this.account = Object.assign(this.account || {}, r); }
      };
      $("tOn").onchange = () => save(null);
      $("tReal").onchange = () => save(null);
      $("tSave").onclick = (e) => save(e.currentTarget);
    },

    /* ----- chart ----- */

    buildChart() {
      const el = $("chart");
      if (!window.LightweightCharts) { el.innerHTML = '<p class="muted small">Không tải được biểu đồ.</p>'; return; }
      if (!this.chart) {
        this.chart = LightweightCharts.createChart(el, {
          autoSize: true,
          layout: { background: { color: "#151c2a" }, textColor: "#8b95a7", fontFamily: "-apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif" },
          grid: { vertLines: { color: "#1a2233" }, horzLines: { color: "#1a2233" } },
          rightPriceScale: { borderColor: "#222c3d" },
          timeScale: { borderColor: "#222c3d", timeVisible: true, secondsVisible: false, rightOffset: 8, barSpacing: el.clientWidth < 500 ? 4 : 6 },
          localization: { timeFormatter: (t) => this.timeLabel(t) },
          crosshair: { mode: 0 },
        });
        this.series = this.chart.addCandlestickSeries({
          upColor: "#14b88a", downColor: "#f0455a", borderVisible: false, wickUpColor: "#14b88a", wickDownColor: "#f0455a",
          // The picked trade's SL/TP and the pending draft stay in view so they can be dragged.
          autoscaleInfoProvider: (original) => {
            const res = original();
            const keep = (this.lineCache || []).filter((w) => {
              if (w.key.startsWith("draft:")) return true;
              const s = this.selected;
              return s && w.key.startsWith(`${s.kind}:${s.ticket}:`);
            }).map((w) => w.price);
            if (!res || !keep.length) return res;
            return { priceRange: { minValue: Math.min(res.priceRange.minValue, ...keep), maxValue: Math.max(res.priceRange.maxValue, ...keep) }, margins: res.margins };
          },
        });
        this.ictCfg = (() => { try { return window.ICT.merge(JSON.parse(store.get("aurum.ictcfg") || "null")); } catch { return window.ICT.defaults(); } })();
        this.magnet = store.get("aurum.magnet") !== "0";
        this.lastSmtSymbol = this.ictCfg.smtSymbol;
        this.loadStudies();
        const term = this;
        // ICT layer: painted in the chart's own frame (under the candles), so it never lags a drag.
        this.series.attachPrimitive({
          attached(p) { term.requestICT = p.requestUpdate; },
          detached() {},
          updateAllViews() {},
          paneViews() {
            return [{
              zOrder: () => "bottom",
              renderer: () => ({
                draw: (target) => target.useMediaCoordinateSpace(({ context, mediaSize }) => {
                  const ts = term.chart.timeScale();
                  const X = (i) => ts.logicalToCoordinate(i), Y = (v) => term.series.priceToCoordinate(v);
                  if (term.ict) window.ICT.draw(context, term.ict, term.ictCfg, X, Y, mediaSize.width, mediaSize.height);
                  if (term.smt) window.ICT.drawSMT(context, term.smt, X, Y, mediaSize.width, { bull: term.ictCfg.smtBull, bear: term.ictCfg.smtBear });
                }),
              }),
            }, {
              // Shark bubbles over the candles, like the app.
              zOrder: () => "top",
              renderer: () => ({
                draw: (target) => target.useMediaCoordinateSpace(({ context, mediaSize }) => {
                  if (!term.sharks) return;
                  const ts = term.chart.timeScale();
                  window.ICT.drawSharks(context, term.sharks, term.viewBars(), (i) => ts.logicalToCoordinate(i), (v) => term.series.priceToCoordinate(v),
                    mediaSize.width, (term.chartStyle.up || "#14b88a").slice(0, 7), (term.chartStyle.down || "#f0455a").slice(0, 7));
                }),
              }),
            }, {
              zOrder: () => "top",
              renderer: () => ({
                draw: (target) => target.useMediaCoordinateSpace(({ context, mediaSize }) => term.drawPositions(context, mediaSize.width)),
              }),
            }];
          },
          // Open positions: dotted entry line from the entry candle, a dot on it, side and money label.
          // (a third pane view, above the candles)
          priceAxisViews() { return term.countdownView ? [term.countdownView] : []; },
        });
        this.countdownView = {
          coordinate: () => {
            const v = this.viewBars(), b = v[v.length - 1];
            const y = b ? this.series.priceToCoordinate(b.close) : null;
            return y == null ? -100 : y + 19;
          },
          text: () => this.countdownText(),
          textColor: () => "#ffffff",
          backColor: () => { const v = this.viewBars(), b = v[v.length - 1]; return b && b.close < b.open ? this.chartStyle.down : this.chartStyle.up; },
          visible: () => !this.replay && this.bars.length > 0 && (this.source === "exness" || !!this.secFeed),
          tickVisible: () => false,
        };
        setInterval(() => { if (this.tab === "chart" && this.requestICT) this.requestICT(); }, 1000);
        this.drawings = this.drawingsMain = new window.AurumDrawings({
          chart: this.chart, series: this.series, store,
          bars: () => this.viewBars(), sec: () => TF_SECONDS[this.interval], digits: () => this.digits,
          symbol: () => this.symbolKey(), magnet: () => this.magnet, onChange: () => this.renderDrawBar(),
          interval: () => this.interval, onEdit: (d, isNew) => this.drawingSettings(d, isNew),
        });
        this.chartStyle = loadChartStyle();
        this.applyChartStyle();
        this.layout = ["1", "h", "v"].includes(store.get("aurum.layout")) ? store.get("aurum.layout") : "1";
        $("tfButtons").innerHTML = TFS.map((i) => `<button type="button" data-tf="${i}"${i === "30s" ? ' class="sec-end" title="Nến giây lấy từ Binance"' : isSecTF(i) ? ' title="Nến giây lấy từ Binance"' : ""}>${i}</button>`).join("");
        $("tfButtons").querySelectorAll("button").forEach((b) => (b.onclick = () => {
          this.interval = b.dataset.tf; store.set("aurum.tf", this.interval); this.loadCandles();
        }));
        this.chart.timeScale().subscribeVisibleLogicalRangeChange((r) => { if (r && r.from < 30 && !(performance.now() < this.olderHold)) this.loadOlder(); });
        this.bindDrag();
        this.bindTicket();
      }
      this.applySeriesFormat();
      this.loadCandles();
    },

    /** Crosshair time: with seconds on the second charts. */
    timeLabel(t) {
      const o = { timeZone: "UTC", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" };
      if (isSecTF(this.interval)) o.second = "2-digit";
      return new Date(t * 1000).toLocaleString("vi-VN", o);
    },

    applySeriesFormat() {
      if (this.series) this.series.applyOptions({ priceFormat: { type: "price", precision: this.digits, minMove: Math.pow(10, -this.digits) } });
    },

    bindTicket() {
      $("sellBtn").onclick = (e) => this.marketOrder("short", e.currentTarget);
      $("buyBtn").onclick = (e) => this.marketOrder("long", e.currentTarget);
      $("lotInput").value = store.get("aurum.lots") || "0.01";
      $("lotInput").onchange = () => { $("lotInput").value = this.lots().toFixed(2); store.set("aurum.lots", $("lotInput").value); };
      document.querySelectorAll("#ticket [data-step]").forEach((b) => (b.onclick = () => this.stepLots($("lotInput"), +b.dataset.step, "aurum.lots")));
      $("lotPick").onclick = () => this.lotMenu($("lotInput"), "aurum.lots");
      $("pendingToggle").onclick = () => this.togglePending();
      $("pPrice").oninput = () => { this.placeDraftStops(); this.updatePendingLabels(); this.syncLines(); };
      ["pStop", "pTarget"].forEach((id) => ($(id).oninput = () => { this.readDraftDist(); this.syncLines(); }));
      $("pStopType").onchange = () => { this.placeDraftStops(); this.updatePendingLabels(); this.syncLines(); };
      $("pPlace").onclick = (e) => this.pendingOrder(e.currentTarget);
      $("pCancel").onclick = () => this.togglePending(false);
      $("layoutBtn").onclick = (e) => this.layoutMenu(e.currentTarget);
      $("chartSymbol2").onclick = () => { if (this.owner) this.pickCmp(); };
      // The second chart trades its own symbol; ⇄ swaps the two charts.
      const lots2 = () => clampLots(num($("lotInput2").value));
      $("lotInput2").value = store.get("aurum.lots2") || "0.01";
      $("lotInput2").onchange = () => { $("lotInput2").value = lots2().toFixed(2); store.set("aurum.lots2", $("lotInput2").value); };
      document.querySelectorAll("[data-step2]").forEach((b) => (b.onclick = () => this.stepLots($("lotInput2"), +b.dataset.step2, "aurum.lots2")));
      $("lotPick2").onclick = () => this.lotMenu($("lotInput2"), "aurum.lots2");
      $("sellBtn2").onclick = (e) => this.marketOrder("short", e.currentTarget, this.cmpName, lots2());
      $("buyBtn2").onclick = (e) => this.marketOrder("long", e.currentTarget, this.cmpName, lots2());
      $("swapBtn").onclick = () => {
        if (!this.owner || !this.cmpName || this.source !== "exness") return;
        const main = this.symbol;
        this.symbol = this.cmpName; store.set("aurum.sym", this.symbol);
        this.ictCfg.smtSymbol = main; this.saveIct();
        this.selected = null; this.togglePending(false);
        this.loadCandles();
      };
      $("indBtn").onclick = () => this.indicatorSheet();
      $("drawBtn").onclick = () => this.toggleRail();
      $("styleBtn").onclick = () => this.chartStyleSheet();
      $("replayBtn").onclick = () => this.startReplayPick();
      $("chartSymbol").onclick = () => this.symbolSheet();

      $("closeAllBtn").onclick = (e) => this.closeAll(e.currentTarget);
    },

    indicatorSheet() {
      const allowed = this.owner || this.features.killzones !== false;
      const flowAllowed = this.owner || this.features.sharkflow !== false;
      sheet.open(`<h3>Chỉ báo</h3>
        <div class="toggles">${IND.filter(([k]) => (k === "flow" ? flowAllowed : allowed)).map(([k, n]) => `<label class="toggle"><span>${n}</span>
          <span class="switch"><input type="checkbox" data-k="${k}" ${showInd[k] ? "checked" : ""}><span></span></span></label>`).join("")}</div>
        ${allowed ? '<button class="btn btn-ghost wide" id="ictMore">⚙ Cài đặt chi tiết (phiên, màu, FVG, MSS…)</button>' : ""}
        <h4>Chỉ báo kỹ thuật</h4>
        <div class="list" id="studyList"></div>
        <select id="addStudy" class="add-study"><option value="">＋ Thêm chỉ báo…</option>${Object.entries(window.TA ? window.TA.STUDIES : {}).map(([k, d]) => `<option value="${k}">${esc(d.name)}</option>`).join("")}</select>
        <p class="muted small">Giờ theo New York như bản TradingView. Chuột phải (hoặc giữ lâu) trên biểu đồ để mở menu.</p>`, (el) => {
        const more = el.querySelector("#ictMore");
        if (more) more.onclick = () => { sheet.close(); this.ictSettingsSheet(); };
        const listStudies = () => {
          const box = el.querySelector("#studyList");
          box.innerHTML = this.studies.length ? this.studies.map((x) => `<div class="study-row" data-id="${x.id}">
              <span class="dot" style="background:${x.colors[0]}"></span><span class="grow ${x.hidden ? "muted" : ""}">${esc(this.studyLabel(x))}</span>
              <button type="button" data-a="edit" title="Cài đặt">⚙</button><button type="button" data-a="eye" title="Ẩn/hiện">${x.hidden ? "🙈" : "👁"}</button><button type="button" data-a="del" title="Xoá">✕</button></div>`).join("")
            : '<div class="empty">Chưa có — chọn ở ô dưới để thêm (EMA, RSI, MACD…)</div>';
          box.querySelectorAll(".study-row").forEach((row) => {
            const x = this.studies.find((y) => y.id === row.dataset.id);
            row.querySelector("[data-a=edit]").onclick = () => { sheet.close(); this.studySettings(x); };
            row.querySelector("[data-a=eye]").onclick = () => { x.hidden = !x.hidden; this.saveStudies(); listStudies(); };
            row.querySelector("[data-a=del]").onclick = () => { this.removeStudy(x.id); listStudies(); };
          });
        };
        listStudies();
        el.querySelector("#addStudy").onchange = (e) => { if (!e.target.value) return; this.addStudy(e.target.value); e.target.value = ""; listStudies(); };
        el.querySelectorAll("input[data-k]").forEach((i) => (i.onchange = () => {
          showInd[i.dataset.k] = i.checked;
          store.set("aurum.ind", JSON.stringify(showInd));
          if (i.dataset.k === "smt") this.loadCmp();
          this.computeICT(); this.redraw(); this.updateFlow();
        }));
      });
    },

    symbolSheet(onPick) {
      if (!this.owner) return;
      sheet.open(`<h3>Chọn mã</h3><div class="fields"><label>Tìm<input id="symQ" placeholder="XAU, EURUSD, BTC…" autocomplete="off"></label></div><div id="symList" class="list sym-list"></div>`, (el) => {
        const q = el.querySelector("#symQ");
        let timer = null;
        const search = async () => {
          const found = await this.call(`/mt5/symbols?q=${encodeURIComponent(q.value.trim())}&limit=40`).catch(() => null);
          const list = (found && found.symbols) || [];
          el.querySelector("#symList").innerHTML = list.map((x) => `<button type="button" class="sym-row" data-s="${esc(x.name)}"><b>${esc(x.name)}</b><span class="muted small">${esc(x.description)}</span></button>`).join("") || '<div class="empty">Không thấy mã</div>';
          el.querySelectorAll(".sym-row").forEach((b) => (b.onclick = () => {
            sheet.close();
            if (onPick) { onPick(b.dataset.s); return; }
            this.symbol = b.dataset.s; store.set("aurum.sym", this.symbol);
            this.selected = null; this.loadCandles();
          }));
        };
        q.oninput = () => { clearTimeout(timer); timer = setTimeout(search, 250); };
        search();
        setTimeout(() => q.focus(), 50);
      });
    },

    async ownerSymbol() {
      if (this.symbol) return this.symbol;
      const gold = this.positions.find((p) => /XAU/i.test(p.symbol));
      if (gold) { this.symbol = gold.symbol; return this.symbol; }
      const found = await this.call("/mt5/symbols?q=XAUUSD&limit=10").catch(() => null);
      const names = ((found && found.symbols) || []).map((x) => x.name);
      this.symbol = names.find((n) => /^XAUUSD/i.test(n)) || names[0] || "XAUUSD";
      return this.symbol;
    },

    exnessPath(count, before) {
      const extra = before ? `&before=${before}` : "";
      return this.owner
        ? `/mt5/candles?symbol=${encodeURIComponent(this.symbol)}&interval=${this.interval}&count=${count}${extra}`
        : `/member/candles?interval=${this.interval}&count=${count}${extra}`;
    },

    toBars(rows) {
      return rows.map((r) => ({ time: r[0], open: r[1], high: r[2], low: r[3], close: r[4], volume: r[5] || 0 }));
    },

    setQuote(data) {
      if (data.bid != null) this.bid = data.bid;
      if (data.ask != null) this.ask = data.ask;
      const last = this.bars.length ? this.bars[this.bars.length - 1].close : null;
      $("livePrice").textContent = fmt(this.bid != null ? this.bid : last, this.digits);
      $("bidText").textContent = fmt(this.bid != null ? this.bid : last, this.digits);
      $("askText").textContent = fmt(this.ask != null ? this.ask : last, this.digits);
      $("spread").textContent = spreadText(this.bid, this.ask, this.digits);
      if (this.draft) this.updatePendingLabels();
    },

    async loadCandles() {
      // Replay keeps its moment across timeframes: the end of the bar shown last.
      const replayTime = this.replay ? this.bars[this.replay.idx].time + TF_SECONDS[this.replayInterval || this.interval] - 1 : null;
      this.replayInterval = this.interval;
      document.querySelectorAll("#tfButtons button").forEach((b) => b.classList.toggle("on", b.dataset.tf === this.interval));
      // The picked timeframe in view on a phone, where the row scrolls.
      const tfBox = $("tfButtons"), tfOn = tfBox.querySelector(".on");
      if (tfOn) {
        const a = tfOn.getBoundingClientRect(), c = tfBox.getBoundingClientRect();
        if (a.left < c.left || a.right > c.right) tfBox.scrollLeft += a.left - c.left - 8;
      }
      if (this.socket) { this.socket.close(); this.socket = null; }
      clearInterval(this.pollTimer); this.pollTimer = null;
      this.noOlder = false;
      this.secFeed = null;
      const token = (this.loadToken = (this.loadToken || 0) + 1);
      this.applyChartStyle();
      if (this.chart2) this.chart2.applyOptions({ timeScale: { secondsVisible: isSecTF(this.interval) } });
      // Another symbol: the old one's quote and price range must not linger on it.
      const symKey = this.owner ? this.symbol : "member";
      if (symKey !== this.loadedSymbol) { this.bid = this.ask = null; this.loadedSymbol = symKey; }
      if (isSecTF(this.interval)) return this.loadSeconds(token);
      let failure = null;
      try {
        if (this.owner) await this.ownerSymbol();
        // A symbol just added to MT5 has no bars until the terminal fetches its history: ask again a few times.
        let data = null, bars = [];
        for (let attempt = 0; attempt < (this.owner ? 4 : 1); attempt++) {
          if (attempt) {
            $("chartSource").textContent = `· đang tải nến ${this.symbol} từ MT5…`;
            await new Promise((r) => setTimeout(r, 1200));
            if (token !== this.loadToken) return;
          }
          try {
            data = await this.call(this.exnessPath(800));
            bars = this.toBars(data.candles || []);
            failure = bars.length < 5 ? new Error("MT5 chưa có nến cho mã này") : null;
          } catch (e) { failure = e; if (e instanceof Unreachable) break; }
          if (token !== this.loadToken) return;
          if (!failure) break;
        }
        if (failure) throw failure;
        this.source = "exness";
        if (data.symbol) this.symbol = this.owner ? this.symbol : data.symbol;
        this.digits = data.digits != null ? data.digits : 2;
        this.applySeriesFormat();
        $("chartSymbol").textContent = data.symbol || this.symbol || "XAUUSD";
        $("chartSource").textContent = "";
        this.bars = bars;
        if (this.drawKey !== this.symbolKey()) { this.drawKey = this.symbolKey(); this.drawings.load(); }
        if (replayTime != null) {
          for (let k = 0; k < 6 && this.bars[0].time > replayTime && !this.noOlder; k++) await this.loadOlder(true);
          let i = this.bars.length - 1;
          while (i > 0 && this.bars[i].time > replayTime) i--;
          this.replay.idx = Math.max(1, Math.min(i, this.bars.length - 2));
          this.applyReplay(true);
        } else {
          this.showFresh(bars);
          this.computeICT();
        }
        this.setQuote(data);
        this.pollTimer = setInterval(() => this.pollBars(token), 2000);
      } catch (e) {
        if (token !== this.loadToken) return;
        const market = binanceMarket(this.owner ? this.symbol : "XAUUSD");
        if (market) await this.loadBinance(market);
        else this.showNoBars(token, plain((e || failure || {}).message || ""));
      }
      this.syncLines();
      this.updateFlow();
      this.redraw();
      this.applyBtMarkers();
      if (this.layout !== "1") this.setLayout(this.layout); else if (this.smtWanted()) this.loadCmp();
    },

    // The newest bars every 2 seconds (MT5 has no public stream).
    async pollBars(token) {
      if (this.polling) return;
      this.polling = true;
      try {
        const data = await this.call(this.exnessPath(3));
        if (token !== this.loadToken) return;
        const fresh = this.toBars(data.candles || []);
        let added = false;
        fresh.forEach((b) => {
          const last = this.bars[this.bars.length - 1];
          if (!last || b.time > last.time) { this.bars.push(b); added = true; } else if (b.time === last.time) this.bars[this.bars.length - 1] = b; else return;
          if (!this.replay) this.series.update(shown(b));
        });
        if (this.replay) return;
        this.setQuote(data);
        if (added || !this.ictTime || Date.now() - this.ictTime > 4000) this.computeICT();
      } catch { /* keep the chart */ } finally { this.polling = false; }
    },

    /** New bars (another timeframe or symbol), shown from the newest one. */
    showFresh(bars) {
      // At once, before and after the new data: the old timeframe's scroll would otherwise land on the
      // first bars and start a fetch of older ones that keeps it there.
      const ts = this.chart.timeScale();
      ts.scrollToPosition(8, false);
      this.olderHold = performance.now() + 800;
      // The price scale follows the new bars (a hand-set range would keep the old symbol's prices).
      this.chart.priceScale("right").applyOptions({ autoScale: true });
      this.series.setData(bars.map(shown));
      ts.scrollToPosition(8, false);
    },

    /** 5s / 10s / 15s: Binance bars (MT5 has none under a minute); orders still go to MT5 at its own price. */
    async loadSeconds(token) {
      let symbol = $("chartSymbol").textContent || "XAUUSD";
      if (this.owner) symbol = await this.ownerSymbol().catch(() => this.symbol || "XAUUSD");
      if (token !== this.loadToken) return;
      const market = binanceMarket(symbol);
      if (!market) {
        toast("Khung giây chỉ có cho vàng, bạc và crypto (lấy nến từ Binance)", true);
        this.interval = "1m"; store.set("aurum.tf", "1m");
        return this.loadCandles();
      }
      const sec = TF_SECONDS[this.interval];
      const feed = new SecondFeed(market, sec);
      $("chartSource").textContent = `· đang tải nến ${this.interval} từ Binance…`;
      try {
        await feed.history(Math.max(240, Math.round(3600 / sec)));
      } catch {
        if (token !== this.loadToken) return;
        $("chartSource").textContent = "· không tải được nến giây từ Binance";
        return;
      }
      if (token !== this.loadToken) return;
      if (this.replay) { clearInterval(this.replay.timer); this.replay = null; this.replayPicking = false; this.renderReplayBar(); }
      this.secFeed = feed; this.socket = feed;
      this.source = "binance";
      this.digits = market.digits;
      this.applySeriesFormat();
      $("chartSymbol").textContent = this.owner ? this.symbol : symbol;
      this.bars = feed.bars;
      if (this.drawKey !== this.symbolKey()) { this.drawKey = this.symbolKey(); this.drawings.load(); }
      const label = () => {
        // Where second bars come from is not shown (only problems are).
        $("chartSource").textContent = "";
      };
      label();
      this.showFresh(this.bars);
      this.computeICT();
      this.quoteLive = false;
      this.setQuote({});
      feed.live((added) => {
        if (token !== this.loadToken || this.replay) return;
        const last = this.bars[this.bars.length - 1];
        if (last) this.series.update(shown(last));
        if (!this.quoteLive) this.setQuote({});
        if (added || !this.ictTime || Date.now() - this.ictTime > 1000) this.computeICT();
      });
      // MT5's own bid/ask for the order buttons; the first one also sets the Binance bars onto the broker's price.
      const quote = async () => {
        try {
          const path = this.owner ? `/mt5/candles?symbol=${encodeURIComponent(this.symbol)}&interval=1m&count=1` : "/member/candles?interval=1m&count=1";
          const data = await this.call(path);
          if (token !== this.loadToken || data.bid == null) return;
          this.quoteLive = true;
          const last = this.bars[this.bars.length - 1];
          if (!feed.aligned && last && data.ask != null) {
            feed.aligned = true;
            const step = Math.pow(10, -market.digits);
            const d = Math.round(((data.bid + data.ask) / 2 - last.close) / step) * step;
            // Only the same market (gold on gold): a big gap means another instrument, left as it is.
            if (Math.abs(d) < last.close * 0.01) {
              feed.shift(d);
              this.series.setData(this.viewBars().map(shown));
              this.computeICT();
              label();
            }
          }
          this.setQuote(data);
        } catch { /* Binance alone */ }
      };
      if (this.base) { quote(); this.pollTimer = setInterval(quote, 2000); }
      this.syncLines();
      this.updateFlow();
      this.redraw();
      this.applyBtMarkers();
      if (this.layout !== "1") this.setLayout(this.layout); else if (this.smtWanted()) this.loadCmp();
    },

    async loadOlder(quiet) {
      if (this.secFeed && !this.replay && !quiet) {
        if (this.loadingOlder) return;
        this.loadingOlder = true;
        const token = this.loadToken, feed = this.secFeed;
        try {
          const added = await feed.older();
          if (!added || token !== this.loadToken) return;
          const range = this.chart.timeScale().getVisibleLogicalRange();
          this.series.setData(this.bars.map(shown));
          if (range) this.chart.timeScale().setVisibleLogicalRange({ from: range.from + added, to: range.to + added });
          this.computeICT();
        } finally { this.loadingOlder = false; }
        return;
      }
      if (this.loadingOlder || this.noOlder || this.source !== "exness" || !this.bars.length) return;
      this.loadingOlder = true;
      const token = this.loadToken;
      try {
        const data = await this.call(this.exnessPath(800, this.bars[0].time));
        if (token !== this.loadToken) return;
        const older = this.toBars(data.candles || []).filter((b) => b.time < this.bars[0].time);
        if (!older.length) { this.noOlder = true; return; }
        const range = this.chart.timeScale().getVisibleLogicalRange();
        this.bars = older.concat(this.bars);
        if (this.replay) this.replay.idx += older.length;
        if (quiet) return;
        this.series.setData(this.viewBars().map(shown));
        if (range) this.chart.timeScale().setVisibleLogicalRange({ from: range.from + older.length, to: range.to + older.length });
        this.computeICT();
        if (this.btView) this.applyBtMarkers();
        if (this.layout !== "1" && this.cmpBars && this.cmpBars.length && this.cmpBars[0].time > this.bars[0].time) this.loadOlderCmp();
      } catch { this.noOlder = true; } finally { this.loadingOlder = false; }
    },

    /** MT5 gave no bars for a symbol Binance does not have either: say so, and try again shortly. */
    showNoBars(token, why) {
      this.source = "none";
      this.bars = [];
      if (this.replay) { clearInterval(this.replay.timer); this.replay = null; this.renderReplayBar(); }
      this.series.setData([]);
      this.computeICT();
      $("chartSymbol").textContent = this.symbol || "—";
      $("chartSource").textContent = `· chưa tải được nến${why ? ": " + why : ""} — tự thử lại…`;
      this.setQuote({});
      setTimeout(() => { if (token === this.loadToken) this.loadCandles(); }, 5000);
    },

    async loadBinance(market) {
      const m = market || binanceMarket("XAUUSD");
      this.source = "binance";
      this.digits = m.digits != null ? m.digits : 2;
      this.applySeriesFormat();
      $("chartSymbol").textContent = this.owner && this.symbol ? this.symbol : "XAUUSD";
      $("chartSource").textContent = "· MT5 chưa trả nến, đang dùng giá tạm";
      const interval = this.interval;
      const rest = m.futures ? "https://fapi.binance.com/fapi/v1/klines" : "https://api.binance.com/api/v3/klines";
      try {
        const res = await fetch(`${rest}?symbol=${m.name}&interval=${interval}&limit=800`);
        const rows = await res.json();
        this.bars = rows.map((r) => ({ time: r[0] / 1000, open: +r[1], high: +r[2], low: +r[3], close: +r[4], volume: +r[5] }));
        if (this.replay) this.exitReplay();
        if (this.drawKey !== this.symbolKey()) { this.drawKey = this.symbolKey(); this.drawings.load(); }
        this.showFresh(this.bars);
        this.setQuote({});
        this.computeICT();
      } catch { /* chart stays empty */ }
      const ws = new WebSocket(`${m.futures ? "wss://fstream.binance.com/ws/" : "wss://stream.binance.com:9443/ws/"}${m.name.toLowerCase()}@kline_${interval}`);
      ws.onmessage = (ev) => {
        const k = JSON.parse(ev.data).k;
        if (!k) return;
        const b = { time: k.t / 1000, open: +k.o, high: +k.h, low: +k.l, close: +k.c, volume: +k.v };
        const last = this.bars[this.bars.length - 1];
        if (last && b.time === last.time) this.bars[this.bars.length - 1] = b; else if (!last || b.time > last.time) { this.bars.push(b); if (!this.replay) this.computeICT(); }
        if (this.replay) return;
        this.series.update(shown(b));
        this.setQuote({});
      };
      this.socket = ws;
    },

    /* ----- price lines: positions, orders, the pending draft, signals ----- */

    findSelected() {
      if (!this.selected) return null;
      const list = this.selected.kind === "pos" ? this.positions : this.orders;
      return list.find((x) => x.ticket === this.selected.ticket) || null;
    },

    /** The lines the chart should show now, keyed so they are updated in place. */
    wantedLines() {
      const out = [];
      if (this.replay) {
        const price = this.bars[this.replay.idx].close;
        this.replay.trades.forEach((t) => {
          out.push({ key: `rp:${t.id}:entry`, price: t.entry, color: t.side === "long" ? "#2b6bf3" : "#f0455a", width: 1, style: 0, title: `Replay ${sideName(t.side)} ${t.lots} ${signed(this.replayProfit(t, price))}` });
          if (t.stop) out.push({ key: `rp:${t.id}:stop`, price: t.stop, color: "#f0455a", width: 1, style: 2, title: "SL" });
          if (t.target) out.push({ key: `rp:${t.id}:target`, price: t.target, color: "#14b88a", width: 1, style: 2, title: "TP" });
        });
        return out;
      }
      if (this.owner) {
        const sel = this.selected;
        const onChart = (x) => x.symbol === this.symbol;
        const dim = (color, active) => (sel && !active ? rgba(color, 0.35) : color);
        this.positions.filter(onChart).forEach((p) => {
          const active = sel && sel.kind === "pos" && sel.ticket === p.ticket;
          const w = active ? 2 : 1;
          // Entry: a dotted line from the entry candle (with a dot on it) and a label with the money in
          // green or red, painted by the chart layer; the price line only keeps the price on the axis.
          out.push({ key: `pos:${p.ticket}:entry`, price: p.entry, color: dim(p.side === "long" ? "#2b6bf3" : "#f0455a", active), width: w, style: 0, title: "", entryOf: p, faded: !!(sel && !active) });
          if (p.stop) out.push({ key: `pos:${p.ticket}:stop`, price: p.stop, color: dim("#f0455a", active), width: w, style: 2, title: `SL ${money0(this.pnlAt(p, p.stop))}` });
          if (p.target) out.push({ key: `pos:${p.ticket}:target`, price: p.target, color: dim("#14b88a", active), width: w, style: 2, title: `TP ${money0(this.pnlAt(p, p.target))}` });
        });
        this.orders.filter(onChart).forEach((o) => {
          const active = sel && sel.kind === "ord" && sel.ticket === o.ticket;
          const w = active ? 2 : 1;
          out.push({ key: `ord:${o.ticket}:entry`, price: o.entry, color: dim(o.side === "long" ? "#2b6bf3" : "#f0455a", active), width: w, style: 1, title: `${sideName(o.side)} ${o.kind.toUpperCase()} ${o.lots}` });
          const om = (lv) => money0(this.valueAt(o.symbol, o.lots, o.side, o.entry, lv));
          if (o.stop) out.push({ key: `ord:${o.ticket}:stop`, price: o.stop, color: dim("#f0455a", active), width: w, style: 2, title: `SL ${om(o.stop)}` });
          if (o.target) out.push({ key: `ord:${o.ticket}:target`, price: o.target, color: dim("#14b88a", active), width: w, style: 2, title: `TP ${om(o.target)}` });
        });
        if (this.draft) {
          const price = num($("pPrice").value), stop = num($("pStop").value), target = num($("pTarget").value);
          if (price) out.push({ key: "draft:entry", price, color: "#9b6bff", width: 2, style: 0, title: `${this.pendingKind(this.draftSide(price))} ${this.lots().toFixed(2)}` });
          const dside = price ? this.draftSide(price) : "long";
          const dm = (lv) => money0(this.valueAt(this.symbol, this.lots(), dside, price, lv));
          if (stop) out.push({ key: "draft:stop", price: stop, color: "#f0455a", width: 1, style: 2, title: `SL ${dm(stop)}` });
          if (target) out.push({ key: "draft:target", price: target, color: "#14b88a", width: 1, style: 2, title: `TP ${dm(target)}` });
        }
      } else {
        this.signals.filter((s) => s.status === "open" && s.symbol === ($("chartSymbol").textContent || s.symbol)).forEach((s) => {
          out.push({ key: `sig:${s.id}:entry`, price: s.entry, color: "#9b6bff", width: 1, style: 2, title: (s.side === "long" ? "MUA" : "BÁN") + " tín hiệu" });
          if (s.stop) out.push({ key: `sig:${s.id}:stop`, price: s.stop, color: "#9b6bff", width: 1, style: 1, title: "SL" });
          if (s.target) out.push({ key: `sig:${s.id}:target`, price: s.target, color: "#9b6bff", width: 1, style: 1, title: "TP" });
        });
      }
      return out;
    },

    /** Money at a price for a position: from its live profit (the broker's own contract size), else lots × contract. */
    pnlAt(p, price) {
      if (price == null) return null;
      const dir = p.side === "long" ? 1 : -1;
      const move = (p.price - p.entry) * dir;
      if (Math.abs(move) > Math.abs(p.entry) * 0.00005 && p.profit) return p.profit / move * (price - p.entry) * dir;
      return this.valueAt(p.symbol, p.lots, p.side, p.entry, price);
    },

    /** Money for `lots` from `entry` to `price` with the usual contract sizes (gold 100, silver 5000, crypto/indices 1, FX 100000). */
    valueAt(symbol, lots, side, entry, price) {
      if (price == null || entry == null) return null;
      const s = String(symbol || "").toUpperCase();
      const contract = /XAU|GOLD/.test(s) ? 100 : /XAG|SILVER/.test(s) ? 5000 : /BTC|ETH|SOL|XRP|LTC|US30|USTEC|NAS|SPX|US500|DE30|DE40|JP225|UK100|HK50/.test(s) ? 1 : 100000;
      return (price - entry) * (side === "long" ? 1 : -1) * lots * contract;
    },

    /** Each open position: a dotted line at its entry from the candle it opened on (a dot there),
     * and "BUY 0.1 | −5.75" at the right, the money green when in profit and red at a loss. */
    drawPositions(g, width) {
      const list = (this.lineCache || []).filter((w) => w.entryOf);
      if (!list.length) return;
      const ts = this.chart.timeScale(), bars = this.viewBars();
      const light = document.documentElement.dataset.theme === "light";
      g.save();
      g.font = "600 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
      g.textBaseline = "middle";
      list.forEach((w) => {
        const p = w.entryOf;
        const yy = this.series.priceToCoordinate(w.price);
        if (yy == null) return;
        const y = Math.round(yy) + 0.5;
        let x0 = 0, dot = false;
        if (bars.length && p.time != null && p.time >= bars[0].time) {
          let i = bars.length - 1;
          while (i > 0 && bars[i].time > p.time) i--;
          const x = ts.logicalToCoordinate(i);
          if (x != null) { x0 = Math.max(0, x); dot = x >= 0 && x <= width; }
        }
        g.globalAlpha = w.faded ? 0.45 : 1;
        g.strokeStyle = w.color; g.lineWidth = Math.max(1, w.width);
        g.setLineDash([2, 3]);
        g.beginPath(); g.moveTo(x0, y); g.lineTo(width, y); g.stroke();
        g.setLineDash([]);
        if (dot) {
          g.beginPath(); g.arc(x0, y, 4, 0, Math.PI * 2);
          g.fillStyle = w.color; g.fill();
          g.lineWidth = 1.5; g.strokeStyle = light ? "#ffffff" : "#151c2a"; g.stroke();
        }
        // Label: side and lots on the side colour, the money on green / red.
        const left = `${sideName(p.side)} ${p.lots}`, right = signed(p.profit);
        const lw = g.measureText(left).width + 12, rw = g.measureText(right).width + 12, h = 18;
        const x = Math.max(4, width - lw - rw - 10), top = y - h / 2;
        g.fillStyle = p.side === "long" ? "#2b6bf3" : "#f0455a";
        g.beginPath(); g.roundRect(x, top, lw + rw, h, 4); g.fill();
        g.fillStyle = (p.profit || 0) >= 0 ? "#14b88a" : "#f0455a";
        g.beginPath(); g.roundRect(x + lw, top, rw, h, [0, 4, 4, 0]); g.fill();
        g.fillStyle = "#ffffff";
        g.fillText(left, x + 6, y + 0.5);
        g.fillText(right, x + lw + 6, y + 0.5);
        g.globalAlpha = 1;
      });
      g.restore();
    },

    syncLines() {
      if (!this.series) return;
      const wanted = this.wantedLines();
      const keys = new Set();
      wanted.forEach((w) => {
        keys.add(w.key);
        if (this.drag && this.drag.key === w.key) return; // the finger owns it
        const opts = { price: w.price, color: w.color, lineWidth: w.width, lineStyle: w.style, axisLabelVisible: true, title: w.title, lineVisible: !w.entryOf };
        const line = this.lines.get(w.key);
        if (line) line.applyOptions(opts); else this.lines.set(w.key, this.series.createPriceLine(opts));
      });
      for (const [k, line] of this.lines) {
        if (!keys.has(k) && !(this.drag && this.drag.key === k)) { this.series.removePriceLine(line); this.lines.delete(k); }
      }
      this.lineCache = wanted;
      if (this.requestICT) this.requestICT();
      // While a trade or drawing is picked (or a pending price is set), a finger drags it, not the page.
      this.updateTouchAction();
    },

    renderSelBar() {
      const bar = $("selBar");
      const x = this.findSelected();
      if (!this.owner || !x || this.replay) { bar.hidden = true; return; }
      const pos = this.selected.kind === "pos";
      bar.hidden = false;
      bar.innerHTML = `<span>${sideName(x.side)}${pos ? "" : " " + x.kind.toUpperCase()} ${x.lots} · #${x.ticket}${pos ? ` · <b class="${x.profit >= 0 ? "pos" : "neg"}">${signed(x.profit)}</b>` : ""}</span>
        ${!x.stop ? '<button type="button" data-a="stop">+SL</button>' : ""}${!x.target ? '<button type="button" data-a="target">+TP</button>' : ""}
        <button type="button" data-a="edit">Sửa</button>
        <button type="button" data-a="close" class="danger">${pos ? "Đóng" : "Huỷ"}</button>
        <button type="button" data-a="x" class="muted">✕</button>`;
      bar.querySelectorAll("button").forEach((b) => (b.onclick = (e) => this.selAction(b.dataset.a, x, e.currentTarget)));
    },

    async selAction(a, x, button) {
      const pos = this.selected.kind === "pos";
      if (a === "x") { this.selected = null; this.renderSelBar(); this.syncLines(); return; }
      if (a === "edit") return pos ? this.positionSheet(x) : this.orderSheet(x);
      if (a === "close") {
        await act(button, () => this.call(pos ? "/mt5/close" : "/mt5/cancel", { ticket: x.ticket }), pos ? "Đã đóng lệnh" : "Đã huỷ lệnh chờ");
        this.selected = null; this.refresh(); return;
      }
      // A new SL/TP a few average bars away, then dragged where it belongs.
      const tail = this.bars.slice(-30);
      const range = tail.length ? tail.reduce((s, b) => s + b.high - b.low, 0) / tail.length : x.entry * 0.001;
      const dist = Math.max(range * 4, x.entry * 0.0005);
      const long = x.side === "long";
      // From the price the trade would close at now (a losing buy is below its entry), so MT5 accepts it.
      const now = pos ? x.price : x.entry;
      const ref = a === "stop" ? (long ? Math.min(now, x.entry) : Math.max(now, x.entry)) : (long ? Math.max(now, x.entry) : Math.min(now, x.entry));
      const dir = (long ? 1 : -1) * (a === "target" ? 1 : -1);
      const level = +(ref + dir * dist).toFixed(this.digitsFor(x.symbol));
      const body = { ticket: x.ticket, stop: a === "stop" ? level : x.stop, target: a === "target" ? level : x.target };
      if (!pos) body.price = x.entry;
      await act(button, () => this.call("/mt5/modify", body), `Đã thêm ${a === "stop" ? "SL" : "TP"} — kéo để chỉnh`);
      this.refresh();
    },

    /* ----- touch & drag on the chart ----- */

    bindDrag() {
      const wrap = $("chartWrap");
      const rel = (e) => { const r = wrap.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
      const paneWidth = () => this.chart.timeScale().width();
      const hit = (y, keys) => {
        let best = null;
        for (const w of this.lineCache || []) {
          if (!keys(w.key)) continue;
          const ly = this.series.priceToCoordinate(w.price);
          if (ly == null) continue;
          const dist = Math.abs(ly - y);
          if (dist < (best ? best.dist : 12)) best = { w, dist };
        }
        return best && best.w;
      };
      const draggable = (key) => {
        if (!this.owner || this.replay) return false;
        if (key.startsWith("draft:")) return true;
        const s = this.selected;
        if (!s) return false;
        const [kind, ticket, field] = key.split(":");
        if (kind !== s.kind || +ticket !== s.ticket) return false;
        // A position's entry line is not moved: pulling it down/up sets its SL or TP (by side).
        return field !== "entry" || kind === "ord" || kind === "pos";
      };
      // While dragging, the price scale holds still so the line stays under the finger.
      const lock = (on) => {
        this.chart.applyOptions({ handleScroll: !on, handleScale: !on });
        const ps = this.chart.priceScale("right");
        if (on) { this.scaleWasAuto = ps.options().autoScale; ps.applyOptions({ autoScale: false }); } else if (this.scaleWasAuto) ps.applyOptions({ autoScale: true });
      };
      let down = null, longPress = null;
      wrap.addEventListener("pointerdown", (e) => {
        this.closeMenu();
        this.focusChart(1);
        if (e.button > 0 || e.target.closest("#selBar, #posPill, #ticket, #drawBar, #favBar, #draftBar, #btChip")) return;
        const { x, y } = rel(e);
        down = { x: e.clientX, y: e.clientY, moved: false, menu: false };
        if (x > paneWidth()) return;
        // A long press opens the chart menu on phones (no right click there).
        if (e.pointerType !== "mouse") {
          clearTimeout(longPress);
          longPress = setTimeout(() => {
            if (down && !down.moved && !this.drag && !this.drawGesture) { down.menu = true; this.openMenu(e.clientX, e.clientY); }
          }, 550);
        }
        if (this.replayPicking) return;
        const r = this.drawings ? this.drawings.down(x, y, e) : false;
        if (r === true) {
          this.drawGesture = true; lock(true); e.stopPropagation();
          clearTimeout(longPress);
          return;
        }
        const w = hit(y, draggable);
        if (!w) return;
        this.drag = { key: w.key, price: w.price, start: w.price, base: w.key, pull: /^pos:\d+:entry$/.test(w.key) };
        lock(true);
        e.stopPropagation();
      }, true);
      ["mousedown", "touchstart"].forEach((t) => wrap.addEventListener(t, (e) => { if (this.drag || this.drawGesture) e.stopPropagation(); }, { capture: true, passive: true }));
      wrap.addEventListener("touchmove", (e) => { if (this.drag || this.drawGesture) e.preventDefault(); }, { passive: false });
      wrap.addEventListener("pointermove", (e) => {
        if (this.drag || this.drawGesture) return;
        const { x, y } = rel(e);
        if (this.drawings && this.drawings.pending) { this.drawings.move(x, y); return; }
        if (e.pointerType !== "mouse") return;
        const overDrawing = this.drawings && x <= paneWidth() && this.drawings.hitTest(x, y, 8);
        if (this.drawings) this.drawings.hover(overDrawing ? overDrawing.d.id : null);
        wrap.style.cursor = this.drawings && this.drawings.tool ? "crosshair"
          : overDrawing ? "move" : x <= paneWidth() && hit(y, draggable) ? "ns-resize" : "";
      });
      wrap.addEventListener("pointerleave", () => { if (this.drawings) this.drawings.hover(null); });
      window.addEventListener("pointermove", (e) => {
        if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 6) { down.moved = true; clearTimeout(longPress); }
        if (this.drawGesture) { const { x, y } = rel(e); this.drawings.move(x, y); return; }
        if (!this.drag) return;
        const price = this.series.coordinateToPrice(rel(e).y);
        if (price == null) return;
        let p = +price.toFixed(this.digits);
        if (this.drag.pull) { this.pullTo(p); return; }
        if (this.drag.key.startsWith("draft:")) p = this.writeDraft(this.drag.key, p);
        this.drag.price = p;
        const line = this.lines.get(this.drag.key);
        if (line) line.applyOptions({ price: p, title: this.dragTitle(this.drag) });
      });
      window.addEventListener("pointerup", (e) => {
        clearTimeout(longPress);
        const d = this.drag, tap = down && !down.moved && !down.menu;
        down = null;
        if (this.drawGesture) {
          this.drawGesture = false; lock(false);
          this.drawings.up();
          return;
        }
        if (d) {
          this.drag = null; lock(false);
          const untouched = d.key === d.base ? Math.abs(d.price - d.start) === 0 : d.start != null && Math.abs(d.price - d.start) === 0;
          if (d.pull && d.key === d.base) {
            // Only a tap on the entry line: pick the next trade at that price.
            this.syncLines();
            if (tap && e.target && wrap.contains(e.target)) { const { x, y } = rel(e); this.tapChart(y, x); }
            return;
          }
          if (untouched) this.syncLines(); else this.commitDrag(d);
          return;
        }
        if (tap && e.target && wrap.contains(e.target)) { const { x, y } = rel(e); this.tapChart(y, x); }
      });
      window.addEventListener("pointercancel", () => {
        clearTimeout(longPress);
        if (this.drag) { this.drag = null; lock(false); this.syncLines(); }
        if (this.drawGesture) { this.drawGesture = false; lock(false); this.drawings.up(); }
        down = null;
      });
      wrap.addEventListener("dblclick", () => { if (this.drawings && this.drawings.current) this.drawingSettings(this.drawings.current); });
      wrap.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        if (this.drawings && this.drawings.pending) { this.drawings.cancel(); return; }
        this.openMenu(e.clientX, e.clientY);
      });
      window.addEventListener("keydown", (e) => {
        if (this.tab !== "chart" || /INPUT|TEXTAREA|SELECT/.test((document.activeElement || {}).tagName || "") || $("sheet").open) return;
        if (e.key === "Escape") { this.closeMenu(); if (this.drawings) this.drawings.cancel(); if (this.replayPicking) this.exitReplay(); }
        if ((e.key === "Delete" || e.key === "Backspace") && this.drawings && this.drawings.selected) { this.drawings.remove(this.drawings.selected); e.preventDefault(); }
        if (this.replay && e.key === "ArrowRight") { this.replayStep(); e.preventDefault(); }
        if (this.replay && e.key === " ") { this.replayPlay(); e.preventDefault(); }
      });
      document.addEventListener("pointerdown", (e) => {
        if (!e.target.closest("#ctxMenu") && !e.target.closest(".lot-pick") && !e.target.closest(".db-pick")) this.closeMenu();
        if (!e.target.closest("#flyout, #toolRail")) this.closeFlyout();
      });
    },

    dragTitle(d) {
      const [kind, ticket, field] = d.key.split(":");
      const name = { entry: kind === "draft" ? "Giá chờ" : "Giá", stop: "SL", target: "TP" }[field];
      if (kind === "pos") {
        const p = this.positions.find((x) => x.ticket === +ticket);
        const v = p ? this.pnlAt(p, d.price) : null;
        return `${name} ${fmt(d.price, this.digits)}${v != null ? " · " + signed(v) : ""}`;
      }
      return `${name} ${fmt(d.price, this.digits)}`;
    },

    /** Moves a draft line; SL/TP stay on the order's side. Returns the price used. */
    writeDraft(key, price) {
      const entry = num($("pPrice").value);
      const tick = Math.pow(10, -this.digits);
      if (key === "draft:entry") {
        $("pPrice").value = fmt(price, this.digits);
        this.placeDraftStops();
      } else if (entry != null) {
        const long = this.draftSide(entry) === "long";
        const below = (key === "draft:stop") === long;
        price = below ? Math.min(price, entry - tick) : Math.max(price, entry + tick);
        $(key === "draft:stop" ? "pStop" : "pTarget").value = fmt(price, this.digits);
        this.readDraftDist();
      }
      this.updatePendingLabels();
      this.syncLines();
      return price;
    },

    /** Pulling a position's entry line: below it (a buy) sets the SL, above it the TP; a sell the other way. */
    pullTo(price) {
      const d = this.drag;
      const ticket = +d.base.split(":")[1];
      const p = this.positions.find((x) => x.ticket === ticket);
      if (!p) return;
      const long = p.side === "long";
      const field = (long ? price < p.entry : price > p.entry) ? "stop" : "target";
      const key = `pos:${ticket}:${field}`;
      if (d.key !== key) { d.key = key; d.start = p[field] || null; this.syncLines(); }
      d.price = price;
      const opts = { price, color: field === "stop" ? "#f0455a" : "#14b88a", lineWidth: 2, lineStyle: 2, axisLabelVisible: true, title: this.dragTitle(d) };
      const line = this.lines.get(key);
      if (line) line.applyOptions(opts); else this.lines.set(key, this.series.createPriceLine(opts));
    },

    async commitDrag(d) {
      const [kind, ticket, field] = d.key.split(":");
      if (kind === "draft") { this.syncLines(); return; }
      const list = kind === "pos" ? this.positions : this.orders;
      const x = list.find((y) => y.ticket === +ticket);
      if (!x) return this.syncLines();
      const body = { ticket: x.ticket, stop: x.stop, target: x.target };
      if (kind === "ord") body.price = x.entry;
      body[field === "entry" ? "price" : field] = d.price;
      const wrong = kind === "pos" ? this.stopsProblem(x, body.stop, body.target) : null;
      if (wrong) { toast(wrong, true); this.syncLines(); return; }
      // Show the new level at once; the next refresh confirms it.
      if (field === "entry") x.entry = d.price; else x[field] = d.price;
      this.syncLines();
      await act(null, () => this.call("/mt5/modify", body), `Đã dời ${field === "stop" ? "SL" : field === "target" ? "TP" : "giá"} → ${fmt(d.price, this.digits)}`);
      this.refresh();
    },

    /** Why MT5 would refuse these SL/TP for an open position (null when fine). */
    stopsProblem(p, stop, target) {
      const long = p.side === "long", now = p.price, d = this.digitsFor(p.symbol);
      if (now == null) return null;
      if (stop && (long ? stop >= now : stop <= now)) return `SL của lệnh ${long ? "MUA phải thấp" : "BÁN phải cao"} hơn giá hiện tại ${fmt(now, d)}`;
      if (target && (long ? target <= now : target >= now)) return `TP của lệnh ${long ? "MUA phải cao" : "BÁN phải thấp"} hơn giá hiện tại ${fmt(now, d)}`;
      return null;
    },

    /** Logical bar index under a pixel column. */
    indexAt(x) {
      const l = this.chart.timeScale().coordinateToLogical(x);
      return l == null ? null : Math.max(0, Math.min(this.viewBars().length - 1, Math.round(l)));
    },

    /** A tap picks a trade by its entry line (the next one when several share a price). */
    tapChart(y, x) {
      if (x > this.chart.timeScale().width()) return;
      if (this.replayPicking) {
        const i = this.indexAt(x);
        if (i != null) this.startReplayAt(i);
        return;
      }
      if (!this.owner || this.replay) return;
      const near = (this.lineCache || []).filter((w) => /^(pos|ord):\d+:entry$/.test(w.key)).filter((w) => {
        const ly = this.series.priceToCoordinate(w.price);
        return ly != null && Math.abs(ly - y) < 12;
      });
      if (near.length) {
        const ids = near.map((w) => { const [k, t] = w.key.split(":"); return { kind: k, ticket: +t }; });
        const cur = this.selected ? ids.findIndex((s) => s.kind === this.selected.kind && s.ticket === this.selected.ticket) : -1;
        this.selected = ids[(cur + 1) % ids.length];
      } else if (this.selected) {
        this.selected = null;
      } else if (!$("pendingBox").hidden) {
        this.togglePending(false);
      }
      this.renderSelBar();
      this.syncLines();
    },

    updateTouchAction() {
      const d = this.drawings;
      const busy = (this.owner && (this.selected || this.draft)) || (d && (d.tool || d.pending || d.selected)) || this.replayPicking;
      $("chartWrap").style.touchAction = busy ? "none" : "";
    },

    resetChart() {
      const ts = this.chart.timeScale();
      ts.applyOptions({ barSpacing: $("chart").clientWidth < 500 ? 4 : 6, rightOffset: 8 });
      ts.resetTimeScale();
      this.chart.priceScale("right").applyOptions({ autoScale: true });
      ts.scrollToRealTime();
    },

    /* ----- chart menu (right click / long press) ----- */

    openMenu(cx, cy) {
      const wrap = $("chartWrap"), r = wrap.getBoundingClientRect();
      const x = cx - r.left, y = cy - r.top;
      const inPane = x <= this.chart.timeScale().width();
      const price = inPane ? this.series.coordinateToPrice(y) : null;
      const idx = inPane ? this.indexAt(x) : null;
      const p = price != null ? +price.toFixed(this.digits) : null;
      const items = [["reset", "⟲ Đặt lại biểu đồ"]];
      if (idx != null && !this.replay) items.push(["replay", "⏮ Replay từ nến này"]);
      if (this.replay) items.push(["exitReplay", "✕ Thoát replay"]);
      if (p != null) items.push(["hline", `— Vẽ đường ngang tại ${fmt(p, this.digits)}`]);
      if (p != null && this.owner && !this.replay) items.push(["pending", `⏳ Lệnh chờ tại ${fmt(p, this.digits)}`]);
      items.push(["tools", "✎ Công cụ vẽ…"]);
      if (this.drawings && this.drawings.list.length) items.push(["clear", `🗑 Xoá tất cả bản vẽ (${this.drawings.list.length})`]);
      if (this.drawings && this.drawings.current) items.push(["drawSettings", "⚙ Cài đặt bản vẽ…"]);
      items.push(["ind", "ƒx Chỉ báo…"], ["ictSettings", "⚙ Cài đặt chỉ báo ICT…"], ["chartStyle", "🎨 Cài đặt biểu đồ (màu, sáng/tối)…"]);
      const menu = $("ctxMenu");
      menu.innerHTML = items.map(([k, t]) => `<button type="button" data-k="${k}">${esc(t)}</button>`).join("");
      menu.hidden = false;
      const mw = menu.offsetWidth, mh = menu.offsetHeight;
      menu.style.left = Math.max(8, Math.min(cx, window.innerWidth - mw - 8)) + "px";
      menu.style.top = Math.max(8, Math.min(cy, window.innerHeight - mh - 8)) + "px";
      menu.querySelectorAll("button").forEach((b) => (b.onclick = () => {
        this.closeMenu();
        const k = b.dataset.k;
        if (k === "reset") this.resetChart();
        if (k === "replay") this.startReplayAt(idx);
        if (k === "exitReplay") this.exitReplay();
        if (k === "hline") { const dr = this.drawings; dr.setTool("horizontalLine"); dr.pending = null; const d = dr.newDrawing("horizontalLine"); d.pts = [{ t: this.viewBars()[idx || 0].time, p }]; dr.pending = d; dr.finish(); }
        if (k === "pending") { this.togglePending(true); $("pPrice").value = fmt(p, this.digits); this.updatePendingLabels(); this.syncLines(); }
        if (k === "tools") this.drawSheet();
        if (k === "clear" && confirm("Xoá tất cả bản vẽ trên mã này?")) this.drawings.clear();
        if (k === "ind") this.indicatorSheet();
        if (k === "ictSettings") this.ictSettingsSheet();
        if (k === "drawSettings") this.drawingSettings(this.drawings.current);
        if (k === "chartStyle") this.chartStyleSheet();
      }));
    },

    closeMenu() { const m = $("ctxMenu"); if (m && !m.hidden) { m.hidden = true; m.classList.remove("db-menu"); } },

    /* ----- drawing tools ----- */

    symbolKey() { return this.owner ? this.symbol : ($("chartSymbol").textContent || "XAUUSD"); },

    drawSheet() {
      const D = window.AurumDrawings;
      sheet.open(`<h3>Công cụ vẽ</h3>
        ${D.categories.map(([title, tools]) => `<h4>${title}</h4><div class="tool-grid">${tools.map((t) => `<button type="button" data-t="${t}"><span class="ti">${D.tools[t].icon}</span>${esc(D.tools[t].name)}</button>`).join("")}</div>`).join("")}
        <label class="toggle"><span>Nam châm (bắt vào giá mở/cao/thấp/đóng của nến)</span><span class="switch"><input type="checkbox" id="magnetOn" ${this.magnet ? "checked" : ""}><span></span></span></label>
        ${this.drawings.list.length ? `<button class="btn btn-ghost wide danger" id="clearDraw">Xoá tất cả bản vẽ (${this.drawings.list.length})</button>` : ""}
        <p class="muted small">Chọn công cụ rồi chạm/kéo trên biểu đồ. Chạm vào bản vẽ để chọn, kéo để di chuyển, kéo chấm tròn để chỉnh; phím Delete để xoá. Bản vẽ lưu theo từng mã trên máy này.</p>`, (el) => {
        el.querySelectorAll("[data-t]").forEach((b) => (b.onclick = () => { sheet.close(); this.drawings.setTool(b.dataset.t); }));
        el.querySelector("#magnetOn").onchange = (e) => { this.magnet = e.target.checked; store.set("aurum.magnet", this.magnet ? "1" : "0"); };
        const c = el.querySelector("#clearDraw");
        if (c) c.onclick = () => { if (confirm("Xoá tất cả bản vẽ trên mã này?")) { this.drawings.clear(); sheet.close(); } };
      });
    },

    hint(tool) {
      const n = window.AurumDrawings.tools[tool].n;
      if (tool === "brush") return "kéo để vẽ";
      if (tool === "path") return "chạm từng điểm, chạm lại điểm cuối để xong";
      if (n === 1) return "chạm vào chỗ cần đặt";
      if (n === 2) return "kéo từ điểm đầu tới điểm cuối (hoặc chạm 2 điểm)";
      return `chạm ${n} điểm`;
    },

    renderDrawBar() {
      const bar = $("drawBar"), d = this.drawings;
      this.updateTouchAction();
      if (!d) return;
      this.renderToolRail();
      const D = window.AurumDrawings;
      if (d.tool) {
        bar.hidden = false;
        bar.innerHTML = `<span class="db-grip" title="Kéo để di chuyển · bấm đúp để về giữa">⋮⋮</span><span><b>${esc(D.tools[d.tool].name)}</b> · ${this.hint(d.tool)}</span><button type="button" data-a="cancel">Huỷ</button>`;
      } else if (d.current) {
        const cur = d.current;
        const pos = cur.tool === "longPosition" || cur.tool === "shortPosition";
        bar.hidden = false;
        // Tool · colour ▾ · width ▾ · style ▾ | templates · settings · lock | delete · close
        bar.innerHTML = `<span class="db-grip" title="Kéo để di chuyển · bấm đúp để về giữa">⋮⋮</span><span class="db-tool" title="${esc(D.tools[cur.tool].name)}">${TOOL_ICON[cur.tool] || ""}</span><span class="db-sep"></span>
          <button type="button" data-p="color" class="db-pick" title="Màu"><span class="db-dot" style="background:${esc(cur.color)}"></span>${BAR_ICON.chev}</button>
          <button type="button" data-p="width" class="db-pick" title="Độ dày">${linePreview(cur.width, "solid")}<span class="db-px">${cur.width}</span>${BAR_ICON.chev}</button>
          <button type="button" data-p="style" class="db-pick" title="Kiểu nét">${linePreview(1.5, cur.style)}${BAR_ICON.chev}</button>
          ${pos ? `<span class="db-sep"></span><span class="rr">R:R <b>${cur.rr}</b></span>` : ""}
          <span class="db-sep"></span>
          <button type="button" data-a="tpl" title="Bản mẫu vẽ">${BAR_ICON.tpl}</button>
          <button type="button" data-a="settings" title="Cài đặt">${BAR_ICON.settings}</button>
          <button type="button" data-a="lock" class="${cur.locked ? "on" : ""}" title="${cur.locked ? "Mở khoá" : "Khoá"}">${cur.locked ? BAR_ICON.lock : BAR_ICON.unlock}</button>
          <span class="db-sep"></span>
          <button type="button" data-a="del" class="danger" title="Xoá">${BAR_ICON.del}</button>
          <button type="button" data-a="x" class="muted" title="Bỏ chọn">${BAR_ICON.close}</button>`;
      } else { bar.hidden = true; return; }
      bar.querySelectorAll("[data-p]").forEach((b) => (b.onclick = () => this.drawPickMenu(b, b.dataset.p)));
      this.placeDrawBar();
      bar.querySelectorAll("[data-a]").forEach((b) => {
        const a = b.dataset.a;
        b.onclick = () => {
          if (a === "cancel") d.cancel();
          if (a === "del") d.remove(d.selected);
          if (a === "x") { d.selected = null; d.update(); }
          if (a === "lock") d.restyle({ locked: !d.current.locked });
          if (a === "settings") this.drawingSettings(d.current);
          if (a === "tpl") { this.templateMenu(b, d, d.current); return; }
          this.renderDrawBar();
        };
      });
    },

    /** The drawing bar where it was dragged to (kept), or centred at the top of the chart. */
    placeDrawBar() {
      const bar = $("drawBar"), wrap = bar.parentElement;
      let pos = null;
      try { pos = JSON.parse(store.get("aurum.drawBarPos") || "null"); } catch { pos = null; }
      if (!pos || !wrap || wrap.id !== "chartWrap") { bar.classList.remove("moved"); bar.style.left = bar.style.top = ""; }
      else {
        bar.classList.add("moved");
        bar.style.left = Math.max(0, Math.min(wrap.clientWidth - bar.offsetWidth, pos.x)) + "px";
        bar.style.top = Math.max(0, Math.min(wrap.clientHeight - bar.offsetHeight, pos.y)) + "px";
      }
      const grip = bar.querySelector(".db-grip");
      if (!grip) return;
      grip.onpointerdown = (e) => {
        e.preventDefault(); e.stopPropagation();
        const w = bar.parentElement.getBoundingClientRect(), r = bar.getBoundingClientRect();
        const dx = e.clientX - r.left, dy = e.clientY - r.top;
        bar.classList.add("moved");
        const move = (ev) => {
          const x = Math.max(0, Math.min(w.width - r.width, ev.clientX - w.left - dx)), y = Math.max(0, Math.min(w.height - r.height, ev.clientY - w.top - dy));
          bar.style.left = x + "px"; bar.style.top = y + "px";
          if (bar.parentElement.id === "chartWrap") store.set("aurum.drawBarPos", JSON.stringify({ x, y }));
        };
        const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
        window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
      };
      grip.ondblclick = () => { store.set("aurum.drawBarPos", null); this.placeDrawBar(); };
    },

    /** The colour / width / style choices under a button of the drawing bar. */
    drawPickMenu(button, kind) {
      const d = this.drawings, cur = d && d.current;
      if (!cur) return;
      const menu = $("ctxMenu");
      if (kind === "color") {
        menu.innerHTML = `<div class="db-palette">${DRAW_PALETTE.map((c) => `<button type="button" data-v="${c}" class="${c.toLowerCase() === String(cur.color).toLowerCase() ? "on" : ""}" style="background:${c}" title="${c}"></button>`).join("")}</div>
          <label class="db-custom"><input type="color" value="${esc(String(cur.color).slice(0, 7))}"> Màu khác…</label>`;
      } else if (kind === "width") {
        menu.innerHTML = `<div class="db-list">${[0.5, 1, 1.5, 2, 3, 4].map((w) => `<button type="button" data-v="${w}" class="${w === cur.width ? "on" : ""}">${linePreview(w, "solid")}<span>${w}px</span></button>`).join("")}</div>`;
      } else {
        menu.innerHTML = `<div class="db-list">${[["solid", "Liền"], ["dashed", "Gạch"], ["dotted", "Chấm"]].map(([v, n]) => `<button type="button" data-v="${v}" class="${v === cur.style ? "on" : ""}">${linePreview(1.5, v)}<span>${n}</span></button>`).join("")}</div>`;
      }
      menu.classList.add("db-menu");
      menu.hidden = false;
      const r = button.getBoundingClientRect();
      menu.style.left = Math.max(8, Math.min(r.left, window.innerWidth - menu.offsetWidth - 8)) + "px";
      menu.style.top = Math.min(r.bottom + 8, window.innerHeight - menu.offsetHeight - 8) + "px";
      const done = (v) => {
        d.restyle({ [kind]: kind === "width" ? +v : v });
        this.closeMenu();
        this.renderDrawBar();
      };
      menu.querySelectorAll("[data-v]").forEach((b) => (b.onclick = () => done(b.dataset.v)));
      const custom = menu.querySelector("input[type=color]");
      if (custom) custom.onchange = () => done(custom.value);
    },

    /* ----- replay ----- */

    viewBars() { return this.replay ? this.bars.slice(0, this.replay.idx + 1) : this.bars; },

    startReplayPick() {
      if (this.replay) { this.exitReplay(); return; }
      this.replayPicking = true;
      this.renderReplayBar();
      this.updateTouchAction();
    },

    startReplayAt(i) {
      if (!this.bars.length) return;
      this.replayPicking = false;
      const prev = this.replay;
      this.replay = {
        idx: Math.max(10, Math.min(this.bars.length - 2, i)), playing: false, timer: null,
        speed: (prev && prev.speed) || +(store.get("aurum.rspeed") || 1),
        trades: (prev && prev.trades) || [], closed: (prev && prev.closed) || [],
      };
      if (prev) clearInterval(prev.timer);
      this.selected = null; this.renderSelBar();
      this.applyReplay(true);
    },

    applyReplay(scroll) {
      $("posPill").hidden = true;
      const view = this.viewBars();
      this.series.setData(view.map(shown));
      if (scroll) {
        // Keep the zoom: the same number of bars, ending at the replay bar.
        const r = this.chart.timeScale().getVisibleLogicalRange();
        const span = r ? Math.max(20, r.to - r.from) : 120;
        this.chart.timeScale().setVisibleLogicalRange({ from: view.length - span + 8, to: view.length + 8 });
      }
      this.computeICT();
      this.updateFlow();
      this.syncLines();
      this.renderReplayBar();
      this.redraw();
    },

    replayStep() {
      const r = this.replay;
      if (!r) return;
      if (r.idx >= this.bars.length - 1) { this.replayPause(); toast("Đã tới nến mới nhất"); return; }
      r.idx++;
      const bar = this.bars[r.idx];
      this.series.update(shown(bar));
      this.replayFill(bar);
      this.computeICT();
      this.updateFlow();
      this.syncLines();
      this.renderReplayBar();
      this.redraw();
    },

    replayPlay() {
      const r = this.replay;
      if (!r) return;
      if (r.playing) return this.replayPause();
      r.playing = true;
      r.timer = setInterval(() => this.replayStep(), 1000 / r.speed);
      this.renderReplayBar();
    },

    replayPause() {
      const r = this.replay;
      if (!r) return;
      r.playing = false;
      clearInterval(r.timer);
      this.renderReplayBar();
    },

    exitReplay() {
      if (this.replay) clearInterval(this.replay.timer);
      this.replay = null;
      this.replayPicking = false;
      this.series.setData(this.bars.map(shown));
      this.chart.timeScale().scrollToRealTime();
      this.computeICT();
      this.updateFlow();
      this.syncLines();
      this.renderReplayBar();
      this.updateTouchAction();
      this.redraw();
    },

    contractSize() {
      const s = this.symbolKey().toUpperCase();
      if (/XAU|GOLD/.test(s)) return 100;
      if (/XAG|SILVER/.test(s)) return 5000;
      if (/BTC|ETH|US30|USTEC|NAS|SPX|US500|DE30|DE40|JP225|UK100/.test(s)) return 1;
      return 100000;
    },

    replayOrder(side) {
      const r = this.replay;
      if (!r) return;
      const bar = this.bars[r.idx];
      const lots = Math.max(0.01, num($("rLots").value) || 0.01);
      store.set("aurum.rlots", String(lots));
      const t = { id: Math.random().toString(36).slice(2, 8), side, lots, entry: bar.close, time: bar.time,
        stop: num($("rStop").value), target: num($("rTarget").value) };
      r.trades.push(t);
      toast(`Replay: ${side === "long" ? "MUA" : "BÁN"} ${lots} @ ${fmt(t.entry, this.digits)}`);
      this.syncLines();
      this.renderReplayBar();
    },

    replayProfit(t, price) { return (price - t.entry) * (t.side === "long" ? 1 : -1) * t.lots * this.contractSize(); },

    replayClose(t, price, reason) {
      const r = this.replay;
      r.trades = r.trades.filter((x) => x !== t);
      r.closed.unshift(Object.assign({}, t, { exit: price, reason, profit: this.replayProfit(t, price) }));
    },

    /** SL/TP of replay trades hit inside the new bar (SL first when both are inside). */
    replayFill(bar) {
      this.replay.trades.slice().forEach((t) => {
        const long = t.side === "long";
        if (t.stop && (long ? bar.low <= t.stop : bar.high >= t.stop)) return this.replayClose(t, t.stop, "SL");
        if (t.target && (long ? bar.high >= t.target : bar.low <= t.target)) this.replayClose(t, t.target, "TP");
      });
    },

    renderReplayBar() {
      const bar = $("replayBar");
      const r = this.replay;
      if (this.replayPicking) {
        bar.hidden = false;
        bar.innerHTML = `<div class="r-row"><b>⏮ Replay</b><span class="muted">Chạm vào nến muốn bắt đầu</span><button type="button" class="btn btn-ghost btn-small" data-a="exit">Huỷ</button></div>`;
        bar.querySelector("[data-a=exit]").onclick = () => this.exitReplay();
        this.updateTouchAction();
        return;
      }
      if (!r) { bar.hidden = true; return; }
      const cur = this.bars[r.idx];
      const price = cur.close;
      const floating = r.trades.reduce((a, t) => a + this.replayProfit(t, price), 0);
      const done = r.closed.reduce((a, t) => a + t.profit, 0);
      const wins = r.closed.filter((t) => t.profit > 0).length;
      bar.hidden = false;
      bar.innerHTML = `<div class="r-row">
          <button type="button" class="rb" data-a="exit" title="Thoát replay">✕</button>
          <button type="button" class="rb" data-a="pick" title="Chọn lại điểm bắt đầu">⟲</button>
          <button type="button" class="rb play" data-a="play" title="Chạy / dừng (phím cách)">${r.playing ? "⏸" : "▶"}</button>
          <button type="button" class="rb" data-a="step" title="Nến tiếp theo (→)">⏭</button>
          <select data-a="speed" title="Tốc độ">${[0.5, 1, 2, 3, 5, 10].map((v) => `<option value="${v}" ${v === r.speed ? "selected" : ""}>${v} nến/giây</option>`).join("")}</select>
          <span class="r-time">${new Date((cur.time + TZ) * 1000).toLocaleString("vi-VN", { timeZone: "UTC", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })} · <b>${fmt(price, this.digits)}</b></span>
        </div>
        <div class="r-row">
          <button type="button" class="rb sellbg" data-a="sell">SELL</button>
          <input id="rLots" inputmode="decimal" value="${esc(store.get("aurum.rlots") || "0.01")}" title="Lot">
          <button type="button" class="rb buybg" data-a="buy">BUY</button>
          <input id="rStop" inputmode="decimal" placeholder="SL" value="${esc((this.rDraft || {}).stop || "")}">
          <input id="rTarget" inputmode="decimal" placeholder="TP" value="${esc((this.rDraft || {}).target || "")}">
          ${r.trades.length ? `<button type="button" class="rb" data-a="closeAll">Đóng ${r.trades.length} lệnh</button>` : ""}
          <span class="r-pnl">Đang mở <b class="${floating >= 0 ? "pos" : "neg"}">${signed(floating)}</b> · Đã đóng ${r.closed.length ? `${wins}/${r.closed.length} thắng ` : ""}<b class="${done >= 0 ? "pos" : "neg"}">${signed(done)}</b> USD</span>
        </div>`;
      const on = (a, f) => { const b = bar.querySelector(`[data-a=${a}]`); if (b) b.onclick = f; };
      on("exit", () => this.exitReplay());
      on("pick", () => { this.replayPause(); this.replayPicking = true; this.renderReplayBar(); });
      on("play", () => this.replayPlay());
      on("step", () => { this.replayPause(); this.replayStep(); });
      on("sell", () => this.replayOrder("short"));
      on("buy", () => this.replayOrder("long"));
      on("closeAll", () => { r.trades.slice().forEach((t) => this.replayClose(t, price, "Đóng tay")); this.syncLines(); this.renderReplayBar(); });
      bar.querySelector("[data-a=speed]").onchange = (e) => {
        r.speed = +e.target.value; store.set("aurum.rspeed", String(r.speed));
        if (r.playing) { clearInterval(r.timer); r.timer = setInterval(() => this.replayStep(), 1000 / r.speed); }
      };
      ["rStop", "rTarget"].forEach((id) => ($(id).oninput = () => { this.rDraft = { stop: $("rStop").value, target: $("rTarget").value }; }));
    },

    /* ----- drawing toolbar on the left of the chart (TradingView-style) ----- */

    renderToolRail() {
      const rail = $("toolRail");
      if (!rail || !this.drawings) return;
      this.renderFavBar();
      const d = this.drawings;
      const shown = store.get("aurum.rail") !== "0" && !(store.get("aurum.rail") == null && $("chart").clientWidth < 500);
      rail.hidden = !shown;
      $("drawBtn").classList.toggle("on", shown);
      const last = (g) => store.get("aurum.rail." + g.id) || g.tools[0];
      const btn = (key, icon, title, on, extra = "") => `<button type="button" data-k="${key}" class="${on ? "on" : ""} ${extra}" title="${esc(title)}">${icon}</button>`;
      rail.innerHTML = btn("cursor", RAIL_ICON.cursor, "Con trỏ", !d.tool)
        + RAIL_GROUPS.map((g) => {
          const t = g.tools.includes(d.tool) ? d.tool : last(g);
          return btn("g:" + g.id, TOOL_ICON[t] || RAIL_ICON[g.id], g.title + " · " + window.AurumDrawings.tools[t].name, g.tools.includes(d.tool), "grp");
        }).join("")
        + '<i class="sep"></i>'
        + btn("measure", TOOL_ICON.priceRange, "Đo giá", d.tool === "priceRange")
        + btn("zoom", RAIL_ICON.zoom, "Phóng to (chuột phải → Đặt lại biểu đồ để thu nhỏ)", false)
        + '<i class="sep"></i>'
        + btn("magnet", RAIL_ICON.magnet, "Nam châm: bắt vào giá mở/cao/thấp/đóng", this.magnet)
        + btn("keep", RAIL_ICON.keep, "Giữ chế độ vẽ (vẽ liên tục)", d.keepTool)
        + btn("lock", d.lockAll ? RAIL_ICON.lock : RAIL_ICON.unlock, "Khoá tất cả bản vẽ", d.lockAll)
        + btn("hide", d.hidden ? RAIL_ICON.eyeOff : RAIL_ICON.eye, "Ẩn tất cả bản vẽ", d.hidden)
        + '<i class="sep"></i>'
        + btn("trash", RAIL_ICON.trash, "Xoá tất cả bản vẽ", false);
      rail.querySelectorAll("button").forEach((b) => (b.onclick = (e) => {
        e.stopPropagation();
        const k = b.dataset.k;
        if (k.startsWith("g:")) {
          const g = RAIL_GROUPS.find((x) => x.id === k.slice(2));
          const open = !$("flyout").hidden && $("flyout").dataset.g === g.id;
          if (!g.tools.includes(d.tool)) d.setTool(last(g));
          if (open) this.closeFlyout(); else this.openFlyout(g, b);
          return;
        }
        this.closeFlyout();
        if (k === "cursor") d.cancel();
        if (k === "measure") d.setTool(d.tool === "priceRange" ? null : "priceRange");
        if (k === "zoom") { const ts = this.chart.timeScale(); ts.applyOptions({ barSpacing: Math.min(50, (ts.options().barSpacing || 6) * 1.5) }); }
        if (k === "magnet") { this.magnet = !this.magnet; store.set("aurum.magnet", this.magnet ? "1" : "0"); }
        const all = this.allDrawings();
        if (k === "keep") { const v = !d.keepTool; all.forEach((x) => (x.keepTool = v)); store.set("aurum.keepTool", v ? "1" : "0"); }
        if (k === "lock") { const v = !d.lockAll; all.forEach((x) => (x.lockAll = v)); store.set("aurum.lockAll", v ? "1" : "0"); }
        if (k === "hide") { const v = !d.hidden; all.forEach((x) => { x.hidden = v; x.selected = null; x.update(); }); }
        if (k === "trash" && d.list.length && confirm(`Xoá tất cả ${d.list.length} bản vẽ trên mã này?`)) d.clear();
        this.renderToolRail();
        this.renderDrawBar();
      }));
    },

    openFlyout(g, button) {
      const fly = $("flyout"), d = this.drawings, D = window.AurumDrawings;
      fly.dataset.g = g.id;
      const fav = this.favorites();
      fly.innerHTML = `<div class="fly-title">${esc(g.title)}</div>` + g.tools.map((t) => `<div class="fly-row"><button type="button" data-t="${t}" class="${d.tool === t ? "on" : ""}">${TOOL_ICON[t] || ""}<span>${esc(D.tools[t].name)}</span></button><button type="button" class="star ${fav.includes(t) ? "on" : ""}" data-fav="${t}" title="Thêm vào thanh yêu thích">${fav.includes(t) ? "★" : "☆"}</button></div>`).join("");
      fly.querySelectorAll("[data-fav]").forEach((b) => (b.onclick = (e) => {
        e.stopPropagation();
        this.toggleFavorite(b.dataset.fav);
        const on = this.favorites().includes(b.dataset.fav);
        b.classList.toggle("on", on); b.textContent = on ? "★" : "☆";
      }));
      fly.hidden = false;
      // The rail may have been redrawn by the tool change: measure its current button.
      const now = $("toolRail").querySelector(`[data-k="g:${g.id}"]`) || button;
      const body = $("toolRail").parentElement.getBoundingClientRect(), r = now.getBoundingClientRect();
      fly.style.top = Math.max(0, Math.min(r.top - body.top, body.height - fly.offsetHeight)) + "px";
      fly.querySelectorAll("button[data-t]").forEach((b) => (b.onclick = (e) => {
        e.stopPropagation();
        store.set("aurum.rail." + g.id, b.dataset.t);
        d.setTool(b.dataset.t);
        this.closeFlyout();
      }));
    },

    closeFlyout() { const f = $("flyout"); if (f && !f.hidden) f.hidden = true; },

    toggleRail() {
      const shown = !$("toolRail").hidden;
      store.set("aurum.rail", shown ? "0" : "1");
      this.renderToolRail();
    },

    /* ----- floating settings panel (the chart stays visible, like TradingView) ----- */

    /**
     * opts: root (the object `data-p` paths point into), onChange(), onReset(redraw),
     * onCancel(), template(action) for the "Bản mẫu" menu, tab (first tab to show).
     */
    openPanel(title, tabs, render, opts = {}) {
      const panel = $("floatPanel");
      let tab = opts.tab && tabs.some(([k]) => k === opts.tab) ? opts.tab : tabs[0][0];
      const draw = () => {
        const scroll = panel.querySelector(".fp-body") ? panel.querySelector(".fp-body").scrollTop : 0;
        panel.innerHTML = `<div class="fp-head"><b>${esc(title)}</b><button type="button" class="fp-x" data-x>✕</button></div>
          <div class="fp-tabs">${tabs.map(([k, n]) => `<button type="button" data-tab="${k}" class="${k === tab ? "on" : ""}">${n}</button>`).join("")}</div>
          <div class="fp-body">${render(tab)}</div>
          <div class="fp-foot">
            ${opts.template ? `<select data-tpl><option value="">Bản mẫu</option><option value="saveAs">Lưu bản mẫu vẽ dưới dạng…</option><option value="reset">Áp dụng mẫu vẽ mặc định</option><option value="save">Đặt làm mặc định cho công cụ</option>${(opts.templateNames ? opts.templateNames() : []).map((n) => `<option value="tpl:${esc(n)}">▦ ${esc(n)}</option>`).join("")}</select>` : ""}
            ${opts.onReset ? '<button type="button" class="btn btn-ghost btn-small" data-reset>Mặc định</button>' : ""}
            <span class="grow"></span>
            ${opts.onCancel ? '<button type="button" class="btn btn-ghost btn-small" data-cancel>Hủy bỏ</button>' : ""}
            <button type="button" class="btn btn-gold btn-small" data-ok>Ok</button></div>`;
        const close = () => { panel.hidden = true; if (opts.onClose) opts.onClose(); };
        panel.querySelector("[data-x]").onclick = () => (opts.onCancel ? opts.onCancel() : null, close());
        panel.querySelector("[data-ok]").onclick = close;
        const cancel = panel.querySelector("[data-cancel]");
        if (cancel) cancel.onclick = () => { opts.onCancel(); close(); };
        panel.querySelectorAll("[data-tab]").forEach((b) => (b.onclick = () => { tab = b.dataset.tab; draw(); panel.querySelector(".fp-body").scrollTop = 0; }));
        const reset = panel.querySelector("[data-reset]");
        if (reset) reset.onclick = () => opts.onReset(draw);
        const tpl = panel.querySelector("[data-tpl]");
        if (tpl) tpl.onchange = () => { if (tpl.value) opts.template(tpl.value, draw); tpl.value = ""; };
        this.bindPanel(panel, opts.root, opts.onChange, draw);
        if (opts.afterDraw) opts.afterDraw(panel, tab);
        panel.querySelector(".fp-body").scrollTop = scroll;
        // Drag the panel by its title bar.
        const head = panel.querySelector(".fp-head");
        head.onpointerdown = (e) => {
          if (e.target.closest("button")) return;
          const r = panel.getBoundingClientRect(), dx = e.clientX - r.left, dy = e.clientY - r.top;
          const move = (ev) => {
            panel.style.left = Math.max(0, Math.min(window.innerWidth - r.width, ev.clientX - dx)) + "px";
            panel.style.top = Math.max(0, Math.min(window.innerHeight - 60, ev.clientY - dy)) + "px";
            panel.style.right = "auto"; panel.style.bottom = "auto";
          };
          const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
          window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
        };
      };
      this.panelDraw = draw;
      draw();
      panel.hidden = false;
    },

    /** Inputs with data-p write into `root` by path; data-redraw re-renders the panel after. */
    bindPanel(panel, root, onChange, draw) {
      panel.querySelectorAll("[data-p]").forEach((input) => {
        const apply = () => {
          const path = input.dataset.p.split("."), last = path.pop();
          const obj = path.reduce((o, k) => (o[k] == null ? (o[k] = {}) : o[k]), root);
          const t = input.dataset.t;
          let v;
          if (t === "bool") v = input.checked;
          else if (t === "notbool") v = !input.checked;
          else if (t === "boolsel") v = input.value === "true";
          else if (t === "num") { v = num(input.value); if (v == null) return; }
          else if (t === "time") {
            const m = /^(\d{1,2}):?(\d{2})$/.exec(input.value.trim());
            if (!m || +m[1] > 24 || +m[2] > 59) return;
            v = +m[1] + +m[2] / 60;
            // A session ending at 00:00 ends at midnight.
            if (v === 0 && last === "end") v = 24;
          } else if (t === "date") {
            const ms = Date.parse(input.value);
            if (isNaN(ms)) return;
            v = ms / 1000;
          } else v = input.value;
          obj[last] = v;
          if (onChange) onChange();
          if (input.dataset.redraw != null && draw) draw();
        };
        input.addEventListener(input.type === "checkbox" || input.tagName === "SELECT" || input.type === "color" || input.type === "datetime-local" ? "change" : "input", apply);
      });
    },

    /* ----- settings of one drawing (Định dạng / Văn bản / Tọa độ / Hiển thị) ----- */

    drawingSettings(d, isNew) {
      if (!d) return;
      const D = window.AurumDrawings;
      const dr = this.allDrawings().find((x) => x.list.includes(d) || x.pending === d) || this.drawings;
      const before = JSON.stringify(d);
      const tool = d.tool, pos = D.isPosition(tool);
      const fib = tool === "fibRetracement" || tool === "fibExtension";
      const styles = [["solid", "———"], ["dashed", "– – –"], ["dotted", "·····"]];
      const widths = [[0.5, "0.5px"], [1, "1px"], [1.5, "1.5px"], [2, "2px"], [3, "3px"], [4, "4px"]];
      const sizes = [10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 40].map((v) => [v, String(v)]);
      const k = fieldKit(d);
      const lineRow = (label = "Đường") => `<div class="fr"><span class="grow">${label}</span>${k.sw("color")}${k.selI("width", widths)}${k.selI("style", styles)}</div>`;
      const fontRow = (label) => `<div class="fr">${label ? `<span class="grow">${label}</span>` : ""}${k.sw("textColor")}${k.selI("fontSize", sizes)}
        <label class="fbtn ${d.bold ? "on" : ""}"><input type="checkbox" data-p="bold" data-t="bool" data-redraw ${d.bold ? "checked" : ""}><b>B</b></label>
        <label class="fbtn ${d.italic ? "on" : ""}"><input type="checkbox" data-p="italic" data-t="bool" data-redraw ${d.italic ? "checked" : ""}><i>I</i></label></div>`;
      const fillRow = (label = "Hình nền") => `<div class="fr">${k.chk("fill")}<span class="grow">${label}</span>${k.sw("fillColor")}<input type="range" min="0" max="80" data-p="fillOpacity" data-t="num" value="${d.fillOpacity}" class="op"></div>`;
      const textBox = () => `<textarea class="fp-text" data-p="text" data-t="str" placeholder="Thêm văn bản">${esc(d.text)}</textarea>`;
      const textOpts = () => `<div class="fr">${k.chk("textBg")}<span class="grow">Hình nền</span>${k.sw("textBgColor")}</div>
        <div class="fr">${k.chk("textBorder")}<span class="grow">Đường viền</span>${k.sw("textBorderColor")}</div>
        <div class="fr">${k.chk("wrap")}<span>Tự động xuống dòng</span></div>`;
      const render = (tab) => {
        if (tab === "text") {
          return fontRow() + textBox() + (tool === "text" ? textOpts()
            : `<div class="fr"><span class="grow">Vị trí chữ</span>${k.selI("textV", [["top", "Trên"], ["middle", "Giữa"], ["bottom", "Dưới"]])}${k.selI("textH", [["left", "Trái"], ["center", "Giữa"], ["right", "Phải"]])}</div>` + textOpts());
        }
        if (tab === "coords") {
          const names = pos ? ["Giá vào", "Dừng lỗ", "Mục tiêu"] : D.tools[tool].labels || [];
          return d.pts.map((p, i) => `<div class="fp-sec">${esc(names[i] || "Điểm " + (i + 1))}</div>
            <div class="fr"><span class="grow">Giá</span><input class="n wide-n" data-p="pts.${i}.p" data-t="num" inputmode="decimal" value="${p.p}"></div>
            <div class="fr"><span class="grow">Thời gian</span><input type="datetime-local" data-p="pts.${i}.t" data-t="date" value="${localInput(p.t)}"></div>`).join("");
        }
        if (tab === "view") {
          return `<div class="fp-sec">Hiện trên khung</div>` + D.timeframes.map((tf) => `<label class="fr"><input type="checkbox" data-p="hideOn.${tf}" data-t="notbool" ${d.hideOn && d.hideOn[tf] ? "" : "checked"}><span>${tf}</span></label>`).join("");
        }
        // Định dạng
        let html = "";
        if (pos) {
          html += lineRow("Đường giá vào") + `<div class="fr"><span class="grow">Vùng mục tiêu</span>${k.sw("targetColor")}</div><div class="fr"><span class="grow">Vùng dừng lỗ</span>${k.sw("stopColor")}</div>`
            + fillRow("Tô nền") + `<p class="fp-note">Kéo chấm tròn để chỉnh giá vào, dừng lỗ và mục tiêu (R:R tự tính). Vị thế không bị kéo ngược chiều.</p>`;
        } else if (fib) {
          const f = d.fib;
          html += lineRow("Đường") + `<div class="fp-sec">Các mức</div><div class="fib-grid">${f.levels.map((l, i) => `<div class="fr">${k.chk(`fib.levels.${i}.on`)}<input class="n" data-p="fib.levels.${i}.v" data-t="num" inputmode="decimal" value="${l.v}">${k.sw(`fib.levels.${i}.color`)}<button type="button" class="fib-del" data-fibdel="${i}" title="Xoá mức">×</button></div>`).join("")}</div>
            <div class="fib-add-row"><input class="n" id="fibNew" inputmode="decimal" placeholder="VD 1.272"><input type="color" id="fibNewColor" class="sw" value="#2962ff"><button type="button" class="btn btn-ghost btn-small" data-fibadd>+ Thêm mức</button></div>
            <div class="fr">${k.chk("fib.oneColorOn")}<span class="grow">Sử dụng một màu</span>${k.sw("fib.oneColor")}</div>
            <div class="fr">${k.chk("fib.bg")}<span class="grow">Hình nền</span><input type="range" min="0" max="50" data-p="fib.bgOpacity" data-t="num" value="${f.bgOpacity}" class="op"></div>
            <div class="fr">${k.chk("fib.reverse")}<span>Đảo ngược</span></div>
            <div class="fr">${k.chk("fib.trend")}<span>Đường xu hướng</span></div>
            <div class="fr">${k.chk("fib.prices")}<span>Các mức giá</span></div>
            <div class="fr">${k.chk("fib.values")}<span>Mức độ</span></div>
            <div class="fr"><span class="grow">Kéo dài</span><label class="mini">${k.chk("fib.extendLeft")} Sang trái</label><label class="mini">${k.chk("fib.extendRight")} Sang phải</label></div>
            <div class="fr"><span class="grow">Nhãn</span>${k.selI("fib.labelSide", [["left", "Bên trái"], ["right", "Bên phải"]])}</div>
            <div class="fr"><span class="grow">Cỡ chữ</span>${k.selI("fib.fontSize", sizes)}</div>`;
        } else if (tool === "text") {
          html += fontRow("Chữ") + textOpts();
        } else {
          if (tool === "rectangle" || tool === "trendLine") html += `<div class="fr"><span class="grow">Kéo dài</span>${k.selI("extend", [["none", "Đừng mở rộng"], ["left", "Sang trái"], ["right", "Sang phải"], ["both", "Cả hai phía"]])}</div>`;
          html += lineRow(tool === "rectangle" || tool === "ellipse" ? "Đường viền" : "Đường");
          if (tool === "rectangle" || tool === "trendLine") html += `<div class="fr">${k.chk("mid")}<span class="grow">Đường trung bình</span>${k.sw("midColor")}${k.selI("midStyle", styles)}</div>`;
          if (D.tools[tool].labels) html += fontRow("Nhãn");
          if (D.hasFill(tool)) html += fillRow();
        }
        return html;
      };
      const tabs = tool === "text" ? [["text", "Văn bản"], ["coords", "Tọa độ"], ["view", "Hiển thị"]]
        : [["style", "Định dạng"]].concat(fib || pos || ["brush", "path", "fixedRangeVolume", "anchoredVolume", "priceRange"].includes(tool) ? [] : [["text", "Văn bản"]]).concat([["coords", "Tọa độ"], ["view", "Hiển thị"]]);
      this.openPanel(D.tools[tool].name, tabs, render, {
        root: d, tab: isNew && tool === "text" ? "text" : undefined,
        onChange: () => { dr.changed(d); dr.remember(d); this.renderDrawBar(); },
        onCancel: () => {
          Object.assign(d, JSON.parse(before));
          if (isNew && tool === "text" && !d.text) dr.remove(d.id); else dr.changed(d);
        },
        onClose: () => { if (tool === "text" && !d.text) dr.remove(d.id); this.renderDrawBar(); },
        templateNames: () => Object.keys(dr.templates(tool)),
        template: (action, redraw) => {
          if (action === "save") { dr.saveAsDefault(d); toast("Đã đặt làm mặc định cho " + D.tools[tool].name); }
          if (action === "reset") { dr.resetDefault(tool); dr.applyTemplate(d, null); redraw(); }
          if (action === "saveAs") this.saveTemplateDialog(dr, d, redraw);
          if (action.startsWith("tpl:")) { dr.applyTemplate(d, action.slice(4)); redraw(); this.renderDrawBar(); }
        },
        afterDraw: (panel) => {
          const t = panel.querySelector(".fp-text"); if (t && isNew) setTimeout(() => t.focus(), 30);
          // Fibonacci: own levels added and any level removed.
          const saveFib = () => { dr.changed(d); dr.remember(d); if (this.panelDraw) this.panelDraw(); };
          panel.querySelectorAll("[data-fibdel]").forEach((b) => (b.onclick = () => { d.fib.levels.splice(+b.dataset.fibdel, 1); saveFib(); }));
          const add = panel.querySelector("[data-fibadd]");
          if (add) add.onclick = () => {
            const v = num(panel.querySelector("#fibNew").value);
            if (v == null) { toast("Nhập mức, ví dụ 1.272 hoặc -0.5", true); return; }
            if (d.fib.levels.some((l) => l.v === v)) { toast("Đã có mức " + v, true); return; }
            d.fib.levels.push({ v, on: true, color: panel.querySelector("#fibNewColor").value });
            d.fib.levels.sort((a, b) => b.v - a.v);
            saveFib();
          };
        },
      });
    },

    /* ----- named drawing templates ----- */

    templateMenu(button, dr, d) {
      if (!d) return;
      const names = Object.keys(dr.templates(d.tool));
      const r = button.getBoundingClientRect();
      const menu = $("ctxMenu");
      menu.innerHTML = `<button type="button" data-k="saveAs">Lưu bản mẫu vẽ dưới dạng…</button><button type="button" data-k="default">Áp dụng mẫu vẽ mặc định</button>`
        + (names.length ? `<hr>` + names.map((n) => `<div class="tpl-row"><button type="button" data-k="tpl" data-n="${esc(n)}">${esc(n)}</button><button type="button" class="tpl-x" data-del="${esc(n)}" title="Xoá bản mẫu">✕</button></div>`).join("") : "");
      menu.hidden = false;
      menu.style.left = Math.max(8, Math.min(r.left, window.innerWidth - menu.offsetWidth - 8)) + "px";
      menu.style.top = Math.min(r.bottom + 6, window.innerHeight - menu.offsetHeight - 8) + "px";
      menu.querySelectorAll("[data-k]").forEach((b) => (b.onclick = () => {
        this.closeMenu();
        if (b.dataset.k === "saveAs") this.saveTemplateDialog(dr, d);
        if (b.dataset.k === "default") { dr.applyTemplate(d, null); this.renderDrawBar(); }
        if (b.dataset.k === "tpl") { dr.applyTemplate(d, b.dataset.n); this.renderDrawBar(); }
      }));
      menu.querySelectorAll("[data-del]").forEach((b) => (b.onclick = (e) => {
        e.stopPropagation();
        dr.deleteTemplate(d.tool, b.dataset.del);
        b.parentElement.remove();
      }));
    },

    saveTemplateDialog(dr, d, after) {
      const names = Object.keys(dr.templates(d.tool));
      sheet.open(`<h3>Lưu biểu mẫu vẽ</h3>
        <div class="fields"><label>Tên biểu mẫu mới<input id="tplName" list="tplNames" maxlength="40" placeholder="vd: OTE, RISK, TP"><datalist id="tplNames">${names.map((n) => `<option value="${esc(n)}">`).join("")}</datalist></label></div>
        <div class="row-btns end"><button class="btn btn-ghost btn-small" data-close>Hủy bỏ</button><button class="btn btn-gold btn-small" id="tplSave" disabled>Lưu</button></div>`, (el) => {
        const input = el.querySelector("#tplName"), save = el.querySelector("#tplSave");
        input.oninput = () => { save.disabled = !input.value.trim(); save.textContent = names.includes(input.value.trim()) ? "Ghi đè" : "Lưu"; };
        const go = () => {
          const name = input.value.trim();
          if (!name) return;
          dr.saveTemplate(d, name);
          sheet.close();
          toast(`Đã lưu bản mẫu "${name}" cho ${window.AurumDrawings.tools[d.tool].name}`);
          if (after) after();
        };
        save.onclick = go;
        input.onkeydown = (e) => { if (e.key === "Enter") go(); };
        setTimeout(() => input.focus(), 30);
      });
    },

    /* ----- indicator settings (like the app's ICT Killzones + Pivots sheet) ----- */

    saveIct() {
      store.set("aurum.ictcfg", JSON.stringify(this.ictCfg));
      if (this.ictCfg.smtSymbol !== this.lastSmtSymbol) {
        this.lastSmtSymbol = this.ictCfg.smtSymbol;
        clearTimeout(this.cmpReload);
        this.cmpReload = setTimeout(() => this.loadCmp(), 700);
      }
      this.computeICT();
      this.redraw();
    },

    ictSettingsSheet() {
      if (!this.owner && this.features.killzones === false) return toast("Chỉ báo chưa được mở cho bạn", true);
      sheet.close();
      const tfOpts = [[1, "1m"], [5, "5m"], [15, "15m"], [30, "30m"], [60, "1h"], [240, "4h"], [1440, "1D"]];
      const styles = [["solid", "———"], ["dashed", "– – –"], ["dotted", "·····"]];
      const render = (tab) => {
        const cfg = this.ictCfg;
        const { chk, tog, numf, sel, selI, sw, color, time, text, head, note } = fieldKit(cfg);
        if (tab === "inputs") {
          return head("Killzones") + tog("showBoxes", "Hiện hộp phiên")
            + cfg.sessions.map((s, i) => `<div class="fr">${chk(`sessions.${i}.on`)}${sw(`sessions.${i}.color`)}${text(`sessions.${i}.name`)}${time(`sessions.${i}.start`)}<span class="to">—</span>${time(`sessions.${i}.end`)}</div>`).join("")
            + head("Pivots") + tog("showPivots", "Hiện điểm pivot (đỉnh/đáy phiên)") + tog("pivotLabels", "Nhãn pivot") + tog("livePivots", "Hiện khi phiên đang chạy")
            + sel("pivotUntilMitigated", "Kéo dài", [[true, "Tới khi giá phá"], [false, "Qua cả khi bị phá"]]) + tog("keepMitigated", "Giữ pivot đã bị phá") + tog("midpoints", "Đường giữa phiên (50%)")
            + cfg.sessions.map((s, i) => `<div class="fr"><span class="grow muted">${esc(s.name)}</span>${text(`sessions.${i}.hi`, "lb")}${text(`sessions.${i}.lo`, "lb")}</div>`).join("")
            + head("Giá mở cửa") + cfg.opens.map((o, i) => `<div class="fr">${chk(`opens.${i}.on`)}${sw(`opens.${i}.color`)}${text(`opens.${i}.label`, "lb")}${time(`opens.${i}.hour`)}</div>`).join("")
            + head("Mốc thời gian (đường dọc)") + cfg.stamps.map((m, i) => `<div class="fr">${chk(`stamps.${i}.on`)}${time(`stamps.${i}.hour`)}</div>`).join("")
            + head("Giờ cắt") + `<div class="fr">${chk("cutoff")}<span class="grow">Dừng các đường lúc</span>${time("cutoffHour")}</div>`
            + head("Đỉnh / đáy ngày") + tog("daily", "Đỉnh / đáy từng ngày") + numf("dailyDays", "Số ngày gần nhất") + tog("dailyKeepTouched", "Giá chạm: dừng lại, nét chấm ……")
            + tog("prevDay", "PDH / PDL (ngày trước)") + tog("prevWeek", "PWH / PWL (tuần trước)") + tog("prevMonth", "PMH / PML (tháng trước)")
            + head("FVG & VI") + tog("fvg", "Hiện FVG") + tog("fvgStrong", "Chỉ FVG mạnh (lọc FVG yếu)") + numf("fvgDisplacement", "Nến tạo FVG ≥ × thân TB", 0.1)
            + tog("fvgConfluence", "Tô nền khi trùng FVG khung lớn") + tog("fvgMid", "Đường giữa 50%") + tog("fvgHideFilled", "Ẩn FVG đã bị chạm")
            + numf("gapKeep", "Chạm rồi bật ngược: giữ (phút)") + numf("fvgMinSize", "Lọc FVG nhỏ (× biên độ nến)", 0.1) + numf("fvgCount", "Giữ FVG gần nhất")
            + tog("vi", "Hiện VI (Volume Imbalance)") + numf("viCount", "Giữ VI gần nhất") + tog("viHideTouched", "Ẩn VI đã bị chạm")
            + head("Cấu trúc") + tog("mss", "MSS (đổi cấu trúc)") + tog("bos", "BOS (phá cấu trúc cùng xu hướng)") + numf("swing", "Swing: số nến mỗi bên") + numf("structureCount", "Giữ số lần phá gần nhất")
            + head("Thanh khoản") + tog("sweeps", "Quét thanh khoản") + numf("sweepCount", "Giữ số lần quét gần nhất")
            + head("SMT") + `<label class="fr"><input type="checkbox" data-smt ${showInd.smt ? "checked" : ""}><span>Hiện SMT khi mở 2 biểu đồ (nút ▥)</span></label>`
            + (this.owner ? `<div class="fr"><span class="grow">Mã so sánh</span>${text("smtSymbol", "lb")}<span class="muted small">trống = tự động (${esc(this.cmpSymbol())})</span></div>` : "")
            + tog("smtInverse", "Mã so sánh chạy ngược chiều (DXY)") + numf("smtSwing", "Swing: số nến mỗi bên") + numf("smtLookback", "Hai đỉnh/đáy cách tối đa (nến)") + numf("smtCount", "Giữ SMT gần nhất")
            + head("Macros") + tog("macros", "Hiện macros")
            + cfg.macroList.map((m, i) => `<div class="fr">${chk(`macroList.${i}.on`)}${text(`macroList.${i}.name`)}${time(`macroList.${i}.start`)}<span class="to">—</span>${time(`macroList.${i}.end`)}</div>`).join("");
        }
        if (tab === "style") {
          return head("Hộp phiên") + tog("boxLabels", "Tên phiên trên hộp") + tog("boxBorder", "Viền hộp") + numf("boxOpacity", "Độ đậm nền (%)")
            + head("Đường") + sel("lineScale", "Độ dày chung", [[0.5, "0.5px"], [0.75, "Mảnh"], [1, "Vừa"], [1.5, "Dày"], [2, "Rất dày"]]) + numf("pivotWidth", "Độ dày pivot", 0.5)
            + sel("pivotStyle", "Nét pivot", styles) + sel("mitigatedStyle", "Nét pivot đã bị phá", styles) + sel("openStyle", "Nét giá mở cửa", styles)
            + color("stampColor", "Màu mốc thời gian") + sel("stampStyle", "Nét mốc thời gian", styles)
            + head("Đỉnh / đáy ngày") + color("dayHighColor", "Màu đỉnh ngày") + color("dayLowColor", "Màu đáy ngày") + sel("dailyStyle", "Nét", styles) + color("periodColor", "Màu PDH/PWH/PMH")
            + head("FVG & VI") + color("fvgBull", "FVG tăng") + color("fvgBear", "FVG giảm") + color("fvgZone", "Nền FVG trùng khung") + color("fvgZoneMid", "Đường giữa FVG trùng khung") + color("viColor", "VI")
            + head("SMT") + color("smtBull", "SMT tăng") + color("smtBear", "SMT giảm")
            + head("Khác") + color("mssBull", "MSS tăng") + color("mssBear", "MSS giảm") + color("sweepColor", "Quét thanh khoản") + color("macroColor", "Macros");
        }
        return head("Chung") + sel("timeZone", "Múi giờ", [["America/New_York", "New York (ICT)"], ["UTC", "UTC"], ["Asia/Ho_Chi_Minh", "Hà Nội (UTC+7)"], ["Europe/London", "London"]])
          + sel("tfLimit", "Killzones trên khung ≤", tfOpts.slice(0, 6)) + numf("maxDays", "Số ngày hiển thị")
          + note("Giờ các phiên theo múi giờ ở trên (ICT dùng giờ New York).")
          + head("FVG") + `<div class="fr"><span class="grow">Từ khung</span>${selI("fvgFrom", tfOpts)}<span class="to">→</span>${selI("fvgTo", tfOpts)}</div>`
          + head("Macros") + sel("macroTfLimit", "Trên khung ≤", tfOpts.slice(0, 4)) + sel("macroTimeLabels", "Nhãn hộp", [[true, "Giờ"], [false, "Tên"]])
          + head("Khác") + tog("dayOfWeek", "Nhãn thứ trong tuần") + tog("rangeTable", "Bảng biên độ phiên") + numf("rangeAvg", "Trung bình số phiên");
      };
      const open = () => this.openPanel("ICT Killzones + Pivots", [["inputs", "Các đầu vào"], ["style", "Định dạng"], ["view", "Hiển thị"]], render, {
        root: this.ictCfg,
        onChange: () => this.saveIct(),
        afterDraw: (panel) => {
          const box = panel.querySelector("[data-smt]");
          if (box) box.onchange = () => { showInd.smt = box.checked; store.set("aurum.ind", JSON.stringify(showInd)); this.loadCmp(); };
        },
        onReset: () => {
          if (!confirm("Đặt lại mọi cài đặt chỉ báo về mặc định?")) return;
          this.ictCfg = window.ICT.defaults(); this.saveIct(); open();
        },
      });
      open();
    },

    /* ----- chart look and light / dark theme ----- */

    chartStyleSheet() {
      const st = this.chartStyle;
      const render = () => {
        const k = fieldKit(st);
        return `<div class="fp-sec">Giao diện web</div>
          <div class="fr"><span class="grow">Chế độ</span>${k.selI("theme", [["dark", "Tối"], ["light", "Sáng"], ["auto", "Theo máy"]])}</div>
          <div class="fp-sec">Nến</div>
          <div class="fr"><span class="grow">Thân nến tăng / giảm</span>${k.sw("up")}${k.sw("down")}</div>
          <div class="fr">${k.chk("border")}<span class="grow">Viền nến</span>${k.sw("borderUp")}${k.sw("borderDown")}</div>
          <div class="fr"><span class="grow">Bấc nến tăng / giảm</span>${k.sw("wickUp")}${k.sw("wickDown")}</div>
          <div class="fp-sec">Nền và lưới</div>
          <div class="fr">${k.chk("customBg")}<span class="grow">Màu nền riêng</span>${k.sw("bg")}</div>
          <div class="fr">${k.chk("vGrid")}<span class="grow">Lưới dọc</span>${k.sw("grid")}</div>
          <div class="fr">${k.chk("hGrid")}<span>Lưới ngang</span></div>
          <div class="fr">${k.chk("crosshairMagnet")}<span>Con trỏ bắt vào nến</span></div>
          <div class="fr">${k.chk("seconds")}<span>Hiện giây trên trục thời gian</span></div>`;
      };
      this.openPanel("Cài đặt biểu đồ", [["look", "Giao diện"]], render, {
        root: st,
        onChange: () => { this.saveChartStyle(); },
        onReset: (redraw) => { this.chartStyle = defaultChartStyle(); this.saveChartStyle(); this.chartStyleSheet(); void redraw; },
      });
    },

    saveChartStyle() {
      store.set("aurum.chartStyle", JSON.stringify(this.chartStyle));
      applyTheme(this.chartStyle.theme);
      this.applyChartStyle();
    },

    applyChartStyle() {
      if (!this.chart) return;
      const st = this.chartStyle, light = document.documentElement.dataset.theme === "light";
      const bg = st.customBg ? st.bg : (light ? "#ffffff" : "#151c2a");
      const grid = light && st.grid === "#1a2233" ? "#eef0f4" : st.grid;
      this.chart.applyOptions({
        layout: { background: { color: bg }, textColor: light ? "#4b5563" : "#8b95a7" },
        grid: { vertLines: { color: grid, visible: st.vGrid }, horzLines: { color: grid, visible: st.hGrid } },
        rightPriceScale: { borderColor: light ? "#d6dae1" : "#222c3d" },
        timeScale: { borderColor: light ? "#d6dae1" : "#222c3d", secondsVisible: st.seconds || isSecTF(this.interval) },
        crosshair: { mode: st.crosshairMagnet ? 1 : 0 },
      });
      const candles = {
        upColor: st.up, downColor: st.down, wickUpColor: st.wickUp, wickDownColor: st.wickDown,
        borderVisible: st.border, borderUpColor: st.borderUp, borderDownColor: st.borderDown,
      };
      this.series.applyOptions(candles);
      if (this.chart2) {
        this.chart2.applyOptions({
          layout: { background: { color: bg }, textColor: light ? "#4b5563" : "#8b95a7" },
          grid: { vertLines: { color: grid, visible: st.vGrid }, horzLines: { color: grid, visible: st.hGrid } },
          rightPriceScale: { borderColor: light ? "#d6dae1" : "#222c3d" }, timeScale: { borderColor: light ? "#d6dae1" : "#222c3d" },
        });
        this.series2.applyOptions(candles);
      }
    },

    /* ----- favourite drawing tools: a floating bar on the chart ----- */

    favorites() { try { return JSON.parse(store.get("aurum.favTools") || "[]"); } catch { return []; } },

    toggleFavorite(tool) {
      const fav = this.favorites();
      const i = fav.indexOf(tool);
      if (i >= 0) fav.splice(i, 1); else fav.push(tool);
      store.set("aurum.favTools", JSON.stringify(fav));
      this.renderFavBar();
    },

    renderFavBar() {
      const bar = $("favBar");
      if (!bar || !this.drawings) return;
      const fav = this.favorites().filter((t) => window.AurumDrawings.tools[t]);
      bar.hidden = !fav.length;
      if (!fav.length) return;
      const d = this.drawings;
      bar.innerHTML = `<span class="grip" title="Kéo để di chuyển">⋮⋮</span>` + fav.map((t) => `<button type="button" data-t="${t}" class="${d.tool === t ? "on" : ""}" title="${esc(window.AurumDrawings.tools[t].name)}">${TOOL_ICON[t] || ""}</button>`).join("");
      bar.querySelectorAll("button").forEach((b) => (b.onclick = (e) => { e.stopPropagation(); d.setTool(d.tool === b.dataset.t ? null : b.dataset.t); }));
      let pos = null;
      try { pos = JSON.parse(store.get("aurum.favPos") || "null"); } catch { /* default */ }
      if (pos) { bar.style.left = pos.x + "px"; bar.style.top = pos.y + "px"; }
      bar.querySelector(".grip").onpointerdown = (e) => {
        e.preventDefault(); e.stopPropagation();
        const wrap = $("chartWrap").getBoundingClientRect(), r = bar.getBoundingClientRect();
        const dx = e.clientX - r.left, dy = e.clientY - r.top;
        const move = (ev) => {
          const x = Math.max(0, Math.min(wrap.width - r.width, ev.clientX - wrap.left - dx)), y = Math.max(0, Math.min(wrap.height - r.height, ev.clientY - wrap.top - dy));
          bar.style.left = x + "px"; bar.style.top = y + "px";
          store.set("aurum.favPos", JSON.stringify({ x, y }));
        };
        const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
        window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
      };
    },

    /* ----- standard indicators (EMA, Bollinger, RSI, MACD…) ----- */

    loadStudies() {
      try { this.studies = JSON.parse(store.get("aurum.studies") || "null"); } catch { this.studies = null; }
      if (!Array.isArray(this.studies)) this.studies = [];
      this.studies = this.studies.filter((x) => window.TA && window.TA.STUDIES[x.type]);
    },

    saveStudies() {
      store.set("aurum.studies", JSON.stringify(this.studies));
      this.applyStudies();
    },

    addStudy(type) {
      const def = window.TA.STUDIES[type];
      const study = { id: Math.random().toString(36).slice(2, 8), type, params: Object.assign({}, def.params), colors: def.colors.slice(), hidden: false };
      this.studies.push(study);
      this.saveStudies();
      return study;
    },

    removeStudy(id) {
      this.dropStudySeries(id);
      this.studies = this.studies.filter((x) => x.id !== id);
      this.saveStudies();
    },

    dropStudySeries(id) {
      const list = this.studySeries && this.studySeries.get(id);
      if (!list) return;
      list.forEach((x) => { try { this.chart.removeSeries(x); } catch { /* gone */ } });
      this.studySeries.delete(id);
    },

    studyLabel(x) {
      const def = window.TA.STUDIES[x.type];
      const nums = Object.entries(x.params).filter(([k, v]) => typeof v === "number" && !["upper", "lower"].includes(k)).map(([, v]) => v);
      return def.name.split(" (")[0] + (nums.length ? " " + nums.join(" ") : "");
    },

    /** Overlays on the price, oscillators in bands under it (each with its own scale). */
    applyStudies() {
      if (!this.chart || !window.TA || !this.studies) return;
      this.studySeries = this.studySeries || new Map();
      const bars = this.viewBars();
      const shownStudies = this.studies.filter((x) => !x.hidden);
      for (const id of [...this.studySeries.keys()]) if (!shownStudies.some((x) => x.id === id)) this.dropStudySeries(id);
      const oscs = shownStudies.filter((x) => !window.TA.STUDIES[x.type].overlay);
      const h = oscs.length ? Math.min(0.22, 0.6 / oscs.length) : 0;
      this.chart.priceScale("right").applyOptions({ scaleMargins: { top: 0.06, bottom: oscs.length * h + 0.04 } });
      shownStudies.forEach((x) => {
        const def = window.TA.STUDIES[x.type];
        let outs;
        try { outs = window.TA.compute(x.type, bars, x.params, x.colors, TZ); } catch { return; }
        let list = this.studySeries.get(x.id);
        if (!list || list.length !== outs.length || x.dirty) {
          this.dropStudySeries(x.id);
          x.dirty = false;
          list = outs.map((o, i) => {
            const scaleId = def.overlay ? (o.bottom ? "vol_" + x.id : "right") : "osc_" + x.id;
            const base = { priceScaleId: scaleId, priceLineVisible: false, lastValueVisible: !def.overlay || i === 0, title: i === 0 ? this.studyLabel(x) : "" };
            const series = o.kind === "hist"
              ? this.chart.addHistogramSeries(Object.assign(base, { priceFormat: o.bottom ? { type: "volume" } : { type: "price", precision: 2, minMove: 0.01 }, lastValueVisible: !o.bottom }))
              : this.chart.addLineSeries(Object.assign(base, { color: o.color, lineWidth: o.width || 1.5, crosshairMarkerVisible: false }));
            (o.levels || []).forEach((lv) => series.createPriceLine({ price: lv, color: "#787b86", lineStyle: 2, lineWidth: 1, axisLabelVisible: false }));
            return series;
          });
          this.studySeries.set(x.id, list);
        }
        outs.forEach((o, i) => {
          const data = o.values.map((v, k) => (v == null || !bars[k] ? { time: bars[k].time + TZ } : o.kind === "hist"
            ? { time: bars[k].time + TZ, value: v, color: o.colorOf ? o.colorOf(k) : o.color }
            : { time: bars[k].time + TZ, value: v }));
          list[i].setData(data);
          if (o.kind !== "hist") list[i].applyOptions({ color: o.color });
        });
      });
      // Bands from the bottom up, in the order they were added; volume sits right above them.
      oscs.forEach((x, j) => {
        try { this.chart.priceScale("osc_" + x.id).applyOptions({ scaleMargins: { top: 1 - (j + 1) * h + 0.02, bottom: j * h + 0.005 } }); } catch { /* not created */ }
      });
      shownStudies.filter((x) => x.type === "volume").forEach((x) => {
        try { this.chart.priceScale("vol_" + x.id).applyOptions({ scaleMargins: { top: 1 - oscs.length * h - 0.16, bottom: oscs.length * h + 0.005 } }); } catch { /* not created */ }
      });
    },

    studySettings(x) {
      const def = window.TA.STUDIES[x.type];
      const before = JSON.stringify({ params: x.params, colors: x.colors });
      const render = () => {
        const k = fieldKit(x);
        const names = { length: "Độ dài", source: "Nguồn", mult: "Hệ số", upper: "Mức trên", lower: "Mức dưới", fast: "Nhanh", slow: "Chậm", signal: "Tín hiệu", k: "%K", d: "%D", smooth: "Làm mượt" };
        return `<div class="fp-sec">Đầu vào</div>` + Object.keys(x.params).map((p) => p === "source"
          ? k.sel("params.source", names.source, [["close", "Đóng cửa"], ["open", "Mở cửa"], ["high", "Cao"], ["low", "Thấp"], ["hl2", "(H+L)/2"], ["hlc3", "(H+L+C)/3"]])
          : k.numf("params." + p, names[p] || p, p === "mult" ? 0.1 : 1)).join("")
          + `<div class="fp-sec">Màu</div>` + x.colors.map((c, i) => k.color("colors." + i, ["Đường chính", "Đường 2", "Đường 3"][i] || "Màu " + (i + 1))).join("");
      };
      this.openPanel(def.name, [["inputs", "Cài đặt"]], render, {
        root: x,
        onChange: () => this.saveStudies(),
        onCancel: () => { Object.assign(x, JSON.parse(before)); this.saveStudies(); },
        onReset: (redraw) => { x.params = Object.assign({}, def.params); x.colors = def.colors.slice(); this.saveStudies(); redraw(); },
      });
    },

    /* ----- ICT layer ----- */

    computeICT() {
      this.ictTime = Date.now();
      const allowed = this.owner || this.features.killzones !== false;
      const bars = this.viewBars();
      // Shark bubbles with the money flow (same switch as its two lines).
      const flowAllowed = this.owner || this.features.sharkflow !== false;
      const flow = flowAllowed && showInd.flow && window.ICT && bars.length ? window.ICT.sharkFlow(bars) : null;
      this.sharks = flow ? flow.sharks : null;
      if (!allowed || !bars.length || !window.ICT || !this.ictCfg) { this.ict = null; this.redraw(); return; }
      try {
        this.ict = window.ICT.compute(bars, TF_SECONDS[this.interval], this.ictCfg, showInd);
      } catch { this.ict = null; }
      if (this.cmpBars && this.cmpBars.length) this.showCmp(false); else this.computeSMT();
      this.applyStudies();
      this.redraw();
    },

    /** "mm:ss" (or "h:mm:ss") until the current bar closes. */
    countdownText() {
      const b = this.bars[this.bars.length - 1];
      if (!b) return "";
      const left = Math.max(0, Math.round(b.time + TF_SECONDS[this.interval] - Date.now() / 1000));
      const h = Math.floor(left / 3600), m = Math.floor((left % 3600) / 60), sec = left % 60;
      const two = (v) => String(v).padStart(2, "0");
      return h ? `${h}:${two(m)}:${two(sec)}` : `${two(m)}:${two(sec)}`;
    },

    /* ----- layout: one chart, or two side by side / stacked with SMT ----- */

    layoutMenu(button) {
      const r = button.getBoundingClientRect();
      const items = [["1", "▭ 1 biểu đồ"], ["h", "◫ 2 biểu đồ ngang"], ["v", "⊟ 2 biểu đồ dọc"]].map(([k, n]) => [k, (this.layout === k ? "✓ " : "　") + n]);
      items.push(["smt", (showInd.smt ? "✓ " : "　") + "SMT (so đỉnh/đáy với mã thứ 2)"]);
      if (this.owner) items.push(["cmp", `　Mã so sánh: ${this.cmpSymbol()}…`]);
      const menu = $("ctxMenu");
      menu.innerHTML = items.map(([k, t]) => `<button type="button" data-k="${k}">${esc(t)}</button>`).join("");
      menu.hidden = false;
      menu.style.left = Math.max(8, Math.min(r.left, window.innerWidth - menu.offsetWidth - 8)) + "px";
      menu.style.top = r.bottom + 6 + "px";
      menu.querySelectorAll("button").forEach((b) => (b.onclick = () => {
        this.closeMenu();
        const k = b.dataset.k;
        if (k === "smt") { showInd.smt = !showInd.smt; store.set("aurum.ind", JSON.stringify(showInd)); this.loadCmp(); return; }
        if (k === "cmp") { this.pickCmp(); return; }
        this.setLayout(k);
      }));
    },

    setLayout(mode) {
      this.layout = mode;
      store.set("aurum.layout", mode);
      $("charts").className = "charts" + (mode === "h" ? " row" : mode === "v" ? " col" : "");
      $("chartWrap2").hidden = mode === "1";
      $("layoutBtn").classList.toggle("on", mode !== "1");
      if (mode === "1") { this.focusChart(1); this.loadCmp(); return; }
      this.ensureChart2();
      this.loadCmp();
    },

    pickCmp() {
      this.symbolSheet((sym) => { this.ictCfg.smtSymbol = sym; this.saveIct(); this.loadCmp(); });
    },

    /** The second chart's symbol: silver for gold (the SMT pair), or the one picked. */
    cmpSymbol() {
      if (!this.owner) return "XAG";
      const sym = this.symbol || "XAUUSD";
      return (this.ictCfg && this.ictCfg.smtSymbol) || (/XAU/i.test(sym) ? sym.replace(/XAU/i, "XAG") : /BTC/i.test(sym) ? sym.replace(/BTC/i, "ETH") : sym);
    },

    ensureChart2() {
      if (this.chart2) return;
      const term = this;
      this.chart2 = LightweightCharts.createChart($("chart2"), {
        autoSize: true,
        layout: { background: { color: "#151c2a" }, textColor: "#8b95a7", fontFamily: "-apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif" },
        rightPriceScale: { borderColor: "#222c3d" },
        timeScale: { borderColor: "#222c3d", timeVisible: true, secondsVisible: isSecTF(this.interval), rightOffset: 8 },
        localization: { timeFormatter: (t) => this.timeLabel(t) },
        crosshair: { mode: 0 },
      });
      this.series2 = this.chart2.addCandlestickSeries({ borderVisible: false });
      // SMT on the second chart too, at that market's highs and lows.
      this.series2.attachPrimitive({
        attached(p) { term.request2 = p.requestUpdate; }, detached() {}, updateAllViews() {},
        paneViews() {
          return [{ zOrder: () => "top", renderer: () => ({ draw: (target) => target.useMediaCoordinateSpace(({ context, mediaSize }) => {
            if (!term.smt || !term.cmpView) return;
            const index = new Map(term.cmpView.map((b, i) => [b.time, i]));
            const list = term.smt.map((d) => {
              const i1 = index.get(d.t1), i2 = index.get(d.t2);
              if (i1 == null || i2 == null) return null;
              const a = term.cmpView[i1], b = term.cmpView[i2];
              return { bull: d.bull, start: i1, end: i2, p1: d.bull ? a.low : a.high, p2: d.bull ? b.low : b.high };
            }).filter(Boolean);
            const ts = term.chart2.timeScale();
            window.ICT.drawSMT(context, list, (i) => ts.logicalToCoordinate(i), (v) => term.series2.priceToCoordinate(v), mediaSize.width, { bull: term.ictCfg.smtBull, bear: term.ictCfg.smtBear });
          }) }) }];
        },
      });
      // Dragging either chart moves both.
      const link = (from, to) => from.timeScale().subscribeVisibleLogicalRangeChange((r) => {
        if (!r || this.layout === "1") return;
        const locked = this.rangeLock && this.rangeLock.get(from);
        if (locked && performance.now() - locked < 120) return; // our own echo
        this.syncRange(from, to);
        // Scrolled back past the second chart's oldest bar: fetch older bars for it.
        if (from === this.chart2 && r.from < 30) this.loadOlderCmp();
      });
      link(this.chart, this.chart2);
      link(this.chart2, this.chart);
      // One crosshair across both charts: the same moment on each.
      const follow = (from, to, toSeries, bars) => from.subscribeCrosshairMove((param) => {
        if (this.syncingCrosshair || this.layout === "1") return;
        this.syncingCrosshair = true;
        try {
          if (!param || param.time == null || !param.point) to.clearCrosshairPosition();
          else {
            const t = param.time - TZ, list = bars();
            let i = list.length - 1;
            while (i > 0 && list[i].time > t) i--;
            if (list[i]) to.setCrosshairPosition(list[i].close, list[i].time + TZ, toSeries);
          }
        } catch { /* nothing to show */ }
        this.syncingCrosshair = false;
      });
      follow(this.chart, this.chart2, this.series2, () => this.cmpView || []);
      follow(this.chart2, this.chart, this.series, () => this.viewBars());
      // Drawings on the second chart too, kept per symbol like the first one's.
      this.drawings2 = new window.AurumDrawings({
        chart: this.chart2, series: this.series2, store,
        bars: () => this.cmpView || [], sec: () => TF_SECONDS[this.interval], digits: () => this.cmpDigits || 2,
        symbol: () => this.cmpName || "XAG", magnet: () => this.magnet, onChange: () => this.renderDrawBar(),
        interval: () => this.interval, onEdit: (d, isNew) => this.drawingSettings(d, isNew),
      });
      this.drawingsMain.link([this.drawings2]);
      this.drawings2.link([this.drawingsMain]);
      this.drawings2.keepTool = this.drawingsMain.keepTool;
      this.drawings2.lockAll = this.drawingsMain.lockAll;
      this.bindDrag2();
      this.applyChartStyle();
    },

    /** Lines of open positions on the second chart's symbol (to edit them, swap the charts). */
    syncLines2() {
      if (!this.series2) return;
      this.lines2 = this.lines2 || new Map();
      const wanted = [];
      if (this.owner && this.layout !== "1" && !this.replay) {
        this.positions.filter((p) => p.symbol === this.cmpName).forEach((p) => {
          wanted.push({ key: `p:${p.ticket}:e`, price: p.entry, color: p.side === "long" ? "#2b6bf3" : "#f0455a", lineStyle: 0, title: `${sideName(p.side)} ${p.lots} ${signed(p.profit)}` });
          if (p.stop) wanted.push({ key: `p:${p.ticket}:s`, price: p.stop, color: "#f0455a", lineStyle: 2, title: "SL" });
          if (p.target) wanted.push({ key: `p:${p.ticket}:t`, price: p.target, color: "#14b88a", lineStyle: 2, title: "TP" });
        });
        this.orders.filter((o) => o.symbol === this.cmpName).forEach((o) => {
          wanted.push({ key: `o:${o.ticket}:e`, price: o.entry, color: o.side === "long" ? "#2b6bf3" : "#f0455a", lineStyle: 1, title: `${sideName(o.side)} ${o.kind.toUpperCase()} ${o.lots}` });
        });
      }
      const keys = new Set(wanted.map((w) => w.key));
      wanted.forEach((w) => {
        const opts = { price: w.price, color: w.color, lineWidth: 1, lineStyle: w.lineStyle, axisLabelVisible: true, title: w.title };
        const line = this.lines2.get(w.key);
        if (line) line.applyOptions(opts); else this.lines2.set(w.key, this.series2.createPriceLine(opts));
      });
      for (const [k, line] of this.lines2) if (!keys.has(k)) { this.series2.removePriceLine(line); this.lines2.delete(k); }
    },

    /** Drawing on the second chart (its trade lines are read-only). */
    bindDrag2() {
      const wrap = $("chartWrap2");
      const rel = (e) => { const r = wrap.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
      const lock = (on) => {
        this.chart2.applyOptions({ handleScroll: !on, handleScale: !on });
        const ps = this.chart2.priceScale("right");
        if (on) { this.scale2WasAuto = ps.options().autoScale; ps.applyOptions({ autoScale: false }); } else if (this.scale2WasAuto) ps.applyOptions({ autoScale: true });
      };
      let gesture = false;
      wrap.addEventListener("pointerdown", (e) => {
        this.closeMenu();
        this.focusChart(2);
        if (e.button > 0 || e.target.closest("#ticket2, .c2-head, #drawBar")) return;
        const { x, y } = rel(e);
        if (x > this.chart2.timeScale().width()) return;
        const r = this.drawings2.down(x, y, e);
        if (r === true) { gesture = true; lock(true); e.stopPropagation(); }
      }, true);
      ["mousedown", "touchstart"].forEach((t) => wrap.addEventListener(t, (e) => { if (gesture) e.stopPropagation(); }, { capture: true, passive: true }));
      wrap.addEventListener("touchmove", (e) => { if (gesture) e.preventDefault(); }, { passive: false });
      wrap.addEventListener("pointermove", (e) => {
        if (gesture) return;
        const { x, y } = rel(e);
        if (this.drawings2.pending) { this.drawings2.move(x, y); return; }
        if (e.pointerType === "mouse") wrap.style.cursor = this.drawings2.tool ? "crosshair" : x <= this.chart2.timeScale().width() && this.drawings2.hitTest(x, y, 8) ? "move" : "";
      });
      window.addEventListener("pointermove", (e) => { if (gesture) { const { x, y } = rel(e); this.drawings2.move(x, y); } });
      const end = () => { if (!gesture) return; gesture = false; lock(false); this.drawings2.up(); };
      window.addEventListener("pointerup", end);
      window.addEventListener("pointercancel", end);
      wrap.addEventListener("dblclick", () => { if (this.drawings2.current) this.drawingSettings(this.drawings2.current); });
      wrap.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        if (this.drawings2.pending) { this.drawings2.cancel(); return; }
        const items = [["reset", "⟲ Đặt lại biểu đồ"], ["tools", "✎ Công cụ vẽ…"]];
        if (this.drawings2.current) items.push(["drawSettings", "⚙ Cài đặt bản vẽ…"]);
        if (this.drawings2.list.length) items.push(["clear", `🗑 Xoá tất cả bản vẽ (${this.drawings2.list.length})`]);
        if (this.owner && this.cmpLive) items.push(["swap", "⇄ Đổi chỗ 2 biểu đồ"]);
        const menu = $("ctxMenu");
        menu.innerHTML = items.map(([k, t]) => `<button type="button" data-k="${k}">${esc(t)}</button>`).join("");
        menu.hidden = false;
        menu.style.left = Math.max(8, Math.min(e.clientX, window.innerWidth - menu.offsetWidth - 8)) + "px";
        menu.style.top = Math.max(8, Math.min(e.clientY, window.innerHeight - menu.offsetHeight - 8)) + "px";
        menu.querySelectorAll("button").forEach((b) => (b.onclick = () => {
          this.closeMenu();
          const k = b.dataset.k;
          if (k === "reset") { const ts = this.chart2.timeScale(); ts.resetTimeScale(); this.chart2.priceScale("right").applyOptions({ autoScale: true }); ts.scrollToRealTime(); }
          if (k === "tools") this.drawSheet();
          if (k === "drawSettings") this.drawingSettings(this.drawings2.current);
          if (k === "clear" && confirm("Xoá tất cả bản vẽ trên " + this.cmpName + "?")) this.drawings2.clear();
          if (k === "swap") $("swapBtn").click();
        }));
      });
    },

    /** The chart last touched: its drawing is the one the bar and settings edit. */
    focusChart(n) {
      const next = n === 2 && this.drawings2 ? this.drawings2 : this.drawingsMain;
      $("chartWrap").classList.toggle("focus", n === 1 && this.layout !== "1");
      $("chartWrap2").classList.toggle("focus", n === 2);
      // The drawing bar sits on the chart being edited.
      const wrap = n === 2 && this.drawings2 ? $("chartWrap2") : $("chartWrap");
      if ($("drawBar").parentElement !== wrap) wrap.appendChild($("drawBar"));
      if (this.drawings === next) return;
      this.drawings = next;
      this.renderDrawBar();
    },

    allDrawings() { return [this.drawingsMain, this.drawings2].filter(Boolean); },

    cmpPath(count, before) {
      const extra = before ? `&before=${before}` : "";
      return this.owner
        ? `/mt5/candles?symbol=${encodeURIComponent(this.cmpSymbol())}&interval=${this.interval}&count=${count}${extra}`
        : `/member/candles?symbol=compare&interval=${this.interval}&count=${count}${extra}`;
    },

    /** SMT is on (it needs the related market's bars even with one chart). */
    smtWanted() { return !!(this.layout !== "1" && showInd.smt && window.ICT && (this.owner || this.features.killzones !== false)); },

    async loadCmp() {
      const show2 = this.layout !== "1" && this.chart2;
      clearInterval(this.cmpTimer); this.cmpTimer = null;
      if (this.cmpFeed) { this.cmpFeed.close(); this.cmpFeed = null; }
      if (!show2 && !this.smtWanted()) { this.cmpBars = []; this.cmpView = null; this.computeSMT(); return; }
      const token = (this.cmpToken = (this.cmpToken || 0) + 1);
      let name = this.cmpSymbol(), digits = 2, live = false, quote = {}, bars = [], feed = null;
      if (isSecTF(this.interval)) {
        // Second bars of the related market from Binance as well.
        const market = binanceMarket(name);
        if (market) {
          feed = new SecondFeed(market, TF_SECONDS[this.interval]);
          try { await feed.history(Math.max(240, Math.round(3600 / feed.sec))); } catch { feed = null; }
        }
        if (token !== this.cmpToken) { if (feed) feed.close(); return; }
        bars = feed ? feed.bars : [];
        if (feed) { name = market.name; digits = market.digits; }
      } else try {
        if (this.source !== "exness") throw new Error("binance");
        const data = await this.call(this.cmpPath(800));
        bars = this.toBars(data.candles || []);
        if (bars.length < 5) throw new Error("no bars");
        // An older member server ignores "compare" and answers gold: that cannot give an SMT.
        if (!this.owner && data.symbol && data.symbol === $("chartSymbol").textContent) throw new Error("old server");
        name = data.symbol || name; digits = data.digits != null ? data.digits : 2;
        quote = { bid: data.bid, ask: data.ask };
        live = true;
      } catch {
        // Binance silver as the stand-in (member servers before 2.6, or no MT5).
        try {
          const res = await fetch(`https://fapi.binance.com/fapi/v1/klines?symbol=XAGUSDT&interval=${this.interval}&limit=800`);
          bars = (await res.json()).map((r) => ({ time: r[0] / 1000, open: +r[1], high: +r[2], low: +r[3], close: +r[4], volume: +r[5] }));
          name = "XAGUSDT"; digits = 3;
        } catch { bars = []; }
      }
      if (token !== this.cmpToken) return;
      this.cmpBars = bars; this.cmpQuote = quote; this.cmpLive = live; this.cmpView = null; this.cmpNoOlder = false;
      this.cmpName = name; this.cmpDigits = digits;
      if (live) this.cmpTimer = setInterval(() => this.pollCmp(token), 2000);
      if (feed) {
        this.cmpFeed = feed;
        let shownAt = 0;
        feed.live((added) => {
          if (token !== this.cmpToken || this.replay || (!added && performance.now() - shownAt < 250)) return;
          shownAt = performance.now();
          this.showCmp(false);
        });
      }
      $("chartSymbol2").textContent = name;
      $("ticket2").hidden = !this.owner || !live;
      $("swapBtn").hidden = !this.owner || !live;
      if (this.drawings2 && this.drawKey2 !== name) { this.drawKey2 = name; this.drawings2.load(); }
      if (this.series2) this.series2.applyOptions({ priceFormat: { type: "price", precision: digits, minMove: Math.pow(10, -digits) } });
      this.showCmp(true);
    },

    async pollCmp(token) {
      try {
        const data = await this.call(this.cmpPath(3));
        const fresh = this.toBars(data.candles || []);
        if (token !== this.cmpToken) return;
        this.cmpQuote = { bid: data.bid, ask: data.ask };
        fresh.forEach((b) => {
          const last = this.cmpBars[this.cmpBars.length - 1];
          if (!last || b.time > last.time) this.cmpBars.push(b); else if (b.time === last.time) this.cmpBars[this.cmpBars.length - 1] = b;
        });
        this.showCmp(false);
      } catch { /* keep */ }
    },

    /** The related market up to the replay moment; drawn on the second chart when it is shown. */
    showCmp(full) {
      const until = this.replay ? this.bars[this.replay.idx].time + TF_SECONDS[this.interval] - 1 : Infinity;
      const view = (this.cmpBars || []).filter((b) => b.time <= until);
      const changed = full || !this.cmpView || view.length !== this.cmpView.length || this.replay;
      this.cmpView = view;
      if (this.series2 && this.layout !== "1") {
        if (changed) this.series2.setData(view.map(shown)); else if (view.length) this.series2.update(shown(view[view.length - 1]));
        const last = view[view.length - 1];
        const q = this.cmpQuote || {}, d2 = this.cmpDigits || 2;
        $("chartPrice2").textContent = last ? fmt(q.bid != null && !this.replay ? q.bid : last.close, d2) : "";
        $("bidText2").textContent = q.bid != null ? fmt(q.bid, d2) : "—";
        $("askText2").textContent = q.ask != null ? fmt(q.ask, d2) : "—";
        $("spread2").textContent = spreadText(q.bid, q.ask, d2);
        this.syncLines2();
        if (full) {
          // A new symbol: its own price range, and the first chart's time span — again once the
          // second chart has its size (it is just being shown), or it keeps the start of its bars.
          this.chart2.priceScale("right").applyOptions({ autoScale: true });
          this.syncRange(this.chart, this.chart2);
          requestAnimationFrame(() => this.syncRange(this.chart, this.chart2));
          setTimeout(() => this.syncRange(this.chart, this.chart2), 250);
        }
      }
      this.computeSMT();
    },

    computeSMT() {
      const on = this.smtWanted() && this.cmpView && this.cmpView.length;
      const c = this.ictCfg || {};
      this.smt = on ? window.ICT.smt(this.viewBars(), this.cmpView, { swing: c.smtSwing, lookback: c.smtLookback, count: c.smtCount, inverse: c.smtInverse }) : null;
      if (this.requestICT) this.requestICT();
      if (this.request2) this.request2();
    },

    /** Shows the same time span on `to` as on `from`; the lock keeps the two from echoing each other. */
    syncRange(from, to) {
      if (!from || !to || this.layout === "1") return;
      const r = from.timeScale().getVisibleLogicalRange();
      const fromBars = from === this.chart ? this.viewBars() : this.cmpView || [];
      const toBars = to === this.chart ? this.viewBars() : this.cmpView || [];
      if (!r || !fromBars.length || !toBars.length) return;
      // The same moments at each edge, through each chart's own bars: equal zoom and no jump to the start.
      const sec = TF_SECONDS[this.interval];
      const a = timeToIndex(toBars, indexToTime(fromBars, r.from, sec), sec);
      const b = timeToIndex(toBars, indexToTime(fromBars, r.to, sec), sec);
      if (a == null || b == null || !(b > a)) return;
      this.rangeLock = this.rangeLock || new Map();
      this.rangeLock.set(to, performance.now());
      try { to.timeScale().setVisibleLogicalRange({ from: a, to: b }); } catch { /* not loaded yet */ }
    },

    /** Older bars of the second chart, so it covers what the first one shows. */
    async loadOlderCmp() {
      if (this.cmpFeed) {
        const feed = this.cmpFeed;
        if (await feed.older() && feed === this.cmpFeed) { this.cmpBars = feed.bars; this.showCmp(true); }
        return;
      }
      if (this.cmpOlderBusy || !this.cmpLive || !this.cmpBars || !this.cmpBars.length || this.cmpNoOlder) return;
      this.cmpOlderBusy = true;
      const token = this.cmpToken;
      try {
        const data = await this.call(this.cmpPath(800, this.cmpBars[0].time));
        if (token !== this.cmpToken) return;
        const older = this.toBars(data.candles || []).filter((b) => b.time < this.cmpBars[0].time);
        if (!older.length) { this.cmpNoOlder = true; return; }
        this.cmpBars = older.concat(this.cmpBars);
        this.showCmp(true);
      } catch { this.cmpNoOlder = true; } finally { this.cmpOlderBusy = false; }
    },

    /** The indicator and drawing layers paint inside the chart's own frame; this only asks for one. */
    redraw() {
      if (this.requestICT) this.requestICT();
      if (this.drawings) this.drawings.update();
    },

    /* ----- money flow / news flash above the chart ----- */

    updateFlow() {
      const box = $("flowBox");
      const nowS = Date.now() / 1000;
      // A red USD release in the last minute takes the place of the money flow.
      const fresh = this.replay ? null : this.goldEvents(3).find((e) => e.time <= nowS && nowS - e.time < 60);
      if (fresh && this.bars.length) {
        const i = this.bars.findIndex((b) => b.time + TF_SECONDS[this.interval] > fresh.time);
        const ref = i >= 0 ? this.bars[i].open : null;
        const price = this.bid != null ? this.bid : this.bars[this.bars.length - 1].close;
        const v = this.verdict(ref != null ? price - ref : null, price);
        box.hidden = false;
        box.innerHTML = `<div>📰 <b>${esc(fresh.title)}</b> <span class="muted">${Math.round(60 - (nowS - fresh.time))}s</span></div><div class="${v.cls}"><b>${v.text}</b></div>`;
        return;
      }
      const allowed = this.owner || this.features.sharkflow !== false;
      const f = allowed && showInd.flow && window.ICT ? window.ICT.sharkFlow(this.viewBars()) : null;
      if (!f) { box.hidden = true; return; }
      const pct = (f.flow >= 0 ? "+" : "") + Math.round(f.flow * 100) + "%";
      const verdict = f.flow >= 0.25 ? ["Tiền VÀO mạnh", "pos"] : f.flow >= 0.08 ? ["Tiền đang vào", "pos"] : f.flow > -0.08 ? ["Tiền cân bằng", "muted"] : f.flow > -0.25 ? ["Tiền đang ra", "neg"] : ["Tiền RA mạnh", "neg"];
      const advice = {
        strongUp: ["Giá tăng + tiền vào → xu hướng tăng khoẻ, ưu tiên MUA", "pos"],
        weakUp: ["⚠️ Giá tăng nhưng tiền RA → tăng yếu, dễ đảo chiều giảm", "warn-t"],
        strongDown: ["Giá giảm + tiền ra → xu hướng giảm khoẻ, ưu tiên BÁN", "neg"],
        weakDown: ["⚠️ Giá giảm nhưng tiền VÀO → có người gom hàng, dễ bật tăng", "warn-t"],
        flat: ["Giá đi ngang → chờ dòng tiền chọn hướng", "muted"],
      }[f.situation];
      box.hidden = false;
      box.innerHTML = `<div>🦈 Dòng tiền <b class="${verdict[1]}">${verdict[0]} ${pct}</b>${f.shark ? ` <span class="${f.shark.buying ? "pos" : "neg"}">· cá mập ${f.shark.buying ? "MUA" : "BÁN"} ×${f.shark.ratio.toFixed(1)}</span>` : ""}</div><div class="${advice[1]}">${advice[0]}</div>`;
    },
  };

  /** The server answered "no such path": it predates the feature. */
  function ServerTooOld(e) { return /Không có đường dẫn/.test(e.message || ""); }

  Member.init();
  $("themeBtn").addEventListener("click", () => {
    const st = loadChartStyle();
    st.theme = document.documentElement.dataset.theme === "light" ? "dark" : "light";
    store.set("aurum.chartStyle", JSON.stringify(st));
    applyTheme(st.theme);
    if (Member.chart) { Member.chartStyle = st; Member.applyChartStyle(); }
  });
  if (/[?&]debug\b/.test(location.search)) window.__aurum = Member; // for automated tests
  $("loginForm").addEventListener("submit", (e) => { e.preventDefault(); Member.login(); });
  $("modeBtn").addEventListener("click", () => Member.setLoginMode(Member.loginMode === "owner" ? "member" : "owner"));
  $("logoutBtn").addEventListener("click", () => Member.logout());
  $("alertBtn").addEventListener("click", () => Member.voiceSheet());
  Member.bindPill();
  $("addMemberBtn").addEventListener("click", () => Member.memberSheet(null));
  route();
})();
