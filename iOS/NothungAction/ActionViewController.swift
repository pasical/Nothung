import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ActionViewController: UIViewController {
    private let model = ActionExtensionViewModel()
    private var hostingController: UIHostingController<ActionRootView>?
    private var copiedValue: String?

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

        Task { [weak self] in
            guard let self else { return }
            do {
                let input = try await ExtensionInputLoader.firstSharedText(from: extensionContext)
                model.updateProgress(String(localized: "正在本地清理…"))
                var output = try NothungCleanCopyWorkflow.run(input) { _ in }

                if let url = NothungCleaningService.singleWebURL(in: output),
                   NothungRuleStorage.load().allowsRedirectExpansion(for: url) {
                    model.updateProgress(String(localized: "已命中短链规则，正在联网展开…"))
                    let resolution = try await RedirectResolver().resolve(url)
                    if resolution.didRedirect {
                        output = try NothungCleaningService.replacingSingleWebURL(
                            in: output,
                            with: resolution.finalURL
                        )
                    }
                }

                model.updateProgress(String(localized: "正在写入剪贴板…"))
                try await writeClipboard(output.cleaned)
                _ = try? NothungClipboardHistoryStorage.record(
                    original: input,
                    cleaned: output.cleaned
                )
                copiedValue = output.cleaned
                model.markCopied()
            } catch {
                model.fail(error.localizedDescription)
            }
        }
    }

    private func completeCopyRequest() {
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
            let previousChangeCount = pasteboard.changeCount
            pasteboard.setItems([item], options: [.localOnly: true])
            try await Task.sleep(nanoseconds: 300_000_000)

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
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: error)
    }
}

private enum ClipboardWriteError: LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        String(localized: "系统连续三次没有确认剪贴板写入；原剪贴板未被覆盖，请重试。")
    }
}
