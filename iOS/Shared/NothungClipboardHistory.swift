import Foundation

struct NothungClipboardEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let original: String
    let cleaned: String
    let capturedAt: Date
    let isPinned: Bool

    init(
        id: UUID = UUID(),
        original: String,
        cleaned: String,
        capturedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.original = original
        self.cleaned = cleaned
        self.capturedAt = capturedAt
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case original
        case cleaned
        case capturedAt
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        original = try container.decode(String.self, forKey: .original)
        cleaned = try container.decode(String.self, forKey: .cleaned)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(original, forKey: .original)
        try container.encode(cleaned, forKey: .cleaned)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(isPinned, forKey: .isPinned)
    }
}

enum NothungClipboardHistoryStorage {
    static let maximumEntryCount = 20

    enum StorageError: LocalizedError {
        case directoryUnavailable
        case invalidEntry
        case capacityReservedByPinnedEntries

        var errorDescription: String? {
            switch self {
            case .directoryUnavailable:
                return String(localized: "无法访问 Nothung 的本地剪贴板集合。")
            case .invalidEntry:
                return String(localized: "这条内容为空或过长，不能加入剪贴板集合。")
            case .capacityReservedByPinnedEntries:
                return String(localized: "剪贴板集合已被 20 条固定内容占满，请先取消固定或删除一条。")
            }
        }
    }

    static func load(directoryURL: URL? = nil) -> [NothungClipboardEntry] {
        guard let directory = historyDirectoryURL(directoryURL),
              FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        var entries: [NothungClipboardEntry] = []
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: directory,
            options: [],
            error: &coordinationError
        ) { coordinatedDirectory in
            entries = read(
                from: historyFileURL(in: coordinatedDirectory)
            )
        }
        guard coordinationError == nil else { return [] }
        return entries
    }

    @discardableResult
    static func record(
        original: String,
        cleaned: String,
        capturedAt: Date = Date(),
        directoryURL: URL? = nil
    ) throws -> NothungClipboardEntry {
        guard !original.isEmpty,
              !cleaned.isEmpty,
              original.count <= NothungCleaningService.maximumInputLength,
              cleaned.count <= NothungCleaningService.maximumInputLength else {
            throw StorageError.invalidEntry
        }

        var newEntry = NothungClipboardEntry(
            original: original,
            cleaned: cleaned,
            capturedAt: capturedAt
        )

        guard let directory = historyDirectoryURL(directoryURL) else {
            throw StorageError.directoryUnavailable
        }
        try prepareDirectory(directory)
        try coordinateMutation(in: directory) { coordinatedDirectory in
            let fileURL = historyFileURL(in: coordinatedDirectory)
            var entries = read(from: fileURL)
            let shouldRemainPinned = entries.contains {
                ($0.original == original || $0.cleaned == cleaned) && $0.isPinned
            }
            if shouldRemainPinned {
                newEntry = NothungClipboardEntry(
                    original: original,
                    cleaned: cleaned,
                    capturedAt: capturedAt,
                    isPinned: true
                )
            }
            entries.removeAll {
                $0.original == original || $0.cleaned == cleaned
            }
            if !newEntry.isPinned,
               entries.count >= maximumEntryCount,
               entries.allSatisfy(\.isPinned) {
                throw StorageError.capacityReservedByPinnedEntries
            }
            entries.insert(newEntry, at: 0)
            try write(orderedAndLimited(entries), to: fileURL)
        }
        return newEntry
    }

    @discardableResult
    static func setPinned(
        id: UUID,
        isPinned: Bool,
        directoryURL: URL? = nil
    ) throws -> NothungClipboardEntry? {
        guard let directory = historyDirectoryURL(directoryURL) else {
            throw StorageError.directoryUnavailable
        }

        var updatedEntry: NothungClipboardEntry?
        try prepareDirectory(directory)
        try coordinateMutation(in: directory) { coordinatedDirectory in
            let fileURL = historyFileURL(in: coordinatedDirectory)
            var entries = read(from: fileURL)
            guard let index = entries.firstIndex(where: { $0.id == id }) else {
                return
            }

            let entry = entries[index]
            let replacement = NothungClipboardEntry(
                id: entry.id,
                original: entry.original,
                cleaned: entry.cleaned,
                capturedAt: entry.capturedAt,
                isPinned: isPinned
            )
            entries[index] = replacement
            updatedEntry = replacement
            try write(orderedAndLimited(entries), to: fileURL)
        }
        return updatedEntry
    }

    @discardableResult
    static func togglePinned(
        id: UUID,
        directoryURL: URL? = nil
    ) throws -> NothungClipboardEntry? {
        guard let directory = historyDirectoryURL(directoryURL) else {
            throw StorageError.directoryUnavailable
        }

        var updatedEntry: NothungClipboardEntry?
        try prepareDirectory(directory)
        try coordinateMutation(in: directory) { coordinatedDirectory in
            let fileURL = historyFileURL(in: coordinatedDirectory)
            var entries = read(from: fileURL)
            guard let index = entries.firstIndex(where: { $0.id == id }) else {
                return
            }

            let entry = entries[index]
            let replacement = NothungClipboardEntry(
                id: entry.id,
                original: entry.original,
                cleaned: entry.cleaned,
                capturedAt: entry.capturedAt,
                isPinned: !entry.isPinned
            )
            entries[index] = replacement
            updatedEntry = replacement
            try write(orderedAndLimited(entries), to: fileURL)
        }
        return updatedEntry
    }

    static func remove(id: UUID, directoryURL: URL? = nil) throws {
        guard let directory = historyDirectoryURL(directoryURL) else {
            throw StorageError.directoryUnavailable
        }
        try prepareDirectory(directory)
        try coordinateMutation(in: directory) { coordinatedDirectory in
            let fileURL = historyFileURL(in: coordinatedDirectory)
            var entries = read(from: fileURL)
            entries.removeAll { $0.id == id }
            try write(entries, to: fileURL)
        }
    }

    static func clear(directoryURL: URL? = nil) throws {
        guard let directory = historyDirectoryURL(directoryURL) else {
            throw StorageError.directoryUnavailable
        }
        try prepareDirectory(directory)
        try coordinateMutation(in: directory) { coordinatedDirectory in
            let fileURL = historyFileURL(in: coordinatedDirectory)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    static var usesSharedContainer: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: NothungRuleStorage.appGroupIdentifier
        ) != nil
    }

    private static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    private static func coordinateMutation(
        in directory: URL,
        _ mutation: (URL) throws -> Void
    ) throws {
        var mutationError: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: directory,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedDirectory in
            do {
                try mutation(coordinatedDirectory)
            } catch {
                mutationError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let mutationError { throw mutationError }
    }

    private static func read(from fileURL: URL) -> [NothungClipboardEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode(
                  [NothungClipboardEntry].self,
                  from: data
              ) else {
            return []
        }
        return orderedAndLimited(entries)
    }

    private static func orderedAndLimited(
        _ entries: [NothungClipboardEntry]
    ) -> [NothungClipboardEntry] {
        let ordered = entries.enumerated().sorted { lhs, rhs in
            if lhs.element.isPinned != rhs.element.isPinned {
                return lhs.element.isPinned
            }
            if lhs.element.capturedAt != rhs.element.capturedAt {
                return lhs.element.capturedAt > rhs.element.capturedAt
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        return Array(ordered.prefix(maximumEntryCount))
    }

    private static func write(
        _ entries: [NothungClipboardEntry],
        to fileURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entries).write(to: fileURL, options: .atomic)

        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
        #endif
    }

    private static func historyFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(
            "NothungClipboardHistory.json",
            isDirectory: false
        )
    }

    private static func historyDirectoryURL(_ directoryURL: URL?) -> URL? {
        directoryURL ?? defaultDirectoryURL
    }

    private static var defaultDirectoryURL: URL? {
        if let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: NothungRuleStorage.appGroupIdentifier
        ) {
            return shared.appendingPathComponent("Clipboard", isDirectory: true)
        }

        // This private-container fallback keeps the keyboard useful in local
        // development builds whose provisioning profile lacks App Groups.
        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("Nothung/Clipboard", isDirectory: true)
    }
}
