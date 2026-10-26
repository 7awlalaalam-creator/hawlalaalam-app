import SwiftUI
import UIKit
import UserNotifications

// «وضع المسجد» و«فحص الأذان» و«خصوصيتك» و«أثرك» و«القرآن حول العالم» — نفس منطق أندرويد
// (Mosque.java · AdhanCheck.java · Stats.java)

// MARK: - الإحصاءات المجهولة

enum Stats {
    static let api = URL(string: Links.homeString + "stats-api.php")!
    private static let alpha = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    private static var dayKey: Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /** صفحة مكث عليها القارئ في المصحف (تُحسب مرة لكل صفحة في اليوم) */
    static func onPage(_ page: Int) {
        guard (1...604).contains(page) else { return }
        let d = Store.d
        var bits = Array(d.string(forKey: "st_bits") ?? "")
        if Store.int("st_day", 0) != dayKey || bits.count != 604 {
            bits = Array(repeating: "0", count: 604)
            d.set(dayKey, forKey: "st_day")
            d.set(0, forKey: "st_today")
        }
        if bits[page - 1] == "1" { return }
        bits[page - 1] = "1"
        d.set(String(bits), forKey: "st_bits")
        d.set(Store.int("st_today", 0) + 1, forKey: "st_today")
        d.set(min(5000, Store.int("st_pending", 0) + 1), forKey: "st_pending")
    }

    static var today: Int { Store.int("st_day", 0) == dayKey ? Store.int("st_today", 0) : 0 }

    static func onKhatma() {
        if !ref.isEmpty { Store.d.set(Store.int("st_khatma_pending", 0) + 1, forKey: "st_khatma_pending") }
    }

    static var mapOn: Bool {
        get { Store.bool("st_map", false) }
        set { Store.d.set(newValue, forKey: "st_map") }
    }

    static var code: String {
        if let s = Store.d.string(forKey: "st_code") { return s }
        let s = String((0..<6).map { _ in alpha.randomElement()! })
        Store.d.set(s, forKey: "st_code")
        return s
    }

    static var link: String { "https://7awlalaalam.com/app?r=" + code }

    static var shareText: String {
        "تطبيق «القرآن حول العالم»: مصحف وتلاوات ومواقيت وأذان وأذكار، بلا إعلانات ولا حساب.\n"
            + "حمّله من هنا: \(link)\n\n"
            + "وعند فتحه اكتب رمز الدعوة \(code) في «أثرك» ليُكتب لي أثر قراءتك، «من دلّ على خير فله مثل أجر فاعله»."
    }

    static var ref: String { Store.string("st_ref") }

    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let r = s.range(of: "R=", options: .backwards) { s = String(s[r.upperBound...]) }
        let out = s.filter { alpha.contains($0) }
        return out.count == 6 ? out : ""
    }

    /** يحفظ رمز من دعاك؛ يعيد رسالة خطأ أو nil */
    static func setRef(_ raw: String) -> String? {
        let s = clean(raw)
        if s.isEmpty { return "الرمز من ٦ حروف وأرقام، مثل K7Q2MA" }
        if s == code { return "هذا رمزك أنت، اكتب رمز من دعاك" }
        if !ref.isEmpty { return "سجّلت رمزًا من قبل" }
        Store.d.set(s, forKey: "st_ref")
        Store.d.set(false, forKey: "st_ref_joined")
        return nil
    }

    /** الدولة من إعدادات المنطقة في الجوال (لا من الموقع) */
    static var country: String {
        let r = Locale.current.regionCode ?? ""
        return r.count == 2 ? r.uppercased() : ""
    }

    static func countryName(_ cc: String) -> String {
        Locale(identifier: "ar").localizedString(forRegionCode: cc) ?? cc
    }

    /** عند فتح التطبيق: لا يرسل شيئًا إلا بموافقة «الخريطة» أو رمز دعوة */
    static func syncSoon() {
        if !mapOn && ref.isEmpty { return }
        let last = Store.d.double(forKey: "st_sync_at")
        if Date().timeIntervalSince1970 - last < 3 * 3600 && Store.bool("st_ref_joined", true) { return }
        Task.detached { await Stats.sync() }
    }

    static func sync() async {
        let ref = Stats.ref, map = mapOn
        if !map && ref.isEmpty { return }
        if !ref.isEmpty && !Store.bool("st_ref_joined", true) {
            if await post(["action": "join", "ref": ref]) { Store.d.set(true, forKey: "st_ref_joined") }
        }
        let pending = min(604, Store.int("st_pending", 0))
        let khatmas = min(3, Store.int("st_khatma_pending", 0))
        if pending > 0 || khatmas > 0 {
            var body: [String: Any] = ["action": "add", "pages": pending]
            if map { body["cc"] = country }
            if !ref.isEmpty { body["ref"] = ref; body["khatmas"] = khatmas }
            if await post(body) {
                Store.d.set(max(0, Store.int("st_pending", 0) - pending), forKey: "st_pending")
                Store.d.set(max(0, Store.int("st_khatma_pending", 0) - khatmas), forKey: "st_khatma_pending")
            }
        }
        Store.d.set(Date().timeIntervalSince1970, forKey: "st_sync_at")
    }

    private static func post(_ body: [String: Any]) async -> Bool {
        var r = URLRequest(url: api, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.setValue(WebConfig.userAgentMark, forHTTPHeaderField: "User-Agent")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 400
    }

    static func get(_ query: String) async -> [String: Any]? {
        guard let url = URL(string: api.absoluteString + "?" + query) else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.setValue(WebConfig.userAgentMark, forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 400 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - وضع المسجد (آيفون: تذكير هادئ عند الإقامة؛ النظام لا يسمح لتطبيق بتصميت الجوال)

enum Mosque {
    static var on: Bool { Store.bool("mosque_on", false) }

    /** دقائق الإقامة بعد الأذان (أم القرى) */
    static func iqama(_ k: Int) -> Int {
        switch k {
        case Prayer.fajr: return 25
        case Prayer.maghrib: return 10
        default: return 20
        }
    }

    /** طلبات تذكير الإقامة ليوم واحد (تُضاف في Notifications.build) */
    static func requests(day: Date, times t: [Date], now: Date) -> [(UNNotificationRequest, Date)] {
        guard on, t.count > Prayer.isha else { return [] }
        var out: [(UNNotificationRequest, Date)] = []
        let cal = Calendar.current
        for k in Prayer.alerts {
            let friday = k == Prayer.dhuhr && cal.component(.weekday, from: t[k]) == 6
            // الجمعة: بعد الأذان الأول بدقيقتين (الخطبة)، وغيرها قبل الإقامة بدقيقتين
            let at = friday ? t[k].addingTimeInterval(2 * 60) : t[k].addingTimeInterval(Double(iqama(k) - 2) * 60)
            if at <= now { continue }
            let c = UNMutableNotificationContent()
            c.title = friday ? "الخطبة: صمّت جوالك" : "أوشكت الإقامة: صمّت جوالك"
            c.body = "اقلب مفتاح الصامت، أو فعّل «عدم الإزعاج» لمدة ساعة من مركز التحكم"
            c.subtitle = "وضع المسجد"
            c.sound = .default
            c.threadIdentifier = "mosque"
            if #available(iOS 15.0, *) { c.interruptionLevel = .timeSensitive }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            let id = "mosque-\(k)-\(comps.month ?? 0)-\(comps.day ?? 0)"
            out.append((UNNotificationRequest(identifier: id, content: c,
                                              trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)), at))
        }
        return out
    }
}

// MARK: - فحص الأذان

@MainActor
enum AdhanCheck {
    struct Item: Identifiable {
        let id = UUID()
        let ok: Bool, title: String, sub: String?, fix: String?, action: (() -> Void)?
    }

    static func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    static func run() async -> [Item] {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        var l: [Item] = []
        let auth = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
        l.append(Item(ok: auth, title: auth ? "الإشعارات مسموحة" : "إشعارات التطبيق متوقفة",
                      sub: auth ? nil : "يحين الوقت ولا يظهر إشعار الأذان", fix: "أصلحه", action: openSettings))
        if auth {
            let sound = s.soundSetting == .enabled
            l.append(Item(ok: sound, title: sound ? "صوت الإشعارات مفعّل · " + AdhanSound.name(AdhanSound.current) : "صوت الإشعارات مطفأ",
                          sub: sound ? nil : "يظهر الأذان بلا صوت", fix: "أصلحه", action: openSettings))
        }
        let on = Store.bool("adhan_on", false)
        l.append(Item(ok: on, title: on ? "تنبيه الأذان مفعّل" : "تنبيه الأذان مطفأ",
                      sub: on ? nil : "من «التنبيهات» في التطبيق", fix: nil, action: nil))
        l.append(Item(ok: Geo.has, title: Geo.has ? "الموقع محدّد" + (Geo.city.isEmpty ? "" : ": " + Geo.city) : "لم تُحدَّد مدينتك",
                      sub: Geo.has ? nil : "المواقيت تُحسب حسب مدينتك", fix: nil, action: nil))
        // آيفون يحفظ إشعارات أسبوع مقدّمًا؛ يتجدد الجدول عند فتح التطبيق أو بالتحديث في الخلفية
        let refresh = UIApplication.shared.backgroundRefreshStatus == .available
        let until = Store.d.double(forKey: "notif_until")
        let daysLeft = Int((until - Date().timeIntervalSince1970) / 86400)
        if on && Geo.has && !refresh && daysLeft < 3 {
            l.append(Item(ok: false, title: "تحديث التطبيق في الخلفية متوقف",
                          sub: "افتح التطبيق مرة كل أيام ليتجدد جدول الأذان، أو فعّله من الإعدادات", fix: "أصلحه", action: openSettings))
        } else if on && Geo.has {
            l.append(Item(ok: true, title: "الأذان مجدول للأيام القادمة", sub: nil, fix: nil, action: nil))
        }
        return l
    }

    static func problems(_ l: [Item]) -> Int { l.filter { !$0.ok }.count }

    /** «جرّب الأذان الآن»: إشعار تجريبي بعد ١٠ ثوانٍ بالصوت المختار */
    static func test() {
        let c = UNMutableNotificationContent()
        c.title = "أذان تجريبي"
        c.body = "إن سمعت هذا فالأذان سيصلك في وقته بإذن الله"
        c.subtitle = "الأذان"
        c.sound = AdhanSound.notificationSound(for: Prayer.dhuhr)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "adhan-test", content: c,
                                                                      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
    }

    /** من التحديث في الخلفية: مرة في الأسبوع، وإشعار فقط إن وُجدت مشكلة */
    static func weeklyIfDue() async {
        guard Store.bool("adhan_on", false) else { return }
        let last = Store.d.double(forKey: "adhan_check_at")
        let now = Date().timeIntervalSince1970
        if last == 0 { Store.d.set(now, forKey: "adhan_check_at"); return }
        if now - last < 7 * 86400 { return }
        Store.d.set(now, forKey: "adhan_check_at")
        let l = await run()
        let n = problems(l)
        guard n > 0, let first = l.first(where: { !$0.ok }), first.title != "إشعارات التطبيق متوقفة" else { return }
        let c = UNMutableNotificationContent()
        c.title = n == 1 ? "شيء واحد قد يؤخّر الأذان" : ar(n) + " أشياء قد تؤخّر الأذان"
        c.body = first.title + " · اضغط لإصلاحه"
        c.sound = .default
        c.userInfo = ["route": "adhancheck"]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "adhan-check", content: c, trigger: nil))
    }
}

// MARK: - الشاشات

/** الصفر بالأرقام العربية نقطة صغيرة يخطئها القارئ: شرطة بدلها */
private func num(_ n: Int) -> String { n <= 0 ? "—" : ar(n) }

private struct DarkHero<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 6) { content }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22).padding(.horizontal, 18)
            .background(PatternBackground().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
    }
}

private struct CheckMark: View {
    var ok: Bool
    var body: some View {
        Text(ok ? "✓" : "!")
            .font(AppFont.ui(15, 700))
            .foregroundColor(ok ? Color(hex: 0x2F8F5B) : Color(hex: 0xB3412F))
            .frame(width: 30, height: 30)
            .background(Circle().fill((ok ? Color(hex: 0x2F8F5B) : Color(hex: 0xB3412F)).opacity(0.15)))
            .accessibilityHidden(true)
    }
}

struct MosqueView: View {
    @State private var on = Mosque.on

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DarkHero {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.slash").font(.system(size: 24)).foregroundColor(Palette.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("تذكير قبل الإقامة").font(AppFont.ui(17, 700)).foregroundColor(.white)
                            Text("ينبّهك بهدوء لتصمّت جوالك قبل الصلاة").font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted)
                        }
                        Spacer()
                        Toggle("", isOn: $on).labelsHidden().tint(Palette.gold)
                            .accessibilityLabel("تفعيل وضع المسجد")
                    }
                }
                .onChange(of: on) { v in
                    Store.d.set(v, forKey: "mosque_on")
                    Notifications.reschedule()
                }

                Text("الإقامة بعد الأذان (تقويم أم القرى)").font(AppFont.ui(15, 700)).foregroundColor(Palette.ink).padding(.top, 6)
                VStack(spacing: 0) {
                    row("الفجر", "بعد ٢٥ دقيقة")
                    Divider()
                    row("الظهر · العصر · العشاء", "بعد ٢٠ دقيقة")
                    Divider()
                    row("المغرب", "بعد ١٠ دقائق")
                    Divider()
                    row("الجمعة", "عند الخطبة")
                }
                .padding(.horizontal, 16).card()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundColor(Palette.goldDeep)
                    Text("في آيفون لا يسمح النظام لأي تطبيق بتصميت الجوال، فيصلك تنبيه هادئ قبل الإقامة بدقيقتين. "
                         + "أسرع طريقة: اسحب مركز التحكم واضغط مطولًا على «التركيز» ← «عدم الإزعاج» ← «لمدة ساعة واحدة».")
                        .font(AppFont.ui(12)).foregroundColor(Palette.muted).lineSpacing(4)
                }
                .padding(14).card(Palette.chip, border: Palette.ivoryBorder, radius: 16)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("وضع المسجد")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
            Spacer()
            Text(b).font(AppFont.ui(14, 700)).foregroundColor(Palette.goldDeep)
        }
        .padding(.vertical, 12)
    }
}

struct PrivacyView: View {
    static let points: [(String, String)] = [
        ("بلا إعلانات أبدًا", "لا قبل المواقيت ولا بين الصفحات"),
        ("بلا حساب ولا تسجيل", "لا رقم جوال ولا بريد ولا كلمة مرور"),
        ("موقعك لا يصلنا", "المواقيت والقبلة تُحسب على جوالك نفسه"),
        ("تلاوتك لا تُحفظ ولا تصلنا", "التسميع يمرّ بخدمة التعرّف في جوالك، ولا يُحفظ الصوت"),
        ("لا بيع ولا مشاركة لبياناتك", "ولا مكتبات تتبّع أو تحليلات"),
    ]

    static var shareText: String {
        "تطبيق «القرآن حول العالم» صدقة جارية:\n" + points.map { "✓ " + $0.0 }.joined(separator: "\n")
            + "\n\nحمّله: https://7awlalaalam.com/app"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DarkHero {
                    Image(systemName: "checkmark.shield").font(.system(size: 44)).foregroundColor(Palette.gold)
                    Text("تطبيق بلا مقابل، وبلا ثمن خفي").font(AppFont.ui(21, 700)).foregroundColor(.white).multilineTextAlignment(.center)
                    Text("صدقة جارية: لا نبيع شيئًا، ولا نجمع شيئًا عنك").font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted)
                }
                VStack(spacing: 0) {
                    ForEach(Array(Self.points.enumerated()), id: \.offset) { i, p in
                        if i > 0 { Divider() }
                        HStack(spacing: 12) {
                            CheckMark(ok: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.0).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                                Text(p.1).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 11)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 14).card()
                (Text("للشفافية: ").foregroundColor(Palette.ink).bold()
                 + Text("الإشعارات الفورية تصل عبر خدمة Firebase بمعرّف جهاز مجهول لا يُربط باسمك، ويمكنك إيقافها من «التنبيهات». "
                        + "واسم مدينتك يعرفه الجوال من خدمة نظامه (أبل). "
                        + "وإن فعّلت «أضِف قراءتي للخريطة» أو أدخلت رمز دعوة، يُرسل عدد الصفحات واسم الدولة أو رمز الدعوة فقط، بلا أي معرّف."))
                    .font(AppFont.ui(12)).foregroundColor(Palette.muted).lineSpacing(4).padding(.horizontal, 4)
                Button { Share.present([Self.shareText]) } label: {
                    Pill(title: "شارك هذا مع من يسأل عن تطبيق آمن", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("خصوصيتك")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AdhanCheckView: View {
    @State private var items: [AdhanCheck.Item] = []
    @State private var sent = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let n = AdhanCheck.problems(items)
                HStack(spacing: 12) {
                    Image(systemName: n == 0 ? "checkmark.seal" : "exclamationmark.triangle")
                        .font(.system(size: 26)).foregroundColor(n == 0 ? Color(hex: 0x2F8F5B) : Palette.goldDeep)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items.isEmpty ? "يفحص…" : n == 0 ? "الأذان سيصلك في وقته بإذن الله"
                             : n == 1 ? "شيء واحد قد يؤخّر الأذان" : ar(n) + " أشياء قد تؤخّر الأذان")
                            .font(AppFont.ui(17, 700)).foregroundColor(Palette.ink)
                        Text("آخر فحص: الآن · يُعاد كل أسبوع تلقائيًا").font(AppFont.ui(12)).foregroundColor(Palette.muted)
                    }
                    Spacer()
                }
                .padding(16).card(Palette.chip, border: Palette.ivoryBorder, radius: 20)

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        if i > 0 { Divider() }
                        HStack(spacing: 12) {
                            CheckMark(ok: it.ok)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(it.title).font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                                if let s = it.sub { Text(s).font(AppFont.ui(12)).foregroundColor(Palette.muted) }
                            }
                            Spacer()
                            if !it.ok, let f = it.fix, let act = it.action {
                                Button(f) { act() }
                                    .font(AppFont.ui(13, 700)).foregroundColor(.white)
                                    .padding(.horizontal, 14).frame(minHeight: 38)
                                    .background(Capsule().fill(Palette.primary))
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 14).card()

                Button {
                    AdhanCheck.test()
                    sent = true
                } label: {
                    Text(sent ? "سيصلك بعد ١٠ ثوانٍ، يمكنك قفل الشاشة" : "جرّب الأذان الآن")
                        .font(AppFont.ui(16, 700)).foregroundColor(Color(hex: 0x0E2C31))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(Palette.gold))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                Text("يصلك إشعار أذان تجريبي بعد ١٠ ثوانٍ بنفس الصوت المختار (" + AdhanSound.name(AdhanSound.current) + ")، لتتأكد أنه يُسمع. "
                     + "تأكد أن مفتاح الصامت في جانب الجوال غير مفعّل.")
                    .font(AppFont.ui(12)).foregroundColor(Palette.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("فحص الأذان")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: phase) { p in if p == .active { Task { await refresh() } } }
    }

    private func refresh() async {
        Store.d.set(Date().timeIntervalSince1970, forKey: "adhan_check_at")
        items = await AdhanCheck.run()
    }
}

struct ImpactView: View {
    @State private var data: [String: Any] = (Store.d.dictionary(forKey: "st_impact_cache") ?? [:])
    @State private var loading = true
    @State private var input = ""
    @State private var ref = Stats.ref
    @State private var message: String?

    private func n(_ k: String) -> Int { (data[k] as? Int) ?? Int("\(data[k] ?? 0)") ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DarkHero {
                    Text("صفحات قرأها من دعوتهم للتطبيق").font(AppFont.ui(13, 700)).foregroundColor(Palette.gold)
                    Text(data.isEmpty && loading ? "…" : num(n("pages"))).font(AppFont.ui(52, 700)).foregroundColor(Palette.goldLight)
                    Text(n("joined") == 0 ? "شارك رابطك، وكل صفحة يقرؤونها تُكتب في أثرك" : "منها " + ar(n("today")) + " اليوم")
                        .font(AppFont.ui(14)).foregroundColor(Palette.onDarkMuted).multilineTextAlignment(.center)
                    Text("«مَن دَلَّ على خيرٍ فله مِثلُ أجرِ فاعِلِه»").font(AppFont.ui(18)).foregroundColor(Palette.onDarkSoft).padding(.top, 10)
                    Text("رواه مسلم").font(AppFont.ui(11)).foregroundColor(Palette.onDarkMuted)
                }
                HStack(spacing: 8) {
                    cell(num(n("joined")), "سجّلوا رمزك")
                    cell(num(n("khatmas")), "ختمات أتمّوها")
                    cell(num(n("days")), "يومًا من الأثر")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("رمز دعوتك").font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
                    Button {
                        UIPasteboard.general.string = Stats.code
                        message = "نُسخ الرمز"
                    } label: {
                        Text(Stats.code).font(AppFont.ui(24, 700)).kerning(4).foregroundColor(Palette.goldDeep)
                            .environment(\.layoutDirection, .leftToRight)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.chip))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("رمز دعوتك \(Stats.code)، اضغط للنسخ")
                    Button { Share.present([Stats.shareText]) } label: {
                        Pill(title: "شارك رابطك", systemImage: "square.and.arrow.up", primary: true, height: 50)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14).card()

                VStack(alignment: .leading, spacing: 8) {
                    if !ref.isEmpty {
                        Text("دعاك صاحب الرمز " + ref).font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
                        Text("جزاك الله خيرًا: قراءتك تُكتب في أثره أيضًا").font(AppFont.ui(12)).foregroundColor(Palette.muted)
                    } else {
                        Text("هل دعاك أحد للتطبيق؟").font(AppFont.ui(14, 700)).foregroundColor(Palette.ink)
                        Text("اكتب رمزه ليُكتب له أثر قراءتك").font(AppFont.ui(12)).foregroundColor(Palette.muted)
                        HStack(spacing: 8) {
                            TextField("K7Q2MA", text: $input)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                .font(AppFont.ui(16, 700))
                                .environment(\.layoutDirection, .leftToRight)
                                .padding(.horizontal, 12).frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.page))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.fieldBorder))
                            Button("حفظ") {
                                if let e = Stats.setRef(input) { message = e; return }
                                ref = Stats.ref
                                message = "تم، جزاك الله خيرًا"
                                Task.detached { await Stats.sync() }
                            }
                            .font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                            .frame(width: 84, height: 46)
                            .background(Capsule().stroke(Palette.fieldBorder))
                        }
                    }
                    if let m = message { Text(m).font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()

                Text("لا نعرف من دعوت ولا أسماءهم: جهاز من دعوته يرسل عدد الصفحات مع رمز الدعوة فقط، دون أي بيانات أخرى.")
                    .font(AppFont.ui(12)).foregroundColor(Palette.muted).lineSpacing(4).padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("أثرك")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await Stats.sync()
            if let d = await Stats.get("action=ref&code=" + Stats.code) {
                data = d
                Store.d.set(d, forKey: "st_impact_cache")
            }
            loading = false
        }
    }

    private func cell(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(AppFont.ui(22, 700)).foregroundColor(Palette.ink)
            Text(l).font(AppFont.ui(12)).foregroundColor(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).card(radius: 14)
        .accessibilityElement(children: .combine)
    }
}

/** الخريطة النقطية من world-map.json (نفس ملف أندرويد) */
private struct WorldDots {
    let w: Int, h: Int
    let land: [[Bool]]
    let centers: [String: [Double]]

    static let shared: WorldDots? = {
        guard let url = Bundle.main.url(forResource: "world-map", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let w = o["w"] as? Int, let h = o["h"] as? Int, let rows = o["rows"] as? [String] else { return nil }
        var land: [[Bool]] = []
        for r in rows {
            let chars = Array(r)
            land.append((0..<w).map { x in
                let nib = Int(String(chars[x / 4]), radix: 16) ?? 0
                return nib & (8 >> (x % 4)) != 0
            })
        }
        return WorldDots(w: w, h: h, land: land, centers: (o["c"] as? [String: [Double]]) ?? [:])
    }()
}

struct WorldMapView: View {
    @State private var data: [String: Any] = (Store.d.dictionary(forKey: "st_world_cache") ?? [:])
    @State private var failed = false
    @State private var mapOn = Stats.mapOn

    private static let bg = Color(hex: 0x0B1F24), cardC = Color(hex: 0x102A30), lineC = Color(hex: 0x1F3A41)

    private var top: [(String, Int)] {
        ((data["top"] as? [[String: Any]]) ?? []).map { (($0["cc"] as? String) ?? "", ($0["pages"] as? Int) ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                let total = (data["total"] as? Int) ?? 0
                let countries = (data["countries"] as? Int) ?? 0
                Text("صفحات قرأها المشاركون اليوم").font(AppFont.ui(13)).foregroundColor(Palette.onDarkMuted)
                Text(data.isEmpty ? (failed ? "—" : "…") : num(total)).font(AppFont.ui(44, 700)).foregroundColor(Palette.goldLight)
                Text(countries > 0 ? "في " + ar(countries) + (countries <= 10 ? " دول" : " دولة")
                     : failed ? "تعذّر الاتصال الآن" : "تضيء الخريطة كلما قرأ المشاركون")
                    .font(AppFont.ui(12)).foregroundColor(Palette.onDarkMuted)

                TimelineView(.animation) { tl in
                    Canvas { ctx, size in draw(ctx, size, t: tl.date.timeIntervalSinceReferenceDate) }
                }
                .frame(height: 190)
                .background(RoundedRectangle(cornerRadius: 18).fill(Self.cardC))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Self.lineC))
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel("خريطة نقاط تضيء حيث يُقرأ القرآن اليوم")

                if !top.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(top.prefix(5).enumerated()), id: \.offset) { i, c in
                            if i > 0 { Rectangle().fill(Self.lineC).frame(height: 1) }
                            HStack {
                                Text(Stats.countryName(c.0)).font(AppFont.ui(14, 700)).foregroundColor(.white)
                                Spacer()
                                Text(ar(c.1) + " صفحة").font(AppFont.ui(14, 700)).foregroundColor(Palette.goldLight)
                            }
                            .padding(.vertical, 11)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Self.cardC))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Self.lineC))
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("أضِف قراءتي للخريطة").font(AppFont.ui(14, 700)).foregroundColor(.white)
                        Text("يُرسل عدد الصفحات واسم الدولة" + (Stats.country.isEmpty ? "" : " (" + Stats.countryName(Stats.country) + ")")
                             + " فقط، بلا موقع دقيق ولا أي معرّف")
                            .font(AppFont.ui(11)).foregroundColor(Palette.onDarkMuted).lineSpacing(3)
                    }
                    Spacer()
                    Toggle("", isOn: $mapOn).labelsHidden().tint(Palette.gold).accessibilityLabel("أضف قراءتي للخريطة")
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
                .onChange(of: mapOn) { v in
                    Stats.mapOn = v
                    if v { Task { await load() } }
                }
                if mapOn {
                    Text(Stats.today == 0 ? "لم تقرأ اليوم بعد: اقرأ ولو صفحة لتضيء بها دولتك" : "قرأت اليوم " + ar(Stats.today) + " صفحة").font(AppFont.ui(12, 700)).foregroundColor(Palette.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(Self.bg.ignoresSafeArea())
        .navigationTitle("القرآن حول العالم")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Self.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        await Stats.sync()
        if let d = await Stats.get("action=world") {
            data = d
            Store.d.set(d, forKey: "st_world_cache")
            failed = false
        } else { failed = true }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, t: Double) {
        guard let m = WorldDots.shared else { return }
        let pad: CGFloat = 10
        let cell = min((size.width - 2 * pad) / CGFloat(m.w), (size.height - 2 * pad) / CGFloat(m.h))
        let ox = (size.width - cell * CGFloat(m.w)) / 2, oy = (size.height - cell * CGFloat(m.h)) / 2
        let r = cell * 0.32
        var land = Path()
        for y in 0..<m.h { for x in 0..<m.w where m.land[y][x] {
            land.addEllipse(in: CGRect(x: ox + (CGFloat(x) + 0.5) * cell - r, y: oy + (CGFloat(y) + 0.5) * cell - r, width: 2 * r, height: 2 * r))
        } }
        ctx.fill(land, with: .color(Color(hex: 0x1F4048)))
        let list = Array(top.prefix(40))
        let maxP = Double(max(1, list.map { $0.1 }.max() ?? 1))
        for (i, c) in list.enumerated() {
            guard let p = m.centers[c.0], p.count == 2 else { continue }
            let cx = ox + CGFloat(p[0]) * cell, cy = oy + CGFloat(p[1]) * cell
            let s = cell * (0.7 + 1.1 * CGFloat(max(0.35, (Double(c.1) / maxP).squareRoot())))
            if i < 3 {
                let ph = CGFloat((t / 2 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1))
                let rr = s * (1 + 2 * ph)
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: 2 * rr, height: 2 * rr)),
                           with: .color(Color(hex: 0xF3D9A4).opacity(Double(0.8 * (1 - ph)))), lineWidth: 1)
            }
            var g = ctx
            g.addFilter(.shadow(color: Palette.gold, radius: 7))
            g.fill(Path(ellipseIn: CGRect(x: cx - s, y: cy - s, width: 2 * s, height: 2 * s)), with: .color(Palette.goldLight))
            let s2 = s * 0.55
            ctx.fill(Path(ellipseIn: CGRect(x: cx - s2, y: cy - s2, width: 2 * s2, height: 2 * s2)), with: .color(Color(hex: 0xF3D9A4)))
        }
    }
}
