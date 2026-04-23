import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var audioManager: AudioManager

    /// Mode "Windows" par défaut : n'affiche que les apps qui jouent actuellement.
    /// L'utilisateur peut toggler pour voir aussi celles qui ont un stream ouvert mais silencieux.
    @AppStorage("showOnlyActiveApps") private var showOnlyActiveApps: Bool = true

    private var visibleAppStates: [AppAudioState] {
        if showOnlyActiveApps {
            return audioManager.appStates.filter { $0.isPlayingOutput }
        }
        return audioManager.appStates
    }

    private var hiddenCount: Int {
        audioManager.appStates.count - visibleAppStates.count
    }

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

                Text("MenuMixer")
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
            if visibleAppStates.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(visibleAppStates) { state in
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
                    .animation(.spring(duration: 0.3), value: visibleAppStates.map(\.pid))
                }
                .frame(maxHeight: 360)
                .scrollIndicators(.hidden)
            }

            // Footer : toggle "afficher aussi les inactives"
            if showOnlyActiveApps && hiddenCount > 0 {
                showHiddenButton
            } else if !showOnlyActiveApps && audioManager.appStates.count > 0 {
                hideInactiveButton
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

    // MARK: - Sous-vues

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 56, height: 56)

                Image(systemName: "speaker.slash")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
            }

            Text(showOnlyActiveApps ? "Aucune app ne joue actuellement" : "Aucune app audio détectée")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if showOnlyActiveApps && audioManager.appStates.count > 0 {
                Text("\(audioManager.appStates.count) app\(audioManager.appStates.count > 1 ? "s" : "") audio silencieuse\(audioManager.appStates.count > 1 ? "s" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, 8)
    }

    private var showHiddenButton: some View {
        Button(action: {
            withAnimation(.spring(duration: 0.3)) {
                showOnlyActiveApps = false
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: "eye")
                    .font(.system(size: 10, weight: .medium))
                Text("Afficher les \(hiddenCount) app\(hiddenCount > 1 ? "s" : "") silencieuse\(hiddenCount > 1 ? "s" : "")")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private var hideInactiveButton: some View {
        Button(action: {
            withAnimation(.spring(duration: 0.3)) {
                showOnlyActiveApps = true
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10, weight: .medium))
                Text("Masquer les apps silencieuses")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }
}
