import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    private let model = KeyboardViewModel()
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var clipboardTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?
    private var clipboardTimer: Timer?
    private var observedPasteboardChangeCount: Int?
    private var displayedInputModeSwitchKey: Bool?

    private let keyFeedback = UIImpactFeedbackGenerator(style: .soft)
    private let deleteFeedback = UIImpactFeedbackGenerator(style: .rigid)
    private let cursorFeedback = UISelectionFeedbackGenerator()

    var enableInputClicksWhenVisible: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.isOpaque = false

        let rootView = makeRootView(
            showsInputModeSwitchKey: needsInputModeSwitchKey
        )
        displayedInputModeSwitchKey = needsInputModeSwitchKey

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController

        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 318)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
    }

    private func makeRootView(
        showsInputModeSwitchKey: Bool
    ) -> KeyboardRootView {
        KeyboardRootView(
            model: model,
            onInsert: { [weak self] entry in
                self?.insert(entry)
            },
            onInsertText: { [weak self] text in
                self?.insertText(text)
            },
            onDelete: { [weak self] in
                self?.deleteBackward()
            },
            onMoveCursor: { [weak self] offset in
                self?.moveCursor(by: offset)
            },
            onPasteCurrentClipboard: { [weak self] in
                self?.pasteCurrentClipboard()
            },
            onCleanSelectedText: { [weak self] in
                self?.cleanSelectedText()
            },
            onInterfaceAction: { [weak self] in
                self?.performInterfaceFeedback()
            },
            showsInputModeSwitchKey: showsInputModeSwitchKey,
            onAdvanceToNextInputMode: { [weak self] in
                self?.advanceInputModeWithFeedback()
            },
            onDismissKeyboard: { [weak self] in
                self?.dismissWithFeedback()
            }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateInputModeSwitchKeyIfNeeded()
        model.reload(hasFullAccess: hasFullAccess)
        prepareFeedback()
        startClipboardMonitoring()
    }

    override func viewDidDisappear(_ animated: Bool) {
        stopClipboardMonitoring()
        pasteTask?.cancel()
        pasteTask = nil
        super.viewDidDisappear(animated)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateInputModeSwitchKeyIfNeeded()
    }

    private func insert(_ entry: NothungClipboardEntry) {
        textDocumentProxy.insertText(entry.cleaned)
        UIDevice.current.playInputClick()
        keyFeedback.impactOccurred(intensity: 0.72)
        keyFeedback.prepare()
        model.markInserted()
    }

    private func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
        UIDevice.current.playInputClick()
        keyFeedback.impactOccurred(intensity: 0.58)
        keyFeedback.prepare()
    }

    private func deleteBackward() {
        textDocumentProxy.deleteBackward()
        UIDevice.current.playInputClick()
        deleteFeedback.impactOccurred(intensity: 0.66)
        deleteFeedback.prepare()
    }

    private func moveCursor(by offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        UIDevice.current.playInputClick()
        cursorFeedback.selectionChanged()
        cursorFeedback.prepare()
    }

    private func performInterfaceFeedback() {
        keyFeedback.impactOccurred(intensity: 0.5)
        keyFeedback.prepare()
    }

    private func dismissWithFeedback() {
        performInterfaceFeedback()
        dismissKeyboard()
    }

    private func advanceInputModeWithFeedback() {
        performInterfaceFeedback()
        advanceToNextInputMode()
    }

    private func updateInputModeSwitchKeyIfNeeded() {
        let shouldShow = needsInputModeSwitchKey
        guard displayedInputModeSwitchKey != shouldShow else { return }
        displayedInputModeSwitchKey = shouldShow
        hostingController?.rootView = makeRootView(
            showsInputModeSwitchKey: shouldShow
        )
    }

    private func prepareFeedback() {
        keyFeedback.prepare()
        deleteFeedback.prepare()
        cursorFeedback.prepare()
    }

    private func startClipboardMonitoring() {
        stopClipboardMonitoring()
        guard hasFullAccess,
              NothungRuleStorage.load().automaticallyCaptureClipboard else {
            return
        }

        observedPasteboardChangeCount = nil
        captureClipboardIfChanged()

        let timer = Timer(
            timeInterval: 0.7,
            target: self,
            selector: #selector(pollClipboard),
            userInfo: nil,
            repeats: true
        )
        clipboardTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        clipboardTask?.cancel()
        clipboardTask = nil
        observedPasteboardChangeCount = nil
    }

    @objc private func pollClipboard() {
        captureClipboardIfChanged()
    }

    private func captureClipboardIfChanged() {
        guard hasFullAccess else {
            stopClipboardMonitoring()
            model.reload(hasFullAccess: false)
            return
        }
        guard NothungRuleStorage.load().automaticallyCaptureClipboard else {
            stopClipboardMonitoring()
            model.reload(hasFullAccess: true)
            return
        }

        let changeCount = UIPasteboard.general.changeCount
        guard changeCount != observedPasteboardChangeCount else { return }
        observedPasteboardChangeCount = changeCount

        clipboardTask?.cancel()
        clipboardTask = Task { [weak self] in
            await self?.model.captureSystemClipboard()
        }
    }

    private func pasteCurrentClipboard() {
        pasteTask?.cancel()
        pasteTask = Task { [weak self] in
            guard let self,
                  let cleaned = await self.model.cleanSystemClipboardForInsertion() else {
                return
            }

            self.textDocumentProxy.insertText(cleaned)
            UIDevice.current.playInputClick()
            self.keyFeedback.impactOccurred(intensity: 0.72)
            self.keyFeedback.prepare()
            self.model.markInserted(preservingErrorMessage: true)
        }
    }

    private func cleanSelectedText() {
        guard let cleaned = model.cleanSelectedTextForInsertion(
            textDocumentProxy.selectedText
        ) else {
            return
        }

        textDocumentProxy.insertText(cleaned)
        UIDevice.current.playInputClick()
        keyFeedback.impactOccurred(intensity: 0.72)
        keyFeedback.prepare()
    }
}
