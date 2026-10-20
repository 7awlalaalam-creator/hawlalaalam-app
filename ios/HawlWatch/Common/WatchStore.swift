import SwiftUI

/**
 * تخزين الساعة: نفس أسماء مفاتيح الآيفون (lat، lng، city، country، calc_method) حتى يعمل
 * حساب المواقيت المشترك (PrayerTimes.swift) كما هو. المجموعة نفسها تجمع تطبيق الساعة وتعقيداتها.
 */
enum Store {
    static let group = "group.com.hawlalaalam.quran"
    static let d: UserDefaults = UserDefaults(suiteName: group) ?? .standard

    static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
    static func string(_ k: String, _ def: String = "") -> String { d.string(forKey: k) ?? def }
}

/** الموقع الذي أرسله الآيفون (مكة افتراضيًا للحساب فقط) */
enum Geo {
    static var has: Bool { Store.d.object(forKey: "lat") != nil && Store.d.object(forKey: "lng") != nil }
    static var lat: Double { Store.d.object(forKey: "lat") as? Double ?? 21.4225 }
    static var lng: Double { Store.d.object(forKey: "lng") as? Double ?? 39.8262 }
    static var city: String { Store.string("city") }
}

/** ألوان التطبيق على الساعة (الخلفية سوداء دائمًا في watchOS) */
enum WColor {
    static let gold = Color(red: 0xC9 / 255, green: 0xA8 / 255, blue: 0x76 / 255)
    static let goldSoft = Color(red: 0xE9 / 255, green: 0xD9 / 255, blue: 0xB8 / 255)
    static let petrol = Color(red: 0x16 / 255, green: 0x35 / 255, blue: 0x3D / 255)
    static let card = Color(red: 0x12 / 255, green: 0x2B / 255, blue: 0x31 / 255)
    static let muted = Color(red: 0xA9 / 255, green: 0xBA / 255, blue: 0xBF / 255)
}

/** الصلوات القادمة من الآن: [(الفهرس، الوقت)] لليوم وغدًا — للشاشة والتعقيدات */
enum WatchPrayer {
    static func upcoming(from now: Date = Date(), count: Int = 6) -> [(Int, Date)] {
        var out: [(Int, Date)] = []
        var day = now
        for _ in 0..<3 {
            let t = Prayer.times(for: day)
            for k in Prayer.alerts where t[k] > now { out.append((k, t[k])) }
            if out.count >= count { break }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return Array(out.prefix(count))
    }
}
