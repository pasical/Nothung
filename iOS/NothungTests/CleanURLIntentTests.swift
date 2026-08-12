import Foundation
@testable import Nothung
import XCTest

final class CleanURLIntentTests: XCTestCase {
    func testCleanerReturnsURLWithoutTrackingParameters() throws {
        let input = try XCTUnwrap(
            URL(string: "https://example.com/article?utm_source=test&id=42&fbclid=abc#part")
        )

        let result = try NothungIntentURLCleaner.clean(input)

        XCTAssertEqual(
            result.cleanedURL.absoluteString,
            "https://example.com/article?id=42#part"
        )
        XCTAssertEqual(result.removedParameters.map(\.name), ["utm_source", "fbclid"])
        XCTAssertTrue(result.didChange)
    }

    func testCleanerReturnsAlreadyCleanURLUnchanged() throws {
        let input = try XCTUnwrap(URL(string: "https://example.com/article?id=42#part"))

        let result = try NothungIntentURLCleaner.clean(input)

        XCTAssertEqual(result.cleanedURL, input)
        XCTAssertFalse(result.didChange)
    }

    func testCleanerExplainsUnsupportedScheme() throws {
        let input = try XCTUnwrap(URL(string: "mailto:hello@example.com"))

        XCTAssertThrowsError(try NothungIntentURLCleaner.clean(input)) { error in
            XCTAssertEqual(error as? NothungIntentCleaningError, .unsupportedScheme)
            XCTAssertEqual(
                error.localizedDescription,
                "只支持以 http:// 或 https:// 开头的网页链接。"
            )
        }
    }

    func testCleanerRejectsEmbeddedCredentials() throws {
        let input = try XCTUnwrap(URL(string: "https://name:secret@example.com/path?utm_source=test"))

        XCTAssertThrowsError(try NothungIntentURLCleaner.clean(input)) { error in
            XCTAssertEqual(error as? NothungIntentCleaningError, .embeddedCredentials)
        }
    }

    func testIntentReturnsCleanedURLValue() async throws {
        let intent = CleanURLIntent()
        intent.url = try XCTUnwrap(
            URL(string: "https://example.com/article?utm_source=shortcut&id=42")
        )

        let result = try await intent.perform()

        XCTAssertEqual(result.value?.absoluteString, "https://example.com/article?id=42")
    }
}
