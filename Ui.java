package com.hawlalaalam.quran;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.Switch;
import android.widget.TextView;

/** عناصر الواجهة بهوية الموقع (Tajawal، الكحلي والذهبي) */
final class Ui {
    private Ui() { }

    static int dp(Context c, float v) { return Math.round(v * c.getResources().getDisplayMetrics().density); }

    static Typeface font(Context c, int weight) {
        try {
            int id = weight >= 700 ? R.font.tajawal_bold : weight >= 500 ? R.font.tajawal_medium : R.font.tajawal_regular;
            return c.getResources().getFont(id);
        } catch (Exception e) {
            return weight >= 600 ? Typeface.DEFAULT_BOLD : Typeface.DEFAULT;
        }
    }

    static Typeface quran(Context c) {
        try { return c.getResources().getFont(R.font.amiri_quran); } catch (Exception e) { return Typeface.SERIF; }
    }

    static TextView text(Context c, CharSequence s, float sp, int color, int weight) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(color);
        t.setTypeface(font(c, weight));
        // خط Tajawal صعوده المعلن (643) أقل من ارتفاع الهمزة والتشكيل فوق الألف (حتى 1065):
        // بدون الحشوة تُقص الهمزة والضمة والتنوين من أعلى السطر الأول («أكمل» تظهر «اكمل»)
        t.setIncludeFontPadding(true);
        t.setLineSpacing(dp(c, 3), 1f);
        return t;
    }

    static GradientDrawable shape(int fill, float radiusDp, int strokeColor, Context c) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(fill);
        g.setCornerRadius(dp(c, radiusDp));
        if (strokeColor != 0) g.setStroke(dp(c, 1), strokeColor);
        return g;
    }

    /** أيقونة خطية ملوّنة */
    static android.widget.ImageView icon(Context c, int res, int color, int sizeDp) {
        android.widget.ImageView v = new android.widget.ImageView(c);
        v.setImageResource(res);
        v.setColorFilter(color);
        v.setLayoutParams(new LinearLayout.LayoutParams(dp(c, sizeDp), dp(c, sizeDp)));
        v.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        return v;
    }

    /** عنوان بأيقونة بدل الإيموجي */
    static LinearLayout iconTitle(Context c, int res, CharSequence s, float sp, int color, int weight, int iconColor) {
        LinearLayout r = new LinearLayout(c);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setGravity(Gravity.CENTER_VERTICAL);
        android.widget.ImageView i = icon(c, res, iconColor, Math.round(sp + 4));
        r.addView(i);
        TextView t = text(c, s, sp, color, weight);
        t.setPadding(dp(c, 8), 0, 0, 0);
        r.addView(t);
        return r;
    }

    /** الوضع الليلي: 0 تلقائي (يتبع الجوال)، 1 نهاري، 2 ليلي — يُطبَّق فورًا على كل الإصدارات */
    static boolean canSetTheme() { return true; }

    static int themeMode(Context c) { return App.prefs(c).getInt("theme_mode", 0); }

    static void applyTheme(Context c, int mode) {
        App.prefs(c).edit().putInt("theme_mode", mode).apply();
        // الويدجت يتبع مظهر التطبيق المختار
        Context app = c.getApplicationContext();
        PrayerWidget.updateAll(app);
        VerseWidget.updateAll(app);
        // تنظيف أي وضع قديم ثبّتته النسخة السابقة على مستوى النظام
        if (android.os.Build.VERSION.SDK_INT >= 31 && !App.prefs(c).getBoolean("theme_sys_reset", false)) {
            android.app.UiModeManager um = c.getSystemService(android.app.UiModeManager.class);
            if (um != null) um.setApplicationNightMode(android.app.UiModeManager.MODE_NIGHT_AUTO);
            App.prefs(c).edit().putBoolean("theme_sys_reset", true).apply();
        }
    }

    /** يُستدعى من attachBaseContext في كل شاشة أصلية: يفرض الوضع المختار لحظيًا */
    static Context wrap(Context base) {
        int mode = App.prefs(base).getInt("theme_mode", 0);
        if (mode == 0) return base;
        android.content.res.Configuration conf = new android.content.res.Configuration(base.getResources().getConfiguration());
        conf.uiMode = (conf.uiMode & ~android.content.res.Configuration.UI_MODE_NIGHT_MASK)
                | (mode == 2 ? android.content.res.Configuration.UI_MODE_NIGHT_YES : android.content.res.Configuration.UI_MODE_NIGHT_NO);
        return base.createConfigurationContext(conf);
    }

    /** مظهر الويدجت: 0 يتبع الجوال، 1 نهاري، 2 ليلي (نفس اختيار التطبيق) */
    static int widgetMode(Context c) { return themeMode(c); }

    /** هل الويدجت داكن الآن؟ */
    static boolean widgetNight(Context c) {
        int m = themeMode(c);
        if (m != 0) return m == 2;
        return isNight(c.getApplicationContext());
    }

    /**
     * زر كبسولة موحّد: أيقونة خطية + نص في سطر واحد، بنفس المقاس في كل الشاشات.
     * primary: خلفية داكنة ونص أبيض، وإلا خلفية البطاقة بإطار.
     */
    static LinearLayout pill(Context c, int iconRes, String label, boolean primary) {
        LinearLayout b = new LinearLayout(c);
        b.setOrientation(LinearLayout.HORIZONTAL);
        b.setGravity(Gravity.CENTER);
        b.setPadding(dp(c, 10), 0, dp(c, 10), 0);
        int fg = primary ? 0xFFFFFFFF : c.getColor(R.color.ink);
        b.setBackground(primary ? shape(c.getColor(R.color.primary), 23, 0, c)
                : shape(c.getColor(R.color.card), 23, c.getColor(R.color.field_border), c));
        b.setContentDescription(label);
        b.setClickable(true);
        b.setFocusable(true);
        if (iconRes != 0) {
            android.widget.ImageView i = icon(c, iconRes, primary ? c.getColor(R.color.gold) : c.getColor(R.color.gold_deep), 18);
            b.addView(i);
        }
        TextView t = text(c, label, 14, fg, 700);
        t.setMaxLines(1);
        t.setSingleLine(true);
        t.setEllipsize(android.text.TextUtils.TruncateAt.END);
        t.setPadding(iconRes != 0 ? dp(c, 6) : 0, 0, 0, 0);
        b.addView(t, new LinearLayout.LayoutParams(-2, -2));
        return b;
    }

    /** نوافذ الحوار تتبع الوضع المختار (كانت نهارية ثابتة في الوضع الليلي) */
    static int dialogTheme(Context c) {
        return isNight(c) ? android.R.style.Theme_Material_Dialog_Alert : android.R.style.Theme_Material_Light_Dialog_Alert;
    }

    static boolean isNight(Context c) {
        return (c.getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK)
                == android.content.res.Configuration.UI_MODE_NIGHT_YES;
    }

    /** عناصر الشريط السفلي (الإعدادات انتقلت إلى ترويسة «اليوم» وشاشة «الأدوات») */
    static final int NAV_TODAY = 0, NAV_MUSHAF = 1, NAV_LISTEN = 2, NAV_TOOLS = 3;

    /** شريط التطبيق السفلي الموحّد — نفسه في «اليوم» و«الأدوات» وصفحات الموقع داخل التطبيق.
     *  0 اليوم · 1 المصحف · 2 الاستماع · 3 الأدوات */
    static LinearLayout appNav(Context c, int active, java.util.function.IntConsumer onTap) {
        LinearLayout nav = new LinearLayout(c);
        nav.setId(R.id.app_nav);
        nav.setBackgroundColor(c.getColor(R.color.card));
        nav.setElevation(dp(c, 8));
        // اتجاه ثابت من اليمين لليسار ومسافة جانبية صغيرة: لا يخرج «اليوم» عن حافة الشاشة
        // (الشاشات المنحنية وبعض الجوالات تقص الأطراف)
        nav.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        nav.setPadding(dp(c, 8), dp(c, 6), dp(c, 8), dp(c, 6));
        int gold = c.getColor(R.color.gold_deep), muted = c.getColor(R.color.muted);
        String[] labels = {"اليوم", "المصحف", "الاستماع", "الأدوات"};
        int[] icons = {R.drawable.ic_nav_today, R.drawable.ic_nav_mushaf, R.drawable.ic_nav_listen,
                R.drawable.ic_nav_more};
        for (int i = 0; i < labels.length; i++) {
            LinearLayout b = new LinearLayout(c);
            b.setOrientation(LinearLayout.VERTICAL);
            b.setGravity(Gravity.CENTER_HORIZONTAL);
            b.setMinimumWidth(0);
            b.setPadding(0, dp(c, 4), 0, dp(c, 4));
            b.setContentDescription(labels[i]);
            b.setTag(i);
            android.widget.ImageView ic = new android.widget.ImageView(c);
            ic.setImageResource(icons[i]);
            ic.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
            ic.setScaleType(android.widget.ImageView.ScaleType.CENTER);      // الأيقونة ٢٤dp وسط كبسولة أعرض
            LinearLayout.LayoutParams icp = new LinearLayout.LayoutParams(dp(c, 52), dp(c, 28));
            icp.gravity = Gravity.CENTER_HORIZONTAL;
            b.addView(ic, icp);
            TextView l = text(c, labels[i], 11, muted, 500);
            l.setPadding(0, dp(c, 3), 0, 0);
            // التسمية في منتصف العنصر دائمًا (كانت تلتصق بالحافة فتُقص «اليوم» عند طرف الشاشة)
            l.setGravity(Gravity.CENTER);
            l.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
            l.setMaxLines(1);
            l.setEllipsize(android.text.TextUtils.TruncateAt.END);
            b.addView(l, new LinearLayout.LayoutParams(-1, -2));
            final int idx = i;
            b.setOnClickListener(v -> onTap.accept(idx));
            nav.addView(b, new LinearLayout.LayoutParams(0, -2, 1f));
        }
        setNavActive(nav, active);
        return nav;
    }

    /** يحدّث العنصر المميّز في الشريط دون إعادة بنائه */
    static void setNavActive(LinearLayout nav, int active) {
        Context c = nav.getContext();
        int gold = c.getColor(R.color.gold_deep), muted = c.getColor(R.color.muted);
        for (int i = 0; i < nav.getChildCount(); i++) {
            LinearLayout b = (LinearLayout) nav.getChildAt(i);
            boolean on = i == active;
            // العنصر النشط داخل كبسولة خفيفة (مثل الشريط في التصميم الجديد)
            b.getChildAt(0).setBackground(on ? shape(c.getColor(R.color.chip), 14, 0, c) : null);
            ((android.widget.ImageView) b.getChildAt(0)).setColorFilter(on ? gold : muted);
            TextView l = (TextView) b.getChildAt(1);
            l.setTextColor(on ? gold : muted);
            l.setTypeface(Typeface.create(l.getTypeface(), on ? Typeface.BOLD : Typeface.NORMAL));
            b.setSelected(on);
        }
    }

    static LinearLayout card(Context c) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setPadding(dp(c, 16), dp(c, 6), dp(c, 16), dp(c, 6));
        l.setBackground(shape(c.getColor(R.color.card), 18, c.getColor(R.color.line), c));
        return l;
    }

    static Button button(Context c, String s, boolean primary) {
        Button b = new Button(c);
        b.setText(s);
        b.setAllCaps(false);
        b.setStateListAnimator(null);
        b.setTypeface(font(c, primary ? 700 : 500));
        b.setTextSize(primary ? 16 : 14);
        b.setTextColor(primary ? 0xFFFFFFFF : c.getColor(R.color.ink));
        b.setBackground(primary ? shape(c.getColor(R.color.primary), 28, 0, c) : shape(c.getColor(R.color.card), 28, c.getColor(R.color.field_border), c));
        return b;
    }

    static Button chip(Context c, String s) {
        Button b = new Button(c, null, android.R.attr.borderlessButtonStyle);
        b.setText(s);
        b.setAllCaps(false);
        b.setStateListAnimator(null);
        b.setTypeface(font(c, 500));
        b.setTextSize(14);
        b.setTextColor(c.getColor(R.color.gold_key));
        b.setBackground(shape(c.getColor(R.color.ivory), 20, c.getColor(R.color.ivory_border), c));
        b.setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_clock, 0, 0, 0);
        b.setCompoundDrawablePadding(dp(c, 8));
        b.setPadding(dp(c, 14), 0, dp(c, 14), 0);
        b.setMinHeight(0);
        b.setMinimumHeight(0);
        return b;
    }

    static Switch toggle(Context c) {
        Switch s = new Switch(c);
        int[][] states = {{android.R.attr.state_checked}, {}};
        // المفعّل: مقبض ذهبي، المطفأ: أبيض. يتميّز بوضوح في الوضعين حتى لو تغيّر لون المسار
        s.setThumbTintList(new ColorStateList(states, new int[]{0xFFC9A876, 0xFFFFFFFF}));
        s.setTrackTintList(new ColorStateList(states, new int[]{c.getColor(R.color.switch_on), c.getColor(R.color.switch_off)}));
        s.setTrackTintMode(android.graphics.PorterDuff.Mode.SRC_IN);
        return s;
    }

    /** صف: عنوان + وصف + مفتاح */
    static LinearLayout row(Context c, String title, String sub, Switch sw) {
        LinearLayout r = new LinearLayout(c);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setPadding(0, dp(c, 12), 0, dp(c, 12));
        LinearLayout texts = new LinearLayout(c);
        texts.setOrientation(LinearLayout.VERTICAL);
        texts.addView(text(c, title, 16, c.getColor(R.color.ink), 700));
        TextView st = text(c, sub, 13, c.getColor(R.color.muted), 400);
        st.setPadding(0, dp(c, 4), 0, 0);
        texts.addView(st);
        r.addView(texts, new LinearLayout.LayoutParams(0, -2, 1f));
        r.addView(sw);
        return r;
    }

    static View divider(Context c) {
        View v = new View(c);
        v.setBackgroundColor(c.getColor(R.color.divider));
        v.setLayoutParams(new LinearLayout.LayoutParams(-1, dp(c, 1)));
        return v;
    }

    /** «الأربعاء ١٩ ربيع الآخر» */
    static String hijriToday() {
        try {
            android.icu.util.ULocale loc = new android.icu.util.ULocale("ar@calendar=islamic-umalqura");
            android.icu.text.SimpleDateFormat f = new android.icu.text.SimpleDateFormat("EEEE d MMMM", loc);
            return Adhan.arabic(f.format(new java.util.Date()));
        } catch (Throwable t) {
            return "";
        }
    }

    static String hijriShort() {
        try {
            android.icu.util.ULocale loc = new android.icu.util.ULocale("ar@calendar=islamic-umalqura");
            return Adhan.arabic(new android.icu.text.SimpleDateFormat("d MMMM", loc).format(new java.util.Date()));
        } catch (Throwable t) {
            return "";
        }
    }

    /**
     * يحجز مساحة أشرطة النظام ولوحة المفاتيح (أندرويد 15+ يرسم خلفها) مع الإبقاء على حشوة الشاشة الأصلية،
     * ويحدّ عرض المحتوى على الأجهزة اللوحية والوضع الأفقي حتى لا تتمدد البطاقات على الشاشة كلها.
     */
    static void applyInsets(View root) { applyInsets(root, true); }

    /** @param cap يحدّ عرض المحتوى؛ false للشاشات التي فيها شريط سفلي يجب أن يبقى بعرض الشاشة */
    static void applyInsets(View root, boolean cap) {
        final int bl = root.getPaddingLeft(), bt = root.getPaddingTop(), br = root.getPaddingRight(), bb = root.getPaddingBottom();
        final int[] ins = new int[4];
        final int max = cap ? dp(root.getContext(), 680) : Integer.MAX_VALUE / 4;
        final Runnable apply = () -> {
            int w = root.getWidth();
            int side = w > 0 ? Math.max(0, (w - ins[0] - ins[2] - bl - br - max) / 2) : 0;
            int l = bl + ins[0] + side, t = bt + ins[1], r = br + ins[2] + side, b = bb + ins[3];
            if (l != root.getPaddingLeft() || t != root.getPaddingTop() || r != root.getPaddingRight() || b != root.getPaddingBottom())
                root.setPadding(l, t, r, b);
        };
        if (android.os.Build.VERSION.SDK_INT >= 35) {
            root.setOnApplyWindowInsetsListener((v, insets) -> {
                android.graphics.Insets i = insets.getInsets(android.view.WindowInsets.Type.systemBars()
                        | android.view.WindowInsets.Type.displayCutout() | android.view.WindowInsets.Type.ime());
                ins[0] = i.left; ins[1] = i.top; ins[2] = i.right; ins[3] = i.bottom;
                apply.run();
                return android.view.WindowInsets.CONSUMED;
            });
        }
        root.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
            if (r - l != or - ol) v.post(apply);
        });
    }

    /** ارتفاع أدنى بدل الارتفاع الثابت: يكبر الزر مع تكبير خط الجوال بدل أن يُقص نصه */
    static <T extends View> T minH(T v, int minDp) {
        int px = dp(v.getContext(), minDp);
        v.setMinimumHeight(px);
        if (v instanceof TextView) {
            TextView t = (TextView) v;
            t.setMinHeight(px);
            int pad = dp(v.getContext(), 6);
            if (t.getPaddingTop() < pad || t.getPaddingBottom() < pad)
                t.setPadding(t.getPaddingLeft(), Math.max(pad, t.getPaddingTop()), t.getPaddingRight(), Math.max(pad, t.getPaddingBottom()));
        }
        return v;
    }

    /** حجم خط يكبر مع إعداد الجوال حتى حد معين: للخانات الضيقة التي تنكسر فيها الكلمة عند تكبير الخط كثيرًا */
    static void capScale(TextView t, float sp, float maxScale) {
        float s = Math.min(t.getResources().getConfiguration().fontScale, maxScale);
        t.setTextSize(android.util.TypedValue.COMPLEX_UNIT_DIP, sp * s);
    }

    static String arabicNum(long n) { return Adhan.arabic(String.valueOf(n)); }

    /**
     * خلفية داكنة بزخرفة نجوم ثمانية ذهبية خفيفة (هوية «حول العالم»)، بزوايا مستديرة.
     * تُرسم بالكود فتبقى حادة على كل الشاشات ولا تضيف صورًا للتطبيق.
     */
    static final class PatternDrawable extends android.graphics.drawable.Drawable {
        private final android.graphics.Paint fill = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.Paint line = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.Path clip = new android.graphics.Path();
        private final android.graphics.RectF box = new android.graphics.RectF();
        private final float radius, cell;

        PatternDrawable(Context c, int color, float radiusDp) {
            fill.setColor(color);
            line.setStyle(android.graphics.Paint.Style.STROKE);
            line.setStrokeWidth(dp(c, 1));
            line.setColor(0x26C9A876);                       // ذهبي شفاف ١٥٪
            radius = dp(c, radiusDp);
            cell = dp(c, 44);
        }

        @Override
        public void draw(android.graphics.Canvas cv) {
            android.graphics.Rect b = getBounds();
            if (b.isEmpty()) return;
            box.set(b);
            clip.reset();
            clip.addRoundRect(box, radius, radius, android.graphics.Path.Direction.CW);
            cv.save();
            cv.clipPath(clip);
            cv.drawRect(box, fill);
            float half = cell * 0.2f;                        // نصف ضلع المربع
            for (float y = b.top + cell / 2f; y < b.bottom + cell; y += cell) {
                for (float x = b.left + cell / 2f; x < b.right + cell; x += cell) {
                    cv.drawRect(x - half, y - half, x + half, y + half, line);
                    cv.save();
                    cv.rotate(45, x, y);
                    cv.drawRect(x - half, y - half, x + half, y + half, line);
                    cv.restore();
                }
            }
            cv.restore();
        }

        @Override public void setAlpha(int a) { fill.setAlpha(a); }
        @Override public void setColorFilter(android.graphics.ColorFilter f) { fill.setColorFilter(f); }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }

        @Override
        public void getOutline(android.graphics.Outline o) {
            o.setRoundRect(getBounds(), radius);
        }
    }

    /** حلقة تقدّم (الختمة): مسار خافت وقوس ذهبي */
    static final class Ring extends View {
        private final android.graphics.Paint track = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.Paint arc = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.RectF oval = new android.graphics.RectF();
        private float fraction;

        Ring(Context c, int trackColor, int arcColor) {
            super(c);
            float w = dp(c, 7);
            for (android.graphics.Paint p : new android.graphics.Paint[]{track, arc}) {
                p.setStyle(android.graphics.Paint.Style.STROKE);
                p.setStrokeWidth(w);
                p.setStrokeCap(android.graphics.Paint.Cap.ROUND);
            }
            track.setColor(trackColor);
            arc.setColor(arcColor);
        }

        void setFraction(float f) {
            fraction = Math.max(0f, Math.min(1f, f));
            invalidate();
        }

        @Override
        protected void onDraw(android.graphics.Canvas cv) {
            float inset = track.getStrokeWidth() / 2f + 1;
            oval.set(inset, inset, getWidth() - inset, getHeight() - inset);
            cv.drawArc(oval, 0, 360, false, track);
            // قوس صغير مرئي حتى في البداية (أول صفحة) حتى لا تبدو الحلقة فارغة
            if (fraction > 0) cv.drawArc(oval, -90, Math.max(6f, 360f * fraction), false, arc);
        }
    }
}
