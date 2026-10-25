import SwiftUI
import WebKit

// MARK: - أخبار التطبيق (نفس News.java): كل إشعار من صاحب التطبيق يُحفظ ٢٤ ساعة من وصوله ثم يُحذف

struct NewsItem: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let url: String
    let article: Int
    let at: Double                       // ثوانٍ منذ ١٩٧٠

    var left: Double { max(0, at + News.keep - Date().timeIntervalSince1970) }
}

enum News {
    static let keep: Double = 24 * 3600
    private static let key = "news_box"
    static let readKey = "news_read_at"

    /** رقم المقالة من رابطها (article.php?id=50 أو /مقالة-50-…html) */
    static func articleID(_ url: String) -> Int {
        let s = url.removingPercentEncoding ?? url
        for p in ["article\\.php\\?id=([0-9]+)", "مقالة-([0-9]+)"] {
            if let r = s.range(of: p, options: .regularExpression) {
                let digits = s[r].filter(\.isNumber)
                if let n = Int(digits) { return n }
            }
        }
        return 0
    }

    private static func raw() -> [[String: Any]] {
        guard let d = Store.d.data(forKey: key),
              let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return a
    }

    private static func save(_ a: [[String: Any]]) {
        if let d = try? JSONSerialization.data(withJSONObject: a) { Store.d.set(d, forKey: key) }
    }

    static func add(id: String, title: String, body: String, url: String, article: Int) {
        guard !id.isEmpty else { return }
        let old = raw()
        if old.contains(where: { ($0["id"] as? String) == id }) { return }      // وصل من قبل: لا نجدّد مدته
        let now = Date().timeIntervalSince1970
        var out: [[String: Any]] = [["id": id, "t": title, "b": body, "u": url,
                                     "a": article > 0 ? article : articleID(url), "at": now]]
        for x in old where out.count < 40 {
            if now - ((x["at"] as? Double) ?? 0) < keep { out.append(x) }
        }
        save(out)
        Task { @MainActor in AppState.shared.newsChanged += 1 }
    }

    static func items() -> [NewsItem] {
        let now = Date().timeIntervalSince1970
        let a = raw()
        let live = a.filter { now - (($0["at"] as? Double) ?? 0) < keep }
        if live.count != a.count { save(live) }
        return live.map {
            NewsItem(id: $0["id"] as? String ?? "", title: $0["t"] as? String ?? "", body: $0["b"] as? String ?? "",
                     url: $0["u"] as? String ?? "", article: ($0["a"] as? Int) ?? 0, at: ($0["at"] as? Double) ?? 0)
        }
    }

    static func unread() -> Int {
        let seen = Store.d.double(forKey: readKey)
        return items().filter { $0.at > seen }.count
    }

    static func markRead() { Store.d.set(Date().timeIntervalSince1970, forKey: readKey) }

    static func ago(_ at: Double) -> String {
        let m = Int(max(0, Date().timeIntervalSince1970 - at) / 60)
        if m < 1 { return "الآن" }
        if m < 60 { return "قبل " + count(m, "دقيقة", "دقيقتين", "دقائق") }
        return "قبل " + count(m / 60, "ساعة", "ساعتين", "ساعات")
    }

    static func left(_ it: NewsItem) -> String {
        let m = Int(it.left / 60)
        if m < 60 { return "يختفي بعد " + count(max(1, m), "دقيقة", "دقيقتين", "دقائق") }
        return "يختفي بعد " + count(m / 60, "ساعة", "ساعتين", "ساعات")
    }

    private static func count(_ n: Int, _ one: String, _ two: String, _ few: String) -> String {
        if n == 1 { return one }
        if n == 2 { return two }
        return ar(n) + " " + (n <= 10 ? few : one)
    }
}

struct NewsView: View {
    @EnvironmentObject var state: AppState
    @State private var items: [NewsItem] = []
    @State private var seenBefore: Double = Store.d.double(forKey: News.readKey)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("تبقى الأخبار هنا ٢٤ ساعة، ثم تُحذف تلقائيًا.", systemImage: "clock")
                    .font(AppFont.ui(13, 500)).foregroundColor(Palette.goldKey)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.chip))
                if items.isEmpty {
                    Text("لا توجد أخبار الآن.\nحين يصل إشعار جديد من التطبيق يظهر هنا.")
                        .font(AppFont.ui(15)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.top, 50)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                    card(it, dark: i == 0)
                }
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("أخبار التطبيق")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            items = News.items()
            News.markRead()
            state.newsChanged += 1
        }
    }

    @ViewBuilder private func card(_ it: NewsItem, dark: Bool) -> some View {
        let ink: Color = dark ? .white : Palette.ink
        let soft: Color = dark ? Palette.onDarkMuted : Palette.muted
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if it.at > seenBefore { Circle().fill(Color(hex: 0xC4462F)).frame(width: 8, height: 8) }
                Text(it.article > 0 ? "مقال جديد" : "من صاحب التطبيق").font(AppFont.ui(12, 700))
                    .foregroundColor(dark ? Palette.gold : Palette.goldDeep)
                Spacer()
                Text(News.ago(it.at)).font(AppFont.ui(12)).foregroundColor(soft)
            }
            if !it.title.isEmpty { Text(it.title).font(AppFont.ui(18, 700)).foregroundColor(ink) }
            if !it.body.isEmpty {
                Text(it.body).font(AppFont.ui(14)).foregroundColor(dark ? Palette.onDarkSoft : Palette.muted).lineSpacing(4)
            }
            HStack {
                if target(it) != nil { Text(it.article > 0 ? "اقرأ المقال" : "افتح").font(AppFont.ui(13, 700)).foregroundColor(ink) }
                Spacer()
                Text(News.left(it)).font(AppFont.ui(12, it.left < 6 * 3600 ? 700 : 400))
                    .foregroundColor(it.left < 6 * 3600 && !dark ? Color(hex: 0xB3412F) : soft)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if dark { content.background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))) }
            else { content.card() }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let t = target(it) { t() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(target(it) != nil ? .isButton : [])
    }

    private func target(_ it: NewsItem) -> (() -> Void)? {
        if it.article > 0 { return { state.show(.article(it.article, it.url)) } }
        if let u = URL(string: it.url), Links.isOurs(u) { return { state.open(u) } }
        return nil
    }
}

// MARK: - المقالات (نفس Articles.java): من articles-api.php، وآخر ٢٠ مقالة محفوظة للقراءة دون إنترنت

struct ArticleItem: Identifiable, Hashable {
    let id: Int
    let title, category, image, excerpt, date, url: String
    let minutes: Int
    let html: String?

    init(_ o: [String: Any]) {
        id = (o["id"] as? Int) ?? Int("\(o["id"] ?? "")") ?? 0
        title = o["title"] as? String ?? ""
        category = o["category"] as? String ?? ""
        image = o["image"] as? String ?? ""
        excerpt = o["excerpt"] as? String ?? ""
        date = o["date"] as? String ?? ""
        url = o["url"] as? String ?? ""
        minutes = max(1, o["minutes"] as? Int ?? 1)
        html = o["html"] as? String
    }

    var readTime: String {
        minutes == 1 ? "دقيقة قراءة" : minutes == 2 ? "دقيقتا قراءة" : ar(minutes) + (minutes <= 10 ? " دقائق" : " دقيقة") + " قراءة"
    }

    var day: String {
        let m = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
        let p = date.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return "" }
        return ar(p[2]) + " " + m[p[1] - 1]
    }

    var meta: String { [category, day, readTime].filter { !$0.isEmpty }.joined(separator: " · ") }
}

enum Articles {
    static let api = Links.homeString + "articles-api.php"
    static let keepOffline = 20

    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("articles")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func json(_ data: Data?) -> [String: Any]? {
        guard let d = data else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    private static func fetch(_ s: String) async -> Data? {
        guard let u = URL(string: s) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 20)
        req.setValue(WebConfig.userAgentMark, forHTTPHeaderField: "User-Agent")
        guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode ?? 0 < 400 else { return nil }
        return d
    }

    static func cachedList() -> [String: Any]? { json(try? Data(contentsOf: dir.appendingPathComponent("list.json"))) }

    /** يجلب القائمة ويحفظها، ويجلب نص آخر المقالات؛ nil عند الفشل */
    static func refresh() async -> [String: Any]? {
        let stamp = Int(Date().timeIntervalSince1970 / 300)
        guard let d = await fetch(api + "?limit=60&t=\(stamp)"), let o = json(d), let arr = o["articles"] as? [[String: Any]] else { return nil }
        try? d.write(to: dir.appendingPathComponent("list.json"), options: .atomic)
        let ids = arr.prefix(keepOffline).compactMap { ($0["id"] as? Int) ?? Int("\($0["id"] ?? "")") }
        Task.detached(priority: .utility) { await prefetch(ids) }           // القائمة تظهر فورًا، والنصوص تُحفظ بعدها
        return o
    }

    /** يحفظ نص آخر المقالات للقراءة دون إنترنت، ويحذف ما خرج منها */
    private static func prefetch(_ ids: [Int]) async {
        var keep: Set<String> = ["list.json"]
        for id in ids {
            keep.insert("\(id).json")
            if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id).json").path) { _ = await article(id) }
        }
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(f) && !f.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    /** مقالة بنصها: من الجهاز أولًا، ثم من الموقع */
    static func article(_ id: Int) async -> ArticleItem? {
        let f = dir.appendingPathComponent("\(id).json")
        if let o = json(try? Data(contentsOf: f)) { return ArticleItem(o) }
        guard let d = await fetch(api + "?id=\(id)"), let o = json(d), (o["id"] as? Int) == id else { return nil }
        try? d.write(to: f, options: .atomic)
        return ArticleItem(o)
    }
}

struct ArticlesView: View {
    @EnvironmentObject var state: AppState
    @State private var data: [String: Any]? = Articles.cachedList()
    @State private var loading = true
    @State private var failed = false
    @State private var category = ""

    private var all: [ArticleItem] { ((data?["articles"] as? [[String: Any]]) ?? []).map(ArticleItem.init) }
    private var cats: [String] { (data?["categories"] as? [String]) ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if all.isEmpty {
                    Text(loading ? "جارٍ جلب المقالات…" : failed ? "تحتاج اتصالًا بالإنترنت لأول مرة لجلب المقالات" : "لا توجد مقالات بعد")
                        .font(AppFont.ui(15)).foregroundColor(Palette.muted).frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    if cats.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach([""] + cats, id: \.self) { c in
                                    let on = c == category
                                    Button { category = c } label: {
                                        Text(c.isEmpty ? "الكل" : c).font(AppFont.ui(14, 700))
                                            .foregroundColor(on ? .white : Palette.ink)
                                            .padding(.horizontal, 16).frame(minHeight: 38)
                                            .background(Capsule().fill(on ? Palette.primary : Palette.card))
                                            .overlay(Capsule().stroke(on ? Color.clear : Palette.line, lineWidth: 1))
                                    }
                                    .accessibilityAddTraits(on ? .isSelected : [])
                                }
                            }
                        }
                    }
                    let shown = all.filter { category.isEmpty || $0.category == category }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, a in
                        NavigationLink(value: Screen.article(a.id, a.url)) {
                            if i == 0 { featured(a) } else { row(a) }
                        }
                        .buttonStyle(.plain)
                    }
                    Text(failed ? "أنت دون إنترنت: تظهر المقالات المحفوظة على جوالك"
                         : "آخر " + ar(Articles.keepOffline) + " مقالًا محفوظة للقراءة دون إنترنت")
                        .font(AppFont.ui(12)).foregroundColor(Palette.muted).frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("المقالات")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let fresh = await Articles.refresh()
            loading = false
            if let f = fresh { data = f } else { failed = true }
        }
    }

    private func featured(_ a: ArticleItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(a.meta).font(AppFont.ui(12, 700)).foregroundColor(Palette.gold)
            Text(a.title).font(AppFont.amiri(22)).foregroundColor(.white).multilineTextAlignment(.leading)
            if !a.excerpt.isEmpty {
                Text(a.excerpt).font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted).lineLimit(3).lineSpacing(3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
    }

    private func row(_ a: ArticleItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(a.meta).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep)
            Text(a.title).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink).multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 16)
    }
}

struct ArticleView: View {
    @EnvironmentObject var state: AppState
    let id: Int
    let url: String
    @State private var item: ArticleItem?
    @State private var done = false
    @AppStorage("article_font", store: Store.d) private var size = 18
    @Environment(\.colorScheme) private var scheme

    private var link: URL { URL(string: url) ?? Links.site("article.php?id=\(id)") }

    var body: some View {
        VStack(spacing: 0) {
            if let a = item, let html = a.html {
                ArticleWeb(html: page(a, html), onLink: open)
            } else {
                Text(done ? "تعذّر فتح المقال. تحتاج اتصالًا بالإنترنت لأول مرة، أو افتحه في الموقع." : "جارٍ فتح المقال…")
                    .font(AppFont.ui(15)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 8) {
                Button { Share.present([shareText]) } label: { Pill(title: "مشاركة المقال", systemImage: "square.and.arrow.up", primary: true) }
                Button { Browser.open(link) } label: { Pill(title: "في الموقع", systemImage: "safari") }
                    .frame(maxWidth: 130)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Palette.ivory)
        }
        .background(Palette.ivory.ignoresSafeArea())
        .navigationTitle("المقالات")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("أ-") { size = max(14, size - 2) }.accessibilityLabel("تصغير الخط")
                Button("أ+") { size = min(28, size + 2) }.accessibilityLabel("تكبير الخط")
            }
        }
        .task {
            item = await Articles.article(id)
            done = true
        }
    }

    private var shareText: String {
        let t = item?.title ?? ""
        return (t.isEmpty ? "" : "«\(t)»\n") + (url.removingPercentEncoding ?? url) + "\n\nمن تطبيق «القرآن حول العالم»: https://7awlalaalam.com/app"
    }

    private func open(_ u: URL) {
        let other = News.articleID(u.absoluteString)
        if other > 0 && other != id { state.show(.article(other, u.absoluteString)) } else { state.open(u) }
    }

    private func hex(_ c: Color) -> String {
        let ui = UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private func page(_ a: ArticleItem, _ html: String) -> String {
        """
        <!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><style>
        html{-webkit-text-size-adjust:100%}
        body{margin:0;padding:18px 20px 28px;background:\(hex(Palette.ivory));color:\(hex(Palette.ink));
        font-family:'Tajawal',-apple-system,sans-serif;font-size:\(size)px;line-height:1.95;word-wrap:break-word}
        .m{display:inline-block;font-size:12px;font-weight:700;color:\(hex(Palette.goldDeep));background:\(hex(Palette.chip));border-radius:10px;padding:2px 10px;line-height:1.8}
        h1{font-family:'Amiri Quran','Amiri',serif;font-size:\(size + 11)px;line-height:1.5;margin:12px 0 10px}
        h2,h3{font-size:\(size + 2)px;line-height:1.6;margin:22px 0 6px}
        p{margin:0 0 14px}a{color:\(hex(Palette.goldDeep))}
        blockquote{margin:14px 0;padding:14px 16px;border-radius:14px;background:\(hex(Palette.dark));color:#FFFFFF;
        font-family:'Amiri Quran','Amiri',serif;font-size:\(size + 3)px;text-align:center;line-height:2}
        ul,ol{padding-inline-start:22px}li{margin:4px 0}
        </style></head><body><span class="m">\(esc(a.meta))</span><h1>\(esc(a.title))</h1>\(html)</body></html>
        """
    }
}

/** نص المقال فقط: بلا سكربتات، والروابط تُفتح خارج العرض */
struct ArticleWeb: UIViewRepresentable {
    let html: String
    let onLink: (URL) -> Void

    func makeCoordinator() -> Coord { Coord(onLink) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.navigationDelegate = context.coordinator
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        context.coordinator.onLink = onLink
        if context.coordinator.last != html {
            context.coordinator.last = html
            w.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        }
    }

    final class Coord: NSObject, WKNavigationDelegate {
        var onLink: (URL) -> Void
        var last = ""
        init(_ f: @escaping (URL) -> Void) { onLink = f }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let u = action.request.url {
                decisionHandler(.cancel)
                if ["http", "https"].contains(u.scheme ?? "") { onLink(u) }
                return
            }
            decisionHandler(.allow)
        }
    }
}
