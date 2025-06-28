#import "LCSharedUtils.h"
#import "FoundationPrivate.h"
#import "UIKitPrivate.h"
#import "utils.h"

extern NSUserDefaults *lcUserDefaults;
extern NSString *lcAppUrlScheme;
extern NSBundle *lcMainBundle;

@implementation LCSharedUtils

+ (NSString*) teamIdentifier {
    static NSString* ans = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void* taskSelf = SecTaskCreateFromSelf(NULL);
        CFErrorRef error = NULL;
        CFTypeRef cfans = SecTaskCopyValueForEntitlement(taskSelf, CFSTR("com.apple.developer.team-identifier"), &error);
        if(CFGetTypeID(cfans) == CFStringGetTypeID()) {
            ans = (__bridge NSString*)cfans;
        }
        CFRelease(taskSelf);
        if(!ans) {
            // the above seems not to work if the device is jailbroken by Palera1n, so we use the public api one as backup
            // https://stackoverflow.com/a/11841898
            NSString *tempAccountName = @"bundleSeedID";
            NSDictionary *query = @{
                (__bridge NSString *)kSecClass : (__bridge NSString *)kSecClassGenericPassword,
                (__bridge NSString *)kSecAttrAccount : tempAccountName,
                (__bridge NSString *)kSecAttrService : @"",
                (__bridge NSString *)kSecReturnAttributes: (__bridge NSNumber *)kCFBooleanTrue,
            };
            CFDictionaryRef result = nil;
            OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
            if (status == errSecItemNotFound)
                status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
            if (status == errSecSuccess) {
                status = SecItemDelete((__bridge CFDictionaryRef)query); // remove temp item
                NSDictionary *dict = (__bridge_transfer NSDictionary *)result;
                NSString *accessGroup = dict[(__bridge NSString *)kSecAttrAccessGroup];
                NSArray *components = [accessGroup componentsSeparatedByString:@"."];
                NSString *bundleSeedID = [[components objectEnumerator] nextObject];
                ans = bundleSeedID;
            }
        }
    });
    return ans;
}

+ (NSString *)appGroupID {
    static dispatch_once_t once;
    static NSString *appGroupID = @"Unknown";
    dispatch_once(&once, ^{
        NSArray* possibleAppGroups = @[
            [@"group.com.SideStore.SideStore." stringByAppendingString:[self teamIdentifier]],
            [@"group.com.rileytestut.AltStore." stringByAppendingString:[self teamIdentifier]]
        ];
        
        // we prefer app groups with "Apps" in it, which indicate this app group is actually used by the store.
        for (NSString *group in possibleAppGroups) {
            NSURL *path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
            if(!path) {
                continue;
            }
            NSURL *bundlePath = [path URLByAppendingPathComponent:@"Apps"];
            if ([NSFileManager.defaultManager fileExistsAtPath:bundlePath.path]) {
                // This will fail if LiveContainer is installed in both stores, but it should never be the case
                appGroupID = group;
                return;
            }
        }
        
        // if no "Apps" is found, we choose a valid group
        for (NSString *group in possibleAppGroups) {
            NSURL *path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
            if(!path) {
                continue;
            }
            appGroupID = group;
            return;
        }
        
        // if no possibleAppGroup is found, we detect app group from entitlement file
        // Cache app group after importing cert so we don't have to analyze executable every launch
        NSString *cached = [lcUserDefaults objectForKey:@"LCAppGroupID"];
        if (cached && [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:cached]) {
            appGroupID = cached;
            return;
        }
        CFErrorRef error = NULL;
        void* taskSelf = SecTaskCreateFromSelf(NULL);
        CFTypeRef value = SecTaskCopyValueForEntitlement(taskSelf, CFSTR("com.apple.security.application-groups"), &error);
        CFRelease(taskSelf);
        
        if(!value) {
            return;
        }
        NSArray* appGroups = (__bridge NSArray *)value;
        if(appGroups.count > 0) {
            appGroupID = [appGroups firstObject];
        }
    });
    return appGroupID;
}

+ (NSURL*) appGroupPath {
    static NSURL *appGroupPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[LCSharedUtils appGroupID]];
    });
    return appGroupPath;
}

+ (NSString *)certificatePassword {
    NSUserDefaults* nud = [[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]];
    if(!nud) {
        nud = NSUserDefaults.standardUserDefaults;
    }
    
    return [nud objectForKey:@"LCCertificatePassword"];
}

+ (BOOL)launchToGuestApp {
    NSString *urlScheme = nil;
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    UIApplication *application = [NSClassFromString(@"UIApplication") sharedApplication];
    
    int tries = 1;
    if (!self.certificatePassword) {
        if (!access(tsPath.UTF8String, F_OK)) {
            urlScheme = @"apple-magnifier://enable-jit?bundle-id=%@";
        } else if ([application canOpenURL:[NSURL URLWithString:@"stikjit://"]]) {
            urlScheme = @"stikjit://enable-jit?bundle-id=%@";
        } else if ([application canOpenURL:[NSURL URLWithString:@"sidestore://"]]) {
            urlScheme = @"sidestore://sidejit-enable?bid=%@";
        }
    }
    if (!urlScheme) {
        tries = 2;
        urlScheme = [NSString stringWithFormat:@"%@://livecontainer-relaunch", lcAppUrlScheme];
    }
    NSURL *launchURL = [NSURL URLWithString:[NSString stringWithFormat:urlScheme, NSBundle.mainBundle.bundleIdentifier]];

    if ([application canOpenURL:launchURL]) {
        //[UIApplication.sharedApplication suspend];
        for (int i = 0; i < tries; i++) {
            [application openURL:launchURL options:@{} completionHandler:^(BOOL b) {
                // syscall(SYS_ptrace, PT_DENY_ATTACH, 0, 0, 0);
                __asm__ __volatile__ (
                    "mov x0, #31\n"
                    "mov x16, #26\n"
                    "svc #0x80\n"
                );
                raise(SIGKILL);
            }];
        }
        return YES;
    } else {
        // none of the ways work somehow (e.g. LC itself was hidden), we just exit and wait for user to manually launch it
        exit(0);
    }
    return NO;
}

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if(![components.host isEqualToString:@"livecontainer-launch"]) return NO;

    NSString* launchBundleId = nil;
    NSString* openUrl = nil;
    NSString* containerFolderName = nil;
    for (NSURLQueryItem* queryItem in components.queryItems) {
        if ([queryItem.name isEqualToString:@"bundle-name"]) {
            launchBundleId = queryItem.value;
        } else if ([queryItem.name isEqualToString:@"open-url"]){
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:queryItem.value options:0];
            openUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        } else if ([queryItem.name isEqualToString:@"container-folder-name"]) {
            containerFolderName = queryItem.value;
        }
    }
    if(launchBundleId) {
        if (openUrl) {
            [lcUserDefaults setObject:openUrl forKey:@"launchAppUrlScheme"];
        }
        
        // Attempt to restart LiveContainer with the selected guest app
        [lcUserDefaults setObject:launchBundleId forKey:@"selected"];
        [lcUserDefaults setObject:containerFolderName forKey:@"selectedContainer"];
        return [self launchToGuestApp];
    }
    
    return NO;
}

+ (void)setWebPageUrlForNextLaunch:(NSString*) urlString {
    [lcUserDefaults setObject:urlString forKey:@"webPageToOpen"];
}

+ (NSURL*)containerLockPath {
    static dispatch_once_t once;
    static NSURL *infoPath;
    
    dispatch_once(&once, ^{
        infoPath = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer/containerLock.plist"];
    });
    return infoPath;
}

+ (NSString*)getContainerUsingLCSchemeWithFolderName:(NSString*)folderName {
    NSURL* infoPath = [self containerLockPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        return nil;
    }
    
    for (NSString* key in info) {
        if([info[key] isKindOfClass:NSString.class]) {
            // incase user have app opened while update
            if([folderName isEqualToString:info[key]]) {
                return key;
            }
        } else if ([info[key] isKindOfClass:NSArray.class]) {
            // in newer version with liveprocess support, it is possible that one lc can open more than 1 app, so we need to save it in an array
            for(NSString* runningFolderName in info[key]) {
                if([folderName isEqualToString:runningFolderName]) {
                    return key;
                }
            }
        }
    }
    
    return nil;
}

+ (void)setContainerUsingByThisLC:(NSString*)folderName remove:(BOOL)remove {
    NSURL* infoPath = [self containerLockPath];
    
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        info = [NSMutableDictionary new];
    }
    if(remove) {
        if([info[lcAppUrlScheme] isKindOfClass:NSString.class]) {
            [info removeObjectForKey:lcAppUrlScheme];
        } else if ([info[lcAppUrlScheme] isKindOfClass:NSArray.class]) {
            if(folderName){
                [(NSMutableArray*)info[lcAppUrlScheme] removeObject:folderName];
            } else {
                [(NSMutableArray*)info[lcAppUrlScheme] removeAllObjects];
            }
        }
    } else {
        if([info[lcAppUrlScheme] isKindOfClass:NSString.class]) {
            // upgrade
            NSString* oldFolderName = info[lcAppUrlScheme];
            info[lcAppUrlScheme] = [NSMutableArray new];
            [(NSMutableArray*)info[lcAppUrlScheme] addObject:folderName];
            [(NSMutableArray*)info[lcAppUrlScheme] addObject:oldFolderName];
        } else if ([info[lcAppUrlScheme] isKindOfClass:NSArray.class]) {
            if(![(NSMutableArray*)info[lcAppUrlScheme] containsObject:folderName]) {
                [(NSMutableArray*)info[lcAppUrlScheme] addObject:folderName];
            }

        } else {
            info[lcAppUrlScheme] = [NSMutableArray new];
            [(NSMutableArray*)info[lcAppUrlScheme] addObject:folderName];
        }
    }
    [info writeToFile:infoPath.path atomically:YES];

}

+ (void)removeContainerUsingByLC:(NSString*)LCScheme {
    NSURL* infoPath = [self containerLockPath];
    
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        return;
    }
    [info removeObjectForKey:LCScheme];
    [info writeToFile:infoPath.path atomically:YES];

}

// move app data to private folder to prevent 0xdead10cc https://forums.developer.apple.com/forums/thread/126438
+ (void)moveSharedAppFolderBack {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *libraryPathUrl = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
    
    NSError *error;
    NSString *sharedAppDataFolderPath = [libraryPathUrl.path stringByAppendingPathComponent:@"SharedDocuments"];
    if(![fm fileExistsAtPath:sharedAppDataFolderPath]){
        [fm createDirectoryAtPath:sharedAppDataFolderPath withIntermediateDirectories:YES attributes:@{} error:&error];
    }
    // move all apps in shared folder back
    NSArray<NSString *> * sharedDataFoldersToMove = [fm contentsOfDirectoryAtPath:sharedAppDataFolderPath error:&error];
    
    // something went wrong with app group
    if(!appGroupFolder && sharedDataFoldersToMove.count > 0) {
        [lcUserDefaults setObject:@"LiveContainer was unable to move the data of shared app back because LiveContainer cannot access app group. Please check JITLess diagnose page in LiveContainer settings for more information." forKey:@"error"];
        return;
    }
    
    for(int i = 0; i < [sharedDataFoldersToMove count]; ++i) {
        NSString* destPath = [appGroupFolder.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@", sharedDataFoldersToMove[i]]];
        if([fm fileExistsAtPath:destPath]) {
            [fm
             moveItemAtPath:[sharedAppDataFolderPath stringByAppendingPathComponent:sharedDataFoldersToMove[i]]
             toPath:[docPathUrl.path stringByAppendingPathComponent:[NSString stringWithFormat:@"FOLDER_EXISTS_AT_APP_GROUP_%@", sharedDataFoldersToMove[i]]]
             error:&error
            ];
            
        } else {
            [fm
             moveItemAtPath:[sharedAppDataFolderPath stringByAppendingPathComponent:sharedDataFoldersToMove[i]]
             toPath:destPath
             error:&error
            ];
        }
    }
    
}

+ (BOOL)moveSharedAppFolderBackWithDataUUID:(NSString*)dataUUID {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *libraryPathUrl = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
    
    NSError *error = nil;
    NSString *sharedAppDataFolderPath = [libraryPathUrl.path stringByAppendingPathComponent:@"SharedDocuments"];
    if(![fm fileExistsAtPath:sharedAppDataFolderPath]){
        [fm createDirectoryAtPath:sharedAppDataFolderPath withIntermediateDirectories:YES attributes:@{} error:&error];
    }
    // something went wrong with app group
    if(!appGroupFolder) {
        [lcUserDefaults setObject:@"LiveContainer was unable to move the data of shared app back because LiveContainer cannot access app group. Please check JITLess diagnose page in LiveContainer settings for more information." forKey:@"error"];
        return false;
    }
    
    NSString* destPath = [appGroupFolder.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@", dataUUID]];
    if([fm fileExistsAtPath:destPath]) {
        return false;
    } else {
        [fm
         moveItemAtPath:[sharedAppDataFolderPath stringByAppendingPathComponent:dataUUID]
         toPath:destPath
         error:&error
        ];
        return error == nil;
    }
    
}

+ (NSBundle*)findBundleWithBundleId:(NSString*)bundleId {
    NSString *docPath = [NSString stringWithFormat:@"%s/Documents", getenv("LC_HOME_PATH")];
    
    NSURL *appGroupFolder = nil;
    
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, bundleId];
    NSBundle *appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    // not found locally, let's look for the app in shared folder
    if (!appBundle) {
        appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
        
        bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", appGroupFolder.path, bundleId];
        appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    }
    return appBundle;
}

+ (void)dumpPreferenceToPath:(NSString*)plistLocationTo dataUUID:(NSString*)dataUUID {
    NSFileManager* fm = [[NSFileManager alloc] init];
    NSError* error1;
    
    NSDictionary* preferences = [lcUserDefaults objectForKey:dataUUID];
    if(!preferences) {
        return;
    }
    
    [fm createDirectoryAtPath:plistLocationTo withIntermediateDirectories:YES attributes:@{} error:&error1];
    for(NSString* identifier in preferences) {
        NSDictionary* preference = preferences[identifier];
        NSString *itemPath = [plistLocationTo stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", identifier]];
        if([preference count] == 0) {
            // Attempt to delete the file
            [fm removeItemAtPath:itemPath error:&error1];
            continue;
        }
        [preference writeToFile:itemPath atomically:YES];
    }
    [lcUserDefaults removeObjectForKey:dataUUID];
}

+ (NSString*)findDefaultContainerWithBundleId:(NSString*)bundleId {
    // find app's default container
    NSURL* appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
    
    NSString* bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", appGroupFolder.path, bundleId];
    NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
    return infoDict[@"LCDataUUID"];
}

@end
