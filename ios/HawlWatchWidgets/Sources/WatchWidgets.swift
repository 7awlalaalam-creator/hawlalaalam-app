import SwiftUI
import WidgetKit

/** تعقيدات واجهة الساعة: الصلاة القادمة والعدّ التنازلي (تحسبها الساعة بنفسها من الموقع المحفوظ) */
struct PrayerEntry: TimelineEntry {
    let date: Date
    let index: Int
    let at: Date
    let located: Bool
}

struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry {
        PrayerEntry(date: Date(), index: Prayer.asr, at: Date().addingTimeInterval(3600), located: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        let n = WatchPrayer.upcoming(count: 1).first ?? (Prayer.fajr, Date().addingTimeInterval(3600))
        completion(PrayerEntry(date: Date(), index: n.0, at: n.1, located: Geo.has))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let now = Date()
        let list = WatchPrayer.upcoming(from: now, count: 6)
        var entries: [PrayerEntry] = []
        var start = now
        for p in list {
            entries.append(PrayerEntry(date: start, index: p.0, at: p.1, located: Geo.has))
            start = p.1.addingTimeInterval(1)
        }
        if entries.isEmpty { entries = [placeholder(in: context)] }
        completion(Timeline(entries: entries, policy: .after(start)))
    }
}

struct PrayerComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    var body: some View {
        let name = Prayer.displayName(entry.index, on: entry.at)
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(name).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(entry.at, style: .timer).font(.system(size: 11).monospacedDigit())
                        .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.5)
                }
                .padding(2)
            }
        case .accessoryInline:
            Text(name + " " + formatClockShort(entry.at))
        case .accessoryCorner:
            Text(name).font(.system(size: 12, weight: .bold))
                .widgetLabel { Text(formatClockShort(entry.at)) }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("الصلاة القادمة").font(.system(size: 12, weight: .bold)).foregroundColor(WColor.gold)
                Text(name + " · " + formatTime(entry.at)).font(.system(size: 15, weight: .bold))
                Text(entry.at, style: .timer).font(.system(size: 13).monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct HawlWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch.prayer", provider: PrayerProvider()) { e in
            PrayerComplicationView(entry: e)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .containerBackgroundIfAvailable()
        }
        .configurationDisplayName("الصلاة القادمة")
        .description("موعد الصلاة القادمة والعدّ التنازلي")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

extension View {
    /** watchOS 10 يطلب خلفية للحاوية؛ watchOS 9 لا يعرفها */
    @ViewBuilder func containerBackgroundIfAvailable() -> some View {
        if #available(watchOS 10.0, *) { self.containerBackground(.clear, for: .widget) } else { self }
    }
}
