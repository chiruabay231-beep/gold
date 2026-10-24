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
    const label = button ? button.textContent : "";
    if (button) { button.disabled = true; button.textContent = "…"; }
    try {
      const result = await work();
      if (done) toast(done);
      return result;
    } catch (e) {
      toast(e instanceof Unreachable ? "Chưa kết nối được, thử lại" : plain(e.message), true);
      return null;
    } finally {
      if (button) { button.disabled = false; button.textContent = label; }
    }
  }

  /* ---------------- indicator switches ---------------- */

  const IND = [
    ["killzones", "ICT Killzones (phiên, đỉnh đáy phiên, giá mở cửa)"],
    ["daily", "Đỉnh đáy từng ngày"],
    ["fvg", "FVG & Volume Imbalance"],
    ["mss", "MSS (đổi cấu trúc)"],
    ["flow", "Dòng tiền cá mập"],
  ];
  const showInd = (() => {
    let saved = {};
    try { saved = JSON.parse(store.get("aurum.ind") || "{}"); } catch { /* default */ }
    return Object.fromEntries(IND.map(([k]) => [k, saved[k] !== false]));
  })();

  const TFS = ["1m", "5m", "15m", "30m", "1h", "4h", "1d"];
  const TF_SECONDS = { "1m": 60, "5m": 300, "15m": 900, "30m": 1800, "1h": 3600, "4h": 14400, "1d": 86400 };

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
          ["copy", "Copy"], ["members", "Thành viên"], ["bot", "Máy chủ"]];
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
      $("loginView").hidden = true;
      $("dashView").hidden = false;
      this.tab = store.get("aurum.tab") || "chart";
      this.me = null;
      this.selected = null;
      this.draft = null;
      $("ticket").hidden = !this.owner;
      $("chartSymbol").disabled = !this.owner;
      $("chartNote").textContent = this.owner
        ? "Chạm vào đường giá vào lệnh để chọn lệnh, rồi kéo SL/TP. Kéo đường tím để đặt giá lệnh chờ."
        : "Đường tím: tín hiệu đang mở (giá vào, SL, TP).";
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
      if (this.tab === "trade") this.renderTrade();
    },

    renderPill(floating) {
      const mine = this.positions;
      const pill = $("posPill");
      if (!this.owner || !mine.length) { pill.hidden = true; return; }
      const lots = mine.reduce((a, p) => a + p.lots, 0);
      pill.hidden = false;
      pill.innerHTML = `<span class="go">${mine.length} lệnh · ${fmt(lots, 2)} lot · <b class="${floating >= 0 ? "pos" : "neg"}">${signed(floating)}</b></span><button type="button" class="x" title="Đóng tất cả">✕</button>`;
      pill.querySelector(".go").onclick = () => this.setTab("trade");
      pill.querySelector(".x").onclick = (e) => this.closeAll(e.currentTarget);
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

    lots() { return Math.max(0.01, Math.round((num($("lotInput").value) || 0.01) * 100) / 100); },

    async marketOrder(side, button) {
      if (!this.symbol) return;
      const body = { symbol: this.symbol, side, type: "market", lots: this.lots() };
      if (this.draft) { body.stop = num($("pStop").value); body.target = num($("pTarget").value); }
      const ok = await act(button, () => this.call("/mt5/order", body), `Đã ${side === "long" ? "MUA" : "BÁN"} ${body.lots} ${this.symbol}`);
      if (ok) this.refresh();
    },

    pendingKind(side, price) {
      if (price == null) return side === "long" ? "BUY LIMIT" : "SELL LIMIT";
      if (side === "long") return price < (this.ask || price) ? "BUY LIMIT" : "BUY STOP";
      return price > (this.bid || price) ? "SELL LIMIT" : "SELL STOP";
    },

    updatePendingLabels() {
      const price = num($("pPrice").value);
      $("pBuy").textContent = this.pendingKind("long", price);
      $("pSell").textContent = this.pendingKind("short", price);
    },

    async pendingOrder(side, button) {
      const price = num($("pPrice").value);
      if (!price) return toast("Nhập giá chờ hoặc kéo đường tím", true);
      const body = { symbol: this.symbol, side, type: "pending", price, lots: this.lots(), stop: num($("pStop").value), target: num($("pTarget").value) };
      const kind = this.pendingKind(side, price);
      const ok = await act(button, () => this.call("/mt5/order", body), `Đã đặt ${kind} ${body.lots} @ ${fmt(price, this.digits)}`);
      if (ok) { this.togglePending(false); this.refresh(); }
    },

    togglePending(open) {
      const box = $("pendingBox");
      open = open === undefined ? box.hidden : open;
      box.hidden = !open;
      $("pendingToggle").textContent = (open ? "▴" : "▾") + " Lệnh chờ · SL/TP";
      if (open) {
        const last = this.bars.length ? this.bars[this.bars.length - 1].close : null;
        if (!num($("pPrice").value) && last) $("pPrice").value = fmt(last, this.digits);
        this.draft = true;
      } else {
        this.draft = null;
        $("pPrice").value = ""; $("pStop").value = ""; $("pTarget").value = "";
      }
      this.updatePendingLabels();
      this.syncLines();
    },

    /* ----- members: signals ----- */

    async refreshSignals() {
      const list = await this.call("/member/signals?limit=80");
      this.signals = list.signals || [];
      if (this.tab === "signals") this.renderSignals();
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
    },

    /* ----- history ----- */

    rangeTimes(key) {
      const start = new Date(); start.setHours(0, 0, 0, 0);
      const day = start.getTime() / 1000, nowS = Date.now() / 1000;
      return { today: [day, nowS + 60], yesterday: [day - 86400, day], week: [day - 6 * 86400, nowS + 60], month: [day - 29 * 86400, nowS + 60] }[key];
    },

    async loadHistory() {
      const ranges = [["today", "Hôm nay"], ["yesterday", "Hôm qua"], ["week", "7 ngày"], ["month", "30 ngày"]];
      $("histRange").innerHTML = ranges.map(([k, n]) => `<button type="button" data-r="${k}" class="${k === this.histRange ? "on" : ""}">${n}</button>`).join("");
      $("histRange").querySelectorAll("button").forEach((b) => (b.onclick = () => { this.histRange = b.dataset.r; this.loadHistory(); }));
      $("histList").innerHTML = '<div class="empty">Đang tải…</div>';
      const [from, to] = this.rangeTimes(this.histRange);
      try {
        const h = await this.call(`/mt5/history?from=${Math.floor(from)}&to=${Math.ceil(to)}`);
        const list = (h.positions || []).sort((a, b) => b.closeTime - a.closeTime);
        const wins = list.filter((p) => p.profit > 0).length;
        const total = list.reduce((a, p) => a + p.profit, 0);
        const fees = list.reduce((a, p) => a + (p.commission || 0) + (p.swap || 0), 0);
        $("histStats").innerHTML = [
          ["Lãi/lỗ", `<span class="${total >= 0 ? "pos" : "neg"}">${signed(total)}</span>`],
          ["Số lệnh", list.length], ["Thắng / thua", `${wins} / ${list.length - wins}`], ["Phí + swap", signed(fees)],
        ].map(([k, v]) => `<div class="stat"><span>${k}</span><b>${v}</b></div>`).join("");
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
      } catch (e) {
        $("histList").innerHTML = `<div class="empty">${esc(plain(e.message))}</div>`;
      }
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

    /* ----- bot & server ----- */

    async loadBot(first) {
      if (!first && $("sheet").open) return;
      try {
        const [s, log] = await Promise.all([this.call("/status"), this.call("/log?limit=80")]);
        const st = s.settings || {};
        const acc = s.account || {};
        $("botPanel").innerHTML = `<div class="panel-head"><h3>Bot tự động</h3><span class="badge ${s.running ? "on" : "off"}">${s.running ? "Đang chạy" : "Đang dừng"}</span></div>
          <div class="kvs">
            <div class="kv"><span>Chiến lược</span><b>${esc(st.strategyName || "–")}</b></div>
            <div class="kv"><span>Mã · khung</span><b>${esc(st.symbol || "–")} · ${esc(st.interval || "")}</b></div>
            <div class="kv"><span>Đặt lệnh</span><b>${st.broker === "mt5" ? "Lệnh thật MT5" : "Tài khoản demo"} · ${st.lots} lot</b></div>
            <div class="kv"><span>Tài khoản bot</span><b>${acc.equity != null ? money(acc.equity) + " " + esc(acc.currency || "") : esc(acc.error || "–")}</b></div>
            ${s.error ? `<div class="kv"><span>Lỗi</span><b class="neg">${esc(s.error)}</b></div>` : ""}
          </div>
          <div class="row-btns">${s.running ? '<button class="btn btn-ghost" id="botStop">■ Dừng bot</button>' : `<button class="btn btn-gold" id="botStart" ${st.strategyName ? "" : "disabled"}>▶ Chạy lại</button>`}</div>
          <p class="muted small">Chọn chiến lược mới và cài bot trong app (Backtest → Bot). Telegram: ${s.telegram && s.telegram.configured ? (s.telegram.linked ? "đã nối" : "chưa nối chat") : "chưa cài"}.</p>
          <h4>Máy chủ</h4>
          <div class="kvs"><div class="kv"><span>Phiên bản</span><b>${esc(s.version)}</b></div>
            <div class="kv"><span>Chạy từ</span><b>${s.startedAt ? fullTime(s.startedAt) : "–"}</b></div>
            <div class="kv"><span>MT5</span><b>${s.mt5 && s.mt5.connected ? "Đã kết nối" : esc((s.mt5 && s.mt5.error) || "Chưa kết nối")}</b></div></div>
          <button class="btn btn-ghost wide" id="srvUpdate">Cập nhật máy chủ lên bản mới nhất</button>`;
        const stopBtn = $("botStop"), startBtn = $("botStart");
        if (stopBtn) stopBtn.onclick = async (e) => { await act(e.currentTarget, () => this.call("/stop", {}), "Đã dừng bot"); this.loadBot(true); };
        if (startBtn) startBtn.onclick = async (e) => { await act(e.currentTarget, () => this.call("/start", {}), "Bot đã chạy"); this.loadBot(true); };
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
          layout: { background: { color: "#151c2a" }, textColor: "#8b95a7", fontFamily: "Be Vietnam Pro, system-ui" },
          grid: { vertLines: { color: "#1a2233" }, horzLines: { color: "#1a2233" } },
          rightPriceScale: { borderColor: "#222c3d" },
          timeScale: { borderColor: "#222c3d", timeVisible: true, secondsVisible: false, rightOffset: 8, barSpacing: el.clientWidth < 500 ? 4 : 6 },
          localization: { timeFormatter: (t) => new Date(t * 1000).toLocaleString("vi-VN", { timeZone: "UTC", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) },
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
        $("tfButtons").innerHTML = TFS.map((i) => `<button type="button" data-tf="${i}">${i}</button>`).join("");
        $("tfButtons").querySelectorAll("button").forEach((b) => (b.onclick = () => {
          this.interval = b.dataset.tf; store.set("aurum.tf", this.interval); this.loadCandles();
        }));
        this.chart.timeScale().subscribeVisibleLogicalRangeChange((r) => {
          this.redraw();
          if (r && r.from < 30) this.loadOlder();
        });
        this.chart.subscribeCrosshairMove(() => this.redraw());
        new ResizeObserver(() => this.redraw()).observe($("chartWrap"));
        this.bindDrag();
        this.bindTicket();
      }
      this.applySeriesFormat();
      this.loadCandles();
    },

    applySeriesFormat() {
      if (this.series) this.series.applyOptions({ priceFormat: { type: "price", precision: this.digits, minMove: Math.pow(10, -this.digits) } });
    },

    bindTicket() {
      $("sellBtn").onclick = (e) => this.marketOrder("short", e.currentTarget);
      $("buyBtn").onclick = (e) => this.marketOrder("long", e.currentTarget);
      $("lotInput").value = store.get("aurum.lots") || "0.01";
      $("lotInput").onchange = () => { $("lotInput").value = this.lots().toFixed(2); store.set("aurum.lots", $("lotInput").value); };
      document.querySelectorAll(".lots [data-step]").forEach((b) => (b.onclick = () => {
        $("lotInput").value = Math.max(0.01, this.lots() + 0.01 * +b.dataset.step).toFixed(2);
        store.set("aurum.lots", $("lotInput").value);
      }));
      $("pendingToggle").onclick = () => this.togglePending();
      ["pPrice", "pStop", "pTarget"].forEach((id) => ($(id).oninput = () => { this.updatePendingLabels(); this.syncLines(); }));
      $("pBuy").onclick = (e) => this.pendingOrder("long", e.currentTarget);
      $("pSell").onclick = (e) => this.pendingOrder("short", e.currentTarget);
      $("indBtn").onclick = () => this.indicatorSheet();
      $("chartSymbol").onclick = () => this.symbolSheet();
      $("closeAllBtn").onclick = (e) => this.closeAll(e.currentTarget);
    },

    indicatorSheet() {
      const allowed = this.owner || this.features.killzones !== false;
      const flowAllowed = this.owner || this.features.sharkflow !== false;
      sheet.open(`<h3>Chỉ báo</h3>
        <div class="toggles">${IND.filter(([k]) => (k === "flow" ? flowAllowed : allowed)).map(([k, n]) => `<label class="toggle"><span>${n}</span>
          <span class="switch"><input type="checkbox" data-k="${k}" ${showInd[k] ? "checked" : ""}><span></span></span></label>`).join("")}</div>
        <p class="muted small">Giờ theo New York như bản TradingView. Killzones chỉ hiện ở khung 30m trở xuống.</p>`, (el) => {
        el.querySelectorAll("input").forEach((i) => (i.onchange = () => {
          showInd[i.dataset.k] = i.checked;
          store.set("aurum.ind", JSON.stringify(showInd));
          this.computeICT(); this.redraw(); this.updateFlow();
        }));
      });
    },

    symbolSheet() {
      if (!this.owner) return;
      sheet.open(`<h3>Chọn mã</h3><div class="fields"><label>Tìm<input id="symQ" placeholder="XAU, EURUSD, BTC…" autocomplete="off"></label></div><div id="symList" class="list sym-list"></div>`, (el) => {
        const q = el.querySelector("#symQ");
        let timer = null;
        const search = async () => {
          const found = await this.call(`/mt5/symbols?q=${encodeURIComponent(q.value.trim())}&limit=40`).catch(() => null);
          const list = (found && found.symbols) || [];
          el.querySelector("#symList").innerHTML = list.map((x) => `<button type="button" class="sym-row" data-s="${esc(x.name)}"><b>${esc(x.name)}</b><span class="muted small">${esc(x.description)}</span></button>`).join("") || '<div class="empty">Không thấy mã</div>';
          el.querySelectorAll(".sym-row").forEach((b) => (b.onclick = () => {
            this.symbol = b.dataset.s; store.set("aurum.sym", this.symbol);
            sheet.close(); this.selected = null; this.loadCandles();
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
      if (this.draft) this.updatePendingLabels();
    },

    async loadCandles() {
      document.querySelectorAll("#tfButtons button").forEach((b) => b.classList.toggle("on", b.dataset.tf === this.interval));
      if (this.socket) { this.socket.close(); this.socket = null; }
      clearInterval(this.pollTimer); this.pollTimer = null;
      this.noOlder = false;
      const token = (this.loadToken = (this.loadToken || 0) + 1);
      try {
        if (this.owner) await this.ownerSymbol();
        const data = await this.call(this.exnessPath(800));
        if (token !== this.loadToken) return;
        const bars = this.toBars(data.candles || []);
        if (bars.length < 5) throw new Error("no bars");
        this.source = "exness";
        if (data.symbol) this.symbol = this.owner ? this.symbol : data.symbol;
        this.digits = data.digits != null ? data.digits : 2;
        this.applySeriesFormat();
        $("chartSymbol").textContent = data.symbol || this.symbol || "XAUUSD";
        $("chartSource").textContent = "· giá Exness";
        this.bars = bars;
        this.series.setData(bars.map(shown));
        this.chart.timeScale().scrollToRealTime();
        this.setQuote(data);
        this.computeICT();
        this.pollTimer = setInterval(() => this.pollBars(token), 2000);
      } catch {
        if (token !== this.loadToken) return;
        await this.loadBinance();
      }
      this.syncLines();
      this.updateFlow();
      this.redraw();
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
          this.series.update(shown(b));
        });
        this.setQuote(data);
        if (added || !this.ictTime || Date.now() - this.ictTime > 4000) this.computeICT();
        this.redraw();
      } catch { /* keep the chart */ } finally { this.polling = false; }
    },

    async loadOlder() {
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
        this.series.setData(this.bars.map(shown));
        if (range) this.chart.timeScale().setVisibleLogicalRange({ from: range.from + older.length, to: range.to + older.length });
        this.computeICT();
        this.redraw();
      } catch { this.noOlder = true; } finally { this.loadingOlder = false; }
    },

    async loadBinance() {
      this.source = "binance";
      this.digits = 2;
      this.applySeriesFormat();
      $("chartSymbol").textContent = "XAUUSD";
      $("chartSource").textContent = "· giá Binance XAUUSDT (tạm)";
      const interval = this.interval === "30m" ? "30m" : this.interval;
      try {
        const res = await fetch(`https://fapi.binance.com/fapi/v1/klines?symbol=XAUUSDT&interval=${interval}&limit=800`);
        const rows = await res.json();
        this.bars = rows.map((r) => ({ time: r[0] / 1000, open: +r[1], high: +r[2], low: +r[3], close: +r[4], volume: +r[5] }));
        this.series.setData(this.bars.map(shown));
        this.chart.timeScale().scrollToRealTime();
        this.setQuote({});
        this.computeICT();
      } catch { /* chart stays empty */ }
      const ws = new WebSocket(`wss://fstream.binance.com/ws/xauusdt@kline_${interval}`);
      ws.onmessage = (ev) => {
        const k = JSON.parse(ev.data).k;
        if (!k) return;
        const b = { time: k.t / 1000, open: +k.o, high: +k.h, low: +k.l, close: +k.c, volume: +k.v };
        const last = this.bars[this.bars.length - 1];
        if (last && b.time === last.time) this.bars[this.bars.length - 1] = b; else if (!last || b.time > last.time) { this.bars.push(b); this.computeICT(); }
        this.series.update(shown(b));
        this.setQuote({});
        this.redraw();
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
      if (this.owner) {
        const sel = this.selected;
        const onChart = (x) => x.symbol === this.symbol;
        const dim = (color, active) => (sel && !active ? rgba(color, 0.35) : color);
        this.positions.filter(onChart).forEach((p) => {
          const active = sel && sel.kind === "pos" && sel.ticket === p.ticket;
          const w = active ? 2 : 1;
          out.push({ key: `pos:${p.ticket}:entry`, price: p.entry, color: dim(p.side === "long" ? "#2b6bf3" : "#f0455a", active), width: w, style: 0, title: `${sideName(p.side)} ${p.lots} ${signed(p.profit)}` });
          if (p.stop) out.push({ key: `pos:${p.ticket}:stop`, price: p.stop, color: dim("#f0455a", active), width: w, style: 2, title: `SL ${active ? signed(this.pnlAt(p, p.stop)) : ""}` });
          if (p.target) out.push({ key: `pos:${p.ticket}:target`, price: p.target, color: dim("#14b88a", active), width: w, style: 2, title: `TP ${active ? signed(this.pnlAt(p, p.target)) : ""}` });
        });
        this.orders.filter(onChart).forEach((o) => {
          const active = sel && sel.kind === "ord" && sel.ticket === o.ticket;
          const w = active ? 2 : 1;
          out.push({ key: `ord:${o.ticket}:entry`, price: o.entry, color: dim(o.side === "long" ? "#2b6bf3" : "#f0455a", active), width: w, style: 1, title: `${sideName(o.side)} ${o.kind.toUpperCase()} ${o.lots}` });
          if (o.stop) out.push({ key: `ord:${o.ticket}:stop`, price: o.stop, color: dim("#f0455a", active), width: w, style: 2, title: "SL" });
          if (o.target) out.push({ key: `ord:${o.ticket}:target`, price: o.target, color: dim("#14b88a", active), width: w, style: 2, title: "TP" });
        });
        if (this.draft) {
          const price = num($("pPrice").value), stop = num($("pStop").value), target = num($("pTarget").value);
          if (price) out.push({ key: "draft:entry", price, color: "#9b6bff", width: 2, style: 0, title: "Giá chờ" });
          if (stop) out.push({ key: "draft:stop", price: stop, color: "#f0455a", width: 2, style: 2, title: "SL mới" });
          if (target) out.push({ key: "draft:target", price: target, color: "#14b88a", width: 2, style: 2, title: "TP mới" });
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

    /** Money at a price for a position, from its live profit (contract size worked out from it). */
    pnlAt(p, price) {
      const move = (p.price - p.entry) * (p.side === "long" ? 1 : -1);
      if (Math.abs(move) < 1e-9) return null;
      return p.profit / move * (price - p.entry) * (p.side === "long" ? 1 : -1);
    },

    syncLines() {
      if (!this.series) return;
      const wanted = this.wantedLines();
      const keys = new Set();
      wanted.forEach((w) => {
        keys.add(w.key);
        if (this.drag && this.drag.key === w.key) return; // the finger owns it
        const opts = { price: w.price, color: w.color, lineWidth: w.width, lineStyle: w.style, axisLabelVisible: true, title: w.title };
        const line = this.lines.get(w.key);
        if (line) line.applyOptions(opts); else this.lines.set(w.key, this.series.createPriceLine(opts));
      });
      for (const [k, line] of this.lines) {
        if (!keys.has(k) && !(this.drag && this.drag.key === k)) { this.series.removePriceLine(line); this.lines.delete(k); }
      }
      this.lineCache = wanted;
      // While a trade is picked (or a pending price is set), a finger on the chart drags lines, not the page.
      $("chartWrap").style.touchAction = this.owner && (this.selected || this.draft) ? "none" : "";
    },

    renderSelBar() {
      const bar = $("selBar");
      const x = this.findSelected();
      if (!this.owner || !x) { bar.hidden = true; return; }
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
      const dir = (x.side === "long" ? 1 : -1) * (a === "target" ? 1 : -1);
      const level = +(x.entry + dir * dist).toFixed(this.digits);
      const body = { ticket: x.ticket, stop: a === "stop" ? level : x.stop, target: a === "target" ? level : x.target };
      if (!pos) body.price = x.entry;
      await act(button, () => this.call("/mt5/modify", body), `Đã thêm ${a === "stop" ? "SL" : "TP"} — kéo để chỉnh`);
      this.refresh();
    },

    /* ----- touch & drag on the chart ----- */

    bindDrag() {
      const wrap = $("chartWrap");
      const yOf = (e) => e.clientY - wrap.getBoundingClientRect().top;
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
        if (key.startsWith("draft:")) return true;
        const s = this.selected;
        if (!s) return false;
        const [kind, ticket, field] = key.split(":");
        if (kind !== s.kind || +ticket !== s.ticket) return false;
        return field !== "entry" || kind === "ord";
      };
      let down = null;
      wrap.addEventListener("pointerdown", (e) => {
        if (!this.owner || e.button > 0 || e.target.closest("#selBar, #posPill")) return;
        const y = yOf(e), x = e.clientX - wrap.getBoundingClientRect().left;
        down = { x: e.clientX, y: e.clientY, moved: false };
        if (x > paneWidth()) return;
        const w = hit(y, draggable);
        if (!w) return;
        this.drag = { key: w.key, price: w.price, start: w.price };
        this.chart.applyOptions({ handleScroll: false, handleScale: false });
        e.stopPropagation();
      }, true);
      ["mousedown", "touchstart"].forEach((t) => wrap.addEventListener(t, (e) => { if (this.drag) e.stopPropagation(); }, { capture: true, passive: true }));
      wrap.addEventListener("touchmove", (e) => { if (this.drag) e.preventDefault(); }, { passive: false });
      wrap.addEventListener("pointermove", (e) => {
        if (this.drag || !this.owner || e.pointerType !== "mouse") return;
        const x = e.clientX - wrap.getBoundingClientRect().left;
        wrap.style.cursor = x <= paneWidth() && hit(yOf(e), draggable) ? "ns-resize" : "";
      });
      window.addEventListener("pointermove", (e) => {
        if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 6) down.moved = true;
        if (!this.drag) return;
        const price = this.series.coordinateToPrice(yOf(e));
        if (price == null) return;
        this.drag.price = +price.toFixed(this.digits);
        const line = this.lines.get(this.drag.key);
        if (line) line.applyOptions({ price: this.drag.price, title: this.dragTitle(this.drag) });
        if (this.drag.key.startsWith("draft:")) this.writeDraft(this.drag.key, this.drag.price);
        this.redraw();
      });
      window.addEventListener("pointerup", (e) => {
        const d = this.drag, tap = down && !down.moved;
        down = null;
        if (d) {
          this.drag = null;
          this.chart.applyOptions({ handleScroll: true, handleScale: true });
          if (Math.abs(d.price - d.start) > 0) this.commitDrag(d); else this.syncLines();
          return;
        }
        if (tap && this.owner && e.target && wrap.contains(e.target)) this.tapChart(yOf(e), e.clientX - wrap.getBoundingClientRect().left);
      });
      window.addEventListener("pointercancel", () => { if (this.drag) { this.drag = null; this.chart.applyOptions({ handleScroll: true, handleScale: true }); this.syncLines(); } down = null; });
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

    writeDraft(key, price) {
      const id = { "draft:entry": "pPrice", "draft:stop": "pStop", "draft:target": "pTarget" }[key];
      $(id).value = fmt(price, this.digits);
      this.updatePendingLabels();
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
      // Show the new level at once; the next refresh confirms it.
      if (field === "entry") x.entry = d.price; else x[field] = d.price;
      this.syncLines();
      const ok = await act(null, () => this.call("/mt5/modify", body), `Đã dời ${field === "stop" ? "SL" : field === "target" ? "TP" : "giá"} → ${fmt(d.price, this.digits)}`);
      this.refresh();
      void ok;
    },

    /** A tap picks a trade by its entry line (the next one when several share a price). */
    tapChart(y, x) {
      if (x > this.chart.timeScale().width()) return;
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

    /* ----- ICT overlay ----- */

    computeICT() {
      this.ictTime = Date.now();
      const allowed = this.owner || this.features.killzones !== false;
      if (!allowed || !this.bars.length || !window.ICT) { this.ict = null; return; }
      try {
        this.ict = window.ICT.compute(this.bars, TF_SECONDS[this.interval], showInd);
      } catch { this.ict = null; }
    },

    redraw() {
      if (this.frame) return;
      this.frame = requestAnimationFrame(() => { this.frame = null; this.draw(); });
    },

    draw() {
      const canvas = $("overlay");
      if (!this.chart || !canvas || this.tab !== "chart") return;
      const wrap = $("chartWrap");
      const ts = this.chart.timeScale();
      const w = ts.width(), h = wrap.clientHeight - ts.height();
      const dpr = window.devicePixelRatio || 1;
      if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
        canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
        canvas.style.width = w + "px"; canvas.style.height = h + "px";
      }
      const g = canvas.getContext("2d");
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, w, h);
      const o = this.ict;
      if (!o || !this.bars.length) return;
      const X = (i) => ts.logicalToCoordinate(i);
      const Y = (p) => this.series.priceToCoordinate(p);
      const half = Math.max(1, ((X(1) || 0) - (X(0) || 0)) / 2);
      const right = w;
      const xEnd = (end) => (end == null ? right : X(end) + half);
      g.font = "10px Be Vietnam Pro, system-ui";
      g.textBaseline = "bottom";
      const line = (x1, x2, y, color, width = 1, dash = []) => {
        if (y == null || x2 < 0 || x1 > w) return;
        g.strokeStyle = color; g.lineWidth = width; g.setLineDash(dash);
        g.beginPath(); g.moveTo(x1, Math.round(y) + 0.5); g.lineTo(x2, Math.round(y) + 0.5); g.stroke();
      };
      const label = (text, x, y, color, align = "right") => {
        if (!text || y == null) return;
        g.fillStyle = color; g.textAlign = align;
        g.fillText(text, Math.min(Math.max(x, 2), w - 2), y - 2);
      };

      if (o.hidden) { g.fillStyle = "#8b95a7"; g.textAlign = "left"; g.fillText("Killzones chỉ hiện ở khung 30m trở xuống", 8, 16); }

      o.stamps.forEach((i) => {
        const x = X(i) - half;
        g.strokeStyle = "#787b8655"; g.lineWidth = 1; g.setLineDash([2, 3]);
        g.beginPath(); g.moveTo(Math.round(x) + 0.5, 0); g.lineTo(Math.round(x) + 0.5, h); g.stroke();
      });

      o.boxes.forEach((b) => {
        const x1 = X(b.start) - half, x2 = X(b.end) + half, y1 = Y(b.high), y2 = Y(b.low);
        if (x2 < 0 || x1 > w || y1 == null || y2 == null) return;
        g.fillStyle = b.color + "1f";
        g.fillRect(x1, y1, x2 - x1, y2 - y1);
        g.setLineDash([]); g.strokeStyle = b.color + "55"; g.lineWidth = 1;
        g.strokeRect(Math.round(x1) + 0.5, Math.round(y1) + 0.5, Math.round(x2 - x1), Math.round(y2 - y1));
        label(b.label, x1 + 2, y1, b.color, "left");
      });

      o.macros.forEach((b) => {
        const x1 = X(b.start) - half, x2 = X(b.end) + half, y1 = Y(b.high), y2 = Y(b.low);
        if (x2 < 0 || x1 > w || y1 == null || y2 == null) return;
        g.setLineDash([2, 2]); g.strokeStyle = "#787b8699"; g.lineWidth = 1;
        g.strokeRect(Math.round(x1) + 0.5, Math.round(y1) + 0.5, Math.round(x2 - x1), Math.round(y2 - y1));
      });

      o.levels.forEach((l) => {
        if (l.daily && !showInd.daily) return;
        const x1 = X(l.start), x2 = xEnd(l.end), y = Y(l.price);
        if (l.daily) {
          line(x1, x2, y, l.color + (l.mitigated ? "99" : "cc"), 1, l.mitigated ? [2, 3] : []);
          return;
        }
        if (l.open) { line(x1, x2, y, "#787b86aa", 1, [5, 4]); label(l.label, x2 - 2, y, "#8b95a7"); return; }
        line(x1, x2, y, l.color + (l.mitigated ? "88" : "ee"), 1, []);
        label(l.label, x2 - 2, y, l.color);
      });

      if (showInd.fvg) {
        o.fvgs.forEach((f) => {
          const x1 = X(f.start) - half, x2 = X(f.end) + half, yt = Y(f.top), yb = Y(f.bottom);
          if (x2 < 0 || x1 > w || yt == null || yb == null) return;
          const color = (f.bull ? "#089981" : "#f23645") + (f.touched ? "99" : "ff");
          if (f.confluence) { g.fillStyle = "#8c8f9926"; g.fillRect(x1, yt, x2 - x1, yb - yt); }
          line(x1, x2, yt, color, 1.2); line(x1, x2, yb, color, 1.2);
          line(x1, x2, (yt + yb) / 2, f.confluence ? "#9c27b0" : color, 0.8, [3, 3]);
        });
        o.vis.forEach((f) => {
          const x1 = X(f.start) - half, x2 = X(f.end) + half;
          const color = "#fa9900" + (f.touched ? "8c" : "ff");
          line(x1, x2, Y(f.top), color, 0.8, [3, 2]); line(x1, x2, Y(f.bottom), color, 0.8, [3, 2]);
        });
      }

      if (showInd.mss) {
        o.breaks.forEach((b) => {
          const x1 = X(b.start), x2 = X(b.end), y = Y(b.price);
          const color = b.bull ? "#089981" : "#f23645";
          line(x1, x2, y, color, 1, [4, 3]);
          if (y != null) { g.fillStyle = color; g.textAlign = "center"; g.textBaseline = b.bull ? "bottom" : "top"; g.fillText("MSS", (x1 + x2) / 2, b.bull ? y - 2 : y + 2); g.textBaseline = "bottom"; }
        });
      }

      o.sweeps.forEach((s) => {
        const x = X(s.index), y = Y(s.price);
        if (x == null || y == null || x < 0 || x > w) return;
        g.fillStyle = "#fa9900"; g.textAlign = "center"; g.textBaseline = s.bull ? "top" : "bottom";
        g.fillText("✕ " + s.label, x, s.bull ? y + 3 : y - 3);
        g.textBaseline = "bottom";
      });
      g.setLineDash([]);
    },

    /* ----- money flow / news flash above the chart ----- */

    updateFlow() {
      const box = $("flowBox");
      const nowS = Date.now() / 1000;
      // A red USD release in the last minute takes the place of the money flow.
      const fresh = this.goldEvents(3).find((e) => e.time <= nowS && nowS - e.time < 60);
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
      const f = allowed && showInd.flow && window.ICT ? window.ICT.sharkFlow(this.bars) : null;
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
  if (/[?&]debug\b/.test(location.search)) window.__aurum = Member; // for automated tests
  $("loginForm").addEventListener("submit", (e) => { e.preventDefault(); Member.login(); });
  $("modeBtn").addEventListener("click", () => Member.setLoginMode(Member.loginMode === "owner" ? "member" : "owner"));
  $("logoutBtn").addEventListener("click", () => Member.logout());
  route();
})();
