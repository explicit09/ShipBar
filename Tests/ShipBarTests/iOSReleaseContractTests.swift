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

    @Test("iPhone icon includes explicit dark and tinted variants")
    func appIconIncludesAppearanceVariants() throws {
        let catalogURL = self.repositoryURL(
            "Resources/iOS/Assets.xcassets/AppIcon.appiconset/Contents.json")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let images = try #require(catalog?["images"] as? [[String: Any]])

        for appearance in ["dark", "tinted"] {
            let variant = try #require(images.first { image in
                guard let appearances = image["appearances"] as? [[String: String]] else { return false }
                return appearances.contains { $0["value"] == appearance }
            })
            let filename = try #require(variant["filename"] as? String)
            #expect(FileManager.default.fileExists(
                atPath: catalogURL.deletingLastPathComponent().appendingPathComponent(filename).path))
        }
    }

    @Test("Mac app bundles the ShipBar AppIcon catalog")
    func macAppBundlesIconCatalog() throws {
        let project = try self.source("project.yml")
        #expect(project.contains("- path: Resources/Mac\n        buildPhase: resources"))
        #expect(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))

        let catalog = self.repositoryURL("Resources/Mac/Assets.xcassets/AppIcon.appiconset/Contents.json")
        #expect(FileManager.default.fileExists(atPath: catalog.path))
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

    @Test("share extension declares an App Store valid activation rule")
    func shareExtensionDeclaresActivationRule() throws {
        let data = try Data(contentsOf: self.repositoryURL("Config/ShareExtension/Info.plist"))
        let info = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let extensionInfo = try #require(info["NSExtension"] as? [String: Any])
        let attributes = try #require(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        let activation = try #require(attributes["NSExtensionActivationRule"] as? [String: Any])

        #expect(activation["NSExtensionActivationSupportsText"] as? Bool == true)
        #expect(activation["NSExtensionActivationSupportsWebURLWithMaxCount"] as? Int == 1)
        #expect(activation["NSExtensionActivationSupportsWebPageWithMaxCount"] as? Int == 1)
    }

    @Test("export policy permanently limits this build to internal TestFlight")
    func exportPolicyIsInternalOnly() throws {
        let data = try Data(contentsOf: self.repositoryURL("Config/iOS/ExportOptions.plist"))
        let options = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(options["method"] as? String == "app-store-connect")
        #expect(options["destination"] as? String == "upload")
        #expect(options["signingStyle"] as? String == "automatic")
        #expect(options["teamID"] as? String == "5986DKD528")
        #expect(options["iCloudContainerEnvironment"] as? String == "Production")
        #expect(options["testFlightInternalTestingOnly"] as? Bool == true)
        #expect(options["manageAppVersionAndBuildNumber"] as? Bool == false)
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
