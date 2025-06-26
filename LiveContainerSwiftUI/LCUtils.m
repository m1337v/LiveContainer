@import Darwin;
@import MachO;
@import UIKit;
@import UniformTypeIdentifiers;

#import "LCUtils.h"
#import "../MultitaskSupport/DecoratedAppSceneView.h"
#import "../ZSign/zsigner.h"
#import "LiveContainerSwiftUI-Swift.h"

Class LCSharedUtilsClass = nil;

// make SFSafariView happy and open data: URLs
@implementation NSURL(hack)
- (BOOL)safari_isHTTPFamilyURL {
    // Screw it, Apple
    return YES;
}
@end

@implementation LCUtils

+ (void)load {
    LCSharedUtilsClass = NSClassFromString(@"LCSharedUtils");
}

#pragma mark Certificate & password
+ (NSString *)teamIdentifier {
    return [LCSharedUtilsClass teamIdentifier];
}

+ (NSURL *)appGroupPath {
    return [LCSharedUtilsClass appGroupPath];
}

+ (NSData *)certificateData {
    NSUserDefaults* nud = [[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]];
    if(!nud) {
        nud = NSUserDefaults.standardUserDefaults;
    }
    return [nud objectForKey:@"LCCertificateData"];
}

+ (NSString *)certificatePassword {
    return [LCSharedUtilsClass certificatePassword];
}

+ (void)setCertificatePassword:(NSString *)certPassword {
    [NSUserDefaults.standardUserDefaults setObject:certPassword forKey:@"LCCertificatePassword"];
    [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] setObject:certPassword forKey:@"LCCertificatePassword"];
}

+ (NSString *)appGroupID {
    return [LCSharedUtilsClass appGroupID];
}

#pragma mark LCSharedUtils wrappers
+ (BOOL)launchToGuestApp {
    return [LCSharedUtilsClass launchToGuestApp];
}

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    return [LCSharedUtilsClass launchToGuestAppWithURL:url];
}

#pragma mark Multitasking (WIP, PoC only)
+ (void)launchMultitaskGuestApp:(NSString *)displayName completionHandler:(void (^)(NSError *error))completionHandler {
    NSBundle *liveProcessBundle = [NSBundle bundleWithPath:[NSBundle.mainBundle.builtInPlugInsPath stringByAppendingPathComponent:@"LiveProcess.appex"]];
    if(!liveProcessBundle) {
        NSError *error = [NSError errorWithDomain:displayName code:2 userInfo:@{NSLocalizedDescriptionKey: @"LiveProcess extension not found. Please reinstall LiveContainer and select Keep Extensions"}];
        completionHandler(error);
        return;
    }
    
    NSError *error;
    NSExtension *extension = [NSExtension extensionWithIdentifier:liveProcessBundle.bundleIdentifier error:&error];
    if(error) {
        completionHandler(error);
        return;
    }
    
    NSUserDefaults *lcUserDefaults = NSUserDefaults.standardUserDefaults;
    NSExtensionItem *item = [NSExtensionItem new];
    NSString* selectedContainer = [lcUserDefaults stringForKey:@"selectedContainer"];
    item.userInfo = @{
        @"selected": [lcUserDefaults stringForKey:@"selected"],
        @"selectedContainer": [lcUserDefaults stringForKey:@"selectedContainer"]
    };
    [lcUserDefaults removeObjectForKey:@"selected"];
    [lcUserDefaults removeObjectForKey:@"selectedContainer"];
    
    [extension beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *identifier) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(identifier) {
                // TODO: show windows elsewhere
                if (@available(iOS 16.1, *)) {
                    if(UIApplication.sharedApplication.supportsMultipleScenes && [[[NSUserDefaults alloc] initWithSuiteName:[LCUtils appGroupID]] integerForKey:@"LCMultitaskMode" ] == 1) {
                        [MultitaskWindowManager openAppWindowWithId:identifier ext:extension displayName:displayName dataUUID:selectedContainer];
                        completionHandler(nil);
                        return;
                    }
                }
                
                
                UIView *view = ((UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject).keyWindow.rootViewController.view;
                
                DecoratedAppSceneView *launcherView = [[DecoratedAppSceneView alloc] initWithExtension:extension identifier:identifier windowName:displayName dataUUID:selectedContainer];
                launcherView.center = view.center;
                [view addSubview:launcherView];
                completionHandler(nil);
            } else {
                NSError *error = [NSError errorWithDomain:displayName code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to start app. Child process has unexpectedly crashed"}];
                completionHandler(error);
            }
        });
    }];
}

+ (void)launchMultitaskGuestDataRetrieve:(NSString *)displayName completionHandler:(void (^)(NSError *error))completionHandler {
    NSBundle *liveProcessBundle = [NSBundle bundleWithPath:[NSBundle.mainBundle.builtInPlugInsPath stringByAppendingPathComponent:@"LiveProcess.appex"]];
    if(!liveProcessBundle) {
        NSError *error = [NSError errorWithDomain:displayName code:2 userInfo:@{NSLocalizedDescriptionKey: @"LiveProcess extension not found. Please reinstall LiveContainer and select Keep Extensions"}];
        completionHandler(error);
        return;
    }
    
    NSError *error;
    NSExtension *extension = [NSExtension extensionWithIdentifier:liveProcessBundle.bundleIdentifier error:&error];
    if(error) {
        completionHandler(error);
        return;
    }
    
    NSUserDefaults *lcUserDefaults = NSUserDefaults.standardUserDefaults;
    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{
        @"selected": [lcUserDefaults stringForKey:@"selected"],
        @"selectedContainer": [lcUserDefaults stringForKey:@"selectedContainer"],
        @"liveprocessRetrieveData": @YES
    };
    [lcUserDefaults removeObjectForKey:@"selected"];
    [lcUserDefaults removeObjectForKey:@"selectedContainer"];
    
    [extension beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *identifier) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(identifier) {
                completionHandler(nil);
            } else {
                NSError *error = [NSError errorWithDomain:displayName code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to start app. Child process has unexpectedly crashed"}];
                completionHandler(error);
            }
        });
    }];
}

#pragma mark Code signing


+ (void)loadStoreFrameworksWithError2:(NSError **)error {
    // too lazy to use dispatch_once
    static BOOL loaded = NO;
    if (loaded) return;

    void* handle = dlopen("@executable_path/Frameworks/ZSign.dylib", RTLD_GLOBAL);
    const char* dlerr = dlerror();
    if (!handle || (uint64_t)handle > 0xf00000000000) {
        if (dlerr) {
            *error = [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to load ZSign: %s", dlerr]}];
        } else {
            *error = [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to load ZSign: An unknown error occurred."]}];
        }
        NSLog(@"[LC] %s", dlerr);
        return;
    }
    
    loaded = YES;
}

+ (NSURL *)storeBundlePath {
    if ([self store] == SideStore) {
        return [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.SideStore.SideStore/App.app"];
    } else {
        return [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.rileytestut.AltStore/App.app"];
    }
}

+ (NSString *)storeInstallURLScheme {
    if ([self store] == SideStore) {
        return @"sidestore://install?url=%@";
    } else {
        return @"altstore://install?url=%@";
    }
}

+ (NSProgress *)signAppBundleWithZSign:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSError *error;

    // use zsign as our signer~
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
    NSData *profileData = [NSData dataWithContentsOfURL:profilePath];
    // Load libraries from Documents, yeah
    [self loadStoreFrameworksWithError2:&error];

    if (error) {
        completionHandler(NO, error);
        return nil;
    }

    NSLog(@"[LC] starting signing...");
    
    NSProgress* ans = [NSClassFromString(@"ZSigner") signWithAppPath:[path path] prov:profileData key: self.certificateData pass:self.certificatePassword completionHandler:completionHandler];
    
    return ans;
}

+ (NSString*)getCertTeamIdWithKeyData:(NSData*)keyData password:(NSString*)password {
    NSError *error;
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
    NSData *profileData = [NSData dataWithContentsOfURL:profilePath];
    [self loadStoreFrameworksWithError2:&error];
    if (error) {
        return nil;
    }
    NSString* ans = [NSClassFromString(@"ZSigner") getTeamIdWithProv:profileData key:keyData pass:password];
    return ans;
}

+ (int)validateCertificateWithCompletionHandler:(void(^)(int status, NSDate *expirationDate, NSString *error))completionHandler {
    NSError *error;
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
    NSData *profileData = [NSData dataWithContentsOfURL:profilePath];
    NSData *certData = [LCUtils certificateData];
    if (error) {
        return -6;
    }
    [self loadStoreFrameworksWithError2:&error];
    int ans = [NSClassFromString(@"ZSigner") checkCertWithProv:profileData key:certData pass:[LCUtils certificatePassword] completionHandler:completionHandler];
    return ans;
}

#pragma mark Setup

+ (Store) store {
    static Store ans;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // use uttype to accurately detect store
        if([UTType typeWithIdentifier:[NSString stringWithFormat:@"io.sidestore.Installed.%@", NSBundle.mainBundle.bundleIdentifier]]) {
            ans = SideStore;
        } else if ([UTType typeWithIdentifier:[NSString stringWithFormat:@"io.altstore.Installed.%@", NSBundle.mainBundle.bundleIdentifier]]) {
            ans = AltStore;
        } else {
            ans = Unknown;
        }
        
        if(ans != Unknown) {
            return;
        }
        
        if([[self appGroupID] containsString:@"AltStore"] && ![[self appGroupID] isEqualToString:@"group.com.rileytestut.AltStore"]) {
            ans = AltStore;
        } else if ([[self appGroupID] containsString:@"SideStore"] && ![[self appGroupID] isEqualToString:@"group.com.SideStore.SideStore"]) {
            ans = SideStore;
        } else if (![[self appGroupID] containsString:@"Unknown"] ) {
            ans = ADP;
        } else {
            ans = Unknown;
        }
    });
    return ans;
}

+ (NSString *)appUrlScheme {
    return NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0];
}

+ (BOOL)isAppGroupAltStoreLike {
    return [self.appGroupID containsString:@"SideStore"] || [self.appGroupID containsString:@"AltStore"];
}

+ (void)changeMainExecutableTo:(NSString *)exec error:(NSError **)error {
    NSURL *infoPath = [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer/App.app/Info.plist"];
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
    if (!infoDict) return;

    infoDict[@"CFBundleExecutable"] = exec;
    [infoDict writeToURL:infoPath error:error];
}

+ (void)validateJITLessSetupWithCompletionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    // Verify that the certificate is usable
    // Create a test app bundle
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CertificateValidation.app"];
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tmpExecPath = [path stringByAppendingPathComponent:@"LiveContainer.tmp"];
    NSString *tmpLibPath = [path stringByAppendingPathComponent:@"TestJITLess.dylib"];
    NSString *tmpInfoPath = [path stringByAppendingPathComponent:@"Info.plist"];
    [NSFileManager.defaultManager copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];
    [NSFileManager.defaultManager copyItemAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/TestJITLess.dylib"] toPath:tmpLibPath error:nil];
    NSMutableDictionary *info = NSBundle.mainBundle.infoDictionary.mutableCopy;
    info[@"CFBundleExecutable"] = @"LiveContainer.tmp";
    [info writeToFile:tmpInfoPath atomically:YES];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block bool signSuccess = false;
    __block NSError* signError = nil;
    
    // Sign the test app bundle

    [LCUtils signAppBundleWithZSign:[NSURL fileURLWithPath:path]
                  completionHandler:^(BOOL success, NSError *_Nullable error) {
        signSuccess = success;
        signError = error;
        dispatch_semaphore_signal(sema);
    }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if(!signSuccess) {
            completionHandler(NO, signError);
        } else if (checkCodeSignature([tmpLibPath UTF8String])) {
            completionHandler(YES, signError);
        } else {
            completionHandler(NO, [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier code:2 userInfo:@{NSLocalizedDescriptionKey: @"lc.signer.latestCertificateInvalidErr"}]);
        }
        
    });
    

}

+ (NSURL *)archiveIPAWithBundleName:(NSString*)newBundleName error:(NSError **)error {
    if (*error) return nil;

    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *bundlePath = NSBundle.mainBundle.bundleURL;

    NSURL *tmpPath = manager.temporaryDirectory;

    NSURL *tmpPayloadPath = [tmpPath URLByAppendingPathComponent:@"LiveContainer2/Payload"];
    [manager removeItemAtURL:tmpPayloadPath error:nil];
    [manager createDirectoryAtURL:tmpPayloadPath withIntermediateDirectories:YES attributes:nil error:error];
    if (*error) return nil;
    
    NSURL *tmpIPAPath = [tmpPath URLByAppendingPathComponent:@"LiveContainer2.ipa"];
    

    [manager copyItemAtURL:bundlePath toURL:[tmpPayloadPath URLByAppendingPathComponent:@"App.app"] error:error];
    if (*error) return nil;
    
    NSURL *infoPath = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/Info.plist"];
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
    if (!infoDict) return nil;

    infoDict[@"CFBundleDisplayName"] = newBundleName;
    infoDict[@"CFBundleName"] = newBundleName;
    infoDict[@"CFBundleIdentifier"] = [NSString stringWithFormat:@"com.kdt.%@", newBundleName];
    infoDict[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0] = [newBundleName lowercaseString];
    infoDict[@"CFBundleIconName"] = @"AppIconGrey";
    if (infoDict[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"]) {
        infoDict[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"] = @"AppIconGrey";
    }
    infoDict[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIconGrey60x60";
    
    if (infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"]) {
        infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"] = @"AppIconGrey";
    }
    infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIconGrey60x60";
    infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][1] = @"AppIconGrey76x76";
    
    // reset a executable name so they don't look the same on the log
    NSURL* appBundlePath = [tmpPayloadPath URLByAppendingPathComponent:@"App.app"];
    
    NSURL* execFromPath = [appBundlePath URLByAppendingPathComponent:infoDict[@"CFBundleExecutable"]];
    infoDict[@"CFBundleExecutable"] = @"LiveContainer2";
    NSURL* execToPath = [appBundlePath URLByAppendingPathComponent:infoDict[@"CFBundleExecutable"]];
    
    // we remove the teamId after app group id so it can be correctly signed by AltSign. We don't touch application-identifier or team-id since most signer can handle them correctly otherwise the app won't launch at all
    __block NSError* parseExecError = nil;
    LCParseMachO(execFromPath.path.UTF8String, false, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
        void* entitlementXMLPtr = 0;
        NSString* entitlementXML = getEntitlementXML(header, &entitlementXMLPtr);
        NSData *plistData = [entitlementXML dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:plistData
                                                                       options:NSPropertyListImmutable
                                                                        format:nil
                                                                         error:&parseExecError];
        if(parseExecError) {
            return;
        }
        
        NSString* teamId = dict[@"com.apple.developer.team-identifier"];
        if(![teamId isKindOfClass:NSString.class]) {
            parseExecError = [NSError errorWithDomain:@"archiveIPAWithBundleName" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"com.apple.developer.team-identifier is not a string!"}];
            return;
        }
        infoDict[@"PrimaryLiveContainerTeamId"] = teamId;
        NSArray* appGroupsToFind = @[
            @"group.com.SideStore.SideStore",
            @"group.com.rileytestut.AltStore",
        ];
        for(NSString* appGroup in appGroupsToFind) {
            NSRange range = [entitlementXML rangeOfString:[NSString stringWithFormat:@"%@.%@", appGroup, teamId]];
            if(range.location == NSNotFound) {
                continue;
            }
            void* appGroupStrPtr = entitlementXMLPtr + range.location + appGroup.length;
            if(memcmp(appGroupStrPtr + 1, teamId.UTF8String, 10) != 0) {
                NSLog(@"App group id does not have prefix!");
            }
            memcpy(appGroupStrPtr, "</string>           ", 20);
            
        }
        
    });
    
    [manager moveItemAtURL:execFromPath toURL:execToPath error:error];
    if (*error) {
        NSLog(@"[LC] %@", *error);
        return nil;
    }
    
    // We have to change executable's UUID so iOS won't consider 2 executables the same
    NSString* errorChangeUUID = LCParseMachO([execToPath.path UTF8String], false, ^(const char *path, struct mach_header_64 *header, int fd, void* filePtr) {
        LCChangeExecUUID(header);
    });
    if (errorChangeUUID) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:errorChangeUUID forKey:NSLocalizedDescriptionKey];
        // populate the error object with the details
        *error = [NSError errorWithDomain:@"world" code:200 userInfo:details];
        NSLog(@"[LC] %@", errorChangeUUID);
        return nil;
    }
    
    [infoDict writeToURL:infoPath error:error];
    
    // we remove the extension
    [manager removeItemAtURL:[appBundlePath URLByAppendingPathComponent:@"PlugIns"] error:error];

    dlopen("/System/Library/PrivateFrameworks/PassKitCore.framework/PassKitCore", RTLD_GLOBAL);
    NSData *zipData = [[NSClassFromString(@"PKZipArchiver") new] zippedDataForURL:tmpPayloadPath.URLByDeletingLastPathComponent];
    if (!zipData) return nil;

    [manager removeItemAtURL:tmpPayloadPath error:error];
    if (*error) return nil;
    
    if([manager fileExistsAtPath:tmpIPAPath.path]) {
        [manager removeItemAtURL:tmpIPAPath error:error];
        if (*error) return nil;
    }

    [zipData writeToURL:tmpIPAPath options:0 error:error];
    if (*error) return nil;

    return tmpIPAPath;
}

+ (NSString *)getVersionInfo {
    return [NSString stringWithFormat:@"Version %@-%@",
            NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],
            NSBundle.mainBundle.infoDictionary[@"LCVersionInfo"]];
}

@end
