import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

// MARK: - النسخة الاحتياطية (ملف موحّد مع أندرويد) ومزامنة iCloud

enum Backup {
    /** مفاتيح تقنية خاصة بهذا الجهاز لا تُنقل */
    private static let skip: Set<String> = [
        "fcm_token", "push_token", "push_topic", "notice_checked", "notice_seen", "notif_until", "v_try", "loc_time",
        "bridge_diag", "open_route", "migrated_v2", "audio_downloads", "internal_device", "icloud_on", "sync_at",
        "sync_device", "web_restore_pending", "update_checked", "wird_snooze_at", "welcomed",
        "sync_hash", "sync_dirty_at",
    ]
    /** قيم تتغيّر وحدها على كل جهاز (آية اليوم، الموقع، الجولة…) فلا تُعدّ تغييرًا في بيانات القارئ عند المزامنة */
    private static let volatile: Set<String> = ["lat", "lng", "city", "country", "read_time", "tour_v", "push_last_msg",
                                                 "hifz_total", "hifz_next", "hifz_held", "hifz_pct"]
    private static let volatilePrefixes = ["v_"]
    private static let skipPrefixes = ["live_", "push_", "dismiss", "NS", "Apple", "com.apple", "WebKit", "WebDatabase", "azkar_progress_"]

    private static func keep(_ k: String) -> Bool {
        if skip.contains(k) { return false }
        return !skipPrefixes.contains { k.hasPrefix($0) }
    }

    /** إعدادات التطبيق وحده (لا مفاتيح النظام) */
    private static var domain: [String: Any] {
        if let g = Store.d.persistentDomain(forName: Store.group), !g.isEmpty { return g }
        return UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
    }

    /** قيم صالحة لـ JSON فقط */
    private static func clean(_ v: Any) -> Any? {
        switch v {
        case let n as NSNumber: return CFGetTypeID(n) == CFBooleanGetTypeID() ? n.boolValue : n
        case let s as String: return s
        case let a as [Any]: return a.compactMap(clean)
        case let d as [String: Any]: return d.compactMapValues(clean)
        case let date as Date: return date.timeIntervalSince1970
        default: return nil
        }
    }

    static func payload(includeWeb: Bool = true) -> [String: Any] {
        var prefs: [String: Any] = [:]
        for (k, v) in domain where keep(k) && k != "web_state" { if let c = clean(v) { prefs[k] = c } }
        // «تابع الاستماع» بالصيغة الموحّدة مع أندرويد: {reciter, moshaf, surah, pos (بالثواني في الملف)}
        if let l = ListenLast.decodeRich(Store.d.string(forKey: "listen_last")), l.track.reciterID > 0, l.track.surah > 0 {
            prefs["listen_last"] = ["reciter": l.track.reciterID, "moshaf": l.track.moshafID, "surah": l.track.surah,
                                    "pos": l.pos, "name": l.track.reciter]
        } else if let s = Store.d.string(forKey: "listen_last"), let d = s.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            prefs["listen_last"] = o
        } else {
            prefs.removeValue(forKey: "listen_last")
        }
        var out: [String: Any] = ["app": "hawlalaalam", "v": 1, "at": Int(Date().timeIntervalSince1970), "platform": "ios", "prefs": prefs]
        if includeWeb, let s = Store.d.string(forKey: "web_state"), let d = s.data(using: .utf8),
           let w = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { out["web"] = w }
        return out
    }

    static func data(includeWeb: Bool = true) -> Data? {
        try? JSONSerialization.data(withJSONObject: payload(includeWeb: includeWeb), options: [.sortedKeys])
    }

    /** بصمة بيانات القارئ (دون الوقت والقيم المتغيّرة وحدها، ومع ترتيب ثابت لمفاتيح صفحة المصحف) */
    static func fingerprint() -> String {
        var p = payload()
        p.removeValue(forKey: "at")
        if var prefs = p["prefs"] as? [String: Any] {
            for k in Array(prefs.keys) where volatile.contains(k) || volatilePrefixes.contains(where: { k.hasPrefix($0) }) {
                prefs.removeValue(forKey: k)
            }
            p["prefs"] = prefs
        }
        guard let d = try? JSONSerialization.data(withJSONObject: p, options: [.sortedKeys]) else { return "" }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /** يحوّل صيغ أندرويد القديمة إلى أسماء آيفون: khatma.X ← khatma_X، وقائمة المفضّلين نصًّا ← أرقام */
    private static func normalize(_ key: String, _ value: Any) -> (String, Any)? {
        var k = key
        if k.hasPrefix("khatma.") { k = "khatma_" + k.dropFirst("khatma.".count) }
        else if k.hasPrefix("reading.") { k = String(k.dropFirst("reading.".count)) }
        else if k.hasPrefix("tasbeeh.") { k = String(k.dropFirst("tasbeeh.".count)) }
        switch k {
        case "listen_favs":
            if let a = value as? [Any] { return (k, a.compactMap { ($0 as? NSNumber)?.intValue ?? Int("\($0)") }) }
            if let s = value as? String, let d = s.data(using: .utf8), let a = try? JSONSerialization.jsonObject(with: d) as? [Any] {
                return (k, a.compactMap { ($0 as? NSNumber)?.intValue ?? Int("\($0)") })
            }
            return nil
        case "listen_last":
            // الصيغة الموحّدة كائن؛ نخزّنه نصًّا كما هو (يفهمه AudioPlayer.last)، والنص القديم من آيفون يُخزَّن كما هو
            // الملف يحمل الموضع بالثواني، والتخزين الداخلي بالملّي ثانية
            if var o = value as? [String: Any] {
                if let p = (o["pos"] as? NSNumber)?.doubleValue { o["pos"] = Int(p * 1000) }
                if let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) { return (k, s) }
            }
            if let o = value as? [String: Any], let d = try? JSONSerialization.data(withJSONObject: o),
               let s = String(data: d, encoding: .utf8) { return (k, s) }
            if let s = value as? String { return (k, s) }
            return nil
        default:
            return (k, value)
        }
    }

    struct Invalid: LocalizedError { var errorDescription: String? { "هذا الملف ليس نسخة احتياطية من «القرآن حول العالم»" } }

    /** يكتب القيم المحفوظة (يستبدل ما يقابلها ويبقي ما سواه) */
    @MainActor static func restore(_ data: Data) throws {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (o["app"] as? String) == "hawlalaalam", let prefs = o["prefs"] as? [String: Any] else { throw Invalid() }
        for (k0, v0) in prefs {
            guard let (k, v) = normalize(k0, v0), keep(k) else { continue }
            Store.d.set(v, forKey: k)
        }
        if let w = o["web"] as? [String: Any], !w.isEmpty,
           let d = try? JSONSerialization.data(withJSONObject: w), let s = String(data: d, encoding: .utf8) {
            Store.d.set(s, forKey: "web_state")
            Store.d.set(true, forKey: "web_restore_pending")
        }
        AppState.shared.reloadFromStore()
        ListenCatalog.shared.reloadFavorites()
    }

    static func fileName(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return "hawlalaalam-backup-" + f.string(from: date) + ".json"
    }

    static func exportFile() -> URL? {
        guard let d = data() else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(fileName())
        return (try? d.write(to: u)) != nil ? u : nil
    }
}

/**
 * مزامنة iCloud (مخزن المفاتيح). الحمولة نفسها في ملف النسخة الاحتياطية.
 * - الوقت المحفوظ هو وقت تغيّر البيانات على الجهاز، لا وقت الرفع؛ والأحدث يفوز.
 * - لا رفع إلا إذا تغيّرت بصمة البيانات منذ آخر مزامنة، فالجهاز الذي فُتح دون تغيير لا يكتب فوق غيره.
 * - عند فتح التطبيق نسحب أولًا ثم نرفع، ولا رفع أثناء تطبيق نسخة واردة ولا بعدها مباشرة (حتى لا يتبادل جهازان الاستعادة).
 */
@MainActor
enum CloudSync {
    private static let kv = NSUbiquitousKeyValueStore.default
    private static var observing = false
    private static var pushTask: Task<Void, Never>?
    private static var applying = false
    private static var quietUntil = Date.distantPast
    static let limit = 900_000

    static var enabled: Bool { Store.bool("icloud_on", false) }

    static var deviceID: String {
        if let s = Store.d.string(forKey: "sync_device"), !s.isEmpty { return s }
        let s = UUID().uuidString
        Store.d.set(s, forKey: "sync_device")
        return s
    }

    static var lastSync: Date? {
        let t = Store.d.double(forKey: "sync_at")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /** ما في iCloud: وقت تغيّر بياناته والجهاز الذي رفعه */
    static var remoteAt: Double { kv.double(forKey: "at") }

    /** تغيّرت بيانات هذا الجهاز منذ آخر مزامنة؟ */
    private static var dirty: Bool { Backup.fingerprint() != (Store.d.string(forKey: "sync_hash") ?? "") }
    private static var dirtyAt: Double { Store.d.double(forKey: "sync_dirty_at") }

    private static func markSynced(at: Double) {
        Store.d.set(at, forKey: "sync_at")
        Store.d.set(Backup.fingerprint(), forKey: "sync_hash")
        Store.d.set(0.0, forKey: "sync_dirty_at")
    }

    /** يسجّل وقت أول تغيّر لم يُرفع بعد */
    private static func noteChange() {
        guard !applying, Date() >= quietUntil, dirty else { return }
        if dirtyAt == 0 { Store.d.set(Date().timeIntervalSince1970, forKey: "sync_dirty_at") }
    }

    static func start() {
        guard enabled else { return }
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv, queue: .main) { _ in
                Task { @MainActor in CloudSync.pullIfNewer() }
            }
        }
        kv.synchronize()
        pullIfNewer()
    }

    /** عند أول تفعيل: إن كان في iCloud نسخة أحدث من جهاز آخر نسأل المستخدم */
    static var remoteNewerFromOtherDevice: Bool {
        kv.synchronize()
        guard let dev = kv.string(forKey: "device"), dev != deviceID else { return false }
        return remoteAt > Store.d.double(forKey: "sync_at") && kv.data(forKey: "backup") != nil
    }

    static func pullIfNewer() {
        guard enabled, !applying, let dev = kv.string(forKey: "device"), dev != deviceID,
              remoteAt > Store.d.double(forKey: "sync_at"), let d = kv.data(forKey: "backup") else { return }
        noteChange()
        // تغيير محلي أحدث من الوارد: يبقى المحلي ويُرفع
        if dirty, dirtyAt > remoteAt { push(); return }
        apply(d, at: remoteAt)
    }

    private static func apply(_ d: Data, at: Double) {
        applying = true
        defer { applying = false }
        guard (try? Backup.restore(d)) != nil else { return }
        markSynced(at: at)
        // صفحة المصحف تعيد إرسال حالتها بعد الاستعادة: نعدّها جزءًا منها لا تغييرًا جديدًا
        quietUntil = Date().addingTimeInterval(15)
        pushTask?.cancel()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000_000)
            if !CloudSync.applying, Store.d.double(forKey: "sync_at") == at { Store.d.set(Backup.fingerprint(), forKey: "sync_hash") }
        }
    }

    /** رفع مؤجّل (تُجمع التغييرات المتتالية)، فقط إن تغيّرت البيانات */
    static func schedulePush() {
        guard enabled, !applying, Date() >= quietUntil else { return }
        noteChange()
        guard dirtyAt > 0 else { return }
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { push() }
        }
    }

    /** يرفع إن كانت هناك تغييرات لم تُرفع (يُستدعى أيضًا عند الانتقال للخلفية) */
    static func push(force: Bool = false) {
        guard enabled, !applying else { return }
        if !force {
            noteChange()
            guard dirty else { return }
        }
        var d = Backup.data()
        if (d?.count ?? 0) > limit { d = Backup.data(includeWeb: false) }      // الحد الأقصى في iCloud ١ م.ب
        guard let data = d, data.count <= limit else { return }
        let at = dirtyAt > 0 ? dirtyAt : Date().timeIntervalSince1970
        kv.set(data, forKey: "backup")
        kv.set(at, forKey: "at")
        kv.set(deviceID, forKey: "device")
        kv.synchronize()
        markSynced(at: at)
    }

    static func setEnabled(_ on: Bool, takeRemote: Bool) {
        Store.d.set(on, forKey: "icloud_on")
        guard on else { return }
        kv.synchronize()
        if takeRemote, let d = kv.data(forKey: "backup") {
            apply(d, at: remoteAt)
        } else {
            push(force: true)
        }
        start()
    }
}

// MARK: - شاشة «النسخ والمزامنة»

struct BackupView: View {
    @EnvironmentObject var state: AppState
    @State private var icloud = CloudSync.enabled
    @State private var importing = false
    @State private var pending: Data?
    @State private var message: String?
    @State private var askRemote = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.fill").foregroundColor(Color(hex: 0x2F6FD6))
                            .frame(width: 46, height: 46).background(Circle().fill(Color(hex: 0x2F6FD6).opacity(0.12)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("المزامنة مع iCloud").font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                            Text(syncLine).font(AppFont.ui(12)).foregroundColor(Palette.muted)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { icloud }, set: { on in
                            if on && CloudSync.remoteNewerFromOtherDevice { askRemote = true; return }
                            icloud = on
                            CloudSync.setEnabled(on, takeRemote: false)
                        }))
                        .labelsHidden().tint(Palette.goldDeep)
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 14).card()

                Text("تنتقل ختمتك وعلاماتك وحفظك وسلسلتك تلقائيًا إلى أي آيفون أو آيباد بحسابك في iCloud.")
                    .font(AppFont.ui(13)).foregroundColor(Palette.muted).padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ما يُحفظ").font(AppFont.ui(15, 700)).foregroundColor(Palette.ink)
                    ForEach(["الختمة والورد اليومي", "العلامات وآخر موضع قراءة", "الحفظ ومواعيد المراجعة", "السلسلة وأيام القراءة",
                             "الإعدادات والتنبيهات والقرّاء المفضّلون", "ختمات العائلة التي انضممت إليها"], id: \.self) { t in
                        Label(t, systemImage: "checkmark").font(AppFont.ui(14)).foregroundColor(Palette.ink)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()

                Button {
                    if let u = Backup.exportFile() { Share.present([u]) } else { message = "تعذّر إنشاء الملف" }
                } label: { Pill(title: "تصدير نسخة احتياطية", systemImage: "square.and.arrow.up", primary: true, height: 50) }
                .buttonStyle(.plain)
                Button { importing = true } label: { Pill(title: "استعادة من ملف", systemImage: "arrow.down.doc", height: 50) }
                    .buttonStyle(.plain)
                Text("احفظ الملف في «الملفات» أو iCloud Drive أو Google Drive. ويمكن نقله إلى تطبيق أندرويد والعكس.")
                    .font(AppFont.ui(13)).foregroundColor(Palette.muted).padding(.horizontal, 4)
                Text("بياناتك لك وحدك · لا حساب ولا خادم لنا").font(AppFont.ui(12, 700)).foregroundColor(Palette.goldDeep)
                    .frame(maxWidth: .infinity).padding(.top, 6)
            }
            .padding(16)
        }
        .background(Palette.page.ignoresSafeArea())
        .navigationTitle("النسخ والمزامنة")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url) { pending = d } else { message = "تعذّرت قراءة الملف" }
        }
        .alert("استعادة النسخة الاحتياطية؟", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("استعد") {
                if let d = pending {
                    do { try Backup.restore(d); message = "تمت الاستعادة بفضل الله"; CloudSync.schedulePush() }
                    catch { message = error.localizedDescription }
                }
                pending = nil
            }
            Button("إلغاء", role: .cancel) { pending = nil }
        } message: { Text("تُستبدل الختمة والعلامات والحفظ والإعدادات الحالية بما في الملف.") }
        .alert("في iCloud نسخة أحدث", isPresented: $askRemote) {
            Button("استخدم نسخة iCloud") { icloud = true; CloudSync.setEnabled(true, takeRemote: true) }
            Button("استخدم بيانات هذا الجهاز") { icloud = true; CloudSync.setEnabled(true, takeRemote: false) }
            Button("إلغاء", role: .cancel) { }
        } message: { Text("وُجدت بيانات من جهاز آخر. أيّها تريد أن تبقى؟") }
        .alert("النسخ والمزامنة", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("حسنًا", role: .cancel) { }
        } message: { Text(message ?? "") }
    }

    private var syncLine: String {
        guard icloud else { return "متوقفة" }
        guard let d = CloudSync.lastSync else { return "مفعّلة" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ar")
        return "آخر مزامنة " + ar(f.localizedString(for: d, relativeTo: Date()))
    }
}
