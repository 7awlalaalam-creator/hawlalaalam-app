#!/bin/bash
# تسجيل ميزة «مساجد قريبة» للمقطع الترويجي (فيديو فقط، لا يغيّر التطبيق)
source <(sed -n '1,/^# ١)/p' rec-promo.sh)
goTools
findTool "مساجد قريبة"
recStart p-mosque
tapText "مساجد قريبة" exact; sleep 12; cap s1
adb shell input swipe 540 1600 540 1100 900; sleep 4; cap s2
recStop p-mosque
ls -la shots
