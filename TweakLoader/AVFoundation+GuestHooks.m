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

// Resolution and Fallback Management
static CGSize targetResolution = {1080, 1920}; // Default to Portrait Full HD
static BOOL resolutionDetected = NO;
static CVPixelBufferRef lastGoodSpoofedPixelBuffer = NULL;
static CMVideoFormatDescriptionRef lastGoodSpoofedFormatDesc = NULL; // Paired with lastGoodSpoofedPixelBuffer

// Image Spoofing Resources
static CVPixelBufferRef staticImageSpoofBuffer = NULL; // This will be at targetResolution

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

#pragma mark - Pixel Buffer Utilities

// Helper to create a CVPixelBufferRef by scaling another CVPixelBufferRef
static CVPixelBufferRef createScaledPixelBuffer(CVPixelBufferRef sourceBuffer, CGSize scaleToSize) {
    if (!sourceBuffer) return NULL;

    size_t sourceWidth = CVPixelBufferGetWidth(sourceBuffer);
    size_t sourceHeight = CVPixelBufferGetHeight(sourceBuffer);
    OSType sourceFormat = CVPixelBufferGetPixelFormatType(sourceBuffer);

    // If already the correct size and format (assuming 32BGRA for output), just retain and return
    if (sourceWidth == (size_t)scaleToSize.width && sourceHeight == (size_t)scaleToSize.height && sourceFormat == kCVPixelFormatType_32BGRA) {
        CVPixelBufferRetain(sourceBuffer);
        return sourceBuffer;
    }

    CVPixelBufferRef scaledPixelBuffer = NULL;
    NSDictionary *pixelAttributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          (size_t)scaleToSize.width,
                                          (size_t)scaleToSize.height,
                                          kCVPixelFormatType_32BGRA, // Output format
                                          (__bridge CFDictionaryRef)pixelAttributes,
                                          &scaledPixelBuffer);
    if (status != kCVReturnSuccess || !scaledPixelBuffer) {
        NSLog(@"[LC] Error creating scaled pixel buffer: %d", status);
        return NULL;
    }

    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:sourceBuffer];
    CIContext *ciContext = [CIContext contextWithOptions:nil]; // Create a new context or use a shared one

    CGFloat scaleX = scaleToSize.width / sourceWidth;
    CGFloat scaleY = scaleToSize.height / sourceHeight;
    ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];
    
    // Adjust for potential origin differences after scaling if aspect ratios differ
    CGRect extent = ciImage.extent;
    if (extent.origin.x != 0 || extent.origin.y != 0) {
        ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
    }

    [ciContext render:ciImage toCVPixelBuffer:scaledPixelBuffer];

    return scaledPixelBuffer; // Caller must release
}

// Helper to update the last good spoofed frame
static void updateLastGoodSpoofedFrame(CVPixelBufferRef newPixelBuffer, CMVideoFormatDescriptionRef newFormatDesc) {
    if (lastGoodSpoofedPixelBuffer) {
        CVPixelBufferRelease(lastGoodSpoofedPixelBuffer);
        lastGoodSpoofedPixelBuffer = NULL;
    }
    if (lastGoodSpoofedFormatDesc) {
        CFRelease(lastGoodSpoofedFormatDesc);
        lastGoodSpoofedFormatDesc = NULL;
    }

    if (newPixelBuffer) {
        lastGoodSpoofedPixelBuffer = newPixelBuffer;
        CVPixelBufferRetain(lastGoodSpoofedPixelBuffer); // Retain for global storage
    }
    if (newFormatDesc) {
        lastGoodSpoofedFormatDesc = newFormatDesc;
        CFRetain(lastGoodSpoofedFormatDesc); // Retain for global storage
    }
}


#pragma mark - GetFrame Logic

static CMSampleBufferRef createSpoofedSampleBuffer() {
    CVPixelBufferRef sourcePixelBuffer = NULL; // Raw buffer from video or static image
    BOOL ownSourcePixelBuffer = NO;

    // 1. Attempt to get video frame
    if ([spoofCameraType isEqualToString:@"video"] && isVideoSetupSuccessfully &&
        videoSpoofPlayerOutput && videoSpoofPlayer.currentItem &&
        videoSpoofPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay && videoSpoofPlayer.rate > 0.0f) {
        
        CMTime playerTime = [videoSpoofPlayer.currentItem currentTime];
        if ([videoSpoofPlayerOutput hasNewPixelBufferForItemTime:playerTime]) {
            sourcePixelBuffer = [videoSpoofPlayerOutput copyPixelBufferForItemTime:playerTime itemTimeForDisplay:NULL];
            if (sourcePixelBuffer) {
                ownSourcePixelBuffer = YES;
                // NSLog(@"[LC] Video: Got raw frame %.2fs", CMTimeGetSeconds(playerTime));
            }
        }
    }

    // 2. Fallback to static image if video frame not obtained
    if (!sourcePixelBuffer && staticImageSpoofBuffer) {
        sourcePixelBuffer = staticImageSpoofBuffer; // Use the global static buffer (already at targetResolution)
        CVPixelBufferRetain(sourcePixelBuffer); // Retain for local use in this function
        ownSourcePixelBuffer = YES;
        // if ([spoofCameraType isEqualToString:@"video"]) NSLog(@"[LC] Video: Fallback to static image source.");
    }
    
    CVPixelBufferRef finalScaledPixelBuffer = NULL;
    if (sourcePixelBuffer) {
        finalScaledPixelBuffer = createScaledPixelBuffer(sourcePixelBuffer, targetResolution);
        if (ownSourcePixelBuffer) {
            CVPixelBufferRelease(sourcePixelBuffer); // Release the source we copied or retained
        }
    }

    // 3. If current frame generation failed, try to use the last good frame
    if (!finalScaledPixelBuffer && lastGoodSpoofedPixelBuffer) {
        finalScaledPixelBuffer = lastGoodSpoofedPixelBuffer;
        CVPixelBufferRetain(finalScaledPixelBuffer); // Retain for local use, as it's a global
        NSLog(@"[LC] FrameGen: Using last good spoofed frame.");
    }

    if (!finalScaledPixelBuffer) {
        NSLog(@"[LC] CRITICAL: No pixel buffer available for spoofing (current or last good).");
        return NULL;
    }

    // 4. Create Format Description for the final buffer
    CMVideoFormatDescriptionRef currentFormatDesc = NULL;
    if (finalScaledPixelBuffer == lastGoodSpoofedPixelBuffer && lastGoodSpoofedFormatDesc) {
        // If using last good frame, and its format desc is available, use it.
        currentFormatDesc = lastGoodSpoofedFormatDesc;
        CFRetain(currentFormatDesc);
    } else {
        OSStatus formatDescStatus = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, finalScaledPixelBuffer, &currentFormatDesc);
        if (formatDescStatus != noErr) {
            NSLog(@"[LC] Failed to create format description. Status: %d", (int)formatDescStatus);
            CVPixelBufferRelease(finalScaledPixelBuffer);
            return NULL;
        }
    }
    
    // 5. Update last good spoofed frame if we generated a new one (not from fallback)
    // Check if finalScaledPixelBuffer is different from lastGoodSpoofedPixelBuffer before updating
    // to avoid redundant updates if we just used the last good one.
    if (finalScaledPixelBuffer != lastGoodSpoofedPixelBuffer) {
         updateLastGoodSpoofedFrame(finalScaledPixelBuffer, currentFormatDesc);
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
        finalScaledPixelBuffer,
        currentFormatDesc,
        &timingInfo,
        &sampleBuffer
    );

    if (currentFormatDesc) CFRelease(currentFormatDesc);
    if (finalScaledPixelBuffer) CVPixelBufferRelease(finalScaledPixelBuffer); // Release local retain

    if (result != noErr) {
        NSLog(@"[LC] Failed to create CMSampleBuffer. Status: %d", (int)result);
        return NULL;
    }
    return sampleBuffer; // Caller must release this sample buffer
}

#pragma mark - Resource Setup

static void setupImageSpoofingResources() {
    NSLog(@"[LC] Setting up image spoofing resources for target resolution: %.0fx%.0f", targetResolution.width, targetResolution.height);
    
    // Release previous static buffer if it exists
    if (staticImageSpoofBuffer) {
        CVPixelBufferRelease(staticImageSpoofBuffer);
        staticImageSpoofBuffer = NULL;
    }

    UIImage *sourceImage = nil;
    if (spoofCameraImagePath && spoofCameraImagePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:spoofCameraImagePath]) {
        sourceImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
        if (!sourceImage) {
            NSLog(@"[LC] Failed to load image from valid path: %@", spoofCameraImagePath);
        } else {
            NSLog(@"[LC] Successfully loaded image from path: %@", spoofCameraImagePath);
        }
    }

    if (!sourceImage) { 
        NSLog(@"[LC] Creating default spoof image at %.0fx%.0f.", targetResolution.width, targetResolution.height);
        UIGraphicsBeginImageContextWithOptions(targetResolution, YES, 1.0); // Create at target res
        CGContextRef uigraphicsContext = UIGraphicsGetCurrentContext();
        if (uigraphicsContext) {
            // Gradient background
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGFloat colors[] = { 0.2, 0.4, 0.8, 1.0, 0.1, 0.2, 0.4, 1.0 };
            CGFloat locations[] = {0.0, 1.0};
            CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, locations, 2);
            CGContextDrawLinearGradient(uigraphicsContext, gradient, CGPointMake(0,0), CGPointMake(0,targetResolution.height), 0);
            CGGradientRelease(gradient);
            CGColorSpaceRelease(colorSpace);

            NSString *text = @"LiveContainer\nSpoofed";
            NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
            paragraphStyle.alignment = NSTextAlignmentCenter;
            NSDictionary *attrs = @{ 
                NSFontAttributeName: [UIFont boldSystemFontOfSize:targetResolution.width * 0.06], 
                NSForegroundColorAttributeName: [UIColor whiteColor],
                NSParagraphStyleAttributeName: paragraphStyle
            };
            CGSize textSize = [text sizeWithAttributes:attrs];
            CGRect textRect = CGRectMake((targetResolution.width - textSize.width) / 2, (targetResolution.height - textSize.height) / 2, textSize.width, textSize.height);
            [text drawInRect:textRect withAttributes:attrs];
            sourceImage = UIGraphicsGetImageFromCurrentImageContext();
        }
        UIGraphicsEndImageContext();
        if (!sourceImage) {
            NSLog(@"[LC] CRITICAL: Failed to create default spoof image.");
            return; 
        }
    }
    
    // Convert UIImage to CVPixelBufferRef at targetResolution
    CGImageRef cgImage = sourceImage.CGImage;
    if (!cgImage) {
        NSLog(@"[LC] CRITICAL: CGImage is NULL for static image.");
        return;
    }

    NSDictionary *pixelBufferAttributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    CVReturn cvRet = CVPixelBufferCreate(kCFAllocatorDefault, 
                                     (size_t)targetResolution.width, (size_t)targetResolution.height, 
                                     kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)pixelBufferAttributes, &staticImageSpoofBuffer);
    if (cvRet != kCVReturnSuccess || !staticImageSpoofBuffer) {
        NSLog(@"[LC] Failed to create CVPixelBuffer for static image. Error: %d", cvRet);
        staticImageSpoofBuffer = NULL;
        return;
    }

    CVPixelBufferLockBaseAddress(staticImageSpoofBuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(staticImageSpoofBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, 
                                                 (size_t)targetResolution.width, (size_t)targetResolution.height, 
                                                 8, CVPixelBufferGetBytesPerRow(staticImageSpoofBuffer),
                                                 rgbColorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, targetResolution.width, targetResolution.height), cgImage); // Draw scaled
        CGContextRelease(context);
    } else {
        NSLog(@"[LC] Failed to create CGBitmapContext for drawing static image.");
    }
    CGColorSpaceRelease(rgbColorSpace);
    CVPixelBufferUnlockBaseAddress(staticImageSpoofBuffer, 0);

    if (staticImageSpoofBuffer) {
        NSLog(@"[LC] Static image CVPixelBuffer prepared successfully at %.0fx%.0f.", targetResolution.width, targetResolution.height);
        // Initialize last good frame with this static image
        CMVideoFormatDescriptionRef tempFormatDesc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, staticImageSpoofBuffer, &tempFormatDesc);
        updateLastGoodSpoofedFrame(staticImageSpoofBuffer, tempFormatDesc); // staticImageSpoofBuffer is already retained by itself
        if (tempFormatDesc) CFRelease(tempFormatDesc);
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
        videoSpoofPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;

        NSDictionary *pixelBufferAttributes = @{
            (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
            (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
        };
        videoSpoofPlayerOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];
        
        dispatch_async(videoProcessingQueue, ^{
            while (playerItem.status != AVPlayerItemStatusReadyToPlay) {
                [NSThread sleepForTimeInterval:0.05];
                if (playerItem.status == AVPlayerItemStatusFailed) {
                     NSLog(@"[LC] Player item failed to load: %@. Error: %@", spoofCameraVideoPath, playerItem.error);
                     isVideoSetupSuccessfully = NO;
                     return;
                }
            }
            
            if (![playerItem.outputs containsObject:videoSpoofPlayerOutput]) {
                [playerItem addOutput:videoSpoofPlayerOutput];
            }
            
            if (spoofCameraLoop) {
                if (playerDidPlayToEndTimeObserver) {
                    [[NSNotificationCenter defaultCenter] removeObserver:playerDidPlayToEndTimeObserver];
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
            NSLog(@"[LC] Video spoofing resources prepared. Player started for: %@. Rate: %.2f", spoofCameraVideoPath, videoSpoofPlayer.rate);
        });
    }];
}


#pragma mark - Delegate Wrapper

// Add this interface declaration for SimpleSpoofDelegate
@interface SimpleSpoofDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@property (nonatomic, assign) AVCaptureOutput *originalOutput; // Use assign for AVCaptureOutput, as it's not typically retained by a delegate

- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureOutput *)output;
@end

@implementation SimpleSpoofDelegate
- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureOutput *)output {
    if (self = [super init]) { // Now 'super' is valid as it inherits from NSObject
        _originalDelegate = delegate;
        _originalOutput = output;
    }
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // Dynamic Resolution Detection from actual camera frames
    if (!resolutionDetected && !spoofCameraEnabled && sampleBuffer) { // Only detect if not spoofing & first time
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (imageBuffer) {
            size_t width = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            if (width > 0 && height > 0) {
                CGSize detectedRes = CGSizeMake(width, height);
                // Check if significantly different from current targetResolution
                if (fabs(detectedRes.width - targetResolution.width) > 1 || fabs(detectedRes.height - targetResolution.height) > 1) {
                    // Corrected NSLog format specifiers
                    NSLog(@"[LC] 📐 Detected camera resolution: %zux%zu. Updating target from %.0fx%.0f.", width, height, targetResolution.width, targetResolution.height);
                    targetResolution = detectedRes;
                    resolutionDetected = YES; // Mark as detected
                    
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        setupImageSpoofingResources(); 
                    });
                } else {
                     resolutionDetected = YES; 
                }
            }
        }
    }

    if (spoofCameraEnabled) {
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            // Properties should now be accessible
            if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:spoofedFrame fromConnection:connection];
            }
            CFRelease(spoofedFrame);
        } else {
            // NSLog(@"[LC] Failed to create spoofed frame, not delivering frame.");
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
        // SimpleSpoofDelegate now conforms to the protocol
        SimpleSpoofDelegate *wrapper = [[SimpleSpoofDelegate alloc] initWithDelegate:sampleBufferDelegate output:self];
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
    } else {
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    }
}
@end


// Photo capture: Revert to passing nil for resolvedSettings to avoid compiler issues.
@implementation AVCapturePhotoOutput(LiveContainerSimpleSpoof)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Spoofing photo capture (Target Res: %.0fx%.0f)", targetResolution.width, targetResolution.height);
        
        CMSampleBufferRef spoofedFrameContents = createSpoofedSampleBuffer(); 
            
        dispatch_async(dispatch_get_main_queue(), ^{
            if (spoofedFrameContents) {
                if ([delegate respondsToSelector:@selector(captureOutput:willBeginCaptureForResolvedSettings:)]) {
                    // Pass nil for resolvedSettings
                    [delegate captureOutput:self willBeginCaptureForResolvedSettings:nil];
                }

                if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                    [delegate captureOutput:self didFinishProcessingPhoto:nil error:nil]; // This nil is for AVCapturePhoto
                }
                if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                    // Pass nil for resolvedSettings
                    [delegate captureOutput:self didFinishCaptureForResolvedSettings:nil error:nil];
                }
                CFRelease(spoofedFrameContents);
            } else {
                NSError *error = [NSError errorWithDomain:@"LiveContainer.Spoof" code:1003 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create spoofed content for photo."}];
                if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
                    // Pass nil for resolvedSettings
                    [delegate captureOutput:self didFinishCaptureForResolvedSettings:nil error:error];
                }
            }
        });
        return; 
    }
    // Corrected recursive call to the original method (via swizzling)
    [self lc_capturePhotoWithSettings:settings delegate:delegate]; 
}
@end


#pragma mark - Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] Initializing AVFoundation Guest Hooks (Build: %s %s)...", __DATE__, __TIME__);
        // ... (guestAppInfo and spoofCameraEnabled checks remain the same) ...
        NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
        if (!guestAppInfo) {
            NSLog(@"[LC] No guestAppInfo found. Hooks not applied.");
            return;
        }

        spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
        // Dynamic resolution detection will happen later if spoofing is off initially.
        // If spoofing is on from the start, it uses default targetResolution.

        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
        spoofCameraLoop = (guestAppInfo[@"spoofCameraLoop"] != nil) ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;

        NSLog(@"[LC] Config: Enabled=%d, Type=%@, ImagePath='%@', VideoPath='%@', Loop=%d, InitialTargetRes=%.0fx%.0f",
              spoofCameraEnabled, spoofCameraType, spoofCameraImagePath, spoofCameraVideoPath, spoofCameraLoop, targetResolution.width, targetResolution.height);
        
        videoProcessingQueue = dispatch_queue_create("com.livecontainer.videoprocessingqueue", DISPATCH_QUEUE_SERIAL);

        // Setup image resources first. This is synchronous and provides a fallback.
        // It will use the initial targetResolution and populate lastGoodSpoofedPixelBuffer.
        setupImageSpoofingResources();

        if (spoofCameraEnabled && [spoofCameraType isEqualToString:@"video"]) {
            if (spoofCameraVideoPath && spoofCameraVideoPath.length > 0) {
                NSLog(@"[LC] Video mode configured. Initiating video resource setup...");
                setupVideoSpoofingResources(); 
            } else {
                NSLog(@"[LC] Video mode configured, but no video path. Will use image fallback.");
                // spoofCameraType is already "image" by default or if video path is bad
            }
        }
        
        if (spoofCameraEnabled && ![spoofCameraType isEqualToString:@"video"] && !staticImageSpoofBuffer) {
            NSLog(@"[LC] ❌ Image mode active but failed to prepare image resources. Disabling spoofing.");
            spoofCameraEnabled = NO; // This might be too aggressive if lastGoodFrame can cover it.
                                     // For now, if static image fails, and it's image mode, disable.
        }
        
        if (!spoofCameraEnabled && !resolutionDetected) {
             NSLog(@"[LC] Spoofing disabled, but resolution detection will run on first real frame.");
        }


        // Apply hooks regardless of initial spoofCameraEnabled state,
        // so that resolution detection can occur if spoofing is turned on later or for the first frame.
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSLog(@"[LC] Applying AVFoundation hooks...");
            swizzle([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
            swizzle([AVCapturePhotoOutput class], @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
            NSLog(@"[LC] ✅ AVFoundation Hooks applied.");
        });
        
        if (spoofCameraEnabled) {
             NSLog(@"[LC] ✅ Spoofing initialized. Configured mode: %@.", spoofCameraType);
        }


    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception during AVFoundationGuestHooksInit: %@", exception);
    }
}