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
    if ([spoofCameraType isEqualToString:@"video"] && spoofVideoAsset) {
        return getNextVideoFrame();
    }
    
    // For images, create a video-like stream
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

@implementation AVCaptureVideoDataOutput(LiveContainerMinimalHooks)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[LC] Video data output delegate set - spoofing: %d", spoofCameraEnabled);
    
    if (!spoofCameraEnabled || !sampleBufferDelegate) {
        // Normal camera behavior - call original and return
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
        return;
    }
    
    // When spoofing is enabled, DON'T call the original delegate method
    // Instead, we'll deliver ONLY our spoofed frames
    NSLog(@"[LC] Spoofing enabled - intercepting delegate completely");
    
    NSValue *outputKey = [NSValue valueWithNonretainedObject:self];
    
    // Clean up existing
    if (activeVideoOutputDelegates && activeVideoOutputDelegates[outputKey]) {
        NSDictionary *delegateInfo = activeVideoOutputDelegates[outputKey];
        NSTimer *timer = delegateInfo[@"timer"];
        if (timer && [timer isValid]) {
            [timer invalidate];
            if (activeTimers) [activeTimers removeObject:timer];
        }
    }
    
    if (!activeVideoOutputDelegates) {
        activeVideoOutputDelegates = [[NSMutableDictionary alloc] init];
    }
    if (!activeTimers) {
        activeTimers = [[NSMutableSet alloc] init];
    }
    
    // Store delegate info
    activeVideoOutputDelegates[outputKey] = @{
        @"delegate": sampleBufferDelegate,
        @"queue": sampleBufferCallbackQueue ?: dispatch_get_main_queue()
    };
    
    // Start ONLY our spoofed frame delivery - no real camera frames
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!spoofCameraEnabled || isCleaningUp) return;
            
            dispatch_async(spoofDeliveryQueue, ^{
                NSTimer *timer = [NSTimer timerWithTimeInterval:1.0/30.0
                                                         repeats:YES
                                                           block:^(NSTimer *timer) {
                    if (!spoofCameraEnabled || isCleaningUp) {
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
                    
                    CMSampleBufferRef sampleBuffer = createSpoofSampleBuffer();
                    if (sampleBuffer && delegate) {
                        dispatch_async(queue, ^{
                            @try {
                                // Create minimal connection
                                AVCaptureConnection *connection = [[AVCaptureConnection alloc] initWithInputPorts:@[] output:self];
                                
                                // Deliver ONLY spoofed frames - no real camera
                                [delegate captureOutput:self didOutputSampleBuffer:sampleBuffer fromConnection:connection];
                            } @catch (NSException *exception) {
                                NSLog(@"[LC] Frame delivery exception: %@", exception.name);
                            } @finally {
                                CFRelease(sampleBuffer);
                            }
                        });
                    }
                }];
                
                [activeTimers addObject:timer];
                
                NSMutableDictionary *updatedInfo = [activeVideoOutputDelegates[outputKey] mutableCopy];
                if (updatedInfo) {
                    updatedInfo[@"timer"] = timer;
                    activeVideoOutputDelegates[outputKey] = updatedInfo;
                }
                
                [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
                [[NSRunLoop currentRunLoop] run];
            });
        });
    });
}

@end

// Hook still image capture
@interface AVCaptureStillImageOutput(LiveContainerMinimalHooks)
- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler;
@end

@implementation AVCaptureStillImageOutput(LiveContainerMinimalHooks)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    NSLog(@"[LC] Still image capture - spoofing: %d", spoofCameraEnabled);
    
    if (!spoofCameraEnabled) {
        [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
        return;
    }
    
    // Return spoofed image
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CMSampleBufferRef sampleBuffer = createSpoofSampleBuffer();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (handler) {
                handler(sampleBuffer, nil);
            }
            if (sampleBuffer) CFRelease(sampleBuffer);
        });
    });
}

@end

// Hook modern photo capture
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
    
    // For now, just call original but we could spoof this too
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}

@end

// Hook movie file output
@interface AVCaptureMovieFileOutput(LiveContainerMinimalHooks)
- (void)lc_startRecordingToOutputFileURL:(NSURL *)outputFileURL recordingDelegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate;
- (void)lc_stopRecording;
@end

@implementation AVCaptureMovieFileOutput(LiveContainerMinimalHooks)

- (void)lc_startRecordingToOutputFileURL:(NSURL *)outputFileURL recordingDelegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    NSLog(@"[LC] Movie file output start recording to: %@", outputFileURL.lastPathComponent);
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Movie file recording - spoofing enabled, relying on AVAssetWriterInput hook");
    }
    
    [self lc_startRecordingToOutputFileURL:outputFileURL recordingDelegate:delegate];
}

- (void)lc_stopRecording {
    NSLog(@"[LC] Movie file output stop recording");
    [self lc_stopRecording];
}

@end

// Hook capture session output management
@interface AVCaptureSession(LiveContainerOutputHooks)
- (void)lc_addOutput:(AVCaptureOutput *)output;
- (void)lc_removeOutput:(AVCaptureOutput *)output;
@end

@implementation AVCaptureSession(LiveContainerOutputHooks)

- (void)lc_addOutput:(AVCaptureOutput *)output {
    NSLog(@"[LC] Session adding output: %@", NSStringFromClass([output class]));
    
    if (spoofCameraEnabled) {
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            NSLog(@"[LC] Video data output added - will be spoofed");
        } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
            NSLog(@"[LC] Movie file output added");
        } else if ([output isKindOfClass:[AVCapturePhotoOutput class]]) {
            NSLog(@"[LC] Photo output added - will be spoofed");
        } else {
            NSLog(@"[LC] Unknown output type added: %@", NSStringFromClass([output class]));
        }
    }
    
    [self lc_addOutput:output];
}

- (void)lc_removeOutput:(AVCaptureOutput *)output {
    NSLog(@"[LC] Session removing output: %@", NSStringFromClass([output class]));
    
    // Clean up our spoofing for this output
    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
        NSValue *outputKey = [NSValue valueWithNonretainedObject:output];
        if (activeVideoOutputDelegates && activeVideoOutputDelegates[outputKey]) {
            NSDictionary *delegateInfo = activeVideoOutputDelegates[outputKey];
            NSTimer *timer = delegateInfo[@"timer"];
            if (timer && [timer isValid]) {
                [timer invalidate];
                if (activeTimers) [activeTimers removeObject:timer];
            }
            [activeVideoOutputDelegates removeObjectForKey:outputKey];
            NSLog(@"[LC] Cleaned up spoofed video data output");
        }
    }
    
    [self lc_removeOutput:output];
}

@end

// Hook AVAssetWriter
@interface AVAssetWriter(LiveContainerMinimalHooks)
- (BOOL)lc_startWriting;
- (void)lc_finishWritingWithCompletionHandler:(void (^)(void))handler;
@end

@implementation AVAssetWriter(LiveContainerMinimalHooks)

- (BOOL)lc_startWriting {
    NSLog(@"[LC] Asset writer start writing - spoofing: %d", spoofCameraEnabled);
    return [self lc_startWriting];
}

- (void)lc_finishWritingWithCompletionHandler:(void (^)(void))handler {
    NSLog(@"[LC] Asset writer finish writing");
    [self lc_finishWritingWithCompletionHandler:handler];
}

@end

// Hook AVAssetWriterInput - CRITICAL FOR RECORDING
@interface AVAssetWriterInput(LiveContainerMinimalHooks)
- (BOOL)lc_appendSampleBuffer:(CMSampleBufferRef)sampleBuffer;
@end

@implementation AVAssetWriterInput(LiveContainerMinimalHooks)

- (BOOL)lc_appendSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (spoofCameraEnabled && sampleBuffer) {
        // Check if this is video data
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        if (formatDesc) {
            CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDesc);
            
            if (mediaType == kCMMediaType_Video) {
                NSLog(@"[LC] Asset writer input - INTERCEPTING VIDEO FRAME for recording");
                
                // Replace the real sample buffer with our spoofed one
                CMSampleBufferRef spoofedBuffer = createSpoofSampleBuffer();
                if (spoofedBuffer) {
                    BOOL result = [self lc_appendSampleBuffer:spoofedBuffer];
                    CFRelease(spoofedBuffer);
                    return result;
                }
            } else if (mediaType == kCMMediaType_Audio) {
                NSLog(@"[LC] Asset writer input - allowing audio through");
                // Let audio through unchanged
            }
        }
    }
    
    return [self lc_appendSampleBuffer:sampleBuffer];
}

@end

// Hook AVAssetReaderTrackOutput for comprehensive coverage
@interface AVAssetReaderTrackOutput(LiveContainerHooks)
- (CMSampleBufferRef)lc_copyNextSampleBuffer;
@end

@implementation AVAssetReaderTrackOutput(LiveContainerHooks)

- (CMSampleBufferRef)lc_copyNextSampleBuffer {
    CMSampleBufferRef originalBuffer = [self lc_copyNextSampleBuffer];
    
    if (spoofCameraEnabled && originalBuffer) {
        NSLog(@"[LC] Asset reader track output - intercepting video frame read");
        
        // Replace with our spoofed frame
        CMSampleBufferRef spoofedBuffer = createSpoofSampleBuffer();
        if (spoofedBuffer) {
            if (originalBuffer) CFRelease(originalBuffer);
            return spoofedBuffer;
        }
    }
    
    return originalBuffer;
}

@end

// Hook AVCaptureVideoPreviewLayer for logging
@interface AVCaptureVideoPreviewLayer(LiveContainerHooks)
- (void)lc_setSession:(AVCaptureSession *)session;
@end

@implementation AVCaptureVideoPreviewLayer(LiveContainerHooks)

- (void)lc_setSession:(AVCaptureSession *)session {
    NSLog(@"[LC] Video preview layer setSession - session: %p", session);
    [self lc_setSession:session];
}

@end

#pragma mark - Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Comprehensive camera spoofing init");
        
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
        
        // Hook all the necessary classes
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            swizzle(stillImageOutputClass, 
                   @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                   @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        }
        
        Class photoOutputClass = NSClassFromString(@"AVCapturePhotoOutput");
        if (photoOutputClass) {
            swizzle(photoOutputClass, 
                   @selector(capturePhotoWithSettings:delegate:),
                   @selector(lc_capturePhotoWithSettings:delegate:));
        }
        
        Class movieFileOutputClass = NSClassFromString(@"AVCaptureMovieFileOutput");
        if (movieFileOutputClass) {
            swizzle(movieFileOutputClass, 
                   @selector(startRecordingToOutputFileURL:recordingDelegate:),
                   @selector(lc_startRecordingToOutputFileURL:recordingDelegate:));
            swizzle(movieFileOutputClass, 
                   @selector(stopRecording),
                   @selector(lc_stopRecording));
        }
        
        Class assetWriterClass = NSClassFromString(@"AVAssetWriter");
        if (assetWriterClass) {
            swizzle(assetWriterClass, @selector(startWriting), @selector(lc_startWriting));
            swizzle(assetWriterClass, 
                   @selector(finishWritingWithCompletionHandler:),
                   @selector(lc_finishWritingWithCompletionHandler:));
        }
        
        Class assetWriterInputClass = NSClassFromString(@"AVAssetWriterInput");
        if (assetWriterInputClass) {
            swizzle(assetWriterInputClass, 
                   @selector(appendSampleBuffer:),
                   @selector(lc_appendSampleBuffer:));
        }
        
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            swizzle(captureSessionClass, @selector(addOutput:), @selector(lc_addOutput:));
            swizzle(captureSessionClass, @selector(removeOutput:), @selector(lc_removeOutput:));
        }
        
        Class assetReaderTrackOutputClass = NSClassFromString(@"AVAssetReaderTrackOutput");
        if (assetReaderTrackOutputClass) {
            swizzle(assetReaderTrackOutputClass,
                   @selector(copyNextSampleBuffer),
                   @selector(lc_copyNextSampleBuffer));
        }
        
        Class videoPreviewLayerClass = NSClassFromString(@"AVCaptureVideoPreviewLayer");
        if (videoPreviewLayerClass) {
            swizzle(videoPreviewLayerClass,
                   @selector(setSession:),
                   @selector(lc_setSession:));
        }
        
        // Minimal app state monitoring
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
            cleanupSpoofResources();
        }];
        
        NSLog(@"[LC] Comprehensive camera spoofing initialized - all recording paths hooked");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in init: %@", exception);
    }
}