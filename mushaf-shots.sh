#!/bin/bash
# لقطات من داخل التطبيق: شاشة «اليوم» وصفحات مصحف المدينة، بالعربية (للمراجعة فقط)
set -x
pip install -q websocket-client 2>/dev/null || pip install -q --break-system-packages websocket-client
P=com.hawlalaalam.quran
APK=$(ls app/build/outputs/apk/debug/*.apk | head -1)
adb install -r -g "$APK"
mkdir -p shots
adb shell pm grant $P android.permission.POST_NOTIFICATIONS || true
adb shell pm grant $P android.permission.ACCESS_COARSE_LOCATION || true
adb emu geo fix 39.1925 21.4858
adb shell cmd locale set-app-locales $P --locales ar || true
cap() { adb exec-out screencap -p > "shots/$1.png"; }
openPage() {
  python3 cdp.py "localStorage.setItem('hawl_reader', JSON.stringify(Object.assign(JSON.parse(localStorage.getItem('hawl_reader')||'{}'),{mode:'mushaf',qpc:true}))); location.href=location.pathname+'?page=$1'; 1"
  sleep 20
}
today() {
  adb shell am force-stop $P
  adb shell am start -n "$P/.HomeActivity"; sleep 12
  cap $1-today-1
  adb shell input swipe 540 1900 540 700 600; sleep 3; cap $1-today-2
  adb shell input swipe 540 1900 540 700 600; sleep 3; cap $1-today-3
  adb shell am force-stop $P
  adb shell am start -n "$P/.ToolsActivity"; sleep 10
  cap $1-tools-1
  adb shell input swipe 540 1900 540 700 600; sleep 3; cap $1-tools-2
  adb shell input swipe 540 1900 540 700 600; sleep 3; cap $1-tools-3
}
adb logcat -c
today light
adb shell am force-stop $P
adb shell am start -n "$P/.MainActivity"; sleep 12
for p in 106 604 50; do openPage $p; cap light-mushaf-$p; done
adb logcat -d | grep -iE "AndroidRuntime|FATAL|crash|lowmemory|killing|died|hawlalaalam" | tail -150 > shots/light-log.txt
adb shell cmd uimode night yes; sleep 3
today dark
ls -la shots
