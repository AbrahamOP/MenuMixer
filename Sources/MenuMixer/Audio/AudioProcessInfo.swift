import AppKit
import CoreAudio

/// Informations sur un processus audio actif.
/// Peut regrouper plusieurs AudioObjectIDs (ex: app principale + helpers).
struct AudioProcessInfo: Identifiable, Hashable {
    let id: pid_t
    let pid: pid_t
    let bundleID: String
    let name: String
    let icon: NSImage

    /// Tous les AudioObjectIDs associés (app + helpers)
    let audioObjectIDs: [AudioObjectID]

    /// Premier AudioObjectID (rétrocompatibilité)
    var audioObjectID: AudioObjectID { audioObjectIDs.first ?? 0 }

    init(pid: pid_t, bundleID: String, name: String, icon: NSImage, audioObjectIDs: [AudioObjectID]) {
        self.id = pid
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.icon = icon
        self.audioObjectIDs = audioObjectIDs
    }

    static func == (lhs: AudioProcessInfo, rhs: AudioProcessInfo) -> Bool {
        lhs.pid == rhs.pid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    /// Données brutes d'un processus audio CoreAudio
    struct RawProcess {
        let pid: pid_t
        let bundleID: String
        let audioObjectID: AudioObjectID
        let runningApp: NSRunningApplication?
    }

    /// Indique si ce AudioObject émet réellement du son vers un output
    /// (équivalent du "l'app joue actuellement" dans le mélangeur Windows)
    static func readIsRunningOutput(audioObjectID: AudioObjectID) -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            audioObjectID, &address, 0, nil, &size, &value
        )
        return status == noErr && value != 0
    }

    /// Extrait les données brutes d'un AudioObjectID
    static func rawFrom(audioObjectID: AudioObjectID) -> RawProcess? {
        var pid: pid_t = 0
        var pidSize = UInt32(MemoryLayout<pid_t>.size)
        var pidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let pidStatus = AudioObjectGetPropertyData(
            audioObjectID, &pidAddress, 0, nil, &pidSize, &pid
        )
        guard pidStatus == noErr, pid > 0 else { return nil }

        var bundleID: CFString = "" as CFString
        var bundleIDSize = UInt32(MemoryLayout<CFString>.size)
        var bundleIDAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(
            audioObjectID, &bundleIDAddress, 0, nil, &bundleIDSize, &bundleID
        )

        let bundleIDString = bundleID as String
        let runningApp = NSRunningApplication(processIdentifier: pid)

        return RawProcess(
            pid: pid,
            bundleID: bundleIDString,
            audioObjectID: audioObjectID,
            runningApp: runningApp
        )
    }
}
