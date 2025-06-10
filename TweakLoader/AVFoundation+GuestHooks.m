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

// Cleanup tracking variables
static NSMutableSet *activeTimers = nil;
static BOOL isCleaningUp = NO;

// Add more tracking for session state
static NSMutableDictionary *sessionStates = nil;
static NSMutableDictionary *outputStates = nil;

// Add session state enum
typedef NS_ENUM(NSInteger, LCSpoofSessionState) {
    LCSpoofSessionStateIdle = 0,
    LCSpoofSessionStateStarting,
    LCSpoofSessionStateRunning,
    LCSpoofSessionStateStopping,
    LCSpoofSessionStateResetting
};

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Forward Declarations

static void cleanupSpoofResources(void);
static void refreshSpoofState(void);
static void setSessionState(AVCaptureSession *session, LCSpoofSessionState state);
static LCSpoofSessionState getSessionState(AVCaptureSession *session);

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

#pragma mark - Cleanup Functions

// Enhanced session state tracking
static void setSessionState(AVCaptureSession *session, LCSpoofSessionState state) {
    if (!sessionStates) {
        sessionStates = [[NSMutableDictionary alloc] init];
    }
    
    NSValue *sessionKey = [NSValue valueWithNonretainedObject:session];
    sessionStates[sessionKey] = @(state);
    
    NSLog(@"[LC] Session %p state changed to: %ld", session, (long)state);
}

static LCSpoofSessionState getSessionState(AVCaptureSession *session) {
    if (!sessionStates) return LCSpoofSessionStateIdle;
    
    NSValue *sessionKey = [NSValue valueWithNonretainedObject:session];
    NSNumber *stateNum = sessionStates[sessionKey];
    return stateNum ? (LCSpoofSessionState)[stateNum integerValue] : LCSpoofSessionStateIdle;
}

static void cleanupSpoofResources(void) {
    NSLog(@"[LC] Simplified cleanup");
    isCleaningUp = YES;
    
    // Stop all timers
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
    NSLog(@"[LC] Simplified cleanup completed");
}

static void refreshSpoofState(void) {
    NSLog(@"[LC] Refreshing spoof state");
    
    NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
    if (!guestAppInfo) {
        // If no guest app info, disable spoofing
        if (spoofCameraEnabled) {
            NSLog(@"[LC] No guest app info, disabling spoofing");
            spoofCameraEnabled = NO;
            cleanupSpoofResources();
        }
        return;
    }
    
    BOOL newSpoofEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
    NSString *newSpoofType = guestAppInfo[@"spoofCameraType"] ?: @"image";
    
    // If spoofing was disabled, clean up
    if (spoofCameraEnabled && !newSpoofEnabled) {
        NSLog(@"[LC] Spoofing disabled, cleaning up");
        spoofCameraEnabled = NO;
        cleanupSpoofResources();
        return;
    }
    
    // If spoofing was re-enabled or type changed, reinitialize
    if (newSpoofEnabled && (!spoofCameraEnabled || ![spoofCameraType isEqualToString:newSpoofType])) {
        NSLog(@"[LC] Spoofing enabled/changed, reinitializing");
        cleanupSpoofResources();
        
        spoofCameraEnabled = newSpoofEnabled;
        spoofCameraType = newSpoofType;
        spoofCameraLoop = guestAppInfo[@"spoofCameraLoop"] ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;
        
        // Reload video if needed
        if ([spoofCameraType isEqualToString:@"video"]) {
            spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
            if (spoofCameraVideoPath.length > 0) {
                NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
                spoofVideoAsset = [AVAsset assetWithURL:videoURL];
                
                if (spoofVideoAsset) {
                    setupVideoReader();
                    NSLog(@"[LC] Reloaded video: %@", spoofCameraVideoPath);
                } else {
                    spoofCameraType = @"image";
                }
            } else {
                spoofCameraType = @"image";
            }
        }
        
        // Reload image
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
        }
        
        prepareImageResources();
    }
    
    spoofCameraEnabled = newSpoofEnabled;
    spoofCameraType = newSpoofType;
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
        NSArray *originalDevices = [self lc_devicesWithMediaType:mediaType];
        
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
        return YES;
    }
    
    return [self lc_lockForConfiguration:error];
}

- (void)lc_unlockForConfiguration {
    NSLog(@"[LC] AVCaptureDevice unlockForConfiguration intercepted");
    
    if (spoofCameraEnabled && [activeCaptureDevices containsObject:self]) {
        NSLog(@"[LC] Configuration unlock for spoofed device");
        return;
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
            
            // Check if this is a reset scenario
            LCSpoofSessionState currentState = getSessionState(self);
            if (currentState == LCSpoofSessionStateRunning || currentState == LCSpoofSessionStateStopping) {
                NSLog(@"[LC] Detected session reset during add input - cleaning up");
                setSessionState(self, LCSpoofSessionStateResetting);
                cleanupSpoofResources();
            }
            
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
            NSLog(@"[LC] Adding spoofed input - tracking session");
            
            if (!activeCaptureSessions) {
                activeCaptureSessions = [[NSMutableSet alloc] init];
            }
            [activeCaptureSessions addObject:self];
            
            // Set session state
            setSessionState(self, LCSpoofSessionStateIdle);
            
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
        
        // Check for reset scenario
        LCSpoofSessionState currentState = getSessionState(self);
        if (currentState == LCSpoofSessionStateRunning) {
            NSLog(@"[LC] Detected session reset during add output - cleaning up");
            setSessionState(self, LCSpoofSessionStateResetting);
            cleanupSpoofResources();
        }
        
        return YES;
    }
    
    return [self lc_canAddOutput:output];
}

- (void)lc_addOutput:(AVCaptureOutput *)output {
    NSLog(@"[LC] AVCaptureSession addOutput intercepted");
    
    if (spoofCameraEnabled && [activeCaptureSessions containsObject:self]) {
        NSLog(@"[LC] Adding spoofed output");
        [self lc_addOutput:output];
        return;
    }
    
    [self lc_addOutput:output];
}

- (void)lc_startRunning {
    NSLog(@"[LC] AVCaptureSession startRunning intercepted");
    
    refreshSpoofState();
    
    if (spoofCameraEnabled && [activeCaptureSessions containsObject:self]) {
        NSLog(@"[LC] Starting spoofed session");
        
        LCSpoofSessionState currentState = getSessionState(self);
        
        // If we're already running, this might be a reset
        if (currentState == LCSpoofSessionStateRunning) {
            NSLog(@"[LC] Session already running - potential reset detected");
            setSessionState(self, LCSpoofSessionStateResetting);
            cleanupSpoofResources();
            
            // Wait a bit before setting to starting
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                setSessionState(self, LCSpoofSessionStateStarting);
            });
        } else {
            setSessionState(self, LCSpoofSessionStateStarting);
        }
        
        // Don't start the real camera
        return;
    }
    
    [self lc_startRunning];
}

- (void)lc_stopRunning {
    NSLog(@"[LC] AVCaptureSession stopRunning intercepted");
    
    if (spoofCameraEnabled && [activeCaptureSessions containsObject:self]) {
        NSLog(@"[LC] Stopping spoofed session");
        
        setSessionState(self, LCSpoofSessionStateStopping);
        
        // Clean up resources for this session
        if (activeVideoOutputDelegates) {
            NSArray *allKeys = [activeVideoOutputDelegates allKeys];
            for (NSValue *key in allKeys) {
                NSDictionary *delegateInfo = activeVideoOutputDelegates[key];
                NSTimer *timer = delegateInfo[@"timer"];
                if (timer && [timer isValid]) {
                    [timer invalidate];
                    if (activeTimers) [activeTimers removeObject:timer];
                }
                [activeVideoOutputDelegates removeObjectForKey:key];
            }
        }
        
        // Remove from active sessions after a delay to allow for potential restart
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LCSpoofSessionState currentState = getSessionState(self);
            if (currentState == LCSpoofSessionStateStopping) {
                [activeCaptureSessions removeObject:self];
                setSessionState(self, LCSpoofSessionStateIdle);
                NSLog(@"[LC] Session fully stopped and removed");
            }
        });
        
        return;
    }
    
    [self lc_stopRunning];
}

@end

// Simplified video output hook - only intercept when actively spoofing
@implementation AVCaptureVideoDataOutput(LiveContainerLowLevelHooks)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[LC] AVCaptureVideoDataOutput setSampleBufferDelegate intercepted");
    
    // Always call the original first to maintain normal behavior
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    
    // Only add our spoofing if enabled and delegate is being set (not nil)
    if (!spoofCameraEnabled || !sampleBufferDelegate) {
        NSLog(@"[LC] Spoofing disabled or delegate nil - using normal camera");
        return;
    }
    
    NSValue *outputKey = [NSValue valueWithNonretainedObject:self];
    
    // Clean up any existing spoof for this output
    if (activeVideoOutputDelegates && activeVideoOutputDelegates[outputKey]) {
        NSDictionary *delegateInfo = activeVideoOutputDelegates[outputKey];
        NSTimer *timer = delegateInfo[@"timer"];
        if (timer && [timer isValid]) {
            [timer invalidate];
            if (activeTimers) [activeTimers removeObject:timer];
        }
        [activeVideoOutputDelegates removeObjectForKey:outputKey];
    }
    
    if (!activeVideoOutputDelegates) {
        activeVideoOutputDelegates = [[NSMutableDictionary alloc] init];
    }
    if (!activeTimers) {
        activeTimers = [[NSMutableSet alloc] init];
    }
    
    // Store the delegate info
    activeVideoOutputDelegates[outputKey] = @{
        @"delegate": sampleBufferDelegate,
        @"queue": sampleBufferCallbackQueue ?: dispatch_get_main_queue(),
        @"originalOutput": self
    };
    
    // Start spoofed frame delivery
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            dispatch_async(spoofDeliveryQueue, ^{
                NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
                
                NSTimer *timer = [NSTimer timerWithTimeInterval:1.0/30.0
                                                         repeats:YES
                                                           block:^(NSTimer *timer) {
                    // Quick check if we should stop
                    if (!spoofCameraEnabled) {
                        [timer invalidate];
                        if (activeTimers) [activeTimers removeObject:timer];
                        return;
                    }
                    
                    NSDictionary *delegateInfo = activeVideoOutputDelegates[outputKey];
                    if (!delegateInfo) {
                        [timer invalidate];
                        if (activeTimers) [activeTimers removeObject:timer];
                        return;
                    }
                    
                    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = delegateInfo[@"delegate"];
                    dispatch_queue_t queue = delegateInfo[@"queue"];
                    AVCaptureVideoDataOutput *output = delegateInfo[@"originalOutput"];
                    
                    CMSampleBufferRef sampleBuffer = createSpoofSampleBuffer();
                    if (sampleBuffer && delegate && output) {
                        dispatch_async(queue, ^{
                            @try {
                                // Create a simple connection
                                AVCaptureConnection *connection = [[AVCaptureConnection alloc] initWithInputPorts:@[] output:output];
                                
                                [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
                            } @catch (NSException *exception) {
                                NSLog(@"[LC] Frame delivery exception: %@", exception.name);
                            } @finally {
                                CFRelease(sampleBuffer);
                            }
                        });
                    }
                }];
                
                [activeTimers addObject:timer];
                
                // Update delegate info with timer
                NSMutableDictionary *updatedInfo = [activeVideoOutputDelegates[outputKey] mutableCopy];
                if (updatedInfo) {
                    updatedInfo[@"timer"] = timer;
                    activeVideoOutputDelegates[outputKey] = updatedInfo;
                }
                
                [runLoop addTimer:timer forMode:NSDefaultRunLoopMode];
                [runLoop run];
            });
        });
    });
}

@end

// Hook still image capture
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

// Hook photo capture
@interface AVCapturePhotoOutput(LiveContainerLowLevelHooks)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@implementation AVCapturePhotoOutput(LiveContainerLowLevelHooks)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    NSLog(@"[LC] Photo capture intercepted");
    
    if (spoofCameraEnabled) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                    NSLog(@"[LC] Would deliver spoofed photo here");
                }
            });
        });
        return;
    }
    
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}

@end

#pragma mark - Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Simplified AVFoundation camera spoofing init");
        
        activeTimers = [[NSMutableSet alloc] init];
        sessionStates = [[NSMutableDictionary alloc] init];
        outputStates = [[NSMutableDictionary alloc] init];
        
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
        
        spoofDeliveryQueue = dispatch_queue_create("com.livecontainer.cameraspoof", DISPATCH_QUEUE_CONCURRENT);
        
        // Load resources
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
        
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            NSLog(@"[LC] Loaded image: %@", spoofImage ? @"SUCCESS" : @"FAILED");
        }
        
        prepareImageResources();
        
        // SIMPLIFIED HOOKS - Only hook what we absolutely need
        
        // Hook video data output for live preview frames
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        // Hook still image capture for photos
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            swizzle(stillImageOutputClass, 
                   @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                   @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        }
        
        // Hook photo output for newer iOS versions
        Class photoOutputClass = NSClassFromString(@"AVCapturePhotoOutput");
        if (photoOutputClass) {
            swizzle(photoOutputClass, 
                   @selector(capturePhotoWithSettings:delegate:),
                   @selector(lc_capturePhotoWithSettings:delegate:));
        }
        
        // Only add essential app state monitoring
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
            NSLog(@"[LC] App background - cleanup");
            cleanupSpoofResources();
        }];
        
        NSLog(@"[LC] Simplified camera spoofing initialized (mode: %@)", spoofCameraType);
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in init: %@", exception);
    }
}