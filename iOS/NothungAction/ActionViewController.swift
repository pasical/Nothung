import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ActionViewController: UIViewController {
    private let model = ActionExtensionViewModel()
    private var hostingController: UIHostingController<ActionRootView>?
    private var copiedValue: String?
    private var workTask: Task<Void, Never>?
    private var clipboardWriteStarted = false
    private var isWritingClipboard = false
    private var closeAfterClipboardWrite = false

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = ActionRootView(
            model: model,
            onCancel: { [weak self] in self?.cancelRequest() },
            onComplete: { [weak self] in self?.completeCopyRequest() },
            onShare: { [weak self] in self?.shareCopiedValue() }
        )
        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        workTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { workTask = nil }
            do {
                let input = try await ExtensionInputLoader.firstSharedText(from: extensionContext)
                try Task.checkCancellation()
                model.updateProgress(String(localized: "正在本地清理…"))
                var output = try NothungCleanCopyWorkflow.run(input) { _ in }

                if let url = NothungCleaningService.singleWebURL(in: output),
                   NothungRuleStorage.load().allowsRedirectExpansion(for: url) {
                    model.updateProgress(String(localized: "已命中短链规则，正在联网展开…"))
                    do {
                        let resolution = try await RedirectResolver().resolve(url)
                        try Task.checkCancellation()
                        if resolution.didRedirect {
                            output = try NothungCleaningService.replacingSingleWebURL(
                                in: output,
                                with: resolution.finalURL
                            )
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Redirect expansion is an optional enhancement. A
                        // network or destination failure must not discard the
                        // already validated, locally cleaned result.
                        try Task.checkCancellation()
                    }
                }

                try Task.checkCancellation()
                model.updateProgress(String(localized: "正在写入剪贴板…"))
                clipboardWriteStarted = true
                isWritingClipboard = true
                do {
                    defer { isWritingClipboard = false }
                    try await writeClipboard(output.cleaned)
                }
                _ = try? NothungClipboardHistoryStorage.record(
                    original: input,
                    cleaned: output.cleaned
                )
                copiedValue = output.cleaned
                model.markCopied()
                if closeAfterClipboardWrite {
                    extensionContext?.completeRequest(returningItems: [])
                }
            } catch is CancellationError {
                return
            } catch {
                isWritingClipboard = false
                if closeAfterClipboardWrite {
                    extensionContext?.completeRequest(returningItems: [])
                    return
                }
                guard !Task.isCancelled else { return }
                model.fail(error.localizedDescription)
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isWritingClipboard {
            closeAfterClipboardWrite = true
            return
        }
        workTask?.cancel()
        workTask = nil
    }

    private func completeCopyRequest() {
        workTask?.cancel()
        workTask = nil
        extensionContext?.completeRequest(returningItems: [])
    }

    private func shareCopiedValue() {
        guard let copiedValue else { return }
        let controller = UIActivityViewController(
            activityItems: [copiedValue],
            applicationActivities: nil
        )
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.maxY - 44,
                width: 1,
                height: 1
            )
        }
        present(controller, animated: true)
    }

    @MainActor
    private func writeClipboard(_ value: String) async throws {
        try Task.checkCancellation()
        let pasteboard = UIPasteboard.general
        let utf8Data = Data(value.utf8)
        let item: [String: Any] = [
            UTType.plainText.identifier: value as NSString,
            UTType.utf8PlainText.identifier: utf8Data as NSData,
        ]

        // Publish eager, concrete representations. Lazy item providers can be
        // torn down with the extension process before pasteboardd materializes
        // their value, which makes an apparently successful copy intermittent.
        for _ in 0..<3 {
            try Task.checkCancellation()
            let previousChangeCount = pasteboard.changeCount
            pasteboard.setItems([item], options: [.localOnly: true])
            try await Task.sleep(nanoseconds: 300_000_000)
            try Task.checkCancellation()

            let committedData = pasteboard.data(
                forPasteboardType: UTType.utf8PlainText.identifier
            )
            if pasteboard.changeCount != previousChangeCount,
               committedData == utf8Data {
                return
            }
        }

        throw ClipboardWriteError.verificationFailed
    }

    private func cancelRequest() {
        if isWritingClipboard {
            closeAfterClipboardWrite = true
            model.updateProgress(String(localized: "正在完成剪贴板写入…"))
            return
        }
        workTask?.cancel()
        workTask = nil
        if clipboardWriteStarted {
            extensionContext?.completeRequest(returningItems: [])
            return
        }
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: error)
    }
}

private enum ClipboardWriteError: LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        String(localized: "系统连续三次没有确认剪贴板写入；剪贴板可能已更新，请检查后重试。")
    }
}
