import CoreAudio
import Foundation

// MARK: - Persisted rack model

enum FilterType: String, Codable, CaseIterable, Identifiable {
    case lowShelf = "Low shelf"
    case peaking = "Bell"
    case highShelf = "High shelf"
    case lowPass = "Low pass"
    case highPass = "High pass"

    var id: String { rawValue }
}

struct EQBand: Codable, Identifiable, Equatable {
    var id = UUID()
    var type: FilterType
    var frequency: Double
    var gainDB: Double
    var q: Double
    var enabled: Bool
}

enum RackModuleKind: String, Codable, CaseIterable, Identifiable {
    case preamp = "Preamp"
    case equalizer = "Parametric EQ"
    case balance = "Balance"
    case limiter = "Limiter"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .preamp: "dial.medium"
        case .equalizer: "slider.horizontal.3"
        case .balance: "arrow.left.and.right"
        case .limiter: "waveform.badge.minus"
        }
    }
}

struct RackSettings: Codable, Equatable {
    var enabled = false
    var preampDB = -3.0
    var balance = 0.0
    var limiterThresholdDB = -0.5
    var modules: [RackModuleKind] = [.preamp, .equalizer, .balance, .limiter]
    var bands: [EQBand] = [
        EQBand(type: .lowShelf, frequency: 105, gainDB: 0, q: 0.71, enabled: true),
        EQBand(type: .peaking, frequency: 350, gainDB: 0, q: 1.0, enabled: true),
        EQBand(type: .peaking, frequency: 1_200, gainDB: 0, q: 1.0, enabled: true),
        EQBand(type: .peaking, frequency: 4_000, gainDB: 0, q: 1.0, enabled: true),
        EQBand(type: .highShelf, frequency: 10_000, gainDB: 0, q: 0.71, enabled: true),
    ]

    static let neutral = RackSettings()
}

final class RackSettingsStore {
    private let key = "rackSettingsByDevice"
    private var values: [String: RackSettings]

    init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: RackSettings].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
    }

    func settings(for deviceUID: String) -> RackSettings {
        values[deviceUID] ?? .neutral
    }

    func save(_ settings: RackSettings, for deviceUID: String) {
        values[deviceUID] = settings
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Immutable realtime configuration

private extension RackModuleKind {
    var realtimeValue: UInt32 {
        switch self {
        case .preamp: PBModulePreamp.rawValue
        case .equalizer: PBModuleEqualizer.rawValue
        case .balance: PBModuleBalance.rawValue
        case .limiter: PBModuleLimiter.rawValue
        }
    }
}

extension RackSettings {
    func realtimeConfig(sampleRate: Double, generation: UInt64) -> PBDSPConfig {
        var config = PBDSPConfig()
        PBDSPConfigInit(&config, generation)

        config.preampLinear = Float(pow(10, preampDB / 20))
        let clampedBalance = min(1, max(-1, balance))
        config.leftGain = Float(clampedBalance > 0 ? 1 - clampedBalance : 1)
        config.rightGain = Float(clampedBalance < 0 ? 1 + clampedBalance : 1)
        config.limiterThreshold = Float(pow(10, limiterThresholdDB / 20))

        let activeModules = enabled ? modules.prefix(Int(PB_MAX_MODULES)) : []
        config.moduleCount = UInt32(activeModules.count)
        for (index, module) in activeModules.enumerated() {
            PBDSPConfigSetModule(&config, UInt32(index), module.realtimeValue)
        }

        let activeBands = bands.prefix(Int(PB_MAX_BANDS))
        config.bandCount = UInt32(activeBands.count)
        for (index, band) in activeBands.enumerated() {
            PBDSPConfigSetBand(
                &config,
                UInt32(index),
                Self.coefficients(for: band, sampleRate: sampleRate)
            )
        }
        return config
    }

    private static func coefficients(for band: EQBand, sampleRate: Double) -> PBBiquadCoefficients {
        let frequency = min(sampleRate * 0.475, max(10, band.frequency))
        let q = max(0.1, min(18, band.q))
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosine = cos(w0)
        let sine = sin(w0)
        let alpha = sine / (2 * q)
        let a = pow(10, band.gainDB / 40)

        var b0 = 1.0
        var b1 = 0.0
        var b2 = 0.0
        var a0 = 1.0
        var a1 = 0.0
        var a2 = 0.0

        switch band.type {
        case .peaking:
            b0 = 1 + alpha * a
            b1 = -2 * cosine
            b2 = 1 - alpha * a
            a0 = 1 + alpha / a
            a1 = -2 * cosine
            a2 = 1 - alpha / a
        case .lowPass:
            b0 = (1 - cosine) / 2
            b1 = 1 - cosine
            b2 = (1 - cosine) / 2
            a0 = 1 + alpha
            a1 = -2 * cosine
            a2 = 1 - alpha
        case .highPass:
            b0 = (1 + cosine) / 2
            b1 = -(1 + cosine)
            b2 = (1 + cosine) / 2
            a0 = 1 + alpha
            a1 = -2 * cosine
            a2 = 1 - alpha
        case .lowShelf, .highShelf:
            let shelfAlpha = sine / 2 * sqrt(2)
            let twoRootAAlpha = 2 * sqrt(a) * shelfAlpha
            if band.type == .lowShelf {
                b0 = a * ((a + 1) - (a - 1) * cosine + twoRootAAlpha)
                b1 = 2 * a * ((a - 1) - (a + 1) * cosine)
                b2 = a * ((a + 1) - (a - 1) * cosine - twoRootAAlpha)
                a0 = (a + 1) + (a - 1) * cosine + twoRootAAlpha
                a1 = -2 * ((a - 1) + (a + 1) * cosine)
                a2 = (a + 1) + (a - 1) * cosine - twoRootAAlpha
            } else {
                b0 = a * ((a + 1) + (a - 1) * cosine + twoRootAAlpha)
                b1 = -2 * a * ((a - 1) + (a + 1) * cosine)
                b2 = a * ((a + 1) + (a - 1) * cosine - twoRootAAlpha)
                a0 = (a + 1) - (a - 1) * cosine + twoRootAAlpha
                a1 = 2 * ((a - 1) - (a + 1) * cosine)
                a2 = (a + 1) - (a - 1) * cosine - twoRootAAlpha
            }
        }

        return PBBiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0,
            enabled: band.enabled ? 1 : 0
        )
    }
}

// MARK: - Allocation-free render path

private struct StereoFilterMemory {
    var z1Left: Double = 0
    var z2Left: Double = 0
    var z1Right: Double = 0
    var z2Right: Double = 0
}

final class RealtimeDSP {
    private let store: OpaquePointer
    private let state: UnsafeMutablePointer<StereoFilterMemory>
    private let proofOnly: Bool
    private var lastGeneration: UInt64 = 0

    // Single-word observations. One writer (HAL), one reader (main thread).
    private(set) var sawSignal: UInt32 = 0
    private(set) var renderableLayout: UInt32 = 0
    private(set) var peak: Float = 0

    init?(settings: RackSettings, sampleRate: Double, generation: UInt64, proofOnly: Bool) {
        guard let created = PBDSPConfigStoreCreate() else { return nil }
        store = created
        state = .allocate(capacity: Int(PB_MAX_BANDS))
        state.initialize(repeating: StereoFilterMemory(), count: Int(PB_MAX_BANDS))
        self.proofOnly = proofOnly
        publish(settings, sampleRate: sampleRate, generation: generation)
    }

    deinit {
        state.deinitialize(count: Int(PB_MAX_BANDS))
        state.deallocate()
        PBDSPConfigStoreDestroy(store)
    }

    func publish(_ settings: RackSettings, sampleRate: Double, generation: UInt64) {
        var config = settings.realtimeConfig(sampleRate: sampleRate, generation: generation)
        PBDSPConfigStorePublish(store, &config)
    }

    @inline(__always)
    private func resetState() {
        for index in 0..<Int(PB_MAX_BANDS) {
            state[index] = StereoFilterMemory()
        }
    }

    @inline(__always)
    private func clear(_ output: UnsafeMutableAudioBufferListPointer) {
        for buffer in output {
            guard let data = buffer.mData else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }
    }

    @inline(__always)
    private func process(_ sample: Double, coefficients c: PBBiquadCoefficients, z1: inout Double, z2: inout Double) -> Double {
        let result = c.b0 * sample + z1
        z1 = c.b1 * sample - c.a1 * result + z2
        z2 = c.b2 * sample - c.a2 * result
        return result
    }

    @inline(__always)
    private func limit(_ sample: Double, threshold: Double) -> Double {
        let magnitude = abs(sample)
        guard magnitude > threshold else { return sample }
        let headroom = max(0.0001, 1 - threshold)
        let compressed = threshold + headroom * tanh((magnitude - threshold) / headroom)
        return sample < 0 ? -compressed : compressed
    }

    // Core Audio invokes this on the HAL realtime thread. No allocation, locking,
    // logging, Foundation, Objective-C messaging, or file access is allowed here.
    func render(input inputList: UnsafePointer<AudioBufferList>, output outputList: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputList))
        let outputs = UnsafeMutableAudioBufferListPointer(outputList)

        var sourceIndex = inputs.count - 1
        while sourceIndex >= 0 {
            let buffer = inputs[sourceIndex]
            if buffer.mNumberChannels == 2, buffer.mData != nil { break }
            sourceIndex -= 1
        }
        var destinationIndex = 0
        while destinationIndex < outputs.count {
            let buffer = outputs[destinationIndex]
            if buffer.mNumberChannels == 2, buffer.mData != nil { break }
            destinationIndex += 1
        }
        guard sourceIndex >= 0,
              destinationIndex < outputs.count,
              let inputData = inputs[sourceIndex].mData,
              let outputData = outputs[destinationIndex].mData else {
            clear(outputs)
            return
        }

        let source = inputs[sourceIndex]
        renderableLayout = 1
        let inputSamples = inputData.assumingMemoryBound(to: Float.self)
        let outputSamples = outputData.assumingMemoryBound(to: Float.self)
        let sampleCount = min(Int(source.mDataByteSize), Int(outputs[destinationIndex].mDataByteSize)) / MemoryLayout<Float>.size
        let frameCount = sampleCount / 2

        var observedPeak: Float = 0
        for frame in 0..<frameCount {
            observedPeak = max(observedPeak, abs(inputSamples[frame * 2]), abs(inputSamples[frame * 2 + 1]))
        }
        peak += 0.2 * (observedPeak - peak)
        if observedPeak > 0.0001 { sawSignal = 1 }

        if proofOnly {
            clear(outputs)
            return
        }

        guard let config = PBDSPConfigStoreLoad(store) else {
            clear(outputs)
            return
        }
        if config.pointee.generation != lastGeneration {
            resetState()
            lastGeneration = config.pointee.generation
        }

        for frame in 0..<frameCount {
            let offset = frame * 2
            var left = Double(inputSamples[offset])
            var right = Double(inputSamples[offset + 1])

            for moduleIndex in 0..<config.pointee.moduleCount {
                switch PBDSPConfigModule(config, moduleIndex) {
                case PBModulePreamp.rawValue:
                    left *= Double(config.pointee.preampLinear)
                    right *= Double(config.pointee.preampLinear)
                case PBModuleEqualizer.rawValue:
                    for bandIndex in 0..<config.pointee.bandCount {
                        guard let band = PBDSPConfigBand(config, bandIndex), band.pointee.enabled != 0 else { continue }
                        left = process(left, coefficients: band.pointee, z1: &state[Int(bandIndex)].z1Left, z2: &state[Int(bandIndex)].z2Left)
                        right = process(right, coefficients: band.pointee, z1: &state[Int(bandIndex)].z1Right, z2: &state[Int(bandIndex)].z2Right)
                    }
                case PBModuleBalance.rawValue:
                    left *= Double(config.pointee.leftGain)
                    right *= Double(config.pointee.rightGain)
                case PBModuleLimiter.rawValue:
                    let threshold = Double(config.pointee.limiterThreshold)
                    left = limit(left, threshold: threshold)
                    right = limit(right, threshold: threshold)
                default:
                    break
                }
            }

            outputSamples[offset] = Float(left)
            outputSamples[offset + 1] = Float(right)
        }

        let writtenBytes = frameCount * 2 * MemoryLayout<Float>.size
        if writtenBytes < Int(outputs[destinationIndex].mDataByteSize) {
            memset(outputData.advanced(by: writtenBytes), 0, Int(outputs[destinationIndex].mDataByteSize) - writtenBytes)
        }
        for index in outputs.indices where index != destinationIndex {
            guard let data = outputs[index].mData else { continue }
            memset(data, 0, Int(outputs[index].mDataByteSize))
        }
    }
}
