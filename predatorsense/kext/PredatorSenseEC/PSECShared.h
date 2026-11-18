//
//  PSECShared.h — shared ABI between PredatorSenseEC.kext and userspace.
//
//  Acer Predator Triton 500 (PT515-51). Every constant here was read out of
//  this machine's own SSDT1, and the read path was verified working on it:
//      CPU_Temp_C 68, GPU_Temp_C 42, Fan1 2586 RPM, Fan2 3072 RPM
//
//  EC RAM (OperationRegion (RAM, EmbeddedControl, Zero, 0xFF)):
//      0x93 F1ST   fan 1 mode/status
//      0x94 F1WS   fan 1 duty
//      0x95 F1RS   fan 1 tach       RPM = 0x78000 / F1RS
//      0x96 F2ST / 0x97 F2WS / 0x98 F2RS
//      0x20 MS0T   CPU temp   (read by name, not offset)
//      0x21 MS1T   GPU temp
//
//  Firmware's own manual-control sequence, from Method (SFMS):
//      F1ST = 0x14        <- mode register, bit 0x10 = manual override
//      F1WS = GFMS(fan)   <- duty
//
//  Method (GFMS) gives the MAXIMUM duty per fan. These are NOT percentages:
//      fan 1 -> 0x66 (102)
//      fan 2 -> 0x4E (78)
//  Userspace speaks in percent; the driver scales to these per-fan maxima.
//

#ifndef PSECShared_h
#define PSECShared_h

#include <stdint.h>

#define kPSECServiceName    "PredatorSenseEC"

// --- EC register offsets (writes go through writeAddressSpace) --------------
#define PSEC_REG_F1ST   0x93
#define PSEC_REG_F1WS   0x94
#define PSEC_REG_F2ST   0x96
#define PSEC_REG_F2WS   0x97
// Third fan channel. GFMS reports a maximum for it (0x4A) so the EC believes it
// exists; whether this chassis wires the GPU fan to channel 2 or 3 is exactly
// what the raw read/write methods below are for.
#define PSEC_REG_F3ST   0x9A
#define PSEC_REG_F3WS   0x9B
#define PSEC_REG_F3RS   0x9C
#define PSEC_FAN3_MAX_DUTY  0x4A

// --- mode register ---------------------------------------------------------
// Observed at boot: 0x04 (bit 2 = tach valid). Firmware writes 0x14 to take
// manual control, so bit 0x10 is the manual-override flag. We never hardcode
// the auto value — we capture whatever the EC had before our first write and
// restore exactly that.
#define PSEC_MODE_MANUAL_BIT    0x10

// --- per-fan maximum duty, from Method (GFMS) ------------------------------
#define PSEC_FAN1_MAX_DUTY  0x66    // 102
#define PSEC_FAN2_MAX_DUTY  0x4E    // 78

// Percent floor. Below this we refuse, regardless of what userspace asks.
// Applied AFTER scaling, so it means "35% of this fan's own maximum".
#define PSEC_MIN_DUTY_PERCENT   35
#define PSEC_MAX_DUTY_PERCENT   100

// --- safety ----------------------------------------------------------------
// Uses the real EC CPU sensor (MS0T), not a per-core MSR.
#define PSEC_THERMAL_CEILING_C      88
#define PSEC_THERMAL_RELEASE_C      78      // hysteresis
#define PSEC_WATCHDOG_TIMEOUT_MS    6000
#define PSEC_POLL_INTERVAL_MS       2000
#define PSEC_FIRST_READ_DELAY_MS    20000   // let the system settle after boot

enum {
    kPSECFanModeAuto   = 0,     // EC's own curve — restores captured mode byte
    kPSECFanModeManual = 1,     // our duty
};

enum {
    kPSECMethodSetFanMode = 0,  // in: mode
    kPSECMethodSetDuty,         // in: fan1Pct, fan2Pct
    kPSECMethodGetStatus,       // out: PSECStatus
    kPSECMethodPing,            // watchdog keepalive
    kPSECMethodECRead,          // in: offset            out: value
    kPSECMethodECWrite,         // in: offset, value
    kPSECMethodSetTurbo,        // in: on
    kPSECMethodSetLcdOverdrive, // in: on
    kPSECMethodSetRgb,          // in: zoneMask, r, g, b
    kPSECMethodSetPowerProfile, // in: profile  (MSR PL1/PL2)
    kPSECMethodRawWMI,          // in: methodId, payload   out: result
    kPSECMethodSetKbEffect,     // in: mode, speed, brightness, direction, r,g,b
    kPSECMethodCount
};

typedef struct {
    uint32_t    version;
    uint32_t    fanMode;            // kPSECFanMode*
    uint32_t    hwFanMode;          // what the EC has actually confirmed
    uint32_t    fan1Percent;        // last commanded
    uint32_t    fan2Percent;
    uint32_t    fan1RawDuty;        // as written to F1WS
    uint32_t    fan2RawDuty;
    uint32_t    fan1RPM;
    uint32_t    fan2RPM;
    uint32_t    fan1Status;         // F1ST as read
    uint32_t    fan2Status;
    int32_t     cpuTempC;           // MS0T, -1 if unavailable
    int32_t     gpuTempC;           // MS1T
    uint32_t    autoModeByte1;      // captured pre-write F1ST
    uint32_t    autoModeByte2;
    uint32_t    thermalTripped;
    uint32_t    watchdogTripped;
    uint32_t    ecPresent;
    uint32_t    lastError;
    uint32_t    wmiPresent;     // \_SB.PCI0.WMID found and WMBH callable
    uint32_t    turboOn;
    uint32_t    lcdOverdriveOn;
    uint32_t    powerProfile;
    uint32_t    pl1Milliwatts;
    uint32_t    pl2Milliwatts;
    uint32_t    powerLimitsLocked;
    uint64_t    lastWMIStatus;
    uint32_t    rgbStatusKB;        // per-candidate results from the last rgb call
    uint32_t    rgbStatusLED;
    uint32_t    rgbStatusRgbKb;
    uint32_t    kbMode;
    uint32_t    kbSpeed;
    uint32_t    kbBrightness;
    uint32_t    kbDirection;
    uint32_t    kbRed;
    uint32_t    kbGreen;
    uint32_t    kbBlue;
    uint32_t    reserved0;
    uint32_t    reserved1;      // keeps the struct a multiple of 8 — see below
} PSECStatus;

// Swift's MemoryLayout.size EXCLUDES trailing padding; C's sizeof INCLUDES it.
// The IOUserClient dispatch table compares the two for exact equality, so any
// field layout that needs tail padding makes every getStatus call fail with
// kIOReturnBadArgument. That is exactly what adding the 7 keyboard fields did
// in 2.6.x. Keep the struct naturally 8-aligned and the two agree.
#if defined(__cplusplus)
static_assert(sizeof(PSECStatus) % 8 == 0,
              "PSECStatus needs tail padding — add a uint32_t reserved field. "
              "Swift MemoryLayout.size will not match C sizeof otherwise.");
#endif

// CPU power profiles. There is NO WMI method for these on a PT515-51 —
// PredatorSense uses Intel XTU. We drive MSR_PKG_POWER_LIMIT, which is what XTU
// ultimately writes, relative to the firmware's own values captured at load.
#define MSR_PKG_POWER_LIMIT     0x610
#define MSR_RAPL_POWER_UNIT     0x606
#define MSR_IA32_MISC_ENABLE    0x1A0    // bit 38 = Turbo Mode DISABLE
#define MSR_POWER_CTL           0x1FC    // bit 0 = BD PROCHOT enable
#define MSR_CORE_PERF_LIMIT_REASONS 0x690 // why the core is not going faster
// 0x690 status bits (low half; high half is the sticky log, cleared on write):
//   0 PROCHOT   1 Thermal   4 Residency/RATL   5 VR Therm   6 VR TDC
//   7 Other/EDP 9 PL1       10 PL2             11 Max Turbo Limit
//   12 Turbo Attenuation
// Both MSRs are documented for 6th-10th gen client parts (Coffee Lake included).

// Performance mirrors Acer's own "Extreme / Turbo" profile, from PredatorSense's
// published table for this machine:
//
//   Normal   PL1 45 W   PL2 ~56 W
//   Fast     PL1 45 W   PL2 up to 90 W
//   Extreme  PL1 45 W   PL2 90 W (hard limit, max Intel spec)
//
// Note PL1 stays at 45 W in EVERY profile — Acer never raises the sustained
// limit, only the burst. An earlier version of this driver lifted PL1 to 60 W,
// which was my invention rather than anything the vendor does; that is gone.
//
// So Performance = the firmware's own PL1, untouched, with PL2 at the 90 W /
// 28 s burst that is both Acer's Extreme profile and Intel's stock
// configuration for a 45 W H-series part (PL2 = 2 x PL1, tau = 28 s).
//
// No voltage is touched: no undervolt, no offset, no AVX ratio games. No
// thermal protection is disabled — PROCHOT, the CPU's own 100 C throttle and
// our 88 C fan ceiling all stay armed.
#define PSEC_PERF_PL1_MW            65000   // Turbo/Performance SUSTAINED limit.
                                            // Firmware default is 45 W. Measured 2026-09-02:
                                            // at PL1 45 W the package sat at 3.15 GHz all-core
                                            // and only 62-67 C - ~30 C of unused headroom below
                                            // Tjmax. The sustained clamp, not heat, was the
                                            // multi-core bottleneck. PSEC_THERMAL_CEILING_C (88)
                                            // remains the backstop.
#define PSEC_PERF_PL2_MW            90000
#define PSEC_PERF_TAU_SEC           28
#define PSEC_PL_ABS_MAX_MW          90000   // and never above this, regardless
enum { kPSPowerLow = 0, kPSPowerBalanced = 1, kPSPowerPerformance = 2 };

#define kPSECStatusVersion  4

// ---------------------------------------------------------------------------
// Acer gaming WMI, via ACPI method \_SB.PCI0.WMID.WMBH(instance, methodId, buf)
//
// Method IDs come from the firmware's own binary MOF (WQAB in SSDT10, class
// AcerGamingFunction). Payload encodings were recovered from PredatorSense's
// binaries and cross-checked against the Linux acer-wmi driver.
//
// NOTE: the earlier AcerGamingWMI kext never ran a line of this — it died at
// boot on the same Info.plist dependency bug fixed here. The SMI path itself is
// untested, not disproven.
// ---------------------------------------------------------------------------
// Method IDs AND their argument widths, straight out of WQAB. The widths are
// not cosmetic: WSMI copies our buffer verbatim into the SMM mailbox, so a
// method declared [in] uint32 must be handed FOUR bytes, not eight. v2.1.0 sent
// eight for everything, which is the likeliest reason RGB did nothing.
//
//   [WmiMethodId(1)]  SetGamingProfile      ([in] uint64,     [out] uint32)
//   [WmiMethodId(3)]  GetGamingProfile      ([in] uint32,     [out] uint64)
//   [WmiMethodId(5)]  GetGamingSysInfo      ([in] uint32,     [out] uint64)
//   [WmiMethodId(6)]  SetGamingRgbKb        ([in] uint32,     [out] uint64)
//   [WmiMethodId(14)] SetGamingFanBehavior  ([in] uint64,     [out] uint32)
//   [WmiMethodId(16)] SetGamingFanSpeed     ([in] uint64,     [out] uint32)
//   [WmiMethodId(17)] GetGamingFanSpeed     ([in] uint32,     [out] uint64)
//   [WmiMethodId(20)] SetGamingKBBacklight  ([in] uint8[16],  [out] uint32)
//   [WmiMethodId(21)] GetGamingKBBacklight  ([in] uint32,     [out] uint8[16])
//   [WmiMethodId(22)] SetGamingMiscSetting  ([in] uint64,     [out] uint32)
//   [WmiMethodId(23)] GetGamingMiscSetting  ([in] uint32,     [out] uint64)
//
// Note SetGamingRgbKb(6) is only 32 bits wide — too narrow for four zones of
// 24-bit colour. The real per-zone interface is SetGamingKBBacklight(20), which
// takes a 16-byte descriptor. That is the one PredatorSense drives.
#define kWMI_SetGamingProfile       1     // u64 — LCD Overdrive lives here
#define kWMI_SetGamingLED           2     // u64
#define kWMI_SetGamingLEDBehavior   10    // u64
#define kWMI_SetGamingLEDColor      12    // u64 — "LED Group Color"
#define kWMI_GetGamingProfile       3     // u32 -> u64
#define kWMI_GetGamingLED           4     // u32 -> u64
#define kWMI_GetGamingSysInfo       5     // u32 -> u64
#define kWMI_SetGamingRgbKb         6     // u32 -> u64
#define kWMI_GetGamingRgbKb         7     // u32 -> u64
#define kWMI_SetGamingFanBehavior   14    // u64
#define kWMI_GetGamingFanBehavior   15    // u32 -> u64
#define kWMI_SetGamingFanSpeed      16    // u64
#define kWMI_GetGamingFanSpeed      17    // u32 -> u64
#define kWMI_SetGamingKBBacklight   20    // u8[16]
#define kWMI_GetGamingKBBacklight   21    // u32 -> u8[16]
#define kWMI_SetGamingMiscSetting   22    // u64 — Turbo lives here
#define kWMI_GetGamingMiscSetting   23    // u32 -> u64

#define kPSECWMIMaxBuf  16

typedef struct {
    uint32_t    methodId;
    uint32_t    inLength;               // 4, 8 or 16
    uint8_t     in[kPSECWMIMaxBuf];
} PSECWMIRequest;

typedef struct {
    uint32_t    status;                 // IOReturn from evaluateObject
    uint32_t    outLength;
    uint8_t     out[kPSECWMIMaxBuf];
} PSECWMIReply;

// SetGamingFanBehavior: bits 0-15 fan-select mask, then 2 bits of mode per slot
// starting at bit 16. Slot 0 = CPU1, slot 3 = GPU1 on this chassis.
#define kWMIFanSelectMask   0x0009ULL     // CPU1 | GPU1
#define kWMIFanAuto     1
#define kWMIFanMax      2
#define kWMIFanCustom   3
// Slot n's 2-bit mode field sits at bit (16 + 2n). The select mask picks bits 0
// and 3, so slot 0 and slot 3 are the two live slots — and since the speed
// ordinals are 1-based versions of those bits, slot 0 is ordinal 1 (GPU on this
// chassis) and slot 3 is ordinal 4 (CPU).
#define WMI_FAN_BEHAVIOR(mode) \
    ( kWMIFanSelectMask | ((uint64_t)(mode) << 16) | ((uint64_t)(mode) << 22) )
#define WMI_FAN_BEHAVIOR2(gpuMode, cpuMode) \
    ( kWMIFanSelectMask | ((uint64_t)(gpuMode) << 16) | ((uint64_t)(cpuMode) << 22) )

// SetGamingFanSpeed: bits 0-7 fan id (1-based ordinal), bits 8-15 percent 0-100.
// SWAPPED in 2.2.0. Testing on the machine showed ordinal 1 drives the GPU-side
// fan and ordinal 4 the CPU-side one — the opposite of the EC's F1/F2 naming.
// Measured, not assumed.
#define kWMIFanIdCPU1   4
#define kWMIFanIdGPU1   1
#define WMI_FAN_SPEED(id, pct)  ( (uint64_t)(id) | ((uint64_t)(pct) << 8) )

// SetGamingMiscSetting: bits 0-7 index, bits 8-15 value. Index 1 = Turbo.
#define kWMIMiscTurbo   1
#define WMI_MISC(i, v)  ( (uint64_t)(i) | ((uint64_t)(v) << 8) )

// SetGamingProfile: bits 0-15 feature mask; value for feature k at bit (16+8k).
// LCD Overdrive is feature bit 4, so its value byte sits at bit 48.
#define WMI_LCD_OVERDRIVE(on) ( 0x0010ULL | ((uint64_t)((on) ? 1 : 0) << 48) )

// SetGamingKBBacklight(20) — 16-byte descriptor. Byte 0 is the mode; static
// colour is mode 0. The remaining layout below is the best reconstruction, and
// the driver deliberately does NOT rely on it blindly: setRgb() reads the
// current descriptor back with GetGamingKBBacklight(21) and patches only the
// colour bytes, so whatever the firmware already has for speed/brightness/
// direction is preserved rather than overwritten with guesses.
#define kWMIKbModeStatic    0
#define kWMIKbOffMode       3
#define kWMIKbByteMode      0
#define kWMIKbByteSpeed     1
#define kWMIKbByteBright    2
#define kWMIKbByteDirection 3
#define kWMIKbByteRed       4
#define kWMIKbByteGreen     5
#define kWMIKbByteBlue      6
#define kWMIRgbAllZones kWMIRgbZoneMaskAll

// Turbo is a composite, not a single call:
//     SetGamingLED(2)          <- 0x10001 on, 0x1 off
//     SetGamingFanBehavior(14) <- mode 2 (MAX) on, mode 1 (auto) off
// Its fan action is the same MAX mode a 100% slider already sends.
#define kWMITurboLedOn   0x10001ULL
#define kWMITurboLedOff  0x1ULL

// SetGamingRgbKb(6) — per-zone static colour. 4-byte packed struct:
//     struct { u8 zone; u8 red; u8 green; u8 blue; } __packed;
//
// Zones are numbered 1-4 in the firmware, left to right. This keyboard has
// THREE physical zones, but which firmware indices they answer to is a property
// of the chassis, not something to hardcode — so the kext accepts all four and
// the daemon holds the mapping (see `zonemap`). Guessing it here is what made
// the right-hand zone dead twice.
#define kWMIRgbZoneFirst 1
#define kWMIRgbZoneLast  4
#define kWMIRgbZoneMaskAll  0x0F

// SetGamingKBBacklight(20) — 16-byte buffer. Carries brightness and every
// animation mode:
//     [0] mode        [1] speed (0-9)     [2] brightness (0-100)
//     [3] 8 if mode == wave, else 0       [4] direction (1 or 2)
//     [5] red         [6] green           [7] blue
//     [9] 1           (enable flag; the rest are zero)
#define kWMIKbLen           16
#define kWMIKbIdxMode       0
#define kWMIKbIdxSpeed      1
#define kWMIKbIdxBrightness 2
#define kWMIKbIdxWave       3
#define kWMIKbIdxDirection  4
#define kWMIKbIdxRed        5
#define kWMIKbIdxGreen      6
#define kWMIKbIdxBlue       7
#define kWMIKbIdxEnable     9

enum {
    kKbModeStatic   = 0,    // uses per-zone colours from method 6
    kKbModeBreath   = 1,
    kKbModeNeon     = 2,    // ignores colour
    kKbModeWave     = 3,    // ignores colour
    kKbModeShifting = 4,
    kKbModeZoom     = 5,
    kKbModeCount    = 6
};

#define kKbSpeedMin      0
#define kKbSpeedMax      9
#define kKbBrightMin     0
#define kKbBrightMax     100
#define kKbDirRightLeft  1
#define kKbDirLeftRight  2

// Raw EC access is deliberately fenced to the fan block. A typo in an offset
// must not be able to write to battery, thermal trip points or anything else.
#define PSEC_RAW_MIN_OFFSET 0x93
#define PSEC_RAW_MAX_OFFSET 0x9C

#endif /* PSECShared_h */
