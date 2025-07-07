//
//  Dyld.m
//  LiveContainer
//
//  Created by s s on 2025/2/7.
//
#include <dlfcn.h>
#include <stdlib.h>
#import "../../fishhook/fishhook.h"
#import "../../litehook/src/litehook.h"
#import "../utils.h"
#include <sys/mman.h>
#include <ctype.h>
#include <ifaddrs.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netdb.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <CFNetwork/CFNetwork.h>
@import Darwin;
@import Foundation;
@import MachO;

typedef uint32_t dyld_platform_t;

typedef struct {
    dyld_platform_t platform;
    uint32_t        version;
} dyld_build_version_t;

uint32_t lcImageIndex = 0;
uint32_t tweakLoaderIndex = 0;
uint32_t appMainImageIndex = 0;
void* appExecutableHandle = 0;
bool tweakLoaderLoaded = false;
bool appExecutableFileTypeOverwritten = false;

void* (*orig_dlsym)(void * __handle, const char * __symbol);
uint32_t (*orig_dyld_image_count)(void);
const struct mach_header* (*orig_dyld_get_image_header)(uint32_t image_index);
intptr_t (*orig_dyld_get_image_vmaddr_slide)(uint32_t image_index);
const char* (*orig_dyld_get_image_name)(uint32_t image_index);
// VPN Detection Bypass hooks
static CFDictionaryRef (*orig_CFNetworkCopySystemProxySettings)(void);
// Signal handlers
int (*orig_sigaction)(int sig, const struct sigaction *restrict act, struct sigaction *restrict oact);

uint32_t guestAppSdkVersion = 0;
uint32_t guestAppSdkVersionSet = 0;
bool (*orig_dyld_program_sdk_at_least)(void* dyldPtr, dyld_build_version_t version);
uint32_t (*orig_dyld_get_program_sdk_version)(void* dyldPtr);



static void overwriteAppExecutableFileType(void) {
    struct mach_header_64* appImageMachOHeader = (struct mach_header_64*) orig_dyld_get_image_header(appMainImageIndex);
    kern_return_t kret = builtin_vm_protect(mach_task_self(), (vm_address_t)appImageMachOHeader, sizeof(appImageMachOHeader), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    if(kret != KERN_SUCCESS) {
        NSLog(@"[LC] failed to change appImageMachOHeader to rw");
    } else {
        NSLog(@"[LC] changed appImageMachOHeader to rw");
        appImageMachOHeader->filetype = MH_EXECUTE;
        builtin_vm_protect(mach_task_self(), (vm_address_t)appImageMachOHeader, sizeof(appImageMachOHeader), false,  PROT_READ);
    }
}

// MARK: shouldHideLibrary
// static bool shouldHideLibrary(const char* imageName) {
//     if (!imageName) return false;
    
//     // Only hide exact matches to avoid breaking legitimate frameworks
//     return (strstr(imageName, "TweakLoader.dylib") ||
//             strstr(imageName, "LiveContainerShared") ||
//             strstr(imageName, "CydiaSubstrate") ||
//             strstr(imageName, "MobileSubstrate") ||
//             strstr(imageName, "substrate") ||
//             strstr(imageName, "fishhook") ||
//             (strstr(imageName, "LiveContainer") && strstr(imageName, ".app/")));
// }

static bool shouldHideLibrary(const char* imageName) {
    if (!imageName) return false;
    
    // Convert to lowercase for case-insensitive comparison
    char lowerImageName[1024];
    strlcpy(lowerImageName, imageName, sizeof(lowerImageName));
    for (int i = 0; lowerImageName[i]; i++) {
        lowerImageName[i] = tolower(lowerImageName[i]);
    }
    
    // Ultra-minimal - only what Reveil specifically looks for
    return (strstr(lowerImageName, "substrate") ||      // All substrate variants
            strstr(lowerImageName, "tweakloader") ||    // TweakLoader
            strstr(lowerImageName, "livecontainershared"));   // LiveContainerShared
}

static void ensureAppMainIndexIsSet(void) {
    if (appMainImageIndex != 0) {
        return; // Already found
    }
    
    // Find the guest app executable (not LiveContainer)
    int imageCount = orig_dyld_image_count();
    for(int i = 0; i < imageCount; ++i) {
        const struct mach_header* currentImageHeader = orig_dyld_get_image_header(i);
        const char* imageName = orig_dyld_get_image_name(i);
        
        if(currentImageHeader && currentImageHeader->filetype == MH_EXECUTE && 
           imageName && i != lcImageIndex && !strstr(imageName, "LiveContainer.app")) {
            
            appMainImageIndex = i;
            NSLog(@"[LC] Found guest app at index %d: %s", i, imageName);
            return;
        }
    }
    
    NSLog(@"[LC] ERROR: Could not find guest app executable!");
}

// Helper for LiveContainer special case handling
// static bool isLiveContainerImage(uint32_t imageIndex, const char* imageName) {
//     return imageIndex == lcImageIndex || (imageName && strstr(imageName, "LiveContainer"));
// }

// static uint32_t handleLiveContainerReplacement(uint32_t imageIndex) {
//     if (imageIndex == lcImageIndex) {
//         if (!appExecutableFileTypeOverwritten) {
//             overwriteAppExecutableFileType();
//             appExecutableFileTypeOverwritten = true;
//         }
//         return appMainImageIndex;
//     }
//     return imageIndex;
// }

// static inline int translateImageIndex(int origin) {
//     if(origin == lcImageIndex) {
//         if(!appExecutableFileTypeOverwritten) {
//             overwriteAppExecutableFileType();
//             appExecutableFileTypeOverwritten = true;
//         }
        
//         return appMainImageIndex;
//     }
    
//     // find tweakloader index
//     if(tweakLoaderLoaded && tweakLoaderIndex == 0) {
//         const char* tweakloaderPath = [[[[NSUserDefaults lcMainBundle] bundlePath] stringByAppendingPathComponent:@"Frameworks/TweakLoader.dylib"] UTF8String];
//         if(tweakloaderPath) {
//             uint32_t imageCount = orig_dyld_image_count();
//             for(uint32_t i = imageCount - 1; i >= 0; --i) {
//                 const char* imgName = orig_dyld_get_image_name(i);
//                 if(imgName && strcmp(imgName, tweakloaderPath) == 0) {
//                     tweakLoaderIndex = i;
//                     break;
//                 }
//             }
//         }

//         if(tweakLoaderIndex == 0) {
//             tweakLoaderIndex = -1; // can't find, don't search again in the future
//         }
//     }
    
//     if(tweakLoaderLoaded && tweakLoaderIndex > 0 && origin >= tweakLoaderIndex) {
//         return origin + 2;
//     } else if(origin >= appMainImageIndex) {
//         return origin + 1;
//     }
//     return origin;
// }

void* hook_dlsym(void * __handle, const char * __symbol) {
    // Hide jailbreak detection symbols
    if (__symbol && (
        // MobileSubstrate/Substrate
        strcmp(__symbol, "MSHookFunction") == 0 ||
        strcmp(__symbol, "MSHookMessageEx") == 0 ||
        strcmp(__symbol, "MSFindSymbol") == 0 ||
        strcmp(__symbol, "MSGetImageByName") == 0 ||
        strcmp(__symbol, "MSImageFromName") == 0 ||
        strcmp(__symbol, "MSSymbolFromName") == 0 ||
        strcmp(__symbol, "_MSHookFunction") == 0 ||

        // fishhook (since you use it!)
        strcmp(__symbol, "rebind_symbols") == 0 ||
        strcmp(__symbol, "rebind_symbols_image") == 0 ||
        strcmp(__symbol, "_rebindings_head") == 0 ||
        strcmp(__symbol, "prepend_rebindings") == 0 ||
        strcmp(__symbol, "rebind_symbols_for_image") == 0 ||
        strcmp(__symbol, "_rebind_symbols_for_image") == 0 ||
        strcmp(__symbol, "perform_rebinding_with_section") == 0 ||

        // libhooker
        strcmp(__symbol, "LHHookFunction") == 0 ||
        strcmp(__symbol, "LHHookFunctions") == 0 ||
        strcmp(__symbol, "LHFindSymbol") == 0 ||
        
         // Theos/Logo
        strcmp(__symbol, "_logos_method_orig") == 0 ||
        strcmp(__symbol, "_logos_method_called") == 0 ||
        strcmp(__symbol, "_logos_register_hook") == 0 || 
        strcmp(__symbol, "_logos_method_replaced") == 0 ||

        // Objective-C runtime introspection
        strcmp(__symbol, "method_exchangeImplementations") == 0 ||
        strcmp(__symbol, "class_getInstanceMethod") == 0 ||
        strcmp(__symbol, "class_addMethod") == 0 ||
        strcmp(__symbol, "method_getImplementation") == 0 ||
        strcmp(__symbol, "method_setImplementation") == 0 ||
        strcmp(__symbol, "class_copyMethodList") == 0 ||
        strcmp(__symbol, "class_getMethodImplementation") == 0 ||
        strcmp(__symbol, "method_getName") == 0 ||
        strcmp(__symbol, "method_getTypeEncoding") == 0 ||
        strcmp(__symbol, "object_getClass") == 0 ||
        strcmp(__symbol, "objc_getAssociatedObject") == 0 ||
        strcmp(__symbol, "objc_setAssociatedObject") == 0 ||

        // Litehook-specific symbols
        strcmp(__symbol, "litehook_find_dsc_symbol") == 0 ||
        strcmp(__symbol, "litehook_find_symbol") == 0 ||
        strcmp(__symbol, "litehook_hook_function") == 0 ||
        strcmp(__symbol, "litehook_unhook_function") == 0 ||
        strcmp(__symbol, "_litehook_find_dsc_symbol") == 0 ||
        strcmp(__symbol, "_litehook_find_symbol") == 0 ||

        // NOT USED - DSC iteration functions
        // strcmp(__symbol, "dyld_shared_cache_some_image_only_contains_addr") == 0 ||
        // strcmp(__symbol, "dyld_shared_cache_iterate_text") == 0 ||
        // strcmp(__symbol, "_dyld_shared_cache_contains_path") == 0 ||

        // NOT USED - Mach-O parsing (you use dlsym instead)
        // strcmp(__symbol, "getsectiondata") == 0 ||
        // strcmp(__symbol, "getsegmentdata") == 0 ||
        // strcmp(__symbol, "_dyld_get_image_slide") == 0 ||

        strcmp(__symbol, "ZzBuildHook") == 0 ||
        strcmp(__symbol, "DobbyHook") == 0 ||
        strcmp(__symbol, "pspawn_hook") == 0)) {
        return NULL;  // Hide these symbols
    }

    if(__handle == (void*)RTLD_MAIN_ONLY) {
        if(strcmp(__symbol, MH_EXECUTE_SYM) == 0) {
            if(!appExecutableFileTypeOverwritten) {
                overwriteAppExecutableFileType();
                appExecutableFileTypeOverwritten = true;
            }
            return (void*)orig_dyld_get_image_header(appMainImageIndex);
        }
        __handle = appExecutableHandle;
    } else if (__handle != (void*)RTLD_SELF && __handle != (void*)RTLD_NEXT) {
        void* ans = orig_dlsym(__handle, __symbol);
        if(!ans) {
            return 0;
        }
        for(struct rebindings_entry* cur = _rebindings_head; cur; cur = cur->next) {
            for(int i = 0; i < cur->rebindings_nel; ++i) {
                if(ans == *(cur->rebindings[i].replaced)) {
                    return cur->rebindings[i].replacement;
                }
            }

        }
        return ans;
    }
    
    __attribute__((musttail)) return orig_dlsym(__handle, __symbol);
}

// uint32_t hook_dyld_image_count(void) {
//     return orig_dyld_image_count() - 1 - (uint32_t)tweakLoaderLoaded;
// }
uint32_t hook_dyld_image_count(void) {
    uint32_t count = orig_dyld_image_count();
    
    // Count visible (non-hidden) images INCLUDING LiveContainer (which will be replaced)
    uint32_t visibleCount = 0;
    for(uint32_t i = 0; i < count; i++) {
        const char* imageName = orig_dyld_get_image_name(i);
        if(!shouldHideLibrary(imageName)) {
            visibleCount++;
        }
    }
    
    return visibleCount;
}

// const struct mach_header* hook_dyld_get_image_header(uint32_t image_index) {
//     __attribute__((musttail)) return orig_dyld_get_image_header(translateImageIndex(image_index));
// }
const struct mach_header* hook_dyld_get_image_header(uint32_t image_index) {
    // ALWAYS handle LiveContainer replacement first
    if(image_index == lcImageIndex) {
        ensureAppMainIndexIsSet();
        if(!appExecutableFileTypeOverwritten) {
            overwriteAppExecutableFileType();
            appExecutableFileTypeOverwritten = true;
        }
        return orig_dyld_get_image_header(appMainImageIndex);
    }
    
    // Before we're ready to hide libraries, use simple passthrough
    if(!appExecutableFileTypeOverwritten) {
        return orig_dyld_get_image_header(image_index);
    }
    
    // After we're ready, use the hiding logic
    uint32_t realCount = orig_dyld_image_count();
    uint32_t visibleIndex = 0;
    
    for(uint32_t i = 0; i < realCount; i++) {
        const char* imageName = orig_dyld_get_image_name(i);
        
        if(shouldHideLibrary(imageName)) {
            continue;
        }
        
        if(visibleIndex == image_index) {
            return orig_dyld_get_image_header(i);
        }
        
        visibleIndex++;
    }
    
    return NULL; // ← Don't return fallback, return NULL like stock iOS
}

// intptr_t hook_dyld_get_image_vmaddr_slide(uint32_t image_index) {
//     __attribute__((musttail)) return orig_dyld_get_image_vmaddr_slide(translateImageIndex(image_index));
// }
intptr_t hook_dyld_get_image_vmaddr_slide(uint32_t image_index) {
    // ALWAYS handle LiveContainer replacement first
    if(image_index == lcImageIndex) {
        if(!appExecutableFileTypeOverwritten) {
            overwriteAppExecutableFileType();
            appExecutableFileTypeOverwritten = true;
        }
        return orig_dyld_get_image_vmaddr_slide(appMainImageIndex);
    }
    
    // Before we're ready to hide libraries, use simple passthrough
    if(!appExecutableFileTypeOverwritten) {
        return orig_dyld_get_image_vmaddr_slide(image_index);
    }
    
    // After we're ready, use the hiding logic
    uint32_t realCount = orig_dyld_image_count();
    uint32_t visibleIndex = 0;
    
    for(uint32_t i = 0; i < realCount; i++) {
        const char* imageName = orig_dyld_get_image_name(i);
        
        if(shouldHideLibrary(imageName)) {
            continue;
        }
        
        if(visibleIndex == image_index) {
            return orig_dyld_get_image_vmaddr_slide(i);
        }
        
        visibleIndex++;
    }
    
    return 0;
}

// const char* hook_dyld_get_image_name(uint32_t image_index) {
//     __attribute__((musttail)) return orig_dyld_get_image_name(translateImageIndex(image_index));
// }
const char* hook_dyld_get_image_name(uint32_t image_index) {
<<<<<<< HEAD
    // ALWAYS handle LiveContainer replacement first
    if(image_index == lcImageIndex) {
        ensureAppMainIndexIsSet();
        if(!appExecutableFileTypeOverwritten) {
            overwriteAppExecutableFileType();
            appExecutableFileTypeOverwritten = true;
        }
        return orig_dyld_get_image_name(appMainImageIndex);
    }
    
    // Before we're ready to hide libraries, use simple passthrough
    if(!appExecutableFileTypeOverwritten) {
        return orig_dyld_get_image_name(image_index);
    }
    
    // Use EXACT SAME logic as hook_dyld_image_count
    uint32_t realCount = orig_dyld_image_count();
    uint32_t visibleIndex = 0;
    
    for(uint32_t i = 0; i < realCount; i++) {
        const char* imageName = orig_dyld_get_image_name(i);
        
        if(shouldHideLibrary(imageName)) {
            continue;
        }
        
        if(visibleIndex == image_index) {
            return imageName;  // ← Remove the special LC handling here
        }
        
        visibleIndex++;
    }
    
    // Out of bounds - return NULL
    return NULL;
=======
    __attribute__((musttail)) return orig_dyld_get_image_name(translateImageIndex(image_index));
>>>>>>> 31dddf0 (nudhookv3)
}

bool hook_dyld_program_sdk_at_least(void* dyldApiInstancePtr, dyld_build_version_t version) {
    // we are targeting ios, so we hard code 2
    if(version.platform == 0xffffffff){
        return version.version <= guestAppSdkVersionSet;
    } else if (version.platform == 2){
        return version.version <= guestAppSdkVersion;
    } else {
        return false;
    }
}

uint32_t hook_dyld_get_program_sdk_version(void* dyldApiInstancePtr) {
    return guestAppSdkVersion;
}

// MARK: VPN Detection Bypass implementations
static CFDictionaryRef hook_CFNetworkCopySystemProxySettings(void) {
    NSLog(@"[LC] 🎭 CFNetworkCopySystemProxySettings called");
    
    // Safety check: if original function wasn't found or hooked properly
    if (!orig_CFNetworkCopySystemProxySettings) {
        NSLog(@"[LC] ⚠️ Original CFNetworkCopySystemProxySettings not available - returning clean settings");
        
        // Return minimal clean settings without calling original
        NSDictionary *safeSettings = @{
            @"HTTPEnable": @0,
            @"HTTPSEnable": @0,
            @"SOCKSEnable": @0,
            @"ProxyAutoConfigEnable": @0,
            @"__SCOPED__": @{}
        };
        
        return CFBridgingRetain(safeSettings);
    }
    
    // Original function is available - proceed with normal spoofing
    NSLog(@"[LC] 🎭 Spoofing system proxy settings (hiding proxy/VPN detection)");
    
    NSDictionary *cleanProxySettings = @{
        @"HTTPEnable": @0,
        @"HTTPPort": @0,
        @"HTTPSEnable": @0,
        @"HTTPSPort": @0,
        @"ProxyAutoConfigEnable": @0,
        @"SOCKSEnable": @0,
        @"SOCKSPort": @0,
        @"ExceptionsList": @[],
        @"__SCOPED__": @{}        // ✅ Blocks VPN detection (empty = no VPN interfaces)
    };
    
    return CFBridgingRetain(cleanProxySettings);
}

int hook_sigaction(int sig, const struct sigaction *restrict act, struct sigaction *restrict oact) {
    // Call the original function first
    int result = orig_sigaction(sig, act, oact);
    
    // If this is a query (act is NULL) and oact is not NULL, spoof the result
    if (act == NULL && oact != NULL) {
        // Make it look like no signal handler is installed
        memset(oact, 0, sizeof(struct sigaction));
        oact->sa_handler = SIG_DFL; // Default handler
        
        NSLog(@"[LC] 🎭 Hiding signal handler for signal %d", sig);
    }
    
    return result;
}

// advanced
// int hook_sigaction(int sig, const struct sigaction *restrict act, struct sigaction *restrict oact) {
//     int result = orig_sigaction(sig, act, oact);
    
//     if (act == NULL && oact != NULL) {
//         // List of signals commonly checked by anti-debugging
//         static const int suspiciousSignals[] = {
//             SIGTRAP,  // Debugger breakpoints
//             SIGSTOP,  // Process stopping
//             SIGTSTP,  // Terminal stop
//             SIGCONT,  // Continue after stop
//             SIGSEGV,  // Segmentation fault (crash reporters)
//             SIGBUS,   // Bus error
//             SIGILL,   // Illegal instruction
//             SIGABRT,  // Abort signal
//             SIGFPE,   // Floating point exception
//         };
        
//         // Check if this signal is commonly monitored
//         bool shouldSpoof = false;
//         for (int i = 0; i < sizeof(suspiciousSignals)/sizeof(int); i++) {
//             if (sig == suspiciousSignals[i]) {
//                 shouldSpoof = true;
//                 break;
//             }
//         }
        
//         if (shouldSpoof) {
//             // Clear the signal handler to look clean
//             memset(oact, 0, sizeof(struct sigaction));
//             oact->sa_handler = SIG_DFL;
//             NSLog(@"[LC] 🎭 Spoofed signal handler for signal %d (%s)", sig, strsignal(sig));
//         }
//     }
    
//     return result;
// }

bool performHookDyldApi(const char* functionName, uint32_t adrpOffset, void** origFunction, void* hookFunction) {
    
    uint32_t* baseAddr = dlsym(RTLD_DEFAULT, functionName);
    assert(baseAddr != 0);
    /*
     arm64e
     1ad450b90  e10300aa   mov     x1, x0
     1ad450b94  487b2090   adrp    x8, dyld4::gAPIs
     1ad450b98  000140f9   ldr     x0, [x8]  {dyld4::gAPIs} may contain offset
     1ad450b9c  100040f9   ldr     x16, [x0]
     1ad450ba0  f10300aa   mov     x17, x0
     1ad450ba4  517fecf2   movk    x17, #0x63fa, lsl #0x30
     1ad450ba8  301ac1da   autda   x16, x17
     1ad450bac  114780d2   mov     x17, #0x238
     1ad450bb0  1002118b   add     x16, x16, x17
     1ad450bb4  020240f9   ldr     x2, [x16]
     1ad450bb8  e30310aa   mov     x3, x16
     1ad450bbc  f00303aa   mov     x16, x3
     1ad450bc0  7085f3f2   movk    x16, #0x9c2b, lsl #0x30
     1ad450bc4  50081fd7   braa    x2, x16

     arm64
     00000001ac934c80         mov        x1, x0
     00000001ac934c84         adrp       x8, #0x1f462d000
     00000001ac934c88         ldr        x0, [x8, #0xf88]                            ; __ZN5dyld45gDyldE
     00000001ac934c8c         ldr        x8, [x0]
     00000001ac934c90         ldr        x2, [x8, #0x258]
     00000001ac934c94         br         x2
     */
    uint32_t* adrpInstPtr = baseAddr + adrpOffset;
    assert ((*adrpInstPtr & 0x9f000000) == 0x90000000);
    uint32_t immlo = (*adrpInstPtr & 0x60000000) >> 29;
    uint32_t immhi = (*adrpInstPtr & 0xFFFFE0) >> 5;
    int64_t imm = (((int64_t)((immhi << 2) | immlo)) << 43) >> 31;
    
    void* gdyldPtr = (void*)(((uint64_t)baseAddr & 0xfffffffffffff000) + imm);
    
    uint32_t* ldrInstPtr1 = baseAddr + adrpOffset + 1;
    // check if the instruction is ldr Unsigned offset
    assert((*ldrInstPtr1 & 0xBFC00000) == 0xB9400000);
    uint32_t size = (*ldrInstPtr1 & 0xC0000000) >> 30;
    uint32_t imm12 = (*ldrInstPtr1 & 0x3FFC00) >> 10;
    gdyldPtr += (imm12 << size);
    
    assert(gdyldPtr != 0);
    assert(*(void**)gdyldPtr != 0);
    void* vtablePtr = **(void***)gdyldPtr;
    
    void* vtableFunctionPtr = 0;
    uint32_t* movInstPtr = baseAddr + adrpOffset + 6;

    if((*movInstPtr & 0x7F800000) == 0x52800000) {
        // arm64e, mov imm + add + ldr
        uint32_t imm16 = (*movInstPtr & 0x1FFFE0) >> 5;
        vtableFunctionPtr = vtablePtr + imm16;
    } else if ((*movInstPtr & 0xFFE00C00) == 0xF8400C00) {
        // arm64e, ldr immediate Pre-index 64bit
        uint32_t imm9 = (*movInstPtr & 0x1FF000) >> 12;
        vtableFunctionPtr = vtablePtr + imm9;
    } else {
        // arm64
        uint32_t* ldrInstPtr2 = baseAddr + adrpOffset + 3;
        assert((*ldrInstPtr2 & 0xBFC00000) == 0xB9400000);
        uint32_t size2 = (*ldrInstPtr2 & 0xC0000000) >> 30;
        uint32_t imm12_2 = (*ldrInstPtr2 & 0x3FFC00) >> 10;
        vtableFunctionPtr = vtablePtr + (imm12_2 << size2);
    }

    
    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)vtableFunctionPtr, sizeof(uintptr_t), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    assert(ret == KERN_SUCCESS);
    *origFunction = (void*)*(void**)vtableFunctionPtr;
    *(uint64_t*)vtableFunctionPtr = (uint64_t)hookFunction;
    builtin_vm_protect(mach_task_self(), (mach_vm_address_t)vtableFunctionPtr, sizeof(uintptr_t), false, PROT_READ);
    return true;
}

bool initGuestSDKVersionInfo(void) {
    // it seems Apple is constantly changing findVersionSetEquivalent's signature so we directly search sVersionMap instead
    // however sVersionMap's struct size is also unknown, but we can figure it out
    uint32_t* versionMapPtr = litehook_find_dsc_symbol("/usr/lib/dyld", "__ZN5dyld3L11sVersionMapE");
    assert(versionMapPtr);

    // we assume the size is 10K so we won't need to change this line until maybe iOS 40
    uint32_t* versionMapEnd = versionMapPtr + 2560;
    // ensure the first is versionSet and the third is iOS version (5.0.0)
    assert(versionMapPtr[0] == 0x07db0901 && versionMapPtr[2] == 0x00050000);
    // get struct size. we assume size is smaller then 128. appearently Apple won't have so many platforms
    uint32_t size = 0;
    for(int i = 1; i < 128; ++i) {
        // find the next versionSet (for 6.0.0)
        if(versionMapPtr[i] == 0x07dc0901) {
            size = i;
            break;
        }
    }
    assert(size);
    
    NSOperatingSystemVersion currentVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    uint32_t maxVersion = ((uint32_t)currentVersion.majorVersion << 16) | ((uint32_t)currentVersion.minorVersion << 8);
    
    uint32_t candidateVersion = 0;
    uint32_t candidateVersionEquivalent = 0;
    uint32_t newVersionSetVersion = 0;
    for(uint32_t* nowVersionMapItem = versionMapPtr; nowVersionMapItem < versionMapEnd; nowVersionMapItem += size) {
        newVersionSetVersion = nowVersionMapItem[2];
        if (newVersionSetVersion > guestAppSdkVersion) { break; }
        candidateVersion = newVersionSetVersion;
        candidateVersionEquivalent = nowVersionMapItem[0];
        if(newVersionSetVersion >= maxVersion) { break; }
    }
    
    if (newVersionSetVersion == 0xffffffff && candidateVersion == 0) {
        candidateVersionEquivalent = newVersionSetVersion;
    }

    guestAppSdkVersionSet = candidateVersionEquivalent;
    
    return true;
}

void do_hook_loadableIntoProcess(void) {

    uint32_t *patchAddr = (uint32_t *)litehook_find_dsc_symbol("/usr/lib/dyld", "__ZNK6mach_o6Header19loadableIntoProcessENS_8PlatformE7CStringb");
    size_t patchSize = sizeof(uint32_t[2]);

    kern_return_t kret;
    kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, patchSize, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    assert(kret == KERN_SUCCESS);

    patchAddr[0] = 0xD2800020; // mov x0, #1
    patchAddr[1] = 0xD65F03C0; // ret

    kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, patchSize, false, PROT_READ | PROT_EXEC);
    assert(kret == KERN_SUCCESS);
}


void DyldHooksInit(bool hideLiveContainer, uint32_t spoofSDKVersion) {
    // iterate through loaded images and find LiveContainer it self
    int imageCount = _dyld_image_count();
    for(int i = 0; i < imageCount; ++i) {
        const struct mach_header* currentImageHeader = _dyld_get_image_header(i);
        if(currentImageHeader->filetype == MH_EXECUTE) {
            lcImageIndex = i;
            break;
        }
    }
    
    orig_dyld_get_image_header = _dyld_get_image_header;
    
    // hook dlopen and dlsym to solve RTLD_MAIN_ONLY, hook other functions to hide LiveContainer itself
    rebind_symbols((struct rebinding[7]){
        {"dlsym", (void *)hook_dlsym, (void **)&orig_dlsym},
        {"_dyld_image_count", (void *)hook_dyld_image_count, (void **)&orig_dyld_image_count},
        {"_dyld_get_image_header", (void *)hook_dyld_get_image_header, (void **)&orig_dyld_get_image_header},
        {"_dyld_get_image_vmaddr_slide", (void *)hook_dyld_get_image_vmaddr_slide, (void **)&orig_dyld_get_image_vmaddr_slide},
        {"_dyld_get_image_name", (void *)hook_dyld_get_image_name, (void **)&orig_dyld_get_image_name},
        {"CFNetworkCopySystemProxySettings", (void *)hook_CFNetworkCopySystemProxySettings, (void **)&orig_CFNetworkCopySystemProxySettings},
        {"sigaction", (void *)hook_sigaction, (void **)&orig_sigaction},
    }, hideLiveContainer ? 7: 1);
    
    appExecutableFileTypeOverwritten = !hideLiveContainer;
    
    if(spoofSDKVersion) {
        guestAppSdkVersion = spoofSDKVersion;
        if(!initGuestSDKVersionInfo() ||
           !performHookDyldApi("dyld_program_sdk_at_least", 1, (void**)&orig_dyld_program_sdk_at_least, hook_dyld_program_sdk_at_least) ||
           !performHookDyldApi("dyld_get_program_sdk_version", 0, (void**)&orig_dyld_get_program_sdk_version, hook_dyld_get_program_sdk_version)) {
            return;
        }
    }
    
    if(access("/Users", F_OK) != -1) {
        // not running on macOS, skip this
        do_hook_loadableIntoProcess();
    }
}

void* getGuestAppHeader(void) {
    return (void*)orig_dyld_get_image_header(appMainImageIndex);
}