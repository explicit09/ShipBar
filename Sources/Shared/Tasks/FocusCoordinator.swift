import Foundation

enum FocusCoordinator {
    static let maximumCount = 3

    @discardableResult
    static func setFocus(
        _ task: ShipTask,
        among tasks: [ShipTask],
        on day: Date,
        calendar: Calendar = .current) -> Bool
    {
        Self.normalize(tasks, on: day, calendar: calendar)
        if Self.isFocused(task, on: day, calendar: calendar) {
            return true
        }

        let focused = Self.focusedTasks(in: tasks, on: day, calendar: calendar)
        guard focused.count < Self.maximumCount, task.status != .done else { return false }

        task.focusDate = calendar.startOfDay(for: day)
        task.focusOrder = focused.count + 1
        task.updatedAt = .now
        return true
    }

    static func removeFocus(
        _ task: ShipTask,
        among tasks: [ShipTask],
        on day: Date,
        calendar: Calendar = .current)
    {
        task.focusDate = nil
        task.focusOrder = nil
        task.updatedAt = .now
        Self.normalize(tasks, on: day, calendar: calendar)
    }

    static func moveFocus(
        _ task: ShipTask,
        to position: Int,
        among tasks: [ShipTask],
        on day: Date,
        calendar: Calendar = .current)
    {
        guard Self.isFocused(task, on: day, calendar: calendar) else { return }

        var ordered = Self.focusedTasks(in: tasks, on: day, calendar: calendar)
            .filter { $0.id != task.id }
        let insertionIndex = min(max(position - 1, 0), ordered.count)
        ordered.insert(task, at: insertionIndex)

        for (index, item) in ordered.enumerated() {
            item.focusDate = calendar.startOfDay(for: day)
            item.focusOrder = index + 1
            item.updatedAt = .now
        }
    }

    static func normalize(
        _ tasks: [ShipTask],
        on day: Date,
        calendar: Calendar = .current)
    {
        for task in tasks where Self.isFocused(task, on: day, calendar: calendar) && task.status == .done {
            task.focusDate = calendar.startOfDay(for: day)
            task.focusOrder = nil
        }

        let focused = Self.focusedTasks(in: tasks, on: day, calendar: calendar)
        for (index, task) in focused.enumerated() {
            if index < Self.maximumCount {
                task.focusDate = calendar.startOfDay(for: day)
                task.focusOrder = index + 1
            } else {
                task.focusDate = nil
                task.focusOrder = nil
            }
        }
    }

    static func focusedTasks(
        in tasks: [ShipTask],
        on day: Date,
        calendar: Calendar = .current) -> [ShipTask]
    {
        tasks
            .filter { Self.isFocused($0, on: day, calendar: calendar) && $0.status != .done }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.focusOrder ?? Int.max
                let rhsOrder = rhs.focusOrder ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private static func isFocused(_ task: ShipTask, on day: Date, calendar: Calendar) -> Bool {
        guard let focusDate = task.focusDate else { return false }
        return calendar.isDate(focusDate, inSameDayAs: day)
    }
}
