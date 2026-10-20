#!/usr/bin/env bash
# Builds Murmur.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Murmur.app"
cd "$ROOT"

echo "▸ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Murmur" "$APP/Contents/MacOS/Murmur"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# SwiftPM resource bundles from dependencies, if any.
find "$BIN" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "▸ Rendering icon…"
  TMP="$(mktemp -d)"
  swift "$ROOT/scripts/make_icon.swift" "$TMP/AppIcon.iconset"
  iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
  rm -rf "$TMP"
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - --identifier com.murmur.dictation "$APP"

echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Murmur 2>/dev/null || true
  rm -rf /Applications/Murmur.app
  cp -R "$APP" /Applications/Murmur.app
  echo "✓ Installed to /Applications/Murmur.app"
  open /Applications/Murmur.app
fi
