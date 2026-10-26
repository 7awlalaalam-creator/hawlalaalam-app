import Foundation

/** «أكمل من حيث توقفت» وسلسلة الأيام المتتالية مع القرآن (نقل لـ Reading.java) */
enum Reading {
    private static var d: UserDefaults { Store.d }

    /** هل الرابط صفحة قراءة قرآن؟ */
    static func isQuranPage(_ url: URL) -> Bool {
        let u = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        return u.contains("/سورة-") || u.contains("/surah-") || u.contains("/mushaf-page")
            || u.contains("action=quran") || u.contains("/reader-") || u.contains("/view-")
            || u.contains("/quran.html") || u.contains("mushaf-pages")
    }

    /** عنوان قصير: «المصحف · صفحة ٤» أو اسم السورة بلا ذيل اسم الموقع */
    static func cleanTitle(_ url: URL?, _ title: String?) -> String {
        if let u = url, Khatma.pageOf(u) > 0 { return L("المصحف · صفحة ") + ar(Khatma.pageOf(u)) }
        var t = title ?? ""
        var cut = t.endIndex
        for sep in ["|", " - ", " – ", " — ", " · "] {
            if let r = t.range(of: sep), r.lowerBound > t.startIndex, r.lowerBound < cut { cut = r.lowerBound }
        }
        t = String(t[t.startIndex..<cut]).trimmingCharacters(in: .whitespaces)
        let s = url?.absoluteString ?? ""
        let index = s.contains("action=quran") || s.contains("/quran.html")
        if index || t.isEmpty || t.hasPrefix("http") || t.contains("القرآن الكريم كامل") { t = L("المصحف الشريف") }
        return ar(t)
    }

    static func record(_ url: URL, title: String?) {
        guard isQuranPage(url) else { return }
        d.set(url.absoluteString, forKey: "read_url")
        d.set(cleanTitle(url, title), forKey: "read_title")
        d.set(Date().timeIntervalSince1970, forKey: "read_time")
        markToday()
    }

    static var lastURL: URL? {
        guard let s = d.string(forKey: "read_url") else { return nil }
        return URL(string: s)
    }

    static var lastTitle: String { cleanTitle(lastURL, d.string(forKey: "read_title")) }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static var days: [String] { d.stringArray(forKey: "read_days") ?? [] }

    static func markToday() {
        let today = dayKey(Date())
        var all = days
        if all.contains(today) { return }
        all.append(today)
        d.set(Array(all.suffix(400)), forKey: "read_days")   // تكفي لسلسلة سنة كاملة
    }

    static func readOn(_ date: Date) -> Bool { days.contains(dayKey(date)) }

    /** عدد الأيام المتتالية حتى اليوم (أو حتى أمس إن لم يقرأ اليوم بعد) */
    static var streak: Int {
        let set = Set(days)
        let cal = Calendar.current
        var day = Date()
        if !set.contains(dayKey(day)) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while set.contains(dayKey(day)) && n < 365 {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }
}
