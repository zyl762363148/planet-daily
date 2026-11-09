#!/bin/bash
set -euo pipefail

echo "=================================================="
echo "  《行星日报》PRO · 全面升级一键部署脚本"
echo "=================================================="

USER_HOME="/Users/c"
SRC_PROJECT="/tmp/DailyDigest"
SRC_DATA="/tmp/DailyDigestData"
DST_PROJECT="$USER_HOME/Developer/DailyDigest"
DST_DATA="$USER_HOME/Library/Application Support/DailyDigest"
LAUNCH_AGENTS="$USER_HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"

# 1. 同步后端与前端源码
echo "→ [1/5] 正在同步升级后的源码到 $DST_PROJECT ..."
mkdir -p "$DST_PROJECT/app/Sources" "$DST_PROJECT/backend"
cp -f "$SRC_PROJECT/build.sh" "$DST_PROJECT/build.sh"
cp -f "$SRC_PROJECT/app/Sources/"*.swift "$DST_PROJECT/app/Sources/"
cp -f "$SRC_PROJECT/backend/"*.py "$DST_PROJECT/backend/"
cp -f "$SRC_PROJECT/backend/run_generate.sh" "$DST_PROJECT/backend/run_generate.sh"
chmod +x "$DST_PROJECT/build.sh" "$DST_PROJECT/backend/run_generate.sh" "$DST_PROJECT/backend/generate.py" "$DST_PROJECT/backend/tts_brief.py" "$DST_PROJECT/backend/speak_brief.py"

# 2. 同步升级后的 24h 多视角早报数据与 09:30 配置
echo "→ [2/5] 正在同步 24 小时全球深度早报数据与 09:30 播报配置 ..."
mkdir -p "$DST_DATA/data/tts" "$DST_DATA/logs" "$DST_DATA/cache" "$DST_DATA/reports"
cp -f "$SRC_DATA/config.json" "$DST_DATA/config.json"
cp -f "$SRC_DATA/data/"*.json "$DST_DATA/data/"
cp -f "$SRC_DATA/data/tts/"* "$DST_DATA/data/tts/" 2>/dev/null || true

# 3. 合成今日 24h 全球大事早报语音音频（优先 Neural TTS 云扬主播，自动回退本地语音）
echo "→ [3/5] 正在渲染今日 24 小时全球早报高质量语音音频 ..."
/usr/bin/python3 "$DST_PROJECT/backend/tts_brief.py" --date "$(date +%Y-%m-%d)" --no-ai || true

# 4. 安装全新编译的《行星日报.app》到 ~/Applications 与桌面
echo "→ [4/5] 正在安装新版《行星日报.app》到桌面 ..."
mkdir -p "$USER_HOME/Applications"
APP_BUNDLE="$USER_HOME/Applications/行星日报.app"
rm -rf "$APP_BUNDLE"
cp -R "$SRC_PROJECT/build/行星日报.app" "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
rm -rf "$USER_HOME/Desktop/行星日报.app"
ln -sfn "$APP_BUNDLE" "$USER_HOME/Desktop/行星日报.app"

# 5. 配置并加载每日 09:10 自动抓取梳理 + 09:30 准时自动语音播报 LaunchAgents
echo "→ [5/5] 正在配置每日 09:10 早报生成与 09:30 准时语音播报定时任务 ..."
mkdir -p "$LAUNCH_AGENTS"

cat > "$LAUNCH_AGENTS/com.c.dailydigest.generate.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.c.dailydigest.generate</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$DST_PROJECT/backend/run_generate.sh</string>
        <string>--scheduled</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Hour</key>
            <integer>9</integer>
            <key>Minute</key>
            <integer>10</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>12</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>16</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>20</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
    </array>
    <key>WorkingDirectory</key>
    <string>$DST_PROJECT/backend</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>LANG</key>
        <string>zh_CN.UTF-8</string>
        <key>PYTHONIOENCODING</key>
        <string>utf-8</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$DST_DATA/logs/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>$DST_DATA/logs/launchd.err.log</string>
</dict>
</plist>
EOF

cat > "$LAUNCH_AGENTS/com.c.dailydigest.speak.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.c.dailydigest.speak</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$DST_PROJECT/backend/speak_brief.py</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>WorkingDirectory</key>
    <string>$DST_PROJECT/backend</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>LANG</key>
        <string>zh_CN.UTF-8</string>
    </dict>
</dict>
</plist>
EOF

for label in com.c.dailydigest.generate com.c.dailydigest.speak; do
    launchctl bootout "gui/$UID_NUM/$label" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$UID_NUM" "$LAUNCH_AGENTS/$label.plist" >/dev/null 2>&1 || launchctl load -w "$LAUNCH_AGENTS/$label.plist" >/dev/null 2>&1 || true
    launchctl enable "gui/$UID_NUM/$label" >/dev/null 2>&1 || true
done

# 重启行星日报 App 展示全新界面
killall DailyDigest >/dev/null 2>&1 || true
open "$APP_BUNDLE"

echo ""
echo "✅ 升级完成！《行星日报》已自动打开，每日 09:30 自动播报已生效。"
