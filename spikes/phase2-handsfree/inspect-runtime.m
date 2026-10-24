#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/sysctl.h>

// Research utility for one inspected ARM64 framework build. Reads metadata and
// method bytes only: never instantiates a Bluetooth device, pairs, or connects.
// It reports observations, not a universal test of macOS Bluetooth capability.

#if defined(__arm64__)
static void inspectMethod(const char *className, const char *selectorName,
                          size_t byteCount) {
    Class cls = objc_getClass(className);
    Method method = class_getInstanceMethod(cls, sel_registerName(selectorName));
    if (!method) {
        fprintf(stderr, "Missing method: %s %s\n", className, selectorName);
        exit(1);
    }
    const uint8_t *code = (const uint8_t *)method_getImplementation(method);
    Dl_info info = {0};
    dladdr(code, &info);
    printf("%s\n  image: %s\n", info.dli_sname ?: selectorName,
           info.dli_fname ?: "unknown");

    for (size_t offset = 0; offset < byteCount; offset += 4) {
        uint32_t instruction;
        memcpy(&instruction, code + offset, sizeof(instruction));
        if (instruction == 0x528058e2 && offset + 8 <= byteCount) {
            uint32_t next;
            memcpy(&next, code + offset + 4, sizeof(next));
            if (next == 0x72bc0002)
                printf("  +0x%04zx: load w2 = 0xe00002c7\n", offset);
        }

        // ARM64 B/BL immediate. Resolve optimized Objective-C selector stubs.
        if ((instruction & 0x7c000000) != 0x14000000) continue;
        int32_t displacement = (int32_t)(instruction << 6) >> 4;
        uintptr_t target = (uintptr_t)code + offset + displacement;
        uint32_t words[2];
        memcpy(words, (const void *)target, sizeof(words));

        // ADRP x1, page; ADD x1, x1, #offset (unshifted).
        if ((words[0] & 0x9f00001f) != 0x90000001 ||
            (words[1] & 0xffc003ff) != 0x91000021) continue;
        int64_t pageDelta = (((words[0] >> 5) & 0x7ffff) << 2) |
                            ((words[0] >> 29) & 3);
        if (pageDelta & (1 << 20)) pageDelta -= (1 << 21);
        uintptr_t selectorAddress = (target & ~(uintptr_t)0xfff) +
            pageDelta * 4096 + ((words[1] >> 10) & 0xfff);
        printf("  +0x%04zx: selector %.120s\n", offset,
               (const char *)selectorAddress);
    }
}

static void inspectLegacyExport(const char *name) {
    const void *address = dlsym(RTLD_DEFAULT, name);
    if (!address) {
        printf("%s: not exported\n", name);
        return;
    }
    uint32_t words[2];
    memcpy(words, address, sizeof(words));
    printf("%s: %s\n", name,
           words[0] == 0x52800000 && words[1] == 0xd65f03c0
               ? "stub (mov w0, #0; ret)"
               : "not the inspected two-instruction stub");
}
#endif

int main(void) {
    @autoreleasepool {
#if defined(__arm64__)
        char build[128] = {0};
        size_t length = sizeof(build);
        if (sysctlbyname("kern.osversion", build, &length, NULL, 0) != 0 ||
            strcmp(build, "26A434") != 0) {
            fprintf(stderr, "This inspector is limited to ARM64 build 26A434; "
                    "method lengths must be reviewed on other builds.\n");
            return 1;
        }
        printf("%s; build %s; ARM64\n",
               NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String,
               build);
        // Lengths independently checked by disassembly on this exact build.
        inspectMethod("IOBluetoothHandsFree", "connectSCO", 0x698);
        inspectMethod("IOBluetoothHandsFreeDevice", "transferAudioToComputer", 4);
        inspectLegacyExport("BluetoothHCIRequestCreate");
        inspectLegacyExport("BluetoothHCISendRawCommand");
        inspectLegacyExport("BluetoothHCISendRawACLData");
        inspectLegacyExport("BluetoothHCIRequestDelete");
        inspectLegacyExport("BluetoothHCISendRawSCOData");
        return 0;
#else
        fprintf(stderr, "This inspector requires the inspected ARM64 build.\n");
        return 1;
#endif
    }
}
