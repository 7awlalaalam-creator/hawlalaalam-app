package com.hawlalaalam.quran;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.drawable.Icon;
import android.os.Build;

/**
 * الإشعارات بتصميم موحّد:
 * عنوان قصير بلا رموز تعبيرية، ونوع الإشعار في سطر التطبيق (الأذان، الختمة، آية اليوم…)،
 * وصورة جاهزة للمشاركة لآية اليوم، وشريط تقدّم للورد، وزر «ذكّرني بعد ساعة».
 * أرقام الإشعارات (notify id) وأكواد الطلبات كما هي في الإصدارات السابقة.
 */
final class Notifier {
    static final String CH_VERSE = "verse";
    static final String CH_WIRD = "wird";
    static final String CH_ADHAN = "adhan";
    static final String CH_REMIND = "reminders";

    static final int ID_WIRD = 2;

    private Notifier() { }

    static void ensureChannels(Context c) {
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CH_VERSE, "آية اليوم", NotificationManager.IMPORTANCE_DEFAULT));
        nm.createNotificationChannel(new NotificationChannel(CH_WIRD, "تذكير الورد اليومي", NotificationManager.IMPORTANCE_DEFAULT));
        nm.createNotificationChannel(new NotificationChannel(CH_ADHAN, "الأذان", NotificationManager.IMPORTANCE_HIGH));
        nm.createNotificationChannel(new NotificationChannel(CH_REMIND, "الأذكار وسورة الكهف", NotificationManager.IMPORTANCE_DEFAULT));
    }

    static boolean allowed(Context c) {
        return Build.VERSION.SDK_INT < 33
                || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    private static PendingIntent open(Context c, String url, int req) {
        return PendingIntent.getActivity(c, req, App.openInApp(c, url),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    /** فتح شاشة «اليوم» حيث بطاقة الآية بأزرار المشاركة والتفسير */
    private static PendingIntent openToday(Context c, int req) {
        Intent i = new Intent(c, HomeActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        return PendingIntent.getActivity(c, req, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    /** مشاركة نص عبر نافذة المشاركة في الجوال (واتساب وغيره) */
    static PendingIntent shareTextPI(Context c, String text, String title, int req) {
        Intent send = new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text);
        Intent chooser = Intent.createChooser(send, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return PendingIntent.getActivity(c, req, chooser, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    static String verseShareText(VerseRepo.Verse v) {
        return "﴿ " + v.text + " ﴾\n" + v.ref() + "\n\nالتفسير: " + v.tafsirUrl();
    }

    /** kind يظهر بجانب اسم التطبيق في رأس الإشعار: «حول العالم · الأذان» */
    private static Notification.Builder base(Context c, String ch, String kind) {
        Notification.Builder b = new Notification.Builder(c, ch)
                .setSmallIcon(R.drawable.ic_stat_quran)
                .setColor(c.getColor(R.color.gold_deep))
                .setAutoCancel(true);
        if (kind != null) b.setSubText(kind);
        return b;
    }

    private static Notification.Action action(Context c, String label, PendingIntent pi) {
        return new Notification.Action.Builder(Icon.createWithResource(c, R.drawable.ic_stat_quran), label, pi).build();
    }

    private static String num(int n) { return Adhan.arabic(String.valueOf(n)); }

    /** «صفحة واحدة»، «صفحتان»، «٣ صفحات»، «١٥ صفحة» */
    static String pages(int n) {
        if (n == 1) return "صفحة واحدة";
        if (n == 2) return "صفحتان";
        return num(n) + (n >= 3 && n <= 10 ? " صفحات" : " صفحة");
    }

    // ------------------------------------------------------------------ آية اليوم

    static void verse(Context c, VerseRepo.Verse v) {
        if (!allowed(c)) return;
        ensureChannels(c);
        Notification.Builder b = base(c, CH_VERSE, "آية اليوم").setContentTitle("آية اليوم");
        if (v != null && v.text != null && !v.text.isEmpty()) {
            b.setContentText(v.text + " · " + v.ref())
             .setContentIntent(openToday(c, 101))
             .addAction(action(c, "شارك كصورة", open(c, v.cardUrl(), 102)))
             .addAction(action(c, "شارك نصًّا", shareTextPI(c, verseShareText(v), "شارك آية اليوم", 129)))
             .addAction(action(c, "التفسير", open(c, v.tafsirUrl(), 103)));
            Bitmap card = verseImage(c, v);
            if (card != null) {
                // الآية بخط المجمع على بطاقة بهوية التطبيق، تظهر عند فتح الإشعار
                b.setStyle(new Notification.BigPictureStyle().bigPicture(card).setSummaryText(v.ref()));
            } else {
                b.setStyle(new Notification.BigTextStyle().bigText("﴿ " + v.text + " ﴾\n" + v.ref()));
            }
        } else {
            b.setContentText("آية اليوم بانتظارك، افتح وتدبّر")
             .setContentIntent(openToday(c, 104));
        }
        c.getSystemService(NotificationManager.class).notify(1, b.build());
    }

    /**
     * بطاقة الآية للإشعار: خلفية الهوية بزخرفة، إطار ذهبي، نص المجمع بخطه، والمرجع.
     * حجم صغير (٧٢٠×٣٦٠، RGB_565) حتى لا يتجاوز حد حجم الإشعار؛ أي خطأ ← null (يعود الإشعار نصيًّا).
     */
    static Bitmap verseImage(Context c, VerseRepo.Verse v) {
        try {
            final int w = 720, h = 360;
            float k = w / 360f;                                   // كأنها شاشة بعرض ٣٦٠dp
            Bitmap b = Bitmap.createBitmap(w, h, Bitmap.Config.RGB_565);
            Canvas cv = new Canvas(b);
            Ui.PatternDrawable bg = new Ui.PatternDrawable(c, 0xFF123640, 0);
            bg.setBounds(0, 0, w, h);
            bg.draw(cv);
            Paint frame = new Paint(Paint.ANTI_ALIAS_FLAG);
            frame.setStyle(Paint.Style.STROKE);
            frame.setStrokeWidth(1.5f * k);
            frame.setColor(0x99C9A876);
            float in = 10 * k;
            cv.drawRoundRect(new RectF(in, in, w - in, h - in), 10 * k, 10 * k, frame);

            int tw = Math.round(w - 44 * k), th = Math.round(h - 74 * k);
            Bitmap text = VerseWidget.draw(c, QuranText.withNumber(v.text, v.ayah), QuranText.font(c),
                    tw, th, k, 24f, 1.3f);
            Paint tint = new Paint(Paint.FILTER_BITMAP_FLAG);
            tint.setColorFilter(new android.graphics.PorterDuffColorFilter(0xFFF5EBD3, android.graphics.PorterDuff.Mode.SRC_IN));
            cv.drawBitmap(text, (w - tw) / 2f, 22 * k, tint);
            text.recycle();

            Paint ref = new Paint(Paint.ANTI_ALIAS_FLAG);
            ref.setColor(0xFFE9D9B8);
            ref.setTextSize(11 * k);
            ref.setTypeface(Ui.font(c, 500));
            ref.setTextAlign(Paint.Align.CENTER);
            cv.drawText(v.ref() + " · حول العالم", w / 2f, h - 24 * k, ref);
            return b;
        } catch (Throwable e) {
            return null;
        }
    }

    // ------------------------------------------------------------------ الورد

    static void wird(Context c) { wird(c, false); }

    /** تذكير الورد؛ followUp = التذكير الثاني اللطيف (أو «ذكّرني بعد ساعة») إن لم يكتمل الورد */
    static void wird(Context c, boolean followUp) {
        if (!allowed(c)) return;
        ensureChannels(c);
        Notification.Builder b = base(c, CH_WIRD, "الختمة");
        if (Khatma.active(c) && !Khatma.done(c)) {
            int left = Khatma.todayRemaining(c);
            if (left == 0) return;                       // أتمّ ورده أو يوم راحة: لا داعي للتذكير
            int target = Math.max(left, Khatma.dailyTarget(c));
            int[] r = Khatma.todayRange(c);
            int open = Math.max(r[0], Khatma.nextPage(c));
            String surah = Khatma.surahName(open);
            String title = followUp ? "تذكير لطيف بوردك"
                    : "وردك اليوم" + (surah.isEmpty() ? "" : ": سورة " + surah);
            String text;
            if (followUp) text = "بقي " + pages(left) + " من وردك، ولو قليلًا قبل النوم";
            else if (left < target) text = "بقي لك " + pages(left) + " من " + pages(target);
            else text = "صفحة " + num(r[0]) + " إلى " + num(r[1]) + " · " + pages(target);
            b.setContentTitle(title)
             .setContentText(text)
             .setProgress(target, target - left, false)
             .setStyle(new Notification.BigTextStyle().bigText(text + "\n" + Khatma.where(open)
                     + " · الختم المتوقع " + Khatma.endDateText(c)))
             .setContentIntent(open(c, Khatma.pageUrl(open), 105))
             .addAction(action(c, "أكمل من صفحة " + num(open), open(c, Khatma.pageUrl(open), 106)))
             .addAction(action(c, "ذكّرني بعد ساعة", snoozePI(c)));
        } else {
            if (followUp) return;
            b.setContentTitle("وردك اليومي")
             .setContentText("قليلٌ دائم، وأثرٌ في القلب. أكمل من حيث توقفت")
             .setContentIntent(open(c, App.HOME, 105))
             .addAction(action(c, "افتح المصحف", open(c, App.mushaf(c), 106)));
        }
        c.getSystemService(NotificationManager.class).notify(ID_WIRD, b.build());
    }

    /** زر «ذكّرني بعد ساعة»: يُخفي الإشعار ويعيد التذكير بعد ساعة (ReminderReceiver) */
    private static PendingIntent snoozePI(Context c) {
        Intent i = new Intent(c, ReminderReceiver.class).setAction(Reminders.ACTION_PREFIX + Reminders.WIRD_SNOOZE);
        return PendingIntent.getBroadcast(c, 212, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    // ------------------------------------------------------------------ الأذان

    /** عند أذان المغرب في رمضان */
    static void iftar(Context c) {
        if (!allowed(c)) return;
        ensureChannels(c);
        Notification n = base(c, CH_ADHAN, "رمضان")
                .setContentTitle("حان وقت الإفطار")
                .setContentText("ذهب الظمأ وابتلّت العروق وثبت الأجر إن شاء الله")
                .setStyle(new Notification.BigTextStyle().bigText(
                        "«ذَهَبَ الظَّمَأُ، وَابْتَلَّتِ الْعُرُوقُ، وَثَبَتَ الأَجْرُ إِنْ شَاءَ اللَّهُ»\nتقبّل الله صيامكم"))
                .setContentIntent(open(c, Ramadan.tadabburUrl(), 108))
                .build();
        c.getSystemService(NotificationManager.class).notify(8, n);
    }

    /** زر «شارك الأجر»: نشر الفضل مع رابط الموقع (الدال على الخير كفاعله) */
    private static PendingIntent shareFadl(Context c, String[] f, int req) {
        String text = f[0] + "\n— " + f[1] + "\n\n" + App.HOME;
        Intent send = new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text);
        Intent chooser = Intent.createChooser(send, "شارك الأجر").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return PendingIntent.getActivity(c, req, chooser,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    /** ترتيب الصلاة بين الخمس (١..٥) لشريط «موقعك من صلوات اليوم»، أو ٠ للشروق */
    private static int prayerOrder(int index) {
        switch (index) {
            case PrayerCalc.FAJR: return 1;
            case PrayerCalc.DHUHR: return 2;
            case PrayerCalc.ASR: return 3;
            case PrayerCalc.MAGHRIB: return 4;
            case PrayerCalc.ISHA: return 5;
            default: return 0;
        }
    }

    static void adhan(Context c, int index) {
        if (!allowed(c)) return;
        ensureChannels(c);
        java.util.Calendar now = java.util.Calendar.getInstance();
        boolean friday = now.get(java.util.Calendar.DAY_OF_WEEK) == java.util.Calendar.FRIDAY;
        String name = (friday && index == PrayerCalc.DHUHR) ? "الجمعة" : Adhan.NAMES[index];
        String city = Adhan.city(c);
        String[] f = Fadl.of(index, now);
        String[] nx = Adhan.after(c, index);
        String nextText = nx == null ? "" : "التالية: " + nx[0] + " " + nx[1];
        int late = Adhan.lastLate(c);
        boolean fixable = !Adhan.canExact(c) || !Adhan.batteryFree(c);
        String big = "حان الآن موعد صلاة " + name
                + (nextText.isEmpty() ? "" : " · " + nextText)
                + "\n\n" + f[0] + "\n— " + f[1]
                + (city.isEmpty() ? "" : "\n\nحسب التوقيت المحلي لـ" + city)
                + (late >= 3 && fixable ? "\n\nوصل هذا التنبيه متأخرًا " + num(late)
                        + " دقائق. اضغط «ضبط الدقة» لإصلاحه." : "");
        Notification.Builder nb = base(c, CH_ADHAN, "الأذان")
                .setContentTitle("صلاة " + name)
                .setContentText("حان الآن" + (nextText.isEmpty() ? "" : " · " + nextText))
                .setStyle(new Notification.BigTextStyle().bigText(big))
                .setCategory(Notification.CATEGORY_REMINDER)
                .setContentIntent(open(c, App.HOME + "prayer-times-ar.html", 107));
        int order = prayerOrder(index);
        if (order > 0) nb.setProgress(5, order, false);   // موقعك من صلوات اليوم الخمس
        nb.addAction(action(c, "أذكار بعد الصلاة", PendingIntent.getActivity(c, 131, PrayerAzkarActivity.intent(c),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)));
        nb.addAction(action(c, "شارك الأجر", shareFadl(c, f, 120 + index)));
        if (late >= 3 && fixable) {
            nb.addAction(action(c, "ضبط الدقة",
                    PendingIntent.getActivity(c, 130, new Intent(c, SettingsActivity.class)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP),
                            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)));
        }
        c.getSystemService(NotificationManager.class).notify(4, nb.build());
    }

    /** الشروق: انتهاء وقت الفجر، وفضل الجلوس للذكر وصلاة الضحى */
    static void sunrise(Context c) {
        if (!allowed(c)) return;
        ensureChannels(c);
        String[] f = Fadl.of(PrayerCalc.SUNRISE, java.util.Calendar.getInstance());
        String duha = Adhan.clock(System.currentTimeMillis() + 15 * 60_000L);
        String[] nx = Adhan.after(c, PrayerCalc.SUNRISE);
        String big = f[0] + "\n— " + f[1]
                + "\n\nيبدأ وقت الضحى بعد ارتفاع الشمس، نحو " + duha
                + (nx == null ? "" : "\nالتالية: " + nx[0] + " " + nx[1]);
        Notification n = base(c, CH_ADHAN, "الأذان")
                .setContentTitle("الشروق · انتهى وقت الفجر")
                .setContentText("أذكار الصباح بانتظارك، ووقت الضحى بعد ارتفاع الشمس")
                .setStyle(new Notification.BigTextStyle().bigText(big))
                .setCategory(Notification.CATEGORY_REMINDER)
                .setContentIntent(open(c, App.HOME + "azkar-morning-evening-ar.html", 109))
                .addAction(action(c, "أذكار الصباح", open(c, App.HOME + "azkar-morning-evening-ar.html", 119)))
                .addAction(action(c, "شارك الأجر", shareFadl(c, f, 126)))
                .build();
        c.getSystemService(NotificationManager.class).notify(9, n);
    }

    /** ليلة يوم الصيام المسنون (عند العشاء) */
    static void fasting(Context c, String[] fast) {
        if (!allowed(c) || fast == null) return;
        ensureChannels(c);
        String big = "غدًا " + fast[0] + "، ولا تنسَ نية الصيام والسحور فإن فيه بركة.\n\n"
                + fast[1] + "\n— " + fast[2] + "\n\n(حسب تقويم أم القرى)";
        Notification n = base(c, CH_REMIND, "الصيام")
                .setContentTitle("غدًا " + fast[0])
                .setContentText(fast[1])
                .setStyle(new Notification.BigTextStyle().bigText(big))
                .setContentIntent(open(c, App.HOME, 127))
                .addAction(action(c, "ذكّر من تحب",
                        shareFadl(c, new String[]{"غدًا " + fast[0] + "\n" + fast[1], fast[2]}, 128)))
                .build();
        c.getSystemService(NotificationManager.class).notify(10, n);
    }

    /** أذكار الصباح والمساء وسورة الكهف */
    static void reminder(Context c, String kind) {
        if (!allowed(c)) return;
        ensureChannels(c);
        String title, text, url, label;
        int id;
        switch (kind) {
            case Reminders.AZKAR_AM:
                title = "أذكار الصباح"; text = "حصّن يومك بذكر الله"; label = "الأذكار";
                url = App.HOME + "azkar-morning-evening-ar.html"; id = 5; break;
            case Reminders.AZKAR_PM:
                title = "أذكار المساء"; text = "اختم نهارك بذكر الله"; label = "الأذكار";
                url = App.HOME + "azkar-morning-evening-ar.html"; id = 6; break;
            default:
                title = "سورة الكهف"; text = "يوم الجمعة: نورٌ لك ما بين الجمعتين"; label = "الجمعة";
                url = App.HOME + "surah-18.html"; id = 7;
        }
        Notification n = base(c, CH_REMIND, label)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(open(c, url, 110 + id))
                .addAction(action(c, "ابدأ الآن", open(c, url, 140 + id)))
                .build();
        c.getSystemService(NotificationManager.class).notify(id, n);
    }
}
