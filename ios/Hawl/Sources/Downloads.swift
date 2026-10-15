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

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: OperationQueue.main)
    }()

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "audio_downloads"),
           let list = try? JSONDecoder().decode([Item].self, from: data) {
            items = list
        }
        // تحميلات انقطعت مع إغلاق التطبيق: نطابقها مع الجلسة
        session.getAllTasks { tasks in
            let live = Set(tasks.compactMap { $0.originalRequest?.url?.absoluteString })
            DispatchQueue.main.async {
                for i in self.items.indices where self.items[i].status == .running && !live.contains(self.items[i].url) {
                    self.items[i].status = FileManager.default.fileExists(atPath: self.fileURL(self.items[i]).path) ? .done : .failed
                }
                self.save()
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

// MARK: - مشغّل التلاوات المحمّلة (يستمر مع قفل الشاشة، والتحكم من شاشة القفل)

@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    @Published private(set) var current: AudioDownloads.Item?
    @Published private(set) var playing = false
    @Published var position: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?

    private init() {
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.resume() }; return .success }
        rc.pauseCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.pause() }; return .success }
        rc.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.toggle() }; return .success }
        rc.skipForwardCommand.preferredIntervals = [15]
        rc.skipBackwardCommand.preferredIntervals = [15]
        rc.skipForwardCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.skip(15) }; return .success }
        rc.skipBackwardCommand.addTarget { _ in Task { @MainActor in AudioPlayer.shared.skip(-15) }; return .success }
        rc.changePlaybackPositionCommand.addTarget { e in
            if let ev = e as? MPChangePlaybackPositionCommandEvent {
                let t = ev.positionTime
                Task { @MainActor in AudioPlayer.shared.seek(t) }
            }
            return .success
        }
    }

    func play(_ item: AudioDownloads.Item) {
        guard let file = AudioDownloads.shared.ready(item.url) else { return }
        if current?.url == item.url, player != nil { resume(); return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(url: file)
        player = p
        current = item
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { t in
            Task { @MainActor in
                let s = AudioPlayer.shared
                s.position = t.seconds.isFinite ? t.seconds : 0
                if let d = s.player?.currentItem?.duration.seconds, d.isFinite, d > 0 { s.duration = d }
                if let d = s.player?.currentItem?.duration.seconds, d.isFinite, s.position >= d - 0.3 { s.playing = false }
                s.updateNowPlaying()
            }
        }
        p.play()
        playing = true
        updateNowPlaying()
    }

    func resume() { player?.play(); playing = player != nil; updateNowPlaying() }
    func pause() { player?.pause(); playing = false; updateNowPlaying() }
    func toggle() { playing ? pause() : resume() }

    func skip(_ s: Double) { seek(max(0, position + s)) }

    func seek(_ t: Double) {
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        position = t
        updateNowPlaying()
    }

    func stop() {
        if let o = timeObserver { player?.removeTimeObserver(o) }
        timeObserver = nil
        player?.pause()
        player = nil
        playing = false
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateNowPlaying() {
        guard let it = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: it.title,
            MPMediaItemPropertyArtist: it.reciter.isEmpty ? "حول العالم" : it.reciter,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
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
