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
shoot() {  # shoot NAME
  adb shell am force-stop $P
  adb shell am start -n $P/.HomeActivity >/dev/null; sleep 8; adb exec-out screencap -p > shots/$1-1-today.png
  adb shell am start -n $P/.ToolsActivity >/dev/null; sleep 6; adb exec-out screencap -p > shots/$1-2-tools.png
  adb shell am start -n $P/.MainActivity -a android.intent.action.VIEW -d "https://7awlalaalam.com/__hawl/mushaf-pages-offline.html?page=97" >/dev/null; sleep 10
  adb exec-out screencap -p > shots/$1-3-mushaf.png
  adb shell am start -n $P/.KhatmaActivity >/dev/null; sleep 5; adb exec-out screencap -p > shots/$1-4-khatma.png
}
# مطوية: الشاشة الأمامية (Galaxy Z Fold: 904×2316 تقريبًا)
adb shell wm size 904x2316; adb shell wm density 400; sleep 3
shoot fold-closed
# مفتوحة: الشاشة الداخلية (1812×2176)
adb shell wm size 1812x2176; adb shell wm density 380; sleep 3
shoot fold-open
# فتح الجوال أثناء القراءة: المصحف مطوي ثم يُفتح دون إغلاق التطبيق
adb shell wm size 904x2316; adb shell wm density 400; sleep 2
adb shell am start -n $P/.MainActivity -a android.intent.action.VIEW -d "https://7awlalaalam.com/__hawl/mushaf-pages-offline.html?page=50" >/dev/null; sleep 9
adb shell wm size 1812x2176; adb shell wm density 380; sleep 5; adb exec-out screencap -p > shots/fold-live-unfold.png
adb shell wm size reset; adb shell wm density reset
adb logcat -d | grep -E "FATAL EXCEPTION" -A20 > shots/fatal.txt || true
ls -la shots
