package com.hawlalaalam.quran;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * جولة في مميزات التطبيق: تظهر مرة بعد كل تحديث يضيف مميزات (TOUR_VERSION)،
 * وتُفتح متى شاء القارئ من الإعدادات. شرائح بسيطة: أيقونة، عنوان، شرح، وشارة «جديد» أو «مطوّر».
 */
public class FeaturesActivity extends Activity {

    /** ارفع الرقم عند إضافة مميزات جديدة إلى الجولة، فتظهر مرة أخرى للجميع بعد التحديث */
    static final int TOUR_VERSION = 4;

    static boolean shouldShow(Context c) {
        return App.prefs(c).getBoolean("welcomed", false) && App.prefs(c).getInt("tour_v", 0) < TOUR_VERSION;
    }

    /** {عنوان، شرح، أيقونة، شارة (0 بلا، 1 جديد، 2 مطوّر)} */
    private static final Object[][] SLIDES = {
            {"أهلًا بك في التحديث الجديد",
                    "جولة سريعة في مميزات «حول العالم | القرآن الكريم»: ما أضفناه حديثًا، وما كان موجودًا وقد لا تعرفه.\nاسحب أو اضغط «التالي».",
                    R.drawable.ic_mushaf_t, 0},
            {"«اليوم» بترتيب جديد",
                    "كل ما تحتاجه بلا تشتيت:\n\n• بطاقة واحدة «أكمل القراءة» ومعها تقدّم ختمتك وورد اليوم.\n• الصلاة القادمة في أعلى الشاشة.\n• الشريط السفلي: اليوم، المصحف، الاستماع، الأدوات.\n• «الإعدادات» من الزر أعلى «اليوم» أو من «الأدوات».\n• فهرس السور والأجزاء يعمل دون إنترنت، مع البحث بالاسم أو الرقم.",
                    R.drawable.ic_nav_more, 1},
            {"إشعارات أوضح",
                    "• آية اليوم تصلك صورةً بخط المجمع جاهزة للمشاركة.\n• إشعار الورد يُظهر تقدّمك، ومعه زر «ذكّرني بعد ساعة».\n• إشعار الأذان يذكر الصلاة التالية، ومعه زر «أذكار بعد الصلاة».\n• كل التنبيهات في مكان واحد: «الأدوات» ← «التنبيهات».",
                    R.drawable.ic_l_bell, 1},
            {"المصحف بأسطر مصحف المدينة",
                    "كل صفحة بأسطرها الخمسة عشر كما في المصحف المطبوع، بخط مجمع الملك فهد وعلامات الآيات، داخل إطار مزخرف، مع رقم الصفحة والجزء واسم السورة.\n\n• يعمل دون إنترنت.\n• اسحب يمينًا ويسارًا للتنقل، أو اختر السورة أو الصفحة من الأعلى.\n• افتحه من «المصحف» في الشريط السفلي، فيفتح من حيث توقفت.",
                    R.drawable.ic_mushaf_t, 1},
            {"اضغط على أي آية",
                    "في صفحة المصحف اضغط على الآية فتظهر لك:\n\n• التفسير الميسر — دون إنترنت.\n• الاستماع من هذه الآية، وتُظلَّل الآية أثناء التلاوة.\n• النسخ.\n• المشاركة كصورة مزخرفة بخط المجمع.\n• علامة وملاحظة.",
                    R.drawable.ic_mushaf_t, 1},
            {"العلامات والبحث",
                    "• 🔖 العلامات: احفظ مواضعك (ورد، حفظ، تدبّر) مع ملاحظة، وارجع إليها بضغطة.\n• 🔍 البحث: ابحث بكلمة أو جزء من آية دون إنترنت ودون الحاجة إلى التشكيل، وانتقل إلى الآية في صفحتها.",
                    R.drawable.ic_mushaf_t, 1},
            {"ختمتي: خطة على مقاسك",
                    "اختر المدة (من أسبوع إلى سنة، أو حتى آخر رمضان) أو الورد اليومي، ومن أين تبدأ، وأيام الراحة.\n\n• ترى أين وصلت، وهل أنت متقدّم أو متأخر.\n• إن فاتك يوم: يُوزَّع الباقي أو يُمدَّد الموعد، كما تختار.\n• تُحتسب الصفحة حين تقرؤها فعلًا، لا بمجرد فتحها.",
                    R.drawable.ic_khatma_t, 2},
            {"تذكير يصلك في وقته",
                    "تذكير الورد بعد الفجر أو العصر أو العشاء، أو في وقت تختاره، مع تذكير ثانٍ لطيف إن لم تُتمّ وردك. ولا يصلك تذكير إن أتممته.\n\nومعه: الأذان ومواقيت الصلاة حسب مدينتك، وأذكار الصباح والمساء.",
                    R.drawable.ic_clock, 2},
            {"الاستماع والتلاوات المحمّلة",
                    "استمع لقرّائك المفضّلين، وحمّل السور للاستماع دون إنترنت من صفحة القارئ («⬇ تحميل»)، وتجدها كلها في «المحمّلة».",
                    R.drawable.ic_listen_t, 0},
            {"أدوات يومية",
                    "• القبلة: بوصلة تعمل دون إنترنت.\n• المسبحة الإلكترونية.\n• آية لحالك: اختر شعورك فتأتيك آية تواسيك وتشاركها كصورة.\n• الترجمات بلغات متعددة.",
                    R.drawable.ic_qibla, 0},
            {"اجعلها صدقة جارية",
                    "شارك التطبيق باسم من تحب، حيًّا أو ميتًا، ليصل القرآن إلى غيرك صدقةً عنه.\n\nوأضف إلى شاشة جوالك ويدجت: آية اليوم، ومواقيت الصلاة، وختمتي، ورمضان.",
                    R.drawable.ic_l_heart, 0},
            {"مريح لعينيك",
                    "• الوضع الليلي صار شاملًا: صفحات الموقع والمصحف والنوافذ كلها داكنة ونصوصها واضحة.\n• «حجم الخط» من الإعدادات يكبّر خط المصحف أيضًا.\n• الأرقام موحّدة بالعربية.",
                    R.drawable.ic_nav_today, 2},
    };

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(Ui.wrap(base));
    }

    private int index;
    private LinearLayout slide, dots;
    private Button next, back;
    private float downX;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        App.prefs(this).edit().putInt("tour_v", TOUR_VERSION).apply();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        root.setBackgroundColor(getColor(R.color.page));
        root.setPadding(dp(20), dp(16), dp(20), dp(20));

        TextView skip = Ui.text(this, "تخطٍّ", 15, getColor(R.color.muted), 500);
        skip.setPadding(dp(8), dp(8), dp(8), dp(8));
        skip.setOnClickListener(v -> finish());
        LinearLayout top = new LinearLayout(this);
        top.setGravity(Gravity.START);
        top.addView(skip);
        root.addView(top);

        ScrollView sv = new ScrollView(this);
        sv.setFillViewport(true);
        slide = new LinearLayout(this);
        slide.setOrientation(LinearLayout.VERTICAL);
        slide.setGravity(Gravity.CENTER_HORIZONTAL);
        sv.addView(slide);
        sv.setOnTouchListener((v, e) -> {
            if (e.getAction() == MotionEvent.ACTION_DOWN) downX = e.getX();
            else if (e.getAction() == MotionEvent.ACTION_UP) {
                float dx = e.getX() - downX;
                if (Math.abs(dx) > dp(70)) { show(index + (dx > 0 ? 1 : -1)); return true; }   // عربي: السحب يمينًا = التالي
            }
            return false;
        });
        root.addView(sv, new LinearLayout.LayoutParams(-1, 0, 1f));

        dots = new LinearLayout(this);
        dots.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams dl = new LinearLayout.LayoutParams(-1, -2);
        dl.topMargin = dp(12);
        dl.bottomMargin = dp(14);
        root.addView(dots, dl);

        LinearLayout btns = new LinearLayout(this);
        back = Ui.button(this, "السابق", false);
        next = Ui.button(this, "التالي", true);
        back.setOnClickListener(v -> show(index - 1));
        next.setOnClickListener(v -> {
            if (index == SLIDES.length - 1) finish(); else show(index + 1);
        });
        LinearLayout.LayoutParams bl = new LinearLayout.LayoutParams(0, -1, 1f);
        LinearLayout.LayoutParams nl = new LinearLayout.LayoutParams(0, -1, 1.4f);
        nl.setMarginStart(dp(10));
        btns.addView(Ui.minH(back, 52), bl);
        btns.addView(Ui.minH(next, 52), nl);
        root.addView(btns);

        setContentView(root);
        Ui.applyInsets(root);
        show(0);
    }

    private void show(int i) {
        if (i < 0 || i >= SLIDES.length) return;
        index = i;
        Object[] s = SLIDES[i];
        slide.removeAllViews();

        FrameLayout iconBox = new FrameLayout(this);
        iconBox.setBackground(Ui.shape(getColor(R.color.dark), 36, 0, this));
        ImageView icon = new ImageView(this);
        Drawable d = getDrawable((Integer) s[2]);
        if (d != null) { d = d.mutate(); d.setTint(getColor(R.color.gold)); }
        icon.setImageDrawable(d);
        FrameLayout.LayoutParams il = new FrameLayout.LayoutParams(dp(38), dp(38), Gravity.CENTER);
        iconBox.addView(icon, il);
        LinearLayout.LayoutParams bl = new LinearLayout.LayoutParams(dp(76), dp(76));
        bl.topMargin = dp(28);
        slide.addView(iconBox, bl);

        int badge = (Integer) s[3];
        if (badge != 0) {
            TextView b = Ui.text(this, badge == 1 ? "جديد" : "مطوّر", 13, getColor(R.color.dark), 700);
            b.setPadding(dp(14), dp(4), dp(14), dp(4));
            b.setBackground(Ui.shape(getColor(R.color.gold), 14, 0, this));
            LinearLayout.LayoutParams l = new LinearLayout.LayoutParams(-2, -2);
            l.topMargin = dp(16);
            slide.addView(b, l);
        }

        TextView t = Ui.text(this, (String) s[0], 24, getColor(R.color.ink), 700);
        t.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(-1, -2);
        tl.topMargin = dp(16);
        slide.addView(t, tl);

        TextView body = Ui.text(this, (String) s[1], 16, getColor(R.color.ink), 400);
        body.setLineSpacing(0, 1.35f);
        body.setGravity(Gravity.START);
        body.setTextDirection(View.TEXT_DIRECTION_RTL);
        body.setPadding(dp(18), dp(16), dp(18), dp(16));
        body.setBackground(Ui.shape(getColor(R.color.card), 18, getColor(R.color.line), this));
        LinearLayout.LayoutParams bdl = new LinearLayout.LayoutParams(-1, -2);
        bdl.topMargin = dp(18);
        slide.addView(body, bdl);

        dots.removeAllViews();
        for (int k = 0; k < SLIDES.length; k++) {
            View dot = new View(this);
            dot.setBackground(Ui.shape(k == i ? getColor(R.color.gold_deep) : getColor(R.color.line), 4, 0, this));
            LinearLayout.LayoutParams l = new LinearLayout.LayoutParams(k == i ? dp(22) : dp(8), dp(8));
            l.setMarginStart(dp(3));
            l.setMarginEnd(dp(3));
            dots.addView(dot, l);
        }
        back.setVisibility(i == 0 ? View.INVISIBLE : View.VISIBLE);
        next.setText(i == SLIDES.length - 1 ? "ابدأ" : "التالي");
        slide.setContentDescription((i + 1) + " من " + SLIDES.length + ": " + s[0]);
    }

    static void open(Context c) { c.startActivity(new Intent(c, FeaturesActivity.class)); }

    private int dp(int v) { return Ui.dp(this, v); }
}
