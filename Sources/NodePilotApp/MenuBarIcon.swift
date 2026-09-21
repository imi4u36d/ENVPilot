import AppKit

/// 菜单栏图标。
///
/// 跟 App 图标同一套图形：一个「>」折角加右边竖排的三个点，画成模板图
/// （`isTemplate = true`）。模板图只保留形状，系统会按菜单栏的明暗自己染色，
/// 所以深色菜单栏上不会再出现一块格格不入的蓝底或白底。
///
/// 之前用的是 SF Symbol `terminal.fill`，跟 App 图标没有关系。
enum MenuBarIcon {
    static let image: NSImage = makeImage()

    private static func makeImage() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let paint = NSColor.black

            // 「>」：两条等宽的圆头线段，跟 App 图标里那个白色折角同一个走向。
            let chevron = NSBezierPath()
            chevron.lineWidth = 2.6
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.move(to: NSPoint(x: 2.6, y: 13.0))
            chevron.line(to: NSPoint(x: 8.6, y: 9.0))
            chevron.line(to: NSPoint(x: 2.6, y: 5.0))
            chevron.stroke()
            chevron.fill()

            // 三个点：从 App 图标的绿/蓝/橙三个圆点降成同一层墨色。
            for y in [4.0, 9.0, 14.0] {
                let dot = NSBezierPath(ovalIn: NSRect(x: 12.6, y: y - 1.35, width: 2.7, height: 2.7))
                paint.setFill()
                dot.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
