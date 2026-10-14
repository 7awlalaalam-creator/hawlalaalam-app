package com.hawlalaalam.quran;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * أذكار بعد الصلاة — دون إنترنت، مع عدّاد لكل ذكر (اضغط على الذكر لتعدّه).
 * الآيات من نص مجمع الملك فهد المدمج في التطبيق (QuranText) وبخطه؛
 * والأذكار من الأحاديث الصحيحة بلا تشكيل، مع مصدر كل ذكر.
 */
public class PrayerAzkarActivity extends Activity {

    @Override
    protected void attachBaseContext(android.content.Context base) {
        super.attachBaseContext(Ui.wrap(base));
    }

    /** {النص، العدد، المصدر، ملاحظة} — النص الذي يبدأ بـ «Q:» آيات من المصحف (سورة:من:إلى) */
    private static final Object[][] AZKAR = {
            {"أستغفر الله", 3, "رواه مسلم", ""},
            {"اللهم أنت السلام ومنك السلام، تباركت يا ذا الجلال والإكرام", 1, "رواه مسلم", ""},
            {"لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير، اللهم لا مانع لما أعطيت، "
                    + "ولا معطي لما منعت، ولا ينفع ذا الجد منك الجد", 1, "متفق عليه", ""},
            {"لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير، لا حول ولا قوة إلا بالله، "
                    + "لا إله إلا الله، ولا نعبد إلا إياه، له النعمة وله الفضل وله الثناء الحسن، "
                    + "لا إله إلا الله مخلصين له الدين ولو كره الكافرون", 1, "رواه مسلم", ""},
            {"سبحان الله", 33, "رواه مسلم", ""},
            {"الحمد لله", 33, "رواه مسلم", ""},
            {"الله أكبر", 33, "رواه مسلم", ""},
            {"لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير", 1, "رواه مسلم", "تمام المئة"},
            {"Q:2:255:255", 1, "رواه النسائي في الكبرى", "آية الكرسي"},
            {"Q:112:1:4", 1, "رواه أبو داود والترمذي والنسائي", "سورة الإخلاص · وثلاثًا بعد الفجر والمغرب"},
            {"Q:113:1:5", 1, "رواه أبو داود والترمذي والنسائي", "سورة الفلق · وثلاثًا بعد الفجر والمغرب"},
            {"Q:114:1:6", 1, "رواه أبو داود والترمذي والنسائي", "سورة الناس · وثلاثًا بعد الفجر والمغرب"},
            {"اللهم أعني على ذكرك وشكرك وحسن عبادتك", 1, "رواه أبو داود والنسائي", ""},
            {"لا إله إلا الله وحده لا شريك له، له الملك وله الحمد، يحيي ويميت، وهو على كل شيء قدير", 10,
                    "رواه الترمذي وأحمد", "بعد صلاتي الفجر والمغرب"},
    };

    private LinearLayout list;
    private int[] counts;
    private String[] texts;
    private int ink, muted, gold;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        ink = getColor(R.color.ink);
        muted = getColor(R.color.muted);
        gold = getColor(R.color.gold_deep);
        counts = state != null && state.getIntArray("counts") != null ? state.getIntArray("counts") : new int[AZKAR.length];
        if (counts.length != AZKAR.length) counts = new int[AZKAR.length];

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        col.setPadding(dp(16), dp(14), dp(16), dp(32));

        LinearLayout head = new LinearLayout(this);
        head.setGravity(Gravity.CENTER_VERTICAL);
        head.setPadding(dp(2), dp(4), dp(2), dp(6));
        ImageButton back = new ImageButton(this);
        back.setImageResource(R.drawable.ic_back);
        back.setContentDescription("رجوع");
        back.setBackground(Ui.shape(getColor(R.color.card), 22, getColor(R.color.line), this));
        back.setOnClickListener(v -> finish());
        head.addView(back, new LinearLayout.LayoutParams(dp(44), dp(44)));
        LinearLayout titles = new LinearLayout(this);
        titles.setOrientation(LinearLayout.VERTICAL);
        titles.setPadding(dp(14), 0, dp(8), 0);
        titles.addView(Ui.text(this, "أذكار بعد الصلاة", 22, ink, 700));
        titles.addView(Ui.text(this, "اضغط على الذكر لتعدّه", 13, muted, 400));
        head.addView(titles, new LinearLayout.LayoutParams(0, -2, 1f));
        col.addView(head);

        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams ll = new LinearLayout.LayoutParams(-1, -2);
        ll.topMargin = dp(10);
        col.addView(list, ll);

        TextView reset = Ui.text(this, "ابدأ من جديد", 14, gold, 700);
        reset.setGravity(Gravity.CENTER);
        reset.setPadding(0, dp(16), 0, dp(8));
        reset.setOnClickListener(v -> { counts = new int[AZKAR.length]; render(); });
        col.addView(reset, new LinearLayout.LayoutParams(-1, -2));

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(getColor(R.color.page));
        scroll.addView(col);
        setContentView(scroll);
        Ui.applyInsets(scroll);

        // نص الآيات من ملف المصحف المدمج: يُقرأ أول مرة في خيط خلفي
        texts = new String[AZKAR.length];
        render();
        new Thread(() -> {
            String[] t = new String[AZKAR.length];
            for (int i = 0; i < AZKAR.length; i++) t[i] = resolve(getApplicationContext(), (String) AZKAR[i][0]);
            runOnUiThread(() -> { if (!isFinishing()) { texts = t; render(); } });
        }).start();
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        out.putIntArray("counts", counts);
    }

    /** «Q:سورة:من:إلى» ← نص الآيات بالرسم العثماني مع علامة نهاية كل آية؛ وغيره كما هو */
    private static String resolve(android.content.Context c, String spec) {
        if (!spec.startsWith("Q:")) return spec;
        try {
            String[] p = spec.split(":");
            int s = Integer.parseInt(p[1]), from = Integer.parseInt(p[2]), to = Integer.parseInt(p[3]);
            StringBuilder sb = new StringBuilder();
            for (int a = from; a <= to; a++) {
                String v = QuranText.verse(c, s, a);
                if (v == null) return null;
                if (sb.length() > 0) sb.append(' ');
                sb.append(QuranText.withNumber(v, a));
            }
            return sb.toString();
        } catch (Exception e) {
            return null;
        }
    }

    private void render() {
        list.removeAllViews();
        for (int i = 0; i < AZKAR.length; i++) {
            View card = card(i);
            if (card == null) continue;
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            if (list.getChildCount() > 0) lp.topMargin = dp(10);
            list.addView(card, lp);
        }
    }

    private View card(int i) {
        String spec = (String) AZKAR[i][0];
        boolean quran = spec.startsWith("Q:");
        String text = quran ? texts[i] : spec;
        if (quran && text == null) return null;          // لم يُقرأ النص بعد (أو تعذّرت قراءته)
        int target = (Integer) AZKAR[i][1];
        String source = (String) AZKAR[i][2];
        String note = (String) AZKAR[i][3];
        boolean done = counts[i] >= target;

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(14), dp(16), dp(12));
        card.setBackground(done ? Ui.shape(getColor(R.color.chip), 18, getColor(R.color.ivory_border), this)
                : Ui.shape(getColor(R.color.card), 18, getColor(R.color.line), this));

        if (!note.isEmpty()) {
            TextView n = Ui.text(this, note, 12, gold, 700);
            n.setPadding(0, 0, 0, dp(6));
            card.addView(n);
        }
        TextView t;
        if (quran) {
            t = new TextView(this);
            t.setText(text);
            t.setTypeface(QuranText.font(this));
            t.setTextSize(text.length() > 200 ? 19 : 22);
            t.setTextColor(ink);
            t.setLineSpacing(0, 1.3f);
            t.setGravity(Gravity.CENTER);
        } else {
            t = Ui.text(this, text, 18, ink, 500);
            t.setLineSpacing(Ui.dp(this, 6), 1f);
        }
        card.addView(t, new LinearLayout.LayoutParams(-1, -2));

        LinearLayout foot = new LinearLayout(this);
        foot.setGravity(Gravity.CENTER_VERTICAL);
        foot.setPadding(0, dp(10), 0, 0);
        foot.addView(Ui.text(this, source, 12, muted, 400), new LinearLayout.LayoutParams(0, -2, 1f));
        String countText = done ? "تم ✓"
                : target == 1 ? "مرة واحدة"
                : Adhan.arabic(String.valueOf(counts[i])) + " / " + Adhan.arabic(String.valueOf(target));
        TextView cnt = Ui.text(this, countText, 14, done ? gold : ink, 700);
        cnt.setGravity(Gravity.CENTER);
        cnt.setPadding(dp(12), dp(4), dp(12), dp(4));
        cnt.setBackground(Ui.shape(done ? getColor(R.color.card) : getColor(R.color.chip), 14, 0, this));
        foot.addView(Ui.minH(cnt, 34));
        card.addView(foot);

        card.setContentDescription(text + "، " + countText);
        card.setOnClickListener(v -> {
            if (counts[i] >= target) return;
            counts[i]++;
            boolean finished = counts[i] >= target;
            v.performHapticFeedback(finished && android.os.Build.VERSION.SDK_INT >= 30
                    ? android.view.HapticFeedbackConstants.CONFIRM : android.view.HapticFeedbackConstants.KEYBOARD_TAP);
            int idx = list.indexOfChild(v);
            View fresh = card(i);
            if (idx >= 0 && fresh != null) {
                list.removeViewAt(idx);
                list.addView(fresh, idx, v.getLayoutParams());
            }
        });
        return card;
    }

    private int dp(int v) { return Ui.dp(this, v); }

    /** فتح الشاشة من إشعار الأذان */
    static Intent intent(android.content.Context c) {
        return new Intent(c, PrayerAzkarActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    }
}
