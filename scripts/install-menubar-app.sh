#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Dev Dashboard.app"
ARCHIVE_PATH="$ROOT/menubar-app/build/DevDashboardMenuBar.xcarchive"
APP_SOURCE="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
APP_DEST="/Applications/$APP_NAME"
LEGACY_APP_DEST="/Applications/DevDashboardMenuBar.app"

cd "$ROOT"

echo "Generating app icons..."
swift "$ROOT/scripts/generate-menubar-icons.swift"

echo "Generating Xcode project..."
cd "$ROOT/menubar-app"
xcodegen generate >/dev/null

echo "Archiving menu bar app..."
xcodebuild \
  -project "$ROOT/menubar-app/DevDashboardMenuBar.xcodeproj" \
  -scheme DevDashboardMenuBar \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  archive \
  -archivePath "$ARCHIVE_PATH" >/dev/null

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Archived app not found at $APP_SOURCE" >&2
  exit 1
fi

echo "Installing to $APP_DEST ..."
rm -rf "$LEGACY_APP_DEST"
rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"

echo "Installed. Opening app..."
open "$APP_DEST"

echo "Done."
