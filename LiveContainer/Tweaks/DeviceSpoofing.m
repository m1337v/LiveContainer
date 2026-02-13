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
#import <WebKit/WebKit.h>
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

const LCDeviceProfile kDeviceProfileiPhone16e = {
    .modelIdentifier = "iPhone17,4",
    .hardwareModel = "D48AP",
    .marketingName = "iPhone 16e",
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
    .systemVersion = "26.0",
    .buildVersion = "24A5260a",
    .kernelVersion = "Darwin Kernel Version 25.0.0: Wed Jun 11 19:43:22 PDT 2025; root:xnu-12100.1.1~3/RELEASE_ARM64_T8140",
    .kernelRelease = "25.0.0",
    .physicalMemory = 12884901888ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 440,
    .screenHeight = 956,
    .chipName = "Apple A19 Pro",
    .gpuName = "Apple A19 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17Pro = {
    .modelIdentifier = "iPhone18,1",
    .hardwareModel = "D103AP",
    .marketingName = "iPhone 17 Pro",
    .systemVersion = "26.0",
    .buildVersion = "24A5260a",
    .kernelVersion = "Darwin Kernel Version 25.0.0: Wed Jun 11 19:43:22 PDT 2025; root:xnu-12100.1.1~3/RELEASE_ARM64_T8140",
    .kernelRelease = "25.0.0",
    .physicalMemory = 12884901888ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 402,
    .screenHeight = 874,
    .chipName = "Apple A19 Pro",
    .gpuName = "Apple A19 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17 = {
    .modelIdentifier = "iPhone18,3",
    .hardwareModel = "D57AP",
    .marketingName = "iPhone 17",
    .systemVersion = "26.0",
    .buildVersion = "24A5260a",
    .kernelVersion = "Darwin Kernel Version 25.0.0: Wed Jun 11 19:43:22 PDT 2025; root:xnu-12100.1.1~3/RELEASE_ARM64_T8130",
    .kernelRelease = "25.0.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A19",
    .gpuName = "Apple A19 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17Air = {
    .modelIdentifier = "iPhone18,4",
    .hardwareModel = "D58AP",
    .marketingName = "iPhone 17 Air",
    .systemVersion = "26.0",
    .buildVersion = "24A5260a",
    .kernelVersion = "Darwin Kernel Version 25.0.0: Wed Jun 11 19:43:22 PDT 2025; root:xnu-12100.1.1~3/RELEASE_ARM64_T8130",
    .kernelRelease = "25.0.0",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A19",
    .gpuName = "Apple A19 GPU"
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

// Boot time / uptime state
static BOOL g_bootTimeSpoofingEnabled = NO;
static NSTimeInterval g_bootTimeOffset = 0; // seconds subtracted from real boot time
static NSTimeInterval g_uptimeTarget = 0;   // target uptime in seconds

// Timezone, locale, and screen capture state
static NSString *g_spoofedTimezone = nil;
static NSString *g_spoofedLocale = nil;
static BOOL g_screenCaptureBlockEnabled = NO;

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
static NSString *(*orig_UIDevice_machineName)(id self, SEL _cmd) = NULL;
static id (*orig_UIDevice_deviceInfoForKey)(id self, SEL _cmd, NSString *key) = NULL;

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

static NSTimeInterval (*orig_NSProcessInfo_systemUptime)(id self, SEL _cmd) = NULL;

static id (*orig_NSFileManager_ubiquityIdentityToken)(id self, SEL _cmd) = NULL;
static NSDictionary *(*orig_NSFileManager_attributesOfFileSystemForPath)(id self, SEL _cmd, NSString *path, NSError **error) = NULL;
static NSString *(*orig_CTCarrier_carrierName)(id self, SEL _cmd) = NULL;

static NSString *(*orig_WKWebView_customUserAgent)(id self, SEL _cmd) = NULL;
static WKWebView *(*orig_WKWebView_initWithFrame)(id self, SEL _cmd, CGRect frame, WKWebViewConfiguration *config) = NULL;
static void (*orig_WKWebView_didFinishNavigation)(id self, SEL _cmd, WKWebView *webView, WKNavigation *navigation) = NULL;

static CGRect (*orig_UIScreen_bounds)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIScreen_nativeBounds)(id self, SEL _cmd) = NULL;
static CGFloat (*orig_UIScreen_scale)(id self, SEL _cmd) = NULL;
static CGFloat (*orig_UIScreen_nativeScale)(id self, SEL _cmd) = NULL;

static NSString *(*orig_UIDevice_model)(id self, SEL _cmd) = NULL;
static NSString *(*orig_UIDevice_localizedModel)(id self, SEL _cmd) = NULL;

static BOOL (*orig_NSProcessInfo_isOperatingSystemAtLeastVersion)(id self, SEL _cmd, NSOperatingSystemVersion version) = NULL;

static void (*orig_NSMutableURLRequest_setValue_forHTTPHeaderField)(id self, SEL _cmd, NSString *value, NSString *field) = NULL;
static void (*orig_WKWebViewConfiguration_setApplicationNameForUserAgent)(id self, SEL _cmd, NSString *name) = NULL;

static NSTimeZone *(*orig_NSTimeZone_localTimeZone)(id self, SEL _cmd) = NULL;
static NSTimeZone *(*orig_NSTimeZone_systemTimeZone)(id self, SEL _cmd) = NULL;
static NSLocale *(*orig_NSLocale_currentLocale)(id self, SEL _cmd) = NULL;
static NSLocale *(*orig_NSLocale_autoupdatingCurrentLocale)(id self, SEL _cmd) = NULL;
static BOOL (*orig_UIScreen_isCaptured)(id self, SEL _cmd) = NULL;

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef key) = NULL;

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

static CFTypeRef LCCopySpoofedGestaltValue(CFStringRef key) {
    if (!key || !LCDeviceSpoofingIsActive()) return NULL;

    if (CFEqual(key, CFSTR("ProductVersion"))) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("BuildVersion")) || CFEqual(key, CFSTR("j9Th5smJpdztHwc+i39zIg"))) {
        const char *value = LCSpoofedBuildVersion();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("ProductType"))) {
        const char *value = LCSpoofedMachineModel();
        if (value) return CFBridgingRetain(@(value));
    } else if (CFEqual(key, CFSTR("HardwareModel"))) {
        const char *value = LCSpoofedHardwareModel();
        if (value) return CFBridgingRetain(@(value));
    }

    return NULL;
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
        } else if (strcmp(name, "hw.product") == 0) {
            const char *value = LCSpoofedMachineModel();
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
        } else if (strcmp(name, "kern.boottime") == 0 && g_bootTimeSpoofingEnabled) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            if (ret == 0 && oldp && *oldlenp >= sizeof(struct timeval)) {
                struct timeval *tv = (struct timeval *)oldp;
                tv->tv_sec -= (time_t)g_bootTimeOffset;
            }
            return ret;
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
#ifdef HW_PRODUCT
                case HW_PRODUCT: {
                    const char *value = LCSpoofedMachineModel();
                    if (value) return LCWriteCStringValue(oldp, oldlenp, value);
                    break;
                }
#endif
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
                case KERN_BOOTTIME: {
                    if (g_bootTimeSpoofingEnabled) {
                        int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
                        if (ret == 0 && oldp && *oldlenp >= sizeof(struct timeval)) {
                            struct timeval *tv = (struct timeval *)oldp;
                            tv->tv_sec -= (time_t)g_bootTimeOffset;
                        }
                        return ret;
                    }
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

// MARK: - Timezone hooks

static NSTimeZone *hook_NSTimeZone_localTimeZone(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedTimezone.length > 0) {
        NSTimeZone *tz = [NSTimeZone timeZoneWithName:g_spoofedTimezone];
        if (tz) return tz;
    }
    if (orig_NSTimeZone_localTimeZone) return orig_NSTimeZone_localTimeZone(self, _cmd);
    return [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
}

static NSTimeZone *hook_NSTimeZone_systemTimeZone(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedTimezone.length > 0) {
        NSTimeZone *tz = [NSTimeZone timeZoneWithName:g_spoofedTimezone];
        if (tz) return tz;
    }
    if (orig_NSTimeZone_systemTimeZone) return orig_NSTimeZone_systemTimeZone(self, _cmd);
    return [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
}

// MARK: - Locale hooks

static NSLocale *hook_NSLocale_currentLocale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedLocale.length > 0) {
        return [[NSLocale alloc] initWithLocaleIdentifier:g_spoofedLocale];
    }
    if (orig_NSLocale_currentLocale) return orig_NSLocale_currentLocale(self, _cmd);
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
}

static NSLocale *hook_NSLocale_autoupdatingCurrentLocale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_spoofedLocale.length > 0) {
        return [[NSLocale alloc] initWithLocaleIdentifier:g_spoofedLocale];
    }
    if (orig_NSLocale_autoupdatingCurrentLocale) return orig_NSLocale_autoupdatingCurrentLocale(self, _cmd);
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
}

// MARK: - Screen capture block hook

static BOOL hook_UIScreen_isCaptured(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_screenCaptureBlockEnabled) {
        return NO; // Always report not captured
    }
    if (orig_UIScreen_isCaptured) return orig_UIScreen_isCaptured(self, _cmd);
    return NO;
}

// MARK: - Uptime hook (paired with KERN_BOOTTIME sysctl hook above)
static NSTimeInterval hook_NSProcessInfo_systemUptime(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_bootTimeSpoofingEnabled) {
        NSTimeInterval real = orig_NSProcessInfo_systemUptime ? orig_NSProcessInfo_systemUptime(self, _cmd) : 0;
        // Shift uptime by the same offset used for KERN_BOOTTIME so they stay consistent
        return real + g_bootTimeOffset;
    }
    if (orig_NSProcessInfo_systemUptime) return orig_NSProcessInfo_systemUptime(self, _cmd);
    return 0;
}

// MARK: - User-Agent auto-generation from profile
static NSString *LCBuildUserAgentForProfile(void) {
    if (!g_currentProfile) return nil;
    const char *model = g_currentProfile->modelIdentifier;
    const char *version = LCSpoofedSystemVersion();
    const char *build = LCSpoofedBuildVersion();
    if (!model || !version || !build) return nil;

    // Determine device type from identifier
    BOOL isIPad = (strncmp(model, "iPad", 4) == 0);
    NSString *versionUnderscored = [[@(version) stringByReplacingOccurrencesOfString:@"." withString:@"_"] copy];

    // Build a realistic Safari-style UA
    if (isIPad) {
        return [NSString stringWithFormat:
            @"Mozilla/5.0 (iPad; CPU OS %@ like Mac OS X) "
            @"AppleWebKit/605.1.15 (KHTML, like Gecko) "
            @"Version/%s Mobile/%s Safari/604.1",
            versionUnderscored, version, build];
    }
    return [NSString stringWithFormat:
        @"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) "
        @"AppleWebKit/605.1.15 (KHTML, like Gecko) "
        @"Version/%s Mobile/%s Safari/604.1",
        versionUnderscored, version, build];
}

// Replace iOS version pattern in existing User-Agent strings
static NSString *LCModifyUserAgentVersion(NSString *ua) {
    if (!ua || ua.length == 0) return ua;
    const char *version = LCSpoofedSystemVersion();
    const char *build = LCSpoofedBuildVersion();
    if (!version || !build) return ua;

    NSString *underscored = [[@(version) stringByReplacingOccurrencesOfString:@"." withString:@"_"] copy];
    NSMutableString *result = [ua mutableCopy];

    // Pattern: CPU iPhone OS 15_4_1 like Mac OS X
    NSRegularExpression *r1 = [NSRegularExpression regularExpressionWithPattern:@"(CPU\\s+(?:iPhone\\s+)?OS\\s+)\\d+[_.]\\d+(?:[_.]\\d+)?(\\s+like)" options:0 error:nil];
    result = [[r1 stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length)
        withTemplate:[NSString stringWithFormat:@"$1%@$2", underscored]] mutableCopy];

    // Pattern: Version/15.4
    NSRegularExpression *r2 = [NSRegularExpression regularExpressionWithPattern:@"(Version/)\\d+\\.\\d+(?:\\.\\d+)?" options:0 error:nil];
    result = [[r2 stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length)
        withTemplate:[NSString stringWithFormat:@"$1%s", version]] mutableCopy];

    // Pattern: Mobile/19F77
    NSRegularExpression *r3 = [NSRegularExpression regularExpressionWithPattern:@"(Mobile/)\\w+" options:0 error:nil];
    result = [[r3 stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length)
        withTemplate:[NSString stringWithFormat:@"$1%s", build]] mutableCopy];

    return result;
}

// MARK: - UIScreen hooks (screen size spoofing)
static CGRect hook_UIScreen_bounds(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return CGRectMake(0, 0, g_currentProfile->screenWidth, g_currentProfile->screenHeight);
    }
    if (orig_UIScreen_bounds) return orig_UIScreen_bounds(self, _cmd);
    return CGRectZero;
}

static CGRect hook_UIScreen_nativeBounds(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        CGFloat scale = g_currentProfile->screenScale;
        return CGRectMake(0, 0,
            g_currentProfile->screenWidth * scale,
            g_currentProfile->screenHeight * scale);
    }
    if (orig_UIScreen_nativeBounds) return orig_UIScreen_nativeBounds(self, _cmd);
    return CGRectZero;
}

static CGFloat hook_UIScreen_scale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return g_currentProfile->screenScale;
    }
    if (orig_UIScreen_scale) return orig_UIScreen_scale(self, _cmd);
    return 2.0;
}

static CGFloat hook_UIScreen_nativeScale(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        return g_currentProfile->screenScale;
    }
    if (orig_UIScreen_nativeScale) return orig_UIScreen_nativeScale(self, _cmd);
    return 2.0;
}

// MARK: - UIDevice model hooks
static NSString *hook_UIDevice_model(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        const char *ident = g_currentProfile->modelIdentifier;
        if (ident && strncmp(ident, "iPad", 4) == 0) return @"iPad";
        return @"iPhone";
    }
    if (orig_UIDevice_model) return orig_UIDevice_model(self, _cmd);
    return @"iPhone";
}

static NSString *hook_UIDevice_localizedModel(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive() && g_currentProfile) {
        const char *ident = g_currentProfile->modelIdentifier;
        if (ident && strncmp(ident, "iPad", 4) == 0) return @"iPad";
        return @"iPhone";
    }
    if (orig_UIDevice_localizedModel) return orig_UIDevice_localizedModel(self, _cmd);
    return @"iPhone";
}

static NSString *hook_UIDevice_machineName(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        const char *value = LCSpoofedMachineModel();
        if (value) return @(value);
    }
    if (orig_UIDevice_machineName) return orig_UIDevice_machineName(self, _cmd);
    return @"iPhone";
}

static id hook_UIDevice_deviceInfoForKey(id self, SEL _cmd, NSString *key) {
    id original = orig_UIDevice_deviceInfoForKey ? orig_UIDevice_deviceInfoForKey(self, _cmd, key) : nil;
    if (!LCDeviceSpoofingIsActive() || key.length == 0) {
        return original;
    }

    if ([key isEqualToString:@"ProductVersion"]) {
        const char *value = LCSpoofedSystemVersion();
        if (value) return @(value);
    } else if ([key isEqualToString:@"BuildVersion"] || [key isEqualToString:@"j9Th5smJpdztHwc+i39zIg"]) {
        const char *value = LCSpoofedBuildVersion();
        if (value) return @(value);
    } else if ([key isEqualToString:@"ProductType"]) {
        const char *value = LCSpoofedMachineModel();
        if (value) return @(value);
    } else if ([key isEqualToString:@"HardwareModel"]) {
        const char *value = LCSpoofedHardwareModel();
        if (value) return @(value);
    } else if ([key isEqualToString:@"DeviceName"]) {
        if (g_customDeviceName.length > 0) return g_customDeviceName;
        if (g_currentProfile && g_currentProfile->marketingName) return @(g_currentProfile->marketingName);
    }

    return original;
}

static CFTypeRef hook_MGCopyAnswer(CFStringRef key) {
    CFTypeRef spoofed = LCCopySpoofedGestaltValue(key);
    if (spoofed) {
        return spoofed;
    }
    if (orig_MGCopyAnswer) {
        return orig_MGCopyAnswer(key);
    }
    return NULL;
}

// MARK: - NSProcessInfo isOperatingSystemAtLeastVersion
static BOOL hook_NSProcessInfo_isOperatingSystemAtLeastVersion(id self, SEL _cmd, NSOperatingSystemVersion version) {
    if (LCDeviceSpoofingIsActive()) {
        const char *v = LCSpoofedSystemVersion();
        if (v) {
            NSOperatingSystemVersion spoofed = LCParseOSVersion(@(v));
            BOOL result = (spoofed.majorVersion > version.majorVersion) ||
                ((spoofed.majorVersion == version.majorVersion) &&
                 (spoofed.minorVersion > version.minorVersion)) ||
                ((spoofed.majorVersion == version.majorVersion) &&
                 (spoofed.minorVersion == version.minorVersion) &&
                 (spoofed.patchVersion >= version.patchVersion));
            return result;
        }
    }
    if (orig_NSProcessInfo_isOperatingSystemAtLeastVersion)
        return orig_NSProcessInfo_isOperatingSystemAtLeastVersion(self, _cmd, version);
    return NO;
}

// MARK: - NSMutableURLRequest User-Agent hook
static void hook_NSMutableURLRequest_setValue_forHTTPHeaderField(id self, SEL _cmd, NSString *value, NSString *field) {
    if (LCDeviceSpoofingIsActive() && [field caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame && value.length > 0) {
        NSString *modified = LCModifyUserAgentVersion(value);
        if (modified && ![modified isEqualToString:value]) {
            if (orig_NSMutableURLRequest_setValue_forHTTPHeaderField)
                orig_NSMutableURLRequest_setValue_forHTTPHeaderField(self, _cmd, modified, field);
            return;
        }
    }
    if (orig_NSMutableURLRequest_setValue_forHTTPHeaderField)
        orig_NSMutableURLRequest_setValue_forHTTPHeaderField(self, _cmd, value, field);
}

// MARK: - WKWebViewConfiguration applicationNameForUserAgent hook
static void hook_WKWebViewConfiguration_setApplicationNameForUserAgent(id self, SEL _cmd, NSString *name) {
    if (LCDeviceSpoofingIsActive() && name.length > 0) {
        NSString *modified = LCModifyUserAgentVersion(name);
        if (modified && ![modified isEqualToString:name]) {
            if (orig_WKWebViewConfiguration_setApplicationNameForUserAgent)
                orig_WKWebViewConfiguration_setApplicationNameForUserAgent(self, _cmd, modified);
            return;
        }
    }
    if (orig_WKWebViewConfiguration_setApplicationNameForUserAgent)
        orig_WKWebViewConfiguration_setApplicationNameForUserAgent(self, _cmd, name);
}

// MARK: - WKWebView JS fingerprint injection script
static NSString *LCBuildFingerprintInjectionScript(void) {
    if (!g_currentProfile) return nil;

    NSInteger screenW = (NSInteger)g_currentProfile->screenWidth;
    NSInteger screenH = (NSInteger)g_currentProfile->screenHeight;
    double dpr = (double)g_currentProfile->screenScale;
    uint32_t cpuCores = g_currentProfile->cpuCoreCount;
    double memoryGB = (double)g_currentProfile->physicalMemory / (1024.0 * 1024.0 * 1024.0);
    // navigator.deviceMemory is rounded to power-of-2 in GB (4, 8, etc.)
    int deviceMem = (int)memoryGB;
    if (deviceMem > 8) deviceMem = 8;
    else if (deviceMem > 4) deviceMem = 8;
    else if (deviceMem > 2) deviceMem = 4;

    NSString *spoofedUA = g_customUserAgent ?: LCBuildUserAgentForProfile();
    NSString *uaJS = @"";
    if (spoofedUA) {
        uaJS = [NSString stringWithFormat:
            @"try{Object.defineProperty(navigator,'userAgent',{get:function(){return '%@'}});}catch(e){}\n"
            @"try{Object.defineProperty(navigator,'appVersion',{get:function(){return '%@'}});}catch(e){}\n",
            [spoofedUA stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"],
            [[spoofedUA stringByReplacingOccurrencesOfString:@"Mozilla/" withString:@""] stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
    }

    return [NSString stringWithFormat:
        @"(function(){\n"
        // Screen size spoofing
        @"try{Object.defineProperty(screen,'width',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'height',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'availWidth',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'availHeight',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'colorDepth',{get:function(){return 24}});}catch(e){}\n"
        @"try{Object.defineProperty(screen,'pixelDepth',{get:function(){return 24}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'devicePixelRatio',{get:function(){return %f}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'innerWidth',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'innerHeight',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'outerWidth',{get:function(){return %ld}});}catch(e){}\n"
        @"try{Object.defineProperty(window,'outerHeight',{get:function(){return %ld}});}catch(e){}\n"
        // Hardware concurrency + memory
        @"try{Object.defineProperty(navigator,'hardwareConcurrency',{get:function(){return %u}});}catch(e){}\n"
        @"try{Object.defineProperty(navigator,'deviceMemory',{get:function(){return %d}});}catch(e){}\n"
        // User-Agent
        @"%@"
        // Canvas fingerprint noise
        @"(function(){\n"
        @"  var seed=%u;\n"
        @"  var origToDU=HTMLCanvasElement.prototype.toDataURL;\n"
        @"  var origGID=CanvasRenderingContext2D.prototype.getImageData;\n"
        @"  function addNoise(canvas){\n"
        @"    try{var ctx=canvas.getContext('2d');if(!ctx)return;\n"
        @"    var d=ctx.getImageData(0,0,canvas.width,canvas.height);\n"
        @"    var p=d.data;var s=seed;\n"
        @"    for(var i=0;i<p.length;i+=160){\n"
        @"      s=(s*1103515245+12345)&0x7fffffff;\n"
        @"      p[i]=(p[i]+(s%%3)-1)&0xff;\n"
        @"    }\n"
        @"    ctx.putImageData(d,0,0);}catch(e){}\n"
        @"  }\n"
        @"  HTMLCanvasElement.prototype.toDataURL=function(){addNoise(this);return origToDU.apply(this,arguments)};\n"
        @"  CanvasRenderingContext2D.prototype.getImageData=function(){\n"
        @"    var d=origGID.apply(this,arguments);var p=d.data;var s=seed;\n"
        @"    for(var i=0;i<p.length;i+=160){s=(s*1103515245+12345)&0x7fffffff;p[i]=(p[i]+(s%%3)-1)&0xff;}\n"
        @"    return d;\n"
        @"  };\n"
        @"})();\n"
        // WebGL parameter spoofing
        @"(function(){\n"
        @"  var origGP=WebGLRenderingContext.prototype.getParameter;\n"
        @"  WebGLRenderingContext.prototype.getParameter=function(p){\n"
        @"    if(p===37445)return'Apple Inc.';\n"
        @"    if(p===37446)return'Apple GPU';\n"
        @"    return origGP.call(this,p);\n"
        @"  };\n"
        @"  if(typeof WebGL2RenderingContext!=='undefined'){\n"
        @"    var origGP2=WebGL2RenderingContext.prototype.getParameter;\n"
        @"    WebGL2RenderingContext.prototype.getParameter=function(p){\n"
        @"      if(p===37445)return'Apple Inc.';\n"
        @"      if(p===37446)return'Apple GPU';\n"
        @"      return origGP2.call(this,p);\n"
        @"    };\n"
        @"  }\n"
        @"})();\n"
        // Audio fingerprint noise
        @"(function(){\n"
        @"  if(window.AudioBuffer){\n"
        @"    var origGCD=AudioBuffer.prototype.getChannelData;\n"
        @"    AudioBuffer.prototype.getChannelData=function(){\n"
        @"      var d=origGCD.apply(this,arguments);\n"
        @"      for(var i=0;i<d.length;i+=100){d[i]+=(Math.random()-0.5)*0.0001;}\n"
        @"      return d;\n"
        @"    };\n"
        @"  }\n"
        @"  if(window.AnalyserNode){\n"
        @"    var origGFFD=AnalyserNode.prototype.getFloatFrequencyData;\n"
        @"    AnalyserNode.prototype.getFloatFrequencyData=function(a){\n"
        @"      origGFFD.call(this,a);\n"
        @"      for(var i=0;i<a.length;i++){a[i]+=(Math.random()-0.5)*0.1;}\n"
        @"    };\n"
        @"  }\n"
        @"})();\n"
        // Font metric noise
        @"(function(){\n"
        @"  var origMT=CanvasRenderingContext2D.prototype.measureText;\n"
        @"  CanvasRenderingContext2D.prototype.measureText=function(t){\n"
        @"    var r=origMT.apply(this,arguments);\n"
        @"    try{Object.defineProperty(r,'width',{value:r.width*(1+(Math.random()-0.5)*0.005)});}catch(e){}\n"
        @"    return r;\n"
        @"  };\n"
        @"})();\n"
        @"})();\n",
        (long)screenW, (long)screenH, (long)screenW, (long)screenH,
        dpr,
        (long)screenW, (long)(screenH - 44), // innerHeight minus status bar
        (long)screenW, (long)screenH,
        cpuCores, deviceMem,
        uaJS,
        arc4random()];
}

// MARK: - WKWebView initWithFrame hook (inject UA + fingerprint JS)
static WKWebView *hook_WKWebView_initWithFrame(id self, SEL _cmd, CGRect frame, WKWebViewConfiguration *config) {
    WKWebView *webView = orig_WKWebView_initWithFrame ? orig_WKWebView_initWithFrame(self, _cmd, frame, config) : nil;
    if (!webView || !LCDeviceSpoofingIsActive()) return webView;

    // Set custom User-Agent
    NSString *ua = g_customUserAgent;
    if (!ua && g_userAgentSpoofingEnabled) ua = LCBuildUserAgentForProfile();
    if (!ua) {
        // Always auto-generate if we have a profile (even if UA spoofing not explicitly set)
        ua = LCBuildUserAgentForProfile();
    }
    if (ua) {
        [webView setValue:ua forKey:@"customUserAgent"];
    }

    // Inject fingerprint-protection JS into the configuration's user content controller
    if (g_canvasFingerprintProtectionEnabled || g_currentProfile) {
        NSString *script = LCBuildFingerprintInjectionScript();
        if (script && config) {
            WKUserContentController *ucc = config.userContentController;
            if (!ucc) {
                ucc = [[WKUserContentController alloc] init];
                config.userContentController = ucc;
            }
            WKUserScript *us = [[WKUserScript alloc] initWithSource:script
                injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                forMainFrameOnly:NO];
            [ucc addUserScript:us];
        }
    }

    return webView;
}

// MARK: - WKWebView User-Agent hook
static NSString *hook_WKWebView_customUserAgent(id self, SEL _cmd) {
    if (LCDeviceSpoofingIsActive()) {
        if (g_userAgentSpoofingEnabled && g_customUserAgent.length > 0)
            return g_customUserAgent;
        // Auto-generate from profile if available
        NSString *auto_ua = LCBuildUserAgentForProfile();
        if (auto_ua) return auto_ua;
    }
    if (orig_WKWebView_customUserAgent) return orig_WKWebView_customUserAgent(self, _cmd);
    return nil;
}

// MARK: - NSFileManager storage hook
static NSDictionary *hook_NSFileManager_attributesOfFileSystemForPath(id self, SEL _cmd, NSString *path, NSError **error) {
    NSDictionary *attrs = orig_NSFileManager_attributesOfFileSystemForPath
        ? orig_NSFileManager_attributesOfFileSystemForPath(self, _cmd, path, error)
        : nil;
    if (LCDeviceSpoofingIsActive() && g_storageSpoofingEnabled && g_spoofedStorageTotal > 0 && attrs) {
        NSMutableDictionary *mutable = [attrs mutableCopy];
        mutable[NSFileSystemSize] = @(g_spoofedStorageTotal);
        mutable[NSFileSystemFreeSize] = @(g_spoofedStorageFree);
        return [mutable copy];
    }
    return attrs;
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
            @"iPhone 16e": [NSValue valueWithPointer:&kDeviceProfileiPhone16e],
            @"iPhone 15 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone15ProMax],
            @"iPhone 15 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone15Pro],
            @"iPhone 14 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone14ProMax],
            @"iPhone 14 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone14Pro],
            @"iPhone 13 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone13ProMax],
            @"iPhone 13 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone13Pro],
        };
    });

    NSValue *value = profileMap[profileName];
    if (!value) {
        g_currentProfileName = @"iPhone 16";
        value = profileMap[g_currentProfileName];
    }
    g_currentProfile = value ? (const LCDeviceProfile *)value.pointerValue : NULL;
}

NSString *LCGetCurrentDeviceProfile(void) {
    return g_currentProfileName;
}

NSDictionary<NSString *, NSDictionary *> *LCGetAvailableDeviceProfiles(void) {
    return @{
        @"iPhone 17 Pro Max": @{@"model": @"iPhone18,2", @"version": @"26.0", @"memory": @"12 GB", @"chip": @"A19 Pro"},
        @"iPhone 17 Pro": @{@"model": @"iPhone18,1", @"version": @"26.0", @"memory": @"12 GB", @"chip": @"A19 Pro"},
        @"iPhone 17": @{@"model": @"iPhone18,3", @"version": @"26.0", @"memory": @"8 GB", @"chip": @"A19"},
        @"iPhone 17 Air": @{@"model": @"iPhone18,4", @"version": @"26.0", @"memory": @"8 GB", @"chip": @"A19"},
        @"iPhone 16 Pro Max": @{@"model": @"iPhone17,2", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18 Pro"},
        @"iPhone 16 Pro": @{@"model": @"iPhone17,1", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18 Pro"},
        @"iPhone 16": @{@"model": @"iPhone17,3", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18"},
        @"iPhone 16e": @{@"model": @"iPhone17,4", @"version": @"18.1", @"memory": @"8 GB", @"chip": @"A18"},
        @"iPhone 15 Pro Max": @{@"model": @"iPhone16,2", @"version": @"17.6.1", @"memory": @"8 GB", @"chip": @"A17 Pro"},
        @"iPhone 15 Pro": @{@"model": @"iPhone16,1", @"version": @"17.6.1", @"memory": @"8 GB", @"chip": @"A17 Pro"},
        @"iPhone 14 Pro Max": @{@"model": @"iPhone15,3", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A16"},
        @"iPhone 14 Pro": @{@"model": @"iPhone15,2", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A16"},
        @"iPhone 13 Pro Max": @{@"model": @"iPhone14,3", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A15"},
        @"iPhone 13 Pro": @{@"model": @"iPhone14,2", @"version": @"17.6.1", @"memory": @"6 GB", @"chip": @"A15"},
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

// Timezone spoofing
void LCSetSpoofedTimezone(NSString *timezone) { g_spoofedTimezone = [timezone copy]; }
NSString *LCGetSpoofedTimezone(void) { return g_spoofedTimezone; }

// Locale spoofing
void LCSetSpoofedLocale(NSString *locale) { g_spoofedLocale = [locale copy]; }
NSString *LCGetSpoofedLocale(void) { return g_spoofedLocale; }

// Screen capture detection blocking
void LCSetScreenCaptureBlockEnabled(BOOL enabled) { g_screenCaptureBlockEnabled = enabled; }
BOOL LCIsScreenCaptureBlockEnabled(void) { return g_screenCaptureBlockEnabled; }

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

void LCSetSpoofedBootTimeRange(NSString *range) {
    // Calculate a random uptime within the specified range, then derive
    // a boot-time offset that shifts KERN_BOOTTIME backwards so that
    //   now - spoofed_boottime ≈ randomUptime
    NSTimeInterval lo, hi;
    if ([range isEqualToString:@"short"]) {
        lo = 1 * 3600;  hi = 4 * 3600;       // 1–4 h
    } else if ([range isEqualToString:@"long"]) {
        lo = 24 * 3600;  hi = 72 * 3600;     // 1–3 d
    } else if ([range isEqualToString:@"week"]) {
        lo = 72 * 3600;  hi = 168 * 3600;    // 3–7 d
    } else { /* medium */
        lo = 4 * 3600;   hi = 24 * 3600;     // 4–24 h
    }
    g_uptimeTarget = lo + (arc4random_uniform((uint32_t)(hi - lo)));

    // Derive the offset: how much we need to shift the boot time
    // Real uptime from NSProcessInfo, target uptime from g_uptimeTarget
    NSTimeInterval realUptime = NSProcessInfo.processInfo.systemUptime;
    g_bootTimeOffset = g_uptimeTarget - realUptime;  // can be negative when target > real
    g_bootTimeSpoofingEnabled = YES;
}

void LCSetUptimeOffset(NSTimeInterval offset) {
    g_bootTimeOffset = offset;
    g_bootTimeSpoofingEnabled = YES;
}

void LCRandomizeUptime(void) {
    LCSetSpoofedBootTimeRange(@"medium");
}

void LCSetSpoofedBootTime(time_t bootTimestamp) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    g_bootTimeOffset = now - (NSTimeInterval)bootTimestamp - NSProcessInfo.processInfo.systemUptime;
    g_bootTimeSpoofingEnabled = YES;
}

time_t LCGetSpoofedBootTime(void) {
    struct timeval tv = {0, 0};
    size_t len = sizeof(tv);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (orig_sysctl && orig_sysctl(mib, 2, &tv, &len, NULL, 0) == 0) {
        if (g_bootTimeSpoofingEnabled) {
            tv.tv_sec -= (time_t)g_bootTimeOffset;
        }
        return tv.tv_sec;
    }
    return 0;
}

NSTimeInterval LCGetSpoofedUptime(void) {
    NSTimeInterval real = NSProcessInfo.processInfo.systemUptime;
    if (g_bootTimeSpoofingEnabled) {
        return real + g_bootTimeOffset;
    }
    return real;
}

void LCSetStorageSpoofingEnabled(BOOL enabled) { g_storageSpoofingEnabled = enabled; }
BOOL LCIsStorageSpoofingEnabled(void) { return g_storageSpoofingEnabled; }

void LCSetSpoofedStorageCapacity(long long capacityGB) {
    g_spoofedStorageCapacityGB = [NSString stringWithFormat:@"%lld", capacityGB];
    g_storageSpoofingEnabled = YES;
    g_spoofedStorageTotal = (uint64_t)(capacityGB * 1000LL * 1000LL * 1000LL);
    g_spoofedStorageFree = (uint64_t)((double)g_spoofedStorageTotal * (0.25 + (arc4random_uniform(20) / 100.0)));
    g_spoofedStorageFreeGB = [NSString stringWithFormat:@"%.1f", g_spoofedStorageFree / 1e9];
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
    if (g_customUserAgent) return g_customUserAgent;
    return LCBuildUserAgentForProfile();
}

void LCUpdateUserAgentForProfile(void) {
    NSString *ua = LCBuildUserAgentForProfile();
    if (ua) {
        g_customUserAgent = [ua copy];
        g_userAgentSpoofingEnabled = YES;
    }
}

#pragma mark - Init

void DeviceSpoofingGuestHooksInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct rebinding rebindings[] = {
            {"uname", (void *)hook_uname, (void **)&orig_uname},
            {"sysctlbyname", (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname},
            {"sysctl", (void *)hook_sysctl, (void **)&orig_sysctl},
            {"MGCopyAnswer", (void *)hook_MGCopyAnswer, (void **)&orig_MGCopyAnswer},
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
        LCInstallInstanceHook(processInfoClass, @selector(systemUptime), (IMP)hook_NSProcessInfo_systemUptime, (IMP *)&orig_NSProcessInfo_systemUptime);

        Class uiScreenClass = objc_getClass("UIScreen");
        LCInstallInstanceHook(uiScreenClass, @selector(brightness), (IMP)hook_UIScreen_brightness, (IMP *)&orig_UIScreen_brightness);
        LCInstallInstanceHook(uiScreenClass, @selector(bounds), (IMP)hook_UIScreen_bounds, (IMP *)&orig_UIScreen_bounds);
        LCInstallInstanceHook(uiScreenClass, @selector(nativeBounds), (IMP)hook_UIScreen_nativeBounds, (IMP *)&orig_UIScreen_nativeBounds);
        LCInstallInstanceHook(uiScreenClass, @selector(scale), (IMP)hook_UIScreen_scale, (IMP *)&orig_UIScreen_scale);
        LCInstallInstanceHook(uiScreenClass, @selector(nativeScale), (IMP)hook_UIScreen_nativeScale, (IMP *)&orig_UIScreen_nativeScale);

        LCInstallInstanceHook(uiDeviceClass, @selector(model), (IMP)hook_UIDevice_model, (IMP *)&orig_UIDevice_model);
        LCInstallInstanceHook(uiDeviceClass, @selector(localizedModel), (IMP)hook_UIDevice_localizedModel, (IMP *)&orig_UIDevice_localizedModel);
        SEL machineNameSelector = NSSelectorFromString(@"machineName");
        if ([uiDeviceClass respondsToSelector:machineNameSelector]) {
            Class uiDeviceMetaClass = object_getClass(uiDeviceClass);
            LCInstallInstanceHook(uiDeviceMetaClass, machineNameSelector, (IMP)hook_UIDevice_machineName, (IMP *)&orig_UIDevice_machineName);
        }
        SEL deviceInfoForKeySelector = NSSelectorFromString(@"_deviceInfoForKey:");
        if ([uiDeviceClass instancesRespondToSelector:deviceInfoForKeySelector]) {
            LCInstallInstanceHook(uiDeviceClass, deviceInfoForKeySelector, (IMP)hook_UIDevice_deviceInfoForKey, (IMP *)&orig_UIDevice_deviceInfoForKey);
        }

        LCInstallInstanceHook(processInfoClass, @selector(isOperatingSystemAtLeastVersion:), (IMP)hook_NSProcessInfo_isOperatingSystemAtLeastVersion, (IMP *)&orig_NSProcessInfo_isOperatingSystemAtLeastVersion);

        // NSMutableURLRequest User-Agent interception
        Class urlReqClass = objc_getClass("NSMutableURLRequest");
        LCInstallInstanceHook(urlReqClass, @selector(setValue:forHTTPHeaderField:), (IMP)hook_NSMutableURLRequest_setValue_forHTTPHeaderField, (IMP *)&orig_NSMutableURLRequest_setValue_forHTTPHeaderField);

        Class asIdManagerClass = objc_getClass("ASIdentifierManager");
        LCInstallInstanceHook(asIdManagerClass, @selector(advertisingIdentifier), (IMP)hook_ASIdentifierManager_advertisingIdentifier, (IMP *)&orig_ASIdentifierManager_advertisingIdentifier);
        LCInstallInstanceHook(asIdManagerClass, @selector(isAdvertisingTrackingEnabled), (IMP)hook_ASIdentifierManager_isAdvertisingTrackingEnabled, (IMP *)&orig_ASIdentifierManager_isAdvertisingTrackingEnabled);

        Class fileManagerClass = objc_getClass("NSFileManager");
        LCInstallInstanceHook(fileManagerClass, @selector(ubiquityIdentityToken), (IMP)hook_NSFileManager_ubiquityIdentityToken, (IMP *)&orig_NSFileManager_ubiquityIdentityToken);

        Class carrierClass = objc_getClass("CTCarrier");
        LCInstallInstanceHook(carrierClass, @selector(carrierName), (IMP)hook_CTCarrier_carrierName, (IMP *)&orig_CTCarrier_carrierName);

        // Timezone hooks (class methods)
        if (g_spoofedTimezone.length > 0) {
            Class timeZoneClass = objc_getClass("NSTimeZone");
            Class timeZoneMeta = object_getClass(timeZoneClass);
            LCInstallInstanceHook(timeZoneMeta, @selector(localTimeZone), (IMP)hook_NSTimeZone_localTimeZone, (IMP *)&orig_NSTimeZone_localTimeZone);
            LCInstallInstanceHook(timeZoneMeta, @selector(systemTimeZone), (IMP)hook_NSTimeZone_systemTimeZone, (IMP *)&orig_NSTimeZone_systemTimeZone);
        }

        // Locale hooks (class methods)
        if (g_spoofedLocale.length > 0) {
            Class localeClass = objc_getClass("NSLocale");
            Class localeMeta = object_getClass(localeClass);
            LCInstallInstanceHook(localeMeta, @selector(currentLocale), (IMP)hook_NSLocale_currentLocale, (IMP *)&orig_NSLocale_currentLocale);
            LCInstallInstanceHook(localeMeta, @selector(autoupdatingCurrentLocale), (IMP)hook_NSLocale_autoupdatingCurrentLocale, (IMP *)&orig_NSLocale_autoupdatingCurrentLocale);
        }

        // Screen capture detection blocking
        if (g_screenCaptureBlockEnabled) {
            LCInstallInstanceHook(uiScreenClass, @selector(isCaptured), (IMP)hook_UIScreen_isCaptured, (IMP *)&orig_UIScreen_isCaptured);
        }

        // WKWebView hooks — always install for UA spoofing + JS injection
        Class wkWebViewClass = objc_getClass("WKWebView");
        if (wkWebViewClass) {
            LCInstallInstanceHook(wkWebViewClass, @selector(customUserAgent), (IMP)hook_WKWebView_customUserAgent, (IMP *)&orig_WKWebView_customUserAgent);
            LCInstallInstanceHook(wkWebViewClass, @selector(initWithFrame:configuration:), (IMP)hook_WKWebView_initWithFrame, (IMP *)&orig_WKWebView_initWithFrame);
        }

        // WKWebViewConfiguration hook
        Class wkConfigClass = objc_getClass("WKWebViewConfiguration");
        if (wkConfigClass) {
            LCInstallInstanceHook(wkConfigClass, @selector(setApplicationNameForUserAgent:), (IMP)hook_WKWebViewConfiguration_setApplicationNameForUserAgent, (IMP *)&orig_WKWebViewConfiguration_setApplicationNameForUserAgent);
        }

        // NSFileManager storage spoofing
        if (g_storageSpoofingEnabled && g_spoofedStorageTotal > 0) {
            Class fileManagerClass2 = objc_getClass("NSFileManager");
            // Hook attributesOfFileSystemForPath:error:
            Method m = class_getInstanceMethod(fileManagerClass2, @selector(attributesOfFileSystemForPath:error:));
            if (m) {
                orig_NSFileManager_attributesOfFileSystemForPath = (NSDictionary *(*)(id, SEL, NSString *, NSError **))
                    method_setImplementation(m, (IMP)hook_NSFileManager_attributesOfFileSystemForPath);
            }
        }
    });
}
