#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""行星日报：抓取 NBA 赛程与比分（ESPN 公开接口，无需密钥），作为「赛事」页签与播报战报的数据。

只读公开接口；按美东日历取今天与昨天两天的赛程，合并出：进行中、昨夜战报、今日赛程
三类（北京时间显示）。单源失败整体降级为空，不阻塞日报。
"""

import json
import os
import re
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

BASE_DATA_ROOT = Path(
    os.environ.get(
        "DIGEST_DATA_ROOT",
        str(Path.home() / "Library" / "Application Support" / "DailyDigest"),
    )
)

ESPN_URL = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"
USER_AGENT = "DailyDigest/2.1"

TEAM_NAMES_ZH = {
    "Atlanta Hawks": "老鹰", "Boston Celtics": "凯尔特人", "Brooklyn Nets": "篮网",
    "Charlotte Hornets": "黄蜂", "Chicago Bulls": "公牛", "Cleveland Cavaliers": "骑士",
    "Dallas Mavericks": "独行侠", "Denver Nuggets": "掘金", "Detroit Pistons": "活塞",
    "Golden State Warriors": "勇士", "Houston Rockets": "火箭", "Indiana Pacers": "步行者",
    "LA Clippers": "快船", "Los Angeles Clippers": "快船", "Los Angeles Lakers": "湖人",
    "Memphis Grizzlies": "灰熊", "Miami Heat": "热火", "Milwaukee Bucks": "雄鹿",
    "Minnesota Timberwolves": "森林狼", "New Orleans Pelicans": "鹈鹕", "New York Knicks": "尼克斯",
    "Oklahoma City Thunder": "雷霆", "Orlando Magic": "魔术", "Philadelphia 76ers": "76人",
    "Phoenix Suns": "太阳", "Portland Trail Blazers": "开拓者", "Sacramento Kings": "国王",
    "San Antonio Spurs": "马刺", "Toronto Raptors": "猛龙", "Utah Jazz": "爵士",
    "Washington Wizards": "奇才",
}

QUARTER_ZH = {1: "第1节", 2: "第2节", 3: "第3节", 4: "第4节", 5: "加时", 6: "第二个加时"}


def log(message: str) -> None:
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {message}", flush=True)


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _et_dates(now: datetime) -> list:
    """美东日历的今天与昨天（NBA 赛程按美东日期归档）。"""
    et = now.astimezone(timezone(timedelta(hours=-5)))  # 11 月起 EST；夏令时偏差对取「今天+昨天」两天无实质影响
    return [et.date(), et.date() - timedelta(days=1)]


def _fetch_day(date_text: str) -> list:
    url = f"{ESPN_URL}?dates={date_text}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return payload.get("events") or []


def _zh_team(name: str) -> str:
    return TEAM_NAMES_ZH.get((name or "").strip(), (name or "").strip())


def _beijing_text(utc_iso: str) -> str:
    try:
        moment = datetime.fromisoformat(utc_iso.replace("Z", "+00:00")).astimezone(timezone(timedelta(hours=8)))
        return f"{moment.month}月{moment.day}日 {moment:%H:%M}"
    except ValueError:
        return ""


def _live_detail(short_detail: str) -> str:
    """ESPN 的 shortDetail（如 '10:18 - 2nd' / 'End of 3rd' / 'Halftime'）转中文。"""
    text = (short_detail or "").strip()
    match = re.match(r"(\d+:\d+)\s*-\s*(\d+)(?:st|nd|rd|th)", text)
    if match:
        quarter = QUARTER_ZH.get(int(match.group(2)), f"第{match.group(2)}节")
        return f"{quarter} {match.group(1)}"
    overtime = re.match(r"(\d+:\d+)\s*-\s*OT(\d*)", text)
    if overtime:
        suffix = overtime.group(2) or "1"
        return f"加时{overtime.group(1)}" if suffix == "1" else f"第{suffix}个加时 {overtime.group(1)}"
    if "End of" in text:
        match2 = re.search(r"End of (\d+)(?:st|nd|rd|th)", text)
        if match2:
            return f"{QUARTER_ZH.get(int(match2.group(1)), '第' + match2.group(1) + '节')}结束"
        return "节间"
    if "Halftime" in text:
        return "中场休息"
    return text or "进行中"


def build_games(events: list, now: datetime) -> list:
    """把 ESPN events 归一成结构化比赛；排序：进行中 → 最近完场 → 即将开始。"""
    games = []
    for event in events:
        competitions = event.get("competitions") or []
        if not competitions:
            continue
        competition = competitions[0]
        status = (competition.get("status") or {}).get("type") or {}
        state = status.get("state") or ""
        if state not in ("pre", "in", "post"):
            continue
        competitors = competition.get("competitors") or []
        away = next((c for c in competitors if c.get("homeAway") == "away"), None)
        home = next((c for c in competitors if c.get("homeAway") == "home"), None)
        if not away or not home:
            continue

        def score_of(competitor):
            try:
                return int(competitor.get("score"))
            except (TypeError, ValueError):
                return None

        games.append(
            {
                "away": _zh_team((away.get("team") or {}).get("displayName") or ""),
                "home": _zh_team((home.get("team") or {}).get("displayName") or ""),
                "away_score": score_of(away),
                "home_score": score_of(home),
                "state": state,
                "detail": _live_detail(status.get("shortDetail")) if state == "in" else (status.get("shortDetail") or ""),
                "start_text": _beijing_text(event.get("date") or ""),
                "start_utc": event.get("date") or "",
            }
        )

    live = [g for g in games if g["state"] == "in"]
    final = sorted(
        [g for g in games if g["state"] == "post" and g["start_utc"]],
        key=lambda g: g["start_utc"],
        reverse=True,
    )[:6]
    upcoming = sorted(
        [g for g in games if g["state"] == "pre" and g["start_utc"]],
        key=lambda g: g["start_utc"],
    )[:6]
    ordered = live + final + upcoming
    for game in ordered:
        game.pop("start_utc", None)
        if game["state"] != "in":
            game.pop("detail", None)
    return ordered


def fetch_nba(now: datetime = None) -> dict:
    now = now or datetime.now().astimezone()
    events = []
    seen_ids = set()
    for date in _et_dates(now):
        try:
            for event in _fetch_day(date.strftime("%Y%m%d")):
                if event.get("id") not in seen_ids:
                    seen_ids.add(event.get("id"))
                    events.append(event)
        except Exception as exc:
            log(f"NBA 赛程 {date} 抓取失败：{exc}")
    games = build_games(events, now)
    if not games:
        raise ValueError("NBA 赛程没有可用数据")
    log(f"NBA 赛程获取 {len(games)} 场")
    return {"updated_at": now_iso(), "games": games}


def collect_sports() -> dict:
    try:
        nba = fetch_nba()
    except Exception as exc:
        log(f"NBA 赛程抓取失败：{exc}")
        return {}
    return {"updated_at": now_iso(), "nba": nba}


if __name__ == "__main__":
    print(json.dumps(collect_sports(), ensure_ascii=False)[:600])
