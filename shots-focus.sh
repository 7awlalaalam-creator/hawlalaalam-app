#!/bin/bash
# فحص مركّز للمميزات الجديدة: المساجد القريبة وصفحة المصحف (مع سجل الأخطاء)
set -x
P=com.hawlalaalam.quran
APK=$(ls app/build/outputs/apk/debug/*.apk | head -1)
adb install -r -g "$APK"
mkdir -p shots
adb shell pm grant $P android.permission.ACCESS_COARSE_LOCATION || true
adb shell pm grant $P android.permission.POST_NOTIFICATIONS || true
adb emu geo fix 39.1925 21.4858
adb shell am start -n $P/.HomeActivity; sleep 8
adb logcat -c
adb shell am start -n $P/.MosquesActivity; sleep 25
adb exec-out screencap -p > shots/m1-mosques.png
adb logcat -d | grep -iE "AndroidRuntime|FATAL|chromium|Mosq|Exception|console" | tail -150 > shots/m1-mosques-log.txt
adb shell input tap 160 2200; sleep 3; adb exec-out screencap -p > shots/m2-nearest.png
adb shell am force-stop $P
adb logcat -c
adb shell am start -n $P/.ToolsActivity; sleep 6
adb exec-out screencap -p > shots/m3-tools.png
adb shell uiautomator dump /sdcard/u.xml >/dev/null; adb pull /sdcard/u.xml shots/tools-ui.txt
B=$(grep -o 'text="مساجد قريبة"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' shots/tools-ui.txt | grep -o 'bounds="[^"]*"' | head -1)
echo "bounds $B"
if [ -n "$B" ]; then XY=$(echo $B | sed -E 's/bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]"/\1 \2 \3 \4/'); set -- $XY; adb shell input tap $(( ($1+$3)/2 )) $(( ($2+$4)/2 )); fi
sleep 20; adb exec-out screencap -p > shots/m4-from-tools.png
adb logcat -d | grep -iE "AndroidRuntime|FATAL|chromium|Mosq|Exception|ActivityTaskManager" | tail -150 > shots/m4-tools-log.txt
ls -la shots
