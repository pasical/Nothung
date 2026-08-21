import Foundation
import NothungCore

struct NothungRuleConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 4

    var schemaVersion = Self.currentSchemaVersion
    var useBuiltInTrackingRules = true
    var automaticallyCaptureClipboard = false
    var cleanImmediatelyAfterPaste = false
    var copyAfterCleaning = false
    var restrictRedirectExpansionToRules = false
    var parameterRules: [NothungParameterRule] = []
    var regexRules: [NothungRegexRule] = []
    var redirectRules: [NothungRedirectRule] = []

    static let `default`: NothungRuleConfiguration = {
        var configuration = NothungRuleConfiguration()
        configuration.parameterRules = [
            .nothungYouTubeParameters,
            .nothungYouTubeShortLinkParameters,
        ]
        configuration.regexRules = [
            .nothungXTrackingCleanup,
            .nothungBilibiliVideoSharingCleanup,
        ]
        configuration.redirectRules = [
            .nothungBilibiliShortLink,
            .nothungYouTubeShortLink,
        ]
        return configuration
    }()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case useBuiltInTrackingRules
        case automaticallyCaptureClipboard
        case cleanImmediatelyAfterPaste
        case copyAfterCleaning
        case restrictRedirectExpansionToRules
        case parameterRules
        case regexRules
        case redirectRules
    }

    /// Decode fields individually so configurations written by an earlier
    /// schema remain readable when a preference is added. In particular,
    /// automatic clipboard capture is deliberately opt-in for existing users.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1
        useBuiltInTrackingRules = try container.decodeIfPresent(
            Bool.self,
            forKey: .useBuiltInTrackingRules
        ) ?? true
        automaticallyCaptureClipboard = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticallyCaptureClipboard
        ) ?? false
        cleanImmediatelyAfterPaste = try container.decodeIfPresent(
            Bool.self,
            forKey: .cleanImmediatelyAfterPaste
        ) ?? false
        copyAfterCleaning = try container.decodeIfPresent(
            Bool.self,
            forKey: .copyAfterCleaning
        ) ?? false
        restrictRedirectExpansionToRules = try container.decodeIfPresent(
            Bool.self,
            forKey: .restrictRedirectExpansionToRules
        ) ?? false
        parameterRules = try container.decodeIfPresent(
            [NothungParameterRule].self,
            forKey: .parameterRules
        ) ?? []
        regexRules = try container.decodeIfPresent(
            [NothungRegexRule].self,
            forKey: .regexRules
        ) ?? []
        redirectRules = try container.decodeIfPresent(
            [NothungRedirectRule].self,
            forKey: .redirectRules
        ) ?? []
    }

    func migratedToCurrentSchema() throws -> NothungRuleConfiguration {
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw NothungRuleConfigurationError.unsupportedSchema(schemaVersion)
        }

        var result = self
        if result.schemaVersion == 1 {
            if !result.regexRules.contains(where: { $0.id == NothungRegexRule.nothungXTrackingCleanup.id }) {
                result.regexRules.append(.nothungXTrackingCleanup)
            }
            if !result.redirectRules.contains(where: {
                $0.host.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "b23.tv"
            }) {
                result.redirectRules.append(.nothungBilibiliShortLink)
            }
            result.schemaVersion = 2
        }
        if result.schemaVersion == 2 {
            if !result.regexRules.contains(where: {
                $0.id == NothungRegexRule.nothungBilibiliVideoSharingCleanup.id
            }) {
                result.regexRules.append(.nothungBilibiliVideoSharingCleanup)
            }
            result.schemaVersion = 3
        }
        if result.schemaVersion == 3 {
            // Schema 3 never shipped YouTube defaults. Add each stable rule
            // once, without re-enabling or recreating any older built-in rule
            // the user disabled or deleted under that schema.
            for rule in NothungParameterRule.nothungYouTubeRules
            where !result.parameterRules.contains(where: { $0.id == rule.id }) {
                result.parameterRules.append(rule)
            }
            if !result.redirectRules.contains(where: {
                $0.id == NothungRedirectRule.nothungYouTubeShortLink.id
            }) {
                result.redirectRules.append(.nothungYouTubeShortLink)
            }
            result.schemaVersion = Self.currentSchemaVersion
        }

        _ = try result.makeCleaner()
        return result
    }

    func makeCleaner() throws -> NothungCleaner {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw NothungRuleConfigurationError.unsupportedSchema(schemaVersion)
        }

        let enabledParameterRules = parameterRules.filter(\.isEnabled)
        guard enabledParameterRules.count <= NothungCleaner.maximumOrderedParameterRuleCount else {
            throw NothungRuleConfigurationError.tooManyParameterRules
        }
        let orderedParameterRules = try enabledParameterRules.map { rule in
            let host = try Self.validatedHost(rule.host)
            return OrderedQueryRule(
                identifier: rule.id.uuidString,
                host: host,
                includesSubdomains: rule.includesSubdomains,
                mode: rule.mode.coreMode,
                parameterNames: Self.normalizedLines(rule.parameterNames)
            )
        }

        let enabledRegexRules = regexRules.filter(\.isEnabled)
        let totalRegexSteps = enabledRegexRules.reduce(0) { $0 + $1.patterns.count }
        guard totalRegexSteps <= NothungCleaner.maximumRegexRuleCount else {
            throw NothungRuleConfigurationError.tooManyRegexSteps
        }
        let regexGroups = try enabledRegexRules.map { rule in
            let patterns = rule.patterns.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !patterns.isEmpty else {
                throw NothungRuleConfigurationError.regexHasNoSteps(rule.title)
            }
            guard patterns.count == rule.replacements.count else {
                throw NothungRuleConfigurationError.regexLineCountMismatch(rule.title)
            }

            let steps = try zip(patterns, rule.replacements).enumerated().map {
                index, pair in
                guard !pair.0.isEmpty else {
                    throw NothungRuleConfigurationError.emptyRegexPattern(rule.title)
                }
                return try OrderedRegexRule(
                    identifier: "\(rule.id.uuidString)-\(index)",
                    pattern: pair.0,
                    replacementTemplate: pair.1,
                    caseInsensitive: rule.caseInsensitive
                )
            }
            return OrderedRegexRuleGroup(
                identifier: rule.title.nonEmpty ?? rule.id.uuidString,
                steps: steps
            )
        }

        return NothungCleaner(
            parameterPolicy: QueryParameterPolicy(
                blockedRules: useBuiltInTrackingRules ? TrackingRule.defaults : []
            ),
            orderedParameterRules: orderedParameterRules,
            regexRules: [],
            regexRuleGroups: regexGroups
        )
    }

    func allowsRedirectExpansion(for url: URL) -> Bool {
        guard let candidateHost = url.host else { return false }
        return redirectRules.lazy.filter(\.isEnabled).contains { rule in
            guard let host = try? Self.validatedHost(rule.host) else { return false }
            let candidate = Self.normalizedHost(candidateHost)
            let expected = Self.normalizedHost(host)
            return candidate == expected
                || (rule.includesSubdomains && candidate.hasSuffix(".\(expected)"))
        }
    }

    func isDefaultFeatureEnabled(_ feature: NothungDefaultFeature) -> Bool {
        switch feature {
        case .generalTrackingParameters:
            return useBuiltInTrackingRules
        case .xTwitterParameters:
            return regexRules.contains {
                $0.id == NothungRegexRule.nothungXTrackingCleanup.id && $0.isEnabled
            }
        case .bilibiliParameters:
            return regexRules.contains {
                $0.id == NothungRegexRule.nothungBilibiliVideoSharingCleanup.id
                    && $0.isEnabled
            }
        case .bilibiliShortLinkExpansion:
            return redirectRules.contains {
                $0.id == NothungRedirectRule.nothungBilibiliShortLink.id && $0.isEnabled
            }
        case .youtubeParameters:
            return NothungParameterRule.nothungYouTubeRules.allSatisfy { defaultRule in
                parameterRules.contains {
                    $0.id == defaultRule.id && $0.isEnabled
                }
            }
        case .youtubeShortLinkExpansion:
            return redirectRules.contains {
                $0.id == NothungRedirectRule.nothungYouTubeShortLink.id && $0.isEnabled
            }
        }
    }

    mutating func setDefaultFeature(
        _ feature: NothungDefaultFeature,
        isEnabled: Bool
    ) {
        switch feature {
        case .generalTrackingParameters:
            useBuiltInTrackingRules = isEnabled
        case .xTwitterParameters:
            setRegexRule(.nothungXTrackingCleanup, isEnabled: isEnabled)
        case .bilibiliParameters:
            setRegexRule(.nothungBilibiliVideoSharingCleanup, isEnabled: isEnabled)
        case .bilibiliShortLinkExpansion:
            setRedirectRule(.nothungBilibiliShortLink, isEnabled: isEnabled)
        case .youtubeParameters:
            for rule in NothungParameterRule.nothungYouTubeRules {
                setParameterRule(rule, isEnabled: isEnabled)
            }
        case .youtubeShortLinkExpansion:
            setRedirectRule(.nothungYouTubeShortLink, isEnabled: isEnabled)
        }
    }

    private mutating func setParameterRule(
        _ defaultRule: NothungParameterRule,
        isEnabled: Bool
    ) {
        if let index = parameterRules.firstIndex(where: { $0.id == defaultRule.id }) {
            parameterRules[index].isEnabled = isEnabled
        } else if isEnabled {
            parameterRules.append(defaultRule)
        }
    }

    private mutating func setRegexRule(
        _ defaultRule: NothungRegexRule,
        isEnabled: Bool
    ) {
        if let index = regexRules.firstIndex(where: { $0.id == defaultRule.id }) {
            regexRules[index].isEnabled = isEnabled
        } else if isEnabled {
            regexRules.append(defaultRule)
        }
    }

    private mutating func setRedirectRule(
        _ defaultRule: NothungRedirectRule,
        isEnabled: Bool
    ) {
        if let index = redirectRules.firstIndex(where: { $0.id == defaultRule.id }) {
            redirectRules[index].isEnabled = isEnabled
        } else if isEnabled {
            redirectRules.append(defaultRule)
        }
    }

    private static func validatedHost(_ rawValue: String) throws -> String {
        let value = normalizedHost(rawValue)
        guard !value.isEmpty,
              !value.contains("/"),
              !value.contains(":"),
              let components = URLComponents(string: "https://\(value)"),
              components.host != nil else {
            throw NothungRuleConfigurationError.invalidHost(rawValue)
        }
        return value
    }

    private static func normalizedHost(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while result.last == "." { result.removeLast() }
        return result
    }

    private static func normalizedLines(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum NothungDefaultFeature: String, CaseIterable, Identifiable, Sendable {
    case generalTrackingParameters
    case xTwitterParameters
    case bilibiliParameters
    case bilibiliShortLinkExpansion
    case youtubeParameters
    case youtubeShortLinkExpansion

    var id: Self { self }

    var title: String {
        switch self {
        case .generalTrackingParameters:
            return String(localized: "通用追踪参数清理")
        case .xTwitterParameters:
            return String(localized: "X / Twitter 多余参数清理")
        case .bilibiliParameters:
            return String(localized: "哔哩哔哩多余参数清理")
        case .bilibiliShortLinkExpansion:
            return String(localized: "哔哩哔哩短链展开")
        case .youtubeParameters:
            return String(localized: "YouTube 多余参数清理")
        case .youtubeShortLinkExpansion:
            return String(localized: "YouTube 短链展开")
        }
    }

    var explanation: String {
        switch self {
        case .generalTrackingParameters:
            return String(localized: "移除 UTM 和常见广告归因参数。")
        case .xTwitterParameters:
            return String(localized: "规范 X / Twitter 域名并移除分享跟踪参数。")
        case .bilibiliParameters:
            return String(localized: "规范哔哩哔哩视频链接并移除分享参数。")
        case .bilibiliShortLinkExpansion:
            return String(localized: "联网跟随 b23.tv 重定向，再清理最终链接。")
        case .youtubeParameters:
            return String(localized: "移除 YouTube 分享跟踪参数，保留视频、时间点与播放列表信息。")
        case .youtubeShortLinkExpansion:
            return String(localized: "联网跟随 youtu.be 重定向，再清理最终链接。")
        }
    }

    var requiresNetwork: Bool {
        switch self {
        case .bilibiliShortLinkExpansion, .youtubeShortLinkExpansion:
            return true
        case .generalTrackingParameters,
             .xTwitterParameters,
             .bilibiliParameters,
             .youtubeParameters:
            return false
        }
    }
}

struct NothungParameterRule: Identifiable, Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case allowList
        case blockList

        var title: String {
            switch self {
            case .allowList: return String(localized: "白名单")
            case .blockList: return String(localized: "黑名单")
            }
        }

        fileprivate var coreMode: OrderedQueryRule.Mode {
            switch self {
            case .allowList: return .allowList
            case .blockList: return .blockList
            }
        }
    }

    var id = UUID()
    var title = String(localized: "新参数规则")
    var host = ""
    var includesSubdomains = false
    var mode: Mode = .blockList
    var parameterNames: [String] = []
    var isEnabled = true
    var source: String? = nil

    /// YouTube uses both a full hostname and a path-based short hostname. Keep
    /// two host-scoped rules so the same conservative parameter list applies
    /// locally before any optional redirect expansion.
    static let nothungYouTubeParameters = NothungParameterRule(
        id: UUID(uuidString: "A24C7FC2-61D6-4EE9-A8BC-9AC7911BE004")!,
        title: String(localized: "YouTube 视频分享去参数"),
        host: "youtube.com",
        includesSubdomains: true,
        mode: .blockList,
        parameterNames: nothungYouTubeTrackingParameterNames,
        source: String(localized: "Nothung · 内置规则")
    )

    static let nothungYouTubeShortLinkParameters = NothungParameterRule(
        id: UUID(uuidString: "A24C7FC2-61D6-4EE9-A8BC-9AC7911BE005")!,
        title: String(localized: "YouTube 短链分享去参数"),
        host: "youtu.be",
        mode: .blockList,
        parameterNames: nothungYouTubeTrackingParameterNames,
        source: String(localized: "Nothung · 内置规则")
    )

    static let nothungYouTubeRules: [NothungParameterRule] = [
        .nothungYouTubeParameters,
        .nothungYouTubeShortLinkParameters,
    ]

    private static let nothungYouTubeTrackingParameterNames = [
        "si",
        "feature",
        "pp",
        "app",
        "embeds_referring_euri",
        "embeds_referring_origin",
        "source_ve_path",
    ]
}

struct NothungRegexRule: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title = String(localized: "新正则规则")
    var patterns: [String] = [""]
    var replacements: [String] = [""]
    var caseInsensitive = false
    var isEnabled = true
    var source: String? = nil

    static let nothungXTrackingCleanup = NothungRegexRule(
        id: UUID(uuidString: "A24C7FC2-61D6-4EE9-A8BC-9AC7911BE001")!,
        title: String(localized: "X / Twitter 去除跟踪参数"),
        patterns: [
            "(http|https)://(www\\.)?(twitter|x)\\.com",
            "\\?.*",
        ],
        replacements: [
            "https://x.com",
            "",
        ],
        source: String(localized: "Nothung · 内置规则")
    )

    static let nothungBilibiliVideoSharingCleanup = NothungRegexRule(
        id: UUID(uuidString: "A24C7FC2-61D6-4EE9-A8BC-9AC7911BE003")!,
        title: String(localized: "哔哩哔哩视频分享去参数"),
        patterns: [
            "(http|https)://(m\\.|www\\.)?bilibili\\.com/video",
            "\\?[^#]*",
        ],
        replacements: [
            "https://www.bilibili.com/video",
            "",
        ],
        source: String(localized: "Nothung · 内置规则")
    )
}

struct NothungRedirectRule: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title = String(localized: "新重定向域名")
    var host = ""
    var includesSubdomains = false
    var isEnabled = true
    var source: String? = nil

    static let nothungBilibiliShortLink = NothungRedirectRule(
        id: UUID(uuidString: "A24C7FC2-61D6-4EE9-A8BC-9AC7911BE002")!,
        title: String(localized: "哔哩哔哩短链"),
        host: "b23.tv",
        source: String(localized: "Nothung · 内置规则")
    )

    static let nothungYouTubeShortLink = NothungRedirectRule(
        id: UUID(uuidString: "A24C7FC2-61D6-4EE9-A8BC-9AC7911BE006")!,
        title: String(localized: "YouTube 短链"),
        host: "youtu.be",
        source: String(localized: "Nothung · 内置规则")
    )
}

enum NothungRuleConfigurationError: Error, LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case tooManyParameterRules
    case tooManyRegexSteps
    case invalidHost(String)
    case regexHasNoSteps(String)
    case regexLineCountMismatch(String)
    case emptyRegexPattern(String)
    case invalidDocument
    case unsupportedImportedRule

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            return String(localized: "规则文件版本比当前 App 更新，暂时无法读取。")
        case .tooManyParameterRules:
            return String(localized: "启用的参数规则不能超过 64 条。")
        case .tooManyRegexSteps:
            return String(localized: "启用的正则替换步骤合计不能超过 64 行。")
        case .invalidHost(let host):
            return String(localized: "域名“\(host)”无效；只填写域名，不要包含协议或路径。")
        case .regexHasNoSteps(let title):
            return String(localized: "正则规则“\(title)”至少需要一行正则。")
        case .regexLineCountMismatch(let title):
            return String(localized: "正则规则“\(title)”的正则与替换内容行数必须一致。")
        case .emptyRegexPattern(let title):
            return String(localized: "正则规则“\(title)”包含空白正则行。")
        case .invalidDocument:
            return String(localized: "没有识别到有效的 Nothung 配置或兼容规则。")
        case .unsupportedImportedRule:
            return String(localized: "这条兼容规则的字段组合暂不受支持。")
        }
    }
}

enum NothungRuleStorage {
    static let appGroupIdentifier = "group.dev.nothung.shared"
    private static let configurationKey = "ruleConfiguration.v1"

    static func load(defaults: UserDefaults = sharedDefaults) -> NothungRuleConfiguration {
        guard let data = defaults.data(forKey: configurationKey),
              let decoded = try? JSONDecoder().decode(
                  NothungRuleConfiguration.self,
                  from: data
              ),
              let migrated = try? decoded.migratedToCurrentSchema() else {
            return .default
        }
        let configuration = localizingBuiltInMetadata(in: migrated)
        if configuration != decoded,
           let migratedData = try? JSONEncoder().encode(configuration) {
            defaults.set(migratedData, forKey: configurationKey)
        }
        return configuration
    }

    /// Keeps built-in metadata aligned with the current app language while
    /// preserving any title the user has customized.
    private static func localizingBuiltInMetadata(
        in configuration: NothungRuleConfiguration
    ) -> NothungRuleConfiguration {
        var result = configuration
        let builtInSources: Set<String> = [
            "Nothung · 内置规则",
            "Nothung · Built-in rule",
        ]

        let regexTitles: [UUID: (Set<String>, NothungRegexRule)] = [
            NothungRegexRule.nothungXTrackingCleanup.id: (
                [
                    "X / Twitter 去除跟踪参数",
                    "Remove X / Twitter tracking parameters",
                ],
                .nothungXTrackingCleanup
            ),
            NothungRegexRule.nothungBilibiliVideoSharingCleanup.id: (
                [
                    "哔哩哔哩视频分享去参数",
                    "Remove parameters from Bilibili video shares",
                ],
                .nothungBilibiliVideoSharingCleanup
            ),
        ]

        let parameterTitles: [UUID: (Set<String>, NothungParameterRule)] = [
            NothungParameterRule.nothungYouTubeParameters.id: (
                [
                    "YouTube 视频分享去参数",
                    "Remove parameters from YouTube video shares",
                    "Remove Sharing Parameters from YouTube Video Links",
                ],
                .nothungYouTubeParameters
            ),
            NothungParameterRule.nothungYouTubeShortLinkParameters.id: (
                [
                    "YouTube 短链分享去参数",
                    "Remove parameters from YouTube short links",
                    "Remove Sharing Parameters from YouTube Short Links",
                ],
                .nothungYouTubeShortLinkParameters
            ),
        ]

        for index in result.parameterRules.indices {
            guard let (knownTitles, localizedRule) = parameterTitles[
                result.parameterRules[index].id
            ] else { continue }
            if knownTitles.contains(result.parameterRules[index].title) {
                result.parameterRules[index].title = localizedRule.title
            }
            if let source = result.parameterRules[index].source,
               builtInSources.contains(source) {
                result.parameterRules[index].source = localizedRule.source
            }
        }

        for index in result.regexRules.indices {
            guard let (knownTitles, localizedRule) = regexTitles[
                result.regexRules[index].id
            ] else { continue }
            if knownTitles.contains(result.regexRules[index].title) {
                result.regexRules[index].title = localizedRule.title
            }
            if let source = result.regexRules[index].source,
               builtInSources.contains(source) {
                result.regexRules[index].source = localizedRule.source
            }
        }

        let redirectTitles: [UUID: (Set<String>, NothungRedirectRule)] = [
            NothungRedirectRule.nothungBilibiliShortLink.id: (
                [
                    "哔哩哔哩短链",
                    "Bilibili short link",
                ],
                .nothungBilibiliShortLink
            ),
            NothungRedirectRule.nothungYouTubeShortLink.id: (
                [
                    "YouTube 短链",
                    "YouTube short link",
                    "YouTube Short Links",
                ],
                .nothungYouTubeShortLink
            ),
        ]

        for index in result.redirectRules.indices {
            guard let (knownTitles, localizedRule) = redirectTitles[
                result.redirectRules[index].id
            ] else { continue }
            if knownTitles.contains(result.redirectRules[index].title) {
                result.redirectRules[index].title = localizedRule.title
            }
            if let source = result.redirectRules[index].source,
               builtInSources.contains(source) {
                result.redirectRules[index].source = localizedRule.source
            }
        }

        return result
    }

    static func save(
        _ configuration: NothungRuleConfiguration,
        defaults: UserDefaults = sharedDefaults
    ) throws {
        _ = try configuration.makeCleaner()
        let data = try JSONEncoder().encode(configuration)
        defaults.set(data, forKey: configurationKey)
    }

    static func exportDocument(_ configuration: NothungRuleConfiguration) throws -> String {
        _ = try configuration.makeCleaner()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(configuration), as: UTF8.self)
    }

    static func importing(
        _ document: String,
        into current: NothungRuleConfiguration
    ) throws -> NothungRuleConfiguration {
        let trimmed = document.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NothungRuleConfigurationError.invalidDocument }

        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(
               NothungRuleConfiguration.self,
               from: data
           ) {
            return try decoded.migratedToCurrentSchema()
        }

        let candidate = extractedBase64(from: trimmed)
        guard let data = Data(base64Encoded: candidate),
              let legacy = try? JSONDecoder().decode(CompatibleRule.self, from: data) else {
            throw NothungRuleConfigurationError.invalidDocument
        }

        var result = current
        let source = [legacy.author, String(localized: "用户导入的兼容规则")]
            .compactMap { $0?.nonEmpty }
            .joined(separator: " · ")

        if let patterns = legacy.patterns, let replacements = legacy.replacements {
            guard !patterns.isEmpty, patterns.count == replacements.count else {
                throw NothungRuleConfigurationError.regexLineCountMismatch(
                    legacy.title ?? String(localized: "导入规则")
                )
            }
            result.regexRules.append(
                NothungRegexRule(
                    title: legacy.title?.nonEmpty ?? String(localized: "导入的正则规则"),
                    patterns: patterns,
                    replacements: replacements,
                    source: source.nonEmpty
                )
            )
        } else if let host = legacy.host, let mode = legacy.mode {
            result.parameterRules.append(
                NothungParameterRule(
                    title: legacy.title?.nonEmpty ?? String(localized: "导入的参数规则"),
                    host: host,
                    mode: mode == 0 ? .allowList : .blockList,
                    parameterNames: legacy.parameters ?? [],
                    source: source.nonEmpty
                )
            )
        } else if let host = legacy.host {
            result.redirectRules.append(
                NothungRedirectRule(
                    title: legacy.title?.nonEmpty ?? String(localized: "导入的重定向域名"),
                    host: host,
                    source: source.nonEmpty
                )
            )
        } else {
            throw NothungRuleConfigurationError.unsupportedImportedRule
        }

        _ = try result.makeCleaner()
        return result
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    private static func extractedBase64(from value: String) -> String {
        let unwrapped = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
            .removingPercentEncoding ?? value
        if Data(base64Encoded: unwrapped) != nil { return unwrapped }

        if let components = URLComponents(string: unwrapped) {
            for item in components.queryItems ?? []
            where ["data", "rule", "content"].contains(item.name.lowercased()) {
                if let candidate = item.value,
                   Data(base64Encoded: candidate) != nil {
                    return candidate
                }
            }
            for component in components.path.split(separator: "/").reversed() {
                let candidate = String(component)
                if Data(base64Encoded: candidate) != nil { return candidate }
            }
        }

        let expression = try? NSRegularExpression(
            pattern: "[A-Za-z0-9+/]{16,}={0,2}"
        )
        let range = NSRange(unwrapped.startIndex..<unwrapped.endIndex, in: unwrapped)
        let candidates = expression?.matches(in: unwrapped, range: range).compactMap {
            Range($0.range, in: unwrapped).map { String(unwrapped[$0]) }
        } ?? []
        return candidates
            .sorted { $0.count > $1.count }
            .first(where: { Data(base64Encoded: $0) != nil })
            ?? unwrapped
    }

    private struct CompatibleRule: Decodable {
        let title: String?
        let patterns: [String]?
        let replacements: [String]?
        let author: String?
        let host: String?
        let mode: Int?
        let parameters: [String]?

        enum CodingKeys: String, CodingKey {
            case title = "a"
            case patterns = "b"
            case replacements = "c"
            case author = "d"
            case host = "e"
            case mode = "f"
            case parameters = "g"
        }
    }
}

enum NothungConfiguredCleaner {
    static func current() -> NothungCleaner {
        (try? NothungRuleStorage.load().makeCleaner()) ?? NothungCleaner()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
