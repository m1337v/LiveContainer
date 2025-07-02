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

NSMutableDictionary* LCPreferences = 0;

CFDictionaryRef hook_CFPreferencesCopyMultiple(CFArrayRef keysToFetch, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName);
CFDictionaryRef (*orig_CFPreferencesCopyMultiple)(CFArrayRef keysToFetch, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName);

void NUDGuestHooksInit(void) {
    // fix for macOS host
    if(access("/Users", F_OK) == 0) {
        method_setImplementation(class_getInstanceMethod(NSClassFromString(@"CFPrefsPlistSource"), @selector(_isSharedInTheiOSSimulator)), (IMP)hook_return_false);
    }
    
    swizzle(NSUserDefaults.class, @selector(objectForKey:), @selector(hook_objectForKey:));
    swizzle(NSUserDefaults.class, @selector(boolForKey:), @selector(hook_boolForKey:));
    swizzle(NSUserDefaults.class, @selector(integerForKey:), @selector(hook_integerForKey:));
    swizzle(NSUserDefaults.class, @selector(setObject:forKey:), @selector(hook_setObject:forKey:));
    swizzle(NSUserDefaults.class, @selector(removeObjectForKey:), @selector(hook_removeObjectForKey:));
    swizzle(NSUserDefaults.class, @selector(dictionaryRepresentation), @selector(hook_dictionaryRepresentation));
    swizzle(NSUserDefaults.class, @selector(persistentDomainForName:), @selector(hook_persistentDomainForName:));
    swizzle(NSUserDefaults.class, @selector(removePersistentDomainForName:), @selector(hook_removePersistentDomainForName:));
    swizzle(NSUserDefaults.class, @selector(setPersistentDomain:forName:), @selector(hook_setPersistentDomain:forName:));
    
    // let lc itself bypass
    [NSUserDefaults.lcUserDefaults _setContainer:[NSURL URLWithString:@"/LiveContainer"]];
    [NSUserDefaults.lcSharedDefaults _setContainer:[NSURL URLWithString:@"/LiveContainer"]];
    
    Class _CFXPreferencesClass = NSClassFromString(@"_CFXPreferences");

    swizzle2(_CFXPreferencesClass, @selector(copyAppValueForKey:identifier:container:configurationURL:), _CFXPreferences2.class, @selector(hook_copyAppValueForKey:identifier:container:configurationURL:));
    swizzle2(_CFXPreferencesClass, @selector(copyValueForKey:identifier:user:host:container:), _CFXPreferences2.class,  @selector(hook_copyValueForKey:identifier:user:host:container:));
    swizzle2(_CFXPreferencesClass, @selector(setValue:forKey:appIdentifier:container:configurationURL:), _CFXPreferences2.class, @selector(hook_setValue:forKey:appIdentifier:container:configurationURL:));

    rebind_symbols((struct rebinding[1]){
        {"CFPreferencesCopyMultiple", (void *)hook_CFPreferencesCopyMultiple, (void **)&orig_CFPreferencesCopyMultiple},
    }, 1);
    
    LCPreferences = [[NSMutableDictionary alloc] init];
    NSFileManager* fm = NSFileManager.defaultManager;
    NSURL* libraryPath = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL* preferenceFolderPath = [libraryPath URLByAppendingPathComponent:@"Preferences"];
    if(![fm fileExistsAtPath:preferenceFolderPath.path]) {
        NSError* error;
        [fm createDirectoryAtPath:preferenceFolderPath.path withIntermediateDirectories:YES attributes:@{} error:&error];
    }
    
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

NSURL* LCGetPreferencePath(NSString* identifier) {
    NSFileManager* fm = NSFileManager.defaultManager;
    NSURL* libraryPath = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL* preferenceFilePath = [libraryPath URLByAppendingPathComponent:[NSString stringWithFormat: @"Preferences/%@.plist", identifier]];
    return preferenceFilePath;
}

NSMutableDictionary* LCGetPreference(NSString* identifier) {
    if(LCPreferences[identifier]) {
        return LCPreferences[identifier];
    }
    NSURL* preferenceFilePath = LCGetPreferencePath(identifier);
    if([NSFileManager.defaultManager fileExistsAtPath:preferenceFilePath.path]) {
        LCPreferences[identifier] = [NSMutableDictionary dictionaryWithContentsOfFile:preferenceFilePath.path];
        return LCPreferences[identifier];
    } else {
        return nil;
    }
    
}

// save preference to livecontainer's user default
void LCSavePreference(void) {
    NSString* containerId = [[NSString stringWithUTF8String:getenv("HOME")] lastPathComponent];
    [NSUserDefaults.lcUserDefaults setObject:LCPreferences forKey:containerId];
}

@implementation NSUserDefaults(LiveContainerHooks)

- (NSString*)realIdentifier {
    NSString* identifier = [self _identifier];
    if([identifier hasPrefix:@"com.kdt.livecontainer"]) {
        return NSUserDefaults.standardUserDefaults._identifier;
    } else {
        return identifier;
    }
}

- (id)hook_objectForKey:(NSString*)key {
    // let LiveContainer itself bypass
    NSString* identifier = [self realIdentifier];
    if(self == [NSUserDefaults lcUserDefaults]) {
        return [self hook_objectForKey:key];
    }
    
    // priortize local preference file over values in native NSUserDefaults
    NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
    if(preferenceDict && preferenceDict[key]) {
        return preferenceDict[key];
    } else {
        return [self hook_objectForKey:key];
    }
}

- (BOOL)hook_boolForKey:(NSString*)key {
    id obj = [self objectForKey:key];
    if(!obj) {
        return NO;
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        return [(NSNumber*)obj boolValue];
    } else if([obj isKindOfClass:[NSString class]]) {
        NSString* lowered = [(NSString*)obj lowercaseString];
        if([lowered isEqualToString:@"yes"] || [lowered isEqualToString:@"true"] || [lowered boolValue]) {
            return YES;
        } else {
            return NO;
        }
    } else {
        return obj != 0;
    }
    
}

- (NSInteger)hook_integerForKey:(NSString*)key {
    id obj = [self objectForKey:key];
    if(!obj) {
        return 0;
    } else if([obj isKindOfClass:[NSString class]]) {
        return [(NSString*)obj integerValue];
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        return [(NSNumber*)obj integerValue];
    }
    return 0;
}

- (void)hook_setObject:(id)obj forKey:(NSString*)key {
    // let LiveContainer itself bypess
    NSString* identifier = [self realIdentifier];
    if(self == [NSUserDefaults lcUserDefaults]) {
        return [self hook_setObject:obj forKey:key];
    }
    @synchronized (LCPreferences) {
        NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
        if(!preferenceDict) {
            preferenceDict = [[NSMutableDictionary alloc] init];
            LCPreferences[identifier] = preferenceDict;
        }
        if(![preferenceDict[key] isEqual:obj]) {
            [self willChangeValueForKey:key];
            preferenceDict[key] = obj;
            LCSavePreference();
            [self didChangeValueForKey:key];
            [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];
        }

    }
}

- (void)hook_removeObjectForKey:(NSString*)key {
    NSString* identifier = [self realIdentifier];
    if([self hook_objectForKey:key]) {
        [self hook_removeObjectForKey:key];
        return;
    }
    @synchronized (LCPreferences) {
        NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
        if(!preferenceDict) {
            return;
        }
        if(preferenceDict[key]) {
            [self willChangeValueForKey:key];
            [preferenceDict removeObjectForKey:key];
            LCSavePreference();
            [self didChangeValueForKey:key];
            [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];
        }
    }
}

- (NSDictionary*) hook_dictionaryRepresentation {
    NSString* identifier = [self realIdentifier];
    NSMutableDictionary* ans = [[self hook_dictionaryRepresentation] mutableCopy];
    if(ans) {
        @synchronized (LCPreferences) {
            [ans addEntriesFromDictionary:LCGetPreference(identifier)];
        }
    } else {
        ans = LCGetPreference(identifier);
    }
    return ans;
    
}

- (NSDictionary*) hook_persistentDomainForName:(NSString*)domainName {
    if([domainName hasPrefix:@"com.kdt.livecontainer"]) {
        domainName = NSUserDefaults.standardUserDefaults._identifier;
    }
    
    NSMutableDictionary* ans = [[self hook_persistentDomainForName:domainName] mutableCopy];
    if(ans) {
        @synchronized (LCPreferences) {
            [ans addEntriesFromDictionary:LCGetPreference(domainName)];
        }
    } else {
        ans = LCGetPreference(domainName);
    }
    return ans;
    
}

- (void) hook_setPersistentDomain:(NSDictionary*)domain forName:(NSString*)domainName {
    if([domainName hasPrefix:@"com.kdt.livecontainer"]) {
        domainName = NSUserDefaults.standardUserDefaults._identifier;
    }
    @synchronized (LCPreferences) {
        NSMutableDictionary* preferenceDict = LCGetPreference(domainName);
        if(!preferenceDict) {
            preferenceDict = [[NSMutableDictionary alloc] init];
            LCPreferences[domainName] = preferenceDict;
        }
        for(NSString* key in domain) {
            NSObject* obj = domain[key];
            if(![preferenceDict[key] isEqual:obj]) {
                [self willChangeValueForKey:key];
                preferenceDict[key] = obj;
                [self didChangeValueForKey:key];
                [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];
            }
        }
        LCSavePreference();
    }
}

- (void) hook_removePersistentDomainForName:(NSString*)domainName {
    NSMutableDictionary* ans = [[self hook_persistentDomainForName:domainName] mutableCopy];
    @synchronized (LCPreferences) {
        if(ans) {
            [self hook_removePersistentDomainForName:domainName];
        } else {
            // empty dictionary means deletion
            [LCPreferences setObject:[[NSMutableDictionary alloc] init] forKey:domainName];
            LCSavePreference();
        }
        NSURL* preferenceFilePath = LCGetPreferencePath(domainName);
        NSFileManager* fm = NSFileManager.defaultManager;
        if([fm fileExistsAtPath:preferenceFilePath.path]) {
            NSError* error;
            [fm removeItemAtURL:preferenceFilePath error:&error];
        }
    }
}

@end


// save preference to livecontainer's user default
void LCSavePreference2(_CFXPreferences2* pref) {
    NSString* containerId = [[NSString stringWithUTF8String:getenv("HOME")] lastPathComponent];
    [pref hook_setValue:(__bridge CFDictionaryRef)LCPreferences forKey:(__bridge CFStringRef)containerId appIdentifier:kCFPreferencesCurrentApplication container:nil configurationURL:nil];
}


@implementation _CFXPreferences2

-(CFPropertyListRef)hook_copyAppValueForKey:(CFStringRef)key identifier:(CFStringRef)identifier container:(CFStringRef)container configurationURL:(CFURLRef)configurationURL {
    // let lc itself bypass
    if(container && CFStringCompare(container, CFSTR("/LiveContainer"), 0) == kCFCompareEqualTo) {
        return [self hook_copyAppValueForKey:key identifier:identifier container:nil configurationURL:configurationURL];
    }
    if(identifier == kCFPreferencesCurrentApplication) {
        identifier = (__bridge CFStringRef)NSUserDefaults.lcGuestAppId;
    }
    
    NSMutableDictionary* preferenceDict = LCGetPreference((__bridge NSString*)identifier);
    if(preferenceDict && preferenceDict[(__bridge NSString*)key]) {
        return CFPropertyListCreateDeepCopy(nil, CFDictionaryGetValue((__bridge CFDictionaryRef)preferenceDict, key), 0);
    } else {
        return [self hook_copyAppValueForKey:key identifier:identifier container:container configurationURL:configurationURL];
    }
}

-(CFPropertyListRef)hook_copyValueForKey:(CFStringRef)key identifier:(CFStringRef)identifier user:(CFStringRef)user host:(CFStringRef)host container:(CFStringRef)container {
    if(identifier == kCFPreferencesCurrentApplication) {
        identifier = (__bridge CFStringRef)NSUserDefaults.lcGuestAppId;
    }
    NSMutableDictionary* preferenceDict = LCGetPreference((__bridge NSString*)identifier);
    if(preferenceDict && preferenceDict[(__bridge NSString*)key]) {
        return CFPropertyListCreateDeepCopy(nil, CFDictionaryGetValue((__bridge CFDictionaryRef)preferenceDict, key), 0);
    } else {
        return [self hook_copyValueForKey:key identifier:identifier user:user host:host container:container];
    }
    
}

-(void)hook_setValue:(CFPropertyListRef)value forKey:(CFStringRef)key appIdentifier:(CFStringRef)appIdentifier container:(CFStringRef)container configurationURL:(CFURLRef)configurationURL {
    // let lc itself bypass
    if(container && CFStringCompare(container, CFSTR("/LiveContainer"), 0) == kCFCompareEqualTo) {
        return [self hook_setValue:value forKey:key appIdentifier:appIdentifier container:nil configurationURL:configurationURL];
    }
    
    if(appIdentifier == kCFPreferencesCurrentApplication) {
        appIdentifier = (__bridge CFStringRef)NSUserDefaults.lcGuestAppId;
    }
    
    @synchronized (LCPreferences) {
        NSMutableDictionary* preferenceDict = LCGetPreference((__bridge NSString*)appIdentifier);
        if(!preferenceDict) {
            preferenceDict = [[NSMutableDictionary alloc] init];
            LCPreferences[(__bridge NSString*)appIdentifier] = preferenceDict;
        }
        if(!value) {
            [preferenceDict removeObjectForKey:(__bridge NSString*)key];
            LCSavePreference2(self);
            return;
        }
        CFTypeRef cur = CFDictionaryGetValue((__bridge CFDictionaryRef)preferenceDict, key);
        
        if(!cur || !CFEqual(cur, value)) {
            CFDictionarySetValue((__bridge CFMutableDictionaryRef)preferenceDict, key, value);
            LCSavePreference2(self);
        }

    }
}

@end

CFDictionaryRef hook_CFPreferencesCopyMultiple(CFArrayRef keysToFetch, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName) {
    NSMutableDictionary* preferenceDict = LCGetPreference((__bridge NSString*)applicationID);
    if(preferenceDict) {
        return CFDictionaryCreateCopy(nil, (__bridge CFDictionaryRef)preferenceDict);
    } else {
        return orig_CFPreferencesCopyMultiple(keysToFetch, applicationID, userName, hostName);
    }
}
