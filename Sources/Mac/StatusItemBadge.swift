import AppKit

enum StatusItemBadge {
    static func image(inboxCount: Int) -> NSImage {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let baseSymbol = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "ShipBar")?
            .withSymbolConfiguration(symbolConfig) ?? NSImage()

        guard inboxCount > 0 else {
            baseSymbol.isTemplate = true
            return baseSymbol
        }

        let countText = inboxCount > 99 ? "99+" : "\(inboxCount)"
        let font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = (countText as NSString).size(withAttributes: attributes)

        let spacing: CGFloat = 4
        let totalWidth = baseSymbol.size.width + spacing + ceil(textSize.width)
        let totalHeight = max(baseSymbol.size.height, ceil(textSize.height))

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()
        defer { image.unlockFocus() }

        let symbolRect = NSRect(
            x: 0,
            y: (totalHeight - baseSymbol.size.height) / 2,
            width: baseSymbol.size.width,
            height: baseSymbol.size.height)
        baseSymbol.isTemplate = true
        baseSymbol.draw(in: symbolRect)

        let textOrigin = NSPoint(
            x: baseSymbol.size.width + spacing,
            y: (totalHeight - textSize.height) / 2)
        (countText as NSString).draw(at: textOrigin, withAttributes: attributes)

        image.isTemplate = true
        return image
    }
}
