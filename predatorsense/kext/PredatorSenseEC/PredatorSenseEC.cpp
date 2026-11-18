//
//  PredatorSenseEC.cpp — PHASE 2: read + write, via the Embedded Controller.
//
//  No SMI. No WMBH. No MSR writes. Everything goes through the ACPI
//  EmbeddedControl address space, which AppleACPIEC serialises and times out —
//  so a bad transaction is an error code, not a wedged CPU.
//
//  Matches IOResources, so it takes no part in boot-time ACPI matching. The EC
//  is located at runtime, well after boot. (v1 declared a dependency on
//  com.apple.driver.AppleACPIPlatform instead of com.apple.iokit.IOACPIFamily
//  and hung the machine at ACPI bring-up; that is fixed in the Info.plist.)
//
//  SAFETY MODEL
//  ------------
//   1. start() touches no hardware. First EC access is 20s after load.
//   2. "Auto" is not a value we invent — we capture the EC's own mode byte
//      before our first write and restore exactly that.
//   3. Duty floor of 35% of each fan's OWN maximum (fan1 max 102, fan2 max 78;
//      these are raw units, not percentages).
//   4. Thermal ceiling at 88C using the real EC sensor MS0T, with hysteresis.
//   5. Watchdog: in manual mode userspace must ping, or we hand the fans back.
//   6. Client disconnect, sleep, stop and any write failure all revert to auto.
//   7. fHwFanMode tracks what the EC CONFIRMED, so a failed write is retried
//      every tick instead of being assumed to have worked.
//

#include "PredatorSenseEC.hpp"
#include <IOKit/pwr_mgt/IOPM.h>
#include <kern/clock.h>
#include <mach/mach_time.h>

#define super IOService
OSDefineMetaClassAndStructors(PredatorSenseEC, IOService)

#define PSLog(fmt, ...) IOLog("PredatorSenseEC: " fmt "\n", ## __VA_ARGS__)

enum { kPowerOff = 0, kPowerOn = 1, kPowerCount };
static IOPMPowerState gPowerStates[kPowerCount] = {
    { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 1, kIOPMPowerOn, kIOPMPowerOn, kIOPMPowerOn, 0, 0, 0, 0, 0, 0, 0, 0 }
};

uint64_t PredatorSenseEC::nowMs(void)
{
    uint64_t ns = 0;
    absolutetime_to_nanoseconds(mach_absolute_time(), &ns);
    return ns / 1000000ULL;
}

uint32_t PredatorSenseEC::pctToRaw(uint32_t pct, uint32_t maxDuty)
{
    if (pct < PSEC_MIN_DUTY_PERCENT) pct = PSEC_MIN_DUTY_PERCENT;
    if (pct > PSEC_MAX_DUTY_PERCENT) pct = PSEC_MAX_DUTY_PERCENT;
    uint32_t raw = (pct * maxDuty) / 100;
    if (raw > maxDuty) raw = maxDuty;       // never exceed the firmware maximum
    return raw;
}

// ---------------------------------------------------------------------------

bool PredatorSenseEC::start(IOService *provider)
{
    if (!super::start(provider))
        return false;

    fLock = IORecursiveLockAlloc();
    if (!fLock) return false;

    fWorkLoop = IOWorkLoop::workLoop();
    if (!fWorkLoop) goto fail;

    fTimer = IOTimerEventSource::timerEventSource(this,
                OSMemberFunctionCast(IOTimerEventSource::Action, this,
                                     &PredatorSenseEC::poll));
    if (!fTimer || fWorkLoop->addEventSource(fTimer) != kIOReturnSuccess)
        goto fail;

    setProperty("Status", "waiting — EC lookup deferred until after boot");

    // No hardware access here, deliberately.
    fTimer->setTimeoutMS(PSEC_FIRST_READ_DELAY_MS);

    PMinit();
    provider->joinPMtree(this);
    registerPowerDriver(this, gPowerStates, kPowerCount);

    registerService();
    PSLog("loaded (IOResources). EC lookup in %u ms", PSEC_FIRST_READ_DELAY_MS);
    return true;

fail:
    if (fTimer) {
        if (fWorkLoop) fWorkLoop->removeEventSource(fTimer);
        fTimer->release();
        fTimer = nullptr;
    }
    OSSafeReleaseNULL(fWorkLoop);
    if (fLock) { IORecursiveLockFree(fLock); fLock = nullptr; }
    return false;
}

void PredatorSenseEC::stop(IOService *provider)
{
    revertToAuto("driver stopping");

    if (fTimer) {
        fTimer->cancelTimeout();
        if (fWorkLoop) fWorkLoop->removeEventSource(fTimer);
        fTimer->release();
        fTimer = nullptr;
    }
    OSSafeReleaseNULL(fWorkLoop);
    OSSafeReleaseNULL(fEC);
    OSSafeReleaseNULL(fWMI);
    PMstop();
    if (fLock) { IORecursiveLockFree(fLock); fLock = nullptr; }
    super::stop(provider);
}

IOReturn PredatorSenseEC::setPowerState(unsigned long which, IOService *whom)
{
    if (which == kPowerOff) {
        // The EC reinitialises across sleep, so any manual duty is void on the
        // other side. Release control but remember what the user wanted.
        revertToAuto("system sleep", /*clearDesired=*/false);
    } else if (fEC) {
        IORecursiveLockLock(fLock);
        fThermalTripped = false;
        fWatchdogTripped = false;
        fHwFanMode = kPSECFanModeAuto;   // EC reset itself
        fLastPingMs = nowMs();
        applyFanState();
        IORecursiveLockUnlock(fLock);
    }
    return kIOPMAckImplied;
}

// ---------------------------------------------------------------------------
// EC access
// ---------------------------------------------------------------------------

bool PredatorSenseEC::findEC(void)
{
    if (fEC) return true;

    OSDictionary *match = IOService::nameMatching("PNP0C09");
    if (!match) return false;
    OSIterator *it = IOService::getMatchingServices(match);
    match->release();
    if (!it) return false;

    while (OSObject *o = it->getNextObject()) {
        IOACPIPlatformDevice *dev = OSDynamicCast(IOACPIPlatformDevice, o);
        if (!dev) continue;
        if (dev->validateObject("F1RS") == kIOReturnSuccess) {
            fEC = dev;
            fEC->retain();
            PSLog("found EC '%s'", dev->getName());
            break;
        }
    }
    it->release();
    return fEC != nullptr;
}

// ---------------------------------------------------------------------------
// Acer gaming WMI.
//
// \_SB.PCI0.WMID.WMBH(instance, methodId, buffer) -> buffer
//
// The WMID device is a PNP0C14 (ACPI-WMI mapper). This machine has four of
// them; three are Intel stubs (WMTF / WFDE / WFTE) and only one exposes WMBH,
// so we filter on the method actually being present rather than on the name.
//
// Nothing here runs at boot. findWMI() is only reached from an explicit user
// request, long after the desktop is up — so if the SMM handler behind WMBH
// really does stall, it cannot cost a boot.
// ---------------------------------------------------------------------------

bool PredatorSenseEC::findWMI(void)
{
    if (fWMI) return true;
    if (fWMIFindTries >= 3) return false;
    fWMIFindTries++;

    OSDictionary *match = IOService::nameMatching("PNP0C14");
    if (!match) return false;
    OSIterator *it = IOService::getMatchingServices(match);
    match->release();
    if (!it) return false;

    while (OSObject *o = it->getNextObject()) {
        IOACPIPlatformDevice *dev = OSDynamicCast(IOACPIPlatformDevice, o);
        if (!dev) continue;
        if (dev->validateObject("WMBH") == kIOReturnSuccess) {
            fWMI = dev;
            fWMI->retain();
            PSLog("found Acer WMI mapper '%s' (WMBH present)", dev->getName());
            break;
        }
    }
    it->release();
    if (!fWMI) PSLog("no PNP0C14 device exposing WMBH");
    return fWMI != nullptr;
}

// The argument WIDTH matters. WSMI copies our buffer straight into the SMM
// mailbox, so a method the MOF declares [in] uint32 must receive four bytes.
// v2.1.0 sent eight for everything — which is the most likely reason the
// keyboard did nothing while the uint64 fan methods worked.
IOReturn PredatorSenseEC::callWMBH(uint32_t methodId, const void *in,
                                   uint32_t inLen, uint8_t *out, uint32_t *outLen)
{
    if (!fWMI && !findWMI()) return kIOReturnNoDevice;
    if (!in || inLen == 0 || inLen > kPSECWMIMaxBuf) return kIOReturnBadArgument;

    OSNumber *inst = OSNumber::withNumber((unsigned long long)0, 32);
    OSNumber *mid  = OSNumber::withNumber((unsigned long long)methodId, 32);
    OSData   *buf  = OSData::withBytes(in, inLen);
    if (!inst || !mid || !buf) {
        OSSafeReleaseNULL(inst); OSSafeReleaseNULL(mid); OSSafeReleaseNULL(buf);
        return kIOReturnNoMemory;
    }

    OSObject *params[3] = { inst, mid, buf };
    OSObject *result = nullptr;

    PSLog("WMBH(0, %u, %u bytes)", methodId, inLen);
    IOReturn r = fWMI->evaluateObject("WMBH", &result, params, 3);

    uint8_t tmp[kPSECWMIMaxBuf];
    bzero(tmp, sizeof(tmp));
    uint32_t got = 0;

    if (r == kIOReturnSuccess && result) {
        if (OSData *d = OSDynamicCast(OSData, result)) {
            got = d->getLength();
            if (got > kPSECWMIMaxBuf) got = kPSECWMIMaxBuf;
            memcpy(tmp, d->getBytesNoCopy(), got);
        } else if (OSNumber *nu = OSDynamicCast(OSNumber, result)) {
            uint64_t v = nu->unsigned64BitValue();
            got = 8;
            for (int i = 0; i < 8; i++) tmp[i] = (uint8_t)((v >> (8 * i)) & 0xFF);
        }
    }
    OSSafeReleaseNULL(result);
    inst->release(); mid->release(); buf->release();

    uint64_t st = 0;
    for (uint32_t i = 0; i < got && i < 8; i++) st |= ((uint64_t)tmp[i]) << (8 * i);
    fLastWMIStatus = st;

    if (r != kIOReturnSuccess) {
        fLastError = r;
        PSLog("WMBH method %u FAILED (0x%08x)", methodId, r);
    } else {
        PSLog("WMBH method %u -> %u bytes, 0x%016llx", methodId, got, st);
    }
    if (out)    memcpy(out, tmp, kPSECWMIMaxBuf);
    if (outLen) *outLen = got;
    return r;
}

IOReturn PredatorSenseEC::callWMBH64(uint32_t methodId, uint64_t payload)
{
    uint8_t raw[8];
    for (int i = 0; i < 8; i++) raw[i] = (uint8_t)((payload >> (8 * i)) & 0xFF);
    return callWMBH(methodId, raw, sizeof(raw), nullptr, nullptr);
}

IOReturn PredatorSenseEC::callWMBH32(uint32_t methodId, uint32_t arg, uint64_t *out)
{
    uint8_t raw[4];
    for (int i = 0; i < 4; i++) raw[i] = (uint8_t)((arg >> (8 * i)) & 0xFF);
    uint8_t buf[kPSECWMIMaxBuf]; uint32_t n = 0;
    IOReturn r = callWMBH(methodId, raw, sizeof(raw), buf, &n);
    if (out) {
        uint64_t v = 0;
        for (uint32_t i = 0; i < n && i < 8; i++) v |= ((uint64_t)buf[i]) << (8 * i);
        *out = v;
    }
    return r;
}

IOReturn PredatorSenseEC::rawWMI(const PSECWMIRequest *req, PSECWMIReply *rep)
{
    if (!req || !rep) return kIOReturnBadArgument;
    bzero(rep, sizeof(*rep));
    IORecursiveLockLock(fLock);
    IOReturn r = callWMBH(req->methodId, req->in, req->inLength,
                          rep->out, &rep->outLength);
    IORecursiveLockUnlock(fLock);
    rep->status = (uint32_t)r;
    return kIOReturnSuccess;    // transport succeeded; the WMI result is in rep
}

// A user pressing a button is a fresh reason to go looking for the mapper.
// Without this, three early misses disabled Turbo/RGB/LCD until the next boot.
void PredatorSenseEC::rearmWMI(void)
{
    if (!fWMI) fWMIFindTries = 0;
}

// Turbo is a composite, not SetGamingMiscSetting. From the Linux acer module:
// the turbo LED goes through SetGamingLED(2), and the fan side is just
// SetGamingFanBehavior mode 2 (MAX) — the same thing a 100% slider already
// does. So this drives the LED and lets the existing fan path handle the rest;
// there is no separate fan ceiling for turbo to unlock.
IOReturn PredatorSenseEC::setTurbo(uint32_t on)
{
    IORecursiveLockLock(fLock);
    rearmWMI();
    bool prevTurbo = fTurboOn;
    uint32_t prevFanMode = fFanMode, prevFan1Pct = fFan1Pct, prevFan2Pct = fFan2Pct;
    uint32_t prevPowerProfile = fPowerProfile;
    IOReturn r = callWMBH64(kWMI_SetGamingLED,
                            on ? kWMITurboLedOn : kWMITurboLedOff);
    if (r == kIOReturnSuccess) {
        fTurboOn = (on != 0);
        // Turbo means turbo: max fans AND the uncapped power profile. Leaving
        // it on Balanced would make the switch cosmetic.
        if (on) {
            if (!prevTurbo) {           // don't overwrite the stash on a repeat
                fPreTurboFanMode = fFanMode;
                fPreTurboFan1Pct = fFan1Pct; fPreTurboFan2Pct = fFan2Pct;
                fPreTurboProfile = fPowerProfile;
            }
            fFanMode = kPSECFanModeManual; fFan1Pct = 100; fFan2Pct = 100;
            fPowerProfile = kPSPowerPerformance;
        } else if (prevTurbo) {
            // Give back exactly what the user had before Turbo.
            fFanMode = fPreTurboFanMode;
            fFan1Pct = fPreTurboFan1Pct; fFan2Pct = fPreTurboFan2Pct;
            fPowerProfile = fPreTurboProfile;
        }
        fLastPingMs = nowMs();
        applyFanState();
        r = applyPowerProfile();
        if (r != kIOReturnSuccess) {
            // Turbo is an all-or-nothing mode.  Do not leave its LED and max
            // fans enabled when the requested 90 W PL2 did not take.
            fTurboOn = prevTurbo;
            fFanMode = prevFanMode; fFan1Pct = prevFan1Pct; fFan2Pct = prevFan2Pct;
            fPowerProfile = prevPowerProfile;
            applyFanState();
            (void)callWMBH64(kWMI_SetGamingLED,
                             prevTurbo ? kWMITurboLedOn : kWMITurboLedOff);
        }
    }
    IORecursiveLockUnlock(fLock);
    return r;
}

IOReturn PredatorSenseEC::setLcdOverdrive(uint32_t on)
{
    IORecursiveLockLock(fLock);
    rearmWMI();
    IOReturn r = callWMBH64(kWMI_SetGamingProfile, WMI_LCD_OVERDRIVE(on));
    if (r == kIOReturnSuccess) {
        uint64_t v = 0;
        if (callWMBH32(kWMI_GetGamingProfile, 0x10, &v) == kIOReturnSuccess)
            PSLog("LCD overdrive readback: 0x%016llx", v);
        fLcdOdOn = (on != 0);
    }
    IORecursiveLockUnlock(fLock);
    return r;
}

// Keyboard RGB.
//
// Two methods work together:
//   SetGamingRgbKb(6)       4 bytes {zone, r, g, b}, ZONES 1-4 LEFT TO RIGHT
//   SetGamingKBBacklight(20) 16 bytes: mode, speed, brightness, direction, rgb
//
// v2.5.0 numbered the zones 0-3. Zone 0 is invalid and zone 4 — the rightmost —
// was never addressed, which is exactly the symptom seen on the machine.
IOReturn PredatorSenseEC::setRgb(uint32_t zoneMask, uint32_t r8, uint32_t g8, uint32_t b8)
{
    if (zoneMask == 0 || zoneMask > kWMIRgbZoneMaskAll) return kIOReturnBadArgument;
    if (r8 > 255 || g8 > 255 || b8 > 255) return kIOReturnBadArgument;

    IORecursiveLockLock(fLock);
    rearmWMI();

    IOReturn last = kIOReturnSuccess;
    bool any = false;
    for (uint32_t z = kWMIRgbZoneFirst; z <= kWMIRgbZoneLast; z++) {
        if (!(zoneMask & (1u << (z - kWMIRgbZoneFirst)))) continue;
        uint8_t p[4] = { (uint8_t)z, (uint8_t)r8, (uint8_t)g8, (uint8_t)b8 };
        IOReturn r = callWMBH(kWMI_SetGamingRgbKb, p, sizeof(p), nullptr, nullptr);
        if (r == kIOReturnSuccess) any = true; else last = r;
    }
    fRgbStatusRgbKb = (uint32_t)last;
    fKbR = r8; fKbG = g8; fKbB = b8;

    // Per-zone colour only shows in static mode, and the zones stay dark if
    // brightness is 0 — so make the state consistent rather than leaving the
    // user with a colour they set and cannot see.
    if (any) {
        fKbMode = kKbModeStatic;
        if (fKbBrightness == 0) fKbBrightness = kKbBrightMax;
        applyKbEffect();
    }
    PSLog("RGB %02x/%02x/%02x zones 0x%x -> %s", r8, g8, b8, zoneMask,
          any ? "ok" : "FAILED");

    IORecursiveLockUnlock(fLock);
    return any ? kIOReturnSuccess : last;
}

// Caller holds fLock.
IOReturn PredatorSenseEC::applyKbEffect(void)
{
    uint8_t buf[kWMIKbLen];
    bzero(buf, sizeof(buf));
    buf[kWMIKbIdxMode]       = (uint8_t)fKbMode;
    // Speed 0 means "no animation" — an animated mode with speed 0 looks
    // identical to a broken one, so floor it.
    uint32_t spd = fKbSpeed;
    if (fKbMode != kKbModeStatic && spd == 0) spd = 1;
    buf[kWMIKbIdxSpeed]      = (uint8_t)spd;
    buf[kWMIKbIdxBrightness] = (uint8_t)fKbBrightness;
    // Byte 3 is 8 for wave. Shifting is the other directional effect and does
    // nothing without it on this firmware, so it gets the same treatment.
    buf[kWMIKbIdxWave]       = (fKbMode == kKbModeWave
                                || fKbMode == kKbModeShifting) ? 8 : 0;
    buf[kWMIKbIdxDirection]  = (uint8_t)fKbDirection;
    buf[kWMIKbIdxRed]        = (uint8_t)fKbR;
    buf[kWMIKbIdxGreen]      = (uint8_t)fKbG;
    buf[kWMIKbIdxBlue]       = (uint8_t)fKbB;
    buf[kWMIKbIdxEnable]     = 1;

    IOReturn r = callWMBH(kWMI_SetGamingKBBacklight, buf, kWMIKbLen,
                          nullptr, nullptr);
    PSLog("KB effect mode=%u speed=%u bright=%u dir=%u rgb=%02x%02x%02x -> 0x%08x",
          fKbMode, fKbSpeed, fKbBrightness, fKbDirection, fKbR, fKbG, fKbB, r);
    return r;
}

IOReturn PredatorSenseEC::setKbEffect(uint32_t mode, uint32_t speed,
                                      uint32_t brightness, uint32_t direction,
                                      uint32_t r8, uint32_t g8, uint32_t b8)
{
    if (mode >= kKbModeCount)               return kIOReturnBadArgument;
    if (speed > kKbSpeedMax)                return kIOReturnBadArgument;
    if (brightness > kKbBrightMax)          return kIOReturnBadArgument;
    if (direction != kKbDirRightLeft && direction != kKbDirLeftRight)
                                            return kIOReturnBadArgument;
    if (r8 > 255 || g8 > 255 || b8 > 255)   return kIOReturnBadArgument;

    IORecursiveLockLock(fLock);
    rearmWMI();
    fKbMode = mode; fKbSpeed = speed; fKbBrightness = brightness;
    fKbDirection = direction; fKbR = r8; fKbG = g8; fKbB = b8;
    IOReturn r = applyKbEffect();
    IORecursiveLockUnlock(fLock);
    return r;
}

// ---------------------------------------------------------------------------
// CPU power profile.
//
// There is no WMI method for this on a PT515-51 — PredatorSense drives Intel
// XTU, which ultimately writes MSR_PKG_POWER_LIMIT. We capture the firmware's
// own PL1/PL2 at first use and express every profile RELATIVE to those, so the
// worst case is the machine's stock behaviour rather than a number we invented.
//
// If bit 63 (the lock bit) is set, the firmware has sealed the MSR until the
// next reset. We report that instead of writing into a register that will
// silently ignore us.
// ---------------------------------------------------------------------------

static inline uint64_t psec_rdmsr(uint32_t msr)
{
    uint32_t lo = 0, hi = 0;
    __asm__ volatile ("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr));
    return ((uint64_t)hi << 32) | lo;
}

static inline void psec_wrmsr(uint32_t msr, uint64_t v)
{
    __asm__ volatile ("wrmsr" : :
        "c"(msr), "a"((uint32_t)(v & 0xFFFFFFFFu)), "d"((uint32_t)(v >> 32)));
}

// PL1/PL2 are in units of (1 / 2^power_unit) watts.
static uint32_t psec_power_unit_divisor(void)
{
    uint64_t u = psec_rdmsr(MSR_RAPL_POWER_UNIT);
    uint32_t p = (uint32_t)(u & 0x0F);
    return 1u << p;                 // typically 8 -> 0.125 W steps
}

// Time windows are a 7-bit float: bits[4:0] = Y, bits[6:5] = Z, and
//     window = 2^Y * (1 + Z/4) * time_unit
// where time_unit = 1 / 2^(MSR_RAPL_POWER_UNIT[19:16]) seconds. Pick the (Y,Z)
// whose product is closest to the requested number of seconds rather than
// hardcoding a magic constant, because the time unit is per-CPU.
static uint32_t psec_encode_tau(uint32_t seconds)
{
    uint64_t u = psec_rdmsr(MSR_RAPL_POWER_UNIT);
    uint32_t texp = (uint32_t)((u >> 16) & 0x0F);   // typically 10 -> ~0.977 ms
    if (texp == 0 || texp > 20) texp = 10;

    uint64_t want = (uint64_t)seconds << texp;      // in time units
    uint32_t best = 0;
    uint64_t bestErr = ~0ULL;
    for (uint32_t y = 0; y < 32; y++) {
        for (uint32_t z = 0; z < 4; z++) {
            uint64_t v = ((1ULL << y) * (4 + z)) / 4;
            uint64_t err = (v > want) ? (v - want) : (want - v);
            if (err < bestErr) { bestErr = err; best = (z << 5) | y; }
        }
    }
    return best & 0x7F;
}

bool PredatorSenseEC::capturePowerLimits(void)
{
    if (fPowerCaptured) return true;
    uint64_t v = psec_rdmsr(MSR_PKG_POWER_LIMIT);
    if (v == 0) return false;

    fPowerLocked = (v >> 63) & 1;
    uint32_t div = psec_power_unit_divisor();
    if (!div) return false;

    fBasePl1mW = (uint32_t)(((v & 0x7FFF) * 1000ull) / div);
    fBasePl2mW = (uint32_t)((((v >> 32) & 0x7FFF) * 1000ull) / div);
    fPl1mW = fBasePl1mW;
    fPl2mW = fBasePl2mW;
    fPowerCaptured = true;
    PSLog("firmware power limits: PL1 %u mW, PL2 %u mW%s",
          fBasePl1mW, fBasePl2mW, fPowerLocked ? " (LOCKED by firmware)" : "");
    return true;
}

IOReturn PredatorSenseEC::applyPowerProfile(void)
{
    if (!capturePowerLimits()) return kIOReturnIOError;
    if (fPowerLocked) return kIOReturnNotPermitted;

    uint32_t wantPl1mW = 0, wantPl2mW = 0;
    switch (fPowerProfile) {
        case kPSPowerLow:
            wantPl1mW = fBasePl1mW * 50 / 100;
            wantPl2mW = fBasePl2mW * 65 / 100;
            break;
        case kPSPowerBalanced:
            wantPl1mW = fBasePl1mW;                 // exactly what Acer ships
            wantPl2mW = fBasePl2mW;
            break;
        case kPSPowerPerformance:
            // Turbo: raise BOTH limits. PL2 is the burst; PL1 is the sustained
            // ceiling that actually decides multi-core throughput once tau
            // expires. Leaving PL1 at the firmware's 45 W was measured on
            // 2026-09-02 to clamp all-core to ~3.15 GHz at only 62-67 C, with
            // ~30 C of headroom below Tjmax going unused. PSEC_THERMAL_CEILING_C
            // is the backstop if this ever does run hot.
            wantPl1mW = fBasePl1mW;   // see 6.8: EC enforces 45 W below the OS
            wantPl2mW = PSEC_PERF_PL2_MW;
            break;
        default: return kIOReturnBadArgument;
    }
    if (wantPl1mW > PSEC_PL_ABS_MAX_MW) wantPl1mW = PSEC_PL_ABS_MAX_MW;
    if (wantPl2mW > PSEC_PL_ABS_MAX_MW) wantPl2mW = PSEC_PL_ABS_MAX_MW;
    if (wantPl2mW < wantPl1mW)          wantPl2mW = wantPl1mW;

    uint32_t div = psec_power_unit_divisor();
    if (!div) return kIOReturnIOError;
    uint64_t pl1 = (uint64_t)wantPl1mW * div / 1000ull;
    uint64_t pl2 = (uint64_t)wantPl2mW * div / 1000ull;
    if (pl1 == 0 || pl2 == 0) return kIOReturnIOError;
    if (pl1 > 0x7FFF) pl1 = 0x7FFF;
    if (pl2 > 0x7FFF) pl2 = 0x7FFF;

    uint64_t v = psec_rdmsr(MSR_PKG_POWER_LIMIT);
    v &= ~0x7FFFull;              v |= (pl1 & 0x7FFF);
    v &= ~(0x7FFFull << 32);      v |= ((pl2 & 0x7FFF) << 32);
    v |= (1ull << 15);            // PL1 enable
    v |= (1ull << 47);            // PL2 enable
    v &= ~(1ull << 16);           // PL1 clamp OFF — clamping is what forces the
    v &= ~(1ull << 48);           // core below its guaranteed ratio.

    // Time windows. On Balanced/Low leave the firmware's own values alone;
    // only Performance asks for the long burst.
    if (fPowerProfile == kPSPowerPerformance) {
        uint64_t tau = psec_encode_tau(PSEC_PERF_TAU_SEC);
        v &= ~(0x7Full << 17);   v |= (tau << 17);      // PL1 window
        v &= ~(0x7Full << 49);   v |= (tau << 49);      // PL2 window
    }
    psec_wrmsr(MSR_PKG_POWER_LIMIT, v);

    // Read back. A silently ignored or capped write must not be reported as
    // success.  In particular, this chassis' firmware default is PL2 = 75 W;
    // reporting the requested 90 W here hid a firmware cap from the app.
    uint64_t rb = psec_rdmsr(MSR_PKG_POWER_LIMIT);
    if ((rb & 0x7FFF) != (pl1 & 0x7FFF)) {
        PSLog("PL1 write ignored by hardware (wanted %llu, got %llu)",
              pl1, rb & 0x7FFF);
        // Not "locked": that is bit 63 only, read at start. Marking it here
        // greyed out the power picker until reboot after one bad write.
        return kIOReturnNotPermitted;
    }

    if (((rb >> 32) & 0x7FFF) != (pl2 & 0x7FFF)) {
        uint64_t actual = (rb >> 32) & 0x7FFF;
        fPl1mW = (uint32_t)(((rb & 0x7FFF) * 1000ull) / div);
        fPl2mW = (uint32_t)((actual * 1000ull) / div);
        PSLog("PL2 capped by hardware: asked %llu, got %llu (%u mW)",
              pl2, actual, fPl2mW);
        // Partial success: PL1 took, PL2 is whatever the firmware allows. The
        // actual value is reported above; failing here rolled Turbo back.
        return kIOReturnSuccess;
    }

    // Make sure Turbo itself is actually enabled. Bit 38 of IA32_MISC_ENABLE is
    // "Turbo Mode DISABLE" — some firmware sets it, and then every power limit
    // in the world buys nothing.
    if (fPowerProfile == kPSPowerPerformance) {
        uint64_t me = psec_rdmsr(MSR_IA32_MISC_ENABLE);
        if (me & (1ull << 38)) {
            psec_wrmsr(MSR_IA32_MISC_ENABLE, me & ~(1ull << 38));
            uint64_t me2 = psec_rdmsr(MSR_IA32_MISC_ENABLE);
            PSLog("turbo was disabled in IA32_MISC_ENABLE — %s",
                  (me2 & (1ull << 38)) ? "could NOT clear it" : "cleared");
        }
    }

    fPl1mW = (uint32_t)((pl1 * 1000ull) / div);
    fPl2mW = (uint32_t)((pl2 * 1000ull) / div);
    PSLog("power profile %u: PL1 %u mW, PL2 %u mW, tau %u s "
          "(firmware was %u / %u)",
          fPowerProfile, fPl1mW, fPl2mW,
          fPowerProfile == kPSPowerPerformance ? PSEC_PERF_TAU_SEC : 0,
          fBasePl1mW, fBasePl2mW);
    return kIOReturnSuccess;
}

IOReturn PredatorSenseEC::setPowerProfile(uint32_t profile)
{
    if (profile > kPSPowerPerformance) return kIOReturnBadArgument;
    IORecursiveLockLock(fLock);
    uint32_t prev = fPowerProfile;
    fPowerProfile = profile;
    IOReturn r = applyPowerProfile();
    if (r != kIOReturnSuccess) fPowerProfile = prev;
    IORecursiveLockUnlock(fLock);
    return r;
}

// ---------------------------------------------------------------------------

bool PredatorSenseEC::readNamed(const char *name, uint32_t *out)
{
    if (!fEC || !out) return false;
    UInt64 v = 0;
    if (fEC->evaluateInteger(name, &v) != kIOReturnSuccess) return false;
    *out = (uint32_t)v;
    return true;
}

// IOACPIAddress is a union, not an integer — for the EC address space the
// whole 64-bit field is just the byte offset into EC RAM.
static inline IOACPIAddress psec_addr(uint8_t offset)
{
    IOACPIAddress a;
    a.addr64 = (UInt64)offset;
    return a;
}

bool PredatorSenseEC::readEC(uint8_t offset, uint32_t *out)
{
    if (!fEC || !out) return false;
    UInt64 v = 0;
    IOReturn r = fEC->readAddressSpace(&v, kIOACPIAddressSpaceIDEmbeddedController,
                                       psec_addr(offset), 8, 0, 0);
    if (r != kIOReturnSuccess) { fLastError = r; return false; }
    *out = (uint32_t)(v & 0xFF);
    return true;
}

bool PredatorSenseEC::writeEC(uint8_t offset, uint32_t value)
{
    if (!fEC) return false;
    IOReturn r = fEC->writeAddressSpace((UInt64)(value & 0xFF),
                                        kIOACPIAddressSpaceIDEmbeddedController,
                                        psec_addr(offset), 8, 0, 0);
    if (r != kIOReturnSuccess) {
        fLastError = r;
        PSLog("EC write 0x%02x = 0x%02x FAILED (0x%08x)", offset, value, r);
        return false;
    }
    return true;
}

// Capture the EC's own mode bytes before we ever write one.
bool PredatorSenseEC::captureAutoMode(void)
{
    if (fAutoCaptured) return true;
    uint32_t m1 = 0, m2 = 0;
    if (!readEC(PSEC_REG_F1ST, &m1) || !readEC(PSEC_REG_F2ST, &m2))
        return false;
    // If the manual bit is somehow already set, strip it — we want the
    // firmware's automatic state, not a leftover manual one.
    fAutoMode1 = m1 & ~(uint32_t)PSEC_MODE_MANUAL_BIT;
    fAutoMode2 = m2 & ~(uint32_t)PSEC_MODE_MANUAL_BIT;
    fAutoCaptured = true;
    PSLog("captured auto mode bytes: F1ST=0x%02x F2ST=0x%02x", fAutoMode1, fAutoMode2);
    return true;
}

// ---------------------------------------------------------------------------
// Fan state
// ---------------------------------------------------------------------------

IOReturn PredatorSenseEC::applyFanState(void)
{
    uint32_t mode = fFanMode;
    if (fThermalTripped || fWatchdogTripped)
        mode = kPSECFanModeAuto;

    // --- preferred path: the same WMI calls PredatorSense itself makes -------
    //
    // Direct EC RAM writes were proven not to stick: the dump showed F1ST
    // reading 0x04 on every sample even while we were writing 0x14, because the
    // EC's own control loop rewrites the register between our poll intervals.
    // The SMM handler behind WMBH is what makes the mode change authoritative.
    // GFGB also proves any duty <= GFMS reads back as MAX, which is why every
    // slider position produced full speed — SetGamingFanSpeed takes a true
    // percentage instead and does not go through that decode.
    if (fWMI || (fWMIFindTries < 3 && findWMI())) {
        if (mode == kPSECFanModeAuto) {
            IOReturn r = callWMBH64(kWMI_SetGamingFanBehavior,
                                    WMI_FAN_BEHAVIOR(kWMIFanAuto));
            if (r == kIOReturnSuccess) { fHwFanMode = kPSECFanModeAuto; return r; }
            PSLog("WMI auto failed — falling back to EC writes");
        } else {
            uint32_t p1 = fFan1Pct, p2 = fFan2Pct;
            if (p1 < PSEC_MIN_DUTY_PERCENT) p1 = PSEC_MIN_DUTY_PERCENT;
            if (p2 < PSEC_MIN_DUTY_PERCENT) p2 = PSEC_MIN_DUTY_PERCENT;
            if (p1 > 100) p1 = 100;
            if (p2 > 100) p2 = 100;

            // 100% means MAX BEHAVIOUR, not "custom curve at 100".
            //
            // The GPU fan was topping out around 4000 RPM where the CPU fan
            // reaches 6000+. That is the custom-curve ceiling, not the fan's
            // ceiling: GFMS gives per-fan maxima of 102 (CPU) and 78 (GPU), and
            // custom mode is bounded by them, so the GPU fan's "100%" is a
            // lower absolute speed than the CPU fan's. Mode 2 (MAX) is the
            // separate path the firmware uses for its own max-fan button and is
            // not bounded that way — it is what actually reaches 6000+.
            //
            // Modes are per-slot, so one fan can sit on its curve while the
            // other runs flat out.
            uint32_t gpuMode = (p2 >= 100) ? kWMIFanMax : kWMIFanCustom;
            uint32_t cpuMode = (p1 >= 100) ? kWMIFanMax : kWMIFanCustom;

            IOReturn r = callWMBH64(kWMI_SetGamingFanBehavior,
                                    WMI_FAN_BEHAVIOR2(gpuMode, cpuMode));
            if (r == kIOReturnSuccess) {
                // A slot in MAX mode ignores its speed value; sending it anyway
                // is harmless and keeps the firmware's stored percentage in
                // step with what we report.
                IOReturn a = callWMBH64(kWMI_SetGamingFanSpeed,
                                        WMI_FAN_SPEED(kWMIFanIdCPU1, p1));
                IOReturn b = callWMBH64(kWMI_SetGamingFanSpeed,
                                        WMI_FAN_SPEED(kWMIFanIdGPU1, p2));
                if (a == kIOReturnSuccess && b == kIOReturnSuccess) {
                    fFan1Raw = p1;
                    fFan2Raw = p2;
                    fHwFanMode = kPSECFanModeManual;
                    return kIOReturnSuccess;
                }
                // Partial application is worse than none.
                callWMBH64(kWMI_SetGamingFanBehavior,
                           WMI_FAN_BEHAVIOR(kWMIFanAuto));
                PSLog("WMI fan speed failed — falling back to EC writes");
            } else {
                PSLog("WMI custom behavior failed — falling back to EC writes");
            }
        }
    }

    // --- fallback: direct EC RAM ------------------------------------------
    //
    // These guards belong HERE, not at the top of the function. Gating the
    // whole thing on the EC meant a machine where the EC lookup failed but
    // WMBH worked lost fan control completely — while Turbo and RGB kept
    // working, which would look arbitrary.
    if (!fEC) return kIOReturnNotReady;
    if (!captureAutoMode()) return kIOReturnIOError;

    if (mode == kPSECFanModeAuto) {
        bool ok = writeEC(PSEC_REG_F1ST, fAutoMode1)
               && writeEC(PSEC_REG_F2ST, fAutoMode2);
        if (!ok) return kIOReturnIOError;   // fHwFanMode deliberately unchanged
        fHwFanMode = kPSECFanModeAuto;
        return kIOReturnSuccess;
    }

    // Manual.
    //
    // IMPORTANT — from Method (GFGB) in this machine's SSDT1:
    //     if (F1ST & 0x10) { if (F1WS <= GFMS(fan)) MAX else CUSTOM }
    // so any duty <= the firmware maximum is interpreted as MAX MODE and the
    // fan runs flat out. Writing 35..102 therefore all mean "maximum", which is
    // exactly the behaviour observed: every slider position gave full speed.
    //
    // The encoding for genuine custom duty is NOT yet established. Until it is,
    // manual mode writes the firmware's own MAX sequence (F1ST=0x14 plus duty =
    // GFMS) rather than pretending a slider position is being honoured.
    uint32_t r1 = PSEC_FAN1_MAX_DUTY;
    uint32_t r2 = PSEC_FAN2_MAX_DUTY;

    if (!writeEC(PSEC_REG_F1WS, r1) || !writeEC(PSEC_REG_F2WS, r2)) {
        PSLog("duty write failed — reverting to auto");
        writeEC(PSEC_REG_F1ST, fAutoMode1);
        writeEC(PSEC_REG_F2ST, fAutoMode2);
        fHwFanMode = kPSECFanModeAuto;
        fFanMode   = kPSECFanModeAuto;
        return kIOReturnIOError;
    }

    if (!writeEC(PSEC_REG_F1ST, fAutoMode1 | PSEC_MODE_MANUAL_BIT) ||
        !writeEC(PSEC_REG_F2ST, fAutoMode2 | PSEC_MODE_MANUAL_BIT)) {
        PSLog("mode write failed — reverting to auto");
        writeEC(PSEC_REG_F1ST, fAutoMode1);
        writeEC(PSEC_REG_F2ST, fAutoMode2);
        fHwFanMode = kPSECFanModeAuto;
        fFanMode   = kPSECFanModeAuto;
        return kIOReturnIOError;
    }

    fFan1Raw = r1;
    fFan2Raw = r2;
    fEcManualEngaged = true;    // F1ST/F2ST now carry the manual bit
    fHwFanMode = kPSECFanModeManual;
    return kIOReturnSuccess;
}

IOReturn PredatorSenseEC::revertToAuto(const char *reason, bool clearDesired)
{
    if (!fWMI && (!fEC || !fAutoCaptured)) return kIOReturnNotReady;

    IORecursiveLockLock(fLock);
    bool ok = false;

    // Prefer WMI if we ever successfully used it — that is the path that
    // actually took control, so it is the path that must give it back.
    if (fWMI) {
        ok = (callWMBH64(kWMI_SetGamingFanBehavior,
                         WMI_FAN_BEHAVIOR(kWMIFanAuto)) == kIOReturnSuccess);
    }
    // If the EC fallback ever set the manual bit, it MUST be cleared even when
    // the WMI call above succeeds. Otherwise: WMI fails once, the EC fallback
    // engages, the next revert's WMI call succeeds, this block is skipped, and
    // 0x14 stays in F1ST with duty at maximum — fans pinned flat out while the
    // driver logs "returned to EC control".
    if (fEC && fAutoCaptured && (fEcManualEngaged || !ok)) {
        bool ecOk = writeEC(PSEC_REG_F1ST, fAutoMode1)
                 && writeEC(PSEC_REG_F2ST, fAutoMode2);
        if (ecOk) fEcManualEngaged = false;
        ok = ok || ecOk;
    }
    if (ok) {
        if (fHwFanMode != kPSECFanModeAuto)
            PSLog("fans returned to EC control (%s)", reason ? reason : "?");
        fHwFanMode = kPSECFanModeAuto;
        if (clearDesired) fFanMode = kPSECFanModeAuto;
    } else {
        // Do NOT claim auto. Leaving the desired mode alone keeps the
        // watchdog retrying on every tick.
        PSLog("revertToAuto(%s) FAILED — will keep retrying", reason ? reason : "?");
    }
    IORecursiveLockUnlock(fLock);
    return ok ? kIOReturnSuccess : kIOReturnIOError;
}

IOReturn PredatorSenseEC::setFanMode(uint32_t mode)
{
    if (mode != kPSECFanModeAuto && mode != kPSECFanModeManual)
        return kIOReturnBadArgument;
    IORecursiveLockLock(fLock);
    rearmWMI();
    fFanMode = mode;
    if (mode == kPSECFanModeManual) {
        fWatchdogTripped = false;
        fLastPingMs = nowMs();
    }
    IOReturn r = applyFanState();
    IORecursiveLockUnlock(fLock);
    return r;
}

IOReturn PredatorSenseEC::setDuty(uint32_t p1, uint32_t p2)
{
    if (p1 > 100 || p2 > 100) return kIOReturnBadArgument;
    IORecursiveLockLock(fLock);
    fFan1Pct = p1;
    fFan2Pct = p2;
    fLastPingMs = nowMs();
    IOReturn r = (fFanMode == kPSECFanModeManual) ? applyFanState() : kIOReturnSuccess;
    IORecursiveLockUnlock(fLock);
    return r;
}

IOReturn PredatorSenseEC::ping(void)
{
    IORecursiveLockLock(fLock);
    fLastPingMs = nowMs();
    if (fWatchdogTripped) {
        fWatchdogTripped = false;
        applyFanState();
    }
    IORecursiveLockUnlock(fLock);
    return kIOReturnSuccess;
}

// ---------------------------------------------------------------------------

IOReturn PredatorSenseEC::ecReadRaw(uint32_t offset, uint32_t *out)
{
    if (offset < PSEC_RAW_MIN_OFFSET || offset > PSEC_RAW_MAX_OFFSET)
        return kIOReturnBadArgument;
    IORecursiveLockLock(fLock);
    bool ok = readEC((uint8_t)offset, out);
    IORecursiveLockUnlock(fLock);
    return ok ? kIOReturnSuccess : kIOReturnIOError;
}

IOReturn PredatorSenseEC::ecWriteRaw(uint32_t offset, uint32_t value)
{
    // Fenced to the fan block so an offset typo cannot reach battery or
    // thermal-trip registers.
    if (offset < PSEC_RAW_MIN_OFFSET || offset > PSEC_RAW_MAX_OFFSET)
        return kIOReturnBadArgument;
    IORecursiveLockLock(fLock);
    PSLog("raw EC write 0x%02x = 0x%02x", offset, value);
    bool ok = writeEC((uint8_t)offset, value);
    IORecursiveLockUnlock(fLock);
    return ok ? kIOReturnSuccess : kIOReturnIOError;
}

void PredatorSenseEC::refreshSensors(void)
{
    uint32_t v = 0;
    fCpuTempC = readNamed("MS0T", &v) && v < 0x7F ? (int32_t)v : -1;
    fGpuTempC = readNamed("MS1T", &v) && v < 0x7F ? (int32_t)v : -1;

    // Tach by NAME. readAddressSpace was returning stale values here while
    // evaluateInteger works reliably for the same fields, so RPM appeared
    // frozen. Names are the proven path; keep the raw reads for diagnosis only.
    //
    // SENSOR MAPPING IS CROSSED, and this is measured, not assumed. With both
    // fans pinned at MAX the machine reported F1RS = 4772 and F2RS = 6221, and
    // the 6221 one is audibly the CPU-side fan. So the EC's F1 channel is the
    // GPU fan and F2 is the CPU fan — the opposite of what the register names
    // suggest, and the same crossing already found in the WMI fan ordinals.
    //
    // fFan1* is what userspace labels "CPU", so it must be fed from F2.
    if (readNamed("F2RS", &v))
        fFan1RPM = (v == 0 || v == 0xFF) ? 0 : (0x78000u / v);   // CPU
    if (readNamed("F1RS", &v))
        fFan2RPM = (v == 0 || v == 0xFF) ? 0 : (0x78000u / v);   // GPU
    if (readNamed("F2ST", &v)) fFan1Status = v;
    if (readNamed("F1ST", &v)) fFan2Status = v;
}

// Plain helper rather than a lambda — lambdas and -fapple-kext are a needless
// risk in a build we cannot test locally.
static void psec_num(IOService *self, const char *k, uint32_t v)
{
    if (OSNumber *n = OSNumber::withNumber(v, 32)) {
        self->setProperty(k, n);
        n->release();
    }
}

void PredatorSenseEC::publishAll(void)
{
    #define num(k, v) psec_num(this, (k), (v))
    num("CPU_Temp_C", fCpuTempC < 0 ? 0 : (uint32_t)fCpuTempC);
    num("GPU_Temp_C", fGpuTempC < 0 ? 0 : (uint32_t)fGpuTempC);
    num("Fan1_RPM", fFan1RPM);
    num("Fan2_RPM", fFan2RPM);
    bool manual = (fHwFanMode == kPSECFanModeManual);
    num("Fan1_Duty_Raw", manual ? fFan1Raw : 0);
    num("Fan2_Duty_Raw", manual ? fFan2Raw : 0);
    setProperty("FanMode", manual ? "manual" : "auto");
    setProperty("ControlPath", fWMI ? "WMI (WMBH)" : "EC RAM");
    setProperty("WMI_Present", fWMI != nullptr);
    setProperty("Turbo", fTurboOn);
    setProperty("LCD_Overdrive", fLcdOdOn);
    num("Power_Profile", fPowerProfile);
    if (fPowerCaptured) { num("PL1_mW", fPl1mW); num("PL2_mW", fPl2mW); }

    // Every fan channel, raw, so the actual EC state is visible rather than
    // inferred. Channel 3 is included because which channel drives the GPU fan
    // on this chassis is not yet established.
    uint32_t rv = 0;
    if (readEC(PSEC_REG_F1ST, &rv)) num("EC_F1ST_93", rv);
    if (readEC(PSEC_REG_F1WS, &rv)) num("EC_F1WS_94", rv);
    if (readEC(PSEC_REG_F1WS + 1, &rv)) num("EC_F1RS_95", rv);
    if (readEC(PSEC_REG_F2ST, &rv)) num("EC_F2ST_96", rv);
    if (readEC(PSEC_REG_F2WS, &rv)) num("EC_F2WS_97", rv);
    if (readEC(PSEC_REG_F2WS + 1, &rv)) num("EC_F2RS_98", rv);
    if (readEC(PSEC_REG_F3ST, &rv)) num("EC_F3ST_9A", rv);
    if (readEC(PSEC_REG_F3WS, &rv)) num("EC_F3WS_9B", rv);
    if (readEC(PSEC_REG_F3RS, &rv)) num("EC_F3RS_9C", rv);
    if (fThermalTripped)  setProperty("Status", "THERMAL OVERRIDE — forced auto");
    else if (fWatchdogTripped) setProperty("Status", "watchdog — forced auto");
    else setProperty("Status", "ok");
    #undef num
}

void PredatorSenseEC::poll(IOTimerEventSource *sender)
{
    IORecursiveLockLock(fLock);

    if (!fEC) {
        if (!findEC()) {
            if (++fFindTries >= 5) {
                setProperty("Status", "EC not found");
                IORecursiveLockUnlock(fLock);
                return;
            }
            IORecursiveLockUnlock(fLock);
            if (fTimer) fTimer->setTimeoutMS(PSEC_POLL_INTERVAL_MS);
            return;
        }
        captureAutoMode();
    }

    refreshSensors();

    // 1. Thermal ceiling — real EC sensor, overrides the user unconditionally.
    //
    // Uses the HOTTER of the two sensors. The fan channels turned out to be
    // crossed relative to their register names; I have no evidence either way
    // about MS0T/MS1T, and a ceiling watching the wrong die is worse than a
    // ceiling that occasionally trips early. Whichever is which, this is right.
    int32_t hottest = fCpuTempC > fGpuTempC ? fCpuTempC : fGpuTempC;
    bool over = (hottest >= 0 && hottest >= PSEC_THERMAL_CEILING_C);
    if (over && !fThermalTripped)
        PSLog("%dC >= ceiling %d — forcing auto", hottest, PSEC_THERMAL_CEILING_C);
    if (over) fThermalTripped = true;
    else if (fThermalTripped && hottest >= 0 && hottest < PSEC_THERMAL_RELEASE_C) {
        PSLog("back to %dC — releasing thermal override", hottest);
        fThermalTripped = false;
    }

    // 2. Liveness — only matters while we are holding the fans manually.
    if (fFanMode == kPSECFanModeManual && !fWatchdogTripped &&
        (nowMs() - fLastPingMs) > PSEC_WATCHDOG_TIMEOUT_MS) {
        PSLog("no keepalive — forcing auto");
        fWatchdogTripped = true;
    }

    // 3. Reconcile desired vs EC-confirmed. Any earlier failed write is retried
    //    here, every tick, so one dropped transaction can never leave the fans
    //    stranded or the ceiling disarmed.
    uint32_t want = (fThermalTripped || fWatchdogTripped) ? kPSECFanModeAuto : fFanMode;
    if (fHwFanMode != want)
        applyFanState();

    publishAll();
    IORecursiveLockUnlock(fLock);

    if (fTimer) fTimer->setTimeoutMS(PSEC_POLL_INTERVAL_MS);
}

IOReturn PredatorSenseEC::getStatus(PSECStatus *out)
{
    if (!out) return kIOReturnBadArgument;
    IORecursiveLockLock(fLock);
    bzero(out, sizeof(*out));
    out->version        = kPSECStatusVersion;
    out->fanMode        = fFanMode;
    out->hwFanMode      = fHwFanMode;
    out->fan1Percent    = fFan1Pct;
    out->fan2Percent    = fFan2Pct;
    out->fan1RawDuty    = fFan1Raw;
    out->fan2RawDuty    = fFan2Raw;
    out->fan1RPM        = fFan1RPM;
    out->fan2RPM        = fFan2RPM;
    out->fan1Status     = fFan1Status;
    out->fan2Status     = fFan2Status;
    out->cpuTempC       = fCpuTempC;
    out->gpuTempC       = fGpuTempC;
    out->autoModeByte1  = fAutoMode1;
    out->autoModeByte2  = fAutoMode2;
    out->thermalTripped = fThermalTripped ? 1 : 0;
    out->watchdogTripped= fWatchdogTripped ? 1 : 0;
    out->ecPresent      = fEC ? 1 : 0;
    out->lastError      = (uint32_t)fLastError;
    out->wmiPresent     = fWMI ? 1 : 0;
    out->turboOn        = fTurboOn ? 1 : 0;
    out->lcdOverdriveOn = fLcdOdOn ? 1 : 0;
    out->powerProfile   = fPowerProfile;
    out->pl1Milliwatts  = fPl1mW;
    out->pl2Milliwatts  = fPl2mW;
    out->powerLimitsLocked = fPowerLocked ? 1 : 0;
    out->lastWMIStatus  = fLastWMIStatus;
    out->rgbStatusKB    = fRgbStatusKB;
    out->rgbStatusLED   = fRgbStatusLED;
    out->rgbStatusRgbKb = fRgbStatusRgbKb;
    out->kbMode         = fKbMode;
    out->kbSpeed        = fKbSpeed;
    out->kbBrightness   = fKbBrightness;
    out->kbDirection    = fKbDirection;
    out->kbRed          = fKbR;
    out->kbGreen        = fKbG;
    out->kbBlue         = fKbB;
    IORecursiveLockUnlock(fLock);
    return kIOReturnSuccess;
}

void PredatorSenseEC::clientAttached(void)
{
    IORecursiveLockLock(fLock);
    fClients++;
    fLastPingMs = nowMs();
    IORecursiveLockUnlock(fLock);
}

void PredatorSenseEC::clientDetached(void)
{
    IORecursiveLockLock(fLock);
    if (fClients) fClients--;
    bool none = (fClients == 0);
    IORecursiveLockUnlock(fLock);
    if (none) revertToAuto("last client disconnected");
}
