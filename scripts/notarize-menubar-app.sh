#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/menubar-app/build/export/Dev Dashboard.app"
ZIP_PATH="$ROOT/menubar-app/build/export/Dev Dashboard.zip"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Exported app not found at $APP_PATH" >&2
  exit 1
fi

echo "Packaging app for notarization..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ -n "${APPLE_NOTARYTOOL_PROFILE:-}" ]]; then
  echo "Submitting for notarization with Keychain profile: $APPLE_NOTARYTOOL_PROFILE"
  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$APPLE_NOTARYTOOL_PROFILE" \
    --wait
else
  : "${APPLE_ID:?APPLE_ID is not set}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"
  : "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is not set}"

  echo "Submitting for notarization with Apple ID: $APPLE_ID"
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
fi

echo "Applying staple to the app..."
xcrun stapler staple "$APP_PATH"

echo "Validating with Gatekeeper..."
spctl -a -t exec -vv "$APP_PATH"

echo "Notarization completed."
