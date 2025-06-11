//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Simple ground-up camera spoofing (image/video)
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import "../LiveContainer/Tweaks/Tweaks.h" // Assumed to provide swizzle function

// --- Global State for Spoofing ---
static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraType = @"image"; // "image" or "video"
static NSString *spoofCameraImagePath = @"";
static NSString *spoofCameraVideoPath = @"";
static BOOL spoofCameraLoop = YES;

// Image Spoofing Resources
static CVPixelBufferRef staticImageSpoofBuffer = NULL;
static CMVideoFormatDescriptionRef staticImageFormatDesc = NULL;

// Video Spoofing Resources
static AVPlayer *videoSpoofPlayer = nil;
static AVPlayerItemVideoOutput *videoSpoofPlayerOutput = nil;
static dispatch_queue_t videoProcessingQueue = NULL;
static BOOL isVideoSetupSuccessfully = NO;
static id playerDidPlayToEndTimeObserver = nil; // Token for notification observer

// --- Helper: NSUserDefaults ---
@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo; // Assumed to be implemented elsewhere
@end

// --- Forward Declarations ---
static void setupImageSpoofingResources(void);
static void setupVideoSpoofingResources(void);
static CMSampleBufferRef createSpoofedSampleBuffer(void);
static void playerItemDidPlayToEndTime(NSNotification *notification);


#pragma mark - GetFrame Logic (Simplified into static functions)

static CMSampleBufferRef createSpoofedSampleBuffer() {
    CVPixelBufferRef currentPixelBuffer = NULL;
    BOOL ownPixelBuffer = NO; // True if we copied/created and need to release currentPixelBuffer

    // Attempt to get video frame if in video mode
    if ([spoofCameraType isEqualToString:@"video"]) {
        if (isVideoSetupSuccessfully) { // Check if video setup was marked as successful
            if (videoSpoofPlayerOutput && videoSpoofPlayer.currentItem && videoSpoofPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay) {
                CMTime playerTime = [videoSpoofPlayer.currentItem currentTime];
                if ([videoSpoofPlayerOutput hasNewPixelBufferForItemTime:playerTime]) {
                    currentPixelBuffer = [videoSpoofPlayerOutput copyPixelBufferForItemTime:playerTime itemTimeForDisplay:NULL];
                    if (currentPixelBuffer) {
                        ownPixelBuffer = YES;
                        // Successfully got video frame, skip image fallback
                         NSLog(@"[LC] Video: Successfully copied pixel buffer for time %lld/%d.", playerTime.value, playerTime.timescale);
                    } else {
                        NSLog(@"[LC] Video: copyPixelBufferForItemTime returned NULL for time %lld/%d.", playerTime.value, playerTime.timescale);
                    }
                } else {
                    NSLog(@"[LC] Video: hasNewPixelBufferForItemTime is NO for time %lld/%d. Player status: %ld, Player rate: %.2f", 
                          playerTime.value, playerTime.timescale, 
                          (long)videoSpoofPlayer.currentItem.status, videoSpoofPlayer.rate);
                }
            } else {
                NSLog(@"[LC] Video: Player/item not ready or output nil. Output: %p, Item: %p, Status: %ld",
                      videoSpoofPlayerOutput,
                      videoSpoofPlayer.currentItem,
                      videoSpoofPlayer.currentItem ? (long)videoSpoofPlayer.currentItem.status : -1L);
            }
        } else {
            NSLog(@"[LC] Video: Mode is video, but isVideoSetupSuccessfully is NO.");
        }
    }

    // Fallback to static image if video frame not obtained or in image mode
    if (!currentPixelBuffer) {
        if (staticImageSpoofBuffer) {
            if ([spoofCameraType isEqualToString:@"video"]) { // Log fallback if it was supposed to be video
                NSLog(@"[LC] Video: Falling back to static image buffer.");
            }
            currentPixelBuffer = staticImageSpoofBuffer; // Use the global static buffer
            CFRetain(currentPixelBuffer); // CMSampleBufferCreateReadyWithImageBuffer consumes a retain count
            ownPixelBuffer = YES;
        } else {
            NSLog(@"[LC] No spoof pixel buffer available (static image buffer is NULL).");
            return NULL;
        }
    }
    
    if (!currentPixelBuffer) { 
        NSLog(@"[LC] CRITICAL: currentPixelBuffer is NULL before format description.");
        return NULL;
    }

    CMVideoFormatDescriptionRef currentFormatDesc = NULL;
    OSStatus formatDescStatus = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, currentPixelBuffer, &currentFormatDesc);

    if (formatDescStatus != noErr) {
        NSLog(@"[LC] Failed to create format description. Status: %d", (int)formatDescStatus);
        if (ownPixelBuffer) CVPixelBufferRelease(currentPixelBuffer);
        return NULL;
    }

    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), NSEC_PER_SEC);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30), // Assume 30 FPS
        .presentationTimeStamp = presentationTime,
        .decodeTimeStamp = kCMTimeInvalid
    };

    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus result = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        currentPixelBuffer,
        currentFormatDesc,
        &timingInfo,
        &sampleBuffer
    );

    if (currentFormatDesc) CFRelease(currentFormatDesc);
    if (ownPixelBuffer) CVPixelBufferRelease(currentPixelBuffer);

    if (result != noErr) {
        NSLog(@"[LC] Failed to create CMSampleBuffer. Status: %d", (int)result);
        return NULL;
    }
    return sampleBuffer; // Caller must release
}

#pragma mark - Resource Setup

static void setupImageSpoofingResources() {
    if (staticImageSpoofBuffer) {
        CVPixelBufferRelease(staticImageSpoofBuffer);
        staticImageSpoofBuffer = NULL;
    }
    if (staticImageFormatDesc) {
        CFRelease(staticImageFormatDesc);
        staticImageFormatDesc = NULL;
    }

    UIImage *image = nil;
    if (spoofCameraImagePath && spoofCameraImagePath.length > 0) {
        image = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
        if (!image) NSLog(@"[LC] Failed to load image from path: %@", spoofCameraImagePath);
    }

    if (!image) { // Create a default image
        CGSize size = CGSizeMake(1280, 720);
        UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
        [[UIColor colorWithRed:0.1 green:0.3 blue:0.8 alpha:1.0] setFill];
        CGContextFillRect(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, size.width, size.height));
        NSString *text = @"LiveContainer\nSpoofed Image";
        NSDictionary *attrs = @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:60], NSForegroundColorAttributeName: [UIColor whiteColor] };
        [text drawInRect:CGRectMake(0, size.height/2 - 60, size.width, 120) withAttributes:attrs];
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSLog(@"[LC] Using default spoof image.");
    } else {
        NSLog(@"[LC] Using image from path: %@", spoofCameraImagePath);
    }
    
    if (!image) {
        NSLog(@"[LC] Failed to create any image for spoofing.");
        return;
    }

    CGImageRef cgImage = image.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);

    NSDictionary *pixelBufferAttributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    CVReturn cvRet = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)pixelBufferAttributes, &staticImageSpoofBuffer);
    if (cvRet != kCVReturnSuccess || !staticImageSpoofBuffer) {
        NSLog(@"[LC] Failed to create CVPixelBuffer for image. Error: %d", cvRet);
        return;
    }

    CVPixelBufferLockBaseAddress(staticImageSpoofBuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(staticImageSpoofBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, width, height, 8, CVPixelBufferGetBytesPerRow(staticImageSpoofBuffer),
                                                 rgbColorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(staticImageSpoofBuffer, 0);

    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, staticImageSpoofBuffer, &staticImageFormatDesc);
    if (!staticImageFormatDesc) {
         NSLog(@"[LC] Failed to create CMVideoFormatDescription for image.");
         CVPixelBufferRelease(staticImageSpoofBuffer);
         staticImageSpoofBuffer = NULL;
    } else {
        NSLog(@"[LC] Image spoofing resources prepared.");
    }
}

static void setupVideoSpoofingResources() {
    if (!spoofCameraVideoPath || spoofCameraVideoPath.length == 0) {
        NSLog(@"[LC] Video path is empty.");
        isVideoSetupSuccessfully = NO;
        return;
    }
    
    NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath]) {
        NSLog(@"[LC] Video file not found at path: %@", spoofCameraVideoPath);
        isVideoSetupSuccessfully = NO;
        return;
    }

    AVURLAsset *asset = [AVURLAsset assetWithURL:videoURL];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (tracks.count == 0) {
        NSLog(@"[LC] No video tracks found in asset: %@", spoofCameraVideoPath);
        isVideoSetupSuccessfully = NO;
        return;
    }

    // Clean up previous player and observer
    if (videoSpoofPlayer) {
        [videoSpoofPlayer pause];
        // Remove previous observer if it exists
        if (playerDidPlayToEndTimeObserver) {
            [[NSNotificationCenter defaultCenter] removeObserver:playerDidPlayToEndTimeObserver];
            playerDidPlayToEndTimeObserver = nil;
        }
        if (videoSpoofPlayer.currentItem) {
            [videoSpoofPlayer.currentItem removeOutput:videoSpoofPlayerOutput];
        }
        videoSpoofPlayer = nil;
        videoSpoofPlayerOutput = nil;
    }

    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
    videoSpoofPlayer = [AVPlayer playerWithPlayerItem:playerItem];

    NSDictionary *pixelBufferAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    videoSpoofPlayerOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];
    
    dispatch_async(videoProcessingQueue, ^{
        while (playerItem.status != AVPlayerItemStatusReadyToPlay) {
            [NSThread sleepForTimeInterval:0.01]; 
            if (playerItem.status == AVPlayerItemStatusFailed) {
                 NSLog(@"[LC] Player item failed to load: %@", playerItem.error);
                 isVideoSetupSuccessfully = NO;
                 return;
            }
        }
        
        if (![playerItem.outputs containsObject:videoSpoofPlayerOutput]) {
            [playerItem addOutput:videoSpoofPlayerOutput];
        }
        
        if (spoofCameraLoop) {
            // Ensure any previous observer is removed before adding a new one
            if (playerDidPlayToEndTimeObserver) {
                [[NSNotificationCenter defaultCenter] removeObserver:playerDidPlayToEndTimeObserver];
                playerDidPlayToEndTimeObserver = nil;
            }
            playerDidPlayToEndTimeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                              object:playerItem
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *note) {
                [videoSpoofPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                    if (finished) [videoSpoofPlayer play];
                }];
            }];
        }
        [videoSpoofPlayer play];
        isVideoSetupSuccessfully = YES;
        NSLog(@"[LC] Video spoofing resources prepared and player started for: %@", spoofCameraVideoPath);
    });
}


#pragma mark - Delegate Wrapper

@interface SimpleSpoofDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@property (nonatomic, assign) AVCaptureOutput *originalOutput; // To pass to original delegate
@end

@implementation SimpleSpoofDelegate
- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureOutput *)output {
    if (self = [super init]) {
        _originalDelegate = delegate;
        _originalOutput = output; // Store the original output
    }
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (spoofCameraEnabled) {
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                // Pass self.originalOutput because 'output' in this context is the hooked AVCaptureVideoDataOutput instance,
                // but the original delegate was set on that instance.
                [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:spoofedFrame fromConnection:connection];
            }
            CFRelease(spoofedFrame);
        } else {
            // NSLog(@"[LC] Failed to create spoofed frame, not delivering frame.");
            // Optionally, deliver the original frame if spoofing fails catastrophically to prevent app freeze
            // if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            //     [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:sampleBuffer fromConnection:connection];
            // }
        }
    } else {
        if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}
@end

#pragma mark - Method Hooks

@implementation AVCaptureVideoDataOutput(LiveContainerSimpleSpoof)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] Hooking AVCaptureVideoDataOutput delegate.");
        SimpleSpoofDelegate *wrapper = [[SimpleSpoofDelegate alloc] initWithDelegate:sampleBufferDelegate output:self];
        // Retain the wrapper. A common way is to associate it with `self`.
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
    } else {
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    }
}
@end

@implementation AVCapturePhotoOutput(LiveContainerSimpleSpoof)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Spoofing photo capture.");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            CMSampleBufferRef spoofedFrameContents = createSpoofedSampleBuffer(); 
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (spoofedFrameContents) {
                    if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                        [delegate captureOutput:self didFinishProcessingPhoto:nil error:nil];
                    }
                    if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                        // Pass nil for resolvedSettings as we cannot reliably create a valid one.
                        [delegate captureOutput:self didFinishCaptureForResolvedSettings:nil error:nil];
                    }
                    CFRelease(spoofedFrameContents);
                } else {
                    NSError *error = [NSError errorWithDomain:@"LiveContainer.Spoof" code:1003 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create spoofed content for photo."}];
                    if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                        // Pass nil for resolvedSettings in error case as well.
                        [delegate captureOutput:self didFinishCaptureForResolvedSettings:nil error:error];
                    }
                }
            });
        });
        return; 
    }
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}
@end

#pragma mark - Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Initializing AVFoundation Guest Hooks...");

        NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
        if (!guestAppInfo) {
            NSLog(@"[LC] No guestAppInfo found. Hooks not applied.");
            return;
        }

        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        if (!spoofCameraEnabled) {
            NSLog(@"[LC] Camera spoofing is disabled in settings.");
            return;
        }

        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
        spoofCameraLoop = (guestAppInfo[@"spoofCameraLoop"] != nil) ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;

        NSLog(@"[LC] Config: Enabled=%d, Type=%@, ImagePath='%@', VideoPath='%@', Loop=%d",
              spoofCameraEnabled, spoofCameraType, spoofCameraImagePath, spoofCameraVideoPath, spoofCameraLoop);
        
        videoProcessingQueue = dispatch_queue_create("com.livecontainer.videoprocessingqueue", DISPATCH_QUEUE_SERIAL);

        // Always setup image resources first, as it's a fallback or primary mode.
        setupImageSpoofingResources();

        if ([spoofCameraType isEqualToString:@"video"]) {
            // Initiate video resource setup. isVideoSetupSuccessfully will be set asynchronously.
            setupVideoSpoofingResources();
        }
        
        // This check ensures that if image mode is selected and image setup failed,
        // then there's nothing to spoof. If video mode is selected, we proceed,
        // and createSpoofedSampleBuffer will handle fallback if video fails.
        if (!staticImageSpoofBuffer && ![spoofCameraType isEqualToString:@"video"]) {
            NSLog(@"[LC] ❌ Image mode selected but failed to prepare image resources. Disabling spoofing.");
            spoofCameraEnabled = NO;
            return;
        }
        
        if (!spoofCameraEnabled) { // Re-check in case it was disabled by the above condition
            NSLog(@"[LC] Spoofing disabled due to resource preparation failure.");
            return;
        }

        // Apply hooks
        swizzle([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
        swizzle([AVCapturePhotoOutput class], @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
        
        // The mode logged here reflects the initial configuration.
        // Actual frames will depend on successful resource loading and the logic in createSpoofedSampleBuffer.
        NSLog(@"[LC] ✅ AVFoundation Guest Hooks initialized. Configured mode: %@.", spoofCameraType);

    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception during AVFoundationGuestHooksInit: %@", exception);
    }
}