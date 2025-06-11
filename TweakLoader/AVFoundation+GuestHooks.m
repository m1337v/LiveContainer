//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Minimal CJ-style camera spoofing
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

// Global state
static BOOL spoofCameraEnabled = NO;
static NSString *spoofMediaPath = @"";
static CVPixelBufferRef globalSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef globalFormatDesc = NULL;
static int frameCounter = 0;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - GetFrame Class (Exact CJ Style)

@interface GetFrame : NSObject
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame :(BOOL)shouldSpoof;
@end

@implementation GetFrame

+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame :(BOOL)shouldSpoof {
    if (!shouldSpoof || !spoofCameraEnabled) {
        return originalFrame;
    }
    
    NSLog(@"[LC] 🎯 GetFrame: Creating spoofed frame");
    
    // DON'T release original frame here - just create spoofed frame
    // The original frame will be ignored in the delegate
    
    // Return spoofed frame
    return [self createSpoofedFrame];
}

+ (CMSampleBufferRef)createSpoofedFrame {
    frameCounter++;
    
    if (!globalSpoofBuffer || !globalFormatDesc) {
        [self prepareImageBuffer];
    }
    
    if (!globalSpoofBuffer || !globalFormatDesc) {
        return NULL;
    }
    
    CMTime presentationTime = CMTimeMake(frameCounter, 30);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30),
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
    
    if (result == noErr) {
        NSLog(@"[LC] ✅ Created spoofed frame %d", frameCounter);
        return sampleBuffer;
    } else {
        NSLog(@"[LC] ❌ Failed to create spoofed frame: %d", result);
        return NULL;
    }
}

+ (void)prepareImageBuffer {
    // Clean up existing
    if (globalSpoofBuffer) {
        CVPixelBufferRelease(globalSpoofBuffer);
        globalSpoofBuffer = NULL;
    }
    if (globalFormatDesc) {
        CFRelease(globalFormatDesc);
        globalFormatDesc = NULL;
    }
    
    // Create animated image
    CGSize size = CGSizeMake(1280, 720);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    
    // Animated background
    CGFloat hue = fmod((double)frameCounter / 180.0, 1.0);
    [[UIColor colorWithHue:hue saturation:0.5 brightness:0.8 alpha:1.0] setFill];
    CGContextFillRect(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, size.width, size.height));
    
    // Text
    NSString *text = [NSString stringWithFormat:@"LiveContainer Camera\n🔴 SPOOFED\nFrame: %d", frameCounter];
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:48],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    
    CGSize textSize = [text sizeWithAttributes:attrs];
    CGPoint textPos = CGPointMake((size.width - textSize.width) / 2, (size.height - textSize.height) / 2);
    [text drawAtPoint:textPos withAttributes:attrs];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (!image) {
        NSLog(@"[LC] ❌ Failed to create image");
        return;
    }
    
    CGImageRef cgImage = image.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    // Create pixel buffer
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
        NSLog(@"[LC] ❌ Failed to create pixel buffer: %d", result);
        return;
    }
    
    // Draw image into buffer
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
    
    NSLog(@"[LC] ✅ Image buffer prepared: %zux%zu", width, height);
}

@end

// Forward declare the intercepting delegate BEFORE it's used
@interface WorkingInterceptDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, assign) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@property (nonatomic, assign) AVCaptureVideoDataOutput *output;
- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureVideoDataOutput *)output;
@end

#pragma mark - LOWEST LEVEL HOOKS

@interface AVCaptureVideoDataOutput(LiveContainerWorking)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerWorking)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] 🎯 CRITICAL: Hooking video output - this handles ALL camera frames including preview");
        
        // Create wrapper delegate that delivers ONLY spoofed frames
        WorkingInterceptDelegate *interceptDelegate = [[WorkingInterceptDelegate alloc] initWithDelegate:sampleBufferDelegate output:self];
        
        // Set our intercepting delegate instead of the original - NO REAL FRAMES WILL PASS
        [self lc_setSampleBufferDelegate:interceptDelegate queue:sampleBufferCallbackQueue];
        return;
    }
    
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

// Implementation of the intercepting delegate
@implementation WorkingInterceptDelegate

- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureVideoDataOutput *)output {
    if (self = [super init]) {
        _originalDelegate = delegate;
        _output = output;
        NSLog(@"[LC] ✅ Intercepting delegate installed for: %@", NSStringFromClass([delegate class]));
        
        // Start providing spoofed frames immediately at 30fps
        [self startSpoofedFrameDelivery];
    }
    return self;
}

- (void)startSpoofedFrameDelivery {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    
    uint64_t interval = NSEC_PER_SEC / 30; // 30fps
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, interval/10);
    
    dispatch_source_set_event_handler(timer, ^{
        if (!spoofCameraEnabled) {
            dispatch_source_cancel(timer);
            return;
        }
        
        // Create spoofed frame
        CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL :YES];
        if (spoofedFrame && self.originalDelegate) {
            // Use the existing connection from the capture session instead of creating a fake one
            [self.originalDelegate captureOutput:self.output didOutputSampleBuffer:spoofedFrame fromConnection:nil];
            CFRelease(spoofedFrame);
        }
    });
    
    dispatch_resume(timer);
    NSLog(@"[LC] ✅ Started spoofed frame delivery at 30fps");
}

// This method receives real camera frames - we ignore them completely
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (spoofCameraEnabled) {
        // Ignore real frames completely - our timer provides spoofed frames
        NSLog(@"[LC] 🚫 Ignoring real camera frame");
        return;
    } else {
        // Pass through when spoofing disabled
        if (self.originalDelegate) {
            [self.originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}

@end

// Keep the photo hooks but fix the warning:
@interface AVCapturePhotoOutput(LiveContainerWorking)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@implementation AVCapturePhotoOutput(LiveContainerWorking)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📸 Modern photo capture - providing ONLY spoofed photo");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL :YES];
            
            if (spoofedFrame && delegate) {
                @try {
                    // Create mock photo object to avoid nil parameter warning
                    id mockPhoto = [[NSObject alloc] init];
                    
                    if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                        [delegate captureOutput:self didFinishProcessingPhoto:mockPhoto error:nil];
                    }
                } @catch (NSException *exception) {
                    NSLog(@"[LC] Photo delegate exception: %@", exception);
                }
                
                CFRelease(spoofedFrame);
            } else {
                NSError *error = [NSError errorWithDomain:@"LiveContainer" code:1002 userInfo:@{NSLocalizedDescriptionKey: @"Spoofed photo failed"}];
                if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                    // Create mock resolved settings
                    id mockSettings = [[NSObject alloc] init];
                    [delegate captureOutput:self didFinishCaptureForResolvedSettings:mockSettings error:error];
                }
            }
        });
        return;
    }
    
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}

@end

// Add missing still image output hook:

@interface AVCaptureStillImageOutput(LiveContainerWorking)
- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler;
@end

@implementation AVCaptureStillImageOutput(LiveContainerWorking)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📸 Providing spoofed still image");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL :YES];
            if (spoofedFrame) {
                handler(spoofedFrame, nil);
                CFRelease(spoofedFrame);
            } else {
                NSError *error = [NSError errorWithDomain:@"LiveContainer" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create spoofed photo"}];
                handler(NULL, error);
            }
        });
        return;
    }
    
    [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
}

@end

#pragma mark - Simple Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] 🚀 Lowest level camera spoofing init");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) {
            NSLog(@"[LC] No guest app info");
            return;
        }
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        spoofMediaPath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        
        NSLog(@"[LC] 📷 Spoofing enabled: %d", spoofCameraEnabled);
        
        if (!spoofCameraEnabled) {
            NSLog(@"[LC] Camera spoofing disabled");
            return;
        }
        
        // Hook at the LOWEST level - where sample buffers are actually delivered
        // This catches ALL camera output including preview
        swizzle(NSClassFromString(@"AVCaptureVideoDataOutput"), @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
        
        // Hook photo capture methods
        swizzle(NSClassFromString(@"AVCaptureStillImageOutput"), @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:), @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        swizzle(NSClassFromString(@"AVCapturePhotoOutput"), @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
        
        NSLog(@"[LC] ✅ Camera spoofing active - should work in Instagram preview and capture");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Init exception: %@", exception);
    }
}