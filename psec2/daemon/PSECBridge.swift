//
//  PSECBridge.swift — thin wrapper over the PredatorSenseEC user client.
//  Runs inside predatorsensed (root). The GUI never touches IOKit.
//

import Foundation
import IOKit

// Must match PSECShared.h exactly.
struct PSECStatus {
    var version: UInt32 = 0
    var fanMode: UInt32 = 0
    var hwFanMode: UInt32 = 0
    var fan1Percent: UInt32 = 0
    var fan2Percent: UInt32 = 0
    var fan1RawDuty: UInt32 = 0
    var fan2RawDuty: UInt32 = 0
    var fan1RPM: UInt32 = 0
    var fan2RPM: UInt32 = 0
    var fan1Status: UInt32 = 0
    var fan2Status: UInt32 = 0
    var cpuTempC: Int32 = -1
    var gpuTempC: Int32 = -1
    var autoModeByte1: UInt32 = 0
    var autoModeByte2: UInt32 = 0
    var thermalTripped: UInt32 = 0
    var watchdogTripped: UInt32 = 0
    var ecPresent: UInt32 = 0
    var lastError: UInt32 = 0
    var wmiPresent: UInt32 = 0
    var turboOn: UInt32 = 0
    var lcdOverdriveOn: UInt32 = 0
    var powerProfile: UInt32 = 0
    var pl1Milliwatts: UInt32 = 0
    var pl2Milliwatts: UInt32 = 0
    var powerLimitsLocked: UInt32 = 0
    var lastWMIStatus: UInt64 = 0
    var rgbStatusKB: UInt32 = 0
    var rgbStatusLED: UInt32 = 0
    var rgbStatusRgbKb: UInt32 = 0
    var kbMode: UInt32 = 0
    var kbSpeed: UInt32 = 0
    var kbBrightness: UInt32 = 0
    var kbDirection: UInt32 = 0
    var kbRed: UInt32 = 0
    var kbGreen: UInt32 = 0
    var kbBlue: UInt32 = 0
    var reserved0: UInt32 = 0
    var reserved1: UInt32 = 0
}

enum PSECSelector: UInt32 {
    case setFanMode = 0
    case setDuty    = 1
    case getStatus  = 2
    case ping       = 3
    case ecRead     = 4
    case ecWrite    = 5
    case setTurbo   = 6
    case setLcdOd   = 7
    case setRgb     = 8
    case setPower   = 9
    case rawWMI     = 10
    case setKbEffect = 11
}

enum PSECFanMode: UInt64 { case auto = 0, manual = 1 }

enum PSECError: Error, CustomStringConvertible {
    case notFound, openFailed(kern_return_t), callFailed(String, kern_return_t)
    var description: String {
        switch self {
        case .notFound: return "PredatorSenseEC not found — is the kext loaded?"
        case .openFailed(let k): return String(format: "IOServiceOpen failed (0x%08x)", k)
        case .callFailed(let w, let k): return String(format: "%@ failed (0x%08x)", w, k)
        }
    }
}

final class PSECBridge {
    private var conn: io_connect_t = 0

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("PredatorSenseEC"))
        guard service != 0 else { throw PSECError.notFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { throw PSECError.openFailed(kr) }
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    private func scalar(_ sel: PSECSelector, _ args: [UInt64]) throws {
        let kr = args.withUnsafeBufferPointer { buf in
            IOConnectCallScalarMethod(conn, sel.rawValue, buf.baseAddress,
                                      UInt32(args.count), nil, nil)
        }
        guard kr == KERN_SUCCESS else { throw PSECError.callFailed("\(sel)", kr) }
    }

    func setFanMode(_ m: PSECFanMode) throws { try scalar(.setFanMode, [m.rawValue]) }

    func setDuty(fan1: Int, fan2: Int) throws {
        try scalar(.setDuty, [UInt64(min(max(fan1, 0), 100)),
                              UInt64(min(max(fan2, 0), 100))])
    }

    func ping() throws { try scalar(.ping, []) }

    // Raw EC access, fenced kernel-side to the fan register block (0x93-0x9C).
    func ecRead(_ offset: Int) throws -> Int {
        var out: [UInt64] = [0]; var n: UInt32 = 1
        let args: [UInt64] = [UInt64(clamping: offset)]
        let kr = args.withUnsafeBufferPointer { buf in
            IOConnectCallScalarMethod(conn, PSECSelector.ecRead.rawValue,
                                      buf.baseAddress, 1, &out, &n)
        }
        guard kr == KERN_SUCCESS else { throw PSECError.callFailed("ecRead", kr) }
        return Int(out[0])
    }

    func ecWrite(_ offset: Int, _ value: Int) throws {
        try scalar(.ecWrite, [UInt64(clamping: offset), UInt64(clamping: value)])
    }

    func setTurbo(_ on: Bool) throws { try scalar(.setTurbo, [on ? 1 : 0]) }
    func setLcdOverdrive(_ on: Bool) throws { try scalar(.setLcdOd, [on ? 1 : 0]) }

    func setRgb(zones: Int, r: Int, g: Int, b: Int) throws {
        try scalar(.setRgb, [UInt64(clamping: zones), UInt64(clamping: r), UInt64(clamping: g), UInt64(clamping: b)])
    }

    func setPowerProfile(_ p: Int) throws { try scalar(.setPower, [UInt64(clamping: p)]) }

    func setKbEffect(mode: Int, speed: Int, brightness: Int, direction: Int,
                     r: Int, g: Int, b: Int) throws {
        try scalar(.setKbEffect, [UInt64(clamping: mode), UInt64(clamping: speed), UInt64(clamping: brightness),
                                  UInt64(clamping: direction), UInt64(clamping: r), UInt64(clamping: g), UInt64(clamping: b)])
    }

    // Must match PSECShared.h.
    struct WMIRequest { var methodId: UInt32 = 0; var inLength: UInt32 = 0
                        var b0: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                                 UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)
                            = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) }
    struct WMIReply   { var status: UInt32 = 0; var outLength: UInt32 = 0
                        var b0: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                                 UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)
                            = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) }

    /// Raw WMBH. `bytes` is the exact input buffer — its length is the argument
    /// width, which the firmware cares about (4 for uint32 methods, 8 for
    /// uint64, 16 for the keyboard descriptor).
    func rawWMI(_ methodId: Int, _ bytes: [UInt8]) throws -> (Int, [UInt8]) {
        guard (1...16).contains(bytes.count) else {
            throw PSECError.callFailed("rawWMI: 1-16 input bytes", 0)
        }
        var req = WMIRequest()
        req.methodId = UInt32(clamping: methodId)
        req.inLength = UInt32(bytes.count)
        withUnsafeMutableBytes(of: &req.b0) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
        }
        var rep = WMIReply()
        var outSize = MemoryLayout<WMIReply>.stride
        let kr = withUnsafeBytes(of: &req) { inRaw in
            withUnsafeMutableBytes(of: &rep) { outRaw in
                IOConnectCallStructMethod(conn, PSECSelector.rawWMI.rawValue,
                                          inRaw.baseAddress,
                                          MemoryLayout<WMIRequest>.stride,
                                          outRaw.baseAddress, &outSize)
            }
        }
        guard kr == KERN_SUCCESS else { throw PSECError.callFailed("rawWMI", kr) }
        var out = [UInt8]()
        withUnsafeBytes(of: &rep.b0) { raw in
            for i in 0..<Int(min(rep.outLength, 16)) { out.append(raw[i]) }
        }
        return (Int(Int32(bitPattern: rep.status)), out)
    }

    func status() throws -> PSECStatus {
        var s = PSECStatus()
        var size = MemoryLayout<PSECStatus>.stride
        let kr = withUnsafeMutableBytes(of: &s) { raw -> kern_return_t in
            IOConnectCallStructMethod(conn, PSECSelector.getStatus.rawValue,
                                      nil, 0, raw.baseAddress, &size)
        }
        guard kr == KERN_SUCCESS else { throw PSECError.callFailed("getStatus", kr) }
        return s
    }
}
