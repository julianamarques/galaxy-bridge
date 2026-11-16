#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Galaxy Bridge.app"
DMG="build/Galaxy Bridge.dmg"
STAGE="build/dmg"

./scripts/build-app.sh "$@"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Aplicativos"
hdiutil create -quiet -volname "Galaxy Bridge" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "Pronto: $DMG"
