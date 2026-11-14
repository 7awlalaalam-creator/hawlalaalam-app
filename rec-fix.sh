#!/bin/bash
# إعادة تسجيل «معنى الكلمة» و«مساجد قريبة» للمقطع الترويجي (فيديو فقط، لا يغيّر التطبيق)
source <(sed -n '1,/^# ١)/p' rec-promo.sh)
# معنى الكلمة (الغريب): ضغط مطوّل على كلمة في الصفحة ٢
goTools
tapText "المصحف" exact; sleep 3; tapText "افتح المصحف"; sleep 9
python3 cdp.py "location.href=location.pathname+'?page=2'" ; sleep 7; cap w0
read WX WY < <(wvTop); echo "WV $WX $WY" >> shots/taps.txt
DPR=$(python3 cdp.py "devicePixelRatio" | tr -d '"')
pos() { python3 cdp.py "(function(){var e=document.querySelector('$1'); if(!e) return ''; var r=e.getClientRects()[0]||e.getBoundingClientRect(); return Math.round((r.left+r.width/2)*$DPR+$WX)+' '+Math.round((r.top+r.height/2)*$DPR+$WY);})()" | tr -d '"'; }
python3 cdp.py "JSON.stringify([...document.querySelectorAll('.w.gh')].slice(0,8).map(e=>e.textContent))" > shots/w-info.txt
XY=$(python3 cdp.py "(function(){var L=[...document.querySelectorAll('.w.gh')]; var e=L.find(x=>x.getBoundingClientRect().top>innerHeight*0.35)||L[3]; if(!e) return ''; var r=e.getClientRects()[0]; return Math.round((r.left+r.width/2)*$DPR+$WX)+' '+Math.round((r.top+r.height/2)*$DPR+$WY);})()" | tr -d '\"'); echo "WORD $XY" >> shots/taps.txt
recStart p-word
sleep 1
[ -n "$XY" ] && { echo "LONG p-word $(date +%s.%N) $XY" >> shots/taps.txt; adb shell input swipe $XY $XY 650; }
sleep 1.5; cap w1; sleep 3
recStop p-word
# مساجد قريبة: انتظار أطول + سجل
adb logcat -c
adb emu geo fix 39.1925 21.4858
goTools
findTool "مساجد قريبة"
recStart p-mosque
tapText "مساجد قريبة" exact; sleep 20; cap s1
python3 cdp.py "JSON.stringify({u:location.href, t:document.body.innerText.slice(0,300), c:document.querySelectorAll('canvas').length, i:document.querySelectorAll('img').length, gl:!!document.createElement('canvas').getContext('webgl')})" > shots/s-dom.txt
sleep 15; cap s1b
adb shell input swipe 540 1600 540 1100 900; sleep 5; cap s2
recStop p-mosque
adb logcat -d | grep -iE "console|webgl|maplibre|leaflet|MosqJS|Mosque|location|GL_|error" | grep -v AppsFilter | tail -120 > shots/s-log.txt
ls -la shots
