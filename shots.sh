#!/bin/bash
# يُشغَّل داخل محاكي أندرويد في GitHub Actions (android-shots.yml)
set -x
P=com.hawlalaalam.quran
APK=$(ls app/build/outputs/apk/debug/*.apk | head -1)
adb install -r -g "$APK"
mkdir -p shots
adb shell settings put system time_12_24 12
adb shell pm grant $P android.permission.POST_NOTIFICATIONS || true
adb shell pm grant $P android.permission.ACCESS_FINE_LOCATION || true
adb shell pm grant $P android.permission.ACCESS_COARSE_LOCATION || true
adb emu geo fix 39.1925 21.4858   # جدة
H=https://7awlalaalam.com/quran
shot() {   # shot name url-or-component [wait]
  adb shell am force-stop $P
  if [[ "$2" == http* ]]; then adb shell am start -a android.intent.action.VIEW -d "$2" -n $P/.MainActivity
  else adb shell am start -n "$P/$2"; fi
  sleep ${3:-6}
  adb exec-out screencap -p > "shots/$1.png"
}
run() {
  local m=$1
  shot ${m}-01-home .HomeActivity 8
  shot ${m}-02-listen "$H/quran-reciters-ar.html" 12
  adb shell input tap 540 900; sleep 6; adb exec-out screencap -p > shots/${m}-03-reciter.png
  shot ${m}-04-azkar "$H/azkar-morning-evening-ar.html" 6
  shot ${m}-05-prayer "$H/prayer-times-ar.html" 8
  shot ${m}-06-tafsir "$H/ayah-2-152.html" 6
  shot ${m}-07-family "$H/family-khatma.html" 8
  shot ${m}-08-tools .ToolsActivity 6
  adb logcat -c
  shot ${m}-09-mushaf .MainActivity 10
  adb logcat -d | grep -iE "AndroidRuntime|FATAL|chromium|hawl|Exception" | tail -80 > shots/${m}-mushaf-log.txt
  shot ${m}-10-mushaf-url "https://7awlalaalam.com/quran/index.php?action=quran" 10
}
run light
adb shell cmd uimode night yes; sleep 2
run dark
adb logcat -d -t 400 | grep -E "AndroidRuntime|FATAL|hawlalaalam" | tail -60 > shots/logcat.txt || true
ls -la shots
