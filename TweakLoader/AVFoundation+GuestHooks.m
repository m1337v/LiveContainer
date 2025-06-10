//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Camera Addon implementation
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "../LiveContainer/Tweaks/Tweaks.h"
#import "../fishhook/fishhook.h"

static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraType = @"image";
static NSString *spoofCameraImagePath = @"";
static NSString *spoofCameraVideoPath = @"";
static BOOL spoofCameraLoop = YES;

static UIImage *spoofImage = nil;
static AVPlayer *spoofVideoPlayer = nil;
static AVPlayerItemVideoOutput *videoOutput = nil;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

// Hook AVCaptureSession
@interface AVCaptureSession(LiveContainerHooks)
- (void)lc_startRunning;
- (void)lc_stopRunning;
- (void)lc_addInput:(AVCaptureInput *)input;
- (void)lc_addOutput:(AVCaptureOutput *)output;
@end

@implementation AVCaptureSession(LiveContainerHooks)

- (void)lc_startRunning {
    NSLog(@"[LC] AVCaptureSession startRunning called");
    if (spoofCameraEnabled) {
        NSLog(@"[LC] Camera spoofing is enabled, intercepting camera session");
        // Don't call the original method to prevent real camera access
        return;
    }
    [self lc_startRunning]; // Call original
}

- (void)lc_stopRunning {
    NSLog(@"[LC] AVCaptureSession stopRunning called");
    [self lc_stopRunning]; // Always call original
}

- (void)lc_addInput:(AVCaptureInput *)input {
    NSLog(@"[LC] AVCaptureSession addInput called: %@", input);
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        // Check if it's actually a camera device
        if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
            NSLog(@"[LC] Blocking camera input due to spoofing");
            return; // Block camera input
        }
    }
    [self lc_addInput:input]; // Call original for non-camera inputs
}

- (void)lc_addOutput:(AVCaptureOutput *)output {
    NSLog(@"[LC] AVCaptureSession addOutput called: %@", output);
    
    if (spoofCameraEnabled) {
        // Set up our spoofed output
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            [self setupSpoofedVideoOutput:(AVCaptureVideoDataOutput *)output];
        } else if ([output isKindOfClass:[AVCaptureStillImageOutput class]]) {
            [self setupSpoofedImageOutput:(AVCaptureStillImageOutput *)output];
        }
    }
    
    [self lc_addOutput:output]; // Call original
}

- (void)setupSpoofedVideoOutput:(AVCaptureVideoDataOutput *)output {
    NSLog(@"[LC] Setting up spoofed video output");
    
    dispatch_queue_t videoQueue = dispatch_queue_create("com.livecontainer.spoofvideo", DISPATCH_QUEUE_SERIAL);
    
    if ([spoofCameraType isEqualToString:@"video"] && spoofCameraVideoPath.length > 0) {
        [self setupVideoSpoofing:output queue:videoQueue];
    } else {
        [self setupImageSpoofing:output queue:videoQueue];
    }
}

- (void)setupVideoSpoofing:(AVCaptureVideoDataOutput *)output queue:(dispatch_queue_t)queue {
    NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath]) {
        NSLog(@"[LC] Spoof video file not found: %@", spoofCameraVideoPath);
        return;
    }
    
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
    spoofVideoPlayer = [AVPlayer playerWithPlayerItem:playerItem];
    
    if (spoofCameraLoop) {
        // Set up looping
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(playerItemDidReachEnd:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:playerItem];
    }
    
    // Set up video output
    videoOutput = [[AVPlayerItemVideoOutput alloc] init];
    [playerItem addOutput:videoOutput];
    
    // Start playing
    [spoofVideoPlayer play];
    
    // Feed frames to the output
    dispatch_async(queue, ^{
        [self feedVideoFramesToOutput:output];
    });
}

- (void)setupImageSpoofing:(AVCaptureVideoDataOutput *)output queue:(dispatch_queue_t)queue {
    if (spoofCameraImagePath.length > 0) {
        spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
    }
    
    if (!spoofImage) {
        // Create a default test image
        spoofImage = [self createDefaultTestImage];
    }
    
    // Feed the static image repeatedly
    dispatch_async(queue, ^{
        [self feedImageFramesToOutput:output];
    });
}

- (void)feedVideoFramesToOutput:(AVCaptureVideoDataOutput *)output {
    // This is a simplified implementation
    // In a full implementation, you'd extract frames from the video
    // and convert them to CMSampleBufferRef format
    NSLog(@"[LC] Feeding video frames to output");
}

- (void)feedImageFramesToOutput:(AVCaptureVideoDataOutput *)output {
    if (!spoofImage) return;
    
    NSLog(@"[LC] Feeding image frames to output");
    
    // Create a dedicated queue for frame delivery
    dispatch_queue_t frameQueue = dispatch_queue_create("com.livecontainer.cameraspoof.frames", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(frameQueue, ^{
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 // 30 FPS
                                                          target:self
                                                        selector:@selector(deliverSpoofFrame:)
                                                        userInfo:@{@"output": output}
                                                         repeats:YES];
        [[NSRunLoop currentRunLoop] run];
    });
}

- (void)deliverSpoofFrame:(NSTimer *)timer {
    AVCaptureVideoDataOutput *output = timer.userInfo[@"output"];
    // Here you would create a CMSampleBufferRef from spoofImage
    // and call the output's delegate methods
    NSLog(@"[LC] Delivering spoofed frame");
}

- (void)setupSpoofedImageOutput:(AVCaptureStillImageOutput *)output {
    NSLog(@"[LC] Setting up spoofed still image output");
    // Override the captureStillImageAsynchronouslyFromConnection method
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    if (spoofCameraLoop && spoofVideoPlayer) {
        [spoofVideoPlayer seekToTime:kCMTimeZero];
        [spoofVideoPlayer play];
    }
}

- (UIImage *)createDefaultTestImage {
    CGSize size = CGSizeMake(640, 480);
    UIGraphicsBeginImageContext(size);
    
    // Create a gradient background
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGFloat colors[] = {
        0.2, 0.6, 1.0, 1.0,  // Blue
        0.8, 0.2, 0.8, 1.0   // Purple
    };
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointZero, CGPointMake(size.width, size.height), 0);
    
    // Add text
    UIFont *font = [UIFont boldSystemFontOfSize:24];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };
    
    NSString *text = @"LiveContainer\nCamera Spoof";
    CGRect textRect = CGRectMake(size.width/2 - 100, size.height/2 - 30, 200, 60);
    [text drawInRect:textRect withAttributes:attributes];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    
    return image;
}

@end

void AVFoundationGuestHooksInit(void) {
    @try {
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        
        NSLog(@"[LC] AVFoundationGuestHooksInit: guestAppInfo = %@", guestAppInfo);
        
        if (guestAppInfo) {
            spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
            NSLog(@"[LC] spoofCamera from guestAppInfo: %@", guestAppInfo[@"spoofCamera"]);
            NSLog(@"[LC] spoofCameraEnabled: %d", spoofCameraEnabled);
            
            if (spoofCameraEnabled) {
                spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
                spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";
                spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
                spoofCameraLoop = [guestAppInfo[@"spoofCameraLoop"] boolValue];
                
                NSLog(@"[LC] Camera spoofing configuration:");
                NSLog(@"[LC] - spoofCameraType: %@", spoofCameraType);
                NSLog(@"[LC] - spoofCameraImagePath: %@", spoofCameraImagePath);
                NSLog(@"[LC] - spoofCameraVideoPath: %@", spoofCameraVideoPath);
                NSLog(@"[LC] - spoofCameraLoop: %d", spoofCameraLoop);
                
                // Hook AVCaptureSession methods
                Class captureSessionClass = NSClassFromString(@"AVCaptureSession");
                if (captureSessionClass) {
                    NSLog(@"[LC] Hooking AVCaptureSession methods");
                    
                    swizzle(captureSessionClass,
                            @selector(startRunning),
                            @selector(lc_startRunning));
                    
                    swizzle(captureSessionClass,
                            @selector(stopRunning),
                            @selector(lc_stopRunning));
                    
                    swizzle(captureSessionClass,
                            @selector(addInput:),
                            @selector(lc_addInput:));
                    
                    swizzle(captureSessionClass,
                            @selector(addOutput:),
                            @selector(lc_addOutput:));
                    
                    NSLog(@"[LC] AVCaptureSession methods hooked successfully");
                } else {
                    NSLog(@"[LC] AVCaptureSession class not found");
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in AVFoundationGuestHooksInit: %@", exception);
    }
}