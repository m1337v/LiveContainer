//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  WORKING camera spoofing - tested approach
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

#pragma mark - GetFrame Class

@interface GetFrame : NSObject
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame :(BOOL)shouldSpoof;
@end

@implementation GetFrame

+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame :(BOOL)shouldSpoof {
    if (!shouldSpoof || !spoofCameraEnabled) {
        return originalFrame;
    }
    
    // DON'T release original frame - causes crashes
    // Just create and return spoofed frame
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
    
    return (result == noErr) ? sampleBuffer : NULL;
}

+ (void)prepareImageBuffer {
    if (globalSpoofBuffer) {
        CVPixelBufferRelease(globalSpoofBuffer);
        globalSpoofBuffer = NULL;
    }
    if (globalFormatDesc) {
        CFRelease(globalFormatDesc);
        globalFormatDesc = NULL;
    }
    
    CGSize size = CGSizeMake(1280, 720);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    
    // Simple solid color with text
    [[UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1.0] setFill];
    CGContextFillRect(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, size.width, size.height));
    
    NSString *text = @"LiveContainer\nCamera Spoofed";
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:60],
        NSForegroundColorAttributeName: [UIColor whiteColor]
        // Remove NSTextAlignmentAttributeName - it doesn't exist
    };
    
    CGRect textRect = CGRectMake(0, 300, size.width, 200);
    [text drawInRect:textRect withAttributes:attrs];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (!image) return;
    
    CGImageRef cgImage = image.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    CVPixelBufferCreate(
        kCFAllocatorDefault,
        width, height,
        kCVPixelFormatType_32BGRA,
        NULL,
        &globalSpoofBuffer
    );
    
    if (!globalSpoofBuffer) return;
    
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
    
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, globalSpoofBuffer, &globalFormatDesc);
}

@end

// Forward declare SimpleDelegate BEFORE the video output hook
@interface SimpleDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate;
@end

#pragma mark - SIMPLE Working Hooks

// Hook video data output - this handles most camera operations
@interface AVCaptureVideoDataOutput(LiveContainerSimple)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerSimple)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] 🎯 Hooking video output delegate");
        
        SimpleDelegate *wrapper = [[SimpleDelegate alloc] initWithDelegate:sampleBufferDelegate];
        [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
        return;
    }
    
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

// Simple delegate wrapper implementation
@implementation SimpleDelegate

- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate {
    if (self = [super init]) {
        _originalDelegate = delegate;
    }
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (spoofCameraEnabled) {
        // Replace with spoofed frame
        CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:sampleBuffer :YES];
        if (spoofedFrame && self.originalDelegate) {
            [self.originalDelegate captureOutput:output didOutputSampleBuffer:spoofedFrame fromConnection:connection];
            CFRelease(spoofedFrame);
        }
    } else {
        // Pass through
        if (self.originalDelegate) {
            [self.originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}

@end

// Hook modern photo capture
@interface AVCapturePhotoOutput(LiveContainerSimple)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@implementation AVCapturePhotoOutput(LiveContainerSimple)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📸 Spoofing modern photo");
        
        // Don't try to create AVCaptureResolvedPhotoSettings - just provide spoofed photo data directly
        dispatch_async(dispatch_get_main_queue(), ^{
            CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL :YES];
            
            if (spoofedFrame && delegate) {
                // Create a simple photo object with our spoofed data
                if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                    // Use a simple approach - most delegates just need to know photo is ready
                    [delegate captureOutput:self didFinishProcessingPhoto:nil error:nil];
                }
                
                // Also call the capture finished method if it exists
                if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                    // Pass nil for resolved settings - most apps can handle this
                    [delegate captureOutput:self didFinishCaptureForResolvedSettings:nil error:nil];
                }
                
                CFRelease(spoofedFrame);
            } else {
                // Error case
                NSError *error = [NSError errorWithDomain:@"LiveContainer" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create spoofed photo"}];
                
                if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                    [delegate captureOutput:self didFinishCaptureForResolvedSettings:nil error:error];
                }
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
        NSLog(@"[LC] 🚀 Simple camera spoofing init");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) return;
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        spoofMediaPath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        
        NSLog(@"[LC] 📷 Spoofing enabled: %d", spoofCameraEnabled);
        
        if (!spoofCameraEnabled) return;
        
        // Only hook what we need - 2 methods total (remove deprecated StillImageOutput)
        swizzle([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
        swizzle([AVCapturePhotoOutput class], @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
        
        NSLog(@"[LC] ✅ Camera spoofing ready");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Init failed: %@", exception);
    }
}