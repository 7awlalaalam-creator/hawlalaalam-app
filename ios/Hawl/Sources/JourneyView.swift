import SwiftUI

/**
 * «رحلتي»: صورة واحدة لعلاقتك بالقرآن — سلسلة الأيام، أيام القراءة في آخر ٣٠ يومًا، الختمات، والحفظ.
 * كل البيانات من الجهاز نفسه (سجل القراءة، الختمة، وحالة الحفظ التي ترسلها صفحة المصحف).
 */
struct JourneyView: View {
    @EnvironmentObject var state: AppState
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        _ = state.rev
        let cal = Calendar.current
        let days: [Date] = (0..<30).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }
        let readCount = days.filter { Reading.readOn($0) }.count
        let hifzTotal = Store.int("hifz_total", 0), held = Store.int("hifz_held", 0), pct = Store.int("hifz_pct", 0)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("سلسلتك الحالية")).font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                    Text(streakText(Reading.streak)).font(AppFont.ui(26, 700)).foregroundColor(.white)
                    Text(L("أطول سلسلة: ") + streakText(bestStreak())).font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 22).fill(Palette.dark))

                HStack(spacing: 8) {
                    stat(ar(readCount), L("يومًا قرأت\nمن آخر ٣٠"))
                    stat(ar(Khatma.completed), Khatma.completed == 1 ? L("ختمة\nأتممتها") : L("ختمات\nأتممتها"))
                    stat(ar(hifzTotal), L("آية\nفي حفظك"))
                }

                PrayerLogJourney()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("آخر ٣٠ يومًا")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                    LazyVGrid(columns: cols, spacing: 6) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                            let on = Reading.readOn(d)
                            Text(ar(cal.component(.day, from: d)))
                                .font(AppFont.ui(12, on ? 700 : 400))
                                .foregroundColor(on ? Palette.widgetDark : Palette.muted)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 9).fill(on ? Palette.gold : Palette.chip))
                                .accessibilityLabel(hijriShort(d) + (on ? L("، قرأت") : L("، لم تقرأ")))
                        }
                    }
                    HStack(spacing: 14) {
                        legend(Palette.gold, L("قرأت"))
                        legend(Palette.chip, L("لم تقرأ"))
                    }
                }
                .padding(16)
                .card()

                if hifzTotal > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("الحفظ")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                        Text("\(ar(held)) آية ثابتة من \(ar(hifzTotal)) · الإتقان \(ar(pct))٪")
                            .font(AppFont.ui(14)).foregroundColor(Palette.muted)
                        ProgressView(value: Double(held), total: Double(max(1, hifzTotal))).tint(Palette.gold)
                        Button { state.openMushaf(page: nil, extra: "hifz=1") } label: {
                            Pill(title: L("راجع حفظك"), systemImage: "puzzlepiece", primary: true, height: 44)
                        }
                    }
                    .padding(16)
                    .card()
                }

                Text(L("كل هذا محفوظ على جهازك فقط.")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle(L("رحلتي"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ n: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(n).font(AppFont.ui(24, 700)).foregroundColor(Palette.ink)
            Text(label).font(AppFont.ui(12)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .card()
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12)
            Text(t).font(AppFont.ui(12)).foregroundColor(Palette.muted)
        }
    }

    private func streakText(_ n: Int) -> String {
        let r = n % 100
        if n == 0 { return L("لم تبدأ بعد") }
        if n == 1 { return L("يوم واحد") }
        if n == 2 { return L("يومان متتاليان") }
        if r >= 3 && r <= 10 { return ar(n) + L(" أيام متتالية") }
        if r >= 11 { return ar(n) + L(" يومًا متتاليًا") }
        return ar(n) + L(" يوم متتالٍ")
    }

    /** أطول سلسلة في السجل (حتى سنة) */
    private func bestStreak() -> Int {
        let set = Set(Reading.days)
        let cal = Calendar.current
        var best = 0, run = 0
        var d = cal.date(byAdding: .day, value: -400, to: Date()) ?? Date()
        let end = Date()
        while d <= end {
            if set.contains(Reading.dayKey(d)) { run += 1; best = max(best, run) } else { run = 0 }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? end.addingTimeInterval(1)
        }
        return best
    }
}
