//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Minimal camera output spoofing
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>  // ADD THIS - for objc_getClassList, Method, etc.
#import "../LiveContainer/Tweaks/Tweaks.h"

static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraImagePath = @"";
static NSString *spoofCameraVideoPath = @"";
static NSString *spoofCameraType = @"image";
static BOOL spoofCameraLoop = YES;

static UIImage *spoofImage = nil;

// Video support
static AVAsset *spoofVideoAsset = nil;
static AVAssetReader *currentVideoReader = nil;
static AVAssetReaderTrackOutput *videoTrackOutput = nil;
static CMTime currentVideoTime;
static BOOL videoReaderFinished = NO;

// Resources
static CVPixelBufferRef globalSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef globalFormatDesc = NULL;
static dispatch_queue_t spoofDeliveryQueue = NULL;
static NSMutableDictionary *activeVideoOutputDelegates = nil;
static NSMutableSet *activeTimers = nil;
static BOOL isCleaningUp = NO;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

static void hookVideoFrameDelegateMethod(void);

#pragma mark - Video Processing

static void setupVideoReader(void) {
    if (!spoofVideoAsset) return;
    
    if (currentVideoReader) {
        [currentVideoReader cancelReading];
        currentVideoReader = nil;
        videoTrackOutput = nil;
    }
    
    NSError *error = nil;
    currentVideoReader = [[AVAssetReader alloc] initWithAsset:spoofVideoAsset error:&error];
    
    if (error) {
        NSLog(@"[LC] Failed to create video reader: %@", error.localizedDescription);
        return;
    }
    
    NSArray *videoTracks = [spoofVideoAsset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        NSLog(@"[LC] No video tracks found in asset");
        return;
    }
    
    AVAssetTrack *videoTrack = videoTracks.firstObject;
    
    NSDictionary *outputSettings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    
    videoTrackOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:outputSettings];
    
    if ([currentVideoReader canAddOutput:videoTrackOutput]) {
        [currentVideoReader addOutput:videoTrackOutput];
    } else {
        NSLog(@"[LC] Cannot add video track output");
        return;
    }
    
    currentVideoTime = kCMTimeZero;
    videoReaderFinished = NO;
    
    if (![currentVideoReader startReading]) {
        NSLog(@"[LC] Failed to start video reader");
        return;
    }
    
    NSLog(@"[LC] Video reader setup completed");
}

static CMSampleBufferRef getNextVideoFrame(void) {
    @try {
        if (!currentVideoReader || !videoTrackOutput) {
            NSLog(@"[LC] Video reader not ready");
            return NULL;
        }
        
        if (currentVideoReader.status == AVAssetReaderStatusReading) {
            CMSampleBufferRef sampleBuffer = [videoTrackOutput copyNextSampleBuffer];
            
            if (sampleBuffer) {
                return sampleBuffer;
            } else {
                // Video finished, restart if looping
                if (spoofCameraLoop) {
                    NSLog(@"[LC] Restarting video for loop");
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        setupVideoReader();
                    });
                }
                return NULL;
            }
        } else {
            NSLog(@"[LC] Video reader status: %ld", (long)currentVideoReader.status);
            return NULL;
        }
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in getNextVideoFrame: %@", exception);
        return NULL;
    }
}

#pragma mark - Image Processing

static UIImage *createTestImage(void) {
    CGSize size = CGSizeMake(1280, 720);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {
        0.0, 0.3, 0.8, 1.0,
        0.8, 0.2, 0.6, 1.0
    };
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointZero, 
                               CGPointMake(size.width, size.height), 0);
    
    UIFont *titleFont = [UIFont boldSystemFontOfSize:48];
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    
    NSString *title = @"LiveContainer\nCamera Spoofing";
    CGRect titleRect = CGRectMake(50, size.height/2 - 50, size.width - 100, 100);
    [title drawInRect:titleRect withAttributes:titleAttrs];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    
    return image;
}

static void prepareImageResources(void) {
    if (globalSpoofBuffer) {
        CVPixelBufferRelease(globalSpoofBuffer);
        globalSpoofBuffer = NULL;
    }
    if (globalFormatDesc) {
        CFRelease(globalFormatDesc);
        globalFormatDesc = NULL;
    }
    
    UIImage *imageToUse = spoofImage ?: createTestImage();
    if (!imageToUse) return;
    
    CGImageRef cgImage = imageToUse.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    NSLog(@"[LC] Creating spoof buffer: %zux%zu", width, height);
    
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    
    CVReturn result = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width, height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attributes,
        &globalSpoofBuffer
    );
    
    if (result != kCVReturnSuccess) {
        NSLog(@"[LC] Failed to create spoof buffer: %d", result);
        return;
    }
    
    CVPixelBufferLockBaseAddress(globalSpoofBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(globalSpoofBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(globalSpoofBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        baseAddress, width, height, 8, bytesPerRow, colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    );
    
    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
        CGContextRelease(context);
    }
    
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(globalSpoofBuffer, 0);
    
    CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault,
        globalSpoofBuffer,
        &globalFormatDesc
    );
    
    NSLog(@"[LC] Image resources prepared successfully");
}

static CMSampleBufferRef createSpoofSampleBuffer(void) {
    @try {
        if ([spoofCameraType isEqualToString:@"video"] && spoofVideoAsset) {
            return getNextVideoFrame();
        }
        
        // For images, create a simple sample buffer
        if (!globalSpoofBuffer || !globalFormatDesc) {
            NSLog(@"[LC] Spoof resources not ready");
            return NULL;
        }
        
        // Create timing info with current time
        CMTime now = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000000);
        CMSampleTimingInfo timingInfo = {
            .duration = CMTimeMake(1, 30),
            .presentationTimeStamp = now,
            .decodeTimeStamp = kCMTimeInvalid
        };
        
        CMSampleBufferRef sampleBuffer = NULL;
        OSStatus result = CMSampleBufferCreateReadyWithImageBuffer(
            kCFAllocatorDefault,
            globalSpoofBuffer,
            globalFormatDesc,
            &timingInfo,
            &sampleBuffer
        );
        
        if (result != noErr) {
            NSLog(@"[LC] Failed to create sample buffer: %d", result);
            return NULL;
        }
        
        return sampleBuffer;
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in createSpoofSampleBuffer: %@", exception);
        return NULL;
    }
}

#pragma mark - Cleanup

static void cleanupSpoofResources(void) {
    NSLog(@"[LC] Cleaning up spoof resources");
    isCleaningUp = YES;
    
    // Clean up timers
    if (activeTimers) {
        for (NSTimer *timer in [activeTimers allObjects]) {
            if ([timer isValid]) {
                [timer invalidate];
            }
        }
        [activeTimers removeAllObjects];
    }
    
    // Clear delegates
    if (activeVideoOutputDelegates) {
        [activeVideoOutputDelegates removeAllObjects];
    }
    
    // Reset video reader
    if (currentVideoReader) {
        [currentVideoReader cancelReading];
        currentVideoReader = nil;
        videoTrackOutput = nil;
        videoReaderFinished = NO;
        currentVideoTime = kCMTimeZero;
    }
    
    // Re-setup video if needed
    if ([spoofCameraType isEqualToString:@"video"] && spoofVideoAsset) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            setupVideoReader();
        });
    }
    
    isCleaningUp = NO;
    NSLog(@"[LC] Cleanup completed");
}

#pragma mark - HOOKS - Only hook data outputs

// Hook video data output - this provides the live preview frames
@interface AVCaptureVideoDataOutput(LiveContainerMinimalHooks)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

#pragma mark - SIMPLIFIED Video Data Output Hook

@implementation AVCaptureVideoDataOutput(LiveContainerMinimalHooks)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[LC] Video data output delegate set - spoofing: %d", spoofCameraEnabled);
    
    if (!spoofCameraEnabled || !sampleBufferDelegate) {
        // Normal behavior - call original
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
        return;
    }
    
    // Call original to maintain Instagram's normal camera setup
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    
    NSLog(@"[LC] Camera spoofing enabled - will hook delegate methods at runtime");
}

@end

// MUCH SIMPLER APPROACH - Hook the actual sample buffer output delegate method
// Use method swizzling on the delegate protocol method itself

static IMP original_captureOutput_didOutputSampleBuffer_fromConnection = NULL;

static void hooked_captureOutput_didOutputSampleBuffer_fromConnection(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) {
    
    if (spoofCameraEnabled && [output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
        NSLog(@"[LC] Intercepting video frame output - replacing with spoofed content");
        
        // Replace with spoofed frame
        CMSampleBufferRef spoofedBuffer = createSpoofSampleBuffer();
        if (spoofedBuffer) {
            // Call original method with spoofed buffer
            ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))original_captureOutput_didOutputSampleBuffer_fromConnection)(self, _cmd, output, spoofedBuffer, connection);
            CFRelease(spoofedBuffer);
            return;
        }
    }
    
    // Call original method with original buffer
    ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))original_captureOutput_didOutputSampleBuffer_fromConnection)(self, _cmd, output, sampleBuffer, connection);
}

#pragma mark - Still Image Hook (Fixed)

@interface AVCaptureStillImageOutput(LiveContainerMinimalHooks)
- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler;
@end

@implementation AVCaptureStillImageOutput(LiveContainerMinimalHooks)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    NSLog(@"[LC] Still image capture - spoofing: %d", spoofCameraEnabled);
    
    if (!spoofCameraEnabled || !handler) {
        [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
        return;
    }
    
    // Create spoofed image sample buffer
    CMSampleBufferRef spoofedBuffer = createSpoofSampleBuffer();
    if (spoofedBuffer) {
        handler(spoofedBuffer, nil);
        CFRelease(spoofedBuffer);
    } else {
        // Fallback to real capture
        [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
    }
}

@end

#pragma mark - Photo Output Hook (Fixed)

@interface AVCapturePhotoOutput(LiveContainerMinimalHooks)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@implementation AVCapturePhotoOutput(LiveContainerMinimalHooks)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    NSLog(@"[LC] Photo capture - spoofing: %d", spoofCameraEnabled);
    
    if (!spoofCameraEnabled) {
        [self lc_capturePhotoWithSettings:settings delegate:delegate];
        return;
    }
    
    // For now, just call original - photo spoofing is more complex
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}

@end

#pragma mark - Simplified Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] ULTRA-SIMPLIFIED camera spoofing init");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraLoop = guestAppInfo[@"spoofCameraLoop"] ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;
        
        NSLog(@"[LC] Camera spoofing - enabled: %d, type: %@", spoofCameraEnabled, spoofCameraType);
        
        if (!spoofCameraEnabled) {
            return;
        }
        
        // Load resources (keep existing code)
        if ([spoofCameraType isEqualToString:@"video"]) {
            spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
            if (spoofCameraVideoPath.length > 0) {
                NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
                spoofVideoAsset = [AVAsset assetWithURL:videoURL];
                
                if (spoofVideoAsset) {
                    setupVideoReader();
                    NSLog(@"[LC] Loaded video: %@", spoofCameraVideoPath);
                } else {
                    spoofCameraType = @"image";
                }
            } else {
                spoofCameraType = @"image";
            }
        }
        
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            NSLog(@"[LC] Loaded image: %@", spoofImage ? @"SUCCESS" : @"FAILED");
        }
        
        prepareImageResources();
        
        // SIMPLIFIED HOOKS - Only the essential ones that work
        
        // Hook video data output delegate setter
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        // Hook still image capture
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            swizzle(stillImageOutputClass, 
                   @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                   @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        }
        
        // Hook modern photo capture
        Class photoOutputClass = NSClassFromString(@"AVCapturePhotoOutput");
        if (photoOutputClass) {
            swizzle(photoOutputClass, 
                   @selector(capturePhotoWithSettings:delegate:),
                   @selector(lc_capturePhotoWithSettings:delegate:));
        }
        
        // Hook the actual delegate method that gets called with video frames
        // This is a runtime hook - we find Instagram's delegate and hook its method
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (spoofCameraEnabled) {
                // Hook the captureOutput:didOutputSampleBuffer:fromConnection: method on all objects
                // This catches Instagram's actual video frame processing
                hookVideoFrameDelegateMethod();  // FIXED: removed [self ...]
            }
        });
        
        NSLog(@"[LC] ULTRA-SIMPLIFIED camera spoofing initialized");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in init: %@", exception);
    }
}

// Runtime method to hook Instagram's actual video frame delegate
static void hookVideoFrameDelegateMethod(void) {
    @try {
        // Get all loaded classes
        int numClasses = objc_getClassList(NULL, 0);
        Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
        numClasses = objc_getClassList(classes, numClasses);
        
        for (int i = 0; i < numClasses; i++) {
            Class cls = classes[i];
            
            // Check if this class implements the video data output delegate method
            Method method = class_getInstanceMethod(cls, @selector(captureOutput:didOutputSampleBuffer:fromConnection:));
            if (method) {
                NSString *className = NSStringFromClass(cls);
                NSLog(@"[LC] Found video delegate method on class: %@", className);
                
                // Hook this method if it's not already hooked
                if (!original_captureOutput_didOutputSampleBuffer_fromConnection) {
                    original_captureOutput_didOutputSampleBuffer_fromConnection = method_setImplementation(method, (IMP)hooked_captureOutput_didOutputSampleBuffer_fromConnection);
                    NSLog(@"[LC] Hooked video frame delegate method on %@", className);
                }
            }
        }
        
        free(classes);
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in hookVideoFrameDelegateMethod: %@", exception);
    }
}