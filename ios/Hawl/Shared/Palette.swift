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
    static let onDarkSoft = Color(hex: 0xEFE4CF)
    static let widgetDark = Color(hex: 0x123640)
}

enum AppFont {
    /** خط الواجهة Tajawal (نفس ملفات تطبيق أندرويد) */
    static func ui(_ size: CGFloat, _ weight: Int = 400) -> Font {
        let name = weight >= 700 ? "Tajawal-Bold" : (weight >= 500 ? "Tajawal-Medium" : "Tajawal-Regular")
        return Font.custom(name, size: size)
    }

    /** خط مصحف المدينة (مجمع الملك فهد، الإصدار ١٨) */
    /** خط الأذكار المشكولة (Amiri Quran، كما في مسبحة أندرويد) */
    static func amiri(_ size: CGFloat) -> Font {
        Font.custom("AmiriQuran-Regular", size: size)
    }

    static func quran(_ size: CGFloat) -> Font {
        Font.custom("KFGQPCHAFSUthmanicScript-Regula", size: size)
    }
}

