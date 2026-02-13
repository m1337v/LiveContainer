//
//  SecItem.m
//  LiveContainer
//
//  Created by s s on 2024/11/29.
//
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "utils.h"
#import <CommonCrypto/CommonDigest.h>
#import "../../litehook/src/litehook.h"
#import "LCSharedUtils.h"

extern void* (*msHookFunction)(void *symbol, void *hook, void **old);
OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result) = SecItemAdd;
OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result) = SecItemCopyMatching;
OSStatus (*orig_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) = SecItemUpdate;
OSStatus (*orig_SecItemDelete)(CFDictionaryRef query) = SecItemDelete;
SecKeyRef (*orig_SecKeyCreateRandomKey)(CFDictionaryRef parameters, CFErrorRef *error) = SecKeyCreateRandomKey;
SecKeyRef (*orig_SecKeyCreateWithData)(CFDataRef keyData, CFDictionaryRef parameters, CFErrorRef *error) = SecKeyCreateWithData;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
OSStatus (*orig_SecKeyGeneratePair)(CFDictionaryRef query, SecKeyRef *publicKey, SecKeyRef *privateKey) = SecKeyGeneratePair;
#pragma clang diagnostic pop
NSString* accessGroup = nil;
NSString* containerId = nil;
static NSString *const kLCContainerAliasAttribute = @"alis";

static NSMutableDictionary *LCCreateMutableDictionary(CFDictionaryRef dictionary) {
    if (!dictionary) {
        return [NSMutableDictionary dictionary];
    }
    id object = (__bridge id)dictionary;
    if (![object isKindOfClass:NSDictionary.class]) {
        return [NSMutableDictionary dictionary];
    }
    return [((NSDictionary *)object) mutableCopy];
}

static void LCApplyScopedAccessGroup(NSMutableDictionary *dictionary) {
    if (accessGroup.length > 0) {
        dictionary[(__bridge id)kSecAttrAccessGroup] = accessGroup;
    }
}

static void LCApplyContainerAlias(NSMutableDictionary *dictionary) {
    if (containerId.length > 0) {
        dictionary[kLCContainerAliasAttribute] = containerId;
    }
}

static NSMutableDictionary *LCCreateScopedDictionary(CFDictionaryRef dictionary, BOOL includeContainerAlias) {
    NSMutableDictionary *scoped = LCCreateMutableDictionary(dictionary);
    LCApplyScopedAccessGroup(scoped);
    if (includeContainerAlias) {
        LCApplyContainerAlias(scoped);
    }
    return scoped;
}

static BOOL LCBoolValue(id value) {
    if (!value || ![value respondsToSelector:@selector(boolValue)]) {
        return NO;
    }
    return [value boolValue];
}

static BOOL LCPersistsSecKeyInKeychain(CFDictionaryRef parameters) {
    if (!parameters) {
        return NO;
    }
    id object = (__bridge id)parameters;
    if (![object isKindOfClass:NSDictionary.class]) {
        return NO;
    }

    NSDictionary *params = (NSDictionary *)object;
    if (LCBoolValue(params[(__bridge id)kSecAttrIsPermanent])) {
        return YES;
    }

    id privateKeyAttrs = params[(__bridge id)kSecPrivateKeyAttrs];
    if ([privateKeyAttrs isKindOfClass:NSDictionary.class] &&
        LCBoolValue(((NSDictionary *)privateKeyAttrs)[(__bridge id)kSecAttrIsPermanent])) {
        return YES;
    }

    id publicKeyAttrs = params[(__bridge id)kSecPublicKeyAttrs];
    if ([publicKeyAttrs isKindOfClass:NSDictionary.class] &&
        LCBoolValue(((NSDictionary *)publicKeyAttrs)[(__bridge id)kSecAttrIsPermanent])) {
        return YES;
    }

    return NO;
}

static NSString *LCRequestedAccessGroup(CFDictionaryRef dictionary) {
    if (!dictionary) {
        return nil;
    }
    id object = (__bridge id)dictionary;
    if (![object isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    id requested = ((NSDictionary *)object)[(__bridge id)kSecAttrAccessGroup];
    if ([requested isKindOfClass:NSString.class] && ((NSString *)requested).length > 0) {
        return (NSString *)requested;
    }
    return nil;
}

static CFTypeRef LCRewrittenResultObject(CFTypeRef resultObject, NSString *requestedAccessGroup) {
    if (!resultObject || requestedAccessGroup.length == 0) {
        return resultObject ? CFRetain(resultObject) : NULL;
    }

    CFTypeID typeId = CFGetTypeID(resultObject);
    if (typeId == CFDictionaryGetTypeID()) {
        CFMutableDictionaryRef mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, (CFDictionaryRef)resultObject);
        if (!mutable) {
            return CFRetain(resultObject);
        }
        if (CFDictionaryContainsKey(mutable, kSecAttrAccessGroup)) {
            CFDictionarySetValue(mutable, kSecAttrAccessGroup, (__bridge const void *)requestedAccessGroup);
        }
        CFTypeRef rewritten = CFDictionaryCreateCopy(kCFAllocatorDefault, mutable);
        CFRelease(mutable);
        return rewritten ?: CFRetain(resultObject);
    }

    if (typeId == CFArrayGetTypeID()) {
        CFArrayRef originalArray = (CFArrayRef)resultObject;
        CFMutableArrayRef mutableArray = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, originalArray);
        if (!mutableArray) {
            return CFRetain(resultObject);
        }
        CFIndex count = CFArrayGetCount(mutableArray);
        for (CFIndex idx = 0; idx < count; idx++) {
            CFTypeRef entry = CFArrayGetValueAtIndex(mutableArray, idx);
            if (!entry || CFGetTypeID(entry) != CFDictionaryGetTypeID()) {
                continue;
            }
            CFMutableDictionaryRef mutableEntry = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, (CFDictionaryRef)entry);
            if (!mutableEntry) {
                continue;
            }
            if (CFDictionaryContainsKey(mutableEntry, kSecAttrAccessGroup)) {
                CFDictionarySetValue(mutableEntry, kSecAttrAccessGroup, (__bridge const void *)requestedAccessGroup);
            }
            CFArraySetValueAtIndex(mutableArray, idx, mutableEntry);
            CFRelease(mutableEntry);
        }
        CFTypeRef rewritten = CFArrayCreateCopy(kCFAllocatorDefault, mutableArray);
        CFRelease(mutableArray);
        return rewritten ?: CFRetain(resultObject);
    }

    return CFRetain(resultObject);
}

static void LCRewriteCopyMatchingResult(CFTypeRef *result, NSString *requestedAccessGroup) {
    if (!result || !*result || requestedAccessGroup.length == 0) {
        return;
    }
    CFTypeRef rewritten = LCRewrittenResultObject(*result, requestedAccessGroup);
    if (!rewritten) {
        return;
    }
    CFRelease(*result);
    *result = rewritten;
}

OSStatus new_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSMutableDictionary *scopedAttributes = LCCreateScopedDictionary(attributes, YES);
    OSStatus status = orig_SecItemAdd((__bridge CFDictionaryRef)scopedAttributes, result);
    if (status == errSecParam) {
        // Some SecItem classes reject alias keys; retry while staying scoped.
        NSMutableDictionary *legacyScopedAttributes = LCCreateScopedDictionary(attributes, NO);
        status = orig_SecItemAdd((__bridge CFDictionaryRef)legacyScopedAttributes, result);
    }

    return status;
}

OSStatus new_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSString *requestedAccessGroup = LCRequestedAccessGroup(query);
    NSMutableDictionary *scopedQuery = LCCreateScopedDictionary(query, YES);
    OSStatus status = orig_SecItemCopyMatching((__bridge CFDictionaryRef)scopedQuery, result);
    if (status == errSecItemNotFound || status == errSecParam) {
        // Keep access-group scoping, but support legacy items without alias tagging.
        NSMutableDictionary *legacyScopedQuery = LCCreateScopedDictionary(query, NO);
        status = orig_SecItemCopyMatching((__bridge CFDictionaryRef)legacyScopedQuery, result);
    }
    if (status == errSecSuccess) {
        LCRewriteCopyMatchingResult(result, requestedAccessGroup);
    }

    return status;
}

OSStatus new_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSMutableDictionary *scopedQuery = LCCreateScopedDictionary(query, YES);
    NSMutableDictionary *scopedAttributes = LCCreateScopedDictionary(attributesToUpdate, NO);
    OSStatus status = orig_SecItemUpdate((__bridge CFDictionaryRef)scopedQuery, (__bridge CFDictionaryRef)scopedAttributes);

    if (status == errSecItemNotFound || status == errSecParam) {
        NSMutableDictionary *legacyScopedQuery = LCCreateScopedDictionary(query, NO);
        status = orig_SecItemUpdate((__bridge CFDictionaryRef)legacyScopedQuery, (__bridge CFDictionaryRef)scopedAttributes);
    }

    return status;
}

OSStatus new_SecItemDelete(CFDictionaryRef query){
    NSMutableDictionary *scopedQuery = LCCreateScopedDictionary(query, YES);
    OSStatus status = orig_SecItemDelete((__bridge CFDictionaryRef)scopedQuery);
    if (status == errSecItemNotFound || status == errSecParam) {
        NSMutableDictionary *legacyScopedQuery = LCCreateScopedDictionary(query, NO);
        status = orig_SecItemDelete((__bridge CFDictionaryRef)legacyScopedQuery);
    }

    return status;
}

SecKeyRef new_SecKeyCreateRandomKey(CFDictionaryRef parameters, CFErrorRef *error) {
    if (!LCPersistsSecKeyInKeychain(parameters) || accessGroup.length == 0) {
        return orig_SecKeyCreateRandomKey(parameters, error);
    }
    NSMutableDictionary *paramsCopy = LCCreateMutableDictionary(parameters);
    LCApplyScopedAccessGroup(paramsCopy);
    return orig_SecKeyCreateRandomKey((__bridge CFDictionaryRef)paramsCopy, error);
}

SecKeyRef new_SecKeyCreateWithData(CFDataRef keyData, CFDictionaryRef parameters, CFErrorRef *error) {
    if (!LCPersistsSecKeyInKeychain(parameters) || accessGroup.length == 0) {
        return orig_SecKeyCreateWithData(keyData, parameters, error);
    }
    NSMutableDictionary *paramsCopy = LCCreateMutableDictionary(parameters);
    LCApplyScopedAccessGroup(paramsCopy);
    return orig_SecKeyCreateWithData(keyData, (__bridge CFDictionaryRef)paramsCopy, error);
}

OSStatus new_SecKeyGeneratePair(CFDictionaryRef parameters, SecKeyRef *publicKey, SecKeyRef *privateKey) {
    if (!LCPersistsSecKeyInKeychain(parameters) || accessGroup.length == 0) {
        return orig_SecKeyGeneratePair(parameters, publicKey, privateKey);
    }
    NSMutableDictionary *queryCopy = LCCreateMutableDictionary(parameters);
    LCApplyScopedAccessGroup(queryCopy);
    return orig_SecKeyGeneratePair((__bridge CFDictionaryRef)queryCopy, publicKey, privateKey);
}

void SecItemGuestHooksInit(void)  {

    NSDictionary* infoDict = [NSUserDefaults guestContainerInfo];
    NSString *plistContainerId = [infoDict[@"folderName"] isKindOfClass:NSString.class] ? infoDict[@"folderName"] : nil;
    if (plistContainerId.length > 0) {
        containerId = plistContainerId;
    } else {
        const char *homePath = getenv("HOME");
        containerId = homePath ? [NSString stringWithUTF8String:homePath].lastPathComponent : nil;
    }

    NSInteger keychainGroupId = [infoDict[@"keychainGroupId"] integerValue];
    if (keychainGroupId < 0) {
        keychainGroupId = 0;
    }

    NSString* groupId = [LCSharedUtils teamIdentifier];
    if (groupId.length == 0) {
        NSLog(@"[LC] failed to detect team identifier for keychain isolation");
        return;
    }

    if(keychainGroupId == 0) {
        accessGroup = [NSString stringWithFormat:@"%@.com.kdt.livecontainer.shared", groupId];
    } else {
        accessGroup = [NSString stringWithFormat:@"%@.com.kdt.livecontainer.shared.%ld", groupId, (long)keychainGroupId];
    }
    
    // check if the keychain access group is available
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: @"NonExistentKey",
        (__bridge id)kSecAttrService: @"NonExistentService",
        (__bridge id)kSecAttrAccessGroup: accessGroup,
        (__bridge id)kSecReturnData: @NO
    };
    
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    if(status == errSecMissingEntitlement) {
        NSLog(@"[LC] failed to access keychain access group %@", accessGroup);
        return;
    }
    
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, SecItemAdd, new_SecItemAdd, nil);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, SecItemCopyMatching, new_SecItemCopyMatching, nil);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, SecItemUpdate, new_SecItemUpdate, nil);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, SecItemDelete, new_SecItemDelete, nil);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, SecKeyCreateRandomKey, new_SecKeyCreateRandomKey, nil);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, SecKeyCreateWithData, new_SecKeyCreateWithData, nil);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, SecKeyGeneratePair, new_SecKeyGeneratePair, nil);
}
