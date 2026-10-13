#!/usr/bin/env bash
set -euo pipefail
"${ADB:-adb}" shell am broadcast -n com.julianamarques.galaxybridge.spike/.CommandReceiver \
    -a com.julianamarques.galaxybridge.spike.SET_MODE --es mode "${1:?modo}"
