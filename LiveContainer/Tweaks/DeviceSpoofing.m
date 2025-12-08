//
//  DeviceSpoofing.m
//  LiveContainer
//
//  Device spoofing implementation based on Ghost/Nomix/BlazeTinder+ patterns
//  Extended for iOS 18.x and iOS 26.x support
//  Comprehensive anti-fingerprinting protection
//

#import "DeviceSpoofing.h"
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <AdSupport/AdSupport.h>
#import <CommonCrypto/CommonDigest.h>
#import "../../fishhook/fishhook.h"

#pragma mark - Device Profiles - iOS 18.x (iPhone 16 Series)

const LCDeviceProfile kDeviceProfileiPhone16ProMax = {
    .modelIdentifier = "iPhone17,2",
    .hardwareModel = "D94AP",
    .marketingName = "iPhone 16 Pro Max",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8140",
    .kernelRelease = "24.1.0",
    .physicalMemory = 8589934592ULL, // 8GB
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
    .physicalMemory = 8589934592ULL, // 8GB
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
    .physicalMemory = 8589934592ULL, // 8GB
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 393,
    .screenHeight = 852,
    .chipName = "Apple A18",
    .gpuName = "Apple A18 GPU"
};

#pragma mark - Device Profiles - iOS 17.x (iPhone 15 Series)

const LCDeviceProfile kDeviceProfileiPhone15ProMax = {
    .modelIdentifier = "iPhone16,2",
    .hardwareModel = "D84AP",
    .marketingName = "iPhone 15 Pro Max",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8130",
    .kernelRelease = "23.6.0",
    .physicalMemory = 8589934592ULL, // 8GB
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

#pragma mark - Device Profiles - iOS 17.x (iPhone 14 Series)

const LCDeviceProfile kDeviceProfileiPhone14ProMax = {
    .modelIdentifier = "iPhone15,3",
    .hardwareModel = "D74AP",
    .marketingName = "iPhone 14 Pro Max",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8120",
    .kernelRelease = "23.6.0",
    .physicalMemory = 6442450944ULL, // 6GB
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

#pragma mark - Device Profiles - iOS 17.x (iPhone 13 Series)

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

#pragma mark - Device Profiles - iPad Pro M4 (iOS 18.x / iPadOS 18.x)

const LCDeviceProfile kDeviceProfileiPadPro13_M4 = {
    .modelIdentifier = "iPad16,5",
    .hardwareModel = "J720AP",
    .marketingName = "iPad Pro 13-inch (M4)",
    .systemVersion = "18.1",
    .buildVersion = "22B83",
    .kernelVersion = "Darwin Kernel Version 24.1.0: Thu Oct 10 21:02:45 PDT 2024; root:xnu-11215.41.3~2/RELEASE_ARM64_T8132",
    .kernelRelease = "24.1.0",
    .physicalMemory = 17179869184ULL, // 16GB
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
    .physicalMemory = 8589934592ULL, // 8GB
    .cpuCoreCount = 10,
    .performanceCores = 4,
    .efficiencyCores = 6,
    .screenScale = 2.0,
    .screenWidth = 834,
    .screenHeight = 1210,
    .chipName = "Apple M4",
    .gpuName = "Apple M4 GPU"
};

#pragma mark - Device Profiles - Legacy iPad Pro M2

const LCDeviceProfile kDeviceProfileiPadPro12_9_6th = {
    .modelIdentifier = "iPad14,5",
    .hardwareModel = "J620AP",
    .marketingName = "iPad Pro 12.9-inch (6th generation)",
    .systemVersion = "17.6.1",
    .buildVersion = "21G93",
    .kernelVersion = "Darwin Kernel Version 23.6.0: Mon Jul 22 20:46:27 PDT 2024; root:xnu-10063.141.2~1/RELEASE_ARM64_T8112",
    .kernelRelease = "23.6.0",
    .physicalMemory = 17179869184ULL, // 16GB
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

// Custom overrides (if user wants to set specific values)
static NSString *g_customDeviceModel = nil;
static NSString *g_customSystemVersion = nil;
static NSString *g_customBuildVersion = nil;
static uint64_t g_customPhysicalMemory = 0;

// Identifier spoofing
static NSString *g_spoofedVendorID = nil;
static NSString *g_spoofedAdvertisingID = nil;

// Fingerprint spoofing state
static float g_spoofedBatteryLevel = -1.0f;  // -1 means use real value
static NSInteger g_spoofedBatteryState = -1; // -1 means use real value
static NSTimeInterval g_uptimeOffset = 0;     // Offset to add to uptime
static uint64_t g_machTimeOffset = 0;         // Offset for mach_absolute_time
static float g_spoofedBrightness = -1.0f;     // -1 means use real value
static uint64_t g_spoofedDiskFreeSpace = 0;   // 0 means use real value
static uint64_t g_spoofedDiskTotalSpace = 0;  // 0 means use real value
static NSInteger g_spoofedThermalState = -1;  // -1 means use real value
static BOOL g_spoofLowPowerMode = NO;
static BOOL g_lowPowerModeValue = NO;
static struct timeval g_spoofedBootTime = {0, 0}; // Spoofed boot time
static BOOL g_bootTimeSpoofingEnabled = NO;

#pragma mark - Original Function Pointers

static int (*orig_uname)(struct utsname *name) = NULL;
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;

// UIDevice method IMPs
static NSString* (*orig_UIDevice_model)(id self, SEL _cmd) = NULL;
static NSString* (*orig_UIDevice_systemVersion)(id self, SEL _cmd) = NULL;
static NSString* (*orig_UIDevice_systemName)(id self, SEL _cmd) = NULL;
static NSString* (*orig_UIDevice_name)(id self, SEL _cmd) = NULL;
static NSUUID* (*orig_UIDevice_identifierForVendor)(id self, SEL _cmd) = NULL;

// NSProcessInfo method IMPs
static unsigned long long (*orig_NSProcessInfo_physicalMemory)(id self, SEL _cmd) = NULL;
static NSUInteger (*orig_NSProcessInfo_processorCount)(id self, SEL _cmd) = NULL;
static NSUInteger (*orig_NSProcessInfo_activeProcessorCount)(id self, SEL _cmd) = NULL;
static NSOperatingSystemVersion (*orig_NSProcessInfo_operatingSystemVersion)(id self, SEL _cmd) = NULL;
static NSString* (*orig_NSProcessInfo_operatingSystemVersionString)(id self, SEL _cmd) = NULL;

// UIScreen method IMPs
static CGFloat (*orig_UIScreen_scale)(id self, SEL _cmd) = NULL;
static CGFloat (*orig_UIScreen_nativeScale)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIScreen_bounds)(id self, SEL _cmd) = NULL;
static CGRect (*orig_UIScreen_nativeBounds)(id self, SEL _cmd) = NULL;

// ASIdentifierManager method IMPs
static NSUUID* (*orig_ASIdentifierManager_advertisingIdentifier)(id self, SEL _cmd) = NULL;

// UIDevice battery method IMPs
static float (*orig_UIDevice_batteryLevel)(id self, SEL _cmd) = NULL;
static NSInteger (*orig_UIDevice_batteryState)(id self, SEL _cmd) = NULL;
static BOOL (*orig_UIDevice_isBatteryMonitoringEnabled)(id self, SEL _cmd) = NULL;

// UIScreen brightness method IMPs
static CGFloat (*orig_UIScreen_brightness)(id self, SEL _cmd) = NULL;

// NSProcessInfo thermal/power method IMPs
static NSInteger (*orig_NSProcessInfo_thermalState)(id self, SEL _cmd) = NULL;
static BOOL (*orig_NSProcessInfo_isLowPowerModeEnabled)(id self, SEL _cmd) = NULL;
static NSTimeInterval (*orig_NSProcessInfo_systemUptime)(id self, SEL _cmd) = NULL;

// Uptime related function pointers
static uint64_t (*orig_mach_absolute_time)(void) = NULL;
static int (*orig_gettimeofday)(struct timeval *tv, void *tz) = NULL;
static int (*orig_clock_gettime)(clockid_t clk_id, struct timespec *tp) = NULL;

// Memory info function pointers
static kern_return_t (*orig_host_statistics)(host_t host, host_flavor_t flavor, host_info_t host_info_out, mach_msg_type_number_t *host_info_outCnt) = NULL;
static kern_return_t (*orig_host_statistics64)(host_t host, host_flavor_t flavor, host_info64_t host_info_out, mach_msg_type_number_t *host_info_outCnt) = NULL;

#pragma mark - Helper Functions

static const char* getSpoofedMachineModel(void) {
    if (g_customDeviceModel) {
        return g_customDeviceModel.UTF8String;
    }
    if (g_currentProfile) {
        return g_currentProfile->modelIdentifier;
    }
    return NULL;
}

static const char* getSpoofedHardwareModel(void) {
    if (g_currentProfile) {
        return g_currentProfile->hardwareModel;
    }
    return NULL;
}

static const char* getSpoofedSystemVersion(void) {
    if (g_customSystemVersion) {
        return g_customSystemVersion.UTF8String;
    }
    if (g_currentProfile) {
        return g_currentProfile->systemVersion;
    }
    return NULL;
}

static const char* getSpoofedBuildVersion(void) {
    if (g_customBuildVersion) {
        return g_customBuildVersion.UTF8String;
    }
    if (g_currentProfile) {
        return g_currentProfile->buildVersion;
    }
    return NULL;
}

static const char* getSpoofedKernelVersion(void) {
    if (g_currentProfile) {
        return g_currentProfile->kernelVersion;
    }
    return NULL;
}

static const char* getSpoofedKernelRelease(void) {
    if (g_currentProfile) {
        return g_currentProfile->kernelRelease;
    }
    return "23.6.0"; // Default to iOS 17.6 kernel release
}

static uint64_t getSpoofedPhysicalMemory(void) {
    if (g_customPhysicalMemory > 0) {
        return g_customPhysicalMemory;
    }
    if (g_currentProfile) {
        return g_currentProfile->physicalMemory;
    }
    return 0;
}

static uint32_t getSpoofedCPUCoreCount(void) {
    if (g_currentProfile) {
        return g_currentProfile->cpuCoreCount;
    }
    return 0;
}

static uint32_t getSpoofedPerformanceCores(void) {
    if (g_currentProfile) {
        return g_currentProfile->performanceCores;
    }
    return 0;
}

static uint32_t getSpoofedEfficiencyCores(void) {
    if (g_currentProfile) {
        return g_currentProfile->efficiencyCores;
    }
    return 0;
}

static CGFloat getSpoofedScreenScale(void) {
    if (g_currentProfile) {
        return g_currentProfile->screenScale;
    }
    return 3.0; // Default to 3x for modern iPhones
}

static CGSize getSpoofedScreenSize(void) {
    if (g_currentProfile) {
        return CGSizeMake(g_currentProfile->screenWidth, g_currentProfile->screenHeight);
    }
    return CGSizeZero;
}

static const char* getSpoofedChipName(void) {
    if (g_currentProfile) {
        return g_currentProfile->chipName;
    }
    return NULL;
}

static const char* getSpoofedGPUName(void) {
    if (g_currentProfile) {
        return g_currentProfile->gpuName;
    }
    return NULL;
}

#pragma mark - uname Hook

static int hook_uname(struct utsname *name) {
    // Safety check - if original function not set, call system directly
    if (!orig_uname) {
        orig_uname = (int (*)(struct utsname *))dlsym(RTLD_DEFAULT, "uname");
        if (!orig_uname) return -1;
    }
    
    int result = orig_uname(name);
    
    if (result != 0 || !g_deviceSpoofingEnabled || !name) {
        return result;
    }
    
    // Spoof machine (device model identifier)
    const char *machineModel = getSpoofedMachineModel();
    if (machineModel) {
        strlcpy(name->machine, machineModel, sizeof(name->machine));
    }
    
    // Spoof kernel version
    const char *kernelVersion = getSpoofedKernelVersion();
    if (kernelVersion) {
        // version field contains full kernel string
        strlcpy(name->version, kernelVersion, sizeof(name->version));
    }
    
    // Spoof kernel release
    const char *kernelRelease = getSpoofedKernelRelease();
    if (kernelRelease) {
        // release field contains just the version number
        strlcpy(name->release, kernelRelease, sizeof(name->release));
    }
    
    return result;
}

#pragma mark - sysctlbyname Hook

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    // Safety check - if original function not set, call system directly
    if (!orig_sysctlbyname) {
        orig_sysctlbyname = (int (*)(const char *, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctlbyname");
        if (!orig_sysctlbyname) return -1;
    }
    
    int result = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    
    if (result != 0 || !g_deviceSpoofingEnabled || !name) {
        return result;
    }
    
    // Handle size query case (oldp is NULL, oldlenp is not)
    // Apps call sysctlbyname with NULL oldp first to get required buffer size
    if (!oldp && oldlenp) {
        // Return spoofed size for known keys
        if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0 || strcmp(name, "hw.product") == 0) {
            const char *spoofedValue = (strcmp(name, "hw.model") == 0) ? getSpoofedHardwareModel() : getSpoofedMachineModel();
            if (spoofedValue) {
                *oldlenp = strlen(spoofedValue) + 1;
                return 0;
            }
        }
        return result;
    }
    
    // Normal case - oldp and oldlenp both provided
    if (!oldp || !oldlenp || *oldlenp == 0) {
        return result;
    }
    
    // hw.machine - Device model identifier (e.g., "iPhone17,2")
    if (strcmp(name, "hw.machine") == 0) {
        const char *machineModel = getSpoofedMachineModel();
        if (machineModel) {
            size_t len = strlen(machineModel) + 1;
            if (*oldlenp >= len) {
                memset(oldp, 0, *oldlenp);
                strlcpy(oldp, machineModel, *oldlenp);
                *oldlenp = len;
            }
        }
    }
    // hw.model - Hardware model (e.g., "D94AP")
    else if (strcmp(name, "hw.model") == 0) {
        const char *hwModel = getSpoofedHardwareModel();
        if (hwModel) {
            size_t len = strlen(hwModel) + 1;
            if (*oldlenp >= len) {
                memset(oldp, 0, *oldlenp);
                strlcpy(oldp, hwModel, *oldlenp);
                *oldlenp = len;
            }
        }
    }
    // hw.product - Same as hw.machine for iOS
    else if (strcmp(name, "hw.product") == 0) {
        const char *machineModel = getSpoofedMachineModel();
        if (machineModel) {
            size_t len = strlen(machineModel) + 1;
            if (*oldlenp >= len) {
                memset(oldp, 0, *oldlenp);
                strlcpy(oldp, machineModel, *oldlenp);
                *oldlenp = len;
            }
        }
    }
    // kern.osversion - Build version (e.g., "22B83" for iOS 18.1)
    else if (strcmp(name, "kern.osversion") == 0) {
        const char *buildVersion = getSpoofedBuildVersion();
        if (buildVersion) {
            size_t len = strlen(buildVersion) + 1;
            if (*oldlenp >= len) {
                memset(oldp, 0, *oldlenp);
                strlcpy(oldp, buildVersion, *oldlenp);
                *oldlenp = len;
            }
        }
    }
    // kern.osrelease - Kernel release version (e.g., "24.1.0" for iOS 18.1)
    else if (strcmp(name, "kern.osrelease") == 0) {
        const char *release = getSpoofedKernelRelease();
        if (release) {
            size_t len = strlen(release) + 1;
            if (*oldlenp >= len) {
                memset(oldp, 0, *oldlenp);
                strlcpy(oldp, release, *oldlenp);
                *oldlenp = len;
            }
        }
    }
    // kern.version - Full kernel version string
    else if (strcmp(name, "kern.version") == 0) {
        const char *kernelVersion = getSpoofedKernelVersion();
        if (kernelVersion) {
            size_t len = strlen(kernelVersion) + 1;
            if (*oldlenp >= len) {
                memset(oldp, 0, *oldlenp);
                strlcpy(oldp, kernelVersion, *oldlenp);
                *oldlenp = len;
            }
        }
    }
    // hw.memsize - Physical memory (64-bit)
    else if (strcmp(name, "hw.memsize") == 0) {
        uint64_t spoofedMemory = getSpoofedPhysicalMemory();
        if (spoofedMemory > 0 && *oldlenp >= sizeof(uint64_t)) {
            *(uint64_t *)oldp = spoofedMemory;
        }
    }
    // hw.physmem - Physical memory (32-bit)
    else if (strcmp(name, "hw.physmem") == 0) {
        uint64_t spoofedMemory = getSpoofedPhysicalMemory();
        if (spoofedMemory > 0 && *oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = (uint32_t)MIN(spoofedMemory, UINT32_MAX);
        }
    }
    // hw.ncpu / hw.logicalcpu / hw.physicalcpu - CPU core count
    else if (strcmp(name, "hw.ncpu") == 0 || 
             strcmp(name, "hw.logicalcpu") == 0 ||
             strcmp(name, "hw.physicalcpu") == 0 ||
             strcmp(name, "hw.logicalcpu_max") == 0 ||
             strcmp(name, "hw.physicalcpu_max") == 0) {
        uint32_t spoofedCores = getSpoofedCPUCoreCount();
        if (spoofedCores > 0 && *oldlenp >= sizeof(int32_t)) {
            *(int32_t *)oldp = (int32_t)spoofedCores;
        }
    }
    // hw.activecpu - Active CPU count
    else if (strcmp(name, "hw.activecpu") == 0) {
        uint32_t spoofedCores = getSpoofedCPUCoreCount();
        if (spoofedCores > 0 && *oldlenp >= sizeof(int32_t)) {
            *(int32_t *)oldp = (int32_t)spoofedCores;
        }
    }
    // hw.perflevel0.physicalcpu - Performance core count
    else if (strcmp(name, "hw.perflevel0.physicalcpu") == 0 ||
             strcmp(name, "hw.perflevel0.logicalcpu") == 0) {
        uint32_t perfCores = getSpoofedPerformanceCores();
        if (perfCores > 0 && *oldlenp >= sizeof(int32_t)) {
            *(int32_t *)oldp = (int32_t)perfCores;
        }
    }
    // hw.perflevel1.physicalcpu - Efficiency core count
    else if (strcmp(name, "hw.perflevel1.physicalcpu") == 0 ||
             strcmp(name, "hw.perflevel1.logicalcpu") == 0) {
        uint32_t effCores = getSpoofedEfficiencyCores();
        if (effCores > 0 && *oldlenp >= sizeof(int32_t)) {
            *(int32_t *)oldp = (int32_t)effCores;
        }
    }
    // hw.nperflevels - Number of performance levels (always 2 for P+E cores)
    else if (strcmp(name, "hw.nperflevels") == 0) {
        if (*oldlenp >= sizeof(int32_t)) {
            *(int32_t *)oldp = 2;
        }
    }
    // machdep.cpu.brand_string - CPU brand string (chip name)
    else if (strcmp(name, "machdep.cpu.brand_string") == 0) {
        const char *chipName = getSpoofedChipName();
        if (chipName) {
            size_t len = strlen(chipName) + 1;
            if (*oldlenp >= len) {
                memset(oldp, 0, *oldlenp);
                strlcpy(oldp, chipName, *oldlenp);
                *oldlenp = len;
            }
        }
    }
    // kern.boottime - System boot time (fingerprinting vector!)
    else if (strcmp(name, "kern.boottime") == 0) {
        if (*oldlenp >= sizeof(struct timeval)) {
            struct timeval *boottime = (struct timeval *)oldp;
            
            // Generate spoofed boot time if not set
            if (!g_bootTimeSpoofingEnabled) {
                g_bootTimeSpoofingEnabled = YES;
                // Set boot time to be 1-7 days ago with random offset
                struct timeval now;
                gettimeofday(&now, NULL);
                time_t offset = (arc4random_uniform(6) + 1) * 86400; // 1-7 days
                offset += arc4random_uniform(86400); // Add random hours/minutes/seconds
                g_spoofedBootTime.tv_sec = now.tv_sec - offset;
                g_spoofedBootTime.tv_usec = arc4random_uniform(1000000);
            }
            
            boottime->tv_sec = g_spoofedBootTime.tv_sec;
            boottime->tv_usec = g_spoofedBootTime.tv_usec;
        }
    }
    
    return result;
}

#pragma mark - sysctl Hook

static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    // Safety check - if original function not set, call system directly
    if (!orig_sysctl) {
        orig_sysctl = (int (*)(int *, u_int, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctl");
        if (!orig_sysctl) return -1;
    }
    
    int result = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    
    if (result != 0 || !g_deviceSpoofingEnabled || namelen < 2 || !oldp || !oldlenp || *oldlenp == 0) {
        return result;
    }
    
    // CTL_HW (6)
    if (name[0] == CTL_HW) {
        switch (name[1]) {
            case HW_MACHINE: { // hw.machine
                const char *machineModel = getSpoofedMachineModel();
                if (machineModel) {
                    size_t len = strlen(machineModel) + 1;
                    if (*oldlenp >= len) {
                        memset(oldp, 0, *oldlenp);
                        strlcpy(oldp, machineModel, *oldlenp);
                        *oldlenp = len;
                    }
                }
                break;
            }
            case HW_MODEL: { // hw.model
                const char *hwModel = getSpoofedHardwareModel();
                if (hwModel) {
                    size_t len = strlen(hwModel) + 1;
                    if (*oldlenp >= len) {
                        memset(oldp, 0, *oldlenp);
                        strlcpy(oldp, hwModel, *oldlenp);
                        *oldlenp = len;
                    }
                }
                break;
            }
            case HW_MEMSIZE: { // hw.memsize
                uint64_t spoofedMemory = getSpoofedPhysicalMemory();
                if (spoofedMemory > 0 && *oldlenp >= sizeof(uint64_t)) {
                    *(uint64_t *)oldp = spoofedMemory;
                }
                break;
            }
            case HW_NCPU: { // hw.ncpu
                uint32_t spoofedCores = getSpoofedCPUCoreCount();
                if (spoofedCores > 0 && *oldlenp >= sizeof(int32_t)) {
                    *(int32_t *)oldp = (int32_t)spoofedCores;
                }
                break;
            }
            case HW_PHYSMEM: { // hw.physmem (32-bit)
                uint64_t spoofedMemory = getSpoofedPhysicalMemory();
                if (spoofedMemory > 0 && *oldlenp >= sizeof(uint32_t)) {
                    *(uint32_t *)oldp = (uint32_t)MIN(spoofedMemory, UINT32_MAX);
                }
                break;
            }
        }
    }
    // CTL_KERN (1)
    else if (name[0] == CTL_KERN) {
        if (name[1] == KERN_OSVERSION) { // kern.osversion
            const char *buildVersion = getSpoofedBuildVersion();
            if (buildVersion) {
                size_t len = strlen(buildVersion) + 1;
                if (*oldlenp >= len) {
                    memset(oldp, 0, *oldlenp);
                    strlcpy(oldp, buildVersion, *oldlenp);
                    *oldlenp = len;
                }
            }
        }
        else if (name[1] == KERN_OSRELEASE) { // kern.osrelease
            const char *release = getSpoofedKernelRelease();
            if (release) {
                size_t len = strlen(release) + 1;
                if (*oldlenp >= len) {
                    memset(oldp, 0, *oldlenp);
                    strlcpy(oldp, release, *oldlenp);
                    *oldlenp = len;
                }
            }
        }
        else if (name[1] == KERN_VERSION) { // kern.version
            const char *kernelVersion = getSpoofedKernelVersion();
            if (kernelVersion) {
                size_t len = strlen(kernelVersion) + 1;
                if (*oldlenp >= len) {
                    memset(oldp, 0, *oldlenp);
                    strlcpy(oldp, kernelVersion, *oldlenp);
                    *oldlenp = len;
                }
            }
        }
        else if (name[1] == KERN_BOOTTIME) { // kern.boottime - uptime fingerprinting!
            if (*oldlenp >= sizeof(struct timeval)) {
                struct timeval *boottime = (struct timeval *)oldp;
                
                if (!g_bootTimeSpoofingEnabled) {
                    g_bootTimeSpoofingEnabled = YES;
                    struct timeval now;
                    gettimeofday(&now, NULL);
                    time_t offset = (arc4random_uniform(6) + 1) * 86400;
                    offset += arc4random_uniform(86400);
                    g_spoofedBootTime.tv_sec = now.tv_sec - offset;
                    g_spoofedBootTime.tv_usec = arc4random_uniform(1000000);
                }
                
                boottime->tv_sec = g_spoofedBootTime.tv_sec;
                boottime->tv_usec = g_spoofedBootTime.tv_usec;
            }
        }
    }
    
    return result;
}

#pragma mark - UIDevice Hooks

static NSString* hook_UIDevice_model(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled || !g_currentProfile) {
        if (orig_UIDevice_model) return orig_UIDevice_model(self, _cmd);
        return @"iPhone";
    }
    
    // Return marketing name (e.g., "iPhone" or "iPad")
    NSString *model = @(g_currentProfile->marketingName);
    if ([model hasPrefix:@"iPhone"]) {
        return @"iPhone";
    } else if ([model hasPrefix:@"iPad"]) {
        return @"iPad";
    }
    if (orig_UIDevice_model) return orig_UIDevice_model(self, _cmd);
    return @"iPhone";
}

static NSString* hook_UIDevice_systemVersion(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_UIDevice_systemVersion) return orig_UIDevice_systemVersion(self, _cmd);
        return @"17.0";
    }
    
    const char *version = getSpoofedSystemVersion();
    if (version) {
        return @(version);
    }
    if (orig_UIDevice_systemVersion) return orig_UIDevice_systemVersion(self, _cmd);
    return @"17.0";
}

static NSString* hook_UIDevice_systemName(id self, SEL _cmd) {
    // Always return the system name based on device type
    if (!g_deviceSpoofingEnabled || !g_currentProfile) {
        if (orig_UIDevice_systemName) return orig_UIDevice_systemName(self, _cmd);
        return @"iOS";
    }
    
    NSString *model = @(g_currentProfile->modelIdentifier);
    if ([model hasPrefix:@"iPad"]) {
        return @"iPadOS";
    }
    return @"iOS";
}

static NSUUID* hook_UIDevice_identifierForVendor(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_UIDevice_identifierForVendor) return orig_UIDevice_identifierForVendor(self, _cmd);
        return [[NSUUID alloc] init];
    }
    
    // Return spoofed vendor ID if set
    if (g_spoofedVendorID) {
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:g_spoofedVendorID];
        if (uuid) return uuid;
    }
    
    // Generate a consistent spoofed UUID based on the app bundle ID
    // This ensures the same app always gets the same vendor ID
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.unknown.app";
    const char *cstr = [bundleID UTF8String];
    unsigned char hash[16];
    CC_MD5(cstr, (CC_LONG)strlen(cstr), hash);
    
    // Format as UUID (8-4-4-4-12)
    NSString *uuidString = [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                           hash[0], hash[1], hash[2], hash[3],
                           hash[4], hash[5],
                           hash[6], hash[7],
                           hash[8], hash[9],
                           hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]];
    
    return [[NSUUID alloc] initWithUUIDString:uuidString];
}

#pragma mark - NSProcessInfo Hooks

static unsigned long long hook_NSProcessInfo_physicalMemory(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_NSProcessInfo_physicalMemory) return orig_NSProcessInfo_physicalMemory(self, _cmd);
        return 8589934592ULL; // 8GB default
    }
    
    uint64_t spoofedMemory = getSpoofedPhysicalMemory();
    if (spoofedMemory > 0) {
        return spoofedMemory;
    }
    if (orig_NSProcessInfo_physicalMemory) return orig_NSProcessInfo_physicalMemory(self, _cmd);
    return 8589934592ULL;
}

static NSUInteger hook_NSProcessInfo_processorCount(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_NSProcessInfo_processorCount) return orig_NSProcessInfo_processorCount(self, _cmd);
        return 6;
    }
    
    uint32_t spoofedCores = getSpoofedCPUCoreCount();
    if (spoofedCores > 0) {
        return spoofedCores;
    }
    if (orig_NSProcessInfo_processorCount) return orig_NSProcessInfo_processorCount(self, _cmd);
    return 6;
}

static NSUInteger hook_NSProcessInfo_activeProcessorCount(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_NSProcessInfo_activeProcessorCount) return orig_NSProcessInfo_activeProcessorCount(self, _cmd);
        return 6;
    }
    
    uint32_t spoofedCores = getSpoofedCPUCoreCount();
    if (spoofedCores > 0) {
        return spoofedCores;
    }
    if (orig_NSProcessInfo_activeProcessorCount) return orig_NSProcessInfo_activeProcessorCount(self, _cmd);
    return 6;
}

static NSOperatingSystemVersion hook_NSProcessInfo_operatingSystemVersion(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_NSProcessInfo_operatingSystemVersion) return orig_NSProcessInfo_operatingSystemVersion(self, _cmd);
        return (NSOperatingSystemVersion){17, 0, 0};
    }
    
    const char *version = getSpoofedSystemVersion();
    if (version) {
        NSOperatingSystemVersion osVersion = {0, 0, 0};
        NSArray *components = [@(version) componentsSeparatedByString:@"."];
        if (components.count >= 1) {
            osVersion.majorVersion = [components[0] integerValue];
        }
        if (components.count >= 2) {
            osVersion.minorVersion = [components[1] integerValue];
        }
        if (components.count >= 3) {
            osVersion.patchVersion = [components[2] integerValue];
        }
        return osVersion;
    }
    if (orig_NSProcessInfo_operatingSystemVersion) return orig_NSProcessInfo_operatingSystemVersion(self, _cmd);
    return (NSOperatingSystemVersion){17, 0, 0};
}

static NSString* hook_NSProcessInfo_operatingSystemVersionString(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_NSProcessInfo_operatingSystemVersionString) return orig_NSProcessInfo_operatingSystemVersionString(self, _cmd);
        return @"Version 17.0 (Build 21A5248v)";
    }
    
    const char *version = getSpoofedSystemVersion();
    const char *build = getSpoofedBuildVersion();
    if (version && build) {
        return [NSString stringWithFormat:@"Version %s (Build %s)", version, build];
    }
    if (orig_NSProcessInfo_operatingSystemVersionString) return orig_NSProcessInfo_operatingSystemVersionString(self, _cmd);
    return @"Version 17.0 (Build 21A5248v)";
}

#pragma mark - UIScreen Hooks

static CGFloat hook_UIScreen_scale(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_UIScreen_scale) return orig_UIScreen_scale(self, _cmd);
        return 3.0;
    }
    
    CGFloat scale = getSpoofedScreenScale();
    if (scale > 0) {
        return scale;
    }
    if (orig_UIScreen_scale) return orig_UIScreen_scale(self, _cmd);
    return 3.0;
}

static CGFloat hook_UIScreen_nativeScale(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_UIScreen_nativeScale) return orig_UIScreen_nativeScale(self, _cmd);
        return 3.0;
    }
    
    CGFloat scale = getSpoofedScreenScale();
    if (scale > 0) {
        return scale;
    }
    if (orig_UIScreen_nativeScale) return orig_UIScreen_nativeScale(self, _cmd);
    return 3.0;
}

static CGRect hook_UIScreen_bounds(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_UIScreen_bounds) return orig_UIScreen_bounds(self, _cmd);
        return CGRectMake(0, 0, 393, 852);
    }
    
    CGSize size = getSpoofedScreenSize();
    if (size.width > 0 && size.height > 0) {
        return CGRectMake(0, 0, size.width, size.height);
    }
    if (orig_UIScreen_bounds) return orig_UIScreen_bounds(self, _cmd);
    return CGRectMake(0, 0, 393, 852);
}

static CGRect hook_UIScreen_nativeBounds(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_UIScreen_nativeBounds) return orig_UIScreen_nativeBounds(self, _cmd);
        return CGRectMake(0, 0, 1179, 2556);
    }
    
    CGSize size = getSpoofedScreenSize();
    CGFloat scale = getSpoofedScreenScale();
    if (size.width > 0 && size.height > 0 && scale > 0) {
        return CGRectMake(0, 0, size.width * scale, size.height * scale);
    }
    if (orig_UIScreen_nativeBounds) return orig_UIScreen_nativeBounds(self, _cmd);
    return CGRectMake(0, 0, 1179, 2556);
}

#pragma mark - ASIdentifierManager Hooks

static NSUUID* hook_ASIdentifierManager_advertisingIdentifier(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_ASIdentifierManager_advertisingIdentifier) return orig_ASIdentifierManager_advertisingIdentifier(self, _cmd);
        return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
    }
    
    // Return spoofed advertising ID if set
    if (g_spoofedAdvertisingID) {
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:g_spoofedAdvertisingID];
        if (uuid) return uuid;
    }
    
    // Return zeroed UUID (same as when "Limit Ad Tracking" is enabled)
    // This is the safest approach for privacy
    return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
}

#pragma mark - Battery Hooks

static float hook_UIDevice_batteryLevel(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled || g_spoofedBatteryLevel < 0) {
        if (orig_UIDevice_batteryLevel) return orig_UIDevice_batteryLevel(self, _cmd);
        return 1.0f;
    }
    return g_spoofedBatteryLevel;
}

static NSInteger hook_UIDevice_batteryState(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled || g_spoofedBatteryState < 0) {
        if (orig_UIDevice_batteryState) return orig_UIDevice_batteryState(self, _cmd);
        return 2; // UIDeviceBatteryStateUnplugged
    }
    return g_spoofedBatteryState;
}

static BOOL hook_UIDevice_isBatteryMonitoringEnabled(id self, SEL _cmd) {
    // Always return YES so battery queries work
    return YES;
}

#pragma mark - Brightness Hooks

static CGFloat hook_UIScreen_brightness(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled || g_spoofedBrightness < 0) {
        if (orig_UIScreen_brightness) return orig_UIScreen_brightness(self, _cmd);
        return 0.5f;
    }
    return (CGFloat)g_spoofedBrightness;
}

#pragma mark - Thermal State & Low Power Mode Hooks

static NSInteger hook_NSProcessInfo_thermalState(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled || g_spoofedThermalState < 0) {
        if (orig_NSProcessInfo_thermalState) return orig_NSProcessInfo_thermalState(self, _cmd);
        return 0; // NSProcessInfoThermalStateNominal
    }
    return g_spoofedThermalState;
}

static BOOL hook_NSProcessInfo_isLowPowerModeEnabled(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled || !g_spoofLowPowerMode) {
        if (orig_NSProcessInfo_isLowPowerModeEnabled) return orig_NSProcessInfo_isLowPowerModeEnabled(self, _cmd);
        return NO;
    }
    return g_lowPowerModeValue;
}

#pragma mark - Uptime Hooks

static NSTimeInterval hook_NSProcessInfo_systemUptime(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_NSProcessInfo_systemUptime) return orig_NSProcessInfo_systemUptime(self, _cmd);
        return 86400.0; // Default 1 day
    }
    
    NSTimeInterval realUptime = 0;
    if (orig_NSProcessInfo_systemUptime) {
        realUptime = orig_NSProcessInfo_systemUptime(self, _cmd);
    }
    
    // Add random offset to uptime (between 1-7 days)
    if (g_uptimeOffset == 0) {
        g_uptimeOffset = (arc4random_uniform(6) + 1) * 86400.0; // 1-7 days in seconds
    }
    
    return realUptime + g_uptimeOffset;
}

static uint64_t hook_mach_absolute_time(void) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_mach_absolute_time) return orig_mach_absolute_time();
        return 0;
    }
    
    uint64_t realTime = 0;
    if (orig_mach_absolute_time) {
        realTime = orig_mach_absolute_time();
    }
    
    // Add offset to mach_absolute_time to mask real uptime
    if (g_machTimeOffset == 0) {
        // Convert uptime offset to mach time units
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        // Add random offset equivalent to 1-7 days
        uint64_t offsetNanos = (uint64_t)((arc4random_uniform(6) + 1) * 86400.0 * 1e9);
        g_machTimeOffset = offsetNanos * timebase.denom / timebase.numer;
    }
    
    return realTime + g_machTimeOffset;
}

static int hook_clock_gettime(clockid_t clk_id, struct timespec *tp) {
    if (!orig_clock_gettime) {
        orig_clock_gettime = (int (*)(clockid_t, struct timespec *))dlsym(RTLD_DEFAULT, "clock_gettime");
        if (!orig_clock_gettime) return -1;
    }
    
    int result = orig_clock_gettime(clk_id, tp);
    
    if (result != 0 || !g_deviceSpoofingEnabled || !tp) {
        return result;
    }
    
    // Spoof CLOCK_MONOTONIC and CLOCK_MONOTONIC_RAW (uptime-based clocks)
    if (clk_id == CLOCK_MONOTONIC || clk_id == CLOCK_MONOTONIC_RAW) {
        if (g_uptimeOffset == 0) {
            g_uptimeOffset = (arc4random_uniform(6) + 1) * 86400.0;
        }
        tp->tv_sec += (time_t)g_uptimeOffset;
    }
    // Spoof CLOCK_UPTIME_RAW
    else if (clk_id == CLOCK_UPTIME_RAW) {
        if (g_uptimeOffset == 0) {
            g_uptimeOffset = (arc4random_uniform(6) + 1) * 86400.0;
        }
        tp->tv_sec += (time_t)g_uptimeOffset;
    }
    
    return result;
}

#pragma mark - Memory Statistics Hooks

static kern_return_t hook_host_statistics(host_t host, host_flavor_t flavor, host_info_t host_info_out, mach_msg_type_number_t *host_info_outCnt) {
    if (!orig_host_statistics) {
        orig_host_statistics = (kern_return_t (*)(host_t, host_flavor_t, host_info_t, mach_msg_type_number_t *))dlsym(RTLD_DEFAULT, "host_statistics");
        if (!orig_host_statistics) return KERN_FAILURE;
    }
    
    kern_return_t result = orig_host_statistics(host, flavor, host_info_out, host_info_outCnt);
    
    if (result != KERN_SUCCESS || !g_deviceSpoofingEnabled || !host_info_out) {
        return result;
    }
    
    // Spoof VM statistics to hide real memory usage patterns
    if (flavor == HOST_VM_INFO) {
        vm_statistics_data_t *vm_stat = (vm_statistics_data_t *)host_info_out;
        
        // Add random noise to memory stats (±5%)
        uint32_t noise = arc4random_uniform(10); // 0-9
        float factor = 0.95f + (noise * 0.01f);  // 0.95-1.04
        
        vm_stat->free_count = (natural_t)(vm_stat->free_count * factor);
        vm_stat->active_count = (natural_t)(vm_stat->active_count * factor);
        vm_stat->inactive_count = (natural_t)(vm_stat->inactive_count * factor);
        vm_stat->wire_count = (natural_t)(vm_stat->wire_count * factor);
    }
    
    return result;
}

static kern_return_t hook_host_statistics64(host_t host, host_flavor_t flavor, host_info64_t host_info_out, mach_msg_type_number_t *host_info_outCnt) {
    if (!orig_host_statistics64) {
        orig_host_statistics64 = (kern_return_t (*)(host_t, host_flavor_t, host_info64_t, mach_msg_type_number_t *))dlsym(RTLD_DEFAULT, "host_statistics64");
        if (!orig_host_statistics64) return KERN_FAILURE;
    }
    
    kern_return_t result = orig_host_statistics64(host, flavor, host_info_out, host_info_outCnt);
    
    if (result != KERN_SUCCESS || !g_deviceSpoofingEnabled || !host_info_out) {
        return result;
    }
    
    // Spoof VM statistics64 to hide real memory usage patterns
    if (flavor == HOST_VM_INFO64) {
        vm_statistics64_data_t *vm_stat = (vm_statistics64_data_t *)host_info_out;
        
        // Add random noise to memory stats (±5%)
        uint32_t noise = arc4random_uniform(10);
        float factor = 0.95f + (noise * 0.01f);
        
        vm_stat->free_count = (natural_t)(vm_stat->free_count * factor);
        vm_stat->active_count = (natural_t)(vm_stat->active_count * factor);
        vm_stat->inactive_count = (natural_t)(vm_stat->inactive_count * factor);
        vm_stat->wire_count = (natural_t)(vm_stat->wire_count * factor);
    }
    
    return result;
}

#pragma mark - Public API

void LCSetDeviceSpoofingEnabled(BOOL enabled) {
    g_deviceSpoofingEnabled = enabled;
    NSLog(@"[LC] Device spoofing %@", enabled ? @"enabled" : @"disabled");
}

BOOL LCIsDeviceSpoofingEnabled(void) {
    return g_deviceSpoofingEnabled;
}

void LCSetDeviceProfile(NSString *profileName) {
    g_currentProfileName = [profileName copy];
    
    static NSDictionary *profileMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        profileMap = @{
            // iOS 18.x - iPhone 16 Series
            @"iPhone 16 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone16ProMax],
            @"iPhone 16 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone16Pro],
            @"iPhone 16": [NSValue valueWithPointer:&kDeviceProfileiPhone16],
            // iOS 17.x - iPhone 15 Series
            @"iPhone 15 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone15ProMax],
            @"iPhone 15 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone15Pro],
            // iOS 17.x - iPhone 14 Series
            @"iPhone 14 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone14ProMax],
            @"iPhone 14 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone14Pro],
            // iOS 17.x - iPhone 13 Series
            @"iPhone 13 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone13ProMax],
            @"iPhone 13 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone13Pro],
            // iPad Pro M4 (iPadOS 18.x)
            @"iPad Pro 13-inch (M4)": [NSValue valueWithPointer:&kDeviceProfileiPadPro13_M4],
            @"iPad Pro 11-inch (M4)": [NSValue valueWithPointer:&kDeviceProfileiPadPro11_M4],
            // iPad Pro M2 (iPadOS 17.x)
            @"iPad Pro 12.9 (6th gen)": [NSValue valueWithPointer:&kDeviceProfileiPadPro12_9_6th],
        };
    });
    
    NSValue *profileValue = profileMap[profileName];
    if (profileValue) {
        g_currentProfile = [profileValue pointerValue];
        NSLog(@"[LC] Set device profile: %@ (%s, iOS %s)", profileName, g_currentProfile->modelIdentifier, g_currentProfile->systemVersion);
    } else {
        g_currentProfile = NULL;
        NSLog(@"[LC] Unknown device profile: %@", profileName);
    }
}

NSString *LCGetCurrentDeviceProfile(void) {
    return g_currentProfileName;
}

NSDictionary<NSString *, NSDictionary *> *LCGetAvailableDeviceProfiles(void) {
    return @{
        // iOS 18.x - iPhone 16 Series
        @"iPhone 16 Pro Max": @{
            @"model": @"iPhone17,2",
            @"memory": @"8 GB",
            @"version": @"18.1",
            @"chip": @"A18 Pro"
        },
        @"iPhone 16 Pro": @{
            @"model": @"iPhone17,1",
            @"memory": @"8 GB",
            @"version": @"18.1",
            @"chip": @"A18 Pro"
        },
        @"iPhone 16": @{
            @"model": @"iPhone17,3",
            @"memory": @"8 GB",
            @"version": @"18.1",
            @"chip": @"A18"
        },
        // iOS 17.x - iPhone 15 Series
        @"iPhone 15 Pro Max": @{
            @"model": @"iPhone16,2",
            @"memory": @"8 GB",
            @"version": @"17.6.1",
            @"chip": @"A17 Pro"
        },
        @"iPhone 15 Pro": @{
            @"model": @"iPhone16,1",
            @"memory": @"8 GB",
            @"version": @"17.6.1",
            @"chip": @"A17 Pro"
        },
        // iOS 17.x - iPhone 14 Series
        @"iPhone 14 Pro Max": @{
            @"model": @"iPhone15,3",
            @"memory": @"6 GB",
            @"version": @"17.6.1",
            @"chip": @"A16 Bionic"
        },
        @"iPhone 14 Pro": @{
            @"model": @"iPhone15,2",
            @"memory": @"6 GB",
            @"version": @"17.6.1",
            @"chip": @"A16 Bionic"
        },
        // iOS 17.x - iPhone 13 Series
        @"iPhone 13 Pro Max": @{
            @"model": @"iPhone14,3",
            @"memory": @"6 GB",
            @"version": @"17.6.1",
            @"chip": @"A15 Bionic"
        },
        @"iPhone 13 Pro": @{
            @"model": @"iPhone14,2",
            @"memory": @"6 GB",
            @"version": @"17.6.1",
            @"chip": @"A15 Bionic"
        },
        // iPad Pro M4 (iPadOS 18.x)
        @"iPad Pro 13-inch (M4)": @{
            @"model": @"iPad16,5",
            @"memory": @"16 GB",
            @"version": @"18.1",
            @"chip": @"M4"
        },
        @"iPad Pro 11-inch (M4)": @{
            @"model": @"iPad16,3",
            @"memory": @"8 GB",
            @"version": @"18.1",
            @"chip": @"M4"
        },
        // iPad Pro M2 (iPadOS 17.x)
        @"iPad Pro 12.9 (6th gen)": @{
            @"model": @"iPad14,5",
            @"memory": @"16 GB",
            @"version": @"17.6.1",
            @"chip": @"M2"
        }
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
        @"gpuName": @(g_currentProfile->gpuName)
    };
}

void LCSetSpoofedDeviceModel(NSString *model) {
    g_customDeviceModel = [model copy];
}

void LCSetSpoofedSystemVersion(NSString *version) {
    g_customSystemVersion = [version copy];
}

void LCSetSpoofedBuildVersion(NSString *build) {
    g_customBuildVersion = [build copy];
}

void LCSetSpoofedPhysicalMemory(uint64_t memory) {
    g_customPhysicalMemory = memory;
}

void LCSetSpoofedVendorID(NSString *vendorID) {
    g_spoofedVendorID = [vendorID copy];
    NSLog(@"[LC] Set spoofed vendor ID: %@", vendorID);
}

void LCSetSpoofedAdvertisingID(NSString *advertisingID) {
    g_spoofedAdvertisingID = [advertisingID copy];
    NSLog(@"[LC] Set spoofed advertising ID: %@", advertisingID);
}

NSString *LCGenerateRandomUUID(void) {
    return [[NSUUID UUID] UUIDString];
}

NSString *LCGenerateRandomMACAddress(void) {
    // Generate random MAC address with locally administered bit set
    uint8_t mac[6];
    arc4random_buf(mac, 6);
    
    // Set locally administered bit (bit 1 of first byte)
    mac[0] |= 0x02;
    // Clear multicast bit (bit 0 of first byte)
    mac[0] &= 0xFE;
    
    return [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",
            mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]];
}

#pragma mark - Fingerprint Spoofing API

void LCSetSpoofedBatteryLevel(float level) {
    g_spoofedBatteryLevel = level;
    NSLog(@"[LC] Set spoofed battery level: %.0f%%", level * 100);
}

void LCSetSpoofedBatteryState(NSInteger state) {
    g_spoofedBatteryState = state;
    NSLog(@"[LC] Set spoofed battery state: %ld", (long)state);
}

void LCSetSpoofedBrightness(float brightness) {
    g_spoofedBrightness = brightness;
    NSLog(@"[LC] Set spoofed brightness: %.2f", brightness);
}

void LCSetSpoofedThermalState(NSInteger state) {
    g_spoofedThermalState = state;
    NSLog(@"[LC] Set spoofed thermal state: %ld", (long)state);
}

void LCSetSpoofedLowPowerMode(BOOL enabled, BOOL value) {
    g_spoofLowPowerMode = enabled;
    g_lowPowerModeValue = value;
    NSLog(@"[LC] Set spoofed low power mode: %@ (value: %@)", enabled ? @"enabled" : @"disabled", value ? @"YES" : @"NO");
}

void LCSetUptimeOffset(NSTimeInterval offset) {
    g_uptimeOffset = offset;
    // Also set mach time offset
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    g_machTimeOffset = (uint64_t)(offset * 1e9) * timebase.denom / timebase.numer;
    NSLog(@"[LC] Set uptime offset: %.0f seconds", offset);
}

void LCRandomizeUptime(void) {
    // Randomize uptime to be 1-7 days
    NSTimeInterval offset = (arc4random_uniform(6) + 1) * 86400.0;
    offset += arc4random_uniform(86400); // Add random hours/minutes/seconds
    LCSetUptimeOffset(offset);
}

void LCSetSpoofedDiskSpace(uint64_t freeSpace, uint64_t totalSpace) {
    g_spoofedDiskFreeSpace = freeSpace;
    g_spoofedDiskTotalSpace = totalSpace;
    NSLog(@"[LC] Set spoofed disk space: %llu free / %llu total", freeSpace, totalSpace);
}

void LCRandomizeBattery(void) {
    // Random battery level between 20% and 95%
    float level = 0.20f + (arc4random_uniform(76) / 100.0f);
    g_spoofedBatteryLevel = level;
    // Random state: 1=Unknown, 2=Unplugged, 3=Charging, 4=Full
    g_spoofedBatteryState = 2; // Most common: Unplugged
    NSLog(@"[LC] Randomized battery: %.0f%% (Unplugged)", level * 100);
}

void LCRandomizeBrightness(void) {
    // Random brightness between 30% and 80%
    float brightness = 0.30f + (arc4random_uniform(51) / 100.0f);
    g_spoofedBrightness = brightness;
    NSLog(@"[LC] Randomized brightness: %.0f%%", brightness * 100);
}

void LCInitializeFingerprintProtection(void) {
    // Initialize all fingerprint spoofing with random but realistic values
    LCRandomizeUptime();
    LCRandomizeBattery();
    LCRandomizeBrightness();
    g_spoofedThermalState = 0; // Nominal
    g_spoofLowPowerMode = YES;
    g_lowPowerModeValue = NO;
    NSLog(@"[LC] Fingerprint protection initialized with randomized values");
}

#pragma mark - Initialization

void DeviceSpoofingGuestHooksInit(void) {
    NSLog(@"[LC] Initializing comprehensive device spoofing hooks...");
    
    // Hook C functions using fishhook (symbol rebinding - works without JIT)
    struct rebinding rebindings[] = {
        {"uname", (void *)hook_uname, (void **)&orig_uname},
        {"sysctlbyname", (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname},
        {"sysctl", (void *)hook_sysctl, (void **)&orig_sysctl},
        {"mach_absolute_time", (void *)hook_mach_absolute_time, (void **)&orig_mach_absolute_time},
        {"clock_gettime", (void *)hook_clock_gettime, (void **)&orig_clock_gettime},
        {"host_statistics", (void *)hook_host_statistics, (void **)&orig_host_statistics},
        {"host_statistics64", (void *)hook_host_statistics64, (void **)&orig_host_statistics64},
    };
    
    int result = rebind_symbols(rebindings, sizeof(rebindings)/sizeof(rebindings[0]));
    if (result == 0) {
        NSLog(@"[LC] Hooked C functions via fishhook (uname, sysctl*, mach_absolute_time, clock_gettime, host_statistics*)");
    } else {
        NSLog(@"[LC] Warning: fishhook rebind_symbols failed with code %d", result);
    }
    
    // Hook UIDevice methods using method swizzling (works without JIT)
    Class UIDeviceClass = objc_getClass("UIDevice");
    if (UIDeviceClass) {
        Method modelMethod = class_getInstanceMethod(UIDeviceClass, @selector(model));
        Method systemVersionMethod = class_getInstanceMethod(UIDeviceClass, @selector(systemVersion));
        Method systemNameMethod = class_getInstanceMethod(UIDeviceClass, @selector(systemName));
        Method identifierForVendorMethod = class_getInstanceMethod(UIDeviceClass, @selector(identifierForVendor));
        Method batteryLevelMethod = class_getInstanceMethod(UIDeviceClass, @selector(batteryLevel));
        Method batteryStateMethod = class_getInstanceMethod(UIDeviceClass, @selector(batteryState));
        Method batteryMonitoringEnabledMethod = class_getInstanceMethod(UIDeviceClass, @selector(isBatteryMonitoringEnabled));
        
        if (modelMethod) {
            orig_UIDevice_model = (NSString* (*)(id, SEL))method_getImplementation(modelMethod);
            method_setImplementation(modelMethod, (IMP)hook_UIDevice_model);
        }
        if (systemVersionMethod) {
            orig_UIDevice_systemVersion = (NSString* (*)(id, SEL))method_getImplementation(systemVersionMethod);
            method_setImplementation(systemVersionMethod, (IMP)hook_UIDevice_systemVersion);
        }
        if (systemNameMethod) {
            orig_UIDevice_systemName = (NSString* (*)(id, SEL))method_getImplementation(systemNameMethod);
            method_setImplementation(systemNameMethod, (IMP)hook_UIDevice_systemName);
        }
        if (identifierForVendorMethod) {
            orig_UIDevice_identifierForVendor = (NSUUID* (*)(id, SEL))method_getImplementation(identifierForVendorMethod);
            method_setImplementation(identifierForVendorMethod, (IMP)hook_UIDevice_identifierForVendor);
        }
        if (batteryLevelMethod) {
            orig_UIDevice_batteryLevel = (float (*)(id, SEL))method_getImplementation(batteryLevelMethod);
            method_setImplementation(batteryLevelMethod, (IMP)hook_UIDevice_batteryLevel);
        }
        if (batteryStateMethod) {
            orig_UIDevice_batteryState = (NSInteger (*)(id, SEL))method_getImplementation(batteryStateMethod);
            method_setImplementation(batteryStateMethod, (IMP)hook_UIDevice_batteryState);
        }
        if (batteryMonitoringEnabledMethod) {
            orig_UIDevice_isBatteryMonitoringEnabled = (BOOL (*)(id, SEL))method_getImplementation(batteryMonitoringEnabledMethod);
            method_setImplementation(batteryMonitoringEnabledMethod, (IMP)hook_UIDevice_isBatteryMonitoringEnabled);
        }
        NSLog(@"[LC] Hooked UIDevice methods (model, systemVersion, systemName, identifierForVendor, battery*)");
    }
    
    // Hook NSProcessInfo methods using method swizzling
    Class NSProcessInfoClass = objc_getClass("NSProcessInfo");
    if (NSProcessInfoClass) {
        Method physicalMemoryMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(physicalMemory));
        Method processorCountMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(processorCount));
        Method activeProcessorCountMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(activeProcessorCount));
        Method operatingSystemVersionMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(operatingSystemVersion));
        Method operatingSystemVersionStringMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(operatingSystemVersionString));
        Method systemUptimeMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(systemUptime));
        Method thermalStateMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(thermalState));
        Method lowPowerModeMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(isLowPowerModeEnabled));
        
        if (physicalMemoryMethod) {
            orig_NSProcessInfo_physicalMemory = (unsigned long long (*)(id, SEL))method_getImplementation(physicalMemoryMethod);
            method_setImplementation(physicalMemoryMethod, (IMP)hook_NSProcessInfo_physicalMemory);
        }
        if (processorCountMethod) {
            orig_NSProcessInfo_processorCount = (NSUInteger (*)(id, SEL))method_getImplementation(processorCountMethod);
            method_setImplementation(processorCountMethod, (IMP)hook_NSProcessInfo_processorCount);
        }
        if (activeProcessorCountMethod) {
            orig_NSProcessInfo_activeProcessorCount = (NSUInteger (*)(id, SEL))method_getImplementation(activeProcessorCountMethod);
            method_setImplementation(activeProcessorCountMethod, (IMP)hook_NSProcessInfo_activeProcessorCount);
        }
        if (operatingSystemVersionMethod) {
            orig_NSProcessInfo_operatingSystemVersion = (NSOperatingSystemVersion (*)(id, SEL))method_getImplementation(operatingSystemVersionMethod);
            method_setImplementation(operatingSystemVersionMethod, (IMP)hook_NSProcessInfo_operatingSystemVersion);
        }
        if (operatingSystemVersionStringMethod) {
            orig_NSProcessInfo_operatingSystemVersionString = (NSString* (*)(id, SEL))method_getImplementation(operatingSystemVersionStringMethod);
            method_setImplementation(operatingSystemVersionStringMethod, (IMP)hook_NSProcessInfo_operatingSystemVersionString);
        }
        if (systemUptimeMethod) {
            orig_NSProcessInfo_systemUptime = (NSTimeInterval (*)(id, SEL))method_getImplementation(systemUptimeMethod);
            method_setImplementation(systemUptimeMethod, (IMP)hook_NSProcessInfo_systemUptime);
        }
        if (thermalStateMethod) {
            orig_NSProcessInfo_thermalState = (NSInteger (*)(id, SEL))method_getImplementation(thermalStateMethod);
            method_setImplementation(thermalStateMethod, (IMP)hook_NSProcessInfo_thermalState);
        }
        if (lowPowerModeMethod) {
            orig_NSProcessInfo_isLowPowerModeEnabled = (BOOL (*)(id, SEL))method_getImplementation(lowPowerModeMethod);
            method_setImplementation(lowPowerModeMethod, (IMP)hook_NSProcessInfo_isLowPowerModeEnabled);
        }
        NSLog(@"[LC] Hooked NSProcessInfo methods (memory, cpu, version, uptime, thermal, lowPower)");
    }
    
    // Hook UIScreen methods using method swizzling
    Class UIScreenClass = objc_getClass("UIScreen");
    if (UIScreenClass) {
        Method scaleMethod = class_getInstanceMethod(UIScreenClass, @selector(scale));
        Method nativeScaleMethod = class_getInstanceMethod(UIScreenClass, @selector(nativeScale));
        Method boundsMethod = class_getInstanceMethod(UIScreenClass, @selector(bounds));
        Method nativeBoundsMethod = class_getInstanceMethod(UIScreenClass, @selector(nativeBounds));
        Method brightnessMethod = class_getInstanceMethod(UIScreenClass, @selector(brightness));
        
        if (scaleMethod) {
            orig_UIScreen_scale = (CGFloat (*)(id, SEL))method_getImplementation(scaleMethod);
            method_setImplementation(scaleMethod, (IMP)hook_UIScreen_scale);
        }
        if (nativeScaleMethod) {
            orig_UIScreen_nativeScale = (CGFloat (*)(id, SEL))method_getImplementation(nativeScaleMethod);
            method_setImplementation(nativeScaleMethod, (IMP)hook_UIScreen_nativeScale);
        }
        if (boundsMethod) {
            orig_UIScreen_bounds = (CGRect (*)(id, SEL))method_getImplementation(boundsMethod);
            method_setImplementation(boundsMethod, (IMP)hook_UIScreen_bounds);
        }
        if (nativeBoundsMethod) {
            orig_UIScreen_nativeBounds = (CGRect (*)(id, SEL))method_getImplementation(nativeBoundsMethod);
            method_setImplementation(nativeBoundsMethod, (IMP)hook_UIScreen_nativeBounds);
        }
        if (brightnessMethod) {
            orig_UIScreen_brightness = (CGFloat (*)(id, SEL))method_getImplementation(brightnessMethod);
            method_setImplementation(brightnessMethod, (IMP)hook_UIScreen_brightness);
        }
        NSLog(@"[LC] Hooked UIScreen methods (scale, nativeScale, bounds, nativeBounds, brightness)");
    }
    
    // Hook ASIdentifierManager methods
    Class ASIdentifierManagerClass = objc_getClass("ASIdentifierManager");
    if (ASIdentifierManagerClass) {
        Method advertisingIdentifierMethod = class_getInstanceMethod(ASIdentifierManagerClass, @selector(advertisingIdentifier));
        
        if (advertisingIdentifierMethod) {
            orig_ASIdentifierManager_advertisingIdentifier = (NSUUID* (*)(id, SEL))method_getImplementation(advertisingIdentifierMethod);
            method_setImplementation(advertisingIdentifierMethod, (IMP)hook_ASIdentifierManager_advertisingIdentifier);
        }
        NSLog(@"[LC] Hooked ASIdentifierManager methods (advertisingIdentifier)");
    }
    
    // Initialize fingerprint protection with randomized values
    LCInitializeFingerprintProtection();
    
    NSLog(@"[LC] Comprehensive device spoofing hooks initialized");
}