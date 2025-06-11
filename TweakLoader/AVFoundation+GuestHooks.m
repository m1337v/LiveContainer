//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  EXACT CJ replication with enhanced video support
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

// CJ-style frame state
static int frameCounter = 0;
static NSTimeInterval lastFrameTime = 0;
static const NSTimeInterval frameInterval = 1.0/30.0; // 30fps

// Image animation state 
static NSInteger imageAnimationFrame = 0;
static const NSInteger maxImageAnimationFrames = 300; // 10 seconds at 30fps

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - EXACT CJ GetFrame Implementation

// Forward declaration for helper function
static AVCapturePhoto* createMockCapturePhoto(CMSampleBufferRef sampleBuffer, AVCaptureResolvedPhotoSettings *resolvedSettings);

// This EXACTLY replicates CJ's GetFrame class
@interface GetFrame : NSObject
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame :(BOOL)shouldSpoof;
+ (UIWindow *)getKeyWindow;
@end

@implementation GetFrame

// EXACT replica of CJ's +[GetFrame getCurrentFrame::] at 0x2AB78
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame :(BOOL)shouldSpoof {
    @try {
        if (!shouldSpoof || !spoofCameraEnabled) {
            return originalFrame;
        }
        
        NSLog(@"[LC] GetFrame: Intercepting camera frame - providing spoofed content");
        
        // CJ ALWAYS releases the original frame first to block real camera
        if (originalFrame) {
            CFRelease(originalFrame);
        }
        
        // Return our spoofed frame instead
        return [self createSpoofedFrame];
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] GetFrame exception: %@", exception);
        return originalFrame;
    }
}

// EXACT replica of CJ's +[GetFrame getKeyWindow] at 0x2B354
+ (UIWindow *)getKeyWindow {
    @try {
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
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] getKeyWindow exception: %@", exception);
        return nil;
    }
}

// Enhanced frame creation that supports both image and video
+ (CMSampleBufferRef)createSpoofedFrame {
    @try {
        if (!spoofCameraEnabled) {
            return NULL;
        }
        
        frameCounter++;
        
        // Video mode with proper looping
        if ([spoofCameraType isEqualToString:@"video"] && spoofVideoAsset) {
            CMSampleBufferRef videoFrame = [self getNextVideoFrame];
            if (videoFrame) {
                NSLog(@"[LC] Returning video frame %d", frameCounter);
                return videoFrame;
            }
            // Fall back to image if video fails
            NSLog(@"[LC] Video frame failed, falling back to image");
        }
        
        // Image mode with animation
        return [self createAnimatedImageFrame];
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in createSpoofedFrame: %@", exception);
        return NULL;
    }
}

+ (CMSampleBufferRef)getNextVideoFrame {
    @try {
        if (!currentVideoReader || !videoTrackOutput) {
            [self setupVideoReader];
            if (!currentVideoReader || !videoTrackOutput) {
                return NULL;
            }
        }
        
        if (currentVideoReader.status == AVAssetReaderStatusReading) {
            CMSampleBufferRef sampleBuffer = [videoTrackOutput copyNextSampleBuffer];
            
            if (sampleBuffer) {
                return sampleBuffer;
            } else if (spoofCameraLoop) {
                // Video ended, restart if looping enabled
                NSLog(@"[LC] Video ended, restarting loop");
                [self setupVideoReader];
                // Try to get first frame of restarted video
                if (currentVideoReader && videoTrackOutput && currentVideoReader.status == AVAssetReaderStatusReading) {
                    return [videoTrackOutput copyNextSampleBuffer];
                }
            }
        }
        
        return NULL;
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in getNextVideoFrame: %@", exception);
        return NULL;
    }
}

+ (CMSampleBufferRef)createAnimatedImageFrame {
    @try {
        if (!globalSpoofBuffer || !globalFormatDesc) {
            return NULL;
        }
        
        // Create animated effect by cycling through different variations
        imageAnimationFrame++;
        if (imageAnimationFrame >= maxImageAnimationFrames) {
            imageAnimationFrame = 0;
            NSLog(@"[LC] Image animation loop completed, restarting");
        }
        
        // CJ-style frame timing
        CMTime presentationTime = CMTimeMake(frameCounter, 30);
        
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
            NSLog(@"[LC] Failed to create animated image buffer: %d", result);
            return NULL;
        }
        
        NSLog(@"[LC] Created animated image frame %d (anim: %ld)", frameCounter, (long)imageAnimationFrame);
        return sampleBuffer;
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in createAnimatedImageFrame: %@", exception);
        return NULL;
    }
}

+ (void)setupVideoReader {
    @try {
        if (!spoofVideoAsset) return;
        
        // Clean up existing reader
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
            NSLog(@"[LC] Cannot add video track output to reader");
            currentVideoReader = nil;
            videoTrackOutput = nil;
            return;
        }
        
        if (![currentVideoReader startReading]) {
            NSLog(@"[LC] Failed to start video reader: %@", currentVideoReader.error);
            currentVideoReader = nil;
            videoTrackOutput = nil;
            return;
        }
        
        NSLog(@"[LC] Video reader setup completed successfully");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in setupVideoReader: %@", exception);
        currentVideoReader = nil;
        videoTrackOutput = nil;
    }
}

@end

#pragma mark - Core Resource Preparation

static void prepareImageResources(void) {
    @try {
        // Clean up existing resources
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
            // Create high-quality animated default image that updates each frame
            CGSize size = CGSizeMake(1920, 1080);
            UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
            
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            
            // Dynamic gradient that changes with frame counter for animation effect
            CGFloat hue = fmod((double)frameCounter / 300.0, 1.0); // Full color cycle every 10 seconds
            UIColor *color1 = [UIColor colorWithHue:hue saturation:0.8 brightness:0.9 alpha:1.0];
            UIColor *color2 = [UIColor colorWithHue:fmod(hue + 0.3, 1.0) saturation:0.8 brightness:0.6 alpha:1.0];
            
            CGFloat colors[8];
            [color1 getRed:&colors[0] green:&colors[1] blue:&colors[2] alpha:&colors[3]];
            [color2 getRed:&colors[4] green:&colors[5] blue:&colors[6] alpha:&colors[7]];
            
            CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
            CGContextDrawLinearGradient(context, gradient, CGPointZero, 
                                       CGPointMake(size.width, size.height), 0);
            
            // Dynamic text that shows current app and frame info
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"Unknown";
            NSString *appName = [bundleID componentsSeparatedByString:@"."].lastObject ?: @"App";
            
            NSString *text = [NSString stringWithFormat:@"LiveContainer Camera Spoofing\n🔴 LIVE STREAM 🔴\n\nApp: %@\nFrame: %d\nMode: %@\nAnimation: %ld/%ld", 
                             appName, frameCounter, spoofCameraType, (long)imageAnimationFrame, (long)maxImageAnimationFrames];
            
            NSShadow *shadow = [[NSShadow alloc] init];
            shadow.shadowOffset = CGSizeMake(3, 3);
            shadow.shadowBlurRadius = 6;
            shadow.shadowColor = [UIColor blackColor];
            
            NSDictionary *attrs = @{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:44],
                NSForegroundColorAttributeName: [UIColor whiteColor],
                NSShadowAttributeName: shadow,
                NSStrokeColorAttributeName: [UIColor blackColor],
                NSStrokeWidthAttributeName: @(-2.0)
            };
            
            CGSize textSize = [text sizeWithAttributes:attrs];
            CGRect textRect = CGRectMake((size.width - textSize.width) / 2, 
                                       (size.height - textSize.height) / 2, 
                                       textSize.width, textSize.height);
            [text drawInRect:textRect withAttributes:attrs];
            
            // Animated pulsing recording indicator
            CGFloat pulseAlpha = 0.3 + 0.7 * sin((double)frameCounter * 0.3);
            CGFloat pulseSize = 40 + 20 * sin((double)frameCounter * 0.5);
            
            [[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:pulseAlpha] setFill];
            CGRect dotRect = CGRectMake(size.width - 150, 80, pulseSize, pulseSize);
            CGContextFillEllipseInRect(context, dotRect);
            
            // Add frame indicator bars
            [[UIColor colorWithWhite:1.0 alpha:0.8] setFill];
            for (int i = 0; i < 10; i++) {
                CGFloat barHeight = 10 + 40 * sin((double)(frameCounter + i * 30) * 0.2);
                CGRect barRect = CGRectMake(100 + i * 15, size.height - 100, 10, barHeight);
                CGContextFillRect(context, barRect);
            }
            
            imageToUse = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            CGGradientRelease(gradient);
            CGColorSpaceRelease(colorSpace);
        }
        
        if (!imageToUse) {
            NSLog(@"[LC] ❌ Failed to create spoof image");
            return;
        }
        
        CGImageRef cgImage = imageToUse.CGImage;
        size_t width = CGImageGetWidth(cgImage);
        size_t height = CGImageGetHeight(cgImage);
        
        // Create pixel buffer with optimal settings
        NSDictionary *attributes = @{
            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
            (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES
        };
        
        CVReturn result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            (__bridge CFDictionaryRef)attributes,
            &globalSpoofBuffer
        );
        
        if (result != kCVReturnSuccess) {
            NSLog(@"[LC] ❌ Failed to create pixel buffer: %d", result);
            return;
        }
        
        // Draw image into pixel buffer
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
        
        // Create format description
        CMVideoFormatDescriptionCreateForImageBuffer(
            kCFAllocatorDefault,
            globalSpoofBuffer,
            &globalFormatDesc
        );
        
        NSLog(@"[LC] ✅ Enhanced animated image resources prepared: %zux%zu", width, height);
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception in prepareImageResources: %@", exception);
    }
}

#pragma mark - CJ-Style Low-Level Hooks

// Block ALL camera access at device level (like CJ's sub_ functions)
@interface AVCaptureDevice(LiveContainerCJStyle)
+ (NSArray<AVCaptureDevice *> *)lc_devicesWithMediaType:(AVMediaType)mediaType;
+ (AVCaptureDevice *)lc_defaultDeviceWithMediaType:(AVMediaType)mediaType;
+ (AVCaptureDevice *)lc_deviceWithUniqueID:(NSString *)deviceUniqueID;
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

+ (AVCaptureDevice *)lc_deviceWithUniqueID:(NSString *)deviceUniqueID {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] CJ-style: BLOCKING device by unique ID: %@", deviceUniqueID);
        return nil; // No device found
    }
    
    return [self lc_deviceWithUniqueID:deviceUniqueID];
}

@end

// Block session-level camera access (like CJ's session hooks)
@interface AVCaptureSession(LiveContainerCJStyle)
- (void)lc_startRunning;
- (void)lc_stopRunning;
- (void)lc_addInput:(AVCaptureInput *)input;
- (void)lc_removeInput:(AVCaptureInput *)input;
@end

@implementation AVCaptureSession(LiveContainerCJStyle)

- (void)lc_startRunning {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] CJ-style: BLOCKING camera session startRunning");
        return; // Don't start real camera session
    }
    
    [self lc_startRunning];
}

- (void)lc_stopRunning {
    // Always allow stopping
    [self lc_stopRunning];
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

- (void)lc_removeInput:(AVCaptureInput *)input {
    // Always allow removing inputs
    [self lc_removeInput:input];
}

@end

// Main video data output hook (CJ's primary interception point)
@interface AVCaptureVideoDataOutput(LiveContainerCJStyle)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerCJStyle)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] CJ-style: Installing spoofed video data output");
        
        dispatch_queue_t spoofQueue = sampleBufferCallbackQueue ?: dispatch_get_main_queue();
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, spoofQueue);
        
        uint64_t interval = (uint64_t)(frameInterval * NSEC_PER_SEC);
        uint64_t leeway = interval / 10; // 10% leeway for performance
        
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, leeway);
        
        // Store references (avoiding retain cycles)
        id<AVCaptureVideoDataOutputSampleBufferDelegate> strongDelegate = sampleBufferDelegate;
        AVCaptureVideoDataOutput *strongOutput = self;
        
        dispatch_source_set_event_handler(timer, ^{
            if (!spoofCameraEnabled) {
                dispatch_source_cancel(timer);
                return;
            }
            
            // Use GetFrame exactly like CJ does
            CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL :YES];
            if (spoofedFrame && strongDelegate) {
                @try {
                    // Create minimal connection for delegate call
                    AVCaptureConnection *connection = [[AVCaptureConnection alloc] initWithInputPorts:@[] output:strongOutput];
                    
                    // Deliver ONLY spoofed frames (no real camera data ever passes through)
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
        NSLog(@"[LC] CJ-style spoofed video stream started (30fps)");
        return;
    }
    
    // Normal operation when spoofing disabled
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

// Photo capture hooks (like CJ's photo interception)
@interface AVCaptureStillImageOutput(LiveContainerCJStyle)
- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler;
@end

@implementation AVCaptureStillImageOutput(LiveContainerCJStyle)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] CJ-style: Intercepting still image capture");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL :YES];
            if (spoofedFrame) {
                handler(spoofedFrame, nil);
                CFRelease(spoofedFrame);
            } else {
                NSError *error = [NSError errorWithDomain:@"LiveContainer" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create spoofed photo"}];
                handler(NULL, error);
            }
        });
        return;
    }
    
    [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
}

@end

// Photo output hooks (iOS 10+)
@interface AVCapturePhotoOutput(LiveContainerCJStyle)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@implementation AVCapturePhotoOutput(LiveContainerCJStyle)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] CJ-style: Intercepting photo output capture");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL :YES];
                
                if (spoofedFrame && delegate) {
                    // Create mock resolved settings using runtime manipulation
                    AVCaptureResolvedPhotoSettings *mockResolvedSettings = nil;
                    
                    // Try to create resolved settings via private methods
                    @try {
                        // Method 1: Try using runtime allocation
                        mockResolvedSettings = (AVCaptureResolvedPhotoSettings *)class_createInstance([AVCaptureResolvedPhotoSettings class], 0);
                        if (mockResolvedSettings) {
                            // Set basic properties via KVC if possible
                            @try {
                                [mockResolvedSettings setValue:@(123456) forKey:@"uniqueID"];
                                if (settings) {
                                    [mockResolvedSettings setValue:@(settings.flashMode) forKey:@"flashEnabled"];
                                }
                            } @catch (NSException *kvcException) {
                                NSLog(@"[LC] KVC property setting failed: %@", kvcException);
                            }
                        }
                    } @catch (NSException *e) {
                        NSLog(@"[LC] Resolved settings creation failed: %@", e);
                    }
                    
                    // Call delegate methods with proper error handling
                    @try {
                        if ([delegate respondsToSelector:@selector(captureOutput:willBeginCaptureForResolvedSettings:)]) {
                            [delegate captureOutput:self willBeginCaptureForResolvedSettings:mockResolvedSettings];
                        }
                    } @catch (NSException *e) {
                        NSLog(@"[LC] willBeginCapture failed: %@", e);
                    }
                    
                    @try {
                        if ([delegate respondsToSelector:@selector(captureOutput:willCapturePhotoForResolvedSettings:)]) {
                            [delegate captureOutput:self willCapturePhotoForResolvedSettings:mockResolvedSettings];
                        }
                    } @catch (NSException *e) {
                        NSLog(@"[LC] willCapturePhoto failed: %@", e);
                    }
                    
                    @try {
                        if ([delegate respondsToSelector:@selector(captureOutput:didCapturePhotoForResolvedSettings:)]) {
                            [delegate captureOutput:self didCapturePhotoForResolvedSettings:mockResolvedSettings];
                        }
                    } @catch (NSException *e) {
                        NSLog(@"[LC] didCapturePhoto failed: %@", e);
                    }
                    
                    // Try different photo delivery methods
                    BOOL photoDelivered = NO;
                    
                    // Method 1: Modern AVCapturePhoto method (iOS 11+) - PREFERRED
                    if (!photoDelivered && [delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                        @try {
                            // Create mock AVCapturePhoto
                            AVCapturePhoto *mockPhoto = createMockCapturePhoto(spoofedFrame, mockResolvedSettings);
                            
                            // Call with mock photo (or nil if creation failed)
                            [delegate captureOutput:self didFinishProcessingPhoto:mockPhoto error:nil];
                            photoDelivered = YES;
                            NSLog(@"[LC] ✅ Photo delivered via AVCapturePhoto method");
                            
                        } @catch (NSException *e) {
                            NSLog(@"[LC] AVCapturePhoto method failed: %@", e);
                        }
                    }
                    
                    // Method 2: Legacy sample buffer method (iOS 10-11) - FALLBACK
                    if (!photoDelivered) {
                        SEL legacySel = @selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:);
                        if ([delegate respondsToSelector:legacySel]) {
                            @try {
                                // Cast delegate to NSObject to access methodSignatureForSelector
                                NSObject *delegateObject = (NSObject *)delegate;
                                NSMethodSignature *legacySignature = [delegateObject methodSignatureForSelector:legacySel];
                                
                                if (legacySignature) {
                                    NSInvocation *legacyInvocation = [NSInvocation invocationWithMethodSignature:legacySignature];
                                    [legacyInvocation setTarget:delegate];
                                    [legacyInvocation setSelector:legacySel];
                                    
                                    // Fix: Use proper pointer types for setArgument
                                    AVCapturePhotoOutput *selfPtr = self;
                                    [legacyInvocation setArgument:&selfPtr atIndex:2];                  // output
                                    [legacyInvocation setArgument:&spoofedFrame atIndex:3];             // photoSampleBuffer
                                    [legacyInvocation setArgument:&spoofedFrame atIndex:4];             // previewPhotoSampleBuffer
                                    [legacyInvocation setArgument:&mockResolvedSettings atIndex:5];     // resolvedSettings
                                    
                                    id nilBracketSettings = nil;
                                    [legacyInvocation setArgument:&nilBracketSettings atIndex:6];       // bracketSettings
                                    NSError *nilError = nil;
                                    [legacyInvocation setArgument:&nilError atIndex:7];                 // error
                                    
                                    [legacyInvocation invoke];
                                    
                                    photoDelivered = YES;
                                    NSLog(@"[LC] ✅ Photo delivered via legacy sample buffer method");
                                }
                                
                            } @catch (NSException *e) {
                                NSLog(@"[LC] Legacy sample buffer method failed: %@", e);
                            }
                        }
                    }
                    
                    // Method 3: Live photo fallback
                    if (!photoDelivered && [delegate respondsToSelector:@selector(captureOutput:didFinishProcessingLivePhotoToMovieFileAtURL:duration:photoDisplayTime:resolvedSettings:error:)]) {
                        @try {
                            NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"spoofed_live_%d.mov", frameCounter]];
                            NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
                            
                            // Create minimal movie file
                            [@"FAKE_LIVE_PHOTO_DATA" writeToURL:tempURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
                            
                            [delegate captureOutput:self 
                             didFinishProcessingLivePhotoToMovieFileAtURL:tempURL 
                             duration:CMTimeMake(1, 30) 
                             photoDisplayTime:CMTimeMake(0, 30) 
                             resolvedSettings:mockResolvedSettings 
                             error:nil];
                            photoDelivered = YES;
                            NSLog(@"[LC] ✅ Photo delivered via live photo method");
                        } @catch (NSException *e) {
                            NSLog(@"[LC] Live photo method failed: %@", e);
                        }
                    }
                    
                    // Final completion callback
                    @try {
                        if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                            NSError *completionError = photoDelivered ? nil : [NSError errorWithDomain:@"LiveContainer" code:1002 userInfo:@{NSLocalizedDescriptionKey: @"Could not deliver spoofed photo"}];
                            
                            // Use mockResolvedSettings if available, otherwise create a basic one for completion
                            AVCaptureResolvedPhotoSettings *completionSettings = mockResolvedSettings;
                            if (!completionSettings) {
                                @try {
                                    completionSettings = (AVCaptureResolvedPhotoSettings *)class_createInstance([AVCaptureResolvedPhotoSettings class], 0);
                                } @catch (NSException *settingsException) {
                                    // If we can't create settings, we have to pass nil and accept the warning
                                    NSLog(@"[LC] Could not create completion settings: %@", settingsException);
                                }
                            }
                            
                            [delegate captureOutput:self didFinishCaptureForResolvedSettings:completionSettings error:completionError];
                        }
                    } @catch (NSException *e) {
                        NSLog(@"[LC] didFinishCapture failed: %@", e);
                    }
                    
                    if (!photoDelivered) {
                        NSLog(@"[LC] ⚠️ Could not deliver photo via any method");
                    }
                    
                    CFRelease(spoofedFrame);
                } else {
                    // Error case - no spoofed frame or delegate
                    NSError *error = [NSError errorWithDomain:@"LiveContainer" code:1002 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create spoofed photo"}];
                    
                    @try {
                        if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                            // Create basic resolved settings for error case
                            AVCaptureResolvedPhotoSettings *errorSettings = nil;
                            @try {
                                errorSettings = (AVCaptureResolvedPhotoSettings *)class_createInstance([AVCaptureResolvedPhotoSettings class], 0);
                            } @catch (NSException *settingsException) {
                                NSLog(@"[LC] Could not create error settings: %@", settingsException);
                            }
                            
                            [delegate captureOutput:self didFinishCaptureForResolvedSettings:errorSettings error:error];
                        }
                    } @catch (NSException *e) {
                        NSLog(@"[LC] Error completion callback failed: %@", e);
                    }
                }
                
            } @catch (NSException *exception) {
                NSLog(@"[LC] ❌ Critical exception in photo capture: %@", exception);
                
                // Final error fallback
                @try {
                    if (delegate && [delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                        NSError *criticalError = [NSError errorWithDomain:@"LiveContainer" code:1003 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Critical photo capture error"}];
                        
                        // Try to create basic settings for final error case
                        AVCaptureResolvedPhotoSettings *finalErrorSettings = nil;
                        @try {
                            finalErrorSettings = (AVCaptureResolvedPhotoSettings *)class_createInstance([AVCaptureResolvedPhotoSettings class], 0);
                        } @catch (NSException *finalSettingsException) {
                            NSLog(@"[LC] Could not create final error settings: %@", finalSettingsException);
                        }
                        
                        [delegate captureOutput:self didFinishCaptureForResolvedSettings:finalErrorSettings error:criticalError];
                    }
                } @catch (NSException *finalException) {
                    NSLog(@"[LC] ❌ Final error callback failed: %@", finalException);
                }
            }
        });
        return;
    }
    
    // Normal operation when spoofing disabled
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}

@end

#pragma mark - Helper Functions

// Helper function to create mock capture photo
static AVCapturePhoto* createMockCapturePhoto(CMSampleBufferRef sampleBuffer, AVCaptureResolvedPhotoSettings *resolvedSettings) {
    @try {
        // Create basic AVCapturePhoto mock using runtime allocation
        AVCapturePhoto *mockPhoto = (AVCapturePhoto *)class_createInstance([AVCapturePhoto class], 0);
        
        if (mockPhoto && sampleBuffer) {
            @try {
                // Set basic properties via KVC
                if (resolvedSettings) {
                    [mockPhoto setValue:resolvedSettings forKey:@"resolvedSettings"];
                }
                [mockPhoto setValue:[NSDate date] forKey:@"timestamp"];
                
                // Try to extract and set image data from sample buffer
                CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                if (imageBuffer) {
                    // Convert to NSData for photo representation
                    CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
                    CIContext *context = [CIContext context];
                    NSData *imageData = [context JPEGRepresentationOfImage:ciImage colorSpace:ciImage.colorSpace options:@{}];
                    if (imageData) {
                        [mockPhoto setValue:imageData forKey:@"fileDataRepresentation"];
                        NSLog(@"[LC] Mock photo created with %lu bytes of image data", (unsigned long)imageData.length);
                    }
                }
                
            } @catch (NSException *kvcException) {
                NSLog(@"[LC] Mock photo KVC failed: %@", kvcException);
                // Object is still valid even if property setting failed
            }
        }
        
        return mockPhoto;
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Mock photo creation failed: %@", exception);
        return nil;
    }
}

#pragma mark - CJ-Style Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] 🎯 EXACT CJ implementation initialization");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info available");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraLoop = guestAppInfo[@"spoofCameraLoop"] ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;
        
        NSLog(@"[LC] 📷 Camera spoofing config - enabled: %d, type: %@, loop: %d", 
              spoofCameraEnabled, spoofCameraType, spoofCameraLoop);
        
        if (!spoofCameraEnabled) {
            NSLog(@"[LC] Camera spoofing disabled, skipping hooks");
            return;
        }
        
        // Create video processing queue
        videoQueue = dispatch_queue_create("com.livecontainer.video.processing", DISPATCH_QUEUE_SERIAL);
        
        // Load video content if specified
        if ([spoofCameraType isEqualToString:@"video"]) {
            spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
            if (spoofCameraVideoPath.length > 0) {
                NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
                
                if ([[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath]) {
                    spoofVideoAsset = [AVAsset assetWithURL:videoURL];
                    
                    if (spoofVideoAsset && spoofVideoAsset.isPlayable) {
                        [GetFrame setupVideoReader];
                        NSLog(@"[LC] ✅ Successfully loaded video: %@", spoofCameraVideoPath);
                    } else {
                        NSLog(@"[LC] ⚠️ Video asset not playable, falling back to image mode");
                        spoofCameraType = @"image";
                    }
                } else {
                    NSLog(@"[LC] ⚠️ Video file not found: %@, falling back to image mode", spoofCameraVideoPath);
                    spoofCameraType = @"image";
                }
            } else {
                NSLog(@"[LC] ⚠️ No video path specified, using image mode");
                spoofCameraType = @"image";
            }
        }
        
        // Load custom image
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            NSLog(@"[LC] 🖼️ Custom image loaded: %@", spoofImage ? @"SUCCESS" : @"FAILED");
        }
        
        // Prepare image resources (always needed as fallback)
        prepareImageResources();
        
        // 🎯 APPLY CJ-STYLE HOOKS AT MULTIPLE LEVELS
        
        // Level 1: Device Discovery (Highest Level)
        Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
        if (captureDeviceClass) {
            swizzle(captureDeviceClass, @selector(devicesWithMediaType:), @selector(lc_devicesWithMediaType:));
            swizzle(captureDeviceClass, @selector(defaultDeviceWithMediaType:), @selector(lc_defaultDeviceWithMediaType:));
            swizzle(captureDeviceClass, @selector(deviceWithUniqueID:), @selector(lc_deviceWithUniqueID:));
            NSLog(@"[LC] ✅ Device-level hooks installed");
        }
        
        // Level 2: Session Management
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            swizzle(captureSessionClass, @selector(startRunning), @selector(lc_startRunning));
            swizzle(captureSessionClass, @selector(stopRunning), @selector(lc_stopRunning));
            swizzle(captureSessionClass, @selector(addInput:), @selector(lc_addInput:));
            swizzle(captureSessionClass, @selector(removeInput:), @selector(lc_removeInput:));
            NSLog(@"[LC] ✅ Session-level hooks installed");
        }
        
        // Level 3: Video Data Output (Main Spoofing Point)
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            swizzle(videoDataOutputClass, @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
            NSLog(@"[LC] ✅ Video data output hooks installed");
        }
        
        // Level 4: Photo Capture
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            swizzle(stillImageOutputClass, @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:), @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
            NSLog(@"[LC] ✅ Still image output hooks installed");
        }
        
        Class photoOutputClass = NSClassFromString(@"AVCapturePhotoOutput");
        if (photoOutputClass) {
            swizzle(photoOutputClass, @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
            NSLog(@"[LC] ✅ Photo output hooks installed");
        }
        
        NSLog(@"[LC] 🎯 ===== CJ-Style Camera Spoofing Ready =====");
        NSLog(@"[LC] 🔥 GetFrame class available: %@", NSStringFromClass([GetFrame class]));
        NSLog(@"[LC] 📊 Hooks installed at: Device -> Session -> VideoOutput -> PhotoOutput");
        NSLog(@"[LC] 🎬 Mode: %@ | Loop: %@ | Instagram should now be fully spoofed", 
              spoofCameraType, spoofCameraLoop ? @"YES" : @"NO");
        NSLog(@"[LC] ===================================================");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ CRITICAL: CJ init exception: %@", exception);
    }
}