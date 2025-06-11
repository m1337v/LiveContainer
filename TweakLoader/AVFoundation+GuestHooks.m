//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Universal camera spoofing - simplified and stable
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

// Core spoofing resources
static CVPixelBufferRef globalSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef globalFormatDesc = NULL;

// Timers management to prevent memory leaks
static NSMutableSet *activeTimers = nil;

// Forward declarations
static CMSampleBufferRef getCurrentSpoofFrame(void);
static CMSampleBufferRef getNextVideoFrame(void);
static CMSampleBufferRef createImageSampleBuffer(void);
static void setupVideoReader(void);
static void prepareImageResources(void);

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Safe Frame Generation

static CMSampleBufferRef getCurrentSpoofFrame(void) {
    @try {
        if (!spoofCameraEnabled) {
            return NULL;
        }
        
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
                // Restart video for loop
                setupVideoReader();
                return createImageSampleBuffer(); // Return image while restarting
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
        // Clean up existing resources
        if (globalSpoofBuffer) {
            CVPixelBufferRelease(globalSpoofBuffer);
            globalSpoofBuffer = NULL;
        }
        if (globalFormatDesc) {
            CFRelease(globalFormatDesc);
            globalFormatDesc = NULL;
        }
        
        // Use provided image or create default
        UIImage *imageToUse = spoofImage;
        if (!imageToUse) {
            // Create default test image
            CGSize size = CGSizeMake(1920, 1080); // High quality default
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
        
        // Create pixel buffer with proper attributes
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
        
        NSLog(@"[LC] Image resources prepared: %zux%zu", width, height);
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in prepareImageResources: %@", exception);
    }
}

#pragma mark - Safe Camera Hook

@interface AVCaptureVideoDataOutput(LiveContainerSafeHooks)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerSafeHooks)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] Installing safe camera spoofing");
        
        // Call original to maintain normal setup
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
        
        // Add spoofed frame delivery
        dispatch_queue_t spoofQueue = sampleBufferCallbackQueue ?: dispatch_get_main_queue();
        
        NSTimer *spoofTimer = [NSTimer timerWithTimeInterval:1.0/30.0 repeats:YES block:^(NSTimer *timer) {
            @try {
                if (!spoofCameraEnabled) {
                    [timer invalidate];
                    if (activeTimers) {
                        [activeTimers removeObject:timer];
                    }
                    return;
                }
                
                CMSampleBufferRef spoofedFrame = getCurrentSpoofFrame();
                if (spoofedFrame && sampleBufferDelegate) {
                    dispatch_async(spoofQueue, ^{
                        @try {
                            // Create a simple connection - don't use complex initialization
                            AVCaptureConnection *connection = nil;
                            
                            // Try to get existing connection from the output
                            NSArray *connections = self.connections;
                            if (connections.count > 0) {
                                connection = connections.firstObject;
                            }
                            
                            if (!connection) {
                                // Create minimal connection if needed
                                connection = [[AVCaptureConnection alloc] initWithInputPorts:@[] output:self];
                            }
                            
                            // Deliver spoofed frame
                            if ([sampleBufferDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                                [sampleBufferDelegate captureOutput:self didOutputSampleBuffer:spoofedFrame fromConnection:connection];
                            }
                            
                        } @catch (NSException *exception) {
                            NSLog(@"[LC] Exception in frame delivery: %@", exception);
                        } @finally {
                            if (spoofedFrame) {
                                CFRelease(spoofedFrame);
                            }
                        }
                    });
                }
                
            } @catch (NSException *exception) {
                NSLog(@"[LC] Exception in timer block: %@", exception);
                [timer invalidate];
                if (activeTimers) {
                    [activeTimers removeObject:timer];
                }
            }
        }];
        
        // Track timer to prevent leaks
        if (!activeTimers) {
            activeTimers = [[NSMutableSet alloc] init];
        }
        [activeTimers addObject:spoofTimer];
        
        [[NSRunLoop mainRunLoop] addTimer:spoofTimer forMode:NSDefaultRunLoopMode];
        NSLog(@"[LC] Started safe spoofed video stream");
        return;
    }
    
    // Normal operation
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

#pragma mark - Complete Camera Blocking

@interface AVCaptureVideoDataOutput(LiveContainerCompleteBlock)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerCompleteBlock)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] BLOCKING real camera - providing ONLY spoofed frames");
        
        // DO NOT call the original method - this completely blocks real camera input
        // [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue]; // REMOVED
        
        if (!sampleBufferDelegate) {
            return;
        }
        
        dispatch_queue_t spoofQueue = sampleBufferCallbackQueue ?: dispatch_get_main_queue();
        
        // Create timer that provides ONLY spoofed frames - no real camera at all
        NSTimer *spoofTimer = [NSTimer timerWithTimeInterval:1.0/30.0 repeats:YES block:^(NSTimer *timer) {
            @try {
                if (!spoofCameraEnabled) {
                    [timer invalidate];
                    if (activeTimers) {
                        [activeTimers removeObject:timer];
                    }
                    return;
                }
                
                CMSampleBufferRef spoofedFrame = getCurrentSpoofFrame();
                if (spoofedFrame) {
                    dispatch_async(spoofQueue, ^{
                        @try {
                            // Create a basic connection for the spoofed frame
                            AVCaptureConnection *connection = [[AVCaptureConnection alloc] initWithInputPorts:@[] output:self];
                            
                            // Deliver ONLY spoofed frame - Instagram never sees real camera
                            if ([sampleBufferDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                                [sampleBufferDelegate captureOutput:self didOutputSampleBuffer:spoofedFrame fromConnection:connection];
                            }
                            
                        } @catch (NSException *exception) {
                            NSLog(@"[LC] Exception delivering spoofed frame: %@", exception);
                        } @finally {
                            CFRelease(spoofedFrame);
                        }
                    });
                }
                
            } @catch (NSException *exception) {
                NSLog(@"[LC] Exception in spoofed timer: %@", exception);
                [timer invalidate];
                if (activeTimers) {
                    [activeTimers removeObject:timer];
                }
            }
        }];
        
        // Track timer
        if (!activeTimers) {
            activeTimers = [[NSMutableSet alloc] init];
        }
        [activeTimers addObject:spoofTimer];
        
        [[NSRunLoop mainRunLoop] addTimer:spoofTimer forMode:NSDefaultRunLoopMode];
        NSLog(@"[LC] Started PURE spoofed video stream - real camera completely blocked");
        return;
    }
    
    // If spoofing disabled, allow normal camera
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

// Also block at the session level to prevent any real camera initialization
@interface AVCaptureSession(LiveContainerSessionBlock)
- (void)lc_startRunning;
- (void)lc_stopRunning;
@end

@implementation AVCaptureSession(LiveContainerSessionBlock)

- (void)lc_startRunning {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] BLOCKING camera session start - preventing real camera access");
        // Don't call original - completely block real camera session
        return;
    }
    
    // Normal operation
    [self lc_startRunning];
}

- (void)lc_stopRunning {
    NSLog(@"[LC] Camera session stop");
    [self lc_stopRunning];
}

@end

// Block camera input at the source level
@interface AVCaptureDeviceInput(LiveContainerInputBlock)
+ (instancetype)lc_deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError;
@end

@implementation AVCaptureDeviceInput(LiveContainerInputBlock)

+ (instancetype)lc_deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    if (spoofCameraEnabled && [device hasMediaType:AVMediaTypeVideo]) {
        NSLog(@"[LC] BLOCKING camera device input creation - no real camera hardware access");
        
        // Return nil to block camera input creation, but don't set error to avoid crashes
        if (outError) {
            *outError = nil;
        }
        return nil;
    }
    
    // Allow non-camera devices (microphone, etc.)
    return [self lc_deviceInputWithDevice:device error:outError];
}

@end

#pragma mark - Enhanced Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Complete camera blocking initialization");
        
        activeTimers = [[NSMutableSet alloc] init];
        
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
        
        // Load video if specified
        if ([spoofCameraType isEqualToString:@"video"]) {
            spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
            if (spoofCameraVideoPath.length > 0) {
                NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
                spoofVideoAsset = [AVAsset assetWithURL:videoURL];
                
                if (spoofVideoAsset) {
                    setupVideoReader();
                    NSLog(@"[LC] Loaded video: %@", spoofCameraVideoPath);
                } else {
                    NSLog(@"[LC] Failed to load video, using image");
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
            NSLog(@"[LC] Loaded image: %@", spoofImage ? @"SUCCESS" : @"FAILED");
        }
        
        // Prepare resources
        prepareImageResources();
        
        // COMPLETE CAMERA BLOCKING - Hook all camera-related classes
        
        // 1. Block video data output delegate setting
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        // 2. Block camera session starting
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            swizzle(captureSessionClass, 
                   @selector(startRunning), 
                   @selector(lc_startRunning));
            swizzle(captureSessionClass, 
                   @selector(stopRunning), 
                   @selector(lc_stopRunning));
        }
        
        // 3. Block camera device input creation
        Class deviceInputClass = NSClassFromString(@"AVCaptureDeviceInput");
        if (deviceInputClass) {
            swizzle(deviceInputClass, 
                   @selector(deviceInputWithDevice:error:), 
                   @selector(lc_deviceInputWithDevice:error:));
        }
        
        NSLog(@"[LC] Complete camera blocking initialized - NO real camera access allowed");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in init: %@", exception);
    }
}