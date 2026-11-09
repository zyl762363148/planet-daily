#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""在项目独立 venv 中合成一章公开口播稿；不使用系统 Python 依赖。"""

import argparse
import asyncio
import re
import sys
from pathlib import Path


def natural_rate(value: str) -> str:
    if not re.fullmatch(r"[+-]?\d{1,2}%", value):
        raise ValueError("natural_rate 必须是 -10% 至 +15% 的百分比，建议 +0%")
    percent = int(value[:-1])
    if not -10 <= percent <= 15:
        raise ValueError("natural_rate 必须在 -10% 至 +15% 之间，建议 +0%")
    return f"{percent:+d}%"


async def synthesize(text_file: Path, output: Path, voice: str, rate: str) -> None:
    import edge_tts

    rate = natural_rate(rate)
    text = text_file.read_text(encoding="utf-8").strip()
    if not text:
        raise ValueError("这一章口播稿为空")
    output.parent.mkdir(parents=True, exist_ok=True)
    partial = output.with_name(output.name + ".part")
    try:
        # 仅使用 edge-tts 正常公开接口，不附加代理、Cookie、凭证或自定义重试。
        communicate = edge_tts.Communicate(text, voice=voice, rate=rate,
                                          connect_timeout=15, receive_timeout=90)
        await communicate.save(str(partial))
        if not partial.is_file() or partial.stat().st_size == 0:
            raise ValueError("在线语音服务未返回音频")
        partial.replace(output)
    finally:
        partial.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="逐章在线自然语音合成")
    parser.add_argument("--text-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--voice", default="zh-CN-YunyangNeural")
    parser.add_argument("--rate", default="+0%")
    args = parser.parse_args()
    try:
        asyncio.run(synthesize(args.text_file, args.output, args.voice, args.rate))
        return 0
    except Exception as exc:
        status = getattr(exc, "status", None)
        if status == 403:
            message = "在线语音服务返回 HTTP 403，请稍后检查服务可用性"
        elif isinstance(exc, ImportError):
            message = "在线自然语音依赖未安装，请在项目根目录运行 ./setup_tts.sh"
        else:
            # 诊断不输出服务连接 URL 或原稿，音频失败交给上层保留旧成品。
            detail = re.sub(r"https?://\S+", "[服务地址]", str(exc))[:500]
            message = f"{type(exc).__name__}: {detail}"
        print(f"在线自然语音合成失败：{message}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
