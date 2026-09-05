import AudioToolbox
import CoreAudio
import Foundation
import os

let engineLog = Logger(subsystem: "com.patchbay.app", category: "engine")

final class SystemAudioEngine {
    enum Status: Equatable {
        case stopped
        case proving(device: String)
        case running(device: String)
        case failed(String)
        /// A route whose app currently has no Core Audio client; nothing to tap yet.
        case waiting(app: String)

        var label: String {
            switch self {
            case .stopped: "off"
            case .proving: "waiting for audio"
            case .running: "processing"
            case .failed: "error"
            case .waiting(let app): "waiting for \(app)"
            }
        }
    }

    enum TapMode: String, CaseIterable { case mixdown, deviceStream }
    /// Which tap topology to build. Mixdown is the conservative default; the device-stream tap
    /// avoids a resample but is exposed as an A/B switch because behaviour differs per device.
    var tapMode: TapMode = .mixdown

    /// What the tap listens to. The system engine takes everything except processes that a
    /// route already owns; a route engine takes exactly its app's processes.
    enum Scope: Equatable {
        case system(excluding: [AudioObjectID])
        case processes([AudioObjectID])
    }
    var scope: Scope = .system(excluding: [])

    /// Applies a new process set to the live tap without tearing the pipeline down. Falls
    /// back to a rebuild when the HAL refuses the description change.
    func setScope(_ newScope: Scope) {
        guard newScope != scope else { return }
        scope = newScope
        guard tapID != kAudioObjectUnknown, let description = tapDescription else { return }
        switch newScope {
        case .system(let excluded): description.processes = excluded + ownProcess()
        case .processes(let ids): description.processes = ids
        }
        var address = propertyAddress(kAudioTapPropertyDescription)
        var object: Unmanaged<CATapDescription>? = Unmanaged.passUnretained(description)
        let size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        let status = AudioObjectSetPropertyData(tapID, &address, 0, nil, size, &object)
        engineLog.info("tap description update -> \(status)")
        if status != noErr { onNeedsRestart?() }
    }

    private var tapDescription: CATapDescription?

    private func ownProcess() -> [AudioObjectID] {
        (try? processObjectID(for: getpid())).map { [$0] } ?? []
    }
    struct Diagnostics: Equatable {
        var tapBinding = "—"
        var sampleRate = 0.0
        var driftCompensation = false
    }

    var onStatus: ((Status) -> Void)?
    var onNeedsRestart: (() -> Void)?
    private(set) var status: Status = .stopped {
        didSet {
            engineLog.info("status \(String(describing: self.status), privacy: .public)")
            DispatchQueue.main.async { [status, weak self] in self?.onStatus?(status) }
        }
    }
    private(set) var outputUID: String?
    private(set) var sampleRate = 48_000.0
    private(set) var diagnostics = Diagnostics()
    var inputPeak: Float { processor?.inputPeak ?? 0 }
    var outputPeak: Float { processor?.outputPeak ?? 0 }
    /// Last `RealtimeDSP.scopeFrames` output samples, oldest first; false when idle.
    func scopeSnapshot(into: UnsafeMutablePointer<Float>) -> Bool {
        guard let processor else { return false }
        processor.scopeSnapshot(into: into)
        return true
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var processor: RealtimeDSP?
    private var proofTimer: Timer?
    private var rateListener: AudioObjectPropertyListenerBlock?
    private var settings = RackSettings.neutral
    private var generation: UInt64 = 0
    private var layoutGeneration: UInt64 = 0
    private var lastLayoutKey = ""
    private var captureProven = false

    deinit { stop() }

    func start(output: Device, settings: RackSettings) {
        engineLog.info("start on \(output.name, privacy: .public) mode \(self.tapMode.rawValue, privacy: .public) proven \(self.captureProven)")
        stopResources()
        self.settings = settings
        outputUID = output.uid
        do {
            try buildPipeline(output: output, proofOnly: !captureProven)
            if captureProven {
                status = .running(device: output.name)
            } else {
                status = .proving(device: output.name)
                beginProof(for: output)
            }
        } catch {
            stopResources()
            status = .failed(Self.message(for: error))
        }
    }

    func stop() {
        engineLog.info("stop")
        stopResources()
        outputUID = nil
        captureProven = false
        status = .stopped
    }

    /// Tears the pipeline down but remembers that capture was proven, so a route whose
    /// app went quiet does not replay the unmuted proof window when it comes back.
    func idle() {
        guard status != .stopped || outputUID != nil else { return }
        engineLog.info("idle")
        stopResources()
        outputUID = nil
        status = .stopped
    }

    func publish(_ settings: RackSettings) {
        self.settings = settings
        generation &+= 1
        let key = settings.layoutKey
        if key != lastLayoutKey { layoutGeneration &+= 1; lastLayoutKey = key }
        processor?.publish(settings, generation: generation, layoutGeneration: layoutGeneration)
    }

    // MARK: Proof-before-mute

    private func beginProof(for output: Device) {
        proofTimer?.invalidate()
        proofTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self, let processor = self.processor else { timer.invalidate(); return }
            guard processor.sawSignal != 0 else { return }
            guard processor.renderableLayout != 0 else {
                timer.invalidate()
                self.stopResources()
                self.status = .failed("This output layout is not stereo-renderable yet. Audio was left untouched.")
                return
            }
            timer.invalidate()
            self.proofTimer = nil
            self.captureProven = true
            self.stopResources()
            do {
                try self.buildPipeline(output: output, proofOnly: false)
                self.status = .running(device: output.name)
            } catch {
                self.stopResources()
                self.status = .failed(Self.message(for: error))
            }
        }
    }

    // MARK: Pipeline

    private func buildPipeline(output: Device, proofOnly: Bool) throws {
        let mute = proofOnly ? CATapMuteBehavior.unmuted : CATapMuteBehavior.mutedWhenTapped
        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var description: CATapDescription
        var binding: String

        switch scope {
        case .processes(let ids):
            // A route: exactly this app's processes, mixed to stereo. The tap mutes them at
            // the device they were playing to once capture is proven, and this engine
            // re-emits them on the route's output.
            description = CATapDescription(stereoMixdownOfProcesses: ids)
            description.name = "patchbay route tap"
            description.isPrivate = true
            description.muteBehavior = mute
            binding = "app mixdown"
            try check(AudioHardwareCreateProcessTap(description, &newTapID), "creating the route tap")
            guard tapIsStereoFloat(newTapID) else {
                AudioHardwareDestroyProcessTap(newTapID)
                throw EngineError("the route tap did not provide stereo Float32 audio")
            }

        case .system(let routed):
            let excluded = routed + ownProcess()
            // Prefer a tap bound to the device's own stream: its format matches the hardware
            // stream exactly, so Core Audio does no rate conversion between tap and output.
            // Fall back to the global stereo mixdown when the device stream isn't plain stereo.
            description = CATapDescription(__excludingProcesses: excluded.map { NSNumber(value: $0) }, andDeviceUID: output.uid, withStream: 0)
            binding = "device stream"
            description.name = "patchbay system tap"
            description.isPrivate = true
            description.muteBehavior = mute
            var created = tapMode == .deviceStream && AudioHardwareCreateProcessTap(description, &newTapID) == noErr && tapIsStereoFloat(newTapID)
            if !created {
                if newTapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(newTapID); newTapID = kAudioObjectUnknown }
                description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
                description.name = "patchbay system tap"
                description.isPrivate = true
                description.muteBehavior = mute
                binding = "stereo mixdown"
                try check(AudioHardwareCreateProcessTap(description, &newTapID), "creating the system tap")
                created = tapIsStereoFloat(newTapID)
                guard created else {
                    AudioHardwareDestroyProcessTap(newTapID)
                    throw EngineError("the system tap did not provide stereo Float32 audio; audio was left untouched")
                }
            }
        }
        tapID = newTapID
        tapDescription = description

        // Bluetooth: tap and output share the BT clock; drift compensation there makes the
        // HAL insert/drop samples periodically (audible crackle). Wired/USB clocks differ.
        let isBluetooth = output.transport == kAudioDeviceTransportTypeBluetooth || output.transport == kAudioDeviceTransportTypeBluetoothLE
        let drift = !isBluetooth

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "patchbay private output",
            kAudioAggregateDeviceUIDKey: "com.patchbay.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: drift,
                kAudioSubTapDriftCompensationQualityKey: kAudioAggregateDriftCompensationMaxQuality,
            ]],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID), "creating the private output")
        aggregateID = newAggregateID
        try requireOutputChannels(newAggregateID)

        sampleRate = try nominalSampleRate(of: newAggregateID)
        diagnostics = Diagnostics(tapBinding: binding, sampleRate: sampleRate, driftCompensation: drift)
        generation &+= 1
        layoutGeneration &+= 1
        lastLayoutKey = settings.layoutKey
        guard let newProcessor = RealtimeDSP(settings: settings, sampleRate: sampleRate, generation: generation, layoutGeneration: layoutGeneration, proofOnly: proofOnly) else {
            throw EngineError("allocating the realtime processor failed")
        }
        processor = newProcessor

        var newIOProcID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, newAggregateID, nil, Self.ioBlock(for: newProcessor)), "creating the realtime output callback")
        ioProcID = newIOProcID
        try check(AudioDeviceStart(newAggregateID, newIOProcID), "starting the audio pipeline")
        installRateListener(on: newAggregateID)
    }

    private static func ioBlock(for processor: RealtimeDSP) -> AudioDeviceIOBlock {
        { _, input, _, output, _ in processor.render(input: input, output: output) }
    }

    /// A device renegotiating its rate or channel layout invalidates the filters and the
    /// aggregate built around it; the owner rebuilds rather than patching live state.
    private func installRateListener(on id: AudioObjectID) {
        var address = propertyAddress(kAudioDevicePropertyNominalSampleRate)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self, self.aggregateID == id else { return }
                if let rate = try? self.nominalSampleRate(of: id), rate != self.sampleRate {
                    self.onNeedsRestart?()
                }
            }
        }
        if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr { rateListener = block }
    }

    private func stopResources() {
        proofTimer?.invalidate()
        proofTimer = nil
        if let rateListener, aggregateID != kAudioObjectUnknown {
            var address = propertyAddress(kAudioDevicePropertyNominalSampleRate)
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
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        tapDescription = nil
        processor = nil
    }

    // MARK: Core Audio helpers

    private func processObjectID(for pid: pid_t) throws -> AudioObjectID {
        var address = propertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var process = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &process, &size, &object), "excluding patchbay from its own tap")
        return object
    }

    private func tapIsStereoFloat(_ id: AudioObjectID) -> Bool {
        var address = propertyAddress(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &format) == noErr else { return false }
        return format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32 && format.mChannelsPerFrame == 2
    }

    private func requireOutputChannels(_ id: AudioObjectID) throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size), "reading output channels")
        guard size >= UInt32(MemoryLayout<AudioBufferList>.size) else { throw EngineError("the selected device has no output channels; audio was left untouched") }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, list), "reading output channels")
        let channels = UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
        guard channels >= 2 else { throw EngineError("the selected device does not expose a stereo output; audio was left untouched") }
    }

    private func nominalSampleRate(of id: AudioObjectID) throws -> Double {
        var address = propertyAddress(kAudioDevicePropertyNominalSampleRate)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate), "reading the sample rate")
        return rate
    }

    private func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw CoreAudioFailure(operation: operation, status: status) }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private struct CoreAudioFailure: LocalizedError {
        let operation: String
        let status: OSStatus
        var errorDescription: String? { "\(operation) failed (OSStatus \(status)). Audio was left untouched." }
    }

    private struct EngineError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
