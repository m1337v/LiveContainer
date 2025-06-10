//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Simple camera spoofing with video support
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
static BOOL videoReaderFinished = NO;

// Resources
static CVPixelBufferRef globalSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef globalFormatDesc = NULL;
static dispatch_queue_t spoofDeliveryQueue = NULL;
static NSMutableDictionary *activeVideoOutputDelegates = nil;
static dispatch_semaphore_t frameDeliverySemaphore = NULL;

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
    
    // Simple output settings
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
            currentVideoTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            return sampleBuffer;
        } else {
            // End of video
            videoReaderFinished = YES;
            
            // Loop if enabled
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
    // Clean up existing resources
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
    
    NSLog(@"[LC] Image resources prepared successfully");
}

static CMSampleBufferRef createSampleBuffer(void) {
    CMSampleBufferRef sampleBuffer = NULL;
    
    if ([spoofCameraType isEqualToString:@"video"] && spoofVideoAsset) {
        // Try to get video frame first
        CMSampleBufferRef videoFrame = getNextVideoFrame();
        if (videoFrame) {
            // Use the video frame directly with updated timing
            CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(videoFrame);
            if (imageBuffer) {
                CMVideoFormatDescriptionRef formatDesc = NULL;
                CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &formatDesc);
                
                if (formatDesc) {
                    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
                    CMSampleTimingInfo timingInfo = {
                        .duration = CMTimeMake(1, 30),
                        .presentationTimeStamp = presentationTime,
                        .decodeTimeStamp = kCMTimeInvalid
                    };
                    
                    OSStatus result = CMSampleBufferCreateReadyWithImageBuffer(
                        kCFAllocatorDefault,
                        imageBuffer,
                        formatDesc,
                        &timingInfo,
                        &sampleBuffer
                    );
                    
                    CFRelease(formatDesc);
                    
                    if (result == noErr && sampleBuffer) {
                        CFRelease(videoFrame);
                        return sampleBuffer;
                    }
                }
            }
            CFRelease(videoFrame);
        }
        
        NSLog(@"[LC] Video frame failed, using fallback image");
    }
    
    // Fallback to image
    if (!globalSpoofBuffer || !globalFormatDesc) {
        return NULL;
    }
    
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = presentationTime,
        .decodeTimeStamp = kCMTimeInvalid
    };
    
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

#pragma mark - Frame Delivery

static void deliverFrameToDelegate(NSValue *outputKey, NSDictionary *delegateInfo) {
    AVCaptureVideoDataOutput *output = [outputKey nonretainedObjectValue];
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = delegateInfo[@"delegate"];
    dispatch_queue_t queue = delegateInfo[@"queue"];
    
    if (!output || !delegate || !queue) return;
    
    // Use semaphore to prevent frame backup
    if (dispatch_semaphore_wait(frameDeliverySemaphore, DISPATCH_TIME_NOW) != 0) {
        return;
    }
    
    CMSampleBufferRef sampleBuffer = createSampleBuffer();
    if (!sampleBuffer) {
        dispatch_semaphore_signal(frameDeliverySemaphore);
        return;
    }
    
    dispatch_async(queue, ^{
        @try {
            if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                NSArray *connections = output.connections;
                AVCaptureConnection *connection = connections.firstObject;
                
                // Create a dummy connection if none exists
                if (!connection) {
                    connection = [[AVCaptureConnection alloc] initWithInputPorts:@[] output:output];
                }
                
                [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
            }
        } @catch (NSException *exception) {
            NSLog(@"[LC] Frame delivery exception: %@", exception.name);
        } @finally {
            CFRelease(sampleBuffer);
            dispatch_semaphore_signal(frameDeliverySemaphore);
        }
    });
}

#pragma mark - Hooks

@interface AVCaptureVideoDataOutput(LiveContainerHooks)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerHooks)

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
        
        // Start simple frame delivery - 30fps
        dispatch_async(spoofDeliveryQueue, ^{
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, spoofDeliveryQueue);
            
            uint64_t interval = NSEC_PER_SEC / 30; // 30fps
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, interval / 10);
            
            dispatch_source_set_event_handler(timer, ^{
                @synchronized(activeVideoOutputDelegates) {
                    NSDictionary *delegateInfo = activeVideoOutputDelegates[outputKey];
                    if (delegateInfo) {
                        deliverFrameToDelegate(outputKey, delegateInfo);
                    } else {
                        NSLog(@"[LC] Delegate removed, cancelling timer");
                        dispatch_source_cancel(timer);
                    }
                }
            });
            
            dispatch_resume(timer);
            NSLog(@"[LC] Frame delivery timer started");
        });
        
        return;
    }
    
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

@interface AVCaptureSession(LiveContainerHooks)
- (void)lc_startRunning;
@end

@implementation AVCaptureSession(LiveContainerHooks)

- (void)lc_startRunning {
    NSLog(@"[LC] AVCaptureSession startRunning - spoof enabled: %d", spoofCameraEnabled);
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Session start intercepted - not starting real camera");
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
            CMSampleBufferRef sampleBuffer = createSampleBuffer();
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

#pragma mark - Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Simple AVFoundation camera spoofing init");
        
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
        spoofDeliveryQueue = dispatch_queue_create("com.livecontainer.cameraspoof", DISPATCH_QUEUE_SERIAL);
        frameDeliverySemaphore = dispatch_semaphore_create(1);
        
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
        
        // Setup hooks
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
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
        
        NSLog(@"[LC] Camera spoofing initialized (mode: %@)", spoofCameraType);
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in init: %@", exception);
    }
}