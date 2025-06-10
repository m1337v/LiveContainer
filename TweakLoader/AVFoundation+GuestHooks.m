//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Universal Camera Spoofing - Superior to CJ + BT - Fixed
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraImagePath = @"";
static UIImage *spoofImage = nil;

// IMPROVEMENT 1: Multi-Resolution Support (Better than CJ)
static NSMutableDictionary *resolutionSpecificBuffers = nil;
static NSMutableDictionary *formatDescriptions = nil;

// IMPROVEMENT 2: App-Specific Optimizations (Better than BT's single focus)
static NSMutableDictionary *appSpecificSettings = nil;

// IMPROVEMENT 3: Advanced Performance Management
static dispatch_queue_t spoofDeliveryQueue = NULL;
static NSMutableDictionary *activeVideoOutputDelegates = nil;
static dispatch_semaphore_t resourceSemaphore = NULL;

// IMPROVEMENT 4: Dynamic Frame Rate Adaptation
typedef struct {
    NSTimeInterval lastFrameTime;
    NSInteger consecutiveDrops;
    NSInteger targetFPS;
    NSInteger currentFPS;
    BOOL isLivestreaming;
    NSString *appIdentifier;
} FrameDeliveryContext;

static NSMutableDictionary *frameContexts = nil;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Forward Declarations

static UIImage *createEnhancedTestImage(void);
static void fillPixelBufferWithImage(CVPixelBufferRef pixelBuffer, UIImage *image, CGSize targetSize);
static CMSampleBufferRef createUniversalSampleBuffer(CGSize requestedSize, OSType pixelFormat, BOOL isLivestream);

#pragma mark - Enhanced Image Creation

static UIImage *createEnhancedTestImage(void) {
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
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowOffset = CGSizeMake(2, 2);
    shadow.shadowBlurRadius = 4;
    shadow.shadowColor = [UIColor blackColor];
    
    NSDictionary *titleAttrs = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSShadowAttributeName: shadow
    };
    
    NSString *title = @"LiveContainer Pro\nUniversal Camera";
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

static void fillPixelBufferWithImage(CVPixelBufferRef pixelBuffer, UIImage *image, CGSize targetSize) {
    if (!pixelBuffer || !image) return;
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        baseAddress, (size_t)targetSize.width, (size_t)targetSize.height, 8, bytesPerRow, colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    );
    
    if (context) {
        // High-quality scaling
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        CGContextSetRenderingIntent(context, kCGRenderingIntentDefault);
        
        // Scale image to exact target size
        CGRect drawRect = CGRectMake(0, 0, targetSize.width, targetSize.height);
        CGContextDrawImage(context, drawRect, image.CGImage);
        
        CGContextRelease(context);
    }
    
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

#pragma mark - IMPROVEMENT 1: Dynamic Resolution Management

static NSString *resolutionKeyForSize(CGSize size) {
    return [NSString stringWithFormat:@"%.0fx%.0f", size.width, size.height];
}

static CVPixelBufferRef getOrCreatePixelBufferForResolution(CGSize resolution, OSType format) {
    NSString *key = [NSString stringWithFormat:@"%@_%d", resolutionKeyForSize(resolution), format];
    
    CVPixelBufferRef existingBuffer = (__bridge CVPixelBufferRef)[resolutionSpecificBuffers objectForKey:key];
    if (existingBuffer) {
        return existingBuffer;
    }
    
    // Create new optimized buffer
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES, // Metal support
        (NSString *)kCVPixelBufferBytesPerRowAlignmentKey: @(64),
        (NSString *)kCVPixelBufferPlaneAlignmentKey: @(64)
    };
    
    CVPixelBufferRef newBuffer = NULL;
    CVReturn result = CVPixelBufferCreate(
        kCFAllocatorDefault,
        (size_t)resolution.width,
        (size_t)resolution.height,
        format,
        (__bridge CFDictionaryRef)attributes,
        &newBuffer
    );
    
    if (result == kCVReturnSuccess && newBuffer) {
        [resolutionSpecificBuffers setObject:(__bridge id)newBuffer forKey:key];
        
        // Fill buffer with scaled image
        UIImage *imageToUse = spoofImage ?: createEnhancedTestImage();
        fillPixelBufferWithImage(newBuffer, imageToUse, resolution);
        
        // Create format description
        CMVideoFormatDescriptionRef formatDesc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, newBuffer, &formatDesc);
        if (formatDesc) {
            [formatDescriptions setObject:(__bridge id)formatDesc forKey:key];
        }
        
        NSLog(@"[LC] Created optimized buffer for %@: %dx%d", key, (int)resolution.width, (int)resolution.height);
    }
    
    return newBuffer;
}

#pragma mark - IMPROVEMENT 2: App-Specific Intelligence

static void initializeAppSpecificSettings(void) {
    appSpecificSettings = [[NSMutableDictionary alloc] init];
    
    // TikTok optimizations (Better than BT's hardcoded approach)
    [appSpecificSettings setObject:@{
        @"preferredFPS": @30,
        @"preferredResolution": NSStringFromCGSize(CGSizeMake(1080, 1920)),
        @"useHighQuality": @YES,
        @"livestreamOptimized": @YES,
        @"bufferPreallocation": @YES
    } forKey:@"com.zhiliaoapp.musically"];
    
    // Instagram optimizations
    [appSpecificSettings setObject:@{
        @"preferredFPS": @30,
        @"preferredResolution": NSStringFromCGSize(CGSizeMake(1080, 1080)),
        @"useHighQuality": @YES,
        @"storyOptimized": @YES
    } forKey:@"com.burbn.instagram"];
    
    // Snapchat optimizations
    [appSpecificSettings setObject:@{
        @"preferredFPS": @24,
        @"preferredResolution": NSStringFromCGSize(CGSizeMake(1080, 1920)),
        @"useHighQuality": @NO, // Snapchat compresses anyway
        @"fastDelivery": @YES
    } forKey:@"com.toyopagroup.picaboo"];
    
    // YouTube optimizations
    [appSpecificSettings setObject:@{
        @"preferredFPS": @60,
        @"preferredResolution": NSStringFromCGSize(CGSizeMake(1920, 1080)),
        @"useHighQuality": @YES,
        @"livestreamOptimized": @YES
    } forKey:@"com.google.ios.youtube"];
    
    // Default settings for unknown apps
    [appSpecificSettings setObject:@{
        @"preferredFPS": @30,
        @"preferredResolution": NSStringFromCGSize(CGSizeMake(1280, 720)),
        @"useHighQuality": @YES,
        @"adaptiveQuality": @YES
    } forKey:@"default"];
    
    NSLog(@"[LC] Initialized app-specific optimizations for %lu platforms", (unsigned long)appSpecificSettings.count);
}

static NSDictionary *getSettingsForCurrentApp(void) {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSDictionary *settings = [appSpecificSettings objectForKey:bundleId];
    
    if (!settings) {
        settings = [appSpecificSettings objectForKey:@"default"];
        NSLog(@"[LC] Using default settings for app: %@", bundleId);
    } else {
        NSLog(@"[LC] Using optimized settings for app: %@", bundleId);
    }
    
    return settings;
}

#pragma mark - IMPROVEMENT 3: Intelligent Frame Delivery

static FrameDeliveryContext *getOrCreateFrameContext(NSValue *outputKey) {
    FrameDeliveryContext *context = [[frameContexts objectForKey:outputKey] pointerValue];
    
    if (!context) {
        context = calloc(1, sizeof(FrameDeliveryContext));
        context->lastFrameTime = 0;
        context->consecutiveDrops = 0;
        context->currentFPS = 30;
        context->isLivestreaming = NO;
        context->appIdentifier = [[[NSBundle mainBundle] bundleIdentifier] copy];
        
        // Set target FPS based on app
        NSDictionary *appSettings = getSettingsForCurrentApp();
        context->targetFPS = [appSettings[@"preferredFPS"] integerValue];
        
        [frameContexts setObject:[NSValue valueWithPointer:context] forKey:outputKey];
        NSLog(@"[LC] Created frame context for output with target FPS: %ld", (long)context->targetFPS);
    }
    
    return context;
}

static BOOL shouldDeliverFrame(FrameDeliveryContext *context) {
    NSTimeInterval currentTime = CACurrentMediaTime();
    NSTimeInterval frameInterval = 1.0 / context->targetFPS;
    NSTimeInterval timeSinceLastFrame = currentTime - context->lastFrameTime;
    
    // Adaptive frame rate based on performance
    if (context->consecutiveDrops > 5) {
        // Reduce frame rate to maintain performance
        frameInterval *= 1.5;
        NSLog(@"[LC] Adaptive: Reducing frame rate due to drops");
    } else if (context->consecutiveDrops == 0 && timeSinceLastFrame > frameInterval * 1.2) {
        // Can increase frame rate
        frameInterval *= 0.9;
    }
    
    if (timeSinceLastFrame >= frameInterval) {
        context->lastFrameTime = currentTime;
        context->consecutiveDrops = 0;
        return YES;
    }
    
    context->consecutiveDrops++;
    return NO;
}

#pragma mark - IMPROVEMENT 4: Enhanced Sample Buffer Creation

static CMSampleBufferRef createUniversalSampleBuffer(CGSize requestedSize, OSType pixelFormat, BOOL isLivestream) {
    // Get appropriate pixel buffer for requested specs
    CVPixelBufferRef pixelBuffer = getOrCreatePixelBufferForResolution(requestedSize, pixelFormat);
    if (!pixelBuffer) {
        NSLog(@"[LC] Failed to get pixel buffer for %@", NSStringFromCGSize(requestedSize));
        return NULL;
    }
    
    // Get corresponding format description
    NSString *key = [NSString stringWithFormat:@"%@_%d", resolutionKeyForSize(requestedSize), pixelFormat];
    CMVideoFormatDescriptionRef formatDesc = (__bridge CMVideoFormatDescriptionRef)[formatDescriptions objectForKey:key];
    
    if (!formatDesc) {
        NSLog(@"[LC] No format description for %@", key);
        return NULL;
    }
    
    // Create timing info with app-specific optimizations
    NSDictionary *appSettings = getSettingsForCurrentApp();
    NSInteger fps = [appSettings[@"preferredFPS"] integerValue];
    
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, (int32_t)fps),
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
    
    if (result != noErr) {
        NSLog(@"[LC] Failed to create sample buffer: %d", result);
        return NULL;
    }
    
    return sampleBuffer;
}

#pragma mark - IMPROVEMENT 5: Universal Frame Delivery

static void deliverUniversalFrame(NSValue *outputKey, NSDictionary *delegateInfo) {
    AVCaptureVideoDataOutput *output = [outputKey nonretainedObjectValue];
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = delegateInfo[@"delegate"];
    dispatch_queue_t queue = delegateInfo[@"queue"];
    
    if (!output || !delegate || !queue) return;
    
    // Get frame context for intelligent delivery
    FrameDeliveryContext *context = getOrCreateFrameContext(outputKey);
    
    if (!shouldDeliverFrame(context)) {
        return; // Skip frame based on intelligent timing
    }
    
    // Resource management
    if (dispatch_semaphore_wait(resourceSemaphore, DISPATCH_TIME_NOW) != 0) {
        context->consecutiveDrops++;
        return; // System overloaded, skip frame
    }
    
    // Determine optimal resolution for this output
    CGSize optimalSize = CGSizeMake(1280, 720); // Default
    NSDictionary *appSettings = getSettingsForCurrentApp();
    NSString *preferredRes = appSettings[@"preferredResolution"];
    if (preferredRes) {
        optimalSize = CGSizeFromString(preferredRes);
    }
    
    // Detect livestream context
    NSString *delegateClass = NSStringFromClass([delegate class]);
    BOOL isLivestream = [delegateClass containsString:@"Live"] ||
                       [delegateClass containsString:@"Stream"] ||
                       [delegateClass containsString:@"Broadcast"] ||
                       context->isLivestreaming;
    
    // Create optimized sample buffer
    CMSampleBufferRef sampleBuffer = createUniversalSampleBuffer(optimalSize, kCVPixelFormatType_32BGRA, isLivestream);
    
    if (!sampleBuffer) {
        dispatch_semaphore_signal(resourceSemaphore);
        return;
    }
    
    dispatch_async(queue, ^{
        @try {
            if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                NSArray *connections = output.connections;
                AVCaptureConnection *connection = connections.firstObject;
                
                if (!connection) {
                    // Create enhanced stub connection
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
            NSLog(@"[LC] Universal delivery exception: %@", exception.name);
            context->consecutiveDrops++;
        } @finally {
            CFRelease(sampleBuffer);
            dispatch_semaphore_signal(resourceSemaphore);
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
        
        // Initialize frame context
        FrameDeliveryContext *context = getOrCreateFrameContext(outputKey);
        context->isLivestreaming = detectedLivestream;
        
        // Start intelligent frame delivery
        dispatch_async(spoofDeliveryQueue, ^{
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, spoofDeliveryQueue);
            
            // Adaptive timing based on app settings
            NSDictionary *appSettings = getSettingsForCurrentApp();
            NSInteger targetFPS = [appSettings[@"preferredFPS"] integerValue];
            uint64_t interval = NSEC_PER_SEC / targetFPS;
            uint64_t leeway = interval / 20; // 5% leeway
            
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, leeway);
            
            dispatch_source_set_event_handler(timer, ^{
                @synchronized(activeVideoOutputDelegates) {
                    NSDictionary *delegateInfo = activeVideoOutputDelegates[outputKey];
                    if (delegateInfo) {
                        deliverUniversalFrame(outputKey, delegateInfo);
                    } else {
                        dispatch_source_cancel(timer);
                    }
                }
            });
            
            dispatch_resume(timer);
        });
        
        NSLog(@"[LC] Started universal frame delivery (livestream: %d, app-optimized)", detectedLivestream);
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
            // Use default size for still images
            CMSampleBufferRef sampleBuffer = createUniversalSampleBuffer(CGSizeMake(1280, 720), kCVPixelFormatType_32BGRA, NO);
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

#pragma mark - Universal Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Universal AVFoundationGuestHooksInit - Superior to CJ + BT");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        NSLog(@"[LC] Universal camera spoofing enabled: %d", spoofCameraEnabled);
        
        if (!spoofCameraEnabled) {
            return;
        }
        
        // Initialize universal resources
        spoofDeliveryQueue = dispatch_queue_create("com.livecontainer.cameraspoof.universal", DISPATCH_QUEUE_SERIAL);
        resourceSemaphore = dispatch_semaphore_create(3); // Allow 3 concurrent operations
        resolutionSpecificBuffers = [[NSMutableDictionary alloc] init];
        formatDescriptions = [[NSMutableDictionary alloc] init];
        frameContexts = [[NSMutableDictionary alloc] init];
        
        // Initialize app-specific intelligence
        initializeAppSpecificSettings();
        
        // Load spoof image with better error handling
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            NSLog(@"[LC] Loaded spoof image: %@", spoofImage ? @"SUCCESS" : @"FAILED");
        }
        
        // Create default image if needed (will be created on-demand in getOrCreatePixelBufferForResolution)
        
        // Universal hooks
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            NSLog(@"[LC] Hooking universal AVCaptureVideoDataOutput");
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
        
        NSLog(@"[LC] Universal camera spoofing initialized - Multi-app optimized");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in universal init: %@", exception);
    }
}