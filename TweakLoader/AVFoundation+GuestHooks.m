//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Camera spoofing based on working cj approach
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

// Forward declaration of delegate wrapper
@interface LCSpoofVideoDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, assign) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@property (nonatomic, assign) AVCaptureOutput *originalOutput;
@end

// --- Global State ---
static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraVideoPath = @"";
static BOOL spoofCameraLoop = YES;

// Cached resources for performance (like cj)
static CVPixelBufferRef g_cachedSpoofedPixelBuffer = NULL;
static CGImageRef g_cachedSpoofedCGImage = NULL;
static NSData *g_cachedSpoofedJPEGData = nil;
static CMSampleBufferRef g_globalSampleBuffer = NULL;

// Video player for spoofing (like cj)
static AVPlayer *videoPlayer = nil;
static AVPlayerItemVideoOutput *videoOutput = nil;
static BOOL isVideoReady = NO;
static id playerEndObserver = nil;

// Timing for frame processing
static CFTimeInterval g_lastFrameTime = 0;
static CFTimeInterval g_currentFrameTime = 0;

#pragma mark - Configuration Loading (Fixed)

static void loadSpoofingConfiguration(void) {
    // Read from LiveContainer's UserDefaults (not guestAppInfo)
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // First try the bundleID-specific defaults
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *configKey = [NSString stringWithFormat:@"LCAppInfo_%@", bundleID];
    NSDictionary *appConfig = [defaults objectForKey:configKey];
    
    if (appConfig) {
        spoofCameraEnabled = [appConfig[@"spoofCamera"] boolValue];
        spoofCameraVideoPath = appConfig[@"spoofCameraVideoPath"] ?: @"";
        spoofCameraLoop = (appConfig[@"spoofCameraLoop"] != nil) ? [appConfig[@"spoofCameraLoop"] boolValue] : YES;
    } else {
        // Fallback to guestAppInfo
        NSDictionary *guestAppInfo = [defaults objectForKey:@"guestAppInfo"];
        if (guestAppInfo) {
            spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
            spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
            spoofCameraLoop = (guestAppInfo[@"spoofCameraLoop"] != nil) ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;
        }
    }
    
    NSLog(@"[LC] Camera config loaded: enabled=%d, path='%@', loop=%d", 
          spoofCameraEnabled, spoofCameraVideoPath, spoofCameraLoop);
    
    // Debug file existence
    if (spoofCameraEnabled && spoofCameraVideoPath.length > 0) {
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath];
        NSLog(@"[LC] Video file exists: %d at path: %@", exists, spoofCameraVideoPath);
    }
}

#pragma mark - Video Setup (Like cj)

static void setupVideoSpoofing(void) {
    NSLog(@"[LC] Setting up video spoofing...");
    
    // Clean up existing setup
    if (videoPlayer) {
        [videoPlayer pause];
        if (playerEndObserver) {
            [[NSNotificationCenter defaultCenter] removeObserver:playerEndObserver];
            playerEndObserver = nil;
        }
        videoPlayer = nil;
    }
    if (videoOutput) {
        videoOutput = nil;
    }
    isVideoReady = NO;
    
    if (!spoofCameraVideoPath || spoofCameraVideoPath.length == 0) {
        NSLog(@"[LC] No video path specified");
        return;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath]) {
        NSLog(@"[LC] Video file not found: %@", spoofCameraVideoPath);
        return;
    }
    
    NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:videoURL];
    videoPlayer = [AVPlayer playerWithPlayerItem:playerItem];
    
    // CRITICAL: Mute the video player to prevent audio bleeding
    videoPlayer.muted = YES;
    videoPlayer.volume = 0.0;
    
    // Setup video output for frame extraction
    NSDictionary *pixelBufferAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];
    [playerItem addOutput:videoOutput];
    
    // Setup looping (like cj)
    if (spoofCameraLoop) {
        videoPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        playerEndObserver = [[NSNotificationCenter defaultCenter] 
                            addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                            object:playerItem
                            queue:nil
                            usingBlock:^(NSNotification *note) {
            [videoPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                if (finished) {
                    [videoPlayer play];
                }
            }];
        }];
    }
    
    // Wait for player to be ready
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int attempts = 0;
        while (attempts < 100 && playerItem.status != AVPlayerItemStatusReadyToPlay) {
            [NSThread sleepForTimeInterval:0.1];
            attempts++;
        }
        
        if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [videoPlayer play];
                isVideoReady = YES;
                NSLog(@"[LC] Video spoofing ready and playing (muted)");
            });
        } else {
            NSLog(@"[LC] Video failed to load, status: %ld", (long)playerItem.status);
        }
    });
}

#pragma mark - Frame Processing (Like cj)

static CMSampleBufferRef createSpoofedSampleBuffer(void) {
    if (!isVideoReady || !videoOutput || !videoPlayer) {
        return NULL;
    }
    
    CMTime currentTime = [videoPlayer.currentItem currentTime];
    if (![videoOutput hasNewPixelBufferForItemTime:currentTime]) {
        return NULL;
    }
    
    CVPixelBufferRef pixelBuffer = [videoOutput copyPixelBufferForItemTime:currentTime itemTimeForDisplay:nil];
    if (!pixelBuffer) {
        return NULL;
    }
    
    // Create format description
    CMVideoFormatDescriptionRef formatDesc;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    if (status != noErr) {
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }
    
    // Update timing (like cj)
    g_lastFrameTime = g_currentFrameTime;
    g_currentFrameTime = CACurrentMediaTime();
    
    // Create timing info
    CMTime presentationTime = CMTimeMakeWithSeconds(g_currentFrameTime, NSEC_PER_SEC);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = presentationTime,
        .decodeTimeStamp = kCMTimeInvalid
    };
    
    // Create sample buffer
    CMSampleBufferRef sampleBuffer;
    status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                     pixelBuffer,
                                                     formatDesc,
                                                     &timingInfo,
                                                     &sampleBuffer);
    
    CFRelease(formatDesc);
    CVPixelBufferRelease(pixelBuffer);
    
    return (status == noErr) ? sampleBuffer : NULL;
}

static void updateCachedSpoofContent(void) {
    if (!spoofCameraEnabled || !isVideoReady) {
        return;
    }
    
    CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
    if (!spoofedFrame) {
        return;
    }
    
    // Store global sample buffer
    if (g_globalSampleBuffer) {
        CFRelease(g_globalSampleBuffer);
    }
    g_globalSampleBuffer = spoofedFrame;
    CFRetain(g_globalSampleBuffer);
    
    // Clean up old cached data
    if (g_cachedSpoofedPixelBuffer) {
        CVPixelBufferRelease(g_cachedSpoofedPixelBuffer);
        g_cachedSpoofedPixelBuffer = NULL;
    }
    if (g_cachedSpoofedCGImage) {
        CGImageRelease(g_cachedSpoofedCGImage);
        g_cachedSpoofedCGImage = NULL;
    }
    g_cachedSpoofedJPEGData = nil;
    
    // Cache new data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(spoofedFrame);
    if (imageBuffer) {
        g_cachedSpoofedPixelBuffer = CVPixelBufferRetain(imageBuffer);
        
        // Create CIImage and apply orientation (like cj)
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
        CIImage *orientedImage = [ciImage imageByApplyingCGOrientation:kCGImagePropertyOrientationRightMirrored];
        
        CIContext *context = [CIContext context];
        g_cachedSpoofedCGImage = [context createCGImage:orientedImage fromRect:orientedImage.extent];
        
        // Create JPEG data
        if (g_cachedSpoofedCGImage) {
            UIImage *image = [UIImage imageWithCGImage:g_cachedSpoofedCGImage];
            g_cachedSpoofedJPEGData = UIImageJPEGRepresentation(image, 1.0);
        }
    }
}

#pragma mark - Photo Hooks (Like cj)

@implementation AVCapturePhoto (LiveContainerSpoof)

- (CVPixelBufferRef)lc_pixelBuffer {
    if (spoofCameraEnabled && g_cachedSpoofedPixelBuffer) {
        NSLog(@"[LC] Returning spoofed pixel buffer for photo");
        return g_cachedSpoofedPixelBuffer;
    }
    return [self lc_pixelBuffer];
}

- (CGImageRef)lc_CGImageRepresentation {
    if (spoofCameraEnabled && g_cachedSpoofedCGImage) {
        NSLog(@"[LC] Returning spoofed CGImage for photo");
        return g_cachedSpoofedCGImage;
    }
    return [self lc_CGImageRepresentation];
}

- (NSData *)lc_fileDataRepresentation {
    if (spoofCameraEnabled && g_cachedSpoofedJPEGData) {
        NSLog(@"[LC] Returning spoofed JPEG data for photo (%lu bytes)", (unsigned long)g_cachedSpoofedJPEGData.length);
        return g_cachedSpoofedJPEGData;
    }
    return [self lc_fileDataRepresentation];
}

@end

#pragma mark - Photo Capture Hook (Like cj)

@implementation AVCapturePhotoOutput (LiveContainerSpoof)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings 
                           delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    
    NSLog(@"[LC] Photo capture requested, spoofing enabled: %d", spoofCameraEnabled);
    
    if (spoofCameraEnabled && isVideoReady) {
        // Update cached content before photo capture
        updateCachedSpoofContent();
        
        // Call original to trigger proper delegate flow
        [self lc_capturePhotoWithSettings:settings delegate:delegate];
    } else {
        [self lc_capturePhotoWithSettings:settings delegate:delegate];
    }
}

@end

#pragma mark - Video Stream Hook (Like cj)

@implementation AVCaptureVideoDataOutput (LiveContainerSpoof)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate 
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] Wrapping video data output delegate");
        LCSpoofVideoDelegate *wrapper = [[LCSpoofVideoDelegate alloc] init];
        wrapper.originalDelegate = sampleBufferDelegate;
        wrapper.originalOutput = self;
        
        // Store wrapper to prevent deallocation
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
    } else {
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    }
}

@end

#pragma mark - Delegate Wrapper Implementation (Like cj)

@implementation LCSpoofVideoDelegate

- (void)captureOutput:(AVCaptureOutput *)output 
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
       fromConnection:(AVCaptureConnection *)connection {
    
    if (spoofCameraEnabled && isVideoReady) {
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            // Forward spoofed frame to original delegate
            if ([self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                [self.originalDelegate captureOutput:self.originalOutput 
                               didOutputSampleBuffer:spoofedFrame 
                                      fromConnection:connection];
            }
            CFRelease(spoofedFrame);
            return;
        }
    }
    
    // Forward original frame if spoofing failed or disabled
    if ([self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        [self.originalDelegate captureOutput:self.originalOutput 
                       didOutputSampleBuffer:sampleBuffer 
                              fromConnection:connection];
    }
}

@end

#pragma mark - Initialization (Fixed)

void AVFoundationGuestHooksInit(void) {
    NSLog(@"[LC] Initializing camera spoofing hooks...");
    
    loadSpoofingConfiguration();
    
    if (!spoofCameraEnabled) {
        NSLog(@"[LC] Camera spoofing disabled");
        return;
    }
    
    setupVideoSpoofing();
    
    // Add configuration change observer
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        NSLog(@"[LC] UserDefaults changed, reloading camera config");
        loadSpoofingConfiguration();
        if (spoofCameraEnabled) {
            setupVideoSpoofing();
        }
    }];
    
    // Install hooks using LiveContainer's swizzle system
    Class photoClass = [AVCapturePhoto class];
    swizzle(photoClass, @selector(pixelBuffer), @selector(lc_pixelBuffer));
    swizzle(photoClass, @selector(CGImageRepresentation), @selector(lc_CGImageRepresentation));
    swizzle(photoClass, @selector(fileDataRepresentation), @selector(lc_fileDataRepresentation));
    
    Class photoOutputClass = [AVCapturePhotoOutput class];
    swizzle(photoOutputClass, @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));
    
    Class videoDataOutputClass = [AVCaptureVideoDataOutput class];
    swizzle(videoDataOutputClass, @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
    
    NSLog(@"[LC] Camera spoofing hooks installed successfully");
}