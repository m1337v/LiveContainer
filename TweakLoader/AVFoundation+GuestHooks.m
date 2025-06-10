//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Camera spoofing based on capture patterns
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraImagePath = @"";
static UIImage *spoofImage = nil;
static CVPixelBufferRef cachedPixelBuffer = NULL;
static CMVideoFormatDescriptionRef cachedFormatDesc = NULL;

// Track active delegates and their queues
static NSMutableDictionary *activeVideoOutputs = nil;
static dispatch_queue_t spoofQueue = NULL;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Utility Functions

static UIImage *createDefaultTestImage(void) {
    CGSize size = CGSizeMake(1280, 720);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Create a more distinctive test pattern
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {
        0.0, 0.5, 1.0, 1.0,  // Blue
        1.0, 0.0, 0.5, 1.0   // Pink
    };
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointZero, 
                               CGPointMake(size.width, size.height), 0);
    
    // Add branding
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

static void prepareCameraResources(void) {
    // Clean up existing resources
    if (cachedPixelBuffer) {
        CVPixelBufferRelease(cachedPixelBuffer);
        cachedPixelBuffer = NULL;
    }
    if (cachedFormatDesc) {
        CFRelease(cachedFormatDesc);
        cachedFormatDesc = NULL;
    }
    
    // Get image to use
    UIImage *imageToUse = spoofImage ?: createDefaultTestImage();
    if (!imageToUse) return;
    
    CGImageRef cgImage = imageToUse.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    // Create pixel buffer with optimal settings
    NSDictionary *pixelBufferAttributes = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES
    };
    
    CVReturn result = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)pixelBufferAttributes,
        &cachedPixelBuffer
    );
    
    if (result != kCVReturnSuccess) {
        NSLog(@"[LC] Failed to create cached pixel buffer: %d", result);
        return;
    }
    
    // Fill pixel buffer
    CVPixelBufferLockBaseAddress(cachedPixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(cachedPixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cachedPixelBuffer);
    
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
    CVPixelBufferUnlockBaseAddress(cachedPixelBuffer, 0);
    
    // Create format description
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, 
                                                 cachedPixelBuffer, 
                                                 &cachedFormatDesc);
    
    NSLog(@"[LC] Camera resources prepared: %zux%zu", width, height);
}

static CMSampleBufferRef createSpoofSampleBuffer(void) {
    if (!cachedPixelBuffer || !cachedFormatDesc) {
        return NULL;
    }
    
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = presentationTime,
        .decodeTimeStamp = kCMTimeInvalid
    };
    
    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus result = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        cachedPixelBuffer,
        cachedFormatDesc,
        &timingInfo,
        &sampleBuffer
    );
    
    if (result != noErr) {
        NSLog(@"[LC] Failed to create sample buffer: %d", result);
        return NULL;
    }
    
    return sampleBuffer;
}

static void deliverSpoofFramesToAllOutputs(void) {
    if (!spoofCameraEnabled || !activeVideoOutputs) return;
    
    CMSampleBufferRef sampleBuffer = createSpoofSampleBuffer();
    if (!sampleBuffer) return;
    
    // Deliver to all registered video outputs
    for (NSValue *outputKey in activeVideoOutputs.allKeys) {
        AVCaptureVideoDataOutput *output = [outputKey nonretainedObjectValue];
        NSDictionary *outputInfo = activeVideoOutputs[outputKey];
        
        id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = outputInfo[@"delegate"];
        dispatch_queue_t queue = outputInfo[@"queue"];
        
        if (delegate && queue) {
            // Create a connection object (simplified)
            AVCaptureConnection *connection = [[AVCaptureConnection alloc] init];
            
            dispatch_async(queue, ^{
                if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                    [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
                }
            });
        }
    }
    
    CFRelease(sampleBuffer);
}

#pragma mark - AVCaptureVideoDataOutput Hooks (Capture-style)

@interface AVCaptureVideoDataOutput(LiveContainerHooks)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerHooks)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[LC] AVCaptureVideoDataOutput setSampleBufferDelegate called");
    
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] Registering spoofed video data output delegate");
        
        if (!activeVideoOutputs) {
            activeVideoOutputs = [[NSMutableDictionary alloc] init];
        }
        
        NSValue *outputKey = [NSValue valueWithNonretainedObject:self];
        activeVideoOutputs[outputKey] = @{
            @"delegate": sampleBufferDelegate,
            @"queue": sampleBufferCallbackQueue ?: dispatch_get_main_queue()
        };
        
        NSLog(@"[LC] Added video output to spoof tracking");
        
        // Don't call original - we'll handle frame delivery ourselves
        return;
    }
    
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

#pragma mark - AVCaptureSession Hooks

@interface AVCaptureSession(LiveContainerHooks)
- (void)lc_startRunning;
- (void)lc_stopRunning;
- (BOOL)lc_addInput:(AVCaptureInput *)input error:(NSError **)error;
@end

@implementation AVCaptureSession(LiveContainerHooks)

- (void)lc_startRunning {
    NSLog(@"[LC] AVCaptureSession startRunning called");
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Starting spoofed camera session");
        
        // Start frame delivery timer
        static dispatch_source_t frameTimer = nil;
        if (frameTimer) {
            dispatch_source_cancel(frameTimer);
        }
        
        frameTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, spoofQueue);
        dispatch_source_set_timer(frameTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 
                                 NSEC_PER_SEC / 30, NSEC_PER_SEC / 100); // 30 FPS
        
        dispatch_source_set_event_handler(frameTimer, ^{
            deliverSpoofFramesToAllOutputs();
        });
        
        dispatch_resume(frameTimer);
        
        // Don't start real camera
        return;
    }
    
    [self lc_startRunning];
}

- (void)lc_stopRunning {
    NSLog(@"[LC] AVCaptureSession stopRunning called");
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Stopping spoofed camera session");
        // Timer cleanup is handled automatically
    }
    
    [self lc_stopRunning];
}

- (BOOL)lc_addInput:(AVCaptureInput *)input error:(NSError **)error {
    NSLog(@"[LC] AVCaptureSession addInput called: %@", input);
    
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
            NSLog(@"[LC] Allowing camera input for spoofing compatibility");
            return YES; // Pretend success but don't actually use it
        }
    }
    
    return [self lc_addInput:input error:error];
}

@end

#pragma mark - AVCaptureStillImageOutput Hooks

@interface AVCaptureStillImageOutput(LiveContainerHooks)
- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler;
@end

@implementation AVCaptureStillImageOutput(LiveContainerHooks)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection 
                                       completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    NSLog(@"[LC] AVCaptureStillImageOutput capture called");
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Returning spoofed still image");
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            CMSampleBufferRef sampleBuffer = createSpoofSampleBuffer();
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (sampleBuffer) {
                    handler(sampleBuffer, nil);
                    CFRelease(sampleBuffer);
                } else {
                    NSError *error = [NSError errorWithDomain:@"LiveContainerCameraSpoof" 
                                                         code:1 
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create spoofed image"}];
                    handler(NULL, error);
                }
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
        NSLog(@"[LC] AVFoundationGuestHooksInit starting (capture-style)");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info available");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        NSLog(@"[LC] Camera spoofing enabled: %d", spoofCameraEnabled);
        
        if (!spoofCameraEnabled) {
            NSLog(@"[LC] Camera spoofing disabled, skipping initialization");
            return;
        }
        
        // Initialize spoof queue
        spoofQueue = dispatch_queue_create("com.livecontainer.cameraspoof", DISPATCH_QUEUE_SERIAL);
        
        // Load spoofed image if available
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            if (spoofImage) {
                NSLog(@"[LC] Loaded spoof image: %@", spoofCameraImagePath);
            } else {
                NSLog(@"[LC] Failed to load spoof image: %@", spoofCameraImagePath);
            }
        }
        
        // Prepare camera resources
        prepareCameraResources();
        
        // Hook AVCaptureVideoDataOutput (key difference from your current approach)
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            NSLog(@"[LC] Hooking AVCaptureVideoDataOutput methods");
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        // Hook AVCaptureSession
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            NSLog(@"[LC] Hooking AVCaptureSession methods");
            swizzle(captureSessionClass, @selector(startRunning), @selector(lc_startRunning));
            swizzle(captureSessionClass, @selector(stopRunning), @selector(lc_stopRunning));
            swizzle(captureSessionClass, @selector(addInput:error:), @selector(lc_addInput:error:));
        }
        
        // Hook AVCaptureStillImageOutput
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            NSLog(@"[LC] Hooking AVCaptureStillImageOutput methods");
            swizzle(stillImageOutputClass, 
                   @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                   @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        }
        
        NSLog(@"[LC] Camera spoofing hooks initialized successfully (capture-style)");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in AVFoundationGuestHooksInit: %@", exception);
    }
}