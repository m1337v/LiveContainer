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
#import <objc/runtime.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

// pragma MARK: - Global State

// Core configuration
static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraVideoPath = @"";
static BOOL spoofCameraLoop = YES;

// Resolution and fallback management
static CGSize targetResolution = {1080, 1920};
static BOOL resolutionDetected = NO;
static CVPixelBufferRef lastGoodSpoofedPixelBuffer = NULL;
static CMVideoFormatDescriptionRef lastGoodSpoofedFormatDesc = NULL;

// Image spoofing resources
static CVPixelBufferRef staticImageSpoofBuffer = NULL;

// Video spoofing resources
static AVPlayer *videoSpoofPlayer = nil;
static AVPlayerItemVideoOutput *videoSpoofPlayerOutput = nil;
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
        NSLog(@"[LC] Error creating scaled pixel buffer: %d", status);
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

static CMSampleBufferRef createSpoofedSampleBuffer() {
    CVPixelBufferRef sourcePixelBuffer = NULL;
    BOOL ownSourcePixelBuffer = NO;

    // 1. Try video frame first
    if (isVideoSetupSuccessfully &&
        videoSpoofPlayerOutput && videoSpoofPlayer.currentItem &&
        videoSpoofPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay && videoSpoofPlayer.rate > 0.0f) {
        
        CMTime playerTime = [videoSpoofPlayer.currentItem currentTime];
        if ([videoSpoofPlayerOutput hasNewPixelBufferForItemTime:playerTime]) {
            sourcePixelBuffer = [videoSpoofPlayerOutput copyPixelBufferForItemTime:playerTime itemTimeForDisplay:NULL];
            if (sourcePixelBuffer) {
                ownSourcePixelBuffer = YES;
            }
        }
    }

    // 2. Fallback to static image
    if (!sourcePixelBuffer && staticImageSpoofBuffer) {
        sourcePixelBuffer = staticImageSpoofBuffer;
        CVPixelBufferRetain(sourcePixelBuffer);
        ownSourcePixelBuffer = YES;
    }
    
    CVPixelBufferRef finalScaledPixelBuffer = NULL;
    if (sourcePixelBuffer) {
        finalScaledPixelBuffer = createScaledPixelBuffer(sourcePixelBuffer, targetResolution);
        if (ownSourcePixelBuffer) {
            CVPixelBufferRelease(sourcePixelBuffer);
        }
    }

    // 3. Last resort - use previous good frame
    if (!finalScaledPixelBuffer && lastGoodSpoofedPixelBuffer) {
        finalScaledPixelBuffer = lastGoodSpoofedPixelBuffer;
        CVPixelBufferRetain(finalScaledPixelBuffer);
    }

    if (!finalScaledPixelBuffer) {
        NSLog(@"[LC] CRITICAL: No pixel buffer available for spoofing");
        return NULL;
    }

    // 4. Create format description
    CMVideoFormatDescriptionRef currentFormatDesc = NULL;
    if (finalScaledPixelBuffer == lastGoodSpoofedPixelBuffer && lastGoodSpoofedFormatDesc) {
        currentFormatDesc = lastGoodSpoofedFormatDesc;
        CFRetain(currentFormatDesc);
    } else {
        OSStatus formatDescStatus = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, finalScaledPixelBuffer, &currentFormatDesc);
        if (formatDescStatus != noErr) {
            NSLog(@"[LC] Failed to create format description: %d", (int)formatDescStatus);
            CVPixelBufferRelease(finalScaledPixelBuffer);
            return NULL;
        }
    }
    
    // 5. Update last good frame if we created a new one
    if (finalScaledPixelBuffer != lastGoodSpoofedPixelBuffer) {
         updateLastGoodSpoofedFrame(finalScaledPixelBuffer, currentFormatDesc);
    }

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

    if (result != noErr) {
        NSLog(@"[LC] Failed to create CMSampleBuffer: %d", (int)result);
        return NULL;
    }
    return sampleBuffer;
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
            if (videoSpoofPlayer.currentItem) {
                [videoSpoofPlayer.currentItem removeOutput:videoSpoofPlayerOutput];
            }
            videoSpoofPlayer = nil;
            videoSpoofPlayerOutput = nil;
        }

        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
        videoSpoofPlayer = [AVPlayer playerWithPlayerItem:playerItem];
        videoSpoofPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        videoSpoofPlayer.muted = YES;

        NSDictionary *pixelBufferAttributes = @{
            (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
            (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
        };
        videoSpoofPlayerOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];
        
        dispatch_async(videoProcessingQueue, ^{
            while (playerItem.status != AVPlayerItemStatusReadyToPlay) {
                [NSThread sleepForTimeInterval:0.05];
                if (playerItem.status == AVPlayerItemStatusFailed) {
                     NSLog(@"[LC] Player item failed: %@", playerItem.error);
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
            NSLog(@"[LC] ✅ Video spoofing ready");
        });
    }];
}

// pragma MARK: - Photo Data Management

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
        
        // Create CGImage (no transforms for universal compatibility)
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
        CIContext *context = [CIContext context];
        g_cachedPhotoCGImage = [context createCGImage:ciImage fromRect:ciImage.extent];
        
        // Create JPEG data
        if (g_cachedPhotoCGImage) {
            UIImage *image = [UIImage imageWithCGImage:g_cachedPhotoCGImage 
                                                 scale:1.0 
                                           orientation:UIImageOrientationUp];
            g_cachedPhotoJPEGData = UIImageJPEGRepresentation(image, 0.9);
        }
        
        NSLog(@"[LC] 📷 Photo data cached for universal compatibility");
    }
}

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
    // Dynamic resolution detection
    if (!resolutionDetected && !spoofCameraEnabled && sampleBuffer) {
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (imageBuffer) {
            size_t width = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            if (width > 0 && height > 0) {
                CGSize detectedRes = CGSizeMake(width, height);
                if (fabs(detectedRes.width - targetResolution.width) > 1 || fabs(detectedRes.height - targetResolution.height) > 1) {
                    NSLog(@"[LC] 📐 Detected resolution: %zux%zu, updating from %.0fx%.0f", width, height, targetResolution.width, targetResolution.height);
                    targetResolution = detectedRes;
                    resolutionDetected = YES;
                    
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

@end

// pragma MARK: - LEVEL 5: Output Level Hooks

@implementation AVCaptureVideoDataOutput(LiveContainerSpoof)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] 📹 L5: Hooking video data output delegate");
        SimpleSpoofDelegate *wrapper = [[SimpleSpoofDelegate alloc] initWithDelegate:sampleBufferDelegate output:self];
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
    } else {
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    }
}
@end

@implementation AVCapturePhotoOutput(LiveContainerSpoof)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📷 L5: Intercepting photo capture - pre-caching spoofed data");
        
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            cachePhotoDataFromSampleBuffer(spoofedFrame);
            CFRelease(spoofedFrame);
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
    if (spoofCameraEnabled && session) {
        NSLog(@"[LC] 📺 L5: Intercepting video preview layer session");
        // TODO: Inject spoofed frames into preview layer
    }
    [self lc_setSession:session];
}
@end

// pragma MARK: - LEVEL 6: Photo Accessor Hooks (Highest Level)

CVPixelBufferRef hook_AVCapturePhoto_pixelBuffer(id self, SEL _cmd) {
    if (spoofCameraEnabled && g_cachedPhotoPixelBuffer) {
        NSLog(@"[LC] 📷 L6: Returning spoofed photo pixel buffer");
        return g_cachedPhotoPixelBuffer;
    }
    return original_AVCapturePhoto_pixelBuffer(self, _cmd);
}

CGImageRef hook_AVCapturePhoto_CGImageRepresentation(id self, SEL _cmd) {
    if (spoofCameraEnabled && g_cachedPhotoCGImage) {
        NSLog(@"[LC] 📷 L6: Returning spoofed photo CGImage");
        return g_cachedPhotoCGImage;
    }
    return original_AVCapturePhoto_CGImageRepresentation(self, _cmd);
}

NSData *hook_AVCapturePhoto_fileDataRepresentation(id self, SEL _cmd) {
    if (spoofCameraEnabled && g_cachedPhotoJPEGData) {
        NSLog(@"[LC] 📷 L6: Returning spoofed photo JPEG data (%lu bytes)", (unsigned long)g_cachedPhotoJPEGData.length);
        return g_cachedPhotoJPEGData;
    }
    return original_AVCapturePhoto_fileDataRepresentation(self, _cmd);
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
            CVPixelBufferRef emergencyPixelBuffer = NULL;
            CGSize emergencySize = targetResolution;

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
                    CGContextRelease(cgContext);
                }
                CGColorSpaceRelease(colorSpace);
                CVPixelBufferUnlockBaseAddress(emergencyPixelBuffer, 0);

                CMVideoFormatDescriptionRef emergencyFormatDesc = NULL;
                CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, emergencyPixelBuffer, &emergencyFormatDesc);
                updateLastGoodSpoofedFrame(emergencyPixelBuffer, emergencyFormatDesc);
                
                if (emergencyFormatDesc) CFRelease(emergencyFormatDesc);
                CVPixelBufferRelease(emergencyPixelBuffer);
                NSLog(@"[LC] Emergency buffer created");
            }
        }

        // Setup video resources if enabled
        if (spoofCameraEnabled && spoofCameraVideoPath && spoofCameraVideoPath.length > 0) {
            NSLog(@"[LC] Video mode: Setting up video resources");
            setupVideoSpoofingResources(); 
        } else if (spoofCameraEnabled) {
            NSLog(@"[LC] Image mode: Using static image fallback");
        }

        // Install hooks at all levels
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSLog(@"[LC] Installing hierarchical hooks...");
            
            // LEVEL 1: Core Video (commented out - requires MSHookFunction)
            // MSHookFunction(CVPixelBufferCreate, hook_CVPixelBufferCreate, (void**)&original_CVPixelBufferCreate);
            
            // LEVEL 2: Device Level
            // swizzle([AVCaptureDevice class], @selector(devicesWithMediaType:), @selector(lc_devicesWithMediaType:));
            // swizzle([AVCaptureDevice class], @selector(defaultDeviceWithMediaType:), @selector(lc_defaultDeviceWithMediaType:));
            
            // LEVEL 3: Device Input Level  
            // swizzle([AVCaptureDeviceInput class], @selector(deviceInputWithDevice:error:), @selector(lc_deviceInputWithDevice:error:));
            
            // LEVEL 4: Session Level
            // swizzle([AVCaptureSession class], @selector(addInput:), @selector(lc_addInput:));
            // swizzle([AVCaptureSession class], @selector(addOutput:), @selector(lc_addOutput:));
            // swizzle([AVCaptureSession class], @selector(startRunning), @selector(lc_startRunning));
            
            // LEVEL 5: Output Level
            swizzle([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
            swizzle([AVCapturePhotoOutput class], @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
            swizzle([AVCaptureMovieFileOutput class], @selector(startRecordingToOutputFileURL:recordingDelegate:), @selector(lc_startRecordingToOutputFileURL:recordingDelegate:));
            swizzle([AVCaptureVideoPreviewLayer class], @selector(setSession:), @selector(lc_setSession:));
            
            // LEVEL 6: Photo Accessor Level
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
            
            NSLog(@"[LC] ✅ All hooks installed successfully");
        });
        
        if (spoofCameraEnabled) {
             NSLog(@"[LC] ✅ Spoofing initialized - LastGoodBuffer: %s", 
                   lastGoodSpoofedPixelBuffer ? "VALID" : "NULL");
        }

    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception during initialization: %@", exception);
    }
}



