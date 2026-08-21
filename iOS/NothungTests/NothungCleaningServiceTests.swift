import Foundation
import NothungCore
@testable import Nothung
import UIKit
import UniformTypeIdentifiers
import XCTest

final class NothungCleaningServiceTests: XCTestCase {
    func testDefaultRulesCleanXTrackingAndExpandBilibiliShortLinks() throws {
        let configuration = NothungRuleConfiguration.default
        let output = try NothungCleaningService.clean(
            "https://www.twitter.com/nothung/status/42?t=share&s=20",
            cleaner: configuration.makeCleaner()
        )

        XCTAssertEqual(output.cleaned, "https://x.com/nothung/status/42")
        XCTAssertEqual(
            output.appliedRegexRuleIdentifiers,
            [NothungRegexRule.nothungXTrackingCleanup.title]
        )
        let bilibiliOutput = try NothungCleaningService.clean(
            "https://m.bilibili.com/video/BV1Nothung?buvid=abc&share_source=copy_link#reply",
            cleaner: configuration.makeCleaner()
        )
        XCTAssertEqual(
            bilibiliOutput.cleaned,
            "https://www.bilibili.com/video/BV1Nothung#reply"
        )
        XCTAssertTrue(
            configuration.allowsRedirectExpansion(
                for: try XCTUnwrap(URL(string: "https://b23.tv/Pj3aF4G"))
            )
        )
        let youtubeOutput = try NothungCleaningService.clean(
            "https://m.youtube.com/watch?v=video&t=42s&list=playlist&index=2&si=share&feature=shared&pp=tracking&app=desktop&utm_source=copy#comments",
            cleaner: configuration.makeCleaner()
        )
        XCTAssertEqual(
            youtubeOutput.cleaned,
            "https://m.youtube.com/watch?v=video&t=42s&list=playlist&index=2#comments"
        )
        let youtubeShortOutput = try NothungCleaningService.clean(
            "https://youtu.be/video?t=42&si=share&feature=shared",
            cleaner: configuration.makeCleaner()
        )
        XCTAssertEqual(youtubeShortOutput.cleaned, "https://youtu.be/video?t=42")
        XCTAssertTrue(
            configuration.allowsRedirectExpansion(
                for: try XCTUnwrap(URL(string: "https://youtu.be/video?t=42"))
            )
        )
        XCTAssertEqual(configuration.regexRules.count, 2)
        XCTAssertTrue(
            configuration.regexRules.allSatisfy {
                $0.source == NothungRegexRule.nothungXTrackingCleanup.source
            }
        )
        XCTAssertEqual(
            configuration.redirectRules.first?.source,
            NothungRedirectRule.nothungBilibiliShortLink.source
        )
    }

    func testVersionOneConfigurationMigratesDefaultsOnlyOnceAndAllowsDeletion() throws {
        let suiteName = "NothungRuleMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var versionOne = NothungRuleConfiguration.default
        versionOne.schemaVersion = 1
        versionOne.regexRules = []
        versionOne.redirectRules = []
        defaults.set(try JSONEncoder().encode(versionOne), forKey: "ruleConfiguration.v1")

        var migrated = NothungRuleStorage.load(defaults: defaults)
        XCTAssertEqual(migrated.schemaVersion, NothungRuleConfiguration.currentSchemaVersion)
        XCTAssertEqual(
            migrated.regexRules,
            [.nothungXTrackingCleanup, .nothungBilibiliVideoSharingCleanup]
        )
        XCTAssertEqual(
            migrated.parameterRules,
            NothungParameterRule.nothungYouTubeRules
        )
        XCTAssertEqual(
            migrated.redirectRules,
            [.nothungBilibiliShortLink, .nothungYouTubeShortLink]
        )

        migrated.regexRules.removeAll()
        migrated.redirectRules.removeAll()
        try NothungRuleStorage.save(migrated, defaults: defaults)

        let reloaded = NothungRuleStorage.load(defaults: defaults)
        XCTAssertTrue(reloaded.regexRules.isEmpty)
        XCTAssertTrue(reloaded.redirectRules.isEmpty)
    }

    func testVersionThreeJSONWithoutAutomaticCaptureDecodesAndMigrates() throws {
        let json = #"""
        {
          "schemaVersion": 3,
          "useBuiltInTrackingRules": true,
          "cleanImmediatelyAfterPaste": false,
          "copyAfterCleaning": false,
          "restrictRedirectExpansionToRules": false,
          "parameterRules": [],
          "regexRules": [],
          "redirectRules": []
        }
        """#

        let decoded = try JSONDecoder().decode(
            NothungRuleConfiguration.self,
            from: Data(json.utf8)
        )
        XCTAssertFalse(decoded.automaticallyCaptureClipboard)

        let migrated = try decoded.migratedToCurrentSchema()
        XCTAssertEqual(migrated.schemaVersion, NothungRuleConfiguration.currentSchemaVersion)
        XCTAssertEqual(
            migrated.parameterRules.map(\.id),
            NothungParameterRule.nothungYouTubeRules.map(\.id)
        )
        XCTAssertEqual(
            migrated.redirectRules.map(\.id),
            [NothungRedirectRule.nothungYouTubeShortLink.id]
        )
    }

    func testVersionThreeMigrationPreservesChangesToExistingDefaults() throws {
        var versionThree = NothungRuleConfiguration.default
        versionThree.schemaVersion = 3
        versionThree.useBuiltInTrackingRules = false
        versionThree.parameterRules = []
        versionThree.redirectRules.removeAll {
            $0.id == NothungRedirectRule.nothungYouTubeShortLink.id
        }
        versionThree.regexRules.removeAll {
            $0.id == NothungRegexRule.nothungXTrackingCleanup.id
        }
        let bilibiliIndex = try XCTUnwrap(
            versionThree.regexRules.firstIndex {
                $0.id == NothungRegexRule.nothungBilibiliVideoSharingCleanup.id
            }
        )
        versionThree.regexRules[bilibiliIndex].isEnabled = false
        versionThree.redirectRules.removeAll {
            $0.id == NothungRedirectRule.nothungBilibiliShortLink.id
        }

        let migrated = try versionThree.migratedToCurrentSchema()

        XCTAssertFalse(migrated.useBuiltInTrackingRules)
        XCTAssertFalse(
            migrated.regexRules.contains {
                $0.id == NothungRegexRule.nothungXTrackingCleanup.id
            }
        )
        XCTAssertEqual(
            migrated.regexRules.first {
                $0.id == NothungRegexRule.nothungBilibiliVideoSharingCleanup.id
            }?.isEnabled,
            false
        )
        XCTAssertFalse(
            migrated.redirectRules.contains {
                $0.id == NothungRedirectRule.nothungBilibiliShortLink.id
            }
        )
        XCTAssertEqual(
            migrated.parameterRules.map(\.id),
            NothungParameterRule.nothungYouTubeRules.map(\.id)
        )
        XCTAssertTrue(
            migrated.redirectRules.contains {
                $0.id == NothungRedirectRule.nothungYouTubeShortLink.id
            }
        )
    }

    func testCurrentSchemaDoesNotRecreateDeletedOrDisabledYouTubeDefaults() throws {
        var current = NothungRuleConfiguration.default
        current.parameterRules.removeAll {
            $0.id == NothungParameterRule.nothungYouTubeParameters.id
        }
        let shortParameterIndex = try XCTUnwrap(
            current.parameterRules.firstIndex {
                $0.id == NothungParameterRule.nothungYouTubeShortLinkParameters.id
            }
        )
        current.parameterRules[shortParameterIndex].isEnabled = false
        current.redirectRules.removeAll {
            $0.id == NothungRedirectRule.nothungYouTubeShortLink.id
        }

        let migrated = try current.migratedToCurrentSchema()

        XCTAssertEqual(migrated, current)
        XCTAssertFalse(migrated.isDefaultFeatureEnabled(.youtubeParameters))
        XCTAssertFalse(migrated.isDefaultFeatureEnabled(.youtubeShortLinkExpansion))
    }

    func testDefaultFeatureSwitchesUseStableRulesAndRestoreDeletedRules() {
        var configuration = NothungRuleConfiguration.default

        XCTAssertEqual(
            NothungParameterRule.nothungYouTubeParameters.id.uuidString,
            "A24C7FC2-61D6-4EE9-A8BC-9AC7911BE004"
        )
        XCTAssertEqual(
            NothungParameterRule.nothungYouTubeShortLinkParameters.id.uuidString,
            "A24C7FC2-61D6-4EE9-A8BC-9AC7911BE005"
        )
        XCTAssertEqual(
            NothungRedirectRule.nothungYouTubeShortLink.id.uuidString,
            "A24C7FC2-61D6-4EE9-A8BC-9AC7911BE006"
        )

        for feature in NothungDefaultFeature.allCases {
            XCTAssertFalse(feature.title.isEmpty)
            XCTAssertFalse(feature.explanation.isEmpty)
            XCTAssertTrue(configuration.isDefaultFeatureEnabled(feature))
            configuration.setDefaultFeature(feature, isEnabled: false)
            XCTAssertFalse(configuration.isDefaultFeatureEnabled(feature))
            configuration.setDefaultFeature(feature, isEnabled: true)
            XCTAssertTrue(configuration.isDefaultFeatureEnabled(feature))
        }

        XCTAssertEqual(
            Set(NothungDefaultFeature.allCases.filter(\.requiresNetwork)),
            [.bilibiliShortLinkExpansion, .youtubeShortLinkExpansion]
        )

        configuration.parameterRules.removeAll {
            $0.id == NothungParameterRule.nothungYouTubeParameters.id
        }
        XCTAssertFalse(configuration.isDefaultFeatureEnabled(.youtubeParameters))
        configuration.setDefaultFeature(.youtubeParameters, isEnabled: true)
        XCTAssertTrue(configuration.isDefaultFeatureEnabled(.youtubeParameters))
        XCTAssertEqual(
            configuration.parameterRules.filter {
                NothungParameterRule.nothungYouTubeRules.map(\.id).contains($0.id)
            }.count,
            2
        )
    }

    func testVersionTwoConfigurationAddsBilibiliCleanupOnlyOnce() throws {
        let suiteName = "NothungRuleVersionTwoMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var versionTwo = NothungRuleConfiguration.default
        versionTwo.schemaVersion = 2
        versionTwo.regexRules = [.nothungXTrackingCleanup]
        defaults.set(try JSONEncoder().encode(versionTwo), forKey: "ruleConfiguration.v1")

        var migrated = NothungRuleStorage.load(defaults: defaults)
        XCTAssertEqual(
            migrated.regexRules,
            [.nothungXTrackingCleanup, .nothungBilibiliVideoSharingCleanup]
        )

        migrated.regexRules.removeAll {
            $0.id == NothungRegexRule.nothungBilibiliVideoSharingCleanup.id
        }
        try NothungRuleStorage.save(migrated, defaults: defaults)

        let reloaded = NothungRuleStorage.load(defaults: defaults)
        XCTAssertFalse(
            reloaded.regexRules.contains {
                $0.id == NothungRegexRule.nothungBilibiliVideoSharingCleanup.id
            }
        )
    }

    func testStoredBuiltInMetadataFollowsCurrentAppLanguage() throws {
        let suiteName = "NothungRuleLocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var stored = NothungRuleConfiguration.default
        stored.regexRules[0].title = "X / Twitter 去除跟踪参数"
        stored.regexRules[0].source = "Nothung · 内置规则"
        stored.redirectRules[0].title = "哔哩哔哩短链"
        stored.redirectRules[0].source = "Nothung · 内置规则"
        stored.parameterRules[0].title = "YouTube 视频分享去参数"
        stored.parameterRules[0].source = "Nothung · 内置规则"
        stored.parameterRules[1].title = "YouTube 短链分享去参数"
        stored.parameterRules[1].source = "Nothung · 内置规则"
        stored.redirectRules[1].title = "YouTube 短链"
        stored.redirectRules[1].source = "Nothung · 内置规则"
        defaults.set(
            try JSONEncoder().encode(stored),
            forKey: "ruleConfiguration.v1"
        )

        let loaded = NothungRuleStorage.load(defaults: defaults)

        XCTAssertEqual(
            loaded.regexRules[0].title,
            NothungRegexRule.nothungXTrackingCleanup.title
        )
        XCTAssertEqual(
            loaded.regexRules[0].source,
            NothungRegexRule.nothungXTrackingCleanup.source
        )
        XCTAssertEqual(
            loaded.redirectRules[0].title,
            NothungRedirectRule.nothungBilibiliShortLink.title
        )
        XCTAssertEqual(
            loaded.redirectRules[0].source,
            NothungRedirectRule.nothungBilibiliShortLink.source
        )
        XCTAssertEqual(
            loaded.parameterRules[0].title,
            NothungParameterRule.nothungYouTubeParameters.title
        )
        XCTAssertEqual(
            loaded.parameterRules[0].source,
            NothungParameterRule.nothungYouTubeParameters.source
        )
        XCTAssertEqual(
            loaded.parameterRules[1].title,
            NothungParameterRule.nothungYouTubeShortLinkParameters.title
        )
        XCTAssertEqual(
            loaded.redirectRules[1].title,
            NothungRedirectRule.nothungYouTubeShortLink.title
        )
    }

    func testServiceUsesAllowlistAndOrderedRegexPipeline() throws {
        let policy = QueryParameterPolicy(
            blockedRules: [TrackingRule(prefix: "utm_")],
            allowedRules: [TrackingRule(exactName: "utm_content")]
        )
        let regexRule = try OrderedRegexRule(
            identifier: "canonical-story",
            pattern: "/story/(\\d+)",
            replacementTemplate: "/articles/$1"
        )
        let cleaner = NothungCleaner(
            parameterPolicy: policy,
            regexRules: [regexRule]
        )

        let output = try NothungCleaningService.clean(
            "https://example.com/story/42?utm_source=test&utm_content=body&id=7",
            cleaner: cleaner
        )

        XCTAssertEqual(
            output.cleaned,
            "https://example.com/articles/42?utm_content=body&id=7"
        )
        XCTAssertEqual(output.removedFields.map(\.name), ["utm_source"])
        XCTAssertEqual(output.appliedRegexRuleIdentifiers, ["canonical-story"])
        XCTAssertTrue(output.didChange)
    }

    func testServiceReportsNoWebURL() {
        XCTAssertThrowsError(try NothungCleaningService.clean("只有普通文本")) { error in
            guard let cleaningError = error as? NothungCleaningService.CleaningError,
                  case .noWebURL = cleaningError else {
                return XCTFail("Expected noWebURL, received \(error)")
            }
        }
    }

    func testServiceRejectsOversizedInputBeforeDetection() {
        let input = String(
            repeating: "a",
            count: NothungCleaningService.maximumInputLength + 1
        )

        XCTAssertThrowsError(try NothungCleaningService.clean(input)) { error in
            guard let cleaningError = error as? NothungCleaningService.CleaningError,
                  case .tooLong = cleaningError else {
                return XCTFail("Expected tooLong, received \(error)")
            }
        }
    }

    func testCleanCopyWorkflowWritesOnlyCleanedContent() throws {
        var clipboardValue: String?

        let output = try NothungCleanCopyWorkflow.run(
            "https://example.com/story?utm_source=share&id=42#result"
        ) { clipboardValue = $0 }

        XCTAssertEqual(
            clipboardValue,
            "https://example.com/story?id=42#result"
        )
        XCTAssertEqual(clipboardValue, output.cleaned)
    }

    func testCleanCopyWorkflowDoesNotOverwriteClipboardOnFailure() {
        var clipboardValue = "existing clipboard value"

        XCTAssertThrowsError(
            try NothungCleanCopyWorkflow.run("not a URL") {
                clipboardValue = $0
            }
        )
        XCTAssertEqual(clipboardValue, "existing clipboard value")
    }

    func testSingleRedirectCandidateCanBeFoundInsideSharedText() throws {
        let output = try NothungCleaningService.clean(
            "哔哩哔哩分享 https://b23.tv/Pj3aF4G 请查收"
        )

        XCTAssertEqual(
            NothungCleaningService.singleWebURL(in: output)?.absoluteString,
            "https://b23.tv/Pj3aF4G"
        )
    }

    func testResolvedURLReplacesShortLinkInsideSharedTextAndIsRecleaned() throws {
        let output = try NothungCleaningService.clean(
            "视频 https://b23.tv/Pj3aF4G 请查收"
        )
        let resolved = try XCTUnwrap(
            URL(string: "https://www.bilibili.com/video/BV1yQu86HEkq/?utm_source=share")
        )

        let replaced = try NothungCleaningService.replacingSingleWebURL(
            in: output,
            with: resolved
        )

        XCTAssertEqual(
            replaced.cleaned,
            "视频 https://www.bilibili.com/video/BV1yQu86HEkq/ 请查收"
        )
        XCTAssertEqual(replaced.inputKind, .text)
    }

    func testExtensionLoaderPrefersSafariURLOverTextRepresentation() async throws {
        let url = try XCTUnwrap(
            URL(string: "https://example.com/article?utm_source=share&id=42")
        )
        let item = NSExtensionItem()
        item.attachments = [
            NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier),
            NSItemProvider(object: "Example Domain" as NSString),
        ]

        let value = try await ExtensionInputLoader.firstSharedText(from: [item])

        XCTAssertEqual(value, url.absoluteString)
    }

    func testExtensionLoaderDeduplicatesRepeatedURLRepresentations() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/path?id=1"))
        let item = NSExtensionItem()
        item.attachments = [
            NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier),
            NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier),
        ]

        let value = try await ExtensionInputLoader.firstSharedText(from: [item])

        XCTAssertEqual(value, url.absoluteString)
    }

    func testExtensionLoaderRejectsTwoDistinctSharedURLs() async throws {
        let first = try XCTUnwrap(URL(string: "https://one.example/"))
        let second = try XCTUnwrap(URL(string: "https://two.example/"))
        let item = NSExtensionItem()
        item.attachments = [
            NSItemProvider(item: first as NSURL, typeIdentifier: UTType.url.identifier),
            NSItemProvider(item: second as NSURL, typeIdentifier: UTType.url.identifier),
        ]

        do {
            _ = try await ExtensionInputLoader.firstSharedText(from: [item])
            XCTFail("Expected multiple logical inputs to be rejected")
        } catch let error as ExtensionInputLoader.LoadingError {
            XCTAssertEqual(error, .multipleInputs)
        }
    }

    func testExtensionLoaderAcceptsAbstractTextRepresentationUsedBySocialHosts() async throws {
        let shared = "查看动态 https://x.com/example/status/123?utm_source=share"
        let item = NSExtensionItem()
        item.attachments = [
            NSItemProvider(item: shared as NSString, typeIdentifier: UTType.text.identifier),
        ]

        let value = try await ExtensionInputLoader.firstSharedText(from: [item])

        XCTAssertEqual(value, shared)
    }

    func testExtensionLoaderPrefersLinkEmbeddedInAttributedContent() async throws {
        let url = try XCTUnwrap(URL(string: "https://x.com/example/status/123?utm_source=share"))
        let attributed = NSMutableAttributedString(string: "X 上的动态")
        attributed.addAttribute(
            .link,
            value: url,
            range: NSRange(location: 0, length: attributed.length)
        )
        let item = NSExtensionItem()
        item.attributedContentText = attributed

        let value = try await ExtensionInputLoader.firstSharedText(from: [item])

        XCTAssertEqual(value, url.absoluteString)
    }

    func testConfigurationAppliesParameterRulesBeforeGuardedRegexGroups() throws {
        var configuration = NothungRuleConfiguration.default
        configuration.useBuiltInTrackingRules = false
        configuration.parameterRules = [
            NothungParameterRule(
                title: "保留内容标识",
                host: "mobile.example",
                mode: .allowList,
                parameterNames: ["id"]
            ),
        ]
        configuration.regexRules = [
            NothungRegexRule(
                title: "统一域名",
                patterns: ["mobile\\.example", "\\?.*"],
                replacements: ["www.example", ""]
            ),
        ]

        let output = try NothungCleaningService.clean(
            "https://mobile.example/story?id=42&share=tracking",
            cleaner: configuration.makeCleaner()
        )

        XCTAssertEqual(output.cleaned, "https://www.example/story")
        XCTAssertEqual(output.removedFields.map(\.name), ["share"])
        XCTAssertEqual(output.appliedRegexRuleIdentifiers, ["统一域名"])
    }

    func testCompatibleBase64ParameterRuleCanBeImported() throws {
        let document = Data(
            #"{"a":"示例白名单","d":"tester","e":"video.example","f":0,"g":["id"]}"#.utf8
        ).base64EncodedString()

        let configuration = try NothungRuleStorage.importing(
            document,
            into: .default
        )

        let rule = try XCTUnwrap(configuration.parameterRules.last)
        XCTAssertEqual(rule.title, "示例白名单")
        XCTAssertEqual(rule.host, "video.example")
        XCTAssertEqual(rule.mode, .allowList)
        XCTAssertEqual(rule.parameterNames, ["id"])
        XCTAssertTrue(rule.source?.hasPrefix("tester · ") == true)
    }

    func testExportedConfigurationRoundTrips() throws {
        var configuration = NothungRuleConfiguration.default
        configuration.copyAfterCleaning = true
        configuration.redirectRules = [
            NothungRedirectRule(title: "短链", host: "short.example")
        ]

        let exported = try NothungRuleStorage.exportDocument(configuration)
        let decoded = try NothungRuleStorage.importing(exported, into: .default)

        XCTAssertEqual(decoded, configuration)
    }

    func testRedirectRulesRespectHostBoundaryAndSubdomainOption() throws {
        var configuration = NothungRuleConfiguration.default
        configuration.redirectRules = [
            NothungRedirectRule(
                title: "短链",
                host: "short.example",
                includesSubdomains: true
            )
        ]

        XCTAssertTrue(
            configuration.allowsRedirectExpansion(
                for: try XCTUnwrap(URL(string: "https://a.short.example/x"))
            )
        )
        XCTAssertFalse(
            configuration.allowsRedirectExpansion(
                for: try XCTUnwrap(URL(string: "https://notshort.example/x"))
            )
        )
    }
}
