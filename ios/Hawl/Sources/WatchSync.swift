import Foundation
import WatchConnectivity

/**
 * يرسل إلى تطبيق الساعة ما يحتاجه دون إنترنت: الموقع وطريقة الحساب (لتحسب الساعة المواقيت بنفسها)،
 * وورد الختمة اليوم، وآية اليوم. يُرسل «سياق التطبيق» الأخير فقط، فلا يتراكم شيء إن كانت الساعة بعيدة.
 */
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    func start() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        if s.delegate == nil { s.delegate = self }
        if s.activationState != .activated { s.activate() }
    }

    /** يُستدعى بعد أي تغيير (AppState.changed / touch) وعند تحديث آية اليوم */
    func send() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        var c: [String: Any] = [
            "calc_method": Store.int("calc_method", 0),
            "country": Store.string("country"),
        ]
        if Geo.has {
            c["lat"] = Geo.lat
            c["lng"] = Geo.lng
            c["city"] = Geo.city
        }
        let running = Khatma.running
        c["k_active"] = running
        if running {
            c["k_done"] = Khatma.todayCount
            c["k_target"] = Khatma.dailyTarget
            c["k_line"] = Khatma.todayLine
            c["k_percent"] = Khatma.percent
        }
        if let v = VerseSource.cached() {
            c["v_text"] = v.text
            c["v_ref"] = v.ref
        }
        // نفس البيانات المرسلة سابقًا: لا نرسلها (كل إرسال يجعل الساعة تعيد رسم ودجتاتها)
        let sig = (c.keys.sorted().map { "\($0)=\(c[$0] ?? "")" }).joined(separator: "|")
        guard sig != lastSig else { return }
        lastSig = sig
        try? s.updateApplicationContext(c)
    }
    private var lastSig = ""

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.send() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.send() }
    }
}
