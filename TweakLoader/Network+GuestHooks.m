#import "Network+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import <objc/runtime.h>
#import "utils.h"

// Global state (following iOS-compatible pattern)
static BOOL spoofNetworkEnabled = NO;
static NSString *proxyType = @"HTTP";
static NSString *proxyHost = @"";
static int proxyPort = 8080;
static NSString *proxyUsername = @"";
static NSString *proxyPassword = @"";
static NSString *networkMode = @"standard";

// Per-app configuration
static NSMutableDictionary *appProxyConfigs = nil;

#pragma mark - Configuration Loading

static void loadNetworkConfiguration(void) {
    NSLog(@"[LC] Loading network spoofing configuration...");
    
    NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
    if (!guestAppInfo) {
        NSLog(@"[LC] ❌ No guestAppInfo found for network config");
        spoofNetworkEnabled = NO;
        return;
    }

    spoofNetworkEnabled = [guestAppInfo[@"spoofNetwork"] boolValue];
    proxyType = guestAppInfo[@"proxyType"] ?: @"HTTP";
    proxyHost = guestAppInfo[@"proxyHost"] ?: @"";
    proxyPort = [guestAppInfo[@"proxyPort"] intValue] ?: 8080;
    proxyUsername = guestAppInfo[@"proxyUsername"] ?: @"";
    proxyPassword = guestAppInfo[@"proxyPassword"] ?: @"";
    networkMode = guestAppInfo[@"spoofNetworkMode"] ?: @"standard";

    NSLog(@"[LC] ⚙️ Network Config: Enabled=%d, Type=%@, Host=%@, Port=%d, Mode=%@", 
          spoofNetworkEnabled, proxyType, proxyHost, proxyPort, networkMode);
}

#pragma mark - Proxy Dictionary Creation (iOS-compatible)

static NSDictionary *createProxyDictionary(void) {
    if (!spoofNetworkEnabled || !proxyHost || proxyHost.length == 0) {
        return nil;
    }
    
    NSMutableDictionary *proxyDict = [NSMutableDictionary dictionary];
    
    if ([proxyType isEqualToString:@"HTTP"]) {
        // HTTP Proxy Configuration (iOS-compatible)
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @YES;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPProxy] = proxyHost;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPPort] = @(proxyPort);
        
        // Note: HTTPS proxy constants are not available on iOS
        // The HTTP proxy will handle HTTPS connections as well
        
    } else if ([proxyType isEqualToString:@"SOCKS5"]) {
        // SOCKS proxy is not directly supported via CFNetwork on iOS
        // Fall back to HTTP proxy
        NSLog(@"[LC] ⚠️ SOCKS5 not directly supported on iOS, falling back to HTTP proxy");
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @YES;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPProxy] = proxyHost;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPPort] = @(proxyPort);
        
    } else if ([proxyType isEqualToString:@"DIRECT"]) {
        // Direct connection (bypass proxy)
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @NO;
    }
    
    NSLog(@"[LC] 🔗 Created iOS-compatible proxy dictionary: %@", proxyDict);
    return [proxyDict copy];
}

#pragma mark - NSURLSession Hooks

@implementation NSURLSession(LiveContainerProxy)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Hook session creation methods
        swizzle([NSURLSession class], @selector(sessionWithConfiguration:), @selector(lc_sessionWithConfiguration:));
        swizzle([NSURLSession class], @selector(sessionWithConfiguration:delegate:delegateQueue:), @selector(lc_sessionWithConfiguration:delegate:delegateQueue:));
    });
}

+ (NSURLSession *)lc_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    if (spoofNetworkEnabled) {
        NSLog(@"[LC] 🔗 Applying proxy to NSURLSession configuration");
        [self applyProxyToConfiguration:configuration];
    }
    return [self lc_sessionWithConfiguration:configuration];
}

+ (NSURLSession *)lc_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration 
                                     delegate:(id<NSURLSessionDelegate>)delegate 
                                delegateQueue:(NSOperationQueue *)queue {
    if (spoofNetworkEnabled) {
        NSLog(@"[LC] 🔗 Applying proxy to NSURLSession configuration with delegate");
        [self applyProxyToConfiguration:configuration];
    }
    return [self lc_sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}

+ (void)applyProxyToConfiguration:(NSURLSessionConfiguration *)configuration {
    NSDictionary *proxyDict = createProxyDictionary();
    if (proxyDict) {
        configuration.connectionProxyDictionary = proxyDict;
        
        // Additional configuration improvements
        configuration.timeoutIntervalForRequest = 30.0;  // 30 second timeout
        configuration.timeoutIntervalForResource = 300.0; // 5 minute resource timeout
        configuration.waitsForConnectivity = YES;
        
        // Add custom headers if needed
        if (proxyUsername.length > 0 && proxyPassword.length > 0) {
            NSString *credentials = [NSString stringWithFormat:@"%@:%@", proxyUsername, proxyPassword];
            NSData *credentialsData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
            NSString *base64Credentials = [credentialsData base64EncodedStringWithOptions:0];
            
            NSMutableDictionary *headers = [configuration.HTTPAdditionalHeaders mutableCopy] ?: [NSMutableDictionary dictionary];
            headers[@"Proxy-Authorization"] = [NSString stringWithFormat:@"Basic %@", base64Credentials];
            configuration.HTTPAdditionalHeaders = headers;
        }
        
        NSLog(@"[LC] ✅ Proxy applied to NSURLSession configuration");
    }
}

@end

#pragma mark - NSURLSessionConfiguration Hooks

@implementation NSURLSessionConfiguration(LiveContainerProxy)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Hook configuration factory methods
        swizzle([NSURLSessionConfiguration class], @selector(defaultSessionConfiguration), @selector(lc_defaultSessionConfiguration));
        swizzle([NSURLSessionConfiguration class], @selector(ephemeralSessionConfiguration), @selector(lc_ephemeralSessionConfiguration));
        swizzle([NSURLSessionConfiguration class], @selector(backgroundSessionConfigurationWithIdentifier:), @selector(lc_backgroundSessionConfigurationWithIdentifier:));
    });
}

+ (NSURLSessionConfiguration *)lc_defaultSessionConfiguration {
    NSURLSessionConfiguration *config = [self lc_defaultSessionConfiguration];
    if (spoofNetworkEnabled) {
        NSLog(@"[LC] 🔗 Applying proxy to default session configuration");
        [NSURLSession applyProxyToConfiguration:config];
    }
    return config;
}

+ (NSURLSessionConfiguration *)lc_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = [self lc_ephemeralSessionConfiguration];
    if (spoofNetworkEnabled) {
        NSLog(@"[LC] 🔗 Applying proxy to ephemeral session configuration");
        [NSURLSession applyProxyToConfiguration:config];
    }
    return config;
}

+ (NSURLSessionConfiguration *)lc_backgroundSessionConfigurationWithIdentifier:(NSString *)identifier {
    NSURLSessionConfiguration *config = [self lc_backgroundSessionConfigurationWithIdentifier:identifier];
    if (spoofNetworkEnabled) {
        NSLog(@"[LC] 🔗 Applying proxy to background session configuration");
        [NSURLSession applyProxyToConfiguration:config];
    }
    return config;
}

@end

#pragma mark - NSURLConnection Legacy Support

@implementation NSURLConnection(LiveContainerProxy)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ([networkMode isEqualToString:@"compatibility"]) {
            // Only hook legacy APIs in compatibility mode
            swizzle([NSURLConnection class], @selector(sendSynchronousRequest:returningResponse:error:), @selector(lc_sendSynchronousRequest:returningResponse:error:));
        }
    });
}

+ (NSData *)lc_sendSynchronousRequest:(NSURLRequest *)request 
                    returningResponse:(NSURLResponse **)response 
                                error:(NSError **)error {
    
    if (spoofNetworkEnabled) {
        NSLog(@"[LC] 🔗 Applying proxy to NSURLConnection (legacy)");
        
        // Create a new request with proxy settings
        NSMutableURLRequest *mutableRequest = [request mutableCopy];
        
        // Add proxy authentication headers if needed
        if (proxyUsername.length > 0 && proxyPassword.length > 0) {
            NSString *credentials = [NSString stringWithFormat:@"%@:%@", proxyUsername, proxyPassword];
            NSData *credentialsData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
            NSString *base64Credentials = [credentialsData base64EncodedStringWithOptions:0];
            
            [mutableRequest setValue:[NSString stringWithFormat:@"Basic %@", base64Credentials] 
                  forHTTPHeaderField:@"Proxy-Authorization"];
        }
        
        request = mutableRequest;
    }
    
    return [self lc_sendSynchronousRequest:request returningResponse:response error:error];
}

@end

#pragma mark - Initialization

void NetworkGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] 🚀 Initializing iOS-compatible network spoofing hooks...");
        
        loadNetworkConfiguration();
        
        if (!spoofNetworkEnabled) {
            NSLog(@"[LC] 📶 Network spoofing disabled");
            return;
        }
        
        NSLog(@"[LC] 🔗 Network spoofing enabled - Mode: %@, Proxy: %@://%@:%d", 
              networkMode, proxyType, proxyHost, proxyPort);
        
        // Initialize app-specific configurations
        appProxyConfigs = [[NSMutableDictionary alloc] init];
        
        NSLog(@"[LC] ✅ Network hooks initialized successfully");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Failed to initialize network hooks: %@", exception);
    }
}