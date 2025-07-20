//
//  XPCServer.m
//  LiveContainer
//
//  Created by s s on 2025/7/20.
//

#import <Foundation/Foundation.h>
#import "XPCServer.h"


@interface ServerDelegate : NSObject <NSXPCListenerDelegate>
@property NSObject<RefreshProgressReporting>* reporter;
@end

@implementation ServerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(RefreshProgressReporting)];
    newConnection.exportedObject = self.reporter;
    [newConnection resume];
    return YES;
}

@end

NSXPCListener* startAnonymousListener(NSObject<RefreshProgressReporting>* reporter) {
    ServerDelegate *delegate = [ServerDelegate new];
    delegate.reporter = reporter;
    NSXPCListener *listener = [NSXPCListener anonymousListener];
    listener.delegate = delegate;
    [listener resume];
    return listener;
}

NSData* bookmarkForURL(NSURL* url) {
    return [url bookmarkDataWithOptions:(1<<11) includingResourceValuesForKeys:0 relativeToURL:0 error:0];
}
