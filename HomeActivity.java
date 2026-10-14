package com.hawlalaalam.quran;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.View;
import android.widget.Chronometer;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Calendar;

/**
 * شاشة «اليوم» — مرتّبة بلا تشتيت:
 * ١) الترويسة والصلاة القادمة، ٢) بطاقة واحدة «أكمل القراءة» مع حلقة الختمة،
 * ٣) بطاقة في وقتها فقط (رمضان أو الأذكار)، ٤) آية اليوم، ٥) أربع أدوات وباقيها في «الأدوات».
 */
public class HomeActivity extends Activity {

    @Override
    protected void attachBaseContext(android.content.Context base) {
        super.attachBaseContext(Ui.wrap(base));                // المظهر المختار يُطبَّق فورًا
    }
    static final String EXTRA_FROM_HOME = "from_home";

    private LinearLayout col;
    private int ink, muted, gold, goldL, ivoryBorder, page;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (!App.prefs(this).getBoolean("welcomed", false)) {
            startActivity(new Intent(this, WelcomeActivity.class));
        } else if (FeaturesActivity.shouldShow(this)) {
            FeaturesActivity.open(this);              // شرح المميزات مرة بعد التحديث
        }
        ink = getColor(R.color.ink);
        muted = getColor(R.color.muted);
        gold = getColor(R.color.gold_deep);
        goldL = getColor(R.color.gold);
        ivoryBorder = getColor(R.color.ivory_border);
        page = getColor(R.color.page);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(page);
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);

        ScrollView scroll = new ScrollView(this);
        col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(16), dp(14), dp(16), dp(24));
        scroll.addView(col);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));
        root.addView(bottomNav());

        setContentView(root);
        Ui.applyInsets(root, false);                     // الشريط السفلي بعرض الشاشة
        Ui.applyInsets(scroll);                          // والمحتوى بعرض مريح على الأجهزة اللوحية
        Notifier.ensureChannels(this);
        Reminders.scheduleAll(this);
        Announce.checkSoon(this);
        Adhan.scheduleNext(this);

        // «اليوم» هي الشاشة الرئيسية: الرجوع منها يخرج من التطبيق ويُبقيه جاهزًا في الخلفية
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                    android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, () -> moveTaskToBack(true));
        }
        // تسخين محرّك الصفحات أثناء الخمول: أول فتح للموقع يصبح أسرع بشكل ملحوظ
        android.os.Looper.myQueue().addIdleHandler(() -> {
            warmWebView(getApplicationContext());
            return false;
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (Ui.isNight(this) != Ui.isNight(Ui.wrap(getApplicationContext()))) { recreate(); return; }
        render();
        RamadanWidget.updateAll(this);
        KhatmaWidget.updateAll(this);
        UpdateChecker.check(this, false);
        if (!VerseRepo.isFresh(this)) {
            new Thread(() -> {
                VerseRepo.fetchToday(getApplicationContext());
                runOnUiThread(() -> { if (!isFinishing()) render(); });
            }).start();
        }
    }

    // ------------------------------------------------------------------ البناء

    private void render() {
        col.removeAllViews();
        col.addView(hero());
        // البطاقة الرئيسية تتداخل مع أسفل الترويسة الداكنة
        LinearLayout.LayoutParams ml = new LinearLayout.LayoutParams(-1, -2);
        ml.topMargin = -dp(46);
        ml.setMarginStart(dp(10));
        ml.setMarginEnd(dp(10));
        col.addView(mainCard(), ml);
        // بطاقة واحدة فقط حسب الوقت: رمضان أولًا، وإلا الأذكار في وقتها
        View ctx = ramadanCard();
        if (ctx == null) ctx = azkarPrompt();
        if (ctx != null) col.addView(ctx, gap(14));
        col.addView(verseCard(), gap(14));
        col.addView(toolsHeader(), gap(22));
        col.addView(toolsRow(), gap(10));
    }

    // ------------------------------------------------------------------ الترويسة

    /** ترويسة داكنة بزخرفة: التحية والتاريخ، زر المظهر والإعدادات، ثم شريط الصلاة القادمة */
    private View hero() {
        LinearLayout hero = new LinearLayout(this);
        hero.setOrientation(LinearLayout.VERTICAL);
        hero.setPadding(dp(16), dp(16), dp(16), dp(16) + dp(46));      // مساحة للبطاقة المتداخلة
        hero.setBackground(new Ui.PatternDrawable(this, getColor(R.color.dark), 26));

        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.app_logo_png);
        logo.setClipToOutline(true);
        logo.setBackground(Ui.shape(0xFF0E2C31, 12, 0x66C9A876, this));
        logo.setContentDescription("حول العالم");
        row.addView(logo, new LinearLayout.LayoutParams(dp(44), dp(44)));

        LinearLayout texts = new LinearLayout(this);
        texts.setOrientation(LinearLayout.VERTICAL);
        texts.setPadding(dp(12), 0, dp(8), 0);
        int h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
        texts.addView(Ui.text(this, h < 12 ? "صباح الخير" : "مساء الخير", 22, 0xFFFFFFFF, 700));
        String city = Adhan.city(this);
        TextView sub = Ui.text(this, Ui.hijriToday() + (city.isEmpty() ? "" : " · " + city), 13,
                getColor(R.color.on_dark_muted), 400);
        sub.setMaxLines(1);
        sub.setEllipsize(android.text.TextUtils.TruncateAt.END);
        texts.addView(sub);
        row.addView(texts, new LinearLayout.LayoutParams(0, -2, 1f));

        if (Ui.canSetTheme()) {                         // زر الوضع الليلي/النهاري
            boolean night = Ui.isNight(this);
            ImageView tb = heroButton(night ? R.drawable.ic_l_sun : R.drawable.ic_l_moon,
                    night ? "الوضع النهاري" : "الوضع الليلي");
            tb.setOnClickListener(v -> { Ui.applyTheme(this, night ? 1 : 2); recreate(); });
            LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(dp(44), dp(44));
            tl.setMarginEnd(dp(8));
            row.addView(tb, tl);
        }
        ImageView st = heroButton(R.drawable.ic_nav_settings, "الإعدادات");
        st.setOnClickListener(v -> startActivity(new Intent(this, SettingsActivity.class)));
        row.addView(st, new LinearLayout.LayoutParams(dp(44), dp(44)));
        hero.addView(row);

        LinearLayout.LayoutParams pl = new LinearLayout.LayoutParams(-1, -2);
        pl.topMargin = dp(16);
        hero.addView(prayerStrip(), pl);
        return hero;
    }

    private ImageView heroButton(int icon, String label) {
        ImageView b = Ui.icon(this, icon, 0xFFE9D9B8, 20);
        b.setScaleType(ImageView.ScaleType.CENTER);
        b.setBackground(Ui.shape(0x14FFFFFF, 14, 0x4DC9A876, this));
        b.setContentDescription(label);
        b.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        return b;
    }

    /** سطر الصلاة القادمة مع العدّ التنازلي؛ وبدون موقع: دعوة لتفعيل المواقيت */
    private View prayerStrip() {
        LinearLayout s = new LinearLayout(this);
        s.setGravity(Gravity.CENTER_VERTICAL);
        s.setPadding(dp(14), dp(10), dp(14), dp(10));
        s.setBackground(Ui.shape(0x14FFFFFF, 16, 0x40C9A876, this));
        s.addView(Ui.icon(this, R.drawable.ic_clock, goldL, 18));

        if (!Adhan.hasLocation(this)) {
            TextView t = Ui.text(this, "فعّل مواقيت الصلاة وتنبيه الأذان", 14, 0xFFFFFFFF, 700);
            t.setPadding(dp(10), 0, dp(8), 0);
            s.addView(t, new LinearLayout.LayoutParams(0, -2, 1f));
            s.addView(Ui.text(this, "تفعيل ←", 13, goldL, 700));
            s.setContentDescription("فعّل مواقيت الصلاة");
            s.setOnClickListener(v -> startActivity(new Intent(this, SettingsActivity.class)));
            return Ui.minH(s, 46);
        }

        long[] nx = Adhan.next(this);
        int idx = (int) nx[0];
        long at = nx[1];
        boolean friday = isFridayDhuhr(idx, at);
        TextView name = Ui.text(this, friday ? "الجمعة" : Adhan.NAMES[idx], 15, 0xFFFFFFFF, 700);
        name.setPadding(dp(10), 0, dp(6), 0);
        s.addView(name);
        s.addView(Ui.text(this, Adhan.clock(at), 13, getColor(R.color.on_dark_muted), 400));
        View spacer = new View(this);
        s.addView(spacer, new LinearLayout.LayoutParams(0, 1, 1f));
        s.addView(Ui.text(this, "بعد ", 13, getColor(R.color.on_dark_muted), 400));
        Chronometer ch = new Chronometer(this);
        ch.setTextColor(0xFFE9D9B8);              // ثابت: الترويسة داكنة دائمًا
        ch.setTextSize(15);
        ch.setTypeface(Ui.font(this, 700));
        ch.setCountDown(true);
        ch.setBase(SystemClock.elapsedRealtime() + (at - System.currentTimeMillis()));
        ch.setOnChronometerTickListener(c -> { if (c.getBase() <= SystemClock.elapsedRealtime()) render(); });
        ch.start();
        s.addView(ch);
        s.setContentDescription("الصلاة القادمة " + (friday ? "الجمعة" : Adhan.NAMES[idx]) + " " + Adhan.clock(at)
                + "، اضغط لعرض المواقيت");
        s.setOnClickListener(v -> openWeb(App.HOME + "prayer-times-ar.html"));
        return Ui.minH(s, 46);
    }

    private static boolean isFridayDhuhr(int idx, long at) {
        if (idx != PrayerCalc.DHUHR) return false;
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(at);
        return c.get(Calendar.DAY_OF_WEEK) == Calendar.FRIDAY;
    }

    // ------------------------------------------------------------------ البطاقة الرئيسية

    /** «أكمل من حيث توقفت» + حلقة الختمة + ورد اليوم، بزر واحد واضح */
    private View mainCard() {
        String url = Reading.lastUrl(this);
        boolean khatma = Khatma.active(this) && !Khatma.done(this);

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(16), dp(16), dp(16));
        card.setBackground(Ui.shape(getColor(R.color.card), 22, getColor(R.color.line), this));
        card.setElevation(dp(6));

        LinearLayout top = new LinearLayout(this);
        top.setGravity(Gravity.CENTER_VERTICAL);

        // الحلقة: نسبة الختمة، أو أيقونة المصحف إن لم تبدأ ختمة
        FrameLayout badge = new FrameLayout(this);
        if (khatma) {
            int pct = Khatma.percent(this);
            Ui.Ring ring = new Ui.Ring(this, getColor(R.color.chip), goldL);
            ring.setFraction(pct / 100f);
            badge.addView(ring, new FrameLayout.LayoutParams(-1, -1));
            LinearLayout mid = new LinearLayout(this);
            mid.setOrientation(LinearLayout.VERTICAL);
            mid.setGravity(Gravity.CENTER);
            TextView p = Ui.text(this, Adhan.arabic(String.valueOf(pct)) + "٪", 17, ink, 700);
            p.setGravity(Gravity.CENTER);
            mid.addView(p);
            TextView l = Ui.text(this, "الختمة", 10, muted, 400);
            l.setGravity(Gravity.CENTER);
            mid.addView(l);
            badge.addView(mid, new FrameLayout.LayoutParams(-1, -1));
            badge.setContentDescription("ختمتي " + Adhan.arabic(String.valueOf(pct)) + "٪");
        } else {
            ImageView ic = new ImageView(this);
            ic.setImageResource(R.drawable.ic_mushaf_t);
            ic.setScaleType(ImageView.ScaleType.CENTER);
            ic.setBackground(Ui.shape(getColor(R.color.chip), 40, 0, this));
            badge.addView(ic, new FrameLayout.LayoutParams(-1, -1));
            badge.setContentDescription("ختمتي");
        }
        badge.setOnClickListener(v -> startActivity(new Intent(this, KhatmaActivity.class)));
        top.addView(badge, new LinearLayout.LayoutParams(dp(80), dp(80)));

        LinearLayout t = new LinearLayout(this);
        t.setOrientation(LinearLayout.VERTICAL);
        t.setPadding(dp(14), 0, 0, 0);
        t.addView(Ui.text(this, url == null ? "ابدأ القراءة" : "أكمل من حيث توقفت", 12, gold, 700));
        TextView title = Ui.text(this, url == null ? "المصحف الشريف" : Reading.lastTitle(this), 18, ink, 700);
        title.setMaxLines(2);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        t.addView(title);
        TextView line = Ui.text(this, khatma ? Khatma.todayLine(this) : "ابدأ ختمة: نحسب وردك كل يوم ونذكّرك به",
                13, muted, 400);
        line.setPadding(0, dp(2), 0, 0);
        t.addView(line);
        top.addView(t, new LinearLayout.LayoutParams(0, -2, 1f));
        card.addView(top);

        if (khatma) {
            // تقدّم ورد اليوم
            int target = Math.max(1, Khatma.dailyTarget(this));
            int doneToday = Math.min(target, Khatma.todayCount(this));
            android.widget.ProgressBar bar = new android.widget.ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
            bar.setMax(target);
            bar.setProgress(doneToday);
            bar.setProgressTintList(android.content.res.ColorStateList.valueOf(goldL));
            bar.setProgressBackgroundTintList(android.content.res.ColorStateList.valueOf(getColor(R.color.chip)));
            bar.setContentDescription("ورد اليوم " + Adhan.arabic(String.valueOf(doneToday)) + " من "
                    + Adhan.arabic(String.valueOf(target)) + " صفحة");
            LinearLayout.LayoutParams bl = new LinearLayout.LayoutParams(-1, dp(10));
            bl.topMargin = dp(12);
            card.addView(bar, bl);
        }

        LinearLayout btns = new LinearLayout(this);
        View go = Ui.pill(this, R.drawable.ic_mushaf_t, url == null ? "افتح المصحف" : "أكمل القراءة", true);
        go.setOnClickListener(v -> openWeb(url == null ? App.mushaf(this) : url));
        btns.addView(Ui.minH(go, 48), new LinearLayout.LayoutParams(0, -2, 1f));
        // الختمة من الحلقة نفسها؛ والزر الثاني لفهرس السور والأجزاء (دون إنترنت)
        View plan = Ui.pill(this, R.drawable.ic_book, "الفهرس", false);
        plan.setContentDescription("فهرس السور والأجزاء");
        plan.setOnClickListener(v -> startActivity(new Intent(this, SurahIndexActivity.class)));
        LinearLayout.LayoutParams pl = new LinearLayout.LayoutParams(-2, -2);
        pl.setMarginStart(dp(8));
        btns.addView(Ui.minH(plan, 48), pl);
        LinearLayout.LayoutParams bl = new LinearLayout.LayoutParams(-1, -2);
        bl.topMargin = dp(14);
        card.addView(btns, bl);
        return card;
    }

    // ------------------------------------------------------------------ بطاقات في وقتها

    /** وضع رمضان: يظهر في رمضان، وقبله بعشرة أيام */
    private View ramadanCard() {
        boolean active = Ramadan.active();
        int until = active ? 0 : Ramadan.daysUntil();
        if (!active && (until < 1 || until > 10)) return null;
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(18), dp(16), dp(18), dp(16));
        card.setBackground(Ui.shape(getColor(R.color.dark), 22, 0, this));
        if (!active) {
            card.addView(Ui.iconTitle(this, R.drawable.ic_l_moon, "رمضان على الأبواب", 13, goldL, 700, goldL));
            TextView t = Ui.text(this, "بعد " + Adhan.arabic(String.valueOf(until)) + (until <= 2 ? " يوم" : " أيام"), 26, 0xFFFFFFFF, 700);
            t.setPadding(0, dp(6), 0, dp(4));
            card.addView(t);
            card.addView(Ui.text(this, "جهّز ختمة رمضان من الآن، ونذكّرك بوردك كل يوم.", 14, getColor(R.color.on_dark_muted), 400));
            TextView btn = pill("جهّز ختمتي", true);
            btn.setBackground(Ui.shape(goldL, 21, 0, this));
            btn.setTextColor(getColor(R.color.dark));
            btn.setOnClickListener(v -> startActivity(new Intent(this, KhatmaActivity.class)));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
            lp.topMargin = dp(12);
            card.addView(Ui.minH(btn, 42), lp);
            return card;
        }
        card.addView(Ui.iconTitle(this, R.drawable.ic_l_moon, "رمضان كريم · " + Ramadan.ordinal(Ramadan.day()), 13, goldL, 700, goldL));
        if (Adhan.hasLocation(this)) {
            long[] ev = Ramadan.nextEvent(this);
            TextView lbl = Ui.text(this, ev[0] == 1 ? "الإفطار بعد" : "الإمساك بعد", 14, getColor(R.color.on_dark_muted), 400);
            lbl.setGravity(Gravity.CENTER);
            lbl.setPadding(0, dp(10), 0, 0);
            card.addView(lbl);
            Chronometer ch = new Chronometer(this);
            ch.setTextColor(0xFFFFFFFF);
            ch.setTextSize(40);
            ch.setTypeface(Ui.font(this, 700));
            ch.setGravity(Gravity.CENTER);
            ch.setCountDown(true);
            ch.setBase(SystemClock.elapsedRealtime() + (ev[1] - System.currentTimeMillis()));
            ch.setOnChronometerTickListener(c -> { if (c.getBase() <= SystemClock.elapsedRealtime()) render(); });
            ch.start();
            card.addView(ch, new LinearLayout.LayoutParams(-1, -2));
            Calendar today = Calendar.getInstance();
            LinearLayout times = new LinearLayout(this);
            times.setPadding(0, dp(10), 0, 0);
            String[][] cells = {{"الإمساك", Adhan.clock(Ramadan.imsak(this, today))}, {"الإفطار", Adhan.clock(Ramadan.iftar(this, today))}};
            for (int i = 0; i < 2; i++) {
                TextView cell = Ui.text(this, cells[i][0] + "\n" + cells[i][1], 15, i == 1 ? goldL : 0xFFFFFFFF, 700);
                cell.setGravity(Gravity.CENTER);
                cell.setPadding(0, dp(8), 0, dp(8));
                cell.setBackground(Ui.shape(0x14FFFFFF, 14, 0, this));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
                if (i > 0) lp.setMarginStart(dp(8));
                times.addView(cell, lp);
            }
            card.addView(times);
        }
        LinearLayout actions = new LinearLayout(this);
        actions.setPadding(0, dp(12), 0, 0);
        TextView tad = pill("تدبّر اليوم", false);
        tad.setOnClickListener(v -> openWeb(Ramadan.tadabburUrl()));
        actions.addView(Ui.minH(tad, 42), new LinearLayout.LayoutParams(0, -1, 1f));
        TextView kh = pill("ختمة رمضان", true);
        kh.setBackground(Ui.shape(goldL, 21, 0, this));
        kh.setTextColor(getColor(R.color.dark));
        kh.setOnClickListener(v -> startActivity(new Intent(this, KhatmaActivity.class)));
        LinearLayout.LayoutParams lp2 = new LinearLayout.LayoutParams(0, -1, 1f);
        lp2.setMarginStart(dp(8));
        actions.addView(Ui.minH(kh, 42), lp2);
        card.addView(actions);
        return card;
    }

    private View azkarPrompt() {
        int h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
        String title;
        if (h >= 4 && h < 11) title = "حان وقت أذكار الصباح";
        else if (h >= 15 && h < 20) title = "حان وقت أذكار المساء";
        else return null;
        LinearLayout card = new LinearLayout(this);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(dp(14), dp(12), dp(14), dp(12));
        card.setBackground(Ui.shape(getColor(R.color.card), 18, getColor(R.color.line), this));
        ImageView ic = new ImageView(this);
        ic.setImageResource(R.drawable.ic_azkar_t);
        ic.setScaleType(ImageView.ScaleType.CENTER);
        ic.setBackground(Ui.shape(getColor(R.color.chip), 12, 0, this));
        card.addView(ic, new LinearLayout.LayoutParams(dp(40), dp(40)));
        LinearLayout t = new LinearLayout(this);
        t.setOrientation(LinearLayout.VERTICAL);
        t.setPadding(dp(12), 0, dp(12), 0);
        t.addView(Ui.text(this, title, 15, ink, 700));
        TextView s = Ui.text(this, "دقائق تحفظك طوال يومك", 12, muted, 400);
        s.setPadding(0, dp(2), 0, 0);
        t.addView(s);
        card.addView(t, new LinearLayout.LayoutParams(0, -2, 1f));
        TextView go = pill("ابدأ", false);
        card.addView(Ui.minH(go, 38), new LinearLayout.LayoutParams(-2, -2));
        card.setOnClickListener(v -> openWeb(App.HOME + "azkar-morning-evening-ar.html"));
        go.setOnClickListener(v -> openWeb(App.HOME + "azkar-morning-evening-ar.html"));
        return card;
    }

    // ------------------------------------------------------------------ آية اليوم

    private View verseCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(18), dp(14), dp(18), dp(14));
        card.setBackground(Ui.shape(getColor(R.color.ivory), 22, ivoryBorder, this));
        VerseRepo.Verse v = VerseRepo.cached(this);

        LinearLayout head = new LinearLayout(this);
        head.setGravity(Gravity.CENTER_VERTICAL);
        head.addView(Ui.iconTitle(this, R.drawable.ic_star, "آية اليوم", 13, gold, 700, gold), new LinearLayout.LayoutParams(0, -2, 1f));
        if (v != null) head.addView(Ui.text(this, v.ref(), 12, muted, 400));
        card.addView(head);

        TextView verse = new TextView(this);
        verse.setTextColor(ink);
        verse.setGravity(Gravity.CENTER);
        verse.setPadding(0, dp(12), 0, dp(14));
        if (v != null && v.text != null && !v.text.isEmpty()) {
            // نص مجمع الملك فهد بخطه، مع علامة نهاية الآية برقمها كما في المصحف
            verse.setTypeface(QuranText.font(this));
            verse.setLineSpacing(0, 1.25f);
            verse.setText(QuranText.withNumber(v.text, v.ayah));
            verse.setTextSize(v.text.length() < 80 ? 25 : v.text.length() < 180 ? 22 : 19);
        } else {
            verse.setTypeface(Ui.font(this, 500));
            verse.setText("جارٍ تحميل آية اليوم…");
            verse.setTextSize(16);
        }
        card.addView(verse);

        if (v != null) {
            // ثلاثة أزرار في صف واحد: الصورة، النص، التفسير
            LinearLayout btns = new LinearLayout(this);
            View share = Ui.pill(this, R.drawable.ic_image, "صورة", true);
            share.setContentDescription("شارك آية اليوم كصورة");
            share.setOnClickListener(x -> openWeb(v.cardUrl()));
            View shareText = Ui.pill(this, R.drawable.ic_text, "نص", false);
            shareText.setContentDescription("شارك آية اليوم نصًّا");
            shareText.setOnClickListener(x -> {
                try {
                    startActivity(Intent.createChooser(new Intent(Intent.ACTION_SEND).setType("text/plain")
                            .putExtra(Intent.EXTRA_TEXT, Notifier.verseShareText(v)), "شارك آية اليوم"));
                } catch (Exception ignored) { }
            });
            View tafsir = Ui.pill(this, R.drawable.ic_book, "التفسير", false);
            tafsir.setContentDescription("اقرأ تفسير آية اليوم");
            tafsir.setOnClickListener(x -> openWeb(v.tafsirUrl()));
            View[] all = {share, shareText, tafsir};
            for (int i = 0; i < all.length; i++) {
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -1, 1f);
                if (i > 0) lp.setMarginStart(dp(6));
                btns.addView(Ui.minH(all[i], 44), lp);
            }
            card.addView(btns);
        }
        return card;
    }

    // ------------------------------------------------------------------ الأدوات

    private View toolsHeader() {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setPadding(dp(4), 0, dp(4), 0);
        r.addView(Ui.text(this, "أدواتك", 16, ink, 700), new LinearLayout.LayoutParams(0, -2, 1f));
        TextView all = Ui.text(this, "كل الأدوات ←", 13, gold, 700);
        all.setPadding(dp(8), dp(8), 0, dp(8));
        all.setOnClickListener(v -> startActivity(new Intent(this, ToolsActivity.class)));
        r.addView(all);
        return r;
    }

    /** أكثر أربع أدوات استخدامًا؛ الباقي في شاشة «الأدوات» */
    private View toolsRow() {
        Object[][] tools = {
                {"آية لحالك", R.drawable.ic_l_heart, MoodActivity.class},
                {"الأذكار", R.drawable.ic_azkar_t, App.HOME + "azkar-morning-evening-ar.html"},
                {"القبلة", R.drawable.ic_qibla, QiblaActivity.class},
                {"المسبحة", R.drawable.ic_tasbeeh, TasbeehActivity.class},
        };
        LinearLayout row = new LinearLayout(this);
        for (int i = 0; i < tools.length; i++) {
            View tile = ToolsActivity.tile(this, (String) tools[i][0], (Integer) tools[i][1], tools[i][2]);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
            if (i > 0) lp.setMarginStart(dp(8));
            row.addView(tile, lp);
        }
        return row;
    }

    private View bottomNav() {
        return Ui.appNav(this, Ui.NAV_TODAY, idx -> {
            if (idx == Ui.NAV_MUSHAF) openWeb(App.mushaf(this));
            else if (idx == Ui.NAV_LISTEN) openWeb(App.HOME + "quran-reciters-ar.html");
            else if (idx == Ui.NAV_TOOLS) startActivity(new Intent(this, ToolsActivity.class));
        });
    }

    // ------------------------------------------------------------------ أدوات

    private void openWeb(String url) {
        startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url), this, MainActivity.class)
                .putExtra(EXTRA_FROM_HOME, true));
    }

    private TextView pill(String s, boolean primary) {
        TextView t = Ui.text(this, s, 14, primary ? 0xFFFFFFFF : ink, 700);
        t.setGravity(Gravity.CENTER);
        t.setPadding(dp(16), 0, dp(16), 0);
        t.setBackground(primary ? Ui.shape(getColor(R.color.primary), 21, 0, this) : Ui.shape(getColor(R.color.card), 21, getColor(R.color.field_border), this));
        return t;
    }

    private LinearLayout.LayoutParams gap(int top) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.topMargin = dp(top);
        return lp;
    }

    private int dp(int v) { return Ui.dp(this, v); }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {   // أندرويد 12 وأقدم
        moveTaskToBack(true);
    }

    private static boolean webWarm;

    /** تحميل مكتبة WebView مسبقًا (مرة واحدة لكل تشغيل) */
    static void warmWebView(android.content.Context c) {
        if (webWarm) return;
        webWarm = true;
        try { android.webkit.WebSettings.getDefaultUserAgent(c); } catch (Throwable ignored) { }
    }
}
