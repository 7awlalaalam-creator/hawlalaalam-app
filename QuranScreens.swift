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
                            Text("آخر قراءة").font(AppFont.ui(12, 700)).foregroundColor(Palette.goldLight)
                            Text("المصحف · صفحة " + ar(state.lastPage)).font(AppFont.ui(16, 700)).foregroundColor(.white)
                        }
                        Spacer()
                        Text("أكمل ←").font(AppFont.ui(13, 700)).foregroundColor(Palette.goldLight)
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
                    row(badge: ar(j), name: "الجزء " + ar(j),
                        meta: "يبدأ في سورة " + Quran.surahName(Quran.surahOf(page: p)), page: p)
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
                TextField("اسم السورة، رقمها، أو رقم الصفحة", text: $query)
                    .font(AppFont.ui(15, 500))
                    .padding(.horizontal, 14).frame(minHeight: 46)
                    .card(radius: 14)
                    .submitLabel(.search)
                Picker("", selection: $juz) {
                    Text("السور").tag(false)
                    Text("الأجزاء").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(!query.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Palette.page)
        }
        .navigationTitle("فهرس المصحف")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func surahRow(_ s: Int) -> some View {
        let n = Quran.counts[s - 1]
        let p = Quran.surahStart[s - 1]
        return row(badge: ar(s), name: Quran.names[s - 1],
                   meta: ar(n) + (n >= 3 && n <= 10 ? " آيات" : " آية") + " · الجزء " + ar(Quran.juzOf(page: p)), page: p)
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
                Text("ص " + ar(page)).font(AppFont.ui(13, 500)).foregroundColor(Palette.muted)
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
            if n >= 1 && n <= Quran.pages { row(badge: ar(n), name: "صفحة " + ar(n), meta: Quran.whereIs(page: n), page: n) }
            if n < 1 || n > Quran.pages { empty }
        } else {
            let hits = Self.search(q)
            if hits.isEmpty { empty } else { ForEach(hits, id: \.self) { s in surahRow(s) } }
        }
    }

    private var empty: some View {
        Text("لا توجد سورة بهذا الاسم. جرّب جزءًا من الاسم أو رقم السورة أو الصفحة.")
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
    static func search(_ q: String) -> [Int] {
        guard !q.isEmpty else { return [] }
        let qq = q.hasPrefix("ال") && q.count > 2 ? String(q.dropFirst(2)) : q
        var exact: [Int] = [], partial: [Int] = []
        for s in 1...114 {
            let name = normalize(Quran.names[s - 1])
            let bare = name.hasPrefix("ال") && name.count > 2 ? String(name.dropFirst(2)) : name
            if name == q || bare == qq { exact.append(s) }
            else if name.contains(q) || name.contains(qq) { partial.append(s) }
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
        ("أستغفر الله", 3, "رواه مسلم", ""),
        ("اللهم أنت السلام ومنك السلام، تباركت يا ذا الجلال والإكرام", 1, "رواه مسلم", ""),
        ("لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير، اللهم لا مانع لما أعطيت، ولا معطي لما منعت، ولا ينفع ذا الجد منك الجد", 1, "متفق عليه", ""),
        ("لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير، لا حول ولا قوة إلا بالله، لا إله إلا الله، ولا نعبد إلا إياه، له النعمة وله الفضل وله الثناء الحسن، لا إله إلا الله مخلصين له الدين ولو كره الكافرون", 1, "رواه مسلم", ""),
        ("سبحان الله", 33, "رواه مسلم", ""),
        ("الحمد لله", 33, "رواه مسلم", ""),
        ("الله أكبر", 33, "رواه مسلم", ""),
        ("لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير", 1, "رواه مسلم", "تمام المئة"),
        ("Q:2:255:255", 1, "رواه النسائي في الكبرى", "آية الكرسي"),
        ("Q:112:1:4", 1, "رواه أبو داود والترمذي والنسائي", "سورة الإخلاص · وثلاثًا بعد الفجر والمغرب"),
        ("Q:113:1:5", 1, "رواه أبو داود والترمذي والنسائي", "سورة الفلق · وثلاثًا بعد الفجر والمغرب"),
        ("Q:114:1:6", 1, "رواه أبو داود والترمذي والنسائي", "سورة الناس · وثلاثًا بعد الفجر والمغرب"),
        ("اللهم أعني على ذكرك وشكرك وحسن عبادتك", 1, "رواه أبو داود والنسائي", ""),
        ("لا إله إلا الله وحده لا شريك له، له الملك وله الحمد، يحيي ويميت، وهو على كل شيء قدير", 10, "رواه الترمذي وأحمد", "بعد صلاتي الفجر والمغرب"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("اضغط على الذكر لتعدّه").font(AppFont.ui(13)).foregroundColor(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(0..<Self.azkar.count, id: \.self) { i in card(i) }
                Button("ابدأ من جديد") { counts = Array(repeating: 0, count: Self.azkar.count) }
                    .font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep).padding(.vertical, 12)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("أذكار بعد الصلاة")
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
            let countText = done ? "تم ✓" : (target == 1 ? "مرة واحدة" : ar(counts[i]) + " / " + ar(target))
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
            .accessibilityLabel(text + "، " + countText)
        }
    }
}

// MARK: - آية لحالك

struct MoodView: View {
    /** نفس MOODS في تطبيق أندرويد: (الشعور، العنوان، مراجع الآيات) */
    static let moods: [(String, String, String)] = [
        ("قلق", "حين يقلقك أمر", "13:28,65:3,9:51,2:286,3:173,20:46"),
        ("حزين", "حين يثقل الحزن قلبك", "9:40,93:3,12:86,94:6,2:155,3:139"),
        ("ضيق", "حين يضيق صدرك", "94:1,65:2,15:97,21:88,2:214,94:5"),
        ("خائف", "حين يغلبك الخوف", "20:46,3:175,9:51,41:30,28:31,10:62"),
        ("مذنب", "حين تثقلك ذنوبك", "39:53,4:110,3:135,25:70,11:114,66:8"),
        ("متعب", "حين يتعبك الطريق", "94:5,2:286,65:7,29:69,2:45,2:153"),
        ("وحيد", "حين تشعر بالوحدة", "2:186,50:16,58:7,57:4,20:46,2:152"),
        ("غاضب", "حين يشتد غضبك", "3:134,41:34,7:199,42:37,42:43,3:159"),
        ("ممتن", "حين يغمرك الامتنان", "14:7,10:58,2:152,16:18,93:11,55:13"),
    ]

    @State private var mood: Int?
    @State private var pick: (Int, Int, String)?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("كيف تشعر الآن؟").font(AppFont.ui(20, 700)).foregroundColor(Palette.ink)
                Text("اختر شعورك، وتأتيك آية من كتاب الله تواسيك").font(AppFont.ui(14)).foregroundColor(Palette.muted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(0..<Self.moods.count, id: \.self) { i in
                        Button { choose(i) } label: {
                            Text(Self.moods[i].0).font(AppFont.ui(15, 700))
                                .foregroundColor(mood == i ? .white : Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(Capsule().fill(mood == i ? Palette.primary : Palette.card))
                                .overlay(Capsule().stroke(mood == i ? Color.clear : Palette.line))
                        }
                    }
                }
                if let p = pick, let m = mood {
                    let s = p.0, a = p.1, text = p.2
                    VStack(spacing: 12) {
                        Text(Self.moods[m].1).font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                        Text(Quran.withNumber(text, a)).font(AppFont.quran(text.count < 120 ? 24 : 20))
                            .foregroundColor(Palette.ink).multilineTextAlignment(.center).lineSpacing(8)
                        Text("سورة " + Quran.surahName(s) + " · الآية " + ar(a)).font(AppFont.ui(13)).foregroundColor(Palette.muted)
                        HStack(spacing: 8) {
                            Button { Share.present(["﴿ \(text) ﴾\nسورة \(Quran.surahName(s)) · الآية \(ar(a))"]) } label: {
                                Pill(title: "شارك", systemImage: "square.and.arrow.up", primary: true)
                            }
                            Button { choose(m) } label: { Pill(title: "آية أخرى", systemImage: "arrow.clockwise") }
                        }
                        NavigationLink {
                            WebScreen(title: "التفسير", url: URL(string: "https://7awlalaalam.com/quran/ayah-\(s)-\(a).html")!)
                        } label: { Text("اقرأ التفسير ←").font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep) }
                    }
                    .padding(18)
                    .card(Palette.ivory, border: Palette.ivoryBorder, radius: 22)
                }
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("آية لحالك")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ i: Int) {
        mood = i
        let refs = Self.moods[i].2.split(separator: ",").compactMap { r -> (Int, Int)? in
            let p = r.split(separator: ":").compactMap { Int($0) }
            return p.count == 2 ? (p[0], p[1]) : nil
        }
        var options = refs
        if let cur = pick, options.count > 1 { options.removeAll { $0.0 == cur.0 && $0.1 == cur.1 } }
        guard let r = options.randomElement(), let t = Quran.verse(r.0, r.1) else { return }
        pick = (r.0, r.1, t)
    }
}
