import SwiftUI
import UIKit

/** خلفية داكنة بزخرفة نجوم ثمانية ذهبية خفيفة (مثل Ui.PatternDrawable في أندرويد) */
struct PatternBackground: View {
    var color: Color = Palette.dark
    @Environment(\.colorScheme) private var scheme

    /** تدرّج اللون نفسه: أفتح في الأعلى وأغمق في الأسفل (مثل Ui.brandGradient في أندرويد) */
    private var stops: [Color] {
        let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return [Color(UIColor(hue: h, saturation: s, brightness: min(1, b * 1.42), alpha: a)),
                Color(ui),
                Color(UIColor(hue: h, saturation: s, brightness: b * 0.62, alpha: a))]
    }

    var body: some View {
        let stops = self.stops
        return Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(stops: [.init(color: stops[0], location: 0),
                                                            .init(color: stops[1], location: 0.55),
                                                            .init(color: stops[2], location: 1)]),
                                           startPoint: CGPoint(x: size.width, y: 0),
                                           endPoint: CGPoint(x: 0, y: size.height)))
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
        .background(Capsule().fill(primary ? AnyShapeStyle(Palette.primaryGrad) : AnyShapeStyle(Palette.card)))
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
            Icon3D(systemImage: systemImage)
            Text(title).font(AppFont.ui(12, 700)).foregroundColor(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 84)
        .card(radius: 16)
        .contentShape(Rectangle())
    }
}

/** أيقونة ذهبية لامعة داخل مربع زجاجي بلون الهوية (مثل GlassTileDrawable و Ui.icon3d في أندرويد) */
struct Icon3D: View {
    var systemImage: String
    var box: CGFloat = 52

    private static let face = LinearGradient(colors: [Color(hex: 0xFFF4CF), Color(hex: 0xF0C766), Color(hex: 0xB07A24)],
                                             startPoint: .top, endPoint: .bottom)
    private static let tile = LinearGradient(colors: [Color(hex: 0x2A6878), Color(hex: 0x16353D), Color(hex: 0x0A1D22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        let r = box * 17 / 64
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        ZStack {
            shape.fill(Self.tile)
            shape.fill(RadialGradient(colors: [Color(hex: 0xE9C06A, alpha: 0.35), .clear],
                                      center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: box / 2))
            // لمعة زجاجية في النصف الأعلى
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: box * 1.3, height: box * 0.75)
                .offset(y: -box * 0.4)
                .clipShape(shape)
            shape.strokeBorder(Color(hex: 0xE9C06A, alpha: 0.55), lineWidth: 1)
            Image(systemName: systemImage)
                .font(.system(size: box * 0.42, weight: .medium))
                .foregroundStyle(Self.face)
                .shadow(color: .black.opacity(0.55), radius: 1.2, y: 1.2)
        }
        .frame(width: box, height: box)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .accessibilityHidden(true)
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
