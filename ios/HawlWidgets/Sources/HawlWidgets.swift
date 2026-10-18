import WidgetKit
import SwiftUI
import ActivityKit

/**
 * الويدجت على الشاشة الرئيسية وشاشة القفل — نفس ويدجت أندرويد:
 * آية اليوم، مواقيت الصلاة الذكي، ختمتي، رمضان.
 * تقرأ بياناتها من التخزين المشترك (App Group) الذي يكتبه التطبيق، وتحسب المواقيت بنفسها.
 */
@main
struct HawlWidgets: WidgetBundle {
    var body: some Widget {
        PrayerWidget()
        VerseWidget()
        KhatmaWidget()
        RamadanWidget()
        PrayerLiveActivity()
    }
}

// MARK: - مشترك

extension View {
    /** خلفية الويدجت (iOS 17 يطلب containerBackground) */
    @ViewBuilder func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            background(color)
        }
    }

    /** المظهر المختار في التطبيق: تلقائي، نهاري، ليلي */
    @ViewBuilder func appTheme() -> some View {
        let mode = Store.int("theme_mode", 0)
        if mode == 1 { environment(\.colorScheme, .light) }
        else if mode == 2 { environment(\.colorScheme, .dark) }
        else { self }
    }

    func widgetBase() -> some View {
        self.environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .appTheme()
    }
}

/** ألوان الويدجت (نفس w_* في أندرويد: عاجي نهارًا، داكن ليلًا) */
enum WColor {
    static let bg = Color.dyn(0xFFFDF8, 0x123640)
    static let text = Color.dyn(0x16353D, 0xFFFFFF)
    static let soft = Color.dyn(0x16353D, 0xEFE4CF)
    static let muted = Color.dyn(0x5D747C, 0xA9BABF)
    static let gold = Color.dyn(0x9A7332, 0xC9A876)
    static let track = Color.dyn(0xEFE4CF, 0x1E4A55)
    static let bar = Color(hex: 0xC9A876)
    static let cell = Color.dyn(0xF5F1E6, 0x1A4550)
}

struct WBar: View {
    var fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(WColor.track)
                Capsule().fill(WColor.bar).frame(width: max(4, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - مواقيت الصلاة

struct PrayerEntry: TimelineEntry {
    let date: Date
    let located: Bool
    let times: [Date]
    let nextIndex: Int
    let nextAt: Date
    let progress: Double
    let tip: Smart.Tip?
    let city: String
}

struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry { entry(at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) { completion(entry(at: Date())) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let now = Date()
        guard Geo.has else {
            completion(Timeline(entries: [entry(at: now)], policy: .after(now.addingTimeInterval(3600))))
            return
        }
        // مدخل كل دقيقة لساعتين: «المتبقي» وشريط التقدّم والبطاقة الذكية تتحدث وحدها
        let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60)
        var entries: [PrayerEntry] = []
        for m in 0..<120 { entries.append(entry(at: start.addingTimeInterval(Double(m) * 60))) }
        completion(Timeline(entries: entries, policy: .after(start.addingTimeInterval(118 * 60))))
    }

    func entry(at now: Date) -> PrayerEntry {
        guard Geo.has else {
            return PrayerEntry(date: now, located: false, times: [], nextIndex: 0, nextAt: now, progress: 0, tip: nil, city: "")
        }
        let cal = Calendar.current
        let t = Prayer.times(for: now)
        let nx = Prayer.next(now: now)
        // بداية الفترة الحالية: آخر صلاة (أو الشروق) مضت، وقبل الفجر: عشاء أمس
        var prev = t.filter { $0 <= now }.last
        if prev == nil, let y = cal.date(byAdding: .day, value: -1, to: now) { prev = Prayer.times(for: y)[Prayer.isha] }
        let span = max(1, nx.1.timeIntervalSince(prev ?? now))
        let progress = min(1, max(0, now.timeIntervalSince(prev ?? now) / span))
        return PrayerEntry(date: now, located: true, times: t, nextIndex: nx.0, nextAt: nx.1, progress: progress,
                           tip: Smart.tip(now), city: Geo.city)
    }
}

struct PrayerWidgetView: View {
    let entry: PrayerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if !entry.located {
                VStack(alignment: .leading, spacing: 6) {
                    Label("مواقيت الصلاة", systemImage: "clock").font(AppFont.ui(13, 700)).foregroundColor(WColor.gold)
                    Text("حدّد موقعك").font(AppFont.ui(18, 700)).foregroundColor(WColor.text)
                    Text("اضغط لفتح الإعدادات وتحديد موقعك").font(AppFont.ui(12)).foregroundColor(WColor.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .widgetURL(URL(string: "hawlapp://settings"))
            } else {
                switch family {
                case .accessoryInline:
                    Text(name + " " + formatTime(entry.nextAt))
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name + " " + formatTime(entry.nextAt)).font(AppFont.ui(15, 700))
                        Text(Prayer.remaining(entry.nextAt.timeIntervalSince(entry.date), after: true)).font(AppFont.ui(13))
                        ProgressView(value: entry.progress)
                    }
                case .accessoryCircular:
                    Gauge(value: entry.progress) { Text(name).font(AppFont.ui(10, 700)) }
                        .gaugeStyle(.accessoryCircularCapacity)
                case .systemSmall:
                    small
                default:
                    full
                }
            }
        }
        .widgetBackground(WColor.bg)
        .widgetBase()
    }

    private var name: String { Prayer.displayName(entry.nextIndex, on: entry.nextAt) }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("الصلاة القادمة", systemImage: "clock").font(AppFont.ui(11, 700)).foregroundColor(WColor.gold)
            Text(name).font(AppFont.ui(22, 700)).foregroundColor(WColor.text)
            Text(formatTime(entry.nextAt)).font(AppFont.ui(14)).foregroundColor(WColor.muted)
            Spacer(minLength: 0)
            Text(Prayer.remaining(entry.nextAt.timeIntervalSince(entry.date), after: true))
                .font(AppFont.ui(15, 700)).foregroundColor(WColor.gold)
            WBar(fraction: entry.progress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "hawlapp://prayer"))
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 7) {
            HStack {
                Text(hijriToday(entry.date) + (entry.city.isEmpty ? "" : " · " + entry.city))
                    .font(AppFont.ui(11)).foregroundColor(WColor.muted).lineLimit(1)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(name + " " + formatTime(entry.nextAt)).font(AppFont.ui(20, 700)).foregroundColor(WColor.text)
                Spacer()
                Text("المتبقي ").font(AppFont.ui(11)).foregroundColor(WColor.muted)
                Text(Prayer.remaining(entry.nextAt.timeIntervalSince(entry.date), after: false))
                    .font(AppFont.ui(15, 700)).foregroundColor(WColor.gold)
            }
            WBar(fraction: entry.progress)
            HStack(spacing: 4) {
                ForEach(Array(Prayer.alerts.enumerated()), id: \.offset) { _, p in
                    let isNext = p == entry.nextIndex && entry.nextAt.timeIntervalSince(entry.date) < 20 * 3600
                    VStack(spacing: 2) {
                        Text(Prayer.names[p]).font(AppFont.ui(11, isNext ? 700 : 400))
                        Text(formatClockShort(entry.times[p])).font(AppFont.ui(12, 700))
                    }
                    .foregroundColor(isNext ? WColor.gold : WColor.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 9).fill(isNext ? WColor.cell : Color.clear))
                }
            }
            if let tip = entry.tip {
                Link(destination: Links.deep(tip.url)) {
                    Text(tip.text).font(AppFont.ui(11, 500)).foregroundColor(WColor.soft)
                        .lineLimit(family == .systemLarge ? 3 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 9).fill(WColor.cell))
                }
            }
        }
        .widgetURL(URL(string: "hawlapp://prayer"))
    }
}

struct PrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrayerWidget", provider: PrayerProvider()) { PrayerWidgetView(entry: $0) }
            .configurationDisplayName("مواقيت الصلاة")
            .description("الصلاة القادمة مع عدّاد، والتاريخ الهجري، وبطاقة ذكية تتغير مع وقتك: الضحى، ساعة الإجابة، الثلث الأخير، الصيام المسنون")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - آية اليوم

struct VerseEntry: TimelineEntry {
    let date: Date
    let verse: VerseSource.Verse?
}

struct VerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: Date(), verse: VerseSource.Verse(surah: 2, ayah: 286, text: "لَا يُكَلِّفُ ٱللَّهُ نَفۡسًا إِلَّا وُسۡعَهَاۚ"))
    }

    func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
        completion(VerseEntry(date: Date(), verse: VerseSource.cached() ?? placeholder(in: context).verse))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        Task {
            // يوم جديد: نجلب آية اليوم من الموقع (أو آية بحسب التاريخ دون إنترنت)
            let v = VerseSource.fresh ? VerseSource.cached() : await VerseSource.fetch(userAgent: "HawlalaalamApp/1 (iOS widget)")
            let now = Date()
            let tomorrow = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400)).addingTimeInterval(120)
            let next = VerseSource.fresh ? tomorrow : min(tomorrow, now.addingTimeInterval(3 * 3600))
            completion(Timeline(entries: [VerseEntry(date: now, verse: v ?? VerseSource.cached())], policy: .after(next)))
        }
    }
}

struct VerseWidgetView: View {
    let entry: VerseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let v = entry.verse {
                switch family {
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("آية اليوم").font(AppFont.ui(11, 700))
                        Text(v.text).font(AppFont.quran(13)).lineLimit(3)
                    }
                default:
                    VStack(spacing: 6) {
                        HStack {
                            Label("آية اليوم", systemImage: "sparkle").font(AppFont.ui(12, 700)).foregroundColor(WColor.gold)
                            Spacer()
                            if family != .systemSmall {
                                Text(hijriToday(entry.date)).font(AppFont.ui(11)).foregroundColor(WColor.muted).lineLimit(1)
                                Link(destination: URL(string: "hawlapp://share-verse")!) {
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(WColor.gold).padding(.leading, 6)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Text(Quran.withNumber(v.text, v.ayah))
                            .font(AppFont.quran(size(v.text)))
                            .foregroundColor(WColor.text)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .minimumScaleFactor(0.55)
                        Spacer(minLength: 0)
                        Text(v.ref).font(AppFont.ui(11)).foregroundColor(WColor.muted).lineLimit(1)
                    }
                }
            } else {
                Text("افتح التطبيق لتحميل آية اليوم").font(AppFont.ui(13)).foregroundColor(WColor.muted)
            }
        }
        .widgetURL(URL(string: "hawlapp://today"))
        .widgetBackground(WColor.bg)
        .widgetBase()
    }

    private func size(_ t: String) -> CGFloat {
        switch family {
        case .systemSmall: return t.count < 60 ? 16 : 13
        case .systemLarge: return t.count < 120 ? 26 : (t.count < 300 ? 22 : 18)
        default: return t.count < 80 ? 20 : (t.count < 180 ? 17 : 14)
        }
    }
}

struct VerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VerseWidget", provider: VerseProvider()) { VerseWidgetView(entry: $0) }
            .configurationDisplayName("آية اليوم")
            .description("آية اليوم من حول العالم، تتجدد يوميًا")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - ختمتي

struct KhatmaEntry: TimelineEntry {
    let date: Date
    let running: Bool
    let percent: Int
    let line: String
    let page: Int
}

struct KhatmaProvider: TimelineProvider {
    func placeholder(in context: Context) -> KhatmaEntry {
        KhatmaEntry(date: Date(), running: true, percent: 42, line: "ورد اليوم: صفحة ٢٥٤ إلى ٢٧٣ · إبراهيم", page: 254)
    }

    func getSnapshot(in context: Context, completion: @escaping (KhatmaEntry) -> Void) { completion(current()) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KhatmaEntry>) -> Void) {
        let tomorrow = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [current()], policy: .after(tomorrow)))
    }

    private func current() -> KhatmaEntry {
        if Khatma.running {
            return KhatmaEntry(date: Date(), running: true, percent: Khatma.percent, line: Khatma.todayLine, page: Khatma.nextPage)
        }
        return KhatmaEntry(date: Date(), running: false, percent: 0, line: "اضغط لتبدأ ختمتك", page: 1)
    }
}

struct KhatmaWidgetView: View {
    let entry: KhatmaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                Gauge(value: Double(entry.percent), in: 0...100) { Text("ختمتي") } currentValueLabel: { Text(ar(entry.percent)) }
                    .gaugeStyle(.accessoryCircularCapacity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("ختمتي", systemImage: "book.closed").font(AppFont.ui(12, 700)).foregroundColor(WColor.gold)
                    if entry.running {
                        Text(ar(entry.percent) + "٪").font(AppFont.ui(28, 700)).foregroundColor(WColor.text)
                        WBar(fraction: Double(entry.percent) / 100)
                    }
                    Spacer(minLength: 0)
                    Text(entry.line).font(AppFont.ui(12, 500)).foregroundColor(WColor.soft).lineLimit(3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: entry.running ? "hawlapp://mushaf?page=\(entry.page)" : "hawlapp://khatma"))
        .widgetBackground(WColor.bg)
        .widgetBase()
    }
}

struct KhatmaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KhatmaWidget", provider: KhatmaProvider()) { KhatmaWidgetView(entry: $0) }
            .configurationDisplayName("ختمتي")
            .description("تقدّم ختمتك وورد اليوم")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

// MARK: - رمضان

struct RamadanEntry: TimelineEntry {
    let date: Date
    let active: Bool
    let daysUntil: Int
    let day: Int
    let located: Bool
    let iftar: Bool
    let at: Date
    let imsak: Date
    let iftarAt: Date
    let city: String
    let year: Int
}

struct RamadanProvider: TimelineProvider {
    func placeholder(in context: Context) -> RamadanEntry { entry(Date()) }

    func getSnapshot(in context: Context, completion: @escaping (RamadanEntry) -> Void) { completion(entry(Date())) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RamadanEntry>) -> Void) {
        let e = entry(Date())
        let tomorrow = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)).addingTimeInterval(60)
        let next = e.active && e.located ? min(tomorrow, e.at.addingTimeInterval(5)) : tomorrow
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func entry(_ now: Date) -> RamadanEntry {
        let active = Ramadan.active(now)
        let ev: (iftar: Bool, at: Date) = Geo.has && active ? Ramadan.nextEvent(now) : (iftar: false, at: now)
        let until = active ? 0 : Ramadan.daysUntil(now)
        let target = Calendar.current.date(byAdding: .day, value: max(0, until), to: now) ?? now
        let year = Hijri.calendar.component(.year, from: target)
        return RamadanEntry(date: now, active: active, daysUntil: until, day: Ramadan.day(now), located: Geo.has,
                            iftar: ev.iftar, at: ev.at,
                            imsak: Geo.has ? Ramadan.imsak(now) : now, iftarAt: Geo.has ? Ramadan.iftar(now) : now,
                            city: Geo.city, year: year)
    }
}

struct RamadanWidgetView: View {
    let entry: RamadanEntry

    private var timesLine: String {
        var t: String = "الإمساك "
        t += formatTime(entry.imsak)
        t += " · الإفطار "
        t += formatTime(entry.iftarAt)
        if !entry.city.isEmpty { t += " · " + entry.city }
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !entry.active {
                Text("🌙 رمضان " + ar(entry.year)).font(AppFont.ui(13, 700)).foregroundColor(WColor.gold)
                Text(entry.daysUntil > 0 ? "بعد " + ar(entry.daysUntil) + " يومًا" : "قريبًا").font(AppFont.ui(24, 700)).foregroundColor(WColor.text)
                Spacer(minLength: 0)
                Text("بلّغنا الله رمضان").font(AppFont.ui(12)).foregroundColor(WColor.muted)
            } else if !entry.located {
                Text("🌙 رمضان كريم").font(AppFont.ui(13, 700)).foregroundColor(WColor.gold)
                Text("حدّد موقعك").font(AppFont.ui(22, 700)).foregroundColor(WColor.text)
                Spacer(minLength: 0)
                Text("لعرض الإمساك والإفطار").font(AppFont.ui(12)).foregroundColor(WColor.muted)
            } else {
                HStack {
                    Text(entry.iftar ? "🌙 الإفطار بعد" : "🌙 الإمساك بعد").font(AppFont.ui(13, 700)).foregroundColor(WColor.gold)
                    Spacer()
                    Text(Ramadan.ordinal(entry.day)).font(AppFont.ui(11)).foregroundColor(WColor.muted)
                }
                Text(timerInterval: entry.date...max(entry.date, entry.at), countsDown: true)
                    .font(AppFont.ui(28, 700)).foregroundColor(WColor.text).monospacedDigit()
                Spacer(minLength: 0)
                Text(timesLine)
                    .font(AppFont.ui(11)).foregroundColor(WColor.muted).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "hawlapp://today"))
        .widgetBackground(WColor.bg)
        .widgetBase()
    }
}

struct RamadanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RamadanWidget", provider: RamadanProvider()) { RamadanWidgetView(entry: $0) }
            .configurationDisplayName("رمضان: الإفطار والإمساك")
            .description("عدّاد الإفطار والإمساك في رمضان، وكم بقي على رمضان قبله")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}


// MARK: - الصلاة القادمة: الجزيرة الديناميكية وشاشة القفل

#if canImport(ActivityKit)
/** عدّاد تنازلي يرسمه النظام؛ وبعد دخول الوقت «حان الآن» (نطاق الوقت لا يكون مقلوبًا أبدًا) */
@available(iOS 16.1, *)
private struct LiveTimer: View {
    var at: Date
    var size: CGFloat
    var color: Color

    var body: some View {
        if at > Date() {
            Text(timerInterval: Date()...at, countsDown: true)
                .font(.system(size: size, weight: .bold).monospacedDigit())
                .foregroundColor(color)
                .multilineTextAlignment(.center)
        } else {
            Text("حان الآن").font(AppFont.ui(size * 0.8, 700)).foregroundColor(color)
        }
    }
}

@available(iOS 16.1, *)
struct PrayerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerLiveAttributes.self) { ctx in
            PrayerLiveLockView(state: ctx.state)
                .activityBackgroundTint(Color(hex: 0x123640))
                .activitySystemActionForegroundColor(Color(hex: 0xE9D9B8))
                .widgetURL(URL(string: "hawlapp://prayer"))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("الصلاة القادمة").font(AppFont.ui(11, 500)).foregroundColor(Color(hex: 0xA9BABF))
                        Text(ctx.state.name).font(AppFont.ui(20, 700)).foregroundColor(.white)
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveTimer(at: ctx.state.at, size: 24, color: Color(hex: 0xC9A876))
                        .frame(maxWidth: 110)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("تدخل " + ctx.state.clock + (ctx.state.city.isEmpty ? "" : " · " + ctx.state.city))
                        .font(AppFont.ui(13)).foregroundColor(Color(hex: 0xEFE4CF))
                        .environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "clock").foregroundColor(Color(hex: 0xC9A876))
                    Text(ctx.state.name).font(AppFont.ui(13, 700)).foregroundColor(.white)
                }
            } compactTrailing: {
                LiveTimer(at: ctx.state.at, size: 14, color: Color(hex: 0xC9A876))
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "clock").foregroundColor(Color(hex: 0xC9A876))
            }
            .widgetURL(URL(string: "hawlapp://prayer"))
        }
    }
}

@available(iOS 16.1, *)
struct PrayerLiveLockView: View {
    var state: PrayerLiveAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("الصلاة القادمة").font(AppFont.ui(12, 500)).foregroundColor(Color(hex: 0xC9A876))
                Text(state.name).font(AppFont.ui(26, 700)).foregroundColor(.white)
                Text(state.clock + (state.city.isEmpty ? "" : " · " + state.city))
                    .font(AppFont.ui(13)).foregroundColor(Color(hex: 0xA9BABF)).lineLimit(1)
            }
            Spacer(minLength: 8)
            LiveTimer(at: state.at, size: 30, color: Color(hex: 0xE9D9B8))
                .frame(maxWidth: 140)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
    }
}
#endif
