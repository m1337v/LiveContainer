//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Enhanced camera spoofing - Fixed compilation issues
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
static UIImage *spoofImage = nil;
static CVPixelBufferRef globalSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef globalFormatDesc = NULL;
static dispatch_queue_t spoofDeliveryQueue = NULL;

// Enhanced tracking
static NSMutableDictionary *activeVideoOutputDelegates = nil;
static NSMutableDictionary *activeLivestreamSessions = nil;
static NSMutableSet *captureDeviceInputs = nil;

// Performance optimization
static dispatch_semaphore_t frameDeliverySemaphore = NULL;
static NSTimeInterval lastFrameTime = 0;
static BOOL isLivestreamMode = NO;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Enhanced Resource Management

static UIImage *createEnhancedTestImage(void) {
    CGSize size = CGSizeMake(1280, 720); // Reasonable size for better performance
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

static void prepareEnhancedSpoofResources(void) {
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
    
    NSLog(@"[LC] Creating enhanced spoof buffer: %zux%zu", width, height);
    
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
        NSLog(@"[LC] Failed to create enhanced spoof buffer: %d", result);
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
    
    NSLog(@"[LC] Enhanced spoof resources prepared successfully");
}

static CMSampleBufferRef createEnhancedSampleBuffer(BOOL forLivestream) {
    if (!globalSpoofBuffer || !globalFormatDesc) {
        return NULL;
    }
    
    // Enhanced timing for livestream
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
        NSLog(@"[LC] Failed to create enhanced sample buffer: %d", result);
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
                    // Enhanced connection handling
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

#pragma mark - Enhanced Hooks

@interface AVCaptureVideoDataOutput(LiveContainerEnhancedHooks)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerEnhancedHooks)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[LC] Enhanced AVCaptureVideoDataOutput setSampleBufferDelegate intercepted");
    
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] Registering enhanced spoofed delegate");
        
        if (!activeVideoOutputDelegates) {
            activeVideoOutputDelegates = [[NSMutableDictionary alloc] init];
        }
        
        NSValue *outputKey = [NSValue valueWithNonretainedObject:self];
        
        // Detect livestream mode
        NSString *delegateClass = NSStringFromClass([sampleBufferDelegate class]);
        BOOL detectedLivestream = [delegateClass containsString:@"Live"] || 
                                 [delegateClass containsString:@"Stream"] ||
                                 [delegateClass containsString:@"Broadcast"];
        
        if (detectedLivestream) {
            isLivestreamMode = YES;
            NSLog(@"[LC] Detected livestream mode: %@", delegateClass);
        }
        
        activeVideoOutputDelegates[outputKey] = @{
            @"delegate": sampleBufferDelegate,
            @"queue": sampleBufferCallbackQueue ?: dispatch_get_main_queue(),
            @"isLivestream": @(detectedLivestream)
        };
        
        // Enhanced frame delivery with performance optimization
        dispatch_async(spoofDeliveryQueue, ^{
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, spoofDeliveryQueue);
            
            // Adaptive frame rate based on mode
            uint64_t interval = detectedLivestream ? (NSEC_PER_SEC / 30) : (NSEC_PER_SEC / 24);
            uint64_t leeway = interval / 10; // 10% leeway for performance
            
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
        NSLog(@"[LC] Enhanced AVFoundationGuestHooksInit");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        NSLog(@"[LC] Enhanced camera spoofing enabled: %d", spoofCameraEnabled);
        
        if (!spoofCameraEnabled) {
            return;
        }
        
        // Initialize enhanced resources
        spoofDeliveryQueue = dispatch_queue_create("com.livecontainer.cameraspoof.enhanced", 
                                                  DISPATCH_QUEUE_SERIAL);
        frameDeliverySemaphore = dispatch_semaphore_create(1);
        captureDeviceInputs = [[NSMutableSet alloc] init];
        activeLivestreamSessions = [[NSMutableDictionary alloc] init];
        
        // Load enhanced spoof image
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            NSLog(@"[LC] Loaded custom spoof image: %@", spoofImage ? @"SUCCESS" : @"FAILED");
        }
        
        // Prepare enhanced resources
        prepareEnhancedSpoofResources();
        
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
        
        NSLog(@"[LC] Enhanced camera spoofing initialized successfully");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in enhanced init: %@", exception);
    }
}