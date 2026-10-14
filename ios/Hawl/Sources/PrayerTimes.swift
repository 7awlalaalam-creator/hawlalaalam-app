import Foundation

/**
 * مواقيت الصلاة فلكيًا (طريقة أم القرى: الفجر 18.5°، العشاء بعد المغرب بـ90 دقيقة و120 في رمضان، العصر المثل الأول).
 * نقل حرفي لـ PrayerCalc.java و Adhan.times في تطبيق أندرويد، فتطابق مواقيته.
 */
enum Prayer {
    static let fajr = 0, sunrise = 1, dhuhr = 2, asr = 3, maghrib = 4, isha = 5
    static let names = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]
    /** الصلوات الخمس (بلا الشروق) */
    static let alerts = [fajr, dhuhr, asr, maghrib, isha]

    // MARK: الحساب (ساعات محلية عشرية)

    static func compute(year: Int, month: Int, day: Int, lat: Double, lng: Double, tz: Double, ramadan: Bool) -> [Double] {
        let jd = julian(year, month, day) - lng / (15.0 * 24.0)
        let fajrT = sunAngleTime(jd, lat, 18.5, 5 / 24.0, true)
        let sunriseT = sunAngleTime(jd, lat, 0.833, 6 / 24.0, true)
        let dhuhrT = midDay(jd, 12 / 24.0)
        let asrT = asrTime(jd, lat, 1, 13 / 24.0)
        let sunsetT = sunAngleTime(jd, lat, 0.833, 18 / 24.0, false)
        let adj = tz - lng / 15.0
        var t = [fajrT + adj, sunriseT + adj, dhuhrT + adj, asrT + adj, sunsetT + adj, 0]
        t[isha] = t[maghrib] + (ramadan ? 120.0 : 90.0) / 60.0
        return t
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
                        lat: lat, lng: lng, tz: tz, ramadan: isRamadan(noon))
        return h.map { noon.addingTimeInterval((($0 - 12) * 60).rounded() * 60) }
    }

    /** الصلاة القادمة: (الفهرس، الوقت) */
    static func next(lat: Double, lng: Double, now: Date = Date()) -> (Int, Date) {
        let t = times(for: now, lat: lat, lng: lng)
        for k in alerts where t[k] > now { return (k, t[k]) }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return (fajr, times(for: tomorrow, lat: lat, lng: lng)[fajr])
    }

    /** «الجمعة» بدل «الظهر» يوم الجمعة */
    static func displayName(_ index: Int, on date: Date) -> String {
        if index == dhuhr && Calendar.current.component(.weekday, from: date) == 6 { return "الجمعة" }
        return names[index]
    }
}
