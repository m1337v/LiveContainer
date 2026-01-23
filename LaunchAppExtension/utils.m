//
//  utils.m
//  LiveContainer
//
//  Created by s s on 2026/1/23.
//
@import Foundation;
@import ObjectiveC;

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)openURL:(id)url;
- (BOOL)isApplicationAvailableToOpenURL:(id)arg1 error:(id*)arg2;
@end

#define PrivClass(name) ((Class)objc_lookUpClass(#name))

bool lsApplicationWorkspaceCanOpenURL(NSURL* url) {
    LSApplicationWorkspace* workspace = [PrivClass(LSApplicationWorkspace) defaultWorkspace];
    NSError* error;
    BOOL success = [workspace isApplicationAvailableToOpenURL:url error:&error];
    return success;
}
