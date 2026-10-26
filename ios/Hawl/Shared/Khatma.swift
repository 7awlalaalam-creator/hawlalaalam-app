import Foundation

/**
 * الختمة الذكية — نقل حرفي لـ Khatma.java (الإصدار ٢):
 * - خطة حسب المدة أو حسب الورد اليومي، وتبدأ من الفاتحة أو من حيث توقف القارئ.
 * - أيام راحة اختيارية، وسياسة واضحة عند فوات يوم: توزيع الباقي أو تمديد الموعد.
 * - الورد ينتهي عند نهاية الجزء إن كانت قريبة، ويُعرض باسم السورة والجزء.
 * - تُحتسب الصفحة مقروءة بعد بقاء القارئ عليها مدة كافية (لا بمجرد التصفح).
 * - سجل يومي وسجل للختمات السابقة.
 * الأيام أرقام صحيحة (أيام منذ ١٩٧٠ بالتوقيت المحلي) كما في أندرويد.
 */
enum Khatma {
    static let pages = 604
    /** مدة البقاء على الصفحة لتُحتسب مقروءة (ثوانٍ) */
    static let dwell: TimeInterval = 12

    static let modeDays = "days", modePages = "pages"

    /** يُستدعى بعد أي تغيير (لتحديث الويدجت وتذكير الورد في التطبيق) */
    static var didChange: (() -> Void)?

    private static var d: UserDefaults { Store.d }
    private static func k(_ key: String) -> String { "khatma_" + key }
    private static func getInt(_ key: String, _ def: Int) -> Int { d.object(forKey: k(key)) as? Int ?? def }
    private static func getBool(_ key: String, _ def: Bool) -> Bool { d.object(forKey: k(key)) as? Bool ?? def }
    private static func getString(_ key: String, _ def: String) -> String { d.string(forKey: k(key)) ?? def }
    private static func put(_ key: String, _ v: Any?) { d.set(v, forKey: k(key)) }

    // MARK: الأيام

    static func today(_ now: Date = Date()) -> Int {
        let off = TimeZone.current.secondsFromGMT(for: now)
        return Int(floor((now.timeIntervalSince1970 + Double(off)) / 86_400))
    }

    /** يوم الأسبوع بترقيم Calendar (الأحد = ١) — اليوم صفر (١٩٧٠/١/١) كان خميسًا */
    static func dow(_ day: Int) -> Int { (((day + 4) % 7) + 7) % 7 + 1 }

    /** أيام الراحة: قناع بتّات حسب يوم الأسبوع */
    static var offMask: Int { getInt("off_days", 0) }

    static func isReadingDay(_ day: Int) -> Bool { (offMask & (1 << dow(day))) == 0 }

    static var readingToday: Bool { isReadingDay(today()) }

    /** عدد أيام القراءة بين يومين (شاملة الطرفين) */
    static func readingDays(_ mask: Int, _ from: Int, _ to: Int) -> Int {
        guard to >= from else { return 0 }
        let to = min(to, from + 3650)                       // حماية من تاريخ تالف بعيد جدًا
        var n = 0
        for day in from...to where (mask & (1 << dow(day))) == 0 { n += 1 }
        return n
    }

    /** اليوم الذي تكتمل فيه كمية من الأيام القرائية بدءًا من يوم معيّن */
    static func dayAfterReadingDays(_ mask0: Int, _ from: Int, _ count: Int) -> Int {
        let mask = (mask0 & 0b11111110) == 0b11111110 ? 0 : mask0   // حماية: لا يجوز أن تكون كل الأيام راحة
        var day = from
        var n = 0
        while day < from + 3650 {
            if (mask & (1 << dow(day))) == 0 {
                n += 1
                if n >= max(1, count) { return day }
            }
            day += 1
        }
        return day
    }

    // MARK: الحالة

    static var active: Bool { getBool("active", false) }
    static var label: String { getString("label", "") }
    static var completed: Int { getInt("completed", 0) }
    static var mode: String { getString("mode", modeDays) }
    /** true: الورد اليومي ثابت ويتمدّد الموعد عند فوات يوم */
    static var fixedPace: Bool { mode == modePages || getBool("extend", false) }
    static var startDay: Int { getInt("start", today()) }
    static var endDay: Int { ensureDay(); return getInt("end", today()) }
    static var startPage: Int { max(1, min(pages, getInt("start_page", 1))) }

    /** الورد اليومي المخطط له */
    static var pace: Int {
        let v = getInt("ppd", 0)
        if v > 0 { return v }
        let s = getInt("start", today()), e = getInt("end", today())
        return max(1, Int(ceil(Double(pages) / Double(max(1, e - s + 1)))))
    }

    private static var bits: [Character] {
        let b = getString("pages", "")
        return b.count == pages ? Array(b) : Array(repeating: "0", count: pages)
    }

    private static var zeros: String { String(repeating: "0", count: pages) }

    /** إعدادات خطة جديدة أو معدّلة */
    struct Plan {
        var mode = Khatma.modeDays
        var days = 30           // لوضع المدة
        var ppd = 20            // لوضع الورد اليومي
        var startPage = 1
        var offMask = 0
        var extend = false      // لوضع المدة: عند فوات يوم نمدّد الموعد بدل زيادة الورد
        var label = ""

        /** عدد صفحات الورد اليومي لهذه الخطة */
        func pace(remaining: Int) -> Int {
            if mode == Khatma.modePages { return max(1, ppd) }
            let t = Khatma.today()
            let rd = Khatma.readingDays(offMask, t, t + max(1, days) - 1)
            return max(1, Int(ceil(Double(remaining) / Double(max(1, rd)))))
        }

        /** يوم الختم المتوقع */
        func end(remaining: Int) -> Int {
            let t = Khatma.today()
            if mode == Khatma.modeDays { return t + max(1, days) - 1 }
            return Khatma.dayAfterReadingDays(offMask, t, Int(ceil(Double(remaining) / Double(max(1, ppd)))))
        }
    }

    /** بدء ختمة جديدة */
    static func start(_ plan: Plan) {
        let t = today()
        let p = plan.pace(remaining: pages)
        put("active", true)
        put("pages", zeros)
        put("mode", plan.mode)
        put("ppd", p)
        put("extend", plan.extend)
        put("start_page", max(1, min(pages, plan.startPage)))
        put("off_days", plan.offMask == 0b11111110 ? 0 : plan.offMask)
        put("start", t)
        put("end", plan.end(remaining: pages))
        put("label", plan.label)
        put("base_day", t)
        put("base_read", 0)
        put("day", t)
        put("today_count", 0)
        put("last_read", t - 1)
        put("extended_note", false)
        put("today_from", nextPage)
        if !Store.bool("wird_on", false) { Store.d.set(true, forKey: "wird_on") }
        didChange?()
    }

    /** تعديل الخطة مع الإبقاء على التقدّم */
    static func replan(_ plan: Plan) {
        let r = read
        let remaining = pages - r
        let p = plan.pace(remaining: remaining)
        // ما قُرئ قبل التعديل (ومنه قراءة اليوم) يتبع الخطة القديمة
        put("base_day", today())
        put("base_read", r)
        put("mode", plan.mode)
        put("ppd", p)
        put("extend", plan.extend)
        put("off_days", plan.offMask == 0b11111110 ? 0 : plan.offMask)
        put("end", plan.end(remaining: remaining))
        put("label", plan.label)
        put("day", today())
        put("today_count", 0)
        put("today_from", nextPage)
        put("extended_note", false)
        didChange?()
    }

    static func stop() {
        put("active", false)
        didChange?()
    }

    // MARK: التتبّع

    /** رقم صفحة المصحف من الرابط (mushaf-pages…?page=4 أو mushaf-page-4.html)، أو ٠ */
    static func pageOf(_ url: URL?) -> Int {
        guard let s = url?.absoluteString else { return 0 }
        let patterns = ["mushaf-page-(\\d{1,3})\\.html", "mushaf-pages[^?#]*\\?(?:[^#]*&)?page=(\\d{1,3})"]
        let ns = s as NSString
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
                  let n = Int(ns.substring(with: m.range(at: 1))) else { continue }
            return (1...pages).contains(n) ? n : 0
        }
        return 0
    }

    /** يُستدعى بعد بقاء القارئ على صفحة المصحف مدة dwell */
    static func onPage(_ page: Int) {
        guard active, (1...pages).contains(page) else { return }
        ensureDay()
        var b = bits
        if b[page - 1] == "1" { return }
        b[page - 1] = "1"
        let todayCount = getInt("today_count", 0) + 1
        let str = String(b)
        put("pages", str)
        put("today_count", todayCount)
        put("last_read", today())
        if str.filter({ $0 == "1" }).count >= pages {
            put("completed", completed + 1)
            put("just_done", true)
            put("history", appendHistory(getString("history", ""), "\(getInt("start", today()))-\(today())"))
        }
        logToday(todayCount)
        Reading.markToday()
        didChange?()
    }

    /** بداية يوم جديد: نثبّت نقطة انطلاق ورد اليوم، ونعالج التأخر دون ورد مُرهق */
    static func ensureDay() {
        let t = today()
        if getInt("day", -1) == t { return }
        put("day", t)
        put("today_count", 0)
        put("today_from", nextPage)
        let remaining = pages - read
        let end = getInt("end", t)
        guard remaining > 0, active else { return }
        if fixedPace {
            // الورد ثابت: الموعد يتحرك مع القراءة الفعلية
            put("end", dayAfterReadingDays(offMask, t, Int(ceil(Double(remaining) / Double(pace)))))
        } else if end < t || readingDays(offMask, t, end) == 0 {
            // انتهت المدة ولم تكتمل الختمة: نمدّد بنفس الورد بدل أن يصبح ورد اليوم كل ما بقي
            put("end", dayAfterReadingDays(offMask, t, Int(ceil(Double(remaining) / Double(pace)))))
            put("extended_note", true)
        }
    }

    static var read: Int { bits.filter { $0 == "1" }.count }

    static var percent: Int { Int((Double(read) * 100 / Double(pages)).rounded()) }

    static var done: Bool { read >= pages }

    static var running: Bool { active && !done }

    /** أول صفحة لم تُقرأ ابتداءً من صفحة البداية (ثم من أول المصحف) */
    static var nextPage: Int {
        let b = bits
        let from = startPage - 1
        if let i = b[from...].firstIndex(of: "0") { return i + 1 }
        if let i = b.firstIndex(of: "0") { return i + 1 }
        return pages
    }

    /** أيام القراءة المتبقية حتى الموعد (يوم واحد على الأقل) */
    static var daysLeft: Int {
        let t = today()
        return max(1, readingDays(offMask, t, max(t, getInt("end", t))))
    }

    /** عدد صفحات الورد قبل التقريب لنهاية الجزء */
    private static var rawTarget: Int {
        ensureDay()
        if !readingToday { return 0 }
        let remainingAtDayStart = pages - read + getInt("today_count", 0)
        if remainingAtDayStart <= 0 { return 0 }
        if fixedPace { return min(remainingAtDayStart, pace) }
        return max(1, Int(ceil(Double(remainingAtDayStart) / Double(daysLeft))))
    }

    /** (من، إلى) صفحات ورد اليوم، ينتهي عند نهاية الجزء إن كانت على بُعد صفحتين */
    static var todayRange: (Int, Int) {
        ensureDay()
        let from = max(1, getInt("today_from", nextPage))
        let target = rawTarget
        if target == 0 { return (from, from - 1) }
        var to = min(pages, from + target - 1)
        for js in Quran.juzStart {
            let juzEnd = js - 1
            if juzEnd >= from && abs(juzEnd - to) <= 2 && juzEnd != to { to = juzEnd; break }
        }
        return (from, to)
    }

    /** عدد صفحات ورد اليوم (٠ في يوم الراحة) */
    static var dailyTarget: Int {
        let r = todayRange
        return max(0, r.1 - r.0 + 1)
    }

    static var todayCount: Int { ensureDay(); return getInt("today_count", 0) }

    /** بقي من ورد اليوم */
    static var todayRemaining: Int { max(0, dailyTarget - todayCount) }

    /** فات يوم قراءة أو أكثر دون قراءة؟ */
    static var missedDays: Bool {
        let t = today()
        if !active { return false }
        let last = max(getInt("last_read", t), getInt("start", t) - 1)
        return readingDays(offMask, last + 1, t - 1) > 0
    }

    /** مُدّد الموعد تلقائيًا لأن المدة انتهت؟ (يُعرض مرة) */
    static func consumeExtendedNote() -> Bool {
        let v = getBool("extended_note", false)
        if v { put("extended_note", false) }
        return v
    }

    static func consumeJustDone() -> Bool {
        let v = getBool("just_done", false)
        if v { put("just_done", false) }
        return v
    }

    /** الفرق عن الخطة بالصفحات: موجب = متقدّم، سالب = متأخر */
    static var aheadBy: Int {
        let t = today()
        let base = getInt("base_day", getInt("start", t))
        let baseRead = getInt("base_read", 0)
        let planned = min(pages - baseRead, pace * readingDays(offMask, base, t - 1))
        let readBeforeToday = read - todayCount
        return (readBeforeToday - baseRead) - planned
    }

    // MARK: الأسماء والتواريخ

    static func surahName(_ page: Int) -> String { Quran.surahName(Quran.surahOf(page: page)) }

    /** «سورة آل عمران · الجزء ٤» */
    static func whereIs(_ page: Int) -> String { Quran.whereIs(page: page) }

    /** نص موحّد لورد اليوم: للبطاقة والويدجت والإشعار */
    static var todayLine: String {
        if !readingToday { return L("يوم راحة من الورد · اقرأ إن شئت") }
        if todayRemaining == 0 { return L("أتممت ورد اليوم ✓") }
        let r = todayRange
        return "ورد اليوم: صفحة \(ar(r.0)) إلى \(ar(r.1)) · \(surahName(r.0))"
    }

    /** تاريخ يوم (رقم اليوم) كنص هجري قصير */
    static func dateText(_ day: Int) -> String {
        let utc = Double(day) * 86_400
        let off = Double(TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: utc)))
        return hijriShort(Date(timeIntervalSince1970: utc - off + 12 * 3600))
    }

    /** تاريخ الختم المتوقع */
    static var endDateText: String { dateText(endDay) }

    // MARK: السجلات

    /** سجل الأيام: «يوم:عدد:ورد» لآخر ٦٠ يومًا */
    private static func logToday(_ count: Int) {
        let t = today()
        let goal = dailyTarget
        var parts = getString("log", "").split(separator: ",").map(String.init)
        parts = parts.filter { !$0.hasPrefix("\(t):") }
        parts = Array(parts.suffix(59))
        parts.append("\(t):\(count):\(goal)")
        put("log", parts.joined(separator: ","))
    }

    /** حالة يوم في السجل: ٠ لم يقرأ، ١ قرأ بعض الورد، ٢ أتم الورد */
    static func dayState(_ day: Int) -> Int {
        for part in getString("log", "").split(separator: ",") {
            let f = part.split(separator: ":").map(String.init)
            if f.count == 3, f[0] == String(day), let n = Int(f[1]), let g = Int(f[2]) {
                return n >= max(1, g) ? 2 : (n > 0 ? 1 : 0)
            }
        }
        return 0
    }

    private static func appendHistory(_ h: String, _ entry: String) -> String {
        let all = h.isEmpty ? [entry] : h.split(separator: ",").map(String.init) + [entry]
        return all.suffix(10).joined(separator: ",")
    }

    /** الختمات السابقة: (يوم البدء، يوم الختم)، الأحدث أولًا */
    static var history: [(Int, Int)] {
        getString("history", "").split(separator: ",").reversed().compactMap { e in
            let f = e.split(separator: "-")
            guard f.count == 2, let a = Int(f[0]), let b = Int(f[1]) else { return nil }
            return (a, b)
        }
    }

    /** صفحة المصحف التي توقّف عندها القارئ (لخيار «من حيث توقفت» وتبويب المصحف) */
    static func lastMushafPage() -> Int {
        if active && !done && read > 0 { return nextPage }
        let p = pageOf(Reading.lastURL)
        if p > 0 { return p }
        let lp = Store.int("last_page", 0)
        return lp > 0 ? lp : 1
    }
}
