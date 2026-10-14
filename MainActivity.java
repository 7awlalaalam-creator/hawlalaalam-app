package com.hawlalaalam.quran;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.app.DownloadManager;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.View;
import android.view.Window;
import android.window.OnBackInvokedDispatcher;
import android.view.WindowManager;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.webkit.CookieManager;
import android.webkit.GeolocationPermissions;
import android.webkit.MimeTypeMap;
import android.webkit.URLUtil;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ProgressBar;
import android.widget.Toast;

import androidx.core.content.FileProvider;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URLDecoder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {

    private static final String HOME = "https://7awlalaalam.com/quran/";
    private static final String CONTACT = "https://7awlalaalam.com/quran/contact.html";
    private static final Set<String> HOSTS =
            new HashSet<>(Arrays.asList("7awlalaalam.com", "www.7awlalaalam.com"));
    private static final Set<String> ORIGINS =
            new HashSet<>(Arrays.asList("https://7awlalaalam.com", "https://www.7awlalaalam.com"));
    /** علامة يستطيع الموقع قراءتها من navigator.userAgent لمعرفة أن الزائر داخل التطبيق */
    private static final String UA_MARK = " HawlalaalamApp/";

    private static final int REQ_FILE = 11;
    private static final int REQ_LOCATION = 12;
    private static final int REQ_NOTIF = 13;

    private WebView web;
    private SwipeRefreshLayout swipe;
    private ProgressBar progress;
    private View offline;
    private FrameLayout fullscreen;

    private String bridgeJs = "";
    private boolean docStartScript = false;
    private android.widget.LinearLayout appNav;
    private boolean createdNight;
    private boolean mainFrameError = false;
    private String failedUrl;

    private ValueCallback<Uri[]> fileCallback;
    private GeolocationPermissions.Callback geoCallback;
    private String geoOrigin;
    private View customView;
    private WebChromeClient.CustomViewCallback customCallback;

    private boolean startupDialogOpen = false;
    private boolean clearHistoryOnLoad = false;
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private ConnectivityManager.NetworkCallback netCallback;

    // ------------------------------------------------------------------ دورة الحياة

    @Override
    protected void attachBaseContext(android.content.Context base) {
        super.attachBaseContext(Ui.wrap(base));             // مظهر التطبيق المختار
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        // أيقونة قديمة مثبّتة على الشاشة تفتح هذه الشاشة مباشرة: نحوّلها إلى «اليوم»
        Intent in = getIntent();
        if (state == null && in != null && Intent.ACTION_MAIN.equals(in.getAction()) && in.getData() == null) {
            startActivity(new Intent(this, HomeActivity.class));
            finish();
            return;
        }
        setContentView(R.layout.activity_main);

        web = findViewById(R.id.web);
        swipe = findViewById(R.id.swipe);
        createdNight = Ui.isNight(this);
        // شريط التطبيق الثابت أسفل صفحات الموقع (بدل شريط الموقع)
        appNav = Ui.appNav(this, Ui.NAV_TOOLS, this::onNavTap);
        ((FrameLayout) findViewById(R.id.nav_slot)).addView(appNav,
                new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT));
        progress = findViewById(R.id.progress);
        offline = findViewById(R.id.offline);
        fullscreen = findViewById(R.id.fullscreen);

        applyEdgeToEdgeInsets();
        if (Build.VERSION.SDK_INT >= 33) {    // الرجوع التنبؤي (إلزامي مع أندرويد 16)
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_DEFAULT, this::handleBack);
        }
        bridgeJs = (App.prefs(this).getBoolean("internal_device", false) ? "window.__hawlInternal=true;\n" : "")
                + "window.__hawlTheme='" + (createdNight ? "dark" : "light") + "';\n"
                + "window.__hawlZoom=" + App.prefs(this).getInt("text_zoom", 100) + ";\n"
                + readAsset("bridge.js");
        setupWebView();
        watchNetwork();

        swipe.setColorSchemeColors(getColor(R.color.gold_deep), getColor(R.color.ink));
        swipe.setProgressBackgroundColorSchemeColor(getColor(R.color.card));
        swipe.setOnRefreshListener(() -> { if (web != null) web.reload(); else swipe.setRefreshing(false); });
        // السحب للتحديث فقط عندما تكون الصفحة في أعلاها
        swipe.setOnChildScrollUpCallback((parent, child) -> web == null || web.getScrollY() > 0);

        findViewById(R.id.retry).setOnClickListener(v -> retry());
        findViewById(R.id.go_home).setOnClickListener(v -> {
            offline.setVisibility(View.GONE);
            web.getSettings().setCacheMode(WebSettings.LOAD_CACHE_ELSE_NETWORK);
            web.loadUrl(HOME);
        });

        if (state == null || web.restoreState(state) == null) {
            web.loadUrl(urlFromIntent(getIntent()));
        }
        Notifier.ensureChannels(this);
        Reminders.scheduleAll(this);
        if (state == null) {
            clearHistoryOnLoad = getIntent().getBooleanExtra(HomeActivity.EXTRA_FROM_HOME, false);
        }
        MediaService.controller = cmd -> {
            if (web != null) web.evaluateJavascript("window.__hawlMedia&&window.__hawlMedia('" + cmd + "')", null);
        };
        Adhan.scheduleNext(this);
    }

    // ------------------------------------------------------------------ التذكيرات والإعدادات

    private void afterBetaNotice() {
        if (!Reminders.askedBefore(this)) showRemindersPrompt();
    }

    private void showRemindersPrompt() {
        Reminders.markAsked(this);
        AlertDialog d = new AlertDialog.Builder(this, Ui.dialogTheme(this))
                .setTitle("🔔 التذكيرات اليومية")
                .setMessage("هل تحب أن يصلك:\n\n✦ آية اليوم مع تفسيرها كل صباح (7:00 ص)\n"
                        + "📖 تذكير بوردك اليومي كل مساء (9:00 م)\n\n"
                        + "تقدر تغيّر الأوقات أو توقفها من الإعدادات: اضغط مطولًا على أيقونة التطبيق ← «الإعدادات».")
                .setPositiveButton("فعّلها", (x, w) -> {
                    if (Notifier.allowed(this)) enableDefaultReminders();
                    else if (Build.VERSION.SDK_INT >= 33)
                        requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQ_NOTIF);
                })
                .setNegativeButton("لا، شكرًا", null)
                .create();
        startupDialogOpen = true;
        d.setOnDismissListener(x -> startupDialogOpen = false);
        d.show();
        if (d.getWindow() != null) d.getWindow().getDecorView().setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
    }

    private void enableDefaultReminders() {
        Reminders.set(this, Reminders.VERSE, true, Reminders.hour(this, Reminders.VERSE), Reminders.minute(this, Reminders.VERSE));
        Reminders.set(this, Reminders.WIRD, true, Reminders.hour(this, Reminders.WIRD), Reminders.minute(this, Reminders.WIRD));
        toast("تم تفعيل التذكيرات ✓");
    }

    /** حالة التلاوة من صفحة الويب ← إشعار التحكم وشاشة القفل */
    private void onMediaState(String title, boolean playing) {
        MediaService svc = MediaService.instance;
        if (svc != null) {
            svc.onState(title, playing);
        } else if (playing) {
            try {
                startForegroundService(new Intent(this, MediaService.class)
                        .setAction(MediaService.ACT_UPDATE)
                        .putExtra(MediaService.EXTRA_TITLE, title)
                        .putExtra(MediaService.EXTRA_PLAYING, true));
            } catch (Exception ignored) { }
        }
    }

    /** يبلّغ صفحة القارئ بحالة تحميل التلاوة لتحديث الزر */
    private void pushDlState(String url) {
        if (web == null || url == null) return;
        int st = Downloads.status(getApplicationContext(), url);
        String state = st == Downloads.DONE ? "done" : st == Downloads.RUNNING ? "running" : "none";
        web.evaluateJavascript("window.__hawlDlState&&window.__hawlDlState(" + JSONObject.quote(url) + ",'" + state + "')", null);
    }

    private void openSettings() {
        startActivity(new Intent(this, SettingsActivity.class));
    }

    // ------------------------------------------------------------------ تنبيه النسخة التجريبية

    /** يظهر مرة واحدة لكل إصدار جديد */
    @SuppressWarnings("deprecation")
    private boolean showBetaNoticeOnce() {
        long versionCode = 0;
        String versionName = "";
        try {
            android.content.pm.PackageInfo pi = getPackageManager().getPackageInfo(getPackageName(), 0);
            versionCode = Build.VERSION.SDK_INT >= 28 ? pi.getLongVersionCode() : pi.versionCode;
            versionName = pi.versionName == null ? "" : pi.versionName;
        } catch (Exception ignored) { }

        SharedPreferences prefs = getSharedPreferences("app", MODE_PRIVATE);
        if (prefs.getLong("beta_notice_seen", -1) == versionCode) return false;
        final long seen = versionCode;

        AlertDialog dialog = new AlertDialog.Builder(this, Ui.dialogTheme(this))
                .setTitle(getString(R.string.beta_title))
                .setMessage(getString(R.string.beta_body, versionName))
                .setCancelable(false)
                .setPositiveButton(getString(R.string.beta_ok), (d, w) -> {
                    prefs.edit().putLong("beta_notice_seen", seen).apply();
                    afterBetaNotice();
                })
                .setNeutralButton(getString(R.string.beta_feedback), (d, w) -> {
                    prefs.edit().putLong("beta_notice_seen", seen).apply();
                    web.loadUrl(CONTACT);
                })
                .create();
        startupDialogOpen = true;
        dialog.setOnDismissListener(x -> startupDialogOpen = false);
        dialog.show();
        if (dialog.getWindow() != null) {
            dialog.getWindow().getDecorView().setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        }
        return true;
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        clearHistoryOnLoad = intent.getBooleanExtra(HomeActivity.EXTRA_FROM_HOME, false);
        Uri data = intent.getData();
        if (data != null && isOurs(data) && web != null) web.loadUrl(data.toString());
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        if (web != null) web.saveState(out);
    }

    @Override
    protected void onResume() {
        super.onResume();
        // تغيّر المظهر من «اليوم» أو الإعدادات: نعيد البناء (الصفحة وسجلها محفوظان)
        if (createdNight != Ui.isNight(Ui.wrap(getApplicationContext()))) { recreate(); return; }
        web.onResume();
        if (App.prefs(this).getBoolean("keep_screen", true)) {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        } else {
            getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
        // تحديث الموقع بهدوء للمسافرين (مرة كل 6 ساعات) لضبط مواقيت الأذان
        long lastLoc = App.prefs(this).getLong("loc_time", 0);
        if (Adhan.enabled(this) && Loc.hasPermission(this)
                && System.currentTimeMillis() - lastLoc > 6 * 3_600_000L) {
            App.prefs(this).edit().putLong("loc_time", System.currentTimeMillis()).apply();
            Loc.get(this, l -> {
                if (l == null) return;
                Adhan.saveLocation(this, l.getLatitude(), l.getLongitude());
                Adhan.scheduleNext(this);
                // خيط مستقل: قد يصل الموقع بعد إغلاق الشاشة (و io مغلق) فيسبب انهيارًا
                Context app = getApplicationContext();
                new Thread(() -> Adhan.saveCity(app,
                        Loc.cityName(app, l.getLatitude(), l.getLongitude()))).start();
            });
        }
        PrayerWidget.updateAll(this);
        RamadanWidget.updateAll(this);
        KhatmaWidget.updateAll(this);
        web.getSettings().setTextZoom(App.prefs(this).getInt("text_zoom", 100));
        // فحص التحديث كل مرة يعود فيها المستخدم (بحد أقصى مرة كل 3 ساعات)
        if (!startupDialogOpen) UpdateChecker.check(this, false);
    }

    // ملاحظة: لا نستدعي web.onPause() عمدًا حتى يستمر تشغيل التلاوة عند الخروج المؤقت من التطبيق

    @Override
    protected void onDestroy() {
        // web تكون null إن أُغلقت الشاشة فورًا بعد التحويل إلى «اليوم» أو بعد انهيار محرّك العرض
        if (web != null) {
            MediaService.controller = null;
            MediaService svc = MediaService.instance;
            if (svc != null) svc.stopAll();
        }
        if (netCallback != null) {
            try {
                getSystemService(ConnectivityManager.class).unregisterNetworkCallback(netCallback);
            } catch (Exception ignored) { }
            netCallback = null;
        }
        io.shutdown();
        if (web != null) web.destroy();
        super.onDestroy();
    }

    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() {      // أندرويد 12 وأقدم
        handleBack();
    }

    /** زر الرجوع: يغلق الفيديو، أو يرجع صفحة، أو يخرج */
    private void handleBack() {
        if (customView != null) {
            hideCustomView();
            return;
        }
        if (web == null) { finish(); return; }          // محرّك الصفحات أُعيد تشغيله للتو
        if (web.canGoBack()) {
            offline.setVisibility(View.GONE);
            web.goBack();
            return;
        }
        // نعرض «اليوم» فوق هذه الشاشة دون إغلاقها (تبقى الصفحة والتلاوة جاهزتين للرجوع)
        startActivity(new Intent(this, HomeActivity.class).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
    }


    // ------------------------------------------------------------------ إعداد WebView

    private void setupWebView() {
        WebSettings ws = web.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setMediaPlaybackRequiresUserGesture(false);
        ws.setLoadWithOverviewMode(true);
        ws.setUseWideViewPort(true);
        ws.setSupportZoom(true);
        ws.setBuiltInZoomControls(true);
        ws.setDisplayZoomControls(false);
        ws.setTextZoom(App.prefs(this).getInt("text_zoom", 100));
        ws.setAllowFileAccess(false);
        ws.setAllowContentAccess(false);
        ws.setGeolocationEnabled(true);
        ws.setSupportMultipleWindows(false); // الروابط target=_blank تُفتح في نفس النافذة ثم تُفرز
        ws.setJavaScriptCanOpenWindowsAutomatically(true);
        ws.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        ws.setUserAgentString(ws.getUserAgentString() + UA_MARK + appVersion());
        // الموقع يتبع مظهر التطبيق: prefers-color-scheme يأخذ قيمته من الثيم (isLightTheme)،
        // و bridge.js يطبّق ألوان الوضع الليلي الحقيقية. التعتيم الآلي مُعطَّل دائمًا:
        // كان يعتّم أجزاء من الصفحة ويترك أخرى فاتحة (الترويسة وفهرس السور) فيختلط المظهر.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
            androidx.webkit.WebSettingsCompat.setAlgorithmicDarkeningAllowed(ws, false);
        }

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(web, true);

        // جسر آمن: يعمل فقط لصفحات نطاق الموقع
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(web, "HawlApp", ORIGINS,
                    (view, message, sourceOrigin, isMainFrame, replyProxy) -> {
                        String data = message.getData();
                        if (isMainFrame && data != null) handleBridge(data);
                    });
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(web, bridgeJs, ORIGINS);
            docStartScript = true;
        }

        try {   // طلبات عامل الخدمة في الموقع تمر من هنا أيضًا
            android.webkit.ServiceWorkerController.getInstance().setServiceWorkerClient(new android.webkit.ServiceWorkerClient() {
                @Override
                public WebResourceResponse shouldInterceptRequest(WebResourceRequest request) {
                    WebResourceResponse q = QuranText.intercept(getApplicationContext(), request);
                    return q != null ? q : OfflineAudio.intercept(getApplicationContext(), request);
                }
            });
        } catch (Throwable ignored) { }
        web.setWebViewClient(new WebViewClient() {
            /** حجب إعلانات AdSense داخل التطبيق (سياسة AdSense تمنع عرضها في WebView) */
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                WebResourceResponse local = QuranText.intercept(getApplicationContext(), request);
                if (local == null) local = OfflineAudio.intercept(getApplicationContext(), request);
                if (local != null) return local;
                String host = request.getUrl().getHost();
                if (host != null && isAdHost(host.toLowerCase())) {
                    return new WebResourceResponse("text/plain", "utf-8",
                            new java.io.ByteArrayInputStream(new byte[0]));
                }
                return null;
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (!request.isForMainFrame()) return false;
                return handleUrl(request.getUrl());
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                mainFrameError = false;
                progress.setVisibility(View.VISIBLE);
                updateNav(url);
            }

            @Override
            public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
                super.doUpdateVisitedHistory(view, url, isReload);
                countAfterDwell(view, url);                    // تنقّل داخل الصفحة دون إعادة تحميل
                if (url != null && isOurs(Uri.parse(url))) Reading.record(MainActivity.this, url, view.getTitle());   // «تابع القراءة» يعرف آخر صفحة
                updateNav(url);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                swipe.setRefreshing(false);
                progress.setVisibility(View.GONE);
                if (clearHistoryOnLoad) { view.clearHistory(); clearHistoryOnLoad = false; }
                Reading.record(MainActivity.this, url, view.getTitle());
                countAfterDwell(view, url);
                if (!docStartScript && url != null && isOurs(Uri.parse(url))) {
                    view.evaluateJavascript(bridgeJs, null);
                }
                if (!mainFrameError) offline.setVisibility(View.GONE);
                CookieManager.getInstance().flush();
            }

            /**
             * انهيار محرّك العرض أو إغلاقه لنقص الذاكرة: بدون هذا يُغلق التطبيق كله.
             * نتخلص من الـ WebView الميت ونعيد بناء الشاشة على نفس الصفحة.
             */
            @Override
            public boolean onRenderProcessGone(WebView view, android.webkit.RenderProcessGoneDetail detail) {
                String last = view.getUrl();
                MediaService.controller = null;
                try {
                    android.view.ViewParent parent = view.getParent();
                    if (parent instanceof android.view.ViewGroup) ((android.view.ViewGroup) parent).removeView(view);
                    view.destroy();
                } catch (Exception ignored) { }
                if (view == web) web = null;
                if (last != null && isOurs(Uri.parse(last))) {
                    setIntent(new Intent(Intent.ACTION_VIEW, Uri.parse(last), MainActivity.this, MainActivity.class));
                }
                if (!isFinishing()) recreate();
                return true;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    mainFrameError = true;
                    failedUrl = request.getUrl().toString();
                    swipe.setRefreshing(false);
                    offline.setVisibility(View.VISIBLE);
                }
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onReceivedTitle(WebView view, String title) {
                // يصل العنوان الصحيح بعد التنقّل (حتى دون إعادة تحميل)، فنصحّح «أكمل من حيث توقفت»
                String u = view.getUrl();
                if (u != null && isOurs(Uri.parse(u))) Reading.record(MainActivity.this, u, title);
            }

            @Override
            public void onProgressChanged(WebView view, int p) {
                progress.setProgress(p);
                progress.setVisibility(p >= 100 ? View.GONE : View.VISIBLE);
            }

            @Override
            public void onShowCustomView(View view, CustomViewCallback callback) {
                if (customView != null) {
                    callback.onCustomViewHidden();
                    return;
                }
                customView = view;
                customCallback = callback;
                fullscreen.addView(view, new FrameLayout.LayoutParams(-1, -1));
                fullscreen.setVisibility(View.VISIBLE);
                setVideoFullscreen(true);
            }

            @Override
            public void onHideCustomView() {
                hideCustomView();
            }

            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                                             FileChooserParams params) {
                if (fileCallback != null) fileCallback.onReceiveValue(null);
                fileCallback = callback;
                try {
                    startActivityForResult(params.createIntent(), REQ_FILE);
                    return true;
                } catch (ActivityNotFoundException e) {
                    fileCallback = null;
                    return false;
                }
            }

            @Override
            public void onGeolocationPermissionsShowPrompt(String origin,
                                                           GeolocationPermissions.Callback callback) {
                String host = Uri.parse(origin).getHost();
                if (host == null || !HOSTS.contains(host)) {
                    callback.invoke(origin, false, false);
                    return;
                }
                if (hasLocationPermission()) {
                    callback.invoke(origin, true, false);
                } else {
                    geoOrigin = origin;
                    geoCallback = callback;
                    requestPermissions(new String[]{
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION}, REQ_LOCATION);
                }
            }
        });

        web.setDownloadListener((url, userAgent, contentDisposition, mimeType, length) ->
                handleDownload(url, userAgent, contentDisposition, mimeType));
    }

    // ------------------------------------------------------------------ الروابط

    private static boolean isAdHost(String h) {
        return h.endsWith("googlesyndication.com") || h.endsWith("doubleclick.net")
                || h.endsWith("googleadservices.com") || h.startsWith("adservice.google.")
                || h.endsWith("googletagservices.com") || h.endsWith("adtrafficquality.google");
    }

    private boolean isOurs(Uri uri) {
        String scheme = uri.getScheme();
        String host = uri.getHost();
        return host != null && HOSTS.contains(host.toLowerCase())
                && ("https".equals(scheme) || "http".equals(scheme));
    }

    @Override
    public void onConfigurationChanged(android.content.res.Configuration conf) {
        super.onConfigurationChanged(conf);
        // الوضع «تلقائي» والجوال بدّل نهاري/ليلي
        if (Ui.themeMode(this) == 0 && createdNight != Ui.isNight(Ui.wrap(getApplicationContext()))) recreate();
    }

    private String appVersion() {
        try { return getPackageManager().getPackageInfo(getPackageName(), 0).versionName; }
        catch (Exception e) { return "1"; }
    }

    /** أي عنصر في شريط التطبيق يطابق الصفحة الحالية */
    private void updateNav(String url) {
        if (appNav == null || url == null) return;
        String u = url.toLowerCase();
        // صفحات السور والمصحف (/سورة-… و/surah-… و/mushaf-page-…) تتبع «المصحف»؛
        // وباقي صفحات الموقع (الأذكار، الترجمات، المواقيت…) تُفتح من «الأدوات» فتتبعها
        int active = (u.contains("reciter") || u.contains("listen")) ? Ui.NAV_LISTEN
                : (Reading.isQuranPage(url) || u.contains("mushaf")) ? Ui.NAV_MUSHAF : Ui.NAV_TOOLS;
        Ui.setNavActive(appNav, active);
    }

    private void onNavTap(int idx) {
        if (web == null && (idx == Ui.NAV_MUSHAF || idx == Ui.NAV_LISTEN)) return;
        switch (idx) {
            case Ui.NAV_TODAY:
                // نُبقي هذه الشاشة حيّة خلف «اليوم» بدل إغلاقها: الرجوع للموقع فوري دون إعادة تحميل
                startActivity(new Intent(this, HomeActivity.class).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
                break;
            case Ui.NAV_MUSHAF: web.loadUrl(App.mushaf(this)); break;
            case Ui.NAV_LISTEN: web.loadUrl(App.HOME + "quran-reciters-ar.html"); break;
            case Ui.NAV_TOOLS: startActivity(new Intent(this, ToolsActivity.class)); break;
        }
    }

    private String urlFromIntent(Intent intent) {
        Uri data = intent != null ? intent.getData() : null;
        return (data != null && isOurs(data)) ? data.toString() : HOME;
    }

    /** @return true إذا عالجنا الرابط خارج WebView */
    private boolean handleUrl(Uri uri) {
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase();
        if (scheme.equals("http") || scheme.equals("https")) {
            // داخل التطبيق: رابط «الخصوصية» يفتح سياسة خصوصية التطبيق
            String path = uri.getPath() == null ? "" : uri.getPath();
            if (isOurs(uri) && path.endsWith("/quran/privacy.html")) {
                web.loadUrl(App.PRIVACY);
                return true;
            }
            if (isOurs(uri)) return false;          // صفحات الموقع داخل التطبيق
            openExternal(uri);                      // أي موقع آخر (واتساب، يوتيوب، إعلانات...) خارجه
            return true;
        }
        if (scheme.equals("about") || scheme.equals("javascript") || scheme.equals("blob")
                || scheme.equals("data")) {
            return false;
        }
        if (scheme.equals("hawlapp")) {             // hawlapp://settings أو hawlapp://qibla من صفحات الموقع
            if ("qibla".equals(uri.getHost())) startActivity(new Intent(this, QiblaActivity.class));
            else openSettings();
            return true;
        }
        if (scheme.equals("intent")) {
            openIntentUri(uri.toString());
            return true;
        }
        openExternal(uri);                          // tel: mailto: whatsapp: sms: geo: ...
        return true;
    }

    private void openExternal(Uri uri) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, uri));
        } catch (ActivityNotFoundException e) {
            toast(getString(R.string.no_app));
        }
    }

    private void openIntentUri(String url) {
        try {
            Intent intent = Intent.parseUri(url, Intent.URI_INTENT_SCHEME);
            intent.addCategory(Intent.CATEGORY_BROWSABLE);
            intent.setComponent(null);
            intent.setSelector(null);
            try {
                startActivity(intent);
            } catch (ActivityNotFoundException e) {
                String fallback = intent.getStringExtra("browser_fallback_url");
                if (fallback != null) {
                    openExternal(Uri.parse(fallback));
                } else if (intent.getPackage() != null) {
                    openExternal(Uri.parse("market://details?id=" + intent.getPackage()));
                } else {
                    toast(getString(R.string.no_app));
                }
            }
        } catch (Exception e) {
            toast(getString(R.string.no_app));
        }
    }

    private void retry() {
        offline.setVisibility(View.GONE);
        if (failedUrl != null) web.loadUrl(failedUrl);
        else web.reload();
    }

    // ------------------------------------------------------------------ عدم الاتصال: عرض الصفحات المحفوظة

    private void watchNetwork() {
        ConnectivityManager cm = getSystemService(ConnectivityManager.class);
        if (cm == null) return;
        boolean online = cm.getActiveNetwork() != null;
        web.getSettings().setCacheMode(online
                ? WebSettings.LOAD_DEFAULT : WebSettings.LOAD_CACHE_ELSE_NETWORK);
        netCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(Network network) {
                main.post(() -> {
                    if (web == null) return;
                    web.getSettings().setCacheMode(WebSettings.LOAD_DEFAULT);
                    if (offline.getVisibility() == View.VISIBLE) retry();
                });
            }

            @Override
            public void onLost(Network network) {
                main.post(() -> { if (web != null) web.getSettings().setCacheMode(WebSettings.LOAD_CACHE_ELSE_NETWORK); });
            }
        };
        try {
            cm.registerDefaultNetworkCallback(netCallback);
        } catch (Exception ignored) {
            netCallback = null;
        }
    }

    // ------------------------------------------------------------------ التنزيلات

    private void handleDownload(String url, String ua, String disposition, String mime) {
        String name = URLUtil.guessFileName(url, disposition, mime);
        if (url.startsWith("blob:")) {
            web.evaluateJavascript("window.__hawlSaveBlob&&window.__hawlSaveBlob("
                    + JSONObject.quote(url) + "," + JSONObject.quote(name) + ")", null);
            return;
        }
        if (url.startsWith("data:")) {
            io.execute(() -> saveDataUrl(url, name));
            return;
        }
        if (Build.VERSION.SDK_INT < 29) {       // الأجهزة القديمة: التنزيل عبر المتصفح
            openExternal(Uri.parse(url));
            return;
        }
        try {
            DownloadManager.Request req = new DownloadManager.Request(Uri.parse(url));
            if (mime != null) req.setMimeType(mime);
            req.addRequestHeader("User-Agent", ua);
            String cookies = CookieManager.getInstance().getCookie(url);
            if (cookies != null) req.addRequestHeader("Cookie", cookies);
            req.setTitle(name);
            req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
            req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name);
            getSystemService(DownloadManager.class).enqueue(req);
            toast(getString(R.string.downloading));
        } catch (Exception e) {
            openExternal(Uri.parse(url));
        }
    }

    private void saveDataUrl(String url, String name) {
        try {
            int comma = url.indexOf(',');
            String meta = url.substring(5, comma);
            String payload = url.substring(comma + 1);
            boolean isB64 = meta.endsWith(";base64");
            String mime = meta.split(";")[0];
            if (mime.isEmpty()) mime = "application/octet-stream";
            byte[] bytes = isB64 ? Base64.decode(payload, Base64.DEFAULT)
                    : URLDecoder.decode(payload, "UTF-8").getBytes("UTF-8");
            saveBytes(bytes, mime, name);
        } catch (Exception ignored) { }
    }

    // ------------------------------------------------------------------ الجسر (مشاركة / حفظ)

    private void handleBridge(String json) {
        io.execute(() -> {
            try {
                JSONObject o = new JSONObject(json);
                String cmd = o.optString("cmd");
                if ("dl_query".equals(cmd)) {
                    String u = o.optString("url");
                    main.post(() -> pushDlState(u));
                } else if ("download".equals(cmd)) {
                    String u = o.optString("url");
                    String title = o.optString("title");
                    String reciter = o.optString("reciter");
                    main.post(() -> {
                        Downloads.start(getApplicationContext(), u, title, reciter);
                        toast("بدأ التحميل، تجده في «التلاوات المحمّلة»");
                        pushDlState(u);
                    });
                } else if ("media".equals(cmd)) {
                    String title = o.optString("title");
                    boolean playing = "playing".equals(o.optString("state"));
                    main.post(() -> onMediaState(title, playing));
                } else if ("diag".equals(cmd)) {
                    // تشخيص صفحة المصحف: يُعرض بالضغط المطوّل على رقم الإصدار في الإعدادات
                    App.prefs(this).edit().putString("bridge_diag", o.optString("msg")).apply();
                } else if ("settings".equals(cmd)) {
                    main.post(this::openSettings);
                } else if ("share".equals(cmd)) {
                    doShare(o);
                } else if ("save".equals(cmd)) {
                    String mime = o.optString("type", "application/octet-stream");
                    byte[] bytes = Base64.decode(o.optString("data"), Base64.DEFAULT);
                    saveBytes(bytes, mime, o.optString("name", "file"));
                }
            } catch (Exception ignored) { }
        });
    }

    private void doShare(JSONObject o) throws Exception {
        StringBuilder text = new StringBuilder(o.optString("text"));
        String url = o.optString("url");
        if (!url.isEmpty() && text.indexOf(url) < 0) {
            if (text.length() > 0) text.append("\n");
            text.append(url);
        }
        JSONArray files = o.optJSONArray("files");
        ArrayList<Uri> uris = new ArrayList<>();
        String mime = "text/plain";
        if (files != null) {
            for (int i = 0; i < files.length(); i++) {
                JSONObject f = files.getJSONObject(i);
                String type = f.optString("type", "application/octet-stream");
                byte[] bytes = Base64.decode(f.optString("data"), Base64.DEFAULT);
                uris.add(writeShareFile(bytes, type, f.optString("name", "file")));
                mime = (i == 0) ? type : (mime.equals(type) ? mime : "*/*");
            }
        }
        final String shareMime = mime;
        final String title = o.optString("title");
        main.post(() -> startShare(uris, shareMime, text.toString(), title));
    }

    private void startShare(ArrayList<Uri> uris, String mime, String text, String title) {
        Intent send;
        if (uris.isEmpty()) {
            send = new Intent(Intent.ACTION_SEND).setType("text/plain");
        } else if (uris.size() == 1) {
            send = new Intent(Intent.ACTION_SEND).setType(mime);
            send.putExtra(Intent.EXTRA_STREAM, uris.get(0));
        } else {
            send = new Intent(Intent.ACTION_SEND_MULTIPLE).setType(mime);
            send.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
        }
        if (!text.isEmpty()) send.putExtra(Intent.EXTRA_TEXT, text);
        if (!title.isEmpty()) send.putExtra(Intent.EXTRA_SUBJECT, title);
        if (!uris.isEmpty()) {
            ClipData clip = ClipData.newRawUri("", uris.get(0));
            for (int i = 1; i < uris.size(); i++) clip.addItem(new ClipData.Item(uris.get(i)));
            send.setClipData(clip);
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        }
        try {
            startActivity(Intent.createChooser(send, getString(R.string.share_via)));
        } catch (ActivityNotFoundException e) {
            toast(getString(R.string.no_app));
        }
    }

    private Uri writeShareFile(byte[] bytes, String mime, String name) throws Exception {
        File dir = new File(getCacheDir(), "shared");
        if (!dir.exists()) dir.mkdirs();
        File f = new File(dir, safeName(name, mime));
        try (FileOutputStream out = new FileOutputStream(f)) {
            out.write(bytes);
        }
        return FileProvider.getUriForFile(this, getPackageName() + ".files", f);
    }

    private void saveBytes(byte[] bytes, String mime, String name) {
        String fileName = safeName(name, mime);
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                ContentValues v = new ContentValues();
                v.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName);
                v.put(MediaStore.MediaColumns.MIME_TYPE, mime);
                v.put(MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/حول العالم");
                v.put(MediaStore.MediaColumns.IS_PENDING, 1);
                Uri uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                if (uri == null) throw new IllegalStateException("insert failed");
                try (OutputStream out = getContentResolver().openOutputStream(uri)) {
                    if (out == null) throw new IllegalStateException("no stream");
                    out.write(bytes);
                }
                v.clear();
                v.put(MediaStore.MediaColumns.IS_PENDING, 0);
                getContentResolver().update(uri, v, null, null);
                main.post(() -> toast(getString(R.string.saved)));
            } else {
                // أندرويد 8-9: نفتح نافذة المشاركة ليحفظها المستخدم حيث يريد
                Uri uri = writeShareFile(bytes, mime, fileName);
                ArrayList<Uri> list = new ArrayList<>();
                list.add(uri);
                main.post(() -> startShare(list, mime, "", ""));
            }
        } catch (Exception e) {
            main.post(() -> toast(getString(R.string.no_app)));
        }
    }

    private static String safeName(String name, String mime) {
        String n = (name == null ? "" : name).replaceAll("[\\\\/:*?\"<>|]", "_").trim();
        if (n.isEmpty()) n = "file";
        if (!n.contains(".") && mime != null) {
            String ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime);
            if (ext != null) n = n + "." + ext;
        }
        return n;
    }

    // ------------------------------------------------------------------ ملء الشاشة والحواف

    private void hideCustomView() {
        if (customView == null) return;
        fullscreen.removeView(customView);
        fullscreen.setVisibility(View.GONE);
        customView = null;
        if (customCallback != null) customCallback.onCustomViewHidden();
        customCallback = null;
        setVideoFullscreen(false);
    }

    @SuppressWarnings("deprecation")
    private void setVideoFullscreen(boolean on) {
        Window w = getWindow();
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = w.getInsetsController();
            if (c == null) return;
            if (on) {
                c.hide(WindowInsets.Type.systemBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            } else {
                c.show(WindowInsets.Type.systemBars());
            }
        } else {
            w.getDecorView().setSystemUiVisibility(on
                    ? (View.SYSTEM_UI_FLAG_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY)
                    : View.SYSTEM_UI_FLAG_VISIBLE);
        }
    }

    /** أندرويد 15+ يرسم التطبيق خلف أشرطة النظام؛ نحجز مساحتها ومساحة لوحة المفاتيح */
    private void applyEdgeToEdgeInsets() {
        if (Build.VERSION.SDK_INT < 35) return;
        View root = findViewById(R.id.root);
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets i = insets.getInsets(WindowInsets.Type.systemBars()
                    | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
            v.setPadding(i.left, i.top, i.right, i.bottom);
            return WindowInsets.CONSUMED;
        });
    }

    // ------------------------------------------------------------------ الصلاحيات والنتائج

    private boolean hasLocationPermission() {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                || checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        super.onRequestPermissionsResult(code, perms, results);
        if (code == REQ_NOTIF) {
            if (Notifier.allowed(this)) enableDefaultReminders();
            else toast("يمكنك تفعيل التذكيرات لاحقًا من الإعدادات");
            return;
        }
        if (code == REQ_LOCATION && geoCallback != null) {
            geoCallback.invoke(geoOrigin, hasLocationPermission(), false);
            geoCallback = null;
        }
    }

    @SuppressWarnings("deprecation")
    @Override
    protected void onActivityResult(int code, int result, Intent data) {
        super.onActivityResult(code, result, data);
        if (code == REQ_FILE && fileCallback != null) {
            fileCallback.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result, data));
            fileCallback = null;
        }
    }

    // ------------------------------------------------------------------ أدوات

    private String readAsset(String name) {
        try (InputStream in = getAssets().open(name);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            return out.toString("UTF-8");
        } catch (Exception e) {
            return "";
        }
    }

    private void toast(String msg) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show();
    }

    /**
     * الختمة: تُحتسب صفحة المصحف مقروءة بعد بقاء القارئ عليها مدة كافية،
     * لا بمجرد فتحها أو تصفحها سريعًا.
     */
    private void countAfterDwell(WebView view, String url) {
        if (Khatma.pageOf(url) == 0 || !Khatma.active(this)) return;
        final String target = url;
        view.postDelayed(() -> {
            try {
                if (isFinishing() || isDestroyed()) return;
                String cur = view.getUrl();
                if (cur != null && Khatma.pageOf(cur) == Khatma.pageOf(target)) Khatma.onUrl(MainActivity.this, target);
            } catch (Throwable ignored) { }
        }, Khatma.DWELL_MS);
    }
}
