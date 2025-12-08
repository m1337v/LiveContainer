//
//  DeviceSpoofing.m
//  LiveContainer
//
//  Device spoofing implementation based on Ghost/Nomix patterns
//

#import "DeviceSpoofing.h"
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "../../litehook/src/litehook.h"

#pragma mark - Device Profiles

const LCDeviceProfile kDeviceProfileiPhone15ProMax = {
    .modelIdentifier = "iPhone16,2",
    .hardwareModel = "D84AP",
    .marketingName = "iPhone 15 Pro Max",
    .systemVersion = "17.4",
    .buildVersion = "21E219",
    .kernelVersion = "Darwin Kernel Version 23.4.0: Fri Mar 15 00:10:42 PDT 2024; root:xnu-10063.101.17~1/RELEASE_ARM64_T8130",
    .physicalMemory = 8589934592ULL, // 8GB
    .cpuCoreCount = 6
};

const LCDeviceProfile kDeviceProfileiPhone15Pro = {
    .modelIdentifier = "iPhone16,1",
    .hardwareModel = "D83AP",
    .marketingName = "iPhone 15 Pro",
    .systemVersion = "17.4",
    .buildVersion = "21E219",
    .kernelVersion = "Darwin Kernel Version 23.4.0: Fri Mar 15 00:10:42 PDT 2024; root:xnu-10063.101.17~1/RELEASE_ARM64_T8130",
    .physicalMemory = 8589934592ULL,
    .cpuCoreCount = 6
};

const LCDeviceProfile kDeviceProfileiPhone14ProMax = {
    .modelIdentifier = "iPhone15,3",
    .hardwareModel = "D74AP",
    .marketingName = "iPhone 14 Pro Max",
    .systemVersion = "17.4",
    .buildVersion = "21E219",
    .kernelVersion = "Darwin Kernel Version 23.4.0: Fri Mar 15 00:10:42 PDT 2024; root:xnu-10063.101.17~1/RELEASE_ARM64_T8120",
    .physicalMemory = 6442450944ULL, // 6GB
    .cpuCoreCount = 6
};

const LCDeviceProfile kDeviceProfileiPhone14Pro = {
    .modelIdentifier = "iPhone15,2",
    .hardwareModel = "D73AP",
    .marketingName = "iPhone 14 Pro",
    .systemVersion = "17.4",
    .buildVersion = "21E219",
    .kernelVersion = "Darwin Kernel Version 23.4.0: Fri Mar 15 00:10:42 PDT 2024; root:xnu-10063.101.17~1/RELEASE_ARM64_T8120",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6
};

const LCDeviceProfile kDeviceProfileiPhone13ProMax = {
    .modelIdentifier = "iPhone14,3",
    .hardwareModel = "D64AP",
    .marketingName = "iPhone 13 Pro Max",
    .systemVersion = "17.4",
    .buildVersion = "21E219",
    .kernelVersion = "Darwin Kernel Version 23.4.0: Fri Mar 15 00:10:42 PDT 2024; root:xnu-10063.101.17~1/RELEASE_ARM64_T8110",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6
};

const LCDeviceProfile kDeviceProfileiPhone13Pro = {
    .modelIdentifier = "iPhone14,2",
    .hardwareModel = "D63AP",
    .marketingName = "iPhone 13 Pro",
    .systemVersion = "17.4",
    .buildVersion = "21E219",
    .kernelVersion = "Darwin Kernel Version 23.4.0: Fri Mar 15 00:10:42 PDT 2024; root:xnu-10063.101.17~1/RELEASE_ARM64_T8110",
    .physicalMemory = 6442450944ULL,
    .cpuCoreCount = 6
};

const LCDeviceProfile kDeviceProfileiPadPro12_9_6th = {
    .modelIdentifier = "iPad14,5",
    .hardwareModel = "J620AP",
    .marketingName = "iPad Pro 12.9-inch (6th generation)",
    .systemVersion = "17.4",
    .buildVersion = "21E219",
    .kernelVersion = "Darwin Kernel Version 23.4.0: Fri Mar 15 00:10:42 PDT 2024; root:xnu-10063.101.17~1/RELEASE_ARM64_T8112",
    .physicalMemory = 17179869184ULL, // 16GB
    .cpuCoreCount = 8
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

#pragma mark - Original Function Pointers

static int (*orig_uname)(struct utsname *name) = NULL;
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;

// UIDevice method IMPs
static NSString* (*orig_UIDevice_model)(id self, SEL _cmd) = NULL;
static NSString* (*orig_UIDevice_systemVersion)(id self, SEL _cmd) = NULL;
static NSString* (*orig_UIDevice_systemName)(id self, SEL _cmd) = NULL;
static NSString* (*orig_UIDevice_name)(id self, SEL _cmd) = NULL;

// NSProcessInfo method IMPs
static unsigned long long (*orig_NSProcessInfo_physicalMemory)(id self, SEL _cmd) = NULL;
static NSUInteger (*orig_NSProcessInfo_processorCount)(id self, SEL _cmd) = NULL;
static NSUInteger (*orig_NSProcessInfo_activeProcessorCount)(id self, SEL _cmd) = NULL;
static NSOperatingSystemVersion (*orig_NSProcessInfo_operatingSystemVersion)(id self, SEL _cmd) = NULL;

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

#pragma mark - uname Hook

static int hook_uname(struct utsname *name) {
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
        // release field contains just the version number
        strlcpy(name->release, "23.4.0", sizeof(name->release));
    }
    
    return result;
}

#pragma mark - sysctlbyname Hook

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int result = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    
    if (result != 0 || !g_deviceSpoofingEnabled || !name || !oldp || !oldlenp || *oldlenp == 0) {
        return result;
    }
    
    // hw.machine - Device model identifier (e.g., "iPhone16,2")
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
    // hw.model - Hardware model (e.g., "D84AP")
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
    // kern.osversion - Build version (e.g., "21E219")
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
    // kern.osrelease - Kernel release version
    else if (strcmp(name, "kern.osrelease") == 0) {
        const char *release = "23.4.0"; // Corresponds to iOS 17.4
        size_t len = strlen(release) + 1;
        if (*oldlenp >= len) {
            memset(oldp, 0, *oldlenp);
            strlcpy(oldp, release, *oldlenp);
            *oldlenp = len;
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
    
    return result;
}

#pragma mark - sysctl Hook

static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
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
            const char *release = "23.4.0";
            size_t len = strlen(release) + 1;
            if (*oldlenp >= len) {
                memset(oldp, 0, *oldlenp);
                strlcpy(oldp, release, *oldlenp);
                *oldlenp = len;
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
    }
    
    return result;
}

#pragma mark - UIDevice Hooks

static NSString* hook_UIDevice_model(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled || !g_currentProfile) {
        return orig_UIDevice_model(self, _cmd);
    }
    
    // Return marketing name (e.g., "iPhone" or "iPad")
    NSString *model = @(g_currentProfile->marketingName);
    if ([model hasPrefix:@"iPhone"]) {
        return @"iPhone";
    } else if ([model hasPrefix:@"iPad"]) {
        return @"iPad";
    }
    return orig_UIDevice_model(self, _cmd);
}

static NSString* hook_UIDevice_systemVersion(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        return orig_UIDevice_systemVersion(self, _cmd);
    }
    
    const char *version = getSpoofedSystemVersion();
    if (version) {
        return @(version);
    }
    return orig_UIDevice_systemVersion(self, _cmd);
}

static NSString* hook_UIDevice_systemName(id self, SEL _cmd) {
    // Always return the system name based on device type
    if (!g_deviceSpoofingEnabled || !g_currentProfile) {
        return orig_UIDevice_systemName(self, _cmd);
    }
    
    NSString *model = @(g_currentProfile->modelIdentifier);
    if ([model hasPrefix:@"iPad"]) {
        return @"iPadOS";
    }
    return @"iOS";
}

#pragma mark - NSProcessInfo Hooks

static unsigned long long hook_NSProcessInfo_physicalMemory(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        return orig_NSProcessInfo_physicalMemory(self, _cmd);
    }
    
    uint64_t spoofedMemory = getSpoofedPhysicalMemory();
    if (spoofedMemory > 0) {
        return spoofedMemory;
    }
    return orig_NSProcessInfo_physicalMemory(self, _cmd);
}

static NSUInteger hook_NSProcessInfo_processorCount(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        return orig_NSProcessInfo_processorCount(self, _cmd);
    }
    
    uint32_t spoofedCores = getSpoofedCPUCoreCount();
    if (spoofedCores > 0) {
        return spoofedCores;
    }
    return orig_NSProcessInfo_processorCount(self, _cmd);
}

static NSUInteger hook_NSProcessInfo_activeProcessorCount(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        return orig_NSProcessInfo_activeProcessorCount(self, _cmd);
    }
    
    uint32_t spoofedCores = getSpoofedCPUCoreCount();
    if (spoofedCores > 0) {
        return spoofedCores;
    }
    return orig_NSProcessInfo_activeProcessorCount(self, _cmd);
}

static NSOperatingSystemVersion hook_NSProcessInfo_operatingSystemVersion(id self, SEL _cmd) {
    if (!g_deviceSpoofingEnabled) {
        return orig_NSProcessInfo_operatingSystemVersion(self, _cmd);
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
    return orig_NSProcessInfo_operatingSystemVersion(self, _cmd);
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
            @"iPhone 15 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone15ProMax],
            @"iPhone 15 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone15Pro],
            @"iPhone 14 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone14ProMax],
            @"iPhone 14 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone14Pro],
            @"iPhone 13 Pro Max": [NSValue valueWithPointer:&kDeviceProfileiPhone13ProMax],
            @"iPhone 13 Pro": [NSValue valueWithPointer:&kDeviceProfileiPhone13Pro],
            @"iPad Pro 12.9 (6th gen)": [NSValue valueWithPointer:&kDeviceProfileiPadPro12_9_6th],
        };
    });
    
    NSValue *profileValue = profileMap[profileName];
    if (profileValue) {
        g_currentProfile = [profileValue pointerValue];
        NSLog(@"[LC] Set device profile: %@ (%s)", profileName, g_currentProfile->modelIdentifier);
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
        @"iPhone 15 Pro Max": @{
            @"model": @"iPhone16,2",
            @"memory": @"8 GB",
            @"version": @"17.4"
        },
        @"iPhone 15 Pro": @{
            @"model": @"iPhone16,1",
            @"memory": @"8 GB",
            @"version": @"17.4"
        },
        @"iPhone 14 Pro Max": @{
            @"model": @"iPhone15,3",
            @"memory": @"6 GB",
            @"version": @"17.4"
        },
        @"iPhone 14 Pro": @{
            @"model": @"iPhone15,2",
            @"memory": @"6 GB",
            @"version": @"17.4"
        },
        @"iPhone 13 Pro Max": @{
            @"model": @"iPhone14,3",
            @"memory": @"6 GB",
            @"version": @"17.4"
        },
        @"iPhone 13 Pro": @{
            @"model": @"iPhone14,2",
            @"memory": @"6 GB",
            @"version": @"17.4"
        },
        @"iPad Pro 12.9 (6th gen)": @{
            @"model": @"iPad14,5",
            @"memory": @"16 GB",
            @"version": @"17.4"
        }
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

#pragma mark - Initialization

void DeviceSpoofingGuestHooksInit(void) {
    NSLog(@"[LC] Initializing device spoofing hooks...");
    
    // Hook system functions using litehook
    orig_uname = (int (*)(struct utsname *))dlsym(RTLD_DEFAULT, "uname");
    orig_sysctlbyname = (int (*)(const char *, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctlbyname");
    orig_sysctl = (int (*)(int *, u_int, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctl");
    
    if (orig_uname) {
        litehook_hook_function(orig_uname, hook_uname);
        NSLog(@"[LC] Hooked uname");
    }
    
    if (orig_sysctlbyname) {
        litehook_hook_function(orig_sysctlbyname, hook_sysctlbyname);
        NSLog(@"[LC] Hooked sysctlbyname");
    }
    
    if (orig_sysctl) {
        litehook_hook_function(orig_sysctl, hook_sysctl);
        NSLog(@"[LC] Hooked sysctl");
    }
    
    // Hook UIDevice methods
    Class UIDeviceClass = objc_getClass("UIDevice");
    if (UIDeviceClass) {
        Method modelMethod = class_getInstanceMethod(UIDeviceClass, @selector(model));
        Method systemVersionMethod = class_getInstanceMethod(UIDeviceClass, @selector(systemVersion));
        Method systemNameMethod = class_getInstanceMethod(UIDeviceClass, @selector(systemName));
        
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
        NSLog(@"[LC] Hooked UIDevice methods");
    }
    
    // Hook NSProcessInfo methods
    Class NSProcessInfoClass = objc_getClass("NSProcessInfo");
    if (NSProcessInfoClass) {
        Method physicalMemoryMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(physicalMemory));
        Method processorCountMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(processorCount));
        Method activeProcessorCountMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(activeProcessorCount));
        Method operatingSystemVersionMethod = class_getInstanceMethod(NSProcessInfoClass, @selector(operatingSystemVersion));
        
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
        NSLog(@"[LC] Hooked NSProcessInfo methods");
    }
    
    NSLog(@"[LC] Device spoofing hooks initialized");
}