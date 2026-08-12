import Foundation
@testable import Nothung
import XCTest

final class RedirectResolverTests: XCTestCase {
    func testHTTPInitialURLIsRejectedBeforeHostValidationOrRequest() async throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:9/path"))

        await assertResolution(of: url, failsWith: .insecureInitialURL(url))
    }

    func testNonHTTPInitialSchemeIsRejected() async throws {
        let url = try XCTUnwrap(URL(string: "ftp://127.0.0.1/resource"))

        await assertResolution(
            of: url,
            failsWith: .unsupportedInitialScheme("ftp")
        )
    }

    func testEmbeddedUserInfoIsRejectedBeforeHostResolution() async throws {
        let url = try XCTUnwrap(
            URL(string: "https://username:password@127.0.0.1/private")
        )

        await assertResolution(of: url, failsWith: .embeddedCredentials(url))
    }

    func testLocalhostAndMetadataNamesAreBlockedWithoutDNSLookup() async throws {
        let cases: [(url: URL, normalizedHost: String)] = [
            (try XCTUnwrap(URL(string: "https://LOCALHOST./")), "localhost"),
            (try XCTUnwrap(URL(string: "https://metadata.google.internal/")), "metadata.google.internal"),
            (try XCTUnwrap(URL(string: "https://service.internal/")), "service.internal"),
        ]

        for testCase in cases {
            await assertResolution(
                of: testCase.url,
                failsWith: .blockedHost(testCase.normalizedHost)
            )
        }
    }

    func testIPv4LoopbackAndPrivateAddressesAreBlocked() async throws {
        let addresses = [
            "127.0.0.1",
            "10.0.0.8",
            "172.16.0.1",
            "192.168.1.1",
            "169.254.169.254",
            "198.18.1.2",
        ]

        for address in addresses {
            let url = try XCTUnwrap(URL(string: "https://\(address)/"))
            await assertNonPublicAddress(of: url, expectedHost: address)
        }
    }

    func testIPv6LoopbackAddressIsBlocked() async throws {
        let url = try XCTUnwrap(URL(string: "https://[::1]/"))

        await assertResolution(
            of: url,
            failsWith: .nonPublicAddress(
                host: "::1",
                address: "0:0:0:0:0:0:0:1"
            )
        )
    }

    func testIPv4MappedIPv6PrivateAddressIsBlocked() async throws {
        let url = try XCTUnwrap(URL(string: "https://[::ffff:192.168.1.1]/"))

        await assertResolution(
            of: url,
            failsWith: .nonPublicAddress(
                host: "::ffff:192.168.1.1",
                address: "0:0:0:0:0:ffff:c0a8:101"
            )
        )
    }

    func testInvalidTimeoutConfigurationsAreRejectedBeforeURLValidation() async throws {
        let url = try XCTUnwrap(URL(string: "https://127.0.0.1/"))
        let configurations = [
            RedirectResolver.Configuration(requestTimeout: 0.24, overallTimeout: 30),
            RedirectResolver.Configuration(requestTimeout: 61, overallTimeout: 30),
            RedirectResolver.Configuration(requestTimeout: .nan, overallTimeout: 30),
            RedirectResolver.Configuration(requestTimeout: 10, overallTimeout: 0.24),
            RedirectResolver.Configuration(requestTimeout: 10, overallTimeout: 301),
            RedirectResolver.Configuration(requestTimeout: 10, overallTimeout: .infinity),
        ]

        for configuration in configurations {
            await assertResolution(
                of: url,
                using: configuration,
                failsWith: .invalidConfiguration
            )
        }
    }

    private func assertResolution(
        of url: URL,
        using configuration: RedirectResolver.Configuration = .standard,
        failsWith expectedError: RedirectResolverError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await RedirectResolver(configuration: configuration).resolve(url)
            XCTFail("Expected redirect resolution to fail", file: file, line: line)
        } catch let error as RedirectResolverError {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail(
                "Expected RedirectResolverError, received \(String(reflecting: error))",
                file: file,
                line: line
            )
        }
    }

    private func assertNonPublicAddress(
        of url: URL,
        expectedHost: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await RedirectResolver().resolve(url)
            XCTFail("Expected a non-public address failure", file: file, line: line)
        } catch let RedirectResolverError.nonPublicAddress(host, resolvedAddress) {
            XCTAssertEqual(host, expectedHost, file: file, line: line)
            XCTAssertFalse(resolvedAddress.isEmpty, file: file, line: line)
        } catch {
            XCTFail(
                "Expected nonPublicAddress, received \(String(reflecting: error))",
                file: file,
                line: line
            )
        }
    }
}
