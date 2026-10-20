import SwiftUI

// MARK: - التفسير الميسر دون إنترنت (نفس ملف صفحة المصحف: assets/quran/tafsir-muyassar.json)

enum TafsirData {
    private struct Doc: Decodable { let src: String?; let s: [[String]] }

    private static var doc: Doc?
    private static var pages: [Int: Int] = [:]
    private static let lock = NSLock()

    /** يُستدعى خارج الخيط الرئيسي أول مرة (الملف كبير نسبيًا) */
    static func text(_ s: Int, _ a: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        if doc == nil, let u = Bundle.main.url(forResource: "tafsir-muyassar", withExtension: "json", subdirectory: "quran"),
           let d = try? Data(contentsOf: u, options: .mappedIfSafe) {
            doc = try? JSONDecoder().decode(Doc.self, from: d)
        }
        guard let l = doc?.s, s >= 1, s <= l.count, a >= 1, a <= l[s - 1].count else { return "" }
        return l[s - 1][a - 1]
    }

    static var source: String { _ = text(1, 1); return doc?.src ?? "التفسير الميسر — مجمع الملك فهد لطباعة المصحف الشريف" }

    /** صفحة الآية في مصحف المدينة (من mushaf.json) */
    static func page(_ s: Int, _ a: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        if pages.isEmpty, let u = Bundle.main.url(forResource: "mushaf", withExtension: "json", subdirectory: "quran"),
           let d = try? Data(contentsOf: u, options: .mappedIfSafe),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let ps = o["pages"] as? [[[Any]]] {
            for (i, entries) in ps.enumerated() {
                for e in entries where e.count >= 2 {
                    if let ss = e[0] as? Int, let aa = e[1] as? Int, pages[ss * 1000 + aa] == nil { pages[ss * 1000 + aa] = i + 1 }
                }
            }
        }
        return pages[s * 1000 + a] ?? Quran.surahStart[max(0, min(113, s - 1))]
    }
}

struct TafsirView: View {
    @EnvironmentObject var state: AppState
    @State private var s: Int
    @State private var a: Int
    @State private var verse = ""
    @State private var tafsir = ""
    @State private var loaded = false

    init(surah: Int, ayah: Int) {
        let ok = Quran.valid(surah, ayah)
        _s = State(initialValue: ok ? surah : 1)
        _a = State(initialValue: ok ? ayah : 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("سورة " + Quran.surahName(s) + " · الآية " + ar(a)).font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                    Text(verse.isEmpty ? " " : Quran.withNumber(verse, a))
                        .font(AppFont.quran(25)).foregroundColor(Palette.ink)
                        .lineSpacing(12).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .textSelection(.enabled)
                }
                .padding(18)
                .card(Palette.ivory, border: Palette.ivoryBorder, radius: 18)

                VStack(alignment: .leading, spacing: 8) {
                    Text("التفسير الميسر").font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                    if !loaded {
                        ProgressView().tint(Palette.goldDeep).frame(maxWidth: .infinity)
                    } else {
                        Text(tafsir.isEmpty ? "لا يتوفر تفسير لهذه الآية" : tafsir)
                            .font(AppFont.ui(17)).foregroundColor(Palette.ink).lineSpacing(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(18)
                .card()

                HStack(spacing: 8) {
                    Button { state.openMushaf(page: TafsirData.page(s, a)) } label: {
                        Pill(title: "افتح في المصحف", systemImage: "book", primary: true, height: 48)
                    }
                    Button { shareImage() } label: { Pill(title: "صورة للمشاركة", systemImage: "photo", height: 48) }
                }
                .buttonStyle(.plain)
                Button { listen() } label: { Pill(title: "استمع إلى سورة " + Quran.surahName(s), systemImage: "headphones", height: 46) }
                    .buttonStyle(.plain)

                HStack {
                    Button { move(-1) } label: {
                        Label("الآية السابقة", systemImage: "chevron.right").font(AppFont.ui(14, 700))
                    }
                    .disabled(s == 1 && a == 1)
                    Spacer()
                    Button { move(+1) } label: {
                        Label("الآية التالية", systemImage: "chevron.left").labelStyle(TrailingIcon()).font(AppFont.ui(14, 700))
                    }
                    .disabled(s == 114 && a == Quran.counts[113])
                }
                .foregroundColor(Palette.goldDeep)
                .padding(.horizontal, 4).padding(.top, 4)

                Text("المصدر: " + TafsirData.source + " · يعمل دون إنترنت").font(AppFont.ui(11)).foregroundColor(Palette.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 8)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("التفسير")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: s * 1000 + a) { await load() }
    }

    private func load() async {
        let (ss, aa) = (s, a)
        let r = await Task.detached(priority: .userInitiated) { (Quran.verse(ss, aa) ?? "", TafsirData.text(ss, aa)) }.value
        guard ss == s, aa == a else { return }
        verse = r.0
        tafsir = r.1
        loaded = true
    }

    private func move(_ d: Int) {
        var i = Quran.index(s, a) + d
        i = max(0, min(Quran.total - 1, i))
        let (ns, na) = Quran.fromIndex(i)
        s = ns
        a = na
    }

    private func shareImage() {
        guard !verse.isEmpty else { return }
        VerseImage.share(AppState.DailyVerse(surah: s, ayah: a, text: verse))
    }

    private func listen() {
        let cat = ListenCatalog.shared
        if let p = cat.preferred, p.1.surahs.contains(s) {
            let (r, m) = p
            let list = ListenCatalog.tracks(r, m)
            AudioPlayer.shared.play(queue: list, start: list.firstIndex { $0.surah == s } ?? 0)
            Toast.show("سورة " + Quran.surahName(s) + " · " + r.name)
        } else {
            state.tab = .listen
            Toast.show("اختر قارئًا لتستمع إلى سورة " + Quran.surahName(s))
        }
    }
}

/** أيقونة بعد النص (للزر «الآية السابقة») */
struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}

/** بطاقة الآية صورةً للمشاركة (نفس بطاقة آية اليوم) */
enum VerseImage {
    @MainActor static func share(_ v: AppState.DailyVerse) {
        let r = ImageRenderer(content: VerseShareCard(verse: v).environment(\.layoutDirection, .rightToLeft))
        r.scale = 3
        if let img = r.uiImage { Share.present([img, v.shareText]) } else { Share.present([v.shareText]) }
    }
}
