import Foundation

extension Notification.Name {
    static let shipBarOpenCapture = Notification.Name("ShipBarOpenCapture")
    static let shipBarQuickCaptureSubmitted = Notification.Name("ShipBarQuickCaptureSubmitted")
    static let shipBarOpenTaskDetail = Notification.Name("ShipBarOpenTaskDetail")
    static let shipBarOpenSettings = Notification.Name("ShipBarOpenSettings")
}

enum ShipBarNotificationKey {
    static let taskID = "taskID"
}
