#!/bin/bash
# تسجيل مقاطع فيديو حقيقية لمميزات التطبيق (للمقطع الترويجي فقط، لا يُنشر شيء للمستخدمين)
# المخرجات في shots/: p-hadith.mp4 p-mood.mp4 p-adhan.mp4 p-ask.mp4 p-word.mp4 + لقطات وسجلات للمراجعة
set -x
P=com.hawlalaalam.quran
pip install -q websocket-client || pip3 install -q websocket-client || true
adb install -r -g $(ls app/build/outputs/apk/debug/*.apk | head -1)
mkdir -p shots
adb shell settings put system time_12_24 12
adb shell pm grant $P android.permission.POST_NOTIFICATIONS || true
adb shell pm grant $P android.permission.ACCESS_FINE_LOCATION || true
adb shell pm grant $P android.permission.ACCESS_COARSE_LOCATION || true
adb emu geo fix 39.1925 21.4858
# شريط حالة نظيف
adb shell settings put global sysui_demo_allowed 1
demo() { adb shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }
demo enter; demo clock -e hhmm 0900; demo battery -e level 100 -e plugged false
demo network -e wifi show -e level 4; demo network -e mobile show -e datatype none -e level 4; demo notifications -e visible false

adb shell monkey -p $P -c android.intent.category.LAUNCHER 1; sleep 8; adb shell am force-stop $P
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

dump() { adb shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1; adb pull /sdcard/u.xml /tmp/u.xml >/dev/null 2>&1; }
# tapText "نص" [exact]: يضغط أول عنصر نصه مطابق تمامًا، وإلا أول عنصر يحتويه
tapText() {
  dump
  B=$(python3 - "$1" "$2" <<'PY'
import sys,re
s=open('/tmp/u.xml',encoding='utf-8').read(); q=sys.argv[1]; exact=len(sys.argv)>2 and sys.argv[2]=='exact'
nodes=[m.group(0) for m in re.finditer(r'<node [^>]*>',s)]
def ctr(n):
    b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
    if b:
        x1,y1,x2,y2=map(int,b.groups())
        if x2>x1 and y2>y1: return (x1+x2)//2,(y1+y2)//2
hit=None
for n in nodes:
    if ('text="%s"'%q) in n or ('content-desc="%s"'%q) in n:
        hit=ctr(n)
        if hit: break
if not hit and not exact:
    for n in nodes:
        if q in n:
            hit=ctr(n)
            if hit: break
if hit: print(*hit)
PY
)
  echo "tap $1 -> $B" | tee -a shots/taps.txt
  [ -n "$B" ] && { echo "TAP $CUR $(date +%s.%N) $B" >> shots/taps.txt; adb shell input tap $B; }
}
wvTop() { dump; python3 - <<'PY'
import re
s=open('/tmp/u.xml',encoding='utf-8').read()
for m in re.finditer(r'<node [^>]*class="android.webkit.WebView"[^>]*>',s):
    b=re.search(r'bounds="\[(\d+),(\d+)\]',m.group(0)); print(b.group(1),b.group(2)); break
PY
}
REC=""
# findTool "اسم": ينزل في شاشة الأدوات حتى يظهر العنصر (بدون ضغط)
findTool() { for i in 1 2 3 4 5; do dump; grep -q "text=\"$1\"" /tmp/u.xml && return 0; adb shell input swipe 540 1700 540 1100 600; sleep 1.5; done; return 1; }
recStart() { CUR=$1; echo "REC $1 $(date +%s.%N)" >> shots/taps.txt; adb shell screenrecord --bit-rate 8000000 /sdcard/$1.mp4 & REC=$!; sleep 1.5; }
recStop() { sleep 1; adb shell pkill -INT screenrecord; wait $REC; sleep 2; adb pull /sdcard/$1.mp4 shots/$1.mp4; }
cap() { adb exec-out screencap -p > shots/$1.png; }
clearAnr() { for i in 1 2 3; do dump; grep -q "responding" /tmp/u.xml || break; tapText "Wait" exact; sleep 2; done; }
goTools() {
  clearAnr
  adb shell am force-stop $P; adb shell monkey -p $P -c android.intent.category.LAUNCHER 1 >/dev/null; sleep 8
  tapText "لاحقًا" exact; tapText "Later" exact; sleep 1
  clearAnr
  tapText "الأدوات" exact; sleep 4; cap tools
}

# ١) الأحاديث الصحيحة
goTools
findTool "الأحاديث"
recStart p-hadith
tapText "الأحاديث" exact; sleep 4; cap h1
adb shell input swipe 540 1700 540 1000 900; sleep 2
tapText "كتاب بدء الوحي" exact; sleep 4; cap h2
adb shell input swipe 540 1600 540 1100 900; sleep 3
recStop p-hadith

# ٢) آية لحالك
goTools
findTool "آية لحالك"
recStart p-mood
tapText "آية لحالك" exact; sleep 4; cap m1
dump; B=$(python3 - <<'PY'
import re
s=open('/tmp/u.xml',encoding='utf-8').read()
m=re.search(r'<node [^>]*text="ضيق"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',s)
if m:
    x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2, y1-50)
PY
)
echo "TAP p-mood $(date +%s.%N) $B" >> shots/taps.txt; [ -n "$B" ] && adb shell input tap $B
sleep 4; cap m2; sleep 6; cap m3
recStop p-mood

# ٣) فحص الأذان + تجربة الأذان (الصوت يُضاف في المونتاج من ملف التطبيق نفسه)
goTools
findTool "فحص الأذان"
recStart p-adhan
tapText "فحص الأذان" exact; sleep 4; cap a1
tapText "جرّب الأذان الآن"; sleep 11; adb shell cmd statusbar expand-notifications; sleep 6; cap a2; adb shell cmd statusbar collapse; sleep 1
recStop p-adhan
adb shell input keyevent KEYCODE_BACK

# ٤) المصحف: اسأل عن الآية  ٥) معنى الكلمة (الغريب)
goTools
tapText "المصحف" exact; sleep 3; tapText "افتح المصحف"; sleep 9; cap q0
python3 cdp.py "location.href" > shots/q-url.txt
python3 cdp.py "location.href=location.pathname+'?page=252'" ; sleep 6; cap q1
read WX WY < <(wvTop); echo "WV $WX $WY" >> shots/taps.txt
DPR=$(python3 cdp.py "devicePixelRatio" | tr -d '"')
pos() {  # pos "css selector" → إحداثيات الشاشة لمنتصف العنصر
  python3 cdp.py "(function(){var e=document.querySelector('$1'); if(!e) return ''; e.scrollIntoView({block:'center'}); var r=e.getClientRects()[0]||e.getBoundingClientRect(); return Math.round((r.left+r.width/2)*$DPR+$WX)+' '+Math.round((r.top+r.height/2)*$DPR+$WY);})()" | tr -d '"'
}
python3 cdp.py "JSON.stringify({ay:document.querySelectorAll('.ay').length, gh:document.querySelectorAll('.w.gh').length, k:[...document.querySelectorAll('.ay')].slice(0,40).map(e=>e.getAttribute('data-k')).join(',')})" > shots/q-info.txt
XY=$(pos '.ay[data-k=\"13:28\"]'); [ -z "$XY" ] && XY=$(pos '.ay'); echo "AYAH $XY" >> shots/taps.txt
recStart p-ask
sleep 1
[ -n "$XY" ] && { echo "TAP p-ask $(date +%s.%N) $XY" >> shots/taps.txt; adb shell input tap $XY; }
sleep 3; cap q2
tapText "اسأل عن الآية"; sleep 3; cap q3
tapText "ما معنى الآية باختصار؟" exact; sleep 12; cap q4
adb shell input swipe 540 1700 540 1100 900; sleep 3; cap q5
recStop p-ask
adb shell input keyevent KEYCODE_BACK; sleep 2
python3 cdp.py "location.href=location.pathname+'?page=2'" ; sleep 6
python3 cdp.py "JSON.stringify([...document.querySelectorAll('.w.gh')].slice(0,12).map(e=>e.textContent))" > shots/w-info.txt
XY=$(pos '.w.gh'); echo "WORD $XY" >> shots/taps.txt
recStart p-word
sleep 1
[ -n "$XY" ] && { echo "LONG p-word $(date +%s.%N) $XY" >> shots/taps.txt; adb shell input swipe $XY $XY 900; }
sleep 4; cap w1
recStop p-word

# ٦) مساجد قريبة
goTools
findTool "مساجد قريبة"
recStart p-mosque
tapText "مساجد قريبة" exact; sleep 12; cap s1
adb shell input swipe 540 1600 540 1100 900; sleep 4; cap s2
recStop p-mosque
ls -la shots
