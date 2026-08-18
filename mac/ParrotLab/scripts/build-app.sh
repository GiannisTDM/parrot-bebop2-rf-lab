#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_DIR="$PROJECT_DIR/dist/Parrot Lab.app"
ZIP_PATH="$PROJECT_DIR/dist/Parrot-Lab-macOS-arm64.zip"

cd "$PROJECT_DIR"
swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/.build/release/ParrotLab" "$APP_DIR/Contents/MacOS/ParrotLab"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod 755 "$APP_DIR/Contents/MacOS/ParrotLab"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
rm -f "$ZIP_PATH"
(
    cd "$PROJECT_DIR/dist"
    /usr/bin/zip -qry -X "$(basename "$ZIP_PATH")" "$(basename "$APP_DIR")"
)
printf '%s\n' "$APP_DIR"
printf '%s\n' "$ZIP_PATH"
