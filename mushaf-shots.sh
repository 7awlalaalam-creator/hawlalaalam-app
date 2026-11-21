#!/bin/bash
# لقطات من داخل التطبيق لصفحات مصحف المدينة (للمراجعة فقط)
set -x
pip install -q websocket-client 2>/dev/null || pip install -q --break-system-packages websocket-client
P=com.hawlalaalam.quran
APK=$(ls app/build/outputs/apk/debug/*.apk | head -1)
adb install -r -g "$APK"
mkdir -p shots
adb shell pm grant $P android.permission.POST_NOTIFICATIONS || true
cap() { adb exec-out screencap -p > "shots/$1.png"; }
openPage() {   # يفتح المصحف على الصفحة $1 في وضع «المصحف»
  python3 cdp.py "localStorage.setItem('hawl_reader', JSON.stringify(Object.assign(JSON.parse(localStorage.getItem('hawl_reader')||'{}'),{mode:'mushaf',qpc:true}))); location.href=location.pathname+'?page=$1'; 1"
  sleep 20
}
run() {
  local m=$1
  adb shell am force-stop $P
  adb shell am start -n "$P/.MainActivity"; sleep 12
  cap $m-00-start
  for p in 106 604 1 50 255; do openPage $p; cap $m-mushaf-$p; done
  python3 cdp.py "JSON.stringify({fw:document.getElementById('fw').className,l:document.querySelectorAll('.qp-l').length})" > shots/$m-dom.txt
}
adb logcat -c
run light
adb logcat -d | grep -iE "AndroidRuntime|FATAL|crash|lowmemory|killing|hawlalaalam|chromium" | tail -150 > shots/light-log.txt
ls -la shots
