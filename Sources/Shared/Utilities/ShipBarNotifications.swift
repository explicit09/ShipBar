import Foundation

extension Notification.Name {
    static let shipBarOpenCapture = Notification.Name("ShipBarOpenCapture")
    static let shipBarQuickCaptureSubmitted = Notification.Name("ShipBarQuickCaptureSubmitted")
    static let shipBarOpenTaskDetail = Notification.Name("ShipBarOpenTaskDetail")
}

enum ShipBarNotificationKey {
    static let taskID = "taskID"
}
