#!/bin/bash
# فحص مركّز: نسخة GitHub المنشورة نفسها (release) → الترحيب → الأدوات → «مساجد قريبة»، مع سجل الأعطال
set -x
P=com.hawlalaalam.quran
curl -sSL -o rel.apk https://github.com/7awlalaalam-creator/hawlalaalam-app/releases/latest/download/hawlalaalam-quran.apk
adb install -r -g rel.apk || adb install -r -g $(ls app/build/outputs/apk/debug/*.apk | head -1)
mkdir -p shots
adb emu geo fix 39.1925 21.4858
tapText() {   # tapText "نص"
  adb shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1; adb pull /sdcard/u.xml /tmp/u.xml >/dev/null 2>&1
  B=$(python3 - "$1" <<'PY'
import sys,re
s=open('/tmp/u.xml',encoding='utf-8').read()
for m in re.finditer(r'<node [^>]*>',s):
    n=m.group(0)
    if sys.argv[1] in n:
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
        if b:
            x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); break
PY
)
  echo "tap $1 -> $B"; [ -n "$B" ] && adb shell input tap $B
}
adb shell am start -n $P/.WelcomeActivity || adb shell monkey -p $P -c android.intent.category.LAUNCHER 1
sleep 8; adb exec-out screencap -p > shots/f0.png
tapText "Begin your journey"; tapText "ابدأ رحلتك"; sleep 6
adb exec-out screencap -p > shots/f1.png
tapText "Tools"; tapText "الأدوات"; sleep 4
adb exec-out screencap -p > shots/f2.png
adb logcat -c
tapText "Nearby mosques"; tapText "مساجد قريبة"; sleep 9; adb exec-out screencap -p > shots/f3a.png; sleep 5
adb exec-out screencap -p > shots/f3-mosques.png
adb logcat -d > /tmp/all.txt
grep -E "AndroidRuntime|FATAL|$P|chromium|Console|ActivityTaskManager" /tmp/all.txt | tail -200 > shots/f3-log.txt
grep -A40 "FATAL EXCEPTION" /tmp/all.txt > shots/f3-fatal.txt || true
ls -la shots
