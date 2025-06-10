//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Enhanced camera spoofing with video support
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
static NSString *spoofCameraType = @"image"; // "image" or "video"
static BOOL spoofCameraLoop = YES;

static UIImage *spoofImage = nil;

// Video support
static AVAsset *spoofVideoAsset = nil;
static AVAssetReader *currentVideoReader = nil;
static AVAssetReaderTrackOutput *videoTrackOutput = nil;
static CMTime currentVideoTime;
static CMTime videoDuration;
static BOOL videoReaderFinished = NO;

// Enhanced resources
static CVPixelBufferRef globalSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef globalFormatDesc = NULL;
static dispatch_queue_t spoofDeliveryQueue = NULL;
static NSMutableDictionary *activeVideoOutputDelegates = nil;
static dispatch_semaphore_t frameDeliverySemaphore = NULL;
static NSTimeInterval lastFrameTime = 0;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Video Processing Support

static void setupVideoReader(void) {
    if (!spoofVideoAsset) return;
    
    // Clean up existing reader
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
    
    // Configure output settings for better performance
    NSDictionary *outputSettings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    
    videoTrackOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:outputSettings];
    videoTrackOutput.alwaysCopiesSampleData = NO; // Performance optimization
    
    if ([currentVideoReader canAddOutput:videoTrackOutput]) {
        [currentVideoReader addOutput:videoTrackOutput];
    } else {
        NSLog(@"[LC] Cannot add video track output");
        return;
    }
    
    // Reset playback state
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
            // Update current time
            currentVideoTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            return sampleBuffer;
        } else {
            // End of video
            videoReaderFinished = YES;
            
            // Loop if enabled
            if (spoofCameraLoop) {
                NSLog(@"[LC] Video finished, looping...");
                setupVideoReader(); // Restart from beginning
                return getNextVideoFrame(); // Try again
            }
        }
    } else if (currentVideoReader.status == AVAssetReaderStatusFailed) {
        NSLog(@"[LC] Video reader failed: %@", currentVideoReader.error.localizedDescription);
    }
    
    return NULL;
}

static CVPixelBufferRef extractPixelBufferFromVideoFrame(CMSampleBufferRef sampleBuffer) {
    if (!sampleBuffer) return NULL;
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return NULL;
    
    // Use CVPixelBufferCreateWithBytes instead of CVPixelBufferCreateCopyWithAlignment
    CVPixelBufferRef pixelBufferCopy = NULL;
    
    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
    
    CVReturn result = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width, height,
        pixelFormat,
        NULL,
        &pixelBufferCopy
    );
    
    if (result == kCVReturnSuccess && pixelBufferCopy) {
        CVPixelBufferLockBaseAddress(pixelBufferCopy, 0);
        void *copyBaseAddress = CVPixelBufferGetBaseAddress(pixelBufferCopy);
        size_t copyBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBufferCopy);
        
        for (size_t row = 0; row < height; row++) {
            memcpy((char*)copyBaseAddress + row * copyBytesPerRow,
                   (char*)baseAddress + row * bytesPerRow,
                   MIN(bytesPerRow, copyBytesPerRow));
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBufferCopy, 0);
    }
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    
    return pixelBufferCopy;
}

#pragma mark - Enhanced Resource Management

static UIImage *createEnhancedTestImage(void) {
    CGSize size = CGSizeMake(1920, 1080);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Simple gradient background
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {
        0.0, 0.3, 0.8, 1.0,  // Blue
        0.8, 0.2, 0.6, 1.0   // Magenta
    };
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointZero, 
                               CGPointMake(size.width, size.height), 0);
    
    // Add text
    UIFont *titleFont = [UIFont boldSystemFontOfSize:48];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowOffset = CGSizeMake(2, 2);
    shadow.shadowBlurRadius = 4;
    shadow.shadowColor = [UIColor blackColor];
    
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSShadowAttributeName: shadow
    };
    
    NSString *title = @"LiveContainer Pro\nCamera Spoofing";
    CGRect titleRect = CGRectMake(50, size.height/2 - 50, size.width - 100, 100);
    [title drawInRect:titleRect withAttributes:titleAttrs];
    
    // Add timestamp
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    UIFont *infoFont = [UIFont systemFontOfSize:24];
    NSDictionary *infoAttrs = @{
        NSFontAttributeName: infoFont,
        NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.8]
    };
    
    CGRect timestampRect = CGRectMake(50, size.height - 80, size.width - 100, 30);
    [timestamp drawInRect:timestampRect withAttributes:infoAttrs];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    
    return image;
}

static void prepareImageSpoofResources(void) {
    // Clean up existing resources
    if (globalSpoofBuffer) {
        CVPixelBufferRelease(globalSpoofBuffer);
        globalSpoofBuffer = NULL;
    }
    if (globalFormatDesc) {
        CFRelease(globalFormatDesc);
        globalFormatDesc = NULL;
    }
    
    UIImage *imageToUse = spoofImage ?: createEnhancedTestImage();
    if (!imageToUse) return;
    
    CGImageRef cgImage = imageToUse.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    NSLog(@"[LC] Creating image spoof buffer: %zux%zu", width, height);
    
    // Enhanced pixel buffer attributes
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
        NSLog(@"[LC] Failed to create image spoof buffer: %d", result);
        return;
    }
    
    // Fill the pixel buffer
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
    
    NSLog(@"[LC] Image spoof resources prepared successfully");
}

static CMSampleBufferRef createSampleBufferFromPixelBuffer(CVPixelBufferRef pixelBuffer) {
    if (!pixelBuffer) return NULL;
    
    // Create format description for this pixel buffer
    CMVideoFormatDescriptionRef formatDesc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    
    if (!formatDesc) {
        NSLog(@"[LC] Failed to create format description");
        return NULL;
    }
    
    // Create timing info
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = presentationTime,
        .decodeTimeStamp = kCMTimeInvalid
    };
    
    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus result = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        formatDesc,
        &timingInfo,
        &sampleBuffer
    );
    
    CFRelease(formatDesc);
    
    if (result != noErr) {
        NSLog(@"[LC] Failed to create sample buffer: %d", result);
        return NULL;
    }
    
    return sampleBuffer;
}

static CMSampleBufferRef createEnhancedSampleBuffer(BOOL forLivestream) {
    if ([spoofCameraType isEqualToString:@"video"] && spoofVideoAsset) {
        // Video mode - get next frame from video
        CMSampleBufferRef videoFrame = getNextVideoFrame();
        if (videoFrame) {
            // Extract pixel buffer and create new sample buffer with current timing
            CVPixelBufferRef pixelBuffer = extractPixelBufferFromVideoFrame(videoFrame);
            CFRelease(videoFrame);
            
            if (pixelBuffer) {
                CMSampleBufferRef newSampleBuffer = createSampleBufferFromPixelBuffer(pixelBuffer);
                CVPixelBufferRelease(pixelBuffer);
                return newSampleBuffer;
            }
        }
        
        // Fallback to image if video fails
        NSLog(@"[LC] Video frame failed, falling back to image");
    }
    
    // Image mode or video fallback
    if (!globalSpoofBuffer || !globalFormatDesc) {
        return NULL;
    }
    
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleTimingInfo timingInfo = {
        .duration = forLivestream ? CMTimeMake(1, 30) : CMTimeMake(1, 24),
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
        NSLog(@"[LC] Failed to create image sample buffer: %d", result);
        return NULL;
    }
    
    return sampleBuffer;
}

#pragma mark - Enhanced Frame Delivery

static void deliverEnhancedFrameToDelegate(NSValue *outputKey, NSDictionary *delegateInfo, BOOL isLivestream) {
    AVCaptureVideoDataOutput *output = [outputKey nonretainedObjectValue];
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = delegateInfo[@"delegate"];
    dispatch_queue_t queue = delegateInfo[@"queue"];
    
    if (!output || !delegate || !queue) return;
    
    // Performance throttling
    NSTimeInterval currentTime = CACurrentMediaTime();
    NSTimeInterval frameInterval = isLivestream ? (1.0/30.0) : (1.0/24.0);
    
    if (currentTime - lastFrameTime < frameInterval * 0.8) {
        return; // Skip frame to maintain performance
    }
    lastFrameTime = currentTime;
    
    // Use semaphore to prevent frame backup
    if (dispatch_semaphore_wait(frameDeliverySemaphore, DISPATCH_TIME_NOW) != 0) {
        return; // Previous frame still processing, skip
    }
    
    CMSampleBufferRef sampleBuffer = createEnhancedSampleBuffer(isLivestream);
    if (!sampleBuffer) {
        dispatch_semaphore_signal(frameDeliverySemaphore);
        return;
    }
    
    dispatch_async(queue, ^{
        @try {
            if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                NSArray *connections = output.connections;
                AVCaptureConnection *connection = connections.firstObject;
                
                if (!connection) {
                    NSObject *enhancedStub = [[NSObject alloc] init];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
                    [delegate captureOutput:output 
                           didOutputSampleBuffer:sampleBuffer 
                              fromConnection:(AVCaptureConnection *)enhancedStub];
#pragma clang diagnostic pop
                } else {
                    [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"[LC] Enhanced delivery exception: %@", exception.name);
        } @finally {
            CFRelease(sampleBuffer);
            dispatch_semaphore_signal(frameDeliverySemaphore);
        }
    });
}

#pragma mark - Enhanced AVCaptureVideoDataOutput Hook

@interface AVCaptureVideoDataOutput(LiveContainerUniversalHooks)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerUniversalHooks)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[LC] Universal AVCaptureVideoDataOutput setSampleBufferDelegate intercepted");
    
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] Registering universal spoofed delegate");
        
        if (!activeVideoOutputDelegates) {
            activeVideoOutputDelegates = [[NSMutableDictionary alloc] init];
        }
        
        NSValue *outputKey = [NSValue valueWithNonretainedObject:self];
        
        // Enhanced delegate detection
        NSString *delegateClass = NSStringFromClass([sampleBufferDelegate class]);
        BOOL detectedLivestream = [delegateClass containsString:@"Live"] || 
                                 [delegateClass containsString:@"Stream"] ||
                                 [delegateClass containsString:@"Broadcast"] ||
                                 [delegateClass containsString:@"RTMP"];
        
        activeVideoOutputDelegates[outputKey] = @{
            @"delegate": sampleBufferDelegate,
            @"queue": sampleBufferCallbackQueue ?: dispatch_get_main_queue(),
            @"isLivestream": @(detectedLivestream),
            @"registrationTime": @(CACurrentMediaTime())
        };
        
        // Start enhanced frame delivery
        dispatch_async(spoofDeliveryQueue, ^{
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, spoofDeliveryQueue);
            
            // Default timing - 30fps for livestream, 24fps for regular
            uint64_t interval = detectedLivestream ? (NSEC_PER_SEC / 30) : (NSEC_PER_SEC / 24);
            uint64_t leeway = interval / 20; // 5% leeway
            
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, leeway);
            
            dispatch_source_set_event_handler(timer, ^{
                @synchronized(activeVideoOutputDelegates) {
                    NSDictionary *delegateInfo = activeVideoOutputDelegates[outputKey];
                    if (delegateInfo) {
                        BOOL isLive = [delegateInfo[@"isLivestream"] boolValue];
                        deliverEnhancedFrameToDelegate(outputKey, delegateInfo, isLive);
                    } else {
                        dispatch_source_cancel(timer);
                    }
                }
            });
            
            dispatch_resume(timer);
        });
        
        NSLog(@"[LC] Started enhanced frame delivery (livestream: %d)", detectedLivestream);
        return;
    }
    
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

#pragma mark - Session and Still Image Hooks

@interface AVCaptureSession(LiveContainerHooks)
- (void)lc_startRunning;
@end

@implementation AVCaptureSession(LiveContainerHooks)

- (void)lc_startRunning {
    NSLog(@"[LC] AVCaptureSession startRunning - spoof enabled: %d", spoofCameraEnabled);
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Session start intercepted");
        return;
    }
    
    [self lc_startRunning];
}

@end

@interface AVCaptureStillImageOutput(LiveContainerHooks)
- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler;
@end

@implementation AVCaptureStillImageOutput(LiveContainerHooks)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    NSLog(@"[LC] Still image capture intercepted");
    
    if (spoofCameraEnabled) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            CMSampleBufferRef sampleBuffer = createEnhancedSampleBuffer(NO);
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(sampleBuffer, nil);
                if (sampleBuffer) CFRelease(sampleBuffer);
            });
        });
        return;
    }
    
    [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
}

@end

#pragma mark - Enhanced Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Enhanced AVFoundationGuestHooksInit with video support");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraLoop = guestAppInfo[@"spoofCameraLoop"] ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;
        
        NSLog(@"[LC] Camera spoofing enabled: %d, type: %@, loop: %d", 
              spoofCameraEnabled, spoofCameraType, spoofCameraLoop);
        
        if (!spoofCameraEnabled) {
            return;
        }
        
        // Initialize enhanced resources
        spoofDeliveryQueue = dispatch_queue_create("com.livecontainer.cameraspoof.enhanced", 
                                                  DISPATCH_QUEUE_SERIAL);
        frameDeliverySemaphore = dispatch_semaphore_create(1);
        
        // Load spoof content based on type
        if ([spoofCameraType isEqualToString:@"video"]) {
            spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
            if (spoofCameraVideoPath.length > 0) {
                NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
                spoofVideoAsset = [AVAsset assetWithURL:videoURL];
                
                if (spoofVideoAsset) {
                    videoDuration = spoofVideoAsset.duration;
                    setupVideoReader();
                    NSLog(@"[LC] Loaded video asset: %@ (duration: %.2fs)", 
                          spoofCameraVideoPath, CMTimeGetSeconds(videoDuration));
                } else {
                    NSLog(@"[LC] Failed to load video asset: %@", spoofCameraVideoPath);
                    spoofCameraType = @"image"; // Fallback to image
                }
            } else {
                NSLog(@"[LC] No video path specified, falling back to image");
                spoofCameraType = @"image";
            }
        }
        
        // Load image (either primary or fallback)
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            NSLog(@"[LC] Loaded custom spoof image: %@", spoofImage ? @"SUCCESS" : @"FAILED");
        }
        
        // Prepare image resources (always needed as fallback)
        prepareImageSpoofResources();
        
        // Enhanced hooks
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            NSLog(@"[LC] Hooking enhanced AVCaptureVideoDataOutput");
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            swizzle(captureSessionClass, @selector(startRunning), @selector(lc_startRunning));
        }
        
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            swizzle(stillImageOutputClass, 
                   @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                   @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        }
        
        NSLog(@"[LC] Enhanced camera spoofing initialized successfully (mode: %@)", spoofCameraType);
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in enhanced init: %@", exception);
    }
}