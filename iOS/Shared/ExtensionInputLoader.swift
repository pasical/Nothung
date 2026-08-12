import Foundation
import UniformTypeIdentifiers

enum ExtensionInputLoader {
    enum LoadingError: LocalizedError, Equatable {
        case noInput
        case multipleInputs
        case unsupportedInput([String])

        var errorDescription: String? {
            switch self {
            case .noInput:
                return "宿主 App 没有提供可读取的内容。"
            case .multipleInputs:
                return "一次只能清理一个 URL 或一段纯文本，请减少所选内容后重试。"
            case .unsupportedInput(let types):
                let summary = types.isEmpty
                    ? "宿主没有提供可识别的类型。"
                    : "宿主提供的类型：\(types.joined(separator: ", "))"
                return "没有从分享内容中读取到链接。\(summary)"
            }
        }
    }

    static func firstSharedText(from context: NSExtensionContext?) async throws -> String {
        guard let items = context?.inputItems as? [NSExtensionItem] else {
            throw LoadingError.noInput
        }
        return try await firstSharedText(from: items)
    }

    /// Resolves one logical share payload even when a host supplies several
    /// representations of it. Safari commonly provides the same page as both a
    /// URL attachment and plain text; URL wins and the text representation is
    /// intentionally ignored.
    static func firstSharedText(from items: [NSExtensionItem]) async throws -> String {
        guard !items.isEmpty else { throw LoadingError.noInput }
        let providers = items.flatMap { $0.attachments ?? [] }

        let urlValues = await distinctValues(
            from: providers,
            conformingTo: UTType.url
        )
        if urlValues.count == 1 { return urlValues[0] }
        if urlValues.count > 1 { throw LoadingError.multipleInputs }

        let attributedLinkValues = distinct(
            items.flatMap { linkValues(from: $0.attributedContentText) }
        )
        if attributedLinkValues.count == 1 { return attributedLinkValues[0] }
        if attributedLinkValues.count > 1 { throw LoadingError.multipleInputs }

        let textValues = await distinctValues(
            from: providers,
            conformingTo: UTType.plainText
        )
        if textValues.count == 1 { return textValues[0] }
        if textValues.count > 1 { throw LoadingError.multipleInputs }

        // Some hosts, including social apps, advertise only the abstract
        // `public.text` supertype rather than a concrete plain-text subtype.
        let genericTextValues = await distinctValues(
            from: providers,
            conformingTo: UTType.text
        )
        if genericTextValues.count == 1 { return genericTextValues[0] }
        if genericTextValues.count > 1 { throw LoadingError.multipleInputs }

        let attributedValues = distinct(
            items.compactMap { $0.attributedContentText?.string.nonEmpty }
        )
        if attributedValues.count == 1 { return attributedValues[0] }
        if attributedValues.count > 1 { throw LoadingError.multipleInputs }

        let advertisedTypes = Array(
            Set(providers.flatMap(\.registeredTypeIdentifiers))
        ).sorted().prefix(8)
        throw LoadingError.unsupportedInput(Array(advertisedTypes))
    }

    private static func distinctValues(
        from providers: [NSItemProvider],
        conformingTo type: UTType
    ) async -> [String] {
        var values: [String] = []
        for provider in providers
        where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            guard let item = try? await loadItem(
                from: provider,
                typeIdentifier: type.identifier
            ),
            let value = string(from: item)?.nonEmpty else {
                continue
            }
            if !values.contains(value) { values.append(value) }
        }
        return values
    }

    private static func distinct(_ values: [String]) -> [String] {
        values.reduce(into: []) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }

    private static func loadItem(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }

    private static func string(from item: NSSecureCoding?) -> String? {
        switch item {
        case let url as URL:
            return url.absoluteString
        case let url as NSURL:
            return url.absoluteString
        case let string as String:
            return string
        case let string as NSString:
            return string as String
        case let data as Data:
            return String(data: data, encoding: .utf8)
        case let data as NSData:
            return String(data: data as Data, encoding: .utf8)
        case let attributed as NSAttributedString:
            return attributed.string
        default:
            return nil
        }
    }

    private static func linkValues(from attributed: NSAttributedString?) -> [String] {
        guard let attributed, attributed.length > 0 else { return [] }
        var values: [String] = []
        attributed.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            let candidate: String?
            switch value {
            case let url as URL:
                candidate = url.absoluteString
            case let url as NSURL:
                candidate = url.absoluteString
            case let string as String:
                candidate = string
            case let string as NSString:
                candidate = string as String
            default:
                candidate = nil
            }
            if let candidate = candidate?.nonEmpty,
               !values.contains(candidate) {
                values.append(candidate)
            }
        }
        return values
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
