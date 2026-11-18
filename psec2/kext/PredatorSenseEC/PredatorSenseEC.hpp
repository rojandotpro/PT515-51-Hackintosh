//
//  PredatorSenseEC.hpp — driver + user client declarations.
//

#ifndef PredatorSenseEC_hpp
#define PredatorSenseEC_hpp

#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/IOWorkLoop.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>

#include "PSECShared.h"

class PredatorSenseEC : public IOService
{
    OSDeclareDefaultStructors(PredatorSenseEC)

public:
    virtual bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual void stop(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual IOReturn setPowerState(unsigned long which, IOService *whom) APPLE_KEXT_OVERRIDE;

    // Called by the user client.
    IOReturn setFanMode(uint32_t mode);
    IOReturn setDuty(uint32_t fan1Pct, uint32_t fan2Pct);
    IOReturn getStatus(PSECStatus *out);
    IOReturn ping(void);
    IOReturn ecReadRaw(uint32_t offset, uint32_t *out);   // fenced to the fan block
    IOReturn ecWriteRaw(uint32_t offset, uint32_t value);

    IOReturn setTurbo(uint32_t on);
    IOReturn setLcdOverdrive(uint32_t on);
    IOReturn setRgb(uint32_t zoneMask, uint32_t r, uint32_t g, uint32_t b);
    IOReturn setPowerProfile(uint32_t profile);
    IOReturn rawWMI(const PSECWMIRequest *req, PSECWMIReply *rep);
    IOReturn setKbEffect(uint32_t mode, uint32_t speed, uint32_t brightness,
                         uint32_t direction, uint32_t r, uint32_t g, uint32_t b);

    void clientAttached(void);
    void clientDetached(void);

    // Hand the fans back to the EC. Safe from any failure path.
    IOReturn revertToAuto(const char *reason, bool clearDesired = true);

private:
    IOACPIPlatformDevice *  fEC             { nullptr };
    IOACPIPlatformDevice *  fWMI            { nullptr };
    IOWorkLoop *            fWorkLoop       { nullptr };
    IOTimerEventSource *    fTimer          { nullptr };
    IORecursiveLock *       fLock           { nullptr };

    uint32_t    fFanMode        { kPSECFanModeAuto };   // desired
    uint32_t    fHwFanMode      { kPSECFanModeAuto };   // EC-confirmed
    uint32_t    fFan1Pct        { 60 };
    uint32_t    fFan2Pct        { 60 };
    uint32_t    fFan1Raw        { 0 };
    uint32_t    fFan2Raw        { 0 };

    // Captured BEFORE we ever write, so "auto" restores exactly what the
    // firmware had rather than a value we invented.
    uint32_t    fAutoMode1      { 0 };
    uint32_t    fAutoMode2      { 0 };
    bool        fAutoCaptured   { false };
    bool        fEcManualEngaged{ false };   // EC manual bit is set right now

    bool        fThermalTripped { false };
    bool        fWatchdogTripped{ false };
    uint32_t    fClients        { 0 };
    uint64_t    fLastPingMs     { 0 };
    int         fFindTries      { 0 };
    IOReturn    fLastError      { kIOReturnSuccess };
    int32_t     fCpuTempC       { -1 };
    int32_t     fGpuTempC       { -1 };
    uint32_t    fFan1RPM        { 0 };
    uint32_t    fFan2RPM        { 0 };
    uint32_t    fFan1Status     { 0 };
    uint32_t    fFan2Status     { 0 };

    bool        fTurboOn        { false };
    // What the user had before Turbo, restored when Turbo turns off.
    uint32_t    fPreTurboFanMode { 0 };
    uint32_t    fPreTurboFan1Pct { 60 };
    uint32_t    fPreTurboFan2Pct { 60 };
    uint32_t    fPreTurboProfile { 1 };
    bool        fLcdOdOn        { false };
    uint32_t    fPowerProfile   { kPSPowerBalanced };
    uint32_t    fPl1mW          { 0 };
    uint32_t    fPl2mW          { 0 };
    uint32_t    fBasePl1mW      { 0 };
    uint32_t    fBasePl2mW      { 0 };
    bool        fPowerCaptured  { false };
    bool        fPowerLocked    { false };
    uint64_t    fLastWMIStatus  { 0 };
    int         fWMIFindTries   { 0 };
    uint32_t    fRgbStatusKB    { 0xFFFFFFFF };   // per-candidate RGB results
    uint32_t    fRgbStatusLED   { 0xFFFFFFFF };
    uint32_t    fRgbStatusRgbKb { 0xFFFFFFFF };
    uint32_t    fKbMode       { kKbModeStatic };
    uint32_t    fKbSpeed      { 5 };
    uint32_t    fKbBrightness { 100 };
    uint32_t    fKbDirection  { kKbDirLeftRight };
    uint32_t    fKbR          { 255 };
    uint32_t    fKbG          { 0 };
    uint32_t    fKbB          { 0 };
    IOReturn    applyKbEffect(void);

    bool        findEC(void);
    bool        findWMI(void);
    void        rearmWMI(void);
    IOReturn    callWMBH(uint32_t methodId, const void *in, uint32_t inLen,
                         uint8_t *out, uint32_t *outLen);
    IOReturn    callWMBH64(uint32_t methodId, uint64_t payload);
    IOReturn    callWMBH32(uint32_t methodId, uint32_t arg, uint64_t *out);
    bool        capturePowerLimits(void);
    IOReturn    applyPowerProfile(void);
    bool        readNamed(const char *name, uint32_t *out);
    bool        readEC(uint8_t offset, uint32_t *out);
    bool        writeEC(uint8_t offset, uint32_t value);

    bool        captureAutoMode(void);
    IOReturn    applyFanState(void);
    void        poll(IOTimerEventSource *sender);
    void        refreshSensors(void);
    void        publishAll(void);

    static uint32_t pctToRaw(uint32_t pct, uint32_t maxDuty);
    static uint64_t nowMs(void);
};

class PSECUserClient : public IOUserClient
{
    OSDeclareDefaultStructors(PSECUserClient)

public:
    virtual bool     initWithTask(task_t owningTask, void *securityID,
                                  UInt32 type, OSDictionary *properties) APPLE_KEXT_OVERRIDE;
    virtual bool     start(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual void     stop(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual IOReturn clientClose(void) APPLE_KEXT_OVERRIDE;
    virtual IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                                    IOExternalMethodDispatch *dispatch, OSObject *target,
                                    void *reference) APPLE_KEXT_OVERRIDE;

    static IOReturn sSetFanMode(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sSetDuty(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sGetStatus(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sPing(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sECRead(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sECWrite(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sSetTurbo(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sSetLcdOverdrive(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sSetRgb(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sSetPowerProfile(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sRawWMI(OSObject *t, void *r, IOExternalMethodArguments *a);
    static IOReturn sSetKbEffect(OSObject *t, void *r, IOExternalMethodArguments *a);

private:
    void releaseDriver(void);
    PredatorSenseEC *   fDriver   { nullptr };
    bool                fAttached { false };
};

#endif /* PredatorSenseEC_hpp */
