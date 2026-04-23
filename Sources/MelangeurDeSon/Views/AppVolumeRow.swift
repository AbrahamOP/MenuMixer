import SwiftUI
import CoreAudio

struct AppVolumeRow: View {
    @ObservedObject var state: AppAudioState
    let outputDevices: [OutputAudioDevice]
    let defaultDeviceID: AudioDeviceID
    let onOutputDeviceChange: (AudioDeviceID) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Ligne du haut : icône + nom + mute
            HStack(spacing: 10) {
                Image(nsImage: state.processInfo.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)

                Text(state.processInfo.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                // Pourcentage
                Text("\(Int(state.volume * 100))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(state.isMuted ? .tertiary : .secondary)
                    .frame(width: 28, alignment: .trailing)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: Int(state.volume * 100))

                // Bouton mute
                Button(action: {
                    withAnimation(.spring(duration: 0.25)) {
                        state.isMuted.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(state.isMuted ? Color.red.opacity(0.15) : Color.white.opacity(0.06))
                            .frame(width: 26, height: 26)

                        Image(systemName: muteIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(state.isMuted ? .red : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(state.isMuted ? "Rétablir le son" : "Couper le son")
            }

            // Slider + VU-mètre
            VStack(spacing: 3) {
                Slider(value: snappingVolume, in: 0...1)
                    .controlSize(.small)
                    .tint(.blue)
                    .disabled(state.isMuted)
                    .opacity(state.isMuted ? 0.35 : 1.0)

                VUMeterView(level: state.peakLevel)
                    .opacity(state.isMuted ? 0.2 : 0.9)
                    .padding(.horizontal, 2)
            }

            // Sélecteur de sortie audio (si plusieurs devices)
            if outputDevices.count > 1 {
                OutputDevicePicker(
                    selectedDeviceID: Binding(
                        get: { state.selectedOutputDeviceID ?? defaultDeviceID },
                        set: { onOutputDeviceChange($0) }
                    ),
                    devices: outputDevices
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 4 : 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(isHovered ? 0.12 : 0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    /// Snap le slider vers 0 et 1 aux extrémités
    private var snappingVolume: Binding<Float> {
        Binding(
            get: { state.volume },
            set: { newValue in
                if newValue > 0.97 { state.volume = 1.0 }
                else if newValue < 0.03 { state.volume = 0.0 }
                else { state.volume = newValue }
            }
        )
    }

    private var muteIcon: String {
        if state.isMuted {
            return "speaker.slash.fill"
        }
        if state.volume < 0.01 {
            return "speaker.fill"
        } else if state.volume < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
}
