package com.hawlalaalam.quran;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Calendar;

/**
 * شاشة «الأدوات»: كل ما خرج من «اليوم» مرتّبًا في مجموعات —
 * سلسلة الأيام، أدوات القرآن، الصلاة والذكر، لقلبك، والصدقة الجارية.
 */
public class ToolsActivity extends Activity {

    @Override
    protected void attachBaseContext(android.content.Context base) {
        super.attachBaseContext(Ui.wrap(base));
    }

    private LinearLayout col;
    private int ink, muted, gold;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        ink = getColor(R.color.ink);
        muted = getColor(R.color.muted);
        gold = getColor(R.color.gold_deep);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(getColor(R.color.page));
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);

        ScrollView scroll = new ScrollView(this);
        col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(16), dp(14), dp(16), dp(24));
        scroll.addView(col);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));
        root.addView(Ui.appNav(this, Ui.NAV_TOOLS, this::onNav));

        setContentView(root);
        Ui.applyInsets(root, false);
        Ui.applyInsets(scroll);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (Ui.isNight(this) != Ui.isNight(Ui.wrap(getApplicationContext()))) { recreate(); return; }
        render();                                   // السلسلة تتحدّث بعد القراءة
    }

    private void render() {
        col.removeAllViews();
        col.addView(header());
        col.addView(streakCard(), gap(14));

        col.addView(section("القرآن"), gap(20));
        col.addView(grid(new Object[][]{
                {"الفهرس", R.drawable.ic_mushaf_t, SurahIndexActivity.class},
                {"ختمتي", R.drawable.ic_khatma_t, KhatmaActivity.class},
                {"المحمّلة", R.drawable.ic_listen_t, DownloadsActivity.class},
                {"الترجمات", R.drawable.ic_globe_t, App.HOME + "languages.html"},
        }), gap(8));

        col.addView(section("الصلاة والذكر"), gap(20));
        col.addView(grid(new Object[][]{
                {"المواقيت", R.drawable.ic_prayer_t, App.HOME + "prayer-times-ar.html"},
                {"القبلة", R.drawable.ic_qibla, QiblaActivity.class},
                {"الأذكار", R.drawable.ic_azkar_t, App.HOME + "azkar-morning-evening-ar.html"},
                {"المسبحة", R.drawable.ic_tasbeeh, TasbeehActivity.class},
                {"أذكار الصلاة", R.drawable.ic_azkar_t, PrayerAzkarActivity.class},
                {"الموقع", R.drawable.ic_book, App.HOME},
        }), gap(8));

        col.addView(section("لقلبك والتطبيق"), gap(20));
        col.addView(grid(new Object[][]{
                {"آية لحالك", R.drawable.ic_l_heart, MoodActivity.class},
                {"الإهداء", R.drawable.ic_heart, DedicateActivity.class},
                {"التنبيهات", R.drawable.ic_l_bell,
                        new Intent(this, SettingsActivity.class).putExtra(SettingsActivity.EXTRA_NOTIF_ONLY, true)},
                {"الإعدادات", R.drawable.ic_nav_settings, SettingsActivity.class},
        }), gap(8));

        col.addView(dedicateCard(), gap(20));
    }

    private View header() {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        TextView t = Ui.text(this, "الأدوات", 24, ink, 700);
        t.setPadding(dp(4), dp(4), dp(4), dp(4));
        r.addView(t, new LinearLayout.LayoutParams(0, -2, 1f));
        ImageView st = Ui.icon(this, R.drawable.ic_nav_settings, ink, 22);
        st.setScaleType(ImageView.ScaleType.CENTER);
        st.setBackground(Ui.shape(getColor(R.color.card), 14, getColor(R.color.line), this));
        st.setContentDescription("الإعدادات");
        st.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        st.setOnClickListener(v -> startActivity(new Intent(this, SettingsActivity.class)));
        r.addView(st, new LinearLayout.LayoutParams(dp(44), dp(44)));
        return r;
    }

    private TextView section(String s) {
        TextView t = Ui.text(this, s, 14, muted, 700);
        t.setPadding(dp(4), 0, dp(4), 0);
        return t;
    }

    /** شبكة بأربع خانات في كل صف؛ الصف الأخير الناقص يُكمَّل بفراغ حتى تبقى الخانات بنفس العرض */
    private View grid(Object[][] tools) {
        LinearLayout g = new LinearLayout(this);
        g.setOrientation(LinearLayout.VERTICAL);
        for (int start = 0; start < tools.length; start += 4) {
            LinearLayout row = new LinearLayout(this);
            for (int k = 0; k < 4; k++) {
                int i = start + k;
                View cell = i < tools.length ? tile(this, (String) tools[i][0], (Integer) tools[i][1], tools[i][2]) : new View(this);
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
                if (k > 0) lp.setMarginStart(dp(8));
                row.addView(cell, lp);
            }
            LinearLayout.LayoutParams rl = new LinearLayout.LayoutParams(-1, -2);
            if (start > 0) rl.topMargin = dp(8);
            g.addView(row, rl);
        }
        return g;
    }

    /** خانة أداة موحّدة (تُستخدم في «اليوم» و«الأدوات»): أيقونة ذهبية واسم في سطر واحد */
    static View tile(Activity a, String label, int icon, Object target) {
        LinearLayout tile = new LinearLayout(a);
        tile.setOrientation(LinearLayout.VERTICAL);
        tile.setGravity(Gravity.CENTER);
        tile.setPadding(0, Ui.dp(a, 14), 0, Ui.dp(a, 12));
        tile.setBackground(Ui.shape(a.getColor(R.color.card), 16, a.getColor(R.color.line), a));
        tile.setContentDescription(label);
        ImageView ic = Ui.icon(a, icon, a.getColor(R.color.gold_deep), 26);
        tile.addView(ic);
        TextView l = Ui.text(a, label, 12, a.getColor(R.color.ink), 700);
        l.setPadding(Ui.dp(a, 4), Ui.dp(a, 8), Ui.dp(a, 4), 0);
        // في القائمة العمودية يأخذ النص عرض الخانة كاملًا، فبدون التوسيط يلتصق بطرفها
        l.setGravity(Gravity.CENTER_HORIZONTAL);
        l.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
        l.setSingleLine(true);
        l.setEllipsize(android.text.TextUtils.TruncateAt.END);
        l.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        tile.addView(l, new LinearLayout.LayoutParams(-1, -2));
        tile.setOnClickListener(v -> {
            if (target instanceof Intent) {
                a.startActivity(new Intent((Intent) target));
            } else if (target instanceof String) {
                a.startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse((String) target), a, MainActivity.class)
                        .putExtra(HomeActivity.EXTRA_FROM_HOME, true));
            } else {
                a.startActivity(new Intent(a, (Class<?>) target));
            }
        });
        return Ui.minH(tile, 84);
    }

    private View streakCard() {
        int n = Reading.streak(this);
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(14), dp(16), dp(14));
        card.setBackground(Ui.shape(getColor(R.color.card), 18, getColor(R.color.line), this));
        String title = n == 0 ? "ابدأ سلسلتك اليوم مع القرآن"
                : n == 1 ? "يوم واحد مع القرآن" : n == 2 ? "يومان متتاليان مع القرآن"
                : Ui.arabicNum(n) + (n <= 10 ? " أيام متتالية مع القرآن" : " يومًا متتاليًا مع القرآن");
        card.addView(Ui.text(this, title, 16, ink, 700));
        TextView s = Ui.text(this, Reading.readOn(this, Calendar.getInstance()) ? "أحسنت، قرأت اليوم ✓" : "اقرأ ولو آية اليوم لتكملها", 12, muted, 400);
        s.setPadding(0, dp(4), 0, dp(10));
        card.addView(s);
        LinearLayout dots = new LinearLayout(this);
        String[] dn = {"ح", "ن", "ث", "ر", "خ", "ج", "س"}; // الأحد..السبت
        Calendar c = Calendar.getInstance();
        c.add(Calendar.DAY_OF_MONTH, -6);
        for (int i = 0; i < 7; i++) {
            boolean on = Reading.readOn(this, c);
            boolean today = i == 6;
            LinearLayout d = new LinearLayout(this);
            d.setOrientation(LinearLayout.VERTICAL);
            d.setGravity(Gravity.CENTER);
            TextView dot = new TextView(this);
            dot.setBackground(Ui.shape(on ? gold : getColor(R.color.chip), 14, today ? gold : 0, this));
            dot.setText(on ? "✓" : "");
            dot.setTextColor(0xFFFFFFFF);
            dot.setGravity(Gravity.CENTER);
            d.addView(dot, new LinearLayout.LayoutParams(dp(28), dp(28)));
            TextView lbl = Ui.text(this, dn[c.get(Calendar.DAY_OF_WEEK) - 1], 11, today ? gold : muted, today ? 700 : 400);
            lbl.setPadding(0, dp(4), 0, 0);
            lbl.setGravity(Gravity.CENTER_HORIZONTAL);
            lbl.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
            d.addView(lbl, new LinearLayout.LayoutParams(-1, -2));
            dots.addView(d, new LinearLayout.LayoutParams(0, -2, 1f));
            c.add(Calendar.DAY_OF_MONTH, 1);
        }
        card.addView(dots);
        return card;
    }

    private View dedicateCard() {
        LinearLayout card = new LinearLayout(this);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(dp(16), dp(14), dp(16), dp(14));
        card.setBackground(new Ui.PatternDrawable(this, getColor(R.color.dark), 18));
        ImageView ic = new ImageView(this);
        ic.setImageResource(R.drawable.ic_heart);
        card.addView(ic, new LinearLayout.LayoutParams(dp(30), dp(30)));
        LinearLayout t = new LinearLayout(this);
        t.setOrientation(LinearLayout.VERTICAL);
        t.setPadding(dp(12), 0, dp(12), 0);
        t.addView(Ui.text(this, "اجعلها صدقة جارية", 16, 0xFFFFFFFF, 700));
        TextView s = Ui.text(this, "شارك التطبيق باسم من تحب، حيًّا أو ميتًا", 12, getColor(R.color.on_dark_muted), 400);
        s.setPadding(0, dp(3), 0, 0);
        t.addView(s);
        card.addView(t, new LinearLayout.LayoutParams(0, -2, 1f));
        ImageView chev = new ImageView(this);
        chev.setImageResource(R.drawable.ic_chevron);
        card.addView(chev, new LinearLayout.LayoutParams(dp(22), dp(22)));
        card.setContentDescription("اجعلها صدقة جارية: شارك التطبيق باسم من تحب");
        card.setOnClickListener(v -> startActivity(new Intent(this, DedicateActivity.class)));
        return card;
    }

    private void onNav(int idx) {
        if (idx == Ui.NAV_TODAY) {
            startActivity(new Intent(this, HomeActivity.class).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
            finish();
        } else if (idx == Ui.NAV_MUSHAF || idx == Ui.NAV_LISTEN) {
            String url = idx == Ui.NAV_MUSHAF ? App.mushaf(this) : App.HOME + "quran-reciters-ar.html";
            startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url), this, MainActivity.class)
                    .putExtra(HomeActivity.EXTRA_FROM_HOME, true));
            finish();
        }
    }

    private LinearLayout.LayoutParams gap(int top) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.topMargin = dp(top);
        return lp;
    }

    private int dp(int v) { return Ui.dp(this, v); }
}
