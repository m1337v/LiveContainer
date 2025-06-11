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
// static void playerItemDidPlayToEndTime(NSNotification *notification); // Not directly used as a separate function anymore

#pragma mark - GetFrame Logic (Simplified into static functions)

static CMSampleBufferRef createSpoofedSampleBuffer() {
    CVPixelBufferRef currentPixelBuffer = NULL;
    BOOL ownPixelBuffer = NO; // True if we copied/created and need to release currentPixelBuffer

    // Attempt to get video frame if in video mode
    if ([spoofCameraType isEqualToString:@"video"]) {
        if (isVideoSetupSuccessfully) {
            if (videoSpoofPlayerOutput && videoSpoofPlayer.currentItem && videoSpoofPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay && videoSpoofPlayer.rate > 0.0f) {
                CMTime playerTime = [videoSpoofPlayer.currentItem currentTime];
                if ([videoSpoofPlayerOutput hasNewPixelBufferForItemTime:playerTime]) {
                    currentPixelBuffer = [videoSpoofPlayerOutput copyPixelBufferForItemTime:playerTime itemTimeForDisplay:NULL];
                    if (currentPixelBuffer) {
                        ownPixelBuffer = YES;
                        NSLog(@"[LC] Video: Successfully copied pixel buffer for time %.2fs.", CMTimeGetSeconds(playerTime));
                    } else {
                        NSLog(@"[LC] Video: copyPixelBufferForItemTime returned NULL for time %.2fs.", CMTimeGetSeconds(playerTime));
                    }
                } else {
                    // This log can be frequent if called faster than video frame rate.
                    // NSLog(@"[LC] Video: hasNewPixelBufferForItemTime is NO for time %.2fs. Player status: %ld, Rate: %.2f", CMTimeGetSeconds(playerTime), (long)videoSpoofPlayer.currentItem.status, videoSpoofPlayer.rate);
                }
            } else {
                NSLog(@"[LC] Video: Player/item not ready, output nil, or player not playing. Output: %p, Item: %p, Status: %ld, Rate: %.2f",
                      videoSpoofPlayerOutput,
                      videoSpoofPlayer.currentItem,
                      videoSpoofPlayer.currentItem ? (long)videoSpoofPlayer.currentItem.status : -1L,
                      videoSpoofPlayer ? videoSpoofPlayer.rate : -1.0f);
            }
        } else {
            NSLog(@"[LC] Video: Mode is video, but isVideoSetupSuccessfully is NO.");
        }
    }

    // Fallback to static image if video frame not obtained or in image mode
    if (!currentPixelBuffer) {
        if (staticImageSpoofBuffer) {
            if ([spoofCameraType isEqualToString:@"video"]) {
                NSLog(@"[LC] Video: Falling back to static image buffer.");
            }
            currentPixelBuffer = staticImageSpoofBuffer;
            CFRetain(currentPixelBuffer); // Retain for CMSampleBufferCreateReadyWithImageBuffer
            ownPixelBuffer = YES;
        } else {
            NSLog(@"[LC] CRITICAL: No spoof pixel buffer available (staticImageSpoofBuffer is NULL).");
            return NULL;
        }
    }
    
    // At this point, currentPixelBuffer should be valid (either video or static image)
    // Or the function should have returned NULL if staticImageSpoofBuffer was also NULL.

    CMVideoFormatDescriptionRef currentFormatDesc = NULL;
    // For static images, we could use the pre-created staticImageFormatDesc if available and matches.
    // However, creating it on-the-fly from currentPixelBuffer is safer if currentPixelBuffer could change (e.g., video frames).
    OSStatus formatDescStatus = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, currentPixelBuffer, &currentFormatDesc);

    if (formatDescStatus != noErr) {
        NSLog(@"[LC] Failed to create format description from currentPixelBuffer. Status: %d", (int)formatDescStatus);
        if (ownPixelBuffer) CVPixelBufferRelease(currentPixelBuffer);
        return NULL;
    }

    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), NSEC_PER_SEC); // Use current time for presentation
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30), // Assume 30 FPS
        .presentationTimeStamp = presentationTime,
        .decodeTimeStamp = kCMTimeInvalid
    };

    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus result = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        currentPixelBuffer, // This is the (potentially) retained CVPixelBufferRef
        currentFormatDesc,
        &timingInfo,
        &sampleBuffer
    );

    if (currentFormatDesc) CFRelease(currentFormatDesc);
    if (ownPixelBuffer) CVPixelBufferRelease(currentPixelBuffer); // Release the buffer we copied or retained

    if (result != noErr) {
        NSLog(@"[LC] Failed to create CMSampleBuffer. Status: %d", (int)result);
        return NULL;
    }
    return sampleBuffer; // Caller must release this sample buffer
}

#pragma mark - Resource Setup

static void setupImageSpoofingResources() {
    NSLog(@"[LC] Setting up image spoofing resources...");
    if (staticImageSpoofBuffer) {
        CVPixelBufferRelease(staticImageSpoofBuffer);
        staticImageSpoofBuffer = NULL;
    }
    // staticImageFormatDesc is not strictly needed globally if created on-the-fly in createSpoofedSampleBuffer
    // but if we were to optimize, we could pre-create it here. For now, let createSpoofedSampleBuffer handle it.
    // if (staticImageFormatDesc) {
    //     CFRelease(staticImageFormatDesc);
    //     staticImageFormatDesc = NULL;
    // }

    UIImage *image = nil;
    if (spoofCameraImagePath && spoofCameraImagePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:spoofCameraImagePath]) {
        image = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
        if (!image) {
            NSLog(@"[LC] Failed to load image from valid path: %@", spoofCameraImagePath);
        } else {
            NSLog(@"[LC] Successfully loaded image from path: %@", spoofCameraImagePath);
        }
    } else {
        if (spoofCameraImagePath && spoofCameraImagePath.length > 0) {
            NSLog(@"[LC] Image path provided but file not found: %@", spoofCameraImagePath);
        } else {
            NSLog(@"[LC] No image path provided.");
        }
    }

    if (!image) { 
        NSLog(@"[LC] Creating default spoof image.");
        CGSize size = CGSizeMake(1080, 1920); // Standard HD size
        UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
        CGContextRef uigraphicsContext = UIGraphicsGetCurrentContext();
        if (uigraphicsContext) {
            [[UIColor colorWithRed:0.1 green:0.3 blue:0.8 alpha:1.0] setFill]; // Blue color
            CGContextFillRect(uigraphicsContext, CGRectMake(0, 0, size.width, size.height));
            NSString *text = @"LiveContainer\nSpoofed Content";
            NSDictionary *attrs = @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:60], NSForegroundColorAttributeName: [UIColor whiteColor] };
            CGSize textSize = [text sizeWithAttributes:attrs];
            CGRect textRect = CGRectMake((size.width - textSize.width) / 2, (size.height - textSize.height) / 2, textSize.width, textSize.height);
            [text drawInRect:textRect withAttributes:attrs];
            image = UIGraphicsGetImageFromCurrentImageContext();
        } else {
            NSLog(@"[LC] Failed to get UIGraphics context for default image.");
        }
        UIGraphicsEndImageContext();
        if (!image) {
            NSLog(@"[LC] CRITICAL: Failed to create default spoof image.");
            return; // staticImageSpoofBuffer will remain NULL
        }
    }
    
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) {
        NSLog(@"[LC] CRITICAL: CGImage is NULL after image creation/loading.");
        return; // staticImageSpoofBuffer will remain NULL
    }
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);

    NSDictionary *pixelBufferAttributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{} // Important for some rendering paths
    };

    CVReturn cvRet = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)pixelBufferAttributes, &staticImageSpoofBuffer);
    if (cvRet != kCVReturnSuccess || !staticImageSpoofBuffer) {
        NSLog(@"[LC] Failed to create CVPixelBuffer for image. Error: %d", cvRet);
        staticImageSpoofBuffer = NULL; // Ensure it's NULL on failure
        return;
    }

    CVPixelBufferLockBaseAddress(staticImageSpoofBuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(staticImageSpoofBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, width, height, 8, CVPixelBufferGetBytesPerRow(staticImageSpoofBuffer),
                                                 rgbColorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
        CGContextRelease(context);
    } else {
        NSLog(@"[LC] Failed to create CGBitmapContext for drawing image.");
        // Buffer might be created but not drawn into.
    }
    CGColorSpaceRelease(rgbColorSpace);
    CVPixelBufferUnlockBaseAddress(staticImageSpoofBuffer, 0);

    // We don't strictly need to create staticImageFormatDesc here if createSpoofedSampleBuffer makes its own.
    // CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, staticImageSpoofBuffer, &staticImageFormatDesc);
    // if (!staticImageFormatDesc) {
    //      NSLog(@"[LC] Failed to create CMVideoFormatDescription for image.");
    //      CVPixelBufferRelease(staticImageSpoofBuffer);
    //      staticImageSpoofBuffer = NULL;
    // } else {
    //     NSLog(@"[LC] Image spoofing resources prepared with static format description.");
    // }
    if (staticImageSpoofBuffer) {
        NSLog(@"[LC] Image spoofing CVPixelBuffer prepared successfully.");
    }
}

static void setupVideoSpoofingResources() {
    NSLog(@"[LC] Setting up video spoofing resources for path: %@", spoofCameraVideoPath);
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
    // Asynchronously load tracks to avoid blocking
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        NSError *error = nil;
        AVKeyValueStatus status = [asset statusOfValueForKey:@"tracks" error:&error];

        if (status != AVKeyValueStatusLoaded) {
            NSLog(@"[LC] Failed to load tracks for asset: %@. Error: %@", spoofCameraVideoPath, error);
            isVideoSetupSuccessfully = NO;
            return;
        }

        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (tracks.count == 0) {
            NSLog(@"[LC] No video tracks found in asset: %@", spoofCameraVideoPath);
            isVideoSetupSuccessfully = NO;
            return;
        }

        // Clean up previous player and observer
        if (videoSpoofPlayer) {
            [videoSpoofPlayer pause];
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
        videoSpoofPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone; // Important for manual looping

        NSDictionary *pixelBufferAttributes = @{
            (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
            (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
        };
        videoSpoofPlayerOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];
        
        // REMOVE THE PROBLEMATIC KVO LINE:
        // [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:&videoProcessingQueue];
        // The polling loop below handles status checking.

        dispatch_async(videoProcessingQueue, ^{
            NSLog(@"[LC] Video processing queue: Waiting for player item status...");
            while (playerItem.status != AVPlayerItemStatusReadyToPlay) {
                [NSThread sleepForTimeInterval:0.05]; // Increased sleep interval slightly
                if (playerItem.status == AVPlayerItemStatusFailed) {
                     NSLog(@"[LC] Player item failed to load: %@. Error: %@", spoofCameraVideoPath, playerItem.error);
                     isVideoSetupSuccessfully = NO;
                     return;
                }
                if (playerItem.status == AVPlayerItemStatusUnknown) {
                    // Still unknown, keep waiting
                }
            }
            NSLog(@"[LC] Video processing queue: Player item is ReadyToPlay.");
            
            if (![playerItem.outputs containsObject:videoSpoofPlayerOutput]) {
                [playerItem addOutput:videoSpoofPlayerOutput];
                NSLog(@"[LC] Video processing queue: Added video output to player item.");
            } else {
                 NSLog(@"[LC] Video processing queue: Video output already on player item.");
            }
            
            if (spoofCameraLoop) {
                if (playerDidPlayToEndTimeObserver) { // Remove old one if any
                    [[NSNotificationCenter defaultCenter] removeObserver:playerDidPlayToEndTimeObserver];
                }
                playerDidPlayToEndTimeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                  object:playerItem
                                                                   queue:[NSOperationQueue mainQueue] // Ensure UI updates on main
                                                              usingBlock:^(NSNotification *note) {
                    NSLog(@"[LC] Video item did play to end. Seeking to zero and replaying.");
                    [videoSpoofPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                        if (finished) {
                            [videoSpoofPlayer play];
                            NSLog(@"[LC] Video replaying. Rate: %.2f", videoSpoofPlayer.rate);
                        }
                    }];
                }];
            }
            
            [videoSpoofPlayer play];
            isVideoSetupSuccessfully = YES; // Set only after successful setup and play command
            NSLog(@"[LC] Video spoofing resources prepared. Player started for: %@. Rate: %.2f", spoofCameraVideoPath, videoSpoofPlayer.rate);
            if (videoSpoofPlayer.rate == 0.0f && playerItem.status == AVPlayerItemStatusReadyToPlay) {
                NSLog(@"[LC] WARNING: Player rate is 0.0 even after play command and item ready.");
            }
        });
    }]; // End of asset loadValuesAsynchronouslyForKeys
}


#pragma mark - Delegate Wrapper (Ensure this is declared before AVCaptureVideoDataOutput category)

@interface SimpleSpoofDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@property (nonatomic, assign) AVCaptureOutput *originalOutput;
@end

@implementation SimpleSpoofDelegate
- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureOutput *)output {
    if (self = [super init]) {
        _originalDelegate = delegate;
        _originalOutput = output;
    }
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (spoofCameraEnabled) {
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer(); // This will be either video or image
        if (spoofedFrame) {
            if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:spoofedFrame fromConnection:connection];
            }
            CFRelease(spoofedFrame); // Release the buffer we created
        } else {
            // NSLog(@"[LC] Failed to create spoofed frame, not delivering frame.");
            // Consider if original frame should be passed if spoofing fails, to avoid black screen
            // This might cause flicker if spoofing is intermittent. For now, if spoof fails, no frame.
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
                        // Passing nil for AVCapturePhoto is a simplification.
                        [delegate captureOutput:self didFinishProcessingPhoto:nil error:nil];
                    }
                    if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                        [delegate captureOutput:self didFinishCaptureForResolvedSettings:nil error:nil];
                    }
                    CFRelease(spoofedFrameContents);
                } else {
                    NSError *error = [NSError errorWithDomain:@"LiveContainer.Spoof" code:1003 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create spoofed content for photo."}];
                    if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
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
        NSLog(@"[LC] Initializing AVFoundation Guest Hooks (Build: %s %s)...", __DATE__, __TIME__);

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

        // Setup image resources first. This is synchronous and provides a fallback.
        setupImageSpoofingResources();

        if ([spoofCameraType isEqualToString:@"video"]) {
            if (spoofCameraVideoPath && spoofCameraVideoPath.length > 0) {
                NSLog(@"[LC] Video mode configured. Initiating video resource setup...");
                setupVideoSpoofingResources(); // This is asynchronous for some parts
            } else {
                NSLog(@"[LC] Video mode configured, but no video path. Will use image fallback.");
                spoofCameraType = @"image"; // Explicitly switch to image if no video path
            }
        }
        
        // If image mode is active (either by config or fallback) and image setup failed, then disable.
        if ([spoofCameraType isEqualToString:@"image"] && !staticImageSpoofBuffer) {
            NSLog(@"[LC] ❌ Image mode active but failed to prepare image resources. Disabling spoofing.");
            spoofCameraEnabled = NO;
        }
        // If video mode is configured, we proceed. createSpoofedSampleBuffer will handle fallback to image
        // if video setup fails or video frames are not available. If staticImageSpoofBuffer is also NULL,
        // then createSpoofedSampleBuffer will return NULL.

        if (!spoofCameraEnabled) {
            NSLog(@"[LC] Spoofing ultimately disabled due to resource preparation issues or settings.");
            return;
        }

        // Apply hooks
        swizzle([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
        swizzle([AVCapturePhotoOutput class], @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
        
        NSLog(@"[LC] ✅ AVFoundation Guest Hooks initialized. Configured mode: %@. Spoofing active.", spoofCameraType);

    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception during AVFoundationGuestHooksInit: %@", exception);
    }
}