import SwiftUI
import UIKit

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
