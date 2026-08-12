#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_DIR="$PROJECT_DIR/dist/EchoCue.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/.build/release/EchoCue" "$CONTENTS_DIR/MacOS/EchoCue"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
