#!/bin/bash
# لقطات على شاشة قابلة للطي: مطوية (الأمامية) ومفتوحة (الداخلية الكبيرة) بمقاسات Galaxy Z Fold
set -x
P=com.hawlalaalam.quran
adb install -r -g $(ls app/build/outputs/apk/debug/*.apk | head -1)
mkdir -p shots
adb emu geo fix 39.1925 21.4858
adb shell monkey -p $P -c android.intent.category.LAUNCHER 1; sleep 6; adb shell am force-stop $P
NOW=$(adb shell date +%s | tr -d '\r'); DAY=$((NOW/86400))
cat > /tmp/s.xml <<X
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
<boolean name="welcomed" value="true" />
<int name="tour_v" value="99" />
<string name="app_lang">ar</string>
<float name="lat" value="21.4858" />
<float name="lng" value="39.1925" />
<string name="city">جدة</string>
<long name="update_checked" value="${NOW}000" />
</map>
X
B=$(python3 -c "print('1'*96+'0'*508)")
cat > /tmp/k.xml <<X
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
<boolean name="active" value="true" /><string name="mode">days</string><int name="ppd" value="20" />
<int name="start_page" value="1" /><int name="off_days" value="0" />
<long name="start" value="$((DAY-5))" /><long name="end" value="$((DAY+25))" />
<long name="base_day" value="$((DAY-5))" /><int name="base_read" value="0" />
<string name="label">ختمتي</string><string name="pages">$B</string>
</map>
X
adb push /tmp/s.xml /data/local/tmp/s.xml; adb push /tmp/k.xml /data/local/tmp/k.xml
adb shell "run-as $P sh -c 'mkdir -p shared_prefs; cp /data/local/tmp/s.xml shared_prefs/settings.xml; cp /data/local/tmp/k.xml shared_prefs/khatma.xml'"
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
clean() {   # يغلق نوافذ النظام (تعليق المشغّل في المحاكي) قبل التصوير
  for i in 1 2 3; do tapText "Wait"; tapText "انتظار"; done
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1
}
snap() { sleep 2; clean; sleep 1; adb exec-out screencap -p > shots/$1.png; }
shoot() {  # shoot NAME
  adb shell am force-stop $P
  adb shell monkey -p $P -c android.intent.category.LAUNCHER 1 >/dev/null; sleep 9; tapText "لاحقًا"; snap $1-1-today
  tapText "الأدوات"; sleep 5; snap $1-2-tools
  tapText "المصحف"; sleep 9; snap $1-3-mushaf
  tapText "اليوم"; sleep 4; tapText "أكمل القراءة"; sleep 1; adb shell input keyevent KEYCODE_BACK; sleep 2
  tapText "الأدوات"; sleep 4; tapText "ختمتي"; sleep 5; snap $1-4-khatma
}
# مطوية: الشاشة الأمامية (Galaxy Z Fold: 904×2316 تقريبًا)
adb shell wm size 904x2316; adb shell wm density 400; sleep 3
shoot fold-closed
# مفتوحة: الشاشة الداخلية (1812×2176)
adb shell wm size 1812x2176; adb shell wm density 380; sleep 3
shoot fold-open
# فتح الجوال أثناء القراءة: المصحف مطوي ثم يُفتح دون إغلاق التطبيق
adb shell wm size 904x2316; adb shell wm density 400; sleep 2
adb shell am force-stop $P; adb shell monkey -p $P -c android.intent.category.LAUNCHER 1 >/dev/null; sleep 8; tapText "المصحف"; sleep 9; snap fold-live-before
adb shell wm size 1812x2176; adb shell wm density 380; sleep 5; snap fold-live-unfold
adb shell wm size reset; adb shell wm density reset
adb logcat -d | grep -E "FATAL EXCEPTION" -A20 > shots/fatal.txt || true
ls -la shots
