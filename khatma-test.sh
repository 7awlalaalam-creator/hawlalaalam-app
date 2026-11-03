#!/bin/bash
# فحص الختمة على محاكي حقيقي: الورد يتخطى المقروء، حساب الصفحات بالبقاء عليها، ٩٩٪ قبل الختم، الالتفاف من وسط المصحف
set -x
P=com.hawlalaalam.quran
adb install -r -g $(ls app/build/outputs/apk/debug/*.apk | head -1)
mkdir -p shots
adb shell monkey -p $P -c android.intent.category.LAUNCHER 1; sleep 6; adb shell am force-stop $P
NOW=$(adb shell date +%s | tr -d '\r'); DAY=$((NOW/86400))
pages() { python3 -c "
import sys; r=set()
for a in sys.argv[1:]:
    x,y=(a.split('-')+[a])[:2]; r.update(range(int(x),int(y)+1))
print(''.join('1' if i in r else '0' for i in range(1,605)))" "$@"; }
seed() {  # seed START_PAGE "pages..."
  local SP=$1; shift; local B=$(pages "$@")
  cat > /tmp/k.xml <<X
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
<boolean name="active" value="true" />
<string name="mode">pages</string>
<int name="ppd" value="10" />
<boolean name="extend" value="false" />
<int name="start_page" value="$SP" />
<int name="off_days" value="0" />
<long name="start" value="$DAY" />
<long name="end" value="$((DAY+60))" />
<long name="base_day" value="$DAY" />
<int name="base_read" value="0" />
<string name="label">test</string>
<string name="pages">$B</string>
</map>
X
  cat > /tmp/s.xml <<X
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
<boolean name="welcomed" value="true" />
<int name="tour_seen" value="99" />
</map>
X
  adb shell am force-stop $P
  adb push /tmp/k.xml /data/local/tmp/k.xml; adb push /tmp/s.xml /data/local/tmp/s.xml
  adb shell "run-as $P sh -c 'mkdir -p shared_prefs; cp /data/local/tmp/k.xml shared_prefs/khatma.xml; [ -f shared_prefs/settings.xml ] || cp /data/local/tmp/s.xml shared_prefs/settings.xml'"
  adb shell "run-as $P sh -c 'sed -i \"s#</map>#<boolean name=\\\"welcomed\\\" value=\\\"true\\\" />\\n</map>#\" shared_prefs/settings.xml'" || true
}
dump() {  # dump NAME
  adb shell "run-as $P cat shared_prefs/khatma.xml" > shots/$1.txt
  python3 - shots/$1.txt <<'PY' | tee -a shots/summary.txt
import re,sys
s=open(sys.argv[1],encoding='utf-8').read()
g=lambda k:(re.search(r'name="%s"[^>]*value="([^"]*)"'%k,s) or [None,None])[1]
b=(re.search(r'name="pages">([01]*)<',s) or [None,''])[1]
print(sys.argv[1].split('/')[-1], 'from',g('today_from'),'to',g('today_to'),'target',g('today_target'),'count',g('today_count'),
      'read',b.count('1'),'p1',b[:1],'p2',b[1:2],'p604',b[603:604])
PY
}
home() { adb shell am start -n $P/.HomeActivity >/dev/null; sleep 7; adb exec-out screencap -p > shots/$1.png; }

# ١) الورد يتخطى الصفحات المقروءة سابقًا (٣–٦): المتوقع من ١ إلى ١٤ والهدف ١٠
seed 1 3-6; home t1-home; dump t1
adb shell am start -n $P/.KhatmaActivity >/dev/null; sleep 4; adb exec-out screencap -p > shots/t1-khatma.png

# ٢) حساب الصفحة بالبقاء عليها في وضع القراءة: افتح صفحة ١ وانتظر ١٦ ثانية
adb shell am start -n $P/.MainActivity -a android.intent.action.VIEW -d "https://7awlalaalam.com/__hawl/mushaf-pages-offline.html?page=1" >/dev/null
sleep 18; adb exec-out screencap -p > shots/t2-page1.png; dump t2-after-page1
adb shell input swipe 200 1300 950 1300 300; sleep 17; adb exec-out screencap -p > shots/t2-swipe.png; dump t2-after-swipe-a
adb shell input swipe 950 1300 200 1300 300; sleep 17; dump t2-after-swipe-b
home t2-home; dump t2-home

# ٣) ٩٩٪ قبل الختم (٦٠٣ صفحة مقروءة)
seed 1 1-603; home t3-home; dump t3

# ٤) ختمة تبدأ من صفحة ٥٩٨: الورد يلتف ٥٩٨ ← ٣
seed 598; home t4-home; dump t4

adb logcat -d | grep -E "FATAL|AndroidRuntime" -A20 > shots/fatal.txt || true
cat shots/summary.txt
ls -la shots
