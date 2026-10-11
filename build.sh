#!/bin/zsh
# Build Mochi.app, install to ~/Applications, and launch it.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP="build/Mochi.app"
DEST="$HOME/Applications/Mochi.app"

swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Mochi"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Mochi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.anh.mochi "$APP"

pkill -x Mochi 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

if [[ "${NO_OPEN:-0}" != "1" ]]; then
    open "$DEST"
fi
echo "Installed $DEST"
