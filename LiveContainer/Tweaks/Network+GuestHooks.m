#import "Network+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <sys/socket.h>
#import <net/if.h>
#import <netdb.h>
#import "../utils.h"

// Global proxy state (Socker-inspired)
static BOOL proxyEnabled = NO;
static NSString *proxyHost = nil;
static NSInteger proxyPort = 8080;
static NSString *proxyUsername = nil;
static NSString *proxyPassword = nil;
static NSString *proxyType = @"HTTP"; // HTTP, SOCKS5, DIRECT

// Socker-style proxy configuration
typedef struct {
    char *host;
    int port;
    char *username;
    char *password;
    int type; // 0=HTTP, 1=SOCKS5
} ProxyConfig;

static ProxyConfig *globalProxyConfig = NULL;

// Forward declarations
static void initializeProxyDetectionBypass(void);
static NSMutableURLRequest *removeProxyHeaders(NSMutableURLRequest *request);
static BOOL (*amIProxied_Original)(BOOL considerVPNConnectionAsProxy) = NULL;

#pragma mark - Configuration Loading (Socker Pattern)

static void loadProxyConfiguration(void) {
    static BOOL hasLoaded = NO;
    if (hasLoaded) return;
    
    NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
    if (!guestAppInfo) {
        NSLog(@"[LC] ❌ No proxy configuration found");
        proxyEnabled = NO;
        hasLoaded = YES;
        return;
    }

    proxyEnabled = [guestAppInfo[@"spoofNetwork"] boolValue];
    proxyHost = [guestAppInfo[@"proxyHost"] copy];
    proxyPort = [guestAppInfo[@"proxyPort"] integerValue] ?: 8080;
    proxyUsername = [guestAppInfo[@"proxyUsername"] copy];
    proxyPassword = [guestAppInfo[@"proxyPassword"] copy];
    proxyType = [guestAppInfo[@"proxyType"] copy] ?: @"HTTP";

    // Create Socker-style config
    if (globalProxyConfig) {
        free(globalProxyConfig->host);
        free(globalProxyConfig->username);
        free(globalProxyConfig->password);
        free(globalProxyConfig);
    }
    
    if (proxyEnabled && proxyHost.length > 0) {
        globalProxyConfig = malloc(sizeof(ProxyConfig));
        globalProxyConfig->host = strdup([proxyHost UTF8String]);
        globalProxyConfig->port = (int)proxyPort;
        globalProxyConfig->username = proxyUsername.length > 0 ? strdup([proxyUsername UTF8String]) : NULL;
        globalProxyConfig->password = proxyPassword.length > 0 ? strdup([proxyPassword UTF8String]) : NULL;
        globalProxyConfig->type = [proxyType isEqualToString:@"SOCKS5"] ? 1 : 0;
    }

    NSLog(@"[LC] 🔗 Proxy Config: Enabled=%d, Type=%@, Host=%@, Port=%ld", 
          proxyEnabled, proxyType, proxyHost, (long)proxyPort);
    
    hasLoaded = YES;
}

#pragma mark - bt+ Style API Detection

static BOOL isAPIRequest(NSURLRequest *request) {
    NSString *urlString = request.URL.absoluteString.lowercaseString;
    NSString *host = request.URL.host.lowercaseString;
    NSString *path = request.URL.path.lowercaseString;
    
    // bt+ style API domain detection
    NSArray *apiDomains = @[
        @"api.",           // Most APIs use api subdomain
        @"graph.",         // Graph APIs (Facebook, etc.)
        @"rest.",          // REST APIs
        @"v1.",            // Versioned APIs
        @"v2.",
        @"v3.",
        @"gateway.",       // API gateways
        @"backend.",       // Backend services
        @"service.",       // Microservices
        @"auth.",          // Authentication services
        @"oauth.",         // OAuth providers
    ];
    
    // bt+ style API path patterns
    NSArray *apiPatterns = @[
        @"/api/",
        @"/v1/",
        @"/v2/",
        @"/v3/",
        @"/rest/",
        @"/graphql",
        @"/oauth",
        @"/auth",
        @"/login",
        @"/token",
        @"/refresh",
        @"/session",
        @"/user",
        @"/users",
        @"/profile",
        @"/account",
        @"/service/",
        @"/backend/",
        @"/gateway/",
        @".json",
        @".xml"
    ];
    
    // bt+ style content type detection
    NSString *contentType = [request valueForHTTPHeaderField:@"Content-Type"];
    if (contentType) {
        contentType = contentType.lowercaseString;
        if ([contentType containsString:@"application/json"] ||
            [contentType containsString:@"application/xml"] ||
            [contentType containsString:@"application/x-www-form-urlencoded"]) {
            return YES;
        }
    }
    
    // Check Accept header for API responses
    NSString *accept = [request valueForHTTPHeaderField:@"Accept"];
    if (accept) {
        accept = accept.lowercaseString;
        if ([accept containsString:@"application/json"] ||
            [accept containsString:@"application/xml"]) {
            return YES;
        }
    }
    
    // Check domain patterns
    for (NSString *pattern in apiDomains) {
        if ([host hasPrefix:pattern]) {
            return YES;
        }
    }
    
    // Check URL patterns
    for (NSString *pattern in apiPatterns) {
        if ([urlString containsString:pattern] || [path containsString:pattern]) {
            return YES;
        }
    }
    
    // bt+ style HTTP method detection (APIs often use POST, PUT, DELETE)
    NSString *method = request.HTTPMethod.uppercaseString;
    if ([method isEqualToString:@"POST"] || 
        [method isEqualToString:@"PUT"] || 
        [method isEqualToString:@"DELETE"] || 
        [method isEqualToString:@"PATCH"]) {
        return YES;
    }
    
    return NO;
}

#pragma mark - Socker-Style Proxy Dictionary Creation

static NSDictionary *createSockerStyleProxyDictionary(void) {
    if (!proxyEnabled || !globalProxyConfig) {
        return nil;
    }
    
    NSMutableDictionary *proxyDict = [NSMutableDictionary dictionary];
    
    if (globalProxyConfig->type == 0) { // HTTP
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @YES;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPProxy] = [NSString stringWithUTF8String:globalProxyConfig->host];
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPPort] = @(globalProxyConfig->port);
        
        // HTTPS support using string keys
        proxyDict[@"HTTPSEnable"] = @YES;
        proxyDict[@"HTTPSProxy"] = [NSString stringWithUTF8String:globalProxyConfig->host];
        proxyDict[@"HTTPSPort"] = @(globalProxyConfig->port);
        
    } else { // SOCKS5
        proxyDict[@"SOCKSEnable"] = @YES;
        proxyDict[@"SOCKSProxy"] = [NSString stringWithUTF8String:globalProxyConfig->host];
        proxyDict[@"SOCKSPort"] = @(globalProxyConfig->port);
        proxyDict[@"SOCKSVersion"] = @5;
    }
    
    // Authentication
    if (globalProxyConfig->username) {
        NSString *username = [NSString stringWithUTF8String:globalProxyConfig->username];
        proxyDict[@"HTTPProxyUsername"] = username;
        proxyDict[@"HTTPSProxyUsername"] = username;
        proxyDict[@"SOCKSUsername"] = username;
    }
    
    if (globalProxyConfig->password) {
        NSString *password = [NSString stringWithUTF8String:globalProxyConfig->password];
        proxyDict[@"HTTPProxyPassword"] = password;
        proxyDict[@"HTTPSProxyPassword"] = password;
        proxyDict[@"SOCKSPassword"] = password;
    }
    
    NSLog(@"[LC] ✅ Created Socker-style proxy dictionary");
    return [proxyDict copy];
}

#pragma mark - Proxy/VPN Detection Bypass (Shadowrocket Compatible)

// Hook CFNetworkCopySystemProxySettings to return clean proxy settings
// static CFDictionaryRef (*original_CFNetworkCopySystemProxySettings)(void);

// static CFDictionaryRef spoofed_CFNetworkCopySystemProxySettings(void) {
//     if (!proxyEnabled) {
//         return original_CFNetworkCopySystemProxySettings();
//     }
    
//     NSLog(@"[LC] 🎭 Spoofing system proxy settings (hiding proxy/VPN detection)");
    
//     // Return a clean proxy configuration that looks like no proxy is set
//     NSDictionary *cleanProxySettings = @{
//         @"HTTPEnable": @0,
//         @"HTTPProxy": @"",
//         @"HTTPPort": @0,
//         @"HTTPSEnable": @0,
//         @"HTTPSProxy": @"",
//         @"HTTPSPort": @0,
//         @"ProxyAutoConfigEnable": @0,
//         @"ProxyAutoConfigURLString": @"",
//         @"SOCKSEnable": @0,
//         @"SOCKSProxy": @"",
//         @"SOCKSPort": @0,
//         @"ExceptionsList": @[],
//         @"FTPEnable": @0,
//         @"FTPPassive": @1,
//         @"FTPProxy": @"",
//         @"FTPPort": @0,
//         @"__SCOPED__": @{} // Empty scoped settings (no VPN interfaces)
//     };
    
//     return CFBridgingRetain(cleanProxySettings);
// }

// Hook SCDynamicStoreCopyProxies for system-level proxy detection
// static CFDictionaryRef (*original_SCDynamicStoreCopyProxies)(SCDynamicStoreRef store, CFArrayRef targetHosts);

// static CFDictionaryRef spoofed_SCDynamicStoreCopyProxies(SCDynamicStoreRef store, CFArrayRef targetHosts) {
//     if (!proxyEnabled) {
//         return original_SCDynamicStoreCopyProxies(store, targetHosts);
//     }
    
//     NSLog(@"[LC] 🎭 Spoofing SCDynamicStore proxy settings");
    
//     // Return clean proxy settings using string keys (iOS compatible)
//     NSDictionary *cleanSettings = @{
//         @"HTTPEnable": @0,
//         @"HTTPProxy": @"",
//         @"HTTPPort": @0,
//         @"HTTPSEnable": @0,
//         @"HTTPSProxy": @"",
//         @"HTTPSPort": @0,
//         @"ProxyAutoConfigEnable": @0,
//         @"SOCKSEnable": @0,
//         @"SOCKSProxy": @"",
//         @"SOCKSPort": @0,
//         @"ExceptionsList": @[]
//     };
    
//     return CFBridgingRetain(cleanSettings);
// }

#pragma mark - Network Interface Detection Bypass

// static int (*original_getifaddrs)(struct ifaddrs **ifap);

// static int spoofed_getifaddrs(struct ifaddrs **ifap) {
//     if (!proxyEnabled) {
//         return original_getifaddrs(ifap);
//     }
    
//     int result = original_getifaddrs(ifap);
//     if (result != 0 || !ifap || !*ifap) {
//         return result;
//     }
    
//     NSLog(@"[LC] 🎭 Filtering VPN interfaces from getifaddrs");
    
//     // Filter out VPN-related interfaces
//     struct ifaddrs *current = *ifap;
//     struct ifaddrs *prev = NULL;
    
//     while (current != NULL) {
//         BOOL shouldRemove = NO;
        
//         if (current->ifa_name) {
//             NSString *interfaceName = [NSString stringWithUTF8String:current->ifa_name];
//             NSArray *vpnPrefixes = @[@"utun", @"tap", @"tun", @"ppp", @"ipsec", @"l2tp", @"pptp"];
            
//             for (NSString *prefix in vpnPrefixes) {
//                 if ([interfaceName hasPrefix:prefix]) {
//                     shouldRemove = YES;
//                     NSLog(@"[LC] 🎭 Hiding VPN interface: %@", interfaceName);
//                     break;
//                 }
//             }
//         }
        
//         if (shouldRemove) {
//             if (prev) {
//                 prev->ifa_next = current->ifa_next;
//             } else {
//                 *ifap = current->ifa_next;
//             }
//             struct ifaddrs *toRemove = current;
//             current = current->ifa_next;
//             free(toRemove);
//         } else {
//             prev = current;
//             current = current->ifa_next;
//         }
//     }
    
//     return result;
// }

#pragma mark - DNS Resolution Bypass

// static struct hostent *(*original_gethostbyname)(const char *name);

// static struct hostent *spoofed_gethostbyname(const char *name) {
//     if (proxyEnabled && name) {
//         NSString *hostname = [NSString stringWithUTF8String:name];
        
//         // Block common proxy/VPN detection domains
//         NSArray *blockedDomains = @[
//             @"whatismyipaddress.com",
//             @"ipinfo.io",
//             @"ip-api.com",
//             @"ipapi.co",
//             @"geoip.com",
//             @"maxmind.com",
//             @"proxy-checker.com",
//             @"vpndetector.com",
//             @"proxydetector.com"
//         ];
        
//         for (NSString *blocked in blockedDomains) {
//             if ([hostname containsString:blocked]) {
//                 NSLog(@"[LC] 🎭 Blocking proxy detection domain: %@", hostname);
//                 h_errno = HOST_NOT_FOUND;
//                 return NULL;
//             }
//         }
//     }
    
//     return original_gethostbyname(name);
// }

#pragma mark - Custom Detection Function Bypass

// Create a universal proxy detection bypass function
BOOL amIProxied_Spoofed(BOOL considerVPNConnectionAsProxy) {
    if (!proxyEnabled) {
        // If proxy is disabled, use real detection (if available)
        if (amIProxied_Original) {
            return amIProxied_Original(considerVPNConnectionAsProxy);
        }
        return NO;
    }
    
    NSLog(@"[LC] 🎭 Spoofing proxy detection - returning NO (not proxied)");
    return NO; // Always return NO when proxy is enabled
}

#pragma mark - HTTP Header Spoofing

// Add method to spoof HTTP headers that reveal proxy usage
static NSMutableURLRequest *removeProxyHeaders(NSMutableURLRequest *request) {
    if (!proxyEnabled) return request;
    
    // Remove headers that might reveal proxy usage
    NSArray *proxyHeaders = @[
        @"X-Forwarded-For",
        @"X-Forwarded-Proto",
        @"X-Forwarded-Host",
        @"X-Real-IP",
        @"Via",
        @"Proxy-Connection",
        @"X-Proxy-ID",
        @"X-Proxy-Authorization"
    ];
    
    for (NSString *header in proxyHeaders) {
        [request setValue:nil forHTTPHeaderField:header];
    }
    
    // Add spoofed headers to look like direct connection
    [request setValue:@"direct" forHTTPHeaderField:@"Connection"];
    
    return request;
}

#pragma mark - Initialize Proxy Detection Bypass

// static void initializeProxyDetectionBypass(void) {
//     if (!proxyEnabled) return;
    
//     NSLog(@"[LC] 🎭 Installing proxy/VPN detection bypass hooks...");
    
//     // Note: We're using a simplified approach since we can't use fishhook/rebind_symbols
//     // These hooks will work for basic detection bypass
    
//     // Hook CFNetwork functions
//     void *cfnetwork = dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork", RTLD_LAZY);
//     if (cfnetwork) {
//         original_CFNetworkCopySystemProxySettings = dlsym(cfnetwork, "CFNetworkCopySystemProxySettings");
//         NSLog(@"[LC] 🎭 CFNetwork hooks prepared");
//     }
    
//     // Hook SystemConfiguration functions
//     void *syscfg = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
//     if (syscfg) {
//         original_SCDynamicStoreCopyProxies = dlsym(syscfg, "SCDynamicStoreCopyProxies");
//         NSLog(@"[LC] 🎭 SystemConfiguration hooks prepared");
//     }
    
//     // Prepare system function hooks
//     original_getifaddrs = getifaddrs;
//     original_gethostbyname = gethostbyname;
    
//     NSLog(@"[LC] ✅ Proxy/VPN detection bypass prepared (basic level)");
// }

#pragma mark - Universal NSURLSession Hooks (Socker Pattern)

@implementation NSURLSession(SockerStyleProxy)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loadProxyConfiguration();
        
        if (proxyEnabled) {
            // Hook ALL session creation methods
            swizzle([NSURLSession class], @selector(sessionWithConfiguration:), @selector(socker_sessionWithConfiguration:));
            swizzle([NSURLSession class], @selector(sessionWithConfiguration:delegate:delegateQueue:), @selector(socker_sessionWithConfiguration:delegate:delegateQueue:));
            swizzle([NSURLSession class], @selector(sharedSession), @selector(socker_sharedSession));
            
            // Hook configuration creation (critical for universal coverage)
            swizzle([NSURLSessionConfiguration class], @selector(defaultSessionConfiguration), @selector(socker_defaultSessionConfiguration));
            swizzle([NSURLSessionConfiguration class], @selector(ephemeralSessionConfiguration), @selector(socker_ephemeralSessionConfiguration));
            swizzle([NSURLSessionConfiguration class], @selector(backgroundSessionConfigurationWithIdentifier:), @selector(socker_backgroundSessionConfigurationWithIdentifier:));
            
            NSLog(@"[LC] 🔗 Universal NSURLSession proxy hooks installed (Socker+Blaze pattern)");
        }
    });
}

+ (NSURLSessionConfiguration *)socker_defaultSessionConfiguration {
    NSURLSessionConfiguration *config = [self socker_defaultSessionConfiguration];
    [self applySockerProxyToConfiguration:config type:@"default"];
    return config;
}

+ (NSURLSessionConfiguration *)socker_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = [self socker_ephemeralSessionConfiguration];
    [self applySockerProxyToConfiguration:config type:@"ephemeral"];
    return config;
}

+ (NSURLSessionConfiguration *)socker_backgroundSessionConfigurationWithIdentifier:(NSString *)identifier {
    NSURLSessionConfiguration *config = [self socker_backgroundSessionConfigurationWithIdentifier:identifier];
    [self applySockerProxyToConfiguration:config type:@"background"];
    return config;
}

+ (NSURLSession *)socker_sharedSession {
    NSURLSession *session = [self socker_sharedSession];
    NSLog(@"[LC] 🔗 Shared session accessed - proxy applied via configuration hooks");
    return session;
}

+ (NSURLSession *)socker_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    [self applySockerProxyToConfiguration:configuration type:@"custom"];
    return [self socker_sessionWithConfiguration:configuration];
}

+ (NSURLSession *)socker_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration 
                                          delegate:(id<NSURLSessionDelegate>)delegate 
                                     delegateQueue:(NSOperationQueue *)queue {
    [self applySockerProxyToConfiguration:configuration type:@"delegate"];
    return [self socker_sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}

+ (void)applySockerProxyToConfiguration:(NSURLSessionConfiguration *)configuration type:(NSString *)type {
    if (!proxyEnabled || !globalProxyConfig) return;
    
    NSDictionary *proxyDict = createSockerStyleProxyDictionary();
    if (proxyDict) {
        configuration.connectionProxyDictionary = proxyDict;
        
        // Socker-style aggressive networking settings
        configuration.waitsForConnectivity = YES;
        configuration.allowsCellularAccess = YES;
        configuration.timeoutIntervalForRequest = 60.0;
        configuration.timeoutIntervalForResource = 300.0;
        configuration.HTTPMaximumConnectionsPerHost = 6;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        
        // Enhanced headers for proxy compatibility
        NSMutableDictionary *headers = [configuration.HTTPAdditionalHeaders mutableCopy] ?: [NSMutableDictionary dictionary];
        
        // Add proxy authentication header
        if (globalProxyConfig->username && globalProxyConfig->password) {
            NSString *credentials = [NSString stringWithFormat:@"%s:%s", globalProxyConfig->username, globalProxyConfig->password];
            NSData *credentialsData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
            NSString *base64Credentials = [credentialsData base64EncodedStringWithOptions:0];
            headers[@"Proxy-Authorization"] = [NSString stringWithFormat:@"Basic %@", base64Credentials];
        }
        
        // bt+ style headers for better API compatibility
        headers[@"User-Agent"] = @"LiveContainer/1.0 Universal API Client";
        headers[@"Accept"] = @"application/json, application/xml, */*";
        headers[@"Accept-Language"] = @"en-US,en;q=0.9";
        headers[@"Accept-Encoding"] = @"gzip, deflate, br";
        headers[@"Connection"] = @"keep-alive";
        
        configuration.HTTPAdditionalHeaders = headers;
        
        NSLog(@"[LC] ✅ Socker+Blaze proxy applied to %@ configuration", type);
    }
}

@end

#pragma mark - Enhanced Data Task Hooks (Socker + bt+ Pattern)

static NSURLSessionDataTask *(*original_dataTaskWithRequest)(id self, SEL _cmd, NSURLRequest *request, void(^completionHandler)(NSData *, NSURLResponse *, NSError *));

static NSURLSessionDataTask *socker_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, void(^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    if (proxyEnabled && globalProxyConfig) {
        NSString *urlString = request.URL.absoluteString;
        NSString *host = request.URL.host;
        BOOL isAPI = isAPIRequest(request);
        
        if (isAPI) {
            NSLog(@"[LC] 🎯 API request detected: %@ -> %@", request.HTTPMethod, host);
        } else {
            NSLog(@"[LC] 🌐 Regular request: %@", host);
        }
        
        // Create enhanced request (bt+ + Socker style)
        NSMutableURLRequest *enhancedRequest = [request mutableCopy];
        
        if (isAPI) {
            // bt+ style API-specific headers
            [enhancedRequest setValue:@"LiveContainer/1.0 API Client" forHTTPHeaderField:@"User-Agent"];
            [enhancedRequest setValue:@"application/json, application/xml, */*" forHTTPHeaderField:@"Accept"];
            [enhancedRequest setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
            
            // Add API-friendly headers
            NSString *existingContentType = [enhancedRequest valueForHTTPHeaderField:@"Content-Type"];
            if (!existingContentType && [request.HTTPMethod isEqualToString:@"POST"]) {
                [enhancedRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            }
            
            // bt+ style anonymity headers for APIs
            [enhancedRequest setValue:@"1" forHTTPHeaderField:@"DNT"]; // Do Not Track
            
        } else {
            // Socker-style headers for regular requests
            [enhancedRequest setValue:@"LiveContainer/1.0 Universal Client" forHTTPHeaderField:@"User-Agent"];
            [enhancedRequest setValue:@"*/*" forHTTPHeaderField:@"Accept"];
        }
        
        // Universal headers for all requests
        [enhancedRequest setValue:@"en-US,en;q=0.9" forHTTPHeaderField:@"Accept-Language"];
        [enhancedRequest setValue:@"gzip, deflate, br" forHTTPHeaderField:@"Accept-Encoding"];
        [enhancedRequest setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
        
        // Add proxy authentication if needed
        if (globalProxyConfig->username && globalProxyConfig->password) {
            NSString *credentials = [NSString stringWithFormat:@"%s:%s", globalProxyConfig->username, globalProxyConfig->password];
            NSData *credentialsData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
            NSString *base64Credentials = [credentialsData base64EncodedStringWithOptions:0];
            [enhancedRequest setValue:[NSString stringWithFormat:@"Basic %@", base64Credentials] forHTTPHeaderField:@"Proxy-Authorization"];
        }
        
        // Remove proxy-revealing headers
        enhancedRequest = removeProxyHeaders(enhancedRequest);
        
        request = enhancedRequest;
        
        NSLog(@"[LC] ✅ Request enhanced with %@ headers", isAPI ? @"API-focused" : @"universal");
        
        // bt+ style response interception for critical API endpoints
        if (isAPI && ([urlString containsString:@"auth"] || [urlString containsString:@"login"] || [urlString containsString:@"token"])) {
            NSLog(@"[LC] 🔐 Critical authentication API detected: %@", urlString);
            
            // Wrap completion handler to log auth responses (bt+ pattern)
            void(^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
                if (data && !error) {
                    @try {
                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                        if (json[@"token"] || json[@"access_token"] || json[@"api_token"]) {
                            NSLog(@"[LC] 🔑 Authentication token detected in response");
                        }
                    } @catch (NSException *exception) {
                        // Silent fail for non-JSON responses
                    }
                }
                
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
            };
            
            return original_dataTaskWithRequest(self, _cmd, request, wrappedCompletion);
        }
    }
    
    return original_dataTaskWithRequest(self, _cmd, request, completionHandler);
}

#pragma mark - Universal NSURLConnection Support (Legacy Apps)

@implementation NSURLConnection(SockerProxy)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (proxyEnabled) {
            swizzle([NSURLConnection class], @selector(initWithRequest:delegate:), @selector(socker_initWithRequest:delegate:));
            swizzle([NSURLConnection class], @selector(initWithRequest:delegate:startImmediately:), @selector(socker_initWithRequest:delegate:startImmediately:));
            swizzle([NSURLConnection class], @selector(sendSynchronousRequest:returningResponse:error:), @selector(socker_sendSynchronousRequest:returningResponse:error:));
            
            NSLog(@"[LC] 🔗 Universal NSURLConnection proxy hooks installed");
        }
    });
}

- (instancetype)socker_initWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    if (proxyEnabled) {
        BOOL isAPI = isAPIRequest(request);
        NSLog(@"[LC] 📡 Legacy %@ connection to: %@", isAPI ? @"API" : @"regular", request.URL.host);
    }
    return [self socker_initWithRequest:request delegate:delegate];
}

- (instancetype)socker_initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)startImmediately {
    if (proxyEnabled) {
        BOOL isAPI = isAPIRequest(request);
        NSLog(@"[LC] 📡 Legacy %@ connection (manual start) to: %@", isAPI ? @"API" : @"regular", request.URL.host);
    }
    return [self socker_initWithRequest:request delegate:delegate startImmediately:startImmediately];
}

+ (NSData *)socker_sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    if (proxyEnabled) {
        BOOL isAPI = isAPIRequest(request);
        NSLog(@"[LC] 📡 Synchronous %@ request to: %@", isAPI ? @"API" : @"regular", request.URL.host);
    }
    return [self socker_sendSynchronousRequest:request returningResponse:response error:error];
}

@end

#pragma mark - Enhanced Proxy Testing (Socker + bt+ Style)

@interface SockerProxyTester : NSObject
+ (void)testProxyConnection:(void(^)(BOOL success, NSTimeInterval latency, NSString *externalIP))completion;
+ (void)testAPIProxyCapability:(void(^)(BOOL success))completion;
@end

@implementation SockerProxyTester

+ (void)testProxyConnection:(void(^)(BOOL success, NSTimeInterval latency, NSString *externalIP))completion {
    if (!proxyEnabled || !globalProxyConfig) {
        completion(NO, 0, nil);
        return;
    }
    
    NSLog(@"[LC] 🧪 Testing Socker-style proxy connection...");
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.connectionProxyDictionary = createSockerStyleProxyDictionary();
    config.timeoutIntervalForRequest = 10.0;
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    // Test with multiple IP checking services
    NSArray *testURLs = @[
        @"https://httpbin.org/ip",
        @"https://api.ipify.org?format=json",
        @"https://ipapi.co/json/",
        @"http://ip-api.com/json/"
    ];
    
    NSString *testURL = testURLs[arc4random_uniform((uint32_t)testURLs.count)];
    NSURL *url = [NSURL URLWithString:testURL];
    
    NSDate *startTime = [NSDate date];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSTimeInterval latency = [[NSDate date] timeIntervalSinceDate:startTime];
        BOOL success = (error == nil && [(NSHTTPURLResponse *)response statusCode] == 200);
        
        NSString *externalIP = nil;
        if (success && data) {
            @try {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                externalIP = json[@"ip"] ?: json[@"origin"] ?: json[@"query"] ?: @"Unknown";
                NSLog(@"[LC] ✅ Socker proxy test successful - External IP: %@, Latency: %.2fs", externalIP, latency);
            } @catch (NSException *exception) {
                NSLog(@"[LC] ⚠️ Could not parse IP response: %@", exception);
            }
        } else {
            NSLog(@"[LC] ❌ Socker proxy test failed - Error: %@", error.localizedDescription);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(success, latency, externalIP);
        });
    }];
    
    [task resume];
}

+ (void)testAPIProxyCapability:(void(^)(BOOL success))completion {
    if (!proxyEnabled || !globalProxyConfig) {
        completion(NO);
        return;
    }
    
    NSLog(@"[LC] 🧪 Testing API proxy capability (bt+ style)...");
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.connectionProxyDictionary = createSockerStyleProxyDictionary();
    config.timeoutIntervalForRequest = 10.0;
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    // Test API endpoint
    NSURL *apiURL = [NSURL URLWithString:@"https://httpbin.org/json"];
    NSMutableURLRequest *apiRequest = [NSMutableURLRequest requestWithURL:apiURL];
    [apiRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [apiRequest setValue:@"LiveContainer/1.0 API Test" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:apiRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL success = (error == nil && [(NSHTTPURLResponse *)response statusCode] == 200);
        
        if (success && data) {
            @try {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (json) {
                    NSLog(@"[LC] ✅ API proxy capability confirmed - JSON response received");
                }
            } @catch (NSException *exception) {
                success = NO;
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(success);
        });
    }];
    
    [task resume];
}

@end

#pragma mark - Initialization

void NetworkGuestHooksInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @try {
            NSLog(@"[LC] 🚀 Initializing Socker+bt hybrid proxy system...");
            
            loadProxyConfiguration();
            
            if (!proxyEnabled) {
                NSLog(@"[LC] 📶 Universal proxy disabled");
                return;
            }
            
            NSLog(@"[LC] 🔗 Universal proxy enabled: %@://%@:%ld", 
                  proxyType, proxyHost, (long)proxyPort);
            
            // Install universal data task hooks (Socker + bt+ pattern)
            Class sessionClass = NSClassFromString(@"NSURLSession");
            if (sessionClass) {
                Method originalMethod = class_getInstanceMethod(sessionClass, @selector(dataTaskWithRequest:completionHandler:));
                if (originalMethod) {
                    original_dataTaskWithRequest = (void *)method_getImplementation(originalMethod);
                    method_setImplementation(originalMethod, (IMP)socker_dataTaskWithRequest);
                    NSLog(@"[LC] ✅ Enhanced data task hooks installed (Socker+Blaze pattern)");
                }
            }
            
            // Initialize proxy detection bypass
            // initializeProxyDetectionBypass();
            
            // Test the proxy connection
            [SockerProxyTester testProxyConnection:^(BOOL success, NSTimeInterval latency, NSString *externalIP) {
                if (success) {
                    NSLog(@"[LC] ✅ Socker+Blaze universal proxy operational");
                    NSLog(@"[LC] 📊 External IP: %@, Latency: %.2fs", externalIP, latency);
                    
                    // Test API capability
                    [SockerProxyTester testAPIProxyCapability:^(BOOL apiSuccess) {
                        if (apiSuccess) {
                            NSLog(@"[LC] ✅ API proxy capability confirmed");
                            NSLog(@"[LC] 🎯 Coverage: Universal HTTP/HTTPS + Enhanced API detection");
                        } else {
                            NSLog(@"[LC] ⚠️ API proxy test failed, but basic proxy works");
                        }
                    }];
                } else {
                    NSLog(@"[LC] ⚠️ Proxy connection test failed - check configuration");
                }
            }];

            NSLog(@"[LC] ✅ Socker+bt hybrid proxy system initialized");
            NSLog(@"[LC] ℹ️ Features:");
            NSLog(@"[LC] 🌐 Universal HTTP/HTTPS traffic proxying (Socker-style)");
            NSLog(@"[LC] 🎯 Enhanced API request detection (bt+ style)");
            NSLog(@"[LC] 🔐 Authentication endpoint monitoring");
            NSLog(@"[LC] 📱 Legacy NSURLConnection support");
            NSLog(@"[LC] 🎭 Basic proxy/VPN detection bypass");
            NSLog(@"[LC] ⚠️ Limitations: Raw sockets, WebRTC require jailbreak");
            
            // Additional test after 3 seconds
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (proxyEnabled) {
                    NSLog(@"[LC] 🧪 Starting immediate proxy test...");
                    
                    // Create a simple test request
                    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
                    config.connectionProxyDictionary = createSockerStyleProxyDictionary();
                    config.timeoutIntervalForRequest = 10.0;
                    
                    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
                    
                    // Test with a simple API that returns your IP
                    NSURL *testURL = [NSURL URLWithString:@"https://httpbin.org/ip"];
                    NSURLSessionDataTask *task = [session dataTaskWithURL:testURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                        if (data && !error) {
                            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                            NSLog(@"[LC] ✅ PROXY TEST SUCCESS - Response: %@", responseString);
                            
                            // Parse JSON to get IP
                            @try {
                                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                                NSString *detectedIP = json[@"origin"];
                                NSLog(@"[LC] 🌍 Your external IP through proxy: %@", detectedIP);
                                NSLog(@"[LC] 🔗 Proxy server: %@:%ld", proxyHost, (long)proxyPort);
                                
                                if ([detectedIP isEqualToString:proxyHost]) {
                                    NSLog(@"[LC] ✅ PROXY IS WORKING CORRECTLY!");
                                } else {
                                    NSLog(@"[LC] ⚠️ Proxy might not be working - IP doesn't match proxy server");
                                }
                            } @catch (NSException *exception) {
                                NSLog(@"[LC] ⚠️ Could not parse test response");
                            }
                        } else {
                            NSLog(@"[LC] ❌ PROXY TEST FAILED - Error: %@", error.localizedDescription);
                        }
                    }];
                    [task resume];
                }
            });
            
        } @catch (NSException *exception) {
            NSLog(@"[LC] ❌ Failed to initialize hybrid proxy: %@", exception);
        }
    });
}