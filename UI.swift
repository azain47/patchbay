import Cocoa
import SwiftUI

// MARK: - Theme

final class Theme: ObservableObject {
    static let shared = Theme()

    enum Accent: String, CaseIterable, Identifiable {
        case amber, blue, sage, rose, violet, mono
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var color: Color {
            switch self {
            case .amber: Color(red: 0.86, green: 0.66, blue: 0.36)
            case .blue: Color(red: 0.36, green: 0.62, blue: 0.92)
            case .sage: Color(red: 0.52, green: 0.72, blue: 0.52)
            case .rose: Color(red: 0.90, green: 0.50, blue: 0.56)
            case .violet: Color(red: 0.66, green: 0.56, blue: 0.92)
            case .mono: Color.primary.opacity(0.85)
            }
        }
    }
    enum Appearance: String, CaseIterable, Identifiable {
        case system, dark, light
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Density: String, CaseIterable, Identifiable {
        case compact, comfortable, spacious
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var metrics: Metrics {
            switch self {
            case .compact: Metrics(width: 420, height: 460, gutter: 14, rowV: 4, badge: 24, chain: 0, name: 12.5)
            case .comfortable: Metrics(width: 480, height: 520, gutter: 16, rowV: 6, badge: 26, chain: 0, name: 13)
            case .spacious: Metrics(width: 560, height: 584, gutter: 18, rowV: 8, badge: 28, chain: 206, name: 13)
            }
        }
    }
    struct Metrics { let width: CGFloat, height: CGFloat, gutter: CGFloat, rowV: CGFloat, badge: CGFloat, chain: CGFloat, name: CGFloat }

    @Published var density: Density { didSet { UserDefaults.standard.set(density.rawValue, forKey: "density"); T.m = density.metrics } }
    @Published var accent: Accent { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent"); T.accent = accent.color } }
    @Published var appearance: Appearance { didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") } }

    private init() {
        accent = Accent(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "") ?? .amber
        appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        density = Density(rawValue: UserDefaults.standard.string(forKey: "density") ?? "") ?? .comfortable
        T.accent = accent.color
        T.m = density.metrics
    }

}

// MARK: - Tokens

enum T {
    static var accent = Color(red: 0.86, green: 0.66, blue: 0.36)
    static let ok = Color(red: 0.48, green: 0.68, blue: 0.48)
    static let warn = Color(red: 0.85, green: 0.42, blue: 0.36)
    static let hover = Color.primary.opacity(0.07)
    static let press = Color.primary.opacity(0.12)
    static let track = Color.primary.opacity(0.13)
    static let card = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.09)

    static var m = Theme.Density.comfortable.metrics
    static var name: Font { .system(size: m.name, weight: .regular) }
    static var nameStrong: Font { .system(size: m.name, weight: .semibold) }
    static let mono = Font.system(size: 10.5, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 9, weight: .medium, design: .monospaced)
    static let section = Font.system(size: 10, weight: .bold)

    static let quick = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let tab = Animation.spring(response: 0.26, dampingFraction: 0.9)
    static let hoverAnim = Animation.easeOut(duration: 0.12)

    static var width: CGFloat { m.width }
    static var height: CGFloat { m.height }
    static var padding: CGFloat { m.gutter }
}

struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(T.quick, value: configuration.isPressed)
    }
}

struct HoverRow: ViewModifier {
    var radius: CGFloat = 8
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(hover ? T.hover : .clear))
            .onHover { hover = $0 }
            .animation(T.hoverAnim, value: hover)
    }
}
extension View { func hoverRow(_ radius: CGFloat = 8) -> some View { modifier(HoverRow(radius: radius)) } }

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(T.section).tracking(1.1).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform").font(.system(size: 12, weight: .bold)).foregroundStyle(T.accent)
            Text("patchbay").font(.system(size: 14, weight: .semibold, design: .rounded)).tracking(-0.2)
        }
    }
}

// MARK: - Root

enum Tab: String, CaseIterable, Identifiable {
    case output, input, rack, fix
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct Root: View {
    @ObservedObject var audio: AudioState
    @ObservedObject var theme: Theme
    @State private var tab: Tab = .output

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Wordmark()
                Spacer()
                TabBar(tab: $tab)
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Toggle("", isOn: Binding(get: { audio.rackOn }, set: { audio.setRackOn($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(T.accent)
                        .disabled(audio.active != nil)
                }
            }
            .padding(.horizontal, T.padding).padding(.top, 14).padding(.bottom, 12)

            Rectangle().fill(T.hairline).frame(height: 0.5)

            ZStack {
                switch tab {
                case .output: OutputTab(audio: audio).transition(.opacity)
                case .input: InputTab(audio: audio).transition(.opacity)
                case .rack: RackTab(audio: audio).transition(.opacity)
                case .fix: FixTab(audio: audio).transition(.opacity)
                }
            }
            .animation(T.tab, value: tab)

            Rectangle().fill(T.hairline).frame(height: 0.5)
            Footer(audio: audio, theme: theme)
        }
        .frame(width: T.width, height: T.height)
        .id(theme.density)
        .overlay(alignment: .bottom) {
            if let notice = audio.notice {
                Text(notice).font(T.mono).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation(T.quick) { audio.notice = nil } } }
            }
        }
        .onChange(of: audio.rackStatus) { _, s in if case .failed(let m) = s { audio.notice = m } }
    }

    private var statusColor: Color {
        guard audio.rackOn else { return Color.secondary.opacity(0.35) }
        switch audio.rackStatus {
        case .running: return audio.rack.bypass ? T.accent : T.ok
        case .proving: return T.accent
        case .failed: return T.warn
        case .stopped: return Color.secondary.opacity(0.35)
        }
    }
}

struct TabBar: View {
    @Binding var tab: Tab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                Button { withAnimation(T.tab) { tab = t } } label: {
                    Text(t.title)
                        .font(.system(size: 12, weight: tab == t ? .semibold : .medium))
                        .foregroundStyle(tab == t ? .primary : .secondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background {
                            if tab == t {
                                Capsule().fill(T.press).matchedGeometryEffect(id: "tab", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(Press())
            }
        }
        .padding(2)
        .background(Capsule().fill(T.card))
        .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
    }
}

struct Footer: View {
    @ObservedObject var audio: AudioState
    @ObservedObject var theme: Theme
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 10) {
            Text(audio.rackOn ? audio.rackStatus.label : "rack off").font(T.mono).foregroundStyle(.tertiary)
            Spacer()
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 24, height: 22)
            }
            .buttonStyle(Press())
            .popover(isPresented: $showSettings, arrowEdge: .bottom) { SettingsPopout(audio: audio, theme: theme) }
            Button("Quit") { NSApp.terminate(nil) }.font(.system(size: 11)).foregroundStyle(.tertiary).buttonStyle(.plain)
        }
        .padding(.horizontal, T.padding).padding(.vertical, 9)
    }
}

struct SettingsPopout: View {
    @ObservedObject var audio: AudioState
    @ObservedObject var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.system(size: 13, weight: .semibold))

            SettingGroup("Appearance") {
                Picker("", selection: $theme.appearance) { ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
            }
            SettingGroup("Layout") {
                Picker("", selection: $theme.density) { ForEach(Theme.Density.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
            }
            SettingGroup("Accent") {
                HStack(spacing: 8) {
                    ForEach(Theme.Accent.allCases) { a in
                        Button { theme.accent = a } label: {
                            ZStack {
                                Circle().fill(a.color).frame(width: 18, height: 18)
                                if theme.accent == a { Circle().strokeBorder(Color.primary.opacity(0.9), lineWidth: 1.5).frame(width: 24, height: 24) }
                            }
                            .frame(width: 24, height: 24)
                        }
                        .buttonStyle(Press()).help(a.title)
                    }
                }
            }
            SettingGroup("Audio capture") {
                Picker("", selection: Binding(get: { audio.tapMode }, set: { audio.tapMode = $0 })) {
                    Text("Stereo mixdown").tag(SystemAudioEngine.TapMode.mixdown)
                    Text("Device stream").tag(SystemAudioEngine.TapMode.deviceStream)
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                Text(audio.tapMode == .mixdown
                     ? "Core Audio mixes every app to stereo, then patchbay resamples to the device rate. Works everywhere."
                     : "Tap bound to the device's own hardware stream: exact format, no resample. Cleaner on paper; some devices go silent.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("patchbay · GPLv3").font(T.monoSmall).foregroundStyle(.tertiary)
                Spacer()
                Link("GitHub", destination: URL(string: "https://github.com/azain47/patchbay")!).font(.system(size: 11))
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct SettingGroup<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(T.section).tracking(1).foregroundStyle(.tertiary)
            content
        }
    }
}

// MARK: - Fix tab

struct FixTab: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "Audio recovery").padding(.horizontal, T.padding).padding(.top, 14).padding(.bottom, 6)
            VStack(spacing: 2) {
                FixRow(icon: "wrench.and.screwdriver.fill", title: "Fix audio", detail: "Reselect a real output and relaunch eqMac if it was routing", kind: .fix, audio: audio) { audio.fixAudio() }
                FixRow(icon: "arrow.clockwise", title: "Restart eqMac", detail: "Kill and relaunch eqMac, restoring the hardware output first", kind: .restart, audio: audio) { audio.restartEqMac() }
                FixRow(icon: "bolt.fill", title: "Reset Core Audio", detail: "Restart coreaudiod (asks for your password). Audio drops for ~3 s", kind: .reset, audio: audio) { audio.resetCA() }
            }
            .padding(.horizontal, 10)
            HStack(spacing: 8) {
                Circle().fill(audio.eqMacOn ? T.ok : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                Text(audio.eqMacOn ? "eqMac is running" : "eqMac is not running").font(T.mono).foregroundStyle(.tertiary)
                Spacer()
                if let out = audio.currentOutput {
                    Text("default → \(out.name)").font(T.mono).foregroundStyle(out.isEqMac && !audio.eqMacOn ? T.warn : Color.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, T.padding).padding(.top, 14)
            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct FixRow: View {
    let icon: String
    let title: String
    let detail: String
    let kind: Action
    @ObservedObject var audio: AudioState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.08))
                    Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(T.accent)
                }
                .frame(width: T.m.badge, height: T.m.badge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(T.nameStrong)
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
                Spacer()
                if audio.active == kind {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, T.m.rowV + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .disabled(audio.active != nil)
        .opacity(audio.active != nil && audio.active != kind ? 0.5 : 1)
        .hoverRow()
    }
}

// MARK: - Output / Input tabs

struct OutputTab: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "Output devices").padding(.horizontal, T.padding).padding(.top, 14).padding(.bottom, 6)
            VStack(spacing: 2) {
                ForEach(audio.outputs) { d in DeviceRow(device: d, isRackTarget: audio.rackOn && audio.rackTarget?.id == d.id) { audio.select(d) } }
            }
            .padding(.horizontal, 10)
            if let vol = audio.outputVolume, audio.currentOutput?.isEqMac == false {
                LevelRow(icon: "speaker.wave.2", value: Double(vol), muted: false, toggleMute: nil) { audio.setOutputVolume(Float($0)) }
                    .padding(.top, 10)
            }
            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct InputTab: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "Input devices").padding(.horizontal, T.padding).padding(.top, 14).padding(.bottom, 6)
            VStack(spacing: 2) {
                ForEach(audio.inputs) { d in DeviceRow(device: d, isRackTarget: false) { audio.select(d) } }
            }
            .padding(.horizontal, 10)
            LevelRow(icon: "mic", value: Double(audio.inputVolume), muted: audio.micMuted, toggleMute: { audio.setMicMuted(!audio.micMuted) }) { audio.setInputVolume(Float($0)) }
                .padding(.top, 10)
            Text("Effects on the microphone need a virtual input device, which patchbay does not install. Gain and mute are hardware controls.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, T.padding).padding(.top, 12)
            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct DeviceRow: View {
    let device: Device
    let isRackTarget: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(device.isDefault ? T.accent.opacity(0.9) : Color.primary.opacity(0.08))
                    Image(systemName: device.icon).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(device.isDefault ? Color.black.opacity(0.8) : Color.primary.opacity(0.7))
                }
                .frame(width: T.m.badge, height: T.m.badge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(device.isDefault ? T.nameStrong : T.name).lineLimit(1)
                    Text("\(device.formattedRate)  \(device.transportLabel)").font(T.monoSmall).foregroundStyle(.tertiary)
                }
                Spacer()
                if isRackTarget { Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(T.accent) }
                if device.isDefault { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 10).padding(.vertical, T.m.rowV)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .hoverRow()
    }
}

struct LevelRow: View {
    let icon: String
    let value: Double
    let muted: Bool
    let toggleMute: (() -> Void)?
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let toggleMute {
                Button(action: toggleMute) {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(muted ? Color.black.opacity(0.85) : Color.primary.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(muted ? T.warn : Color.primary.opacity(0.08)))
                }
                .buttonStyle(Press())
                .help(muted ? "Unmute microphone" : "Mute microphone")
                .animation(T.quick, value: muted)
            } else {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 28)
            }
            Fader(value: value, range: 0...1, set: set).opacity(muted ? 0.4 : 1)
            Text(muted ? "muted" : "\(Int((value * 100).rounded()))%").font(T.mono).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, T.padding)
    }
}

// MARK: - Controls

struct Meter: View {
    let level: Float
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(T.track)
                Capsule().fill(level > 0.98 ? T.warn : T.accent).frame(width: g.size.width * CGFloat(min(1, max(0, level))))
                    .animation(.linear(duration: 0.04), value: level)
            }
        }
    }
}

struct MeterPair: View {
    @ObservedObject var meters: Meters
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Text("in").font(T.monoSmall).foregroundStyle(.secondary).frame(width: 16, alignment: .trailing)
                Meter(level: meters.input).frame(width: 64, height: 3)
            }
            HStack(spacing: 6) {
                Text("out").font(T.monoSmall).foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
                Meter(level: meters.output).frame(width: 64, height: 3)
            }
        }
    }
}

struct Fader: View {
    let value: Double
    let range: ClosedRange<Double>
    var log = false
    var center: Double? = nil
    let set: (Double) -> Void
    @State private var dragging = false

    private func norm(_ v: Double) -> Double {
        if log { return (Foundation.log(max(v, range.lowerBound)) - Foundation.log(range.lowerBound)) / (Foundation.log(range.upperBound) - Foundation.log(range.lowerBound)) }
        return (v - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    private func denorm(_ n: Double) -> Double {
        let t = min(1, max(0, n))
        if log { return exp(Foundation.log(range.lowerBound) + t * (Foundation.log(range.upperBound) - Foundation.log(range.lowerBound))) }
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = w * norm(value)
            let cx = center.map { w * norm($0) }
            ZStack(alignment: .leading) {
                Capsule().fill(T.track).frame(height: 3)
                if let cx {
                    Rectangle().fill(T.accent.opacity(0.8)).frame(width: max(1, abs(x - cx)), height: 3).offset(x: min(x, cx))
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1, height: 7).offset(x: cx - 0.5)
                } else {
                    Capsule().fill(T.accent.opacity(0.8)).frame(width: max(0, x), height: 3)
                }
                Circle().fill(Color.white).frame(width: dragging ? 13 : 11, height: dragging ? 13 : 11)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .offset(x: max(0, min(w - 11, x - 5.5)))
                    .animation(T.quick, value: dragging)
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in dragging = true; set(denorm(v.location.x / w)) }.onEnded { _ in dragging = false })
        }
        .frame(height: 18)
    }
}

struct VFader: View {
    let value: Double
    let range: ClosedRange<Double>
    let set: (Double) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let n = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let y = h * (1 - n)
            let cy = h * 0.5
            ZStack(alignment: .top) {
                Capsule().fill(T.track).frame(width: 3)
                Rectangle().fill(T.accent.opacity(0.85)).frame(width: 3, height: max(1, abs(y - cy))).offset(y: min(y, cy))
                Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 9, height: 1).offset(y: cy)
                Circle().fill(Color.white).frame(width: dragging ? 13 : 11, height: dragging ? 13 : 11)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .offset(y: max(0, min(h - 11, y - 5.5)))
                    .animation(T.quick, value: dragging)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                dragging = true
                let t = min(1, max(0, 1 - v.location.y / h))
                set(range.lowerBound + t * (range.upperBound - range.lowerBound))
            }.onEnded { _ in dragging = false })
        }
    }
}

struct ParamRow: View {
    let spec: ParamSpec
    let value: Double
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(spec.label).font(.system(size: 11.5)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            if let options = spec.options {
                Picker("", selection: Binding(get: { Int(value.rounded()) }, set: { set(Double($0)) })) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, o in Text(o).tag(i + Int(spec.range.lowerBound)) }
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.small)
            } else {
                Fader(value: value, range: spec.range, log: spec.log, center: spec.range.contains(0) && spec.range.lowerBound < 0 ? 0 : nil) { v in
                    set(spec.step > 0 ? (v / spec.step).rounded() * spec.step : v)
                }
                Text(format(value)).font(T.mono).foregroundStyle(.secondary).frame(width: 66, alignment: .trailing)
            }
        }
        .frame(height: 24)
    }

    private func format(_ v: Double) -> String {
        if spec.unit == "Hz" { return v >= 1000 ? String(format: "%.2f kHz", v / 1000) : String(format: "%.0f Hz", v) }
        if spec.unit == "dB" { return String(format: "%+.1f dB", v) }
        if spec.unit == ":1" { return String(format: "%.1f:1", v) }
        if spec.unit == "ms" { return v < 10 ? String(format: "%.1f ms", v) : String(format: "%.0f ms", v) }
        if spec.unit == "s" { return String(format: "%.1f s", v) }
        if spec.step > 0 { return "\(Int(v)) \(spec.unit)".trimmingCharacters(in: .whitespaces) }
        return String(format: "%.0f%@", v, spec.unit == "%" ? "%" : " " + spec.unit)
    }
}

// MARK: - Rack tab

struct RackTab: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            if T.m.chain > 0 {
                HStack(spacing: 0) {
                    ChainColumn(audio: audio).frame(width: T.m.chain)
                    Rectangle().fill(T.hairline).frame(width: 0.5)
                    ModuleEditor(audio: audio).frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            } else {
                ChainStrip(audio: audio)
                Rectangle().fill(T.hairline).frame(height: 0.5)
                ModuleEditor(audio: audio).frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Rectangle().fill(T.hairline).frame(height: 0.5)

            HStack(spacing: 14) {
                MeterPair(meters: audio.meters)
                Button { audio.setBypass(!audio.rack.bypass) } label: {
                    Text("Bypass").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(audio.rack.bypass ? Color.black.opacity(0.85) : .secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(audio.rack.bypass ? T.accent : T.card))
                        .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
                }
                .buttonStyle(Press())
                .animation(T.quick, value: audio.rack.bypass)
                Spacer()
                Menu {
                    ForEach(audio.outputRates, id: \.self) { r in
                        Button { audio.setSampleRate(r) } label: {
                            HStack { Text(rateLabel(r)); if r == audio.rackTarget?.rate { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(rateLabel(audio.rackTarget?.rate ?? 0)).font(T.mono).foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(T.card))
                    .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Device sample rate")
                .disabled(audio.outputRates.count < 2)
                Text(audio.rackOn ? audio.diagnostics.tapBinding : "").font(T.monoSmall).foregroundStyle(.tertiary)
                Button("Reset rack") { audio.resetRack() }.font(.system(size: 11)).foregroundStyle(.tertiary).buttonStyle(.plain)
            }
            .padding(.horizontal, T.padding).padding(.vertical, 9)
        }
    }

    private func rateLabel(_ r: Double) -> String {
        r >= 1000 ? String(format: r.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0f kHz" : "%.1f kHz", r / 1000) : "—"
    }
}

struct ChainColumn: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(text: "Chain")
                Menu {
                    ForEach(["Tone", "Character", "Dynamics", "Space"], id: \.self) { group in
                        Section(group) {
                            ForEach(ModuleKind.allCases.filter { $0.group == group }) { kind in
                                Button { audio.addModule(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 22, height: 20)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
            }
            .padding(.leading, T.padding).padding(.trailing, 8).padding(.top, 12).padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(audio.rack.modules) { m in
                        ChainRow(module: m, selected: audio.selectedModule == m.id,
                                 select: { audio.selectedModule = m.id },
                                 toggle: { audio.setModuleEnabled(m.id, !m.enabled) })
                            .draggable(m.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let s = items.first, let from = UUID(uuidString: s),
                                      let fi = audio.rack.modules.firstIndex(where: { $0.id == from }),
                                      let ti = audio.rack.modules.firstIndex(where: { $0.id == m.id }), fi != ti else { return false }
                                withAnimation(T.quick) { audio.moveModule(from: IndexSet(integer: fi), to: ti > fi ? ti + 1 : ti) }
                                return true
                            }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
                .animation(T.quick, value: audio.rack.modules.map(\.id))
                if audio.rack.modules.isEmpty {
                    Text("Empty chain. Add a module with +.").font(T.mono).foregroundStyle(.tertiary).padding()
                }
            }
        }
    }
}

/// Horizontal chain for narrow layouts: chips in signal order, drag to reorder.
struct ChainStrip: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(audio.rack.modules) { m in
                    ChainChip(module: m, selected: audio.selectedModule == m.id,
                              select: { audio.selectedModule = m.id },
                              toggle: { audio.setModuleEnabled(m.id, !m.enabled) })
                        .draggable(m.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let s = items.first, let from = UUID(uuidString: s),
                                  let fi = audio.rack.modules.firstIndex(where: { $0.id == from }),
                                  let ti = audio.rack.modules.firstIndex(where: { $0.id == m.id }), fi != ti else { return false }
                            withAnimation(T.quick) { audio.moveModule(from: IndexSet(integer: fi), to: ti > fi ? ti + 1 : ti) }
                            return true
                        }
                }
                Menu {
                    ForEach(["Tone", "Character", "Dynamics", "Space"], id: \.self) { group in
                        Section(group) {
                            ForEach(ModuleKind.allCases.filter { $0.group == group }) { kind in
                                Button { audio.addModule(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(T.card))
                        .overlay(Circle().strokeBorder(T.hairline, lineWidth: 0.5))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30)
            }
            .padding(.horizontal, T.padding).padding(.vertical, 10)
            .animation(T.quick, value: audio.rack.modules.map(\.id))
        }
    }
}

struct ChainChip: View {
    let module: RackModule
    let selected: Bool
    let select: () -> Void
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Circle().fill(module.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 6, height: 6)
                    .frame(width: 12, height: 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Image(systemName: module.kind.symbol).font(.system(size: 10)).foregroundStyle(selected ? .primary : .secondary)
            Text(module.title).font(.system(size: 11.5, weight: selected ? .semibold : .medium)).lineLimit(1)
                .foregroundStyle(module.enabled ? .primary : .secondary)
        }
        .padding(.leading, 8).padding(.trailing, 11).padding(.vertical, 5)
        .background(Capsule().fill(selected ? T.press : (hover ? T.hover : T.card)))
        .overlay(Capsule().strokeBorder(selected ? T.accent.opacity(0.5) : T.hairline, lineWidth: 0.5))
        .contentShape(Capsule())
        .onTapGesture(perform: select)
        .onHover { hover = $0 }
        .animation(T.hoverAnim, value: hover)
        .animation(T.quick, value: selected)
    }
}

struct ChainRow: View {
    let module: RackModule
    let selected: Bool
    let select: () -> Void
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 9) {
            Button(action: toggle) {
                Circle().fill(module.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 7, height: 7)
                    .frame(width: 16, height: 16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Image(systemName: module.kind.symbol).font(.system(size: 11)).foregroundStyle(selected ? .primary : .secondary).frame(width: 16)
            Text(module.title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                .foregroundStyle(module.enabled ? .primary : .secondary)
            Spacer()
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.quaternary).opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? T.press : (hover ? T.hover : .clear)))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hover = $0 }
        .animation(T.hoverAnim, value: hover)
        .animation(T.quick, value: selected)
    }
}

struct ModuleEditor: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        if let m = audio.selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: m.kind.symbol).font(.system(size: 12)).foregroundStyle(T.accent)
                    Text(m.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if m.name != nil { Text(m.kind.title).font(T.monoSmall).foregroundStyle(.tertiary) }
                    Spacer()
                    IconButton("chevron.up") { audio.moveModule(m.id, by: -1) }
                    IconButton("chevron.down") { audio.moveModule(m.id, by: 1) }
                    IconButton("arrow.counterclockwise") { audio.resetModule(m.id) }
                    IconButton("trash") { audio.removeModule(m.id) }
                }
                .padding(.horizontal, T.padding).padding(.top, 14).padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(m.kind.specs, id: \.key) { spec in
                            ParamRow(spec: spec, value: m.param(spec.key)) { audio.setParam(m.id, spec.key, $0) }
                        }
                        switch m.kind {
                        case .parametricEQ: ParametricEditor(audio: audio, module: m)
                        case .graphicEQ: GraphicEditor(audio: audio, module: m)
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, T.padding).padding(.bottom, 14)
                }
            }
            .id(m.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 22)).foregroundStyle(.quaternary)
                Text("Select a module").font(T.mono).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct IconButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hover = false
    init(_ symbol: String, action: @escaping () -> Void) { self.symbol = symbol; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                .foregroundStyle(hover ? .primary : .secondary).frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? T.hover : .clear))
        }
        .buttonStyle(Press()).onHover { hover = $0 }.animation(T.hoverAnim, value: hover)
    }
}

struct ParametricEditor: View {
    @ObservedObject var audio: AudioState
    let module: RackModule
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                    TextField("AutoEq headphone…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                        .onChange(of: query) { _, q in if !q.isEmpty { audio.autoEQ.load() } }
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(T.card))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(T.hairline, lineWidth: 0.5))
                IconButton("square.and.arrow.down") { audio.importParametricFile() }.help("Import ParametricEQ.txt")
                IconButton("square.and.arrow.up") { audio.exportParametricFile(module.id) }.help("Export ParametricEQ.txt")
            }
            if !query.isEmpty {
                AutoEQResults(audio: audio, query: query) { query = "" }
            }

            HStack {
                Text("\(module.bands.count) filters").font(T.monoSmall).foregroundStyle(.tertiary)
                Spacer()
                Button { audio.addBand(module.id) } label: { Label("Add filter", systemImage: "plus").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            ForEach(module.bands) { band in
                BandRow(band: band,
                        setType: { t in audio.setBand(module.id, band.id) { $0.type = t } },
                        setFreq: { f in audio.setBand(module.id, band.id) { $0.frequency = f } },
                        setGain: { g in audio.setBand(module.id, band.id) { $0.gainDB = g } },
                        setQ: { q in audio.setBand(module.id, band.id) { $0.q = q } },
                        toggle: { audio.setBand(module.id, band.id) { $0.enabled.toggle() } },
                        remove: { audio.removeBand(module.id, band.id) })
            }
        }
    }
}

struct AutoEQResults: View {
    @ObservedObject var audio: AudioState
    let query: String
    let done: () -> Void
    @ObservedObject private var catalog: AutoEQCatalog

    init(audio: AudioState, query: String, done: @escaping () -> Void) {
        self.audio = audio; self.query = query; self.done = done; self.catalog = audio.autoEQ
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch catalog.state {
            case .loading: Text("Loading catalogue…").font(T.mono).foregroundStyle(.tertiary).padding(10)
            case .failed(let e): Text("Catalogue unavailable: \(e)").font(T.mono).foregroundStyle(T.warn).padding(10)
            case .idle: EmptyView()
            case .ready:
                let results = catalog.search(query)
                if results.isEmpty {
                    Text("No matches").font(T.mono).foregroundStyle(.tertiary).padding(10)
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(results) { e in
                                Button { audio.applyAutoEQ(e); done() } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(e.title).font(.system(size: 12)).lineLimit(1)
                                            Text(e.subtitle).font(T.monoSmall).foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 9).padding(.vertical, 5).contentShape(Rectangle())
                                }
                                .buttonStyle(Press()).hoverRow(6)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.hairline, lineWidth: 0.5))
    }
}

struct BandRow: View {
    let band: EQBand
    let setType: (FilterType) -> Void
    let setFreq: (Double) -> Void
    let setGain: (Double) -> Void
    let setQ: (Double) -> Void
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    Circle().fill(band.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 7, height: 7).frame(width: 14, height: 14).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Picker("", selection: Binding(get: { band.type }, set: setType)) {
                    ForEach(FilterType.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().controlSize(.small).frame(width: 92)
                Fader(value: band.frequency, range: 20...20_000, log: true, set: setFreq)
                Text(band.frequency >= 1000 ? String(format: "%.2fk", band.frequency / 1000) : String(format: "%.0f", band.frequency))
                    .font(T.mono).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
                IconButton("xmark") { remove() }.opacity(hover ? 1 : 0.25)
            }
            HStack(spacing: 10) {
                Color.clear.frame(width: 14)
                Text("Gain").font(T.monoSmall).foregroundStyle(.tertiary).frame(width: 30, alignment: .leading)
                Fader(value: band.gainDB, range: -18...18, center: 0, set: setGain).opacity(band.type.usesGain ? 1 : 0.35).disabled(!band.type.usesGain)
                Text(String(format: "%+.1f", band.gainDB)).font(T.mono).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                Text("Q").font(T.monoSmall).foregroundStyle(.tertiary).frame(width: 12, alignment: .leading)
                Fader(value: band.q, range: 0.1...12, log: true, set: setQ).frame(width: 90)
                Text(String(format: "%.2f", band.q)).font(T.mono).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? T.hover : T.card))
        .opacity(band.enabled ? 1 : 0.5)
        .onHover { hover = $0 }
        .animation(T.hoverAnim, value: hover)
    }
}

struct GraphicEditor: View {
    @ObservedObject var audio: AudioState
    let module: RackModule

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(module.bands) { band in
                    VStack(spacing: 6) {
                        Text(String(format: "%+.0f", band.gainDB)).font(T.monoSmall).foregroundStyle(.tertiary)
                        VFader(value: band.gainDB, range: -12...12) { g in audio.setBand(module.id, band.id) { $0.gainDB = (g * 2).rounded() / 2 } }
                            .frame(height: 160)
                        Text(band.frequency >= 1000 ? String(format: "%.0fk", band.frequency / 1000) : String(format: "%.0f", band.frequency))
                            .font(T.monoSmall).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(T.card))
            HStack {
                Spacer()
                Button("Flatten") { for b in module.bands { audio.setBand(module.id, b.id) { $0.gainDB = 0 } } }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
}
