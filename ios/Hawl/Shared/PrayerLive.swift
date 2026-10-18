import Foundation
#if canImport(ActivityKit)
import ActivityKit

/**
 * الصلاة القادمة في الجزيرة الديناميكية وشاشة القفل (نشاط حيّ).
 * مشترك بين التطبيق (يبدأ النشاط ويحدّثه) والويدجت (يرسمه).
 * العدّاد يعمل وحده على الجهاز من وقت الصلاة؛ لا يحتاج التطبيق لتحديثه كل ثانية.
 */
@available(iOS 16.1, *)
struct PrayerLiveAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /** اسم الصلاة القادمة: «العصر»، «الجمعة» */
        var name: String
        /** وقت دخولها */
        var at: Date
        /** «٣:١٨ م» */
        var clock: String
        /** المدينة إن وُجدت */
        var city: String
    }
}
#endif
