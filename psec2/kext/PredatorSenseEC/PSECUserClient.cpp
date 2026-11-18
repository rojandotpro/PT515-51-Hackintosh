//
//  PSECUserClient.cpp
//

#include "PredatorSenseEC.hpp"

#define super IOUserClient
OSDefineMetaClassAndStructors(PSECUserClient, IOUserClient)

#define UCLog(fmt, ...) IOLog("PSECUserClient: " fmt "\n", ## __VA_ARGS__)

// Order MUST match the kPSECMethod* enum in PSECShared.h.
static const IOExternalMethodDispatch gMethods[kPSECMethodCount] =
{
    // function                        scalarIn structIn scalarOut structOut
    { &PSECUserClient::sSetFanMode,     1, 0, 0, 0 },
    { &PSECUserClient::sSetDuty,        2, 0, 0, 0 },
    { &PSECUserClient::sGetStatus,      0, 0, 0, sizeof(PSECStatus) },
    { &PSECUserClient::sPing,           0, 0, 0, 0 },
    { &PSECUserClient::sECRead,         1, 0, 1, 0 },
    { &PSECUserClient::sECWrite,        2, 0, 0, 0 },
    { &PSECUserClient::sSetTurbo,       1, 0, 0, 0 },
    { &PSECUserClient::sSetLcdOverdrive,1, 0, 0, 0 },
    { &PSECUserClient::sSetRgb,         4, 0, 0, 0 },
    { &PSECUserClient::sSetPowerProfile,1, 0, 0, 0 },
    { &PSECUserClient::sRawWMI,         0, sizeof(PSECWMIRequest),
                                        0, sizeof(PSECWMIReply) },
    { &PSECUserClient::sSetKbEffect,    7, 0, 0, 0 },
};

bool PSECUserClient::initWithTask(task_t owningTask, void *securityID,
                                  UInt32 type, OSDictionary *properties)
{
    if (!super::initWithTask(owningTask, securityID, type, properties))
        return false;

    // Fan control is root-only. Without this any process could hold the fans
    // down, and the watchdog only protects against a controller that dies —
    // not one that is malicious.
    if (clientHasPrivilege(securityID, kIOClientPrivilegeAdministrator)
            != kIOReturnSuccess) {
        UCLog("rejecting non-privileged client");
        return false;
    }
    return true;
}

bool PSECUserClient::start(IOService *provider)
{
    fDriver = OSDynamicCast(PredatorSenseEC, provider);
    if (!fDriver) return false;
    if (!super::start(provider)) return false;

    fDriver->retain();          // an in-flight method must not outlive this
    fDriver->clientAttached();
    fAttached = true;
    return true;
}

// Detach exactly once, whichever of stop()/clientClose() arrives first.
void PSECUserClient::releaseDriver(void)
{
    PredatorSenseEC *d = fDriver;
    if (!d) return;
    fDriver = nullptr;
    if (fAttached) { d->clientDetached(); fAttached = false; }
    d->release();
}

void PSECUserClient::stop(IOService *provider)
{
    releaseDriver();
    super::stop(provider);
}

IOReturn PSECUserClient::clientClose(void)
{
    // App exited or crashed. This is the fastest path back to auto and does
    // not depend on any timer.
    releaseDriver();
    if (!isInactive()) terminate();
    return kIOReturnSuccess;
}

IOReturn PSECUserClient::externalMethod(uint32_t selector,
                                        IOExternalMethodArguments *args,
                                        IOExternalMethodDispatch *dispatch,
                                        OSObject *target, void *reference)
{
    if (selector >= kPSECMethodCount) return kIOReturnUnsupported;
    dispatch = (IOExternalMethodDispatch *)&gMethods[selector];
    if (!target) target = this;
    return super::externalMethod(selector, args, dispatch, target, reference);
}

#define UC_SELF() \
    PSECUserClient *self = OSDynamicCast(PSECUserClient, t); \
    if (!self || !self->fDriver) return kIOReturnNotAttached;

IOReturn PSECUserClient::sSetFanMode(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    return self->fDriver->setFanMode((uint32_t)a->scalarInput[0]);
}

IOReturn PSECUserClient::sSetDuty(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    return self->fDriver->setDuty((uint32_t)a->scalarInput[0],
                                  (uint32_t)a->scalarInput[1]);
}

IOReturn PSECUserClient::sGetStatus(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    if (!a->structureOutput || a->structureOutputSize < sizeof(PSECStatus))
        return kIOReturnBadArgument;
    IOReturn ret = self->fDriver->getStatus((PSECStatus *)a->structureOutput);
    if (ret == kIOReturnSuccess) a->structureOutputSize = sizeof(PSECStatus);
    return ret;
}

IOReturn PSECUserClient::sPing(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    return self->fDriver->ping();
}

IOReturn PSECUserClient::sECRead(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    uint32_t v = 0;
    IOReturn ret = self->fDriver->ecReadRaw((uint32_t)a->scalarInput[0], &v);
    a->scalarOutput[0] = v;
    return ret;
}

IOReturn PSECUserClient::sECWrite(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    return self->fDriver->ecWriteRaw((uint32_t)a->scalarInput[0],
                                     (uint32_t)a->scalarInput[1]);
}

IOReturn PSECUserClient::sSetTurbo(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    return self->fDriver->setTurbo((uint32_t)a->scalarInput[0]);
}

IOReturn PSECUserClient::sSetLcdOverdrive(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    return self->fDriver->setLcdOverdrive((uint32_t)a->scalarInput[0]);
}

IOReturn PSECUserClient::sSetRgb(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    return self->fDriver->setRgb((uint32_t)a->scalarInput[0],
                                 (uint32_t)a->scalarInput[1],
                                 (uint32_t)a->scalarInput[2],
                                 (uint32_t)a->scalarInput[3]);
}

IOReturn PSECUserClient::sSetPowerProfile(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    return self->fDriver->setPowerProfile((uint32_t)a->scalarInput[0]);
}

IOReturn PSECUserClient::sRawWMI(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    if (!a->structureInput || a->structureInputSize < sizeof(PSECWMIRequest))
        return kIOReturnBadArgument;
    if (!a->structureOutput || a->structureOutputSize < sizeof(PSECWMIReply))
        return kIOReturnBadArgument;
    IOReturn ret = self->fDriver->rawWMI((const PSECWMIRequest *)a->structureInput,
                                         (PSECWMIReply *)a->structureOutput);
    if (ret == kIOReturnSuccess) a->structureOutputSize = sizeof(PSECWMIReply);
    return ret;
}

IOReturn PSECUserClient::sSetKbEffect(OSObject *t, void *r, IOExternalMethodArguments *a)
{
    UC_SELF()
    return self->fDriver->setKbEffect((uint32_t)a->scalarInput[0],
                                      (uint32_t)a->scalarInput[1],
                                      (uint32_t)a->scalarInput[2],
                                      (uint32_t)a->scalarInput[3],
                                      (uint32_t)a->scalarInput[4],
                                      (uint32_t)a->scalarInput[5],
                                      (uint32_t)a->scalarInput[6]);
}
