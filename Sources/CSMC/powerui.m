#include "smc.h"

#ifdef LITE
int native_limit_get(void) { return -1; }
int native_limit_set(int limit) { (void)limit; return -1; }
#else
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>

// macOS 27 firmware gates SMC charge-inhibit keys; the native "Charge Limit" (PowerUI, private) still works.
static id client(void) {
    static id c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI", RTLD_NOW)) return;
        Class cls = NSClassFromString(@"PowerUISmartChargeClient");
        SEL init = sel_registerName("initWithClientName:");
        if (!cls || ![cls instancesRespondToSelector:init]) return;
        id o = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], init, @"baterai-safer");
        if (o && ((BOOL (*)(id, SEL))objc_msgSend)(o, sel_registerName("isMCLSupported"))) c = o;
    });
    return c;
}

int native_limit_get(void) {
    id c = client();
    if (!c) return -1;
    NSError *e = nil;
    unsigned long long on = ((unsigned long long (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("isMCLCurrentlyEnabled:"), &e);
    if (e) return -1;
    if (!on) return 100;
    unsigned char v = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("getMCLLimitWithError:"), &e);
    return e ? -1 : v;
}

int native_limit_set(int limit) {
    id c = client();
    if (!c) return -1;
    NSError *e = nil;
    BOOL ok = limit >= 100
        ? ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("disableMCL:"), &e)
        : ((BOOL (*)(id, SEL, unsigned char, NSError **))objc_msgSend)(c, sel_registerName("setMCLLimit:error:"), (unsigned char)limit, &e);
    return ok && !e ? 0 : -1;
}
#endif
