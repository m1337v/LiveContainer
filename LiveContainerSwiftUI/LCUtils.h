#import <Foundation/Foundation.h>

typedef void (^LCParseMachOCallback)(const char *path, struct mach_header_64 *header, int fd, void* filePtr);

typedef NS_ENUM(NSInteger, Store){
    SideStore = 0,
    AltStore = 1,
    ADP = 2,
    Unknown = -1
};

#define PATCH_EXEC_RESULT_NO_SPACE_FOR_TWEAKLOADER 1

void LCPatchAppBundleFixupARM64eSlice(NSURL *bundleURL);
NSString *LCParseMachO(const char *path, bool readOnly, LCParseMachOCallback callback);
void LCPatchAddRPath(const char *path, struct mach_header_64 *header);
int LCPatchExecSlice(const char *path, struct mach_header_64 *header, bool doInject);
void LCChangeExecUUID(struct mach_header_64 *header);
NSString* getEntitlementXML(struct mach_header_64* header, void** entitlementXMLPtrOut);
NSString* getLCEntitlementXML(void);
bool checkCodeSignature(const char* path);
void refreshFile(NSString* execPath);
int dyld_get_program_sdk_version(void);

@interface PKZipArchiver : NSObject

- (NSData *)zippedDataForURL:(NSURL *)url;

@end

@interface LCUtils : NSObject

+ (void)validateJITLessSetupWithCompletionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (NSURL *)archiveIPAWithBundleName:(NSString*)newBundleName error:(NSError **)error;
+ (NSData *)certificateData;
+ (NSString *)certificatePassword;

+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;
+ (void)launchMultitaskGuestApp:(NSString *)displayName completionHandler:(void (^)(NSError *error))completionHandler API_AVAILABLE(ios(16.0));
+ (NSString*)getContainerUsingLCSchemeWithFolderName:(NSString*)folderName;

+ (NSProgress *)signAppBundleWithZSign:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (NSString*)getCertTeamIdWithKeyData:(NSData*)keyData password:(NSString*)password;
+ (int)validateCertificateWithCompletionHandler:(void(^)(int status, NSDate *expirationDate, NSString *error))completionHandler;

+ (BOOL)isAppGroupAltStoreLike;
+ (Store)store;
+ (NSString *)teamIdentifier;
+ (NSString *)appGroupID;
+ (NSString *)appUrlScheme;
+ (NSURL *)appGroupPath;
+ (NSString *)storeInstallURLScheme;
+ (NSString *)getVersionInfo;
@end

