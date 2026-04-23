import Foundation
import CoreAudio

/// État audio d'une application individuelle
class AppAudioState: ObservableObject, Identifiable {
    let id: pid_t
    var pid: pid_t { id }
    let processInfo: AudioProcessInfo

    @Published var volume: Float = 1.0
    @Published var isMuted: Bool = false
    @Published var selectedOutputDeviceID: AudioDeviceID?
    @Published var peakLevel: Float = 0.0

    /// Volume effectif (prend en compte le mute)
    var effectiveVolume: Float {
        isMuted ? 0.0 : volume
    }

    init(processInfo: AudioProcessInfo) {
        self.id = processInfo.pid
        self.processInfo = processInfo
        restoreFromDefaults()
    }

    // MARK: - Persistance

    private var defaultsKeyPrefix: String {
        "appAudio_\(processInfo.bundleID.isEmpty ? processInfo.name : processInfo.bundleID)"
    }

    func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(volume, forKey: "\(defaultsKeyPrefix)_volume")
        defaults.set(isMuted, forKey: "\(defaultsKeyPrefix)_muted")
    }

    private func restoreFromDefaults() {
        let defaults = UserDefaults.standard
        let key = "\(defaultsKeyPrefix)_volume"
        if defaults.object(forKey: key) != nil {
            volume = defaults.float(forKey: key)
        }
        isMuted = defaults.bool(forKey: "\(defaultsKeyPrefix)_muted")
    }
}
