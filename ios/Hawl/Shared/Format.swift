import Foundation

/** ٦٢ ← 62 */
func ar(_ n: Int) -> String { ar(String(n)) }

func ar(_ s: String) -> String {
    if Lang.en { return s }                     // الإنجليزية: أرقام لاتينية
    let digits: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
    return String(s.map { ch -> Character in
        if ch.isASCII, let v = ch.wholeNumberValue { return digits[v] }
        return ch
    })
}

/** «٧:٠٥ م» (نفس App.formatTime + Adhan.arabic في أندرويد) */
func formatTime(hour h: Int, minute m: Int) -> String {
    let h12 = h % 12 == 0 ? 12 : h % 12
    let suffix = Lang.en ? (h < 12 ? "AM" : "PM") : (h < 12 ? L("ص") : L("م"))
    return ar(String(format: "%d:%02d %@", h12, m, suffix))
}

/** «٣:٣٠ م» */
func formatTime(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return formatTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
}

/** «٣:٣٠» بلا ص/م (خلايا المواقيت) */
func formatClockShort(_ date: Date) -> String {
    formatTime(date).replacingOccurrences(of: " ص", with: "").replacingOccurrences(of: " م", with: "")
        .replacingOccurrences(of: " AM", with: "").replacingOccurrences(of: " PM", with: "")
}

private let hijriFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .islamicUmmAlQura)
    f.locale = Lang.locale
    f.dateFormat = "EEEE d MMMM"
    return f
}()

private let hijriShortFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .islamicUmmAlQura)
    f.locale = Lang.locale
    f.dateFormat = "d MMMM"
    return f
}()

/** «الجمعة ٧ جمادى الأولى» بتقويم أم القرى */
func hijriToday(_ date: Date = Date()) -> String { ar(hijriFormatter.string(from: date)) }

/** «٧ جمادى الأولى» */
func hijriShort(_ date: Date) -> String { ar(hijriShortFormatter.string(from: date)) }

/** «صفحة واحدة»، «صفحتان»، «٣ صفحات»، «١٥ صفحة» */
func pagesText(_ n: Int) -> String {
    if Lang.en { return n == 1 ? "1 page" : "\(n) pages" }
    if n == 1 { return L("صفحة واحدة") }
    if n == 2 { return L("صفحتان") }
    return ar(n) + (n >= 3 && n <= 10 ? L(" صفحات") : L(" صفحة"))
}

enum Hijri {
    static let calendar = Calendar(identifier: .islamicUmmAlQura)

    /** (الشهر ١..١٢، اليوم) */
    static func parts(_ date: Date) -> (month: Int, day: Int) {
        let c = calendar.dateComponents([.month, .day], from: date)
        return (c.month ?? 0, c.day ?? 0)
    }
}
