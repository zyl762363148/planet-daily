#!/bin/bash
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1

export DIGEST_DATA_ROOT="${DIGEST_DATA_ROOT:-$HOME/Library/Application Support/DailyDigest}"
mkdir -p "$DIGEST_DATA_ROOT/logs" || exit 1

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG="${LANG:-zh_CN.UTF-8}"
export PYTHONIOENCODING=utf-8

unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy

LOCKDIR="$DIGEST_DATA_ROOT/.generate.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    if [ -n "$(find "$LOCKDIR" -maxdepth 1 -mmin +30 2>/dev/null)" ]; then
        rmdir "$LOCKDIR" 2>/dev/null || true
        mkdir "$LOCKDIR" 2>/dev/null || exit 0
    else
        echo "日报生成已在运行，跳过重复任务。"
        exit 0
    fi
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

LOG="$DIGEST_DATA_ROOT/logs/generate-$(date +%Y-%m-%d).log"
{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') start ==="
    if [ "${1:-}" = "--scheduled" ] && [ "$(date +%H)" != "09" ]; then
        export DIGEST_ROLLING=1
        echo "模式：滚动增量（定时触发，非 09:00 全量档）"
    else
        echo "模式：全量生成"
    fi
    /usr/bin/caffeinate -is /usr/bin/python3 "$DIR/generate.py"
    code=$?
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') exit=$code ==="
    exit "$code"
} >> "$LOG" 2>&1
