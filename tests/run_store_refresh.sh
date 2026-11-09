#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_TEMP="$(mktemp -d /tmp/digest-refresh-check.XXXXXX)"
trap 'rm -rf "$TASK_TEMP"' EXIT
TASK_SOURCES=()
for TASK_SOURCE in "$TASK_ROOT"/app/Sources/*.swift; do
  if [[ "$TASK_SOURCE" != */DailyDigestApp.swift ]]; then
    TASK_SOURCES+=("$TASK_SOURCE")
  fi
done
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit -framework AVFoundation \
  "${TASK_SOURCES[@]}" "$TASK_ROOT/tests/StoreRefreshChecks.swift" -o "$TASK_TEMP/check"
"$TASK_TEMP/check"
