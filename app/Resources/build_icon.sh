#!/bin/bash
# 共享原生矢量路径生成图标母版和完整 macOS iconset，不使用外部依赖。
set -euo pipefail
cd "$(dirname "$0")"

ICON_WORK="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK"' EXIT

swiftc -swift-version 5 -parse-as-library \
    -target arm64-apple-macosx14.0 \
    -module-cache-path "${TMPDIR:-/tmp}/dailydigest-icon-module-cache" \
    ../Sources/BrandMark.swift make_icon.swift \
    -o "$ICON_WORK/make-icon"

"$ICON_WORK/make-icon" "$ICON_WORK/AppIcon.png" 1024
ICONSET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for side in 16 32 128 256 512; do
    # 每个尺寸直接渲染矢量，避免缩略图二次采样损失负形与小信号点。
    "$ICON_WORK/make-icon" "$ICONSET/icon_${side}x${side}.png" "$side"
    double=$((side * 2))
    "$ICON_WORK/make-icon" "$ICONSET/icon_${side}x${side}@2x.png" "$double"
done

if ! iconutil -c icns "$ICONSET" -o "$ICON_WORK/AppIcon.icns" 2>"$ICON_WORK/iconutil.log"; then
    # 某些精简系统无法调用 ICNS 编码器；标准 PNG 图块容器可直接打包。
    # 仍用系统 iconutil 解包校验，确保 Finder 能识别交付。
    echo "系统图标编码器不可用，使用标准 ICNS PNG 容器打包。"
    /usr/bin/python3 - "$ICONSET" "$ICON_WORK/AppIcon.icns" <<'PYICON'
from pathlib import Path
import struct
import sys
root, output = Path(sys.argv[1]), Path(sys.argv[2])
assets = [
    ("icp4", "icon_16x16.png", 16), ("icp5", "icon_32x32.png", 32),
    ("icp6", "icon_32x32@2x.png", 64), ("ic07", "icon_128x128.png", 128),
    ("ic08", "icon_256x256.png", 256), ("ic09", "icon_512x512.png", 512),
    ("ic10", "icon_512x512@2x.png", 1024), ("ic11", "icon_16x16@2x.png", 32),
    ("ic12", "icon_32x32@2x.png", 64), ("ic13", "icon_128x128@2x.png", 256),
    ("ic14", "icon_256x256@2x.png", 512),
]
chunks = []
for tag, filename, side in assets:
    image = (root / filename).read_bytes()
    assert image[:8] == b"\x89PNG\r\n\x1a\n", filename
    assert struct.unpack(">II", image[16:24]) == (side, side), filename
    chunks.append(tag.encode("ascii") + struct.pack(">I", len(image) + 8) + image)
body = b"".join(chunks)
output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
PYICON
fi
iconutil -c iconset "$ICON_WORK/AppIcon.icns" -o "$ICON_WORK/Verified.iconset"
# 生成成功后再替换现有交付，避免编译失败留下半成品。
cp "$ICON_WORK/AppIcon.png" AppIcon.png
cp "$ICON_WORK/AppIcon.icns" AppIcon.icns
mkdir -p previews
for side in 16 32 128; do
    cp "$ICONSET/icon_${side}x${side}.png" "previews/AppIcon-${side}.png"
done
printf '已生成：%s/AppIcon.png\n已生成：%s/AppIcon.icns\n' "$(pwd)" "$(pwd)"
