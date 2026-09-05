import Cocoa
import SwiftUI

// MARK: - Tokens

enum T {
    static let accent = Color(red: 0.86, green: 0.66, blue: 0.36)
    static let ok = Color(red: 0.48, green: 0.68, blue: 0.48)
    static let warn = Color(red: 0.85, green: 0.42, blue: 0.36)
    static let hover = Color.primary.opacity(0.07)
    static let press = Color.primary.opacity(0.12)
    static let track = Color.primary.opacity(0.13)
    static let card = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.09)

    static let name = Font.system(size: 13, weight: .regular)
    static let nameStrong = Font.system(size: 13, weight: .semibold)
    static let mono = Font.system(size: 10.5, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 9, weight: .medium, design: .monospaced)
    static let section = Font.system(size: 10, weight: .bold)
    static let title = Font.system(size: 15, weight: .semibold)

    static let quick = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let page = Animation.spring(response: 0.32, dampingFraction: 0.88)
    static let hoverAnim = Animation.easeOut(duration: 0.12)

    static let devicesWidth: CGFloat = 372
    static let rackWidth: CGFloat = 640
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
    var radius: CGFloat = 7
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(hover ? T.hover : .clear))
            .onHover { hover = $0 }
            .animation(T.hoverAnim, value: hover)
    }
}
extension View { func hoverRow(_ radius: CGFloat = 7) -> some View { modifier(HoverRow(radius: radius)) } }

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(T.section).tracking(1.1).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
    }
}

// MARK: - Root

enum Page { case devices, rack }

struct Root: View {
    @ObservedObject var audio: AudioState
    @State private var page: Page = .devices

    var body: some View {
        ZStack {
            if page == .devices {
                DevicesPage(audio: audio) { withAnimation(T.page) { page = .rack } }
                    .frame(width: T.devicesWidth)
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                RackPage(audio: audio) { withAnimation(T.page) { page = .devices } }
                    .frame(width: T.rackWidth)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .animation(T.page, value: page)
        .overlay(alignment: .bottom) {
            if let notice = audio.notice {
                Text(notice).font(T.mono).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation(T.quick) { audio.notice = nil } } }
            }
        }
    }
}

// MARK: - Devices page

struct DevicesPage: View {
    @ObservedObject var audio: AudioState
    let openRack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("patchbay").font(T.title)
                Spacer()
                RackPill(audio: audio, action: openRack)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)

            SectionLabel(text: "Output")
            VStack(spacing: 1) {
                ForEach(audio.outputs) { d in DeviceRow(device: d, isRackTarget: audio.rackOn && audio.rackTarget?.id == d.id) { audio.select(d) } }
            }
            .padding(.horizontal, 6)
            if let vol = audio.outputVolume, audio.currentOutput?.isEqMac == false {
                LevelRow(icon: "speaker.wave.2", value: Double(vol)) { audio.setOutputVolume(Float($0)) }
            }

            SectionLabel(text: "Input")
            VStack(spacing: 1) {
                ForEach(audio.inputs) { d in DeviceRow(device: d, isRackTarget: false) { audio.select(d) } }
            }
            .padding(.horizontal, 6)
            LevelRow(icon: "mic", value: Double(audio.inputVolume)) { audio.setInputVolume(Float($0)) }

            Rectangle().fill(T.hairline).frame(height: 0.5).padding(.horizontal, 14).padding(.top, 10)

            HStack(spacing: 6) {
                Circle().fill(audio.eqMacOn ? T.ok : Color.secondary.opacity(0.3)).frame(width: 5, height: 5)
                Text("eqMac \(audio.eqMacOn ? "on" : "off")").font(T.mono).foregroundStyle(.tertiary)
                Spacer()
                Menu {
                    Button("Fix audio") { audio.fixAudio() }
                    Button("Restart eqMac") { audio.restartEqMac() }
                    Button("Reset Core Audio…") { audio.resetCA() }
                } label: {
                    Image(systemName: audio.active != nil && audio.active != .rack ? "hourglass" : "wrench.adjustable")
                        .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 22, height: 20)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
                .disabled(audio.active != nil)
                Button("Quit") { NSApp.terminate(nil) }.font(.system(size: 11)).foregroundStyle(.tertiary).buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
    }
}

struct RackPill: View {
    @ObservedObject var audio: AudioState
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .medium))
                    Text("Rack").font(.system(size: 12, weight: .medium))
                    Meter(level: audio.outputPeak).frame(width: 26, height: 3).opacity(audio.rackOn ? 1 : 0.3)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(hover ? T.press : T.card))
                .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
            }
            .buttonStyle(Press())
            .onHover { hover = $0 }
            .animation(T.hoverAnim, value: hover)
            Toggle("", isOn: Binding(get: { audio.rackOn }, set: { audio.setRackOn($0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(T.accent)
                .disabled(audio.active != nil)
        }
    }
}

struct DeviceRow: View {
    let device: Device
    let isRackTarget: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(device.isDefault ? T.accent.opacity(0.9) : Color.primary.opacity(0.08))
                    Image(systemName: device.icon).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(device.isDefault ? Color.black.opacity(0.8) : Color.primary.opacity(0.7))
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(device.isDefault ? T.nameStrong : T.name).lineLimit(1)
                    Text("\(device.formattedRate)  \(device.transportLabel)").font(T.monoSmall).foregroundStyle(.tertiary)
                }
                Spacer()
                if isRackTarget { Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(T.accent) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .hoverRow()
    }
}

struct LevelRow: View {
    let icon: String
    let value: Double
    let set: (Double) -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 24)
            Fader(value: value, range: 0...1, set: set)
            Text("\(Int((value * 100).rounded()))%").font(T.mono).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 2)
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

struct Fader: View {
    let value: Double
    let range: ClosedRange<Double>
    var log = false
    var center: Double? = nil
    let set: (Double) -> Void
    @State private var hover = false
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
                Circle().fill(Color.white).frame(width: dragging ? 12 : 10, height: dragging ? 12 : 10)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .offset(x: max(0, min(w - 10, x - 5)))
                    .animation(T.quick, value: dragging)
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in dragging = true; set(denorm(v.location.x / w)) }.onEnded { _ in dragging = false })
        }
        .frame(height: 16)
        .onHover { hover = $0 }
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
                Circle().fill(Color.white).frame(width: dragging ? 12 : 10, height: dragging ? 12 : 10)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .offset(y: max(0, min(h - 10, y - 5)))
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
        HStack(spacing: 10) {
            Text(spec.label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
            if let options = spec.options {
                Picker("", selection: Binding(get: { Int(value.rounded()) }, set: { set(Double($0)) })) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, o in Text(o).tag(i + Int(spec.range.lowerBound)) }
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.small)
            } else {
                Fader(value: value, range: spec.range, log: spec.log, center: spec.range.contains(0) && spec.range.lowerBound < 0 ? 0 : nil) { v in
                    set(spec.step > 0 ? (v / spec.step).rounded() * spec.step : v)
                }
                Text(format(value)).font(T.mono).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            }
        }
        .frame(height: 22)
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

// MARK: - Rack page

struct RackPage: View {
    @ObservedObject var audio: AudioState
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: back) {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)); Text("Devices").font(.system(size: 12, weight: .medium)) }
                        .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(Press()).hoverRow(6)
                Spacer()
                Text(audio.rackTarget?.name ?? "No output").font(T.mono).foregroundStyle(.secondary)
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(audio.rackStatus.label).font(T.mono).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    audio.setBypass(!audio.rack.bypass)
                } label: {
                    Text("Bypass").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(audio.rack.bypass ? Color.black.opacity(0.85) : .secondary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(audio.rack.bypass ? T.accent : T.card))
                        .overlay(Capsule().strokeBorder(T.hairline, lineWidth: 0.5))
                }
                .buttonStyle(Press())
                .animation(T.quick, value: audio.rack.bypass)
                Toggle("", isOn: Binding(get: { audio.rackOn }, set: { audio.setRackOn($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(T.accent).disabled(audio.active != nil)
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)

            Rectangle().fill(T.hairline).frame(height: 0.5)

            HStack(spacing: 0) {
                ChainColumn(audio: audio).frame(width: 214)
                Rectangle().fill(T.hairline).frame(width: 0.5)
                ModuleEditor(audio: audio).frame(maxWidth: .infinity)
            }
            .frame(height: 430)

            Rectangle().fill(T.hairline).frame(height: 0.5)

            HStack(spacing: 12) {
                MeterPair(label: "in", level: audio.inputPeak)
                MeterPair(label: "out", level: audio.outputPeak)
                Spacer()
                Text(diagnosticsText).font(T.monoSmall).foregroundStyle(.tertiary)
                Menu {
                    Picker("Tap", selection: Binding(get: { audio.tapMode }, set: { audio.tapMode = $0 })) {
                        Text("Stereo mixdown").tag(SystemAudioEngine.TapMode.mixdown)
                        Text("Device stream (no resample)").tag(SystemAudioEngine.TapMode.deviceStream)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 20, height: 18)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                Button("Reset rack") { audio.resetRack() }.font(.system(size: 11)).foregroundStyle(.tertiary).buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .onChange(of: audio.rackStatus) { _, s in if case .failed(let m) = s { audio.notice = m } }
    }

    private var statusColor: Color {
        switch audio.rackStatus {
        case .running: audio.rack.bypass ? T.accent : T.ok
        case .proving: T.accent
        case .failed: T.warn
        case .stopped: Color.secondary.opacity(0.35)
        }
    }

    private var diagnosticsText: String {
        guard audio.rackOn, audio.diagnostics.sampleRate > 0 else { return "" }
        return String(format: "%@ · %.1f kHz · drift %@", audio.diagnostics.tapBinding, audio.diagnostics.sampleRate / 1000, audio.diagnostics.driftCompensation ? "on" : "off")
    }
}

struct MeterPair: View {
    let label: String
    let level: Float
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(T.monoSmall).foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
            Meter(level: level).frame(width: 70, height: 3)
        }
    }
}

struct ChainColumn: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(text: "Chain")
                Spacer()
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
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26).padding(.trailing, 8).padding(.top, 6)
            }
            ScrollView {
                VStack(spacing: 1) {
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
                .padding(.horizontal, 6).padding(.bottom, 6)
                .animation(T.quick, value: audio.rack.modules.map(\.id))
                if audio.rack.modules.isEmpty {
                    Text("Empty chain. Add a module with +.").font(T.mono).foregroundStyle(.tertiary).padding()
                }
            }
        }
    }
}

struct ChainRow: View {
    let module: RackModule
    let selected: Bool
    let select: () -> Void
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
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
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? T.press : (hover ? T.hover : .clear)))
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
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(m.kind.specs, id: \.key) { spec in
                            ParamRow(spec: spec, value: m.param(spec.key)) { audio.setParam(m.id, spec.key, $0) }
                        }
                        switch m.kind {
                        case .parametricEQ: ParametricEditor(audio: audio, module: m)
                        case .graphicEQ: GraphicEditor(audio: audio, module: m)
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 12)
                }
            }
            .id(m.id)
            .transition(.opacity)
        } else {
            VStack(spacing: 6) {
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
                .foregroundStyle(hover ? .primary : .secondary).frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(hover ? T.hover : .clear))
        }
        .buttonStyle(Press()).onHover { hover = $0 }.animation(T.hoverAnim, value: hover)
    }
}

struct ParametricEditor: View {
    @ObservedObject var audio: AudioState
    let module: RackModule
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                    TextField("AutoEq headphone…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                        .onSubmit { audio.autoEQ.load() }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(T.card))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.hairline, lineWidth: 0.5))
                .onAppear { audio.autoEQ.load() }
                IconButton("square.and.arrow.down") { audio.importParametricFile() }
                IconButton("square.and.arrow.up") { audio.exportParametricFile(module.id) }
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
            .padding(.top, 4)

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
            case .loading: Text("Loading catalogue…").font(T.mono).foregroundStyle(.tertiary).padding(8)
            case .failed(let e): Text("Catalogue unavailable: \(e)").font(T.mono).foregroundStyle(T.warn).padding(8)
            case .idle: EmptyView()
            case .ready:
                let results = catalog.search(query)
                if results.isEmpty {
                    Text("No matches").font(T.mono).foregroundStyle(.tertiary).padding(8)
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(results) { e in
                                Button { audio.applyAutoEQ(e); done() } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(e.title).font(.system(size: 12)).lineLimit(1)
                                            Text(e.subtitle).font(T.monoSmall).foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4).contentShape(Rectangle())
                                }
                                .buttonStyle(Press()).hoverRow(5)
                            }
                        }
                        .padding(3)
                    }
                    .frame(maxHeight: 170)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 7).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(T.hairline, lineWidth: 0.5))
        .transition(.opacity.combined(with: .move(edge: .top)))
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
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    Circle().fill(band.enabled ? T.accent : Color.primary.opacity(0.18)).frame(width: 7, height: 7).frame(width: 14, height: 14).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Picker("", selection: Binding(get: { band.type }, set: setType)) {
                    ForEach(FilterType.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().controlSize(.small).frame(width: 96)
                Fader(value: band.frequency, range: 20...20_000, log: true, set: setFreq)
                Text(band.frequency >= 1000 ? String(format: "%.2fk", band.frequency / 1000) : String(format: "%.0f", band.frequency))
                    .font(T.mono).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                IconButton("xmark") { remove() }.opacity(hover ? 1 : 0.25)
            }
            HStack(spacing: 8) {
                Color.clear.frame(width: 14)
                Text("Gain").font(T.monoSmall).foregroundStyle(.tertiary).frame(width: 30, alignment: .leading)
                Fader(value: band.gainDB, range: -18...18, center: 0, set: setGain).opacity(band.type.usesGain ? 1 : 0.35).disabled(!band.type.usesGain)
                Text(String(format: "%+.1f", band.gainDB)).font(T.mono).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                Text("Q").font(T.monoSmall).foregroundStyle(.tertiary).frame(width: 12, alignment: .leading)
                Fader(value: band.q, range: 0.1...12, log: true, set: setQ).frame(width: 90)
                Text(String(format: "%.2f", band.q)).font(T.mono).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(hover ? T.hover : T.card))
        .opacity(band.enabled ? 1 : 0.5)
        .onHover { hover = $0 }
        .animation(T.hoverAnim, value: hover)
    }
}

struct GraphicEditor: View {
    @ObservedObject var audio: AudioState
    let module: RackModule

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(module.bands) { band in
                    VStack(spacing: 5) {
                        Text(String(format: "%+.0f", band.gainDB)).font(T.monoSmall).foregroundStyle(.tertiary)
                        VFader(value: band.gainDB, range: -12...12) { g in audio.setBand(module.id, band.id) { $0.gainDB = (g * 2).rounded() / 2 } }
                            .frame(height: 150)
                        Text(band.frequency >= 1000 ? String(format: "%.0fk", band.frequency / 1000) : String(format: "%.0f", band.frequency))
                            .font(T.monoSmall).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(T.card))
            HStack {
                Spacer()
                Button("Flatten") { for b in module.bands { audio.setBand(module.id, b.id) { $0.gainDB = 0 } } }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
}
