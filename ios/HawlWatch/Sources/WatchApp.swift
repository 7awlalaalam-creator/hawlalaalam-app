import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit

@main
struct HawlWatchApp: App {
    @StateObject private var data = WatchData.shared

    var body: some Scene {
        WindowGroup {
            RootWatchView()
                .environmentObject(data)
                .environment(\.layoutDirection, Lang.dir)
                .environment(\.locale, Lang.locale)
                .tint(WColor.gold)
        }
    }
}

/** يستقبل من الآيفون الموقع والورد وآية اليوم، ويحفظها لتعمل الساعة دون الجوال */
final class WatchData: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchData()
    @Published var rev = 0

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func apply(_ c: [String: Any]) {
        let d = Store.d
        for k in ["lat", "lng"] { if let v = c[k] as? Double { d.set(v, forKey: k) } }
        for k in ["city", "country"] { if let v = c[k] as? String { d.set(v, forKey: k) } }
        if let v = c["calc_method"] as? Int { d.set(v, forKey: "calc_method") }
        let active = c["k_active"] as? Bool ?? false
        d.set(active, forKey: "w_k_active")
        for k in ["k_done", "k_target", "k_percent"] { if let v = c[k] as? Int { d.set(v, forKey: "w_" + k) } }
        if let v = c["k_line"] as? String { d.set(v, forKey: "w_k_line") }
        if let v = c["v_text"] as? String, !v.isEmpty { d.set(v, forKey: "w_v_text") }
        if let v = c["v_ref"] as? String { d.set(v, forKey: "w_v_ref") }
        d.set(Date().timeIntervalSince1970, forKey: "w_synced")
        DispatchQueue.main.async {
            self.rev += 1
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let c = session.receivedApplicationContext
        if !c.isEmpty { apply(c) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}

struct RootWatchView: View {
    @EnvironmentObject var data: WatchData

    var body: some View {
        TabView {
            PrayerPage()
            WirdPage()
            TasbeehPage()
            VersePage()
        }
        .tabViewStyle(.page)
        .id(data.rev)
    }
}

// MARK: - الصلاة القادمة

struct PrayerPage: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let list = WatchPrayer.upcoming(from: ctx.date, count: 5)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("الصلاة القادمة")).font(.system(size: 13, weight: .bold)).foregroundColor(WColor.gold)
                    if let first = list.first {
                        Text(Prayer.displayName(first.0, on: first.1)).font(.system(size: 30, weight: .bold))
                        Countdown(to: first.1)
                        Text(formatTime(first.1) + (Geo.city.isEmpty ? "" : " · " + Geo.city))
                            .font(.system(size: 13)).foregroundColor(WColor.muted)
                    }
                    if !Geo.has {
                        Text(L("افتح التطبيق في جوالك لتحديد موقعك"))
                            .font(.system(size: 12)).foregroundColor(WColor.goldSoft).padding(.top, 4)
                    }
                    Divider().padding(.vertical, 4)
                    ForEach(Array(list.dropFirst().enumerated()), id: \.offset) { _, p in
                        HStack {
                            Text(Prayer.displayName(p.0, on: p.1)).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(formatTime(p.1)).font(.system(size: 15)).foregroundColor(WColor.muted)
                        }
                    }
                }
            }
        }
    }
}

/** عدّاد تنازلي بالأرقام العربية (Text(timerInterval:) يعرض الأرقام الغربية) */
struct Countdown: View {
    let to: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            let left = max(0, Int(to.timeIntervalSince(ctx.date)))
            Text(left == 0 ? L("حان الآن") : ar(String(format: "%d:%02d:%02d", left / 3600, (left % 3600) / 60, left % 60)))
                .font(.system(size: 30, weight: .bold).monospacedDigit())
                .foregroundColor(WColor.gold)
        }
    }
}

// MARK: - ورد اليوم

struct WirdPage: View {
    var body: some View {
        let d = Store.d
        let active = d.bool(forKey: "w_k_active")
        let done = d.integer(forKey: "w_k_done"), target = d.integer(forKey: "w_k_target")
        VStack(spacing: 6) {
            Text(L("ورد اليوم")).font(.system(size: 13, weight: .bold)).foregroundColor(WColor.gold)
            if active && target > 0 {
                ZStack {
                    Circle().stroke(WColor.card, lineWidth: 8)
                    Circle().trim(from: 0, to: CGFloat(min(1, Double(done) / Double(max(1, target)))))
                        .stroke(WColor.gold, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(ar(done) + "/" + ar(target)).font(.system(size: 26, weight: .bold))
                        Text(L("صفحة")).font(.system(size: 12)).foregroundColor(WColor.muted)
                    }
                }
                .frame(width: 110, height: 110)
                Text(d.string(forKey: "w_k_line") ?? "").font(.system(size: 12)).foregroundColor(WColor.muted)
                    .multilineTextAlignment(.center).lineLimit(2)
            } else if active {
                Text(L("يوم راحة من الورد")).font(.system(size: 15))
            } else {
                Text(L("ابدأ ختمة من التطبيق في جوالك ليظهر وردك هنا"))
                    .font(.system(size: 14)).foregroundColor(WColor.muted).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - التسبيح

struct TasbeehPage: View {
    @AppStorage("w_tasbeeh") private var count = 0
    @AppStorage("w_tasbeeh_target") private var target = 33

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(L("التسبيح")).font(.system(size: 13, weight: .bold)).foregroundColor(WColor.gold)
                Spacer()
                Button(target == 33 ? L("٣٣") : L("١٠٠")) { target = target == 33 ? 100 : 33 }
                    .font(.system(size: 12, weight: .bold)).buttonStyle(.bordered).frame(width: 52)
            }
            Button {
                count += 1
                WKInterfaceDevice.current().play(count % target == 0 ? .success : .click)
            } label: {
                VStack(spacing: 2) {
                    Text(ar(count)).font(.system(size: 44, weight: .bold).monospacedDigit())
                    Text(L("من ") + ar(target) + (count >= target ? " · " + ar(count / target) + L(" دورة") : ""))
                        .font(.system(size: 12)).foregroundColor(WColor.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 18).fill(WColor.card))
            Button(L("ابدأ من جديد")) { count = 0 }
                .font(.system(size: 13)).foregroundColor(WColor.goldSoft)
        }
    }
}

// MARK: - آية اليوم

struct VersePage: View {
    private static let fallback: [(String, String)] = [
        (L("أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ"), L("سورة الرعد · الآية ٢٨")),
        (L("فَاذْكُرُونِي أَذْكُرْكُمْ وَاشْكُرُوا لِي وَلَا تَكْفُرُونِ"), L("سورة البقرة · الآية ١٥٢")),
        (L("فَإِنَّ مَعَ الْعُسْرِ يُسْرًا"), L("سورة الشرح · الآية ٥")),
        (L("وَهُوَ مَعَكُمْ أَيْنَ مَا كُنتُمْ"), L("سورة الحديد · الآية ٤")),
        (L("إِنَّ اللَّهَ مَعَ الصَّابِرِينَ"), L("سورة البقرة · الآية ١٥٣")),
    ]

    var body: some View {
        let d = Store.d
        let pick = Self.fallback[Int(Date().timeIntervalSince1970 / 86400) % Self.fallback.count]
        let text = d.string(forKey: "w_v_text") ?? pick.0
        let ref = d.string(forKey: "w_v_text") == nil ? pick.1 : (d.string(forKey: "w_v_ref") ?? "")
        ScrollView {
            VStack(spacing: 8) {
                Text(L("آية اليوم")).font(.system(size: 13, weight: .bold)).foregroundColor(WColor.gold)
                Text("﴿ " + text + " ﴾").font(.system(size: 18, weight: .medium))
                    .multilineTextAlignment(.center).lineSpacing(4)
                Text(ref).font(.system(size: 12)).foregroundColor(WColor.muted)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
