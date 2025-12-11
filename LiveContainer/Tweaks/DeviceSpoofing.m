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
#import <sys/mount.h>
#import <sys/param.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <AdSupport/AdSupport.h>
#import <CommonCrypto/CommonDigest.h>
#import <WebKit/WebKit.h>
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

#pragma mark - Device Profiles - iOS 26.x (iPhone 17 Series - Predicted)

// iPhone 17 Pro Max (iOS 26.x) - Predicted specs based on Apple patterns
const LCDeviceProfile kDeviceProfileiPhone17ProMax = {
    .modelIdentifier = "iPhone18,2",
    .hardwareModel = "D104AP",
    .marketingName = "iPhone 17 Pro Max",
    .systemVersion = "26.0",
    .buildVersion = "24A5264n",
    .kernelVersion = "Darwin Kernel Version 26.0.0: Wed Sep 10 22:15:30 PDT 2025; root:xnu-12000.1.1~1/RELEASE_ARM64_T8150",
    .kernelRelease = "26.0.0",
    .physicalMemory = 12884901888ULL, // 12GB
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 460,
    .screenHeight = 998,
    .chipName = "Apple A19 Pro",
    .gpuName = "Apple A19 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17Pro = {
    .modelIdentifier = "iPhone18,1",
    .hardwareModel = "D103AP",
    .marketingName = "iPhone 17 Pro",
    .systemVersion = "26.0",
    .buildVersion = "24A5264n",
    .kernelVersion = "Darwin Kernel Version 26.0.0: Wed Sep 10 22:15:30 PDT 2025; root:xnu-12000.1.1~1/RELEASE_ARM64_T8150",
    .kernelRelease = "26.0.0",
    .physicalMemory = 12884901888ULL, // 12GB
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 420,
    .screenHeight = 912,
    .chipName = "Apple A19 Pro",
    .gpuName = "Apple A19 Pro GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17 = {
    .modelIdentifier = "iPhone18,3",
    .hardwareModel = "D57AP",
    .marketingName = "iPhone 17",
    .systemVersion = "26.0",
    .buildVersion = "24A5264n",
    .kernelVersion = "Darwin Kernel Version 26.0.0: Wed Sep 10 22:15:30 PDT 2025; root:xnu-12000.1.1~1/RELEASE_ARM64_T8140",
    .kernelRelease = "26.0.0",
    .physicalMemory = 8589934592ULL, // 8GB
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 402,
    .screenHeight = 874,
    .chipName = "Apple A19",
    .gpuName = "Apple A19 GPU"
};

const LCDeviceProfile kDeviceProfileiPhone17Air = {
    .modelIdentifier = "iPhone18,4",
    .hardwareModel = "D58AP",
    .marketingName = "iPhone 17 Air",
    .systemVersion = "26.0",
    .buildVersion = "24A5264n",
    .kernelVersion = "Darwin Kernel Version 26.0.0: Wed Sep 10 22:15:30 PDT 2025; root:xnu-12000.1.1~1/RELEASE_ARM64_T8140",
    .kernelRelease = "26.0.0",
    .physicalMemory = 8589934592ULL, // 8GB
    .cpuCoreCount = 6,
    .performanceCores = 2,
    .efficiencyCores = 4,
    .screenScale = 3.0,
    .screenWidth = 402,
    .screenHeight = 874,
    .chipName = "Apple A19",
    .gpuName = "Apple A19 GPU"
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
static NSString *g_customDeviceName = nil;      // Custom device name (e.g., "John's iPhone")
static NSString *g_customCarrierName = nil;     // Custom carrier name

// Identifier spoofing
static NSString *g_spoofedVendorID = nil;
static NSString *g_spoofedAdvertisingID = nil;
static NSString *g_spoofedInstallationID = nil;  // App installation ID
static NSString *g_spoofedMACAddress = nil;      // Spoofed MAC address
static BOOL g_spoofedAdTrackingEnabled = YES;    // Advertising tracking limit

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

// User-Agent spoofing
static NSString *g_spoofedUserAgent = nil;
static NSString *g_customUserAgent = nil;
static BOOL g_userAgentSpoofingEnabled = NO;

// Storage spoofing - using marketing units (1000-based) like Apple
#define LC_BYTES_PER_GB (1000ULL * 1000ULL * 1000ULL)
#define LC_DEFAULT_BLOCK_SIZE (4096ULL)

static BOOL g_storageSpoofingEnabled = NO;
static uint64_t g_spoofedStorageTotal = 0;     // Total storage in bytes (0 = use real)
static uint64_t g_spoofedStorageFree = 0;      // Free storage in bytes (0 = use real)
static NSString *g_spoofedStorageCapacityGB = nil;  // e.g., "128" for 128GB
static NSString *g_spoofedStorageFreeGB = nil;      // e.g., "45.2" for 45.2GB free

// Canvas/WebGL/Audio fingerprint protection
static BOOL g_canvasFingerprintProtectionEnabled = NO;
static NSInteger g_fingerprintNoiseSeed = 0;  // Per-session consistent noise seed

// iCloud/CloudKit/Siri privacy protection
static BOOL g_iCloudPrivacyProtectionEnabled = NO;
static BOOL g_siriPrivacyProtectionEnabled = NO;

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
static BOOL (*orig_ASIdentifierManager_isAdvertisingTrackingEnabled)(id self, SEL _cmd) = NULL;

// WKWebView method IMPs
static NSString* (*orig_WKWebView_customUserAgent)(id self, SEL _cmd) = NULL;
static void (*orig_WKWebView_setCustomUserAgent)(id self, SEL _cmd, NSString *userAgent) = NULL;
static NSString* (*orig_WKWebViewConfiguration_applicationNameForUserAgent)(id self, SEL _cmd) = NULL;

// NSMutableURLRequest method IMPs
static void (*orig_NSMutableURLRequest_setValue_forHTTPHeaderField)(id self, SEL _cmd, NSString *value, NSString *field) = NULL;
static void (*orig_NSMutableURLRequest_setAllHTTPHeaderFields)(id self, SEL _cmd, NSDictionary *headerFields) = NULL;

// NSURLSessionConfiguration method IMPs
static NSDictionary* (*orig_NSURLSessionConfiguration_HTTPAdditionalHeaders)(id self, SEL _cmd) = NULL;
static void (*orig_NSURLSessionConfiguration_setHTTPAdditionalHeaders)(id self, SEL _cmd, NSDictionary *headers) = NULL;

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

// Storage spoofing function pointers
static int (*orig_statfs)(const char *path, struct statfs *buf) = NULL;
static int (*orig_statfs64)(const char *path, struct statfs *buf) = NULL;

// NSFileManager method IMPs for storage
static NSDictionary* (*orig_NSFileManager_attributesOfFileSystemForPath)(id self, SEL _cmd, NSString *path, NSError **error) = NULL;

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

static NSString* getSpoofedUserAgent(void) {
    // Custom user agent takes priority
    if (g_customUserAgent) {
        return g_customUserAgent;
    }
    
    // Generate user agent based on current profile
    if (g_currentProfile) {
        // User-Agent format: Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1
        NSString *deviceType = @"iPhone";
        NSString *cpuType = @"iPhone OS";
        
        if (strncmp(g_currentProfile->modelIdentifier, "iPad", 4) == 0) {
            deviceType = @"iPad";
            cpuType = @"CPU OS";
        }
        
        // Convert version string (e.g., "18.1") to underscore format (e.g., "18_1")
        NSString *versionStr = @(g_currentProfile->systemVersion);
        NSString *versionUnderscore = [versionStr stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        
        // Get proper WebKit/Safari version based on iOS version
        // WebKit versions are tied to iOS releases
        NSString *safariVersion = nil;
        NSString *webKitVersion = nil;
        NSString *buildNumber = nil;
        
        // Extract major version
        int majorVersion = [[versionStr componentsSeparatedByString:@"."].firstObject intValue];
        
        // Map iOS version to WebKit/Safari version
        // Reference: https://en.wikipedia.org/wiki/Safari_version_history
        if (majorVersion >= 26) {
            // iOS 26.x (hypothetical)
            safariVersion = @"26.0";
            webKitVersion = @"620.1.15";
            buildNumber = @"22A5307f";
        } else if (majorVersion >= 18) {
            // iOS 18.x
            safariVersion = @"18.0";
            webKitVersion = @"619.1.26";
            buildNumber = @"22A3354";
        } else if (majorVersion >= 17) {
            // iOS 17.x
            if ([versionStr hasPrefix:@"17.6"]) {
                safariVersion = @"17.6";
                webKitVersion = @"618.3.11";
                buildNumber = @"21G93";
            } else if ([versionStr hasPrefix:@"17.5"]) {
                safariVersion = @"17.5";
                webKitVersion = @"618.2.12";
                buildNumber = @"21F90";
            } else if ([versionStr hasPrefix:@"17.4"]) {
                safariVersion = @"17.4";
                webKitVersion = @"618.1.15";
                buildNumber = @"21E219";
            } else {
                safariVersion = @"17.0";
                webKitVersion = @"617.1.17";
                buildNumber = @"21A329";
            }
        } else if (majorVersion >= 16) {
            // iOS 16.x
            safariVersion = @"16.6";
            webKitVersion = @"616.3.14";
            buildNumber = @"20G75";
        } else if (majorVersion >= 15) {
            // iOS 15.x
            safariVersion = @"15.6";
            webKitVersion = @"615.3.12";
            buildNumber = @"19G82";
        } else {
            // Fallback
            safariVersion = versionStr;
            webKitVersion = @"605.1.15";
            buildNumber = @"15E148";
        }
        
        // Build the User-Agent string matching real Safari format
        g_spoofedUserAgent = [NSString stringWithFormat:
            @"Mozilla/5.0 (%@; %@ %@ like Mac OS X) AppleWebKit/%@ (KHTML, like Gecko) Version/%@ Mobile/%@ Safari/%@",
            deviceType, cpuType, versionUnderscore, webKitVersion, safariVersion, buildNumber, webKitVersion];
        
        return g_spoofedUserAgent;
    }
    
    return nil;
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

static NSString* hook_UIDevice_name(id self, SEL _cmd) {
    // Return custom device name if set
    if (g_deviceSpoofingEnabled && g_customDeviceName && g_customDeviceName.length > 0) {
        return g_customDeviceName;
    }
    
    // Generate a realistic device name based on profile
    if (g_deviceSpoofingEnabled && g_currentProfile) {
        // Generate names like "John's iPhone" or "iPhone"
        static NSArray *firstNames = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            firstNames = @[@"Alex", @"Sam", @"Jordan", @"Taylor", @"Casey", 
                          @"Morgan", @"Riley", @"Avery", @"Quinn", @"Drew"];
        });
        
        // Use a consistent name based on some seed
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"app";
        NSUInteger nameIndex = [bundleID hash] % firstNames.count;
        NSString *firstName = firstNames[nameIndex];
        
        NSString *deviceType = @"iPhone";
        if (strncmp(g_currentProfile->modelIdentifier, "iPad", 4) == 0) {
            deviceType = @"iPad";
        }
        
        return [NSString stringWithFormat:@"%@'s %@", firstName, deviceType];
    }
    
    if (orig_UIDevice_name) return orig_UIDevice_name(self, _cmd);
    return @"iPhone";
}

static NSUUID* hook_UIDevice_identifierForVendor(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_UIDevice_identifierForVendor) return orig_UIDevice_identifierForVendor(self, _cmd);
        return [[NSUUID alloc] init];
    }
    
    // Return spoofed vendor ID if explicitly set
    if (g_spoofedVendorID && g_spoofedVendorID.length > 0) {
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:g_spoofedVendorID];
        if (uuid) {
            NSLog(@"[LC] Returning explicitly set IDFV: %@", g_spoofedVendorID);
            return uuid;
        }
    }
    
    // Generate a consistent spoofed UUID based on:
    // 1. App bundle ID (or vendor portion for same-vendor apps)
    // 2. Device profile (so changing profile changes IDFV)
    // 3. A salt to make it unique per LiveContainer instance
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.unknown.app";
    
    // Extract vendor portion (first two parts of bundle ID)
    NSArray *components = [bundleID componentsSeparatedByString:@"."];
    NSString *vendorPortion = bundleID;
    if (components.count >= 2) {
        vendorPortion = [NSString stringWithFormat:@"%@.%@", components[0], components[1]];
    }
    
    // Include profile name for uniqueness
    NSString *profileName = g_currentProfileName ?: @"default";
    
    // Generate a salt based on the LiveContainer's own identifier
    NSString *lcIdentifier = [[NSBundle mainBundle] bundleIdentifier] ?: @"lc";
    
    // Combine all factors
    NSString *seedString = [NSString stringWithFormat:@"IDFV_%@_%@_%@_SALT2025", vendorPortion, profileName, lcIdentifier];
    const char *cstr = [seedString UTF8String];
    
    // Use SHA256 for better distribution (truncate to 16 bytes for UUID)
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cstr, (CC_LONG)strlen(cstr), hash);
    
    // Set UUID version 4 (random) and variant bits for RFC 4122 compliance
    hash[6] = (hash[6] & 0x0F) | 0x40; // Version 4
    hash[8] = (hash[8] & 0x3F) | 0x80; // Variant 1
    
    // Format as UUID (8-4-4-4-12)
    NSString *uuidString = [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                           hash[0], hash[1], hash[2], hash[3],
                           hash[4], hash[5],
                           hash[6], hash[7],
                           hash[8], hash[9],
                           hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]];
    
    NSLog(@"[LC] Generated IDFV for vendor '%@' with profile '%@': %@", vendorPortion, profileName, uuidString);
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
    if (g_spoofedAdvertisingID && g_spoofedAdvertisingID.length > 0) {
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:g_spoofedAdvertisingID];
        if (uuid) return uuid;
    }
    
    // Return zeroed UUID (same as when "Limit Ad Tracking" is enabled)
    // This is the safest approach for privacy
    return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
}

static BOOL hook_ASIdentifierManager_isAdvertisingTrackingEnabled(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_ASIdentifierManager_isAdvertisingTrackingEnabled) {
            return orig_ASIdentifierManager_isAdvertisingTrackingEnabled(self, _cmd);
        }
        return NO;
    }
    
    // Return the spoofed value (default: NO for privacy)
    return g_spoofedAdTrackingEnabled;
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

#pragma mark - User-Agent Hooks

// Hook WKWebView customUserAgent getter
static NSString* hook_WKWebView_customUserAgent(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_WKWebView_customUserAgent) return orig_WKWebView_customUserAgent(self, _cmd);
        return nil;
    }
    
    // Check if a custom user agent was already set on this webview
    NSString *existingUA = nil;
    if (orig_WKWebView_customUserAgent) {
        existingUA = orig_WKWebView_customUserAgent(self, _cmd);
    }
    
    // If no custom UA is set, return our spoofed one
    if (!existingUA || existingUA.length == 0) {
        return getSpoofedUserAgent();
    }
    
    return existingUA;
}

// Hook WKWebView customUserAgent setter to intercept and modify
static void hook_WKWebView_setCustomUserAgent(id self, SEL _cmd, NSString *userAgent) {
    if (!g_deviceSpoofingEnabled) {
        if (orig_WKWebView_setCustomUserAgent) orig_WKWebView_setCustomUserAgent(self, _cmd, userAgent);
        return;
    }
    
    // Always set our spoofed UA to ensure consistency
    NSString *spoofedUA = getSpoofedUserAgent();
    if (spoofedUA) {
        userAgent = spoofedUA;
    }
    
    if (orig_WKWebView_setCustomUserAgent) {
        orig_WKWebView_setCustomUserAgent(self, _cmd, userAgent);
    }
}

// Hook WKWebViewConfiguration applicationNameForUserAgent to append spoofed app name
static NSString* hook_WKWebViewConfiguration_applicationNameForUserAgent(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled || !g_userAgentSpoofingEnabled) {
        if (orig_WKWebViewConfiguration_applicationNameForUserAgent) {
            return orig_WKWebViewConfiguration_applicationNameForUserAgent(self, _cmd);
        }
        return nil;
    }
    
    // Return a consistent application name based on the profile
    // This is appended to the default WebKit user agent
    if (g_currentProfile) {
        // Format: Version/X.X Mobile/BUILDNUM Safari/XXX.X.XX
        NSString *versionStr = @(g_currentProfile->systemVersion);
        int majorVersion = [[versionStr componentsSeparatedByString:@"."].firstObject intValue];
        
        NSString *buildNumber = @"15E148";
        NSString *safariVersion = @"605.1.15";
        
        if (majorVersion >= 26) {
            buildNumber = @"22A5307f";
            safariVersion = @"620.1.15";
        } else if (majorVersion >= 18) {
            buildNumber = @"22A3354";
            safariVersion = @"619.1.26";
        } else if (majorVersion >= 17) {
            buildNumber = @"21G93";
            safariVersion = @"618.3.11";
        } else if (majorVersion >= 16) {
            buildNumber = @"20G75";
            safariVersion = @"616.3.14";
        }
        
        return [NSString stringWithFormat:@"Version/%@ Mobile/%@ Safari/%@", versionStr, buildNumber, safariVersion];
    }
    
    if (orig_WKWebViewConfiguration_applicationNameForUserAgent) {
        return orig_WKWebViewConfiguration_applicationNameForUserAgent(self, _cmd);
    }
    return nil;
}

// Hook NSMutableURLRequest setValue:forHTTPHeaderField: to intercept User-Agent
static void hook_NSMutableURLRequest_setValue_forHTTPHeaderField(id self, SEL _cmd, NSString *value, NSString *field) {
    if (g_deviceSpoofingEnabled && field && [field caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
        NSString *spoofedUA = getSpoofedUserAgent();
        if (spoofedUA) {
            value = spoofedUA;
        }
    }
    
    if (orig_NSMutableURLRequest_setValue_forHTTPHeaderField) {
        orig_NSMutableURLRequest_setValue_forHTTPHeaderField(self, _cmd, value, field);
    }
}

// Hook NSMutableURLRequest setAllHTTPHeaderFields: to intercept User-Agent in bulk headers
static void hook_NSMutableURLRequest_setAllHTTPHeaderFields(id self, SEL _cmd, NSDictionary *headerFields) {
    if (g_deviceSpoofingEnabled && headerFields) {
        NSString *spoofedUA = getSpoofedUserAgent();
        if (spoofedUA) {
            NSMutableDictionary *modifiedHeaders = [headerFields mutableCopy];
            
            // Find and replace User-Agent (case-insensitive key search)
            for (NSString *key in headerFields.allKeys) {
                if ([key caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
                    modifiedHeaders[key] = spoofedUA;
                    break;
                }
            }
            
            headerFields = modifiedHeaders;
        }
    }
    
    if (orig_NSMutableURLRequest_setAllHTTPHeaderFields) {
        orig_NSMutableURLRequest_setAllHTTPHeaderFields(self, _cmd, headerFields);
    }
}

// Hook NSURLSessionConfiguration HTTPAdditionalHeaders getter
static NSDictionary* hook_NSURLSessionConfiguration_HTTPAdditionalHeaders(id self, SEL _cmd) {
    NSDictionary *headers = nil;
    if (orig_NSURLSessionConfiguration_HTTPAdditionalHeaders) {
        headers = orig_NSURLSessionConfiguration_HTTPAdditionalHeaders(self, _cmd);
    }
    
    if (!g_deviceSpoofingEnabled) {
        return headers;
    }
    
    NSString *spoofedUA = getSpoofedUserAgent();
    if (!spoofedUA) {
        return headers;
    }
    
    // Add or replace User-Agent in the returned headers
    NSMutableDictionary *modifiedHeaders = headers ? [headers mutableCopy] : [NSMutableDictionary dictionary];
    modifiedHeaders[@"User-Agent"] = spoofedUA;
    
    return modifiedHeaders;
}

// Hook NSURLSessionConfiguration HTTPAdditionalHeaders setter
static void hook_NSURLSessionConfiguration_setHTTPAdditionalHeaders(id self, SEL _cmd, NSDictionary *headers) {
    if (g_deviceSpoofingEnabled) {
        NSString *spoofedUA = getSpoofedUserAgent();
        if (spoofedUA) {
            NSMutableDictionary *modifiedHeaders = headers ? [headers mutableCopy] : [NSMutableDictionary dictionary];
            modifiedHeaders[@"User-Agent"] = spoofedUA;
            headers = modifiedHeaders;
        }
    }
    
    if (orig_NSURLSessionConfiguration_setHTTPAdditionalHeaders) {
        orig_NSURLSessionConfiguration_setHTTPAdditionalHeaders(self, _cmd, headers);
    }
}

#pragma mark - Storage Spoofing Hooks

// Helper function to get spoofed storage values
static void getSpoofedStorageValues(uint64_t *totalBytes, uint64_t *freeBytes) {
    if (!totalBytes || !freeBytes) return;
    
    // Initialize with zeros
    *totalBytes = 0;
    *freeBytes = 0;
    
    if (!g_storageSpoofingEnabled) return;
    
    // Use direct byte values if set
    if (g_spoofedStorageTotal > 0) {
        *totalBytes = g_spoofedStorageTotal;
        *freeBytes = g_spoofedStorageFree > 0 ? g_spoofedStorageFree : (g_spoofedStorageTotal / 3); // Default 33% free
        return;
    }
    
    // Otherwise use GB string values
    if (g_spoofedStorageCapacityGB) {
        double totalGB = [g_spoofedStorageCapacityGB doubleValue];
        if (totalGB > 0) {
            *totalBytes = (uint64_t)(totalGB * LC_BYTES_PER_GB);
            
            if (g_spoofedStorageFreeGB) {
                double freeGB = [g_spoofedStorageFreeGB doubleValue];
                *freeBytes = (uint64_t)(freeGB * LC_BYTES_PER_GB);
            } else {
                // Default to ~30% free space
                *freeBytes = (uint64_t)(*totalBytes * 0.30);
            }
        }
    }
}

// Helper to calculate block count from bytes
static uint64_t calculateStorageBlockCount(uint64_t bytes, uint32_t blockSize) {
    if (blockSize == 0) blockSize = LC_DEFAULT_BLOCK_SIZE;
    return (bytes + blockSize - 1) / blockSize;
}

// Hook statfs to spoof storage info
static int hook_statfs(const char *path, struct statfs *buf) {
    if (!orig_statfs) {
        orig_statfs = (int (*)(const char *, struct statfs *))dlsym(RTLD_DEFAULT, "statfs");
        if (!orig_statfs) return -1;
    }
    
    int result = orig_statfs(path, buf);
    
    if (result != 0 || !buf || !g_deviceSpoofingEnabled || !g_storageSpoofingEnabled) {
        return result;
    }
    
    // Only spoof for main filesystem paths
    if (path && (strcmp(path, "/") == 0 || 
                 strcmp(path, "/var") == 0 || 
                 strcmp(path, "/private/var") == 0 ||
                 strncmp(path, "/var/mobile", 11) == 0 ||
                 strncmp(path, "/private/var/mobile", 19) == 0)) {
        
        uint64_t totalBytes, freeBytes;
        getSpoofedStorageValues(&totalBytes, &freeBytes);
        
        if (totalBytes > 0 && buf->f_bsize > 0) {
            buf->f_blocks = calculateStorageBlockCount(totalBytes, buf->f_bsize);
            buf->f_bfree = calculateStorageBlockCount(freeBytes, buf->f_bsize);
            buf->f_bavail = buf->f_bfree;
        }
    }
    
    return result;
}

// Hook statfs64 (64-bit variant)
static int hook_statfs64(const char *path, struct statfs *buf) {
    if (!orig_statfs64) {
        orig_statfs64 = (int (*)(const char *, struct statfs *))dlsym(RTLD_DEFAULT, "statfs64");
        if (!orig_statfs64) {
            // Fallback to statfs if statfs64 not available
            return hook_statfs(path, buf);
        }
    }
    
    int result = orig_statfs64(path, buf);
    
    if (result != 0 || !buf || !g_deviceSpoofingEnabled || !g_storageSpoofingEnabled) {
        return result;
    }
    
    // Only spoof for main filesystem paths
    if (path && (strcmp(path, "/") == 0 || 
                 strcmp(path, "/var") == 0 || 
                 strcmp(path, "/private/var") == 0 ||
                 strncmp(path, "/var/mobile", 11) == 0 ||
                 strncmp(path, "/private/var/mobile", 19) == 0)) {
        
        uint64_t totalBytes, freeBytes;
        getSpoofedStorageValues(&totalBytes, &freeBytes);
        
        if (totalBytes > 0 && buf->f_bsize > 0) {
            buf->f_blocks = calculateStorageBlockCount(totalBytes, buf->f_bsize);
            buf->f_bfree = calculateStorageBlockCount(freeBytes, buf->f_bsize);
            buf->f_bavail = buf->f_bfree;
        }
    }
    
    return result;
}

// Hook NSFileManager attributesOfFileSystemForPath:error:
static NSDictionary* hook_NSFileManager_attributesOfFileSystemForPath(id self, SEL _cmd, NSString *path, NSError **error) {
    NSDictionary *originalAttrs = nil;
    if (orig_NSFileManager_attributesOfFileSystemForPath) {
        originalAttrs = orig_NSFileManager_attributesOfFileSystemForPath(self, _cmd, path, error);
    }
    
    if (!originalAttrs || !g_deviceSpoofingEnabled || !g_storageSpoofingEnabled) {
        return originalAttrs;
    }
    
    uint64_t totalBytes, freeBytes;
    getSpoofedStorageValues(&totalBytes, &freeBytes);
    
    if (totalBytes == 0) {
        return originalAttrs;
    }
    
    NSMutableDictionary *modifiedAttrs = [originalAttrs mutableCopy];
    modifiedAttrs[NSFileSystemSize] = @(totalBytes);
    modifiedAttrs[NSFileSystemFreeSize] = @(freeBytes);
    
    return modifiedAttrs;
}

#pragma mark - Canvas/WebGL/Audio Fingerprint Protection

// JavaScript injection for canvas, WebGL, and audio fingerprint protection
// Based on Project-X CanvasFingerprintHooks approach
static NSString *getCanvasFingerprintProtectionScript(void) {
    return @"(function() {\n"
        "    if (window.__lcFingerprintProtection) return;\n"
        "    window.__lcFingerprintProtection = true;\n"
        "\n"
        "    // Canvas 2D Fingerprint Protection\n"
        "    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;\n"
        "    const origToBlob = HTMLCanvasElement.prototype.toBlob;\n"
        "    const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;\n"
        "\n"
        "    function addNoise(canvas) {\n"
        "        try {\n"
        "            const ctx = canvas.getContext('2d');\n"
        "            if (!ctx) return;\n"
        "            const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);\n"
        "            const pixels = imageData.data;\n"
        "            for (let i = 0; i < pixels.length; i += 4) {\n"
        "                if (Math.random() < 0.02) {\n"
        "                    pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));\n"
        "                    pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));\n"
        "                    pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));\n"
        "                }\n"
        "            }\n"
        "            ctx.putImageData(imageData, 0, 0);\n"
        "        } catch (e) {}\n"
        "    }\n"
        "\n"
        "    HTMLCanvasElement.prototype.toDataURL = function() {\n"
        "        addNoise(this);\n"
        "        return origToDataURL.apply(this, arguments);\n"
        "    };\n"
        "\n"
        "    HTMLCanvasElement.prototype.toBlob = function(callback) {\n"
        "        addNoise(this);\n"
        "        return origToBlob.apply(this, arguments);\n"
        "    };\n"
        "\n"
        "    CanvasRenderingContext2D.prototype.getImageData = function() {\n"
        "        const imageData = origGetImageData.apply(this, arguments);\n"
        "        const pixels = imageData.data;\n"
        "        for (let i = 0; i < pixels.length; i += 4) {\n"
        "            if (Math.random() < 0.02) {\n"
        "                pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));\n"
        "                pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));\n"
        "                pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));\n"
        "            }\n"
        "        }\n"
        "        return imageData;\n"
        "    };\n"
        "\n"
        "    // WebGL Fingerprint Protection (WebGL1 & WebGL2)\n"
        "    const spoofedVendor = 'Apple Inc.';\n"
        "    const spoofedRenderer = 'Apple GPU';\n"
        "\n"
        "    function hookWebGLContext(prototype) {\n"
        "        if (!prototype) return;\n"
        "\n"
        "        const origReadPixels = prototype.readPixels;\n"
        "        prototype.readPixels = function(x, y, width, height, format, type, pixels) {\n"
        "            origReadPixels.apply(this, arguments);\n"
        "            if (pixels instanceof Uint8Array) {\n"
        "                for (let i = 0; i < pixels.length; i += 4) {\n"
        "                    if (Math.random() < 0.02) {\n"
        "                        pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));\n"
        "                        pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));\n"
        "                        pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));\n"
        "                    }\n"
        "                }\n"
        "            }\n"
        "        };\n"
        "\n"
        "        const origGetParameter = prototype.getParameter;\n"
        "        prototype.getParameter = function(param) {\n"
        "            if (param === 37445) return spoofedVendor;\n"
        "            if (param === 37446) return spoofedRenderer;\n"
        "            if (param === this.MAX_TEXTURE_SIZE) return 4096 + Math.floor(Math.random() * 10);\n"
        "            if (param === this.MAX_RENDERBUFFER_SIZE) return 4096 + Math.floor(Math.random() * 10);\n"
        "            if (param === this.MAX_VIEWPORT_DIMS) {\n"
        "                const result = origGetParameter.call(this, param);\n"
        "                if (result) result[0] += Math.floor(Math.random() * 10);\n"
        "                return result;\n"
        "            }\n"
        "            return origGetParameter.call(this, param);\n"
        "        };\n"
        "\n"
        "        const origGetSupportedExtensions = prototype.getSupportedExtensions;\n"
        "        prototype.getSupportedExtensions = function() {\n"
        "            const exts = origGetSupportedExtensions.call(this) || [];\n"
        "            return exts.slice().sort(() => Math.random() - 0.5);\n"
        "        };\n"
        "\n"
        "        const origGetShaderPrecisionFormat = prototype.getShaderPrecisionFormat;\n"
        "        prototype.getShaderPrecisionFormat = function() {\n"
        "            const res = origGetShaderPrecisionFormat.apply(this, arguments);\n"
        "            if (res && typeof res === 'object') {\n"
        "                res.precision += Math.floor(Math.random() * 2);\n"
        "            }\n"
        "            return res;\n"
        "        };\n"
        "    }\n"
        "\n"
        "    if (window.WebGLRenderingContext) {\n"
        "        hookWebGLContext(WebGLRenderingContext.prototype);\n"
        "    }\n"
        "    if (window.WebGL2RenderingContext) {\n"
        "        hookWebGLContext(WebGL2RenderingContext.prototype);\n"
        "    }\n"
        "\n"
        "    // Audio Fingerprint Protection\n"
        "    if (window.AnalyserNode) {\n"
        "        const origGetFloatFrequencyData = AnalyserNode.prototype.getFloatFrequencyData;\n"
        "        AnalyserNode.prototype.getFloatFrequencyData = function(array) {\n"
        "            origGetFloatFrequencyData.call(this, array);\n"
        "            for (let i = 0; i < array.length; i++) {\n"
        "                array[i] += (Math.random() - 0.5) * 0.1;\n"
        "            }\n"
        "        };\n"
        "\n"
        "        const origGetByteFrequencyData = AnalyserNode.prototype.getByteFrequencyData;\n"
        "        AnalyserNode.prototype.getByteFrequencyData = function(array) {\n"
        "            origGetByteFrequencyData.call(this, array);\n"
        "            for (let i = 0; i < array.length; i++) {\n"
        "                array[i] = Math.max(0, Math.min(255, array[i] + Math.floor((Math.random() - 0.5) * 2)));\n"
        "            }\n"
        "        };\n"
        "    }\n"
        "\n"
        "    if (window.AudioBuffer) {\n"
        "        const origGetChannelData = AudioBuffer.prototype.getChannelData;\n"
        "        AudioBuffer.prototype.getChannelData = function() {\n"
        "            const data = origGetChannelData.apply(this, arguments);\n"
        "            for (let i = 0; i < data.length; i += 100) {\n"
        "                data[i] += (Math.random() - 0.5) * 0.0001;\n"
        "            }\n"
        "            return data;\n"
        "        };\n"
        "    }\n"
        "\n"
        "    // Font Fingerprint Protection\n"
        "    if (window.CanvasRenderingContext2D) {\n"
        "        const origMeasureText = CanvasRenderingContext2D.prototype.measureText;\n"
        "        CanvasRenderingContext2D.prototype.measureText = function(text) {\n"
        "            const result = origMeasureText.apply(this, arguments);\n"
        "            const width = result.width * (1 + (Math.random() - 0.5) * 0.01);\n"
        "            Object.defineProperty(result, 'width', { value: width, writable: false });\n"
        "            return result;\n"
        "        };\n"
        "    }\n"
        "\n"
        "    // Navigator Fonts API (if available)\n"
        "    if (window.navigator && window.navigator.fonts && window.navigator.fonts.query) {\n"
        "        const origAvailableFonts = window.navigator.fonts.query;\n"
        "        window.navigator.fonts.query = function() {\n"
        "            return origAvailableFonts.apply(this, arguments).then(fonts => {\n"
        "                return fonts.slice().sort(() => Math.random() - 0.5);\n"
        "            });\n"
        "        };\n"
        "    }\n"
        "\n"
        "    // Recursive iframe injection with MutationObserver\n"
        "    function injectAllFrames(win) {\n"
        "        try {\n"
        "            if (win.__lcFingerprintProtection) return;\n"
        "            win.eval('(' + arguments.callee.toString() + ')(window)');\n"
        "        } catch (e) {}\n"
        "        for (let i = 0; i < win.frames.length; i++) {\n"
        "            try { injectAllFrames(win.frames[i]); } catch (e) {}\n"
        "        }\n"
        "    }\n"
        "\n"
        "    const observer = new MutationObserver(function(mutations) {\n"
        "        mutations.forEach(function(mutation) {\n"
        "            mutation.addedNodes.forEach(function(node) {\n"
        "                if (node.tagName === 'IFRAME') {\n"
        "                    try { injectAllFrames(node.contentWindow); } catch (e) {}\n"
        "                }\n"
        "            });\n"
        "        });\n"
        "    });\n"
        "    observer.observe(document, { childList: true, subtree: true });\n"
        "\n"
        "    console.log('[LiveContainer] Canvas, Audio, WebGL, WebGL2, and Font fingerprint protection enabled');\n"
        "})();";
}

// Hook for WKUserContentController to inject fingerprint protection script
static void (*orig_WKUserContentController_addUserScript)(id self, SEL _cmd, WKUserScript *userScript) = NULL;

static void hook_WKUserContentController_addUserScript(id self, SEL _cmd, WKUserScript *userScript) {
    if (orig_WKUserContentController_addUserScript) {
        orig_WKUserContentController_addUserScript(self, _cmd, userScript);
    }
}

// Inject fingerprint protection into WKWebView on initialization
static id (*orig_WKWebView_initWithFrame_configuration)(id self, SEL _cmd, CGRect frame, WKWebViewConfiguration *configuration) = NULL;

static id hook_WKWebView_initWithFrame_configuration(id self, SEL _cmd, CGRect frame, WKWebViewConfiguration *configuration) {
    // Call original first
    id result = nil;
    if (orig_WKWebView_initWithFrame_configuration) {
        result = orig_WKWebView_initWithFrame_configuration(self, _cmd, frame, configuration);
    }
    
    // Inject fingerprint protection if enabled
    if (result && g_deviceSpoofingEnabled && g_canvasFingerprintProtectionEnabled) {
        @try {
            WKUserContentController *contentController = configuration.userContentController;
            if (!contentController) {
                contentController = [[WKUserContentController alloc] init];
                configuration.userContentController = contentController;
            }
            
            // Check if script already injected
            BOOL alreadyInjected = NO;
            for (WKUserScript *script in contentController.userScripts) {
                if ([script.source containsString:@"__lcFingerprintProtection"]) {
                    alreadyInjected = YES;
                    break;
                }
            }
            
            if (!alreadyInjected) {
                NSString *scriptSource = getCanvasFingerprintProtectionScript();
                WKUserScript *script = [[WKUserScript alloc] initWithSource:scriptSource
                                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                           forMainFrameOnly:NO];
                [contentController addUserScript:script];
                NSLog(@"[LC] Injected canvas fingerprint protection script");
            }
        } @catch (NSException *e) {
            NSLog(@"[LC] Failed to inject fingerprint protection: %@", e);
        }
    }
    
    return result;
}

#pragma mark - iCloud/CloudKit Privacy Protection Hooks

// NSFileManager ubiquityIdentityToken hook - blocks iCloud account fingerprinting
static id (*orig_NSFileManager_ubiquityIdentityToken)(id self, SEL _cmd) = NULL;
static id hook_NSFileManager_ubiquityIdentityToken(id self, SEL _cmd) {
    if (g_iCloudPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking ubiquityIdentityToken access (iCloud fingerprint protection)");
        return nil;
    }
    if (orig_NSFileManager_ubiquityIdentityToken) {
        return orig_NSFileManager_ubiquityIdentityToken(self, _cmd);
    }
    return nil;
}

// CKContainer accountStatusWithCompletionHandler hook
static void (*orig_CKContainer_accountStatusWithCompletionHandler)(id self, SEL _cmd, void (^completionHandler)(NSInteger, NSError *)) = NULL;
static void hook_CKContainer_accountStatusWithCompletionHandler(id self, SEL _cmd, void (^completionHandler)(NSInteger, NSError *)) {
    if (g_iCloudPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking CKContainer accountStatus (returning no account)");
        if (completionHandler) {
            // CKAccountStatusNoAccount = 1
            NSError *error = [NSError errorWithDomain:@"CKErrorDomain" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"iCloud access denied"}];
            completionHandler(1, error);
        }
        return;
    }
    if (orig_CKContainer_accountStatusWithCompletionHandler) {
        orig_CKContainer_accountStatusWithCompletionHandler(self, _cmd, completionHandler);
    }
}

// CKContainer defaultContainer hook
static id (*orig_CKContainer_defaultContainer)(id self, SEL _cmd) = NULL;
static id hook_CKContainer_defaultContainer(id self, SEL _cmd) {
    if (g_iCloudPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking CKContainer defaultContainer access");
        return nil;
    }
    if (orig_CKContainer_defaultContainer) {
        return orig_CKContainer_defaultContainer(self, _cmd);
    }
    return nil;
}

// CKContainer containerWithIdentifier hook
static id (*orig_CKContainer_containerWithIdentifier)(id self, SEL _cmd, NSString *identifier) = NULL;
static id hook_CKContainer_containerWithIdentifier(id self, SEL _cmd, NSString *identifier) {
    if (g_iCloudPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking CKContainer containerWithIdentifier: %@", identifier);
        return nil;
    }
    if (orig_CKContainer_containerWithIdentifier) {
        return orig_CKContainer_containerWithIdentifier(self, _cmd, identifier);
    }
    return nil;
}

// CKContainer fetchUserRecordIDWithCompletionHandler hook
static void (*orig_CKContainer_fetchUserRecordIDWithCompletionHandler)(id self, SEL _cmd, void (^completionHandler)(id, NSError *)) = NULL;
static void hook_CKContainer_fetchUserRecordIDWithCompletionHandler(id self, SEL _cmd, void (^completionHandler)(id, NSError *)) {
    if (g_iCloudPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking CKContainer fetchUserRecordID");
        if (completionHandler) {
            // CKErrorNotAuthenticated = 9
            NSError *error = [NSError errorWithDomain:@"CKErrorDomain" code:9 userInfo:@{NSLocalizedDescriptionKey: @"User authentication failed"}];
            completionHandler(nil, error);
        }
        return;
    }
    if (orig_CKContainer_fetchUserRecordIDWithCompletionHandler) {
        orig_CKContainer_fetchUserRecordIDWithCompletionHandler(self, _cmd, completionHandler);
    }
}

// CKContainer requestApplicationPermission hook
static void (*orig_CKContainer_requestApplicationPermission)(id self, SEL _cmd, NSUInteger permission, void (^completionHandler)(NSInteger, NSError *)) = NULL;
static void hook_CKContainer_requestApplicationPermission(id self, SEL _cmd, NSUInteger permission, void (^completionHandler)(NSInteger, NSError *)) {
    if (g_iCloudPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking CKContainer requestApplicationPermission");
        if (completionHandler) {
            // CKErrorPermissionFailure = 10, CKApplicationPermissionStatusDenied = 2
            NSError *error = [NSError errorWithDomain:@"CKErrorDomain" code:10 userInfo:@{NSLocalizedDescriptionKey: @"iCloud permission denied"}];
            completionHandler(2, error);
        }
        return;
    }
    if (orig_CKContainer_requestApplicationPermission) {
        orig_CKContainer_requestApplicationPermission(self, _cmd, permission, completionHandler);
    }
}

// CKDatabase fetchRecordWithID hook
static void (*orig_CKDatabase_fetchRecordWithID)(id self, SEL _cmd, id recordID, void (^completionHandler)(id, NSError *)) = NULL;
static void hook_CKDatabase_fetchRecordWithID(id self, SEL _cmd, id recordID, void (^completionHandler)(id, NSError *)) {
    if (g_iCloudPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking CKDatabase fetchRecordWithID");
        if (completionHandler) {
            NSError *error = [NSError errorWithDomain:@"CKErrorDomain" code:10 userInfo:@{NSLocalizedDescriptionKey: @"iCloud access denied"}];
            completionHandler(nil, error);
        }
        return;
    }
    if (orig_CKDatabase_fetchRecordWithID) {
        orig_CKDatabase_fetchRecordWithID(self, _cmd, recordID, completionHandler);
    }
}

// CKDatabase performQuery hook
static void (*orig_CKDatabase_performQuery)(id self, SEL _cmd, id query, id zoneID, void (^completionHandler)(NSArray *, NSError *)) = NULL;
static void hook_CKDatabase_performQuery(id self, SEL _cmd, id query, id zoneID, void (^completionHandler)(NSArray *, NSError *)) {
    if (g_iCloudPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking CKDatabase performQuery");
        if (completionHandler) {
            NSError *error = [NSError errorWithDomain:@"CKErrorDomain" code:10 userInfo:@{NSLocalizedDescriptionKey: @"iCloud access denied"}];
            completionHandler(nil, error);
        }
        return;
    }
    if (orig_CKDatabase_performQuery) {
        orig_CKDatabase_performQuery(self, _cmd, query, zoneID, completionHandler);
    }
}

#pragma mark - Siri Privacy Protection Hooks

// INPreferences requestSiriAuthorization hook
static void (*orig_INPreferences_requestSiriAuthorization)(id self, SEL _cmd, void (^handler)(NSInteger)) = NULL;
static void hook_INPreferences_requestSiriAuthorization(id self, SEL _cmd, void (^handler)(NSInteger)) {
    if (g_siriPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking Siri authorization request");
        if (handler) {
            // INSiriAuthorizationStatusDenied = 2
            handler(2);
        }
        return;
    }
    if (orig_INPreferences_requestSiriAuthorization) {
        orig_INPreferences_requestSiriAuthorization(self, _cmd, handler);
    }
}

// INPreferences siriAuthorizationStatus hook
static NSInteger (*orig_INPreferences_siriAuthorizationStatus)(id self, SEL _cmd) = NULL;
static NSInteger hook_INPreferences_siriAuthorizationStatus(id self, SEL _cmd) {
    if (g_siriPrivacyProtectionEnabled) {
        NSLog(@"[LC] Returning denied Siri authorization status");
        // INSiriAuthorizationStatusDenied = 2
        return 2;
    }
    if (orig_INPreferences_siriAuthorizationStatus) {
        return orig_INPreferences_siriAuthorizationStatus(self, _cmd);
    }
    return 0; // INSiriAuthorizationStatusNotDetermined
}

// INVocabulary sharedVocabulary hook
static id (*orig_INVocabulary_sharedVocabulary)(id self, SEL _cmd) = NULL;
static id hook_INVocabulary_sharedVocabulary(id self, SEL _cmd) {
    if (g_siriPrivacyProtectionEnabled) {
        NSLog(@"[LC] Blocking INVocabulary sharedVocabulary");
        return nil;
    }
    if (orig_INVocabulary_sharedVocabulary) {
        return orig_INVocabulary_sharedVocabulary(self, _cmd);
    }
    return nil;
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
            // iOS 26.x - iPhone 17 Series
            @"iPhone 17 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone17ProMax],
            @"iPhone 17 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone17Pro],
            @"iPhone 17": [NSValue valueWithPointer:&kDeviceProfileiPhone17],
            @"iPhone 17 Air": [NSValue valueWithPointer:&kDeviceProfileiPhone17Air],
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
        // iOS 26.x - iPhone 17 Series
        @"iPhone 17 Pro Max": @{
            @"model": @"iPhone18,2",
            @"memory": @"12 GB",
            @"version": @"26.0",
            @"chip": @"A19 Pro"
        },
        @"iPhone 17 Pro": @{
            @"model": @"iPhone18,1",
            @"memory": @"12 GB",
            @"version": @"26.0",
            @"chip": @"A19 Pro"
        },
        @"iPhone 17": @{
            @"model": @"iPhone18,3",
            @"memory": @"8 GB",
            @"version": @"26.0",
            @"chip": @"A19"
        },
        @"iPhone 17 Air": @{
            @"model": @"iPhone18,4",
            @"memory": @"8 GB",
            @"version": @"26.0",
            @"chip": @"A19"
        },
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
    
    // Update boot time to match the new uptime
    struct timeval now;
    gettimeofday(&now, NULL);
    g_spoofedBootTime.tv_sec = now.tv_sec - (time_t)offset;
    g_spoofedBootTime.tv_usec = arc4random_uniform(1000000);
    g_bootTimeSpoofingEnabled = YES;
    
    NSLog(@"[LC] Set uptime offset: %.0f seconds (boot time: %ld)", offset, (long)g_spoofedBootTime.tv_sec);
}

void LCRandomizeUptime(void) {
    // Randomize uptime to be 1-14 days (increased range for better variability)
    NSTimeInterval offset = (arc4random_uniform(14) + 1) * 86400.0;
    offset += arc4random_uniform(86400); // Add random hours/minutes/seconds
    offset += arc4random_uniform(3600);  // Add extra random minutes
    offset += arc4random_uniform(60);    // Add extra random seconds
    LCSetUptimeOffset(offset);
}

void LCSetSpoofedBootTime(time_t bootTimestamp) {
    g_spoofedBootTime.tv_sec = bootTimestamp;
    g_spoofedBootTime.tv_usec = arc4random_uniform(1000000);
    g_bootTimeSpoofingEnabled = YES;
    
    // Calculate and update uptime offset to match
    struct timeval now;
    gettimeofday(&now, NULL);
    g_uptimeOffset = (NSTimeInterval)(now.tv_sec - bootTimestamp);
    
    // Update mach time offset
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    g_machTimeOffset = (uint64_t)(g_uptimeOffset * 1e9) * timebase.denom / timebase.numer;
    
    NSLog(@"[LC] Set spoofed boot time: %ld (uptime: %.0f seconds)", (long)bootTimestamp, g_uptimeOffset);
}

time_t LCGetSpoofedBootTime(void) {
    if (g_bootTimeSpoofingEnabled) {
        return g_spoofedBootTime.tv_sec;
    }
    // Return current boot time if not spoofing
    struct timeval boottime;
    size_t len = sizeof(boottime);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (sysctl(mib, 2, &boottime, &len, NULL, 0) == 0) {
        return boottime.tv_sec;
    }
    return 0;
}

NSTimeInterval LCGetSpoofedUptime(void) {
    if (g_uptimeOffset > 0) {
        struct timeval now;
        gettimeofday(&now, NULL);
        return (NSTimeInterval)(now.tv_sec - g_spoofedBootTime.tv_sec);
    }
    return [[NSProcessInfo processInfo] systemUptime];
}

#pragma mark - Storage Spoofing API

void LCSetStorageSpoofingEnabled(BOOL enabled) {
    g_storageSpoofingEnabled = enabled;
    NSLog(@"[LC] Storage spoofing %@", enabled ? @"enabled" : @"disabled");
}

BOOL LCIsStorageSpoofingEnabled(void) {
    return g_storageSpoofingEnabled;
}

void LCSetSpoofedStorageCapacity(NSString *capacityGB) {
    g_spoofedStorageCapacityGB = [capacityGB copy];
    
    // Also update the byte values
    if (capacityGB) {
        double totalGB = [capacityGB doubleValue];
        g_spoofedStorageTotal = (uint64_t)(totalGB * LC_BYTES_PER_GB);
    } else {
        g_spoofedStorageTotal = 0;
    }
    
    NSLog(@"[LC] Set spoofed storage capacity: %@ GB (%llu bytes)", capacityGB ?: @"disabled", g_spoofedStorageTotal);
}

void LCSetSpoofedStorageFree(NSString *freeGB) {
    g_spoofedStorageFreeGB = [freeGB copy];
    
    // Also update the byte values
    if (freeGB) {
        double free = [freeGB doubleValue];
        g_spoofedStorageFree = (uint64_t)(free * LC_BYTES_PER_GB);
    } else {
        g_spoofedStorageFree = 0;
    }
    
    NSLog(@"[LC] Set spoofed free storage: %@ GB (%llu bytes)", freeGB ?: @"disabled", g_spoofedStorageFree);
}

void LCSetSpoofedStorageBytes(uint64_t totalBytes, uint64_t freeBytes) {
    g_spoofedStorageTotal = totalBytes;
    g_spoofedStorageFree = freeBytes;
    
    // Also update the GB string values
    if (totalBytes > 0) {
        double totalGB = (double)totalBytes / LC_BYTES_PER_GB;
        g_spoofedStorageCapacityGB = [NSString stringWithFormat:@"%.0f", totalGB];
    } else {
        g_spoofedStorageCapacityGB = nil;
    }
    
    if (freeBytes > 0) {
        double freeGB = (double)freeBytes / LC_BYTES_PER_GB;
        g_spoofedStorageFreeGB = [NSString stringWithFormat:@"%.1f", freeGB];
    } else {
        g_spoofedStorageFreeGB = nil;
    }
    
    NSLog(@"[LC] Set spoofed storage: %llu total / %llu free bytes", totalBytes, freeBytes);
}

NSDictionary *LCGenerateStorageForCapacity(NSString *capacityGB) {
    double totalGB = [capacityGB doubleValue];
    double freePercent;
    
    // Calculate realistic free space based on capacity
    if (totalGB <= 64) {
        // 64GB devices typically have less free space (15-30%)
        freePercent = (arc4random_uniform(15) + 15) / 100.0;
    } else if (totalGB <= 128) {
        // 128GB devices (25-40%)
        freePercent = (arc4random_uniform(15) + 25) / 100.0;
    } else if (totalGB <= 256) {
        // 256GB devices (35-55%)
        freePercent = (arc4random_uniform(20) + 35) / 100.0;
    } else {
        // 512GB+ devices (45-65%)
        freePercent = (arc4random_uniform(20) + 45) / 100.0;
    }
    
    double freeGB = totalGB * freePercent;
    // Add some variability to the decimal points
    freeGB += (arc4random_uniform(10) / 10.0);
    // Round to one decimal place
    freeGB = round(freeGB * 10) / 10;
    
    return @{
        @"TotalStorage": capacityGB,
        @"FreeStorage": [NSString stringWithFormat:@"%.1f", freeGB],
        @"TotalBytes": @((uint64_t)(totalGB * LC_BYTES_PER_GB)),
        @"FreeBytes": @((uint64_t)(freeGB * LC_BYTES_PER_GB)),
        @"FilesystemType": @"APFS"
    };
}

NSString *LCRandomizeStorageCapacity(void) {
    // Weighted distribution based on common iPhone storage configurations
    int randomValue = arc4random_uniform(100);
    NSString *capacity;
    
    if (randomValue < 20) {
        capacity = @"64";   // 20% - 64GB
    } else if (randomValue < 55) {
        capacity = @"128";  // 35% - 128GB (most common)
    } else if (randomValue < 80) {
        capacity = @"256";  // 25% - 256GB
    } else if (randomValue < 95) {
        capacity = @"512";  // 15% - 512GB
    } else {
        capacity = @"1024"; // 5% - 1TB
    }
    
    return capacity;
}

void LCRandomizeStorage(void) {
    NSString *capacity = LCRandomizeStorageCapacity();
    NSDictionary *storage = LCGenerateStorageForCapacity(capacity);
    
    LCSetSpoofedStorageCapacity(storage[@"TotalStorage"]);
    LCSetSpoofedStorageFree(storage[@"FreeStorage"]);
    g_storageSpoofingEnabled = YES;
    
    NSLog(@"[LC] Randomized storage: %@ GB total, %@ GB free", 
          storage[@"TotalStorage"], storage[@"FreeStorage"]);
}

uint64_t LCGetSpoofedStorageTotal(void) {
    return g_spoofedStorageTotal;
}

uint64_t LCGetSpoofedStorageFree(void) {
    return g_spoofedStorageFree;
}

NSString *LCGetSpoofedStorageCapacityGB(void) {
    return g_spoofedStorageCapacityGB;
}

NSString *LCGetSpoofedStorageFreeGB(void) {
    return g_spoofedStorageFreeGB;
}

// Legacy function - kept for compatibility
void LCSetSpoofedDiskSpace(uint64_t freeSpace, uint64_t totalSpace) {
    LCSetSpoofedStorageBytes(totalSpace, freeSpace);
    g_storageSpoofingEnabled = YES;
}

void LCRandomizeBattery(void) {
    // Random battery level between 15% and 98% (wider range)
    float level = 0.15f + (arc4random_uniform(84) / 100.0f);
    g_spoofedBatteryLevel = level;
    // Random state: 1=Unknown, 2=Unplugged, 3=Charging, 4=Full
    // Weighted: 70% Unplugged, 25% Charging, 5% Full
    int stateRoll = arc4random_uniform(100);
    if (stateRoll < 70) {
        g_spoofedBatteryState = 2; // Unplugged
    } else if (stateRoll < 95) {
        g_spoofedBatteryState = 3; // Charging
    } else {
        g_spoofedBatteryState = 4; // Full
    }
    NSLog(@"[LC] Randomized battery: %.0f%% (State: %ld)", level * 100, (long)g_spoofedBatteryState);
}

void LCRandomizeBrightness(void) {
    // Random brightness between 20% and 90% (wider range)
    float brightness = 0.20f + (arc4random_uniform(71) / 100.0f);
    g_spoofedBrightness = brightness;
    NSLog(@"[LC] Randomized brightness: %.0f%%", brightness * 100);
}

void LCInitializeFingerprintProtection(void) {
    // Initialize all fingerprint spoofing with random but realistic values
    LCRandomizeUptime();
    LCRandomizeBattery();
    LCRandomizeBrightness();
    LCRandomizeStorage();
    g_spoofedThermalState = arc4random_uniform(2); // Nominal or Fair
    g_spoofLowPowerMode = YES;
    g_lowPowerModeValue = (arc4random_uniform(100) < 20); // 20% chance of low power mode
    // Enable User-Agent spoofing by default
    g_userAgentSpoofingEnabled = YES;
    // Enable canvas fingerprint protection by default
    g_canvasFingerprintProtectionEnabled = YES;
    NSLog(@"[LC] Fingerprint protection initialized with randomized values (Canvas protection: ON)");
}

#pragma mark - Canvas Fingerprint Protection API

void LCSetCanvasFingerprintProtectionEnabled(BOOL enabled) {
    g_canvasFingerprintProtectionEnabled = enabled;
    NSLog(@"[LC] Canvas fingerprint protection %@", enabled ? @"enabled" : @"disabled");
}

BOOL LCIsCanvasFingerprintProtectionEnabled(void) {
    return g_canvasFingerprintProtectionEnabled;
}

#pragma mark - iCloud/CloudKit Privacy Protection API

void LCSetICloudPrivacyProtectionEnabled(BOOL enabled) {
    g_iCloudPrivacyProtectionEnabled = enabled;
    NSLog(@"[LC] iCloud/CloudKit privacy protection %@", enabled ? @"enabled" : @"disabled");
}

BOOL LCIsICloudPrivacyProtectionEnabled(void) {
    return g_iCloudPrivacyProtectionEnabled;
}

#pragma mark - Siri Privacy Protection API

void LCSetSiriPrivacyProtectionEnabled(BOOL enabled) {
    g_siriPrivacyProtectionEnabled = enabled;
    NSLog(@"[LC] Siri privacy protection %@", enabled ? @"enabled" : @"disabled");
}

BOOL LCIsSiriPrivacyProtectionEnabled(void) {
    return g_siriPrivacyProtectionEnabled;
}

#pragma mark - Device Name and Identifier API

void LCSetSpoofedDeviceName(NSString *deviceName) {
    g_customDeviceName = [deviceName copy];
    NSLog(@"[LC] Set spoofed device name: %@", deviceName ?: @"(auto)");
}

NSString *LCGetSpoofedDeviceName(void) {
    return g_customDeviceName;
}

void LCSetSpoofedCarrierName(NSString *carrierName) {
    g_customCarrierName = [carrierName copy];
    NSLog(@"[LC] Set spoofed carrier name: %@", carrierName ?: @"(auto)");
}

NSString *LCGetSpoofedCarrierName(void) {
    return g_customCarrierName;
}

void LCSetSpoofedVendorID(NSString *vendorID) {
    g_spoofedVendorID = [vendorID copy];
    NSLog(@"[LC] Set spoofed vendor ID (IDFV): %@", vendorID ?: @"(auto)");
}

NSString *LCGetSpoofedVendorID(void) {
    return g_spoofedVendorID;
}

void LCSetSpoofedAdvertisingID(NSString *advertisingID) {
    g_spoofedAdvertisingID = [advertisingID copy];
    NSLog(@"[LC] Set spoofed advertising ID (IDFA): %@", advertisingID ?: @"(zeroed)");
}

NSString *LCGetSpoofedAdvertisingID(void) {
    return g_spoofedAdvertisingID;
}

void LCSetSpoofedAdTrackingEnabled(BOOL enabled) {
    g_spoofedAdTrackingEnabled = enabled;
    NSLog(@"[LC] Set ad tracking enabled: %@", enabled ? @"YES" : @"NO");
}

BOOL LCGetSpoofedAdTrackingEnabled(void) {
    return g_spoofedAdTrackingEnabled;
}

void LCSetSpoofedInstallationID(NSString *installationID) {
    g_spoofedInstallationID = [installationID copy];
    NSLog(@"[LC] Set spoofed installation ID: %@", installationID ?: @"(auto)");
}

NSString *LCGetSpoofedInstallationID(void) {
    return g_spoofedInstallationID;
}

void LCSetSpoofedMACAddress(NSString *macAddress) {
    g_spoofedMACAddress = [macAddress copy];
    NSLog(@"[LC] Set spoofed MAC address: %@", macAddress ?: @"(auto)");
}

NSString *LCGetSpoofedMACAddress(void) {
    return g_spoofedMACAddress;
}

#pragma mark - Battery API

void LCSetSpoofedBatteryLevel(float level) {
    g_spoofedBatteryLevel = level;
    NSLog(@"[LC] Set spoofed battery level: %.0f%%", level * 100);
}

float LCGetSpoofedBatteryLevel(void) {
    return g_spoofedBatteryLevel;
}

void LCSetSpoofedBatteryState(NSInteger state) {
    g_spoofedBatteryState = state;
    NSLog(@"[LC] Set spoofed battery state: %ld", (long)state);
}

NSInteger LCGetSpoofedBatteryState(void) {
    return g_spoofedBatteryState;
}

#pragma mark - Screen API

void LCSetSpoofedScreenScale(CGFloat scale) {
    // Screen scale is part of profile, this would override it
    // Currently not implemented as profile defines screen characteristics
    NSLog(@"[LC] Screen scale override not implemented (use device profile instead)");
}

void LCSetSpoofedBrightness(float brightness) {
    g_spoofedBrightness = brightness;
    NSLog(@"[LC] Set spoofed brightness: %.0f%%", brightness * 100);
}

float LCGetSpoofedBrightness(void) {
    return g_spoofedBrightness;
}

#pragma mark - Random UUID/MAC Generation

NSString *LCGenerateRandomUUID(void) {
    return [[NSUUID UUID] UUIDString];
}

NSString *LCGenerateRandomMACAddress(void) {
    // Generate a random locally-administered MAC address (bit 1 of first byte set)
    uint8_t mac[6];
    for (int i = 0; i < 6; i++) {
        mac[i] = arc4random_uniform(256);
    }
    // Set locally administered bit and clear multicast bit
    mac[0] = (mac[0] | 0x02) & 0xFE;
    
    return [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",
            mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]];
}

NSString *LCGenerateRandomInstallationID(int length) {
    static const char charset[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    for (int i = 0; i < length; i++) {
        [result appendFormat:@"%c", charset[arc4random_uniform((uint32_t)strlen(charset))]];
    }
    return result;
}

#pragma mark - User-Agent Spoofing API

void LCSetSpoofedUserAgent(NSString *userAgent) {
    g_customUserAgent = [userAgent copy];
    g_userAgentSpoofingEnabled = (userAgent != nil);
    NSLog(@"[LC] Set custom User-Agent: %@", userAgent ?: @"(disabled)");
}

void LCSetUserAgentSpoofingEnabled(BOOL enabled) {
    g_userAgentSpoofingEnabled = enabled;
    NSLog(@"[LC] User-Agent spoofing %@", enabled ? @"enabled" : @"disabled");
}

BOOL LCIsUserAgentSpoofingEnabled(void) {
    return g_userAgentSpoofingEnabled;
}

NSString *LCGetCurrentUserAgent(void) {
    return getSpoofedUserAgent();
}

void LCUpdateUserAgentForProfile(void) {
    // Auto-update User-Agent based on current device profile
    if (g_customUserAgent) {
        // Don't override if custom UA is already set
        return;
    }
    NSString *autoUA = getSpoofedUserAgent();
    if (autoUA) {
        NSLog(@"[LC] Auto-generated User-Agent for profile: %@", autoUA);
    }
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
        {"statfs", (void *)hook_statfs, (void **)&orig_statfs},
        {"statfs64", (void *)hook_statfs64, (void **)&orig_statfs64},
    };
    
    int result = rebind_symbols(rebindings, sizeof(rebindings)/sizeof(rebindings[0]));
    if (result == 0) {
        NSLog(@"[LC] Hooked C functions via fishhook (uname, sysctl*, mach_absolute_time, clock_gettime, host_statistics*, statfs*)");
    } else {
        NSLog(@"[LC] Warning: fishhook rebind_symbols failed with code %d", result);
    }
    
    // Hook UIDevice methods using method swizzling (works without JIT)
    Class UIDeviceClass = objc_getClass("UIDevice");
    if (UIDeviceClass) {
        Method modelMethod = class_getInstanceMethod(UIDeviceClass, @selector(model));
        Method systemVersionMethod = class_getInstanceMethod(UIDeviceClass, @selector(systemVersion));
        Method systemNameMethod = class_getInstanceMethod(UIDeviceClass, @selector(systemName));
        Method nameMethod = class_getInstanceMethod(UIDeviceClass, @selector(name));
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
        if (nameMethod) {
            orig_UIDevice_name = (NSString* (*)(id, SEL))method_getImplementation(nameMethod);
            method_setImplementation(nameMethod, (IMP)hook_UIDevice_name);
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
        NSLog(@"[LC] Hooked UIDevice methods (model, systemVersion, systemName, name, identifierForVendor, battery*)");
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
        Method isAdvertisingTrackingEnabledMethod = class_getInstanceMethod(ASIdentifierManagerClass, @selector(isAdvertisingTrackingEnabled));
        
        if (advertisingIdentifierMethod) {
            orig_ASIdentifierManager_advertisingIdentifier = (NSUUID* (*)(id, SEL))method_getImplementation(advertisingIdentifierMethod);
            method_setImplementation(advertisingIdentifierMethod, (IMP)hook_ASIdentifierManager_advertisingIdentifier);
        }
        if (isAdvertisingTrackingEnabledMethod) {
            orig_ASIdentifierManager_isAdvertisingTrackingEnabled = (BOOL (*)(id, SEL))method_getImplementation(isAdvertisingTrackingEnabledMethod);
            method_setImplementation(isAdvertisingTrackingEnabledMethod, (IMP)hook_ASIdentifierManager_isAdvertisingTrackingEnabled);
        }
        NSLog(@"[LC] Hooked ASIdentifierManager methods (advertisingIdentifier, isAdvertisingTrackingEnabled)");
    }
    
    // Hook NSFileManager for storage spoofing
    Class NSFileManagerClass = objc_getClass("NSFileManager");
    if (NSFileManagerClass) {
        Method attributesMethod = class_getInstanceMethod(NSFileManagerClass, @selector(attributesOfFileSystemForPath:error:));
        
        if (attributesMethod) {
            orig_NSFileManager_attributesOfFileSystemForPath = (NSDictionary* (*)(id, SEL, NSString *, NSError **))method_getImplementation(attributesMethod);
            method_setImplementation(attributesMethod, (IMP)hook_NSFileManager_attributesOfFileSystemForPath);
        }
        NSLog(@"[LC] Hooked NSFileManager methods (attributesOfFileSystemForPath:error:)");
    }
    
    // Hook WKWebView for User-Agent spoofing and canvas fingerprint protection
    Class WKWebViewClass = objc_getClass("WKWebView");
    if (WKWebViewClass) {
        Method customUserAgentMethod = class_getInstanceMethod(WKWebViewClass, @selector(customUserAgent));
        Method setCustomUserAgentMethod = class_getInstanceMethod(WKWebViewClass, @selector(setCustomUserAgent:));
        
        if (customUserAgentMethod) {
            orig_WKWebView_customUserAgent = (NSString* (*)(id, SEL))method_getImplementation(customUserAgentMethod);
            method_setImplementation(customUserAgentMethod, (IMP)hook_WKWebView_customUserAgent);
        }
        if (setCustomUserAgentMethod) {
            orig_WKWebView_setCustomUserAgent = (void (*)(id, SEL, NSString *))method_getImplementation(setCustomUserAgentMethod);
            method_setImplementation(setCustomUserAgentMethod, (IMP)hook_WKWebView_setCustomUserAgent);
        }
        
        // Hook initWithFrame:configuration: for canvas fingerprint protection injection
        Method initMethod = class_getInstanceMethod(WKWebViewClass, @selector(initWithFrame:configuration:));
        if (initMethod) {
            orig_WKWebView_initWithFrame_configuration = (id (*)(id, SEL, CGRect, WKWebViewConfiguration *))method_getImplementation(initMethod);
            method_setImplementation(initMethod, (IMP)hook_WKWebView_initWithFrame_configuration);
        }
        
        NSLog(@"[LC] Hooked WKWebView methods (customUserAgent, setCustomUserAgent:, initWithFrame:configuration:)");
    }
    
    // Hook WKWebViewConfiguration for applicationNameForUserAgent
    Class WKWebViewConfigurationClass = objc_getClass("WKWebViewConfiguration");
    if (WKWebViewConfigurationClass) {
        Method appNameMethod = class_getInstanceMethod(WKWebViewConfigurationClass, @selector(applicationNameForUserAgent));
        
        if (appNameMethod) {
            orig_WKWebViewConfiguration_applicationNameForUserAgent = (NSString* (*)(id, SEL))method_getImplementation(appNameMethod);
            method_setImplementation(appNameMethod, (IMP)hook_WKWebViewConfiguration_applicationNameForUserAgent);
        }
        NSLog(@"[LC] Hooked WKWebViewConfiguration methods (applicationNameForUserAgent)");
    }
    
    // Hook NSMutableURLRequest for User-Agent header injection
    Class NSMutableURLRequestClass = objc_getClass("NSMutableURLRequest");
    if (NSMutableURLRequestClass) {
        Method setValueMethod = class_getInstanceMethod(NSMutableURLRequestClass, @selector(setValue:forHTTPHeaderField:));
        
        if (setValueMethod) {
            orig_NSMutableURLRequest_setValue_forHTTPHeaderField = (void (*)(id, SEL, NSString *, NSString *))method_getImplementation(setValueMethod);
            method_setImplementation(setValueMethod, (IMP)hook_NSMutableURLRequest_setValue_forHTTPHeaderField);
        }
        NSLog(@"[LC] Hooked NSMutableURLRequest methods (setValue:forHTTPHeaderField:)");
    }
    
    // Hook NSFileManager for ubiquityIdentityToken (iCloud fingerprint protection)
    Class NSFileManagerClass2 = objc_getClass("NSFileManager");
    if (NSFileManagerClass2) {
        Method ubiquityTokenMethod = class_getInstanceMethod(NSFileManagerClass2, @selector(ubiquityIdentityToken));
        if (ubiquityTokenMethod) {
            orig_NSFileManager_ubiquityIdentityToken = (id (*)(id, SEL))method_getImplementation(ubiquityTokenMethod);
            method_setImplementation(ubiquityTokenMethod, (IMP)hook_NSFileManager_ubiquityIdentityToken);
        }
        NSLog(@"[LC] Hooked NSFileManager methods (ubiquityIdentityToken)");
    }
    
    // Hook CKContainer for iCloud/CloudKit privacy protection
    Class CKContainerClass = objc_getClass("CKContainer");
    if (CKContainerClass) {
        Method accountStatusMethod = class_getInstanceMethod(CKContainerClass, @selector(accountStatusWithCompletionHandler:));
        Method defaultContainerMethod = class_getClassMethod(CKContainerClass, @selector(defaultContainer));
        Method containerWithIdMethod = class_getClassMethod(CKContainerClass, @selector(containerWithIdentifier:));
        Method fetchUserRecordMethod = class_getInstanceMethod(CKContainerClass, @selector(fetchUserRecordIDWithCompletionHandler:));
        Method requestPermissionMethod = class_getInstanceMethod(CKContainerClass, @selector(requestApplicationPermission:completionHandler:));
        
        if (accountStatusMethod) {
            orig_CKContainer_accountStatusWithCompletionHandler = (void (*)(id, SEL, void (^)(NSInteger, NSError *)))method_getImplementation(accountStatusMethod);
            method_setImplementation(accountStatusMethod, (IMP)hook_CKContainer_accountStatusWithCompletionHandler);
        }
        if (defaultContainerMethod) {
            orig_CKContainer_defaultContainer = (id (*)(id, SEL))method_getImplementation(defaultContainerMethod);
            method_setImplementation(defaultContainerMethod, (IMP)hook_CKContainer_defaultContainer);
        }
        if (containerWithIdMethod) {
            orig_CKContainer_containerWithIdentifier = (id (*)(id, SEL, NSString *))method_getImplementation(containerWithIdMethod);
            method_setImplementation(containerWithIdMethod, (IMP)hook_CKContainer_containerWithIdentifier);
        }
        if (fetchUserRecordMethod) {
            orig_CKContainer_fetchUserRecordIDWithCompletionHandler = (void (*)(id, SEL, void (^)(id, NSError *)))method_getImplementation(fetchUserRecordMethod);
            method_setImplementation(fetchUserRecordMethod, (IMP)hook_CKContainer_fetchUserRecordIDWithCompletionHandler);
        }
        if (requestPermissionMethod) {
            orig_CKContainer_requestApplicationPermission = (void (*)(id, SEL, NSUInteger, void (^)(NSInteger, NSError *)))method_getImplementation(requestPermissionMethod);
            method_setImplementation(requestPermissionMethod, (IMP)hook_CKContainer_requestApplicationPermission);
        }
        NSLog(@"[LC] Hooked CKContainer methods (iCloud/CloudKit privacy protection)");
    }
    
    // Hook CKDatabase for CloudKit query protection
    Class CKDatabaseClass = objc_getClass("CKDatabase");
    if (CKDatabaseClass) {
        Method fetchRecordMethod = class_getInstanceMethod(CKDatabaseClass, @selector(fetchRecordWithID:completionHandler:));
        Method performQueryMethod = class_getInstanceMethod(CKDatabaseClass, @selector(performQuery:inZoneWithID:completionHandler:));
        
        if (fetchRecordMethod) {
            orig_CKDatabase_fetchRecordWithID = (void (*)(id, SEL, id, void (^)(id, NSError *)))method_getImplementation(fetchRecordMethod);
            method_setImplementation(fetchRecordMethod, (IMP)hook_CKDatabase_fetchRecordWithID);
        }
        if (performQueryMethod) {
            orig_CKDatabase_performQuery = (void (*)(id, SEL, id, id, void (^)(NSArray *, NSError *)))method_getImplementation(performQueryMethod);
            method_setImplementation(performQueryMethod, (IMP)hook_CKDatabase_performQuery);
        }
        NSLog(@"[LC] Hooked CKDatabase methods (CloudKit query protection)");
    }
    
    // Hook INPreferences for Siri privacy protection
    Class INPreferencesClass = objc_getClass("INPreferences");
    if (INPreferencesClass) {
        Method requestAuthMethod = class_getClassMethod(INPreferencesClass, @selector(requestSiriAuthorization:));
        Method authStatusMethod = class_getClassMethod(INPreferencesClass, @selector(siriAuthorizationStatus));
        
        if (requestAuthMethod) {
            orig_INPreferences_requestSiriAuthorization = (void (*)(id, SEL, void (^)(NSInteger)))method_getImplementation(requestAuthMethod);
            method_setImplementation(requestAuthMethod, (IMP)hook_INPreferences_requestSiriAuthorization);
        }
        if (authStatusMethod) {
            orig_INPreferences_siriAuthorizationStatus = (NSInteger (*)(id, SEL))method_getImplementation(authStatusMethod);
            method_setImplementation(authStatusMethod, (IMP)hook_INPreferences_siriAuthorizationStatus);
        }
        NSLog(@"[LC] Hooked INPreferences methods (Siri privacy protection)");
    }
    
    // Hook INVocabulary for Siri vocabulary protection
    Class INVocabularyClass = objc_getClass("INVocabulary");
    if (INVocabularyClass) {
        Method sharedVocabMethod = class_getClassMethod(INVocabularyClass, @selector(sharedVocabulary));
        
        if (sharedVocabMethod) {
            orig_INVocabulary_sharedVocabulary = (id (*)(id, SEL))method_getImplementation(sharedVocabMethod);
            method_setImplementation(sharedVocabMethod, (IMP)hook_INVocabulary_sharedVocabulary);
        }
        NSLog(@"[LC] Hooked INVocabulary methods (Siri vocabulary protection)");
    }
    
    // Initialize fingerprint protection with randomized values
    LCInitializeFingerprintProtection();
    
    NSLog(@"[LC] Comprehensive device spoofing hooks initialized");
}