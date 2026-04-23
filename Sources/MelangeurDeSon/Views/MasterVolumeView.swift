import SwiftUI

struct MasterVolumeView: View {
    @Binding var volume: Float
    @Binding var isMuted: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Bouton mute avec icône dynamique
                Button(action: {
                    withAnimation(.spring(duration: 0.25)) {
                        isMuted.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(isMuted ? Color.red.opacity(0.15) : Color.blue.opacity(0.12))
                            .frame(width: 30, height: 30)

                        Image(systemName: masterIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isMuted ? .red : .blue)
                    }
                }
                .buttonStyle(.plain)
                .help(isMuted ? "Rétablir le son global" : "Couper le son global")

                VStack(alignment: .leading, spacing: 0) {
                    Text("Volume global")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isMuted ? "Coupé" : "\(Int(volume * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isMuted ? .red : .secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.15), value: isMuted ? -1 : Int(volume * 100))
                }

                Spacer()
            }

            Slider(value: snappingVolume, in: 0...1)
                .controlSize(.small)
                .tint(.blue)
                .disabled(isMuted)
                .opacity(isMuted ? 0.35 : 1.0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
    }

    /// Snap le slider vers 0 et 1 aux extrémités pour éviter les taps inutiles
    private var snappingVolume: Binding<Float> {
        Binding(
            get: { volume },
            set: { newValue in
                if newValue > 0.97 { volume = 1.0 }
                else if newValue < 0.03 { volume = 0.0 }
                else { volume = newValue }
            }
        )
    }

    private var masterIcon: String {
        if isMuted {
            return "speaker.slash.fill"
        }
        if volume < 0.01 {
            return "speaker.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}
