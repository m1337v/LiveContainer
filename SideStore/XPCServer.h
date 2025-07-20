//
//  XPCServer.h
//  LiveContainer
//
//  Created by s s on 2025/7/20.
//

#import <Foundation/Foundation.h>

@protocol RefreshProgressReporting
- (void)updateProgress:(float)value;
- (void)finish:(NSString*)error;
- (NSString*)test;
@end

NSXPCListener* startAnonymousListener(NSObject<RefreshProgressReporting>* reporter);
NSData* bookmarkForURL(NSURL* url);
