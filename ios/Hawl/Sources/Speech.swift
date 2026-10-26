import Foundation
import Speech
import AVFoundation
import WebKit

/**
 * التسميع: التعرّف على التلاوة بالعربية من نظام آيفون، ويُرسل النص المسموع إلى صفحة المصحف
 * (window.__hawlSpeech) التي تقارنه بكلمات الآيات. على الجهاز نفسه حين يدعمه آيفون، ولا يُحفظ الصوت.
 * طلب التعرّف من خوادم آبل محدود بدقيقة تقريبًا، فنبدأ طلبًا جديدًا تلقائيًا ما دام المستخدم يقرأ.
 */
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private weak var web: WKWebView?
    private var active = false
    private var lang = "ar-SA"
    private var lastText = ""
    /** رقم الطلب الحالي: نتجاهل ردود الطلبات القديمة (إلغاؤها يرسل خطأ، فلا نبدأ بسببه طلبًا جديدًا) */
    private var gen = 0
    /** يتوقف بعد دقيقة بلا كلام (التعرّف على الجهاز لا ينتهي وحده) */
    private var silence: Task<Void, Never>?

    func start(web: WKWebView?, lang: String) {
        self.web = web
        self.lang = lang.isEmpty ? "ar-SA" : lang
        gen += 1
        let token = gen                     // إن ضغط «إيقاف» أثناء طلب الإذن لا نبدأ بعده
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard self.gen == token else { return }
                guard status == .authorized else {
                    self.state("error", L("اسمح للتطبيق بالتعرّف على الكلام من: الإعدادات ← حول العالم"))
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        guard self.gen == token else { return }
                        guard granted else {
                            self.state("error", L("اسمح للتطبيق باستخدام الميكروفون من: الإعدادات ← حول العالم"))
                            return
                        }
                        self.active = true
                        self.begin()
                    }
                }
            }
        }
    }

    /** يُستدعى عند مغادرة المصحف أو الخروج من التطبيق: لا يبقى الميكروفون يعمل */
    func stopIfActive() { if active { stop() } }

    func stop() {
        active = false
        gen += 1
        silence?.cancel()
        finishRequest()
        // نعيد الصوت إلى وضع التلاوة المعتاد، ونُعلم التطبيقات الأخرى فيعود صوتها كما كان
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .spokenAudio)
        state("stopped", "")
    }

    private func begin() {
        gen += 1
        finishRequest()
        guard active else { return }
        let myGen = gen
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: lang)), rec.isAvailable else {
            active = false
            state("error", L("التعرّف على العربية غير متاح الآن في جوالك"))
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            if #available(iOS 16.0, *) { req.addsPunctuation = false }
            // محرّك جديد في كل مرة: القديم قد يحتفظ بصيغة صوت سابقة (مثل سماعات بلوتوث) فيُسقط التطبيق
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                active = false
                state("error", L("تعذّر الوصول إلى الميكروفون"))
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
            engine.prepare()
            try engine.start()
            request = req
            lastText = ""
            task = rec.recognitionTask(with: req) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString ?? ""
                let isFinal = result?.isFinal ?? false
                Task { @MainActor in
                    guard let self, self.gen == myGen else { return }
                    self.handle(text: text, isFinal: isFinal, failed: error != nil)
                }
            }
            state("listening", "")
            armSilence()
        } catch {
            active = false
            finishRequest()
            state("error", L("تعذّر بدء الاستماع"))
        }
    }

    private func armSilence() {
        silence?.cancel()
        silence = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled, let self, self.active else { return }
            self.stop()
        }
    }

    private func handle(text: String, isFinal: Bool, failed: Bool) {
        if !text.isEmpty && text != lastText { armSilence() }
        if !text.isEmpty { lastText = text }
        if isFinal || failed {
            // انتهى هذا الطلب (توقّف طويل أو حدّ الدقيقة): نثبّت ما سُمع ونبدأ طلبًا جديدًا إن كان المستخدم ما زال يقرأ
            let had = !lastText.isEmpty
            if had { send(lastText, final: true) }
            lastText = ""
            // خطأ دون أي كلام (لا ميكروفون أو لا تعرّف): نتوقف بدل تكرار المحاولة بلا نهاية
            if active && (had || isFinal) { begin() } else if active { stop() }
            return
        }
        if !text.isEmpty { send(text, final: false) }
    }

    private func finishRequest() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func send(_ text: String, final: Bool) {
        js(["type": "text", "text": text, "final": final])
    }

    private func state(_ s: String, _ msg: String) {
        js(["type": "state", "state": s, "msg": msg])
    }

    private func js(_ o: [String: Any]) {
        guard let web, let data = try? JSONSerialization.data(withJSONObject: o),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__hawlSpeech && window.__hawlSpeech(\(json))", completionHandler: nil)
    }
}
