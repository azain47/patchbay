import Cocoa
import SwiftUI

struct RackSummary: View {
    @ObservedObject var audio: AudioState
    let open: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Button(action: open) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DSP rack")
                                .font(.system(size: 13, weight: .medium))
                            Text(audio.rackStatus.label)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(statusColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(Tap())

                Spacer()

                Toggle("", isOn: Binding(
                    get: { audio.rackOn },
                    set: { audio.setRackOn($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(audio.active != nil)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.08))
                    Rectangle()
                        .fill(Color.amber)
                        .frame(width: geometry.size.width * CGFloat(min(1, max(0, audio.rackPeak))))
                }
            }
            .frame(height: 2)
            .opacity(audio.rackOn ? 1 : 0.35)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch audio.rackStatus {
        case .running: .sage
        case .failed: .red.opacity(0.8)
        case .proving: .amber
        case .stopped: .secondary
        }
    }
}

struct RackEditor: View {
    @ObservedObject var audio: AudioState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(audio.rack.modules.enumerated()), id: \.element) { index, module in
                        ModuleEditor(audio: audio, module: module, index: index)
                        if index < audio.rack.modules.count - 1 { Divider().padding(.leading, 42) }
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 570)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("patchbay")
                    .font(.system(size: 22, weight: .semibold))
                Text(audio.rackTarget?.name ?? "No output")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(audio.rackStatus.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(audio.rackOn ? Color.sage : Color.secondary)
            Toggle("Rack", isOn: Binding(
                get: { audio.rackOn },
                set: { audio.setRackOn($0) }
            ))
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Text("\(audio.rack.modules.count) modules  ·  \(audio.rack.bands.count) filters")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Reset") { audio.resetRack() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct ModuleEditor: View {
    @ObservedObject var audio: AudioState
    let module: RackModuleKind
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: module.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.amber)
                    .frame(width: 16)
                Text(module.rawValue)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button { audio.moveModule(at: index, by: -1) } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                Button { audio.moveModule(at: index, by: 1) } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == audio.rack.modules.count - 1)
            }
            .buttonStyle(.plain)

            controls
                .padding(.leading, 25)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var controls: some View {
        switch module {
        case .preamp:
            ParameterSlider(
                label: "Gain",
                value: audio.rack.preampDB,
                range: -24...12,
                valueLabel: String(format: "%+.1f dB", audio.rack.preampDB),
                set: audio.setPreamp
            )
        case .balance:
            ParameterSlider(
                label: "Position",
                value: audio.rack.balance,
                range: -1...1,
                valueLabel: balanceLabel,
                set: audio.setBalance
            )
        case .limiter:
            ParameterSlider(
                label: "Ceiling",
                value: audio.rack.limiterThresholdDB,
                range: -12...(-0.1),
                valueLabel: String(format: "%.1f dB", audio.rack.limiterThresholdDB),
                set: audio.setLimiterThreshold
            )
        case .equalizer:
            VStack(spacing: 10) {
                ForEach(audio.rack.bands) { band in
                    BandEditor(audio: audio, band: band)
                }
            }
        }
    }

    private var balanceLabel: String {
        if abs(audio.rack.balance) < 0.01 { return "center" }
        return String(format: "%.0f%% %@", abs(audio.rack.balance) * 100, audio.rack.balance < 0 ? "left" : "right")
    }
}

private struct BandEditor: View {
    @ObservedObject var audio: AudioState
    let band: EQBand

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { band.enabled },
                    set: { audio.setBandEnabled(band.id, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)

                Picker("", selection: Binding(
                    get: { band.type },
                    set: { audio.setBandType(band.id, $0) }
                )) {
                    ForEach(FilterType.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 96)

                Slider(value: Binding(
                    get: { log10(band.frequency) },
                    set: { audio.setBandFrequency(band.id, pow(10, $0)) }
                ), in: log10(20)...log10(20_000))

                Text(frequencyLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }

            HStack(spacing: 10) {
                ParameterSlider(
                    label: "Gain",
                    value: band.gainDB,
                    range: -15...15,
                    valueLabel: String(format: "%+.1f dB", band.gainDB),
                    set: { audio.setBandGain(band.id, $0) }
                )
                ParameterSlider(
                    label: "Q",
                    value: band.q,
                    range: 0.2...10,
                    valueLabel: String(format: "%.2f", band.q),
                    set: { audio.setBandQ(band.id, $0) }
                )
            }
            .opacity(band.type == .lowShelf || band.type == .highShelf ? 0.65 : 1)
        }
        .opacity(band.enabled ? 1 : 0.4)
    }

    private var frequencyLabel: String {
        band.frequency >= 1_000
            ? String(format: "%.1f kHz", band.frequency / 1_000)
            : String(format: "%.0f Hz", band.frequency)
    }
}

private struct ParameterSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let valueLabel: String
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range)
            Text(valueLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
        }
    }
}

final class RackWindowController {
    private var window: NSWindow?

    func show(audio: AudioState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: RackEditor(audio: audio))
        let window = NSWindow(contentViewController: controller)
        window.title = "patchbay DSP rack"
        window.setContentSize(NSSize(width: 540, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
