import AudioToolbox
import CoreAudio
import Foundation

private func audioLog(_ msg: String) {
    guard let file = fopen("/tmp/melangeur-engine.log", "a") else { return }
    fputs(String(format: "%.3f %@\n", Date().timeIntervalSince1970, msg), file)
    fclose(file)
}

/// Gère le pipeline audio pour un processus via IOProc sur l'aggregate device.
/// L'aggregate device contient le tap (input) + output device (output).
/// L'IOProc lit le tap, applique le volume, et écrit vers l'output.
class AudioEngineManager {
    let pid: pid_t
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false

    private let _volumeLock = NSLock()
    private var _volume: Float = 1.0

    nonisolated(unsafe) var ioProcCallCount: UInt64 = 0
    nonisolated(unsafe) var rawPeakLevel: Float = 0

    var volume: Float {
        get { _volumeLock.lock(); defer { _volumeLock.unlock() }; return _volume }
        set { _volumeLock.lock(); _volume = max(0, min(1, newValue)); _volumeLock.unlock() }
    }

    init(pid: pid_t) {
        self.pid = pid
    }

    deinit {
        stop()
    }

    func start(aggregateDeviceID: AudioObjectID) throws {
        guard !isRunning else { return }
        self.aggregateDeviceID = aggregateDeviceID

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var procID: AudioDeviceIOProcID?

        let status = AudioDeviceCreateIOProcID(
            aggregateDeviceID,
            ioProc,
            selfPtr,
            &procID
        )

        guard status == noErr, let id = procID else {
            audioLog("[Engine pid=\(pid)] CreateIOProcID FAILED: \(status)")
            throw NSError(domain: "AudioEngine", code: Int(status),
                         userInfo: [NSLocalizedDescriptionKey: "CreateIOProcID failed: \(status)"])
        }

        self.ioProcID = id

        let startStatus = AudioDeviceStart(aggregateDeviceID, id)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, id)
            self.ioProcID = nil
            audioLog("[Engine pid=\(pid)] AudioDeviceStart FAILED: \(startStatus)")
            throw NSError(domain: "AudioEngine", code: Int(startStatus),
                         userInfo: [NSLocalizedDescriptionKey: "AudioDeviceStart failed: \(startStatus)"])
        }

        isRunning = true
        audioLog("[Engine pid=\(pid)] Started on aggregate \(aggregateDeviceID)")
    }

    func stop() {
        guard isRunning else { return }
        if let procID = ioProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        }
        ioProcID = nil
        isRunning = false
    }
}

/// IOProc : lit l'audio du tap (input), applique le volume, écrit vers la sortie (output)
private func ioProc(
    inDevice: AudioObjectID,
    inNow: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    inInputTime: UnsafePointer<AudioTimeStamp>,
    outOutputData: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime: UnsafePointer<AudioTimeStamp>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }
    let manager = Unmanaged<AudioEngineManager>.fromOpaque(clientData).takeUnretainedValue()
    let vol = manager.volume
    manager.ioProcCallCount &+= 1
    let count = manager.ioProcCallCount

    let inputABL = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
    let outputABL = UnsafeMutableAudioBufferListPointer(outOutputData)

    // Debug logging (rarement)
    if count <= 3 || count % 5000 == 0 {
        var maxAbs: Float = 0
        if let buf = inputABL.first, let data = buf.mData {
            let floats = data.assumingMemoryBound(to: Float.self)
            let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            for i in 0..<n { let a = Swift.abs(floats[i]); if a > maxAbs { maxAbs = a } }
        }
        audioLog("[IOProc pid=\(manager.pid) #\(count)] vol=\(vol) in=\(inputABL.count) out=\(outputABL.count) maxAbs=\(maxAbs)")
    }

    // Copier input → output avec volume
    let bufCount = min(inputABL.count, outputABL.count)
    var peakLevel: Float = 0

    for i in 0..<bufCount {
        let inBuf = inputABL[i]
        let bytesToCopy = min(Int(inBuf.mDataByteSize), Int(outputABL[i].mDataByteSize))

        guard bytesToCopy > 0, let inData = inBuf.mData, let outData = outputABL[i].mData else {
            continue
        }

        let frameCount = bytesToCopy / MemoryLayout<Float>.size

        if vol >= 0.999 {
            memcpy(outData, inData, bytesToCopy)
        } else if vol <= 0.001 {
            memset(outData, 0, bytesToCopy)
        } else {
            let inFloats = inData.assumingMemoryBound(to: Float.self)
            let outFloats = outData.assumingMemoryBound(to: Float.self)
            for j in 0..<frameCount {
                outFloats[j] = inFloats[j] * vol
            }
        }

        // Mesurer le peak du signal de sortie pour le VU-mètre
        let outFloats = outData.assumingMemoryBound(to: Float.self)
        for j in stride(from: 0, to: frameCount, by: 4) {
            let a = Swift.abs(outFloats[j])
            if a > peakLevel { peakLevel = a }
        }

        outputABL[i].mDataByteSize = UInt32(bytesToCopy)
    }

    // Remplir de silence les buffers output supplémentaires
    for i in bufCount..<outputABL.count {
        if let outData = outputABL[i].mData {
            memset(outData, 0, Int(outputABL[i].mDataByteSize))
        }
    }

    // Mettre à jour le peak pour le VU-mètre
    if peakLevel > manager.rawPeakLevel {
        manager.rawPeakLevel = peakLevel
    }

    return noErr
}
