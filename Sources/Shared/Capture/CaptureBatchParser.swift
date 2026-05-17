import Foundation

enum CaptureBatchParser {
    static func parse(_ input: String, projects: [ProjectToken]) -> [CaptureDraft] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let items = self.listItems(from: trimmed)
        guard items.count > 1 else {
            return [CaptureParser.parse(trimmed, projects: projects)]
        }

        return items.map { item in
            CaptureParser.parse(item, projects: projects)
        }
    }

    private static func listItems(from input: String) -> [String] {
        let lines = input
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let items = lines.compactMap(self.stripListMarker)
        guard items.count > 1 else { return [] }
        return items
    }

    private static func stripListMarker(from line: String) -> String? {
        if let checkboxItem = self.stripCheckboxMarker(from: line) {
            return checkboxItem
        }

        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if line.hasPrefix("• ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return self.stripNumberedMarker(from: line)
    }

    private static func stripCheckboxMarker(from line: String) -> String? {
        let prefixes = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] "]
        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func stripNumberedMarker(from line: String) -> String? {
        var index = line.startIndex
        var digitCount = 0
        while index < line.endIndex, line[index].isNumber {
            digitCount += 1
            index = line.index(after: index)
        }

        guard digitCount > 0, digitCount < 4, index < line.endIndex else { return nil }
        guard line[index] == "." || line[index] == ")" else { return nil }
        index = line.index(after: index)
        guard index < line.endIndex, line[index].isWhitespace else { return nil }

        let item = line[index...].trimmingCharacters(in: .whitespacesAndNewlines)
        return item.isEmpty ? nil : item
    }
}
