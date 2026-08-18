import Darwin
import Dispatch
import Foundation

protocol RedirectResolving: Sendable {
    func resolve(_ url: URL) async throws -> RedirectResolution
}

/// Resolves HTTPS redirects without sharing cookies, credentials, or response bodies
/// with the rest of the app.
///
/// This type is intentionally independent from the cleaning flow. Callers must make
/// the network disclosure explicit before invoking `resolve(_:)`.
///
/// Host resolution is a defense-in-depth preflight, not DNS pinning: `URLSession`
/// performs its own connection resolution and can use system proxies. Do not expose
/// this resolver as a generic server-side request primitive.
struct RedirectResolver: Sendable {
    static let maximumRedirectCount = 5

    /// Resolution only needs response headers. Every task is cancelled before its
    /// response body is consumed, making the accepted body limit zero bytes.
    static let maximumResponseBodyBytes = 0

    struct Configuration: Sendable, Equatable {
        static let standard = Configuration()

        /// Inactivity timeout applied to each individual request.
        var requestTimeout: TimeInterval = 10

        /// Wall-clock budget for DNS checks and the complete redirect chain.
        var overallTimeout: TimeInterval = 30
    }

    let configuration: Configuration

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    func resolve(_ url: URL) async throws -> RedirectResolution {
        try validateConfiguration()

        return try await withThrowingTaskGroup(of: RedirectResolution.self) { group in
            group.addTask {
                try await resolveWithinTimeLimit(url)
            }
            group.addTask {
                let nanoseconds = UInt64(configuration.overallTimeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw RedirectResolverError.overallTimeout(
                    seconds: configuration.overallTimeout
                )
            }

            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw CancellationError()
            }
            return first
        }
    }

    private func resolveWithinTimeLimit(_ originalURL: URL) async throws -> RedirectResolution {
        let initialURL = try await validatedURL(originalURL, context: .initial)
        let delegate = RedirectSessionDelegate()
        let session = URLSession(
            configuration: makeSessionConfiguration(),
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var currentURL = initialURL
        var visited = Set([requestIdentity(for: initialURL)])
        var hops: [RedirectHop] = []

        while true {
            try Task.checkCancellation()
            let response = try await response(for: currentURL, session: session, delegate: delegate)

            guard Self.redirectStatusCodes.contains(response.http.statusCode) else {
                response.bytes.task.cancel()
                return RedirectResolution(
                    originalURL: originalURL,
                    finalURL: currentURL,
                    hops: hops,
                    finalStatusCode: response.http.statusCode
                )
            }

            response.bytes.task.cancel()
            guard hops.count < Self.maximumRedirectCount else {
                throw RedirectResolverError.tooManyRedirects(
                    maximum: Self.maximumRedirectCount
                )
            }
            guard let location = response.http.value(forHTTPHeaderField: "Location")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !location.isEmpty else {
                throw RedirectResolverError.missingRedirectLocation(
                    url: currentURL,
                    statusCode: response.http.statusCode
                )
            }
            guard let candidate = URL(string: location, relativeTo: currentURL)?.absoluteURL else {
                throw RedirectResolverError.invalidRedirectLocation(
                    sourceURL: currentURL,
                    value: location
                )
            }
            let candidateIdentity = requestIdentity(for: candidate)
            guard !visited.contains(candidateIdentity) else {
                throw RedirectResolverError.redirectLoop(url: candidate)
            }

            let nextURL = try await validatedURL(
                candidate,
                context: .redirect(sourceURL: currentURL)
            )
            let identity = requestIdentity(for: nextURL)
            guard !visited.contains(identity) else {
                throw RedirectResolverError.redirectLoop(url: nextURL)
            }

            hops.append(
                RedirectHop(
                    sourceURL: currentURL,
                    destinationURL: nextURL,
                    statusCode: response.http.statusCode
                )
            )
            visited.insert(identity)
            currentURL = nextURL
        }
    }

    private func response(
        for url: URL,
        session: URLSession,
        delegate: RedirectSessionDelegate
    ) async throws -> (bytes: URLSession.AsyncBytes, http: HTTPURLResponse) {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: configuration.requestTimeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Nothung/0.1 RedirectResolver", forHTTPHeaderField: "User-Agent")
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        request.setValue(nil, forHTTPHeaderField: "Proxy-Authorization")

        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse else {
                bytes.task.cancel()
                throw RedirectResolverError.nonHTTPResponse(url: url)
            }
            return (bytes, http)
        } catch let error as RedirectResolverError {
            throw error
        } catch let error as URLError {
            if Task.isCancelled {
                throw CancellationError()
            }
            if error.code == .timedOut {
                throw RedirectResolverError.requestTimeout(
                    url: url,
                    seconds: configuration.requestTimeout
                )
            }
            throw RedirectResolverError.transportFailure(
                url: url,
                code: error.errorCode
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RedirectResolverError.transportFailure(
                url: url,
                code: (error as NSError).code
            )
        }
    }

    private func validatedURL(_ url: URL, context: ValidationContext) async throws -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased() else {
            throw RedirectResolverError.invalidURL(url)
        }

        guard scheme == "http" || scheme == "https" else {
            switch context {
            case .initial:
                throw RedirectResolverError.unsupportedInitialScheme(scheme)
            case let .redirect(sourceURL):
                throw RedirectResolverError.unsupportedRedirectScheme(
                    sourceURL: sourceURL,
                    destinationURL: url,
                    scheme: scheme
                )
            }
        }
        guard scheme == "https" else {
            switch context {
            case .initial:
                throw RedirectResolverError.insecureInitialURL(url)
            case let .redirect(sourceURL):
                throw RedirectResolverError.insecureRedirect(
                    sourceURL: sourceURL,
                    destinationURL: url
                )
            }
        }
        guard components.user == nil, components.password == nil else {
            throw RedirectResolverError.embeddedCredentials(url)
        }
        let canonicalURL = components.url ?? url
        guard let rawHost = canonicalURL.host(percentEncoded: false), !rawHost.isEmpty else {
            throw RedirectResolverError.missingHost(url)
        }

        let host = HostPolicy.normalized(rawHost)
        guard !host.isEmpty, !HostPolicy.isBlockedName(host) else {
            throw RedirectResolverError.blockedHost(host)
        }
        try await HostPolicy.validateResolvedAddresses(for: host)
        return canonicalURL
    }

    private func validateConfiguration() throws {
        guard configuration.requestTimeout.isFinite,
              (0.25...60).contains(configuration.requestTimeout),
              configuration.overallTimeout.isFinite,
              (0.25...300).contains(configuration.overallTimeout) else {
            throw RedirectResolverError.invalidConfiguration
        }
    }

    private func makeSessionConfiguration() -> URLSessionConfiguration {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.overallTimeout
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.httpCookieAcceptPolicy = .never
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.urlCredentialStorage = nil
        sessionConfiguration.httpMaximumConnectionsPerHost = 1
        sessionConfiguration.waitsForConnectivity = false
        sessionConfiguration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return sessionConfiguration
    }

    private func requestIdentity(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url.absoluteString
        }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    private enum ValidationContext {
        case initial
        case redirect(sourceURL: URL)
    }

    private static let redirectStatusCodes: Set<Int> = [301, 302, 303, 307, 308]
}

extension RedirectResolver: RedirectResolving {}

struct RedirectResolution: Sendable, Equatable {
    let originalURL: URL
    let finalURL: URL
    let hops: [RedirectHop]
    let finalStatusCode: Int

    var didRedirect: Bool { !hops.isEmpty }
}

struct RedirectHop: Sendable, Equatable {
    let sourceURL: URL
    let destinationURL: URL
    let statusCode: Int
}

enum RedirectResolverError: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidURL(URL)
    case unsupportedInitialScheme(String)
    case unsupportedRedirectScheme(sourceURL: URL, destinationURL: URL, scheme: String)
    case insecureInitialURL(URL)
    case insecureRedirect(sourceURL: URL, destinationURL: URL)
    case embeddedCredentials(URL)
    case missingHost(URL)
    case blockedHost(String)
    case dnsResolutionFailed(host: String, code: Int32)
    case nonPublicAddress(host: String, address: String)
    case nonHTTPResponse(url: URL)
    case missingRedirectLocation(url: URL, statusCode: Int)
    case invalidRedirectLocation(sourceURL: URL, value: String)
    case redirectLoop(url: URL)
    case tooManyRedirects(maximum: Int)
    case requestTimeout(url: URL, seconds: TimeInterval)
    case overallTimeout(seconds: TimeInterval)
    case transportFailure(url: URL, code: Int)
}

extension RedirectResolverError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return String(localized: "重定向解析器的超时设置无效。")
        case .invalidURL:
            return String(localized: "这个链接无法解析。")
        case .unsupportedInitialScheme:
            return String(localized: "只能解析 http:// 或 https:// 链接。")
        case let .unsupportedRedirectScheme(_, _, scheme):
            return String(localized: "重定向目标使用了不允许的 \(scheme) 协议。")
        case .insecureInitialURL:
            return String(localized: "为避免明文请求，重定向解析不会访问初始 http:// 链接。请使用 https:// 链接。")
        case .insecureRedirect:
            return String(localized: "重定向尝试从 HTTPS 降级到不安全的 HTTP，已停止解析。")
        case .embeddedCredentials:
            return String(localized: "链接包含用户名或密码，已停止解析。")
        case let .missingHost(url):
            return String(localized: "链接缺少主机名：\(url.absoluteString)")
        case let .blockedHost(host):
            return String(localized: "出于本地网络安全考虑，不能访问主机 \(host)。")
        case let .dnsResolutionFailed(host, _):
            return String(localized: "无法解析主机 \(host) 的公开网络地址。")
        case let .nonPublicAddress(host, address):
            return String(localized: "主机 \(host) 指向本地、私有或保留地址 \(address)，已停止解析。")
        case .nonHTTPResponse:
            return String(localized: "服务器没有返回有效的 HTTP 响应。")
        case let .missingRedirectLocation(_, statusCode):
            return String(localized: "服务器返回了重定向状态 \(statusCode)，但没有提供目标地址。")
        case .invalidRedirectLocation:
            return String(localized: "服务器提供的重定向目标无效。")
        case .redirectLoop:
            return String(localized: "检测到重定向循环，已停止解析。")
        case let .tooManyRedirects(maximum):
            return String(localized: "重定向超过 \(maximum) 次，已停止解析。")
        case let .requestTimeout(_, seconds):
            return String(localized: "单次请求超过 \(seconds.formatted()) 秒，已停止解析。")
        case let .overallTimeout(seconds):
            return String(localized: "重定向解析超过 \(seconds.formatted()) 秒，已停止。")
        case .transportFailure:
            return String(localized: "网络请求失败，未完成重定向解析。")
        }
    }
}

private final class RedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    private func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

private enum HostPolicy {
    private struct IPAddress: Sendable, Hashable {
        enum Family: Sendable, Hashable {
            case v4
            case v6
        }

        let family: Family
        let bytes: [UInt8]

        var displayString: String {
            switch family {
            case .v4:
                return bytes.map(String.init).joined(separator: ".")
            case .v6:
                guard bytes.count == 16 else { return "IPv6" }
                return stride(from: 0, to: 16, by: 2)
                    .map { index in
                        String(format: "%x", UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1]))
                    }
                    .joined(separator: ":")
            }
        }
    }

    /// Holds an async continuation while `getaddrinfo` runs on a dedicated blocking
    /// queue. Cancellation resumes the awaiting task immediately; the system lookup
    /// may finish later, but it can no longer extend the resolver's wall-clock limit.
    private final class DNSLookupState: @unchecked Sendable {
        private enum Outcome: Sendable {
            case addresses(Set<IPAddress>)
            case failure(RedirectResolverError)
            case cancelled
        }

        private let lock = NSLock()
        private var continuation: CheckedContinuation<Set<IPAddress>, any Error>?
        private var pendingOutcome: Outcome?

        func install(_ continuation: CheckedContinuation<Set<IPAddress>, any Error>) {
            lock.lock()
            if let pendingOutcome {
                self.pendingOutcome = nil
                lock.unlock()
                resume(continuation, with: pendingOutcome)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }

        func finish(with addresses: Set<IPAddress>) {
            finish(with: .addresses(addresses))
        }

        func finish(with error: RedirectResolverError) {
            finish(with: .failure(error))
        }

        func cancel() {
            finish(with: .cancelled)
        }

        private func finish(with outcome: Outcome) {
            lock.lock()
            if let continuation {
                self.continuation = nil
                lock.unlock()
                resume(continuation, with: outcome)
            } else if pendingOutcome == nil {
                pendingOutcome = outcome
                lock.unlock()
            } else {
                lock.unlock()
            }
        }

        private func resume(
            _ continuation: CheckedContinuation<Set<IPAddress>, any Error>,
            with outcome: Outcome
        ) {
            switch outcome {
            case let .addresses(addresses):
                continuation.resume(returning: addresses)
            case let .failure(error):
                continuation.resume(throwing: error)
            case .cancelled:
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    static func normalized(_ host: String) -> String {
        var result = host.lowercased()
        while result.last == "." {
            result.removeLast()
        }
        return result
    }

    static func isBlockedName(_ host: String) -> Bool {
        let exactNames: Set<String> = [
            "localhost",
            "localhost.localdomain",
            "ip6-localhost",
            "ip6-loopback",
            "broadcasthost",
            "metadata",
            "metadata.google.internal",
            "metadata.aws.internal",
            "metadata.azure.internal",
            "instance-data",
            "instance-data.ec2.internal",
        ]
        if exactNames.contains(host) {
            return true
        }

        let blockedSuffixes = [
            ".localhost",
            ".local",
            ".localdomain",
            ".internal",
            ".home.arpa",
            ".lan",
        ]
        return blockedSuffixes.contains(where: host.hasSuffix)
    }

    static func validateResolvedAddresses(for host: String) async throws {
        let state = DNSLookupState()
        let addresses = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                DispatchQueue.global(qos: .utility).async {
                    do {
                        state.finish(with: try resolve(host))
                    } catch let error as RedirectResolverError {
                        state.finish(with: error)
                    } catch {
                        state.finish(
                            with: .dnsResolutionFailed(host: host, code: EAI_FAIL)
                        )
                    }
                }
            }
        } onCancel: {
            state.cancel()
        }

        guard !addresses.isEmpty else {
            throw RedirectResolverError.dnsResolutionFailed(host: host, code: EAI_NONAME)
        }
        let hostIsIPAddressLiteral = isIPAddressLiteral(host)
        for address in addresses where isBlocked(address) {
            // Packet-tunnel and rule-based proxy apps commonly synthesize DNS
            // answers from RFC 2544's 198.18.0.0/15 range. For a real hostname,
            // URLSession still performs TLS hostname validation and the system
            // proxy owns the route, so treating that synthetic answer as a local
            // SSRF target breaks otherwise valid links. Direct IP-literal input
            // remains blocked.
            if !hostIsIPAddressLiteral, isProxySyntheticAddress(address) {
                continue
            }
            throw RedirectResolverError.nonPublicAddress(
                host: host,
                address: address.displayString
            )
        }
    }

    private static func resolve(_ host: String) throws -> Set<IPAddress> {
        var addresses = Set<IPAddress>()
        var absenceCode: Int32 = EAI_NONAME

        // Query A and AAAA independently. On DNS64 networks an AF_UNSPEC lookup can
        // return only a synthesized AAAA address; checking the original A record as
        // well prevents a private IPv4 target from hiding inside an unknown NAT64
        // network-specific prefix.
        for family in [AF_INET, AF_INET6] {
            do {
                addresses.formUnion(try resolve(host, family: family))
            } catch let RedirectResolverError.dnsResolutionFailed(_, code) {
                guard code == EAI_ADDRFAMILY || code == EAI_NODATA || code == EAI_NONAME else {
                    throw RedirectResolverError.dnsResolutionFailed(host: host, code: code)
                }
                absenceCode = code
            }
        }
        guard !addresses.isEmpty else {
            throw RedirectResolverError.dnsResolutionFailed(host: host, code: absenceCode)
        }
        return addresses
    }

    private static func resolve(_ host: String, family: Int32) throws -> Set<IPAddress> {
        var hints = addrinfo()
        hints.ai_family = family
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0 else {
            throw RedirectResolverError.dnsResolutionFailed(host: host, code: status)
        }
        defer { freeaddrinfo(result) }

        var addresses = Set<IPAddress>()
        var cursor = result
        while let entry = cursor?.pointee {
            if let address = address(from: entry) {
                addresses.insert(address)
            }
            cursor = entry.ai_next
        }
        return addresses
    }

    private static func address(from entry: addrinfo) -> IPAddress? {
        guard let rawAddress = entry.ai_addr else { return nil }

        switch entry.ai_family {
        case AF_INET:
            let address = UnsafeRawPointer(rawAddress)
                .assumingMemoryBound(to: sockaddr_in.self)
                .pointee
                .sin_addr
            let bytes = withUnsafeBytes(of: address) { Array($0) }
            return IPAddress(family: .v4, bytes: bytes)
        case AF_INET6:
            let address = UnsafeRawPointer(rawAddress)
                .assumingMemoryBound(to: sockaddr_in6.self)
                .pointee
                .sin6_addr
            let bytes = withUnsafeBytes(of: address) { Array($0) }
            return IPAddress(family: .v6, bytes: bytes)
        default:
            return nil
        }
    }

    private static func isBlocked(_ address: IPAddress) -> Bool {
        switch address.family {
        case .v4:
            return isBlockedIPv4(address.bytes)
        case .v6:
            return isBlockedIPv6(address.bytes)
        }
    }

    private static func isIPAddressLiteral(_ host: String) -> Bool {
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return true
        }
        var ipv6 = in6_addr()
        return host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1
    }

    private static func isProxySyntheticAddress(_ address: IPAddress) -> Bool {
        switch address.family {
        case .v4:
            return isBenchmarkingIPv4(address.bytes)
        case .v6:
            let bytes = address.bytes
            guard bytes.count == 16 else { return false }
            let mapped = bytes.prefix(10).allSatisfy { $0 == 0 }
                && bytes[10] == 0xFF && bytes[11] == 0xFF
            let wellKnownNAT64 = bytes[0...11] == [
                0x00, 0x64, 0xFF, 0x9B,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00,
            ]
            return (mapped || wellKnownNAT64)
                && isBenchmarkingIPv4(Array(bytes[12...15]))
        }
    }

    private static func isBenchmarkingIPv4(_ bytes: [UInt8]) -> Bool {
        bytes.count == 4 && bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19)
    }

    private static func isBlockedIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return true }
        let first = bytes[0]
        let second = bytes[1]

        if first == 0 || first == 10 || first == 127 || first >= 224 {
            return true
        }
        if first == 100, (64...127).contains(second) {
            return true
        }
        if first == 169, second == 254 {
            return true
        }
        if first == 172, (16...31).contains(second) {
            return true
        }
        if first == 192, second == 168 {
            return true
        }
        if isBenchmarkingIPv4(bytes) {
            return true
        }

        // Non-routable documentation and protocol-assignment ranges are not valid
        // redirect destinations either.
        if first == 192, second == 0, (bytes[2] == 0 || bytes[2] == 2) {
            return true
        }
        if first == 192, second == 88, bytes[2] == 99 {
            return true
        }
        if first == 198, second == 51, bytes[2] == 100 {
            return true
        }
        if first == 203, second == 0, bytes[2] == 113 {
            return true
        }
        return false
    }

    private static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }

        let firstTenAreZero = bytes.prefix(10).allSatisfy { $0 == 0 }
        if firstTenAreZero, bytes[10] == 0xFF, bytes[11] == 0xFF {
            return isBlockedIPv4(Array(bytes[12...15]))
        }

        // Check IPv4 embedded by the well-known NAT64 prefix 64:ff9b::/96.
        if bytes[0...11] == [
            0x00, 0x64, 0xFF, 0x9B,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ] {
            return isBlockedIPv4(Array(bytes[12...15]))
        }

        // Deprecated IPv4-compatible addresses (::/96) can otherwise disguise an
        // IPv4 loopback or private destination.
        if bytes.prefix(12).allSatisfy({ $0 == 0 }) {
            return true
        }

        // Only globally routed unicast space is eligible after the mapped/NAT64
        // exceptions above. This also rejects unspecified, loopback, discard-only,
        // ULA, link-local, site-local, and multicast ranges.
        guard hasPrefix(bytes, [0x20], bitCount: 3) else {
            return true
        }

        let blockedGlobalPrefixes: [([UInt8], Int)] = [
            ([0x20, 0x01, 0x00, 0x00], 32), // Teredo
            ([0x20, 0x01, 0x00, 0x02, 0x00, 0x00], 48), // benchmarking
            ([0x20, 0x01, 0x00, 0x10], 28), // ORCHIDv1
            ([0x20, 0x01, 0x00, 0x20], 28), // ORCHIDv2
            ([0x20, 0x01, 0x0D, 0xB8], 32), // documentation
            ([0x20, 0x02], 16), // 6to4
            ([0x3F, 0xFF, 0x00], 20), // documentation
        ]
        return blockedGlobalPrefixes.contains { prefix, bitCount in
            hasPrefix(bytes, prefix, bitCount: bitCount)
        }
    }

    private static func hasPrefix(
        _ bytes: [UInt8],
        _ prefix: [UInt8],
        bitCount: Int
    ) -> Bool {
        guard bitCount >= 0, bitCount <= bytes.count * 8 else { return false }
        let fullByteCount = bitCount / 8
        let remainingBits = bitCount % 8
        guard bytes.prefix(fullByteCount).elementsEqual(prefix.prefix(fullByteCount)) else {
            return false
        }
        guard remainingBits > 0 else { return true }
        guard prefix.count > fullByteCount else { return false }

        let mask = UInt8.max << (8 - remainingBits)
        return bytes[fullByteCount] & mask == prefix[fullByteCount] & mask
    }
}
