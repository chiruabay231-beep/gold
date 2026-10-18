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

VERSION = "1.0"
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


class Mt5Feed:
    def __init__(self, cfg, symbol, interval):
        self.cfg = cfg
        self.symbol = symbol
        mt5 = Mt5.connect(cfg)
        names = {"1m": "M1", "5m": "M5", "15m": "M15", "30m": "M30", "1h": "H1", "4h": "H4", "1d": "D1"}
        self.timeframe = getattr(mt5, "TIMEFRAME_" + names[interval])
        if not mt5.symbol_select(symbol, True):
            raise RuntimeError(f"MT5 không có mã {symbol} (Exness thường là XAUUSDm hoặc XAUUSD)")

    def _rates(self, count):
        mt5 = Mt5.connect(self.cfg)
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, count)
        if rates is None:
            raise RuntimeError(f"MT5 copy_rates lỗi: {mt5.last_error()}")
        return [[float(r["time"]), float(r["open"]), float(r["high"]), float(r["low"]), float(r["close"]),
                 float(r["tick_volume"])] for r in rates]

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


# --------------------------------------------------------------------------
# Brokers. Positions use the app's PaperAccount.Position field names.
# Events: ("opened", pos) ("closed", trade) ("stopMoved", pos) ("error", text)
# ("skip", text): a signal that was not traded, logged without a notification.
# --------------------------------------------------------------------------

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
        info = self.mt5.symbol_info(request["symbol"])
        modes = []
        if info is not None:
            if info.filling_mode & 1:
                modes.append(self.mt5.ORDER_FILLING_FOK)
            if info.filling_mode & 2:
                modes.append(self.mt5.ORDER_FILLING_IOC)
        modes.append(self.mt5.ORDER_FILLING_RETURN)
        result = None
        for mode in modes:
            request["type_filling"] = mode
            result = self.mt5.order_send(request)
            if result is not None and result.retcode != self.mt5.TRADE_RETCODE_INVALID_FILL:
                break
        if result is None:
            return None, f"order_send lỗi: {self.mt5.last_error()}"
        if result.retcode not in (self.mt5.TRADE_RETCODE_DONE, self.mt5.TRADE_RETCODE_PLACED):
            return None, f"MT5 từ chối ({result.retcode}): {result.comment}"
        return result, None

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

    def _run(self):
        port = int(self.server.config.get("port", 8787))
        while True:
            try:
                self.process = subprocess.Popen(
                    [self._binary(), "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{port}"],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, creationflags=NO_WINDOW)
            except FileNotFoundError:
                self.error = "Không tìm thấy cloudflared"
                return
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
        self.telegram = Telegram(self)
        self.tunnel = Tunnel(self) if self.config.get("tunnel") else None

    # ----- persistence -----

    def save_config(self):
        write_json(CONFIG_PATH, self.config)

    def save_state(self):
        with self.lock:
            write_json(STATE_PATH, {"settings": self.settings, "paper": self.paper, "mt5Memory": self.mt5_memory,
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
        with self.lock:
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

        def _authorized(self):
            header = self.headers.get("Authorization", "")
            given = header[7:] if header.startswith("Bearer ") else self.headers.get("X-Bot-Password", "")
            if given and hmac.compare_digest(given.encode(), server.config["password"].encode()):
                failures["count"] = 0
                return True
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
            if not self._authorized():
                return
            try:
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
                self._send(404, {"ok": False, "error": "Không có đường dẫn này"})
            except Exception as e:
                self._send(500, {"ok": False, "error": str(e)})

        def do_POST(self):
            path = self.path.partition("?")[0]
            if not self._authorized():
                return
            try:
                body = self._body()
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
                if path == "/telegram-test":
                    server.telegram.send("🔔 Thử thông báo từ máy chủ bot")
                    return self._send(200, {"ok": True})
                self._send(404, {"ok": False, "error": "Không có đường dẫn này"})
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
    if "--selftest" in sys.argv:
        sys.exit(selftest())
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
