#!/bin/zsh
# Package Mochi for download: a universal (Apple Silicon + Intel) app in a zip.
# Output: dist/Mochi-<version>.zip
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP="dist/Mochi.app"
ZIP="dist/Mochi-$VERSION.zip"

# Separate builds per architecture: the Command Line Tools can't build multi-arch in one go.
swift build -c release --arch arm64 --product Mochi
swift build -c release --arch x86_64 --product Mochi
ARM="$(swift build -c release --arch arm64 --show-bin-path)/Mochi"
X86="$(swift build -c release --arch x86_64 --show-bin-path)/Mochi"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/Mochi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature: no Apple Developer ID, so Gatekeeper asks users to "Open Anyway" once.
codesign --force --sign - --identifier com.anh.mochi "$APP"
codesign --verify --strict "$APP"

# ditto keeps the bundle's metadata and signature intact (plain zip can break it).
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

lipo -info "$APP/Contents/MacOS/Mochi"
echo "Built $ZIP"
