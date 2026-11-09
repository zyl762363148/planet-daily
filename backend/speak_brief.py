#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""行星日报：LaunchAgent 每分钟检查并播放当天的预渲染节目。

App 和脚本共用 data/tts/.playback.lock（POSIX flock，播放期间持有），
以及 .spoken-YYYY-MM-DD（纯文本 HH:mm，成功开始后写入）。修改配置时间
即可在同一天重新安排；迟到不超过 30 分钟时补播，不会因整点轮询错过。
"""

import argparse
import aifc
import fcntl
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

BASE_DATA_ROOT = Path(os.environ.get(
    "DIGEST_DATA_ROOT",
    str(Path.home() / "Library" / "Application Support" / "DailyDigest"),
))
DATA_DIR = BASE_DATA_ROOT / "data"
TTS_DIR = DATA_DIR / "tts"
CONFIG_PATH = BASE_DATA_ROOT / "config.json"
LOG_DIR = Path.home() / "Library" / "Logs" / "DailyDigest"
LOG_PATH = LOG_DIR / "speak.log"

DEFAULT_TTS = {"enabled": True, "time": "09:10", "rate": 200, "voice": "Tingting"}
CATCH_UP_SECONDS = 30 * 60
PLAYBACK_TIMEOUT = 20 * 60


def log(message: str, persist: bool = True) -> None:
    line = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {message}"
    print(line, flush=True)
    if not persist:
        return
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError:
        pass


def load_tts_config() -> dict:
    """缺失字段使用默认值；损坏的配置不能意外触发声音。"""
    config = dict(DEFAULT_TTS)
    try:
        payload = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return config
    except (OSError, ValueError) as exc:
        raise ValueError(f"无法读取 config.json：{exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError("config.json 必须是对象")
    tts = payload.get("tts", {})
    if not isinstance(tts, dict):
        raise ValueError("tts 必须是对象")
    config.update({key: tts[key] for key in DEFAULT_TTS if key in tts})
    if not isinstance(config["enabled"], bool):
        raise ValueError("tts.enabled 必须是 true 或 false")
    scheduled = config["time"]
    if not isinstance(scheduled, str) or not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", scheduled):
        raise ValueError("tts.time 必须是 24 小时制 HH:mm，例如 09:10")
    rate = config["rate"]
    if isinstance(rate, bool) or not isinstance(rate, int) or not 80 <= rate <= 350:
        raise ValueError("tts.rate 必须是 80–350 之间的整数")
    if not isinstance(config["voice"], str) or not config["voice"].strip():
        raise ValueError("tts.voice 必须是有效的语音名称")
    config["voice"] = config["voice"].strip()
    return config


def is_due(now: datetime, scheduled: str) -> bool:
    hour, minute = (int(part) for part in scheduled.split(":"))
    due = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    return 0 <= (now - due).total_seconds() < CATCH_UP_SECONDS


def app_running(read_only: bool = False):
    """返回 None 代表无法判断；权限/系统错误时跳过以免双播。"""
    try:
        result = subprocess.run(
            ["/usr/bin/pgrep", "-x", "DailyDigest"], capture_output=True, timeout=10
        )
    except (OSError, subprocess.SubprocessError) as exc:
        log(f"无法检查 App 进程，跳过本次播报：{exc}", persist=not read_only)
        return None
    if result.returncode in (0, 1):
        return result.returncode == 0
    log(f"无法检查 App 进程（pgrep {result.returncode}），跳过本次播报", persist=not read_only)
    return None


def marker_path(date_text: str) -> Path:
    return TTS_DIR / f".spoken-{date_text}"


def already_played(date_text: str, scheduled: str) -> bool:
    try:
        return marker_path(date_text).read_text(encoding="utf-8").strip() == scheduled
    except (OSError, ValueError):
        return False


def mark_played(date_text: str, scheduled: str) -> None:
    path = marker_path(date_text)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    try:
        temporary.write_text(scheduled + "\n", encoding="utf-8")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def clear_played(date_text: str, scheduled: str) -> None:
    if already_played(date_text, scheduled):
        marker_path(date_text).unlink(missing_ok=True)


def acquire_playback_lock():
    """返回持有 flock 的文件；关闭文件后释放，绝不删除锁文件。"""
    TTS_DIR.mkdir(parents=True, exist_ok=True)
    handle = (TTS_DIR / ".playback.lock").open("a+b")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        return None
    except Exception:
        handle.close()
        raise
    return handle


def stop_process(process) -> None:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def playback_timeout(audio: Path) -> float:
    """按音频实长加宽限，长节目不会在二十分钟处被定时播放器截断。"""
    try:
        with aifc.open(str(audio), "rb") as sound:
            rate = sound.getframerate()
            duration = sound.getnframes() / rate if rate else 0
        if duration > 0:
            return max(PLAYBACK_TIMEOUT, duration + 120)
    except (OSError, EOFError, ValueError, aifc.Error):
        pass
    return PLAYBACK_TIMEOUT


def play_audio(audio: Path, date_text: str, scheduled: str, lock_handle) -> int:
    process = None
    marked = False
    try:
        # 子进程继承锁：即便脚本意外退出，afplay 仍持有锁直到声音结束。
        process = subprocess.Popen(
            ["/usr/bin/afplay", str(audio)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            pass_fds=(lock_handle.fileno(),),
        )
        try:
            code = process.wait(timeout=0.25)
        except subprocess.TimeoutExpired:
            code = None
        if code is not None and code != 0:
            log(f"afplay 启动失败，返回码 {code}；保留后续重试")
            return 1
        mark_played(date_text, scheduled)
        marked = True
        log(f"开始播放今日播报：{audio}（计划 {scheduled}）")
        if code is None:
            code = process.wait(timeout=playback_timeout(audio))
        if code != 0:
            clear_played(date_text, scheduled)
            log(f"afplay 播放失败，返回码 {code}；保留后续重试")
            return 1
        log("播报播放完成")
        return 0
    except (OSError, subprocess.SubprocessError) as exc:
        if process is not None:
            stop_process(process)
        if marked:
            clear_played(date_text, scheduled)
        log(f"afplay 失败：{exc}；保留后续重试")
        return 1


def run(now=None, force: bool = False, dry_run: bool = False) -> int:
    now = now or datetime.now()
    try:
        config = load_tts_config()
    except ValueError as exc:
        log(f"语音配置无效，跳过：{exc}", persist=not dry_run)
        return 1
    if not config["enabled"] and not force:
        return 0
    scheduled = config["time"]
    if not force and not is_due(now, scheduled):
        return 0
    date_text = now.strftime("%Y-%m-%d")
    audio = TTS_DIR / f"brief-{date_text}.aiff"
    if not audio.is_file():
        log(f"今天的播报音频尚未生成：{audio}", persist=not dry_run)
        return 0
    if dry_run:
        # 不创建目录/锁/marker/日志，更不触发抓取、AI 或 TTS 生成。
        if not force:
            if already_played(date_text, scheduled):
                log("[dry-run] 当前计划已经播放，跳过", persist=False)
                return 0
            running = app_running(read_only=True)
            if running is None:
                return 1
            if running:
                log("[dry-run] App 正在运行，将交由 App 内定时器播放", persist=False)
                return 0
        lock_path = TTS_DIR / ".playback.lock"
        try:
            with lock_path.open("rb") as existing_lock:
                try:
                    fcntl.flock(existing_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    log("[dry-run] 已有播报正在播放，跳过", persist=False)
                    return 0
        except FileNotFoundError:
            pass
        except OSError as exc:
            log(f"[dry-run] 无法检查播放锁，跳过：{exc}", persist=False)
            return 1
        log(f"[dry-run] 将播放 {audio}（计划 {scheduled}）", persist=False)
        return 0
    try:
        handle = acquire_playback_lock()
    except OSError as exc:
        log(f"无法取得播放锁，跳过：{exc}")
        return 1
    if handle is None:
        log("已有播报正在播放，跳过本次请求")
        return 0
    with handle:
        if not force:
            if already_played(date_text, scheduled):
                return 0
            running = app_running()
            if running is None:
                return 1
            if running:
                log("行星日报 App 正在运行，交给 App 内定时器播放")
                return 0
        return play_audio(audio, date_text, scheduled, handle)


def main() -> int:
    parser = argparse.ArgumentParser(description="行星日报定时语音播报")
    parser.add_argument("--dry-run", action="store_true", help="只打印判断，不播放")
    parser.add_argument(
        "--force", action="store_true",
        help="忽略时间、已播和 App 检查，立即播放今天音频；仍遵守播放互斥锁",
    )
    args = parser.parse_args()
    return run(force=args.force, dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
