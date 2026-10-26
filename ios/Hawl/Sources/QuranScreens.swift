import SwiftUI

// MARK: - فهرس المصحف (دون إنترنت)

struct IndexView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var juz = false

    var body: some View {
        List {
            if query.isEmpty && state.lastPage > 0 {
                Button { open(state.lastPage) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bookmark.fill").foregroundColor(Palette.goldLight)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.gold.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("آخر قراءة")).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldLight)
                            Text(L("المصحف · صفحة ") + ar(state.lastPage)).font(AppFont.ui(16, 700)).foregroundColor(.white)
                        }
                        Spacer()
                        Text(L("أكمل ←")).font(AppFont.ui(13, 700)).foregroundColor(Palette.goldLight)
                    }
                    .padding(12)
                    .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 16)))
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            if !query.isEmpty {
                searchResults
            } else if juz {
                ForEach(1...30, id: \.self) { j in
                    let p = Quran.juzStart[j - 1]
                    row(badge: ar(j), name: L("الجزء ") + ar(j),
                        meta: L("يبدأ في سورة ") + Quran.surahName(Quran.surahOf(page: p)), page: p)
                }
            } else {
                ForEach(1...114, id: \.self) { s in surahRow(s) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.page)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                TextField(L("اسم السورة، رقمها، أو رقم الصفحة"), text: $query)
                    .font(AppFont.ui(15, 500))
                    .padding(.horizontal, 14).frame(minHeight: 46)
                    .card(radius: 14)
                    .submitLabel(.search)
                Picker("", selection: $juz) {
                    Text(L("السور")).tag(false)
                    Text(L("الأجزاء")).tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(!query.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Palette.page)
        }
        .navigationTitle(L("فهرس المصحف"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func surahRow(_ s: Int) -> some View {
        let n = Quran.counts[s - 1]
        let p = Quran.surahStart[s - 1]
        return row(badge: ar(s), name: Quran.names[s - 1],
                   meta: ar(n) + (n >= 3 && n <= 10 ? L(" آيات") : L(" آية")) + L(" · الجزء ") + ar(Quran.juzOf(page: p)), page: p)
    }

    private func row(badge: String, name: String, meta: String, page: Int) -> some View {
        Button { open(page) } label: {
            HStack(spacing: 12) {
                StarBadge(text: badge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(AppFont.ui(16, 700)).foregroundColor(Palette.ink)
                    Text(meta).font(AppFont.ui(12)).foregroundColor(Palette.muted).lineLimit(1)
                }
                Spacer()
                Text(L("ص ") + ar(page)).font(AppFont.ui(13, 500)).foregroundColor(Palette.muted)
            }
            .frame(minHeight: 44)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder private var searchResults: some View {
        let q = Self.normalize(query)
        let num = Int(q)
        if let n = num {
            if n >= 1 && n <= 114 { surahRow(n) }
            if n >= 1 && n <= Quran.pages { row(badge: ar(n), name: L("صفحة ") + ar(n), meta: Quran.whereIs(page: n), page: n) }
            if n < 1 || n > Quran.pages { empty }
        } else {
            let hits = Self.search(q)
            if hits.isEmpty { empty } else { ForEach(hits, id: \.self) { s in surahRow(s) } }
        }
    }

    private var empty: some View {
        Text(L("لا توجد سورة بهذا الاسم. جرّب جزءًا من الاسم أو رقم السورة أو الصفحة."))
            .font(AppFont.ui(14)).foregroundColor(Palette.muted)
            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 24)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
    }

    private func open(_ page: Int) {
        state.openMushaf(page: page)
        dismiss()
    }

    /** نفس توحيد الحروف في تطبيق أندرويد: بلا تشكيل، والهمزات، والتاء المربوطة، والألف المقصورة، والأرقام */
    static func normalize(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            let v = u.value
            if (0x064B...0x065F).contains(v) || v == 0x0670 || v == 0x0640 { continue }
            switch u {
            case "أ", "إ", "آ", "ٱ": out.append("ا")
            case "ة": out.append("ه")
            case "ى": out.append("ي")
            default:
                if (0x0660...0x0669).contains(v) { out.append(Character(String(v - 0x0660))) }
                else { out.unicodeScalars.append(u) }
            }
        }
        var t = out.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("سوره ") { t = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        return t
    }

    /** المطابقة التامة أولًا («ق» ← سورة ق)، ثم ما يحتوي الكلمة */
    /** «Al-Baqarah» و«baqara» تتطابق: حروف لاتينية صغيرة بلا «al» ولا h أخيرة */
    static func enKey(_ s: String) -> String {
        var k = String(s.lowercased().filter { $0.isASCII && $0.isLetter })
        if k.hasPrefix("al") && k.count > 4 { k = String(k.dropFirst(2)) }
        if k.hasSuffix("h") && k.count > 3 { k = String(k.dropLast()) }
        return k
    }

    static func search(_ q: String) -> [Int] {
        guard !q.isEmpty else { return [] }
        let qq = q.hasPrefix("ال") && q.count > 2 ? String(q.dropFirst(2)) : q
        var exact: [Int] = [], partial: [Int] = []
        for s in 1...114 {
            let name = normalize(Quran.arNames[s - 1])
            let bare = name.hasPrefix("ال") && name.count > 2 ? String(name.dropFirst(2)) : name
            let ek = enKey(q), en = enKey(Quran.names[s - 1])
            if name == q || bare == qq || (!ek.isEmpty && en == ek) { exact.append(s) }
            else if name.contains(q) || name.contains(qq) || (!ek.isEmpty && en.contains(ek)) { partial.append(s) }
        }
        return exact + partial
    }
}

// MARK: - أذكار بعد الصلاة

struct PrayerAzkarView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var counts: [Int] = Array(repeating: 0, count: Self.azkar.count)
    @State private var texts: [String?] = Array(repeating: nil, count: Self.azkar.count)

    /** (النص، العدد، المصدر، ملاحظة) — «Q:سورة:من:إلى» آيات من نص المجمع المدمج. نفس قائمة تطبيق أندرويد */
    static let azkar: [(String, Int, String, String)] = [
        (L("أستغفر الله"), 3, L("رواه مسلم"), ""),
        (L("اللهم أنت السلام ومنك السلام، تباركت يا ذا الجلال والإكرام"), 1, L("رواه مسلم"), ""),
        (L("لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير، اللهم لا مانع لما أعطيت، ولا معطي لما منعت، ولا ينفع ذا الجد منك الجد"), 1, L("متفق عليه"), ""),
        (L("لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير، لا حول ولا قوة إلا بالله، لا إله إلا الله، ولا نعبد إلا إياه، له النعمة وله الفضل وله الثناء الحسن، لا إله إلا الله مخلصين له الدين ولو كره الكافرون"), 1, L("رواه مسلم"), ""),
        (L("سبحان الله"), 33, L("رواه مسلم"), ""),
        (L("الحمد لله"), 33, L("رواه مسلم"), ""),
        (L("الله أكبر"), 33, L("رواه مسلم"), ""),
        (L("لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير"), 1, L("رواه مسلم"), L("تمام المئة")),
        ("Q:2:255:255", 1, L("رواه النسائي في الكبرى"), L("آية الكرسي")),
        ("Q:112:1:4", 1, L("رواه أبو داود والترمذي والنسائي"), L("سورة الإخلاص · وثلاثًا بعد الفجر والمغرب")),
        ("Q:113:1:5", 1, L("رواه أبو داود والترمذي والنسائي"), L("سورة الفلق · وثلاثًا بعد الفجر والمغرب")),
        ("Q:114:1:6", 1, L("رواه أبو داود والترمذي والنسائي"), L("سورة الناس · وثلاثًا بعد الفجر والمغرب")),
        (L("اللهم أعني على ذكرك وشكرك وحسن عبادتك"), 1, L("رواه أبو داود والنسائي"), ""),
        (L("لا إله إلا الله وحده لا شريك له، له الملك وله الحمد، يحيي ويميت، وهو على كل شيء قدير"), 10, L("رواه الترمذي وأحمد"), L("بعد صلاتي الفجر والمغرب")),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(L("اضغط على الذكر لتعدّه")).font(AppFont.ui(13)).foregroundColor(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(0..<Self.azkar.count, id: \.self) { i in card(i) }
                Button(L("ابدأ من جديد")) { counts = Array(repeating: 0, count: Self.azkar.count) }
                    .font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep).padding(.vertical, 12)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(L("أذكار بعد الصلاة"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let specs = Self.azkar.map { $0.0 }
            let resolved: [String?] = await Task.detached { specs.map(Self.resolve) }.value
            texts = resolved
        }
    }

    /** «Q:سورة:من:إلى» ← الآيات بالرسم العثماني مع علامة كل آية؛ وغيره كما هو */
    nonisolated static func resolve(_ spec: String) -> String? {
        guard spec.hasPrefix("Q:") else { return spec }
        let p = spec.split(separator: ":").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var parts: [String] = []
        for a in p[1]...p[2] {
            guard let v = Quran.verse(p[0], a) else { return nil }
            parts.append(Quran.withNumber(v, a))
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder private func card(_ i: Int) -> some View {
        let item = Self.azkar[i]
        let spec = item.0, target = item.1, source = item.2, note = item.3
        let quran = spec.hasPrefix("Q:")
        if let text = quran ? texts[i] : spec {
            let done = counts[i] >= target
            let countText = done ? L("تم ✓") : (target == 1 ? L("مرة واحدة") : ar(counts[i]) + " / " + ar(target))
            Button {
                guard counts[i] < target else { return }
                counts[i] += 1
                UIImpactFeedbackGenerator(style: counts[i] >= target ? .medium : .light).impactOccurred()
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if !note.isEmpty { Text(note).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep) }
                    Text(text)
                        .font(quran ? AppFont.quran(text.count > 200 ? 19 : 22) : AppFont.ui(18, 500))
                        .foregroundColor(Palette.ink)
                        .lineSpacing(quran ? 8 : 6)
                        .multilineTextAlignment(quran ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: quran ? .center : .leading)
                    HStack {
                        Text(source).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                        Spacer()
                        Text(countText).font(AppFont.ui(14, 700))
                            .foregroundColor(done ? Palette.goldDeep : Palette.ink)
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .background(Capsule().fill(done ? Palette.card : Palette.chip))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .card(done ? Palette.chip : Palette.card, border: done ? Palette.ivoryBorder : Palette.line)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text + L("، ") + countText)
        }
    }
}
