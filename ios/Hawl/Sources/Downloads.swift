import SwiftUI
import AVFoundation
import MediaPlayer

/**
 * التلاوات المحمّلة للاستماع دون إنترنت (ملفات mp3quran.net المباشرة) — مثل Downloads.java.
 * التحميل بجلسة خلفية فيستمر ولو خرج القارئ من التطبيق، والتشغيل من الجهاز بمشغّل التطبيق.
 */
final class AudioDownloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = AudioDownloads()
    static let changed = Notification.Name("hawl.downloads.changed")
    static let sessionID = "com.hawlalaalam.quran.audio"

    enum Status: String, Codable { case done, running, failed, none }

    struct Item: Codable, Identifiable, Equatable {
        var url: String
        var title: String
        var reciter: String
        var file: String
        var size: Int64 = 0
        var status: Status = .running
        var percent: Int = 0
        var time: Double = Date().timeIntervalSince1970
        var id: String { url }
    }

    @Published private(set) var items: [Item] = []

    /** يستدعيه النظام بعد انتهاء التحميلات والتطبيق في الخلفية */
    var backgroundCompletion: (() -> Void)?

    /** الجلسة الخلفية تُنشأ خارج الخيط الرئيسي: إنشاؤها ينتظر خدمة التحميل في النظام، وقد يطول ذلك
        (مثلًا بعد إعادة تشغيل الجوال وهو مقفل) فيُغلق النظام التطبيق لأنه تأخر أكثر من ١٠ ثوانٍ في الفتح */
    private var _session: URLSession?
    private let sessionLock = NSLock()
    private var session: URLSession {
        sessionLock.lock(); defer { sessionLock.unlock() }
        if let s = _session { return s }
        let cfg = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: OperationQueue.main)
        _session = s
        return s
    }

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "audio_downloads"),
           let list = try? JSONDecoder().decode([Item].self, from: data) {
            items = list
        }
        // تحميلات انقطعت مع إغلاق التطبيق: نطابقها مع الجلسة (في الخلفية، دون تأخير فتح التطبيق)
        DispatchQueue.global(qos: .utility).async {
            self.session.getAllTasks { tasks in
                let live = Set(tasks.compactMap { $0.originalRequest?.url?.absoluteString })
                DispatchQueue.main.async {
                    for i in self.items.indices where self.items[i].status == .running && !live.contains(self.items[i].url) {
                        self.items[i].status = FileManager.default.fileExists(atPath: self.fileURL(self.items[i]).path) ? .done : .failed
                    }
                    self.save()
                }
            }
        }
    }

    static func isAudio(_ url: String) -> Bool {
        let u = url.lowercased()
        return u.hasPrefix("http") && u.contains("mp3quran.net") && u.hasSuffix(".mp3")
    }

    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /** اسم ملف ثابت من الرابط (نفس فكرة Downloads.fileName في أندرويد) */
    static func fileName(_ url: String) -> String {
        guard let u = URL(string: url) else { return "audio.mp3" }
        let host = (u.host ?? "x").split(separator: ".").first.map(String.init) ?? "x"
        let path = u.path.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "_mp3$", with: "", options: .regularExpression)
        return host + path + ".mp3"
    }

    func fileURL(_ item: Item) -> URL { Self.dir.appendingPathComponent(item.file) }

    func item(_ url: String) -> Item? { items.first { $0.url == url } }

    func status(_ url: String) -> Status { item(url)?.status ?? .none }

    /** الملف المحلي إن كان مكتمل التحميل */
    func ready(_ url: String) -> URL? {
        guard let it = item(url), it.status == .done else { return nil }
        let f = fileURL(it)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    func start(url: String, title: String, reciter: String) {
        guard Self.isAudio(url), let u = URL(string: url) else { return }
        if let s = item(url)?.status, s == .done || s == .running { return }
        items.removeAll { $0.url == url }
        items.append(Item(url: url, title: title.isEmpty ? "تلاوة" : title, reciter: reciter, file: Self.fileName(url)))
        items.sort { $0.title < $1.title }
        save()
        session.downloadTask(with: u).resume()
    }

    func delete(_ url: String) {
        session.getAllTasks { tasks in
            for t in tasks where t.originalRequest?.url?.absoluteString == url { t.cancel() }
        }
        if let it = item(url) { try? FileManager.default.removeItem(at: fileURL(it)) }
        items.removeAll { $0.url == url }
        save()
    }

    func retry(_ it: Item) {
        delete(it.url)
        start(url: it.url, title: it.title, reciter: it.reciter)
    }

    var totalBytes: Int64 { items.filter { $0.status == .done }.reduce(0) { $0 + $1.size } }

    static func mb(_ bytes: Int64) -> String { ar(max(1, Int((Double(bytes) / 1_048_576).rounded()))) + " م.ب" }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: "audio_downloads") }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    private func update(_ url: String?, _ change: (inout Item) -> Void) {
        guard let u = url, let i = items.firstIndex(where: { $0.url == u }) else { return }
        change(&items[i])
    }

    // MARK: URLSessionDownloadDelegate (على الخيط الرئيسي)

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let u = downloadTask.originalRequest?.url?.absoluteString
        let pct = totalBytesExpectedToWrite > 0 ? Int(totalBytesWritten * 100 / totalBytesExpectedToWrite) : 0
        guard let cur = item(u ?? ""), cur.percent != pct else { return }
        update(u) {
            $0.percent = pct
            $0.size = max(totalBytesExpectedToWrite, totalBytesWritten)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let u = downloadTask.originalRequest?.url?.absoluteString ?? ""
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        let dest = Self.dir.appendingPathComponent(Self.fileName(u))
        try? FileManager.default.removeItem(at: dest)
        let ok = code < 400 && (try? FileManager.default.moveItem(at: location, to: dest)) != nil
        var excluded = dest
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true                       // لا تُرفع إلى iCloud (تُحمَّل من جديد عند الحاجة)
        try? excluded.setResourceValues(rv)
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
        update(u) {
            $0.status = ok ? .done : .failed
            $0.percent = ok ? 100 : 0
            if ok { $0.size = size }
        }
        save()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let e = error else { return }
        if (e as NSError).code == NSURLErrorCancelled { return }
        update(task.originalRequest?.url?.absoluteString) { $0.status = .failed }
        save()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundCompletion?()
        backgroundCompletion = nil
    }
}

/** قراءة «تابع الاستماع» بصيغة آيفون الكاملة (المقطع وقائمة التشغيل) من أي سياق */
enum ListenLast {
    static func decodeRich(_ s: String?) -> AudioPlayer.Last? {
        guard let s = s, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AudioPlayer.Last.self, from: d)
    }
}

// MARK: - مشغّل التلاوات (بث مباشر أو من الملف المحمّل، يستمر مع قفل الشاشة والتحكم من شاشة القفل)

/** مقطع في قائمة التشغيل: سورة لقارئ، أو إذاعة، أو تلاوة محمّلة */
struct Track: Codable, Equatable, Hashable {
    var url: String
    var title: String
    var reciter: String
    var reciterID: Int = 0
    var moshafID: Int = 0
    var surah: Int = 0
    var radio = false
}

@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5]

    @Published private(set) var current: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index = 0
    @Published private(set) var playing = false
    @Published private(set) var buffering = false
    @Published var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var speed: Float = 1
    @Published var repeatOne = false
    /** مؤقت النوم: وقت الإيقاف، أو الإيقاف في نهاية السورة */
    @Published private(set) var sleepAt: Date?
    @Published private(set) var sleepAtEnd = false
    @Published private(set) var sleepMinutes: Int?
    @Published private(set) var failed = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var wasPlayingBeforeInterruption = false
    private var sleepTask: Task<Void, Never>?
    private var lastSave: Double = 0

    private init() {
        let v = Store.d.object(forKey: "listen_speed") as? Double ?? 1
        speed = Self.speeds.contains(Float(v)) ? Float(v) : 1
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.resume() }; return .success }
        rc.pauseCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.pause() }; return .success }
        rc.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.toggle() }; return .success }
        rc.skipForwardCommand.preferredIntervals = [15]
        rc.skipBackwardCommand.preferredIntervals = [15]
        rc.skipForwardCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.skip(15) }; return .success }
        rc.skipBackwardCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.skip(-15) }; return .success }
        rc.nextTrackCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.next() }; return .success }
        rc.previousTrackCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.previous() }; return .success }
        rc.changePlaybackPositionCommand.addTarget { e in
            if let ev = e as? MPChangePlaybackPositionCommandEvent {
                let t = ev.positionTime
                Task { @MainActor in AudioPlayer.shared.seek(t) }
            }
            return .success
        }
        updateRemote()
        // مكالمة أو منبّه أو Siri: يتوقف الصوت ونعكس ذلك على الزر وشاشة القفل، ونستأنف إن سمح النظام
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let opts = AVAudioSession.InterruptionOptions(rawValue: (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0)
            Task { @MainActor in AudioPlayer.shared.interrupted(type, shouldResume: opts.contains(.shouldResume)) }
        }
        // فصل السماعة أو انقطاع البلوتوث: إيقاف مؤقت (لا يعلو الصوت من مكبّر الجوال فجأة)
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            if reason == .oldDeviceUnavailable { Task { @MainActor in AudioPlayer.shared.pause() } }
        }
    }

    private func interrupted(_ type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        switch type {
        case .began?:
            wasPlayingBeforeInterruption = playing
            playing = false
            saveLast(force: true)
            updateNowPlaying()
        case .ended?:
            if shouldResume && wasPlayingBeforeInterruption { resume() }
            wasPlayingBeforeInterruption = false
        default: break
        }
    }

    var hasNext: Bool { index + 1 < queue.count }
    var hasPrevious: Bool { index > 0 }

    /** تلاوة محمّلة من شاشة «المحمّلة» */
    func play(_ item: AudioDownloads.Item) {
        if current?.url == item.url, player != nil { resume(); return }
        play(queue: [Track(url: item.url, title: item.title, reciter: item.reciter)], start: 0)
    }

    /** قائمة تشغيل (سور القارئ متتالية) تبدأ من مقطع معيّن، مع الاستكمال من موضع محفوظ إن وُجد */
    func play(queue q: [Track], start: Int, at: Double = 0) {
        guard !q.isEmpty else { return }
        queue = q
        index = max(0, min(q.count - 1, start))
        load(at: at)
    }

    private func load(at: Double = 0) {
        guard index < queue.count else { return }
        let t = queue[index]
        teardown()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let src: URL? = AudioDownloads.shared.ready(t.url) ?? URL(string: t.url)
        guard let url = src else { return }
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain              // سرعة التلاوة دون تغيير طبقة الصوت
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        player = p
        current = t
        failed = false
        buffering = true
        position = at
        duration = 0
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { tm in
            Task { @MainActor in AudioPlayer.shared.tick(tm.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in AudioPlayer.shared.ended() }
        }
        statusObservation = item.observe(\.status, options: [.new]) { it, _ in
            let st = it.status
            Task { @MainActor in
                if st == .failed { AudioPlayer.shared.failed = true; AudioPlayer.shared.buffering = false; AudioPlayer.shared.playing = false }
            }
        }
        // الحالة الفعلية للمشغّل هي المرجع (إيقاف من النظام أو انتهاء أو تعثّر)
        controlObservation = p.observe(\.timeControlStatus, options: [.new]) { pl, _ in
            let st = pl.timeControlStatus
            Task { @MainActor in
                let a = AudioPlayer.shared
                guard a.player === pl else { return }
                a.buffering = st == .waitingToPlayAtSpecifiedRate
                let now = st != .paused
                if a.playing != now { a.playing = now; a.updateNowPlaying() }
            }
        }
        if at > 1 { p.seek(to: CMTime(seconds: at, preferredTimescale: 600)) }
        p.playImmediately(atRate: speed)
        playing = true
        updateNowPlaying()
        saveLast(force: true)
    }

    private func tick(_ s: Double) {
        guard let p = player else { return }
        position = s.isFinite ? s : 0
        if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        buffering = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
        updateNowPlaying()
        saveLast()
    }

    private func ended() {
        if sleepAtEnd { cancelSleep(); finish(); return }      // مؤقت «نهاية السورة» مقدَّم على التكرار
        if repeatOne { seek(0); player?.playImmediately(atRate: speed); return }
        if hasNext { index += 1; load() } else { finish() }
    }

    /** انتهت قائمة التشغيل: نوقف ونبقي آخر مقطع ظاهرًا */
    private func finish() {
        player?.pause()
        playing = false
        saveLast(force: true, done: true)
        updateNowPlaying()
    }

    func resume() {
        if current != nil, player == nil || failed || player?.currentItem?.status == .failed { load(at: position); return }
        player?.playImmediately(atRate: speed)
        playing = player != nil
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        playing = false
        saveLast(force: true)
        updateNowPlaying()
    }

    func toggle() { playing ? pause() : resume() }

    func next() { guard hasNext else { return }; index += 1; load() }

    func previous() {
        if position > 5 || !hasPrevious { seek(0); return }
        index -= 1
        load()
    }

    func skip(_ s: Double) {
        let target = max(0, position + s)
        seek(duration > 0 ? min(target, duration - 1) : target)
    }

    func seek(_ t: Double) {
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        position = t
        updateNowPlaying()
    }

    func setSpeed(_ v: Float) {
        speed = v
        Store.d.set(Double(v), forKey: "listen_speed")
        if playing { player?.rate = v }
        updateNowPlaying()
    }

    /** مؤقت النوم بالدقائق، أو ٠ لنهاية السورة، أو nil للإلغاء */
    func setSleep(minutes: Int?) {
        cancelSleep()
        guard let m = minutes else { return }
        if m == 0 { sleepAtEnd = true; return }
        let at = Date().addingTimeInterval(Double(m) * 60)
        sleepAt = at
        sleepMinutes = m
        sleepTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Double(m) * 60 * 1_000_000_000))
            if Task.isCancelled { return }
            AudioPlayer.shared.pause()
            AudioPlayer.shared.cancelSleep()
        }
    }

    func cancelSleep() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepAt = nil
        sleepAtEnd = false
        sleepMinutes = nil
    }

    func stop() {
        teardown()
        playing = false
        position = 0
        duration = 0
        current = nil
        queue = []
        index = 0
        cancelSleep()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateRemote()
    }

    private func teardown() {
        if let o = timeObserver { player?.removeTimeObserver(o) }
        timeObserver = nil
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = nil
        statusObservation = nil
        controlObservation = nil
        player?.pause()
        player = nil
    }

    // MARK: الاستكمال

    struct Last: Codable { var track: Track; var pos: Double; var queue: [Track]; var index: Int }

    static var last: Last? {
        guard let s = Store.d.string(forKey: "listen_last") else { return nil }
        if let l = ListenLast.decodeRich(s) { return l }
        // الصيغة الموحّدة (من نسخة احتياطية أو من أندرويد): {reciter, moshaf, surah, pos بالملّي ثانية}
        guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let rid = (o["reciter"] as? NSNumber)?.intValue, let sura = (o["surah"] as? NSNumber)?.intValue,
              let r = ListenCatalog.shared.reciter(rid) else { return nil }
        let mid = (o["moshaf"] as? NSNumber)?.intValue ?? 0
        guard let m = r.moshaf.first(where: { $0.id == mid }) ?? r.moshaf.first, m.surahs.contains(sura) else { return nil }
        let q = ListenCatalog.tracks(r, m)
        guard let i = q.firstIndex(where: { $0.surah == sura }) else { return nil }
        let pos = ((o["pos"] as? NSNumber)?.doubleValue ?? 0) / 1000
        return Last(track: q[i], pos: pos, queue: q, index: i)
    }

    func resumeLast() {
        guard let l = Self.last else { return }
        if current == l.track, player != nil { resume(); return }
        play(queue: l.queue.isEmpty ? [l.track] : l.queue, start: l.index, at: l.pos)
    }

    private func saveLast(force: Bool = false, done: Bool = false) {
        guard let t = current, !t.radio else { return }
        let now = Date().timeIntervalSince1970
        if !force && now - lastSave < 5 { return }
        lastSave = now
        let l = Last(track: t, pos: done ? 0 : position, queue: queue.count > 120 ? [t] : queue, index: queue.count > 120 ? 0 : index)
        if let d = try? JSONEncoder().encode(l), let s = String(data: d, encoding: .utf8) { Store.d.set(s, forKey: "listen_last") }
    }

    private func updateRemote() {
        let rc = MPRemoteCommandCenter.shared()
        rc.nextTrackCommand.isEnabled = hasNext
        rc.previousTrackCommand.isEnabled = current != nil
        let live = current?.radio == true
        rc.skipForwardCommand.isEnabled = !live
        rc.skipBackwardCommand.isEnabled = !live
        rc.changePlaybackPositionCommand.isEnabled = !live
    }

    private func updateNowPlaying() {
        updateRemote()
        guard let it = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: it.title,
            MPMediaItemPropertyArtist: it.reciter.isEmpty ? "القرآن حول العالم" : it.reciter,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(speed) : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: it.radio,
        ]
        if !it.radio {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - رسالة قصيرة أسفل الشاشة (مثل Toast في أندرويد)

@MainActor
final class Toast: ObservableObject {
    static let shared = Toast()
    @Published private(set) var message: String?
    private var hide: Task<Void, Never>?

    static func show(_ m: String) { shared.present(m) }

    private func present(_ m: String) {
        message = m
        hide?.cancel()
        hide = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { self.message = nil }
        }
    }
}

struct ToastOverlay: View {
    @ObservedObject private var toast = Toast.shared

    var body: some View {
        VStack {
            Spacer()
            if let m = toast.message {
                Text(m)
                    .font(AppFont.ui(14, 500))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Capsule().fill(Color(hex: 0x123640).opacity(0.95)))
                    .padding(.bottom, 90)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast.message)
        .allowsHitTesting(false)
    }
}
