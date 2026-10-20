import SwiftUI
import SafariServices

/** صفحات الموقع التي صارت لها شاشات أصلية في التطبيق */
enum NativeRoute {
    static func screen(for url: URL) -> Screen? {
        let path = url.path.lowercased()
        let name = (path as NSString).lastPathComponent
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if name.hasPrefix("azkar-morning-evening") { return .azkar(nil) }
        if name.hasPrefix("prayer-times") { return .prayerTimes }
        if name.hasPrefix("family-khatma") { return .family(q.first { $0.name == "id" }?.value.flatMap { FamilyAPI.parseID($0) }) }
        if let m = name.range(of: "^ayah-([0-9]+)-([0-9]+)\\.html$", options: .regularExpression) {
            let parts = name[m].dropFirst(5).dropLast(5).split(separator: "-").compactMap { Int($0) }
            if parts.count == 2, Quran.valid(parts[0], parts[1]) { return .tafsir(parts[0], parts[1]) }
        }
        return nil
    }

    /** surah-18.html ← صفحة بداية السورة في المصحف */
    static func surahPage(_ url: URL) -> Int? {
        let name = (url.path as NSString).lastPathComponent.lowercased()
        guard name.hasPrefix("surah-"), name.hasSuffix(".html"),
              let n = Int(name.dropFirst(6).dropLast(5)), (1...114).contains(n) else { return nil }
        return Quran.surahStart[n - 1]
    }

    /** verse-story-card.html?surah=&from= ← بطاقة الآية تُرسم في التطبيق */
    static func verseCard(_ url: URL) -> (Int, Int)? {
        guard url.path.lowercased().hasSuffix("verse-story-card.html") else { return nil }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let s = q.first(where: { $0.name == "surah" })?.value.flatMap(Int.init),
              let a = q.first(where: { $0.name == "from" })?.value.flatMap(Int.init), Quran.valid(s, a) else { return nil }
        return (s, a)
    }
}

/** صفحات الموقع الأخرى (الترجمات، الخصوصية، المقالات…) تُفتح في متصفح سفاري داخل نافذة، لا داخل التطبيق */
enum Browser {
    @MainActor static func open(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController,
              ["http", "https"].contains((url.scheme ?? "").lowercased()) else { UIApplication.shared.open(url); return }
        var top = root
        while let p = top.presentedViewController { top = p }
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(hex: 0x9A7332)
        vc.dismissButtonStyle = .close
        top.present(vc, animated: true)
    }
}
