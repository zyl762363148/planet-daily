#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""行星日报 · 统一配置层

前后端共用 `~/Library/Application Support/DailyDigest/config.json`：
- modules.catalog  栏目注册表（前端侧栏完全由它驱动，不再写死）
- modules.enabled  用户勾选的模块
- broadcast        语音播报取材范围（只讲重点，不再全栏目念一遍）
- 全中文策略：后端只收中文源，不接任何在线翻译 / 大模型服务
- appearance       皮肤与深浅模式
- weather          天气开关与城市

所有读取都带默认值，旧版 config.json（只有 tts/city）可直接升级使用。
"""

import copy
import json
import os
from pathlib import Path

BASE_DATA_ROOT = Path(
    os.environ.get(
        "DIGEST_DATA_ROOT",
        str(Path.home() / "Library" / "Application Support" / "DailyDigest"),
    )
)
CONFIG_PATH = BASE_DATA_ROOT / "config.json"

# 栏目注册表：group 决定侧栏分组，broadcast 决定默认是否进语音播报。
CATALOG = [
    {"id": "wire",       "name": "环球通讯社", "icon": "globe.asia.australia", "color": "#4C7A8C", "group": "要闻", "broadcast": True},
    {"id": "global",     "name": "外媒编译",   "icon": "newspaper",            "color": "#3F6E8C", "group": "要闻", "broadcast": True},
    {"id": "policy",     "name": "政策解读",   "icon": "building.columns",     "color": "#2C4A7C", "group": "要闻", "broadcast": True},
    {"id": "economy",    "name": "财经观察",   "icon": "chart.line.uptrend.xyaxis", "color": "#82623C", "group": "要闻", "broadcast": True},
    {"id": "infogap",    "name": "信息差",     "icon": "sparkles",             "color": "#506D7B", "group": "科技", "broadcast": False},
    {"id": "ai",         "name": "人工智能",   "icon": "brain.head.profile",   "color": "#7C5CFF", "group": "科技", "broadcast": True},
    {"id": "opensource", "name": "开源项目",   "icon": "chevron.left.forwardslash.chevron.right", "color": "#22A06B", "group": "科技", "broadcast": False},
    {"id": "sport",      "name": "体育资讯",   "icon": "sportscourt",          "color": "#2E7D6B", "group": "生活", "broadcast": False},
    {"id": "life",       "name": "生活消费",   "icon": "house",                "color": "#B07A3C", "group": "生活", "broadcast": False},
    {"id": "health",     "name": "健康生活",   "icon": "heart.text.square",    "color": "#D65050", "group": "生活", "broadcast": False},
    {"id": "games",      "name": "游戏资讯",   "icon": "gamecontroller",       "color": "#776493", "group": "兴趣", "broadcast": False},
    {"id": "design",     "name": "设计灵感",   "icon": "paintpalette",         "color": "#D95B8A", "group": "兴趣", "broadcast": False},
    {"id": "media",      "name": "新媒动态",   "icon": "megaphone",            "color": "#1F9D9B", "group": "兴趣", "broadcast": False},
]
CATALOG_IDS = [m["id"] for m in CATALOG]
GROUP_ORDER = ["要闻", "科技", "生活", "兴趣"]

DEFAULT_ENABLED = [
    "wire", "global", "policy", "economy", "infogap", "ai",
    "sport", "life", "health", "games", "opensource",
]
DEFAULT_BROADCAST = ["wire", "global", "policy", "economy", "ai"]

# 皮肤：前端 Theme.swift 里同名，改这里请同步改那边。
SKINS = ["ink", "paper", "midnight", "sage", "clay"]

DEFAULT_CONFIG = {
    "collection": {"per_update_limit": 12, "daily_limit": 60},
    "tts": {
        "enabled": True,
        "engine": "edge",
        "natural_rate": "-8%",
        "rate": 190,
        "time": "09:10",
        "voice": "zh-CN-YunyangNeural",
    },
    "weather": {
        "enabled": True,
        "city": "杭州富阳",
        "latitude": 30.05,
        "longitude": 119.95,
    },
    "appearance": {"skin": "ink", "mode": "system"},
    "modules": {
        "catalog": CATALOG,
        "enabled": DEFAULT_ENABLED,
        "show_hotlists": True,
        "show_sports": True,
        "show_topic": True,
        "show_opportunities": False,
    },
    "broadcast": {
        "modules": DEFAULT_BROADCAST,
        "include_weather": True,
        "include_hot_topics": True,
        "include_sports": False,
        "max_items_per_module": 3,
    },
}

# 外媒与英文源统一显示中文名；原文链接仍保留在 url 字段。
SOURCE_CN = {
    "BBC中文": "英国广播公司中文",
    "Reuters": "路透社", "AP News": "美联社", "Bloomberg": "彭博社",
    "Financial Times": "金融时报", "The Guardian World": "卫报",
    "Al Jazeera": "半岛电视台", "DW World": "德国之声", "BBC World": "英国广播公司",
    "CNBC World": "美国消费者新闻与商业频道", "WSJ World": "华尔街日报",
    "NPR": "美国国家公共广播", "Sky News": "天空新闻", "France 24": "法国二十四台",
    "Hacker News": "黑客新闻社区", "Ars Technica": "技术纵横",
    "Product Hunt": "新品发现社区",
    "CNBC Finance": "美国消费者新闻与商业频道财经", "WSJ Markets": "华尔街日报市场",
    "MarketWatch": "市场观察", "TechCrunch AI": "科技创投网",
    "The Verge AI": "边缘科技网", "MIT Tech Review": "麻省理工科技评论",
    "OpenAI": "开放人工智能研究中心", "arXiv AI": "预印本平台",
    "Dezeen": "设计志", "Designboom": "设计潮",
    "Fast Company Co.Design": "快公司设计频道",
    "Digiday": "数字媒体观察", "Tubefilter": "网络视频观察",
    "Nieman Lab": "尼曼新闻实验室",
    "WHO": "世界卫生组织", "STAT": "医疗新闻站",
    "ScienceDaily": "每日科学", "ScienceDaily Health": "每日科学健康",
    "Nature": "自然杂志", "Politico": "政治新闻网",
    "NYT World": "纽约时报", "France 24 World": "法国二十四台",
    "NPR World": "美国国家公共广播", "CBS World": "哥伦比亚广播公司国际",
    "ESPN": "娱乐体育节目网", "Sky Sports": "天空体育",
    "CBS Sports": "哥伦比亚广播体育", "France 24 Sport": "法国二十四台体育",
    "The Verge": "边缘科技网", "TechCrunch": "科技创投网",
    "Forbes": "福布斯", "9to5Mac": "苹果资讯网",
    "WSJ": "华尔街日报", "BBC": "英国广播公司", "FT": "金融时报",
    "The Information": "信息网", "Bloomberg Opinion": "彭博观点",
}


def chinese_source(name: str) -> str:
    """把来源名转成中文；已是中文或未收录时保留原样。"""
    if not name:
        return "公开信源"
    if name in SOURCE_CN:
        return SOURCE_CN[name]
    for english, chinese in SOURCE_CN.items():
        if name.startswith(english) or english.startswith(name):
            return chinese
    return name


def load_config() -> dict:
    """读取并合并默认值；任何缺字段都不影响运行。"""
    raw = {}
    try:
        raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        if not isinstance(raw, dict):
            raw = {}
    except (OSError, ValueError):
        raw = {}

    cfg = copy.deepcopy(DEFAULT_CONFIG)
    # 旧配置顶层 city/经纬度 → weather 段（向后兼容）
    legacy_weather = {}
    for key in ("city", "latitude", "longitude"):
        if key in raw:
            legacy_weather[key] = raw[key]
    if legacy_weather:
        cfg["weather"].update(legacy_weather)
    if isinstance(raw.get("weather"), dict):
        cfg["weather"].update(raw["weather"])
    if isinstance(raw.get("tts"), dict):
        cfg["tts"].update(raw["tts"])
    if isinstance(raw.get("collection"), dict):
        cfg["collection"].update(raw["collection"])
    if isinstance(raw.get("appearance"), dict):
        cfg["appearance"].update(raw["appearance"])

    # 旧顶层键保留，前端老代码仍读得到
    for key in ("city", "latitude", "longitude"):
        if key in raw:
            cfg[key] = raw[key]

    modules = raw.get("modules") if isinstance(raw.get("modules"), dict) else {}
    broadcast = raw.get("broadcast") if isinstance(raw.get("broadcast"), dict) else {}
    cfg["modules"].update({
        k: v for k, v in modules.items() if k != "catalog"
    })
    cfg["broadcast"].update(broadcast)

    # catalog 始终以当前代码为准（新增栏目自动出现），但保留用户自定义顺序无意义
    cfg["modules"]["catalog"] = copy.deepcopy(CATALOG)
    cfg["modules"]["enabled"] = _valid_ids(cfg["modules"].get("enabled"), DEFAULT_ENABLED)
    cfg["broadcast"]["modules"] = _valid_ids(
        cfg["broadcast"].get("modules"), DEFAULT_BROADCAST
    )
    if cfg["appearance"].get("skin") not in SKINS:
        cfg["appearance"]["skin"] = "ink"
    return cfg


def _valid_ids(value, fallback):
    if not isinstance(value, list):
        return list(fallback)
    result, seen = [], set()
    for item in value:
        if isinstance(item, str) and item in CATALOG_IDS and item not in seen:
            result.append(item)
            seen.add(item)
    return result or list(fallback)


def enabled_modules(config: dict = None) -> list:
    cfg = config or load_config()
    return list(cfg["modules"]["enabled"])


def broadcast_modules(config: dict = None) -> list:
    cfg = config or load_config()
    # 只播已启用的栏目，避免关掉的模块还出现在音频里
    enabled = set(cfg["modules"]["enabled"])
    return [cid for cid in cfg["broadcast"]["modules"] if cid in enabled]


def module_meta(cid: str) -> dict:
    return next((m for m in CATALOG if m["id"] == cid), {})


def write_default_config() -> dict:
    """把升级后的配置落盘（保留用户已有的 tts/天气等设置）。"""
    cfg = load_config()
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(
        json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return cfg


if __name__ == "__main__":
    result = write_default_config()
    print("已写入:", CONFIG_PATH)
    print("启用栏目:", ", ".join(result["modules"]["enabled"]))
    print("播报栏目:", ", ".join(result["broadcast"]["modules"]))
