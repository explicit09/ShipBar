import AppKit
import SwiftData

@MainActor
protocol StatusItemMenuDelegate: AnyObject {
    func menuDidRequestQuickCapture()
    func menuDidRequestVoiceCapture()
    func menuDidRequestOpenWindow()
    func menuDidRequestSettings()
    func menuDidRequestSetAPIKey()
    func menuDidRequestQuit()
    func menuDidRequestNewProject()
    func menuDidSelectTask(_ task: ShipTask)
    func menuDidToggleDone(_ task: ShipTask)
    func menuDidHandoffTask(_ task: ShipTask, to target: AgentTarget)
}

@MainActor
final class StatusItemMenuController: NSObject {
    private static let targetMenuWidth: CGFloat = 310
    private static let dynamicLabelWidth: CGFloat = 200
    private static let taskMetadataWidth: CGFloat = 72

    weak var delegate: StatusItemMenuDelegate?

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
        super.init()
    }

    func buildMenu() -> NSMenu {
        let tasks = self.fetchAllTasks()
        let projects = self.fetchAllProjects()
        let todayTasks = TaskQueries.todayTasks(from: tasks)
        let inboxTasks = TaskQueries.inboxTasks(from: tasks)

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = Self.targetMenuWidth

        self.appendTodaySection(to: menu, tasks: todayTasks)
        menu.addItem(.separator())
        self.appendInboxRow(to: menu, count: inboxTasks.count)
        menu.addItem(.separator())
        self.appendProjectsSection(to: menu, projects: projects, tasks: tasks)
        menu.addItem(.separator())
        self.appendCapture(to: menu)
        menu.addItem(.separator())
        self.appendFooter(to: menu)

        return menu
    }

    private func appendTodaySection(to menu: NSMenu, tasks: [ShipTask]) {
        let header = self.headerItem(title: "Today (\(tasks.count))")
        menu.addItem(header)

        if tasks.isEmpty {
            menu.addItem(self.disabledItem(title: "Nothing scheduled. Capture something."))
            return
        }

        for task in tasks.prefix(8) {
            menu.addItem(self.taskItem(task))
        }

        if tasks.count > 8 {
            menu.addItem(self.disabledItem(title: "+ \(tasks.count - 8) more in ShipBar"))
        }
    }

    private func appendInboxRow(to menu: NSMenu, count: Int) {
        let title = count == 0 ? "Inbox — empty" : "Inbox (\(count))"
        let item = NSMenuItem(
            title: title,
            action: #selector(self.openWindow),
            keyEquivalent: "i")
        item.keyEquivalentModifierMask = [.command]
        item.target = self
        item.image = self.symbolImage(count == 0 ? "tray" : "tray.full.fill", color: count == 0 ? .secondaryLabelColor : .systemOrange)
        menu.addItem(item)
    }

    private func appendProjectsSection(to menu: NSMenu, projects: [Project], tasks: [ShipTask]) {
        menu.addItem(self.headerItem(title: "Projects"))

        if projects.isEmpty {
            menu.addItem(self.disabledItem(title: "No projects yet"))
        }

        for project in projects {
            let projectTasks = TaskQueries.tasks(for: project, from: tasks).filter { $0.status != .done }
            let projectFont = NSFont.menuFont(ofSize: 0)
            let projectLabel = StatusMenuTextFitter.projectLabel(
                name: project.name,
                count: projectTasks.count,
                font: projectFont,
                maxWidth: Self.dynamicLabelWidth)
            let item = NSMenuItem(
                title: projectLabel,
                action: nil,
                keyEquivalent: "")
            item.toolTip = project.name
            item.image = self.symbolImage("folder.fill", color: self.projectAccent(for: project))

            let submenu = NSMenu()
            submenu.autoenablesItems = false
            if projectTasks.isEmpty {
                submenu.addItem(self.disabledItem(title: "No open tasks"))
            } else {
                for task in projectTasks.prefix(12) {
                    submenu.addItem(self.taskItem(task))
                }
                if projectTasks.count > 12 {
                    submenu.addItem(self.disabledItem(title: "+ \(projectTasks.count - 12) more"))
                }
            }
            item.submenu = submenu
            menu.addItem(item)
        }

        let newProject = NSMenuItem(
            title: "New Project…",
            action: #selector(self.newProject),
            keyEquivalent: "n")
        newProject.keyEquivalentModifierMask = [.command, .shift]
        newProject.target = self
        newProject.image = self.symbolImage("folder.badge.plus", color: .controlAccentColor)
        menu.addItem(newProject)
    }

    private func appendCapture(to menu: NSMenu) {
        let item = NSMenuItem(
            title: "Quick Capture…",
            action: #selector(self.quickCapture),
            keyEquivalent: "k")
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        item.image = self.symbolImage("plus.circle.fill", color: .controlAccentColor)
        menu.addItem(item)

        let voice = NSMenuItem(
            title: "Voice Capture…",
            action: #selector(self.voiceCapture),
            keyEquivalent: "v")
        voice.keyEquivalentModifierMask = [.command, .shift]
        voice.target = self
        voice.image = self.symbolImage("mic.fill", color: .systemPurple)
        menu.addItem(voice)
    }

    private func appendFooter(to menu: NSMenu) {
        let openWindow = NSMenuItem(
            title: "Open ShipBar…",
            action: #selector(self.openWindow),
            keyEquivalent: "o")
        openWindow.keyEquivalentModifierMask = [.command]
        openWindow.target = self
        openWindow.image = self.symbolImage("rectangle.stack", color: .secondaryLabelColor)
        menu.addItem(openWindow)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(self.openSettings),
            keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        settings.image = self.symbolImage("gearshape", color: .secondaryLabelColor)
        menu.addItem(settings)

        let apiKey = NSMenuItem(
            title: KeychainStore.openAIKey() == nil ? "Set OpenAI API Key…" : "Change OpenAI API Key…",
            action: #selector(self.setAPIKey),
            keyEquivalent: "")
        apiKey.target = self
        apiKey.image = self.symbolImage("key.fill", color: .secondaryLabelColor)
        menu.addItem(apiKey)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit ShipBar",
            action: #selector(self.quit),
            keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
    }

    private func taskItem(_ task: ShipTask) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = self.taskTitle(for: task)
        item.toolTip = task.title
        item.target = self
        item.action = #selector(self.taskClicked(_:))
        item.representedObject = task.id
        item.image = self.symbolImage(
            task.status == .done ? "checkmark.circle.fill" : "circle",
            color: task.status == .done ? .systemGreen : .tertiaryLabelColor)

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let open = NSMenuItem(title: "Open…", action: #selector(self.taskOpen(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = task.id
        submenu.addItem(open)

        let toggle = NSMenuItem(
            title: task.status == .done ? "Mark Todo" : "Mark Done",
            action: #selector(self.taskToggleDone(_:)),
            keyEquivalent: "")
        toggle.target = self
        toggle.representedObject = task.id
        submenu.addItem(toggle)

        submenu.addItem(.separator())

        let handoffHeader = NSMenuItem(title: "Hand off to", action: nil, keyEquivalent: "")
        handoffHeader.isEnabled = false
        submenu.addItem(handoffHeader)

        for target in AgentTarget.allCases {
            let handoff = NSMenuItem(
                title: target.label,
                action: #selector(self.taskHandoff(_:)),
                keyEquivalent: "")
            handoff.target = self
            handoff.image = self.symbolImage(target.systemImage, color: .controlAccentColor)
            handoff.representedObject = TaskHandoffPayload(taskID: task.id, targetRawValue: target.rawValue)
            submenu.addItem(handoff)
        }

        item.submenu = submenu
        return item
    }

    private func taskTitle(for task: ShipTask) -> NSAttributedString {
        let priorityDot = self.priorityDot(for: task.priority)
        let titleString = NSMutableAttributedString()
        titleString.append(priorityDot)
        titleString.append(NSAttributedString(string: "  "))

        let titleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: task.status == .done ? NSColor.tertiaryLabelColor : NSColor.labelColor,
        ]

        let metadataFont = NSFont.systemFont(ofSize: 11)
        var metaParts: [String] = []
        if let projectName = task.project?.name {
            metaParts.append(StatusMenuTextFitter.fitted(
                projectName,
                font: metadataFont,
                maxWidth: Self.taskMetadataWidth))
        } else if task.isInbox {
            metaParts.append("Inbox")
        }
        if task.hasPrompt {
            metaParts.append("Prompt")
        }

        let metadata = NSMutableAttributedString()
        if !metaParts.isEmpty {
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: metadataFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            metadata.append(NSAttributedString(
                string: "  · \(metaParts.joined(separator: " · "))",
                attributes: metaAttrs))
        }

        let fittedTitle = StatusMenuTextFitter.taskTitle(
            task.title,
            font: titleFont,
            fixedWidth: titleString.size().width + metadata.size().width,
            maxWidth: Self.dynamicLabelWidth)
        titleString.append(NSAttributedString(string: fittedTitle, attributes: titleAttrs))
        titleString.append(metadata)
        return titleString
    }

    private func priorityDot(for priority: TaskPriority) -> NSAttributedString {
        let color: NSColor = switch priority {
        case .high: .systemOrange
        case .medium: .secondaryLabelColor
        case .low: .systemBlue
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .black),
            .foregroundColor: color,
        ]
        return NSAttributedString(string: "●", attributes: attrs)
    }

    private func headerItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        item.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: attrs)
        return item
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        item.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        return item
    }

    private func symbolImage(_ name: String, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func projectAccent(for project: Project) -> NSColor {
        switch project.color {
        case "green": NSColor.systemGreen
        case "orange": NSColor.systemOrange
        case "purple": NSColor.systemPurple
        case "yellow": NSColor.systemYellow
        case "red": NSColor.systemRed
        default: NSColor.controlAccentColor
        }
    }

    private func fetchAllTasks() -> [ShipTask] {
        var descriptor = FetchDescriptor<ShipTask>()
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        return (try? self.modelContext.fetch(descriptor)) ?? []
    }

    private func fetchAllProjects() -> [Project] {
        var descriptor = FetchDescriptor<Project>()
        descriptor.sortBy = [SortDescriptor(\.sortOrder)]
        return (try? self.modelContext.fetch(descriptor)) ?? []
    }

    private func task(forID id: String) -> ShipTask? {
        let descriptor = FetchDescriptor<ShipTask>()
        let tasks = (try? self.modelContext.fetch(descriptor)) ?? []
        return tasks.first { $0.id == id }
    }

    @objc private func quickCapture() {
        self.delegate?.menuDidRequestQuickCapture()
    }

    @objc private func voiceCapture() {
        self.delegate?.menuDidRequestVoiceCapture()
    }

    @objc private func setAPIKey() {
        self.delegate?.menuDidRequestSetAPIKey()
    }

    @objc private func openWindow() {
        self.delegate?.menuDidRequestOpenWindow()
    }

    @objc private func openSettings() {
        self.delegate?.menuDidRequestSettings()
    }

    @objc private func quit() {
        self.delegate?.menuDidRequestQuit()
    }

    @objc private func newProject() {
        self.delegate?.menuDidRequestNewProject()
    }

    @objc private func taskClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let task = self.task(forID: id) else { return }
        self.delegate?.menuDidSelectTask(task)
    }

    @objc private func taskOpen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let task = self.task(forID: id) else { return }
        self.delegate?.menuDidSelectTask(task)
    }

    @objc private func taskToggleDone(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let task = self.task(forID: id) else { return }
        self.delegate?.menuDidToggleDone(task)
    }

    @objc private func taskHandoff(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? TaskHandoffPayload,
              let task = self.task(forID: payload.taskID),
              let target = AgentTarget(rawValue: payload.targetRawValue)
        else { return }
        self.delegate?.menuDidHandoffTask(task, to: target)
    }
}

private struct TaskHandoffPayload {
    let taskID: String
    let targetRawValue: String
}
