import SwiftUI

/**
 * متابعة الصلوات (مثل PrayerLog.java في أندرويد، بنفس المفتاح والصيغة فتنتقل بالنسخ الاحتياطي بين النظامين):
 * المفتاح «prayer_log» نص JSON: {"رقم اليوم": قناع} — البت ٠ الفجر، ١ الظهر، ٢ العصر، ٣ المغرب، ٤ العشاء.
 * رقم اليوم = الأيام منذ ١٩٧٠ بالتوقيت المحلي. نحتفظ بآخر ٤٠٠ يوم فقط.
 */
enum PrayerLog {
    static let key = "prayer_log"
    static let names = [L("الفجر"), L("الظهر"), L("العصر"), L("المغرب"), L("العشاء")]
    static let full = 0b11111

    static func day(_ d: Date = Date()) -> Int {
        Int(floor((d.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: d))) / 86400))
    }

    static func load() -> [Int: Int] {
        guard let s = Store.d.string(forKey: key), let data = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [Int: Int] = [:]
        for (k, v) in o { if let d = Int(k), let m = (v as? NSNumber)?.intValue { out[d] = m & full } }
        return out
    }

    private static func save(_ m: [Int: Int]) {
        let keep = day() - 400
        var o: [String: Int] = [:]
        for (d, v) in m where d >= keep && v != 0 { o[String(d)] = v }
        if let data = try? JSONSerialization.data(withJSONObject: o), let s = String(data: data, encoding: .utf8) {
            Store.d.set(s, forKey: key)
        }
    }

    static func mask(_ d: Int) -> Int { load()[d] ?? 0 }

    static func toggle(day d: Int, prayer i: Int) {
        var m = load()
        m[d] = (m[d] ?? 0) ^ (1 << i)
        save(m)
    }

    static func count(_ mask: Int) -> Int { (0..<5).filter { mask & (1 << $0) != 0 }.count }

    /** صلوات آخر ٧ أيام (منها اليوم) */
    static func week() -> Int {
        let m = load(), t = day()
        return (0..<7).reduce(0) { $0 + count(m[t - $1] ?? 0) }
    }

    /** أيام متتالية بالصلوات الخمس كاملة (اليوم يُحسب إن اكتمل، وإلا نبدأ من أمس) */
    static func streak() -> Int {
        let m = load()
        var d = day()
        if (m[d] ?? 0) != full { d -= 1 }
        var n = 0
        while (m[d] ?? 0) == full { n += 1; d -= 1 }
        return n
    }
}

/** بطاقة «صلواتي اليوم» في الشاشة الرئيسية: الصلوات الخمس، وتُعلَّم الصلاة التي دخل وقتها بلمسة */
struct PrayerLogCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        _ = state.rev
        return TimelineView(.everyMinute) { ctx in
            let t = Prayer.times(for: ctx.date)
            let today = PrayerLog.day(ctx.date)
            let m = PrayerLog.mask(today)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("صلواتي اليوم")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                    Spacer()
                    Text(ar(PrayerLog.count(m)) + L(" من ٥")).font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
                }
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        let on = m & (1 << i) != 0
                        let due = t[Prayer.alerts[i]] <= ctx.date
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            PrayerLog.toggle(day: today, prayer: i)
                            state.touch()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(on ? Palette.gold : Palette.muted.opacity(due ? 0.8 : 0.35))
                                Text(PrayerLog.names[i]).font(AppFont.ui(12, on ? 700 : 500))
                                    .foregroundColor(due || on ? Palette.ink : Palette.muted.opacity(0.6))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Palette.chip : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .disabled(!due && !on)
                        .accessibilityLabel(PrayerLog.names[i] + (on ? L("، صلّيتها") : due ? L("، لم تُسجَّل بعد") : L("، لم يدخل وقتها")))
                    }
                }
                NavigationLink(value: Screen.journey) {
                    Text(L("هذا الأسبوع: ") + ar(PrayerLog.week()) + L(" من ٣٥ صلاة"))
                        .font(AppFont.ui(12)).foregroundColor(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .card()
        }
    }
}

/** قسم الصلوات في «رحلتي»: آخر ٧ أيام × ٥ صلوات، والمجموع، والسلسلة */
struct PrayerLogJourney: View {
    var body: some View {
        let m = PrayerLog.load(), t = PrayerLog.day()
        let cal = Calendar.current
        let streak = PrayerLog.streak()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("صلواتي")).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                Spacer()
                Text(ar(PrayerLog.week()) + L(" من ٣٥ هذا الأسبوع")).font(AppFont.ui(13)).foregroundColor(Palette.muted)
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Text("").frame(width: 46)
                    ForEach(0..<5, id: \.self) { i in
                        Text(PrayerLog.names[i]).font(AppFont.ui(11)).foregroundColor(Palette.muted)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                    }
                }
                ForEach((0..<7).reversed(), id: \.self) { k in
                    let d = t - k
                    let mask = m[d] ?? 0
                    let date = cal.date(byAdding: .day, value: -k, to: Date()) ?? Date()
                    GridRow {
                        Text(k == 0 ? L("اليوم") : weekday(date)).font(AppFont.ui(11, k == 0 ? 700 : 400))
                            .foregroundColor(Palette.ink).frame(width: 46, alignment: .leading)
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(mask & (1 << i) != 0 ? Palette.gold : Palette.chip)
                                .frame(height: 22)
                        }
                    }
                }
            }
            if streak >= 1 {
                Label(streak == 1 ? L("يوم كامل بالصلوات الخمس") : ar(streak) + L(" أيام متتالية بالصلوات الخمس"), systemImage: "flame")
                    .font(AppFont.ui(13, 700)).foregroundColor(Palette.goldDeep)
            }
            Text(L("سجّل صلواتك من بطاقة «صلواتي اليوم» في الصفحة الرئيسية.")).font(AppFont.ui(12)).foregroundColor(Palette.muted)
        }
        .padding(16)
        .card()
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Lang.locale
        f.dateFormat = "EEEE"
        return f.string(from: d)
    }
}
