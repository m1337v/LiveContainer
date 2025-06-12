//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Comprehensive camera spoofing with hierarchical hooks
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <MobileCoreServices/MobileCoreServices.h> 
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

// pragma MARK: - Global State

// Defensive macros
#define SAFE_CALL(obj, selector, ...) \
    ({ \
        typeof(obj) _obj = (obj); \
        (_obj && [_obj respondsToSelector:@selector(selector)]) ? [_obj selector __VA_ARGS__] : nil; \
    })

#define SAFE_RETAIN(obj) \
    ({ \
        typeof(obj) _obj = (obj); \
        _obj ? CFRetain(_obj) : NULL; \
        _obj; \
    })

#define SAFE_RELEASE(obj) \
    do { \
        if (obj) { \
            CFRelease(obj); \
            obj = NULL; \
        } \
    } while(0)

// Core configuration
static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraVideoPath = @"";
static BOOL spoofCameraLoop = YES;

// Resolution and fallback management
static CGSize targetResolution = {1080, 1920};
static BOOL resolutionDetected = NO;
static CVPixelBufferRef lastGoodSpoofedPixelBuffer = NULL;
static CMVideoFormatDescriptionRef lastGoodSpoofedFormatDesc = NULL;
static OSType lastRequestedFormat = 0;

// Image spoofing resources
static CVPixelBufferRef staticImageSpoofBuffer = NULL;

// Video spoofing resources
static AVPlayer *videoSpoofPlayer = nil;
static AVPlayerItemVideoOutput *videoSpoofPlayerOutput = nil;
static AVPlayerItemVideoOutput *yuvOutput1 = nil;  // For 420v format
static AVPlayerItemVideoOutput *yuvOutput2 = nil;  // For 420f format
static dispatch_queue_t videoProcessingQueue = NULL;
static BOOL isVideoSetupSuccessfully = NO;
static id playerDidPlayToEndTimeObserver = nil;

// Photo data cache
static CVPixelBufferRef g_cachedPhotoPixelBuffer = NULL;
static CGImageRef g_cachedPhotoCGImage = NULL;
static NSData *g_cachedPhotoJPEGData = nil;

// pragma MARK: - Helper Interface

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

// pragma MARK: - Forward Declarations

// Core functions
static void setupImageSpoofingResources(void);
static void setupVideoSpoofingResources(void);
static CMSampleBufferRef createSpoofedSampleBuffer(void);
static void cachePhotoDataFromSampleBuffer(CMSampleBufferRef sampleBuffer);
static void cleanupPhotoCache(void);

// Level 1 hooks (Core Video)
static CVReturn (*original_CVPixelBufferCreate)(CFAllocatorRef, size_t, size_t, OSType, CFDictionaryRef, CVPixelBufferRef *);
CVReturn hook_CVPixelBufferCreate(CFAllocatorRef allocator, size_t width, size_t height, OSType pixelFormatType, CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *pixelBufferOut);

// Level 2 hooks (Device Level)
// Device enumeration hooks declared in @implementation

// Level 3 hooks (Device Input Level)
// Device input hooks declared in @implementation

// Level 4 hooks (Session Level)
// Session hooks declared in @implementation

// Level 5 hooks (Output Level)
// Output hooks declared in @implementation

// Level 6 hooks (Photo Accessor Level)
static CVPixelBufferRef (*original_AVCapturePhoto_pixelBuffer)(id, SEL);
static CGImageRef (*original_AVCapturePhoto_CGImageRepresentation)(id, SEL);
static NSData *(*original_AVCapturePhoto_fileDataRepresentation)(id, SEL);
CVPixelBufferRef hook_AVCapturePhoto_pixelBuffer(id self, SEL _cmd);
CGImageRef hook_AVCapturePhoto_CGImageRepresentation(id self, SEL _cmd);
NSData *hook_AVCapturePhoto_fileDataRepresentation(id self, SEL _cmd);

// pragma MARK: - Core Utilities

// Pixel buffer utilities
static CIContext *sharedCIContext = nil;

// Replace the createScaledPixelBuffer function with this improved version:
static CVPixelBufferRef createScaledPixelBuffer(CVPixelBufferRef sourceBuffer, CGSize scaleToSize) {
    if (!sourceBuffer) return NULL;

    size_t sourceWidth = CVPixelBufferGetWidth(sourceBuffer);
    size_t sourceHeight = CVPixelBufferGetHeight(sourceBuffer);
    OSType sourceFormat = CVPixelBufferGetPixelFormatType(sourceBuffer);

    // CRITICAL: Match the target format to what was requested
    OSType targetFormat = kCVPixelFormatType_32BGRA; // Default
    if (lastRequestedFormat != 0) {
        targetFormat = lastRequestedFormat;
        NSLog(@"[LC] 🎯 Creating buffer in requested format: %c%c%c%c", 
              (targetFormat >> 24) & 0xFF, (targetFormat >> 16) & 0xFF, 
              (targetFormat >> 8) & 0xFF, targetFormat & 0xFF);
    }

    // If source already matches target size and format, return as-is
    if (sourceWidth == (size_t)scaleToSize.width && 
        sourceHeight == (size_t)scaleToSize.height && 
        sourceFormat == targetFormat) {
        CVPixelBufferRetain(sourceBuffer);
        return sourceBuffer;
    }

    CVPixelBufferRef scaledPixelBuffer = NULL;
    NSDictionary *pixelAttributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    // IMPROVEMENT: Create buffer in the requested format, not always BGRA
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          (size_t)scaleToSize.width,
                                          (size_t)scaleToSize.height,
                                          targetFormat, // Use requested format!
                                          (__bridge CFDictionaryRef)pixelAttributes,
                                          &scaledPixelBuffer);
    if (status != kCVReturnSuccess || !scaledPixelBuffer) {
        NSLog(@"[LC] Error creating scaled pixel buffer with format %c%c%c%c: %d", 
              (targetFormat >> 24) & 0xFF, (targetFormat >> 16) & 0xFF, 
              (targetFormat >> 8) & 0xFF, targetFormat & 0xFF, status);
        return NULL;
    }

    if (!sharedCIContext) {
        sharedCIContext = [CIContext contextWithOptions:nil];
        if (!sharedCIContext) {
            NSLog(@"[LC] CRITICAL: Failed to create shared CIContext");
            CVPixelBufferRelease(scaledPixelBuffer);
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

    // CRITICAL: Render to the target format buffer
    [sharedCIContext render:ciImage toCVPixelBuffer:scaledPixelBuffer];
    return scaledPixelBuffer;
}

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
        CVPixelBufferRetain(lastGoodSpoofedPixelBuffer);
    }
    if (newFormatDesc) {
        lastGoodSpoofedFormatDesc = newFormatDesc;
        CFRetain(lastGoodSpoofedFormatDesc);
    }
}

// pragma MARK: - Frame Generation Logic

static BOOL isValidPixelFormat(OSType format) {
    switch (format) {
        case kCVPixelFormatType_32BGRA:
            return YES;
        case 875704422: // '420v' - YUV 4:2:0 video range
            return YES;
        case 875704438: // '420f' - YUV 4:2:0 full range  
            return YES;
        // NOTE: Don't use the constants as they have the same values as the literals above
        // case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: // Same as 875704438
        // case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:  // Same as 875704422
        default:
            NSLog(@"[LC] ⚠️ Unknown pixel format: %c%c%c%c (%u)", 
                  (format >> 24) & 0xFF, (format >> 16) & 0xFF, 
                  (format >> 8) & 0xFF, format & 0xFF, (unsigned int)format);
            return NO;
    }
}

// Replace crash-resistant version:
static CMSampleBufferRef createSpoofedSampleBuffer() {
    @try {
        // DEFENSIVE: Validate state before proceeding
        if (!spoofCameraEnabled) {
            return NULL;
        }

        // Get desired format from current context if available
        OSType preferredFormat = kCVPixelFormatType_32BGRA; // Safe default
        
        // Try to match the format being requested by the app
        if (lastRequestedFormat != 0 && isValidPixelFormat(lastRequestedFormat)) {
            preferredFormat = lastRequestedFormat;
        }
        
        CVPixelBufferRef sourcePixelBuffer = NULL;
        BOOL ownSourcePixelBuffer = NO;

        // 1. Try video frame first with format matching (with defensive checks)
        if (isVideoSetupSuccessfully && videoSpoofPlayer && videoSpoofPlayer.currentItem &&
            videoSpoofPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay && videoSpoofPlayer.rate > 0.0f) {
            
            CMTime playerTime = [videoSpoofPlayer.currentItem currentTime];
            
            // DEFENSIVE: Check if time is valid
            if (CMTIME_IS_VALID(playerTime) && !CMTIME_IS_INDEFINITE(playerTime)) {
                // IMPROVEMENT: Better format matching with fallback
                AVPlayerItemVideoOutput *bestOutput = videoSpoofPlayerOutput; // Default BGRA
                NSString *formatName = @"BGRA";
                
                // Try to match exact format first
                if (preferredFormat == 875704422 && yuvOutput1) { // '420v'
                    if ([yuvOutput1 hasNewPixelBufferForItemTime:playerTime]) {
                        bestOutput = yuvOutput1;
                        formatName = @"420v";
                    }
                } else if (preferredFormat == 875704438 && yuvOutput2) { // '420f'
                    if ([yuvOutput2 hasNewPixelBufferForItemTime:playerTime]) {
                        bestOutput = yuvOutput2;
                        formatName = @"420f";
                    }
                }
                
                // DEFENSIVE: Check if output is valid and has frames
                if (bestOutput && [bestOutput hasNewPixelBufferForItemTime:playerTime]) {
                    sourcePixelBuffer = [bestOutput copyPixelBufferForItemTime:playerTime itemTimeForDisplay:NULL];
                    if (sourcePixelBuffer) {
                        ownSourcePixelBuffer = YES;
                        NSLog(@"[LC] Using video output: %@ for requested format: %c%c%c%c", 
                            formatName,
                            (preferredFormat >> 24) & 0xFF, (preferredFormat >> 16) & 0xFF, 
                            (preferredFormat >> 8) & 0xFF, preferredFormat & 0xFF);
                    }
                }
            }
        }

        // 2. Fallback to static image (with defensive checks)
        if (!sourcePixelBuffer && staticImageSpoofBuffer) {
            sourcePixelBuffer = staticImageSpoofBuffer;
            CVPixelBufferRetain(sourcePixelBuffer);
            ownSourcePixelBuffer = YES;
        }
        
        // DEFENSIVE: Validate source buffer before scaling
        if (!sourcePixelBuffer) {
            NSLog(@"[LC] ⚠️ No source buffer available");
            return NULL;
        }
        
        CVPixelBufferRef finalScaledPixelBuffer = NULL;
        finalScaledPixelBuffer = createScaledPixelBuffer(sourcePixelBuffer, targetResolution);
        
        if (ownSourcePixelBuffer) {
            CVPixelBufferRelease(sourcePixelBuffer);
        }

        // 3. Last resort - use previous good frame (with defensive checks)
        if (!finalScaledPixelBuffer && lastGoodSpoofedPixelBuffer) {
            finalScaledPixelBuffer = lastGoodSpoofedPixelBuffer;
            CVPixelBufferRetain(finalScaledPixelBuffer);
        }

        if (!finalScaledPixelBuffer) {
            NSLog(@"[LC] ❌ CRITICAL: No pixel buffer available for spoofing");
            return NULL;
        }

        // 4. Create format description (with defensive checks)
        CMVideoFormatDescriptionRef currentFormatDesc = NULL;
        if (finalScaledPixelBuffer == lastGoodSpoofedPixelBuffer && lastGoodSpoofedFormatDesc) {
            currentFormatDesc = lastGoodSpoofedFormatDesc;
            CFRetain(currentFormatDesc);
        } else {
            OSStatus formatDescStatus = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, finalScaledPixelBuffer, &currentFormatDesc);
            if (formatDescStatus != noErr || !currentFormatDesc) {
                NSLog(@"[LC] ❌ Failed to create format description: %d", (int)formatDescStatus);
                CVPixelBufferRelease(finalScaledPixelBuffer);
                return NULL;
            }
        }
        
        // 5. Update last good frame if we created a new one
        if (finalScaledPixelBuffer != lastGoodSpoofedPixelBuffer) {
            updateLastGoodSpoofedFrame(finalScaledPixelBuffer, currentFormatDesc);
        }

        // 6. Create sample buffer (with defensive timing)
        CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), NSEC_PER_SEC);
        CMSampleTimingInfo timingInfo = {
            .duration = CMTimeMake(1, 30),
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
        if (finalScaledPixelBuffer) CVPixelBufferRelease(finalScaledPixelBuffer);

        if (result != noErr || !sampleBuffer) {
            NSLog(@"[LC] ❌ Failed to create CMSampleBuffer: %d", (int)result);
            return NULL;
        }
        
        return sampleBuffer;
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ CRITICAL Exception in createSpoofedSampleBuffer: %@", exception);
        return NULL;
    }
}

// pragma MARK: - Resource Setup

static void setupImageSpoofingResources() {
    NSLog(@"[LC] 🖼️ Setting up image spoofing resources: %.0fx%.0f", targetResolution.width, targetResolution.height);
    
    if (staticImageSpoofBuffer) {
        CVPixelBufferRelease(staticImageSpoofBuffer);
        staticImageSpoofBuffer = NULL;
    }

    // Create default gradient image
    UIImage *sourceImage = nil;
    UIGraphicsBeginImageContextWithOptions(targetResolution, YES, 1.0);
    CGContextRef uigraphicsContext = UIGraphicsGetCurrentContext();
    if (uigraphicsContext) {
        // Blue gradient background
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGFloat colors[] = { 0.2, 0.4, 0.8, 1.0, 0.1, 0.2, 0.4, 1.0 };
        CGFloat locations[] = {0.0, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, locations, 2);
        CGContextDrawLinearGradient(uigraphicsContext, gradient, CGPointMake(0,0), CGPointMake(0,targetResolution.height), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(colorSpace);

        // Add text
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
        NSLog(@"[LC] CRITICAL: Failed to create default spoof image");
        return; 
    }
    
    // Convert to CVPixelBuffer
    CGImageRef cgImage = sourceImage.CGImage;
    if (!cgImage) {
        NSLog(@"[LC] CRITICAL: CGImage is NULL");
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
        NSLog(@"[LC] Failed to create CVPixelBuffer for static image: %d", cvRet);
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
        CGContextDrawImage(context, CGRectMake(0, 0, targetResolution.width, targetResolution.height), cgImage);
        CGContextRelease(context);
    }
    CGColorSpaceRelease(rgbColorSpace);
    CVPixelBufferUnlockBaseAddress(staticImageSpoofBuffer, 0);

    if (staticImageSpoofBuffer) {
        NSLog(@"[LC] ✅ Static image buffer created successfully");
        CMVideoFormatDescriptionRef tempFormatDesc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, staticImageSpoofBuffer, &tempFormatDesc);
        updateLastGoodSpoofedFrame(staticImageSpoofBuffer, tempFormatDesc);
        if (tempFormatDesc) CFRelease(tempFormatDesc);
    }
}

static void setupVideoSpoofingResources() {
    NSLog(@"[LC] 🎬 Setting up video spoofing: %@", spoofCameraVideoPath);
    if (!spoofCameraVideoPath || spoofCameraVideoPath.length == 0) {
        isVideoSetupSuccessfully = NO;
        return;
    }
    
    NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath]) {
        NSLog(@"[LC] Video file not found: %@", spoofCameraVideoPath);
        isVideoSetupSuccessfully = NO;
        return;
    }

    // IMPROVEMENT: Clean up ALL outputs first
    if (videoSpoofPlayer && videoSpoofPlayer.currentItem) {
        if (videoSpoofPlayerOutput) {
            [videoSpoofPlayer.currentItem removeOutput:videoSpoofPlayerOutput];
            videoSpoofPlayerOutput = nil;
        }
        if (yuvOutput1) {
            [videoSpoofPlayer.currentItem removeOutput:yuvOutput1];
            yuvOutput1 = nil;
        }
        if (yuvOutput2) {
            [videoSpoofPlayer.currentItem removeOutput:yuvOutput2];
            yuvOutput2 = nil;
        }
    }
    
    // Create multiple format outputs for better compatibility (CaptureJailed pattern)
    NSDictionary *bgraAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    
    NSDictionary *yuv420vAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(875704422), // '420v'
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    
    NSDictionary *yuv420fAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(875704438), // '420f'
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    AVURLAsset *asset = [AVURLAsset assetWithURL:videoURL];
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        NSError *error = nil;
        AVKeyValueStatus status = [asset statusOfValueForKey:@"tracks" error:&error];

        if (status != AVKeyValueStatusLoaded) {
            NSLog(@"[LC] Failed to load video tracks: %@", error);
            isVideoSetupSuccessfully = NO;
            return;
        }

        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (tracks.count == 0) {
            NSLog(@"[LC] No video tracks found");
            isVideoSetupSuccessfully = NO;
            return;
        }

        // Clean up existing player
        if (videoSpoofPlayer) {
            [videoSpoofPlayer pause];
            if (playerDidPlayToEndTimeObserver) {
                [[NSNotificationCenter defaultCenter] removeObserver:playerDidPlayToEndTimeObserver];
                playerDidPlayToEndTimeObserver = nil;
            }
            videoSpoofPlayer = nil;
        }

        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
        videoSpoofPlayer = [AVPlayer playerWithPlayerItem:playerItem];
        videoSpoofPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        videoSpoofPlayer.muted = YES;

        // CREATE ALL THREE OUTPUTS (like CaptureJailed)
        videoSpoofPlayerOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:bgraAttributes];
        yuvOutput1 = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:yuv420vAttributes];
        yuvOutput2 = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:yuv420fAttributes];
        
        dispatch_async(videoProcessingQueue, ^{
            while (playerItem.status != AVPlayerItemStatusReadyToPlay) {
                [NSThread sleepForTimeInterval:0.05];
                if (playerItem.status == AVPlayerItemStatusFailed) {
                     NSLog(@"[LC] Player item failed: %@", playerItem.error);
                     isVideoSetupSuccessfully = NO;
                     return;
                }
            }
            
            // ADD ALL THREE OUTPUTS TO PLAYER ITEM
            if (![playerItem.outputs containsObject:videoSpoofPlayerOutput]) {
                [playerItem addOutput:videoSpoofPlayerOutput];
                NSLog(@"[LC] ✅ Added BGRA output");
            }
            if (![playerItem.outputs containsObject:yuvOutput1]) {
                [playerItem addOutput:yuvOutput1];
                NSLog(@"[LC] ✅ Added 420v output");
            }
            if (![playerItem.outputs containsObject:yuvOutput2]) {
                [playerItem addOutput:yuvOutput2];
                NSLog(@"[LC] ✅ Added 420f output");
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
            NSLog(@"[LC] ✅ Video spoofing ready with 3 format outputs");
        });
    }];
}

//pragma MARK: - Centralized Frame Manager (cj Pattern)

@interface GetFrame : NSObject
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame preserveOrientation:(BOOL)preserve;
+ (CVPixelBufferRef)getCurrentFramePixelBuffer:(OSType)requestedFormat;
+ (void)setCurrentVideoPath:(NSString *)path;
+ (UIWindow *)getKeyWindow;
@end

// Static variables
static NSString *currentVideoPath = nil;
static AVPlayer *frameExtractionPlayer = nil;
static AVPlayerItemVideoOutput *bgraOutput = nil;
static AVPlayerItemVideoOutput *yuv420vOutput = nil;
static AVPlayerItemVideoOutput *yuv420fOutput = nil;

@implementation GetFrame

// Fix the GetFrame getCurrentFrame method to better handle sample buffer creation:
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame preserveOrientation:(BOOL)preserve {
    if (!spoofCameraEnabled) {
        return originalFrame; // Pass through when disabled
    }
    
    if (!frameExtractionPlayer || !frameExtractionPlayer.currentItem) {
        NSLog(@"[GetFrame] No player available, returning NULL (let primary system handle)");
        return NULL; // Return NULL instead of fallback - let primary system handle
    }
    
    CMTime currentTime = [frameExtractionPlayer.currentItem currentTime];
    
    // CRITICAL: Check if player is actually ready
    if (frameExtractionPlayer.currentItem.status != AVPlayerItemStatusReadyToPlay) {
        NSLog(@"[GetFrame] Player not ready, returning NULL");
        return NULL;
    }
    
    // CRITICAL: CaptureJailed's format detection from originalFrame
    OSType requestedFormat = kCVPixelFormatType_32BGRA; // Default
    if (originalFrame) {
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(originalFrame);
        if (formatDesc) {
            requestedFormat = CMFormatDescriptionGetMediaSubType(formatDesc);
        }
    }
    
    NSLog(@"[GetFrame] Processing format: %c%c%c%c", 
          (requestedFormat >> 24) & 0xFF, (requestedFormat >> 16) & 0xFF, 
          (requestedFormat >> 8) & 0xFF, requestedFormat & 0xFF);
    
    // CRITICAL: CaptureJailed's exact format selection algorithm
    AVPlayerItemVideoOutput *selectedOutput = bgraOutput; // Default
    NSString *outputType = @"BGRA-default";
    
    switch (requestedFormat) {
        case 875704422: // '420v'
            if (yuv420vOutput && [yuv420vOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = yuv420vOutput;
                outputType = @"420v-direct";
            } else if (bgraOutput && [bgraOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = bgraOutput;
                outputType = @"BGRA-fallback-from-420v";
            }
            break;
            
        case 875704438: // '420f'
            if (yuv420fOutput && [yuv420fOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = yuv420fOutput;
                outputType = @"420f-direct";
            } else if (yuv420vOutput && [yuv420vOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = yuv420vOutput;
                outputType = @"420v-fallback-from-420f";
            } else if (bgraOutput && [bgraOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = bgraOutput;
                outputType = @"BGRA-fallback-from-420f";
            }
            break;
            
        default: // BGRA or unknown
            if (bgraOutput && [bgraOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = bgraOutput;
                outputType = @"BGRA-direct";
            } else if (yuv420vOutput && [yuv420vOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = yuv420vOutput;
                outputType = @"420v-fallback-from-unknown";
            }
            break;
    }
    
    if (!selectedOutput || ![selectedOutput hasNewPixelBufferForItemTime:currentTime]) {
        NSLog(@"[GetFrame] No frames available from outputs");
        return NULL; // Let primary system handle
    }
    
    CVPixelBufferRef pixelBuffer = [selectedOutput copyPixelBufferForItemTime:currentTime itemTimeForDisplay:NULL];
    if (!pixelBuffer) {
        NSLog(@"[GetFrame] Failed to get pixel buffer");
        return NULL;
    }
    
    // CRITICAL: Scale the pixel buffer to target resolution using existing system
    CVPixelBufferRef scaledBuffer = createScaledPixelBuffer(pixelBuffer, targetResolution);
    CVPixelBufferRelease(pixelBuffer); // Release original
    
    if (!scaledBuffer) {
        NSLog(@"[GetFrame] Failed to scale buffer");
        return NULL;
    }
    
    // CRITICAL: Create sample buffer with proper timing
    CMSampleBufferRef newSampleBuffer = NULL;
    CMVideoFormatDescriptionRef videoFormatDesc = NULL;
    
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault, scaledBuffer, &videoFormatDesc);
    
    if (status != noErr || !videoFormatDesc) {
        NSLog(@"[GetFrame] Failed to create format description: %d", status);
        CVPixelBufferRelease(scaledBuffer);
        return NULL;
    }
    
    // CRITICAL: Use proper timing - either from original or current time
    CMSampleTimingInfo timingInfo;
    if (originalFrame) {
        // Try to get timing from original frame
        CMItemCount timingCount = 0;
        CMSampleBufferGetSampleTimingInfoArray(originalFrame, 0, NULL, &timingCount);
        
        if (timingCount > 0) {
            CMSampleBufferGetSampleTimingInfoArray(originalFrame, 1, &timingInfo, &timingCount);
        } else {
            // Fallback timing
            timingInfo = (CMSampleTimingInfo){
                .duration = CMTimeMake(1, 30),
                .presentationTimeStamp = currentTime,
                .decodeTimeStamp = kCMTimeInvalid
            };
        }
    } else {
        // Create new timing
        timingInfo = (CMSampleTimingInfo){
            .duration = CMTimeMake(1, 30),
            .presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), NSEC_PER_SEC),
            .decodeTimeStamp = kCMTimeInvalid
        };
    }
    
    status = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        scaledBuffer,
        videoFormatDesc,
        &timingInfo,
        &newSampleBuffer
    );
    
    CFRelease(videoFormatDesc);
    CVPixelBufferRelease(scaledBuffer);
    
    if (status != noErr || !newSampleBuffer) {
        NSLog(@"[GetFrame] Failed to create sample buffer: %d", status);
        return NULL;
    }
    
    OSType actualFormat = CVPixelBufferGetPixelFormatType(scaledBuffer);
    NSLog(@"[GetFrame] ✅ Frame created via %@: req=%c%c%c%c → actual=%c%c%c%c", 
          outputType,
          (requestedFormat >> 24) & 0xFF, (requestedFormat >> 16) & 0xFF, 
          (requestedFormat >> 8) & 0xFF, requestedFormat & 0xFF,
          (actualFormat >> 24) & 0xFF, (actualFormat >> 16) & 0xFF, 
          (actualFormat >> 8) & 0xFF, actualFormat & 0xFF);
    
    return newSampleBuffer;
}

+ (CVPixelBufferRef)getCurrentFramePixelBuffer:(OSType)requestedFormat {
    if (!spoofCameraEnabled) {
        return NULL;
    }
    
    if (!frameExtractionPlayer || !frameExtractionPlayer.currentItem) {
        NSLog(@"[GetFrame] No player available for pixel buffer extraction");
        return NULL;
    }
    
    CMTime currentTime = [frameExtractionPlayer.currentItem currentTime];
    
    // Select output based on requested format
    AVPlayerItemVideoOutput *selectedOutput = bgraOutput; // Default
    
    switch (requestedFormat) {
        case 875704422: // '420v'
            if (yuv420vOutput && [yuv420vOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = yuv420vOutput;
            }
            break;
        case 875704438: // '420f'
            if (yuv420fOutput && [yuv420fOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = yuv420fOutput;
            }
            break;
        default: // BGRA
            if (bgraOutput && [bgraOutput hasNewPixelBufferForItemTime:currentTime]) {
                selectedOutput = bgraOutput;
            }
            break;
    }
    
    if (selectedOutput && [selectedOutput hasNewPixelBufferForItemTime:currentTime]) {
        CVPixelBufferRef pixelBuffer = [selectedOutput copyPixelBufferForItemTime:currentTime itemTimeForDisplay:NULL];
        
        if (pixelBuffer) {
            OSType actualFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
            NSLog(@"[GetFrame] Extracted pixel buffer: req=%c%c%c%c → actual=%c%c%c%c", 
                  (requestedFormat >> 24) & 0xFF, (requestedFormat >> 16) & 0xFF, 
                  (requestedFormat >> 8) & 0xFF, requestedFormat & 0xFF,
                  (actualFormat >> 24) & 0xFF, (actualFormat >> 16) & 0xFF, 
                  (actualFormat >> 8) & 0xFF, actualFormat & 0xFF);
        }
        
        return pixelBuffer; // Caller must release
    }
    
    NSLog(@"[GetFrame] No pixel buffer available for format: %c%c%c%c", 
          (requestedFormat >> 24) & 0xFF, (requestedFormat >> 16) & 0xFF, 
          (requestedFormat >> 8) & 0xFF, requestedFormat & 0xFF);
    return NULL;
}

+ (void)setCurrentVideoPath:(NSString *)path {
    if ([path isEqualToString:currentVideoPath]) {
        return; // Already set
    }
    
    currentVideoPath = path;
    [self setupPlayerWithPath:path];
}

+ (void)setupPlayerWithPath:(NSString *)path {
    // Clean up existing player like CaptureJailed
    if (frameExtractionPlayer) {
        [frameExtractionPlayer pause];
        
        // Remove old outputs like CaptureJailed does
        if (frameExtractionPlayer.currentItem) {
            if (bgraOutput) [frameExtractionPlayer.currentItem removeOutput:bgraOutput];
            if (yuv420vOutput) [frameExtractionPlayer.currentItem removeOutput:yuv420vOutput];
            if (yuv420fOutput) [frameExtractionPlayer.currentItem removeOutput:yuv420fOutput];
        }
        
        frameExtractionPlayer = nil;
        bgraOutput = nil;
        yuv420vOutput = nil;
        yuv420fOutput = nil;
    }
    
    if (!path || path.length == 0) {
        NSLog(@"[GetFrame] No video path provided");
        return;
    }
    
    NSURL *videoURL = [NSURL fileURLWithPath:path];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:videoURL];
    frameExtractionPlayer = [AVPlayer playerWithPlayerItem:item];
    
    // CRITICAL: Create multiple format outputs exactly like CaptureJailed
    NSDictionary *bgraAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    
    NSDictionary *yuv420vAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(875704422), // '420v'
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    
    NSDictionary *yuv420fAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(875704438), // '420f'
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    
    bgraOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:bgraAttributes];
    yuv420vOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:yuv420vAttributes];
    yuv420fOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:yuv420fAttributes];
    
    [item addOutput:bgraOutput];
    [item addOutput:yuv420vOutput];
    [item addOutput:yuv420fOutput];
    
    [frameExtractionPlayer play];
    
    NSLog(@"[GetFrame] Video player setup complete with 3 outputs for: %@", path.lastPathComponent);
}

+ (UIWindow *)getKeyWindow {
    // Use modern UIWindowScene API
    if (@available(iOS 15.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        return window;
                    }
                }
            }
        }
        return nil;
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return [[UIApplication sharedApplication] keyWindow];
        #pragma clang diagnostic pop
    }
}

// old
// + (UIWindow *)getKeyWindow {
//     // Use modern UIWindowScene API for iOS 15+, fallback for older versions
//     if (@available(iOS 15.0, *)) {
//         NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
//         for (UIScene *scene in connectedScenes) {
//             if ([scene isKindOfClass:[UIWindowScene class]]) {
//                 UIWindowScene *windowScene = (UIWindowScene *)scene;
//                 for (UIWindow *window in windowScene.windows) {
//                     if (window.isKeyWindow) {
//                         return window;
//                     }
//                 }
//             }
//         }
        
//         // Fallback to first window if no key window found
//         for (UIScene *scene in connectedScenes) {
//             if ([scene isKindOfClass:[UIWindowScene class]]) {
//                 UIWindowScene *windowScene = (UIWindowScene *)scene;
//                 if (windowScene.windows.count > 0) {
//                     return windowScene.windows.firstObject;
//                 }
//             }
//         }
//         return nil;
//     } else {
//         // iOS 14 and earlier
//         #pragma clang diagnostic push
//         #pragma clang diagnostic ignored "-Wdeprecated-declarations"
//         NSArray *windows = [[UIApplication sharedApplication] windows];
//         for (UIWindow *window in windows) {
//             if (window.isKeyWindow) {
//                 return window;
//             }
//         }
//         return windows.firstObject;
//         #pragma clang diagnostic pop
//     }
// }


// old
// + (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame preserveOrientation:(BOOL)preserve {
//     if (!spoofCameraEnabled) {
//         return originalFrame; // Pass through when disabled
//     }
    
//     // Get spoofed frame
//     CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
//     if (!spoofedFrame) {
//         return originalFrame; // Fallback to original
//     }
    
//     if (preserve) {
//         // Return spoofed frame with ORIGINAL orientation context
//         // This is key for photo capture where orientation must be preserved
//         return spoofedFrame;
//     } else {
//         // Return spoofed frame with orientation processing
//         // This might be for preview layers where transform is expected
//         return spoofedFrame;
//     }
// }



@end

@interface GetFrameDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@property (nonatomic, assign) AVCaptureOutput *originalOutput;
@end

@implementation GetFrameDelegate

// Update the SimpleSpoofDelegate to track formats from REAL frames too:
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // CRITICAL: Track format from REAL frames like CaptureJailed
    if (sampleBuffer) {
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        if (formatDesc) {
            OSType mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
            if (mediaSubType != lastRequestedFormat) {
                lastRequestedFormat = mediaSubType;
                NSLog(@"[LC] 📐 Format detected from real frame: %c%c%c%c", 
                      (mediaSubType >> 24) & 0xFF, (mediaSubType >> 16) & 0xFF, 
                      (mediaSubType >> 8) & 0xFF, mediaSubType & 0xFF);
            }
        }
    }

    if (spoofCameraEnabled) {
        // CRITICAL: Use GetFrame like CaptureJailed does
        CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:sampleBuffer preserveOrientation:NO];
        if (spoofedFrame && self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:spoofedFrame fromConnection:connection];
        }
        if (spoofedFrame && spoofedFrame != sampleBuffer) {
            CFRelease(spoofedFrame);
        }
    } else {
        // Pass through original
        if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}

@end

// pragma MARK: - Photo Data Management

// pragma MARK: - Photo Caching (simple approach - still rotation issues)

// static void cachePhotoDataFromSampleBuffer(CMSampleBufferRef sampleBuffer) {
//     if (!sampleBuffer) return;
    
//     // Clean up old cached data
//     if (g_cachedPhotoPixelBuffer) {
//         CVPixelBufferRelease(g_cachedPhotoPixelBuffer);
//         g_cachedPhotoPixelBuffer = NULL;
//     }
//     if (g_cachedPhotoCGImage) {
//         CGImageRelease(g_cachedPhotoCGImage);
//         g_cachedPhotoCGImage = NULL;
//     }
//     g_cachedPhotoJPEGData = nil;
    
//     // Cache new data
//     CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//     if (imageBuffer) {
//         g_cachedPhotoPixelBuffer = CVPixelBufferRetain(imageBuffer);
        
//         // Create CGImage with NO orientation processing
//         CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
//         CIContext *context = [CIContext context];
//         g_cachedPhotoCGImage = [context createCGImage:ciImage fromRect:ciImage.extent];
        
//         // Create JPEG data WITHOUT UIImage wrapper (preserves original orientation metadata)
//         if (g_cachedPhotoCGImage) {
//             NSMutableData *jpegData = [NSMutableData data];
            
//             // Use modern UTType API instead of deprecated kUTTypeJPEG
//             CFStringRef jpegType;
//             jpegType = (__bridge CFStringRef)UTTypeJPEG.identifier;
            
//             CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpegData, jpegType, 1, NULL);
            
//             if (destination) {
//                 // Add minimal metadata without forcing orientation
//                 NSDictionary *properties = @{
//                     (__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @0.9
//                     // NO orientation metadata - let app handle it naturally
//                 };
                
//                 CGImageDestinationAddImage(destination, g_cachedPhotoCGImage, (__bridge CFDictionaryRef)properties);
//                 CGImageDestinationFinalize(destination);
//                 CFRelease(destination);
                
//                 g_cachedPhotoJPEGData = [jpegData copy];
//             }
//         }
        
//         NSLog(@"[LC] 📷 Photo cached WITHOUT orientation interference");
//     }
// }

// pragma MARK: - Photo Caching (advanced approach with orientation handling)

static dispatch_queue_t photoCacheQueue = NULL;

static void initializePhotoCacheQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        photoCacheQueue = dispatch_queue_create("com.livecontainer.photocache", DISPATCH_QUEUE_SERIAL);
    });
}

static void cachePhotoDataFromSampleBuffer(CMSampleBufferRef sampleBuffer) {
    if (!sampleBuffer) return;
    
    initializePhotoCacheQueue();
    
    dispatch_async(photoCacheQueue, ^{
        @autoreleasepool {
            // DEFENSIVE: Clean up old cached data safely
            if (g_cachedPhotoPixelBuffer) {
                CVPixelBufferRelease(g_cachedPhotoPixelBuffer);
                g_cachedPhotoPixelBuffer = NULL;
            }
            if (g_cachedPhotoCGImage) {
                CGImageRelease(g_cachedPhotoCGImage);
                g_cachedPhotoCGImage = NULL;
            }
            g_cachedPhotoJPEGData = nil;
            
            // Cache new data with defensive checks
            CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
            if (!imageBuffer) {
                NSLog(@"[LC] ⚠️ No image buffer in sample buffer");
                return;
            }
            
            g_cachedPhotoPixelBuffer = CVPixelBufferRetain(imageBuffer);
            
            // DEFENSIVE: Create CGImage with error checking
            @try {
                CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
                if (ciImage) {
                    CIContext *context = [CIContext context];
                    if (context) {
                        g_cachedPhotoCGImage = [context createCGImage:ciImage fromRect:ciImage.extent];
                        
                        if (g_cachedPhotoCGImage) {
                            // DEFENSIVE: Get device orientation safely
                            __block UIDeviceOrientation deviceOrientation = UIDeviceOrientationUnknown;
                            
                            dispatch_sync(dispatch_get_main_queue(), ^{
                                deviceOrientation = [[UIDevice currentDevice] orientation];
                            });
                            
                            UIImageOrientation imageOrientation = UIImageOrientationUp; // Safe default
                            
                            // Map device orientation safely
                            switch (deviceOrientation) {
                                case UIDeviceOrientationPortrait:
                                    imageOrientation = UIImageOrientationRight;
                                    break;
                                case UIDeviceOrientationPortraitUpsideDown:
                                    imageOrientation = UIImageOrientationLeft;
                                    break;
                                case UIDeviceOrientationLandscapeLeft:
                                    imageOrientation = UIImageOrientationUp;
                                    break;
                                case UIDeviceOrientationLandscapeRight:
                                    imageOrientation = UIImageOrientationDown;
                                    break;
                                default:
                                    imageOrientation = UIImageOrientationUp; // Safe fallback
                                    break;
                            }
                            
                            UIImage *image = [UIImage imageWithCGImage:g_cachedPhotoCGImage 
                                                                 scale:1.0 
                                                           orientation:imageOrientation];
                            
                            if (image) {
                                g_cachedPhotoJPEGData = UIImageJPEGRepresentation(image, 0.9);
                                NSLog(@"[LC] 📷 Photo cached safely: %lu bytes", (unsigned long)g_cachedPhotoJPEGData.length);
                            }
                        }
                    }
                }
            } @catch (NSException *exception) {
                NSLog(@"[LC] ❌ Exception in photo caching: %@", exception);
                // Clean up on error
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
        }
    });
}

static void cleanupPhotoCache(void) {
    if (!photoCacheQueue) return;
    
    dispatch_async(photoCacheQueue, ^{
        if (g_cachedPhotoPixelBuffer) {
            CVPixelBufferRelease(g_cachedPhotoPixelBuffer);
            g_cachedPhotoPixelBuffer = NULL;
        }
        if (g_cachedPhotoCGImage) {
            CGImageRelease(g_cachedPhotoCGImage);
            g_cachedPhotoCGImage = NULL;
        }
        g_cachedPhotoJPEGData = nil;
        NSLog(@"[LC] 🧹 Photo cache cleaned up safely");
    });
}

// pragma MARK: - Delegate Wrapper

@interface SimpleSpoofDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@property (nonatomic, assign) AVCaptureOutput *originalOutput;
- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureOutput *)output;
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
    // IMPROVEMENT: Track format for better matching
    if (!spoofCameraEnabled && sampleBuffer) {
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        if (formatDesc) {
            OSType mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
            if (mediaSubType != lastRequestedFormat) {
                lastRequestedFormat = mediaSubType;
                NSLog(@"[LC] 📐 Detected format preference: %c%c%c%c", 
                      (mediaSubType >> 24) & 0xFF, (mediaSubType >> 16) & 0xFF, 
                      (mediaSubType >> 8) & 0xFF, mediaSubType & 0xFF);
            }
        }
    }

    if (spoofCameraEnabled) {
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:spoofedFrame fromConnection:connection];
            }
            CFRelease(spoofedFrame);
        }
    } else {
        if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}
@end

// pragma MARK: - LEVEL 1: Core Video Hooks (Lowest Level)

CVReturn hook_CVPixelBufferCreate(CFAllocatorRef allocator, size_t width, size_t height, OSType pixelFormatType, CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *pixelBufferOut) {
    
    if (spoofCameraEnabled && width > 0 && height > 0) {
        NSLog(@"[LC] 🔧 L1: Intercepting CVPixelBuffer creation: %zux%zu", width, height);
        
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            CVImageBufferRef spoofedBuffer = CMSampleBufferGetImageBuffer(spoofedFrame);
            if (spoofedBuffer) {
                *pixelBufferOut = CVPixelBufferRetain(spoofedBuffer);
                CFRelease(spoofedFrame);
                return kCVReturnSuccess;
            }
            CFRelease(spoofedFrame);
        }
    }
    
    return original_CVPixelBufferCreate(allocator, width, height, pixelFormatType, pixelBufferAttributes, pixelBufferOut);
}

// pragma MARK: - LEVEL 2: Device Level Hooks

@implementation AVCaptureDevice(LiveContainerSpoof)

+ (NSArray<AVCaptureDevice *> *)lc_devicesWithMediaType:(AVMediaType)mediaType {
    NSArray *originalDevices = [self lc_devicesWithMediaType:mediaType];
    
    if (spoofCameraEnabled && [mediaType isEqualToString:AVMediaTypeVideo]) {
        NSLog(@"[LC] 🎥 L2: Intercepting device enumeration - %lu devices", (unsigned long)originalDevices.count);
    }
    return originalDevices;
}

+ (AVCaptureDevice *)lc_defaultDeviceWithMediaType:(AVMediaType)mediaType {
    AVCaptureDevice *originalDevice = [self lc_defaultDeviceWithMediaType:mediaType];
    
    if (spoofCameraEnabled && [mediaType isEqualToString:AVMediaTypeVideo]) {
        NSLog(@"[LC] 🎥 L2: Intercepting default device: %@", originalDevice.localizedName);
    }
    return originalDevice;
}

@end

// pragma MARK: - LEVEL 3: Device Input Level Hooks

@implementation AVCaptureDeviceInput(LiveContainerSpoof)

+ (instancetype)lc_deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    if (spoofCameraEnabled && device && [device hasMediaType:AVMediaTypeVideo]) {
        NSLog(@"[LC] 🎥 L3: Intercepting device input creation: %@", device.localizedName);
        
        AVCaptureDeviceInput *originalInput = [self lc_deviceInputWithDevice:device error:outError];
        if (originalInput) {
            objc_setAssociatedObject(originalInput, @selector(lc_deviceInputWithDevice:error:), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return originalInput;
    }
    return [self lc_deviceInputWithDevice:device error:outError];
}

@end

// pragma MARK: - LEVEL 4: Session Level Hooks

@implementation AVCaptureSession(LiveContainerSpoof)

- (void)lc_addInput:(AVCaptureInput *)input {
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        NSLog(@"[LC] 🎥 L4: Intercepting session input: %@ (pos: %ld)", 
              deviceInput.device.localizedName, (long)deviceInput.device.position);
        
        objc_setAssociatedObject(self, @selector(lc_addInput:), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self lc_addInput:input];
}

- (void)lc_addOutput:(AVCaptureOutput *)output {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📹 L4: Intercepting session output: %@", NSStringFromClass([output class]));
        
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            NSLog(@"[LC] Video data output detected");
        } else if ([output isKindOfClass:[AVCapturePhotoOutput class]]) {
            NSLog(@"[LC] Photo output detected");
        } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
            NSLog(@"[LC] Movie file output detected");
        }
    }
    [self lc_addOutput:output];
}

- (void)lc_setSessionPreset:(AVCaptureSessionPreset)sessionPreset {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📐 L4: Session preset change: %@", sessionPreset);
        // Track format preferences from preset
        if ([sessionPreset isEqualToString:AVCaptureSessionPresetPhoto]) {
            lastRequestedFormat = kCVPixelFormatType_32BGRA;
        } else if ([sessionPreset isEqualToString:AVCaptureSessionPresetHigh]) {
            lastRequestedFormat = 875704422; // '420v'
        }
    }
    [self lc_setSessionPreset:sessionPreset];
}

- (void)lc_startRunning {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 🎥 L4: Session starting - checking for camera inputs");
        
        BOOL hasCameraInput = NO;
        for (AVCaptureInput *input in self.inputs) {
            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
                    hasCameraInput = YES;
                    break;
                }
            }
        }
        
        if (hasCameraInput) {
            NSLog(@"[LC] 🎥 L4: Camera session detected - spoofing will be active");
        }
    }
    [self lc_startRunning];
}

- (void)lc_stopRunning {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 🎥 L4: Session stopping - cleaning up spoofed resources");
        
        // CRITICAL: Clean up photo cache when session stops (fixes Instagram discard)
        cleanupPhotoCache();
        
        // Clean up any preview layer associations
        objc_setAssociatedObject(self, @selector(lc_addInput:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self lc_stopRunning];
}

@end

// pragma MARK: - LEVEL 5: Output Level Hooks

@implementation AVCaptureVideoDataOutput(LiveContainerSpoof)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] 📹 L5: Using primary spoofing system (SimpleSpoofDelegate)");
        
        // IMPROVEMENT: Detect preferred format from output settings
        NSDictionary *videoSettings = self.videoSettings;
        if (videoSettings) {
            NSNumber *formatNum = videoSettings[(NSString*)kCVPixelBufferPixelFormatTypeKey];
            if (formatNum) {
                lastRequestedFormat = [formatNum unsignedIntValue];
                NSLog(@"[LC] 📐 Output requests format: %c%c%c%c", 
                      (lastRequestedFormat >> 24) & 0xFF, (lastRequestedFormat >> 16) & 0xFF, 
                      (lastRequestedFormat >> 8) & 0xFF, lastRequestedFormat & 0xFF);
            }
        }
        
        // TEMPORARY: Use SimpleSpoofDelegate for stability
        SimpleSpoofDelegate *wrapper = [[SimpleSpoofDelegate alloc] initWithDelegate:sampleBufferDelegate output:self];
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
    } else {
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    }
}
// old
// - (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
//     if (spoofCameraEnabled && sampleBufferDelegate) {
//         NSLog(@"[LC] 📹 L5: Hooking video data output delegate with format detection");
        
//         // IMPROVEMENT: Detect preferred format from output settings
//         NSDictionary *videoSettings = self.videoSettings;
//         if (videoSettings) {
//             NSNumber *formatNum = videoSettings[(NSString*)kCVPixelBufferPixelFormatTypeKey];
//             if (formatNum) {
//                 lastRequestedFormat = [formatNum unsignedIntValue];
//                 NSLog(@"[LC] 📐 Output requests format: %c%c%c%c", 
//                       (lastRequestedFormat >> 24) & 0xFF, (lastRequestedFormat >> 16) & 0xFF, 
//                       (lastRequestedFormat >> 8) & 0xFF, lastRequestedFormat & 0xFF);
//             }
//         }
        
//         SimpleSpoofDelegate *wrapper = [[SimpleSpoofDelegate alloc] initWithDelegate:sampleBufferDelegate output:self];
//         objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
//         [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
//     } else {
//         objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
//         [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
//     }
// }


// @implementation AVCaptureVideoDataOutput(LiveContainerSpoof)
// - (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
//     if (spoofCameraEnabled && sampleBufferDelegate) {
//         NSLog(@"[LC] 📹 L5: Using GetFrame pattern for video output");
//         GetFrameDelegate *wrapper = [[GetFrameDelegate alloc] initWithDelegate:sampleBufferDelegate output:self];
//         objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
//         [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
//     } else {
//         [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
//     }
// }
// 

@end

@implementation AVCapturePhotoOutput(LiveContainerSpoof)

// Cache WITHOUT orientation interference (old)
// - (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
//     if (spoofCameraEnabled) {
//         NSLog(@"[LC] 📷 UNIVERSAL: Pre-caching spoofed photo data");
        
//         // Create spoofed frame 
//         CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
//         if (spoofedFrame) {
//             // CRITICAL: Cache the RAW data without any orientation processing
//             CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(spoofedFrame);
//             if (imageBuffer) {
//                 // Clean cache
//                 if (g_cachedPhotoPixelBuffer) {
//                     CVPixelBufferRelease(g_cachedPhotoPixelBuffer);
//                     g_cachedPhotoPixelBuffer = NULL;
//                 }
//                 if (g_cachedPhotoCGImage) {
//                     CGImageRelease(g_cachedPhotoCGImage);
//                     g_cachedPhotoCGImage = NULL;
//                 }
//                 g_cachedPhotoJPEGData = nil;
                
//                 // Cache RAW pixel buffer (no processing!)
//                 g_cachedPhotoPixelBuffer = CVPixelBufferRetain(imageBuffer);
                
//                 // Create CGImage directly from pixel buffer (no orientation transforms!)
//                 CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
//                 CIContext *context = [CIContext context];
//                 g_cachedPhotoCGImage = [context createCGImage:ciImage fromRect:ciImage.extent];
                
//                 // Create JPEG with MINIMAL processing
//                 if (g_cachedPhotoCGImage) {
//                     NSMutableData *jpegData = [NSMutableData data];
//                     // Use modern UTType API instead of deprecated kUTTypeJPEG
//                     CFStringRef jpegType;
//                     jpegType = (__bridge CFStringRef)UTTypeJPEG.identifier;
            
//                     CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpegData, jpegType, 1, NULL);
//                     if (destination) {
//                         // NO orientation metadata - let apps handle naturally
//                         NSDictionary *properties = @{
//                             (__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @0.9
//                         };
//                         CGImageDestinationAddImage(destination, g_cachedPhotoCGImage, (__bridge CFDictionaryRef)properties);
//                         CGImageDestinationFinalize(destination);
//                         CFRelease(destination);
//                         g_cachedPhotoJPEGData = [jpegData copy];
//                     }
//                 }
//             }
//             CFRelease(spoofedFrame);
//         }
//     }
    
//     // Always call original - let app handle the capture naturally
//     [self lc_capturePhotoWithSettings:settings delegate:delegate];
// }


// - (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
//     if (spoofCameraEnabled) {
//         NSLog(@"[LC] 📷 L5: Using GetFrame pattern for photo capture");
        
//         // Use GetFrame with preserve orientation = YES for photos
//         CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:NULL preserveOrientation:YES];
//         if (spoofedFrame) {
//             cachePhotoDataFromSampleBuffer(spoofedFrame);
//             CFRelease(spoofedFrame);
//         }
//     }
//     [self lc_capturePhotoWithSettings:settings delegate:delegate];
// }
// 

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📷 Pre-caching photo using primary system");
        
        // CRITICAL: Use your existing PRIMARY system for photo caching
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            cachePhotoDataFromSampleBuffer(spoofedFrame);
            CFRelease(spoofedFrame);
        } else {
            NSLog(@"[LC] 📷 Primary system failed, trying GetFrame");
            // Only try GetFrame if primary fails
            CMSampleBufferRef getFrameResult = [GetFrame getCurrentFrame:NULL preserveOrientation:YES];
            if (getFrameResult) {
                cachePhotoDataFromSampleBuffer(getFrameResult);
                CFRelease(getFrameResult);
            }
        }
    }
    [self lc_capturePhotoWithSettings:settings delegate:delegate];
}

@end

@implementation AVCaptureMovieFileOutput(LiveContainerSpoof)
- (void)lc_startRecordingToOutputFileURL:(NSURL *)outputFileURL recordingDelegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 🎬 L5: Intercepting video recording to: %@", outputFileURL);
        // TODO: Create spoofed video file instead of recording real camera
    }
    [self lc_startRecordingToOutputFileURL:outputFileURL recordingDelegate:delegate];
}
@end

@implementation AVCaptureVideoPreviewLayer(LiveContainerSpoof)

- (void)lc_setSession:(AVCaptureSession *)session {
    if (spoofCameraEnabled) {
        if (session) {
            NSLog(@"[LC] 📺 L5: Setting spoofed preview session");
            objc_setAssociatedObject(self, @selector(lc_setSession:), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            // Start feeding spoofed frames to preview layer
            [self startSpoofedPreviewFeed];
        } else {
            NSLog(@"[LC] 📺 L5: Clearing preview session (discard/cleanup)");
            [self stopSpoofedPreviewFeed];
            objc_setAssociatedObject(self, @selector(lc_setSession:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cleanupPhotoCache();
        }
    }
    [self lc_setSession:session];
}

- (void)startSpoofedPreviewFeed {
    // Create a sample buffer display layer for spoofed content
    AVSampleBufferDisplayLayer *spoofLayer = [[AVSampleBufferDisplayLayer alloc] init];
    spoofLayer.frame = self.bounds;
    spoofLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self addSublayer:spoofLayer];
    
    // Store reference for cleanup
    objc_setAssociatedObject(self, @selector(startSpoofedPreviewFeed), spoofLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Feed spoofed frames to the layer
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (spoofCameraEnabled && spoofLayer.superlayer) {
            @autoreleasepool {
                CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
                if (spoofedFrame && spoofLayer.isReadyForMoreMediaData) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [spoofLayer enqueueSampleBuffer:spoofedFrame];
                    });
                    CFRelease(spoofedFrame);
                }
                [NSThread sleepForTimeInterval:1.0/30.0]; // 30 FPS
            }
        }
    });
}

- (void)stopSpoofedPreviewFeed {
    AVSampleBufferDisplayLayer *spoofLayer = objc_getAssociatedObject(self, @selector(startSpoofedPreviewFeed));
    if (spoofLayer) {
        [spoofLayer removeFromSuperlayer];
        objc_setAssociatedObject(self, @selector(startSpoofedPreviewFeed), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
@end

// pragma MARK: - LEVEL 6: Photo Accessor Hooks (Highest Level)

CVPixelBufferRef hook_AVCapturePhoto_pixelBuffer(id self, SEL _cmd) {
    @try {
        if (spoofCameraEnabled && g_cachedPhotoPixelBuffer) {
            NSLog(@"[LC] 📷 L6: Returning spoofed photo pixel buffer");
            return g_cachedPhotoPixelBuffer;
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception in pixelBuffer hook: %@", exception);
    }
    
    // DEFENSIVE: Always try to call original
    if (original_AVCapturePhoto_pixelBuffer) {
        return original_AVCapturePhoto_pixelBuffer(self, _cmd);
    }
    return NULL;
}

CGImageRef hook_AVCapturePhoto_CGImageRepresentation(id self, SEL _cmd) {
    @try {
        if (spoofCameraEnabled && g_cachedPhotoCGImage) {
            NSLog(@"[LC] 📷 L6: Returning spoofed photo CGImage");
            return g_cachedPhotoCGImage;
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception in CGImageRepresentation hook: %@", exception);
    }
    
    // DEFENSIVE: Always try to call original
    if (original_AVCapturePhoto_CGImageRepresentation) {
        return original_AVCapturePhoto_CGImageRepresentation(self, _cmd);
    }
    return NULL;
}

NSData *hook_AVCapturePhoto_fileDataRepresentation(id self, SEL _cmd) {
    @try {
        if (spoofCameraEnabled && g_cachedPhotoJPEGData) {
            NSLog(@"[LC] 📷 L6: Returning spoofed photo JPEG data (%lu bytes)", (unsigned long)g_cachedPhotoJPEGData.length);
            return g_cachedPhotoJPEGData;
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception in fileDataRepresentation hook: %@", exception);
    }
    
    // DEFENSIVE: Always try to call original
    if (original_AVCapturePhoto_fileDataRepresentation) {
        return original_AVCapturePhoto_fileDataRepresentation(self, _cmd);
    }
    return nil;
}

// pragma MARK: - Configuration Loading

static void loadSpoofingConfiguration(void) {
    NSLog(@"[LC] Loading camera spoofing configuration...");
    
    NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
    if (!guestAppInfo) {
        NSLog(@"[LC] ❌ No guestAppInfo found");
        spoofCameraEnabled = NO;
        return;
    }

    spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
    spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
    spoofCameraLoop = (guestAppInfo[@"spoofCameraLoop"] != nil) ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;

    NSLog(@"[LC] ⚙️ Config: Enabled=%d, VideoPath='%@', Loop=%d", 
          spoofCameraEnabled, spoofCameraVideoPath, spoofCameraLoop);
    
    if (spoofCameraEnabled) {
        if (spoofCameraVideoPath.length == 0) {
            NSLog(@"[LC] Image mode (no video path provided)");
        } else {
            BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath];
            NSLog(@"[LC] Video mode - file exists: %d at path: %@", exists, spoofCameraVideoPath);
            
            if (!exists) {
                NSLog(@"[LC] ❌ Video file not found - falling back to image mode");
                spoofCameraVideoPath = @"";
            } else {
                // TEMPORARY: Disable GetFrame setup to avoid conflicts
                // [GetFrame setCurrentVideoPath:spoofCameraVideoPath];
                NSLog(@"[LC] GetFrame setup disabled - using primary video system only");
            }
        }
    }
}

// pragma MARK: - Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] 🚀 Initializing comprehensive AVFoundation hooks...");
        
        loadSpoofingConfiguration();
        
        videoProcessingQueue = dispatch_queue_create("com.livecontainer.videoprocessingqueue", DISPATCH_QUEUE_SERIAL);

        // Setup primary image resources
        setupImageSpoofingResources();

        // Create emergency fallback if needed
        if (!lastGoodSpoofedPixelBuffer) {
        NSLog(@"[LC] ⚠️ Creating emergency fallback buffer");
        
        // IMPROVEMENT: Create emergency buffer in multiple formats
        OSType emergencyFormat = kCVPixelFormatType_32BGRA; // Start with BGRA
        CVPixelBufferRef emergencyPixelBuffer = NULL;
        CGSize emergencySize = targetResolution;

        NSDictionary *pixelAttributes = @{
            (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
            (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
            (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
        };
        
        CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                            (size_t)emergencySize.width, (size_t)emergencySize.height,
                                            emergencyFormat,
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
                // Create more subtle emergency pattern (blue gradient instead of magenta)
                CGFloat colors[] = { 0.2, 0.4, 0.8, 1.0, 0.1, 0.2, 0.4, 1.0 };
                CGFloat locations[] = {0.0, 1.0};
                CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, locations, 2);
                CGContextDrawLinearGradient(cgContext, gradient, CGPointMake(0,0), CGPointMake(0,emergencySize.height), 0);
                CGGradientRelease(gradient);
                CGContextRelease(cgContext);
            }
            CGColorSpaceRelease(colorSpace);
            CVPixelBufferUnlockBaseAddress(emergencyPixelBuffer, 0);

            CMVideoFormatDescriptionRef emergencyFormatDesc = NULL;
            CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, emergencyPixelBuffer, &emergencyFormatDesc);
            updateLastGoodSpoofedFrame(emergencyPixelBuffer, emergencyFormatDesc);
            
            if (emergencyFormatDesc) CFRelease(emergencyFormatDesc);
            CVPixelBufferRelease(emergencyPixelBuffer);
            NSLog(@"[LC] Emergency BGRA buffer created");
        }
    }

        // Setup video resources if enabled
        if (spoofCameraEnabled && spoofCameraVideoPath && spoofCameraVideoPath.length > 0) {
            NSLog(@"[LC] Video mode: Setting up PRIMARY video system only");
            setupVideoSpoofingResources(); // Use your working system
            // TEMPORARY: Disable GetFrame to avoid conflicts
            // [GetFrame setCurrentVideoPath:spoofCameraVideoPath];
        } else if (spoofCameraEnabled) {
            NSLog(@"[LC] Image mode: Using static image fallback");
        }

        // Install hooks at all levels
        // Update your hook installation with better error handling:
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            @try {
                NSLog(@"[LC] Installing hierarchical hooks...");
                
                // LEVEL 2: Device Level (with error handling)
                @try {
                    swizzle([AVCaptureDevice class], @selector(devicesWithMediaType:), @selector(lc_devicesWithMediaType:));
                    swizzle([AVCaptureDevice class], @selector(defaultDeviceWithMediaType:), @selector(lc_defaultDeviceWithMediaType:));
                    NSLog(@"[LC] ✅ Level 2 hooks installed");
                } @catch (NSException *e) {
                    NSLog(@"[LC] ❌ Level 2 hook error: %@", e);
                }
                
                // LEVEL 3: Device Input Level (with error handling)
                @try {
                    swizzle([AVCaptureDeviceInput class], @selector(deviceInputWithDevice:error:), @selector(lc_deviceInputWithDevice:error:));
                    NSLog(@"[LC] ✅ Level 3 hooks installed");
                } @catch (NSException *e) {
                    NSLog(@"[LC] ❌ Level 3 hook error: %@", e);
                }
                
                // LEVEL 4: Session Level (with error handling)
                @try {
                    swizzle([AVCaptureSession class], @selector(addInput:), @selector(lc_addInput:));
                    swizzle([AVCaptureSession class], @selector(addOutput:), @selector(lc_addOutput:));
                    swizzle([AVCaptureSession class], @selector(startRunning), @selector(lc_startRunning));
                    swizzle([AVCaptureSession class], @selector(setSessionPreset:), @selector(lc_setSessionPreset:));
                    swizzle([AVCaptureSession class], @selector(stopRunning), @selector(lc_stopRunning));
                    NSLog(@"[LC] ✅ Level 4 hooks installed");
                } @catch (NSException *e) {
                    NSLog(@"[LC] ❌ Level 4 hook error: %@", e);
                }

                // LEVEL 5: Output Level (with error handling)
                @try {
                    swizzle([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
                    swizzle([AVCapturePhotoOutput class], @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
                    swizzle([AVCaptureMovieFileOutput class], @selector(startRecordingToOutputFileURL:recordingDelegate:), @selector(lc_startRecordingToOutputFileURL:recordingDelegate:));
                    swizzle([AVCaptureVideoPreviewLayer class], @selector(setSession:), @selector(lc_setSession:));
                    NSLog(@"[LC] ✅ Level 5 hooks installed");
                } @catch (NSException *e) {
                    NSLog(@"[LC] ❌ Level 5 hook error: %@", e);
                }
                
                // LEVEL 6: Photo Accessor Level (with error handling)
                @try {
                    Method pixelBufferMethod = class_getInstanceMethod([AVCapturePhoto class], @selector(pixelBuffer));
                    if (pixelBufferMethod) {
                        original_AVCapturePhoto_pixelBuffer = (CVPixelBufferRef (*)(id, SEL))method_getImplementation(pixelBufferMethod);
                        method_setImplementation(pixelBufferMethod, (IMP)hook_AVCapturePhoto_pixelBuffer);
                        NSLog(@"[LC] ✅ L6: Photo pixelBuffer hook installed");
                    }
                    
                    Method cgImageMethod = class_getInstanceMethod([AVCapturePhoto class], @selector(CGImageRepresentation));
                    if (cgImageMethod) {
                        original_AVCapturePhoto_CGImageRepresentation = (CGImageRef (*)(id, SEL))method_getImplementation(cgImageMethod);
                        method_setImplementation(cgImageMethod, (IMP)hook_AVCapturePhoto_CGImageRepresentation);
                        NSLog(@"[LC] ✅ L6: Photo CGImageRepresentation hook installed");
                    }
                    
                    Method fileDataMethod = class_getInstanceMethod([AVCapturePhoto class], @selector(fileDataRepresentation));
                    if (fileDataMethod) {
                        original_AVCapturePhoto_fileDataRepresentation = (NSData *(*)(id, SEL))method_getImplementation(fileDataMethod);
                        method_setImplementation(fileDataMethod, (IMP)hook_AVCapturePhoto_fileDataRepresentation);
                        NSLog(@"[LC] ✅ L6: Photo fileDataRepresentation hook installed");
                    }
                } @catch (NSException *e) {
                    NSLog(@"[LC] ❌ Level 6 hook error: %@", e);
                }
                
                NSLog(@"[LC] ✅ All hooks installed with error handling");
                
            } @catch (NSException *exception) {
                NSLog(@"[LC] ❌ CRITICAL: Hook installation failed: %@", exception);
            }
        });
        
        if (spoofCameraEnabled) {
             NSLog(@"[LC] ✅ Spoofing initialized - LastGoodBuffer: %s", 
                   lastGoodSpoofedPixelBuffer ? "VALID" : "NULL");
        }

    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception during initialization: %@", exception);
    }
}



