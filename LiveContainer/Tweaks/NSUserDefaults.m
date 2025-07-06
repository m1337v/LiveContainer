//
//  NSUserDefaults.m
//  LiveContainer
//
//  Created by s s on 2024/11/29.
//

#import "FoundationPrivate.h"
#import "LCSharedUtils.h"
#import "utils.h"
#import "LCSharedUtils.h"
#import "../../fishhook/fishhook.h"

BOOL hook_return_false(void) {
    return NO;
}

void swizzle(Class class, SEL originalAction, SEL swizzledAction) {
    method_exchangeImplementations(class_getInstanceMethod(class, originalAction), class_getInstanceMethod(class, swizzledAction));
}

void swizzle2(Class class, SEL originalAction, Class class2, SEL swizzledAction) {
    Method m1 = class_getInstanceMethod(class2, swizzledAction);
    class_addMethod(class, swizzledAction, method_getImplementation(m1), method_getTypeEncoding(m1));
    method_exchangeImplementations(class_getInstanceMethod(class, originalAction), class_getInstanceMethod(class, swizzledAction));
}

CFDictionaryRef hook_CFPreferencesCopyMultiple(CFArrayRef keysToFetch, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName);
CFDictionaryRef (*orig_CFPreferencesCopyMultiple)(CFArrayRef keysToFetch, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName);

NSURL* appContainerURL = 0;
NSString* appContainerPath = 0;

void NUDGuestHooksInit(void) {
    appContainerPath = [NSString stringWithUTF8String:getenv("HOME")];
    appContainerURL = [NSURL URLWithString:appContainerPath];
    
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wundeclared-selector"
    
    // fix for macOS host
    if(access("/Users", F_OK) == 0) {
        method_setImplementation(class_getInstanceMethod(NSClassFromString(@"CFPrefsPlistSource"), @selector(_isSharedInTheiOSSimulator)), (IMP)hook_return_false);
    }
    
    swizzle(NSUserDefaults.class, @selector(init), @selector(hook_init));
    swizzle(NSUserDefaults.class, @selector(persistentDomainForName:), @selector(hook_persistentDomainForName:));
    swizzle(NSUserDefaults.class, @selector(_initWithSuiteName:container:), @selector(hook__initWithSuiteName:container:));
    swizzle(NSUserDefaults.class, @selector(setPersistentDomain:forName:), @selector(hook_setPersistentDomain:forName:));
    
    // let lc itself bypass
    [NSUserDefaults.lcUserDefaults _setContainer:[NSURL URLWithString:@"/LiveContainer"]];
    [NSUserDefaults.lcSharedDefaults _setContainer:[NSURL URLWithString:@"/LiveContainer"]];
    [NSUserDefaults.standardUserDefaults _setContainer:appContainerURL];
    
    Class _CFXPreferencesClass = NSClassFromString(@"_CFXPreferences");

    swizzle2(_CFXPreferencesClass, @selector(copyAppValueForKey:identifier:container:configurationURL:), _CFXPreferences2.class, @selector(hook_copyAppValueForKey:identifier:container:configurationURL:));
    swizzle2(_CFXPreferencesClass, @selector(copyValueForKey:identifier:user:host:container:), _CFXPreferences2.class,  @selector(hook_copyValueForKey:identifier:user:host:container:));
    swizzle2(_CFXPreferencesClass, @selector(setValue:forKey:appIdentifier:container:configurationURL:), _CFXPreferences2.class, @selector(hook_setValue:forKey:appIdentifier:container:configurationURL:));
    
    #pragma clang diagnostic pop
    
    rebind_symbols((struct rebinding[1]){
        {"CFPreferencesCopyMultiple", (void *)hook_CFPreferencesCopyMultiple, (void **)&orig_CFPreferencesCopyMultiple},
    }, 1);
    
    // Create Library/Preferences folder in app's data folder in case it does not exist
    NSFileManager* fm = NSFileManager.defaultManager;
    NSURL* libraryPath = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL* preferenceFolderPath = [libraryPath URLByAppendingPathComponent:@"Preferences"];
    if(![fm fileExistsAtPath:preferenceFolderPath.path]) {
        NSError* error;
        [fm createDirectoryAtPath:preferenceFolderPath.path withIntermediateDirectories:YES attributes:@{} error:&error];
    }
    
    // Recover language when app is about to quit
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationWillTerminateNotification"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull notification) {
        // restore language if needed
        NSArray* savedLaunguage = [NSUserDefaults.lcUserDefaults objectForKey:@"LCLastLanguages"];
        if(savedLaunguage) {
            [NSUserDefaults.lcUserDefaults setObject:savedLaunguage forKey:@"AppleLanguages"];
        }
    }];
    
    
}


@implementation NSUserDefaults(LiveContainerHooks)

- (instancetype)hook_init {
    NSUserDefaults* nud = [self hook_init];
    [nud _setContainer:appContainerURL];
    return nud;
}

- (instancetype)hook__initWithSuiteName:(NSString*)suiteName container:(NSURL*)container {
    if(!suiteName) {
        return NSUserDefaults.standardUserDefaults;
    }
    
    return [self hook__initWithSuiteName:suiteName container:appContainerURL];
}

- (NSDictionary*) hook_persistentDomainForName:(NSString*)domainName {
    NSUserDefaults* nud = [[NSUserDefaults alloc] initWithSuiteName:domainName];
    return [nud dictionaryRepresentation];
}

- (void)hook_setPersistentDomain:(NSDictionary*)domain forName:(NSString*)domainName {
    NSUserDefaults* nud = [[NSUserDefaults alloc] initWithSuiteName:domainName];
    
    if(!domain) {
        NSDictionary* dict = [nud dictionaryRepresentation];
        for(NSString* key in dict) {
            [nud removeObjectForKey:key];
        }
        return;
    }

    for(NSString* key in domain) {
        NSObject* obj = domain[key];
        [nud setObject:obj forKey:key];
    }
}

@end


@implementation _CFXPreferences2

-(CFPropertyListRef)hook_copyAppValueForKey:(CFStringRef)key identifier:(CFStringRef)identifier container:(CFStringRef)container configurationURL:(CFURLRef)configurationURL {
    // let lc itself bypass
    if(container && CFStringCompare(container, CFSTR("/LiveContainer"), 0) == kCFCompareEqualTo) {
        return [self hook_copyAppValueForKey:key identifier:identifier container:nil configurationURL:configurationURL];
    } else {
        container = (__bridge CFStringRef)appContainerPath;
    }
    if(identifier == kCFPreferencesCurrentApplication) {
        identifier = (__bridge CFStringRef)NSUserDefaults.lcGuestAppId;
    }
    
    return [self hook_copyAppValueForKey:key identifier:identifier container:container configurationURL:configurationURL];
}

-(CFPropertyListRef)hook_copyValueForKey:(CFStringRef)key identifier:(CFStringRef)identifier user:(CFStringRef)user host:(CFStringRef)host container:(CFStringRef)container {
    if(container && CFStringCompare(container, CFSTR("/LiveContainer"), 0) == kCFCompareEqualTo) {
        return [self hook_copyValueForKey:key identifier:identifier user:user host:host container:nil];
    } else {
        container = (__bridge CFStringRef)appContainerPath;
    }
    if(identifier == kCFPreferencesCurrentApplication) {
        identifier = (__bridge CFStringRef)NSUserDefaults.lcGuestAppId;
    }
    return [self hook_copyValueForKey:key identifier:identifier user:user host:host container:container];
}

-(void)hook_setValue:(CFPropertyListRef)value forKey:(CFStringRef)key appIdentifier:(CFStringRef)appIdentifier container:(CFStringRef)container configurationURL:(CFURLRef)configurationURL {
    // let lc itself bypass
    // if(appIdentifier && CFStringHasPrefix(appIdentifier, CFSTR("com.kdt"))) {
    if(container && CFStringCompare(container, CFSTR("/LiveContainer"), 0) == kCFCompareEqualTo) {
        return [self hook_setValue:value forKey:key appIdentifier:appIdentifier container:nil configurationURL:configurationURL];
    } else {
        container = (__bridge CFStringRef)appContainerPath;
    }
    
    if(appIdentifier == kCFPreferencesCurrentApplication) {
        appIdentifier = (__bridge CFStringRef)NSUserDefaults.lcGuestAppId;
    }
    
    return [self hook_setValue:value forKey:key appIdentifier:appIdentifier container:container configurationURL:configurationURL];
}

@end

CFDictionaryRef hook_CFPreferencesCopyMultiple(CFArrayRef keysToFetch, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName) {
    NSUserDefaults* nud = [[NSUserDefaults alloc] initWithSuiteName:(__bridge NSString*)applicationID];
    return (__bridge CFDictionaryRef)[nud dictionaryRepresentation];
}
