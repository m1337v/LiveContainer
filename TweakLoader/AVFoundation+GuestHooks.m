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

// Cached Photo Data
static CVPixelBufferRef g_cachedPhotoPixelBuffer = NULL;
static CGImageRef g_cachedPhotoCGImage = NULL;
static NSData *g_cachedPhotoJPEGData = nil;

// --- Helper: NSUserDefaults ---
@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo; // Assumed to be implemented elsewhere
@end

// --- Forward Declarations ---
static void setupImageSpoofingResources(void);
static void setupVideoSpoofingResources(void);
static CMSampleBufferRef createSpoofedSampleBuffer(void);
// static void playerItemDidPlayToEndTime(NSNotification *notification); // Not directly used as a separate function anymore

// ADD THESE NEW FORWARD DECLARATIONS:
static void cachePhotoDataFromSampleBuffer(CMSampleBufferRef sampleBuffer);
static void cleanupPhotoCache(void);

// Photo accessor hook function pointers
static CVPixelBufferRef (*original_AVCapturePhoto_pixelBuffer)(id, SEL);
static CGImageRef (*original_AVCapturePhoto_CGImageRepresentation)(id, SEL);
static NSData *(*original_AVCapturePhoto_fileDataRepresentation)(id, SEL);

// Photo accessor hook functions
CVPixelBufferRef hook_AVCapturePhoto_pixelBuffer(id self, SEL _cmd);
CGImageRef hook_AVCapturePhoto_CGImageRepresentation(id self, SEL _cmd);
NSData *hook_AVCapturePhoto_fileDataRepresentation(id self, SEL _cmd);

#pragma mark - Pixel Buffer Utilities

// Cache CIContext for createScaledPixelBuffer
static CIContext *sharedCIContext = nil;

static CVPixelBufferRef createScaledPixelBuffer(CVPixelBufferRef sourceBuffer, CGSize scaleToSize) {
    if (!sourceBuffer) return NULL;

    size_t sourceWidth = CVPixelBufferGetWidth(sourceBuffer);
    size_t sourceHeight = CVPixelBufferGetHeight(sourceBuffer);
    OSType sourceFormat = CVPixelBufferGetPixelFormatType(sourceBuffer);

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
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)pixelAttributes,
                                          &scaledPixelBuffer);
    if (status != kCVReturnSuccess || !scaledPixelBuffer) {
        NSLog(@"[LC] Error creating scaled pixel buffer for scaling: %d", status);
        return NULL;
    }

    // Initialize shared CIContext on first use
    if (!sharedCIContext) {
        sharedCIContext = [CIContext contextWithOptions:nil];
        if (!sharedCIContext) {
            NSLog(@"[LC] CRITICAL: Failed to create shared CIContext for scaling.");
            CVPixelBufferRelease(scaledPixelBuffer); // Release the buffer we created
            return NULL; 
        }
    }
    
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:sourceBuffer];
    CGFloat scaleX = scaleToSize.width / sourceWidth;
    CGFloat scaleY = scaleToSize.height / sourceHeight;
    ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];
    
    CGRect extent = ciImage.extent;
    if (extent.origin.x != 0 || extent.origin.y != 0) {
        ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
    }

    [sharedCIContext render:ciImage toCVPixelBuffer:scaledPixelBuffer];

    return scaledPixelBuffer;
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

// Add this helper function to cache photo data:
static void cachePhotoDataFromSampleBuffer(CMSampleBufferRef sampleBuffer) {
    if (!sampleBuffer) return;
    
    // Clean up old cached data
    if (g_cachedPhotoPixelBuffer) {
        CVPixelBufferRelease(g_cachedPhotoPixelBuffer);
        g_cachedPhotoPixelBuffer = NULL;
    }
    if (g_cachedPhotoCGImage) {
        CGImageRelease(g_cachedPhotoCGImage);
        g_cachedPhotoCGImage = NULL;
    }
    g_cachedPhotoJPEGData = nil;
    
    // Cache new data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer) {
        g_cachedPhotoPixelBuffer = CVPixelBufferRetain(imageBuffer);
        
        // Create CGImage with PROPER ORIENTATION for photos
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
        
        // Apply camera-like orientation transform for photos
        // Photos typically need to be rotated and/or flipped to match expected orientation
        CGAffineTransform transform = CGAffineTransformIdentity;
        
        // For front camera simulation - flip horizontally
        transform = CGAffineTransformScale(transform, -1.0, 1.0);
        transform = CGAffineTransformTranslate(transform, -ciImage.extent.size.width, 0);
        
        // Apply the transform
        ciImage = [ciImage imageByApplyingTransform:transform];
        
        CIContext *context = [CIContext context];
        g_cachedPhotoCGImage = [context createCGImage:ciImage fromRect:ciImage.extent];
        
        // Create JPEG data with proper orientation
        if (g_cachedPhotoCGImage) {
            UIImage *image = [UIImage imageWithCGImage:g_cachedPhotoCGImage];
            
            // Apply additional UIImage orientation correction if needed
            // This ensures the final image has the correct orientation when saved
            UIImage *orientedImage = [UIImage imageWithCGImage:image.CGImage 
                                                         scale:image.scale 
                                                   orientation:UIImageOrientationUp]; // Force upright orientation
            
            g_cachedPhotoJPEGData = UIImageJPEGRepresentation(orientedImage, 0.9);
        }
    }
}

// Add photo accessor hook methods:
CVPixelBufferRef hook_AVCapturePhoto_pixelBuffer(id self, SEL _cmd) {
    if (spoofCameraEnabled && g_cachedPhotoPixelBuffer) {
        NSLog(@"[LC] 📷 Returning spoofed photo pixel buffer");
        return g_cachedPhotoPixelBuffer;
    }
    return original_AVCapturePhoto_pixelBuffer(self, _cmd);
}

CGImageRef hook_AVCapturePhoto_CGImageRepresentation(id self, SEL _cmd) {
    if (spoofCameraEnabled && g_cachedPhotoCGImage) {
        NSLog(@"[LC] 📷 Returning spoofed photo CGImage");
        return g_cachedPhotoCGImage;
    }
    return original_AVCapturePhoto_CGImageRepresentation(self, _cmd);
}

NSData *hook_AVCapturePhoto_fileDataRepresentation(id self, SEL _cmd) {
    if (spoofCameraEnabled && g_cachedPhotoJPEGData) {
        NSLog(@"[LC] 📷 Returning spoofed photo JPEG data (%lu bytes)", (unsigned long)g_cachedPhotoJPEGData.length);
        return g_cachedPhotoJPEGData;
    }
    return original_AVCapturePhoto_fileDataRepresentation(self, _cmd);
}

// Add this cleanup function:
static void cleanupPhotoCache(void) {
    if (g_cachedPhotoPixelBuffer) {
        CVPixelBufferRelease(g_cachedPhotoPixelBuffer);
        g_cachedPhotoPixelBuffer = NULL;
    }
    if (g_cachedPhotoCGImage) {
        CGImageRelease(g_cachedPhotoCGImage);
        g_cachedPhotoCGImage = NULL;
    }
    g_cachedPhotoJPEGData = nil;
}

// Photo capture: Revert to passing nil for resolvedSettings to avoid compiler issues.
@implementation AVCapturePhotoOutput(LiveContainerSimpleSpoof)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📷 Intercepting photo capture - pre-caching spoofed data");
        
        // Pre-cache spoofed photo data BEFORE calling delegate
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            cachePhotoDataFromSampleBuffer(spoofedFrame);
            CFRelease(spoofedFrame);
        }
        
        // Call original to trigger normal photo capture flow
        // The accessor hooks will return our cached spoofed data
        [self lc_capturePhotoWithSettings:settings delegate:delegate];
        return;
    }
    
    // Normal path when spoofing disabled
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}
@end


// Add this function pointer at the top:
static void (*original_AVCapturePhotoCaptureDelegate_didFinishProcessingPhoto)(id, SEL, AVCapturePhotoOutput *, AVCapturePhoto *, NSError *);

// Add this hook function:
void hook_AVCapturePhotoCaptureDelegate_didFinishProcessingPhoto(
    id self, SEL _cmd, 
    AVCapturePhotoOutput *photoOutput, 
    AVCapturePhoto *capturedPhoto, 
    NSError *error) {
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📷 Photo capture completed - ensuring spoofed data is cached");
        
        // Refresh cached data one more time to ensure it's available for accessor calls
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            cachePhotoDataFromSampleBuffer(spoofedFrame);
            CFRelease(spoofedFrame);
        }
    }
    
    // Call original delegate
    if (original_AVCapturePhotoCaptureDelegate_didFinishProcessingPhoto) {
        original_AVCapturePhotoCaptureDelegate_didFinishProcessingPhoto(self, _cmd, photoOutput, capturedPhoto, error);
    }
}

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
        spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
        spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
        spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
        spoofCameraLoop = (guestAppInfo[@"spoofCameraLoop"] != nil) ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;

        NSLog(@"[LC] Config: Enabled=%d, Type=%@, ImagePath='%@', VideoPath='%@', Loop=%d, InitialTargetRes=%.0fx%.0f",
              spoofCameraEnabled, spoofCameraType, spoofCameraImagePath, spoofCameraVideoPath, spoofCameraLoop, targetResolution.width, targetResolution.height);
        
        videoProcessingQueue = dispatch_queue_create("com.livecontainer.videoprocessingqueue", DISPATCH_QUEUE_SERIAL);

        // 1. Setup primary image resources. This attempts to load user image or default blue.
        // It will also try to set lastGoodSpoofedPixelBuffer.
        setupImageSpoofingResources();

        // 2. Failsafe: If lastGoodSpoofedPixelBuffer is still NULL, create an emergency one.
        if (!lastGoodSpoofedPixelBuffer) {
            NSLog(@"[LC] Warning: lastGoodSpoofedPixelBuffer is NULL after primary image setup. Creating emergency fallback.");
            CVPixelBufferRef emergencyPixelBuffer = NULL;
            CGSize emergencySize = targetResolution; // Use current targetResolution

            NSDictionary *pixelAttributes = @{
                (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
                (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
            };
            CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                                  (size_t)emergencySize.width, (size_t)emergencySize.height,
                                                  kCVPixelFormatType_32BGRA,
                                                  (__bridge CFDictionaryRef)pixelAttributes,
                                                  &emergencyPixelBuffer);

            if (status == kCVReturnSuccess && emergencyPixelBuffer) {
                CVPixelBufferLockBaseAddress(emergencyPixelBuffer, 0);
                void *baseAddress = CVPixelBufferGetBaseAddress(emergencyPixelBuffer);
                CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
                CGContextRef cgContext = CGBitmapContextCreate(baseAddress,
                                                               emergencySize.width, emergencySize.height,
                                                               8, CVPixelBufferGetBytesPerRow(emergencyPixelBuffer), colorSpace,
                                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
                if (cgContext) {
                    CGContextSetRGBFillColor(cgContext, 1.0, 0.0, 1.0, 1.0); // Magenta
                    CGContextFillRect(cgContext, CGRectMake(0, 0, emergencySize.width, emergencySize.height));
                    
                    NSString *text = @"EMERGENCY\nFALLBACK";
                    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
                    style.alignment = NSTextAlignmentCenter;
                    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:emergencySize.width * 0.04],
                                             NSForegroundColorAttributeName: [UIColor blackColor], // Black text on magenta
                                             NSParagraphStyleAttributeName: style };
                    CGSize textSize = [text sizeWithAttributes:attrs];
                    CGRect textRect = CGRectMake((emergencySize.width - textSize.width) / 2,
                                                 (emergencySize.height - textSize.height) / 2,
                                                 textSize.width, textSize.height);
                    
                    UIGraphicsPushContext(cgContext);
                    [text drawInRect:textRect withAttributes:attrs];
                    UIGraphicsPopContext();
                    
                    CGContextRelease(cgContext);
                } else {
                    NSLog(@"[LC] Failed to create CGContext for emergency buffer. It might appear as uninitialized (black).");
                }
                CGColorSpaceRelease(colorSpace);
                CVPixelBufferUnlockBaseAddress(emergencyPixelBuffer, 0);

                CMVideoFormatDescriptionRef emergencyFormatDesc = NULL;
                CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, emergencyPixelBuffer, &emergencyFormatDesc);
                updateLastGoodSpoofedFrame(emergencyPixelBuffer, emergencyFormatDesc); // This retains them
                
                if (emergencyFormatDesc) CFRelease(emergencyFormatDesc);
                CVPixelBufferRelease(emergencyPixelBuffer); // Release our local instance
                NSLog(@"[LC] Emergency fallback pixel buffer created and set as lastGood.");
            } else {
                NSLog(@"[LC] CRITICAL: Failed to create CVPixelBuffer for emergency fallback. Status: %d. Spoofing may be unreliable.", status);
            }
        }

        // 3. Setup video resources if in video mode
        if (spoofCameraEnabled && [spoofCameraType isEqualToString:@"video"]) {
            if (spoofCameraVideoPath && spoofCameraVideoPath.length > 0) {
                NSLog(@"[LC] Video mode configured. Initiating video resource setup...");
                setupVideoSpoofingResources(); 
            } else {
                NSLog(@"[LC] Video mode configured, but no video path. Will use image fallback (static, default blue, or emergency).");
            }
        }
        
        // 4. Check image mode status
        if (spoofCameraEnabled && ![spoofCameraType isEqualToString:@"video"]) {
            if (!staticImageSpoofBuffer) {
                 NSLog(@"[LC] ⚠️ Image mode: Primary staticImageSpoofBuffer (user/default blue) failed. Relying on emergency fallback.");
            } else if (!lastGoodSpoofedPixelBuffer) {
                 NSLog(@"[LC] ⚠️ Image mode: lastGoodSpoofedPixelBuffer is NULL despite staticImageSpoofBuffer potentially being OK. This is unexpected.");
            }
        }
        
        if (!spoofCameraEnabled && !resolutionDetected) {
             NSLog(@"[LC] Spoofing disabled, but resolution detection will run on first real frame.");
        }

        // 5. Apply hooks
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSLog(@"[LC] Applying AVFoundation hooks...");
            swizzle([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
            swizzle([AVCapturePhotoOutput class], @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
            
            // ADD THESE NEW HOOKS:
            // Hook photo accessor methods directly on AVCapturePhoto class
            Method pixelBufferMethod = class_getInstanceMethod([AVCapturePhoto class], @selector(pixelBuffer));
            if (pixelBufferMethod) {
                original_AVCapturePhoto_pixelBuffer = (CVPixelBufferRef (*)(id, SEL))method_getImplementation(pixelBufferMethod);
                method_setImplementation(pixelBufferMethod, (IMP)hook_AVCapturePhoto_pixelBuffer);
                NSLog(@"[LC] ✅ Photo pixelBuffer hook installed");
            }
            
            Method cgImageMethod = class_getInstanceMethod([AVCapturePhoto class], @selector(CGImageRepresentation));
            if (cgImageMethod) {
                original_AVCapturePhoto_CGImageRepresentation = (CGImageRef (*)(id, SEL))method_getImplementation(cgImageMethod);
                method_setImplementation(cgImageMethod, (IMP)hook_AVCapturePhoto_CGImageRepresentation);
                NSLog(@"[LC] ✅ Photo CGImageRepresentation hook installed");
            }
            
            Method fileDataMethod = class_getInstanceMethod([AVCapturePhoto class], @selector(fileDataRepresentation));
            if (fileDataMethod) {
                original_AVCapturePhoto_fileDataRepresentation = (NSData *(*)(id, SEL))method_getImplementation(fileDataMethod);
                method_setImplementation(fileDataMethod, (IMP)hook_AVCapturePhoto_fileDataRepresentation);
                NSLog(@"[LC] ✅ Photo fileDataRepresentation hook installed");
            }
            
            // Hook photo delegate (using runtime method discovery like cj)
            // Class photoCaptureDelegate = NSClassFromString(@"AVCapturePhotoCaptureDelegate");
            // if (photoCaptureDelegate) {
            //     Method delegateMethod = class_getInstanceMethod(photoCaptureDelegate, @selector(captureOutput:didFinishProcessingPhoto:error:));
            //     if (delegateMethod) {
            //         original_AVCapturePhotoCaptureDelegate_didFinishProcessingPhoto = 
            //             (void (*)(id, SEL, AVCapturePhotoOutput *, AVCapturePhoto *, NSError *))method_getImplementation(delegateMethod);
            //         method_setImplementation(delegateMethod, (IMP)hook_AVCapturePhotoCaptureDelegate_didFinishProcessingPhoto);
            //         NSLog(@"[LC] ✅ Photo delegate hook installed");
            //     }
            // }
            
            NSLog(@"[LC] ✅ AVFoundation Hooks applied.");
        });
        
        if (spoofCameraEnabled) {
             NSLog(@"[LC] ✅ Spoofing initialized. Configured mode: %@. LastGoodBuffer is %s.", 
                   spoofCameraType, lastGoodSpoofedPixelBuffer ? "VALID" : "NULL (Problem!)");
        }

    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception during AVFoundationGuestHooksInit: %@", exception);
    }
}



