#import "Network+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import <objc/runtime.h>
#import "utils.h"

// Global state (following Socker's configuration pattern)
static BOOL spoofNetworkEnabled = NO;
static NSString *proxyType = @"HTTP";
static NSString *proxyHost = @"";
static int proxyPort = 8080;
static NSString *proxyUsername = @"";
static NSString *proxyPassword = @"";
static NSString *networkMode = @"standard";

// Per-app configuration (like Socker's app-specific settings)
static NSMutableDictionary *appProxyConfigs = nil;

#pragma mark - Configuration Loading (adapted from Socker)

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

#pragma mark - Proxy Dictionary Creation (enhanced from Socker)

static NSDictionary *createProxyDictionary(void) {
    if (!spoofNetworkEnabled || !proxyHost || proxyHost.length == 0) {
        return nil;
    }
    
    NSMutableDictionary *proxyDict = [NSMutableDictionary dictionary];
    
    if ([proxyType isEqualToString:@"HTTP"]) {
        // HTTP Proxy Configuration (from Socker's approach)
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @YES;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPProxy] = proxyHost;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPPort] = @(proxyPort);
        
        // HTTPS proxy (usually same as HTTP)
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPSEnable] = @YES;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPSProxy] = proxyHost;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPSPort] = @(proxyPort);
        
    } else if ([proxyType isEqualToString:@"SOCKS5"]) {
        // Enhanced SOCKS5 Configuration (from Socker)
        proxyDict[(__bridge NSString *)kCFNetworkProxiesSOCKSEnable] = @YES;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesSOCKSProxy] = proxyHost;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesSOCKSPort] = @(proxyPort);
        proxyDict[(__bridge NSString *)kCFNetworkProxiesSOCKSVersion] = @5;
        
        // SOCKS5 Authentication (from Socker's implementation)
        if (proxyUsername.length > 0 && proxyPassword.length > 0) {
            proxyDict[(__bridge NSString *)kCFNetworkProxiesSOCKSUser] = proxyUsername;
            proxyDict[(__bridge NSString *)kCFNetworkProxiesSOCKSPassword] = proxyPassword;
            NSLog(@"[LC] 🔐 SOCKS5 authentication configured for user: %@", proxyUsername);
        }
        
    } else if ([proxyType isEqualToString:@"DIRECT"]) {
        // Direct connection (bypass proxy) - from Socker
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @NO;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPSEnable] = @NO;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesSOCKSEnable] = @NO;
    }
    
    // Add bypass list for localhost and private IPs (from Socker)
    NSArray *bypassList = @[
        @"localhost",
        @"127.0.0.1", 
        @"::1",
        @"10.*",
        @"172.16.*", @"172.17.*", @"172.18.*", @"172.19.*",
        @"172.20.*", @"172.21.*", @"172.22.*", @"172.23.*", 
        @"172.24.*", @"172.25.*", @"172.26.*", @"172.27.*",
        @"172.28.*", @"172.29.*", @"172.30.*", @"172.31.*",
        @"192.168.*",
        @"169.254.*"
    ];
    
    proxyDict[(__bridge NSString *)kCFNetworkProxiesExceptionsList] = bypassList;
    
    NSLog(@"[LC] 🔗 Created enhanced proxy dictionary: %@", proxyDict);
    return [proxyDict copy];
}

#pragma mark - NSURLSession Hooks (enhanced)

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
        
        // Additional configuration improvements (from Socker's approach)
        configuration.timeoutIntervalForRequest = 30.0;  // 30 second timeout
        configuration.timeoutIntervalForResource = 300.0; // 5 minute resource timeout
        configuration.waitsForConnectivity = YES;
        
        // Add custom headers if needed (like Socker does)
        if (proxyUsername.length > 0 && proxyPassword.length > 0) {
            NSString *credentials = [NSString stringWithFormat:@"%@:%@", proxyUsername, proxyPassword];
            NSData *credentialsData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
            NSString *base64Credentials = [credentialsData base64EncodedStringWithOptions:0];
            
            NSMutableDictionary *headers = [configuration.HTTPAdditionalHeaders mutableCopy] ?: [NSMutableDictionary dictionary];
            headers[@"Proxy-Authorization"] = [NSString stringWithFormat:@"Basic %@", base64Credentials];
            configuration.HTTPAdditionalHeaders = headers;
        }
        
        NSLog(@"[LC] ✅ Enhanced proxy applied to NSURLSession configuration");
    }
}

@end

#pragma mark - NSURLSessionConfiguration Hooks (enhanced)

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

#pragma mark - CFStream Hooks (for legacy apps, like Socker)

@implementation NSInputStream(LiveContainerProxy)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ([networkMode isEqualToString:@"compatibility"]) {
            // Only hook in compatibility mode for legacy support
            swizzle([NSInputStream class], @selector(initWithURL:), @selector(lc_initWithURL:));
        }
    });
}

- (instancetype)lc_initWithURL:(NSURL *)url {
    NSInputStream *stream = [self lc_initWithURL:url];
    
    if (spoofNetworkEnabled && stream) {
        NSLog(@"[LC] 🔗 Applying proxy to NSInputStream for URL: %@", url);
        
        NSDictionary *proxyDict = createProxyDictionary();
        if (proxyDict) {
            // Apply proxy settings to the stream (legacy support)
            CFReadStreamSetProperty((__bridge CFReadStreamRef)stream, 
                                  kCFStreamPropertyHTTPProxy, 
                                  (__bridge CFDictionaryRef)proxyDict);
        }
    }
    
    return stream;
}

@end

#pragma mark - NSURLConnection Legacy Support (like Socker)

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

#pragma mark - Initialization (following Socker's pattern)

void NetworkGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] 🚀 Initializing enhanced network spoofing hooks (Socker-inspired)...");
        
        loadNetworkConfiguration();
        
        if (!spoofNetworkEnabled) {
            NSLog(@"[LC] 📶 Network spoofing disabled");
            return;
        }
        
        NSLog(@"[LC] 🔗 Enhanced network spoofing enabled - Mode: %@, Proxy: %@://%@:%d", 
              networkMode, proxyType, proxyHost, proxyPort);
        
        // Initialize app-specific configurations (like Socker)
        appProxyConfigs = [[NSMutableDictionary alloc] init];
        
        NSLog(@"[LC] ✅ Enhanced network hooks initialized successfully (Socker-style)");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Failed to initialize enhanced network hooks: %@", exception);
    }
}