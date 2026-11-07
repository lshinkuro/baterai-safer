#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

// Layout must match AppleSMC's kernel struct (80 bytes); kept in C so the compiler pads it like the kernel does.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } SMCKeyInfoData;
typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

enum { kSMCHandleYPCEvent = 2, kSMCReadKey = 5, kSMCWriteKey = 6, kSMCGetKeyInfo = 9 };

static io_connect_t conn = 0;

static int smc_open(void) {
    if (conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return kr == KERN_SUCCESS ? 0 : -1;
}

static uint32_t fourcc(const char *k) {
    return ((uint32_t)k[0] << 24) | ((uint32_t)k[1] << 16) | ((uint32_t)k[2] << 8) | (uint32_t)k[3];
}

static int call(SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(SMCParam);
    kern_return_t kr = IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, in, sizeof(SMCParam), out, &outSize);
    return (kr == KERN_SUCCESS && out->result == 0) ? 0 : -1;
}

static int key_info(const char *key, SMCKeyInfoData *info) {
    if (smc_open() != 0) return -1;
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.data8 = kSMCGetKeyInfo;
    if (call(&in, &out) != 0) return -1;
    *info = out.keyInfo;
    return 0;
}

int smc_has_key(const char *key) {
    SMCKeyInfoData info;
    return key_info(key, &info) == 0;
}

int smc_read(const char *key, uint8_t *buf, uint32_t *size, uint32_t *type) {
    SMCKeyInfoData info;
    if (key_info(key, &info) != 0 || info.dataSize > 32 || info.dataSize > *size) return -1;
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = kSMCReadKey;
    if (call(&in, &out) != 0) return -1;
    memcpy(buf, out.bytes, info.dataSize);
    *size = info.dataSize;
    if (type) *type = info.dataType;
    return 0;
}

int smc_write(const char *key, const uint8_t *buf, uint32_t size) {
    SMCKeyInfoData info;
    if (key_info(key, &info) != 0 || info.dataSize != size) return -1;
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.keyInfo.dataSize = size;
    in.data8 = kSMCWriteKey;
    memcpy(in.bytes, buf, size);
    return call(&in, &out);
}
