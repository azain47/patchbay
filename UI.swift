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

    /// `auto` picks per page: list pages are compact, the rack is spacious, at one width
    /// so switching tabs never jumps horizontally.
    enum Density: String, CaseIterable, Identifiable {
        case auto, compact, comfortable, spacious
        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        func metrics(for tab: Tab) -> Metrics {
            guard self == .auto else { return metrics }
            var m = (tab == .rack ? Density.spacious : .compact).metrics
            m.width = 540
            return m
        }

        var metrics: Metrics {
            switch self {
            case .auto, .compact:
                Metrics(width: 420, maxHeight: 520, gutter: 12, rowV: 3, rowGap: 0, badge: 22, nameSize: 12, monoSize: 10,
                        sectionTop: 8, paramH: 20, gap: 6, bandV: 4, faderH: 84, chainW: 150, chainRowH: 30, subtitle: false)
            case .comfortable:
                Metrics(width: 480, maxHeight: 600, gutter: 14, rowV: 6, rowGap: 2, badge: 26, nameSize: 13, monoSize: 10.5,
                        sectionTop: 12, paramH: 24, gap: 10, bandV: 7, faderH: 100, chainW: 170, chainRowH: 34, subtitle: true)
            case .spacious:
                Metrics(width: 560, maxHeight: 680, gutter: 16, rowV: 9, rowGap: 4, badge: 30, nameSize: 13.5, monoSize: 11,
                        sectionTop: 14, paramH: 28, gap: 12, bandV: 10, faderH: 120, chainW: 188, chainRowH: 38, subtitle: true)
            }
        }
    }
    /// Everything that makes a page dense or airy. Height follows content up to `maxHeight`.
    /// Delivered to views through the environment, so a page keeps its own metrics and
    /// its own view identity no matter which page is in front.
    struct Metrics: Equatable {
        var width: CGFloat
        let maxHeight, gutter, rowV, rowGap, badge, nameSize, monoSize, sectionTop, paramH, gap, bandV, faderH, chainW, chainRowH: CGFloat
        let subtitle: Bool

        var name: Font { .system(size: nameSize, weight: .regular) }
        var nameStrong: Font { .system(size: nameSize, weight: .semibold) }
        var mono: Font { .system(size: monoSize, weight: .medium, design: .monospaced) }
        var monoSmall: Font { .system(size: monoSize - 1.5, weight: .medium, design: .monospaced) }
        var section: Font { .system(size: monoSize - 0.5, weight: .bold) }
    }

    @Published var density: Density { didSet { UserDefaults.standard.set(density.rawValue, forKey: "density") } }
    @Published var accent: Accent { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent"); T.apply(accent) } }
    /// Off: the popover closes when you click anywhere else. On: it stays until the menu bar
    /// icon is clicked again, for tweaking while another app has focus.
    @Published var keepOpen: Bool { didSet { UserDefaults.standard.set(keepOpen, forKey: "keepOpen") } }
    /// How much slower a slider moves while shift is held: pointer travel × this.
    @Published var scrubFine: Double { didSet { UserDefaults.standard.set(scrubFine, forKey: "scrubFine") } }
    static let scrubSteps: [(Double, String)] = [(0.5, "½"), (0.25, "¼"), (0.1, "⅒"), (0.05, "1⁄20"), (0.02, "1⁄50")]

    private init() {
        accent = Accent(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "") ?? .amber
        density = Density(rawValue: UserDefaults.standard.string(forKey: "density") ?? "") ?? .auto
        keepOpen = UserDefaults.standard.bool(forKey: "keepOpen")
        let fine = UserDefaults.standard.double(forKey: "scrubFine")
        scrubFine = fine > 0 ? fine : 0.1
        T.apply(accent)
    }

}

// MARK: - Tokens


enum T {
    static var accent = Color(red: 0.86, green: 0.66, blue: 0.36)
    /// Foreground on an accent fill. Mono is the label colour itself, so it takes the
    /// window background; every other accent is light enough for near-black.
    static var onAccent = Color.black.opacity(0.82)
    static let ok = Color(red: 0.48, green: 0.68, blue: 0.48)
    static let warn = Color(red: 0.85, green: 0.42, blue: 0.36)
    static let hover = Color.primary.opacity(0.07)
    static let press = Color.primary.opacity(0.12)
    static let track = Color.primary.opacity(0.13)
    static let card = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.09)

    static let chromePadding: CGFloat = 16
    /// Horizontal inset of list rows; their content starts `rowInset + 10` from the edge,
    /// which is where section labels start too.
    static let rowInset: CGFloat = 8

    static func apply(_ a: Theme.Accent) {
        accent = a.color
        onAccent = a == .mono ? Color(nsColor: .windowBackgroundColor) : Color.black.opacity(0.82)
    }

    // Response is the spring's period: at 0.35–0.45 s a move is visibly travelled (about
    // 12–16 frames to settle) yet lands before the hand leaves the mouse.
    static let quick = Animation.spring(response: 0.32, dampingFraction: 0.84)
    /// Selection and toggles: a hint of overshoot.
    static let snap = Animation.spring(response: 0.38, dampingFraction: 0.74)
    /// Page swap.
    static let page = Animation.spring(response: 0.42, dampingFraction: 0.88)
    /// Things appearing: rise a few points while fading in.
    static let rise = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 6)).combined(with: .scale(scale: 0.98, anchor: .top)),
        removal: .opacity)
    static let hoverAnim = Animation.easeOut(duration: 0.14)
}

private struct MetricsKey: EnvironmentKey { static let defaultValue = Theme.Density.compact.metrics }
extension EnvironmentValues {
    var metrics: Theme.Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}

/// Width the module editor actually has: the page minus the chain column when it is open.
private struct EditorWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 480 }
extension EnvironmentValues {
    var editorWidth: CGFloat {
        get { self[EditorWidthKey.self] }
        set { self[EditorWidthKey.self] = newValue }
    }
}

struct Press: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(configuration.isPressed ? .spring(response: 0.12, dampingFraction: 0.9) : T.snap, value: configuration.isPressed)
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

/// Sizes its one child to its ideal width, capped at what the parent offers. A borderless
/// Menu fills whatever it is proposed and, pinned with fixedSize, pushes the row wider
/// than the window when its label is long; under Hug it hugs the label and truncates.
struct Hug: Layout {
    var maxWidth: CGFloat = .infinity
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(.unspecified)
        return CGSize(width: min(ideal.width, proposal.width ?? ideal.width, maxWidth), height: ideal.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

struct SectionLabel: View {
    @Environment(\.metrics) private var m
    let text: String
    var body: some View {
        Text(text.uppercased()).font(m.section).tracking(1.1).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The mark and name; off the system chain a small badge says which chain the rack page
/// is editing (a route, the microphone) before you get there.
struct Wordmark: View {
    let scope: AudioState.RackScope
    var body: some View {
        HStack(spacing: 7) {
            Logo.Mark().frame(width: 16, height: 16).foregroundStyle(T.accent)
            Text("patchbay").font(.system(size: 14, weight: .semibold, design: .rounded)).tracking(-0.2)
            if scope != .system {
                Image(systemName: scope.symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(T.accent)
                    .frame(width: 18, height: 16)
                    .background(Capsule().fill(T.accent.opacity(0.14)))
                    .transition(.opacity)
            }
        }
        .animation(T.quick, value: scope)
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
                Wordmark(scope: audio.rackScope)
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
            .fixedSize(horizontal: false, vertical: true)
            // T.accent is a static token, not an environment value: rebuilding is what makes
            // a new accent reach views whose inputs did not otherwise change. The footer is
            // left alone so the settings popout picking the accent stays open.
            .id(theme.accent)

            Rectangle().fill(T.hairline).frame(height: 0.5)

            // Preserve page state, but resolve layout immediately. Only the page's
            // opacity animates; child controls must not inherit a tab-switch spring.
            ZStack(alignment: .top) {
                ForEach(Tab.allCases) { t in
                    let active = t == tab
                    let metrics = theme.density.metrics(for: t)
                    page(t, active: active)
                        .environment(\.metrics, metrics)
                        .animation(T.page) { content in
                            content.opacity(active ? 1 : 0)
                        }
                        .frame(height: active ? nil : 0, alignment: .top)
                        .clipped()
                        .allowsHitTesting(active)
                        .accessibilityHidden(!active)
                }
            }
            .id(theme.accent)

            Rectangle().fill(T.hairline).frame(height: 0.5)
            Footer(audio: audio, theme: theme)
        }
        .frame(width: front.width)
        .frame(maxHeight: front.maxHeight, alignment: .top)
        .environment(\.metrics, front)
        .onChange(of: audio.rackStatus) { _, s in if case .failed(let message) = s { audio.notice = message } }
        .background(RackShortcutHost(audio: audio))
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
        case .running: return audio.headerBypass ? T.accent : T.ok
        case .proving, .waiting: return T.accent
        case .failed: return T.warn
        case .stopped: return Color.secondary.opacity(0.35)
        }
    }
}

/// Handles rack undo at the event boundary so a focused AppKit text editor keeps Cmd-Z.
/// View-level SwiftUI keyboard shortcuts are resolved before the native text responder.
private struct RackShortcutHost: NSViewRepresentable {
    let audio: AudioState

    func makeNSView(context: Context) -> RackShortcutView {
        let view = RackShortcutView()
        view.audio = audio
        return view
    }

    func updateNSView(_ nsView: RackShortcutView, context: Context) {
        nsView.audio = audio
    }

    static func dismantleNSView(_ nsView: RackShortcutView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class RackShortcutView: NSView {
    weak var audio: AudioState?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    deinit {
        stopMonitoring()
    }

    fileprivate func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let audio,
              audio.tab == .rack,
              let window,
              event.window === window,
              NSApp.keyWindow === window,
              event.keyCode == 6
        else { return event }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if Self.isTextResponder(window.firstResponder) {
            // This menu-bar app has no Edit menu to dispatch the standard commands.
            // Keep text edits on the field editor's native history, never the rack's.
            guard let manager = window.firstResponder?.undoManager else { return event }
            if modifiers == .command, manager.canUndo {
                manager.undo()
                return nil
            }
            if modifiers == [.command, .shift], manager.canRedo {
                manager.redo()
                return nil
            }
            return event
        }
        switch modifiers {
        case .command:
            guard audio.canUndoRack else { return event }
            audio.undoRack()
            return nil
        case [.command, .shift]:
            guard audio.canRedoRack else { return event }
            audio.redoRack()
            return nil
        default:
            return event
        }
    }

    private static func isTextResponder(_ responder: NSResponder?) -> Bool {
        var current = responder
        while let responder = current {
            if responder is NSTextView || responder is NSTextField || responder is NSSearchField { return true }
            current = responder.nextResponder
        }
        return false
    }
}

struct TabBar: View {
    @Binding var tab: Tab

    /// Only the selection pill moves. Icons and hit targets stay outside its animation.
    var body: some View {
        let index = CGFloat(Tab.allCases.firstIndex(of: tab) ?? 0)
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    Image(systemName: t.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tab == t ? .primary : .secondary)
                        .frame(width: 30, height: 22)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)  // Press() animates on isPressed, which coincides with the tab change
                .help(t.title)
            }
        }
        .background(alignment: .leading) {
            Capsule().fill(T.press).frame(width: 30, height: 22)
                .animation(T.snap) { content in
                    content.offset(x: index * 32)
                }
        }
        .padding(2)
        .background(Capsule().fill(T.card))
        .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
    }
}

struct Footer: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    @ObservedObject var theme: Theme
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 10) {
            // Notices take the status slot for a few seconds instead of floating over the
            // page, where they covered whatever control sat underneath.
            if let notice = audio.notice {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill").font(.system(size: 10)).foregroundStyle(T.accent)
                    Text(notice).font(.system(size: 11)).foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
                }
                .help(notice)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
            } else {
                Text(audio.scopeOn ? audio.scopeStatus.label : (audio.headerScope == .system ? "rack off" : "route off"))
                    .font(m.mono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    .help(audio.rackOn ? audio.diagnostics.tapBinding : "")
                    .transition(.opacity)
            }
            Spacer(minLength: 8)
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 24, height: 22)
            }
            .buttonStyle(Press())
            .help("Settings")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsPopout(audio: audio, theme: theme)
            }
            Button("Quit") { NSApp.terminate(nil) }.font(.system(size: 11)).foregroundStyle(.tertiary).buttonStyle(.plain)
        }
        .frame(height: 22)
        .padding(.horizontal, T.chromePadding).padding(.vertical, 8)
        .animation(T.quick, value: audio.notice)
    }
}

struct SettingsPopout: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    @ObservedObject var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.system(size: 13, weight: .semibold))

            SettingGroup("Layout") {
                Picker("", selection: $theme.density) { ForEach(Theme.Density.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                if theme.density == .auto {
                    Text("Compact on the device pages, spacious on the rack. The window follows its content.")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingGroup("Window") {
                Toggle(isOn: $theme.keepOpen) { Text("Stay open").font(.system(size: 11)) }
                    .toggleStyle(.switch).controlSize(.mini).tint(T.accent)
                    .help("Off: a click anywhere else closes the window. On: it stays until the menu bar icon is clicked again.")
            }
            SettingGroup("Shift step") {
                Picker("", selection: $theme.scrubFine) {
                    ForEach(Theme.scrubSteps, id: \.0) { step in Text(step.1).tag(step.0) }
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                .help("Slider speed while shift is held, as a fraction of pointer travel")
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
            SettingGroup("Virtual microphone") {
                HStack(alignment: .firstTextBaseline) {
                    Text(audio.virtualMicInstalled
                         ? "patchbay Mic is installed in /Library/Audio/Plug-Ins/HAL."
                         : "Mic effects need a loopback driver (BlackHole, 90 KB). Admin password; Core Audio restarts for ~3 s.")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if audio.micBusy {
                        ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                    } else if audio.virtualMicInstalled {
                        Button("Remove") { audio.uninstallVirtualMic() }.font(.system(size: 11)).controlSize(.small)
                    } else {
                        Button("Install") { audio.installVirtualMic() }.font(.system(size: 11)).controlSize(.small)
                    }
                }
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
            SectionLabel(text: "Audio recovery").padding(.horizontal, T.rowInset + 10).padding(.top, m.sectionTop).padding(.bottom, m.sectionTop / 2)
            VStack(spacing: m.rowGap) {
                FixRow(icon: "wrench.and.screwdriver.fill", title: "Fix audio", detail: "Reselect a real output and relaunch eqMac if it was routing", kind: .fix, audio: audio) { audio.fixAudio() }
                FixRow(icon: "arrow.clockwise", title: "Restart eqMac", detail: "Kill and relaunch eqMac, restoring the hardware output first", kind: .restart, audio: audio) { audio.restartEqMac() }
                FixRow(icon: "bolt.fill", title: "Reset Core Audio", detail: "Restart coreaudiod (asks for your password). Audio drops for ~3 s", kind: .reset, audio: audio) { audio.resetCA() }
            }
            .padding(.horizontal, T.rowInset)
            HStack(spacing: 8) {
                Circle().fill(audio.eqMacOn ? T.ok : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                Text(audio.eqMacOn ? "eqMac is running" : "eqMac is not running").font(m.mono).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                Spacer(minLength: 12)
                if let out = audio.currentOutput {
                    Text("default → \(out.name)").font(m.mono).foregroundStyle(out.isEqMac && !audio.eqMacOn ? T.warn : Color.secondary.opacity(0.5))
                        .lineLimit(1).truncationMode(.middle).help(out.name)
                }
            }
            .padding(.horizontal, T.rowInset + 10).padding(.top, m.sectionTop)
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
            SectionLabel(text: "Output devices").padding(.horizontal, T.rowInset + 10).padding(.top, m.sectionTop).padding(.bottom, m.sectionTop / 2)
            VStack(spacing: m.rowGap) {
                ForEach(audio.outputs) { d in
                    DeviceRow(device: d, isRackTarget: audio.rackOn && audio.rackTarget?.id == d.id, action: { audio.select(d) }) {
                        if !d.isEqMac { DevicePresetTag(audio: audio, device: d) }
                    }
                }
            }
            .padding(.horizontal, T.rowInset)
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
            SectionLabel(text: "Input devices").padding(.horizontal, T.rowInset + 10).padding(.top, m.sectionTop).padding(.bottom, m.sectionTop / 2)
            VStack(spacing: m.rowGap) {
                ForEach(audio.inputs) { d in
                    DeviceRow(device: d, isRackTarget: audio.micProcessing && audio.micSource?.id == d.id, isDefault: audio.micSource?.id == d.id) { audio.select(d) }
                }
            }
            .padding(.horizontal, T.rowInset)
            LevelRow(icon: "mic", value: Double(audio.inputVolume), muted: audio.micMuted, toggleMute: { audio.setMicMuted(!audio.micMuted) }) { audio.setInputVolume(Float($0)) }
                .padding(.top, m.sectionTop - 2)

            if audio.virtualMicInstalled {
                SectionLabel(text: "Microphone chain").padding(.horizontal, T.rowInset + 10).padding(.top, m.sectionTop + 4).padding(.bottom, m.sectionTop / 2)
                MicSection(audio: audio).padding(.horizontal, T.rowInset)
            }
            Color.clear.frame(height: m.sectionTop)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// Processed microphone row, shown once the patchbay Mic driver is installed (Settings →
/// Virtual microphone): on/off, live status, and a way into the chain editor.
struct MicSection: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState

    var body: some View {
        Group {
            HStack(spacing: 10) {
                Button { audio.setMicProcessing(!audio.micProcessing) } label: {
                    Circle().fill(dot).frame(width: 7, height: 7).frame(width: 14, height: 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(audio.micBusy)
                ZStack {
                    Circle().fill(audio.micProcessing ? T.accent.opacity(0.9) : Color.primary.opacity(0.08))
                    Image(systemName: "waveform.and.mic").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(audio.micProcessing ? T.onAccent : Color.primary.opacity(0.7))
                }
                .frame(width: m.badge, height: m.badge)
                VStack(alignment: .leading, spacing: 2) {
                    Text("patchbay Mic").font(m.nameStrong)
                    Text(statusText).font(m.monoSmall).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { audio.micProcessing }, set: { audio.setMicProcessing($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(T.accent)
                    .disabled(audio.micBusy || !audio.virtualMicPresent)
                IconButton("slider.horizontal.3", active: audio.rackScope == .input) {
                    audio.setRackScope(.input)
                    audio.tab = .rack
                }
                .help("Edit the microphone chain")
            }
            .padding(.horizontal, 10).padding(.vertical, m.rowV + 1)
            .hoverRow()
            if m.subtitle {
                Text("While on, apps see “patchbay Mic” as the default microphone and receive the processed signal. Turning it off hands the default back to \(audio.micSource?.name ?? "the real microphone").")
                    .font(.system(size: m.monoSize)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, m.gutter - 4).padding(.top, 6)
            }
        }
    }

    private var statusText: String {
        if audio.micBusy { return "restarting Core Audio…" }
        if !audio.virtualMicPresent { return "driver installed, device not up yet" }
        return audio.micProcessing ? audio.micStatus.label : "off"
    }

    private var dot: Color {
        guard audio.micProcessing else { return Color.primary.opacity(0.18) }
        switch audio.micStatus {
        case .running: return T.ok
        case .proving, .waiting: return T.accent
        case .failed: return T.warn
        case .stopped: return Color.primary.opacity(0.18)
        }
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
            .padding(.leading, T.rowInset + 10).padding(.trailing, T.rowInset + 2).padding(.top, m.sectionTop).padding(.bottom, m.sectionTop / 2)

            if audio.routes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 20)).foregroundStyle(.tertiary)
                    Text("Send one app to a different output.").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text("Everything you do not route keeps using the system chain.").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, m.sectionTop * 2)
            } else {
                VStack(spacing: m.rowGap) {
                    ForEach(audio.routes) { route in RouteRow(route: route, audio: audio) }
                }
                .padding(.horizontal, T.rowInset)
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
            // Both texts outrank the spacer, so they split the row between them and
            // truncate only once it is genuinely full.
            .layoutPriority(1)
            Spacer(minLength: 6)
            Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary)
            Hug {
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
                    }
                    .foregroundStyle(device == nil ? T.warn : .primary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.visible)
            }
            .padding(.leading, 8).padding(.trailing, 2).padding(.vertical, 3)
            .background(Capsule().fill(T.card))
            .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
            .layoutPriority(1)

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

struct DeviceRow<Accessory: View>: View {
    @Environment(\.metrics) private var m
    let device: Device
    let isRackTarget: Bool
    /// Which row is checked. Defaults to macOS's default device; the input list passes
    /// the chain's source instead, since the default becomes the virtual mic while on.
    var isDefault: Bool? = nil
    let action: () -> Void
    /// Trailing control with its own clicks (the output list's preset tag).
    @ViewBuilder var accessory: Accessory

    var body: some View {
        let selected = isDefault ?? device.isDefault
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(selected ? T.accent.opacity(0.9) : Color.primary.opacity(0.08))
                Image(systemName: device.icon).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? T.onAccent : Color.primary.opacity(0.7))
            }
            .frame(width: m.badge, height: m.badge)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(selected ? m.nameStrong : m.name).lineLimit(1).truncationMode(.middle)
                if m.subtitle {
                    Text("\(device.formattedRate)  \(device.transportLabel)").font(m.monoSmall).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .help(device.name)
            Spacer(minLength: 8)
            accessory
            if !m.subtitle { Text(device.formattedRate).font(m.monoSmall).foregroundStyle(.tertiary).fixedSize() }
            Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(T.accent)
                .opacity(isRackTarget ? 1 : 0).help("The rack processes this output")
            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .opacity(selected ? 1 : 0)
        }
        .padding(.horizontal, 10).padding(.vertical, m.rowV)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .hoverRow(m.subtitle ? 8 : 6)
        .animation(T.snap, value: selected)
        .animation(T.quick, value: isRackTarget)
    }
}

extension DeviceRow where Accessory == EmptyView {
    init(device: Device, isRackTarget: Bool, isDefault: Bool? = nil, action: @escaping () -> Void) {
        self.init(device: device, isRackTarget: isRackTarget, isDefault: isDefault, action: action) { EmptyView() }
    }
}

/// The preset an output loads when it becomes active. Faint bookmark while unbound, the
/// preset's name once bound; either way a menu to pick one.
struct DevicePresetTag: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    let device: Device
    @State private var hover = false

    var body: some View {
        let bound = audio.boundPreset(for: device.uid)
        Hug(maxWidth: 140) {
        Menu {
            Section("Load on \(device.name)") {
                Button { audio.bindPreset(nil, to: device) } label: {
                    HStack { Text("No preset"); if bound == nil { Image(systemName: "checkmark") } }
                }
                ForEach(audio.presets) { p in
                    Button { audio.bindPreset(p.id, to: device) } label: {
                        HStack { Text(p.name); if bound?.id == p.id { Image(systemName: "checkmark") } }
                    }
                }
            }
            if audio.presets.isEmpty { Text("Save a preset from the rack first") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: bound == nil ? "bookmark" : "bookmark.fill").font(.system(size: 9))
                if let bound { Text(bound.name).font(.system(size: 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle) }
            }
            .foregroundStyle(bound == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(T.accent))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .tint(bound == nil ? Color.secondary : T.accent)
        }
        .padding(.horizontal, bound == nil ? 5 : 8).padding(.vertical, 3)
        .background(Capsule().fill(bound == nil ? (hover ? T.hover : .clear) : T.accent.opacity(0.13)))
        .opacity(bound == nil && !hover ? 0.6 : 1)
        .onHover { hover = $0 }
        .help(bound.map { "Loads “\($0.name)” when \(device.name) becomes the output" } ?? "Pick a preset to load when \(device.name) becomes the output")
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
                        .foregroundStyle(muted ? Color.white : Color.primary.opacity(0.7))
                        .frame(width: m.badge, height: m.badge)
                        .background(Circle().fill(muted ? T.warn : Color.primary.opacity(0.08)))
                }
                .buttonStyle(Press())
                .help(muted ? "Unmute microphone" : "Mute microphone")
                .animation(T.quick, value: muted)
            } else {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: m.badge)
            }
            Fader(value: value, range: 0...1, label: { "\(Int(($0 * 100).rounded()))%" }, set: set).opacity(muted ? 0.4 : 1)
            Text(muted ? "muted" : "\(Int((value * 100).rounded()))%").font(m.mono).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, T.rowInset + 10)
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

/// Shared scrub behaviour for both faders. Plain drag is absolute: the knob goes where the
/// pointer is. With shift held the drag turns relative and ten times finer, accumulating in
/// an unrounded position so parameters with coarse steps still creep one step at a time,
/// and a bubble on the knob shows the value being dialled.
struct Scrub {
    var last: CGFloat?
    var position: Double?
    var shift = false

    /// Returns the new normalised position for a pointer at `p` along an axis of length `length`.
    mutating func step(pointer p: CGFloat, length: CGFloat, current: Double) -> Double {
        shift = NSEvent.modifierFlags.contains(.shift)
        defer { last = p }
        guard shift else { position = nil; return Double(p / length) }
        let base = position ?? current
        let delta = last.map { Double((p - $0) / length) * Theme.shared.scrubFine } ?? 0
        let next = min(1, max(0, base + delta))
        position = next
        return next
    }

    mutating func end() { last = nil; position = nil; shift = false }
}

/// Value bubble shown on a knob while shift-scrubbing.
struct ScrubBubble: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
            .fixedSize()
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

struct Fader: View {
    let value: Double
    let range: ClosedRange<Double>
    var log = false
    var center: Double? = nil
    /// How the bubble prints the value; nil falls back to a plain number.
    var label: ((Double) -> String)? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }
    let set: (Double) -> Void
    @State private var dragging = false
    @State private var hover = false
    @State private var scrub = Scrub()

    private func norm(_ v: Double) -> Double {
        if log { return (Foundation.log(max(v, range.lowerBound)) - Foundation.log(range.lowerBound)) / (Foundation.log(range.upperBound) - Foundation.log(range.lowerBound)) }
        return (v - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    private func denorm(_ n: Double) -> Double {
        let t = min(1, max(0, n))
        if log { return exp(Foundation.log(range.lowerBound) + t * (Foundation.log(range.upperBound) - Foundation.log(range.lowerBound))) }
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }
    private var bubbleText: String { label?(value) ?? String(format: abs(value) < 10 ? "%.2f" : "%.1f", value) }

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
                    .background(Circle().fill(T.accent.opacity(dragging ? 0.28 : (hover ? 0.18 : 0))).frame(width: 22, height: 22))
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .offset(x: max(0, min(w - 11, x - 5.5)))
                    .animation(T.snap, value: dragging)
                    .animation(T.hoverAnim, value: hover)
                    .overlay(alignment: .leading) {
                        // Beside the knob, not above it: rows sit at the top of a clipping scroll view.
                        if dragging && scrub.shift {
                            let knob = max(0, min(w - 11, x - 5.5))
                            let onLeft = knob > w / 2
                            ScrubBubble(text: bubbleText)
                                .offset(x: onLeft ? knob - 6 : knob + 17)
                                .alignmentGuide(.leading) { d in onLeft ? d[.trailing] : d[.leading] }
                        }
                    }
            }
            .frame(height: 18)
            .animation(dragging ? nil : T.snap, value: value)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging {
                        dragging = true
                        onEditingChanged(true)
                    }
                    set(denorm(scrub.step(pointer: v.location.x, length: w, current: norm(value))))
                }
                .onEnded { _ in
                    if dragging { onEditingChanged(false) }
                    dragging = false
                    scrub.end()
                })
            .animation(T.quick, value: scrub.shift)
        }
        .frame(height: 18)
    }
}

struct VFader: View {
    let value: Double
    let range: ClosedRange<Double>
    var label: ((Double) -> String)? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }
    let set: (Double) -> Void
    @State private var dragging = false
    @State private var hover = false
    @State private var scrub = Scrub()

    private var bubbleText: String { label?(value) ?? String(format: "%+.1f", value) }

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
                    .background(Circle().fill(T.accent.opacity(dragging ? 0.28 : (hover ? 0.18 : 0))).frame(width: 22, height: 22))
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .offset(y: max(0, min(h - 11, y - 5.5)))
                    .animation(T.snap, value: dragging)
                    .animation(T.hoverAnim, value: hover)
                    .overlay(alignment: .top) {
                        if dragging && scrub.shift {
                            ScrubBubble(text: bubbleText)
                                .offset(x: 22, y: max(0, min(h - 11, y - 5.5)) - 2)
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .animation(dragging ? nil : T.snap, value: value)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging {
                        dragging = true
                        onEditingChanged(true)
                    }
                    // Screen y grows downward; measure from the bottom so the axis grows with the fader.
                    let t = scrub.step(pointer: h - v.location.y, length: h, current: n)
                    set(range.lowerBound + min(1, max(0, t)) * (range.upperBound - range.lowerBound))
                }
                .onEnded { _ in
                    if dragging { onEditingChanged(false) }
                    dragging = false
                    scrub.end()
                })
            .animation(T.quick, value: scrub.shift)
        }
    }
}

struct ParamRow: View {
    @Environment(\.metrics) private var m
    let spec: ParamSpec
    let value: Double
    var onEditingChanged: (Bool) -> Void = { _ in }
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(spec.label).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).frame(width: 62, alignment: .leading)
            if let options = spec.options {
                Picker("", selection: Binding(get: { Int(value.rounded()) }, set: { set(Double($0)) })) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, o in Text(o).tag(i + Int(spec.range.lowerBound)) }
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.small)
            } else {
                Fader(value: value, range: spec.range, log: spec.log, center: spec.range.contains(0) && spec.range.lowerBound < 0 ? 0 : nil,
                      label: format, onEditingChanged: onEditingChanged) { v in
                    set(spec.step > 0 ? (v / spec.step).rounded() * spec.step : v)
                }
                Text(format(value)).font(m.mono).foregroundStyle(.secondary).lineLimit(1).frame(width: 58, alignment: .trailing)
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
    /// False while another page is in front; the analyser stops.
    var active = true
    // Keep panel state local; persist independently of the visual transition.
    @State private var showGraph = UserDefaults.standard.object(forKey: "showGraph") as? Bool ?? false
    @State private var chainOpen = UserDefaults.standard.object(forKey: "chainOpen") as? Bool ?? true

    var body: some View {
        let editorWidth = chainOpen ? m.width - m.chainW - 0.5 : m.width
        VStack(spacing: 0) {
            if !audio.scopeOn { OffBanner(audio: audio).transition(.move(edge: .top).combined(with: .opacity)) }
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    ChainColumn(audio: audio)
                        .frame(width: m.chainW)
                    Rectangle().fill(T.hairline).frame(width: 0.5)
                }
                .frame(width: chainOpen ? m.chainW + 0.5 : 0, alignment: .leading)
                .clipped()
                .opacity(chainOpen ? 1 : 0)
                .allowsHitTesting(chainOpen)
                .accessibilityHidden(!chainOpen)
                VStack(spacing: 0) {
                    Graph(audio: audio, analyzing: showGraph && active)
                        .frame(height: m.faderH + 40)
                        .padding(.horizontal, m.gutter).padding(.top, m.sectionTop).padding(.bottom, 2)
                        .frame(height: showGraph ? m.faderH + 42 + m.sectionTop : 0, alignment: .top)
                        .clipped()
                        .opacity(showGraph ? 1 : 0)
                        .allowsHitTesting(showGraph)
                        .accessibilityHidden(!showGraph)
                    ModuleEditor(audio: audio, chainOpen: chainOpen)
                        .animation(T.snap, value: audio.selectedModule)
                }
                .frame(width: editorWidth)
                .clipped()
                .environment(\.editorWidth, editorWidth)
            }
            .clipped()
            .animation(T.snap, value: chainOpen)
            .animation(T.snap, value: showGraph)
            .onChange(of: chainOpen) { _, v in UserDefaults.standard.set(v, forKey: "chainOpen") }
            .onChange(of: showGraph) { _, v in UserDefaults.standard.set(v, forKey: "showGraph") }
            Rectangle().fill(T.hairline).frame(height: 0.5)

            HStack(spacing: 6) {
                IconButton("sidebar.left", active: chainOpen) { chainOpen.toggle() }
                    .help(chainOpen ? "Hide chain" : "Show chain")
                IconButton("waveform.path.ecg", active: showGraph) { showGraph.toggle() }
                    .help(showGraph ? "Hide graph" : "Show response and spectrum")
                Button { audio.setBypass(!audio.rack.bypass) } label: {
                    Text("Bypass").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(audio.rack.bypass ? T.onAccent : .secondary)
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(Capsule().fill(audio.rack.bypass ? T.accent : T.card))
                        .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
                        .fixedSize()
                }
                .buttonStyle(Press(scale: 0.92))
                .help("Hear the unprocessed signal (A/B)")
                .animation(T.quick, value: audio.rack.bypass)
                .padding(.leading, 4)
                Spacer(minLength: 8)
                MeterPair(meters: audio.meters)
                Spacer(minLength: 8)
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
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(T.card))
                    .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Device sample rate")
                .disabled(audio.outputRates.count < 2)
                IconButton("arrow.uturn.backward") { audio.undoRack() }
                    .disabled(!active || !audio.canUndoRack)
                    .help("Undo rack edit (⌘Z)")
                IconButton("arrow.uturn.forward") { audio.redoRack() }
                    .disabled(!active || !audio.canRedoRack)
                    .help("Redo rack edit (⇧⌘Z)")
                IconButton("arrow.counterclockwise") { audio.resetRack() }.help("Reset rack")
            }
            .padding(.horizontal, m.gutter - 4).padding(.vertical, 8)
        }
        .animation(T.quick, value: audio.scopeOn)
        .presetPrompt(audio: audio)
    }

    private func rateLabel(_ r: Double) -> String {
        r >= 1000 ? String(format: r.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0f kHz" : "%.1f kHz", r / 1000) : "—"
    }
}

/// Edits on a chain that is off are silent; say so where the editing happens.
struct OffBanner: View {
    @ObservedObject var audio: AudioState
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.slash").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(audio.headerScope == .system ? "Rack is off. Changes are saved but not heard." : "This chain is off. Changes are saved but not heard.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Button("Turn on") { audio.setScopeOn(true) }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.accent)
                .disabled(audio.active != nil)
        }
        .padding(.horizontal, T.chromePadding).frame(height: 30)
        .background(T.accent.opacity(0.08))
        .overlay(alignment: .bottom) { Rectangle().fill(T.hairline).frame(height: 0.5) }
    }
}

// MARK: - Presets

/// Which preset the chain came from (a dot once it has been edited past it) and, on the
/// system chain, whether the current output loads it automatically.
struct PresetBar: View {
    @ObservedObject var audio: AudioState
    @State private var hover = false

    var body: some View {
        let current = audio.currentPreset
        let device = audio.rackScope == .system ? audio.rackTarget : nil
        let bound = device.map { audio.boundPreset(for: $0.uid) } ?? nil
        Menu { PresetMenuItems(audio: audio) } label: {
            HStack(spacing: 7) {
                Image(systemName: current == nil ? "bookmark" : "bookmark.fill").font(.system(size: 10))
                    .foregroundStyle(current == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(T.accent))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(current?.name ?? "No preset").font(.system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(current == nil ? .secondary : .primary)
                        if audio.presetModified {
                            Circle().fill(T.accent).frame(width: 5, height: 5).help("Edited since the preset was applied")
                        }
                    }
                    if let device, let bound {
                        Text(bound.id == current?.id ? "auto-loads on this output" : "this output loads “\(bound.name)”")
                            .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(hover ? T.hover : T.card))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(T.hairline, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        // Button-style menu with a plain button draws the label as laid out; the borderless
        // style would reduce it to its text and icon.
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .onHover { hover = $0 }
        .help(current.map { "Preset “\($0.name)”" } ?? "Presets: named chains you can recall and bind to an output")
    }
}

struct PresetMenuItems: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        let device = audio.rackScope == .system ? audio.rackTarget : nil
        Button { audio.clearPreset() } label: {
            HStack {
                Text("No preset")
                if audio.rack.preset == nil && audio.rack.modules.isEmpty {
                    Image(systemName: "checkmark")
                }
            }
        }
        Divider()
        if audio.presets.isEmpty {
            Text("No presets yet")
        }
        ForEach(audio.presets) { preset in
            Button { audio.applyPreset(preset) } label: {
                HStack {
                    Text(preset.name)
                    if preset.id == audio.rack.preset { Image(systemName: audio.presetModified ? "circle.fill" : "checkmark") }
                }
            }
        }
        Divider()
        Button("Save as preset…") { audio.presetPrompt = .save }
        if let current = audio.currentPreset {
            Button("Update “\(current.name)”") { audio.updatePreset() }.disabled(!audio.presetModified)
            Button("Rename…") { audio.presetPrompt = .rename(current.id) }
            Button("Delete “\(current.name)”", role: .destructive) { audio.deletePreset(current.id) }
        }
        if let device, !audio.presets.isEmpty {
            Divider()
            Menu("Load on \(device.name)") {
                let bound = audio.boundPreset(for: device.uid)
                Button { audio.bindPreset(nil, to: device) } label: {
                    HStack { Text("No preset"); if bound == nil { Image(systemName: "checkmark") } }
                }
                ForEach(audio.presets) { p in
                    Button { audio.bindPreset(p.id, to: device) } label: {
                        HStack { Text(p.name); if bound?.id == p.id { Image(systemName: "checkmark") } }
                    }
                }
            }
        }
    }
}

/// The name sheet for saving or renaming a preset, hung off the rack page.
struct PresetNameSheet: ViewModifier {
    @ObservedObject var audio: AudioState
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { audio.presetPrompt != nil }, set: { if !$0 { audio.presetPrompt = nil } })) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) { audio.presetPrompt = nil }
                Button(isRename ? "Rename" : "Save") {
                    switch audio.presetPrompt {
                    case .save: audio.savePreset(named: name)
                    case .rename(let id): audio.renamePreset(id, to: name)
                    case nil: break
                    }
                    audio.presetPrompt = nil
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                if case .save = audio.presetPrompt, audio.rackScope == .system, let device = audio.rackTarget?.name {
                    Text("Saves the chain as it is now and remembers it for \(device).")
                }
            }
            .onChange(of: audio.presetPrompt) { _, prompt in
                switch prompt {
                case .save: name = audio.rackScope == .system ? (audio.rackTarget?.name ?? "") : ""
                case .rename(let id): name = audio.presets.first { $0.id == id }?.name ?? ""
                case nil: break
                }
            }
    }

    private var isRename: Bool { if case .rename = audio.presetPrompt { true } else { false } }
    private var title: String { isRename ? "Rename preset" : "Save preset" }
}
extension View { func presetPrompt(audio: AudioState) -> some View { modifier(PresetNameSheet(audio: audio)) } }

/// The signal chain as a vertical stack in processing order, first stage on top. Press and
/// drag a row to reorder: it follows the pointer, the others slide out of its way, release
/// commits. The scope chip on top says which chain this is.
struct ChainColumn: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    @State private var dragging: UUID?
    @State private var dragOffset: CGFloat = 0
    @Namespace private var selection

    private var rowPitch: CGFloat { m.chainRowH + 4 }

    private var scopeName: String {
        switch audio.rackScope {
        case .system: "System"
        case .route(let id): audio.routes.first { $0.id == id }?.name ?? "Route"
        case .input: "Microphone"
        }
    }

    /// Where the held row would land if released now.
    private func target(from index: Int) -> Int {
        let shifted = Int((dragOffset / rowPitch).rounded())
        return min(max(index + shifted, 0), audio.rack.modules.count - 1)
    }

    private func displacement(of index: Int) -> CGFloat {
        guard let dragging, let from = audio.rack.modules.firstIndex(where: { $0.id == dragging }) else { return 0 }
        if audio.rack.modules[index].id == dragging { return dragOffset }
        let to = target(from: from)
        if from < index, index <= to { return -rowPitch }
        if to <= index, index < from { return rowPitch }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !audio.routes.isEmpty || audio.virtualMicInstalled {
                Hug {
                    Menu {
                        Button { audio.setRackScope(.system) } label: {
                            HStack { Text("System"); if audio.rackScope == .system { Image(systemName: "checkmark") } }
                        }
                        if audio.virtualMicInstalled {
                            Button { audio.setRackScope(.input) } label: {
                                HStack { Text("Microphone"); if audio.rackScope == .input { Image(systemName: "checkmark") } }
                            }
                        }
                        if !audio.routes.isEmpty { Divider() }
                        ForEach(audio.routes) { route in
                            Button { audio.setRackScope(.route(route.id)) } label: {
                                HStack { Text(route.name); if audio.rackScope == .route(route.id) { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: audio.rackScope.symbol).font(.system(size: 10))
                            Text(scopeName).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(T.accent)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.visible)
                }
                .padding(.leading, 9).padding(.trailing, 3).padding(.vertical, 4)
                .background(Capsule().fill(T.accent.opacity(0.12)))
                .help("Which chain to edit")
                .padding(.horizontal, m.gutter - 4).padding(.top, m.sectionTop).padding(.bottom, m.gap)
            } else {
                SectionLabel(text: "Chain").padding(.horizontal, m.gutter - 4).padding(.top, m.sectionTop).padding(.bottom, m.gap)
            }
            PresetBar(audio: audio).padding(.horizontal, m.gutter - 4).padding(.bottom, m.gap)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(Array(audio.rack.modules.enumerated()), id: \.element.id) { index, module in
                        ChainRow(module: module, selected: audio.selectedModule == module.id, lifted: dragging == module.id, selection: selection,
                                 select: { withAnimation(T.snap) { audio.selectedModule = module.id } },
                                 toggle: { audio.setModuleEnabled(module.id, !module.enabled) })
                            .frame(height: m.chainRowH)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.92)).combined(with: .offset(x: -8)),
                                                    removal: .opacity.combined(with: .scale(scale: 0.92))))
                            .offset(y: displacement(of: index))
                            .zIndex(dragging == module.id ? 1 : 0)
                            .gesture(
                                DragGesture(minimumDistance: 4, coordinateSpace: .named("chain"))
                                    .onChanged { value in
                                        if dragging == nil {
                                            audio.beginRackEdit()
                                            audio.selectedModule = module.id
                                        }
                                        dragging = module.id
                                        dragOffset = value.translation.height
                                    }
                                    .onEnded { _ in
                                        let to = target(from: index)
                                        withAnimation(T.quick) {
                                            if to != index { audio.moveModule(from: IndexSet(integer: index), to: to > index ? to + 1 : to) }
                                            dragging = nil
                                            dragOffset = 0
                                        }
                                        audio.endRackEdit()
                                    }
                            )
                            .animation(dragging == module.id ? nil : T.quick, value: displacement(of: index))
                    }
                    if audio.rack.modules.isEmpty {
                        Text("Empty chain").font(m.monoSmall).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, m.gutter - 4)
                .coordinateSpace(name: "chain")
                .animation(T.quick, value: audio.rack.modules.map(\.id))
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
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text("Add module").font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(T.card))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(T.hairline, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .padding(.horizontal, m.gutter - 4).padding(.top, m.gap).padding(.bottom, m.sectionTop)
        }
    }
}

struct ChainRow: View {
    let module: RackModule
    let selected: Bool
    let lifted: Bool
    let selection: Namespace.ID
    let select: () -> Void
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 7) {
            Button(action: toggle) {
                Circle().fill(module.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 6, height: 6)
                    .frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(module.enabled ? "Bypass this module" : "Enable this module")
            Image(systemName: module.kind.symbol).font(.system(size: 10)).foregroundStyle(selected ? .primary : .secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.displayName).font(.system(size: 11.5, weight: selected ? .semibold : .medium)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(module.enabled ? .primary : .secondary)
                if let caption = module.caption {
                    Text(caption).font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 7).fill(hover ? T.hover : T.card))
        .background {
            // One highlight that travels between rows instead of each row fading its own.
            if selected {
                RoundedRectangle(cornerRadius: 7).fill(T.press)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(T.accent.opacity(0.5), lineWidth: 0.5))
                    .matchedGeometryEffect(id: "selected", in: selection)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(T.hairline, lineWidth: selected ? 0 : 0.5))
        .shadow(color: .black.opacity(lifted ? 0.28 : 0), radius: lifted ? 10 : 0, y: lifted ? 4 : 0)
        .scaleEffect(lifted ? 1.03 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hover = $0 }
        .help(module.title)
        .animation(T.hoverAnim, value: hover)
        .animation(T.snap, value: selected)
        .animation(T.snap, value: lifted)
    }
}

extension RackModule {
    /// Profile modules are named "<source> · … · <headphone>": the headphone is what you
    /// look for in the chain, the source is detail.
    var displayName: String {
        guard let name, let last = name.components(separatedBy: " · ").last else { return kind.title }
        return last
    }

    /// Second line under the name: where a profile came from and what the module is, or a
    /// short summary for EQs.
    var caption: String? {
        if let name {
            let parts = name.components(separatedBy: " · ").dropLast()
            return (parts.isEmpty ? [kind.title] : Array(parts) + [kind.title]).joined(separator: " · ")
        }
        switch kind {
        case .parametricEQ: return bands.isEmpty ? "no filters" : "\(bands.count) filter\(bands.count == 1 ? "" : "s")"
        default: return kind.group
        }
    }
}

struct ModuleEditor: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    /// With the chain column hidden the header title turns into the module picker, so
    /// switching and adding modules never needs the column.
    var chainOpen = true

    var body: some View {
        if let module = audio.selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Button { audio.setModuleEnabled(module.id, !module.enabled) } label: {
                        Circle().fill(module.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 6, height: 6)
                            .frame(width: 12, height: 12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(module.enabled ? "Bypass this module" : "Enable this module")
                    if chainOpen {
                        Image(systemName: module.kind.symbol).font(.system(size: 12)).foregroundStyle(T.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(module.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                            if let caption = module.caption {
                                Text(caption).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                            }
                        }
                        .help(module.title)
                    } else {
                        Hug {
                            Menu {
                                ForEach(audio.rack.modules) { other in
                                    Button { audio.selectedModule = other.id } label: {
                                        HStack { Label(other.displayName, systemImage: other.kind.symbol); if other.id == module.id { Image(systemName: "checkmark") } }
                                    }
                                }
                                Divider()
                                Menu("Add") {
                                    ForEach(["Tone", "Character", "Dynamics", "Space"], id: \.self) { group in
                                        Section(group) {
                                            ForEach(ModuleKind.allCases.filter { $0.group == group }) { kind in
                                                Button { audio.addModule(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                                            }
                                        }
                                    }
                                }
                                Menu(audio.currentPreset.map { "Preset · \($0.name)" } ?? "Presets") { PresetMenuItems(audio: audio) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: module.kind.symbol).font(.system(size: 12)).foregroundStyle(T.accent)
                                    Text(module.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.visible)
                        }
                        .padding(.leading, 6).padding(.trailing, 2).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(T.card))
                        .help(module.title)
                    }
                    Spacer(minLength: 4)
                    IconButton("arrow.counterclockwise") { audio.resetModule(module.id) }.help("Reset module")
                    IconButton("trash") { audio.removeModule(module.id) }.help("Remove module")
                }
                .padding(.horizontal, m.gutter).padding(.top, m.sectionTop).padding(.bottom, m.gap)

                ScrollView {
                    VStack(alignment: .leading, spacing: m.gap) {
                        ForEach(module.kind.specs, id: \.key) { spec in
                            ParamRow(spec: spec, value: module.param(spec.key),
                                     onEditingChanged: { editing in
                                         if editing { audio.beginRackEdit() } else { audio.endRackEdit() }
                                     }) { audio.setParam(module.id, spec.key, $0) }
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
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 10)), removal: .identity))
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
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false
    init(_ symbol: String, active: Bool = false, action: @escaping () -> Void) { self.symbol = symbol; self.active = active; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                .foregroundStyle(isEnabled ? (active ? T.accent : (hover ? .primary : .secondary)) : Color.primary.opacity(0.28))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(isEnabled ? (active ? T.press : (hover ? T.hover : .clear)) : .clear))
                .scaleEffect(isEnabled && hover ? 1.06 : 1)
        }
        .buttonStyle(Press(scale: 0.88)).onHover { hover = $0 }
        .animation(T.hoverAnim, value: hover)
        .animation(T.snap, value: active)
    }
}

/// Response of the chain's linear stages over a live output spectrum.
/// The selected module's own curve is drawn on top when it is an EQ or filter.
struct Graph: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    @ObservedObject private var meters: Meters
    let analyzing: Bool
    init(audio: AudioState, analyzing: Bool) {
        self.audio = audio; self.meters = audio.meters; self.analyzing = analyzing
    }

    private static let fMin = 20.0, fMax = 20_000.0
    private static let points = 160

    var body: some View {
        let sr = max(8_000, audio.rackTarget?.rate ?? 48_000)
        let chain = (0..<Self.points).map { i -> Double in
            audio.rack.responseDB(at: Self.frequency(at: Double(i) / Double(Self.points - 1)), sampleRate: sr)
        }
        let selected: [Double]? = audio.selected.flatMap { module in
            module.linearCascade(sampleRate: sr) == nil || audio.rack.modules.filter({ $0.enabled && $0.linearCascade(sampleRate: sr) != nil }).count < 2 ? nil
                : (0..<Self.points).map { i in module.responseDB(at: Self.frequency(at: Double(i) / Double(Self.points - 1)), sampleRate: sr) }
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

        }
        // The curves are shapes on top of the canvas so they morph: a fader drag, a preset
        // or a new profile springs the response into place instead of jumping.
        .overlay {
            let norm = CurveVector(chain.map { $0 / range })
            ZStack {
                if let selected {
                    ResponseCurve(values: CurveVector(selected.map { $0 / range }))
                        .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .transition(.opacity)
                }
                ResponseCurve(values: norm, closed: true).fill(T.accent.opacity(0.12))
                ResponseCurve(values: norm).stroke(T.accent, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            .animation(T.snap, value: norm)
            .animation(T.quick, value: selected == nil)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.hairline, lineWidth: 0.5))
        .onAppear { meters.wantsSpectrum = analyzing }
        .onChange(of: analyzing) { _, enabled in meters.wantsSpectrum = enabled }
        .onDisappear { meters.wantsSpectrum = false }
    }

    private static func frequency(at t: Double) -> Double { fMin * pow(fMax / fMin, t) }
}

/// Response values scaled to ±1 of the graph's range; animatable element by element.
struct CurveVector: VectorArithmetic {
    var v: [Double]
    init(_ v: [Double]) { self.v = v }
    static var zero: CurveVector { CurveVector([]) }
    private static func combine(_ a: CurveVector, _ b: CurveVector, _ f: (Double, Double) -> Double) -> CurveVector {
        let n = max(a.v.count, b.v.count)
        return CurveVector((0..<n).map { f($0 < a.v.count ? a.v[$0] : 0, $0 < b.v.count ? b.v[$0] : 0) })
    }
    static func + (a: CurveVector, b: CurveVector) -> CurveVector { combine(a, b, +) }
    static func - (a: CurveVector, b: CurveVector) -> CurveVector { combine(a, b, -) }
    mutating func scale(by rhs: Double) { v = v.map { $0 * rhs } }
    var magnitudeSquared: Double { v.reduce(0) { $0 + $1 * $1 } }
}

struct ResponseCurve: Shape {
    var values: CurveVector
    var closed = false
    var animatableData: CurveVector {
        get { values }
        set { values = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let v = values.v
        guard v.count > 1 else { return p }
        let mid = rect.midY, span = rect.height / 2 - 8
        for (i, n) in v.enumerated() {
            let pt = CGPoint(x: rect.minX + CGFloat(i) / CGFloat(v.count - 1) * rect.width, y: mid - CGFloat(n) * span)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        if closed { p.addLine(to: CGPoint(x: rect.maxX, y: mid)); p.addLine(to: CGPoint(x: rect.minX, y: mid)); p.closeSubpath() }
        return p
    }
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
                    Image(systemName: audio.importing ? "arrow.down.circle" : "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                    TextField(searchPrompt, text: $query)
                        .textFieldStyle(.plain).font(.system(size: 12))
                        .onChange(of: query) { _, q in if !q.isEmpty { loadCatalog() } }
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(T.card))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(T.hairline, lineWidth: 0.5))
                IconButton("square.and.arrow.down") { audio.importParametricFile() }.help("Import ParametricEQ.txt")
                IconButton("square.and.arrow.up") { audio.exportParametricFile(module.id) }.help("Export ParametricEQ.txt")
            }
            ProfileChips(audio: audio)
            if !query.isEmpty {
                ProfileResults(audio: audio, query: query) { query = "" }
                    .transition(T.rise)
            }

            BandColumns(bands: bands, selected: current?.id, height: m.faderH,
                        select: { selectedBand = $0 },
                        setGain: { id, g in audio.setBand(module.id, id) { $0.gainDB = g } },
                        onEditingChanged: { editing in
                            if editing { audio.beginRackEdit() } else { audio.endRackEdit() }
                        })

            if let band = current {
                BandDetail(band: band,
                           setType: { t in audio.setBand(module.id, band.id) { $0.type = t } },
                           setFreq: { f in audio.setBand(module.id, band.id) { $0.frequency = f } },
                           setQ: { q in audio.setBand(module.id, band.id) { $0.q = q } },
                           onEditingChanged: { editing in
                               if editing { audio.beginRackEdit() } else { audio.endRackEdit() }
                           },
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
        .animation(T.snap, value: selectedBand)
        .animation(T.quick, value: query.isEmpty)
    }

    private var searchPrompt: String {
        switch audio.profileSource {
        case .all: "Search headphones and IEMs…"
        case .autoEQ: "AutoEq headphone…"
        case .squig: "\(audio.squig.database?.siteName ?? "squig.link") phone…"
        }
    }

    private func loadCatalog() {
        switch audio.profileSource {
        case .all: audio.autoEQ.load(); audio.squig.loadAll()
        case .autoEQ: audio.autoEQ.load()
        case .squig: audio.squig.load()
        }
    }
}

/// One vertical gain fader per band, low frequencies on the left. Tap a column to
/// edit its type, frequency and Q below.
struct BandColumns: View {
    @Environment(\.metrics) private var m
    @Environment(\.editorWidth) private var editorWidth
    let bands: [EQBand]
    let selected: UUID?
    let height: CGFloat
    let select: (UUID) -> Void
    let setGain: (UUID, Double) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }
    @Namespace private var highlight

    var body: some View {
        // Columns share the editor width down to 28 pt each (enough for "10.3k"); past that
        // they keep 28 pt and the row scrolls. One ScrollView either way, so adding a band
        // never swaps the view out from under the pointer.
        let spacing: CGFloat = 2, inset: CGFloat = 6
        let available = editorWidth - 2 * m.gutter - 2 * inset
        let n = CGFloat(max(bands.count, 1))
        let width = max(28, min(56, (available - spacing * (n - 1)) / n))
        let overflow = width * n + spacing * (n - 1) > available + 0.5
        ScrollView(.horizontal, showsIndicators: overflow) {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(bands) { band in
                    BandColumn(band: band, selected: band.id == selected, height: height,
                               select: { select(band.id) }, setGain: { setGain(band.id, $0) },
                               onEditingChanged: onEditingChanged)
                        .frame(width: width)
                        .background {
                            if band.id == selected {
                                RoundedRectangle(cornerRadius: 6).fill(T.press).matchedGeometryEffect(id: "selected", in: highlight)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .bottom)))
                }
            }
            .animation(T.snap, value: selected)
            .padding(.vertical, 8).padding(.horizontal, inset)
            .frame(minWidth: available + 2 * inset, alignment: .center)
        }
        .scrollDisabled(!overflow)
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: overflow ? 10 : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: overflow ? 10 : 0)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(T.card))
        .overlay {
            if bands.isEmpty { Text("No filters").font(m.mono).foregroundStyle(.tertiary) }
        }
    }
}

struct BandColumn: View {
    @Environment(\.metrics) private var m
    /// Whole dB with a sign; anything that rounds to zero is "0", never "-0".
    static func gainLabel(_ db: Double) -> String {
        let r = db.rounded()
        return r == 0 ? "0" : String(format: "%+.0f", r)
    }
    let band: EQBand
    let selected: Bool
    let height: CGFloat
    let select: () -> Void
    let setGain: (Double) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }
    var body: some View {
        VStack(spacing: 5) {
            Text(band.type.usesGain ? Self.gainLabel(band.gainDB) : "·")
                .font(m.monoSmall).foregroundStyle(selected ? .primary : .tertiary).lineLimit(1)
            VFader(value: band.gainDB, range: -18...18, label: { String(format: "%+.1f dB", $0) },
                   onEditingChanged: onEditingChanged) { setGain(($0 * 2).rounded() / 2) }
                .frame(height: height)
                .opacity(band.type.usesGain ? 1 : 0.3)
                .disabled(!band.type.usesGain)
            Text(band.frequency >= 1000 ? String(format: "%.1fk", band.frequency / 1000) : String(format: "%.0f", band.frequency))
                .font(m.monoSmall).foregroundStyle(selected ? .primary : .tertiary).lineLimit(1).minimumScaleFactor(0.7)
            Circle().fill(band.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 5, height: 5)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .opacity(band.enabled ? 1 : 0.55)
        .animation(T.quick, value: band.enabled)
    }
}

struct BandDetail: View {
    @Environment(\.metrics) private var m
    let band: EQBand
    let setType: (FilterType) -> Void
    let setFreq: (Double) -> Void
    let setQ: (Double) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }
    let toggle: () -> Void
    let remove: () -> Void

    private static func hz(_ f: Double) -> String { f >= 1000 ? String(format: "%.2f kHz", f / 1000) : String(format: "%.0f Hz", f) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    Circle().fill(band.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 7, height: 7).frame(width: 14, height: 14).contentShape(Rectangle())
                }.buttonStyle(.plain).help(band.enabled ? "Disable filter" : "Enable filter")
                Picker("", selection: Binding(get: { band.type }, set: setType)) {
                    ForEach(FilterType.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().controlSize(.small).frame(width: 92)
                Spacer(minLength: 4)
                IconButton("xmark") { remove() }.help("Remove filter")
            }
            HStack(spacing: 8) {
                Text("Freq").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                Fader(value: band.frequency, range: 20...20_000, log: true, label: Self.hz, onEditingChanged: onEditingChanged, set: setFreq)
                Text(Self.hz(band.frequency)).font(m.mono).foregroundStyle(.secondary).lineLimit(1).frame(width: 64, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Text("Q").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                Fader(value: band.q, range: 0.1...12, log: true, label: { String(format: "%.2f", $0) }, onEditingChanged: onEditingChanged, set: setQ)
                Text(String(format: "%.2f", band.q)).font(m.mono).foregroundStyle(.secondary).lineLimit(1).frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.vertical, m.bandV).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(T.card))
    }
}

/// Search results for the current source. In *All sources* AutoEq's curated results
/// come first, then every squig.link database that lists the phone, each labelled.
struct ProfileResults: View {
    @Environment(\.metrics) private var m
    @ObservedObject var audio: AudioState
    let query: String
    let done: () -> Void
    @ObservedObject private var autoEQ: AutoEQCatalog
    @ObservedObject private var squig: SquigCatalog

    init(audio: AudioState, query: String, done: @escaping () -> Void) {
        self.audio = audio; self.query = query; self.done = done
        self.autoEQ = audio.autoEQ; self.squig = audio.squig
    }

    private enum Row: Identifiable {
        case header(String), autoEQ(AutoEQCatalog.Entry), squig(SquigCatalog.Hit)
        var id: String {
            switch self {
            case .header(let t): "h|" + t
            case .autoEQ(let e): "a|" + e.id
            case .squig(let h): "s|" + h.id
            }
        }
    }

    private var rows: [Row] {
        switch audio.profileSource {
        case .all:
            // Grouped by where the curve comes from. AutoEq lists many variants of one
            // model, so it is capped to keep the reviewer measurements in view.
            let curated = autoEQ.search(query, limit: 8).map(Row.autoEQ)
            let measured = squig.search(query, everywhere: true, limit: 40)
            let sites = Set(measured.map(\.db.site)).count
            return (curated.isEmpty ? [] : [.header("AutoEq · ready-made corrections")] + curated)
                + (measured.isEmpty ? [] : [.header("squig.link · \(measured.count) measurements from \(sites) reviewer\(sites == 1 ? "" : "s")")] + measured.map(Row.squig))
        case .autoEQ:
            return autoEQ.search(query).map(Row.autoEQ)
        case .squig:
            return squig.search(query, everywhere: false).map(Row.squig)
        }
    }

    /// Loading or failure to report above (or instead of) the rows.
    private var status: (text: String, warn: Bool)? {
        switch audio.profileSource {
        case .all:
            if squig.indexTotal == 0 || squig.indexed < squig.indexTotal {
                return ("Searching \(squig.indexed)/\(max(squig.indexTotal, squig.indexed)) squig.link databases…", false)
            }
            if case .loading = autoEQ.state { return ("Loading AutoEq…", false) }
            return nil
        case .autoEQ:
            switch autoEQ.state {
            case .loading: return ("Loading catalogue…", false)
            case .failed(let e): return ("Catalogue unavailable: \(e)", true)
            default: return nil
            }
        case .squig:
            if squig.database == nil { return ("Pick a squig.link database first", false) }
            switch squig.state {
            case .loading: return ("Loading measurements…", false)
            case .failed(let e): return ("Database unavailable: \(e)", true)
            default: return nil
            }
        }
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 0) {
            if let status {
                Text(status.text).font(m.monoSmall).foregroundStyle(status.warn ? T.warn : Color.secondary.opacity(0.6))
                    .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, rows.isEmpty ? 8 : 2)
            }
            if rows.isEmpty {
                if status == nil { Text("No matches").font(m.mono).foregroundStyle(.tertiary).padding(10) }
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(rows) { row in
                            if case .header(let text) = row {
                                Text(text).font(m.monoSmall).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 9).padding(.top, 8).padding(.bottom, 2)
                            } else {
                            Button { apply(row); done() } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title(row)).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                        Text(source(row)).font(m.monoSmall).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 9).padding(.vertical, 5).contentShape(Rectangle())
                            }
                            .buttonStyle(Press()).hoverRow(6)
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 220)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.hairline, lineWidth: 0.5))
    }

    private var all: Bool { audio.profileSource == .all }

    private func apply(_ row: Row) {
        switch row {
        case .autoEQ(let e): audio.applyAutoEQ(e)
        case .squig(let h): audio.applySquig(h)
        case .header: break
        }
    }

    private func title(_ row: Row) -> String {
        switch row {
        case .autoEQ(let e): e.title
        case .squig(let h): h.entry.title
        case .header(let t): t
        }
    }

    private func source(_ row: Row) -> String {
        switch row {
        case .autoEQ(let e): all ? e.subtitle : "AutoEq · " + e.subtitle
        case .squig(let h): h.db.title
        case .header: ""
        }
    }
}

/// A small rounded control surface for a hugging Menu.
struct Chip<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Hug { content }
            .padding(.leading, 8).padding(.trailing, 2).padding(.vertical, 3)
            .background(Capsule().fill(T.card))
            .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
    }
}

/// Left-to-right rows that wrap, each child at its ideal width capped to the row, so a
/// long target name moves to the next line instead of pushing the chips off the edge.
struct Flow: Layout {
    var spacing: CGFloat = 6

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]], x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rs = rows(subviews, width: width)
        let h = rs.reduce(0) { $0 + ($1.map(\.1.height).max() ?? 0) } + spacing * CGFloat(max(0, rs.count - 1))
        let w = rs.map { $0.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, $0.count - 1)) }.max() ?? 0
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let h = row.map(\.1.height).max() ?? 0
            for (i, size) in row {
                subviews[i].place(at: CGPoint(x: x, y: y + (h - size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += h + spacing
        }
    }
}

/// Source, filter count and (for squig.link) target for the profile search.
struct ProfileChips: View {
    @ObservedObject var audio: AudioState
    @ObservedObject private var squig: SquigCatalog

    init(audio: AudioState) { self.audio = audio; self.squig = audio.squig }

    var body: some View {
        Flow(spacing: 6) {
            Chip {
                Menu {
                    Button { audio.profileSource = .all } label: {
                        HStack { Text("All sources"); if audio.profileSource == .all { Image(systemName: "checkmark") } }
                    }
                    Divider()
                    Button { audio.profileSource = .autoEQ } label: {
                        HStack { Text("AutoEq"); if audio.profileSource == .autoEQ { Image(systemName: "checkmark") } }
                    }
                    Menu("squig.link") {
                        if squig.databases.isEmpty {
                            Text("Loading sites…")
                        }
                        ForEach(squig.databases) { db in
                            Button { audio.profileSource = .squig; squig.select(db) } label: {
                                HStack { Text(db.title); if audio.profileSource == .squig, db == squig.database { Image(systemName: "checkmark") } }
                            }
                        }
                    }
                } label: {
                    Text(sourceTitle).font(.system(size: 11)).lineLimit(1)
                }
                .menuStyle(.borderlessButton).menuIndicator(.visible)
                .onAppear {
                    squig.loadSites()
                    if audio.profileSource == .squig { squig.load() }
                }
            }
            .help("Where profiles come from: everywhere at once, AutoEq's index, or one reviewer's measurements on squig.link")
            Chip {
                Menu {
                    ForEach(AudioState.importBandChoices, id: \.self) { n in
                        Button { audio.importBands = n } label: { HStack { Text("\(n) filters"); if n == audio.importBands { Image(systemName: "checkmark") } } }
                    }
                } label: { Text("\(audio.importBands) filters").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).menuIndicator(.visible)
            }
            .help("Filters to fit. AutoEq's own result is used at 10; other counts are fitted from the full-resolution correction.")
            if audio.profileSource == .all {
                Chip {
                    Menu {
                        ForEach(SquigCatalog.Style.allCases) { style in
                            Button { audio.targetStyle = style } label: { HStack { Text(style.title); if style == audio.targetStyle { Image(systemName: "checkmark") } } }
                        }
                    } label: { Text("Target: \(audio.targetStyle.title)").font(.system(size: 11)).lineLimit(1) }
                    .menuStyle(.borderlessButton).menuIndicator(.visible)
                }
                .help("What squig.link measurements are corrected towards: each reviewer's Harman curve for that kind of phone, or their neutral (diffuse-field) curve. AutoEq results are its own Harman corrections.")
            }
            if audio.profileSource == .squig, !squig.targets.isEmpty {
                Chip {
                    Menu {
                        ForEach(squig.targets) { t in
                            Button { squig.setTarget(t) } label: { HStack { Text(t.name); if t == squig.target { Image(systemName: "checkmark") } } }
                        }
                    } label: { Text(squig.target?.name ?? "Target").font(.system(size: 11)).lineLimit(1) }
                    .menuStyle(.borderlessButton).menuIndicator(.visible)
                }
                .help("Target curve the measurement is corrected towards")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceTitle: String {
        switch audio.profileSource {
        case .all: "All sources"
        case .autoEQ: "AutoEq"
        case .squig: squig.database?.title ?? "squig.link"
        }
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
                        Text(BandColumn.gainLabel(band.gainDB)).font(m.monoSmall).foregroundStyle(.tertiary)
                        VFader(value: band.gainDB, range: -12...12, label: { String(format: "%+.1f dB", $0) },
                               onEditingChanged: { editing in
                                   if editing { audio.beginRackEdit() } else { audio.endRackEdit() }
                               }) { g in
                            audio.setBand(module.id, band.id) { $0.gainDB = (g * 2).rounded() / 2 }
                        }
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
                Button("Flatten") {
                    audio.beginRackEdit()
                    for b in module.bands { audio.setBand(module.id, b.id) { $0.gainDB = 0 } }
                    audio.endRackEdit()
                }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
}
