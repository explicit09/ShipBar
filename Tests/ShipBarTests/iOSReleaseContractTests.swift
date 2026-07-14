import Foundation
import Testing

@Suite("iOS release bundle contracts")
struct iOSReleaseContractTests {
    @Test("release identity comes from build settings")
    func releaseIdentityComesFromBuildSettings() throws {
        let project = try self.source("project.yml")
        let info = try self.source("Config/iOS/Info.plist")

        #expect(project.contains("MARKETING_VERSION: \"1.0\""))
        #expect(project.contains("CURRENT_PROJECT_VERSION: \"2\""))
        #expect(info.contains("$(MARKETING_VERSION)"))
        #expect(info.contains("$(CURRENT_PROJECT_VERSION)"))
        #expect(info.contains("<string>1.0</string>") == false)
    }

    @Test("first beta is iPhone only with complete phone orientations")
    func firstBetaIsConfiguredForIPhone() throws {
        let project = try self.source("project.yml")
        let info = try self.source("Config/iOS/Info.plist")

        #expect(project.contains("TARGETED_DEVICE_FAMILY: \"1\""))
        #expect(info.contains("UISupportedInterfaceOrientations"))
        #expect(info.contains("UIInterfaceOrientationPortrait"))
        #expect(info.contains("UIInterfaceOrientationLandscapeLeft"))
        #expect(info.contains("UIInterfaceOrientationLandscapeRight"))
    }

    @Test("release declares export compliance and production resources")
    func releaseDeclaresComplianceAndResources() throws {
        let project = try self.source("project.yml")
        let info = try self.source("Config/iOS/Info.plist")

        #expect(project.contains("path: Resources/iOS"))
        #expect(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
        #expect(info.contains("ITSAppUsesNonExemptEncryption"))
        #expect(info.contains("<false/>"))
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
