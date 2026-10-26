import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

// MARK: - الإشعارات الفورية من صاحب التطبيق (نفس Push.java في أندرويد)
//
// يشترك كل جهاز في موضوع واحد «all» في نفس مشروع Firebase، فصفحة الإدارة notify-admin.php
// ترسل رسالة واحدة تصل للآيفون والأندرويد معًا. لا يُرسل التطبيق أي بيانات عن المستخدم.
// الإشعار نفسه يحمل المعرّف id، فلا يتكرر عند من وصله فورًا ثم من ملف app-notice.json.

enum PushConfig {
    // من Firebase ← إعدادات المشروع ← تطبيق iOS (com.hawlalaalam.quran) ← GoogleService-Info.plist
    static let googleAppID = "1:431488654981:ios:f526e8e5d9d8d4cd4013ec"   // GOOGLE_APP_ID
    static let apiKey = "AIzaSyBSzv9tz0UOafSdLu3BT1Pqz2sLQjAwml4"   // مفتاح Firebase (مقيّد بخدمات Firebase فقط، كما في أندرويد)
    static let gcmSenderID = "431488654981"
    static let projectID = "hawlalaalam-730cc"

    static var ready: Bool { !googleAppID.isEmpty && !apiKey.isEmpty }
}

enum Push {
    static let topic = "all"
    private static let delegate = PushDelegate()

    /** يُستدعى عند تشغيل التطبيق؛ لا يفعل شيئًا إن لم تُضبط قيم Firebase بعد */
    static func start(_ app: UIApplication) {
        guard PushConfig.ready else { return }
        if FirebaseApp.app() == nil {
            let o = FirebaseOptions(googleAppID: PushConfig.googleAppID, gcmSenderID: PushConfig.gcmSenderID)
            o.apiKey = PushConfig.apiKey
            o.projectID = PushConfig.projectID
            o.bundleID = Bundle.main.bundleIdentifier ?? "com.hawlalaalam.quran"
            FirebaseApp.configure(options: o)
        }
        Messaging.messaging().delegate = delegate
        app.registerForRemoteNotifications()
    }

    static func setAPNsToken(_ token: Data) {
        guard PushConfig.ready, FirebaseApp.app() != nil else { return }
        Messaging.messaging().apnsToken = token
        sync()
    }

    /** الاشتراك بالموضوع حسب مفتاح «أخبار وتنبيهات حول العالم» في الإعدادات */
    private static var lastSynced: Bool?
    static func sync() {
        guard PushConfig.ready, FirebaseApp.app() != nil, Messaging.messaging().apnsToken != nil else { return }
        // نفس الحالة المرسلة سابقًا في هذا التشغيل: لا اتصال بالشبكة
        let on = Store.bool("news_on", true)
        if lastSynced == on { return }
        lastSynced = on
        if on {
            Messaging.messaging().subscribe(toTopic: topic)
        } else {
            Messaging.messaging().unsubscribe(fromTopic: topic)
        }
    }

    /** هل هذا إشعار فوري من Firebase؟ */
    static func isPush(_ info: [AnyHashable: Any]) -> Bool {
        info["gcm.message_id"] != nil || info["google.c.a.e"] != nil || info["google.c.sender.id"] != nil
    }

    /**
     * يسجّل المعرّف كأنه عُرض (نفس مفتاح Announce)، ويعيد false إن كان قد عُرض من قبل أو انتهت مدته
     * أو أوقف المستخدم الأخبار.
     */
    @discardableResult
    static func markDelivered(_ info: [AnyHashable: Any]) -> Bool {
        let id = "\(info["id"] ?? "")".trimmingCharacters(in: .whitespaces)
        if !Store.bool("news_on", true) { return false }
        if let e = Double("\(info["expires"] ?? "0")"), e > 0, Date().timeIntervalSince1970 > e { return false }
        // نفس الرسالة قد تصل لدالتين (الاستيقاظ في الخلفية ثم العرض)، فنسمح بها مرة أخرى بمعرّف رسالتها
        let msg = "\(info["gcm.message_id"] ?? "")"
        if id.isEmpty { return true }
        if id == Store.string("notice_seen") { return !msg.isEmpty && msg == Store.string("push_last_msg") }
        Store.d.set(id, forKey: "notice_seen")
        Store.d.set(msg, forKey: "push_last_msg")
        // «أخبار التطبيق»: يبقى ٢٤ ساعة
        News.add(id: id, title: "\(info["title"] ?? (aps(info)?["title"] ?? ""))", body: "\(info["body"] ?? (aps(info)?["body"] ?? ""))",
                 url: "\(info["url"] ?? "")", article: article(info))
        return true
    }

    /** نص الإشعار الظاهر (من apns.alert) حين لا يحمله data */
    private static func aps(_ info: [AnyHashable: Any]) -> [String: Any]? {
        (info["aps"] as? [String: Any])?["alert"] as? [String: Any]
    }

    /** رقم المقالة إن كان الإشعار «مقال جديد» */
    static func article(_ info: [AnyHashable: Any]) -> Int {
        if let n = Int("\(info["aid"] ?? "")"), n > 0 { return n }
        return News.articleID("\(info["url"] ?? "")")
    }

    /** الرابط يُفتح داخل التطبيق فقط إن كان من موقعنا */
    static func link(_ info: [AnyHashable: Any]) -> URL? {
        guard let s = info["url"] as? String, let u = URL(string: s.trimmingCharacters(in: .whitespaces)),
              Links.isOurs(u) else { return nil }
        return u
    }

    /**
     * رسالة بيانات فقط (بلا نص ظاهر) وصلت والتطبيق يعمل أو استيقظ في الخلفية:
     * نعرضها نحن كإشعار محلي — مثل PushService.java في أندرويد.
     */
    static func showDataOnly(_ info: [AnyHashable: Any]) async {
        let title = "\(info["title"] ?? "")".trimmingCharacters(in: .whitespaces)
        let body = "\(info["body"] ?? "")".trimmingCharacters(in: .whitespaces)
        if title.isEmpty && body.isEmpty { return }
        guard markDelivered(info) else { return }
        let c = UNMutableNotificationContent()
        c.title = title.isEmpty ? L("حول العالم") : title
        c.body = body
        c.subtitle = L("أخبار حول العالم")
        c.sound = .default
        let aid = article(info)
        if aid > 0 { c.userInfo = ["article": aid, "url": "\(info["url"] ?? "")"] }
        else if let u = link(info) { c.userInfo = ["url": u.absoluteString] } else { c.userInfo = ["route": "today"] }
        let id = "\(info["id"] ?? UUID().uuidString)"
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "news-" + id, content: c, trigger: nil))
    }
}

private final class PushDelegate: NSObject, MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // الاشتراك بالموضوع يكفي؛ لا نحفظ المعرّف في أي مكان
        Push.sync()
    }
}
