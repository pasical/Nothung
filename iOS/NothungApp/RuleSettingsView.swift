import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RuleSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var configuration: NothungRuleConfiguration
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isImportingFile = false

    let onSaved: () -> Void

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        _configuration = State(initialValue: NothungRuleStorage.load())
    }

    var body: some View {
        Form {
            behaviorSection
            keyboardSection
            ruleCategoriesSection
            transferSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
            }
        }
        .tint(NothungPalette.accent)
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                let document = try String(contentsOf: url, encoding: .utf8)
                try importDocument(document)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            errorMessage == nil ? "规则已更新" : "无法保存规则",
            isPresented: Binding(
                get: { errorMessage != nil || statusMessage != nil },
                set: { shown in
                    if !shown {
                        errorMessage = nil
                        statusMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? statusMessage ?? "")
        }
    }

    private var keyboardSection: some View {
        Section("输入方式") {
            NavigationLink {
                KeyboardSettingsView()
            } label: {
                SettingsDestinationLabel(
                    icon: "keyboard",
                    title: "Nothung 输入法",
                    explanation: "启用输入法、完全访问与最近记录"
                )
            }
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("启用通用追踪参数", isOn: $configuration.useBuiltInTrackingRules)
            Toggle("粘贴后立即清理", isOn: $configuration.cleanImmediatelyAfterPaste)
            Toggle("清理后自动复制", isOn: $configuration.copyAfterCleaning)
            Toggle(
                "仅对规则中的域名展开重定向",
                isOn: $configuration.restrictRedirectExpansionToRules
            )
        } header: {
            Text("处理方式")
        } footer: {
            Text("参数规则先执行，再依列表顺序执行正则规则。")
        }
    }

    private var ruleCategoriesSection: some View {
        Section {
            NavigationLink {
                ParameterRulesView(rules: $configuration.parameterRules)
            } label: {
                SettingsDestinationLabel(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "参数规则",
                    explanation: "按域名保留或移除查询参数"
                )
            }

            NavigationLink {
                RegexRulesView(rules: $configuration.regexRules)
            } label: {
                SettingsDestinationLabel(
                    icon: "text.badge.star",
                    title: "正则规则",
                    explanation: "依次替换域名、路径或参数"
                )
            }

            NavigationLink {
                RedirectRulesView(rules: $configuration.redirectRules)
            } label: {
                SettingsDestinationLabel(
                    icon: "arrow.triangle.branch",
                    title: "重定向规则",
                    explanation: "指定允许联网展开的短链域名"
                )
            }
        } header: {
            Text("清理规则")
        } footer: {
            Text("可在各类别中新增、排序、启停或删除规则。")
        }
    }

    private var transferSection: some View {
        Section {
            PasteButton(payloadType: String.self) { values in
                guard let document = values.first else { return }
                do {
                    try importDocument(document)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .labelStyle(.titleAndIcon)

            Button {
                isImportingFile = true
            } label: {
                Label("从文件导入规则包", systemImage: "doc.badge.plus")
            }

            Button {
                do {
                    UIPasteboard.general.string = try NothungRuleStorage.exportDocument(
                        configuration
                    )
                    statusMessage = "配置 JSON 已复制到剪贴板。"
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label("复制配置 JSON", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                configuration = .default
            } label: {
                Label("恢复默认规则", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("导入与导出")
        } footer: {
            Text("支持 Nothung 配置 JSON 和兼容的 Base64 规则。导入完整配置会替换当前草稿。")
        }
    }

    private func importDocument(_ document: String) throws {
        configuration = try NothungRuleStorage.importing(
            document,
            into: configuration
        )
        statusMessage = "已导入 \(configuration.parameterRules.count) 条参数规则、\(configuration.regexRules.count) 条正则规则和 \(configuration.redirectRules.count) 条重定向规则；检查后请点击保存。"
    }

    private func save() {
        do {
            try NothungRuleStorage.save(configuration)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct KeyboardSettingsView: View {
    @State private var entries: [NothungClipboardEntry] = []
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("前往“设置”→“通用”→“键盘”→“键盘”，选择“添加新键盘”并添加 Nothung。")
                Text("打开 Nothung，开启“允许完全访问”，即可自动清理剪贴板并按规则展开短链。")

                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else {
                        return
                    }
                    UIApplication.shared.open(url)
                } label: {
                    Label("打开系统设置", systemImage: "gear")
                }
            } header: {
                Text("启用输入法")
            } footer: {
                Text("完全访问后，Nothung 只在键盘可见期间检查并自动清理新的剪贴板；收起或切换键盘后立即停止。查看和插入已有记录不依赖网络。")
            }

            Section {
                if entries.isEmpty {
                    Text("还没有最近记录。使用主 App、分享扩展或 Nothung 输入法清理内容后，会显示在这里。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries.prefix(5)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.cleaned)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                            Text(entry.capturedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        do {
                            try NothungClipboardHistoryStorage.clear()
                            reload()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("清空全部记录", systemImage: "trash")
                    }
                }
            } header: {
                Text("最近记录")
            } footer: {
                Text("最多保存 20 条原文和清理结果，只保存在设备上；相同内容会自动去重。长按键盘中的条目可显示原文或删除单条。")
            }

            Section("系统限制") {
                Text("密码框、电话号码键盘，以及主动禁用第三方键盘的 App 不会显示 Nothung。这是 iOS 的系统限制。")
                    .foregroundStyle(.secondary)
                if !NothungClipboardHistoryStorage.usesSharedContainer {
                    Label(
                        "当前版本中，主 App 与输入法的最近记录不会同步。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("输入法")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .refreshable { reload() }
        .alert(
            "无法更新剪贴板集合",
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

    private func reload() {
        entries = NothungClipboardHistoryStorage.load()
    }
}

private struct SettingsDestinationLabel: View {
    let icon: String
    let title: String
    let explanation: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(NothungPalette.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ParameterRulesView: View {
    @Binding var rules: [NothungParameterRule]
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List(selection: $selection) {
            Section {
                Text("参数规则只修改 URL 的查询部分。白名单仅保留指定参数；黑名单仅删除指定参数。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("规则") {
                ForEach(rules) { rule in
                    NavigationLink {
                        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                            ParameterRuleEditor(rule: $rules[index])
                        }
                    } label: {
                        RuleRowLabel(
                            title: rule.title,
                            subtitle: "\(rule.mode.title) · \(rule.host.ruleDisplayValue)",
                            isEnabled: rule.isEnabled
                        )
                    }
                    .swipeActions {
                        deleteButton(rule.id)
                    }
                    .tag(rule.id)
                }
                .onDelete { offsets in
                    remove(ids: Set(offsets.map { rules[$0].id }))
                }
                .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("参数规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ruleListToolbar(
                editMode: $editMode,
                selection: $selection,
                deleteSelection: { remove(ids: selection) },
                add: { rules.append(NothungParameterRule()) }
            )
        }
    }

    private func deleteButton(_ id: UUID) -> some View {
        Button("删除", role: .destructive) {
            remove(ids: [id])
        }
    }

    private func remove(ids: Set<UUID>) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rules.removeAll { ids.contains($0.id) }
            selection.subtract(ids)
        }
    }
}

private struct RegexRulesView: View {
    @Binding var rules: [NothungRegexRule]
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List(selection: $selection) {
            Section {
                Text("正则规则按列表顺序执行，一条规则内也按行顺序替换。用于参数规则无法表达的域名、路径和文本整形。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("规则") {
                ForEach(rules) { rule in
                    NavigationLink {
                        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                            RegexRuleEditor(rule: $rules[index])
                        }
                    } label: {
                        RuleRowLabel(
                            title: rule.title,
                            subtitle: "\(rule.patterns.count) 个替换步骤",
                            isEnabled: rule.isEnabled
                        )
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            remove(ids: [rule.id])
                        }
                    }
                    .tag(rule.id)
                }
                .onDelete { offsets in
                    remove(ids: Set(offsets.map { rules[$0].id }))
                }
                .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("正则规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ruleListToolbar(
                editMode: $editMode,
                selection: $selection,
                deleteSelection: { remove(ids: selection) },
                add: { rules.append(NothungRegexRule()) }
            )
        }
    }

    private func remove(ids: Set<UUID>) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rules.removeAll { ids.contains($0.id) }
            selection.subtract(ids)
        }
    }
}

private struct RedirectRulesView: View {
    @Binding var rules: [NothungRedirectRule]
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List(selection: $selection) {
            Section {
                Text("重定向规则是联网许可列表。命中后，主 App、“使用 Nothung 复制”和键盘可见期间的自动捕捉流程会跟随最多五次 HTTPS 跳转，再清理最终链接。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("规则") {
                ForEach(rules) { rule in
                    NavigationLink {
                        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                            RedirectRuleEditor(rule: $rules[index])
                        }
                    } label: {
                        RuleRowLabel(
                            title: rule.title,
                            subtitle: rule.host.ruleDisplayValue,
                            isEnabled: rule.isEnabled
                        )
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            remove(ids: [rule.id])
                        }
                    }
                    .tag(rule.id)
                }
                .onDelete { offsets in
                    remove(ids: Set(offsets.map { rules[$0].id }))
                }
                .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("重定向规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ruleListToolbar(
                editMode: $editMode,
                selection: $selection,
                deleteSelection: { remove(ids: selection) },
                add: { rules.append(NothungRedirectRule()) }
            )
        }
    }

    private func remove(ids: Set<UUID>) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rules.removeAll { ids.contains($0.id) }
            selection.subtract(ids)
        }
    }
}

private struct ParameterRuleEditor: View {
    @Binding var rule: NothungParameterRule

    var body: some View {
        Form {
            Section("规则") {
                Toggle("启用", isOn: $rule.isEnabled)
                TextField("规则名称", text: $rule.title)
                TextField("域名，例如 example.com", text: $rule.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("包含子域名", isOn: $rule.includesSubdomains)
                Picker("模式", selection: $rule.mode) {
                    ForEach(NothungParameterRule.Mode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section {
                TextEditor(text: lineListBinding($rule.parameterNames))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
            } header: {
                Text("参数名称")
            } footer: {
                Text("每行一个。留空会移除该域名的全部参数。")
            }

            RuleSourceSection(source: rule.source)
        }
        .navigationTitle(rule.title.ruleDisplayValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RegexRuleEditor: View {
    @Binding var rule: NothungRegexRule

    var body: some View {
        Form {
            Section("规则") {
                Toggle("启用", isOn: $rule.isEnabled)
                TextField("规则名称", text: $rule.title)
                Toggle("忽略大小写", isOn: $rule.caseInsensitive)
            }

            Section {
                TextEditor(text: preservingLineListBinding($rule.patterns))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
            } header: {
                Text("正则")
            } footer: {
                Text("每行一步。首行匹配不到时跳过整条规则。")
            }

            Section {
                TextEditor(text: preservingLineListBinding($rule.replacements))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
            } header: {
                Text("替换内容")
            } footer: {
                Text("与正则逐行对应；空行表示删除匹配内容。每一步结果都必须仍是 HTTP(S) URL。")
            }

            RuleSourceSection(source: rule.source)
        }
        .navigationTitle(rule.title.ruleDisplayValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RedirectRuleEditor: View {
    @Binding var rule: NothungRedirectRule

    var body: some View {
        Form {
            Section {
                Toggle("启用", isOn: $rule.isEnabled)
                TextField("规则名称", text: $rule.title)
                TextField("域名，例如 b23.tv", text: $rule.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("包含子域名", isOn: $rule.includesSubdomains)
            } header: {
                Text("规则")
            } footer: {
                Text("只填写域名，不要包含 https://、端口或路径。")
            }

            RuleSourceSection(source: rule.source)
        }
        .navigationTitle(rule.title.ruleDisplayValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RuleRowLabel: View {
    let title: String
    let subtitle: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(isEnabled ? NothungPalette.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.ruleDisplayValue)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RuleSourceSection: View {
    let source: String?

    var body: some View {
        if let source = source?.trimmedNonEmpty {
            Section("来源") {
                Label(source, systemImage: "person.text.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@ToolbarContentBuilder
private func ruleListToolbar(
    editMode: Binding<EditMode>,
    selection: Binding<Set<UUID>>,
    deleteSelection: @escaping () -> Void,
    add: @escaping () -> Void
) -> some ToolbarContent {
    if editMode.wrappedValue.isEditing {
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive, action: deleteSelection) {
                Label("删除所选", systemImage: "trash")
            }
            .disabled(selection.wrappedValue.isEmpty)
        }
    }

    ToolbarItemGroup(placement: .primaryAction) {
        Button(editMode.wrappedValue.isEditing ? "完成" : "编辑") {
            withAnimation {
                if editMode.wrappedValue.isEditing {
                    selection.wrappedValue.removeAll()
                    editMode.wrappedValue = .inactive
                } else {
                    editMode.wrappedValue = .active
                }
            }
        }
        if !editMode.wrappedValue.isEditing {
            Button(action: add) {
                Label("添加规则", systemImage: "plus")
            }
        }
    }
}

private func lineListBinding(_ values: Binding<[String]>) -> Binding<String> {
    Binding(
        get: { values.wrappedValue.joined(separator: "\n") },
        set: { text in
            values.wrappedValue = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    )
}

private func preservingLineListBinding(_ values: Binding<[String]>) -> Binding<String> {
    Binding(
        get: { values.wrappedValue.joined(separator: "\n") },
        set: { values.wrappedValue = $0.components(separatedBy: "\n") }
    )
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var ruleDisplayValue: String {
        trimmedNonEmpty ?? "未填写"
    }
}
