import SwiftUI

struct NothungMark: View {
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            ReforgedBladeShape()
                .fill(NothungPalette.ink)
                .frame(width: size * 0.62, height: size)

            RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
                .fill(NothungPalette.accent)
                .frame(width: size * 0.17, height: size * 0.17)
                .rotationEffect(.degrees(45))
                .offset(y: -size * 0.01)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(180))
        .accessibilityHidden(true)
    }
}

private struct ReforgedBladeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Upper blade. The deliberate break is joined by the indigo forge mark.
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.02))
        path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.57, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.36, y: h * 0.14))
        path.closeSubpath()

        // Lower blade and shoulders.
        path.move(to: CGPoint(x: w * 0.43, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.57, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.70))
        path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.70))
        path.closeSubpath()

        // Guard, grip, and pommel.
        path.addRoundedRect(
            in: CGRect(x: w * 0.12, y: h * 0.68, width: w * 0.76, height: h * 0.075),
            cornerSize: CGSize(width: h * 0.04, height: h * 0.04)
        )
        path.addRoundedRect(
            in: CGRect(x: w * 0.455, y: h * 0.72, width: w * 0.09, height: h * 0.20),
            cornerSize: CGSize(width: w * 0.04, height: w * 0.04)
        )
        path.addEllipse(in: CGRect(x: w * 0.41, y: h * 0.88, width: w * 0.18, height: w * 0.18))

        return path
    }
}
