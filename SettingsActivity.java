package com.hawlalaalam.quran;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.TimePickerDialog;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.util.Calendar;
import java.util.HashMap;
import java.util.Map;

/** الإعدادات بتصميم هوية الموقع */
public class SettingsActivity extends Activity {

    @Override
    protected void attachBaseContext(android.content.Context base) {
        super.attachBaseContext(Ui.wrap(base));                // المظهر المختار يُطبَّق فورًا
    }
    private static final int REQ_NOTIF = 31;
    private static final int REQ_LOC = 32;
    private static final String ADHAN = "adhan";

    private Switch verseSwitch, wirdSwitch, adhanSwitch;
    private Button verseTime, wirdTime;
    private final Map<String, Switch> switches = new HashMap<>();
    private final Map<String, Button> chips = new HashMap<>();
    private TextView adhanPlace;
    private LinearLayout adhanHealth;
    private LinearLayout prayerGrid;
    private String pendingKind;
    private boolean suppress;

    private int ink, muted, gold;
    /** تفتحه «الأدوات» ← «التنبيهات»: قسما التذكيرات والأذان فقط، بعنوان «التنبيهات» */
    static final String EXTRA_NOTIF_ONLY = "notif_only";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        final boolean notifOnly = getIntent().getBooleanExtra(EXTRA_NOTIF_ONLY, false);
        ink = getColor(R.color.ink);
        muted = getColor(R.color.muted);
        gold = getColor(R.color.gold_deep);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        col.setPadding(dp(18), dp(14), dp(18), dp(36));

        // --- الرأس
        LinearLayout head = new LinearLayout(this);
        head.setGravity(Gravity.CENTER_VERTICAL);
        head.setPadding(dp(2), dp(4), dp(2), dp(6));
        ImageButton back = new ImageButton(this);
        back.setImageResource(R.drawable.ic_back);
        back.setContentDescription("رجوع");
        back.setBackground(Ui.shape(getColor(R.color.card), 22, getColor(R.color.line), this));
        back.setOnClickListener(v -> finish());
        head.addView(back, new LinearLayout.LayoutParams(dp(44), dp(44)));
        TextView title = Ui.text(this, notifOnly ? "التنبيهات" : "الإعدادات", 24, ink, 700);
        title.setPadding(dp(14), 0, dp(14), 0);
        head.addView(title, new LinearLayout.LayoutParams(0, -2, 1f));
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.app_logo_png);
        logo.setContentDescription("شعار حول العالم");
        logo.setClipToOutline(true);
        logo.setBackground(Ui.shape(0xFF0E2C31, 11, 0, this));
        head.addView(logo, new LinearLayout.LayoutParams(dp(44), dp(44)));
        col.addView(head);

        // --- التذكيرات
        col.addView(section("التذكيرات اليومية"));
        LinearLayout c1 = Ui.card(this);
        String[][] items = {
                {Reminders.VERSE, "آية اليوم", "آية كل صباح مع تفسيرها وزر مشاركتها"},
                {Reminders.WIRD, "الورد اليومي", "تذكير بقراءة وردك وإكمال ختمتك"},
                {Reminders.AZKAR_AM, "أذكار الصباح", "حصّن يومك بذكر الله"},
                {Reminders.AZKAR_PM, "أذكار المساء", "اختم نهارك بذكر الله"},
                {Reminders.KAHF, "سورة الكهف", "كل جمعة، نورٌ لك ما بين الجمعتين"},
        };
        for (int k = 0; k < items.length; k++) {
            final String kind = items[k][0];
            if (k > 0) c1.addView(Ui.divider(this));
            Switch sw = Ui.toggle(this);
            c1.addView(Ui.row(this, items[k][1], items[k][2], sw));
            Button chip = Ui.chip(this, "");
            chip.setOnClickListener(v -> {
                if (Reminders.byPrayer(this, kind) && !Reminders.WIRD.equals(kind)) {
                    Toast.makeText(this, "الوقت مرتبط بالصلاة. أطفئ «الأذكار مرتبطة بالصلاة» لتحديد وقت ثابت", Toast.LENGTH_LONG).show();
                } else pickTime(kind);
            });
            c1.addView(Ui.minH(chip, 38), chipLp());
            sw.setChecked(Reminders.enabled(this, kind));
            sw.setOnCheckedChangeListener((b, on) -> { if (!suppress) toggle(kind, on); });
            switches.put(kind, sw);
            chips.put(kind, chip);
        }
        // الأذكار مرتبطة بأوقات الصلاة
        c1.addView(Ui.divider(this));
        Switch byPrayer = Ui.toggle(this);
        byPrayer.setChecked(App.prefs(this).getBoolean("azkar_by_prayer", true));
        byPrayer.setOnCheckedChangeListener((b, on) -> {
            App.prefs(this).edit().putBoolean("azkar_by_prayer", on).apply();
            Reminders.schedule(this, Reminders.AZKAR_AM);
            Reminders.schedule(this, Reminders.AZKAR_PM);
            refreshTimes();
        });
        c1.addView(Ui.row(this, "الأذكار مرتبطة بالصلاة", "الصباح بعد الفجر بربع ساعة، والمساء بعد العصر، حسب مدينتك", byPrayer));
        // تنبيه الإفطار في رمضان
        c1.addView(Ui.divider(this));
        Switch iftar = Ui.toggle(this);
        iftar.setChecked(App.prefs(this).getBoolean("iftar_on", true));
        iftar.setOnCheckedChangeListener((b, on) -> {
            App.prefs(this).edit().putBoolean("iftar_on", on).apply();
            Adhan.scheduleNext(this);
        });
        c1.addView(Ui.row(this, "تنبيه الإفطار في رمضان", "دعاء الإفطار عند أذان المغرب، يعمل تلقائيًا في رمضان", iftar));
        // أخبار صاحب التطبيق: قناة مستقلة يتحكم بها القارئ من إعدادات الجوال
        c1.addView(Ui.divider(this));
        LinearLayout newsRow = new LinearLayout(this);
        newsRow.setGravity(Gravity.CENTER_VERTICAL);
        newsRow.setMinimumHeight(dp(56));
        LinearLayout newsTexts = new LinearLayout(this);
        newsTexts.setOrientation(LinearLayout.VERTICAL);
        newsTexts.addView(Ui.text(this, "أخبار وتنبيهات حول العالم", 16, ink, 700));
        TextView newsSub = Ui.text(this, "ما يرسله صاحب التطبيق من أخبار وتنبيهات", 13, muted, 400);
        newsSub.setPadding(0, dp(4), 0, 0);
        newsTexts.addView(newsSub);
        newsRow.addView(newsTexts, new LinearLayout.LayoutParams(0, -2, 1f));
        newsRow.addView(Ui.text(this, "تغيير ›", 13, muted, 400));
        newsRow.setPadding(0, dp(10), 0, dp(10));
        newsRow.setOnClickListener(v -> {
            try {
                android.app.NotificationManager nm = getSystemService(android.app.NotificationManager.class);
                nm.createNotificationChannel(new android.app.NotificationChannel(Announce.CHANNEL,
                        "أخبار وتنبيهات حول العالم", android.app.NotificationManager.IMPORTANCE_DEFAULT));
                startActivity(new Intent(android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                        .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, getPackageName())
                        .putExtra(android.provider.Settings.EXTRA_CHANNEL_ID, Announce.CHANNEL));
            } catch (Exception ignored) { }
        });
        c1.addView(newsRow);
        verseSwitch = switches.get(Reminders.VERSE);
        wirdSwitch = switches.get(Reminders.WIRD);
        verseTime = chips.get(Reminders.VERSE);
        wirdTime = chips.get(Reminders.WIRD);
        col.addView(c1);

        Button test = new Button(this, null, android.R.attr.borderlessButtonStyle);
        test.setText("جرّب إشعار آية اليوم الآن");
        test.setAllCaps(false);
        test.setTypeface(Ui.font(this, 500));
        test.setTextColor(gold);
        test.setOnClickListener(v -> {
            if (!Notifier.allowed(this)) { askNotifPermission(Reminders.VERSE); return; }
            Toast.makeText(this, "جارٍ جلب آية اليوم…", Toast.LENGTH_SHORT).show();
            new Thread(() -> {
                VerseRepo.Verse vr = VerseRepo.fetchToday(getApplicationContext());
                Notifier.verse(getApplicationContext(), vr);
                VerseWidget.updateAll(getApplicationContext());
            }).start();
        });
        col.addView(test);

        // --- الأذان
        col.addView(section("الأذان ومواقيت الصلاة"));
        LinearLayout c4 = Ui.card(this);
        adhanSwitch = Ui.toggle(this);
        c4.addView(Ui.row(this, "تنبيه الأذان", "عند دخول كل صلاة مع فضلها · طريقة أم القرى", adhanSwitch));
        adhanSwitch.setChecked(Adhan.enabled(this));
        adhanSwitch.setOnCheckedChangeListener((b, on) -> {
            if (suppress) return;
            if (on) enableAdhan();
            else { Adhan.setEnabled(this, false); refreshAdhan(); refreshAdhanHealth(); }
        });
        // حالة دقة الأذان: صلاحية المنبّه الدقيق وتوفير البطارية
        adhanHealth = new LinearLayout(this);
        adhanHealth.setOrientation(LinearLayout.VERTICAL);
        c4.addView(adhanHealth);
        // أعلى دقة: منبّه بنظام «ساعة المنبّه»
        c4.addView(Ui.divider(this));
        Switch precise = Ui.toggle(this);
        precise.setChecked(Adhan.alarmClockMode(this));
        precise.setOnCheckedChangeListener((b, on) -> {
            App.prefs(this).edit().putBoolean("adhan_alarm_clock", on).apply();
            Adhan.scheduleNext(this);
        });
        c4.addView(Ui.row(this, "أعلى دقة لوقت الأذان",
                "يصل في الدقيقة نفسها حتى مع توفير البطارية · قد يظهر رمز المنبّه أعلى الشاشة", precise));
        // الشروق وفضل الضحى
        c4.addView(Ui.divider(this));
        Switch sunrise = Ui.toggle(this);
        sunrise.setChecked(Adhan.sunriseOn(this));
        sunrise.setOnCheckedChangeListener((b, on) -> App.prefs(this).edit().putBoolean("sunrise_on", on).apply());
        c4.addView(Ui.row(this, "تنبيه الشروق", "انتهاء وقت الفجر، وفضل الجلوس للذكر وصلاة الضحى", sunrise));
        // تذكير الصيام المسنون
        c4.addView(Ui.divider(this));
        Switch fasting = Ui.toggle(this);
        fasting.setChecked(Adhan.fastingOn(this));
        fasting.setOnCheckedChangeListener((b, on) -> {
            App.prefs(this).edit().putBoolean("fasting_on", on).apply();
            Adhan.scheduleNext(this);
        });
        c4.addView(Ui.row(this, "تذكير الصيام المسنون", "ليلة الاثنين والخميس والأيام البيض وعرفة وعاشوراء", fasting));
        c4.addView(Ui.divider(this));
        LinearLayout placeRow = new LinearLayout(this);
        placeRow.setGravity(Gravity.CENTER_VERTICAL);
        placeRow.setPadding(0, 0, 0, dp(10));
        adhanPlace = Ui.text(this, "", 13, muted, 400);
        adhanPlace.setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_pin, 0, 0, 0);
        adhanPlace.setCompoundDrawablePadding(dp(6));
        placeRow.addView(adhanPlace, new LinearLayout.LayoutParams(0, -2, 1f));
        TextView locBtn = Ui.text(this, "تحديث الموقع", 13, gold, 700);
        locBtn.setPadding(dp(8), dp(10), dp(8), dp(10));
        locBtn.setOnClickListener(v -> { if (!Loc.hasPermission(this)) requestLocation(); else refreshLocation(false); });
        placeRow.addView(locBtn);
        c4.addView(placeRow);
        prayerGrid = new LinearLayout(this);
        prayerGrid.setPadding(0, 0, 0, dp(14));
        c4.addView(prayerGrid);
        c4.addView(Ui.divider(this));
        LinearLayout soundRow = new LinearLayout(this);
        soundRow.setGravity(Gravity.CENTER_VERTICAL);
        soundRow.setMinimumHeight(dp(52));
        soundRow.addView(Ui.text(this, "صوت تنبيه الأذان", 15, ink, 500), new LinearLayout.LayoutParams(0, -2, 1f));
        soundRow.addView(Ui.text(this, "تغيير ›", 13, muted, 400));
        soundRow.setOnClickListener(v -> {
            Notifier.ensureChannels(this);
            try {
                startActivity(new Intent(android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                        .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, getPackageName())
                        .putExtra(android.provider.Settings.EXTRA_CHANNEL_ID, Notifier.CH_ADHAN));
            } catch (Exception ignored) { }
        });
        c4.addView(soundRow);
        c4.addView(Ui.divider(this));
        LinearLayout qiblaRow = new LinearLayout(this);
        qiblaRow.setGravity(Gravity.CENTER_VERTICAL);
        qiblaRow.setMinimumHeight(dp(52));
        qiblaRow.addView(Ui.iconTitle(this, R.drawable.ic_l_compass, "بوصلة القبلة", 15, ink, 500, gold), new LinearLayout.LayoutParams(0, -2, 1f));
        qiblaRow.addView(Ui.text(this, "افتح ›", 13, muted, 400));
        qiblaRow.setOnClickListener(v -> startActivity(new Intent(this, QiblaActivity.class)));
        c4.addView(qiblaRow);
        col.addView(c4);

        if (!notifOnly) {
        // --- القراءة
        col.addView(section("القراءة"));
        LinearLayout c3 = Ui.card(this);
        Switch screen = Ui.toggle(this);
        screen.setChecked(App.prefs(this).getBoolean("keep_screen", true));
        screen.setOnCheckedChangeListener((b, on) -> App.prefs(this).edit().putBoolean("keep_screen", on).apply());
        c3.addView(Ui.row(this, "إبقاء الشاشة مضاءة", "لا تنطفئ الشاشة أثناء القراءة والاستماع", screen));
        c3.addView(Ui.divider(this));
        TextView zoomLabel = Ui.text(this, "", 16, ink, 700);
        zoomLabel.setPadding(0, dp(14), 0, dp(2));
        c3.addView(zoomLabel);
        TextView zoomSub = Ui.text(this, "حجم النص في صفحات القراءة والتفسير", 13, muted, 400);
        c3.addView(zoomSub);
        android.widget.SeekBar zoom = new android.widget.SeekBar(this);
        zoom.setMax(8);                                   // 80% .. 160% بخطوة 10
        int cur = App.prefs(this).getInt("text_zoom", 100);
        zoom.setProgress((cur - 80) / 10);
        zoom.setProgressTintList(android.content.res.ColorStateList.valueOf(ink));
        zoom.setThumbTintList(android.content.res.ColorStateList.valueOf(gold));
        zoom.setContentDescription("حجم الخط");
        zoomLabel.setText("حجم الخط: " + Adhan.arabic(String.valueOf(cur)) + "٪");
        zoom.setOnSeekBarChangeListener(new android.widget.SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(android.widget.SeekBar b, int v, boolean user) {
                int z = 80 + v * 10;
                App.prefs(SettingsActivity.this).edit().putInt("text_zoom", z).apply();
                zoomLabel.setText("حجم الخط: " + Adhan.arabic(String.valueOf(z)) + "٪");
            }
            @Override public void onStartTrackingTouch(android.widget.SeekBar b) { }
            @Override public void onStopTrackingTouch(android.widget.SeekBar b) { }
        });
        LinearLayout.LayoutParams zlp = new LinearLayout.LayoutParams(-1, dp(48));
        zlp.bottomMargin = dp(6);
        c3.addView(zoom, zlp);
        if (Ui.canSetTheme()) {                           // المظهر: تلقائي / نهاري / ليلي
            c3.addView(Ui.divider(this));
            TextView th = Ui.text(this, "المظهر", 16, ink, 700);
            th.setPadding(0, dp(14), 0, dp(10));
            c3.addView(th);
            LinearLayout modes = new LinearLayout(this);
            String[] names = {"تلقائي", "نهاري", "ليلي"};
            int curMode = Ui.themeMode(this);
            for (int i = 0; i < 3; i++) {
                final int mode = i;
                boolean on = i == curMode;
                TextView m = Ui.text(this, names[i], 14, on ? 0xFFFFFFFF : ink, 500);
                m.setGravity(Gravity.CENTER);
                m.setBackground(on ? Ui.shape(getColor(R.color.primary), 20, 0, this)
                        : Ui.shape(getColor(R.color.card), 20, getColor(R.color.field_border), this));
                m.setOnClickListener(v -> { if (mode != Ui.themeMode(this)) { Ui.applyTheme(this, mode); recreate(); } });
                LinearLayout.LayoutParams ml = new LinearLayout.LayoutParams(0, -1, 1f);
                if (i > 0) ml.setMarginStart(dp(8));
                modes.addView(Ui.minH(m, 42), ml);
            }
            LinearLayout.LayoutParams mlp = new LinearLayout.LayoutParams(-1, -2);
            mlp.bottomMargin = dp(14);
            c3.addView(modes, mlp);
        }
        col.addView(c3);
        TextView tip = Ui.text(this, "أضف ويدجت «آية اليوم» و«مواقيت الصلاة»: اضغط مطولًا على مكان فارغ في الشاشة الرئيسية ← الأدوات ← حول العالم.", 13, muted, 400);
        tip.setPadding(dp(6), dp(10), dp(6), 0);
        col.addView(tip);

        // --- عام
        col.addView(section("عام"));
        Button share = Ui.button(this, "شارك التطبيق مع من تحب", true);
        share.setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_share, 0, 0, 0);
        share.setPadding(dp(32), dp(6), dp(32), dp(6));
        share.setCompoundDrawablePadding(dp(10));
        share.setOnClickListener(v -> startActivity(Intent.createChooser(
                new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, App.shareText(this)),
                "شارك التطبيق")));
        // بعرض محتواه في المنتصف: الأيقونة تبقى ملاصقة للنص مهما اتسعت الشاشة
        LinearLayout.LayoutParams shareLp = new LinearLayout.LayoutParams(-2, -2);
        shareLp.gravity = Gravity.CENTER_HORIZONTAL;
        col.addView(Ui.minH(share, 54), shareLp);
        LinearLayout two = new LinearLayout(this);
        LinearLayout.LayoutParams twoLp = new LinearLayout.LayoutParams(-1, -2);
        twoLp.topMargin = dp(10);
        Button update = Ui.button(this, "البحث عن تحديث", false);
        update.setOnClickListener(v -> UpdateChecker.check(this, true));
        Button feedback = Ui.button(this, "أرسل ملاحظة", false);
        feedback.setOnClickListener(v -> { startActivity(App.openInApp(this, App.CONTACT)); finish(); });
        LinearLayout.LayoutParams half = new LinearLayout.LayoutParams(0, -1, 1f);
        LinearLayout.LayoutParams half2 = new LinearLayout.LayoutParams(0, -1, 1f);
        half2.setMarginStart(dp(10));
        two.addView(Ui.minH(update, 50), half);
        two.addView(Ui.minH(feedback, 50), half2);
        col.addView(two, twoLp);

        if (Crash.has(this)) {
            Button crash = Ui.button(this, "توقف التطبيق سابقًا — أرسل تقرير العطل", true);
            crash.setOnClickListener(v -> { Crash.share(this); v.setVisibility(View.GONE); });
            LinearLayout.LayoutParams cl = new LinearLayout.LayoutParams(-1, -2);
            cl.topMargin = dp(10);
            col.addView(Ui.minH(crash, 52), cl);
        }

        Button tour = Ui.button(this, "جولة في مميزات التطبيق", false);
        tour.setOnClickListener(v -> FeaturesActivity.open(this));
        LinearLayout.LayoutParams tourLp = new LinearLayout.LayoutParams(-1, -2);
        tourLp.topMargin = dp(10);
        col.addView(Ui.minH(tour, 52), tourLp);

        TextView ver = Ui.text(this, "✦  الإصدار " + Adhan.arabic(App.versionName(this)) + "  ✦", 13, muted, 500);
        ver.setOnLongClickListener(v -> {
            String d = App.prefs(this).getString("bridge_diag", "لا يوجد تشخيص بعد — افتح صفحة من المصحف ثم عد هنا");
            new android.app.AlertDialog.Builder(this, Ui.dialogTheme(this)).setTitle("تشخيص صفحة المصحف")
                    .setMessage(d).setPositiveButton("حسنًا", null).show();
            return true;
        });
        ver.setGravity(Gravity.CENTER);
        ver.setPadding(0, dp(30), 0, dp(6));
        final int[] taps = {0};
        ver.setOnClickListener(v -> {                 // لصاحب الموقع: 7 لمسات تستبعد زيارات هذا الجوال من الإحصاءات
            if (++taps[0] < 7) return;
            taps[0] = 0;
            boolean on = !App.prefs(this).getBoolean("internal_device", false);
            App.prefs(this).edit().putBoolean("internal_device", on).apply();
            Toast.makeText(this, on ? "تم: زيارات هذا الجوال لن تُحسب في الإحصاءات (أعد فتح التطبيق)"
                    : "عادت زيارات هذا الجوال تُحسب في الإحصاءات", Toast.LENGTH_LONG).show();
        });
        col.addView(ver);
        TextView privacy = Ui.text(this, "سياسة الخصوصية", 13, gold, 700);
        privacy.setGravity(Gravity.CENTER);
        privacy.setPadding(0, dp(4), 0, dp(10));
        privacy.setOnClickListener(v -> { startActivity(App.openInApp(this, App.PRIVACY)); finish(); });
        col.addView(privacy);
        TextView foot = Ui.text(this, "صدقة جارية لمحمد بن مفرح الشهري رحمه الله، ولموتى المسلمين", 12, muted, 400);
        foot.setGravity(Gravity.CENTER);
        col.addView(foot);
        }   // !notifOnly

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(getColor(R.color.page));
        scroll.addView(col);
        setContentView(scroll);
        Ui.applyInsets(scroll);
        refreshTimes();
        refreshAdhan();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (Adhan.enabled(this)) Adhan.scheduleNext(this);
        refreshAdhan();
        refreshAdhanHealth();
    }

    // ------------------------------------------------------------------ التذكيرات

    private void toggle(String kind, boolean on) {
        if (on && !Notifier.allowed(this)) { askNotifPermission(kind); return; }
        Reminders.set(this, kind, on, Reminders.hour(this, kind), Reminders.minute(this, kind));
        refreshTimes();
        if (on) Toast.makeText(this, "سيصلك التذكير يوميًا الساعة "
                + Adhan.arabic(App.formatTime(Reminders.hour(this, kind), Reminders.minute(this, kind))), Toast.LENGTH_SHORT).show();
    }

    private void askNotifPermission(String kind) {
        if (Build.VERSION.SDK_INT >= 33) {
            pendingKind = kind;
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQ_NOTIF);
            return;
        }
        // قبل أندرويد 13 لا يوجد طلب صلاحية: الإشعارات مطفأة من إعدادات الجوال، فنعيد المفتاح ونفتح الإعدادات
        pendingKind = null;
        setChecked(ADHAN.equals(kind) ? adhanSwitch : switches.get(kind), false);
        Toast.makeText(this, "الإشعارات متوقفة لهذا التطبيق، فعّلها من الصفحة التالية", Toast.LENGTH_LONG).show();
        try {
            startActivity(new Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, getPackageName()));
        } catch (Exception ignored) { }
    }

    private void pickTime(String kind) {
        new TimePickerDialog(this, (tp, h, m) -> {
            if (Reminders.WIRD.equals(kind)) App.prefs(this).edit().putInt("wird_prayer", -1).apply();   // وقت ثابت بدل الصلاة
            Reminders.set(this, kind, true, h, m);
            setChecked(switches.get(kind), true);
            refreshTimes();
        }, Reminders.hour(this, kind), Reminders.minute(this, kind), false).show();
    }

    private void refreshTimes() {
        for (String kind : Reminders.ALL) {
            Button chip = chips.get(kind);
            if (chip == null) continue;
            String t = Adhan.arabic(App.formatTime(Reminders.hour(this, kind), Reminders.minute(this, kind)));
            if (Reminders.WIRD.equals(kind)) t = Reminders.wirdLabel(this);
            else if (Reminders.byPrayer(this, kind)) t = Reminders.AZKAR_AM.equals(kind) ? "بعد الفجر بربع ساعة" : "بعد العصر بربع ساعة";
            chip.setText(Reminders.KAHF.equals(kind) ? "الجمعة " + t : t);
            chip.setAlpha(Reminders.enabled(this, kind) ? 1f : 0.5f);
        }
    }

    // ------------------------------------------------------------------ الأذان

    private void enableAdhan() {
        if (!Notifier.allowed(this)) { askNotifPermission(ADHAN); return; }
        if (!Loc.hasPermission(this)) { requestLocation(); return; }
        if (!Adhan.hasLocation(this)) { refreshLocation(true); return; }
        Adhan.setEnabled(this, true);
        refreshAdhan();
        refreshAdhanHealth();
        Toast.makeText(this, "تم تفعيل تنبيه الأذان ✓", Toast.LENGTH_SHORT).show();
        maybeAskExactAlarms();
    }

    private void requestLocation() {
        requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION}, REQ_LOC);
    }

    private void refreshLocation(boolean thenEnable) {
        Toast.makeText(this, "جارٍ تحديد موقعك…", Toast.LENGTH_SHORT).show();
        Loc.get(this, l -> {
            if (isFinishing() || isDestroyed()) {
                // أُغلقت الشاشة قبل وصول الموقع: نحفظه دون أي نافذة
                if (l != null) {
                    Context a = getApplicationContext();
                    Adhan.saveLocation(a, l.getLatitude(), l.getLongitude());
                    if (thenEnable && Notifier.allowed(a)) Adhan.setEnabled(a, true);
                    Adhan.scheduleNext(a);
                    PrayerWidget.updateAll(a);
                }
                return;
            }
            if (l == null) {
                Toast.makeText(this, "تعذّر تحديد الموقع، فعّل خدمة الموقع (GPS) ثم حاول مرة أخرى", Toast.LENGTH_LONG).show();
                if (thenEnable) setChecked(adhanSwitch, false);
                return;
            }
            Adhan.saveLocation(this, l.getLatitude(), l.getLongitude());
            Adhan.scheduleNext(this);
            PrayerWidget.updateAll(this);
            refreshAdhan();
            if (thenEnable) enableAdhan();
            new Thread(() -> {
                String city = Loc.cityName(getApplicationContext(), l.getLatitude(), l.getLongitude());
                Adhan.saveCity(getApplicationContext(), city);
                runOnUiThread(() -> { if (!isDestroyed()) refreshAdhan(); PrayerWidget.updateAll(getApplicationContext()); });
            }).start();
        });
    }

    /** يوضح سبب تأخر الأذان إن وُجد، مع زر إصلاح مباشر */
    private void refreshAdhanHealth() {
        if (adhanHealth == null) return;
        adhanHealth.removeAllViews();
        if (!Adhan.enabled(this)) return;
        String msg; String btn = null; Runnable fix = null;
        int late = Adhan.lastLate(this);
        if (!Adhan.canExact(this)) {
            msg = "⚠️ قد يتأخر الأذان عدة دقائق: صلاحية «المنبهات والتذكيرات» غير مفعّلة";
            btn = "السماح";
            fix = () -> {
                try {
                    startActivity(new Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:" + getPackageName())));
                } catch (Exception ignored) { }
            };
        } else if (!Adhan.batteryFree(this)) {
            msg = "⚠️ توفير البطارية قد يؤخر الأذان. من الصفحة التالية: البطارية ← «غير مقيّد»";
            btn = "فتح الإعدادات";
            fix = () -> {
                try {
                    startActivity(new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:" + getPackageName())));
                } catch (Exception ignored) { }
            };
        } else {
            msg = late >= 3
                    ? "آخر أذان تأخر " + Adhan.arabic(String.valueOf(late)) + " دقائق. إن تكرر، أوقف «التطبيقات النائمة» من إعدادات البطارية في جوالك"
                    : "✓ التنبيه مضبوط ليصل في وقته بالدقيقة";
        }
        adhanHealth.setPadding(0, dp(10), 0, 0);
        TextView t = Ui.text(this, msg, 13, msg.startsWith("✓") ? getColor(R.color.gold) : muted, 500);
        adhanHealth.addView(t);
        if (btn != null) {
            Button b = Ui.chip(this, btn);
            final Runnable go = fix;
            b.setOnClickListener(v -> go.run());
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
            lp.topMargin = dp(8);
            adhanHealth.addView(b, lp);
        }
    }

    private void maybeAskExactAlarms() {
        if (Build.VERSION.SDK_INT < 31 || Adhan.canExact(this) || isFinishing() || isDestroyed()) return;
        AlertDialog d = new AlertDialog.Builder(this, Ui.dialogTheme(this))
                .setTitle("دقة وقت الأذان")
                .setMessage("ليصلك التنبيه في الدقيقة نفسها، اسمح للتطبيق بـ«المنبهات والتذكيرات» من الصفحة التالية.")
                .setPositiveButton("السماح", (x, w) -> {
                    try {
                        startActivity(new Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:" + getPackageName())));
                    } catch (Exception ignored) { }
                })
                .setNegativeButton("لاحقًا", null)
                .create();
        d.show();
        if (d.getWindow() != null) d.getWindow().getDecorView().setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
    }

    private void setChecked(Switch s, boolean on) {
        suppress = true;
        s.setChecked(on);
        suppress = false;
    }

    private void refreshAdhan() {
        if (prayerGrid == null) return;
        setChecked(adhanSwitch, Adhan.enabled(this));
        prayerGrid.removeAllViews();
        if (!Adhan.hasLocation(this)) {
            adhanPlace.setText("لم يُحدَّد الموقع بعد");
            prayerGrid.addView(Ui.text(this, "حدّد موقعك لعرض مواقيت الصلاة", 14, muted, 400));
            return;
        }
        String city = Adhan.city(this);
        adhanPlace.setText((city.isEmpty() ? "موقعك الحالي" : city) + " · " + Ui.hijriToday());

        int[] prayers = {PrayerCalc.FAJR, PrayerCalc.DHUHR, PrayerCalc.ASR, PrayerCalc.MAGHRIB, PrayerCalc.ISHA};
        long[] t = Adhan.times(this, Calendar.getInstance());
        long now = System.currentTimeMillis();
        int next = -1;
        for (int k = 0; k < prayers.length; k++) if (t[prayers[k]] > now) { next = k; break; }
        for (int k = 0; k < prayers.length; k++) {
            boolean isNext = k == next;
            LinearLayout cell = new LinearLayout(this);
            cell.setOrientation(LinearLayout.VERTICAL);
            cell.setGravity(Gravity.CENTER);
            cell.setPadding(0, dp(8), 0, dp(8));
            // الخلية القادمة: خلفية «primary» بنص فاتح؛ تبقى مقروءة في الوضعين الفاتح والداكن
            // ألوان ثابتة للخلية القادمة (ذهبي بنص داكن) حتى لا يعبث بها الوضع الداكن في بعض الجوالات
            cell.setBackground(Ui.shape(isNext ? 0xFFC9A876 : getColor(R.color.chip), 12, 0, this));
            TextView nm = Ui.text(this, Adhan.NAMES[prayers[k]], 12, isNext ? 0xFF0E2C31 : muted, isNext ? 700 : 400);
            nm.setGravity(Gravity.CENTER);
            Ui.capScale(nm, 12, 1.15f);
            nm.setSingleLine(true);
            cell.addView(nm, new LinearLayout.LayoutParams(-1, -2));
            TextView tm = Ui.text(this, Adhan.clock(t[prayers[k]]).replace(" ص", "").replace(" م", ""), 14,
                    isNext ? 0xFF0E2C31 : ink, 700);
            tm.setGravity(Gravity.CENTER);
            Ui.capScale(tm, 14, 1.15f);
            tm.setSingleLine(true);
            tm.setPadding(0, dp(4), 0, 0);
            cell.addView(tm, new LinearLayout.LayoutParams(-1, -2));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
            if (k > 0) lp.setMarginStart(dp(5));
            prayerGrid.addView(cell, lp);
        }
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        super.onRequestPermissionsResult(code, perms, results);
        if (code == REQ_LOC) {
            if (Loc.hasPermission(this)) {
                if (adhanSwitch.isChecked()) enableAdhan();
                else refreshLocation(false);
            } else {
                Toast.makeText(this, "نحتاج موقعك لحساب مواقيت الصلاة بدقة", Toast.LENGTH_LONG).show();
                setChecked(adhanSwitch, false);
            }
            return;
        }
        if (code != REQ_NOTIF || pendingKind == null) return;
        String kind = pendingKind;
        pendingKind = null;
        if (ADHAN.equals(kind)) {
            if (Notifier.allowed(this)) enableAdhan();
            else { setChecked(adhanSwitch, false); Toast.makeText(this, "فعّل الإشعارات للتطبيق من إعدادات الجوال", Toast.LENGTH_LONG).show(); }
            return;
        }
        boolean ok = Notifier.allowed(this);
        if (!ok) Toast.makeText(this, "فعّل الإشعارات للتطبيق من إعدادات الجوال", Toast.LENGTH_LONG).show();
        Reminders.set(this, kind, ok, Reminders.hour(this, kind), Reminders.minute(this, kind));
        for (String k : Reminders.ALL) if (switches.get(k) != null) setChecked(switches.get(k), Reminders.enabled(this, k));
        refreshTimes();
    }

    // ------------------------------------------------------------------ أدوات

    private int dp(int v) { return Ui.dp(this, v); }

    private LinearLayout.LayoutParams chipLp() {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
        lp.bottomMargin = dp(12);
        lp.gravity = Gravity.START;
        return lp;
    }

    private TextView section(String s) {
        TextView t = Ui.text(this, s, 13, gold, 700);
        t.setPadding(dp(6), dp(24), dp(6), dp(10));
        return t;
    }
}
