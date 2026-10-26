import SwiftUI

// MARK: - الأحاديث الصحيحة دون إنترنت (نفس Hadith.java): صحيح البخاري وصحيح مسلم
// الملفات من مشروع أندرويد: assets/hadith/*.deflate (DEFLATE خام) و hadith-daily.json

struct HadithBook: Identifiable, Hashable { let id: Int; let name: String; let count: Int }

final class HadithCollection {
    let key: String
    let title: String
    let books: [HadithBook]
    let num: [Int], book: [Int]
    let isnad: [String], matn: [String], narrator: [String]
    private var norm: [String]?
    private let lock = NSLock()

    init(key: String, title: String, books: [HadithBook], rows: [[Any]]) {
        self.key = key; self.title = title; self.books = books
        var n = [Int](), b = [Int](), i = [String](), m = [String](), r = [String]()
        n.reserveCapacity(rows.count)
        for x in rows where x.count >= 5 {
            n.append(x[0] as? Int ?? 0); b.append(x[1] as? Int ?? 0)
            i.append(x[2] as? String ?? ""); m.append(x[3] as? String ?? ""); r.append(x[4] as? String ?? "")
        }
        num = n; book = b; isnad = i; matn = m; narrator = r
    }

    var count: Int { num.count }

    func index(of n: Int) -> Int? {
        var lo = 0, hi = num.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if num[mid] == n { return mid }
            if num[mid] < n { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    func bookName(_ id: Int) -> String { books.first { $0.id == id }?.name ?? "" }

    func search(_ q: String, max: Int) -> [Int] {
        let words = Hadith.norm(q).split(separator: " ").map(String.init)
        if words.isEmpty { return [] }
        lock.lock(); defer { lock.unlock() }
        if norm == nil { norm = zip(matn, narrator).map { Hadith.norm($0 + " " + $1) } }
        var out = [Int]()
        for (k, s) in norm!.enumerated() where words.allSatisfy({ s.contains($0) }) {
            out.append(k)
            if out.count >= max { break }
        }
        return out
    }
}

enum Hadith {
    static let bukhari = "bukhari", muslim = "muslim"
    private static var cache: [String: HadithCollection] = [:]
    private static let lock = NSLock()
    private static var daily: [(Int, Int)]?

    static func title(_ key: String) -> String { key == muslim ? L("صحيح مسلم") : L("صحيح البخاري") }

    static func peek(_ key: String) -> HadithCollection? { lock.lock(); defer { lock.unlock() }; return cache[key] }

    /** يُستدعى من خلفية (Task.detached) */
    static func load(_ key: String) -> HadithCollection? {
        if let c = peek(key) { return c }
        guard let u = Bundle.main.url(forResource: "hadith-" + key, withExtension: "deflate"),
              let raw = try? Data(contentsOf: u),
              let data = try? (raw as NSData).decompressed(using: .zlib) as Data,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let books = ((o["books"] as? [[Any]]) ?? []).compactMap { b -> HadithBook? in
            guard b.count >= 3, let id = b[0] as? Int, let n = b[1] as? String else { return nil }
            return HadithBook(id: id, name: n, count: b[2] as? Int ?? 0)
        }
        let c = HadithCollection(key: key, title: o["title"] as? String ?? title(key), books: books, rows: (o["h"] as? [[Any]]) ?? [])
        lock.lock(); cache[key] = c; lock.unlock()
        return c
    }

    /** «حديث اليوم»: نفس الحديث طوال اليوم لكل المستخدمين */
    static func today() -> (String, Int) {
        if daily == nil, let u = Bundle.main.url(forResource: "hadith-daily", withExtension: "json"),
           let d = try? Data(contentsOf: u), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let a = o["daily"] as? [[Any]] {
            daily = a.compactMap { x -> (Int, Int)? in
                guard x.count == 2, let k = x[0] as? String, let n = x[1] as? Int else { return nil }
                return (k == muslim ? 1 : 0, n)
            }
        }
        guard let d = daily, !d.isEmpty else { return (bukhari, 1) }
        let cal = Calendar(identifier: .gregorian)
        let day = cal.component(.year, from: Date()) * 366 + (cal.ordinality(of: .day, in: .year, for: Date()) ?? 1)
        let pick = d[day % d.count]
        return (pick.0 == 1 ? muslim : bukhari, pick.1)
    }

    // المفضلة
    static var favorites: Set<String> { Set(Store.d.stringArray(forKey: "hadith_fav") ?? []) }
    static func isFav(_ key: String, _ n: Int) -> Bool { favorites.contains("\(key):\(n)") }
    static func toggleFav(_ key: String, _ n: Int) {
        var s = favorites
        let id = "\(key):\(n)"
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        Store.d.set(Array(s).sorted(), forKey: "hadith_fav")
    }

    static func shareText(_ c: HadithCollection, _ i: Int, isnad: Bool) -> String {
        var t = ""
        if isnad && !c.isnad[i].isEmpty { t += c.isnad[i] + "\n\n" }
        t += c.matn[i] + "\n\n" + c.title + L("، رقم ") + ar(c.num[i])
        let b = c.bookName(c.book[i])
        if !b.isEmpty { t += " — " + b }
        return t + L("\nمن تطبيق «القرآن حول العالم»: https://7awlalaalam.com/app")
    }

    /** تطبيع للبحث: بلا تشكيل، والهمزات ألفًا، والتاء المربوطة هاءً، والألف المقصورة ياءً */
    static func norm(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            let v = u.value
            if (0x064B...0x065F).contains(v) || v == 0x0670 || v == 0x0640 { continue }
            switch v {
            case 0x0623, 0x0625, 0x0622, 0x0671: out.append("ا")
            case 0x0629: out.append("ه")
            case 0x0649: out.append("ي")
            case 0x0624: out.append("و")
            case 0x0626: out.append("ي")
            default: out.append(u)
            }
        }
        return String(out).lowercased()
    }
}

struct HadithView: View {
    static func meta(_ c: HadithCollection, _ i: Int) -> String {
        let who: String = c.narrator[i].isEmpty ? "" : L("عن ") + c.narrator[i] + " · "
        let book: String = c.key == Hadith.muslim ? L("مسلم ") : L("البخاري ")
        return who + book + ar(c.num[i])
    }

    var key: String = Hadith.bukhari
    var bookID: Int? = nil
    @State private var tab = 0                 // ٠ البخاري، ١ مسلم، ٢ المفضلة
    @State private var query = ""
    @State private var submitted = ""
    @State private var shown = 40
    @State private var loaded = 0              // يتغيّر حين يكتمل التحميل
    @State private var favs = Hadith.favorites
    @State private var results: [Int] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let b = bookID { bookList(b) } else { home }
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(bookID != nil ? (Hadith.peek(key)?.bookName(bookID!) ?? Hadith.title(key)) : L("الأحاديث الصحيحة"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { favs = Hadith.favorites; if bookID == nil { tab = key == Hadith.muslim ? 1 : tab } }
        .task {
            if Hadith.peek(Hadith.bukhari) == nil || Hadith.peek(Hadith.muslim) == nil {
                await Task.detached(priority: .userInitiated) { _ = Hadith.load(Hadith.bukhari); _ = Hadith.load(Hadith.muslim) }.value
                loaded += 1
            }
        }
    }

    @ViewBuilder private var home: some View {
        daily
        Picker("", selection: $tab) {
            Text(L("صحيح البخاري")).tag(0)
            Text(L("صحيح مسلم")).tag(1)
            Text(L("المفضلة")).tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.top, 6)
        .onChange(of: tab) { _ in shown = 40; submitted = ""; query = ""; results = []; favs = Hadith.favorites }
        if tab == 2 { favorites } else {
            TextField(L("ابحث في ") + (tab == 1 ? L("صحيح مسلم") : L("صحيح البخاري")) + "…", text: $query)
                .font(AppFont.ui(15))
                .submitLabel(.search)
                .onSubmit { runSearch() }
                .padding(.horizontal, 14).frame(minHeight: 48)
                .card(radius: 14)
            if let c = Hadith.peek(tab == 1 ? Hadith.muslim : Hadith.bukhari) {
                if !submitted.isEmpty {
                    let res = results
                    Text(res.isEmpty ? "لا نتائج لـ«\(submitted)»" : ar(res.count) + (res.count >= 300 ? "+" : "") + L(" نتيجة"))
                        .font(AppFont.ui(13, 500)).foregroundColor(Palette.muted).padding(.top, 4)
                    items(c, res)
                } else {
                    Text(L("الكتب")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink).padding(.top, 12)
                    VStack(spacing: 0) {
                        ForEach(Array(c.books.enumerated()), id: \.element.id) { k, b in
                            if k > 0 { Rectangle().fill(Palette.divider).frame(height: 1) }
                            NavigationLink(value: Screen.hadithBook(c.key, b.id)) {
                                HStack {
                                    Text(b.name).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink).multilineTextAlignment(.leading)
                                    Spacer()
                                    Text(ar(b.count)).font(AppFont.ui(12, 500)).foregroundColor(Palette.muted)
                                }
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .card()
                    Text(L("البخاري بترقيم فتح الباري، ومسلم بترقيم محمد فؤاد عبد الباقي · يعمل دون إنترنت"))
                        .font(AppFont.ui(11)).foregroundColor(Palette.muted).frame(maxWidth: .infinity).padding(.top, 6)
                }
            } else {
                Text(L("جارٍ فتح الأحاديث…")).font(AppFont.ui(15)).foregroundColor(Palette.muted).frame(maxWidth: .infinity).padding(.top, 30)
                    .id(loaded)
            }
        }
    }

    /** البحث خارج الخيط الرئيسي، والنتائج تُحفظ فلا يتكرر مع «عرض المزيد» */
    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        shown = 40
        guard let c = Hadith.peek(tab == 1 ? Hadith.muslim : Hadith.bukhari), !q.isEmpty else { submitted = ""; results = []; return }
        Task {
            let r = await Task.detached(priority: .userInitiated) { c.search(q, max: 300) }.value
            results = r
            submitted = q
        }
    }

    private var daily: some View {
        let d = Hadith.today()
        let c = Hadith.peek(d.0)
        let i = c?.index(of: d.1)
        return NavigationLink(value: Screen.hadithDetail(d.0, d.1)) {
            VStack(spacing: 8) {
                Text(L("حديث اليوم")).font(AppFont.ui(12, 700)).foregroundColor(Palette.gold)
                Text(i.map { c!.matn[$0] } ?? "…").font(AppFont.amiri(21)).foregroundColor(.white)
                    .multilineTextAlignment(.center).lineSpacing(6)
                if let i = i, let c = c {
                    let who: String = c.narrator[i].isEmpty ? "" : L("عن ") + c.narrator[i] + " · "
                    let src: String = Hadith.title(d.0) + " " + ar(c.num[i])
                    Text(who + src)
                        .font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted).multilineTextAlignment(.center)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
        }
        .buttonStyle(.plain)
        .id(loaded)
    }

    @ViewBuilder private var favorites: some View {
        let list = favs.sorted()
        if list.isEmpty {
            Text(L("لم تحفظ أحاديث بعد.\nاضغط «حفظ» في أي حديث ليظهر هنا."))
                .font(AppFont.ui(15)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, 40)
        }
        ForEach(list, id: \.self) { f in
            let p = f.split(separator: ":").map(String.init)
            if p.count == 2, let n = Int(p[1]), let c = Hadith.peek(p[0]), let i = c.index(of: n) { item(c, i) }
        }
        .id(loaded)
    }

    @ViewBuilder private func bookList(_ b: Int) -> some View {
        if let c = Hadith.peek(key) {
            items(c, (0..<c.count).filter { c.book[$0] == b })
        } else {
            Text(L("جارٍ فتح الأحاديث…")).font(AppFont.ui(15)).foregroundColor(Palette.muted).frame(maxWidth: .infinity).padding(.top, 30)
                .id(loaded)
        }
    }

    @ViewBuilder private func items(_ c: HadithCollection, _ idx: [Int]) -> some View {
        ForEach(idx.prefix(shown), id: \.self) { i in item(c, i) }
        if idx.count > shown {
            Button { shown += 80 } label: { Pill(title: L("عرض المزيد (") + ar(idx.count - shown) + ")", systemImage: "chevron.down") }
                .buttonStyle(.plain).padding(.top, 6)
        }
    }

    private func item(_ c: HadithCollection, _ i: Int) -> some View {
        NavigationLink(value: Screen.hadithDetail(c.key, c.num[i])) {
            VStack(alignment: .leading, spacing: 6) {
                Text(c.matn[i]).font(AppFont.amiri(18)).foregroundColor(Palette.ink).lineLimit(4).lineSpacing(4)
                    .multilineTextAlignment(.leading)
                Text(Self.meta(c, i))
                    .font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 16)
        }
        .buttonStyle(.plain)
    }
}

struct HadithDetailView: View {
    let key: String
    @State var num: Int
    @State private var col: HadithCollection?
    @AppStorage("hadith_isnad", store: Store.d) private var showIsnad = true
    @State private var fav = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let c = col, let i = c.index(of: num) { content(c, i) } else {
                    Text(col == nil ? L("جارٍ فتح الحديث…") : L("لم يُعثر على الحديث")).font(AppFont.ui(15)).foregroundColor(Palette.muted)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(Hadith.title(key) + " · " + ar(num))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            col = Hadith.peek(key)
            if col == nil { col = await Task.detached(priority: .userInitiated) { Hadith.load(key) }.value }
            fav = Hadith.isFav(key, num)
        }
    }

    @ViewBuilder private func content(_ c: HadithCollection, _ i: Int) -> some View {
        let hasIsnad = !c.isnad[i].isEmpty
        let bookName = c.bookName(c.book[i])
        if !bookName.isEmpty { Text(bookName).font(AppFont.ui(13, 500)).foregroundColor(Palette.muted) }
        VStack(alignment: .leading, spacing: 10) {
            if hasIsnad {
                Button { showIsnad.toggle() } label: {
                    Label(showIsnad ? L("إخفاء السند") : L("إظهار السند"), systemImage: "link")
                        .font(AppFont.ui(13, 700)).foregroundColor(Palette.goldKey)
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .background(Capsule().fill(Palette.chip))
                        .overlay(Capsule().stroke(Palette.ivoryBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                if showIsnad {
                    Text(L("السند")).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep).padding(.top, 2)
                    Text(c.isnad[i]).font(AppFont.amiri(16)).foregroundColor(Palette.muted).lineSpacing(6).textSelection(.enabled)
                }
                Text(L("المتن")).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep).padding(.top, 4)
            } else {
                Text(L("نص الحديث")).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep)
            }
            Text(c.matn[i]).font(AppFont.amiri(hasIsnad ? 23 : 20)).foregroundColor(Palette.ink).lineSpacing(8).textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Palette.ivory, border: Palette.ivoryBorder)

        HStack(spacing: 8) {
            if !c.narrator[i].isEmpty { fact(L("الراوي"), c.narrator[i]) }
            fact(L("المصدر"), Hadith.title(key) + L("، ح ") + ar(num))
        }

        HStack(spacing: 8) {
            Button { Share.present([Hadith.shareText(c, i, isnad: showIsnad)]) } label: { Pill(title: L("مشاركة"), systemImage: "square.and.arrow.up", primary: true) }
            Button {
                UIPasteboard.general.string = Hadith.shareText(c, i, isnad: showIsnad)
            } label: { Pill(title: L("نسخ"), systemImage: "doc.on.doc") }
            Button { Hadith.toggleFav(key, num); fav = Hadith.isFav(key, num) } label: {
                Pill(title: fav ? L("محفوظ") : L("حفظ"), systemImage: fav ? "heart.fill" : "heart")
            }
        }
        .buttonStyle(.plain)

        HStack {
            if i > 0 { Button(L("› الحديث ") + ar(c.num[i - 1])) { go(c.num[i - 1]) } }
            Spacer()
            if i < c.count - 1 { Button(L("الحديث ") + ar(c.num[i + 1]) + " ‹") { go(c.num[i + 1]) } }
        }
        .font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep)
        .padding(.vertical, 8)
    }

    private func go(_ n: Int) { num = n; fav = Hadith.isFav(key, n) }

    private func fact(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(AppFont.ui(11)).foregroundColor(Palette.muted)
            Text(v).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 12)
    }
}
