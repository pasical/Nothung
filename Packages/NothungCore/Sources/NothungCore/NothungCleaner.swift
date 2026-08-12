import Foundation

/// A query-parameter removal rule.
///
/// Parameter names and host names are matched case-insensitively. A host-scoped
/// rule can either match one host exactly or include its subdomains.
public struct TrackingRule: Sendable, Hashable {
    public enum NameMatch: Sendable, Hashable {
        case exact(String)
        case prefix(String)
    }

    public enum HostScope: Sendable, Hashable {
        case any
        case host(String, includesSubdomains: Bool)
    }

    public let nameMatch: NameMatch
    public let hostScope: HostScope

    public init(nameMatch: NameMatch, hostScope: HostScope = .any) {
        self.nameMatch = nameMatch
        self.hostScope = hostScope
    }

    public init(
        exactName: String,
        host: String? = nil,
        includesSubdomains: Bool = false
    ) {
        self.init(
            nameMatch: .exact(exactName),
            hostScope: host.map {
                .host($0, includesSubdomains: includesSubdomains)
            } ?? .any
        )
    }

    public init(
        prefix: String,
        host: String? = nil,
        includesSubdomains: Bool = false
    ) {
        self.init(
            nameMatch: .prefix(prefix),
            hostScope: host.map {
                .host($0, includesSubdomains: includesSubdomains)
            } ?? .any
        )
    }

    /// Conservative defaults limited to names that identify advertising or
    /// analytics attribution metadata, rather than content-bearing parameters.
    public static let defaults: [TrackingRule] = {
        let exactNames = [
            "_ga",
            "_gl",
            "_hsenc",
            "_hsmi",
            "dclid",
            "fbclid",
            "gbraid",
            "gclid",
            "li_fat_id",
            "mc_cid",
            "mc_eid",
            "mkt_tok",
            "msclkid",
            "srsltid",
            "ttclid",
            "twclid",
            "wbraid",
            "yclid",
        ]

        return [TrackingRule(prefix: "utm_")]
            + exactNames.map { TrackingRule(exactName: $0) }
    }()

    fileprivate func matches(parameterName: String, host: String) -> Bool {
        guard matches(host: host) else {
            return false
        }

        let candidate = parameterName.lowercased()
        switch nameMatch {
        case let .exact(name):
            return candidate == name.lowercased()
        case let .prefix(prefix):
            return candidate.hasPrefix(prefix.lowercased())
        }
    }

    private func matches(host candidateHost: String) -> Bool {
        switch hostScope {
        case .any:
            return true
        case let .host(ruleHost, includesSubdomains):
            let candidate = Self.normalized(host: candidateHost)
            let expected = Self.normalized(host: ruleHost)
            guard !expected.isEmpty else {
                return false
            }
            if candidate == expected {
                return true
            }
            return includesSubdomains && candidate.hasSuffix(".\(expected)")
        }
    }

    private static func normalized(host: String) -> String {
        var result = host.lowercased()
        while result.last == "." {
            result.removeLast()
        }
        return result
    }
}

/// Query-parameter policy used by ``NothungCleaner``.
///
/// A matching allow rule always wins over a matching block rule. This makes it
/// possible to keep a parameter that would otherwise be caught by a broad
/// prefix rule without weakening that rule for every host.
public struct QueryParameterPolicy: Sendable, Hashable {
    public let blockedRules: [TrackingRule]
    public let allowedRules: [TrackingRule]

    public init(
        blockedRules: [TrackingRule] = TrackingRule.defaults,
        allowedRules: [TrackingRule] = []
    ) {
        self.blockedRules = blockedRules
        self.allowedRules = allowedRules
    }

    fileprivate func shouldRemove(parameterName: String, host: String) -> Bool {
        guard blockedRules.contains(where: {
            $0.matches(parameterName: parameterName, host: host)
        }) else {
            return false
        }

        return !allowedRules.contains(where: {
            $0.matches(parameterName: parameterName, host: host)
        })
    }
}

/// One host-scoped query rule in an ordered parameter pipeline.
///
/// This models the same useful user-facing concepts as many link cleaners:
/// allow-list rules retain only the named parameters, while block-list rules
/// remove the named parameters. An empty name list removes every parameter in
/// either mode. Rules are applied sequentially before regular-expression rules.
public struct OrderedQueryRule: Sendable, Hashable {
    public enum Mode: String, Sendable, Hashable, Codable {
        case allowList
        case blockList
    }

    public let identifier: String
    public let host: String
    public let includesSubdomains: Bool
    public let mode: Mode
    public let parameterNames: [String]

    public init(
        identifier: String,
        host: String,
        includesSubdomains: Bool = false,
        mode: Mode,
        parameterNames: [String]
    ) {
        self.identifier = identifier
        self.host = host
        self.includesSubdomains = includesSubdomains
        self.mode = mode
        self.parameterNames = parameterNames
    }

    fileprivate func matches(host candidateHost: String) -> Bool {
        let candidate = Self.normalized(host: candidateHost)
        let expected = Self.normalized(host: host)
        guard !expected.isEmpty else { return false }
        return candidate == expected
            || (includesSubdomains && candidate.hasSuffix(".\(expected)"))
    }

    fileprivate func shouldRemove(parameterName: String) -> Bool {
        let names = Set(parameterNames.map { $0.lowercased() })
        guard !names.isEmpty else { return true }
        let matches = names.contains(parameterName.lowercased())
        switch mode {
        case .allowList:
            return !matches
        case .blockList:
            return matches
        }
    }

    private static func normalized(host: String) -> String {
        var result = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while result.last == "." { result.removeLast() }
        return result
    }
}

public enum OrderedRegexRuleError: Error, Sendable, Equatable {
    case emptyIdentifier
    case emptyPattern
    case patternTooLong
    case replacementTooLong
    case invalidPattern(String)
}

/// One validated regular-expression replacement in an ordered URL pipeline.
///
/// Rules are intentionally data: they cannot execute Swift, JavaScript, or
/// downloaded code. ``NothungCleaner`` applies them in array order and validates
/// the URL after every replacement.
public struct OrderedRegexRule: Sendable, Hashable {
    public static let maximumPatternLength = 512
    public static let maximumReplacementLength = 2_048

    public let identifier: String
    public let pattern: String
    public let replacementTemplate: String
    public let caseInsensitive: Bool

    public init(
        identifier: String,
        pattern: String,
        replacementTemplate: String,
        caseInsensitive: Bool = false
    ) throws {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OrderedRegexRuleError.emptyIdentifier
        }
        guard !pattern.isEmpty else {
            throw OrderedRegexRuleError.emptyPattern
        }
        guard pattern.count <= Self.maximumPatternLength else {
            throw OrderedRegexRuleError.patternTooLong
        }
        guard replacementTemplate.count <= Self.maximumReplacementLength else {
            throw OrderedRegexRuleError.replacementTooLong
        }

        do {
            _ = try NSRegularExpression(
                pattern: pattern,
                options: caseInsensitive ? [.caseInsensitive] : []
            )
        } catch {
            throw OrderedRegexRuleError.invalidPattern(identifier)
        }

        self.identifier = identifier
        self.pattern = pattern
        self.replacementTemplate = replacementTemplate
        self.caseInsensitive = caseInsensitive
    }

    fileprivate func replacingMatches(in value: String) throws -> (String, Int) {
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(
                pattern: pattern,
                options: caseInsensitive ? [.caseInsensitive] : []
            )
        } catch {
            throw OrderedRegexRuleError.invalidPattern(identifier)
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matchCount = expression.numberOfMatches(in: value, range: range)
        guard matchCount > 0 else {
            return (value, 0)
        }

        return (
            expression.stringByReplacingMatches(
                in: value,
                range: range,
                withTemplate: replacementTemplate
            ),
            matchCount
        )
    }
}

/// A guarded group of ordered regular-expression replacements.
///
/// The first step is both the activation guard and the first replacement. If it
/// has no match, the complete group is skipped. Once active, every step runs in
/// order and each intermediate value is validated by ``NothungCleaner``.
public struct OrderedRegexRuleGroup: Sendable, Hashable {
    public let identifier: String
    public let steps: [OrderedRegexRule]

    public init(identifier: String, steps: [OrderedRegexRule]) {
        self.identifier = identifier
        self.steps = steps
    }
}

/// A parameter removed from a URL.
///
/// `name` and `value` are percent-decoded for display. A parameter without an
/// equals sign has a `nil` value, while `name=` has an empty-string value.
public struct RemovedParameter: Sendable, Equatable {
    public let name: String
    public let value: String?

    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }
}

public struct URLCleaningResult: Sendable, Equatable {
    public let originalURL: URL
    public let cleanedURL: URL
    public let removedParameters: [RemovedParameter]
    public let appliedRegexRuleIdentifiers: [String]
    public let didChange: Bool

    public init(
        originalURL: URL,
        cleanedURL: URL,
        removedParameters: [RemovedParameter],
        appliedRegexRuleIdentifiers: [String] = [],
        didChange: Bool
    ) {
        self.originalURL = originalURL
        self.cleanedURL = cleanedURL
        self.removedParameters = removedParameters
        self.appliedRegexRuleIdentifiers = appliedRegexRuleIdentifiers
        self.didChange = didChange
    }
}

public struct TextCleaningResult: Sendable, Equatable {
    public let originalText: String
    public let cleanedText: String
    public let urlResults: [URLCleaningResult]
    public let didChange: Bool

    public init(
        originalText: String,
        cleanedText: String,
        urlResults: [URLCleaningResult],
        didChange: Bool
    ) {
        self.originalText = originalText
        self.cleanedText = cleanedText
        self.urlResults = urlResults
        self.didChange = didChange
    }
}

public enum NothungCleanerError: Error, Sendable, Equatable {
    case unsupportedScheme(String?)
    case missingHost
    case userInfoNotAllowed
    case couldNotConstructCleanedURL
    case tooManyParameterRules
    case tooManyRegexRules
    case regexInputTooLong
    case regexProducedUnsafeURL(String)
}

/// Removes known tracking query parameters without making network requests.
public struct NothungCleaner: Sendable {
    public static let maximumOrderedParameterRuleCount = 64
    public static let maximumRegexRuleCount = 64
    public static let maximumRegexInputLength = 16_384

    public let parameterPolicy: QueryParameterPolicy
    public let orderedParameterRules: [OrderedQueryRule]
    public let regexRules: [OrderedRegexRule]
    public let regexRuleGroups: [OrderedRegexRuleGroup]

    /// Compatibility view of the policy's blocked rules.
    public var rules: [TrackingRule] {
        parameterPolicy.blockedRules
    }

    public init(rules: [TrackingRule] = TrackingRule.defaults) {
        self.parameterPolicy = QueryParameterPolicy(blockedRules: rules)
        self.orderedParameterRules = []
        self.regexRules = []
        self.regexRuleGroups = []
    }

    public init(
        parameterPolicy: QueryParameterPolicy = QueryParameterPolicy(),
        orderedParameterRules: [OrderedQueryRule] = [],
        regexRules: [OrderedRegexRule],
        regexRuleGroups: [OrderedRegexRuleGroup] = []
    ) {
        self.parameterPolicy = parameterPolicy
        self.orderedParameterRules = orderedParameterRules
        self.regexRules = regexRules
        self.regexRuleGroups = regexRuleGroups
    }

    /// Cleans one absolute HTTP or HTTPS URL.
    ///
    /// Query components that are retained are copied byte-for-byte from the
    /// URL's `absoluteString`, so duplicate parameters, order, fragments, and
    /// percent-encoding are preserved.
    public func clean(url: URL) throws -> URLCleaningResult {
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw NothungCleanerError.unsupportedScheme(url.scheme)
        }
        guard url.user == nil, url.password == nil else {
            throw NothungCleanerError.userInfoNotAllowed
        }
        guard let host = url.host, !host.isEmpty else {
            throw NothungCleanerError.missingHost
        }

        let original = url.absoluteString
        let fragmentStart = original.firstIndex(of: "#") ?? original.endIndex
        guard let queryMark = original[..<fragmentStart].firstIndex(of: "?") else {
            return try finalizedResult(
                originalURL: url,
                parameterCleanedURL: url,
                removedParameters: []
            )
        }

        let queryStart = original.index(after: queryMark)
        let rawQuery = original[queryStart..<fragmentStart]
        guard !rawQuery.isEmpty else {
            return try finalizedResult(
                originalURL: url,
                parameterCleanedURL: url,
                removedParameters: []
            )
        }

        let components = rawQuery.split(
            separator: "&",
            omittingEmptySubsequences: false
        )
        guard orderedParameterRules.count <= Self.maximumOrderedParameterRuleCount else {
            throw NothungCleanerError.tooManyParameterRules
        }

        var retained = Array(components)
        var removed: [RemovedParameter] = []

        for rule in orderedParameterRules where rule.matches(host: host) {
            var next: [Substring] = []
            next.reserveCapacity(retained.count)
            for component in retained {
                let parsed = Self.parsedQueryComponent(component)
                if rule.shouldRemove(parameterName: parsed.name) {
                    removed.append(parsed.removedParameter)
                } else {
                    next.append(component)
                }
            }
            retained = next
        }

        var policyRetained: [Substring] = []
        policyRetained.reserveCapacity(retained.count)
        for component in retained {
            let parsed = Self.parsedQueryComponent(component)
            if parameterPolicy.shouldRemove(parameterName: parsed.name, host: host) {
                removed.append(parsed.removedParameter)
            } else {
                policyRetained.append(component)
            }
        }
        retained = policyRetained

        let parameterCleanedURL: URL
        if removed.isEmpty {
            parameterCleanedURL = url
        } else {
            var cleaned = String(original[..<queryMark])
            if !retained.isEmpty {
                cleaned.append("?")
                cleaned.append(retained.map(String.init).joined(separator: "&"))
            }
            cleaned.append(contentsOf: original[fragmentStart...])

            guard let rebuiltURL = URL(string: cleaned) else {
                throw NothungCleanerError.couldNotConstructCleanedURL
            }
            parameterCleanedURL = rebuiltURL
        }

        return try finalizedResult(
            originalURL: url,
            parameterCleanedURL: parameterCleanedURL,
            removedParameters: removed
        )
    }

    /// Cleans every explicit HTTP or HTTPS URL detected in a block of text.
    /// Other URL schemes and non-URL text are left untouched.
    public func clean(text: String) -> TextCleaningResult {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(
                  types: NSTextCheckingResult.CheckingType.link.rawValue
              ) else {
            return unchangedTextResult(for: text)
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let source = text as NSString
        var results: [(range: NSRange, result: URLCleaningResult)] = []

        detector.enumerateMatches(
            in: text,
            options: [],
            range: fullRange
        ) { match, _, _ in
            guard let match,
                  match.resultType == .link,
                  match.range.location != NSNotFound else {
                return
            }

            let rawURL = source.substring(with: match.range)
            guard Self.hasExplicitHTTPScheme(rawURL),
                  let url = URL(string: rawURL),
                  let result = try? clean(url: url) else {
                return
            }
            results.append((match.range, result))
        }

        guard !results.isEmpty else {
            return unchangedTextResult(for: text)
        }

        let output = NSMutableString(string: text)
        for item in results.reversed() where item.result.didChange {
            output.replaceCharacters(
                in: item.range,
                with: item.result.cleanedURL.absoluteString
            )
        }

        let cleanedText = output as String
        return TextCleaningResult(
            originalText: text,
            cleanedText: cleanedText,
            urlResults: results.map(\.result),
            didChange: cleanedText != text
        )
    }

    private func finalizedResult(
        originalURL: URL,
        parameterCleanedURL: URL,
        removedParameters: [RemovedParameter]
    ) throws -> URLCleaningResult {
        let regexResult = try applyRegexRules(to: parameterCleanedURL)
        return URLCleaningResult(
            originalURL: originalURL,
            cleanedURL: regexResult.url,
            removedParameters: removedParameters,
            appliedRegexRuleIdentifiers: regexResult.appliedIdentifiers,
            didChange: regexResult.url.absoluteString != originalURL.absoluteString
        )
    }

    private func applyRegexRules(
        to url: URL
    ) throws -> (url: URL, appliedIdentifiers: [String]) {
        guard !regexRules.isEmpty || !regexRuleGroups.isEmpty else {
            return (url, [])
        }
        let regexStepCount = regexRules.count
            + regexRuleGroups.reduce(0) { $0 + $1.steps.count }
        guard regexStepCount <= Self.maximumRegexRuleCount else {
            throw NothungCleanerError.tooManyRegexRules
        }

        var current = url.absoluteString
        guard current.count <= Self.maximumRegexInputLength else {
            throw NothungCleanerError.regexInputTooLong
        }

        var applied: [String] = []
        for rule in regexRules {
            let replacement = try rule.replacingMatches(in: current)
            guard replacement.1 > 0 else {
                continue
            }
            current = try validatedRegexOutput(
                replacement.0,
                identifier: rule.identifier
            )
            applied.append(rule.identifier)
        }

        for group in regexRuleGroups {
            guard let first = group.steps.first else { continue }
            let firstReplacement = try first.replacingMatches(in: current)
            guard firstReplacement.1 > 0 else { continue }

            current = try validatedRegexOutput(
                firstReplacement.0,
                identifier: group.identifier
            )
            for step in group.steps.dropFirst() {
                let replacement = try step.replacingMatches(in: current)
                guard replacement.1 > 0 else { continue }
                current = try validatedRegexOutput(
                    replacement.0,
                    identifier: group.identifier
                )
            }
            applied.append(group.identifier)
        }

        guard let result = URL(string: current) else {
            throw NothungCleanerError.couldNotConstructCleanedURL
        }
        return (result, applied)
    }

    private func validatedRegexOutput(
        _ value: String,
        identifier: String
    ) throws -> String {
        guard value.count <= Self.maximumRegexInputLength,
              let candidate = URL(string: value),
              let scheme = candidate.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              candidate.user == nil,
              candidate.password == nil,
              let host = candidate.host,
              !host.isEmpty else {
            throw NothungCleanerError.regexProducedUnsafeURL(identifier)
        }
        return candidate.absoluteString
    }

    private func unchangedTextResult(for text: String) -> TextCleaningResult {
        TextCleaningResult(
            originalText: text,
            cleanedText: text,
            urlResults: [],
            didChange: false
        )
    }

    private static func percentDecoded(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    private static func parsedQueryComponent(
        _ component: Substring
    ) -> (name: String, removedParameter: RemovedParameter) {
        let equals = component.firstIndex(of: "=")
        let rawName = equals.map { component[..<$0] } ?? component[...]
        let rawValue = equals.map { component[component.index(after: $0)...] }
        let name = percentDecoded(String(rawName))
        return (
            name,
            RemovedParameter(
                name: name,
                value: rawValue.map { percentDecoded(String($0)) }
            )
        )
    }

    private static func hasExplicitHTTPScheme(_ value: String) -> Bool {
        let prefix = value.prefix(8).lowercased()
        return prefix.hasPrefix("http://") || prefix.hasPrefix("https://")
    }
}
