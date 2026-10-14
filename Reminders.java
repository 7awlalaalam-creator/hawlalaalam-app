package com.hawlalaalam.quran;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import java.util.Calendar;

/** جدولة التذكيرات اليومية */
final class Reminders {
    static final String VERSE = "verse";
    static final String WIRD = "wird";
    static final String AZKAR_AM = "azkar_am";
    static final String AZKAR_PM = "azkar_pm";
    static final String KAHF = "kahf";
    static final String[] ALL = {VERSE, WIRD, AZKAR_AM, AZKAR_PM, KAHF};
    static final String ACTION_PREFIX = "com.hawlalaalam.quran.REMIND_";
    /** تذكير الورد الثاني (ليس ضمن ALL: لا يظهر في الإعدادات ولا يُجدول يوميًا) */
    static final String WIRD_FOLLOW = "wird_follow";
    /** زر «ذكّرني بعد ساعة» في إشعار الورد */
    static final String WIRD_SNOOZE = "wird_snooze";

    private Reminders() { }

    static boolean enabled(Context c, String kind) {
        return App.prefs(c).getBoolean(kind + "_on", false);
    }

    static int hour(Context c, String kind) {
        int def;
        switch (kind) {
            case VERSE: def = 7; break;
            case AZKAR_AM: def = 6; break;
            case AZKAR_PM: def = 17; break;
            case KAHF: def = 9; break;
            default: def = 21;
        }
        return App.prefs(c).getInt(kind + "_h", def);
    }

    static int minute(Context c, String kind) {
        return App.prefs(c).getInt(kind + "_m", AZKAR_AM.equals(kind) ? 30 : 0);
    }

    static void set(Context c, String kind, boolean on, int h, int m) {
        App.prefs(c).edit().putBoolean(kind + "_on", on).putInt(kind + "_h", h).putInt(kind + "_m", m).apply();
        schedule(c, kind);
    }

    private static PendingIntent pending(Context c, String kind) {
        Intent i = new Intent(c, ReminderReceiver.class).setAction(ACTION_PREFIX + kind);
        int req = 201;   // ثابتة: 201..205 (تحافظ على تذكيرات الإصدارات السابقة)
        for (int k = 0; k < ALL.length; k++) if (ALL[k].equals(kind)) req = 201 + k;
        return PendingIntent.getBroadcast(c, req, i,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    static void schedule(Context c, String kind) {
        AlarmManager am = c.getSystemService(AlarmManager.class);
        PendingIntent pi = pending(c, kind);
        if (!enabled(c, kind)) {
            am.cancel(pi);
            return;
        }
        Calendar next = Calendar.getInstance();
        next.set(Calendar.HOUR_OF_DAY, hour(c, kind));
        next.set(Calendar.MINUTE, minute(c, kind));
        next.set(Calendar.SECOND, 0);
        next.set(Calendar.MILLISECOND, 0);
        if (byPrayer(c, kind)) {                       // بعد الفجر/العصر بربع ساعة حسب المدينة
            long when = prayerBased(c, kind);
            next.setTimeInMillis(when);
        } else if (KAHF.equals(kind)) {                    // أسبوعي: يوم الجمعة
            while (next.get(Calendar.DAY_OF_WEEK) != Calendar.FRIDAY
                    || next.getTimeInMillis() <= System.currentTimeMillis() + 30_000) {
                next.add(Calendar.DAY_OF_MONTH, 1);
            }
        } else if (next.getTimeInMillis() <= System.currentTimeMillis() + 30_000) {
            next.add(Calendar.DAY_OF_MONTH, 1);
        }
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.getTimeInMillis(), pi);
    }

    /** أذكار الصباح والمساء مرتبطة بالصلاة (افتراضيًا عند توفر الموقع)، والورد إن اختار القارئ صلاة */
    static boolean byPrayer(Context c, String kind) {
        if (WIRD.equals(kind)) return wirdPrayer(c) >= 0 && Adhan.hasLocation(c);
        return (AZKAR_AM.equals(kind) || AZKAR_PM.equals(kind))
                && App.prefs(c).getBoolean("azkar_by_prayer", true) && Adhan.hasLocation(c);
    }

    /** الصلاة التي يأتي بعدها تذكير الورد (PrayerCalc)، أو -١ لوقت ثابت */
    static int wirdPrayer(Context c) { return App.prefs(c).getInt("wird_prayer", -1); }

    static void setWirdPrayer(Context c, int prayer) {
        App.prefs(c).edit().putInt("wird_prayer", prayer).putBoolean(WIRD + "_on", true).apply();
        schedule(c, WIRD);
    }

    /** وصف وقت تذكير الورد: «بعد العشاء» أو «٩:٠٠ م» */
    static String wirdLabel(Context c) {
        if (byPrayer(c, WIRD)) return "بعد " + Adhan.NAMES[wirdPrayer(c)];
        return Adhan.arabic(App.formatTime(hour(c, WIRD), minute(c, WIRD)));
    }

    private static long prayerBased(Context c, String kind) {
        int prayer = WIRD.equals(kind) ? wirdPrayer(c) : AZKAR_AM.equals(kind) ? PrayerCalc.FAJR : PrayerCalc.ASR;
        long after = (WIRD.equals(kind) ? 20 : 15) * 60_000L;
        Calendar day = Calendar.getInstance();
        long t = Adhan.times(c, day)[prayer] + after;
        if (t <= System.currentTimeMillis() + 30_000) {
            day.add(Calendar.DAY_OF_MONTH, 1);
            t = Adhan.times(c, day)[prayer] + after;
        }
        return t;
    }

    // ------------------------------------------------------------------ التذكير الثاني للورد

    static boolean followUpOn(Context c) { return App.prefs(c).getBoolean("wird_follow", true); }

    static void setFollowUp(Context c, boolean on) {
        App.prefs(c).edit().putBoolean("wird_follow", on).apply();
        if (!on) c.getSystemService(AlarmManager.class).cancel(followUpPending(c));
    }

    private static PendingIntent followUpPending(Context c) {
        Intent i = new Intent(c, ReminderReceiver.class).setAction(ACTION_PREFIX + WIRD_FOLLOW);
        return PendingIntent.getBroadcast(c, 206, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    /** تذكير ثانٍ لطيف بعد ٣ ساعات إن لم يكتمل الورد، ولا يتجاوز ١١ مساءً */
    static void scheduleFollowUp(Context c) {
        if (!followUpOn(c) || !Khatma.active(c) || Khatma.done(c) || Khatma.todayRemaining(c) == 0) return;
        Calendar at = Calendar.getInstance();
        at.add(Calendar.HOUR_OF_DAY, 3);
        Calendar limit = Calendar.getInstance();
        limit.set(Calendar.HOUR_OF_DAY, 23);
        limit.set(Calendar.MINUTE, 0);
        if (at.after(limit) || at.get(Calendar.DAY_OF_YEAR) != limit.get(Calendar.DAY_OF_YEAR)) return;
        c.getSystemService(AlarmManager.class)
                .setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.getTimeInMillis(), followUpPending(c));
    }

    /**
     * «ذكّرني بعد ساعة»: نفس منبّه التذكير الثاني (requestCode 206) بعد ساعة.
     * طلبه القارئ بنفسه، فلا يتقيّد بحد الساعة ١١ مساءً، ويحل محل أي تذكير ثانٍ مجدول.
     */
    static void snoozeWird(Context c) {
        if (!Khatma.active(c) || Khatma.done(c) || Khatma.todayRemaining(c) == 0) return;
        c.getSystemService(AlarmManager.class).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + 60 * 60_000L, followUpPending(c));
    }

    static void scheduleAll(Context c) {
        Announce.schedule(c);                         // إشعارات صاحب التطبيق
        for (String k : ALL) schedule(c, k);
    }

    static boolean askedBefore(Context c) {
        SharedPreferences p = App.prefs(c);
        return p.getBoolean("reminders_asked", false);
    }

    static void markAsked(Context c) {
        App.prefs(c).edit().putBoolean("reminders_asked", true).apply();
    }
}
