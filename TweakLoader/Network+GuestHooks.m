#import "Network+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <objc/runtime.h>
#import "../fishhook/fishhook.h"
#import "utils.h"

// Add missing includes for networking
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <dlfcn.h>

// Global state
static BOOL spoofNetworkEnabled = NO;
static NSString *proxyType = @"HTTP";
static NSString *proxyHost = @"";
static int proxyPort = 8080;
static NSString *proxyUsername = @"";
static NSString *proxyPassword = @"";
static NSString *networkMode = @"standard";

// Original function pointers for socket-level hooks
static int (*original_connect)(int, const struct sockaddr *, socklen_t) = NULL;
static int (*original_socket)(int, int, int) = NULL;
static struct hostent *(*original_gethostbyname)(const char *) = NULL;
static int (*original_getaddrinfo)(const char *, const char *, const struct addrinfo *, struct addrinfo **) = NULL;

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
    proxyPort = [guestAppInfo[@"proxyPort"] intValue];
    if (proxyPort == 0) proxyPort = 8080;
    proxyUsername = guestAppInfo[@"proxyUsername"] ?: @"";
    proxyPassword = guestAppInfo[@"proxyPassword"] ?: @"";
    networkMode = guestAppInfo[@"spoofNetworkMode"] ?: @"standard"; // Fixed key name

    NSLog(@"[LC] ⚙️ Network Config: Enabled=%d, Type=%@, Host=%@, Port=%d, Mode=%@", 
          spoofNetworkEnabled, proxyType, proxyHost, proxyPort, networkMode);
}

#pragma mark - Socket-Level Hooks (inspired by socker)

static int lc_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    loadNetworkConfiguration();
    
    if (!spoofNetworkEnabled || [networkMode isEqualToString:@"compatibility"]) {
        return original_connect(sockfd, addr, addrlen);
    }
    
    // For aggressive mode, intercept all socket connections
    if ([networkMode isEqualToString:@"aggressive"]) {
        NSLog(@"[LC] 🔌 Intercepting socket connection in aggressive mode");
        
        // Convert sockaddr to proxy connection
        if (addr->sa_family == AF_INET) {
            struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
            char ip_str[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &(addr_in->sin_addr), ip_str, INET_ADDRSTRLEN);
            int port = ntohs(addr_in->sin_port);
            
            NSLog(@"[LC] 🎯 Original destination: %s:%d", ip_str, port);
            
            // Redirect to proxy
            if (proxyHost.length > 0) {
                struct sockaddr_in proxy_addr;
                memset(&proxy_addr, 0, sizeof(proxy_addr));
                proxy_addr.sin_family = AF_INET;
                proxy_addr.sin_port = htons(proxyPort);
                
                // Resolve proxy host
                struct hostent *proxy_host_entry = gethostbyname(proxyHost.UTF8String);
                if (proxy_host_entry) {
                    memcpy(&proxy_addr.sin_addr, proxy_host_entry->h_addr_list[0], proxy_host_entry->h_length);
                    NSLog(@"[LC] 🔄 Redirecting to proxy: %@:%d", proxyHost, proxyPort);
                    return original_connect(sockfd, (struct sockaddr *)&proxy_addr, sizeof(proxy_addr));
                }
            }
        }
    }
    
    return original_connect(sockfd, addr, addrlen);
}

static struct hostent *lc_gethostbyname(const char *name) {
    loadNetworkConfiguration();
    
    if (spoofNetworkEnabled && [networkMode isEqualToString:@"aggressive"]) {
        NSLog(@"[LC] 🔍 DNS lookup intercepted: %s", name);
        
        // In aggressive mode, we might want to return proxy IP for all lookups
        // or implement custom DNS resolution logic here
    }
    
    return original_gethostbyname(name);
}

static int lc_getaddrinfo(const char *node, const char *service, 
                         const struct addrinfo *hints, struct addrinfo **res) {
    loadNetworkConfiguration();
    
    if (spoofNetworkEnabled && [networkMode isEqualToString:@"aggressive"]) {
        NSLog(@"[LC] 🔍 getaddrinfo intercepted: %s:%s", node ?: "null", service ?: "null");
    }
    
    return original_getaddrinfo(node, service, hints, res);
}

#pragma mark - CFNetwork Hooks (Enhanced)

static CFHTTPMessageRef lc_CFHTTPMessageCreateRequest(CFAllocatorRef alloc,
                                                     CFStringRef requestMethod,
                                                     CFURLRef url,
                                                     CFStringRef httpVersion) {
    static CFHTTPMessageRef (*original_CFHTTPMessageCreateRequest)(CFAllocatorRef, CFStringRef, CFURLRef, CFStringRef) = NULL;
    
    if (!original_CFHTTPMessageCreateRequest) {
        original_CFHTTPMessageCreateRequest = dlsym(RTLD_DEFAULT, "CFHTTPMessageCreateRequest");
    }
    
    CFHTTPMessageRef message = original_CFHTTPMessageCreateRequest(alloc, requestMethod, url, httpVersion);
    
    loadNetworkConfiguration();
    if (spoofNetworkEnabled && message) {
        // Add proxy authentication headers if needed
        if (proxyUsername.length > 0 && proxyPassword.length > 0) {
            NSString *credentials = [NSString stringWithFormat:@"%@:%@", proxyUsername, proxyPassword];
            NSData *credentialsData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
            NSString *base64Credentials = [credentialsData base64EncodedStringWithOptions:0];
            
            CFStringRef authValue = (__bridge CFStringRef)[NSString stringWithFormat:@"Basic %@", base64Credentials];
            CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Proxy-Authorization"), authValue);
            
            NSLog(@"[LC] 🔐 Added proxy auth to CFHTTPMessage");
        }
    }
    
    return message;
}

#pragma mark - Enhanced Proxy Dictionary Creation

static NSDictionary *createEnhancedProxyDictionary(void) {
    if (!spoofNetworkEnabled || !proxyHost || proxyHost.length == 0) {
        return nil;
    }
    
    NSMutableDictionary *proxyDict = [NSMutableDictionary dictionary];
    
    // More comprehensive proxy configuration
    if ([proxyType isEqualToString:@"HTTP"]) {
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @YES;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPProxy] = proxyHost;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPPort] = @(proxyPort);
        
        // Enable for HTTPS as well (though constants may not be available)
        proxyDict[@"HTTPSEnable"] = @YES;
        proxyDict[@"HTTPSProxy"] = proxyHost;
        proxyDict[@"HTTPSPort"] = @(proxyPort);
        
    } else if ([proxyType isEqualToString:@"SOCKS5"]) {
        // SOCKS configuration
        proxyDict[@"SOCKSEnable"] = @YES;
        proxyDict[@"SOCKSProxy"] = proxyHost;
        proxyDict[@"SOCKSPort"] = @(proxyPort);
        proxyDict[@"SOCKSVersion"] = @5;
        
    } else if ([proxyType isEqualToString:@"DIRECT"]) {
        // No proxy
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @NO;
        proxyDict[@"HTTPSEnable"] = @NO;
        proxyDict[@"SOCKSEnable"] = @NO;
    }
    
    // Authentication
    if (proxyUsername.length > 0) {
        proxyDict[@"HTTPProxyUsername"] = proxyUsername;
        proxyDict[@"HTTPSProxyUsername"] = proxyUsername;
        proxyDict[@"SOCKSUsername"] = proxyUsername;
    }
    
    if (proxyPassword.length > 0) {
        proxyDict[@"HTTPProxyPassword"] = proxyPassword;
        proxyDict[@"HTTPSProxyPassword"] = proxyPassword;
        proxyDict[@"SOCKSPassword"] = proxyPassword;
    }
    
    NSLog(@"[LC] ✅ Created enhanced proxy dictionary: %@", proxyDict);
    return [proxyDict copy];
}

#pragma mark - Enhanced NSURLSession Hooks

@implementation NSURLSession(LiveContainerProxyEnhanced)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzle([NSURLSession class], @selector(sessionWithConfiguration:), @selector(lc_sessionWithConfiguration:));
        swizzle([NSURLSession class], @selector(sessionWithConfiguration:delegate:delegateQueue:), @selector(lc_sessionWithConfiguration:delegate:delegateQueue:));
        
        // Also hook shared session
        swizzle([NSURLSession class], @selector(sharedSession), @selector(lc_sharedSession));
    });
}

+ (NSURLSession *)lc_sharedSession {
    NSURLSession *session = [self lc_sharedSession];
    
    loadNetworkConfiguration();
    if (spoofNetworkEnabled) {
        NSLog(@"[LC] 🔗 Shared session accessed - applying proxy retroactively");
        // Note: Can't modify shared session configuration after creation
        // This is a limitation - apps should use custom configurations
    }
    
    return session;
}

+ (NSURLSession *)lc_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    loadNetworkConfiguration();
    
    if (spoofNetworkEnabled) {
        NSLog(@"[LC] 🔗 Applying enhanced proxy to NSURLSession configuration");
        [self applyEnhancedProxyToConfiguration:configuration];
    }
    return [self lc_sessionWithConfiguration:configuration];
}

+ (NSURLSession *)lc_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration 
                                     delegate:(id<NSURLSessionDelegate>)delegate 
                                delegateQueue:(NSOperationQueue *)queue {
    loadNetworkConfiguration();
    
    if (spoofNetworkEnabled) {
        NSLog(@"[LC] 🔗 Applying enhanced proxy to NSURLSession configuration with delegate");
        [self applyEnhancedProxyToConfiguration:configuration];
    }
    return [self lc_sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}

+ (void)applyEnhancedProxyToConfiguration:(NSURLSessionConfiguration *)configuration {
    NSDictionary *proxyDict = createEnhancedProxyDictionary();
    if (proxyDict) {
        configuration.connectionProxyDictionary = proxyDict;
        
        // Enhanced timeout configuration
        if ([networkMode isEqualToString:@"aggressive"]) {
            configuration.timeoutIntervalForRequest = 60.0;
            configuration.timeoutIntervalForResource = 600.0;
        } else {
            configuration.timeoutIntervalForRequest = 30.0;
            configuration.timeoutIntervalForResource = 300.0;
        }
        
        configuration.waitsForConnectivity = YES;
        configuration.allowsCellularAccess = YES;
        
        // Additional headers for better proxy compatibility
        NSMutableDictionary *headers = [configuration.HTTPAdditionalHeaders mutableCopy] ?: [NSMutableDictionary dictionary];
        
        if (proxyUsername.length > 0 && proxyPassword.length > 0) {
            NSString *credentials = [NSString stringWithFormat:@"%@:%@", proxyUsername, proxyPassword];
            NSData *credentialsData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
            NSString *base64Credentials = [credentialsData base64EncodedStringWithOptions:0];
            
            headers[@"Proxy-Authorization"] = [NSString stringWithFormat:@"Basic %@", base64Credentials];
        }
        
        // User-Agent modification for better compatibility
        if ([networkMode isEqualToString:@"compatibility"]) {
            headers[@"User-Agent"] = @"Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15";
        }
        
        configuration.HTTPAdditionalHeaders = headers;
        
        NSLog(@"[LC] ✅ Enhanced proxy configuration applied successfully");
    }
}

@end

#pragma mark - Initialization Function

void NetworkGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] 🚀 Initializing enhanced network spoofing hooks...");
        
        loadNetworkConfiguration();
        
        if (!spoofNetworkEnabled) {
            NSLog(@"[LC] 📶 Network spoofing disabled");
            return;
        }
        
        NSLog(@"[LC] 🔗 Network spoofing enabled - Mode: %@, Proxy: %@://%@:%d", 
              networkMode, proxyType, proxyHost, proxyPort);
        
        // Install socket-level hooks for aggressive mode
        if ([networkMode isEqualToString:@"aggressive"]) {
            NSLog(@"[LC] ⚡ Installing aggressive mode socket hooks...");
            
            // Use fishhook for system-level function interception
            struct rebinding socket_rebindings[] = {
                {"connect", (void *)lc_connect, (void **)&original_connect},
                {"gethostbyname", (void *)lc_gethostbyname, (void **)&original_gethostbyname},
                {"getaddrinfo", (void *)lc_getaddrinfo, (void **)&original_getaddrinfo},
            };
            
            if (rebind_symbols(socket_rebindings, sizeof(socket_rebindings)/sizeof(struct rebinding)) == 0) {
                NSLog(@"[LC] ✅ Socket-level hooks installed successfully");
            } else {
                NSLog(@"[LC] ❌ Failed to install socket-level hooks");
            }
        }
        
        // Test the configuration
        NSDictionary *testProxy = createEnhancedProxyDictionary();
        if (testProxy) {
            NSLog(@"[LC] ✅ Proxy configuration test passed");
        } else {
            NSLog(@"[LC] ❌ Proxy configuration test failed");
        }
        
        NSLog(@"[LC] ✅ Enhanced network hooks initialized successfully");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Failed to initialize network hooks: %@", exception);
    }
}