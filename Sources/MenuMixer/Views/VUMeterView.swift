import SwiftUI

struct VUMeterView: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let levelWidth = max(0, width * CGFloat(min(level, 1.0)))

            ZStack(alignment: .leading) {
                // Fond
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.06))

                // Barre de niveau avec gradient
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.35, saturation: 0.8, brightness: 0.85),
                                Color(hue: 0.2, saturation: 0.8, brightness: 0.9),
                                Color(hue: 0.08, saturation: 0.9, brightness: 0.95),
                                Color(hue: 0.0, saturation: 0.85, brightness: 0.95)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: levelWidth)

                // Lueur au bout de la barre
                if level > 0.02 {
                    Circle()
                        .fill(levelTipColor.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .blur(radius: 3)
                        .offset(x: levelWidth - 3)
                }
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .animation(.linear(duration: 0.06), value: level)
    }

    private var levelTipColor: Color {
        if level > 0.85 {
            return .red
        } else if level > 0.6 {
            return .orange
        } else {
            return .green
        }
    }
}
