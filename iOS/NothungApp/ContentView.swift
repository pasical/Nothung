import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(
        "hasCompletedOnboarding.v1",
        store: UserDefaults(suiteName: NothungRuleStorage.appGroupIdentifier)
    ) private var hasCompletedOnboarding = false

    @StateObject private var model = CleanerViewModel()
    @State private var showingPrivacy = false
    @State private var showingRedirectDisclosure = false
    @State private var showingAddHistoryEntry = false
    @State private var showingClearHistoryConfirmation = false
    @State private var showingOnboardingAgain = false
    @State private var historyEntries: [NothungClipboardEntry] = []
    @State private var historyErrorMessage: String?
    @State private var copiedHistoryEntryID: UUID?
    @State private var historyCopyFeedbackCount = 0
    @FocusState private var inputIsFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    masthead
                    inputCard

                    if let errorMessage = model.errorMessage {
                        errorCard(errorMessage)
                    }

                    if let output = model.output {
                        resultCard(output)
                        removedFieldsCard(output)
                        appliedRulesCard(output)
                        redirectStatusCard
                    }

                    historyCard
                    privacyCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                reloadHistory()
            }
            .background(NothungPalette.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        RuleSettingsView(
                            onSaved: {
                                model.invalidateOutput()
                            },
                            onReplayOnboarding: {
                                showingOnboardingAgain = true
                            }
                        )
                    } label: {
                        Label("设置", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        inputIsFocused = false
                    }
                }
            }
            .sensoryFeedback(.success, trigger: model.copied)
            .sensoryFeedback(.success, trigger: historyCopyFeedbackCount)
            .onAppear(perform: reloadHistory)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    reloadHistory()
                }
            }
            .onChange(of: model.output) { _, _ in
                recordCurrentOutputInHistory()
            }
            .sheet(isPresented: $showingPrivacy) {
                PrivacyStatementView()
            }
            .sheet(isPresented: $showingAddHistoryEntry) {
                AddClipboardEntryView { text in
                    let cleaned: String
                    do {
                        cleaned = try NothungCleaningService.clean(text).cleaned
                    } catch let cleaningError as NothungCleaningService.CleaningError {
                        if case .noWebURL = cleaningError {
                            cleaned = text
                        } else {
                            throw cleaningError
                        }
                    }
                    try NothungClipboardHistoryStorage.record(
                        original: text,
                        cleaned: cleaned
                    )
                    reloadHistory()
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { !hasCompletedOnboarding || showingOnboardingAgain },
                    set: { isPresented in
                        if !isPresented {
                            hasCompletedOnboarding = true
                            showingOnboardingAgain = false
                        }
                    }
                )
            ) {
                NothungOnboardingView {
                    hasCompletedOnboarding = true
                    showingOnboardingAgain = false
                    reloadHistory()
                }
                .interactiveDismissDisabled()
            }
            .alert(
                "联网展开重定向？",
                isPresented: $showingRedirectDisclosure
            ) {
                Button("取消", role: .cancel) {}
                Button("仅这一次") {
                    Task {
                        await model.expandRedirects()
                    }
                }
            } message: {
                Text(
                    "Nothung 会把当前完整 URL 通过 HTTPS 发送给目标网站，并逐跳访问它返回的地址。网站会看到你的 IP 地址和 URL；Nothung 不会附带 Cookie 或登录凭据。"
                )
            }
            .alert(
                "无法更新最近记录",
                isPresented: Binding(
                    get: { historyErrorMessage != nil },
                    set: { if !$0 { historyErrorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(historyErrorMessage ?? "")
            }
            .confirmationDialog(
                "清空所有最近记录？",
                isPresented: $showingClearHistoryConfirmation,
                titleVisibility: .visible
            ) {
                Button("清空所有记录", role: .destructive) {
                    clearHistory()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会删除所有固定与未固定的本地记录，且无法撤销。")
            }
        }
    }

    private var masthead: some View {
        HStack(alignment: .top, spacing: 15) {
            NothungMark(size: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: "NOTHUNG")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(NothungPalette.accent)

                Text("清理链接，\n收好剪贴板。")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(NothungPalette.ink)
                    .lineSpacing(-1)

                Text("去掉链接里的多余痕迹，把常用文本安全留在本机。")
                    .font(.subheadline)
                    .foregroundStyle(NothungPalette.muted)
                    .padding(.top, 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NothungPhaseLabel(text: "待清理")
                Spacer()
                if !model.input.isEmpty || model.output != nil {
                    Button {
                        inputIsFocused = false
                        model.clear()
                    } label: {
                        Label("清空", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
                PasteButton(payloadType: String.self) { values in
                    model.acceptPaste(values)
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
            }

            ZStack(alignment: .topLeading) {
                if model.input.isEmpty {
                    Text("粘贴 URL，或输入包含链接的文本")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(NothungPalette.muted.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $model.input)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(NothungPalette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 116)
                    .focused($inputIsFocused)
                    .onChange(of: model.input) { _, _ in
                        model.inputDidChange()
                    }
                    .accessibilityLabel("待清理的链接或文本")
            }
            .padding(8)
            .background(NothungPalette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(NothungPalette.seam, lineWidth: 0.75)
            }

            Button {
                inputIsFocused = false
                model.clean()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.sparkles")
                    Text(
                        model.output == nil
                            ? String(localized: "清理链接")
                            : String(localized: "重新清理")
                    )
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.callout.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 13))
            .controlSize(.large)
            .disabled(!model.canClean)
        }
        .nothungCard()
    }

    private func resultCard(_ output: NothungCleaningOutput) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                NothungPhaseLabel(text: "重铸结果")
                Spacer()
                Label {
                    Text(
                        output.didChange
                            ? String(localized: "已清理")
                            : String(localized: "无需改动")
                    )
                } icon: {
                    Image(systemName: output.didChange ? "sparkles" : "checkmark.shield")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(output.didChange ? NothungPalette.accent : NothungPalette.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("之前")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NothungPalette.muted)
                Text(output.original)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(NothungPalette.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(NothungPalette.seam)
                .frame(height: 0.75)

            VStack(alignment: .leading, spacing: 8) {
                Text("之后")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NothungPalette.accent)
                Text(output.cleaned)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .foregroundStyle(NothungPalette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    model.copyOutput()
                } label: {
                    Label {
                        Text(
                            model.copied
                                ? String(localized: "已复制")
                                : String(localized: "复制")
                        )
                    } icon: {
                        Image(systemName: model.copied ? "checkmark" : "doc.on.doc")
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                ShareLink(item: output.cleaned) {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .buttonBorderShape(.roundedRectangle(radius: 12))

            if output.inputKind == .url {
                Rectangle()
                    .fill(NothungPalette.seam)
                    .frame(height: 0.75)

                Button {
                    showingRedirectDisclosure = true
                } label: {
                    HStack(spacing: 10) {
                        if model.isExpandingRedirects {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.branch")
                        }
                        Text(
                            model.isExpandingRedirects
                                ? String(localized: "正在安全展开…")
                                : String(localized: "展开短链或重定向")
                        )
                        Spacer()
                        Text("会联网")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NothungPalette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .disabled(!model.canExpandRedirects)

                Text("命中已启用的短链规则时会自动联网展开；其他链接可在主 App 中手动展开。")
                    .font(.caption)
                    .foregroundStyle(NothungPalette.muted)
            }
        }
        .nothungCard()
    }

    @ViewBuilder
    private func removedFieldsCard(_ output: NothungCleaningOutput) -> some View {
        if !output.removedFields.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    NothungPhaseLabel(text: "移除的痕迹")
                    Spacer()
                    Text("\(output.removedFields.count) 项")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(NothungPalette.muted)
                }

                ForEach(output.removedFields) { field in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Circle()
                            .fill(NothungPalette.accent)
                            .frame(width: 6, height: 6)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(field.name)
                                .font(.system(.callout, design: .monospaced, weight: .semibold))
                                .foregroundStyle(NothungPalette.ink)

                            if let value = field.value, !value.isEmpty {
                                Text(value)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(NothungPalette.muted)
                                    .lineLimit(2)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
            .nothungCard()
        }
    }

    @ViewBuilder
    private func appliedRulesCard(_ output: NothungCleaningOutput) -> some View {
        if !output.appliedRegexRuleIdentifiers.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                NothungPhaseLabel(text: "依次应用的替换规则")

                ForEach(
                    Array(output.appliedRegexRuleIdentifiers.enumerated()),
                    id: \.offset
                ) { index, identifier in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(NothungPalette.accent)
                            .frame(width: 22, height: 22)
                            .background(
                                NothungPalette.accentWash,
                                in: Circle()
                            )
                        Text(identifier)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(NothungPalette.ink)
                        Spacer(minLength: 0)
                    }
                }
            }
            .nothungCard()
        }
    }

    @ViewBuilder
    private var redirectStatusCard: some View {
        if model.isExpandingRedirects
            || model.redirectMessage != nil
            || model.redirectErrorMessage != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    NothungPhaseLabel(text: "重定向")
                    Spacer()
                    if model.isExpandingRedirects {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let message = model.redirectMessage {
                    Label(message, systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                        .foregroundStyle(NothungPalette.ink)
                }

                if let error = model.redirectErrorMessage {
                    Label(error, systemImage: "exclamationmark.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                ForEach(Array(model.redirectHops.enumerated()), id: \.offset) { index, hop in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("第 \(index + 1) 跳 · HTTP \(hop.statusCode)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(NothungPalette.accent)
                        Text(hop.destinationURL.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NothungPalette.muted)
                            .textSelection(.enabled)
                    }
                }
            }
            .nothungCard()
        }
    }

    private func errorCard(_ message: String) -> some View {
        Label {
            Text(message)
                .font(.subheadline)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nothungCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    NothungPhaseLabel(text: "最近剪贴板与清理记录")
                    Spacer(minLength: 8)
                    historyHeaderActions
                }

                VStack(alignment: .leading, spacing: 8) {
                    NothungPhaseLabel(text: "最近剪贴板与清理记录")
                    historyHeaderActions
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if historyEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clipboard")
                        .font(.title2)
                        .foregroundStyle(NothungPalette.accent)
                        .accessibilityHidden(true)
                    Text("还没有本地记录")
                        .font(.headline)
                        .foregroundStyle(NothungPalette.ink)
                    Text("清理链接或添加内容后，会显示在这里。")
                        .font(.footnote)
                        .foregroundStyle(NothungPalette.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10, alignment: .top),
                        GridItem(.flexible(), spacing: 10, alignment: .top),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(historyEntries) { entry in
                        historyEntryCard(entry)
                    }
                }
            }

            Text("最多保存 \(NothungClipboardHistoryStorage.maximumEntryCount) 条，只保存在设备上。固定条目始终排在前面。")
                .font(.caption)
                .foregroundStyle(NothungPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .nothungCard()
    }

    private func historyEntryCard(_ entry: NothungClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: entry.cleaned.contains("://") ? "link" : "text.alignleft")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(NothungPalette.accent)
                    .accessibilityHidden(true)

                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NothungPalette.accent)
                        .accessibilityLabel("已固定")
                }

                Spacer(minLength: 2)

                Menu {
                    Button {
                        loadHistoryEntry(entry)
                    } label: {
                        Label("载入清理区", systemImage: "arrow.up.doc")
                    }

                    Button {
                        copyHistoryEntry(entry)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }

                    Button {
                        setPinned(entry, isPinned: !entry.isPinned)
                    } label: {
                        Label(
                            entry.isPinned
                                ? String(localized: "取消固定")
                                : String(localized: "固定"),
                            systemImage: entry.isPinned ? "pin.slash" : "pin"
                        )
                    }

                    Button(role: .destructive) {
                        removeHistoryEntry(entry)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NothungPalette.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多操作")
            }

            Text(
                entry.capturedAt,
                format: .dateTime
                    .month(.twoDigits)
                    .day(.twoDigits)
                    .hour()
                    .minute()
            )
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(NothungPalette.muted)
            .lineLimit(1)
            .accessibilityLabel(
                entry.capturedAt.formatted(date: .long, time: .shortened)
            )

            Text(entry.cleaned)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(NothungPalette.ink)
                .lineLimit(4)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if entry.original != entry.cleaned {
                Label("已清理", systemImage: "wand.and.stars")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NothungPalette.accent)
            }

            Spacer(minLength: 2)

            HStack(spacing: 8) {
                Button {
                    loadHistoryEntry(entry)
                } label: {
                    Label("载入清理区", systemImage: "arrow.up.doc")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("把这条记录载入上方的清理输入框")

                Button {
                    copyHistoryEntry(entry)
                } label: {
                    Label(
                        copiedHistoryEntryID == entry.id
                            ? String(localized: "已复制")
                            : String(localized: "复制"),
                        systemImage: copiedHistoryEntryID == entry.id
                            ? "checkmark"
                            : "doc.on.doc"
                    )
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background(
            NothungPalette.canvas,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NothungPalette.seam, lineWidth: 0.75)
        }
    }

    private var historyHeaderActions: some View {
        HStack(spacing: 8) {
            if !historyEntries.isEmpty {
                Button {
                    showingClearHistoryConfirmation = true
                } label: {
                    Label("清空全部记录", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHint("删除所有固定与未固定的本地记录")
            }

            Button {
                showingAddHistoryEntry = true
            } label: {
                Label("添加条目", systemImage: "plus")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
        }
    }

    private func loadHistoryEntry(_ entry: NothungClipboardEntry) {
        model.input = entry.cleaned
        model.inputDidChange()
        inputIsFocused = true
    }

    private func copyHistoryEntry(_ entry: NothungClipboardEntry) {
        UIPasteboard.general.string = entry.cleaned
        copiedHistoryEntryID = entry.id
        historyCopyFeedbackCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedHistoryEntryID == entry.id {
                copiedHistoryEntryID = nil
            }
        }
    }

    private func reloadHistory() {
        historyEntries = NothungClipboardHistoryStorage.load()
    }

    private func recordCurrentOutputInHistory() {
        guard let output = model.output else { return }
        do {
            try NothungClipboardHistoryStorage.record(
                original: output.original,
                cleaned: output.cleaned
            )
            reloadHistory()
        } catch {
            historyErrorMessage = error.localizedDescription
        }
    }

    private func setPinned(_ entry: NothungClipboardEntry, isPinned: Bool) {
        do {
            try NothungClipboardHistoryStorage.setPinned(
                id: entry.id,
                isPinned: isPinned
            )
            reloadHistory()
        } catch {
            historyErrorMessage = error.localizedDescription
        }
    }

    private func removeHistoryEntry(_ entry: NothungClipboardEntry) {
        do {
            try NothungClipboardHistoryStorage.remove(id: entry.id)
            reloadHistory()
        } catch {
            historyErrorMessage = error.localizedDescription
        }
    }

    private func clearHistory() {
        do {
            try NothungClipboardHistoryStorage.clear()
            reloadHistory()
        } catch {
            historyErrorMessage = error.localizedDescription
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(NothungPalette.accent)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 5) {
                    Text("只在设备上处理")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NothungPalette.ink)

                    Text("参数与正则清理、最近记录都在本机完成。自动捕捉默认关闭；开启后，键盘只在可见期间读取新剪贴板。只有启用短链展开或手动展开时才会访问目标网站。")
                        .font(.footnote)
                        .foregroundStyle(NothungPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("查看完整隐私说明") {
                showingPrivacy = true
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(NothungPalette.accent)
            .padding(.leading, 36)
        }
        .padding(16)
        .background(NothungPalette.accentWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PrivacyStatementView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        NothungPhaseLabel(text: "生效日期 2026-08-21")
                        Text("Nothung 隐私说明")
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .foregroundStyle(NothungPalette.ink)
                        Text("Nothung 在设备上执行参数与正则清理。主 App 会处理你粘贴、输入或手动加入最近记录的内容；分享扩展接收宿主 App 交给它的内容。Nothung 键盘可处理你手动输入的内容；给予完全访问后，还可在你点按粘贴时读取当前剪贴板，或在已开启自动捕捉且键盘可见时读取新的剪贴板。启用或手动使用短链展开时，完整 URL 会发送给链接目标网站。")
                            .foregroundStyle(NothungPalette.muted)
                    }

                    privacySection(
                        title: "数据收集",
                        body: "GitHub 仓库中的 Nothung 版本没有开发者运营的数据接收服务器，也不包含账户、广告、分析、遥测或第三方 SDK。主 App 的粘贴、输入与手动添加，分享扩展收到的内容，以及键盘中的手动粘贴、手动添加与已开启的自动捕捉，都可能在设备上形成最近记录。联网展开短链时，目标网站会收到完整 URL 与网络元数据；这不同于向 Nothung 开发者上传数据。修改后的派生构建应根据实际行为提供自己的说明。"
                    )
                    privacySection(
                        title: "网络访问",
                        body: "参数过滤和正则替换完全在本地进行。命中你启用的短链展开规则时，主 App 的清理流程、分享扩展，以及键盘中的手动粘贴、手动添加与已开启的自动捕捉流程会通过 HTTPS 访问当前 URL 和最多五个重定向目标；主 App 手动添加最近记录与键盘魔棒清理所选链接始终离线。其他链接只会在主 App 经你逐次确认后展开。因此相关网站会收到你的 IP 地址、完整 URL 和常规网络元数据。解析使用临时会话，不附带 Cookie、Authorization 或登录凭据，收到响应头后立即停止读取响应体。Nothung 不会自动打开最终链接。"
                    )
                    privacySection(
                        title: "剪贴板",
                        body: "自动捕捉默认关闭，Nothung 不在后台监控剪贴板。你开启自动捕捉并为输入法打开“允许完全访问”后，键盘只在屏幕上可见期间检查剪贴板变化，自动读取、清理并保存新文本；键盘收起或切换后即停止。完全访问也允许键盘在你点按粘贴按钮时读取当前剪贴板，并访问与主 App 共享的最近记录；键盘手动添加会处理你输入的内容。主 App 通过可见的系统“粘贴”控件读取你选择的内容，也会保存你手动加入最近记录的内容；分享扩展只接收宿主 App 提供的内容。Nothung 在本机保存最多 20 条原文和清理结果，可逐条删除、固定或全部清空。"
                    )
                    privacySection(
                        title: "规则设置",
                        body: "自定义规则、处理开关和有限的剪贴板集合仅保存在设备上的 Nothung App Group 中，用于主 App、Action Extension、键盘与快捷指令。Nothung 不会上传这些数据；导入、导出或清空只会在你明确操作时发生。"
                    )
                    privacySection(
                        title: "变更与联系",
                        body: "本说明与 GitHub 仓库根目录的 PRIVACY.md 同步。如果新功能会传输或保留 URL、分享文本、诊断或使用数据，必须先更新说明。可通过仓库 Issues 反馈，请勿附带私密链接或个人信息。"
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Link(
                            destination: URL(string: "https://github.com/pasical/Nothung/blob/main/PRIVACY.md")!
                        ) {
                            Label("在 GitHub 阅读 PRIVACY.md", systemImage: "doc.text")
                                .frame(minHeight: 44)
                        }

                        Link(
                            destination: URL(string: "https://github.com/pasical/Nothung/issues")!
                        ) {
                            Label("通过 GitHub Issues 联系支持", systemImage: "questionmark.bubble")
                                .frame(minHeight: 44)
                        }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NothungPalette.accent)
                }
                .padding(22)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(NothungPalette.canvas.ignoresSafeArea())
            .navigationTitle("隐私")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .tint(NothungPalette.accent)
    }

    private func privacySection(
        title: LocalizedStringResource,
        body: LocalizedStringResource
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
                .foregroundStyle(NothungPalette.ink)
            Text(body)
                .font(.body)
                .foregroundStyle(NothungPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AddClipboardEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textIsFocused: Bool

    @State private var text = ""
    @State private var errorMessage: String?

    let onSave: (String) throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .focused($textIsFocused)
                        .accessibilityLabel("要加入最近记录的内容")
                } header: {
                    Text("内容")
                } footer: {
                    Text("保存时会在本机应用当前参数与正则规则，不会展开短链或发起网络请求。")
                }
            }
            .navigationTitle("添加条目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                textIsFocused = true
            }
            .alert(
                "无法添加条目",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(NothungPalette.accent)
    }

    private func save() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try onSave(value)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NothungOnboardingView: View {
    private static let sampleURL =
        "https://example.com/article?utm_source=chat&utm_campaign=demo"

    @State private var page = 0
    @State private var configuration = NothungRuleStorage.load()
    @State private var cleanedExample = false
    @State private var pastedShareResult = ""
    @State private var keyboardTestText = ""
    @State private var feedbackCount = 0
    @State private var errorMessage: String?
    @State private var showingPrivacyStatement = false
    @FocusState private var keyboardTestIsFocused: Bool

    let onComplete: () -> Void

    private static let fallbackCleanedURL = "https://example.com/article"

    private var cleanedURL: String {
        guard let cleaner = try? NothungRuleConfiguration.default.makeCleaner() else {
            return Self.fallbackCleanedURL
        }
        return (try? NothungCleaningService.clean(Self.sampleURL, cleaner: cleaner).cleaned)
            ?? Self.fallbackCleanedURL
    }

    private var normalizedShareResult: String {
        normalizedShareValue(pastedShareResult)
    }

    private var shareResultIsCorrect: Bool {
        normalizedShareResult == cleanedURL
    }

    private func normalizedShareValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress

                TabView(selection: $page) {
                    cleanPage.tag(0)
                    sharePage.tag(1)
                    keyboardPage.tag(2)
                    privacyRulesPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
            .background(NothungPalette.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .alert(
            "无法保存设置",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingPrivacyStatement) {
            PrivacyStatementView()
        }
        .tint(NothungPalette.accent)
        .sensoryFeedback(.success, trigger: feedbackCount)
        .onChange(of: page) { _, _ in
            keyboardTestIsFocused = false
        }
        .onChange(of: pastedShareResult) { oldValue, newValue in
            let becameCorrect =
                normalizedShareValue(newValue) == cleanedURL
                && normalizedShareValue(oldValue) != cleanedURL
            if becameCorrect {
                feedbackCount += 1
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index <= page ? NothungPalette.accent : NothungPalette.seam)
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .animation(.easeInOut(duration: 0.2), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("使用引导，第 \(page + 1) 步，共 4 步")
    }

    private var cleanPage: some View {
        onboardingPage(step: 1, title: "清理链接") {
            Text("点按“清理示例”。")
                .font(.body)
                .foregroundStyle(NothungPalette.muted)

            VStack(alignment: .leading, spacing: 12) {
                Text(
                    cleanedExample
                        ? String(localized: "清理后")
                        : String(localized: "原链接")
                )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        cleanedExample ? NothungPalette.accent : NothungPalette.muted
                    )

                Text(verbatim: cleanedExample ? cleanedURL : Self.sampleURL)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(NothungPalette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        cleanedExample = true
                    }
                    feedbackCount += 1
                } label: {
                    Label(
                        cleanedExample
                            ? String(localized: "已清理")
                            : String(localized: "清理示例"),
                        systemImage: cleanedExample ? "checkmark" : "wand.and.stars"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
            }
            .nothungCard()
        }
    }

    private var sharePage: some View {
        onboardingPage(step: 2, title: "从分享菜单复制") {
            VStack(alignment: .leading, spacing: 10) {
                instructionStep(number: 1, text: "打开分享菜单。")
                instructionStep(number: 2, text: "选择“使用 Nothung 复制”。")
                instructionStep(number: 3, text: "把结果粘贴到输入框。")
            }

            ShareLink(item: Self.sampleURL) {
                Label("打开分享菜单", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))

            HStack(alignment: .center, spacing: 10) {
                TextField(
                    "在这里粘贴结果",
                    text: $pastedShareResult,
                    axis: .vertical
                )
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...4)
                .accessibilityLabel("清理后的链接")

                PasteButton(payloadType: String.self) { values in
                    guard let value = values.first else { return }
                    pastedShareResult = value
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle(radius: 10))
            }
            .padding(14)
            .background(
                NothungPalette.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NothungPalette.seam, lineWidth: 0.75)
            }

            if !normalizedShareResult.isEmpty {
                Label(
                    shareResultIsCorrect
                        ? String(localized: "链接已清理")
                        : String(localized: "请重新从分享菜单复制"),
                    systemImage: shareResultIsCorrect
                        ? "checkmark.circle.fill"
                        : "arrow.counterclockwise.circle"
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        shareResultIsCorrect ? NothungPalette.accent : NothungPalette.muted
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var keyboardPage: some View {
        onboardingPage(step: 3, title: "启用输入法") {
            VStack(alignment: .leading, spacing: 10) {
                instructionStep(
                    number: 1,
                    text: "前往“通用”→“键盘”→“键盘”，添加 Nothung。"
                )
                instructionStep(
                    number: 2,
                    text: "需要访问剪贴板时，开启“允许完全访问”。"
                )
                instructionStep(number: 3, text: "返回后点输入框，切换到 Nothung。")
            }

            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                UIApplication.shared.open(url)
            } label: {
                Label("打开 Nothung 设置", systemImage: "gear")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))

            TextField("点这里测试键盘", text: $keyboardTestText, axis: .vertical)
                .focused($keyboardTestIsFocused)
                .font(.body)
                .lineLimit(3...6)
                .padding(14)
                .frame(minHeight: 86, alignment: .topLeading)
                .background(
                    NothungPalette.surface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(NothungPalette.seam, lineWidth: 0.75)
                }
        }
    }

    private var privacyRulesPage: some View {
        onboardingPage(step: 4, title: "选择默认功能") {
            Label {
                Text("短链展开会把完整 URL 发送给目标网站；其余默认功能在本机处理。")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(NothungPalette.accent)
            }
            .foregroundStyle(NothungPalette.muted)

            VStack(spacing: 0) {
                ForEach(
                    Array(NothungDefaultFeature.allCases.enumerated()),
                    id: \.element.id
                ) { index, feature in
                    if index > 0 {
                        Divider()
                    }
                    defaultFeatureRow(feature)
                }
            }
            .nothungCard()

            Button {
                showingPrivacyStatement = true
            } label: {
                Label("查看完整隐私说明", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
        }
    }

    private func defaultFeatureRow(_ feature: NothungDefaultFeature) -> some View {
        Toggle(
            isOn: Binding(
                get: { configuration.isDefaultFeatureEnabled(feature) },
                set: { configuration.setDefaultFeature(feature, isEnabled: $0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NothungPalette.ink)
                if feature.requiresNetwork {
                    Label("需要联网", systemImage: "network")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
                Text(feature.explanation)
                    .font(.footnote)
                    .foregroundStyle(NothungPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 12)
    }

    private func onboardingPage<Content: View>(
        step: Int,
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(verbatim: "\(step) / 4")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(NothungPalette.accent)

                    Text(title)
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .foregroundStyle(NothungPalette.ink)
                }

                content()
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 30)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    private func instructionStep(
        number: Int,
        text: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 11) {
            Text(verbatim: "\(number)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(NothungPalette.accent, in: Circle())
                .accessibilityHidden(true)

            Text(text)
                .font(.body)
                .foregroundStyle(NothungPalette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if page > 0 {
                Button {
                    keyboardTestIsFocused = false
                    withAnimation { page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("上一步")
            }

            if page == 2 {
                Button("跳过") {
                    keyboardTestIsFocused = false
                    withAnimation { page = 3 }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                keyboardTestIsFocused = false
                if page < 3 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                HStack {
                    Text(page < 3
                         ? String(localized: "继续")
                         : String(localized: "完成"))
                        .fontWeight(.semibold)
                    Spacer(minLength: 8)
                    Image(systemName: page < 3 ? "arrow.right" : "checkmark")
                }
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(NothungPalette.surface)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func finish() {
        do {
            try NothungRuleStorage.save(configuration)
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
