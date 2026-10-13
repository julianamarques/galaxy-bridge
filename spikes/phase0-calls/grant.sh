#!/usr/bin/env bash
set -euo pipefail
PKG=com.julianamarques.galaxybridge.spike
for p in READ_PHONE_STATE READ_CALL_LOG ANSWER_PHONE_CALLS CALL_PHONE READ_CONTACTS; do
    "${ADB:-adb}" shell pm grant "$PKG" "android.permission.$p"
done
"${ADB:-adb}" shell cmd notification allow_listener "$PKG/$PKG.CallListenerService"
echo "Permissões concedidas."
