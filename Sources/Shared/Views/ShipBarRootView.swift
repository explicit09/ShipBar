import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ShipBarRootView: View {
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \ShipTask.createdAt, order: .reverse) private var tasks: [ShipTask]
    @Query(sort: \AgentRun.updatedAt, order: .reverse) private var agentRuns: [AgentRun]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedProjectID: String?
    @State private var selectedTask: ShipTask?
    @State private var selectedAgentRun: AgentRun?
    @State private var selectedSection = ShipBarSection.buildBar
    @State private var showGlobalCapture = false
    @State private var macDestination = ShipBarDestination.today
    @State private var sharedCaptureImportStatus = "No recent imports"
    @State private var settingsSheet: SettingsSheet?
    @State private var openAIKeyDraft = ""
    @State private var taskPendingDeletion: ShipTask?
    @State private var showTaskDeleteConfirm = false
    @State private var showCommandPalette = false

    private enum SettingsSheet: String, Identifiable {
        case promptTemplates
        case openAIKey
        case about

        var id: String { self.rawValue }

        var title: String {
            switch self {
            case .promptTemplates: "Prompt Templates"
            case .openAIKey: "OpenAI API Key"
            case .about: "About ShipBar"
            }
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            self.mobileBody
            #else
            self.macBody
            #endif
        }
        .sheet(item: self.$settingsSheet) { sheet in
            self.settingsSheetView(sheet)
        }
        .sheet(item: self.$selectedAgentRun) { run in
            AgentRunReviewView(
                run: run,
                task: self.tasks.first { $0.id == run.taskID },
                save: { ShipBarPersistence.save(self.modelContext, operation: "Save agent run review") },
                accept: self.acceptRun(_:task:),
                requestChanges: self.requestChanges(_:task:),
                fail: self.failRun,
                cancel: self.cancelRun)
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: self.$showTaskDeleteConfirm,
            titleVisibility: .visible)
        {
            Button("Delete", role: .destructive) {
                if let task = self.taskPendingDeletion {
                    self.deleteTask(task)
                }
                self.taskPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                self.taskPendingDeletion = nil
            }
        } message: {
            Text("This can't be undone.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .shipBarOpenSettings)) { _ in
            self.openSettingsSection()
        }
        .overlay {
            if self.showCommandPalette {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { self.showCommandPalette = false }
                    ShipBarCommandPaletteView(
                        tasks: self.tasks,
                        projects: self.projects,
                        runs: self.agentRuns,
                        execute: self.executeCommand,
                        dismiss: { self.showCommandPalette = false })
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .transaction { transaction in
            if self.reduceMotion { transaction.animation = nil }
        }
    }

    private var macBody: some View {
        VStack(spacing: 10) {
            ShipBarCommandStrip(
                openSearch: { self.showCommandPalette = true },
                openCapture: { self.showGlobalCapture = true })

            self.macDestinationContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()

            ShipBarDestinationDock(
                selection: Binding(
                    get: { self.macDestination },
                    set: { self.selectMacDestination($0) }),
                count: { $0.actionableCount(tasks: self.tasks, runs: self.agentRuns) })
        }
        .padding(.horizontal, ShipBarStyle.contentPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(ShipBarStyle.canvas)
        .sheet(isPresented: self.$showGlobalCapture) {
            VStack(alignment: .leading, spacing: 12) {
                ShipBarPageHeader(title: "Capture", purpose: "Turn it into actionable work.")
                QuickCaptureView(
                    projects: self.projects,
                    selectedProjectID: self.selectedProjectID,
                    createTask: { draft in
                        self.createTask(from: draft)
                        self.showGlobalCapture = false
                    },
                    autoFocus: true,
                    placeholder: ShipBarDestination.capturePrompt)
            }
            .padding(18)
            .frame(width: 420, height: 150)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shipBarOpenCapture)) { notification in
            guard ShipBarNotificationRouting.shouldPresentGlobalCapture(notification) else { return }
            self.showGlobalCapture = true
        }
    }

    @ViewBuilder
    private var macDestinationContent: some View {
        switch self.macDestination {
        case .today:
            TodayCommandCenterView(
                tasks: self.tasks,
                runs: self.agentRuns,
                setFocus: self.setFocus,
                removeFocus: self.removeFocus,
                moveFocus: self.moveFocus,
                selectTask: self.presentTaskDetail,
                toggleDone: self.toggleDone)
        case .inbox:
            self.inboxContent
        case .runs:
            AgentRunsView(runs: self.agentRuns) { run in
                self.selectedAgentRun = run
            }
        case .projects:
            if let selectedProject {
                ProjectWorkspaceView(
                    project: selectedProject,
                    tasks: TaskQueries.tasks(for: selectedProject, from: self.tasks),
                    runs: self.agentRuns,
                    createTask: self.createTask(from:),
                    selectTask: self.presentTaskDetail,
                    toggleDone: self.toggleDone,
                    handoffToAgent: self.handoffToAgent,
                    deleteProject: self.deleteProject(_:taskHandling:))
            } else {
                self.projectsList
            }
        case .settings:
            self.settingsContent
        }
    }

    private var projectsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ShipBarPageHeader(title: "Projects", purpose: "Outcomes, focus, and agent activity.") {
                    Button("New Project", systemImage: "folder.badge.plus", action: self.createProject)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                ForEach(self.projects) { project in
                    let projectTasks = self.tasks.filter { $0.project?.id == project.id }
                    let health = ProjectQueries.health(project: project, tasks: projectTasks, runs: self.agentRuns)
                    Button {
                        self.selectedProjectID = project.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(self.projectColor(project))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                if !project.outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(project.outcome)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(health.openCount) open")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            ShipBarProgressBar(progress: health.progress, tint: self.projectColor(project))
                                .frame(width: 48, height: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(ShipBarStyle.raisedSurface, in: RoundedRectangle(cornerRadius: ShipBarStyle.controlRadius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if self.projects.isEmpty {
                    ContentUnavailableView(
                        "No projects yet",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a project to group outcomes and agent activity."))
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func openCount(for project: Project) -> Int {
        self.tasks.filter { $0.project?.id == project.id && $0.status != .done }.count
    }

    private func projectColor(_ project: Project) -> Color {
        switch project.color {
        case "green": ShipBarStyle.promptGreen
        case "orange": .orange
        case "purple": .purple
        case "yellow": .yellow
        default: ShipBarStyle.accent
        }
    }

    #if os(iOS)
    @State private var iosTab: MobileTab = .today
    @State private var showCaptureSheet = false
    @State private var iosVoiceSession: VoiceSession?

    enum MobileTab: Hashable {
        case today, inbox, runs, projects, settings
    }

    private var mobileBody: some View {
        TabView(selection: self.$iosTab) {
            NavigationStack {
                IOSTodayPane(
                    tasks: self.tasks,
                    runs: self.agentRuns,
                    inboxCount: TaskQueries.inboxTasks(from: self.tasks).count,
                    projects: self.projects,
                    openCount: self.openCount(for:),
                    onCreateCapture: { self.showCaptureSheet = true },
                    selectTask: self.presentTaskDetail,
                    toggleDone: self.toggleDone,
                    setFocus: self.setFocus,
                    removeFocus: self.removeFocus,
                    delete: self.requestDeleteTask,
                    openInbox: { self.iosTab = .inbox },
                    openProject: { project in
                        self.selectedProjectID = project.id
                        self.iosTab = .projects
                    },
                    newProject: self.createProjectAndOpenIOS)
                    .navigationBarHidden(true)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 62)
                    }
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }
            .tag(MobileTab.today)

            NavigationStack {
                IOSTaskListPane(
                    mode: .inbox,
                    tasks: TaskQueries.inboxTasks(from: self.tasks),
                    projects: self.projects,
                    selectTask: self.presentTaskDetail,
                    toggleDone: self.toggleDone,
                    delete: self.requestDeleteTask,
                    scheduleToday: self.scheduleTodayFromInbox,
                    assignProject: self.triageTask(_:to:))
                    .navigationTitle("Inbox")
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 62)
                    }
            }
            .tabItem { Label("Inbox", systemImage: "tray.fill") }
            .tag(MobileTab.inbox)

            NavigationStack {
                IOSRunsPane(runs: self.agentRuns) { run in
                    self.selectedAgentRun = run
                }
                .navigationTitle("Runs")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 62)
                }
            }
            .tabItem { Label("Runs", systemImage: "paperplane.fill") }
            .badge(AgentRunQueries.queues(from: self.agentRuns).needsReview.count)
            .tag(MobileTab.runs)

            NavigationStack {
                Group {
                    if let selectedProject {
                        ProjectWorkspaceView(
                            project: selectedProject,
                            tasks: TaskQueries.tasks(for: selectedProject, from: self.tasks),
                            runs: self.agentRuns,
                            createTask: self.createTask(from:),
                            selectTask: self.presentTaskDetail,
                            toggleDone: self.toggleDone,
                            handoffToAgent: self.handoffToAgent,
                            deleteProject: self.deleteProject(_:taskHandling:))
                            .padding(.horizontal, 16)
                    } else {
                        IOSProjectListPane(
                            projects: self.projects,
                            openCount: self.openCount(for:),
                            select: { project in self.selectedProjectID = project.id })
                    }
                }
                .navigationTitle(self.selectedProject?.name ?? "Projects")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if self.selectedProject != nil {
                            Button("Projects") {
                                self.selectedProjectID = nil
                            }
                            .accessibilityLabel("Back to Projects")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: self.createProjectAndOpenIOS) {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityLabel("New Project")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 62)
                }
            }
            .tabItem { Label("Projects", systemImage: "folder.fill") }
            .tag(MobileTab.projects)

            NavigationStack {
                self.settingsContent
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 62)
                    }
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(MobileTab.settings)
        }
        .overlay(alignment: .bottom) {
            self.captureBar
                .padding(.bottom, 58)
        }
        .sheet(item: self.$selectedTask) { task in
            NavigationStack {
                TaskDetailView(task: task, projects: self.projects)
                    .navigationTitle("Task")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                self.selectedTask = nil
                            }
                            .accessibilityLabel("Close Task")
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: self.$showCaptureSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    QuickCaptureView(
                        projects: self.projects,
                        selectedProjectID: self.iosCaptureProjectID,
                        createTask: { draft in
                            self.createTask(from: draft)
                            self.showCaptureSheet = false
                        },
                        autoFocus: true)
                    Spacer()
                }
                .padding()
                .navigationTitle("Capture")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { self.showCaptureSheet = false }
                    }
                }
            }
            .presentationDetents([.height(170), .medium])
        }
        .sheet(item: self.$iosVoiceSession) { session in
            IOSVoiceCaptureView(
                session: session,
                onClose: {
                    session.stop()
                    self.iosVoiceSession = nil
                })
                .presentationDetents([.medium, .large])
        }
        .task {
            self.seedDefaultProjectIfNeeded()
            self.importPendingSharedCaptures()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shipBarOpenCapture)) { _ in
            self.showCaptureSheet = true
        }
        .onChange(of: self.scenePhase) { _, phase in
            guard phase == .active else { return }
            self.importPendingSharedCaptures()
        }
    }

    private var captureBar: some View {
        HStack(spacing: 8) {
            Button {
                self.showCaptureSheet = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(ShipBarStyle.accent)
                            .frame(width: 30, height: 30)
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("Quick Capture...")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "return")
                        .font(.system(size: 15))
                        .foregroundStyle(ShipBarStyle.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quick Capture")

            Button(action: self.openIOSVoiceCapture) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 46, height: 46)
                    .background {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice Capture")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func openIOSVoiceCapture() {
        self.iosVoiceSession = VoiceSession(modelContainer: self.modelContext.container)
    }

    private var iosCaptureProjectID: String? {
        switch self.iosTab {
        case .projects: self.selectedProjectID
        default: nil
        }
    }

    private func scheduleTodayFromInbox(_ task: ShipTask) {
        InboxBatchCoordinator.scheduleToday([task], among: self.tasks)
        ShipBarPersistence.save(self.modelContext, operation: "Schedule Inbox task today")
    }

    private func createProjectAndOpenIOS() {
        self.createProject()
        self.iosTab = .projects
    }
    #endif

    @ViewBuilder
    private var sectionContent: some View {
        switch self.selectedSection {
        case .buildBar:
            self.dashboardContent
        case .inbox:
            self.inboxContent
        case .projects:
            self.dashboardContent
        case .tasks:
            self.tasksContent
        case .prompts:
            TaskListView(
                title: "Prompts",
                tasks: self.tasks.filter(\.hasPrompt),
                selectTask: self.presentTaskDetail,
                toggleDone: self.toggleDone,
                handoffToAgent: self.handoffToAgent,
                projects: self.projects,
                triageToProject: self.triageTask(_:to:),
                updateStatus: self.updateStatus(_:to:),
                updatePriority: self.updatePriority(_:to:),
                updateType: self.updateType(_:to:))
        case .agents:
            VStack(alignment: .leading, spacing: 12) {
                Text("Agents")
                    .font(.system(size: 22, weight: .bold))
                Divider()
                Label("Claude Code", systemImage: "sparkles")
                Label("Codex", systemImage: "circle.hexagongrid")
                Label("Cursor", systemImage: "cube.fill")
                Spacer(minLength: 0)
            }
                    .font(.system(size: 14, weight: .medium))
        case .settings:
            self.settingsContent
        }
    }

    private var dashboardContent: some View {
        ShipBarDashboardView(
            projects: self.projects,
            tasks: self.tasks,
            selectedProjectID: self.selectedProjectID,
            createProject: self.createProject,
            createTask: self.createTask(from:),
            selectProject: self.selectProject,
            selectTask: self.presentTaskDetail,
            toggleDone: self.toggleDone,
            handoffToAgent: self.handoffToAgent)
    }

    private var inboxContent: some View {
        InboxTriageView(
            tasks: TaskQueries.inboxTasks(from: self.tasks),
            allTasks: self.tasks,
            projects: self.projects,
            createTask: self.createTask(from:),
            selectTask: self.presentTaskDetail,
            deleteTask: self.deleteTask)
    }

    @ViewBuilder
    private var tasksContent: some View {
        if let selectedProject {
            ProjectWorkspaceView(
                project: selectedProject,
                tasks: TaskQueries.tasks(for: selectedProject, from: self.tasks),
                runs: self.agentRuns,
                createTask: self.createTask(from:),
                selectTask: self.presentTaskDetail,
                toggleDone: self.toggleDone,
                handoffToAgent: self.handoffToAgent)
        } else {
            TaskListView(
                title: "Tasks",
                tasks: self.visibleTasks,
                selectTask: self.presentTaskDetail,
                toggleDone: self.toggleDone,
                handoffToAgent: self.handoffToAgent,
                projects: self.projects,
                triageToProject: self.triageTask(_:to:),
                updateStatus: self.updateStatus(_:to:),
                updatePriority: self.updatePriority(_:to:),
                updateType: self.updateType(_:to:))
        }
    }

    private var settingsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                ShipBarPageHeader(title: "Settings", purpose: "Storage, capture, and product details.")

                VStack(alignment: .leading, spacing: 0) {
                    self.diagnosticsRow(
                        title: "CloudKit sync",
                        status: ShipBarV2PreviewData.isEnabled()
                            ? "Preview only"
                            : ShipBarModelContainer.cloudKitDiagnostics.statusText,
                        detail: ShipBarV2PreviewData.isEnabled()
                            ? "Isolated in-memory store; CloudKit sync is disabled."
                            : ShipBarModelContainer.cloudKitDiagnostics.detailText,
                        systemImage: "icloud")
                    Divider().padding(.vertical, 10)
                    self.diagnosticsRow(
                        title: "Share Sheet Inbox",
                        status: SharedCaptureStore.diagnostics.statusText,
                        detail: "\(SharedCaptureStore.diagnostics.detailText) \(self.sharedCaptureImportStatus)",
                        systemImage: "square.and.arrow.down")
                    Divider().padding(.vertical, 10)
                    self.diagnosticsRow(
                        title: "Local saves",
                        status: ShipBarPersistence.statusText,
                        detail: ShipBarPersistence.detailText,
                        systemImage: "internaldrive")
                }
                .padding(12)
                .background(ShipBarStyle.raisedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    #if os(iOS)
                    self.settingsActionRow(
                        title: "OpenAI API Key",
                        systemImage: "key.fill",
                        action: self.openOpenAIKeySettings)
                    Divider().padding(.vertical, 10)
                    #endif
                    self.settingsActionRow(
                        title: "Prompt templates",
                        systemImage: "doc.text",
                        action: { self.settingsSheet = .promptTemplates })
                    Divider().padding(.vertical, 10)
                    self.settingsActionRow(
                        title: "About ShipBar",
                        systemImage: "info.circle",
                        action: { self.settingsSheet = .about })
                }
                .padding(12)
                .background(ShipBarStyle.raisedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.bottom, 8)
        }
        .padding(.horizontal, ShipBarStyle.contentPadding)
        .padding(.top, Self.settingsTopPadding)
    }

    private func diagnosticsRow(
        title: String,
        status: String,
        detail: String,
        systemImage: String) -> some View
    {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ShipBarStyle.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                    Spacer()
                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsActionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                #if os(iOS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                #endif
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func settingsSheetView(_ sheet: SettingsSheet) -> some View {
        #if os(iOS)
        NavigationStack {
            self.settingsSheetContent(sheet)
                .navigationTitle(sheet.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { self.settingsSheet = nil }
                    }
                }
        }
        #else
        self.settingsSheetContent(sheet)
            .frame(width: 360)
            .padding()
        #endif
    }

    @ViewBuilder
    private func settingsSheetContent(_ sheet: SettingsSheet) -> some View {
        switch sheet {
        case .promptTemplates:
            VStack(alignment: .leading, spacing: 12) {
                Label("Prompt-ready tasks", systemImage: "doc.on.doc")
                    .font(.system(size: 18, weight: .semibold))
                Text("Add task-specific agent instructions in a task's Prompt field. Prompt text can be copied from the task detail sheet for Codex, Claude Code, or Cursor.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Quick Capture syntax: put prompt text after a vertical bar, for example: Fix login bug | Inspect auth flow and patch the failing path.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding()
        case .openAIKey:
            VStack(alignment: .leading, spacing: 14) {
                Label("Realtime voice", systemImage: "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Voice Capture uses the OpenAI realtime model. The key is stored in this device's keychain.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(iOS)
                SecureField("sk-...", text: self.$openAIKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                #else
                SecureField("sk-...", text: self.$openAIKeyDraft)
                    .textFieldStyle(.roundedBorder)
                #endif
                HStack {
                    Button("Clear", role: .destructive) {
                        self.openAIKeyDraft = ""
                        KeychainStore.setOpenAIKey(nil)
                        self.settingsSheet = nil
                    }
                    Spacer()
                    Button("Save") {
                        self.saveOpenAIKey()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer(minLength: 0)
            }
            .padding()
        case .about:
            VStack(alignment: .leading, spacing: 12) {
                Label("ShipBar", systemImage: "shippingbox")
                    .font(.system(size: 18, weight: .semibold))
                Text("A local-first capture and task handoff tool for turning inbox items into project work and agent-ready prompts.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(self.sharedCaptureImportStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding()
        }
    }

    private func openOpenAIKeySettings() {
        self.openAIKeyDraft = KeychainStore.openAIKey() ?? ""
        self.settingsSheet = .openAIKey
    }

    private func saveOpenAIKey() {
        let trimmed = self.openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.setOpenAIKey(trimmed.isEmpty ? nil : trimmed)
        self.settingsSheet = nil
    }

    private static var settingsTopPadding: CGFloat {
        #if os(iOS)
        18
        #else
        8
        #endif
    }

    private var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return self.projects.first { $0.id == selectedProjectID }
    }

    private var visibleTasks: [ShipTask] {
        if let selectedProject {
            return TaskQueries.tasks(for: selectedProject, from: self.tasks)
        }
        return TaskQueries.todayTasks(from: self.tasks)
    }

    private func presentTaskDetail(_ task: ShipTask) {
        #if os(macOS)
        NotificationCenter.default.post(
            name: .shipBarOpenTaskDetail,
            object: nil,
            userInfo: [ShipBarNotificationKey.taskID: task.id])
        #else
        self.selectedTask = task
        #endif
    }

    private func createTask(from draft: CaptureDraft) {
        self.insertTask(from: draft)
        ShipBarPersistence.save(self.modelContext, operation: "Create task")
    }

    private func insertTask(from draft: CaptureDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let resolvedProject = self.project(for: draft.projectID ?? self.selectedProjectID)
        let task = ShipTask(
            title: title,
            prompt: draft.prompt,
            status: draft.status,
            priority: draft.priority,
            type: draft.type,
            dueDate: draft.dueDate,
            isInbox: resolvedProject == nil,
            sourceApp: draft.sourceApp,
            sourceURL: draft.sourceURL,
            rawCaptureText: draft.rawText,
            project: resolvedProject)
        self.modelContext.insert(task)
    }

    private func deleteTask(_ task: ShipTask) {
        ShipBarTaskLifecycle.delete(task, in: self.modelContext)
        ShipBarPersistence.save(self.modelContext, operation: "Delete task")
    }

    private func requestDeleteTask(_ task: ShipTask) {
        self.taskPendingDeletion = task
        self.showTaskDeleteConfirm = true
    }

    private func toggleDone(_ task: ShipTask) {
        task.applyStatus(task.status == .done ? .todo : .done)
        FocusCoordinator.normalize(self.tasks, on: .now)
        ShipBarPersistence.save(self.modelContext, operation: "Toggle task status")
    }

    private func setFocus(_ task: ShipTask) {
        guard FocusCoordinator.setFocus(task, among: self.tasks, on: .now) else { return }
        ShipBarPersistence.save(self.modelContext, operation: "Set today's focus")
    }

    private func removeFocus(_ task: ShipTask) {
        FocusCoordinator.removeFocus(task, among: self.tasks, on: .now)
        ShipBarPersistence.save(self.modelContext, operation: "Remove today's focus")
    }

    private func moveFocus(_ task: ShipTask, to position: Int) {
        FocusCoordinator.moveFocus(task, to: position, among: self.tasks, on: .now)
        ShipBarPersistence.save(self.modelContext, operation: "Reorder today's focus")
    }

    private func handoffToAgent(_ task: ShipTask, target: AgentTarget) {
        let run = AgentRunLifecycle.prepare(task: task, target: target, in: self.modelContext)
        guard ShipBarPersistence.save(self.modelContext, operation: "Prepare agent run") else { return }

        let action = AgentWorkflowAction.make(for: target, task: task)
        Clipboard.copy(action.clipboardText)
        AgentLauncher.open(target, repoPath: action.repoPath)
        _ = AgentRunLifecycle.transition(run, to: .handedOff)
        _ = task.beginAgentHandoff(to: target)
        ShipBarPersistence.save(self.modelContext, operation: "Hand off task")
    }

    private func acceptRun(_ run: AgentRun, task: ShipTask?) {
        AgentRunLifecycle.accept(run, task: task, completeTask: true)
        FocusCoordinator.normalize(self.tasks, on: .now)
        ShipBarPersistence.save(self.modelContext, operation: "Accept agent run")
    }

    private func requestChanges(_ run: AgentRun, task: ShipTask) {
        _ = AgentRunLifecycle.requestChanges(run, task: task, in: self.modelContext)
        ShipBarPersistence.save(self.modelContext, operation: "Request agent changes")
    }

    private func failRun(_ run: AgentRun) {
        let message = run.errorMessage.isEmpty ? "Marked failed during review." : run.errorMessage
        _ = AgentRunLifecycle.fail(run, message: message)
        ShipBarPersistence.save(self.modelContext, operation: "Fail agent run")
    }

    private func cancelRun(_ run: AgentRun) {
        _ = AgentRunLifecycle.transition(run, to: .canceled)
        ShipBarPersistence.save(self.modelContext, operation: "Cancel agent run")
    }

    private func triageTask(_ task: ShipTask, to project: Project) {
        task.triage(project: project)
        ShipBarPersistence.save(self.modelContext, operation: "Triage task")
    }

    private func updateStatus(_ task: ShipTask, to status: TaskStatus) {
        task.applyStatus(status)
        ShipBarPersistence.save(self.modelContext, operation: "Update task status")
    }

    private func updatePriority(_ task: ShipTask, to priority: TaskPriority) {
        task.priority = priority
        task.updatedAt = .now
        ShipBarPersistence.save(self.modelContext, operation: "Update task priority")
    }

    private func updateType(_ task: ShipTask, to type: TaskType) {
        task.type = type
        task.updatedAt = .now
        ShipBarPersistence.save(self.modelContext, operation: "Update task type")
    }

    private func createProject() {
        let project = Project(
            name: ShipBarProjectNaming.newProjectName(existing: self.projects),
            sortOrder: self.projects.count)
        self.modelContext.insert(project)
        self.selectedProjectID = project.id
        self.selectedSection = .projects
        #if os(iOS)
        self.iosTab = .projects
        #endif
        ShipBarPersistence.save(self.modelContext, operation: "Create project")
    }

    private func deleteProject(_ project: Project, taskHandling: ShipBarProjectTaskHandling) {
        if self.selectedProjectID == project.id {
            self.selectedProjectID = nil
        }
        ShipBarProjectLifecycle.delete(project, taskHandling: taskHandling, in: self.modelContext)
        ShipBarPersistence.save(self.modelContext, operation: "Delete project")
    }

    private func openSettingsSection() {
        #if os(macOS)
        self.selectMacDestination(.settings)
        #else
        self.iosTab = .settings
        #endif
    }

    private func executeCommand(_ command: ShipBarCommandResult) {
        if command.id.hasPrefix("nav:") {
            let destination = String(command.id.dropFirst("nav:".count))
            #if os(macOS)
            self.selectMacDestination(ShipBarDestination(rawValue: destination) ?? .today)
            #else
            switch destination {
            case "inbox": self.iosTab = .inbox
            case "projects": self.iosTab = .projects
            case "settings": self.iosTab = .settings
            default: self.iosTab = .today
            }
            #endif
            return
        }

        if command.id.hasPrefix("project:") {
            self.selectedProjectID = String(command.id.dropFirst("project:".count))
            #if os(macOS)
            self.selectMacDestination(.projects)
            #else
            self.iosTab = .projects
            #endif
            return
        }

        if command.id.hasPrefix("task:"),
           let task = self.tasks.first(where: { $0.id == String(command.id.dropFirst("task:".count)) })
        {
            self.presentTaskDetail(task)
            return
        }

        if command.id.hasPrefix("run:"),
           let run = self.agentRuns.first(where: { $0.id == String(command.id.dropFirst("run:".count)) })
        {
            self.selectedAgentRun = run
        }
    }

    private func selectProject(_ project: Project) {
        self.selectedProjectID = project.id
        self.selectedSection = .tasks
    }

    private func selectMacDestination(_ destination: ShipBarDestination) {
        self.macDestination = destination
        self.selectedProjectID = destination.retainedProjectID(self.selectedProjectID)
    }

    private func project(for id: String?) -> Project? {
        guard let id else { return nil }
        return self.projects.first { $0.id == id }
    }

    private func seedDefaultProjectIfNeeded() {
        ShipBarDefaultData.seedProjectsIfNeeded(in: self.modelContext)
    }

    private func importPendingSharedCaptures() {
        #if os(iOS)
        let captures: [SharedCapturePayload]
        do {
            captures = try SharedCaptureStore.consumeFromSharedContainer()
        } catch {
            self.sharedCaptureImportStatus = error.localizedDescription
            return
        }
        guard !captures.isEmpty else { return }
        let projectTokens = self.projects.map(\.token)
        for capture in captures {
            self.insertTask(from: capture.captureDraft(projects: projectTokens))
        }
        ShipBarPersistence.save(self.modelContext, operation: "Import shared captures")
        self.sharedCaptureImportStatus = captures.count == 1 ? "Imported 1 capture." : "Imported \(captures.count) captures."
        self.selectedSection = .inbox
        #endif
    }
}
