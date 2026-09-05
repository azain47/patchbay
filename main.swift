import Cocoa
import SwiftUI
import CoreAudio
import UniformTypeIdentifiers
import Combine
import Accelerate

// MARK: - Device model

struct Device: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32
    let rate: Double
    let isInput: Bool
    var isDefault: Bool

    var isEqMac: Bool { name.contains("eqMac") }

    var icon: String {
        if isInput { return transport == kAudioDeviceTransportTypeBuiltIn ? "mic" : "mic.badge.plus" }
        if isEqMac { return "waveform.path.ecg" }
        let lower = name.lowercased()
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("headphone") || lower.contains("buds") || lower.contains("ear") { return "headphones" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual: return "circle.dotted"
        default: return "speaker.wave.2"
        }
    }

    var transportLabel: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "built-in"
        case kAudioDeviceTransportTypeBluetooth: "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: "bluetooth le"
        case kAudioDeviceTransportTypeUSB: "usb"
        case kAudioDeviceTransportTypeHDMI: "hdmi"
        case kAudioDeviceTransportTypeDisplayPort: "displayport"
        case kAudioDeviceTransportTypeVirtual: "virtual"
        case kAudioDeviceTransportTypeAirPlay: "airplay"
        case kAudioDeviceTransportTypeThunderbolt: "thunderbolt"
        default: "other"
        }
    }

    var formattedRate: String { rate >= 1000 ? String(format: "%.1f kHz", rate / 1000) : "\(Int(rate)) Hz" }
}

// MARK: - Core Audio

enum CA {
    static func devices(input: Bool) -> [Device] {
        var size: UInt32 = 0
        var addr = addr(kAudioHardwarePropertyDevices)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        let defID = defaultID(input: input)
        return ids.compactMap { id in
            var ss: UInt32 = 0
            var sa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &ss)
            guard ss > 0 else { return nil }
            let name = strProp(id, kAudioObjectPropertyName)
            let uid = strProp(id, kAudioDevicePropertyDeviceUID)
            // Our own private aggregates are visible to us alone; nothing else carries this UID prefix.
            guard !name.isEmpty, !name.contains("eqMac Export"), !uid.hasPrefix("com.patchbay.") else { return nil }
            return Device(id: id, uid: uid, name: name,
                          transport: u32Prop(id, kAudioDevicePropertyTransportType),
                          rate: f64Prop(id, kAudioDevicePropertyNominalSampleRate), isInput: input, isDefault: id == defID)
        }
    }

    static func defaultID(input: Bool) -> AudioDeviceID {
        var id: AudioDeviceID = 0
        var s = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = addr(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &s, &id)
        return id
    }

    static func setDefault(_ id: AudioDeviceID, input: Bool) {
        var d = id
        let s = UInt32(MemoryLayout<AudioDeviceID>.size)
        if input {
            var a = addr(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, s, &d)
        } else {
            var a1 = addr(kAudioHardwarePropertyDefaultOutputDevice)
            var a2 = addr(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a1, 0, nil, s, &d)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a2, 0, nil, s, &d)
        }
    }

    static func volume(_ id: AudioDeviceID, input: Bool) -> Float? {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            guard AudioObjectHasProperty(id, &a) else { continue }
            var v: Float32 = 0
            var s = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v) == noErr { return v }
        }
        return nil
    }

    static func setVolume(_ id: AudioDeviceID, input: Bool, _ value: Float) {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        var v = value
        var any = false
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            guard AudioObjectHasProperty(id, &a) else { continue }
            if AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr { any = true }
            if element == kAudioObjectPropertyElementMain, any { break }
        }
    }

    static func availableRates(_ id: AudioDeviceID) -> [Double] {
        var a = addr(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ranges) == noErr else { return [] }
        let common: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
        var out = Set<Double>()
        for r in ranges {
            if r.mMinimum == r.mMaximum { out.insert(r.mMinimum) } else { common.filter { $0 >= r.mMinimum && $0 <= r.mMaximum }.forEach { out.insert($0) } }
        }
        return out.sorted()
    }

    @discardableResult
    static func setRate(_ id: AudioDeviceID, _ rate: Double) -> Bool {
        var a = addr(kAudioDevicePropertyNominalSampleRate)
        var v = Float64(rate)
        return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &v) == noErr
    }

    static func mute(_ id: AudioDeviceID, input: Bool) -> Bool? {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: element)
            guard AudioObjectHasProperty(id, &a) else { continue }
            var v: UInt32 = 0; var s = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v) == noErr { return v != 0 }
        }
        return nil
    }

    static func setMute(_ id: AudioDeviceID, input: Bool, _ muted: Bool) -> Bool {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        var v: UInt32 = muted ? 1 : 0
        var any = false
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: element)
            guard AudioObjectHasProperty(id, &a) else { continue }
            if AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr { any = true }
            if element == kAudioObjectPropertyElementMain, any { break }
        }
        return any
    }

    static func bestReal(from devs: [Device]) -> Device? {
        let real = devs.filter { !$0.isEqMac }
        if let eq = devs.first(where: { $0.isEqMac && $0.isDefault }) {
            let w = eq.name.replacingOccurrences(of: " (eqMac)", with: "")
            if let m = real.first(where: { $0.name == w }) { return m }
        }
        return real.first(where: { $0.name.lowercased().contains("headphone") })
            ?? real.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn })
            ?? real.first
    }

    static func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func strProp(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String {
        var a = addr(sel); var v: CFString = "" as CFString; var s = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v) == noErr else { return "" }
        return v as String
    }
    private static func u32Prop(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var a = addr(sel); var v: UInt32 = 0; var s = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v); return v
    }
    private static func f64Prop(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> Double {
        var a = addr(sel); var v: Float64 = 0; var s = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v); return v
    }
}

// MARK: - App state

enum Action: Equatable { case fix, restart, reset, rack }

/// Meter levels live on their own object so 30 Hz updates only re-render meter views.
final class Meters: ObservableObject {
    @Published var input: Float = 0
    @Published var output: Float = 0
    /// Output spectrum in dBFS per log-spaced bin (20 Hz–20 kHz); empty while the graph is hidden.
    @Published var spectrum: [Float] = []
    /// Set by the graph view; the analyser only runs while something is looking at it.
    var wantsSpectrum = false

    static let bins = 96
    private let n = RealtimeDSP.scopeFrames
    private let samples: UnsafeMutablePointer<Float>
    private let window: [Float]
    private var windowed: [Float], real: [Float], imag: [Float], magnitudes: [Float]
    private let fft: vDSP.FFT<DSPSplitComplex>
    private var smoothed = [Float](repeating: -100, count: Meters.bins)

    init() {
        samples = .allocate(capacity: n)
        samples.initialize(repeating: 0, count: n)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: n)
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        magnitudes = [Float](repeating: 0, count: n / 2)
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Float(n))), radix: .radix2, ofType: DSPSplitComplex.self)!
    }

    deinit { samples.deallocate() }

    /// Reads the engine's scope ring, windows, FFTs, and folds the linear bins into
    /// log-spaced bars with a fast-attack, slow-release smoother.
    func analyse(sampleRate: Double, read: (UnsafeMutablePointer<Float>) -> Bool) {
        guard wantsSpectrum, read(samples) else {
            if !spectrum.isEmpty { spectrum = []; smoothed = [Float](repeating: -100, count: Meters.bins) }
            return
        }
        vDSP.multiply(UnsafeBufferPointer(start: samples, count: n), window, result: &windowed)
        // Pack the real windowed signal into split-complex form for the real FFT.
        windowed.withUnsafeBufferPointer { src in
            src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complex in
                real.withUnsafeMutableBufferPointer { r in imag.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
                    fft.forward(input: split, output: &split)
                    vDSP.squareMagnitudes(split, result: &magnitudes)
                } }
            }
        }
        let binHz = sampleRate / Double(n)
        let scale = 1 / Float(n) * 2   // Hann coherent gain and one-sided spectrum
        var bars = [Float](repeating: -100, count: Meters.bins)
        for b in 0..<Meters.bins {
            let f0 = 20 * pow(1000, Double(b) / Double(Meters.bins)), f1 = 20 * pow(1000, Double(b + 1) / Double(Meters.bins))
            let i0 = max(1, Int(f0 / binHz)), i1 = max(i0 + 1, Int(f1 / binHz))
            var peak: Float = 0
            for i in i0..<min(i1, n / 2) { peak = max(peak, magnitudes[i]) }
            bars[b] = 10 * log10(max(1e-10, peak * scale * scale))
        }
        for b in 0..<Meters.bins {
            smoothed[b] = bars[b] > smoothed[b] ? bars[b] : smoothed[b] - 2.5
        }
        spectrum = smoothed
    }
}

final class AudioState: ObservableObject {
    let meters = Meters()
    @Published var micMuted = false
    private var micVolumeBeforeMute: Float = 1
    @Published var outputs: [Device] = []
    @Published var inputs: [Device] = []
    @Published var eqMacOn = false
    @Published var active: Action? = nil
    @Published var healthy = true
    @Published var rack = RackSettings.neutral
    @Published var rackOn = false
    @Published var rackStatus: SystemAudioEngine.Status = .stopped
    @Published var selectedModule: UUID?

    // Routing: which app goes where. `rack` always holds the chain being edited; `rackScope`
    // says whether that is the system chain, one route's chain, or the microphone chain.
    enum RackScope: Equatable { case system, route(UUID), input }
    @Published var rackScope: RackScope = .system

    // Microphone: real mic → chain → "patchbay Mic" virtual device, opt-in driver install.
    @Published var virtualMicInstalled = VirtualMic.installed
    @Published var virtualMicPresent = false
    @Published var micProcessing = UserDefaults.standard.bool(forKey: "micProcessing")
    @Published var micStatus: SystemAudioEngine.Status = .stopped
    @Published var micBusy = false
    private let micEngine = MicEngine()
    /// The real microphone feeding the chain. Remembered separately because the default
    /// input becomes the virtual mic while processing is on.
    private var micSourceUID: String? = UserDefaults.standard.string(forKey: "micSourceUID")
    var micSource: Device? { inputs.first { $0.uid == micSourceUID } ?? inputs.first { $0.isDefault } ?? inputs.first }
    @Published var routes: [Route] = []
    @Published var routeStatus: [UUID: SystemAudioEngine.Status] = [:]
    @Published var audioApps: [AudioApp] = []
    @Published var tab: Tab = .output
    @Published var inputVolume: Float = 1
    @Published var outputVolume: Float?
    @Published var outputRates: [Double] = []
    @Published var diagnostics = SystemAudioEngine.Diagnostics()
    @Published var notice: String?

    let autoEQ = AutoEQCatalog()

    var currentOutput: Device? { outputs.first { $0.isDefault } }
    var currentInput: Device? { inputs.first { $0.isDefault } }
    var rackTarget: Device? {
        if let currentOutput, !currentOutput.isEqMac { return currentOutput }
        return CA.bestReal(from: outputs)
    }
    var selected: RackModule? { rack.modules.first { $0.id == selectedModule } }

    private var timer: Timer?
    private var meterTimer: Timer?
    private var listeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    private var wakeObserver: NSObjectProtocol?
    private let rackStore = RackSettingsStore()
    private let routesStore = RoutesStore()
    private let engine = SystemAudioEngine()
    private var routeEngines: [UUID: SystemAudioEngine] = [:]
    private var rackDeviceUID: String?
    var onHealth: ((Bool) -> Void)?

    init() {
        engine.tapMode = tapMode
        engine.onStatus = { [weak self] status in
            self?.rackStatus = status
            self?.diagnostics = self?.engine.diagnostics ?? .init()
        }
        engine.onNeedsRestart = { [weak self] in
            guard let self, self.rackOn, let target = self.rackTarget else { return }
            self.engine.start(output: target, settings: self.systemRack)
        }
        micEngine.onStatus = { [weak self] status in self?.micStatus = status }
        micEngine.onNeedsRestart = { [weak self] in
            guard let self, self.micProcessing, let source = self.micSource else { return }
            self.micEngine.start(source: source, settings: self.micRack)
        }
        routes = routesStore.routes
        refresh()
        // A previous instance that died with processing on left the default input on the
        // virtual mic. This launch either re-attaches (processing persisted on) or hands
        // the default back; either way nobody stays on a silent device.
        if !micProcessing { restoreRealMicDefault() }
        refreshProcesses()
        selectedModule = rack.modules.first?.id
        for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var a = CA.addr(sel)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in DispatchQueue.main.async { self?.refresh() } }
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, nil, block)
            listeners.append((sel, block))
        }
        var processAddress = CA.addr(kAudioHardwarePropertyProcessObjectList)
        let processBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in DispatchQueue.main.async { self?.refreshProcesses() } }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processAddress, nil, processBlock)
        listeners.append((kAudioHardwarePropertyProcessObjectList, processBlock))
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in DispatchQueue.main.async { self?.updateHealth() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.rackOn, let target = self.rackTarget { self.engine.start(output: target, settings: self.systemRack) }
            for engine in self.routeEngines.values { engine.stop() }
            self.refreshProcesses()
        }
    }
    @Published var tapMode: SystemAudioEngine.TapMode = SystemAudioEngine.TapMode(rawValue: UserDefaults.standard.string(forKey: "tapMode") ?? "") ?? .mixdown {
        didSet {
            UserDefaults.standard.set(tapMode.rawValue, forKey: "tapMode")
            engine.tapMode = tapMode
            if rackOn, let target = rackTarget { engine.start(output: target, settings: systemRack) }
        }
    }

    /// The engine whose chain is currently being edited.
    private var scopedEngine: LiveEngine? {
        switch rackScope {
        case .system: engine
        case .route(let id): routeEngines[id]
        case .input: micEngine
        }
    }
    private var scopedOn: Bool {
        switch rackScope {
        case .system: rackOn
        case .route(let id): routes.first { $0.id == id }?.enabled ?? false
        case .input: micProcessing
        }
    }
    /// The system chain regardless of what the rack page is editing. `rack` is only the
    /// system chain while `rackScope == .system`; otherwise read it back from the store.
    private var systemRack: RackSettings {
        if rackScope == .system { return rack }
        var stored = rackDeviceUID.map { rackStore.settings(for: $0) } ?? .neutral
        stored.enabled = rackOn
        return stored
    }
    private var micRackKey: String? { micSource.map { "input:\($0.uid)" } }

    /// Meters only tick while the popover is visible.
    func setVisible(_ visible: Bool) {
        meterTimer?.invalidate(); meterTimer = nil
        guard visible else { return }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let live = self.scopedOn ? self.scopedEngine : nil
            let i = live?.inputPeak ?? 0, o = live?.outputPeak ?? 0
            if abs(i - self.meters.input) > 0.002 { self.meters.input = i }
            if abs(o - self.meters.output) > 0.002 { self.meters.output = o }
            self.meters.analyse(sampleRate: live?.sampleRate ?? 48_000) { live?.scopeSnapshot(into: $0) ?? false }
        }
    }

    deinit {
        timer?.invalidate(); meterTimer?.invalidate(); engine.stop()
        for engine in routeEngines.values { engine.stop() }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        for (sel, block) in listeners {
            var a = CA.addr(sel)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, nil, block)
        }
    }

    // MARK: Devices

    func refresh() {
        // The virtual mic has an output stream too; it is never an output for the user and
        // never a source for the chain, so it is kept out of both lists.
        let all = CA.devices(input: false) + CA.devices(input: true)
        virtualMicPresent = all.contains(where: VirtualMic.isVirtualMic)
        virtualMicInstalled = VirtualMic.installed
        outputs = CA.devices(input: false).filter { !VirtualMic.isVirtualMic($0) }
        inputs = CA.devices(input: true).filter { !VirtualMic.isVirtualMic($0) }
        if let input = micSource { inputVolume = CA.volume(input.id, input: true) ?? 1 }
        if let output = currentOutput { outputVolume = CA.volume(output.id, input: false) }
        outputRates = rackTarget.map { CA.availableRates($0.id) } ?? []
        if let input = micSource { micMuted = CA.mute(input.id, input: true) ?? (inputVolume == 0 && micVolumeBeforeMute > 0) }
        updateHealth()
        synchronizeRackDevice()
        synchronizeRoutes()
        synchronizeMic()
    }

    /// pgrep on a background queue; the main thread never blocks on a process spawn.
    private func updateHealth() {
        let eqMacDefault = currentOutput?.isEqMac == true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let alive = Self.alive("eqMac")
            DispatchQueue.main.async {
                guard let self else { return }
                self.eqMacOn = alive
                let was = self.healthy
                self.healthy = !((!alive) && eqMacDefault)
                if was != self.healthy { self.onHealth?(self.healthy) }
            }
        }
    }

    func setMicMuted(_ muted: Bool) {
        guard let input = micSource else { return }
        micMuted = muted
        if CA.setMute(input.id, input: true, muted) { return }
        // Device has no mute control: emulate with the gain slider.
        if muted { micVolumeBeforeMute = inputVolume; setInputVolume(0) } else { setInputVolume(micVolumeBeforeMute > 0 ? micVolumeBeforeMute : 1) }
    }

    private func synchronizeRackDevice() {
        guard let target = rackTarget else {
            if rackOn { engine.stop(); rackStatus = .failed("No physical output device is available.") }
            return
        }
        if rackDeviceUID != target.uid {
            rackDeviceUID = target.uid
            if rackScope == .system {
                var loaded = rackStore.settings(for: target.uid)
                loaded.enabled = rackOn
                rack = loaded
                if selected == nil { selectedModule = rack.modules.first?.id }
            }
        }
        guard rackOn, active != .rack, engine.outputUID != target.uid else { return }
        engine.start(output: target, settings: systemRack)
    }

    // MARK: Routing

    /// Re-reads Core Audio's process list, regroups it by app, and pushes the new process
    /// sets to every engine. Cheap; runs on each process-list change.
    func refreshProcesses() {
        audioApps = AudioProcesses.apps()
        synchronizeRoutes()
    }

    private func objects(for route: Route) -> [AudioObjectID] {
        audioApps.first { $0.bundleID == route.bundleID }?.objects ?? []
    }

    /// Starts, retargets or stops one engine per enabled route, and keeps the routed
    /// processes out of the system tap.
    private func synchronizeRoutes() {
        var routedObjects: [AudioObjectID] = []
        for route in routes {
            let objects = objects(for: route)
            let device = outputs.first { $0.uid == route.outputUID }
            engineLog.info("route \(route.name, privacy: .public) [\(route.bundleID, privacy: .public)] enabled \(route.enabled) processes \(objects.count) device \(device?.name ?? "missing", privacy: .public)")
            guard route.enabled, let device, !objects.isEmpty else {
                if !route.enabled {
                    routeEngines.removeValue(forKey: route.id)?.stop()
                    routeStatus[route.id] = .stopped
                } else {
                    routeEngines[route.id]?.idle()
                    routeStatus[route.id] = device == nil ? .failed("Output device is not connected.") : .waiting(app: route.name)
                }
                continue
            }
            routedObjects += objects
            let engine = routeEngines[route.id] ?? makeRouteEngine(route.id)
            let scope = SystemAudioEngine.Scope.processes(objects)
            if engine.outputUID != device.uid {
                engine.scope = scope
                engine.start(output: device, settings: route.rack)
            } else {
                engine.setScope(scope)
            }
        }
        for id in routeEngines.keys where !routes.contains(where: { $0.id == id }) {
            routeEngines.removeValue(forKey: id)?.stop()
            routeStatus[id] = nil
        }
        engine.setScope(.system(excluding: routedObjects))
    }

    private func makeRouteEngine(_ id: UUID) -> SystemAudioEngine {
        let engine = SystemAudioEngine()
        engine.onStatus = { [weak self] status in
            guard let self else { return }
            // An idled engine says "stopped"; while the route is enabled that means "waiting for the app".
            if status == .stopped, let route = self.routes.first(where: { $0.id == id }), route.enabled {
                self.routeStatus[id] = .waiting(app: route.name)
            } else {
                self.routeStatus[id] = status
            }
        }
        engine.onNeedsRestart = { [weak self] in
            guard let self, let route = self.routes.first(where: { $0.id == id }), let device = self.outputs.first(where: { $0.uid == route.outputUID }) else { return }
            engine.scope = .processes(self.objects(for: route))
            engine.start(output: device, settings: route.rack)
        }
        routeEngines[id] = engine
        return engine
    }

    func addRoute(app: AudioApp, outputUID: String) {
        guard !routes.contains(where: { $0.bundleID == app.bundleID }) else { return }
        routes.append(Route(bundleID: app.bundleID, name: app.name, outputUID: outputUID))
        saveRoutes()
    }

    func removeRoute(_ id: UUID) {
        if rackScope == .route(id) { setRackScope(.system) }
        routes.removeAll { $0.id == id }
        saveRoutes()
    }

    func setRoute(_ id: UUID, enabled: Bool) {
        guard let i = routes.firstIndex(where: { $0.id == id }) else { return }
        routes[i].enabled = enabled
        if rackScope == .route(id) { rack.enabled = enabled }
        saveRoutes()
    }

    func setRoute(_ id: UUID, outputUID: String) {
        guard let i = routes.firstIndex(where: { $0.id == id }), routes[i].outputUID != outputUID else { return }
        routes[i].outputUID = outputUID
        routeEngines[id]?.stop()   // forces a restart on the new device in synchronizeRoutes
        saveRoutes()
    }

    private func saveRoutes() {
        routesStore.save(routes)
        synchronizeRoutes()
    }

    /// Switches which chain the rack page edits. The edited copy is written back to its
    /// owner first so nothing is lost.
    func setRackScope(_ scope: RackScope) {
        guard scope != rackScope else { return }
        persistRack()
        rackScope = scope
        switch scope {
        case .system:
            var loaded = rackDeviceUID.map { rackStore.settings(for: $0) } ?? .neutral
            loaded.enabled = rackOn
            rack = loaded
        case .route(let id):
            guard let route = routes.first(where: { $0.id == id }) else { rackScope = .system; return }
            var loaded = route.rack
            loaded.enabled = route.enabled
            rack = loaded
        case .input:
            var loaded = micRackKey.map { rackStore.settings(for: $0) } ?? RackSettings(modules: [])
            loaded.enabled = micProcessing
            rack = loaded
        }
        selectedModule = rack.modules.first?.id
    }

    /// What the header switch, status dot and footer refer to: the route being edited
    /// while the rack page is in front, the system chain everywhere else. Flipping the
    /// switch from the device pages must never silently toggle a route.
    var headerScope: RackScope { tab == .rack ? rackScope : .system }
    var scopeOn: Bool {
        switch headerScope {
        case .system: rackOn
        case .route(let id): routes.first { $0.id == id }?.enabled ?? false
        case .input: micProcessing
        }
    }
    var scopeStatus: SystemAudioEngine.Status {
        switch headerScope {
        case .system: rackStatus
        case .route(let id): routeStatus[id] ?? .stopped
        case .input: micStatus
        }
    }
    /// Bypass state of whatever the header refers to.
    var headerBypass: Bool { headerScope == .system ? systemRack.bypass : rack.bypass }
    func setScopeOn(_ on: Bool) {
        switch headerScope {
        case .system: setRackOn(on)
        case .route(let id): setRoute(id, enabled: on)
        case .input: setMicProcessing(on)
        }
    }

    // MARK: Microphone

    /// Keeps the mic engine matched to the chosen source while processing is on. Any
    /// state in which the engine cannot run hands the default input back to the real
    /// microphone, so apps are never left listening to a silent virtual device.
    private func synchronizeMic() {
        guard micProcessing else { micEngine.stop(); return }
        guard virtualMicPresent else {
            micEngine.stop()
            micStatus = .failed(virtualMicInstalled ? "patchbay Mic is not available yet." : "patchbay Mic is not installed.")
            restoreRealMicDefault()
            return
        }
        guard let source = micSource else { micEngine.stop(); micStatus = .failed("No microphone is available."); return }
        guard micEngine.sourceUID != source.uid else { return }
        micEngine.start(source: source, settings: micRack)
        if case .failed = micEngine.status { restoreRealMicDefault() }
    }

    private func restoreRealMicDefault() {
        guard let source = micSource else { return }
        let defaultInput = CA.devices(input: true).first { $0.isDefault }
        if defaultInput.map(VirtualMic.isVirtualMic) == true { CA.setDefault(source.id, input: true) }
    }

    /// Called from the app delegate on quit and on SIGTERM.
    func prepareForQuit() {
        if micProcessing { micEngine.stop(); restoreRealMicDefault() }
    }

    private var micRack: RackSettings {
        if rackScope == .input { return rack }
        var stored = micRackKey.map { rackStore.settings(for: $0) } ?? RackSettings(modules: [])
        stored.enabled = micProcessing
        return stored
    }

    /// Turns the processed microphone on or off. While on, "patchbay Mic" is the default
    /// input so apps pick it up; turning off hands the default back to the real mic.
    func setMicProcessing(_ on: Bool) {
        guard on != micProcessing else { return }
        if on {
            guard virtualMicPresent, let source = micSource else { notice = "Install patchbay Mic first."; return }
            micSourceUID = source.uid
            UserDefaults.standard.set(source.uid, forKey: "micSourceUID")
            micProcessing = true
            UserDefaults.standard.set(true, forKey: "micProcessing")
            if rackScope == .input { rack.enabled = true }
            micEngine.start(source: source, settings: micRack)
            if let virtual = CA.devices(input: true).first(where: { $0.uid == VirtualMic.deviceUID }) { CA.setDefault(virtual.id, input: true) }
        } else {
            micProcessing = false
            UserDefaults.standard.set(false, forKey: "micProcessing")
            if rackScope == .input { rack.enabled = false }
            micEngine.stop()
            micStatus = .stopped
            if let source = micSource { CA.setDefault(source.id, input: true) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
    }

    /// Picks which real microphone feeds the chain (and becomes the default input when
    /// processing is off).
    func setMicSource(_ device: Device) {
        micSourceUID = device.uid
        UserDefaults.standard.set(device.uid, forKey: "micSourceUID")
        if !micProcessing { CA.setDefault(device.id, input: true) }
        if rackScope == .input { setRackScope(.system); setRackScope(.input) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refresh() }
    }

    /// Installing or removing the driver restarts coreaudiod, which invalidates every tap,
    /// aggregate and IO proc. Everything is stopped first and rebuilt once the HAL is back.
    func installVirtualMic() { changeDriver(install: true) }
    func uninstallVirtualMic() { changeDriver(install: false) }

    private func changeDriver(install: Bool) {
        guard !micBusy else { return }
        micBusy = true
        if !install, micProcessing { setMicProcessing(false) }
        quiesceEngines()
        let done: (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result, (error as? VirtualMic.Failure)?.message != "Cancelled." {
                self.notice = error.localizedDescription
            }
            // coreaudiod needs a moment to come back and enumerate the driver.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.micBusy = false
                self.refresh()
                self.refreshProcesses()
                if install, self.virtualMicPresent { self.notice = "patchbay Mic installed." }
            }
        }
        install ? VirtualMic.install(completion: done) : VirtualMic.uninstall(completion: done)
    }

    private func quiesceEngines() {
        engine.stop()
        for route in routeEngines.values { route.stop() }
        micEngine.stop()
    }

    func select(_ device: Device) {
        if device.isInput { setMicSource(device); return }
        if rackOn && device.isEqMac { setRackOn(false) }
        engine.stop()
        CA.setDefault(device.id, input: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.refresh()
            if self.rackOn, let target = self.rackTarget { self.engine.start(output: target, settings: self.systemRack) }
        }
    }

    func setInputVolume(_ value: Float) {
        inputVolume = value
        if let input = micSource { CA.setVolume(input.id, input: true, value) }
    }

    func setOutputVolume(_ value: Float) {
        outputVolume = value
        if let output = currentOutput { CA.setVolume(output.id, input: false, value) }
    }

    // MARK: Rack lifecycle

    func setRackOn(_ enabled: Bool) {
        guard enabled != rackOn else { return }
        if !enabled {
            rackOn = false; rack.enabled = false; persistRack(); engine.stop(); return
        }
        guard let target = rackTarget else { rackStatus = .failed("No physical output device is available."); return }
        rackOn = true; rack.enabled = true; persistRack(); active = .rack
        bg {
            if Self.alive("eqMac") { Self.kill("eqMac"); usleep(500_000) }
            CA.setDefault(target.id, input: false)
            DispatchQueue.main.async {
                self.refresh()
                self.engine.start(output: target, settings: self.systemRack)
                self.active = nil
            }
        }
    }

    func setBypass(_ bypass: Bool) { update { $0.bypass = bypass } }

    /// Sets the hardware device's nominal rate. The engine's rate listener rebuilds the
    /// pipeline (new filter coefficients, line buffers) once Core Audio reports the change.
    func setSampleRate(_ rate: Double) {
        guard let target = rackTarget, target.rate != rate else { return }
        if !CA.setRate(target.id, rate) { notice = "This device refused \(Int(rate)) Hz." }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
    }

    // MARK: Rack editing

    func addModule(_ kind: ModuleKind) {
        guard rack.modules.count < Int(PB_MAX_MODULES) else { notice = "Rack is full (\(PB_MAX_MODULES) modules)."; return }
        let module = RackModule(kind: kind)
        // Keep signal order: after the last module that belongs at or before this stage, else first.
        let at = rack.modules.lastIndex { $0.kind.stage <= kind.stage }.map { $0 + 1 } ?? 0
        update { $0.modules.insert(module, at: at) }
        selectedModule = module.id
        if at > 0 { notice = "\(kind.title) placed after \(rack.modules[at - 1].title)" }
    }

    func removeModule(_ id: UUID) {
        update { $0.modules.removeAll { $0.id == id } }
        if selectedModule == id { selectedModule = rack.modules.first?.id }
    }

    func moveModule(from source: IndexSet, to destination: Int) {
        update { $0.modules.move(fromOffsets: source, toOffset: destination) }
    }

    func moveModule(_ id: UUID, by offset: Int) {
        guard let index = rack.modules.firstIndex(where: { $0.id == id }) else { return }
        let dest = index + offset
        guard rack.modules.indices.contains(dest) else { return }
        update { $0.modules.swapAt(index, dest) }
    }

    func setModuleEnabled(_ id: UUID, _ enabled: Bool) { updateModule(id) { $0.enabled = enabled } }
    func setParam(_ id: UUID, _ key: String, _ value: Double) { updateModule(id) { $0.params[key] = value } }
    func setBand(_ id: UUID, _ bandID: UUID, _ mutate: (inout EQBand) -> Void) {
        updateModule(id) { module in
            guard let i = module.bands.firstIndex(where: { $0.id == bandID }) else { return }
            mutate(&module.bands[i])
        }
    }
    @discardableResult
    func addBand(_ id: UUID) -> UUID? {
        var added: UUID?
        updateModule(id) { module in
            guard module.bands.count < 32 else { return }
            let band = EQBand(type: .peaking, frequency: 1_000, gainDB: 0, q: 1)
            module.bands.insert(band, at: 0)
            added = band.id
        }
        return added
    }
    func removeBand(_ id: UUID, _ bandID: UUID) { updateModule(id) { $0.bands.removeAll { $0.id == bandID } } }
    func resetModule(_ id: UUID) {
        updateModule(id) { module in
            module.params = module.kind.defaults
            module.bands = module.kind.defaultBands
            module.name = nil
        }
    }

    func resetRack() {
        var neutral = rackScope == .system ? RackSettings.neutral : RackSettings(modules: [])
        neutral.enabled = scopedOn
        rack = neutral
        selectedModule = rack.modules.first?.id
        persistRack()
        scopedEngine?.publish(rack)
    }

    // MARK: Presets, import, export

    func applyPreset(_ preset: ParametricPreset, name: String, replacing id: UUID? = nil) {
        var module = RackModule(kind: .parametricEQ, name: name)
        module.params["preamp"] = preset.preampDB
        module.bands = preset.bands
        if let id, let index = rack.modules.firstIndex(where: { $0.id == id }) {
            module.id = id
            update { $0.modules[index] = module }
        } else {
            guard rack.modules.count < Int(PB_MAX_MODULES) else { notice = "Rack is full."; return }
            update { $0.modules.insert(module, at: 0) }
        }
        selectedModule = module.id
    }

    func importParametricFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = "Choose an Equalizer APO / AutoEq ParametricEQ.txt"
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        guard let preset = ParametricPreset.parse(text) else { notice = "No filters found in that file."; return }
        applyPreset(preset, name: url.deletingPathExtension().lastPathComponent, replacing: selected?.kind == .parametricEQ ? selected?.id : nil)
    }

    func exportParametricFile(_ id: UUID) {
        guard let module = rack.modules.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(module.title) ParametricEQ.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let preset = ParametricPreset(preampDB: module.param("preamp"), bands: module.bands)
        try? preset.exportText.write(to: url, atomically: true, encoding: .utf8)
    }

    func applyAutoEQ(_ entry: AutoEQCatalog.Entry) {
        autoEQ.fetchProfile(entry) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let preset):
                let existing = self.rack.modules.first { $0.name?.hasPrefix("AutoEq") == true }
                self.applyPreset(preset, name: "AutoEq · \(entry.name)", replacing: existing?.id)
            case .failure(let error):
                self.notice = "Could not fetch profile: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Internals

    private func updateModule(_ id: UUID, _ mutate: (inout RackModule) -> Void) {
        guard let index = rack.modules.firstIndex(where: { $0.id == id }) else { return }
        update { mutate(&$0.modules[index]) }
    }

    private func update(_ mutate: (inout RackSettings) -> Void) {
        mutate(&rack)
        persistRack()
        scopedEngine?.publish(rack)
    }

    private func persistRack() {
        switch rackScope {
        case .system:
            guard let uid = rackDeviceUID else { return }
            rackStore.save(rack, for: uid)
        case .route(let id):
            guard let i = routes.firstIndex(where: { $0.id == id }) else { return }
            routes[i].rack = rack
            routesStore.save(routes)
        case .input:
            guard let key = micRackKey else { return }
            rackStore.save(rack, for: key)
        }
    }

    // MARK: eqMac recovery

    func fixAudio() {
        guard active == nil else { return }
        active = .fix
        bg {
            let involved = Self.alive("eqMac") || CA.devices(input: false).first(where: { $0.isDefault })?.isEqMac == true
            Self.kill("eqMac"); sleep(2)
            if let best = CA.bestReal(from: CA.devices(input: false)) { CA.setDefault(best.id, input: false) }
            if involved { sleep(1); self.launchEqMac(); sleep(6) } else { usleep(500_000) }
            DispatchQueue.main.async { self.refresh(); self.active = nil }
        }
    }

    func restartEqMac() {
        guard active == nil else { return }
        if rackOn { setRackOn(false) }
        active = .restart
        bg {
            Self.kill("eqMac"); sleep(2)
            if let best = CA.bestReal(from: CA.devices(input: false)) { CA.setDefault(best.id, input: false) }
            sleep(1); self.launchEqMac(); sleep(6)
            DispatchQueue.main.async { self.refresh(); self.active = nil }
        }
    }

    func resetCA() {
        guard active == nil else { return }
        let resume = rackOn
        if rackOn { setRackOn(false) }
        active = .reset
        bg {
            let hadEqMac = Self.alive("eqMac")
            let script = NSAppleScript(source: #"do shell script "killall coreaudiod" with administrator privileges"#)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            if error != nil { DispatchQueue.main.async { self.active = nil }; return }
            sleep(3)
            if hadEqMac {
                Self.kill("eqMac"); sleep(1)
                if let best = CA.bestReal(from: CA.devices(input: false)) { CA.setDefault(best.id, input: false) }
                sleep(1); self.launchEqMac(); sleep(6)
            }
            DispatchQueue.main.async { self.refresh(); self.active = nil; if resume { self.setRackOn(true) } }
        }
    }

    private func launchEqMac() {
        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/eqMac.app"), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }

    private func bg(_ work: @escaping () -> Void) { DispatchQueue.global(qos: .userInitiated).async(execute: work) }

    private static func alive(_ name: String) -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-x", name]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit(); return p.terminationStatus == 0
    }
    private static func kill(_ name: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill"); p.arguments = ["-9", "-x", name]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
}

// MARK: - Status bar

final class Bar: NSObject, NSPopoverDelegate {
    private var item: NSStatusItem!
    private var pop: NSPopover!
    private let audio = AudioState()
    private var monitor: Any?
    private var appearanceSink: AnyCancellable?

    override init() {
        super.init()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        pop = NSPopover()
        let host = NSHostingController(rootView: Root(audio: audio, theme: Theme.shared))
        host.sizingOptions = .preferredContentSize
        pop.contentViewController = host
        appearanceSink = Theme.shared.$appearance.sink { [weak self] a in
            self?.pop.appearance = a == .system ? nil : NSAppearance(named: a == .dark ? .darkAqua : .aqua)
        }
        pop.behavior = .transient
        pop.animates = false
        pop.delegate = self
        if let b = item.button {
            b.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "patchbay")
            b.target = self
            b.action = #selector(tap)
        }
        audio.onHealth = { [weak self] ok in
            self?.item.button?.image = NSImage(systemSymbolName: ok ? "waveform" : "waveform.badge.exclamationmark", accessibilityDescription: "patchbay")
        }
    }

    @objc private func tap() {
        if pop.isShown { hide(); return }
        audio.refresh()
        // With several displays each menu bar has its own button; anchor to the one that was clicked.
        let clicked = NSApp.currentEvent?.window?.contentView
        guard let b = clicked ?? item.button else { return }
        pop.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
        audio.setVisible(true)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hide() }
    }

    private func hide() {
        pop.performClose(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    func popoverDidClose(_ notification: Notification) {
        audio.setVisible(false)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    func prepareForQuit() { audio.prepareForQuit() }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var bar: Bar?
    func applicationDidFinishLaunching(_ n: Notification) { bar = Bar() }
    func applicationWillTerminate(_ n: Notification) { bar?.prepareForQuit() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let del = Delegate()
app.delegate = del
// `kill`, Activity Monitor and logout send SIGTERM; route it through terminate so
// applicationWillTerminate runs and the microphone default is handed back.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { NSApp.terminate(nil) }
termination.resume()
app.run()
