import AppKit

enum StatusMenuTextFitter {
    static func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    static func fitted(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        guard maxWidth > 0 else { return "" }
        guard self.width(of: text, font: font) > maxWidth else { return text }

        let characters = Array(text)
        let ellipsis = "…"
        guard self.width(of: ellipsis, font: font) <= maxWidth else { return "" }

        var lower = 0
        var upper = characters.count
        while lower < upper {
            let candidateCount = (lower + upper + 1) / 2
            let candidate = String(characters.prefix(candidateCount)) + ellipsis
            if self.width(of: candidate, font: font) <= maxWidth {
                lower = candidateCount
            } else {
                upper = candidateCount - 1
            }
        }

        return String(characters.prefix(lower))
            .trimmingCharacters(in: .whitespacesAndNewlines) + ellipsis
    }

    static func projectLabel(
        name: String,
        count: Int,
        font: NSFont,
        maxWidth: CGFloat
    ) -> String {
        let suffix = "  (\(count))"
        let nameWidth = max(0, maxWidth - self.width(of: suffix, font: font))
        return self.fitted(name, font: font, maxWidth: nameWidth) + suffix
    }

    static func taskTitle(
        _ title: String,
        font: NSFont,
        fixedWidth: CGFloat,
        maxWidth: CGFloat
    ) -> String {
        self.fitted(title, font: font, maxWidth: max(0, maxWidth - fixedWidth))
    }
}
