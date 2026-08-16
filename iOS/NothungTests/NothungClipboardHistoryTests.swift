import Foundation
@testable import Nothung
import XCTest

final class NothungClipboardHistoryTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NothungClipboardHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directoryURL,
           FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        directoryURL = nil
    }

    func testRecordKeepsOriginalAndCleanedText() throws {
        let date = Date(timeIntervalSince1970: 42)
        let entry = try NothungClipboardHistoryStorage.record(
            original: "https://example.com/?utm_source=x&id=1",
            cleaned: "https://example.com/?id=1",
            capturedAt: date,
            directoryURL: directoryURL
        )

        XCTAssertEqual(
            NothungClipboardHistoryStorage.load(directoryURL: directoryURL),
            [entry]
        )
        XCTAssertEqual(entry.capturedAt, date)
    }

    func testDuplicateOriginalOrCleanedValueMovesToFront() throws {
        _ = try NothungClipboardHistoryStorage.record(
            original: "https://example.com/?utm_source=first",
            cleaned: "https://example.com/",
            directoryURL: directoryURL
        )
        _ = try NothungClipboardHistoryStorage.record(
            original: "https://other.example/",
            cleaned: "https://other.example/",
            directoryURL: directoryURL
        )
        let replacement = try NothungClipboardHistoryStorage.record(
            original: "https://example.com/?utm_source=second",
            cleaned: "https://example.com/",
            directoryURL: directoryURL
        )

        let entries = NothungClipboardHistoryStorage.load(directoryURL: directoryURL)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first, replacement)
    }

    func testHistoryIsLimitedToTwentyEntries() throws {
        for index in 0..<(NothungClipboardHistoryStorage.maximumEntryCount + 4) {
            try NothungClipboardHistoryStorage.record(
                original: "https://example.com/\(index)?utm_source=test",
                cleaned: "https://example.com/\(index)",
                directoryURL: directoryURL
            )
        }

        let entries = NothungClipboardHistoryStorage.load(directoryURL: directoryURL)
        XCTAssertEqual(entries.count, NothungClipboardHistoryStorage.maximumEntryCount)
        XCTAssertEqual(entries.first?.cleaned, "https://example.com/23")
        XCTAssertEqual(entries.last?.cleaned, "https://example.com/4")
    }

    func testRemoveAndClear() throws {
        let first = try NothungClipboardHistoryStorage.record(
            original: "https://one.example/",
            cleaned: "https://one.example/",
            directoryURL: directoryURL
        )
        _ = try NothungClipboardHistoryStorage.record(
            original: "https://two.example/",
            cleaned: "https://two.example/",
            directoryURL: directoryURL
        )

        try NothungClipboardHistoryStorage.remove(
            id: first.id,
            directoryURL: directoryURL
        )
        XCTAssertEqual(
            NothungClipboardHistoryStorage.load(directoryURL: directoryURL).map(\.cleaned),
            ["https://two.example/"]
        )

        try NothungClipboardHistoryStorage.clear(directoryURL: directoryURL)
        XCTAssertTrue(
            NothungClipboardHistoryStorage.load(directoryURL: directoryURL).isEmpty
        )
    }

    func testCorruptHistoryFailsClosed() throws {
        try Data("not json".utf8).write(
            to: directoryURL.appendingPathComponent("NothungClipboardHistory.json")
        )

        XCTAssertTrue(
            NothungClipboardHistoryStorage.load(directoryURL: directoryURL).isEmpty
        )
    }
}
