//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Camera spoofing based on CJ's approach
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraImagePath = @"";
static NSString *spoofCameraVideoPath = @"";
static NSString *spoofCameraType = @"image";
static BOOL spoofCameraLoop = YES;

static UIImage *spoofImage = nil;
static AVAsset *spoofVideoAsset = nil;
static AVAssetReader *currentVideoReader = nil;
static AVAssetReaderTrackOutput *videoTrackOutput = nil;
static dispatch_queue_t videoQueue = nil;

// Core spoofing resources
static CVPixelBufferRef globalSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef globalFormatDesc = NULL;

// Performance tracking
static NSTimeInterval lastFrameTime = 0;
static const NSTimeInterval frameInterval = 1.0/30.0; // 30fps

// Forward declarations
static CMSampleBufferRef getCurrentSpoofFrame(void);
static CMSampleBufferRef getNextVideoFrame(void);
static CMSampleBufferRef createImageSampleBuffer(void);
static void setupVideoReader(void);
static void prepareImageResources(void);

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - CJ-Style GetFrame Class

// Replicate CJ's +[GetFrame getCurrentFrame::] functionality
@interface LiveContainerGetFrame : NSObject
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame shouldSpoof:(BOOL)shouldSpoof;
+ (UIWindow *)getKeyWindow;
@end

@implementation LiveContainerGetFrame

+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame shouldSpoof:(BOOL)shouldSpoof {
    @try {
        if (!shouldSpoof || !spoofCameraEnabled) {
            return originalFrame;
        }
        
        NSLog(@"[LC] GetFrame: Intercepting camera frame - providing spoofed content");
        
        // Release original frame to ensure no real camera data passes through
        if (originalFrame) {
            CFRelease(originalFrame);
        }
        
        // Return spoofed frame instead
        return getCurrentSpoofFrame();
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in GetFrame getCurrentFrame: %@", exception);
        return originalFrame;
    }
}

+ (UIWindow *)getKeyWindow {
    // Updated for iOS 13+ compatibility
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        return window;
                    }
                }
            }
        }
    }
    
    // Fallback for older iOS versions
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray *windows = [[UIApplication sharedApplication] windows];
    for (UIWindow *window in windows) {
        if (window.isKeyWindow) {
            return window;
        }
    }
    return [[UIApplication sharedApplication] keyWindow];
    #pragma clang diagnostic pop
}

@end

#pragma mark - Core Frame Generation Functions

static CMSampleBufferRef getCurrentSpoofFrame(void) {
    @try {
        if (!spoofCameraEnabled) {
            return NULL;
        }
        
        // Performance throttling
        NSTimeInterval currentTime = CACurrentMediaTime();
        if (currentTime - lastFrameTime < frameInterval * 0.8) {
            return NULL;
        }
        lastFrameTime = currentTime;
        
        if ([spoofCameraType isEqualToString:@"video"] && spoofVideoAsset) {
            return getNextVideoFrame();
        } else {
            return createImageSampleBuffer();
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in getCurrentSpoofFrame: %@", exception);
        return NULL;
    }
}

static CMSampleBufferRef getNextVideoFrame(void) {
    @try {
        if (!currentVideoReader || !videoTrackOutput) {
            setupVideoReader();
            if (!currentVideoReader || !videoTrackOutput) {
                return createImageSampleBuffer();
            }
        }
        
        if (currentVideoReader.status == AVAssetReaderStatusReading) {
            CMSampleBufferRef sampleBuffer = [videoTrackOutput copyNextSampleBuffer];
            
            if (sampleBuffer) {
                return sampleBuffer;
            } else if (spoofCameraLoop) {
                setupVideoReader();
                return createImageSampleBuffer();
            }
        }
        
        return createImageSampleBuffer();
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in getNextVideoFrame: %@", exception);
        return createImageSampleBuffer();
    }
}

static CMSampleBufferRef createImageSampleBuffer(void) {
    @try {
        if (!globalSpoofBuffer || !globalFormatDesc) {
            return NULL;
        }
        
        CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000000);
        CMSampleTimingInfo timingInfo = {
            .duration = CMTimeMake(1, 30),
            .presentationTimeStamp = presentationTime,
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
        NSLog(@"[LC] Exception in createImageSampleBuffer: %@", exception);
        return NULL;
    }
}

static void setupVideoReader(void) {
    @try {
        if (!spoofVideoAsset) return;
        
        if (currentVideoReader) {
            [currentVideoReader cancelReading];
            currentVideoReader = nil;
            videoTrackOutput = nil;
        }
        
        NSError *error = nil;
        currentVideoReader = [[AVAssetReader alloc] initWithAsset:spoofVideoAsset error:&error];
        
        if (error || !currentVideoReader) {
            NSLog(@"[LC] Failed to create video reader: %@", error.localizedDescription);
            return;
        }
        
        NSArray *videoTracks = [spoofVideoAsset tracksWithMediaType:AVMediaTypeVideo];
        if (videoTracks.count == 0) {
            NSLog(@"[LC] No video tracks found");
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
        
        if (![currentVideoReader startReading]) {
            NSLog(@"[LC] Failed to start video reader");
            return;
        }
        
        NSLog(@"[LC] Video reader setup completed");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in setupVideoReader: %@", exception);
    }
}

static void prepareImageResources(void) {
    @try {
        if (globalSpoofBuffer) {
            CVPixelBufferRelease(globalSpoofBuffer);
            globalSpoofBuffer = NULL;
        }
        if (globalFormatDesc) {
            CFRelease(globalFormatDesc);
            globalFormatDesc = NULL;
        }
        
        UIImage *imageToUse = spoofImage;
        if (!imageToUse) {
            // Create high-quality default image
            CGSize size = CGSizeMake(1920, 1080);
            UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
            
            [[UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1.0] setFill];
            UIRectFill(CGRectMake(0, 0, size.width, size.height));
            
            NSString *text = @"LiveContainer Camera Spoofing";
            NSDictionary *attrs = @{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:64],
                NSForegroundColorAttributeName: [UIColor whiteColor]
            };
            
            CGSize textSize = [text sizeWithAttributes:attrs];
            CGRect textRect = CGRectMake((size.width - textSize.width) / 2, 
                                       (size.height - textSize.height) / 2, 
                                       textSize.width, textSize.height);
            [text drawInRect:textRect withAttributes:attrs];
            
            imageToUse = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
        
        if (!imageToUse) {
            NSLog(@"[LC] Failed to create spoof image");
            return;
        }
        
        CGImageRef cgImage = imageToUse.CGImage;
        size_t width = CGImageGetWidth(cgImage);
        size_t height = CGImageGetHeight(cgImage);
        
        NSDictionary *attributes = @{
            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };
        
        CVReturn result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            (__bridge CFDictionaryRef)attributes,
            &globalSpoofBuffer
        );
        
        if (result != kCVReturnSuccess) {
            NSLog(@"[LC] Failed to create pixel buffer: %d", result);
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
        
        NSLog(@"[LC] Image resources prepared: %zux%zu", width, height);
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in prepareImageResources: %@", exception);
    }
}

#pragma mark - CJ-Style Camera Hooks

// Block camera device discovery (like CJ's approach)
@interface AVCaptureDevice(LiveContainerCJStyle)
+ (NSArray<AVCaptureDevice *> *)lc_devicesWithMediaType:(AVMediaType)mediaType;
+ (AVCaptureDevice *)lc_defaultDeviceWithMediaType:(AVMediaType)mediaType;
@end

@implementation AVCaptureDevice(LiveContainerCJStyle)

+ (NSArray<AVCaptureDevice *> *)lc_devicesWithMediaType:(AVMediaType)mediaType {
    if (spoofCameraEnabled && [mediaType isEqualToString:AVMediaTypeVideo]) {
        NSLog(@"[LC] CJ-style: BLOCKING camera device discovery");
        return @[]; // No camera devices available
    }
    
    return [self lc_devicesWithMediaType:mediaType];
}

+ (AVCaptureDevice *)lc_defaultDeviceWithMediaType:(AVMediaType)mediaType {
    if (spoofCameraEnabled && [mediaType isEqualToString:AVMediaTypeVideo]) {
        NSLog(@"[LC] CJ-style: BLOCKING default camera device");
        return nil; // No default camera
    }
    
    return [self lc_defaultDeviceWithMediaType:mediaType];
}

@end

// Block camera session (like CJ's session hooks)
@interface AVCaptureSession(LiveContainerCJStyle)
- (void)lc_startRunning;
- (void)lc_addInput:(AVCaptureInput *)input;
@end

@implementation AVCaptureSession(LiveContainerCJStyle)

- (void)lc_startRunning {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] CJ-style: BLOCKING camera session start");
        // Don't call original - completely prevent real camera session
        return;
    }
    
    [self lc_startRunning];
}

- (void)lc_addInput:(AVCaptureInput *)input {
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
            NSLog(@"[LC] CJ-style: BLOCKING camera input addition");
            return; // Don't add camera input
        }
    }
    
    [self lc_addInput:input];
}

@end

// Replace video data output (CJ's main spoofing point)
@interface AVCaptureVideoDataOutput(LiveContainerCJStyle)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerCJStyle)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] CJ-style: Installing spoofed video data output");
        
        // Don't call original - we completely replace camera functionality
        dispatch_queue_t spoofQueue = sampleBufferCallbackQueue ?: dispatch_get_main_queue();
        
        // Use dispatch_source for timer-based delivery
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, spoofQueue);
        
        uint64_t interval = (uint64_t)(frameInterval * NSEC_PER_SEC);
        uint64_t leeway = interval / 10; // 10% leeway
        
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, leeway);
        
        // Store references (avoiding __weak in manual reference counting)
        id<AVCaptureVideoDataOutputSampleBufferDelegate> strongDelegate = sampleBufferDelegate;
        AVCaptureVideoDataOutput *strongOutput = self;
        
        dispatch_source_set_event_handler(timer, ^{
            if (!spoofCameraEnabled) {
                dispatch_source_cancel(timer);
                return;
            }
            
            // Use GetFrame approach like CJ
            CMSampleBufferRef spoofedFrame = [LiveContainerGetFrame getCurrentFrame:NULL shouldSpoof:YES];
            if (spoofedFrame && strongDelegate) {
                @try {
                    // Create basic connection
                    AVCaptureConnection *connection = [[AVCaptureConnection alloc] initWithInputPorts:@[] output:strongOutput];
                    
                    // Deliver ONLY spoofed frames (like CJ)
                    if ([strongDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                        [strongDelegate captureOutput:strongOutput didOutputSampleBuffer:spoofedFrame fromConnection:connection];
                    }
                    
                } @catch (NSException *exception) {
                    NSLog(@"[LC] Exception delivering spoofed frame: %@", exception);
                } @finally {
                    if (spoofedFrame) {
                        CFRelease(spoofedFrame);
                    }
                }
            }
        });
        
        dispatch_resume(timer);
        NSLog(@"[LC] CJ-style spoofed video stream started");
        return;
    }
    
    // Normal operation
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

#pragma mark - CJ-Style Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] CJ-style camera spoofing initialization");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraLoop = guestAppInfo[@"spoofCameraLoop"] ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;
        
        NSLog(@"[LC] Camera spoofing config - enabled: %d, type: %@, loop: %d", 
              spoofCameraEnabled, spoofCameraType, spoofCameraLoop);
        
        if (!spoofCameraEnabled) {
            return;
        }
        
        // Create video processing queue
        videoQueue = dispatch_queue_create("com.livecontainer.video", DISPATCH_QUEUE_SERIAL);
        
        // Load video if specified
        if ([spoofCameraType isEqualToString:@"video"]) {
            spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
            if (spoofCameraVideoPath.length > 0) {
                NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
                
                if ([[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath]) {
                    spoofVideoAsset = [AVAsset assetWithURL:videoURL];
                    
                    if (spoofVideoAsset && spoofVideoAsset.isPlayable) {
                        setupVideoReader();
                        NSLog(@"[LC] Successfully loaded video: %@", spoofCameraVideoPath);
                    } else {
                        NSLog(@"[LC] Video asset not playable, falling back to image");
                        spoofCameraType = @"image";
                    }
                } else {
                    NSLog(@"[LC] Video file not found: %@", spoofCameraVideoPath);
                    spoofCameraType = @"image";
                }
            } else {
                spoofCameraType = @"image";
            }
        }
        
        // Load image
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            NSLog(@"[LC] Custom image loaded: %@", spoofImage ? @"SUCCESS" : @"FAILED");
        }
        
        // Prepare image resources
        prepareImageResources();
        
        // HOOK LIKE CJ - Multiple levels of blocking
        
        // 1. Device discovery level (highest)
        Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
        if (captureDeviceClass) {
            swizzle(captureDeviceClass, 
                   @selector(devicesWithMediaType:), 
                   @selector(lc_devicesWithMediaType:));
            swizzle(captureDeviceClass, 
                   @selector(defaultDeviceWithMediaType:), 
                   @selector(lc_defaultDeviceWithMediaType:));
        }
        
        // 2. Session level
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            swizzle(captureSessionClass, 
                   @selector(startRunning), 
                   @selector(lc_startRunning));
            swizzle(captureSessionClass, 
                   @selector(addInput:), 
                   @selector(lc_addInput:));
        }
        
        // 3. Video data output level (main spoofing point like CJ)
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        NSLog(@"[LC] CJ-style hooks installed successfully");
        NSLog(@"[LC] Camera spoofing mode: %@ (blocking at: Device -> Session -> VideoOutput)", spoofCameraType);
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in CJ-style init: %@", exception);
    }
}