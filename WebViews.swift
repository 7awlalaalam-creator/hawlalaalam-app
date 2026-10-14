import SwiftUI
import WebKit

/**
 * يقدّم صفحة المصحف دون إنترنت وملفاتها من داخل التطبيق عبر العنوان hawl://app/__hawl/…
 * (نفس جدول الملفات في QuranText.intercept بتطبيق أندرويد).
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
                       "Access-Control-Allow-Origin": "*"]
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { }
}

/** المصحف بأسطر مصحف المدينة — نفس صفحة تطبيق أندرويد دون إنترنت */
struct MushafWebView: UIViewRepresentable {
    var page: Int
    var night: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(HawlSchemeHandler(), forURLScheme: HawlSchemeHandler.scheme)
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        // جسر الصفحة: window.HawlApp.postMessage كما في أندرويد، والمظهر المختار
        let bridge = "window.HawlApp={postMessage:function(m){window.webkit.messageHandlers.HawlApp.postMessage(m)}};"
            + "window.__hawlTheme='" + (night ? "dark" : "light") + "';"
        cfg.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(context.coordinator, name: "HawlApp")

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.observe(web)
        context.coordinator.night = night
        context.coordinator.load(web, page: page)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        if c.night != night {
            // تغيّر المظهر: نعيد تحميل الصفحة نفسها بالألوان الجديدة
            c.night = night
            web.configuration.userContentController.removeAllUserScripts()
            let bridge = "window.HawlApp={postMessage:function(m){window.webkit.messageHandlers.HawlApp.postMessage(m)}};"
                + "window.__hawlTheme='" + (night ? "dark" : "light") + "';"
            web.configuration.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            c.load(web, page: c.currentPage ?? page)
        } else if page != c.requestedPage && page != c.currentPage {
            c.load(web, page: page)
        } else if page != c.requestedPage {
            c.requestedPage = page                   // الصفحة المعروضة هي المطلوبة أصلًا
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "HawlApp")
        coordinator.urlObservation = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var urlObservation: NSKeyValueObservation?
        var requestedPage: Int?
        var currentPage: Int?
        var night = false

        func load(_ web: WKWebView, page: Int) {
            requestedPage = page
            let p = max(1, min(Quran.pages, page))
            if let url = URL(string: "hawl://app/__hawl/mushaf-pages-offline.html?page=\(p)") {
                web.load(URLRequest(url: url))
            }
        }

        /** الصفحة تغيّر ?page=N دون إعادة تحميل (history.replaceState): نتابع العنوان */
        func observe(_ web: WKWebView) {
            urlObservation = web.observe(\.url, options: [.new]) { [weak self] w, _ in
                guard let url = w.url,
                      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      let v = items.first(where: { $0.name == "page" })?.value, let p = Int(v) else { return }
                self?.currentPage = p
                Task { @MainActor in AppState.shared.recordRead(page: p) }
            }
        }

        /** رسائل الصفحة: المشاركة كصورة (cmd: share) */
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let str = message.body as? String,
                  let data = str.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["cmd"] as? String) == "share" else { return }
            var items: [Any] = []
            if let files = obj["files"] as? [[String: Any]] {
                for f in files {
                    if let b64 = f["data"] as? String, let bytes = Data(base64Encoded: b64), let img = UIImage(data: bytes) {
                        items.append(img)
                    }
                }
            }
            if let t = obj["text"] as? String, !t.isEmpty { items.append(t) }
            if !items.isEmpty { Task { @MainActor in Share.present(items) } }
        }

        /** الروابط الخارجية تُفتح في المتصفح */
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.allow) }
            if url.scheme == HawlSchemeHandler.scheme || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
                return decisionHandler(.allow)
            }
            if action.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
    }
}

/** صفحة من الموقع داخل التطبيق (الاستماع، الأذكار، الترجمات…) */
struct WebPage: UIViewRepresentable {
    var url: URL
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        // العلامة نفسها التي يرسلها تطبيق أندرويد: الموقع يخفي ترويسته داخل التطبيق
        cfg.applicationNameForUserAgent = "HawlalaalamApp"
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebPage

        init(_ parent: WebPage) { self.parent = parent }

        @objc func reload(_ sender: UIRefreshControl) {
            (sender.superview?.superview as? WKWebView)?.reload()
            sender.endRefreshing()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.loading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.loading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.loading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.loading = false }
        }

        /** روابط خارج الموقع (واتساب، يوتيوب…) تُفتح في تطبيقها أو المتصفح */
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return decisionHandler(.allow) }
            let host = url.host?.lowercased() ?? ""
            let ours = host.hasSuffix("7awlalaalam.com")
            if (scheme == "http" || scheme == "https") && (ours || action.targetFrame?.isMainFrame == false) {
                return decisionHandler(.allow)
            }
            if scheme == "about" || scheme == "blob" || scheme == "data" { return decisionHandler(.allow) }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}

/** صفحة موقع بعنوان وشريط تحميل، داخل NavigationStack */
struct WebScreen: View {
    var title: String
    var url: URL
    @State private var loading = true

    var body: some View {
        WebPage(url: url, loading: $loading)
            .overlay(alignment: .top) {
                if loading { ProgressView().progressViewStyle(.linear).tint(Palette.goldDeep) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Palette.page)
    }
}
