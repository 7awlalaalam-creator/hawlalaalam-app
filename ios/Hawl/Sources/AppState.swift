import SwiftUI
import CoreLocation
import WidgetKit

/** الشاشات التي تُفتح داخل «اليوم» و«الأدوات» (تنقّل بالقيم: يعمل من الإشعارات والويدجت أيضًا) */
enum Screen: Hashable {
    case web(URL, String)
    case khatma
    case settings
    case notifications
    case qibla
    case tasbeeh
    case mood(Int?)
    case downloads
    case prayerTimes
    case index
    case prayerAzkar
    case dedicate
    case player(String)
}

/** حالة التطبيق: التنقّل، وآية اليوم، ومرآة للإعدادات المحفوظة في Store (المشتركة مع الويدجت) */
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Tab: Hashable { case today, mushaf, listen, tools }

    // التنقّل
    @Published var tab: Tab = .today
    @Published var todayPath = NavigationPath()
    @Published var toolsPath = NavigationPath()
    /** طلب فتح صفحة في المصحف (من الفهرس أو «أكمل القراءة» أو الإشعار) */
    @Published var mushafRequest: Int?
    /** فتح «أذكار بعد الصلاة» من إشعار الأذان */
    @Published var showPrayerAzkar = false
    @Published var showWelcome = false
    @Published var showTour = false
    /** صفحة الاستماع: طلب تحميل رابط معيّن */
    @Published var listenRequest: URL?

    /** يزيد مع كل تغيير في الإعدادات أو الختمة فتُعاد رسم الشاشات */
    @Published private(set) var rev = 0

    // آية اليوم
    @Published private(set) var verse: DailyVerse?

    // الإعدادات التي تُربط بعناصر الواجهة مباشرة
    @Published var themeMode: Int { didSet { Store.d.set(themeMode, forKey: "theme_mode"); WidgetCenter.shared.reloadAllTimelines() } }
    @Published var calcMethod: Int { didSet { Store.d.set(calcMethod, forKey: "calc_method"); changed() } }
    @Published var textZoom: Int { didSet { Store.d.set(textZoom, forKey: "text_zoom") } }
    @Published var lastPage: Int { didSet { Store.d.set(lastPage, forKey: "last_page") } }

    typealias DailyVerse = VerseSource.Verse

    private init() {
        let d = Store.d
        Self.migrateIfNeeded()
        themeMode = d.integer(forKey: "theme_mode")
        calcMethod = d.integer(forKey: "calc_method")
        textZoom = d.object(forKey: "text_zoom") as? Int ?? 100
        lastPage = d.integer(forKey: "last_page")
        verse = Self.cachedVerse()
        Khatma.didChange = {
            Task { @MainActor in AppState.shared.changed() }
        }
        if !d.bool(forKey: "welcomed") { showWelcome = true }
        else if d.integer(forKey: "tour_v") < FeaturesView.tourVersion { showTour = true }
    }

    /** النسخة الأولى من تطبيق iOS حفظت إعداداتها في التخزين العادي: ننقلها مرة */
    private static func migrateIfNeeded() {
        let d = Store.d, old = UserDefaults.standard
        guard d !== old, !d.bool(forKey: "migrated_v2") else { return }
        for k in ["lat", "lng", "city", "country", "adhan_on", "verse_on", "verse_h", "kahf_on", "theme_mode",
                  "calc_method", "last_page", "read_days", "v_s", "v_a", "v_text", "v_date"] {
            if let v = old.object(forKey: k), d.object(forKey: k) == nil { d.set(v, forKey: k) }
        }
        if old.bool(forKey: "azkar_on") {
            d.set(true, forKey: "azkar_am_on")
            d.set(true, forKey: "azkar_pm_on")
        }
        d.set(true, forKey: "migrated_v2")
    }

    var colorScheme: ColorScheme? { themeMode == 1 ? .light : (themeMode == 2 ? .dark : nil) }

    var hasLocation: Bool { _ = rev; return Geo.has }
    var city: String { _ = rev; return Geo.city }

    /** بعد أي تغيير: نعيد الجدولة ونحدّث الويدجت والشاشات */
    func changed() {
        rev += 1
        Notifications.reschedule()
        WidgetCenter.shared.reloadAllTimelines()
        Push.sync()                                  // مفتاح الأخبار: الاشتراك أو إلغاؤه في الإشعارات الفورية
        LiveActivities.refresh()                     // الموقع أو طريقة الحساب أو مفتاح النشاط الحي تغيّرت
    }

    // MARK: الإعدادات كمفاتيح

    func flag(_ key: String, _ def: Bool = false) -> Bool { _ = rev; return Store.bool(key, def) }

    func setFlag(_ key: String, _ on: Bool) {
        Store.d.set(on, forKey: key)
        changed()
    }

    func number(_ key: String, _ def: Int) -> Int { _ = rev; return Store.int(key, def) }

    func setNumber(_ key: String, _ v: Int) {
        Store.d.set(v, forKey: key)
        changed()
    }

    /** ربط مفتاح بمفتاح تبديل؛ التفعيل يطلب إذن التنبيهات أولًا إن احتاج */
    func toggle(_ key: String, _ def: Bool = false, needsNotifications: Bool = true,
                denied: (() -> Void)? = nil) -> Binding<Bool> {
        Binding(get: { self.flag(key, def) }, set: { on in
            if !on || !needsNotifications { self.setFlag(key, on); return }
            Task {
                if await Notifications.requestPermission() { self.setFlag(key, true) }
                else { denied?() }
            }
        })
    }

    // MARK: التنقّل

    func openMushaf(page: Int?) {
        mushafRequest = page ?? Khatma.lastMushafPage()
        tab = .mushaf
    }

    /** فتح شاشة داخل «اليوم» (من إشعار أو ويدجت أو اختصار) */
    func show(_ s: Screen) {
        tab = .today
        todayPath = NavigationPath()
        todayPath.append(s)
    }

    /** يفتح أي رابط: صفحة المصحف ← تبويب المصحف، والاستماع ← تبويبه، وصفحات الموقع داخل التطبيق، وغيرها خارجه */
    func open(_ url: URL, title: String = "") {
        if (url.scheme ?? "").lowercased() == "hawlapp" { handleDeepLink(url); return }
        let p = Khatma.pageOf(url)
        if p > 0 { openMushaf(page: p); return }
        if Links.isOurs(url) {
            if url.absoluteString.contains("quran-reciters") { tab = .listen; listenRequest = url; return }
            show(.web(url, title))
            return
        }
        UIApplication.shared.open(url)
    }

    /** hawlapp://… من الويدجت والإشعارات والاختصارات وصفحات الموقع */
    func handleDeepLink(_ url: URL) {
        let host = (url.host ?? "").lowercased()
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ n: String) -> String? { q.first(where: { $0.name == n })?.value }
        switch host {
        case "open":
            if let s = item("u"), let u = URL(string: s) { open(u) }
        case "mushaf":
            openMushaf(page: item("page").flatMap(Int.init))
        case "listen": tab = .listen
        case "tools": tab = .tools
        case "downloads": show(.downloads)
        case "dedicate": show(.dedicate)
        case "index": show(.index)
        case "khatma": show(.khatma)
        case "settings": show(.settings)
        case "notifications": show(.notifications)
        case "qibla": show(.qibla)
        case "tasbeeh": show(.tasbeeh)
        case "mood": show(.mood(item("m").flatMap(Int.init)))
        case "prayer": show(.prayerTimes)
        case "azkar": show(.web(Links.azkar, "الأذكار"))
        case "prayer-azkar": tab = .today; showPrayerAzkar = true
        case "share-verse":
            tab = .today
            if let v = verse { Share.present([v.shareText]) }
        default: tab = .today
        }
    }

    // MARK: آية اليوم (نفس منطق VerseRepo في أندرويد)

    nonisolated static func cachedVerse() -> DailyVerse? { VerseSource.cached() }

    nonisolated static var verseFresh: Bool { VerseSource.fresh }

    func refreshVerse(force: Bool = false) async {
        if !force && Self.verseFresh { return }
        if let v = await Self.fetchVerse() {
            verse = v
            WidgetCenter.shared.reloadAllTimelines()
            Notifications.reschedule()
        }
    }

    /** يجلب آية اليوم من الموقع ويحفظها (يُستدعى من التطبيق ومن التحديث في الخلفية) */
    nonisolated static func fetchVerse() async -> DailyVerse? {
        await VerseSource.fetch(userAgent: WebConfig.userAgentMark)
    }

    // MARK: الموقع

    func setLocation(_ loc: CLLocation) {
        Store.d.set(loc.coordinate.latitude, forKey: "lat")
        Store.d.set(loc.coordinate.longitude, forKey: "lng")
        Store.d.set(Date().timeIntervalSince1970, forKey: "loc_time")
        changed()
        CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "ar")) { marks, _ in
            let name = marks?.first?.locality ?? marks?.first?.administrativeArea ?? ""
            let cc = marks?.first?.isoCountryCode ?? ""
            Task { @MainActor in
                if cc.count == 2 { Store.d.set(cc.uppercased(), forKey: "country") }
                if !name.isEmpty { Store.d.set(name, forKey: "city") }
                AppState.shared.changed()
            }
        }
    }

    // MARK: القراءة

    /** تُستدعى عند كل صفحة مصحف تُعرض (آخر صفحة + السلسلة) */
    func recordMushaf(page: Int) {
        guard (1...Quran.pages).contains(page) else { return }
        if page != lastPage { lastPage = page }
        Reading.record(Links.page(page), title: nil)
        rev += 1
    }

    var shareAppText: String {
        "📖 تطبيق «حول العالم | القرآن الكريم»\n"
            + "قراءة واستماع وتفسير وأكثر من ٣٠ أداة إسلامية، مجانًا وبلا تسجيل.\n\n"
            + Links.homeString
    }
}
