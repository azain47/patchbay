import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// What the rack page needs from whichever engine it is editing.
protocol LiveEngine: AnyObject {
    var inputPeak: Float { get }
    var outputPeak: Float { get }
    var sampleRate: Double { get }
    func scopeSnapshot(into: UnsafeMutablePointer<Float>) -> Bool
    func publish(_ settings: RackSettings)
}

extension SystemAudioEngine: LiveEngine {}
extension MicEngine: LiveEngine {}

// MARK: - Virtual microphone driver

/// The one piece of patchbay that touches the system: a passthrough loopback device
/// (BlackHole, GPLv3, built as "patchbay Mic") in /Library/Audio/Plug-Ins/HAL. Whatever
/// patchbay writes to its output stream appears on its input stream, so any app can
/// select "patchbay Mic" as its microphone and receive the processed signal.
enum VirtualMic {
    static let deviceUID = "patchbay Mic_UID"
    static let installPath = "/Library/Audio/Plug-Ins/HAL/patchbayMic.driver"
    static var bundledPath: String? { Bundle.main.path(forResource: "patchbayMic", ofType: "driver") }

    static var installed: Bool { FileManager.default.fileExists(atPath: installPath) }
    static func isVirtualMic(_ device: Device) -> Bool { device.uid == deviceUID }

    /// Copies the driver in and restarts coreaudiod. Asks for an administrator password.
    /// Every engine must be stopped before this; coreaudiod's restart invalidates them all.
    static func install(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let bundled = bundledPath else { completion(.failure(Failure("The driver is missing from this build."))); return }
        privileged("rm -rf '\(installPath)' && cp -R '\(bundled)' '\(installPath)' && chown -R root:wheel '\(installPath)' && killall coreaudiod", completion: completion)
    }

    static func uninstall(completion: @escaping (Result<Void, Error>) -> Void) {
        privileged("rm -rf '\(installPath)' && killall coreaudiod", completion: completion)
    }

    private static func privileged(_ command: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async {
                if let error, let message = error[NSAppleScript.errorMessage] as? String {
                    // -128 is the user cancelling the password prompt.
                    if (error[NSAppleScript.errorNumber] as? Int) == -128 { completion(.failure(Failure("Cancelled."))) }
                    else { completion(.failure(Failure(message))) }
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

// MARK: - Microphone engine

/// real microphone → chain → patchbay Mic. A private aggregate of the two devices runs one
/// IO proc that reads the mic's input buffers and writes the virtual device's output
/// buffers; `RealtimeDSP` does the rest. Nothing is muted and nothing needs proving: if
/// patchbay stops, the virtual mic simply falls silent and the real mic is untouched.
final class MicEngine {
    private(set) var status: SystemAudioEngine.Status = .stopped {
        didSet {
            engineLog.info("mic status \(String(describing: self.status), privacy: .public)")
            DispatchQueue.main.async { [status, weak self] in self?.onStatus?(status) }
        }
    }
    var onStatus: ((SystemAudioEngine.Status) -> Void)?
    var onNeedsRestart: (() -> Void)?
    private(set) var sourceUID: String?
    private(set) var sampleRate = 48_000.0
    var inputPeak: Float { processor?.inputPeak ?? 0 }
    var outputPeak: Float { processor?.outputPeak ?? 0 }
    func scopeSnapshot(into: UnsafeMutablePointer<Float>) -> Bool {
        guard let processor else { return false }
        processor.scopeSnapshot(into: into)
        return true
    }

    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var processor: RealtimeDSP?
    private var rateListener: AudioObjectPropertyListenerBlock?
    private var settings = RackSettings(modules: [])
    private var generation: UInt64 = 0
    private var layoutGeneration: UInt64 = 0
    private var lastLayoutKey = ""

    deinit { stop() }

    func start(source: Device, settings: RackSettings) {
        engineLog.info("mic start from \(source.name, privacy: .public)")
        stopResources()
        self.settings = settings
        sourceUID = source.uid
        do {
            try buildPipeline(source: source)
            status = .running(device: source.name)
        } catch {
            stopResources()
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func stop() {
        guard aggregateID != kAudioObjectUnknown || sourceUID != nil else { return }
        engineLog.info("mic stop")
        stopResources()
        sourceUID = nil
        status = .stopped
    }

    func publish(_ settings: RackSettings) {
        self.settings = settings
        generation &+= 1
        let key = settings.layoutKey
        if key != lastLayoutKey { layoutGeneration &+= 1; lastLayoutKey = key }
        processor?.publish(settings, generation: generation, layoutGeneration: layoutGeneration)
    }

    private func buildPipeline(source: Device) throws {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "patchbay microphone",
            kAudioAggregateDeviceUIDKey: "com.patchbay.mic.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: source.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: source.uid],
                [kAudioSubDeviceUIDKey: VirtualMic.deviceUID, kAudioSubDeviceDriftCompensationKey: true],
            ],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateID), "creating the microphone pipeline")
        aggregateID = newAggregateID

        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        try check(AudioObjectGetPropertyData(newAggregateID, &address, 0, nil, &size, &rate), "reading the microphone sample rate")
        sampleRate = rate

        generation &+= 1
        layoutGeneration &+= 1
        lastLayoutKey = settings.layoutKey
        guard let newProcessor = RealtimeDSP(settings: settings, sampleRate: sampleRate, generation: generation, layoutGeneration: layoutGeneration, proofOnly: false) else {
            throw VirtualMic.Failure("allocating the realtime processor failed")
        }
        processor = newProcessor

        var newIOProcID: AudioDeviceIOProcID?
        let block: AudioDeviceIOBlock = { _, input, _, output, _ in newProcessor.render(input: input, output: output) }
        try check(AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, newAggregateID, nil, block), "creating the microphone callback")
        ioProcID = newIOProcID
        try check(AudioDeviceStart(newAggregateID, newIOProcID), "starting the microphone pipeline")

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.aggregateID == newAggregateID else { return }
                var current = Float64(0)
                var s = UInt32(MemoryLayout<Float64>.size)
                if AudioObjectGetPropertyData(newAggregateID, &address, 0, nil, &s, &current) == noErr, current != self.sampleRate {
                    self.onNeedsRestart?()
                }
            }
        }
        if AudioObjectAddPropertyListenerBlock(newAggregateID, &address, .main, listener) == noErr { rateListener = listener }
    }

    private func stopResources() {
        if let rateListener, aggregateID != kAudioObjectUnknown {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(aggregateID, &address, .main, rateListener)
        }
        rateListener = nil
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        processor = nil
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw VirtualMic.Failure("\(operation) failed (OSStatus \(status)).") }
    }
}
