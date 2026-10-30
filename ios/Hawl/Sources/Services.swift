import SwiftUI
import CoreLocation
import UserNotifications
import AVFoundation
import BackgroundTasks
import WidgetKit

// MARK: - الموقع والبوصلة

/** الموقع (للمواقيت) واتجاه الجوال (للقبلة) */
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    /**
     * لا ننشئ مدير الموقع ولا نسأل عن الإذن أثناء رسم الشاشة الأولى: الاستعلام يتصل بخدمة الموقع في النظام اتصالًا
     * متزامنًا، وإذا تأخرت (بعد تشغيل الجوال أو عند فتح التطبيق في الخلفية) يتجاوز التطبيق مهلة العشر ثوانٍ فيغلقه iOS
     * (0x8BADF00D). يُنشأ عند أول استخدام، أو بعد ظهور الشاشة بقليل، وتصلنا حالة الإذن من الدالة المفوّضة.
     */
    private var made: CLLocationManager?
    private var status: CLAuthorizationStatus = .notDetermined
    private var manager: CLLocationManager {
        if let m = made { return m }
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        made = m
        return m
    }
    @Published var heading: Double?
    /** نفس الاتجاه دون قفز من ٣٥٩ إلى ٠ (لتدوير القرص بسلاسة دون لفّة كاملة) */
    @Published var headingTurn: Double = 0
    @Published var headingAccuracy: Double = -1
    @Published var busy = false
    @Published var denied = false
    @Published var failed = false

    private override init() {
        super.init()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in _ = self?.manager }
    }

    /** من الحالة المحفوظة (تحدّثها الدالة المفوّضة) حتى لا ننتظر خدمة الموقع */
    var authorized: Bool { [.authorizedWhenInUse, .authorizedAlways].contains(status) }

    /** يطلب الإذن عند الحاجة ثم يحدّث الموقع مرة واحدة */
    func requestLocation() {
        busy = true
        failed = false
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: busy = false; denied = true
        default: manager.requestLocation()
        }
    }

    /** تحديث هادئ للمسافرين: مرة كل ٦ ساعات إن كان الأذان مفعّلًا والإذن ممنوحًا (مثل أندرويد) */
    func refreshIfStale() {
        guard authorized, Store.bool("adhan_on", false) else { return }
        if Date().timeIntervalSince1970 - Store.d.double(forKey: "loc_time") > 6 * 3600 {
            Store.d.set(Date().timeIntervalSince1970, forKey: "loc_time")
            manager.requestLocation()
        }
    }

    func startHeading() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 1
            manager.startUpdatingHeading()
        }
    }

    func preciseForQibla(_ on: Bool) {
        manager.desiredAccuracy = on ? kCLLocationAccuracyNearestTenMeters : kCLLocationAccuracyKilometer
    }

    func stopHeading() { made?.stopUpdatingHeading(); heading = nil }

    var headingAvailable: Bool { CLLocationManager.headingAvailable() }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus
        Task { @MainActor in
            self.status = status
            self.denied = [.denied, .restricted].contains(status)
            if self.busy && (status == .authorizedWhenInUse || status == .authorizedAlways) { self.manager.requestLocation() }
            if self.denied { self.busy = false }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.busy = false
            AppState.shared.setLocation(loc)
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.busy { self.failed = true }
            self.busy = false
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        let v = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        let acc = h.headingAccuracy
        Task { @MainActor in
            if let old = self.heading {
                let d = (v - old + 540).truncatingRemainder(dividingBy: 360) - 180
                self.headingTurn += d
            } else {
                self.headingTurn = v
            }
            self.heading = v
            self.headingAccuracy = acc
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}

// MARK: - التذكيرات (مفاتيح الإعدادات، نفس Reminders.java)

enum Reminders {
    static let verse = "verse", wird = "wird", azkarAM = "azkar_am", azkarPM = "azkar_pm", kahf = "kahf"

    static func enabled(_ kind: String) -> Bool { Store.bool(kind + "_on", false) }

    static func hour(_ kind: String) -> Int {
        let def: Int
        switch kind {
        case verse: def = 7
        case azkarAM: def = 6
        case azkarPM: def = 17
        case kahf: def = 9
        default: def = 21
        }
        return Store.int(kind + "_h", def)
    }

    static func minute(_ kind: String) -> Int { Store.int(kind + "_m", kind == azkarAM ? 30 : 0) }

    static func set(_ kind: String, on: Bool, hour h: Int, minute m: Int) {
        Store.d.set(on, forKey: kind + "_on")
        Store.d.set(h, forKey: kind + "_h")
        Store.d.set(m, forKey: kind + "_m")
    }

    /** الصلاة التي يأتي بعدها تذكير الورد، أو -١ لوقت ثابت */
    static var wirdPrayer: Int { Store.int("wird_prayer", -1) }

    static var followUp: Bool { Store.bool("wird_follow", true) }

    /** أذكار الصباح والمساء مرتبطة بالصلاة (افتراضيًا عند توفر الموقع)، والورد إن اختار القارئ صلاة */
    static func byPrayer(_ kind: String) -> Bool {
        if kind == wird { return Prayer.names.indices.contains(wirdPrayer) && Geo.has }
        return (kind == azkarAM || kind == azkarPM) && Store.bool("azkar_by_prayer", true) && Geo.has
    }

    /** «بعد العشاء» أو «٩:٠٠ م» */
    static var wirdLabel: String {
        if byPrayer(wird) { return L("بعد ") + Prayer.names[wirdPrayer] }
        return formatTime(hour: hour(wird), minute: minute(wird))
    }

    /** وصف وقت التذكير لشريحة الإعدادات */
    static func timeLabel(_ kind: String) -> String {
        if kind == wird { return wirdLabel }
        if byPrayer(kind) { return kind == azkarAM ? L("بعد الفجر بربع ساعة") : L("بعد العصر بربع ساعة") }
        let t = formatTime(hour: hour(kind), minute: minute(kind))
        return kind == kahf ? L("الجمعة ") + t : t
    }
}

// MARK: - الإشعارات

/**
 * التنبيهات المحلية بنفس محتوى إشعارات أندرويد (Notifier.java).
 * iOS يسمح بـ ٦٤ تنبيهًا مجدولًا فقط: نجدول الأيام القادمة بالأقرب فالأقرب حتى ٦٠ تنبيهًا،
 * ونعيد الجدولة عند فتح التطبيق وفي التحديث الدوري في الخلفية.
 */
@MainActor
enum Notifications {
    static let adhanCategory = "ADHAN", sunriseCategory = "SUNRISE", fastCategory = "FAST"
    static let wirdCategory = "WIRD", verseCategory = "VERSE", remindCategory = "REMIND"

    static let actAzkar = "AZKAR", actMosques = "MOSQUES", actShare = "SHARE", actSnooze = "SNOOZE", actOpenPage = "OPEN_PAGE"
    static let actCard = "CARD", actText = "TEXT", actTafsir = "TAFSIR", actStart = "START", actMorning = "MORNING", actPrayed = "PRAYED"

    static func registerCategories() {
        func a(_ id: String, _ title: String, fg: Bool = true) -> UNNotificationAction {
            UNNotificationAction(identifier: id, title: title, options: fg ? [.foreground] : [])
        }
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: adhanCategory, actions: [a(actPrayed, L("✓ صلّيت"), fg: false), a(actMosques, L("أقرب مسجد")), a(actAzkar, L("أذكار بعد الصلاة")), a(actShare, L("شارك الأجر"))],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: sunriseCategory, actions: [a(actMorning, L("أذكار الصباح")), a(actShare, L("شارك الأجر"))],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: fastCategory, actions: [a(actShare, L("ذكّر من تحب"))], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: wirdCategory, actions: [a(actOpenPage, L("أكمل القراءة")), a(actSnooze, L("ذكّرني بعد ساعة"), fg: false)],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: verseCategory, actions: [a(actCard, L("شارك كصورة")), a(actText, L("شارك نصًّا")), a(actTafsir, L("التفسير"))],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: remindCategory, actions: [a(actStart, L("ابدأ الآن"))], intentIdentifiers: [], options: []),
        ])
    }

    /** يطلب الإذن (مرة) ويعيد true إن سُمح */
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let s = await center.notificationSettings()
        if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional { return true }
        if s.authorizationStatus == .denied { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func allowed() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    private struct Item { let req: UNNotificationRequest; let at: Date? }

    private static var pendingWork: Task<Void, Never>?

    /** إعادة الجدولة (تُجمع الطلبات المتتالية في طلب واحد) */
    static func reschedule() {
        pendingWork?.cancel()
        pendingWork = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            build()
        }
    }

    private static func build() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let cal = Calendar.current
        let now = Date()
        var timed: [Item] = []
        var repeating: [UNNotificationRequest] = []
        let city = Geo.city

        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let t = Geo.has ? Prayer.times(for: day) : []

            // الأذان والشروق
            if Store.bool("adhan_on", false) && Geo.has {
                for k in Prayer.alerts where t[k] > now {
                    timed.append(Item(req: adhan(k, at: t[k], city: city), at: t[k]))
                }
                if Store.bool("sunrise_on", true) && t[Prayer.sunrise] > now {
                    timed.append(Item(req: sunrise(at: t[Prayer.sunrise]), at: t[Prayer.sunrise]))
                }
            }
            // «وضع المسجد»: تذكير هادئ قبل الإقامة
            if Mosque.on && Geo.has {
                for (req, at) in Mosque.requests(day: day, times: t, now: now) { timed.append(Item(req: req, at: at)) }
            }
            // تذكير الصيام المسنون (عند العشاء)
            if Store.bool("fasting_on", true) && Geo.has && t[Prayer.isha] > now, let fast = Fadl.fastAfter(day) {
                timed.append(Item(req: fasting(fast, at: t[Prayer.isha]), at: t[Prayer.isha]))
            }
            // الإفطار في رمضان (عند المغرب)
            if Store.bool("iftar_on", true) && Geo.has && Ramadan.active(t[Prayer.maghrib]) && t[Prayer.maghrib] > now {
                timed.append(Item(req: iftar(at: t[Prayer.maghrib]), at: t[Prayer.maghrib]))
            }
            // آية اليوم
            if Reminders.enabled(Reminders.verse),
               let at = cal.date(bySettingHour: Reminders.hour(Reminders.verse), minute: Reminders.minute(Reminders.verse), second: 0, of: day),
               at > now {
                timed.append(Item(req: verse(at: at, today: offset == 0), at: at))
            }
            // الورد
            if Reminders.enabled(Reminders.wird) {
                for it in wird(day: day, offset: offset, prayerTimes: t, now: now) { timed.append(it) }
            }
            // أذكار الصباح والمساء المرتبطة بالصلاة
            for kind in [Reminders.azkarAM, Reminders.azkarPM] where Reminders.enabled(kind) && Reminders.byPrayer(kind) {
                let at = t[kind == Reminders.azkarAM ? Prayer.fajr : Prayer.asr].addingTimeInterval(15 * 60)
                if at > now { timed.append(Item(req: remind(kind, trigger: once(at), id: "\(kind)-\(offset)"), at: at)) }
            }
        }

        // تذكيرات بوقت ثابت تتكرر
        for kind in [Reminders.azkarAM, Reminders.azkarPM] where Reminders.enabled(kind) && !Reminders.byPrayer(kind) {
            var c = DateComponents()
            c.hour = Reminders.hour(kind)
            c.minute = Reminders.minute(kind)
            repeating.append(remind(kind, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true), id: kind))
        }
        if Reminders.enabled(Reminders.kahf) {
            var c = DateComponents()
            c.weekday = 6
            c.hour = Reminders.hour(Reminders.kahf)
            c.minute = Reminders.minute(Reminders.kahf)
            repeating.append(remind(Reminders.kahf, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true), id: "kahf"))
        }

        // «ذكّرني بعد ساعة»
        let snooze = Store.d.double(forKey: "wird_snooze_at")
        if snooze > now.timeIntervalSince1970 && Khatma.running && Khatma.todayRemaining > 0 {
            let at = Date(timeIntervalSince1970: snooze)
            timed.append(Item(req: wirdContent(followUp: true, trigger: once(at), id: "wird-snooze"), at: at))
        }

        let budget = max(0, 60 - repeating.count)
        let chosen = timed.sorted { ($0.at ?? now) < ($1.at ?? now) }.prefix(budget)
        for r in repeating { center.add(r) }
        for it in chosen { center.add(it.req) }
        Store.d.set(chosen.last?.at?.timeIntervalSince1970 ?? 0, forKey: "notif_until")
    }

    private static func once(_ at: Date) -> UNCalendarNotificationTrigger {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    private static func content(_ title: String, _ body: String, kind: String?) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        if let k = kind { c.subtitle = k }
        c.sound = .default
        return c
    }

    // MARK: الأذان

    private static func adhan(_ k: Int, at: Date, city: String) -> UNNotificationRequest {
        let name = Prayer.displayName(k, on: at)
        let f = Fadl.of(k, on: at)
        let nx = Prayer.after(k, on: at)
        let nextText = L("التالية: ") + nx.0 + " " + formatTime(nx.1)
        var body: String = L("حان الآن موعد صلاة ") + name + " · " + nextText
        body += "\n\n" + f.0 + "\n— " + f.1
        if !city.isEmpty { body += L("\n\nحسب التوقيت المحلي لـ") + city }
        let c = content(L("صلاة ") + name, body, kind: L("الأذان"))
        c.sound = AdhanSound.notificationSound(for: k)
        c.categoryIdentifier = adhanCategory
        c.threadIdentifier = "adhan"
        // لزر «✓ صلّيت»: رقم الصلاة في متابعة الصلوات (٠ الفجر … ٤ العشاء) ويومها
        let logIndex = Prayer.alerts.firstIndex(of: k) ?? -1
        c.userInfo = ["route": "prayer", "share": "\(f.0)\n— \(f.1)\n\n\(Links.homeString)",
                      "pl_i": logIndex, "pl_d": PrayerLog.day(at)]
        return UNNotificationRequest(identifier: "adhan-\(Int(at.timeIntervalSince1970))-\(k)", content: c, trigger: once(at))
    }

    /** الشروق: انتهاء وقت الفجر، وفضل الجلوس للذكر وصلاة الضحى */
    private static func sunrise(at: Date) -> UNNotificationRequest {
        let f = Fadl.of(Prayer.sunrise, on: at)
        let duha = formatTime(at.addingTimeInterval(15 * 60))
        let nx = Prayer.after(Prayer.sunrise, on: at)
        var body: String = L("أذكار الصباح بانتظارك، ووقت الضحى بعد ارتفاع الشمس\n\n") + f.0 + "\n— " + f.1
        body += L("\n\nيبدأ وقت الضحى بعد ارتفاع الشمس، نحو ") + duha
        body += L("\nالتالية: ") + nx.0 + " " + formatTime(nx.1)
        let c = content(L("الشروق · انتهى وقت الفجر"), body, kind: L("الأذان"))
        c.categoryIdentifier = sunriseCategory
        c.threadIdentifier = "adhan"
        c.userInfo = ["url": Links.azkar.absoluteString, "share": "\(f.0)\n— \(f.1)\n\n\(Links.homeString)"]
        return UNNotificationRequest(identifier: "sunrise-\(Int(at.timeIntervalSince1970))", content: c, trigger: once(at))
    }

    /** ليلة يوم الصيام المسنون (عند العشاء) */
    private static func fasting(_ fast: Fadl.Fast, at: Date) -> UNNotificationRequest {
        let body: String = "غدًا \(fast.title)، ولا تنسَ نية الصيام والسحور فإن فيه بركة.\n\n\(fast.text)\n— \(fast.source)\n\n(حسب تقويم أم القرى)"
        let c = content(L("غدًا ") + fast.title, body, kind: L("الصيام"))
        c.categoryIdentifier = fastCategory
        c.userInfo = ["url": Links.homeString,
                      "share": "غدًا \(fast.title)\n\(fast.text)\n— \(fast.source)\n\n\(Links.homeString)"]
        return UNNotificationRequest(identifier: "fast-\(Int(at.timeIntervalSince1970))", content: c, trigger: once(at))
    }

    /** عند أذان المغرب في رمضان */
    private static func iftar(at: Date) -> UNNotificationRequest {
        let c = content(L("حان وقت الإفطار"),
                        L("«ذَهَبَ الظَّمَأُ، وَابْتَلَّتِ الْعُرُوقُ، وَثَبَتَ الأَجْرُ إِنْ شَاءَ اللَّهُ»\nتقبّل الله صيامكم"), kind: L("رمضان"))
        c.userInfo = ["url": Ramadan.tadabburURL(at).absoluteString]
        return UNNotificationRequest(identifier: "iftar-\(Int(at.timeIntervalSince1970))", content: c, trigger: once(at))
    }

    // MARK: آية اليوم

    private static func verse(at: Date, today: Bool) -> UNNotificationRequest {
        let c = content(L("آية اليوم"), L("آية اليوم بانتظارك، افتح وتدبّر"), kind: L("آية اليوم"))
        c.userInfo = ["route": "today"]
        if today, AppState.verseFresh, let v = AppState.cachedVerse() {
            c.body = v.text + " · " + v.ref
            c.categoryIdentifier = verseCategory
            c.userInfo = ["route": "today", "card": v.cardURL.absoluteString, "tafsir": v.tafsirURL.absoluteString, "share": v.shareText]
            if let att = verseAttachment(v) { c.attachments = [att] }
        }
        return UNNotificationRequest(identifier: "verse-\(Int(at.timeIntervalSince1970))", content: c, trigger: once(at))
    }

    /** بطاقة الآية بخط المجمع على خلفية الهوية، تظهر عند فتح الإشعار */
    private static func verseAttachment(_ v: AppState.DailyVerse) -> UNNotificationAttachment? {
        let renderer = ImageRenderer(content: VerseShareCard(verse: v).environment(\.layoutDirection, .rightToLeft))
        renderer.scale = 2
        guard let img = renderer.uiImage, let data = img.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("verse-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "verse", url: url, options: nil)
        } catch { return nil }
    }

    // MARK: الورد

    private static func wirdTime(day: Date, prayerTimes t: [Date]) -> Date? {
        if Reminders.byPrayer(Reminders.wird), t.count > Reminders.wirdPrayer {
            return t[Reminders.wirdPrayer].addingTimeInterval(20 * 60)
        }
        return Calendar.current.date(bySettingHour: Reminders.hour(Reminders.wird), minute: Reminders.minute(Reminders.wird), second: 0, of: day)
    }

    private static func wird(day: Date, offset: Int, prayerTimes t: [Date], now: Date) -> [Item] {
        guard let at = wirdTime(day: day, prayerTimes: t), at > now else { return [] }
        let khatma = Khatma.running
        if khatma {
            let dayNum = Khatma.today(day)
            if !Khatma.isReadingDay(dayNum) { return [] }                  // يوم راحة
            if offset == 0 && Khatma.todayRemaining == 0 { return [] }      // أتمّ ورده
        }
        var out = [Item(req: wirdContent(followUp: false, trigger: once(at), id: "wird-\(offset)", today: offset == 0), at: at)]
        // تذكير ثانٍ لطيف بعد ٣ ساعات إن لم يكتمل الورد، ولا يتجاوز ١١ مساءً
        if offset == 0 && khatma && Reminders.followUp, Khatma.todayRemaining > 0 {
            let f = at.addingTimeInterval(3 * 3600)
            if let limit = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: day), f <= limit {
                out.append(Item(req: wirdContent(followUp: true, trigger: once(f), id: "wird-follow"), at: f))
            }
        }
        return out
    }

    private static func wirdContent(followUp: Bool, trigger: UNNotificationTrigger, id: String, today: Bool = true) -> UNNotificationRequest {
        let c: UNMutableNotificationContent
        if Khatma.running {
            let left = Khatma.todayRemaining
            let target = max(left, Khatma.dailyTarget)
            let r = Khatma.todayRange
            let open = max(r.0, Khatma.nextPage)
            if today {
                let surah = Khatma.surahName(open)
                let title = followUp ? L("تذكير لطيف بوردك") : L("وردك اليوم") + (surah.isEmpty ? "" : L(": سورة ") + surah)
                let text: String
                if followUp { text = L("بقي ") + pagesText(left) + L(" من وردك، ولو قليلًا قبل النوم") }
                else if left < target { text = L("بقي لك ") + pagesText(left) + L(" من ") + pagesText(target) }
                else { text = "صفحة \(ar(r.0)) إلى \(ar(r.1)) · \(pagesText(target))" }
                c = content(title, "\(text)\n\(Khatma.whereIs(open)) · الختم المتوقع \(Khatma.endDateText)", kind: L("الختمة"))
            } else {
                c = content(L("وردك اليوم"), L("نحو ") + pagesText(Khatma.pace) + L(" · أكمل ختمتك من حيث توقفت"), kind: L("الختمة"))
            }
            c.userInfo = ["page": open]
        } else {
            c = content(L("وردك اليومي"), L("قليلٌ دائم، وأثرٌ في القلب. أكمل من حيث توقفت"), kind: L("الختمة"))
            c.userInfo = ["page": Khatma.lastMushafPage()]
        }
        c.categoryIdentifier = wirdCategory
        c.threadIdentifier = "wird"
        return UNNotificationRequest(identifier: id, content: c, trigger: trigger)
    }

    // MARK: الأذكار والكهف

    private static func remind(_ kind: String, trigger: UNNotificationTrigger, id: String) -> UNNotificationRequest {
        let title: String, text: String, label: String, url: URL
        switch kind {
        case Reminders.azkarAM: title = L("أذكار الصباح"); text = L("حصّن يومك بذكر الله"); label = L("الأذكار"); url = Links.azkar
        case Reminders.azkarPM: title = L("أذكار المساء"); text = L("اختم نهارك بذكر الله"); label = L("الأذكار"); url = Links.azkar
        default: title = L("سورة الكهف"); text = L("يوم الجمعة: نورٌ لك ما بين الجمعتين"); label = L("الجمعة"); url = Links.kahf
        }
        let c = content(title, text, kind: label)
        c.categoryIdentifier = remindCategory
        c.userInfo = ["url": url.absoluteString]
        return UNNotificationRequest(identifier: id, content: c, trigger: trigger)
    }

    /** «جرّب إشعار آية اليوم الآن» */
    static func testVerse() async {
        _ = await AppState.fetchVerse()
        let c = content(L("آية اليوم"), L("آية اليوم بانتظارك، افتح وتدبّر"), kind: L("آية اليوم"))
        c.userInfo = ["route": "today"]
        if let v = AppState.cachedVerse() {
            c.body = v.text + " · " + v.ref
            c.categoryIdentifier = verseCategory
            c.userInfo = ["route": "today", "card": v.cardURL.absoluteString, "tafsir": v.tafsirURL.absoluteString, "share": v.shareText]
            if let att = verseAttachment(v) { c.attachments = [att] }
        }
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "verse-test", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
    }
}

// MARK: - أخبار صاحب التطبيق (نفس Announce.java: ملف app-notice.json في الموقع، دون أي بيانات عن المستخدم)

enum Announce {
    /** فحص عند فتح التطبيق، مرة كل ٣٠ دقيقة على الأكثر */
    static func checkSoon() {
        if Date().timeIntervalSince1970 - Store.d.double(forKey: "notice_checked") < 30 * 60 { return }
        Task { await check() }
    }

    static func check() async {
        Store.d.set(Date().timeIntervalSince1970, forKey: "notice_checked")
        let stamp = Int(Date().timeIntervalSince1970 / 600)
        guard let url = URL(string: Links.notice.absoluteString + "?t=\(stamp)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(WebConfig.userAgentMark, forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: req),
              let o = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] else { return }
        let id = (o["id"] as? String ?? (o["id"].map { "\($0)" } ?? "")).trimmingCharacters(in: .whitespaces)
        let title = (o["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let body = (o["body"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let link = (o["url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let expires = (o["expires"] as? NSNumber)?.doubleValue ?? 0
        if id.isEmpty || (title.isEmpty && body.isEmpty) { return }
        if id == Store.string("notice_seen") { return }
        if expires > 0 && Date().timeIntervalSince1970 > expires { return }
        Store.d.set(id, forKey: "notice_seen")
        let a0 = (o["aid"] as? Int) ?? Int("\(o["aid"] ?? "")") ?? 0
        let aid = a0 > 0 ? a0 : News.articleID(link)
        News.add(id: id, title: title, body: body, url: link, article: aid)      // «أخبار التطبيق»: ٢٤ ساعة
        guard Store.bool("news_on", true) else { return }
        let c = UNMutableNotificationContent()
        c.title = title.isEmpty ? L("حول العالم") : title
        c.body = body
        c.subtitle = L("أخبار حول العالم")
        c.sound = .default
        // الرابط من نطاق الموقع فقط يُفتح داخل التطبيق؛ غير ذلك يفتح «اليوم»
        if aid > 0 { c.userInfo = ["article": aid, "url": link] }
        else if let u = URL(string: link), Links.isOurs(u) { c.userInfo = ["url": link] } else { c.userInfo = ["route": "today"] }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "news-" + id, content: c, trigger: nil))
    }
}

// MARK: - التحديث الدوري في الخلفية

enum Background {
    static let refreshID = "com.hawlalaalam.quran.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            guard let t = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            schedule()
            let work = Task {
                _ = await AppState.fetchVerse()
                await Announce.check()
                await Stats.sync()
                await AdhanCheck.weeklyIfDue()
                await MainActor.run {
                    Notifications.reschedule()
                    WidgetCenter.shared.reloadAllTimelines()
                    LiveActivities.refresh(canStart: false)   // من الخلفية: تحديث فقط، لا بدء
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                t.setTaskCompleted(success: true)
            }
            t.expirationHandler = { work.cancel() }
        }
    }

    /** كل ٣ ساعات تقريبًا (النظام يختار الوقت المناسب) */
    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: refreshID)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        try? BGTaskScheduler.shared.submit(r)
    }
}

// MARK: - مندوب التطبيق: الإشعارات والاختصارات والخلفية

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /** اختصار من أيقونة التطبيق فُتح به التطبيق */
    static var pendingShortcut: String?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // التلاوات تستمر عند قفل الشاشة أو الخروج من التطبيق
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        Background.register()
        Task { @MainActor in Notifications.registerCategories() }
        Push.start(application)
        return true
    }

    // الإشعارات الفورية (Firebase)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Push.setAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard Push.isPush(userInfo) else { completionHandler(.noData); return }
        let aps = userInfo["aps"] as? [String: Any]
        if aps?["alert"] != nil {
            Push.markDelivered(userInfo)                 // النظام يعرضه؛ نسجّله فقط كي لا يتكرر من app-notice.json
            completionHandler(.newData)
        } else {
            Task {
                await Push.showDataOnly(userInfo)
                completionHandler(.newData)
            }
        }
    }

    /** انتهت تحميلات التلاوات والتطبيق في الخلفية */
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        if identifier == AudioDownloads.sessionID { AudioDownloads.shared.backgroundCompletion = completionHandler }
        else { completionHandler() }
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { AppDelegate.pendingShortcut = item.type }
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        if Push.isPush(info) && !Push.markDelivered(info) { completionHandler([]); return }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let info = content.userInfo
        let action = response.actionIdentifier
        let route = info["route"] as? String
        let page = info["page"] as? Int
        let url = Push.isPush(info) ? Push.link(info) : (info["url"] as? String).flatMap(URL.init(string:))
        let aid = Push.isPush(info) ? Push.article(info) : (info["article"] as? Int ?? 0)
        let rawURL = "\(info["url"] ?? "")"
        let share = info["share"] as? String
        let card = (info["card"] as? String).flatMap(URL.init(string:))
        let tafsir = (info["tafsir"] as? String).flatMap(URL.init(string:))
        Task { @MainActor in
            let s = AppState.shared
            switch action {
            case Notifications.actPrayed:
                if let i = info["pl_i"] as? Int, let d = info["pl_d"] as? Int, i >= 0,
                   PrayerLog.mask(d) & (1 << i) == 0 {
                    PrayerLog.toggle(day: d, prayer: i)
                    s.touch()
                }
            case Notifications.actMosques:
                s.show(.mosques)
            case Notifications.actAzkar:
                s.tab = .today
                s.showPrayerAzkar = true
            case Notifications.actShare, Notifications.actText:
                if let t = share { Share.present([t]) }
            case Notifications.actSnooze:
                // «ذكّرني بعد ساعة»: يعود التذكير بعد ساعة
                Store.d.set(Date().timeIntervalSince1970 + 3600, forKey: "wird_snooze_at")
                Notifications.reschedule()
            case Notifications.actCard:
                if let u = card { s.open(u, title: L("آية اليوم")) }
            case Notifications.actTafsir:
                if let u = tafsir { s.open(u, title: L("التفسير")) }
            case Notifications.actMorning:
                s.open(Links.azkar, title: L("الأذكار"))
            default:
                if let p = page { s.openMushaf(page: p) }
                else if aid > 0 { s.show(.article(aid, rawURL)) }        // مقال جديد: يُفتح في شاشة المقالات
                else if let u = url { s.open(u) }
                else if route == "prayer" { s.show(.prayerTimes) }
                else if route == "adhancheck" { s.show(.adhanCheck) }
                else if content.threadIdentifier == "mosque" { s.show(.mosque) }
                else { s.tab = .today }
            }
            completionHandler()
        }
    }
}

/** اختصارات أيقونة التطبيق (الضغط المطوّل) */
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let type = shortcutItem.type
        Task { @MainActor in
            if let u = URL(string: type) { AppState.shared.handleDeepLink(u) }
            completionHandler(true)
        }
    }
}


// MARK: - صوت تنبيه الأذان (نفس Adhan.sound في أندرويد)
// نغمة الجوال، أو «الله أكبر، الله أكبر» بصوت أذان المسجد الحرام، أو الأذان، أو صامت.
// ملفات الصوت في الحزمة: adhan_takbeer.caf و adhan_full.caf (آيفون يشغّل ٣٠ ثانية على الأكثر من صوت الإشعار)؛
// ما دام الملف غير موجود لا يظهر خياره، ويعمل التنبيه بنغمة الجوال.

enum AdhanSound {
    static let standard = "default", takbeer = "takbeer", full = "full", silent = "silent"

    static func file(_ s: String) -> String { "adhan_" + s + ".caf" }

    static func available(_ s: String) -> Bool {
        s == standard || s == silent || Bundle.main.url(forResource: "adhan_" + s, withExtension: "caf") != nil
    }

    static var current: String {
        let saved = Store.string("adhan_sound")
        let s = saved.isEmpty ? (available(takbeer) ? takbeer : standard) : saved
        return available(s) ? s : standard
    }

    static var fajrFull: Bool { Store.bool("adhan_fajr_full", true) }

    static func notificationSound(for prayer: Int) -> UNNotificationSound? {
        var s = current
        if prayer == Prayer.fajr && s == takbeer && fajrFull && available(full) { s = full }
        switch s {
        case silent: return nil
        case takbeer, full: return UNNotificationSound(named: UNNotificationSoundName(file(s)))
        default: return .default
        }
    }

    static func name(_ s: String) -> String {
        switch s {
        case takbeer: return L("التكبير فقط")
        case full: return L("الأذان كاملًا")
        case silent: return L("صامت")
        default: return L("نغمة الجوال")
        }
    }

    static var options: [String] { [takbeer, full, standard, silent].filter(available) }
}
