import AppKit
import Foundation
import Testing

@Suite("Status menu text fitting")
struct StatusMenuTextFitterTests {
    private let font = NSFont.systemFont(ofSize: 13)

    @Test("short labels remain unchanged")
    func shortLabelsRemainUnchanged() {
        #expect(StatusMenuTextFitter.fitted("ShipBar", font: self.font, maxWidth: 360) == "ShipBar")
    }

    @Test("long labels fit the rendered width with one ellipsis")
    func longLabelsFitRenderedWidth() {
        let source = "Refine podcast guest questions to encourage monologue-friendly answers for social clips"
        let fitted = StatusMenuTextFitter.fitted(source, font: self.font, maxWidth: 220)

        #expect(fitted.hasSuffix("…"))
        #expect(fitted.filter { $0 == "…" }.count == 1)
        #expect(StatusMenuTextFitter.width(of: fitted, font: self.font) <= 220)
    }

    @Test("truncation preserves grapheme clusters")
    func truncationPreservesGraphemes() {
        let family = "👨‍👩‍👧‍👦"
        let fitted = StatusMenuTextFitter.fitted(
            String(repeating: family, count: 12),
            font: self.font,
            maxWidth: 80)

        #expect(fitted.hasSuffix("…"))
        #expect(fitted.dropLast().allSatisfy { String($0) == family })
    }

    @Test("non-positive and sub-ellipsis budgets return an empty label")
    func impossibleBudgetsReturnEmptyLabel() {
        #expect(StatusMenuTextFitter.fitted("ShipBar", font: self.font, maxWidth: 0).isEmpty)
        #expect(StatusMenuTextFitter.fitted("ShipBar", font: self.font, maxWidth: -10).isEmpty)
        let ellipsisWidth = StatusMenuTextFitter.width(of: "…", font: self.font)
        #expect(StatusMenuTextFitter.fitted("ShipBar", font: self.font, maxWidth: ellipsisWidth / 2).isEmpty)
    }

    @Test("project labels preserve their count and fit the native menu font")
    func projectLabelsFitNativeMenuFont() {
        let font = NSFont.menuFont(ofSize: 0)
        let label = StatusMenuTextFitter.projectLabel(
            name: String(repeating: "Very long project name ", count: 8),
            count: 12,
            font: font,
            maxWidth: 360)

        #expect(label.hasSuffix("  (12)"))
        #expect(label.contains("…"))
        #expect(StatusMenuTextFitter.width(of: label, font: font) <= 360)
    }

    @Test("task titles deterministically fit their remaining attributed width")
    func taskTitlesFitRemainingWidth() {
        let title = "Refine podcast guest questions to encourage monologue-friendly answers for social clips"
        let first = StatusMenuTextFitter.taskTitle(
            title,
            font: self.font,
            fixedWidth: 180,
            maxWidth: 360)
        let second = StatusMenuTextFitter.taskTitle(
            title,
            font: self.font,
            fixedWidth: 180,
            maxWidth: 360)

        #expect(first == second)
        #expect(first.hasSuffix("…"))
        #expect(StatusMenuTextFitter.width(of: first, font: self.font) <= 180)
    }

    @Test("compact task and project labels fit the CodexBar-sized content budget")
    func compactLabelsFitCodexBarContentBudget() {
        let projectFont = NSFont.menuFont(ofSize: 0)
        let compactProject = StatusMenuTextFitter.projectLabel(
            name: String(repeating: "Very long project name ", count: 8),
            count: 12,
            font: projectFont,
            maxWidth: 200)

        #expect(compactProject.hasSuffix("  (12)"))
        #expect(compactProject.filter { $0 == "…" }.count == 1)
        #expect(StatusMenuTextFitter.width(of: compactProject, font: projectFont) <= 200)

        let compactTask = StatusMenuTextFitter.taskTitle(
            "Refine podcast guest questions to encourage monologue-friendly answers for social clips",
            font: self.font,
            fixedWidth: 88,
            maxWidth: 200)

        #expect(compactTask.hasSuffix("…"))
        #expect(compactTask.filter { $0 == "…" }.count == 1)
        #expect(StatusMenuTextFitter.width(of: compactTask, font: self.font) <= 112)
    }

    @Test("task and project items use fitting and full-title tooltips")
    func controllerUsesFittingAndTooltips() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/Mac/StatusItemMenuController.swift"),
            encoding: .utf8)

        #expect(source.contains("StatusMenuTextFitter.projectLabel"))
        #expect(source.contains("StatusMenuTextFitter.taskTitle"))
        #expect(source.contains("NSFont.menuFont(ofSize: 0)"))
        #expect(source.contains("targetMenuWidth: CGFloat = 310"))
        #expect(source.contains("dynamicLabelWidth: CGFloat = 200"))
        #expect(source.contains("taskMetadataWidth: CGFloat = 72"))
        #expect(source.contains("menu.minimumWidth = Self.targetMenuWidth"))
        #expect(source.contains("item.toolTip = task.title"))
        #expect(source.contains("item.toolTip = project.name"))
    }
}
