#!/usr/bin/env bash
# Baixa o servidor do scrcpy, que o Mac envia ao Galaxy pelo adb para espelhar a tela.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="5.0"
SHA256="26cbc9ad0aced6c2282455bef4fb43462605c1f8758c74b4ab1dbf818c229daa"
TARGET="Resources/scrcpy-server"
LICENSE="Resources/scrcpy-LICENSE.txt"
STAMP="Resources/scrcpy.version"

if [ -f "$TARGET" ] && [ -f "$LICENSE" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$VERSION" ]; then
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -sSfL -o "$WORK/scrcpy-server" "https://github.com/Genymobile/scrcpy/releases/download/v$VERSION/scrcpy-server-v$VERSION"
echo "$SHA256  $WORK/scrcpy-server" | shasum -a 256 -c --status || { echo "Checksum inválido para o scrcpy-server" >&2; exit 1; }
curl -sSfL -o "$WORK/LICENSE" "https://raw.githubusercontent.com/Genymobile/scrcpy/v$VERSION/LICENSE"
mv "$WORK/scrcpy-server" "$TARGET"
mv "$WORK/LICENSE" "$LICENSE"
echo "$VERSION" > "$STAMP"
