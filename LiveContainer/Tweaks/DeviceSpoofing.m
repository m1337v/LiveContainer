//
//  DeviceSpoofing.m
//  LiveContainer
//
//  Ghost-parity device spoofing core.
//  This file intentionally keeps a compatibility API surface while
//  implementing a minimal, deterministic spoofing model.
//

#import "DeviceSpoofing.h"

#import <AdSupport/AdSupport.h>
#import <CoreTelephony/CTCarrier.h>
#import <dlfcn.h>
#import <errno.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

#import "../../fishhook/fishhook.h"

#pragma mark - Profiles

const LCDeviceProfile kDeviceProfileiPhone16ProMax = {
    .modelIdentifier = "iPhone17,2",
    .hardwareModel = "D94AP",
    .marketingName = "iPhone 16 Pro Max",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8140",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 440,
    .screenHeight = 956,
    .chipName = "Apple A18 Pro",
    .gpuName = "Apple A18 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone16Pro = {
    .modelIdentifier = "iPhone17,1",
    .hardwareModel = "D93AP",
    .marketingName = "iPhone 16 Pro",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8140",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 402,
    .screenHeight = 874,
    .chipName = "Apple A18 Pro",
    .gpuName = "Apple A18 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone16 = {
    .modelIdentifier = "iPhone17,3",
    .hardwareModel = "D47AP",
    .marketingName = "iPhone 16",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8130",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A18",
    .gpuName = "Apple A18 GPU"
};

// Compatibility aliases for existing UI options. Kept deterministic; no speculative OS build data.
const LCDeviceProfile kDeviceProfileiPhone17ProMax = {
    .modelIdentifier = "iPhone18,2",
    .hardwareModel = "D104AP",
    .marketingName = "iPhone 17 Pro Max",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8140",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 440,
    .screenHeight = 956,
    .chipName = "Apple A18 Pro",
    .gpuName = "Apple A18 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17Pro = {
    .modelIdentifier = "iPhone18,1",
    .hardwareModel = "D103AP",
    .marketingName = "iPhone 17 Pro",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8140",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 402,
    .screenHeight = 874,
    .chipName = "Apple A18 Pro",
    .gpuName = "Apple A18 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17 = {
    .modelIdentifier = "iPhone18,3",
    .hardwareModel = "D57AP",
    .marketingName = "iPhone 17",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8130",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A18",
    .gpuName = "Apple A18 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17Air = {
    .modelIdentifier = "iPhone18,4",
    .hardwareModel = "D58AP",
    .marketingName = "iPhone 17 Air",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8130",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A18",
    .gpuName = "Apple A18 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone15ProMax = {
    .modelIdentifier = "iPhone16,2",
    .hardwareModel = "D84AP",
    .marketingName = "iPhone 15 Pro Max",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8130",
    .kernelRelease = "23.6.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 430,
    .screenHeight = 932,
    .chipName = "Apple A17 Pro",
    .gpuName = "Apple A17 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone15Pro = {
    .modelIdentifier = "iPhone16,1",
    .hardwareModel = "D83AP",
    .marketingName = "iPhone 15 Pro",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8130",
    .kernelRelease = "23.6.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A17 Pro",
    .gpuName = "Apple A17 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone14ProMax = {
    .modelIdentifier = "iPhone15,3",
    .hardwareModel = "D74AP",
    .marketingName = "iPhone 14 Pro Max",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8120",
    .kernelRelease = "23.6.0",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 430,
    .screenHeight = 932,
    .chipName = "Apple A16 Bionic",
    .gpuName = "Apple A16 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone14Pro = {
    .modelIdentifier = "iPhone15,2",
    .hardwareModel = "D73AP",
    .marketingName = "iPhone 14 Pro",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8120",
    .kernelRelease = "23.6.0",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A16 Bionic",
    .gpuName = "Apple A16 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone13ProMax = {
    .modelIdentifier = "iPhone14,3",
    .hardwareModel = "D64AP",
    .marketingName = "iPhone 13 Pro Max",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8110",
    .kernelRelease = "23.6.0",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 428,
    .screenHeight = 926,
    .chipName = "Apple A15 Bionic",
    .gpuName = "Apple A15 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone13Pro = {
    .modelIdentifier = "iPhone14,2",
    .hardwareModel = "D63AP",
    .marketingName = "iPhone 13 Pro",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8110",
    .kernelRelease = "23.6.0",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 390,
    .screenHeight = 844,
    .chipName = "Apple A15 Bionic",
    .gpuName = "Apple A15 GPU"
};

const LCDeviceProfile kDeviceProfileiPadPro13_M4 = {
    .modelIdentifier = "iPad16,5",
    .hardwareModel = "J720AP",
    .marketingName = "iPad Pro 13-inch (M4)",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8132",
    .kernelRelease = "24.1.0",
    .physicalMemory = 17179869184ULL,
    .cpuCoreCount = 10,
    .performanceCores = 4,
    .efficiencyCores = 6,
    .screenScale = 2.0,
    .screenWidth = 1032,
    .screenHeight = 1376,
    .chipName = "Apple M4",
    .gpuName = "Apple M4 GPU"
};

const LCDeviceProfile kDeviceProfileiPadPro11_M4 = {
    .modelIdentifier = "iPad16,3",
    .hardwareModel = "J717AP",
    .marketingName = "iPad Pro 11-inch (M4)",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8132",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 10,
    .performanceCores = 4,
    .efficiencyCores = 6,
    .screenScale = 2.0,
    .screenWidth = 834,
    .screenHeight = 1210,
    .chipName = "Apple M4",
    .gpuName = "Apple M4 GPU"
};

const LCDeviceProfile kDeviceProfileiPadPro12_9_6th = {
    .modelIdentifier = "iPad14,5",
    .hardwareModel = "J620AP",
    .marketingName = "iPad Pro 12.9-inch (6th generation)",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8112",
    .kernelRelease = "23.6.0",
    .physicalMemory = 17179869184ULL,
    .cpuCoreCount = 8,
    .performanceCores = 4,
    .efficiencyCores = 4,
    .screenScale = 2.0,
    .screenWidth = 1024,
    .screenHeight = 1366,
    .chipName = "Apple M2",
    .gpuName = "Apple M2 GPU"
};

#pragma mark - Global State

static BOOL g_deviceSpoofingEnabled = NO;
static NSString *g_currentProfileName = nil;
static const LCDeviceProfile *g_currentProfile = NULL;

static NSString *g_customDeviceModel = nil;
static NSString *g_customSystemVersion = nil;
static NSString *g_customBuildVersion = nil;
static uint64_t g_customPhysicalMemory = 0;
static NSString *g_customDeviceName = nil;
static NSString *g_customCarrierName = nil;

static NSString *g_spoofedVendorID = nil;
static NSString *g_spoofedAdvertisingID = nil;
static NSString *g_spoofedInstallationID = nil;
static NSString *g_spoofedMACAddress = nil;
static BOOL g_adTrackingConfigured = NO;
static BOOL g_spoofedAdTrackingEnabled = NO;

static BOOL g_batteryLevelConfigured = NO;
static float g_spoofedBatteryLevel = -1.0f;
static BOOL g_batteryStateConfigured = NO;
static NSInteger g_spoofedBatteryState = -1;
static BOOL g_brightnessConfigured = NO;
static float g_spoofedBrightness = -1.0f;
static BOOL g_thermalConfigured = NO;
static NSInteger g_spoofedThermalState = -1;
static BOOL g_spoofLowPowerMode = NO;
static BOOL g_lowPowerModeValue = NO;

// Compatibility-only state for deprecated surfaces.
static BOOL g_storageSpoofingEnabled = NO;
static uint64_t g_spoofedStorageTotal = 0;
static uint64_t g_spoofedStorageFree = 0;
static NSString *g_spoofedStorageCapacityGB = nil;
static NSString *g_spoofedStorageFreeGB = nil;
static BOOL g_canvasFingerprintProtectionEnabled = NO;
static BOOL g_iCloudPrivacyProtectionEnabled = YES;
static BOOL g_siriPrivacyProtectionEnabled = NO;
static NSString *g_customUserAgent = nil;
static BOOL g_userAgentSpoofingEnabled = NO;

#pragma mark - Original Function Pointers

static int (*orig_uname)(struct utsname *name) = NULL;
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;

static NSString *(*orig_UIDevice_systemVersion)(id self, SEL _cmd) = NULL;
static NSString *(*orig_UIDevice_name)(id self, SEL _cmd) = NULL;
static NSUUID *(*orig_UIDevice_identifierForVendor)(id self, SEL _cmd) = NULL;
static float (*orig_UIDevice_batteryLevel)(id self, SEL _cmd) = NULL;
static NSInteger (*orig_UIDevice_batteryState)(id self, SEL _cmd) = NULL;
static BOOL (*orig_UIDevice_isBatteryMonitoringEnabled)(id self, SEL _cmd) = NULL;

static unsigned long long (*orig_NSProcessInfo_physicalMemory)(id self, SEL _cmd) = NULL;
static NSUInteger (*orig_NSProcessInfo_processorCount)(id self, SEL _cmd) = NULL;
static NSUInteger (*orig_NSProcessInfo_activeProcessorCount)(id self, SEL _cmd) = NULL;
static NSOperatingSystemVersion (*orig_NSProcessInfo_operatingSystemVersion)(id self, SEL _cmd) = NULL;
static NSString *(*orig_NSProcessInfo_operatingSystemVersionString)(id self, SEL _cmd) = NULL;
static NSInteger (*orig_NSProcessInfo_thermalState)(id self, SEL _cmd) = NULL;
static BOOL (*orig_NSProcessInfo_isLowPowerModeEnabled)(id self, SEL _cmd) = NULL;

static CGFloat (*orig_UIScreen_brightness)(id self, SEL _cmd) = NULL;

static NSUUID *(*orig_ASIdentifierManager_advertisingIdentifier)(id self, SEL _cmd) = NULL;
static BOOL (*orig_ASIdentifierManager_isAdvertisingTrackingEnabled)(id self, SEL _cmd) = NULL;

static id (*orig_NSFileManager_ubiquityIdentityToken)(id self, SEL _cmd) = NULL;
static NSString *(*orig_CTCarrier_carrierName)(id self, SEL _cmd) = NULL;

#pragma mark - Helpers

static inline BOOL LCDeviceSpoofingIsActive(void) {
    return g_deviceSpoofingEnabled;
}

static const char *LCSpoofedMachineModel(void) {
    if (g_customDeviceModel.length > 0) return g_customDeviceModel.UTF8String;
    if (g_currentProfile) return g_currentProfile->modelIdentifier;
    return NULL;
}

static const char *LCSpoofedHardwareModel(void) {
    if (g_currentProfile) return g_currentProfile->hardwareModel;
    return NULL;
}

static const char *LCSpoofedSystemVersion(void) {
    if (g_customSystemVersion.length > 0) return g_customSystemVersion.UTF8String;
    if (g_currentProfile) return g_currentProfile->systemVersion;
    return NULL;
}

static const char *LCSpoofedBuildVersion(void) {
    if (g_customBuildVersion.length > 0) return g_customBuildVersion.UTF8String;
    if (g_currentProfile) return g_currentProfile->buildVersion;
    return NULL;
}

static const char *LCSpoofedKernelVersion(void) {
    if (g_currentProfile) return g_currentProfile->kernelVersion;
    return NULL;
}

static const char *LCSpoofedKernelRelease(void) {
    if (g_currentProfile) return g_currentProfile->kernelRelease;
    return NULL;
}

static uint64_t LCSpoofedPhysicalMemory(void) {
    if (g_customPhysicalMemory > 0) return g_customPhysicalMemory;
    if (g_currentProfile) return g_currentProfile->physicalMemory;
    return 0;
}

static uint32_t LCSpoofedCPUCount(void) {
    if (g_currentProfile) return g_currentProfile->cpuCoreCount;
    return 0;
}

static NSOperatingSystemVersion LCParseOSVersion(NSString *versionString) {
    NSOperatingSystemVersion v = {0, 0, 0};
    NSArray<NSString *> *parts = [versionString componentsSeparatedByString:@"."];
    if (parts.count > 0) v.majorVersion = parts[0].integerValue;
    if (parts.count > 1) v.minorVersion = parts[1].integerValue;
    if (parts.count > 2) v.patchVersion = parts[2].integerValue;
    return v;
}

static NSString *LCSpoofedOSVersionString(void) {
    const char *version = LCSpoofedSystemVersion();
    const char *build = LCSpoofedBuildVersion();
    if (!version || !build) return nil;
    return [NSString stringWithFormat:@"Version %s (Build %s)", version, build];
}

static int LCWriteCStringValue(void *oldp, size_t *oldlenp, const char *value) {
    if (!oldlenp || !value) {
        errno = EINVAL;
        return -1;
    }

    size_t needed = strlen(value) + 1;
    if (!oldp) {
        *oldlenp = needed;
        return 0;
    }

    if (*oldlenp < needed) {
        *oldlenp = needed;
        errno = ENOMEM;
        return -1;
    }

    memset(oldp, 0, *oldlenp);
    strlcpy((char *)oldp, value, *oldlenp);
    *oldlenp = needed;
    return 0;
}

static int LCWriteU32Value(void *oldp, size_t *oldlenp, uint32_t value) {
    if (!oldlenp) {
        errno = EINVAL;
        return -1;
    }

    size_t needed = sizeof(uint32_t);
    if (!oldp) {
        *oldlenp = needed;
        return 0;
    }

    if (*oldlenp < needed) {
        *oldlenp = needed;
        errno = ENOMEM;
        return -1;
    }

    *(uint32_t *)oldp = value;
    *oldlenp = needed;
    return 0;
}

static int LCWriteU64Value(void *oldp, size_t *oldlenp, uint64_t value) {
    if (!oldlenp) {
        errno = EINVAL;
        return -1;
    }

    size_t needed = sizeof(uint64_t);
    if (!oldp) {
        *oldlenp = needed;
        return 0;
    }

    if (*oldlenp < needed) {
        *oldlenp = needed;
        errno = ENOMEM;
        return -1;
    }

    *(uint64_t *)oldp = value;
    *oldlenp = needed;
    return 0;
}

static NSUUID *LCUUIDFromOverrideString(NSString *value) {
    if (value.length == 0) return nil;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
    return uuid;
}

static void LCInstallInstanceHook(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || !selector || !replacement || !original) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    IMP current = method_getImplementation(method);
    if (current == replacement) return;
    *original = current;
    method_setImplementation(method, replacement);
}

#pragma mark - C Hooks

static int hook_uname(struct utsname *name) {
    if (!orig_uname) {
        orig_uname = (int (*)(struct utsname *))dlsym(RTLD_DEFAULT, "uname");
        if (!orig_uname) return -1;
    }

    int rc = orig_uname(name);
    if (rc != 0 || !LCDeviceSpoofingIsActive() || !name) return rc;

    const char *machine = LCSpoofedMachineModel();
    if (machine) strlcpy(name->machine, machine, sizeof(name->machine));

    const char *kernelRelease = LCSpoofedKernelRelease();
    if (kernelRelease) strlcpy(name->release, kernelRelease, sizeof(name->release));

    const char *kernelVersion = LCSpoofedKernelVersion();
    if (kernelVersion) strlcpy(name->version, kernelVersion, sizeof(name->version));

    return rc;
}

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctlbyname) {
        orig_sysctlbyname = (int (*)(const char *, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctlbyname");
        if (!orig_sysctlbyname) return -1;
    }

    if (LCDeviceSpoofingIsActive() && name) {
        if (strcmp(name, "hw.machine") == 0) {
            const char *value = LCSpoofedMachineModel();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.model") == 0) {
            const char *value = LCSpoofedHardwareModel();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.logicalcpu") == 0 || strcmp(name, "hw.physicalcpu") == 0) {
            uint32_t value = LCSpoofedCPUCount();
            if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.memsize") == 0) {
            uint64_t value = LCSpoofedPhysicalMemory();
            if (value > 0) return LCWriteU64Value(oldp, oldlenp, value);
        } else if (strcmp(name, "hw.physmem") == 0) {
            uint64_t value = LCSpoofedPhysicalMemory();
            if (value > 0) return LCWriteU32Value(oldp, oldlenp, (uint32_t)MIN(value, UINT32_MAX));
        } else if (strcmp(name, "kern.osversion") == 0) {
            const char *value = LCSpoofedBuildVersion();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "kern.osrelease") == 0) {
            const char *value = LCSpoofedKernelRelease();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "kern.version") == 0) {
            const char *value = LCSpoofedKernelVersion();
            if (value) return LCWriteCStringValue(oldp, oldlenp, value);
        } else if (strcmp(name, "kern.hostname") == 0) {
            if (g_customDeviceName.length > 0) {
                return LCWriteCStringValue(oldp, oldlenp, g_customDeviceName.UTF8String);
            }
        }
    }

    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctl) {
        orig_sysctl = (int (*)(int *, u_int, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctl");
        if (!orig_sysctl) return -1;
    }

    if (LCDeviceSpoofingIsActive() && name && namelen >= 2) {
        if (name[0] == CTL_HW) {
            switch (name[1]) {
                case HW_MACHINE: {
                    const char *value = LCSpoofedMachineModel();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
                case HW_MODEL: {
                    const char *value = LCSpoofedHardwareModel();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
                case HW_NCPU: {
                    uint32_t value = LCSpoofedCPUCount();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, value);
                    break;
                }
                case HW_MEMSIZE: {
                    uint64_t value = LCSpoofedPhysicalMemory();
                    if (value > 0) return LCWriteU64Value(oldp, oldlenp, value);
                    break;
                }
                case HW_PHYSMEM: {
                    uint64_t value = LCSpoofedPhysicalMemory();
                    if (value > 0) return LCWriteU32Value(oldp, oldlenp, (uint32_t)MIN(value, UINT32_MAX));
                    break;
                }
                default:
                    break;
            }
        } else if (name[0] == CTL_KERN) {
            switch (name[1]) {
                case KERN_OSVERSION: {
                    const char *value = LCSpoofedBuildVersion();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
                case KERN_OSRELEASE: {
                    const char *value = LCSpoofedKernelRelease();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
                case KERN_VERSION: {
                    const char *value = LCSpoofedKernelVersion();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
                default:
                    break;
            }
        }
    }

    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

#pragma mark - ObjC Hooks

static NSString *hook_UIDevice_systemVersion(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return @(value);
    }
    if (orig_UIDevice_systemVersion) return orig_UIDevice_systemVersion(self, _cmd);
    return @"17.0";
}

static NSString *hook_UIDevice_name(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_customDeviceName.length > 0) {
        return g_customDeviceName;
    }
    if (orig_UIDevice_name) return orig_UIDevice_name(self, _cmd);
    return @"iPhone";
}

static NSUUID *hook_UIDevice_identifierForVendor(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        NSUUID *uuid = LCUUIDFromOverrideString(g_spoofedVendorID);
        if (uuid) return uuid;
    }
    if (orig_UIDevice_identifierForVendor) return orig_UIDevice_identifierForVendor(self, _cmd);
    return [[NSUUID alloc] init];
}

static float hook_UIDevice_batteryLevel(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_batteryLevelConfigured) {
        return g_spoofedBatteryLevel;
    }
    if (orig_UIDevice_batteryLevel) return orig_UIDevice_batteryLevel(self, _cmd);
    return 1.0f;
}

static NSInteger hook_UIDevice_batteryState(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_batteryStateConfigured) {
        return g_spoofedBatteryState;
    }
    if (orig_UIDevice_batteryState) return orig_UIDevice_batteryState(self, _cmd);
    return 2;
}

static BOOL hook_UIDevice_isBatteryMonitoringEnabled(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && (g_batteryLevelConfigured || g_batteryStateConfigured)) {
        return YES;
    }
    if (orig_UIDevice_isBatteryMonitoringEnabled) return orig_UIDevice_isBatteryMonitoringEnabled(self, _cmd);
    return YES;
}

static unsigned long long hook_NSProcessInfo_physicalMemory(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        uint64_t value = LCSpoofedPhysicalMemory();
        if (value > 0) return value;
    }
    if (orig_NSProcessInfo_physicalMemory) return orig_NSProcessInfo_physicalMemory(self, _cmd);
    return 0;
}

static NSUInteger hook_NSProcessInfo_processorCount(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        uint32_t value = LCSpoofedCPUCount();
        if (value > 0) return value;
    }
    if (orig_NSProcessInfo_processorCount) return orig_NSProcessInfo_processorCount(self, _cmd);
    return 0;
}

static NSUInteger hook_NSProcessInfo_activeProcessorCount(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        uint32_t value = LCSpoofedCPUCount();
        if (value > 0) return value;
    }
    if (orig_NSProcessInfo_activeProcessorCount) return orig_NSProcessInfo_activeProcessorCount(self, _cmd);
    return 0;
}

static NSOperatingSystemVersion hook_NSProcessInfo_operatingSystemVersion(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return LCParseOSVersion(@(value));
    }
    if (orig_NSProcessInfo_operatingSystemVersion) return orig_NSProcessInfo_operatingSystemVersion(self, _cmd);
    return (NSOperatingSystemVersion){0, 0, 0};
}

static NSString *hook_NSProcessInfo_operatingSystemVersionString(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        NSString *value = LCSpoofedOSVersionString();
        if (value) return value;
    }
    if (orig_NSProcessInfo_operatingSystemVersionString) return orig_NSProcessInfo_operatingSystemVersionString(self, _cmd);
    return @"";
}

static NSInteger hook_NSProcessInfo_thermalState(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_thermalConfigured) {
        return g_spoofedThermalState;
    }
    if (orig_NSProcessInfo_thermalState) return orig_NSProcessInfo_thermalState(self, _cmd);
    return 0;
}

static BOOL hook_NSProcessInfo_isLowPowerModeEnabled(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofLowPowerMode) {
        return g_lowPowerModeValue;
    }
    if (orig_NSProcessInfo_isLowPowerModeEnabled) return orig_NSProcessInfo_isLowPowerModeEnabled(self, _cmd);
    return NO;
}

static CGFloat hook_UIScreen_brightness(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_brightnessConfigured) {
        return (CGFloat)g_spoofedBrightness;
    }
    if (orig_UIScreen_brightness) return orig_UIScreen_brightness(self, _cmd);
    return 0.5;
}

static NSUUID *hook_ASIdentifierManager_advertisingIdentifier(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        NSUUID *uuid = LCUUIDFromOverrideString(g_spoofedAdvertisingID);
        if (uuid) return uuid;
    }
    if (orig_ASIdentifierManager_advertisingIdentifier) return orig_ASIdentifierManager_advertisingIdentifier(self, _cmd);
    return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
}

static BOOL hook_ASIdentifierManager_isAdvertisingTrackingEnabled(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_adTrackingConfigured) {
        return g_spoofedAdTrackingEnabled;
    }
    if (orig_ASIdentifierManager_isAdvertisingTrackingEnabled) return orig_ASIdentifierManager_isAdvertisingTrackingEnabled(self, _cmd);
    return NO;
}

static id hook_NSFileManager_ubiquityIdentityToken(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_iCloudPrivacyProtectionEnabled) {
        return nil;
    }
    if (orig_NSFileManager_ubiquityIdentityToken) return orig_NSFileManager_ubiquityIdentityToken(self, _cmd);
    return nil;
}

static NSString *hook_CTCarrier_carrierName(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_customCarrierName.length > 0) {
        return g_customCarrierName;
    }
    if (orig_CTCarrier_carrierName) return orig_CTCarrier_carrierName(self, _cmd);
    return nil;
}

#pragma mark - Public API

void LCSetDeviceSpoofingEnabled(BOOL enabled) {
    g_deviceSpoofingEnabled = enabled;
}

BOOL LCIsDeviceSpoofingEnabled(void) {
    return g_deviceSpoofingEnabled;
}

void LCSetDeviceProfile(NSString *profileName) {
    g_currentProfileName = [profileName copy];

    static NSDictionary<NSString *, NSValue *> *profileMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        profileMap = @{
            @"iPhone 17 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone17ProMax],
            @"iPhone 17 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone17Pro],
            @"iPhone 17": [NSValue valueWithPointer:&kDeviceProfileiPhone17],
            @"iPhone 17 Air": [NSValue valueWithPointer:&kDeviceProfileiPhone17Air],
            @"iPhone 16 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone16ProMax],
            @"iPhone 16 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone16Pro],
            @"iPhone 16": [NSValue valueWithPointer:&kDeviceProfileiPhone16],
            @"iPhone 15 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone15ProMax],
            @"iPhone 15 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone15Pro],
            @"iPhone 14 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone14ProMax],
            @"iPhone 14 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone14Pro],
            @"iPhone 13 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone13ProMax],
            @"iPhone 13 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone13Pro],
            @"iPad Pro 13-inch (M4)": [NSValue valueWithPointer:&kDeviceProfileiPadPro13_M4],
            @"iPad Pro 11-inch (M4)": [NSValue valueWithPointer:&kDeviceProfileiPadPro11_M4],
            @"iPad Pro 12.9 (6th gen)": [NSValue valueWithPointer:&kDeviceProfileiPadPro12_9_6th],
        };
    });

    NSValue *value = profileMap[profileName];
    g_currentProfile = value ? (const LCDeviceProfile *)value.pointerValue : NULL;
}

NSString *LCGetCurrentDeviceProfile(void) {
    return g_currentProfileName;
}

NSDictionary<NSString *, NSDictionary *> *LCGetAvailableDeviceProfiles(void) {
    return @{
        @"iPhone 17 Pro Max": @{@"model": @"iPhone18,2", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18 Pro"},
        @"iPhone 17 Pro": @{@"model": @"iPhone18,1", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18 Pro"},
        @"iPhone 17": @{@"model": @"iPhone18,3", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18"},
        @"iPhone 17 Air": @{@"model": @"iPhone18,4", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18"},
        @"iPhone 16 Pro Max": @{@"model": @"iPhone17,2", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18 Pro"},
        @"iPhone 16 Pro": @{@"model": @"iPhone17,1", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18 Pro"},
        @"iPhone 16": @{@"model": @"iPhone17,3", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18"},
        @"iPhone 15 Pro Max": @{@"model": @"iPhone16,2", @"version": @"17.6.1", @"memory": @"8 GB", @"chip": @"A17 Pro"},
        @"iPhone 15 Pro": @{@"model": @"iPhone16,1", @"version": @"17.6.1", @"memory": @"8 GB", @"chip": @"A17 Pro"},
        @"iPhone 14 Pro Max": @{@"model": @"iPhone15,3", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A16"},
        @"iPhone 14 Pro": @{@"model": @"iPhone15,2", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A16"},
        @"iPhone 13 Pro Max": @{@"model": @"iPhone14,3", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A15"},
        @"iPhone 13 Pro": @{@"model": @"iPhone14,2", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A15"},
        @"iPad Pro 13-inch (M4)": @{@"model": @"iPad16,5", @"version": @"18.1", @"memory": @"16 GB", @"chip": @"M4"},
        @"iPad Pro 11-inch (M4)": @{@"model": @"iPad16,3", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"M4"},
        @"iPad Pro 12.9 (6th gen)": @{@"model": @"iPad14,5", @"version": @"17.6.1", @"memory": @"16 GB", @"chip": @"M2"},
    };
}

NSDictionary *LCGetCurrentProfileData(void) {
    if (!g_currentProfile) return nil;
    return @{
        @"modelIdentifier": @(g_currentProfile->modelIdentifier),
        @"hardwareModel": @(g_currentProfile->hardwareModel),
        @"marketingName": @(g_currentProfile->marketingName),
        @"systemVersion": @(g_currentProfile->systemVersion),
        @"buildVersion": @(g_currentProfile->buildVersion),
        @"kernelRelease": @(g_currentProfile->kernelRelease),
        @"physicalMemory": @(g_currentProfile->physicalMemory),
        @"cpuCoreCount": @(g_currentProfile->cpuCoreCount),
        @"performanceCores": @(g_currentProfile->performanceCores),
        @"efficiencyCores": @(g_currentProfile->efficiencyCores),
        @"screenScale": @(g_currentProfile->screenScale),
        @"screenWidth": @(g_currentProfile->screenWidth),
        @"screenHeight": @(g_currentProfile->screenHeight),
        @"chipName": @(g_currentProfile->chipName),
        @"gpuName": @(g_currentProfile->gpuName),
    };
}

void LCSetSpoofedDeviceModel(NSString *model) { g_customDeviceModel = [model copy]; }
void LCSetSpoofedSystemVersion(NSString *version) { g_customSystemVersion = [version copy]; }
void LCSetSpoofedBuildVersion(NSString *build) { g_customBuildVersion = [build copy]; }
void LCSetSpoofedPhysicalMemory(uint64_t memory) { g_customPhysicalMemory = memory; }

void LCSetSpoofedDeviceName(NSString *deviceName) { g_customDeviceName = [deviceName copy]; }
NSString *LCGetSpoofedDeviceName(void) { return g_customDeviceName; }

void LCSetSpoofedCarrierName(NSString *carrierName) { g_customCarrierName = [carrierName copy]; }
NSString *LCGetSpoofedCarrierName(void) { return g_customCarrierName; }

void LCSetSpoofedVendorID(NSString *vendorID) { g_spoofedVendorID = [vendorID copy]; }
NSString *LCGetSpoofedVendorID(void) { return g_spoofedVendorID; }

void LCSetSpoofedAdvertisingID(NSString *advertisingID) { g_spoofedAdvertisingID = [advertisingID copy]; }
NSString *LCGetSpoofedAdvertisingID(void) { return g_spoofedAdvertisingID; }

void LCSetSpoofedAdTrackingEnabled(BOOL enabled) {
    g_adTrackingConfigured = YES;
    g_spoofedAdTrackingEnabled = enabled;
}

BOOL LCGetSpoofedAdTrackingEnabled(void) {
    return g_adTrackingConfigured ? g_spoofedAdTrackingEnabled : NO;
}

void LCSetSpoofedInstallationID(NSString *installationID) { g_spoofedInstallationID = [installationID copy]; }
NSString *LCGetSpoofedInstallationID(void) { return g_spoofedInstallationID; }

void LCSetSpoofedMACAddress(NSString *macAddress) { g_spoofedMACAddress = [macAddress copy]; }
NSString *LCGetSpoofedMACAddress(void) { return g_spoofedMACAddress; }

void LCSetSpoofedBatteryLevel(float level) {
    g_batteryLevelConfigured = YES;
    g_spoofedBatteryLevel = level;
}

float LCGetSpoofedBatteryLevel(void) {
    return g_spoofedBatteryLevel;
}

void LCSetSpoofedBatteryState(NSInteger state) {
    g_batteryStateConfigured = YES;
    g_spoofedBatteryState = state;
}

NSInteger LCGetSpoofedBatteryState(void) {
    return g_spoofedBatteryState;
}

void LCRandomizeBattery(void) {
    // Ghost-parity mode: no runtime randomization.
}

void LCSetSpoofedBrightness(float brightness) {
    g_brightnessConfigured = YES;
    g_spoofedBrightness = brightness;
}

float LCGetSpoofedBrightness(void) {
    return g_spoofedBrightness;
}

void LCRandomizeBrightness(void) {
    // Ghost-parity mode: no runtime randomization.
}

void LCSetSpoofedThermalState(NSInteger state) {
    g_thermalConfigured = YES;
    g_spoofedThermalState = state;
}

void LCSetSpoofedLowPowerMode(BOOL enabled, BOOL value) {
    g_spoofLowPowerMode = enabled;
    g_lowPowerModeValue = value;
}

void LCSetUptimeOffset(NSTimeInterval offset) { (void)offset; }
void LCRandomizeUptime(void) {}
void LCSetSpoofedBootTime(time_t bootTimestamp) { (void)bootTimestamp; }

time_t LCGetSpoofedBootTime(void) {
    struct timeval tv = {0, 0};
    size_t len = sizeof(tv);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (sysctl(mib, 2, &tv, &len, NULL, 0) == 0) {
        return tv.tv_sec;
    }
    return 0;
}

NSTimeInterval LCGetSpoofedUptime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

void LCSetStorageSpoofingEnabled(BOOL enabled) { g_storageSpoofingEnabled = enabled; }
BOOL LCIsStorageSpoofingEnabled(void) { return g_storageSpoofingEnabled; }

void LCSetSpoofedStorageCapacity(NSString *capacityGB) {
    g_spoofedStorageCapacityGB = [capacityGB copy];
    g_spoofedStorageTotal = (uint64_t)(capacityGB.doubleValue * 1000.0 * 1000.0 * 1000.0);
}

void LCSetSpoofedStorageFree(NSString *freeGB) {
    g_spoofedStorageFreeGB = [freeGB copy];
    g_spoofedStorageFree = (uint64_t)(freeGB.doubleValue * 1000.0 * 1000.0 * 1000.0);
}

void LCSetSpoofedStorageBytes(uint64_t totalBytes, uint64_t freeBytes) {
    g_spoofedStorageTotal = totalBytes;
    g_spoofedStorageFree = freeBytes;
}

NSDictionary *LCGenerateStorageForCapacity(NSString *capacityGB) {
    double totalGB = MAX(capacityGB.doubleValue, 0.0);
    double freeGB = totalGB * 0.35;
    return @{
        @"TotalStorage": [NSString stringWithFormat:@"%.0f", totalGB],
        @"FreeStorage": [NSString stringWithFormat:@"%.1f", freeGB],
        @"TotalBytes": @((uint64_t)(totalGB * 1000.0 * 1000.0 * 1000.0)),
        @"FreeBytes": @((uint64_t)(freeGB * 1000.0 * 1000.0 * 1000.0)),
        @"FilesystemType": @"APFS",
    };
}

NSString *LCRandomizeStorageCapacity(void) {
    return @"128";
}

void LCRandomizeStorage(void) {
    // Ghost-parity mode: no runtime randomization.
}

uint64_t LCGetSpoofedStorageTotal(void) { return g_spoofedStorageTotal; }
uint64_t LCGetSpoofedStorageFree(void) { return g_spoofedStorageFree; }
NSString *LCGetSpoofedStorageCapacityGB(void) { return g_spoofedStorageCapacityGB; }
NSString *LCGetSpoofedStorageFreeGB(void) { return g_spoofedStorageFreeGB; }

void LCSetSpoofedDiskSpace(uint64_t freeSpace, uint64_t totalSpace) {
    LCSetSpoofedStorageBytes(totalSpace, freeSpace);
}

void LCSetCanvasFingerprintProtectionEnabled(BOOL enabled) { g_canvasFingerprintProtectionEnabled = enabled; }
BOOL LCIsCanvasFingerprintProtectionEnabled(void) { return g_canvasFingerprintProtectionEnabled; }

void LCSetICloudPrivacyProtectionEnabled(BOOL enabled) { g_iCloudPrivacyProtectionEnabled = enabled; }
BOOL LCIsICloudPrivacyProtectionEnabled(void) { return g_iCloudPrivacyProtectionEnabled; }

void LCSetSiriPrivacyProtectionEnabled(BOOL enabled) { g_siriPrivacyProtectionEnabled = enabled; }
BOOL LCIsSiriPrivacyProtectionEnabled(void) { return g_siriPrivacyProtectionEnabled; }

void LCInitializeFingerprintProtection(void) {
    // Ghost-parity mode: deterministic only.
}

void LCSetSpoofedScreenScale(CGFloat scale) { (void)scale; }

NSString *LCGenerateRandomUUID(void) {
    return NSUUID.UUID.UUIDString;
}

NSString *LCGenerateRandomMACAddress(void) {
    uint8_t mac[6];
    for (int i = 0; i < 6; ++i) mac[i] = arc4random_uniform(256);
    mac[0] = (mac[0] | 0x02) & 0xFE;
    return [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]];
}

NSString *LCGenerateRandomInstallationID(int length) {
    static const char charset[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    if (length <= 0) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:(NSUInteger)length];
    for (int i = 0; i < length; ++i) {
        [result appendFormat:@"%c", charset[arc4random_uniform((uint32_t)strlen(charset))]];
    }
    return result;
}

void LCSetSpoofedUserAgent(NSString *userAgent) {
    g_customUserAgent = [userAgent copy];
    g_userAgentSpoofingEnabled = (userAgent != nil);
}

void LCSetUserAgentSpoofingEnabled(BOOL enabled) {
    g_userAgentSpoofingEnabled = enabled;
}

BOOL LCIsUserAgentSpoofingEnabled(void) {
    return g_userAgentSpoofingEnabled;
}

NSString *LCGetCurrentUserAgent(void) {
    return g_customUserAgent;
}

void LCUpdateUserAgentForProfile(void) {
    // No-op in Ghost-parity mode.
}

#pragma mark - Init

void DeviceSpoofingGuestHooksInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct rebinding rebindings[] = {
            {"uname", (void *)hook_uname, (void **)&orig_uname},
            {"sysctlbyname", (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname},
            {"sysctl", (void *)hook_sysctl, (void **)&orig_sysctl},
        };
        rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));

        Class uiDeviceClass = objc_getClass("UIDevice");
        LCInstallInstanceHook(uiDeviceClass, @selector(systemVersion), (IMP)hook_UIDevice_systemVersion, (IMP *)&orig_UIDevice_systemVersion);
        LCInstallInstanceHook(uiDeviceClass, @selector(name), (IMP)hook_UIDevice_name, (IMP *)&orig_UIDevice_name);
        LCInstallInstanceHook(uiDeviceClass, @selector(identifierForVendor), (IMP)hook_UIDevice_identifierForVendor, (IMP *)&orig_UIDevice_identifierForVendor);
        LCInstallInstanceHook(uiDeviceClass, @selector(batteryLevel), (IMP)hook_UIDevice_batteryLevel, (IMP *)&orig_UIDevice_batteryLevel);
        LCInstallInstanceHook(uiDeviceClass, @selector(batteryState), (IMP)hook_UIDevice_batteryState, (IMP *)&orig_UIDevice_batteryState);
        LCInstallInstanceHook(uiDeviceClass, @selector(isBatteryMonitoringEnabled), (IMP)hook_UIDevice_isBatteryMonitoringEnabled, (IMP *)&orig_UIDevice_isBatteryMonitoringEnabled);

        Class processInfoClass = objc_getClass("NSProcessInfo");
        LCInstallInstanceHook(processInfoClass, @selector(physicalMemory), (IMP)hook_NSProcessInfo_physicalMemory, (IMP *)&orig_NSProcessInfo_physicalMemory);
        LCInstallInstanceHook(processInfoClass, @selector(processorCount), (IMP)hook_NSProcessInfo_processorCount, (IMP *)&orig_NSProcessInfo_processorCount);
        LCInstallInstanceHook(processInfoClass, @selector(activeProcessorCount), (IMP)hook_NSProcessInfo_activeProcessorCount, (IMP *)&orig_NSProcessInfo_activeProcessorCount);
        LCInstallInstanceHook(processInfoClass, @selector(operatingSystemVersion), (IMP)hook_NSProcessInfo_operatingSystemVersion, (IMP *)&orig_NSProcessInfo_operatingSystemVersion);
        LCInstallInstanceHook(processInfoClass, @selector(operatingSystemVersionString), (IMP)hook_NSProcessInfo_operatingSystemVersionString, (IMP *)&orig_NSProcessInfo_operatingSystemVersionString);
        LCInstallInstanceHook(processInfoClass, @selector(thermalState), (IMP)hook_NSProcessInfo_thermalState, (IMP *)&orig_NSProcessInfo_thermalState);
        LCInstallInstanceHook(processInfoClass, @selector(isLowPowerModeEnabled), (IMP)hook_NSProcessInfo_isLowPowerModeEnabled, (IMP *)&orig_NSProcessInfo_isLowPowerModeEnabled);

        Class uiScreenClass = objc_getClass("UIScreen");
        LCInstallInstanceHook(uiScreenClass, @selector(brightness), (IMP)hook_UIScreen_brightness, (IMP *)&orig_UIScreen_brightness);

        Class asIdManagerClass = objc_getClass("ASIdentifierManager");
        LCInstallInstanceHook(asIdManagerClass, @selector(advertisingIdentifier), (IMP)hook_ASIdentifierManager_advertisingIdentifier, (IMP *)&orig_ASIdentifierManager_advertisingIdentifier);
        LCInstallInstanceHook(asIdManagerClass, @selector(isAdvertisingTrackingEnabled), (IMP)hook_ASIdentifierManager_isAdvertisingTrackingEnabled, (IMP *)&orig_ASIdentifierManager_isAdvertisingTrackingEnabled);

        Class fileManagerClass = objc_getClass("NSFileManager");
        LCInstallInstanceHook(fileManagerClass, @selector(ubiquityIdentityToken), (IMP)hook_NSFileManager_ubiquityIdentityToken, (IMP *)&orig_NSFileManager_ubiquityIdentityToken);

        Class carrierClass = objc_getClass("CTCarrier");
        LCInstallInstanceHook(carrierClass, @selector(carrierName), (IMP)hook_CTCarrier_carrierName, (IMP *)&orig_CTCarrier_carrierName);
    });
}
