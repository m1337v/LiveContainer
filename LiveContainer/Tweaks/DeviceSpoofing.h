//
//  DeviceSpoofing.h
//  LiveContainer
//
//  Device spoofing to prevent fingerprinting
//

#ifndef DeviceSpoofing_h
#define DeviceSpoofing_h

#import <Foundation/Foundation.h>

// Device profile structure
typedef struct {
    const char *modelIdentifier;    // e.g., "iPhone16,2"
    const char *hardwareModel;      // e.g., "D84AP"
    const char *marketingName;      // e.g., "iPhone 15 Pro Max"
    const char *systemVersion;      // e.g., "17.4"
    const char *buildVersion;       // e.g., "21E219"
    const char *kernelVersion;      // e.g., "Darwin Kernel Version 23.4.0..."
    uint64_t physicalMemory;        // In bytes
    uint32_t cpuCoreCount;          // Number of CPU cores
} LCDeviceProfile;

// Available device profiles
extern const LCDeviceProfile kDeviceProfileiPhone15ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone15Pro;
extern const LCDeviceProfile kDeviceProfileiPhone14ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone14Pro;
extern const LCDeviceProfile kDeviceProfileiPhone13ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone13Pro;
extern const LCDeviceProfile kDeviceProfileiPadPro12_9_6th;

// Initialize device spoofing hooks
void DeviceSpoofingGuestHooksInit(void);

// Configuration functions
void LCSetDeviceSpoofingEnabled(BOOL enabled);
BOOL LCIsDeviceSpoofingEnabled(void);

void LCSetDeviceProfile(NSString *profileName);
NSString *LCGetCurrentDeviceProfile(void);

// Get available profiles
NSDictionary<NSString *, NSDictionary *> *LCGetAvailableDeviceProfiles(void);

// Custom spoofing values
void LCSetSpoofedDeviceModel(NSString *model);
void LCSetSpoofedSystemVersion(NSString *version);
void LCSetSpoofedBuildVersion(NSString *build);
void LCSetSpoofedPhysicalMemory(uint64_t memory);

#endif /* DeviceSpoofing_h */