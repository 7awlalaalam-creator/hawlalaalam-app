import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/**
 * نشاط «الصلاة القادمة» الحيّ: يُبدأ عند فتح التطبيق (آبل لا تسمح ببدئه من الخلفية)،
 * ويُحدَّث إلى الصلاة التالية كلما فُتح التطبيق أو جاء تحديث الخلفية.
 * العدّاد نفسه يرسمه النظام من وقت الصلاة، فلا يستهلك البطارية.
 */
enum LiveActivities {
    static let key = "live_prayer"

    /** مفعّل افتراضيًا؛ ويُطفأ من «التنبيهات» */
    static var enabled: Bool { Store.bool(key, true) }

    /** هل يدعم الجهاز النشاط الحي ومسموح به في إعدادات الجوال؟ */
    static var supported: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) { return ActivityAuthorizationInfo().areActivitiesEnabled }
        #endif
        return false
    }

    /** يبدأ النشاط أو يحدّثه أو ينهيه حسب الإعداد؛ canStart = التطبيق في المقدمة */
    static func refresh(canStart: Bool = true) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        let all = Activity<PrayerLiveAttributes>.activities
        guard enabled, Geo.has, ActivityAuthorizationInfo().areActivitiesEnabled else {
            for a in all { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let (idx, at) = Prayer.next()
        let state = PrayerLiveAttributes.ContentState(
            name: Prayer.displayName(idx, on: at), at: at, clock: formatTime(at), city: Geo.city)
        // يبقى ظاهرًا ربع ساعة بعد دخول الوقت بعبارة «حان وقت الصلاة»، ثم يُعدّ قديمًا
        let content = ActivityContent(state: state, staleDate: at.addingTimeInterval(15 * 60))
        if let current = all.first {
            for extra in all.dropFirst() { Task { await extra.end(nil, dismissalPolicy: .immediate) } }
            if current.content.state != state { Task { await current.update(content) } }
        } else if canStart {
            _ = try? Activity.request(attributes: PrayerLiveAttributes(), content: content, pushType: nil)
        }
        #endif
    }

    /** إنهاء النشاط (عند إيقاف الإعداد) */
    static func endAll() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        for a in Activity<PrayerLiveAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        #endif
    }
}
