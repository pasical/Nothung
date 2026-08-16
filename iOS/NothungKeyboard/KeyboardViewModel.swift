import Combine
import Foundation
import UIKit

@MainActor
final class KeyboardViewModel: ObservableObject {
    @Published private(set) var entries: [NothungClipboardEntry] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var hasFullAccess = false
    @Published var revealedEntry: NothungClipboardEntry?
    @Published var isEditorPresented = false
    @Published var editorText = ""
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private var lastCapturedClipboard: String?

    func reload(hasFullAccess: Bool) {
        self.hasFullAccess = hasFullAccess
        entries = NothungClipboardHistoryStorage.load()
        if let revealedEntry,
           !entries.contains(where: { $0.id == revealedEntry.id }) {
            self.revealedEntry = nil
        }
    }

    func captureSystemClipboard() async {
        guard hasFullAccess,
              let raw = Self.systemClipboardText() else {
            return
        }

        if raw == lastCapturedClipboard
            || entries.contains(where: { $0.original == raw }) {
            lastCapturedClipboard = raw
            return
        }

        if await processAndRecord(
            raw,
            message: "检测到新剪贴板，正在清理…"
        ) != nil {
            lastCapturedClipboard = raw
        }
    }

    func cleanSystemClipboardForInsertion() async -> String? {
        guard hasFullAccess else {
            failPaste("请先为 Nothung 开启完全访问。")
            return nil
        }
        guard let raw = Self.systemClipboardText() else {
            failPaste("剪贴板里没有可粘贴的文本。")
            return nil
        }

        let cleaned = await processAndRecord(
            raw,
            message: "正在清理并粘贴…"
        )
        if cleaned != nil {
            lastCapturedClipboard = raw
        }
        return cleaned
    }

    func beginManualEntry() {
        revealedEntry = nil
        editorText = ""
        statusMessage = nil
        errorMessage = nil
        isEditorPresented = true
    }

    func submitManualEntry() async {
        let raw = editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            errorMessage = "请输入要手动加入 Nothung 剪贴板的内容。"
            return
        }
        if await processAndRecord(raw, message: "正在清理并加入…") != nil {
            editorText = ""
            isEditorPresented = false
        }
    }

    func dismissManualEntry() {
        editorText = ""
        isEditorPresented = false
        statusMessage = nil
        errorMessage = nil
    }

    func markInserted() {
        statusMessage = "已插入清理后的内容。"
        errorMessage = nil
    }

    func failPaste(_ message: String) {
        isProcessing = false
        statusMessage = nil
        errorMessage = message
    }

    func remove(_ entry: NothungClipboardEntry) {
        do {
            try NothungClipboardHistoryStorage.remove(id: entry.id)
            if revealedEntry?.id == entry.id { revealedEntry = nil }
            entries = NothungClipboardHistoryStorage.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func processAndRecord(
        _ raw: String,
        message: String
    ) async -> String? {
        guard raw.count <= NothungCleaningService.maximumInputLength else {
            failPaste("内容超过 \(NothungCleaningService.maximumInputLength) 个字符，请缩短后再试。")
            return nil
        }

        isProcessing = true
        statusMessage = message
        errorMessage = nil

        do {
            var output = Self.outputForClipboard(raw)

            if hasFullAccess,
               let url = NothungCleaningService.singleWebURL(in: output),
               NothungRuleStorage.load().allowsRedirectExpansion(for: url) {
                statusMessage = "命中短链规则，正在联网展开…"
                do {
                    let resolution = try await RedirectResolver(
                        configuration: .init(
                            requestTimeout: 5,
                            overallTimeout: 12
                        )
                    ).resolve(url)
                    if resolution.didRedirect {
                        output = try NothungCleaningService.replacingSingleWebURL(
                            in: output,
                            with: resolution.finalURL
                        )
                    }
                } catch {
                    // Local cleaning is still useful when a short link cannot be resolved.
                }
            }

            try Task.checkCancellation()
            try NothungClipboardHistoryStorage.record(
                original: raw,
                cleaned: output.cleaned
            )
            entries = NothungClipboardHistoryStorage.load()
            isProcessing = false
            statusMessage = "已加入 Nothung 剪贴板。"
            errorMessage = nil
            return output.cleaned
        } catch is CancellationError {
            isProcessing = false
            return nil
        } catch {
            isProcessing = false
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private static func outputForClipboard(
        _ raw: String
    ) -> NothungCleaningOutput {
        if let cleaned = try? NothungCleaningService.clean(raw) {
            return cleaned
        }

        return NothungCleaningOutput(
            original: raw,
            cleaned: raw,
            removedFields: [],
            appliedRegexRuleIdentifiers: [],
            didChange: false,
            detectedURLCount: 0,
            inputKind: .text
        )
    }

    private static func systemClipboardText() -> String? {
        let pasteboard = UIPasteboard.general
        let candidates: [String?] = [
            pasteboard.string,
            pasteboard.url?.absoluteString,
            pasteboard.strings?.first,
            pasteboard.urls?.first?.absoluteString,
        ]

        for candidate in candidates {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty {
                return text
            }
        }
        return nil
    }

}
