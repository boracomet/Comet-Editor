#!/usr/bin/env bash
# Yerel / CI: derleme + i18n doğrulama
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== xcodebuild Debug =="
xcodebuild -project cometeditor.xcodeproj -scheme cometeditor -configuration Debug build -quiet

echo "== i18n export + verify =="
python3 scripts/i18n_sync.py export
python3 scripts/i18n_sync.py verify

echo "ci_smoke: OK"
