import CoreAudio
import Foundation

// MARK: - Model

enum FilterType: String, Codable, CaseIterable, Identifiable {
    case peaking = "Bell"
    case lowShelf = "Low shelf"
    case highShelf = "High shelf"
    case lowPass = "Low pass"
    case highPass = "High pass"
    case bandPass = "Band pass"
    case notch = "Notch"

    var id: String { rawValue }
    var usesGain: Bool { self == .peaking || self == .lowShelf || self == .highShelf }
}

struct EQBand: Codable, Identifiable, Equatable {
    var id = UUID()
    var type: FilterType
    var frequency: Double
    var gainDB: Double
    var q: Double
    var enabled = true
}

struct ParamSpec {
    let key: String
    let label: String
    let range: ClosedRange<Double>
    let unit: String
    let step: Double
    let log: Bool
    let options: [String]?

    init(_ key: String, _ label: String, _ range: ClosedRange<Double>, unit: String = "", step: Double = 0, log: Bool = false, options: [String]? = nil) {
        self.key = key; self.label = label; self.range = range; self.unit = unit; self.step = step; self.log = log; self.options = options
    }
}

enum ModuleKind: String, Codable, CaseIterable, Identifiable {
    case gain, parametricEQ, graphicEQ, filter, loudness
    case bassEnhancer, exciter, crystalizer, crusher
    case compressor, expander, gate, deesser, limiter, maximizer, autogain
    case stereoTools, crossfeed, delay, reverb

    var id: String { rawValue }

    var realtimeValue: UInt32 {
        switch self {
        case .gain: 1
        case .parametricEQ: 2
        case .graphicEQ: 3
        case .filter: 4
        case .loudness: 5
        case .bassEnhancer: 6
        case .exciter: 7
        case .crystalizer: 8
        case .crusher: 9
        case .compressor: 10
        case .expander: 11
        case .gate: 12
        case .deesser: 13
        case .limiter: 14
        case .maximizer: 15
        case .autogain: 16
        case .stereoTools: 17
        case .crossfeed: 18
        case .delay: 19
        case .reverb: 20
        }
    }

    var title: String {
        switch self {
        case .gain: "Gain"
        case .parametricEQ: "Parametric EQ"
        case .graphicEQ: "Graphic EQ"
        case .filter: "Filter"
        case .loudness: "Loudness"
        case .bassEnhancer: "Bass enhancer"
        case .exciter: "Exciter"
        case .crystalizer: "Crystalizer"
        case .crusher: "Crusher"
        case .compressor: "Compressor"
        case .expander: "Expander"
        case .gate: "Gate"
        case .deesser: "De-esser"
        case .limiter: "Limiter"
        case .maximizer: "Maximizer"
        case .autogain: "Autogain"
        case .stereoTools: "Stereo tools"
        case .crossfeed: "Crossfeed"
        case .delay: "Delay"
        case .reverb: "Reverb"
        }
    }

    /// Canonical slot in a signal chain, earliest first. Gain staging and noise
    /// control act on the raw signal; correction (de-ess, filters, EQ) precedes
    /// dynamics so the compressor sees the fixed tone; saturation follows dynamics
    /// so harmonics are not pumped; stereo and time effects come last among the
    /// creative stages so tails are not re-compressed; loudness compensation is a
    /// playback-level EQ near the end; maximizer then limiter close the chain.
    var stage: Int {
        switch self {
        case .gain: 0
        case .gate: 1
        case .expander: 2
        case .deesser: 3
        case .filter: 4
        case .parametricEQ: 5
        case .graphicEQ: 6
        case .compressor: 7
        case .autogain: 8
        case .bassEnhancer: 9
        case .exciter: 10
        case .crystalizer: 11
        case .crusher: 12
        case .crossfeed: 13
        case .stereoTools: 14
        case .delay: 15
        case .reverb: 16
        case .loudness: 17
        case .maximizer: 18
        case .limiter: 19
        }
    }

    var group: String {
        switch self {
        case .gain, .parametricEQ, .graphicEQ, .filter, .loudness: "Tone"
        case .bassEnhancer, .exciter, .crystalizer, .crusher: "Character"
        case .compressor, .expander, .gate, .deesser, .limiter, .maximizer, .autogain: "Dynamics"
        case .stereoTools, .crossfeed, .delay, .reverb: "Space"
        }
    }

    var symbol: String {
        switch self {
        case .gain: "dial.medium"
        case .parametricEQ: "point.topleft.down.to.point.bottomright.curvepath"
        case .graphicEQ: "slider.vertical.3"
        case .filter: "line.diagonal"
        case .loudness: "ear"
        case .bassEnhancer: "waveform.path"
        case .exciter: "sparkles"
        case .crystalizer: "diamond"
        case .crusher: "square.grid.3x3"
        case .compressor: "arrow.down.right.and.arrow.up.left"
        case .expander: "arrow.up.left.and.arrow.down.right"
        case .gate: "door.left.hand.closed"
        case .deesser: "s.circle"
        case .limiter: "waveform.badge.minus"
        case .maximizer: "waveform.badge.plus"
        case .autogain: "gauge.with.needle"
        case .stereoTools: "arrow.left.and.right"
        case .crossfeed: "arrow.triangle.swap"
        case .delay: "clock.arrow.circlepath"
        case .reverb: "building.columns"
        }
    }

    var specs: [ParamSpec] {
        switch self {
        case .gain:
            [ParamSpec("gain", "Gain", -30...20, unit: "dB")]
        case .parametricEQ, .graphicEQ:
            [ParamSpec("preamp", "Preamp", -20...6, unit: "dB")]
        case .filter:
            [ParamSpec("type", "Type", 0...2, options: ["Low pass", "High pass", "Band pass"]),
             ParamSpec("cutoff", "Cutoff", 20...20_000, unit: "Hz", log: true),
             ParamSpec("slope", "Slope", 1...4, options: ["12 dB/oct", "24 dB/oct", "36 dB/oct", "48 dB/oct"])]
        case .loudness:
            [ParamSpec("amount", "Amount", 0...15, unit: "dB")]
        case .bassEnhancer:
            [ParamSpec("floor", "Floor", 20...500, unit: "Hz", log: true),
             ParamSpec("drive", "Drive", 0...24, unit: "dB"),
             ParamSpec("blend", "Blend", 0...100, unit: "%")]
        case .exciter:
            [ParamSpec("ceil", "Ceiling", 1_000...16_000, unit: "Hz", log: true),
             ParamSpec("drive", "Drive", 0...24, unit: "dB"),
             ParamSpec("blend", "Blend", 0...100, unit: "%")]
        case .crystalizer:
            [ParamSpec("intensity", "Intensity", 0...100, unit: "%")]
        case .crusher:
            [ParamSpec("bits", "Bit depth", 2...16, unit: "bit", step: 1),
             ParamSpec("reduce", "Rate reduce", 1...32, unit: "x", step: 1),
             ParamSpec("mix", "Mix", 0...100, unit: "%")]
        case .compressor:
            [ParamSpec("threshold", "Threshold", -60...0, unit: "dB"),
             ParamSpec("ratio", "Ratio", 1...20, unit: ":1"),
             ParamSpec("attack", "Attack", 0.1...200, unit: "ms", log: true),
             ParamSpec("release", "Release", 5...2_000, unit: "ms", log: true),
             ParamSpec("knee", "Knee", 0...24, unit: "dB"),
             ParamSpec("makeup", "Makeup", 0...24, unit: "dB")]
        case .expander:
            [ParamSpec("threshold", "Threshold", -80...0, unit: "dB"),
             ParamSpec("ratio", "Ratio", 1...8, unit: ":1"),
             ParamSpec("attack", "Attack", 0.1...200, unit: "ms", log: true),
             ParamSpec("release", "Release", 5...2_000, unit: "ms", log: true),
             ParamSpec("range", "Range", 0...60, unit: "dB")]
        case .gate:
            [ParamSpec("threshold", "Threshold", -80...0, unit: "dB"),
             ParamSpec("attack", "Attack", 0.1...200, unit: "ms", log: true),
             ParamSpec("release", "Release", 5...2_000, unit: "ms", log: true),
             ParamSpec("range", "Range", 0...80, unit: "dB")]
        case .deesser:
            [ParamSpec("frequency", "Frequency", 2_000...12_000, unit: "Hz", log: true),
             ParamSpec("threshold", "Threshold", -60...0, unit: "dB"),
             ParamSpec("ratio", "Ratio", 1...10, unit: ":1")]
        case .limiter:
            [ParamSpec("ceiling", "Ceiling", -12...0, unit: "dB"),
             ParamSpec("release", "Release", 5...1_000, unit: "ms", log: true)]
        case .maximizer:
            [ParamSpec("gain", "Gain", 0...24, unit: "dB"),
             ParamSpec("ceiling", "Ceiling", -12...0, unit: "dB"),
             ParamSpec("release", "Release", 5...1_000, unit: "ms", log: true)]
        case .autogain:
            [ParamSpec("target", "Target", -40...(-6), unit: "dB"),
             ParamSpec("speed", "Speed", 0.1...10, unit: "s", log: true),
             ParamSpec("maxGain", "Max gain", 0...30, unit: "dB")]
        case .stereoTools:
            [ParamSpec("width", "Width", 0...200, unit: "%"),
             ParamSpec("balance", "Balance", -100...100, unit: "%"),
             ParamSpec("mid", "Mid", -24...12, unit: "dB"),
             ParamSpec("side", "Side", -24...12, unit: "dB"),
             ParamSpec("mono", "Mono", 0...1, options: ["Stereo", "Mono"]),
             ParamSpec("swap", "Channels", 0...1, options: ["Normal", "Swapped"])]
        case .crossfeed:
            [ParamSpec("level", "Level", -12...0, unit: "dB"),
             ParamSpec("cutoff", "Cutoff", 300...2_000, unit: "Hz", log: true),
             ParamSpec("delay", "Delay", 0...1.5, unit: "ms")]
        case .delay:
            [ParamSpec("left", "Left", 0...1_000, unit: "ms"),
             ParamSpec("right", "Right", 0...1_000, unit: "ms"),
             ParamSpec("feedback", "Feedback", 0...90, unit: "%"),
             ParamSpec("wet", "Wet", 0...100, unit: "%"),
             ParamSpec("dry", "Dry", 0...100, unit: "%")]
        case .reverb:
            [ParamSpec("room", "Room size", 0...100, unit: "%"),
             ParamSpec("damp", "Damping", 0...100, unit: "%"),
             ParamSpec("width", "Width", 0...100, unit: "%"),
             ParamSpec("wet", "Wet", 0...100, unit: "%"),
             ParamSpec("dry", "Dry", 0...100, unit: "%")]
        }
    }

    var defaults: [String: Double] {
        switch self {
        case .gain: ["gain": 0]
        case .parametricEQ, .graphicEQ: ["preamp": 0]
        case .filter: ["type": 1, "cutoff": 80, "slope": 2]
        case .loudness: ["amount": 6]
        case .bassEnhancer: ["floor": 120, "drive": 6, "blend": 35]
        case .exciter: ["ceil": 6_000, "drive": 6, "blend": 25]
        case .crystalizer: ["intensity": 30]
        case .crusher: ["bits": 8, "reduce": 2, "mix": 100]
        case .compressor: ["threshold": -18, "ratio": 3, "attack": 10, "release": 120, "knee": 6, "makeup": 0]
        case .expander: ["threshold": -45, "ratio": 2, "attack": 5, "release": 150, "range": 24]
        case .gate: ["threshold": -50, "attack": 1, "release": 100, "range": 60]
        case .deesser: ["frequency": 6_000, "threshold": -24, "ratio": 4]
        case .limiter: ["ceiling": -0.3, "release": 60]
        case .maximizer: ["gain": 6, "ceiling": -0.3, "release": 60]
        case .autogain: ["target": -18, "speed": 2, "maxGain": 12]
        case .stereoTools: ["width": 100, "balance": 0, "mid": 0, "side": 0, "mono": 0, "swap": 0]
        case .crossfeed: ["level": -4.5, "cutoff": 700, "delay": 0.3]
        case .delay: ["left": 0, "right": 12, "feedback": 0, "wet": 50, "dry": 100]
        case .reverb: ["room": 50, "damp": 50, "width": 100, "wet": 20, "dry": 100]
        }
    }

    var defaultBands: [EQBand] {
        switch self {
        case .parametricEQ:
            [EQBand(type: .lowShelf, frequency: 105, gainDB: 0, q: 0.71),
             EQBand(type: .peaking, frequency: 350, gainDB: 0, q: 1),
             EQBand(type: .peaking, frequency: 1_200, gainDB: 0, q: 1),
             EQBand(type: .peaking, frequency: 4_000, gainDB: 0, q: 1),
             EQBand(type: .highShelf, frequency: 10_000, gainDB: 0, q: 0.71)]
        case .graphicEQ:
            ModuleKind.graphicFrequencies.map { EQBand(type: .peaking, frequency: $0, gainDB: 0, q: 1.8) }
        default: []
        }
    }

    static let graphicFrequencies: [Double] = [25, 40, 63, 100, 160, 250, 400, 630, 1_000, 1_600, 2_500, 4_000, 6_300, 10_000, 16_000, 20_000]
}

struct RackModule: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ModuleKind
    var enabled = true
    var name: String?
    var params: [String: Double]
    var bands: [EQBand]

    init(kind: ModuleKind, name: String? = nil) {
        self.kind = kind
        self.name = name
        self.params = kind.defaults
        self.bands = kind.defaultBands
    }

    var title: String { name ?? kind.title }

    func param(_ key: String) -> Double {
        params[key] ?? kind.defaults[key] ?? 0
    }
}

struct RackSettings: Codable, Equatable {
    var enabled = false
    var bypass = false
    var modules: [RackModule] = [RackModule(kind: .parametricEQ), RackModule(kind: .limiter)]

    static let neutral = RackSettings()

    var layoutKey: String {
        modules.map { "\($0.id):\($0.kind.rawValue):\($0.bands.count)" }.joined(separator: "|")
    }
}

final class RackSettingsStore {
    private let key = "rackSettingsByDevice.v2"
    private var values: [String: RackSettings]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: RackSettings].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
    }

    func settings(for deviceUID: String) -> RackSettings { values[deviceUID] ?? .neutral }

    func save(_ settings: RackSettings, for deviceUID: String) {
        values[deviceUID] = settings
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Equalizer APO preset format

struct ParametricPreset {
    var preampDB: Double
    var bands: [EQBand]

    /// Parses Equalizer APO / AutoEq `ParametricEQ.txt` text.
    /// `Preamp: -6.1 dB` / `Filter 1: ON LSC Fc 105 Hz Gain 6.4 dB Q 0.70`
    static func parse(_ text: String) -> ParametricPreset? {
        var preamp = 0.0
        var bands: [EQBand] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let tokens = line.split(separator: " ").map(String.init)
            if line.lowercased().hasPrefix("preamp:"), tokens.count >= 2, let value = Double(tokens[1]) {
                preamp = value
                continue
            }
            guard line.lowercased().hasPrefix("filter"), let onIndex = tokens.firstIndex(where: { $0 == "ON" || $0 == "OFF" }) else { continue }
            let enabled = tokens[onIndex] == "ON"
            guard onIndex + 1 < tokens.count else { continue }
            let typeCode = tokens[onIndex + 1].uppercased()
            let type: FilterType
            switch typeCode {
            case "PK", "PEQ", "MODAL": type = .peaking
            case "LS", "LSC", "LSQ": type = .lowShelf
            case "HS", "HSC", "HSQ": type = .highShelf
            case "LP", "LPQ": type = .lowPass
            case "HP", "HPQ": type = .highPass
            case "BP": type = .bandPass
            case "NO": type = .notch
            default: continue
            }
            func value(after key: String) -> Double? {
                guard let index = tokens.firstIndex(of: key), index + 1 < tokens.count else { return nil }
                return Double(tokens[index + 1])
            }
            guard let frequency = value(after: "Fc") else { continue }
            let gain = value(after: "Gain") ?? 0
            let q = value(after: "Q") ?? (type == .lowShelf || type == .highShelf ? 0.707 : 1)
            bands.append(EQBand(type: type, frequency: frequency, gainDB: gain, q: q, enabled: enabled))
        }
        guard !bands.isEmpty else { return nil }
        return ParametricPreset(preampDB: preamp, bands: bands)
    }

    var exportText: String {
        var lines = [String(format: "Preamp: %.1f dB", preampDB)]
        for (index, band) in bands.enumerated() {
            let code: String
            switch band.type {
            case .peaking: code = "PK"
            case .lowShelf: code = "LSC"
            case .highShelf: code = "HSC"
            case .lowPass: code = "LPQ"
            case .highPass: code = "HPQ"
            case .bandPass: code = "BP"
            case .notch: code = "NO"
            }
            lines.append(String(format: "Filter %d: %@ %@ Fc %.0f Hz Gain %.1f dB Q %.2f", index + 1, band.enabled ? "ON" : "OFF", code, band.frequency, band.gainDB, band.q))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Biquad design (RBJ cookbook)

enum BiquadDesign {
    static func coefficients(type: FilterType, frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> PBBiquad {
        let f = min(sampleRate * 0.49, max(10, frequency))
        let q = max(0.05, min(30, q))
        let w0 = 2 * Double.pi * f / sampleRate
        let cosine = cos(w0)
        let sine = sin(w0)
        let alpha = sine / (2 * q)
        let a = pow(10, gainDB / 40)

        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0
        switch type {
        case .peaking:
            b0 = 1 + alpha * a; b1 = -2 * cosine; b2 = 1 - alpha * a
            a0 = 1 + alpha / a; a1 = -2 * cosine; a2 = 1 - alpha / a
        case .lowPass:
            b0 = (1 - cosine) / 2; b1 = 1 - cosine; b2 = (1 - cosine) / 2
            a0 = 1 + alpha; a1 = -2 * cosine; a2 = 1 - alpha
        case .highPass:
            b0 = (1 + cosine) / 2; b1 = -(1 + cosine); b2 = (1 + cosine) / 2
            a0 = 1 + alpha; a1 = -2 * cosine; a2 = 1 - alpha
        case .bandPass:
            b0 = alpha; b1 = 0; b2 = -alpha
            a0 = 1 + alpha; a1 = -2 * cosine; a2 = 1 - alpha
        case .notch:
            b0 = 1; b1 = -2 * cosine; b2 = 1
            a0 = 1 + alpha; a1 = -2 * cosine; a2 = 1 - alpha
        case .lowShelf, .highShelf:
            let beta = sine * sqrt(a) / q
            if type == .lowShelf {
                b0 = a * ((a + 1) - (a - 1) * cosine + beta)
                b1 = 2 * a * ((a - 1) - (a + 1) * cosine)
                b2 = a * ((a + 1) - (a - 1) * cosine - beta)
                a0 = (a + 1) + (a - 1) * cosine + beta
                a1 = -2 * ((a - 1) + (a + 1) * cosine)
                a2 = (a + 1) + (a - 1) * cosine - beta
            } else {
                b0 = a * ((a + 1) + (a - 1) * cosine + beta)
                b1 = -2 * a * ((a - 1) + (a + 1) * cosine)
                b2 = a * ((a + 1) + (a - 1) * cosine - beta)
                a0 = (a + 1) - (a - 1) * cosine + beta
                a1 = 2 * ((a - 1) - (a + 1) * cosine)
                a2 = (a + 1) - (a - 1) * cosine - beta
            }
        }
        return PBBiquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Butterworth Q values for a cascade of `sections` second-order stages.
    static func butterworthQ(sections: Int) -> [Double] {
        (0..<sections).map { k in 1 / (2 * cos(Double(2 * k + 1) * Double.pi / Double(4 * sections))) }
    }
}

// MARK: - Compile settings into a realtime snapshot

extension RackSettings {
    func realtimeConfig(sampleRate: Double, generation: UInt64, layoutGeneration: UInt64) -> PBDSPConfig {
        var config = PBDSPConfig()
        config.generation = generation
        config.layoutGeneration = layoutGeneration
        config.sampleRate = Float(sampleRate)
        config.bypass = bypass ? 1 : 0

        var biquads: [PBBiquad] = []
        var compiled: [PBModule] = []

        func dbToLin(_ db: Double) -> Float { Float(pow(10, db / 20)) }
        func coef(ms: Double) -> Float { Float(exp(-1 / (sampleRate * max(0.01, ms) / 1000))) }

        for module in modules.prefix(Int(PB_MAX_MODULES)) {
            var m = PBModule()
            m.kind = module.kind.realtimeValue
            m.enabled = module.enabled ? 1 : 0
            m.biquadStart = UInt32(biquads.count)
            var p: [Float] = []
            let kind = module.kind
            let v = module.param

            switch kind {
            case .gain:
                p = [dbToLin(v("gain"))]
            case .parametricEQ, .graphicEQ:
                p = [dbToLin(v("preamp"))]
                for band in module.bands where band.enabled {
                    biquads.append(BiquadDesign.coefficients(type: band.type, frequency: band.frequency, gainDB: band.gainDB, q: band.q, sampleRate: sampleRate))
                }
            case .filter:
                let type: FilterType = [FilterType.lowPass, .highPass, .bandPass][min(2, max(0, Int(v("type"))))]
                let sections = min(4, max(1, Int(v("slope"))))
                let qs = type == .bandPass ? Array(repeating: 1.0, count: sections) : BiquadDesign.butterworthQ(sections: sections)
                for q in qs {
                    biquads.append(BiquadDesign.coefficients(type: type, frequency: v("cutoff"), gainDB: 0, q: q, sampleRate: sampleRate))
                }
            case .loudness:
                let amount = v("amount")
                biquads.append(BiquadDesign.coefficients(type: .lowShelf, frequency: 100, gainDB: amount, q: 0.707, sampleRate: sampleRate))
                biquads.append(BiquadDesign.coefficients(type: .highShelf, frequency: 8_000, gainDB: amount * 0.4, q: 0.707, sampleRate: sampleRate))
            case .bassEnhancer:
                p = [dbToLin(v("drive")), Float(v("blend") / 100)]
                for q in BiquadDesign.butterworthQ(sections: 2) {
                    biquads.append(BiquadDesign.coefficients(type: .lowPass, frequency: v("floor"), gainDB: 0, q: q, sampleRate: sampleRate))
                }
            case .exciter:
                p = [dbToLin(v("drive")), Float(v("blend") / 100)]
                for q in BiquadDesign.butterworthQ(sections: 2) {
                    biquads.append(BiquadDesign.coefficients(type: .highPass, frequency: v("ceil"), gainDB: 0, q: q, sampleRate: sampleRate))
                }
            case .crystalizer:
                p = [Float(v("intensity") / 100)]
            case .crusher:
                p = [Float(pow(2, v("bits") - 1)), Float(max(1, v("reduce").rounded())), Float(v("mix") / 100)]
            case .compressor:
                p = [Float(v("threshold")), Float(v("ratio")), coef(ms: v("attack")), coef(ms: v("release")), Float(v("knee")), dbToLin(v("makeup"))]
            case .expander:
                p = [Float(v("threshold")), Float(v("ratio")), coef(ms: v("attack")), coef(ms: v("release")), Float(v("range"))]
            case .gate:
                p = [Float(v("threshold")), coef(ms: v("attack")), coef(ms: v("release")), Float(v("range"))]
            case .deesser:
                p = [Float(v("threshold")), Float(v("ratio")), coef(ms: 1), coef(ms: 40)]
                biquads.append(BiquadDesign.coefficients(type: .bandPass, frequency: v("frequency"), gainDB: 0, q: 2, sampleRate: sampleRate))
            case .limiter:
                p = [dbToLin(v("ceiling")), coef(ms: v("release"))]
            case .maximizer:
                p = [dbToLin(v("gain")), dbToLin(v("ceiling")), coef(ms: v("release"))]
            case .autogain:
                p = [Float(v("target")), coef(ms: v("speed") * 1000), Float(v("maxGain")), coef(ms: 300)]
            case .stereoTools:
                p = [Float(v("width") / 100), Float(v("balance") / 100), dbToLin(v("mid")), dbToLin(v("side")), Float(v("mono")), Float(v("swap"))]
            case .crossfeed:
                p = [dbToLin(v("level")), Float(v("delay") / 1000 * sampleRate)]
                biquads.append(BiquadDesign.coefficients(type: .lowPass, frequency: v("cutoff"), gainDB: 0, q: 0.707, sampleRate: sampleRate))
            case .delay:
                p = [Float(v("left") / 1000 * sampleRate), Float(v("right") / 1000 * sampleRate), Float(v("feedback") / 100), Float(v("wet") / 100), Float(v("dry") / 100)]
            case .reverb:
                p = [Float(v("room") / 100 * 0.28 + 0.7), Float(v("damp") / 100 * 0.4), Float(v("width") / 100), Float(v("wet") / 100 * 3), Float(v("dry") / 100)]
            }

            m.biquadCount = UInt32(biquads.count) - m.biquadStart
            withUnsafeMutableBytes(of: &m.params) { raw in
                let floats = raw.bindMemory(to: Float.self)
                for (i, value) in p.prefix(Int(PB_MAX_PARAMS)).enumerated() { floats[i] = value }
            }
            compiled.append(m)
            if biquads.count > Int(PB_MAX_BIQUADS) { break }
        }

        config.moduleCount = UInt32(compiled.count)
        config.biquadCount = UInt32(min(biquads.count, Int(PB_MAX_BIQUADS)))
        withUnsafeMutableBytes(of: &config.modules) { raw in
            let slots = raw.bindMemory(to: PBModule.self)
            for (i, m) in compiled.enumerated() { slots[i] = m }
        }
        withUnsafeMutableBytes(of: &config.biquads) { raw in
            let slots = raw.bindMemory(to: PBBiquad.self)
            for (i, b) in biquads.prefix(Int(PB_MAX_BIQUADS)).enumerated() { slots[i] = b }
        }
        return config
    }
}

// MARK: - Realtime engine

private struct BiquadMemory {
    var z1L = 0.0, z2L = 0.0, z1R = 0.0, z2R = 0.0
}

private struct ModuleMemory {
    var d = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)  // generic scalar state
    var lineWrite = 0
}

/// Everything the HAL thread touches. Allocated once on the main thread when the
/// pipeline is built; `render` never allocates, locks, or calls into Foundation.
final class RealtimeDSP {
    private static let scratchFrames = 4096
    private static let reverbCombs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private static let reverbAllpasses = [556, 441, 341, 225]
    private static let reverbSpread = 23

    private let store: OpaquePointer
    private let proofOnly: Bool
    private let sampleRate: Double
    private let biquadMemory: UnsafeMutablePointer<BiquadMemory>
    private let moduleMemory: UnsafeMutablePointer<ModuleMemory>
    private let lineCapacity: Int
    private let lines: UnsafeMutablePointer<Float>          // PB_MAX_MODULES * lineCapacity
    private let reverbState: UnsafeMutablePointer<Double>    // PB_MAX_MODULES * 64 (comb/allpass indices + damp memory)
    private let scratchL: UnsafeMutablePointer<Double>
    private let scratchR: UnsafeMutablePointer<Double>
    private var lastLayout: UInt64 = .max
    private let reverbGeometry: UnsafeMutablePointer<Int>   // 24 ints, see runReverb
    private let reverbFits: Bool

    // Single-word observations: HAL thread writes, main thread reads.
    private(set) var sawSignal: UInt32 = 0
    private(set) var renderableLayout: UInt32 = 0
    private(set) var inputPeak: Float = 0
    private(set) var outputPeak: Float = 0

    init?(settings: RackSettings, sampleRate: Double, generation: UInt64, layoutGeneration: UInt64, proofOnly: Bool) {
        guard let created = PBDSPConfigStoreCreate() else { return nil }
        store = created
        self.proofOnly = proofOnly
        self.sampleRate = sampleRate
        let modules = Int(PB_MAX_MODULES)
        biquadMemory = .allocate(capacity: Int(PB_MAX_BIQUADS))
        biquadMemory.initialize(repeating: BiquadMemory(), count: Int(PB_MAX_BIQUADS))
        moduleMemory = .allocate(capacity: modules)
        moduleMemory.initialize(repeating: ModuleMemory(), count: modules)
        lineCapacity = Int(sampleRate * 2.2)
        lines = .allocate(capacity: modules * lineCapacity)
        lines.initialize(repeating: 0, count: modules * lineCapacity)
        reverbState = .allocate(capacity: modules * 64)
        reverbState.initialize(repeating: 0, count: modules * 64)
        reverbGeometry = .allocate(capacity: 24)
        var cursor = 0
        let scale = sampleRate / 44_100
        for c in 0..<8 {
            reverbGeometry[c] = Int(Double(Self.reverbCombs[c]) * scale)
            reverbGeometry[8 + c] = cursor
            cursor += reverbGeometry[c] + Self.reverbSpread
        }
        for a in 0..<4 {
            reverbGeometry[16 + a] = Int(Double(Self.reverbAllpasses[a]) * scale)
            reverbGeometry[20 + a] = cursor
            cursor += reverbGeometry[16 + a] + Self.reverbSpread
        }
        reverbFits = cursor < lineCapacity / 2
        scratchL = .allocate(capacity: Self.scratchFrames)
        scratchR = .allocate(capacity: Self.scratchFrames)
        publish(settings, generation: generation, layoutGeneration: layoutGeneration)
    }

    deinit {
        biquadMemory.deallocate()
        moduleMemory.deallocate()
        lines.deallocate()
        reverbState.deallocate()
        reverbGeometry.deallocate()
        scratchL.deallocate()
        scratchR.deallocate()
        PBDSPConfigStoreDestroy(store)
    }

    func publish(_ settings: RackSettings, generation: UInt64, layoutGeneration: UInt64) {
        var config = settings.realtimeConfig(sampleRate: sampleRate, generation: generation, layoutGeneration: layoutGeneration)
        PBDSPConfigStorePublish(store, &config)
    }

    // MARK: Render entry

    func render(input inputList: UnsafePointer<AudioBufferList>, output outputList: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputList))
        let outputs = UnsafeMutableAudioBufferListPointer(outputList)

        var sourceIndex = inputs.count - 1
        while sourceIndex >= 0 {
            let b = inputs[sourceIndex]
            if b.mNumberChannels == 2, b.mData != nil { break }
            sourceIndex -= 1
        }
        var destinationIndex = 0
        while destinationIndex < outputs.count {
            let b = outputs[destinationIndex]
            if b.mNumberChannels == 2, b.mData != nil { break }
            destinationIndex += 1
        }
        guard sourceIndex >= 0, destinationIndex < outputs.count,
              let inputData = inputs[sourceIndex].mData,
              let outputData = outputs[destinationIndex].mData else {
            clear(outputs)
            return
        }

        renderableLayout = 1
        let inSamples = inputData.assumingMemoryBound(to: Float.self)
        let outSamples = outputData.assumingMemoryBound(to: Float.self)
        let outBytes = Int(outputs[destinationIndex].mDataByteSize)
        let frameCount = min(Int(inputs[sourceIndex].mDataByteSize), outBytes) / (2 * MemoryLayout<Float>.size)

        var peakIn: Float = 0
        for i in 0..<(frameCount * 2) { peakIn = max(peakIn, abs(inSamples[i])) }
        inputPeak += 0.25 * (peakIn - inputPeak)
        if peakIn > 0.0001 { sawSignal = 1 }

        if proofOnly { clear(outputs); return }
        guard let config = PBDSPConfigStoreLoad(store) else { clear(outputs); return }

        if config.pointee.layoutGeneration != lastLayout {
            resetMemory()
            lastLayout = config.pointee.layoutGeneration
        }

        if config.pointee.bypass != 0 || config.pointee.moduleCount == 0 {
            memcpy(outSamples, inSamples, frameCount * 2 * MemoryLayout<Float>.size)
            outputPeak += 0.25 * (peakIn - outputPeak)
        } else {
            var done = 0
            var peakOut: Float = 0
            while done < frameCount {
                let n = min(Self.scratchFrames, frameCount - done)
                for i in 0..<n {
                    scratchL[i] = Double(inSamples[(done + i) * 2])
                    scratchR[i] = Double(inSamples[(done + i) * 2 + 1])
                }
                process(config, frames: n)
                for i in 0..<n {
                    var l = Float(scratchL[i]), r = Float(scratchR[i])
                    if !l.isFinite { l = 0 }
                    if !r.isFinite { r = 0 }
                    outSamples[(done + i) * 2] = l
                    outSamples[(done + i) * 2 + 1] = r
                    peakOut = max(peakOut, abs(l), abs(r))
                }
                done += n
            }
            outputPeak += 0.25 * (peakOut - outputPeak)
        }

        let written = frameCount * 2 * MemoryLayout<Float>.size
        if written < outBytes { memset(outputData.advanced(by: written), 0, outBytes - written) }
        for i in outputs.indices where i != destinationIndex {
            if let d = outputs[i].mData { memset(d, 0, Int(outputs[i].mDataByteSize)) }
        }
    }

    // MARK: Chain

    private static let modulesOffset = MemoryLayout<PBDSPConfig>.offset(of: \.modules)!
    private static let biquadsOffset = MemoryLayout<PBDSPConfig>.offset(of: \.biquads)!
    private static let paramsOffset = MemoryLayout<PBModule>.offset(of: \.params)!

    private func process(_ config: UnsafePointer<PBDSPConfig>, frames n: Int) {
        let count = Int(config.pointee.moduleCount)
        let base = UnsafeRawPointer(config)
        let modules = (base + Self.modulesOffset).assumingMemoryBound(to: PBModule.self)
        let biquads = (base + Self.biquadsOffset).assumingMemoryBound(to: PBBiquad.self)
        for slot in 0..<count {
            let m = modules + slot
            guard m.pointee.enabled != 0 else { continue }
            let p = (UnsafeRawPointer(m) + Self.paramsOffset).assumingMemoryBound(to: Float.self)
            runModule(kind: m.pointee.kind, slot: slot, p: p,
                      biquads: biquads + Int(m.pointee.biquadStart),
                      biquadStart: Int(m.pointee.biquadStart),
                      biquadCount: Int(m.pointee.biquadCount), frames: n)
        }
    }

    @inline(__always)
    private func biquadRun(_ c: PBBiquad, _ mem: UnsafeMutablePointer<BiquadMemory>, _ l: inout Double, _ r: inout Double) {
        let yl = c.b0 * l + mem.pointee.z1L
        mem.pointee.z1L = c.b1 * l - c.a1 * yl + mem.pointee.z2L
        mem.pointee.z2L = c.b2 * l - c.a2 * yl
        let yr = c.b0 * r + mem.pointee.z1R
        mem.pointee.z1R = c.b1 * r - c.a1 * yr + mem.pointee.z2R
        mem.pointee.z2R = c.b2 * r - c.a2 * yr
        l = yl; r = yr
    }

    @inline(__always)
    private func dB(_ x: Double) -> Double { 20 * log10(x + 1e-9) }

    @inline(__always)
    private func computeGainReduction(over: Double, ratio: Double, knee: Double) -> Double {
        if over <= -knee / 2 { return 0 }
        if over >= knee / 2 || knee <= 0 { return (1 / ratio - 1) * over }
        let x = over + knee / 2
        return (1 / ratio - 1) * x * x / (2 * knee)
    }

    private func runModule(kind: UInt32, slot: Int, p: UnsafePointer<Float>, biquads: UnsafePointer<PBBiquad>, biquadStart: Int, biquadCount: Int, frames n: Int) {
        let mem = moduleMemory + slot
        let line = lines + slot * lineCapacity
        let bq = biquadMemory + biquadStart

        switch kind {
        case 1: // gain
            let g = Double(p[0])
            for i in 0..<n { scratchL[i] *= g; scratchR[i] *= g }

        case 2, 3: // parametric / graphic EQ
            let g = Double(p[0])
            for i in 0..<n {
                var l = scratchL[i] * g, r = scratchR[i] * g
                for b in 0..<biquadCount { biquadRun(biquads[b], bq + b, &l, &r) }
                scratchL[i] = l; scratchR[i] = r
            }

        case 4, 5: // filter cascade, loudness shelves
            for i in 0..<n {
                var l = scratchL[i], r = scratchR[i]
                for b in 0..<biquadCount { biquadRun(biquads[b], bq + b, &l, &r) }
                scratchL[i] = l; scratchR[i] = r
            }

        case 6, 7: // bass enhancer (LP → saturate → blend), exciter (HP → saturate → blend)
            let drive = Double(p[0]), blend = Double(p[1])
            for i in 0..<n {
                var l = scratchL[i], r = scratchR[i]
                for b in 0..<biquadCount { biquadRun(biquads[b], bq + b, &l, &r) }
                let hl = tanh(l * drive) - tanh(l), hr = tanh(r * drive) - tanh(r)
                scratchL[i] += hl * blend; scratchR[i] += hr * blend
            }

        case 8: // crystalizer
            let k = Double(p[0]) * 2
            for i in 0..<n {
                let l = scratchL[i], r = scratchR[i]
                scratchL[i] = l + k * (l - mem.pointee.d.0)
                scratchR[i] = r + k * (r - mem.pointee.d.1)
                mem.pointee.d.0 = l; mem.pointee.d.1 = r
            }

        case 9: // crusher
            let levels = Double(p[0]), hold = Int(p[1]), mix = Double(p[2])
            for i in 0..<n {
                var counter = Int(mem.pointee.d.2)
                if counter <= 0 {
                    mem.pointee.d.0 = (scratchL[i] * levels).rounded() / levels
                    mem.pointee.d.1 = (scratchR[i] * levels).rounded() / levels
                    counter = hold
                }
                counter -= 1
                mem.pointee.d.2 = Double(counter)
                scratchL[i] += (mem.pointee.d.0 - scratchL[i]) * mix
                scratchR[i] += (mem.pointee.d.1 - scratchR[i]) * mix
            }

        case 10: // compressor (stereo-linked peak detector)
            let thr = Double(p[0]), ratio = Double(p[1]), att = Double(p[2]), rel = Double(p[3]), knee = Double(p[4]), makeup = Double(p[5])
            var env = mem.pointee.d.0
            for i in 0..<n {
                let level = max(abs(scratchL[i]), abs(scratchR[i]))
                env = level > env ? att * env + (1 - att) * level : rel * env + (1 - rel) * level
                let g = pow(10, computeGainReduction(over: dB(env) - thr, ratio: ratio, knee: knee) / 20) * makeup
                scratchL[i] *= g; scratchR[i] *= g
            }
            mem.pointee.d.0 = env

        case 11, 12: // expander, gate
            let thr = Double(p[0])
            let ratio = kind == 11 ? Double(p[1]) : 20
            let att = Double(kind == 11 ? p[2] : p[1]), rel = Double(kind == 11 ? p[3] : p[2])
            let range = Double(kind == 11 ? p[4] : p[3])
            var env = mem.pointee.d.0
            for i in 0..<n {
                let level = max(abs(scratchL[i]), abs(scratchR[i]))
                env = level > env ? att * env + (1 - att) * level : rel * env + (1 - rel) * level
                let under = thr - dB(env)
                let reduction = under > 0 ? min(range, (ratio - 1) * under) : 0
                let g = pow(10, -reduction / 20)
                scratchL[i] *= g; scratchR[i] *= g
            }
            mem.pointee.d.0 = env

        case 13: // de-esser: band-pass sidechain drives a compressor on the full signal
            let thr = Double(p[0]), ratio = Double(p[1]), att = Double(p[2]), rel = Double(p[3])
            var env = mem.pointee.d.0
            for i in 0..<n {
                var sl = scratchL[i], sr = scratchR[i]
                for b in 0..<biquadCount { biquadRun(biquads[b], bq + b, &sl, &sr) }
                let level = max(abs(sl), abs(sr))
                env = level > env ? att * env + (1 - att) * level : rel * env + (1 - rel) * level
                let g = pow(10, computeGainReduction(over: dB(env) - thr, ratio: ratio, knee: 3) / 20)
                scratchL[i] *= g; scratchR[i] *= g
            }
            mem.pointee.d.0 = env

        case 14, 15: // limiter, maximizer
            let pre = kind == 15 ? Double(p[0]) : 1
            let ceiling = Double(kind == 15 ? p[1] : p[0]), rel = Double(kind == 15 ? p[2] : p[1])
            var env = mem.pointee.d.0
            for i in 0..<n {
                var l = scratchL[i] * pre, r = scratchR[i] * pre
                let level = max(abs(l), abs(r))
                env = level > env ? level : rel * env + (1 - rel) * level
                let g = env > ceiling ? ceiling / env : 1
                l *= g; r *= g
                scratchL[i] = min(ceiling, max(-ceiling, l))
                scratchR[i] = min(ceiling, max(-ceiling, r))
            }
            mem.pointee.d.0 = env

        case 16: // autogain: RMS follower steering a slow gain toward the target
            let target = Double(p[0]), speed = Double(p[1]), maxGain = Double(p[2]), rmsCoef = Double(p[3])
            var rms = mem.pointee.d.0, gainDB = mem.pointee.d.1
            for i in 0..<n {
                let sq = (scratchL[i] * scratchL[i] + scratchR[i] * scratchR[i]) * 0.5
                rms = rmsCoef * rms + (1 - rmsCoef) * sq
                let levelDB = 10 * log10(rms + 1e-12)
                if levelDB > -70 {
                    let desired = min(maxGain, max(-maxGain, target - levelDB))
                    gainDB = speed * gainDB + (1 - speed) * desired
                }
                let g = pow(10, gainDB / 20)
                scratchL[i] *= g; scratchR[i] *= g
            }
            mem.pointee.d.0 = rms; mem.pointee.d.1 = gainDB

        case 17: // stereo tools
            let width = Double(p[0]), balance = Double(p[1]), midG = Double(p[2]), sideG = Double(p[3])
            let mono = p[4] > 0.5, swap = p[5] > 0.5
            let lBal = balance > 0 ? 1 - balance : 1, rBal = balance < 0 ? 1 + balance : 1
            for i in 0..<n {
                var l = scratchL[i], r = scratchR[i]
                if swap { let t = l; l = r; r = t }
                let mid = (l + r) * 0.5 * midG
                var side = (l - r) * 0.5 * sideG * width
                if mono { side = 0 }
                scratchL[i] = (mid + side) * lBal
                scratchR[i] = (mid - side) * rBal
            }

        case 18: // crossfeed: delayed, low-passed opposite channel blended in
            let level = Double(p[0])
            let delay = min(lineCapacity / 2 - 2, max(1, Int(p[1])))
            let half = lineCapacity / 2
            var w = mem.pointee.lineWrite
            for i in 0..<n {
                let l = scratchL[i], r = scratchR[i]
                let rd = (w - delay + half) % half
                var xl = Double(line[half + rd]), xr = Double(line[rd])   // cross: L gets delayed R
                for b in 0..<biquadCount { biquadRun(biquads[b], bq + b, &xl, &xr) }
                line[w] = Float(l); line[half + w] = Float(r)
                w = (w + 1) % half
                scratchL[i] = (l + xl * level) / (1 + level)
                scratchR[i] = (r + xr * level) / (1 + level)
            }
            mem.pointee.lineWrite = w

        case 19: // delay
            let half = lineCapacity / 2
            let dl = min(half - 2, max(0, Int(p[0]))), dr = min(half - 2, max(0, Int(p[1])))
            let fb = Double(p[2]), wet = Double(p[3]), dry = Double(p[4])
            var w = mem.pointee.lineWrite
            for i in 0..<n {
                let l = scratchL[i], r = scratchR[i]
                let tl = Double(line[(w - dl + half) % half]), tr = Double(line[half + (w - dr + half) % half])
                line[w] = Float(l + tl * fb); line[half + w] = Float(r + tr * fb)
                w = (w + 1) % half
                scratchL[i] = l * dry + tl * wet
                scratchR[i] = r * dry + tr * wet
            }
            mem.pointee.lineWrite = w

        case 20: // Freeverb
            runReverb(slot: slot, p: p, line: line, frames: n)

        default:
            break
        }
    }

    /// Freeverb (Jezar, public domain): 8 parallel lowpass-feedback combs → 4 series allpasses per channel.
    /// Line layout per channel: combs then allpasses, right channel offset by `reverbSpread` samples.
    private func runReverb(slot: Int, p: UnsafePointer<Float>, line: UnsafeMutablePointer<Float>, frames n: Int) {
        let room = Double(p[0]), damp = Double(p[1]), width = Double(p[2]), wet = Double(p[3]), dry = Double(p[4])
        let wet1 = wet * (width / 2 + 0.5), wet2 = wet * ((1 - width) / 2)
        let st = reverbState + slot * 64   // [0..8) comb idx L, [8..16) comb idx R, [16..20) ap idx L, [20..24) ap idx R, [24..32) filt L, [32..40) filt R
        let half = lineCapacity / 2
        let rl = line, rr = line + half

        let geo = reverbGeometry   // [combSize×8, combOffset×8, apSize×4, apOffset×4], computed at init
        guard reverbFits else { return }

        for i in 0..<n {
            let input = (scratchL[i] + scratchR[i]) * 0.015
            var outL = 0.0, outR = 0.0
            for c in 0..<8 {
                // left
                var idx = Int(st[c]); let sizeL = geo[c]
                let base = rl + geo[8 + c]
                var out = Double(base[idx])
                var filt = st[24 + c]
                filt = out * (1 - damp) + filt * damp
                base[idx] = Float(input + filt * room)
                st[24 + c] = filt
                idx += 1; if idx >= sizeL { idx = 0 }
                st[c] = Double(idx)
                outL += out
                // right (spread)
                idx = Int(st[8 + c]); let sizeR = sizeL + Self.reverbSpread
                let baseR = rr + geo[8 + c]
                out = Double(baseR[idx])
                filt = st[32 + c]
                filt = out * (1 - damp) + filt * damp
                baseR[idx] = Float(input + filt * room)
                st[32 + c] = filt
                idx += 1; if idx >= sizeR { idx = 0 }
                st[8 + c] = Double(idx)
                outR += out
            }
            for a in 0..<4 {
                var idx = Int(st[16 + a])
                let base = rl + geo[20 + a]
                var buf = Double(base[idx])
                var out = -outL + buf
                base[idx] = Float(outL + buf * 0.5)
                idx += 1; if idx >= geo[16 + a] { idx = 0 }
                st[16 + a] = Double(idx)
                outL = out

                idx = Int(st[20 + a])
                let baseR = rr + geo[20 + a]
                buf = Double(baseR[idx])
                out = -outR + buf
                baseR[idx] = Float(outR + buf * 0.5)
                idx += 1; if idx >= geo[16 + a] + Self.reverbSpread { idx = 0 }
                st[20 + a] = Double(idx)
                outR = out
            }
            scratchL[i] = outL * wet1 + outR * wet2 + scratchL[i] * dry
            scratchR[i] = outR * wet1 + outL * wet2 + scratchR[i] * dry
        }
    }

    private func resetMemory() {
        for i in 0..<Int(PB_MAX_BIQUADS) { biquadMemory[i] = BiquadMemory() }
        for i in 0..<Int(PB_MAX_MODULES) { moduleMemory[i] = ModuleMemory() }
        memset(lines, 0, Int(PB_MAX_MODULES) * lineCapacity * MemoryLayout<Float>.size)
        memset(reverbState, 0, Int(PB_MAX_MODULES) * 64 * MemoryLayout<Double>.size)
    }

    @inline(__always)
    private func clear(_ output: UnsafeMutableAudioBufferListPointer) {
        for b in output { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
    }
}
