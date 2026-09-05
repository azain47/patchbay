import Cocoa
import SwiftUI
import CoreAudio
import UniformTypeIdentifiers
import Combine

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
            guard !name.isEmpty, !name.contains("eqMac Export"), !name.hasPrefix("patchbay") else { return nil }
            return Device(id: id, uid: strProp(id, kAudioDevicePropertyDeviceUID), name: name,
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
    private let engine = SystemAudioEngine()
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
            self.engine.start(output: target, settings: self.rack)
        }
        refresh()
        selectedModule = rack.modules.first?.id
        for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var a = CA.addr(sel)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in DispatchQueue.main.async { self?.refresh() } }
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, nil, block)
            listeners.append((sel, block))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in DispatchQueue.main.async { self?.updateHealth() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.rackOn, let target = self.rackTarget else { return }
            self.engine.start(output: target, settings: self.rack)
        }
    }
    @Published var tapMode: SystemAudioEngine.TapMode = SystemAudioEngine.TapMode(rawValue: UserDefaults.standard.string(forKey: "tapMode") ?? "") ?? .mixdown {
        didSet {
            UserDefaults.standard.set(tapMode.rawValue, forKey: "tapMode")
            engine.tapMode = tapMode
            if rackOn, let target = rackTarget { engine.start(output: target, settings: rack) }
        }
    }

    /// Meters only tick while the popover is visible.
    func setVisible(_ visible: Bool) {
        meterTimer?.invalidate(); meterTimer = nil
        guard visible else { return }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let i = self.rackOn ? self.engine.inputPeak : 0, o = self.rackOn ? self.engine.outputPeak : 0
            if abs(i - self.meters.input) > 0.002 { self.meters.input = i }
            if abs(o - self.meters.output) > 0.002 { self.meters.output = o }
        }
    }

    deinit {
        timer?.invalidate(); meterTimer?.invalidate(); engine.stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        for (sel, block) in listeners {
            var a = CA.addr(sel)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, nil, block)
        }
    }

    // MARK: Devices

    func refresh() {
        outputs = CA.devices(input: false)
        inputs = CA.devices(input: true)
        if let input = currentInput { inputVolume = CA.volume(input.id, input: true) ?? 1 }
        if let output = currentOutput { outputVolume = CA.volume(output.id, input: false) }
        outputRates = rackTarget.map { CA.availableRates($0.id) } ?? []
        if let input = currentInput { micMuted = CA.mute(input.id, input: true) ?? (inputVolume == 0 && micVolumeBeforeMute > 0) }
        updateHealth()
        synchronizeRackDevice()
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
        guard let input = currentInput else { return }
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
            var loaded = rackStore.settings(for: target.uid)
            loaded.enabled = rackOn
            rack = loaded
            if selected == nil { selectedModule = rack.modules.first?.id }
        }
        guard rackOn, active != .rack, engine.outputUID != target.uid else { return }
        engine.start(output: target, settings: rack)
    }

    func select(_ device: Device) {
        if device.isInput {
            CA.setDefault(device.id, input: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refresh() }
            return
        }
        if rackOn && device.isEqMac { setRackOn(false) }
        engine.stop()
        CA.setDefault(device.id, input: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.refresh()
            if self.rackOn, let target = self.rackTarget { self.engine.start(output: target, settings: self.rack) }
        }
    }

    func setInputVolume(_ value: Float) {
        inputVolume = value
        if let input = currentInput { CA.setVolume(input.id, input: true, value) }
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
                self.engine.start(output: target, settings: self.rack)
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
        update { $0.modules.append(module) }
        selectedModule = module.id
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
    func addBand(_ id: UUID) {
        updateModule(id) { module in
            guard module.bands.count < 32 else { return }
            module.bands.append(EQBand(type: .peaking, frequency: 1_000, gainDB: 0, q: 1))
        }
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
        var neutral = RackSettings.neutral
        neutral.enabled = rackOn
        rack = neutral
        selectedModule = rack.modules.first?.id
        persistRack()
        engine.publish(rack)
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
        engine.publish(rack)
    }

    private func persistRack() {
        guard let uid = rackDeviceUID else { return }
        rackStore.save(rack, for: uid)
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
        pop.contentViewController = NSHostingController(rootView: Root(audio: audio, theme: Theme.shared))
        appearanceSink = Theme.shared.$appearance.sink { [weak self] a in
            self?.pop.appearance = a == .system ? nil : NSAppearance(named: a == .dark ? .darkAqua : .aqua)
        }
        pop.behavior = .transient
        pop.animates = true
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
}

final class Delegate: NSObject, NSApplicationDelegate {
    var bar: Bar?
    func applicationDidFinishLaunching(_ n: Notification) { bar = Bar() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let del = Delegate()
app.delegate = del
app.run()
