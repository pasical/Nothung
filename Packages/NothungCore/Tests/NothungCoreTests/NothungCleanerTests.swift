import Foundation
import Testing
@testable import NothungCore

@Suite("NothungCleaner")
struct NothungCleanerTests {
    private let cleaner = NothungCleaner()

    @Test
    func removesDefaultUTMPrefixAndReportsDecodedValues() throws {
        let result = try clean("https://example.com/story?id=42&utm_source=news&utm_medium=email")

        #expect(result.cleanedURL.absoluteString == "https://example.com/story?id=42")
        #expect(
            result.removedParameters == [
                RemovedParameter(name: "utm_source", value: "news"),
                RemovedParameter(name: "utm_medium", value: "email"),
            ]
        )
        #expect(result.didChange)
    }

    @Test
    func removesDefaultExactNames() throws {
        let result = try clean("https://example.com/?fbclid=facebook&gclid=google&article=7")

        #expect(result.cleanedURL.absoluteString == "https://example.com/?article=7")
        #expect(result.removedParameters.map(\.name) == ["fbclid", "gclid"])
    }

    @Test
    func preservesSafeParametersAndTheirOrder() throws {
        let input = "https://example.com/search?z=last&a=first&query=swift"
        let result = try clean(input)

        #expect(result.cleanedURL.absoluteString == input)
        #expect(result.originalURL == result.cleanedURL)
        #expect(result.removedParameters.isEmpty)
        #expect(!result.didChange)
    }

    @Test
    func preservesDuplicateSafeParametersAndRemovesDuplicateTrackers() throws {
        let result = try clean("https://example.com/?tag=one&utm_source=a&tag=two&utm_source=b&tag=three")

        #expect(result.cleanedURL.absoluteString == "https://example.com/?tag=one&tag=two&tag=three")
        #expect(result.removedParameters.map(\.value) == ["a", "b"])
    }

    @Test
    func preservesFragmentExactly() throws {
        let result = try clean("https://example.com/path?keep=1&utm_source=x#section%202?still-fragment")

        #expect(
            result.cleanedURL.absoluteString
                == "https://example.com/path?keep=1#section%202?still-fragment"
        )
    }

    @Test
    func preservesPercentEncodedAmpersandAndEquals() throws {
        let result = try clean("https://example.com/?payload=a%26b%3Dc&utm_source=x#frag%3D1")

        #expect(
            result.cleanedURL.absoluteString
                == "https://example.com/?payload=a%26b%3Dc#frag%3D1"
        )
    }

    @Test
    func encodedParameterNameMatchesAfterPercentDecoding() throws {
        let result = try clean("https://example.com/?u%74m_source=mail&keep=%2Fvalue")

        #expect(result.cleanedURL.absoluteString == "https://example.com/?keep=%2Fvalue")
        #expect(
            result.removedParameters
                == [RemovedParameter(name: "utm_source", value: "mail")]
        )
    }

    @Test
    func plusSignsAreNotConvertedToSpaces() throws {
        let result = try clean("https://example.com/?q=a+b&utm_source=c+d")

        #expect(result.cleanedURL.absoluteString == "https://example.com/?q=a+b")
        #expect(result.removedParameters.first?.value == "c+d")
    }

    @Test
    func emptyAndMissingValuesRemainDistinctInReport() throws {
        let result = try clean("https://example.com/?utm_source=&gclid&keep=")

        #expect(result.cleanedURL.absoluteString == "https://example.com/?keep=")
        #expect(
            result.removedParameters == [
                RemovedParameter(name: "utm_source", value: ""),
                RemovedParameter(name: "gclid", value: nil),
            ]
        )
    }

    @Test
    func allRemovedParametersDropQueryDelimiterButKeepFragment() throws {
        let result = try clean("https://example.com/path?utm_source=x&fbclid=y#anchor")

        #expect(result.cleanedURL.absoluteString == "https://example.com/path#anchor")
    }

    @Test
    func noQueryIsUnchanged() throws {
        let input = "https://example.com/path#anchor"
        let result = try clean(input)

        #expect(result.cleanedURL.absoluteString == input)
        #expect(!result.didChange)
    }

    @Test
    func emptyQueryIsUnchanged() throws {
        let input = "https://example.com/path?#anchor"
        let result = try clean(input)

        #expect(result.cleanedURL.absoluteString == input)
        #expect(!result.didChange)
    }

    @Test
    func httpAndCaseInsensitiveParameterNamesAreAccepted() throws {
        let result = try clean("HTTP://example.com/path?UTM_Source=x&Keep=1")

        #expect(result.cleanedURL.absoluteString == "HTTP://example.com/path?Keep=1")
        #expect(result.removedParameters.first?.name == "UTM_Source")
    }

    @Test
    func nonHTTPURLThrows() throws {
        let ftpURL = try makeURL("ftp://example.com/?utm_source=x")
        let fileURL = try makeURL("file:///tmp/test?utm_source=x")

        #expect(throws: NothungCleanerError.unsupportedScheme("ftp")) {
            try cleaner.clean(url: ftpURL)
        }
        #expect(throws: NothungCleanerError.unsupportedScheme("file")) {
            try cleaner.clean(url: fileURL)
        }
    }

    @Test
    func httpURLWithoutHostThrows() throws {
        let url = try makeURL("http:/path?utm_source=x")

        #expect(throws: NothungCleanerError.missingHost) {
            try cleaner.clean(url: url)
        }
    }

    @Test
    func userInfoIsRejected() throws {
        let userOnly = try makeURL("https://user@example.com/path?utm_source=x")
        let password = try makeURL("https://user:password@example.com/path?utm_source=x")

        #expect(throws: NothungCleanerError.userInfoNotAllowed) {
            try cleaner.clean(url: userOnly)
        }
        #expect(throws: NothungCleanerError.userInfoNotAllowed) {
            try cleaner.clean(url: password)
        }
    }

    @Test
    func ipv6HostIsAcceptedAndPreserved() throws {
        let result = try clean("https://[2001:db8::1]/path?utm_source=x&a=1")

        #expect(result.cleanedURL.absoluteString == "https://[2001:db8::1]/path?a=1")
    }

    @Test
    func idnHostIsAccepted() throws {
        let original = try makeURL("https://例え.テスト/path?utm_source=x&keep=1#場所")
        let expected = try makeURL("https://例え.テスト/path?keep=1#場所")
        let result = try cleaner.clean(url: original)

        #expect(result.cleanedURL.absoluteString == expected.absoluteString)
        #expect(result.didChange)
    }

    @Test
    func veryLongRetainedValueIsNotTruncated() throws {
        let value = String(repeating: "abc%26def%3D", count: 10_000)
        let input = "https://example.com/?payload=\(value)&utm_source=x"
        let expected = "https://example.com/?payload=\(value)"
        let result = try clean(input)

        #expect(result.cleanedURL.absoluteString == expected)
        #expect(result.removedParameters.count == 1)
    }

    @Test
    func customGlobalExactRule() throws {
        let custom = NothungCleaner(rules: [TrackingRule(exactName: "campaign-id")])
        let url = try makeURL("https://example.com/?campaign-id=1&keep=2")
        let result = try custom.clean(url: url)

        #expect(result.cleanedURL.absoluteString == "https://example.com/?keep=2")
    }

    @Test
    func customGlobalPrefixRule() throws {
        let custom = NothungCleaner(rules: [TrackingRule(prefix: "track_")])
        let url = try makeURL("https://example.com/?track_one=1&TRACK_TWO=2&keep=3")
        let result = try custom.clean(url: url)

        #expect(result.cleanedURL.absoluteString == "https://example.com/?keep=3")
    }

    @Test
    func hostScopedRuleMatchesHostCaseInsensitively() throws {
        let custom = NothungCleaner(
            rules: [TrackingRule(exactName: "share_id", host: "EXAMPLE.COM")]
        )
        let matching = try makeURL("https://example.com/?share_id=1&keep=2")
        let other = try makeURL("https://other.example/?share_id=1&keep=2")

        #expect(
            try custom.clean(url: matching).cleanedURL.absoluteString
                == "https://example.com/?keep=2"
        )
        #expect(try !custom.clean(url: other).didChange)
    }

    @Test
    func hostScopedRuleDoesNotMatchSubdomainByDefault() throws {
        let custom = NothungCleaner(
            rules: [TrackingRule(exactName: "share_id", host: "example.com")]
        )
        let url = try makeURL("https://news.example.com/?share_id=1")

        #expect(try !custom.clean(url: url).didChange)
    }

    @Test
    func hostScopedRuleCanIncludeSubdomains() throws {
        let custom = NothungCleaner(
            rules: [
                TrackingRule(
                    exactName: "share_id",
                    host: "example.com",
                    includesSubdomains: true
                ),
            ]
        )
        let url = try makeURL("https://deep.news.example.com/?share_id=1&keep=2")

        #expect(
            try custom.clean(url: url).cleanedURL.absoluteString
                == "https://deep.news.example.com/?keep=2"
        )
    }

    @Test
    func subdomainMatchingUsesLabelBoundary() throws {
        let custom = NothungCleaner(
            rules: [
                TrackingRule(
                    exactName: "share_id",
                    host: "example.com",
                    includesSubdomains: true
                ),
            ]
        )
        let url = try makeURL("https://notexample.com/?share_id=1")

        #expect(try !custom.clean(url: url).didChange)
    }

    @Test
    func emptyRulesDisableAllRemoval() throws {
        let custom = NothungCleaner(rules: [])
        let url = try makeURL("https://example.com/?utm_source=x&fbclid=y")

        #expect(try !custom.clean(url: url).didChange)
    }

    @Test
    func allowRulesOverrideBroadBlockRules() throws {
        let policy = QueryParameterPolicy(
            blockedRules: [TrackingRule(prefix: "utm_")],
            allowedRules: [TrackingRule(exactName: "utm_content")]
        )
        let custom = NothungCleaner(parameterPolicy: policy, regexRules: [])
        let result = try custom.clean(
            url: makeURL("https://example.com/?utm_source=x&utm_content=article&id=7")
        )

        #expect(
            result.cleanedURL.absoluteString
                == "https://example.com/?utm_content=article&id=7"
        )
        #expect(result.removedParameters.map(\.name) == ["utm_source"])
    }

    @Test
    func hostScopedAllowRuleDoesNotLeakToOtherHosts() throws {
        let policy = QueryParameterPolicy(
            blockedRules: [TrackingRule(prefix: "utm_")],
            allowedRules: [
                TrackingRule(exactName: "utm_content", host: "example.com"),
            ]
        )
        let custom = NothungCleaner(parameterPolicy: policy, regexRules: [])

        let allowed = try custom.clean(
            url: makeURL("https://example.com/?utm_content=article")
        )
        let blocked = try custom.clean(
            url: makeURL("https://other.example/?utm_content=article")
        )

        #expect(!allowed.didChange)
        #expect(blocked.cleanedURL.absoluteString == "https://other.example/")
    }

    @Test
    func orderedRegexRulesRunSequentiallyWithoutAQuery() throws {
        let first = try OrderedRegexRule(
            identifier: "old-to-middle",
            pattern: "/old$",
            replacementTemplate: "/middle"
        )
        let second = try OrderedRegexRule(
            identifier: "middle-to-new",
            pattern: "/middle$",
            replacementTemplate: "/new"
        )
        let custom = NothungCleaner(
            parameterPolicy: QueryParameterPolicy(),
            regexRules: [first, second]
        )
        let result = try custom.clean(url: makeURL("https://example.com/old"))

        #expect(result.cleanedURL.absoluteString == "https://example.com/new")
        #expect(
            result.appliedRegexRuleIdentifiers
                == ["old-to-middle", "middle-to-new"]
        )
    }

    @Test
    func regexReplacementSupportsCaptureGroupsAndRunsAfterParameterCleaning() throws {
        let rule = try OrderedRegexRule(
            identifier: "canonical-story",
            pattern: "https://example\\.com/story/(\\d+)",
            replacementTemplate: "https://example.com/articles/$1"
        )
        let custom = NothungCleaner(
            parameterPolicy: QueryParameterPolicy(),
            regexRules: [rule]
        )
        let result = try custom.clean(
            url: makeURL("https://example.com/story/42?utm_source=x#details")
        )

        #expect(
            result.cleanedURL.absoluteString
                == "https://example.com/articles/42#details"
        )
        #expect(result.removedParameters.map(\.name) == ["utm_source"])
        #expect(result.appliedRegexRuleIdentifiers == ["canonical-story"])
    }

    @Test
    func invalidRegexIsRejectedWhenRuleIsCreated() {
        #expect(throws: OrderedRegexRuleError.invalidPattern("broken")) {
            try OrderedRegexRule(
                identifier: "broken",
                pattern: "(",
                replacementTemplate: ""
            )
        }
    }

    @Test
    func emptyRegexPatternIsRejectedBeforeItCanMatchEveryBoundary() {
        #expect(throws: OrderedRegexRuleError.emptyPattern) {
            try OrderedRegexRule(
                identifier: "empty",
                pattern: "",
                replacementTemplate: "x"
            )
        }
    }

    @Test
    func regexCannotProduceANonWebURL() throws {
        let rule = try OrderedRegexRule(
            identifier: "unsafe-scheme",
            pattern: "^https://",
            replacementTemplate: "file:///"
        )
        let custom = NothungCleaner(
            parameterPolicy: QueryParameterPolicy(),
            regexRules: [rule]
        )

        #expect(throws: NothungCleanerError.regexProducedUnsafeURL("unsafe-scheme")) {
            try custom.clean(url: makeURL("https://example.com/path"))
        }
    }

    @Test
    func regexCannotIntroduceEmbeddedCredentials() throws {
        let rule = try OrderedRegexRule(
            identifier: "unsafe-userinfo",
            pattern: "example\\.com",
            replacementTemplate: "user:password@example.com"
        )
        let custom = NothungCleaner(
            parameterPolicy: QueryParameterPolicy(),
            regexRules: [rule]
        )

        #expect(throws: NothungCleanerError.regexProducedUnsafeURL("unsafe-userinfo")) {
            try custom.clean(url: makeURL("https://example.com/path"))
        }
    }

    @Test
    func regexPipelineLimitsRuleCount() throws {
        let rules = try (0...NothungCleaner.maximumRegexRuleCount).map { index in
            try OrderedRegexRule(
                identifier: "rule-\(index)",
                pattern: "never-match-\(index)",
                replacementTemplate: ""
            )
        }
        let custom = NothungCleaner(
            parameterPolicy: QueryParameterPolicy(),
            regexRules: rules
        )

        #expect(throws: NothungCleanerError.tooManyRegexRules) {
            try custom.clean(url: makeURL("https://example.com/path"))
        }
    }

    @Test
    func regexPipelineLimitsURLLength() throws {
        let rule = try OrderedRegexRule(
            identifier: "bounded",
            pattern: "never-match",
            replacementTemplate: ""
        )
        let custom = NothungCleaner(
            parameterPolicy: QueryParameterPolicy(),
            regexRules: [rule]
        )
        let longPath = String(
            repeating: "a",
            count: NothungCleaner.maximumRegexInputLength + 1
        )

        #expect(throws: NothungCleanerError.regexInputTooLong) {
            try custom.clean(url: makeURL("https://example.com/\(longPath)"))
        }
    }

    @Test
    func cleansMultipleURLsInTextAndKeepsResultOrder() {
        let text = "First https://one.example/a?utm_source=x&id=1 then https://two.example/b?fbclid=y&q=2."
        let result = cleaner.clean(text: text)

        #expect(
            result.cleanedText
                == "First https://one.example/a?id=1 then https://two.example/b?q=2."
        )
        #expect(result.urlResults.count == 2)
        #expect(result.urlResults[0].removedParameters.first?.name == "utm_source")
        #expect(result.urlResults[1].removedParameters.first?.name == "fbclid")
        #expect(result.didChange)
    }

    @Test
    func nonURLTextIsUnchanged() {
        let text = "There is no link here: example dot com. 你好。"
        let result = cleaner.clean(text: text)

        #expect(result.cleanedText == text)
        #expect(result.urlResults.isEmpty)
        #expect(!result.didChange)
    }

    @Test
    func textIgnoresNonHTTPSchemes() {
        let text = "ftp://example.com/?utm_source=x and mailto:person@example.com"
        let result = cleaner.clean(text: text)

        #expect(result.cleanedText == text)
        #expect(result.urlResults.isEmpty)
        #expect(!result.didChange)
    }

    @Test
    func textPreservesEmojiUTF16RangesAndChinesePunctuation() {
        let text = "🙂前缀（https://example.com/路径?utm_source=%E9%82%AE%E4%BB%B6&keep=%E5%80%BC#%E7%AB%A0）后缀"
        let result = cleaner.clean(text: text)

        #expect(
            result.cleanedText
                == "🙂前缀（https://example.com/%E8%B7%AF%E5%BE%84?keep=%E5%80%BC#%E7%AB%A0）后缀"
        )
        #expect(result.urlResults.first?.removedParameters.first?.value == "邮件")
    }

    @Test
    func textIncludesUnchangedHTTPURLsInResults() {
        let text = "https://example.com/?id=1 and https://example.org/?utm_source=x"
        let result = cleaner.clean(text: text)

        #expect(result.urlResults.count == 2)
        #expect(!result.urlResults[0].didChange)
        #expect(result.urlResults[1].didChange)
    }

    @Test
    func orderedAllowListKeepsOnlyNamedParametersForItsHost() throws {
        let rule = OrderedQueryRule(
            identifier: "video",
            host: "video.example",
            mode: .allowList,
            parameterNames: ["id", "episode"]
        )
        let custom = NothungCleaner(
            parameterPolicy: QueryParameterPolicy(blockedRules: []),
            orderedParameterRules: [rule],
            regexRules: []
        )

        let result = try custom.clean(
            url: makeURL("https://video.example/watch?id=7&utm_source=x&episode=2")
        )

        #expect(result.cleanedURL.absoluteString == "https://video.example/watch?id=7&episode=2")
        #expect(result.removedParameters.map(\.name) == ["utm_source"])
    }

    @Test
    func emptyOrderedParameterRuleRemovesEveryParameter() throws {
        for mode in [OrderedQueryRule.Mode.allowList, .blockList] {
            let custom = NothungCleaner(
                parameterPolicy: QueryParameterPolicy(blockedRules: []),
                orderedParameterRules: [
                    OrderedQueryRule(
                        identifier: "drop-all",
                        host: "example.com",
                        includesSubdomains: true,
                        mode: mode,
                        parameterNames: []
                    ),
                ],
                regexRules: []
            )

            let result = try custom.clean(
                url: makeURL("https://sub.example.com/path?id=1&keep=2#fragment")
            )
            #expect(result.cleanedURL.absoluteString == "https://sub.example.com/path#fragment")
            #expect(result.removedParameters.map(\.name) == ["id", "keep"])
        }
    }

    @Test
    func regexGroupSkipsAllStepsWhenItsFirstPatternDoesNotMatch() throws {
        let group = OrderedRegexRuleGroup(
            identifier: "guarded",
            steps: [
                try OrderedRegexRule(
                    identifier: "guarded-0",
                    pattern: "other\\.example",
                    replacementTemplate: "target.example"
                ),
                try OrderedRegexRule(
                    identifier: "guarded-1",
                    pattern: "\\?.*",
                    replacementTemplate: ""
                ),
            ]
        )
        let custom = NothungCleaner(
            parameterPolicy: QueryParameterPolicy(blockedRules: []),
            regexRules: [],
            regexRuleGroups: [group]
        )

        let result = try custom.clean(
            url: makeURL("https://example.com/path?keep=1")
        )

        #expect(result.cleanedURL.absoluteString == "https://example.com/path?keep=1")
        #expect(result.appliedRegexRuleIdentifiers.isEmpty)
    }

    @Test
    func regexGroupRunsEveryStepInOrderAfterGuardMatches() throws {
        let group = OrderedRegexRuleGroup(
            identifier: "canonical",
            steps: [
                try OrderedRegexRule(
                    identifier: "canonical-0",
                    pattern: "mobile\\.example",
                    replacementTemplate: "www.example"
                ),
                try OrderedRegexRule(
                    identifier: "canonical-1",
                    pattern: "\\?.*",
                    replacementTemplate: ""
                ),
            ]
        )
        let custom = NothungCleaner(
            parameterPolicy: QueryParameterPolicy(blockedRules: []),
            regexRules: [],
            regexRuleGroups: [group]
        )

        let result = try custom.clean(
            url: makeURL("https://mobile.example/path?share=1")
        )

        #expect(result.cleanedURL.absoluteString == "https://www.example/path")
        #expect(result.appliedRegexRuleIdentifiers == ["canonical"])
    }

    private func clean(_ value: String) throws -> URLCleaningResult {
        try cleaner.clean(url: makeURL(value))
    }

    private func makeURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw FixtureError.invalidURL(value)
        }
        return url
    }

    private enum FixtureError: Error {
        case invalidURL(String)
    }
}
