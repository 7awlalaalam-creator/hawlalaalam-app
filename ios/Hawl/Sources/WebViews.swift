import SwiftUI
import WebKit

/** إعدادات صفحات الموقع داخل التطبيق: علامة التطبيق، وجسر bridge.js المشترك مع أندرويد */
enum WebConfig {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    /** يُضاف إلى userAgent فيعرف الموقع وbridge.js أن الزائر داخل التطبيق (نفس علامة أندرويد) */
    static var appName: String { "HawlalaalamApp/" + version }
    static var userAgentMark: String { "HawlalaalamApp/" + version + " (iOS)" }

    private static var bridgeSource: String = {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        // ملفات المصحف والخط تُقدَّم من التطبيق عبر hawl://app/__hawl/ (بدل /__hawl/ في أندرويد)
        // وتُميَّز زيارات آيفون في الإحصاءات وفي قالب الموقع
        return s.replacingOccurrences(of: "'/__hawl/", with: "'hawl://app/__hawl/")
            .replacingOccurrences(of: "'android_app'", with: "'ios_app'")
            .replacingOccurrences(of: "setAttribute('data-app', 'android')", with: "setAttribute('data-app', 'ios')")
    }()

    /** الجسر لصفحات نطاق الموقع فقط، مع المظهر وحجم الخط */
    static func bridge(night: Bool) -> String {
        let zoom = Store.int("text_zoom", 100)
        let internalDevice = Store.bool("internal_device", false)
        var js: String = "if(/(^|\\.)7awlalaalam\\.com$/.test(location.hostname)){"
        js += "window.HawlApp={postMessage:function(m){window.webkit.messageHandlers.HawlApp.postMessage(m)}};"
        if internalDevice { js += "window.__hawlInternal=true;" }
        js += "window.__hawlTheme='" + (night ? "dark" : "light") + "';"
        js += "window.__hawlZoom=" + String(zoom) + ";\n"
        js += bridgeSource
        js += "\n}"
        return js
    }

    /** حجم الخط في صفحات الموقع (مثل setTextZoom في أندرويد) */
    static func zoomCSS() -> String {
        let z = Store.int("text_zoom", 100)
        if z == 100 { return "" }
        return "(function(){if(!/(^|\\.)7awlalaalam\\.com$/.test(location.hostname))return;"
            + "var s=document.createElement('style');s.textContent='html{-webkit-text-size-adjust:\(z)%!important}';"
            + "(document.head||document.documentElement).appendChild(s);})();"
    }

    /** حجب نطاقات الإعلانات داخل التطبيق (كما في أندرويد) */
    static let adRules = """
    [{"trigger":{"url-filter":"^https?://([^/]*\\\\.)?(googlesyndication\\\\.com|doubleclick\\\\.net|googleadservices\\\\.com|googletagservices\\\\.com|adtrafficquality\\\\.google)/"},"action":{"type":"block"}}]
    """

    static var compiledRules: WKContentRuleList?

    static func prepareRules() {
        guard compiledRules == nil else { return }
        WKContentRuleListStore.default()?.compileContentRuleList(forIdentifier: "hawl-ads", encodedContentRuleList: adRules) { list, _ in
            compiledRules = list
        }
    }
}

/**
 * يقدّم صفحة المصحف دون إنترنت وملفاتها من داخل التطبيق عبر العنوان hawl://app/__hawl/…
 * (نفس جدول الملفات في QuranText.intercept بتطبيق أندرويد). تُطلب أيضًا من صفحات الموقع (الخط وجدول التحويل).
 */
final class HawlSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "hawl"
    private static let files: [String: (String, String, String)] = [
        "/__hawl/mushaf-pages-offline.html": ("mushaf-offline", "html", "text/html"),
        "/__hawl/hafs.woff2": ("hafs", "woff2", "font/woff2"),
        "/__hawl/qmap.json": ("qmap", "json", "application/json"),
        "/__hawl/mushaf.json": ("mushaf", "json", "application/json"),
        "/__hawl/tafsir.json": ("tafsir-muyassar", "json", "application/json"),
        "/__hawl/search.json": ("search", "json", "application/json"),
    ]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let f = Self.files[url.path],
              let fileURL = Bundle.main.url(forResource: f.0, withExtension: f.1, subdirectory: "quran"),
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let textual = f.2.hasPrefix("text") || f.2.hasPrefix("application")
        let headers = ["Content-Type": f.2 + (textual ? "; charset=utf-8" : ""),
                       "Content-Length": String(data.count),
                       "Cache-Control": "max-age=31536000",
                       "Access-Control-Allow-Origin": "*"]
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { }
}

// MARK: - رسائل الصفحات إلى التطبيق (نفس handleBridge في أندرويد)

final class HawlBridge: NSObject, WKScriptMessageHandler {
    weak var web: WKWebView?
    /** الميكروفون (التسميع) مسموح لصفحة المصحف وحدها، ومن إطارها الرئيسي فقط */
    var allowSpeech = false
    private var queried = Set<String>()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(downloadsChanged), name: AudioDownloads.changed, object: nil)
    }

    @objc private func downloadsChanged() {
        Task { @MainActor in self.pushAll() }
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let str = message.body as? String, let data = str.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = o["cmd"] as? String else { return }
        if cmd == "speech" && (!allowSpeech || !message.frameInfo.isMainFrame) { return }
        Task { @MainActor in self.handle(cmd, o) }
    }

    @MainActor private func handle(_ cmd: String, _ o: [String: Any]) {
        switch cmd {
        case "share", "save":
            var items: [Any] = []
            var files = o["files"] as? [[String: Any]] ?? []
            if cmd == "save" { files = [o] }
            for f in files {
                guard let b64 = f["data"] as? String, let bytes = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { continue }
                let type = f["type"] as? String ?? ""
                if type.hasPrefix("image/"), let img = UIImage(data: bytes) { items.append(img); continue }
                let name = Self.safeName(f["name"] as? String ?? "file")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                if (try? bytes.write(to: url)) != nil { items.append(url) }
            }
            var text = o["text"] as? String ?? ""
            let link = o["url"] as? String ?? ""
            if !link.isEmpty && !text.contains(link) { text += (text.isEmpty ? "" : "\n") + link }
            if cmd == "share" && !text.isEmpty { items.append(text) }
            if !items.isEmpty { Share.present(items) }
        case "download":
            guard let u = o["url"] as? String else { return }
            queried.insert(u)
            AudioDownloads.shared.start(url: u, title: o["title"] as? String ?? "", reciter: o["reciter"] as? String ?? "")
            Toast.show("بدأ التحميل، تجده في «التلاوات المحمّلة»")
            push(u)
        case "dl_query":
            guard let u = o["url"] as? String else { return }
            queried.insert(u)
            push(u)
        case "settings":
            AppState.shared.show(.settings)
        case "diag":
            Store.d.set(o["msg"] as? String ?? "", forKey: "bridge_diag")
        case "speech":
            // التسميع: بدء التعرّف على التلاوة أو إيقافه
            if (o["op"] as? String) == "start" { SpeechService.shared.start(web: web, lang: o["lang"] as? String ?? "ar-SA") }
            else { SpeechService.shared.stop() }
        case "hifz":
            // حالة الحفظ من صفحة المصحف: لبطاقة «مراجعة الحفظ» في «اليوم»
            Store.d.set(o["total"] as? Int ?? 0, forKey: "hifz_total")
            Store.d.set(o["next"] as? Int ?? -1, forKey: "hifz_next")
            Store.d.set(o["held"] as? Int ?? 0, forKey: "hifz_held")
            Store.d.set(o["pct"] as? Int ?? 0, forKey: "hifz_pct")
            AppState.shared.touch()
        default: break                                    // media: التحكم من شاشة القفل يتولاه النظام في iOS
        }
    }

    @MainActor private func push(_ url: String) {
        let st: String
        switch AudioDownloads.shared.status(url) {
        case .done: st = "done"
        case .running: st = "running"
        default: st = "none"
        }
        let q = (try? JSONSerialization.data(withJSONObject: [url])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        web?.evaluateJavaScript("window.__hawlDlState&&window.__hawlDlState(\(q)[0],'\(st)')", completionHandler: nil)
    }

    @MainActor private func pushAll() { for u in queried { push(u) } }

    static func safeName(_ n: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let s = n.components(separatedBy: bad).joined(separator: "_").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "file" : s
    }
}

// MARK: - المصحف دون إنترنت

/** المصحف بأسطر مصحف المدينة — نفس صفحة تطبيق أندرويد دون إنترنت */
struct MushafWebView: UIViewRepresentable {
    var page: Int
    var night: Bool
    var zoom: Int
    /** أداة تُفتح مع الصفحة (مراجعة الحفظ أو البحث بالمعنى)، ورقم الطلب حتى تُفتح كل مرة تُطلب */
    var extra: String = ""
    var extraID: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func script(night: Bool, zoom: Int) -> String {
        let theme: String = night ? "dark" : "light"
        return "window.HawlApp={postMessage:function(m){window.webkit.messageHandlers.HawlApp.postMessage(m)}};"
            + "window.__hawlTheme='\(theme)';window.__hawlZoom=\(zoom);"
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(HawlSchemeHandler(), forURLScheme: HawlSchemeHandler.scheme)
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.applicationNameForUserAgent = WebConfig.appName
        cfg.userContentController.addUserScript(WKUserScript(source: Self.script(night: night, zoom: zoom),
                                                             injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(context.coordinator.bridge, name: "HawlApp")

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.bridge.web = web
        context.coordinator.bridge.allowSpeech = true
        context.coordinator.observe(web)
        context.coordinator.night = night
        context.coordinator.zoom = zoom
        context.coordinator.extraID = extraID
        context.coordinator.load(web, page: page, extra: extra)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        if extraID != c.extraID {
            c.extraID = extraID
            c.load(web, page: page != c.requestedPage ? page : (c.currentPage ?? page), extra: extra)
            return
        }
        if c.night != night || c.zoom != zoom {
            // تغيّر المظهر أو حجم الخط: نعيد تحميل الصفحة نفسها
            c.night = night
            c.zoom = zoom
            web.configuration.userContentController.removeAllUserScripts()
            web.configuration.userContentController.addUserScript(WKUserScript(source: Self.script(night: night, zoom: zoom),
                                                                               injectionTime: .atDocumentStart, forMainFrameOnly: true))
            c.load(web, page: c.currentPage ?? page)
        } else if page != c.requestedPage && page != c.currentPage {
            c.load(web, page: page)
        } else if page != c.requestedPage {
            c.requestedPage = page                   // الصفحة المعروضة هي المطلوبة أصلًا
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "HawlApp")
        SpeechService.shared.stopIfActive()
        coordinator.urlObservation = nil
        coordinator.dwellTask?.cancel()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let bridge = HawlBridge()
        var urlObservation: NSKeyValueObservation?
        var requestedPage: Int?
        var currentPage: Int?
        var night = false
        var zoom = 100
        var dwellTask: Task<Void, Never>?
        var extraID = 0

        func load(_ web: WKWebView, page: Int, extra: String = "") {
            requestedPage = page
            let p = max(1, min(Quran.pages, page))
            let more = extra.isEmpty ? "" : "&" + extra
            if let url = URL(string: "hawl://app/__hawl/mushaf-pages-offline.html?page=\(p)\(more)") {
                web.load(URLRequest(url: url))
            }
        }

        /** الصفحة تغيّر ?page=N دون إعادة تحميل (history.replaceState): نتابع العنوان */
        func observe(_ web: WKWebView) {
            urlObservation = web.observe(\.url, options: [.new]) { [weak self] w, _ in
                guard let url = w.url,
                      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      let v = items.first(where: { $0.name == "page" })?.value, let p = Int(v) else { return }
                Task { @MainActor [weak self] in self?.pageShown(p) }
            }
        }

        /** آخر صفحة والسلسلة فورًا، والختمة بعد بقاء القارئ على الصفحة (لا بمجرد التصفح) */
        @MainActor private func pageShown(_ p: Int) {
            if p == currentPage { return }
            currentPage = p
            AppState.shared.recordMushaf(page: p)
            dwellTask?.cancel()
            guard Khatma.active else { return }
            dwellTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Khatma.dwell * 1_000_000_000))
                guard !Task.isCancelled, let self = self, self.currentPage == p else { return }
                Khatma.onPage(p)
            }
        }

        /** الروابط الخارجية تُفتح في المتصفح، وروابط الموقع داخل التطبيق */
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.allow) }
            let scheme = (url.scheme ?? "").lowercased()
            if scheme == HawlSchemeHandler.scheme || scheme == "about" || scheme == "blob" || scheme == "data" {
                return decisionHandler(.allow)
            }
            if action.navigationType == .linkActivated || action.targetFrame?.isMainFrame == true {
                Task { @MainActor in AppState.shared.open(url) }
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - صفحات الموقع

/** صفحة من الموقع داخل التطبيق (الاستماع، الأذكار، الترجمات…) بنفس سلوك MainActivity في أندرويد */
struct WebPage: UIViewRepresentable {
    var url: URL
    var night: Bool
    @Binding var loading: Bool
    @Binding var title: String
    @Binding var failed: Bool
    var reloadToken: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        // العلامة نفسها التي يرسلها تطبيق أندرويد: الموقع وbridge.js يعرفان أن الزائر داخل التطبيق
        cfg.applicationNameForUserAgent = WebConfig.appName
        cfg.setURLSchemeHandler(HawlSchemeHandler(), forURLScheme: HawlSchemeHandler.scheme)
        let ucc = cfg.userContentController
        ucc.addUserScript(WKUserScript(source: WebConfig.bridge(night: night), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let z = WebConfig.zoomCSS()
        if !z.isEmpty { ucc.addUserScript(WKUserScript(source: z, injectionTime: .atDocumentEnd, forMainFrameOnly: true)) }
        ucc.add(context.coordinator.bridge, name: "HawlApp")
        if let rules = WebConfig.compiledRules { ucc.add(rules) }

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.overrideUserInterfaceStyle = night ? .dark : .light
        web.isOpaque = false
        web.backgroundColor = UIColor(Palette.page)
        web.scrollView.backgroundColor = UIColor(Palette.page)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        context.coordinator.bridge.web = web
        context.coordinator.observe(web)
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh
        context.coordinator.requested = url
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if url != c.requested {
            c.requested = url
            web.load(URLRequest(url: url))
        } else if reloadToken != c.reloadToken {
            c.reloadToken = reloadToken
            if let u = c.failedURL ?? web.url { web.load(URLRequest(url: u)) } else { web.reload() }
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "HawlApp")
        coordinator.observations = []
        coordinator.dwellTask?.cancel()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebPage
        let bridge = HawlBridge()
        var requested: URL?
        var failedURL: URL?
        var reloadToken = 0
        var observations: [NSKeyValueObservation] = []
        var dwellTask: Task<Void, Never>?
        private var triedCache = false

        init(_ parent: WebPage) { self.parent = parent }

        @objc func reload(_ sender: UIRefreshControl) {
            (sender.superview?.superview as? WKWebView)?.reload()
            sender.endRefreshing()
        }

        func observe(_ web: WKWebView) {
            observations = [
                web.observe(\.title, options: [.new]) { [weak self] w, _ in
                    let t = w.title ?? ""
                    let u = w.url
                    Task { @MainActor [weak self] in
                        self?.parent.title = t
                        if let u = u { Reading.record(u, title: t) }     // العنوان الصحيح يصل بعد التنقّل
                    }
                },
                web.observe(\.url, options: [.new]) { [weak self] w, _ in
                    guard let u = w.url else { return }
                    let title = w.title
                    Task { @MainActor [weak self] in self?.urlChanged(u, title: title, web: w) }   // تنقّل داخل الصفحة دون إعادة تحميل
                },
            ]
        }

        /** الختمة: تُحتسب صفحة المصحف بعد بقاء القارئ عليها مدة كافية */
        @MainActor private func urlChanged(_ u: URL, title: String?, web: WKWebView) {
            Reading.record(u, title: title)
            dwellTask?.cancel()
            let p = Khatma.pageOf(u)
            guard p > 0, Khatma.active else { return }
            dwellTask = Task { @MainActor [weak web] in
                try? await Task.sleep(nanoseconds: UInt64(Khatma.dwell * 1_000_000_000))
                guard !Task.isCancelled, let cur = web?.url, Khatma.pageOf(cur) == p else { return }
                Khatma.onPage(p)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in self.parent.loading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            triedCache = false
            failedURL = nil
            Task { @MainActor in
                self.parent.loading = false
                self.parent.failed = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in self.parent.loading = false }
        }

        /** لا اتصال: نجرّب النسخة المحفوظة من الصفحة، وإلا نعرض شاشة «لا يوجد اتصال» */
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            let failing = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? requested
            if !triedCache, let u = failing {
                triedCache = true
                webView.load(URLRequest(url: u, cachePolicy: .returnCacheDataDontLoad))
                return
            }
            failedURL = failing
            Task { @MainActor in
                self.parent.loading = false
                self.parent.failed = true
            }
        }

        /** روابط خارج الموقع (واتساب، يوتيوب…) تُفتح في تطبيقها أو المتصفح؛ hawlapp:// يفتح شاشات التطبيق */
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return decisionHandler(.allow) }
            if scheme == "about" || scheme == "blob" || scheme == "data" || scheme == HawlSchemeHandler.scheme {
                return decisionHandler(.allow)
            }
            if scheme == "hawlapp" {
                Task { @MainActor in AppState.shared.handleDeepLink(url) }
                return decisionHandler(.cancel)
            }
            if scheme == "http" || scheme == "https" {
                if Links.isOurs(url) {
                    // داخل التطبيق: رابط «الخصوصية» يفتح سياسة خصوصية التطبيق
                    if url.path.hasSuffix("/quran/privacy.html") {
                        webView.load(URLRequest(url: Links.privacy))
                        return decisionHandler(.cancel)
                    }
                    // صفحة المصحف من الموقع تُفتح في مصحف التطبيق (دون إنترنت وبالإطار)
                    if action.targetFrame?.isMainFrame != false, action.navigationType == .linkActivated, Khatma.pageOf(url) > 0 {
                        Task { @MainActor in AppState.shared.openMushaf(page: Khatma.pageOf(url)) }
                        return decisionHandler(.cancel)
                    }
                    return decisionHandler(.allow)
                }
                if action.targetFrame?.isMainFrame == false { return decisionHandler(.allow) }   // إطارات مضمّنة (يوتيوب…)
            }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        /** روابط target=_blank تُفتح في نفس الصفحة */
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let u = navigationAction.request.url {
                if Links.isOurs(u) { webView.load(navigationAction.request) } else { UIApplication.shared.open(u) }
            }
            return nil
        }
    }
}

/** صفحة موقع بعنوان وشريط تحميل وشاشة «لا يوجد اتصال»، داخل NavigationStack */
struct WebScreen: View {
    var title: String
    var url: URL
    @Environment(\.colorScheme) private var scheme
    @State private var loading = true
    @State private var pageTitle = ""
    @State private var failed = false
    @State private var reload = 0

    var body: some View {
        WebPage(url: url, night: scheme == .dark, loading: $loading, title: $pageTitle, failed: $failed, reloadToken: reload)
            .id(scheme)                                         // تغيّر المظهر: نعيد بناء الصفحة بألوانه
            .overlay(alignment: .top) {
                if loading { ProgressView().progressViewStyle(.linear).tint(Palette.goldDeep) }
            }
            .overlay { if failed { offline } }
            .navigationTitle(title.isEmpty ? Self.short(pageTitle) : title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Palette.page)
            .keepScreenOn()
    }

    private var offline: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash").font(.system(size: 40)).foregroundColor(Palette.goldDeep)
            Text("لا يوجد اتصال بالإنترنت").font(AppFont.ui(18, 700)).foregroundColor(Palette.ink)
            Text("المصحف والفهرس والأذكار بعد الصلاة والقبلة والمسبحة تعمل دون إنترنت.")
                .font(AppFont.ui(14)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
            Button { failed = false; reload += 1 } label: { Pill(title: "إعادة المحاولة", systemImage: "arrow.clockwise", primary: true) }
                .frame(maxWidth: 260)
            Button { AppState.shared.openMushaf(page: nil) } label: { Pill(title: "افتح المصحف", systemImage: "book") }
                .frame(maxWidth: 260)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.page)
    }

    /** عنوان الصفحة بلا اسم الموقع */
    static func short(_ t: String) -> String {
        var s = t
        for sep in [" | ", " - ", " – ", " — "] { if let r = s.range(of: sep) { s = String(s[..<r.lowerBound]) } }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "حول العالم" : ar(s)
    }
}

/** إبقاء الشاشة مضاءة أثناء القراءة والاستماع (من الإعدادات، مفعّل افتراضيًا) */
struct KeepScreenOn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = Store.bool("keep_screen", true) }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View {
    func keepScreenOn() -> some View { modifier(KeepScreenOn()) }
}
