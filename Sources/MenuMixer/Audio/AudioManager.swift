import Foundation
import CoreAudio
import Combine
import AppKit

private func managerLog(_ msg: String) {
    let path = "/tmp/melangeur-audio-debug.log"
    if let file = fopen(path, "a") {
        let timestamp = Date().timeIntervalSince1970
        let line = String(format: "%.3f %@\n", timestamp, msg)
        fputs(line, file)
        fclose(file)
    }
}

/// Orchestrateur principal.
/// Architecture "tap à la demande" : un tap n'est créé que quand le volume
/// est modifié ou l'app est mutée, et détruit quand le volume revient à 100%.
/// Limite de taps concurrents pour respecter la limite macOS (~3-5 aggregate devices).
@MainActor
class AudioManager: ObservableObject {
    @Published var appStates: [AppAudioState] = []
    /// Volume master = volume système macOS (lié bidirectionnellement)
    @Published var masterVolume: Float = 1.0
    /// Mute master = mute système macOS (lié bidirectionnellement)
    @Published var masterMuted: Bool = false

    let deviceManager = AudioDeviceManager()
    private let tapManager = ProcessTapManager()
    private var engines: [pid_t: AudioEngineManager] = [:]
    private var processListenerBlock: AudioObjectPropertyListenerBlock?
    private var cancellables = Set<AnyCancellable>()
    /// Cancellables par processus — nettoyés proprement lors du removeProcess
    private var processCancellables: [pid_t: Set<AnyCancellable>] = [:]
    /// Listeners CoreAudio sur kAudioProcessPropertyIsRunningOutput par pid
    /// (un processus peut avoir plusieurs audioObjectIDs : app + helpers)
    private var isRunningListeners: [pid_t: [(AudioObjectID, AudioObjectPropertyListenerBlock)]] = [:]
    private var refreshTimer: Timer?
    private var peakTimer: Timer?

    /// Nombre maximum de taps concurrents (limite macOS ~3-5)
    private let maxConcurrentTaps = 4

    /// Le master volume est géré par le système, pas par les taps.
    /// Les taps n'utilisent que le volume per-app.
    private func needsTap(for state: AppAudioState) -> Bool {
        return state.effectiveVolume < 0.999
    }

    func start() {
        managerLog("AudioManager.start() - devices: \(deviceManager.outputDevices.map(\.name)), default: \(deviceManager.defaultOutputDeviceID)")

        // Initialiser le master depuis le volume système
        masterVolume = deviceManager.systemVolume
        masterMuted = deviceManager.systemMuted

        // Quand l'utilisateur change le master slider → modifier le volume système
        // throttle pour ne pas spammer CoreAudio pendant le drag
        $masterVolume
            .dropFirst()
            .removeDuplicates()
            .throttle(for: .milliseconds(30), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] newVolume in
                self?.deviceManager.setSystemVolume(newVolume)
            }
            .store(in: &cancellables)
        $masterMuted
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] newMuted in
                self?.deviceManager.setSystemMute(newMuted)
            }
            .store(in: &cancellables)

        // Quand le volume système change (touches clavier, menu bar) → mettre à jour le slider
        // systemVolume n'est mis à jour que par le listener CoreAudio (pas par setSystemVolume)
        // donc ces valeurs viennent uniquement de changements externes
        deviceManager.$systemVolume
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] sysVol in
                guard let self else { return }
                self.masterVolume = sysVol
            }
            .store(in: &cancellables)
        deviceManager.$systemMuted
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] sysMuted in
                guard let self else { return }
                self.masterMuted = sysMuted
            }
            .store(in: &cancellables)

        // Quand le device de sortie par défaut change (ex: connexion Bluetooth),
        // recréer tous les taps actifs qui suivent le device par défaut.
        deviceManager.$defaultOutputDeviceID
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] newDeviceID in
                guard let self else { return }
                managerLog("Default output device changé → \(newDeviceID)")
                self.deviceManager.refreshDevices()
                self.recreateTapsForDefaultDevice()
            }
            .store(in: &cancellables)

        refreshAudioProcesses()
        startProcessMonitoring()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAudioProcesses()
            }
        }
        peakTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePeakLevels()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        peakTimer?.invalidate()
        peakTimer = nil
        stopProcessMonitoring()

        for (pid, engine) in engines {
            engine.stop()
            tapManager.removeTap(for: pid)
        }
        for pid in Array(isRunningListeners.keys) {
            removeIsRunningListeners(for: pid)
        }
        engines.removeAll()
        processCancellables.removeAll()
        appStates.removeAll()
    }

    // MARK: - IsRunningOutput (détection "app qui joue actuellement")

    private func addIsRunningListeners(for state: AppAudioState) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let pid = state.pid
        var listeners: [(AudioObjectID, AudioObjectPropertyListenerBlock)] = []

        for audioObjectID in state.processInfo.audioObjectIDs {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshIsPlayingOutput(for: pid)
                }
            }
            let status = AudioObjectAddPropertyListenerBlock(
                audioObjectID, &address, DispatchQueue.main, block
            )
            if status == noErr {
                listeners.append((audioObjectID, block))
            }
        }
        isRunningListeners[pid] = listeners
    }

    private func removeIsRunningListeners(for pid: pid_t) {
        guard let listeners = isRunningListeners[pid] else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for (audioObjectID, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(
                audioObjectID, &address, DispatchQueue.main, block
            )
        }
        isRunningListeners.removeValue(forKey: pid)
    }

    @MainActor
    private func refreshIsPlayingOutput(for pid: pid_t) {
        guard let state = appStates.first(where: { $0.pid == pid }) else { return }
        let anyRunning = state.processInfo.audioObjectIDs.contains { id in
            AudioProcessInfo.readIsRunningOutput(audioObjectID: id)
        }
        if state.isPlayingOutput != anyRunning {
            state.isPlayingOutput = anyRunning
        }
    }

    func setOutputDevice(for pid: pid_t, deviceID: AudioDeviceID) {
        guard let state = appStates.first(where: { $0.pid == pid }) else { return }
        state.selectedOutputDeviceID = deviceID

        // Si un tap existe, le recréer avec le nouveau device
        if engines[pid] != nil {
            teardownPipeline(pid: pid)
            setupPipeline(for: state)
        }
    }

    // MARK: - Tap lifecycle

    /// Synchronise les taps : crée/détruit selon le volume effectif
    private func syncAllTaps() {
        for state in appStates {
            syncTap(for: state)
        }
    }

    private func syncTap(for state: AppAudioState) {
        let needs = needsTap(for: state)
        let hasTap = engines[state.pid] != nil

        if needs && !hasTap {
            setupPipeline(for: state)
        } else if !needs && hasTap {
            teardownPipeline(pid: state.pid)
            managerLog("[\(state.processInfo.name)] Tap supprimé (volume 100%)")
        } else if hasTap {
            // Mettre à jour le volume de l'engine existant
            engines[state.pid]?.volume = state.effectiveVolume
        }
    }

    private func setupPipeline(for state: AppAudioState) {
        let processInfo = state.processInfo

        // Vérifier la limite de taps concurrents
        if engines.count >= maxConcurrentTaps {
            managerLog("[\(processInfo.name)] Limite de \(maxConcurrentTaps) taps atteinte, skip")
            return
        }

        let outputUID: String
        if let deviceID = state.selectedOutputDeviceID,
           let device = deviceManager.outputDevices.first(where: { $0.id == deviceID }) {
            outputUID = device.uid
        } else if let defaultDevice = deviceManager.outputDevices.first(where: { $0.id == deviceManager.defaultOutputDeviceID }) {
            outputUID = defaultDevice.uid
        } else {
            // Fallback : interroger CoreAudio directement (le cache outputDevices peut être en retard)
            let directUID = AudioDeviceManager.getDeviceUID(deviceID: deviceManager.defaultOutputDeviceID)
            guard !directUID.isEmpty else {
                managerLog("[\(processInfo.name)] Pas de output device trouvé (default=\(deviceManager.defaultOutputDeviceID))")
                return
            }
            outputUID = directUID
            managerLog("[\(processInfo.name)] Device trouvé via fallback direct: \(directUID)")
        }

        managerLog("[\(processInfo.name)] Creating tap (audioObjectIDs: \(processInfo.audioObjectIDs))")

        guard let tap = tapManager.createTap(for: processInfo, outputDeviceUID: outputUID) else {
            managerLog("[\(processInfo.name)] Impossible de créer le tap")
            return
        }

        let engine = AudioEngineManager(pid: processInfo.pid)
        engines[processInfo.pid] = engine

        do {
            try engine.start(aggregateDeviceID: tap.aggregateDeviceID)
            engine.volume = state.effectiveVolume
            managerLog("[\(processInfo.name)] Engine démarré, volume=\(state.effectiveVolume)")
        } catch {
            // CRITIQUE : si l'engine ne démarre pas, le tap avec mutedWhenTapped
            // mute l'audio original sans IOProc pour le router → silence permanent.
            // On doit nettoyer complètement.
            managerLog("[\(processInfo.name)] Erreur démarrage engine: \(error) — nettoyage tap")
            engines.removeValue(forKey: processInfo.pid)
            tapManager.removeTap(for: processInfo.pid)
        }
    }

    /// Recréer tous les taps qui utilisent le device par défaut
    /// (ceux sans selectedOutputDeviceID explicite)
    private func recreateTapsForDefaultDevice() {
        for state in appStates {
            guard engines[state.pid] != nil else { continue }
            // Ne recréer que les taps qui suivent le device par défaut
            if state.selectedOutputDeviceID == nil ||
               !deviceManager.outputDevices.contains(where: { $0.id == state.selectedOutputDeviceID }) {
                managerLog("[\(state.processInfo.name)] Recréation tap pour nouveau device par défaut")
                teardownPipeline(pid: state.pid)
                setupPipeline(for: state)
            }
        }
    }

    private func teardownPipeline(pid: pid_t) {
        engines[pid]?.stop()
        engines.removeValue(forKey: pid)
        tapManager.removeTap(for: pid)
    }

    // MARK: - Découverte des processus

    private func refreshAudioProcesses() {
        let currentProcesses = Self.getAudioProcesses()
        let currentPIDs = Set(currentProcesses.map(\.pid))
        let existingPIDs = Set(appStates.map(\.pid))

        for process in currentProcesses where !existingPIDs.contains(process.pid) {
            addProcess(process)
        }

        for pid in existingPIDs where !currentPIDs.contains(pid) {
            removeProcess(pid: pid)
        }

        // Vérifier si les audioObjectIDs ont changé (nouveau helper apparu)
        for process in currentProcesses where existingPIDs.contains(process.pid) {
            guard let state = appStates.first(where: { $0.pid == process.pid }) else { continue }
            let oldIDs = Set(state.processInfo.audioObjectIDs)
            let newIDs = Set(process.audioObjectIDs)
            if oldIDs != newIDs {
                managerLog("[\(process.name)] audioObjectIDs changés: \(oldIDs) → \(newIDs)")
                let savedVolume = state.volume
                let savedMuted = state.isMuted
                let savedDevice = state.selectedOutputDeviceID
                removeProcess(pid: process.pid)
                addProcess(process)
                if let newState = appStates.first(where: { $0.pid == process.pid }) {
                    newState.volume = savedVolume
                    newState.isMuted = savedMuted
                    newState.selectedOutputDeviceID = savedDevice
                }
            }
        }
    }

    private func addProcess(_ processInfo: AudioProcessInfo) {
        let state = AppAudioState(processInfo: processInfo)
        var subs = Set<AnyCancellable>()

        // receive(on: RunLoop.main) diffère l'exécution au prochain tick du run loop,
        // APRÈS que willSet ait terminé et que la propriété ait sa nouvelle valeur.
        // Sans ça, state.isMuted/volume aurait encore l'ancienne valeur dans le sink.
        state.$volume
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self, weak state] _ in
                guard let self, let state else { return }
                self.syncTap(for: state)
                state.saveToDefaults()
            }
            .store(in: &subs)

        state.$isMuted
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self, weak state] _ in
                guard let self, let state else { return }
                self.syncTap(for: state)
                state.saveToDefaults()
            }
            .store(in: &subs)

        processCancellables[processInfo.pid] = subs

        appStates.append(state)
        sortAppStates()

        // État initial + listener CoreAudio pour détecter "app qui joue"
        state.isPlayingOutput = processInfo.audioObjectIDs.contains { id in
            AudioProcessInfo.readIsRunningOutput(audioObjectID: id)
        }
        addIsRunningListeners(for: state)

        // Créer le tap seulement si nécessaire (volume != 100% ou muté)
        if needsTap(for: state) {
            setupPipeline(for: state)
        }
    }

    private func sortAppStates() {
        appStates.sort { $0.processInfo.name.localizedCaseInsensitiveCompare($1.processInfo.name) == .orderedAscending }
    }

    private func removeProcess(pid: pid_t) {
        teardownPipeline(pid: pid)
        removeIsRunningListeners(for: pid)
        processCancellables.removeValue(forKey: pid)
        appStates.removeAll { $0.pid == pid }
    }

    // MARK: - VU meters

    private func updatePeakLevels() {
        let decayFactor: Float = 0.7
        for state in appStates {
            if let engine = engines[state.pid] {
                let raw = engine.rawPeakLevel
                engine.rawPeakLevel = 0
                let clamped = min(raw, 1.0)
                let newLevel = max(clamped, state.peakLevel * decayFactor)
                if abs(newLevel - state.peakLevel) > 0.001 {
                    state.peakLevel = newLevel
                }
            } else if state.peakLevel > 0.001 {
                state.peakLevel *= decayFactor
                if state.peakLevel < 0.001 { state.peakLevel = 0 }
            }
        }
    }

    // MARK: - Monitoring des processus

    private func startProcessMonitoring() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshAudioProcesses()
            }
        }
        self.processListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func stopProcessMonitoring() {
        guard let block = processListenerBlock else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - CoreAudio Process Discovery

    static func getAudioProcesses() -> [AudioProcessInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: 0, count: count)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &objectIDs
        )
        guard status == noErr else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier

        let rawProcesses = objectIDs.compactMap { AudioProcessInfo.rawFrom(audioObjectID: $0) }
            .filter { $0.pid != myPID }

        // Identifier les apps "régulières" (visibles dans le Dock)
        var regularApps: [String: (pid: pid_t, app: NSRunningApplication, audioObjectIDs: [AudioObjectID])] = [:]

        for raw in rawProcesses {
            guard let app = raw.runningApp,
                  app.activationPolicy == .regular,
                  !raw.bundleID.isEmpty else { continue }
            if regularApps[raw.bundleID] == nil {
                regularApps[raw.bundleID] = (pid: raw.pid, app: app, audioObjectIDs: [raw.audioObjectID])
            } else {
                regularApps[raw.bundleID]?.audioObjectIDs.append(raw.audioObjectID)
            }
        }

        // Rattacher les helpers à leur app parente
        for raw in rawProcesses {
            if let app = raw.runningApp, app.activationPolicy == .regular { continue }
            guard !raw.bundleID.isEmpty else { continue }

            let parentBundleID = regularApps.keys.first { parentID in
                raw.bundleID.hasPrefix(parentID + ".") || raw.bundleID == parentID
            }

            if let parentID = parentBundleID {
                regularApps[parentID]?.audioObjectIDs.append(raw.audioObjectID)
            }
        }

        return regularApps.map { (bundleID, entry) in
            AudioProcessInfo(
                pid: entry.pid,
                bundleID: bundleID,
                name: entry.app.localizedName ?? bundleID,
                icon: entry.app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(),
                audioObjectIDs: entry.audioObjectIDs
            )
        }
    }
}
