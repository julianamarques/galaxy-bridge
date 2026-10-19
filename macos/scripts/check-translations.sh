#!/usr/bin/env bash
# Lists the Mac app's texts that have no English translation in
# Resources/en.lproj/Localizable.strings, and translations no text uses anymore.
# The keys come from the Swift compiler (-emit-localized-strings), the same
# source Xcode uses for String Catalogs, so they match what the app looks up.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A clean build is needed: an incremental one only emits the files it recompiles.
swift build --scratch-path "$WORK/build" \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK/strings" >/dev/null

python3 -I - "$WORK/strings" Sources Resources/en.lproj/Localizable.strings <<'PY'
import json, os, subprocess, sys
strings_dir, sources, table = sys.argv[1:4]
ours = {os.path.splitext(f)[0] for root, _, files in os.walk(sources) for f in files if f.endswith(".swift")}
keys = set()
for name in os.listdir(strings_dir):
    if os.path.splitext(name)[0] in ours:
        data = json.load(open(os.path.join(strings_dir, name)))
        for entries in data.get("tables", {}).values():
            keys.update(entry["key"] for entry in entries)
translated = set(json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", table], check=True, capture_output=True).stdout))
missing, unused = sorted(keys - translated), sorted(translated - keys)
for key in missing:
    print("sem tradução:", key)
for key in unused:
    print("sem uso:", key)
print(f"{len(keys)} textos, {len(missing)} sem tradução, {len(unused)} sem uso")
sys.exit(1 if missing else 0)
PY
