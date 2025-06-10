//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Camera spoofing - fixed connection issue
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

// Track active video outputs and their delegates 
static NSMutableDictionary *activeVideoOutputDelegates = nil;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Resource Management (Capture Style)

static UIImage *createDefaultTestImage(void) {
    CGSize size = CGSizeMake(1280, 720);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Gradient background
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {
        0.0, 0.5, 1.0, 1.0,  // Blue
        1.0, 0.0, 0.5, 1.0   // Pink
    };
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointZero, 
                               CGPointMake(size.width, size.height), 0);
    
    // Text overlay
    UIFont *font = [UIFont boldSystemFontOfSize:48];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSStrokeColorAttributeName: [UIColor blackColor],
        NSStrokeWidthAttributeName: @(-2)
    };
    
    NSString *text = @"LiveContainer Camera";
    CGRect textRect = CGRectMake(0, size.height/2 - 30, size.width, 60);
    [text drawInRect:textRect withAttributes:attributes];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    
    return image;
}

static void prepareGlobalSpoofResources(void) {
    // Clean up existing resources
    if (globalSpoofBuffer) {
        CVPixelBufferRelease(globalSpoofBuffer);
        globalSpoofBuffer = NULL;
    }
    if (globalFormatDesc) {
        CFRelease(globalFormatDesc);
        globalFormatDesc = NULL;
    }
    
    UIImage *imageToUse = spoofImage ?: createDefaultTestImage();
    if (!imageToUse) return;
    
    CGImageRef cgImage = imageToUse.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    // Create pixel buffer
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
        NSLog(@"[LC] Failed to create global spoof buffer: %d", result);
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
    
    NSLog(@"[LC] Global spoof resources prepared: %zux%zu", width, height);
}

static CMSampleBufferRef createSpoofSampleBuffer(void) {
    if (!globalSpoofBuffer || !globalFormatDesc) {
        return NULL;
    }
    
    // Create timing info with current time
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30), // 30 FPS
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
        NSLog(@"[LC] Failed to create spoof sample buffer: %d", result);
        return NULL;
    }
    
    return sampleBuffer;
}

// Frame delivery function (FIXED - eliminate the warning)
static void deliverFrameToDelegate(NSValue *outputKey, NSDictionary *delegateInfo) {
    AVCaptureVideoDataOutput *output = [outputKey nonretainedObjectValue];
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = delegateInfo[@"delegate"];
    dispatch_queue_t queue = delegateInfo[@"queue"];
    
    if (!output || !delegate || !queue) return;
    
    CMSampleBufferRef sampleBuffer = createSpoofSampleBuffer();
    if (!sampleBuffer) return;
    
    dispatch_async(queue, ^{
        if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            // Try to get existing connections from the output first
            NSArray *connections = output.connections;
            AVCaptureConnection *connection = connections.firstObject;
            
            if (connection) {
                // Use existing connection if available
                [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
            } else {
                // Create a minimal stub connection object to avoid the warning
                // This is a common pattern in camera spoofing tweaks
                NSObject *stubConnection = [[NSObject alloc] init];
                
                @try {
                    // Cast to AVCaptureConnection* to satisfy the type checker
                    [delegate captureOutput:output 
                           didOutputSampleBuffer:sampleBuffer 
                              fromConnection:(AVCaptureConnection *)stubConnection];
                } @catch (NSException *exception) {
                    NSLog(@"[LC] Delegate rejected stub connection: %@", exception.name);
                    // If stub connection fails, some delegates might work with different approaches
                    // We could implement more sophisticated connection creation here if needed
                }
            }
        }
        CFRelease(sampleBuffer);
    });
}

#pragma mark - Core Hook: AVCaptureVideoDataOutput

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
        
        // Start frame delivery
        dispatch_async(spoofDeliveryQueue, ^{
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, spoofDeliveryQueue);
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 
                                     NSEC_PER_SEC / 30, NSEC_PER_SEC / 100); // 30 FPS
            
            dispatch_source_set_event_handler(timer, ^{
                @synchronized(activeVideoOutputDelegates) {
                    NSDictionary *delegateInfo = activeVideoOutputDelegates[outputKey];
                    if (delegateInfo) {
                        deliverFrameToDelegate(outputKey, delegateInfo);
                    } else {
                        dispatch_source_cancel(timer);
                    }
                }
            });
            
            dispatch_resume(timer);
        });
        
        NSLog(@"[LC] Started frame delivery for output");
        return;
    }
    
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

#pragma mark - Session Management

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

#pragma mark - Still Image Support

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
            CMSampleBufferRef sampleBuffer = createSpoofSampleBuffer();
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
        NSLog(@"[LC] AVFoundationGuestHooksInit");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        NSLog(@"[LC] Camera spoofing enabled: %d", spoofCameraEnabled);
        
        if (!spoofCameraEnabled) {
            return;
        }
        
        // Initialize delivery queue
        spoofDeliveryQueue = dispatch_queue_create("com.livecontainer.cameraspoof.delivery", DISPATCH_QUEUE_SERIAL);
        
        // Load spoof image
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            NSLog(@"[LC] Loaded spoof image: %@", spoofImage ? @"SUCCESS" : @"FAILED");
        }
        
        // Prepare global resources
        prepareGlobalSpoofResources();
        
        // Hook video data output
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            NSLog(@"[LC] Hooking AVCaptureVideoDataOutput");
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        // Hook session
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            swizzle(captureSessionClass, @selector(startRunning), @selector(lc_startRunning));
        }
        
        // Hook still image
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            swizzle(stillImageOutputClass, 
                   @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                   @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        }
        
        NSLog(@"[LC] Camera spoofing initialized");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in AVFoundationGuestHooksInit: %@", exception);
    }
}