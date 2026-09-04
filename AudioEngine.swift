import AudioToolbox
import CoreAudio
import Foundation

final class SystemAudioEngine {
    enum Status: Equatable {
        case stopped
        case proving(device: String)
        case running(device: String)
        case failed(String)

        var label: String {
            switch self {
            case .stopped: "off"
            case .proving: "waiting for audio"
            case .running: "processing"
            case .failed: "error"
            }
        }
    }

    var onStatus: ((Status) -> Void)?
    private(set) var status: Status = .stopped {
        didSet { DispatchQueue.main.async { [status, weak self] in self?.onStatus?(status) } }
    }
    private(set) var outputUID: String?
    private(set) var sampleRate = 48_000.0
    var peak: Float { processor?.peak ?? 0 }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var processor: RealtimeDSP?
    private var proofTimer: Timer?
    private var settings = RackSettings.neutral
    private var generation: UInt64 = 0
    private var captureProven = false

    deinit { stop() }

    func start(output: Device, settings: RackSettings) {
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
        proofTimer?.invalidate()
        proofTimer = nil
        stopResources()
        outputUID = nil
        captureProven = false
        status = .stopped
    }

    func publish(_ settings: RackSettings) {
        self.settings = settings
        generation &+= 1
        processor?.publish(settings, sampleRate: sampleRate, generation: generation)
    }

    private func beginProof(for output: Device) {
        proofTimer?.invalidate()
        proofTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self, let processor = self.processor else {
                timer.invalidate()
                return
            }
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

    private func buildPipeline(output: Device, proofOnly: Bool) throws {
        var excluded: [AudioObjectID] = []
        if let processID = try? processObjectID(for: getpid()) {
            excluded.append(processID)
        }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.name = "patchbay system tap"
        description.isPrivate = true
        description.muteBehavior = proofOnly ? CATapMuteBehavior.unmuted : CATapMuteBehavior.mutedWhenTapped

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &newTapID), "creating the system tap")
        tapID = newTapID
        try requireFloatStereoTap(newTapID)

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
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID),
            "creating the private output"
        )
        aggregateID = newAggregateID
        try requireOutputChannels(newAggregateID)

        sampleRate = try nominalSampleRate(of: newAggregateID)
        generation &+= 1
        guard let newProcessor = RealtimeDSP(
            settings: settings,
            sampleRate: sampleRate,
            generation: generation,
            proofOnly: proofOnly
        ) else {
            throw EngineError("allocating the realtime processor failed")
        }
        processor = newProcessor

        var newIOProcID: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(
                &newIOProcID,
                newAggregateID,
                nil,
                Self.ioBlock(for: newProcessor)
            ),
            "creating the realtime output callback"
        )
        ioProcID = newIOProcID
        try check(AudioDeviceStart(newAggregateID, newIOProcID), "starting the audio pipeline")
    }

    private static func ioBlock(for processor: RealtimeDSP) -> AudioDeviceIOBlock {
        { _, input, _, output, _ in
            processor.render(input: input, output: output)
        }
    }

    private func stopResources() {
        proofTimer?.invalidate()
        proofTimer = nil

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
        processor = nil
    }

    private func processObjectID(for pid: pid_t) throws -> AudioObjectID {
        var address = propertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var process = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                &process,
                &size,
                &object
            ),
            "excluding patchbay from its own tap"
        )
        return object
    }

    private func requireFloatStereoTap(_ id: AudioObjectID) throws {
        var address = propertyAddress(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &format), "reading the tap format")
        let isFloat32 = format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        guard isFloat32, format.mChannelsPerFrame == 2 else {
            throw EngineError("the system tap did not provide stereo Float32 audio; audio was left untouched")
        }
    }

    private func requireOutputChannels(_ id: AudioObjectID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size), "reading output channels")
        guard size >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            throw EngineError("the selected device has no output channels; audio was left untouched")
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, list), "reading output channels")
        let channels = UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
        guard channels >= 2 else {
            throw EngineError("the selected device does not expose a stereo output; audio was left untouched")
        }
    }

    private func nominalSampleRate(of id: AudioObjectID) throws -> Double {
        var address = propertyAddress(kAudioDevicePropertyNominalSampleRate)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate), "reading the sample rate")
        return rate
    }

    private func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw CoreAudioFailure(operation: operation, status: status) }
    }

    private static func message(for error: Error) -> String {
        if let described = error as? LocalizedError, let message = described.errorDescription {
            return message
        }
        return error.localizedDescription
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
