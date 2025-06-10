//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Camera spoofing implementation based on capture/fokodak patterns
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

// Configuration variables
static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraType = @"image";
static NSString *spoofCameraImagePath = @"";
static NSString *spoofCameraVideoPath = @"";
static BOOL spoofCameraLoop = YES;

// Runtime variables
static UIImage *spoofImage = nil;
static CVPixelBufferRef spoofPixelBuffer = NULL;
static CMVideoFormatDescriptionRef spoofFormatDescription = NULL;
static dispatch_queue_t cameraQueue = NULL;
static NSMutableSet *activeSessions = nil;
static NSMutableDictionary *sessionOutputs = nil;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Utility Functions

static CVPixelBufferRef createPixelBufferFromImage(UIImage *image) {
    if (!image || !image.CGImage) {
        NSLog(@"[LC] Invalid image for pixel buffer creation");
        return NULL;
    }
    
    CGImageRef cgImage = image.CGImage;
    CGSize imageSize = CGSizeMake(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    
    // Use standard camera resolutions
    CGSize targetSize = CGSizeMake(1280, 720); // 720p default
    if (imageSize.width > 1920 || imageSize.height > 1080) {
        targetSize = CGSizeMake(1920, 1080); // 1080p for large images
    }
    
    // Maintain aspect ratio
    CGFloat aspectRatio = imageSize.width / imageSize.height;
    if (targetSize.width / targetSize.height > aspectRatio) {
        targetSize.width = targetSize.height * aspectRatio;
    } else {
        targetSize.height = targetSize.width / aspectRatio;
    }
    
    // Ensure even dimensions
    targetSize.width = floor(targetSize.width / 2) * 2;
    targetSize.height = floor(targetSize.height / 2) * 2;
    
    NSDictionary *pixelBufferAttributes = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES
    };
    
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn result = CVPixelBufferCreate(
        kCFAllocatorDefault,
        (size_t)targetSize.width,
        (size_t)targetSize.height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)pixelBufferAttributes,
        &pixelBuffer
    );
    
    if (result != kCVReturnSuccess) {
        NSLog(@"[LC] Failed to create pixel buffer: %d", result);
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        baseAddress,
        (size_t)targetSize.width,
        (size_t)targetSize.height,
        8,
        bytesPerRow,
        colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    );
    
    if (context) {
        // Clear and draw image
        CGContextClearRect(context, CGRectMake(0, 0, targetSize.width, targetSize.height));
        CGContextDrawImage(context, CGRectMake(0, 0, targetSize.width, targetSize.height), cgImage);
        CGContextRelease(context);
    }
    
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    return pixelBuffer;
}

static CMSampleBufferRef createSampleBufferFromPixelBuffer(CVPixelBufferRef pixelBuffer) {
    if (!pixelBuffer) return NULL;
    
    CMVideoFormatDescriptionRef formatDescription = NULL;
    OSStatus result = CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        &formatDescription
    );
    
    if (result != noErr) {
        NSLog(@"[LC] Failed to create format description: %d", result);
        return NULL;
    }
    
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30), // 30 FPS
        .presentationTimeStamp = presentationTime,
        .decodeTimeStamp = kCMTimeInvalid
    };
    
    CMSampleBufferRef sampleBuffer = NULL;
    result = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        formatDescription,
        &timingInfo,
        &sampleBuffer
    );
    
    CFRelease(formatDescription);
    
    if (result != noErr) {
        NSLog(@"[LC] Failed to create sample buffer: %d", result);
        return NULL;
    }
    
    return sampleBuffer;
}

static UIImage *createDefaultTestImage(void) {
    CGSize size = CGSizeMake(1280, 720);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Create gradient background
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {
        0.1, 0.4, 0.8, 1.0,  // Blue
        0.8, 0.1, 0.6, 1.0   // Magenta
    };
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointZero, CGPointMake(size.width, size.height), 0);
    
    // Add LiveContainer branding
    UIFont *titleFont = [UIFont boldSystemFontOfSize:48];
    UIFont *subtitleFont = [UIFont systemFontOfSize:24];
    
    NSDictionary *titleAttributes = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSStrokeColorAttributeName: [UIColor blackColor],
        NSStrokeWidthAttributeName: @(-3)
    };
    
    NSDictionary *subtitleAttributes = @{
        NSFontAttributeName: subtitleFont,
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSStrokeColorAttributeName: [UIColor blackColor],
        NSStrokeWidthAttributeName: @(-2)
    };
    
    NSString *title = @"LiveContainer";
    NSString *subtitle = @"Camera Spoofing Active";
    
    CGRect titleRect = CGRectMake(0, size.height/2 - 60, size.width, 60);
    CGRect subtitleRect = CGRectMake(0, size.height/2 + 10, size.width, 30);
    
    [title drawInRect:titleRect withAttributes:titleAttributes];
    [subtitle drawInRect:subtitleRect withAttributes:subtitleAttributes];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    
    return image;
}

static void prepareForCameraSpoofing(void) {
    NSLog(@"[LC] Preparing camera spoofing resources");
    
    // Load spoofed image
    UIImage *imageToUse = nil;
    if (spoofCameraImagePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:spoofCameraImagePath]) {
        imageToUse = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
        if (imageToUse) {
            NSLog(@"[LC] Loaded custom spoof image: %@", spoofCameraImagePath);
        } else {
            NSLog(@"[LC] Failed to load custom spoof image, using default");
        }
    }
    
    if (!imageToUse) {
        imageToUse = createDefaultTestImage();
    }
    
    spoofImage = imageToUse;
    
    // Create pixel buffer
    if (spoofPixelBuffer) {
        CVPixelBufferRelease(spoofPixelBuffer);
    }
    spoofPixelBuffer = createPixelBufferFromImage(spoofImage);
    
    // Create format description
    if (spoofFormatDescription) {
        CFRelease(spoofFormatDescription);
    }
    if (spoofPixelBuffer) {
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, spoofPixelBuffer, &spoofFormatDescription);
    }
    
    NSLog(@"[LC] Camera spoofing resources prepared");
}

static void deliverSpoofedFramesToOutput(AVCaptureOutput *output, AVCaptureConnection *connection) {
    if (!spoofPixelBuffer) return;
    
    CMSampleBufferRef sampleBuffer = createSampleBufferFromPixelBuffer(spoofPixelBuffer);
    if (!sampleBuffer) return;
    
    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
        AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
        id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = videoOutput.sampleBufferDelegate;
        dispatch_queue_t queue = videoOutput.sampleBufferCallbackQueue;
        
        if (delegate && queue) {
            dispatch_async(queue, ^{
                if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                    [delegate captureOutput:videoOutput didOutputSampleBuffer:sampleBuffer fromConnection:connection];
                }
                CFRelease(sampleBuffer);
            });
        } else {
            CFRelease(sampleBuffer);
        }
    } else {
        CFRelease(sampleBuffer);
    }
}

#pragma mark - AVCaptureSession Hooks

@interface AVCaptureSession(LiveContainerHooks)
- (void)lc_startRunning;
- (void)lc_stopRunning;
- (BOOL)lc_addInput:(AVCaptureInput *)input error:(NSError **)error;
- (BOOL)lc_addOutput:(AVCaptureOutput *)output;
- (BOOL)lc_canAddInput:(AVCaptureInput *)input;
- (BOOL)lc_canAddOutput:(AVCaptureOutput *)output;
@end

@implementation AVCaptureSession(LiveContainerHooks)

- (void)lc_startRunning {
    NSLog(@"[LC] AVCaptureSession startRunning called");
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Camera spoofing enabled, managing spoofed session");
        
        // Track this session
        if (!activeSessions) {
            activeSessions = [[NSMutableSet alloc] init];
        }
        [activeSessions addObject:self];
        
        // Start delivering frames to outputs
        NSArray *outputs = sessionOutputs[@((NSUInteger)self)];
        if (outputs) {
            dispatch_async(cameraQueue, ^{
                for (NSDictionary *outputInfo in outputs) {
                    AVCaptureOutput *output = outputInfo[@"output"];
                    AVCaptureConnection *connection = outputInfo[@"connection"];
                    
                    // Create timer for this output
                    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, cameraQueue);
                    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC / 30, NSEC_PER_SEC / 100);
                    
                    dispatch_source_set_event_handler(timer, ^{
                        if (![activeSessions containsObject:self]) {
                            dispatch_source_cancel(timer);
                            return;
                        }
                        deliverSpoofedFramesToOutput(output, connection);
                    });
                    
                    dispatch_resume(timer);
                }
            });
        }
        
        // Don't call original startRunning to prevent real camera access
        return;
    }
    
    [self lc_startRunning];
}

- (void)lc_stopRunning {
    NSLog(@"[LC] AVCaptureSession stopRunning called");
    
    if (spoofCameraEnabled) {
        [activeSessions removeObject:self];
        NSLog(@"[LC] Removed spoofed session from active list");
    }
    
    [self lc_stopRunning];
}

- (BOOL)lc_addInput:(AVCaptureInput *)input error:(NSError **)error {
    NSLog(@"[LC] AVCaptureSession addInput called: %@", input);
    
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
            NSLog(@"[LC] Blocking camera input due to spoofing");
            return YES; // Pretend success but don't actually add
        }
    }
    
    return [self lc_addInput:input error:error];
}

- (BOOL)lc_addOutput:(AVCaptureOutput *)output {
    NSLog(@"[LC] AVCaptureSession addOutput called: %@", output);
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Adding output to spoofed session");
        
        // Initialize session outputs tracking
        if (!sessionOutputs) {
            sessionOutputs = [[NSMutableDictionary alloc] init];
        }
        
        NSUInteger sessionKey = (NSUInteger)self;
        NSMutableArray *outputs = sessionOutputs[@(sessionKey)];
        if (!outputs) {
            outputs = [[NSMutableArray alloc] init];
            sessionOutputs[@(sessionKey)] = outputs;
        }
        
        // Create a fake connection for this output
        AVCaptureConnection *connection = [[AVCaptureConnection alloc] init];
        
        [outputs addObject:@{
            @"output": output,
            @"connection": connection
        }];
        
        NSLog(@"[LC] Output added to spoofed session tracking");
        return YES; // Pretend success
    }
    
    return [self lc_addOutput:output];
}

- (BOOL)lc_canAddInput:(AVCaptureInput *)input {
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
            NSLog(@"[LC] Allowing camera input check for spoofing");
            return YES; // Allow check to succeed
        }
    }
    
    return [self lc_canAddInput:input];
}

- (BOOL)lc_canAddOutput:(AVCaptureOutput *)output {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Allowing output check for spoofing");
        return YES; // Allow all outputs for spoofing
    }
    
    return [self lc_canAddOutput:output];
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
    
    if (spoofCameraEnabled && spoofPixelBuffer) {
        NSLog(@"[LC] Returning spoofed still image");
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            CMSampleBufferRef sampleBuffer = createSampleBufferFromPixelBuffer(spoofPixelBuffer);
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

#pragma mark - AVCapturePhotoOutput Hooks (iOS 10+)

@interface AVCapturePhotoOutput(LiveContainerHooks)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@implementation AVCapturePhotoOutput(LiveContainerHooks)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    NSLog(@"[LC] AVCapturePhotoOutput capture called");
    
    if (spoofCameraEnabled && spoofPixelBuffer) {
        NSLog(@"[LC] Handling spoofed photo capture");
        
        // For photo output, we need to create a more complex response
        // This is a simplified implementation - real photo output spoofing would need
        // to create proper AVCapturePhoto objects
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // This is a simplified approach - in practice, you'd need to create
                    // a proper AVCapturePhoto object with the spoofed image data
                    NSError *error = [NSError errorWithDomain:@"LiveContainerCameraSpoof" 
                                                         code:0 
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Photo capture completed with spoofed content"}];
                    [delegate captureOutput:self didFinishProcessingPhoto:nil error:error];
                });
            }
        });
        return;
    }
    
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}

@end

#pragma mark - Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        NSLog(@"[LC] AVFoundationGuestHooksInit: guestAppInfo = %@", guestAppInfo);
        
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info available");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        NSLog(@"[LC] Camera spoofing enabled: %d", spoofCameraEnabled);
        
        if (!spoofCameraEnabled) {
            return;
        }
        
        // Load configuration
        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
        spoofCameraLoop = [guestAppInfo[@"spoofCameraLoop"] boolValue];
        
        NSLog(@"[LC] Camera spoofing configuration:");
        NSLog(@"[LC] - Type: %@", spoofCameraType);
        NSLog(@"[LC] - Image: %@", spoofCameraImagePath);
        NSLog(@"[LC] - Video: %@", spoofCameraVideoPath);
        NSLog(@"[LC] - Loop: %d", spoofCameraLoop);
        
        // Initialize resources
        cameraQueue = dispatch_queue_create("com.livecontainer.cameraspoof", DISPATCH_QUEUE_SERIAL);
        prepareForCameraSpoofing();
        
        // Hook AVCaptureSession
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            NSLog(@"[LC] Hooking AVCaptureSession methods");
            
            swizzle(captureSessionClass, @selector(startRunning), @selector(lc_startRunning));
            swizzle(captureSessionClass, @selector(stopRunning), @selector(lc_stopRunning));
            swizzle(captureSessionClass, @selector(addInput:error:), @selector(lc_addInput:error:));
            swizzle(captureSessionClass, @selector(addOutput:), @selector(lc_addOutput:));
            swizzle(captureSessionClass, @selector(canAddInput:), @selector(lc_canAddInput:));
            swizzle(captureSessionClass, @selector(canAddOutput:), @selector(lc_canAddOutput:));
        }
        
        // Hook AVCaptureStillImageOutput
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            NSLog(@"[LC] Hooking AVCaptureStillImageOutput methods");
            swizzle(stillImageOutputClass, 
                   @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                   @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        }
        
        // Hook AVCapturePhotoOutput (iOS 10+)
        Class photoOutputClass = NSClassFromString(@"AVCapturePhotoOutput");
        if (photoOutputClass) {
            NSLog(@"[LC] Hooking AVCapturePhotoOutput methods");
            swizzle(photoOutputClass,
                   @selector(capturePhotoWithSettings:delegate:),
                   @selector(lc_capturePhotoWithSettings:delegate:));
        }
        
        NSLog(@"[LC] Camera spoofing hooks initialized successfully");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in AVFoundationGuestHooksInit: %@", exception);
    }
}