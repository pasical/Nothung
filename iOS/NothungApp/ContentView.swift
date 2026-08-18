import SwiftUI

struct ContentView: View {
    @StateObject private var model = CleanerViewModel()
    @State private var showingPrivacy = false
    @State private var showingRedirectDisclosure = false
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

                    privacyCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NothungPalette.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        RuleSettingsView {
                            model.invalidateOutput()
                        }
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
            .sheet(isPresented: $showingPrivacy) {
                PrivacyStatementView()
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
        }
    }

    private var masthead: some View {
        HStack(alignment: .top, spacing: 15) {
            NothungMark(size: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text("NOTHUNG")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(NothungPalette.accent)

                Text("把分享链接\n重铸得干净。")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(NothungPalette.ink)
                    .lineSpacing(-1)

                Text("移除不必要的追踪参数，同时保留链接本来的去向。")
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

                    Text("参数与正则清理在本地完成。Nothung 不在后台读取剪贴板；开启完全访问后，键盘只在可见期间自动捕捉新文本，收起后立即停止。命中重定向规则时才会访问目标网站。")
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
                        NothungPhaseLabel(text: "生效日期 2026-08-16")
                        Text("Nothung 隐私说明")
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .foregroundStyle(NothungPalette.ink)
                        Text("Nothung 在设备上执行参数与正则清理，不会把内容发送给开发者。主 App 和分享扩展在你明确操作时取得内容；获完全访问的 Nothung 键盘在可见期间自动捕捉新剪贴板。命中重定向规则时，完整 URL 会发送给链接目标。快捷指令保持本地处理。")
                            .foregroundStyle(NothungPalette.muted)
                    }

                    privacySection(
                        title: "数据收集",
                        body: "GitHub 仓库中的 Nothung 版本不会把个人数据发送给开发者，也不会出售或向第三方共享数据。它不包含账户、广告、分析、遥测或第三方 SDK。仅会在设备上保存最多 20 条由你明确操作产生的原文与清理结果。修改后的派生构建应根据实际行为提供自己的说明。"
                    )
                    privacySection(
                        title: "网络访问",
                        body: "参数过滤和正则替换完全在本地进行。命中你启用的重定向规则时，主 App、分享扩展，以及键盘可见期间的自动捕捉流程会通过 HTTPS 访问当前 URL 和最多五个重定向目标；其他链接仅在主 App 逐次确认后展开。因此相关网站会收到你的 IP 地址、完整 URL 和常规网络元数据。解析使用临时会话，不附带 Cookie、Authorization 或登录凭据，收到响应头后立即停止读取响应体。Nothung 不会自动打开最终链接。"
                    )
                    privacySection(
                        title: "剪贴板",
                        body: "Nothung 不在后台监控剪贴板。开启“允许完全访问”后，键盘只在屏幕上可见期间检查剪贴板变化，自动读取、清理并保存新文本；键盘收起或切换后即停止。主 App 仍只通过可见的系统“粘贴”控件读取你明确选择的内容，分享扩展只接收宿主 App 提供的内容。Nothung 会在本机保存最近 20 条原文和清理结果，供键盘再次插入；可在设置中随时全部清空。"
                    )
                    privacySection(
                        title: "规则设置",
                        body: "自定义规则、处理开关和有限的剪贴板集合仅保存在设备上的 Nothung App Group 中，用于主 App、Action Extension、键盘与快捷指令。Nothung 不会上传这些数据；导入、导出或清空只会在你明确操作时发生。"
                    )
                    privacySection(
                        title: "变更与联系",
                        body: "本说明与 GitHub 仓库根目录的 PRIVACY.md 同步。如果新功能会传输或保留 URL、分享文本、诊断或使用数据，必须先更新说明。可通过仓库 Issues 反馈，请勿附带私密链接或个人信息。"
                    )
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

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
