//
//  DeviceSpoofing.h
//  LiveContainer
//
//  Device spoofing to prevent fingerprinting
//  Extended for iOS 18.x and 26.x support
//

#ifndef DeviceSpoofing_h
#define DeviceSpoofing_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <stdint.h>

// Device profile structure - extended with more fields
typedef struct {
    const char *modelIdentifier;    // e.g., "iPhone17,1"
    const char *hardwareModel;      // e.g., "D93AP"
    const char *marketingName;      // e.g., "iPhone 16 Pro Max"
    const char *systemVersion;      // e.g., "18.1"
    const char *buildVersion;       // e.g., "22B83"
    const char *kernelVersion;      // e.g., "Darwin Kernel Version 24.1.0..."
    const char *kernelRelease;      // e.g., "24.1.0"
    uint64_t physicalMemory;        // In bytes
    uint32_t cpuCoreCount;          // Number of CPU cores
    uint32_t performanceCores;      // Performance cores
    uint32_t efficiencyCores;       // Efficiency cores
    CGFloat screenScale;            // Screen scale (3.0 for Retina)
    CGFloat screenWidth;            // Native screen width
    CGFloat screenHeight;           // Native screen height
    const char *chipName;           // e.g., "A18 Pro"
    const char *gpuName;            // e.g., "Apple GPU"
} LCDeviceProfile;

// Available device profiles - iOS 18.x / 26.x compatible
extern const LCDeviceProfile kDeviceProfileiPhone16ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone16Pro;
extern const LCDeviceProfile kDeviceProfileiPhone16;
extern const LCDeviceProfile kDeviceProfileiPhone15ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone15Pro;
extern const LCDeviceProfile kDeviceProfileiPhone14ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone14Pro;
extern const LCDeviceProfile kDeviceProfileiPhone13ProMax;
extern const LCDeviceProfile kDeviceProfileiPhone13Pro;
extern const LCDeviceProfile kDeviceProfileiPadPro13_M4;
extern const LCDeviceProfile kDeviceProfileiPadPro11_M4;
extern const LCDeviceProfile kDeviceProfileiPadPro12_9_6th;

// Initialize device spoofing hooks
void DeviceSpoofingGuestHooksInit(void);

// Configuration functions
void LCSetDeviceSpoofingEnabled(BOOL enabled);
BOOL LCIsDeviceSpoofingEnabled(void);

void LCSetDeviceProfile(NSString *profileName);
NSString *LCGetCurrentDeviceProfile(void);
NSDictionary *LCGetCurrentProfileData(void);

// Get available profiles
NSDictionary<NSString *, NSDictionary *> *LCGetAvailableDeviceProfiles(void);

// Custom spoofing values
void LCSetSpoofedDeviceModel(NSString *model);
void LCSetSpoofedSystemVersion(NSString *version);
void LCSetSpoofedBuildVersion(NSString *build);
void LCSetSpoofedPhysicalMemory(uint64_t memory);
void LCSetSpoofedVendorID(NSString *vendorID);
void LCSetSpoofedAdvertisingID(NSString *advertisingID);

// Fingerprint spoofing - Battery
void LCSetSpoofedBatteryLevel(float level);        // 0.0-1.0
void LCSetSpoofedBatteryState(NSInteger state);    // 0=Unknown, 1=Unplugged, 2=Charging, 3=Full
void LCRandomizeBattery(void);

// Fingerprint spoofing - Screen/Brightness
void LCSetSpoofedBrightness(float brightness);     // 0.0-1.0
void LCRandomizeBrightness(void);

// Fingerprint spoofing - Uptime (critical fingerprinting vector!)
void LCSetUptimeOffset(NSTimeInterval offset);     // Offset in seconds to add to uptime
void LCRandomizeUptime(void);                      // Randomize uptime to 1-7 days

// Fingerprint spoofing - Thermal/Power state
void LCSetSpoofedThermalState(NSInteger state);    // 0=Nominal, 1=Fair, 2=Serious, 3=Critical
void LCSetSpoofedLowPowerMode(BOOL enabled, BOOL value);

// Fingerprint spoofing - Disk space
void LCSetSpoofedDiskSpace(uint64_t freeSpace, uint64_t totalSpace);

// Initialize all fingerprint protection with random values
void LCInitializeFingerprintProtection(void);

// Random generation helpers
NSString *LCGenerateRandomUUID(void);
NSString *LCGenerateRandomMACAddress(void);

#endif /* DeviceSpoofing_h */