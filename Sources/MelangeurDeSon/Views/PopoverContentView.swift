import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: "dial.medium.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                Text("Mélangeur de Son")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 24, height: 24)

                        Image(systemName: "power")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Quitter l'application")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Contenu
            if audioManager.appStates.isEmpty {
                // État vide
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.04))
                            .frame(width: 56, height: 56)

                        Image(systemName: "speaker.slash")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.tertiary)
                    }

                    Text("Aucune app audio active")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(.vertical, 8)
            } else {
                // Liste des apps
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(audioManager.appStates) { state in
                            AppVolumeRow(
                                state: state,
                                outputDevices: audioManager.deviceManager.outputDevices,
                                defaultDeviceID: audioManager.deviceManager.defaultOutputDeviceID,
                                onOutputDeviceChange: { deviceID in
                                    audioManager.setOutputDevice(for: state.pid, deviceID: deviceID)
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .offset(y: -8)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.spring(duration: 0.3), value: audioManager.appStates.count)
                }
                .frame(maxHeight: 360)
                .scrollIndicators(.hidden)
            }

            // Séparateur subtil
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            // Master Volume
            MasterVolumeView(
                volume: $audioManager.masterVolume,
                isMuted: $audioManager.masterMuted
            )
            .padding(.bottom, 10)
        }
        .frame(width: 350)
    }
}
