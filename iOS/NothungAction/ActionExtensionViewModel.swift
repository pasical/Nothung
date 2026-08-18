import Combine
import Foundation

@MainActor
final class ActionExtensionViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading(String)
        case copied
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading(
        String(localized: "正在读取分享内容…")
    )

    func updateProgress(_ message: String) {
        phase = .loading(message)
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    func markCopied() {
        phase = .copied
    }
}
