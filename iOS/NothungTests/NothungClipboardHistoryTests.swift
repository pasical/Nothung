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
        XCTAssertFalse(entry.isPinned)
    }

    func testLegacyEntryWithoutPinnedFieldDecodesAsUnpinned() throws {
        struct LegacyEntry: Encodable {
            let id: UUID
            let original: String
            let cleaned: String
            let capturedAt: Date
        }

        let legacy = LegacyEntry(
            id: UUID(),
            original: "https://example.com/?utm_source=legacy",
            cleaned: "https://example.com/",
            capturedAt: Date(timeIntervalSince1970: 42)
        )
        try JSONEncoder().encode([legacy]).write(
            to: directoryURL.appendingPathComponent("NothungClipboardHistory.json")
        )

        let entries = NothungClipboardHistoryStorage.load(directoryURL: directoryURL)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, legacy.id)
        XCTAssertFalse(try XCTUnwrap(entries.first).isPinned)
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

    func testPinnedEntriesAreShownFirstAndCanBeToggled() throws {
        let oldest = try NothungClipboardHistoryStorage.record(
            original: "https://oldest.example/",
            cleaned: "https://oldest.example/",
            capturedAt: Date(timeIntervalSince1970: 1),
            directoryURL: directoryURL
        )
        let newest = try NothungClipboardHistoryStorage.record(
            original: "https://newest.example/",
            cleaned: "https://newest.example/",
            capturedAt: Date(timeIntervalSince1970: 2),
            directoryURL: directoryURL
        )

        let pinned = try XCTUnwrap(
            NothungClipboardHistoryStorage.setPinned(
                id: oldest.id,
                isPinned: true,
                directoryURL: directoryURL
            )
        )
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(
            NothungClipboardHistoryStorage.load(directoryURL: directoryURL).map(\.id),
            [oldest.id, newest.id]
        )

        let unpinned = try XCTUnwrap(
            NothungClipboardHistoryStorage.togglePinned(
                id: oldest.id,
                directoryURL: directoryURL
            )
        )
        XCTAssertFalse(unpinned.isPinned)
        XCTAssertEqual(
            NothungClipboardHistoryStorage.load(directoryURL: directoryURL).map(\.id),
            [newest.id, oldest.id]
        )
    }

    func testDuplicateRecordingPreservesPinnedState() throws {
        let original = try NothungClipboardHistoryStorage.record(
            original: "https://example.com/?utm_source=first",
            cleaned: "https://example.com/",
            capturedAt: Date(timeIntervalSince1970: 1),
            directoryURL: directoryURL
        )
        try NothungClipboardHistoryStorage.setPinned(
            id: original.id,
            isPinned: true,
            directoryURL: directoryURL
        )

        let replacement = try NothungClipboardHistoryStorage.record(
            original: "https://example.com/?utm_source=second",
            cleaned: "https://example.com/",
            capturedAt: Date(timeIntervalSince1970: 2),
            directoryURL: directoryURL
        )

        let entries = NothungClipboardHistoryStorage.load(directoryURL: directoryURL)
        XCTAssertTrue(replacement.isPinned)
        XCTAssertEqual(entries, [replacement])
        XCTAssertNotEqual(replacement.id, original.id)
    }

    func testLimitEvictsUnpinnedEntriesBeforePinnedEntries() throws {
        var oldestEntry: NothungClipboardEntry?
        for index in 0..<NothungClipboardHistoryStorage.maximumEntryCount {
            let entry = try NothungClipboardHistoryStorage.record(
                original: "https://example.com/\(index)?utm_source=test",
                cleaned: "https://example.com/\(index)",
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                directoryURL: directoryURL
            )
            if index == 0 { oldestEntry = entry }
        }
        let oldest = try XCTUnwrap(oldestEntry)
        try NothungClipboardHistoryStorage.setPinned(
            id: oldest.id,
            isPinned: true,
            directoryURL: directoryURL
        )

        for index in 20..<24 {
            try NothungClipboardHistoryStorage.record(
                original: "https://example.com/\(index)?utm_source=test",
                cleaned: "https://example.com/\(index)",
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                directoryURL: directoryURL
            )
        }

        let entries = NothungClipboardHistoryStorage.load(directoryURL: directoryURL)
        XCTAssertEqual(entries.count, NothungClipboardHistoryStorage.maximumEntryCount)
        XCTAssertEqual(entries.first?.id, oldest.id)
        XCTAssertTrue(try XCTUnwrap(entries.first).isPinned)
        XCTAssertFalse(entries.contains { $0.cleaned == "https://example.com/1" })
    }

    func testRecordingFailsClearlyWhenAllTwentyEntriesArePinned() throws {
        for index in 0..<NothungClipboardHistoryStorage.maximumEntryCount {
            let entry = try NothungClipboardHistoryStorage.record(
                original: "https://example.com/\(index)",
                cleaned: "https://example.com/\(index)",
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                directoryURL: directoryURL
            )
            try NothungClipboardHistoryStorage.setPinned(
                id: entry.id,
                isPinned: true,
                directoryURL: directoryURL
            )
        }

        XCTAssertThrowsError(
            try NothungClipboardHistoryStorage.record(
                original: "https://new.example/",
                cleaned: "https://new.example/",
                capturedAt: Date(timeIntervalSince1970: 100),
                directoryURL: directoryURL
            )
        ) { error in
            guard case NothungClipboardHistoryStorage.StorageError
                .capacityReservedByPinnedEntries = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let entries = NothungClipboardHistoryStorage.load(directoryURL: directoryURL)
        XCTAssertEqual(entries.count, NothungClipboardHistoryStorage.maximumEntryCount)
        XCTAssertTrue(entries.allSatisfy(\.isPinned))
        XCTAssertFalse(entries.contains { $0.cleaned == "https://new.example/" })
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
