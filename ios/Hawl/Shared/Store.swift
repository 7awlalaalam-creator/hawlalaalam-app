import Foundation

/**
 * التخزين المشترك بين التطبيق والويدجت (App Group).
 * إن لم تتوفر المجموعة (بناء المحاكي دون توقيع) نرجع إلى التخزين العادي فيعمل التطبيق كما هو.
 */
enum Store {
    static let group = "group.com.hawlalaalam.quran"
    static let d: UserDefaults = UserDefaults(suiteName: group) ?? .standard

    static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
    static func string(_ k: String, _ def: String = "") -> String { d.string(forKey: k) ?? def }
}

/** روابط الموقع والتطبيق (نفس App.HOME في أندرويد) */
enum Links {
    static let home = URL(string: "https://7awlalaalam.com/quran/")!
    static let homeString = "https://7awlalaalam.com/quran/"
    static let azkar = site("azkar-morning-evening-ar.html")
    static let prayerTimes = site("prayer-times-ar.html")
    static let reciters = site("quran-reciters-ar.html")
    static let contact = site("contact.html")
    static let privacy = site("privacy-app-section.html")
    static let languages = site("languages.html")
    static let kahf = site("surah-18.html")
    static let duas = site("duas-library-ar.html")
    static let tafsirSources = site("tafsir-sources-ar.html")
    static let notice = site("app-notice.json")

    /** صفحة المصحف في التطبيق دون إنترنت (نفس Khatma.pageUrl في أندرويد) */
    static let offlinePrefix = "https://7awlalaalam.com/__hawl/mushaf-pages-offline.html?page="

    static func site(_ path: String) -> URL { URL(string: homeString + path)! }

    static func page(_ p: Int) -> URL { URL(string: offlinePrefix + String(max(1, min(Quran.pages, p))))! }

    static func ayah(_ s: Int, _ a: Int) -> URL { site("ayah-\(s)-\(a).html") }

    /** «المصحف»: من حيث توقف القارئ */
    static func mushaf() -> URL { page(Khatma.lastMushafPage()) }

    /** رابط داخلي يفتح أي صفحة داخل التطبيق: hawlapp://open?u=… */
    static func deep(_ url: URL) -> URL {
        var c = URLComponents()
        c.scheme = "hawlapp"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "u", value: url.absoluteString)]
        return c.url ?? URL(string: "hawlapp://today")!
    }

    static func isOurs(_ url: URL) -> Bool {
        let h = (url.host ?? "").lowercased()
        let s = (url.scheme ?? "").lowercased()
        return (h == "7awlalaalam.com" || h == "www.7awlalaalam.com") && (s == "https" || s == "http")
    }
}

/** الموقع المحفوظ للمواقيت (مكة افتراضيًا للحساب فقط، كما في أندرويد) */
enum Geo {
    static var has: Bool { Store.d.object(forKey: "lat") != nil && Store.d.object(forKey: "lng") != nil }
    static var lat: Double { Store.d.object(forKey: "lat") as? Double ?? 21.4225 }
    static var lng: Double { Store.d.object(forKey: "lng") as? Double ?? 39.8262 }
    static var city: String { Store.string("city") }
}
