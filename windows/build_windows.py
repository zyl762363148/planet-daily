#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""行星日报 · Windows 离线版打包器

两种用法：
1) Mac 端导出（默认）：读本机日报数据与配置，生成自包含 PlanetDaily.html、
   复制当天中文播报音频并转成 m4a、写入启动/刷新脚本。
   菜单「文件 → 导出 Windows 版…」调用的就是这一条。
2) Windows 端刷新（--local）：把新的 latest.json 放进同目录 data/ 后运行
   Refresh.bat，重新生成 PlanetDaily.html，不改动已有音频。

全部离线：不请求任何网络服务，不调用在线翻译或大模型。
"""

import argparse
import datetime as dt
import json
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
HOME = pathlib.Path.home()
MAC_DATA = HOME / "Library/Application Support/DailyDigest/data"
MAC_CONFIG = HOME / "Library/Application Support/DailyDigest/config.json"

TEMPLATE = HERE / "template.html"


def read_json(path, fallback):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"读取 {path} 失败：{exc}")
        return fallback


def json_for_script(value):
    """内嵌到 <script type=application/json>，避免内容提前闭合 script 标签。"""
    return json.dumps(value, ensure_ascii=False).replace("<", "\\u003c").replace(">", "\\u003e")


def issue_number(data_dir, date_text):
    """用归档日报的份数当本期期号，与 Mac 端的「第 N 期」观感一致。"""
    files = sorted(p.name for p in data_dir.glob("20??-??-??.json"))
    if date_text and f"{date_text}.json" in files:
        return files.index(f"{date_text}.json") + 1
    return len(files) + 1


def build_config(cfg, data_dir, date_text):
    modules = cfg.get("modules", {}) if isinstance(cfg, dict) else {}
    catalog = []
    for entry in modules.get("catalog", []) or []:
        if isinstance(entry, dict) and entry.get("id"):
            catalog.append({
                "id": entry.get("id"),
                "name": entry.get("name", ""),
                "group": entry.get("group", "资讯"),
                "color": entry.get("color", "#6B7C86"),
            })
    appearance = cfg.get("appearance", {}) if isinstance(cfg, dict) else {}
    weather = cfg.get("weather", {}) if isinstance(cfg, dict) else {}
    return {
        "city": weather.get("city", "") if weather.get("enabled", True) else "",
        "skin": appearance.get("skin", "ink"),
        "issue": issue_number(data_dir, date_text),
        "enabled": modules.get("enabled", []) or [],
        "catalog": catalog,
    }


def ffmpeg_exe():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return shutil.which("ffmpeg")


def prepare_audio(data_dir, out_dir, date_text, local):
    target_dir = out_dir / "audio"
    target_dir.mkdir(parents=True, exist_ok=True)
    mp3 = target_dir / "brief.mp3"
    m4a = target_dir / "brief.m4a"
    if local:
        if mp3.exists():
            return "audio/brief.mp3"
        if m4a.exists():
            return "audio/brief.m4a"
        return "__NONE__"

    source = data_dir / "tts" / f"brief-{date_text}.aiff"
    if not source.exists():
        candidates = sorted((data_dir / "tts").glob("brief-*.aiff"))
        source = candidates[-1] if candidates else None
    if not source:
        print("未找到当天播报音频，Windows 版将使用浏览器朗读")
        return "__NONE__"

    # 同一份音频已转换过就不再重复编码，Mac 端反复导出会快很多
    if mp3.exists() and mp3.stat().st_mtime >= source.stat().st_mtime:
        return "audio/brief.mp3"

    # 优先 ffmpeg（本机 imageio-ffmpeg 自带），mp3 在 Windows 浏览器上兼容性最好
    ffmpeg = ffmpeg_exe()
    if ffmpeg:
        try:
            subprocess.run(
                [ffmpeg, "-y", "-loglevel", "error", "-i", str(source),
                 "-codec:a", "libmp3lame", "-b:a", "96k", str(mp3)],
                check=True, capture_output=True, timeout=300,
            )
            print(f"播报音频已转换：{mp3.name}（{mp3.stat().st_size // 1024} KB）")
            return "audio/brief.mp3"
        except Exception as exc:
            print(f"ffmpeg 转换失败，尝试系统转换器：{exc}")

    converter = pathlib.Path("/usr/bin/afconvert")
    if converter.exists():
        try:
            subprocess.run(
                [str(converter), "-f", "m4af", "-d", "aac", str(source), str(m4a)],
                check=True, capture_output=True, timeout=180,
            )
            print(f"播报音频已转换：{m4a.name}（{m4a.stat().st_size // 1024} KB）")
            return "audio/brief.m4a"
        except Exception as exc:
            print(f"音频转换失败（改用浏览器朗读）：{exc}")
    return "__NONE__"


def write_scripts(out_dir):
    launch = r"""@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "PY="
where py >nul 2>nul && set "PY=py"
if not defined PY (where python >nul 2>nul && set "PY=python")
if defined PY (
  start "PlanetDaily Server" /min %PY% -m http.server 8765 --bind 127.0.0.1
  timeout /t 1 /nobreak >nul
  start "" http://127.0.0.1:8765/PlanetDaily.html
) else (
  start "" "PlanetDaily.html"
)
"""
    refresh = r"""@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo 正在用 data\latest.json 重新生成 PlanetDaily.html ...
py build_windows.py --local
if errorlevel 1 python build_windows.py --local
echo.
echo 完成。重新双击 Launch.bat 即可看到新数据。
pause
"""
    (out_dir / "Launch.bat").write_text(launch, encoding="utf-8")
    (out_dir / "Refresh.bat").write_text(refresh, encoding="utf-8")

    readme = """行星日报 · Windows 离线版
========================================

打开方式
  双击 Launch.bat（推荐）。它会启动一个只监听 127.0.0.1 的本地小服务并用默认浏览器打开；
  如果电脑没装 Python，会自动直接打开 PlanetDaily.html，多数功能仍可使用。
  建议用 Microsoft Edge 或 Chrome。

文件内容
  PlanetDaily.html   完整客户端，数据已内嵌，可离线阅读
  Launch.bat         双击启动
  Refresh.bat        换数据后重新生成页面
  build_windows.py   生成器（Refresh.bat 会调用）
  data/latest.json   当天的日报数据快照
  data/config.json   栏目、皮肤、城市等偏好
  data/meta.json     期号
  data/tts/          播报章节时间点
  audio/brief.mp3    当天中文语音播报（若有；也可能是 brief.m4a）
  template.html      页面模板（普通使用不需要动）

更新内容
  方式一（推荐）：在 Mac 版行星日报里点「文件 → 导出 Windows 版…」，把整个 windows
                  文件夹拷贝过来覆盖即可，数据与语音一起更新。
  方式二：把新的 latest.json 放进 data 文件夹，双击 Refresh.bat。

界面功能
  左侧选栏目、换 5 套皮肤、切换明暗；右上角搜索全部栏目；
  电台卡可播放内置中文语音、点章节跳转，没有音频时点「朗读提要」用浏览器语音；
  今日栏目卡片点进去看该栏目全文，条目可点「阅读原文」跳转官网。

关于独立 exe
  这套是免安装版，不需要管理员权限、不写注册表、不联网。
  如果要打包成单个 .exe，需要在 Windows 电脑上用 Electron 或 PyInstaller 打包本目录；
  macOS 无法直接生成可在 Windows 运行的原生 exe。

全部内容为中文，数据来自本机日报快照；不接在线翻译，不接任何大模型服务。
"""
    # BOM 让 Windows 记事本正确识别 UTF-8 中文
    (out_dir / "README.txt").write_text("\ufeff" + readme, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="生成行星日报 Windows 离线版")
    parser.add_argument("--source", default=str(MAC_DATA), help="日报数据目录")
    parser.add_argument("--config", default=str(MAC_CONFIG), help="config.json 路径")
    parser.add_argument("--out", default=str(HERE), help="输出目录")
    parser.add_argument("--local", action="store_true", help="Windows 端就地刷新")
    args = parser.parse_args()

    out_dir = pathlib.Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    data_dir = (out_dir / "data") if args.local else pathlib.Path(args.source).resolve()
    cfg_path = (out_dir / "data/config.json") if args.local else pathlib.Path(args.config).resolve()

    digest = read_json(data_dir / "latest.json", None)
    if not digest:
        print("错误：找不到 latest.json，请先生成日报数据")
        return 1
    cfg = read_json(cfg_path, {})
    date_text = str(digest.get("date", ""))
    chapters = read_json(data_dir / "tts" / f"brief-{date_text}.chapters.json", [])
    if not chapters:
        chapter_files = sorted((data_dir / "tts").glob("brief-*.chapters.json"))
        chapters = read_json(chapter_files[-1], []) if chapter_files else []

    (out_dir / "data").mkdir(parents=True, exist_ok=True)
    meta_path = out_dir / "data/meta.json"
    if not args.local:
        shutil.copy2(data_dir / "latest.json", out_dir / "data/latest.json")
        if cfg_path.exists():
            shutil.copy2(cfg_path, out_dir / "data/config.json")
        # 章节时间点与期号随包带走，Windows 端刷新时才不会丢失
        chapter_src = data_dir / "tts" / f"brief-{date_text}.chapters.json"
        if chapter_src.exists():
            (out_dir / "data/tts").mkdir(parents=True, exist_ok=True)
            shutil.copy2(chapter_src, out_dir / "data/tts" / f"brief-{date_text}.chapters.json")
        meta_path.write_text(
            json.dumps({"issue": issue_number(data_dir, date_text)}, ensure_ascii=False),
            encoding="utf-8",
        )

    audio_path = prepare_audio(data_dir, out_dir, date_text, args.local)
    payload = build_config(cfg, data_dir, date_text)
    if args.local:
        meta = read_json(meta_path, {})
        if meta.get("issue"):
            payload["issue"] = meta["issue"]
    write_scripts(out_dir)

    html = TEMPLATE.read_text(encoding="utf-8")
    html = (html
            .replace("__DIGEST_JSON__", json_for_script(digest))
            .replace("__CONFIG_JSON__", json_for_script(payload))
            .replace("__CHAPTERS_JSON__", json_for_script(chapters))
            .replace("__AUDIO_PATH__", audio_path)
            .replace("__BUILD_TIME__", dt.datetime.now().strftime("%Y-%m-%d %H:%M")))
    (out_dir / "PlanetDaily.html").write_text(html, encoding="utf-8")

    total = sum(len(c.get("items", [])) for c in digest.get("categories", []))
    print(f"已生成：{out_dir / 'PlanetDaily.html'}")
    print(f"日期 {date_text} | {len(digest.get('categories', []))} 个栏目 | {total} 条 | 播报 {len(chapters)} 章 | 音频 {audio_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
