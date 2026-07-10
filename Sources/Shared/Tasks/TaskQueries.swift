import Foundation

struct TodayTaskGroups {
    let now: ShipTask?
    let next: [ShipTask]
    let waiting: [ShipTask]
    let completed: [ShipTask]
}

enum TaskQueries {
    static func inboxTasks(from tasks: [ShipTask]) -> [ShipTask] {
        filteredTasks(from: tasks, filter: .inbox)
    }

    static func todayTasks(from tasks: [ShipTask], now: Date = .now) -> [ShipTask] {
        let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        return tasks
            .filter { task in
                if task.status == .done { return false }
                guard let due = task.dueDate else { return true }
                return due < endOfToday
            }
            .sorted(by: sortByDueThenPriority)
    }

    static func todayGroups(
        from tasks: [ShipTask],
        runs: [AgentRun],
        now: Date = .now,
        calendar: Calendar = .current) -> TodayTaskGroups
    {
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay.addingTimeInterval(24 * 60 * 60)
        let activeRunStatuses: Set<AgentRunStatus> = [.handedOff, .running, .needsReview]
        let waitingTaskIDs = Set(runs.filter { activeRunStatuses.contains($0.status) }.map(\.taskID))
        let openTasks = tasks.filter { $0.status != .done }
        let waiting = openTasks
            .filter { waitingTaskIDs.contains($0.id) }
            .sorted(by: Self.sortByFocusThenDueThenPriority)

        let focused = FocusCoordinator.focusedTasks(in: openTasks, on: now, calendar: calendar)
        let availableFocused = focused.filter { !waitingTaskIDs.contains($0.id) }
        let nowTask = availableFocused.first
        let excludedIDs = Set(waiting.map(\.id) + [nowTask?.id].compactMap { $0 })
        var next = availableFocused.dropFirst().filter { !excludedIDs.contains($0.id) }

        let nextIDs = Set(next.map(\.id))
        let dueToday = openTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate < endOfDay &&
                !excludedIDs.contains(task.id) &&
                !nextIDs.contains(task.id)
        }
        next.append(contentsOf: dueToday.sorted(by: Self.sortByDueThenPriority))

        let completed = tasks
            .filter { task in
                guard task.status == .done, let completedAt = task.completedAt else { return false }
                return calendar.isDate(completedAt, inSameDayAs: now)
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        return TodayTaskGroups(
            now: nowTask,
            next: Array(next),
            waiting: waiting,
            completed: completed)
    }

    private static func sortByDueThenPriority(_ lhs: ShipTask, _ rhs: ShipTask) -> Bool {
        let lDate = lhs.dueDate ?? .distantFuture
        let rDate = rhs.dueDate ?? .distantFuture
        if lDate != rDate {
            return lDate < rDate
        }
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank < rhs.priority.sortRank
        }
        return lhs.createdAt > rhs.createdAt
    }

    private static func sortByFocusThenDueThenPriority(_ lhs: ShipTask, _ rhs: ShipTask) -> Bool {
        let lhsFocus = lhs.focusOrder ?? Int.max
        let rhsFocus = rhs.focusOrder ?? Int.max
        if lhsFocus != rhsFocus { return lhsFocus < rhsFocus }
        return Self.sortByDueThenPriority(lhs, rhs)
    }

    static func filteredTasks(from tasks: [ShipTask], filter: TaskFilter) -> [ShipTask] {
        tasks
            .filter { task in
                if !filter.includeDone, task.status == .done {
                    return false
                }
                if filter.inboxOnly, !task.isInbox {
                    return false
                }
                if !filter.inboxOnly, task.isInbox {
                    return false
                }
                if let status = filter.status, task.status != status {
                    return false
                }
                if let priority = filter.priority, task.priority != priority {
                    return false
                }
                if let type = filter.type, task.type != type {
                    return false
                }
                if let projectID = filter.projectID, task.project?.id != projectID {
                    return false
                }
                if filter.promptReadyOnly, !task.hasPrompt {
                    return false
                }
                return true
            }
            .sorted(by: sortByPriorityThenCreatedAt)
    }

    static func tasks(for project: Project, from tasks: [ShipTask]) -> [ShipTask] {
        filteredTasks(from: tasks, filter: TaskFilter(projectID: project.id))
    }

    private static func sortByPriorityThenCreatedAt(_ lhs: ShipTask, _ rhs: ShipTask) -> Bool {
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank < rhs.priority.sortRank
        }
        return lhs.createdAt > rhs.createdAt
    }
}
