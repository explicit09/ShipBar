enum ShipBarPlatform {
    case macOS
    case iOS
}

enum AgentLaunchBehavior: Equatable {
    case launchLocally
    case prepareForMac
}

enum AgentLaunchPolicy {
    static func behavior(for target: AgentTarget, platform: ShipBarPlatform) -> AgentLaunchBehavior {
        _ = target
        return platform == .macOS ? .launchLocally : .prepareForMac
    }
}
