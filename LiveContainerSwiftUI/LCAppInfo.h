#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import "LCUtils.h"

typedef NS_ENUM(NSInteger, LCOrientationLock){
    Disabled = 0,
    Landscape = 1,
    Portrait = 2
};

@interface LCAppInfo : NSObject {
    NSMutableDictionary* _info;
    NSMutableDictionary* _infoPlist;
    NSString* _bundlePath;
}
@property NSString* relativeBundlePath;
@property bool isShared;
@property bool isJITNeeded;
@property bool isLocked;
@property bool isHidden;
@property bool doSymlinkInbox;
@property bool hideLiveContainer;
@property bool dontLoadTweakLoader;
@property bool dontInjectTweakLoader;
@property UIColor* cachedColor;
@property UIColor* cachedColorDark;
@property LCOrientationLock orientationLock;
@property bool fixFilePickerNew;
@property bool fixLocalNotification;
@property bool doUseLCBundleId;
@property NSString* selectedLanguage;
@property NSString* dataUUID;
@property NSString* tweakFolder;
@property NSArray<NSDictionary*>* containerInfo;
@property bool autoSaveDisabled;
@property bool dontSign;
@property bool spoofSDKVersion;
@property (nonatomic, strong) NSString* jitLaunchScriptJs;
@property NSDate* lastLaunched;
@property NSDate* installationDate;
@property NSString* remark;
#if is32BitSupported
@property bool is32bit;
#endif

// GPS Addon Section
@property BOOL spoofGPS;
@property CLLocationDegrees spoofLatitude;
@property CLLocationDegrees spoofLongitude;
@property CLLocationDistance spoofAltitude;
@property NSString* spoofLocationName;

// Camera Addon Section
@property BOOL spoofCamera;
@property NSString* spoofCameraType; // "image" or "video"
@property NSString* spoofCameraImagePath;
@property NSString* spoofCameraVideoPath;
@property BOOL spoofCameraLoop;
@property NSString* spoofCameraMode; // NEW: "standard", "aggressive", "compatibility"
@property (nonatomic) NSString* spoofCameraTransformOrientation; // "none", "portrait", "landscape"
@property (nonatomic) NSString* spoofCameraTransformScale;       // "fit", "fill", "crop"
@property (nonatomic) NSString* spoofCameraTransformFlip;        // "none", "horizontal", "vertical"

// Network Addon Section
@property BOOL spoofNetwork;
@property NSString* proxyHost;
@property int proxyPort;
@property NSString* proxyUsername;
@property NSString* proxyPassword;

// SSL section
@property bool bypassSSLPinning;

// Device Addon Section (Ghost-style profile + per-feature toggles)
@property bool deviceSpoofingEnabled;
@property (nonatomic) NSString* deviceSpoofProfile;
@property (nonatomic) NSString* deviceSpoofCustomVersion; // Independent iOS version override

// Per-feature toggles (Ghost parity)
@property bool deviceSpoofDeviceName;
@property (nonatomic) NSString* deviceSpoofDeviceNameValue;
@property bool deviceSpoofCarrier;
@property (nonatomic) NSString* deviceSpoofCarrierName;
@property (nonatomic) NSString* deviceSpoofMCC;
@property (nonatomic) NSString* deviceSpoofMNC;
@property (nonatomic) NSString* deviceSpoofCarrierCountry;
@property bool deviceSpoofIdentifiers;
@property (nonatomic) NSString* deviceSpoofVendorID;
@property (nonatomic) NSString* deviceSpoofAdvertisingID;
@property bool deviceSpoofTimezone;
@property (nonatomic) NSString* deviceSpoofTimezoneValue;
@property bool deviceSpoofLocale;
@property (nonatomic) NSString* deviceSpoofLocaleValue;
@property bool deviceSpoofScreenCapture;

// Extended spoofing (Ghost + Project-X parity)
@property bool deviceSpoofBootTime;
@property (nonatomic) NSString* deviceSpoofBootTimeRange; // "short","medium","long","week"
@property bool deviceSpoofUserAgent;
@property (nonatomic) NSString* deviceSpoofUserAgentValue;
@property bool deviceSpoofBattery;
@property float deviceSpoofBatteryLevel;      // 0.0 – 1.0
@property int deviceSpoofBatteryState;         // 0=unknown,1=unplugged,2=charging,3=full
@property bool deviceSpoofStorage;
@property (nonatomic) NSString* deviceSpoofStorageCapacity; // GB string e.g. "256"
@property bool deviceSpoofBrightness;
@property float deviceSpoofBrightnessValue;    // 0.0 – 1.0
@property bool deviceSpoofThermal;
@property int deviceSpoofThermalState;         // 0=nominal,1=fair,2=serious,3=critical
@property bool deviceSpoofLowPowerMode;
@property bool deviceSpoofLowPowerModeValue;

- (void)setBundlePath:(NSString*)newBundlePath;
- (NSMutableDictionary*)info;
- (UIImage*)iconIsDarkIcon:(BOOL)isDarkIcon;
- (void)clearIconCache;
- (NSString*)displayName;
- (NSString*)bundlePath;
- (NSString*)bundleIdentifier;
- (NSString*)version;
- (NSMutableArray<NSString *>*)urlSchemes;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
- (UIImage *)generateLiveContainerWrappedIconWithStyle:(GeneratedIconStyle)style;
- (NSDictionary *)generateWebClipConfigWithContainerId:(NSString*)containerId iconStyle:(GeneratedIconStyle)style;
- (void)save;
- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(bool success, NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler  forceSign:(BOOL)forceSign;
@end
