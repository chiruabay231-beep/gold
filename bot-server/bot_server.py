#!/usr/bin/env python3
"""Gold bot server: runs the app's strategies 24/7 on a VPS.

* Prices: Binance Futures / Binance Spot (public, free) or MetaTrader 5 (Exness).
* Orders: a demo (paper) account kept here, or real MT5 orders (phase 2).
* Strategy code runs in botkit(.exe), the same Swift engine as the app.
* The iPhone app controls the bot over HTTPS (Cloudflare quick tunnel) with a
  password; Telegram gets every fill.

Standard library only; MetaTrader5 (pip) is needed only for the MT5 source.
Run:  python bot_server.py            (reads config.json next to this file)
      python bot_server.py --selftest (checks botkit with sample data)
"""

import hashlib
import hmac
import json
import math
import os
import random
import re
import secrets
import subprocess
import sys
import threading
import time
import traceback
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "2.1"
RELEASE_ZIP = "https://github.com/chiruabay231-beep/gold/releases/download/bot-latest/gold-bot-windows.zip"
# Exit code that tells run.ps1 to restart at once and keep the tunnel (same address).
UPDATE_EXIT_CODE = 3
HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(HERE, "config.json")
STATE_PATH = os.path.join(HERE, "state.json")
LOG_PATH = os.path.join(HERE, "server.log")
IS_WINDOWS = os.name == "nt"
NO_WINDOW = 0x08000000 if IS_WINDOWS else 0  # CREATE_NO_WINDOW

# Windows consoles default to cp1252, which cannot print Vietnamese.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

DEFAULT_CONFIG = {
    "password": "",
    "port": 8787,
    "telegram": {"token": "", "chat_id": ""},
    # Cloudflare quick tunnel: gives an https://….trycloudflare.com address.
    "tunnel": True,
    # The app looks the address up here when it changes (empty = off).
    "url_relay": "https://ntfy.sh",
    "cloudflared": "",
    "botkit": "",
    "poll_seconds": 2,
    "history_bars": 1000,
    "paper_balance": 10000,
    "mt5": {
        "path": "",          # terminal64.exe, empty = installed default
        "login": 0,
        "password": "",      # investor (read-only) password is enough for prices
        "server": "",
        # Real orders need both of these; the app must also choose broker "mt5".
        "trading_enabled": False,
        "allow_real_account": False,
        "max_lots": 0.10,
        "magic": 20260,
        "deviation": 30,
    },
    # Only for testing without internet: bars every N seconds.
    "sample_bar_seconds": 0,
}

INTERVALS = {"1m": 60, "5m": 300, "15m": 900, "30m": 1800, "1h": 3600, "4h": 14400, "1d": 86400}
SOURCES = ("binance_futures", "binance_spot", "mt5", "sample")


class _NoLock:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def now():
    return time.time()


def fmt(price):
    if price is None:
        return "—"
    return f"{price:.2f}" if abs(price) >= 10 else f"{price:.5f}"


def money(value):
    return f"{value:+.2f}$"


def contract_size(symbol):
    s = symbol.upper().replace("_", "")
    if s.startswith("XAU") or s.startswith("PAXG"):
        return 100.0
    if s.startswith("XAG"):
        return 5000.0
    cur = ("EUR", "GBP", "USD", "JPY", "AUD", "NZD", "CAD", "CHF")
    if len(s) == 6 and s[:3] in cur and s[3:] in cur:
        return 100000.0
    return 1.0


def pid_alive(pid):
    if IS_WINDOWS:
        import ctypes
        kernel = ctypes.windll.kernel32
        handle = kernel.OpenProcess(0x1000, False, int(pid))  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        code = ctypes.c_ulong()
        ok = kernel.GetExitCodeProcess(handle, ctypes.byref(code))
        kernel.CloseHandle(handle)
        return bool(ok) and code.value == 259  # STILL_ACTIVE
    try:
        os.kill(int(pid), 0)
        return True
    except OSError:
        return False


def merge(defaults, values):
    out = dict(defaults)
    for key, value in (values or {}).items():
        if isinstance(out.get(key), dict) and isinstance(value, dict):
            out[key] = merge(out[key], value)
        else:
            out[key] = value
    return out


def read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8-sig") as f:  # PowerShell writes a BOM
            return json.load(f)
    except FileNotFoundError:
        return default
    except Exception as e:  # a broken file must not stop the bot
        print(f"Không đọc được {path}: {e}", file=sys.stderr)
        return default


def write_json(path, value):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def http_json(url, data=None, timeout=15):
    body = None
    headers = {"User-Agent": "gold-bot/" + VERSION}
    if data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


# --------------------------------------------------------------------------
# Strategy engine (botkit)
# --------------------------------------------------------------------------

def botkit_path(config):
    if config.get("botkit"):
        return config["botkit"]
    name = "botkit.exe" if IS_WINDOWS else "botkit"
    for candidate in (os.path.join(HERE, name), os.path.join(HERE, "bin", name),
                      os.path.join(HERE, "..", ".build", "release", name)):
        if os.path.exists(candidate):
            return os.path.abspath(candidate)
    return name


def run_botkit(config, request, timeout=120):
    try:
        proc = subprocess.run([botkit_path(config)], input=json.dumps(request).encode(),
                              capture_output=True, timeout=timeout, creationflags=NO_WINDOW)
    except FileNotFoundError:
        return {"ok": False, "error": "Không tìm thấy botkit"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "botkit chạy quá lâu"}
    out = proc.stdout.decode("utf-8", "replace").strip()
    try:
        return json.loads(out.splitlines()[-1])
    except Exception:
        err = proc.stderr.decode("utf-8", "replace").strip()
        return {"ok": False, "error": (err or out or f"botkit lỗi {proc.returncode}")[-500:]}


def botkit_id(position_id):
    """botkit needs UUIDs; MT5 tickets are numbers."""
    try:
        return str(uuid.UUID(position_id)).upper()
    except ValueError:
        return str(uuid.UUID(int=int(position_id))).upper()


# --------------------------------------------------------------------------
# Price feeds. poll() returns recent bars [t, o, h, l, c, v]; the last one is
# still forming.
# --------------------------------------------------------------------------

class BinanceFeed:
    def __init__(self, futures, symbol, interval):
        self.futures = futures
        self.symbol = symbol.upper().replace("_", "")
        self.interval = interval
        if futures:
            self.hosts = ["https://fapi.binance.com/fapi/v1/klines"]
        else:
            self.hosts = ["https://api.binance.com/api/v3/klines", "https://api1.binance.com/api/v3/klines",
                          "https://data-api.binance.vision/api/v3/klines"]

    def _klines(self, limit, end_ms=None):
        query = {"symbol": self.symbol, "interval": self.interval, "limit": limit}
        if end_ms:
            query["endTime"] = end_ms
        last_error = None
        for host in self.hosts:
            try:
                rows = http_json(host + "?" + urllib.parse.urlencode(query))
                return [[r[0] / 1000, float(r[1]), float(r[2]), float(r[3]), float(r[4]), float(r[5])] for r in rows]
            except Exception as e:
                last_error = e
        raise RuntimeError(f"Binance: {last_error}")

    def history(self, count):
        limit = 1500 if self.futures else 1000
        bars = []
        end = None
        while len(bars) < count:
            chunk = self._klines(min(limit, count - len(bars)), end)
            if not chunk:
                break
            bars = chunk + bars
            end = int(chunk[0][0] * 1000) - 1
            if len(chunk) < limit:
                break
        return bars

    def poll(self):
        return self._klines(3)

    def price(self, bars):
        return bars[-1][4] if bars else None

    def close(self):
        pass


class SampleFeed:
    """Random walk for testing without a network."""

    def __init__(self, symbol, interval, bar_seconds):
        self.symbol = symbol
        self.step = bar_seconds or INTERVALS.get(interval, 60)
        self.rng = random.Random(7)
        self.bars = []
        price = 2650.0
        start = int(now() // self.step) * self.step - 600 * self.step
        for i in range(600):
            self.bars.append(self._bar(start + i * self.step, price))
            price = self.bars[-1][4]

    def _bar(self, t, open_price):
        close = open_price + self.rng.gauss(0, 1.5)
        high = max(open_price, close) + abs(self.rng.gauss(0, 0.6))
        low = min(open_price, close) - abs(self.rng.gauss(0, 0.6))
        return [t, open_price, high, low, close, 100.0]

    def history(self, count):
        self.poll()
        return [list(b) for b in self.bars[-count:]]

    def poll(self):
        t = int(now() // self.step) * self.step
        while self.bars[-1][0] < t:
            self.bars.append(self._bar(self.bars[-1][0] + self.step, self.bars[-1][4]))
        last = self.bars[-1]
        tick = last[4] + self.rng.gauss(0, 0.3)
        last[4] = tick
        last[2] = max(last[2], tick)
        last[3] = min(last[3], tick)
        return [list(b) for b in self.bars[-3:]]

    def price(self, bars):
        return bars[-1][4] if bars else None

    def close(self):
        pass


class Mt5:
    """Shared MetaTrader 5 connection (one terminal per process)."""
    lock = threading.RLock()
    module = None
    connected = False
    error = ""

    @classmethod
    def connect(cls, cfg):
        with cls.lock:
            if cls.module is None:
                try:
                    import MetaTrader5  # noqa: only on Windows
                    cls.module = MetaTrader5
                except ImportError:
                    cls.error = "Chưa cài MetaTrader5 (pip install MetaTrader5) — chỉ chạy trên Windows"
                    raise RuntimeError(cls.error)
            mt5 = cls.module
            if cls.connected and mt5.terminal_info() is not None:
                return mt5
            kwargs = {}
            if cfg.get("path"):
                kwargs["path"] = cfg["path"]
            if cfg.get("login"):
                kwargs.update(login=int(cfg["login"]), password=str(cfg.get("password", "")),
                              server=str(cfg.get("server", "")))
            if not mt5.initialize(**kwargs):
                cls.connected = False
                cls.error = f"MT5 không kết nối được: {mt5.last_error()}"
                raise RuntimeError(cls.error)
            cls.connected = True
            cls.error = ""
            return mt5

    # Brokers stamp bars in their server time (Exness: UTC, many others UTC+2/+3).
    offset_seconds = 0

    @classmethod
    def detect_offset(cls, symbol):
        """Server-time offset from a fresh tick; kept while the market is closed."""
        tick = cls.module.symbol_info_tick(symbol) if cls.module else None
        if tick is None or not tick.time:
            return cls.offset_seconds
        hours = (tick.time - now()) / 3600
        # A tick from the last few minutes tells the offset; an old one (weekend) does not.
        if abs(hours - round(hours)) < 0.1 and abs(round(hours)) <= 14:
            cls.offset_seconds = int(round(hours)) * 3600
        return cls.offset_seconds

    @classmethod
    def bars(cls, rates):
        offset = cls.offset_seconds
        return [[float(r["time"]) - offset, float(r["open"]), float(r["high"]), float(r["low"]), float(r["close"]),
                 float(r["tick_volume"])] for r in rates]


MT5_TIMEFRAMES = {"1m": "M1", "5m": "M5", "15m": "M15", "30m": "M30", "1h": "H1", "4h": "H4", "1d": "D1", "1w": "W1"}


class Mt5Feed:
    def __init__(self, cfg, symbol, interval):
        self.cfg = cfg
        self.symbol = symbol
        mt5 = Mt5.connect(cfg)
        self.timeframe = getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[interval])
        if not mt5.symbol_select(symbol, True):
            raise RuntimeError(f"MT5 không có mã {symbol} (Exness thường là XAUUSDm hoặc XAUUSD)")

    def _rates(self, count):
        mt5 = Mt5.connect(self.cfg)
        Mt5.detect_offset(self.symbol)
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, count)
        if rates is None:
            raise RuntimeError(f"MT5 copy_rates lỗi: {mt5.last_error()}")
        return Mt5.bars(rates)

    def history(self, count):
        return self._rates(count)

    def poll(self):
        return self._rates(3)

    def price(self, bars):
        tick = Mt5.connect(self.cfg).symbol_info_tick(self.symbol)
        if tick is not None and tick.bid > 0:
            return float(tick.bid)
        return bars[-1][4] if bars else None

    def close(self):
        pass


MT5_WINDOW_CLASS = "MetaQuotes::MetaTrader::5.00"
# WM_COMMAND id of the toolbar's Algo Trading button (a toggle).
MT5_CMD_ALGO_TRADING = 32851


def mt5_windows(login=None):
    """Top-level MT5 terminal windows, those showing `login` in the title first."""
    if os.name != "nt":
        return []
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def visit(hwnd, _):
        name = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(hwnd, name, 256)
        if name.value == MT5_WINDOW_CLASS:
            title = ctypes.create_unicode_buffer(512)
            user32.GetWindowTextW(hwnd, title, 512)
            found.append((hwnd, title.value))
        return True

    user32.EnumWindows(visit, 0)
    if login:
        mine = [w for w in found if str(login) in w[1]]
        return mine if mine else (found if len(found) == 1 else [])
    return found


def write_algo_ini(data_path):
    """Algo Trading on at start, and not turned off when the account changes."""
    path = os.path.join(data_path, "config", "common.ini")
    text = ""
    for encoding in ("utf-16", "utf-8"):
        try:
            with open(path, encoding=encoding) as f:
                text = f.read()
            break
        except (OSError, UnicodeError):
            continue
    wanted = {"Enabled": "1", "Account": "0", "Profile": "0", "AllowLiveTrading": "1"}
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip().lower() == "[experts]")
    except StopIteration:
        lines += ["[Experts]"]
        start = len(lines) - 1
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    section = [l for l in lines[start + 1:end] if l.split("=")[0].strip() not in wanted]
    section += [f"{k}={v}" for k, v in wanted.items()]
    lines[start + 1:end] = section
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-16") as f:
        f.write("\n".join(lines) + "\n")


def ensure_algo_trading(mt5, cfg, log=None, restart=True):
    """Turns MT5's Algo Trading back on (MT5 turns it off when the account changes).

    First presses the button by window message; if that does not work, closes the
    terminal, writes Enabled=1 / Account=0 into its common.ini and starts it again,
    so later account changes keep it on. Returns True when trading is allowed."""
    def allowed():
        t = mt5.terminal_info()
        return t is not None and bool(t.trade_allowed)

    for _ in range(8):  # MT5 switches it off a moment after the login
        if not allowed():
            break
        time.sleep(0.25)
    else:
        return True
    # Only press the toggle when the terminal answers and says it is off.
    if os.name != "nt" or mt5.terminal_info() is None:
        return False
    import ctypes
    a = mt5.account_info()
    windows = mt5_windows(a.login if a else None)
    for hwnd, _ in windows[:1]:
        ctypes.windll.user32.PostMessageW(hwnd, 0x0111, MT5_CMD_ALGO_TRADING, 0)
        for _ in range(20):
            time.sleep(0.25)
            if allowed():
                if log:
                    log("⚙️ Đã tự bật Algo Trading trong MT5")
                return True
    if not restart:
        return False
    # Restart the terminal with the setting written down.
    t = mt5.terminal_info()
    if t is None or not getattr(t, "data_path", None):
        return False
    exe = os.path.join(t.path, "terminal64.exe") if getattr(t, "path", None) else cfg.get("path")
    data_path = t.data_path
    for hwnd, _ in windows[:1]:
        ctypes.windll.user32.PostMessageW(hwnd, 0x0010, 0, 0)  # WM_CLOSE
    mt5.shutdown()
    Mt5.connected = False
    for _ in range(60):
        if not mt5_windows(a.login if a else None):
            break
        time.sleep(0.5)
    try:
        write_algo_ini(data_path)
    except OSError:
        pass
    restart = dict(cfg)
    if exe:
        restart["path"] = exe
    try:
        mt5 = Mt5.connect(restart)
    except RuntimeError:
        return False
    for _ in range(20):
        if allowed():
            if log:
                log("⚙️ Đã khởi động lại MT5 với Algo Trading bật sẵn")
            return True
        time.sleep(0.25)
    return False


def mt5_send(mt5, request):
    """order_send trying the symbol's filling modes; returns (result, error text)."""
    info = mt5.symbol_info(request["symbol"]) if request.get("symbol") else None
    modes = []
    if info is not None:
        if info.filling_mode & 1:
            modes.append(mt5.ORDER_FILLING_FOK)
        if info.filling_mode & 2:
            modes.append(mt5.ORDER_FILLING_IOC)
    modes.append(mt5.ORDER_FILLING_RETURN)
    result = None
    for mode in modes:
        request["type_filling"] = mode
        result = mt5.order_send(request)
        if result is not None and result.retcode != mt5.TRADE_RETCODE_INVALID_FILL:
            break
    if result is None:
        return None, f"order_send lỗi: {mt5.last_error()}"
    if result.retcode not in (mt5.TRADE_RETCODE_DONE, mt5.TRADE_RETCODE_PLACED):
        return None, f"MT5 từ chối ({result.retcode}): {result.comment}"
    return result, None


# Orders placed by hand from the app; the bot only manages its own magic number.
APP_MAGIC = 20261


class Mt5Account:
    """MT5 login and market data for the app (Live chart source "MT5 (VPS)").

    Every call holds Mt5.lock: the MetaTrader5 package is one connection per
    process and the bot loop uses it too."""

    def __init__(self, server):
        self.server = server

    @property
    def cfg(self):
        return self.server.config["mt5"]

    def _mt5(self):
        return Mt5.connect(self.cfg)

    def status(self):
        with Mt5.lock:
            try:
                mt5 = self._mt5()
            except RuntimeError as e:
                return {"ok": True, "connected": False, "error": str(e)}
            a = mt5.account_info()
            t = mt5.terminal_info()
            if a is None:
                return {"ok": True, "connected": False, "error": f"MT5 chưa đăng nhập tài khoản: {mt5.last_error()}",
                        "terminal": t.name if t else None}
            mode = {mt5.ACCOUNT_TRADE_MODE_DEMO: "demo", mt5.ACCOUNT_TRADE_MODE_REAL: "real"}.get(a.trade_mode, "contest")
            return {"ok": True, "connected": bool(t.connected) if t else True, "login": a.login, "server": a.server,
                    "name": a.name, "company": a.company, "currency": a.currency, "balance": a.balance,
                    "equity": a.equity, "leverage": a.leverage, "mode": mode, "tradeAllowed": bool(a.trade_allowed),
                    "terminal": t.name if t else None, "remembered": bool(self.cfg.get("login")),
                    "offsetHours": Mt5.offset_seconds / 3600}

    def login(self, body):
        try:
            login = int(str(body.get("login", "")).strip())
        except ValueError:
            raise ValueError("Số tài khoản MT5 phải là số")
        password = str(body.get("password", ""))
        server = str(body.get("server", "")).strip()
        if not password or not server:
            raise ValueError("Cần mật khẩu và tên máy chủ (server) MT5")
        s = self.server.settings
        if s.get("running") and s.get("broker") == "mt5" and int(self.cfg.get("login") or 0) != login:
            raise ValueError("Bot đang đặt lệnh trên tài khoản MT5 hiện tại: dừng bot trước khi đổi tài khoản")
        with Mt5.lock:
            cfg = dict(self.cfg, login=login, password=password, server=server)
            if body.get("path"):
                cfg["path"] = str(body["path"])
            mt5 = None
            if Mt5.module is not None and Mt5.connected and Mt5.module.terminal_info() is not None:
                mt5 = Mt5.module
                if not mt5.login(login, password=password, server=server):
                    raise ValueError(f"Đăng nhập thất bại ({mt5.last_error()}). Kiểm tra số tài khoản, mật khẩu, server.")
            else:
                Mt5.connected = False
                try:
                    mt5 = Mt5.connect(cfg)
                except RuntimeError as e:
                    raise ValueError(str(e))
                if mt5.account_info() is None or mt5.account_info().login != login:
                    raise ValueError(f"Đăng nhập thất bại ({mt5.last_error()}). Kiểm tra số tài khoản, mật khẩu, server.")
            if body.get("remember", True):
                self.cfg.update(login=login, password=password, server=server)
                if body.get("path"):
                    self.cfg["path"] = str(body["path"])
            else:
                self.cfg.update(login=0, password="", server="")
            self.server.save_config()
            if not ensure_algo_trading(mt5, cfg, self.server.log):
                self.server.log("⚠️ Algo Trading trong MT5 đang tắt: bật nút Algo Trading trên VPS để đặt lệnh")
        self.server.log(f"🔑 Đăng nhập MT5 #{login} ({server})")
        return self.status()

    def logout(self):
        s = self.server.settings
        if s.get("running") and (s.get("broker") == "mt5" or s.get("source") == "mt5"):
            raise ValueError("Bot đang dùng MT5: dừng bot trước khi đăng xuất")
        with Mt5.lock:
            self.cfg.update(login=0, password="", server="")
            self.server.save_config()
            if Mt5.module is not None:
                Mt5.module.shutdown()
            Mt5.connected = False
        self.server.log("🔒 Đã đăng xuất MT5 và xoá mật khẩu đã lưu")
        return {"ok": True, "connected": False}

    def symbols(self, query, limit=150):
        with Mt5.lock:
            mt5 = self._mt5()
            rows = mt5.symbols_get() or ()
            q = query.strip().lower()
            found = [r for r in rows if not q or q in r.name.lower() or q in (r.description or "").lower()]
            # Symbols in Market Watch first, then by name.
            found.sort(key=lambda r: (not r.visible, len(r.name), r.name))
            return {"ok": True, "total": len(rows),
                    "symbols": [{"name": r.name, "description": r.description or "", "path": r.path or "",
                                 "digits": r.digits} for r in found[:limit]]}

    # ----- Trading by hand from the app -----

    def _check_trading(self, mt5):
        a = mt5.account_info()
        if a is None:
            raise ValueError("MT5 chưa đăng nhập tài khoản")
        if not self.cfg.get("trading_enabled"):
            raise ValueError("Chưa cho phép đặt lệnh: bật \"Cho phép đặt lệnh từ app\" ở Giao dịch → Đăng nhập sàn")
        if a.trade_mode == mt5.ACCOUNT_TRADE_MODE_REAL and not self.cfg.get("allow_real_account"):
            raise ValueError("Đây là tài khoản THẬT: bật \"Cho phép tài khoản thật\" ở Giao dịch → Đăng nhập sàn")
        if not a.trade_allowed:
            raise ValueError("Tài khoản không cho giao dịch (đang dùng mật khẩu investor? cần mật khẩu chính)")
        t = mt5.terminal_info()
        if t is not None and not t.trade_allowed:
            if not ensure_algo_trading(mt5, self.cfg, self.server.log):
                raise ValueError("Bật nút Algo Trading trong MT5 trên VPS")
            a = Mt5.module.account_info() or a
        return a

    def settings(self, body):
        with Mt5.lock:
            for key in ("trading_enabled", "allow_real_account"):
                if key in body:
                    self.cfg[key] = bool(body[key])
            if "max_lots" in body:
                self.cfg["max_lots"] = max(0.01, min(float(body["max_lots"]), 100.0))
            self.server.save_config()
        self.server.log(f"⚙︎ MT5: đặt lệnh từ app {'BẬT' if self.cfg.get('trading_enabled') else 'TẮT'}, "
                        f"tài khoản thật {'cho phép' if self.cfg.get('allow_real_account') else 'chặn'}, "
                        f"tối đa {self.cfg.get('max_lots')} lot")
        return self.trading()

    def _volume(self, mt5, info, lots):
        max_lots = float(self.cfg.get("max_lots", 0.1))
        if lots > max_lots + 1e-9:
            raise ValueError(f"Khối lượng {lots} lớn hơn giới hạn {max_lots} lot (đổi ở Đăng nhập sàn)")
        step = info.volume_step or 0.01
        volume = max(info.volume_min, math.floor(lots / step + 1e-9) * step)
        return round(volume, 8)

    def trading(self, symbol=None):
        """Positions, pending orders and today's closed deals of the account."""
        with Mt5.lock:
            mt5 = self._mt5()
            a = mt5.account_info()
            offset = Mt5.offset_seconds
            positions = []
            for r in (mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()) or ():
                positions.append({"ticket": int(r.ticket), "symbol": r.symbol,
                                  "side": "long" if r.type == mt5.POSITION_TYPE_BUY else "short", "lots": r.volume,
                                  "entry": r.price_open, "price": r.price_current, "stop": r.sl or None,
                                  "target": r.tp or None, "profit": r.profit + getattr(r, "swap", 0),
                                  "time": float(r.time) - offset, "bot": r.magic == int(self.cfg.get("magic", 20260)),
                                  "comment": r.comment})
            orders = []
            kinds = {mt5.ORDER_TYPE_BUY_LIMIT: ("long", "limit"), mt5.ORDER_TYPE_SELL_LIMIT: ("short", "limit"),
                     mt5.ORDER_TYPE_BUY_STOP: ("long", "stop"), mt5.ORDER_TYPE_SELL_STOP: ("short", "stop")}
            for o in (mt5.orders_get(symbol=symbol) if symbol else mt5.orders_get()) or ():
                side, kind = kinds.get(o.type, ("long", "other"))
                orders.append({"ticket": int(o.ticket), "symbol": o.symbol, "side": side, "kind": kind,
                               "lots": o.volume_current, "entry": o.price_open, "stop": o.sl or None,
                               "target": o.tp or None, "time": float(o.time_setup) - offset})
            deals = []
            for d in mt5.history_deals_get(now() - 86400 + offset, now() + 86400 + offset) or ():
                if d.entry != mt5.DEAL_ENTRY_OUT or (symbol and d.symbol != symbol):
                    continue
                deals.append({"ticket": int(d.ticket), "position": int(d.position_id), "symbol": d.symbol,
                              "side": "short" if d.type == mt5.DEAL_TYPE_BUY else "long", "lots": d.volume,
                              "price": d.price, "profit": d.profit + d.commission + d.swap + getattr(d, "fee", 0),
                              "time": float(d.time) - offset,
                              "reason": {mt5.DEAL_REASON_SL: "stop", mt5.DEAL_REASON_TP: "target"}.get(d.reason, "manual")})
            mode = None
            if a is not None:
                mode = {mt5.ACCOUNT_TRADE_MODE_DEMO: "demo", mt5.ACCOUNT_TRADE_MODE_REAL: "real"}.get(a.trade_mode, "contest")
            return {"ok": True, "positions": positions, "orders": orders, "deals": deals[-30:],
                    "balance": a.balance if a else None, "equity": a.equity if a else None,
                    "margin": a.margin if a else None, "marginFree": a.margin_free if a else None,
                    "marginLevel": a.margin_level if a else None, "profit": a.profit if a else None,
                    "leverage": a.leverage if a else None, "server": a.server if a else None,
                    "currency": a.currency if a else None, "login": a.login if a else None, "mode": mode,
                    "tradingEnabled": bool(self.cfg.get("trading_enabled")),
                    "allowReal": bool(self.cfg.get("allow_real_account")),
                    "maxLots": float(self.cfg.get("max_lots", 0.1))}

    def order(self, body):
        symbol = str(body.get("symbol", ""))
        side = body.get("side")
        kind = body.get("type", "market")
        if side not in ("long", "short") or kind not in ("market", "pending"):
            raise ValueError("Lệnh không hợp lệ")
        with Mt5.lock:
            mt5 = self._mt5()
            self._check_trading(mt5)
            info = mt5.symbol_info(symbol)
            if info is None or not mt5.symbol_select(symbol, True):
                raise ValueError(f"MT5 không có mã {symbol}")
            tick = mt5.symbol_info_tick(symbol)
            volume = self._volume(mt5, info, float(body.get("lots", 0.01)))
            buy = side == "long"
            request = {"symbol": symbol, "volume": volume, "magic": APP_MAGIC, "comment": "GoldApp",
                       "deviation": int(self.cfg.get("deviation", 30)), "type_time": mt5.ORDER_TIME_GTC}
            if kind == "market":
                request.update(action=mt5.TRADE_ACTION_DEAL, type=mt5.ORDER_TYPE_BUY if buy else mt5.ORDER_TYPE_SELL,
                               price=tick.ask if buy else tick.bid)
            else:
                price = round(float(body["price"]), info.digits)
                below = price < (tick.ask if buy else tick.bid)
                # Buy below / sell above the market = limit, otherwise stop.
                order_type = (mt5.ORDER_TYPE_BUY_LIMIT if below else mt5.ORDER_TYPE_BUY_STOP) if buy else \
                    (mt5.ORDER_TYPE_SELL_STOP if below else mt5.ORDER_TYPE_SELL_LIMIT)
                request.update(action=mt5.TRADE_ACTION_PENDING, type=order_type, price=price)
            if body.get("stop"):
                request["sl"] = round(float(body["stop"]), info.digits)
            if body.get("target"):
                request["tp"] = round(float(body["target"]), info.digits)
            result, error = mt5_send(mt5, request)
            if error:
                raise ValueError(error)
        self.server.log(f"📱 Lệnh tay MT5: {'MUA' if buy else 'BÁN'} {volume} {symbol}"
                        f"{' chờ @ ' + fmt(request['price']) if kind != 'market' else ''}", notify=True)
        return dict(self.trading(), ticket=int(result.order))

    def close(self, body):
        ticket = int(body.get("ticket", 0))
        with Mt5.lock:
            mt5 = self._mt5()
            self._check_trading(mt5)
            rows = mt5.positions_get(ticket=ticket) or ()
            if not rows:
                raise ValueError("Không còn lệnh này")
            r = rows[0]
            tick = mt5.symbol_info_tick(r.symbol)
            buy = r.type == mt5.POSITION_TYPE_BUY
            volume = float(body.get("lots") or r.volume)
            request = {"action": mt5.TRADE_ACTION_DEAL, "symbol": r.symbol, "volume": min(volume, r.volume),
                       "type": mt5.ORDER_TYPE_SELL if buy else mt5.ORDER_TYPE_BUY, "position": r.ticket,
                       "price": tick.bid if buy else tick.ask, "deviation": int(self.cfg.get("deviation", 30)),
                       "magic": r.magic, "comment": "GoldApp close", "type_time": mt5.ORDER_TIME_GTC}
            _, error = mt5_send(mt5, request)
            if error:
                raise ValueError(error)
        self.server.log(f"📱 Đóng lệnh MT5 #{ticket} ({r.symbol}, lãi/lỗ {money(r.profit)})", notify=True)
        return self.trading()

    def modify(self, body):
        ticket = int(body.get("ticket", 0))
        with Mt5.lock:
            mt5 = self._mt5()
            self._check_trading(mt5)
            rows = mt5.positions_get(ticket=ticket) or ()
            if rows:
                r = rows[0]
                info = mt5.symbol_info(r.symbol)
                request = {"action": mt5.TRADE_ACTION_SLTP, "symbol": r.symbol, "position": r.ticket,
                           "sl": round(float(body["stop"]), info.digits) if body.get("stop") else 0.0,
                           "tp": round(float(body["target"]), info.digits) if body.get("target") else 0.0}
            else:
                orders = mt5.orders_get(ticket=ticket) or ()
                if not orders:
                    raise ValueError("Không còn lệnh này")
                o = orders[0]
                info = mt5.symbol_info(o.symbol)
                price = float(body.get("price") or o.price_open)
                request = {"action": mt5.TRADE_ACTION_MODIFY, "symbol": o.symbol, "order": o.ticket,
                           "price": round(price, info.digits), "type_time": mt5.ORDER_TIME_GTC,
                           "sl": round(float(body["stop"]), info.digits) if body.get("stop") else 0.0,
                           "tp": round(float(body["target"]), info.digits) if body.get("target") else 0.0}
            _, error = mt5_send(mt5, request)
            if error:
                raise ValueError(error)
        return self.trading()

    def cancel(self, body):
        ticket = int(body.get("ticket", 0))
        with Mt5.lock:
            mt5 = self._mt5()
            self._check_trading(mt5)
            orders = mt5.orders_get(ticket=ticket) or ()
            if not orders:
                raise ValueError("Không còn lệnh chờ này")
            _, error = mt5_send(mt5, {"action": mt5.TRADE_ACTION_REMOVE, "order": ticket, "symbol": orders[0].symbol})
            if error:
                raise ValueError(error)
        self.server.log(f"📱 Huỷ lệnh chờ MT5 #{ticket}")
        return self.trading()

    def history(self, start, end):
        """Closed positions, orders and deals of the account between two UTC times (MT5 History)."""
        import datetime
        with Mt5.lock:
            mt5 = self._mt5()
            # The server-time offset comes from a live tick: any symbol of the account will do.
            probe = next(iter(mt5.positions_get() or ()), None)
            symbol = probe.symbol if probe else next((r.name for r in (mt5.symbols_get() or ()) if r.visible), None)
            offset = Mt5.detect_offset(symbol) if symbol else Mt5.offset_seconds
            # MT5 wants server-time datetimes.
            frm = datetime.datetime.fromtimestamp(float(start) + offset, tz=datetime.timezone.utc)
            to = datetime.datetime.fromtimestamp(float(end) + offset, tz=datetime.timezone.utc)
            deals_raw = list(mt5.history_deals_get(frm, to) or ())
            orders_raw = list(mt5.history_orders_get(frm, to) or ()) if hasattr(mt5, "history_orders_get") else []
            a = mt5.account_info()
            deal_names = {mt5.DEAL_TYPE_BUY: "buy", mt5.DEAL_TYPE_SELL: "sell"}
            balance_type = getattr(mt5, "DEAL_TYPE_BALANCE", 2)
            deals, by_position = [], {}
            summary = {"profit": 0.0, "deposit": 0.0, "withdrawal": 0.0, "swap": 0.0, "commission": 0.0}
            for d in deals_raw:
                fee = getattr(d, "fee", 0) or 0
                kind = deal_names.get(d.type, "balance" if d.type == balance_type else "other")
                entry = {getattr(mt5, "DEAL_ENTRY_IN", 0): "in", getattr(mt5, "DEAL_ENTRY_OUT", 1): "out"}.get(d.entry, "inout")
                deals.append({"ticket": int(d.ticket), "position": int(d.position_id), "symbol": d.symbol or "",
                              "type": kind, "entry": entry, "lots": d.volume, "price": d.price,
                              "profit": d.profit, "swap": d.swap, "commission": d.commission + fee,
                              "time": float(d.time) - offset, "comment": getattr(d, "comment", "") or ""})
                if kind == "balance":
                    summary["deposit" if d.profit >= 0 else "withdrawal"] += d.profit
                    continue
                summary["profit"] += d.profit
                summary["swap"] += d.swap
                summary["commission"] += d.commission + fee
                if d.position_id:
                    by_position.setdefault(int(d.position_id), []).append(d)
            orders_by_ticket = {int(o.ticket): o for o in orders_raw}
            symbol_info = {}
            for name in {r[0].symbol for r in by_position.values() if r}:
                info = mt5.symbol_info(name)
                symbol_info[name] = (info.digits, info.description or "") if info else (None, "")
            positions = []
            for pid, rows in by_position.items():
                ins = [r for r in rows if r.entry == getattr(mt5, "DEAL_ENTRY_IN", 0)]
                outs = [r for r in rows if r.entry != getattr(mt5, "DEAL_ENTRY_IN", 0)]
                if not ins or not outs:
                    continue
                first = ins[0]
                lots = sum(r.volume for r in outs)
                exit_price = sum(r.price * r.volume for r in outs) / lots if lots else outs[-1].price
                reason = {mt5.DEAL_REASON_SL: "stop", mt5.DEAL_REASON_TP: "target"}.get(outs[-1].reason, "manual")
                # SL/TP when it closed: MT5 writes the level that fired in the closing deal's
                # comment ("[sl 4021.884]"), so the slippage against it can be shown.
                fired = re.search(r"\[(sl|tp)\s*([0-9.]+)\]", getattr(outs[-1], "comment", "") or "")
                stop = getattr(outs[-1], "sl", 0) or 0
                target = getattr(outs[-1], "tp", 0) or 0
                if fired and fired.group(1) == "sl":
                    stop = float(fired.group(2))
                if fired and fired.group(1) == "tp":
                    target = float(fired.group(2))
                opening = orders_by_ticket.get(int(getattr(first, "order", 0) or 0))
                if opening is None and getattr(first, "order", 0) and hasattr(mt5, "history_orders_get"):
                    try:
                        opening = next(iter(mt5.history_orders_get(ticket=int(first.order)) or ()), None)
                    except (TypeError, RuntimeError):
                        opening = None
                stop_open = getattr(first, "sl", 0) or (opening.sl if opening is not None else 0)
                target_open = getattr(first, "tp", 0) or (opening.tp if opening is not None else 0)
                positions.append({"ticket": pid, "symbol": first.symbol,
                                  "side": "long" if first.type == mt5.DEAL_TYPE_BUY else "short",
                                  "lots": lots, "entry": first.price, "exit": exit_price,
                                  "openTime": float(first.time) - offset, "closeTime": float(outs[-1].time) - offset,
                                  "profit": sum(r.profit + r.swap + r.commission + (getattr(r, "fee", 0) or 0) for r in rows),
                                  "reason": reason, "stop": stop or None, "target": target or None,
                                  "stopOpen": stop_open or None, "targetOpen": target_open or None,
                                  "swap": sum(r.swap for r in rows),
                                  "commission": sum(r.commission + (getattr(r, "fee", 0) or 0) for r in rows),
                                  "comment": getattr(first, "comment", "") or "",
                                  "digits": symbol_info.get(first.symbol, (None, ""))[0],
                                  "description": symbol_info.get(first.symbol, (None, ""))[1]})
            order_names = {mt5.ORDER_TYPE_BUY: "buy", mt5.ORDER_TYPE_SELL: "sell", mt5.ORDER_TYPE_BUY_LIMIT: "buy limit",
                           mt5.ORDER_TYPE_SELL_LIMIT: "sell limit", mt5.ORDER_TYPE_BUY_STOP: "buy stop",
                           mt5.ORDER_TYPE_SELL_STOP: "sell stop"}
            states = {getattr(mt5, "ORDER_STATE_FILLED", 4): "filled", getattr(mt5, "ORDER_STATE_CANCELED", 2): "canceled",
                      getattr(mt5, "ORDER_STATE_EXPIRED", 6): "expired", getattr(mt5, "ORDER_STATE_REJECTED", 5): "rejected"}
            orders = [{"ticket": int(o.ticket), "symbol": o.symbol, "type": order_names.get(o.type, "other"),
                       "lots": o.volume_initial, "filled": o.volume_initial - o.volume_current,
                       "price": o.price_open or getattr(o, "price_current", 0), "stop": o.sl or None, "target": o.tp or None,
                       "state": states.get(o.state, "other"), "time": float(o.time_setup) - offset,
                       "doneTime": float(o.time_done or o.time_setup) - offset} for o in orders_raw]
            summary["balance"] = a.balance if a else None
            summary["currency"] = a.currency if a else None
            return {"ok": True, "positions": positions, "orders": orders, "deals": deals, "summary": summary}

    def candles(self, symbol, interval, count, before=None):
        if interval not in MT5_TIMEFRAMES:
            raise ValueError("MT5 có khung 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w (không có khung giây)")
        count = max(1, min(int(count), 5000))
        with Mt5.lock:
            mt5 = self._mt5()
            if not mt5.symbol_select(symbol, True):
                raise ValueError(f"MT5 không có mã {symbol}")
            timeframe = getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[interval])
            offset = Mt5.detect_offset(symbol)
            if before:
                import datetime
                # Bars that opened before `before` (app time = UTC), in server time.
                start = datetime.datetime.fromtimestamp(float(before) + offset - 1, tz=datetime.timezone.utc)
                rates = mt5.copy_rates_from(symbol, timeframe, start, count)
            else:
                rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, count)
            if rates is None:
                raise ValueError(f"MT5 không trả nến {symbol}: {mt5.last_error()}")
            bars = Mt5.bars(rates)
            if before:
                bars = [b for b in bars if b[0] < float(before)]
            tick = mt5.symbol_info_tick(symbol)
            info = mt5.symbol_info(symbol)
            return {"ok": True, "symbol": symbol, "candles": bars,
                    # Only the newest bar of a live request is still forming.
                    "lastComplete": bool(before),
                    "bid": tick.bid if tick else None, "ask": tick.ask if tick else None,
                    "digits": info.digits if info else None,
                    "description": info.description if info else ""}


# --------------------------------------------------------------------------
# Brokers. Positions use the app's PaperAccount.Position field names.
# Events: ("opened", pos) ("closed", trade) ("stopMoved", pos) ("error", text)
# ("skip", text): a signal that was not traded, logged without a notification.
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# Copy trade: every position of the main MT5 account (the one logged in for
# the app) is opened on the follower accounts, with its SL/TP kept in step and
# closed when the main one closes. The MetaTrader5 package drives one terminal
# per process, so each follower runs in its own process (--copy-worker) with
# its own copy of the MT5 terminal (portable mode).

COPY_MAGIC = 20262
COPY_PREFIX = "GC"


def copy_comment(ticket):
    return f"{COPY_PREFIX}{ticket}"


def copy_master_ticket(comment):
    m = re.match(rf"{COPY_PREFIX}(\d+)", comment or "")
    return int(m.group(1)) if m else None


def base_symbol(symbol):
    """XAUUSDm, XAUUSD.r, #XAUUSD → XAUUSD (broker suffixes and prefixes off)."""
    m = re.match(r"[#.]?([A-Z0-9]+)", symbol or "")
    return m.group(1) if m else symbol


class CopyWorker:
    """Follower side, inside the --copy-worker process."""

    def __init__(self, mt5):
        self.mt5 = mt5
        self.symbols = {}

    def connect(self, cfg):
        mt5 = self.mt5
        kwargs = {"timeout": 60000}
        if cfg.get("path"):
            kwargs["path"] = cfg["path"]
            kwargs["portable"] = bool(cfg.get("portable"))
        kwargs.update(login=int(cfg["login"]), password=str(cfg["password"]), server=str(cfg["server"]))
        if not mt5.initialize(**kwargs):
            return {"ok": False, "error": f"Không đăng nhập được #{cfg['login']} ({mt5.last_error()})"}
        a = mt5.account_info()
        if a is None or a.login != int(cfg["login"]):
            return {"ok": False, "error": f"MT5 không vào được tài khoản #{cfg['login']} ({mt5.last_error()})"}
        return self.account()

    def account(self):
        mt5 = self.mt5
        a = mt5.account_info()
        if a is None:
            return {"ok": False, "error": f"MT5 mất đăng nhập ({mt5.last_error()})"}
        mode = {mt5.ACCOUNT_TRADE_MODE_DEMO: "demo", mt5.ACCOUNT_TRADE_MODE_REAL: "real"}.get(a.trade_mode, "contest")
        mine = [p for p in (mt5.positions_get() or ()) if p.magic == COPY_MAGIC]
        return {"ok": True, "login": a.login, "server": a.server, "balance": a.balance, "equity": a.equity,
                "currency": a.currency, "mode": mode, "positions": len(mine),
                "profit": sum(p.profit + getattr(p, "swap", 0) for p in mine)}

    def resolve(self, symbol, mapping):
        """The follower's name for the main account's symbol."""
        if mapping.get(symbol):
            return mapping[symbol]
        if symbol in self.symbols:
            return self.symbols[symbol]
        mt5 = self.mt5
        found = symbol if mt5.symbol_info(symbol) is not None else None
        if found is None:
            base = base_symbol(symbol)
            pattern = re.compile(rf"[#.]?{re.escape(base)}([^A-Z0-9].*|[a-z].*)?$")
            names = [s.name for s in (mt5.symbols_get() or ()) if pattern.match(s.name)]
            names.sort(key=lambda n: (len(n), n))
            found = names[0] if names else None
        if found is not None:
            mt5.symbol_select(found, True)
            self.symbols[symbol] = found
        return found

    def volume(self, info, lots, f):
        fixed = float(f.get("fixedLots") or 0)
        wanted = fixed if fixed > 0 else lots * float(f.get("multiplier") or 1)
        wanted = min(wanted, float(f.get("maxLots") or 0.1))
        step = info.volume_step or 0.01
        volume = math.floor(wanted / step + 1e-9) * step
        if volume < info.volume_min - 1e-9:
            if info.volume_min > float(f.get("maxLots") or 0.1) + 1e-9:
                return None
            volume = info.volume_min
        return round(volume, 8)

    def sync(self, msg):
        mt5 = self.mt5
        f = msg.get("follower", {})
        state = self.account()
        if not state["ok"]:
            return state
        if state["mode"] == "real" and not f.get("allowReal"):
            return dict(state, ok=False, error="Tài khoản THẬT: bật 'Cho phép tài khoản thật' cho tài khoản copy này")
        terminal = mt5.terminal_info()
        if terminal is not None and not terminal.trade_allowed and not ensure_algo_trading(mt5, {}, restart=False):
            return dict(state, ok=False, error="Bật nút Algo Trading trong MT5 của tài khoản copy này")
        master = {int(m["ticket"]): m for m in msg.get("positions", [])}
        skip = set(int(t) for t in msg.get("skip", []))
        mapping = f.get("symbolMap") or {}
        deviation = int(f.get("deviation") or 30)
        mine = {}
        for p in mt5.positions_get() or ():
            if p.magic == COPY_MAGIC and copy_master_ticket(p.comment) is not None:
                mine[copy_master_ticket(p.comment)] = p
        actions = []
        errors = []
        # Closed on the main account → close here.
        for ticket, p in mine.items():
            if ticket in master:
                continue
            tick = mt5.symbol_info_tick(p.symbol)
            buy = p.type == mt5.POSITION_TYPE_BUY
            _, error = mt5_send(mt5, {"action": mt5.TRADE_ACTION_DEAL, "symbol": p.symbol, "volume": p.volume,
                                      "type": mt5.ORDER_TYPE_SELL if buy else mt5.ORDER_TYPE_BUY, "position": p.ticket,
                                      "price": tick.bid if buy else tick.ask, "deviation": deviation,
                                      "magic": COPY_MAGIC, "comment": copy_comment(ticket),
                                      "type_time": mt5.ORDER_TIME_GTC})
            if error:
                errors.append(f"Đóng {p.symbol}: {error}")
            else:
                actions.append({"kind": "closed", "master": ticket, "symbol": p.symbol, "lots": p.volume,
                                "profit": p.profit + getattr(p, "swap", 0)})
        for ticket, m in master.items():
            p = mine.get(ticket)
            if p is not None:
                # Keep SL/TP in step with the main account.
                info = mt5.symbol_info(p.symbol)
                digits = info.digits if info else 5
                sl = round(float(m.get("sl") or 0), digits)
                tp = round(float(m.get("tp") or 0), digits)
                half = (10 ** -digits) / 2
                if abs((p.sl or 0) - sl) > half or abs((p.tp or 0) - tp) > half:
                    _, error = mt5_send(mt5, {"action": mt5.TRADE_ACTION_SLTP, "symbol": p.symbol,
                                              "position": p.ticket, "sl": sl, "tp": tp})
                    if error:
                        errors.append(f"SL/TP {p.symbol}: {error}")
                    else:
                        actions.append({"kind": "modified", "master": ticket, "symbol": p.symbol, "sl": sl, "tp": tp})
                continue
            if ticket in skip:
                continue
            symbol = self.resolve(m["symbol"], mapping)
            if symbol is None:
                errors.append(f"Không có mã tương ứng với {m['symbol']} (đặt 'Đổi tên mã')")
                actions.append({"kind": "skipped", "master": ticket, "symbol": m["symbol"]})
                continue
            info = mt5.symbol_info(symbol)
            volume = self.volume(info, float(m["lots"]), f)
            if volume is None:
                errors.append(f"{symbol}: lot tối thiểu {info.volume_min} lớn hơn giới hạn")
                actions.append({"kind": "skipped", "master": ticket, "symbol": symbol})
                continue
            buy = m["side"] == "long"
            tick = mt5.symbol_info_tick(symbol)
            request = {"action": mt5.TRADE_ACTION_DEAL, "symbol": symbol, "volume": volume,
                       "type": mt5.ORDER_TYPE_BUY if buy else mt5.ORDER_TYPE_SELL,
                       "price": tick.ask if buy else tick.bid, "deviation": deviation, "magic": COPY_MAGIC,
                       "comment": copy_comment(ticket), "type_time": mt5.ORDER_TIME_GTC}
            if m.get("sl"):
                request["sl"] = round(float(m["sl"]), info.digits)
            if m.get("tp"):
                request["tp"] = round(float(m["tp"]), info.digits)
            result, error = mt5_send(mt5, dict(request))
            if error and ("sl" in request or "tp" in request):
                # Stops already passed on this broker: open, SL/TP are retried on the next sync.
                request.pop("sl", None)
                request.pop("tp", None)
                result, error = mt5_send(mt5, request)
            if error:
                errors.append(f"Mở {symbol}: {error}")
                actions.append({"kind": "failed", "master": ticket, "symbol": symbol, "error": error})
            else:
                actions.append({"kind": "opened", "master": ticket, "symbol": symbol, "side": m["side"],
                                "lots": volume, "price": getattr(result, "price", 0) or request["price"]})
        state = self.account()
        state.update(actions=actions, error="; ".join(errors[:3]),
                     copied=sorted(set(mine) | {a["master"] for a in actions if a["kind"] == "opened"}))
        return state

    def close_all(self):
        mt5 = self.mt5
        closed = 0
        for p in mt5.positions_get() or ():
            if p.magic != COPY_MAGIC:
                continue
            tick = mt5.symbol_info_tick(p.symbol)
            buy = p.type == mt5.POSITION_TYPE_BUY
            _, error = mt5_send(mt5, {"action": mt5.TRADE_ACTION_DEAL, "symbol": p.symbol, "volume": p.volume,
                                      "type": mt5.ORDER_TYPE_SELL if buy else mt5.ORDER_TYPE_BUY, "position": p.ticket,
                                      "price": tick.bid if buy else tick.ask, "deviation": 30, "magic": COPY_MAGIC,
                                      "comment": p.comment, "type_time": mt5.ORDER_TIME_GTC})
            closed += 0 if error else 1
        return dict(self.account(), closed=closed)


def copy_worker_main():
    """--copy-worker: one JSON request per stdin line, one JSON reply per stdout line."""
    out = sys.stdout
    sys.stdout = sys.stderr  # nothing else may write to the reply channel
    try:
        import MetaTrader5
    except ImportError:
        MetaTrader5 = None
    worker = CopyWorker(MetaTrader5) if MetaTrader5 else None
    for line in sys.stdin:
        try:
            msg = json.loads(line)
            if worker is None:
                reply = {"ok": False, "error": "Chưa cài MetaTrader5 (pip install MetaTrader5)"}
            elif msg.get("cmd") == "connect":
                reply = worker.connect(msg["cfg"])
            elif msg.get("cmd") == "sync":
                reply = worker.sync(msg)
            elif msg.get("cmd") == "close_all":
                reply = worker.close_all()
            else:
                reply = worker.account()
        except Exception as e:
            reply = {"ok": False, "error": f"{type(e).__name__}: {e}"}
        out.write(json.dumps(reply) + "\n")
        out.flush()
    # stdin closed: the server stopped.
    if MetaTrader5 is not None:
        MetaTrader5.shutdown()


class CopyProcess:
    """A --copy-worker child process, talked to over its stdin/stdout."""

    def __init__(self):
        import queue
        self.replies = queue.Queue()
        self.proc = subprocess.Popen([sys.executable, os.path.abspath(__file__), "--copy-worker"],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     text=True, encoding="utf-8", bufsize=1, creationflags=NO_WINDOW)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            try:
                self.replies.put(json.loads(line))
            except ValueError:
                pass
        self.replies.put(None)

    def alive(self):
        return self.proc.poll() is None

    def request(self, msg, timeout=60):
        import queue
        if not self.alive():
            raise RuntimeError("Tiến trình copy đã dừng")
        while not self.replies.empty():
            self.replies.get_nowait()
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        try:
            reply = self.replies.get(timeout=timeout)
        except queue.Empty:
            self.close()
            raise RuntimeError("MT5 của tài khoản copy không trả lời")
        if reply is None:
            raise RuntimeError("Tiến trình copy đã dừng")
        return reply

    def close(self):
        try:
            self.proc.kill()
        except OSError:
            pass


def clone_terminal(follower_id, master_cfg):
    """A portable copy of the main MT5 terminal for one follower (terminals/<id>)."""
    import shutil
    dest = os.path.join(HERE, "terminals", follower_id)
    exe = os.path.join(dest, "terminal64.exe")
    if os.path.exists(exe):
        return exe
    source = os.path.dirname(master_cfg.get("path") or "")
    data_path = None
    with Mt5.lock:
        try:
            info = Mt5.connect(master_cfg).terminal_info()
            source = source or getattr(info, "path", "") or ""
            data_path = getattr(info, "data_path", None)
        except RuntimeError:
            pass
    if not source or not os.path.exists(os.path.join(source, "terminal64.exe")):
        raise ValueError("Không tìm thấy MT5 trên VPS để sao chép: cài MT5 trước, hoặc nhập đường dẫn terminal64.exe")
    shutil.copytree(source, dest, ignore=shutil.ignore_patterns("Bases", "logs", "Logs", "Tester", "*.log"))
    config_dir = os.path.join(dest, "Config")
    os.makedirs(config_dir, exist_ok=True)
    # The broker's server list, so the copy finds e.g. Exness-MT5Trial7.
    if data_path:
        for name in ("servers.dat",):
            src = os.path.join(data_path, "config", name)
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(config_dir, name))
    common = os.path.join(config_dir, "common.ini")
    if not os.path.exists(common):
        # Algo Trading on, so the copy can trade.
        with open(common, "w", encoding="utf-16") as f:
            f.write("[Experts]\nAllowLiveTrading=1\nAllowDllImport=0\nEnabled=1\nAccount=0\nProfile=0\n")
    return exe


DEFAULT_FOLLOWER = {"id": "", "name": "", "login": 0, "password": "", "server": "", "path": "", "multiplier": 1.0,
                    "fixedLots": 0.0, "maxLots": 0.1, "allowReal": False, "enabled": True, "symbolMap": {}}


class CopyTrader:
    """Main side: reads the main account's positions and drives one worker per follower."""

    def __init__(self, server):
        self.server = server
        self.lock = threading.RLock()
        self.master = {"connected": False}
        self.snapshot = None
        self.snapshot_time = 0
        self.runtime = {}  # follower id → {"proc", "status", "key", "thread"}
        self.events = []
        threading.Thread(target=self._master_loop, daemon=True).start()

    @property
    def cfg(self):
        c = self.server.config.setdefault("copy", {})
        c.setdefault("enabled", False)
        c.setdefault("followers", [])
        return c

    def state(self, fid):
        return self.server.copy_state.setdefault(fid, {"seen": []})

    def event(self, text, notify=True):
        with self.lock:
            self.events.insert(0, {"time": now(), "text": text})
            del self.events[50:]
        self.server.log(text, notify=notify)

    # ----- main account -----

    def _master_loop(self):
        while True:
            try:
                if self.cfg["enabled"] and any(f.get("enabled") for f in self.cfg["followers"]):
                    self._read_master()
                    self._ensure_threads()
            except Exception as e:
                self.master = {"connected": False, "error": str(e)}
            time.sleep(1)

    def _read_master(self):
        with Mt5.lock:
            mt5 = Mt5.connect(self.server.config["mt5"])
            a = mt5.account_info()
            if a is None:
                self.master = {"connected": False, "error": "Tài khoản chính chưa đăng nhập MT5 (Giao dịch → Đăng nhập)"}
                return
            rows = mt5.positions_get() or ()
            positions = [{"ticket": int(r.ticket), "symbol": r.symbol,
                          "side": "long" if r.type == mt5.POSITION_TYPE_BUY else "short",
                          "lots": r.volume, "sl": r.sl or 0, "tp": r.tp or 0}
                         for r in rows if r.magic != COPY_MAGIC]
        with self.lock:
            self.master = {"connected": True, "login": a.login, "server": a.server, "positions": len(positions),
                           "balance": a.balance, "currency": a.currency}
            self.snapshot = positions
            self.snapshot_time = time.time()

    # ----- followers -----

    def _ensure_threads(self):
        for f in self.cfg["followers"]:
            rt = self.runtime.setdefault(f["id"], {"status": {}, "proc": None, "key": None})
            if rt.get("thread") is None or not rt["thread"].is_alive():
                rt["thread"] = threading.Thread(target=self._follower_loop, args=(f["id"],), daemon=True)
                rt["thread"].start()

    def follower(self, fid):
        return next((f for f in self.cfg["followers"] if f["id"] == fid), None)

    def _stop_proc(self, rt):
        if rt.get("proc") is not None:
            rt["proc"].close()
            rt["proc"] = None
            rt["key"] = None

    def _follower_loop(self, fid):
        backoff = 0
        while True:
            f = self.follower(fid)
            rt = self.runtime.get(fid)
            if f is None or rt is None:
                if rt is not None:
                    self._stop_proc(rt)
                return
            if not (self.cfg["enabled"] and f.get("enabled")):
                self._stop_proc(rt)
                rt["status"] = {"connected": False, "error": "Đang tắt"}
                time.sleep(2)
                continue
            if backoff > time.time():
                time.sleep(1)
                continue
            try:
                self._sync_follower(f, rt)
            except Exception as e:
                rt["status"] = dict(rt.get("status") or {}, connected=False, error=str(e))
                self._stop_proc(rt)
                backoff = time.time() + 15
            time.sleep(1)

    def _sync_follower(self, f, rt):
        key = f"{f['login']}|{f['server']}|{f.get('path')}|{f.get('password')}"
        if rt.get("proc") is None or not rt["proc"].alive() or rt.get("key") != key:
            self._stop_proc(rt)
            path = f.get("path") or clone_terminal(f["id"], self.server.config["mt5"])
            proc = CopyProcess()
            reply = proc.request({"cmd": "connect", "cfg": {"path": path, "portable": not f.get("path"),
                                                            "login": f["login"], "password": f["password"],
                                                            "server": f["server"]}}, timeout=120)
            if not reply.get("ok"):
                proc.close()
                raise RuntimeError(reply.get("error") or "Không kết nối được")
            rt["proc"], rt["key"] = proc, key
            self.event(f"🔗 Copy: đã kết nối #{f['login']} ({f.get('name') or f['server']})", notify=False)
        with self.lock:
            snapshot = self.snapshot
            fresh = time.time() - self.snapshot_time < 10
            master_login = self.master.get("login")
        if snapshot is None or not fresh:
            rt["status"] = dict(rt.get("status") or {}, error="Chờ tài khoản chính")
            return
        if int(f["login"]) == int(master_login or 0):
            raise RuntimeError("Tài khoản copy trùng tài khoản chính")
        st = self.state(f["id"])
        if not st.get("baseline"):
            # Positions already open when copying starts are not copied.
            st["seen"] = sorted(set(st.get("seen", [])) | {p["ticket"] for p in snapshot})
            st["baseline"] = True
            self.server.save_state()
        reply = rt["proc"].request({"cmd": "sync", "positions": snapshot, "skip": st["seen"], "follower": f})
        rt["status"] = dict(reply, connected=reply.get("login") is not None, lastSync=now())
        rt["status"].pop("actions", None)
        rt["status"].pop("copied", None)
        name = f.get("name") or f"#{f['login']}"
        # What was copied for each main-account ticket, for the member's signal list.
        copies = st.setdefault("copies", {})
        for a in reply.get("actions", []):
            key = str(a.get("master"))
            if a["kind"] == "opened":
                copies[key] = {"lots": a["lots"], "price": a.get("price")}
            elif a["kind"] == "closed":
                copies.setdefault(key, {"lots": a["lots"]}).update(profit=a.get("profit"))
            elif a["kind"] == "failed":
                copies[key] = {"lots": 0, "error": a.get("error", "")}
        if len(copies) > 300:
            for old in sorted(copies, key=lambda k: int(k) if k.isdigit() else 0)[:len(copies) - 300]:
                del copies[old]
        if any(a["kind"] in ("opened", "closed", "failed") for a in reply.get("actions", [])):
            self.server.save_state()
        for a in reply.get("actions", []):
            if a["kind"] == "opened":
                self.event(f"📋 Copy {name}: {'MUA' if a['side'] == 'long' else 'BÁN'} {a['lots']} {a['symbol']} "
                           f"@ {fmt(a['price'])} (lệnh chính #{a['master']})")
            elif a["kind"] == "closed":
                self.event(f"📋 Copy {name}: đóng {a['symbol']} {a['lots']} lot, lãi/lỗ {money(a['profit'])}")
            elif a["kind"] == "failed":
                self.event(f"⚠︎ Copy {name}: không mở được {a['symbol']}: {a['error']}")
        copied = set(reply.get("copied", []))
        tried = {a["master"] for a in reply.get("actions", []) if a["kind"] in ("failed", "skipped")}
        new_seen = set(st["seen"]) | copied | tried
        if new_seen != set(st["seen"]):
            # Keep only tickets still open on the main account plus recent ones.
            st["seen"] = sorted(new_seen)[-500:]
            self.server.save_state()

    # ----- API -----

    def status(self):
        followers = []
        for f in self.cfg["followers"]:
            rt = self.runtime.get(f["id"], {})
            row = {k: v for k, v in f.items() if k != "password"}
            row["hasPassword"] = bool(f.get("password"))
            row["status"] = rt.get("status") or {"connected": False}
            followers.append(row)
        with self.lock:
            return {"ok": True, "enabled": bool(self.cfg["enabled"]), "master": dict(self.master),
                    "followers": followers, "events": self.events[:30]}

    def settings(self, body):
        enabled = bool(body.get("enabled"))
        if enabled and not self.cfg["enabled"]:
            # Turning copying on: only positions opened from now are copied.
            for f in self.cfg["followers"]:
                self.state(f["id"])["baseline"] = False
        self.cfg["enabled"] = enabled
        self.server.save_config()
        self.event(f"📋 Copy trade {'BẬT' if enabled else 'TẮT'}")
        return self.status()

    def save_follower(self, body, new_id=None):
        fid = str(body.get("id") or "")
        current = self.follower(fid) if fid else None
        f = dict(current or DEFAULT_FOLLOWER)
        if not current:
            f["id"] = new_id or uuid.uuid4().hex[:8]
        try:
            f["login"] = int(str(body.get("login", f["login"])).strip())
        except ValueError:
            raise ValueError("Số tài khoản phải là số")
        f["server"] = str(body.get("server", f["server"])).strip()
        if body.get("password"):
            f["password"] = str(body["password"])
        for key, cast in (("name", str), ("path", str), ("multiplier", float), ("fixedLots", float),
                          ("maxLots", float), ("allowReal", bool), ("enabled", bool)):
            if key in body:
                f[key] = cast(body[key])
        if isinstance(body.get("symbolMap"), dict):
            f["symbolMap"] = {str(k): str(v) for k, v in body["symbolMap"].items() if k and v}
        if not f["login"] or not f["server"] or not f.get("password"):
            raise ValueError("Cần số tài khoản, server và mật khẩu (mật khẩu chính, không phải investor)")
        if f["multiplier"] <= 0 or f["maxLots"] <= 0:
            raise ValueError("Hệ số lot và lot tối đa phải lớn hơn 0")
        if int(f["login"]) == int(self.server.config["mt5"].get("login") or 0):
            raise ValueError("Đây là tài khoản chính; tài khoản copy phải là tài khoản khác")
        if any(o["login"] == f["login"] and o["id"] != f["id"] for o in self.cfg["followers"]):
            raise ValueError("Tài khoản này đã có trong danh sách copy")
        if current:
            current.update(f)
        else:
            self.cfg["followers"].append(f)
            self.state(f["id"])["baseline"] = False
        self.server.save_config()
        self.event(f"📋 Copy: {'cập nhật' if current else 'thêm'} tài khoản #{f['login']} ({f['server']})", notify=False)
        return self.status()

    def remove_follower(self, body):
        fid = str(body.get("id") or "")
        f = self.follower(fid)
        if f is None:
            raise ValueError("Không có tài khoản copy này")
        rt = self.runtime.get(fid) or {}
        closed = 0
        if body.get("closePositions") and rt.get("proc") is not None:
            closed = rt["proc"].request({"cmd": "close_all"}).get("closed", 0)
        self.cfg["followers"] = [o for o in self.cfg["followers"] if o["id"] != fid]
        self.server.copy_state.pop(fid, None)
        self.server.save_config()
        self.runtime.pop(fid, None)
        self._stop_proc(rt)
        self.event(f"📋 Copy: đã xoá tài khoản #{f['login']}" + (f", đóng {closed} lệnh" if closed else ""), notify=False)
        return self.status()

    def close_follower(self, body):
        rt = self.runtime.get(str(body.get("id") or "")) or {}
        if rt.get("proc") is None:
            raise ValueError("Tài khoản copy chưa kết nối")
        reply = rt["proc"].request({"cmd": "close_all"})
        self.event(f"📋 Copy: đóng {reply.get('closed', 0)} lệnh copy")
        return self.status()


class PaperBroker:
    name = "paper"

    def __init__(self, account):
        self.account = account  # dict kept in state.json

    def mode(self):
        return "paper"

    def positions(self, symbol):
        return [p for p in self.account["positions"] if p["symbol"] == symbol]

    def open(self, symbol, side, lots, price, stop, target):
        p = {"id": str(uuid.uuid4()).upper(), "symbol": symbol, "side": side, "lots": lots, "entryPrice": price,
             "stop": stop, "target": target, "contractSize": contract_size(symbol), "openTime": now(),
             "initialStop": stop, "peakPrice": price}
        self.account["positions"].append(p)
        return [("opened", p)]

    def close(self, position_id, price, reason="manual"):
        for p in list(self.account["positions"]):
            if p["id"] == position_id:
                profit = (price - p["entryPrice"]) * (1 if p["side"] == "long" else -1) * p["lots"] * p["contractSize"]
                self.account["positions"].remove(p)
                self.account["balance"] += profit
                trade = dict(p, exitPrice=price, exitTime=now(), profit=profit, reason=reason)
                self.account["history"].insert(0, trade)
                del self.account["history"][500:]
                return [("closed", trade)]
        return []

    def set_stop(self, position_id, stop):
        for p in self.account["positions"]:
            if p["id"] == position_id:
                p["stop"] = stop
                return [("stopMoved", p)]
        return []

    def on_price(self, symbol, price):
        events = []
        for p in list(self.positions(symbol)):
            long = p["side"] == "long"
            p["peakPrice"] = max(p.get("peakPrice") or price, price) if long else min(p.get("peakPrice") or price, price)
            if p.get("stop") is not None and (price <= p["stop"] if long else price >= p["stop"]):
                events += self.close(p["id"], p["stop"], "stop")
            elif p.get("target") is not None and (price >= p["target"] if long else price <= p["target"]):
                events += self.close(p["id"], p["target"], "target")
        return events

    def info(self, prices):
        open_profit = sum((prices.get(p["symbol"], p["entryPrice"]) - p["entryPrice"]) *
                          (1 if p["side"] == "long" else -1) * p["lots"] * p["contractSize"]
                          for p in self.account["positions"])
        return {"mode": "paper", "balance": self.account["balance"], "equity": self.account["balance"] + open_profit,
                "openProfit": open_profit, "currency": "USD"}

    def history(self):
        return self.account["history"]


class Mt5Broker:
    """Real MT5 orders (demo or live account) with SL/TP on the server side."""
    name = "mt5"

    def __init__(self, cfg, memory):
        self.cfg = cfg
        self.memory = memory  # {"ticket": {"initialStop", "peakPrice"}} kept in state.json
        self.known = set()
        self.closed = []
        self.mt5 = Mt5.connect(cfg)
        info = self.mt5.account_info()
        if info is None:
            raise RuntimeError(f"MT5 chưa đăng nhập: {self.mt5.last_error()}")
        if not cfg.get("trading_enabled"):
            raise RuntimeError("Đặt lệnh MT5 đang tắt: sửa config.json → mt5.trading_enabled = true")
        if info.trade_mode == self.mt5.ACCOUNT_TRADE_MODE_REAL and not cfg.get("allow_real_account"):
            raise RuntimeError("Đây là tài khoản THẬT: sửa config.json → mt5.allow_real_account = true nếu chắc chắn")
        if not info.trade_allowed:
            raise RuntimeError("Tài khoản MT5 không cho phép giao dịch (đang dùng mật khẩu investor?)")
        terminal = self.mt5.terminal_info()
        if terminal is not None and not terminal.trade_allowed:
            raise RuntimeError("Bật nút Algo Trading trong MT5 trên VPS")

    def mode(self):
        info = self.mt5.account_info()
        if info is None:
            return "mt5"
        return {self.mt5.ACCOUNT_TRADE_MODE_DEMO: "demo", self.mt5.ACCOUNT_TRADE_MODE_REAL: "real"}.get(
            info.trade_mode, "contest")

    def _mine(self, symbol=None):
        rows = self.mt5.positions_get(symbol=symbol) if symbol else self.mt5.positions_get()
        return [r for r in (rows or []) if r.magic == int(self.cfg.get("magic", 20260))]

    def _position(self, r):
        mem = self.memory.setdefault(str(r.ticket), {"initialStop": r.sl or None, "peakPrice": r.price_open})
        info = self.mt5.symbol_info(r.symbol)
        return {"id": str(r.ticket), "symbol": r.symbol, "side": "long" if r.type == self.mt5.POSITION_TYPE_BUY else "short",
                "lots": r.volume, "entryPrice": r.price_open, "stop": r.sl or None, "target": r.tp or None,
                "contractSize": info.trade_contract_size if info else contract_size(r.symbol),
                "openTime": float(r.time), "initialStop": mem.get("initialStop"), "peakPrice": mem.get("peakPrice"),
                "profit": r.profit}

    def positions(self, symbol):
        return [self._position(r) for r in self._mine(symbol)]

    def _send(self, request):
        return mt5_send(self.mt5, request)

    def open(self, symbol, side, lots, price, stop, target):
        max_lots = float(self.cfg.get("max_lots", 0.1))
        info = self.mt5.symbol_info(symbol)
        tick = self.mt5.symbol_info_tick(symbol)
        if info is None or tick is None:
            return [("error", f"MT5 không có giá {symbol}")]
        step = info.volume_step or 0.01
        volume = min(lots, max_lots)
        volume = max(info.volume_min, math.floor(volume / step + 1e-9) * step)
        volume = round(volume, 8)
        if volume > max_lots + 1e-9:
            return [("error", f"Khối lượng tối thiểu {volume} lớn hơn max_lots {max_lots}")]
        buy = side == "long"
        request = {"action": self.mt5.TRADE_ACTION_DEAL, "symbol": symbol, "volume": volume,
                   "type": self.mt5.ORDER_TYPE_BUY if buy else self.mt5.ORDER_TYPE_SELL,
                   "price": tick.ask if buy else tick.bid, "deviation": int(self.cfg.get("deviation", 30)),
                   "magic": int(self.cfg.get("magic", 20260)), "comment": "GoldBot",
                   "type_time": self.mt5.ORDER_TIME_GTC}
        if stop:
            request["sl"] = round(stop, info.digits)
        if target:
            request["tp"] = round(target, info.digits)
        result, error = self._send(request)
        if error:
            return [("error", error)]
        ticket = str(result.order)
        self.memory[ticket] = {"initialStop": request.get("sl"), "peakPrice": result.price or request["price"]}
        for r in self._mine(symbol):
            if str(r.ticket) == ticket or str(r.identifier) == ticket:
                self.memory[str(r.ticket)] = self.memory[ticket]
                self.known.add(str(r.ticket))
                return [("opened", self._position(r))]
        return [("opened", {"id": ticket, "symbol": symbol, "side": side, "lots": volume,
                            "entryPrice": result.price or request["price"], "stop": stop, "target": target})]

    def close(self, position_id, price=None, reason="manual"):
        for r in self._mine():
            if str(r.ticket) != str(position_id):
                continue
            tick = self.mt5.symbol_info_tick(r.symbol)
            buy = r.type == self.mt5.POSITION_TYPE_BUY
            request = {"action": self.mt5.TRADE_ACTION_DEAL, "symbol": r.symbol, "volume": r.volume,
                       "type": self.mt5.ORDER_TYPE_SELL if buy else self.mt5.ORDER_TYPE_BUY,
                       "position": r.ticket, "price": tick.bid if buy else tick.ask,
                       "deviation": int(self.cfg.get("deviation", 30)), "magic": int(self.cfg.get("magic", 20260)),
                       "comment": "GoldBot close", "type_time": self.mt5.ORDER_TIME_GTC}
            _, error = self._send(request)
            if error:
                return [("error", error)]
            self.closed.append((str(r.ticket), reason))
            return self._detect_closed(r.symbol)
        return []

    def set_stop(self, position_id, stop):
        for r in self._mine():
            if str(r.ticket) == str(position_id):
                info = self.mt5.symbol_info(r.symbol)
                request = {"action": self.mt5.TRADE_ACTION_SLTP, "symbol": r.symbol, "position": r.ticket,
                           "sl": round(stop, info.digits if info else 2), "tp": r.tp}
                _, error = self._send(request)
                if error:
                    return [("error", "Dời SL: " + error)]
                r2 = [x for x in self._mine(r.symbol) if x.ticket == r.ticket]
                return [("stopMoved", self._position(r2[0]) if r2 else dict(self._position(r), stop=stop))]
        return []

    def _detect_closed(self, symbol):
        events = []
        current = {str(r.ticket) for r in self._mine()}
        for ticket in list(self.known - current):
            self.known.discard(ticket)
            reason = next((why for t, why in self.closed if t == ticket), None)
            self.closed = [(t, w) for t, w in self.closed if t != ticket]
            deals = self.mt5.history_deals_get(position=int(ticket)) or []
            profit = sum(d.profit + d.commission + d.swap + getattr(d, "fee", 0) for d in deals)
            exit_deal = deals[-1] if deals else None
            if reason is None and exit_deal is not None:
                reason = {self.mt5.DEAL_REASON_SL: "stop", self.mt5.DEAL_REASON_TP: "target"}.get(exit_deal.reason, "manual")
            entry = deals[0] if deals else None
            trade = {"id": ticket, "symbol": exit_deal.symbol if exit_deal else symbol,
                     "side": "long" if entry is not None and entry.type == self.mt5.DEAL_TYPE_BUY else "short",
                     "lots": entry.volume if entry else 0, "entryPrice": entry.price if entry else 0,
                     "exitPrice": exit_deal.price if exit_deal else 0, "openTime": float(entry.time) if entry else 0,
                     "exitTime": float(exit_deal.time) if exit_deal else now(), "profit": profit,
                     "reason": reason or "manual"}
            self.memory.pop(ticket, None)
            events.append(("closed", trade))
        self.known |= current
        return events

    def on_price(self, symbol, price):
        for r in self._mine(symbol):
            mem = self.memory.setdefault(str(r.ticket), {"initialStop": r.sl or None, "peakPrice": r.price_open})
            peak = mem.get("peakPrice") or r.price_open
            mem["peakPrice"] = max(peak, price) if r.type == self.mt5.POSITION_TYPE_BUY else min(peak, price)
        return self._detect_closed(symbol)

    def info(self, prices):
        a = self.mt5.account_info()
        if a is None:
            return {"mode": "mt5", "error": str(self.mt5.last_error())}
        return {"mode": self.mode(), "balance": a.balance, "equity": a.equity, "openProfit": a.profit,
                "currency": a.currency, "login": a.login, "server": a.server}

    def history(self):
        frm = now() - 30 * 86400
        deals = self.mt5.history_deals_get(frm, now() + 86400) or []
        out = []
        for d in deals:
            if d.magic != int(self.cfg.get("magic", 20260)) or d.entry != self.mt5.DEAL_ENTRY_OUT:
                continue
            out.append({"id": str(d.position_id), "symbol": d.symbol,
                        "side": "short" if d.type == self.mt5.DEAL_TYPE_BUY else "long", "lots": d.volume,
                        "exitPrice": d.price, "exitTime": float(d.time),
                        "profit": d.profit + d.commission + d.swap + getattr(d, "fee", 0),
                        "reason": {self.mt5.DEAL_REASON_SL: "stop", self.mt5.DEAL_REASON_TP: "target"}.get(d.reason, "manual")})
        return list(reversed(out))


# --------------------------------------------------------------------------
# Trade management (same rules as TradeManagement.improvedStop in the app)
# --------------------------------------------------------------------------

def improved_stop(p, rules):
    if not rules.get("moveStop", True):
        return None
    initial, peak, entry = p.get("initialStop"), p.get("peakPrice"), p["entryPrice"]
    if initial is None or peak is None:
        return None
    risk = abs(entry - initial)
    if risk <= 0:
        return None
    sign = 1 if p["side"] == "long" else -1
    peak_r = (peak - entry) * sign / risk
    trigger = float(rules.get("triggerR", 2))
    if peak_r < trigger:
        return None
    lock = float(rules.get("lockR", 1))
    step = float(rules.get("trailStepR", 0))
    if step > 0:
        lock += math.floor((peak_r - trigger) / step) * step
    new_stop = entry + sign * lock * risk
    current = p.get("stop")
    if current is None:
        return new_stop
    return new_stop if (new_stop - current) * sign > 1e-9 else None


# --------------------------------------------------------------------------
# Telegram
# --------------------------------------------------------------------------

class Telegram:
    def __init__(self, server):
        self.server = server
        self.queue = []
        self.cv = threading.Condition()
        threading.Thread(target=self._sender, daemon=True).start()
        threading.Thread(target=self._poller, daemon=True).start()

    @property
    def token(self):
        return (self.server.config.get("telegram") or {}).get("token", "").strip()

    @property
    def chat_id(self):
        return str((self.server.config.get("telegram") or {}).get("chat_id", "")).strip()

    def send(self, text):
        if not self.token:
            return
        with self.cv:
            self.queue.append(text)
            self.cv.notify()

    def _api(self, method, params, timeout=20):
        url = f"https://api.telegram.org/bot{self.token}/{method}"
        data = urllib.parse.urlencode(params).encode()
        with urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=timeout) as r:
            return json.loads(r.read().decode())

    def _sender(self):
        while True:
            with self.cv:
                while not self.queue:
                    self.cv.wait()
                text = self.queue.pop(0)
            if not self.chat_id:
                continue
            for attempt in range(3):
                try:
                    self._api("sendMessage", {"chat_id": self.chat_id, "text": text[:4000]})
                    break
                except Exception:
                    time.sleep(2 * (attempt + 1))

    def _poller(self):
        offset = 0
        while True:
            if not self.token:
                time.sleep(10)
                continue
            try:
                result = self._api("getUpdates", {"timeout": 50, "offset": offset}, timeout=60)
                for update in result.get("result", []):
                    offset = update["update_id"] + 1
                    message = update.get("message") or {}
                    chat = str((message.get("chat") or {}).get("id", ""))
                    text = (message.get("text") or "").strip()
                    if not chat or not text:
                        continue
                    if not self.chat_id:
                        # The first person to message the bot owns it.
                        self.server.config.setdefault("telegram", {})["chat_id"] = chat
                        self.server.save_config()
                        self.send(f"✅ Đã liên kết Telegram (chat id {chat}). Gõ /help để xem lệnh.")
                        continue
                    if chat == self.chat_id:
                        self.send(self.server.telegram_command(text))
            except Exception:
                time.sleep(10)


# --------------------------------------------------------------------------
# Cloudflare quick tunnel
# --------------------------------------------------------------------------

class Tunnel:
    def __init__(self, server):
        self.server = server
        self.url = ""
        self.process = None
        self.error = ""
        threading.Thread(target=self._run, daemon=True).start()

    def _binary(self):
        configured = self.server.config.get("cloudflared")
        if configured:
            return configured
        name = "cloudflared.exe" if IS_WINDOWS else "cloudflared"
        local = os.path.join(HERE, name)
        return local if os.path.exists(local) else name

    def _adopt(self):
        """Right after an update the old cloudflared is still running: keep it and its address."""
        flag = os.path.join(HERE, "update.flag")
        try:
            fresh = now() - os.path.getmtime(flag) < 300
            os.remove(flag)
            pid = int(open(os.path.join(HERE, "tunnel.pid")).read().strip())
            url = open(os.path.join(HERE, "tunnel.txt"), encoding="utf-8").read().strip()
        except (OSError, ValueError):
            return
        if not fresh or not url or not pid_alive(pid):
            return
        self.url = url
        self.server.tunnel_url = url
        self.server.log(f"🌐 Giữ địa chỉ máy chủ sau khi cập nhật: {url}")
        threading.Thread(target=publish_address, args=(self.server,), daemon=True).start()
        while pid_alive(pid):
            time.sleep(10)
        self.url = ""

    def _run(self):
        port = int(self.server.config.get("port", 8787))
        self._adopt()
        while True:
            try:
                self.process = subprocess.Popen(
                    [self._binary(), "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{port}"],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, creationflags=NO_WINDOW)
            except FileNotFoundError:
                self.error = "Không tìm thấy cloudflared"
                return
            try:
                with open(os.path.join(HERE, "tunnel.pid"), "w") as f:
                    f.write(str(self.process.pid))
            except OSError:
                pass
            for raw in self.process.stdout:
                line = raw.decode("utf-8", "replace")
                match = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", line)
                if match and match.group(0) != self.url:
                    self.url = match.group(0)
                    self.error = ""
                    self.server.on_tunnel(self.url)
            self.process.wait()
            self.url = ""
            self.error = "Tunnel bị ngắt, đang kết nối lại"
            time.sleep(10)

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()


# --------------------------------------------------------------------------
# The bot
# --------------------------------------------------------------------------

DEFAULT_SETTINGS = {
    "running": False,
    "source": "binance_futures",
    "symbol": "XAUUSDT",
    "interval": "1m",
    "broker": "paper",
    "strategy": None,
    "strategyName": "",
    "indicators": [],
    "config": None,
    "parameterValues": {},
    "lots": 0.01,
    "riskPercent": 0,
    "allowLong": True,
    "allowShort": True,
    "reverse": True,
    "rules": {},
}

CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

# What members' apps show besides the chart and the signals (the owner chooses).
DEFAULT_MEMBER_FEATURES = {"news": True, "killzones": True, "sharkflow": True, "demo": True,
                           "indicators": False, "backtest": False,
                           # Members may copy into their own REAL-money accounts.
                           "copyReal": False}


def new_member_code():
    raw = "".join(secrets.choice(CODE_ALPHABET) for _ in range(12))
    return "-".join(raw[i:i + 4] for i in range(0, 12, 4))


def code_hash(code):
    return hashlib.sha256(code.strip().upper().encode()).hexdigest()


def relay_topic(secret, kind="url"):
    """ntfy topic the server posts its address to. Only someone holding the owner's
    password (kind "url") or a member's code hash (kind "murl") can work it out."""
    return "aurum-" + hashlib.sha256(f"{kind}:{secret}".encode()).hexdigest()[:24]


def publish_address(server):
    """Posts the tunnel address to ntfy.sh, so the app finds the server again after
    the address changes (VPS restart) without Telegram. Repeated every 6 hours, as
    ntfy keeps messages 12 hours."""
    url = server.tunnel_url
    relay = (server.config.get("url_relay") or "").rstrip("/")
    if not url or not relay:
        return
    topics = [relay_topic(server.config["password"])]
    topics += [relay_topic(m["codeHash"], "murl") for m in server.config.get("members", [])
               if m.get("codeHash") and Members.active(m)]
    for topic in topics:
        try:
            request = urllib.request.Request(f"{relay}/{topic}", data=url.encode(), method="POST",
                                             headers={"User-Agent": "gold-bot/" + VERSION, "Cache": "yes"})
            urllib.request.urlopen(request, timeout=10).close()
        except Exception:
            pass


class Members:
    """People the owner shares the signals with. Each has an invite code (only its
    hash is kept), a role ("signals": sees the signals; "copy": may also copy them into
    their own MT5 account) and an expiry. The signals are the owner's trades: the
    positions of the main MT5 account (bot, app or MT5 itself) or of the VPS demo bot.
    Members never see the strategy, the lot sizes or the owner's account."""

    def __init__(self, server):
        self.server = server
        self.lock = threading.RLock()
        self.items = server.signal_state  # newest first, kept in state.json
        self.by_key = {s["key"]: s for s in self.items if s.get("status") == "open"}
        threading.Thread(target=self._loop, daemon=True).start()

    @property
    def cfg(self):
        return self.server.config.setdefault("members", [])

    @property
    def features(self):
        saved = self.server.config.get("memberFeatures") or {}
        return {k: bool(saved.get(k, v)) for k, v in DEFAULT_MEMBER_FEATURES.items()}

    def set_features(self, body):
        features = self.features
        for key in DEFAULT_MEMBER_FEATURES:
            if key in body:
                features[key] = bool(body[key])
        self.server.config["memberFeatures"] = features
        self.server.save_config()
        return self.list()

    # ----- members -----

    def find(self, mid):
        return next((m for m in self.cfg if m["id"] == mid), None)

    def by_code(self, code):
        digest = code_hash(code)
        for m in self.cfg:
            if hmac.compare_digest(m.get("codeHash", ""), digest):
                return m
        return None

    @staticmethod
    def active(m):
        return bool(m.get("enabled")) and (not m.get("expires") or m["expires"] > now())

    def check(self, m):
        if not m.get("enabled"):
            raise PermissionError("Tài khoản thành viên đã bị khoá")
        if m.get("expires") and m["expires"] <= now():
            raise PermissionError("Mã thành viên đã hết hạn")
        if now() - (m.get("lastSeen") or 0) > 60:
            m["lastSeen"] = now()
            self.server.save_config()

    def public(self, m):
        f = self.server.copier.follower(self.follower_id(m))
        return {"id": m["id"], "name": m["name"], "role": m["role"], "enabled": bool(m.get("enabled")),
                "expires": m.get("expires") or None, "created": m.get("created"), "lastSeen": m.get("lastSeen"),
                "hasCopy": f is not None}

    def list(self):
        with self.lock:
            open_count = sum(1 for s in self.items if s.get("status") == "open")
            return {"ok": True, "members": [self.public(m) for m in self.cfg], "openSignals": open_count,
                    "signals": len(self.items), "url": self.server.tunnel_url, "features": self.features}

    def save(self, body):
        mid = str(body.get("id") or "")
        m = self.find(mid) if mid else None
        code = None
        if m is None:
            m = {"id": uuid.uuid4().hex[:8], "created": now(), "lastSeen": None}
            code = new_member_code()
            m["codeHash"] = code_hash(code)
            self.cfg.append(m)
        m["name"] = str(body.get("name", m.get("name", "")) or "").strip() or "Thành viên"
        role = str(body.get("role", m.get("role", "signals")))
        m["role"] = role if role in ("signals", "copy") else "signals"
        m["enabled"] = bool(body.get("enabled", m.get("enabled", True)))
        if "days" in body:
            days = float(body.get("days") or 0)
            m["expires"] = now() + days * 86400 if days > 0 else None
        self.server.save_config()
        self._sync_followers()
        threading.Thread(target=publish_address, args=(self.server,), daemon=True).start()
        self.server.log(f"👥 {'Thêm' if code else 'Sửa'} thành viên {m['name']} ({m['role']})")
        return dict(self.list(), code=code, member=self.public(m))

    def new_code(self, body):
        m = self.find(str(body.get("id") or ""))
        if m is None:
            raise ValueError("Không có thành viên này")
        code = new_member_code()
        m["codeHash"] = code_hash(code)
        self.server.save_config()
        threading.Thread(target=publish_address, args=(self.server,), daemon=True).start()
        self.server.log(f"👥 Đổi mã thành viên {m['name']} (mã cũ hết dùng được)")
        return dict(self.list(), code=code, member=self.public(m))

    def remove(self, body):
        m = self.find(str(body.get("id") or ""))
        if m is None:
            raise ValueError("Không có thành viên này")
        if self.server.copier.follower(self.follower_id(m)):
            self.server.copier.remove_follower({"id": self.follower_id(m), "closePositions": False})
        self.cfg.remove(m)
        self.server.save_config()
        self.server.log(f"👥 Xoá thành viên {m['name']}")
        return self.list()

    # ----- what a member sees -----

    def me(self, m):
        return {"ok": True, "name": m["name"], "role": m["role"], "expires": m.get("expires") or None,
                "version": VERSION, "ownerCopyOn": bool(self.server.copier.cfg["enabled"]),
                "features": self.features}

    def signals(self, m=None, limit=60):
        """The signals; for a member who copies, with the lots copied into their account."""
        copies = {}
        if m is not None and m.get("role") == "copy":
            copies = self.server.copy_state.get(self.follower_id(m), {}).get("copies", {})
        rows = []
        with self.lock:
            for s in self.items[:limit]:
                row = {k: v for k, v in s.items() if k != "key"}
                if s["key"].startswith("mt5:") and s["key"][4:] in copies:
                    row["copy"] = copies[s["key"][4:]]
                rows.append(row)
        return {"ok": True, "signals": rows}

    @staticmethod
    def follower_id(m):
        return "m" + m["id"]

    def copy_status(self, m):
        status = self.server.copier.status()
        row = next((f for f in status["followers"] if f["id"] == self.follower_id(m)), None)
        return {"ok": True, "follower": row, "ownerCopyOn": status["enabled"],
                "allowed": m["role"] == "copy"}

    def copy_save(self, m, body):
        if m["role"] != "copy":
            raise PermissionError("Mã của bạn chỉ được xem tín hiệu (không có quyền copy lệnh)")
        fid = self.follower_id(m)
        current = self.server.copier.follower(fid)
        if body.get("allowReal") and not self.features["copyReal"]:
            raise PermissionError("Người cung cấp chưa cho copy vào tài khoản thật: dùng tài khoản demo")
        data = {k: body[k] for k in ("login", "password", "server", "multiplier", "fixedLots", "maxLots",
                                     "allowReal", "symbolMap") if k in body}
        data.update(id=fid if current else "", name=m["name"], path="")
        self.server.copier.save_follower(data, new_id=fid)
        f = self.server.copier.follower(fid)
        f["member"] = m["id"]
        f["memberEnabled"] = bool(body.get("enabled", True))
        self._sync_followers()
        return self.copy_status(m)

    def copy_remove(self, m):
        if self.server.copier.follower(self.follower_id(m)):
            self.server.copier.remove_follower({"id": self.follower_id(m), "closePositions": False})
        return self.copy_status(m)

    def _sync_followers(self):
        """A member's copy runs only while the member is active and wants it."""
        changed = False
        for f in self.server.copier.cfg["followers"]:
            if not f.get("member"):
                continue
            m = self.find(f["member"])
            on = m is not None and self.active(m) and m["role"] == "copy" and f.get("memberEnabled", True)
            if bool(f.get("enabled")) != on:
                f["enabled"] = on
                changed = True
            if f.get("allowReal") and not self.features["copyReal"]:
                # The owner took it back: a real account then refuses to copy.
                f["allowReal"] = False
                changed = True
        if changed:
            self.server.save_config()

    # ----- the signal feed -----

    def _loop(self):
        while True:
            try:
                if self.cfg:
                    self._scan()
                    self._sync_followers()
            except Exception as e:
                if os.environ.get("BOT_DEBUG"):
                    print("signals:", e)
            time.sleep(3)

    def _owner_positions(self):
        mt5_cfg = self.server.config.get("mt5") or {}
        if mt5_cfg.get("login"):
            with Mt5.lock:
                mt5 = Mt5.connect(mt5_cfg)
                if mt5.account_info() is None:
                    return None
                rows = mt5.positions_get() or ()
                return [{"key": f"mt5:{r.ticket}", "symbol": r.symbol,
                         "side": "long" if r.type == mt5.POSITION_TYPE_BUY else "short",
                         "entry": r.price_open, "stop": r.sl or None, "target": r.tp or None,
                         "price": r.price_current, "time": float(r.time) - Mt5.offset_seconds}
                        for r in rows if r.magic != COPY_MAGIC]
        with self.server.lock:
            return [{"key": f"paper:{p['id']}", "symbol": p["symbol"], "side": p["side"], "entry": p["entryPrice"],
                     "stop": p.get("stop"), "target": p.get("target"),
                     "price": self.server.prices.get(p["symbol"], p["entryPrice"]),
                     "time": p.get("openTime") or now()} for p in self.server.paper.get("positions", [])]

    def _scan(self):
        rows = self._owner_positions()
        if rows is None:
            return
        changed = False
        seen = set()
        with self.lock:
            for r in rows:
                seen.add(r["key"])
                s = self.by_key.get(r["key"])
                if s is None:
                    s = {"id": uuid.uuid4().hex[:10], "key": r["key"], "symbol": r["symbol"], "side": r["side"],
                         "entry": r["entry"], "stop": r["stop"], "target": r["target"], "price": r["price"],
                         "openTime": r["time"], "status": "open"}
                    self.items.insert(0, s)
                    self.by_key[r["key"]] = s
                    changed = True
                    self.server.log(f"📣 Tín hiệu {'MUA' if r['side'] == 'long' else 'BÁN'} {r['symbol']} @ {fmt(r['entry'])}"
                                    f" · SL {fmt(r['stop']) if r['stop'] else '–'} · TP {fmt(r['target']) if r['target'] else '–'}")
                else:
                    if (s["stop"], s["target"]) != (r["stop"], r["target"]):
                        s["stop"], s["target"] = r["stop"], r["target"]
                        changed = True
                    s["price"] = r["price"]
            for key in [k for k in self.by_key if k not in seen]:
                s = self.by_key.pop(key)
                s["status"] = "closed"
                s["exit"] = s.get("price")
                s["closeTime"] = now()
                sign = 1 if s["side"] == "long" else -1
                s["result"] = (s["exit"] - s["entry"]) * sign if s.get("exit") is not None else None
                changed = True
            del self.items[200:]
        if changed:
            self.server.save_state()


class BotServer:
    def __init__(self):
        self.lock = threading.RLock()
        self.config = merge(DEFAULT_CONFIG, read_json(CONFIG_PATH, {}))
        if not self.config.get("password"):
            self.config["password"] = secrets.token_urlsafe(12)
            self.save_config()
            print("Đã tạo mật khẩu mới trong config.json:", self.config["password"])
        state = read_json(STATE_PATH, {})
        self.settings = merge(DEFAULT_SETTINGS, state.get("settings"))
        self.paper = state.get("paper") or {"balance": float(self.config["paper_balance"]), "positions": [], "history": []}
        self.mt5_memory = state.get("mt5Memory") or {}
        self.copy_state = state.get("copy") or {}
        self.signal_state = state.get("signals") or []
        self.log_entries = state.get("log") or []
        self.feed = None
        self.feed_key = None
        self.broker = PaperBroker(self.paper)
        self.candles = []
        self.prices = {}
        self.last_eval_time = None
        self.error = ""
        self.started_at = now()
        self.last_poll = 0
        self.tunnel_url = ""
        self.mt5_account = Mt5Account(self)
        self.copier = CopyTrader(self)
        self.members = Members(self)
        self.telegram = Telegram(self)
        self.tunnel = Tunnel(self) if self.config.get("tunnel") else None
        threading.Thread(target=self._relay_loop, daemon=True).start()

    def _relay_loop(self):
        while True:
            time.sleep(6 * 3600)
            publish_address(self)

    # ----- persistence -----

    def save_config(self):
        write_json(CONFIG_PATH, self.config)

    def save_state(self):
        with self.lock:
            write_json(STATE_PATH, {"settings": self.settings, "paper": self.paper, "mt5Memory": self.mt5_memory,
                                    "copy": self.copy_state, "signals": self.signal_state,
                                    "log": self.log_entries[:300]})

    def log(self, text, notify=False):
        with self.lock:
            self.log_entries.insert(0, {"time": now(), "text": text})
            del self.log_entries[300:]
        line = time.strftime("%Y-%m-%d %H:%M:%S ") + text
        print(line, flush=True)
        try:
            if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > 5_000_000:
                os.replace(LOG_PATH, LOG_PATH + ".old")
            with open(LOG_PATH, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass
        if notify:
            self.telegram.send(text)

    def on_tunnel(self, url):
        self.tunnel_url = url
        try:
            with open(os.path.join(HERE, "tunnel.txt"), "w", encoding="utf-8") as f:
                f.write(url + "\n")
        except OSError:
            pass
        self.log(f"🌐 Địa chỉ máy chủ: {url}\n(dán vào app → Backtest → Bot → Máy chủ VPS)", notify=True)
        threading.Thread(target=publish_address, args=(self,), daemon=True).start()

    # ----- control -----

    def start(self, body):
        with self.lock:
            s = merge(DEFAULT_SETTINGS, self.settings)
            for key in DEFAULT_SETTINGS:
                if key in body and key != "running":
                    s[key] = body[key]
            if s["source"] not in SOURCES:
                raise ValueError("Nguồn giá không hợp lệ")
            if s["interval"] not in INTERVALS:
                raise ValueError("Khung thời gian trên VPS: 1m, 5m, 15m, 30m, 1h, 4h, 1d")
            if s["broker"] == "mt5" and s["source"] != "mt5":
                raise ValueError("Đặt lệnh MT5 cần nguồn giá MT5")
            if not s.get("strategy") and not body.get("sampleStrategy"):
                raise ValueError("Chưa chọn chiến lược")
            s["lots"] = max(0.01, float(s["lots"]))
            check = run_botkit(self.config, self._botkit_request(s, [], body.get("sampleStrategy"), command="validate"))
            if not check.get("ok"):
                raise ValueError("Lỗi chiến lược: " + str(check.get("error")))
            if body.get("sampleStrategy"):
                s["sampleStrategy"] = body["sampleStrategy"]
                s["strategyName"] = s.get("strategyName") or body["sampleStrategy"]
            self._make_broker(s)
            s["running"] = True
            self.settings = s
            self.feed_key = None
            self.last_eval_time = None
            self.error = ""
            self.save_state()
        self.log(f"▶︎ Bot chạy: {s['strategyName'] or 'chiến lược'} · {s['symbol']} {s['interval']} · "
                 f"{'lệnh THẬT MT5' if s['broker'] == 'mt5' else 'tài khoản demo'}", notify=True)

    def stop(self, reason="từ app"):
        with self.lock:
            if not self.settings.get("running"):
                return
            self.settings["running"] = False
            self.save_state()
        self.log(f"■ Bot dừng ({reason}). Lệnh đang mở vẫn giữ SL/TP.", notify=True)

    def _make_broker(self, s):
        if s["broker"] == "mt5":
            if not isinstance(self.broker, Mt5Broker):
                self.broker = Mt5Broker(self.config["mt5"], self.mt5_memory)
        elif not isinstance(self.broker, PaperBroker):
            self.broker = PaperBroker(self.paper)

    def _ensure_feed(self):
        s = self.settings
        key = (s["source"], s["symbol"], s["interval"])
        if self.feed is not None and self.feed_key == key:
            return
        if s["source"] == "mt5":
            self.feed = Mt5Feed(self.config["mt5"], s["symbol"], s["interval"])
        elif s["source"] == "sample":
            self.feed = SampleFeed(s["symbol"], s["interval"], self.config.get("sample_bar_seconds", 0))
        else:
            self.feed = BinanceFeed(s["source"] == "binance_futures", s["symbol"], s["interval"])
        self.candles = self.feed.history(int(self.config.get("history_bars", 1000)))
        self.feed_key = key
        # Signals on bars before the start are history, not new trades.
        self.last_eval_time = self.candles[-2][0] if len(self.candles) > 1 else None
        self.log(f"Đã tải {len(self.candles)} nến {s['symbol']} {s['interval']} ({s['source']})")

    def _botkit_request(self, s, candles, sample=None, command="evaluate", positions=None):
        request = {"command": command, "candles": candles, "allowLong": bool(s["allowLong"]),
                   "allowShort": bool(s["allowShort"]), "parameterValues": s.get("parameterValues") or {},
                   "indicators": s.get("indicators") or [], "rules": s.get("rules") or {}}
        if s.get("config"):
            request["config"] = s["config"]
        if s.get("strategy"):
            request["strategy"] = s["strategy"]
        else:
            request["sampleStrategy"] = sample or s.get("sampleStrategy")
        if positions:
            request["positions"] = [dict(p, id=botkit_id(p["id"]), openTime=p.get("openTime") or 0,
                                         contractSize=p.get("contractSize") or 1) for p in positions]
        return request

    # ----- main loop -----

    def loop(self):
        if self.settings.get("running"):
            try:
                self._make_broker(self.settings)
                self.log("Khởi động lại: tiếp tục chạy bot", notify=True)
            except Exception as e:
                self.settings["running"] = False
                self.log(f"⚠︎ Không chạy lại được bot: {e}", notify=True)
        while True:
            started = now()
            try:
                self.tick()
            except Exception as e:
                message = str(e) or e.__class__.__name__
                if message != self.error:
                    self.log(f"⚠︎ {message}", notify=self.settings.get("running", False))
                self.error = message
                if os.environ.get("BOT_DEBUG"):
                    traceback.print_exc()
                self.feed_key = None
                time.sleep(10)
            time.sleep(max(0.2, float(self.config.get("poll_seconds", 2)) - (now() - started)))

    def tick(self):
        uses_mt5 = self.settings.get("source") == "mt5" or self.settings.get("broker") == "mt5"
        with self.lock, (Mt5.lock if uses_mt5 else _NoLock()):
            s = self.settings
            has_positions = bool(self.broker.positions(s["symbol"]))
            if not s.get("running") and not has_positions:
                return
            self._ensure_feed()
            bars = self.feed.poll()
            self.last_poll = now()
            self.error = ""
            new_closed = self._merge(bars)
            price = self.feed.price(self.candles)
            if price is None:
                return
            symbol = s["symbol"]
            self.prices[symbol] = price
            events = self.broker.on_price(symbol, price)
            rules = s.get("rules") or {}
            for p in self.broker.positions(symbol):
                stop = improved_stop(p, rules)
                if stop is not None:
                    events += self.broker.set_stop(p["id"], stop)
            if new_closed and s.get("running"):
                events += self.evaluate(price)
            for event in events:
                self.report(event)
            if events:
                self.save_state()

    def _merge(self, bars):
        """Adds polled bars; True when a new bar closed."""
        if not bars:
            return False
        by_time = {b[0]: i for i, b in enumerate(self.candles[-5:], start=max(0, len(self.candles) - 5))}
        for bar in bars:
            if bar[0] in by_time:
                self.candles[by_time[bar[0]]] = bar
            elif not self.candles or bar[0] > self.candles[-1][0]:
                self.candles.append(bar)
        limit = int(self.config.get("history_bars", 1000)) + 50
        if len(self.candles) > limit:
            del self.candles[:len(self.candles) - limit]
        last_closed = self.candles[-2][0] if len(self.candles) > 1 else None
        return last_closed is not None and (self.last_eval_time is None or last_closed > self.last_eval_time)

    def evaluate(self, price):
        s = self.settings
        closed = self.candles[:-1]
        self.last_eval_time = closed[-1][0]
        symbol = s["symbol"]
        positions = self.broker.positions(symbol)
        result = run_botkit(self.config, self._botkit_request(s, closed, positions=positions))
        if not result.get("ok"):
            raise RuntimeError("Lỗi chiến lược: " + str(result.get("error")))
        events = []
        by_botkit_id = {botkit_id(p["id"]): p for p in positions}
        for rev in result.get("reversals", []):
            p = by_botkit_id.get(str(rev.get("id")).upper())
            if p:
                self.log(f"↩︎ {rev.get('reason')}")
                events += self.broker.close(p["id"], price, "reversal")
        for signal in result.get("lastBarSignals", []):
            events += self.handle(signal, price)
        return events

    def handle(self, signal, price):
        s = self.settings
        symbol = s["symbol"]
        kind = signal.get("kind")
        positions = self.broker.positions(symbol)
        events = []
        if kind in ("longExit", "shortExit"):
            side = "long" if kind == "longExit" else "short"
            for p in positions:
                if p["side"] == side:
                    events += self.broker.close(p["id"], price, "manual")
            return events
        side = "long" if kind == "longEntry" else "short"
        if not (s["allowLong"] if side == "long" else s["allowShort"]):
            return events
        if any(p["side"] == side for p in positions):
            return events
        opposite = [p for p in positions if p["side"] != side]
        if opposite:
            if not s.get("reverse", True):
                return events
            for p in opposite:
                events += self.broker.close(p["id"], price, "manual")
        stop, target = signal.get("stop"), signal.get("target")
        if stop is not None and (stop >= price if side == "long" else stop <= price):
            return events + [("skip", f"Bỏ tín hiệu: SL {fmt(stop)} sai phía so với giá {fmt(price)}")]
        if target is not None and (target <= price if side == "long" else target >= price):
            return events + [("skip", f"Bỏ tín hiệu: TP {fmt(target)} sai phía so với giá {fmt(price)}")]
        return events + self.broker.open(symbol, side, self.order_lots(price, stop), price, stop, target)

    def order_lots(self, entry, stop):
        s = self.settings
        risk = float(s.get("riskPercent") or 0)
        if risk > 0 and stop is not None and abs(entry - stop) > 0:
            balance = self.broker.info(self.prices).get("balance", 0)
            lots = balance * risk / 100 / (abs(entry - stop) * contract_size(s["symbol"]))
            return max(0.01, math.floor(lots * 100) / 100)
        return max(0.01, float(s.get("lots", 0.01)))

    def report(self, event):
        kind, data = event
        if kind == "error":
            self.log("⚠︎ " + data, notify=True)
        elif kind == "skip":
            self.log(data)
        elif kind == "opened":
            text = (f"{'🟢 MUA' if data['side'] == 'long' else '🔴 BÁN'} {data['lots']:.2f} lot {data['symbol']} "
                    f"@ {fmt(data['entryPrice'])}")
            if data.get("stop") is not None:
                text += f" · SL {fmt(data['stop'])}"
            if data.get("target") is not None:
                text += f" · TP {fmt(data['target'])}"
            self.log(text, notify=True)
        elif kind == "closed":
            label = {"target": "🎯 Chạm TP (Target fill)", "stop": "🛑 Chạm SL (Stop loss fill)",
                     "reversal": "↩︎ Tự chốt (đảo chiều)"}.get(data.get("reason"), "✖︎ Đóng lệnh")
            self.log(f"{label} {data['symbol']} {money(data.get('profit', 0))}", notify=True)
        elif kind == "stopMoved":
            self.log(f"🔒 Dời SL {data['symbol']} → {fmt(data.get('stop'))}", notify=True)

    # ----- views -----

    def status(self):
        with self.lock:
            s = self.settings
            try:
                positions = self.broker.positions(s["symbol"]) if s else []
                account = self.broker.info(self.prices)
            except Exception as e:
                positions, account = [], {"mode": self.broker.name, "error": str(e)}
            for p in positions:
                price = self.prices.get(p["symbol"])
                if price is not None and "profit" not in p:
                    p["profit"] = (price - p["entryPrice"]) * (1 if p["side"] == "long" else -1) * p["lots"] * p["contractSize"]
            settings = {k: v for k, v in s.items() if k not in ("strategy", "indicators", "config")}
            return {"ok": True, "version": VERSION, "running": bool(s.get("running")), "settings": settings,
                    "price": self.prices.get(s["symbol"]), "bars": len(self.candles),
                    "lastBarTime": self.candles[-1][0] if self.candles else None, "lastPoll": self.last_poll,
                    "error": self.error, "tunnelURL": self.tunnel_url, "startedAt": self.started_at,
                    "account": account, "positions": positions,
                    "telegram": {"configured": bool(self.telegram.token), "linked": bool(self.telegram.chat_id)},
                    "mt5": {"error": Mt5.error, "connected": Mt5.connected, "tradingEnabled":
                            bool(self.config["mt5"].get("trading_enabled")), "maxLots": self.config["mt5"].get("max_lots")}}

    def close_positions(self, position_id=None):
        with self.lock:
            s = self.settings
            price = self.prices.get(s["symbol"])
            events = []
            for p in self.broker.positions(s["symbol"]):
                if position_id in (None, p["id"]):
                    events += self.broker.close(p["id"], price if price is not None else p["entryPrice"], "manual")
            for event in events:
                self.report(event)
            self.save_state()
            return len([e for e in events if e[0] == "closed"])

    def self_update(self):
        """Downloads the latest bot (bot-latest release), replaces the files and restarts
        through run.ps1, keeping config.json, state.json and the tunnel address."""
        import io
        import zipfile
        with urllib.request.urlopen(RELEASE_ZIP, timeout=180) as response:
            data = response.read()
        archive = zipfile.ZipFile(io.BytesIO(data))
        names = [n for n in archive.namelist() if not n.endswith("/")]
        if "bot_server.py" not in names:
            raise ValueError("Bản tải về không hợp lệ")
        source = archive.read("bot_server.py").decode("utf-8")
        match = re.search(r'VERSION = "([^"]+)"', source)
        version = match.group(1) if match else "?"
        for name in names:
            if name in ("config.json", "state.json"):
                continue
            target = os.path.join(HERE, name)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            for attempt in range(5):
                try:
                    with open(target, "wb") as f:
                        f.write(archive.read(name))
                    break
                except PermissionError:
                    if attempt == 4:
                        raise
                    time.sleep(1)
        with open(os.path.join(HERE, "update.flag"), "w") as f:
            f.write(str(now()))
        self.log(f"⬆︎ Đã tải bản {version}, máy chủ khởi động lại…", notify=True)
        self.save_state()

        def restart():
            time.sleep(1.5)
            # Start the new version ourselves too: it steps aside if run.ps1 brings one
            # up first (an older run.ps1 waited for the tunnel and never did).
            args = [a for a in sys.argv[1:] if a != "--after-update"]
            flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
            try:
                subprocess.Popen([sys.executable, os.path.join(HERE, "bot_server.py"), "--after-update"] + args,
                                 cwd=HERE, creationflags=flags, close_fds=True,
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                pass
            os._exit(UPDATE_EXIT_CODE)

        threading.Thread(target=restart, daemon=True).start()
        return {"ok": True, "version": version, "current": VERSION, "restarting": True}

    def reset_paper(self, balance):
        with self.lock:
            self.paper.clear()
            self.paper.update({"balance": float(balance), "positions": [], "history": []})
            self.save_state()
        self.log(f"Đặt lại tài khoản demo VPS: {balance:.2f}$")

    def telegram_command(self, text):
        command = text.split()[0].split("@")[0].lower()
        if command in ("/status", "/trangthai"):
            st = self.status()
            a = st["account"]
            lines = [f"{'▶︎ Đang chạy' if st['running'] else '■ Đang dừng'} · {st['settings'].get('strategyName') or '—'}",
                     f"{st['settings']['symbol']} {st['settings']['interval']} · giá {fmt(st['price'])}",
                     f"Tài khoản {a.get('mode')}: số dư {a.get('balance', 0):.2f} · equity {a.get('equity', 0):.2f}"]
            for p in st["positions"]:
                lines.append(f"• {'MUA' if p['side'] == 'long' else 'BÁN'} {p['lots']:.2f} @ {fmt(p['entryPrice'])} "
                             f"SL {fmt(p.get('stop'))} TP {fmt(p.get('target'))} {money(p.get('profit', 0))}")
            if st["error"]:
                lines.append("⚠︎ " + st["error"])
            return "\n".join(lines)
        if command in ("/url", "/diachi"):
            return f"🌐 {self.tunnel_url or 'Chưa có địa chỉ tunnel'}"
        if command in ("/stop", "/dung"):
            self.stop("từ Telegram")
            return "Đã dừng bot."
        if command in ("/start", "/chay"):
            if not self.settings.get("strategy") and not self.settings.get("sampleStrategy"):
                return "Chưa có chiến lược: chạy bot từ app trước."
            try:
                self.start({})
                return "Đã chạy lại bot với cài đặt lần trước."
            except Exception as e:
                return f"Không chạy được: {e}"
        if command in ("/close", "/dong"):
            return f"Đã đóng {self.close_positions()} lệnh."
        return ("Lệnh:\n/status – trạng thái\n/url – địa chỉ máy chủ cho app\n/start – chạy lại bot\n"
                "/stop – dừng bot\n/close – đóng mọi lệnh của bot")


# --------------------------------------------------------------------------
# HTTP API for the app
# --------------------------------------------------------------------------

def make_handler(server):
    failures = {"count": 0}

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt_, *args):
            pass

        def _send(self, code, payload):
            data = json.dumps(payload, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _authorized(self, path):
            """True for the owner; a member (their entry) only on /member/ paths."""
            header = self.headers.get("Authorization", "")
            given = header[7:] if header.startswith("Bearer ") else self.headers.get("X-Bot-Password", "")
            if given and hmac.compare_digest(given.encode(), server.config["password"].encode()):
                failures["count"] = 0
                if path.startswith("/member/"):
                    self._send(403, {"ok": False, "error": "Đây là mật khẩu chủ máy chủ: dùng mã thành viên"})
                    return False
                return True
            member = server.members.by_code(given) if given else None
            if member is not None:
                failures["count"] = 0
                if not path.startswith("/member/"):
                    self._send(403, {"ok": False, "error": "Mã thành viên chỉ xem được tín hiệu"})
                    return False
                return member
            failures["count"] += 1
            time.sleep(min(5, failures["count"]))  # slows down password guessing
            self._send(401, {"ok": False, "error": "Sai mật khẩu máy chủ"})
            return False

        def _body(self):
            length = int(self.headers.get("Content-Length") or 0)
            if length > 5_000_000:
                raise ValueError("Yêu cầu quá lớn")
            raw = self.rfile.read(length) if length else b"{}"
            return json.loads(raw.decode() or "{}")

        def do_GET(self):
            path, _, query = self.path.partition("?")
            params = urllib.parse.parse_qs(query)
            limit = int((params.get("limit") or ["100"])[0])
            if path == "/ping":
                return self._send(200, {"ok": True, "app": "gold-bot", "version": VERSION})
            who = self._authorized(path)
            if not who:
                return
            try:
                if isinstance(who, dict):
                    server.members.check(who)
                    if path == "/member/me":
                        return self._send(200, server.members.me(who))
                    if path == "/member/signals":
                        return self._send(200, server.members.signals(who, min(limit, 200)))
                    if path == "/member/copy":
                        return self._send(200, server.members.copy_status(who))
                    return self._send(404, {"ok": False, "error": "Không có đường dẫn này"})
                if path == "/members":
                    return self._send(200, server.members.list())
                if path == "/status":
                    return self._send(200, server.status())
                if path == "/log":
                    with server.lock:
                        return self._send(200, {"ok": True, "log": server.log_entries[:limit]})
                if path == "/history":
                    with server.lock:
                        return self._send(200, {"ok": True, "history": server.broker.history()[:limit]})
                if path == "/samples":
                    return self._send(200, run_botkit(server.config, {"command": "samples"}))
                if path == "/mt5/status":
                    return self._send(200, server.mt5_account.status())
                if path == "/mt5/symbols":
                    return self._send(200, server.mt5_account.symbols((params.get("q") or [""])[0], limit))
                if path == "/copy/status":
                    return self._send(200, server.copier.status())
                if path == "/mt5/history":
                    end = float((params.get("to") or [now()])[0])
                    start = float((params.get("from") or [end - 86400])[0])
                    return self._send(200, server.mt5_account.history(start, end))
                if path == "/mt5/trading":
                    symbol = (params.get("symbol") or [None])[0]
                    return self._send(200, server.mt5_account.trading(symbol))
                if path == "/mt5/candles":
                    symbol = (params.get("symbol") or [""])[0]
                    if not symbol:
                        raise ValueError("Thiếu mã")
                    return self._send(200, server.mt5_account.candles(
                        symbol, (params.get("interval") or ["1m"])[0], (params.get("count") or ["500"])[0],
                        (params.get("before") or [None])[0]))
                self._send(404, {"ok": False, "error": "Không có đường dẫn này"})
            except PermissionError as e:
                self._send(403, {"ok": False, "error": str(e)})
            except ValueError as e:
                self._send(400, {"ok": False, "error": str(e)})
            except Exception as e:
                self._send(500, {"ok": False, "error": str(e)})

        def do_POST(self):
            path = self.path.partition("?")[0]
            who = self._authorized(path)
            if not who:
                return
            try:
                body = self._body()
                if isinstance(who, dict):
                    server.members.check(who)
                    if path == "/member/copy":
                        return self._send(200, server.members.copy_save(who, body))
                    if path == "/member/copy/remove":
                        return self._send(200, server.members.copy_remove(who))
                    return self._send(404, {"ok": False, "error": "Không có đường dẫn này"})
                if path == "/members/save":
                    return self._send(200, server.members.save(body))
                if path == "/members/code":
                    return self._send(200, server.members.new_code(body))
                if path == "/members/features":
                    return self._send(200, server.members.set_features(body))
                if path == "/members/remove":
                    return self._send(200, server.members.remove(body))
                if path == "/start":
                    server.start(body)
                    return self._send(200, server.status())
                if path == "/stop":
                    server.stop()
                    return self._send(200, server.status())
                if path == "/close":
                    count = server.close_positions(body.get("id") if not body.get("all") else None)
                    return self._send(200, dict(server.status(), closed=count))
                if path == "/reset":
                    if server.settings.get("broker") == "mt5":
                        raise ValueError("Chỉ đặt lại được tài khoản demo VPS")
                    server.reset_paper(float(body.get("balance", server.config["paper_balance"])))
                    return self._send(200, server.status())
                if path == "/mt5/login":
                    return self._send(200, server.mt5_account.login(body))
                if path == "/mt5/logout":
                    return self._send(200, server.mt5_account.logout())
                if path == "/mt5/settings":
                    return self._send(200, server.mt5_account.settings(body))
                if path == "/mt5/order":
                    return self._send(200, server.mt5_account.order(body))
                if path == "/mt5/close":
                    return self._send(200, server.mt5_account.close(body))
                if path == "/mt5/modify":
                    return self._send(200, server.mt5_account.modify(body))
                if path == "/mt5/cancel":
                    return self._send(200, server.mt5_account.cancel(body))
                if path == "/update":
                    return self._send(200, server.self_update())
                if path == "/copy/settings":
                    return self._send(200, server.copier.settings(body))
                if path == "/copy/follower":
                    return self._send(200, server.copier.save_follower(body))
                if path == "/copy/remove":
                    return self._send(200, server.copier.remove_follower(body))
                if path == "/copy/close":
                    return self._send(200, server.copier.close_follower(body))
                if path == "/telegram-test":
                    server.telegram.send("🔔 Thử thông báo từ máy chủ bot")
                    return self._send(200, {"ok": True})
                self._send(404, {"ok": False, "error": "Không có đường dẫn này"})
            except PermissionError as e:
                self._send(403, {"ok": False, "error": str(e)})
            except ValueError as e:
                self._send(400, {"ok": False, "error": str(e)})
            except Exception as e:
                self._send(500, {"ok": False, "error": str(e)})

    return Handler


# --------------------------------------------------------------------------

def selftest():
    config = merge(DEFAULT_CONFIG, read_json(CONFIG_PATH, {}))
    feed = SampleFeed("XAUUSDT", "1m", 60)
    bars = feed.history(600)[:-1]
    samples = run_botkit(config, {"command": "samples"})
    print("botkit:", botkit_path(config))
    if not samples.get("ok"):
        print("LỖI:", samples.get("error"))
        return 1
    total = 0
    for name in samples["samples"]:
        result = run_botkit(config, {"sampleStrategy": name, "candles": bars, "rules": {"closeOnReversal": True}})
        if not result.get("ok"):
            print(f"LỖI {name}: {result.get('error')}")
            return 1
        total += len(result["signals"])
        print(f"OK  {name}: {len(result['signals'])} tín hiệu gần nhất / {result['bars']} nến")
    p = {"id": "1", "side": "long", "entryPrice": 100.0, "initialStop": 99.0, "peakPrice": 102.5, "stop": 99.0}
    assert improved_stop(p, {}) == 101.0, "improved_stop"
    assert improved_stop(dict(p, stop=101.0), {}) is None
    assert botkit_id("12345") == str(uuid.UUID(int=12345)).upper()
    broker = PaperBroker({"balance": 1000.0, "positions": [], "history": []})
    broker.open("XAUUSDT", "short", 0.01, 2000.0, 2005.0, 1990.0)
    events = broker.on_price("XAUUSDT", 1989.0)
    assert events and events[0][1]["reason"] == "target" and abs(broker.account["balance"] - 1010.0) < 1e-6
    print(f"Tự kiểm tra xong: {len(samples['samples'])} chiến lược, {total} tín hiệu.")
    return 0


def main():
    if "--copy-worker" in sys.argv:
        return copy_worker_main()
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    if "--after-update" in sys.argv:
        # Started by an update: run only if no other copy (run.ps1's) answers on the port.
        time.sleep(8)
        port = int(read_json(CONFIG_PATH, {}).get("port", 8787))
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/ping", timeout=5):
                return
        except OSError:
            pass
    server = BotServer()
    port = int(server.config.get("port", 8787))
    httpd = ThreadingHTTPServer(("0.0.0.0" if "--public" in sys.argv else "127.0.0.1", port), make_handler(server))
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    server.log(f"Máy chủ bot {VERSION} đang chạy, cổng {port}")
    try:
        server.loop()
    except KeyboardInterrupt:
        pass
    finally:
        if server.tunnel:
            server.tunnel.stop()
        server.save_state()


if __name__ == "__main__":
    main()
