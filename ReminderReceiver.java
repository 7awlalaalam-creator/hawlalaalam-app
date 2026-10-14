package com.hawlalaalam.quran;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class ReminderReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction() == null ? "" : intent.getAction();
        Context c = context.getApplicationContext();

        if (action.equals(Reminders.ACTION_PREFIX + Reminders.VERSE)) {
            PendingResult pr = goAsync();
            new Thread(() -> {
                try {
                    VerseRepo.Verse v = VerseRepo.fetchToday(c);
                    Notifier.verse(c, v);
                    VerseWidget.updateAll(c);
                } catch (Exception ignored) {
                } finally {
                    Reminders.schedule(c, Reminders.VERSE);
                    pr.finish();
                }
            }).start();
        } else if (action.equals(Reminders.ACTION_PREFIX + Reminders.WIRD)) {
            Notifier.wird(c, false);
            Reminders.schedule(c, Reminders.WIRD);
            Reminders.scheduleFollowUp(c);
        } else if (action.equals(Announce.ACTION)) {
            PendingResult pr = goAsync();
            new Thread(() -> { try { Announce.check(c); } finally { pr.finish(); } }).start();
        } else if (action.equals(Reminders.ACTION_PREFIX + Reminders.WIRD_FOLLOW)) {
            Notifier.wird(c, true);
        } else if (action.equals(Reminders.ACTION_PREFIX + Reminders.WIRD_SNOOZE)) {
            // «ذكّرني بعد ساعة»: نُخفي الإشعار الحالي ونعيده بعد ساعة
            android.app.NotificationManager nm = c.getSystemService(android.app.NotificationManager.class);
            if (nm != null) nm.cancel(Notifier.ID_WIRD);
            Reminders.snoozeWird(c);
        } else if (action.equals(Reminders.ACTION_PREFIX + Reminders.AZKAR_AM)
                || action.equals(Reminders.ACTION_PREFIX + Reminders.AZKAR_PM)
                || action.equals(Reminders.ACTION_PREFIX + Reminders.KAHF)) {
            String kind = action.substring(Reminders.ACTION_PREFIX.length());
            Notifier.reminder(c, kind);
            Reminders.schedule(c, kind);
        } else if (action.equals(Adhan.ACTION)) {
            int idx = intent.getIntExtra(Adhan.EXTRA_INDEX, PrayerCalc.DHUHR);
            Adhan.markArrival(c);
            if (idx == PrayerCalc.SUNRISE) {
                if (Adhan.enabled(c) && Adhan.sunriseOn(c)) Notifier.sunrise(c);
            } else if (Adhan.enabled(c)) {
                Notifier.adhan(c, idx);
            }
            if (idx == PrayerCalc.ISHA && Adhan.fastingOn(c)) Notifier.fasting(c, Fadl.fastTomorrow());
            if (idx == PrayerCalc.MAGHRIB && Ramadan.active() && App.prefs(c).getBoolean("iftar_on", true)) Notifier.iftar(c);
            PrayerWidget.updateAll(c);
            RamadanWidget.updateAll(c);
            KhatmaWidget.updateAll(c);
            Adhan.scheduleNext(c);
        } else if (action.equals(PrayerWidget.ACTION_TICK)) {
            // تحديث الويدجت عند تبدّل البطاقة الذكية (الضحى، الثلث الأخير، منتصف الليل…)
            PrayerWidget.updateAll(c);
            // يوم جديد: آية اليوم والتاريخ الهجري في ويدجت الآية
            if (!VerseRepo.isFresh(c)) {
                PendingResult pr = goAsync();
                new Thread(() -> {
                    try { VerseRepo.fetchToday(c); VerseWidget.updateAll(c); }
                    catch (Exception ignored) { }
                    finally { pr.finish(); }
                }).start();
            }
        } else {
            Adhan.scheduleNext(c);
            PrayerWidget.updateAll(c);
            VerseWidget.updateAll(c);
            RamadanWidget.updateAll(c);
            KhatmaWidget.updateAll(c);
            // إقلاع الجهاز، تحديث التطبيق، تغيير الوقت أو المنطقة الزمنية
            Reminders.scheduleAll(c);
        }
    }
}
