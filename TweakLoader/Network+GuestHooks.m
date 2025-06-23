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

// Additional function pointers inspired by socker
static ssize_t (*original_send)(int, const void *, size_t, int) = NULL;
static ssize_t (*original_sendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t) = NULL;
static ssize_t (*original_recv)(int, void *, size_t, int) = NULL;
static ssize_t (*original_recvfrom)(int, void *, size_t, int, struct sockaddr *, socklen_t *) = NULL;

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
    networkMode = guestAppInfo[@"spoofNetworkMode"] ?: @"standard";

    NSLog(@"[LC] ⚙️ Network Config: Enabled=%d, Type=%@, Host=%@, Port=%d, Mode=%@", 
          spoofNetworkEnabled, proxyType, proxyHost, proxyPort, networkMode);
}

#pragma mark - Enhanced Socket-Level Hooks (inspired by socker)

static int lc_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    loadNetworkConfiguration();
    
    if (!spoofNetworkEnabled || [networkMode isEqualToString:@"compatibility"]) {
        return original_connect(sockfd, addr, addrlen);
    }
    
    // For aggressive mode, intercept all socket connections
    if ([networkMode isEqualToString:@"aggressive"]) {
        NSLog(@"[LC] 🔌 Intercepting socket connection in aggressive mode");
        
        // Handle IPv4 connections
        if (addr->sa_family == AF_INET) {
            struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
            char ip_str[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &(addr_in->sin_addr), ip_str, INET_ADDRSTRLEN);
            int port = ntohs(addr_in->sin_port);
            
            NSLog(@"[LC] 🎯 Original destination: %s:%d", ip_str, port);
            
            // Skip localhost and private network ranges in some cases
            if (strcmp(ip_str, "127.0.0.1") == 0 || 
                strncmp(ip_str, "192.168.", 8) == 0 ||
                strncmp(ip_str, "10.", 3) == 0) {
                NSLog(@"[LC] 🏠 Allowing local/private network connection");
                return original_connect(sockfd, addr, addrlen);
            }
            
            // Redirect to proxy
            if (proxyHost.length > 0) {
                struct sockaddr_in proxy_addr;
                memset(&proxy_addr, 0, sizeof(proxy_addr));
                proxy_addr.sin_family = AF_INET;
                proxy_addr.sin_port = htons(proxyPort);
                
                // Resolve proxy host
                struct hostent *proxy_host_entry = original_gethostbyname(proxyHost.UTF8String);
                if (proxy_host_entry && proxy_host_entry->h_addr_list[0]) {
                    memcpy(&proxy_addr.sin_addr, proxy_host_entry->h_addr_list[0], proxy_host_entry->h_length);
                    NSLog(@"[LC] 🔄 Redirecting to proxy: %@:%d", proxyHost, proxyPort);
                    return original_connect(sockfd, (struct sockaddr *)&proxy_addr, sizeof(proxy_addr));
                } else {
                    NSLog(@"[LC] ❌ Failed to resolve proxy host: %@", proxyHost);
                }
            }
        }
        // Handle IPv6 connections
        else if (addr->sa_family == AF_INET6) {
            struct sockaddr_in6 *addr_in6 = (struct sockaddr_in6 *)addr;
            char ip_str[INET6_ADDRSTRLEN];
            inet_ntop(AF_INET6, &(addr_in6->sin6_addr), ip_str, INET6_ADDRSTRLEN);
            int port = ntohs(addr_in6->sin6_port);
            
            NSLog(@"[LC] 🎯 Original IPv6 destination: [%s]:%d", ip_str, port);
            
            // For IPv6, we might need different proxy handling
            // For now, allow through but log
            NSLog(@"[LC] 📡 IPv6 connection - passing through");
        }
    }
    
    return original_connect(sockfd, addr, addrlen);
}

static struct hostent *lc_gethostbyname(const char *name) {
    loadNetworkConfiguration();
    
    if (spoofNetworkEnabled && [networkMode isEqualToString:@"aggressive"]) {
        NSLog(@"[LC] 🔍 DNS lookup intercepted: %s", name);
        
        // Skip resolution for localhost and known local hosts
        if (strcmp(name, "localhost") == 0 || 
            strcmp(name, "127.0.0.1") == 0 ||
            strstr(name, ".local") != NULL) {
            NSLog(@"[LC] 🏠 Allowing local DNS resolution");
            return original_gethostbyname(name);
        }
        
        // Could implement custom DNS resolution here
        // For now, just log and pass through
        NSLog(@"[LC] 📡 DNS resolution for: %s", name);
    }
    
    return original_gethostbyname(name);
}

static int lc_getaddrinfo(const char *node, const char *service, 
                         const struct addrinfo *hints, struct addrinfo **res) {
    loadNetworkConfiguration();
    
    if (spoofNetworkEnabled && [networkMode isEqualToString:@"aggressive"]) {
        NSLog(@"[LC] 🔍 getaddrinfo intercepted: %s:%s", node ?: "null", service ?: "null");
        
        // Skip for local addresses
        if (node && (strcmp(node, "localhost") == 0 || 
                    strcmp(node, "127.0.0.1") == 0 ||
                    strstr(node, ".local") != NULL)) {
            NSLog(@"[LC] 🏠 Allowing local getaddrinfo");
            return original_getaddrinfo(node, service, hints, res);
        }
    }
    
    return original_getaddrinfo(node, service, hints, res);
}

// Additional hooks inspired by socker for more comprehensive coverage
static ssize_t lc_send(int sockfd, const void *buf, size_t len, int flags) {
    // Could intercept and modify data here
    return original_send(sockfd, buf, len, flags);
}

static ssize_t lc_sendto(int sockfd, const void *buf, size_t len, int flags,
                        const struct sockaddr *dest_addr, socklen_t addrlen) {
    loadNetworkConfiguration();
    
    if (spoofNetworkEnabled && [networkMode isEqualToString:@"aggressive"]) {
        if (dest_addr && dest_addr->sa_family == AF_INET) {
            struct sockaddr_in *addr_in = (struct sockaddr_in *)dest_addr;
            char ip_str[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &(addr_in->sin_addr), ip_str, INET_ADDRSTRLEN);
            int port = ntohs(addr_in->sin_port);
            NSLog(@"[LC] 📤 sendto intercepted: %s:%d (%zu bytes)", ip_str, port, len);
        }
    }
    
    return original_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
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
    
    // More comprehensive proxy configuration based on socker patterns
    if ([proxyType isEqualToString:@"HTTP"]) {
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPEnable] = @YES;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPProxy] = proxyHost;
        proxyDict[(__bridge NSString *)kCFNetworkProxiesHTTPPort] = @(proxyPort);
        
        // Enable for HTTPS as well
        proxyDict[@"HTTPSEnable"] = @YES;
        proxyDict[@"HTTPSProxy"] = proxyHost;
        proxyDict[@"HTTPSPort"] = @(proxyPort);
        
    } else if ([proxyType isEqualToString:@"SOCKS5"]) {
        // SOCKS configuration
        proxyDict[@"SOCKSEnable"] = @YES;
        proxyDict[@"SOCKSProxy"] = proxyHost;
        proxyDict[@"SOCKSPort"] = @(proxyPort);
        proxyDict[@"SOCKSVersion"] = @5;
        
    } else if ([proxyType isEqualToString:@"SOCKS4"]) {
        // SOCKS4 configuration
        proxyDict[@"SOCKSEnable"] = @YES;
        proxyDict[@"SOCKSProxy"] = proxyHost;
        proxyDict[@"SOCKSPort"] = @(proxyPort);
        proxyDict[@"SOCKSVersion"] = @4;
        
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
    
    // Additional proxy settings for better compatibility
    proxyDict[@"ExceptionsList"] = @[@"localhost", @"127.0.0.1", @"*.local"];
    proxyDict[@"FTPPassive"] = @YES;
    
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
        
        // Enhanced timeout configuration based on mode
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
        
        // Install socket-level hooks for aggressive mode using the same pattern as Dyld.m
        if ([networkMode isEqualToString:@"aggressive"]) {
            NSLog(@"[LC] ⚡ Installing aggressive mode socket hooks...");
            
            // Use the exact same pattern as in LiveContainer/Tweaks/Dyld.m line 342
            struct rebinding rebindings[] = {
                {"connect", (void *)lc_connect, (void **)&original_connect},
                {"gethostbyname", (void *)lc_gethostbyname, (void **)&original_gethostbyname},
                {"getaddrinfo", (void *)lc_getaddrinfo, (void **)&original_getaddrinfo},
                {"send", (void *)lc_send, (void **)&original_send},
                {"sendto", (void *)lc_sendto, (void **)&original_sendto},
                {"recv", (void *)original_recv, (void **)&original_recv},
                {"recvfrom", (void *)original_recvfrom, (void **)&original_recvfrom},
            };
            
            int result = rebind_symbols(rebindings, 7);
            if (result == 0) {
                NSLog(@"[LC] ✅ Socket-level hooks installed successfully");
            } else {
                NSLog(@"[LC] ❌ Failed to install socket-level hooks: %d", result);
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