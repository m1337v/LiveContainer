@import AuthenticationServices;
#import "utils.h"
#import "LCSharedUtils.h"

__attribute__((constructor))
static void AuthenticationServicesGuestHooksInit() {
    // Only hook if running as guest app (not LiveContainer itself)
    if ([NSUserDefaults guestAppInfo]) {
        swizzle([ASAuthorizationAppleIDProvider class], @selector(createRequest), @selector(hook_createRequest));
        swizzle([ASAuthorizationController class], @selector(initWithAuthorizationRequests:), @selector(hook_initWithAuthorizationRequests:));
    }
}

@implementation ASAuthorizationAppleIDProvider (LiveContainerHooks)

- (ASAuthorizationAppleIDRequest *)hook_createRequest {
    ASAuthorizationAppleIDRequest *request = [self hook_createRequest];
    
    // Map the bundle ID to LiveContainer's bundle ID for Apple's servers
    // but preserve the guest app's identity in user-facing elements
    NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
    NSString *guestBundleId = guestAppInfo[@"CFBundleIdentifier"];
    NSString *lcBundleId = [NSBundle mainBundle].bundleIdentifier;
    
    if (guestBundleId && ![guestBundleId isEqualToString:lcBundleId]) {
        // Store the original bundle ID for potential user display
        objc_setAssociatedObject(request, @"guestBundleId", guestBundleId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"[LC] 🍎 Apple Sign In request created for guest app: %@", guestBundleId);
    }
    
    return request;
}

@end

@implementation ASAuthorizationController (LiveContainerHooks)

- (instancetype)hook_initWithAuthorizationRequests:(NSArray<ASAuthorizationRequest *> *)authorizationRequests {
    // Log the authentication attempt
    NSLog(@"[LC] 🍎 Apple Sign In controller initialized with %lu requests", (unsigned long)authorizationRequests.count);
    
    return [self hook_initWithAuthorizationRequests:authorizationRequests];
}

@end