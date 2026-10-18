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

    /** متوقف افتراضيًا (لا نزعج أحدًا)؛ يفعّله المستخدم من «التنبيهات» */
    static var enabled: Bool { Store.bool(key, false) }

    /** أخفاه المستخدم بالسحب: لا نعيده قبل دخول هذا الوقت */
    private static let dismissedKey = "live_prayer_dismissed_until"

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
        let every = Activity<PrayerLiveAttributes>.activities
        // النظام يُبقي النشاط المنتهي (بعد ٨ ساعات) في القائمة مدةً؛ لا نعدّه
        let all = every.filter { $0.activityState == .active || $0.activityState == .stale }
        for old in every where !all.contains(where: { $0.id == old.id }) {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        guard enabled, Geo.has, ActivityAuthorizationInfo().areActivitiesEnabled else {
            for a in all { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let now = Date()
        let (idx, at) = Prayer.next(now: now)
        let (idx2, at2) = Prayer.next(now: at.addingTimeInterval(60))
        let state = PrayerLiveAttributes.ContentState(
            name: Prayer.displayName(idx, on: at), at: at, clock: formatTime(at), city: Geo.city,
            nextName: Prayer.displayName(idx2, on: at2), nextAt: at2, nextClock: formatTime(at2))
        // عند دخول الوقت يُعاد الرسم فيتحول العدّاد إلى الصلاة التالية
        let content = ActivityContent(state: state, staleDate: at)
        if let current = all.first {
            for extra in all.dropFirst() { Task { await extra.end(nil, dismissalPolicy: .immediate) } }
            if current.content.state != state { Task { await current.update(content) } }
        } else if canStart, Store.d.double(forKey: dismissedKey) < now.timeIntervalSince1970 {
            guard let a = try? Activity.request(attributes: PrayerLiveAttributes(), content: content, pushType: nil) else { return }
            // سحبه المستخدم من شاشة القفل: نحترم ذلك حتى تدخل الصلاة القادمة
            Task {
                for await st in a.activityStateUpdates where st == .dismissed {
                    Store.d.set(at.timeIntervalSince1970, forKey: dismissedKey)
                    break
                }
            }
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
