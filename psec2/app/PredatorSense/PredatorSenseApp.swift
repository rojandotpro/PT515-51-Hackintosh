//
//  PredatorSenseApp.swift — menu bar front end.
//

import SwiftUI
import AppKit      // NSApplication — SwiftUI does not re-export AppKit

@main
struct PredatorSenseApp: App {
    @StateObject private var model = PSECModel()

    /// The Predator mark as a TEMPLATE image, so macOS recolours it for the
    /// current menu bar appearance instead of us shipping a black shape that
    /// disappears in dark mode. Falls back to the SF Symbol if absent.
    private var menuIcon: some View {
        if let img = NSImage(named: "MenuIcon") {
            img.isTemplate = true
            img.size = NSSize(width: 17, height: 17)
            return AnyView(Image(nsImage: img)
                .opacity(model.connected ? 1.0 : 0.4))
        }
        return AnyView(Image(systemName: model.connected ? "fan.fill" : "fan.slash"))
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model)
                .onAppear { model.start() }
                .onDisappear { model.stop() }
        } label: {
            HStack(spacing: 3) {
                menuIcon
                if model.connected && model.state.cpuTempC >= 0 {
                    Text("\(model.state.cpuTempC)°")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: PSECModel

    // A plain VStack, deliberately. A ScrollView has no intrinsic height, so in
    // a MenuBarExtra(.window) it collapses to zero and the popover comes up
    // empty — which is exactly what happened in 2.9.x. The panel now sizes
    // itself to its content again; the overflow that motivated the ScrollView
    // was really the ColorPickers and the six-across mode picker, both gone.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !model.connected {
                disconnected
            } else {
                if model.state.thermalTripped || model.state.watchdogTripped { banner }
                fans
                Divider()
                power
                Divider()
                display
                Divider()
                keyboard
                Divider()
                readouts
            }
            Divider()
            HStack {
                if let e = model.lastError, model.connected {
                    Text(e).font(.caption2).foregroundStyle(.red).lineLimit(1)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.font(.caption)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("PredatorSense").font(.headline)
                Text("Triton 500 · " + (model.state.controlPath == "wmi"
                                        ? "Acer WMI" : "EC direct"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.connected && model.state.cpuTempC >= 0 {
                Text("\(model.state.cpuTempC)°C")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(model.state.cpuTempC >= 88 ? .red
                                     : model.state.cpuTempC >= 78 ? .orange : .primary)
            }
        }
    }

    private var disconnected: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Daemon not reachable", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout.weight(.medium))
            Text(model.lastError ?? "predatorsensed is not running.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var banner: some View {
        Label(model.state.thermalTripped
              ? "CPU hit 88°C — fans returned to the EC."
              : "Control daemon went quiet — fans returned to the EC.",
              systemImage: "shield.fill")
            .font(.caption).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var fans: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FANS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { model.state.fanMode },
                set: { model.setFanMode($0) })) {
                Text("Auto").tag("auto")
                Text("Manual").tag("manual")
            }
            .pickerStyle(.segmented).labelsHidden()

            let manual = model.state.fanMode == "manual"
            slider("CPU", $model.fan1Slider, manual)
            slider("GPU", $model.fan2Slider, manual)

            if manual {
                Text("Minimum 35% of each fan's own maximum (CPU 102, GPU 78 raw).")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func slider(_ label: String, _ v: Binding<Double>, _ on: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.callout).frame(width: 32, alignment: .leading)
            Slider(value: v, in: 35...100, step: 1) { editing in
                if !editing { model.commitDuty() }
            }
            .disabled(!on)
            Text("\(Int(v.wrappedValue))%")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 38, alignment: .trailing)
                .foregroundStyle(on ? .primary : .secondary)
        }
    }

    private var power: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CPU POWER").font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { model.state.powerProfile },
                set: { model.setPowerProfile($0) })) {
                Text("Low").tag("low")
                Text("Balanced").tag("balanced")
                Text("Performance").tag("performance")
            }
            .pickerStyle(.segmented).labelsHidden()
            .disabled(model.state.powerLocked)

            if model.state.powerLocked {
                Text("Firmware has locked the package power MSR until the next "
                     + "reset — profiles can't be applied this boot.")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.state.pl1mW > 0 {
                Text("PL1 \(model.state.pl1mW / 1000) W · PL2 \(model.state.pl2mW / 1000) W")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Toggle("Turbo", isOn: Binding(
                get: { model.state.turbo },
                set: { model.setTurbo($0) }))
                .toggleStyle(.switch).font(.callout)
                .disabled(!model.state.wmiPresent)
        }
    }

    private var display: some View {
        Toggle("LCD Overdrive", isOn: Binding(
            get: { model.state.lcdOverdrive },
            set: { model.setLcdOverdrive($0) }))
            .toggleStyle(.switch).font(.callout)
            .disabled(!model.state.wmiPresent)
    }

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("KEYBOARD").font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            labelled("Bright", Binding(get: { model.kbBright }, set: { model.kbBright = $0; model.holdKb() }), 0...100) { model.setKbBrightness() }
            Text("0% turns the backlight off.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("Sleep").font(.caption).frame(width: 42, alignment: .leading)
                Picker("", selection: Binding(
                    get: { model.state.kbTimeoutSec },
                    set: { model.setKbTimeout($0) })) {
                    Text("Off").tag(0)
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("1m").tag(60)
                    Text("5m").tag(300)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            Text("Backlight turns off when idle and comes back on any key or "
                 + "trackpad touch. The keyboard firmware also has its own idle "
                 + "timeout that \"Off\" here cannot disable.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Two rows of three: six modes in one segmented control was
            // squeezing the labels to ellipses at this width.
            Picker("", selection: Binding(
                get: { model.state.kbModeName },
                set: { model.setKbMode($0) })) {
                Text("Static").tag("static")
                Text("Breath").tag("breath")
                Text("Neon").tag("neon")
            }
            .pickerStyle(.segmented).labelsHidden()
            Picker("", selection: Binding(
                get: { model.state.kbModeName },
                set: { model.setKbMode($0) })) {
                Text("Wave").tag("wave")
                Text("Shifting").tag("shifting")
                Text("Zoom").tag("zoom")
            }
            .pickerStyle(.segmented).labelsHidden()

            let mode = model.state.kbModeName
            if mode != "static" {
                labelled("Speed", $model.kbSpeed, 0...9) { model.setKbSpeed() }
            }
            if mode == "wave" || mode == "shifting" {
                Button { model.toggleKbDirection() } label: {
                    Label(model.state.kbDirection == 1 ? "Right to left"
                                                       : "Left to right",
                          systemImage: model.state.kbDirection == 1
                                       ? "arrow.left" : "arrow.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }

            if mode == "static" {
                Picker("", selection: $model.selectedZone) {
                    Text("All").tag(0)
                    Text("Left").tag(1)
                    Text("Middle").tag(2)
                    Text("Right").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 4) {
                    ForEach(0..<PSECModel.zoneCount, id: \.self) { z in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(model.zoneColors[z])
                            .frame(height: 6)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .stroke(.secondary.opacity(0.35)))
                    }
                }
            }

            if mode == "neon" || mode == "wave" {
                Text("This mode generates its own colours.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5),
                                         count: 8), spacing: 5) {
                    ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, c in
                        Button { model.setRgb(c, zoneMask: swatchMask) } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(c).frame(height: 20)
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .stroke(.secondary.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    Button("More colours…") { model.openColourPanel() }
                        .buttonStyle(.bordered).controlSize(.small)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: model.red/255, green: model.green/255,
                                    blue: model.blue/255))
                        .frame(width: 34, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(.secondary.opacity(0.4)))
                    Text(String(format: "#%02X%02X%02X", Int(model.red),
                                Int(model.green), Int(model.blue)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .disabled(!model.state.wmiPresent)
    }

    private var swatchMask: Int {
        model.selectedZone == 0 ? PSECModel.allZones
                                : 1 << (model.selectedZone - 1)
    }

    private func labelled(_ title: String, _ v: Binding<Double>,
                          _ range: ClosedRange<Double>,
                          _ commit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 42, alignment: .leading)
            Slider(value: v, in: range, step: 1) { editing in
                if !editing { commit() }
            }
            Text("\(Int(v.wrappedValue))")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private static let presets: [Color] = [
        .red, .orange, .yellow, .green, .mint, .cyan, .blue, .indigo,
        .purple, .pink, .white, Color(red: 1.0, green: 0.35, blue: 0.0),
        Color(red: 0.0, green: 1.0, blue: 0.5), Color(red: 0.6, green: 0.0, blue: 1.0),
        Color(red: 1.0, green: 0.0, blue: 0.4), Color(red: 0.5, green: 0.5, blue: 0.5)
    ]

    private var readouts: some View {
        VStack(alignment: .leading, spacing: 4) {
            let wmi = model.state.controlPath == "wmi"
            row("CPU fan", "\(model.state.fan1RPM) RPM",
                model.state.fan1RawDuty > 0
                ? (wmi ? "\(model.state.fan1RawDuty)%" : "duty \(model.state.fan1RawDuty)/102")
                : "")
            row("GPU fan", "\(model.state.fan2RPM) RPM",
                model.state.fan2RawDuty > 0
                ? (wmi ? "\(model.state.fan2RawDuty)%" : "duty \(model.state.fan2RawDuty)/78")
                : "")
            row("GPU temp", model.state.gpuTempC >= 0 ? "\(model.state.gpuTempC)°C" : "n/a", "")
            row("EC state", model.state.hwFanMode, "")
        }
    }

    private func row(_ k: String, _ v: String, _ extra: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.system(.caption, design: .monospaced))
            if !extra.isEmpty {
                Text(extra).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
