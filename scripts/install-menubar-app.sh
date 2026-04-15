#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Dev Dashboard.app"
ARCHIVE_PATH="$ROOT/menubar-app/build/DevDashboardMenuBar.xcarchive"
EXPORT_DIR="$ROOT/menubar-app/build/export"
APP_SOURCE="$EXPORT_DIR/$APP_NAME"
APP_DEST="/Applications/$APP_NAME"
LEGACY_APP_DEST="/Applications/DevDashboardMenuBar.app"
EXPORT_OPTIONS_PLIST="$ROOT/menubar-app/build/ExportOptions.generated.plist"

function first_identity_matching() {
  local pattern="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -v pattern="$pattern" -F '"' '$2 ~ pattern { print $2; exit }'
}

function extract_team_id() {
  local identity="$1"
  if [[ "$identity" =~ \(([A-Z0-9]+)\)$ ]]; then
    echo "${match[1]}"
  fi
}

SIGNING_IDENTITY="${DEV_DASHBOARD_CODE_SIGN_IDENTITY:-$(first_identity_matching "Developer ID Application")}"
EXPORT_METHOD="developer-id"
SIGNING_CERTIFICATE="Developer ID Application"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(first_identity_matching "Apple Development")"
  EXPORT_METHOD="development"
  SIGNING_CERTIFICATE="Apple Development"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "No code signing identity found in Keychain." >&2
  echo "Set DEV_DASHBOARD_CODE_SIGN_IDENTITY to a valid identity and try again." >&2
  exit 1
fi

TEAM_ID="${DEV_DASHBOARD_TEAM_ID:-$(extract_team_id "$SIGNING_IDENTITY")}"

if [[ -z "$TEAM_ID" ]]; then
  echo "Unable to determine DEVELOPMENT_TEAM from signing identity: $SIGNING_IDENTITY" >&2
  echo "Set DEV_DASHBOARD_TEAM_ID and try again." >&2
  exit 1
fi

cd "$ROOT"

echo "Generating app icons..."
swift "$ROOT/scripts/generate-menubar-icons.swift"

echo "Generating Xcode project..."
cd "$ROOT/menubar-app"
xcodegen generate >/dev/null

echo "Using signing identity: $SIGNING_IDENTITY"
echo "Using development team: $TEAM_ID"
echo "Export method: $EXPORT_METHOD"

mkdir -p "$EXPORT_DIR"
rm -rf "$ARCHIVE_PATH" "$APP_SOURCE"

cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$EXPORT_METHOD</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>signingCertificate</key>
  <string>$SIGNING_CERTIFICATE</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
</dict>
</plist>
EOF

echo "Archiving signed menu bar app..."
xcodebuild \
  -project "$ROOT/menubar-app/DevDashboardMenuBar.xcodeproj" \
  -scheme DevDashboardMenuBar \
  -configuration Release \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  archive \
  -archivePath "$ARCHIVE_PATH" >/dev/null

echo "Exporting signed app bundle..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  DEVELOPMENT_TEAM="$TEAM_ID" >/dev/null

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Exported app not found at $APP_SOURCE" >&2
  exit 1
fi

echo "Installing to $APP_DEST ..."
rm -rf "$LEGACY_APP_DEST"
rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"

echo "Installed. Opening app..."
open "$APP_DEST"

echo "Done."
