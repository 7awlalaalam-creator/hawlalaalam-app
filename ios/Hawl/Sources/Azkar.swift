import SwiftUI
import UIKit

// MARK: - الأذكار دون إنترنت (assets/azkar.json — النصوص نفسها في صفحة الموقع، مشتركة مع أندرويد)

struct AzkarItem: Decodable, Hashable {
    let text: String
    let count: Int
    let source: String?
    let note: String?

    /** «Q:سورة:من:إلى» يُقرأ من نص المصحف */
    var quran: (Int, Int, Int)? {
        guard text.hasPrefix("Q:") else { return nil }
        let p = text.split(separator: ":").compactMap { Int($0) }
        return p.count == 3 ? (p[0], p[1], p[2]) : nil
    }

    /** النص المعروض: الآيات بخط المجمع بأرقامها، أو نص الذكر */
    var display: String {
        guard let q = quran else { return text }
        return (q.1...max(q.1, q.2)).compactMap { a in Quran.verse(q.0, a).map { Quran.withNumber($0, a) } }.joined(separator: " ")
    }
}

struct AzkarSection: Decodable, Identifiable {
    let id: String
    let title: String
    let items: [AzkarItem]
}

enum AzkarData {
    private struct Doc: Decodable { let sections: [AzkarSection] }

    static let sections: [AzkarSection] = {
        guard let u = Bundle.main.url(forResource: "azkar", withExtension: "json"),
              let d = try? Data(contentsOf: u),
              let doc = try? JSONDecoder().decode(Doc.self, from: d) else { return [] }
        return doc.sections
    }()

    static let order = ["morning", "evening", "sleep", "prayer"]

    static func tabTitle(_ id: String) -> String {
        switch id {
        case "morning": return L("الصباح")
        case "evening": return L("المساء")
        case "sleep": return L("النوم")
        default: return L("بعد الصلاة")
        }
    }

    /** الصباح من الفجر إلى العصر، والمساء بعد العصر (وبالساعة إن لم يُحدَّد الموقع) */
    static func current(_ now: Date = Date()) -> String {
        if Geo.has {
            let t = Prayer.times(for: now)
            return now >= t[Prayer.fajr] && now < t[Prayer.asr] ? "morning" : "evening"
        }
        let h = Calendar.current.component(.hour, from: now)
        return h >= 4 && h < 15 ? "morning" : "evening"
    }

    static func key(_ id: String, _ day: Date = Date()) -> String { "azkar_progress_" + id + "_" + Reading.dayKey(day) }

    static func progress(_ id: String, count: Int) -> [Int] {
        let a = (Store.d.array(forKey: key(id)) as? [Int]) ?? []
        return a.count == count ? a : Array(repeating: 0, count: count)
    }

    static func save(_ id: String, _ p: [Int]) { Store.d.set(p, forKey: key(id)) }
}

struct AzkarView: View {
    @State private var tab: String
    @State private var counts: [String: [Int]] = [:]

    init(section: String? = nil) {
        _tab = State(initialValue: section.flatMap { AzkarData.order.contains($0) ? $0 : nil } ?? AzkarData.current())
    }

    private var section: AzkarSection? { AzkarData.sections.first { $0.id == tab } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $tab) {
                        ForEach(AzkarData.order, id: \.self) { Text(AzkarData.tabTitle($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 4)

                    if let s = section {
                        let c = counts[s.id] ?? AzkarData.progress(s.id, count: s.items.count)
                        let done = zip(c, s.items).filter { pair in pair.0 >= pair.1.count }.count
                        HStack {
                            Text(L("أنجزت ") + ar(done) + L(" من ") + ar(s.items.count)).font(AppFont.ui(13, 700)).foregroundColor(Palette.ink)
                            Spacer()
                            Button { reset(s) } label: {
                                Label(L("ابدأ من جديد"), systemImage: "arrow.counterclockwise").font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                            }
                            .disabled(c.allSatisfy { $0 == 0 })
                        }
                        ProgressView(value: Double(done), total: Double(max(1, s.items.count))).tint(Palette.gold)
                            .padding(.bottom, 6)
                        if done == s.items.count {
                            Label(L("أتممت ") + s.title + L("، تقبّل الله منك"), systemImage: "checkmark.seal.fill")
                                .font(AppFont.ui(15, 700)).foregroundColor(Palette.goldDeep)
                                .padding(14).frame(maxWidth: .infinity).card(Palette.ivory, border: Palette.ivoryBorder, radius: 16)
                        }
                        ForEach(Array(s.items.enumerated()), id: \.offset) { i, it in
                            zikrCard(s, it, i, c[i]).id(i)
                        }
                    } else {
                        Text(L("تعذّر فتح الأذكار")).font(AppFont.ui(15)).foregroundColor(Palette.muted).padding(30)
                    }
                    Text(L("المصدر: حصن المسلم من القرآن والسنة الصحيحة")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                        .frame(maxWidth: .infinity).padding(.top, 6)
                }
                .padding(16)
            }
            .onChange(of: tab) { _ in proxy.scrollTo(0, anchor: .top) }
            .onChange(of: counts) { _ in
                // بعد اكتمال الذكر ننتقل إلى التالي غير المكتمل
                guard let s = section else { return }
                let c = counts[s.id] ?? []
                if let next = c.indices.first(where: { c[$0] < s.items[$0].count }), lastTapped >= 0, c.indices.contains(lastTapped),
                   c[lastTapped] >= s.items[lastTapped].count {
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(next, anchor: .top) }
                }
            }
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(L("الأذكار"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .keepScreenOn()
    }

    @State private var lastTapped = -1

    private func load() {
        for s in AzkarData.sections { counts[s.id] = AzkarData.progress(s.id, count: s.items.count) }
    }

    private func zikrCard(_ s: AzkarSection, _ it: AzkarItem, _ i: Int, _ n: Int) -> some View {
        let done = n >= it.count
        return Button { tap(s, i) } label: {
            VStack(alignment: .leading, spacing: 10) {
                if let note = it.note, !note.isEmpty {
                    Text(note).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldKey)
                }
                Text(it.display)
                    .font(it.quran != nil ? AppFont.quran(22) : AppFont.amiri(21))
                    .foregroundColor(Palette.ink)
                    .lineSpacing(it.quran != nil ? 10 : 8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(done ? L("✓ تم") : (it.count == 1 ? L("مرة واحدة") : ar(n) + L(" من ") + ar(it.count)))
                        .font(AppFont.ui(13, 700)).foregroundColor(Palette.goldKey)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Palette.chip))
                    if let src = it.source, !src.isEmpty {
                        Text(src).font(AppFont.ui(11)).foregroundColor(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !done {
                        Text(L("اضغط للعدّ")).font(AppFont.ui(13, 700)).foregroundColor(.white)
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .background(Capsule().fill(Palette.primary))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(Palette.ivory, border: done ? Palette.ivoryBorder : Palette.gold.opacity(0.5), radius: 18)
            .opacity(done ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(it.quran != nil ? (it.note ?? L("آيات")) : it.text)
        .accessibilityValue(done ? L("تم") : ar(n) + L(" من ") + ar(it.count))
        .accessibilityHint(L("اضغط مرتين للعدّ"))
    }

    private func tap(_ s: AzkarSection, _ i: Int) {
        var c = counts[s.id] ?? AzkarData.progress(s.id, count: s.items.count)
        guard c[i] < s.items[i].count else { return }
        c[i] += 1
        let finished = c[i] >= s.items[i].count
        UIImpactFeedbackGenerator(style: finished ? .medium : .light).impactOccurred()
        lastTapped = i
        counts[s.id] = c
        AzkarData.save(s.id, c)
    }

    private func reset(_ s: AzkarSection) {
        let z = Array(repeating: 0, count: s.items.count)
        lastTapped = -1
        counts[s.id] = z
        AzkarData.save(s.id, z)
    }
}
