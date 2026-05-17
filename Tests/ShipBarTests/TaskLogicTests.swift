import Foundation
import Testing

@Suite("Task logic")
struct TaskLogicTests {
    @Test("completedAt follows done status")
    func completedAtFollowsDoneStatus() {
        let task = ShipTask(title: "Ship parser")

        #expect(task.completedAt == nil)

        task.applyStatus(.done, now: Date(timeIntervalSince1970: 10))
        #expect(task.completedAt == Date(timeIntervalSince1970: 10))

        task.applyStatus(.todo, now: Date(timeIntervalSince1970: 20))
        #expect(task.completedAt == nil)
    }

    @Test("today queue includes only open tasks sorted by priority")
    func todayQueueSortsOpenTasks() {
        let low = ShipTask(title: "Low", priority: .low)
        let high = ShipTask(title: "High", priority: .high)
        let done = ShipTask(title: "Done", status: .done, priority: .high)

        let result = TaskQueries.todayTasks(from: [low, high, done])

        #expect(result.map { $0.title } == ["High", "Low"])
    }
}
