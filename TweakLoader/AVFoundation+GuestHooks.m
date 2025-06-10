//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Universal camera spoofing based on CJ approach
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraImagePath = @"";
static NSString *spoofCameraVideoPath = @"";
static NSString *spoofCameraType = @"image";
static BOOL spoofCameraLoop = YES;

static UIImage *spoofImage = nil;
static AVAsset *spoofVideoAsset = nil;
static AVAssetReader *currentVideoReader = nil;
static AVAssetReaderTrackOutput *videoTrackOutput = nil;

// Core spoofing resources
static CVPixelBufferRef globalSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef globalFormatDesc = NULL;

// Forward declarations
static void hookCaptureOutputDelegate(void);
static CMSampleBufferRef getNextVideoFrame(void);
static CMSampleBufferRef getLoopedImageFrame(void);
static CMSampleBufferRef createImageSampleBuffer(void);
static void setupVideoReader(void);
static void prepareImageResources(void);

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - Core Frame Generation (No Original Camera Data)

// Generate ONLY spoofed frames - never use original camera data
// Simplified: Convert everything to video streams (like fd)
static CMSampleBufferRef getCurrentSpoofFrame(void) {
    if (!spoofCameraEnabled) {
        return NULL;
    }
    
    // ALWAYS return video frames - even for pictures
    if ([spoofCameraType isEqualToString:@"video"] && spoofVideoAsset) {
        return getNextVideoFrame();
    } else {
        // For "images" - create a looped video from the image
        return getLoopedImageFrame();
    }
}

static CMSampleBufferRef getNextVideoFrame(void) {
    if (!currentVideoReader || !videoTrackOutput) {
        setupVideoReader();
        if (!currentVideoReader || !videoTrackOutput) {
            return createImageSampleBuffer(); // Fallback to image
        }
    }
    
    if (currentVideoReader.status == AVAssetReaderStatusReading) {
        CMSampleBufferRef sampleBuffer = [videoTrackOutput copyNextSampleBuffer];
        
        if (sampleBuffer) {
            return sampleBuffer;
        } else {
            // Video finished, restart if looping
            if (spoofCameraLoop) {
                NSLog(@"[LC] Video finished, restarting for loop");
                setupVideoReader();
                return getNextVideoFrame();
            }
            return createImageSampleBuffer(); // Fallback
        }
    }
    
    return createImageSampleBuffer(); // Fallback
}

// Convert static image to looped video frames (fd approach)
static CMSampleBufferRef getLoopedImageFrame(void) {
    if (!globalSpoofBuffer || !globalFormatDesc) {
        return NULL;
    }
    
    // Create timestamp for smooth video loop
    static double frameTime = 0.0;
    frameTime += 1.0/30.0; // 30fps
    
    CMTime presentationTime = CMTimeMakeWithSeconds(frameTime, 1000000000);
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
    
    if (result != noErr) {
        NSLog(@"[LC] Failed to create looped image frame: %d", result);
        return NULL;
    }
    
    return sampleBuffer;
}

static CMSampleBufferRef createImageSampleBuffer(void) {
    if (!globalSpoofBuffer || !globalFormatDesc) {
        return NULL;
    }
    
    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000000);
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
    
    if (result != noErr) {
        NSLog(@"[LC] Failed to create image sample buffer: %d", result);
        return NULL;
    }
    
    return sampleBuffer;
}

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
    
    if (error || !currentVideoReader) {
        NSLog(@"[LC] Failed to create video reader: %@", error.localizedDescription);
        return;
    }
    
    NSArray *videoTracks = [spoofVideoAsset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        NSLog(@"[LC] No video tracks found");
        return;
    }
    
    AVAssetTrack *videoTrack = videoTracks.firstObject;
    
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
    
    if (![currentVideoReader startReading]) {
        NSLog(@"[LC] Failed to start video reader");
        return;
    }
    
    NSLog(@"[LC] Video reader setup completed successfully");
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
    
    // Use provided image or create default
    UIImage *imageToUse = spoofImage;
    if (!imageToUse) {
        // Create a simple test image
        CGSize size = CGSizeMake(1280, 720);
        UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
        
        [[UIColor blueColor] setFill];
        UIRectFill(CGRectMake(0, 0, size.width, size.height));
        
        NSString *text = @"LiveContainer\nCamera Spoofing";
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:48],
            NSForegroundColorAttributeName: [UIColor whiteColor]
        };
        
        CGRect textRect = CGRectMake(50, size.height/2 - 50, size.width - 100, 100);
        [text drawInRect:textRect withAttributes:attrs];
        
        imageToUse = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    if (!imageToUse) {
        NSLog(@"[LC] Failed to create spoof image");
        return;
    }
    
    CGImageRef cgImage = imageToUse.CGImage;
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
        NSLog(@"[LC] Failed to create pixel buffer: %d", result);
        return;
    }
    
    // Draw image into pixel buffer
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
    
    NSLog(@"[LC] Image resources prepared successfully: %zux%zu", width, height);
}

#pragma mark - Universal Camera Prevention

// Prevent real camera capture at the AVCaptureVideoDataOutput level
@interface AVCaptureVideoDataOutput(LiveContainerNoRealCapture)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@implementation AVCaptureVideoDataOutput(LiveContainerNoRealCapture)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] Preventing real camera capture - providing ONLY spoofed video stream");
        
        // Don't call original method - we completely replace camera input
        dispatch_queue_t spoofQueue = sampleBufferCallbackQueue ?: dispatch_get_main_queue();
        
        // Create continuous spoofed frame delivery (30fps)
        NSTimer *spoofTimer = [NSTimer timerWithTimeInterval:1.0/30.0 repeats:YES block:^(NSTimer *timer) {
            if (!spoofCameraEnabled) {
                [timer invalidate];
                return;
            }
            
            // Generate spoofed frame
            CMSampleBufferRef spoofedFrame = getCurrentSpoofFrame();
            if (spoofedFrame && sampleBufferDelegate) {
                dispatch_async(spoofQueue, ^{
                    @try {
                        // Create connection
                        AVCaptureConnection *connection = [[AVCaptureConnection alloc] initWithInputPorts:@[] output:self];
                        
                        // Deliver ONLY spoofed frames - app never sees real camera
                        [sampleBufferDelegate captureOutput:self didOutputSampleBuffer:spoofedFrame fromConnection:connection];
                        
                    } @catch (NSException *exception) {
                        NSLog(@"[LC] Exception delivering spoofed frame: %@", exception);
                    } @finally {
                        CFRelease(spoofedFrame);
                    }
                });
            }
        }];
        
        // Start spoofed frame delivery
        [[NSRunLoop mainRunLoop] addTimer:spoofTimer forMode:NSDefaultRunLoopMode];
        NSLog(@"[LC] Started spoofed video stream at 30fps");
        return;
    }
    
    // If spoofing disabled, allow normal camera operation
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

#pragma mark - Universal Delegate Hooking (CJ Style)

// Hook ALL classes that implement the video delegate method
static void hookCaptureOutputDelegate(void) {
    // Get all loaded classes and find ones that implement the delegate method
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    
    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        
        // Look for the delegate method on ANY class
        Method method = class_getInstanceMethod(cls, @selector(captureOutput:didOutputSampleBuffer:fromConnection:));
        if (method) {
            NSString *className = NSStringFromClass(cls);
            NSLog(@"[LC] Found universal video delegate on: %@", className);
            
            // Replace the method implementation
            IMP originalIMP = method_getImplementation(method);
            IMP newIMP = imp_implementationWithBlock(^(id self, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) {
                
                // Check if this is video output and spoofing is enabled
                if (spoofCameraEnabled && [output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                    NSLog(@"[LC] Blocking real camera frame from %@ - providing spoofed frame", className);
                    
                    // NEVER use the original sampleBuffer - always generate spoofed frame
                    CMSampleBufferRef spoofedFrame = getCurrentSpoofFrame();
                    if (spoofedFrame) {
                        // Call original method with ONLY spoofed frame
                        ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))originalIMP)(self, @selector(captureOutput:didOutputSampleBuffer:fromConnection:), output, spoofedFrame, connection);
                        CFRelease(spoofedFrame);
                        return; // Never process real camera data
                    }
                }
                
                // For non-video outputs or when spoofing disabled, allow normal operation
                ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))originalIMP)(self, @selector(captureOutput:didOutputSampleBuffer:fromConnection:), output, sampleBuffer, connection);
            });
            
            method_setImplementation(method, newIMP);
            NSLog(@"[LC] Hooked universal video delegate on %@", className);
        }
    }
    
    free(classes);
}

#pragma mark - Initialization

// Simplified initialization
void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Universal video spoofing (fd approach)");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) return;
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraLoop = YES; // Always loop
        
        if (!spoofCameraEnabled) return;
        
        // Load video if specified
        if ([spoofCameraType isEqualToString:@"video"]) {
            spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
            if (spoofCameraVideoPath.length > 0) {
                NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
                spoofVideoAsset = [AVAsset assetWithURL:videoURL];
                
                if (spoofVideoAsset) {
                    setupVideoReader();
                    NSLog(@"[LC] Loaded video for streaming");
                } else {
                    spoofCameraType = @"image"; // Fallback
                }
            } else {
                spoofCameraType = @"image";
            }
        }
        
        // Load image (will be converted to looped video)
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        if (spoofCameraImagePath.length > 0) {
            spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
            NSLog(@"[LC] Loaded image - will loop as video");
        }
        
        // Prepare resources
        prepareImageResources();
        
        // Only hook video data output - everything is video
        Class videoDataOutputClass = NSClassFromString(@"AVCaptureVideoDataOutput");
        if (videoDataOutputClass) {
            swizzle(videoDataOutputClass, 
                   @selector(setSampleBufferDelegate:queue:), 
                   @selector(lc_setSampleBufferDelegate:queue:));
        }
        
        // Universal delegate hooking for any missed cases
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (spoofCameraEnabled) {
                hookCaptureOutputDelegate();
            }
        });
        
        NSLog(@"[LC] Universal video spoofing initialized - pictures converted to looped video");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in init: %@", exception);
    }
}