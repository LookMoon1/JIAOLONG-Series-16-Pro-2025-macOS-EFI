//
//  MechrevoEC.cpp — 机械革命蛟龙16Pro 只读数据采集驱动 v8
//
//  数据源：ACPI \_SB.INOU.ECRR(addr) 读取 0xFED50000 eSPI 共享内存窗口。
//  该路径已在 v4-v6 反复验证可稳定开机运行，不带任何写入、不调用其它设备方法。
//
//  采集三段关键区：
//    0x400-0x4FF  温度 / 风扇 / 功率
//    0x700-0x7FF  电量 / 功耗墙 / 性能字段
//    0xEA0-0xECF  OEM IPC 命令块（UVER/CCI/CTL/MGI/MGO）
//
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <mach/kmod.h>

#define kECDelayMs 1
#define kMapLen    0x100

class MechrevoEC : public IOService
{
    OSDeclareDefaultStructors(MechrevoEC)

public:
    virtual bool start(IOService *provider) override;
    virtual void stop(IOService *provider) override;
    virtual void free() override;

    void timerFired(OSObject *owner, IOTimerEventSource *sender);

private:
    IOReturn ecRead(UInt32 addr, UInt8 *value);
    void     publishWindow(const char *name, UInt32 start, UInt32 len);

    IOACPIPlatformDevice *fDevice   = nullptr;
    IOTimerEventSource   *fTimer    = nullptr;
    IOLock               *fLock     = nullptr;
    UInt64                fSeq      = 0;
    UInt32                fPollMs   = 1500;
    UInt32                fFailures = 0;
    UInt32                fReadOK   = 0;
};

OSDefineMetaClassAndStructors(MechrevoEC, IOService)

bool MechrevoEC::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;

    fDevice = static_cast<IOACPIPlatformDevice *>(provider);
    if (!fDevice) { stop(provider); return false; }

    fLock = IOLockAlloc();
    if (!fLock) { stop(provider); return false; }

    if (OSNumber *n = OSDynamicCast(OSNumber, getProperty("PollMs")))
        fPollMs = (UInt32)n->unsigned32BitValue();
    if (fPollMs < 500) fPollMs = 500;

    UInt8 v = 0;
    IOReturn r = ecRead(0x00, &v);
    IOLog("MechrevoEC: ECRR(0x00) ret=0x%x value=0x%02x\n", r, v);
    setProperty("ProbeOK", (r == kIOReturnSuccess));
    setProperty("ProbeStatus", (UInt32)r, 32);

    fTimer = IOTimerEventSource::timerEventSource(this,
                OSMemberFunctionCast(IOTimerEventSource::Action, this, &MechrevoEC::timerFired));
    if (fTimer && getWorkLoop() && getWorkLoop()->addEventSource(fTimer) == kIOReturnSuccess) {
        fTimer->setTimeoutMS(2000);
    } else {
        IOLog("MechrevoEC: timer setup failed\n");
    }

    registerService();
    return true;
}

void MechrevoEC::stop(IOService *provider)
{
    if (fTimer) {
        fTimer->cancelTimeout();
        if (getWorkLoop()) getWorkLoop()->removeEventSource(fTimer);
        fTimer->release();
        fTimer = nullptr;
    }
    if (fLock) { IOLockFree(fLock); fLock = nullptr; }
    fDevice = nullptr;
    IOService::stop(provider);
}

void MechrevoEC::free()
{
    if (fTimer) { fTimer->release(); fTimer = nullptr; }
    if (fLock)  { IOLockFree(fLock); fLock = nullptr; }
    IOService::free();
}

IOReturn MechrevoEC::ecRead(UInt32 addr, UInt8 *value)
{
    if (!fDevice || !value) return kIOReturnNotReady;

    OSNumber *p = OSNumber::withNumber((unsigned long long)addr, 32);
    if (!p) return kIOReturnNoMemory;
    OSObject *params[1] = { p };

    UInt32 v = 0xFFFFFFFF;
    IOLockLock(fLock);
    IOReturn ret = fDevice->evaluateInteger("ECRR", &v, params, 1);
    IOLockUnlock(fLock);

    p->release();
    IOSleep(kECDelayMs);

    if (ret != kIOReturnSuccess || v == 0xFFFFFFFF || v == 0xFFFFFFFE) {
        fFailures++;
        return kIOReturnError;
    }
    *value = (UInt8)(v & 0xFF);
    return kIOReturnSuccess;
}

void MechrevoEC::publishWindow(const char *name, UInt32 start, UInt32 len)
{
    if (!fDevice) return;

    UInt8 *buf = (UInt8 *)IOMallocZero(len);
    if (!buf) return;

    UInt32 ok = 0;
    for (UInt32 i = 0; i < len; i++) {
        UInt8 v = 0xFF;
        if (ecRead(start + i, &v) == kIOReturnSuccess) { buf[i] = v; ok++; }
        else buf[i] = 0xFE;
    }
    fReadOK += ok;

    OSData *data = OSData::withBytes(buf, len);
    if (data) { setProperty(name, data); data->release(); }
    IOFree(buf, len);
}

void MechrevoEC::timerFired(OSObject *owner, IOTimerEventSource *sender)
{
    publishWindow("FanMap",  0x0D0, 0x10);   // 风扇占空比历史 + 风扇等级
    publishWindow("MidMap",  0x430, 0x80);   // 0x430-0x4AF：温度/风扇表/功率
    publishWindow("HighMap", 0x700, 0x100);  // 0x700-0x7FF：电量/功耗墙/性能字段
    publishWindow("IPCMap",  0xEA0, 0x30);   // OEM IPC 命令块

    fSeq++;
    setProperty("Seq", fSeq, 64);
    setProperty("ReadOK", fReadOK, 32);
    setProperty("Failures", fFailures, 32);

    sender->setTimeoutMS(fPollMs);
}

// kext 必须导出 kmod_info，否则内核集合拒绝链接
extern "C" {
static kern_return_t mec_kmod_start(struct kmod_info *ki, void *data) { return KERN_SUCCESS; }
static kern_return_t mec_kmod_stop(struct kmod_info *ki, void *data) { return KERN_SUCCESS; }
KMOD_EXPLICIT_DECL(com.local.MechrevoEC, "1.0", mec_kmod_start, mec_kmod_stop)
}
