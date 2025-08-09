#import "Network+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import <Network/Network.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "../utils.h"
#import "../../fishhook/fishhook.h"

#pragma mark - Global State (Keep Existing Variables)

static BOOL proxyEnabled = NO;
static NSString *proxyHost = nil;
static NSInteger proxyPort = 1080;
static NSString *proxyUsername = nil;
static NSString *proxyPassword = nil;

#pragma mark - nx-Style Function Pointers

// Network path function pointers (nx pattern)
static void *orig_nw_path_copy_proxy_settings = NULL;
static void *orig_nw_path_copy_proxy_configs = NULL;
static void *orig_nw_path_should_use_proxy = NULL;

// CFNetwork function pointers
static CFDictionaryRef (*orig_CFNetworkCopySystemProxySettings)(void) = NULL;

#pragma mark - Configuration Loading (Keep Your Pattern)

static void loadProxyConfiguration(void) {
    static BOOL hasLoaded = NO;
    if (hasLoaded) return;
    
    NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
    if (!guestAppInfo) {
        proxyEnabled = NO;
        hasLoaded = YES;
        return;
    }

    proxyEnabled = [guestAppInfo[@"spoofNetwork"] boolValue];
    proxyHost = [guestAppInfo[@"proxyHost"] copy] ?: @"";
    proxyPort = [guestAppInfo[@"proxyPort"] integerValue] ?: 1080;
    proxyUsername = [guestAppInfo[@"proxyUsername"] copy] ?: @"";
    proxyPassword = [guestAppInfo[@"proxyPassword"] copy] ?: @"";

    NSLog(@"[LC] 🔗 Proxy Config: Enabled=%d, Host=%@, Port=%ld", 
          proxyEnabled, proxyHost, (long)proxyPort);
    
    hasLoaded = YES;
}

#pragma mark - nx-Style Proxy Dictionary

static NSDictionary *createProxyDictionary(void) {
    if (!proxyEnabled || proxyHost.length == 0 || proxyPort == 0) {
        return nil;
    }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    // SOCKS5 configuration (nx pattern)
    dict[@"SOCKSEnable"] = @YES;
    dict[@"SOCKSProxy"] = proxyHost;
    dict[@"SOCKSPort"] = @(proxyPort);
    dict[@"SOCKSVersion"] = @5;
    
    // Authentication (if provided)
    if (proxyUsername.length > 0) {
        dict[@"SOCKSUsername"] = proxyUsername;
    }
    
    if (proxyPassword.length > 0) {
        dict[@"SOCKSPassword"] = proxyPassword;
    }
    
    return [dict copy];
}

#pragma mark - nx-Style Network Path Hooks

static xpc_object_t hook_nw_path_copy_proxy_settings(void) {
    NSDictionary *proxyDict = createProxyDictionary();
    if (!proxyDict) {
        return orig_nw_path_copy_proxy_settings ? 
               ((xpc_object_t(*)(void))orig_nw_path_copy_proxy_settings)() : NULL;
    }
    
    xpc_object_t settings = xpc_dictionary_create(NULL, NULL, 0);
    
    // SOCKS5 configuration (nx pattern)
    xpc_dictionary_set_bool(settings, "SOCKSEnable", true);
    xpc_dictionary_set_string(settings, "SOCKSProxy", [proxyHost UTF8String]);
    xpc_dictionary_set_int64(settings, "SOCKSPort", proxyPort);
    xpc_dictionary_set_int64(settings, "SOCKSVersion", 5);
    
    // Authentication
    if (proxyUsername.length > 0) {
        xpc_dictionary_set_string(settings, "SOCKSUsername", [proxyUsername UTF8String]);
    }
    
    if (proxyPassword.length > 0) {
        xpc_dictionary_set_string(settings, "SOCKSPassword", [proxyPassword UTF8String]);
    }
    
    return settings;
}

static xpc_object_t hook_nw_path_copy_proxy_configs(void *path) {
    NSDictionary *proxyDict = createProxyDictionary();
    if (!proxyDict) {
        return orig_nw_path_copy_proxy_configs ? 
               ((xpc_object_t(*)(void*))orig_nw_path_copy_proxy_configs)(path) : NULL;
    }
    
    xpc_object_t config = xpc_dictionary_create(NULL, NULL, 0);
    
    // SOCKS5 configuration (nx pattern)
    xpc_dictionary_set_bool(config, "SOCKSEnable", true);
    xpc_dictionary_set_string(config, "SOCKSProxy", [proxyHost UTF8String]);
    xpc_dictionary_set_int64(config, "SOCKSPort", proxyPort);
    xpc_dictionary_set_int64(config, "SOCKSVersion", 5);
    
    // Authentication
    if (proxyUsername.length > 0) {
        xpc_dictionary_set_string(config, "SOCKSUsername", [proxyUsername UTF8String]);
    }
    
    if (proxyPassword.length > 0) {
        xpc_dictionary_set_string(config, "SOCKSPassword", [proxyPassword UTF8String]);
    }
    
    // Create array with single config (nx pattern)
    xpc_object_t configs = xpc_array_create(NULL, 0);
    xpc_array_append_value(configs, config);
    
    return configs;
}

static bool hook_nw_path_should_use_proxy(void *path, void *endpoint) {
    if (!proxyEnabled) {
        return orig_nw_path_should_use_proxy ? 
               ((bool(*)(void*, void*))orig_nw_path_should_use_proxy)(path, endpoint) : false;
    }
    
    // Always use proxy when enabled (nx pattern)
    return true;
}

#pragma mark - nx-Style CFNetwork Hook

static CFDictionaryRef hook_CFNetworkCopySystemProxySettings(void) {
    NSDictionary *proxyDict = createProxyDictionary();
    if (!proxyDict) {
        return orig_CFNetworkCopySystemProxySettings ? 
               orig_CFNetworkCopySystemProxySettings() : NULL;
    }
    
    // Return SOCKS5 proxy settings (nx pattern)
    return CFBridgingRetain(proxyDict);
}

#pragma mark - nx-Style NSURLSession Hooks

@implementation NSURLSession(nxProxy)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Hook all session creation methods (nx pattern)
        swizzle([NSURLSession class], @selector(sessionWithConfiguration:), @selector(nx_sessionWithConfiguration:));
        swizzle([NSURLSession class], @selector(sessionWithConfiguration:delegate:delegateQueue:), @selector(nx_sessionWithConfiguration:delegate:delegateQueue:));
        swizzle([NSURLSession class], @selector(sharedSession), @selector(nx_sharedSession));
        
        // Hook configuration creation (critical for universal coverage)
        swizzle([NSURLSessionConfiguration class], @selector(defaultSessionConfiguration), @selector(nx_defaultSessionConfiguration));
        swizzle([NSURLSessionConfiguration class], @selector(ephemeralSessionConfiguration), @selector(nx_ephemeralSessionConfiguration));
    });
}

+ (NSURLSessionConfiguration *)nx_defaultSessionConfiguration {
    NSURLSessionConfiguration *config = [self nx_defaultSessionConfiguration];
    [self applynxProxyToConfiguration:config];
    return config;
}

+ (NSURLSessionConfiguration *)nx_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = [self nx_ephemeralSessionConfiguration];
    [self applynxProxyToConfiguration:config];
    return config;
}

+ (NSURLSession *)nx_sharedSession {
    return [self nx_sharedSession];
}

+ (NSURLSession *)nx_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    [self applynxProxyToConfiguration:configuration];
    return [self nx_sessionWithConfiguration:configuration];
}

+ (NSURLSession *)nx_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration 
                                        delegate:(id<NSURLSessionDelegate>)delegate 
                                   delegateQueue:(NSOperationQueue *)queue {
    [self applynxProxyToConfiguration:configuration];
    return [self nx_sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}

+ (void)applynxProxyToConfiguration:(NSURLSessionConfiguration *)configuration {
    if (!proxyEnabled) return;
    
    NSDictionary *proxyDict = createProxyDictionary();
    if (!proxyDict) return;
    
    configuration.connectionProxyDictionary = proxyDict;
    
    // nx-style networking optimizations
    configuration.waitsForConnectivity = YES;
    configuration.allowsCellularAccess = YES;
    configuration.timeoutIntervalForRequest = 60.0;
    configuration.timeoutIntervalForResource = 300.0;
    configuration.HTTPMaximumConnectionsPerHost = 6;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
}

@end

#pragma mark - nx-Style Proxy Manager

@interface nxProxyManager : NSObject
+ (void)loadProxyConfig;
+ (NSString *)host;
+ (NSNumber *)port;
+ (NSString *)username;
+ (NSString *)password;
+ (BOOL)socksProxy;
+ (NSDictionary *)proxyDictionary;
+ (void)setProxy;
@end

@implementation nxProxyManager

+ (void)loadProxyConfig {
    loadProxyConfiguration();
}

+ (NSString *)host {
    return proxyHost ?: @"";
}

+ (NSNumber *)port {
    return @(proxyPort);
}

+ (NSString *)username {
    return proxyUsername ?: @"";
}

+ (NSString *)password {
    return proxyPassword ?: @"";
}

+ (BOOL)socksProxy {
    return YES; // Always SOCKS5 (nx pattern)
}

+ (NSDictionary *)proxyDictionary {
    return createProxyDictionary();
}

+ (void)setProxy {
    NSDictionary *proxyDict = [self proxyDictionary];
    if (!proxyDict) {
        NSLog(@"[LC] 📡 No proxy configuration to set");
        return;
    }
    
    // Set system proxy override (nx pattern)
    CFDictionaryRef cfDict = (__bridge CFDictionaryRef)proxyDict;
    if (cfDict) {
        // Use private CFNetwork function (nx style)
        void (*setOverride)(CFDictionaryRef) = dlsym(RTLD_DEFAULT, "_CFNetworkSetOverrideSystemProxySettings");
        if (setOverride) {
            setOverride(cfDict);
            NSLog(@"[LC] ✅ System proxy override set (nx pattern)");
        }
    }
}

@end

#pragma mark - nx-Style Initialization

void NetworkGuestHooksInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[LC] 🚀 Initializing nx-style network proxy system...");
        
        loadProxyConfiguration();
        
        if (!proxyEnabled) {
            NSLog(@"[LC] 📶 Network proxy disabled");
            return;
        }
        
        NSLog(@"[LC] 🔗 Network proxy enabled: %@:%ld", proxyHost, (long)proxyPort);
        
        // Hook network path functions (nx pattern)
        void *libnetwork = dlopen("/usr/lib/libnetwork.dylib", RTLD_LAZY);
        if (libnetwork) {
            orig_nw_path_copy_proxy_settings = dlsym(libnetwork, "nw_path_copy_proxy_settings");
            orig_nw_path_copy_proxy_configs = dlsym(libnetwork, "nw_path_copy_proxy_configs");
            orig_nw_path_should_use_proxy = dlsym(libnetwork, "nw_path_should_use_proxy");
            
            // Install network path hooks
            if (orig_nw_path_copy_proxy_settings) {
                rebind_symbols((struct rebinding[1]){
                    {"nw_path_copy_proxy_settings", (void *)hook_nw_path_copy_proxy_settings, (void **)&orig_nw_path_copy_proxy_settings},
                }, 1);
            }
            
            if (orig_nw_path_copy_proxy_configs) {
                rebind_symbols((struct rebinding[1]){
                    {"nw_path_copy_proxy_configs", (void *)hook_nw_path_copy_proxy_configs, (void **)&orig_nw_path_copy_proxy_configs},
                }, 1);
            }
            
            if (orig_nw_path_should_use_proxy) {
                rebind_symbols((struct rebinding[1]){
                    {"nw_path_should_use_proxy", (void *)hook_nw_path_should_use_proxy, (void **)&orig_nw_path_should_use_proxy},
                }, 1);
            }
            
            NSLog(@"[LC] ✅ Network path function hooks installed (nx pattern)");
        }
        
        // Hook CFNetwork functions (nx pattern)
        void *cfnetwork = dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork", RTLD_LAZY);
        if (cfnetwork) {
            orig_CFNetworkCopySystemProxySettings = dlsym(cfnetwork, "CFNetworkCopySystemProxySettings");
            
            if (orig_CFNetworkCopySystemProxySettings) {
                rebind_symbols((struct rebinding[1]){
                    {"CFNetworkCopySystemProxySettings", (void *)hook_CFNetworkCopySystemProxySettings, (void **)&orig_CFNetworkCopySystemProxySettings},
                }, 1);
                
                NSLog(@"[LC] ✅ CFNetwork hooks installed (nx pattern)");
            }
        }
        
        // Set system proxy override (nx pattern)
        [nxProxyManager setProxy];
        
        NSLog(@"[LC] ✅ nx-style network proxy system initialized");
        NSLog(@"[LC] 🔗 Features: SOCKS5-only, System override, Universal coverage");
        NSLog(@"[LC] 📱 Proxy: %@:%ld %@", proxyHost, (long)proxyPort, 
              (proxyUsername.length > 0) ? @"(with auth)" : @"(no auth)");
    });
}