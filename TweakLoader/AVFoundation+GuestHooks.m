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
#import "../LiveContainer/Tweaks/Tweaks.h"

// --- Global State for Spoofing ---
static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraVideoPath = @"";
static BOOL spoofCameraLoop = YES;

// Resolution and Fallback Management
static CGSize targetResolution = {1080, 1920}; // Default to Portrait Full HD
static BOOL resolutionDetected = NO;
static CVPixelBufferRef lastGoodSpoofedPixelBuffer = NULL;
static CMVideoFormatDescriptionRef lastGoodSpoofedFormatDesc = NULL;

// Video Spoofing Resources
static AVPlayer *videoSpoofPlayer = nil;
static AVPlayerItemVideoOutput *videoSpoofPlayerOutput = nil;
static dispatch_queue_t videoProcessingQueue = NULL;
static BOOL isVideoSetupSuccessfully = NO;
static id playerDidPlayToEndTimeObserver = nil;

// --- Helper: NSUserDefaults ---
@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

// --- Forward Declarations ---
static void setupVideoSpoofingResources(void);
static CMSampleBufferRef createSpoofedSampleBuffer(void);

#pragma mark - Pixel Buffer Utilities

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
            NSLog(@"[LC] CRITICAL: Failed to create shared CIContext.");
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

#pragma mark - GetFrame Logic

static CMSampleBufferRef createSpoofedSampleBuffer() {
    CVPixelBufferRef sourcePixelBuffer = NULL;
    BOOL ownSourcePixelBuffer = NO;

    // Get video frame
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
    
    CVPixelBufferRef finalScaledPixelBuffer = NULL;
    if (sourcePixelBuffer) {
        finalScaledPixelBuffer = createScaledPixelBuffer(sourcePixelBuffer, targetResolution);
        if (ownSourcePixelBuffer) {
            CVPixelBufferRelease(sourcePixelBuffer);
        }
    }

    // Fallback to last good frame
    if (!finalScaledPixelBuffer && lastGoodSpoofedPixelBuffer) {
        finalScaledPixelBuffer = lastGoodSpoofedPixelBuffer;
        CVPixelBufferRetain(finalScaledPixelBuffer);
        NSLog(@"[LC] Using last good spoofed frame.");
    }

    if (!finalScaledPixelBuffer) {
        NSLog(@"[LC] CRITICAL: No pixel buffer available for spoofing.");
        return NULL;
    }

    // Create Format Description
    CMVideoFormatDescriptionRef currentFormatDesc = NULL;
    if (finalScaledPixelBuffer == lastGoodSpoofedPixelBuffer && lastGoodSpoofedFormatDesc) {
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
    
    // Update last good frame if we generated a new one
    if (finalScaledPixelBuffer != lastGoodSpoofedPixelBuffer) {
         updateLastGoodSpoofedFrame(finalScaledPixelBuffer, currentFormatDesc);
    }

    CMTime presentationTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), NSEC_PER_SEC);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30), // 30 FPS
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
        NSLog(@"[LC] Failed to create CMSampleBuffer. Status: %d", (int)result);
        return NULL;
    }
    return sampleBuffer;
}

#pragma mark - Resource Setup

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
        
        // CRITICAL: Mute the video player
        videoSpoofPlayer.muted = YES;
        videoSpoofPlayer.volume = 0.0;

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
            NSLog(@"[LC] Video spoofing ready and playing (muted). Rate: %.2f", videoSpoofPlayer.rate);
        });
    }];
}

#pragma mark - Delegate Wrapper

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
    // Dynamic Resolution Detection
    if (!resolutionDetected && !spoofCameraEnabled && sampleBuffer) {
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (imageBuffer) {
            size_t width = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            if (width > 0 && height > 0) {
                CGSize detectedRes = CGSizeMake(width, height);
                if (fabs(detectedRes.width - targetResolution.width) > 1 || fabs(detectedRes.height - targetResolution.height) > 1) {
                    NSLog(@"[LC] 📐 Detected camera resolution: %zux%zu. Updating target from %.0fx%.0f.", width, height, targetResolution.width, targetResolution.height);
                    targetResolution = detectedRes;
                    resolutionDetected = YES;
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

#pragma mark - Method Hooks

@implementation AVCaptureVideoDataOutput(LiveContainerSimpleSpoof)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] Hooking AVCaptureVideoDataOutput delegate.");
        SimpleSpoofDelegate *wrapper = [[SimpleSpoofDelegate alloc] initWithDelegate:sampleBufferDelegate output:self];
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
    } else {
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    }
}
@end

@implementation AVCapturePhotoOutput(LiveContainerSimpleSpoof)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Spoofing photo capture (Target Res: %.0fx%.0f)", targetResolution.width, targetResolution.height);
        
        CMSampleBufferRef spoofedFrameContents = createSpoofedSampleBuffer(); 
            
        dispatch_async(dispatch_get_main_queue(), ^{
            if (spoofedFrameContents) {
                if ([delegate respondsToSelector:@selector(captureOutput:willBeginCaptureForResolvedSettings:)]) {
                    [delegate captureOutput:self willBeginCaptureForResolvedSettings:nil];
                }

                if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
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
        return; 
    }
    [self lc_capturePhotoWithSettings:settings delegate:delegate]; 
}
@end

#pragma mark - Configuration Loading

static void loadSpoofingConfiguration(void) {
    NSLog(@"[LC] Loading camera spoofing configuration from guestAppInfo...");
    
    NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
    if (!guestAppInfo) {
        NSLog(@"[LC] No guestAppInfo found.");
        spoofCameraEnabled = NO;
        return;
    }

    spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
    spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
    spoofCameraLoop = (guestAppInfo[@"spoofCameraLoop"] != nil) ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;

    NSLog(@"[LC] Config: Enabled=%d, VideoPath='%@', Loop=%d", 
          spoofCameraEnabled, spoofCameraVideoPath, spoofCameraLoop);
    
    // Debug file existence
    if (spoofCameraEnabled && spoofCameraVideoPath.length > 0) {
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath];
        NSLog(@"[LC] Video file exists: %d at path: %@", exists, spoofCameraVideoPath);
        if (!exists) {
            NSLog(@"[LC] Camera spoofing disabled - video file not found");
            spoofCameraEnabled = NO;
        }
    }
}

#pragma mark - Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] 🎥 Initializing AVFoundation Guest Hooks...");
        
        loadSpoofingConfiguration();
        
        videoProcessingQueue = dispatch_queue_create("com.livecontainer.videoprocessingqueue", DISPATCH_QUEUE_SERIAL);

        // Create emergency fallback buffer
        if (!lastGoodSpoofedPixelBuffer) {
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
                    CGContextSetRGBFillColor(cgContext, 0.2, 0.4, 0.8, 1.0); // Blue background
                    CGContextFillRect(cgContext, CGRectMake(0, 0, emergencySize.width, emergencySize.height));
                    
                    NSString *text = @"LiveContainer\nCamera Spoof";
                    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
                    style.alignment = NSTextAlignmentCenter;
                    NSDictionary *attrs = @{ 
                        NSFontAttributeName: [UIFont boldSystemFontOfSize:emergencySize.width * 0.04],
                        NSForegroundColorAttributeName: [UIColor whiteColor],
                        NSParagraphStyleAttributeName: style 
                    };
                    CGSize textSize = [text sizeWithAttributes:attrs];
                    CGRect textRect = CGRectMake((emergencySize.width - textSize.width) / 2,
                                                 (emergencySize.height - textSize.height) / 2,
                                                 textSize.width, textSize.height);
                    
                    UIGraphicsPushContext(cgContext);
                    [text drawInRect:textRect withAttributes:attrs];
                    UIGraphicsPopContext();
                    
                    CGContextRelease(cgContext);
                }
                CGColorSpaceRelease(colorSpace);
                CVPixelBufferUnlockBaseAddress(emergencyPixelBuffer, 0);

                CMVideoFormatDescriptionRef emergencyFormatDesc = NULL;
                CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, emergencyPixelBuffer, &emergencyFormatDesc);
                updateLastGoodSpoofedFrame(emergencyPixelBuffer, emergencyFormatDesc);
                
                if (emergencyFormatDesc) CFRelease(emergencyFormatDesc);
                CVPixelBufferRelease(emergencyPixelBuffer);
                NSLog(@"[LC] Emergency fallback buffer created.");
            }
        }

        // Setup video resources if enabled
        if (spoofCameraEnabled && spoofCameraVideoPath && spoofCameraVideoPath.length > 0) {
            NSLog(@"[LC] Setting up video spoofing...");
            setupVideoSpoofingResources(); 
        }

        // Add configuration change observer
        [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
            NSLog(@"[LC] 🔄 Settings changed, reloading camera config");
            loadSpoofingConfiguration();
            if (spoofCameraEnabled && spoofCameraVideoPath && spoofCameraVideoPath.length > 0) {
                setupVideoSpoofingResources();
            }
        }];
        
        // Apply hooks
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSLog(@"[LC] 🔧 Applying AVFoundation hooks...");
            swizzle([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
            swizzle([AVCapturePhotoOutput class], @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
            NSLog(@"[LC] ✅ AVFoundation Hooks applied.");
        });
        
        if (spoofCameraEnabled) {
             NSLog(@"[LC] ✅ Camera spoofing initialized. LastGoodBuffer: %s", 
                   lastGoodSpoofedPixelBuffer ? "VALID" : "NULL");
        }

    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception during AVFoundationGuestHooksInit: %@", exception);
    }
}