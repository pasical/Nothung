import AppIntents
import Foundation
import NothungCore

enum NothungIntentCleaningError: Error, LocalizedError, Equatable {
    case unsupportedScheme
    case missingHost
    case embeddedCredentials
    case couldNotClean

    var errorDescription: String? {
            switch self {
            case .unsupportedScheme:
            return String(localized: "只支持以 http:// 或 https:// 开头的网页链接。")
            case .missingHost:
            return String(localized: "链接缺少网站地址，请检查后重试。")
            case .embeddedCredentials:
            return String(localized: "链接包含用户名或密码。为避免误分享凭据，Nothung 不会处理这类链接。")
            case .couldNotClean:
            return String(localized: "Nothung 无法安全地清理这个链接，请检查地址后重试。")
            }
    }
}

/// Synchronous and network-free adapter kept separate from App Intent plumbing
/// so its URL-in/URL-out contract can be tested directly.
enum NothungIntentURLCleaner {
    static func clean(_ url: URL) throws -> URLCleaningResult {
        do {
            return try NothungConfiguredCleaner.current().clean(url: url)
        } catch let error as NothungCleanerError {
            switch error {
            case .unsupportedScheme:
                throw NothungIntentCleaningError.unsupportedScheme
            case .missingHost:
                throw NothungIntentCleaningError.missingHost
            case .userInfoNotAllowed:
                throw NothungIntentCleaningError.embeddedCredentials
            case .couldNotConstructCleanedURL,
                 .tooManyParameterRules,
                 .tooManyRegexRules,
                 .regexInputTooLong,
                 .regexProducedUnsafeURL:
                throw NothungIntentCleaningError.couldNotClean
            }
        } catch {
            throw NothungIntentCleaningError.couldNotClean
        }
    }
}

struct CleanURLIntent: AppIntent {
    static let title: LocalizedStringResource = "清理链接"
    static let description = IntentDescription(
        "移除网页链接中的常见跟踪参数；全部处理都在设备上完成。",
        categoryName: "链接",
        searchKeywords: ["URL", "追踪参数", "隐私"],
        resultValueName: "清理后的 URL"
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "URL",
        description: "需要移除跟踪参数的网页链接",
        requestValueDialog: IntentDialog("要清理哪个链接？")
    )
    var url: URL

    static var parameterSummary: some ParameterSummary {
        Summary("清理 \(\.$url)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<URL> & ProvidesDialog {
        let result = try NothungIntentURLCleaner.clean(url)
        let dialog: IntentDialog = result.didChange
            ? "链接已清理。"
            : "这个链接不含已知的跟踪参数。"
        return .result(value: result.cleanedURL, dialog: dialog)
    }
}

struct NothungAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CleanURLIntent(),
            phrases: [
                "用 \(.applicationName) 清理链接",
                "让 \(.applicationName) 清理 URL",
            ],
            shortTitle: "清理链接",
            systemImageName: "link.badge.minus"
        )
    }
}
