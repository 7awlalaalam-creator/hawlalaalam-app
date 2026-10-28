#!/bin/bash
# لقطات تطبيق الساعة على المحاكي: نزرع موقع جدة واللغة العربية (نسخة المعاينة قابلة للتصحيح فيعمل run-as)
set -x
mkdir -p wshots
P=com.hawlalaalam.quran
W=$P.wear
APK=$(ls wear/build/outputs/apk/debug/*.apk | head -1)
adb install -r -g "$APK" > wshots/install.txt 2>&1
adb root; sleep 2
adb shell setprop persist.sys.timezone Asia/Riyadh
adb shell cmd alarm set-timezone Asia/Riyadh
adb shell service call alarm 3 s16 Asia/Riyadh
adb shell settings put system time_12_24 12
D="$(TZ=Asia/Riyadh date +%Y)-$(TZ=Asia/Riyadh date +%-j)"
cat > /tmp/w.xml <<X
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <float name="lat" value="21.5433" />
    <float name="lng" value="39.1728" />
    <string name="city">جدة</string>
    <string name="country">SA</string>
    <string name="lang">ar</string>
    <int name="streak" value="7" />
    <int name="tb_n" value="22" />
    <string name="tb_day">$D</string>
</map>
X
adb push /tmp/w.xml /data/local/tmp/w.xml
adb shell am start -W -n $P/$W.MainActivity; sleep 8; adb exec-out screencap -p > wshots/00-first.png; adb shell am force-stop $P
adb shell "run-as $P mkdir -p shared_prefs"
adb shell "run-as $P cp /data/local/tmp/w.xml shared_prefs/w.xml"
adb shell "run-as $P cat shared_prefs/w.xml" > wshots/prefs.txt 2>&1
adb shell date >> wshots/prefs.txt
shot() {   # $1 الشاشة، $2 الاسم، $3 إضافات
  adb shell am force-stop $P
  adb shell am start -W -n $P/$W.$1 $3
  sleep 6
  adb exec-out screencap -p > wshots/$2.png
  echo "=== $2" >> wshots/am.txt
  adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity|ResumedActivity" | head -3 >> wshots/am.txt
}
shot MainActivity 01-main
adb shell input swipe 225 380 225 80 400; sleep 2; adb exec-out screencap -p > wshots/02-main-menu.png
adb shell input swipe 225 380 225 80 400; sleep 2; adb exec-out screencap -p > wshots/02b-main-menu.png
shot TimesActivity 03-times
shot TasbeehActivity 04-tasbeeh
shot VerseActivity 05-verse
shot AzkarActivity 06-azkar-menu
shot AzkarActivity 07-azkar "--es section morning"
shot AzkarActivity 07c-azkar-sleep "--es section sleep"
shot SettingsActivity 08-settings
# بطاقة Tile (أداة التصحيح في Wear OS 4)
adb shell input keyevent KEYCODE_HOME; sleep 1
adb shell am broadcast -a com.google.android.wearable.app.DEBUG_SURFACE --es operation add-tile --ecn component $P/$W.NextPrayerTile > wshots/tile.txt 2>&1
adb shell am broadcast -a com.google.android.wearable.app.DEBUG_SYSUI --es operation show-tile --ei index 0 >> wshots/tile.txt 2>&1
sleep 6; adb exec-out screencap -p > wshots/09-tile.png
adb logcat -d -b crash > wshots/crash.txt 2>&1
adb logcat -d -s ActivityManager:* ActivityTaskManager:* AndroidRuntime:* WindowManager:W System.err:* > wshots/am-log.txt 2>&1
adb logcat -d | grep -iE "quran" | grep -v "DefaultMetadataPreviewProvider\|LauncherIconCache\|CacheInvalidation\|AllLauncherApps" | tail -200 > wshots/app-log.txt
adb logcat -d | grep -E "AndroidRuntime|FATAL|ANR|hawlalaalam|Exception" | grep -v DefaultMetadataPreviewProvider | head -150 > wshots/log.txt
exit 0
