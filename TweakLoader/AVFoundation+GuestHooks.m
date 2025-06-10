//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Low-level camera spoofing with video support
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
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

// Lower level tracking
static NSMutableSet *activeCaptureDevices = nil;
static NSMutableSet *activeCaptureInputs = nil;
static NSMutableSet *activeCaptureSessions = nil;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Video Processing Support

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
    if (!currentVideoReader || !videoTrackOutput) {
        return NULL;
    }
    
    if (currentVideoReader.status == AVAssetReaderStatusReading) {
        CMSampleBufferRef sampleBuffer = [videoTrackOutput copyNextSampleBuffer];
        
        if (sampleBuffer) {
            currentVideoTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            return sampleBuffer;
        } else {
            videoReaderFinished = YES;
            if (spoofCameraLoop) {
                NSLog(@"[LC] Video finished, looping...");
                setupVideoReader();
                return getNextVideoFrame();
            }
        }
    } else if (currentVideoReader.status == AVAssetReaderStatusFailed) {
        NSLog(@"[LC] Video reader failed: %@", currentVideoReader.error.localizedDescription);
    }
    
    return NULL;
}

#pragma mark - Resource Management

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
    if ([spoofCameraType isEqualToString:@"video"] && spoofVideoAsset) {
        // Return video frame directly - no reprocessing
        return getNextVideoFrame();
    }
    
    // Fallback to image
    if (!globalSpoofBuffer || !globalFormatDesc) {
        return NULL;
    }
    
    // FIXED: Add proper timing instead of invalid times
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000000);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30), // 30fps
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
}

#pragma mark - Lower Level Hooks

// Hook AVCaptureDevice at the lowest level
@interface AVCaptureDevice(LiveContainerLowLevelHooks)
+ (NSArray<AVCaptureDevice *> *)lc_devicesWithMediaType:(AVMediaType)mediaType;
+ (AVCaptureDevice *)lc_defaultDeviceWithMediaType:(AVMediaType)mediaType;
- (BOOL)lc_lockForConfiguration:(NSError **)error;
- (void)lc_unlockForConfiguration;
@end

@implementation AVCaptureDevice(LiveContainerLowLevelHooks)

+ (NSArray<AVCaptureDevice *> *)lc_devicesWithMediaType:(AVMediaType)mediaType {
    NSLog(@"[LC] AVCaptureDevice devicesWithMediaType intercepted: %@", mediaType);
    
    if (spoofCameraEnabled && [mediaType isEqualToString:AVMediaTypeVideo]) {
        NSLog(@"[LC] Returning spoofed video devices");
        // Return original devices but we'll intercept their usage
        NSArray *originalDevices = [self lc_devicesWithMediaType:mediaType];
        
        // Track all devices
        if (!activeCaptureDevices) {
            activeCaptureDevices = [[NSMutableSet alloc] init];
        }
        [activeCaptureDevices addObjectsFromArray:originalDevices];
        
        return originalDevices;
    }
    
    return [self lc_devicesWithMediaType:mediaType];
}

+ (AVCaptureDevice *)lc_defaultDeviceWithMediaType:(AVMediaType)mediaType {
    NSLog(@"[LC] AVCaptureDevice defaultDeviceWithMediaType intercepted: %@", mediaType);
    
    if (spoofCameraEnabled && [mediaType isEqualToString:AVMediaTypeVideo]) {
        NSLog(@"[LC] Returning spoofed default video device");
        AVCaptureDevice *originalDevice = [self lc_defaultDeviceWithMediaType:mediaType];
        
        if (!activeCaptureDevices) {
            activeCaptureDevices = [[NSMutableSet alloc] init];
        }
        if (originalDevice) {
            [activeCaptureDevices addObject:originalDevice];
        }
        
        return originalDevice;
    }
    
    return [self lc_defaultDeviceWithMediaType:mediaType];
}

- (BOOL)lc_lockForConfiguration:(NSError **)error {
    NSLog(@"[LC] AVCaptureDevice lockForConfiguration intercepted");
    
    if (spoofCameraEnabled && [activeCaptureDevices containsObject:self]) {
        NSLog(@"[LC] Allowing configuration lock for spoofed device");
        return YES; // Always allow configuration
    }
    
    return [self lc_lockForConfiguration:error];
}

- (void)lc_unlockForConfiguration {
    NSLog(@"[LC] AVCaptureDevice unlockForConfiguration intercepted");
    
    if (spoofCameraEnabled && [activeCaptureDevices containsObject:self]) {
        NSLog(@"[LC] Configuration unlock for spoofed device");
        return; // Do nothing
    }
    
    [self lc_unlockForConfiguration];
}

@end

// Hook AVCaptureDeviceInput
@interface AVCaptureDeviceInput(LiveContainerLowLevelHooks)
+ (instancetype)lc_deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError;
@end

@implementation AVCaptureDeviceInput(LiveContainerLowLevelHooks)

+ (instancetype)lc_deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    NSLog(@"[LC] AVCaptureDeviceInput deviceInputWithDevice intercepted");
    
    if (spoofCameraEnabled && [activeCaptureDevices containsObject:device]) {
        NSLog(@"[LC] Creating spoofed device input");
        
        if (!activeCaptureInputs) {
            activeCaptureInputs = [[NSMutableSet alloc] init];
        }
        
        // Create the input normally but track it
        AVCaptureDeviceInput *input = [self lc_deviceInputWithDevice:device error:outError];
        if (input) {
            [activeCaptureInputs addObject:input];
        }
        return input;
    }
    
    return [self lc_deviceInputWithDevice:device error:outError];
}

@end

// Hook AVCaptureSession at lower level
@interface AVCaptureSession(LiveContainerLowLevelHooks)
- (BOOL)lc_canAddInput:(AVCaptureInput *)input;
- (void)lc_addInput:(AVCaptureInput *)input;
- (BOOL)lc_canAddOutput:(AVCaptureOutput *)output;
- (void)lc_addOutput:(AVCaptureOutput *)output;
- (void)lc_startRunning;
- (void)lc_stopRunning;
@end

@implementation AVCaptureSession(LiveContainerLowLevelHooks)

- (BOOL)lc_canAddInput:(AVCaptureInput *)input {
    NSLog(@"[LC] AVCaptureSession canAddInput intercepted");
    
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        if ([activeCaptureDevices containsObject:deviceInput.device]) {
            NSLog(@"[LC] Allowing spoofed input");
            return YES;
        }
    }
    
    return [self lc_canAddInput:input];
}

- (void)lc_addInput:(AVCaptureInput *)input {
    NSLog(@"[LC] AVCaptureSession addInput intercepted");
    
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        if ([activeCaptureDevices containsObject:deviceInput.device]) {
            NSLog(@"[LC] Adding spoofed input - allowing but tracking session");
            
            if (!activeCaptureSessions) {
                activeCaptureSessions = [[NSMutableSet alloc] init];
            }
            [activeCaptureSessions addObject:self];
            
            // FIXED: Still call the original to set up the session properly
            [self lc_addInput:input];
            return;
        }
    }
    
    [self lc_addInput:input];
}

- (BOOL)lc_canAddOutput:(AVCaptureOutput *)output {
    NSLog(@"[LC] AVCaptureSession canAddOutput intercepted");
    
    if (spoofCameraEnabled && [activeCaptureSessions containsObject:self]) {
        NSLog(@"[LC] Allowing spoofed output");
        return YES;
    }
    
    return [self lc_canAddOutput:output];
}

- (void)lc_addOutput:(AVCaptureOutput *)output {
    NSLog(@"[LC] AVCaptureSession addOutput intercepted");
    
    if (spoofCameraEnabled && [activeCaptureSessions containsObject:self]) {
        NSLog(@"[LC] Adding spoofed output - allowing but will intercept frames");
        // FIXED: Allow the output to be added so the session is set up properly
        [self lc_addOutput:output];
        return;
    }
    
    [self lc_addOutput:output];
}

- (void)lc_startRunning {
    NSLog(@"[LC] AVCaptureSession startRunning intercepted");
    
    if (spoofCameraEnabled && [activeCaptureSessions containsObject:self]) {
        NSLog(@"[LC] Starting spoofed session - blocking real camera");
        // FIXED: Don't start the real camera, but simulate running state
        // We need to set the running state without actually starting
        return;
    }
    
    [self lc_startRunning];
}

- (void)lc_stopRunning {
    NSLog(@"[LC] AVCaptureSession stopRunning intercepted");
    
    if (spoofCameraEnabled && [activeCaptureSessions containsObject:self]) {
        NSLog(@"[LC] Stopping spoofed session");
        return;
    }
    
    [self lc_stopRunning];
}

@end

// Hook AVCaptureVideoDataOutput (existing but simplified)
@interface AVCaptureVideoDataOutput(LiveContainerLowLevelHooks)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerLowLevelHooks)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[LC] AVCaptureVideoDataOutput setSampleBufferDelegate intercepted");
    
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] Registering spoofed delegate");
        
        if (!activeVideoOutputDelegates) {
            activeVideoOutputDelegates = [[NSMutableDictionary alloc] init];
        }
        
        NSValue *outputKey = [NSValue valueWithNonretainedObject:self];
        activeVideoOutputDelegates[outputKey] = @{
            @"delegate": sampleBufferDelegate,
            @"queue": sampleBufferCallbackQueue ?: dispatch_get_main_queue()
        };
        
        // FIXED: Create a proper connection for this output
        dispatch_async(dispatch_get_main_queue(), ^{
            // Give the session time to set up
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Start frame delivery
                dispatch_async(spoofDeliveryQueue, ^{
                    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
                    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0/30.0
                                                             repeats:YES
                                                               block:^(NSTimer *timer) {
                        NSDictionary *delegateInfo = activeVideoOutputDelegates[outputKey];
                        if (delegateInfo) {
                            id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = delegateInfo[@"delegate"];
                            dispatch_queue_t queue = delegateInfo[@"queue"];
                            
                            CMSampleBufferRef sampleBuffer = createSpoofSampleBuffer();
                            if (sampleBuffer) {
                                dispatch_async(queue, ^{
                                    @try {
                                        // FIXED: Create a proper connection or use existing one
                                        AVCaptureConnection *connection = self.connections.firstObject;
                                        if (!connection) {
                                            // Create a mock connection if needed
                                            connection = [[AVCaptureConnection alloc] initWithInputPorts:@[] output:self];
                                        }
                                        
                                        [delegate captureOutput:self didOutputSampleBuffer:sampleBuffer fromConnection:connection];
                                    } @catch (NSException *exception) {
                                        NSLog(@"[LC] Frame delivery exception: %@", exception.name);
                                    } @finally {
                                        CFRelease(sampleBuffer);
                                    }
                                });
                            }
                        } else {
                            NSLog(@"[LC] Delegate removed, invalidating timer");
                            [timer invalidate];
                        }
                    }];
                    
                    [runLoop addTimer:timer forMode:NSDefaultRunLoopMode];
                    [runLoop run];
                });
            });
        });
        
        return;
    }
    
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

// Add hooks for still image capture to fix recording
@interface AVCaptureStillImageOutput(LiveContainerLowLevelHooks)
- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler;
@end

@implementation AVCaptureStillImageOutput(LiveContainerLowLevelHooks)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    NSLog(@"[LC] Still image capture intercepted");
    
    if (spoofCameraEnabled) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            CMSampleBufferRef sampleBuffer = createSpoofSampleBuffer();
            dispatch_async(dispatch_get_main_queue(), ^{
                if (handler) {
                    handler(sampleBuffer, nil);
                }
                if (sampleBuffer) CFRelease(sampleBuffer);
            });
        });
        return;
    }
    
    [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
}

@end

// Add newer capture photo output support
@interface AVCapturePhotoOutput(LiveContainerLowLevelHooks)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@implementation AVCapturePhotoOutput(LiveContainerLowLevelHooks)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    NSLog(@"[LC] Photo capture intercepted");
    
    if (spoofCameraEnabled) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // Create a mock photo object
            // This is more complex and would need proper AVCapturePhoto creation
            // For now, just call the delegate with basic completion
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                    // This would need proper photo object creation
                    NSLog(@"[LC] Would deliver spoofed photo here");
                }
            });
        });
        return;
    }
    
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}

@end

// Add the missing hooks in initialization
void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Low-level AVFoundation camera spoofing init");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraLoop = guestAppInfo[@"spoofCameraLoop"] ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;
        
        NSLog(@"[LC] Camera spoofing - enabled: %d, type: %@, loop: %d", 
              spoofCameraEnabled, spoofCameraType, spoofCameraLoop);
        
        if (!spoofCameraEnabled) {
            return;
        }
        
        // Initialize resources
        spoofDeliveryQueue = dispatch_queue_create("com.livecontainer.cameraspoof", DISPATCH_QUEUE_CONCURRENT);
        
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
                    NSLog(@"[LC] Failed to load video: %@", spoofCameraVideoPath);
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
        
        // Always prepare image resources (fallback)
        prepareImageResources();
        
        // Setup low-level hooks
        
        // AVCaptureDevice hooks
        Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
        if (captureDeviceClass) {
            swizzle(captureDeviceClass, @selector(devicesWithMediaType:), @selector(lc_devicesWithMediaType:));
            swizzle(captureDeviceClass, @selector(defaultDeviceWithMediaType:), @selector(lc_defaultDeviceWithMediaType:));
            swizzle(captureDeviceClass, @selector(lockForConfiguration:), @selector(lc_lockForConfiguration:));
            swizzle(captureDeviceClass, @selector(unlockForConfiguration), @selector(lc_unlockForConfiguration));
        }
        
        // AVCaptureDeviceInput hooks
        Class captureDeviceInputClass = NSClassFromString(@"AVCaptureDeviceInput");
        if (captureDeviceInputClass) {
            swizzle(captureDeviceInputClass, @selector(deviceInputWithDevice:error:), @selector(lc_deviceInputWithDevice:error:));
        }
        
        // AVCaptureSession hooks
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            swizzle(captureSessionClass, @selector(canAddInput:), @selector(lc_canAddInput:));
            swizzle(captureSessionClass, @selector(addInput:), @selector(lc_addInput:));
            swizzle(captureSessionClass, @selector(canAddOutput:), @selector(lc_canAddOutput:));
            swizzle(captureSessionClass, @selector(addOutput:), @selector(lc_addOutput:));
            swizzle(captureSessionClass, @selector(startRunning), @selector(lc_startRunning));
            swizzle(captureSessionClass, @selector(stopRunning), @selector(lc_stopRunning));
        }
        
        // AVCaptureVideoDataOutput hooks
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        // Add still image output hooks
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            swizzle(stillImageOutputClass, 
                   @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                   @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        }
        
        // Add photo output hooks for newer iOS versions
        Class photoOutputClass = NSClassFromString(@"AVCapturePhotoOutput");
        if (photoOutputClass) {
            swizzle(photoOutputClass, 
                   @selector(capturePhotoWithSettings:delegate:),
                   @selector(lc_capturePhotoWithSettings:delegate:));
        }
        
        NSLog(@"[LC] Low-level camera spoofing initialized (mode: %@)", spoofCameraType);
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in init: %@", exception);
    }
}