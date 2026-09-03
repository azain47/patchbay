import Cocoa
import SwiftUI
import CoreAudio

// ─── Model ──────────────────────────────────────────────

struct Device: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32
    let rate: Double
    var isDefault: Bool

    var isEqMac: Bool { name.contains("eqMac") }

    var icon: String {
        if isEqMac { return "waveform.path.ecg" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return name.lowercased().contains("headphone") ? "headphones" : "hifispeaker.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "dot.radiowaves.left.and.right"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeUSB:
            return "cable.connector"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        default: return "speaker.fill"
        }
    }

    var transportLabel: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:       "built-in"
        case kAudioDeviceTransportTypeBluetooth:      "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:    "bluetooth le"
        case kAudioDeviceTransportTypeUSB:            "usb"
        case kAudioDeviceTransportTypeHDMI:           "hdmi"
        case kAudioDeviceTransportTypeDisplayPort:    "displayport"
        case kAudioDeviceTransportTypeVirtual:        "virtual"
        case kAudioDeviceTransportTypeAirPlay:        "airplay"
        case kAudioDeviceTransportTypeThunderbolt:    "thunderbolt"
        case kAudioDeviceTransportTypeFireWire:       "firewire"
        default:                                      "other"
        }
    }

    var formattedRate: String {
        rate >= 1000 ? String(format: "%.1f kHz", rate / 1000) : "\(Int(rate)) Hz"
    }
}

// ─── CoreAudio ──────────────────────────────────────────

enum CA {
    static func devices() -> [Device] {
        var size: UInt32 = 0
        var addr = propAddr(kAudioHardwarePropertyDevices)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        let defID = defaultOutputID()
        return ids.compactMap { id -> Device? in
            var ss: UInt32 = 0
            var sa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &ss)
            guard ss > 0 else { return nil }

            let name = strProp(id, kAudioObjectPropertyName)
            guard !name.isEmpty, !name.contains("eqMac Export") else { return nil }

            return Device(
                id: id,
                uid: strProp(id, kAudioDevicePropertyDeviceUID),
                name: name,
                transport: u32Prop(id, kAudioDevicePropertyTransportType),
                rate: f64Prop(id, kAudioDevicePropertyNominalSampleRate),
                isDefault: id == defID
            )
        }
    }

    static func defaultOutputID() -> AudioDeviceID {
        var id: AudioDeviceID = 0
        var s = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = propAddr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &s, &id)
        return id
    }

    @discardableResult
    static func setDefault(_ id: AudioDeviceID) -> (out: OSStatus, sys: OSStatus, verified: Bool) {
        var d = id
        let s = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a1 = propAddr(kAudioHardwarePropertyDefaultOutputDevice)
        var a2 = propAddr(kAudioHardwarePropertyDefaultSystemOutputDevice)
        let r1 = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a1, 0, nil, s, &d)
        let r2 = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a2, 0, nil, s, &d)
        let actual = defaultOutputID()
        return (r1, r2, actual == id)
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

    // helpers
    static func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func propAddr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress { addr(sel) }
    private static func strProp(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String {
        var a = propAddr(sel); var v: CFString = "" as CFString; var s = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v) == noErr else { return "" }
        return v as String
    }
    private static func u32Prop(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var a = propAddr(sel); var v: UInt32 = 0; var s = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v); return v
    }
    private static func f64Prop(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> Double {
        var a = propAddr(sel); var v: Float64 = 0; var s = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v); return v
    }
}

// ─── State ──────────────────────────────────────────────

enum Action: Equatable { case fix, restart, reset }

final class AudioState: ObservableObject {
    @Published var devices: [Device] = []
    @Published var eqMacOn = false
    @Published var active: Action? = nil
    @Published var healthy = true

    var real: [Device] { devices.filter { !$0.isEqMac } }
    var current: Device? { devices.first { $0.isDefault } }

    private var timer: Timer?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    var onHealth: ((Bool) -> Void)?

    init() {
        refresh()
        installListeners()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.updateHealth() }
        }
    }

    // ── CoreAudio listeners (read-only, UI refresh only) ──

    private func installListeners() {
        var outAddr = CA.addr(kAudioHardwarePropertyDefaultOutputDevice)
        let outBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        outputListener = outBlock
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outAddr, nil, outBlock)

        var devAddr = CA.addr(kAudioHardwarePropertyDevices)
        let devBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        devicesListener = devBlock
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devAddr, nil, devBlock)
    }

    // ── State ──

    func refresh() {
        devices = CA.devices()
        eqMacOn = alive("eqMac")
        updateHealth()
    }

    private func updateHealth() {
        eqMacOn = alive("eqMac")
        let was = healthy
        healthy = !((!eqMacOn) && (current?.isEqMac == true))
        if was != healthy { onHealth?(healthy) }
    }

    func switchTo(_ d: Device) {
        CA.setDefault(d.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
    }

    func fixAudio() {
        guard active == nil else { return }
        active = .fix
        bg {
            let eqMacInvolved = Self.alive("eqMac")
                || CA.devices().first(where: { $0.isDefault })?.isEqMac == true
            Self.kill("eqMac"); sleep(2)
            if let b = CA.bestReal(from: CA.devices()) { CA.setDefault(b.id) }
            if eqMacInvolved {
                sleep(1); self.launchEqMac(); sleep(6)
            } else {
                usleep(500_000)
            }
            DispatchQueue.main.async { self.refresh(); self.active = nil }
        }
    }

    func restartEqMac() {
        guard active == nil else { return }
        active = .restart
        bg {
            Self.kill("eqMac"); sleep(2)
            if let b = CA.bestReal(from: CA.devices()) { CA.setDefault(b.id) }
            sleep(1)
            self.launchEqMac(); sleep(6)
            DispatchQueue.main.async { self.refresh(); self.active = nil }
        }
    }

    func resetCA() {
        guard active == nil else { return }
        active = .reset
        bg {
            let was = self.alive("eqMac")
            let sc = NSAppleScript(source: #"do shell script "killall coreaudiod" with administrator privileges"#)
            var e: NSDictionary?
            sc?.executeAndReturnError(&e)
            if e != nil { DispatchQueue.main.async { self.active = nil }; return }
            sleep(3)
            if was {
                Self.kill("eqMac"); sleep(1)
                if let b = CA.bestReal(from: CA.devices()) { CA.setDefault(b.id) }
                sleep(1); self.launchEqMac(); sleep(6)
            }
            DispatchQueue.main.async { self.refresh(); self.active = nil }
        }
    }

    private func launchEqMac() {
        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/eqMac.app"),
                                               configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }

    private func bg(_ work: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func alive(_ name: String) -> Bool { Self.alive(name) }
    private static func alive(_ name: String) -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", name]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit(); return p.terminationStatus == 0
    }
    private static func kill(_ name: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-9", "-x", name]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
}

// ─── Colors ─────────────────────────────────────────────

extension Color {
    static let amber  = Color(red: 0.77, green: 0.60, blue: 0.35)
    static let sage   = Color(red: 0.48, green: 0.58, blue: 0.42)
}

// ─── Styles ─────────────────────────────────────────────

struct Tap: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// ─── Views ──────────────────────────────────────────────

struct PopoverBody: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            VStack(alignment: .leading, spacing: 0) {
                ForEach(audio.devices) { dev in
                    DeviceRow(device: dev) { audio.switchTo(dev) }
                }
            }
            .padding(.top, 8)

            Color.clear.frame(height: 10)

            VStack(spacing: 0) {
                Act("Fix audio",       "wrench.fill",       .fix,     audio) { audio.fixAudio() }
                Act("Restart eqMac",   "arrow.clockwise",   .restart, audio) { audio.restartEqMac() }
                Act("Reset core audio","bolt.fill",          .reset,   audio) { audio.resetCA() }
            }

            Color.clear.frame(height: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(audio.eqMacOn ? Color.sage : Color.secondary.opacity(0.25))
                    .frame(width: 5, height: 5)
                Text("eqMac \(audio.eqMacOn ? "on" : "off")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .frame(width: 260)
    }
}


struct DeviceRow: View {
    let device: Device
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(device.isDefault ? Color.amber : Color.clear)
                    .frame(width: 3, height: device.isDefault ? 32 : 22)
                    .animation(.easeOut(duration: 0.2), value: device.isDefault)

                Image(systemName: device.icon)
                    .font(.system(size: 12, weight: device.isDefault ? .medium : .regular))
                    .foregroundStyle(device.isDefault ? .primary : .tertiary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13, weight: device.isDefault ? .medium : .regular))
                        .foregroundStyle(device.isDefault ? .primary : .secondary)
                    Text("\(device.formattedRate)  \(device.transportLabel)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(device.isDefault ? .secondary : .quaternary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hover ? Color.primary.opacity(0.07) : Color.clear)
                    .animation(.easeOut(duration: 0.15), value: hover)
            )
        }
        .buttonStyle(Tap())
        .onHover { hover = $0 }
        .padding(.horizontal, 2)
    }
}

struct Act: View {
    let label: String
    let icon: String
    let kind: Action
    @ObservedObject var audio: AudioState
    let action: () -> Void
    @State private var hover = false

    init(_ label: String, _ icon: String, _ kind: Action, _ audio: AudioState, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.kind = kind; self.audio = audio; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(hover ? .primary : .secondary)
                    .frame(width: 16)
                    .animation(.easeOut(duration: 0.15), value: hover)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(audio.active != nil && audio.active != kind ? .tertiary : .primary)
                Spacer()
                if audio.active == kind {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hover ? Color.primary.opacity(0.07) : Color.clear)
                    .animation(.easeOut(duration: 0.15), value: hover)
            )
        }
        .buttonStyle(Tap())
        .disabled(audio.active != nil)
        .onHover { hover = $0 }
        .padding(.horizontal, 2)
    }
}

// ─── Status Bar ─────────────────────────────────────────

final class Bar: NSObject {
    private var item: NSStatusItem!
    private var pop: NSPopover!
    private let audio = AudioState()
    private var monitor: Any?

    override init() {
        super.init()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        pop = NSPopover()
        pop.contentViewController = NSHostingController(rootView: PopoverBody(audio: audio))
        pop.behavior = .transient

        if let b = item.button {
            b.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AudioFix")
            b.target = self
            b.action = #selector(tap)
        }

        audio.onHealth = { [weak self] ok in
            self?.item.button?.image = NSImage(
                systemSymbolName: ok ? "waveform" : "waveform.badge.exclamationmark",
                accessibilityDescription: "AudioFix"
            )
        }
    }

    @objc private func tap() {
        if pop.isShown { hide(); return }
        audio.refresh()
        guard let b = item.button else { return }
        pop.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func hide() {
        pop.performClose(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// ─── Entry ──────────────────────────────────────────────

final class Delegate: NSObject, NSApplicationDelegate {
    var bar: Bar?
    func applicationDidFinishLaunching(_ n: Notification) { bar = Bar() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let del = Delegate()
app.delegate = del
app.run()
