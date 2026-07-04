#!/bin/bash
# Builds Bolt.app from the SPM executable and ad-hoc signs it.
# Usage:
#   ./build-app.sh            build release .app into ./dist
#   ./build-app.sh --install  also copy to /Applications and launch
set -euo pipefail

cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

BIN=".build/release/Bolt"
APP="dist/Bolt.app"

echo "==> assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bolt"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Strip symbols and the debug map; otherwise the binary embeds absolute
# source paths from the build machine (a privacy leak if the .app is shared).
echo "==> strip"
strip "$APP/Contents/MacOS/Bolt"

# Ad-hoc signature: enough for a personal, non-distributed build. A stable
# signature also keeps the TCC permission grants (Accessibility etc.)
# attached across rebuilds of the same bundle path.
echo "==> codesign (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> done: $APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> installing to /Applications"
    # Quit a running copy first so the binary can be replaced.
    pkill -x Bolt 2>/dev/null || true
    sleep 0.5
    rm -rf /Applications/Bolt.app
    cp -R "$APP" /Applications/
    echo "==> launching"
    open /Applications/Bolt.app
fi
