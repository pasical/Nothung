import Foundation

private enum ValidationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

private var checkCount = 0

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    checkCount += 1
    guard condition() else {
        throw ValidationFailure.failed(message)
    }
}

private func url(_ value: String) throws -> URL {
    guard let result = URL(string: value) else {
        throw ValidationFailure.failed("Foundation rejected fixture: \(value)")
    }
    return result
}

private func runValidation() throws {
    let cleaner = NothungCleaner()

    let basic = try cleaner.clean(
        url: url("https://example.com/a?id=42&utm_source=mail&utm_medium=email")
    )
    try expect(
        basic.cleanedURL.absoluteString == "https://example.com/a?id=42",
        "UTM removal changed the destination"
    )
    try expect(basic.removedParameters.count == 2, "UTM removals were not reported")

    let duplicate = try cleaner.clean(
        url: url("https://example.com/?tag=1&utm_source=a&tag=2&utm_source=b")
    )
    try expect(
        duplicate.cleanedURL.absoluteString == "https://example.com/?tag=1&tag=2",
        "duplicate retained parameters lost order"
    )

    let encoded = try cleaner.clean(
        url: url("https://example.com/?payload=a%26b%3Dc&u%74m_source=x#frag%3D1")
    )
    try expect(
        encoded.cleanedURL.absoluteString == "https://example.com/?payload=a%26b%3Dc#frag%3D1",
        "encoded delimiter or fragment was rewritten"
    )

    let emptyValues = try cleaner.clean(
        url: url("https://example.com/?utm_source=&gclid&keep=")
    )
    try expect(
        emptyValues.cleanedURL.absoluteString == "https://example.com/?keep=",
        "empty retained value changed"
    )
    try expect(
        emptyValues.removedParameters.map(\.value) == ["", nil],
        "missing and empty values were conflated"
    )

    let unchanged = try cleaner.clean(url: url("https://example.com/p?q=a+b#part"))
    try expect(!unchanged.didChange, "safe URL should be unchanged")
    try expect(
        unchanged.cleanedURL.absoluteString == "https://example.com/p?q=a+b#part",
        "plus or fragment changed"
    )

    let ipv6 = try cleaner.clean(
        url: url("https://[2001:db8::1]/?utm_source=x&keep=1")
    )
    try expect(
        ipv6.cleanedURL.absoluteString == "https://[2001:db8::1]/?keep=1",
        "IPv6 host changed"
    )

    let hostScoped = NothungCleaner(
        rules: [
            TrackingRule(
                exactName: "share_id",
                host: "example.com",
                includesSubdomains: true
            ),
        ]
    )
    let subdomain = try hostScoped.clean(
        url: url("https://news.example.com/?share_id=x&keep=1")
    )
    try expect(
        subdomain.cleanedURL.absoluteString == "https://news.example.com/?keep=1",
        "host-scoped subdomain rule did not match"
    )
    let boundary = try hostScoped.clean(
        url: url("https://notexample.com/?share_id=x")
    )
    try expect(!boundary.didChange, "host matching ignored label boundary")

    let mixedText = cleaner.clean(
        text: "前缀（https://one.example/a?utm_source=x&id=1）和 https://two.example/?gclid=y&q=2。"
    )
    try expect(mixedText.urlResults.count == 2, "multiple text URLs were not detected")
    try expect(
        mixedText.cleanedText == "前缀（https://one.example/a?id=1）和 https://two.example/?q=2。",
        "text replacement damaged Unicode punctuation"
    )

    let plainText = cleaner.clean(text: "没有链接的普通文本")
    try expect(!plainText.didChange && plainText.urlResults.isEmpty, "plain text changed")

    do {
        _ = try cleaner.clean(url: url("file:///tmp/a?utm_source=x"))
        throw ValidationFailure.failed("file URL was accepted")
    } catch NothungCleanerError.unsupportedScheme {
        checkCount += 1
    }

    do {
        _ = try cleaner.clean(url: url("https://user:secret@example.com/?utm_source=x"))
        throw ValidationFailure.failed("userinfo URL was accepted")
    } catch NothungCleanerError.userInfoNotAllowed {
        checkCount += 1
    }

    print("NothungCore validation passed: \(checkCount) checks")
}

do {
    try runValidation()
} catch {
    fatalError("NothungCore validation failed: \(error)")
}
