import Foundation
import CoreAudio

private func tapLog(_ msg: String) {
    guard let file = fopen("/tmp/melangeur-engine.log", "a") else { return }
    fputs(String(format: "%.3f %@\n", Date().timeIntervalSince1970, msg), file)
    fclose(file)
}

/// Gère la création et destruction des process taps CoreAudio.
/// Un tap par app (groupant tous les audioObjectIDs).
class ProcessTapManager {
    struct ActiveTap {
        let tapID: AudioObjectID
        let aggregateDeviceID: AudioObjectID
        let pid: pid_t
    }

    private var activeTaps: [pid_t: ActiveTap] = [:]

    deinit {
        removeAllTaps()
    }

    func createTap(for processInfo: AudioProcessInfo, outputDeviceUID: String) -> ActiveTap? {
        let pid = processInfo.pid

        if let existing = activeTaps[pid] {
            return existing
        }

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processInfo.audioObjectIDs)
        let tapUUID = UUID()
        tapDescription.uuid = tapUUID
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.name = "MelangeurDeSon-\(processInfo.name)"
        tapDescription.isPrivate = true

        var tapID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard status == noErr, tapID != kAudioObjectUnknown else {
            tapLog("[Tap \(processInfo.name)] Erreur création tap: \(status)")
            return nil
        }

        let tapUID = getTapUID(tapID: tapID) ?? tapUUID.uuidString

        guard let aggregateDeviceID = createAggregateDevice(
            tapUID: tapUID,
            outputDeviceUID: outputDeviceUID,
            pid: pid
        ) else {
            tapLog("[Tap \(processInfo.name)] Erreur création aggregate device")
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let tap = ActiveTap(tapID: tapID, aggregateDeviceID: aggregateDeviceID, pid: pid)
        activeTaps[pid] = tap

        tapLog("[Tap \(processInfo.name)] Tap créé: tapID=\(tapID), aggDevID=\(aggregateDeviceID)")
        return tap
    }

    func removeTap(for pid: pid_t) {
        guard let tap = activeTaps.removeValue(forKey: pid) else { return }
        destroyTap(tap)
    }

    func hasTap(for pid: pid_t) -> Bool {
        activeTaps[pid] != nil
    }

    func removeAllTaps() {
        for (_, tap) in activeTaps {
            destroyTap(tap)
        }
        activeTaps.removeAll()
    }

    // MARK: - Private

    private func destroyTap(_ tap: ActiveTap) {
        AudioHardwareDestroyAggregateDevice(tap.aggregateDeviceID)
        AudioHardwareDestroyProcessTap(tap.tapID)
    }

    private func getTapUID(tapID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &uid)
        if status == noErr, let cfUID = uid?.takeUnretainedValue() {
            return cfUID as String
        }
        return nil
    }

    private func createAggregateDevice(tapUID: String, outputDeviceUID: String, pid: pid_t) -> AudioObjectID? {
        let aggregateUID = "MelangeurDeSon-Agg-\(pid)-\(UUID().uuidString)"

        let subDeviceDict: [String: Any] = [
            kAudioSubDeviceUIDKey: outputDeviceUID
        ]

        let tapDict: [String: Any] = [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: true
        ]

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceNameKey: "MelangeurDeSon-\(pid)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [subDeviceDict],
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceTapListKey: [tapDict]
        ]

        var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateDeviceID
        )

        guard status == noErr, aggregateDeviceID != kAudioObjectUnknown else {
            tapLog("[Tap pid=\(pid)] CreateAggregateDevice failed: \(status)")
            return nil
        }

        return aggregateDeviceID
    }
}
