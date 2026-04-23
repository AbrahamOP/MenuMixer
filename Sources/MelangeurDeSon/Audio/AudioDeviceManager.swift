import Foundation
import CoreAudio

private func deviceLog(_ msg: String) {
    guard let file = fopen("/tmp/melangeur-audio-debug.log", "a") else { return }
    fputs(String(format: "%.3f [Device] %@\n", Date().timeIntervalSince1970, msg), file)
    fclose(file)
}

/// Représente un périphérique audio de sortie
struct OutputAudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String

    static func == (lhs: OutputAudioDevice, rhs: OutputAudioDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Gère l'énumération, le monitoring des périphériques audio de sortie,
/// et le contrôle du volume système.
@MainActor
class AudioDeviceManager: ObservableObject {
    @Published var outputDevices: [OutputAudioDevice] = []
    @Published var defaultOutputDeviceID: AudioDeviceID = 0
    @Published var systemVolume: Float = 1.0
    @Published var systemMuted: Bool = false

    private nonisolated(unsafe) var listenerBlock: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private nonisolated(unsafe) var monitoredDeviceID: AudioDeviceID = 0
    /// Empêche les boucles de feedback quand on modifie le volume depuis l'app
    private var isSettingVolume = false
    private var settingVolumeWorkItem: DispatchWorkItem?

    init() {
        refreshDevices()
        refreshSystemVolume()
        startMonitoring()
        startVolumeMonitoring(for: defaultOutputDeviceID)
    }

    deinit {
        stopMonitoring()
        stopVolumeMonitoring()
    }

    // MARK: - Refresh

    /// Rafraîchit la liste des périphériques de sortie
    func refreshDevices() {
        outputDevices = Self.getOutputDevices()
        let newDefault = Self.getDefaultOutputDeviceID()
        let oldDefault = defaultOutputDeviceID
        defaultOutputDeviceID = newDefault

        if newDefault != oldDefault && newDefault != 0 {
            stopVolumeMonitoring()
            startVolumeMonitoring(for: newDefault)
            refreshSystemVolume()
        }
    }

    /// Lit le volume et mute système du device par défaut
    func refreshSystemVolume() {
        guard defaultOutputDeviceID != 0 else { return }
        let vol = Self.getDeviceVolume(deviceID: defaultOutputDeviceID)
        let muted = Self.getDeviceMute(deviceID: defaultOutputDeviceID)
        deviceLog("refreshSystemVolume: vol=\(vol), muted=\(muted)")
        systemVolume = vol
        systemMuted = muted
    }

    // MARK: - Contrôle du volume système

    /// Modifie le volume du device de sortie par défaut.
    /// Ne met PAS à jour `systemVolume` pour éviter la boucle de feedback.
    /// Le listener CoreAudio mettra à jour `systemVolume` après le délai.
    func setSystemVolume(_ volume: Float) {
        guard defaultOutputDeviceID != 0 else { return }
        markSettingVolume()
        let clamped = max(0, min(1, volume))

        var vol = Float32(clamped)
        let size = UInt32(MemoryLayout<Float32>.size)

        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(defaultOutputDeviceID, &address) {
                var settable: DarwinBoolean = false
                AudioObjectIsPropertySettable(defaultOutputDeviceID, &address, &settable)
                if settable.boolValue {
                    AudioObjectSetPropertyData(defaultOutputDeviceID, &address, 0, nil, size, &vol)
                }
            }
        }
    }

    /// Modifie le mute du device de sortie par défaut
    func setSystemMute(_ muted: Bool) {
        guard defaultOutputDeviceID != 0 else { return }
        markSettingVolume()

        var muteValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(defaultOutputDeviceID, &address) {
            AudioObjectSetPropertyData(defaultOutputDeviceID, &address, 0, nil, size, &muteValue)
        }
    }

    /// Bloque le listener CoreAudio pendant 300ms après un changement depuis l'app
    private func markSettingVolume() {
        isSettingVolume = true
        settingVolumeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.isSettingVolume = false
        }
        settingVolumeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: - Monitoring des périphériques

    private func startMonitoring() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
        self.listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            block
        )

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            DispatchQueue.main,
            block
        )
    }

    private nonisolated func stopMonitoring() {
        guard let block = listenerBlock else { return }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            block
        )

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - Monitoring du volume système

    private func startVolumeMonitoring(for deviceID: AudioDeviceID) {
        guard deviceID != 0 else { return }
        monitoredDeviceID = deviceID

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isSettingVolume else { return }
                self.refreshSystemVolume()
            }
        }
        self.volumeListenerBlock = block

        // Écouter les changements de volume
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, block)

        // Aussi écouter le canal 1 (certains devices n'ont pas de master)
        volumeAddress.mElement = 1
        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, block)

        // Écouter les changements de mute
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, block)
    }

    private nonisolated func stopVolumeMonitoring() {
        guard monitoredDeviceID != 0, let block = volumeListenerBlock else { return }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(monitoredDeviceID, &volumeAddress, DispatchQueue.main, block)

        volumeAddress.mElement = 1
        AudioObjectRemovePropertyListenerBlock(monitoredDeviceID, &volumeAddress, DispatchQueue.main, block)

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(monitoredDeviceID, &muteAddress, DispatchQueue.main, block)

        monitoredDeviceID = 0
    }

    // MARK: - Static Helpers

    /// Récupère tous les périphériques de sortie audio
    static func getOutputDevices() -> [OutputAudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> OutputAudioDevice? in
            guard hasOutputStreams(deviceID: deviceID) else { return nil }

            let name = getDeviceName(deviceID: deviceID)
            let uid = getDeviceUID(deviceID: deviceID)

            // Filtrer les aggregate devices créés par l'app
            if name.hasPrefix("MelangeurDeSon") || uid.hasPrefix("MelangeurDeSon") {
                return nil
            }

            return OutputAudioDevice(id: deviceID, name: name, uid: uid)
        }
    }

    /// Récupère l'ID du périphérique de sortie par défaut
    static func getDefaultOutputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceID
        )

        return status == noErr ? deviceID : 0
    }

    /// Récupère le volume scalaire d'un device (0.0 à 1.0)
    static func getDeviceVolume(deviceID: AudioDeviceID) -> Float {
        var volume: Float32 = 1.0
        var size = UInt32(MemoryLayout<Float32>.size)

        // Essayer le master d'abord
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
                if status == noErr { return volume }
            }
        }

        return 1.0
    }

    /// Récupère l'état mute d'un device
    static func getDeviceMute(deviceID: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        }

        return muted != 0
    }

    private static func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID, &propertyAddress, 0, nil, &dataSize
        )

        return status == noErr && dataSize > 0
    }

    private static func getDeviceName(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &name
        )

        if status == noErr, let cfName = name?.takeUnretainedValue() {
            return cfName as String
        }
        return "Unknown"
    }

    static func getDeviceUID(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &uid
        )

        if status == noErr, let cfUID = uid?.takeUnretainedValue() {
            return cfUID as String
        }
        return ""
    }
}
