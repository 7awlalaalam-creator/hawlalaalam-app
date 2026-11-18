import SwiftUI

/**
 * «من الموقع»: خدمات وإعلان يُدارون من صفحة الإدارة في الموقع (api/v1/app-services)،
 * فتظهر في «الأدوات» و«اليوم» دون تحديث التطبيق (نفس SiteServices في أندرويد).
 * يُحفظ آخر رد محليًا؛ وإن لم تكن واجهة الموقع جاهزة تُقرأ قائمة تجريبية من مستودع GitHub.
 */
struct SiteItem: Identifiable, Hashable {
    let id: String, title: String, icon: String, url: URL, isNew: Bool
    var iconURL: URL? = nil      // icon_url: صورة PNG مربعة بدل الإيموجي إن وُجدت
    var desc: String = ""        // وصف قصير اختياري يظهر في الخانة الكبيرة (الخدمة الأولى)
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
    func refresh(force: Bool = false) async {
        if !force, Date().timeIntervalSince1970 - Store.d.double(forKey: kAt) < 120 { return }
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
            let iu = (s["icon_url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let iconURL = iu.hasPrefix("https://") ? URL(string: iu) : nil
            let dAr = s["desc"] as? String ?? "", dEn = s["desc_en"] as? String ?? ""
            out.append(SiteItem(id: id.isEmpty ? u.absoluteString : id, title: title, icon: s["icon"] as? String ?? "✦", url: u, isNew: isNew,
                                iconURL: iconURL, desc: Lang.en && !dEn.isEmpty ? dEn : dAr))
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

/** أيقونة خدمة: صورة icon_url بزوايا دائرية، والإيموجي حتى تُحمَّل أو إن لم توجد */
struct SiteIcon: View {
    let item: SiteItem
    var size: CGFloat
    var body: some View {
        Group {
            if let iu = item.iconURL {
                AsyncImage(url: iu) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
                    } else {
                        Text(item.icon).font(.system(size: size * 0.62))
                    }
                }
            } else {
                Text(item.icon).font(.system(size: size * 0.62))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct NewBadge: View {
    var body: some View {
        Text(L("جديد")).font(AppFont.ui(9, 700)).foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color(hex: 0xC94A3A)))
            .padding(6)
    }
}

/** خانة «من الموقع» الصغيرة: شعار واسم في سطر */
struct SiteTile: View {
    let item: SiteItem
    var body: some View {
        VStack(spacing: 5) {
            SiteIcon(item: item, size: 38)
            Text(item.title).font(AppFont.ui(11, 700)).foregroundColor(Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card(radius: 18)
        .overlay(alignment: .topTrailing) { if item.isNew { NewBadge() } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + (item.isNew ? "، " + L("جديد") : ""))
    }
}

/** الخانة الكبيرة: الخدمة الأولى بلون الهوية مع وصفها وزر «افتح» */
struct SiteBigTile: View {
    let item: SiteItem
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SiteIcon(item: item, size: 50)
            Spacer(minLength: 4)
            Text(item.title).font(AppFont.ui(16, 700)).foregroundColor(.white).lineLimit(2)
            if !item.desc.isEmpty {
                Text(item.desc).font(AppFont.ui(11)).foregroundColor(Palette.onDarkMuted).lineLimit(1).truncationMode(.tail)
            }
            Text(L("افتح ‹")).font(AppFont.ui(12, 700)).foregroundColor(Color(hex: 0x2B1D06))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 11).fill(LinearGradient(colors: [Color(hex: 0xF3DFA8), Color(hex: 0xC9A876)],
                                                                                 startPoint: .top, endPoint: .bottom)))
                .padding(.top, 5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .overlay(alignment: .topTrailing) { if item.isNew { NewBadge() } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + (item.desc.isEmpty ? "" : "، " + item.desc) + (item.isNew ? "، " + L("جديد") : ""))
    }
}

/**
 * قسم «✦ من الموقع» في الأدوات بتخطيط «بينتو»: الخدمة الأولى خانة كبيرة (عرض خانتين وارتفاع خانتين)
 * وبجانبها أربع صغيرة؛ وما زاد صفوف من أربع تحتها. بلا سحب جانبي ولا فراغات.
 */
struct SiteServicesSection: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var svc = SiteServices.shared
    private let cell: CGFloat = 82, gap: CGFloat = 8

    @ViewBuilder private func link<V: View>(_ it: SiteItem, @ViewBuilder _ label: () -> V) -> some View {
        if SiteServices.isSite(it.url) {
            NavigationLink(value: Screen.web(it.url, it.title)) { label() }
                .simultaneousGesture(TapGesture().onEnded { svc.markOpened(it.id) })
        } else {
            Button { svc.markOpened(it.id); SiteServices.open(it.url, title: it.title, state: state) } label: { label() }
        }
    }

    var body: some View {
        let items = svc.items
        if !items.isEmpty {
            let rest = min(4, items.count - 1)
            let extra = Array(items.dropFirst(1 + rest))
            VStack(alignment: .leading, spacing: gap) {
                HStack {
                    Text(L("✦ من الموقع")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                    Spacer()
                    Text(L("يُحدَّث تلقائيًا")).font(AppFont.ui(11)).foregroundColor(Palette.muted)
                }
                .padding(.horizontal, 4)
                HStack(spacing: gap) {
                    link(items[0]) { SiteBigTile(item: items[0]) }
                        .frame(maxWidth: .infinity)
                        .frame(height: rest == 0 ? cell : cell * 2 + gap)
                    if rest > 0 {
                        let side = Array(items[1...rest])
                        let rows = rest <= 2 ? 1 : 2
                        VStack(spacing: gap) {
                            ForEach(0..<rows, id: \.self) { r in
                                HStack(spacing: gap) {
                                    ForEach(0..<2, id: \.self) { k in
                                        let i = r * 2 + k
                                        if i < side.count { link(side[i]) { SiteTile(item: side[i]) } }
                                        else { Color.clear }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: cell * 2 + gap)
                    }
                }
                .buttonStyle(.plain)
                if !extra.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 4), spacing: gap) {
                        ForEach(extra) { it in link(it) { SiteTile(item: it) }.frame(height: cell) }
                    }
                    .buttonStyle(.plain)
                }
            }
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
