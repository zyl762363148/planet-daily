#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""行星日报：抓取微博热搜与知乎热榜公开榜单，作为「全网热榜」写入当日 JSON。

榜单是实时快照：每次生成（含滚动增量）都重新抓取；单个来源失败时沿用
当天已写入的旧快照并在日志中记录，绝不编造词条。只读取公开接口，
不携带任何账号凭据；发送的只有普通浏览器请求头。
"""

import json
import os
import re
import subprocess
import tempfile
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

BASE_DATA_ROOT = Path(
    os.environ.get(
        "DIGEST_DATA_ROOT",
        str(Path.home() / "Library" / "Application Support" / "DailyDigest"),
    )
)
DATA_DIR = BASE_DATA_ROOT / "data"

HOTLIST_LIMIT = 20
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0 Safari/537.36"
)

# 「爆」「沸」等标签按热度从高到低排序，一条词条只保留最高一级。
WEIBO_LABEL_RANK = {"爆": 4, "沸": 3, "热": 2, "新": 1, "荐": 0}
# 抖音 label 数字 → 平台标签
DOUYIN_LABELS = {1: "新", 2: "热", 3: "爆"}


def log(message: str) -> None:
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {message}", flush=True)


def format_heat(value) -> str:
    """微博原始热度是次数：1148327 → 114.8万。"""
    try:
        number = int(value)
    except (TypeError, ValueError):
        return ""
    if number <= 0:
        return ""
    if number >= 100_000_000:
        return f"{number / 100_000_000:.1f}亿"
    if number >= 10_000:
        return f"{number / 10_000:.1f}万"
    return str(number)


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _curl_json(url: str, cookie_args: list = None, referer: str = "") -> dict:
    command = [
        "/usr/bin/curl",
        "-sL",
        "--compressed",
        "--max-time", "18",
        "--connect-timeout", "8",
        "--noproxy", "*",
        "-A", USER_AGENT,
        "-H", "Accept: application/json, text/plain, */*",
    ]
    if referer:
        command.extend(["-H", f"Referer: {referer}"])
    if cookie_args:
        command.extend(cookie_args)
    command.append(url)
    result = subprocess.run(command, capture_output=True, timeout=26)
    if result.returncode != 0:
        raise OSError(f"curl {result.returncode}")
    payload = json.loads(result.stdout.decode("utf-8", errors="replace"))
    if not isinstance(payload, dict):
        raise ValueError("响应不是 JSON 对象")
    return payload


def fetch_weibo_hot() -> dict:
    """微博热搜需要先访问首页取得访客 Cookie，再请求热搜接口。"""
    with tempfile.TemporaryDirectory(prefix="weibo-cookie-") as work:
        jar = str(Path(work) / "cookies.txt")
        seed = subprocess.run(
            ["/usr/bin/curl", "-s", "--max-time", "12", "--connect-timeout", "8",
             "--noproxy", "*", "-A", USER_AGENT, "-c", jar, "-o", os.devnull,
             "https://weibo.com/"],
            capture_output=True, timeout=18,
        )
        if seed.returncode != 0:
            raise OSError(f"微博首页预热失败：curl {seed.returncode}")
        payload = _curl_json(
            "https://weibo.com/ajax/side/hotSearch",
            cookie_args=["-b", jar],
            referer="https://weibo.com/",
        )
    if payload.get("ok") != 1:
        raise ValueError(f"微博热搜接口返回异常：{str(payload)[:120]}")

    rows = payload.get("data", {}).get("realtime") or []
    items, seen = [], set()
    for row in rows:
        if row.get("is_ad") or row.get("realpos") is None:
            continue
        title = (row.get("note") or row.get("word") or "").strip()
        if not title or title in seen:
            continue
        seen.add(title)
        query = row.get("word_scheme") or title
        url = "https://s.weibo.com/weibo?q=" + urllib.parse.quote(query)
        label = (row.get("label_name") or row.get("icon_desc") or "").strip()
        if label not in WEIBO_LABEL_RANK:
            label = ""
        items.append(
            {
                "title": title[:80],
                "url": url,
                "heat": format_heat(row.get("num")),
                "label": label,
            }
        )
        if len(items) >= HOTLIST_LIMIT:
            break
    if not items:
        raise ValueError("微博热搜没有可用词条")
    return {"id": "weibo", "name": "微博热搜", "updated_at": now_iso(), "items": items}


def fetch_zhihu_hot() -> dict:
    payload = _curl_json("https://api.zhihu.com/topstory/hot-list?limit=50")
    rows = payload.get("data") or []
    items, seen = [], set()
    for row in rows:
        target = row.get("target") or {}
        title = (target.get("title") or "").strip()
        if not title or title in seen:
            continue
        seen.add(title)
        api_url = (target.get("url") or "").strip()
        match = re.search(r"questions/(\d+)", api_url)
        url = f"https://www.zhihu.com/question/{match.group(1)}" if match else api_url
        if not url.startswith("http"):
            continue
        heat = str(row.get("detail_text") or "").replace("热度", "").replace(" ", "").strip()
        answers = target.get("answer_count")
        if not heat and answers:
            heat = format_heat(answers) + " 回答"
        items.append({"title": title[:100], "url": url, "heat": heat, "label": ""})
        if len(items) >= HOTLIST_LIMIT:
            break
    if not items:
        raise ValueError("知乎热榜没有可用词条")
    return {"id": "zhihu", "name": "知乎热榜", "updated_at": now_iso(), "items": items}


def fetch_douyin_hot() -> dict:
    payload = _curl_json("https://www.iesdouyin.com/web/api/v2/hotsearch/billboard/word/")
    rows = payload.get("word_list") or []
    items, seen = [], set()
    for row in rows:
        title = str(row.get("word") or "").strip()
        if not title or title in seen:
            continue
        seen.add(title)
        label = DOUYIN_LABELS.get(row.get("label"), "")
        query = urllib.parse.quote(title)
        items.append(
            {
                "title": title[:80],
                "url": f"https://www.douyin.com/search/{query}",
                "heat": format_heat(row.get("hot_value")),
                "label": label if label in WEIBO_LABEL_RANK else "",
            }
        )
        if len(items) >= HOTLIST_LIMIT:
            break
    if not items:
        raise ValueError("抖音热点没有可用词条")
    return {"id": "douyin", "name": "抖音热点", "updated_at": now_iso(), "items": items}


def fetch_baidu_hot() -> dict:
    payload = _curl_json("https://top.baidu.com/api/board?platform=wise&tab=realtime")
    cards = (payload.get("data") or {}).get("cards") or []
    items, seen = [], set()

    def walk(node):
        if isinstance(node, list):
            for child in node:
                walk(child)
        elif isinstance(node, dict):
            word = str(node.get("word") or "").strip()
            if word and word not in seen:
                seen.add(word)
                url = str(node.get("url") or "").strip()
                items.append(
                    {
                        "title": word[:80],
                        "url": url or ("https://www.baidu.com/s?wd=" + urllib.parse.quote(word)),
                        "heat": format_heat(node.get("hot_score")),
                        "label": "",
                    }
                )
            else:
                for key in ("content", "cards"):
                    if key in node:
                        walk(node[key])

    for card in cards:
        walk(card)
    if not items:
        raise ValueError("百度热搜没有可用词条")
    return {"id": "baidu", "name": "百度热搜", "updated_at": now_iso(), "items": items[:HOTLIST_LIMIT]}


FETCHERS = {
    "weibo": fetch_weibo_hot,
    "zhihu": fetch_zhihu_hot,
    "douyin": fetch_douyin_hot,
    "baidu": fetch_baidu_hot,
}
SOURCE_ORDER = ("weibo", "zhihu", "douyin", "baidu")


def collect_hotlists(existing: dict = None) -> dict:
    """抓取全部来源；失败时沿用当天旧快照（快照自带 updated_at，UI 会如实标注）。"""
    existing = existing if isinstance(existing, dict) else {}
    existing_by_id = {
        source.get("id"): source
        for source in existing.get("sources", [])
        if isinstance(source, dict) and source.get("id")
    }
    merged = existing.get("sources", []) if isinstance(existing.get("sources"), list) else []
    merged_by_id = {source.get("id"): source for source in merged if isinstance(source, dict)}

    result = dict(merged_by_id)
    for source_id, fetcher in FETCHERS.items():
        try:
            result[source_id] = fetcher()
            log(f"热榜 {source_id} 获取 {len(result[source_id]['items'])} 条")
        except Exception as exc:
            stale = existing_by_id.get(source_id)
            if stale and stale.get("items"):
                result[source_id] = stale
                log(f"热榜 {source_id} 抓取失败，沿用当天快照：{exc}")
            else:
                result.pop(source_id, None)
                log(f"热榜 {source_id} 抓取失败：{exc}")
    ordered = [result[key] for key in SOURCE_ORDER if key in result]
    return {"updated_at": now_iso(), "sources": ordered}


def load_previous_hotlists(date_text: str, lookback_days: int = 7, data_dir: Path = None) -> dict:
    """向前找最近一期带热榜的归档（通常是昨天），用于计算位次趋势。"""
    data_dir = data_dir or DATA_DIR
    try:
        day = datetime.strptime(date_text, "%Y-%m-%d").date()
    except ValueError:
        return {}
    for offset in range(1, lookback_days + 1):
        target = day - timedelta(days=offset)
        path = data_dir / f"{target:%Y-%m-%d}.json"
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        hotlists = payload.get("hotlists")
        if isinstance(hotlists, dict) and hotlists.get("sources"):
            return hotlists
    return {}


def annotate_trends(board: dict, date_text: str, data_dir: Path = None) -> dict:
    """给每个词条补 prev_rank（上一期名次）；上期未上榜的词条不写字段。"""
    previous = load_previous_hotlists(date_text, data_dir=data_dir)
    if not previous:
        return board
    for source in board.get("sources") or []:
        source_id = source.get("id")
        prev_source = next(
            (s for s in previous.get("sources", []) if isinstance(s, dict) and s.get("id") == source_id),
            None,
        )
        prev_rank: dict = {}
        for index, item in enumerate((prev_source or {}).get("items") or []):
            title = str(item.get("title") or "").strip()
            if title and title not in prev_rank:
                prev_rank[title] = index + 1
        for index, item in enumerate(source.get("items") or []):
            title = str(item.get("title") or "").strip()
            if title and title in prev_rank:
                item["prev_rank"] = prev_rank[title]
    return board


def load_existing_hotlists(date_text: str, data_dir: Path = None) -> dict:
    """从当天（或 latest）JSON 读出旧热榜，用于失败兜底。"""
    data_dir = data_dir or (BASE_DATA_ROOT / "data")
    for name in (date_text, "latest"):
        path = data_dir / f"{name}.json"
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if payload.get("date") == date_text:
            hotlists = payload.get("hotlists")
            if isinstance(hotlists, dict):
                return hotlists
    return {}
