//
//  main.m
//  LiveContainer
//
//  Created by s s on 2026/2/17.
//
#import "../LiveContainer/utils.h"
#import "../LiveContainer/UIKitPrivate.h"

@interface LaunchAppExtensionHelperHandler : NSObject<NSExtensionRequestHandling>
@end
@implementation LaunchAppExtensionHelperHandler
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    // unfortunately SpringBoard blocks openURL for iOS 10+ new extension types, so we need to chain load another extension with old extension type to open the URL
    [[PrivClass(LSApplicationWorkspace) defaultWorkspace] openURL:[[context.inputItems.firstObject userInfo] valueForKey:@"url"]];
}
@end
