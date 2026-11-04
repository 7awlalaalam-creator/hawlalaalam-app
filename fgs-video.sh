#!/bin/bash
# فيديو بيان Google Play: تشغيل التلاوة في الخلفية (FOREGROUND_SERVICE_MEDIA_PLAYBACK)
set -x
P=com.hawlalaalam.quran
adb install -r -g $(ls app/build/outputs/apk/debug/*.apk | head -1)
mkdir -p shots
adb shell monkey -p $P -c android.intent.category.LAUNCHER 1; sleep 6; adb shell am force-stop $P
NOW=$(adb shell date +%s | tr -d '\r')
cat > /tmp/s.xml <<X
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
<boolean name="welcomed" value="true" />
<int name="tour_v" value="99" />
<string name="app_lang">ar</string>
<long name="update_checked" value="${NOW}000" />
</map>
X
adb push /tmp/s.xml /data/local/tmp/s.xml
adb shell "run-as $P sh -c 'mkdir -p shared_prefs; cp /data/local/tmp/s.xml shared_prefs/settings.xml'"
tapText() {
  adb shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1; adb pull /sdcard/u.xml /tmp/u.xml >/dev/null 2>&1
  B=$(python3 - "$1" <<'PY'
import sys,re
s=open('/tmp/u.xml',encoding='utf-8').read()
for m in re.finditer(r'<node [^>]*>',s):
    n=m.group(0)
    if ('text="%s"'%sys.argv[1]) in n or ('content-desc="%s"'%sys.argv[1]) in n:
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
        if b:
            x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); break
PY
)
  echo "tap $1 -> $B"; [ -n "$B" ] && adb shell input tap $B
}
for i in 1 2 3; do tapText "Wait"; done
adb shell screenrecord --time-limit 75 --bit-rate 6000000 /sdcard/fgs.mp4 &
REC=$!
sleep 2
adb shell monkey -p $P -c android.intent.category.LAUNCHER 1 >/dev/null; sleep 7
tapText "لاحقًا"; sleep 1
tapText "الاستماع"; sleep 6
tapText "الإذاعات"; sleep 6
tapText "استمع"; sleep 12          # تبدأ التلاوة ويظهر المشغّل
adb shell input keyevent KEYCODE_HOME; sleep 8   # خارج التطبيق والتلاوة مستمرة
adb shell input swipe 540 10 540 1400 600; sleep 2; adb shell input swipe 540 300 540 1800 600; sleep 9   # أزرار التحكم في الإشعار
adb shell input keyevent KEYCODE_BACK; sleep 3
adb shell input keyevent KEYCODE_SLEEP; sleep 3; adb shell input keyevent KEYCODE_WAKEUP; sleep 8   # شاشة القفل
adb shell input keyevent KEYCODE_MENU; sleep 2
wait $REC
adb pull /sdcard/fgs.mp4 shots/fgs-media-playback.mp4
adb exec-out screencap -p > shots/fgs-last.png
ls -la shots
