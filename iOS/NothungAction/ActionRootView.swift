import SwiftUI

struct ActionRootView: View {
    @ObservedObject var model: ActionExtensionViewModel
    let onCancel: () -> Void
    let onComplete: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch model.phase {
                case .loading(let message):
                    loadingView(message)
                case .copied:
                    copiedView
                case .failed(let message):
                    failureView(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NothungPalette.canvas.ignoresSafeArea())
        .tint(NothungPalette.accent)
    }

    private var copiedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(NothungPalette.accent)
            Text("已复制到剪贴板")
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(NothungPalette.ink)
            Text("链接已经写入系统剪贴板。")
                .font(.subheadline)
                .foregroundStyle(NothungPalette.muted)
            HStack(spacing: 10) {
                Button(action: onComplete) {
                    Text("完成")
                        .frame(maxWidth: .infinity)
                }
                    .buttonStyle(.borderedProminent)
                Button(action: onShare) {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .padding(.horizontal, 28)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            NothungMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("NOTHUNG")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(NothungPalette.accent)
                Text("重铸链接")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(NothungPalette.ink)
            }
            Spacer()
            Button(action: model.phase == .copied ? onComplete : onCancel) {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(NothungPalette.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NothungPalette.seam)
                .frame(height: 0.75)
        }
    }

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(NothungPalette.muted)
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("无法复制分享内容")
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(NothungPalette.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(NothungPalette.muted)
                .multilineTextAlignment(.center)
            Button("关闭", action: onCancel)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
    }
}
