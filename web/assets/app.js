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
    document.querySelector(".nav .btn").hidden = member;
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

  async function api(base, secret, path) {
    let res;
    try {
      res = await fetch(base + path, { headers: { Authorization: "Bearer " + secret }, cache: "no-store" });
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

  const fmt = (v, d = 2) => (v == null ? "–" : Number(v).toFixed(d));
  const signed = (v, d = 2) => (v >= 0 ? "+" : "") + Number(v).toFixed(d);
  const clock = (t) => {
    const date = new Date(t * 1000), today = new Date();
    return date.toDateString() === today.toDateString()
      ? date.toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" })
      : date.toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  };
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  // Members' messages never name the server.
  const plain = (s) => String(s || "").replace(/ trên VPS/g, "").replace(/ VPS/g, "").replace(/VPS/g, "hệ thống");

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

  const Member = {
    // "member" (invite code) or "owner" (server password).
    role: store.get("aurum.role") || "member",
    secret: null,
    base: store.get("aurum.url"),
    loginMode: "member",
    timer: null,
    lastLookup: 0,
    chart: null,
    series: null,
    socket: null,
    pollTimer: null,
    source: "exness",
    chartSymbolName: null,
    interval: store.get("aurum.tf") || "1m",
    priceLines: [],
    signals: [],
    positions: [],

    init() {
      this.secret = this.role === "owner" ? ownerStore.get() : store.get("aurum.code");
    },

    show() {
      if (this.secret && this.base) { this.openDash(); } else { this.openLogin(); }
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

    openDash() {
      const owner = this.role === "owner";
      $("loginView").hidden = true;
      $("dashView").hidden = false;
      $("accountPanel").hidden = !owner;
      $("membersPanel").hidden = !owner;
      $("closedPanel").hidden = owner;
      $("openTitle").textContent = owner ? "Lệnh đang mở" : "Đang mở";
      $("chartNote").textContent = owner ? "Đường xanh/đỏ: lệnh đang mở và SL/TP." : "Đường tím: tín hiệu đang mở (vào lệnh, SL, TP).";
      this.chartSymbolName = null;
      this.refresh().then(() => this.buildChart());
      clearInterval(this.timer);
      this.timer = setInterval(() => this.refresh(), owner ? 3000 : 5000);
    },

    stop() {
      clearInterval(this.timer); this.timer = null;
      clearInterval(this.pollTimer); this.pollTimer = null;
      if (this.socket) { this.socket.close(); this.socket = null; }
    },

    /** One call; when the address moved, find the new one and try again. */
    async call(path) {
      try {
        return await api(this.base, this.secret, path);
      } catch (e) {
        if (!(e instanceof Unreachable) || Date.now() - this.lastLookup < 20000) throw e;
        this.lastLookup = Date.now();
        const moved = await lookupAddress(this.secret, this.role === "owner").catch(() => null);
        if (!moved || moved === this.base) throw e;
        this.base = moved;
        store.set("aurum.url", moved);
        return api(this.base, this.secret, path);
      }
    },

    async refresh() {
      if (!this.secret) return;
      try {
        if (this.role === "owner") await this.refreshOwner(); else await this.refreshMember();
        $("dashError").hidden = true;
        this.drawLines();
      } catch (e) {
        if (e.status === 401 || e.status === 403) {
          this.logout(this.role === "owner" ? "Mật khẩu không còn đúng" : (e.status === 403 ? plain(e.message) : "Mã mời không còn dùng được"));
          return;
        }
        $("dashError").textContent = e instanceof Unreachable ? "Chưa kết nối được, đang thử lại…" : plain(e.message);
        $("dashError").hidden = false;
      }
    },

    async refreshMember() {
      const [me, list] = await Promise.all([this.call("/member/me"), this.call("/member/signals?limit=60")]);
      $("whoName").textContent = me.name;
      const until = me.expires ? " · hết hạn " + new Date(me.expires * 1000).toLocaleDateString("vi-VN") : " · không hết hạn";
      $("whoRole").textContent = (me.role === "copy" ? "Xem tín hiệu + copy lệnh" : "Xem tín hiệu") + until;
      this.signals = list.signals || [];
      const open = this.signals.filter((s) => s.status === "open");
      const closed = this.signals.filter((s) => s.status !== "open");
      const wins = closed.filter((s) => (s.result || 0) > 0).length;
      $("openList").innerHTML = open.length ? open.map((s) => this.signalRow(s)).join("") : '<div class="empty">Chưa có lệnh đang mở</div>';
      $("closedTitle").textContent = closed.length ? `Đã đóng · thắng ${wins}/${closed.length}` : "Đã đóng";
      $("closedList").innerHTML = closed.length ? closed.slice(0, 40).map((s) => this.signalRow(s)).join("") : '<div class="empty">Chưa có</div>';
    },

    async refreshOwner() {
      const [t, m] = await Promise.all([this.call("/mt5/trading"), this.call("/members").catch(() => null)]);
      $("whoName").textContent = "Chủ máy chủ";
      $("whoRole").textContent = t.login ? `#${t.login} · ${t.server || ""}${t.mode === "real" ? " · tài khoản thật" : " · demo"}` : "MT5 chưa đăng nhập";
      const cur = t.currency || "USD";
      const floating = (t.positions || []).reduce((a, p) => a + p.profit, 0);
      $("accountStats").innerHTML = [
        [`Lãi/lỗ đang chạy (${cur})`, `<span class="${floating >= 0 ? "pos" : "neg"}">${signed(floating)}</span>`],
        [`Số dư (${cur})`, fmt(t.balance)], [`Vốn (${cur})`, fmt(t.equity)],
        ["Mức ký quỹ", t.marginLevel ? fmt(t.marginLevel, 0) + "%" : "–"],
      ].map(([k, v]) => `<div class="stat"><span>${k}</span><b>${v}</b></div>`).join("");
      this.positions = t.positions || [];
      $("openList").innerHTML = this.positions.length ? this.positions.map((p) => this.positionRow(p)).join("") : '<div class="empty">Không có lệnh đang mở</div>';
      if (!this.chartSymbolName) {
        this.chartSymbolName = (this.positions.find((p) => /XAU/i.test(p.symbol)) || {}).symbol || null;
      }
      if (m) {
        const now = Date.now() / 1000;
        $("membersTitle").textContent = `Thành viên · ${m.members.length}`;
        $("membersList").innerHTML = m.members.length ? m.members.map((x) => {
          const badge = !x.enabled ? '<span class="badge off">Khoá</span>' : (x.expires && x.expires <= now ? '<span class="badge exp">Hết hạn</span>' : "");
          return `<div class="member-row"><div><b>${esc(x.name)}</b> ${badge}
            <div class="muted small">${x.role === "copy" ? "Tín hiệu + copy" : "Chỉ tín hiệu"}${x.expires ? " · đến " + new Date(x.expires * 1000).toLocaleDateString("vi-VN") : ""}${x.hasCopy ? " · đã nối MT5" : ""}</div></div>
            <div class="muted small">${x.lastSeen ? clock(x.lastSeen) : "chưa vào"}</div></div>`;
        }).join("") : '<div class="empty">Chưa có thành viên</div>';
      }
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
      return this.row(buy, s.symbol, s.entry, `SL ${fmt(s.stop)} · TP ${fmt(s.target)}${s.status === "open" ? "" : " · ra " + fmt(s.exit)}`,
        copy, move != null ? signed(move) : "", move, clock(s.status === "open" ? s.openTime : (s.closeTime || s.openTime)), color);
    },

    positionRow(p) {
      const buy = p.side === "long";
      return this.row(buy, p.symbol, p.entry, `${p.lots} lot · SL ${fmt(p.stop)} · TP ${fmt(p.target)} · giá ${fmt(p.price)}`,
        "", signed(p.profit), p.profit, clock(p.time), buy ? "#2b6bf3" : "var(--down)");
    },

    row(buy, symbol, entry, levels, extra, moveText, move, time, color) {
      return `<div class="sig">
        <div class="bar" style="background:${color}"></div>
        <div>
          <div class="top"><span class="sym">${esc(symbol)}</span>
            <span class="side ${buy ? "buy" : "sell"}">${buy ? "MUA" : "BÁN"}</span>
            <span>${fmt(entry)}</span></div>
          <div class="lv">${levels}</div>
          ${extra}
        </div>
        <div class="right">
          ${moveText ? `<div class="move ${move >= 0 ? "pos" : "neg"}">${moveText}</div>` : ""}
          <div class="muted small">${time}</div>
        </div>
      </div>`;
    },

    /* ----- chart: Exness bars through the server, Binance XAUUSDT if they are not there ----- */

    buildChart() {
      const el = $("chart");
      if (!window.LightweightCharts) { el.innerHTML = '<p class="muted small">Không tải được biểu đồ.</p>'; return; }
      if (!this.chart) {
        this.chart = LightweightCharts.createChart(el, {
          autoSize: true,
          layout: { background: { color: "#151c2a" }, textColor: "#8b95a7", fontFamily: "Be Vietnam Pro, system-ui" },
          grid: { vertLines: { color: "#1c2535" }, horzLines: { color: "#1c2535" } },
          rightPriceScale: { borderColor: "#222c3d" },
          timeScale: { borderColor: "#222c3d", timeVisible: true, secondsVisible: false },
          crosshair: { mode: 0 },
        });
        this.series = this.chart.addCandlestickSeries({
          upColor: "#14b88a", downColor: "#f0455a", borderVisible: false, wickUpColor: "#14b88a", wickDownColor: "#f0455a",
        });
        const tf = $("tfButtons");
        ["1m", "5m", "15m", "1h", "4h"].forEach((i) => {
          const b = document.createElement("button");
          b.textContent = i; b.dataset.tf = i;
          b.onclick = () => { this.interval = i; store.set("aurum.tf", i); this.loadCandles(); };
          tf.appendChild(b);
        });
      }
      this.loadCandles();
    },

    exnessPath(count, ownerSymbol) {
      return this.role === "owner"
        ? `/mt5/candles?symbol=${encodeURIComponent(ownerSymbol)}&interval=${this.interval}&count=${count}`
        : `/member/candles?interval=${this.interval}&count=${count}`;
    },

    async ownerSymbol() {
      if (this.chartSymbolName) return this.chartSymbolName;
      const found = await this.call("/mt5/symbols?q=XAUUSD&limit=10").catch(() => null);
      const names = ((found && found.symbols) || []).map((x) => x.name);
      this.chartSymbolName = names.find((n) => /^XAUUSD/i.test(n)) || names[0] || "XAUUSD";
      return this.chartSymbolName;
    },

    toBars(rows) {
      return rows.map((r) => ({ time: r[0], open: r[1], high: r[2], low: r[3], close: r[4] }));
    },

    async loadCandles() {
      document.querySelectorAll("#tfButtons button").forEach((b) => b.classList.toggle("on", b.dataset.tf === this.interval));
      if (this.socket) { this.socket.close(); this.socket = null; }
      clearInterval(this.pollTimer); this.pollTimer = null;
      try {
        const symbol = this.role === "owner" ? await this.ownerSymbol() : null;
        const data = await this.call(this.exnessPath(500, symbol));
        const bars = this.toBars(data.candles || []);
        if (bars.length < 5) throw new Error("no bars");
        this.source = "exness";
        $("chartSymbol").textContent = data.symbol || symbol || "XAUUSD";
        $("chartSource").textContent = "· giá Exness";
        this.series.setData(bars);
        $("livePrice").textContent = fmt(bars[bars.length - 1].close);
        this.chart.timeScale().scrollToRealTime();
        // The newest bars every 2 seconds (MT5 has no public stream).
        this.pollTimer = setInterval(async () => {
          try {
            const fresh = this.toBars((await this.call(this.exnessPath(3, symbol))).candles || []);
            fresh.forEach((b) => this.series.update(b));
            if (fresh.length) $("livePrice").textContent = fmt(fresh[fresh.length - 1].close);
          } catch { /* keep the chart */ }
        }, 2000);
      } catch {
        await this.loadBinance();
      }
      this.drawLines();
    },

    async loadBinance() {
      this.source = "binance";
      $("chartSymbol").textContent = "XAUUSD";
      $("chartSource").textContent = "· giá Binance XAUUSDT";
      try {
        const res = await fetch(`https://fapi.binance.com/fapi/v1/klines?symbol=XAUUSDT&interval=${this.interval}&limit=500`);
        const rows = await res.json();
        const data = rows.map((r) => ({ time: r[0] / 1000, open: +r[1], high: +r[2], low: +r[3], close: +r[4] }));
        this.series.setData(data);
        if (data.length) $("livePrice").textContent = fmt(data[data.length - 1].close);
        this.chart.timeScale().scrollToRealTime();
      } catch { /* chart stays empty */ }
      const ws = new WebSocket(`wss://fstream.binance.com/ws/xauusdt@kline_${this.interval}`);
      ws.onmessage = (ev) => {
        const k = JSON.parse(ev.data).k;
        if (!k) return;
        this.series.update({ time: k.t / 1000, open: +k.o, high: +k.h, low: +k.l, close: +k.c });
        $("livePrice").textContent = fmt(+k.c);
      };
      this.socket = ws;
    },

    drawLines() {
      if (!this.series) return;
      this.priceLines.forEach((l) => this.series.removePriceLine(l));
      this.priceLines = [];
      const add = (price, color, title, style) => {
        if (price == null) return;
        this.priceLines.push(this.series.createPriceLine({ price, color, lineWidth: 1, lineStyle: style, axisLabelVisible: true, title }));
      };
      if (this.role === "owner") {
        this.positions.filter((p) => !this.chartSymbolName || p.symbol === this.chartSymbolName).forEach((p) => {
          add(p.entry, p.side === "long" ? "#2b6bf3" : "#f0455a", `${p.side === "long" ? "BUY" : "SELL"} ${p.lots} ${signed(p.profit)}`, 2);
          add(p.stop, "#f0455a", "SL", 1);
          add(p.target, "#14b88a", "TP", 1);
        });
        return;
      }
      const purple = "#9b6bff";
      this.signals.filter((s) => s.status === "open" && /XAU/i.test(s.symbol)).forEach((s) => {
        add(s.entry, purple, (s.side === "long" ? "MUA" : "BÁN") + " tín hiệu", 2);
        add(s.stop, purple, "SL", 1);
        add(s.target, purple, "TP", 1);
      });
    },
  };

  Member.init();
  $("loginForm").addEventListener("submit", (e) => { e.preventDefault(); Member.login(); });
  $("modeBtn").addEventListener("click", () => Member.setLoginMode(Member.loginMode === "owner" ? "member" : "owner"));
  $("logoutBtn").addEventListener("click", () => Member.logout());
  route();
})();
