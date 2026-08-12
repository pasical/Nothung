import SwiftUI
import UIKit

enum NothungPalette {
    static let accent = Color(red: 82 / 255, green: 103 / 255, blue: 216 / 255)

    static let ink = adaptive(
        light: UIColor(red: 23 / 255, green: 25 / 255, blue: 35 / 255, alpha: 1),
        dark: UIColor(red: 244 / 255, green: 245 / 255, blue: 250 / 255, alpha: 1)
    )

    static let muted = adaptive(
        light: UIColor(red: 98 / 255, green: 103 / 255, blue: 121 / 255, alpha: 1),
        dark: UIColor(red: 168 / 255, green: 173 / 255, blue: 188 / 255, alpha: 1)
    )

    static let canvas = adaptive(
        light: UIColor(red: 244 / 255, green: 245 / 255, blue: 250 / 255, alpha: 1),
        dark: UIColor(red: 15 / 255, green: 17 / 255, blue: 24 / 255, alpha: 1)
    )

    static let surface = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 26 / 255, green: 29 / 255, blue: 39 / 255, alpha: 1)
    )

    static let seam = adaptive(
        light: UIColor(red: 216 / 255, green: 220 / 255, blue: 234 / 255, alpha: 1),
        dark: UIColor(red: 51 / 255, green: 56 / 255, blue: 75 / 255, alpha: 1)
    )

    static let accentWash = adaptive(
        light: UIColor(red: 232 / 255, green: 235 / 255, blue: 251 / 255, alpha: 1),
        dark: UIColor(red: 35 / 255, green: 42 / 255, blue: 74 / 255, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

private struct NothungCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(NothungPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(NothungPalette.seam.opacity(0.8), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 10, y: 3)
    }
}

extension View {
    func nothungCard() -> some View {
        modifier(NothungCardModifier())
    }
}

struct NothungPhaseLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(NothungPalette.accent)
    }
}
