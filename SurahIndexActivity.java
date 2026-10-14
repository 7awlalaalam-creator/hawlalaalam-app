package com.hawlalaalam.quran;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * فهرس المصحف — أصلي ويعمل دون إنترنت (من بيانات التطبيق: QuranText و Khatma).
 * السور أو الأجزاء، بحث باسم السورة أو رقمها أو رقم الصفحة، و«آخر قراءة».
 * الضغط يفتح صفحة المصحف دون إنترنت من حيث تبدأ السورة أو الجزء.
 */
public class SurahIndexActivity extends Activity {

    @Override
    protected void attachBaseContext(android.content.Context base) {
        super.attachBaseContext(Ui.wrap(base));
    }

    private LinearLayout list;
    private TextView tabSurahs, tabJuz;
    private boolean juzMode;
    private String query = "";
    private int ink, muted, gold;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        ink = getColor(R.color.ink);
        muted = getColor(R.color.muted);
        gold = getColor(R.color.gold_deep);
        if (state != null) juzMode = state.getBoolean("juz", false);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(getColor(R.color.page));
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.VERTICAL);
        top.setPadding(dp(16), dp(12), dp(16), dp(6));

        LinearLayout head = new LinearLayout(this);
        head.setGravity(Gravity.CENTER_VERTICAL);
        ImageButton back = new ImageButton(this);
        back.setImageResource(R.drawable.ic_back);
        back.setContentDescription("رجوع");
        back.setBackground(Ui.shape(getColor(R.color.card), 22, getColor(R.color.line), this));
        back.setOnClickListener(v -> finish());
        head.addView(back, new LinearLayout.LayoutParams(dp(44), dp(44)));
        TextView title = Ui.text(this, "فهرس المصحف", 22, ink, 700);
        title.setPadding(dp(14), 0, dp(8), 0);
        head.addView(title, new LinearLayout.LayoutParams(0, -2, 1f));
        TextView offline = Ui.text(this, "دون إنترنت", 12, getColor(R.color.gold_key), 700);
        offline.setPadding(dp(10), dp(4), dp(10), dp(4));
        offline.setBackground(Ui.shape(getColor(R.color.chip), 14, 0, this));
        head.addView(offline);
        top.addView(head);

        EditText search = new EditText(this);
        search.setHint("اسم السورة، رقمها، أو رقم الصفحة");
        search.setSingleLine(true);
        search.setTextSize(15);
        search.setTypeface(Ui.font(this, 500));
        search.setTextColor(ink);
        search.setHintTextColor(muted);
        search.setPadding(dp(14), 0, dp(14), 0);
        search.setBackground(Ui.shape(getColor(R.color.card), 14, getColor(R.color.line), this));
        search.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH);
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int a, int b, int c) { }
            @Override public void onTextChanged(CharSequence s, int a, int b, int c) { }
            @Override public void afterTextChanged(Editable e) {
                query = e.toString().trim();
                render();
            }
        });
        LinearLayout.LayoutParams sl = new LinearLayout.LayoutParams(-1, -2);
        sl.topMargin = dp(12);
        top.addView(Ui.minH(search, 48), sl);

        LinearLayout tabs = new LinearLayout(this);
        tabs.setPadding(dp(4), dp(4), dp(4), dp(4));
        tabs.setBackground(Ui.shape(getColor(R.color.chip), 14, 0, this));
        tabSurahs = tab("السور");
        tabJuz = tab("الأجزاء");
        tabSurahs.setOnClickListener(v -> { juzMode = false; render(); });
        tabJuz.setOnClickListener(v -> { juzMode = true; render(); });
        tabs.addView(Ui.minH(tabSurahs, 40), new LinearLayout.LayoutParams(0, -2, 1f));
        LinearLayout.LayoutParams jl = new LinearLayout.LayoutParams(0, -2, 1f);
        jl.setMarginStart(dp(4));
        tabs.addView(Ui.minH(tabJuz, 40), jl);
        LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(-1, -2);
        tl.topMargin = dp(10);
        top.addView(tabs, tl);
        root.addView(top);

        ScrollView scroll = new ScrollView(this);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(dp(16), dp(4), dp(16), dp(20));
        scroll.addView(list);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));
        root.addView(Ui.appNav(this, Ui.NAV_MUSHAF, this::onNav));

        setContentView(root);
        Ui.applyInsets(root, false);
        Ui.applyInsets(scroll);
        render();
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        out.putBoolean("juz", juzMode);
    }

    private TextView tab(String s) {
        TextView t = Ui.text(this, s, 14, ink, 700);
        t.setGravity(Gravity.CENTER);
        return t;
    }

    private void render() {
        boolean searching = !query.isEmpty();
        styleTab(tabSurahs, !juzMode || searching);
        styleTab(tabJuz, juzMode && !searching);
        list.removeAllViews();
        if (!searching) {
            View last = lastRead();
            if (last != null) add(last, 8);
        }
        if (searching) renderSearch();
        else if (juzMode) for (int j = 1; j <= 30; j++) add(juzRow(j), 0);
        else for (int s = 1; s <= 114; s++) add(surahRow(s), 0);
    }

    private void styleTab(TextView t, boolean on) {
        t.setBackground(on ? Ui.shape(getColor(R.color.card), 10, 0, this) : null);
        t.setTextColor(on ? ink : muted);
        t.setSelected(on);
    }

    private void add(View v, int topDp) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.topMargin = dp(topDp);
        list.addView(v, lp);
    }

    // ------------------------------------------------------------------ البحث

    /** يوحّد الحروف للبحث دون تشكيل: الهمزات والتاء المربوطة والألف المقصورة */
    static String normalize(String s) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (ch >= 'ً' && ch <= 'ٟ' || ch == 'ٰ' || ch == 'ـ') continue;   // تشكيل وتطويل
            if (ch == 'أ' || ch == 'إ' || ch == 'آ' || ch == 'ٱ') ch = 'ا';
            else if (ch == 'ة') ch = 'ه';
            else if (ch == 'ى') ch = 'ي';
            else if (ch >= '٠' && ch <= '٩') ch = (char) ('0' + (ch - '٠'));
            b.append(ch);
        }
        return b.toString().trim();
    }

    private void renderSearch() {
        String q = normalize(query);
        if (q.startsWith("سوره ")) q = q.substring(5).trim();
        int n = -1;
        try { n = Integer.parseInt(q); } catch (NumberFormatException ignored) { }
        int found = 0;
        if (n >= 1 && n <= 114) { add(surahRow(n), 0); found++; }
        if (n >= 1 && n <= Khatma.PAGES) { add(pageRow(n), found > 0 ? 8 : 0); found++; }
        if (n < 0 && !q.isEmpty()) {
            String qq = q.startsWith("ال") && q.length() > 2 ? q.substring(2) : q;
            // المطابقة التامة أولًا («ق» ← سورة ق)، ثم ما يحتوي الكلمة
            boolean[] shown = new boolean[115];
            for (int s = 1; s <= 114; s++) {
                String name = normalize(QuranText.NAMES[s - 1]);
                String bare = name.startsWith("ال") && name.length() > 2 ? name.substring(2) : name;
                if (name.equals(q) || bare.equals(qq)) { add(surahRow(s), 0); found++; shown[s] = true; }
            }
            for (int s = 1; s <= 114; s++) {
                if (shown[s]) continue;
                String name = normalize(QuranText.NAMES[s - 1]);
                if (name.contains(q) || name.contains(qq)) { add(surahRow(s), 0); found++; }
            }
        }
        if (found == 0) {
            TextView t = Ui.text(this, "لا توجد سورة بهذا الاسم. جرّب جزءًا من الاسم أو رقم السورة أو الصفحة.", 14, muted, 400);
            t.setGravity(Gravity.CENTER);
            t.setPadding(dp(8), dp(28), dp(8), dp(8));
            add(t, 0);
        }
    }

    // ------------------------------------------------------------------ الصفوف

    private View lastRead() {
        String url = Reading.lastUrl(this);
        if (url == null) return null;
        LinearLayout card = new LinearLayout(this);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(dp(14), dp(12), dp(14), dp(12));
        card.setBackground(new Ui.PatternDrawable(this, getColor(R.color.dark), 16));
        android.widget.ImageView ic = Ui.icon(this, R.drawable.ic_mushaf_t, 0xFFE9D9B8, 22);
        ic.setScaleType(android.widget.ImageView.ScaleType.CENTER);
        ic.setBackground(Ui.shape(0x26C9A876, 12, 0, this));
        card.addView(ic, new LinearLayout.LayoutParams(dp(40), dp(40)));
        LinearLayout t = new LinearLayout(this);
        t.setOrientation(LinearLayout.VERTICAL);
        t.setPadding(dp(12), 0, dp(8), 0);
        t.addView(Ui.text(this, "آخر قراءة", 12, 0xFFE9D9B8, 700));
        TextView tt = Ui.text(this, Reading.lastTitle(this), 16, 0xFFFFFFFF, 700);
        tt.setMaxLines(1);
        tt.setEllipsize(android.text.TextUtils.TruncateAt.END);
        t.addView(tt);
        card.addView(t, new LinearLayout.LayoutParams(0, -2, 1f));
        card.addView(Ui.text(this, "أكمل ←", 13, 0xFFE9D9B8, 700));
        card.setContentDescription("آخر قراءة: " + Reading.lastTitle(this));
        card.setOnClickListener(v -> open(url));
        return Ui.minH(card, 56);
    }

    private View surahRow(int s) {
        int ayat = QuranText.COUNTS[s - 1];
        int page = Khatma.SURAH_START[s - 1];
        String meta = num(ayat) + (ayat >= 3 && ayat <= 10 ? " آيات" : " آية") + " · الجزء " + num(Khatma.juzOf(page));
        return row(num(s), QuranText.NAMES[s - 1], meta, page, "سورة " + QuranText.NAMES[s - 1]);
    }

    private View juzRow(int j) {
        int page = Khatma.JUZ_START[j - 1];
        String meta = "يبدأ في " + Khatma.where(page).replaceFirst(" · الجزء .*$", "");
        return row(num(j), "الجزء " + num(j), meta, page, "الجزء " + num(j));
    }

    private View pageRow(int p) {
        return row(num(p), "صفحة " + num(p), Khatma.where(p), p, "صفحة " + num(p));
    }

    private View row(String badge, String name, String meta, int page, String label) {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setPadding(dp(2), dp(10), dp(2), dp(10));

        FrameLayout star = new FrameLayout(this);
        int edge = getColor(R.color.gold);
        for (int k = 0; k < 2; k++) {
            View sq = new View(this);
            sq.setBackground(Ui.shape(0, 3, edge, this));
            sq.setRotation(k * 45f);
            FrameLayout.LayoutParams sp = new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER);
            star.addView(sq, sp);
        }
        TextView b = Ui.text(this, badge, badge.length() > 2 ? 10 : 12, getColor(R.color.gold_key), 700);
        b.setGravity(Gravity.CENTER);
        star.addView(b, new FrameLayout.LayoutParams(-1, -1));
        r.addView(star, new LinearLayout.LayoutParams(dp(40), dp(40)));

        LinearLayout t = new LinearLayout(this);
        t.setOrientation(LinearLayout.VERTICAL);
        t.setPadding(dp(12), 0, dp(8), 0);
        t.addView(Ui.text(this, name, 16, ink, 700));
        TextView m = Ui.text(this, meta, 12, muted, 400);
        m.setMaxLines(1);
        m.setEllipsize(android.text.TextUtils.TruncateAt.END);
        t.addView(m);
        r.addView(t, new LinearLayout.LayoutParams(0, -2, 1f));
        r.addView(Ui.text(this, "ص " + num(page), 13, muted, 500));

        r.setBackground(getDrawable(android.R.drawable.list_selector_background));
        r.setContentDescription(label + "، " + meta + "، صفحة " + num(page));
        r.setOnClickListener(v -> open(Khatma.pageUrl(page)));

        LinearLayout wrap = new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.addView(Ui.minH(r, 60));
        wrap.addView(Ui.divider(this));
        return wrap;
    }

    private String num(int n) { return Adhan.arabic(String.valueOf(n)); }

    private void open(String url) {
        startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url), this, MainActivity.class)
                .putExtra(HomeActivity.EXTRA_FROM_HOME, true));
        finish();
    }

    private void onNav(int idx) {
        if (idx == Ui.NAV_TODAY) {
            startActivity(new Intent(this, HomeActivity.class).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
            finish();
        } else if (idx == Ui.NAV_MUSHAF) {
            open(App.mushaf(this));
        } else if (idx == Ui.NAV_LISTEN) {
            open(App.HOME + "quran-reciters-ar.html");
        } else if (idx == Ui.NAV_TOOLS) {
            startActivity(new Intent(this, ToolsActivity.class));
            finish();
        }
    }

    private int dp(int v) { return Ui.dp(this, v); }
}
