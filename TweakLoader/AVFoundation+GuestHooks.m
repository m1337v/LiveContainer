//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Simple CJ-style camera spoofing - Hook at sample buffer level only
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
static NSString *spoofMediaType = @"image";
static BOOL spoofLoop = YES;

// Core resources
static CVPixelBufferRef globalSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef globalFormatDesc = NULL;
static AVAsset *spoofAsset = nil;
static AVAssetReader *assetReader = nil;
static AVAssetReaderTrackOutput *videoOutput = nil;

// Frame counter
static int frameCounter = 0;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

#pragma mark - GetFrame Class (CJ Style)

@interface GetFrame : NSObject
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame :(BOOL)shouldSpoof;
@end

@implementation GetFrame

+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame :(BOOL)shouldSpoof {
    if (!shouldSpoof || !spoofCameraEnabled) {
        return originalFrame;
    }
    
    NSLog(@"[LC] 🎯 GetFrame: BLOCKING real camera frame, providing ONLY spoofed frame");
    
    // CRITICAL: Immediately release original frame - real camera data NEVER gets through
    if (originalFrame) {
        CFRelease(originalFrame);
    }
    
    // Return ONLY spoofed frame
    return [self createSpoofedFrame];
}

+ (CMSampleBufferRef)createSpoofedFrame {
    frameCounter++;
    
    if ([spoofMediaType isEqualToString:@"video"] && spoofAsset) {
        CMSampleBufferRef videoFrame = [self getVideoFrame];
        if (videoFrame) {
            return videoFrame;
        }
    }
    
    return [self getImageFrame];
}

+ (CMSampleBufferRef)getVideoFrame {
    if (!assetReader || !videoOutput) {
        [self setupVideoReader];
    }
    
    if (assetReader.status == AVAssetReaderStatusReading) {
        CMSampleBufferRef sampleBuffer = [videoOutput copyNextSampleBuffer];
        if (sampleBuffer) {
            return sampleBuffer;
        }
        
        if (spoofLoop) {
            [self setupVideoReader];
            if (assetReader.status == AVAssetReaderStatusReading) {
                return [videoOutput copyNextSampleBuffer];
            }
        }
    }
    
    return NULL;
}

+ (CMSampleBufferRef)getImageFrame {
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

+ (void)setupVideoReader {
    if (!spoofAsset) return;
    
    if (assetReader) {
        [assetReader cancelReading];
        assetReader = nil;
        videoOutput = nil;
    }
    
    NSError *error = nil;
    assetReader = [[AVAssetReader alloc] initWithAsset:spoofAsset error:&error];
    if (error || !assetReader) return;
    
    NSArray *videoTracks = [spoofAsset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) return;
    
    videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTracks.firstObject 
                                                   outputSettings:@{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    
    if ([assetReader canAddOutput:videoOutput]) {
        [assetReader addOutput:videoOutput];
        [assetReader startReading];
    }
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
    
    UIImage *image = nil;
    if (spoofMediaPath.length > 0) {
        image = [UIImage imageWithContentsOfFile:spoofMediaPath];
    }
    
    if (!image) {
        CGSize size = CGSizeMake(1280, 720);
        UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
        
        CGFloat hue = fmod((double)frameCounter / 180.0, 1.0);
        [[UIColor colorWithHue:hue saturation:0.3 brightness:0.9 alpha:1.0] setFill];
        CGContextFillRect(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, size.width, size.height));
        
        NSString *text = [NSString stringWithFormat:@"LiveContainer\n🔴 Camera Spoofing\nFrame: %d", frameCounter];
        [text drawInRect:CGRectMake(50, 250, size.width-100, 220) 
          withAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:48],
                          NSForegroundColorAttributeName: [UIColor whiteColor]}];
        
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    if (!image) return;
    
    CGImageRef cgImage = image.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                       (__bridge CFDictionaryRef)@{(NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES},
                       &globalSpoofBuffer);
    
    if (!globalSpoofBuffer) return;
    
    CVPixelBufferLockBaseAddress(globalSpoofBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(globalSpoofBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(globalSpoofBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace,
                                               kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
        CGContextRelease(context);
    }
    
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(globalSpoofBuffer, 0);
    
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, globalSpoofBuffer, &globalFormatDesc);
}

@end

#pragma mark - LOWEST LEVEL HOOKS - Sample Buffer Interception Only

// Hook video frames at the delegate level (where apps receive frames)
@interface AVCaptureVideoDataOutput(LiveContainerLowest)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

// Custom delegate that delivers ONLY spoofed frames, never real camera frames
@interface InterceptingVideoDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, assign) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@property (nonatomic, assign) AVCaptureVideoDataOutput *output;
- (instancetype)initWithOriginalDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureVideoDataOutput *)output;
@end

@implementation InterceptingVideoDelegate

- (instancetype)initWithOriginalDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureVideoDataOutput *)output {
    if (self = [super init]) {
        _originalDelegate = delegate;
        _output = output;
    }
    return self;
}

// CRITICAL: This method receives ALL camera frames and replaces them with spoofed frames
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (spoofCameraEnabled) {
        // CRITICAL: Use GetFrame to BLOCK real frame and provide ONLY spoofed frame
        CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:sampleBuffer :YES];
        
        if (spoofedFrame && self.originalDelegate) {
            [self.originalDelegate captureOutput:output didOutputSampleBuffer:spoofedFrame fromConnection:connection];
            CFRelease(spoofedFrame);
        }
        // Real frame is already released in GetFrame - app NEVER sees it
    } else {
        // Pass through real frame only when spoofing disabled
        if (self.originalDelegate) {
            [self.originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if ([self.originalDelegate respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)]) {
        [self.originalDelegate captureOutput:output didDropSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

@end

@implementation AVCaptureVideoDataOutput(LiveContainerLowest)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] 🎯 LOWEST: Replacing video delegate - ONLY spoofed frames will be delivered");
        
        // Create intercepting delegate that ONLY delivers spoofed frames
        InterceptingVideoDelegate *interceptDelegate = [[InterceptingVideoDelegate alloc] initWithOriginalDelegate:sampleBufferDelegate output:self];
        
        [self lc_setSampleBufferDelegate:interceptDelegate queue:sampleBufferCallbackQueue];
        return;
    }
    
    [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

@end

// Hook photo capture - deliver ONLY spoofed photos
@interface AVCaptureStillImageOutput(LiveContainerLowest)
- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler;
@end

@implementation AVCaptureStillImageOutput(LiveContainerLowest)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📸 LOWEST: Providing ONLY spoofed photo");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Get spoofed frame instead of taking real photo
            CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL :YES];
            if (spoofedFrame) {
                handler(spoofedFrame, nil);
                CFRelease(spoofedFrame);
            } else {
                NSError *error = [NSError errorWithDomain:@"LiveContainer" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Spoofed photo failed"}];
                handler(NULL, error);
            }
        });
        return;
    }
    
    [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
}

@end

// Hook modern photo capture - deliver ONLY spoofed photos
@interface AVCapturePhotoOutput(LiveContainerLowest)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@implementation AVCapturePhotoOutput(LiveContainerLowest)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📸 LOWEST: Providing ONLY spoofed modern photo");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL :YES];
            
            if (spoofedFrame && delegate) {
                @try {
                    // Create basic resolved settings to avoid null parameter warnings
                    AVCaptureResolvedPhotoSettings *basicSettings = (AVCaptureResolvedPhotoSettings *)class_createInstance([AVCaptureResolvedPhotoSettings class], 0);
                    
                    if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                        [delegate captureOutput:self didFinishProcessingPhoto:nil error:nil];
                    }
                    
                    if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                        [delegate captureOutput:self didFinishCaptureForResolvedSettings:basicSettings error:nil];
                    }
                } @catch (NSException *exception) {
                    NSLog(@"[LC] Photo delegate exception: %@", exception);
                }
                
                CFRelease(spoofedFrame);
            } else {
                AVCaptureResolvedPhotoSettings *errorSettings = (AVCaptureResolvedPhotoSettings *)class_createInstance([AVCaptureResolvedPhotoSettings class], 0);
                NSError *error = [NSError errorWithDomain:@"LiveContainer" code:1002 userInfo:@{NSLocalizedDescriptionKey: @"Spoofed photo failed"}];
                if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                    [delegate captureOutput:self didFinishCaptureForResolvedSettings:errorSettings error:error];
                }
            }
        });
        return;
    }
    
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}

@end

#pragma mark - Simple Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] 🚀 LOWEST LEVEL camera spoofing - ONLY spoofed frames will be delivered");
        
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        if (!guestAppInfo) return;
        
        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        spoofMediaType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofLoop = guestAppInfo[@"spoofCameraLoop"] ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;
        
        NSLog(@"[LC] 📷 Config - enabled: %d, type: %@", spoofCameraEnabled, spoofMediaType);
        
        if (!spoofCameraEnabled) return;
        
        // Load content
        if ([spoofMediaType isEqualToString:@"video"]) {
            spoofMediaPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
            if (spoofMediaPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:spoofMediaPath]) {
                spoofAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:spoofMediaPath]];
                if (!spoofAsset.isPlayable) {
                    spoofMediaType = @"image";
                }
            } else {
                spoofMediaType = @"image";
            }
        } else {
            spoofMediaPath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        }
        
        // Install only the essential 3 hooks
        swizzle(NSClassFromString(@"AVCaptureVideoDataOutput"), @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
        swizzle(NSClassFromString(@"AVCaptureStillImageOutput"), @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:), @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
        swizzle(NSClassFromString(@"AVCapturePhotoOutput"), @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
        
        NSLog(@"[LC] ✅ LOWEST LEVEL camera spoofing active");
        NSLog(@"[LC] 🚫 Real camera frames: COMPLETELY BLOCKED");
        NSLog(@"[LC] 🎯 Spoofed frames: ONLY source of camera data");
        NSLog(@"[LC] 🔥 Ready for Instagram/TikTok/Snapchat");
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Init exception: %@", exception);
    }
}