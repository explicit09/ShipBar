import Foundation

enum InboxBatchCoordinator {
    static func assign(_ tasks: [ShipTask], to project: Project, now: Date = .now) {
        for task in tasks {
            task.triage(project: project, now: now)
        }
    }

    static func scheduleToday(
        _ selected: [ShipTask],
        among allTasks: [ShipTask],
        on day: Date = .now,
        calendar: Calendar = .current)
    {
        let startOfDay = calendar.startOfDay(for: day)
        for task in selected {
            task.isInbox = false
            task.dueDate = startOfDay
            task.updatedAt = .now
            _ = FocusCoordinator.setFocus(task, among: allTasks, on: day, calendar: calendar)
        }
    }

    static func moveToSomeday(
        _ selected: [ShipTask],
        among allTasks: [ShipTask],
        on day: Date = .now,
        calendar: Calendar = .current)
    {
        for task in selected {
            task.isInbox = false
            task.dueDate = nil
            FocusCoordinator.removeFocus(task, among: allTasks, on: day, calendar: calendar)
            task.updatedAt = .now
        }
    }
}
