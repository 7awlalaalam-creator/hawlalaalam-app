import SwiftUI

// MARK: - بيانات القرّاء والإذاعات (mp3quran.net API v3، نفس مصدر صفحة الموقع)

/** رقم قد يصل نصًّا أو عددًا من الخادم */
private struct FlexInt: Codable, Hashable {
    let v: Int
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let i = try? c.decode(Int.self) { v = i }
        else if let s = try? c.decode(String.self), let i = Int(s) { v = i }
        else { v = 0 }
    }
    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(v) }
}

struct Moshaf: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let server: String
    let surahTotal: Int
    let surahs: [Int]

    private enum K: String, CodingKey { case id, name, server, surah_total, surah_list }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = (try? c.decode(FlexInt.self, forKey: .id).v) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        server = (try? c.decode(String.self, forKey: .server)) ?? ""
        surahTotal = (try? c.decode(FlexInt.self, forKey: .surah_total).v) ?? 0
        let list = (try? c.decode(String.self, forKey: .surah_list)) ?? ""
        var seen = Set<Int>()   // رقم مكرر في القائمة يُسقط القائمة الكسولة في SwiftUI
        surahs = list.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...114).contains($0) }.filter { seen.insert($0).inserted }
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(server, forKey: .server)
        try c.encode(surahTotal, forKey: .surah_total)
        try c.encode(surahs.map(String.init).joined(separator: ","), forKey: .surah_list)
    }

    /** رابط السورة: الخادم + رقم السورة بثلاث خانات */
    func url(_ surah: Int) -> String {
        let base = server.hasSuffix("/") ? server : server + "/"
        return base + String(format: "%03d", surah) + ".mp3"
    }

    /** «حفص عن عاصم - مرتل» ← «حفص · مرتل» */
    var shortName: String {
        name.replacingOccurrences(of: "رواية ", with: "").replacingOccurrences(of: " - ", with: " · ")
    }
}

struct Reciter: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let moshaf: [Moshaf]

    private enum K: String, CodingKey { case id, name, moshaf }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = (try? c.decode(FlexInt.self, forKey: .id).v) ?? 0
        name = ((try? c.decode(String.self, forKey: .name)) ?? "").trimmingCharacters(in: .whitespaces)
        // رواية حفص أولًا، ثم الأكمل
        moshaf = ((try? c.decode([Moshaf].self, forKey: .moshaf)) ?? []).filter { !$0.server.isEmpty && !$0.surahs.isEmpty }
            .sorted { a, b in
                let ha = a.name.contains("حفص"), hb = b.name.contains("حفص")
                return ha != hb ? ha : a.surahs.count > b.surahs.count
            }
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(moshaf, forKey: .moshaf)
    }

    /** الحرف في الشارة: أول حرف من الاسم، وإن كان ألفًا (إ أ آ ا) فأول حرف من آخر كلمة (حتى لا تبدو «إ» علامة تعجب) */
    var initial: String {
        let alef: Set<Character> = ["ا", "أ", "إ", "آ"]
        guard let f = name.first else { return "ق" }
        if !alef.contains(f) { return String(f) }
        // «إبراهيم الأخضر» ← «خ»: من آخر كلمة دون «ال»
        for w in name.split(separator: " ").reversed() {
            let core = w.hasPrefix("ال") && w.count > 2 ? w.dropFirst(2) : Substring(w)
            if let c = core.first, !alef.contains(c) { return String(c) }
        }
        return String(name.first(where: { !alef.contains($0) && $0 != " " }) ?? f)
    }
    var surahCount: Int { moshaf.map { $0.surahs.count }.max() ?? 0 }
}

struct Radio: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let url: String

    private enum K: String, CodingKey { case id, name, url }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = (try? c.decode(FlexInt.self, forKey: .id).v) ?? 0
        name = ((try? c.decode(String.self, forKey: .name)) ?? "").trimmingCharacters(in: .whitespaces)
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
    }
}

/** تحميل القائمتين مع حفظهما على الجهاز (تُحدَّث كل ٣ أيام، وتعمل دون اتصال بعد أول مرة) */
@MainActor
final class ListenCatalog: ObservableObject {
    static let shared = ListenCatalog()

    @Published private(set) var reciters: [Reciter] = []
    @Published private(set) var radios: [Radio] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var favorites: [Int] = []

    fileprivate struct RecitersDoc: Codable { let reciters: [Reciter] }
    fileprivate struct RadiosDoc: Codable { let radios: [Radio] }

    private static let api = "https://mp3quran.net/api/v3/"
    private static let maxAge: Double = 3 * 24 * 3600

    private init() {
        favorites = (Store.d.array(forKey: "listen_favs") as? [Int]) ?? []
        // القائمة المحفوظة (قرابة ١ م.ب) تُقرأ وتُفك في الخلفية، لا على خيط الواجهة
        let rf = Self.file("reciters"), of = Self.file("radios")
        Task.detached(priority: .userInitiated) {
            let r = (try? Data(contentsOf: rf)).flatMap { try? JSONDecoder().decode(RecitersDoc.self, from: $0) }.map { ListenCatalog.sorted($0.reciters) }
            let o = (try? Data(contentsOf: of)).flatMap { try? JSONDecoder().decode(RadiosDoc.self, from: $0) }.map { $0.radios.filter { !$0.url.isEmpty } }
            await MainActor.run {
                let c = ListenCatalog.shared
                if c.reciters.isEmpty, let r = r { c.reciters = r }
                if c.radios.isEmpty, let o = o { c.radios = o }
            }
        }
    }

    /** بعد استعادة نسخة احتياطية */
    func reloadFavorites() { favorites = (Store.d.array(forKey: "listen_favs") as? [Int]) ?? [] }

    nonisolated private static func file(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("listen", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent(name + ".json")
    }

    private static func age(_ name: String) -> Double {
        let a = (try? FileManager.default.attributesOfItem(atPath: file(name).path)[.modificationDate] as? Date) ?? .distantPast
        return Date().timeIntervalSince(a)
    }

    nonisolated fileprivate static func sorted(_ l: [Reciter]) -> [Reciter] {
        l.filter { !$0.moshaf.isEmpty && !$0.name.isEmpty }
            .sorted { $0.name.compare($1.name, locale: Locale(identifier: "ar")) == .orderedAscending }
    }

    func reciter(_ id: Int) -> Reciter? { reciters.first { $0.id == id } }

    func load(force: Bool = false) async {
        if loading { return }
        let need = force || reciters.isEmpty || radios.isEmpty || Self.age("reciters") > Self.maxAge
        guard need else { return }
        loading = true
        failed = false
        async let r = Self.fetch("reciters?language=ar")
        async let o = Self.fetch("radios?language=ar")
        let (rd, od) = await (r, o)
        if let d = rd, let doc = try? JSONDecoder().decode(RecitersDoc.self, from: d), !doc.reciters.isEmpty {
            reciters = Self.sorted(doc.reciters)
            try? d.write(to: Self.file("reciters"))
        }
        if let d = od, let doc = try? JSONDecoder().decode(RadiosDoc.self, from: d), !doc.radios.isEmpty {
            radios = doc.radios.filter { !$0.url.isEmpty }
            try? d.write(to: Self.file("radios"))
        }
        failed = reciters.isEmpty
        loading = false
    }

    private static func fetch(_ path: String) async -> Data? {
        guard let u = URL(string: api + path) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 25)
        req.setValue(WebConfig.userAgentMark, forHTTPHeaderField: "User-Agent")
        guard let r = try? await URLSession.shared.data(for: req),
              ((r.1 as? HTTPURLResponse)?.statusCode ?? 200) < 400 else { return nil }
        return r.0
    }

    func isFavorite(_ id: Int) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: Int) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.append(id) }
        Store.d.set(favorites, forKey: "listen_favs")
    }

    /** القارئ الذي يُستمع به إن لم يُختر: آخر من استمعت له، ثم أول المفضّلين */
    var preferred: (Reciter, Moshaf)? {
        if let l = AudioPlayer.last, let r = reciter(l.track.reciterID),
           let m = r.moshaf.first(where: { $0.id == l.track.moshafID }) ?? r.moshaf.first { return (r, m) }
        for f in favorites { if let r = reciter(f), let m = r.moshaf.first { return (r, m) } }
        return nil
    }

    /** قائمة سور القارئ للتشغيل المتتالي */
    static func tracks(_ r: Reciter, _ m: Moshaf) -> [Track] {
        m.surahs.map { s in
            Track(url: m.url(s), title: "سورة " + Quran.surahName(s), reciter: r.name, reciterID: r.id, moshafID: m.id, surah: s)
        }
    }
}

/** «سورة واحدة»، «سورتان»، «٥ سور»، «١١٤ سورة» */
func surahsText(_ n: Int) -> String {
    if n == 1 { return "سورة واحدة" }
    if n == 2 { return "سورتان" }
    return ar(n) + (n >= 3 && n <= 10 ? " سور" : " سورة")
}

/** للبحث: دون تشكيل، والهمزات والتاء المربوطة والألف المقصورة موحّدة */
func normalizeArabic(_ s: String) -> String {
    var out = ""
    for u in s.unicodeScalars {
        switch u.value {
        case 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x0640: continue
        case 0x0622, 0x0623, 0x0625, 0x0671: out.unicodeScalars.append("ا")
        case 0x0629: out.unicodeScalars.append("ه")
        case 0x0649: out.unicodeScalars.append("ي")
        case 0x0624: out.unicodeScalars.append("و")
        case 0x0626: out.unicodeScalars.append("ي")
        default: out.unicodeScalars.append(u)
        }
    }
    return out.lowercased()
}

extension Quran {
    /** السور المدنية في مصحف المدينة؛ والباقي مكية */
    static let madani: Set<Int> = [2, 3, 4, 5, 8, 9, 13, 22, 24, 33, 47, 48, 49, 55, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 76, 98, 99, 110]

    /** «مكية · ٧ آيات» */
    static func surahInfo(_ s: Int) -> String {
        guard (1...114).contains(s) else { return "" }
        let n = counts[s - 1]
        let ayat = n >= 3 && n <= 10 ? ar(n) + " آيات" : ar(n) + " آية"
        return (madani.contains(s) ? "مدنية" : "مكية") + " · " + ayat
    }
}

// MARK: - تبويب الاستماع

struct ListenView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var catalog = ListenCatalog.shared
    @ObservedObject private var player = AudioPlayer.shared
    @ObservedObject private var dl = AudioDownloads.shared
    @State private var section = 0
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $section) {
                    Text("القرّاء").tag(0)
                    Text("الإذاعات").tag(1)
                    Text("المحمّلة").tag(2)
                }
                .pickerStyle(.segmented)

                if section != 2 {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(Palette.muted)
                        TextField(section == 0 ? "ابحث عن قارئ…" : "ابحث عن إذاعة…", text: $query)
                            .font(AppFont.ui(15))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Palette.muted) }
                                .accessibilityLabel("مسح البحث")
                        }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 46)
                    .card(radius: 14)
                }

                if section == 0, query.isEmpty, let last = AudioPlayer.last, player.current == nil || player.current == last.track {
                    continueCard(last)
                }

                switch section {
                case 0: recitersList
                case 1: radiosList
                default: downloadsList
                }
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("الاستماع")
        .refreshable { await catalog.load(force: true) }
        .task { await catalog.load() }
        .onChange(of: section) { _ in query = "" }
    }

    private func continueCard(_ l: AudioPlayer.Last) -> some View {
        Button {
            if player.current == l.track { player.toggle() } else { player.resumeLast() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: player.current == l.track && player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Palette.dark)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Palette.gold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("تابع الاستماع").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                    Text(l.track.title + " · " + l.track.reciter).font(AppFont.ui(17, 700)).foregroundColor(.white).lineLimit(1)
                    if l.pos > 0 {
                        Text("من " + PlayerView.clock(l.pos)).font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Palette.dark))
        }
        .buttonStyle(.plain)
    }

    private var filteredReciters: [Reciter] {
        let q = normalizeArabic(query.trimmingCharacters(in: .whitespaces))
        let all = q.isEmpty ? catalog.reciters : catalog.reciters.filter { normalizeArabic($0.name).contains(q) }
        let favs = all.filter { catalog.isFavorite($0.id) }
        return favs + all.filter { !catalog.isFavorite($0.id) }
    }

    @ViewBuilder private var recitersList: some View {
        if catalog.reciters.isEmpty {
            emptyState
        } else {
            let list = filteredReciters
            if list.isEmpty {
                Text("لا يوجد قارئ بهذا الاسم").font(AppFont.ui(15)).foregroundColor(Palette.muted).padding(.top, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, r in
                        if i > 0 { Rectangle().fill(Palette.divider).frame(height: 1) }
                        reciterRow(r)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 2)
                .card()
            }
        }
    }

    private func reciterRow(_ r: Reciter) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: Screen.reciter(r.id)) {
                HStack(spacing: 12) {
                    Text(r.initial).font(AppFont.ui(18, 700)).foregroundColor(Palette.gold)
                        .frame(width: 46, height: 46).background(Circle().fill(Color(hex: 0x1C5249)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.name).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink).lineLimit(1)
                        HStack(spacing: 6) {
                            ForEach(r.moshaf.prefix(2)) { m in
                                Text(m.shortName).font(AppFont.ui(11, 700)).foregroundColor(Palette.goldKey).lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Palette.chip))
                            }
                            if r.moshaf.count > 2 { Text("+" + ar(r.moshaf.count - 2)).font(AppFont.ui(11, 700)).foregroundColor(Palette.muted) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { catalog.toggleFavorite(r.id) } label: {
                Image(systemName: catalog.isFavorite(r.id) ? "heart.fill" : "heart")
                    .font(.system(size: 16)).foregroundColor(catalog.isFavorite(r.id) ? Palette.gold : Palette.muted)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(catalog.isFavorite(r.id) ? "إزالة من المفضّلين" : "أضف إلى المفضّلين")
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var radiosList: some View {
        if catalog.radios.isEmpty {
            emptyState
        } else {
            let q = normalizeArabic(query.trimmingCharacters(in: .whitespaces))
            let list = q.isEmpty ? catalog.radios : catalog.radios.filter { normalizeArabic($0.name).contains(q) }
            LazyVStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, r in
                    if i > 0 { Rectangle().fill(Palette.divider).frame(height: 1) }
                    let on = player.current?.url == r.url
                    Button {
                        if on { player.toggle() }
                        else { player.play(queue: [Track(url: r.url, title: r.name, reciter: "إذاعة مباشرة", radio: true)], start: 0) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dot.radiowaves.left.and.right").foregroundColor(Palette.goldDeep)
                                .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 12).fill(Palette.chip))
                            Text(r.name).font(AppFont.ui(15, 700)).foregroundColor(on ? Palette.goldDeep : Palette.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: on && player.playing ? "pause.circle.fill" : "play.circle")
                                .font(.system(size: 26)).foregroundColor(Palette.goldDeep)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 2)
            .card()
        }
    }

    @ViewBuilder private var downloadsList: some View {
        let done = dl.items.filter { $0.status == .done }
        if done.isEmpty {
            Text("لا توجد تلاوات محمّلة بعد. افتح صفحة أي قارئ واضغط ⬇ بجانب السورة لتستمع إليها دون إنترنت.")
                .font(AppFont.ui(15)).foregroundColor(Palette.ink)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .card(Palette.ivory, border: Palette.ivoryBorder, radius: 16)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(done.enumerated()), id: \.element.id) { i, it in
                    if i > 0 { Rectangle().fill(Palette.divider).frame(height: 1) }
                    let on = player.current?.url == it.url
                    Button {
                        if on { player.toggle() }
                        else {
                            let q = done.map { Track(url: $0.url, title: $0.title, reciter: $0.reciter) }
                            player.play(queue: q, start: i)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "airplane").foregroundColor(Palette.goldDeep)
                                .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 12).fill(Palette.chip))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.title).font(AppFont.ui(15, 700)).foregroundColor(on ? Palette.goldDeep : Palette.ink)
                                Text(it.reciter + " · " + AudioDownloads.mb(it.size)).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: on && player.playing ? "pause.circle.fill" : "play.circle")
                                .font(.system(size: 26)).foregroundColor(Palette.goldDeep)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 2)
            .card()
        }
        NavigationLink(value: Screen.downloads) {
            Pill(title: "إدارة التحميلات", systemImage: "arrow.down.circle", height: 48)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 12) {
            if catalog.loading {
                ProgressView().tint(Palette.goldDeep)
                Text("جارٍ تحميل القائمة…").font(AppFont.ui(14)).foregroundColor(Palette.muted)
            } else {
                Image(systemName: "wifi.slash").font(.system(size: 34)).foregroundColor(Palette.goldDeep)
                Text("تحتاج اتصالًا بالإنترنت لأول مرة").font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                Text("بعدها تبقى القائمة محفوظة على جوالك، والتلاوات المحمّلة تعمل دون إنترنت.")
                    .font(AppFont.ui(13)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
                Button { Task { await catalog.load(force: true) } } label: {
                    Pill(title: "إعادة المحاولة", systemImage: "arrow.clockwise", primary: true)
                }
                .frame(maxWidth: 240)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - صفحة القارئ

struct ReciterView: View {
    let id: Int
    @ObservedObject private var catalog = ListenCatalog.shared
    @ObservedObject private var player = AudioPlayer.shared
    @ObservedObject private var dl = AudioDownloads.shared
    @State private var moshafID: Int?
    @State private var confirmAll = false

    var body: some View {
        Group {
            if let r = catalog.reciter(id) {
                content(r)
            } else {
                ProgressView().tint(Palette.goldDeep).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await catalog.load() }
            }
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ r: Reciter) -> some View {
        let m = r.moshaf.first(where: { $0.id == moshafID }) ?? r.moshaf[0]
        let tracks = ListenCatalog.tracks(r, m)
        let missing = tracks.filter { dl.status($0.url) == .none || dl.status($0.url) == .failed }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 8) {
                    Text(r.initial).font(AppFont.ui(28, 700)).foregroundColor(Palette.gold)
                        .frame(width: 70, height: 70).background(Circle().fill(Color(hex: 0x1C5249)))
                    Text(r.name).font(AppFont.ui(21, 700)).foregroundColor(.white).multilineTextAlignment(.center)
                    Text(m.shortName + " · " + surahsText(m.surahs.count)).font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted)
                    Button { player.play(queue: tracks, start: 0) } label: {
                        Label("استمع للمصحف كاملًا", systemImage: "play.fill")
                            .font(AppFont.ui(15, 700)).foregroundColor(Palette.dark)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Capsule().fill(Palette.gold))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 22).fill(Palette.dark))

                if r.moshaf.count > 1 {
                    Menu {
                        ForEach(r.moshaf) { x in
                            Button { moshafID = x.id } label: { Text(x.name + " (" + ar(x.surahs.count) + ")") }
                        }
                    } label: {
                        HStack {
                            Text("الرواية: " + m.name).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.down").foregroundColor(Palette.goldDeep)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 46).card(radius: 14)
                    }
                }

                HStack(spacing: 8) {
                    Button { catalog.toggleFavorite(r.id) } label: {
                        Pill(title: catalog.isFavorite(r.id) ? "في المفضّلين" : "أضف للمفضّلين",
                             systemImage: catalog.isFavorite(r.id) ? "heart.fill" : "heart", height: 44)
                    }
                    Button { confirmAll = true } label: {
                        Pill(title: missing.isEmpty ? "كلها محمّلة" : "حمّل الكل", systemImage: "arrow.down.circle", height: 44)
                    }
                    .disabled(missing.isEmpty)
                }
                .buttonStyle(.plain)

                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in
                        if i > 0 { Rectangle().fill(Palette.divider).frame(height: 1) }
                        surahRow(t, index: i, all: tracks)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 2)
                .card()
            }
            .padding(16)
        }
        .navigationTitle(r.name)
        .alert("تحميل " + surahsText(missing.count) + "؟", isPresented: $confirmAll) {
            Button("حمّل") { for t in missing { dl.start(url: t.url, title: t.title, reciter: t.reciter) } }
            Button("إلغاء", role: .cancel) { }
        } message: { Text("يُفضّل التحميل عبر شبكة Wi-Fi. تجدها في «المحمّلة» وتعمل دون إنترنت.") }
    }

    private func surahRow(_ t: Track, index: Int, all: [Track]) -> some View {
        let on = player.current?.url == t.url
        return HStack(spacing: 10) {
            Button {
                if on { player.toggle() } else { player.play(queue: all, start: index) }
            } label: {
                HStack(spacing: 12) {
                    StarBadge(text: ar(t.surah))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Quran.surahName(t.surah) + (on ? "  ◂ " + (player.playing ? "يُشغَّل الآن" : "متوقف") : ""))
                            .font(AppFont.ui(15, 700)).foregroundColor(on ? Palette.goldDeep : Palette.ink)
                        Text(Quran.surahInfo(t.surah)).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            downloadButton(t)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func downloadButton(_ t: Track) -> some View {
        switch dl.status(t.url) {
        case .done:
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                .frame(width: 34, height: 34).background(Circle().fill(Palette.gold))
                .accessibilityLabel("محمّلة")
        case .running:
            Text(ar(dl.item(t.url)?.percent ?? 0) + "٪").font(AppFont.ui(11, 700)).foregroundColor(Palette.goldDeep)
                .frame(width: 40, height: 34)
        default:
            Button { dl.start(url: t.url, title: t.title, reciter: t.reciter) } label: {
                Image(systemName: "arrow.down").font(.system(size: 14, weight: .semibold)).foregroundColor(Palette.goldDeep)
                    .frame(width: 34, height: 34).overlay(Circle().stroke(Palette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("تحميل " + t.title)
        }
    }
}

// MARK: - المشغّل المصغّر والكامل

/** شريط يظهر فوق شريط التبويب ما دام هناك تلاوة */
struct MiniPlayerBar: View {
    @ObservedObject private var player = AudioPlayer.shared
    @State private var open = false

    var body: some View {
        if let t = player.current {
            HStack(spacing: 10) {
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(Palette.dark)
                        .frame(width: 40, height: 40).background(Circle().fill(Palette.gold))
                }
                .accessibilityLabel(player.playing ? "إيقاف مؤقت" : "تشغيل")
                Button { open = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(AppFont.ui(14, 700)).foregroundColor(.white).lineLimit(1)
                        Text(subtitle(t)).font(AppFont.ui(11)).foregroundColor(Palette.onDarkMuted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                if player.hasNext {
                    Button { player.next() } label: {
                        Image(systemName: "forward.end.fill").foregroundColor(.white).frame(width: 36, height: 40)
                    }
                    .accessibilityLabel("التالي")
                }
                Button { player.stop() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(Palette.onDarkMuted)
                        .frame(width: 32, height: 40)
                }
                .accessibilityLabel("إغلاق المشغّل")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.dark))
            .padding(.horizontal, 12).padding(.bottom, 6)
            .sheet(isPresented: $open) {
                NowPlayingView().environment(\.layoutDirection, .rightToLeft)
            }
        }
    }

    private func subtitle(_ t: Track) -> String {
        if player.failed { return "تعذّر التشغيل، تحقق من الاتصال" }
        if t.radio { return "بث مباشر" }
        if player.buffering && player.playing { return t.reciter + " · جارٍ التحميل…" }
        var s = t.reciter + " · " + PlayerView.clock(player.position)
        if player.duration > 0 { s += " / " + PlayerView.clock(player.duration) }
        if let at = player.sleepAt { s += " · النوم " + formatTime(at) }
        return s
    }
}

struct NowPlayingView: View {
    @ObservedObject private var player = AudioPlayer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let t = player.current {
                        VStack(spacing: 6) {
                            Image(systemName: t.radio ? "dot.radiowaves.left.and.right" : "headphones")
                                .font(.system(size: 34)).foregroundColor(Palette.gold)
                                .frame(width: 84, height: 84).background(Circle().fill(Color(hex: 0x1C5249)))
                            Text(t.title).font(AppFont.ui(24, 700)).foregroundColor(.white).multilineTextAlignment(.center).padding(.top, 8)
                            Text(t.reciter).font(AppFont.ui(15)).foregroundColor(Palette.onDarkMuted)
                            if !t.radio {
                                Slider(value: Binding(get: { player.position }, set: { player.seek($0) }), in: 0...max(1, player.duration))
                                    .tint(Palette.gold).padding(.top, 14)
                                HStack {
                                    Text(PlayerView.clock(player.position))
                                    Spacer()
                                    Text(PlayerView.clock(player.duration))
                                }
                                .font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted)
                            }
                            HStack(spacing: 26) {
                                Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 22)) }
                                    .disabled(t.radio).accessibilityLabel("السابق")
                                Button { player.skip(-15) } label: { Image(systemName: "gobackward.15").font(.system(size: 24)) }
                                    .disabled(t.radio).accessibilityLabel("رجوع ١٥ ثانية")
                                Button { player.toggle() } label: {
                                    Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 62))
                                }
                                .accessibilityLabel(player.playing ? "إيقاف مؤقت" : "تشغيل")
                                Button { player.skip(15) } label: { Image(systemName: "goforward.15").font(.system(size: 24)) }
                                    .disabled(t.radio).accessibilityLabel("تقديم ١٥ ثانية")
                                Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 22)) }
                                    .disabled(!player.hasNext).accessibilityLabel("التالي")
                            }
                            .foregroundColor(Palette.gold)
                            .padding(.top, 8)
                            if player.failed {
                                Text("تعذّر التشغيل. تحقق من اتصالك بالإنترنت أو حمّل السورة.").font(AppFont.ui(13))
                                    .foregroundColor(Palette.onDarkSoft).multilineTextAlignment(.center)
                            }
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Palette.widgetDark))

                        if !t.radio { options }
                    } else {
                        Text("لا تلاوة الآن").font(AppFont.ui(16)).foregroundColor(Palette.muted).padding(40)
                    }
                }
                .padding(16)
            }
            .background(Palette.page.ignoresSafeArea())
            .navigationTitle("يُشغَّل الآن")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() }.font(AppFont.ui(15, 700)) }
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("سرعة التلاوة").font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
            HStack(spacing: 8) {
                ForEach(AudioPlayer.speeds, id: \.self) { v in
                    Button { player.setSpeed(v) } label: {
                        Text(ar(v == 1 ? "١×" : String(format: "%g×", v).replacingOccurrences(of: ".", with: "٫")))
                            .font(AppFont.ui(14, 700))
                            .foregroundColor(player.speed == v ? .white : Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Capsule().fill(player.speed == v ? Palette.primary : Palette.chip))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("مؤقت النوم").font(AppFont.ui(14, 700)).foregroundColor(Palette.ink).padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach([15, 30, 45, 60], id: \.self) { m in sleepButton(ar(m) + " دقيقة", minutes: m) }
                sleepButton("نهاية السورة", minutes: 0)
                sleepButton("إيقاف المؤقت", minutes: nil)
            }
            if let at = player.sleepAt {
                Text("يتوقف الاستماع الساعة " + formatTime(at)).font(AppFont.ui(13)).foregroundColor(Palette.muted)
            } else if player.sleepAtEnd {
                Text("يتوقف الاستماع في نهاية السورة").font(AppFont.ui(13)).foregroundColor(Palette.muted)
            }
            Toggle(isOn: $player.repeatOne) {
                Text("تكرار السورة").font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
            }
            .tint(Palette.goldDeep)
            if player.queue.count > 1 {
                Text("التالي في القائمة").font(AppFont.ui(14, 700)).foregroundColor(Palette.ink).padding(.top, 4)
                VStack(spacing: 0) {
                    ForEach(Array(player.queue.enumerated().dropFirst(player.index + 1).prefix(5)), id: \.offset) { i, q in
                        Button { player.play(queue: player.queue, start: i) } label: {
                            HStack {
                                Text(q.title).font(AppFont.ui(14, 500)).foregroundColor(Palette.ink)
                                Spacer()
                                Image(systemName: "play").foregroundColor(Palette.goldDeep)
                            }
                            .padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).card()
            }
        }
        .padding(16)
        .card()
    }

    private func sleepButton(_ title: String, minutes: Int?) -> some View {
        let on: Bool = {
            guard let m = minutes else { return false }
            if m == 0 { return player.sleepAtEnd }
            return player.sleepAt != nil && player.sleepMinutes == m
        }()
        return Button { player.setSleep(minutes: minutes); sleepChoice = minutes } label: {
            Text(title).font(AppFont.ui(13, 700)).foregroundColor(on ? .white : Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(on ? Palette.primary : Palette.chip))
        }
        .buttonStyle(.plain)
    }

    @State private var sleepChoice: Int?
}
