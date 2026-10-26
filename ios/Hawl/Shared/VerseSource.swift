import Foundation

/** آية اليوم (نفس VerseRepo في أندرويد): من الصفحة الرئيسية للموقع، وإلا آية بحسب التاريخ دون إنترنت */
enum VerseSource {
    struct Verse: Equatable, Sendable {
        let surah: Int, ayah: Int, text: String
        var ref: String { L("سورة ") + Quran.surahName(surah) + L(" · الآية ") + ar(ayah) }
        var tafsirURL: URL { Links.ayah(surah, ayah) }
        var cardURL: URL { Links.site("verse-story-card.html?surah=\(surah)&from=\(ayah)&to=\(ayah)") }
        var shareText: String { "﴿ \(text) ﴾\n\(ref)\n\nالتفسير: \(tafsirURL.absoluteString)" }
    }

    static func cached() -> Verse? {
        let d = Store.d
        if let s = d.object(forKey: "v_s") as? Int, let a = d.object(forKey: "v_a") as? Int,
           let t = d.string(forKey: "v_text"), !t.isEmpty {
            return Verse(surah: s, ayah: a, text: t)
        }
        return nil
    }

    /** جُلبت آية اليوم من الموقع اليوم؟ */
    static var fresh: Bool { Store.string("v_date") == Reading.dayKey(Date()) && cached() != nil }

    /** يجلب آية اليوم ويحفظها (للتطبيق والويدجت والتحديث في الخلفية) */
    static func fetch(userAgent: String) async -> Verse? {
        let d = Store.d
        let today = Reading.dayKey(Date())
        var s = 0, a = 0, fromSite = false
        if Date().timeIntervalSince1970 - d.double(forKey: "v_try") > 3600 {
            var req = URLRequest(url: Links.home, timeoutInterval: 12)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            if let result = try? await URLSession.shared.data(for: req),
               let html = String(data: result.0, encoding: .utf8),
               let r = ref(in: html), Quran.valid(r.0, r.1) {
                s = r.0; a = r.1; fromSite = true
            }
            if !fromSite { d.set(Date().timeIntervalSince1970, forKey: "v_try") }
        }
        if !fromSite {
            if let c = cached(), d.string(forKey: "v_day") == today { return c }
            // دون اتصال: آية بحسب التاريخ
            let r = Quran.fromIndex(Int(Date().timeIntervalSince1970 / 86400))
            s = r.0; a = r.1
        }
        guard let t = Quran.verse(s, a), !t.isEmpty else { return cached() }
        d.set(fromSite ? today : "", forKey: "v_date")
        d.set(today, forKey: "v_day")
        d.set(s, forKey: "v_s")
        d.set(a, forKey: "v_a")
        d.set(t, forKey: "v_text")
        return Verse(surah: s, ayah: a, text: t)
    }

    /** أول رابط ayah-س-آ.html بعد «آية اليوم» في الصفحة الرئيسية */
    static func ref(in html: String) -> (Int, Int)? {
        guard let re = try? NSRegularExpression(pattern: "ayah-(\\d{1,3})-(\\d{1,3})\\.html") else { return nil }
        let ns = html as NSString
        let start = ns.range(of: "آية اليوم").location
        let from = start == NSNotFound ? 0 : start
        let m = re.firstMatch(in: html, range: NSRange(location: from, length: ns.length - from))
            ?? re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length))
        guard let match = m,
              let s = Int(ns.substring(with: match.range(at: 1))),
              let a = Int(ns.substring(with: match.range(at: 2))) else { return nil }
        return (s, a)
    }
}
