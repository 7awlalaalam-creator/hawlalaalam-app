import Foundation

/**
 * مواقيت الصلاة فلكيًا بطريقة الحساب المعتمدة في الدولة (أم القرى في السعودية…)، والعصر بالمثل الأول.
 * نقل حرفي لـ PrayerCalc.java و Adhan.times في تطبيق أندرويد، فتطابق مواقيته.
 */
enum Prayer {
    static let fajr = 0, sunrise = 1, dhuhr = 2, asr = 3, maghrib = 4, isha = 5
    static let names = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]
    /** الصلوات الخمس (بلا الشروق) */
    static let alerts = [fajr, dhuhr, asr, maghrib, isha]

    // MARK: طرق الحساب (نفس جدول PrayerCalc.METHODS في أندرويد)

    struct Method {
        let name: String
        let fajr: Double, isha: Double
        var ishaMin = 0, ishaMinRamadan = 0
    }

    /** الفهرس 0 محجوز لـ«تلقائي حسب الدولة» */
    static let methods: [Method?] = [
        nil,
        Method(name: "أم القرى (السعودية)", fajr: 18.5, isha: 0, ishaMin: 90, ishaMinRamadan: 120),
        Method(name: "الهيئة المصرية العامة للمساحة", fajr: 19.5, isha: 17.5),
        Method(name: "رابطة العالم الإسلامي", fajr: 18, isha: 17),
        Method(name: "جامعة العلوم الإسلامية بكراتشي", fajr: 18, isha: 18),
        Method(name: "الجمعية الإسلامية لأمريكا الشمالية", fajr: 15, isha: 15),
        Method(name: "دبي (الإمارات)", fajr: 18.2, isha: 18.2),
        Method(name: "الكويت", fajr: 18, isha: 17.5),
        Method(name: "قطر", fajr: 18, isha: 0, ishaMin: 90, ishaMinRamadan: 90),
        Method(name: "الخليج (البحرين وعُمان)", fajr: 19.5, isha: 0, ishaMin: 90, ishaMinRamadan: 90),
        Method(name: "وزارة الأوقاف المغربية", fajr: 19, isha: 17),
        Method(name: "الجزائر", fajr: 18, isha: 17),
        Method(name: "تونس", fajr: 18, isha: 18),
        Method(name: "الأردن", fajr: 18, isha: 18),
        Method(name: "رئاسة الشؤون الدينية التركية", fajr: 18, isha: 17),
        Method(name: "ماليزيا وسنغافورة وإندونيسيا", fajr: 20, isha: 18),
        Method(name: "روسيا", fajr: 16, isha: 15),
    ]

    static func forCountry(_ cc: String?) -> Int {
        switch (cc ?? "").uppercased() {
        case "SA", "YE": return 1
        case "AE": return 6
        case "KW": return 7
        case "QA": return 8
        case "BH", "OM": return 9
        case "EG", "SD", "SS", "LY", "SY", "LB", "IQ", "PS": return 2
        case "JO": return 13
        case "MA": return 10
        case "DZ": return 11
        case "TN": return 12
        case "TR": return 14
        case "PK", "IN", "BD", "AF": return 4
        case "US", "CA": return 5
        case "MY", "SG", "ID", "BN": return 15
        case "RU": return 16
        default: return 3
        }
    }

    // MARK: الحساب (ساعات محلية عشرية)

    static func compute(year: Int, month: Int, day: Int, lat: Double, lng: Double, tz: Double, ramadan: Bool,
                        method m: Method) -> [Double] {
        let jd = julian(year, month, day) - lng / (15.0 * 24.0)
        var fajrT = sunAngleTime(jd, lat, m.fajr, 5 / 24.0, true)
        let sunriseT = sunAngleTime(jd, lat, 0.833, 6 / 24.0, true)
        let dhuhrT = midDay(jd, 12 / 24.0)
        let asrT = asrTime(jd, lat, 1, 13 / 24.0)
        let sunsetT = sunAngleTime(jd, lat, 0.833, 18 / 24.0, false)
        var ishaT = m.ishaMin > 0 ? sunsetT + Double(ramadan ? m.ishaMinRamadan : m.ishaMin) / 60.0
            : sunAngleTime(jd, lat, m.isha, 18 / 24.0, false)
        // خطوط العرض العليا (AngleBased)
        let night = 24 - (sunsetT - sunriseT)
        let fajrLimit = m.fajr / 60.0 * night
        if fajrT.isNaN || sunriseT - fajrT > fajrLimit { fajrT = sunriseT - fajrLimit }
        if m.ishaMin == 0 {
            let ishaLimit = m.isha / 60.0 * night
            if ishaT.isNaN || ishaT - sunsetT > ishaLimit { ishaT = sunsetT + ishaLimit }
        }
        let adj = tz - lng / 15.0
        return [fajrT + adj, sunriseT + adj, dhuhrT + adj, asrT + adj, sunsetT + adj, ishaT + adj]
    }

    private static func julian(_ year: Int, _ month: Int, _ day: Int) -> Double {
        var y = Double(year), m = Double(month)
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(y / 100.0)
        let b = 2 - a + floor(a / 4.0)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + Double(day) + b - 1524.5
    }

    /** [الميل، معادلة الزمن] */
    private static func sunPosition(_ jd: Double) -> (Double, Double) {
        let dd = jd - 2451545.0
        let g = fixAngle(357.529 + 0.98560028 * dd)
        let q = fixAngle(280.459 + 0.98564736 * dd)
        let l = fixAngle(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g))
        let e = 23.439 - 0.00000036 * dd
        let ra = datan2(dcos(e) * dsin(l), dcos(l)) / 15.0
        let eqt = q / 15.0 - fixHour(ra)
        let decl = dasin(dsin(e) * dsin(l))
        return (decl, eqt)
    }

    private static func midDay(_ jd: Double, _ t: Double) -> Double {
        fixHour(12 - sunPosition(jd + t).1)
    }

    private static func sunAngleTime(_ jd: Double, _ lat: Double, _ angle: Double, _ t: Double, _ ccw: Bool) -> Double {
        let decl = sunPosition(jd + t).0
        let noon = midDay(jd, t)
        var x = (-dsin(angle) - dsin(decl) * dsin(lat)) / (dcos(decl) * dcos(lat))
        x = max(-1, min(1, x))
        let tt = dacos(x) / 15.0
        return noon + (ccw ? -tt : tt)
    }

    private static func asrTime(_ jd: Double, _ lat: Double, _ factor: Double, _ t: Double) -> Double {
        let decl = sunPosition(jd + t).0
        let angle = -dacot(factor + dtan(abs(lat - decl)))
        return sunAngleTime(jd, lat, angle, t, false)
    }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
    private static func dsin(_ d: Double) -> Double { sin(rad(d)) }
    private static func dcos(_ d: Double) -> Double { cos(rad(d)) }
    private static func dtan(_ d: Double) -> Double { tan(rad(d)) }
    private static func dasin(_ x: Double) -> Double { deg(asin(x)) }
    private static func dacos(_ x: Double) -> Double { deg(acos(x)) }
    private static func datan2(_ y: Double, _ x: Double) -> Double { deg(atan2(y, x)) }
    private static func dacot(_ x: Double) -> Double { deg(atan(1 / x)) }
    private static func fixAngle(_ a: Double) -> Double { let r = a - 360 * floor(a / 360.0); return r < 0 ? r + 360 : r }
    private static func fixHour(_ a: Double) -> Double { let r = a - 24 * floor(a / 24.0); return r < 0 ? r + 24 : r }

    // MARK: أوقات يوم معيّن

    static func isRamadan(_ date: Date) -> Bool {
        Calendar(identifier: .islamicUmmAlQura).component(.month, from: date) == 9
    }

    /**
     * مواقيت اليوم كتواريخ. نقيس من الظهر لا من منتصف الليل (كما في أندرويد):
     * في يوم تغيير التوقيت الصيفي لا تنزاح المواقيت ساعة.
     */
    static func times(for day: Date, lat: Double, lng: Double) -> [Date] {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        let noon = cal.date(from: comps) ?? day
        let tz = Double(TimeZone.current.secondsFromGMT(for: noon)) / 3600.0
        let h = compute(year: comps.year ?? 2026, month: comps.month ?? 1, day: comps.day ?? 1,
                        lat: lat, lng: lng, tz: tz, ramadan: isRamadan(noon), method: currentMethod())
        return h.map { noon.addingTimeInterval((($0 - 12) * 60).rounded() * 60) }
    }

    /** الطريقة المختارة في الإعدادات، أو المعتمدة في الدولة (من الموقع، وإلا من منطقة التوقيت) */
    static func methodIndex() -> Int {
        let d = UserDefaults.standard
        let choice = d.integer(forKey: "calc_method")
        if choice > 0 && choice < methods.count { return choice }
        return forCountry(country())
    }

    static func country() -> String {
        if let cc = UserDefaults.standard.string(forKey: "country"), cc.count == 2 { return cc }
        return Locale.current.region?.identifier ?? ""
    }

    static func currentMethod() -> Method { methods[methodIndex()] ?? methods[1]! }

    /** الصلاة القادمة: (الفهرس، الوقت) */
    static func next(lat: Double, lng: Double, now: Date = Date()) -> (Int, Date) {
        let t = times(for: now, lat: lat, lng: lng)
        for k in alerts where t[k] > now { return (k, t[k]) }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return (fajr, times(for: tomorrow, lat: lat, lng: lng)[fajr])
    }

    /** المتبقي بوحدته: «٥٢ دقيقة»، «١:٠٥ ساعة»، «ساعتان»؛ after لصيغة «بعد …» */
    static func remaining(_ seconds: TimeInterval, after: Bool) -> String {
        let m = Int((seconds / 60).rounded(.up))
        if m <= 0 { return "الآن" }
        let t: String
        if m < 60 {
            t = m == 1 ? "دقيقة" : m == 2 ? (after ? "دقيقتين" : "دقيقتان") : ar(m) + (m <= 10 ? " دقائق" : " دقيقة")
        } else {
            let h = m / 60, mm = m % 60
            if mm == 0 {
                t = h == 1 ? "ساعة" : h == 2 ? (after ? "ساعتين" : "ساعتان") : ar(h) + (h <= 10 ? " ساعات" : " ساعة")
            } else {
                t = ar(String(format: "%d:%02d", h, mm)) + " ساعة"
            }
        }
        return after ? "بعد " + t : t
    }

    /** «الجمعة» بدل «الظهر» يوم الجمعة */
    static func displayName(_ index: Int, on date: Date) -> String {
        if index == dhuhr && Calendar.current.component(.weekday, from: date) == 6 { return "الجمعة" }
        return names[index]
    }
}
