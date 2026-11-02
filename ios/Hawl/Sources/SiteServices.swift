import SwiftUI

/**
 * «من الموقع»: خدمات وإعلان يُدارون من صفحة الإدارة في الموقع (api/v1/app-services)،
 * فتظهر في «الأدوات» و«اليوم» دون تحديث التطبيق (نفس SiteServices في أندرويد).
 * يُحفظ آخر رد محليًا؛ وإن لم تكن واجهة الموقع جاهزة تُقرأ قائمة تجريبية من مستودع GitHub.
 */
struct SiteItem: Identifiable, Hashable {
    let id: String, title: String, icon: String, url: URL, isNew: Bool
}

struct SiteNotice: Hashable {
    let id: String, title: String, body: String, button: String, url: URL?
}

@MainActor
final class SiteServices: ObservableObject {
    static let shared = SiteServices()
    private static let fallback = URL(string: "https://raw.githubusercontent.com/7awlalaalam-creator/hawlalaalam-app/main/data/app-services.json")!
    private let kJSON = "svc_json", kAt = "svc_at", kClosed = "svc_closed", kOpened = "svc_opened"

    @Published private(set) var items: [SiteItem] = []
    @Published private(set) var notice: SiteNotice?

    private init() { rebuild() }

    /** تحديث في الخلفية، مرة كل دقيقتين على الأكثر */
    func refresh() async {
        if Date().timeIntervalSince1970 - Store.d.double(forKey: kAt) < 120 { return }
        var txt: String?
        let (code, body) = await SiteAPI.request("app-services")
        if code == 200, Self.valid(body) { txt = body }
        if txt == nil {
            var req = URLRequest(url: Self.fallback, timeoutInterval: 20)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            if let r = try? await URLSession.shared.data(for: req), let s = String(data: r.0, encoding: .utf8), Self.valid(s) { txt = s }
        }
        guard let t = txt else { return }
        Store.d.set(t, forKey: kJSON)
        Store.d.set(Date().timeIntervalSince1970, forKey: kAt)
        rebuild()
    }

    private static func valid(_ s: String) -> Bool {
        guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
        return o["services"] != nil
    }

    private static var today: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Riyadh")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /** يظهر في الآيفون وضمن مدته */
    private static func live(_ o: [String: Any]) -> Bool {
        if let p = o["platforms"] as? [String], !p.isEmpty, !p.contains(where: { $0.lowercased() == "ios" }) { return false }
        let d = today
        if let f = o["from"] as? String, f.count >= 10, d < String(f.prefix(10)) { return false }
        if let t = o["to"] as? String, t.count >= 10, d > String(t.prefix(10)) { return false }
        return true
    }

    private func rebuild() {
        let raw = Store.string(kJSON, "{}")
        let o = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
        let opened = Store.string(kOpened)
        var out: [SiteItem] = []
        for s in (o["services"] as? [[String: Any]] ?? []) where Self.live(s) && out.count < 12 {
            let id = s["id"] as? String ?? ""
            let ar = s["title"] as? String ?? "", en = s["title_en"] as? String ?? ""
            let title = Lang.en && !en.isEmpty ? en : ar
            guard !title.isEmpty, let u = URL(string: s["url"] as? String ?? ""), u.scheme == "https" || u.scheme == "hawlapp" else { continue }
            let isNew = (s["badge"] as? String) == "new" && !opened.contains("|\(id)|")
            out.append(SiteItem(id: id.isEmpty ? u.absoluteString : id, title: title, icon: s["icon"] as? String ?? "✦", url: u, isNew: isNew))
        }
        items = out
        notice = nil
        if let a = o["announcement"] as? [String: Any], Self.live(a) {
            let id = a["id"] as? String ?? "", title = a["title"] as? String ?? ""
            if !id.isEmpty, !title.isEmpty, !Store.string(kClosed).contains("|\(id)|") {
                notice = SiteNotice(id: id, title: title, body: a["body"] as? String ?? "", button: a["button"] as? String ?? "",
                                    url: URL(string: a["url"] as? String ?? ""))
            }
        }
    }

    func close(_ n: SiteNotice) {
        Store.d.set(String(("|\(n.id)|" + Store.string(kClosed)).prefix(400)), forKey: kClosed)
        rebuild()
    }

    /** صفحات الموقع تُفتح داخل التطبيق، وغيرها في المتصفح */
    func markOpened(_ id: String) {
        let s = Store.string(kOpened)
        guard !s.contains("|\(id)|") else { return }
        Store.d.set(String(("|\(id)|" + s).prefix(400)), forKey: kOpened)
        rebuild()
    }

    static func isSite(_ u: URL) -> Bool { ["7awlalaalam.com", "www.7awlalaalam.com"].contains(u.host ?? "") && appLink(u) == nil }

    /** شاشة في التطبيق نفسه: hawlapp://tools ...، وصفحة «كل الأدوات» في الموقع تفتح «الأدوات» */
    static func appLink(_ u: URL) -> URL? {
        if u.scheme == "hawlapp" { return u }
        if u.path.hasSuffix("/all-tools.html") { return URL(string: "hawlapp://tools") }
        return nil
    }

    /** يفتح الرابط حيث يجب: شاشة التطبيق، أو صفحة الموقع داخله، أو المتصفح */
    static func open(_ u: URL, title: String, state: AppState) {
        if let a = appLink(u) { state.open(a); return }
        if isSite(u) { state.show(.web(u, title)) } else { UIApplication.shared.open(u) }
    }
}

/** خانة «من الموقع» (إيموجي واسم وشارة «جديد») */
struct SiteTile: View {
    let item: SiteItem
    var body: some View {
        VStack(spacing: 6) {
            Text(item.icon).font(.system(size: 24)).frame(height: 28)
            Text(item.title).font(AppFont.ui(12, 700)).foregroundColor(.white)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if item.isNew {
                Text(L("جديد")).font(AppFont.ui(9, 700)).foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color(hex: 0xC94A3A)))
                    .offset(x: 4, y: -6)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + (item.isNew ? "، " + L("جديد") : ""))
    }
}

/** قسم «✦ من الموقع» في الأدوات */
struct SiteServicesSection: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var svc = SiteServices.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        if !svc.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("✦ من الموقع")).font(AppFont.ui(14, 700)).foregroundColor(Palette.gold)
                    Spacer()
                    Text(L("يُحدَّث تلقائيًا")).font(AppFont.ui(11)).foregroundColor(Palette.onDarkMuted)
                }
                .padding(.horizontal, 4)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(svc.items) { it in
                        if SiteServices.isSite(it.url) {
                            NavigationLink(value: Screen.web(it.url, it.title)) { SiteTile(item: it) }
                                .simultaneousGesture(TapGesture().onEnded { svc.markOpened(it.id) })
                        } else {
                            Button { svc.markOpened(it.id); SiteServices.open(it.url, title: it.title, state: state) } label: { SiteTile(item: it) }
                        }
                    }
                }
            }
            .padding(12)
            .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
            .padding(.top, 8)
        }
    }
}

/** بطاقة «إعلان من الموقع» أعلى «اليوم»؛ يغلقها المستخدم بـ ✕ فلا تعود */
struct SiteNoticeCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var svc = SiteServices.shared

    var body: some View {
        if let n = svc.notice {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("إعلان من الموقع")).font(AppFont.ui(11)).foregroundColor(.white.opacity(0.85))
                Text(n.title).font(AppFont.ui(17, 700)).foregroundColor(.white).padding(.trailing, 24)
                if !n.body.isEmpty {
                    Text(n.body).font(AppFont.ui(13)).foregroundColor(.white.opacity(0.95)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if n.url != nil {
                    Text((n.button.isEmpty ? L("افتح") : n.button) + "  ‹")
                        .font(AppFont.ui(13, 700)).foregroundColor(Color(hex: 0x7A5A20))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white))
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xC9A24F), Color(hex: 0x7A5A20)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .contentShape(Rectangle())
            .onTapGesture {
                guard let u = n.url else { return }
                SiteServices.open(u, title: n.title, state: state)
            }
            .overlay(alignment: .topTrailing) {
                Button { withAnimation { svc.close(n) } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.9))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(L("إغلاق الإعلان"))
            }
            .padding(.top, 14)
        }
    }
}
