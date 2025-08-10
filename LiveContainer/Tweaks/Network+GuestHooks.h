//
//  Network+GuestHooks.h
//  LiveContainer
//
//  Network spoofing hooks for routing traffic through proxies
//

#import <Foundation/Foundation.h>

// Initialize network hooks
void NetworkGuestHooksInit(void);

// Proxy configuration structure
typedef struct {
    BOOL enabled;
    NSString *host;
    int port;
    NSString *username;
    NSString *password;
} LCProxyConfig;

// Get current proxy configuration
LCProxyConfig* getCurrentProxyConfig(void);