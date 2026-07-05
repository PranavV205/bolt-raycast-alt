#!/bin/bash
# Builds Bolt.app from the SPM executable and ad-hoc signs it.
# Usage:
#   ./build-app.sh            build release .app into ./dist
#   ./build-app.sh --install  also copy to /Applications and launch
set -euo pipefail

cd "$(dirname "$0")"

# UNIVERSAL=1 builds a fat arm64+x86_64 binary (used by the release workflow
# so Intel Macs can run downloaded builds). Local builds stay single-arch.
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    echo "==> swift build -c release (universal)"
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release/Bolt"
else
    echo "==> swift build -c release"
    swift build -c release
    BIN=".build/release/Bolt"
fi

APP="dist/Bolt.app"

echo "==> assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bolt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Strip symbols and the debug map; otherwise the binary embeds absolute
# source paths from the build machine (a privacy leak if the .app is shared).
echo "==> strip"
strip "$APP/Contents/MacOS/Bolt"

# Prefer a stable signing identity when one exists: macOS ties permission
# grants (Accessibility etc.) to the signer, so a real certificate keeps
# them across rebuilds. Ad-hoc signatures change every build and lose them.
# Create one via Keychain Access > Certificate Assistant (type: Code
# Signing, name: "Bolt Dev"), or override with CODESIGN_IDENTITY.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"Bolt Dev"'; then
    IDENTITY="Bolt Dev"
fi
echo "==> codesign (${IDENTITY:-ad-hoc})"
codesign --force --sign "${IDENTITY:--}" "$APP"

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
