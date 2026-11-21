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
  adb shell am start -n "$P/.HomeActivity"; sleep 10
  # شاشة الترحيب في أول تشغيل: زر «ابدأ رحلتك مع القرآن»
  adb shell input tap 540 1875; sleep 8
  cap $1-today-1
  adb shell input swipe 540 1900 540 700 600; sleep 3; cap $1-today-2
  adb shell input swipe 540 1900 540 700 600; sleep 3; cap $1-today-3
  adb shell input tap 135 2235; sleep 8     # «الأدوات» في الشريط السفلي (يسار في العربية)
  cap $1-tools-1
  adb shell input swipe 540 1900 540 700 600; sleep 3; cap $1-tools-2
  adb shell input swipe 540 1900 540 700 600; sleep 3; cap $1-tools-3
}
today light
adb shell cmd uimode night yes; sleep 3
today dark
ls -la shots
