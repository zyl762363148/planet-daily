#!/usr/bin/env python3
"""行星日报 · 每日邮件推送。

把当天的日报 JSON（包含「一日简报」）渲染成一封内联样式的 HTML 邮件。

用法：
    python3 backend/send_email.py                 # 发送今天（或最近一期）的日报
    python3 backend/send_email.py --date 2026-10-24
    python3 backend/send_email.py --dry-run       # 只在 reports/ 下生成 HTML，不发送

配置文件：~/.config/dailydigest/email.json

    SMTP 方式：
    {
      "method": "smtp",
      "enabled": true,
      "to": ["you@example.com"],
      "from": "行星日报 <digest@example.com>",
      "subject": "行星日报 · {date}",
      "smtp": {
        "host": "smtp.example.com",
        "port": 465,
        "username": "digest@example.com",
        "password": "******",
        "ssl": true
      }
    }

    Mail.app 方式（本机 Mail 已配好账号）：
    {
      "method": "mailapp",
      "to": ["you@example.com"],
      "subject": "行星日报 · {date}",
      "mailapp": { "send": true }
    }

未配置或发送失败时只写日志（~/Library/Logs/DailyDigest/email.log），
不会打断其它流程。
"""

import argparse
import html
import json
import os
import re
import smtplib
import ssl
import subprocess
import sys
import tempfile
from datetime import datetime
from email.message import EmailMessage
from email.utils import formatdate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.expanduser("~/Library/Application Support/DailyDigest/data")
REPORT_DIR = os.path.join(ROOT, "reports")
LOG_DIR = os.path.expanduser("~/Library/Logs/DailyDigest")
LOG_PATH = os.path.join(LOG_DIR, "email.log")
CONFIG_PATH = os.path.expanduser("~/.config/dailydigest/email.json")

BRAND_START = "#FF5A36"
BRAND_END = "#FF9F45"
INK = "#1F2328"
INK_SOFT = "#5C6470"
INK_FAINT = "#8A929E"
PAPER = "#F6F2EC"
CARD = "#FFFFFF"
HAIRLINE = "#EDE6DD"

CATEGORY_FALLBACK = {
    "wire": "#FF5A36",
    "policy": "#2C4A7C",
    "infogap": "#4C8DFF",
    "economy": "#F2A33A",
    "ai": "#9B7BFF",
    "opensource": "#2FBF71",
    "design": "#F06FA8",
    "media": "#24B8C8",
    "health": "#EF6B6B",
}


# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------


def log(message: str) -> None:
    os.makedirs(LOG_DIR, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{stamp}] {message}"
    print(line)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError:
        pass


def load_config() -> dict:
    if not os.path.exists(CONFIG_PATH):
        return {}
    try:
        with open(CONFIG_PATH, encoding="utf-8") as handle:
            config = json.load(handle)
        if not isinstance(config, dict):
            raise ValueError("配置必须是 JSON 对象")
        return config
    except (OSError, ValueError) as exc:
        log(f"邮件配置读取失败：{exc}")
        return {}


def available_dates() -> list:
    if not os.path.isdir(DATA_DIR):
        return []
    names = []
    for name in os.listdir(DATA_DIR):
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}\.json", name):
            names.append(name[:10])
    return sorted(names, reverse=True)


def load_digest(date: str) -> tuple:
    """返回 (date, digest)；date 为空时取今天或最近一期。"""
    if date:
        path = os.path.join(DATA_DIR, f"{date}.json")
        if not os.path.exists(path):
            return None, None
    else:
        today = datetime.now().strftime("%Y-%m-%d")
        path = os.path.join(DATA_DIR, f"{today}.json")
        if not os.path.exists(path):
            dates = available_dates()
            if not dates:
                return None, None
            date = dates[0]
            path = os.path.join(DATA_DIR, f"{date}.json")
            log(f"今天还没有日报，改用最近一期 {date}")
        else:
            date = today

    try:
        with open(path, encoding="utf-8") as handle:
            return date, json.load(handle)
    except (OSError, ValueError) as exc:
        log(f"日报读取失败（{path}）：{exc}")
        return None, None


def chinese_date(date: str) -> str:
    try:
        day = datetime.strptime(date, "%Y-%m-%d")
    except ValueError:
        return date
    weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    return f"{day.year} 年 {day.month} 月 {day.day} 日 · {weekdays[day.weekday()]}"


def short_date(date: str) -> str:
    try:
        day = datetime.strptime(date, "%Y-%m-%d")
    except ValueError:
        return date
    return f"{day.month} 月 {day.day} 日"


def category_color(category: dict) -> str:
    return category.get("color") or CATEGORY_FALLBACK.get(category.get("id", ""), BRAND_START)


def esc(value) -> str:
    return html.escape(str(value or ""), quote=True)


def item_lookup(digest: dict) -> dict:
    lookup = {}
    for category in digest.get("categories") or []:
        for item in category.get("items") or []:
            lookup[item.get("id")] = (category, item)
    return lookup


def top_entries(digest: dict) -> list:
    """优先用一日简报的要点定位条目，不够 5 条时按分数补齐。"""
    lookup = item_lookup(digest)
    brief = digest.get("brief") or {}
    entries = []
    seen = set()
    for point in brief.get("points") or []:
        item_id = point.get("item_id")
        if not item_id or item_id in seen:
            continue
        pair = lookup.get(item_id)
        if not pair:
            continue
        seen.add(item_id)
        entries.append(
            {
                "category": pair[0],
                "item": pair[1],
                "text": point.get("text") or "",
                "from_brief": True,
            }
        )
        if len(entries) >= 5:
            break

    if len(entries) < 5:
        ranked = sorted(
            (
                (category, item)
                for category in digest.get("categories") or []
                for item in category.get("items") or []
            ),
            key=lambda pair: pair[1].get("score") or 0,
            reverse=True,
        )
        for category, item in ranked:
            if len(entries) >= 5:
                break
            if item.get("id") in seen:
                continue
            seen.add(item.get("id"))
            entries.append(
                {
                    "category": category,
                    "item": item,
                    "text": item.get("takeaway") or item.get("summary") or "",
                    "from_brief": False,
                }
            )
    return entries


# ---------------------------------------------------------------------------
# HTML 渲染
# ---------------------------------------------------------------------------


def render_html(date: str, digest: dict) -> str:
    categories = digest.get("categories") or []
    total = sum(len(category.get("items") or []) for category in categories)
    brief = digest.get("brief") or {}
    summary = (brief.get("summary") or "").strip()
    points = brief.get("points") or []
    opportunities = brief.get("opportunities") or []
    entries = top_entries(digest)
    generated = (digest.get("generated_at") or "").replace("T", " ")[:16]

    parts = []
    parts.append(
        f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>行星日报 · {esc(short_date(date))}</title>
</head>
<body style="margin:0;padding:0;background:{PAPER};-webkit-font-smoothing:antialiased;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:{PAPER};padding:24px 12px;">
<tr><td align="center">
<table role="presentation" width="640" cellpadding="0" cellspacing="0" border="0" style="width:640px;max-width:100%;background:{CARD};border-radius:18px;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Helvetica Neue',sans-serif;color:{INK};">
"""
    )

    # 封面
    parts.append(
        f"""<tr><td style="background-color:{BRAND_START};background:linear-gradient(135deg,{BRAND_START} 0%,{BRAND_END} 100%);padding:30px 32px 26px 32px;">
<div style="font-size:10px;letter-spacing:3px;color:rgba(255,255,255,0.78);font-weight:700;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;">行星日报 · PLANET DAILY</div>
<div style="font-size:28px;line-height:1.3;font-weight:700;color:#FFFFFF;margin-top:10px;">{esc(chinese_date(date))}</div>
<div style="font-size:12px;color:rgba(255,255,255,0.85);margin-top:10px;">{total} 条精选 · {len(categories)} 个栏目 · 每天一颗信息星球</div>
</td></tr>"""
    )

    # 一日简报
    if summary or points or opportunities:
        parts.append(
            f"""<tr><td style="padding:26px 32px 6px 32px;">
<div style="font-size:11px;font-weight:700;letter-spacing:2px;color:{BRAND_START};">一日简报</div>"""
        )
        if summary:
            parts.append(
                f"""<p style="margin:12px 0 0 0;font-size:15px;line-height:1.8;color:{INK};">{esc(summary)}</p>"""
            )
        if points:
            parts.append(
                '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:16px;">'
            )
            for point in points[:8]:
                category_id = point.get("category_id") or ""
                color = CATEGORY_FALLBACK.get(category_id, INK_SOFT)
                name = point.get("category") or ""
                chip = (
                    f'<span style="display:inline-block;font-size:10px;font-weight:600;color:{color};'
                    f'background:{color}1A;border-radius:9px;padding:2px 8px;margin-right:8px;white-space:nowrap;">{esc(name)}</span>'
                    if name
                    else ""
                )
                parts.append(
                    f"""<tr><td style="padding:5px 0;font-size:14px;line-height:1.7;color:{INK};">{chip}{esc(point.get("text") or "")}</td></tr>"""
                )
            parts.append("</table>")

        if opportunities:
            lookup = item_lookup(digest)
            parts.append(
                f"""<div style="margin-top:18px;padding:14px 16px 12px 16px;background:#FFF8E8;border:1px solid #E9CE96;border-radius:12px;">
<div style="font-size:12px;font-weight:700;letter-spacing:1px;color:#8A5A12;">💡 机会信号</div>
<div style="font-size:10px;color:#A98145;margin-top:2px;">机会在哪 · 怎么跟进</div>"""
            )
            for entry in opportunities[:3]:
                item_id = entry.get("item_id") or ""
                pair = lookup.get(item_id)
                item = pair[1] if pair else {}
                title = esc(entry.get("title") or "值得跟进的机会")
                url = item.get("url") or ""
                title_html = (
                    f'<a href="{esc(url)}" style="color:#4A3410;text-decoration:none;">{title}</a>'
                    if url
                    else title
                )
                category_id = entry.get("category_id") or (pair[0].get("id") if pair else "")
                category_name = entry.get("category") or ""
                chip = (
                    f'<span style="display:inline-block;font-size:9.5px;font-weight:600;color:{CATEGORY_FALLBACK.get(category_id, "#8A5A12")};'
                    f'background:{CATEGORY_FALLBACK.get(category_id, "#8A5A12")}14;border-radius:8px;padding:1px 7px;margin-right:6px;white-space:nowrap;">{esc(category_name)}</span>'
                    if category_name
                    else ""
                )
                why = esc(entry.get("why") or "")
                how = esc(entry.get("how") or "")
                audience = (entry.get("audience") or "").strip()
                audience_html = (
                    f'<div style="font-size:10.5px;color:#8A6B32;margin-top:3px;">与谁有关：{esc(audience)}</div>'
                    if audience
                    else ""
                )
                parts.append(
                    f"""<div style="margin-top:11px;">
<div style="font-size:13.5px;font-weight:700;line-height:1.55;color:#4A3410;">{chip}{title_html}</div>
<div style="font-size:12.5px;line-height:1.75;color:#6B552C;margin-top:3px;"><span style="font-weight:600;color:#8A5A12;">机会在哪</span> {why}<br><span style="font-weight:600;color:#8A5A12;">怎么跟进</span> {how}</div>
{audience_html}
</div>"""
                )
            parts.append("</div>")
        parts.append("</td></tr>")

    # 今日热点 TOP5
    if entries:
        parts.append(
            f"""<tr><td style="padding:22px 32px 0 32px;">
<div style="border-top:1px solid {HAIRLINE};padding-top:20px;font-size:16px;font-weight:700;color:{INK};">今日热点</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:8px;">"""
        )
        for index, entry in enumerate(entries, start=1):
            category = entry["category"]
            item = entry["item"]
            color = category_color(category)
            title = esc(item.get("title") or "")
            url = item.get("url") or ""
            link = (
                f'<a href="{esc(url)}" style="color:{INK};text-decoration:none;">{title}</a>'
                if url
                else title
            )
            meta_bits = [
                f'<span style="color:{color};font-weight:600;">{esc(item.get("source") or category.get("name") or "")}</span>'
            ]
            if item.get("time"):
                meta_bits.append(
                    f'<span style="font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:{INK_FAINT};">{esc(item.get("time"))}</span>'
                )
            if item.get("heat"):
                meta_bits.append(
                    f'<span style="font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:#D97706;">{esc(item.get("heat"))}</span>'
                )
            if item.get("audience"):
                meta_bits.append(
                    f'<span style="color:{color};font-weight:600;">与谁有关：{esc(item.get("audience"))}</span>'
                )
            parts.append(
                f"""<tr>
<td width="42" valign="top" style="padding:12px 0 10px 0;font-size:22px;font-weight:800;color:{BRAND_START if index <= 3 else INK_FAINT};">{index:02d}</td>
<td style="padding:12px 0 10px 4px;">
<div style="font-size:15px;line-height:1.55;font-weight:600;">{link}</div>
<div style="font-size:11px;color:{INK_SOFT};margin-top:4px;">{" · ".join(meta_bits)}</div>
</td></tr>"""
            )
        parts.append("</table></td></tr>")

    # 全网热榜（微博 / 知乎实时快照，各取前 10）
    hot_sources = [
        source
        for source in ((digest.get("hotlists") or {}).get("sources") or [])
        if source.get("items")
    ]
    for source in hot_sources:
        parts.append(
            f"""<tr><td style="padding:16px 32px 0 32px;">
<div style="border-top:1px solid {HAIRLINE};padding-top:20px;font-size:16px;font-weight:700;color:{INK};">{esc(source.get("name") or "热榜")}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:6px;">"""
        )
        for index, entry in enumerate(source.get("items")[:10], start=1):
            title = esc(entry.get("title") or "")
            url = entry.get("url") or ""
            link = (
                f'<a href="{esc(url)}" style="color:{INK};text-decoration:none;">{title}</a>'
                if url
                else title
            )
            bits = []
            if entry.get("label"):
                bits.append(f'<span style="color:#D97706;font-weight:700;">{esc(entry["label"])}</span>')
            if entry.get("heat"):
                bits.append(
                    f'<span style="font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:{INK_FAINT};">{esc(entry["heat"])}</span>'
                )
            meta = f' <span style="font-size:11px;">{" · ".join(bits)}</span>' if bits else ""
            parts.append(
                f"""<tr>
<td width="34" valign="top" style="padding:8px 0 7px 0;font-size:16px;font-weight:800;color:{BRAND_START if index <= 3 else INK_FAINT};">{index}</td>
<td style="padding:8px 0 7px 4px;font-size:13.5px;line-height:1.55;">{link}{meta}</td></tr>"""
            )
        parts.append("</table></td></tr>")

    # 栏目精选
    picked = [category for category in categories if category.get("items")]
    if picked:
        parts.append(
            f"""<tr><td style="padding:16px 32px 4px 32px;">
<div style="border-top:1px solid {HAIRLINE};padding-top:20px;font-size:16px;font-weight:700;color:{INK};">栏目精选</div></td></tr>"""
        )

    for category in picked:
        color = category_color(category)
        items = category.get("items") or []
        name = category.get("name") or ""
        parts.append(
            f"""<tr><td style="padding:14px 32px 0 32px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td width="3" style="background:{color};border-radius:2px;"></td>
<td style="padding-left:12px;font-size:13px;font-weight:700;color:{INK};">{esc(name)}</td>
<td align="right" style="font-size:10px;color:{INK_FAINT};font-family:ui-monospace,SFMono-Regular,Menlo,monospace;">{len(items)} 条</td>
</tr></table>"""
        )
        if category.get("brief"):
            parts.append(
                f'<p style="margin:8px 0 2px 15px;font-size:12px;line-height:1.7;color:{INK_SOFT};">{esc(category.get("brief"))}</p>'
            )
        for item in items[:2]:
            title = esc(item.get("title") or "")
            url = item.get("url") or ""
            link = (
                f'<a href="{esc(url)}" style="color:{INK};text-decoration:none;">{title}</a>'
                if url
                else title
            )
            summary_text = (item.get("summary") or "").strip()
            takeaway = (item.get("takeaway") or "").strip()
            body = summary_text
            if takeaway:
                body = (
                    f"{summary_text}"
                    f'<br><span style="color:{INK_SOFT};"><span style="color:{color};font-weight:600;">为什么值得看 </span>{esc(takeaway)}</span>'
                )
            meta = esc(item.get("source") or "")
            if item.get("time"):
                meta += f" · {esc(item.get('time'))}"
            if item.get("audience"):
                meta += (
                    f' · <span style="color:{color};font-weight:600;">'
                    f'与谁有关：{esc(item.get("audience"))}</span>'
                )
            parts.append(
                f"""<div style="margin:10px 0 0 15px;">
<div style="font-size:14px;line-height:1.55;font-weight:600;">{link}</div>
<div style="font-size:11px;color:{INK_FAINT};margin-top:3px;">{meta}</div>
<div style="font-size:13px;line-height:1.75;color:{INK_SOFT};margin-top:6px;">{body if takeaway else esc(body)}</div>
</div>"""
            )
        parts.append("</td></tr>")

    # 页脚
    parts.append(
        f"""<tr><td style="padding:24px 32px 28px 32px;">
<div style="border-top:1px solid {HAIRLINE};padding-top:16px;font-size:11px;line-height:1.7;color:{INK_FAINT};">
行星日报每日自动生成{f"，生成于 {esc(generated)}" if generated else ""}。<br>
打开 App 可以查看全部条目、收藏和过去一周的汇总。回复这封邮件不会有人看到 :)
</div></td></tr>
</table>
</td></tr>
</table>
</body>
</html>"""
    )
    return "".join(parts)


def render_plain(date: str, digest: dict) -> str:
    total = sum(len(category.get("items") or []) for category in digest.get("categories") or [])
    lines = [f"行星日报 · {chinese_date(date)}", f"{total} 条精选", ""]
    brief = digest.get("brief") or {}
    if brief.get("summary"):
        lines += ["【一日简报】", brief["summary"], ""]
    for point in brief.get("points") or []:
        category = point.get("category") or ""
        text = point.get("text") or ""
        lines.append(f"· {category}：{text}" if category else f"· {text}")
    lines.append("")

    opportunities = brief.get("opportunities") or []
    if opportunities:
        lines.append("【💡 机会信号】")
        for entry in opportunities[:3]:
            title = entry.get("title") or "值得跟进的机会"
            label = entry.get("category") or ""
            lines.append(f"· {label}｜{title}" if label else f"· {title}")
            if entry.get("why"):
                lines.append(f"  机会在哪：{entry['why']}")
            if entry.get("how"):
                lines.append(f"  怎么跟进：{entry['how']}")
            if entry.get("audience"):
                lines.append(f"  与谁有关：{entry['audience']}")
        lines.append("")

    for entry in top_entries(digest):
        item = entry["item"]
        lines.append(f"{'●'} {item.get('title') or ''}")
        if item.get("audience"):
            lines.append(f"  与谁有关：{item['audience']}")
        if item.get("url"):
            lines.append(f"  {item['url']}")
        lines.append("")

    for source in (digest.get("hotlists") or {}).get("sources") or []:
        items = source.get("items") or []
        if not items:
            continue
        lines.append(f"【{source.get('name') or '热榜'}】")
        for index, entry in enumerate(items[:10], start=1):
            heat = f"（{entry['heat']}）" if entry.get("heat") else ""
            lines.append(f"{index}. {entry.get('title') or ''}{heat}")
        lines.append("")
    lines.append("由行星日报自动生成。")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 发送
# ---------------------------------------------------------------------------


def normalize_recipients(value) -> list:
    if isinstance(value, str):
        return [part.strip() for part in value.replace("；", ";").replace(",", ";").split(";") if part.strip()]
    if isinstance(value, list):
        return [str(part).strip() for part in value if str(part).strip()]
    return []


def build_subject(config: dict, date: str) -> str:
    template = config.get("subject") or "行星日报 · {date}"
    return template.replace("{date}", short_date(date))


def send_smtp(config: dict, subject: str, html_body: str, plain_body: str) -> bool:
    smtp = config.get("smtp") or {}
    host = smtp.get("host") or ""
    if not host:
        log("SMTP 配置缺少 host，跳过发送")
        return False

    port = int(smtp.get("port") or (465 if smtp.get("ssl", True) else 587))
    use_ssl = bool(smtp.get("ssl", port == 465))
    use_starttls = bool(smtp.get("starttls", False))
    sender = config.get("from") or smtp.get("username") or ""
    recipients = normalize_recipients(config.get("to"))
    if not recipients:
        log("收件人（to）为空，跳过发送")
        return False

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = sender
    message["To"] = ", ".join(recipients)
    message["Date"] = formatdate(localtime=True)
    message.set_content(plain_body, subtype="plain", charset="utf-8")
    message.add_alternative(html_body, subtype="html", charset="utf-8")

    try:
        if use_ssl:
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(host, port, context=context, timeout=30) as server:
                if smtp.get("username"):
                    server.login(smtp["username"], smtp.get("password") or "")
                server.send_message(message, from_addr=sender, to_addrs=recipients)
        else:
            with smtplib.SMTP(host, port, timeout=30) as server:
                server.ehlo()
                if use_starttls:
                    server.starttls(context=ssl.create_default_context())
                    server.ehlo()
                if smtp.get("username"):
                    server.login(smtp["username"], smtp.get("password") or "")
                server.send_message(message, from_addr=sender, to_addrs=recipients)
        log(f"邮件已通过 SMTP 发送：{', '.join(recipients)}")
        return True
    except Exception as exc:  # noqa: BLE001 - 任何发信失败都只写日志
        log(f"SMTP 发送失败：{exc}")
        return False


def applescript_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def send_mailapp(config: dict, subject: str, html_body: str) -> bool:
    recipients = normalize_recipients(config.get("to"))
    if not recipients:
        log("收件人（to）为空，跳过发送")
        return False

    mailapp = config.get("mailapp") or {}
    auto_send = bool(mailapp.get("send", True))

    fd, html_path = tempfile.mkstemp(prefix="planet-daily-", suffix=".html")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(html_body)

        recipient_lines = "\n".join(
            f'        make new to recipient at end of to recipients with properties {{address:"{applescript_escape(address)}"}}'
            for address in recipients
        )
        send_line = "        send newMsg" if auto_send else "        activate"
        script = f'''set htmlFile to POSIX file "{applescript_escape(html_path)}"
set htmlText to read htmlFile as «class utf8»
tell application "Mail"
    set newMsg to make new outgoing message with properties {{subject:"{applescript_escape(subject)}", visible:{str(auto_send).lower()}}}
    tell newMsg
{recipient_lines}
        set html content to htmlText
    end tell
{send_line}
end tell
'''
        fd2, script_path = tempfile.mkstemp(prefix="planet-daily-", suffix=".applescript")
        with os.fdopen(fd2, "w", encoding="utf-8") as handle:
            handle.write(script)
        try:
            result = subprocess.run(
                ["/usr/bin/osascript", script_path],
                capture_output=True,
                text=True,
                timeout=60,
            )
        finally:
            try:
                os.remove(script_path)
            except OSError:
                pass
    finally:
        try:
            os.remove(html_path)
        except OSError:
            pass

    if result.returncode != 0:
        log(f"Mail.app 发送失败：{(result.stderr or '').strip()[-240:]}")
        return False
    log("邮件已交给 Mail.app " + ("发送" if auto_send else "打开"))
    return True


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description="行星日报邮件推送")
    parser.add_argument("--date", help="日报日期，默认今天（没有则最近一期）")
    parser.add_argument("--dry-run", action="store_true", help="只生成 HTML，不发送")
    args = parser.parse_args()

    date, digest = load_digest(args.date)
    if not digest:
        log("没有可用的日报数据，邮件任务结束")
        return 0

    html_body = render_html(date, digest)
    plain_body = render_plain(date, digest)

    os.makedirs(REPORT_DIR, exist_ok=True)
    html_path = os.path.join(REPORT_DIR, f"email-{date}.html")
    with open(html_path, "w", encoding="utf-8") as handle:
        handle.write(html_body)
    log(f"邮件 HTML 已生成：{html_path}")

    if args.dry_run:
        log("--dry-run：不发送")
        return 0

    config = load_config()
    if not config:
        log(f"未找到邮件配置（{CONFIG_PATH}），只生成 HTML")
        return 0
    if config.get("enabled") is False:
        log("邮件配置 enabled=false，跳过发送")
        return 0

    method = (config.get("method") or "smtp").lower()
    subject = build_subject(config, date)

    if method == "mailapp":
        ok = send_mailapp(config, subject, html_body)
    elif method == "smtp":
        ok = send_smtp(config, subject, html_body, plain_body)
    else:
        log(f"未知发送方式：{method}（支持 smtp / mailapp）")
        return 0

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
