import Foundation
import NothungCore

enum NothungInputKind: Equatable {
    case url
    case text
}

struct NothungRemovedField: Identifiable, Equatable {
    let id: Int
    let name: String
    let value: String?
}

struct NothungCleaningOutput: Equatable {
    let original: String
    let cleaned: String
    let removedFields: [NothungRemovedField]
    let appliedRegexRuleIdentifiers: [String]
    let didChange: Bool
    let detectedURLCount: Int
    let inputKind: NothungInputKind
}

enum NothungCleaningService {
    static let maximumInputLength = 100_000

    enum CleaningError: LocalizedError {
        case noWebURL
        case tooLong
        case embeddedCredentials
        case invalidWebURL

        var errorDescription: String? {
            switch self {
            case .noWebURL:
                return String(localized: "没有找到以 http:// 或 https:// 开头的链接。")
            case .tooLong:
                return String(localized: "内容超过 100,000 个字符，请缩短后再试。")
            case .embeddedCredentials:
                return String(localized: "链接包含用户名或密码。为避免误分享凭据，Nothung 不会处理这类链接。")
            case .invalidWebURL:
                return String(localized: "这个网页链接无法安全解析，请检查地址后重试。")
            }
        }
    }

    static func clean(
        _ input: String,
        cleaner: NothungCleaner = NothungConfiguredCleaner.current()
    ) throws -> NothungCleaningOutput {
        guard input.count <= maximumInputLength else {
            throw CleaningError.tooLong
        }

        if let url = standaloneWebURL(from: input) {
            let result: URLCleaningResult
            do {
                result = try cleaner.clean(url: url)
            } catch NothungCleanerError.userInfoNotAllowed {
                throw CleaningError.embeddedCredentials
            } catch is NothungCleanerError {
                throw CleaningError.invalidWebURL
            }
            let fields = result.removedParameters.enumerated().map { index, parameter in
                NothungRemovedField(
                    id: index,
                    name: parameter.name,
                    value: parameter.value
                )
            }

            return NothungCleaningOutput(
                original: result.originalURL.absoluteString,
                cleaned: result.cleanedURL.absoluteString,
                removedFields: fields,
                appliedRegexRuleIdentifiers: result.appliedRegexRuleIdentifiers,
                didChange: result.didChange,
                detectedURLCount: 1,
                inputKind: .url
            )
        }

        let result = cleaner.clean(text: input)
        guard !result.urlResults.isEmpty else {
            throw CleaningError.noWebURL
        }

        let fields = result.urlResults
            .flatMap(\.removedParameters)
            .enumerated()
            .map { index, parameter in
                NothungRemovedField(
                    id: index,
                    name: parameter.name,
                    value: parameter.value
                )
            }

        return NothungCleaningOutput(
            original: result.originalText,
            cleaned: result.cleanedText,
            removedFields: fields,
            appliedRegexRuleIdentifiers: result.urlResults.flatMap(
                \.appliedRegexRuleIdentifiers
            ),
            didChange: result.didChange,
            detectedURLCount: result.urlResults.count,
            inputKind: .text
        )
    }

    /// Returns the sole HTTP(S) URL represented by a cleaning result. This also
    /// supports share payloads such as “标题 https://b23.tv/…” while refusing to
    /// guess when the host supplied several different links.
    static func singleWebURL(in output: NothungCleaningOutput) -> URL? {
        if output.inputKind == .url {
            return URL(string: output.cleaned)
        }
        return singleWebURLMatch(in: output.cleaned)?.url
    }

    /// Replaces the one URL in a cleaned share payload and runs the complete
    /// cleaning pipeline again for the resolved destination.
    static func replacingSingleWebURL(
        in output: NothungCleaningOutput,
        with resolvedURL: URL
    ) throws -> NothungCleaningOutput {
        guard output.inputKind == .text,
              let match = singleWebURLMatch(in: output.cleaned) else {
            return try clean(resolvedURL.absoluteString)
        }
        let replaced = (output.cleaned as NSString).replacingCharacters(
            in: match.range,
            with: resolvedURL.absoluteString
        )
        return try clean(replaced)
    }

    private static func standaloneWebURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }
        return components.url
    }

    private static func singleWebURLMatch(in text: String) -> NSTextCheckingResult? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return nil
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, options: [], range: range).filter { match in
            guard let scheme = match.url?.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}

/// The one-step workflow used by the Action Extension.
///
/// Keeping the clipboard write behind a closure makes the ordering explicit:
/// invalid content never replaces the person's existing clipboard value.
enum NothungCleanCopyWorkflow {
    @discardableResult
    static func run(
        _ input: String,
        writeToClipboard: (String) -> Void
    ) throws -> NothungCleaningOutput {
        let output = try NothungCleaningService.clean(input)
        writeToClipboard(output.cleaned)
        return output
    }
}
