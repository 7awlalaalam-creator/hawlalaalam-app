import SwiftUI
import CoreLocation

/** حالة التطبيق وإعداداته المحفوظة على الجهاز (UserDefaults) */
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    static let home = URL(string: "https://7awlalaalam.com/quran/")!

    enum Tab: Hashable { case today, mushaf, listen, tools }

    private let d = UserDefaults.standard

    // التنقل
    @Published var tab: Tab = .today
    /** طلب فتح صفحة في المصحف (من الفهرس أو «أكمل القراءة») */
    @Published var mushafRequest: Int?
    /** فتح «أذكار بعد الصلاة» من إشعار الأذان */
    @Published var showPrayerAzkar = false

    // القراءة
    @Published var lastPage: Int { didSet { d.set(lastPage, forKey: "last_page") } }
    @Published private(set) var readDays: Set<String>

    // الموقع
    @Published var lat: Double? { didSet { d.set(lat, forKey: "lat") } }
    @Published var lng: Double? { didSet { d.set(lng, forKey: "lng") } }
    @Published var city: String { didSet { d.set(city, forKey: "city") } }

    // التنبيهات
    @Published var adhanOn: Bool { didSet { d.set(adhanOn, forKey: "adhan_on"); Notifications.reschedule() } }
    @Published var verseOn: Bool { didSet { d.set(verseOn, forKey: "verse_on"); Notifications.reschedule() } }
    @Published var verseHour: Int { didSet { d.set(verseHour, forKey: "verse_h"); Notifications.reschedule() } }
    @Published var azkarOn: Bool { didSet { d.set(azkarOn, forKey: "azkar_on"); Notifications.reschedule() } }
    @Published var kahfOn: Bool { didSet { d.set(kahfOn, forKey: "kahf_on"); Notifications.reschedule() } }

    /** المظهر: ٠ تلقائي، ١ نهاري، ٢ ليلي */
    @Published var themeMode: Int { didSet { d.set(themeMode, forKey: "theme_mode") } }

    // آية اليوم
    @Published private(set) var verse: DailyVerse?

    struct DailyVerse: Equatable {
        let surah: Int, ayah: Int, text: String
        var ref: String { "سورة " + Quran.surahName(surah) + " · الآية " + ar(ayah) }
        var tafsirURL: URL { URL(string: "https://7awlalaalam.com/quran/ayah-\(surah)-\(ayah).html")! }
        var cardURL: URL { URL(string: "https://7awlalaalam.com/quran/verse-story-card.html?surah=\(surah)&from=\(ayah)&to=\(ayah)")! }
    }

    private init() {
        let d = UserDefaults.standard              // لا نقرأ self.d قبل اكتمال التهيئة
        lastPage = d.integer(forKey: "last_page")
        readDays = Set(d.stringArray(forKey: "read_days") ?? [])
        lat = d.object(forKey: "lat") as? Double
        lng = d.object(forKey: "lng") as? Double
        city = d.string(forKey: "city") ?? ""
        adhanOn = d.bool(forKey: "adhan_on")
        verseOn = d.object(forKey: "verse_on") as? Bool ?? false
        verseHour = d.object(forKey: "verse_h") as? Int ?? 7
        azkarOn = d.bool(forKey: "azkar_on")
        kahfOn = d.bool(forKey: "kahf_on")
        themeMode = d.integer(forKey: "theme_mode")
        if let s = d.object(forKey: "v_s") as? Int, let a = d.object(forKey: "v_a") as? Int,
           let t = d.string(forKey: "v_text"), !t.isEmpty {
            verse = DailyVerse(surah: s, ayah: a, text: t)
        }
    }

    var hasLocation: Bool { lat != nil && lng != nil }

    var colorScheme: ColorScheme? { themeMode == 1 ? .light : (themeMode == 2 ? .dark : nil) }

    // MARK: القراءة والسلسلة

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func recordRead(page: Int) {
        guard page >= 1 && page <= Quran.pages else { return }
        if page != lastPage { lastPage = page }
        let key = Self.dayKey(Date())
        if !readDays.contains(key) {
            readDays.insert(key)
            // نحتفظ بآخر ٤٠٠ يوم فقط
            let kept = readDays.sorted().suffix(400)
            readDays = Set(kept)
            d.set(Array(kept), forKey: "read_days")
        }
    }

    func readOn(_ date: Date) -> Bool { readDays.contains(Self.dayKey(date)) }

    /** الأيام المتتالية حتى اليوم (أو أمس إن لم يقرأ اليوم بعد) */
    var streak: Int {
        let cal = Calendar.current
        var day = Date()
        if !readOn(day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while readOn(day) && n < 400 {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }

    func openMushaf(page: Int?) {
        mushafRequest = page ?? (lastPage > 0 ? lastPage : 1)
        tab = .mushaf
    }

    // MARK: آية اليوم (نفس منطق VerseRepo في أندرويد)

    func refreshVerse() async {
        let today = Self.dayKey(Date())
        if d.string(forKey: "v_date") == today, verse != nil { return }
        var s = 0, a = 0, fromSite = false
        let lastTry = d.double(forKey: "v_try")
        if Date().timeIntervalSince1970 - lastTry > 3600 {
            if let html = await Self.fetchHome() {
                if let r = Self.verseRef(in: html), Quran.valid(r.0, r.1) { s = r.0; a = r.1; fromSite = true }
            }
            if !fromSite { d.set(Date().timeIntervalSince1970, forKey: "v_try") }
        }
        if !fromSite {
            // دون اتصال: آية بحسب التاريخ
            let r = Quran.fromIndex(Int(Date().timeIntervalSince1970 / 86400))
            s = r.0
            a = r.1
        }
        let (vs, va) = (s, a)
        let text: String? = await Task.detached { Quran.verse(vs, va) }.value
        guard let t = text, !t.isEmpty else { return }
        verse = DailyVerse(surah: s, ayah: a, text: t)
        d.set(fromSite ? today : "", forKey: "v_date")
        d.set(s, forKey: "v_s")
        d.set(a, forKey: "v_a")
        d.set(t, forKey: "v_text")
    }

    private static func fetchHome() async -> String? {
        var req = URLRequest(url: home, timeoutInterval: 12)
        req.setValue("HawlalaalamApp iOS", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: req) else { return nil }
        return String(data: result.0, encoding: .utf8)
    }

    /** أول رابط ayah-س-آ.html بعد «آية اليوم» في الصفحة الرئيسية */
    static func verseRef(in html: String) -> (Int, Int)? {
        guard let re = try? NSRegularExpression(pattern: "ayah-(\\d{1,3})-(\\d{1,3})\\.html") else { return nil }
        let ns = html as NSString
        let start = ns.range(of: "آية اليوم").location
        let from = start == NSNotFound ? 0 : start
        let m = re.firstMatch(in: html, range: NSRange(location: from, length: ns.length - from))
            ?? re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length))
        guard let match = m,
              let s = Int(ns.substring(with: match.range(at: 1))),
              let a = Int(ns.substring(with: match.range(at: 2))) else { return nil }
        return (s, a)
    }

    // MARK: الموقع

    func setLocation(_ loc: CLLocation) {
        lat = loc.coordinate.latitude
        lng = loc.coordinate.longitude
        CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "ar")) { [weak self] marks, _ in
            let name = marks?.first?.locality ?? marks?.first?.administrativeArea ?? ""
            Task { @MainActor in
                if !name.isEmpty { self?.city = name }
                Notifications.reschedule()
            }
        }
        Notifications.reschedule()
    }

    static let shareText = "تطبيق «حول العالم | القرآن الكريم»: مصحف المدينة بخط المجمع، والتفسير، والختمة، والأذان.\n" + home.absoluteString
}
