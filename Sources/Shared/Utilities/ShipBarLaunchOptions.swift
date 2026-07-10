enum ShipBarLaunchOptions {
    static func shouldOpenMain(arguments: [String]) -> Bool {
        arguments.contains("--open-main")
    }
}
