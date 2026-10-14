import SwiftUI
import CoreLocation
import UserNotifications
import AVFoundation

/** الموقع (للمواقيت) واتجاه الجوال (للقبلة) */
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    @Published var heading: Double?
    @Published var busy = false
    @Published var denied = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        denied = [.denied, .restricted].contains(manager.authorizationStatus)
    }

    /** يطلب الإذن عند الحاجة ثم يحدّث الموقع مرة واحدة */
    func requestLocation() {
        busy = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: busy = false; denied = true
        default: manager.requestLocation()
        }
    }

    func startHeading() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stopHeading() { manager.stopUpdatingHeading() }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus
        Task { @MainActor in
            self.denied = [.denied, .restricted].contains(status)
            if self.busy && (status == .authorizedWhenInUse || status == .authorizedAlways) { self.manager.requestLocation() }
            if self.denied { self.busy = false }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.busy = false
            AppState.shared.setLocation(loc)
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.busy = false }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        let v = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        Task { @MainActor in self.heading = v }
    }
}

/**
 * التنبيهات المحلية. iOS يسمح بـ ٦٤ تنبيهًا مجدولًا فقط، فنجدول أذان ٧ أيام (٣٥)
 * والتذكيرات اليومية المتكررة، ونعيد الجدولة كلما فُتح التطبيق.
 */
@MainActor
enum Notifications {
    static let adhanCategory = "ADHAN"
    static let azkarAction = "AZKAR"

    static func registerCategories() {
        let azkar = UNNotificationAction(identifier: azkarAction, title: "أذكار بعد الصلاة", options: [.foreground])
        let cat = UNNotificationCategory(identifier: adhanCategory, actions: [azkar], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    /** يطلب الإذن (مرة) ويعيد true إن سُمح */
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule() {
        let s = AppState.shared
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        var requests: [UNNotificationRequest] = []

        if s.adhanOn, let lat = s.lat, let lng = s.lng {
            let cal = Calendar.current
            let now = Date()
            for offset in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
                let t = Prayer.times(for: day, lat: lat, lng: lng)
                for (i, k) in Prayer.alerts.enumerated() where t[k] > now {
                    let name = Prayer.displayName(k, on: t[k])
                    let c = UNMutableNotificationContent()
                    c.title = "صلاة " + name
                    var body = "حان الآن موعد صلاة " + name
                    if i + 1 < Prayer.alerts.count {
                        let nk = Prayer.alerts[i + 1]
                        body += " · التالية: " + Prayer.displayName(nk, on: t[nk]) + " " + formatTime(t[nk])
                    }
                    if !s.city.isEmpty { body += "\nحسب التوقيت المحلي لـ" + s.city }
                    c.body = body
                    c.subtitle = "الأذان"
                    c.sound = .default
                    c.categoryIdentifier = adhanCategory
                    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: t[k])
                    requests.append(UNNotificationRequest(identifier: "adhan-\(offset)-\(k)", content: c,
                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                }
            }
        }
        if s.verseOn {
            requests.append(daily(id: "verse", title: "آية اليوم", body: "آية اليوم بانتظارك، افتح وتدبّر",
                                  hour: s.verseHour, minute: 0, route: "today"))
        }
        if s.azkarOn {
            requests.append(daily(id: "azkar-am", title: "أذكار الصباح", body: "حصّن يومك بذكر الله", hour: 6, minute: 30, route: "azkar"))
            requests.append(daily(id: "azkar-pm", title: "أذكار المساء", body: "اختم نهارك بذكر الله", hour: 17, minute: 0, route: "azkar"))
        }
        if s.kahfOn {
            let c = UNMutableNotificationContent()
            c.title = "سورة الكهف"
            c.body = "يوم الجمعة: نورٌ لك ما بين الجمعتين"
            c.sound = .default
            c.userInfo = ["page": Quran.surahStart[17]]
            var comps = DateComponents()
            comps.weekday = 6
            comps.hour = 9
            requests.append(UNNotificationRequest(identifier: "kahf", content: c,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        }
        for r in requests { center.add(r) }
    }

    private static func daily(id: String, title: String, body: String, hour: Int, minute: Int, route: String) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.userInfo = ["route": route]
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return UNNotificationRequest(identifier: id, content: c,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
    }
}

/** يستقبل الضغط على الإشعار ويعرضه والتطبيق مفتوح */
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // التلاوات تستمر عند قفل الشاشة أو الخروج من التطبيق
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        Task { @MainActor in Notifications.registerCategories() }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let isAdhan = response.notification.request.content.categoryIdentifier == Notifications.adhanCategory
        let route = info["route"] as? String
        let page = info["page"] as? Int
        Task { @MainActor in
            let s = AppState.shared
            if action == Notifications.azkarAction || (isAdhan && action == UNNotificationDefaultActionIdentifier) {
                s.tab = .today
                s.showPrayerAzkar = true
            } else if let p = page {
                s.openMushaf(page: p)
            } else if route == "azkar" {
                s.tab = .tools
            } else {
                s.tab = .today
            }
            completionHandler()
        }
    }
}
