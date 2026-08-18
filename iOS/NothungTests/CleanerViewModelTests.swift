import Foundation
@testable import Nothung
import XCTest

@MainActor
final class CleanerViewModelTests: XCTestCase {
    func testClearRemovesInputResultAndTransientState() {
        let model = CleanerViewModel()
        model.input = "https://example.com/?utm_source=test"
        model.clean()
        XCTAssertNotNil(model.output)

        model.clear()

        XCTAssertEqual(model.input, "")
        XCTAssertNil(model.output)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.copied)
    }

    func testRedirectResultIsRecleanedAndMergedIntoVisibleOutput() async throws {
        let shortURL = try XCTUnwrap(
            URL(string: "https://short.example/x?fbclid=start")
        )
        let locallyCleanedURL = try XCTUnwrap(
            URL(string: "https://short.example/x")
        )
        let finalURL = try XCTUnwrap(
            URL(string: "https://target.example/story?utm_source=redirect&id=42")
        )
        let resolution = RedirectResolution(
            originalURL: locallyCleanedURL,
            finalURL: finalURL,
            hops: [
                RedirectHop(
                    sourceURL: locallyCleanedURL,
                    destinationURL: finalURL,
                    statusCode: 302
                ),
            ],
            finalStatusCode: 200
        )
        let model = CleanerViewModel(
            redirectResolver: StubRedirectResolver(result: .success(resolution))
        )

        model.input = shortURL.absoluteString
        model.clean()
        await model.expandRedirects()

        XCTAssertEqual(model.output?.original, shortURL.absoluteString)
        XCTAssertEqual(
            model.output?.cleaned,
            "https://target.example/story?id=42"
        )
        XCTAssertEqual(
            model.output?.removedFields.map(\.name),
            ["fbclid", "utm_source"]
        )
        XCTAssertEqual(model.redirectHops, resolution.hops)
        XCTAssertNotNil(model.redirectMessage)
        XCTAssertNil(model.redirectErrorMessage)
        XCTAssertFalse(model.isExpandingRedirects)
    }

    func testRedirectFailurePreservesLocalCleaningResult() async throws {
        let input = try XCTUnwrap(
            URL(string: "https://example.com/path?utm_source=local&id=7")
        )
        let failure = RedirectResolverError.transportFailure(url: input, code: -1)
        let model = CleanerViewModel(
            redirectResolver: StubRedirectResolver(result: .failure(failure))
        )

        model.input = input.absoluteString
        model.clean()
        let localOutput = model.output
        await model.expandRedirects()

        XCTAssertEqual(model.output, localOutput)
        XCTAssertNil(model.redirectMessage)
        XCTAssertEqual(model.redirectErrorMessage, failure.localizedDescription)
        XCTAssertFalse(model.isExpandingRedirects)
    }
}

private struct StubRedirectResolver: RedirectResolving {
    let result: Result<RedirectResolution, RedirectResolverError>

    func resolve(_ url: URL) async throws -> RedirectResolution {
        try result.get()
    }
}
