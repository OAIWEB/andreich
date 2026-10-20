#!/usr/bin/env python3
"""Лимиты Claude: недельный остаток и дневная норма.

Берёт те же цифры, что показывает /usage: токен подписки лежит в связке ключей
(элемент «Claude Code-credentials»), данные — в https://api.anthropic.com/api/oauth/usage.

Дневная норма: остаток недели минус резерв на конец, делённый на число оставшихся
суток. Сутки и неделя считаются от 6 утра понедельника — когда сбрасывается лимит.

  usage.py          → JSON с состоянием (для приложения)
  usage.py --line   → одна строка (для статусной строки Claude Code)
  usage.py --fresh  → не брать из кэша, спросить сервер
"""
import json
import math
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta

SUPPORT = os.path.expanduser("~/Library/Application Support/AndreichNotch")
CACHE = os.path.join(SUPPORT, "usage.json")
LEDGER = os.path.join(SUPPORT, "usage-day.json")
TTL = 90                  # сколько секунд кэш считается свежим
RESERVE = 4.0             # сколько % недельных оставляем на воскресенье (просил 3–5)
DAY_START_HOUR = 6        # граница суток и недели — 6 утра
URL = "https://api.anthropic.com/api/oauth/usage"


def token():
    out = subprocess.run(["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                         capture_output=True, text=True, timeout=20)
    if out.returncode != 0:
        raise RuntimeError("нет доступа к связке ключей")
    return json.loads(out.stdout)["claudeAiOauth"]["accessToken"]


def fetch():
    req = urllib.request.Request(URL, headers={
        "Authorization": "Bearer " + token(),
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-cli/2.1.302 (external, cli)",
    })
    with urllib.request.urlopen(req, timeout=15) as r:
        d = json.loads(r.read().decode())
    five, week = d.get("five_hour") or {}, d.get("seven_day") or {}
    snap = {
        "fetched_at": time.time(),
        "five_hour": float(five.get("utilization") or 0),
        "five_hour_resets_at": five.get("resets_at"),
        "weekly": float(week.get("utilization") or 0),
        "weekly_resets_at": week.get("resets_at"),
    }
    os.makedirs(SUPPORT, exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(snap, f)
    os.replace(tmp, CACHE)
    return snap


def cached():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except Exception:
        return None


def snapshot(force=False):
    c = cached()
    if not force and c and time.time() - c.get("fetched_at", 0) < TTL:
        return c, False
    try:
        return fetch(), False
    except Exception as e:
        if c:
            return c, True          # сервер молчит — показываем последнее известное
        raise e


def day_start(now):
    s = now.replace(hour=DAY_START_HOUR, minute=0, second=0, microsecond=0)
    return s if now >= s else s - timedelta(days=1)


def ledger(weekly, start, days_left, now):
    """Помнит, с какого уровня начался день, чтобы знать расход за сегодня."""
    key = start.isoformat()
    try:
        with open(LEDGER) as f:
            d = json.load(f)
    except Exception:
        d = {}
    last = d.get("last") or {}
    # новый день или неделя сброшена (процент упал)
    if d.get("day_start") != key or weekly + 0.01 < d.get("start_weekly", 1e9):
        # если Мак спал и последнее наблюдение было ещё вчера — оно и есть уровень на утро
        base = weekly
        if last.get("ts", 0) < start.timestamp() and last.get("weekly") is not None and last["weekly"] <= weekly:
            base = last["weekly"]
        d = {"day_start": key, "start_weekly": base, "days_left": days_left}
    d["last"] = {"weekly": weekly, "ts": now.timestamp()}
    os.makedirs(SUPPORT, exist_ok=True)
    tmp = LEDGER + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, LEDGER)
    return d


def human(delta):
    s = max(0, int(delta.total_seconds()))
    d, h, m = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
    if d:
        return f"{d}д {h}ч"
    if h:
        return f"{h}ч {m}м"
    return f"{m}м"


def state(force=False):
    snap, stale = snapshot(force)
    now = datetime.now().astimezone()
    weekly = snap["weekly"]
    reset = datetime.fromisoformat(snap["weekly_resets_at"]).astimezone() if snap.get("weekly_resets_at") else None
    start = day_start(now)
    span = (reset - start).total_seconds() if reset else 7 * 86400
    days_left = max(1, math.ceil((span - 60) / 86400))      # минута допуска: сброс ровно в 6:00
    led = ledger(weekly, start, days_left, now)

    budget = max(0.0, (100.0 - led["start_weekly"] - RESERVE) / led.get("days_left", days_left))
    spent = max(0.0, weekly - led["start_weekly"])
    left = budget - spent
    if left <= 0:
        st = "over"
    elif left < budget * 0.3:
        st = "warn"
    else:
        st = "ok"

    five_reset = datetime.fromisoformat(snap["five_hour_resets_at"]).astimezone() if snap.get("five_hour_resets_at") else None
    return {
        "weekly_used": round(weekly, 1),
        "weekly_left": round(100 - weekly, 1),
        "week_resets_in": human(reset - now) if reset else "",
        "week_resets_at": reset.isoformat() if reset else "",
        "five_hour_used": round(snap["five_hour"], 1),
        "five_hour_resets_in": human(five_reset - now) if five_reset else "",
        "day_budget": round(budget, 1),
        "day_spent": round(spent, 1),
        "day_left": round(left, 1),
        "day_fill": round(min(1.0, spent / budget), 3) if budget > 0 else 1.0,
        "days_left": led.get("days_left", days_left),
        "reserve": RESERVE,
        "state": st,
        "stale": stale,
        "age": round(time.time() - snap.get("fetched_at", 0)),
    }


def line(s):
    mark = {"ok": "", "warn": "⚠ ", "over": "⛔ "}[s["state"]]
    tail = " · данные старые" if s["stale"] else ""
    return (f"{mark}недели осталось {s['weekly_left']:.0f}% · сегодня можно ещё {max(0.0, s['day_left']):.1f}%"
            f" из {s['day_budget']:.1f}% · сброс через {s['week_resets_in']}{tail}")


def background_refresh():
    """Обновляем кэш отдельным процессом — статусная строка не ждёт сеть."""
    try:
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "--fresh"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except Exception:
        pass


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--bg" in args:                      # для статусной строки: только кэш, обновление в фоне
        c = cached()
        if not c or time.time() - c.get("fetched_at", 0) >= TTL:
            background_refresh()
        if not c:
            print("лимиты: считаю…" if "--line" in args else json.dumps({"error": "кэш пуст"}, ensure_ascii=False))
            sys.exit(0)
        globals()["TTL"] = 10 ** 9          # этот запуск в сеть не ходит
    try:
        s = state(force="--fresh" in args)
    except Exception as e:
        if "--line" in args:
            print(f"лимиты недоступны: {e}")
        else:
            print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(0)
    print(line(s) if "--line" in args else json.dumps(s, ensure_ascii=False))
