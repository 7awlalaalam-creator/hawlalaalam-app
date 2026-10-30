import Foundation
import MetricKit

/**
 * تقارير الأعطال (MetricKit): يرسلها النظام للتطبيق في اليوم التالي للعطل، فنحفظ آخرها على الجهاز فقط.
 * لا يُرسل شيء تلقائيًا؛ يظهر في الإعدادات زر «أرسل تقرير العطل» ليرسله المستخدم بنفسه إن شاء.
 */
final class CrashReports: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReports()
    static let changed = Notification.Name("crash_reports_changed")

    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("crash", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func start() {
        if #available(iOS 14.0, *) { MXMetricManager.shared.add(self) }
    }

    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            let crashes = p.crashDiagnostics ?? []
            let hangs = p.hangDiagnostics ?? []
            guard !crashes.isEmpty || !hangs.isEmpty else { continue }
            let name = "diag-\(Int(p.timeStampEnd.timeIntervalSince1970)).json"
            try? p.jsonRepresentation().write(to: Self.dir.appendingPathComponent(name))
        }
        // نبقي آخر ٣ تقارير فقط
        let files = Self.files()
        for f in files.dropFirst(3) { try? FileManager.default.removeItem(at: f) }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    static func files() -> [URL] {
        let fs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return fs.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static var latest: URL? { files().first }

    static func clear() { for f in files() { try? FileManager.default.removeItem(at: f) } }
}
