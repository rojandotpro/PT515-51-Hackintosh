//
//  main.swift — predatorsensed
//
//  Root daemon. Owns the single connection to PredatorSenseEC.kext and speaks a
//  line protocol on a UNIX socket so the menu bar app can stay unprivileged.
//
//  Socket: /var/run/predatorsense.sock  (root:admin, 0660)
//
//  Commands:  status | fanmode auto|manual | duty <fan1Pct> <fan2Pct>
//

import Foundation
import IOKit          // IOHIDSystem, for the backlight idle timer

let kSocketPath = "/var/run/predatorsense.sock"
let kAdminGID: gid_t = 80
let kKbModeNames = ["static", "breath", "neon", "wave", "shifting", "zoom"]
let kStateDir  = "/Library/Application Support/PredatorSense"
let kStatePath = kStateDir + "/state.json"
// Measured on this panel 2026-09-16: the backlight is dark below 25, so 25 is
// the real floor, not the 10 previously assumed.
let kKbMinimumVisibleBrightness = 25

// Everything the user can choose, so a reboot lands where they left off.
struct Settings: Codable {
    var fanMode = "auto"
    var fan1 = 60, fan2 = 60
    var powerProfile = "balanced"
    var lcdOverdrive = false
    var turbo = false
    var kbMode = "static"
    var kbSpeed = 5, kbBrightness = 100, kbDirection = 2
    var kbColor = [255, 0, 0]
    var zoneColors = [[255,0,0],[255,0,0],[255,0,0]]
    /// Firmware zone index for [left, middle, right]. Measured on this machine:
    /// index 1 = left, 2 = middle, 4 = right — index 3 is not wired at all.
    /// Correct with `zonemap` if a physical zone doesn't respond; no rebuild.
    var zoneMap = [1, 2, 4]
    /// Seconds of no keyboard/trackpad activity before the backlight dims.
    /// 0 disables it. PredatorSense on Windows offers 30 s; same default here.
    var kbTimeoutSec = 30
}
// Synthesized Decodable fails on ANY missing key (defaults are not used), which
// silently reset every setting whenever a field was added. Decode field by field.
extension Settings {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ cur: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: k)).flatMap { $0 } ?? cur
        }
        fanMode = get(.fanMode, fanMode);  fan1 = get(.fan1, fan1);  fan2 = get(.fan2, fan2)
        powerProfile = get(.powerProfile, powerProfile)
        lcdOverdrive = get(.lcdOverdrive, lcdOverdrive);  turbo = get(.turbo, turbo)
        kbMode = get(.kbMode, kbMode);  kbSpeed = get(.kbSpeed, kbSpeed)
        kbBrightness = get(.kbBrightness, kbBrightness);  kbDirection = get(.kbDirection, kbDirection)
        kbColor = get(.kbColor, kbColor);  zoneColors = get(.zoneColors, zoneColors)
        zoneMap = get(.zoneMap, zoneMap);  kbTimeoutSec = get(.kbTimeoutSec, kbTimeoutSec)
        // Never trust persisted numbers to be in range: a negative value used
        // to crash the daemon on every launch.
        fan1 = min(max(fan1, 0), 100);  fan2 = min(max(fan2, 0), 100)
        kbSpeed = min(max(kbSpeed, 0), 9);  kbDirection = min(max(kbDirection, 0), 255)
        kbBrightness = min(max(kbBrightness, 0), 100);  kbTimeoutSec = max(kbTimeoutSec, 0)
        kbColor = kbColor.count == 3 ? kbColor.map { min(max($0, 0), 255) } : [255, 0, 0]
        zoneColors = zoneColors.map { $0.count == 3 ? $0.map { min(max($0, 0), 255) } : [255, 0, 0] }
    }
}
var settings = Settings()

// --- keyboard backlight auto-dim -------------------------------------------
//
// Idle time comes from IOHIDSystem's HIDIdleTime property: nanoseconds since the
// last HID event, maintained by the kernel. That means no event tap, no
// Accessibility permission, nothing that reads what you actually type — and it
// works from a root LaunchDaemon, which a CGEventSource query would not.
var kbDimmed = false

func hidIdleSeconds() -> Double {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault,
              IOServiceMatching("IOHIDSystem"), &it) == KERN_SUCCESS else { return 0 }
    defer { IOObjectRelease(it) }
    let entry = IOIteratorNext(it)
    guard entry != 0 else { return 0 }
    defer { IOObjectRelease(entry) }

    var propsRef: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &propsRef,
              kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let props = propsRef?.takeRetainedValue() as? [String: Any],
          let n = props["HIDIdleTime"] as? NSNumber else { return 0 }
    return n.doubleValue / 1_000_000_000.0
}

/// Push a brightness to the hardware WITHOUT touching the saved setting, so an
/// auto-dim never overwrites the brightness the user chose.
func applyBrightness(_ value: Int) {
    let mode = kKbModeNames.firstIndex(of: settings.kbMode) ?? 0
    try? bridge.setKbEffect(mode: mode, speed: settings.kbSpeed,
                            brightness: value, direction: settings.kbDirection,
                            r: settings.kbColor[0], g: settings.kbColor[1],
                            b: settings.kbColor[2])
}

// The EC blanks the keyboard backlight on its own idle timer, and only its own
// key matrix wakes it — trackpad input does not, and the OS never sees either
// event. Confirmed 2026-09-17: kbTimeoutSec 0 / kbDimmed false with the light
// off. We therefore re-assert brightness, but sparingly: applyBrightness()
// rewrites the whole effect descriptor, which restarts the animation, so doing
// it on a short fixed period makes every mode visibly stutter.
//
// Rules:
//   * While you are actively using the machine (idle < grace) never write —
//     the EC has not blanked anything yet, so there is nothing to undo.
//   * Past the grace period, re-assert on a slow cadence so an EC blank is
//     reversed without a keypress.
//   * The moment input returns, assert once immediately so the light is there
//     when you touch the trackpad.
let kKbActiveGraceSec = 15.0
let kKbReassertSec    = 15.0
var kbLastAssert = Date.distantPast
var kbWasIdle    = false

func kbIdleTick() {
    let idle = hidIdleSeconds()
    let noTimeout = settings.kbTimeoutSec <= 0
    let shouldBeLit = noTimeout || idle < Double(settings.kbTimeoutSec)

    guard shouldBeLit else {
        if !kbDimmed && settings.kbBrightness > 0 {
            applyBrightness(0)
            kbDimmed = true
        }
        kbWasIdle = true
        return
    }

    if kbDimmed {
        applyBrightness(settings.kbBrightness)
        kbDimmed = false
        kbLastAssert = Date()
        kbWasIdle = false
        return
    }

    let active = idle < kKbActiveGraceSec
    if active {
        // Coming back from idle: one write, so the keyboard is lit the instant
        // you touch it even though the EC only listens to its own keys.
        if kbWasIdle {
            applyBrightness(settings.kbBrightness)
            kbLastAssert = Date()
        }
        kbWasIdle = false
        return                      // active use: stay silent, no stutter
    }

    kbWasIdle = true
    // Never re-assert over an explicit "off" (0 %).
    if settings.kbBrightness > 0 && Date().timeIntervalSince(kbLastAssert) >= kKbReassertSec {
        applyBrightness(settings.kbBrightness)
        kbLastAssert = Date()
    }
}

// Hardware: 0 = off, 25...100 visible. UI: 0...100 %. 0 % is a real "off";
// 1...100 % spreads over the visible 25...100 range.
func kbPctToHw(_ p: Int) -> Int {
    let q = max(0, min(100, p))
    return q == 0 ? 0 : 24 + Int((0.76 * Double(q)).rounded())
}
func kbHwToPct(_ hw: Int) -> Int {
    if hw < kKbMinimumVisibleBrightness { return 0 }
    return max(1, min(100, Int((Double(hw - 24) / 0.76).rounded())))
}

func loadSettings() {
    guard let d = FileManager.default.contents(atPath: kStatePath),
          let s = try? JSONDecoder().decode(Settings.self, from: d) else { return }
    settings = s
    // The firmware interprets values below 10 as off. Keep 0 exclusively for
    // the temporary idle dim, never as a persisted user brightness.
    if settings.kbBrightness != 0 && settings.kbBrightness < kKbMinimumVisibleBrightness {
        settings.kbBrightness = kKbMinimumVisibleBrightness
    }
    logLine("loaded saved settings")
}

func saveSettings() {
    do {
        try FileManager.default.createDirectory(atPath: kStateDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755])
        let e = JSONEncoder(); e.outputFormatting = .prettyPrinted
        try e.encode(settings).write(to: URL(fileURLWithPath: kStatePath),
                                     options: .atomic)
    } catch { logLine("could not save settings: \(error)") }
}

// A client hanging up mid-reply would otherwise raise SIGPIPE and kill us.
signal(SIGPIPE, SIG_IGN)
// bind() honours the umask, so tighten it BEFORE creating the socket.
umask(0o177)

func logLine(_ s: String) {
    FileHandle.standardError.write("predatorsensed: \(s)\n".data(using: .utf8)!)
}

// The kext defers its own EC lookup for 20s after load, and launchd starts us
// well before that. Retry rather than exiting — crash-looping under launchd
// just moves the wait somewhere less visible.
func connectWithRetry() -> PSECBridge {
    var attempt = 0
    while true {
        do { return try PSECBridge() }
        catch {
            attempt += 1
            if attempt == 1 || attempt % 10 == 0 {
                logLine("waiting for PredatorSenseEC (\(error)) — attempt \(attempt)")
            }
            if attempt >= 120 { logLine("fatal: kext never appeared"); exit(1) }
            usleep(1_000_000)
        }
    }
}
let bridge = connectWithRetry()
logLine("connected to PredatorSenseEC")
loadSettings()

let stateQueue = DispatchQueue(label: "predatorsense.state")

func json(_ d: [String: Any]) -> String {
    guard let j = try? JSONSerialization.data(withJSONObject: d),
          let s = String(data: j, encoding: .utf8) else { return "{\"ok\":false}" }
    return s
}
func ok(_ e: [String: Any] = [:]) -> String {
    var d: [String: Any] = ["ok": true]; d.merge(e) { a, _ in a }; return json(d)
}
func err(_ m: String) -> String { json(["ok": false, "error": m]) }

func statusDict() throws -> [String: Any] {
    let s = try bridge.status()
    return [
        "fanMode":        s.fanMode == 1 ? "manual" : "auto",
        "hwFanMode":      s.hwFanMode == 1 ? "manual" : "auto",
        "fan1Percent":    Int(s.fan1Percent),
        "fan2Percent":    Int(s.fan2Percent),
        "fan1RawDuty":    Int(s.fan1RawDuty),
        "fan2RawDuty":    Int(s.fan2RawDuty),
        "fan1RPM":        Int(s.fan1RPM),
        "fan2RPM":        Int(s.fan2RPM),
        "cpuTempC":       Int(s.cpuTempC),
        "gpuTempC":       Int(s.gpuTempC),
        "thermalTripped": s.thermalTripped != 0,
        "watchdogTripped":s.watchdogTripped != 0,
        "ecPresent":      s.ecPresent != 0,
        "wmiPresent":     s.wmiPresent != 0,
        "controlPath":    s.wmiPresent != 0 ? "wmi" : "ec",
        "turbo":          s.turboOn != 0,
        "lcdOverdrive":   s.lcdOverdriveOn != 0,
        "powerProfile":   ["low", "balanced", "performance"][
                              Int(min(s.powerProfile, 2))],
        "pl1mW":          Int(s.pl1Milliwatts),
        "pl2mW":          Int(s.pl2Milliwatts),
        "powerLocked":    s.powerLimitsLocked != 0,
        "lastWMIStatus":  String(format: "0x%016llX", s.lastWMIStatus),
        "kbMode":         Int(s.kbMode),
        "kbModeName":     kKbModeNames[Int(min(s.kbMode, 5))],
        "kbSpeed":        Int(s.kbSpeed),
        "kbBrightness":   Int(s.kbBrightness),
        "kbPercent":      kbHwToPct(kbDimmed ? settings.kbBrightness : Int(s.kbBrightness)),
        "kbDirection":    Int(s.kbDirection),
        "kbColor":        [Int(s.kbRed), Int(s.kbGreen), Int(s.kbBlue)],
        "kbTimeoutSec":   settings.kbTimeoutSec,
        "kbDimmed":       kbDimmed,
        "zoneMap":        settings.zoneMap,
        "rgbStatus":      ["kbBacklight20": String(format: "0x%08X", s.rgbStatusKB),
                           "ledColor12":    String(format: "0x%08X", s.rgbStatusLED),
                           "rgbKb6":        String(format: "0x%08X", s.rgbStatusRgbKb)],
    ]
}

func boolArg(_ s: String) -> Bool? {
    switch s.lowercased() {
    case "on", "1", "true", "yes":  return true
    case "off", "0", "false", "no": return false
    default: return nil
    }
}

// Re-apply the saved state. Ordering matters: zone colours before the mode, or
// a static restore paints the zones and then the mode call overwrites them.
func restoreSettings() {
    logLine("restoring saved settings")
    for (i, c) in settings.zoneColors.enumerated() where c.count == 3 {
        let fw = settings.zoneMap.indices.contains(i) ? settings.zoneMap[i] : i + 1
        try? bridge.setRgb(zones: 1 << (fw - 1), r: c[0], g: c[1], b: c[2])
    }
    let mode = kKbModeNames.firstIndex(of: settings.kbMode) ?? 0
    try? bridge.setKbEffect(mode: mode, speed: settings.kbSpeed,
                            brightness: settings.kbBrightness,
                            direction: settings.kbDirection,
                            r: settings.kbColor[0], g: settings.kbColor[1],
                            b: settings.kbColor[2])
    let prof = ["low": 0, "balanced": 1, "performance": 2][settings.powerProfile] ?? 1
    try? bridge.setPowerProfile(prof)
    if settings.lcdOverdrive { try? bridge.setLcdOverdrive(true) }
    if settings.turbo        { try? bridge.setTurbo(true) }
    if settings.fanMode == "manual" {
        try? bridge.setDuty(fan1: settings.fan1, fan2: settings.fan2)
        try? bridge.setFanMode(.manual)
    }
}

func captureSettings() {
    guard let st = try? bridge.status() else { return }
    settings.fanMode      = st.fanMode == 1 ? "manual" : "auto"
    settings.fan1         = Int(st.fan1Percent)
    settings.fan2         = Int(st.fan2Percent)
    settings.powerProfile = ["low","balanced","performance"][Int(min(st.powerProfile,2))]
    settings.lcdOverdrive = st.lcdOverdriveOn != 0
    settings.turbo        = st.turboOn != 0
    settings.kbMode       = kKbModeNames[Int(min(st.kbMode, 5))]
    settings.kbSpeed      = Int(st.kbSpeed)
    if !kbDimmed { settings.kbBrightness = Int(st.kbBrightness) }
    settings.kbDirection  = Int(st.kbDirection)
    settings.kbColor      = [Int(st.kbRed), Int(st.kbGreen), Int(st.kbBlue)]
    saveSettings()
}

let kMutating: Set<String> = ["fanmode","duty","turbo","lcdod","rgb","power",
                              "kbmode","kbbright","kbpct"]

func handle(_ line: String) -> String {
    let p = line.split(separator: " ").map(String.init)
    guard let cmd = p.first?.lowercased() else { return err("empty") }
    // Any explicit command means someone is at the machine, so drop the dim
    // before acting — otherwise a brightness change would be applied and then
    // immediately overwritten by the dim state.
    if kbDimmed && ["kbmode", "kbbright", "kbpct", "rgb", "kbtimeout"].contains(cmd) {
        // Restore the real brightness FIRST. Otherwise the kext still holds 0,
        // forces 100 for the new effect, and captureSettings saves that 100.
        applyBrightness(settings.kbBrightness)
        kbDimmed = false
        kbLastAssert = Date()
    }
    defer { if kMutating.contains(cmd) { captureSettings() } }
    do {
        switch cmd {
        case "status":
            return ok(try statusDict())
        case "fanmode":
            guard p.count >= 2 else { return err("usage: fanmode auto|manual") }
            switch p[1].lowercased() {
            case "auto":   try bridge.setFanMode(.auto)
            case "manual": try bridge.setFanMode(.manual)
            default: return err("unknown mode \(p[1])")
            }
            return ok(try statusDict())
        case "duty":
            guard p.count >= 3, let a = Int(p[1]), let b = Int(p[2]) else {
                return err("usage: duty <fan1Pct> <fan2Pct>")
            }
            try bridge.setDuty(fan1: a, fan2: b)
            return ok(try statusDict())
        case "ecread":
            guard p.count >= 2, let off = Int(p[1].replacingOccurrences(of: "0x", with: ""),
                                              radix: 16) else {
                return err("usage: ecread <hexOffset>   e.g. ecread 96")
            }
            let v = try bridge.ecRead(off)
            return ok(["offset": String(format: "0x%02X", off),
                       "value": v, "hex": String(format: "0x%02X", v)])

        case "ecwrite":
            guard p.count >= 3,
                  let off = Int(p[1].replacingOccurrences(of: "0x", with: ""), radix: 16),
                  let val = Int(p[2].replacingOccurrences(of: "0x", with: ""), radix: 16) else {
                return err("usage: ecwrite <hexOffset> <hexValue>   e.g. ecwrite 9B 4A")
            }
            try bridge.ecWrite(off, val)
            return ok(["wrote": String(format: "0x%02X = 0x%02X", off, val)])

        case "ecdump":
            var out: [String: Any] = [:]
            for off in 0x93...0x9C {
                if let v = try? bridge.ecRead(off) {
                    out[String(format: "0x%02X", off)] = String(format: "0x%02X", v)
                }
            }
            return ok(["dump": out])

        case "turbo":
            guard p.count >= 2, let on = boolArg(p[1]) else {
                return err("usage: turbo on|off")
            }
            try bridge.setTurbo(on)
            return ok(try statusDict())

        case "lcdod":
            guard p.count >= 2, let on = boolArg(p[1]) else {
                return err("usage: lcdod on|off")
            }
            try bridge.setLcdOverdrive(on)
            return ok(try statusDict())

        case "rgb":
            // rgb <r> <g> <b> [zoneMask 1-7]   — zones 1,2,4,8; 15 = all four
            guard p.count >= 4, let r = Int(p[1]), let g = Int(p[2]),
                  let b = Int(p[3]) else {
                return err("usage: rgb <r> <g> <b> [zoneMask 1-7]")
            }
            let zones = p.count >= 5 ? (Int(p[4]) ?? 7) : 7      // 3 zones -> 0b111
            guard (1...7).contains(zones),
                  (0...255).contains(r), (0...255).contains(g),
                  (0...255).contains(b) else {
                return err("rgb components 0-255, zoneMask 1-7 (3 zones)")
            }
            // `zones` is a LOGICAL mask: bit0 = left, bit1 = middle, bit2 = right.
            // Translate through the map to firmware indices, one call each.
            for z in 0..<3 where zones & (1 << z) != 0 {
                let fw = settings.zoneMap.indices.contains(z) ? settings.zoneMap[z] : z + 1
                try bridge.setRgb(zones: 1 << (fw - 1), r: r, g: g, b: b)
                settings.zoneColors[z] = [r, g, b]
            }
            // Include the per-candidate statuses: whichever method the chassis
            // actually implements is the one that made the light change.
            var d = try statusDict()
            d["rgbSent"] = ["zones": zones, "r": r, "g": g, "b": b]
            return ok(d)

        case "kbmode":
            // kbmode <name|0-5> [speed 0-9] [brightness 0-100] [dir 1|2] [r g b]
            guard p.count >= 2 else {
                return err("usage: kbmode " + kKbModeNames.joined(separator: "|")
                           + " [speed] [brightness] [dir] [r g b]")
            }
            let cur = try bridge.status()
            let mode: Int
            if let i = Int(p[1]), (0...5).contains(i) { mode = i }
            else if let i = kKbModeNames.firstIndex(of: p[1].lowercased()) { mode = i }
            else { return err("unknown mode \(p[1])") }
            let speed = p.count >= 3 ? (Int(p[2]) ?? Int(cur.kbSpeed)) : Int(cur.kbSpeed)
            let bri   = p.count >= 4 ? (Int(p[3]) ?? Int(cur.kbBrightness))
                                     : Int(cur.kbBrightness)
            let dir   = p.count >= 5 ? (Int(p[4]) ?? Int(cur.kbDirection))
                                     : Int(cur.kbDirection)
            let rr    = p.count >= 8 ? (Int(p[5]) ?? Int(cur.kbRed))   : Int(cur.kbRed)
            let gg    = p.count >= 8 ? (Int(p[6]) ?? Int(cur.kbGreen)) : Int(cur.kbGreen)
            let bb    = p.count >= 8 ? (Int(p[7]) ?? Int(cur.kbBlue))  : Int(cur.kbBlue)
            try bridge.setKbEffect(mode: mode, speed: speed, brightness: bri,
                                   direction: dir == 1 ? 1 : 2, r: rr, g: gg, b: bb)
            return ok(try statusDict())

        case "kbtimeout":
            // kbtimeout <seconds>|off   — 0/off disables the auto-dim
            guard p.count >= 2 else { return err("usage: kbtimeout <seconds>|off") }
            let v = p[1].lowercased() == "off" ? 0 : (Int(p[1]) ?? -1)
            guard (0...3600).contains(v) else {
                return err("usage: kbtimeout <0-3600 seconds>|off")
            }
            settings.kbTimeoutSec = v
            saveSettings()
            if kbDimmed { applyBrightness(settings.kbBrightness); kbDimmed = false }
            return ok(try statusDict())

        case "kbpct":
            guard p.count >= 2, let v = Int(p[1]), (0...100).contains(v) else {
                return err("usage: kbpct <0-100>")
            }
            return handle("kbbright \(kbPctToHw(v))")

        case "kbbright":
            guard p.count >= 2, let v = Int(p[1]),
                  v == 0 || (kKbMinimumVisibleBrightness...100).contains(v) else {
                return err("usage: kbbright <0|25-100>; use kbpct for 0-100%")
            }
            let c = try bridge.status()
            try bridge.setKbEffect(mode: Int(c.kbMode), speed: Int(c.kbSpeed),
                                   brightness: v, direction: Int(c.kbDirection),
                                   r: Int(c.kbRed), g: Int(c.kbGreen), b: Int(c.kbBlue))
            return ok(try statusDict())

        case "zonemap":
            // zonemap <left> <middle> <right>   firmware zone index 1-4 each
            guard p.count >= 4,
                  let a = Int(p[1]), let b = Int(p[2]), let c = Int(p[3]),
                  [a,b,c].allSatisfy({ (1...4).contains($0) }) else {
                return err("usage: zonemap <left> <middle> <right>   (each 1-4)")
            }
            settings.zoneMap = [a, b, c]
            saveSettings()
            return ok(["zoneMap": settings.zoneMap])

        case "kbget":
            // The 16-byte descriptor the firmware is currently holding.
            let zone = p.count >= 2 ? (UInt8(p[1], radix: 16) ?? 1) : 1
            let (st, out) = try bridge.rawWMI(21, [zone, 0, 0, 0])
            return ok(["status": String(format: "0x%08X", UInt32(bitPattern: Int32(st))),
                       "descriptor": out.map { String(format: "%02X", $0) }
                                        .joined(separator: " "),
                       "len": out.count])

        case "kbraw":
            // Write an exact 16-byte descriptor. This is how we pin down the
            // colour byte offsets without another build.
            var bytes = [UInt8]()
            for tok in p.dropFirst() {
                guard let v = UInt8(tok.replacingOccurrences(of: "0x", with: ""),
                                    radix: 16) else { return err("bad hex '\(tok)'") }
                bytes.append(v)
            }
            guard !bytes.isEmpty, bytes.count <= 16 else {
                return err("usage: kbraw <up to 16 hex bytes>")
            }
            if bytes.count < 16 { bytes += [UInt8](repeating: 0,
                                                   count: 16 - bytes.count) }
            let (st2, out2) = try bridge.rawWMI(20, bytes)
            return ok(["sent": bytes.map { String(format: "%02X", $0) }
                                    .joined(separator: " "),
                       "status": String(format: "0x%08X", UInt32(bitPattern: Int32(st2))),
                       "out": out2.map { String(format: "%02X", $0) }
                                  .joined(separator: " ")])

        case "power":
            guard p.count >= 2 else {
                return err("usage: power low|balanced|performance")
            }
            let map = ["low": 0, "balanced": 1, "performance": 2]
            guard let v = map[p[1].lowercased()] else {
                return err("unknown profile \(p[1])")
            }
            try bridge.setPowerProfile(v)
            return ok(try statusDict())

        case "wmi":
            // Raw WMBH probe. Byte COUNT is the argument width and the firmware
            // cares: uint32 methods want 4 bytes, uint64 8, the keyboard 16.
            //   wmi <methodId> <b0> <b1> ...      (hex bytes, little-endian)
            //   wmi 23 01                         -> padded to 4  (GetMisc)
            //   wmi 22 01 01                      -> padded to 8  (SetMisc)
            guard p.count >= 3, let mid = Int(p[1]) else {
                return err("usage: wmi <methodId> <hexByte>...")
            }
            var bytes = [UInt8]()
            for tok in p[2...] {
                guard let v = UInt8(tok.replacingOccurrences(of: "0x", with: ""),
                                    radix: 16) else {
                    return err("bad hex byte '\(tok)'")
                }
                bytes.append(v)
            }
            // Pad to the declared width for this method rather than silently
            // sending a short buffer.
            let width: Int
            switch mid {
            case 20:                      width = 16
            case 1, 2, 8, 10, 12, 14, 16, 18, 22: width = 8
            default:                      width = 4
            }
            if bytes.count < width { bytes += [UInt8](repeating: 0,
                                                      count: width - bytes.count) }
            let (st, out) = try bridge.rawWMI(mid, bytes)
            return ok(["method": mid,
                       "sent": bytes.map { String(format: "%02X", $0) }.joined(separator: " "),
                       "status": String(format: "0x%08X", UInt32(bitPattern: Int32(st))),
                       "out": out.map { String(format: "%02X", $0) }.joined(separator: " "),
                       "outLen": out.count])

        default:
            return err("unknown command \(cmd)")
        }
    } catch { return err("\(error)") }
}

// Watchdog keepalive. Deliberately proves health with a real round trip first —
// a daemon that is alive but wedged must NOT keep the fans held manually.
var pingFailures = 0
let pingTimer = DispatchSource.makeTimerSource(queue: stateQueue)
pingTimer.schedule(deadline: .now() + 1.0, repeating: 2.0)
pingTimer.setEventHandler {
    do {
        _ = try bridge.status()
        try bridge.ping()
        pingFailures = 0
    } catch {
        pingFailures += 1
        if pingFailures == 3 {
            logLine("bridge unhealthy (\(error)) — withholding keepalive; "
                    + "the kext will return the fans to the EC")
        }
    }
}
pingTimer.resume()

// Backlight idle watcher. Half a second so the light comes back the moment you
// touch the trackpad, rather than up to two seconds later.
let kbTimer = DispatchSource.makeTimerSource(queue: stateQueue)
kbTimer.schedule(deadline: .now() + 2.0, repeating: 0.5)
kbTimer.setEventHandler { kbIdleTick() }
kbTimer.resume()

// --- socket ---------------------------------------------------------------

unlink(kSocketPath)
let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
guard listenFD >= 0 else { logLine("fatal: socket()"); exit(1) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
withUnsafeMutableBytes(of: &addr.sun_path) { raw in
    let b = Array(kSocketPath.utf8)
    precondition(b.count < raw.count)
    raw.copyBytes(from: b)
    raw[b.count] = 0
}
let bound = withUnsafePointer(to: &addr) { p -> Int32 in
    p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bound == 0 else { logLine("fatal: bind() \(errno)"); exit(1) }
chown(kSocketPath, 0, kAdminGID)
chmod(kSocketPath, 0o660)
guard listen(listenFD, 8) == 0 else { logLine("fatal: listen()"); exit(1) }
logLine("listening on \(kSocketPath)")

// Restore only now that we can answer. Running it before listen() made the
// daemon silently unreachable during boot — a command sent in that window
// connected to nobody and returned an empty reply.
stateQueue.async {
    restoreSettings()
    logLine("settings restored")
}

// Leave the hardware in a known state on the way out.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        logLine("shutting down — returning fans to the EC")
        try? bridge.setFanMode(.auto)
        unlink(kSocketPath)
        exit(0)
    }
    src.resume()
    signalSources.append(src)
}

func serve(_ fd: Int32) {
    defer { close(fd) }
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

    var buf = [UInt8](repeating: 0, count: 4096)
    var pending = ""
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { return }
        pending += String(decoding: buf[0..<n], as: UTF8.self)
        while let i = pending.firstIndex(of: "\n") {
            let line = String(pending[pending.startIndex..<i])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            pending = String(pending[pending.index(after: i)...])
            if line.isEmpty { continue }
            let reply = stateQueue.sync { handle(line) } + "\n"
            _ = reply.withCString { write(fd, $0, strlen($0)) }
        }
        if pending.utf8.count > 64 * 1024 { return }
    }
}

DispatchQueue(label: "predatorsense.accept").async {
    while true {
        let fd = accept(listenFD, nil, nil)
        if fd < 0 { if errno == EINTR { continue }; usleep(100_000); continue }
        DispatchQueue.global().async { serve(fd) }
    }
}

dispatchMain()
