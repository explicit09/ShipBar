import Foundation
import ImageIO
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

        #expect(project.contains("- path: Resources/iOS\n        buildPhase: resources"))
        #expect(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
        #expect(info.contains("ITSAppUsesNonExemptEncryption"))
        #expect(info.contains("<false/>"))
    }

    @Test("app icon catalog points to a square 1024 pixel PNG")
    func appIconIsProductionSized() throws {
        let catalogURL = self.repositoryURL(
            "Resources/iOS/Assets.xcassets/AppIcon.appiconset/Contents.json")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let images = try #require(catalog?["images"] as? [[String: Any]])
        let universal = try #require(images.first { $0["idiom"] as? String == "universal" })
        #expect(universal["platform"] as? String == "ios")
        #expect(universal["size"] as? String == "1024x1024")

        let filename = try #require(universal["filename"] as? String)
        let imageURL = catalogURL.deletingLastPathComponent().appendingPathComponent(filename)
        let imageSource = try #require(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1024)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1024)
    }

    @Test("privacy manifest explicitly disables tracking")
    func privacyManifestDisablesTracking() throws {
        let data = try Data(contentsOf: self.repositoryURL("Resources/iOS/PrivacyInfo.xcprivacy"))
        let manifest = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect(manifest["NSPrivacyCollectedDataTypes"] is [[String: Any]])
        #expect(manifest["NSPrivacyAccessedAPITypes"] is [[String: Any]])
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: self.repositoryURL(relativePath), encoding: .utf8)
    }

    private func repositoryURL(_ relativePath: String) -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repositoryRoot.appendingPathComponent(relativePath)
    }
}
