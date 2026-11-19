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
  // Formatters made once: toLocaleString builds one per call, too slow for labels drawn every frame.
  const CLOCK_TIME = new Intl.DateTimeFormat("vi-VN", { hour: "2-digit", minute: "2-digit" });
  const CLOCK_DAY = new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  const clock = (t) => {
    const date = new Date(t * 1000), today = new Date();
    return date.toDateString() === today.toDateString() ? CLOCK_TIME.format(date) : CLOCK_DAY.format(date);
  };
  const fullTime = (t) => new Date(t * 1000).toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  /** "XAUUSDm" → "XAU/USD", "US30m" → "US30": the broker's suffix dropped, currency pairs split. */
  const symShort = (s) => {
    const base = String(s).replace(/[a-z.#_-]+$/, "");
    return /^[A-Z]{6}$/.test(base) ? `${base.slice(0, 3)}/${base.slice(3)}` : base || s;
  };
  /** A round badge for a symbol tab: gold, silver, crypto, indices and currencies by their sign. */
  const symIcon = (s) => {
    const u = String(s).toUpperCase();
    const known = [[/XAU|GOLD/, "#d4a017", "Au"], [/XAG|SILVER/, "#8e99a8", "Ag"], [/^BTC/, "#f7931a", "₿"], [/^ETH/, "#627eea", "Ξ"],
      [/^SOL/, "#9945ff", "◎"], [/^BNB/, "#f0b90b", "B"], [/^XRP/, "#3b4252", "X"], [/^DOGE/, "#c2a633", "Ð"], [/^LTC/, "#345d9d", "Ł"],
      [/^(US30|DJ)/, "#2b6bf3", "DJ"], [/^(USTEC|NAS|US100)/, "#14b88a", "NQ"], [/^(US500|SPX)/, "#e0565b", "SP"], [/^(DE30|DE40|GER)/, "#3b4252", "DE"],
      [/OIL|WTI|BRENT/, "#3b4252", "⛽"], [/^EUR/, "#2b6bf3", "€"], [/^GBP/, "#7b5cff", "£"], [/^USD/, "#14b88a", "$"], [/^AUD/, "#f2a93b", "A$"],
      [/^NZD/, "#22a3a3", "N$"], [/^CAD/, "#e0565b", "C$"], [/^CHF/, "#e0565b", "₣"], [/^JPY/, "#e0565b", "¥"]];
    const hit = known.find(([re]) => re.test(u));
    const hue = [...u].reduce((a, c) => (a * 31 + c.charCodeAt(0)) % 360, 7);
    const [color, text] = hit ? [hit[1], hit[2]] : [`hsl(${hue} 55% 45%)`, u.slice(0, 1)];
    return `<i class="sym-ico" style="background:${color}">${text}</i>`;
  };
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
    ["dm", "DM (nến không râu trên / dưới)"],
    ["news", "Tin tức trên biểu đồ (tin USD đỏ / cam, giờ ra tin)"],
    ["flow", "Dòng tiền cá mập"],
    ["zones", "Vùng cung / cầu cá mập (chờ mua / chờ bán, ghi giá)"],
    ["smt", "SMT (khi mở 2 biểu đồ: so đỉnh/đáy với mã thứ 2)"],
    ["macro", "Macro: giờ vàng biến động mạnh nhất mỗi phiên (giờ VN, tự đổi mùa, đếm ngược)"],
    ["liq", "Vùng thanh khoản mạnh / vừa (BSL / SSL: đỉnh đáy bằng, PDH / PDL, tuần, phiên, H1 / H4)"],
    ["plan", "Kế hoạch giao dịch (ngày → H4 → H1, trend 3 đỉnh / 3 đáy, breakout thật / giả, nến rút râu)"],
  ];
  const showInd = (() => {
    let saved = {};
    try { saved = JSON.parse(store.get("aurum.ind") || "{}"); } catch { /* default */ }
    // DM starts off; the others on.
    return Object.fromEntries(IND.map(([k]) => [k, k === "dm" ? saved[k] === true : saved[k] !== false]));
  })();

  const TFS = ["5s", "10s", "15s", "30s", "1m", "2m", "3m", "4m", "5m", "6m", "10m", "12m", "15m", "20m", "30m", "1h", "4h", "1d"];
  const TF_SECONDS = { "5s": 5, "10s": 10, "15s": 15, "30s": 30, "1m": 60, "2m": 120, "3m": 180, "4m": 240, "5m": 300, "6m": 360,
    "10m": 600, "12m": 720, "15m": 900, "20m": 1200, "30m": 1800, "1h": 3600, "4h": 14400, "1d": 86400 };
  // MT5's other minute charts: in a short list after 1m, so the row stays as it was.
  const TF_MORE = ["2m", "3m", "4m", "6m", "10m", "12m", "20m"];
  const isSecTF = (tf) => TF_SECONDS[tf] < 60;
  /** Binance has 1m, 3m, 5m… but not 2m, 4m, 6m, 10m, 12m or 20m: those are merged from its shorter klines. */
  const BINANCE_KLINE = { "2m": ["1m", 2], "4m": ["1m", 4], "6m": ["3m", 2], "10m": ["5m", 2], "12m": ["3m", 4], "20m": ["5m", 4] };
  const binanceKline = (tf) => BINANCE_KLINE[tf] || [tf, 1];
  /** Shorter klines merged into bars of `tf` (the first dropped when it starts in their middle). */
  function mergeKlines(bars, tf) {
    const [, factor] = binanceKline(tf);
    if (factor === 1) return bars;
    const sec = TF_SECONDS[tf], out = [];
    bars.forEach((b) => {
      const t = Math.floor(b.time / sec) * sec, last = out[out.length - 1];
      if (last && last.time === t) { last.high = Math.max(last.high, b.high); last.low = Math.min(last.low, b.low); last.close = b.close; last.volume += b.volume; }
      else out.push({ time: t, open: b.open, high: b.high, low: b.low, close: b.close, volume: b.volume });
    });
    if (out.length > 1 && bars.length && bars[0].time > out[0].time) out.shift();
    return out;
  }
  /** Recent Binance bars of `tf` (merged when Binance has no such kline). */
  async function binanceBars(rest, name, tf, limit) {
    const [kname, factor] = binanceKline(tf);
    const rows = await (await fetch(`${rest}?symbol=${name}&interval=${kname}&limit=${Math.min(1000, limit * factor)}`)).json();
    return mergeKlines(rows.map((r) => ({ time: r[0] / 1000, open: +r[1], high: +r[2], low: +r[3], close: +r[4], volume: +r[5] })), tf);
  }
  /** A live kline handler for bars of `tf`: each shorter kline into its bar (no minute counted twice). */
  function klineFolder(tf) {
    const [, factor] = binanceKline(tf), sec = TF_SECONDS[tf];
    let bucket = null, done = null, partTime = null, part = null;
    const merge = (a, b, t) => (a ? { time: t, open: a.open, high: Math.max(a.high, b.high), low: Math.min(a.low, b.low), close: b.close, volume: a.volume + b.volume }
      : { time: t, open: b.open, high: b.high, low: b.low, close: b.close, volume: b.volume });
    return (k, last) => {
      if (factor === 1) return k;
      const t = Math.floor(k.time / sec) * sec;
      if (bucket !== t) { bucket = t; done = last && last.time === t ? Object.assign({}, last) : null; partTime = null; part = null; }
      if (partTime != null && partTime !== k.time && part) done = merge(done, part, t);
      partTime = k.time; part = k;
      return merge(done, k, t);
    };
  }
  /** One chart; two symbols side by side / stacked; or the one symbol on 2, 3, 4 timeframes. */
  const LAYOUTS = ["1", "h", "v", "m2", "m3", "m4"];

  /* ----- second bars (5s / 10s / 15s) from Binance: MT5 has nothing under one minute ----- */

  /** The usual SMT pair of a symbol, with its broker prefix / suffix kept: XAUUSDm → XAGUSDm, USTEC → US500,
   *  BTCUSDT → ETHUSDT… null when it has none. */
  const SMT_PAIRS = {
    XAUUSD: "XAGUSD", XAGUSD: "XAUUSD", GOLD: "SILVER", SILVER: "GOLD", XAUUSDT: "XAGUSDT", XAGUSDT: "XAUUSDT",
    USTEC: "US500", NAS100: "SPX500", US100: "US500", NDX100: "SPX500", NQ: "ES",
    US500: "USTEC", SPX500: "NAS100", SP500: "NAS100", ES: "NQ",
    US30: "US500", DJ30: "SPX500", WS30: "SPX500", DOW30: "SPX500", YM: "ES",
    BTCUSD: "ETHUSD", ETHUSD: "BTCUSD", BTCUSDT: "ETHUSDT", ETHUSDT: "BTCUSDT",
    EURUSD: "GBPUSD", GBPUSD: "EURUSD", AUDUSD: "NZDUSD", NZDUSD: "AUDUSD",
    USOIL: "UKOIL", UKOIL: "USOIL", XTIUSD: "XBRUSD", XBRUSD: "XTIUSD", WTI: "BRENT", BRENT: "WTI",
  };
  function smtPair(symbol) {
    const m = String(symbol || "").match(/^([#.]?)([A-Z0-9]+)(.*)$/);
    if (!m) return null;
    const [, pre, base, rest] = m;
    if (SMT_PAIRS[base]) return pre + SMT_PAIRS[base] + rest;
    // OANDA style: NAS100_USD → SPX500_USD, XAU_USD → XAG_USD.
    const o = String(symbol).match(/^([A-Z0-9]+)_([A-Z]+)$/);
    if (o) {
      const pair = SMT_PAIRS[o[1] + o[2]] || SMT_PAIRS[o[1]];
      if (pair) return /USD$/.test(pair) && pair.length === 6 ? pair.slice(0, 3) + "_" + pair.slice(3) : pair + "_" + o[2];
    }
    return null;
  }

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

    /** One finished piece (a trade, or one 1-second candle) into its bar; true when it opened a new bar.
     *  Every trade counts (wicks included, for reading the bars); windows without a trade get a flat bar at
     *  the last close, so the bars run on without holes. */
    add(t, o, h, l, c, v, list) {
      const bars = list || this.bars, d = this.offset;
      const time = Math.floor(t / this.sec) * this.sec;
      let last = bars[bars.length - 1];
      if (last && time < last.time) return false;
      if (last && last.time === time) {
        last.high = Math.max(last.high, h + d); last.low = Math.min(last.low, l + d); last.close = c + d; last.volume += v;
        return false;
      }
      if (last) {
        // Quiet seconds: flat bars at the last close (a long pause, over 300 bars, is left as a gap).
        const missing = (time - last.time) / this.sec - 1;
        if (missing > 0 && missing <= 300) {
          for (let k = 1; k <= missing; k++) bars.push({ time: last.time + k * this.sec, open: last.close, high: last.close, low: last.close, close: last.close, volume: 0 });
          last = bars[bars.length - 1];
        }
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

    /** Live: `onBar(newBar)` after every trade / candle update. A stream that drops (network, the
     *  exchange's own cut, a sleeping tab) or goes quiet for 30 s is opened again, after the trades
     *  missed meanwhile are fetched, so the newest bar never stands still while the bid / ask move. */
    live(onBar) {
      this.onBar = onBar;
      this.stopped = false;
      this.connect();
      clearInterval(this.watch);
      this.watch = setInterval(() => {
        if (this.stopped) return;
        if (Date.now() - (this.heardAt || 0) > 30000 && this.ws) { try { this.ws.close(); } catch { /* gone */ } }
      }, 5000);
    }

    connect() {
      const m = this.market;
      const ws = new WebSocket(m.futures
        ? `wss://fstream.binance.com/ws/${m.name.toLowerCase()}@aggTrade`
        : `wss://stream.binance.com:9443/ws/${m.name.toLowerCase()}@kline_1s`);
      this.heardAt = Date.now();
      ws.onmessage = (ev) => {
        this.heardAt = Date.now();
        const x = JSON.parse(ev.data);
        if (m.futures) {
          if (x.a == null || x.a <= this.lastId) return;
          this.lastId = x.a;
          this.onBar(this.add(x.T / 1000, +x.p, +x.p, +x.p, +x.p, +x.q));
        } else if (x.k) {
          const k = x.k;
          this.onBar(this.addOpenSecond(k.t / 1000, +k.o, +k.h, +k.l, +k.c, +k.v));
        }
      };
      ws.onclose = () => {
        if (this.stopped || this.ws !== ws) return;
        this.ws = null;
        setTimeout(() => this.reconnect(), 1500);
      };
      ws.onerror = () => { try { ws.close(); } catch { /* closing */ } };
      this.ws = ws;
    }

    /** The trades (or 1-second candles) missed while the stream was down, then the stream again. */
    async reconnect() {
      if (this.stopped) return;
      try {
        const m = this.market;
        if (m.futures && this.lastId) {
          for (let k = 0; k < 5; k++) {
            const rows = await (await fetch(`https://fapi.binance.com/fapi/v1/aggTrades?symbol=${m.name}&fromId=${this.lastId + 1}&limit=1000`)).json();
            if (!Array.isArray(rows) || !rows.length) break;
            let added = false;
            rows.forEach((r) => { if (r.a > this.lastId) { this.lastId = r.a; added = this.add(r.T / 1000, +r.p, +r.p, +r.p, +r.p, +r.q) || added; } });
            this.onBar(added);
            if (rows.length < 1000) break;
          }
        } else if (!m.futures && this.bars.length) {
          const from = (this.bars[this.bars.length - 1].time) * 1000;
          const rows = await (await fetch(`https://api.binance.com/api/v3/klines?symbol=${m.name}&interval=1s&startTime=${from}&limit=1000`)).json();
          if (Array.isArray(rows)) { let added = false; rows.forEach((r) => { added = this.addOpenSecond(r[0] / 1000, +r[1], +r[2], +r[3], +r[4], +r[5]) || added; }); this.onBar(added); }
        }
      } catch { /* the stream itself may still come back */ }
      if (!this.stopped) this.connect();
    }

    /** Moves every price by `d` (to sit on the broker's price), and what comes after too. */
    shift(d) {
      this.bars.forEach((b) => { b.open += d; b.high += d; b.low += d; b.close += d; });
      if (this.snap && this.snap.bar) ["open", "high", "low", "close"].forEach((k) => (this.snap.bar[k] += d));
      this.offset += d;
    }

    close() {
      this.stopped = true;
      clearInterval(this.watch);
      if (this.ws) { this.ws.onmessage = null; this.ws.onclose = null; this.ws.close(); }
      this.ws = null;
    }
  }

  /* ----- more timeframes of the same symbol beside the chart (layouts of 2 / 3 / 4 charts) ----- */

  /** The bar holding `t` (the last one at or before it). */
  function barAt(bars, t) {
    let lo = 0, hi = bars.length - 1;
    if (hi < 0 || t < bars[0].time) return null;
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (bars[mid].time <= t) lo = mid; else hi = mid - 1; }
    return bars[lo];
  }

  /** One extra chart: its own timeframe, the main chart's symbol, live like it (MT5 every 2 s, or Binance). */
  class TfPane {
    constructor(term, tf) {
      this.term = term; this.tf = TF_SECONDS[tf] ? tf : "1h"; this.bars = []; this.token = 0;
      const wrap = (this.wrap = document.createElement("div"));
      wrap.className = "chart-wrap tf-pane";
      wrap.innerHTML = `<div class="tfp-chart"></div><div class="tfp-head"><b></b>
        <select title="Khung thời gian của ô này">${TFS.map((i) => `<option value="${i}">${i}</option>`).join("")}</select>
        <span class="tfp-price"></span>
        <button type="button" class="swap-btn" title="Đưa khung này lên biểu đồ chính (để vẽ, đặt lệnh)">⤢</button></div>`;
      this.chart = LightweightCharts.createChart(wrap.firstChild, {
        autoSize: true,
        kineticScroll: { mouse: true, touch: true },
        layout: { background: { color: "#050506" }, textColor: "#8b95a7", fontFamily: "-apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif" },
        rightPriceScale: { borderColor: "#1e1e23" },
        timeScale: { borderColor: "#1e1e23", timeVisible: true, rightOffset: 6, barSpacing: 5 },
        localization: { timeFormatter: (t) => term.timeLabel(t) },
        crosshair: { mode: 0 },
      });
      this.series = this.chart.addCandlestickSeries({ borderVisible: false });
      // The main chart's layer on this one: a view of the terminal with this chart, its bars and timeframe.
      const pane = this, v = (this.v = Object.create(term));
      const own = (get) => ({ get, set() { /* this chart's own */ }, configurable: true });
      Object.defineProperties(v, { bars: own(() => pane.bars), interval: own(() => pane.tf), digits: own(() => (pane.digits != null ? pane.digits : term.digits)) });
      Object.assign(v, {
        chart: this.chart, series: this.series, viewBars: () => pane.bars, replay: null, requestICT: null, isPane: true,
        ict: null, models: null, plan: null, liq: null, macro: null, smt: null, sharks: null, sharkZones: null, newsDots: null, seriesPriceOn: null, studySeries: new Map(), studySig: "",
      });
      Object.assign(v, v.axisViews());
      this.series.attachPrimitive(v.layer());
      // The symbol's drawings: the main chart's own list, drawn and edited here too (each chart keeps
      // its own pick); a change on any chart repaints the others.
      this.lines = new Map();
      const dr = (this.drawings = new window.AurumDrawings({
        chart: this.chart, series: this.series, store,
        bars: () => pane.bars, sec: () => TF_SECONDS[pane.tf], digits: () => v.digits,
        symbol: () => term.symbolKey(), magnet: () => term.magnet, interval: () => pane.tf,
        onChange: () => term.drawingsChanged(dr), onEdit: (d, isNew) => term.drawingSettings(d, isNew),
      }));
      let ownList = [];
      Object.defineProperty(dr, "list", {
        get: () => (term.drawingsMain ? term.drawingsMain.list : ownList),
        set: (list) => { if (term.drawingsMain) term.drawingsMain.list = list; else ownList = list; },
        configurable: true,
      });
      dr.keepTool = store.get("aurum.keepTool") === "1";
      dr.lockAll = store.get("aurum.lockAll") === "1";
      this.bindDraw();
      const sel = wrap.querySelector("select");
      sel.value = this.tf;
      sel.onchange = () => { this.tf = sel.value; term.savePaneTfs(); this.load(); };
      wrap.querySelector("button").onclick = () => term.paneToMain(this);
      wrap.addEventListener("pointerdown", (e) => { if (!e.target.closest("#ctxMenu")) term.closeMenu(); });
      this.chart.timeScale().subscribeVisibleLogicalRangeChange((r) => { if (r && r.from < 30) this.older(); });
      this.chart.subscribeCrosshairMove((param) => term.crossFrom(this.chart, param));
    }

    symbol() { return this.term.owner ? this.term.symbol || "XAUUSD" : $("chartSymbol").textContent || "XAUUSD"; }
    key() { return `${this.term.owner ? this.term.symbol : "member"}|${this.tf}`; }
    ensure() { if (this.loadedKey !== this.key()) this.load(); }

    path(count, before) {
      const extra = before ? `&before=${before}` : "";
      return this.term.owner
        ? `/mt5/candles?symbol=${encodeURIComponent(this.symbol())}&interval=${this.tf}&count=${count}${extra}`
        : `/member/candles?interval=${this.tf}&count=${count}${extra}`;
    }

    stop() {
      clearInterval(this.timer); this.timer = null;
      this.tickable = false;
      if (this.feed) { this.feed.close(); this.feed = null; }
      if (this.ws) { this.ws.onmessage = null; this.ws.onclose = null; this.ws.close(); this.ws = null; }
      this.loadedKey = null;
    }

    destroy() {
      this.stop(); this.token++; clearTimeout(this.analyseTimer);
      window.removeEventListener("pointermove", this.onWinMove);
      window.removeEventListener("pointerup", this.onWinUp);
      window.removeEventListener("pointercancel", this.onWinUp);
      if (this.term.drawings === this.drawings) this.term.focusChart(1);
      if ($("drawBar").parentElement === this.wrap) $("chartWrap").appendChild($("drawBar"));
      this.chart.remove(); this.wrap.remove();
    }

    async load() {
      const term = this.term, tf = this.tf, sec = TF_SECONDS[tf];
      this.stop();
      this.loadedKey = this.key();
      const token = ++this.token;
      this.noOlder = false;
      this.wrap.querySelector("select").value = tf;
      this.wrap.querySelector("b").textContent = $("chartSymbol").textContent || this.symbol();
      this.chart.applyOptions({ timeScale: { secondsVisible: isSecTF(tf) } });
      let bars = [], digits = term.digits != null ? term.digits : 2, live = null;
      const market = binanceMarket(this.symbol());
      try {
        if (isSecTF(tf)) {
          if (!market) throw new Error("no seconds");
          const feed = new SecondFeed(Object.assign({}, market), sec);
          await feed.history(Math.max(240, Math.round(3600 / sec)));
          if (token !== this.token) { feed.close(); return; }
          // Onto the broker's price, as the main chart's second bars are.
          const last = feed.bars[feed.bars.length - 1], step = Math.pow(10, -feed.market.digits);
          if (last && term.bid != null && term.ask != null) {
            const d = Math.round(((term.bid + term.ask) / 2 - last.close) / step) * step;
            if (Math.abs(d) < last.close * 0.01) feed.shift(d);
          }
          this.feed = feed; bars = feed.bars; digits = feed.market.digits;
          live = "feed";
        } else {
          try {
            if (!term.base) throw new Error("no server");
            const data = await term.call(this.path(800));
            bars = term.toBars(data.candles || []);
            if (bars.length < 5) throw new Error("no bars");
            if (data.digits != null) digits = data.digits;
            live = "mt5";
          } catch (e) {
            if (!market) throw e;
            const rest = market.futures ? "https://fapi.binance.com/fapi/v1/klines" : "https://api.binance.com/api/v3/klines";
            bars = await binanceBars(rest, market.name, tf, 800);
            if (market.digits != null) digits = market.digits;
            live = "binance";
          }
        }
      } catch {
        if (token !== this.token) return;
        this.wrap.querySelector(".tfp-price").textContent = "chưa tải được nến — thử lại…";
        this.loadedKey = null;
        setTimeout(() => { if (token === this.token) this.ensure(); }, 5000);
        return;
      }
      if (token !== this.token) return;
      this.bars = bars;
      this.series.applyOptions({ priceFormat: { type: "price", precision: digits, minMove: Math.pow(10, -digits) } });
      this.digits = digits;
      this.chart.priceScale("right").applyOptions({ autoScale: true });
      this.series.setData(bars.map(shown));
      this.chart.timeScale().scrollToPosition(6, false);
      this.showPrice();
      this.analyse();
      if (live === "feed") {
        let drawn = bars.length;
        this.feed.live(() => {
          if (token !== this.token) return;
          const last = this.bars[this.bars.length - 1];
          if (this.bars.length - drawn > 1) this.series.setData(this.bars.map(shown)); else if (last) this.series.update(shown(last));
          drawn = this.bars.length;
          this.showPrice();
          this.analyseSoon();
        });
      } else if (live === "mt5") {
        this.polledAt = Date.now();
        this.timer = setInterval(() => this.poll(token), 2000);
        this.tickable = true;
      } else {
        const ws = new WebSocket(`${market.futures ? "wss://fstream.binance.com/ws/" : "wss://stream.binance.com:9443/ws/"}${market.name.toLowerCase()}@kline_${binanceKline(tf)[0]}`);
        const fold = klineFolder(tf);
        ws.onmessage = (ev) => {
          const k = JSON.parse(ev.data).k;
          if (!k || token !== this.token) return;
          this.put(fold({ time: k.t / 1000, open: +k.o, high: +k.h, low: +k.l, close: +k.c, volume: +k.v }, this.bars[this.bars.length - 1]));
          this.showPrice();
        };
        this.ws = ws;
      }
    }

    /** The main chart's MT5 tick (the same symbol) into this chart's forming bar. */
    tick(t) {
      if (!this.tickable || !this.bars.length) return;
      this.term.tickInto(this.bars, TF_SECONDS[this.tf], t, (b) => this.series.update(shown(b)));
      this.showPrice(t.bid);
    }

    put(b) {
      const last = this.bars[this.bars.length - 1];
      if (!last || b.time > last.time) this.bars.push(b); else if (b.time === last.time) this.bars[this.bars.length - 1] = b; else return;
      this.series.update(shown(b));
      this.analyseSoon();
    }

    /** The newest bars, every bar since the last poll after a sleeping tab. */
    async poll(token) {
      if (this.polling) return;
      const sec = TF_SECONDS[this.tf], late = (Date.now() - (this.polledAt || Date.now())) / 1000;
      if (late / sec > 700) { this.load(); return; }
      this.polling = true;
      try {
        const data = await this.term.call(this.path(Math.max(3, Math.ceil(late / sec) + 3)));
        if (token !== this.token) return;
        this.polledAt = Date.now();
        this.term.toBars(data.candles || []).forEach((b) => this.put(b));
        this.showPrice(data.bid);
      } catch { /* keep the chart */ } finally { this.polling = false; }
    }

    /** Older bars when scrolled back to the start (MT5 only). */
    async older() {
      if (this.noOlder || this.busy || !this.bars.length || !this.timer) return;
      this.busy = true;
      const token = this.token;
      try {
        const data = await this.term.call(this.path(800, this.bars[0].time));
        if (token !== this.token) return;
        const got = this.term.toBars(data.candles || []).filter((b) => b.time < this.bars[0].time);
        if (!got.length) { this.noOlder = true; return; }
        this.bars.unshift(...got);
        const ts = this.chart.timeScale(), r = ts.getVisibleLogicalRange();
        this.series.setData(this.bars.map(shown));
        if (r) ts.setVisibleLogicalRange({ from: r.from + got.length, to: r.to + got.length });
        this.analyse();
      } catch { this.noOlder = true; } finally { this.busy = false; }
    }

    showPrice(bid) {
      const last = this.bars[this.bars.length - 1];
      this.wrap.querySelector(".tfp-price").textContent = last ? fmt(bid != null ? bid : last.close, this.digits) : "";
    }

    repaint() { if (this.v.requestICT) this.v.requestICT(); }

    /** ICT, shark flow and the standard indicators on this timeframe, with the main chart's settings. */
    analyse() {
      clearTimeout(this.analyseTimer); this.analyseTimer = null;
      this.analysedAt = Date.now();
      const term = this.term, v = this.v, bars = this.bars;
      const flowAllowed = term.owner || term.features.sharkflow !== false;
      const flow = flowAllowed && (showInd.flow || showInd.zones) && window.ICT && bars.length ? window.ICT.sharkFlow(bars) : null;
      v.sharks = flow && showInd.flow ? flow.sharks : null;
      v.sharkZones = flow && showInd.zones ? flow.zones : null;
      v.ict = null;
      if ((term.owner || term.features.killzones !== false) && bars.length && window.ICT && term.ictCfg) {
        try { v.ict = window.ICT.compute(bars, TF_SECONDS[this.tf], term.ictCfg, showInd, { m1: term.mondayM1(bars) }); } catch { /* none */ }
      }
      v.models = term.modelsFor(bars, TF_SECONDS[this.tf], v.digits);
      v.plan = term.planFor(bars, TF_SECONDS[this.tf], v.digits);
      v.liq = term.liqFor(bars, TF_SECONDS[this.tf], v.digits);
      v.macro = term.macroFor(bars, TF_SECONDS[this.tf]);
      // Indicators added, removed or changed on the main chart: built again here.
      const sig = JSON.stringify(term.studies || []);
      if (sig !== v.studySig) { [...v.studySeries.keys()].forEach((id) => v.dropStudySeries(id)); v.studySig = sig; }
      if (bars.length) v.applyStudies();
      this.mirrorDrawings(true);
      this.syncLines();
      this.repaint();
    }

    analyseSoon() {
      if (this.analyseTimer) return;
      this.analyseTimer = setTimeout(() => this.analyse(), Math.max(0, 1500 - (Date.now() - (this.analysedAt || 0))));
    }

    /** The main chart's drawings (one list), hidden with them. */
    mirrorDrawings() {
      const d = this.drawings, main = this.term.drawingsMain;
      d.hidden = !!(main && main.hidden);
      if (d.selected && !d.list.some((x) => x.id === d.selected)) d.selected = null;
      d.update();
    }

    /** Drawing on this chart, like on the main one: pick a tool, tap / drag; tap a drawing to pick it. */
    bindDraw() {
      const term = this.term, wrap = this.wrap, dr = this.drawings;
      const rel = (e) => { const r = wrap.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
      const lock = (on) => {
        this.chart.applyOptions({ handleScroll: !on, handleScale: !on });
        const ps = this.chart.priceScale("right");
        if (on) { this.scaleWasAuto = ps.options().autoScale; ps.applyOptions({ autoScale: false }); } else if (this.scaleWasAuto) ps.applyOptions({ autoScale: true });
      };
      let gesture = false;
      wrap.addEventListener("pointerdown", (e) => {
        term.focusPane(this);
        if (e.button > 0 || e.target.closest(".tfp-head, #drawBar")) return;
        const { x, y } = rel(e);
        if (x > this.chart.timeScale().width()) return;
        const r = dr.down(x, y, e);
        if (r === true) { gesture = true; lock(true); e.stopPropagation(); }
      }, true);
      ["mousedown", "touchstart"].forEach((t) => wrap.addEventListener(t, (e) => { if (gesture) e.stopPropagation(); }, { capture: true, passive: true }));
      wrap.addEventListener("touchmove", (e) => { if (gesture) e.preventDefault(); }, { passive: false });
      wrap.addEventListener("pointermove", (e) => {
        if (gesture) return;
        const { x, y } = rel(e);
        if (dr.pending) { dr.move(x, y, e); return; }
        if (e.pointerType === "mouse") wrap.style.cursor = dr.tool ? "crosshair" : x <= this.chart.timeScale().width() && dr.hitTest(x, y, 8) ? "move" : "";
      });
      this.onWinMove = (e) => { if (gesture) { const { x, y } = rel(e); dr.move(x, y, e); } };
      this.onWinUp = () => { if (!gesture) return; gesture = false; lock(false); dr.up(); };
      window.addEventListener("pointermove", this.onWinMove);
      window.addEventListener("pointerup", this.onWinUp);
      window.addEventListener("pointercancel", this.onWinUp);
      wrap.addEventListener("dblclick", () => { if (dr.current) term.drawingSettings(dr.current); });
      wrap.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        if (dr.pending) { dr.cancel(); return; }
        const items = [["tools", "✎ Công cụ vẽ…"]];
        if (dr.current) items.push(["drawSettings", "⚙ Cài đặt bản vẽ…"], ["drawDel", "🗑 Xoá bản vẽ này"]);
        items.push(["main", "⤢ Đưa khung này lên biểu đồ chính"]);
        const menu = $("ctxMenu");
        menu.innerHTML = items.map(([k, t]) => `<button type="button" data-k="${k}">${esc(t)}</button>`).join("");
        menu.hidden = false;
        menu.style.left = Math.max(8, Math.min(e.clientX, window.innerWidth - menu.offsetWidth - 8)) + "px";
        menu.style.top = Math.max(8, Math.min(e.clientY, window.innerHeight - menu.offsetHeight - 8)) + "px";
        menu.querySelectorAll("button").forEach((b) => (b.onclick = () => {
          term.closeMenu();
          if (b.dataset.k === "tools") term.drawSheet();
          if (b.dataset.k === "drawSettings") term.drawingSettings(dr.current);
          if (b.dataset.k === "drawDel" && dr.current) dr.remove(dr.current.id);
          if (b.dataset.k === "main") term.paneToMain(this);
        }));
      });
    }

    /** Positions, orders and the pending draft on this chart's price axis, read-only. */
    syncLines() {
      const wanted = this.term.owner ? this.term.lineCache || [] : [];
      const keys = new Set();
      wanted.forEach((w) => {
        keys.add(w.key);
        const opts = { price: w.price, color: w.color, lineWidth: w.width, lineStyle: w.style, axisLabelVisible: true, title: w.drawn ? "" : w.title, lineVisible: !w.drawn };
        const line = this.lines.get(w.key);
        if (line) line.applyOptions(opts); else this.lines.set(w.key, this.series.createPriceLine(opts));
      });
      for (const [k, line] of this.lines) if (!keys.has(k)) { this.series.removePriceLine(line); this.lines.delete(k); }
    }
  }

  const TAB_TITLE = document.title;
  /** A tab icon: the brand's logo with a badge in its corner, a green up arrow or a red down arrow
   *  (grey dash when the candle stands at its open). */
  const tabIcons = {};
  let tabLogo = null;
  function tabIcon(dir) {
    if (tabIcons[dir]) return Promise.resolve(tabIcons[dir]);
    tabLogo = tabLogo || new Promise((ok) => { const img = new Image(); img.onload = () => ok(img); img.onerror = () => ok(null); img.src = "favicon.svg"; });
    return tabLogo.then((img) => {
      const c = document.createElement("canvas");
      c.width = c.height = 64;
      const g = c.getContext("2d");
      if (img) g.drawImage(img, 0, 0, 64, 64);
      // The badge: a round disc at the bottom right with a white ring, an arrow inside.
      const cx = 45, cy = 45, r = 17, k = 0.85;
      g.fillStyle = "#ffffff"; g.beginPath(); g.arc(cx, cy, r + 3, 0, Math.PI * 2); g.fill();
      g.fillStyle = dir > 0 ? "#089981" : dir < 0 ? "#f23645" : "#787b86";
      g.beginPath(); g.arc(cx, cy, r, 0, Math.PI * 2); g.fill();
      g.fillStyle = "#fff"; g.beginPath();
      const arrow = (sgn) => [[0, -13], [12, 1], [5, 1], [5, 12], [-5, 12], [-5, 1], [-12, 1]]
        .forEach(([x, y], i) => g[i ? "lineTo" : "moveTo"](cx + x * k, cy + y * k * sgn));
      if (dir) arrow(dir > 0 ? 1 : -1);
      else g.rect(cx - 10, cy - 3, 20, 6);
      g.closePath(); g.fill();
      return (tabIcons[dir] = c.toDataURL("image/png"));
    });
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

  /** A hole in the bars while the market trades: a gap over 3 h (and 3 bars) without a weekend day in it.
   *  MT5 can hand a symbol just opened its old cached bars before the missing stretch is downloaded. */
  function barsHole(bars, sec) {
    // Only the last 24 hours: further back holidays (an early close) look like holes and made 1h charts
    // load again and again.
    const since = bars.length ? bars[bars.length - 1].time - 86400 : 0;
    for (let i = Math.max(1, bars.length - 1500); i < bars.length; i++) {
      const a = bars[i - 1].time, b = bars[i].time;
      if (a < since || b - a <= Math.max(sec * 3, 10800)) continue;
      let weekend = false;
      for (let t = a; t <= b && !weekend; t += 3 * 3600) { const d = new Date(t * 1000).getUTCDay(); weekend = d === 0 || d === 6; }
      if (!weekend) return { after: a, before: b };
    }
    return null;
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
  /** The "Nến tick" bot (v2) on past Exness bars, as the server's TickBot: inside each candle, every run of
   *  `step` from the last entry (the candle's open at first) opens a position that way (BUY at the ask, SELL
   *  at the bid); each closes on its own `closeProfit` (a BUY at the bid, a SELL at the ask); at most
   *  `maxPositions` open; all out when the basket is `basketStop` dollars down (no entries for the rest of the
   *  candle) and, by default, at the candle's close. The price path in a candle: its 1-minute bars when it is
   *  longer than a minute, else open → low → high → close (rising) or open → high → low → close (falling),
   *  walked in small steps. */
  function tickBotBacktest(bars, c, value, spread, subBars) {
    const sec = TF_SECONDS[c.interval] || 60, trades = [];
    let placed = 0, si = 0, book = [];
    if (c.maxSpread > 0 && spread > c.maxSpread) return { placed: 0, trades };
    const path = (b) => (b.close >= b.open ? [b.open, b.low, b.high, b.close] : [b.open, b.high, b.low, b.close]);
    const res = Math.max(0.0001, Math.min(c.step, c.closeProfit) / 4);
    const gain = (p, bid) => (p.side === "long" ? bid - p.entry : p.entry - (bid + spread));
    const out = (p, bid, reason, time) => trades.push(Object.assign({}, p, { exit: p.side === "long" ? bid : bid + spread, reason, closeTime: time,
      profit: value(p.side, p.entry, p.side === "long" ? bid : bid + spread) }));
    bars.forEach((b) => {
      let pieces = [b];
      if (subBars && sec > 60) {
        while (si < subBars.length && subBars[si].time < b.time) si++;
        const list = [];
        for (let k = si; k < subBars.length && subBars[k].time < b.time + sec; k++) list.push(subBars[k]);
        if (list.length) pieces = list;
      }
      // The points price went through in this candle, with their time (share of the candle).
      const walk = [];
      pieces.forEach((pc, pi) => {
        const pts = path(pc);
        for (let k = 0; k < 3; k++) {
          const a = pts[k], z = pts[k + 1], n = Math.max(1, Math.ceil(Math.abs(z - a) / res));
          for (let j = 1; j <= n; j++) walk.push([a + (z - a) * j / n, (pi + (k + j / n) / 3) / pieces.length]);
        }
      });
      let ref = b.open, stopped = false;
      for (const [bid, share] of walk) {
        const time = b.time + Math.round(share * sec);
        // Each position out on its profit, its stop, or (losing) once the candle has turned against it.
        book = book.filter((p) => {
          const g = gain(p, bid);
          if (c.holdSeconds >= 0 && time - p.openTime >= c.holdSeconds) { out(p, bid, "hold", time); return false; }
          if (g >= c.closeProfit - 1e-9) { out(p, bid, "target", time); return false; }
          if (c.sl > 0 && g <= -c.sl + 1e-9) { out(p, bid, "sl", time); return false; }
          if (c.flipExit && g < 0 && (p.side === "long" ? bid < b.open - c.step : bid > b.open + c.step)) { out(p, bid, "flip", time); return false; }
          return true;
        });
        // Basket stop.
        const floating = book.reduce((a, p) => a + value(p.side, p.entry, p.side === "long" ? bid : bid + spread), 0);
        if (c.basketStop > 0 && book.length && floating <= -c.basketStop) {
          book.forEach((p) => out(p, bid, "stop", time)); book = []; stopped = true;
        }
        if (stopped || book.length >= c.maxPositions || share > 1 - (c.minLeftPct || 0) / 100) continue;
        const move = bid - ref;
        const up = move >= c.step - 1e-9, down = -move >= c.step - 1e-9;
        if (!up && !down) continue;
        ref = bid;
        if ((up && c.direction === "short") || (down && c.direction === "long")) continue;
        if (c.withCandle && (up ? bid <= b.open : bid >= b.open)) continue;
        for (let q = 0; q < Math.min(c.burst || 1, c.maxPositions - book.length); q++) {
          placed++;
          book.push({ side: up ? "long" : "short", entry: up ? bid + spread : bid, stop: null, target: null, openTime: time });
        }
      }
      if (c.exitAtClose !== false && book.length) { book.forEach((p) => out(p, b.close, "close", b.time + sec)); book = []; }
    });
    if (book.length) { const b = bars[bars.length - 1]; book.forEach((p) => out(p, b.close, "end", b.time + sec)); }
    return { placed, trades };
  }

  /** The tick bot on REAL Exness ticks ([ms, bid, ask]), step by step as the server runs it: each tick
   *  closes positions on their profit / stop / candle turning, checks the basket stop, then may open
   *  (BUY at the ask, SELL at the bid, the real spread of that moment). */
  /** Broker account types to try (XAUUSD, rough averages: change them to your broker's figures). spread in
   *  price, commission in $ per lot round trip; spread null = the real one. */
  const ACCOUNT_SIMS = {
    real: { name: "Thực tế (spread tick thật / nến)", spread: null, commission: 0 },
    standard: { name: "Standard (spread ~0.20, không phí)", spread: 0.20, commission: 0 },
    pro: { name: "Pro (spread ~0.12, không phí)", spread: 0.12, commission: 0 },
    raw: { name: "Raw Spread (spread ~0.03 + phí 7$/lot)", spread: 0.03, commission: 7 },
    zero: { name: "Zero (spread 0 + phí 10$/lot)", spread: 0, commission: 10 },
    custom: { name: "Tuỳ chỉnh…", spread: 0.1, commission: 0 },
  };

  function tickBotOnTicks(ticks, c, value) {
    const sec = TF_SECONDS[c.interval] || 60, trades = [];
    let placed = 0, book = [], bar = null, open = 0, ref = 0, stopped = false;
    const out = (p, bid, ask, reason, t) => {
      const exit = p.side === "long" ? bid : ask;
      trades.push(Object.assign({}, p, { exit, reason, closeTime: t, profit: value(p.side, p.entry, exit) }));
    };
    for (const [ms, bid0, ask0] of ticks) {
      const t = ms / 1000, bid = bid0, ask = c.noSpread ? bid0 : ask0;
      const bt = Math.floor(t / sec) * sec;
      if (bt !== bar) {
        if (c.exitAtClose !== false && book.length) { book.forEach((p) => out(p, bid, ask, "close", t)); book = []; }
        bar = bt; open = bid; ref = bid; stopped = false;
      }
      const gain = (p) => (p.side === "long" ? bid - p.entry : p.entry - ask);
      book = book.filter((p) => {
        const g = gain(p);
        if (c.holdSeconds >= 0 && t - p.openTime >= c.holdSeconds) { out(p, bid, ask, "hold", t); return false; }
        if (g >= c.closeProfit - 1e-9) { out(p, bid, ask, "target", t); return false; }
        if (c.sl > 0 && g <= -c.sl + 1e-9) { out(p, bid, ask, "sl", t); return false; }
        if (c.flipExit && g < 0 && (p.side === "long" ? bid < open - c.step : bid > open + c.step)) { out(p, bid, ask, "flip", t); return false; }
        return true;
      });
      const floating = book.reduce((a, p) => a + value(p.side, p.entry, p.side === "long" ? bid : ask), 0);
      if (c.basketStop > 0 && book.length && floating <= -c.basketStop) { book.forEach((p) => out(p, bid, ask, "stop", t)); book = []; stopped = true; }
      if (stopped || book.length >= c.maxPositions) continue;
      if (bar + sec - t < sec * (c.minLeftPct || 0) / 100) continue;
      if (!c.noSpread && c.maxSpread > 0 && ask - bid > c.maxSpread) continue;
      const move = bid - ref, up = move >= c.step - 1e-9, down = -move >= c.step - 1e-9;
      if (!up && !down) continue;
      ref = bid;
      if ((up && c.direction === "short") || (down && c.direction === "long")) continue;
      if (c.withCandle && (up ? bid <= open : bid >= open)) continue;
      for (let q = 0; q < Math.min(c.burst || 1, c.maxPositions - book.length); q++) {
        placed++;
        book.push({ side: up ? "long" : "short", entry: up ? ask : bid, stop: null, target: null, openTime: t });
      }
    }
    if (book.length && ticks.length) { const [ms, bid, ask] = ticks[ticks.length - 1]; book.forEach((p) => out(p, bid, c.noSpread ? bid : ask, "end", ms / 1000)); }
    return { placed, trades };
  }

  /** The "Nhồi lệnh" grid bot on ticks, as the server's GridBot: a basket of buys and / or of sells; each time
   *  price goes `gridStep` further against a basket's worst entry it adds the last lot × `multiplier` (at most
   *  `maxLevels` positions, `maxLot` each); a basket `tpMoney` up is closed whole and starts again; all out
   *  when the bot is `basketStop` down, then no entries for `cooldownMin` minutes. `value(side, entry, exit, lots)`
   *  is the money of a position (commission off). Also returns the worst floating loss it went through. */
  function gridLot(c, n, factor = 1) {
    // Half up to the 0.01 lot, as the server's grid_lot.
    const lots = Math.floor(c.lots * factor * Math.pow(c.multiplier || 1, n) * 100 + 0.5 + 1e-9) / 100;
    return Math.min(+c.maxLot || 99, Math.max(0.01, lots));
  }

  /** The side a closed candle pushes (body ≥ biasMinBody % of its range), as the server's candle_bias. */
  function candleBias(c, o, h, l, cl) {
    const rng = h - l;
    if (!(rng > 0)) return { side: null, body: 0 };
    const body = (cl - o) / rng;
    return { side: Math.abs(body) * 100 < (c.biasMinBody ?? 50) - 1e-9 ? null : body > 0 ? "long" : "short", body };
  }

  /** The side the grid bot's signal entry allows (as the server's grid_signal): each filter that is on (the last
   *  closed candle, the M1 support / resistance, the tick move) gives the sides it allows; the answer is the one
   *  side all allow, else null. */
  /* Swings, reversal candles, FVG / OB on closed bars [o, h, l, c] — as the server's swing_points, reversal_candle,
   * swing_vote, fvg_ob_zones and zone_vote. */
  function swingPoints(bars, k) {
    const highs = [], lows = [];
    for (let i = k; i < bars.length - k; i++) {
      const before = bars.slice(i - k, i), after = bars.slice(i + 1, i + k + 1), [, h, l] = bars[i];
      if (h > Math.max(...before.map((b) => b[1])) && h >= Math.max(...after.map((b) => b[1]))) highs.push(h);
      if (l < Math.min(...before.map((b) => b[2])) && l <= Math.min(...after.map((b) => b[2]))) lows.push(l);
    }
    return { highs, lows };
  }

  function reversalCandle(prev, last) {
    const [o, h, l, c] = last, rng = h - l;
    if (!(rng > 0)) return null;
    const body = Math.abs(c - o), lower = Math.min(o, c) - l, upper = h - Math.max(o, c), [po, , , pc] = prev;
    const bull = (lower >= 2 * body && lower >= 0.5 * rng && c >= l + 0.5 * rng) || (c > o && pc < po && c >= po && o <= pc)
      || (c > o && c - l >= 0.65 * rng && lower >= 0.3 * rng);
    const bear = (upper >= 2 * body && upper >= 0.5 * rng && c <= h - 0.5 * rng) || (c < o && pc > po && c <= po && o >= pc)
      || (c < o && h - c >= 0.65 * rng && upper >= 0.3 * rng);
    return bull && !bear ? "long" : bear && !bull ? "short" : null;
  }

  function swingVote(c, bars) {
    const k = c.swingK || 3, z = c.swingZone ?? 0.5;
    if (bars.length < 2 * k + 3) return [];
    const { highs, lows } = swingPoints(bars.slice(0, -1), k), last = bars[bars.length - 1];
    const rev = reversalCandle(bars[bars.length - 2], last);
    // Any recent swing is a level; the reversal says whether price holds over it (buy) or under it (sell).
    const levels = highs.slice(-5).concat(lows.slice(-5));
    if (rev === "long" && levels.some((x) => Math.abs(last[2] - x) <= z && last[3] > x)) return ["long"];
    if (rev === "short" && levels.some((x) => Math.abs(last[1] - x) <= z && last[3] < x)) return ["short"];
    const eng = engulfing(bars[bars.length - 2], last);
    if (eng === "short" && lows.slice(-5).some((x) => last[0] >= x && x > last[3])) return ["short"];
    if (eng === "long" && highs.slice(-5).some((x) => last[0] <= x && x < last[3])) return ["long"];
    return [];
  }

  /** Trend lines through 3 swing highs (falling or rising) and 3 swing lows of bars {time, open, high, low, close}:
   *  for each side the latest three swings whose middle sits on the line through the outer two (within a quarter of
   *  the average bar range), with no close beyond the line between them. Each line: its points, its value at a bar
   *  index, and the last closed bar against it — "breakout" (closed through), "bounce" (touched and closed back),
   *  "near" (within the tolerance) or "away". */
  function trendLines3(bars, k = 3) {
    const n = bars.length;
    if (n < 2 * k + 8) return [];
    const avg = bars.slice(-50).reduce((a, b) => a + (b.high - b.low), 0) / Math.min(50, n), tol = Math.max(avg * 0.25, 1e-9);
    const highs = [], lows = [];
    for (let i = k; i < n - k; i++) {
      const w = bars.slice(i - k, i + k + 1);
      if (bars[i].high >= Math.max(...w.map((b) => b.high)) && bars[i].high > Math.max(...bars.slice(i - k, i).map((b) => b.high))) highs.push(i);
      if (bars[i].low <= Math.min(...w.map((b) => b.low)) && bars[i].low < Math.min(...bars.slice(i - k, i).map((b) => b.low))) lows.push(i);
    }
    const out = [];
    for (const [kind, idx, val] of [["high", highs, (i) => bars[i].high], ["low", lows, (i) => bars[i].low]]) {
      const recent = idx.slice(-8);
      let best = null;
      for (let c = recent.length - 1; c >= 2 && !best; c--) {
        for (let b = c - 1; b >= 1 && !best; b--) {
          for (let a = b - 1; a >= 0 && !best; a--) {
            const i1 = recent[a], i2 = recent[b], i3 = recent[c], p1 = val(i1), p3 = val(i3), slope = (p3 - p1) / (i3 - i1);
            const at = (i) => p1 + slope * (i - i1);
            if (Math.abs(val(i2) - at(i2)) > tol) continue;
            // Respected between the first and the last point: no close beyond it.
            let ok = true;
            for (let i = i1; i <= i3 && ok; i++) if (kind === "high" ? bars[i].close > at(i) + tol : bars[i].close < at(i) - tol) ok = false;
            if (!ok) continue;
            best = { kind, i1, i3, p1, p3, points: [i1, i2, i3], at };
          }
        }
      }
      if (!best) continue;
      // What price did after the third point: the first close through the line (a breakout), else the last touch
      // that closed back (a bounce); then where the last bar is.
      best.state = null; best.eventAt = null; best.touches = 0;
      for (let i = best.i3 + 1; i < n; i++) {
        const lv = best.at(i), b = bars[i];
        if (kind === "high" ? b.close > lv + tol : b.close < lv - tol) { best.state = "breakout"; best.eventAt = i; break; }
        if (kind === "high" ? b.high >= lv - tol && b.close < lv : b.low <= lv + tol && b.close > lv) { best.state = "bounce"; best.eventAt = i; best.touches++; }
      }
      if (!best.state) best.state = Math.abs(bars[n - 1].close - best.at(n - 1)) <= tol ? "near" : "away";
      out.push(best);
    }
    return out;
  }

  /** A breaking bar (as the server's engulfing): a down / up bar whose body covers the bar before's body or makes
   *  at least 60 % of its range. */
  function engulfing(prev, last) {
    const [o, h, l, c] = last, [po, , , pc] = prev, rng = h - l;
    if (!(rng > 0) || c === o) return null;
    const covers = Math.max(o, c) >= Math.max(po, pc) && Math.min(o, c) <= Math.min(po, pc);
    return covers || Math.abs(c - o) >= 0.6 * rng ? (c > o ? "long" : "short") : null;
  }

  function swingLevels(c, bars) {
    const k = c.swingK || 3;
    if (bars.length < 2 * k + 3) return null;
    const { highs, lows } = swingPoints(bars.slice(0, -1), k);
    return { highs: highs.slice(-5), lows: lows.slice(-5), prev: bars[bars.length - 2], last: bars[bars.length - 1] };
  }

  /** "Đợi xác nhận ở cản" (as the server's level_block): [side not to open, level] near a recent swing low / high
   *  unless the last bar broke it, else null. */
  function levelBlock(c, lv, bid) {
    if (!lv) return null;
    const room = c.levelRoom ?? 1.5, eng = engulfing(lv.prev, lv.last), last = lv.last;
    // A level's role is where price is: under it a resistance (a broken support too), over it a support.
    const levels = lv.highs.concat(lv.lows);
    const sups = levels.filter((x) => bid - x >= 0 && bid - x <= room), ress = levels.filter((x) => x - bid > 0 && x - bid <= room);
    if (sups.length) { const sp = Math.max(...sups); if (!(eng === "short" && last[3] < sp)) return ["short", sp]; }
    if (ress.length) { const r = Math.min(...ress); if (!(eng === "long" && last[3] > r)) return ["long", r]; }
    return null;
  }

  function fvgObZones(bars, kinds) {
    const zones = [];
    for (let i = 2; i < bars.length; i++) {
      const a = bars[i - 2], d = bars[i];
      for (const [side, gap] of [["long", a[1] < d[2]], ["short", a[2] > d[1]]]) {
        if (!gap) continue;
        if (kinds === "fvg" || kinds === "both") zones.push(side === "long" ? ["fvg", side, a[1], d[2], i] : ["fvg", side, d[1], a[2], i]);
        if (kinds === "ob" || kinds === "both") {
          for (let j = i - 2; j > Math.max(-1, i - 6); j--) {
            const [o, h, l, cl] = bars[j];
            if (side === "long" ? cl < o : cl > o) { zones.push(["ob", side, l, h, i]); break; }
          }
        }
      }
    }
    return zones.filter((z) => {
      const later = bars.slice(z[4] + 1);
      return z[1] === "long" ? !later.some((b) => b[3] < z[2]) : !later.some((b) => b[3] > z[3]);
    });
  }

  function zoneVote(c, bars) {
    if (bars.length < 4) return [];
    const [o, h, l, cl] = bars[bars.length - 1], zones = fvgObZones(bars, c.sigZone || "both");
    for (let q = zones.length - 1; q >= 0; q--) {
      const [, side, lo, hi, i] = zones[q];
      if (i >= bars.length - 1) continue;
      if (side === "long" && l <= hi && cl > o && cl >= lo) return ["long"];
      if (side === "short" && h >= lo && cl < o && cl <= hi) return ["short"];
    }
    return [];
  }

  function gridSignal(c, bid, candle, sup, res, move, extra) {
    // Each filter that is on votes for the sides it allows; "all": a side needs every vote, "two": at least two
    // (all when fewer are on) and more than the other side.
    const votes = { long: 0, short: 0 };
    let used = 0;
    const vote = (ok) => { used++; ok.forEach((x) => votes[x]++); };
    if (c.sigCandle) {
      const side = candle ? candleBias({ biasMinBody: c.sigBody ?? 50 }, candle.o, candle.h, candle.l, candle.c).side : null;
      vote(side ? [side] : []);
    }
    if (c.sigSr && c.sigSr !== "off") {
      const z = c.srZone ?? 1, ok = new Set();
      if (sup != null && res != null) {
        if (c.sigSr === "bounce") { if (bid >= sup - z && bid <= sup + z) ok.add("long"); if (bid >= res - z && bid <= res + z) ok.add("short"); }
        else if (c.sigSr === "break") { if (bid > res && bid <= res + z) ok.add("long"); if (bid >= sup - z && bid < sup) ok.add("short"); }
        else if ((bid >= sup - z && bid <= sup + z) || (bid >= res - z && bid <= res + z)) { ok.add("long"); ok.add("short"); }
      }
      vote([...ok]);
    }
    if (c.sigTick) {
      const ok = [];
      if (move != null) { if (move >= c.tickMove - 1e-9) ok.push("long"); if (move <= -c.tickMove + 1e-9) ok.push("short"); }
      vote(ok);
    }
    Object.values(extra || {}).forEach((ok) => vote(ok));
    if (!used) return null;
    const need = (c.sigNeed || "all") === "all" ? used : Math.min(2, used);
    const good = ["long", "short"].filter((x) => votes[x] >= need && votes[x] > votes[x === "long" ? "short" : "long"]);
    return good.length === 1 ? good[0] : null;
  }

  /** New York's offset from UTC (−4 summer time, −5 winter), as the server's ny_offset_hours. */
  function nyOffsetHours(ts) {
    const y = new Date(ts * 1000).getUTCFullYear();
    const sunday = (m, n) => { const first = new Date(Date.UTC(y, m - 1, 1)); return Date.UTC(y, m - 1, 1 + ((7 - first.getUTCDay()) % 7) + 7 * (n - 1)) / 1000; };
    const start = sunday(3, 2) + 7 * 3600, end = sunday(11, 1) + 6 * 3600;
    return ts >= start && ts < end ? -4 : -5;
  }

  /** The grid bot's fast-market guard, as the server's grid_guard: [why, until] inside the New York window
   *  (weekdays, NY time) or around a high-impact USD event, else null. */
  function gridGuard(c, ts, events) {
    const hm = (x) => { const [h, m] = String(x || "0:0").split(":"); return Math.max(0, Math.min(1439, (+h || 0) * 60 + (+m || 0))); };
    if (c.nyGuard) {
      const local = ts + nyOffsetHours(ts) * 3600, mins = ((local % 86400) + 86400) % 86400 / 60, wd = (Math.floor(local / 86400) + 3) % 7;
      const a = hm(c.nyFrom || "08:15"), b = hm(c.nyTo || "10:30");
      if (wd < 5 && mins >= a && mins < b) return ["giờ mở cửa Mỹ", ts + (b - mins) * 60];
    }
    if (c.newsGuard) {
      const before = (c.newsBefore ?? 15) * 60, after = (c.newsAfter ?? 15) * 60;
      for (const e of events || []) if (e.country === "USD" && e.impact === "High" && ts >= e.time - before && ts <= e.time + after) return ["tin " + e.title, e.time + after];
    }
    return null;
  }

  function gridBotOnTicks(ticks, c, value) {
    const trades = [];
    let locks = 0, guards = 0, flips = 0, trails = 0, placed = 0, book = [], pauseUntil = 0, cycles = 0, stops = 0, sls = 0, maxFloat = 0, maxLevel = 0, maxLots = 0;
    const sidePause = { long: 0, short: 0 };
    // Candle strength: the candles of `biasTf` built from the ticks' bid; `strong` = the last closed one's side.
    const useBias = c.bias && c.bias !== "off", bsec = TF_SECONDS[c.biasTf] || 300;
    let cur = null, strong = null;
    // Signal entry: the last closed sigTf candle, the M1 support / resistance (last srBars closed M1 bars),
    // and the bid's move over the last tickSec seconds.
    const sig = c.entry === "signal", ssec = TF_SECONDS[c.sigTf] || 60;
    let sCur = null, sPrev = null, mCur = null, m1 = [], sup = null, res = null, back = 0, signals = 0;
    // Swings / FVG / OB: the closed structTf candles (the last structBars), the votes worked out on each new one.
    const useStruct = sig && (c.sigSwing || (c.sigZone && c.sigZone !== "off") || c.levelGuard), xsec = TF_SECONDS[c.structTf] || 60;
    let xCur = null, xBars = [], extra = {}, xLevels = null, blocks = 0;
    // The basket's stop: `sl` in price past its first (best) entry.
    // The basket's stop (as the server's sl_level): sl past its best entry; a locked nhồi dương basket (2 layers or
    // more) also at the tightest of the layer before, its average entry and the basket trailing stop.
    const locked = (ps) => c.addMode === "with" && c.pyramidLock !== false && ps.length >= 2;
    const slLevel = (ps, long, peak) => {
      if (!ps.length) return null;
      const e = ps.map((p) => p.entry).sort((a, b) => a - b);
      let level = c.sl > 0 ? (long ? e[e.length - 1] - c.sl : e[0] + c.sl) : null;
      if (locked(ps)) {
        const lots = ps.reduce((a, p) => a + p.lots, 0), avg = ps.reduce((a, p) => a + p.entry * p.lots, 0) / lots;
        let lock = long ? Math.max(e[e.length - 2], avg) : Math.min(e[1], avg);
        if (c.trailOn && peak != null && (long ? peak - avg : avg - peak) >= c.trailStart - 1e-9) {
          const tr = long ? peak - c.trailDist : peak + c.trailDist;
          lock = long ? Math.max(lock, tr) : Math.min(lock, tr);
        }
        level = level == null ? lock : long ? Math.max(level, lock) : Math.min(level, lock);
      }
      return level;
    };
    const bpeak = { long: null, short: null };
    const pv = (p, bid, ask) => value(p.side, p.entry, p.side === "long" ? bid : ask, p.lots);
    const out = (p, bid, ask, reason, t) => trades.push(Object.assign({}, p, { exit: p.side === "long" ? bid : ask, reason, closeTime: t, profit: pv(p, bid, ask) }));
    for (const [ms, bid0, ask0] of ticks) {
      const t = ms / 1000, bid = bid0, ask = c.noSpread ? bid0 : ask0;
      if (useBias) {
        const bt = Math.floor(t / bsec) * bsec;
        if (!cur || cur.t !== bt) {
          if (cur && bt - cur.t === bsec) strong = candleBias(c, cur.o, cur.h, cur.l, cur.c).side;
          else if (cur) strong = null; // a gap (weekend, no ticks): no closed candle right before
          cur = { t: bt, o: bid, h: bid, l: bid, c: bid };
        } else { cur.h = Math.max(cur.h, bid); cur.l = Math.min(cur.l, bid); cur.c = bid; }
      }
      let move = null;
      if (useStruct) {
        const xt = Math.floor(t / xsec) * xsec;
        if (!xCur || xCur.t !== xt) {
          if (xCur) {
            xBars.push([xCur.o, xCur.h, xCur.l, xCur.c]);
            if (xBars.length > (c.structBars || 120)) xBars.shift();
            extra = {};
            if (c.levelGuard) xLevels = swingLevels(c, xBars);
            if (c.sigSwing) extra.swing = swingVote(c, xBars);
            if (c.sigZone && c.sigZone !== "off") extra.zone = zoneVote(c, xBars);
          }
          xCur = { t: xt, o: bid, h: bid, l: bid, c: bid };
        } else { xCur.h = Math.max(xCur.h, bid); xCur.l = Math.min(xCur.l, bid); xCur.c = bid; }
      }
      if (sig) {
        const st = Math.floor(t / ssec) * ssec;
        if (!sCur || sCur.t !== st) { sPrev = sCur && st - sCur.t === ssec ? sCur : null; sCur = { t: st, o: bid, h: bid, l: bid, c: bid }; }
        else { sCur.h = Math.max(sCur.h, bid); sCur.l = Math.min(sCur.l, bid); sCur.c = bid; }
        const mt = Math.floor(t / 60) * 60;
        if (!mCur || mCur.t !== mt) {
          if (mCur) { m1.push(mCur); if (m1.length > (c.srBars || 30)) m1.shift(); sup = Math.min(...m1.map((b) => b.l)); res = Math.max(...m1.map((b) => b.h)); }
          mCur = { t: mt, h: bid, l: bid };
        } else { mCur.h = Math.max(mCur.h, bid); mCur.l = Math.min(mCur.l, bid); }
        while (back + 1 < ticks.length && ticks[back + 1][0] / 1000 <= t - (c.tickSec || 10)) back++;
        if (ticks[back][0] / 1000 <= t - (c.tickSec || 10)) move = bid - ticks[back][1];
      }
      if (book.length && c.trailOn) {
        // Trailing stop for each position: the best price since it opened; once trailStart in profit, out when price
        // comes back trailDist from it.
        const lockedSide = { long: locked(book.filter((p) => p.side === "long")), short: locked(book.filter((p) => p.side === "short")) };
        book = book.filter((p) => {
          const long = p.side === "long", px = long ? bid : ask;
          p.peak = p.peak == null ? px : long ? Math.max(p.peak, px) : Math.min(p.peak, px);
          if (lockedSide[p.side]) return true; // a locked basket trails as one
          if ((long ? p.peak - p.entry : p.entry - p.peak) < c.trailStart - 1e-9) return true;
          const stop = long ? p.peak - c.trailDist : p.peak + c.trailDist;
          if (long ? px <= stop + 1e-9 : px >= stop - 1e-9) { out(p, bid, ask, "trail", t); trails++; return false; }
          return true;
        });
      }
      if (book.length) {
        const total = book.reduce((a, p) => a + pv(p, bid, ask), 0);
        if (total < maxFloat) maxFloat = total;
        if (c.basketStop > 0 && total <= -c.basketStop) {
          book.forEach((p) => out(p, bid, ask, "stop", t)); book = []; stops++; pauseUntil = t + (c.cooldownMin || 0) * 60; continue;
        }
        let closed = false;
        for (const side of ["long", "short"]) {
          const ps = book.filter((p) => p.side === side), px = side === "long" ? bid : ask;
          bpeak[side] = !ps.length ? null : bpeak[side] == null ? px : side === "long" ? Math.max(bpeak[side], px) : Math.min(bpeak[side], px);
        }
        for (const side of ["long", "short"]) {
          const ps = book.filter((p) => p.side === side);
          if (!ps.length) continue;
          const sum = ps.reduce((a, p) => a + pv(p, bid, ask), 0), lv = slLevel(ps, side === "long", bpeak[side]);
          const hit = lv != null && (side === "long" ? bid <= lv + 1e-9 : ask >= lv - 1e-9);
          if (hit || (c.slMoney > 0 && sum <= -c.slMoney + 1e-9)) {
            const lock = hit && locked(ps);
            ps.forEach((p) => out(p, bid, ask, lock ? "lock" : "sl", t)); book = book.filter((p) => p.side !== side);
            if (lock) locks++; else { sls++; sidePause[side] = t + (c.cooldownMin || 0) * 60; }
            closed = true; continue;
          }
          if (c.tpMoney > 0 && sum >= c.tpMoney - 1e-9) {
            ps.forEach((p) => out(p, bid, ask, "basket", t)); book = book.filter((p) => p.side !== side); cycles++; closed = true;
          }
        }
        if (closed) continue;
      }
      if ((c.nyGuard || c.newsGuard) && gridGuard(c, t, c._news)) {
        if (c.guardAction === "close" && book.length) { book.forEach((p) => out(p, bid, ask, "guard", t)); book = []; guards++; }
        continue;
      }
      if (t < pauseUntil) continue;
      if (!c.noSpread && c.maxSpread > 0 && ask - bid > c.maxSpread) continue;
      let signal = sig ? gridSignal(c, bid, sPrev, m1.length ? sup : null, m1.length ? res : null, move, useStruct ? extra : null) : null;
      if (signal && c.levelGuard) { const b = levelBlock(c, xLevels, bid); if (b && b[0] === signal) { signal = null; blocks++; } }
      // Wait waitSec after the candle closed, then only if price holds over (a buy) / under (a sell) its close.
      if (signal && c.waitSec > 0 && sPrev) {
        if (t - sCur.t < c.waitSec) signal = null;
        else if (signal === "long" ? bid < sPrev.c : bid > sPrev.c) signal = null;
      }
      if (signal) signals++;
      if (sig && c.flipClose && signal && book.some((p) => p.side !== signal)) {
        // The signal turned: out of the basket the other way; the new one opens at the next tick.
        book.filter((p) => p.side !== signal).forEach((p) => out(p, bid, ask, "flip", t));
        book = book.filter((p) => p.side === signal); flips++;
        continue;
      }
      for (const side of ["long", "short"]) {
        if ((c.direction !== "both" && c.direction !== side) || t < sidePause[side]) continue;
        const long = side === "long", ps = book.filter((p) => p.side === side), price = long ? ask : bid;
        let add = !ps.length, factor = 1;
        if (!ps.length && sig && (book.length || signal !== side)) continue; // one basket at a time, on the signal's side
        if (!ps.length && useBias && !sig) {
          if (c.bias === "only" && strong !== side) continue;
          if (c.bias === "more" && strong === side) factor = c.biasLotMult || 2;
        }
        if (ps.length) factor = Math.max(1, Math.round(ps[0].lots / c.lots * 100) / 100);
        if (ps.length && ps.length < c.maxLevels) {
          const worst = long ? Math.min(...ps.map((p) => p.entry)) : Math.max(...ps.map((p) => p.entry));
          const best = long ? Math.max(...ps.map((p) => p.entry)) : Math.min(...ps.map((p) => p.entry));
          // Nhồi dương: gridStep further the basket's way than its best entry; nhồi âm: against its worst.
          add = (c.addMode === "with" ? (long ? price - best : best - price) : (long ? worst - price : price - worst)) >= c.gridStep - 1e-9;
          // Signal entry with confirmAdd: a layer only once price turns back the basket's way.
          if (add && sig && c.confirmAdd) add = move != null && (long ? move : -move) >= c.tickMove / 2 - 1e-9;
          // No layer right under a resistance (over a support) before a bar breaks it.
          if (add && sig && c.levelGuard) { const b = levelBlock(c, xLevels, bid); if (b && b[0] === side) add = false; }
        }
        if (!add) continue;
        placed++;
        const lot = gridLot(c, ps.length, factor);
        book.push({ side, entry: price, lots: lot, layer: ps.length + 1, stop: ps.length ? slLevel(ps.concat([{ entry: price, lots: lot }]), long, bpeak[side]) : (c.sl > 0 ? (long ? price - c.sl : price + c.sl) : null), target: null, openTime: t });
        maxLevel = Math.max(maxLevel, ps.length + 1);
      }
      const lots = book.reduce((a, p) => a + p.lots, 0);
      if (lots > maxLots) maxLots = lots;
    }
    if (book.length && ticks.length) { const [ms, bid, ask] = ticks[ticks.length - 1]; book.forEach((p) => out(p, bid, c.noSpread ? bid : ask, "end", ms / 1000)); }
    return { placed, trades, grid: { cycles, stops, sls, trails, flips, guards, blocks, locks, signals, maxFloat, maxLevel, maxLots: Math.round(maxLots * 100) / 100 } };
  }

  /** Bars as a path of prices for the grid bot when no ticks are loaded: open → low → high → close on a
   *  rising bar, open → high → low → close on a falling one, at the given spread. */
  function barsAsTicks(bars, spread) {
    const out = [];
    bars.forEach((b) => {
      const path = b.close >= b.open ? [b.open, b.low, b.high, b.close] : [b.open, b.high, b.low, b.close];
      path.forEach((p, i) => out.push([(b.time + i * 15) * 1000, p, p + spread]));
    });
    return out;
  }

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

  const VOICE_DEFAULTS = { enabled: true, lang: "vi-VN", voice: "", rate: 0.95, pitch: 1, volume: 1, chime: true, target: "", stop: "", entry: "", buy: "", sell: "", details: false, popup: true, notify: false, sessions: true };
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
    voices(forLang) {
      if (!window.speechSynthesis) return [];
      const lang = (forLang || this.cfg.lang).toLowerCase(), short = lang.slice(0, 2);
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

    /** Three short high beeps, whatever the chime setting (price alerts). */
    alarm() {
      const ctx = this.ctx;
      if (!ctx) return;
      if (ctx.state === "suspended") ctx.resume();
      for (let i = 0; i < 3; i++) {
        const o = ctx.createOscillator(), g = ctx.createGain(), t = ctx.currentTime + i * 0.22;
        o.type = "square"; o.frequency.value = 1175;
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.18, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
        o.connect(g).connect(ctx.destination); o.start(t); o.stop(t + 0.18);
      }
    },

    /** `lang` reads it with the best voice of that language instead of the chosen one (English session calls). */
    speak(text, force, good, lang) {
      if ((!force && !this.cfg.enabled) || !text || !window.speechSynthesis) return;
      const say = () => {
        const u = new SpeechSynthesisUtterance(text);
        const voice = lang && !this.cfg.lang.toLowerCase().startsWith(lang.slice(0, 2)) ? this.voices(lang)[0] || null : this.pick();
        u.lang = voice ? voice.lang : lang || this.cfg.lang;
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
    alert(spoken, title, body, good, lang) {
      this.speak(spoken, false, good, lang);
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
    return { theme: "dark", up: "#14b88a", down: "#f0455a", wickUp: "#14b88a", wickDown: "#f0455a", border: true, borderV: 2, borderUp: "#14b88a", borderDown: "#f0455a",
      customBg: false, bg: "#050506", bgType: "theme", bg2: "#2a3550", bgImgOpacity: 35, vGrid: true, hGrid: true, grid: "#1a2233", crosshairMagnet: false, seconds: false,
      askLine: true, bidColor: "#f0455a", askColor: "#2b6bf3", pop: false, popV: 2, tfRing: true, ringColor: "#4068f6" };
  }
  /* Candles that stand out: a colour too close to the background is pushed away from it (lighter on a dark or
   * grey background, darker on a light one), and a body still near the background gets a dark or light edge. */
  function hexRgb(h) {
    h = String(h || "").replace("#", "");
    if (h.length === 3) h = h.split("").map((c) => c + c).join("");
    const n = parseInt(h.slice(0, 6), 16);
    return isNaN(n) ? [0, 0, 0] : [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function lum(c) { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); }
  function contrastOf(a, b) { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }
  function rgbHex(c) { return "#" + c.map((v) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, "0")).join(""); }
  function mixRgb(c, to, t) { return c.map((v, i) => v + (to[i] - v) * t); }
  function rgbHsl([r, g, b]) {
    r /= 255; g /= 255; b /= 255;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
    if (!d) return [0, 0, l];
    const sat = d / (1 - Math.abs(2 * l - 1));
    const h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
    return [(h * 60 + 360) % 360, sat, l];
  }
  function hslRgb([h, sat, l]) {
    const c = (1 - Math.abs(2 * l - 1)) * sat, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
    const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
    return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
  }
  /** The colour moved in lightness (its hue kept, a coloured one made vivid) until it stands out from the background. */
  function standOut(color, bg, min) {
    const c = hexRgb(color), b = hexRgb(bg);
    if (contrastOf(c, b) >= min) return rgbHex(c);
    const [h, sat, l] = rgbHsl(c), s2 = sat > 0.15 ? Math.max(sat, 0.8) : sat;
    const ways = lum(c) >= lum(b) ? [1, -1] : [-1, 1];
    for (const dir of ways) for (let t = 0.02; t <= 1.001; t += 0.02) {
      const nl = l + dir * t;
      if (nl < 0 || nl > 1) break;
      const m = hslRgb([h, s2, nl]);
      if (contrastOf(m, b) >= min) return rgbHex(m);
    }
    return rgbHex(contrastOf([255, 255, 255], b) > contrastOf([0, 0, 0], b) ? [255, 255, 255] : [0, 0, 0]);
  }
  /* The same for the indicators' and drawings' lines: while they paint, a stroke colour too close to the
   * background is moved away from it (and a see-through one made a little stronger); a coloured text or mark too. */
  const POP = { on: false, bg: "#050506", cache: new Map() };
  function parseColor(v) {
    v = v.trim();
    if (v[0] === "#") {
      let h = v.slice(1);
      if (h.length === 3 || h.length === 4) h = h.split("").map((c) => c + c).join("");
      if (!/^[0-9a-f]{6}([0-9a-f]{2})?$/i.test(h)) return null;
      return { rgb: hexRgb(h), a: h.length === 8 ? parseInt(h.slice(6), 16) / 255 : 1 };
    }
    const m = v.match(/^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)(?:[\s,/]+([\d.]+%?))?\s*\)$/i);
    if (!m) return null;
    let a = m[4] == null ? 1 : parseFloat(m[4]);
    if (m[4] && m[4].endsWith("%")) a /= 100;
    return { rgb: [+m[1], +m[2], +m[3]], a };
  }
  function popColor(v, fill) {
    if (!POP.on || typeof v !== "string") return v;
    const key = (fill ? "f" : "s") + v;
    let r = POP.cache.get(key);
    if (r !== undefined) return r;
    r = v;
    const p = parseColor(v);
    if (p) {
      const [, sat, l] = rgbHsl(p.rgb);
      // Fills: only coloured ones (texts and marks in an indicator's colour), never the zones' light shading
      // nor black or white text on a label.
      const take = fill ? p.a >= 0.85 && sat > 0.25 && l > 0.12 && l < 0.88 : p.a >= 0.2;
      if (take) {
        const c = hexRgb(standOut(rgbHex(p.rgb), POP.bg, 3));
        const a = fill || p.a >= 1 ? p.a : Math.min(1, p.a * 1.35);
        r = a >= 1 ? rgbHex(c) : `rgba(${c.map(Math.round).join(",")},${a.toFixed(3)})`;
      }
    }
    if (POP.cache.size > 3000) POP.cache.clear();
    POP.cache.set(key, r);
    return r;
  }
  const CTX_STROKE = Object.getOwnPropertyDescriptor(CanvasRenderingContext2D.prototype, "strokeStyle");
  const CTX_FILL = Object.getOwnPropertyDescriptor(CanvasRenderingContext2D.prototype, "fillStyle");
  /** Sharp lines for the indicator layers (drawn in CSS pixels): every point of a line put on the device
   *  pixel grid (on a pixel's middle for an odd number of device pixels, between two for an even one),
   *  widths in whole device pixels and filled boxes on whole pixels, so nothing is smeared over two. */
  const CTX_P = CanvasRenderingContext2D.prototype;
  const CTX_LW = Object.getOwnPropertyDescriptor(CTX_P, "lineWidth");
  function withCrisp(ctx, paint) {
    if (!ctx || !CTX_LW || !ctx.getTransform) return paint();
    const dpr = Math.abs(ctx.getTransform().a) || window.devicePixelRatio || 1;
    const odd = () => Math.round(CTX_LW.get.call(ctx) * dpr) % 2 === 1;
    const sS = (v) => (odd() ? (Math.floor(v * dpr) + 0.5) / dpr : Math.round(v * dpr) / dpr);
    const sF = (v) => Math.round(v * dpr) / dpr;
    ctx.moveTo = (x, y) => CTX_P.moveTo.call(ctx, sS(x), sS(y));
    ctx.lineTo = (x, y) => CTX_P.lineTo.call(ctx, sS(x), sS(y));
    ctx.strokeRect = (x, y, w, h) => { const x0 = sS(x), y0 = sS(y); CTX_P.strokeRect.call(ctx, x0, y0, sS(x + w) - x0, sS(y + h) - y0); };
    ctx.fillRect = (x, y, w, h) => {
      const x0 = sF(x), y0 = sF(y);
      let ww = sF(x + w) - x0, hh = sF(y + h) - y0;
      if (w && !ww) ww = (w > 0 ? 1 : -1) / dpr;
      if (h && !hh) hh = (h > 0 ? 1 : -1) / dpr;
      CTX_P.fillRect.call(ctx, x0, y0, ww, hh);
    };
    Object.defineProperty(ctx, "lineWidth", { configurable: true, get: () => CTX_LW.get.call(ctx), set: (v) => CTX_LW.set.call(ctx, Math.max(1, Math.round(v * dpr)) / dpr) });
    try { return paint(); } finally { delete ctx.moveTo; delete ctx.lineTo; delete ctx.strokeRect; delete ctx.fillRect; delete ctx.lineWidth; }
  }

  /** Runs a paint with the colours it sets made to stand out (when on); the context is left as it was. */
  function withPop(ctx, paint) {
    if (!POP.on || !ctx || !CTX_STROKE || !CTX_FILL) return withCrisp(ctx, paint);
    Object.defineProperty(ctx, "strokeStyle", { configurable: true, get: () => CTX_STROKE.get.call(ctx), set: (v) => CTX_STROKE.set.call(ctx, popColor(v, false)) });
    Object.defineProperty(ctx, "fillStyle", { configurable: true, get: () => CTX_FILL.get.call(ctx), set: (v) => CTX_FILL.set.call(ctx, popColor(v, true)) });
    try { return withCrisp(ctx, paint); } finally { delete ctx.strokeStyle; delete ctx.fillStyle; }
  }
  window.AurumPop = { wrap: withPop, color: (v) => popColor(v, false) };
  function candleLook(st, bg) {
    const solid = (h, d) => String(h || d).slice(0, 7);
    const look = { up: solid(st.up, "#14b88a"), down: solid(st.down, "#f0455a"), wickUp: solid(st.wickUp, st.up), wickDown: solid(st.wickDown, st.down),
      border: st.border, borderUp: solid(st.borderUp, st.up), borderDown: solid(st.borderDown, st.down) };
    if (!st.pop) return Object.assign(look, { up: st.up, down: st.down, wickUp: st.wickUp, wickDown: st.wickDown, borderUp: st.borderUp, borderDown: st.borderDown });
    const b = hexRgb(bg);
    for (const k of ["up", "down"]) {
      const W = k === "up" ? "wickUp" : "wickDown", B = k === "up" ? "borderUp" : "borderDown";
      look[k] = standOut(look[k], bg, 3);
      look[W] = standOut(look[W], bg, 3);
      const body = hexRgb(look[k]);
      if (contrastOf(body, b) < 3.3) {
        // An edge from the end (black or white) that is furthest from the body, so the body's outline shows.
        const to = contrastOf(body, [0, 0, 0]) >= contrastOf(body, [255, 255, 255]) ? [0, 0, 0] : [255, 255, 255];
        look[B] = rgbHex(mixRgb(body, to, 0.55));
        look.border = true;
      } else look[B] = st.border ? standOut(look[B], bg, 3) : look[k];
    }
    return look;
  }
  function loadChartStyle() {
    try {
      const saved = JSON.parse(store.get("aurum.chartStyle") || "{}") || {};
      const st = Object.assign(defaultChartStyle(), saved);
      if (st.askColor === "#f5a524") st.askColor = defaultChartStyle().askColor; // the first, single-line look
      // Candle edges on (TradingView's look: sharp bodies even when thin), once for styles saved before.
      if (st.borderV !== 2) { st.border = true; st.borderUp = st.up; st.borderDown = st.down; st.borderV = 2; }
      // "Nổi bật" changed the chosen colours: off again, the colours exactly as picked (it can be turned on).
      if (saved.popV !== 2) { st.pop = false; st.popV = 2; }
      // Background: the theme's, one colour, a gradient (top → bottom) or a picture (TradingView's choices + image).
      if (!["theme", "solid", "gradient", "image"].includes(saved.bgType)) st.bgType = saved.customBg ? "solid" : "theme";
      return st;
    } catch { return defaultChartStyle(); }
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

  // Axis text: black (white on dark) and bold. Lightweight Charts has no font-weight option, so the
  // family is a bold face under its own name (style.css), falling back to the system font.
  const AXIS_FAMILY = "AurumAxis, -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
  const axisFont = (bg, light) => ({ background: { color: bg }, textColor: light ? "#000000" : "#f1f4f9", fontFamily: AXIS_FAMILY, fontSize: 12 });
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
    curve: svg(`<path d="M5 21Q14 -1 23 21"/>${dot(5, 21)}${dot(14, 10)}${dot(23, 21)}`),
    text: svg(`<path d="M7 7h14M14 7v15M11 22h6"/>`),
  };
  /** The trade characters' pictures: size on the chart, where the fishing line / the rope starts (picture coordinates). */
  const CREW = {
    get scale() { return +(store.get("aurum.crewScale") || 0.6); },
    /** "shadow" (silhouettes with a golden rim, the default) or "anime". */
    get style() { return store.get("aurum.crewStyle") === "anime" ? "anime" : "shadow"; },
    /** How long the money / snapped picture stays after a TP / SL. */
    endMs: 1200,
    get folder() { return this.style === "anime" ? "assets/crew" : "assets/crew2"; },
    /** Where the line starts in each picture (made with the pictures by tools/mascots/build.py). */
    get points() { const p = window.CREW_POINTS || { angler: {}, hauler: {} }; return this.style === "anime" ? p : p.shadow || p; },
  };

  /** What each mascot picture shows. */
  const MASCOT_MOODS = { rich: "lãi đậm", happy: "vui mừng", tea: "nhâm nhi trà (đi ngang)", sleep: "ngủ gật (im lìm)", nervous: "hồi hộp (sắp có tin)",
    cry: "khóc (giá đi ngược)", shock: "hồn lìa khỏi xác", angry: "tức điên (dính SL)", trophy: "ăn mừng TP" };

  const RAIL_ICON = {
    mascot: svg(`<circle cx="14" cy="11" r="6"/><path d="M8 9c1-4 11-4 12 0M11.5 11h.01M16.5 11h.01M12 14c1 1 3 1 4 0M7 25c1-5 4-8 7-8s6 3 7 8"/>`),
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
    { id: "shapes", title: "Hình học", tools: ["brush", "rectangle", "ellipse", "curve", "arrowMarker"] },
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
      document.querySelectorAll("#dashView .tab").forEach((el) => {
        el.hidden = el.dataset.tab !== this.tab && el.dataset.tab !== this.sideTab;
        el.classList.toggle("side-tab", el.dataset.tab === this.sideTab);
      });
      document.body.classList.toggle("side-open", !!this.sideTab);
      document.body.classList.toggle("on-chart", this.tab === "chart");
      if (this.tab === "chart" && this.fitReady) requestAnimationFrame(() => this.fitChart());
      if (this.tab !== "chart" && document.body.classList.contains("chart-full")) this.setFull(false);
      this.renderFavBar();
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
      $("chartNote").title = $("chartNote").textContent;
      if (!this.owner) {
        try { await this.refreshMe(); } catch (e) { if (this.handleAuth(e)) return; }
      }
      if (this.owner) await this.pickAccountServer();
      this.renderTabs();
      this.buildChart();
      await this.refresh();
      this.loadTab(true);
      this.loadNews();
      this.stop(false);
      this.timers.push(setInterval(() => this.refresh(), this.owner ? 2000 : 5000));
      this.timers.push(setInterval(() => { this.loadTab(false); if (this.sideTab) this.loadTab(false, this.sideTab); }, 5000));
      this.timers.push(setInterval(() => this.updateTab(), 1000));
      if (!this.owner) this.timers.push(setInterval(() => this.refreshMe().catch((e) => this.handleAuth(e)), 30000));
      this.timers.push(setInterval(() => this.loadNews(), 5 * 60 * 1000));
      if (this.owner) {
        const badge = () => {
          this.botCall("/status").then((st) => { this.botStatus = st; this.renderBotBadge(); }).catch(() => {});
          this.botCall("/stopbot").then((st) => { this.stopStatus = st; this.renderBotBadge(); }).catch(() => {});
        };
        badge();
        this.timers.push(setInterval(badge, 15000));
      }
      this.timers.push(setInterval(() => this.updateFlow(), 1000));
      if (!this.visibilityBound) {
        // Back from another tab or a locked phone: catch up at once instead of on the next timer.
        this.visibilityBound = true;
        let hiddenAt = 0;
        document.addEventListener("visibilitychange", () => {
          if (document.hidden) { hiddenAt = Date.now(); return; }
          if (!this.chart || this.replay || !hiddenAt) return;
          const away = (Date.now() - hiddenAt) / 1000;
          hiddenAt = 0;
          if (away < 3) return;
          // Second bars come from a live stream that may have dropped while away: reload them.
          // The extra timeframes: their streams may have dropped too.
          if (away > 15) (this.panes || []).forEach((p) => { if (!p.timer) p.load(); });
          if (isSecTF(this.interval) || this.source === "binance") { if (away > 15) this.loadCandles(); return; }
          if (this.pollTimer && this.source === "exness") this.pollBars(this.loadToken);
          if (this.cmpBars && this.cmpBars.length && this.pair()) this.loadCmp();
        });
      }
    },

    stop(all = true) {
      this.timers.forEach(clearInterval);
      this.timers = [];
      if (all) {
        this.updateTab(true);
        clearInterval(this.pollTimer); this.pollTimer = null;
        if (this.socket) { this.socket.close(); this.socket = null; }
        this.stopTicks();
        (this.panes || []).forEach((p) => p.stop());
      }
    },

    /** One call; when the address moved, find the new one and try again. */
    /** The bots' server: the second copy (the computer's own MT5 account) when it runs and "Bot chạy trên tài
     *  khoản riêng" is on, else the main one. Charts and manual trading always stay on the main account. */
    async pickAccountServer() {
      this.mainBase = this.mainBase || this.base;
      this.botBase = null;
      this.ownAccount = false;
      if (store.get("aurum.useWebAcct") !== "1") return;
      try {
        const st = await api(this.mainBase, this.secret, "/status");
        const w = st.webAccount;
        if (w && w.enabled && w.running && w.url) { this.botBase = w.url; this.ownAccount = true; }
      } catch { /* the main server will do */ }
    },
    mainCall(path, body) { return api(this.mainBase || this.base, this.secret, path, body); },
    /** A call for the bots (their own server when it runs). */
    async botCall(path, body) {
      if (!this.botBase) return this.call(path, body);
      try {
        return await api(this.botBase, this.secret, path, body);
      } catch (e) {
        if (!(e instanceof Unreachable)) throw e;
        await this.pickAccountServer();
        return this.botBase ? api(this.botBase, this.secret, path, body) : this.call(path, body);
      }
    },

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
      this.lastTrading = t;
      $("whoName").textContent = "Chủ máy chủ";
      $("whoRole").style.cursor = "pointer";
      $("whoRole").title = "Đổi / đăng nhập tài khoản MT5";
      $("whoRole").onclick = () => { this.setTab("bot"); const b = $("mt5Login"); if (b) { if (!b.innerHTML) this.renderMt5Login(); b.scrollIntoView({ behavior: "smooth" }); } };
      $("whoRole").innerHTML = (t.login
        ? `#${t.login} · ${esc(t.server || "")} <span class="acct ${t.mode === "real" ? "real" : ""}" title="${t.mode === "real" ? "Tài khoản thật" : "Tài khoản demo"}">✦</span>`
        : "MT5 chưa đăng nhập");
      const floating = this.floating();
      if (!sym && !this.symbol) await this.ownerSymbol();
      this.renderPill(floating);
      this.renderSelBar();
      this.syncLines2();
      if (this.shown("trade")) this.renderTrade();
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

    /** Only the pill's money changes with each quote (rebuilding it would drop a tap on its ✕). */
    pillMoney() {
      const b = $("posPill").querySelector(".go b");
      if (!b) return this.renderPill(this.floating());
      const v = this.floating();
      b.textContent = signed(v); b.className = v >= 0 ? "pos" : "neg";
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
        // The server closes them all and tries again those the broker turns down (3.3+); an older one, one by one.
        let res = null;
        try { res = await this.call("/mt5/close_all", { tickets: list.map((p) => p.ticket) }); } catch (e) {
          if (!/Không có đường dẫn|404/.test(e.message || "")) throw e;
          for (const p of list) await this.call("/mt5/close", { ticket: p.ticket });
        }
        if (res && res.left) throw new Error(`Còn ${res.left} lệnh chưa đóng được${res.error ? ": " + res.error : ""}. Bấm Đóng tất cả lần nữa.`);
      }, "Đã đóng tất cả lệnh");
      this.refresh();
    },

    renderTrade() {
      const t = this.account || {};
      const cur = t.currency || "USD";
      const floating = this.floating();
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
          <div class="lv">SL ${p.stop ? fmt(p.stop, this.digitsFor(p.symbol)) + this.levelMoney(this.pnlAt(p, p.stop)) : "–"} · TP ${p.target ? fmt(p.target, this.digitsFor(p.symbol)) + this.levelMoney(this.pnlAt(p, p.target)) : "–"} · ${clock(p.time)}${p.bot ? " · bot" : ""}</div>
        </div>
        <div class="right"><div class="move ${this.liveProfit(p) >= 0 ? "pos" : "neg"}">${signed(this.liveProfit(p))}</div></div>
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
          <div class="lv">SL ${o.stop ? fmt(o.stop, this.digitsFor(o.symbol)) + this.levelMoney(this.valueAt(o.symbol, o.lots, o.side, o.entry, o.stop)) : "–"} · TP ${o.target ? fmt(o.target, this.digitsFor(o.symbol)) + this.levelMoney(this.valueAt(o.symbol, o.lots, o.side, o.entry, o.target)) : "–"} · ${clock(o.time)}</div>
        </div>
        <div class="right"></div>
        <button class="x" type="button" title="Huỷ lệnh chờ">✕</button>
      </div>`;
    },

    /** " (−23.10)" after a SL / TP price: the money if it is hit, red or green. */
    levelMoney(v) {
      if (v == null || !isFinite(v)) return "";
      return ` <b class="lv-usd ${v >= 0 ? "pos" : "neg"}">${signed(v)}</b>`;
    },

    /** Under the SL / TP boxes of a sheet: what each price would bring, in the account's money, as it is typed. */
    bindLevelMoney(el, ids, moneyAt) {
      const cur = esc((this.account || {}).currency || "USD");
      ids.forEach(([inputId, kind]) => {
        const input = el.querySelector("#" + inputId);
        if (!input) return;
        const out = document.createElement("span");
        out.className = "lvl-usd";
        input.after(out);
        const show = () => {
          const v = moneyAt(num(input.value));
          out.className = "lvl-usd " + (v == null || !isFinite(v) ? "" : v >= 0 ? "pos" : "neg");
          out.textContent = v == null || !isFinite(v) ? (kind === "sl" ? "Chạm SL: —" : "Chạm TP: —")
            : `${kind === "sl" ? "Chạm SL" : "Chạm TP"}: ${signed(v)} ${cur}`;
        };
        input.addEventListener("input", show);
        show();
      });
    },

    digitsFor(symbol) { return symbol === this.symbol ? this.digits : (/JPY/.test(symbol) ? 3 : (/XAU|XAG|US30|USTEC|NAS|BTC/.test(symbol) ? 2 : 5)); },

    positionSheet(p) {
      if (!p) return;
      const d = this.digitsFor(p.symbol);
      sheet.open(`<h3>${sideName(p.side)} ${p.lots} ${esc(p.symbol)} <span class="muted small">#${p.ticket}</span></h3>
        <p class="muted small">Vào ${fmt(p.entry, d)} · giá ${fmt(p.price, d)} · ${fullTime(p.time)}</p>
        <p class="big ${this.liveProfit(p) >= 0 ? "pos" : "neg"}">${signed(this.liveProfit(p))} ${esc((this.account || {}).currency || "USD")}</p>
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
        this.bindLevelMoney(el, [["sStop", "sl"], ["sTarget", "tp"]], (price) => (price ? this.pnlAt(p, price) : null));
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
        const entryNow = () => num(el.querySelector("#oPrice").value) || o.entry;
        this.bindLevelMoney(el, [["oStop", "sl"], ["oTarget", "tp"]], (price) => (price ? this.valueAt(o.symbol, o.lots, o.side, entryNow(), price) : null));
        el.querySelector("#oPrice").addEventListener("input", () => ["oStop", "oTarget"].forEach((id) => el.querySelector("#" + id).dispatchEvent(new Event("input"))));
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

    /** A lot box was changed: keep it, and while replaying keep the ticket's and the replay bar's the same
     *  (BUY / SELL on either places the backtest order). */
    setLots(input, key) {
      store.set(key, input.value);
      if (!this.replay) return;
      const other = input.id === "rLots" ? $("lotInput") : input.id === "lotInput" ? $("rLots") : null;
      if (!other) return;
      other.value = input.value;
      store.set(other.id === "rLots" ? "aurum.rlots" : "aurum.lots", input.value);
    },

    /** − / + on a lot box: 0.01 a step under 1 lot, 0.1 under 10, then 1. */
    stepLots(input, dir, key) {
      const v = clampLots(num(input.value));
      const step = dir > 0 ? (v < 1 ? 0.01 : v < 10 ? 0.1 : 1) : (v <= 1 ? 0.01 : v <= 10 ? 0.1 : 1);
      input.value = clampLots(v + step * dir).toFixed(2);
      this.setLots(input, key);
      if (this.draft) this.updatePendingLabels();
    },

    /** Lot choices under a lot box, up to the most allowed (200 lot, or the server's limit). */
    lotMenu(input, key) {
      const menu = $("ctxMenu");
      // The broker's limit is for real orders; a backtest takes up to MAX_LOTS.
      const serverMax = !this.replay && this.owner && this.account && this.account.maxLots ? +this.account.maxLots : null;
      const max = Math.min(MAX_LOTS, serverMax || MAX_LOTS);
      const list = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200];
      const cur = clampLots(num(input.value));
      menu.innerHTML = `<div class="lot-menu">${list.map((v) => `<button type="button" data-v="${v}" class="${cur === v ? "on" : ""} ${v > max ? "over" : ""}" ${v > max ? `title="Vượt giới hạn máy chủ ${max} lot"` : ""}>${v}</button>`).join("")}
        <button type="button" data-v="${max}" class="max">MAX · ${max} lot</button></div>
        ${serverMax && serverMax < MAX_LOTS ? `<p class="muted small lot-note">Máy chủ đang cho tối đa ${serverMax} lot mỗi lệnh.</p><button type="button" class="lot-raise" data-raise>Nâng giới hạn máy chủ lên ${MAX_LOTS} lot</button>` : `<p class="muted small lot-note">${this.replay ? "Backtest: t" : "T"}ối đa ${MAX_LOTS} lot mỗi lệnh.</p>`}`;
      menu.hidden = false;
      const r = input.getBoundingClientRect();
      menu.style.left = Math.max(8, Math.min(r.left - 60, window.innerWidth - menu.offsetWidth - 8)) + "px";
      menu.style.top = Math.min(r.bottom + 6, window.innerHeight - menu.offsetHeight - 8) + "px";
      menu.querySelectorAll("[data-v]").forEach((b) => (b.onclick = () => {
        input.value = clampLots(+b.dataset.v).toFixed(2);
        this.setLots(input, key);
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

    /** The side at `price` with a Stop (`stop` true) or Limit order. */
    draftSideAs(price, stop) {
      const last = this.bars.length ? this.bars[this.bars.length - 1].close : price;
      const mid = this.bid != null && this.ask != null ? (this.bid + this.ask) / 2 : last;
      const below = price < mid;
      return stop ? (below ? "short" : "long") : (below ? "long" : "short");
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

    /** The pending order being set up, confirmed right on the chart (the full form is under it).
     *  SL and TP are typed right here, removed with their ✕ or added back with + SL / + TP. */
    renderDraftBar(price, side, kind) {
      const bar = $("draftBar");
      if (!this.draft || price == null) { bar.hidden = true; return; }
      // Typing in a field: keep it (a redraw would drop the caret); the money updates on Enter / leaving it.
      if (bar.contains(document.activeElement) && document.activeElement.tagName === "INPUT") return;
      const sl = num($("pStop").value), tp = num($("pTarget").value), lots = this.lots();
      const money = (lv) => { const v = this.valueAt(this.symbol, lots, side, price, lv); return `<span class="${(v || 0) >= 0 ? "pos" : "neg"}">${money0(v)}</span>`; };
      const field = (f, name, lv) => lv == null
        ? `<button type="button" class="dadd ${f}" data-add="${f}">+ ${name}</button>`
        : `<span class="dfield ${f}"><em>${name}</em><input data-f="${f}" inputmode="decimal" value="${fmt(lv, this.digits)}" size="${fmt(lv, this.digits).length}">${money(lv)}<button type="button" data-del="${f}" title="Bỏ ${name}">✕</button></span>`;
      bar.hidden = false;
      const other = this.pendingKind(this.draftSideAs(price, !$("pStopType").checked)).replace(/ .*/, "") + " " + ($("pStopType").checked ? "LIMIT" : "STOP");
      bar.innerHTML = `<button type="button" class="dk ${side === "long" ? "buy" : "sell"}" data-a="kind" title="Bấm để đổi sang ${other} (cùng giá)">${kind} <span class="dk-swap">⇄</span></button>
        <span><b>${lots.toFixed(2)}</b> @ <b>${fmt(price, this.digits)}</b></span>
        ${field("stop", "SL", sl)}${field("target", "TP", tp)}
        <button type="button" class="go ${side === "long" ? "buy" : "sell"}" data-a="place">Đặt lệnh</button>
        <button type="button" class="x" data-a="cancel" title="Huỷ">✕</button>`;
      const input = (f) => $(f === "stop" ? "pStop" : "pTarget");
      const apply = () => { this.readDraftDist(); this.updatePendingLabels(); this.syncLines(); };
      bar.querySelectorAll("input[data-f]").forEach((i) => {
        i.onkeydown = (e) => { if (e.key === "Enter") i.blur(); if (e.key === "Escape") { i.value = input(i.dataset.f).value; i.blur(); } };
        i.onchange = () => {
          const v = num(i.value), long = side === "long", isStop = i.dataset.f === "stop";
          // SL under a buy's entry and above a sell's; TP the other way.
          if (v == null || (isStop === long ? v >= price : v <= price)) { toast(`${isStop ? "SL" : "TP"} của lệnh ${long ? "MUA" : "BÁN"} phải ${isStop === long ? "thấp" : "cao"} hơn giá vào ${fmt(price, this.digits)}`, true); i.value = input(i.dataset.f).value; return; }
          input(i.dataset.f).value = fmt(v, this.digits);
          setTimeout(apply);
        };
      });
      bar.querySelectorAll("[data-del]").forEach((b) => (b.onclick = () => { input(b.dataset.del).value = ""; apply(); }));
      bar.querySelectorAll("[data-add]").forEach((b) => (b.onclick = () => {
        // Back at the last distance used, else three average candles away (TP twice that).
        const tail = this.bars.slice(-30), long = side === "long", isStop = b.dataset.add === "stop";
        const r = tail.length ? tail.reduce((a, x) => a + x.high - x.low, 0) / tail.length : price * 0.0005;
        const dist = (isStop ? this.draftDist && this.draftDist.risk : this.draftDist && this.draftDist.reward) || r * (isStop ? 3 : 6);
        input(b.dataset.add).value = fmt(price + (isStop === long ? -1 : 1) * dist, this.digits);
        apply();
      }));
      // LIMIT ⇄ STOP at the same price: the side turns over (above the price: SELL LIMIT ⇄ BUY STOP), SL / TP with it.
      bar.querySelector("[data-a=kind]").onclick = () => {
        this.readDraftDist();
        $("pStopType").checked = !$("pStopType").checked;
        this.placeDraftStops(); this.updatePendingLabels(); this.syncLines();
      };
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
        // The entry starts in the middle of the chart in view (not off its bottom), with SL / TP inside it too.
        // The chart under the BUY / SELL box: the entry in its middle, SL / TP inside it (so the scale stays put).
        const ph = (this.chart.paneSize ? this.chart.paneSize().height : 0) || $("chart").clientHeight;
        const tk = $("ticket");
        const v0 = Math.min(ph * 0.5, tk && !tk.hidden ? tk.offsetTop + tk.offsetHeight + 12 : 12);
        // …and above the order bar that opens at the chart's foot (taller on a phone).
        const v1 = Math.max(v0 + 40, ph - (innerWidth < 600 ? 160 : 64));
        const mid = this.series.coordinateToPrice((v0 + v1) / 2);
        const hi = this.series.coordinateToPrice(v0), lo = this.series.coordinateToPrice(v1);
        if (!num($("pPrice").value) && last) {
          let entry = mid != null ? mid : last - r * 3;
          // Right on the price it would fill at once: a little below (or above, if below is out of view).
          if (Math.abs(entry - last) < r) {
            // Halfway between the price and the edge with more room, leaving room for the SL beyond it.
            const below = hi == null || lo == null || last - lo >= hi - last, side = hi != null && lo != null ? (below ? last - lo : hi - last) : r * 6;
            const off = Math.min(Math.max(r, side * 0.45), side * 0.6);
            entry = below ? last - off : last + off;
          }
          $("pPrice").value = fmt(entry, this.digits);
        }
        if (!this.draftDist) this.draftDist = { risk: +(r * 3).toFixed(this.digits), reward: +(r * 6).toFixed(this.digits) };
        // SL on one side of the entry, TP on the other: both inside the chart (same R:R, shorter if needed).
        const at = num($("pPrice").value);
        if (hi != null && lo != null && at != null && at < hi && at > lo) {
          const long = this.draftSide(at) === "long", up = (hi - at) * 0.9, down = (at - lo) * 0.9;
          const riskRoom = long ? down : up, rewardRoom = long ? up : down;
          const k = Math.min(1, this.draftDist.risk ? riskRoom / this.draftDist.risk : 1, this.draftDist.reward ? rewardRoom / this.draftDist.reward : 1);
          if (k < 1) this.draftDist = { risk: +((this.draftDist.risk || 0) * k).toFixed(this.digits), reward: +((this.draftDist.reward || 0) * k).toFixed(this.digits) };
        }
        this.draft = true;
        this.placeDraftStops();
        // On a small screen, bring that line to the middle of the screen.
        requestAnimationFrame(() => requestAnimationFrame(() => {
          const y = this.series.priceToCoordinate(num($("pPrice").value));
          if (y == null) return;
          const sy = $("chart").getBoundingClientRect().top + y;
          if (sy < innerHeight * 0.3 || sy > innerHeight * 0.7) window.scrollBy({ top: sy - innerHeight / 2, behavior: "smooth" });
        }));
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
      if (this.shown("signals")) this.renderSignals();
    },

    /* ----- voice alerts ----- */

    /** New fills and closes since the last look (the first look only learns what is there, like the app). */
    watchTrades(t) {
      const deals = t.deals || [], positions = t.positions || [];
      // (The positions as they were, for the trade characters of the ones that just closed.)
      const prevPositions = this.crewSeen || [];
      this.crewSeen = positions;
      this.crewPrev = prevPositions;
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
        this.mascotEvent = { win: d.profit >= 0, at: Date.now() };
        if (d.reason === "target" || d.reason === "stop") {
          const p = (this.crewPrev || []).find((x) => (d.position != null ? x.ticket === d.position : x.symbol === d.symbol) && !positions.some((y) => y.ticket === x.ticket));
          if (p && p.target) this.crewEnded({ key: "pos:" + p.ticket, buy: p.side === "long", entry: p.entry, tp: p.target, sl: p.stop }, d.reason === "target");
        }
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
          + k.head("Phiên giao dịch")
          + `<div class="fr"><button type="button" class="btn btn-ghost btn-small" data-sess>⚙ Thông báo mở / kết thúc phiên Á · Âu · New York…</button></div>`
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
          { const sb = panel.querySelector("[data-sess]"); if (sb) sb.onclick = () => this.sessSettingsSheet(); }
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

    /** A section is on screen: the current tab, or the one open beside the full-screen chart. */
    shown(t) { return this.tab === t || this.sideTab === t; },

    loadTab(first, t = this.tab) {
      if (!this.secret) return;
      if (t === "trade" && first) this.renderTrade();
      if (t === "signals" && first) this.renderSignals();
      if (t === "history" && first) this.loadHistory();
      if (t === "news" && first) { this.renderNews(); this.loadNews(true); }
      if (t === "copy") this.loadCopy(first);
      if (t === "members" && first) this.loadMembers();
      if (t === "bot") this.loadBot(first);
      if (t === "autobot") {
        this.applyBotHub();
        Promise.allSettled([this.loadAutoBot(first), this.loadStopBot(first), this.loadSRBot(first), this.loadTickBot(first), this.loadGridBot(first)]).then(() => this.applyBotHub());
      }
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
        this.loadLotTotals();
      } catch (e) {
        $("histList").innerHTML = `<div class="empty">${esc(plain(e.message))}</div>`;
      }
    },

    /** Lots traded today, yesterday and over the whole account, whatever range the list shows. */
    async loadLotTotals() {
      const box = $("histLots");
      const show = (t) => {
        const cell = (k, v, n) => `<div class="ls"><span>${k}</span><b>${v == null ? "…" : v.toFixed(2)} <small>lot</small></b><em>${n == null ? "" : n + " lệnh"}</em></div>`;
        box.innerHTML = cell("Hôm nay", t && t.today.lots, t && t.today.n) + cell("Hôm qua", t && t.yesterday.lots, t && t.yesterday.n) + cell("Tất cả", t && t.all.lots, t && t.all.n);
      };
      // Read again at most once a minute (the whole account's history can be long).
      if (this.lotTotals && Date.now() - this.lotTotals.at < 60000) return show(this.lotTotals);
      show(this.lotTotals || null);
      try {
        const h = await this.call(`/mt5/history?from=1262304000&to=${Math.ceil(Date.now() / 1000 + 60)}`);
        const [today] = this.rangeTimes("today"), [yStart, yEnd] = this.rangeTimes("yesterday");
        const sum = (list) => ({ lots: list.reduce((a, p) => a + (p.lots || 0), 0), n: list.length });
        const all = h.positions || [];
        this.lotTotals = {
          at: Date.now(), all: sum(all),
          today: sum(all.filter((p) => p.closeTime >= today)),
          yesterday: sum(all.filter((p) => p.closeTime >= yStart && p.closeTime < yEnd)),
        };
        show(this.lotTotals);
      } catch {
        if (!this.lotTotals) box.innerHTML = "";
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
        if (this.shown("news")) this.renderNews();
        // The release times on the chart and the next one's countdown.
        this.renderNewsStrip();
        if (this.requestICT) this.requestICT();
      } catch (e) {
        if (this.shown("news")) $("newsList").innerHTML = `<div class="empty">${esc(plain(ServerTooOld(e) ? "Cập nhật máy chủ lên bản mới để xem tin tức" : e.message))}</div>`;
      }
    },

    goldEvents(minRank) {
      // Kept until the news change: the chart asks for them every frame.
      const list = (this.news && this.news.events) || [], memo = this.goldMemo;
      if (memo && memo.list === list && memo.rank === minRank) return memo.out;
      const rank = { High: 3, Medium: 2, Low: 1 };
      const out = list.filter((e) => e.country === "USD" && (rank[e.impact] || 0) >= minRank);
      this.goldMemo = { list, rank: minRank, out };
      return out;
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
        const st = await this.botCall("/stopbot");
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
        const r = await act(button, () => this.botCall("/stopbot", Object.assign(body(), extra)), done);
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
          <div class="lv">SL ${o.stop ? fmt(o.stop, d(o.symbol)) : "–"} · TP ${o.target ? fmt(o.target, d(o.symbol)) : "–"}${o.trail != null ? ` · <b class="pos">trailing ${fmt(o.trail, d(o.symbol))}</b>` : ""}</div></div>
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
      try { st = await this.botCall("/srbot"); } catch (e) { problem = ServerTooOld(e) ? "Cập nhật máy chủ lên bản 3.1 (tab Máy chủ → Cập nhật) để chạy bot này; backtest ở dưới vẫn dùng được." : plain(e.message); }
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
        const r = await act(button, () => this.botCall("/srbot", Object.assign(this.srSettings(), extra)), done);
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
          <div class="lv">SL ${o.stop ? fmt(o.stop, d(o.symbol)) : "–"} · TP ${o.target ? fmt(o.target, d(o.symbol)) : "–"}${o.trail != null ? ` · <b class="pos">trailing ${fmt(o.trail, d(o.symbol))}</b>` : ""}</div></div>
          <div class="right"><div class="move ${(o.profit || 0) >= 0 ? "pos" : "neg"}">${signed(o.profit || 0)}</div></div></div>`).join("")}</div>
        ${(st.events || []).length ? `<h4>Hoạt động</h4><div class="list log">${st.events.slice(0, 15).map((e) => `<div class="log-row"><span class="muted small">${clock(e.time)}</span> ${esc(e.text)}</div>`).join("")}</div>` : ""}`;
    },

    /* ----- the Bot box: one bot at a time, and how it runs ----- */

    applyBotHub() {
      const BOTS = [["strategy", "📈 Chiến lược (ICT / mẫu)"], ["stop", "🎯 Stop theo nến"], ["sr", "🧱 Cản & Hỗ trợ"], ["tick", "⚡ Nến tick"], ["grid", "🕸️ Nhồi lệnh (grid)"]];
      const MODES = [["backtest", "🧪 Backtest", "chạy trên nến đã qua"], ["demo", "🎮 Chạy thử", "tiền ảo, không đặt lệnh thật"], ["mt5", "💹 Tài khoản MT5", "Exness demo / thật"]];
      let bot = store.get("aurum.hubBot") || "strategy", mode = store.get("aurum.hubMode") || "demo";
      if (!BOTS.some(([k]) => k === bot)) bot = "strategy";
      if (!MODES.some(([k]) => k === mode)) mode = "demo";
      const bots = $("hubBots"), modes = $("hubModes");
      if (!bots || !modes) return;
      bots.innerHTML = BOTS.map(([k, n]) => `<button type="button" data-b="${k}" class="${k === bot ? "on" : ""}">${n}</button>`).join("");
      modes.innerHTML = MODES.map(([k, n, sub]) => `<button type="button" data-m="${k}" class="${k === mode ? "on" : ""}"><b>${n}</b><span>${sub}</span></button>`).join("");
      bots.querySelectorAll("[data-b]").forEach((b) => (b.onclick = () => { store.set("aurum.hubBot", b.dataset.b); this.applyBotHub(); }));
      modes.querySelectorAll("[data-m]").forEach((b) => (b.onclick = () => { store.set("aurum.hubMode", b.dataset.m); this.applyBotHub(); }));
      // The MT5 account in use: demo or real (from the last trading status).
      const t = this.lastTrading || {}, acct = $("hubAcct");
      if (acct) {
        acct.textContent = t.login ? `MT5 #${t.login} · ${t.mode === "real" ? "TÀI KHOẢN THẬT" : "demo"}` : "MT5 chưa đăng nhập";
        acct.className = "badge " + (t.login ? (t.mode === "real" ? "real" : "on") : "off");
      }
      const key = bot + ":" + mode;
      document.querySelectorAll("#botHub [data-hub]").forEach((el) => { el.hidden = !el.dataset.hub.split(" ").includes(key); });
      if (!this.botLiveTimer) this.botLiveTimer = setInterval(() => this.renderBotLive(), 4000);
      this.renderBotLive();
      // The strategy bot: demo on the server or orders on MT5, set from the mode.
      const broker = $("abBroker"), source = $("abSource");
      if (bot === "strategy" && broker && mode !== "backtest") {
        broker.value = mode === "mt5" ? "mt5" : "paper";
        if (mode === "mt5" && source) { source.value = "mt5"; if (source.onchange) source.onchange(); }
        broker.closest("label").hidden = true;
      }
      // The tick bot's start button says where it will trade (virtual or MT5).
      if (bot === "tick" && this.tickStatus && $("tbForm") && !(this.tickStatus.config || {}).running && !$("tickBotPanel").contains(document.activeElement)) this.renderTickBot(this.tickStatus, "");
      if (bot === "grid" && this.gridStatus && $("gbForm") && !(this.gridStatus.config || {}).running && !$("gridBotPanel").contains(document.activeElement)) this.renderGridBot(this.gridStatus, "");
      // The backtest box tests the bot picked here.
      const btBot = $("btBot");
      if (btBot && (bot === "stop" || bot === "sr" || bot === "tick" || bot === "grid")) { btBot.value = bot; btBot.closest("label").hidden = true; }
      if ($("btOptWrap")) $("btOptWrap").hidden = bot !== "tick";
      if ($("btSrcWrap")) $("btSrcWrap").hidden = bot !== "tick" && bot !== "grid";
      const notes = {
        "strategy:backtest": "Backtest chiến lược (ICT, mẫu, tự viết) chạy trong app iPhone: Backtest → chọn chiến lược. Trên web, chọn bot 🎯 Stop theo nến hoặc 🧱 Cản & Hỗ trợ để backtest.",
        "strategy:demo": "Chạy thử: bot chạy trên máy chủ với tài khoản ảo (số dư đặt lại được), không đặt lệnh lên MT5.",
        "strategy:mt5": "Bot đặt lệnh trên tài khoản MT5 đang đăng nhập. Muốn chạy thử an toàn: đăng nhập tài khoản DEMO Exness (bấm tên tài khoản góc trên) rồi bật bot.",
        "stop:demo": "Bot Stop theo nến đặt lệnh trực tiếp trên MT5 nên không có tài khoản ảo: để chạy thử, đăng nhập tài khoản DEMO Exness rồi bật bot dưới đây (hoặc chạy 🧪 Backtest).",
        "sr:demo": "Bot Cản & Hỗ trợ đặt lệnh trực tiếp trên MT5 nên không có tài khoản ảo: để chạy thử, đăng nhập tài khoản DEMO Exness rồi bật bot dưới đây (hoặc chạy 🧪 Backtest).",
        "tick:backtest": "Backtest trên nến Exness đã qua với đúng cài đặt của bot: đường đi giá trong mỗi cây nến lấy từ nến 1 phút (khung 1m: mở → thấp → cao → đóng với nến tăng, ngược lại với nến giảm — chỉ là ước lượng, giá thật còn lên xuống nhiều hơn trong nến). Mua khớp giá Ask, bán ở Bid.",
        "tick:demo": "Chạy thử: bot chạy trên máy chủ theo giá Exness thật từng tick, lệnh và số dư là ẢO (không đặt lệnh lên MT5, kể cả khi đang đăng nhập tài khoản thật).",
        "grid:backtest": "Backtest bot nhồi lệnh trên tick thật Exness (tối đa 2 ngày) hoặc trên nến 1 phút (ước lượng). Xem kỹ ô 'Âm sâu nhất khi đang gồng': đó là số tiền tài khoản phải chịu được.",
        "grid:demo": "Chạy thử: bot nhồi lệnh chạy trên máy chủ theo giá Exness thật từng tick, lệnh và số dư là ẢO (không đặt lệnh lên MT5).",
        "grid:mt5": "Bot nhồi lệnh đặt lệnh THẬT trên tài khoản MT5 đang đăng nhập (bắt buộc có SL rổ hoặc Cắt lỗ chung). Nên chạy trên tài khoản DEMO Exness trước.",
      };
      const real = t.login && t.mode === "real" && mode !== "backtest" && !(mode === "demo" && (bot === "strategy" || bot === "tick" || bot === "grid"));
      $("hubNote").innerHTML = (notes[key] ? esc(notes[key]) : "") + (real ? `<div class="warn">⚠️ Đang đăng nhập TÀI KHOẢN THẬT: bot sẽ đặt lệnh bằng tiền thật.</div>` : "");
    },

    /* ----- the Bot box's own chart and profit history (the bot runs on the VPS: this only watches it) ----- */

    /** The chosen bot as the chart needs it: market, timeframe, open positions and closed trades. */
    botView() {
      const bot = store.get("aurum.hubBot") || "strategy";
      const norm = (h) => ({ side: h.side, spreadCost: h.spreadCost, entry: h.entry ?? h.entryPrice ?? null, exit: h.exit ?? h.exitPrice ?? null,
        openTime: h.openTime ?? h.entryTime ?? null, closeTime: h.closeTime ?? h.exitTime ?? null, profit: +h.profit || 0, lots: h.lots, reason: h.reason });
      const pick = (st, name) => st && st.config ? { name, running: !!st.config.running, paper: !!st.config.paper, symbol: st.config.symbol, interval: st.config.interval || "1m",
        positions: (st.positions || []).map((p) => ({ side: p.side, entry: p.entry ?? p.entryPrice, profit: +p.profit || 0 })), history: (st.history || []).map(norm), stats: st.stats } : null;
      if (bot === "tick") return pick(this.tickStatus, "⚡ Nến tick");
      if (bot === "grid") return pick(this.gridStatus, "🕸️ Nhồi lệnh");
      if (bot === "sr") return pick(this.srStatus, "🧱 Cản & Hỗ trợ");
      if (bot === "stop") return pick(this.stopStatus, "🎯 Stop theo nến");
      const a = this.autoFull;
      if (!a || !a.st) return null;
      const s = a.st.settings || {};
      return { name: "📈 Chiến lược" + (s.strategyName ? ": " + s.strategyName : ""), running: !!a.st.running, paper: s.broker !== "mt5", symbol: s.symbol, interval: s.interval,
        positions: (a.st.positions || []).map((p) => ({ side: p.side, entry: p.entryPrice, profit: +p.profit || 0 })), history: (a.hist || []).map(norm) };
    },

    /** Drawing on the bot's chart: its own drawings for each symbol (not the main chart's), a small toolbar over the
     *  chart, tap / drag as on the main chart. */
    setupBotDrawings() {
      const term = this, wrap = $("botChart");
      if (!window.AurumDrawings || !wrap || this.botDraw) return;
      const dr = (this.botDraw = new window.AurumDrawings({
        chart: this.botChart, series: this.botSeries, store,
        bars: () => this.botBars || [], sec: () => TF_SECONDS[this.botTf] || 60, digits: () => this.digitsFor(this.botSym),
        symbol: () => this.botSym || "XAUUSD", magnet: () => false, interval: () => this.botTf || "1m",
        onChange: () => this.renderBotDrawBar(),
        onEdit: () => {},
      }));
      // The bot chart's own drawings, kept apart from the main chart's.
      dr.key = () => "aurum.botdraw." + (this.botSym || "XAUUSD");
      const rel = (e) => { const r = wrap.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
      const lock = (on) => this.botChart.applyOptions({ handleScroll: !on, handleScale: !on });
      let gesture = false;
      wrap.addEventListener("pointerdown", (e) => {
        if (e.button > 0 || e.target.closest(".bl-draw")) return;
        const { x, y } = rel(e);
        if (x > this.botChart.timeScale().width()) return;
        if (dr.down(x, y, e) === true) { gesture = true; lock(true); e.stopPropagation(); }
      }, true);
      ["mousedown", "touchstart"].forEach((t) => wrap.addEventListener(t, (e) => { if (gesture) e.stopPropagation(); }, { capture: true, passive: true }));
      wrap.addEventListener("touchmove", (e) => { if (gesture) e.preventDefault(); }, { passive: false });
      wrap.addEventListener("pointermove", (e) => {
        if (gesture) return;
        const { x, y } = rel(e);
        if (dr.pending) { dr.move(x, y, e); return; }
        if (e.pointerType === "mouse") wrap.style.cursor = dr.tool ? "crosshair" : x <= this.botChart.timeScale().width() && dr.hitTest(x, y, 8) ? "move" : "";
      });
      window.addEventListener("pointermove", (e) => { if (gesture) { const { x, y } = rel(e); dr.move(x, y, e); } });
      const up = () => { if (!gesture) return; gesture = false; lock(false); dr.up(); };
      window.addEventListener("pointerup", up);
      window.addEventListener("pointercancel", up);
      wrap.addEventListener("contextmenu", (e) => { e.preventDefault(); if (dr.pending) dr.cancel(); else if (dr.tool) dr.setTool(null); });
      document.addEventListener("keydown", (e) => {
        if (this.tab !== "autobot" || /INPUT|TEXTAREA|SELECT/.test((document.activeElement || {}).tagName || "")) return;
        if ((e.key === "Delete" || e.key === "Backspace") && dr.current) { dr.remove(dr.current.id); e.preventDefault(); }
        if (e.key === "Escape") { if (dr.pending) dr.cancel(); dr.setTool(null); }
      });
      this.renderBotDrawBar();
    },

    /** The bot chart's drawing tools: line, ray, horizontal, rectangle, Fib, text; delete the picked one; hide all;
     *  the auto trend lines through 3 highs / 3 lows. */
    renderBotDrawBar() {
      const bar = $("blDraw"), dr = this.botDraw;
      if (!bar || !dr) return;
      const tools = [["trendLine", "╱", "Đường xu hướng"], ["trendRay", "↗", "Tia xu hướng"], ["horizontalLine", "─", "Đường ngang"], ["rectangle", "▭", "Hình chữ nhật (vùng)"], ["fibRetracement", "Fib", "Fib thoái lui"], ["text", "T", "Văn bản"]];
      const auto = store.get("aurum.botTrend") !== "0";
      bar.innerHTML = tools.map(([k, icon, name]) => `<button type="button" data-t="${k}" title="${name}" class="${dr.tool === k ? "on" : ""}">${icon}</button>`).join("")
        + `<button type="button" data-a="del" title="Xoá bản vẽ đang chọn" ${dr.current ? "" : "disabled"}>🗑</button>`
        + `<button type="button" data-a="hide" title="${dr.hidden ? "Hiện" : "Ẩn"} bản vẽ" class="${dr.hidden ? "on" : ""}">${dr.hidden ? "🙈" : "👁"}</button>`
        + `<button type="button" data-a="levels" title="Hỗ trợ / kháng cự bot đang dùng" class="wide ${store.get("aurum.botLevels") !== "0" ? "on" : ""}">▤ Cản / hỗ trợ</button>`
        + `<button type="button" data-a="trend" title="Tự kẻ đường trend qua 3 đỉnh / 3 đáy" class="${auto ? "on" : ""}">⟋ Trend 3 đỉnh/đáy</button>`;
      bar.querySelectorAll("[data-t]").forEach((b) => (b.onclick = () => { dr.setTool(dr.tool === b.dataset.t ? null : b.dataset.t); this.renderBotDrawBar(); }));
      bar.querySelector('[data-a="del"]').onclick = () => { if (dr.current) dr.remove(dr.current.id); this.renderBotDrawBar(); };
      bar.querySelector('[data-a="hide"]').onclick = () => { dr.hidden = !dr.hidden; dr.update(); this.renderBotDrawBar(); };
      bar.querySelector('[data-a="levels"]').onclick = () => { store.set("aurum.botLevels", store.get("aurum.botLevels") === "0" ? "1" : "0"); this.renderBotDrawBar(); if (this.botBars) this.renderBotLevels(this.botBars, { symbol: this.botSym }); };
      bar.querySelector('[data-a="trend"]').onclick = () => { store.set("aurum.botTrend", auto ? "0" : "1"); this.renderBotDrawBar(); if (this.botBars) this.renderBotTrend(this.botBars, { symbol: this.botSym }); };
    },

    /** The supports and resistances the bot reads (the recent swing highs / lows, as its "đợi xác nhận" filter):
     *  each drawn from the bar that made it to now, green under price (a support), red over it (a resistance),
     *  dashed once price has closed through it (its role turned), the band of levelRoom around the nearest two. */
    renderBotLevels(bars, v) {
      (this.botLevelSeries || []).forEach((sr) => { try { this.botChart.removeSeries(sr); } catch { /* gone */ } });
      this.botLevelSeries = [];
      if (store.get("aurum.botLevels") === "0" || bars.length < 12) return;
      const c = Object.assign({ swingK: 3, levelRoom: 1.5 }, (this.gridStatus && this.gridStatus.config) || {});
      const k = c.swingK || 3, n = bars.length, last = bars[n - 1].close, d = this.digitsFor(v.symbol);
      const levels = [];
      for (let i = k; i < n - 1 - k; i++) {
        const w = bars.slice(i - k, i + k + 1), before = bars.slice(i - k, i);
        if (bars[i].high > Math.max(...before.map((b) => b.high)) && bars[i].high >= Math.max(...w.map((b) => b.high))) levels.push({ i, p: bars[i].high, kind: "high" });
        if (bars[i].low < Math.min(...before.map((b) => b.low)) && bars[i].low <= Math.min(...w.map((b) => b.low))) levels.push({ i, p: bars[i].low, kind: "low" });
      }
      // The bot looks at the last five highs and five lows; of those, the nearest three over and three under price.
      const recent = levels.filter((l) => l.kind === "high").slice(-5).concat(levels.filter((l) => l.kind === "low").slice(-5));
      const over = recent.filter((l) => l.p > last).sort((a, b) => a.p - b.p).slice(0, 3), under = recent.filter((l) => l.p <= last).sort((a, b) => b.p - a.p).slice(0, 3);
      [...over, ...under].forEach((l) => {
        const res = l.p > last, broken = bars.slice(l.i + 1).some((b) => (l.kind === "low" ? b.close < l.p : b.close > l.p));
        const color = res ? "#f0455a" : "#14b88a";
        const sr = this.botChart.addLineSeries({ color, lineWidth: 2, lineStyle: broken ? 2 : 0, lastValueVisible: true, priceLineVisible: false, crosshairMarkerVisible: false,
          title: `${res ? "Cản" : "Hỗ trợ"}${broken ? " · đã phá, đổi vai" : ""}` });
        sr.setData([{ time: bars[l.i].time + TZ, value: l.p }, { time: bars[n - 1].time + TZ, value: l.p }]);
        this.botLevelSeries.push(sr);
      });
      // The band the bot keeps out of around the nearest support and resistance.
      [over[0], under[0]].filter(Boolean).forEach((l) => {
        [l.p + c.levelRoom, l.p - c.levelRoom].forEach((p) => {
          const band = this.botChart.addLineSeries({ color: (l.p > last ? "#f0455a" : "#14b88a") + "55", lineWidth: 1, lineStyle: 1, lastValueVisible: false, priceLineVisible: false, crosshairMarkerVisible: false });
          band.setData([{ time: bars[Math.max(l.i, n - 40)].time + TZ, value: p }, { time: bars[n - 1].time + TZ, value: p }]);
          this.botLevelSeries.push(band);
        });
      });
      const info = $("blLevels");
      if (info) info.innerHTML = `<span>🟥 Cản gần nhất: ${over[0] ? `<b>${fmt(over[0].p, d)}</b>` : "–"}</span><span>🟩 Hỗ trợ gần nhất: ${under[0] ? `<b>${fmt(under[0].p, d)}</b>` : "–"}</span><span class="muted">vùng mờ = ±${c.levelRoom} bot đợi nến phá / phản ứng, nét đứt = mức đã bị phá (đổi vai)</span>`;
    },

    /** Trend lines through 3 swing highs (above) and 3 swing lows (below) of the bot's chart, drawn to the last
     *  bar, and what price did at each: broke out or touched it and turned back. */
    renderBotTrend(bars, v) {
      (this.botTrendSeries || []).forEach((sr) => { try { this.botChart.removeSeries(sr); } catch { /* gone */ } });
      this.botTrendSeries = [];
      const info = $("blTrend");
      const lines = store.get("aurum.botTrend") !== "0" ? trendLines3(bars) : [];
      const d = this.digitsFor(v.symbol), notes = [];
      lines.forEach((ln) => {
        const sr = this.botChart.addLineSeries({ color: ln.kind === "high" ? "#f0455a" : "#14b88a", lineWidth: 2, lineStyle: 0, lastValueVisible: false, priceLineVisible: false, crosshairMarkerVisible: false });
        // The line through its three points on to the last bar; a dot on each of the three.
        const idx = [...new Set([...ln.points, bars.length - 1])].sort((x, y) => x - y);
        sr.setData(idx.map((i) => ({ time: bars[i].time + TZ, value: ln.at(i) })));
        sr.setMarkers(ln.points.map((i, q) => ({ time: bars[i].time + TZ, position: "inBar", color: ln.kind === "high" ? "#f0455a" : "#14b88a", shape: "circle", text: String(q + 1) })));
        this.botTrendSeries.push(sr);
        const when = ln.eventAt != null ? ` lúc ${clock(bars[ln.eventAt].time)}` : "";
        const what = ln.state === "breakout" ? `<b class="${ln.kind === "high" ? "pos" : "neg"}">giá đã đóng nến phá ${ln.kind === "high" ? "lên" : "xuống"}${when}</b>`
          : ln.state === "bounce" ? `<b class="${ln.kind === "high" ? "neg" : "pos"}">chạm trend rồi bật ${ln.kind === "high" ? "xuống" : "lên"}${when}${ln.touches > 1 ? ` (${ln.touches} lần)` : ""}</b>`
          : ln.state === "near" ? "giá đang sát trend" : "giá chưa chạm lại trend";
        if (ln.eventAt != null && ln.eventAt > ln.i3) {
          // The breakout / bounce bar marked on the line.
          const mk = ln.points.map((i, q) => ({ time: bars[i].time + TZ, position: "inBar", color: ln.kind === "high" ? "#f0455a" : "#14b88a", shape: "circle", text: String(q + 1) }));
          mk.push({ time: bars[ln.eventAt].time + TZ, position: ln.kind === "high" ? (ln.state === "breakout" ? "belowBar" : "aboveBar") : (ln.state === "breakout" ? "aboveBar" : "belowBar"),
            color: "#f2c14e", shape: ln.state === "breakout" ? (ln.kind === "high" ? "arrowUp" : "arrowDown") : (ln.kind === "high" ? "arrowDown" : "arrowUp"), text: ln.state === "breakout" ? "phá" : "bật" });
          sr.setMarkers(mk.sort((a, b) => a.time - b.time));
        }
        notes.push(`${ln.kind === "high" ? "Trend 3 đỉnh" : "Trend 3 đáy"} (đang ở ${fmt(ln.at(bars.length - 1), d)}): ${what}`);
      });
      if (info) { info.hidden = !notes.length; info.innerHTML = notes.map((x) => `<span>⟋ ${x}</span>`).join(""); }
    },

    /** Why a closed trade closed, as a tag coloured by its result. */
    closeTag(reason, profit) {
      if (!reason) return "";
      const r = String(reason), good = profit > 0, bad = profit < 0;
      const label = { target: "chốt lời", stop: "cắt lỗ", trail: "trailing", flip: "tín hiệu ngược", basket: "chốt rổ", sl: "SL", end: "cuối test" }[r] || r;
      return ` <span class="close-tag ${good ? "good" : bad ? "bad" : ""}">${esc(label)}</span>`;
    },

    /** Why a bot that wins often can still lose: average win against average loss, the win rate it needs
     *  to break even, and the money by the way trades closed and by side. */
    /** The grid bot's trades read as baskets (positions closed together), and what to change: the stop against the
     *  basket target, the spread's share, a side losing against the trend, stops right after the 2nd layer. */
    gridAdvice(h) {
      const groups = new Map();
      h.forEach((x) => { const k = `${x.reason}|${Math.round(x.closeTime || 0)}|${x.side}`; const g = groups.get(k) || { reason: x.reason, side: x.side, n: 0, sum: 0, lots: 0 }; g.n++; g.sum += x.profit; g.lots += +x.lots || 0; groups.set(k, g); });
      const all = [...groups.values()], wins = all.filter((g) => g.reason === "chốt rổ" || (g.reason === "trailing" && g.sum > 0)), stops = all.filter((g) => g.reason === "cắt lỗ chung" || g.reason === "SL rổ");
      if (!wins.length && !stops.length) return "";
      const aw = wins.length ? wins.reduce((a, g) => a + g.sum, 0) / wins.length : 0, al = stops.length ? -stops.reduce((a, g) => a + g.sum, 0) / stops.length : 0;
      const need = aw + al > 0 ? al / (aw + al) * 100 : 0, rate = (wins.length / Math.max(1, wins.length + stops.length)) * 100;
      const spread = h.reduce((a, x) => a + (x.spreadCost || 0), 0), gross = h.filter((x) => x.profit > 0).reduce((a, x) => a + x.profit, 0);
      const bySide = (sd) => h.filter((x) => x.side === sd).reduce((a, x) => a + x.profit, 0);
      const buy = bySide("long"), sell = bySide("short"), shallow = stops.filter((g) => g.n <= 2).length;
      const tips = [];
      if (stops.length && al > aw * 1.5) tips.push(`Mỗi lần cắt lỗ mất TB <b class="neg">${signed(-al)}</b> = ${(al / Math.max(aw, 0.01)).toFixed(1)} rổ thắng (${signed(aw)}), nên phải chốt được ${need.toFixed(0)}% số rổ; bot đang được <b>${rate.toFixed(0)}%</b>. → Tăng <b>Chốt rổ</b> (VD ${money(Math.max(2, Math.round(aw * 2)))}) hoặc giảm lot gấp để mỗi lần cắt nhẹ hơn.`);
      if (stops.length && shallow / stops.length >= 0.5) tips.push(`${shallow}/${stops.length} lần cắt lỗ xảy ra khi rổ mới có 1–2 lệnh: <b>Cắt lỗ chung quá sát</b>, lưới chưa kịp nhồi đã bị cắt. → Nới Cắt lỗ chung (theo ô "Rủi ro của cài đặt này") hoặc tăng Khoảng nhồi; nếu muốn cắt sớm thì dùng SL rổ theo giá và tắt nhồi (Tối đa lớp = 1).`);
      if (gross > 0 && spread / gross > 0.12) tips.push(`Spread đã ăn <b>${Math.round(spread / gross * 100)}%</b> tiền lời (${signed(-spread)}). → Chốt rổ lớn hơn (spread ~0.17$ mỗi 0.01 lot mỗi lần vào) hoặc thử tài khoản Raw / Zero ở ô giả lập.`);
      if (Math.min(buy, sell) < -3 && Math.max(buy, sell) > Math.min(buy, sell) + 5) tips.push(`${buy < sell ? "BUY" : "SELL"} lỗ <b class="neg">${signed(Math.min(buy, sell))}</b> trong khi ${buy < sell ? "SELL" : "BUY"} ${signed(Math.max(buy, sell))}: bot vào <b>ngược chiều giá đang chạy</b>, phần lỗ nằm ở một bên.`);
      if (!tips.length) tips.push("Chưa thấy lỗi rõ ràng; chạy thêm để có nhiều rổ hơn rồi xem lại.");
      return `<div class="grid-advice"><b>🔎 Bot nhồi lệnh sai ở đâu</b> <span class="muted small">(${wins.length} rổ chốt lời · ${stops.length} lần cắt lỗ · tính theo rổ, không theo từng lệnh)</span><ol>${tips.map((x) => `<li>${x}</li>`).join("")}</ol></div>`;
    },

    botWhy(h) {
      if (!h.length) return "";
      const wins = h.filter((x) => x.profit > 0), losses = h.filter((x) => x.profit <= 0);
      const aw = wins.length ? wins.reduce((a, x) => a + x.profit, 0) / wins.length : 0;
      const al = losses.length ? -losses.reduce((a, x) => a + x.profit, 0) / losses.length : 0;
      const need = aw + al > 0 ? al / (aw + al) * 100 : 0, rate = wins.length / h.length * 100;
      const group = (key) => {
        const m = new Map();
        h.forEach((x) => { const k = key(x) || "khác"; const g = m.get(k) || { n: 0, sum: 0 }; g.n++; g.sum += x.profit; m.set(k, g); });
        return [...m.entries()].sort((a, b) => a[1].sum - b[1].sum);
      };
      const row = ([k, g]) => `<div class="log-row"><span>${esc(k)}</span> · ${g.n} lệnh · <b class="${g.sum >= 0 ? "pos" : "neg"}">${signed(g.sum)}</b></div>`;
      const big = losses.slice().sort((a, b) => a.profit - b.profit).slice(0, 3);
      return `<div class="bot-why">
        <h4>Vì sao thắng nhiều mà vẫn lỗ?</h4>
        <div class="stats">
          <div class="stat"><span>Lời TB mỗi lệnh thắng</span><b class="pos">${signed(aw)}</b></div>
          <div class="stat"><span>Lỗ TB mỗi lệnh thua</span><b class="neg">${signed(-al)}</b></div>
          <div class="stat"><span>Cần thắng tối thiểu</span><b>${need.toFixed(0)}%</b></div>
          <div class="stat"><span>Đang thắng</span><b class="${rate >= need ? "pos" : "neg"}">${rate.toFixed(0)}%</b></div>
          ${h.some((x) => x.spreadCost != null) ? `<div class="stat"><span>Phí spread Exness đã trả</span><b class="neg">${signed(-h.reduce((a, x) => a + (x.spreadCost || 0), 0))}</b></div>` : ""}
        </div>
        <p class="muted small">Tính trên ${h.length} lệnh đóng gần nhất.</p>
        <p class="small">${al > aw ? `Mỗi lệnh thua mất trung bình <b>${(al / Math.max(aw, 0.01)).toFixed(1)} lần</b> số lời của một lệnh thắng, nên phải thắng trên <b>${need.toFixed(0)}%</b> mới hoà vốn; bot đang thắng ${rate.toFixed(0)}% → ${rate >= need ? "vẫn lời" : "nên vẫn lỗ"}.` : "Lời TB lớn hơn lỗ TB."}</p>
        <div class="why-cols"><div><b class="small">Theo cách đóng lệnh</b>${group((x) => x.reason).map(row).join("")}</div>
          <div><b class="small">Theo chiều</b>${group((x) => (x.side === "long" ? "BUY" : "SELL")).map(row).join("")}</div>
          <div><b class="small">3 lệnh lỗ nặng nhất</b>${big.map((x) => `<div class="log-row">${sideName(x.side)} · ${esc(x.reason || "")} · <b class="neg">${signed(x.profit)}</b></div>`).join("")}</div></div>
      </div>`;
    },

    /** The chosen bot's status as the MT5-like view reads it. */
    botStatusFor() {
      const bot = store.get("aurum.hubBot") || "strategy";
      if (bot === "tick") return this.tickStatus || {};
      if (bot === "grid") return this.gridStatus || {};
      if (bot === "sr") return this.srStatus || {};
      if (bot === "stop") return this.stopStatus || {};
      const a = this.autoFull || {}, st = a.st || {}, acc = st.account || {};
      return { config: { symbol: (st.settings || {}).symbol }, positions: (st.positions || []).map((p) => ({ symbol: p.symbol, side: p.side, lots: p.lots, entry: p.entryPrice, profit: +p.profit || 0 })),
        paper: acc.balance != null ? { balance: acc.balance, equity: acc.equity } : null };
    },

    /** Candles of the bot's market with its entries (▲▼) and exits (●), its open positions as lines,
     *  then its profit: total, win rate, the balance curve and the last trades. Every 4 s while shown. */
    async renderBotLive() {
      const box = $("botLive");
      if (!box || box.hidden || this.tab !== "autobot" || !window.LightweightCharts) return;
      const v = this.botView();
      $("blTitle").textContent = v ? v.name : "Bot";
      const mk = $("blMarks");
      if (mk && !mk.dataset.bound) {
        mk.dataset.bound = "1";
        mk.checked = store.get("aurum.botMarks") === "1";
        mk.onchange = () => { store.set("aurum.botMarks", mk.checked ? "1" : null); this.renderBotLive(); };
      }
      $("blSub").textContent = v ? ` · ${v.symbol || "–"} ${v.interval || ""} · ${v.running ? (v.paper ? "đang chạy ẢO" : "đang chạy trên MT5") : "đang tắt"}${this.ownAccount ? " · tài khoản riêng" : ""} · chạy 24/24 trên VPS` : " · chưa có dữ liệu";
      // The grid bot: what it is doing now, over its chart (resting after a stop, waiting for a signal…).
      const gs = $("blState");
      if (gs) {
        const txt = store.get("aurum.hubBot") === "grid" && this.gridStatus ? this.gridStateText(this.gridStatus) : "";
        gs.hidden = !txt; gs.innerHTML = txt ? "🤖 " + txt : "";
      }
      if (!v || !v.symbol || !v.interval) return;
      if (!this.botChart) {
        const el = $("botChart");
        this.botChart = LightweightCharts.createChart(el, {
          autoSize: true, layout: { background: { color: "#050506" }, textColor: "#c3cad7", fontSize: 11 },
          grid: { vertLines: { color: "#141417" }, horzLines: { color: "#141417" } },
          rightPriceScale: { borderColor: "#1e1e23" }, timeScale: { borderColor: "#1e1e23", timeVisible: true, rightOffset: 4 },
          crosshair: { mode: 0 },
        });
        this.botSeries = this.botChart.addCandlestickSeries({ upColor: "#14b88a", downColor: "#f0455a", wickUpColor: "#14b88a", wickDownColor: "#f0455a", borderVisible: false });
        this.botLines = [];
        this.setupBotDrawings();
      }
      const key = v.symbol + "|" + v.interval;
      try {
        const data = await this.botCall(`/mt5/candles?symbol=${encodeURIComponent(v.symbol)}&interval=${v.interval}&count=300`);
        const bars = this.toBars(data.candles || []);
        if (!bars.length) return;
        this.botSeries.setData(bars.map((b) => ({ time: b.time + TZ, open: b.open, high: b.high, low: b.low, close: b.close })));
        this.botBars = bars; this.botSym = v.symbol; this.botTf = v.interval;
        if (this.botDraw && this.botDrawKey !== v.symbol) { this.botDrawKey = v.symbol; this.botDraw.load(); }
        if (this.botDraw) this.botDraw.update();
        this.renderBotTrend(bars, v);
        this.renderBotLevels(bars, v);
        if (this.botKey !== key) { this.botKey = key; this.botChart.timeScale().scrollToRealTime(); }
        const sec = TF_SECONDS[v.interval] || 60, first = bars[0].time;
        const at = (t) => Math.floor(t / sec) * sec + TZ;
        const marks = [];
        v.history.slice(0, 150).forEach((h) => {
          const long = h.side === "long";
          if (h.openTime && h.openTime >= first) marks.push({ time: at(h.openTime), position: long ? "belowBar" : "aboveBar", color: long ? "#2b6bf3" : "#f0455a", shape: long ? "arrowUp" : "arrowDown", text: long ? "B" : "S" });
          if (h.closeTime && h.closeTime >= first) marks.push({ time: at(h.closeTime), position: long ? "aboveBar" : "belowBar", color: h.profit >= 0 ? "#14b88a" : "#f0455a", shape: "circle", text: (h.profit >= 0 ? "+" : "") + h.profit.toFixed(2) });
        });
        marks.sort((a, b) => a.time - b.time);
        // The entries / exits are many with a scalping bot: off unless asked for.
        this.botSeries.setMarkers(store.get("aurum.botMarks") === "1" ? marks : []);
        (this.botLines || []).forEach((l) => this.botSeries.removePriceLine(l));
        this.botLines = v.positions.filter((p) => p.entry != null).map((p) => this.botSeries.createPriceLine({ price: p.entry, color: p.side === "long" ? "#2b6bf3" : "#f0455a", lineWidth: 1, lineStyle: 2,
          axisLabelVisible: true, title: `${p.side === "long" ? "BUY" : "SELL"} ${p.profit >= 0 ? "+" : ""}${p.profit.toFixed(2)}` }));
        // The spread, as MT5 draws it: the candles are Bid, the Ask line over them (buys fill there, sells close there).
        const st0 = this.botStatusFor(), live = st0.price || (v.symbol === this.symbol && this.bid != null && this.ask != null ? { bid: this.bid, ask: this.ask } : null);
        if (live && live.ask != null && live.bid != null && live.ask > live.bid) {
          const sp = live.ask - live.bid, dd = this.digitsFor(v.symbol);
          this.botLines.push(this.botSeries.createPriceLine({ price: live.ask, color: "#f0455a", lineWidth: 1, lineStyle: 0, axisLabelVisible: true, title: `Ask · spread ${sp.toFixed(Math.min(dd, 3))}` }));
          this.botLines.push(this.botSeries.createPriceLine({ price: live.bid, color: "#8b93a7", lineWidth: 1, lineStyle: 0, axisLabelVisible: true, title: "Bid" }));
        }
      } catch (e) {
        $("blSub").textContent += " · " + plain(e.message);
      }
      // Profit history.
      const h = v.history, wins = h.filter((x) => x.profit > 0), net = h.reduce((a, x) => a + x.profit, 0);
      const gp = wins.reduce((a, x) => a + x.profit, 0), gl = -h.filter((x) => x.profit < 0).reduce((a, x) => a + x.profit, 0);
      const open = v.positions.reduce((a, p) => a + p.profit, 0);
      let bal = 0;
      const curve = [0].concat(h.slice().reverse().map((x) => (bal += x.profit)));
      const W = 600, H = 90, lo = Math.min(...curve), hi = Math.max(...curve), span = hi - lo || 1;
      const pts = curve.map((c, i) => `${(i / Math.max(curve.length - 1, 1) * W).toFixed(1)},${(H - 4 - (c - lo) / span * (H - 8)).toFixed(1)}`).join(" ");
      const d = this.digitsFor(v.symbol);
      const stat = (k, val, cls = "") => `<div class="stat"><span>${k}</span><b class="${cls}">${val}</b></div>`;
      $("botPL").innerHTML = `<div class="stats">
          ${stat("Lãi/lỗ đã chốt", signed(net), net >= 0 ? "pos" : "neg")}
          ${stat("Đang mở", `${v.positions.length} · ${signed(open)}`, open >= 0 ? "pos" : "neg")}
          ${stat("Thắng", h.length ? `${wins.length}/${h.length} · ${Math.round(wins.length / h.length * 100)}%` : "–")}
          ${stat("Profit factor", gl > 0 ? (gp / gl).toFixed(2) : gp > 0 ? "∞" : "–")}
          ${(() => { const rb = +store.get("aurum.rebate") || 0; if (!rb) return ""; const lots = h.reduce((a, x) => a + (+x.lots || 0), 0), got = lots * rb;
            return stat("Backcom ước tính", `${signed(got)} · ${lots.toFixed(2)} lot`, "pos") + stat("Ròng sau backcom", signed(net + got), net + got >= 0 ? "pos" : "neg"); })()}
        </div>
        ${h.length > 1 ? `<svg class="bt-eq" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"><polyline points="${pts}" fill="none" stroke="${net >= 0 ? "var(--up)" : "var(--down)"}" stroke-width="2" vector-effect="non-scaling-stroke"/></svg>` : ""}
        ${this.botWhy(h)}${store.get("aurum.hubBot") === "grid" ? this.gridAdvice(h) : ""}
        <div class="bl-m5">${this.mt5LikeView(this.botStatusFor())}</div>
        <h4>Lịch sử lệnh của bot (mới nhất trước)</h4>
        <div class="list log">${h.length ? h.slice(0, 25).map((x) => `<div class="log-row"><span class="muted small">${x.closeTime ? clock(x.closeTime) : ""}</span> ${sideName(x.side)}${x.lots ? " " + x.lots : ""} ${x.entry != null ? fmt(x.entry, d) : "–"} → ${x.exit != null ? fmt(x.exit, d) : "–"} · <b class="${x.profit >= 0 ? "pos" : "neg"}">${signed(x.profit)}</b>${this.closeTag(x.reason, x.profit)}</div>`).join("") : '<div class="empty">Chưa có lệnh đã đóng</div>'}</div>`;
    },

    /* ----- "Nến tick" bot on the server: in on a run from the candle's open, out by its close ----- */

    async loadTickBot(first) {
      const el = $("tickBotPanel");
      if (!el) return;
      let st = null, problem = "";
      try { st = await this.botCall("/tickbot"); } catch (e) { problem = ServerTooOld(e) ? "Cập nhật máy chủ lên bản 5.3 (tab Máy chủ → Cập nhật) để chạy bot này." : plain(e.message); }
      this.tickStatus = st;
      if (!this.tickWatch) this.watchTickBot();
      if (first || !el.querySelector("#tbForm") || !el.contains(document.activeElement)) this.renderTickBot(st, problem);
      else this.renderTickBotLive(st);
    },

    tickSettings() {
      const c = Object.assign({ symbol: "", interval: "1m", direction: "both", lots: 0.01, step: 0.3, closeProfit: 0.3, maxPositions: 6, basketStop: 30, burst: 1, exitAtClose: true, minLeftPct: 15, maxSpread: 0.5, noSpread: false, sl: 0.3, withCandle: true, flipExit: true },
        (this.tickStatus && this.tickStatus.config) || {});
      const v = (id) => ($(id) ? $(id).value : null);
      if ($("tbSymbol")) {
        Object.assign(c, {
          symbol: v("tbSymbol").trim(), interval: v("tbInterval"), direction: v("tbDirection"), lots: num(v("tbLots")) || 0.01,
          step: num(v("tbStep")) || 0.3, closeProfit: num(v("tbClose")) || 0.3, maxPositions: Math.max(1, Math.round(num(v("tbMax")) || 6)),
          basketStop: num(v("tbBasket")) ?? 30, exitAtClose: $("tbExit").checked, minLeftPct: num(v("tbLeft")) ?? 15, maxSpread: num(v("tbSpread")) ?? 0.5,
          noSpread: $("tbNoSpread").checked,
          simSpread: $("tbAcct").value === "real" ? -1 : (num(v("tbSimSpread")) ?? 0.1), commission: $("tbAcct").value === "real" ? 0 : (num(v("tbComm")) || 0),
          burst: Math.max(1, Math.min(5, Math.round(num(v("tbBurst")) || 1))),
          sl: num(v("tbSL")) ?? 0.3, withCandle: $("tbWith").checked, flipExit: $("tbFlip").checked,
          holdSeconds: v("tbHold") === "" || v("tbHold") == null ? -1 : Math.max(0, num(v("tbHold")) ?? -1),
        });
      }
      c.symbol = c.symbol || this.symbol || "XAUUSDm";
      // "Chạy thử" in the Bot box: virtual orders on the live Exness price; "Tài khoản MT5": real orders.
      c.paper = c.running ? c.paper !== false : (store.get("aurum.hubMode") || "demo") !== "mt5";
      return c;
    },

    renderTickBot(st, problem) {
      const el = $("tickBotPanel");
      const c = this.tickSettings();
      const opt = (list, v) => list.map(([k, n]) => `<option value="${k}" ${String(k) === String(v) ? "selected" : ""}>${n}</option>`).join("");
      const runPaper = st && st.config && st.config.paper;
      if (st && st.config && st.config.sl === undefined) problem = (problem ? problem + " " : "") + "Máy chủ VPS còn bản cũ: chưa có SL mỗi lệnh / thuận chiều nến / đóng khi nến đảo. Vào tab Máy chủ → Cập nhật (bản 5.0) rồi đặt lại tài khoản ảo để chạy lại từ đầu.";
      el.innerHTML = `<div class="panel-head"><h3>⚡ Bot nến tick (bản đầu)</h3>${st ? `<span class="badge ${c.running ? "on" : "off"}">${c.running ? (runPaper ? "Đang chạy ẢO" : "Đang chạy trên MT5") : "Đang tắt"}</span>` : ""}</div>
        <p class="muted small">Bot <b>MUA / BÁN liên tục</b> theo từng tick trong cây nến: mỗi lần giá chạy thêm một <b>bước</b> từ lệnh trước (lúc đầu từ giá mở nến) thì vào thêm 1 lệnh theo chiều đó (lên = MUA, xuống = BÁN), nên <b>bên nào giá phản ứng mạnh hơn sẽ có nhiều lệnh hơn</b>. Lệnh nào dương đủ mức <b>chốt lời</b> thì đóng ngay, lệnh khác vào tiếp; lệnh âm tới <b>SL</b> hoặc khi <b>nến đảo chiều</b> thì đóng sớm. An toàn: giới hạn số lệnh mở cùng lúc, <b>cắt lỗ chung</b> khi cả rổ lệnh âm quá mức, và đóng hết khi hết cây nến.</p>
        ${problem ? `<p class="warn">${esc(problem)}</p>` : ""}
        <div id="tbForm">
          <div class="fields three">
            <label>Mã<input id="tbSymbol" value="${esc(c.symbol)}"></label>
            <label>Khung nến<select id="tbInterval">${opt(["1m", "3m", "5m", "15m", "30m", "1h"].map((t) => [t, t]), c.interval)}</select></label>
            <label>Chiều<select id="tbDirection">${opt([["both", "Cả MUA và BÁN"], ["long", "Chỉ MUA"], ["short", "Chỉ BÁN"]], c.direction)}</select></label>
          </div>
          <div class="fields three">
            <label>Lot mỗi lệnh<input id="tbLots" inputmode="decimal" value="${c.lots}"></label>
            <label>Bước vào lệnh (giá chạy thêm)<input id="tbStep" inputmode="decimal" value="${c.step}"></label>
            <label>Chốt lời mỗi lệnh (giá)<input id="tbClose" inputmode="decimal" value="${c.closeProfit}"></label>
          </div>
          <div class="fields three">
            <label>Tối đa lệnh mở cùng lúc<input id="tbMax" inputmode="numeric" value="${c.maxPositions}"></label>
            <label>Cắt lỗ chung ($, 0 = tắt)<input id="tbBasket" inputmode="decimal" value="${c.basketStop}"></label>
            <label>Spread tối đa (0 = bỏ qua)<input id="tbSpread" inputmode="decimal" value="${c.maxSpread}"></label>
          </div>
          <div class="fields three">
            <label>Không vào khi nến còn dưới (%)<input id="tbLeft" inputmode="decimal" value="${c.minLeftPct}"></label>
            <label>Số lệnh mỗi lần vào (1 – 5)<input id="tbBurst" inputmode="numeric" value="${c.burst || 1}"></label>
            <label>&nbsp;<button class="btn btn-ghost" id="tbPreset" type="button">⚙ Cài giống video (XAUUSD 0.01 · chốt ~1$)</button></label>
          </div>
          <div class="fields three">
            <label>SL mỗi lệnh (giá, 0 = không SL)<input id="tbSL" inputmode="decimal" value="${c.sl ?? 0.3}"></label>
            <label>🧪 Vào rồi chốt sau (giây, trống = tắt) — chỉ thử ảo / backtest<input id="tbHold" inputmode="decimal" placeholder="VD 0, 5, 30" value="${c.holdSeconds != null && c.holdSeconds >= 0 ? c.holdSeconds : ""}"></label>
          </div>
          <label class="check"><input type="checkbox" id="tbWith" ${c.withCandle !== false ? "checked" : ""}> Chỉ vào <b>thuận chiều cây nến</b> (giá trên giá mở: chỉ MUA · dưới: chỉ BÁN)</label>
          <label class="check"><input type="checkbox" id="tbFlip" ${c.flipExit !== false ? "checked" : ""}> Đóng lệnh âm khi <b>cây nến đảo chiều</b> (qua giá mở thêm 1 bước)</label>
          <label class="check"><input type="checkbox" id="tbExit" ${c.exitAtClose ? "checked" : ""}> Đóng hết lệnh khi hết cây nến</label>
          <div class="fields three">
            <label>Tài khoản ảo giả lập loại<select id="tbAcct">${Object.entries(ACCOUNT_SIMS).map(([k, a]) => `<option value="${k}" ${(c.simSpread == null || c.simSpread < 0) ? (k === "real" ? "selected" : "") : (k === "custom" ? "selected" : "")}>${a.name}</option>`).join("")}</select></label>
            <label>Spread giả lập (giá)<input id="tbSimSpread" inputmode="decimal" value="${c.simSpread != null && c.simSpread >= 0 ? c.simSpread : 0.1}"></label>
            <label>Phí ($/lot, khứ hồi)<input id="tbComm" inputmode="decimal" value="${c.commission || 0}"></label>
          </div>
          <label class="check"><input type="checkbox" id="tbNoSpread" ${c.noSpread ? "checked" : ""}> Chạy trên giá <b>không có spread</b> (MUA và BÁN cùng giá Bid) — chỉ áp dụng cho 🎮 Chạy thử và 🧪 Backtest; tài khoản MT5 thật luôn có spread</label>
          <p class="muted small">Ví dụ vàng: bước 0.3 · chốt lời 0.3 = giá chạy lên 0.3$ thì MUA thêm 1 lệnh, xuống 0.3$ thì BÁN thêm 1 lệnh; lệnh nào lời 0.3$ (0.01 lot ≈ 0.3$) thì đóng. Cần tài khoản MT5 dạng <b>hedging</b> (mặc định của Exness) để giữ MUA và BÁN cùng lúc.</p>
          <div class="row-btns">
            ${!st ? "" : c.running ? '<button class="btn btn-ghost" id="tbStop">■ Tắt bot</button><button class="btn btn-ghost" id="tbSave">Lưu cài đặt</button>' : `<button class="btn btn-gold" id="tbStart">▶ Bật bot nến tick ${c.paper ? "(ẢO · giá Exness)" : "trên MT5"}</button>`}
            ${st && c.paper ? '<button class="btn btn-ghost" id="tbReset">Đặt lại tài khoản ảo</button>' : ""}
          </div>
        </div>
        <div id="tbLive"></div>`;
      const send = async (button, extra, done) => {
        const r = await act(button, () => this.botCall("/tickbot", Object.assign(this.tickSettings(), extra)), done);
        if (r) { this.tickStatus = r; this.renderTickBot(r, ""); }
      };
      const start = $("tbStart"), stop = $("tbStop"), save = $("tbSave");
      if (start) start.onclick = (e) => {
        if (!this.tickSettings().paper && !confirm("Bot sẽ đặt lệnh THẬT trên tài khoản MT5 đang đăng nhập. Tiếp tục?")) return;
        send(e.currentTarget, { running: true }, "Đã bật bot nến tick");
      };
      if (stop) stop.onclick = (e) => send(e.currentTarget, { running: false }, "Đã tắt bot (lệnh đang mở giữ nguyên)");
      if (save) save.onclick = (e) => send(e.currentTarget, {}, "Đã lưu");
      const tbAcct = $("tbAcct");
      if (tbAcct) {
        const fillAcct = () => {
          const a = ACCOUNT_SIMS[tbAcct.value] || ACCOUNT_SIMS.real;
          if (tbAcct.value !== "custom" && tbAcct.value !== "real") { $("tbSimSpread").value = a.spread; $("tbComm").value = a.commission; }
          $("tbSimSpread").closest("label").hidden = tbAcct.value === "real";
          $("tbComm").closest("label").hidden = tbAcct.value === "real";
        };
        tbAcct.onchange = fillAcct; fillAcct();
      }
      const preset = $("tbPreset");
      if (preset) preset.onclick = () => {
        // As in the video: XAUUSD 0.01 a position, buys and sells side by side, each out at about +1$, 3–4 open.
        const set = (id, v) => { if ($(id)) $(id).value = v; };
        set("tbLots", 0.01); set("tbStep", 0.5); set("tbClose", 1); set("tbMax", 4); set("tbBurst", 1); set("tbBasket", 20); set("tbSL", 1);
        set("tbInterval", "5m"); set("tbDirection", "both"); set("tbLeft", 5);
        if ($("tbExit")) $("tbExit").checked = false;
        toast("Đã điền cài đặt giống video: bấm Lưu / Bật để dùng");
      };
      const reset = $("tbReset");
      if (reset) reset.onclick = (e) => {
        const v = prompt("Số dư tài khoản ảo mới (USD):", "10000");
        if (!v || !num(v)) return;
        send(e.currentTarget, { paperReset: num(v) }, "Đã đặt lại tài khoản ảo");
      };
      this.renderTickBotLive(st);
    },

    renderTickBotLive(st, id = "tbLive") {
      const live = $(id);
      if (!live || !st) { if (live) live.innerHTML = ""; return; }
      const d = (sym) => this.digitsFor(sym), s = st.stats || {};
      live.innerHTML = `<div class="stats">
          <div class="stat"><span>Lệnh đã đóng</span><b>${s.trades || 0}</b></div>
          <div class="stat"><span>Thắng</span><b>${s.wins || 0}${s.trades ? ` (${Math.round(s.wins / s.trades * 100)}%)` : ""}</b></div>
          <div class="stat"><span>Lãi/lỗ</span><b class="${(s.profit || 0) >= 0 ? "pos" : "neg"}">${signed(s.profit || 0)}</b></div>
          <div class="stat"><span>Đang mở</span><b>${(st.positions || []).length}</b></div>
        </div>
        ${st.error ? `<p class="warn">${esc(st.error)}</p>` : ""}
        ${st.paper ? `<p class="muted small">Tài khoản ẢO: số dư ${money(st.paper.balance)} · lệnh và lãi/lỗ tính theo giá Exness thật${(st.config || {}).noSpread ? " (không tính spread)" : ""}, không đặt lệnh lên MT5.</p>` : ""}
        <div class="list">${(st.positions || []).map((o) => `<div class="sig"><div class="bar" style="background:${o.side === "long" ? "#2b6bf3" : "var(--down)"}"></div>
          <div><div class="top"><span class="sym">${esc(o.symbol)}</span><span class="side ${o.side === "long" ? "buy" : "sell"}">${sideName(o.side)} ${o.lots}</span><span class="muted small">@ ${fmt(o.entry, d(o.symbol))}${o.paper ? " · ảo" : ""}</span></div>
          <div class="lv">SL ${o.stop ? fmt(o.stop, d(o.symbol)) : "–"} · TP ${o.target ? fmt(o.target, d(o.symbol)) : "–"}${o.trail != null ? ` · <b class="pos">trailing ${fmt(o.trail, d(o.symbol))}</b>` : ""}</div></div>
          <div class="right"><div class="move ${(o.profit || 0) >= 0 ? "pos" : "neg"}">${signed(o.profit || 0)}</div></div></div>`).join("")}</div>
        ${(st.history || []).length ? `<h4>Lệnh ảo đã đóng</h4><div class="list log">${st.history.slice(0, 20).map((x) => `<div class="log-row"><span class="muted small">${clock(x.closeTime)}</span> ${sideName(x.side)} ${fmt(x.entry, d(x.symbol))} → ${fmt(x.exit, d(x.symbol))} · ${esc(x.reason)} · <b class="${x.profit >= 0 ? "pos" : "neg"}">${signed(x.profit)}</b></div>`).join("")}</div>` : ""}
        ${(st.events || []).length ? `<h4>Hoạt động</h4><div class="list log">${st.events.slice(0, 15).map((e) => `<div class="log-row"><span class="muted small">${clock(e.time)}</span> ${esc(e.text)}</div>`).join("")}</div>` : ""}`;
    },

    /** The bot's open positions as MT5's Trade screen shows them: the floating total on top, the account
     *  lines, then "XAUUSD buy 0.01 / entry → now / profit" for each. */
    mt5LikeView(st) {
      const pos = st.positions || [], d = (sym) => this.digitsFor(sym);
      const floating = pos.reduce((a, p) => a + (p.profit || 0), 0);
      const acc = st.paper || null;
      const line = (k, v) => `<div class="m5-line"><span>${k}</span><b>${v}</b></div>`;
      return `<div class="m5-view">
        <div class="m5-total ${floating >= 0 ? "pos" : "neg"}">${floating >= 0 ? "" : "−"}${Math.abs(floating).toFixed(2)} USD</div>
        ${acc ? line("Balance:", acc.balance.toFixed(2)) + line("Equity:", (acc.equity ?? acc.balance + floating).toFixed(2)) : ""}
        ${st.price ? line("Giá Bid / Ask:", `${fmt(st.price.bid, d((st.config || {}).symbol))} / ${fmt(st.price.ask, d((st.config || {}).symbol))}`) : ""}
        <div class="m5-head">Positions</div>
        ${pos.length ? pos.map((p) => `<div class="m5-pos">
          <div><div><b>${esc((p.symbol || "").replace(/m$/, ""))}</b> <span class="${p.side === "long" ? "m5-buy" : "m5-sell"}">${p.side === "long" ? "buy" : "sell"} ${p.lots}</span></div>
            <div class="m5-px">${fmt(p.entry, d(p.symbol))} → ${p.now != null ? fmt(p.now, d(p.symbol)) : "…"}</div></div>
          <div class="m5-pl ${(p.profit || 0) >= 0 ? "pos" : "neg"}">${(p.profit || 0).toFixed(2)}</div></div>`).join("") : '<div class="m5-empty">Chưa có lệnh đang mở</div>'}
      </div>`;
    },

    /** While the tick bot runs and its box is shown: its view again every 1.5 s. */
    watchTickBot() {
      clearInterval(this.tickWatch);
      this.tickWatch = setInterval(async () => {
        const bot = store.get("aurum.hubBot");
        if (this.tab !== "autobot" || document.hidden || (bot !== "tick" && bot !== "grid")) return;
        const st0 = bot === "grid" ? this.gridStatus : this.tickStatus;
        if (!(st0 && st0.config && st0.config.running)) return;
        try {
          const st = await this.botCall(bot === "grid" ? "/gridbot" : "/tickbot");
          if (bot === "grid") { this.gridStatus = st; this.renderGridBotLive(st); } else { this.tickStatus = st; this.renderTickBotLive(st); }
        } catch { /* next time */ }
      }, 1500);
    },

    /* ----- "Nhồi lệnh" grid bot on the server: adds to a losing basket, closes it on a small profit ----- */

    async loadGridBot(first) {
      const el = $("gridBotPanel");
      if (!el) return;
      let st = null, problem = "";
      try { st = await this.botCall("/gridbot"); } catch (e) { problem = ServerTooOld(e) ? "Cập nhật máy chủ lên bản 5.7 (tab Máy chủ → Cập nhật) để chạy bot nhồi lệnh. Backtest vẫn chạy được ngay." : plain(e.message); }
      this.gridStatus = st;
      if (!this.tickWatch) this.watchTickBot();
      if (first || !el.querySelector("#gbForm") || !el.contains(document.activeElement)) this.renderGridBot(st, problem);
      else this.renderGridBotLive(st);
    },

    gridSettings() {
      const c = Object.assign({ symbol: "", direction: "both", lots: 0.01, gridStep: 2, multiplier: 1.5, maxLevels: 6, maxLot: 0.5, tpMoney: 1,
        basketStop: 60, cooldownMin: 60, sl: 0, slMoney: 0, bias: "off", biasTf: "5m", biasMinBody: 50, biasLotMult: 2,
        entry: "signal", sigCandle: true, sigTf: "1m", sigBody: 50, sigSr: "auto", sigNeed: "two", trailOn: false, trailStart: 1, trailDist: 0.5,
        addMode: "with", pyramidLock: true, flipClose: true, waitSec: 15, levelGuard: true, levelRoom: 1.5,
        nyGuard: true, nyFrom: "08:15", nyTo: "10:30", newsGuard: true, newsBefore: 15, newsAfter: 15, guardAction: "pause", sigSwing: false, swingK: 3, swingZone: 0.5, sigZone: "off", structTf: "1m", structBars: 120, srBars: 30, srZone: 1, sigTick: true, tickSec: 10, tickMove: 0.3, confirmAdd: true, maxSpread: 0.5, noSpread: false, simSpread: -1, commission: 0 }, (this.gridStatus && this.gridStatus.config) || {});
      const v = (id) => ($(id) ? $(id).value : null);
      if ($("gbSymbol")) {
        Object.assign(c, {
          symbol: v("gbSymbol").trim(), direction: v("gbDirection"), lots: num(v("gbLots")) || 0.01, gridStep: num(v("gbStep")) || 2,
          multiplier: Math.max(1, Math.min(3, num(v("gbMult")) || 1)), maxLevels: Math.max(1, Math.min(30, Math.round(num(v("gbLevels")) || 6))),
          maxLot: num(v("gbMaxLot")) || 0.5, tpMoney: Math.max(0, num(v("gbTp")) ?? 1), addMode: v("gbAddMode"), pyramidLock: $("gbLock").checked, flipClose: $("gbFlip").checked, levelGuard: $("gbLevelGuard").checked, levelRoom: Math.max(0.05, num(v("gbLevelRoom")) ?? 1.5),
          nyGuard: $("gbNyGuard").checked, nyFrom: v("gbNyFrom") || "08:15", nyTo: v("gbNyTo") || "10:30", newsGuard: $("gbNewsGuard").checked,
          newsBefore: Math.max(0, num(v("gbNewsBefore")) ?? 15), newsAfter: Math.max(0, num(v("gbNewsAfter")) ?? 15), guardAction: v("gbGuardAction"), waitSec: Math.max(0, Math.min(59, num(v("gbWait")) ?? 15)), basketStop: num(v("gbStop")) ?? 60, cooldownMin: num(v("gbCool")) ?? 60,
          sl: Math.max(0, num(v("gbSL")) || 0), slMoney: Math.max(0, num(v("gbSLMoney")) || 0),
          bias: v("gbBias"), biasTf: v("gbBiasTf"), biasMinBody: Math.max(0, Math.min(100, num(v("gbBiasBody")) ?? 50)),
          biasLotMult: Math.max(1, Math.min(5, num(v("gbBiasMult")) || 2)),
          entry: v("gbEntry"), sigCandle: $("gbSigCandle").checked, sigTf: v("gbSigTf"), sigBody: Math.max(0, Math.min(100, num(v("gbSigBody")) ?? 50)),
          trailOn: $("gbTrail").checked, trailStart: Math.max(0.01, num(v("gbTrailStart")) || 1), trailDist: Math.max(0.01, num(v("gbTrailDist")) || 0.5),
          sigSwing: $("gbSwing").checked, swingK: Math.max(1, Math.min(10, Math.round(num(v("gbSwingK")) || 3))), swingZone: Math.max(0.01, num(v("gbSwingZone")) || 0.5),
          sigZone: v("gbZone"), structTf: v("gbStructTf"), structBars: Math.max(20, Math.min(500, Math.round(num(v("gbStructBars")) || 120))),
          sigSr: v("gbSigSr"), sigNeed: v("gbSigNeed"), srBars: Math.max(5, Math.min(500, Math.round(num(v("gbSrBars")) || 30))), srZone: Math.max(0.01, num(v("gbSrZone")) || 1),
          sigTick: $("gbSigTick").checked, tickSec: Math.max(1, Math.min(300, num(v("gbTickSec")) || 10)), tickMove: Math.max(0.01, num(v("gbTickMove")) || 0.3),
          confirmAdd: $("gbConfirm").checked,
          maxSpread: num(v("gbSpread")) ?? 0.5, noSpread: $("gbNoSpread").checked,
          simSpread: $("gbAcct").value === "real" ? -1 : (num(v("gbSimSpread")) ?? 0.1), commission: $("gbAcct").value === "real" ? 0 : (num(v("gbComm")) || 0),
        });
      }
      c.symbol = c.symbol || this.symbol || "XAUUSDm";
      c.maxLot = Math.max(c.lots, c.maxLot);
      c.interval = "1m"; // the backtest's bars and the bot chart
      c.paper = c.running ? c.paper !== false : (store.get("aurum.hubMode") || "demo") !== "mt5";
      return c;
    },

    /** What the grid risks: each layer's lot, the lots at full depth, and the floating loss when price has
     *  gone the whole grid against one basket. */
    gridRisk(c, factor = 1) {
      const lots = Array.from({ length: c.maxLevels }, (_, i) => gridLot(c, i, factor));
      // Price can go the whole grid against the basket, or only to its SL.
      const full = c.gridStep * c.maxLevels, depth = c.sl > 0 ? Math.min(c.sl, full) : full;
      const px = this.symbol === c.symbol && this.bid ? this.bid : 2000;
      const used = lots.filter((_, i) => i * c.gridStep < depth - 1e-9);
      let loss = used.reduce((a, l, i) => a + (this.valueAt(c.symbol, l, "long", px, px - (depth - i * c.gridStep)) || 0), 0);
      if (c.slMoney > 0) loss = Math.max(loss, -c.slMoney);
      return { lots, total: Math.round(lots.reduce((a, x) => a + x, 0) * 100) / 100, depth, loss, layers: used.length };
    },

    renderGridBot(st, problem) {
      const el = $("gridBotPanel");
      const c = this.gridSettings();
      const opt = (list, v) => list.map(([k, n]) => `<option value="${k}" ${String(k) === String(v) ? "selected" : ""}>${n}</option>`).join("");
      const runPaper = st && st.config && st.config.paper;
      if (st && st.config && st.config.sl === undefined) problem = (problem ? problem + " " : "") + "Máy chủ VPS chưa có SL rổ: vào tab Máy chủ → Cập nhật lên bản 5.7 (Backtest vẫn dùng được ngay).";
      else if (st && st.config && st.config.bias === undefined) problem = (problem ? problem + " " : "") + "Máy chủ VPS chưa có lực nến: vào tab Máy chủ → Cập nhật lên bản 5.7 (Backtest vẫn dùng được ngay).";
      else if (st && st.config && st.config.entry === undefined) problem = (problem ? problem + " " : "") + "Máy chủ VPS chưa có vào lệnh theo tín hiệu (nến / cản M1 / tick): vào tab Máy chủ → Cập nhật lên bản 5.8 (Backtest dùng được ngay).";
      else if (st && st.grid && st.config.running && st.grid.state === undefined) problem = (problem ? problem + " " : "") + "Cập nhật máy chủ lên bản 5.8 để xem bot đang làm gì (đang nghỉ / chờ tín hiệu) và nút Chạy lại ngay.";
      el.innerHTML = `<div class="panel-head"><h3>🕸️ Bot nhồi lệnh (grid / gấp lot)</h3>${st ? `<span class="badge ${c.running ? "on" : "off"}">${c.running ? (runPaper ? "Đang chạy ẢO" : "Đang chạy trên MT5") : "Đang tắt"}</span>` : ""}</div>
        <p class="muted small" id="gbIntro"></p>
        <p class="warn small">⚠️ Bot dạng này thắng đều phần lớn thời gian vì giá thường hồi lại, nhưng một đợt chạy một mạch không hồi (tin, xu hướng mạnh) sẽ lấy lại toàn bộ lãi hoặc cháy tài khoản. Luôn đặt <b>Cắt lỗ chung</b>, chạy 🧪 Backtest và 🎮 Chạy thử trước.</p>
        ${problem ? `<p class="warn">${esc(problem)}</p>` : ""}
        <div id="gbForm">
          <div class="fields three">
            <label>Mã<input id="gbSymbol" value="${esc(c.symbol)}"></label>
            <label>Chiều<select id="gbDirection">${opt([["both", "Cả rổ MUA và rổ BÁN"], ["long", "Chỉ rổ MUA"], ["short", "Chỉ rổ BÁN"]], c.direction)}</select></label>
            <label>Lot lệnh đầu<input id="gbLots" inputmode="decimal" value="${c.lots}"></label>
          </div>
          <div class="fields three">
            <label>Kiểu nhồi<select id="gbAddMode">${opt([["with", "📈 Nhồi dương — giá đi đúng hướng mới nhồi thêm"], ["against", "📉 Nhồi âm — giá chạy ngược thì nhồi (kiểu cũ)"]], c.addMode || "against")}</select></label>
            <label class="grow2">&nbsp;<span class="muted small" id="gbAddHint"></span></label>
          </div>
          <label class="check"><input type="checkbox" id="gbLock" ${c.pyramidLock !== false ? "checked" : ""}> <b>Khoá lời khi nhồi dương</b>: rổ có từ 2 lớp thì cả rổ đi chung một SL — chặt nhất trong: giá lớp trước, <b>giá vốn trung bình</b> (không lỗ), và trailing của cả rổ. Không còn cảnh chốt lớp dưới rồi bỏ lại lớp trên cùng âm.</label>
          <div class="fields three">
            <label>Khoảng nhồi (giá)<input id="gbStep" inputmode="decimal" value="${c.gridStep}"></label>
            <label>Hệ số gấp lot (1 – 3)<input id="gbMult" inputmode="decimal" value="${c.multiplier}"></label>
            <label>Tối đa lớp mỗi rổ<input id="gbLevels" inputmode="numeric" value="${c.maxLevels}"></label>
          </div>
          <div class="fields three">
            <label>Lot tối đa mỗi lệnh<input id="gbMaxLot" inputmode="decimal" value="${c.maxLot}"></label>
            <label>Chốt rổ khi lời ($, 0 = tắt — chốt bằng trailing)<input id="gbTp" inputmode="decimal" value="${c.tpMoney}"></label>
            <label>Cắt lỗ chung cả bot ($, 0 = tắt)<input id="gbStop" inputmode="decimal" value="${c.basketStop}"></label>
          </div>
          <div class="fields three">
            <label>SL rổ theo giá (tính từ lệnh đầu, 0 = tắt)<input id="gbSL" inputmode="decimal" placeholder="VD 12" value="${c.sl || 0}"></label>
            <label>SL rổ theo tiền ($ mỗi rổ, 0 = tắt)<input id="gbSLMoney" inputmode="decimal" placeholder="VD 30" value="${c.slMoney || 0}"></label>
            <label>&nbsp;<span class="muted small">Chạm SL: đóng cả rổ bên đó, bên đó nghỉ như sau cắt lỗ. Trên MT5, SL theo giá được đặt luôn vào từng lệnh trên sàn (vẫn cắt khi máy chủ mất kết nối).</span></label>
          </div>
          <div class="guard-box">
            <b>🛡 Bảo vệ khi giá chạy nhanh</b>
            <label class="check"><input type="checkbox" id="gbNyGuard" ${c.nyGuard !== false ? "checked" : ""}> Không vào lệnh trong <b>giờ mở cửa Mỹ</b> (giờ New York, tự đổi mùa hè / đông; thứ 2 – thứ 6)</label>
            <div class="fields three">
              <label>Từ (giờ New York)<input id="gbNyFrom" value="${esc(c.nyFrom || "08:15")}" placeholder="08:15"></label>
              <label>Đến (giờ New York)<input id="gbNyTo" value="${esc(c.nyTo || "10:30")}" placeholder="10:30"></label>
              <label>&nbsp;<span class="muted small" id="gbNyVn"></span></label>
            </div>
            <label class="check"><input type="checkbox" id="gbNewsGuard" ${c.newsGuard !== false ? "checked" : ""}> Không vào lệnh quanh <b>tin đỏ USD</b> (CPI, NFP, FOMC… theo lịch tin)</label>
            <div class="fields three">
              <label>Trước tin (phút)<input id="gbNewsBefore" inputmode="numeric" value="${c.newsBefore ?? 15}"></label>
              <label>Sau tin (phút)<input id="gbNewsAfter" inputmode="numeric" value="${c.newsAfter ?? 15}"></label>
              <label>Khi tới giờ đó<select id="gbGuardAction">${opt([["pause", "Ngừng mở lệnh mới (lệnh đang mở vẫn chạy)"], ["close", "Đóng hết lệnh rồi nghỉ"]], c.guardAction || "pause")}</select></label>
            </div>
          </div>
          <label class="check"><input type="checkbox" id="gbTrail" ${c.trailOn ? "checked" : ""}> <b>Trailing stop từng lệnh</b>: lệnh nào lời đủ mức bắt đầu thì SL bám theo giá tốt nhất (trên MT5 dời luôn SL trên sàn) — nên tăng Chốt rổ để trailing có chỗ chạy</label>
          <div class="fields three">
            <label>Bắt đầu trailing khi lời (giá)<input id="gbTrailStart" inputmode="decimal" value="${c.trailStart ?? 1}"></label>
            <label>Khoảng cách trailing (giá)<input id="gbTrailDist" inputmode="decimal" value="${c.trailDist ?? 0.5}"></label>
            <label>&nbsp;<span class="muted small">VD vàng: lời 1.0 thì bật, SL cách giá cao nhất 0.5 → giá quay xuống 0.5 là chốt.</span></label>
          </div>
          <div class="fields three">
            <label>Cách vào lệnh<select id="gbEntry">${opt([["signal", "🎯 Theo tín hiệu — 1 bên mỗi lần"], ["both", "Mở cả rổ MUA và rổ BÁN"]], c.entry || "both")}</select></label>
            <label class="grow2">&nbsp;<span class="muted small">Theo tín hiệu: bot <b>không</b> mở MUA + BÁN cùng lúc, chỉ mở <b>1 rổ</b> khi các bộ lọc bật bên dưới cùng chỉ một chiều; rổ đó chốt / SL xong mới mở rổ mới.</span></label>
          </div>
          <div class="gb-sig" data-entry="signal">
            <label class="check"><input type="checkbox" id="gbSigCandle" ${c.sigCandle !== false ? "checked" : ""}> <b>Nến</b>: cây nến vừa đóng cùng chiều (tăng → MUA, giảm → BÁN), thân ≥ % cả cây</label>
            <div class="fields three">
              <label>Khung nến<select id="gbSigTf">${opt(["1m", "3m", "5m", "15m"].map((t) => [t, t]), c.sigTf || "1m")}</select></label>
              <label>Thân nến ≥ (%)<input id="gbSigBody" inputmode="decimal" value="${c.sigBody ?? 50}"></label>
              <label>Cản M1<select id="gbSigSr">${opt([["auto", "Tự động: giá ở sát cản, nến / tick chọn phá hay bật"], ["bounce", "Bật cản: MUA ở hỗ trợ, BÁN ở kháng cự"], ["break", "Phá cản: MUA khi vượt kháng cự, BÁN khi thủng hỗ trợ"], ["off", "Tắt"]], c.sigSr || "auto")}</select></label>
            </div>
            <div class="fields three">
              <label>Cản = đỉnh / đáy của (số nến M1 vừa đóng)<input id="gbSrBars" inputmode="numeric" value="${c.srBars ?? 30}"></label>
              <label>Vùng quanh cản (giá)<input id="gbSrZone" inputmode="decimal" value="${c.srZone ?? 1}"></label>
              <label>Cần bao nhiêu bộ lọc đồng ý<select id="gbSigNeed">${opt([["two", "Ít nhất 2 bộ lọc (vào lệnh nhiều hơn)"], ["all", "Tất cả bộ lọc đang bật (chặt, ít lệnh)"]], c.sigNeed || "all")}</select></label>
            </div>
            <label class="check"><input type="checkbox" id="gbSigTick" ${c.sigTick !== false ? "checked" : ""}> <b>Tick</b>: giá vừa chạy đủ mạnh theo chiều đó</label>
            <div class="fields three">
              <label>Giá chạy ít nhất (giá)<input id="gbTickMove" inputmode="decimal" value="${c.tickMove ?? 0.3}"></label>
              <label>Trong (giây)<input id="gbTickSec" inputmode="decimal" value="${c.tickSec ?? 10}"></label>
              <label>Chờ sau khi nến đóng (giây, 0 = tắt)<input id="gbWait" inputmode="decimal" value="${c.waitSec ?? 15}"></label>
            </div>
            <label class="check"><input type="checkbox" id="gbLevelGuard" ${c.levelGuard !== false ? "checked" : ""}> <b>Đợi xác nhận ở đỉnh / đáy M1</b>: giá đang sát một đáy vừa hình thành thì <b>không BÁN</b> (hay bị bật lên) — chỉ BÁN khi có <b>nến nhấn chìm / thân dài đóng phá xuống</b> dưới đáy; giá phản ứng tăng ở đó thì để bộ lọc Đỉnh đáy cho MUA. Ở đỉnh thì ngược lại.</label>
            <div class="fields three">
              <label>Coi là "sát" đỉnh / đáy khi cách (giá)<input id="gbLevelRoom" inputmode="decimal" value="${c.levelRoom ?? 1.5}"></label>
              <label class="grow2">&nbsp;<span class="muted small">Đỉnh / đáy lấy theo khung và số nến ở mục "Đỉnh đáy + nến đảo chiều" bên dưới (mặc định M1, 3 nến mỗi bên). Nên bật cả bộ lọc Đỉnh đáy để bot MUA khi giá phản ứng ở đáy / BÁN khi phản ứng ở đỉnh, và khi nến phá qua.</span></label>
            </div>
            <label class="check"><input type="checkbox" id="gbSwing" ${c.sigSwing ? "checked" : ""}> <b>Đỉnh đáy + nến đảo chiều</b>: bot tự tìm đỉnh / đáy cũ; khi giá về đó và đóng một cây <b>pin bar</b> hoặc <b>nến nhấn chìm</b> đảo chiều → MUA ở đáy, BÁN ở đỉnh</label>
            <div class="fields three">
              <label>Đỉnh / đáy = cao / thấp nhất (số nến mỗi bên)<input id="gbSwingK" inputmode="numeric" value="${c.swingK ?? 3}"></label>
              <label>Vùng quanh đỉnh / đáy (giá)<input id="gbSwingZone" inputmode="decimal" value="${c.swingZone ?? 0.5}"></label>
              <label>Phản ứng FVG / OB<select id="gbZone">${opt([["off", "Tắt"], ["both", "FVG + OB"], ["fvg", "Chỉ FVG"], ["ob", "Chỉ OB"]], c.sigZone || "off")}</select></label>
            </div>
            <div class="fields three">
              <label>Khung nến đỉnh đáy / FVG / OB<select id="gbStructTf">${opt(["1m", "3m", "5m", "15m"].map((t) => [t, t]), c.structTf || "1m")}</select></label>
              <label>Xét bao nhiêu nến gần nhất<input id="gbStructBars" inputmode="numeric" value="${c.structBars ?? 120}"></label>
              <label>&nbsp;<span class="muted small">FVG / OB: giá chọc vào vùng FVG / OB chưa bị phá rồi cây nến đóng bật ra theo chiều vùng (vùng tăng → MUA, vùng giảm → BÁN).</span></label>
            </div>
            <p class="muted small">⏱ Chờ sau khi nến đóng: nến vừa đóng thì bot đợi số giây này xem giá, hết thời gian mà tín hiệu vẫn còn và giá vẫn <b>giữ trên giá đóng cửa</b> nến đó (MUA) / <b>dưới</b> (BÁN) mới vào; giá quay ngược thì bỏ qua.</p>
            <label class="check"><input type="checkbox" id="gbFlip" ${c.flipClose !== false ? "checked" : ""}> <b>Đóng rổ khi có tín hiệu ngược</b>: đang giữ rổ MUA mà tín hiệu chuyển sang BÁN thì đóng rổ MUA rồi mở rổ BÁN (không để rổ cũ kẹt làm bot chỉ đánh một chiều)</label>
            <label class="check"><input type="checkbox" id="gbConfirm" ${c.confirmAdd !== false ? "checked" : ""}> <b>Nhồi khi giá quay đầu</b>: đủ khoảng nhồi rồi còn phải đợi tick quay lại chiều của rổ (½ mức tick) mới nhồi — không nhồi khi giá còn đang rơi / tăng mạnh</label>
          </div>
          <div class="fields three" data-entry="both">
            <label>Lực nến (nhìn cây nến vừa đóng)<select id="gbBias">${opt([["off", "Tắt — mở cả MUA và BÁN như nhau"], ["only", "Chỉ mở rổ bên nến mạnh"], ["more", "Cả 2 bên, bên nến mạnh lot lớn hơn"]], c.bias || "off")}</select></label>
            <label>Khung nến xem lực<select id="gbBiasTf">${opt(["1m", "3m", "5m", "15m", "30m", "1h"].map((t) => [t, t]), c.biasTf || "5m")}</select></label>
            <label>Nến mạnh khi thân ≥ (% cả cây)<input id="gbBiasBody" inputmode="decimal" value="${c.biasMinBody ?? 50}"></label>
          </div>
          <div class="fields three" data-entry="both">
            <label>Bên mạnh: lot × (chế độ lot lớn hơn)<input id="gbBiasMult" inputmode="decimal" value="${c.biasLotMult ?? 2}"></label>
            <label class="grow2">&nbsp;<span class="muted small">Nến vừa đóng là nến TĂNG mạnh (thân dài, ít râu) → ưu tiên rổ MUA; GIẢM mạnh → ưu tiên rổ BÁN; nến yếu (doji, râu dài) → chế độ "chỉ bên mạnh" sẽ đợi, chế độ "lot lớn hơn" mở 2 bên như nhau. Chỉ áp dụng khi MỞ rổ mới; rổ đang chạy vẫn nhồi và chốt như cũ.</span></label>
          </div>
          <div class="fields three">
            <label>Nghỉ sau cắt lỗ / SL (phút)<input id="gbCool" inputmode="decimal" value="${c.cooldownMin}"></label>
            <label>Spread tối đa (0 = bỏ qua)<input id="gbSpread" inputmode="decimal" value="${c.maxSpread}"></label>
            <label>&nbsp;<button class="btn btn-ghost" id="gbPreset" type="button">⚙ Cài giống video (0.01 · nhồi 2$ · ×1.5 · chốt 1$)</button></label>
          </div>
          <div class="fields three">
            <label>Tài khoản ảo giả lập loại<select id="gbAcct">${Object.entries(ACCOUNT_SIMS).map(([k, a]) => `<option value="${k}" ${(c.simSpread == null || c.simSpread < 0) ? (k === "real" ? "selected" : "") : (k === "custom" ? "selected" : "")}>${a.name}</option>`).join("")}</select></label>
            <label>Spread giả lập (giá)<input id="gbSimSpread" inputmode="decimal" value="${c.simSpread != null && c.simSpread >= 0 ? c.simSpread : 0.1}"></label>
            <label>Phí ($/lot, khứ hồi)<input id="gbComm" inputmode="decimal" value="${c.commission || 0}"></label>
          </div>
          <label class="check"><input type="checkbox" id="gbNoSpread" ${c.noSpread ? "checked" : ""}> Chạy trên giá <b>không có spread</b> — chỉ 🎮 Chạy thử và 🧪 Backtest</label>
          <div class="grid-risk" id="gbRisk"></div>
          <div class="row-btns">
            ${!st ? "" : c.running ? '<button class="btn btn-ghost" id="gbStopBtn">■ Tắt bot</button><button class="btn btn-ghost" id="gbSave">Lưu cài đặt</button>' : `<button class="btn btn-gold" id="gbStart">▶ Bật bot nhồi lệnh ${c.paper ? "(ẢO · giá Exness)" : "trên MT5"}</button>`}
            ${st && c.paper ? '<button class="btn btn-ghost" id="gbReset">Đặt lại tài khoản ảo</button>' : ""}
          </div>
        </div>
        <div id="gbLive"></div>`;
      const showRisk = () => {
        const g = this.gridSettings(), r = this.gridRisk(g), up = g.addMode === "with";
        if ($("gbNyVn")) {
          // The NY window in Vietnam time today (UTC+7).
          const off = nyOffsetHours(Date.now() / 1000), vn = (x) => { const [h, m] = String(x).split(":"); const t = ((+h || 0) * 60 + (+m || 0) - off * 60 + 7 * 60 + 2880) % 1440; return `${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`; };
          $("gbNyVn").textContent = `= ${vn(g.nyFrom)} – ${vn(g.nyTo)} giờ Việt Nam (${off === -4 ? "mùa hè Mỹ" : "mùa đông Mỹ"}). Mỹ mở cửa 09:30 New York.`;
        }
        $("gbIntro").innerHTML = up
          ? 'Bot "nhồi dương": mở 1 rổ, giá chạy <b>đúng hướng</b> thêm một <b>khoảng nhồi</b> (tính từ lệnh tốt nhất của rổ) thì vào thêm 1 lệnh (lot × <b>hệ số gấp</b>, 1 = không gấp). Giá đi ngược thì <b>không nhồi</b>. Thoát bằng <b>trailing</b>, <b>chốt rổ</b>, SL rổ hoặc cắt lỗ chung.'
          : 'Bot "nhồi âm": mở 1 lệnh MUA và 1 lệnh BÁN. Bên nào giá chạy <b>ngược</b> thêm một <b>khoảng nhồi</b> thì vào thêm lệnh bên đó với lot × <b>hệ số gấp</b> (1 = không gấp). Khi cả rổ bên đó dương đủ <b>mức chốt rổ</b> thì đóng hết rổ và mở lại từ đầu.';
        $("gbAddHint").innerHTML = up
          ? `Nhồi dương nên: hệ số gấp <b>1</b> (lot đều, không gấp lệnh ở giá cao), bật <b>Trailing stop</b> và để Chốt rổ <b>0</b> hoặc lớn — chốt rổ nhỏ sẽ đóng rổ trước khi kịp nhồi.${g.tpMoney > 0 && g.tpMoney <= this.valueAt(g.symbol, g.lots, "long", 2000, 2000 + g.gridStep) ? ' <b class="neg">Chốt rổ hiện tại nhỏ hơn lời của 1 khoảng nhồi → rổ sẽ chốt trước khi nhồi lớp 2.</b>' : ""}`
          : "Nhồi âm gồng lệnh khi giá đi ngược: thắng đều nhưng một đợt chạy mạnh không hồi có thể lấy hết lãi.";
        if (up) {
          // Nhồi dương: the full grid up, then price comes back. Layer i is i × step over the first entry.
          const px = this.symbol === g.symbol && this.bid ? this.bid : 2000, n = g.maxLevels, top = (n - 1) * g.gridStep;
          const at = (drop) => r.lots.reduce((a, l, i) => a + (this.valueAt(g.symbol, l, "long", px + i * g.gridStep, px + top - drop) || 0), 0);
          $("gbRisk").innerHTML = `<b>Rủi ro của cài đặt này</b> (vàng, 1 rổ, nhồi dương):
            <div class="small">Lot từng lớp: ${r.lots.join(" · ")} → tổng <b>${r.total} lot</b> khi đủ ${n} lớp (giá đã đi đúng hướng ${+top.toFixed(2)}).</div>
            <div class="small">Đủ ${n} lớp rồi giá quay về đúng giá lệnh đầu → rổ <b class="${at(top) >= 0 ? "pos" : "neg"}">${signed(at(top))}</b>${g.trailOn ? ` · có trailing ${g.trailDist}: mỗi lệnh được giữ lời từ khi lời ${g.trailStart}` : ' · <b class="neg">chưa bật trailing</b>: lời có thể trả lại hết'}${g.sl > 0 ? ` · SL rổ ${g.sl} dưới lệnh cao nhất → nếu chạm ngay sau lớp cuối: rổ <b class="${at(g.sl) >= 0 ? "pos" : "neg"}">${signed(at(g.sl))}</b>` : ""}.</div>
            <div class="small muted">Giá đi ngược ngay từ lệnh đầu: chỉ 1 lệnh ${g.lots} lot chịu lỗ (không nhồi thêm)${g.sl > 0 ? `, SL rổ cắt ở −${g.sl} giá ≈ ${signed(this.valueAt(g.symbol, g.lots, "long", px, px - g.sl) || 0)}` : g.basketStop > 0 ? `, cắt lỗ chung ở −${money(g.basketStop)}` : ""}.</div>`;
          return;
        }
        $("gbRisk").innerHTML = `<b>Rủi ro của cài đặt này</b> (vàng, 1 rổ):
          <div class="small">Lot từng lớp: ${r.lots.join(" · ")} → tổng <b>${r.total} lot</b> khi đủ ${g.maxLevels} lớp.</div>
          <div class="small">${g.sl > 0 || g.slMoney > 0 ? `Chạm SL rổ (${g.sl > 0 ? `giá chạy ngược <b>${+r.depth.toFixed(2)}</b>, đã nhồi ${r.layers} lớp` : ""}${g.sl > 0 && g.slMoney > 0 ? " hoặc " : ""}${g.slMoney > 0 ? `rổ âm ${money(g.slMoney)}` : ""}) → mất khoảng <b class="neg">${signed(r.loss)}</b> mỗi lần.`
            : `Không có SL rổ: giá chạy ngược một mạch <b>${+r.depth.toFixed(2)}</b> (hết lưới) → rổ âm khoảng <b class="neg">${signed(r.loss)}</b> và vẫn gồng tiếp.`}${g.basketStop > 0 ? ` · Cắt lỗ chung cả bot ở <b>−${money(g.basketStop)}</b>.` : g.sl > 0 || g.slMoney > 0 ? "" : ' · <b class="neg">Không có cắt lỗ nào.</b>'}</div>
          ${g.bias === "more" && g.biasLotMult > 1 ? (() => { const s2 = this.gridRisk(g, g.biasLotMult); return `<div class="small">Rổ bên nến mạnh (lot ×${g.biasLotMult}): ${s2.lots.join(" · ")} → tổng <b>${s2.total} lot</b> · cùng đoạn giá ngược thì âm khoảng <b class="neg">${signed(s2.loss)}</b>.</div>`; })() : ""}
          <div class="small muted">${!(g.tpMoney > 0) ? "Chốt rổ đang tắt: lời chỉ đến từ trailing." : `Mỗi rổ thắng chỉ được khoảng ${money(g.tpMoney)}: ${g.sl > 0 || g.slMoney > 0 ? `một lần chạm SL rổ ≈ ${Math.max(1, Math.round(-r.loss / g.tpMoney))} rổ thắng` : g.basketStop > 0 ? `một lần cắt lỗ chung ≈ ${Math.round(g.basketStop / g.tpMoney)} rổ thắng` : "một lần thua có thể mất cả tài khoản"}.`}</div>`;
      };
      $("gbForm").querySelectorAll("input,select").forEach((x) => x.addEventListener("input", showRisk));
      showRisk();
      const showEntry = () => { const e = $("gbEntry").value; $("gbForm").querySelectorAll("[data-entry]").forEach((x) => { x.hidden = x.dataset.entry !== e; }); };
      $("gbEntry").addEventListener("change", showEntry); showEntry();
      const send = async (button, extra, done) => {
        const r = await act(button, () => this.botCall("/gridbot", Object.assign(this.gridSettings(), extra)), done);
        if (r) { this.gridStatus = r; this.renderGridBot(r, ""); }
      };
      const start = $("gbStart"), stop = $("gbStopBtn"), save = $("gbSave");
      if (start) start.onclick = (e) => {
        const g = this.gridSettings();
        if (!g.paper && !confirm(`Bot nhồi lệnh sẽ đặt lệnh THẬT trên tài khoản MT5 đang đăng nhập, gấp lot tới ${this.gridRisk(g).total} lot mỗi rổ. Tiếp tục?`)) return;
        send(e.currentTarget, { running: true }, "Đã bật bot nhồi lệnh");
      };
      if (stop) stop.onclick = (e) => send(e.currentTarget, { running: false }, "Đã tắt bot (lệnh đang mở giữ nguyên)");
      if (save) save.onclick = (e) => send(e.currentTarget, {}, "Đã lưu");
      const acct = $("gbAcct"), fillAcct = () => {
        const a = ACCOUNT_SIMS[acct.value] || ACCOUNT_SIMS.real;
        if (acct.value !== "custom" && acct.value !== "real") { $("gbSimSpread").value = a.spread; $("gbComm").value = a.commission; }
        $("gbSimSpread").closest("label").hidden = acct.value === "real";
        $("gbComm").closest("label").hidden = acct.value === "real";
      };
      acct.onchange = () => { fillAcct(); showRisk(); }; fillAcct();
      $("gbPreset").onclick = () => {
        // As in the video: 0.01 to start, a new layer every 2$ against, lots × 1.5, the basket out at about +1$.
        const set = (id, v) => { if ($(id)) $(id).value = v; };
        set("gbLots", 0.01); set("gbStep", 2); set("gbMult", 1.5); set("gbLevels", 6); set("gbMaxLot", 0.5); set("gbTp", 1); set("gbStop", 60); set("gbCool", 60);
        set("gbDirection", "both"); set("gbAddMode", "against");
        showRisk();
        toast("Đã điền cài đặt giống video: chạy 🧪 Backtest trước, rồi Lưu / Bật");
      };
      const reset = $("gbReset");
      if (reset) reset.onclick = (e) => {
        const v = prompt("Số dư tài khoản ảo mới (USD):", "10000");
        if (!v || !num(v)) return;
        send(e.currentTarget, { paperReset: num(v) }, "Đã đặt lại tài khoản ảo");
      };
      this.renderGridBotLive(st);
    },

    /** What the grid bot is doing now, in words: resting until when (and why), waiting for which signal,
     *  holding a basket, spread too wide. */
    gridStateText(st) {
      const g = (st && st.grid) || {}, s = g.state, cfg = (st && st.config) || {};
      if (s === undefined || (!s && cfg.running && !("state" in g))) {
        // A server before 5.8 sends no state at all.
        return cfg.running ? `bot đang bật nhưng máy chủ VPS chưa gửi trạng thái: vào tab <b>Máy chủ → Cập nhật</b> lên bản mới nhất${st.error ? ` · <b class="neg">lỗi: ${esc(st.error)}</b>` : ""}` : "";
      }
      if (!s) return cfg.running ? "đang khởi động…" : "";
      const sideName2 = (x) => (x === "long" ? "MUA" : "BÁN");
      const rest = Object.entries(s.sidePause || {}).map(([k, v]) => `rổ ${sideName2(k)} nghỉ sau SL tới ${clock(v)}`).join(" · ");
      const tag = (ok) => (ok && ok.length ? `<b class="pos">✓ ${ok.map(sideName2).join("/")}</b>` : '<b class="neg">✗</b>');
      let txt = "";
      if (s.kind === "off") txt = "bot đang tắt";
      else if (s.kind === "starting") txt = "bot vừa bật, đang đọc giá…";
      else if (s.kind === "guard") txt = `🛡 <b>đang tránh ${esc(s.why || "giờ mạnh")}</b> tới ${clock(s.until)} — không mở lệnh mới${s.holding ? ` (vẫn giữ ${s.holding} lệnh đang mở)` : ""}`;
      else if (s.kind === "flip") txt = `tín hiệu vừa đảo sang <b>${sideName2(s.side)}</b>: đã đóng rổ ngược chiều, mở rổ mới ngay`;
      else if (s.kind === "error") txt = `<b class="neg">bot đang gặp lỗi: ${esc(s.error || st.error || "")}</b> — bot tự thử lại mỗi 2 giây`;
      else if (s.kind === "noprice") txt = `<b class="neg">MT5 không trả giá ${esc(s.symbol || "")}</b> — kiểm tra MT5 trên VPS đã đăng nhập và mã đúng`;
      else if (s.kind === "pause") txt = `<b class="neg">đang nghỉ sau ${esc(s.why || "cắt lỗ")} tới ${clock(s.until)}</b> (còn ${Math.max(0, Math.ceil((s.until * 1000 - Date.now()) / 60000))} phút) — không vào lệnh mới`;
      else if (s.kind === "spread") txt = `<b class="neg">spread đang ${s.spread} &gt; mức tối đa ${s.max}</b> — chờ spread hạ`;
      else if (s.kind === "holding") txt = `đang giữ ${s.count} lệnh (rổ ${s.sides.map(sideName2).join(" + ")}) — chờ chốt / nhồi${cfg.entry === "signal" ? ` · tín hiệu bây giờ: ${s.signal ? `<b>${sideName2(s.signal)}</b>` : "chưa có"}${cfg.flipClose && s.signal && !s.sides.includes(s.signal) ? " → đảo chiều" : ""}` : ""}`;
      else if (s.kind === "wait" && s.gate === "waiting") txt = `⏱ nến vừa đóng — <b>chờ ${Math.ceil(s.waitLeft || 0)}s</b> xem giá rồi mới vào (giá đóng nến ${fmt(s.close, this.digitsFor(cfg.symbol))})`;
      else if (s.kind === "wait" && s.gate === "level") txt = s.blocked === "short"
        ? `có tín hiệu BÁN nhưng giá đang <b>sát đáy ${fmt(s.level, this.digitsFor(cfg.symbol))}</b> — chờ <b>nến nhấn chìm phá xuống</b> mới BÁN, hoặc phản ứng tăng để MUA`
        : `có tín hiệu MUA nhưng giá đang <b>sát đỉnh ${fmt(s.level, this.digitsFor(cfg.symbol))}</b> — chờ <b>nến nhấn chìm phá lên</b> mới MUA, hoặc phản ứng giảm để BÁN`;
      else if (s.kind === "wait" && s.gate === "notHeld") txt = `có tín hiệu nhưng giá <b class="neg">không giữ được</b> giá đóng nến ${fmt(s.close, this.digitsFor(cfg.symbol))} sau ${cfg.waitSec}s — bỏ qua, chờ tiếp`;
      else if (s.kind === "wait") {
        const p = s.parts || {};
        txt = `<b>đang chờ tín hiệu</b>: ${[cfg.sigCandle ? `nến ${tag(p.candle)}` : "", cfg.sigSr && cfg.sigSr !== "off" ? `cản ${tag(p.sr)}` : "", cfg.sigTick ? `tick ${tag(p.tick)}` : "", cfg.sigSwing ? `đỉnh/đáy ${tag(p.swing)}` : "", cfg.sigZone && cfg.sigZone !== "off" ? `${cfg.sigZone === "both" ? "FVG/OB" : cfg.sigZone.toUpperCase()} ${tag(p.zone)}` : ""].filter(Boolean).join(" · ")} — ${(cfg.sigNeed || "all") === "all" ? "cần tất cả cùng một chiều" : "cần 2 bộ lọc cùng một chiều"}${cfg.sigSr === "bounce" && cfg.sigCandle ? ' · <span class="muted">mẹo: "Bật cản" + nến hay ngược nhau, thử cản "Tự động"</span>' : ""}`;
      } else if (s.kind === "open") txt = "sẵn sàng vào lệnh";
      return txt + (rest ? ` · <b class="neg">${rest}</b>` : "");
    },

    renderGridBotLive(st) {
      this.renderTickBotLive(st, "gbLive");
      const live = $("gbLive");
      if (!live || !st || !st.grid) return;
      const pos = st.positions || [], g = st.grid;
      const side = (s) => pos.filter((p) => p.side === s);
      const basket = (s) => { const ps = side(s); return ps.length ? `${ps.length} lớp · ${+ps.reduce((a, p) => a + (+p.lots || 0), 0).toFixed(2)} lot · <b class="${ps.reduce((a, p) => a + (p.profit || 0), 0) >= 0 ? "pos" : "neg"}">${signed(ps.reduce((a, p) => a + (p.profit || 0), 0))}</b>` : "trống"; };
      let pause = g.pauseUntil && g.pauseUntil * 1000 > Date.now() ? ` · <b class="neg">đang nghỉ sau cắt lỗ tới ${clock(g.pauseUntil)}</b>` : "";
      Object.entries(g.sidePause || {}).forEach(([k, v]) => { if (v * 1000 > Date.now()) pause += ` · <b class="neg">rổ ${k === "long" ? "MUA" : "BÁN"} nghỉ sau SL tới ${clock(v)}</b>`; });
      const sg = g.signal, cfg = st.config || {}, sd = (x) => (x === "long" ? '<b class="pos">MUA</b>' : x === "short" ? '<b class="neg">BÁN</b>' : "—");
      const sigTxt = sg ? ` · tín hiệu: ${sg.side ? sd(sg.side) : "<b>chờ</b>"}${cfg.sigCandle && sg.candle ? ` (nến ${esc(cfg.sigTf || "")} ${sd(sg.candle[0])} ${Math.round(sg.candle[1] * 100)}%` : " ("}${sg.sup != null ? ` · hỗ trợ ${fmt(sg.sup, this.digitsFor(cfg.symbol))} / cản ${fmt(sg.res, this.digitsFor(cfg.symbol))}` : ""}${sg.move != null ? ` · tick ${sg.move > 0 ? "+" : ""}${sg.move}/${cfg.tickSec}s` : ""})` : "";
      const b = g.bias, bias = sigTxt || (b ? ` · lực nến ${esc((st.config || {}).biasTf || "")}: ${b.side ? `<b class="${b.side === "long" ? "pos" : "neg"}">${b.side === "long" ? "MUA" : "BÁN"} mạnh</b>` : "<b>yếu</b>"} (thân ${b.body > 0 ? "+" : ""}${b.body}%)` : "");
      const stTxt = this.gridStateText(st), resting = g.state && (g.state.kind === "pause" || Object.keys(g.state.sidePause || {}).length);
      live.insertAdjacentHTML("afterbegin", `${stTxt ? `<p class="grid-state">🤖 ${stTxt}${resting ? ' <button class="btn btn-ghost btn-small" id="gbResume" type="button">▶ Chạy lại ngay</button>' : ""}</p>` : ""}<p class="small">Rổ MUA: ${basket("long")} · Rổ BÁN: ${basket("short")} · đã chốt ${g.cycles || 0} rổ từ lúc bật${bias}${pause}</p>`);
      const resume = $("gbResume");
      if (resume) resume.onclick = async (e) => {
        const r = await act(e.currentTarget, () => this.botCall("/gridbot", { resume: true }), "Bot vào lệnh lại ngay khi có tín hiệu");
        if (r) { this.gridStatus = r; this.renderGridBotLive(r); }
      };
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
          <label>Bot<select id="btBot"><option value="stop" ${bot === "stop" ? "selected" : ""}>🎯 Stop theo nến</option><option value="sr" ${bot === "sr" ? "selected" : ""}>🧱 Cản & Hỗ trợ</option><option value="tick" ${bot === "tick" ? "selected" : ""}>⚡ Nến tick</option><option value="grid" ${bot === "grid" ? "selected" : ""}>🕸️ Nhồi lệnh</option></select></label>
          <label>Spread (giá, trống = spread hiện tại)<input id="btSpread" inputmode="decimal" placeholder="VD vàng 0.16" value="${esc(store.get("aurum.btSpread") || "")}"></label>
          <label>Thời gian<select id="btDays">${[1, 3, 7, 14, 30, 60].map((d) => `<option value="${d}" ${d === days ? "selected" : ""}>${d} ngày</option>`).join("")}</select></label>
          <label>Vốn ban đầu<input id="btBalance" inputmode="decimal" value="${esc(store.get("aurum.btBalance") || "10000")}"></label>
          <label>Backcom ($ mỗi lot, 0 = không)<input id="btRebate" inputmode="decimal" value="${esc(store.get("aurum.rebate") || "0")}"></label>
          <label>Loại tài khoản (giả lập)<select id="btAcct">${Object.entries(ACCOUNT_SIMS).map(([k, a]) => `<option value="${k}" ${k === (store.get("aurum.btAcct") || "real") ? "selected" : ""}>${a.name}</option>`).join("")}</select></label>
          <label>Spread giả lập (giá)<input id="btSimSpread" inputmode="decimal" value="${esc(store.get("aurum.btSimSpread") || "0.1")}"></label>
          <label>Phí ($/lot, khứ hồi)<input id="btComm" inputmode="decimal" value="${esc(store.get("aurum.btComm") || "0")}"></label>
          <label>&nbsp;<button class="btn btn-gold" id="btRun" type="button">▶ Chạy backtest</button></label>
          <label id="btSrcWrap">Dữ liệu<select id="btSrc"><option value="ticks" ${store.get("aurum.btSrc") !== "bars" ? "selected" : ""}>Tick thật MT5 (chính xác, tối đa 2 ngày)</option><option value="bars" ${store.get("aurum.btSrc") === "bars" ? "selected" : ""}>Nến (ước lượng, nhanh)</option></select></label>
          <label id="btOptWrap">&nbsp;<button class="btn btn-ghost" id="btOpt" type="button">🔎 Tìm cài đặt tốt nhất</button></label>
        </div>
        <p class="muted small" id="btInfo"></p>
        <div id="btResult"></div>`;
      // Picking an account type fills its spread and commission (still editable).
      const acctSel = $("btAcct"), fill = () => {
        const a = ACCOUNT_SIMS[acctSel.value] || ACCOUNT_SIMS.real;
        if (acctSel.value !== "custom") { $("btSimSpread").value = a.spread == null ? "" : a.spread; $("btComm").value = a.commission; }
        $("btSimSpread").closest("label").hidden = acctSel.value === "real";
        $("btComm").closest("label").hidden = acctSel.value === "real";
      };
      acctSel.onchange = fill; fill();
      $("btRun").onclick = () => this.runStopBt();
      $("btOpt").onclick = () => this.optimizeTickBot();
      this.applyBotHub();
    },

    async runStopBt() {
      const bot = $("btBot").value;
      const c = bot === "sr" ? this.srSettings() : bot === "tick" ? this.tickSettings() : bot === "grid" ? this.gridSettings() : this.stopBotSettings();
      if (bot === "grid" && c.newsGuard) {
        // The week's calendar for the news guard (the server's feed; this week only).
        if (!this.news) { try { this.news = await this.call(this.owner ? "/news" : "/member/news"); } catch { /* no calendar: the guard skips news */ } }
        c._news = (this.news && this.news.events) || [];
      }
      const days = +$("btDays").value, balance = num($("btBalance").value) || 10000;
      store.set("aurum.btDays", String(days)); store.set("aurum.btBalance", String(balance)); store.set("aurum.btBot", bot);
      store.set("aurum.btSpread", $("btSpread").value.trim());
      if ($("btRebate")) store.set("aurum.rebate", String(num($("btRebate").value) || 0));
      // Spread: as typed, or the live one when the backtest is on the chart's symbol.
      let spread = num($("btSpread").value);
      if (spread == null) spread = c.symbol === this.symbol && this.bid != null && this.ask != null ? Math.max(0, this.ask - this.bid) : 0;
      if ((bot === "tick" || bot === "grid") && c.noSpread) spread = 0;
      const acct = $("btAcct") ? $("btAcct").value : "real";
      const simSpread = acct === "real" ? null : num($("btSimSpread").value);
      const commission = acct === "real" ? 0 : num($("btComm").value) || 0;
      store.set("aurum.btAcct", acct);
      if ($("btSimSpread")) store.set("aurum.btSimSpread", $("btSimSpread").value);
      if ($("btComm")) store.set("aurum.btComm", $("btComm").value);
      if (simSpread != null) spread = simSpread;
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
        // The trade's money, less the account type's commission (per lot, round trip).
        const value = (side, entry, exit, lots = c.lots) => this.valueAt(c.symbol, lots, side, entry, exit) - commission * lots;
        // The tick bot on real ticks: up to 2 days, 6 hours a call.
        let ticks = null;
        if ((bot === "tick" || bot === "grid") && $("btSrc") && $("btSrc").value === "ticks") {
          store.set("aurum.btSrc", "ticks");
          const end = Date.now() / 1000, start = Math.max(from, end - 2 * 86400);
          ticks = [];
          // An hour a call (a few MB at most), each given 60 s; an hour MT5 has no ticks for is skipped.
          let failed = 0, lastError = "";
          for (let t = start; t < end; t += 3600) {
            info.textContent = `Đang tải tick thật ${c.symbol}… ${Math.round((t - start) / (end - start) * 100)}% · ${ticks.length.toLocaleString("vi-VN")} tick`;
            const path = `/mt5/ticks?symbol=${encodeURIComponent(c.symbol)}&from=${Math.floor(t)}&to=${Math.floor(Math.min(end, t + 3600))}`;
            try {
              const r = await Promise.race([this.call(path), new Promise((_, no) => setTimeout(() => no(new Error("máy chủ không trả lời sau 60 giây")), 60000))]);
              ticks = ticks.concat(r.ticks || []);
            } catch (e) {
              if (ServerTooOld(e)) throw new Error("Máy chủ VPS chưa có tải tick: vào tab Máy chủ → Cập nhật lên bản 5.1");
              failed++; lastError = plain(e.message);
              if (failed >= 3 && !ticks.length) throw new Error("Không tải được tick (" + lastError + "). Thử chọn 'Nến (ước lượng)' hoặc mở MT5 trên VPS để nó tải lịch sử tick.");
            }
          }
          if (ticks.length < 100) throw new Error("MT5 không trả đủ tick cho khoảng này (cập nhật máy chủ lên 5.1?)");
          // Another account type: its spread over the real bid of every tick.
          if (simSpread != null) ticks = ticks.map(([t, b]) => [t, b, b + simSpread]);
        } else if ($("btSrc")) store.set("aurum.btSrc", "bars");
        // The tick bot: the 1-minute bars inside its candles show the way price went in each.
        let sub = null;
        if (bot === "tick" && sec > 60 && !ticks) {
          info.textContent = `Đang tải nến 1m ${c.symbol} cho đường đi giá trong từng cây nến…`;
          const p1 = (before) => `/mt5/candles?symbol=${encodeURIComponent(c.symbol)}&interval=1m&count=5000${before ? `&before=${before}` : ""}`;
          sub = this.toBars((await this.call(p1())).candles || []);
          for (let k = 0; k < 40 && sub.length && sub[0].time > from; k++) {
            const older = this.toBars((await this.call(p1(sub[0].time))).candles || []).filter((b) => b.time < sub[0].time);
            if (!older.length) break;
            sub = older.concat(sub);
          }
        }
        this.btData = { key: `${c.symbol}|${c.interval}|${days}|${ticks ? "t" : "b"}`, bars, sub, spread, value, c, ticks };
        const r = bot === "grid" ? gridBotOnTicks(ticks || barsAsTicks(bars, spread), c, value) : bot === "sr" ? srBacktest(bars, c, value, spread) : bot === "tick" ? (ticks ? tickBotOnTicks(ticks, c, value) : tickBotBacktest(bars, c, value, spread, sub)) : stopBotBacktest(bars, c, value, spread);
        if (ticks) spread = ticks.reduce((a, x) => a + (x[2] - x[1]), 0) / ticks.length;
        this.btShow = 30;
        this.btResult = { bot, spread, commission, acct, c, ticks: ticks ? ticks.length : 0, bars: bars.length, from: bars[0].time, to: bars[bars.length - 1].time + sec, balance, placed: r.placed, trades: r.trades, grid: r.grid, digits: this.digitsFor(c.symbol) };
        info.textContent = "";
        this.renderStopBtResult();
      } catch (e) {
        info.textContent = "Không chạy được: " + plain(e.message);
      } finally { btn.disabled = false; }
    },

    /** The tick bot's settings tried over a grid on the loaded Exness bars: picked on the first two thirds,
     *  checked on the last third (bars it never saw), so a lucky fit shows as a loss there. */
    async optimizeTickBot() {
      const info = $("btInfo"), btn = $("btOpt");
      const days = +$("btDays").value, c0 = this.tickSettings();
      const src = $("btSrc") && $("btSrc").value === "ticks" ? "t" : "b";
      if (!this.btData || this.btData.key !== `${c0.symbol}|${c0.interval}|${days}|${src}`) {
        $("btBot").value = "tick";
        await this.runStopBt();
        if (!this.btData) return;
      }
      const { bars, sub, value, ticks } = this.btData;
      const spread = c0.noSpread ? 0 : this.btData.spread;
      // Real ticks when loaded (the first two thirds of them to choose, the rest to check), else bars.
      const series = ticks || bars, cut = Math.floor(series.length * 2 / 3);
      const train = series.slice(0, cut), test = series.slice(cut);
      const run = (part, c) => (ticks ? tickBotOnTicks(part, c, value) : tickBotBacktest(part, c, value, spread, sub));
      const tOf = (x) => (ticks ? x[0] / 1000 : x.time);
      const grid = [];
      for (const step of [0.2, 0.3, 0.5, 0.8, 1.2]) for (const closeProfit of [0.3, 0.5, 1, 1.5, 2.5])
        for (const sl of [0.3, 0.5, 1, 2]) for (const withCandle of [true, false]) for (const maxPositions of [1, 3])
          grid.push({ step, closeProfit, sl, withCandle, maxPositions, burst: 1, flipExit: true });
      const net = (r) => r.trades.reduce((a, x) => a + x.profit, 0);
      const out = [];
      btn.disabled = true;
      try {
        for (let i = 0; i < grid.length; i++) {
          const c = Object.assign({}, c0, grid[i]);
          const a = run(train, c), b = run(test, c);
          const wins = a.trades.filter((x) => x.profit > 0).length;
          out.push({ p: grid[i], train: net(a), test: net(b), n: a.trades.length, nt: b.trades.length, win: a.trades.length ? wins / a.trades.length : 0 });
          if (i % 8 === 7) { info.textContent = `Đang thử ${i + 1}/${grid.length} cài đặt…`; await new Promise((r) => setTimeout(r, 0)); }
        }
      } finally { btn.disabled = false; }
      info.textContent = "";
      out.sort((x, y) => y.train - x.train);
      const top = out.slice(0, 12), bestTest = Math.max(...out.map((x) => x.test));
      const d = (v) => `<b class="${v >= 0 ? "pos" : "neg"}">${signed(v)}</b>`;
      const day = (t) => new Date(t * 1000).toLocaleDateString("vi-VN", { day: "2-digit", month: "2-digit" });
      const hm = (t) => new Date(t * 1000).toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
      $("btResult").innerHTML = `<h4>🔎 ${grid.length} cài đặt trên ${ticks ? `<b>${ticks.length.toLocaleString("vi-VN")} tick thật</b>` : "nến (ước lượng)"} · chọn trên ${hm(tOf(train[0]))} → ${hm(tOf(train[train.length - 1]))}, kiểm tra trên ${hm(tOf(test[0]))} → ${hm(tOf(test[test.length - 1]))}</h4>
        <p class="small">${top.length && top[0].test > 0 ? "Cài đặt đứng đầu vẫn <b>lời ở phần kiểm tra</b> (dữ liệu nó chưa thấy): có thể thử chạy ảo." : `<b class="neg">Không cài đặt nào đứng đầu giữ được lời ở phần kiểm tra</b> (tốt nhất ${signed(bestTest)}): trên dữ liệu này, kiểu vào lệnh theo nhịp giá ngắn không có lợi thế, spread và nhiễu ăn hết. Nên đổi khung lớn hơn, thêm lọc (giờ phiên, xu hướng) hoặc giảm số lệnh.`}</p>
        <div class="list">${top.map((x, i) => `<div class="sig opt-row" data-i="${i}"><div class="bar" style="background:${x.test >= 0 ? "var(--up)" : "var(--down)"}"></div><div><div class="top"><b>#${i + 1}</b> bước ${x.p.step} · chốt ${x.p.closeProfit} · SL ${x.p.sl} · ${x.p.withCandle ? "thuận nến" : "2 chiều"} · tối đa ${x.p.maxPositions}</div>
          <div class="lv">Phần chọn: ${d(x.train)} · ${x.n} lệnh · thắng ${Math.round(x.win * 100)}% &nbsp;|&nbsp; Phần kiểm tra: ${d(x.test)} · ${x.nt} lệnh</div></div>
          <div class="right"><button class="btn btn-ghost btn-small" type="button" data-use="${i}">Dùng</button></div></div>`).join("")}</div>`;
      $("btResult").querySelectorAll("[data-use]").forEach((b) => (b.onclick = () => {
        const p = top[+b.dataset.use].p, set = (id, v) => { if ($(id)) $(id).value = v; };
        set("tbStep", p.step); set("tbClose", p.closeProfit); set("tbSL", p.sl); set("tbMax", p.maxPositions); set("tbBurst", 1);
        if ($("tbWith")) $("tbWith").checked = p.withCandle;
        if ($("tbFlip")) $("tbFlip").checked = true;
        toast("Đã điền cài đặt vào ô Bot nến tick: chuyển sang 🎮 Chạy thử, bấm Lưu / Bật");
      }));
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
      const grid = R.bot === "grid";
      const reason = grid ? { basket: "chốt rổ", lock: "khoá lời nhồi", trail: "trailing", flip: "tín hiệu ngược", guard: "tránh giờ mạnh", sl: "SL rổ", stop: "cắt lỗ chung", end: "đóng cuối test" } : R.bot === "tick" ? { target: "chốt lời", stop: "cắt lỗ chung", sl: "cắt lỗ lệnh", flip: "nến đảo chiều", hold: "hết giờ giữ", end: "đóng cuối test", close: "hết nến" }
        : { target: "chạm TP", stop: "chạm SL", trail: "chạm SL đã dời", end: "đóng cuối test", close: "hết nến" };
      const sr = R.bot === "sr" || R.bot === "tick" || grid, tick = R.bot === "tick";
      const G = R.grid || {}, gc = R.c;
      const gridHead = `<p class="muted small">🕸️ Nhồi lệnh · ${esc(gc.symbol)} · ${R.ticks ? `<b>${R.ticks.toLocaleString("vi-VN")} tick thật</b> · spread TB` : "nến 1m (ước lượng) · spread"} ${fmt(R.spread, R.digits)}${R.acct && R.acct !== "real" ? ` · <b>giả lập ${esc(ACCOUNT_SIMS[R.acct].name.split(" (")[0])}</b>${R.commission ? ` (phí ${R.commission}$/lot)` : ""}` : ""} · ${day(R.from)} → ${day(R.to)} · lot đầu ${gc.lots} · <b>nhồi ${gc.addMode === "with" ? "dương" : "âm"}</b> mỗi ${gc.gridStep} · ×${gc.multiplier} · tối đa ${gc.maxLevels} lớp · chốt rổ ${gc.tpMoney > 0 ? money(gc.tpMoney) : "tắt"}${gc.sl > 0 ? ` · SL rổ ${gc.sl} giá` : ""}${gc.slMoney > 0 ? ` · SL rổ ${money(gc.slMoney)}` : ""}${gc.trailOn ? ` · trailing ${gc.trailDist} sau khi lời ${gc.trailStart}` : ""}${gc.nyGuard ? ` · tránh ${gc.nyFrom}–${gc.nyTo} NY` : ""}${gc.newsGuard ? ` · tránh tin đỏ ±${gc.newsBefore}/${gc.newsAfter}p${gc._news ? ` (${gc._news.filter((e) => e.country === "USD" && e.impact === "High").length} tin)` : ""}` : ""}${gc.entry === "signal" ? ` · <b>vào 1 bên theo tín hiệu</b>: ${[gc.sigCandle ? `nến ${gc.sigTf} ≥${gc.sigBody}%` : "", gc.sigSr !== "off" ? `${{ auto: "cản M1 tự động", bounce: "bật cản M1", break: "phá cản M1" }[gc.sigSr] || "cản M1"} ${gc.srBars} nến ±${gc.srZone}` : "", gc.sigTick ? `tick ${gc.tickMove}/${gc.tickSec}s` : "", gc.waitSec > 0 ? `chờ ${gc.waitSec}s sau khi nến đóng` : "", gc.levelGuard ? `đợi xác nhận ở đỉnh/đáy ±${gc.levelRoom}` : "", gc.sigSwing ? `nến đảo chiều ở đỉnh/đáy ${gc.structTf}` : "", gc.sigZone && gc.sigZone !== "off" ? `phản ứng ${gc.sigZone === "both" ? "FVG + OB" : gc.sigZone.toUpperCase()} ${gc.structTf}` : ""].filter(Boolean).join(" + ")} (${(gc.sigNeed || "all") === "all" ? "cần đủ" : "cần 2 đồng ý"})${gc.confirmAdd ? " · nhồi khi giá quay đầu" : ""}` : ""}${gc.entry !== "signal" && gc.bias && gc.bias !== "off" ? ` · lực nến ${gc.biasTf} ≥${gc.biasMinBody}% (${gc.bias === "only" ? "chỉ bên mạnh" : `bên mạnh ×${gc.biasLotMult} lot`})` : ""} · cắt lỗ chung ${gc.basketStop ? money(gc.basketStop) : "tắt"}${gc.direction === "long" ? " · chỉ rổ MUA" : gc.direction === "short" ? " · chỉ rổ BÁN" : ""}</p>`;
      el.innerHTML = `${grid ? gridHead : `<p class="muted small">${tick ? "⚡ Nến tick" : sr ? "🧱 Cản & Hỗ trợ" : "🎯 Stop theo nến"} · ${esc(R.c.symbol)} ${R.c.interval} · ${R.ticks ? `<b>${R.ticks.toLocaleString("vi-VN")} tick thật</b> · spread TB` : "spread"} ${fmt(R.spread, R.digits)}${R.acct && R.acct !== "real" ? ` · <b>giả lập ${esc(ACCOUNT_SIMS[R.acct].name.split(" (")[0])}</b>${R.commission ? ` (phí ${R.commission}$/lot)` : ""}` : ""} · ${day(R.from)} → ${day(R.to)} · ${R.bars} nến · ${R.c.lots} lot · ${tick ? `bước ${R.c.step} · chốt lời ${R.c.closeProfit} · SL ${R.c.sl || "không"}${R.c.withCandle ? " · thuận chiều nến" : ""}${R.c.flipExit ? " · đóng khi nến đảo" : ""} · tối đa ${R.c.maxPositions} lệnh · cắt lỗ chung ${R.c.basketStop ? money(R.c.basketStop) : "tắt"}${R.c.exitAtClose !== false ? " · đóng khi hết nến" : ""}` : `R:R ${R.c.rr}`}${R.c.direction === "long" ? " · chỉ Buy" : R.c.direction === "short" ? " · chỉ Sell" : ""}</p>`}
        <div class="stats">
          ${stat("Lãi/lỗ ròng", signed(net), net >= 0 ? "pos" : "neg")}
          ${stat("Số lệnh", `${t.length} <span class="muted small">/ ${R.placed} ${sr ? "tín hiệu" : "lệnh chờ đặt"}</span>`)}
          ${stat("Thắng", t.length ? `${wins.length}/${t.length} · ${Math.round(wins.length / t.length * 100)}%` : "–")}
          ${grid && gc.entry === "signal" ? stat("Lệnh MUA / BÁN", `${t.filter((x) => x.side === "long").length} / ${t.filter((x) => x.side === "short").length}${G.flips ? ` <span class="muted small">· ${G.flips} lần đảo chiều</span>` : ""}`) : ""}
          ${grid ? (gc.trailOn ? stat("Lệnh chốt bằng trailing", `${G.trails || 0} · <b class="${t.filter((x) => x.reason === "trail").reduce((a, x) => a + x.profit, 0) >= 0 ? "pos" : "neg"}">${signed(t.filter((x) => x.reason === "trail").reduce((a, x) => a + x.profit, 0))}</b>`) : "") + stat("Rổ chốt lời / SL rổ / cắt lỗ chung", `${G.cycles || 0} / <b class="${G.sls ? "neg" : ""}">${G.sls || 0}</b> / <b class="${G.stops ? "neg" : ""}">${G.stops || 0}</b>`)
            + stat("Âm sâu nhất khi đang gồng", signed(G.maxFloat || 0), (G.maxFloat || 0) < 0 ? "neg" : "")
            + (gc.entry === "signal" ? stat("Rổ mở theo tín hiệu", `${t.filter((x) => x.layer === 1).length}`) : "")
            + stat("Lớp sâu nhất / lot mở nhiều nhất", `${G.maxLevel || 0} lớp · ${G.maxLots || 0} lot`) : ""}
          ${grid ? "" : stat(tick ? "Chốt lời / cắt lỗ chung" : "Chạm TP / SL", `${tp} / ${sl}${tick ? ` <span class="muted small">· ${t.filter((x) => x.reason === "sl").length} cắt lỗ lệnh · ${t.filter((x) => x.reason === "flip").length} nến đảo · ${t.filter((x) => x.reason === "close").length} hết nến</span>` : sr ? ` <span class="muted small">· ${t.filter((x) => x.reason === "trail").length} SL dời</span>` : ""}`)}
          ${stat("Profit factor", gl > 0 ? (gp / gl).toFixed(2) : gp > 0 ? "∞" : "–")}
          ${stat("Sụt giảm lớn nhất", dd ? "−" + money(dd) : "0", dd ? "neg" : "")}
          ${stat("Lời TB / lỗ TB", `${wins.length ? signed(gp / wins.length) : "–"} / ${losses.length ? signed(-gl / losses.length) : "–"}`)}
          ${stat("Vốn cuối", money(R.balance + net), net >= 0 ? "pos" : "neg")}
          ${(() => { const rb = +store.get("aurum.rebate") || 0; if (!rb) return ""; const lots = t.reduce((a, x) => a + (x.lots || R.c.lots || 0), 0), got = lots * rb;
            return stat("Backcom nhận", `${signed(got)} <span class="muted small">· ${lots.toFixed(2)} lot</span>`, "pos") + stat("Ròng sau backcom", signed(net + got), net + got >= 0 ? "pos" : "neg"); })()}
        </div>
        ${t.length ? `<svg class="bt-eq" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"><polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2" vector-effect="non-scaling-stroke"/></svg>` : ""}
        <div class="row-btns"><button class="btn btn-ghost" id="btChart" type="button" ${t.length ? "" : "disabled"}>📈 Xem các lệnh trên biểu đồ</button></div>
        <h4>Lệnh (mới nhất trước)</h4>
        <div class="list bt-trades">${t.length ? t.slice().reverse().slice(0, this.btShow || 30).map((x) => `<div class="sig"><div class="bar" style="background:${x.profit >= 0 ? "var(--up)" : "var(--down)"}"></div>
          <div><div class="top"><span class="side ${x.side === "long" ? "buy" : "sell"}">${sr ? (x.side === "long" ? "BUY" : "SELL") : x.side === "long" ? "BUY STOP" : "SELL STOP"}</span>
            <span class="muted small">${fmt(x.entry, d)} → ${fmt(x.exit, d)}</span></div>
            <div class="lv">${reason[x.reason]}${x.layer ? ` · lớp ${x.layer} · ${x.lots} lot` : ""}${x.level != null ? ` · vùng ${fmt(x.level, d)}` : ""} · ${clock(x.openTime)} ${day(x.openTime)}${grid ? "" : ` · SL ${fmt(x.stop, d)} · TP ${x.target != null ? fmt(x.target, d) : "–"}`}</div></div>
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
        const [st, hist] = await Promise.all([this.botCall("/status"), this.botCall("/history?limit=200")]);
        this.autoFull = { st, hist: (hist && hist.history) || [] };
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
      if (stop) stop.onclick = async (e) => { await act(e.currentTarget, () => this.botCall("/stop", {}), "Đã dừng bot"); this.loadAutoBot(false); };
      if (restart) restart.onclick = async (e) => { await act(e.currentTarget, () => this.botCall("/start", {}), "Bot đã chạy"); this.loadAutoBot(false); };
      if (reset) reset.onclick = async (e) => {
        const v = prompt("Số dư demo mới (USD):", "10000");
        if (!v || !num(v)) return;
        await act(e.currentTarget, () => this.botCall("/reset", { balance: num(v) }), "Đã đặt lại tài khoản demo");
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
        const ok = await act(e.currentTarget, () => this.botCall("/start", body), "Bot đã chạy");
        if (ok) this.loadAutoBot(false);
      };
      this.applyBotHub();
    },

    renderBotTrades(st, history) {
      const pos = st.positions || [];
      const d = (sym) => this.digitsFor(sym);
      $("botPosTitle").textContent = pos.length ? `Lệnh của bot · ${pos.length}` : "Lệnh của bot";
      $("botCloseAll").hidden = !pos.length;
      $("botCloseAll").onclick = async (e) => {
        if (!confirm(`Đóng ${pos.length} lệnh của bot?`)) return;
        await act(e.currentTarget, () => this.botCall("/close", { all: true }), "Đã đóng lệnh của bot");
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
        await act(e.currentTarget, () => this.botCall("/close", { id: p.id }), "Đã đóng lệnh");
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
        // Its own box, refreshed every 15 s and only redrawn when something changed (no flicker).
        if (first || !this.ownAt || Date.now() - this.ownAt > 15000) { this.ownAt = Date.now(); this.renderOwnAccount(); }
        if ($("mt5Login") && !$("mt5Login").innerHTML) this.renderMt5Login();
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

    /** "Tài khoản MT5 riêng cho máy tính": a second copy of the server on the VPS with its own MT5 login, so
     *  this computer (e.g. a demo account for the bots) and the app (the main account) do not share one. */
    async renderOwnAccount() {
      const box = $("ownAcctBox");
      if (!box) return;
      let w = null, problem = "";
      try { w = await this.mainCall("/webacct"); } catch (e) { problem = ServerTooOld(e) ? "Cập nhật máy chủ lên bản 4.7 để dùng." : plain(e.message); }
      const use = store.get("aurum.useWebAcct") === "1";
      const html = `<h4>🖥️ Tài khoản MT5 riêng cho máy tính</h4>
        <p class="muted small">Máy chủ VPS chạy thêm một MT5 thứ 2 với tài khoản riêng (ví dụ tài khoản <b>demo</b>) <b>chỉ cho bot</b>: tab Bot trên máy tính này xem và chạy bot trên tài khoản đó, còn tab Biểu đồ vẫn trade tay trên <b>tài khoản chính</b> (app cũng vậy) — không cần đăng nhập qua lại. Bot chạy 24/24 trên VPS, tắt web vẫn chạy. Lần đầu bật, máy chủ sao chép MT5 (vài phút).</p>
        ${problem ? `<p class="warn">${esc(problem)}</p>` : ""}
        ${w ? `<div class="kvs"><div class="kv"><span>Máy chủ thứ 2</span><b>${w.enabled ? (w.running ? `đang chạy · cổng ${w.port}` : "đang khởi động…") : "đang tắt"}</b></div>
          <div class="kv"><span>MT5 của nó</span><b>${w.info && w.info.mt5 ? (w.info.mt5.connected ? "đã kết nối" : esc(w.info.mt5.error || "chưa đăng nhập")) : "–"}</b></div>
          <div class="kv"><span>Tab Bot trên máy tính này</span><b>${this.ownAccount ? "🖥️ chạy trên tài khoản riêng" : "dùng tài khoản chính"}</b></div></div>
          ${w.error ? `<p class="warn">${esc(w.error)}</p>` : ""}
          <div class="row-btns">
            <button class="btn ${w.enabled ? "btn-ghost" : "btn-gold"}" id="ownToggle" type="button">${w.enabled ? "■ Tắt máy chủ thứ 2" : "▶ Bật tài khoản riêng cho máy tính"}</button>
            ${w.enabled ? `<button class="btn ${use ? "btn-ghost" : "btn-gold"}" id="ownUse" type="button">${use ? "Bot về tài khoản chính" : "Bot chạy trên tài khoản riêng"}</button>` : ""}
          </div>
          ${w.enabled ? `<div id="ownLogin"></div>` : ""}` : ""}`;
      // Same as on screen: leave it (and the login form being typed in) alone.
      if (html === this.ownHtml && box.innerHTML) return;
      this.ownHtml = html;
      box.innerHTML = html;
      if (w && w.enabled && w.running && w.url) this.renderOwnLogin(w.url);
      const toggle = $("ownToggle"), useBtn = $("ownUse");
      if (toggle) toggle.onclick = async (e) => {
        const on = !w.enabled;
        const r = await act(e.currentTarget, () => this.mainCall("/webacct", { enabled: on }), on ? "Đang bật máy chủ thứ 2 (lần đầu vài phút)…" : "Đã tắt");
        if (r) { if (!on && use) { store.set("aurum.useWebAcct", null); location.reload(); return; } this.renderOwnAccount(); }
      };
      if (useBtn) useBtn.onclick = () => {
        store.set("aurum.useWebAcct", use ? null : "1");
        toast(use ? "Bot về tài khoản chính" : "Bot chạy trên tài khoản riêng");
        setTimeout(() => location.reload(), 600);
      };
    },

    /** The second copy's own MT5 login (for the bots): who is logged in there, and a form to log in. */
    async renderOwnLogin(url) {
      const box = $("ownLogin");
      if (!box) return;
      const own = (path, body) => api(url, this.secret, path, body);
      let t = null;
      try { t = await own("/mt5/trading"); } catch { /* not logged in yet */ }
      box.innerHTML = `<div class="fp-sec" style="margin-top:10px">Tài khoản MT5 cho bot</div>
        <p class="small">${t && t.login ? `Đang đăng nhập <b>#${esc(String(t.login))}</b> · ${esc(t.server || "")} · ${t.mode === "real" ? '<b class="neg">TÀI KHOẢN THẬT</b>' : "demo"}` : "Chưa đăng nhập: nhập tài khoản demo Exness để bot chạy."}</p>
        <div class="fields three">
          <label>Số tài khoản<input id="olLogin" inputmode="numeric" placeholder="VD 123456789"></label>
          <label>Mật khẩu<input id="olPass" type="password" autocomplete="off"></label>
          <label>Máy chủ<input id="olServer" placeholder="VD Exness-MT5Trial15" value="${esc((t && t.server) || "")}"></label>
        </div>
        <div class="row-btns"><button class="btn btn-gold" id="olGo" type="button">Đăng nhập cho bot</button></div>`;
      $("olGo").onclick = async (e) => {
        const login = $("olLogin").value.trim(), password = $("olPass").value, server = $("olServer").value.trim();
        if (!login || !password || !server) return toast("Nhập đủ số tài khoản, mật khẩu, máy chủ", true);
        const r = await act(e.currentTarget, () => own("/mt5/login", { server, login, password, remember: true }), "Đã đăng nhập tài khoản cho bot");
        if (r) this.renderOwnLogin(url);
      };
    },

    /** The MT5 accounts, like the app's "Đăng nhập sàn": the saved accounts kept on the VPS (shared with the
     *  app: an account logged in from the app is here too) with one tap to switch, and a form to add one.
     *  Passwords stay on the owner's server; the browser keeps none. */
    async renderMt5Login() {
      const box = $("mt5Login");
      if (!box) return;
      const t = this.account || {};
      let list = null;
      try { list = (await this.call("/mt5/accounts")).accounts || []; } catch { list = null; }
      const cur = (a) => a.current || (t.login && +a.login === +t.login && a.server === t.server);
      if (list && t.login && !list.some(cur)) list.unshift({ login: t.login, server: t.server, broker: t.company || "", hasPassword: false, current: true });
      const isReal = (a) => (cur(a) ? t.mode === "real" : a.mode ? a.mode === "real" : /real/i.test(a.server) || !/(trial|demo)/i.test(a.server));
      const rows = (list || []).map((a, i) => `<div class="row acct-row${cur(a) ? " on" : ""}" data-i="${i}">
          <span class="acct-seal ${isReal(a) ? "real" : ""}">✦</span>
          <span class="grow"><b>#${esc(String(a.login))}</b><br><span class="muted small">${esc(a.broker || "MT5")} · ${esc(a.server)}${isReal(a) ? " · thật" : " · demo"}</span></span>
          ${cur(a) ? `<span class="tag-on">Đang dùng</span>${t.balance != null ? `<span class="muted small" style="margin-left:8px">${fmt(t.balance, 2)} ${esc(t.currency || "")}</span>` : ""}`
            : `<button type="button" class="btn btn-small" data-sw="${i}">Chuyển</button><button type="button" class="btn btn-small btn-ghost" data-del="${i}" title="Xoá khỏi danh sách">✕</button>`}
        </div>`).join("");
      box.innerHTML = `<div class="panel-head"><h3>Tài khoản MT5</h3>${t.login ? '<button class="btn btn-ghost btn-small" id="mtOut" type="button">Đăng xuất</button>' : ""}</div>
        ${list == null ? '<p class="muted small">Máy chủ chưa có danh sách tài khoản chung (cần cập nhật máy chủ lên bản 3.7). Vẫn đăng nhập được ở dưới.</p>' : ""}
        ${rows ? `<div class="list">${rows}</div>` : list ? '<p class="muted small">Chưa có tài khoản nào. Thêm ở dưới (tài khoản đã đăng nhập trên app cũng hiện ở đây sau khi mở app một lần).</p>' : ""}
        <details class="acct-add" ${list && list.length ? "" : "open"}><summary>＋ Thêm tài khoản Exness / MT5</summary>
        <div class="fields two">
          <label>Số tài khoản<input id="mtLogin" inputmode="numeric" autocomplete="username"></label>
          <label>Mật khẩu chính (không phải investor)<input id="mtPass" type="password" autocomplete="current-password"></label>
        </div>
        <div class="fields"><label>Server <span class="muted small">(để trống = tự tìm)</span><input id="mtServer" list="mtServers" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Tự động: server đã dùng, EZSquare-Server…"></label></div>
        <datalist id="mtServers">${[...new Set([...(list || []).map((a) => a.server), "EZSquare-Server", "Exness-MT5Trial", "Exness-MT5Real"])].map((v) => `<option value="${esc(v)}">`).join("")}</datalist>
        <label class="toggle"><span>Lưu để chuyển nhanh (máy chủ giữ mật khẩu, dùng chung với app)</span><span class="switch"><input type="checkbox" id="mtRemember" checked><span></span></span></label>
        <button class="btn btn-gold wide" id="mtIn" type="button">Đăng nhập</button>
        <p class="muted small">Sàn khác Exness (vd EZSquare): MT5 trên VPS phải tìm được server đó trước — trong MT5: Tệp → Mở tài khoản → tìm tên sàn → đăng nhập một lần.</p></details>`;
      const after = async (r, what) => {
        if (!r) return;
        this.htfData = null;
        try { await this.refreshOwner(); } catch { /* shown by the next refresh */ }
        this.loadCandles();
        this.renderMt5Login();
        toast(what);
      };
      // A saved account's number typed: its server filled in.
      $("mtLogin").oninput = () => {
        const n = $("mtLogin").value.replace(/\D/g, ""), hit = (list || []).find((a) => String(a.login) === n);
        if (hit && !$("mtServer").value) $("mtServer").value = hit.server;
      };
      box.querySelectorAll("[data-sw]").forEach((b) => (b.onclick = async () => {
        const a = list[+b.dataset.sw];
        if (!confirm(`Chuyển sang tài khoản #${a.login} (${a.server})?${t.login ? `\nĐang dùng #${t.login} sẽ được thay.` : ""}`)) return;
        let password = null;
        if (!a.hasPassword) { password = prompt(`Mật khẩu chính của #${a.login} (${a.server})`); if (!password) return; }
        const r = await act(b, () => this.call("/mt5/switch", password ? { login: a.login, server: a.server, password } : { login: a.login, server: a.server }));
        after(r, `Đã chuyển sang #${a.login}`);
      }));
      box.querySelectorAll("[data-del]").forEach((b) => (b.onclick = async () => {
        const a = list[+b.dataset.del];
        if (!confirm(`Xoá #${a.login} (${a.server}) khỏi danh sách đã lưu (cả trên app)?`)) return;
        const r = await act(b, () => this.call("/mt5/forget", { login: a.login, server: a.server }), "Đã xoá");
        if (r) this.renderMt5Login();
      }));
      $("mtIn").onclick = async (e) => {
        // MT5 server names have no spaces: "EZSquare Server" → "EZSquare-Server".
        const server = $("mtServer").value.trim().replace(/\s+/g, "-"), login = $("mtLogin").value.replace(/\D/g, ""), password = $("mtPass").value;
        if (!login || !password) return toast("Cần số tài khoản và mật khẩu", true);
        const r = await act(e.currentTarget, () => this.call("/mt5/login", { server, login, password, remember: $("mtRemember").checked }));
        if (r && r.server) toast(`Server: ${r.server}`);
        $("mtPass").value = "";
        after(r, `Đã đăng nhập #${login}`);
      };
      const out = $("mtOut");
      if (out) out.onclick = async (e) => {
        if (!confirm("Đăng xuất tài khoản MT5 trên VPS? Danh sách đã lưu vẫn giữ. Bot đang dùng MT5 phải dừng trước.")) return;
        const r = await act(e.currentTarget, () => this.call("/mt5/logout", {}), "Đã đăng xuất MT5");
        if (r) { this.account = Object.assign({}, this.account, { login: 0 }); this.renderMt5Login(); }
      };
    },

    renderMt5Settings() {
      const t = this.account || {};
      this.renderMt5Login();
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
          kineticScroll: { mouse: true, touch: true },
          layout: { background: { color: "#050506" }, textColor: "#8b95a7", fontFamily: "-apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif" },
          grid: { vertLines: { color: "#1a2233" }, horzLines: { color: "#1a2233" } },
          rightPriceScale: { borderColor: "#1e1e23" },
          timeScale: { borderColor: "#1e1e23", timeVisible: true, secondsVisible: false, rightOffset: 8, barSpacing: el.clientWidth < 500 ? 4 : 6 },
          localization: { timeFormatter: (t) => this.timeLabel(t) },
          crosshair: { mode: 0 },
        });
        this.series = this.chart.addCandlestickSeries({
          upColor: "#14b88a", downColor: "#f0455a", borderVisible: false, wickUpColor: "#14b88a", wickDownColor: "#f0455a",
          // The picked trade's SL/TP and the pending draft stay in view so they can be dragged.
          autoscaleInfoProvider: (original) => {
            const res = original();
            const keep = (this.lineCache || []).filter((w) => {
              if (w.key.startsWith("draft:")) return w.key === "draft:entry";
              const s = this.selected;
              return s && w.key.startsWith(`${s.kind}:${s.ticket}:`);
            }).map((w) => w.price)
              // The TP of a trade with its angler / hauler on it: the character stands there.
              .concat(this.crewShowing ? this.crewShowing().map((t) => t.tp) : []);
            if (!res || !keep.length) return res;
            let minValue = Math.min(res.priceRange.minValue, ...keep), maxValue = Math.max(res.priceRange.maxValue, ...keep);
            // An angler sits on a BUY's TP: room above it for her whole figure.
            const buys = this.crewShowing ? this.crewShowing().filter((t) => t.buy) : [];
            if (buys.length) maxValue = Math.max(maxValue, ...buys.map((t) => t.tp + (maxValue - minValue) * 0.4));
            return { priceRange: { minValue, maxValue }, margins: res.margins };
          },
        });
        // Every bar fed to the candles also goes to the series of the chosen chart type (line, bars…).
        {
          const s = this.series, set = s.setData.bind(s), upd = s.update.bind(s);
          s.setData = (data) => { set(data); this.altSet(data); };
          s.update = (bar) => { upd(bar); this.altUpdate(bar); };
        }
        this.ictCfg = (() => { try { return window.ICT.merge(JSON.parse(store.get("aurum.ictcfg") || "null")); } catch { return window.ICT.defaults(); } })();
        const loadCfg = (lib, key) => (lib ? (() => { try { return lib.merge(JSON.parse(store.get(key) || "null")); } catch { return lib.defaults(); } })() : null);
        this.macroCfg = loadCfg(window.MACRO, "aurum.macrocfg");
        this.liqCfg = window.LIQ ? (() => { try { return window.LIQ.merge(JSON.parse(store.get("aurum.liqcfg") || "null")); } catch { return window.LIQ.defaults(); } })() : null;
        this.planCfg = window.PLAN ? (() => { try { return window.PLAN.merge(JSON.parse(store.get("aurum.plancfg") || "null")); } catch { return window.PLAN.defaults(); } })() : null;
        this.modelCfg = window.MODELS ? (() => { try { return window.MODELS.merge(JSON.parse(store.get("aurum.modelcfg") || "null")); } catch { return window.MODELS.defaults(); } })() : null;
        // Off unless turned on (TradingView's default): points go where the mouse / finger is, not onto the candle.
        this.magnet = store.get("aurum.magnet") === "1";
        this.lastSmtSymbol = this.ictCfg.smtSymbol;
        this.loadStudies();
        this.series.attachPrimitive(this.layer());
        Object.assign(this, this.axisViews());
        setInterval(() => { if (this.tab === "chart") { this.repaint(); if (document.body.classList.contains("chart-full")) { this.updateLegend(); this.updateClock(); } } }, 1000);
        this.chart.subscribeCrosshairMove((param) => {
          if (!document.body.classList.contains("chart-full")) return;
          const d = param && param.point && param.seriesData ? param.seriesData.get(this.series) : null;
          this.legendBar = d && d.open != null ? d : null;
          this.updateLegend();
        });
        setInterval(() => { if (this.tab === "chart") this.updateMascotMoods(); }, 1500);
        this.drawings = this.drawingsMain = new window.AurumDrawings({
          chart: this.chart, series: this.series, store,
          bars: () => this.viewBars(), sec: () => TF_SECONDS[this.interval], digits: () => this.digits,
          symbol: () => this.symbolKey(), magnet: () => this.magnet,
          onChange: () => this.drawingsChanged(this.drawingsMain),
          onSave: (dr) => this.pushDrawings(dr),
          interval: () => this.interval, onEdit: (d, isNew) => this.drawingSettings(d, isNew),
        });
        // The app's drawings of this market (through the VPS), every few seconds while the chart shows.
        setInterval(() => { if (this.tab === "chart" && !document.hidden) this.pullDrawings(); }, 8000);
        this.chartStyle = loadChartStyle();
        this.applyChartStyle();
        this.layout = LAYOUTS.includes(store.get("aurum.layout")) ? store.get("aurum.layout") : "1";
        $("tfButtons").innerHTML = TFS.filter((i) => !TF_MORE.includes(i)).map((i) => `<button type="button" data-tf="${i}"${i === "30s" ? ' class="sec-end" title="Nến giây lấy từ Binance"' : isSecTF(i) ? ' title="Nến giây lấy từ Binance"' : ""}>${i}</button>`
          + (i === "1m" ? `<select class="tf-more" id="tfMore" title="Khung phút khác của MT5"><option value="">M+</option>${TF_MORE.map((m) => `<option value="${m}">${m}</option>`).join("")}</select>` : "")).join("");
        $("tfButtons").querySelectorAll("button").forEach((b) => (b.onclick = () => {
          // Replay goes back days or months: second bars (Binance, the last hours only) cannot follow it there.
          if (this.replay && isSecTF(b.dataset.tf)) { toast("Replay dùng khung từ 1m trở lên (nến giây chỉ có vài giờ gần nhất)", true); return; }
          this.interval = b.dataset.tf; store.set("aurum.tf", this.interval); this.loadCandles();
        }));
        $("tfMore").onchange = (e) => {
          if (!e.target.value) return;
          this.interval = e.target.value; store.set("aurum.tf", this.interval); this.loadCandles();
        };
        this.chart.timeScale().subscribeVisibleLogicalRangeChange((r) => { if (r && r.from < 30 && !(performance.now() < this.olderHold)) this.loadOlder(); });
        this.chart.subscribeCrosshairMove((param) => this.crossFrom(this.chart, param));
        this.bindDrag();
        this.bindTicket();
      }
      this.applySeriesFormat();
      this.loadCandles();
    },

    /** Crosshair time: with seconds on the second charts. */
    timeLabel(t) {
      // "13:46 25-10" by hand: toLocaleString builds a formatter per call, too slow for two charts' axes.
      const d = new Date(t * 1000), p = (n) => (n < 10 ? "0" : "") + n;
      const sec = isSecTF(this.interval) ? ":" + p(d.getUTCSeconds()) : "";
      return `${p(d.getUTCHours())}:${p(d.getUTCMinutes())}${sec} ${p(d.getUTCDate())}-${p(d.getUTCMonth() + 1)}`;
    },

    applySeriesFormat() {
      if (this.series) this.series.applyOptions({ priceFormat: { type: "price", precision: this.digits, minMove: Math.pow(10, -this.digits) } });
    },

    bindTicket() {
      $("sellBtn").onclick = (e) => this.marketOrder("short", e.currentTarget);
      $("buyBtn").onclick = (e) => this.marketOrder("long", e.currentTarget);
      $("lotInput").value = store.get("aurum.lots") || "0.01";
      $("lotInput").onchange = () => { $("lotInput").value = this.lots().toFixed(2); this.setLots($("lotInput"), "aurum.lots"); };
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
        this.setCmpFor(this.symbol, main);
        this.selected = null; this.togglePending(false);
        this.loadCandles();
      };
      $("indBtn").onclick = () => this.indicatorSheet();
      $("undoBtn").onclick = () => this.undoDrawing();
      $("redoBtn").onclick = () => this.redoDrawing();
      $("drawBtn").onclick = () => this.toggleRail();
      $("styleBtn").onclick = () => this.chartStyleSheet();
      $("typeBtn").onclick = (e) => { e.stopPropagation(); const m = $("ctxMenu"); if (m && !m.hidden && m.querySelector(".type-list")) this.closeMenu(); else this.chartTypeMenu(e.currentTarget); };
      this.renderTypeBtn();
      $("fullBtn").onclick = () => this.setFull(!document.body.classList.contains("chart-full"));
      this.setupChartFit();
      if (!this.fullKeys) {
        this.fullKeys = true;
        // F toggles full screen (not while typing); leaving the browser's full screen (Esc) leaves it too.
        document.addEventListener("keydown", (e) => {
          const t = e.target;
          if (e.key !== "f" && e.key !== "F") return;
          if (e.ctrlKey || e.metaKey || e.altKey || (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName)))) return;
          if (this.tab !== "chart" || $("dashView").hidden) return;
          e.preventDefault();
          this.setFull(!document.body.classList.contains("chart-full"));
        });
        document.addEventListener("fullscreenchange", () => {
          if (!document.fullscreenElement && document.body.classList.contains("chart-full") && this.fullNative) this.setFull(false);
        });
        window.addEventListener("resize", () => { if (document.body.classList.contains("chart-full")) this.fitFull(); });
      }
      $("replayBtn").onclick = () => this.startReplayPick();
      $("chartSymbol").onclick = () => this.symbolSheet();

      $("closeAllBtn").onclick = (e) => this.closeAll(e.currentTarget);
    },

    indicatorSheet() {
      const allowed = this.owner || this.features.killzones !== false;
      const flowAllowed = this.owner || this.features.sharkflow !== false;
      sheet.open(`<h3>Chỉ báo</h3>
        <div class="toggles">${IND.filter(([k]) => (k === "flow" || k === "zones" ? flowAllowed : allowed)).map(([k, n]) => `<label class="toggle"><span>${n}</span>
          <span class="switch"><input type="checkbox" data-k="${k}" ${showInd[k] ? "checked" : ""}><span></span></span></label>`).join("")}</div>
        ${flowAllowed ? '<button class="btn btn-ghost wide" id="sharkMore">⚙ Dòng tiền cá mập (màu bong bóng, vùng cung / cầu)</button>' : ""}
        ${allowed ? '<button class="btn btn-ghost wide" id="ictMore">⚙ Cài đặt chi tiết (phiên, màu, FVG, MSS…)</button><button class="btn btn-ghost wide" id="smcMore">⚙ Macro (giờ biến động mạnh)</button><button class="btn btn-ghost wide" id="liqMore">⚙ Vùng thanh khoản (mạnh / vừa)</button><button class="btn btn-ghost wide" id="planMore">⚙ Kế hoạch giao dịch (trend, breakout, vùng H1/H4, tín hiệu)</button>' : ""}
        <h4>Chỉ báo kỹ thuật</h4>
        <div class="list" id="studyList"></div>
        <button class="btn btn-ghost wide" id="ema200Std">＋ EMA 200 chuẩn (như TradingView / MT5: giá đóng cửa, mượt từ nến đầu)</button>
        <select id="addStudy" class="add-study"><option value="">＋ Thêm chỉ báo…</option>${Object.entries(window.TA ? window.TA.STUDIES : {}).map(([k, d]) => `<option value="${k}">${esc(d.name)}</option>`).join("")}</select>
        <p class="muted small">Giờ theo New York như bản TradingView. Chuột phải (hoặc giữ lâu) trên biểu đồ để mở menu.</p>`, (el) => {
        const sharkB = el.querySelector("#sharkMore");
        if (sharkB) sharkB.onclick = () => { sheet.close(); this.sharkSettingsSheet(); };
        const more = el.querySelector("#ictMore");
        if (more) more.onclick = () => { sheet.close(); this.ictSettingsSheet(); };
        const smcB = el.querySelector("#smcMore");
        if (smcB) smcB.onclick = () => { sheet.close(); this.macroSettingsSheet(); };
        const liqB = el.querySelector("#liqMore");
        if (liqB) liqB.onclick = () => { sheet.close(); this.liqSettingsSheet(); };
        const plan = el.querySelector("#planMore");
        if (plan) plan.onclick = () => { sheet.close(); this.planSettingsSheet(); };
        const emaStd = el.querySelector("#ema200Std");
        if (emaStd) emaStd.onclick = () => {
          // The standard EMA 200: length 200 on the close, no offset; an EMA 200 already there is set to it.
          let x = this.studies.find((y) => y.type === "ema" && +y.params.length === 200);
          if (!x) x = this.addStudy("ema");
          x.params = Object.assign({}, x.params, { length: 200, source: "close" });
          if (x.colors[0] === window.TA.STUDIES.ema.colors[0]) x.colors[0] = "#2962ff";
          x.hidden = false; x.dirty = true;
          this.saveStudies(); this.applyStudies(); listStudies();
          toast("EMA 200 chuẩn: 200 nến, giá đóng cửa · đang tải thêm nến cũ cho EMA chính xác");
          if (this.historyCount() > (this.bars || []).length) this.loadCandles();
        };
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
            // The open tab takes the new symbol (or the tab that already has it opens).
            const tabs = this.symTabs(), i = tabs.indexOf(this.symbol);
            if (!tabs.includes(b.dataset.s)) { if (i >= 0) tabs[i] = b.dataset.s; else tabs.push(b.dataset.s); this.saveSymTabs(tabs); }
            this.switchSymbol(b.dataset.s);
          }));
        };
        q.oninput = () => { clearTimeout(timer); timer = setTimeout(search, 250); };
        search();
        setTimeout(() => q.focus(), 50);
      });
    },

    /* ----- symbol tabs: several symbols side by side, one click apart ----- */

    symTabs() {
      try { const t = JSON.parse(store.get("aurum.symTabs") || "[]"); return Array.isArray(t) ? t.filter((x) => typeof x === "string" && x) : []; } catch { return []; }
    },

    saveSymTabs(tabs) { store.set("aurum.symTabs", JSON.stringify([...new Set(tabs)].slice(0, 12))); },

    switchSymbol(symbol) {
      if (!symbol || symbol === this.symbol) { this.renderSymTabs(); return; }
      this.symbol = symbol; store.set("aurum.sym", symbol);
      this.selected = null;
      if (this.draft) this.togglePending(false);
      this.loadCandles();
    },

    renderSymTabs() {
      const box = $("symTabs");
      if (!box) return;
      if (!this.owner || !this.symbol) { box.hidden = true; return; }
      const tabs = this.symTabs();
      if (!tabs.includes(this.symbol)) { tabs.push(this.symbol); this.saveSymTabs(tabs); }
      box.hidden = false;
      box.innerHTML = tabs.map((s) => `<div class="sym-tab${s === this.symbol ? " on" : ""}" data-s="${esc(s)}" role="button" tabindex="0" title="${esc(s)}">
          ${symIcon(s)}<span>${esc(symShort(s))}</span>${tabs.length > 1 ? '<button type="button" class="x" title="Đóng">✕</button>' : ""}</div>`).join("")
        + '<button type="button" class="sym-add" title="Thêm mã">＋</button>';
      box.querySelectorAll(".sym-tab").forEach((t) => {
        t.onclick = (e) => {
          if (e.target.closest(".x")) {
            const list = this.symTabs(), i = list.indexOf(t.dataset.s);
            list.splice(i, 1);
            this.saveSymTabs(list);
            if (t.dataset.s === this.symbol) this.switchSymbol(list[Math.min(i, list.length - 1)]); else this.renderSymTabs();
            return;
          }
          this.switchSymbol(t.dataset.s);
        };
        t.onkeydown = (e) => { if (e.key === "Enter") this.switchSymbol(t.dataset.s); };
      });
      box.querySelector(".sym-add").onclick = () => this.symbolSheet((s) => { this.saveSymTabs(this.symTabs().concat(s)); this.switchSymbol(s); });
      const on = box.querySelector(".on");
      if (on) {
        const a = on.getBoundingClientRect(), c = box.getBoundingClientRect();
        if (a.left < c.left || a.right > c.right) box.scrollLeft += a.left - c.left - 8;
      }
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

    /** Bars to load: 800, or enough for the longest average to settle before the left of the chart
     *  (5 × its length: an EMA 200 then starts where TradingView's / MT5's is, to the cent). */
    historyCount() {
      const longest = Math.max(0, ...(this.studies || []).filter((x) => !x.hidden).map((x) => Math.max(0, ...Object.entries(x.params || {})
        .filter(([k, v]) => typeof v === "number" && /length|slow|period/i.test(k)).map(([, v]) => v))));
      return Math.min(3000, Math.max(800, Math.round(longest * 5)));
    },

    exnessPath(count, before) {
      const extra = before ? `&before=${before}` : "";
      return this.owner
        ? `/mt5/candles?symbol=${encodeURIComponent(this.symbol)}&interval=${this.interval}&count=${count}${extra}`
        : `/member/candles?interval=${this.interval}&count=${count}${extra}`;
    },

    /** The browser tab: the brand's icon with a green ▲ / red ▼ badge, and the open symbol's price, by the
     *  candle now forming on the chart's timeframe (1m on 1m, 5m on 5m…): up while it is above its open. */
    updateTab(reset) {
      const bars = !reset && this.bars && this.bars.length ? this.viewBars() : [];
      const last = bars.length ? bars[bars.length - 1] : null;
      let title = TAB_TITLE, dir = null;
      if (last) {
        const price = !this.replay && this.bid != null ? this.bid : last.close;
        dir = price > last.open ? 1 : price < last.open ? -1 : 0;
        const sym = ($("chartSymbol").textContent || this.symbol || "").replace(/m$/, "") || "XAUUSD";
        title = `${dir > 0 ? "▲" : dir < 0 ? "▼" : "•"} ${fmt(price, this.digits)} ${sym} ${this.interval || ""}`.trim();
      }
      if (document.title !== title) document.title = title;
      if (this.tabDir === dir) return;
      this.tabDir = dir;
      const link = document.querySelector('link[rel="icon"]');
      if (!link) return;
      if (dir == null) { link.type = "image/svg+xml"; link.href = "favicon.svg"; return; }
      tabIcon(dir).then((url) => { if (this.tabDir === dir) { link.type = "image/png"; link.href = url; } });
    },

    toBars(rows) {
      return rows.map((r) => ({ time: r[0], open: r[1], high: r[2], low: r[3], close: r[4], volume: r[5] || 0 }));
    },

    setQuote(data) {
      if (data.bid != null) this.bid = data.bid;
      if (data.ask != null) this.ask = data.ask;
      const last = this.bars.length ? this.bars[this.bars.length - 1].close : null;
      $("bidText").textContent = fmt(this.bid != null ? this.bid : last, this.digits);
      $("askText").textContent = fmt(this.ask != null ? this.ask : last, this.digits);
      $("spread").textContent = spreadText(this.bid, this.ask, this.digits);
      if (this.draft) this.updatePendingLabels();
      this.checkAlerts(this.bid != null ? this.bid : last);
      // The money follows this quote at once (pill, picked trade, chart labels), not the next account read.
      if (this.owner && this.positions.length && !this.replay) {
        this.pillMoney();
        const sb = $("selBar").querySelector("b");
        const x = this.selected && this.selected.kind === "pos" ? this.findSelected() : null;
        if (sb && x) { const v = this.liveProfit(x); sb.textContent = signed(v); sb.className = v >= 0 ? "pos" : "neg"; }
      }
      this.repaint();
    },

    /** The chart layers again (money, quotes, countdown), the extra timeframes' too. */
    repaint() {
      if (this.requestICT) this.requestICT();
      (this.panes || []).forEach((p) => p.repaint());
    },

    async loadCandles() {
      // Replay keeps its moment across timeframes: the end of the bar shown last.
      const replayTime = this.replay ? this.bars[this.replay.idx].time + TF_SECONDS[this.replayInterval || this.interval] - 1 : null;
      this.replayInterval = this.interval;
      document.querySelectorAll("#tfButtons button").forEach((b) => b.classList.toggle("on", b.dataset.tf === this.interval));
      const more = $("tfMore");
      if (more) { more.value = TF_MORE.includes(this.interval) ? this.interval : ""; more.classList.toggle("on", TF_MORE.includes(this.interval)); }
      // The picked timeframe in view on a phone, where the row scrolls.
      const tfBox = $("tfButtons"), tfOn = tfBox.querySelector(".on");
      if (tfOn) {
        const a = tfOn.getBoundingClientRect(), c = tfBox.getBoundingClientRect();
        if (a.left < c.left || a.right > c.right) tfBox.scrollLeft += a.left - c.left - 8;
      }
      if (this.socket) { this.socket.close(); this.socket = null; }
      clearInterval(this.pollTimer); this.pollTimer = null;
      this.stopTicks();
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
            data = await this.call(this.exnessPath(this.historyCount()));
            bars = this.toBars(data.candles || []);
            failure = bars.length < 5 ? new Error("MT5 chưa có nến cho mã này") : null;
            // A stretch missing in the middle: MT5 is still fetching it; ask again shortly.
            if (!failure && this.owner && attempt < 3 && barsHole(bars, TF_SECONDS[this.interval] || 60)) failure = new Error("MT5 đang tải nến");
          } catch (e) { failure = e; if (e instanceof Unreachable) break; }
          if (token !== this.loadToken) return;
          if (!failure) break;
        }
        if (failure) throw failure;
        this.source = "exness";
        // The account may call the market by another name (XAUUSD ↔ XAUUSDm, GOLD…): the server answers with it.
        if (data.symbol && data.symbol !== this.symbol) { this.symbol = data.symbol; if (this.owner) store.set("aurum.sym", this.symbol); }
        this.digits = data.digits != null ? data.digits : 2;
        if (data.contractSize) (this.contracts = this.contracts || {})[data.symbol || this.symbol] = data.contractSize;
        this.applySeriesFormat();
        $("chartSymbol").textContent = data.symbol || this.symbol || "XAUUSD";
        this.renderSymTabs();
        $("chartSource").textContent = "";
        this.bars = bars;
        if (this.drawKey !== this.symbolKey()) { this.drawKey = this.symbolKey(); this.drawings.load(); this.pullDrawings(); }
        if (replayTime != null) {
          // The bars around the replay moment, fetched there directly (paging back from today could not
          // reach a moment weeks ago on a small timeframe, and the replay would land somewhere else).
          this.replayGap = false;
          if (this.bars[0].time > replayTime) await this.replayWindow(replayTime, token);
          if (token !== this.loadToken) return;
          let i = this.bars.length - 1;
          while (i > 0 && this.bars[i].time > replayTime) i--;
          this.replay.idx = Math.max(1, Math.min(i, this.bars.length - 2));
          this.applyReplay(true);
        } else {
          this.showFresh(bars);
          this.computeICT();
        }
        this.setQuote(data);
        this.lastPollAt = Date.now();
        this.pollTimer = setInterval(() => this.pollBars(token), 2000);
        this.startTicks(token);
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

    /* ----- MT5 ticks pushed by the VPS (server 3.4+): every bid / ask as it comes, not a poll every 2 s ----- */

    startTicks(token) {
      this.stopTicks();
      if (!this.base || !this.secret) return;
      const ctrl = (this.tickAbort = new AbortController());
      const path = this.owner ? `/mt5/ticks?symbol=${encodeURIComponent(this.symbol || "")}` : "/member/ticks";
      (async () => {
        let wait = 1000;
        while (!ctrl.signal.aborted && token === this.loadToken) {
          try {
            const res = await fetch(this.base + path, { headers: { Authorization: "Bearer " + this.secret }, signal: ctrl.signal, cache: "no-store" });
            if (res.status === 404 || res.status === 403) return; // an older server, or not for this member: the 2 s poll stays
            if (!res.ok || !res.body) throw new Error(String(res.status));
            const reader = res.body.getReader(), dec = new TextDecoder();
            let buf = "";
            this.tickLive = true;
            for (;;) {
              const { value, done } = await reader.read();
              if (done) break;
              buf += dec.decode(value, { stream: true });
              let i;
              while ((i = buf.indexOf("\n\n")) >= 0) {
                const line = buf.slice(0, i).split("\n").find((l) => l.startsWith("data:"));
                buf = buf.slice(i + 2);
                if (line) { try { this.onTick(JSON.parse(line.slice(5)), token); } catch { /* a bad line */ } }
              }
              wait = 1000;
            }
          } catch { if (ctrl.signal.aborted) return; }
          this.tickLive = false;
          await new Promise((r) => setTimeout(r, wait));
          wait = Math.min(15000, wait * 2);
        }
      })();
    },

    stopTicks() {
      if (this.tickAbort) { this.tickAbort.abort(); this.tickAbort = null; }
      this.tickLive = false;
    },

    /** One tick: the quote, the money and the forming bar at once (drawn once per frame at most). */
    onTick(t, token) {
      if (token !== this.loadToken || !t || !(t.bid > 0)) return;
      this.tickNext = t;
      if (this.tickFrame) return;
      this.tickFrame = requestAnimationFrame(() => {
        this.tickFrame = null;
        const tick = this.tickNext;
        if (!tick || token !== this.loadToken) return;
        this.tickInto(this.bars, TF_SECONDS[this.interval], tick, (b) => { if (!this.replay && !this.replayGap) this.series.update(shown(b)); });
        (this.panes || []).forEach((p) => p.tick(tick));
        if (!this.replay) this.setQuote({ bid: tick.bid, ask: tick.ask });
      });
    },

    /** A tick into the forming bar (or the next one when the bar's time is up); bars of another time are left
     *  to the poll, so a clock that is off can never add a bar at the wrong time. */
    tickInto(bars, sec, t, draw) {
      const last = bars[bars.length - 1];
      if (!last || !sec || this.replay) return;
      const start = Math.floor(t.time / sec) * sec;
      if (start === last.time) {
        last.high = Math.max(last.high, t.bid); last.low = Math.min(last.low, t.bid); last.close = t.bid;
        draw(last);
      } else if (start === last.time + sec) {
        const b = { time: start, open: t.bid, high: t.bid, low: t.bid, close: t.bid, volume: 0 };
        bars.push(b);
        draw(b);
      }
    },

    // The newest bars every 2 seconds (MT5 has no public stream).
    async pollBars(token) {
      // A replay window in the past: today's bars would land after a hole (they come back on leaving replay).
      if (this.polling || this.replayGap) return;
      // A hidden tab or a sleeping phone polls late: fetch every bar since the last poll (else the chart
      // has a hole), or reload when that is more than a fetch holds.
      const sec = TF_SECONDS[this.interval] || 60, nowMs = Date.now();
      const late = this.lastPollAt ? (nowMs - this.lastPollAt) / 1000 : 0;
      if (late / sec > 700) { this.lastPollAt = null; this.loadCandles(); return; }
      const count = Math.max(3, Math.ceil(late / sec) + 3);
      this.polling = true;
      try {
        let data = await this.call(this.exnessPath(count));
        this.lastPollAt = nowMs;
        if (token !== this.loadToken) return;
        let fresh = this.toBars(data.candles || []);
        // The newest bars do not follow on from the chart's last one (stale history at the start):
        // fetch every bar in between once, or reload when that is too many.
        const tail = this.bars[this.bars.length - 1];
        if (tail && fresh.length && fresh[0].time > tail.time + sec * 1.5) {
          const need = Math.ceil((fresh[fresh.length - 1].time - tail.time) / sec) + 3;
          if (need > 1000) { this.polling = false; this.loadCandles(); return; }
          data = await this.call(this.exnessPath(need));
          if (token !== this.loadToken) return;
          fresh = this.toBars(data.candles || []);
        }
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
      this.renderSymTabs();
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
      let drawn = this.bars.length;
      feed.live((added) => {
        if (token !== this.loadToken || this.replay) return;
        const last = this.bars[this.bars.length - 1];
        // Several bars at once (quiet seconds filled, trades caught up after a dropped stream): all of them.
        if (this.bars.length - drawn > 1) this.series.setData(this.bars.map(shown));
        else if (last) this.series.update(shown(last));
        drawn = this.bars.length;
        if (last) this.checkAlerts(last.close);
        if (!this.quoteLive) this.setQuote({});
        else if (this.owner && this.positions.length && performance.now() - (this.pillAt || 0) > 250) {
          // The money with the bar, a few times a second.
          this.pillAt = performance.now();
          this.pillMoney();
        }
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
        if (this.pair() && this.cmpBars && this.cmpBars.length && this.cmpBars[0].time > this.bars[0].time) this.loadOlderCmp();
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
      this.renderSymTabs();
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
      this.renderSymTabs();
      $("chartSource").textContent = "· MT5 chưa trả nến, đang dùng giá tạm";
      const interval = this.interval;
      const rest = m.futures ? "https://fapi.binance.com/fapi/v1/klines" : "https://api.binance.com/api/v3/klines";
      try {
        this.bars = await binanceBars(rest, m.name, interval, 800);
        if (this.replay) this.exitReplay();
        if (this.drawKey !== this.symbolKey()) { this.drawKey = this.symbolKey(); this.drawings.load(); this.pullDrawings(); }
        this.showFresh(this.bars);
        this.setQuote({});
        this.computeICT();
      } catch { /* chart stays empty */ }
      const ws = new WebSocket(`${m.futures ? "wss://fstream.binance.com/ws/" : "wss://stream.binance.com:9443/ws/"}${m.name.toLowerCase()}@kline_${binanceKline(interval)[0]}`);
      const fold = klineFolder(interval);
      ws.onmessage = (ev) => {
        const k = JSON.parse(ev.data).k;
        if (!k) return;
        const last = this.bars[this.bars.length - 1];
        const b = fold({ time: k.t / 1000, open: +k.o, high: +k.h, low: +k.l, close: +k.c, volume: +k.v }, last);
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
        // Like a real position: from the entry candle (a dot there), "BUY 0.1 | +12.40" at the right, SL / TP with their money.
        this.replay.trades.forEach((t) => {
          const p = { side: t.side, lots: t.lots, profit: this.replayProfit(t, price) };
          out.push({ key: `rp:${t.id}:entry`, price: t.entry, color: t.side === "long" ? "#2b6bf3" : "#f0455a", width: 1, style: 0, title: "", entryOf: p, from: t.time, drawn: true });
          if (t.stop) out.push({ key: `rp:${t.id}:stop`, price: t.stop, color: "#f0455a", width: 1, style: 2, title: `SL ${money0(this.replayProfit(t, t.stop))}`, from: t.time, drawn: true });
          if (t.target) out.push({ key: `rp:${t.id}:target`, price: t.target, color: "#14b88a", width: 1, style: 2, title: `TP ${money0(this.replayProfit(t, t.target))}`, from: t.time, drawn: true });
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
          out.push({ key: `pos:${p.ticket}:entry`, price: p.entry, color: dim(p.side === "long" ? "#2b6bf3" : "#f0455a", active), width: w, style: 0, title: "", entryOf: p, faded: !!(sel && !active), from: p.time, drawn: true });
          if (p.stop) out.push({ key: `pos:${p.ticket}:stop`, price: p.stop, color: dim("#f0455a", active), width: w, style: 2, title: `SL ${money0(this.pnlAt(p, p.stop))}`, from: p.time, drawn: true, active });
          if (p.target) out.push({ key: `pos:${p.ticket}:target`, price: p.target, color: dim("#14b88a", active), width: w, style: 2, title: `TP ${money0(this.pnlAt(p, p.target))}`, from: p.time, drawn: true, active });
        });
        this.orders.filter(onChart).forEach((o) => {
          const active = sel && sel.kind === "ord" && sel.ticket === o.ticket;
          const w = active ? 2 : 1;
          out.push({ key: `ord:${o.ticket}:entry`, price: o.entry, color: dim(o.side === "long" ? "#2b6bf3" : "#f0455a", active), width: w, style: 1, title: `${sideName(o.side)} ${o.kind.toUpperCase()} ${o.lots}`, from: o.time, drawn: true });
          const om = (lv) => money0(this.valueAt(o.symbol, o.lots, o.side, o.entry, lv));
          if (o.stop) out.push({ key: `ord:${o.ticket}:stop`, price: o.stop, color: dim("#f0455a", active), width: w, style: 2, title: `SL ${om(o.stop)}`, from: o.time, drawn: true, active });
          if (o.target) out.push({ key: `ord:${o.ticket}:target`, price: o.target, color: dim("#14b88a", active), width: w, style: 2, title: `TP ${om(o.target)}`, from: o.time, drawn: true, active });
        });
        if (this.draft) {
          const price = num($("pPrice").value), stop = num($("pStop").value), target = num($("pTarget").value);
          // The draft starts at the newest candle, where the order would be placed.
          const from = this.bars.length ? this.bars[this.bars.length - 1].time : null;
          if (price) out.push({ key: "draft:entry", price, color: "#9b6bff", width: 2, style: 0, title: `${this.pendingKind(this.draftSide(price))} ${this.lots().toFixed(2)}`, from, drawn: true });
          const dside = price ? this.draftSide(price) : "long";
          const dm = (lv) => money0(this.valueAt(this.symbol, this.lots(), dside, price, lv));
          if (stop) out.push({ key: "draft:stop", price: stop, color: "#f0455a", width: 1, style: 2, title: `SL ${dm(stop)}`, from, drawn: true });
          if (target) out.push({ key: "draft:target", price: target, color: "#14b88a", width: 1, style: 2, title: `TP ${dm(target)}`, from, drawn: true });
        }
      } else {
        this.signals.filter((s) => s.status === "open" && s.symbol === ($("chartSymbol").textContent || s.symbol)).forEach((s) => {
          out.push({ key: `sig:${s.id}:entry`, price: s.entry, color: "#9b6bff", width: 1, style: 2, title: (s.side === "long" ? "MUA" : "BÁN") + " tín hiệu" });
          if (s.stop) out.push({ key: `sig:${s.id}:stop`, price: s.stop, color: "#9b6bff", width: 1, style: 1, title: "SL" });
          if (s.target) out.push({ key: `sig:${s.id}:target`, price: s.target, color: "#9b6bff", width: 1, style: 1, title: "TP" });
        });
      }
      // A level waiting for Xác nhận shows its line there (a new SL / TP included).
      const m = this.pendingMove;
      if (m && !this.replay) {
        const w = out.find((l) => l.key === m.key);
        const label = `${m.field === "stop" ? "SL" : m.field === "target" ? "TP" : "Giá"} ${fmt(m.price, this.digits)} ?`;
        if (w) Object.assign(w, { price: m.price, title: w.entryOf ? w.title : label, width: 2 });
        else out.push({ key: m.key, price: m.price, color: m.field === "stop" ? "#f0455a" : "#14b88a", width: 2, style: 2, title: label, from: m.x.time, drawn: true });
      }
      return out;
    },

    /** A position's money at the chart's live bid / ask (a buy closes at the bid, a sell at the ask), from the
     *  same quote as the candles so it moves with them; the server's figure (every 2 s) for other symbols. */
    liveProfit(p) {
      if (!p || p.symbol !== this.symbol || this.bid == null || this.ask == null || this.replay) return p ? p.profit : 0;
      let bid = this.bid, ask = this.ask;
      // Second bars move with every Binance trade, quicker than the broker's quote: the last bar's close
      // (already on the broker's price) is the bid then, the ask that plus the spread.
      const last = this.secFeed && this.bars.length ? this.bars[this.bars.length - 1].close : null;
      if (last != null) { ask = last + (ask - bid); bid = last; }
      const v = this.pnlAt(p, p.side === "long" ? bid : ask);
      return v == null || !isFinite(v) ? p.profit : v;
    },

    floating() { return this.positions.reduce((a, p) => a + (this.liveProfit(p) || 0), 0); },

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
      return (price - entry) * (side === "long" ? 1 : -1) * lots * this.contractOf(symbol);
    },

    /** Units per lot: the broker's own (sent with the bars by server 3.2+), else the usual sizes. */
    contractOf(symbol) {
      const known = (this.contracts || {})[symbol];
      if (known) return known;
      const s = String(symbol || "").toUpperCase();
      if (/XAU|GOLD/.test(s)) return 100;
      if (/XAG|SILVER/.test(s)) return 5000;
      if (/OIL|XTI|XBR|WTI|BRENT/.test(s)) return 1000;
      if (/XNG|NGAS|NATGAS/.test(s)) return 10000;
      if (/BTC|ETH|SOL|XRP|LTC|BNB|DOGE|ADA|US30|USTEC|NAS|SPX|US500|DE30|DE40|JP225|UK100|HK50|STOXX|FR40|AUS200/.test(s)) return 1;
      return 100000;
    },

    /** Where a trade line starts: the candle at `time` (with a dot there when on screen), else the left edge. */
    tradeLineStart(time, width) {
      const bars = this.viewBars();
      if (!bars.length || time == null || time < bars[0].time) return { x0: 0, dot: false };
      let i = bars.length - 1;
      while (i > 0 && bars[i].time > time) i--;
      const x = this.chart.timeScale().logicalToCoordinate(i);
      return x == null ? { x0: 0, dot: false } : { x0: Math.max(0, Math.min(width, x)), dot: x >= 0 && x <= width };
    },

    /** The trade lines as drawn: the cached ones with the line under the finger at its dragged price. */
    tradeLines() {
      const d = this.drag;
      const list = (this.lineCache || []).filter((w) => w.drawn).map((w) => (d && d.key === w.key ? Object.assign({}, w, { price: d.price, title: this.dragTitle(d), width: 2 }) : w));
      if (d && d.pull && d.key !== d.base && !list.some((w) => w.key === d.key)) {
        // Pulling a new SL / TP out of a position's entry.
        const [kind, id] = d.key.split(":");
        const p = kind === "rp" ? this.replayTrade(id) : this.positions.find((x) => x.ticket === +id);
        const stop = d.key.endsWith(":stop");
        if (p) list.push({ key: d.key, price: d.price, color: stop ? "#f0455a" : "#14b88a", width: 2, style: 2, title: this.dragTitle(d), from: p.time, drawn: true });
      }
      return list;
    },

    /** Positions, pending orders and the draft: each line starts at the candle the trade began on (a dot at
     * the entry there) instead of crossing the whole chart; labels sit at the right. A position's entry
     * reads "BUY 0.1 | −5.75", the money green in profit and red at a loss. */
    drawTradeLines(g, width) {
      const list = this.tradeLines();
      if (!list.length) return;
      const light = document.documentElement.dataset.theme === "light";
      // The picked trade's SL / TP labels slide left, clear of the other trades' labels piled at the right,
      // and slide back when it is let go.
      const shifts = (this.tagShifts = this.tagShifts || {});
      const away = Math.min(170, width * 0.32);
      let sliding = false;
      g.save();
      g.font = "600 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
      g.textBaseline = "middle";
      list.forEach((w) => {
        const yy = this.series.priceToCoordinate(w.price);
        if (yy == null) return;
        const y = Math.round(yy) + 0.5;
        const { x0, dot } = this.tradeLineStart(w.from, width);
        const entry = /:entry$/.test(w.key);
        g.globalAlpha = w.faded ? 0.45 : 1;
        g.strokeStyle = w.color; g.lineWidth = Math.max(1, w.width);
        g.setLineDash(w.entryOf ? [2, 3] : w.style === 2 ? [5, 4] : w.style === 1 ? [2, 3] : []);
        g.beginPath(); g.moveTo(x0, y); g.lineTo(width, y); g.stroke();
        g.setLineDash([]);
        if (dot && entry) {
          g.beginPath(); g.arc(x0, y, 4, 0, Math.PI * 2);
          g.fillStyle = w.color; g.fill();
          g.lineWidth = 1.5; g.strokeStyle = light ? "#ffffff" : "#050506"; g.stroke();
        }
        const h = 18, top = y - h / 2;
        if (w.entryOf) {
          // Side and lots on the side colour, the money on green / red.
          const p = w.entryOf;
          const live = this.liveProfit(p);
          const left = `${sideName(p.side)} ${p.lots}`, right = signed(live);
          const lw = g.measureText(left).width + 12, rw = g.measureText(right).width + 12;
          const x = Math.max(4, width - lw - rw - 10);
          g.fillStyle = p.side === "long" ? "#2b6bf3" : "#f0455a";
          g.beginPath(); g.roundRect(x, top, lw + rw, h, 4); g.fill();
          g.fillStyle = (live || 0) >= 0 ? "#14b88a" : "#f0455a";
          g.beginPath(); g.roundRect(x + lw, top, rw, h, [0, 4, 4, 0]); g.fill();
          g.fillStyle = "#ffffff";
          g.fillText(left, x + 6, y + 0.5);
          g.fillText(right, x + lw + 6, y + 0.5);
        } else if (w.title) {
          const tw = g.measureText(w.title).width + 12;
          const goal = w.active || (this.drag && this.drag.key === w.key && !/^draft:/.test(w.key)) ? away : 0;
          let cur = shifts[w.key] || 0;
          cur += (goal - cur) * 0.28;
          if (Math.abs(goal - cur) < 0.6) cur = goal; else sliding = true;
          if (cur) shifts[w.key] = cur; else delete shifts[w.key];
          const x = Math.max(4, width - tw - 10 - cur);
          g.fillStyle = w.color;
          g.beginPath(); g.roundRect(x, top, tw, h, 4); g.fill();
          g.fillStyle = "#ffffff";
          g.fillText(w.title, x + 6, y + 0.5);
        }
        g.globalAlpha = 1;
      });
      g.restore();
      if (sliding && !this.tagSlideQueued) {
        this.tagSlideQueued = true;
        requestAnimationFrame(() => { this.tagSlideQueued = false; this.repaint(); });
      }
    },

    syncLines() {
      if (!this.series) return;
      const wanted = this.wantedLines();
      const keys = new Set();
      wanted.forEach((w) => {
        keys.add(w.key);
        if (this.drag && this.drag.key === w.key) return; // the finger owns it
        // Drawn lines are painted by the chart layer; the price line only keeps the price on the axis.
        const opts = { price: w.price, color: w.color, lineWidth: w.width, lineStyle: w.style, axisLabelVisible: true, title: w.drawn ? "" : w.title, lineVisible: !w.drawn };
        const line = this.lines.get(w.key);
        if (line) line.applyOptions(opts); else this.lines.set(w.key, this.series.createPriceLine(opts));
      });
      for (const [k, line] of this.lines) {
        if (!keys.has(k) && !(this.drag && this.drag.key === k)) { this.series.removePriceLine(line); this.lines.delete(k); }
      }
      this.lineCache = wanted;
      (this.panes || []).forEach((p) => p.syncLines());
      if (this.requestICT) this.requestICT();
      // While a trade or drawing is picked (or a pending price is set), a finger drags it, not the page.
      this.updateTouchAction();
    },

    /** The blue box being dragged with Alt (80% see-through) on the chart it was started on, or none. */
    drawBox() {
      const b = this.boxSel;
      document.querySelectorAll(".box-sel").forEach((el) => { if (!b || el.parentNode !== b.wrap) el.hidden = true; });
      if (!b) return;
      let el = b.wrap.querySelector(".box-sel");
      if (!el) { el = document.createElement("div"); el.className = "box-sel"; b.wrap.appendChild(el); }
      el.hidden = false;
      Object.assign(el.style, { left: Math.min(b.x0, b.x1) + "px", top: Math.min(b.y0, b.y1) + "px", width: Math.abs(b.x1 - b.x0) + "px", height: Math.abs(b.y1 - b.y0) + "px" });
    },

    /** Starts the Alt box on a chart (`dr` its drawings, `wrap` its frame) at (x, y). */
    startBox(dr, wrap, x, y) {
      this.boxSel = { dr, wrap, x0: x, y0: y, x1: x, y1: y };
      [this.drawings, this.drawings2].forEach((d) => d && d.clearMulti());
      this.renderBoxBar();
      this.drawBox();
    },

    /** The box let go: its drawings picked on that chart. */
    endBox() {
      const b = this.boxSel;
      if (!b) return;
      this.boxSel = null;
      this.drawBox();
      const n = Math.hypot(b.x1 - b.x0, b.y1 - b.y0) > 4 ? b.dr.selectIn(b.x0, b.y0, b.x1, b.y1) : 0;
      b.wrap.boxPicked = n ? b : null;
      this.renderBoxBar();
      if (!n) toast("Không có bản vẽ nào trong ô");
    },

    /** "N bản vẽ · Xoá tất cả · ✕" on each chart whose drawings are picked by the box. */
    renderBoxBar() {
      [[this.drawings, $("chartWrap")], [this.drawings2, $("chartWrap2")]].forEach(([dr, wrap]) => {
        if (!wrap) return;
        let bar = wrap.querySelector(".box-bar");
        const n = dr ? dr.multiCount : 0;
        if (!bar && !n) return;
        if (!bar) { bar = document.createElement("div"); bar.className = "box-bar"; wrap.appendChild(bar); }
        bar.hidden = !n;
        if (!n) return;
        bar.innerHTML = `<span><b>${n}</b> bản vẽ đã chọn</span><button type="button" class="danger" data-a="del">🗑 Xoá tất cả</button><button type="button" data-a="x" title="Bỏ chọn (Esc)">✕</button>`;
        const b = wrap.boxPicked;
        if (b) { bar.style.left = Math.max(8, Math.min(b.x0, b.x1)) + "px"; bar.style.top = Math.max(8, Math.min(b.y0, b.y1) - 40) + "px"; }
        bar.onpointerdown = (e) => e.stopPropagation();
        bar.querySelector("[data-a=del]").onclick = () => this.deleteBoxed(dr);
        bar.querySelector("[data-a=x]").onclick = () => { dr.clearMulti(); this.renderBoxBar(); };
      });
    },

    /** Deletes the drawings picked by the box (on `dr`, else whichever chart has some). */
    deleteBoxed(dr) {
      const target = dr || [this.drawings, this.drawings2].find((d) => d && d.multiCount);
      const n = target ? target.removeMulti() : 0;
      this.renderBoxBar();
      if (n) toast(`Đã xoá ${n} bản vẽ`);
      if (target && this.drawingsChanged) this.drawingsChanged(target);
    },

    renderSelBar() {
      const bar = $("selBar");
      const x = this.findSelected();
      if (!this.owner || !x || this.replay) { bar.hidden = true; return; }
      const pos = this.selected.kind === "pos";
      bar.hidden = false;
      bar.innerHTML = `<span>${sideName(x.side)}${pos ? "" : " " + x.kind.toUpperCase()} ${x.lots} · #${x.ticket}${pos ? ` · <b class="${this.liveProfit(x) >= 0 ? "pos" : "neg"}">${signed(this.liveProfit(x))}</b>` : ""}</span>
        <button type="button" data-a="stop" class="sl">${x.stop ? "SL ✎" : "+SL"}</button><button type="button" data-a="target" class="tp">${x.target ? "TP ✎" : "+TP"}</button>
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
      // SL / TP in pips from the entry (the last distance used, else 15 pip SL and 2R TP), checked in
      // the bar on the chart and sent only on Xác nhận.
      const pip = this.pipOf(x.symbol), long = x.side === "long", sign = (long ? 1 : -1) * (a === "target" ? 1 : -1);
      let level = x[a];
      if (!level) {
        const slPips = +(store.get("aurum.slPips") || 15);
        const risk = x.stop ? Math.abs(x.entry - x.stop) : slPips * pip;
        level = x.entry + sign * (a === "stop" ? slPips * pip : risk * 2);
      }
      this.editLevel(pos ? "pos" : "ord", x, a, level);
    },

    /* ----- touch & drag on the chart ----- */

    bindDrag() {
      const wrap = $("chartWrap");
      const rel = (e) => { const r = wrap.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
      const paneWidth = () => this.chart.timeScale().width();
      const hit = (y, keys, x) => {
        let best = null;
        for (const w of this.lineCache || []) {
          if (!keys(w.key)) continue;
          if (x != null && w.drawn && x < this.tradeLineStart(w.from, paneWidth()).x0 - 10) continue;
          const ly = this.series.priceToCoordinate(w.price);
          if (ly == null) continue;
          const dist = Math.abs(ly - y);
          if (dist < (best ? best.dist : 12)) best = { w, dist };
        }
        return best && best.w;
      };
      const draggable = (key) => {
        // Replay trades: their SL / TP dragged, or pulled out of the entry, as real ones (no MT5 involved).
        if (this.replay) return key.startsWith("rp:");
        if (!this.owner) return false;
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
      // Fingers on the chart: a second one (pinch to zoom) cancels a line drag, so a zoom never moves SL/TP.
      const fingers = new Set();
      const cancelDrag = () => { if (this.drag) { this.drag = null; lock(false); this.syncLines(); } };
      wrap.addEventListener("pointerdown", (e) => {
        fingers.add(e.pointerId);
        if (fingers.size > 1) { cancelDrag(); clearTimeout(longPress); return; }
        this.closeMenu();
        this.focusChart(1);
        if (e.button > 0 || e.target.closest("#selBar, #posPill, #ticket, #drawBar, #favBar, #draftBar, #btChip, .box-bar, #mascots .mascot")) return;
        if (this.mascotSel) { this.mascotSel = null; document.querySelectorAll("#mascots .sel").forEach((x) => x.classList.remove("sel")); }
        // A tap on a free spot of the chart opens the timeframe ring; not one that closes it or picks / drops a drawing.
        { const dr = this.drawings, ringWasOpen = this.closeTfRing();
          this.tapFree = !ringWasOpen && !(dr && (dr.selected || dr.current || dr.tool || dr.pending || dr.multiCount)) && !this.draft && !this.replayPicking; }
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
        // Alt (⌥ on a Mac) + drag with the mouse: a blue box; the drawings in it are picked, to delete together.
        if (e.pointerType === "mouse" && e.altKey && this.drawings && !this.drawings.tool && !this.drawings.pending) {
          this.startBox(this.drawings, wrap, x, y);
          lock(true); e.stopPropagation(); e.preventDefault();
          return;
        }
        const r = this.drawings ? this.drawings.down(x, y, e) : false;
        // A press elsewhere let the box's drawings go.
        this.renderBoxBar();
        if (r === true) {
          this.drawGesture = true; lock(true); e.stopPropagation();
          clearTimeout(longPress);
          return;
        }
        const w = hit(y, draggable, x);
        if (!w) return;
        // Not moved until the finger has gone 8 px up or down: a tap or a shaky press changes nothing.
        this.drag = { key: w.key, price: w.price, start: w.price, base: w.key, pull: /^(pos:\d+|rp:\w+):entry$/.test(w.key), pid: e.pointerId, y0: e.clientY, armed: false };
        lock(true);
        e.stopPropagation();
      }, true);
      ["mousedown", "touchstart"].forEach((t) => wrap.addEventListener(t, (e) => { if (this.drag || this.drawGesture) e.stopPropagation(); }, { capture: true, passive: true }));
      wrap.addEventListener("touchmove", (e) => { if (this.drag || this.drawGesture) e.preventDefault(); }, { passive: false });
      wrap.addEventListener("pointermove", (e) => {
        if (this.drag || this.drawGesture) return;
        const { x, y } = rel(e);
        if (this.drawings && this.drawings.pending) { this.drawings.move(x, y, e); return; }
        if (e.pointerType !== "mouse") return;
        const overDrawing = this.drawings && x <= paneWidth() && this.drawings.hitTest(x, y, 8);
        if (this.drawings) this.drawings.hover(overDrawing ? overDrawing.d.id : null);
        wrap.style.cursor = this.drawings && this.drawings.tool ? "crosshair"
          : overDrawing ? "move" : x <= paneWidth() && hit(y, draggable, x) ? "ns-resize" : "";
      });
      wrap.addEventListener("pointerleave", () => { if (this.drawings) this.drawings.hover(null); });
      window.addEventListener("pointermove", (e) => {
        if (this.boxSel && this.boxSel.wrap === wrap) { const { x, y } = rel(e); this.boxSel.x1 = Math.max(0, Math.min(x, paneWidth())); this.boxSel.y1 = y; this.drawBox(); return; }
        if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 6) { down.moved = true; clearTimeout(longPress); }
        if (this.drawGesture) { const { x, y } = rel(e); this.drawings.move(x, y, e); return; }
        if (!this.drag || e.pointerId !== this.drag.pid) return;
        if (fingers.size > 1) { cancelDrag(); return; }
        if (!this.drag.armed) { if (Math.abs(e.clientY - this.drag.y0) < 8) return; this.drag.armed = true; }
        const price = this.series.coordinateToPrice(rel(e).y);
        if (price == null) return;
        let p = +price.toFixed(this.digits);
        if (this.drag.pull) { this.pullTo(p); return; }
        if (this.drag.key.startsWith("draft:")) p = this.writeDraft(this.drag.key, p);
        this.drag.price = p;
        const line = this.lines.get(this.drag.key);
        if (line) line.applyOptions({ price: p });
        if (this.requestICT) this.requestICT();
      });
      window.addEventListener("pointerup", (e) => {
        fingers.delete(e.pointerId);
        clearTimeout(longPress);
        if (this.boxSel && this.boxSel.wrap === wrap) {
          down = null;
          lock(false);
          this.endBox();
          return;
        }
        if (this.drag && e.pointerId !== this.drag.pid) return;
        const d = this.drag, tap = down && !down.moved && !down.menu;
        down = null;
        if (this.drawGesture) {
          this.drawGesture = false; lock(false);
          this.drawings.up();
          return;
        }
        if (d) {
          this.drag = null; lock(false);
          const untouched = !d.armed || (d.key === d.base ? Math.abs(d.price - d.start) === 0 : d.start != null && Math.abs(d.price - d.start) === 0);
          if (!d.armed && !d.pull) {
            // Never dragged: a tap, nothing moves.
            this.syncLines();
            if (tap && e.target && wrap.contains(e.target)) { const { x, y } = rel(e); this.tapChart(y, x); }
            return;
          }
          if (d.pull && d.key === d.base) {
            // Only a tap on the entry line: pick the next trade at that price.
            this.syncLines();
            if (tap && e.target && wrap.contains(e.target)) { const { x, y } = rel(e); this.tapChart(y, x); }
            return;
          }
          if (untouched) this.syncLines(); else this.commitDrag(d);

          return;
        }
        if (tap && e.target && wrap.contains(e.target)) {
          const { x, y } = rel(e);
          // A double tap with a finger (the mouse has dblclick): 2 charts for the SMT, or back to one.
          if (e.pointerType === "touch") {
            const prev = this.lastTap, now = performance.now();
            this.lastTap = { t: now, x, y };
            if (prev && now - prev.t < 320 && Math.hypot(x - prev.x, y - prev.y) < 30 && !this.chartDblBusy(e)) { this.lastTap = null; this.togglePairLayout(); return; }
          }
          this.tapChart(y, x, this.tapFree ? e : null);
        }
      });
      window.addEventListener("pointercancel", (e) => {
        fingers.delete(e.pointerId);
        clearTimeout(longPress);
        cancelDrag();
        if (this.drawGesture) { this.drawGesture = false; lock(false); this.drawings.up(); }
        down = null;
      });
      wrap.addEventListener("dblclick", (e) => {
        if (this.drawings && this.drawings.current) { this.drawingSettings(this.drawings.current); return; }
        // Double-click on the chart: the 2-chart layout for the SMT (again: back to one chart).
        if (!this.chartDblBusy(e)) this.togglePairLayout();
      });
      wrap.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        if (this.drawings && this.drawings.pending) { this.drawings.cancel(); return; }
        this.openMenu(e.clientX, e.clientY);
      });
      window.addEventListener("keydown", (e) => {
        if (this.tab !== "chart" || /INPUT|TEXTAREA|SELECT/.test((document.activeElement || {}).tagName || "") || $("sheet").open) return;
        // Undo / redo (⌘Z / Ctrl+Z, ⇧⌘Z / Ctrl+Y): the drawings of the chart in use.
        if ((e.ctrlKey || e.metaKey) && !e.altKey && (e.key === "z" || e.key === "Z" || e.key === "y")) {
          if (e.key === "y" || e.shiftKey) this.redoDrawing(); else this.undoDrawing();
          e.preventDefault(); return;
        }
        if (e.key === "Escape") { this.closeMenu(); if (this.drawings) this.drawings.cancel(); if (this.replayPicking) this.exitReplay(); }
        if ((e.key === "Delete" || e.key === "Backspace") && [this.drawings, this.drawings2].some((d) => d && d.multiCount)) { this.deleteBoxed(); e.preventDefault(); }
        else if ((e.key === "Delete" || e.key === "Backspace") && this.drawings && this.drawings.selected) { this.drawings.remove(this.drawings.selected); e.preventDefault(); }
        if (e.key === "Escape") { [this.drawings, this.drawings2].forEach((d) => d && d.clearMulti()); this.renderBoxBar(); }
        if (this.replay && e.key === "ArrowRight") { this.replayStep(); e.preventDefault(); }
        if (this.replay && e.key === " ") { this.replayPlay(); e.preventDefault(); }
      });
      document.addEventListener("pointerdown", (e) => {
        if (!e.target.closest("#ctxMenu") && !e.target.closest(".lot-pick") && !e.target.closest(".db-pick") && !e.target.closest("#typeBtn")) this.closeMenu();
        if (!e.target.closest("#flyout, #toolRail")) this.closeFlyout();
      });
    },

    replayTrade(id) { return this.replay ? this.replay.trades.find((t) => t.id === id) : null; },

    dragTitle(d) {
      const [kind, ticket, field] = d.key.split(":");
      const name = { entry: kind === "draft" ? "Giá chờ" : "Giá", stop: "SL", target: "TP" }[field];
      if (kind === "rp") {
        const t = this.replayTrade(ticket);
        return `${name} ${fmt(d.price, this.digits)}${t ? " · " + signed(this.replayProfit(t, d.price)) : ""}`;
      }
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
      const [kind, id] = d.base.split(":");
      const ticket = kind === "rp" ? id : +id;
      const p = kind === "rp" ? this.replayTrade(id) : this.positions.find((x) => x.ticket === ticket);
      if (!p) return;
      // Within 12 px of the entry nothing is pulled out yet (an SL / TP on the entry would lose it).
      const ey = this.series.priceToCoordinate(p.entry), py = this.series.priceToCoordinate(price);
      if (ey != null && py != null && Math.abs(py - ey) < 12) {
        if (d.key !== d.base) { d.key = d.base; this.syncLines(); }
        return;
      }
      const long = p.side === "long";
      const field = (long ? price < p.entry : price > p.entry) ? "stop" : "target";
      const key = `${kind}:${ticket}:${field}`;
      if (d.key !== key) { d.key = key; d.start = p[field] || null; this.syncLines(); }
      d.price = price;
      const opts = { price, color: field === "stop" ? "#f0455a" : "#14b88a", lineWidth: 2, lineStyle: 2, axisLabelVisible: true, title: "", lineVisible: false };
      const line = this.lines.get(key);
      if (line) line.applyOptions(opts); else this.lines.set(key, this.series.createPriceLine(opts));
      if (this.requestICT) this.requestICT();
    },

    async commitDrag(d) {
      const [kind, ticket, field] = d.key.split(":");
      if (kind === "draft") { this.syncLines(); return; }
      if (kind === "rp") return this.moveReplayLevel(ticket, field, d.price);
      const list = kind === "pos" ? this.positions : this.orders;
      const x = list.find((y) => y.ticket === +ticket);
      if (!x) return this.syncLines();
      const body = { ticket: x.ticket, stop: x.stop, target: x.target };
      if (kind === "ord") body.price = x.entry;
      body[field === "entry" ? "price" : field] = d.price;
      const wrong = kind === "pos" ? this.stopsProblem(x, body.stop, body.target) : null;
      if (wrong) { toast(wrong, true); this.syncLines(); return; }
      // Nothing goes to MT5 before a tap on Xác nhận: the line waits at its new place (real money).
      this.askMove({ key: d.key, kind, x, field, price: d.price, from: field === "entry" ? x.entry : x[field], body });
    },

    /** Price step a trader calls a pip: gold 0.1, silver / oil / JPY pairs 0.01, crypto and indices 1, FX 0.0001. */
    pipOf(symbol) {
      const s = String(symbol || "").toUpperCase();
      if (/XAU|GOLD/.test(s)) return 0.1;
      if (/XAG|SILVER|OIL|XTI|XBR|WTI|BRENT|JPY/.test(s)) return 0.01;
      if (/BTC|ETH|SOL|BNB|LTC|US30|USTEC|NAS|SPX|US500|DE30|DE40|JP225|UK100|HK50/.test(s)) return 1;
      return 0.0001;
    },

    /** Opens the SL / TP / pending-price editor for a trade at `price` (the line shows it meanwhile). */
    editLevel(kind, x, field, price) {
      this.levelBar({ key: `${kind}:${x.ticket}:${field}`, kind, x, field, price: +price.toFixed(this.digitsFor(x.symbol)), from: field === "entry" ? x.entry : x[field] });
    },

    /** The bar to set an SL / TP / pending price before it goes to MT5: the distance in pips with − / + (1 pip)
     *  and quick picks (SL 10 / 15 / 20 pip, TP 1R / 2R / 3R), the price and money, then Huỷ / Xác nhận.
     *  The line shows the level meanwhile (+SL / +TP on the trade bar). */
    levelBar(m) {
      this.pendingMove = m;
      this.syncLines();
      let bar = $("moveConfirm");
      if (!bar) {
        bar = document.createElement("div");
        bar.id = "moveConfirm"; bar.className = "move-confirm";
        $("chartWrap").appendChild(bar);
      }
      const x = m.x, d = this.digitsFor(x.symbol), pip = this.pipOf(x.symbol), long = x.side === "long";
      const name = m.field === "stop" ? "SL" : m.field === "target" ? "TP" : "Giá chờ";
      // The order MT5 gets: this level, the others as they are.
      m.body = { ticket: x.ticket, stop: x.stop, target: x.target };
      if (m.kind === "ord") m.body.price = x.entry;
      m.body[m.field === "entry" ? "price" : m.field] = m.price;
      const level = m.field !== "entry";
      const sign = (long ? 1 : -1) * (m.field === "target" ? 1 : -1);
      const pips = level ? (m.price - x.entry) * sign / pip : null;
      const money = level ? (m.kind === "pos" ? this.pnlAt(x, m.price) : this.valueAt(x.symbol, x.lots, x.side, x.entry, m.price)) : null;
      const wrongSide = level && pips <= 0 ? `${name} phải ở phía ${m.field === "stop" ? "lỗ" : "lời"} của giá vào` : null;
      const problem = wrongSide || (m.kind === "pos" ? this.stopsProblem(x, m.body.stop, m.body.target) : null);
      const risk = x.stop && m.field === "target" ? Math.abs(x.entry - x.stop) : 0;
      const picks = m.field === "stop" ? [10, 15, 20].map((p) => `<button type="button" data-p="${p}" class="${Math.abs(pips - p) < 0.05 ? "on" : ""}">${p}</button>`).join("")
        : m.field === "target" && risk ? [1, 2, 3].map((r) => `<button type="button" data-r="${r}" class="${Math.abs(pips * pip - r * risk) < pip / 2 ? "on" : ""}">${r}R</button>`).join("")
        : m.field === "target" ? [20, 30, 40].map((p) => `<button type="button" data-p="${p}">${p}</button>`).join("") : "";
      bar.hidden = false;
      bar.innerHTML = `<span class="mc-t"><b class="${m.field === "stop" ? "neg" : m.field === "target" ? "pos" : ""}">${name}</b> ${esc(x.symbol)} #${x.ticket}</span>
        <span class="mc-step"><button type="button" data-n="-1" title="Gần giá vào 1 pip">−</button>
          <b>${level ? `${pips.toFixed(1)} pip` : fmt(m.price, d)}</b><button type="button" data-n="1" title="Xa thêm 1 pip">+</button></span>
        ${picks ? `<span class="mc-picks">${picks}${m.field === "stop" ? "<em>pip</em>" : ""}</span>` : ""}
        <span class="mc-v">${level ? `${fmt(m.price, d)} ` : ""}${money != null ? `<span class="${money >= 0 ? "pos" : "neg"}">${signed(money)}</span>` : ""}${m.from ? ` <span class="muted">(cũ ${fmt(m.from, d)})</span>` : ""}</span>
        ${problem ? `<span class="mc-warn">${esc(problem)}</span>` : ""}
        <button type="button" class="no" data-a="no">Huỷ</button><button type="button" class="yes" data-a="yes" ${problem ? "disabled" : ""}>Xác nhận</button>`;
      const set = (price) => this.levelBar(Object.assign(m, { price: +price.toFixed(d) }));
      bar.querySelectorAll("[data-n]").forEach((b) => (b.onclick = () => {
        // − brings an SL / TP 1 pip nearer the entry, + 1 pip further; a pending price just moves 1 pip down / up.
        const step = +b.dataset.n * pip;
        set(level ? m.price + sign * step : m.price + step);
      }));
      bar.querySelectorAll("[data-p]").forEach((b) => (b.onclick = () => {
        if (m.field === "stop") store.set("aurum.slPips", b.dataset.p);
        set(x.entry + sign * +b.dataset.p * pip);
      }));
      bar.querySelectorAll("[data-r]").forEach((b) => (b.onclick = () => set(x.entry + sign * +b.dataset.r * risk)));
      bar.querySelector("[data-a=no]").onclick = () => this.closeMove();
      bar.querySelector("[data-a=yes]").onclick = async (e) => {
        const btn = e.currentTarget;
        btn.disabled = true;
        const ok = await act(btn, () => this.call("/mt5/modify", m.body), `Đã đặt ${name} → ${fmt(m.price, d)}`);
        if (ok) { if (m.field === "entry") x.entry = m.price; else x[m.field] = m.price; }
        this.closeMove();
        this.refresh();
      };
    },

    /** The bar asking to confirm a moved SL / TP / pending price; the line shows the new level meanwhile. */
    askMove(m) {
      this.pendingMove = m;
      this.syncLines();
      let bar = $("moveConfirm");
      if (!bar) {
        bar = document.createElement("div");
        bar.id = "moveConfirm"; bar.className = "move-confirm";
        $("chartWrap").appendChild(bar);
      }
      const name = m.field === "stop" ? "SL" : m.field === "target" ? "TP" : "giá chờ";
      const p = m.kind === "pos" ? m.x : null;
      const money = p && m.field !== "entry" ? this.pnlAt(p, m.price) : null;
      bar.hidden = false;
      bar.innerHTML = `<span>Dời <b>${name}</b> ${esc(m.x.symbol)} #${m.x.ticket}: ${m.from ? fmt(m.from, this.digits) : "–"} → <b>${fmt(m.price, this.digits)}</b>
          ${money != null ? `<span class="${money >= 0 ? "pos" : "neg"}">${signed(money)}</span>` : ""}</span>
        <button type="button" class="no" data-a="no">Huỷ</button><button type="button" class="yes" data-a="yes">Xác nhận</button>`;
      bar.querySelector("[data-a=no]").onclick = () => this.closeMove();
      bar.querySelector("[data-a=yes]").onclick = async (e) => {
        const btn = e.currentTarget;
        btn.disabled = true;
        const ok = await act(btn, () => this.call("/mt5/modify", m.body), `Đã dời ${name} → ${fmt(m.price, this.digits)}`);
        if (ok) { if (m.field === "entry") m.x.entry = m.price; else m.x[m.field] = m.price; }
        this.closeMove();
        this.refresh();
      };
    },

    closeMove() {
      this.pendingMove = null;
      const bar = $("moveConfirm");
      if (bar) bar.hidden = true;
      this.syncLines();
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
    tapChart(y, x, ev) {
      if (x > this.chart.timeScale().width()) return;
      const ring = () => { if (ev && !(this.drawings && (this.drawings.selected || this.drawings.current))) this.tfRingSoon(ev.clientX, ev.clientY); };
      // A news dot: that news, its figures and how gold moved.
      const dot = (this.newsDots || []).find((d) => Math.hypot(d.x - x, d.y - y) < 12);
      if (dot) { this.newsSheet(dot.e); return; }
      if (this.replayPicking) {
        const i = this.indexAt(x);
        if (i != null) this.startReplayAt(i);
        return;
      }
      if (!this.owner || this.replay) { ring(); return; }
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
      } else ring();
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
      if (p != null && !this.replay) items.push(["alert", `🔔 Cảnh báo khi giá chạm ${fmt(p, this.digits)}`]);
      const zone = this.drawings && this.drawings.current ? this.zoneOf(this.drawings.current) : null;
      if (zone && !this.replay) items.push(["alertZone", `🔔 Cảnh báo khi giá vào vùng ${fmt(zone.bottom, this.digits)} – ${fmt(zone.top, this.digits)}`]);
      const myAlerts = this.symbolAlerts();
      if (myAlerts.length) items.push(["alertsClear", `🔕 Xoá cảnh báo giá (${myAlerts.length})`]);
      items.push(["tools", "✎ Công cụ vẽ…"]);
      if (this.drawings && this.drawings.list.length) items.push(["clear", `🗑 Xoá tất cả bản vẽ (${this.drawings.list.length})`]);
      if (this.drawings && this.drawings.current) items.push(["drawSettings", "⚙ Cài đặt bản vẽ…"], ["drawDel", "🗑 Xoá bản vẽ này"]);
      items.push(["ind", "ƒx Chỉ báo…"], ["ictSettings", "⚙ Cài đặt chỉ báo ICT…"], ["macroSettings", "⚙ Macro…"], ["sessSettings", "🔔 Thông báo phiên…"], ["liqSettings", "⚙ Vùng thanh khoản…"], ["planSettings", "⚙ Kế hoạch giao dịch…"], ["chartStyle", "🎨 Cài đặt biểu đồ (màu, sáng/tối)…"]);
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
        if (k === "alert") this.addAlert({ kind: "price", price: p });
        if (k === "alertZone") this.addAlert({ kind: "zone", drawingId: this.drawings.current.id, top: zone.top, bottom: zone.bottom });
        if (k === "alertsClear") { this.saveAlerts(this.alerts.filter((a) => a.sym !== this.symbolKey())); toast("Đã xoá cảnh báo giá"); }
        if (k === "pending") { this.togglePending(true); $("pPrice").value = fmt(p, this.digits); this.updatePendingLabels(); this.syncLines(); }
        if (k === "tools") this.drawSheet();
        if (k === "clear" && confirm("Xoá tất cả bản vẽ trên mã này?")) this.drawings.clear();
        if (k === "ind") this.indicatorSheet();
        if (k === "ictSettings") this.ictSettingsSheet();
        if (k === "planSettings") this.planSettingsSheet();
        if (k === "liqSettings") this.liqSettingsSheet();
        if (k === "macroSettings") this.macroSettingsSheet();
        if (k === "sessSettings") this.sessSettingsSheet();
        if (k === "setups") this.setupListSheet();
        if (k === "drawSettings") this.drawingSettings(this.drawings.current);
        if (k === "drawDel" && this.drawings.current) this.drawings.remove(this.drawings.current.id);
        if (k === "chartStyle") this.chartStyleSheet();
      }));
    },

    /* ----- price alerts: a beep, the voice and a note when price reaches a level or enters a zone ----- */

    get alerts() {
      if (!this._alerts) { try { this._alerts = JSON.parse(store.get("aurum.alerts") || "[]"); } catch { this._alerts = []; } }
      return this._alerts;
    },

    saveAlerts(list) {
      this._alerts = list;
      store.set("aurum.alerts", JSON.stringify(list));
      if (this.requestICT) this.requestICT();
    },

    symbolAlerts() { return this.alerts.filter((a) => a.sym === this.symbolKey()); },

    /** The prices a drawing covers (a rectangle, a channel, a level…): the zone an alert watches. */
    zoneOf(d) {
      const prices = (d.pts || []).map((x) => x.p).filter((v) => v != null);
      if (!prices.length) return null;
      const top = Math.max(...prices), bottom = Math.min(...prices);
      return { top, bottom };
    },

    addAlert(a) {
      Voice.unlock();
      const alert = Object.assign({ id: Math.random().toString(36).slice(2, 8), sym: this.symbolKey(), at: Date.now() }, a);
      this.saveAlerts(this.alerts.concat(alert));
      const d = this.digits;
      toast(a.kind === "zone" ? `🔔 Sẽ kêu khi giá vào vùng ${fmt(a.bottom, d)} – ${fmt(a.top, d)}` : `🔔 Sẽ kêu khi giá chạm ${fmt(a.price, d)}`);
    },

    /** Each new price against the alerts of this symbol: a level is reached when the price crosses or touches
     *  it, a zone when the price comes inside it. Each alert rings once, then goes. */
    checkAlerts(price) {
      if (price == null || this.replay || !this.alerts.length) return;
      const sym = this.symbolKey(), d = this.digits, fired = [];
      this.alerts.forEach((a) => {
        if (a.sym !== sym) return;
        let zone = a.kind === "zone" ? { top: a.top, bottom: a.bottom } : null;
        if (zone && a.drawingId && this.drawings) {
          // The zone follows its drawing when it is moved or reshaped.
          const dr = this.drawings.list.find((x) => x.id === a.drawingId);
          if (dr) { zone = this.zoneOf(dr) || zone; a.top = zone.top; a.bottom = zone.bottom; }
        }
        const prev = a.last;
        a.last = price;
        if (prev == null) {
          // Already there when set: a zone rings at once, a level waits for the price to come to it.
          if (zone && price >= zone.bottom && price <= zone.top) fired.push(a);
          return;
        }
        if (zone) { if (price >= zone.bottom && price <= zone.top && !(prev >= zone.bottom && prev <= zone.top)) fired.push(a); }
        else if ((prev - a.price) * (price - a.price) <= 0 && prev !== price) fired.push(a);
      });
      if (!fired.length) return;
      fired.forEach((a) => {
        const what = a.kind === "zone" ? `vào vùng ${fmt(a.bottom, d)} – ${fmt(a.top, d)}` : `chạm ${fmt(a.price, d)}`;
        Voice.alarm();
        setTimeout(() => Voice.speak(`${Voice.spokenSymbol(sym)} ${a.kind === "zone" ? "vào vùng cảnh báo" : "chạm giá cảnh báo"} ${Voice.spokenPrice(price)}`, true), 700);
        toast(`🔔 ${sym}: giá ${what} (${fmt(price, d)})`);
        if (document.hidden && window.Notification && Notification.permission === "granted") {
          try { new Notification(`🔔 ${sym}`, { body: `Giá ${what} (${fmt(price, d)})`, icon: "favicon.svg" }); } catch { /* not allowed */ }
        }
      });
      this.saveAlerts(this.alerts.filter((a) => !fired.includes(a)));
    },

    /** Alert levels as yellow dashed lines with a bell, zones with a bell at their right. */
    drawAlerts(g, width) {
      const list = this.symbolAlerts();
      if (!list.length || this.replay) return;
      g.save();
      g.font = "600 10.5px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
      g.textBaseline = "middle"; g.textAlign = "right";
      list.forEach((a) => {
        const color = "#f2c14e";
        if (a.kind === "zone") {
          const yt = this.series.priceToCoordinate(a.top), yb = this.series.priceToCoordinate(a.bottom);
          if (yt == null || yb == null) return;
          g.strokeStyle = rgba(color, 0.8); g.lineWidth = 2;
          g.beginPath(); g.moveTo(width - 3, yt); g.lineTo(width - 3, yb); g.stroke();
          g.fillStyle = color; g.fillText("🔔 vùng", width - 8, Math.min(yt, yb) + 8);
          return;
        }
        const yy = this.series.priceToCoordinate(a.price);
        if (yy == null) return;
        const y = Math.round(yy) + 0.5;
        g.strokeStyle = rgba(color, 0.75); g.lineWidth = 1; g.setLineDash([6, 4]);
        g.beginPath(); g.moveTo(0, y); g.lineTo(width, y); g.stroke();
        g.setLineDash([]);
        g.fillStyle = color; g.fillText(`🔔 ${fmt(a.price, this.digits)}`, width - 8, y - 8);
      });
      g.restore();
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
      if (tool === "curve") return "chạm điểm đầu, điểm giữa (độ cong) rồi điểm cuối";
      if (n === 1 || tool === "longPosition" || tool === "shortPosition") return tool.endsWith("Position") ? "chạm vào giá vào lệnh: hộp vừa màn hình, kéo SL / TP / mép phải riêng từng cái" : "chạm vào chỗ cần đặt";
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
        // The saved templates one tap away: the next drawing starts with the one picked.
        const tpls = Object.keys(d.templates(d.tool)), next = tpls.length ? d.nextTemplate(d.tool) : null;
        bar.innerHTML = `<span class="db-grip" title="Kéo để di chuyển · bấm đúp để về giữa">⋮⋮</span><span><b>${esc(D.tools[d.tool].name)}</b> · ${this.hint(d.tool)}</span>`
          + (tpls.length ? `<button type="button" data-a="tplNext" class="db-pick" title="Mẫu cho đường vẽ tiếp theo">${BAR_ICON.tpl}<span class="db-px">${esc(next || "Mẫu")}</span>${BAR_ICON.chev}</button>` : "")
          + `<button type="button" data-a="cancel">Huỷ</button>`;
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
          if (a === "tplNext") { this.nextTemplateMenu(b, d); return; }
          this.renderDrawBar();
        };
      });
    },

    /** The drawing bar where it was dragged to (kept), or centred at the top of the chart; placed again
     *  whenever the chart holding it changes size (split dividers, layouts), so it never hangs outside. */
    placeDrawBar() {
      const bar = $("drawBar"), wrap = bar.parentElement;
      if (window.ResizeObserver && wrap) {
        if (!this.drawBarWatch) this.drawBarWatch = new ResizeObserver(() => { if (!$("drawBar").hidden) this.placeDrawBar(); });
        if (this.drawBarWatched !== wrap) {
          if (this.drawBarWatched) this.drawBarWatch.unobserve(this.drawBarWatched);
          this.drawBarWatch.observe(wrap);
          this.drawBarWatched = wrap;
        }
      }
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
      // The backtest starts with the ticket's lot (0.01 … 200, picked from its ▾ list).
      if (!prev) store.set("aurum.rlots", this.lots().toFixed(2));
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
      if (this.replayGap && r.idx >= this.bars.length - 60) this.replayExtend();
      if (r.idx >= this.bars.length - 1) {
        if (this.replayGap) return; // the next bars are on their way
        this.replayPause(); toast("Đã tới nến mới nhất"); return;
      }
      r.idx++;
      const bar = this.bars[r.idx];
      this.series.update(shown(bar));
      this.replayFill(bar);
      this.updateMascotMoods();
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
      // Bars of a window in the past: today's again.
      if (this.replayGap) { this.replayGap = false; this.replay = null; this.replayPicking = false; this.renderReplayBar(); this.updateTouchAction(); this.loadCandles(); return; }
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

    contractSize() { return this.contractOf(this.symbolKey()); },

    /** Bars after `after` (up to 2000 bars on), and whether they reach today's. */
    async replaySegment(after) {
      const sec = TF_SECONDS[this.interval] || 60, until = after + 2000 * sec;
      const data = await this.call(this.exnessPath(5000, until));
      return { bars: this.toBars(data.candles || []).filter((b) => b.time > after), live: until >= Date.now() / 1000 };
    },

    /** The bars around replay moment `t` (another timeframe picked during replay): 1000 before, the rest
     *  after it, joined to today's bars when they reach them. */
    async replayWindow(t, token) {
      try {
        const back = this.toBars((await this.call(this.exnessPath(1000, t + 1))).candles || []);
        if (token !== this.loadToken || back.length < 5) return;
        const fwd = await this.replaySegment(back[back.length - 1].time);
        if (token !== this.loadToken) return;
        let bars = back.concat(fwd.bars);
        const end = bars[bars.length - 1].time, today = this.bars;
        if (fwd.live || end >= today[0].time) bars = bars.concat(today.filter((b) => b.time > end));
        else this.replayGap = true;
        this.bars = bars;
        this.noOlder = false;
      } catch { /* keep today's bars */ }
    },

    /** Replay near the end of a window in the past: the next bars. */
    async replayExtend() {
      if (this.replayExtending || !this.replay) return;
      this.replayExtending = true;
      const token = this.loadToken;
      try {
        const seg = await this.replaySegment(this.bars[this.bars.length - 1].time);
        if (token !== this.loadToken || !this.replay) return;
        this.bars.push(...seg.bars);
        if (seg.live || !seg.bars.length) this.replayGap = false;
      } catch { /* try again on the next bar */ } finally { this.replayExtending = false; }
    },

    replayOrder(side) {
      const r = this.replay;
      if (!r) return;
      const bar = this.bars[r.idx];
      const lots = clampLots(num($("rLots").value));
      store.set("aurum.rlots", lots.toFixed(2));
      const t = { id: Math.random().toString(36).slice(2, 8), side, lots, entry: bar.close, time: bar.time,
        stop: num($("rStop").value), target: num($("rTarget").value) };
      r.trades.push(t);
      toast(`Replay: ${side === "long" ? "MUA" : "BÁN"} ${lots} @ ${fmt(t.entry, this.digits)}`);
      this.syncLines();
      this.renderReplayBar();
      if (store.get("aurum.jask") !== "0") this.journalAsk(t);
    },

    /** A replay trade's SL / TP dragged: on the side the price allows, then into its journal entry. */
    moveReplayLevel(id, field, price) {
      const t = this.replayTrade(id);
      if (!t || field === "entry") return this.syncLines();
      const now = this.bars[this.replay.idx].close, long = t.side === "long";
      const below = (field === "stop") === long;
      if (below ? price >= now : price <= now) {
        toast(`${field === "stop" ? "SL" : "TP"} của lệnh ${long ? "MUA" : "BÁN"} phải ${below ? "dưới" : "trên"} giá hiện tại ${fmt(now, this.digits)}`, true);
        return this.syncLines();
      }
      t[field] = +price.toFixed(this.digits);
      const list = this.journal(), e = list.find((x) => x.id === t.id && x.trade);
      if (e) { e.trade[field] = t[field]; this.saveJournal(list); }
      toast(`Replay: ${field === "stop" ? "SL" : "TP"} ${fmt(t[field], this.digits)} (${signed(this.replayProfit(t, t[field]))})`);
      this.syncLines();
      this.renderReplayBar();
    },

    replayProfit(t, price) { return (price - t.entry) * (t.side === "long" ? 1 : -1) * t.lots * this.contractSize(); },

    replayClose(t, price, reason) {
      const r = this.replay;
      r.trades = r.trades.filter((x) => x !== t);
      const profit = this.replayProfit(t, price);
      r.closed.unshift(Object.assign({}, t, { exit: price, reason, profit }));
      if (reason === "TP" || reason === "SL") {
        this.mascotEvent = { win: profit >= 0, at: Date.now() };
        if (t.target) this.crewEnded({ key: "rp:" + t.id, buy: t.side === "long", entry: t.entry, tp: t.target, sl: t.stop }, reason === "TP");
      }
      this.journalResult(t, price, reason, profit);
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
      $("replayBtn").classList.toggle("on", !!(r || this.replayPicking));
      // The chart gives up the bar's height (after it is drawn), so chart and bar fit on the screen together.
      requestAnimationFrame(() => {
        const h = bar.hidden ? 0 : bar.offsetHeight + 6;
        if (h === this.rbHeight) return;
        const first = !this.rbHeight && h;
        this.rbHeight = h;
        document.documentElement.style.setProperty("--rb", h + "px");
        if (first) setTimeout(() => bar.scrollIntoView({ block: "nearest", behavior: "smooth" }), 50);
      });
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
          <span class="r-lot"><button type="button" data-rstep="-1" aria-label="Giảm lot">−</button><input id="rLots" inputmode="decimal" value="${esc(store.get("aurum.rlots") || "0.01")}" title="Lot"><button type="button" class="lot-pick" data-a="rlotPick" title="Chọn nhanh khối lượng (tối đa ${MAX_LOTS} lot)">▾</button><button type="button" data-rstep="1" aria-label="Tăng lot">+</button></span>
          <button type="button" class="rb buybg" data-a="buy">BUY</button>
          <input id="rStop" inputmode="decimal" placeholder="SL" value="${esc((this.rDraft || {}).stop || "")}">
          <input id="rTarget" inputmode="decimal" placeholder="TP" value="${esc((this.rDraft || {}).target || "")}">
          <button type="button" class="rb" data-a="skip" title="Không vào lệnh ở nến này: ghi lý do vào nhật ký">Bỏ qua</button>
          ${r.trades.length ? `<button type="button" class="rb" data-a="closeAll">Đóng ${r.trades.length} lệnh</button>` : ""}
          <button type="button" class="rb" data-a="journal" title="Nhật ký backtest: lý do từng lệnh, thống kê, xuất file">📓 ${this.journal().length}</button>
          <label class="r-ask" title="Hỏi lý do mỗi lần bấm BUY / SELL"><input type="checkbox" data-a="ask" ${store.get("aurum.jask") !== "0" ? "checked" : ""}> Hỏi lý do</label>
          <span class="r-pnl">Đang mở <b class="${floating >= 0 ? "pos" : "neg"}">${signed(floating)}</b> · Đã đóng ${r.closed.length ? `${wins}/${r.closed.length} thắng ` : ""}<b class="${done >= 0 ? "pos" : "neg"}">${signed(done)}</b> USD</span>
        </div>`;
      const on = (a, f) => { const b = bar.querySelector(`[data-a=${a}]`); if (b) b.onclick = f; };
      on("exit", () => this.exitReplay());
      on("pick", () => { this.replayPause(); this.replayPicking = true; this.renderReplayBar(); });
      on("play", () => this.replayPlay());
      on("step", () => { this.replayPause(); this.replayStep(); });
      on("sell", () => this.replayOrder("short"));
      on("buy", () => this.replayOrder("long"));
      on("skip", () => this.journalAsk(null));
      on("journal", () => { this.replayPause(); this.journalSheet(); });
      bar.querySelector("[data-a=ask]").onchange = (e) => store.set("aurum.jask", e.target.checked ? "1" : "0");
      on("closeAll", () => { r.trades.slice().forEach((t) => this.replayClose(t, price, "Đóng tay")); this.syncLines(); this.renderReplayBar(); });
      bar.querySelector("[data-a=speed]").onchange = (e) => {
        r.speed = +e.target.value; store.set("aurum.rspeed", String(r.speed));
        if (r.playing) { clearInterval(r.timer); r.timer = setInterval(() => this.replayStep(), 1000 / r.speed); }
      };
      on("rlotPick", () => this.lotMenu($("rLots"), "aurum.rlots"));
      bar.querySelectorAll("[data-rstep]").forEach((b) => (b.onclick = () => this.stepLots($("rLots"), +b.dataset.rstep, "aurum.rlots")));
      $("rLots").onchange = () => { $("rLots").value = clampLots(num($("rLots").value)).toFixed(2); this.setLots($("rLots"), "aurum.rlots"); };
      ["rStop", "rTarget"].forEach((id) => ($(id).oninput = () => { this.rDraft = { stop: $("rStop").value, target: $("rTarget").value }; }));
    },

    /* ----- backtest journal: why each replay trade (or pass) was taken, with the chart around it ----- */

    journal() { try { return JSON.parse(store.get("aurum.journal") || "[]"); } catch { return []; } },

    saveJournal(list) {
      // The newest 3000 decisions (a few MB at most).
      try { store.set("aurum.journal", JSON.stringify(list.slice(-3000))); } catch { toast("Bộ nhớ trình duyệt đầy: xuất nhật ký rồi xoá bớt", true); }
    },

    journalTags(skip) {
      const own = (() => { try { return JSON.parse(store.get("aurum.jtags") || "[]"); } catch { return []; } })();
      const base = skip
        ? ["Chưa có setup", "Ngoài killzone", "Ngược xu hướng", "Sắp có tin", "Chưa quét thanh khoản", "Chưa phá trendline", "Giá giữa vùng", "Spread cao", "Đã đủ lệnh hôm nay"]
        : ["Quét thanh khoản", "FVG", "MSS / BOS", "Killzone London", "Killzone NY", "Phiên Á", "Đỉnh/đáy ngày", "Đỉnh/đáy tuần", "OTE (Fib)",
          "DM", "VI", "Cung cầu cá mập", "Dòng tiền cùng hướng", "Theo xu hướng khung lớn", "Ngược xu hướng", "SMT", "Tin tức",
          "Chạm trendline", "Phá trendline", "Retest trendline", "Trendline tăng", "Trendline giảm", "Kênh giá"];
      return base.concat(own.filter((t) => !base.includes(t)));
    },

    /** What the chart showed at the replay bar: recent bars, ICT marks near it, money flow, time. */
    journalContext() {
      const bars = this.viewBars(), n = bars.length, last = bars[n - 1], d = this.digits;
      const r = (v) => (v == null ? null : +(+v).toFixed(d));
      const ict = this.ict || {};
      const age = (i) => (i == null ? null : n - 1 - i);
      const sma = (k) => (n >= k ? r(bars.slice(-k).reduce((a, b) => a + b.close, 0) / k) : null);
      const flow = window.ICT && n > 30 ? (() => { try { return window.ICT.sharkFlow(bars); } catch { return null; } })() : null;
      const live = (ict.boxes || []).filter((b) => b.end >= n - 1);
      return {
        vnTime: new Date(last.time * 1000).toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh", weekday: "short", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }),
        killzone: live.map((b) => b.label || ((this.ictCfg.sessions || []).find((x) => x.color === b.color) || {}).name || "killzone").join(", ") || null,
        sma50: sma(50), sma200: sma(200),
        bars: bars.slice(-40).map((b) => [b.time, r(b.open), r(b.high), r(b.low), r(b.close)]),
        fvgs: (ict.fvgs || []).filter((g) => g.end == null || g.end >= n - 3).slice(-6).map((g) => ({ bull: g.bull, top: r(g.top), bottom: r(g.bottom), age: age(g.start) })),
        breaks: (ict.breaks || []).slice(-4).map((b) => ({ bull: b.bull, mss: !!b.shift, price: r(b.price), age: age(b.end) })),
        sweeps: (ict.sweeps || []).filter((s) => age(s.index) <= 60).slice(-6).map((s) => ({ bull: s.bull, label: s.label || "", price: r(s.price), age: age(s.index) })),
        levels: (ict.levels || []).filter((l) => !l.mitigated && l.kind !== "mid" && l.label)
          .sort((a, b) => Math.abs(a.price - last.close) - Math.abs(b.price - last.close)).slice(0, 8)
          .map((l) => ({ kind: l.kind, label: l.label, price: r(l.price) })),
        dms: (ict.dms || []).slice(-3).map((x) => ({ high: x.high, price: r(x.price), age: age(x.index) })),
        trendlines: this.trendlinesAt(bars).map((l) => Object.assign(l, { price: r(l.price) })),
        flow: flow ? { value: +flow.flow.toFixed(2), situation: flow.situation, zones: (flow.zones || []).slice(0, 4).map((z) => ({ demand: z.demand, top: r(z.top), bottom: r(z.bottom), strength: +z.strength.toFixed(2) })) } : null,
      };
    },

    /** The trend lines drawn on this symbol that reach the replay bar, nearest first: their price there, slope,
     *  and whether the last bars touched or crossed them. */
    trendlinesAt(bars) {
      const n = bars.length, d = this.drawingsMain;
      if (!d || n < 6) return [];
      const last = bars[n - 1], range = Math.max(...bars.slice(-50).map((b) => b.high)) - Math.min(...bars.slice(-50).map((b) => b.low));
      return d.list.filter((x) => ["trendLine", "trendRay"].includes(x.tool) && x.pts.length === 2 && x.pts[0].t !== x.pts[1].t).map((x) => {
        const [a, b] = x.pts[0].t < x.pts[1].t ? x.pts : [x.pts[1], x.pts[0]];
        const at = (t) => a.p + ((t - a.t) * (b.p - a.p)) / (b.t - a.t);
        const reaches = x.tool === "trendRay" || /right|both/.test(x.extend || "") || last.time <= b.t;
        if (!reaches || last.time < a.t) return null;
        const side = (bar) => Math.sign(bar.close - at(bar.time));
        const recent = bars.slice(-4);
        return {
          up: b.p > a.p, price: at(last.time), dist: Math.abs(last.close - at(last.time)), text: x.text || "",
          touched: recent.some((bar) => bar.low <= at(bar.time) && bar.high >= at(bar.time)),
          broken: side(bars[n - 6]) !== 0 && side(last) !== 0 && side(bars[n - 6]) !== side(last),
          near: range > 0 ? Math.abs(last.close - at(last.time)) / range < 0.15 : false,
        };
      }).filter((l) => l && (l.touched || l.broken || l.near)).sort((p, q) => p.dist - q.dist).slice(0, 4)
        .map(({ dist, ...l }) => l);
    },

    /** Tags the chart itself suggests (picked in advance, can be unpicked). */
    journalHints(ctx, skip) {
      if (skip) return [];
      const out = [];
      if (ctx.sweeps.some((s) => s.age <= 12)) out.push("Quét thanh khoản");
      if (ctx.fvgs.length) out.push("FVG");
      if (ctx.breaks.some((b) => b.age <= 15)) out.push("MSS / BOS");
      if (/london/i.test(ctx.killzone || "")) out.push("Killzone London");
      if (/new york|ny/i.test(ctx.killzone || "")) out.push("Killzone NY");
      if (/asia|á/i.test(ctx.killzone || "")) out.push("Phiên Á");
      const tl = (ctx.trendlines || [])[0];
      if (tl) {
        if (tl.broken) out.push("Phá trendline"); else if (tl.touched) out.push("Chạm trendline");
        out.push(tl.up ? "Trendline tăng" : "Trendline giảm");
      }
      return out;
    },

    /** One decision at the replay bar: a trade just placed (`trade`), or a pass (`trade` null). */
    journalAsk(trade) {
      const r = this.replay;
      if (!r) return;
      this.replayPause();
      const bar = this.bars[r.idx], skip = !trade, ctx = this.journalContext();
      const tags = this.journalTags(skip), picked = new Set(this.journalHints(ctx, skip));
      const head = skip ? "Bỏ qua cây nến này" : `${trade.side === "long" ? "MUA" : "BÁN"} ${trade.lots} @ ${fmt(trade.entry, this.digits)}`;
      sheet.open(`<h3>📓 ${esc(head)}</h3>
        <p class="muted small">${esc(ctx.vnTime)}${ctx.killzone ? " · " + esc(ctx.killzone) : ""} · ${esc(this.symbolKey())} ${esc(this.interval)}</p>
        <p class="small">${skip ? "Vì sao không vào lệnh?" : "Vì sao vào lệnh này? (chọn các lý do)"} <span class="muted">— đã chọn sẵn theo chart, bấm để bỏ</span></p>
        <div class="chips jtags">${tags.map((t) => `<button type="button" data-t="${esc(t)}" class="${picked.has(t) ? "on" : ""}">${esc(t)}</button>`).join("")}<button type="button" data-add>＋ Lý do khác</button></div>
        ${skip ? "" : `<div class="fields"><label>Bias khung lớn<select id="jBias"><option value="">—</option><option value="up">Tăng</option><option value="down">Giảm</option><option value="range">Đi ngang</option></select></label>
          <label>Độ tự tin<select id="jConf"><option value="">—</option><option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select></label></div>`}
        <div class="fields"><label>Ghi chú (tuỳ ý)<textarea id="jNote" rows="3" maxlength="600" placeholder="vd: quét đáy Á rồi MSS M5, vào ở FVG, SL dưới đáy quét"></textarea></label></div>
        <div class="row-btns end"><button class="btn btn-ghost btn-small" data-close>${skip ? "Huỷ" : "Không ghi"}</button><button class="btn btn-gold btn-small" id="jSave">Lưu vào nhật ký</button></div>`, (el) => {
        el.querySelectorAll("[data-t]").forEach((b) => (b.onclick = () => b.classList.toggle("on")));
        el.querySelector("[data-add]").onclick = (e) => {
          const t = (prompt("Lý do mới (sẽ được nhớ cho lần sau):") || "").trim().slice(0, 40);
          if (!t) return;
          const own = (() => { try { return JSON.parse(store.get("aurum.jtags") || "[]"); } catch { return []; } })();
          if (!own.includes(t)) { own.push(t); store.set("aurum.jtags", JSON.stringify(own)); }
          const b = document.createElement("button");
          b.type = "button"; b.dataset.t = t; b.className = "on"; b.textContent = t;
          b.onclick = () => b.classList.toggle("on");
          e.currentTarget.before(b);
        };
        el.querySelector("#jSave").onclick = () => {
          const list = this.journal();
          const entry = {
            id: trade ? trade.id : Math.random().toString(36).slice(2, 8),
            at: Date.now(), sym: this.symbolKey(), tf: this.interval, time: bar.time, price: bar.close, digits: this.digits,
            action: skip ? "skip" : trade.side === "long" ? "buy" : "sell",
            tags: [...el.querySelectorAll("[data-t].on")].map((b) => b.dataset.t),
            note: el.querySelector("#jNote").value.trim(),
            bias: skip ? null : el.querySelector("#jBias").value || null,
            confidence: skip ? null : +el.querySelector("#jConf").value || null,
            trade: skip ? null : { lots: trade.lots, entry: trade.entry, stop: trade.stop, target: trade.target },
            result: null, ctx,
          };
          list.push(entry);
          this.saveJournal(list);
          sheet.close();
          toast(skip ? "Đã ghi: bỏ qua" : "Đã ghi lý do vào nhật ký");
          this.renderReplayBar();
        };
      });
    },

    /** A replay trade closed: its result (money and R) into its journal entry. */
    journalResult(t, exit, reason, profit) {
      const list = this.journal(), e = list.find((x) => x.id === t.id && x.action !== "skip");
      if (!e) return;
      const risk = t.stop ? Math.abs(t.entry - t.stop) : null;
      const move = (exit - t.entry) * (t.side === "long" ? 1 : -1);
      e.result = { exit: +(+exit).toFixed(this.digits), reason, profit: +profit.toFixed(2), r: risk ? +(move / risk).toFixed(2) : null, bars: this.replay ? Math.round((this.bars[this.replay.idx].time - t.time) / (TF_SECONDS[this.interval] || 60)) : null };
      this.saveJournal(list);
    },

    journalSheet() {
      const list = this.journal();
      const trades = list.filter((e) => e.action !== "skip"), done = trades.filter((e) => e.result);
      const win = (e) => e.result.profit > 0;
      const rOf = (arr) => arr.reduce((a, e) => a + (e.result.r || 0), 0);
      const pct = (a, b) => (b ? Math.round((a / b) * 100) + "%" : "—");
      const byTag = {};
      done.forEach((e) => e.tags.forEach((t) => { (byTag[t] = byTag[t] || []).push(e); }));
      const tagRows = Object.entries(byTag).sort((a, b) => b[1].length - a[1].length).map(([t, arr]) =>
        `<tr><td>${esc(t)}</td><td>${arr.length}</td><td>${pct(arr.filter(win).length, arr.length)}</td><td class="${rOf(arr) >= 0 ? "pos" : "neg"}">${rOf(arr).toFixed(1)}R</td></tr>`).join("");
      const when = (e) => new Date((e.time + TZ) * 1000).toLocaleString("vi-VN", { timeZone: "UTC", day: "2-digit", month: "2-digit", year: "2-digit", hour: "2-digit", minute: "2-digit" });
      const act = { buy: '<b class="pos">MUA</b>', sell: '<b class="neg">BÁN</b>', skip: '<span class="muted">Bỏ qua</span>' };
      const rows = list.slice().reverse().slice(0, 200).map((e) => `<tr><td>${when(e)}<br><span class="muted small">${esc(e.sym)} ${esc(e.tf)}</span></td><td>${act[e.action]}</td>
        <td>${esc(e.tags.join(", "))}${e.note ? `<br><span class="muted small">${esc(e.note)}</span>` : ""}</td>
        <td>${e.result ? `<span class="${e.result.profit >= 0 ? "pos" : "neg"}">${signed(e.result.profit)}${e.result.r != null ? ` · ${e.result.r}R` : ""}</span><br><span class="muted small">${esc(e.result.reason)}</span>` : e.action === "skip" ? "" : '<span class="muted">chưa đóng</span>'}</td>
        <td><button type="button" class="tpl-x" data-del="${esc(e.id)}" title="Xoá">✕</button></td></tr>`).join("");
      sheet.open(`<h3>📓 Nhật ký backtest</h3>
        <div class="jstats"><div><span>Quyết định</span><b>${list.length}</b></div><div><span>Lệnh đã đóng</span><b>${done.length}</b></div>
          <div><span>Tỉ lệ thắng</span><b>${pct(done.filter(win).length, done.length)}</b></div><div><span>Tổng R</span><b class="${rOf(done) >= 0 ? "pos" : "neg"}">${rOf(done).toFixed(1)}R</b></div>
          <div><span>Bỏ qua</span><b>${list.length - trades.length}</b></div></div>
        ${tagRows ? `<p class="small"><b>Theo lý do</b> <span class="muted">(lệnh đã đóng)</span></p><div class="jtable"><table><tr><th>Lý do</th><th>Lệnh</th><th>Thắng</th><th>R</th></tr>${tagRows}</table></div>` : ""}
        <div class="row-btns"><button class="btn btn-gold btn-small" id="jJson">⬇ Xuất file (gửi cho Claude)</button><button class="btn btn-ghost btn-small" id="jCsv">⬇ Excel (CSV)</button>
          ${list.length ? '<button class="btn btn-ghost btn-small" id="jClear">Xoá hết</button>' : ""}</div>
        ${rows ? `<div class="jtable"><table><tr><th>Nến</th><th></th><th>Lý do</th><th>Kết quả</th><th></th></tr>${rows}</table></div>` : '<p class="muted">Chưa có gì. Trong Replay, bấm BUY / SELL hoặc "Bỏ qua" và chọn lý do.</p>'}`, (el) => {
        const download = (name, text, type) => {
          const a = document.createElement("a");
          a.href = URL.createObjectURL(new Blob([text], { type }));
          a.download = name; document.body.appendChild(a); a.click(); a.remove();
          setTimeout(() => URL.revokeObjectURL(a.href), 2000);
        };
        const stamp = new Date().toISOString().slice(0, 10);
        el.querySelector("#jJson").onclick = () => download(`aurum-nhat-ky-${stamp}.json`, JSON.stringify({ app: "Aurum Pro", kind: "backtest-journal", version: 1, exported: new Date().toISOString(), entries: this.journal() }, null, 1), "application/json");
        el.querySelector("#jCsv").onclick = () => {
          const q = (v) => `"${String(v == null ? "" : v).replace(/"/g, '""')}"`;
          const lines = [["Thời gian (VN)", "Mã", "Khung", "Hành động", "Giá", "SL", "TP", "Lý do", "Ghi chú", "Bias", "Tự tin", "Kết quả USD", "R", "Đóng do", "Killzone"].map(q).join(",")]
            .concat(this.journal().map((e) => [e.ctx && e.ctx.vnTime, e.sym, e.tf, e.action, e.price, e.trade && e.trade.stop, e.trade && e.trade.target, e.tags.join("; "), e.note, e.bias, e.confidence,
              e.result && e.result.profit, e.result && e.result.r, e.result && e.result.reason, e.ctx && e.ctx.killzone].map(q).join(",")));
          download(`aurum-nhat-ky-${stamp}.csv`, "﻿" + lines.join("\n"), "text/csv");
        };
        const clear = el.querySelector("#jClear");
        if (clear) clear.onclick = () => { if (confirm("Xoá toàn bộ nhật ký backtest? Nên xuất file trước.")) { this.saveJournal([]); this.journalSheet(); } };
        el.querySelectorAll("[data-del]").forEach((b) => (b.onclick = () => { this.saveJournal(this.journal().filter((e) => e.id !== b.dataset.del)); this.journalSheet(); }));
      });
    },

    /* ----- trade characters: an angler fishing a BUY up to its TP, a hauler dragging a SELL down to its TP ----- */

    /** Open trades with a TP on this chart: the replay's, or the MT5 positions on this symbol. */
    crewTrades() {
      // On the 1-minute chart only (a bar moves enough there for the pull to read).
      if (store.get("aurum.crewOff") === "1" || this.interval !== "1m") return [];
      if (this.replay) return this.replay.trades.filter((t) => t.target).map((t) => ({ key: "rp:" + t.id, buy: t.side === "long", entry: t.entry, tp: t.target, sl: t.stop }));
      if (!this.owner) return [];
      return this.positions.filter((p) => p.symbol === this.symbol && p.target).map((p) => ({ key: "pos:" + p.ticket, buy: p.side === "long", entry: p.entry, tp: p.target, sl: p.stop }));
    },

    /** Every trade with a character on the chart now: the open ones and those closed less than a minute ago. */
    crewShowing() {
      const done = (this.crewDone || []).filter((x) => Date.now() - x.at < CREW.endMs && x.sym === this.symbolKey());
      return this.crewTrades().filter((t) => !done.some((d) => d.key === t.key)).concat(done);
    },

    /** A trade closed at its TP (money) or SL (the line snaps): its character stays a minute. */
    crewEnded(trade, tpHit) {
      if (!trade || !trade.tp) return;
      this.crewDone = (this.crewDone || []).filter((x) => Date.now() - x.at < CREW.endMs && x.key !== trade.key);
      this.crewDone.push(Object.assign({}, trade, { tpHit, at: Date.now(), sym: this.symbolKey() }));
      this.placeCrewSoon();
    },

    placeCrewSoon() {
      if (this.crewRaf || !$("crew")) return;
      this.crewRaf = requestAnimationFrame(() => { this.crewRaf = 0; this.placeCrew(); });
    },

    /** How hard the character pulls: hard near the entry (or at a loss), less half way, at ease near the TP;
     *  braced (red, hair up) for a moment when the price jerks against the trade. */
    crewEffort(t, close, braced) {
      if (braced) return "brace";
      const p = t.buy ? (close - t.entry) / (t.tp - t.entry) : (t.entry - close) / (t.entry - t.tp);
      return p >= 0.66 ? "easy" : p >= 0.33 ? "effort" : "strain";
    },

    placeCrew() {
      const box = $("crew");
      if (!box || !this.chart) return;
      const now = performance.now(), wall = Date.now();
      const dt = Math.min(0.05, Math.max(0.001, (now - (this.crewAt || now)) / 1000));
      this.crewAt = now;
      const done = (this.crewDone || []).filter((x) => wall - x.at < CREW.endMs && x.sym === this.symbolKey() && this.interval === "1m");
      this.crewDone = done;
      const live = this.crewTrades().filter((t) => !done.some((d) => d.key === t.key));
      const bars = this.viewBars();
      if ((!live.length && !done.length) || !bars.length) { if (box.childElementCount) box.innerHTML = ""; this.crewShown = null; return; }
      const ts = this.chart.timeScale(), n = bars.length, last = bars[n - 1];
      const lx = ts.logicalToCoordinate(n - 1), spacing = ts.options().barSpacing || 6;
      if (lx == null) return;
      box.style.width = ts.width() + "px";
      const S = CREW.scale, custom = this.crewCustom();
      const all = live.map((t) => ({ t, end: null })).concat(done.map((d) => ({ t: d, end: d })));
      const sig = all.map((x) => x.t.key).join("|") + "@" + S;
      if (this.crewShown !== sig) {
        box.innerHTML = all.map((x) => `<img class="crew-pic" data-k="${esc(x.t.key)}" alt="" draggable="false">`).join("") + '<svg class="crew-lines"></svg>';
        // A new character: room for it right of the newest bar (when the chart shows the newest bars).
        const room = Math.ceil(5 + (S * 140 + all.length * 70 * S / 0.6) / spacing);
        const pos = ts.scrollPosition();
        if (pos > -2 && pos < room) ts.scrollToPosition(room, false);
        this.crewShown = sig;
      }
      this.crewPhys = this.crewPhys || {};
      const paneW = ts.width(), paneH = (this.chart.paneSize ? this.chart.paneSize().height : box.clientHeight) || box.clientHeight;
      let lines = "", moving = false;
      all.forEach((x, i) => {
        const t = x.t, img = box.querySelector(`img[data-k="${CSS.escape(t.key)}"]`);
        const ytp = this.series.priceToCoordinate(t.tp), py = this.series.priceToCoordinate(last.close);
        if (!img || ytp == null) return;
        const side = t.buy ? "buy" : "sell", own = custom[side];
        const who = t.buy ? "angler" : "hauler";
        // Spring physics: a price tick kicks the character (harder the faster the price moved), a spring brings it
        // back; the line's tension goes up when the candle pulls against the trade and drops when it gives way.
        const ph = this.crewPhys[t.key] || (this.crewPhys[t.key] = { last: last.close, x: 0, y: 0, vx: 0, vy: 0, ten: 0.4, brace: 0 });
        const effortNow = x.end ? null : this.crewEffort(t, last.close, false);
        if (!x.end && last.close !== ph.last && py != null) {
          const y0 = this.series.priceToCoordinate(ph.last);
          const dpx = y0 == null ? 0 : py - y0;                     // + = the price fell on screen
          const kick = Math.min(60, Math.abs(dpx)) * 9 * (S / 0.6);
          const against = t.buy ? last.close < ph.last : last.close > ph.last;
          if (t.buy) {
            // Price up: she is lifted (jumps); price down: dragged down toward the candle, bowing.
            ph.vy += against ? kick : -kick * 0.9; ph.vx += against ? -kick * 0.5 : kick * 0.25;
          } else {
            // Price down: he lunges forward and down; price up: yanked back and up toward the candle.
            ph.vy += against ? -kick * 0.9 : kick * 0.6; ph.vx += against ? -kick * 0.7 : kick * 0.4;
          }
          ph.ten = against ? 1 : Math.max(0, ph.ten - 0.6);
          if (against) { ph.hot = Math.min(1, (ph.hot || 0) + Math.abs(dpx) / 12); ph.kickAt = now; ph.kick = Math.abs(dpx); }
          if (against && Math.abs(dpx) > 1.5) ph.brace = wall + 450 + Math.min(900, Math.abs(dpx) * 40);
          ph.last = last.close;
        }
        // Integrate the spring (slightly under-damped: a small bounce).
        const k = 170, c = 15, lim = 70 * (S / 0.6);
        ph.vx += (-k * ph.x - c * ph.vx) * dt; ph.vy += (-k * ph.y - c * ph.vy) * dt;
        ph.x = Math.max(-lim, Math.min(lim, ph.x + ph.vx * dt)); ph.y = Math.max(-lim, Math.min(lim, ph.y + ph.vy * dt));
        const restTen = { easy: 0.12, effort: 0.45, strain: 0.8, brace: 0.95 }[effortNow] || 0.4;
        ph.ten += (restTen - ph.ten) * Math.min(1, dt * 2.5);
        // How red the line glows: a hard jerk against the trade heats it, it cools in about a second.
        ph.hot = Math.max(0, (ph.hot || 0) - dt * 0.9);
        if (ph.hot > 0.01) moving = true;
        if (Math.abs(ph.vx) + Math.abs(ph.vy) > 2 || Math.abs(ph.x) + Math.abs(ph.y) > 0.4 || Math.abs(ph.ten - restTen) > 0.02) moving = true;
        const braced = !x.end && wall < ph.brace;
        const mood = x.end ? (x.end.tpHit ? "money" : "snap") : braced ? "brace" : effortNow;
        // The picture: the character's own (uploaded) or the drawn one.
        const W = own ? 172 * S * (own.w >= own.h ? 1.15 : 1) : 172 * S;
        const H = own ? W * own.h / own.w : 206 * S;
        const feet = own ? H * (own.gy || 1) : (156 + 34) * S;
        const cx = lx + spacing * 5 + (t.buy ? 30 : 40) * S + i * 70 * (S / 0.6);
        let left = cx - (own ? W / 2 : (80 + 6) * S) + ph.x, top = ytp - feet + ph.y;
        const off = top < 2 ? "up" : top + feet > paneH - 2 ? "down" : null;
        top = Math.max(2, Math.min(paneH - feet - 2, top));
        left = Math.max(2, Math.min(paneW - W - 2, left));
        const src = own ? own.src : `${CREW.folder}/${who}-${mood}.svg`;
        if (img.getAttribute("src") !== src) img.setAttribute("src", src);
        // An uploaded picture shows the states by its pose: leaning back harder the harder the pull, a red glow
        // when braced, a hop with the money, knocked over at the SL. The drawn ones also tilt a little with the spring.
        const lean = own ? ({ easy: 0, effort: 5, strain: 10, brace: 14, money: 0, snap: 32 }[mood] || 0) * (t.buy ? 1 : 1) : 0;
        const tilt = Math.max(-10, Math.min(10, ph.vx * 0.03)) + lean;
        const flip = "";
        img.style.cssText = `width:${W.toFixed(1)}px;height:${H.toFixed(1)}px;transform-origin:50% ${((feet / H) * 100).toFixed(1)}%;`
          + `transform:translate(${left.toFixed(1)}px,${top.toFixed(1)}px) rotate(${tilt.toFixed(2)}deg)${flip};`
          + (own ? (mood === "brace" ? "filter:drop-shadow(0 0 6px #ff4a2a) drop-shadow(0 0 2px #ff4a2a);" : mood === "snap" ? "filter:grayscale(.6) drop-shadow(0 0 3px #f2c14e);" : "filter:drop-shadow(0 0 3px #f2c14e);") : "");
        img.title = `${t.buy ? "BUY" : "SELL"} · TP ${fmt(t.tp, this.digits)}`;
        if (off) {
          // Beside the character (right, or left at the chart's right edge), level with its feet / head.
          const right = left + W + 82 < paneW;
          const tx = right ? left + W + 40 : left - 40, ty = off === "up" ? top + 12 : top + H - 12;
          lines += `<g transform="translate(${tx.toFixed(1)} ${ty.toFixed(1)})"><rect x="-38" y="-9" width="76" height="16" rx="8" fill="#14b88a" opacity=".92"/>`
            + `<text y="3.4" text-anchor="middle" font-size="10" font-weight="700" fill="#fff" font-family="-apple-system, Segoe UI, Roboto, sans-serif">TP ${off === "up" ? "▲" : "▼"} ${fmt(t.tp, this.digits)}</text></g>`;
        }
        if (own && x.end) {
          lines += x.end.tpHit
            ? `<text x="${(left + W / 2).toFixed(1)}" y="${(top - 4).toFixed(1)}" text-anchor="middle" font-size="${(22 * S / 0.6).toFixed(0)}">💰</text>`
            : `<text x="${(left + W / 2).toFixed(1)}" y="${(top - 4).toFixed(1)}" text-anchor="middle" font-size="${(20 * S / 0.6).toFixed(0)}" fill="#ff5a70" font-weight="900">!</text>`;
        }
        if (x.end) {
          if (!x.end.tpHit && wall - x.end.at < 1500 && py != null) {
            lines += `<path class="crew-piece" d="M${lx} ${py} q6 ${t.buy ? -18 : 18} -2 ${t.buy ? -36 : 36}" stroke="${t.buy ? "#e8eef7" : "#c9a46a"}" stroke-width="${t.buy ? 0.55 : 1.1}" fill="none"/>`;
          }
          return;
        }
        if (py == null) return;
        // Where the line starts: the uploaded picture's marked point (turned with it), else the drawn rod / shoulder.
        let sx, sy;
        if (own) {
          const ax = own.ax * W, ay = own.ay * H;
          const ox = W / 2, oy = feet, r = (tilt * Math.PI) / 180;
          sx = left + ox + (ax - ox) * Math.cos(r) - (ay - oy) * Math.sin(r);
          sy = top + oy + (ax - ox) * Math.sin(r) + (ay - oy) * Math.cos(r);
        } else {
          const at = (CREW.points[who] || {})[mood] || (t.buy ? [14, 40] : [62, 77]);
          const ax = (at[0] + 6) * S, ay = (at[1] + 34) * S, ox = (80 + 6) * S, oy = feet, r = ((tilt - lean) * Math.PI) / 180;
          sx = left + ox + (ax - ox) * Math.cos(r) - (ay - oy) * Math.sin(r);
          sy = top + oy + (ax - ox) * Math.sin(r) + (ay - oy) * Math.cos(r);
        }
        // Slack when the pull eases (it sags), tight and quivering when the candle pulls hard.
        const len = Math.hypot(lx - sx, py - sy);
        const sag = (1 - ph.ten) * Math.min(40, len * 0.22) * (S / 0.6);
        const quiver = ph.ten > 0.7 ? Math.sin(now / 22) * 1.8 * (ph.ten - 0.6) * 2.5 : 0;
        if (quiver) moving = true;
        const mx = (sx + lx) / 2 + quiver, my = (sy + py) / 2 + sag + quiver;
        const d = `M${sx.toFixed(1)} ${sy.toFixed(1)} Q${mx.toFixed(1)} ${my.toFixed(1)} ${lx} ${py.toFixed(1)}`;
        // Black line (with a pale halo on a dark chart), turning red-hot when the price jerks hard against the trade.
        const light = document.documentElement.dataset.theme === "light", hot = Math.min(1, ph.hot || 0);
        const mix = (a, b, f) => "#" + [0, 2, 4].map((i) => Math.round(parseInt(a.slice(i + 1, i + 3), 16) * (1 - f) + parseInt(b.slice(i + 1, i + 3), 16) * f).toString(16).padStart(2, "0")).join("");
        const color = mix(light ? "#000000" : "#05070a", "#ff2a3a", hot);
        // Hair-thin (under half a pixel) unless the line glows hot.
        const w = (t.buy ? 0.4 + ph.ten * 0.08 : 0.45 + ph.ten * 0.05) * (1 + hot * 1.4);
        if (!light) lines += `<path d="${d}" stroke="#e8eef7" stroke-width="${(w + 1).toFixed(2)}" fill="none" opacity="${(0.4 * (1 - hot)).toFixed(2)}" stroke-linecap="round"/>`;
        if (hot > 0.05) lines += `<path d="${d}" stroke="#ff3b2f" stroke-width="${(w + 4 * hot).toFixed(2)}" fill="none" opacity="${(0.32 * hot).toFixed(2)}" stroke-linecap="round"/>`;
        lines += `<path d="${d}" stroke="${color}" stroke-width="${w.toFixed(2)}" fill="none" stroke-linecap="round"/>`;
        if (!t.buy && hot > 0.3) lines += `<path d="${d}" stroke="#ffd2a0" stroke-width="${w.toFixed(2)}" fill="none" stroke-dasharray="1 2.4" opacity="${(0.6 * hot).toFixed(2)}"/>`;
        // The line's end at the hand / the rod tip, so it reads as held.
        lines += `<circle cx="${sx.toFixed(1)}" cy="${sy.toFixed(1)}" r="${Math.max(0.7, w).toFixed(2)}" fill="${color}"/>`;
        lines += t.buy ? `<path d="M${lx} ${py.toFixed(1)} v2.2 q0 1.6 -1.6 1.3" stroke="${color}" stroke-width=".9" fill="none"/>`
          : `<circle cx="${lx}" cy="${py.toFixed(1)}" r="1.5" fill="none" stroke="${color}" stroke-width="1.1"/>`;
        if (hot > 0.35) {
          // Sparks running along the hot line, and strain streaks at the hands.
          for (let k = 0; k < 4; k++) {
            const f = ((now / 380 + k / 4) % 1), q = 1 - f;
            const px = q * q * sx + 2 * q * f * mx + f * f * lx, pyy = q * q * sy + 2 * q * f * my + f * f * py;
            lines += `<circle cx="${px.toFixed(1)}" cy="${pyy.toFixed(1)}" r="${(1.2 + hot).toFixed(1)}" fill="#ffd54a" opacity="${(hot * (0.5 + 0.5 * Math.sin(now / 60 + k))).toFixed(2)}"/>`;
          }
          const ang = Math.atan2(py - sy, lx - sx) + Math.PI;
          [-0.5, 0, 0.5].forEach((o, k) => {
            const a = ang + o, r0 = 6 * (S / 0.6), r1 = r0 + (6 + hot * 8) * (S / 0.6);
            lines += `<path d="M${(sx + Math.cos(a) * r0).toFixed(1)} ${(sy + Math.sin(a) * r0).toFixed(1)} L${(sx + Math.cos(a) * r1).toFixed(1)} ${(sy + Math.sin(a) * r1).toFixed(1)}" stroke="${k === 1 ? "#ff3b2f" : "#ffb24a"}" stroke-width="1.4" stroke-linecap="round" opacity="${hot.toFixed(2)}"/>`;
          });
        }
        if (ph.kickAt && now - ph.kickAt < 350 && ph.kick > 2) {
          // A hard jerk kicks up dust at the feet.
          const fx = left + W / 2, fy = top + feet, f = (now - ph.kickAt) / 350;
          lines += `<path d="M${(fx - 10 - f * 14).toFixed(1)} ${fy.toFixed(1)} q-5 -${(4 + f * 4).toFixed(1)} -10 0 M${(fx + 10 + f * 14).toFixed(1)} ${fy.toFixed(1)} q5 -${(4 + f * 4).toFixed(1)} 10 0" stroke="${light ? "#8b95a7" : "#c9d1de"}" stroke-width="1.3" fill="none" opacity="${(1 - f).toFixed(2)}"/>`;
          moving = true;
        }
      });
      box.querySelector(".crew-lines").innerHTML = lines;
      if (done.length) moving = true;
      // Keep animating (every frame) while a spring, the line's tension or a quiver is still moving.
      cancelAnimationFrame(this.crewLoop);
      if (moving) this.crewLoop = requestAnimationFrame(() => this.placeCrew());
      else this.crewAt = 0;
    },

    /** Pictures uploaded for the BUY / SELL character: { buy: { src, w, h, ax, ay, flip }, sell: … }. */
    crewCustom() {
      if (this.crewCustomCache === undefined) {
        try { this.crewCustomCache = JSON.parse(store.get("aurum.crewCustom") || "{}") || {}; } catch { this.crewCustomCache = {}; }
        // Pictures saved before the line's start was found by itself: find it on the rod's tip / the fist now, once.
        Object.entries(this.crewCustomCache).forEach(([side, v]) => {
          if (!v || v.anchorV === 2) return;
          const im = new Image();
          im.onload = () => {
            const cv = document.createElement("canvas");
            cv.width = v.w; cv.height = v.h;
            cv.getContext("2d").drawImage(im, 0, 0, v.w, v.h);
            Object.assign(v, this.crewFindAnchor(cv, side), { anchorV: 2 });
            this.saveCrewCustom(this.crewCustomCache);
          };
          im.src = v.src;
        });
      }
      return this.crewCustomCache;
    },

    saveCrewCustom(v) {
      this.crewCustomCache = v;
      try { store.set("aurum.crewCustom", JSON.stringify(v)); } catch { toast("Ảnh quá lớn để lưu trong trình duyệt", true); }
      this.crewShown = null;
      this.placeCrew();
    },

    /** Your own pictures for the characters: pick one, then mark where the line starts (rod tip / shoulder) and
     *  the ground the feet stand on, erase what should not show (a fish, a watermark), flip it to face the candles. */
    crewPictureSheet() {
      const cur = JSON.parse(JSON.stringify(this.crewCustom()));
      sheet.open(`<h3>Ảnh nhân vật của bạn</h3>
        <p class="muted small">Dùng ảnh bạn có quyền sử dụng (PNG nền trong suốt là đẹp nhất). Người câu nên quay mặt sang trái, về phía nến (dùng <b>Lật ngang</b>).
        Chọn công cụ rồi chạm vào ảnh: <b>Nối dây</b> = đầu cần câu / vai, <b>Mặt đất</b> = chỗ chân đứng (đặt trên mức TP), <b>Tẩy</b> = xoá phần thừa (con cá, chữ, bóng nước).</p>
        <div class="cp-tabs"><button type="button" data-side="buy" class="on">🎣 BUY — người câu</button><button type="button" data-side="sell">🪢 SELL — người kéo</button></div>
        <div class="cp-edit"></div>
        <div class="row-btns end"><button class="btn btn-ghost btn-small" data-close>Huỷ</button><button class="btn btn-gold btn-small" id="cpSave">Lưu</button></div>`, (el) => {
        let side = "buy";
        const tabs = el.querySelectorAll(".cp-tabs button");
        tabs.forEach((b) => (b.onclick = () => { side = b.dataset.side; tabs.forEach((x) => x.classList.toggle("on", x === b)); this.crewEditor(el.querySelector(".cp-edit"), cur, side); }));
        this.crewEditor(el.querySelector(".cp-edit"), cur, side);
        el.querySelector("#cpSave").onclick = () => {
          Object.values(cur).forEach((v) => { if (v) v.anchorV = 2; });
          this.saveCrewCustom(cur); sheet.close(); toast("Đã lưu ảnh nhân vật");
        };
      });
    },

    /** Where the line most likely starts in a picture: the rod's tip for the angler (the far end of the figure up
     *  toward the candles: left and high), the fist on the rope for the hauler (the figure's top-left point). */
    crewFindAnchor(canvas, side) {
      const w = canvas.width, h = canvas.height, data = canvas.getContext("2d").getImageData(0, 0, w, h).data;
      const solid = (x, y) => x >= 0 && y >= 0 && x < w && y < h && data[(y * w + x) * 4 + 3] >= 120;
      // The hauler's fist, not the thin rope running off it: only spots with body around them count.
      const thick = (x, y) => { let n = 0; for (let j = -2; j <= 2; j++) for (let i = -2; i <= 2; i++) n += solid(x + i, y + j) ? 1 : 0; return n >= 16; };
      let best = null;
      for (let y = 0; y < h * 0.6; y++) for (let x = 0; x < w; x++) {
        if (!solid(x, y) || (side !== "buy" && !thick(x, y))) continue;
        const score = side === "buy" ? x + y * 0.35 : x + y;
        if (!best || score < best.score) best = { score, x, y };
      }
      return best ? { ax: (best.x + 0.5) / w, ay: (best.y + 0.5) / h } : {};
    },

    crewEditor(box, cur, side) {
      const v = cur[side];
      box.innerHTML = `<div class="row-btns"><label class="btn btn-ghost btn-small">Chọn ảnh…<input type="file" accept="image/*" hidden></label>
        ${v ? `<button class="btn btn-ghost btn-small" data-a="flip">⇋ Lật ngang</button><button class="btn btn-ghost btn-small" data-a="auto">🎯 Tự tìm ${side === "buy" ? "đầu cần" : "tay nắm dây"}</button><button class="btn btn-ghost btn-small" data-a="clear">Bỏ ảnh</button>` : ""}</div>
        ${v ? `<div class="cp-tools"><button type="button" data-t="dot" class="on">● Nối dây</button><button type="button" data-t="ground">▁ Mặt đất</button>
          <button type="button" data-t="erase">⌫ Tẩy</button><label class="muted small">cỡ tẩy <input type="range" min="4" max="40" value="14" data-a="size"></label></div>
          <div class="cp-pic"><canvas></canvas><i class="cp-dot"></i><i class="cp-ground"></i></div>`
          : '<p class="muted small">Chưa có ảnh — đang dùng hình vẽ sẵn.</p>'}`;
      box.querySelector("input[type=file]").onchange = (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => {
          const im = new Image();
          im.onload = () => {
            // Down to 360 px on the long side (kept in the browser).
            const k = Math.min(1, 360 / Math.max(im.width, im.height));
            const cv = document.createElement("canvas");
            cv.width = Math.round(im.width * k); cv.height = Math.round(im.height * k);
            cv.getContext("2d").drawImage(im, 0, 0, cv.width, cv.height);
            cur[side] = { src: cv.toDataURL("image/png"), w: cv.width, h: cv.height, ax: side === "buy" ? 0.06 : 0.45, ay: 0.08, gy: 0.98 };
            Object.assign(cur[side], this.crewFindAnchor(cv, side));
            this.crewEditor(box, cur, side);
          };
          im.src = reader.result;
        };
        reader.readAsDataURL(file);
      };
      if (!v) return;
      const canvas = box.querySelector("canvas"), g = canvas.getContext("2d");
      canvas.width = v.w; canvas.height = v.h;
      const img = new Image();
      img.onload = () => {
        g.clearRect(0, 0, v.w, v.h); g.drawImage(img, 0, 0);
        if (v.findAnchor) { delete v.findAnchor; Object.assign(v, this.crewFindAnchor(canvas, side)); marks(); }
      };
      img.src = v.src;
      const marks = () => {
        box.querySelector(".cp-dot").style.cssText = `left:${(v.ax * 100).toFixed(1)}%;top:${(v.ay * 100).toFixed(1)}%`;
        box.querySelector(".cp-ground").style.top = `${((v.gy || 1) * 100).toFixed(1)}%`;
      };
      marks();
      let tool = "dot", size = 14, erasing = false;
      box.querySelectorAll("[data-t]").forEach((b) => (b.onclick = () => { tool = b.dataset.t; box.querySelectorAll("[data-t]").forEach((x) => x.classList.toggle("on", x === b)); }));
      box.querySelector("[data-a=size]").oninput = (e) => { size = +e.target.value; };
      const at = (e) => { const r = canvas.getBoundingClientRect(); return [(e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height]; };
      const rub = (e) => {
        const [fx, fy] = at(e), r = canvas.getBoundingClientRect();
        g.save(); g.globalCompositeOperation = "destination-out";
        g.beginPath(); g.arc(fx * v.w, fy * v.h, (size / 2) * (v.w / r.width), 0, Math.PI * 2); g.fill(); g.restore();
      };
      canvas.onpointerdown = (e) => {
        e.preventDefault();
        const [fx, fy] = at(e);
        if (tool === "dot") {
          // Onto the figure: the nearest drawn pixel within a few pixels of the tap (the rod's tip, the hand).
          const px = Math.round(fx * v.w), py = Math.round(fy * v.h), r = Math.round(24 * v.w / canvas.getBoundingClientRect().width);
          const data = g.getImageData(Math.max(0, px - r), Math.max(0, py - r), Math.min(v.w, px + r + 1) - Math.max(0, px - r), Math.min(v.h, py + r + 1) - Math.max(0, py - r));
          let best = null;
          for (let y = 0; y < data.height; y++) for (let x = 0; x < data.width; x++) {
            if (data.data[(y * data.width + x) * 4 + 3] < 120) continue;
            const ax = Math.max(0, px - r) + x, ay = Math.max(0, py - r) + y, dd = (ax - px) ** 2 + (ay - py) ** 2;
            if (!best || dd < best.dd) best = { ax, ay, dd };
          }
          v.ax = best ? (best.ax + 0.5) / v.w : fx; v.ay = best ? (best.ay + 0.5) / v.h : fy;
          marks();
        }
        else if (tool === "ground") { v.gy = fy; marks(); }
        else { erasing = true; canvas.setPointerCapture(e.pointerId); rub(e); }
      };
      canvas.onpointermove = (e) => { if (erasing) rub(e); };
      canvas.onpointerup = canvas.onpointercancel = () => { if (erasing) { erasing = false; v.src = canvas.toDataURL("image/png"); } };
      box.querySelector("[data-a=flip]").onclick = () => {
        const c2 = document.createElement("canvas"); c2.width = v.w; c2.height = v.h;
        const g2 = c2.getContext("2d"); g2.translate(v.w, 0); g2.scale(-1, 1); g2.drawImage(canvas, 0, 0);
        v.src = c2.toDataURL("image/png"); v.ax = 1 - v.ax; v.findAnchor = true;
        this.crewEditor(box, cur, side);
      };
      box.querySelector("[data-a=clear]").onclick = () => { delete cur[side]; this.crewEditor(box, cur, side); };
      box.querySelector("[data-a=auto]").onclick = () => { Object.assign(v, this.crewFindAnchor(canvas, side)); marks(); };
    },

    /* ----- mascots: a buyer and a seller on the chart, cheering or crying with the price ----- */

    mascotKey() { return "aurum.mascots." + this.symbolKey(); },
    mascotList() { try { return JSON.parse(store.get(this.mascotKey()) || "[]"); } catch { return []; } },
    saveMascots(list) { store.set(this.mascotKey(), JSON.stringify(list)); },

    /** A new mascot right of the middle of the chart, standing on the price. */
    addMascot(kind) {
      const bars = this.viewBars();
      if (!bars.length) return;
      const r = this.chart.timeScale().getVisibleLogicalRange();
      const list = this.mascotList();
      // Side by side when there are several; the whole figure inside the chart.
      const at = 0.5 + ((list.length * 0.14) % 0.42);
      const i = r ? Math.max(0, Math.min(bars.length - 1, Math.round(r.from + (r.to - r.from) * at))) : bars.length - 1;
      const size = 120, h = size * 206 / 172, top = h * 0.93 + 8, bottom = 0;
      let y = this.series.priceToCoordinate(bars[bars.length - 1].close);
      const paneH = $("chart").clientHeight - 30;
      y = Math.max(top, Math.min(paneH - 8 - bottom, y == null ? paneH / 2 : y));
      const p = this.series.coordinateToPrice(y);
      const m = { id: Math.random().toString(36).slice(2, 9), kind, t: bars[i].time, p: +(p != null ? p : bars[bars.length - 1].close).toFixed(this.digits), size };
      list.push(m);
      this.saveMascots(list);
      store.set("aurum.mascotsOff", "0");
      this.mascotSel = m.id;
      this.renderMascots();
      toast(`${kind === "girl" ? "Cô gái phe MUA" : "Chàng trai phe BÁN"}: kéo để đặt chỗ, góc dưới để đổi cỡ`);
    },

    mascotMenu(button) {
      const list = this.mascotList(), off = store.get("aurum.mascotsOff") === "1";
      const crewOff = store.get("aurum.crewOff") === "1";
      const items = [["girl", "👧 Thêm cô gái phe MUA (vui khi giá lên)"], ["boy", "👦 Thêm chàng trai phe BÁN (vui khi giá xuống)"],
        ["crew", (crewOff ? "　" : "✓ ") + "🎣 Câu nến / kéo nến theo lệnh có TP"],
        ["crewBig", "➕ Nhân vật câu / kéo to lên"], ["crewSmall", "➖ Nhân vật câu / kéo nhỏ lại"],
        ["crewStyle", CREW.style === "anime" ? "🌑 Câu / kéo kiểu bóng đen viền vàng" : "🎨 Câu / kéo kiểu anime"],
        ["crewPics", "🖼 Dùng ảnh nhân vật của bạn…"]];
      if (list.length) items.push(["toggle", off ? "👁 Hiện nhân vật" : "🙈 Ẩn nhân vật"], ["clear", `🗑 Xoá ${list.length} nhân vật trên mã này`]);
      const r = button.getBoundingClientRect(), menu = $("ctxMenu");
      menu.innerHTML = items.map(([k, t]) => `<button type="button" data-k="${k}">${esc(t)}</button>`).join("");
      menu.hidden = false;
      menu.style.left = Math.min(r.right + 6, window.innerWidth - menu.offsetWidth - 8) + "px";
      menu.style.top = Math.min(r.top, window.innerHeight - menu.offsetHeight - 8) + "px";
      menu.querySelectorAll("button").forEach((b) => (b.onclick = () => {
        this.closeMenu();
        const k = b.dataset.k;
        if (k === "girl" || k === "boy") this.addMascot(k);
        if (k === "toggle") { store.set("aurum.mascotsOff", off ? "0" : "1"); this.renderMascots(); }
        if (k === "crew") { store.set("aurum.crewOff", crewOff ? "0" : "1"); this.crewShown = null; this.placeCrew(); }
        if (k === "crewPics") { this.crewPictureSheet(); return; }
        if (k === "crewStyle") { store.set("aurum.crewStyle", CREW.style === "anime" ? "shadow" : "anime"); this.placeCrew(); }
        if (k === "crewBig" || k === "crewSmall") {
          const size = Math.max(0.3, Math.min(1.4, Math.round((CREW.scale + (k === "crewBig" ? 0.1 : -0.1)) * 10) / 10));
          store.set("aurum.crewScale", String(size));
          toast(`Cỡ nhân vật câu / kéo: ${Math.round(size / 0.6 * 100)}%`);
          this.placeCrew();
        }
        if (k === "clear" && confirm("Xoá các nhân vật trên mã này?")) { this.saveMascots([]); this.renderMascots(); }
        this.renderToolRail();
      }));
    },

    /** The mascots of this symbol as elements over the chart (again when the list or the symbol changes). */
    renderMascots() {
      const box = $("mascots");
      if (!box || !this.chart) return;
      this.mascotSym = this.symbolKey();
      const list = store.get("aurum.mascotsOff") === "1" ? [] : this.mascotList();
      box.innerHTML = list.map((m) => `<div class="mascot${m.id === this.mascotSel ? " sel" : ""}" data-id="${esc(m.id)}">
          <img alt="" draggable="false"><button type="button" class="m-btn m-x" title="Xoá">✕</button>
          <button type="button" class="m-btn m-swap" title="Đổi phe Mua / Bán">⇄</button><i class="m-rs" title="Kéo để đổi cỡ"></i></div>`).join("");
      box.querySelectorAll(".mascot").forEach((el) => this.bindMascot(el));
      this.moods = {};
      this.updateMascotMoods(true);
      this.placeMascots();
    },

    bindMascot(el) {
      const id = el.dataset.id;
      const edit = (f) => { const list = this.mascotList(), m = list.find((x) => x.id === id); if (m) { f(m, list); this.saveMascots(list); } return m; };
      el.querySelector(".m-x").onclick = (e) => { e.stopPropagation(); this.saveMascots(this.mascotList().filter((x) => x.id !== id)); this.renderMascots(); this.renderToolRail(); };
      el.querySelector(".m-swap").onclick = (e) => { e.stopPropagation(); edit((m) => (m.kind = m.kind === "girl" ? "boy" : "girl")); this.renderMascots(); };
      el.addEventListener("pointerdown", (e) => {
        e.stopPropagation();
        if (e.target.closest(".m-btn")) return;
        const resize = !!e.target.closest(".m-rs");
        const m = this.mascotList().find((x) => x.id === id);
        if (!m) return;
        if (this.mascotSel !== id) { this.mascotSel = id; document.querySelectorAll("#mascots .mascot").forEach((x) => x.classList.toggle("sel", x.dataset.id === id)); }
        el.setPointerCapture(e.pointerId);
        const start = { x: e.clientX, y: e.clientY, size: m.size, at: this.mascotXY(m) };
        let moved = null;
        const move = (ev) => {
          const dx = ev.clientX - start.x, dy = ev.clientY - start.y;
          if (resize) { moved = { size: Math.round(Math.max(60, Math.min(280, start.size + dx))) }; m.size = moved.size; }
          else if (start.at) {
            const ts = this.chart.timeScale(), bars = this.viewBars(), sec = TF_SECONDS[this.interval] || 60;
            const l = ts.coordinateToLogical(start.at.x + dx), price = this.series.coordinateToPrice(start.at.y + dy);
            if (l == null || price == null || !bars.length) return;
            moved = { t: indexToTime(bars, l, sec), p: +price.toFixed(this.digits) };
            Object.assign(m, moved);
          }
          this.placeMascot(el, m);
        };
        const up = () => {
          el.removeEventListener("pointermove", move); el.removeEventListener("pointerup", up); el.removeEventListener("pointercancel", up);
          if (moved) edit((x) => Object.assign(x, moved));
        };
        el.addEventListener("pointermove", move); el.addEventListener("pointerup", up); el.addEventListener("pointercancel", up);
      });
    },

    /** Where a mascot's feet are on the chart (pixels), or null off the bars. */
    mascotXY(m) {
      const bars = this.viewBars();
      if (!bars.length) return null;
      const ts = this.chart.timeScale(), sec = TF_SECONDS[this.interval] || 60;
      const l = timeToIndex(bars, m.t, sec);
      if (l == null) return null;
      const i = Math.floor(l), x0 = ts.logicalToCoordinate(i), x1 = ts.logicalToCoordinate(i + 1);
      const y = this.series.priceToCoordinate(m.p);
      if (x0 == null || y == null) return null;
      return { x: x1 == null ? x0 : x0 + (x1 - x0) * (l - i), y };
    },

    placeMascot(el, m) {
      const at = this.mascotXY(m), w = m.size, h = w * 206 / 172;
      if (!at) { el.style.display = "none"; return; }
      el.style.display = "";
      el.style.width = w + "px"; el.style.height = h + "px";
      // The feet stand on the price.
      el.style.transform = `translate(${Math.round(at.x - w / 2)}px, ${Math.round(at.y - h * 0.93)}px)`;
    },

    placeMascotsSoon() {
      // (Nothing to move unless there are mascots, or the symbol changed and its own may come.)
      if (this.mascotRaf || !$("mascots") || (!$("mascots").childElementCount && this.mascotSym === this.symbolKey())) return;
      this.mascotRaf = requestAnimationFrame(() => { this.mascotRaf = 0; this.placeMascots(); });
    },

    placeMascots() {
      const box = $("mascots");
      if (!box || !this.chart) return;
      if (this.mascotSym !== this.symbolKey()) return this.renderMascots();
      box.style.width = this.chart.timeScale().width() + "px";
      const list = this.mascotList();
      box.querySelectorAll(".mascot").forEach((el) => { const m = list.find((x) => x.id === el.dataset.id); if (m) this.placeMascot(el, m); });
    },

    /** The mood of a mascot (girl wants the price up, boy down): your trade just closed, news coming, then the bars. */
    mascotMood(kind) {
      const ev = this.mascotEvent;
      if (ev && Date.now() - ev.at < 25000) return ev.win ? "trophy" : "angry";
      const nowS = Date.now() / 1000;
      if (!this.replay && this.news && this.goldEvents(3).some((e) => e.time > nowS && e.time - nowS < 900)) return "nervous";
      const b = this.viewBars(), n = b.length;
      if (n < 12) return "tea";
      const range = (a) => a.reduce((s, x) => s + x.high - x.low, 0) / a.length;
      const atr = range(b.slice(-40)) || 1;
      const move = ((b[n - 1].close - b[n - 6].close) / atr) * (kind === "girl" ? 1 : -1);
      if (move >= 2.2) return "rich";
      if (move >= 0.6) return "happy";
      if (move <= -2.2) return "shock";
      if (move <= -0.6) return "cry";
      if (n > 40 && range(b.slice(-8)) < atr * 0.4) return "sleep";
      return "tea";
    },

    /** New pictures when a mood changes (held 3 s at least, so a mood does not flicker). */
    updateMascotMoods(now) {
      const box = $("mascots");
      if (!box || !box.childElementCount) return;
      this.moods = this.moods || {};
      const list = this.mascotList();
      box.querySelectorAll(".mascot").forEach((el) => {
        const m = list.find((x) => x.id === el.dataset.id);
        if (!m) return;
        const mood = this.mascotMood(m.kind), was = this.moods[m.id];
        if (was && was.mood === mood && was.kind === m.kind) return;
        if (!now && was && Date.now() - was.at < 3000 && was.kind === m.kind) return;
        this.moods[m.id] = { mood, kind: m.kind, at: Date.now() };
        el.querySelector("img").src = `assets/mascots/${m.kind}-${mood}.svg`;
        el.title = `${m.kind === "girl" ? "Phe MUA" : "Phe BÁN"} · ${MASCOT_MOODS[mood]}`;
      });
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
        + btn("mascot", RAIL_ICON.mascot, "Nhân vật phe Mua / Bán (vui, khóc theo giá)", this.mascotList().length > 0 && store.get("aurum.mascotsOff") !== "1")
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
        if (k === "mascot") { this.mascotMenu(b); return; }
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
            ${opts.template ? `<select data-tpl><option value="">Bản mẫu</option><option value="saveAs">Lưu bản mẫu vẽ dưới dạng…</option><option value="reset">Về kiểu gốc của công cụ</option><option value="save">Đặt làm mặc định cho công cụ</option>${(opts.templateNames ? opts.templateNames() : []).map((n) => `<option value="tpl:${esc(n)}">▦ ${esc(n)}</option>`).join("")}</select>` : ""}
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
      menu.innerHTML = `<button type="button" data-k="saveAs">Lưu bản mẫu vẽ dưới dạng…</button><button type="button" data-k="default">Về kiểu gốc của công cụ</button>`
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

    /** While a tool is picked: the template its next drawing starts with. */
    nextTemplateMenu(button, dr) {
      const tool = dr.tool, names = Object.keys(dr.templates(tool)), next = dr.nextTemplate(tool);
      const r = button.getBoundingClientRect();
      const menu = $("ctxMenu");
      menu.innerHTML = `<div class="muted small" style="padding:4px 10px">Đường vẽ tiếp theo dùng mẫu</div>`
        + names.map((n) => `<button type="button" data-n="${esc(n)}">${n === next ? "✓ " : "　"}${esc(n)}</button>`).join("")
        + `<hr><button type="button" data-n="">${next ? "　" : "✓ "}Kiểu gốc của công cụ</button>`;
      menu.hidden = false;
      menu.style.left = Math.max(8, Math.min(r.left, window.innerWidth - menu.offsetWidth - 8)) + "px";
      menu.style.top = Math.min(r.bottom + 6, window.innerHeight - menu.offsetHeight - 8) + "px";
      menu.querySelectorAll("[data-n]").forEach((b) => (b.onclick = () => {
        this.closeMenu();
        dr.useTemplate(tool, b.dataset.n || null);
        this.renderDrawBar();
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
      // The "Mã so sánh" field is the current chart symbol's own choice (empty: its usual pair).
      if (this.owner && this.ictCfg.smtSymbol !== this.lastSmtSymbol) {
        const main = this.symbol, cmp = (this.ictCfg.smtSymbol || "").trim();
        this.ictCfg.smtFor = Object.assign({}, this.ictCfg.smtFor || {});
        if (cmp) this.ictCfg.smtFor[main] = cmp; else delete this.ictCfg.smtFor[main];
      }
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
      // The "Mã so sánh" field shows this chart symbol's own choice.
      if (this.ictCfg) { this.ictCfg.smtSymbol = (this.ictCfg.smtFor || {})[this.symbol] || ""; this.lastSmtSymbol = this.ictCfg.smtSymbol; }
      const tfOpts = [[1, "1m"], [5, "5m"], [15, "15m"], [30, "30m"], [60, "1h"], [240, "4h"], [1440, "1D"]];
      const styles = [["solid", "———"], ["dashed", "– – –"], ["dotted", "·····"]];
      const render = (tab) => {
        const cfg = this.ictCfg;
        const { chk, tog, numf, sel, selI, sw, color, time, text, head, note } = fieldKit(cfg);
        if (tab === "inputs") {
          return head("Killzones") + tog("showBoxes", "Hiện hộp phiên")
            + cfg.sessions.map((s, i) => `<div class="fr">${chk(`sessions.${i}.on`)}${sw(`sessions.${i}.color`)}${text(`sessions.${i}.name`)}${time(`sessions.${i}.start`)}<span class="to">—</span>${time(`sessions.${i}.end`)}</div>`).join("")
            + head("Pivots") + tog("showPivots", "Hiện điểm pivot (đỉnh/đáy phiên)") + tog("pivotLabels", "Nhãn pivot") + tog("livePivots", "Hiện khi phiên đang chạy")
            + sel("pivotColorMode", "Màu đỉnh / đáy phiên", [["session", "Theo màu phiên"], ["custom", "Màu riêng (bên dưới)"]])
            + color("pivotHighColor", "Màu đỉnh") + color("pivotLowColor", "Màu đáy")
            + sel("levelLabelAlign", "Vị trí chữ trên đường", [["left", "Trái"], ["center", "Giữa"], ["right", "Phải"]])
            + `<div class="fr"><span class="grow">Đường đang chạy kéo tới …</span>${selI("lineEnd", [["near", "Gần nến cuối (gọn)"], ["edge", "Sát bảng giá (cũ)"]])}</div>`
            + numf("lineEndBars", "Qua nến cuối bao nhiêu cây (khi chọn gần nến cuối)")
            + sel("pivotUntilMitigated", "Kéo dài", [[true, "Tới khi giá phá"], [false, "Qua cả khi bị phá"]]) + tog("keepMitigated", "Giữ pivot đã bị phá") + tog("periodUntilBroken", "PDH/PDL, PWH/PWL dừng tại nến cắt qua") + tog("midpoints", "Đường giữa phiên (50%)")
            + cfg.sessions.map((s, i) => `<div class="fr"><span class="grow muted">${esc(s.name)}</span>${text(`sessions.${i}.hi`, "lb")}${text(`sessions.${i}.lo`, "lb")}</div>`).join("")
            + head("Giá mở cửa") + cfg.opens.map((o, i) => `<div class="fr">${chk(`opens.${i}.on`)}${sw(`opens.${i}.color`)}${text(`opens.${i}.label`, "lb")}${time(`opens.${i}.hour`)}</div>`).join("")
            + head("Mốc thời gian (đường dọc)") + cfg.stamps.map((m, i) => `<div class="fr">${chk(`stamps.${i}.on`)}${time(`stamps.${i}.hour`)}</div>`).join("")
            + head("Giờ cắt") + `<div class="fr">${chk("cutoff")}<span class="grow">Dừng các đường lúc</span>${time("cutoffHour")}</div>`
            + head("Đỉnh / đáy ngày") + tog("daily", "Đỉnh / đáy từng ngày") + numf("dailyDays", "Số ngày gần nhất") + tog("dailyKeepTouched", "Giá chạm: dừng lại, nét chấm ……")
            + head("Ngày / Tuần / Tháng") + tog("dwmAlert", "Báo khi giá phá High/Low (PDH/PDL, PWH/PWL, PMH/PML)")
            + cfg.dwm.map((p, i) => `<div class="fr dwm-row">${[["open", `${p.key} Open`], ["hl", "High/Low"], ["mid", "Midline"], ["divider", "Divider"]].map(([f, n]) => `<label class="dwm-c">${chk(`dwm.${i}.${f}`)}<span>${n}</span></label>`).join("")}${sw(`dwm.${i}.color`)}</div>`).join("")
            + `<div class="fr"><span class="grow">Kiểu nét</span>${selI("dwmStyle", styles)}${selI("dwmWidth", [[1, "1"], [2, "2"], [3, "3"]])}</div>`
            + `<div class="fr">${chk("dayOfWeek")}<span class="grow">Nhãn thứ trong tuần</span>${selI("dowPos", [["bottom", "Dưới"], ["top", "Trên"]])}${selI("dowAt", [["midnight", "Nửa đêm"], ["midday", "Giữa trưa"]])}</div>`
            + tog("dowHideWeekend", "Ẩn nhãn T7 / CN")
            + `<div class="fr">${chk("nextDay")}<span class="grow">Đường dọc bắt đầu ngày hôm sau (giờ VN, đếm ngược)</span>${sw("nextDayColor")}</div>`
            + tog("dayOpenLines", "Giữ đường dọc ở mỗi lần mở nến ngày (ngày/tháng + giờ VN)")
            + note("Open: giá mở ngày (DO) / tuần (WO) / tháng (MO) hiện tại. High/Low: đỉnh – đáy của ngày / tuần / tháng trước (PDH–PDL, PWH–PWL, PMH–PML). Midline: giữa của chúng (PDM, PWM, PMM). Divider: vạch dọc nơi mỗi ngày / tuần / tháng bắt đầu. Ngày tính theo múi giờ ở tab Hiển thị (ICT: 0h New York). Hiện ở mọi khung nhỏ hơn kỳ đó.")
            + head("FVG đầu tuần (M1, thứ 2)") + tog("weekFvg", "FVG M1 đầu tiên của thứ 2 sau giờ bên dưới, kẻ tới hết tuần")
            + `<div class="fr"><span class="grow">Tính từ</span>${time("weekFvgHour")}${selI("weekFvgZone", [["America/New_York", "Giờ New York"], ["Asia/Ho_Chi_Minh", "Giờ Việt Nam"]])}</div>`
            + numf("weekFvgWeeks", "Số tuần gần nhất")
            + note("Mỗi tuần lấy FVG đầu tiên trên khung M1 hình thành trong ngày thứ 2 từ giờ đã chọn (mặc định 9:30 sáng New York, tức 21:30 giờ VN mùa đông / 20:30 mùa hè; New York tự đổi giờ mùa hè), 3 cây nến M1 tạo FVG đều từ giờ đó và cùng ngày thứ 2, dù chart đang ở khung nào; vùng kéo ngang tới hết tuần để xem giá phản ứng. Đường giữa là 50% của FVG. Nến M1 lấy từ máy chủ MT5 (hoặc Binance).")
            + head("FVG & VI") + tog("fvg", "Hiện FVG")
            + sel("fvgMode", "FVG kéo tới", [["ifvg", "Nến hiện tại · nến đóng phá qua → IFVG"], ["touch", "Lần chạm đầu (cũ)"]]) + tog("fvgStrong", "Chỉ FVG mạnh (lọc FVG yếu)") + numf("fvgDisplacement", "Nến tạo FVG ≥ × thân TB", 0.1)
            + tog("fvgConfluence", "Tô nền khi trùng FVG khung lớn") + tog("fvgMid", "Đường giữa 50%") + tog("fvgHideFilled", "Ẩn FVG đã bị chạm")
            + numf("gapKeep", "Chạm rồi bật ngược: giữ (phút)") + numf("fvgMinSize", "Lọc FVG nhỏ (× biên độ nến)", 0.1) + numf("fvgCount", "Giữ FVG gần nhất")
            + tog("vi", "Hiện VI (Volume Imbalance)") + numf("viCount", "Giữ VI gần nhất") + tog("viKeep", "Giữ VI khi nến chạm / xuyên qua (dừng tại cây đó)") + tog("viHideTouched", "Ẩn VI đã bị chạm")
            + head("Cấu trúc") + tog("mss", "MSS (đổi cấu trúc)") + tog("bos", "BOS (phá cấu trúc cùng xu hướng)") + numf("swing", "Swing: số nến mỗi bên") + numf("structureCount", "Giữ số lần phá gần nhất")
            + head("Thanh khoản") + tog("sweeps", "Quét thanh khoản") + numf("sweepCount", "Giữ số lần quét gần nhất")
            + head("DM (nến mạnh không râu)") + `<label class="fr"><input type="checkbox" data-dm ${showInd.dm ? "checked" : ""}><span>Hiện DM</span></label>`
            + numf("dmBody", "Nến khoẻ: thân ≥ × ATR(14) (0 = mọi cây)", 0.1) + numf("dmWick", "Coi là không râu khi râu ≤ % cả cây (0 = không râu)", 0.5)
            + numf("dmCount", "Số đường DM gần nhất") + tog("dmUntilBroken", "Dừng đường ở nến cắt qua (tắt = kéo tới nến hiện tại)")
            + head("SMT") + `<label class="fr"><input type="checkbox" data-smt ${showInd.smt ? "checked" : ""}><span>Hiện SMT khi mở 2 biểu đồ (nút ▥)</span></label>`
            + (this.owner ? `<div class="fr"><span class="grow">Mã so sánh</span>${text("smtSymbol", "lb")}<span class="muted small">riêng cho ${esc(this.symbol || "")} · trống = tự động (${esc(smtPair(this.symbol) || "—")})</span></div>` : "")
            + note("SMT so đỉnh với đỉnh, đáy với đáy của 2 mã. Mã chạy ngược chiều (DXY) được tự nhận biết: khi đó đỉnh vàng so với đáy DXY.") + numf("smtSwing", "Swing: số nến mỗi bên (lớn hơn = ít SMT, chỉ đỉnh/đáy chính)") + numf("smtLookback", "Hai đỉnh/đáy cách tối đa (nến)") + numf("smtCount", "Giữ SMT gần nhất")
            + head("Macros") + tog("macros", "Hiện macros")
            + cfg.macroList.map((m, i) => `<div class="fr">${chk(`macroList.${i}.on`)}${sw(`macroList.${i}.color`)}${text(`macroList.${i}.name`)}${time(`macroList.${i}.start`)}<span class="to">—</span>${time(`macroList.${i}.end`)}</div>`).join("")
            + sel("macroStyle", "Kiểu", [["bar", "Thanh ngang (gọn)"], ["box", "Hộp chấm quanh nến"]])
            + sel("macroBarPos", "Vị trí thanh", [["bottom", "Dưới đáy chart"], ["top", "Trên đỉnh chart"], ["high", "Trên đỉnh khung macro"]])
            + numf("macroBarHeight", "Độ dày thanh (px)") + numf("macroBarOpacity", "Độ đậm thanh (%)", 5);
        }
        if (tab === "style") {
          return head("Hộp phiên") + tog("boxLabels", "Tên phiên trên hộp") + tog("boxBorder", "Viền hộp") + numf("boxOpacity", "Độ đậm nền (%)")
            + head("Đường") + sel("lineScale", "Độ dày chung", [[0.5, "0.5px"], [0.75, "Mảnh"], [1, "Vừa"], [1.5, "Dày"], [2, "Rất dày"]]) + numf("pivotWidth", "Độ dày pivot", 0.5)
            + sel("pivotStyle", "Nét pivot", styles) + sel("mitigatedStyle", "Nét pivot đã bị phá", styles) + sel("openStyle", "Nét giá mở cửa", styles)
            + color("stampColor", "Màu mốc thời gian") + sel("stampStyle", "Nét mốc thời gian", styles)
            + head("Đỉnh / đáy ngày") + color("dayHighColor", "Màu đỉnh ngày") + color("dayLowColor", "Màu đáy ngày") + sel("dailyStyle", "Nét", styles) + sel("dailyLabelAlign", "Vị trí chữ đỉnh/đáy thứ", [["left", "Trái"], ["center", "Giữa"], ["right", "Phải"]])
            + head("FVG & VI") + color("fvgBull", "FVG tăng") + color("fvgBear", "FVG giảm") + color("fvgZone", "Nền FVG trùng khung") + color("fvgZoneMid", "Đường giữa FVG trùng khung") + color("viColor", "VI")
            + head("SMT") + color("smtBull", "SMT tăng") + color("smtBear", "SMT giảm")
            + head("FVG đầu tuần") + color("weekFvgColor", "Màu vùng FVG thứ 2")
            + head("Khác") + color("mssBull", "MSS tăng") + color("mssBear", "MSS giảm") + color("sweepColor", "Quét thanh khoản")
            + head("DM") + color("dmLineColor", "Màu đường") + color("dmTextColor", "Màu chữ") + sel("dmStyle", "Nét", styles)
            + sel("dmWidth", "Độ dày", [[1, "1px"], [2, "2px"], [3, "3px"]]);
        }
        return head("Chung") + sel("timeZone", "Múi giờ", [["America/New_York", "New York (ICT)"], ["UTC", "UTC"], ["Asia/Ho_Chi_Minh", "Hà Nội (UTC+7)"], ["Europe/London", "London"]])
          + sel("tfLimit", "Killzones trên khung ≤", tfOpts.slice(0, 6)) + numf("maxDays", "Số ngày hiển thị")
          + note("Giờ các phiên theo múi giờ ở trên (ICT dùng giờ New York).")
          + head("FVG") + `<div class="fr"><span class="grow">Từ khung</span>${selI("fvgFrom", tfOpts)}<span class="to">→</span>${selI("fvgTo", tfOpts)}</div>`
          + head("Macros") + sel("macroTfLimit", "Trên khung ≤", tfOpts.slice(0, 4)) + sel("macroTimeLabels", "Nhãn hộp", [[true, "Giờ"], [false, "Tên"]])
          + head("Khác") + tog("rangeTable", "Bảng biên độ phiên") + numf("rangeAvg", "Trung bình số phiên");
      };
      const open = () => this.openPanel("ICT Killzones + Pivots", [["inputs", "Các đầu vào"], ["style", "Định dạng"], ["view", "Hiển thị"]], render, {
        root: this.ictCfg,
        onChange: () => this.saveIct(),
        afterDraw: (panel) => {
          const box = panel.querySelector("[data-smt]");
          if (box) box.onchange = () => { showInd.smt = box.checked; store.set("aurum.ind", JSON.stringify(showInd)); this.loadCmp(); };
          const dm = panel.querySelector("[data-dm]");
          if (dm) dm.onchange = () => { showInd.dm = dm.checked; store.set("aurum.ind", JSON.stringify(showInd)); this.computeICT(); this.redraw(); };
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
          <div class="fr">${k.chk("pop")}<span class="grow">Nến, đường chỉ báo và bản vẽ nổi bật (tự tăng tương phản với nền)</span></div>
          <div class="fp-sec">Nền và lưới</div>
          <div class="fr"><span class="grow">Hình nền</span><select data-p="bgType" data-t="str" data-redraw>${[["theme", "Theo giao diện"], ["solid", "Solid (một màu)"], ["gradient", "Gradient"], ["image", "Ảnh"]].map(([v, n]) => `<option value="${v}" ${st.bgType === v ? "selected" : ""}>${n}</option>`).join("")}</select>
            ${st.bgType === "solid" || st.bgType === "gradient" || st.bgType === "image" ? k.sw("bg") : ""}${st.bgType === "gradient" ? k.sw("bg2") : ""}</div>
          ${st.bgType === "image" ? `<div class="fr"><span class="grow">Ảnh nền</span><label class="btn btn-ghost btn-small bg-pick">${store.get("aurum.chartBgImg") ? "Đổi ảnh…" : "Chọn ảnh…"}<input type="file" accept="image/*" data-bgimg hidden></label>${store.get("aurum.chartBgImg") ? '<button type="button" class="btn btn-ghost btn-small" data-bgdel>Xoá ảnh</button>' : ""}</div>
            <div class="fr"><span class="grow">Độ rõ của ảnh</span><input type="range" min="5" max="100" step="5" data-p="bgImgOpacity" data-t="num" value="${st.bgImgOpacity}" class="op"><span class="op-v">${st.bgImgOpacity}%</span></div>
            <p class="fp-note">Ảnh phủ kín chart, nằm dưới nến. Kéo thanh để ảnh mờ hơn hoặc rõ hơn; ô màu là màu lót dưới ảnh.</p>` : ""}
          <div class="fr">${k.chk("vGrid")}<span class="grow">Lưới dọc</span>${k.sw("grid")}</div>
          <div class="fr">${k.chk("hGrid")}<span>Lưới ngang</span></div>
          <div class="fr">${k.chk("crosshairMagnet")}<span>Con trỏ bắt vào nến</span></div>
          <div class="fr">${k.chk("tfRing")}<span class="grow">Bấm 1 lần vào chart: hiện vòng chọn khung thời gian</span>${k.sw("ringColor")}</div>
          <div class="fr">${k.chk("seconds")}<span>Hiện giây trên trục thời gian</span></div>
          <div class="fp-sec">Giá</div>
          <div class="fr">${k.chk("askLine")}<span class="grow">Đường Bid / Ask (spread)</span>${k.sw("bidColor")}${k.sw("askColor")}</div>`;
      };
      this.openPanel("Cài đặt biểu đồ", [["look", "Giao diện"]], render, {
        root: st,
        onChange: () => { this.saveChartStyle(); const v = $("floatPanel").querySelector(".op-v"); if (v) v.textContent = `${st.bgImgOpacity}%`; },
        onReset: (redraw) => { this.chartStyle = defaultChartStyle(); this.saveChartStyle(); this.chartStyleSheet(); void redraw; },
        afterDraw: (panel) => {
          const file = panel.querySelector("[data-bgimg]"), del = panel.querySelector("[data-bgdel]");
          if (file) file.onchange = () => { const f = file.files && file.files[0]; if (f) this.setChartBgImage(f); };
          if (del) del.onclick = () => { store.set("aurum.chartBgImg", null); this.applyChartStyle(); if (this.panelDraw) this.panelDraw(); };
        },
      });
    },

    /** A picture for the chart background: made at most 1920 px wide (JPEG) so it keeps in the browser's storage. */
    setChartBgImage(file) {
      const reader = new FileReader();
      reader.onload = () => {
        const img = new Image();
        img.onload = () => {
          const k = Math.min(1, 1920 / Math.max(img.width, img.height));
          const c = document.createElement("canvas");
          c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
          c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
          let url = c.toDataURL("image/jpeg", 0.85);
          try { store.set("aurum.chartBgImg", url); } catch {
            url = c.toDataURL("image/jpeg", 0.6);
            try { store.set("aurum.chartBgImg", url); } catch { return toast("Ảnh quá lớn, chọn ảnh nhỏ hơn", true); }
          }
          this.applyChartStyle();
          if (this.panelDraw) this.panelDraw();
        };
        img.onerror = () => toast("Không đọc được ảnh", true);
        img.src = reader.result;
      };
      reader.readAsDataURL(file);
    },

    /** The picture under every chart of the page (behind the see-through chart), at the chosen strength. */
    applyChartBgImage(on, base) {
      const url = on ? store.get("aurum.chartBgImg") : null;
      document.querySelectorAll(".chart-wrap").forEach((wrap) => {
        let el = wrap.querySelector(":scope > .chart-bg-img");
        if (!url) { if (el) el.remove(); wrap.style.backgroundColor = ""; return; }
        if (!el) { el = document.createElement("div"); el.className = "chart-bg-img"; wrap.insertBefore(el, wrap.firstChild); }
        if (el.dataset.src !== String(url.length)) { el.style.backgroundImage = `url("${url}")`; el.dataset.src = String(url.length); }
        el.style.opacity = String(Math.max(0.05, Math.min(1, (this.chartStyle.bgImgOpacity ?? 35) / 100)));
        wrap.style.backgroundColor = base;
      });
    },

    saveChartStyle() {
      store.set("aurum.chartStyle", JSON.stringify(this.chartStyle));
      applyTheme(this.chartStyle.theme);
      this.applyChartStyle();
    },

    /* ----- chart type (TradingView's menu): bars, candles, hollow, volume candles, line, line with markers, steps ----- */

    chartTypes() {
      const ic = (d) => `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
      return [
        ["bars", "Thanh", ic('<path d="M7 4v15M4 8h3M7 15h3M16 6v14M13 10h3M16 17h3"/>')],
        ["candles", "Biểu đồ nến", ic('<path d="M8 3v3M8 17v4M16 5v3M16 15v5"/><rect x="5.5" y="6" width="5" height="11" rx="1" fill="currentColor"/><rect x="13.5" y="8" width="5" height="7" rx="1"/>')],
        ["hollow", "Biểu đồ nến rỗng", ic('<path d="M8 3v3M8 17v4M16 5v3M16 15v5"/><rect x="5.5" y="6" width="5" height="11" rx="1"/><rect x="13.5" y="8" width="5" height="7" rx="1"/><path d="M7.5 9v5"/>')],
        ["volume", "Nến khối lượng", ic('<path d="M8 3v3M8 18v3M16 6v3M16 15v4"/><rect x="4.5" y="6" width="7" height="12" rx="1"/><rect x="14" y="9" width="4" height="6" rx="1"/>')],
        ["line", "Đường", ic('<path d="M3 17l5-6 4 3 4-6 5 4"/>')],
        ["markers", "Biểu đồ có điểm đánh dấu", ic('<path d="M3 17l5-6 4 3 4-6 5 4"/><circle cx="8" cy="11" r="1.6" fill="currentColor"/><circle cx="12" cy="14" r="1.6" fill="currentColor"/><circle cx="16" cy="8" r="1.6" fill="currentColor"/>')],
        ["steps", "Biểu đồ đường bậc", ic('<path d="M3 18h4v-5h5v-5h4v4h5"/>')],
      ];
    },
    chartType() { const t = store.get("aurum.chartType"); return this.chartTypes().some(([k]) => k === t) ? t : "candles"; },

    /** The chosen type: candles and hollow on the candle series itself; the others in a series of their own
     *  over it, the candles left see-through (they keep the price scale, the indicators and drawings). */
    applyChartType() {
      if (!this.chart || !this.series) return;
      const type = this.chartType(), st = this.chartStyle || {}, look = this.look || {};
      const up = (look.up || st.up || "#14b88a").slice(0, 7), down = (look.down || st.down || "#f0455a").slice(0, 7);
      const clear = "rgba(0,0,0,0)";
      if (this.altSeries && this.altType !== type) { try { this.chart.removeSeries(this.altSeries); } catch { /* gone */ } this.altSeries = null; }
      this.altType = type;
      if (type === "candles") return;
      if (type === "hollow") {
        this.series.applyOptions({ upColor: clear, borderVisible: true, borderUpColor: up, wickUpColor: up, downColor: down, borderDownColor: down, wickDownColor: down });
        return;
      }
      // The candles hidden, their last-price label kept.
      this.series.applyOptions({ upColor: clear, downColor: clear, borderVisible: false, wickVisible: false });
      const common = { lastValueVisible: false, priceLineVisible: false, crosshairMarkerVisible: type !== "bars" && type !== "volume" };
      if (!this.altSeries) {
        if (type === "bars") this.altSeries = this.chart.addBarSeries(Object.assign({ upColor: up, downColor: down, thinBars: false, openVisible: true }, common));
        else if (type === "volume") this.altSeries = this.chart.addCandlestickSeries(Object.assign({ upColor: up, downColor: down, borderVisible: false, wickUpColor: up, wickDownColor: down }, common));
        else this.altSeries = this.chart.addLineSeries(Object.assign({ color: st.lineColor || "#2962ff", lineWidth: 2, lineType: type === "steps" ? 1 : 0,
          pointMarkersVisible: type === "markers", pointMarkersRadius: 2.5 }, common));
      } else if (type === "bars") this.altSeries.applyOptions({ upColor: up, downColor: down });
      this.altSet(this.series.data ? this.series.data() : this.viewBars().map(shown));
    },

    /** A bar as the chosen type's series takes it: OHLC, or the close for the lines; volume candles weighted
     *  by their volume against the average (stronger colour, wider look). */
    altPoint(b) {
      const t = this.altType;
      if (t === "line" || t === "markers" || t === "steps") return { time: b.time, value: b.close };
      if (t === "volume") {
        const avg = this.altAvgVol || 0, k = avg > 0 && b.volume ? Math.min(1, 0.25 + 0.75 * (b.volume / (avg * 2))) : 0.6;
        const st = Object.assign({}, this.chartStyle, this.look), base = (b.close >= b.open ? st.up || "#14b88a" : st.down || "#f0455a").slice(0, 7);
        const c = base + Math.round(k * 255).toString(16).padStart(2, "0");
        return { time: b.time, open: b.open, high: b.high, low: b.low, close: b.close, color: c, borderColor: c, wickColor: base };
      }
      return { time: b.time, open: b.open, high: b.high, low: b.low, close: b.close };
    },
    altSet(data) {
      if (!this.altSeries || !data) return;
      if (this.altType === "volume") { const v = data.filter((b) => b.volume > 0); this.altAvgVol = v.length ? v.reduce((a, b) => a + b.volume, 0) / v.length : 0; }
      try { this.altSeries.setData(data.map((b) => this.altPoint(b))); } catch { /* not ready */ }
    },
    altUpdate(bar) {
      if (!this.altSeries || !bar) return;
      try { this.altSeries.update(this.altPoint(bar)); } catch { /* older bar */ }
    },

    /** TradingView's chart type menu, under its button. */
    chartTypeMenu(anchor) {
      const menu = $("ctxMenu"), cur = this.chartType();
      menu.innerHTML = `<div class="db-list type-list">${this.chartTypes().map(([k, name, icon], i) => `${i === 4 ? '<div class="type-sep"></div>' : ""}<button type="button" data-t="${k}" class="${k === cur ? "on" : ""}">${icon}<span>${name}</span></button>`).join("")}</div>`;
      menu.classList.add("db-menu");
      menu.hidden = false;
      const r = anchor.getBoundingClientRect();
      menu.style.left = Math.max(8, Math.min(r.left, window.innerWidth - menu.offsetWidth - 8)) + "px";
      menu.style.top = Math.min(r.bottom + 8, window.innerHeight - menu.offsetHeight - 8) + "px";
      menu.querySelectorAll("[data-t]").forEach((b) => (b.onclick = () => {
        store.set("aurum.chartType", b.dataset.t);
        this.closeMenu();
        this.applyChartStyle();
        this.renderTypeBtn();
      }));
    },
    renderTypeBtn() {
      const btn = $("typeBtn");
      if (!btn) return;
      const t = this.chartTypes().find(([k]) => k === this.chartType());
      btn.innerHTML = t[2];
      btn.title = "Kiểu biểu đồ: " + t[1];
    },

    applyChartStyle() {
      if (!this.chart) return;
      if (!this.axisFontAsked && document.fonts && document.fonts.load) {
        this.axisFontAsked = true;
        document.fonts.load("13px AurumAxis").then(() => this.applyChartStyle()).catch(() => {});
      }
      const st = this.chartStyle, light = document.documentElement.dataset.theme === "light";
      const themeBg = light ? "#ffffff" : "#050506", type = st.bgType || (st.customBg ? "solid" : "theme");
      const bg = type === "theme" ? themeBg : st.bg;
      const image = type === "image" && !!store.get("aurum.chartBgImg");
      // What the chart's own canvas paints: a colour, a gradient, or nothing over the picture.
      const paint = type === "gradient" ? { type: "gradient", topColor: st.bg, bottomColor: st.bg2 || st.bg }
        : image ? { type: "solid", color: "rgba(0,0,0,0)" } : { type: "solid", color: bg };
      const layoutOf = () => Object.assign(axisFont(bg, light), { background: paint });
      this.applyChartBgImage(image, bg);
      // The default grid: faint grey on the black chart, light on the white one.
      const grid = st.grid === "#1a2233" ? (light ? "#eef0f4" : "#141417") : st.grid;
      this.chart.applyOptions({
        layout: layoutOf(),
        grid: { vertLines: { color: grid, visible: st.vGrid }, horzLines: { color: grid, visible: st.hGrid } },
        rightPriceScale: { borderColor: light ? "#d6dae1" : "#1e1e23" },
        timeScale: { borderColor: light ? "#d6dae1" : "#1e1e23", secondsVisible: st.seconds || isSecTF(this.interval) },
        crosshair: { mode: st.crosshairMagnet ? 1 : 0 },
      });
      const look = this.look = candleLook(st, bg);
      if (POP.on !== !!st.pop || POP.bg !== bg) {
        POP.on = !!st.pop; POP.bg = bg; POP.cache.clear();
        if (this.studySeries && this.studies) try { this.applyStudies(); } catch { /* not ready */ }
        if (this.drawings && this.drawings.requestUpdate) this.drawings.requestUpdate();
        if (this.drawings2 && this.drawings2.requestUpdate) this.drawings2.requestUpdate();
      }
      const candles = {
        upColor: look.up, downColor: look.down, wickUpColor: look.wickUp, wickDownColor: look.wickDown, wickVisible: true,
        borderVisible: look.border, borderUpColor: look.borderUp, borderDownColor: look.borderDown,
      };
      this.series.applyOptions(candles);
      this.applyChartType();
      if (this.chart2) {
        this.chart2.applyOptions({
          layout: layoutOf(),
          grid: { vertLines: { color: grid, visible: st.vGrid }, horzLines: { color: grid, visible: st.hGrid } },
          rightPriceScale: { borderColor: light ? "#d6dae1" : "#1e1e23" }, timeScale: { borderColor: light ? "#d6dae1" : "#1e1e23" },
        });
        this.series2.applyOptions(candles);
      }
      (this.panes || []).forEach((p) => {
        p.chart.applyOptions({
          layout: layoutOf(),
          grid: { vertLines: { color: grid, visible: st.vGrid }, horzLines: { color: grid, visible: st.hGrid } },
          rightPriceScale: { borderColor: light ? "#d6dae1" : "#1e1e23" }, timeScale: { borderColor: light ? "#d6dae1" : "#1e1e23" },
        });
        p.series.applyOptions(candles);
      });
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
      // Floats over the whole page (it can sit outside the chart), shown on the chart tab only.
      bar.hidden = !fav.length || this.tab !== "chart";
      if (bar.hidden) return;
      if (bar.parentElement !== document.body) document.body.appendChild(bar);
      bar.classList.add("floating");
      const d = this.drawings;
      bar.innerHTML = `<span class="grip" title="Kéo để di chuyển"><i></i><i></i><i></i><i></i><i></i><i></i></span><span class="fav-sep"></span>` + fav.map((t) => `<button type="button" data-t="${t}" class="${d.tool === t ? "on" : ""}" data-tip="${esc(window.AurumDrawings.tools[t].name)}" aria-label="${esc(window.AurumDrawings.tools[t].name)}">${TOOL_ICON[t] || ""}</button>`).join("");
      bar.querySelectorAll("button").forEach((b) => (b.onclick = (e) => { e.stopPropagation(); d.setTool(d.tool === b.dataset.t ? null : b.dataset.t); }));
      // Where it was left, as a share of the window (kept on resize); at first over the top of the chart.
      let pos = null;
      try { pos = JSON.parse(store.get("aurum.favPos2") || "null"); } catch { /* default */ }
      const place = () => {
        const w = bar.offsetWidth || 300, h = bar.offsetHeight || 40;
        let x, y;
        if (pos) { x = pos.x * window.innerWidth; y = pos.y * window.innerHeight; } else {
          const c = $("chartWrap").getBoundingClientRect();
          x = c.left + (c.width - w) / 2; y = c.top + 52;
        }
        bar.style.left = Math.max(4, Math.min(window.innerWidth - w - 4, x)) + "px";
        bar.style.top = Math.max(4, Math.min(window.innerHeight - h - 4, y)) + "px";
      };
      place();
      if (!this.favResizeBound) { this.favResizeBound = true; window.addEventListener("resize", () => this.renderFavBar()); }
      bar.querySelector(".grip").onpointerdown = (e) => {
        e.preventDefault(); e.stopPropagation();
        const r = bar.getBoundingClientRect(), dx = e.clientX - r.left, dy = e.clientY - r.top;
        bar.classList.add("dragging");
        const move = (ev) => {
          ev.preventDefault();
          bar.style.left = Math.max(4, Math.min(window.innerWidth - r.width - 4, ev.clientX - dx)) + "px";
          bar.style.top = Math.max(4, Math.min(window.innerHeight - r.height - 4, ev.clientY - dy)) + "px";
        };
        const up = () => {
          window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); window.removeEventListener("pointercancel", up);
          bar.classList.remove("dragging");
          const b = bar.getBoundingClientRect();
          pos = { x: b.left / window.innerWidth, y: b.top / window.innerHeight };
          store.set("aurum.favPos2", JSON.stringify(pos));
        };
        window.addEventListener("pointermove", move); window.addEventListener("pointerup", up); window.addEventListener("pointercancel", up);
      };
      // A double tap on the grip puts it back over the chart.
      bar.querySelector(".grip").ondblclick = () => { store.set("aurum.favPos2", null); this.renderFavBar(); };
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
          if (o.kind !== "hist") list[i].applyOptions({ color: popColor(o.color, false) });
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

    /* ----- Kế hoạch giao dịch (plan.js) ----- */

    /** x of any time on this chart (between bars, or past the last one). */
    timeX(t) {
      const b = this.viewBars(), n = b.length, ts = this.chart.timeScale();
      if (!n) return null;
      let sec = Infinity;
      for (let i = Math.max(1, n - 20); i < n; i++) sec = Math.min(sec, b[i].time - b[i - 1].time);
      if (!isFinite(sec) || sec <= 0) sec = 60;
      let l;
      if (t >= b[n - 1].time) l = n - 1 + (t - b[n - 1].time) / sec;
      else if (t <= b[0].time) l = (t - b[0].time) / sec;
      else {
        let lo = 0, hi = n - 1;
        while (hi - lo > 1) { const m = (lo + hi) >> 1; if (b[m].time <= t) lo = m; else hi = m; }
        l = lo + Math.min(1, (t - b[lo].time) / sec);
      }
      const i = Math.floor(l), a = ts.logicalToCoordinate(i), c = ts.logicalToCoordinate(i + 1);
      return a == null || c == null ? a : a + (c - a) * (l - i);
    },

    /** 1-minute bars of each Monday 09:30–15:30 (VN) of the weeks on the chart, for "FVG đầu tuần" (the first
     *  M1 FVG after 09:30) on any timeframe: from the VPS (MT5) or Binance, fetched once per Monday (the
     *  running Monday again every minute until its gap is there). Cut at the chart's last bar (replay). */
    mondayM1(bars) {
      const cfg = this.ictCfg;
      if (!cfg || !cfg.weekFvg || !bars || !bars.length || !showInd.killzones) return null;
      const key = this.symbolKey();
      if (!this.wfM1 || this.wfM1.key !== key) this.wfM1 = { key, days: new Map() };
      const store1 = this.wfM1, now = Date.now() / 1000;
      const zone = cfg.weekFvgZone || "America/New_York", hour = cfg.weekFvgHour != null ? +cfg.weekFvgHour : 9.5;
      const off = (t) => window.ICT.offsetSeconds(t, zone);
      const first = bars[0].time, last = bars[bars.length - 1].time;
      let d = Math.floor((last + off(last)) / 86400);
      while ((d + 4) % 7 !== 1) d--;
      const want = [];
      for (let k = 0; k < Math.max(1, cfg.weekFvgWeeks || 1); k++, d -= 7) {
        // That Monday's start time there, in UTC (the zone's offset on that day, summer time included).
        const guess = d * 86400 + hour * 3600;
        const open = guess - off(guess - off(guess));
        if (open + 6 * 3600 < first) break;
        want.push(open);
      }
      want.forEach((open) => {
        const got = store1.days.get(open);
        const running = now < open + 6 * 3600;
        if (got && (got.busy || !running || now - got.at < 60)) return;
        if (now < open) return;
        const entry = { busy: true, at: now, bars: got ? got.bars : [] };
        store1.days.set(open, entry);
        this.fetchM1(open, open + 6 * 3600).then((list) => {
          entry.bars = list || entry.bars; entry.busy = false; entry.at = Date.now() / 1000;
          if (this.wfM1 === store1 && list && list.length) this.computeICT();
        }).catch(() => { entry.busy = false; });
      });
      const upTo = last + TF_SECONDS[this.interval];
      return want.slice().reverse().flatMap((open) => (store1.days.get(open) || { bars: [] }).bars).filter((b) => b.time < upTo);
    },

    /** 1-minute bars from `from` to `to` (UTC seconds) of the chart's symbol. */
    async fetchM1(from, to) {
      const count = Math.ceil((to - from) / 60) + 5;
      if (this.source === "exness") {
        const path = this.owner ? `/mt5/candles?symbol=${encodeURIComponent(this.symbol)}&interval=1m&count=${count}&before=${to}` : `/member/candles?interval=1m&count=${count}&before=${to}`;
        const data = await this.call(path);
        return this.toBars(data.candles || []).filter((b) => b.time >= from && b.time < to);
      }
      const market = binanceMarket(this.symbol);
      if (!market) return [];
      const rest = market.futures ? "https://fapi.binance.com/fapi/v1/klines" : "https://api.binance.com/api/v3/klines";
      const rows = await (await fetch(`${rest}?symbol=${market.name}&interval=1m&startTime=${from * 1000}&endTime=${to * 1000 - 1}&limit=${Math.min(1000, count)}`)).json();
      return Array.isArray(rows) ? rows.map((r) => ({ time: r[0] / 1000, open: +r[1], high: +r[2], low: +r[3], close: +r[4], volume: +r[5] })) : [];
    },

    /** Day, H4 and H1 candles of the chart's symbol (for the plan), from the VPS; again after a minute. */
    async loadHtf() {
      const key = this.symbolKey();
      if (this.htfLoading || (this.htfData && this.htfData.key === key && Date.now() - this.htfData.at < 60000)) return;
      this.htfLoading = true;
      try {
        const get = async (interval, count) => {
          const path = this.owner ? `/mt5/candles?symbol=${encodeURIComponent(this.symbol)}&interval=${interval}&count=${count}` : `/member/candles?interval=${interval}&count=${count}`;
          const data = await this.call(path);
          return this.toBars(data.candles || []);
        };
        const [d1, h4, h1] = await Promise.all([get("1d", 30), get("4h", 180), get("1h", 500)]);
        this.htfData = { key, at: Date.now(), d1, h4, h1 };
        this.computeICT();
      } catch { this.htfData = { key, at: Date.now(), d1: [], h4: [], h1: [] }; }
      finally { this.htfLoading = false; }
    },

    planFor(bars, sec, digits) {
      if (!showInd.plan || !window.PLAN || !this.planCfg || !bars.length || !sec || sec >= 86400) return null;
      try {
        // The day / H4 / H1 candles as known at the last bar (a replay must not see later ones).
        return window.PLAN.compute(bars, sec, this.planCfg, { ...this.htfCtx(bars, sec), fmt: (v) => fmt(v, digits) });
      } catch { return null; }
    },

    /** The day / H4 / H1 candles for the plan and the liquidity zones, as known at the last bar. */
    htfCtx(bars, sec) {
      if (this.source === "exness" && (!this.htfData || this.htfData.key !== this.symbolKey() || Date.now() - this.htfData.at > 60000)) this.loadHtf();
      const h = this.htfData && this.htfData.key === this.symbolKey() ? this.htfData : {};
      const upTo = bars[bars.length - 1].time + sec, cut = (list) => (list || []).filter((c) => c.time < upTo);
      return { d1: cut(h.d1), h4: cut(h.h4), h1: cut(h.h1) };
    },

    liqFor(bars, sec, digits) {
      if (!showInd.liq || !window.LIQ || !this.liqCfg || !bars.length || !sec || sec >= 86400) return null;
      try { return window.LIQ.compute(bars, sec, this.liqCfg, { ...this.htfCtx(bars, sec), fmt: (v) => fmt(v, digits) }); } catch { return null; }
    },

    /** The macro windows for these bars. */
    macroFor(bars, sec) {
      if (!showInd.macro || !window.MACRO || !this.macroCfg || !bars.length || !sec) return null;
      try { return window.MACRO.compute(bars, sec, this.macroCfg); } catch { return null; }
    },

    macroSettingsSheet() {
      if (!window.MACRO) return;
      sheet.close();
      const render = () => {
        const { tog, color, head, note } = fieldKit(this.macroCfg);
        return `<label class="toggle"><span>Bật Macro</span><span class="switch"><input type="checkbox" data-macro ${showInd.macro ? "checked" : ""}><span></span></span></label>`
          + note("Mỗi phiên một khung quan trọng nhất, đo trên nến 1m vàng từ 28/1 đến 6/11/2026 (biên độ nến 5 phút so với trung vị của ngày, % ngày có nến ≥ 2×). Khung tính theo giờ của sàn tạo ra nó nên giờ VN tự lệch 1 tiếng khi Mỹ / Anh đổi giờ. Đếm ngược ở giữa phía trên chart.")
          + `<div class="list">${window.MACRO.WINDOWS.map((w) => `<div class="row"><span class="grow">${esc(w.name)} <span class="muted small">(${w.from}–${w.to} ${w.tz === "Asia/Ho_Chi_Minh" ? "giờ VN" : w.tz === "Europe/London" ? "giờ London" : "giờ New York"})</span></span><span class="small">${esc(w.stat)}</span></div>`).join("")}</div>`
          + head("Hiện") + tog("asia", "Phiên Á") + tog("london", "Phiên London") + tog("ny", "Phiên New York") + tog("labels", "Nhãn giờ") + tog("countdown", "Đếm ngược macro tiếp theo")
          + head("Màu") + color("colAsia", "Phiên Á") + color("colLondon", "Phiên London") + color("colNy", "Phiên New York");
      };
      const open = () => this.openPanel("Macro", [["inputs", "Cài đặt"]], render, {
        root: this.macroCfg,
        onChange: () => { store.set("aurum.macrocfg", JSON.stringify(this.macroCfg)); this.computeICT(); this.redraw(); },
        afterDraw: (panel) => {
          const on = panel.querySelector("[data-macro]");
          if (on) on.onchange = () => { showInd.macro = on.checked; store.set("aurum.ind", JSON.stringify(showInd)); this.computeICT(); this.redraw(); };
        },
        onReset: () => {
          if (!confirm("Đặt lại cài đặt Macro về mặc định?")) return;
          this.macroCfg = window.MACRO.defaults(); store.set("aurum.macrocfg", JSON.stringify(this.macroCfg)); this.computeICT(); this.redraw(); open();
        },
      });
      open();
    },

    saveLiq() {
      store.set("aurum.liqcfg", JSON.stringify(this.liqCfg));
      this.computeICT();
      this.redraw();
    },

    liqSettingsSheet() {
      if (!window.LIQ) return;
      sheet.close();
      const render = (tab) => {
        const cfg = this.liqCfg;
        const { tog, numf, color, head, note } = fieldKit(cfg);
        if (tab === "style") return head("Màu") + color("bsl", "Thanh khoản trên (BSL)") + color("ssl", "Thanh khoản dưới (SSL)");
        return `<label class="toggle"><span>Bật Vùng thanh khoản</span><span class="switch"><input type="checkbox" data-liq ${showInd.liq ? "checked" : ""}><span></span></span></label>`
          + note("Vùng thanh khoản = nơi stop nằm chờ: trên các đỉnh (BSL) và dưới các đáy (SSL). Các mức gần nhau (trong khoảng dung sai theo ATR) gộp thành một vùng rồi được chấm điểm: đỉnh / đáy bằng nhau +2 (3 lần +3), swing H1 +1 / H4 +2, đỉnh / đáy ngày trước +2, tuần trước +3, đỉnh / đáy phiên Á / London / New York +1 (2 phiên +2), nến khối lượng lớn +1, hơn 1 ngày chưa bị quét +1, số tròn +1. Từ 5 điểm là MẠNH, 3–4 là vừa.")
          + head("Phân loại") + numf("strong", "Điểm tối thiểu vùng MẠNH") + numf("medium", "Điểm tối thiểu vùng vừa") + tog("showMedium", "Hiện vùng vừa")
          + numf("swingLen", "Độ dài swing (nến mỗi bên)") + numf("tolAtr", "Dung sai gộp mức (× ATR)", 0.05) + numf("range", "Chỉ hiện vùng cách giá trong (× biên độ ngày)", 0.5) + numf("showTaken", "Giữ vùng vừa bị lấy gần nhất")
          + head("Yếu tố tính điểm") + tog("equal", "Đỉnh / đáy bằng nhau") + tog("htf", "Swing H1 / H4") + tog("days", "Đỉnh / đáy ngày trước") + tog("weeks", "Đỉnh / đáy tuần trước")
          + tog("sessions", "Đỉnh / đáy phiên Á / London / New York") + tog("volume", "Nến khối lượng lớn") + tog("age", "Lâu chưa bị quét (> 1 ngày)") + tog("round", "Số tròn")
          + note("Kiểm tra trên vàng khung 5m (tháng 4–6 | 7–11/2026): vùng MẠNH không bị giá chạm tới nhiều hơn vùng vừa hay yếu ở cùng khoảng cách, nhưng khi bị quét thì đóng lại ngay nhiều hơn (39% | 40%, so với vừa 32% | 33%, yếu 36% | 30%). Đây là bản đồ nơi stop nằm, không phải tín hiệu vào lệnh.")
          + head("Khác") + tog("labels", "Nhãn ở mép phải") + tog("panel", "Bảng vùng gần nhất (góc trái trên)");
      };
      const open = () => this.openPanel("Vùng thanh khoản", [["inputs", "Các đầu vào"], ["style", "Định dạng"]], render, {
        root: this.liqCfg,
        onChange: () => this.saveLiq(),
        afterDraw: (panel) => {
          const on = panel.querySelector("[data-liq]");
          if (on) on.onchange = () => { showInd.liq = on.checked; store.set("aurum.ind", JSON.stringify(showInd)); this.computeICT(); this.redraw(); };
        },
        onReset: () => {
          if (!confirm("Đặt lại cài đặt Vùng thanh khoản về mặc định?")) return;
          this.liqCfg = window.LIQ.defaults(); this.saveLiq(); open();
        },
      });
      open();
    },

    savePlan() {
      store.set("aurum.plancfg", JSON.stringify(this.planCfg));
      this.computeICT();
      this.redraw();
    },

    planSettingsSheet() {
      if (!window.PLAN) return;
      sheet.close();
      const render = (tab) => {
        const cfg = this.planCfg;
        const { tog, numf, sel, color, head, note } = fieldKit(cfg);
        if (tab === "style") return head("Màu") + color("bull", "Mua") + color("bear", "Bán") + color("level", "PDH / PDL") + color("zoneBuy", "Vùng mua") + color("zoneSell", "Vùng bán") + color("trendColor", "Trendline");
        return `<label class="toggle"><span>Bật Kế hoạch giao dịch</span><span class="switch"><input type="checkbox" data-plan ${showInd.plan ? "checked" : ""}><span></span></span></label>`
          + note("Theo cách vào lệnh của bạn: 1) kế hoạch ngày từ nến hôm qua (đi tiếp, đảo chiều hay chờ quét PDH / PDL); 2) H4 đóng trên / dưới giá mở ngày; 3) vùng FVG / OB H1 – H4; 4) trend kẻ qua 3 đỉnh / 3 đáy và breakout thật / giả; 5) vào lệnh ở nến rút râu. Thuận bias ngày thì gồng, ngược bias thì chốt ngắn.")
          + head("Ngày → H4 → H1") + tog("levels", "PDH / PDL / giá mở ngày") + tog("h4", "H4 so với giá mở ngày") + tog("zones", "Vùng FVG / OB H1 – H4") + numf("zoneCount", "Số vùng mỗi phía")
          + head("Trend") + tog("trend", "Trend 3 đỉnh / 3 đáy") + sel("trendTf", "Khung kẻ trend", [["auto", "Tự động (1m→15m, 5m→H1, 15m→H4)"], ["900", "15m"], ["3600", "H1"], ["14400", "H4"]])
          + numf("touches", "Số lần chạm tối thiểu") + numf("fakeBars", "Breakout giả nếu đóng lại trong (nến khung trend)")
          + head("Tín hiệu (nến rút râu)") + tog("signals", "Hiện tín hiệu")
          + tog("sigRetest", "Retest sau breakout THẬT") + tog("sigFake", "Breakout GIẢ (vào theo trend)") + tog("sigTrend", "Chạm trend (lần chạm thứ 4+)") + tog("sigZone", "Vùng FVG / OB H1 – H4 cùng chiều trend") + tog("sigSweep", "Quét PDH / PDL rồi rút râu")
          + note("Backtest vàng (tháng 4–11/2026, SL 10–50 pip, spread 0.3, tháng 4–6 | tháng 7–11). Khung 5m: retest breakout thật +7.5R | +14.4R (46% thắng, ~0.3 lệnh/ngày, dương cả trên dữ liệu 24/7); quét PDH / PDL −6.9R | +15.4R; breakout giả −15.4R | −32.0R; vùng H1/H4 −43.6R | −65.3R; chạm trend −14.5R | −37.4R. Khung 1m: retest −5.0R | +6.0R (~0.9 lệnh/ngày), các loại khác đều âm. Vì vậy mặc định chỉ bật retest và nên xem ở khung 5m; bật thêm loại khác để tự đối chiếu với thống kê trên chart.")
          + numf("maxSlPips", "SL tối đa (pip · vàng: 1 pip = 0.1)") + numf("minSlPips", "SL tối thiểu (pip, để spread không ăn hết lệnh)") + numf("tpWith", "TP khi thuận bias ngày (R, gồng tới thanh khoản)", 0.5) + numf("tpAgainst", "TP khi ngược bias ngày (R, chốt ngắn)", 0.5) + numf("tpNeutral", "TP khi ngày đi ngang (R)", 0.5)
          + numf("spread", "Spread + phí (giá)", 0.05) + numf("signalCount", "Số tín hiệu gần nhất trên chart")
          + head("Khác") + tog("panel", "Bảng kế hoạch ở góc trái dưới");
      };
      const open = () => this.openPanel("Kế hoạch giao dịch", [["inputs", "Các đầu vào"], ["style", "Định dạng"]], render, {
        root: this.planCfg,
        onChange: () => this.savePlan(),
        afterDraw: (panel) => {
          const on = panel.querySelector("[data-plan]");
          if (on) on.onchange = () => { showInd.plan = on.checked; store.set("aurum.ind", JSON.stringify(showInd)); this.computeICT(); this.redraw(); };
        },
        onReset: () => {
          if (!confirm("Đặt lại cài đặt Kế hoạch giao dịch về mặc định?")) return;
          this.planCfg = window.PLAN.defaults(); this.savePlan(); open();
        },
      });
      open();
    },

    /* ----- TTrades Model (models.js) ----- */

    /** The model on these bars (the chart's or an extra timeframe's), or null when it is off. */
    modelsFor(bars, sec, digits) {
      const allowed = this.owner || this.features.killzones !== false;
      if (!showInd.models || !allowed || !window.MODELS || !this.modelCfg || !bars.length) return null;
      try {
        return window.MODELS.compute(bars, sec, this.modelCfg, { events: (this.news && this.news.events) || [], fmt: (v) => fmt(v, digits) });
      } catch { return null; }
    },

    saveModels() {
      store.set("aurum.modelcfg", JSON.stringify(this.modelCfg));
      this.computeICT();
      this.redraw();
    },

    /** The fixed setups of the TTrades indicator, newest first: show one on the chart, or copy it into a
     *  long / short position drawing whose entry, stop and target can be dragged. */
    setupListSheet() {
      const o = this.models, d = this.digits;
      if (!o || !o.setups || !o.setups.length) return toast("Chưa có setup: bật TTrades Model, kiểu \"Setup cố định\"", true);
      sheet.close();
      const S = window.MODELS.SETUP_STATUS, bars = this.viewBars();
      const list = o.setups.slice(-40).reverse();
      const color = { win: "pos", loss: "neg", open: "pos", signal: "pos", wait: "" };
      sheet.open(`<h3>Setup TTrades · ${esc(o.htfName)} → ${esc(this.interval)}</h3>
        <p class="muted small">Mức của mỗi setup được chốt khi nến 2 đóng và không đổi theo nến mới. Bấm <b>Sửa</b> để chép setup thành lệnh vẽ (Vị thế Mua / Bán) rồi kéo vào lệnh, SL, TP theo ý bạn.</p>
        <div class="list">${list.map((s) => {
          const t = s.trade, when = bars[Math.min(s.formedAt, bars.length - 1)].time;
          const info = t && t.entry != null ? `vào ${fmt(t.entry, d)} · SL ${fmt(t.stop, d)} · TP ${fmt(t.target, d)}${t.why !== "open" ? ` · <b class="${t.r > 0 ? "pos" : "neg"}">${t.r >= 0 ? "+" : ""}${t.r.toFixed(1)}R</b>` : ""}`
            : `EQ ${fmt(s.eq, d)} · huỷ ${fmt(s.invalid, d)} · mục tiêu ${fmt(s.target, d)}`;
          const sc = s.list ? ` · ${s.score}/${s.list.length} yếu tố` : "";
          return `<div class="row"><span class="${s.dir > 0 ? "pos" : "neg"}">#${s.n} ${s.dir > 0 ? "MUA" : "BÁN"}</span>
            <span class="grow" style="margin-left:8px">${fullTime(when)} · <span class="${color[s.status] || "muted"}">${esc(S[s.status])}</span>${sc}<br><span class="muted small">${info}</span></span>
            <button type="button" class="btn btn-small" data-go="${s.n}">Xem</button><button type="button" class="btn btn-small" data-edit="${s.n}" style="margin-left:6px">Sửa</button></div>`;
        }).join("")}</div>`, (el) => {
        const find = (n) => o.setups.find((s) => s.n === +n);
        el.querySelectorAll("[data-go]").forEach((b) => (b.onclick = () => {
          const s = find(b.dataset.go);
          sheet.close();
          this.chart.timeScale().setVisibleLogicalRange({ from: s.c1.start - 40, to: Math.max(s.endIdx, s.trade && s.trade.exitAt ? s.trade.exitAt : 0) + 40 });
        }));
        el.querySelectorAll("[data-edit]").forEach((b) => (b.onclick = () => { sheet.close(); this.setupToDrawing(find(b.dataset.edit)); }));
      });
    },

    /** A setup as a position drawing: its trade, or for one still waiting: now → its cancel level → candle 1's target. */
    setupToDrawing(s) {
      const dr = this.drawings, bars = this.viewBars();
      if (!dr || !s || !bars.length) return;
      const sec = TF_SECONDS[this.interval] || 60, t = s.trade;
      const at = t && t.entry != null ? t.time : bars[bars.length - 1].time;
      const entry = t && t.entry != null ? t.entry : bars[bars.length - 1].close;
      const stop = t && t.stop != null ? t.stop : s.invalid, target = t && t.target != null ? t.target : s.target;
      if ((entry - stop) * s.dir <= 0 || (target - entry) * s.dir <= 0) return toast("Giá đã ra ngoài setup này: không chép được", true);
      const d = dr.newDrawing(s.dir > 0 ? "longPosition" : "shortPosition");
      const right = at + sec * 30;
      d.pts = [{ t: at, p: entry }, { t: right, p: stop }, { t: right, p: target }];
      d.text = `Setup #${s.n}`;
      dr.pending = d;
      dr.finish();
      this.renderDrawBar();
      toast(`Đã chép setup #${s.n} thành lệnh vẽ: kéo vào lệnh / SL / TP để chỉnh`);
    },

    modelsSettingsSheet() {
      if (!window.MODELS) return;
      sheet.close();
      const htfOpts = [["auto", "Tự động theo cặp khung"], [900, "15m"], [1800, "30m"], [3600, "H1"], [14400, "H4"], [86400, "D1"], [604800, "W1"]];
      const render = (tab) => {
        const cfg = this.modelCfg;
        const { tog, numf, sel, color, text, head, note } = fieldKit(cfg);
        if (tab === "style") {
          return head("Màu") + color("bull", "Tăng") + color("bear", "Giảm") + color("eqColor", "Đường EQ (cân bằng)")
            + color("projColor", "Mục tiêu Std") + color("breakerColor", "Breaker") + color("unicornColor", "Unicorn");
        }
        return `<label class="toggle"><span>Bật TTrades Model</span><span class="switch"><input type="checkbox" data-models ${showInd.models ? "checked" : ""}><span></span></span></label>`
          + head("Cách hiển thị") + sel("view", "Kiểu", [["setup", "Setup cố định (rõ ràng, không chạy theo nến)"], ["full", "Đầy đủ (câu chuyện nến hiện tại, CISD, breaker)"]])
          + note("Setup cố định: mỗi swing được chốt mức khi nến 2 đóng (huỷ, EQ, mục tiêu), rồi vào lệnh ở CISD đầu tiên hợp lệ. Mức không đổi theo nến mới; mỗi setup có trạng thái riêng.")
          + head("Checklist vào lệnh (theo tài liệu)")
          + `<div class="row-btns"><button type="button" class="btn btn-small" data-preset="safe">Chắc ăn</button><button type="button" class="btn btn-small" data-preset="many">Nhiều lệnh</button><button type="button" class="btn btn-small" data-preset="kz">Có killzone</button></div>`
          + note("Mẫu có sẵn (backtest vàng 1m→15m, tháng 4–11/2026, dữ liệu kiểu MT5 và 24/7, SL ≤ 50 pip): <b>Chắc ăn</b> — bắt buộc hồ sơ ngày + bias ngày + CISD mạnh + FVG H1/H4, TP 1R: 59–61% thắng, ~0.5 lệnh/ngày. <b>Nhiều lệnh</b> — bỏ killzone, bắt buộc hồ sơ ngày + bias ngày + lịch + CISD mạnh, cần 6 điểm, TP 1.5R: 47–52% thắng, ~1.7 lệnh/ngày. <b>Có killzone</b> — killzone + hồ sơ ngày + lịch, 7 điểm, TP 1.5R: 49–60% thắng, ~1.1 lệnh/ngày. Cả ba đều dương ở cả 2 giai đoạn; killzone không bắt buộc thì không được tính điểm.")
          + sel("setupMode", "Cách xét", [["score", "Checklist: đủ yếu tố bắt buộc + đủ điểm"], ["filters", "Theo các công tắc ở mục \"Vào lệnh M1\""]])
          + numf("setupMinScore", "Số yếu tố tối thiểu")
          + numf("setupMaxSlPips", "SL tối đa (pip · vàng: 1 pip = 0.1)") + sel("setupSlMode", "SL xa hơn mức tối đa", [["skip", "Bỏ qua lệnh đó"], ["cap", "Kéo SL về mức tối đa"]])
          + sel("entryTarget", "Chốt lời", [["1R", "1R (tỉ lệ thắng cao nhất)"], ["1.2R", "1.2R"], ["1.5R", "1.5R (lãi nhiều hơn)"], ["2R", "2R"], ["c1", "Đáy / đỉnh nến 1"]])
          + tog("setupNear", "Hiện setup gần đủ (B): thiếu 1 yếu tố, không vào — để đối chiếu")
          + note("Yếu tố BẮT BUỘC (bật = bắt buộc):")
          + Object.entries(window.MODELS.CHECK_LABELS).map(([k, label]) => `<label class="toggle"><span>${esc(label)}</span><span class="switch"><input type="checkbox" data-must="${k}" ${String(cfg.setupMust || "").split(",").includes(k) ? "checked" : ""}><span></span></span></label>`).join("")
          + head("Hiển thị setup")
          + numf("setupCount", "Giữ setup đã vào lệnh gần nhất") + tog("setupSkips", "Đánh dấu CISD bị bỏ qua (và lý do)") + tog("setupDead", "Hiện cả setup bị huỷ / hết giờ (mờ)")
          + `<div class="row-btns"><button type="button" class="btn wide" data-setups>📋 Danh sách setup · sửa thành lệnh vẽ</button></div>`
          + head("Khung lớn (nến 1-2-3-4)") + sel("htf", "Khung lớn", htfOpts) + note("Tự động: 1m→15m, 3m→30m, 5m→H1, 15m→H4, H1→D1, H4→W1 (theo tài liệu).")
          + tog("swing", "Đánh số nến 1-2-3-4, đáy / đỉnh nến 1 bị quét, mục tiêu") + tog("eqLines", "EQ râu nến 2 / EQ nến 3 (giá phải giữ)")
          + tog("pcl", "PCH / PCL nến trước của khung lớn")
          + head("CISD") + tog("cisd", "Hiện CISD") + tog("cisdPoiOnly", "Chỉ CISD tại POI (sau khi quét đỉnh / đáy)") + numf("cisdCount", "Giữ CISD gần nhất")
          + tog("projections", "Mục tiêu Std của chân thao túng (CISD mới nhất)") + text("projLevels", "lb") + note("Các mức, cách nhau dấu phẩy: -1,-2,-2.5,-4.")
          + head("Breaker & Unicorn") + tog("breakers", "Breaker block") + tog("unicorn", "Unicorn (breaker trùng FVG)") + numf("breakerCount", "Giữ breaker gần nhất")
          + head("Vào lệnh M1 (15m → 1m)") + tog("entries", "Hiện điểm vào M1 trên khung 1m (mũi tên, SL / TP, kết quả)")
          + sel("entryBot", "Bot", [["ttrades", "TTrades M1 (theo cài đặt bên dưới)"], ["daily", "Bot ICT tổng hợp: TTrades + quét thanh khoản (~2 lệnh / ngày)"]])
          + sel("entryTarget", "Chốt lời", [["1R", "1R"], ["1.5R", "1.5R"], ["2R", "2R (tối thiểu theo tài liệu)"], ["3R", "3R"], ["std1", "Mức -1 Std"], ["std2", "Mức -2 Std"], ["std4", "Mức -4 Std"], ["c1", "Đáy / đỉnh nến 1 (mục tiêu swing)"]])
          + sel("entryMode", "Vào lệnh", [["market", "Giá mở nến kế tiếp"], ["limit", "Lệnh limit tại mức CISD (chờ 15 nến)"]])
          + sel("entryStop", "Cắt lỗ", [["leg", "Ngoài chân thao túng M1"], ["c2", "Đỉnh / đáy nến 2 (15m)"]])
          + tog("entryKillzones", "Chỉ trong killzone London 2–5h, NY 7–10h (giờ New York)") + tog("entryNyPm", "Thêm killzone NY chiều 13:30–16h (giờ New York)") + tog("entryAsia", "Thêm phiên Á 20h–0h (giờ New York)") + tog("entrySkipMonday", "Bỏ Thứ Hai")
          + tog("entryOnePerSwing", "Một lệnh mỗi swing 15m") + tog("entryIdeal", "Chỉ ideal formation (nến 2 râu dài)") + numf("entrySpread", "Spread + phí mỗi lệnh (giá)", 0.05)
          + tog("entryDailyProfile", "Hồ sơ ngày: London đảo chiều → NY theo; London phá hẳn → bỏ NY; London đi ngang → NY đảo chiều")
          + tog("entryDailyBias", "Bias ngày (PDH / PDL, failure to displace) cùng chiều") + tog("entryNews", "Tránh giờ ra tin 8:25–8:45 và 9:55–10:15 (NY)")
          + tog("entryDiscount", "Mua ở discount / bán ở premium của swing (nến 1 + nến 2)") + tog("entryAlignH1", "Đồng thuận bias nến H1")
          + tog("entryStrong", "Nến CISD mạnh (thân ≥ biên độ TB)") + tog("entryPartial", "Chốt 50% ở 1R rồi dời SL về hoà vốn")
          + `<button type="button" class="btn btn-gold wide" data-bt-m1>▶ Backtest bot M1 trên dữ liệu MT5</button>`
          + head("Khác") + tog("rules", "Luật lịch: Thứ Hai, ngày trước tin đỏ, sắp có tin") + tog("panel", "Bảng tóm tắt ở góc trái dưới");
      };
      const open = () => this.openPanel("TTrades Model", [["inputs", "Các đầu vào"], ["style", "Định dạng"]], render, {
        root: this.modelCfg,
        onChange: () => this.saveModels(),
        afterDraw: (panel) => {
          const bt = panel.querySelector("[data-bt-m1]");
          if (bt) bt.onclick = () => this.modelBacktestSheet();
          const PRESETS = { safe: { setupMust: "profile,dbias,strong,htf", setupMinScore: 0, entryTarget: "1R" },
            many: { setupMust: "profile,dbias,cal,strong", setupMinScore: 6, entryTarget: "1.5R" }, kz: { setupMust: "kz,profile,cal", setupMinScore: 7, entryTarget: "1.5R" } };
          panel.querySelectorAll("[data-preset]").forEach((b) => (b.onclick = () => {
            Object.assign(this.modelCfg, PRESETS[b.dataset.preset], { setupMode: "score", setupMaxSlPips: 50, setupSlMode: "skip" });
            this.saveModels(); open();
            toast(`Đã chọn mẫu "${b.textContent}"`);
          }));
          panel.querySelectorAll("[data-must]").forEach((box) => (box.onchange = () => {
            const set = new Set(String(this.modelCfg.setupMust || "").split(",").filter(Boolean));
            if (box.checked) set.add(box.dataset.must); else set.delete(box.dataset.must);
            this.modelCfg.setupMust = [...set].join(",");
            this.saveModels();
          }));
          const su = panel.querySelector("[data-setups]");
          if (su) su.onclick = () => this.setupListSheet();
          const on = panel.querySelector("[data-models]");
          if (on) on.onchange = () => { showInd.models = on.checked; store.set("aurum.ind", JSON.stringify(showInd)); this.computeICT(); this.redraw(); };
        },
        onReset: () => {
          if (!confirm("Đặt lại cài đặt TTrades Model về mặc định?")) return;
          this.modelCfg = window.MODELS.defaults(); this.saveModels(); open();
        },
      });
      open();
    },

    /** 1-minute bars of the chart's symbol for the last `days`, fetched from the VPS (MT5) page by page. */
    async historyM1(days, progress) {
      const key = `${this.symbolKey()}|${days}`;
      if (this.m1Cache && this.m1Cache.key === key && Date.now() - this.m1Cache.at < 10 * 60 * 1000) return this.m1Cache.bars;
      const per = this.owner ? 5000 : 1000, want = days * 1440, from = Date.now() / 1000 - days * 86400;
      let bars = [], before = null;
      for (let page = 0; page < 80 && bars.length < want; page++) {
        const extra = before ? `&before=${before}` : "";
        const path = this.owner ? `/mt5/candles?symbol=${encodeURIComponent(this.symbol)}&interval=1m&count=${per}${extra}` : `/member/candles?interval=1m&count=${per}${extra}`;
        const data = await this.call(path);
        const got = this.toBars(data.candles || []);
        if (!got.length) break;
        bars = got.concat(bars.filter((b) => b.time > got[got.length - 1].time));
        before = got[0].time;
        if (progress) progress(bars.length);
        if (got[0].time <= from || got.length < per * 0.5) break;
      }
      bars = bars.filter((b) => b.time >= from);
      this.m1Cache = { key, bars, at: Date.now() };
      return bars;
    },

    /** The M1 bot (TTrades fractal model) over past 1-minute bars: win rate, R, drawdown, month by month. */
    modelBacktestSheet() {
      if (!window.MODELS || !this.modelCfg) return;
      sheet.close();
      const cfg = this.modelCfg;
      const days = +(store.get("aurum.btm1days") || 30);
      sheet.open(`<h3>Backtest bot M1 · TTrades</h3>
        <p class="muted small">Bot vào lệnh khung 1m theo mô hình fractal: swing nến 2 / nến 3 trên 15m → CISD trên 1m (sau khi quét đỉnh / đáy) theo hướng swing,
        vào ở giá mở nến kế tiếp. Không nhìn trước tương lai; cây nến chạm cả SL và TP tính là thua. Dùng cài đặt ở mục "Vào lệnh M1".</p>
        <label>Bot<select id="btBot">${[["ttrades", "TTrades M1 (theo cài đặt)"], ["daily", "ICT tổng hợp: TTrades + quét thanh khoản · ~2 lệnh / ngày"]].map(([v, n]) => `<option value="${v}" ${v === cfg.entryBot ? "selected" : ""}>${n}</option>`).join("")}</select></label>
        <div class="fields two"><label>Số ngày<select id="btDays">${[7, 14, 30, 60, 90].map((d) => `<option value="${d}" ${d === days ? "selected" : ""}>${d} ngày</option>`).join("")}</select></label>
        <label>Chốt lời<select id="btTarget">${[["1R", "1R"], ["1.5R", "1.5R"], ["2R", "2R"], ["3R", "3R"], ["std1", "-1 Std"], ["std2", "-2 Std"], ["std4", "-4 Std"], ["c1", "Đáy / đỉnh nến 1"]].map(([v, n]) => `<option value="${v}" ${v === cfg.entryTarget ? "selected" : ""}>${n}</option>`).join("")}</select></label></div>
        <div class="toggles bt-filters">${[["entryKillzones", "Killzone London 2–5h, NY 7–10h"], ["entryNyPm", "Thêm NY chiều 13:30–16h"], ["entryAsia", "Thêm phiên Á 20h–0h NY (8–12h VN mùa đông)"], ["entrySkipMonday", "Bỏ Thứ Hai"], ["entryOnePerSwing", "Một lệnh mỗi swing 15m"],
          ["entryDailyProfile", "Hồ sơ ngày (London / NY reversal)"], ["entryDiscount", "Mua discount / bán premium của swing"], ["entryDailyBias", "Bias ngày (PDH / PDL) cùng chiều"],
          ["entryAlignH1", "Đồng thuận bias nến H1"], ["entryStrong", "Nến CISD mạnh"], ["entryPartial", "Chốt 50% ở 1R + dời SL hoà vốn"], ["entryNews", "Tránh giờ ra tin 8:30 / 10:00"], ["entryIdeal", "Chỉ ideal formation"]]
          .map(([k, n]) => `<label class="toggle"><span>${n}</span><span class="switch"><input type="checkbox" data-f="${k}" ${cfg[k] ? "checked" : ""}><span></span></span></label>`).join("")}</div>
        <button class="btn btn-gold wide" id="btRun">▶ Chạy backtest ${esc(this.symbol || "")}</button>
        <div id="btOut" class="bt-out"></div>`, (el) => {
        const out = el.querySelector("#btOut");
        el.querySelector("#btRun").onclick = async (e) => {
          const button = e.currentTarget;
          const d = +el.querySelector("#btDays").value;
          store.set("aurum.btm1days", String(d));
          cfg.entryTarget = el.querySelector("#btTarget").value;
          cfg.entryBot = el.querySelector("#btBot").value;
          el.querySelectorAll("[data-f]").forEach((x) => { cfg[x.dataset.f] = x.checked; });
          store.set("aurum.modelcfg", JSON.stringify(cfg));
          button.disabled = true;
          out.innerHTML = `<p class="muted">Đang tải nến M1…</p>`;
          try {
            const bars = await this.historyM1(d, (n) => { out.innerHTML = `<p class="muted">Đang tải nến M1… ${n.toLocaleString("vi-VN")} cây</p>`; });
            if (bars.length < 500) throw new Error("Chưa đủ nến M1 (máy chủ trả về quá ít)");
            const tally = {};
            const trades = window.MODELS.botEntries(bars, cfg, { tally });
            this.renderBacktestM1(out, bars, trades, tally);
          } catch (err) {
            out.innerHTML = `<p class="neg">Không chạy được: ${esc(err.message || String(err))}</p>`;
          } finally { button.disabled = false; }
        };
      });
    },

    renderBacktestM1(out, bars, trades, tally) {
      const M = window.MODELS, st = M.stats(trades), d = this.digits;
      const pct = (v) => (v * 100).toFixed(1) + "%", r = (v) => (v >= 0 ? "+" : "") + v.toFixed(1) + "R";
      const months = {};
      trades.forEach((t) => { const k = new Date(t.time * 1000).toISOString().slice(0, 7); (months[k] = months[k] || []).push(t); });
      const first = bars[0].time, last = bars[bars.length - 1].time;
      // Per trading day (days with bars), and the stop / target distances in price.
      const tradingDays = new Set(bars.map((b) => Math.floor(b.time / 86400))).size || 1;
      const byDay = {};
      trades.forEach((t) => { const k = Math.floor(t.time / 86400); byDay[k] = (byDay[k] || 0) + 1; });
      const perDay = trades.length / tradingDays, maxDay = Math.max(0, ...Object.values(byDay));
      const avg = (f) => (trades.length ? trades.reduce((a, t) => a + f(t), 0) / trades.length : 0).toFixed(2);
      out.innerHTML = `<p class="muted small">${bars.length.toLocaleString("vi-VN")} nến M1 · ${fullTime(first)} → ${fullTime(last)}</p>
        <div class="kvs">
          <div class="kv"><span>Số lệnh</span><b>${st.trades}</b></div>
          <div class="kv"><span>Tỉ lệ thắng</span><b class="${st.winRate >= 0.34 ? "pos" : "neg"}">${pct(st.winRate)}</b></div>
          <div class="kv"><span>Tổng</span><b class="${st.totalR >= 0 ? "pos" : "neg"}">${r(st.totalR)}</b></div>
          <div class="kv"><span>TB mỗi lệnh</span><b>${(st.avgR >= 0 ? "+" : "") + st.avgR.toFixed(2)}R</b></div>
          <div class="kv"><span>Profit factor</span><b>${st.profitFactor == null ? "–" : st.profitFactor.toFixed(2)}</b></div>
          <div class="kv"><span>Sụt vốn lớn nhất</span><b>${st.maxDD.toFixed(1)}R</b></div>
          <div class="kv"><span>Thua liên tiếp</span><b>${st.worstStreak}</b></div>
          <div class="kv"><span>Lệnh mỗi ngày</span><b>${perDay.toFixed(2)} · nhiều nhất ${maxDay}</b></div>
          <div class="kv"><span>Ngày có lệnh</span><b>${Object.keys(byDay).length} / ${tradingDays} (${pct(Object.keys(byDay).length / tradingDays)})</b></div>
          <div class="kv"><span>SL / TP trung bình</span><b>${avg((t) => t.risk)} / ${avg((t) => Math.abs(t.target - t.entry))} giá</b></div>
        </div>
        ${trades.some((t) => t.model && t.model !== "A") ? `<h4>Theo mô hình</h4>
        <div class="list">${Object.entries(M.BOT_MODELS).filter(([k]) => trades.some((t) => t.model === k)).map(([k, n]) => {
          const s = M.stats(trades.filter((t) => t.model === k));
          return `<div class="row"><span class="grow">${k} · ${esc(n)}</span><span>${s.trades} lệnh · ${pct(s.winRate)}</span><b class="${s.totalR >= 0 ? "pos" : "neg"}" style="margin-left:10px">${r(s.totalR)}</b></div>`; }).join("")}</div>` : ""}
        <h4>Theo phiên</h4>
        <div class="list">${[["london", "London 2–5h NY"], ["ny", "New York 7–11h"], ["pm", "NY chiều 13:30–16h"], ["asia", "Phiên Á 20h–0h"]].filter(([k]) => trades.some((t) => t.session === k)).map(([k, n]) => {
          const s = M.stats(trades.filter((t) => t.session === k));
          return `<div class="row"><span class="grow">${n}</span><span>${s.trades} lệnh · ${pct(s.winRate)}</span><b class="${s.totalR >= 0 ? "pos" : "neg"}" style="margin-left:10px">${r(s.totalR)}</b></div>`; }).join("") || '<div class="empty">Không có lệnh nào</div>'}</div>
        <p class="muted small">Hoà vốn cần thắng khoảng: TP 1R → 50%, 1.5R → 40%, 2R → 34%, 3R → 25% (chưa tính phí). 1R = khoảng cách vào lệnh → cắt lỗ.</p>
        ${this.skipsHtml(trades.filter((t) => !t.model || t.model === "A"), tally, bars)}
        <h4>Theo tháng</h4>
        <div class="list">${Object.entries(months).map(([k, l]) => { const s = M.stats(l); return `<div class="row"><span class="grow">${k}</span><span>${s.trades} lệnh · ${pct(s.winRate)}</span><b class="${s.totalR >= 0 ? "pos" : "neg"}" style="margin-left:10px">${r(s.totalR)}</b></div>`; }).join("")}</div>
        <h4>Lệnh gần nhất</h4>
        <div class="list">${trades.slice(-40).reverse().map((t) => `<div class="row clickable" data-t="${t.time}"><span class="${t.dir > 0 ? "pos" : "neg"}">${t.dir > 0 ? "MUA" : "BÁN"}</span>
          <span class="grow" style="margin-left:8px">${t.model && t.model !== "A" ? `<span class="muted small">${t.model}</span> ` : ""}${fullTime(t.time)} · ${fmt(t.entry, d)} · SL ${fmt(t.stop, d)} · TP ${fmt(t.target, d)}</span>
          <b class="${t.why === "open" ? "" : t.r > 0 ? "pos" : "neg"}">${t.why === "open" ? "đang chạy" : r(t.r)}</b></div>`).join("") || '<div class="empty">Không có lệnh nào</div>'}</div>`;
      out.querySelectorAll("[data-t]").forEach((row) => (row.onclick = () => this.showBacktestTrade(+row.dataset.t)));
    },

    /** Where the CISD signals went: the filters that dropped the most first, so a setting that blocks nearly
     *  everything is plain to see. Each signal counts once, at the first check it fails. */
    skipsHtml(trades, tally, bars) {
      const M = window.MODELS;
      if (!tally || !M.SKIPS) return "";
      const rows = Object.entries(tally).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]);
      const signals = rows.reduce((a, [, n]) => a + n, 0) + trades.length;
      const days = Math.max(1, (bars[bars.length - 1].time - bars[0].time) / 86400);
      const perWeek = (trades.length / days) * 7;
      const own = rows.filter(([k]) => M.SKIPS[k] && M.SKIPS[k][1]);
      const top = own[0], hint = top && perWeek < 2 ? `<p class="muted small">Ít lệnh chủ yếu do bộ lọc <b>${esc(M.SKIPS[top[0]][0])}</b>: thử tắt nó ở trên rồi chạy lại.</p>` : "";
      return `<h4>Tín hiệu TTrades bị loại</h4>
        <p class="muted small">${signals.toLocaleString("vi-VN")} tín hiệu CISD M1 → ${trades.length} lệnh (~${perWeek.toFixed(1)} lệnh / tuần). Mỗi tín hiệu chỉ tính ở bộ lọc đầu tiên loại nó.</p>
        <div class="list">${rows.map(([k, n]) => { const d = M.SKIPS[k] || [k, null]; return `<div class="row"><span class="grow">${esc(d[0])}${d[1] ? ' <span class="muted small">· cài đặt</span>' : ""}</span><b>${n.toLocaleString("vi-VN")}</b></div>`; }).join("")}</div>${hint}`;
    },

    /** A backtest trade on the 1-minute chart. */
    showBacktestTrade(t) {
      sheet.close();
      const go = () => {
        const i = this.bars.findIndex((b) => b.time >= t);
        if (i < 0) return toast("Lệnh này cũ hơn các nến đang có trên biểu đồ: kéo biểu đồ về trước để tải thêm", true);
        this.chart.timeScale().setVisibleLogicalRange({ from: i - 60, to: i + 90 });
      };
      if (this.interval !== "1m") { this.interval = "1m"; store.set("aurum.tf", "1m"); this.loadCandles().then(go); } else go();
    },

    /* ----- ICT layer ----- */

    computeICT() {
      this.ictTime = Date.now();
      const allowed = this.owner || this.features.killzones !== false;
      const bars = this.viewBars();
      // Shark bubbles with the money flow (same switch as its two lines).
      const flowAllowed = this.owner || this.features.sharkflow !== false;
      const flow = flowAllowed && (showInd.flow || showInd.zones) && window.ICT && bars.length ? window.ICT.sharkFlow(bars) : null;
      this.sharks = flow && showInd.flow ? flow.sharks : null;
      this.sharkZones = flow && showInd.zones ? flow.zones : null;
      if (!allowed || !bars.length || !window.ICT || !this.ictCfg) { this.ict = null; this.redraw(); (this.panes || []).forEach((p) => p.analyseSoon()); return; }
      try {
        this.ict = window.ICT.compute(bars, TF_SECONDS[this.interval], this.ictCfg, showInd, { m1: this.mondayM1(bars) });
      } catch { this.ict = null; }
      this.alertPeriodBreaks();
      this.models = this.modelsFor(bars, TF_SECONDS[this.interval], this.digits);
      this.plan = this.planFor(bars, TF_SECONDS[this.interval], this.digits);
      this.liq = this.liqFor(bars, TF_SECONDS[this.interval], this.digits);
      this.macro = this.macroFor(bars, TF_SECONDS[this.interval]);
      if (this.cmpBars && this.cmpBars.length) this.showCmp(false); else this.computeSMT();
      this.applyStudies();
      this.redraw();
      // Indicator settings changed here reach the extra timeframes too (at most every 1.5 s).
      (this.panes || []).forEach((p) => p.analyseSoon());
    },

    /** The charts reach down to the window's bottom (whatever the lines above them take), plus or minus what
     *  the grip under them was dragged (saved). Refitted when the window or the lines above change size. */
    setupChartFit() {
      if (this.fitReady) return;
      this.fitReady = true;
      this.chartExtra = +(store.get("aurum.chartExtra") || 0) || 0;
      const fit = () => this.fitChart();
      window.addEventListener("resize", fit);
      if (window.ResizeObserver) {
        const ro = new ResizeObserver(fit);
        document.querySelectorAll(".chart-top, .chart-sub").forEach((el) => ro.observe(el));
      }
      const grip = $("chartGrip");
      grip.addEventListener("pointerdown", (e) => {
        e.preventDefault();
        grip.setPointerCapture(e.pointerId);
        grip.classList.add("drag");
        const y0 = e.clientY, start = this.chartExtra;
        const move = (ev) => { this.chartExtra = Math.round(start + ev.clientY - y0); this.fitChart(); };
        const up = () => {
          grip.classList.remove("drag");
          grip.removeEventListener("pointermove", move);
          grip.removeEventListener("pointerup", up);
          grip.removeEventListener("pointercancel", up);
          store.set("aurum.chartExtra", String(this.chartExtra));
        };
        grip.addEventListener("pointermove", move);
        grip.addEventListener("pointerup", up);
        grip.addEventListener("pointercancel", up);
      });
      grip.addEventListener("dblclick", () => { this.chartExtra = 0; store.set("aurum.chartExtra", "0"); this.fitChart(); });
      fit();
    },

    fitChart() {
      const charts = $("charts");
      if (!charts || $("dashView").hidden || this.tab !== "chart") return;
      // From the charts' top on the page (not the scrolled view) to the window's bottom, less what the page has
      // under them (the grip, the note, the paddings), so the chart tab fits the window with nothing to scroll.
      const box = charts.getBoundingClientRect(), dash = $("dashView").getBoundingClientRect();
      const top = box.top + window.scrollY, below = Math.max(0, dash.bottom - box.bottom);
      const avail = window.innerHeight - top - below;
      // The grip only makes the chart smaller than the window (taller would bring the page scroll back).
      if ((this.chartExtra || 0) > 0) { this.chartExtra = 0; store.set("aurum.chartExtra", "0"); }
      const h = Math.max(300, Math.floor(avail + (this.chartExtra || 0)));
      // Never less than 300 px: drags past that are not kept.
      if (avail + (this.chartExtra || 0) < 300) this.chartExtra = Math.min(0, 300 - avail);
      document.documentElement.style.setProperty("--ch", h + "px");
    },

    /** Full screen: the chart panel alone over the whole window, and the browser's own full screen where it has
     *  one (not iPhone Safari: there the panel still fills the page). */
    setFull(on) {
      document.body.classList.toggle("chart-full", on);
      if (on) { this.renderSideRail(); this.renderRangeBar(); this.updateLegend(); this.updateClock(); }
      else if (this.sideTab) { this.sideTab = null; this.renderTabs(); }
      $("fullBtn").title = on ? "Thoát toàn màn hình (F / Esc)" : "Toàn màn hình (F, thoát: Esc)";
      const el = document.documentElement;
      if (on) {
        this.fullNative = false;
        if (el.requestFullscreen && !document.fullscreenElement) {
          el.requestFullscreen({ navigationUI: "hide" }).then(() => { this.fullNative = true; }).catch(() => {});
        }
      } else if (document.fullscreenElement && document.exitFullscreen) {
        this.fullNative = false;
        document.exitFullscreen().catch(() => {});
      }
      this.fitFull();
    },

    /** The space above the charts (title, timeframes, flow lines) taken off their height. */
    fitFull() {
      requestAnimationFrame(() => {
        const charts = $("charts");
        if (document.body.classList.contains("chart-full") && charts) {
          const top = Math.max(0, Math.round(charts.getBoundingClientRect().top)) + 6;
          document.body.style.setProperty("--fs-top", top + "px");
          // Under the charts: the grip's place, the range bar, and on phones the section bar at the bottom.
          const rail = $("sideRail"), phone = window.innerWidth <= 600;
          const bot = $("rangeBar").offsetHeight + (phone && rail ? rail.offsetHeight : 0) + 4;
          document.body.style.setProperty("--fs-bot", bot + "px");
        }
        this.redraw();
        if (this.placeSplits) this.placeSplits();
      });
    },

    /** Full screen's right column: the other sections (opening beside the chart), the theme, leaving. */
    renderSideRail() {
      const rail = $("sideRail");
      if (!rail) return;
      const icon = (d) => `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
      const ICONS = {
        trade: '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 9h8M8 13h8M8 17h5"/>',
        signals: '<path d="M4 18 9 12l4 3 7-9"/><path d="M15 6h5v5"/>',
        history: '<circle cx="12" cy="12" r="8"/><path d="M12 8v4l3 2"/>',
        news: '<path d="M5 5h11v14H6a1 1 0 0 1-1-1z"/><path d="M16 9h3v9a1 1 0 0 1-1 1h-2M8 9h5M8 13h5M8 16h3"/>',
        autobot: '<rect x="5" y="8" width="14" height="11" rx="2"/><path d="M12 4v4M9 13h.01M15 13h.01M9 16h6"/>',
        copy: '<rect x="8" y="8" width="11" height="11" rx="2"/><path d="M5 15V6a1 1 0 0 1 1-1h9"/>',
        members: '<circle cx="9" cy="9" r="3"/><path d="M3.5 19a5.5 5.5 0 0 1 11 0M16 7a3 3 0 0 1 0 6M17.5 14.5A5 5 0 0 1 20.5 19"/>',
        bot: '<rect x="4" y="5" width="16" height="6" rx="1.5"/><rect x="4" y="13" width="16" height="6" rx="1.5"/><path d="M8 8h.01M8 16h.01"/>',
      };
      const items = this.tabList().filter(([k]) => k !== "chart");
      rail.innerHTML = items.map(([k, name]) => `<button type="button" data-side="${k}" class="${this.sideTab === k ? "on" : ""}" title="${esc(name)}">${icon(ICONS[k] || ICONS.trade)}</button>`).join("")
        + `<span class="grow"></span><span class="sep"></span>`
        + `<button type="button" data-side-act="theme" title="Sáng / tối">${icon('<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>')}</button>`
        + `<button type="button" data-side-act="exit" title="Thoát toàn màn hình (Esc)">${icon('<path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5"/>')}</button>`;
      rail.querySelectorAll("[data-side]").forEach((b) => (b.onclick = () => this.openSide(b.dataset.side)));
      rail.querySelector('[data-side-act="theme"]').onclick = () => $("themeBtn").click();
      rail.querySelector('[data-side-act="exit"]').onclick = () => this.setFull(false);
    },

    /** One section beside the full-screen chart (the same section again closes it). */
    openSide(k) {
      this.sideTab = this.sideTab === k ? null : k;
      this.renderTabs();
      this.renderSideRail();
      if (this.sideTab) this.loadTab(true, this.sideTab);
      this.fitFull();
    },

    /** Under the full-screen chart: how far back to show, and the clock. */
    renderRangeBar() {
      const bar = $("rangeBar");
      if (!bar || bar.dataset.ready) return;
      bar.dataset.ready = "1";
      const RANGES = [["1Ngày", 1], ["5Ngày", 5], ["1Tháng", 30], ["3Tháng", 91], ["6Tháng", 182], ["YTD", "ytd"], ["1Năm", 365], ["Tất cả", "all"]];
      bar.innerHTML = RANGES.map(([n, d]) => `<button type="button" data-days="${d}">${n}</button>`).join("") + `<span class="clock" id="tvClock"></span>`;
      bar.querySelectorAll("[data-days]").forEach((b) => (b.onclick = () => this.showRange(b.dataset.days)));
    },

    /** The last `days` days of the loaded bars on screen (all of them when fewer are loaded). */
    showRange(days) {
      const bars = this.viewBars();
      if (!bars.length || !this.chart) return;
      const sec = TF_SECONDS[this.interval], last = bars[bars.length - 1].time;
      let from;
      if (days === "all") from = bars[0].time;
      else if (days === "ytd") from = Date.UTC(new Date(last * 1000).getUTCFullYear(), 0, 1) / 1000;
      else from = last - +days * 86400;
      let a = timeToIndex(bars, Math.max(from, bars[0].time), sec);
      if (from < bars[0].time) toast(`Đang có dữ liệu từ ${this.timeLabel(bars[0].time)}: hiện tất cả nến đã tải`);
      a = Math.max(0, Math.floor(a));
      this.chart.timeScale().setVisibleLogicalRange({ from: a, to: bars.length - 1 + 5 });
    },

    /** TradingView's line over the chart: symbol, timeframe, and the bar under the cursor (or the last one). */
    updateLegend() {
      const el = $("tvLegend");
      if (!el || !document.body.classList.contains("chart-full")) return;
      const bars = this.viewBars();
      const b = this.legendBar || bars[bars.length - 1];
      if (!b) { el.innerHTML = ""; return; }
      const d = this.digits, chg = b.close - b.open, pct = b.open ? (chg / b.open) * 100 : 0, cls = chg >= 0 ? "up" : "dn";
      el.innerHTML = `<b>${esc($("chartSymbol").textContent)} · ${esc(this.interval)}</b>`
        + `<span>O <span class="${cls}">${fmt(b.open, d)}</span></span><span>H <span class="${cls}">${fmt(b.high, d)}</span></span>`
        + `<span>L <span class="${cls}">${fmt(b.low, d)}</span></span><span>C <span class="${cls}">${fmt(b.close, d)}</span></span>`
        + `<span class="${cls}">${chg >= 0 ? "+" : "−"}${fmt(Math.abs(chg), d)} (${chg >= 0 ? "+" : "−"}${Math.abs(pct).toFixed(2)}%)</span>`;
    },

    updateClock() {
      const el = $("tvClock");
      if (!el) return;
      const now = new Date(), off = -now.getTimezoneOffset() / 60, p = (n) => String(n).padStart(2, "0");
      el.textContent = `${p(now.getHours())}:${p(now.getMinutes())}:${p(now.getSeconds())} UTC${off >= 0 ? "+" : "−"}${Math.abs(off)}`;
    },

    /** "Báo khi giá phá High/Low": the newest candle crossed PDH / PDL / PWH… (once per level, live only). */
    alertPeriodBreaks() {
      if (!this.ictCfg.dwmAlert || this.replay || !this.ict) return;
      const list = this.ict.periodBreaks || [];
      // A new symbol or timeframe: the first pass only remembers what is already broken.
      const chart = `${$("chartSymbol").textContent}|${this.interval}`;
      if (chart !== this.periodAlertChart) { this.periodAlertChart = chart; this.periodAlerted = new Set(); this.periodAlertReady = false; }
      list.forEach((b) => {
        const key = `${b.label}|${b.price}`;
        if (this.periodAlerted.has(key)) return;
        this.periodAlerted.add(key);
        if (!this.periodAlertReady) return;
        const p = fmt(b.price, this.digits);
        Voice.alert(`${b.label} ${b.high ? "bị phá lên" : "bị phá xuống"}`, `Phá ${b.label}`, `Giá ${b.high ? "vượt lên trên" : "xuống dưới"} ${b.label} ${p}`, b.high);
      });
      this.periodAlertReady = true;
    },

    /** "mm:ss" (or "h:mm:ss") until the current bar closes. */
    /** The live bid/ask for the ask line and spread band: Exness quotes on the chart's own symbol, outside replay. */
    spreadQuote() {
      if (!this.chartStyle.askLine || this.replay || this.bid == null || this.ask == null) return null;
      if (this.source !== "exness" && !this.secFeed) return null;
      const { bid, ask } = this;
      if (!(ask > bid) || ask - bid > bid * 0.01) return null;
      return { bid, ask };
    },

    /** The spread on the chart: the bid and the ask as two faint dotted lines in their own colours,
     *  so a sell's SL / a buy's TP can be set knowing they trigger on the ask. */
    drawSpread(g, width) {
      const q = this.spreadQuote();
      this.showSeriesPrice(!q);
      if (!q) return;
      const st = this.chartStyle;
      const line = (price, color) => {
        const yy = this.series.priceToCoordinate(price);
        if (yy == null) return;
        const y = Math.round(yy) + 0.5;
        g.strokeStyle = rgba(color, 0.55);
        g.beginPath(); g.moveTo(0, y); g.lineTo(width, y); g.stroke();
      };
      g.save();
      g.lineWidth = 1; g.setLineDash([2, 3]);
      line(q.bid, (st.bidColor || "#f0455a").slice(0, 7));
      line(q.ask, (st.askColor || "#2b6bf3").slice(0, 7));
      g.restore();
    },

    /** Red and orange USD news on the chart: a dashed line at the release time (ahead of the last bar for
     *  the ones to come) with a flag at the bottom: the time and a short name. */
    drawNews(g, width, height) {
      if (!showInd.news || !this.news || this.replay) return;
      const bars = this.viewBars(), sec = TF_SECONDS[this.interval] || 60;
      if (!bars.length) return;
      const ts = this.chart.timeScale(), from = bars[0].time, nowS = Date.now() / 1000;
      g.save();
      g.font = "600 10px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
      g.textBaseline = "middle";
      const placed = [];
      this.newsDots = [];
      this.goldEvents(2).forEach((e) => {
        if (e.time < from || e.time > nowS + 3 * 86400) return;
        // Between two bars (the chart only places whole bar numbers), ahead of the last for news to come.
        const l = timeToIndex(bars, e.time, sec), i = Math.floor(l);
        const x0 = ts.logicalToCoordinate(i), x1 = ts.logicalToCoordinate(i + 1);
        if (x0 == null || x1 == null) return;
        const x = x0 + (l - i) * (x1 - x0);
        if (x < 0 || x > width) return;
        const color = e.impact === "High" ? "#f0455a" : "#f5a524", xx = Math.round(x) + 0.5;
        if (e.time < nowS - 900) {
          // Over: a small round dot at the release time (a tap shows the news), no line across the chart.
          const y = height - 10;
          g.beginPath(); g.arc(xx, y, 5, 0, Math.PI * 2); g.fillStyle = color; g.fill();
          g.lineWidth = 1.5; g.strokeStyle = document.documentElement.dataset.theme === "light" ? "#ffffff" : "#050506"; g.stroke();
          this.newsDots.push({ x: xx, y, e });
          return;
        }
        g.strokeStyle = rgba(color, e.time > nowS ? 0.75 : 0.45); g.lineWidth = 1; g.setLineDash([3, 3]);
        g.beginPath(); g.moveTo(xx, 0); g.lineTo(xx, height); g.stroke();
        g.setLineDash([]);
        // The flag: "19:30 Non-Farm Empl…", stacked up when two sit close.
        const name = e.title.length > 20 ? e.title.slice(0, 19) + "…" : e.title;
        const text = `${clock(e.time)} ${name}`, tw = g.measureText(text).width + 16;
        let y = height - 14;
        while (placed.some((p) => Math.abs(p.x - x) < p.w && Math.abs(p.y - y) < 18)) y -= 18;
        placed.push({ x, y, w: tw });
        const left = Math.min(Math.max(2, x - 6), width - tw - 2);
        g.fillStyle = rgba(color, 0.92);
        g.beginPath(); g.roundRect(left, y - 8, tw, 16, 4); g.fill();
        g.fillStyle = "#ffffff";
        g.beginPath(); g.arc(left + 7, y, 2.5, 0, Math.PI * 2); g.fill();
        g.fillText(text, left + 12, y + 0.5);
      });
      g.restore();
    },

    /** One past news from its dot on the chart: the time, the figures, what they meant and gold's move. */
    newsSheet(e) {
      const v = this.newsVerdict(e), r = this.reaction(e);
      const row = (k, val) => `<div class="kv"><span>${k}</span><b>${val}</b></div>`;
      sheet.open(`<h3><span class="dot ${e.impact === "High" ? "high" : "med"}"></span> ${esc(e.title)}</h3>
        <p class="muted small">USD · ${e.impact === "High" ? "Tin đỏ" : "Tin cam"} · ${fullTime(e.time)}</p>
        <div class="kvs">
          ${row("Thực tế", esc(e.actual || "–"))}${row("Dự báo", esc(e.forecast || "–"))}${row("Kỳ trước", esc(e.previous || "–"))}
          ${v ? row("Ý nghĩa", `<span class="${v.cls}">${esc(v.text)}</span>`) : ""}
          ${r ? row("Vàng sau tin (15 phút)", `<span class="${r.move >= 0 ? "pos" : "neg"}">${signed(r.move)}</span>`) : ""}
        </div>`);
    },

    /** What a figure means for gold: before the release the forecast against the previous one, after it the
     *  actual against the forecast. A stronger US figure is good for the dollar, so bad for gold (for
     *  unemployment and jobless claims a lower figure is the stronger one). */
    newsVerdict(e) {
      const num = (v) => {
        const m = String(v || "").replace(",", ".").match(/-?\d+(\.\d+)?/);
        if (!m) return null;
        let x = +m[0];
        if (/k\b/i.test(v)) x *= 1e3; else if (/m\b/i.test(v)) x *= 1e6; else if (/b\b/i.test(v)) x *= 1e9;
        return x;
      };
      const out = !!String(e.actual || "").trim();
      const a = num(out ? e.actual : e.forecast), b = num(out ? e.forecast : e.previous);
      if (a == null || b == null) return null;
      if (a === b) return { text: out ? "đúng dự báo" : "như kỳ trước", cls: "muted" };
      const lowerBetter = /unemployment|claims|jobless/i.test(e.title);
      const usd = lowerBetter ? a < b : a > b;
      return { text: usd ? "tốt USD → xấu cho vàng" : "xấu USD → tốt cho vàng", cls: usd ? "neg" : "pos", out };
    },

    /** Under the timeframes at the right, one short row per news of the day (red and yellow USD news, or the
     *  next day that has some): time, a short name, its own countdown (or how long ago), and ▲ / ▼ for gold
     *  by the forecast (then the result). The figures are in the tooltip; a tap opens News. */
    /** "Thông báo phiên": which sessions, how long before the open the row shows, how long it stays after,
     *  the alert before the open and before the close, and the voice. */
    sessDefaults() { return { on: true, asia: true, eu: true, ny: true, showBefore: 60, before: 15, after: 5, endBefore: 15, voice: true, popup: true }; },
    sessCfg() {
      if (!this.sessNotice) {
        try { this.sessNotice = Object.assign(this.sessDefaults(), JSON.parse(store.get("aurum.sessNotice") || "{}")); } catch { this.sessNotice = this.sessDefaults(); }
        if (Voice.cfg.sessions === false && store.get("aurum.sessNotice") == null) this.sessNotice.on = false;
      }
      return this.sessNotice;
    },
    sessSettingsSheet() {
      sheet.close();
      const cfg = this.sessCfg();
      const mins = (arr) => arr.map((v) => [v, v ? `${v} phút` : "Không"]);
      const render = () => {
        const { tog, sel, head, note } = fieldKit(cfg);
        return head("Thông báo phiên") + tog("on", "Bật thông báo mở / đóng phiên")
          + tog("asia", "🌏 Phiên Á — Tokyo 09:00–15:30 (07:00–13:30 VN)")
          + tog("eu", "🌍 Phiên Âu — London 08:00–16:30 (15:00–23:30 VN mùa đông)")
          + tog("ny", "🗽 Phiên New York — chứng khoán Mỹ 09:30–16:00 (21:30–04:00 VN mùa đông)")
          + head("Khi nào hiện")
          + sel("showBefore", "Hiện dòng đếm ngược trước giờ mở", mins([15, 30, 60, 120]))
          + sel("after", "Giữ dòng sau khi mở rồi tự ẩn", mins([1, 3, 5, 10, 15]))
          + sel("before", "Báo trước giờ mở", mins([0, 5, 10, 15, 30]))
          + sel("endBefore", "Báo sắp kết thúc phiên (trước giờ đóng)", mins([0, 5, 10, 15, 30]))
          + head("Cách báo") + tog("voice", "Đọc bằng giọng tiếng Anh") + tog("popup", "Hiện thông báo trên trang")
          + note("Giờ mở / đóng theo giờ của từng sàn chứng khoán, tự đổi khi Âu / Mỹ đổi giờ mùa hè. Chỉ Thứ 2 – Thứ 6.");
      };
      const open = () => this.openPanel("Thông báo phiên", [["s", "Cài đặt"]], render, {
        root: cfg,
        onChange: () => { store.set("aurum.sessNotice", JSON.stringify(cfg)); this.renderNewsStrip(); },
        onReset: () => { Object.assign(cfg, this.sessDefaults()); store.set("aurum.sessNotice", JSON.stringify(cfg)); open(); },
      });
      open();
    },

    /** The opens and closes of the Asian, European and New York sessions near now (each in its own city's
     *  clock, so summer time moves them by itself), Monday to Friday there. */
    sessionEvents(nowS) {
      const SESS = [
        { key: "asia", name: "Á", en: "Asian", icon: "🌏", tz: "Asia/Tokyo", open: [9, 0], close: [15, 30] },
        { key: "eu", name: "Âu", en: "London", icon: "🌍", tz: "Europe/London", open: [8, 0], close: [16, 30] },
        { key: "ny", name: "New York", en: "New York", icon: "🗽", tz: "America/New_York", open: [9, 30], close: [16, 0] }, // the US stock market
      ];
      const off = (tz, t) => (window.ICT && window.ICT.offsetSeconds ? window.ICT.offsetSeconds(t, tz) : 0);
      const cfg = this.sessCfg(), out = [];
      for (const s of SESS) {
        if (cfg[s.key] === false) continue;
        for (let d = -1; d <= 2; d++) {
          const local = new Date((nowS + off(s.tz, nowS)) * 1000 + d * 86400000);
          const wd = local.getUTCDay();
          if (wd === 0 || wd === 6) continue;
          const at = ([h, m]) => { const g = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate(), h, m) / 1000; return g - off(s.tz, g - off(s.tz, g)); };
          out.push(Object.assign({ kind: "open", time: at(s.open) }, s), Object.assign({ kind: "close", time: at(s.close) }, s));
        }
      }
      return out.filter((x) => x.time > nowS - 3600 && x.time < nowS + 86400).sort((a, b) => a.time - b.time);
    },

    /** Rows over the news: the countdown to an open (until a few minutes after it), and the coming close;
     *  alerts before the open, at the open and before the close. */
    sessionRow(nowS) {
      const cfg = this.sessCfg();
      if (!cfg.on) return "";
      const vnHM = (t) => new Date((t + 7 * 3600) * 1000).toISOString().slice(11, 16);
      const list = this.sessionEvents(nowS);
      this.sessAlerted = this.sessAlerted || new Set();
      const say = (id, spoken, title, body) => {
        if (this.sessAlerted.has(id)) return;
        this.sessAlerted.add(id);
        if (cfg.voice) Voice.speak(spoken, false, undefined, "en-US");
        if (cfg.popup) toast(`${title}: ${body}`);
        if (Voice.cfg.notify && document.hidden && window.Notification && Notification.permission === "granted") {
          try { new Notification(title, { body, icon: "favicon.svg" }); } catch { /* not allowed */ }
        }
      };
      for (const x of list) {
        const left = x.time - nowS, id = x.key + ":" + x.kind + ":" + Math.round(x.time);
        if (x.kind === "open") {
          if (cfg.before > 0 && left <= cfg.before * 60 && left > cfg.before * 60 - 60) say(id + ":b", `${x.en} session opens in ${cfg.before} minutes`, `${x.icon} Sắp vào phiên ${x.name}`, `mở lúc ${vnHM(x.time)} (giờ VN) · còn ${cfg.before} phút`);
          if (left <= 0 && left > -60) say(id + ":0", `${x.en} session is open`, `${x.icon} Phiên ${x.name} đã mở`, `${vnHM(x.time)} giờ VN`);
        } else if (cfg.endBefore > 0 && left <= cfg.endBefore * 60 && left > cfg.endBefore * 60 - 60) {
          say(id + ":e", `${x.en} session closes in ${cfg.endBefore} minutes`, `${x.icon} Sắp kết thúc phiên ${x.name}`, `đóng lúc ${vnHM(x.time)} (giờ VN) · còn ${cfg.endBefore} phút`);
        }
      }
      const two = (n) => String(n).padStart(2, "0"), cdOf = (sec) => `${Math.floor(sec / 60)}:${two(Math.floor(sec % 60))}`;
      const rows = list.filter((x) => x.kind === "open"
        ? x.time - nowS <= (cfg.showBefore || 60) * 60 && nowS - x.time < (cfg.after || 5) * 60
        : cfg.endBefore > 0 && x.time - nowS <= cfg.endBefore * 60 && x.time > nowS).slice(0, 2);
      return rows.map((x) => {
        const left = x.time - nowS;
        if (x.kind === "close") {
          return `<div class="ns-sess ${x.key} ending" title="Phiên ${x.name} đóng lúc ${vnHM(x.time)} giờ VN">
            <span>${x.icon}</span><b>Sắp kết thúc phiên ${x.name}</b><span class="muted">${vnHM(x.time)}</span><span class="cd">còn ${cdOf(left)}</span></div>`;
        }
        const cd = left > 0 ? `còn ${cdOf(left)}` : `đã mở ${Math.floor(-left / 60)}′`;
        return `<div class="ns-sess ${x.key}${left > 0 && left <= 900 ? " soon" : ""}${left <= 0 ? " open" : ""}" title="Phiên ${x.name} mở lúc ${vnHM(x.time)} giờ VN">
          <span>${x.icon}</span><b>${left > 0 ? "Sắp vào phiên" : "Phiên"} ${x.name}</b><span class="muted">${vnHM(x.time)}</span><span class="cd">${cd}</span></div>`;
      }).join("");
    },

    renderNewsStrip() {
      const box = $("newsStrip");
      if (!box) return;
      const nowS = Date.now() / 1000;
      const sess = this.replay ? "" : this.sessionRow(nowS);
      const all = showInd.news && this.news && !this.replay ? this.goldEvents(2) : [];
      const dayOf = (t) => new Date(t * 1000).toDateString();
      // Today's still to come (or out less than 15 minutes ago), else the next day with news; 5 rows at most.
      let list = all.filter((e) => dayOf(e.time) === dayOf(nowS) && e.time > nowS - 900);
      if (!list.some((e) => e.time > nowS)) {
        const next = all.find((e) => e.time > nowS);
        if (next) list = list.concat(all.filter((e) => dayOf(e.time) === dayOf(next.time) && e.time > nowS));
      }
      // The red news from 1 minute before it comes out until 15 minutes after: a card on top with the
      // countdown, then how gold took it (TỐT / XẤU from the move since the release).
      // The card from 1 minute before the release until 1 minute after it, then gone.
      const live = this.goldEvents(3).find((e) => nowS >= e.time - 60 && nowS <= e.time + 60);
      if (live) list = list.filter((e) => e !== live);
      list = list.slice(0, 5);
      box.hidden = !list.length && !live && !sess;
      if (box.hidden) return;
      const two = (n) => String(n).padStart(2, "0");
      const left = (sec) => { const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), x = Math.floor(sec % 60); return h ? `${h}:${two(m)}:${two(x)}` : `${m}:${two(x)}`; };
      const day = (t) => (dayOf(t) === dayOf(nowS) ? "" : new Date(t * 1000).toLocaleDateString("vi-VN", { weekday: "short" }) + " ");
      const sec = TF_SECONDS[this.interval] || 60;
      let card = "";
      if (live) {
        let line;
        if (nowS < live.time) line = `<span class="muted">Sắp ra tin · chờ phản ứng giá</span>`;
        else {
          const i = this.bars.findIndex((b) => b.time + sec > live.time);
          const ref = i >= 0 ? this.bars[i].open : null;
          const price = this.bid != null ? this.bid : this.bars.length ? this.bars[this.bars.length - 1].close : null;
          const verdict = price != null ? this.verdict(ref != null ? price - ref : null, price) : { text: "Đang đo phản ứng giá…", cls: "" };
          line = `<b class="${verdict.cls}">${esc(verdict.text)}</b>`;
        }
        const t = live.time - nowS, when = t > 0 ? `còn ${Math.ceil(t)}s` : `${Math.floor(-t / 60) ? Math.floor(-t / 60) + "′ " : ""}${Math.floor(-t % 60)}s`;
        card = `<div class="ns-live${t > 0 ? " soon" : ""}" title="${esc(live.title)}"><div>📰 <b>${esc(live.title)}</b> <span class="muted">${when}</span></div><div>${line}</div></div>`;
      }
      box.innerHTML = sess + card + list.map((e) => {
        const v = this.newsVerdict(e), soon = e.time > nowS && e.time - nowS < 900;
        const when = e.time > nowS ? left(e.time - nowS) : `✓ ${Math.max(0, Math.round((nowS - e.time) / 60))}′`;
        const tip = `${e.title} · Dự báo ${e.forecast || "–"} · Trước ${e.previous || "–"}${e.actual ? " · Thực tế " + e.actual : ""}${v ? " · " + v.text : ""}`;
        const name = e.title.replace(/\s+(m\/m|q\/q|y\/y)$/i, "").replace(/^Advance\s+/i, "");
        return `<div class="ns ${e.impact === "High" ? "red" : "yellow"}${soon ? " soon" : ""}${e.time <= nowS ? " past" : ""}" title="${esc(tip)}">
          <span class="dot"></span><b>${day(e.time)}${clock(e.time).slice(0, 5)}</b><span class="nm">${esc(name.length > 16 ? name.slice(0, 15) + "…" : name)}</span>
          <span class="cd">${when}</span>${v && v.cls !== "muted" ? `<span class="vd ${v.cls}">${v.cls === "pos" ? "▲" : "▼"}</span>` : ""}</div>`;
      }).join("");
      box.querySelectorAll(".ns").forEach((b) => (b.onclick = () => this.setTab("news")));
    },

    /** The candle's own last-price line and label, hidden while the bid / ask lines stand in for them. */
    showSeriesPrice(on) {
      if (this.seriesPriceOn === on) return;
      this.seriesPriceOn = on;
      // Not inside the chart's own paint: apply on the next frame.
      requestAnimationFrame(() => this.series && this.series.applyOptions({ priceLineVisible: on, lastValueVisible: on }));
    },

    countdownText() {
      const b = this.bars[this.bars.length - 1];
      if (!b) return "";
      const left = Math.max(0, Math.round(b.time + TF_SECONDS[this.interval] - Date.now() / 1000));
      const h = Math.floor(left / 3600), m = Math.floor((left % 3600) / 60), sec = left % 60;
      const two = (v) => String(v).padStart(2, "0");
      return h ? `${h}:${two(m)}:${two(sec)}` : `${two(m)}:${two(sec)}`;
    },

    /** The chart's own layer (ICT, shark zones, spread, news, alerts, trade lines): the main chart's, or an
     *  extra timeframe's through a view of this terminal on that chart and its bars. */
    layer() {
      const term = this;
      // ICT layer: painted in the chart's own frame (under the candles), so it never lags a drag.
      return {
        attached(p) { term.requestICT = p.requestUpdate; },
        detached() {},
        updateAllViews() {},
        paneViews() {
          return [{
            zOrder: () => "bottom",
            renderer: () => ({
              draw: (target) => target.useMediaCoordinateSpace(({ context, mediaSize }) => withPop(context, () => {
                const ts = term.chart.timeScale();
                const X = (i) => ts.logicalToCoordinate(i), Y = (v) => term.series.priceToCoordinate(v);
                if (term.ict) window.ICT.draw(context, term.ict, term.ictCfg, X, Y, mediaSize.width, mediaSize.height);
                if (term.models && window.MODELS) window.MODELS.draw(context, term.models, term.modelCfg, X, Y, mediaSize.width, mediaSize.height, (v) => fmt(v, term.digits));
                const W = mediaSize.width, H = mediaSize.height, F = (v) => fmt(v, term.digits);
                if (term.macro && window.MACRO) window.MACRO.draw(context, term.macro, term.macroCfg, (t) => term.timeX(t), W, H);
                if (term.liq && window.LIQ) window.LIQ.draw(context, term.liq, term.liqCfg, (t) => term.timeX(t), Y, mediaSize.width, mediaSize.height, (v) => fmt(v, term.digits));
                if (term.plan && window.PLAN) window.PLAN.draw(context, term.plan, term.planCfg, (t) => term.timeX(t), X, Y, mediaSize.width, mediaSize.height, (v) => fmt(v, term.digits));
                if (term.smt) window.ICT.drawSMT(context, term.smt, X, Y, mediaSize.width, { bull: term.ictCfg.smtBull, bear: term.ictCfg.smtBear });
                term.drawSharkZones(context, mediaSize.width, false);
                term.drawSpread(context, mediaSize.width);
                term.drawNews(context, mediaSize.width, mediaSize.height);
                term.drawAlerts(context, mediaSize.width);
                if (!term.isPane) { term.placeMascotsSoon(); term.placeCrewSoon(); }
              })),
            }),
          }, {
            // Shark bubbles over the candles, like the app.
            zOrder: () => "top",
            renderer: () => ({
              draw: (target) => target.useMediaCoordinateSpace(({ context, mediaSize }) => withPop(context, () => {
                term.drawSharkZones(context, mediaSize.width, true);
                // The TTrades panel over the candles, so they never cross its text.
                if (term.models && window.MODELS && window.MODELS.drawPanelOnly) window.MODELS.drawPanelOnly(context, term.models, term.modelCfg, mediaSize.width, mediaSize.height);
                if (term.macro && window.MACRO) window.MACRO.drawStatus(context, term.macro, term.macroCfg, mediaSize.width);
                if (term.liq && window.LIQ) window.LIQ.drawPanel(context, term.liq, term.liqCfg, mediaSize.width, mediaSize.height);
                if (term.plan && window.PLAN) window.PLAN.drawPanel(context, term.plan, term.planCfg, mediaSize.width, mediaSize.height);
                if (!term.sharks) return;
                const ts = term.chart.timeScale();
                const sc = term.sharkColors();
                window.ICT.drawSharks(context, term.sharksShown(term.sharks), term.viewBars(), (i) => ts.logicalToCoordinate(i), (v) => term.series.priceToCoordinate(v),
                  mediaSize.width, sc.buy, sc.sell, sc.bubble);
              })),
            }),
          }, {
            zOrder: () => "top",
            renderer: () => ({
              draw: (target) => target.useMediaCoordinateSpace(({ context, mediaSize }) => withCrisp(context, () => term.drawTradeLines(context, mediaSize.width))),
            }),
          }];
        },
        // Open positions: dotted entry line from the entry candle, a dot on it, side and money label.
        // (a third pane view, above the candles)
        priceAxisViews() { return term.countdownView ? [term.bidView, term.askView, term.countdownView] : []; },
      };
    },

    /** Bid, ask and the bar countdown on the price axis. */
    axisViews() {
      // The ask on the price axis, kept clear of the bid label just under it.
      const askView = {
        coordinate: () => {
          const q = this.spreadQuote();
          if (!q) return -100;
          const ya = this.series.priceToCoordinate(q.ask), yb = this.series.priceToCoordinate(q.bid);
          return ya == null || yb == null ? -100 : Math.min(ya, yb - 19);
        },
        text: () => { const q = this.spreadQuote(); return q ? fmt(q.ask, this.digits) : ""; },
        textColor: () => "#ffffff",
        backColor: () => this.chartStyle.askColor || "#2b6bf3",
        visible: () => !!this.spreadQuote(),
        tickVisible: () => false,
      };
      // The bid in its own colour, in place of the candle's last price (hidden while the bid / ask show).
      const bidView = {
        coordinate: () => { const q = this.spreadQuote(), y = q ? this.series.priceToCoordinate(q.bid) : null; return y == null ? -100 : y; },
        text: () => { const q = this.spreadQuote(); return q ? fmt(q.bid, this.digits) : ""; },
        textColor: () => "#ffffff",
        backColor: () => this.chartStyle.bidColor || "#f0455a",
        visible: () => !!this.spreadQuote(),
        tickVisible: () => false,
      };
      const countdownView = {
        coordinate: () => {
          const v = this.viewBars(), b = v[v.length - 1], q = this.spreadQuote();
          const y = b ? this.series.priceToCoordinate(q ? q.bid : b.close) : null;
          return y == null ? -100 : y + 19;
        },
        text: () => this.countdownText(),
        textColor: () => "#ffffff",
        backColor: () => { const v = this.viewBars(), b = v[v.length - 1]; return b && b.close < b.open ? this.chartStyle.down : this.chartStyle.up; },
        visible: () => !this.replay && this.bars.length > 0 && (this.source === "exness" || !!this.secFeed),
        tickVisible: () => false,
      };
      return { askView, bidView, countdownView };
    },

    /* ----- layout: one chart, or two side by side / stacked with SMT ----- */

    layoutMenu(button) {
      const r = button.getBoundingClientRect();
      const items = [["1", "▭ 1 biểu đồ"], ["h", "◫ 2 mã ngang"], ["v", "⊟ 2 mã dọc (trên – dưới)"],
        ["m2", "◫ 1 mã · 2 khung time"], ["m3", "◧ 1 mã · 3 khung time"], ["m4", "⊞ 1 mã · 4 khung time"]].map(([k, n]) => [k, (this.layout === k ? "✓ " : "　") + n]);
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

    /** A double-click that belongs to something else: a button or panel over the chart, a drawing being made. */
    /* ----- timeframe ring (MT5's): a tap on the chart, then a tap on a timeframe ----- */

    /** Shown a moment after the tap, so a double click (2 charts) does not open it. */
    tfRingSoon(cx, cy) {
      if ((this.chartStyle || {}).tfRing === false) return;
      clearTimeout(this.tfRingTimer);
      // At once: a double click closes it again with its second press (and opens the 2 charts).
      this.tfRingTimer = setTimeout(() => this.openTfRing(cx, cy), 0);
    },

    openTfRing(cx, cy) {
      let el = $("tfRing");
      if (!el) { el = document.createElement("div"); el.id = "tfRing"; el.className = "tf-ring"; document.body.appendChild(el); }
      const tfs = [["1m", "M1"], ["5m", "M5"], ["15m", "M15"], ["30m", "M30"], ["1h", "H1"], ["4h", "H4"], ["1d", "D1"]];
      const R = 68, size = 180, c = size / 2;
      const at = (deg) => { const r = (deg - 90) * Math.PI / 180; return [c + R * Math.cos(r), c + R * Math.sin(r)]; };
      // 11 even places round the ring: the timeframes over the top (M30 at the top), the tools at the bottom.
      const ic = (d) => `<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
      const toolList = [
        ["ind", "ƒ", "Chỉ báo"],
        ["h", ic('<rect x="3" y="5" width="8" height="14" rx="1.5"/><rect x="13" y="5" width="8" height="14" rx="1.5"/>'), "2 mã ngang (trái – phải), SMT"],
        ["v", ic('<rect x="4" y="3" width="16" height="8" rx="1.5"/><rect x="4" y="13" width="16" height="8" rx="1.5"/>'), "2 mã dọc (trên – dưới), SMT"],
        ["set", ic('<path d="M5 4v16M12 4v16M19 4v16"/><circle cx="5" cy="9" r="2" fill="currentColor"/><circle cx="12" cy="15" r="2" fill="currentColor"/><circle cx="19" cy="8" r="2" fill="currentColor"/>'), "Cài đặt biểu đồ"],
      ];
      const all = tfs.length + toolList.length, step = 360 / all, start = 180 - (tfs.length + (toolList.length - 1) / 2) * step;
      const items = tfs.map(([tf, name], i) => { const [x, y] = at(start + step * i);
        return `<button type="button" data-tf="${tf}" class="${tf === this.interval ? "on" : ""}" style="left:${x}px;top:${y}px">${name}</button>`; });
      const tools = toolList.map(([k, icon, title], j) => { const [x, y] = at(start + step * (tfs.length + j));
        const on = (k === "h" || k === "v") && this.layout === k;
        return `<button type="button" data-k="${k}" class="tool${on ? " on" : ""}" title="${title}" style="left:${x}px;top:${y}px">${icon}</button>`; });
      el.innerHTML = items.join("") + tools.join("");
      el.style.setProperty("--ring", (this.chartStyle && this.chartStyle.ringColor) || "#4068f6");
      const left = Math.max(6, Math.min(window.innerWidth - size - 6, cx - c)), top = Math.max(6, Math.min(window.innerHeight - size - 6, cy - c));
      el.style.left = left + "px"; el.style.top = top + "px";
      el.hidden = false;
      el.classList.remove("open"); void el.offsetWidth; // the closed look first, so the turn in plays every time
      el.classList.add("open");
      el.onpointerdown = (e) => e.stopPropagation();
      el.onclick = (e) => {
        const b = e.target.closest("button");
        this.closeTfRing();
        if (!b) return;
        if (b.dataset.tf) {
          if (b.dataset.tf === this.interval) return;
          if (this.replay && isSecTF(b.dataset.tf)) return;
          this.interval = b.dataset.tf; store.set("aurum.tf", this.interval); this.loadCandles();
        } else if (b.dataset.k === "ind") this.indicatorSheet();
        else if (b.dataset.k === "set") this.chartStyleSheet();
        else if (b.dataset.k === "h" || b.dataset.k === "v") {
          // The 2-chart layout (SMT) that way, or back to one chart when it is already open.
          if (this.layout === b.dataset.k) { this.setLayout("1"); return; }
          if (!showInd.smt) { showInd.smt = true; store.set("aurum.ind", JSON.stringify(showInd)); }
          store.set("aurum.pairMode", b.dataset.k);
          this.setLayout(b.dataset.k);
        }
      };
      if (!this.tfRingKeys) {
        this.tfRingKeys = true;
        document.addEventListener("keydown", (e) => { if (e.key === "Escape") this.closeTfRing(); });
        document.addEventListener("pointerdown", (e) => { if (!e.target.closest("#tfRing") && !e.target.closest("#chartWrap")) this.closeTfRing(); }, true);
        window.addEventListener("wheel", () => this.closeTfRing(), { passive: true });
      }
    },

    /** Closes the ring; true when it was open. */
    closeTfRing() {
      clearTimeout(this.tfRingTimer);
      const el = $("tfRing");
      if (!el || el.hidden) return false;
      el.hidden = true; el.classList.remove("open");
      return true;
    },

    chartDblBusy(e) {
      if (e && e.target && e.target.closest && e.target.closest("#ticket, #ticket2, #selBar, #posPill, #drawBar, #favBar, #draftBar, #btChip, .mascot, .c2-head, .quick-trade, button, input, select")) return true;
      const dr = this.drawings;
      return !!(dr && (dr.pending || dr.tool)) || !!this.replayPicking;
    },

    /** One chart ⇄ two markets (gold / silver) with the SMT on; the 2-chart layout last used comes back. */
    togglePairLayout() {
      this.closeTfRing();
      if (this.pair()) {
        store.set("aurum.pairMode", this.layout);
        this.setLayout("1");
        return;
      }
      if (!showInd.smt) { showInd.smt = true; store.set("aurum.ind", JSON.stringify(showInd)); }
      const mode = store.get("aurum.pairMode") === "h" ? "h" : "v";
      this.setLayout(mode);
      if (!store.get("aurum.pairHint")) {
        store.set("aurum.pairHint", "1");
        toast("Đã mở 2 biểu đồ (SMT). Bấm đúp vào chart lần nữa để về 1 biểu đồ");
      }
    },

    setLayout(mode) {
      if (!LAYOUTS.includes(mode)) mode = "h";
      this.layout = mode;
      store.set("aurum.layout", mode);
      const many = mode[0] === "m";
      $("charts").className = "charts" + (mode === "h" ? " row" : mode === "v" ? " col" : many ? ` mtf ${mode}` : "");
      $("chartWrap2").hidden = !this.pair();
      $("layoutBtn").classList.toggle("on", mode !== "1");
      this.setPanes(many ? +mode[1] - 1 : 0);
      this.setupSplits();
      if (!this.pair()) { this.focusChart(1); this.loadCmp(); return; }
      this.ensureChart2();
      this.loadCmp();
    },

    /* ----- 2 / 3 / 4 timeframes: dividers between the charts, dragged to make one bigger ----- */

    /** The dividers' places (share of the width for the first column, of the height for the first row),
     *  kept per layout. */
    splitOf(mode) {
      let v = {};
      try { v = JSON.parse(store.get("aurum.split." + mode) || "{}"); } catch { /* even */ }
      const ok = (x) => (typeof x === "number" && x >= 0.12 && x <= 0.88 ? x : 0.5);
      return { c: ok(v.c), r: ok(v.r) };
    },

    setupSplits() {
      const box = $("charts"), mode = this.layout;
      box.querySelectorAll(".split").forEach((e) => e.remove());
      ["--c1", "--r1", "--c2", "--r2", "--cols", "--rows"].forEach((k) => box.style.removeProperty(k));
      // Every layout with more than one chart: 2 symbols side by side (a column divider), one above the
      // other (a row divider), or 2 / 3 / 4 timeframes.
      if (!mode || mode === "1") return;
      const sp = this.splitOf(mode);
      const mk = (dir) => {
        const e = document.createElement("div");
        e.className = "split split-" + dir;
        e.title = "Kéo để đổi cỡ các ô · bấm đúp để chia đều";
        e.innerHTML = "<i></i>";
        box.appendChild(e);
        return e;
      };
      const col = mode === "v" ? null : mk("col"), row = mode === "m2" || mode === "h" ? null : mk("row");
      const apply = () => {
        box.style.setProperty("--c1", sp.c);
        box.style.setProperty("--r1", sp.r);
        box.style.setProperty("--c2", 1 - sp.c);
        box.style.setProperty("--r2", 1 - sp.r);
        box.style.setProperty("--cols", `minmax(0, ${sp.c}fr) minmax(0, ${1 - sp.c}fr)`);
        box.style.setProperty("--rows", `minmax(0, ${sp.r}fr) minmax(0, ${1 - sp.r}fr)`);
        this.placeSplits();
      };
      const save = () => store.set("aurum.split." + mode, JSON.stringify({ c: +sp.c.toFixed(3), r: +sp.r.toFixed(3) }));
      const drag = (el, key) => {
        el.addEventListener("pointerdown", (e) => {
          e.preventDefault(); e.stopPropagation();
          el.setPointerCapture(e.pointerId);
          el.classList.add("on"); document.body.classList.add("splitting", key === "c" ? "split-x" : "split-y");
          const move = (ev) => {
            const r = box.getBoundingClientRect(), gap = parseFloat(getComputedStyle(box).columnGap) || 6;
            const v = key === "c" ? (ev.clientX - r.left - gap / 2) / (r.width - gap) : (ev.clientY - r.top - gap / 2) / (r.height - gap);
            sp[key] = Math.max(0.12, Math.min(0.88, v));
            apply();
          };
          const up = () => {
            el.classList.remove("on"); document.body.classList.remove("splitting", "split-x", "split-y");
            el.removeEventListener("pointermove", move); el.removeEventListener("pointerup", up); el.removeEventListener("pointercancel", up);
            save();
          };
          el.addEventListener("pointermove", move); el.addEventListener("pointerup", up); el.addEventListener("pointercancel", up);
        });
        el.addEventListener("dblclick", () => { sp[key] = 0.5; apply(); save(); });
      };
      if (col) drag(col, "c");
      if (row) drag(row, "r");
      apply();
      if (!this.splitWatch && window.ResizeObserver) {
        this.splitWatch = new ResizeObserver(() => this.placeSplits());
        this.splitWatch.observe(box);
      }
    },

    /** The dividers over the gaps between the charts (none on a phone, where the charts are stacked). */
    placeSplits() {
      const box = $("charts"), mode = this.layout;
      if (!mode || mode === "1") return;
      const w = box.clientWidth, h = box.clientHeight, cs = getComputedStyle(box);
      const gx = parseFloat(cs.columnGap) || 6, gy = parseFloat(cs.rowGap) || 6;
      const sp = this.splitOf(mode);
      const c = +box.style.getPropertyValue("--c1") || sp.c, r = +box.style.getPropertyValue("--r1") || sp.r;
      const x = (w - gx) * c + gx / 2, y = (h - gy) * r + gy / 2;
      const col = box.querySelector(".split-col"), row = box.querySelector(".split-row");
      if (col) Object.assign(col.style, { left: x + "px", top: "0px", height: h + "px" });
      // 3 charts: the main one fills the left column, so the row divider is only over the right one.
      if (row) Object.assign(row.style, { top: y + "px", left: (mode === "m3" ? x : 0) + "px", width: (mode === "m3" ? w - x : w) + "px" });
    },

    /** Two symbols on two charts (the SMT layouts). */
    pair() { return this.layout === "h" || this.layout === "v"; },

    /** The timeframes of the extra charts, kept between visits. */
    paneTfs() {
      let tfs = [];
      try { tfs = JSON.parse(store.get("aurum.mtf") || "[]"); } catch { /* defaults */ }
      return ["1h", "4h", "15m"].map((d, i) => (TF_SECONDS[tfs[i]] ? tfs[i] : d));
    },

    savePaneTfs() {
      const tfs = this.paneTfs();
      (this.panes || []).forEach((p, i) => (tfs[i] = p.tf));
      store.set("aurum.mtf", JSON.stringify(tfs));
    },

    /** `n` extra charts of the main chart's symbol, each on its own timeframe. */
    setPanes(n) {
      this.panes = this.panes || [];
      while (this.panes.length > n) this.panes.pop().destroy();
      if (!n || !window.LightweightCharts) { this.relinkDrawings(); return; }
      const tfs = this.paneTfs();
      while (this.panes.length < n) {
        const p = new TfPane(this, tfs[this.panes.length]);
        $("charts").appendChild(p.wrap);
        this.panes.push(p);
      }
      this.applyChartStyle();
      this.panes.forEach((p) => p.ensure());
      this.relinkDrawings();
    },

    /** Every chart's drawings know the others: a tool picked on one is ready on all (draw on any chart). */
    relinkDrawings() {
      const all = this.allDrawings();
      all.forEach((d) => d.link(all));
      const main = this.drawingsMain;
      if (main) all.forEach((d) => { if (d !== main && d.tool !== main.tool) { d.tool = main.tool; d.pending = null; } });
    },

    /** The picked extra chart's timeframe onto the main chart (drawings, orders), the main one's into it. */
    paneToMain(pane) {
      const tf = this.interval;
      this.interval = pane.tf; store.set("aurum.tf", this.interval);
      pane.tf = tf;
      this.savePaneTfs();
      this.loadCandles();
    },

    /** One crosshair over every timeframe: the bar holding the same moment on each chart. */
    /** Whether a crosshair move on `from` is the mouse's (to pass on to the other charts). The crosshair
     *  set on another chart fires its own move a moment later: passing that back made the mouse's chart
     *  jump to the other chart's candle. */
    crossReal(from, param) {
      if (param && param.point) {
        if (!param.sourceEvent) return false;
        this.crossOwner = from;
        return true;
      }
      if (this.crossOwner !== from) return false;
      this.crossOwner = null;
      return true;
    },

    crossFrom(from, param) {
      if (this.syncingCrosshair || !this.layout || this.layout[0] !== "m" || !this.panes || !this.panes.length) return;
      if (!this.crossReal(from, param)) return;
      this.syncingCrosshair = true;
      try {
        const t = param && param.point && param.time != null ? param.time - TZ : null;
        const charts = [{ chart: this.chart, series: this.series, bars: this.viewBars() }].concat(this.panes.map((p) => ({ chart: p.chart, series: p.series, bars: p.bars })));
        // The horizontal line follows the mouse's price on every timeframe (one symbol), not the candle's close.
        const src = charts.find((c) => c.chart === from);
        const price = t != null && src ? src.series.coordinateToPrice(param.point.y) : null;
        charts.forEach((c) => {
          if (c.chart === from) return;
          const b = t == null ? null : barAt(c.bars, t);
          try { if (b) c.chart.setCrosshairPosition(price != null ? price : b.close, b.time + TZ, c.series); else c.chart.clearCrosshairPosition(); } catch { /* not ready */ }
        });
      } finally { this.syncingCrosshair = false; }
    },

    pickCmp() {
      this.symbolSheet((sym) => { this.setCmpFor(this.symbol, sym); this.loadCmp(); });
    },

    /** The second chart's symbol: silver for gold (the SMT pair), or the one picked. */
    /** The market compared for the SMT: the one set by hand, else the usual pair of the chart's symbol
     *  (gold ⇄ silver, Nasdaq → S&P 500, Dow → S&P 500, S&P 500 → Nasdaq, BTC ⇄ ETH, EUR ⇄ GBP, AUD ⇄ NZD,
     *  WTI ⇄ Brent), with the broker's own prefix / suffix kept (USTECm → US500m). */
    cmpSymbol() {
      const sym = this.owner ? this.symbol || "XAUUSD" : $("chartSymbol").textContent || "XAUUSD";
      const own = this.owner && this.ictCfg && this.ictCfg.smtFor ? this.ictCfg.smtFor[sym] : "";
      return own || smtPair(sym) || sym;
    },

    /** The comparison market picked by hand for one chart symbol only (another symbol keeps its own pair). */
    setCmpFor(main, cmp) {
      const cfg = this.ictCfg;
      cfg.smtFor = Object.assign({}, cfg.smtFor || {});
      if (cmp && cmp !== smtPair(main)) cfg.smtFor[main] = cmp; else delete cfg.smtFor[main];
      cfg.smtSymbol = cfg.smtFor[main] || "";
      this.lastSmtSymbol = cfg.smtSymbol;
      this.saveIct();
    },

    ensureChart2() {
      if (this.chart2) return;
      const term = this;
      this.chart2 = LightweightCharts.createChart($("chart2"), {
        autoSize: true,
        kineticScroll: { mouse: true, touch: true },
        layout: { background: { color: "#050506" }, textColor: "#8b95a7", fontFamily: "-apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif" },
        rightPriceScale: { borderColor: "#1e1e23" },
        timeScale: { borderColor: "#1e1e23", timeVisible: true, secondsVisible: isSecTF(this.interval), rightOffset: 8 },
        localization: { timeFormatter: (t) => this.timeLabel(t) },
        crosshair: { mode: 0 },
      });
      this.series2 = this.chart2.addCandlestickSeries({ borderVisible: false });
      // SMT on the second chart too, at that market's highs and lows.
      this.series2.attachPrimitive({
        attached(p) { term.request2 = p.requestUpdate; }, detached() {}, updateAllViews() {},
        paneViews() {
          return [{ zOrder: () => "top", renderer: () => ({ draw: (target) => target.useMediaCoordinateSpace(({ context, mediaSize }) => withPop(context, () => {
            if (!term.smt || !term.cmpView) return;
            // Mapped onto the second chart's bars once per SMT result, not every frame.
            const c = term.smt2Cache;
            if (!c || c.smt !== term.smt || c.view !== term.cmpView) {
              const index = new Map(term.cmpView.map((b, i) => [b.time, i]));
              // The other market's own high / low of each SMT (found around the chart's swing).
              term.smt2Cache = { smt: term.smt, view: term.cmpView, list: term.smt.map((d) => {
                const i1 = index.get(d.bt1 != null ? d.bt1 : d.t1), i2 = index.get(d.bt2 != null ? d.bt2 : d.t2);
                if (i1 == null || i2 == null) return null;
                const a = term.cmpView[i1], b = term.cmpView[i2];
                return { bull: d.bull, start: i1, end: i2, p1: d.b1 != null ? d.b1 : d.bull ? a.low : a.high, p2: d.b2 != null ? d.b2 : d.bull ? b.low : b.high };
              }).filter(Boolean) };
            }
            const list = term.smt2Cache.list;
            const ts = term.chart2.timeScale();
            window.ICT.drawSMT(context, list, (i) => ts.logicalToCoordinate(i), (v) => term.series2.priceToCoordinate(v), mediaSize.width, { bull: term.ictCfg.smtBull, bear: term.ictCfg.smtBear });
          })) }) }];
        },
      });
      // Dragging either chart moves both.
      const link = (from, to) => from.timeScale().subscribeVisibleLogicalRangeChange((r) => {
        if (!r || !this.pair()) return;
        const locked = this.rangeLock && this.rangeLock.get(from);
        if (locked && performance.now() - locked < 120) return; // our own echo
        this.syncRange(from, to);
        // Scrolled back past the second chart's oldest bar: fetch older bars for it.
        if (from === this.chart2 && r.from < 30) this.loadOlderCmp();
      });
      link(this.chart, this.chart2);
      link(this.chart2, this.chart);
      // One crosshair across both charts: the same moment on each.
      // The other symbol's line sits as far (in %) from its candle as the mouse is from this one's, so it
      // moves with the mouse instead of jumping between closes.
      const at = (list, t) => { let i = list.length - 1; while (i > 0 && list[i].time > t) i--; return list[i]; };
      const follow = (from, fromSeries, fromBars, to, toSeries, bars) => from.subscribeCrosshairMove((param) => {
        if (this.syncingCrosshair || !this.pair() || !this.crossReal(from, param)) return;
        this.syncingCrosshair = true;
        try {
          if (!param || param.time == null || !param.point) to.clearCrosshairPosition();
          else {
            const t = param.time - TZ, b = at(bars(), t), own = at(fromBars(), t);
            const mouse = fromSeries.coordinateToPrice(param.point.y);
            const price = b && own && own.close && mouse != null ? b.close * (mouse / own.close) : b && b.close;
            if (b) to.setCrosshairPosition(price, b.time + TZ, toSeries);
          }
        } catch { /* nothing to show */ }
        this.syncingCrosshair = false;
      });
      follow(this.chart, this.series, () => this.viewBars(), this.chart2, this.series2, () => this.cmpView || []);
      follow(this.chart2, this.series2, () => this.cmpView || [], this.chart, this.series, () => this.viewBars());
      // Drawings on the second chart too, kept per symbol like the first one's.
      this.drawings2 = new window.AurumDrawings({
        chart: this.chart2, series: this.series2, store,
        bars: () => this.cmpView || [], sec: () => TF_SECONDS[this.interval], digits: () => this.cmpDigits || 2,
        symbol: () => this.cmpName || "XAG", magnet: () => this.magnet, onChange: () => this.renderDrawBar(),
        interval: () => this.interval, onEdit: (d, isNew) => this.drawingSettings(d, isNew),
      });
      this.relinkDrawings();
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
      if (this.owner && this.pair() && !this.replay) {
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
        if (e.button > 0 || e.target.closest("#ticket2, .c2-head, #drawBar, .box-bar")) return;
        const { x, y } = rel(e);
        if (x > this.chart2.timeScale().width()) return;
        // Alt (⌥ on a Mac) + drag with the mouse: the blue box picking this chart's drawings, as on the first one.
        if (e.pointerType === "mouse" && e.altKey && !this.drawings2.tool && !this.drawings2.pending) {
          this.startBox(this.drawings2, wrap, x, y);
          lock(true); e.stopPropagation(); e.preventDefault();
          return;
        }
        const r = this.drawings2.down(x, y, e);
        this.renderBoxBar();
        if (r === true) { gesture = true; lock(true); e.stopPropagation(); }
      }, true);
      ["mousedown", "touchstart"].forEach((t) => wrap.addEventListener(t, (e) => { if (gesture) e.stopPropagation(); }, { capture: true, passive: true }));
      wrap.addEventListener("touchmove", (e) => { if (gesture) e.preventDefault(); }, { passive: false });
      wrap.addEventListener("pointermove", (e) => {
        if (gesture) return;
        const { x, y } = rel(e);
        if (this.drawings2.pending) { this.drawings2.move(x, y, e); return; }
        if (e.pointerType === "mouse") wrap.style.cursor = this.drawings2.tool ? "crosshair" : x <= this.chart2.timeScale().width() && this.drawings2.hitTest(x, y, 8) ? "move" : "";
      });
      window.addEventListener("pointermove", (e) => {
        if (this.boxSel && this.boxSel.wrap === wrap) { const { x, y } = rel(e); this.boxSel.x1 = Math.max(0, Math.min(x, this.chart2.timeScale().width())); this.boxSel.y1 = y; this.drawBox(); return; }
        if (gesture) { const { x, y } = rel(e); this.drawings2.move(x, y, e); }
      });
      const end = () => {
        if (this.boxSel && this.boxSel.wrap === wrap) { lock(false); this.endBox(); return; }
        if (!gesture) return; gesture = false; lock(false); this.drawings2.up();
      };
      window.addEventListener("pointerup", end);
      window.addEventListener("pointercancel", end);
      wrap.addEventListener("dblclick", (e) => {
        if (this.drawings2.current) { this.drawingSettings(this.drawings2.current); return; }
        if (!this.chartDblBusy(e)) this.togglePairLayout();
      });
      wrap.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        if (this.drawings2.pending) { this.drawings2.cancel(); return; }
        const items = [["reset", "⟲ Đặt lại biểu đồ"], ["tools", "✎ Công cụ vẽ…"]];
        if (this.drawings2.current) items.push(["drawSettings", "⚙ Cài đặt bản vẽ…"], ["drawDel", "🗑 Xoá bản vẽ này"]);
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
          if (k === "drawDel" && this.drawings2.current) this.drawings2.remove(this.drawings2.current.id);
          if (k === "clear" && confirm("Xoá tất cả bản vẽ trên " + this.cmpName + "?")) this.drawings2.clear();
          if (k === "swap") $("swapBtn").click();
        }));
      });
    },

    /** The chart last touched: its drawing is the one the bar and settings edit. */
    /** A drawing changed (or was picked) on one chart of the symbol: the bar follows, the others repaint. */
    /** Drawings shared with the app: kept on the VPS per market (XAUUSDm and XAUUSD are one), the newest
     *  copy winning. Only the owner's MT5 (VPS) charts. */
    drawSyncOn() { return this.owner && this.source === "exness" && !!this.symbol; },
    drawSyncKey() { return "aurum.drawUpd." + ((this.symbol || "").match(/^[#.]?([A-Z0-9]+)/) || [, this.symbol])[1]; },

    pushDrawings(dr) {
      if (dr !== this.drawingsMain || !this.drawSyncOn()) return;
      clearTimeout(this.drawPushTimer);
      const symbol = this.symbol, key = this.drawSyncKey();
      this.drawPushTimer = setTimeout(async () => {
        if (symbol !== this.symbol) return;
        const updated = Date.now() / 1000;
        store.set(key, String(updated));
        try { await this.call("/drawings", { symbol, updated, drawings: dr.list }); } catch { /* an older server: kept here */ }
      }, 1200);
    },

    async pullDrawings() {
      const dr = this.drawingsMain;
      if (!dr || !this.drawSyncOn() || this.drawPulling || dr.pending || (dr.gesture && dr.gesture.moved)) return;
      const symbol = this.symbol, key = this.drawSyncKey();
      this.drawPulling = true;
      try {
        const res = await this.call(`/drawings?symbol=${encodeURIComponent(symbol)}`);
        if (symbol !== this.symbol || !res || !Array.isArray(res.drawings)) return;
        const mine = +(store.get(key) || 0);
        if (res.updated > mine + 0.001) {
          store.set(key, String(res.updated));
          if (JSON.stringify(res.drawings) !== JSON.stringify(dr.list)) { dr.replaceAll(res.drawings); this.drawingsChanged(dr); }
        } else if (!res.updated && dr.list.length) {
          // The VPS has none yet: this chart's become the shared ones.
          this.pushDrawings(dr);
        }
      } catch { /* an older server or offline: nothing shared */ } finally { this.drawPulling = false; }
    },

    undoDrawing() {
      const d = this.drawings;
      if (!d || !d.undo) return;
      if (d.undo()) { toast("↶ Đã quay lại bước trước"); this.renderDrawBar(); } else toast("Không còn gì để quay lại", true);
      this.renderUndo();
    },
    redoDrawing() {
      const d = this.drawings;
      if (!d || !d.redo) return;
      if (d.redo()) { toast("↷ Đã làm lại"); this.renderDrawBar(); } else toast("Không còn gì để làm lại", true);
      this.renderUndo();
    },
    renderUndo() {
      const d = this.drawings, u = $("undoBtn"), r = $("redoBtn");
      if (u) u.disabled = !(d && d.canUndo && d.canUndo());
      if (r) r.disabled = !(d && d.canRedo && d.canRedo());
    },

    drawingsChanged(from) {
      this.renderUndo();
      if (from === this.drawings || !this.drawings) this.renderDrawBar();
      const main = this.drawingsMain;
      if (main && from !== main) main.update();
      (this.panes || []).forEach((p) => { if (p.drawings !== from) p.mirrorDrawings(); });
    },

    /** An extra timeframe chart was touched: its drawings are the ones the bar and settings edit. */
    focusPane(pane) {
      this.closeMenu();
      $("chartWrap").classList.remove("focus");
      $("chartWrap2").classList.remove("focus");
      (this.panes || []).forEach((p) => p.wrap.classList.toggle("focus", p === pane));
      if ($("drawBar").parentElement !== pane.wrap) pane.wrap.appendChild($("drawBar"));
      // One pick at a time across the charts.
      this.allDrawings().forEach((x) => { if (x !== pane.drawings && x.selected) { x.selected = null; x.update(); } });
      if (this.drawings === pane.drawings) return;
      this.drawings = pane.drawings;
      this.renderDrawBar();
    },

    focusChart(n) {
      const next = n === 2 && this.drawings2 ? this.drawings2 : this.drawingsMain;
      (this.panes || []).forEach((p) => p.wrap.classList.remove("focus"));
      if (n === 1 && this.panes && this.panes.length) (this.panes || []).forEach((p) => { if (p.drawings.selected) { p.drawings.selected = null; p.drawings.update(); } });
      $("chartWrap").classList.toggle("focus", n === 1 && (this.pair() || !!(this.panes && this.panes.length)));
      $("chartWrap2").classList.toggle("focus", n === 2);
      // The drawing bar sits on the chart being edited.
      const wrap = n === 2 && this.drawings2 ? $("chartWrap2") : $("chartWrap");
      if ($("drawBar").parentElement !== wrap) wrap.appendChild($("drawBar"));
      if (this.drawings === next) return;
      this.drawings = next;
      this.renderDrawBar();
    },

    allDrawings() { return [this.drawingsMain, this.drawings2].concat((this.panes || []).map((p) => p.drawings)).filter(Boolean); },

    cmpPath(count, before) {
      const extra = before ? `&before=${before}` : "";
      return this.owner
        ? `/mt5/candles?symbol=${encodeURIComponent(this.cmpSymbol())}&interval=${this.interval}&count=${count}${extra}`
        : `/member/candles?symbol=compare&interval=${this.interval}&count=${count}${extra}`;
    },

    /** SMT is on (it needs the related market's bars even with one chart). */
    smtWanted() { return !!(this.pair() && showInd.smt && window.ICT && (this.owner || this.features.killzones !== false)); },

    async loadCmp() {
      const show2 = this.pair() && this.chart2;
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
        // From Binance (a Binance chart, member servers before 2.6, or no MT5): the pair's Binance market
        // (silver futures for gold, ETH for BTC…); none for markets Binance does not have.
        try {
          const market = binanceMarket(name) || (/XAU|GOLD/i.test($("chartSymbol").textContent) ? binanceMarket("XAG") : null);
          if (!market) throw new Error("no Binance pair");
          bars = await binanceBars(market.futures ? "https://fapi.binance.com/fapi/v1/klines" : "https://api.binance.com/api/v3/klines", market.name, this.interval, 800);
          name = market.name; digits = market.digits != null ? market.digits : 2;
          this.cmpMarket = market;
        } catch { bars = []; }
      }
      if (token !== this.cmpToken) return;
      this.cmpBars = bars; this.cmpQuote = quote; this.cmpLive = live; this.cmpView = null; this.cmpNoOlder = false; this.cmpCovered = [];
      if (live) this.cmpMarket = null;
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
      // A replay further back than the compared market's loaded bars: fetch them around the replayed bar.
      if (this.replay) this.cmpCover(until);
      const view = (this.cmpBars || []).filter((b) => b.time <= until);
      const changed = full || !this.cmpView || view.length !== this.cmpView.length || this.replay;
      this.cmpView = view;
      if (this.series2 && this.pair()) {
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
      // SMT again when either market gets a bar (or every 2 s for the live ones), not on every trade.
      const key = `${this.viewBars().length}:${view.length}`;
      if (full || changed || key !== this.smtKey || !this.smtTime || Date.now() - this.smtTime > 2000) {
        this.smtKey = key; this.smtTime = Date.now();
        this.computeSMT();
      } else if (this.request2) this.request2();
    },

    computeSMT() {
      const on = this.smtWanted() && this.cmpView && this.cmpView.length;
      const c = this.ictCfg || {};
      this.smt = on ? window.ICT.smt(this.viewBars(), this.cmpView, { swing: c.smtSwing, lookback: c.smtLookback, count: c.smtCount }) : null;
      if (this.requestICT) this.requestICT();
      if (this.request2) this.request2();
    },

    /** Shows the same time span on `to` as on `from`; the lock keeps the two from echoing each other. */
    syncRange(from, to) {
      if (!from || !to || !this.pair()) return;
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
    /** The compared market's bars around `until` (the replayed bar): from 400 bars before it to 1000 after,
     *  fetched when they are not loaded yet (and again when the replay runs past them). */
    async cmpCover(until) {
      const bars = this.cmpBars || [], sec = TF_SECONDS[this.interval];
      if (!sec || this.cmpCoverBusy || isSecTF(this.interval)) return;
      const from = until - 400 * sec, to = until + 60 * sec;
      const covered = (this.cmpCovered || []).some(([a, b]) => a <= from && b >= Math.min(to, Date.now() / 1000));
      const loaded = bars.length && bars[0].time <= from && bars[bars.length - 1].time >= Math.min(to, Date.now() / 1000 - 2 * sec);
      if (covered || loaded) return;
      const before = Math.min(Math.floor(Date.now() / 1000) + sec, until + 1000 * sec);
      const token = this.cmpToken;
      this.cmpCoverBusy = true;
      try {
        let got = [];
        if (this.cmpLive) {
          const data = await this.call(this.cmpPath(1400, before));
          got = this.toBars(data.candles || []);
        } else if (this.cmpMarket) {
          const m = this.cmpMarket, [kname, factor] = binanceKline(this.interval);
          const rest = m.futures ? "https://fapi.binance.com/fapi/v1/klines" : "https://api.binance.com/api/v3/klines";
          const rows = await (await fetch(`${rest}?symbol=${m.name}&interval=${kname}&endTime=${before * 1000}&limit=${Math.min(1000, 1400 * factor)}`)).json();
          got = Array.isArray(rows) ? mergeKlines(rows.map((r) => ({ time: r[0] / 1000, open: +r[1], high: +r[2], low: +r[3], close: +r[4], volume: +r[5] })), this.interval) : [];
        }
        if (token !== this.cmpToken || !got.length) return;
        // Into the loaded bars, by time (a gap between the two stays a gap; the charts line up by time).
        const map = new Map((this.cmpBars || []).map((b) => [b.time, b]));
        got.forEach((b) => map.set(b.time, b));
        this.cmpBars = [...map.values()].sort((a, b) => a.time - b.time);
        this.cmpCovered = (this.cmpCovered || []).concat([[got[0].time, got[got.length - 1].time]]);
        this.cmpView = null;
        this.showCmp(true);
      } catch { /* keep what there is */ } finally { this.cmpCoverBusy = false; }
    },

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
      this.renderNewsStrip();
      const box = $("flowBox");
      // (A red release's live verdict is in the news rows at the right.)
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
      const min = store.get("aurum.flowMin") === "1";
      box.classList.toggle("min", min);
      if (min) {
        // Folded: one line, the verdict and the zone prices; a tap opens it again.
        const z = f.zones && showInd.zones ? f.zones : [];
        const buy = z.find((x) => x.demand), sell = z.find((x) => !x.demand), d = this.digits;
        box.innerHTML = `🦈 <b class="${verdict[1]}">${verdict[0]} ${pct}</b>${buy ? ` · <span class="pos">🟢 ${fmt(buy.bottom, d)}–${fmt(buy.top, d)}</span>` : ""}${sell ? ` · <span class="neg">🔴 ${fmt(sell.bottom, d)}–${fmt(sell.top, d)}</span>` : ""}<button type="button" class="flow-x" title="Mở rộng">▾</button>`;
        box.onclick = () => { store.set("aurum.flowMin", "0"); this.updateFlow(); };
        return;
      }
      box.onclick = null;
      box.innerHTML = `<div>🦈 Dòng tiền <b class="${verdict[1]}">${verdict[0]} ${pct}</b>${f.shark ? ` <span class="${f.shark.buying ? "pos" : "neg"}">· cá mập ${f.shark.buying ? "MUA" : "BÁN"} ×${f.shark.ratio.toFixed(1)}</span>` : ""}<button type="button" class="flow-x" title="Thu gọn còn 1 dòng (chart cao hơn)">▴</button></div><div class="${advice[1]}">${advice[0]}</div>${this.zonesLine(f)}`;
      box.querySelector(".flow-x").onclick = (e) => { e.stopPropagation(); store.set("aurum.flowMin", "1"); this.updateFlow(); };
    },

    /** Shark supply / demand: the bands under the candles, their names over them (`labels`). */
    drawSharkZones(g, width, labels) {
      if (!this.sharkZones) return;
      const ts = this.chart.timeScale();
      // Heights of the trade labels at the right, for the names to keep clear of.
      const avoid = labels ? this.tradeLines().map((w) => this.series.priceToCoordinate(w.price)).filter((y) => y != null) : [];
      const sc = this.sharkColors();
      // Ending near the last candle like the ICT lines (unless those reach the right edge).
      const cfg = this.ictCfg || {}, n = this.viewBars().length;
      const near = cfg.lineEnd === "edge" || !n ? null : ts.logicalToCoordinate(n - 1 + Math.max(1, cfg.lineEndBars || 8));
      window.ICT.drawZones(g, this.sharkZones, (i) => ts.logicalToCoordinate(i), (v) => this.series.priceToCoordinate(v), width,
        sc.demand, sc.supply, this.digits,
        document.documentElement.dataset.theme === "light" ? "rgba(255,255,255,.9)" : "rgba(8,8,10,.88)", labels, avoid, sc.zone, near);
    },

    /** "Dòng tiền cá mập" colours: the candles' own by default, or the ones picked in its settings. */
    sharkDefaults() {
      return { follow: true, buy: "#14b88a", sell: "#f0455a", demand: "#14b88a", supply: "#f0455a", bubbleOpacity: 35, zoneOpacity: 13, minRatio: 2.5, maxBubbles: 0 };
    },
    sharkCfgGet() {
      if (!this.sharkCfg) {
        try { this.sharkCfg = Object.assign(this.sharkDefaults(), JSON.parse(store.get("aurum.sharkcfg") || "{}")); } catch { this.sharkCfg = this.sharkDefaults(); }
      }
      return this.sharkCfg;
    },
    sharkColors() {
      const c = this.sharkCfgGet(), st = this.chartStyle || {};
      const up = (st.up || "#14b88a").slice(0, 7), down = (st.down || "#f0455a").slice(0, 7);
      const pct = (v, d) => Math.max(0, Math.min(100, isFinite(+v) ? +v : d)) / 100;
      return c.follow
        ? { buy: up, sell: down, demand: up, supply: down, bubble: pct(c.bubbleOpacity, 35), zone: pct(c.zoneOpacity, 13) }
        : { buy: c.buy.slice(0, 7), sell: c.sell.slice(0, 7), demand: c.demand.slice(0, 7), supply: c.supply.slice(0, 7), bubble: pct(c.bubbleOpacity, 35), zone: pct(c.zoneOpacity, 13) };
    },

    /** The bubbles kept by "Bong bóng hiện": at least the chosen strength, and only the strongest N on screen. */
    sharksShown(list) {
      if (!list || !list.length) return list;
      const c = this.sharkCfgGet(), min = +c.minRatio || 0, max = +c.maxBubbles || 0;
      let out = min > 2.5 ? list.filter((x) => x.ratio >= min) : list;
      if (max > 0 && out.length > max) {
        const r = this.chart && this.chart.timeScale().getVisibleLogicalRange();
        const seen = r ? out.filter((x) => x.index >= Math.floor(r.from) - 1 && x.index <= Math.ceil(r.to) + 1) : out;
        out = seen.slice().sort((a, b) => b.ratio - a.ratio).slice(0, max);
      }
      return out;
    },

    sharkSettingsSheet() {
      sheet.close();
      const cfg = this.sharkCfgGet();
      const render = () => {
        const { tog, color, numf, sel, head, note } = fieldKit(cfg);
        return head("Bong bóng hiện")
          + sel("minRatio", "Độ mạnh tối thiểu (khối lượng ≥)", [[2.5, "2.5 × TB (tất cả)"], [3, "3 × trung bình"], [4, "4 × trung bình"], [5, "5 × trung bình"], [7, "7 × trung bình (rất mạnh)"], [10, "10 × trung bình (cực mạnh)"]])
          + sel("maxBubbles", "Số bong bóng tối đa trên màn hình", [[0, "Không giới hạn"], [5, "5 mạnh nhất"], [10, "10 mạnh nhất"], [20, "20 mạnh nhất"], [30, "30 mạnh nhất"]])
          + note("Bong bóng to = khối lượng lớn hơn. Chọn mức cao hoặc giới hạn số lượng để chart đỡ rối: chỉ còn những lệnh cá mập mạnh nhất.")
          + head("Màu") + tog("follow", "Theo màu nến (tắt để chọn màu riêng bên dưới)")
          + color("buy", "Bong bóng cá mập MUA 🦈") + color("sell", "Bong bóng cá mập BÁN 🦈")
          + color("demand", "Vùng CẦU (chờ mua)") + color("supply", "Vùng CUNG (chờ bán)")
          + head("Độ đậm") + numf("bubbleOpacity", "Nền bong bóng (%)") + numf("zoneOpacity", "Nền vùng cung / cầu (%)")
          + note("Bong bóng: lệnh lớn bất thường (cá mập) — dưới nến là mua, trên nến là bán. Vùng CẦU / CUNG: nơi cá mập đã mua / bán mạnh, chờ giá quay lại để vào lệnh.");
      };
      const open = () => this.openPanel("Dòng tiền cá mập", [["style", "Định dạng"]], render, {
        root: cfg,
        onChange: () => { store.set("aurum.sharkcfg", JSON.stringify(cfg)); this.redraw(); },
        onReset: () => {
          if (!confirm("Đặt lại dòng tiền cá mập về mặc định?")) return;
          Object.assign(cfg, this.sharkDefaults()); store.set("aurum.sharkcfg", JSON.stringify(cfg)); this.redraw(); open();
        },
      });
      open();
    },

    /** The strongest demand under the price and supply above it: where to look for an entry. */
    zonesLine(f) {
      if (!showInd.zones || !f.zones || !f.zones.length) return "";
      const buy = f.zones.find((z) => z.demand), sell = f.zones.find((z) => !z.demand), d = this.digits;
      const txt = (z) => `<b>${fmt(z.bottom, d)}–${fmt(z.top, d)}</b> <span class="muted">(${Math.round(z.strength * 100)}%)</span>`;
      return `<div class="small">${buy ? `<span class="pos">🟢 Chờ MUA</span> ${txt(buy)}` : ""}${buy && sell ? " · " : ""}${sell ? `<span class="neg">🔴 Chờ BÁN</span> ${txt(sell)}` : ""}</div>`;
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
