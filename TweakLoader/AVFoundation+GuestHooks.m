//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Minimal camera spoofing implementation
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

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Utility Functions

static UIImage *createDefaultTestImage(void) {
    CGSize size = CGSizeMake(640, 480);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Simple solid color background
    [[UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0] setFill];
    CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
    
    // Add simple text
    NSString *text = @"LiveContainer\nCamera Spoof";
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:32],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    
    CGSize textSize = [text sizeWithAttributes:attributes];
    CGRect textRect = CGRectMake(
        (size.width - textSize.width) / 2,
        (size.height - textSize.height) / 2,
        textSize.width,
        textSize.height
    );
    
    [text drawInRect:textRect withAttributes:attributes];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

static CMSampleBufferRef createSampleBufferFromImage(UIImage *image) {
    if (!image) return NULL;
    
    // Create pixel buffer from image
    CGImageRef cgImage = image.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn result = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        NULL,
        &pixelBuffer
    );
    
    if (result != kCVReturnSuccess || !pixelBuffer) {
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        baseAddress,
        width,
        height,
        8,
        bytesPerRow,
        colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    );
    
    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
        CGContextRelease(context);
    }
    
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    // Create format description
    CMVideoFormatDescriptionRef formatDescription = NULL;
    result = CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        &formatDescription
    );
    
    if (result != noErr) {
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }
    
    // Create timing info
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = presentationTime,
        .decodeTimeStamp = kCMTimeInvalid
    };
    
    // Create sample buffer
    CMSampleBufferRef sampleBuffer = NULL;
    result = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        formatDescription,
        &timingInfo,
        &sampleBuffer
    );
    
    CVPixelBufferRelease(pixelBuffer);
    CFRelease(formatDescription);
    
    return sampleBuffer;
}

#pragma mark - AVCaptureSession Hooks

@interface AVCaptureSession(LiveContainerHooks)
- (void)lc_startRunning;
- (void)lc_addInput:(AVCaptureInput *)input;
@end

@implementation AVCaptureSession(LiveContainerHooks)

- (void)lc_startRunning {
    NSLog(@"[LC] AVCaptureSession startRunning - spoofing enabled: %d", spoofCameraEnabled);
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Camera spoofing active - blocking real camera");
        // Don't call original to prevent real camera access
        return;
    }
    
    [self lc_startRunning];
}

- (void)lc_addInput:(AVCaptureInput *)input {
    NSLog(@"[LC] AVCaptureSession addInput: %@", input);
    
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
            NSLog(@"[LC] Blocking camera input for spoofing");
            return; // Block camera input
        }
    }
    
    [self lc_addInput:input];
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
    NSLog(@"[LC] Still image capture requested");
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Returning spoofed still image");
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *imageToUse = spoofImage ?: createDefaultTestImage();
            CMSampleBufferRef sampleBuffer = createSampleBufferFromImage(imageToUse);
            
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
        NSLog(@"[LC] AVFoundationGuestHooksInit starting");
        
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
        
        // Hook AVCaptureSession
        Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
        if (captureSessionClass) {
            NSLog(@"[LC] Hooking AVCaptureSession methods");
            swizzle(captureSessionClass, @selector(startRunning), @selector(lc_startRunning));
            swizzle(captureSessionClass, @selector(addInput:), @selector(lc_addInput:));
        }
        
        // Hook AVCaptureStillImageOutput
        Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
        if (stillImageOutputClass) {
            NSLog(@"[LC] Hooking AVCaptureStillImageOutput methods");
            swizzle(stillImageOutputClass, 
                   @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                   @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        }
        
        NSLog(@"[LC] Camera spoofing hooks initialized successfully");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in AVFoundationGuestHooksInit: %@", exception);
    }
}