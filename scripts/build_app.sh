#!/usr/bin/env bash
# Builds Echo.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Echo.app"
cd "$ROOT"

echo "▸ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Echo" "$APP/Contents/MacOS/Echo"
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
codesign --force --deep --sign - --identifier com.echo.dictation "$APP"

echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Echo 2>/dev/null || true
  rm -rf /Applications/Echo.app
  cp -R "$APP" /Applications/Echo.app
  echo "✓ Installed to /Applications/Echo.app"
  open /Applications/Echo.app
fi
