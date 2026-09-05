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

    /// `auto` picks per page: list pages are compact, the rack is spacious, at one width
    /// so switching tabs never jumps horizontally.
    enum Density: String, CaseIterable, Identifiable {
        case auto, compact, comfortable, spacious
        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        func metrics(for tab: Tab) -> Metrics {
            guard self == .auto else { return metrics }
            var m = (tab == .rack ? Density.spacious : .compact).metrics
            m.width = 480
            return m
        }

        var metrics: Metrics {
            switch self {
            case .auto, .compact:
                Metrics(width: 400, maxHeight: 480, gutter: 12, rowV: 3, rowGap: 0, badge: 22, nameSize: 12, monoSize: 10,
                        sectionTop: 8, paramH: 20, gap: 6, bandV: 4, faderH: 84, subtitle: false)
            case .comfortable:
                Metrics(width: 460, maxHeight: 560, gutter: 16, rowV: 6, rowGap: 2, badge: 26, nameSize: 13, monoSize: 10.5,
                        sectionTop: 12, paramH: 24, gap: 10, bandV: 7, faderH: 100, subtitle: true)
            case .spacious:
                Metrics(width: 540, maxHeight: 640, gutter: 20, rowV: 9, rowGap: 4, badge: 30, nameSize: 13.5, monoSize: 11,
                        sectionTop: 16, paramH: 28, gap: 14, bandV: 10, faderH: 120, subtitle: true)
            }
        }
    }
    /// Everything that makes a page dense or airy. Height follows content up to `maxHeight`.
    /// Delivered to views through the environment, so a page keeps its own metrics and
    /// its own view identity no matter which page is in front.
    struct Metrics: Equatable {
        var width: CGFloat
        let maxHeight, gutter, rowV, rowGap, badge, nameSize, monoSize, sectionTop, paramH, gap, bandV, faderH: CGFloat
        let subtitle: Bool

        var name: Font { .system(size: nameSize, weight: .regular) }
        var nameStrong: Font { .system(size: nameSize, weight: .semibold) }
        var mono: Font { .system(size: monoSize, weight: .medium, design: .monospaced) }
        var monoSmall: Font { .system(size: monoSize - 1.5, weight: .medium, design: .monospaced) }
        var section: Font { .system(size: monoSize - 0.5, weight: .bold) }
    }

    @Published var density: Density { didSet { UserDefaults.standard.set(density.rawValue, forKey: "density") } }
    @Published var accent: Accent { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent"); T.accent = accent.color } }
    @Published var appearance: Appearance { didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") } }

    private init() {
        accent = Accent(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "") ?? .amber
        appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        density = Density(rawValue: UserDefaults.standard.string(forKey: "density") ?? "") ?? .auto
        T.accent = accent.color
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

    static let chromePadding: CGFloat = 16

    static let quick = Animation.spring(response: 0.15, dampingFraction: 0.92)
    static let tab = Animation.spring(response: 0.16, dampingFraction: 0.95)
    static let hoverAnim = Animation.easeOut(duration: 0.07)
}

private struct MetricsKey: EnvironmentKey { static let defaultValue = Theme.Density.compact.metrics }
extension EnvironmentValues {
    var metrics: Theme.Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
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
    @Environment(\.metrics) private var m
    let text: String
    var body: some View {
        Text(text.uppercased()).font(m.section).tracking(1.1).foregroundStyle(.tertiary)
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
    case output, input, routes, rack, fix
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .output: "speaker.wave.2"
        case .input: "mic"
        case .routes: "arrow.triangle.branch"
        case .rack: "slider.horizontal.3"
        case .fix: "bandage"
        }
    }
}

struct Root: View {
    @ObservedObject var audio: AudioState
    @ObservedObject var theme: Theme

    var body: some View {
        let tab = audio.tab
        let front = theme.density.metrics(for: tab)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Wordmark()
                Spacer()
                TabBar(tab: $audio.tab)
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Toggle("", isOn: Binding(get: { audio.scopeOn }, set: { audio.setScopeOn($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(T.accent)
                        .disabled(audio.active != nil)
                        .help(audio.headerScope == .system ? "System chain" : "This route")
                }
            }
            .padding(.horizontal, T.chromePadding).padding(.vertical, 12)

            Rectangle().fill(T.hairline).frame(height: 0.5)

            // Every page stays mounted so faders, scroll positions and selections survive
            // a tab switch; pages behind the front one are collapsed to zero height.
            // The swap itself is deliberately unanimated: the new page appears in its
            // final state, nothing grows, fades or settles.
            ZStack(alignment: .top) {
                ForEach(Tab.allCases) { t in
                    let active = t == tab
                    page(t, active: active)
                        .environment(\.metrics, theme.density.metrics(for: t))
                        .frame(height: active ? nil : 0, alignment: .top)
                        .clipped()
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                }
            }
            .animation(nil, value: tab)

            Rectangle().fill(T.hairline).frame(height: 0.5)
            Footer(audio: audio, theme: theme)
        }
        .frame(width: front.width)
        .frame(maxHeight: front.maxHeight)
        .environment(\.metrics, front)
        .overlay(alignment: .bottom) {
            if let notice = audio.notice {
                Text(notice).font(front.mono).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation(T.quick) { audio.notice = nil } } }
            }
        }
        .onChange(of: audio.rackStatus) { _, s in if case .failed(let message) = s { audio.notice = message } }
    }

    @ViewBuilder
    private func page(_ t: Tab, active: Bool) -> some View {
        switch t {
        case .output: OutputTab(audio: audio)
        case .input: InputTab(audio: audio)
        case .routes: RoutesTab(audio: audio)
        case .rack: RackTab(audio: audio, active: active)
        case .fix: FixTab(audio: audio)
        }
    }

    private var statusColor: Color {
        guard audio.scopeOn else { return Color.secondary.opacity(0.35) }
        switch audio.scopeStatus {
        case .running: return audio.rack.bypass ? T.accent : T.ok
        case .proving, .waiting: return T.accent
        case .failed: return T.warn
        case .stopped: return Color.secondary.opacity(0.35)
        }
    }
}

struct TabBar: View {
    @Binding var tab: Tab

    /// Deliberately static. A tab switch changes nothing but which icon is lit;
    /// no sliding pill, no symbol morph. The page swap is instant too.
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    Image(systemName: t.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tab == t ? .primary : .secondary)
                        .frame(width: 30, height: 22)
                        .background(Capsule().fill(tab == t ? T.press : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)  // Press() animates on isPressed, which coincides with the tab change
                .help(t.title)
            }
        }
        .padding(2)
        .background(Capsule().fill(T.card))
        .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
        .animation(nil, value: tab)
    }
}

struct Footer: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    @ObservedObject var theme: Theme
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 10) {
            Text(audio.scopeOn ? audio.scopeStatus.label : (audio.headerScope == .system ? "rack off" : "route off")).font(m.mono).foregroundStyle(.tertiary)
            Spacer()
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 24, height: 22)
            }
            .buttonStyle(Press())
            .popover(isPresented: $showSettings, arrowEdge: .bottom) { SettingsPopout(audio: audio, theme: theme) }
            Button("Quit") { NSApp.terminate(nil) }.font(.system(size: 11)).foregroundStyle(.tertiary).buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}

struct SettingsPopout: View {
    @Environment(\.metrics) private var m
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
                if theme.density == .auto {
                    Text("Compact on the device pages, spacious on the rack. The window follows its content.")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
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
                Text("patchbay · GPLv3").font(m.monoSmall).foregroundStyle(.tertiary)
                Spacer()
                Link("GitHub", destination: URL(string: "https://github.com/azain47/patchbay")!).font(.system(size: 11))
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct SettingGroup<Content: View>: View {
    @Environment(\.metrics) private var m
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(m.section).tracking(1).foregroundStyle(.tertiary)
            content
        }
    }
}

// MARK: - Fix tab

struct FixTab: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "Audio recovery").padding(.horizontal, m.gutter).padding(.top, m.sectionTop).padding(.bottom, m.sectionTop / 2)
            VStack(spacing: m.rowGap) {
                FixRow(icon: "wrench.and.screwdriver.fill", title: "Fix audio", detail: "Reselect a real output and relaunch eqMac if it was routing", kind: .fix, audio: audio) { audio.fixAudio() }
                FixRow(icon: "arrow.clockwise", title: "Restart eqMac", detail: "Kill and relaunch eqMac, restoring the hardware output first", kind: .restart, audio: audio) { audio.restartEqMac() }
                FixRow(icon: "bolt.fill", title: "Reset Core Audio", detail: "Restart coreaudiod (asks for your password). Audio drops for ~3 s", kind: .reset, audio: audio) { audio.resetCA() }
            }
            .padding(.horizontal, 10)
            HStack(spacing: 8) {
                Circle().fill(audio.eqMacOn ? T.ok : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                Text(audio.eqMacOn ? "eqMac is running" : "eqMac is not running").font(m.mono).foregroundStyle(.tertiary)
                Spacer()
                if let out = audio.currentOutput {
                    Text("default → \(out.name)").font(m.mono).foregroundStyle(out.isEqMac && !audio.eqMacOn ? T.warn : Color.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, m.gutter).padding(.top, m.sectionTop)
            Color.clear.frame(height: m.sectionTop)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct FixRow: View {
    @Environment(\.metrics) private var m
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
                .frame(width: m.badge, height: m.badge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(m.nameStrong)
                    if m.subtitle { Text(detail).font(.system(size: m.monoSize)).foregroundStyle(.tertiary) }
                }
                Spacer()
                if audio.active == kind {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, m.rowV + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .help(detail)
        .disabled(audio.active != nil)
        .opacity(audio.active != nil && audio.active != kind ? 0.5 : 1)
        .hoverRow()
    }
}

// MARK: - Output / Input tabs

struct OutputTab: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "Output devices").padding(.horizontal, m.gutter).padding(.top, m.sectionTop).padding(.bottom, m.sectionTop / 2)
            VStack(spacing: m.rowGap) {
                ForEach(audio.outputs) { d in DeviceRow(device: d, isRackTarget: audio.rackOn && audio.rackTarget?.id == d.id) { audio.select(d) } }
            }
            .padding(.horizontal, 10)
            if let vol = audio.outputVolume, audio.currentOutput?.isEqMac == false {
                LevelRow(icon: "speaker.wave.2", value: Double(vol), muted: false, toggleMute: nil) { audio.setOutputVolume(Float($0)) }
                    .padding(.top, m.sectionTop - 2)
            }
            Color.clear.frame(height: m.sectionTop)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct InputTab: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "Input devices").padding(.horizontal, m.gutter).padding(.top, m.sectionTop).padding(.bottom, m.sectionTop / 2)
            VStack(spacing: m.rowGap) {
                ForEach(audio.inputs) { d in DeviceRow(device: d, isRackTarget: false) { audio.select(d) } }
            }
            .padding(.horizontal, 10)
            LevelRow(icon: "mic", value: Double(audio.inputVolume), muted: audio.micMuted, toggleMute: { audio.setMicMuted(!audio.micMuted) }) { audio.setInputVolume(Float($0)) }
                .padding(.top, m.sectionTop - 2)
            if m.subtitle {
                Text("Effects on the microphone need a virtual input device, which patchbay does not install. Gain and mute are hardware controls.")
                    .font(.system(size: m.monoSize)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, m.gutter).padding(.top, m.sectionTop)
            }
            Color.clear.frame(height: m.sectionTop)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Routes tab

struct RoutesTab: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState

    private var unrouted: [AudioApp] { audio.audioApps.filter { app in !audio.routes.contains { $0.bundleID == app.bundleID } } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(text: "App routes")
                Menu {
                    if unrouted.isEmpty {
                        Text("No other apps are connected to Core Audio")
                    }
                    ForEach(unrouted) { app in
                        Button {
                            audio.addRoute(app: app, outputUID: audio.rackTarget?.uid ?? audio.outputs.first?.uid ?? "")
                        } label: {
                            Label { Text(app.name) } icon: {
                                if let icon = AudioApp.icon(for: app.bundleID) { Image(nsImage: icon) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 22, height: 20)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
                .help("Route an app to a device")
            }
            .padding(.leading, m.gutter).padding(.trailing, 8).padding(.top, m.sectionTop).padding(.bottom, m.sectionTop / 2)

            if audio.routes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 20)).foregroundStyle(.quaternary)
                    Text("Send one app to a different output.").font(m.mono).foregroundStyle(.tertiary)
                    Text("Everything you do not route keeps using the system chain.").font(m.monoSmall).foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, m.sectionTop * 2)
            } else {
                VStack(spacing: m.rowGap) {
                    ForEach(audio.routes) { route in RouteRow(route: route, audio: audio) }
                }
                .padding(.horizontal, 10)
                .animation(T.quick, value: audio.routes.map(\.id))
            }
            Color.clear.frame(height: m.sectionTop)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { audio.refreshProcesses() }
    }
}

struct RouteRow: View {
    @Environment(\.metrics) private var m
    let route: Route
    @ObservedObject var audio: AudioState
    @State private var hover = false

    private var status: SystemAudioEngine.Status { audio.routeStatus[route.id] ?? .stopped }
    private var device: Device? { audio.outputs.first { $0.uid == route.outputUID } }
    private var editing: Bool { audio.rackScope == .route(route.id) }

    var body: some View {
        HStack(spacing: 10) {
            Button { audio.setRoute(route.id, enabled: !route.enabled) } label: {
                Circle().fill(dot).frame(width: 7, height: 7).frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(route.enabled ? status.label : "off")

            if let icon = AudioApp.icon(for: route.bundleID) {
                Image(nsImage: icon).resizable().frame(width: m.badge - 2, height: m.badge - 2)
            } else {
                Image(systemName: "app").frame(width: m.badge - 2, height: m.badge - 2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name).font(m.nameStrong).lineLimit(1).foregroundStyle(route.enabled ? .primary : .secondary)
                if m.subtitle { Text(route.enabled ? status.label : "off").font(m.monoSmall).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 6)
            Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary)
            Menu {
                ForEach(audio.outputs.filter { !$0.isEqMac }) { d in
                    Button { audio.setRoute(route.id, outputUID: d.uid) } label: {
                        HStack { Text(d.name); if d.uid == route.outputUID { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: device?.icon ?? "questionmark").font(.system(size: 10))
                    Text(device?.name ?? "Not connected").font(m.name).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(device == nil ? T.warn : .primary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(T.card))
                .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            IconButton("slider.horizontal.3", active: editing) {
                audio.setRackScope(.route(route.id))
                audio.tab = .rack
            }
            .help("Edit this route's chain")
            IconButton("xmark") { audio.removeRoute(route.id) }.help("Remove route").opacity(hover ? 1 : 0.3)
        }
        .padding(.horizontal, 10).padding(.vertical, m.rowV + 1)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? T.hover : .clear))
        .onHover { hover = $0 }
        .animation(T.hoverAnim, value: hover)
    }

    private var dot: Color {
        guard route.enabled else { return Color.primary.opacity(0.18) }
        switch status {
        case .running: return T.ok
        case .proving, .waiting: return T.accent
        case .failed: return T.warn
        case .stopped: return Color.primary.opacity(0.18)
        }
    }
}

struct DeviceRow: View {
    @Environment(\.metrics) private var m
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
                .frame(width: m.badge, height: m.badge)
                if m.subtitle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(device.isDefault ? m.nameStrong : m.name).lineLimit(1)
                        Text("\(device.formattedRate)  \(device.transportLabel)").font(m.monoSmall).foregroundStyle(.tertiary)
                    }
                } else {
                    Text(device.name).font(device.isDefault ? m.nameStrong : m.name).lineLimit(1)
                }
                Spacer()
                if !m.subtitle { Text(device.formattedRate).font(m.monoSmall).foregroundStyle(.tertiary) }
                if isRackTarget { Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(T.accent) }
                if device.isDefault { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 10).padding(.vertical, m.rowV)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .hoverRow(m.subtitle ? 8 : 6)
    }
}

struct LevelRow: View {
    @Environment(\.metrics) private var m
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
            Text(muted ? "muted" : "\(Int((value * 100).rounded()))%").font(m.mono).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, m.gutter)
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
    @Environment(\.metrics) private var m
    @ObservedObject var meters: Meters
    var body: some View {
        let w: CGFloat = m.subtitle ? 64 : 44
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                if m.subtitle { Text("in").font(m.monoSmall).foregroundStyle(.secondary).frame(width: 16, alignment: .trailing) }
                Meter(level: meters.input).frame(width: w, height: 3)
            }
            HStack(spacing: 6) {
                if m.subtitle { Text("out").font(m.monoSmall).foregroundStyle(.secondary).frame(width: 20, alignment: .trailing) }
                Meter(level: meters.output).frame(width: w, height: 3)
            }
        }
        .help("Input / output level")
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
    @Environment(\.metrics) private var m
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
                Text(format(value)).font(m.mono).foregroundStyle(.secondary).frame(width: 66, alignment: .trailing)
            }
        }
        .frame(height: m.paramH)
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
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    /// False while another page is in front; the analyser stops and the graph unmounts.
    var active = true
    @AppStorage("showGraph") private var showGraph = false

    var body: some View {
        VStack(spacing: 0) {
            ChainStrip(audio: audio)
            Rectangle().fill(T.hairline).frame(height: 0.5)
            if showGraph && active {
                Graph(audio: audio)
                    .frame(height: m.faderH + 40)
                    .padding(.horizontal, m.gutter).padding(.vertical, m.gap)
                    .transition(.opacity)
                Rectangle().fill(T.hairline).frame(height: 0.5)
            }
            ModuleEditor(audio: audio).frame(maxWidth: .infinity)

            Rectangle().fill(T.hairline).frame(height: 0.5)

            HStack(spacing: 12) {
                MeterPair(meters: audio.meters)
                IconButton("waveform.path.ecg", active: showGraph) { withAnimation(T.quick) { showGraph.toggle() } }
                    .help(showGraph ? "Hide graph" : "Show response and spectrum")
                Button { audio.setBypass(!audio.rack.bypass) } label: {
                    Text("Bypass").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(audio.rack.bypass ? Color.black.opacity(0.85) : .secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(audio.rack.bypass ? T.accent : T.card))
                        .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
                        .fixedSize()
                }
                .buttonStyle(Press())
                .animation(T.quick, value: audio.rack.bypass)
                Spacer(minLength: 4)
                if m.subtitle && audio.rackOn {
                    Text(audio.diagnostics.tapBinding).font(m.monoSmall).foregroundStyle(.tertiary).lineLimit(1)
                }
                Menu {
                    ForEach(audio.outputRates, id: \.self) { r in
                        Button { audio.setSampleRate(r) } label: {
                            HStack { Text(rateLabel(r)); if r == audio.rackTarget?.rate { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(rateLabel(audio.rackTarget?.rate ?? 0)).font(m.mono).foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(T.card))
                    .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Device sample rate")
                .disabled(audio.outputRates.count < 2)
                IconButton("arrow.uturn.backward") { audio.resetRack() }.help("Reset rack")
            }
            .padding(.horizontal, m.gutter).padding(.vertical, m.rowV + 3)
        }
    }

    private func rateLabel(_ r: Double) -> String {
        r >= 1000 ? String(format: r.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0f kHz" : "%.1f kHz", r / 1000) : "—"
    }
}

/// The signal chain as chips in processing order, first stage on the left. Drag to reorder.
struct ChainStrip: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState

    private var scopeName: String {
        switch audio.rackScope {
        case .system: "System"
        case .route(let id): audio.routes.first { $0.id == id }?.name ?? "Route"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if !audio.routes.isEmpty {
                Menu {
                    Button { audio.setRackScope(.system) } label: {
                        HStack { Text("System"); if audio.rackScope == .system { Image(systemName: "checkmark") } }
                    }
                    Divider()
                    ForEach(audio.routes) { route in
                        Button { audio.setRackScope(.route(route.id)) } label: {
                            HStack { Text(route.name); if audio.rackScope == .route(route.id) { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: audio.rackScope == .system ? "macwindow.on.rectangle" : "arrow.triangle.branch").font(.system(size: 10))
                        Text(scopeName).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(T.accent)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(T.accent.opacity(0.12)))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Which chain to edit")
                .padding(.leading, m.gutter)
                Rectangle().fill(T.hairline).frame(width: 0.5, height: 18)
            }
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
                .padding(.leading, audio.routes.isEmpty ? m.gutter : 4).padding(.trailing, m.gutter)
                .animation(T.quick, value: audio.rack.modules.map(\.id))
            }
        }
        .padding(.vertical, m.rowV + 4)
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

struct ModuleEditor: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState

    var body: some View {
        if let module = audio.selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: module.kind.symbol).font(.system(size: 12)).foregroundStyle(T.accent)
                    Text(module.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if module.name != nil { Text(module.kind.title).font(m.monoSmall).foregroundStyle(.tertiary) }
                    Spacer()
                    IconButton("chevron.up") { audio.moveModule(module.id, by: -1) }
                    IconButton("chevron.down") { audio.moveModule(module.id, by: 1) }
                    IconButton("arrow.counterclockwise") { audio.resetModule(module.id) }
                    IconButton("trash") { audio.removeModule(module.id) }
                }
                .padding(.horizontal, m.gutter).padding(.top, m.sectionTop).padding(.bottom, m.gap)

                ScrollView {
                    VStack(alignment: .leading, spacing: m.gap) {
                        ForEach(module.kind.specs, id: \.key) { spec in
                            ParamRow(spec: spec, value: module.param(spec.key)) { audio.setParam(module.id, spec.key, $0) }
                        }
                        switch module.kind {
                        case .parametricEQ: ParametricEditor(audio: audio, module: module)
                        case .graphicEQ: GraphicEditor(audio: audio, module: module)
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, m.gutter).padding(.bottom, m.sectionTop)
                }
            }
            .id(module.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 22)).foregroundStyle(.quaternary)
                Text("Select a module").font(m.mono).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity).frame(height: 120)
        }
    }
}

struct IconButton: View {
    let symbol: String
    var active = false
    let action: () -> Void
    @State private var hover = false
    init(_ symbol: String, active: Bool = false, action: @escaping () -> Void) { self.symbol = symbol; self.active = active; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                .foregroundStyle(active ? T.accent : (hover ? .primary : .secondary)).frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? T.press : (hover ? T.hover : .clear)))
        }
        .buttonStyle(Press()).onHover { hover = $0 }.animation(T.hoverAnim, value: hover)
    }
}

/// Response of the chain's linear stages over a live output spectrum.
/// The selected module's own curve is drawn on top when it is an EQ or filter.
struct Graph: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    @ObservedObject private var meters: Meters
    init(audio: AudioState) { self.audio = audio; self.meters = audio.meters }

    private static let fMin = 20.0, fMax = 20_000.0
    private static let points = 160

    var body: some View {
        let chain = (0..<Self.points).map { i -> Double in
            audio.rack.responseDB(at: Self.frequency(at: Double(i) / Double(Self.points - 1)))
        }
        let selected: [Double]? = audio.selected.flatMap { module in
            module.linearCascade == nil || audio.rack.modules.filter({ $0.enabled && $0.linearCascade != nil }).count < 2 ? nil
                : (0..<Self.points).map { i in module.responseDB(at: Self.frequency(at: Double(i) / Double(Self.points - 1))) }
        }
        let range = max(6, (chain + (selected ?? [])).map { abs($0) }.max() ?? 0).rounded(.up)
        let spectrum = meters.spectrum
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func y(_ db: Double) -> CGFloat { h / 2 - CGFloat(db / range) * (h / 2 - 8) }
            func x(_ f: Double) -> CGFloat { CGFloat(log(f / Self.fMin) / log(Self.fMax / Self.fMin)) * w }

            // Spectrum: dBFS -90…0 across the full height.
            if !spectrum.isEmpty {
                var bars = Path()
                let bw = w / CGFloat(spectrum.count)
                for (i, db) in spectrum.enumerated() {
                    let t = CGFloat(max(0, min(1, (Double(db) + 90) / 90)))
                    bars.addRect(CGRect(x: CGFloat(i) * bw + 0.5, y: h - t * h, width: max(1, bw - 1), height: t * h))
                }
                ctx.fill(bars, with: .color(T.accent.opacity(0.16)))
            }

            // Grid.
            var grid = Path()
            for f in [50.0, 100, 200, 500, 1_000, 2_000, 5_000, 10_000] { grid.move(to: CGPoint(x: x(f), y: 0)); grid.addLine(to: CGPoint(x: x(f), y: h)) }
            ctx.stroke(grid, with: .color(Color.primary.opacity(0.05)), lineWidth: 0.5)
            var zero = Path(); zero.move(to: CGPoint(x: 0, y: h / 2)); zero.addLine(to: CGPoint(x: w, y: h / 2))
            ctx.stroke(zero, with: .color(Color.primary.opacity(0.14)), lineWidth: 0.5)
            for f in [100.0, 1_000, 10_000] {
                ctx.draw(Text(f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))").font(m.monoSmall).foregroundStyle(.quaternary),
                         at: CGPoint(x: x(f) + 3, y: h - 7), anchor: .leading)
            }
            ctx.draw(Text(String(format: "±%.0f dB", range)).font(m.monoSmall).foregroundStyle(.quaternary), at: CGPoint(x: w - 3, y: 7), anchor: .trailing)

            func curve(_ values: [Double]) -> Path {
                var p = Path()
                for (i, db) in values.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) / CGFloat(values.count - 1) * w, y: y(db))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                return p
            }
            if let selected { ctx.stroke(curve(selected), with: .color(Color.primary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            var fill = curve(chain)
            fill.addLine(to: CGPoint(x: w, y: h / 2)); fill.addLine(to: CGPoint(x: 0, y: h / 2)); fill.closeSubpath()
            ctx.fill(fill, with: .color(T.accent.opacity(0.12)))
            ctx.stroke(curve(chain), with: .color(T.accent), lineWidth: 1.5)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.hairline, lineWidth: 0.5))
        .onAppear { meters.wantsSpectrum = true }
        .onDisappear { meters.wantsSpectrum = false }
    }

    private static func frequency(at t: Double) -> Double { fMin * pow(fMax / fMin, t) }
}

struct ParametricEditor: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    let module: RackModule
    @State private var query = ""
    @State private var selectedBand: UUID?

    private var bands: [EQBand] { module.bands.sorted { $0.frequency < $1.frequency } }
    private var current: EQBand? { bands.first { $0.id == selectedBand } ?? bands.first }

    var body: some View {
        VStack(alignment: .leading, spacing: m.gap) {
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

            BandColumns(bands: bands, selected: current?.id, height: m.faderH,
                        select: { selectedBand = $0 },
                        setGain: { id, g in audio.setBand(module.id, id) { $0.gainDB = g } })

            if let band = current {
                BandDetail(band: band,
                           setType: { t in audio.setBand(module.id, band.id) { $0.type = t } },
                           setFreq: { f in audio.setBand(module.id, band.id) { $0.frequency = f } },
                           setQ: { q in audio.setBand(module.id, band.id) { $0.q = q } },
                           toggle: { audio.setBand(module.id, band.id) { $0.enabled.toggle() } },
                           remove: { audio.removeBand(module.id, band.id); selectedBand = nil })
            }

            HStack {
                Text("\(module.bands.count) filters").font(m.monoSmall).foregroundStyle(.tertiary)
                Spacer()
                Button { selectedBand = audio.addBand(module.id) } label: { Label("Add filter", systemImage: "plus").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .animation(T.quick, value: module.bands.map(\.id))
        .animation(T.quick, value: selectedBand)
    }
}

/// One vertical gain fader per band, low frequencies on the left. Tap a column to
/// edit its type, frequency and Q below.
struct BandColumns: View {
    @Environment(\.metrics) private var m
    let bands: [EQBand]
    let selected: UUID?
    let height: CGFloat
    let select: (UUID) -> Void
    let setGain: (UUID, Double) -> Void

    var body: some View {
        let dense = bands.count > 14
        let columns = HStack(alignment: .bottom, spacing: dense ? 4 : 6) {
            ForEach(bands) { band in
                BandColumn(band: band, selected: band.id == selected, height: height,
                           select: { select(band.id) }, setGain: { setGain(band.id, $0) })
                    .frame(width: dense ? 30 : nil).frame(maxWidth: dense ? nil : .infinity)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        Group {
            if dense { ScrollView(.horizontal, showsIndicators: false) { columns } } else { columns }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(T.card))
        .overlay {
            if bands.isEmpty { Text("No filters").font(m.mono).foregroundStyle(.tertiary) }
        }
    }
}

struct BandColumn: View {
    @Environment(\.metrics) private var m
    let band: EQBand
    let selected: Bool
    let height: CGFloat
    let select: () -> Void
    let setGain: (Double) -> Void

    var body: some View {
        VStack(spacing: 5) {
            Text(band.type.usesGain ? String(format: "%+.0f", band.gainDB) : "·")
                .font(m.monoSmall).foregroundStyle(selected ? .primary : .tertiary).lineLimit(1)
            VFader(value: band.gainDB, range: -18...18) { setGain(($0 * 2).rounded() / 2) }
                .frame(height: height)
                .opacity(band.type.usesGain ? 1 : 0.3)
                .disabled(!band.type.usesGain)
            Text(band.frequency >= 1000 ? String(format: "%.1fk", band.frequency / 1000) : String(format: "%.0f", band.frequency))
                .font(m.monoSmall).foregroundStyle(selected ? .primary : .tertiary).lineLimit(1).minimumScaleFactor(0.7)
            Circle().fill(band.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 5, height: 5)
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? T.press : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .opacity(band.enabled ? 1 : 0.55)
    }
}

struct BandDetail: View {
    @Environment(\.metrics) private var m
    let band: EQBand
    let setType: (FilterType) -> Void
    let setFreq: (Double) -> Void
    let setQ: (Double) -> Void
    let toggle: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Circle().fill(band.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 7, height: 7).frame(width: 14, height: 14).contentShape(Rectangle())
            }.buttonStyle(.plain).help(band.enabled ? "Disable filter" : "Enable filter")
            Picker("", selection: Binding(get: { band.type }, set: setType)) {
                ForEach(FilterType.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().controlSize(.small).frame(width: 92)
            Fader(value: band.frequency, range: 20...20_000, log: true, set: setFreq)
            Text(band.frequency >= 1000 ? String(format: "%.2fk", band.frequency / 1000) : String(format: "%.0f", band.frequency))
                .font(m.mono).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
            Text("Q").font(m.monoSmall).foregroundStyle(.tertiary)
            Fader(value: band.q, range: 0.1...12, log: true, set: setQ).frame(width: m.subtitle ? 80 : 56)
            Text(String(format: "%.2f", band.q)).font(m.mono).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
            IconButton("xmark") { remove() }.help("Remove filter")
        }
        .padding(.vertical, m.bandV).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(T.card))
    }
}

struct AutoEQResults: View {
    @Environment(\.metrics) private var m
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
            case .loading: Text("Loading catalogue…").font(m.mono).foregroundStyle(.tertiary).padding(10)
            case .failed(let e): Text("Catalogue unavailable: \(e)").font(m.mono).foregroundStyle(T.warn).padding(10)
            case .idle: EmptyView()
            case .ready:
                let results = catalog.search(query)
                if results.isEmpty {
                    Text("No matches").font(m.mono).foregroundStyle(.tertiary).padding(10)
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(results) { e in
                                Button { audio.applyAutoEQ(e); done() } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(e.title).font(.system(size: 12)).lineLimit(1)
                                            Text(e.subtitle).font(m.monoSmall).foregroundStyle(.tertiary)
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

struct GraphicEditor: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    let module: RackModule

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(module.bands) { band in
                    VStack(spacing: 6) {
                        Text(String(format: "%+.0f", band.gainDB)).font(m.monoSmall).foregroundStyle(.tertiary)
                        VFader(value: band.gainDB, range: -12...12) { g in audio.setBand(module.id, band.id) { $0.gainDB = (g * 2).rounded() / 2 } }
                            .frame(height: 160)
                        Text(band.frequency >= 1000 ? String(format: "%.0fk", band.frequency / 1000) : String(format: "%.0f", band.frequency))
                            .font(m.monoSmall).foregroundStyle(.tertiary)
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
