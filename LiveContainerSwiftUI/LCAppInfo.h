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
@property LCOrientationLock orientationLock;
@property bool doUseLCBundleId;
@property NSString* selectedLanguage;
@property NSString* dataUUID;
@property NSString* tweakFolder;
@property NSArray<NSDictionary*>* containerInfo;
@property bool autoSaveDisabled;
@property bool dontSign;
@property bool spoofSDKVersion;
@property NSDate* lastLaunched;
@property NSDate* installationDate;

@property bool is32bit;

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
@property NSString* proxyType; // "HTTP", "SOCKS5", "DIRECT"
@property NSString* proxyHost;
@property int proxyPort;
@property NSString* proxyUsername;
@property NSString* proxyPassword;
@property NSString* spoofNetworkMode; // "standard", "aggressive", "compatibility"

- (void)setBundlePath:(NSString*)newBundlePath;
- (NSMutableDictionary*)info;
- (UIImage*)icon;
- (NSString*)displayName;
- (NSString*)bundlePath;
- (NSString*)bundleIdentifier;
- (NSString*)version;
- (NSMutableArray*) urlSchemes;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
- (UIImage *)generateLiveContainerWrappedIcon;
- (NSDictionary *)generateWebClipConfigWithContainerId:(NSString*)containerId;
- (void)save;
- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(bool success, NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler  forceSign:(BOOL)forceSign;
@end
