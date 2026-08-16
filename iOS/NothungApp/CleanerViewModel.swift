import Combine
import Foundation
import UIKit

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var output: NothungCleaningOutput?
    @Published private(set) var errorMessage: String?
    @Published private(set) var copied = false
    @Published private(set) var isExpandingRedirects = false
    @Published private(set) var redirectHops: [RedirectHop] = []
    @Published private(set) var redirectMessage: String?
    @Published private(set) var redirectErrorMessage: String?

    private var activeRedirectRequestID: UUID?
    private var redirectTask: Task<RedirectResolution, Error>?
    private let redirectResolver: any RedirectResolving
    private var historySourceInput: String?

    init(redirectResolver: any RedirectResolving = RedirectResolver()) {
        self.redirectResolver = redirectResolver
    }

    var canClean: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canExpandRedirects: Bool {
        guard !isExpandingRedirects,
              let output,
              let url = NothungCleaningService.singleWebURL(in: output) else {
            return false
        }
        let configuration = NothungRuleStorage.load()
        return !configuration.restrictRedirectExpansionToRules
            || configuration.allowsRedirectExpansion(for: url)
    }

    func acceptPaste(_ values: [String]) {
        guard let first = values.first else { return }
        historySourceInput = first
        input = first
        invalidateOutput()
        if NothungRuleStorage.load().cleanImmediatelyAfterPaste {
            clean()
        }
    }

    func inputDidChange() {
        if input != historySourceInput {
            historySourceInput = nil
        }
        invalidateOutput()
    }

    func clean() {
        resetRedirectState()
        guard canClean else {
            errorMessage = "请先粘贴 URL 或输入包含链接的文本。"
            output = nil
            return
        }

        do {
            output = try NothungCleaningService.clean(input)
            errorMessage = nil
            if let output { recordInHistory(output) }
            let configuration = NothungRuleStorage.load()
            let shouldAutomaticallyExpand = output
                .flatMap(NothungCleaningService.singleWebURL(in:))
                .map(configuration.allowsRedirectExpansion(for:)) == true

            if shouldAutomaticallyExpand {
                Task {
                    await expandRedirects(copyWhenFinished: configuration.copyAfterCleaning)
                }
            } else if configuration.copyAfterCleaning {
                copyOutput()
            }
        } catch {
            output = nil
            errorMessage = "无法清理这段内容：\(error.localizedDescription)"
        }
    }

    func invalidateOutput() {
        output = nil
        errorMessage = nil
        copied = false
        resetRedirectState()
    }

    func clear() {
        input = ""
        historySourceInput = nil
        invalidateOutput()
    }

    func copyOutput() {
        guard let output else { return }
        UIPasteboard.general.string = output.cleaned
        recordInHistory(output, force: true)
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.copied = false
        }
    }

    /// Performs the only network-enabled operation in the app.
    ///
    /// The view presents a disclosure before calling this method. The Action
    /// Extension and App Intent never invoke it and remain local-only.
    func expandRedirects(copyWhenFinished: Bool = false) async {
        guard canExpandRedirects,
              let startingOutput = output,
              let startingURL = NothungCleaningService.singleWebURL(
                in: startingOutput
              ) else {
            return
        }

        let requestID = UUID()
        activeRedirectRequestID = requestID
        isExpandingRedirects = true
        redirectHops = []
        redirectMessage = nil
        redirectErrorMessage = nil

        defer {
            if activeRedirectRequestID == requestID {
                isExpandingRedirects = false
                activeRedirectRequestID = nil
                redirectTask = nil
            }
        }

        do {
            let task = Task {
                try await redirectResolver.resolve(startingURL)
            }
            redirectTask = task
            let resolution = try await task.value
            guard activeRedirectRequestID == requestID else { return }

            redirectHops = resolution.hops
            guard resolution.didRedirect else {
                redirectMessage = "没有发现重定向；当前链接已经是最终地址。"
                if copyWhenFinished { copyOutput() }
                return
            }

            let finalOutput = try NothungCleaningService.replacingSingleWebURL(
                in: startingOutput,
                with: resolution.finalURL
            )
            guard activeRedirectRequestID == requestID else { return }

            let combinedFields = (startingOutput.removedFields + finalOutput.removedFields)
                .enumerated()
                .map { index, field in
                    NothungRemovedField(
                        id: index,
                        name: field.name,
                        value: field.value
                    )
                }

            output = NothungCleaningOutput(
                original: startingOutput.original,
                cleaned: finalOutput.cleaned,
                removedFields: combinedFields,
                appliedRegexRuleIdentifiers:
                    startingOutput.appliedRegexRuleIdentifiers
                    + finalOutput.appliedRegexRuleIdentifiers,
                didChange: finalOutput.cleaned != startingOutput.original,
                detectedURLCount: finalOutput.detectedURLCount,
                inputKind: finalOutput.inputKind
            )
            if let output { recordInHistory(output) }
            redirectMessage = "已展开 \(resolution.hops.count) 次重定向，并再次清理最终地址。"
            if copyWhenFinished { copyOutput() }
        } catch is CancellationError {
            // Input changes invalidate the request silently; an explicit task
            // cancellation should not replace a valid local cleaning result.
        } catch {
            guard activeRedirectRequestID == requestID else { return }
            redirectErrorMessage = error.localizedDescription
            if copyWhenFinished { copyOutput() }
        }
    }

    private func resetRedirectState() {
        redirectTask?.cancel()
        redirectTask = nil
        activeRedirectRequestID = nil
        isExpandingRedirects = false
        redirectHops = []
        redirectMessage = nil
        redirectErrorMessage = nil
    }

    private func recordInHistory(
        _ output: NothungCleaningOutput,
        force: Bool = false
    ) {
        guard force || historySourceInput == input else { return }
        _ = try? NothungClipboardHistoryStorage.record(
            original: historySourceInput ?? input,
            cleaned: output.cleaned
        )
    }
}
