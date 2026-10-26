import Foundation
import SwiftUI

/**
 لغة التطبيق: العربية (الأصل) أو الإنجليزية — نفس L.java في أندرويد.
 النصوص مكتوبة بالعربية وتمر عبر L(): في الإنجليزية تُستبدل من en.json، وما لا ترجمة له يبقى عربيًا.
 التفضيل app_lang في مجموعة التطبيق (يقرؤه الويدجت أيضًا). أول تشغيل لمستخدم جديد يتبع لغة الجوال.
 */
enum Lang {
    static let ar = "ar", english = "en"
    private static let defaults = UserDefaults(suiteName: "group.com.hawlalaalam.quran") ?? .standard

    /** تُقرأ مرة لكل تشغيل: تغيير اللغة يتطلب إعادة فتح التطبيق */
    static let code: String = {
        if let s = defaults.string(forKey: "app_lang") { return s }
        let existing = defaults.bool(forKey: "welcomed")
        let sys = Locale.preferredLanguages.first ?? "ar"
        let s = existing || sys.hasPrefix("ar") ? ar : english
        defaults.set(s, forKey: "app_lang")
        return s
    }()

    static var en: Bool { code == english }

    /** اللغة المحفوظة للتشغيل القادم (قد تختلف عن code حتى يُعاد فتح التطبيق) */
    static var saved: String { defaults.string(forKey: "app_lang") ?? code }

    static func set(_ s: String) { defaults.set(s, forKey: "app_lang") }

    static var dir: LayoutDirection { en ? .leftToRight : .rightToLeft }
    static var locale: Locale { Locale(identifier: en ? "en" : "ar") }

    static let dict: [String: String] = {
        guard en, let url = Bundle.main.url(forResource: "en", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return o
    }()
}

/** ترجمة نص عربي إلى لغة التطبيق */
func L(_ s: String) -> String {
    guard Lang.en else { return s }
    return Lang.dict[s] ?? s
}
