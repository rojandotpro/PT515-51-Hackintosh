//
//  PSECClient.swift — talks to predatorsensed over its UNIX socket.
//  No IOKit here; the GUI stays unprivileged.
//

import Foundation
import Combine      // ObservableObject / @Published live here, not Foundation
import SwiftUI      // Color, for the RGB picker
import AppKit       // NSColor, to get sRGB components out of a Color

struct PSECState: Equatable {
    var fanMode = "auto"
    var hwFanMode = "auto"
    var fan1Percent = 60
    var fan2Percent = 60
    var fan1RPM = 0
    var fan2RPM = 0
    var fan1RawDuty = 0
    var fan2RawDuty = 0
    var cpuTempC = -1
    var gpuTempC = -1
    var thermalTripped = false
    var watchdogTripped = false
    var ecPresent = false
    var wmiPresent = false
    var controlPath = "ec"
    var turbo = false
    var lcdOverdrive = false
    var powerProfile = "balanced"
    var pl1mW = 0
    var pl2mW = 0
    var powerLocked = false
    var kbMode = 0
    var kbModeName = "static"
    var kbSpeed = 5
    var kbBrightness = 100
    var kbPercent = 100
    var kbDirection = 2
    var kbColor: [Int] = [255, 0, 0]
    var kbTimeoutSec = 30
    var kbDimmed = false
}

enum PSECClientError: Error, LocalizedError {
    case cannotConnect, daemon(String)
    var errorDescription: String? {
        switch self {
        case .cannotConnect: return "Can't reach predatorsensed. Is the daemon loaded?"
        case .daemon(let m): return m
        }
    }
}

// Stateless — every call opens its own socket — so it is safe to touch from
// any queue. Marked explicitly, because PSECModel is @MainActor and Dispatch
// closures are @Sendable and do NOT inherit that isolation.
final class PSECClient: @unchecked Sendable {
    static let socketPath = "/var/run/predatorsense.sock"

    @discardableResult
    func send(_ command: String) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PSECClientError.cannotConnect }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let b = Array(Self.socketPath.utf8)
            raw.copyBytes(from: b); raw[b.count] = 0
        }
        let rc = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { throw PSECClientError.cannotConnect }

        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        _ = (command + "\n").withCString { write(fd, $0, strlen($0)) }

        var reply = ""
        var buf = [UInt8](repeating: 0, count: 8192)
        while !reply.contains("\n") {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            reply += String(decoding: buf[0..<n], as: UTF8.self)
        }
        guard let line = reply.split(separator: "\n").first,
              let d = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { throw PSECClientError.daemon("Malformed reply") }

        if let okFlag = o["ok"] as? Bool, okFlag == false {
            throw PSECClientError.daemon(o["error"] as? String ?? "unknown error")
        }
        return o
    }

    func state(from d: [String: Any]) -> PSECState {
        var s = PSECState()
        s.fanMode         = d["fanMode"] as? String ?? "auto"
        s.hwFanMode       = d["hwFanMode"] as? String ?? "auto"
        s.fan1Percent     = d["fan1Percent"] as? Int ?? 60
        s.fan2Percent     = d["fan2Percent"] as? Int ?? 60
        s.fan1RPM         = d["fan1RPM"] as? Int ?? 0
        s.fan2RPM         = d["fan2RPM"] as? Int ?? 0
        s.fan1RawDuty     = d["fan1RawDuty"] as? Int ?? 0
        s.fan2RawDuty     = d["fan2RawDuty"] as? Int ?? 0
        s.cpuTempC        = d["cpuTempC"] as? Int ?? -1
        s.gpuTempC        = d["gpuTempC"] as? Int ?? -1
        s.thermalTripped  = d["thermalTripped"] as? Bool ?? false
        s.watchdogTripped = d["watchdogTripped"] as? Bool ?? false
        s.ecPresent       = d["ecPresent"] as? Bool ?? false
        s.wmiPresent      = d["wmiPresent"] as? Bool ?? false
        s.controlPath     = d["controlPath"] as? String ?? "ec"
        s.turbo           = d["turbo"] as? Bool ?? false
        s.lcdOverdrive    = d["lcdOverdrive"] as? Bool ?? false
        s.powerProfile    = d["powerProfile"] as? String ?? "balanced"
        s.pl1mW           = d["pl1mW"] as? Int ?? 0
        s.pl2mW           = d["pl2mW"] as? Int ?? 0
        s.powerLocked     = d["powerLocked"] as? Bool ?? false
        s.kbMode          = d["kbMode"] as? Int ?? 0
        s.kbModeName      = d["kbModeName"] as? String ?? "static"
        s.kbSpeed         = d["kbSpeed"] as? Int ?? 5
        s.kbBrightness    = d["kbBrightness"] as? Int ?? 100
        s.kbPercent       = d["kbPercent"] as? Int ?? 100
        s.kbDirection     = d["kbDirection"] as? Int ?? 2
        s.kbColor         = d["kbColor"] as? [Int] ?? [255, 0, 0]
        s.kbTimeoutSec    = d["kbTimeoutSec"] as? Int ?? 30
        s.kbDimmed        = d["kbDimmed"] as? Bool ?? false
        return s
    }
}

@MainActor
final class PSECModel: ObservableObject {
    @Published var state = PSECState()
    @Published var connected = false
    @Published var lastError: String?
    @Published var fan1Slider: Double = 60
    @Published var fan2Slider: Double = 60
    @Published var rgbColor: Color = .red
    @Published var kbBright: Double = 100
    @Published var kbSpeed: Double = 5
    @Published var zoneColors: [Color] = [.red, .red, .red]   // 3 physical zones
    @Published var selectedZone = 0          // 0 = all zones, 1-3 = one zone
    @Published var red: Double = 255
    @Published var green: Double = 0
    @Published var blue: Double = 0

    /// This keyboard has three physical zones; a 4th write goes nowhere.
    /// nonisolated: these are plain constants, and a @MainActor static cannot
    /// be used as a default argument value — an error under Swift 6.
    nonisolated static let zoneCount = 3
    nonisolated static let allZones = 0x07
    nonisolated static let minimumVisibleKeyboardBrightness = 25

    /// NSColorPanel needs an ObjC target/action, hence a small NSObject shim.
    /// AppKit sends the action on the main thread, so the target is main-actor
    /// isolated too and can read `sender.color` without a concurrency warning.
    @MainActor
    final class ColourTarget: NSObject {
        var onPick: ((NSColor) -> Void)?
        @objc func picked(_ sender: NSColorPanel) { onPick?(sender.color) }
    }
    private let colourTarget = ColourTarget()

    private nonisolated let client = PSECClient()
    private var timer: Timer?
    private var seeded = false
    private var holdKbUntil = Date.distantPast
    /// Slider is 0-100 %; the daemon speaks hardware units (0 = off, 25-100).
    private var kbHw: Int {
        let p = Int(kbBright.rounded())
        return p <= 0 ? 0 : 24 + Int((0.76 * Double(p)).rounded())
    }
    // Socket I/O never on the main thread: the daemon can block on an EC
    // transaction and that would beachball the UI.
    private nonisolated let io = DispatchQueue(label: "predatorsense.io", qos: .utility)

    func start() {
        guard timer == nil else { return }      // onAppear can fire repeatedly
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    func refresh() { dispatch("status") }

    private func dispatch(_ cmd: String) {
        io.async { [weak self] in
            guard let self else { return }
            do {
                let s = self.client.state(from: try self.client.send(cmd))
                Task { @MainActor in
                    // Seed sliders from hardware, but never from a dimmed
                    // keyboard (brightness 0 there is the idle dim, not the
                    // user's value) — wait for a lit reading instead.
                    // Follow the daemon's brightness unless the slider was just used.
                    if Date() > self.holdKbUntil && !s.kbDimmed {
                        self.kbBright = Double(s.kbPercent)
                    }
                    if !self.seeded, !s.kbDimmed {
                        self.fan1Slider = Double(max(s.fan1Percent, 35))
                        self.fan2Slider = Double(max(s.fan2Percent, 35))
                        self.kbSpeed = Double(s.kbSpeed)
                        self.seeded = true
                    }
                    self.state = s; self.connected = true; self.lastError = nil
                }
            } catch {
                Task { @MainActor in
                    self.seeded = false     // re-sync after the daemon comes back
                    self.connected = false
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func setFanMode(_ mode: String) {
        // Push duty BEFORE entering manual, so the fans never pass through a
        // stale value on the way.
        if mode == "manual" { dispatch("duty \(Int(fan1Slider)) \(Int(fan2Slider))") }
        dispatch("fanmode \(mode)")
    }
    func commitDuty() { dispatch("duty \(Int(fan1Slider)) \(Int(fan2Slider))") }

    func setTurbo(_ on: Bool)        { seeded = false; dispatch("turbo \(on ? "on" : "off")") }
    func setLcdOverdrive(_ on: Bool) { dispatch("lcdod \(on ? "on" : "off")") }
    func setPowerProfile(_ p: String) { dispatch("power \(p)") }

    private static func rgb(_ c: Color) -> (Int, Int, Int) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
        return (Int((ns.redComponent   * 255).rounded()),
                Int((ns.greenComponent * 255).rounded()),
                Int((ns.blueComponent  * 255).rounded()))
    }

    // Fire-and-forget commands whose reply is not a status dict.
    private func fire(_ cmd: String) {
        io.async { [weak self] in
            guard let self else { return }
            do { _ = try self.client.send(cmd) }
            catch {
                Task { @MainActor in self.lastError = error.localizedDescription }
            }
            Task { @MainActor in self.refresh() }
        }
    }

    /// zoneMask bit 0 = zone 1 (leftmost) ... bit 3 = zone 4 (rightmost).
    func setRgb(_ c: Color, zoneMask: Int = PSECModel.allZones) {
        let (r, g, b) = Self.rgb(c)
        red = Double(r); green = Double(g); blue = Double(b)
        applyColour(zoneMask: zoneMask)
    }

    /// Push the current r/g/b to whichever zones are selected. In an animated
    /// mode the colour belongs to the effect, not the zones, so it goes there.
    func applyColour(zoneMask: Int? = nil) {
        let r = Int(red), g = Int(green), b = Int(blue)
        if state.kbModeName == "static" {
            let mask = zoneMask ?? (selectedZone == 0 ? Self.allZones
                                                      : 1 << (selectedZone - 1))
            for z in 0..<Self.zoneCount where mask & (1 << z) != 0 {
                zoneColors[z] = Color(red: red/255, green: green/255, blue: blue/255)
            }
            fire("rgb \(r) \(g) \(b) \(mask)")
        } else {
            fire("kbmode \(state.kbModeName) \(Int(kbSpeed)) \(kbHw) "
                 + "\(state.kbDirection) \(r) \(g) \(b)")
        }
    }

    /// The system colour panel. It never appeared from a ColorPicker because a
    /// MenuBarExtra window can't bring it up in an accessory app — activating
    /// the app first is what makes it work.
    func openColourPanel() {
        colourTarget.onPick = { [weak self] c in
            guard let self else { return }
            let ns = c.usingColorSpace(.sRGB) ?? .white
            self.red   = (ns.redComponent   * 255).rounded()
            self.green = (ns.greenComponent * 255).rounded()
            self.blue  = (ns.blueComponent  * 255).rounded()
            self.applyColour()
        }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSColorPanel.shared
        panel.setTarget(colourTarget)
        panel.setAction(#selector(ColourTarget.picked(_:)))
        panel.isContinuous = false
        panel.makeKeyAndOrderFront(nil)
    }

    func setKbMode(_ name: String) {
        fire("kbmode \(name) \(Int(kbSpeed)) \(kbHw) \(state.kbDirection) "
             + "\(Int(red)) \(Int(green)) \(Int(blue))")
    }
    func holdKb() { holdKbUntil = Date().addingTimeInterval(4) }
    func setKbBrightness() {
        holdKbUntil = Date().addingTimeInterval(4)
        fire("kbpct \(Int(kbBright.rounded()))")
    }
    func setKbTimeout(_ sec: Int) { fire("kbtimeout \(sec)") }
    func setKbSpeed()      { setKbMode(state.kbModeName) }
    func toggleKbDirection() {
        let d = state.kbDirection == 1 ? 2 : 1
        fire("kbmode \(state.kbModeName) \(Int(kbSpeed)) \(kbHw) \(d) "
             + "\(Int(red)) \(Int(green)) \(Int(blue))")
    }
}
