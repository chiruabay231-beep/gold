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

import collections
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
import types
import time
import traceback
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "6.9"
RELEASE_ZIP = "https://github.com/chiruabay231-beep/gold/releases/download/bot-latest/gold-bot-windows.zip"
# Exit code that tells run.ps1 to restart at once and keep the tunnel (same address).
UPDATE_EXIT_CODE = 3
HERE = os.path.dirname(os.path.abspath(__file__))
# A second copy of the server (for the website's own MT5 account) runs with `--instance web`: its own
# config / state / log / tunnel files ("web.config.json"…), its own port and its own MT5 terminal.
INSTANCE = ""


def own(name):
    return os.path.join(HERE, f"{INSTANCE}.{name}" if INSTANCE else name)


CONFIG_PATH = os.path.join(HERE, "config.json")
STATE_PATH = os.path.join(HERE, "state.json")
# SL / TP of the MT5 positions as seen (set on opening, or dragged later): MT5's history keeps neither.
STOPS_PATH = os.path.join(HERE, "stops.json")
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


def on_tick(info, price):
    """A price on the symbol's tick grid (oil, indices… move in steps bigger than a digit), else MT5 refuses it."""
    price = float(price)
    step = getattr(info, "trade_tick_size", 0) or 0
    if step > 0:
        price = round(price / step) * step
    return round(price, info.digits)


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
                if cfg.get("portable"):
                    kwargs["portable"] = True
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

    # Other names of the same market at other brokers.
    ALIASES = {"XAUUSD": ("GOLD", "XAUUSD"), "XAGUSD": ("SILVER", "XAGUSD"), "USTEC": ("NAS100", "US100", "NDX100", "USTEC"),
               "US30": ("DJ30", "WS30", "DOW30", "US30"), "US500": ("SPX500", "SP500", "US500"), "USOIL": ("WTI", "XTIUSD", "USOIL"),
               "UKOIL": ("BRENT", "XBRUSD", "UKOIL"), "BTCUSD": ("BTCUSD", "BITCOIN"), "ETHUSD": ("ETHUSD", "ETHEREUM")}
    _names = {}

    @classmethod
    def find_symbol(cls, mt5, symbol):
        """The account's own name for `symbol`: as asked when it has it, else the same market with the
        broker's suffix / prefix (XAUUSD ↔ XAUUSDm, XAUUSD.r, #XAUUSD…) or another usual name (GOLD).
        None when the account has nothing like it. Kept per account (forgotten at a login)."""
        a = mt5.account_info()
        key = (a.login if a else 0, a.server if a else "", symbol)
        if key in cls._names:
            return cls._names[key]
        found = symbol if mt5.symbol_info(symbol) is not None else None
        if found is None:
            base = base_symbol(symbol)
            wanted = {base}
            for k, names in cls.ALIASES.items():
                if base == k or base in names:
                    wanted.update(names); wanted.add(k)
            rows = mt5.symbols_get() or ()
            hits = [r for r in rows if base_symbol(r.name) in wanted]
            # Market Watch first, the base name itself, then the shortest.
            hits.sort(key=lambda r: (not r.visible, base_symbol(r.name) != base, len(r.name), r.name))
            found = hits[0].name if hits else None
        if found is not None:
            mt5.symbol_select(found, True)
            cls._names[key] = found
        return found

    @classmethod
    def need_symbol(cls, mt5, symbol):
        """`find_symbol`, or an error naming the closest symbols of the account."""
        found = cls.find_symbol(mt5, symbol)
        if found is None or not mt5.symbol_select(found, True):
            base = base_symbol(symbol)[:3]
            near = [r.name for r in (mt5.symbols_get() or ()) if r.name.upper().startswith(base)][:6]
            raise ValueError(f"MT5 không có mã {symbol}" + (f" — tài khoản này có: {', '.join(near)}" if near else ""))
        return found

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


MT5_TIMEFRAMES = {"1m": "M1", "2m": "M2", "3m": "M3", "4m": "M4", "5m": "M5", "6m": "M6", "10m": "M10", "12m": "M12",
                  "15m": "M15", "20m": "M20", "30m": "M30", "1h": "H1", "4h": "H4", "1d": "D1", "1w": "W1"}


class Mt5Feed:
    def __init__(self, cfg, symbol, interval):
        self.cfg = cfg
        self.symbol = symbol
        mt5 = Mt5.connect(cfg)
        self.timeframe = getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[interval])
        try:
            self.symbol = Mt5.need_symbol(mt5, symbol)
        except ValueError as e:
            raise RuntimeError(str(e))

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
        if result.retcode == getattr(mt5, "TRADE_RETCODE_INVALID_STOPS", 10016):
            return None, ("SL/TP không hợp lệ (10016): lệnh MUA cần SL dưới giá hiện tại và TP trên giá; "
                          "lệnh BÁN ngược lại, và cách giá đủ xa theo sàn")
        hint = RETCODE_HINTS.get(result.retcode)
        return None, f"MT5 từ chối ({result.retcode}): {hint or result.comment}"
    return result, None


# What MT5's refusals mean and what to do (other brokers and prop accounts hit these more than Exness).
RETCODE_HINTS = {
    10004: "giá đã đổi (requote), bấm lại",
    10006: "sàn từ chối lệnh",
    10013: "lệnh không hợp lệ",
    10014: "khối lượng không hợp lệ: kiểm tra lot tối thiểu / bước lot của mã này",
    10015: "giá không hợp lệ",
    10017: "mã này đang bị khoá giao dịch trên tài khoản (sàn tắt giao dịch mã này)",
    10018: "thị trường đang đóng cửa",
    10019: "không đủ tiền ký quỹ (margin): giảm lot",
    10020: "giá thay đổi, bấm lại",
    10021: "chưa có giá để khớp, thử lại",
    10024: "gửi lệnh quá nhanh, đợi một chút",
    10026: "SÀN tắt giao dịch tự động (EA / API) trên tài khoản này: không đặt lệnh qua app / web được, chỉ đặt tay trong MT5 — hỏi sàn / quỹ có cho EA không",
    10027: "nút Algo Trading trong MT5 trên VPS đang TẮT: mở MT5 trên VPS, bật Algo Trading (nút trên thanh công cụ) rồi đặt lại",
    10028: "lệnh đang bị khoá để xử lý",
    10029: "lệnh hoặc vị thế bị khoá",
    10031: "MT5 mất kết nối tới máy chủ sàn",
    10033: "đã đạt số lệnh chờ tối đa của tài khoản",
    10034: "đã đạt khối lượng tối đa cho mã này",
    10040: "đã đạt số lệnh mở tối đa của tài khoản",
    10042: "mã này chỉ cho MUA",
    10043: "mã này chỉ cho BÁN",
    10044: "mã này chỉ cho đóng lệnh đang có, không cho mở lệnh mới",
    10045: "sàn bắt đóng lệnh theo thứ tự FIFO",
    10046: "tài khoản không cho mở lệnh ngược chiều (hedge)",
}


def check_stops(mt5, symbol, info, long, stop, target):
    """SL/TP of an open position against the price it would close at, with a clear
    message instead of MT5's bare 10016 "Invalid stops"."""
    tick = mt5.symbol_info_tick(symbol)
    if tick is None or info is None:
        return
    price = tick.bid if long else tick.ask
    gap = (getattr(info, "trade_stops_level", 0) or 0) * (getattr(info, "point", 0) or 0)
    d = info.digits
    if stop:
        if long and stop >= price - gap:
            raise ValueError(f"SL của lệnh MUA phải thấp hơn giá hiện tại {price:.{d}f}" + (f" ít nhất {gap:.{d}f}" if gap else ""))
        if not long and stop <= price + gap:
            raise ValueError(f"SL của lệnh BÁN phải cao hơn giá hiện tại {price:.{d}f}" + (f" ít nhất {gap:.{d}f}" if gap else ""))
    if target:
        if long and target <= price + gap:
            raise ValueError(f"TP của lệnh MUA phải cao hơn giá hiện tại {price:.{d}f}" + (f" ít nhất {gap:.{d}f}" if gap else ""))
        if not long and target >= price - gap:
            raise ValueError(f"TP của lệnh BÁN phải thấp hơn giá hiện tại {price:.{d}f}" + (f" ít nhất {gap:.{d}f}" if gap else ""))


# Orders placed by hand from the app; the bot only manages its own magic number.
APP_MAGIC = 20261


class TickHub:
    """The MT5 bid / ask of the symbols someone is watching, read every 50 ms and pushed at once to every
    open stream (/mt5/ticks, /member/ticks): the app and the website see each tick, not a poll every 2 s."""

    def __init__(self, account):
        self.account = account
        self.cond = threading.Condition()
        self.latest = {}    # symbol -> {"seq", "bid", "ask", "time"}
        self.watchers = {}  # symbol -> open streams
        self.seq = 0
        self.thread = None
        self.next_connect = 0
        self.listeners = []

    def add_listener(self, fn):
        """fn(symbol, bid, ask) on every new tick, called outside the MT5 lock."""
        self.listeners.append(fn)

    def watch(self, symbol):
        with self.cond:
            self.watchers[symbol] = self.watchers.get(symbol, 0) + 1
            if self.thread is None:
                self.thread = threading.Thread(target=self._loop, daemon=True)
                self.thread.start()

    def unwatch(self, symbol):
        with self.cond:
            self.watchers[symbol] = max(0, self.watchers.get(symbol, 0) - 1)

    def wait(self, symbol, seq, timeout):
        """The symbol's newest tick once it is newer than `seq`, or None after `timeout` seconds."""
        with self.cond:
            self.cond.wait_for(lambda: (self.latest.get(symbol) or {}).get("seq", 0) > seq, timeout)
            tick = self.latest.get(symbol)
            return tick if tick and tick["seq"] > seq else None

    def _loop(self):
        while True:
            with self.cond:
                symbols = [s for s, n in self.watchers.items() if n > 0]
            if not symbols or (not Mt5.connected and now() < self.next_connect):
                time.sleep(0.2)
                continue
            fresh = {}
            if Mt5.lock.acquire(timeout=1):
                try:
                    mt5 = self.account._mt5()
                    offset = Mt5.offset_seconds
                    for symbol in symbols:
                        own = Mt5.find_symbol(mt5, symbol) or symbol
                        t = mt5.symbol_info_tick(own)
                        if t is None:
                            mt5.symbol_select(own, True)
                            continue
                        key = (getattr(t, "time_msc", 0) or t.time, t.bid, t.ask)
                        old = self.latest.get(symbol)
                        if old is None or old.get("key") != key:
                            stamp = (getattr(t, "time_msc", 0) or t.time * 1000) / 1000.0
                            fresh[symbol] = {"key": key, "bid": t.bid, "ask": t.ask, "time": stamp - offset}
                except Exception:  # MT5 not logged in yet: try again in a few seconds
                    self.next_connect = now() + 5
                finally:
                    Mt5.lock.release()
            if fresh:
                with self.cond:
                    for symbol, tick in fresh.items():
                        self.seq += 1
                        tick["seq"] = self.seq
                        self.latest[symbol] = tick
                    self.cond.notify_all()
                for symbol, tick in fresh.items():
                    for fn in list(self.listeners):
                        try:
                            fn(symbol, tick["bid"], tick["ask"])
                        except Exception:  # a listener must not stop the ticks
                            pass
            time.sleep(0.05)


class Mt5Account:
    """MT5 login and market data for the app (Live chart source "MT5 (VPS)").

    Every call holds Mt5.lock: the MetaTrader5 package is one connection per
    process and the bot loop uses it too."""

    def __init__(self, server):
        self.server = server
        self.ticks = TickHub(self)
        self.stops = read_json(STOPS_PATH, {})
        if not isinstance(self.stops, dict):
            self.stops = {}
        threading.Thread(target=self._watch_stops, daemon=True).start()

    def _watch_stops(self):
        """Every few seconds while MT5 is connected: the SL / TP of the open positions, so a level dragged
        in MT5 itself (or while no app is open) is still known when the position closes."""
        while True:
            time.sleep(5)
            if not Mt5.connected or Mt5.module is None or not Mt5.lock.acquire(timeout=2):
                continue
            try:
                self._track_stops(Mt5.module.positions_get() or ())
            except Exception:  # never stop the server for this
                pass
            finally:
                Mt5.lock.release()

    @property
    def cfg(self):
        return self.server.config["mt5"]

    def _mt5(self):
        return Mt5.connect(self.cfg)

    def _track_stops(self, rows, when=None):
        """Remembers each open position's SL / TP: the first one set and the last one, with when it was
        last moved (MT5's history has neither once the position is closed)."""
        changed = False
        stamp = when or now()
        for r in rows:
            key = str(int(r.ticket))
            sl, tp = float(r.sl or 0), float(r.tp or 0)
            rec = self.stops.get(key)
            if rec is None:
                rec = self.stops[key] = {"sl0": sl or None, "tp0": tp or None, "sl": sl or None, "tp": tp or None,
                                         "slAt": None, "tpAt": None, "seen": stamp}
                changed = True
                continue
            rec["seen"] = stamp
            for k, v in (("sl", sl), ("tp", tp)):
                if (rec.get(k) or 0) != v:
                    if not rec.get(k + "0") and v:
                        rec[k + "0"] = v  # set for the first time after opening
                    elif rec.get(k) is not None or v:
                        rec[k + "At"] = stamp
                    rec[k] = v or None
                    changed = True
        if changed:
            # Positions closed more than 120 days ago are forgotten.
            old = stamp - 120 * 86400
            self.stops = {k: v for k, v in self.stops.items() if (v.get("seen") or 0) >= old}
            try:
                write_json(STOPS_PATH, self.stops)
            except OSError:
                pass

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
        if not password:
            raise ValueError("Cần mật khẩu MT5 (mật khẩu chính)")
        # The servers to try: the one typed (and without its spaces: "EZSquare Server" → "EZSquare-Server"),
        # or, left empty, the ones this account / the saved accounts used, the current one and the known ones.
        if server:
            candidates = [server] + ([re.sub(r"\s+", "-", server)] if re.search(r"\s", server) else [])
        else:
            candidates = self._server_candidates(login)
        s = self.server.settings
        if s.get("running") and s.get("broker") == "mt5" and int(self.cfg.get("login") or 0) != login:
            raise ValueError("Bot đang đặt lệnh trên tài khoản MT5 hiện tại: dừng bot trước khi đổi tài khoản")
        with Mt5.lock:
            if body.get("path"):
                self.cfg["path"] = str(body["path"])
            hint = (" Server phải viết đúng như trong MT5 (vd EZSquare-Server, Exness-MT5Trial7: có gạch nối, không có dấu cách)."
                    " Sàn khác Exness: MT5 trên VPS phải tìm được server đó trước (Tệp → Mở tài khoản → tìm tên sàn).")
            if not (Mt5.module is not None and Mt5.connected and Mt5.module.terminal_info() is not None):
                # Start the terminal (with the remembered account, else as it is), then log in below.
                Mt5.connected = False
                try:
                    Mt5.connect(self.cfg)
                except RuntimeError:
                    try:
                        Mt5.connect({"path": self.cfg.get("path", "")})
                    except RuntimeError as e:
                        raise ValueError(str(e))
            mt5 = Mt5.module
            ok = False
            for srv in candidates:
                if mt5.login(login, password=password, server=srv):
                    ok, server = True, srv
                    break
            if not ok:
                tried = f" (đã thử: {', '.join(candidates)})" if not str(body.get("server", "")).strip() else ""
                raise ValueError(f"Đăng nhập thất bại ({mt5.last_error()}){tried}. Kiểm tra số tài khoản, mật khẩu (mật khẩu chính), server.{hint}")
            cfg = dict(self.cfg, login=login, password=password, server=server)
            if body.get("remember", True):
                self.cfg.update(login=login, password=password, server=server)
                a = mt5.account_info()
                mode = ({mt5.ACCOUNT_TRADE_MODE_DEMO: "demo", mt5.ACCOUNT_TRADE_MODE_REAL: "real"}.get(a.trade_mode, "contest")) if a else ""
                self._keep_account(login, server, password, body.get("broker") or (a.company if a else ""), a.name if a else "", mode)
                if body.get("path"):
                    self.cfg["path"] = str(body["path"])
            else:
                self.cfg.update(login=0, password="", server="")
            self.server.save_config()
            if not ensure_algo_trading(mt5, cfg, self.server.log):
                self.server.log("⚠️ Algo Trading trong MT5 đang tắt: bật nút Algo Trading trên VPS để đặt lệnh")
        self.server.log(f"🔑 Đăng nhập MT5 #{login} ({server})")
        return self.status()

    # Servers worth trying when none is typed (the MT5 on the VPS must know them).
    KNOWN_SERVERS = ("EZSquare-Server",)

    def _server_candidates(self, login):
        acc = self._accounts()
        out = [a.get("server") for a in acc if int(a.get("login") or 0) == int(login)]
        out += [self.cfg.get("server")] + [a.get("server") for a in acc] + list(self.KNOWN_SERVERS)
        seen, uniq = set(), []
        for x in out:
            if x and x not in seen:
                seen.add(x); uniq.append(x)
        return uniq[:8]

    # ----- Saved accounts, shared by the app and the web (passwords stay on this VPS) -----

    def _accounts(self):
        acc = self.cfg.get("accounts")
        if not isinstance(acc, list):
            acc = self.cfg["accounts"] = []
        return acc

    def _keep_account(self, login, server, password, broker="", name="", mode=""):
        acc = [a for a in self._accounts() if not (int(a.get("login") or 0) == int(login) and a.get("server") == server)]
        old = next((a for a in self._accounts() if int(a.get("login") or 0) == int(login) and a.get("server") == server), {})
        acc.insert(0, {"login": int(login), "server": server, "password": password or old.get("password", ""),
                       "broker": broker or old.get("broker", ""), "name": name or old.get("name", ""), "mode": mode or old.get("mode", "")})
        self.cfg["accounts"] = acc[:20]
        self.server.save_config()

    def accounts(self):
        """The saved accounts (no passwords), the one logged in first."""
        cur = (int(self.cfg.get("login") or 0), self.cfg.get("server") or "")
        rows = [{"login": int(a.get("login") or 0), "server": a.get("server", ""), "broker": a.get("broker", ""), "name": a.get("name", ""), "mode": a.get("mode", ""),
                 "hasPassword": bool(a.get("password")), "current": (int(a.get("login") or 0), a.get("server", "")) == cur}
                for a in self._accounts()]
        rows.sort(key=lambda r: not r["current"])
        return {"ok": True, "accounts": rows}

    def remember(self, body):
        """Keep an account (from the app's own list) without logging into it."""
        try:
            login = int(str(body.get("login", "")).strip())
        except ValueError:
            raise ValueError("Số tài khoản MT5 phải là số")
        server = str(body.get("server", "")).strip()
        if not server:
            raise ValueError("Cần tên máy chủ (server) MT5")
        self._keep_account(login, server, str(body.get("password", "")), str(body.get("broker", "")))
        return self.accounts()

    def switch(self, body):
        """Log into a saved account with its saved password (or the one given)."""
        login, server = int(str(body.get("login", "0")).strip() or 0), str(body.get("server", "")).strip()
        a = next((x for x in self._accounts() if int(x.get("login") or 0) == login and x.get("server") == server), None)
        password = str(body.get("password") or (a or {}).get("password") or "")
        if not password:
            raise ValueError("Tài khoản này chưa lưu mật khẩu trên VPS: nhập mật khẩu")
        return self.login({"login": login, "server": server, "password": password, "remember": True, "broker": (a or {}).get("broker", "")})

    def forget(self, body):
        login, server = int(str(body.get("login", "0")).strip() or 0), str(body.get("server", "")).strip()
        self.cfg["accounts"] = [a for a in self._accounts() if not (int(a.get("login") or 0) == login and a.get("server") == server)]
        self.server.save_config()
        return self.accounts()

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
        if hasattr(a, "trade_expert") and not a.trade_expert:
            raise ValueError("Sàn / quỹ tắt giao dịch tự động (EA / API) trên tài khoản này: app / web không đặt lệnh được, "
                             "chỉ đặt tay trong MT5. Hỏi sàn / quỹ có cho EA không.")
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
                self.cfg["max_lots"] = max(0.01, min(float(body["max_lots"]), 200.0))
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
            rows = (mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()) or ()
            self._track_stops(rows)
            for r in rows:
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
            symbol = Mt5.need_symbol(mt5, symbol)
            info = mt5.symbol_info(symbol)
            tick = mt5.symbol_info_tick(symbol)
            volume = self._volume(mt5, info, float(body.get("lots", 0.01)))
            buy = side == "long"
            request = {"symbol": symbol, "volume": volume, "magic": APP_MAGIC, "comment": "GoldApp",
                       "deviation": int(self.cfg.get("deviation", 30)), "type_time": mt5.ORDER_TIME_GTC}
            if kind == "market":
                request.update(action=mt5.TRADE_ACTION_DEAL, type=mt5.ORDER_TYPE_BUY if buy else mt5.ORDER_TYPE_SELL,
                               price=tick.ask if buy else tick.bid)
            else:
                price = on_tick(info, body["price"])
                below = price < (tick.ask if buy else tick.bid)
                # Buy below / sell above the market = limit, otherwise stop.
                order_type = (mt5.ORDER_TYPE_BUY_LIMIT if below else mt5.ORDER_TYPE_BUY_STOP) if buy else \
                    (mt5.ORDER_TYPE_SELL_STOP if below else mt5.ORDER_TYPE_SELL_LIMIT)
                request.update(action=mt5.TRADE_ACTION_PENDING, type=order_type, price=price)
            if body.get("stop"):
                request["sl"] = on_tick(info, body["stop"])
            if body.get("target"):
                request["tp"] = on_tick(info, body["target"])
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
            buy = r.type == mt5.POSITION_TYPE_BUY
            volume = float(body.get("lots") or r.volume)
            # A requote or a busy moment: up to 3 tries, each at a fresh price with more room for slippage.
            for attempt in range(3):
                tick = mt5.symbol_info_tick(r.symbol)
                request = {"action": mt5.TRADE_ACTION_DEAL, "symbol": r.symbol, "volume": min(volume, r.volume),
                           "type": mt5.ORDER_TYPE_SELL if buy else mt5.ORDER_TYPE_BUY, "position": r.ticket,
                           "price": tick.bid if buy else tick.ask,
                           "deviation": int(self.cfg.get("deviation", 30)) * (attempt + 1),
                           "magic": r.magic, "comment": "GoldApp close", "type_time": mt5.ORDER_TIME_GTC}
                _, error = mt5_send(mt5, request)
                if not error or not (mt5.positions_get(ticket=ticket) or ()):
                    error = None
                    break
                time.sleep(0.3)
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
                check_stops(mt5, r.symbol, info, r.type == mt5.POSITION_TYPE_BUY,
                            float(body["stop"]) if body.get("stop") else None,
                            float(body["target"]) if body.get("target") else None)
                request = {"action": mt5.TRADE_ACTION_SLTP, "symbol": r.symbol, "position": r.ticket,
                           "sl": on_tick(info, body["stop"]) if body.get("stop") else 0.0,
                           "tp": on_tick(info, body["target"]) if body.get("target") else 0.0}
            else:
                orders = mt5.orders_get(ticket=ticket) or ()
                if not orders:
                    raise ValueError("Không còn lệnh này")
                o = orders[0]
                info = mt5.symbol_info(o.symbol)
                price = float(body.get("price") or o.price_open)
                request = {"action": mt5.TRADE_ACTION_MODIFY, "symbol": o.symbol, "order": o.ticket,
                           "price": on_tick(info, price), "type_time": mt5.ORDER_TIME_GTC,
                           "sl": on_tick(info, body["stop"]) if body.get("stop") else 0.0,
                           "tp": on_tick(info, body["target"]) if body.get("target") else 0.0}
            _, error = mt5_send(mt5, request)
            if error:
                raise ValueError(error)
            if rows:
                self._track_stops(mt5.positions_get(ticket=ticket) or ())
        return self.trading()

    def close_all(self, body):
        """Closes every open position (of one symbol, or the tickets given) on the server, trying again
        those the broker turned down (requote, busy…) with a fresh price, up to 3 rounds."""
        symbol = str(body.get("symbol") or "") or None
        wanted = {int(t) for t in (body.get("tickets") or [])}
        closed, errors = 0, {}
        with Mt5.lock:
            mt5 = self._mt5()
            self._check_trading(mt5)
            for attempt in range(3):
                rows = [r for r in ((mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()) or ())
                        if not wanted or int(r.ticket) in wanted]
                if not rows:
                    break
                for r in rows:
                    tick = mt5.symbol_info_tick(r.symbol)
                    if tick is None:
                        errors[int(r.ticket)] = "không có giá"
                        continue
                    buy = r.type == mt5.POSITION_TYPE_BUY
                    request = {"action": mt5.TRADE_ACTION_DEAL, "symbol": r.symbol, "volume": r.volume,
                               "type": mt5.ORDER_TYPE_SELL if buy else mt5.ORDER_TYPE_BUY, "position": r.ticket,
                               "price": tick.bid if buy else tick.ask,
                               "deviation": int(self.cfg.get("deviation", 30)) * (attempt + 1),
                               "magic": r.magic, "comment": "GoldApp close all", "type_time": mt5.ORDER_TIME_GTC}
                    _, error = mt5_send(mt5, request)
                    if error:
                        errors[int(r.ticket)] = error
                    else:
                        closed += 1
                        errors.pop(int(r.ticket), None)
                time.sleep(0.4)
            left = [r for r in ((mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()) or ())
                    if not wanted or int(r.ticket) in wanted]
        self.server.log(f"📱 Đóng tất cả MT5: {closed} lệnh" + (f", còn {len(left)} lệnh chưa đóng được" if left else ""),
                        notify=True)
        out = self.trading()
        out.update(closed=closed, left=len(left),
                   error="; ".join(f"#{k}: {v}" for k, v in errors.items() if any(int(r.ticket) == k for r in left)) or None)
        return out

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
                # As seen while it was open (set or dragged from the app, the web or MT5 itself).
                seen = self.stops.get(str(pid)) or {}
                if not (fired and fired.group(1) == "sl"):
                    stop = stop or seen.get("sl") or 0
                if not (fired and fired.group(1) == "tp"):
                    target = target or seen.get("tp") or 0
                stop_open = stop_open or seen.get("sl0") or 0
                target_open = target_open or seen.get("tp0") or 0
                positions.append({"ticket": pid, "symbol": first.symbol,
                                  "side": "long" if first.type == mt5.DEAL_TYPE_BUY else "short",
                                  "lots": lots, "entry": first.price, "exit": exit_price,
                                  "openTime": float(first.time) - offset, "closeTime": float(outs[-1].time) - offset,
                                  "profit": sum(r.profit + r.swap + r.commission + (getattr(r, "fee", 0) or 0) for r in rows),
                                  "reason": reason, "stop": stop or None, "target": target or None,
                                  "stopOpen": stop_open or None, "targetOpen": target_open or None,
                                  "stopMovedAt": seen.get("slAt"), "targetMovedAt": seen.get("tpAt"),
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

    def ticks(self, symbol, start, end):
        """Real bid / ask ticks between two times (UTC seconds, at most 6 hours a call): [[ms, bid, ask], …],
        for the tick bot's backtest."""
        import datetime
        start, end = float(start), float(end)
        if end <= start:
            raise ValueError("Khoảng thời gian không hợp lệ")
        end = min(end, start + 6 * 3600)
        with Mt5.lock:
            mt5 = self._mt5()
            symbol = Mt5.need_symbol(mt5, symbol)
            offset = Mt5.detect_offset(symbol)
            utc = datetime.timezone.utc
            rows = mt5.copy_ticks_range(symbol, datetime.datetime.fromtimestamp(start + offset, tz=utc),
                                        datetime.datetime.fromtimestamp(end + offset, tz=utc), mt5.COPY_TICKS_INFO)
            info = mt5.symbol_info(symbol)
        out, last = [], None
        for r in rows if rows is not None else ():
            bid, ask = float(r["bid"]), float(r["ask"])
            if not bid or not ask or (bid, ask) == last:
                continue
            last = (bid, ask)
            out.append([int(r["time_msc"]) - int(offset * 1000), bid, ask])
        return {"ok": True, "symbol": symbol, "digits": getattr(info, "digits", 2), "from": start, "to": end, "ticks": out}

    def candles(self, symbol, interval, count, before=None):
        if interval not in MT5_TIMEFRAMES:
            raise ValueError("MT5 có khung 1m, 2m, 3m, 4m, 5m, 6m, 10m, 12m, 15m, 20m, 30m, 1h, 4h, 1d, 1w (không có khung giây)")
        count = max(1, min(int(count), 5000))
        with Mt5.lock:
            mt5 = self._mt5()
            symbol = Mt5.need_symbol(mt5, symbol)
            timeframe = getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[interval])
            offset = Mt5.detect_offset(symbol)
            if before:
                import datetime
                # Bars that opened before `before` (app time = UTC), in server time.
                start = datetime.datetime.fromtimestamp(float(before) + offset - 1, tz=datetime.timezone.utc)
                rates = mt5.copy_rates_from(symbol, timeframe, start, count)
            else:
                rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, count)
            # A symbol just added to Market Watch has no history until the terminal fetches it.
            for _ in range(6):
                if rates is not None and len(rates):
                    break
                time.sleep(0.5)
                rates = (mt5.copy_rates_from(symbol, timeframe, start, count) if before
                         else mt5.copy_rates_from_pos(symbol, timeframe, 0, count))
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
                    # Units per lot (gold 100, oil 1000 at Exness…): the web works out SL/TP money with it.
                    "contractSize": info.trade_contract_size if info else None,
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


# The usual SMT pair of a market (the second chart of the members' web): gold ⇄ silver, Nasdaq / Dow → S&P 500,
# S&P 500 → Nasdaq, BTC ⇄ ETH, EUR ⇄ GBP, AUD ⇄ NZD, WTI ⇄ Brent. The account's own name is found by find_symbol.
SMT_PAIRS = {"XAUUSD": "XAGUSD", "XAGUSD": "XAUUSD", "GOLD": "SILVER", "SILVER": "GOLD",
             "USTEC": "US500", "NAS100": "SPX500", "US100": "US500", "NDX100": "SPX500",
             "US500": "USTEC", "SPX500": "NAS100", "SP500": "NAS100",
             "US30": "US500", "DJ30": "SPX500", "WS30": "SPX500", "DOW30": "SPX500",
             "BTCUSD": "ETHUSD", "ETHUSD": "BTCUSD", "EURUSD": "GBPUSD", "GBPUSD": "EURUSD",
             "AUDUSD": "NZDUSD", "NZDUSD": "AUDUSD", "USOIL": "UKOIL", "UKOIL": "USOIL",
             "XTIUSD": "XBRUSD", "XBRUSD": "XTIUSD", "WTI": "BRENT", "BRENT": "WTI"}


def smt_pair(symbol):
    """XAUUSDm → XAGUSDm, USTEC → US500 (prefix / suffix kept); the symbol itself when it has no pair."""
    m = re.match(r"([#.]?)([A-Z0-9]+)(.*)$", symbol or "")
    if not m or m.group(2) not in SMT_PAIRS:
        return symbol
    return m.group(1) + SMT_PAIRS[m.group(2)] + m.group(3)


DRAWINGS_PATH = os.path.join(HERE, "drawings.json")
_drawings_lock = threading.Lock()


def drawings_get(symbol):
    """The chart drawings of a market shared by the web and the app (the web's format), by its base name."""
    key = base_symbol(symbol or "XAUUSD")
    with _drawings_lock:
        entry = read_json(DRAWINGS_PATH, {}).get(key) or {}
    return {"ok": True, "symbol": key, "updated": entry.get("updated", 0), "drawings": entry.get("drawings", [])}


def drawings_save(body):
    """Stores a market's drawings when they are newer than the stored ones; answers what is stored."""
    key = base_symbol(str(body.get("symbol") or "XAUUSD"))
    items = body.get("drawings")
    if not isinstance(items, list) or len(items) > 1000:
        raise ValueError("Danh sách bản vẽ không hợp lệ")
    updated = float(body.get("updated") or time.time())
    with _drawings_lock:
        data = read_json(DRAWINGS_PATH, {})
        entry = data.get(key) or {}
        if updated >= float(entry.get("updated", 0)):
            entry = {"updated": updated, "drawings": items}
            data[key] = entry
            write_json(DRAWINGS_PATH, data)
    return {"ok": True, "symbol": key, "updated": entry.get("updated", 0), "drawings": entry.get("drawings", [])}


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
        flag = own("update.flag")
        try:
            fresh = now() - os.path.getmtime(flag) < 300
            os.remove(flag)
            pid = int(open(own("tunnel.pid")).read().strip())
            url = open(own("tunnel.txt"), encoding="utf-8").read().strip()
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
                with open(own("tunnel.pid"), "w") as f:
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
    if INSTANCE:
        return  # the main server's address is the one the app and the website look up
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


# Why a bot closed a position, as a short code in the closing order's comment on MT5 (comments are short, ASCII
# is safest), read back by magic_history.
CLOSE_CODES = {"tránh giờ mạnh": "guard", "chốt rổ": "tp", "trailing": "trail", "SL rổ": "sl", "cắt lỗ chung": "stop", "tín hiệu ngược": "flip",
               "chốt lời": "tp1", "cắt lỗ lệnh": "sl1", "nến đảo chiều": "rev", "hết nến": "bar", "hết giờ giữ": "hold"}
CLOSE_REASONS = {v: k for k, v in CLOSE_CODES.items()}


def deal_reason(mt5, d):
    """Why an MT5 deal closed a position: the broker's SL / TP / stop out, else the bot's code in its comment."""
    r = getattr(d, "reason", None)
    if r is not None and r == getattr(mt5, "DEAL_REASON_SL", -1):
        return "SL trên sàn"
    if r is not None and r == getattr(mt5, "DEAL_REASON_TP", -1):
        return "TP trên sàn"
    if r is not None and r == getattr(mt5, "DEAL_REASON_SO", -1):
        return "cháy (stop out)"
    code = (getattr(d, "comment", "") or "").split(" ")[-1]
    return CLOSE_REASONS.get(code)


def magic_history(mt5, magic, since, limit=200):
    """A bot's closed trades on MT5 (its magic number), newest first: side, entry → exit, times (UTC), profit."""
    deals = mt5.history_deals_get(since + Mt5.offset_seconds - 60, now() + Mt5.offset_seconds + 86400) or ()
    opened, out = {}, []
    for d in deals:
        if getattr(d, "magic", 0) == magic and d.entry == mt5.DEAL_ENTRY_IN:
            opened[d.position_id] = d
    for d in deals:
        if getattr(d, "magic", 0) != magic or d.entry != mt5.DEAL_ENTRY_OUT:
            continue
        i = opened.get(d.position_id)
        out.append({"symbol": d.symbol, "side": "long" if d.type == mt5.DEAL_TYPE_SELL else "short", "lots": d.volume,
                    "entry": i.price if i else None, "openTime": float(i.time) - Mt5.offset_seconds if i else None,
                    "exit": d.price, "closeTime": float(d.time) - Mt5.offset_seconds, "reason": deal_reason(mt5, d),
                    "profit": round(d.profit + d.commission + d.swap + (getattr(d, "fee", 0) or 0), 2)})
    out.sort(key=lambda x: x["closeTime"], reverse=True)
    return out[:limit]


STOP_MAGIC = 20263
DEFAULT_STOPBOT = {"running": False, "symbol": "", "interval": "1m", "direction": "both", "offset": 0.0,
                   "stopMode": "candle", "stopDistance": 5.0, "rr": 2.0, "lots": 0.01, "minRange": 0.0,
                   "maxRange": 0.0, "oco": True, "onePosition": True}


class StopBot:
    """"Stop theo nến" on the MT5 account (the app's CandleStopBot): after each closed
    candle a buy stop above its high and a sell stop below its low, SL on the other side
    of the candle (or a fixed distance), TP = rr × risk. Unfilled orders live one candle;
    when one side fills the other is cancelled (OCO). Runs on the server, so it keeps
    going when the website or app is closed."""

    def __init__(self, server):
        self.server = server
        self.lock = threading.RLock()
        self.events = []
        self.last_bar = None
        self.known = set()     # positions of the bot already seen
        self.error = ""
        self.started = None
        threading.Thread(target=self._loop, daemon=True).start()

    @property
    def cfg(self):
        c = self.server.config.setdefault("stopbot", {})
        for k, v in DEFAULT_STOPBOT.items():
            c.setdefault(k, v)
        return c

    def event(self, text, notify=False):
        with self.lock:
            self.events.insert(0, {"time": now(), "text": text})
            del self.events[80:]
        self.server.log("🎯 Bot Stop: " + text, notify=notify)

    def settings(self, body):
        c = self.cfg
        for key, cast in (("symbol", str), ("interval", str), ("direction", str), ("offset", float), ("stopMode", str),
                          ("stopDistance", float), ("rr", float), ("lots", float), ("minRange", float), ("maxRange", float),
                          ("oco", bool), ("onePosition", bool)):
            if key in body:
                c[key] = cast(body[key])
        if c["interval"] not in MT5_TIMEFRAMES or c["interval"] == "1w":
            raise ValueError("Khung không hợp lệ")
        if c["direction"] not in ("both", "long", "short") or c["stopMode"] not in ("candle", "fixed"):
            raise ValueError("Cài đặt không hợp lệ")
        c["lots"] = max(0.01, c["lots"])
        if "running" in body:
            on = bool(body["running"])
            if on and not c["symbol"]:
                raise ValueError("Chưa chọn mã")
            if on and not c["running"]:
                self.last_bar, self.known, self.error, self.started = None, set(), "", now()
                self.event(f"BẬT · {c['symbol']} {c['interval']} · {c['lots']} lot · R:R {c['rr']}", notify=True)
            if not on and c["running"]:
                self.event("TẮT, huỷ lệnh chờ của bot", notify=True)
                try:
                    with Mt5.lock:
                        self._cancel_all(Mt5.connect(self.server.config["mt5"]))
                except Exception as e:
                    self.event(f"không huỷ được lệnh chờ: {e}")
            c["running"] = on
        self.server.save_config()
        return self.status()

    def orders_for(self, bar):
        """The two orders after a closed bar {open, high, low, close} (CandleStopBot.orders)."""
        c = self.cfg
        rng = bar["high"] - bar["low"]
        if rng <= 0 or rng < c["minRange"] or (c["maxRange"] > 0 and rng > c["maxRange"]):
            return []
        off, out = max(c["offset"], 0.0), []
        if c["direction"] != "short":
            entry = bar["high"] + off
            stop = bar["low"] - off if c["stopMode"] == "candle" else entry - max(c["stopDistance"], 0)
            if entry > stop:
                out.append(("long", entry, stop, entry + c["rr"] * (entry - stop) if c["rr"] > 0 else None))
        if c["direction"] != "long":
            entry = bar["low"] - off
            stop = bar["high"] + off if c["stopMode"] == "candle" else entry + max(c["stopDistance"], 0)
            if stop > entry:
                out.append(("short", entry, stop, entry - c["rr"] * (stop - entry) if c["rr"] > 0 else None))
        return out

    def _mine(self, rows):
        return [r for r in rows or () if getattr(r, "magic", 0) == STOP_MAGIC]

    def _cancel_all(self, mt5):
        for o in self._mine(mt5.orders_get(symbol=self.cfg["symbol"])):
            mt5_send(mt5, {"action": mt5.TRADE_ACTION_REMOVE, "order": o.ticket, "symbol": o.symbol})

    def _loop(self):
        while True:
            time.sleep(1.5)
            if not self.cfg["running"]:
                continue
            try:
                with Mt5.lock:
                    self._tick()
                self.error = ""
            except Exception as e:
                if str(e) != self.error:
                    self.event(f"lỗi: {e}")
                self.error = str(e)

    def _tick(self):
        c = self.cfg
        mt5 = Mt5.connect(self.server.config["mt5"])
        self.server.mt5_account._check_trading(mt5)
        symbol = Mt5.need_symbol(mt5, c["symbol"])
        info = mt5.symbol_info(symbol)
        positions = self._mine(mt5.positions_get(symbol=symbol))
        orders = self._mine(mt5.orders_get(symbol=symbol))
        # A side filled: note it and cancel the other side (OCO).
        tickets = {int(p.ticket) for p in positions}
        for p in positions:
            if int(p.ticket) not in self.known:
                self.event(f"khớp {'MUA' if p.type == mt5.POSITION_TYPE_BUY else 'BÁN'} {p.volume} @ {fmt(p.price_open)}", notify=True)
        for gone in self.known - tickets:
            self.event(f"lệnh #{gone} đã đóng")
        new_fill = bool(tickets - self.known)
        self.known = tickets
        if new_fill and c["oco"] and orders:
            self._cancel_all(mt5)
            orders = []
        timeframe = getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[c["interval"]])
        rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, 2)
        if rates is None or len(rates) < 2:
            return
        bar = rates[-2]  # the last closed candle
        bar_time = float(bar["time"])
        if self.last_bar is None:
            self.last_bar = bar_time  # start with the next close
            return
        if bar_time <= self.last_bar:
            return
        self.last_bar = bar_time
        # A new candle closed: last candle's unfilled orders go.
        if orders:
            self._cancel_all(mt5)
        if c["onePosition"] and positions:
            return
        tick = mt5.symbol_info_tick(symbol)
        gap = (getattr(info, "trade_stops_level", 0) or 0) * (getattr(info, "point", 0) or 0)
        volume = self.server.mt5_account._volume(mt5, info, float(c["lots"]))
        placed = []
        for side, entry, stop, target in self.orders_for({k: float(bar[k]) for k in ("open", "high", "low", "close")}):
            buy = side == "long"
            # A stop order must be beyond the market: skip a side price has already passed.
            if tick is not None and (entry <= tick.ask + gap if buy else entry >= tick.bid - gap):
                continue
            d = info.digits
            request = {"action": mt5.TRADE_ACTION_PENDING, "symbol": symbol, "volume": volume,
                       "type": mt5.ORDER_TYPE_BUY_STOP if buy else mt5.ORDER_TYPE_SELL_STOP,
                       "price": round(entry, d), "sl": round(stop, d), "tp": round(target, d) if target else 0.0,
                       "magic": STOP_MAGIC, "comment": "StopBot", "type_time": mt5.ORDER_TIME_GTC,
                       "deviation": int(self.server.config["mt5"].get("deviation", 30))}
            _, error = mt5_send(mt5, request)
            if error:
                self.event(f"không đặt được {'BUY' if buy else 'SELL'} STOP: {error}")
            else:
                placed.append(f"{'BUY' if buy else 'SELL'} STOP {fmt(entry)}")
        if placed:
            self.event("nến đóng → " + ", ".join(placed))

    def status(self):
        c = dict(self.cfg)
        history = []
        orders, positions, stats = [], [], {"trades": 0, "wins": 0, "profit": 0.0}
        try:
            with Mt5.lock:
                mt5 = Mt5.connect(self.server.config["mt5"])
                symbol = c["symbol"] or None
                for o in self._mine(mt5.orders_get(symbol=symbol) if symbol else mt5.orders_get()):
                    orders.append({"ticket": int(o.ticket), "symbol": o.symbol, "side": "long" if o.type == mt5.ORDER_TYPE_BUY_STOP else "short",
                                   "lots": o.volume_current, "entry": o.price_open, "stop": o.sl or None, "target": o.tp or None})
                for p in self._mine(mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()):
                    positions.append({"ticket": int(p.ticket), "symbol": p.symbol, "side": "long" if p.type == mt5.POSITION_TYPE_BUY else "short",
                                      "lots": p.volume, "entry": p.price_open, "stop": p.sl or None, "target": p.tp or None,
                                      "profit": p.profit + getattr(p, "swap", 0)})
                since = self.started or now() - 86400
                for d in mt5.history_deals_get(since + Mt5.offset_seconds - 60, now() + Mt5.offset_seconds + 86400) or ():
                    if getattr(d, "magic", 0) == STOP_MAGIC and d.entry == mt5.DEAL_ENTRY_OUT:
                        pnl = d.profit + d.commission + d.swap + (getattr(d, "fee", 0) or 0)
                        stats["trades"] += 1
                        stats["wins"] += 1 if pnl > 0 else 0
                        stats["profit"] += pnl
                history = magic_history(mt5, STOP_MAGIC, now() - 7 * 86400)
        except Exception as e:
            c["statusError"] = str(e)
        with self.lock:
            return {"ok": True, "config": c, "history": history, "orders": orders, "positions": positions, "stats": stats,
                    "events": self.events[:40], "error": self.error, "startedAt": self.started}


# --------------------------------------------------------------------------
# "Cản & Hỗ trợ" bot: support / resistance zones from the recent swing highs and
# lows (both kinds: an old resistance can hold as support), and an entry when a
# closed candle reacts at a zone (a rejection wick or an engulfing candle), SL
# beyond that candle, TP = rr × risk, then the SL trails each closed candle.
# The website's backtest (web/assets/app.js, srSignal / srBacktest) uses the
# same rules; keep the two in step.

SR_MAGIC = 20264
DEFAULT_SRBOT = {"running": False, "symbol": "", "interval": "1m", "direction": "both", "lots": 0.01,
                 "lookback": 300, "swing": 3, "zoneAtr": 0.3, "minTouches": 2, "wickRatio": 0.45,
                 "pattern": "both", "slBufferAtr": 0.1, "rr": 2.0, "trail": True, "trailStartR": 0.5}


def sr_atr(bars, i, n=14):
    """Average true range of the n bars ending at i (None before there are enough)."""
    if i < n:
        return None
    total = 0.0
    for j in range(i - n + 1, i + 1):
        b, prev = bars[j], bars[j - 1]
        total += max(b["high"] - b["low"], abs(b["high"] - prev["close"]), abs(b["low"] - prev["close"]))
    return total / n


def sr_levels(bars, i, cfg, atr):
    """Zones from the swing highs and lows confirmed before bar i: [(price, touches)]."""
    k = max(1, int(cfg["swing"]))
    start = max(k, i - int(cfg["lookback"]))
    prices = []
    for j in range(start, i - k):
        h, l = bars[j]["high"], bars[j]["low"]
        left = bars[j - k:j]
        right = bars[j + 1:j + k + 1]
        if all(h > b["high"] for b in left) and all(h >= b["high"] for b in right):
            prices.append(h)
        if all(l < b["low"] for b in left) and all(l <= b["low"] for b in right):
            prices.append(l)
    prices.sort()
    tol = atr * float(cfg["zoneAtr"])
    # A plain running sum (not sum(), which compensates rounding) so the website's backtest gets
    # exactly the same zones.
    levels, count, total = [], 0, 0.0
    for price in prices:
        if count and price - total / count > tol:
            levels.append((total / count, count))
            count, total = 0, 0.0
        count += 1
        total += price
    if count:
        levels.append((total / count, count))
    return [lv for lv in levels if lv[1] >= int(cfg["minTouches"])]


def sr_signal(bars, i, cfg):
    """The trade the closed bar i calls for: (side, level, stop) or None."""
    atr = sr_atr(bars, i)
    if not atr or i < 2:
        return None
    b, p = bars[i], bars[i - 1]
    rng = b["high"] - b["low"]
    if rng <= 0:
        return None
    body_lo, body_hi = min(b["open"], b["close"]), max(b["open"], b["close"])
    pattern = cfg["pattern"]
    wick = float(cfg["wickRatio"])
    bull_pin = (body_lo - b["low"]) / rng >= wick and (b["close"] - b["low"]) / rng >= 0.5
    bear_pin = (b["high"] - body_hi) / rng >= wick and (b["high"] - b["close"]) / rng >= 0.5
    bull_eng = b["close"] > b["open"] and p["close"] < p["open"] and b["close"] >= p["open"] and b["open"] <= p["close"]
    bear_eng = b["close"] < b["open"] and p["close"] > p["open"] and b["close"] <= p["open"] and b["open"] >= p["close"]
    bull = (pattern != "engulf" and bull_pin) or (pattern != "pin" and bull_eng)
    bear = (pattern != "engulf" and bear_pin) or (pattern != "pin" and bear_eng)
    if cfg["direction"] == "short":
        bull = False
    if cfg["direction"] == "long":
        bear = False
    if bull == bear:
        return None
    tol = atr * float(cfg["zoneAtr"])
    buffer = atr * float(cfg["slBufferAtr"])
    best = None
    for price, touches in sr_levels(bars, i, cfg, atr):
        if bull and b["low"] <= price + tol and b["low"] >= price - 2 * tol and b["close"] > price:
            key = (touches, -abs(b["low"] - price))
        elif bear and b["high"] >= price - tol and b["high"] <= price + 2 * tol and b["close"] < price:
            key = (touches, -abs(b["high"] - price))
        else:
            continue
        if best is None or key > best[0]:
            best = (key, price)
    if best is None:
        return None
    if bull:
        return ("long", best[1], b["low"] - buffer)
    return ("short", best[1], b["high"] + buffer)


def sr_trail(bars, i, cfg, side, entry, first_stop, stop):
    """The stop after closed bar i: behind that candle once price has moved trailStartR × risk."""
    if not cfg["trail"]:
        return stop
    atr = sr_atr(bars, i)
    if not atr:
        return stop
    b = bars[i]
    risk = abs(entry - first_stop)
    buffer = atr * float(cfg["slBufferAtr"])
    if side == "long":
        if b["close"] - entry < float(cfg["trailStartR"]) * risk:
            return stop
        candidate = b["low"] - buffer
        return candidate if candidate > stop and candidate < b["close"] else stop
    if entry - b["close"] < float(cfg["trailStartR"]) * risk:
        return stop
    candidate = b["high"] + buffer
    return candidate if candidate < stop and candidate > b["close"] else stop


class SRBot:
    """"Cản & Hỗ trợ" on the MT5 account, after every closed candle: trails the SL of
    its position, and when it has none, enters at market on a reaction at a zone."""

    def __init__(self, server):
        self.server = server
        self.lock = threading.RLock()
        self.events = []
        self.last_bar = None
        self.first_stop = {}   # ticket -> SL it opened with (the risk for trailStartR)
        self.known = set()
        self.error = ""
        self.started = None
        threading.Thread(target=self._loop, daemon=True).start()

    @property
    def cfg(self):
        c = self.server.config.setdefault("srbot", {})
        for k, v in DEFAULT_SRBOT.items():
            c.setdefault(k, v)
        return c

    def event(self, text, notify=False):
        with self.lock:
            self.events.insert(0, {"time": now(), "text": text})
            del self.events[80:]
        self.server.log("🧱 Bot Cản/Hỗ trợ: " + text, notify=notify)

    def settings(self, body):
        c = self.cfg
        for key, cast in (("symbol", str), ("interval", str), ("direction", str), ("lots", float), ("lookback", int),
                          ("swing", int), ("zoneAtr", float), ("minTouches", int), ("wickRatio", float), ("pattern", str),
                          ("slBufferAtr", float), ("rr", float), ("trail", bool), ("trailStartR", float)):
            if key in body:
                c[key] = cast(body[key])
        if c["interval"] not in MT5_TIMEFRAMES or c["interval"] == "1w":
            raise ValueError("Khung không hợp lệ")
        if c["direction"] not in ("both", "long", "short") or c["pattern"] not in ("both", "pin", "engulf"):
            raise ValueError("Cài đặt không hợp lệ")
        c["lots"] = max(0.01, c["lots"])
        c["lookback"] = max(30, min(c["lookback"], 2000))
        c["swing"] = max(1, min(c["swing"], 20))
        if "running" in body:
            on = bool(body["running"])
            if on and not c["symbol"]:
                raise ValueError("Chưa chọn mã")
            if on and not c["running"]:
                self.last_bar, self.known, self.error, self.started = None, set(), "", now()
                self.event(f"BẬT · {c['symbol']} {c['interval']} · {c['lots']} lot · R:R {c['rr']}", notify=True)
            if not on and c["running"]:
                self.event("TẮT (lệnh đang mở giữ nguyên)", notify=True)
            c["running"] = on
        self.server.save_config()
        return self.status()

    def _mine(self, rows):
        return [r for r in rows or () if getattr(r, "magic", 0) == SR_MAGIC]

    def _loop(self):
        while True:
            time.sleep(1.5)
            if not self.cfg["running"]:
                continue
            try:
                with Mt5.lock:
                    self._tick()
                self.error = ""
            except Exception as e:
                if str(e) != self.error:
                    self.event(f"lỗi: {e}")
                self.error = str(e)

    def _tick(self):
        c = self.cfg
        mt5 = Mt5.connect(self.server.config["mt5"])
        self.server.mt5_account._check_trading(mt5)
        symbol = Mt5.need_symbol(mt5, c["symbol"])
        info = mt5.symbol_info(symbol)
        positions = self._mine(mt5.positions_get(symbol=symbol))
        tickets = {int(p.ticket) for p in positions}
        for gone in self.known - tickets:
            self.event(f"lệnh #{gone} đã đóng")
            self.first_stop.pop(gone, None)
        self.known = tickets
        timeframe = getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[c["interval"]])
        rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, int(c["lookback"]) + 40)
        if rates is None or len(rates) < 30:
            return
        bar_time = float(rates[-2]["time"])  # the last closed candle
        if self.last_bar is None:
            self.last_bar = bar_time  # start with the next close
            return
        if bar_time <= self.last_bar:
            return
        self.last_bar = bar_time
        bars = [{k: float(r[k]) for k in ("open", "high", "low", "close")} for r in rates[:-1]]
        i = len(bars) - 1
        d = info.digits
        # Trail the SL of the bot's position behind the candle that just closed.
        for p in positions:
            long = p.type == mt5.POSITION_TYPE_BUY
            first = self.first_stop.setdefault(int(p.ticket), p.sl or 0.0)
            if not p.sl or not first:
                continue
            new = sr_trail(bars, i, c, "long" if long else "short", p.price_open, first, p.sl)
            if abs(new - p.sl) >= (getattr(info, "point", 0) or 0) and round(new, d) != round(p.sl, d):
                _, error = mt5_send(mt5, {"action": mt5.TRADE_ACTION_SLTP, "symbol": symbol, "position": p.ticket,
                                          "sl": round(new, d), "tp": p.tp or 0.0, "magic": SR_MAGIC})
                if error:
                    self.event(f"không dời được SL #{p.ticket}: {error}")
                else:
                    self.event(f"dời SL #{p.ticket} → {fmt(new)}")
        if positions:
            return
        signal = sr_signal(bars, i, c)
        if not signal:
            return
        side, level, stop = signal
        long = side == "long"
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            return
        price = tick.ask if long else tick.bid
        risk = price - stop if long else stop - price
        if risk <= 0:
            self.event(f"bỏ tín hiệu {'MUA' if long else 'BÁN'} tại {fmt(level)}: giá đã qua SL")
            return
        target = price + c["rr"] * risk if long else price - c["rr"] * risk
        volume = self.server.mt5_account._volume(mt5, info, float(c["lots"]))
        request = {"action": mt5.TRADE_ACTION_DEAL, "symbol": symbol, "volume": volume,
                   "type": mt5.ORDER_TYPE_BUY if long else mt5.ORDER_TYPE_SELL, "price": price,
                   "sl": round(stop, d), "tp": round(target, d) if c["rr"] > 0 else 0.0,
                   "magic": SR_MAGIC, "comment": "SRBot", "type_time": mt5.ORDER_TIME_GTC,
                   "deviation": int(self.server.config["mt5"].get("deviation", 30))}
        result, error = mt5_send(mt5, request)
        what = f"{'MUA' if long else 'BÁN'} {volume} @ {fmt(price)} (vùng {fmt(level)}, SL {fmt(stop)})"
        if error:
            self.event(f"không vào được {what}: {error}")
            return
        ticket = int(getattr(result, "order", 0) or 0)
        if ticket:
            self.first_stop[ticket] = round(stop, d)
            self.known.add(ticket)
        self.event(f"vào {what}", notify=True)

    def status(self):
        c = dict(self.cfg)
        history = []
        positions, stats = [], {"trades": 0, "wins": 0, "profit": 0.0}
        try:
            with Mt5.lock:
                mt5 = Mt5.connect(self.server.config["mt5"])
                symbol = c["symbol"] or None
                for p in self._mine(mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()):
                    positions.append({"ticket": int(p.ticket), "symbol": p.symbol, "side": "long" if p.type == mt5.POSITION_TYPE_BUY else "short",
                                      "lots": p.volume, "entry": p.price_open, "stop": p.sl or None, "target": p.tp or None,
                                      "profit": p.profit + getattr(p, "swap", 0)})
                since = self.started or now() - 86400
                for d in mt5.history_deals_get(since + Mt5.offset_seconds - 60, now() + Mt5.offset_seconds + 86400) or ():
                    if getattr(d, "magic", 0) == SR_MAGIC and d.entry == mt5.DEAL_ENTRY_OUT:
                        pnl = d.profit + d.commission + d.swap + (getattr(d, "fee", 0) or 0)
                        stats["trades"] += 1
                        stats["wins"] += 1 if pnl > 0 else 0
                        stats["profit"] += pnl
                history = magic_history(mt5, SR_MAGIC, now() - 7 * 86400)
        except Exception as e:
            c["statusError"] = str(e)
        with self.lock:
            return {"ok": True, "config": c, "history": history, "orders": [], "positions": positions, "stats": stats,
                    "events": self.events[:40], "error": self.error, "startedAt": self.started}


# ---------------------------------------------------------------------------
# "Nến tick" bot v2: scalps inside each candle on its ticks. Every time price runs `step` from the last
# entry (or the candle's open) it opens a position that way (up = BUY, down = SELL), so the side price
# pushes harder gets more positions. No SL / TP at the broker: a position closes as soon as it is
# `closeProfit` in profit, and the next one can come in. Safety: at most `maxPositions` open, the whole
# basket closed if it is `basketStop` dollars down, and (by default) everything closed at the candle's end.
# The website's backtest (web/assets/app.js, tickBotBacktest) follows the same rules; keep the two in step.

TICK_MAGIC = 20265
DEFAULT_TICKBOT = {"running": False, "symbol": "", "interval": "1m", "direction": "both", "lots": 0.01,
                   "step": 0.3, "closeProfit": 0.3, "maxPositions": 6, "basketStop": 30.0, "burst": 1,
                   # v3: a stop for each position (price, 0 = none), entries only with the candle (above its open:
                   # buys, below: sells), and losing positions out once the candle turns the other way past a step.
                   "sl": 0.3, "withCandle": True, "flipExit": True,
                   "exitAtClose": True, "minLeftPct": 15, "maxSpread": 0.5,
                   # Virtual account only: fills at the bid both ways (as if there were no spread).
                   "noSpread": False,
                   # Virtual account only, a broker account type to try: a spread of its own (price, -1 = the real
                   # one) and a commission in dollars per lot, round trip.
                   "simSpread": -1.0, "commission": 0.0,
                   # Test mode (virtual account only): every position out after this many seconds, profit or loss
                   # (-1 = off; 0 = at the next tick).
                   "holdSeconds": -1.0,
                   # True: virtual orders on the live Exness price (no order sent to MT5), False: real orders.
                   "paper": True}
TICK_PAPER_PATH = os.path.join(HERE, "tickbot_paper.json")
SECONDS_OF = {"1m": 60, "2m": 120, "3m": 180, "4m": 240, "5m": 300, "6m": 360, "10m": 600, "12m": 720,
              "15m": 900, "20m": 1200, "30m": 1800, "1h": 3600}


class TickBot:
    """Buys and sells again and again inside one candle, more on the side price pushes; each position
    closes on its own small profit (no SL / TP), the rest at the candle's close."""

    MAGIC = TICK_MAGIC
    KEY = "tickbot"
    LABEL = "⚡ Bot nến tick: "
    COMMENT = "TickBot"

    @staticmethod
    def defaults():
        return DEFAULT_TICKBOT

    @staticmethod
    def paper_path():
        return TICK_PAPER_PATH

    def __init__(self, server):
        self.server = server
        self.lock = threading.RLock()
        self.events = []
        self.bar = None          # the candle being traded
        self.ref = None          # price of the last entry in it (the candle's open at first)
        self.stopped_bar = None  # the candle whose basket stop was hit: no more entries in it
        self.error = ""
        self.started = None
        self.paper = read_json(self.paper_path(), None) or {"balance": 10000.0, "positions": [], "history": []}
        threading.Thread(target=self._loop, daemon=True).start()

    def _save_paper(self):
        write_json(self.paper_path(), self.paper)

    @property
    def cfg(self):
        c = self.server.config.setdefault(self.KEY, {})
        for k, v in self.defaults().items():
            c.setdefault(k, v)
        return c

    def event(self, text, notify=False):
        with self.lock:
            self.events.insert(0, {"time": now(), "text": text})
            del self.events[80:]
        self.server.log(self.LABEL + text, notify=notify)

    def settings(self, body):
        c = self.cfg
        self._fields(c, body)
        if body.get("paperReset"):
            with self.lock:
                self.paper = {"balance": float(body["paperReset"]), "positions": [], "history": []}
                self._save_paper()
            self.event(f"đặt lại tài khoản ảo: {money(float(body['paperReset']))}")
        if "running" in body:
            on = bool(body["running"])
            if on and not c["symbol"]:
                raise ValueError("Chưa chọn mã")
            if on and not c["running"]:
                self._reset()
                self.error, self.started = "", now()
                self.event(f"BẬT {'(ẢO, giá Exness)' if c['paper'] else 'trên MT5'} · {c['symbol']} · {self._start_text(c)}", notify=True)
            if not on and c["running"]:
                self.event("TẮT (lệnh đang mở giữ nguyên)", notify=True)
            c["running"] = on
        self.server.save_config()
        return self.status()

    def _reset(self):
        self.bar, self.ref, self.stopped_bar = None, None, None

    def _start_text(self, c):
        return (f"{c['interval']} · {c['lots']} lot · vào mỗi {c['step']} giá chạy · chốt khi lời {c['closeProfit']} · "
                f"tối đa {c['maxPositions']} lệnh")

    def _fields(self, c, body):
        for key, cast in (("symbol", str), ("interval", str), ("direction", str), ("lots", float), ("step", float),
                          ("closeProfit", float), ("maxPositions", int), ("basketStop", float), ("burst", int), ("exitAtClose", bool),
                          ("sl", float), ("withCandle", bool), ("flipExit", bool),
                          ("simSpread", float), ("commission", float),
                          ("holdSeconds", float),
                          ("minLeftPct", float), ("maxSpread", float), ("paper", bool), ("noSpread", bool)):
            if key in body:
                c[key] = cast(body[key])
        if c["interval"] not in SECONDS_OF:
            raise ValueError("Khung không hợp lệ (1m – 1h)")
        if c["direction"] not in ("both", "long", "short"):
            raise ValueError("Chiều không hợp lệ")
        if c["step"] <= 0 or c["closeProfit"] <= 0:
            raise ValueError("Bước vào lệnh và mức chốt lời phải lớn hơn 0")
        c["lots"] = max(0.01, c["lots"])
        c["maxPositions"] = max(1, min(50, c["maxPositions"]))
        c["burst"] = max(1, min(5, c["burst"]))
        c["basketStop"] = max(0.0, c["basketStop"])
        c["minLeftPct"] = max(0.0, min(90.0, c["minLeftPct"]))
        if c.get("holdSeconds", -1) >= 0 and not c["paper"]:
            # Opening only to close at once on a real account is churning: costs the spread every time and
            # breaks most brokers' and IB programs' terms. Only on the virtual account, to see the numbers.
            c["holdSeconds"] = -1.0
            raise ValueError("Chế độ 'vào rồi chốt ngay' chỉ chạy trên tài khoản ẢO (Chạy thử) và Backtest")

    def _mine(self, rows):
        return [r for r in rows or () if getattr(r, "magic", 0) == self.MAGIC]

    def _loop(self):
        while True:
            time.sleep(0.25)
            if not self.cfg["running"]:
                continue
            try:
                with Mt5.lock:
                    self._tick()
                self.error = ""
            except Exception as e:
                if str(e) != self.error:
                    self.event(f"lỗi: {e}")
                self.error = str(e)
                self.state = {"kind": "error", "error": str(e)}
                time.sleep(2)

    @staticmethod
    def _units(info, symbol):
        size = float(getattr(info, "trade_contract_size", 0) or 0)
        return size if size > 0 else contract_size(symbol)

    # ----- the book: the bot's positions as dicts, on MT5 or virtual -----

    def _book(self, mt5, symbol):
        if self.cfg["paper"]:
            return [p for p in self.paper["positions"] if p["symbol"] == symbol]
        return [{"id": int(p.ticket), "symbol": p.symbol, "side": "long" if p.type == mt5.POSITION_TYPE_BUY else "short",
                 "lots": p.volume, "entry": p.price_open, "openTime": float(p.time), "raw": p}
                for p in self._mine(mt5.positions_get(symbol=symbol))]

    def _open(self, mt5, symbol, info, tick, long, why, lots=None, stop=None):
        c = self.cfg
        lots = round(max(0.01, float(lots if lots is not None else c["lots"])), 2)
        price = tick.ask if long else tick.bid
        if c["paper"]:
            self.seq = getattr(self, "seq", 0) + 1
            # The spread paid on the way in (Exness' own bid / ask at that tick), in money.
            spread_cost = round((tick.ask - tick.bid) * lots * self._units(info, symbol), 2)
            p = {"id": f"P{int(time.time() * 1000)}-{self.seq}", "symbol": symbol, "side": "long" if long else "short", "lots": lots,
                 "entry": price, "openTime": float(tick.time), "paper": True, "spreadCost": spread_cost, "stop": stop}
            with self.lock:
                self.paper["positions"].append(p)
                self._save_paper()
            self.event(f"ẢO: {'MUA' if long else 'BÁN'} {lots} @ {fmt(price)} ({why})")
            return True
        volume = self.server.mt5_account._volume(mt5, info, lots)
        request = {"action": mt5.TRADE_ACTION_DEAL, "symbol": symbol, "volume": volume,
                   "type": mt5.ORDER_TYPE_BUY if long else mt5.ORDER_TYPE_SELL, "price": price, "sl": float(stop) if stop else 0.0, "tp": 0.0,
                   "magic": self.MAGIC, "comment": self.COMMENT, "type_time": mt5.ORDER_TIME_GTC,
                   "deviation": int(self.server.config["mt5"].get("deviation", 30))}
        _, error = mt5_send(mt5, request)
        if error:
            self.event(f"không vào được {'MUA' if long else 'BÁN'} @ {fmt(price)}: {error}")
            return False
        self.event(f"{'MUA' if long else 'BÁN'} {volume} @ {fmt(price)} ({why})")
        return True

    def _close(self, mt5, p, tick, units, why):
        long = p["side"] == "long"
        price = tick.bid if long else tick.ask
        profit = (price - p["entry"]) * (1 if long else -1) * p["lots"] * units
        if self.cfg["paper"]:
            profit -= float(self.cfg.get("commission", 0) or 0) * p["lots"]
            with self.lock:
                self.paper["positions"] = [x for x in self.paper["positions"] if x["id"] != p["id"]]
                self.paper["balance"] = round(self.paper["balance"] + profit, 2)
                self.paper["history"].insert(0, dict({k: v for k, v in p.items() if k != "raw"}, exit=price, reason=why, closeTime=now(), profit=round(profit, 2)))
                del self.paper["history"][500:]
                self._save_paper()
            self.event(f"ẢO: đóng {'MUA' if long else 'BÁN'} {fmt(p['entry'])} → {fmt(price)} ({why}) · {money(profit)}")
            return
        request = {"action": mt5.TRADE_ACTION_DEAL, "symbol": p["symbol"], "volume": p["lots"],
                   "type": mt5.ORDER_TYPE_SELL if long else mt5.ORDER_TYPE_BUY, "position": p["id"], "price": price,
                   "deviation": int(self.server.config["mt5"].get("deviation", 30)),
                   "magic": self.MAGIC, "comment": f"{self.COMMENT} {CLOSE_CODES.get(why, 'close')}", "type_time": mt5.ORDER_TIME_GTC}
        _, error = mt5_send(mt5, request)
        if error:
            self.event(f"không đóng được #{p['id']}: {error}")
        else:
            self.event(f"đóng #{p['id']} {fmt(p['entry'])} → {fmt(price)} ({why}) · ~{money(profit)}")

    def _tick(self):
        c = self.cfg
        mt5 = Mt5.connect(self.server.config["mt5"])
        if not c["paper"]:
            self.server.mt5_account._check_trading(mt5)
        symbol = Mt5.need_symbol(mt5, c["symbol"])
        info = mt5.symbol_info(symbol)
        tick = mt5.symbol_info_tick(symbol)
        timeframe = getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[c["interval"]])
        rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, 1)
        if tick is None or rates is None or not len(rates):
            return
        no_spread = c["paper"] and c.get("noSpread")
        if no_spread:
            # The virtual account without the spread: buys and sells both at the bid.
            tick = types.SimpleNamespace(bid=tick.bid, ask=tick.bid, time=tick.time)
        elif c["paper"] and float(c.get("simSpread", -1)) >= 0:
            # Another account type tried on the virtual account: its own spread over the real bid.
            tick = types.SimpleNamespace(bid=tick.bid, ask=tick.bid + float(c["simSpread"]), time=tick.time)
        bar_time, bar_open = float(rates[-1]["time"]), float(rates[-1]["open"])
        sec = SECONDS_OF[c["interval"]]
        units = self._units(info, symbol)
        book = self._book(mt5, symbol)
        if bar_time != self.bar:
            # A new candle: what is still open from the last one goes (by default), the count starts again.
            if c["exitAtClose"]:
                for p in book:
                    if p["openTime"] < bar_time:
                        self._close(mt5, p, tick, units, "hết nến")
                book = self._book(mt5, symbol)
            self.bar, self.ref = bar_time, bar_open
        gain = lambda p: (tick.bid - p["entry"]) if p["side"] == "long" else (p["entry"] - tick.ask)
        # Each position out on its own profit, its own stop, or (losing) when the candle has turned against it.
        hold = float(c.get("holdSeconds", -1)) if c["paper"] else -1
        for p in book:
            g = gain(p)
            if hold >= 0 and float(tick.time) - p["openTime"] >= hold:
                self._close(mt5, p, tick, units, "hết giờ giữ")
            elif g >= c["closeProfit"] - 1e-9:
                self._close(mt5, p, tick, units, "chốt lời")
            elif c.get("sl", 0) > 0 and g <= -c["sl"] + 1e-9:
                self._close(mt5, p, tick, units, "cắt lỗ lệnh")
            elif c.get("flipExit") and g < 0 and ((p["side"] == "long" and tick.bid < bar_open - c["step"])
                                                   or (p["side"] == "short" and tick.bid > bar_open + c["step"])):
                self._close(mt5, p, tick, units, "nến đảo chiều")
        book = self._book(mt5, symbol)
        # Basket stop: all out when the open positions together are this much down.
        floating = sum(gain(p) * p["lots"] * units for p in book)
        if c["basketStop"] > 0 and book and floating <= -c["basketStop"]:
            for p in book:
                self._close(mt5, p, tick, units, "cắt lỗ chung")
            self.stopped_bar = bar_time
            self.event(f"cắt lỗ chung {money(floating)}: dừng vào lệnh tới hết cây nến", notify=True)
            return
        if self.stopped_bar == bar_time or len(book) >= c["maxPositions"]:
            return
        left = bar_time + sec - float(tick.time)
        if left < sec * c["minLeftPct"] / 100:
            return
        if not no_spread and c["maxSpread"] > 0 and tick.ask - tick.bid > c["maxSpread"]:
            return
        # A run of `step` from the last entry: in that way.
        move = tick.bid - self.ref
        long, short = move >= c["step"] - 1e-9, -move >= c["step"] - 1e-9
        if not (long or short):
            return
        self.ref = tick.bid
        if (long and c["direction"] == "short") or (short and c["direction"] == "long"):
            return
        # With the candle only: no buys while it is below its open, no sells while above.
        if c.get("withCandle") and ((long and tick.bid <= bar_open) or (short and tick.bid >= bar_open)):
            return
        # `burst` positions at once on each run (as many as the cap leaves room for).
        for _ in range(min(int(c.get("burst", 1)), c["maxPositions"] - len(book))):
            if not self._open(mt5, symbol, info, tick, long, f"giá chạy {move:+.2f}"):
                break

    def _paper_status(self, c):
        positions = []
        try:
            with Mt5.lock:
                mt5 = Mt5.connect(self.server.config["mt5"])
                for p in self.paper["positions"]:
                    tick = mt5.symbol_info_tick(p["symbol"])
                    info = mt5.symbol_info(p["symbol"])
                    long = p["side"] == "long"
                    px = (tick.bid if long or c.get("noSpread") else tick.ask) if tick else p["entry"]
                    positions.append(dict(p, now=px, profit=round((px - p["entry"]) * (1 if long else -1) * p["lots"] * self._units(info, p["symbol"]), 2)))
        except Exception as e:
            c["statusError"] = str(e)
            positions = [dict(p, profit=0.0) for p in self.paper["positions"]]
        hist = self.paper["history"]
        stats = {"trades": len(hist), "wins": sum(1 for h in hist if h["profit"] > 0), "profit": round(sum(h["profit"] for h in hist), 2)}
        price = None
        try:
            with Mt5.lock:
                mt5 = Mt5.connect(self.server.config["mt5"])
                t = mt5.symbol_info_tick(Mt5.need_symbol(mt5, c["symbol"])) if c.get("symbol") else None
                if t is not None:
                    price = {"bid": t.bid, "ask": t.bid if c.get("noSpread") else t.ask}
        except Exception:
            pass
        floating = round(sum(p["profit"] for p in positions), 2)
        with self.lock:
            return {"ok": True, "config": c, "positions": positions, "stats": stats, "history": hist[:300], "price": price,
                    "paper": {"balance": self.paper["balance"], "equity": round(self.paper["balance"] + floating, 2), "floating": floating},
                    "events": self.events[:40], "error": self.error, "startedAt": self.started}

    def status(self):
        c = dict(self.cfg)
        history = []
        if c.get("paper"):
            return self._paper_status(c)
        positions, stats = [], {"trades": 0, "wins": 0, "profit": 0.0}
        try:
            with Mt5.lock:
                mt5 = Mt5.connect(self.server.config["mt5"])
                symbol = c["symbol"] or None
                for p in self._mine(mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()):
                    positions.append({"ticket": int(p.ticket), "symbol": p.symbol, "side": "long" if p.type == mt5.POSITION_TYPE_BUY else "short",
                                      "lots": p.volume, "entry": p.price_open, "stop": None, "target": None,
                                      "now": getattr(p, "price_current", None), "profit": p.profit + getattr(p, "swap", 0)})
                since = self.started or now() - 86400
                for d in mt5.history_deals_get(since + Mt5.offset_seconds - 60, now() + Mt5.offset_seconds + 86400) or ():
                    if getattr(d, "magic", 0) == self.MAGIC and d.entry == mt5.DEAL_ENTRY_OUT:
                        pnl = d.profit + d.commission + d.swap + (getattr(d, "fee", 0) or 0)
                        stats["trades"] += 1
                        stats["wins"] += 1 if pnl > 0 else 0
                        stats["profit"] += pnl
                history = magic_history(mt5, self.MAGIC, now() - 7 * 86400)
        except Exception as e:
            c["statusError"] = str(e)
        with self.lock:
            return {"ok": True, "config": c, "history": history, "positions": positions, "stats": stats,
                    "events": self.events[:40], "error": self.error, "startedAt": self.started}


# ---------- "Nhồi lệnh" bot: a grid with an optional lot multiplier (martingale) ----------
# One basket of buys and / or one of sells. A basket starts with `lots`; each time price goes `gridStep`
# further against its worst entry it adds a position of the last lot × `multiplier` (1 = same lot), at most
# `maxLevels` positions and `maxLot` a position. When a basket is `tpMoney` dollars up (after commission)
# it is all closed ("chốt rổ") and starts again. Safety: everything closed once the bot's open positions are
# `basketStop` dollars down, then no entries for `cooldownMin` minutes. Small wins most of the time, and one
# long run against the grid takes them all back: the stop is required on a real account.
# The website's backtest (web/assets/app.js, gridBotOnTicks) follows the same rules; keep the two in step.

GRID_MAGIC = 20266
DEFAULT_GRIDBOT = {"running": False, "symbol": "", "direction": "both", "lots": 0.01, "gridStep": 2.0,
                   "multiplier": 1.5, "maxLevels": 6, "maxLot": 0.5, "tpMoney": 1.0, "basketStop": 60.0,
                   "cooldownMin": 60.0,
                   # Stop for each basket: price this far against its first entry (on MT5 also the positions' own SL
                   # at the broker), and / or the basket this many dollars down. 0 = off. Then that side rests
                   # `cooldownMin` minutes.
                   "sl": 0.0, "slMoney": 0.0,
                   # Candle strength: the last closed `biasTf` candle with a body of at least `biasMinBody` % of its
                   # range sets the side. "only": new baskets only on that side; "more": both, that side's basket
                   # `biasLotMult` times bigger; "off": both the same.
                   "bias": "off", "biasTf": "5m", "biasMinBody": 50.0, "biasLotMult": 2.0,
                   # How a new basket starts. "both": a buy basket and a sell basket side by side (as above). "signal":
                   # one basket at a time, on the one side every filter that is on agrees on:
                   #   sigCandle — the last closed `sigTf` candle pushes that way (body ≥ `sigBody` % of its range);
                   #   sigSr — the M1 support / resistance (low / high of the last `srBars` closed M1 candles):
                   #           "bounce" buys within `srZone` of the support and sells near the resistance,
                   #           "break" buys just over the resistance and sells just under the support;
                   #   sigTick — price has moved `tickMove` that way in the last `tickSec` seconds.
                   # confirmAdd: a new layer only once price turns back the basket's way (half a tickMove in tickSec).
                   "entry": "signal", "sigCandle": True, "sigTf": "1m", "sigBody": 50.0, "sigSr": "auto", "sigNeed": "two",
                   "srBars": 30, "srZone": 1.0, "sigTick": True, "tickSec": 10.0, "tickMove": 0.3, "confirmAdd": True,
                   # Trailing stop for each position: once it is `trailStart` in profit (price), its stop follows the
                   # best price at `trailDist` behind (on MT5 as the position's own SL at the broker). Off by default.
                   "trailOn": False, "trailStart": 1.0, "trailDist": 0.5,
                   # Where layers go: "with" (nhồi dương) — another position each time price goes gridStep further the
                   # basket's way past its best entry; "against" (nhồi âm) — each gridStep against it past its worst.
                   "addMode": "with",
                   # Signal entry: a basket is closed when the signal turns the other way (then that side's basket
                   # opens), so a basket that never reaches its target or stop does not block the other side.
                   "flipClose": True,
                   # Signal entry: after a sigTf candle closes, no new basket (nor a turn) for `waitSec` seconds; then
                   # only if price still holds over that candle's close (a buy) or under it (a sell). 0 = off.
                   "waitSec": 15.0,
                   # Signal entry: no sell within levelRoom of a recent M1 swing low (no buy near a swing high) unless an
                   # engulfing candle just closed through it — wait for the break, or the bounce the other way.
                   "levelGuard": True, "levelRoom": 1.5,
                   # Fast-market guard: no new positions inside the New York window (NY time, weekdays) nor within
                   # newsBefore / newsAfter minutes of a high-impact USD event; guardAction "close" also closes
                   # everything the bot holds when such a time starts.
                   "nyGuard": True, "nyFrom": "08:15", "nyTo": "10:30", "newsGuard": True, "newsBefore": 15.0,
                   "newsAfter": 15.0, "guardAction": "pause",
                   # More signal filters, on the closed `structTf` candles (the last `structBars`):
                   #   sigSwing — a reversal candle (pin bar / engulfing) at an earlier swing low (buy) or high (sell),
                   #              swings over `swingK` bars each side, within `swingZone`;
                   #   sigZone — price dipping into an unbroken FVG / OB ("fvg", "ob", "both") and the candle closing
                   #             back out the zone's way.
                   "sigSwing": False, "swingK": 3, "swingZone": 0.5, "sigZone": "off", "structTf": "1m", "structBars": 120,
                   "maxSpread": 0.5, "noSpread": False, "simSpread": -1.0, "commission": 0.0,
                   "paper": True}
GRID_PAPER_PATH = os.path.join(HERE, "gridbot_paper.json")


def ny_offset_hours(ts):
    """New York's offset from UTC at `ts`: −4 from the second Sunday of March (2:00) to the first Sunday of
    November (2:00), else −5 (no time zone database needed on the VPS)."""
    import datetime
    d = datetime.datetime.utcfromtimestamp(ts)

    def sunday(month, n):
        first = datetime.datetime(d.year, month, 1)
        return first + datetime.timedelta(days=(6 - first.weekday()) % 7 + 7 * (n - 1))

    start = sunday(3, 2) + datetime.timedelta(hours=7)
    end = sunday(11, 1) + datetime.timedelta(hours=6)
    return -4 if start <= d < end else -5


def hhmm(text):
    """"08:15" → minutes after midnight."""
    h, _, m = str(text).partition(":")
    return max(0, min(1439, int(h or 0) * 60 + int(m or 0)))


def grid_guard(c, ts, events):
    """When the grid bot should stay out of the market: (why, until) inside the New York window (weekdays, NY time)
    or within newsBefore / newsAfter minutes of a high-impact USD event, else None. The website's backtest follows
    the same rule (gridGuard)."""
    if c.get("nyGuard"):
        local = ts + ny_offset_hours(ts) * 3600
        mins, weekday = (local % 86400) / 60, int(local // 86400 + 3) % 7  # 1970-01-01 was a Thursday (3)
        a, b = hhmm(c.get("nyFrom", "08:15")), hhmm(c.get("nyTo", "10:30"))
        if weekday < 5 and a <= mins < b:
            return "giờ mở cửa Mỹ", ts + (b - mins) * 60
    if c.get("newsGuard"):
        before, after = float(c.get("newsBefore", 15)) * 60, float(c.get("newsAfter", 15)) * 60
        for e in events or ():
            if e.get("country") == "USD" and e.get("impact") == "High" and e["time"] - before <= ts <= e["time"] + after:
                return "tin " + str(e.get("title", "")), e["time"] + after
    return None


def grid_lot(c, level, factor=1.0):
    """The lot of a basket's position number `level` (0 = the first); `factor` = the basket's size (the
    candle-strength side's baskets are bigger)."""
    # Half up to the 0.01 lot, as the website's gridLot (Python's round() would give 0.015 → 0.01).
    lots = math.floor(float(c["lots"]) * factor * float(c["multiplier"]) ** level * 100 + 0.5 + 1e-9) / 100
    return min(float(c["maxLot"]), max(0.01, lots))


def candle_bias(c, o, h, l, cl, min_body=None):
    """The side a closed candle pushes ("long" / "short", None when its body is under `biasMinBody` % of its
    range) and its body as a share of the range (+ up, − down)."""
    rng = h - l
    if rng <= 0:
        return None, 0.0
    body = (cl - o) / rng
    if abs(body) * 100 < float(c.get("biasMinBody", 50) if min_body is None else min_body) - 1e-9:
        return None, body
    return ("long" if body > 0 else "short"), body


def swing_points(bars, k):
    """Confirmed swing highs and lows of closed bars (open, high, low, close): a high over the k bars before it and
    not under the k after it (lows the same way)."""
    highs, lows = [], []
    for i in range(k, len(bars) - k):
        h, l = bars[i][1], bars[i][2]
        if h > max(b[1] for b in bars[i - k:i]) and h >= max(b[1] for b in bars[i + 1:i + k + 1]):
            highs.append(h)
        if l < min(b[2] for b in bars[i - k:i]) and l <= min(b[2] for b in bars[i + 1:i + k + 1]):
            lows.append(l)
    return highs, lows


def reversal_candle(prev, last):
    """"long" / "short" when the last closed bar is a reversal: a pin bar (its wick on one side at least half the
    bar and twice its body, closing in the other half), an engulfing of the bar before, or a rejection bar."""
    o, h, l, c = last
    rng = h - l
    if rng <= 0:
        return None
    body, lower, upper = abs(c - o), min(o, c) - l, h - max(o, c)
    po, _, _, pc = prev
    bull = ((lower >= 2 * body and lower >= 0.5 * rng and c >= l + 0.5 * rng) or (c > o and pc < po and c >= po and o <= pc)
            # a rejection: an up bar closing in its top 35 % with a lower wick of at least 30 % of the bar
            or (c > o and c - l >= 0.65 * rng and lower >= 0.3 * rng))
    bear = ((upper >= 2 * body and upper >= 0.5 * rng and c <= h - 0.5 * rng) or (c < o and pc > po and c <= po and o >= pc)
            or (c < o and h - c >= 0.65 * rng and upper >= 0.3 * rng))
    return "long" if bull and not bear else "short" if bear and not bull else None


def swing_vote(c, bars):
    """The swing filter: a reversal candle that just closed at an earlier swing low (buy) or high (sell), within
    swingZone. Returns (sides, the level)."""
    k, z = int(c.get("swingK", 3)), float(c.get("swingZone", 0.5))
    if len(bars) < 2 * k + 3:
        return set(), None
    highs, lows = swing_points(bars[:-1], k)
    rev, last = reversal_candle(bars[-2], bars[-1]), bars[-1]
    # Any recent swing is a level: a low still under price is a support, one price broke and came back up to is now a
    # resistance (and the other way for highs) — the reversal decides which.
    levels = highs[-5:] + lows[-5:]
    if rev == "long":
        near = [x for x in levels if abs(last[2] - x) <= z and last[3] > x]
        if near:
            return {"long"}, near[-1]
    if rev == "short":
        near = [x for x in levels if abs(last[1] - x) <= z and last[3] < x]
        if near:
            return {"short"}, near[-1]
    # A break: an engulfing bar closing through a recent swing (down through a low: sell, up through a high: buy).
    eng = engulfing(bars[-2], last)
    if eng == "short":
        broke = [x for x in lows[-5:] if last[0] >= x > last[3]]
        if broke:
            return {"short"}, broke[-1]
    if eng == "long":
        broke = [x for x in highs[-5:] if last[0] <= x < last[3]]
        if broke:
            return {"long"}, broke[-1]
    return set(), None


def engulfing(prev, last):
    """A breaking bar: "short" / "long" when the last bar is a down / up bar whose body covers the bar before's body
    (an engulfing, whatever that bar's colour) or makes at least 60 % of its range (a long body), else None."""
    o, h, l, c = last
    po, _, _, pc = prev
    rng = h - l
    if rng <= 0 or c == o:
        return None
    covers = max(o, c) >= max(po, pc) and min(o, c) <= min(po, pc)
    if covers or abs(c - o) >= 0.6 * rng:
        return "long" if c > o else "short"
    return None


def swing_levels(c, bars):
    """The recent confirmed swing highs / lows (the last five each) and the last two closed bars, for level_block."""
    k = int(c.get("swingK", 3))
    if len(bars) < 2 * k + 3:
        return None
    highs, lows = swing_points(bars[:-1], k)
    return {"highs": highs[-5:], "lows": lows[-5:], "prev": bars[-2], "last": bars[-1]}


def level_block(c, lv, bid):
    """"Đợi xác nhận ở cản": the side not to open now and the level why — no sell within levelRoom over a recent
    swing (a support) unless the last closed bar broke down and closed under it; no buy within levelRoom under one
    (a resistance, a broken support included) unless it broke up and closed over it. (side, level) or None."""
    if not lv:
        return None
    room, eng, last = float(c.get("levelRoom", 1.5)), engulfing(lv["prev"], lv["last"]), lv["last"]
    # A level's role is where price is: under it, a resistance (a broken support included, retested from below);
    # over it, a support.
    levels = lv["highs"] + lv["lows"]
    sups = [x for x in levels if 0 <= bid - x <= room]
    ress = [x for x in levels if 0 < x - bid <= room]
    if sups:
        s = max(sups)
        if not (eng == "short" and last[3] < s):
            return "short", s
    if ress:
        r = min(ress)
        if not (eng == "long" and last[3] > r):
            return "long", r
    return None


def fvg_ob_zones(bars, kinds):
    """Unbroken fair value gaps and order blocks of closed bars: a bullish FVG where a bar's low is over the high of
    the bar two before it (its OB: the last down bar before the move), a bearish one the other way; broken once a
    later bar closes through it. `kinds`: "fvg", "ob" or "both". [(kind, side, low, high, index)]"""
    zones, n = [], len(bars)
    for i in range(2, n):
        a, d = bars[i - 2], bars[i]
        for side, gap in (("long", a[1] < d[2]), ("short", a[2] > d[1])):
            if not gap:
                continue
            if kinds in ("fvg", "both"):
                zones.append(("fvg", side, a[1], d[2], i) if side == "long" else ("fvg", side, d[1], a[2], i))
            if kinds in ("ob", "both"):
                for j in range(i - 2, max(-1, i - 6), -1):
                    o, h, l, cl = bars[j]
                    if (cl < o) if side == "long" else (cl > o):
                        zones.append(("ob", side, l, h, i))
                        break
    out = []
    for z in zones:
        later = bars[z[4] + 1:]
        if z[1] == "long" and any(b[3] < z[2] for b in later):
            continue
        if z[1] == "short" and any(b[3] > z[3] for b in later):
            continue
        out.append(z)
    return out


def zone_vote(c, bars):
    """The FVG / OB filter: the last closed bar dipped into an unbroken bullish zone and closed up out of it in the
    zone or above (buy), or the other way at a bearish zone (sell). Returns (sides, the zone)."""
    if len(bars) < 4:
        return set(), None
    o, h, l, cl = bars[-1]
    for z in reversed(fvg_ob_zones(bars, c.get("sigZone", "both"))):
        kind, side, lo, hi, i = z
        if i >= len(bars) - 1:
            continue  # formed by the last bar itself
        if side == "long" and l <= hi and cl > o and cl >= lo:
            return {"long"}, {"kind": kind, "side": side, "lo": lo, "hi": hi}
        if side == "short" and h >= lo and cl < o and cl <= hi:
            return {"short"}, {"kind": kind, "side": side, "lo": lo, "hi": hi}
    return set(), None


def grid_signal(c, bid, candle, sup, res, move, detail=None, extra=None):
    """The side the grid bot's signal entry allows now. Each filter that is on votes for the sides it allows; with
    `sigNeed` "all" a side needs every filter's vote, with "two" at least two (all of them when fewer are on) and more
    votes than the other side. None when no side qualifies or no filter is on. `candle` = the last closed sigTf candle
    (open, high, low, close), `sup` / `res` = the M1 support / resistance, `move` = the bid's move over the last
    tickSec seconds. The website's gridSignal follows the same rules."""
    votes, used = {"long": 0, "short": 0}, 0

    def vote(name, ok):
        nonlocal used
        used += 1
        for x in ok:
            votes[x] += 1
        if detail is not None:
            detail[name] = sorted(ok)

    if c.get("sigCandle"):
        side = candle_bias(c, *candle, min_body=float(c.get("sigBody", 50)))[0] if candle else None
        vote("candle", {side} if side else set())
    if c.get("sigSr", "off") != "off":
        z, ok = float(c.get("srZone", 1.0)), set()
        if sup is not None and res is not None:
            if c["sigSr"] == "bounce":
                if sup - z <= bid <= sup + z:
                    ok.add("long")
                if res - z <= bid <= res + z:
                    ok.add("short")
            elif c["sigSr"] == "break":
                if res < bid <= res + z:
                    ok.add("long")
                if sup - z <= bid < sup:
                    ok.add("short")
            elif sup - z <= bid <= sup + z or res - z <= bid <= res + z:
                # "auto": price at a level; the candle and the ticks say whether it breaks or bounces.
                ok = {"long", "short"}
        vote("sr", ok)
    if c.get("sigTick"):
        ok = set()
        if move is not None:
            if move >= float(c["tickMove"]) - 1e-9:
                ok.add("long")
            if move <= -float(c["tickMove"]) + 1e-9:
                ok.add("short")
        vote("tick", ok)
    for name, ok in (extra or {}).items():
        vote(name, ok)
    if not used:
        return None
    need = used if c.get("sigNeed", "all") == "all" else min(2, used)
    good = [x for x in ("long", "short") if votes[x] >= need and votes[x] > votes["short" if x == "long" else "long"]]
    return good[0] if len(good) == 1 else None


class GridBot(TickBot):
    """Grid / martingale "nhồi lệnh": adds to a losing basket every gridStep, closes it on a small profit."""

    MAGIC = GRID_MAGIC
    KEY = "gridbot"
    LABEL = "🕸️ Bot nhồi lệnh: "
    COMMENT = "GridBot"

    @staticmethod
    def defaults():
        return DEFAULT_GRIDBOT

    @staticmethod
    def paper_path():
        return GRID_PAPER_PATH

    @property
    def cfg(self):
        c = self.server.config.setdefault(self.KEY, {})
        if "entry" in c and "sigNeed" not in c and c.get("sigSr") == "bounce":
            # Saved by 5.7 – 5.9, where "bounce" was the default and needed all three filters (it hardly ever
            # traded: the candle into a support points down while the bounce points up): now "auto", 2 of 3.
            c["sigSr"] = "auto"
        return TickBot.cfg.fget(self)

    def _reset(self):
        self.pause_until = 0.0
        self.side_pause = {}
        self.cycles = 0

    @staticmethod
    def sl_level(c, ps, long):
        """The basket's stop: `sl` in price past its first (best) entry, or None."""
        if not c.get("sl") or not ps:
            return None
        return max(p["entry"] for p in ps) - c["sl"] if long else min(p["entry"] for p in ps) + c["sl"]

    def _start_text(self, c):
        return (f"{c['lots']} lot · nhồi {'dương' if c.get('addMode') == 'with' else 'âm'} mỗi {c['gridStep']} giá × {c['multiplier']} · "
                f"tối đa {c['maxLevels']} lớp · chốt rổ {money(c['tpMoney']) if c['tpMoney'] > 0 else 'tắt (trailing)'} · SL rổ {c['sl'] or 'tắt'} giá / {money(c['slMoney']) if c['slMoney'] else 'tắt'} · "
                f"cắt lỗ chung {money(c['basketStop'])}"
                + (self._signal_text(c) if c.get("entry") == "signal" else self._bias_text(c)))

    @staticmethod
    def _signal_text(c):
        parts = []
        if c.get("sigCandle"):
            parts.append(f"nến {c['sigTf']} ≥{c['sigBody']:g}%")
        if c.get("sigSr", "off") != "off":
            kind = {"auto": "cản M1 tự động", "bounce": "bật cản M1", "break": "phá cản M1"}[c["sigSr"]]
            parts.append(f"{kind} ({c['srBars']} nến, vùng {c['srZone']:g})")
        if c.get("sigTick"):
            parts.append(f"tick {c['tickMove']:g}/{c['tickSec']:g}s")
        if float(c.get("waitSec", 0)) > 0:
            parts.append(f"chờ {c['waitSec']:g}s sau khi nến đóng")
        if c.get("levelGuard"):
            parts.append(f"đợi xác nhận ở đỉnh/đáy M1 (±{c['levelRoom']:g})")
        if c.get("sigSwing"):
            parts.append(f"nến đảo chiều ở đỉnh/đáy {c['structTf']}")
        if c.get("sigZone", "off") != "off":
            parts.append(f"phản ứng {'FVG + OB' if c['sigZone'] == 'both' else c['sigZone'].upper()} {c['structTf']}")
        if c.get("trailOn"):
            parts.append(f"trailing {c['trailDist']:g} sau khi lời {c['trailStart']:g}")
        return (" · vào 1 bên theo " + " + ".join(parts) + (" (cần đủ)" if c.get("sigNeed", "all") == "all" else " (cần 2 đồng ý)")) + (" · nhồi khi giá quay đầu" if c.get("confirmAdd") else "")

    def _signal_why(self, c, side):
        sg, parts = getattr(self, "signal", None) or {}, []
        if c.get("sigCandle") and sg.get("candle"):
            parts.append(f"nến {c['sigTf']} {'tăng' if side == 'long' else 'giảm'} {abs(round(sg['candle'][1] * 100))}%")
        if c.get("sigSr", "off") != "off" and sg.get("sup") is not None:
            bid = (getattr(self, "bids", None) or [(0, 0, "")])[-1][1]
            at_sup = abs(bid - sg["sup"]) <= abs(bid - sg["res"])
            lv = sg["sup"] if at_sup else sg["res"]
            how = "bật" if (side == "long") == at_sup else "phá"
            parts.append(f"{how} {'hỗ trợ' if at_sup else 'kháng cự'} {fmt(lv)}")
        if c.get("sigTick") and sg.get("move") is not None:
            parts.append(f"tick {sg['move']:+.2f}/{c['tickSec']:g}s")
        if c.get("sigSwing") and sg.get("swingLevel") is not None:
            parts.append(f"nến đảo chiều tại {'đáy' if side == 'long' else 'đỉnh'} {fmt(sg['swingLevel'])}")
        if c.get("sigZone", "off") != "off" and sg.get("zone"):
            z = sg["zone"]
            parts.append(f"phản ứng {z['kind'].upper()} {fmt(z['lo'])}–{fmt(z['hi'])}")
        return (": " + ", ".join(parts)) if parts else ""

    @staticmethod
    def _bias_text(c):
        if c.get("bias", "off") == "off":
            return ""
        how = "chỉ bên mạnh" if c["bias"] == "only" else f"bên mạnh ×{c['biasLotMult']:g} lot"
        return f" · lực nến {c['biasTf']} ≥{c['biasMinBody']:g}% ({how})"

    def _fields(self, c, body):
        for key, cast in (("symbol", str), ("direction", str), ("lots", float), ("gridStep", float), ("multiplier", float),
                          ("maxLevels", int), ("maxLot", float), ("tpMoney", float), ("basketStop", float),
                          ("cooldownMin", float), ("sl", float), ("slMoney", float), ("maxSpread", float),
                          ("bias", str), ("biasTf", str), ("biasMinBody", float), ("biasLotMult", float), ("simSpread", float), ("commission", float),
                          ("entry", str), ("sigCandle", bool), ("sigTf", str), ("sigBody", float), ("sigSr", str), ("sigNeed", str), ("srBars", int),
                          ("srZone", float), ("sigTick", bool), ("tickSec", float), ("tickMove", float), ("confirmAdd", bool),
                          ("trailOn", bool), ("trailStart", float), ("trailDist", float),
                          ("sigSwing", bool), ("swingK", int), ("swingZone", float), ("sigZone", str), ("structTf", str), ("structBars", int),
                          ("addMode", str), ("flipClose", bool), ("waitSec", float), ("levelGuard", bool), ("levelRoom", float),
                          ("nyGuard", bool), ("nyFrom", str), ("nyTo", str), ("newsGuard", bool), ("newsBefore", float),
                          ("newsAfter", float), ("guardAction", str), ("paper", bool), ("noSpread", bool)):
            if key in body:
                c[key] = cast(body[key])
        if c["direction"] not in ("both", "long", "short"):
            raise ValueError("Chiều không hợp lệ")
        if c["addMode"] not in ("with", "against"):
            raise ValueError("Kiểu nhồi không hợp lệ")
        if c["gridStep"] <= 0 or c["tpMoney"] < 0:
            raise ValueError("Khoảng nhồi phải lớn hơn 0, mức chốt rổ không âm")
        if c["tpMoney"] == 0 and not c.get("trailOn") and not body.get("trailOn"):
            raise ValueError("Chốt rổ = 0 (tắt) thì phải bật Trailing stop để bot có chỗ chốt lời")
        c["lots"] = round(max(0.01, c["lots"]), 2)
        c["multiplier"] = max(1.0, min(3.0, c["multiplier"]))
        c["maxLevels"] = max(1, min(30, c["maxLevels"]))
        c["maxLot"] = max(c["lots"], c["maxLot"])
        c["basketStop"] = max(0.0, c["basketStop"])
        c["cooldownMin"] = max(0.0, c["cooldownMin"])
        c["sl"], c["slMoney"] = max(0.0, c["sl"]), max(0.0, c["slMoney"])
        if c["bias"] not in ("off", "only", "more"):
            raise ValueError("Kiểu lực nến không hợp lệ")
        if c["biasTf"] not in SECONDS_OF:
            raise ValueError("Khung nến của lực nến không hợp lệ (1m – 1h)")
        c["biasMinBody"] = max(0.0, min(100.0, c["biasMinBody"]))
        c["biasLotMult"] = max(1.0, min(5.0, c["biasLotMult"]))
        if c["entry"] not in ("both", "signal"):
            raise ValueError("Cách vào lệnh không hợp lệ")
        if c["sigTf"] not in SECONDS_OF:
            raise ValueError("Khung nến tín hiệu không hợp lệ (1m – 1h)")
        if c["sigSr"] not in ("off", "auto", "bounce", "break"):
            raise ValueError("Kiểu cản không hợp lệ")
        if c["sigNeed"] not in ("all", "two"):
            raise ValueError("Số bộ lọc cần đồng ý không hợp lệ")
        c["sigBody"] = max(0.0, min(100.0, c["sigBody"]))
        c["srBars"] = max(5, min(500, c["srBars"]))
        c["srZone"] = max(0.01, c["srZone"])
        c["tickSec"] = max(1.0, min(300.0, c["tickSec"]))
        c["tickMove"] = max(0.01, c["tickMove"])
        if c["entry"] == "signal" and not (c["sigCandle"] or c["sigSr"] != "off" or c["sigTick"] or c["sigSwing"] or c["sigZone"] != "off"):
            raise ValueError("Vào theo tín hiệu: bật ít nhất một trong nến / cản / tick")
        c["trailStart"], c["trailDist"] = max(0.01, c["trailStart"]), max(0.01, c["trailDist"])
        if c["guardAction"] not in ("pause", "close"):
            raise ValueError("Cách tránh giờ mạnh không hợp lệ")
        if not re.fullmatch(r"\d{1,2}:\d{2}", c["nyFrom"]) or not re.fullmatch(r"\d{1,2}:\d{2}", c["nyTo"]):
            raise ValueError("Giờ phiên Mỹ phải dạng HH:MM (giờ New York)")
        c["newsBefore"], c["newsAfter"] = max(0.0, min(240.0, c["newsBefore"])), max(0.0, min(240.0, c["newsAfter"]))
        c["waitSec"] = max(0.0, min(float(SECONDS_OF.get(c.get("sigTf", "1m"), 60)) - 1, c["waitSec"]))
        if c["sigZone"] not in ("off", "fvg", "ob", "both"):
            raise ValueError("Kiểu vùng FVG / OB không hợp lệ")
        if c["structTf"] not in SECONDS_OF:
            raise ValueError("Khung nến đỉnh đáy / FVG không hợp lệ (1m – 1h)")
        c["swingK"] = max(1, min(10, c["swingK"]))
        c["swingZone"] = max(0.01, c["swingZone"])
        c["structBars"] = max(20, min(500, c["structBars"]))
        if body.get("resume"):
            # "Chạy lại ngay": no more resting after a stop.
            self.pause_until, self.side_pause = 0.0, {}
            self.event("bỏ thời gian nghỉ: vào lệnh lại ngay khi có tín hiệu")
        if not c["paper"] and c["basketStop"] <= 0 and c["sl"] <= 0 and c["slMoney"] <= 0 and (c["running"] or body.get("running")):
            raise ValueError("Trên tài khoản MT5 phải đặt SL rổ hoặc Cắt lỗ chung (nhồi lệnh không cắt lỗ có thể cháy tài khoản)")

    def _tick(self):
        c = self.cfg
        mt5 = Mt5.connect(self.server.config["mt5"])
        if not c["paper"]:
            self.server.mt5_account._check_trading(mt5)
        symbol = Mt5.need_symbol(mt5, c["symbol"])
        info = mt5.symbol_info(symbol)
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            self.state = {"kind": "noprice", "symbol": symbol}
            return
        no_spread = c["paper"] and c.get("noSpread")
        if no_spread:
            tick = types.SimpleNamespace(bid=tick.bid, ask=tick.bid, time=tick.time)
        elif c["paper"] and float(c.get("simSpread", -1)) >= 0:
            tick = types.SimpleNamespace(bid=tick.bid, ask=tick.bid + float(c["simSpread"]), time=tick.time)
        units = self._units(info, symbol)
        comm = float(c.get("commission", 0) or 0) if c["paper"] else 0.0
        # The bid of the last few minutes, for the tick filter (one sample a loop, 4 a second).
        hist = getattr(self, "bids", None)
        if hist is None or (hist and hist[-1][2] != symbol):
            hist = self.bids = collections.deque(maxlen=2400)
        t_now = time.time()
        hist.append((t_now, float(tick.bid), symbol))
        back = [b for (t, b, _) in hist if t <= t_now - float(c["tickSec"])]
        move = float(tick.bid) - back[-1] if back else None

        def pnl(ps):
            return sum(((tick.bid - p["entry"]) if p["side"] == "long" else (p["entry"] - tick.ask)) * p["lots"] * units
                       - comm * p["lots"] for p in ps)

        book = self._book(mt5, symbol)
        if c.get("trailOn") and book and self._trail(mt5, c, book, tick, units, info):
            book = self._book(mt5, symbol)
        total = pnl(book)
        if c["basketStop"] > 0 and book and total <= -c["basketStop"]:
            for p in book:
                self._close(mt5, p, tick, units, "cắt lỗ chung")
            self.pause_until = time.time() + c["cooldownMin"] * 60
            self.event(f"cắt lỗ chung {money(total)}: nghỉ {c['cooldownMin']:g} phút", notify=True)
            self.state = {"kind": "pause", "until": self.pause_until, "why": "cắt lỗ chung"}
            return
        closed = False
        pauses = getattr(self, "side_pause", None)
        if pauses is None:
            pauses = self.side_pause = {}
        for side in ("long", "short"):
            ps = [p for p in book if p["side"] == side]
            level = self.sl_level(c, ps, side == "long")
            hit = level is not None and (tick.bid <= level + 1e-9 if side == "long" else tick.ask >= level - 1e-9)
            if ps and (hit or (c.get("slMoney", 0) > 0 and pnl(ps) <= -c["slMoney"] + 1e-9)):
                loss = pnl(ps)
                for p in ps:
                    self._close(mt5, p, tick, units, "SL rổ")
                pauses[side] = time.time() + c["cooldownMin"] * 60
                self.event(f"SL rổ {'MUA' if side == 'long' else 'BÁN'} {len(ps)} lệnh · {money(loss)} · bên này nghỉ {c['cooldownMin']:g} phút", notify=True)
                closed = True
                continue
            if ps and c["tpMoney"] > 0 and pnl(ps) >= c["tpMoney"] - 1e-9:
                gain = pnl(ps)
                for p in ps:
                    self._close(mt5, p, tick, units, "chốt rổ")
                self.cycles = getattr(self, "cycles", 0) + 1
                self.event(f"chốt rổ {'MUA' if side == 'long' else 'BÁN'} {len(ps)} lệnh · {money(gain)}")
                closed = True
        if closed:
            return  # the new basket starts at the next tick, on a fresh price
        guard = grid_guard(c, time.time(), self._news_events()) if (c.get("nyGuard") or c.get("newsGuard")) else None
        if guard:
            if c.get("guardAction") == "close" and book:
                loss = pnl(book)
                for p in book:
                    self._close(mt5, p, tick, units, "tránh giờ mạnh")
                self.event(f"{guard[0]}: đóng hết {len(book)} lệnh trước giờ mạnh · {money(loss)}", notify=True)
            self.state = {"kind": "guard", "why": guard[0], "until": guard[1], "holding": len(book) if c.get("guardAction") != "close" else 0}
            return
        if time.time() < getattr(self, "pause_until", 0):
            self.state = {"kind": "pause", "until": self.pause_until, "why": "cắt lỗ chung"}
            return
        if not no_spread and c["maxSpread"] > 0 and tick.ask - tick.bid > c["maxSpread"]:
            self.state = {"kind": "spread", "spread": round(tick.ask - tick.bid, 3), "max": c["maxSpread"]}
            return
        signal = None
        if c.get("entry") == "signal":
            candle, bar_t = None, None
            rates = mt5.copy_rates_from_pos(symbol, getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[c["sigTf"]]), 1, 1)
            if rates is not None and len(rates):
                r = rates[-1]
                candle, bar_t = (float(r["open"]), float(r["high"]), float(r["low"]), float(r["close"])), float(r["time"])
            sup = res = None
            if c.get("sigSr", "off") != "off":
                bars = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M1, 1, int(c["srBars"]))
                if bars is not None and len(bars):
                    sup, res = float(min(b["low"] for b in bars)), float(max(b["high"] for b in bars))
            extra, struct = {}, {}
            if c.get("sigSwing") or c.get("sigZone", "off") != "off" or c.get("levelGuard"):
                # Swings and FVG / OB of the closed structTf candles, worked out again only on a new candle.
                rates = mt5.copy_rates_from_pos(symbol, getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[c["structTf"]]), 1, int(c["structBars"]))
                if rates is not None and len(rates):
                    key = (symbol, c["structTf"], float(rates[-1]["time"]), c.get("sigSwing"), c.get("sigZone"), c.get("swingK"), c.get("swingZone"),
                           c.get("levelGuard"))
                    if getattr(self, "struct_key", None) != key:
                        bars = [(float(r["open"]), float(r["high"]), float(r["low"]), float(r["close"])) for r in rates]
                        self.struct_key, self.struct = key, {"swing": swing_vote(c, bars) if c.get("sigSwing") else None,
                                                             "zone": zone_vote(c, bars) if c.get("sigZone", "off") != "off" else None,
                                                             "levels": swing_levels(c, bars) if c.get("levelGuard") else None}
                    struct = self.struct
                for name in ("swing", "zone"):
                    if struct.get(name) is not None:
                        extra[name] = struct[name][0]
            parts = {}
            signal = grid_signal(c, float(tick.bid), candle, sup, res, move, parts, extra)
            gate, wait_left, level = None, 0.0, None
            block = level_block(c, struct.get("levels"), float(tick.bid)) if c.get("levelGuard") else None
            if block and signal == block[0]:
                gate, level, signal = "level", block[1], None
            if float(c.get("waitSec", 0)) > 0 and bar_t is not None:
                # Seconds since that candle closed, on the broker's clock (the tick's and the bars' times are both).
                since = float(tick.time) - (bar_t + SECONDS_OF[c["sigTf"]])
                if since < float(c["waitSec"]):
                    gate, wait_left, signal = "waiting", round(float(c["waitSec"]) - since, 1), None
                elif signal and ((signal == "long" and tick.bid < candle[3]) or (signal == "short" and tick.bid > candle[3])):
                    gate, signal = "notHeld", None
            if block:
                level = block[1]
            self.signal = {"gate": gate, "level": level, "blocked": block[0] if block else None, "waitLeft": wait_left, "close": candle[3] if candle else None, "side": signal, "candle": candle_bias(c, *candle, min_body=float(c["sigBody"])) if candle else None,
                           "sup": sup, "res": res, "move": None if move is None else round(move, 3), "time": now(), "parts": parts,
                           "swingLevel": (struct.get("swing") or (None, None))[1], "zone": (struct.get("zone") or (None, None))[1]}
        strong = None
        if c.get("entry") != "signal" and c.get("bias", "off") != "off":
            # The last closed candle of the strength timeframe (bid prices, as the chart).
            rates = mt5.copy_rates_from_pos(symbol, getattr(mt5, "TIMEFRAME_" + MT5_TIMEFRAMES[c["biasTf"]]), 1, 1)
            if rates is not None and len(rates):
                r = rates[-1]
                strong, body = candle_bias(c, float(r["open"]), float(r["high"]), float(r["low"]), float(r["close"]))
                self.bias = {"side": strong, "body": round(body * 100), "time": float(r["time"])}
        if c.get("entry") == "signal" and c.get("flipClose") and signal and any(p["side"] != signal for p in book):
            # The signal turned: out of the basket the other way; the new one opens at the next tick.
            other = [p for p in book if p["side"] != signal]
            loss = pnl(other)
            for p in other:
                self._close(mt5, p, tick, units, "tín hiệu ngược")
            self.event(f"tín hiệu đảo sang {'MUA' if signal == 'long' else 'BÁN'}: đóng rổ {'BÁN' if signal == 'long' else 'MUA'} {len(other)} lệnh · {money(loss)}")
            self.state = {"kind": "flip", "side": signal}
            return
        # What the bot is doing now, for the website ("why does it not trade?").
        rest = {k: v for k, v in pauses.items() if v > time.time()}
        if book:
            self.state = {"kind": "holding", "sides": sorted({p["side"] for p in book}), "count": len(book), "sidePause": rest,
                          "signal": signal, "parts": (getattr(self, "signal", None) or {}).get("parts", {}) if c.get("entry") == "signal" else {}}
        elif c.get("entry") == "signal":
            self.state = {"kind": "wait" if not signal else "open", "side": signal, "parts": self.signal.get("parts", {}), "sidePause": rest,
                          "gate": self.signal.get("gate"), "waitLeft": self.signal.get("waitLeft"), "close": self.signal.get("close"),
                          "level": self.signal.get("level"), "blocked": self.signal.get("blocked")}
        else:
            self.state = {"kind": "open", "sidePause": rest}
        for side in ("long", "short"):
            if c["direction"] not in ("both", side) or time.time() < pauses.get(side, 0):
                continue
            long = side == "long"
            ps = [p for p in book if p["side"] == side]
            price = tick.ask if long else tick.bid
            if not ps:
                if c.get("entry") == "signal" and (book or signal != side):
                    continue  # one basket at a time, on the side the signal shows
                if c.get("bias") == "only" and strong != side and c.get("entry") != "signal":
                    continue  # no basket against (or without) the candle's push
                factor = float(c["biasLotMult"]) if c.get("bias") == "more" and strong == side else 1.0
                stop = (price - c["sl"] if long else price + c["sl"]) if c.get("sl") else None
                why = "mở rổ" + (f" · lực nến {'MUA' if long else 'BÁN'} {abs(self.bias['body'])}%" if strong == side else "")
                if c.get("entry") == "signal":
                    why = "mở rổ theo tín hiệu" + self._signal_why(c, side)
                self._open(mt5, symbol, info, tick, long, why, grid_lot(c, 0, factor), stop)
            elif len(ps) < c["maxLevels"]:
                worst = min(p["entry"] for p in ps) if long else max(p["entry"] for p in ps)
                best = max(p["entry"] for p in ps) if long else min(p["entry"] for p in ps)
                # Nhồi dương: price gridStep further the basket's way than its best entry; nhồi âm: against its worst.
                gone = (price - best if long else best - price) if c.get("addMode") == "with" else (worst - price if long else price - worst)
                turned = not (c.get("entry") == "signal" and c.get("confirmAdd")) or (
                    move is not None and (move if long else -move) >= float(c["tickMove"]) / 2 - 1e-9)
                if gone >= c["gridStep"] - 1e-9 and turned:
                    # The new layer gets the basket's stop (first entry ± sl), as its other positions, and its size.
                    stop = self.sl_level(c, ps, long)
                    first = min(ps, key=lambda p: p["openTime"])
                    factor = max(1.0, round(float(first["lots"]) / float(c["lots"]), 2))
                    self._open(mt5, symbol, info, tick, long, f"nhồi {'dương' if c.get('addMode') == 'with' else 'âm'} lớp {len(ps) + 1}", grid_lot(c, len(ps), factor), stop)

    def _news_events(self):
        """This week's calendar for the news guard: the server's cached feed, fetched again in the background every
        10 minutes (never inside the bot's loop, which holds MT5)."""
        if time.time() - getattr(self, "news_at", 0) > 600 and not getattr(self, "news_busy", False):
            self.news_at, self.news_busy = time.time(), True

            def fetch():
                try:
                    self.news_events = (self.server.news.get() or {}).get("events") or []
                except Exception:
                    pass
                finally:
                    self.news_busy = False
            threading.Thread(target=fetch, daemon=True).start()
        return getattr(self, "news_events", [])

    def _trail(self, mt5, c, book, tick, units, info):
        """Trailing stop for each position: the best price since it opened, and once the position is trailStart in
        profit a stop trailDist behind it. Closes what crossed its stop; on MT5 also moves the position's own SL.
        True when something was closed."""
        peaks = getattr(self, "peaks", None)
        if peaks is None:
            peaks = self.peaks = {}
        start, dist, closed, dirty = float(c["trailStart"]), float(c["trailDist"]), False, False
        for p in book:
            long = p["side"] == "long"
            now_px = tick.bid if long else tick.ask
            peak = p.get("peak") if p.get("paper") else peaks.get(p["id"])
            peak = now_px if peak is None else (max(peak, now_px) if long else min(peak, now_px))
            if p.get("paper"):
                if p.get("peak") != peak:
                    p["peak"] = peak
            else:
                peaks[p["id"]] = peak
            if (peak - p["entry"] if long else p["entry"] - peak) < start - 1e-9:
                continue
            stop = peak - dist if long else peak + dist
            if (now_px <= stop + 1e-9) if long else (now_px >= stop - 1e-9):
                self._close(mt5, p, tick, units, "trailing")
                peaks.pop(p["id"], None)
                closed = True
                continue
            if p.get("paper"):
                if p.get("trail") is None or (stop > p["trail"] + 1e-9 if long else stop < p["trail"] - 1e-9):
                    for x in self.paper["positions"]:
                        if x["id"] == p["id"]:
                            x["trail"], x["peak"] = round(stop, 3), peak
                    dirty = True
            else:
                raw = p.get("raw")
                cur = float(getattr(raw, "sl", 0) or 0)
                point = float(getattr(info, "point", 0.01) or 0.01)
                if cur == 0 or (stop > cur + point if long else stop < cur - point):
                    digits = int(getattr(info, "digits", 2) or 2)
                    _, error = mt5_send(mt5, {"action": mt5.TRADE_ACTION_SLTP, "symbol": p["symbol"], "position": p["id"],
                                              "sl": round(stop, digits), "tp": float(getattr(raw, "tp", 0) or 0)})
                    if error and getattr(self, "trail_error", "") != error:
                        self.event(f"không dời được SL trailing #{p['id']}: {error}")
                    self.trail_error = error or ""
        if dirty:
            with self.lock:
                self._save_paper()
        live = {p["id"] for p in book}
        for k in [k for k in peaks if k not in live]:
            peaks.pop(k, None)
        return closed

    def status(self):
        st = super().status()
        cfg = st.get("config") or {}
        levels = [grid_lot(cfg, i) for i in range(int(cfg.get("maxLevels", 1)))] if cfg.get("maxLot") else []
        st["grid"] = {"cycles": getattr(self, "cycles", 0), "pauseUntil": getattr(self, "pause_until", 0) or None,
                      "bias": getattr(self, "bias", None) if cfg.get("bias", "off") != "off" and cfg.get("entry") != "signal" else None,
                      "signal": getattr(self, "signal", None) if cfg.get("entry") == "signal" else None,
                      "state": ((getattr(self, "state", None) or {"kind": "starting"}) if cfg.get("running") else {"kind": "off"}),
                      "sidePause": {k: v for k, v in (getattr(self, "side_pause", None) or {}).items() if v > time.time()},
                      "lots": levels, "totalLots": round(sum(levels), 2)}
        return st


class NewsFeed:
    """This week's economic calendar (Forex Factory mirror) and gold headlines (Google
    News), fetched for the website: browsers cannot read those feeds themselves (CORS).
    Cached for 15 minutes, as the calendar feed asks."""

    CALENDAR = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
    HEADLINES = "https://news.google.com/rss/search?" + urllib.parse.urlencode(
        {"q": "giá vàng thế giới OR XAUUSD when:2d", "hl": "vi", "gl": "VN", "ceid": "VN:vi"})

    def __init__(self):
        self.lock = threading.Lock()
        self.cache = None
        self.time = 0

    @staticmethod
    def _get(url):
        request = urllib.request.Request(url, headers={"User-Agent": "GoldBot/" + VERSION})
        with urllib.request.urlopen(request, timeout=20) as r:
            return r.read()

    def get(self):
        with self.lock:
            if self.cache and now() - self.time < 900:
                return self.cache
            events, headlines, problems = [], [], []
            try:
                import datetime
                for row in json.loads(self._get(self.CALENDAR).decode("utf-8")):
                    try:
                        when = datetime.datetime.fromisoformat(str(row["date"])).timestamp()
                    except (KeyError, ValueError):
                        continue
                    events.append({"title": row.get("title", ""), "country": row.get("country", ""), "time": when,
                                   "impact": row.get("impact", ""), "forecast": row.get("forecast", ""),
                                   "previous": row.get("previous", ""), "actual": row.get("actual", "")})
                events.sort(key=lambda e: e["time"])
            except Exception:
                problems.append("lịch kinh tế")
            try:
                import email.utils
                import xml.etree.ElementTree as ET
                for item in ET.fromstring(self._get(self.HEADLINES)).iter("item"):
                    date = item.findtext("pubDate")
                    try:
                        when = email.utils.parsedate_to_datetime(date).timestamp() if date else None
                    except (TypeError, ValueError):
                        when = None
                    headlines.append({"title": item.findtext("title") or "", "link": item.findtext("link") or "",
                                      "source": item.findtext("source") or "", "time": when})
                headlines.sort(key=lambda h: -(h["time"] or 0))
                del headlines[40:]
            except Exception:
                problems.append("tin tức")
            result = {"ok": True, "events": events, "headlines": headlines,
                      "error": "Không tải được " + " và ".join(problems) if problems else ""}
            if not problems or not self.cache:
                self.cache = result
            # A failed fetch is tried again after a minute.
            self.time = now() if not problems else now() - 840
            return self.cache


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

    def chart_symbol(self):
        """The gold symbol of the owner's MT5 account (XAUUSDm on Exness Standard)."""
        with self.lock:
            for s in self.items:
                if "XAU" in s["symbol"].upper():
                    return s["symbol"]
        cached = getattr(self, "_chart_symbol", None)
        if cached:
            return cached
        with Mt5.lock:
            mt5 = Mt5.connect(self.server.config["mt5"])
            for name in ("XAUUSDm", "XAUUSD", "XAUUSD.r", "XAUUSDc", "GOLD"):
                if mt5.symbol_info(name) is not None:
                    self._chart_symbol = name
                    return name
        raise ValueError("Tài khoản không có mã vàng")

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


class WebAccount:
    """The website's own MT5 account: a second copy of this server (`--instance web`) on the next port, with
    its own portable MT5 terminal (terminals/web), its own login, bots and tunnel. The app keeps the main
    server and its account; a computer that turns "Tài khoản riêng" on talks to the second one."""

    def __init__(self, server):
        self.server = server
        self.process = None
        self.error = ""
        if self.cfg.get("enabled") and not INSTANCE:
            threading.Thread(target=self._supervise, daemon=True).start()

    @property
    def cfg(self):
        return self.server.config.setdefault("webAccount", {"enabled": False})

    @property
    def port(self):
        return int(self.server.config.get("port", 8787)) + 1

    def _local(self, path, body=None, timeout=5):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=json.dumps(body).encode() if body is not None else None,
                                     headers={"Authorization": "Bearer " + self.server.config["password"], "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8") or "{}")

    def _write_config(self):
        """The instance's config: this one's, on the next port, with the web terminal and nothing shared that
        must run once (Telegram, copy trading, members)."""
        main = self.server.config
        path = os.path.join(HERE, "web.config.json")
        cfg = read_json(path, {}) or {}
        exe = clone_terminal("web", main["mt5"])
        mt5 = dict(cfg.get("mt5") or {})
        mt5.update({"path": exe, "portable": True})
        for k in ("trading_enabled", "max_lots", "deviation"):
            mt5.setdefault(k, main["mt5"].get(k))
        cfg.update({"password": main["password"], "port": self.port, "mt5": mt5, "tunnel": main.get("tunnel"),
                    "cloudflared": main.get("cloudflared", ""), "url_relay": "", "telegram": {}, "copy": {}, "members": [],
                    "webAccount": {"enabled": False}})
        write_json(path, cfg)

    def _spawn(self):
        try:
            self._local("/shutdown", {})  # an older copy (before an update): out of the way
            time.sleep(3)
        except Exception:
            pass
        self._write_config()
        args = [sys.executable, os.path.join(HERE, "bot_server.py"), "--instance", "web"]
        if "--public" in sys.argv:
            args.append("--public")
        self.process = subprocess.Popen(args, cwd=HERE, creationflags=NO_WINDOW,
                                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.server.log(f"🖥️ Tài khoản riêng cho máy tính: đã chạy máy chủ thứ 2 (cổng {self.port})")

    def _supervise(self):
        while self.cfg.get("enabled"):
            try:
                if self.process is None or self.process.poll() is not None:
                    self._spawn()
                self.error = ""
            except Exception as e:
                self.error = str(e)
            time.sleep(15)
        self.stop()

    def stop(self):
        try:
            self._local("/shutdown", {})
        except Exception:
            pass
        if self.process and self.process.poll() is None:
            try:
                self.process.terminate()
            except OSError:
                pass
        self.process = None

    def url(self):
        try:
            return open(os.path.join(HERE, "web.tunnel.txt"), encoding="utf-8").read().strip()
        except OSError:
            return ""

    def status(self):
        running, info = False, {}
        if self.cfg.get("enabled"):
            try:
                st = self._local("/status", timeout=3)
                running = True
                info = {"version": st.get("version"), "mt5": st.get("mt5"), "url": st.get("tunnelURL") or self.url()}
            except Exception:
                pass
        return {"enabled": bool(self.cfg.get("enabled")), "running": running, "port": self.port,
                "url": info.get("url") or (self.url() if running else ""), "info": info, "error": self.error}

    def settings(self, body):
        on = bool(body.get("enabled"))
        was = bool(self.cfg.get("enabled"))
        self.cfg["enabled"] = on
        self.server.save_config()
        if on and not was:
            threading.Thread(target=self._supervise, daemon=True).start()
        if not on and was:
            self.stop()
            self.server.log("🖥️ Đã tắt tài khoản riêng cho máy tính")
        return self.status()


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
        # The VPS demo account's SL / TP at every MT5 tick, not only at the bot's 2-second poll.
        self.tick_symbol = None
        self.mt5_account.ticks.add_listener(self._on_tick)
        self.copier = CopyTrader(self)
        self.members = Members(self)
        self.news = NewsFeed()
        self.stopbot = StopBot(self)
        self.srbot = SRBot(self)
        self.tickbot = TickBot(self)
        self.gridbot = GridBot(self)
        self.web_account = WebAccount(self)
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
            with open(own("tunnel.txt"), "w", encoding="utf-8") as f:
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
            if body.get("sampleStrategy") and "strategy" not in body:
                # A sample picked on the website replaces the strategy sent by the app.
                s.update(strategy=None, indicators=[], config=None, parameterValues={},
                         strategyName=str(body["sampleStrategy"]))
            if not s.get("strategy") and not body.get("sampleStrategy") and not s.get("sampleStrategy"):
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
            self._watch_ticks(symbol if s.get("source") == "mt5" and getattr(self.broker, "name", "") == "paper"
                              and self.broker.positions(symbol) else None)
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

    def _watch_ticks(self, symbol):
        """Keeps the MT5 tick stream on the symbol whose demo positions are open (or none)."""
        if symbol == self.tick_symbol:
            return
        if self.tick_symbol:
            self.mt5_account.ticks.unwatch(self.tick_symbol)
        if symbol:
            self.mt5_account.ticks.watch(symbol)
        self.tick_symbol = symbol

    def _on_tick(self, symbol, bid, ask):
        """An MT5 tick: the demo positions on it hit their SL / TP (and trail) at once."""
        if symbol != self.tick_symbol or getattr(self.broker, "name", "") != "paper":
            return
        if not self.lock.acquire(timeout=0.2):
            return  # the bot's own poll is busy with them right now
        try:
            if not self.broker.positions(symbol):
                return
            self.prices[symbol] = bid
            events = self.broker.on_price(symbol, bid)
            rules = self.settings.get("rules") or {}
            for p in self.broker.positions(symbol):
                stop = improved_stop(p, rules)
                if stop is not None:
                    events += self.broker.set_stop(p["id"], stop)
            for event in events:
                self.report(event)
            if events:
                self.save_state()
        finally:
            self.lock.release()

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
                    "error": self.error, "tunnelURL": self.tunnel_url, "startedAt": self.started_at, "instance": INSTANCE,
                    "webAccount": None if INSTANCE else self.web_account.status(),
                    "account": account, "positions": positions,
                    "telegram": {"configured": bool(self.telegram.token), "linked": bool(self.telegram.chat_id)},
                    "mt5": {"error": Mt5.error, "connected": Mt5.connected, "tradingEnabled":
                            bool(self.config["mt5"].get("trading_enabled")), "maxLots": self.config["mt5"].get("max_lots")}}

    def bots(self, local=False):
        """Every bot at once (for the app's bot screen): its settings, open positions, numbers and closed
        trades; with the computer's own account on, its bots too ("own")."""
        out = {"ok": True, "version": VERSION, "instance": INSTANCE,
               "tick": self.tickbot.status(), "grid": self.gridbot.status(), "sr": self.srbot.status(), "stop": self.stopbot.status()}
        st = self.status()
        with self.lock:
            try:
                hist = self.broker.history()[:100]
            except Exception:
                hist = []
        out["strategy"] = {"running": st["running"], "settings": st["settings"], "account": st["account"],
                           "positions": st["positions"], "history": hist}
        if not local and not INSTANCE and self.web_account.cfg.get("enabled"):
            try:
                out["own"] = self.web_account._local("/bots?local=1", timeout=10)
            except Exception as e:
                out["own"] = {"ok": False, "error": str(e)}
        return out

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
        if INSTANCE:
            # The second copy: the main server updates the files and starts this one again.
            port = int(self.config.get("port", 8788)) - 1
            req = urllib.request.Request(f"http://127.0.0.1:{port}/update", data=b"{}",
                                         headers={"Authorization": "Bearer " + self.config["password"], "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=240) as r:
                return json.loads(r.read().decode("utf-8") or "{}")
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

        def _cors(self):
            """The website (another origin) calls the server too: members with their code,
            the owner with the password. Nothing works without one of them."""
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Max-Age", "600")

        def _send(self, code, payload):
            data = json.dumps(payload, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self._cors()
            self.end_headers()
            self.wfile.write(data)

        def do_OPTIONS(self):
            # Browser preflight for the members' web page.
            self.send_response(204)
            self._cors()
            self.send_header("Content-Length", "0")
            self.end_headers()

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

        def _stream_ticks(self, symbol):
            """Server-sent events: one "data: {bid, ask, time}" line per MT5 tick of `symbol`, a comment every
            10 s so the tunnel keeps the stream open. Ends when the client goes."""
            if not symbol:
                return self._send(400, {"ok": False, "error": "Thiếu mã"})
            hub = server.mt5_account.ticks
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Accel-Buffering", "no")
            self.send_header("Transfer-Encoding", "chunked")
            self._cors()
            self.end_headers()
            self.close_connection = True

            def chunk(text):
                data = text.encode()
                self.wfile.write(b"%x\r\n%s\r\n" % (len(data), data))

            hub.watch(symbol)
            seq = 0
            try:
                chunk(": open\n\n")
                while True:
                    tick = hub.wait(symbol, seq, 10)
                    if tick is None:
                        chunk(": ping\n\n")
                        continue
                    seq = tick["seq"]
                    chunk("data: " + json.dumps({"symbol": symbol, "bid": tick["bid"], "ask": tick["ask"],
                                                 "time": tick["time"]}) + "\n\n")
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
                pass
            finally:
                hub.unwatch(symbol)

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
                    if path == "/member/news":
                        if not server.members.features["news"]:
                            raise PermissionError("Tin tức chưa được mở cho thành viên")
                        return self._send(200, server.news.get())
                    if path == "/member/ticks":
                        return self._stream_ticks(server.members.chart_symbol())
                    if path == "/member/candles":
                        # Exness (MT5) bars of the signals' symbol, for the members' web chart.
                        symbol = server.members.chart_symbol()
                        if (params.get("symbol") or [""])[0] == "compare":
                            # The SMT pair of the second chart: silver for gold, S&P 500 for Nasdaq, ETH for BTC…
                            symbol = smt_pair(symbol)
                        data = server.mt5_account.candles(symbol, (params.get("interval") or ["1m"])[0],
                                                          min(int((params.get("count") or ["500"])[0]), 1000),
                                                          (params.get("before") or [None])[0])
                        return self._send(200, dict(data, symbol=symbol))
                    return self._send(404, {"ok": False, "error": "Không có đường dẫn này"})
                if path == "/members":
                    return self._send(200, server.members.list())
                if path == "/news":
                    return self._send(200, server.news.get())
                if path == "/stopbot":
                    return self._send(200, server.stopbot.status())
                if path == "/srbot":
                    return self._send(200, server.srbot.status())
                if path == "/tickbot":
                    return self._send(200, server.tickbot.status())
                if path == "/gridbot":
                    return self._send(200, server.gridbot.status())
                if path == "/webacct":
                    return self._send(200, server.web_account.status())
                if path == "/bots":
                    return self._send(200, server.bots(local=(params.get("local") or [""])[0] == "1"))
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
                if path == "/mt5/accounts":
                    return self._send(200, server.mt5_account.accounts())
                if path == "/drawings":
                    return self._send(200, drawings_get((params.get("symbol") or [""])[0]))
                if path == "/mt5/symbols":
                    return self._send(200, server.mt5_account.symbols((params.get("q") or [""])[0], limit))
                if path == "/copy/status":
                    return self._send(200, server.copier.status())
                if path == "/mt5/history":
                    end = float((params.get("to") or [now()])[0])
                    start = float((params.get("from") or [end - 86400])[0])
                    return self._send(200, server.mt5_account.history(start, end))
                if path == "/mt5/ticks":
                    return self._stream_ticks((params.get("symbol") or [""])[0])
                if path == "/mt5/trading":
                    symbol = (params.get("symbol") or [None])[0]
                    return self._send(200, server.mt5_account.trading(symbol))
                if path == "/mt5/ticks":
                    return self._send(200, server.mt5_account.ticks((params.get("symbol") or [""])[0],
                                                                    (params.get("from") or ["0"])[0], (params.get("to") or ["0"])[0]))
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
                if path == "/stopbot":
                    return self._send(200, server.stopbot.settings(body))
                if path == "/srbot":
                    return self._send(200, server.srbot.settings(body))
                if path == "/tickbot":
                    return self._send(200, server.tickbot.settings(body))
                if path == "/gridbot":
                    return self._send(200, server.gridbot.settings(body))
                if path == "/webacct":
                    if INSTANCE:
                        raise ValueError("Bật / tắt ở máy chủ chính")
                    return self._send(200, server.web_account.settings(body))
                if path == "/shutdown" and INSTANCE:
                    self._send(200, {"ok": True})
                    server.save_state()
                    if server.tunnel:
                        server.tunnel.stop()
                    threading.Thread(target=lambda: (time.sleep(0.5), os._exit(0)), daemon=True).start()
                    return
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
                if path == "/mt5/switch":
                    return self._send(200, server.mt5_account.switch(body))
                if path == "/mt5/remember":
                    return self._send(200, server.mt5_account.remember(body))
                if path == "/drawings":
                    return self._send(200, drawings_save(body))
                if path == "/mt5/forget":
                    return self._send(200, server.mt5_account.forget(body))
                if path == "/mt5/settings":
                    return self._send(200, server.mt5_account.settings(body))
                if path == "/mt5/order":
                    return self._send(200, server.mt5_account.order(body))
                if path == "/mt5/close":
                    return self._send(200, server.mt5_account.close(body))
                if path == "/mt5/close_all":
                    return self._send(200, server.mt5_account.close_all(body))
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
    global INSTANCE, CONFIG_PATH, STATE_PATH, STOPS_PATH, LOG_PATH, TICK_PAPER_PATH, GRID_PAPER_PATH
    if "--copy-worker" in sys.argv:
        return copy_worker_main()
    if "--instance" in sys.argv:
        # The website's own account: every file of its own ("web.config.json"…).
        INSTANCE = re.sub(r"[^a-z0-9]", "", sys.argv[sys.argv.index("--instance") + 1].lower()) or "web"
        CONFIG_PATH, STATE_PATH, STOPS_PATH, LOG_PATH = own("config.json"), own("state.json"), own("stops.json"), own("server.log")
        TICK_PAPER_PATH = own("tickbot_paper.json")
        GRID_PAPER_PATH = own("gridbot_paper.json")
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
