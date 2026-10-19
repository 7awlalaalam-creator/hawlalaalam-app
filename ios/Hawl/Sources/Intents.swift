import AppIntents
import Foundation

/**
 * اختصارات Siri وتطبيق «الاختصارات»: افتح المصحف، الصلاة القادمة، راجع حفظي، ختمتي.
 * تعمل دون إعداد: تظهر تلقائيًا في «الاختصارات» وفي بحث Spotlight، وتُقال لـ Siri باسم التطبيق.
 */
@available(iOS 16.0, *)
struct OpenMushafIntent: AppIntent {
    static var title: LocalizedStringResource = "افتح المصحف"
    static var description = IntentDescription("يفتح المصحف من حيث توقفت")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.openMushaf(page: nil)
        return .result()
    }
}

@available(iOS 16.0, *)
struct NextPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "الصلاة القادمة"
    static var description = IntentDescription("موعد الصلاة القادمة في مدينتك")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard Geo.has else {
            return .result(dialog: "افتح تطبيق حول العالم وحدّد موقعك أولًا لنعرف مواقيت مدينتك.")
        }
        let (idx, at) = Prayer.next()
        let name = Prayer.displayName(idx, on: at)
        let left = Prayer.remaining(at.timeIntervalSinceNow, after: true)
        return .result(dialog: "\(name) الساعة \(formatTime(at))، \(left).")
    }
}

@available(iOS 16.0, *)
struct HifzReviewIntent: AppIntent {
    static var title: LocalizedStringResource = "راجع حفظي"
    static var description = IntentDescription("يفتح مراجعة الآيات المحفوظة")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.openMushaf(page: nil, extra: "hifz=1")
        return .result()
    }
}

@available(iOS 16.0, *)
struct KhatmaIntent: AppIntent {
    static var title: LocalizedStringResource = "ورد اليوم"
    static var description = IntentDescription("ما بقي من ورد ختمتك اليوم")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard Khatma.running else { return .result(dialog: "لم تبدأ ختمة بعد. ابدأها من تطبيق حول العالم.") }
        let left = Khatma.todayRemaining
        if left == 0 { return .result(dialog: "أتممت وردك اليوم، تقبّل الله منك.") }
        return .result(dialog: "بقي من وردك اليوم \(ar(left)) \(left <= 10 ? "صفحات" : "صفحة"). \(Khatma.todayLine)")
    }
}

@available(iOS 16.0, *)
struct HawlShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenMushafIntent(), phrases: [
            "افتح المصحف في \(.applicationName)",
            "اقرأ القرآن في \(.applicationName)",
            "Open Mushaf in \(.applicationName)"
        ])
        AppShortcut(intent: NextPrayerIntent(), phrases: [
            "الصلاة القادمة في \(.applicationName)",
            "متى الصلاة في \(.applicationName)",
            "Next prayer in \(.applicationName)"
        ])
        AppShortcut(intent: HifzReviewIntent(), phrases: [
            "راجع حفظي في \(.applicationName)",
            "Review memorization in \(.applicationName)"
        ])
        AppShortcut(intent: KhatmaIntent(), phrases: [
            "ورد اليوم في \(.applicationName)",
            "Today's wird in \(.applicationName)"
        ])
    }
}
