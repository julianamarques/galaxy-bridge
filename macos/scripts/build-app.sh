#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
ARCH_FLAGS=()
for arg in "$@"; do
    case "$arg" in
        --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
        -*) echo "opção desconhecida: $arg" >&2; exit 1 ;;
        *) CONFIG="$arg" ;;
    esac
done
APP="build/Galaxy Bridge.app"

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" --show-bin-path ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})/GalaxyBridge"

[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift
./scripts/fetch-adb.sh

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GalaxyBridge"
MIN_MACOS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist)"
xcrun vtool -set-build-version macos "$MIN_MACOS" "$(xcrun --show-sdk-version)" -replace \
    -output "$APP/Contents/MacOS/GalaxyBridge" "$APP/Contents/MacOS/GalaxyBridge" 2>/dev/null
# Recursos dos pacotes Swift (os dados de números de telefone do PhoneNumberKit); sem eles o app fecha ao abrir.
cp -R "$(dirname "$BIN")"/*.bundle "$APP/Contents/Resources/"
cp Resources/adb "$APP/Contents/MacOS/adb"
cp Resources/adb-NOTICE.txt "$APP/Contents/Resources/adb-NOTICE.txt"
cp ../LICENSE ../NOTICE "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Pronto: $APP"
