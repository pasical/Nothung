import SwiftUI
import UIKit

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel

    let onInsert: (NothungClipboardEntry) -> Void
    let onInsertText: (String) -> Void
    let onDelete: () -> Void
    let onMoveCursor: (Int) -> Void
    let onPasteCurrentClipboard: () -> Void
    let onCleanSelectedText: () -> Void
    let onInterfaceAction: () -> Void
    let showsInputModeSwitchKey: Bool
    let onAdvanceToNextInputMode: () -> Void
    let onDismissKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isEditorPresented {
                editorActionRow
            } else {
                documentActionRow
            }
        }
        .background {
            KeyboardDeckBackground()
                .clipShape(KeyboardTopShape())
                .padding(.horizontal, 2)
                .ignoresSafeArea(edges: .bottom)
        }
        .clipShape(KeyboardTopShape())
        .tint(NothungPalette.accent)
    }

    private var header: some View {
        HStack(spacing: 8) {
            NothungMark(size: 27)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    model.isEditorPresented
                        ? String(localized: "手动添加")
                        : "NOTHUNG"
                )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(model.isEditorPresented ? 0.2 : 1.5)
                    .foregroundStyle(NothungPalette.ink)

                HStack(spacing: 4) {
                    if model.errorMessage == nil && !model.isEditorPresented {
                        Circle()
                            .fill(model.hasFullAccess ? NothungPalette.accent : KeyboardChrome.warning)
                            .frame(width: 5, height: 5)
                    }

                    Text(headerDetail)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(
                            model.errorMessage == nil
                                ? NothungPalette.muted
                                : Color.red
                        )
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if !model.isEditorPresented {
                Text("\(model.entries.count)/\(NothungClipboardHistoryStorage.maximumEntryCount)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NothungPalette.muted)
                    .padding(.horizontal, 7)
                    .frame(height: 27)
                    .modifier(
                        KeyboardSurface(
                            role: .content,
                            cornerRadius: 13.5,
                            interactive: false
                        )
                    )
            }

            if model.isEditorPresented {
                headerButton(
                    accessibilityLabel: "取消手动添加",
                    action: {
                        onInterfaceAction()
                        model.dismissManualEntry()
                    }
                ) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                }
            } else {
                headerButton(
                    accessibilityLabel: "手动添加剪贴板条目",
                    action: {
                        onInterfaceAction()
                        model.beginManualEntry()
                    }
                ) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            if showsInputModeSwitchKey {
                headerButton(
                    accessibilityLabel: "切换到下一个键盘",
                    action: onAdvanceToNextInputMode
                ) {
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .semibold))
                }
            }

            headerButton(
                accessibilityLabel: "收起键盘",
                action: onDismissKeyboard
            ) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 49)
    }

    private var headerDetail: String {
        if let errorMessage = model.errorMessage {
            return errorMessage
        }
        if let statusMessage = model.statusMessage {
            return statusMessage
        }
        if model.isEditorPresented {
            return String(localized: "输入后清理并加入")
        }
        guard model.hasFullAccess else {
            return String(localized: "离线模式 · 可清理所选链接")
        }
        return model.automaticallyCapturesClipboard
            ? String(localized: "自动捕捉剪贴板")
            : String(localized: "自动捕捉已关闭")
    }

    @ViewBuilder
    private var content: some View {
        if model.isEditorPresented {
            editorView
        } else if let entry = model.revealedEntry {
            originalView(entry)
        } else {
            historyView
        }
    }

    private var historyView: some View {
        Group {
            if model.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8, alignment: .leading),
                            GridItem(.flexible(), spacing: 8, alignment: .leading),
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(model.entries) { entry in
                            historyCard(entry)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptyStateIcon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(NothungPalette.accent)

            Text(
                emptyStateTitle
            )
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(NothungPalette.ink)

            Text(
                emptyStateDetail
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(NothungPalette.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: 286)
        .modifier(
            KeyboardSurface(
                role: .content,
                cornerRadius: 22,
                interactive: false
            )
        )
        .padding(.horizontal, 20)
    }

    private var emptyStateIcon: String {
        guard model.hasFullAccess else { return "wand.and.sparkles" }
        return model.automaticallyCapturesClipboard
            ? "wave.3.right.circle.fill"
            : "pause.circle.fill"
    }

    private var emptyStateTitle: String {
        guard model.hasFullAccess else {
            return String(localized: "选中文本后可本地清理")
        }
        return model.automaticallyCapturesClipboard
            ? String(localized: "等待新的剪贴板")
            : String(localized: "自动捕捉已关闭")
    }

    private var emptyStateDetail: String {
        guard model.hasFullAccess else {
            return String(localized: "在输入框中选中含链接的文本，再点左下角按钮；完全访问仅用于剪贴板与共享历史。")
        }
        return model.automaticallyCapturesClipboard
            ? String(localized: "复制文本后切回这里，会自动清理并加入。")
            : String(localized: "仍可点左下角的粘贴键，或手动添加内容。")
    }

    private func historyCard(_ entry: NothungClipboardEntry) -> some View {
        Button {
            onInsert(entry)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: entry.cleaned.contains("://") ? "link" : "text.alignleft")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NothungPalette.accent)

                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NothungPalette.accent)
                            .accessibilityLabel("已固定")
                    }

                    Spacer(minLength: 0)

                    Text(
                        entry.capturedAt,
                        format: .dateTime
                            .month(.twoDigits)
                            .day(.twoDigits)
                            .hour()
                            .minute()
                    )
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(NothungPalette.muted)
                    .lineLimit(1)
                }

                Text(entry.cleaned)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(NothungPalette.ink)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .modifier(
                KeyboardSurface(
                    role: .content,
                    cornerRadius: 16,
                    interactive: true
                )
            )
        }
        .buttonStyle(KeyboardCardButtonStyle())
        .contextMenu {
            Button {
                onInterfaceAction()
                model.revealedEntry = entry
            } label: {
                Label("显示原文", systemImage: "doc.text.magnifyingglass")
            }

            Button {
                onInterfaceAction()
                model.togglePinned(entry)
            } label: {
                Label(
                    entry.isPinned ? "取消固定" : "固定到顶部",
                    systemImage: entry.isPinned ? "pin.slash" : "pin"
                )
            }

            Button(role: .destructive) {
                onInterfaceAction()
                model.remove(entry)
            } label: {
                Label("删除此条", systemImage: "trash")
            }
        }
    }

    private func originalView(_ entry: NothungClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NothungPhaseLabel(text: "原文")

                Spacer()

                Button("返回记录") {
                    onInterfaceAction()
                    model.revealedEntry = nil
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(NothungPalette.accent)
            }

            ScrollView {
                Text(entry.original)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NothungPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(11)
            .modifier(
                KeyboardSurface(
                    role: .content,
                    cornerRadius: 17,
                    interactive: false
                )
            )

            Button {
                onInsert(entry)
                model.revealedEntry = nil
            } label: {
                Label("插入清理结果", systemImage: "arrow.turn.down.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 40)
            .buttonStyle(KeyboardKeyStyle(role: .primary))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    private var editorView: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                NothungPhaseLabel(text: "内容")

                Spacer()

                Text("\(model.editorText.count) / \(NothungCleaningService.maximumInputLength)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(NothungPalette.muted)
            }

            ZStack(alignment: .topLeading) {
                if model.editorText.isEmpty {
                    Text("输入要手动加入 Nothung 剪贴板的内容")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(NothungPalette.muted.opacity(0.76))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $model.editorText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(NothungPalette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .accessibilityLabel("剪贴板条目内容")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(
                KeyboardSurface(
                    role: .content,
                    cornerRadius: 18,
                    interactive: false
                )
            )

            Text("加入时会先执行本地清理规则。")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(NothungPalette.muted)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
    }

    private var documentActionRow: some View {
        KeyboardSurfaceGroup(spacing: 6) {
            HStack(spacing: 7) {
                Button(
                    action: model.hasFullAccess
                        ? onPasteCurrentClipboard
                        : onCleanSelectedText
                ) {
                    Image(
                        systemName: model.hasFullAccess
                            ? "doc.on.doc"
                            : "wand.and.sparkles"
                    )
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 46, height: 44)
                .buttonStyle(KeyboardKeyStyle(role: .modifier))
                .accessibilityLabel(
                    model.hasFullAccess
                        ? "清理并粘贴当前剪贴板"
                        : "本地清理所选链接"
                )

                RepeatingKeyboardKey(
                    systemName: "chevron.left",
                    accessibilityLabel: "光标左移",
                    width: 46,
                    profile: .cursor,
                    action: { onMoveCursor(-1) }
                )

                RepeatingKeyboardKey(
                    systemName: "chevron.right",
                    accessibilityLabel: "光标右移",
                    width: 46,
                    profile: .cursor,
                    action: { onMoveCursor(1) }
                )

                Button {
                    onInsertText(" ")
                } label: {
                    Text("空格")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .buttonStyle(KeyboardKeyStyle(role: .standard))
                .accessibilityLabel("插入空格")

                Button {
                    onInsertText("\n")
                } label: {
                    Image(systemName: "return")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 46, height: 44)
                .buttonStyle(KeyboardKeyStyle(role: .modifier))
                .accessibilityLabel("插入换行")

                RepeatingKeyboardKey(
                    systemName: "delete.left",
                    accessibilityLabel: "删除",
                    width: 46,
                    profile: .acceleratingDelete,
                    action: onDelete
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var editorActionRow: some View {
        KeyboardSurfaceGroup(spacing: 6) {
            HStack(spacing: 7) {
                Button {
                    onInterfaceAction()
                    model.dismissManualEntry()
                } label: {
                    Text("取消")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .buttonStyle(KeyboardKeyStyle(role: .modifier))

                Button {
                    onInterfaceAction()
                    model.editorText = ""
                } label: {
                    Label("清空", systemImage: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .buttonStyle(KeyboardKeyStyle(role: .standard))
                .disabled(model.editorText.isEmpty)

                Button {
                    onInterfaceAction()
                    Task { await model.submitManualEntry() }
                } label: {
                    Label {
                        Text(
                            model.isProcessing
                                ? String(localized: "处理中")
                                : String(localized: "添加")
                        )
                    } icon: {
                        Image(systemName: "plus")
                    }
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .buttonStyle(KeyboardKeyStyle(role: .primary))
                .disabled(
                    model.isProcessing
                        || model.editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func headerButton<Label: View>(
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(NothungPalette.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 34, height: 34)
        .buttonStyle(KeyboardHeaderButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct KeyboardDeckBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)

            KeyboardChrome.deckTint
        }
    }
}

private struct KeyboardTopShape: Shape {
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 30,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 30,
            style: .continuous
        )
        .path(in: rect)
    }
}

private enum KeyboardChrome {
    static let deckTint = adaptive(
        light: UIColor(red: 214 / 255, green: 216 / 255, blue: 224 / 255, alpha: 0.54),
        dark: UIColor(red: 20 / 255, green: 21 / 255, blue: 27 / 255, alpha: 0.46)
    )
    static let fallbackContent = adaptive(
        light: UIColor(red: 248 / 255, green: 249 / 255, blue: 252 / 255, alpha: 1),
        dark: UIColor(red: 46 / 255, green: 48 / 255, blue: 56 / 255, alpha: 1)
    )
    static let fallbackStandardKey = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 84 / 255, green: 86 / 255, blue: 94 / 255, alpha: 1)
    )
    static let fallbackModifierKey = adaptive(
        light: UIColor(red: 247 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1),
        dark: UIColor(red: 70 / 255, green: 72 / 255, blue: 80 / 255, alpha: 1)
    )
    static let border = adaptive(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.10)
    )
    static let pressedOverlay = adaptive(
        light: UIColor(white: 0, alpha: 0.14),
        dark: UIColor(white: 0, alpha: 0.28)
    )
    static let warning = adaptive(
        light: UIColor(red: 215 / 255, green: 139 / 255, blue: 44 / 255, alpha: 1),
        dark: UIColor(red: 246 / 255, green: 174 / 255, blue: 75 / 255, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

private enum KeyboardSurfaceRole {
    case content
    case standard
    case modifier
    case primary

    var fallbackFill: Color {
        switch self {
        case .content: return KeyboardChrome.fallbackContent
        case .standard: return KeyboardChrome.fallbackStandardKey
        case .modifier: return KeyboardChrome.fallbackModifierKey
        case .primary: return NothungPalette.accent
        }
    }

    var foreground: Color {
        self == .primary ? .white : NothungPalette.ink
    }
}

private struct KeyboardSurface: ViewModifier {
    let role: KeyboardSurfaceRole
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(role.fallbackFill, in: shape)
            .overlay { shape.stroke(KeyboardChrome.border, lineWidth: 0.5) }
    }
}

private struct KeyboardSurfaceGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
    }
}

private struct KeyboardKeyStyle: ButtonStyle {
    let role: KeyboardSurfaceRole

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        configuration.label
            .foregroundStyle(role.foreground)
            .contentShape(shape)
            .modifier(KeyboardSurface(role: role, cornerRadius: 10, interactive: true))
            .overlay {
                shape
                    .fill(KeyboardChrome.pressedOverlay)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.linear(duration: 0.045), value: configuration.isPressed)
    }
}

private struct KeyboardHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .modifier(KeyboardSurface(role: .content, cornerRadius: 17, interactive: true))
            .overlay {
                Circle()
                    .fill(KeyboardChrome.pressedOverlay)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.linear(duration: 0.045), value: configuration.isPressed)
    }
}

private struct KeyboardCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(KeyboardChrome.pressedOverlay)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.linear(duration: 0.045), value: configuration.isPressed)
    }
}

private enum KeyRepeatProfile {
    case cursor
    case acceleratingDelete

    var initialDelay: TimeInterval {
        switch self {
        case .cursor: return 0.34
        case .acceleratingDelete: return 0.30
        }
    }

    func interval(after heldDuration: TimeInterval) -> TimeInterval {
        switch self {
        case .cursor:
            return 0.075
        case .acceleratingDelete:
            switch heldDuration {
            case ..<0.8: return 0.095
            case ..<1.6: return 0.064
            case ..<2.5: return 0.042
            default: return 0.026
            }
        }
    }
}

private struct RepeatingKeyboardKey: View {
    let systemName: String
    let accessibilityLabel: LocalizedStringKey
    let width: CGFloat
    let profile: KeyRepeatProfile
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NothungPalette.ink)

            RepeatingPressSurface(
                profile: profile,
                action: action,
                pressStateChanged: { isPressed = $0 }
            )
        }
        .frame(width: width, height: 44)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .modifier(KeyboardSurface(role: .modifier, cornerRadius: 10, interactive: true))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KeyboardChrome.pressedOverlay)
                .opacity(isPressed ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.linear(duration: 0.045), value: isPressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

private struct RepeatingPressSurface: UIViewRepresentable {
    let profile: KeyRepeatProfile
    let action: () -> Void
    let pressStateChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(profile: profile, action: action, pressStateChanged: pressStateChanged)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.isExclusiveTouch = true
        button.isAccessibilityElement = false
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.beginPress),
            for: .touchDown
        )
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.endPress),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.profile = profile
        context.coordinator.action = action
        context.coordinator.pressStateChanged = pressStateChanged
    }

    static func dismantleUIView(_ uiView: UIButton, coordinator: Coordinator) {
        coordinator.cancel()
    }

    final class Coordinator: NSObject {
        var profile: KeyRepeatProfile
        var action: () -> Void
        var pressStateChanged: (Bool) -> Void

        private var timer: Timer?
        private var pressedAt: TimeInterval?

        init(
            profile: KeyRepeatProfile,
            action: @escaping () -> Void,
            pressStateChanged: @escaping (Bool) -> Void
        ) {
            self.profile = profile
            self.action = action
            self.pressStateChanged = pressStateChanged
        }

        @objc func beginPress() {
            guard pressedAt == nil else { return }
            pressedAt = ProcessInfo.processInfo.systemUptime
            pressStateChanged(true)
            action()
            scheduleTimer(after: profile.initialDelay)
        }

        @objc func endPress() {
            cancel()
        }

        func cancel() {
            timer?.invalidate()
            timer = nil
            pressedAt = nil
            pressStateChanged(false)
        }

        @objc private func repeatAction() {
            guard let pressedAt else { return }
            action()
            let heldDuration = ProcessInfo.processInfo.systemUptime - pressedAt
            scheduleTimer(after: profile.interval(after: heldDuration))
        }

        private func scheduleTimer(after interval: TimeInterval) {
            timer?.invalidate()
            let timer = Timer(
                timeInterval: interval,
                target: self,
                selector: #selector(repeatAction),
                userInfo: nil,
                repeats: false
            )
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
