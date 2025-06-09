#include <Foundation/Foundation.h>

@interface NSBundle(private)
- (id)_cfBundle;
@end

@interface NSUserDefaults(private)
+ (void)setStandardUserDefaults:(id)defaults;
- (NSString*)_identifier;
@end

@interface NSExtension : NSObject
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void(^)(NSUUID *))callback;
- (int)pidForRequestIdentifier:(NSUUID *)identifier;
- (void)_kill:(int)arg1;
- (void)setRequestInterruptionBlock:(void(^)(NSUUID *))callback;
- (void)_hostDidEnterBackgroundNote:(NSNotification *)note;
@end

void* SecTaskCreateFromSelf(CFAllocatorRef allocator);
NSString *SecTaskCopyTeamIdentifier(void *task, NSError **error);
CFTypeRef SecTaskCopyValueForEntitlement(void *task, CFStringRef key, CFErrorRef *error);
