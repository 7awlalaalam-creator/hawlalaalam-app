import SwiftUI
import UIKit

// هوية «حول العالم»: نفس ألوان تطبيق أندرويد (res/values/colors.xml و values-night/colors.xml)

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(UIColor(hex: hex, alpha: CGFloat(alpha)))
    }

    /** لون يتبدّل تلقائيًا بين النهاري والليلي */
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

enum Palette {
    static let page = Color.dyn(0xF6F8F9, 0x0B1A1E)
    static let card = Color.dyn(0xFFFFFF, 0x12262B)
    static let ink = Color.dyn(0x16353D, 0xE9EEF0)
    static let muted = Color.dyn(0x5D747C, 0x8FA6AC)
    static let gold = Color(hex: 0xC9A876)
    static let goldDeep = Color.dyn(0x9A7332, 0xC9A876)
    static let goldKey = Color.dyn(0x8A6A33, 0xD8BE92)
    static let goldLight = Color(hex: 0xE9D9B8)
    static let ivory = Color.dyn(0xFFFDF8, 0x162E33)
    static let ivoryBorder = Color.dyn(0xEFE4CF, 0x2A4A50)
    static let chip = Color.dyn(0xF5F1E6, 0x1A3439)
    static let dark = Color.dyn(0x123640, 0x0F2A30)
    static let onDarkMuted = Color(hex: 0xA9BABF)
    static let line = Color.dyn(0xE6E9EC, 0x1F3A41)
    static let primary = Color.dyn(0x16353D, 0x2E6370)
    static let fieldBorder = Color.dyn(0xD5DADF, 0x2A4A50)
    static let divider = Color.dyn(0xEEF0F2, 0x1A3136)
    static let logoBg = Color(hex: 0x0E2C31)
}

enum AppFont {
    /** خط الواجهة Tajawal (نفس ملفات تطبيق أندرويد) */
    static func ui(_ size: CGFloat, _ weight: Int = 400) -> Font {
        let name = weight >= 700 ? "Tajawal-Bold" : (weight >= 500 ? "Tajawal-Medium" : "Tajawal-Regular")
        return Font.custom(name, size: size)
    }

    /** خط مصحف المدينة (مجمع الملك فهد، الإصدار ١٨) */
    static func quran(_ size: CGFloat) -> Font {
        Font.custom("KFGQPCHAFSUthmanicScript-Regula", size: size)
    }
}

/** ٦٢ ← 62 */
func ar(_ n: Int) -> String { ar(String(n)) }

func ar(_ s: String) -> String {
    let digits: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
    return String(s.map { ch -> Character in
        if let v = ch.wholeNumberValue, ch.isASCII { return digits[v] }
        return ch
    })
}

/** «٣:٣٠ م» */
func formatTime(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    let h = c.hour ?? 0, m = c.minute ?? 0
    let h12 = h % 12 == 0 ? 12 : h % 12
    return ar(String(format: "%d:%02d %@", h12, m, h < 12 ? "ص" : "م"))
}

/** «الجمعة ٧ جمادى الأولى» بتقويم أم القرى */
func hijriToday(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .islamicUmmAlQura)
    f.locale = Locale(identifier: "ar")
    f.dateFormat = "EEEE d MMMM"
    return ar(f.string(from: date))
}

/** خلفية داكنة بزخرفة نجوم ثمانية ذهبية خفيفة (مثل Ui.PatternDrawable في أندرويد) */
struct PatternBackground: View {
    var color: Color = Palette.dark

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
            let cell: CGFloat = 44
            let half = cell * 0.2
            let stroke = Color(hex: 0xC9A876, alpha: 0.15)
            var y = cell / 2
            while y < size.height + cell {
                var x = cell / 2
                while x < size.width + cell {
                    let r = CGRect(x: x - half, y: y - half, width: half * 2, height: half * 2)
                    ctx.stroke(Path(r), with: .color(stroke), lineWidth: 1)
                    let t = CGAffineTransform(translationX: x, y: y)
                        .rotated(by: .pi / 4)
                        .translatedBy(x: -x, y: -y)
                    ctx.stroke(Path(r).applying(t), with: .color(stroke), lineWidth: 1)
                    x += cell
                }
                y += cell
            }
        }
    }
}

/** حلقة تقدّم ذهبية */
struct Ring: View {
    var fraction: Double
    var track: Color = Palette.chip
    var tint: Color = Palette.gold
    var width: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: width)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(width / 2)
    }
}

/** بطاقة بخلفية وإطار */
struct CardStyle: ViewModifier {
    var fill: Color = Palette.card
    var border: Color = Palette.line
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(border, lineWidth: 1))
    }
}

extension View {
    func card(_ fill: Color = Palette.card, border: Color = Palette.line, radius: CGFloat = 18) -> some View {
        modifier(CardStyle(fill: fill, border: border, radius: radius))
    }
}

/** زر كبسولة موحّد (مثل Ui.pill): أساسي داكن أو ثانوي بإطار */
struct Pill: View {
    var title: String
    var systemImage: String?
    var primary: Bool = false
    var height: CGFloat = 46

    var body: some View {
        HStack(spacing: 6) {
            if let s = systemImage {
                Image(systemName: s)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(primary ? Palette.gold : Palette.goldDeep)
            }
            Text(title).font(AppFont.ui(14, 700)).lineLimit(1)
        }
        .foregroundColor(primary ? .white : Palette.ink)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(Capsule().fill(primary ? Palette.primary : Palette.card))
        .overlay(Capsule().stroke(primary ? Color.clear : Palette.fieldBorder, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/** خانة أداة: أيقونة ذهبية واسم في سطر واحد */
struct ToolTile: View {
    var title: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(Palette.goldDeep)
                .frame(height: 26)
            Text(title).font(AppFont.ui(12, 700)).foregroundColor(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .card(radius: 16)
        .contentShape(Rectangle())
    }
}

/** شارة نجمة ثمانية برقم (فهرس السور) */
struct StarBadge: View {
    var text: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).stroke(Palette.gold, lineWidth: 1).frame(width: 24, height: 24)
            RoundedRectangle(cornerRadius: 3).stroke(Palette.gold, lineWidth: 1).frame(width: 24, height: 24)
                .rotationEffect(.degrees(45))
            Text(text).font(AppFont.ui(text.count > 2 ? 10 : 12, 700)).foregroundColor(Palette.goldKey)
        }
        .frame(width: 40, height: 40)
    }
}

/** نافذة المشاركة في الجوال */
enum Share {
    static func present(_ items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        if let pop = vc.popoverPresentationController {            // الآيباد
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }
}
