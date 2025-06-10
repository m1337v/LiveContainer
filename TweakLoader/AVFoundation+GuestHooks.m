//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Camera spoofing implementation with actual frame delivery
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import "../LiveContainer/Tweaks/Tweaks.h"

static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraType = @"image";
static NSString *spoofCameraImagePath = @"";
static NSString *spoofCameraVideoPath = @"";
static BOOL spoofCameraLoop = YES;

static UIImage *spoofImage = nil;
static AVPlayer *spoofVideoPlayer = nil;
static NSTimer *frameTimer = nil;
static NSMutableArray *activeOutputs = nil;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

// Custom capture session to handle spoofed data
@interface LCSpoofCaptureSession : NSObject
@property (nonatomic, strong) NSMutableArray *outputs;
@property (nonatomic, assign) BOOL isRunning;
@end

@implementation LCSpoofCaptureSession

- (instancetype)init {
    self = [super init];
    if (self) {
        _outputs = [[NSMutableArray alloc] init];
        _isRunning = NO;
    }
    return self;
}

- (void)addOutput:(AVCaptureOutput *)output {
    [self.outputs addObject:output];
    NSLog(@"[LC] Added spoofed output: %@", output);
}

- (void)startRunning {
    if (self.isRunning) return;
    
    self.isRunning = YES;
    NSLog(@"[LC] Starting spoofed camera session");
    
    // Start delivering frames
    [self startFrameDelivery];
}

- (void)stopRunning {
    self.isRunning = NO;
    NSLog(@"[LC] Stopping spoofed camera session");
    
    // Stop delivering frames
    [self stopFrameDelivery];
}

- (void)startFrameDelivery {
    if (frameTimer) {
        [frameTimer invalidate];
    }
    
    // Create timer for 30 FPS
    frameTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0
                                                  target:self
                                                selector:@selector(deliverFrame)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)stopFrameDelivery {
    if (frameTimer) {
        [frameTimer invalidate];
        frameTimer = nil;
    }
}

- (void)deliverFrame {
    if (!self.isRunning) return;
    
    // Get the image to display
    UIImage *imageToShow = [self getCurrentFrame];
    if (!imageToShow) return;
    
    // Convert to sample buffer and deliver to all outputs
    CMSampleBufferRef sampleBuffer = [self createSampleBufferFromImage:imageToShow];
    if (sampleBuffer) {
        [self deliverSampleBuffer:sampleBuffer];
        CFRelease(sampleBuffer);
    }
}

- (UIImage *)getCurrentFrame {
    if ([spoofCameraType isEqualToString:@"video"] && spoofVideoPlayer) {
        // Get current video frame
        return [self getCurrentVideoFrame];
    } else {
        // Return static image
        return spoofImage ?: [self createDefaultTestImage];
    }
}

- (UIImage *)getCurrentVideoFrame {
    // This is simplified - in a full implementation you'd extract the current frame from AVPlayer
    // For now, return the static image as a fallback
    return spoofImage ?: [self createDefaultTestImage];
}

- (CMSampleBufferRef)createSampleBufferFromImage:(UIImage *)image {
    CGSize size = CGSizeMake(640, 480);
    
    // Create pixel buffer
    CVPixelBufferRef pixelBuffer = NULL;
    CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32BGRA, NULL, &pixelBuffer);
    
    if (!pixelBuffer) return NULL;
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    
    // Create graphics context and draw image
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, size.width, size.height, 8,
                                                CVPixelBufferGetBytesPerRow(pixelBuffer),
                                                colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    if (context) {
        // Scale and draw image
        CGRect drawRect = CGRectMake(0, 0, size.width, size.height);
        CGContextDrawImage(context, drawRect, image.CGImage);
        CGContextRelease(context);
    }
    
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    // Create sample buffer
    CMSampleBufferRef sampleBuffer = NULL;
    CMVideoFormatDescriptionRef formatDescription = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDescription);
    
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30), // 30 FPS
        .presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000),
        .decodeTimeStamp = kCMTimeInvalid
    };
    
    CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixelBuffer, formatDescription, &timingInfo, &sampleBuffer);
    
    CVPixelBufferRelease(pixelBuffer);
    if (formatDescription) CFRelease(formatDescription);
    
    return sampleBuffer;
}

- (void)deliverSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    for (AVCaptureOutput *output in self.outputs) {
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
            id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = videoOutput.sampleBufferDelegate;
            dispatch_queue_t queue = videoOutput.sampleBufferCallbackQueue;
            
            if (delegate && queue) {
                dispatch_async(queue, ^{
                    if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                        [delegate captureOutput:videoOutput didOutputSampleBuffer:sampleBuffer fromConnection:nil];
                    }
                });
            }
        }
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

static LCSpoofCaptureSession *spoofSession = nil;

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
        NSLog(@"[LC] Camera spoofing is enabled, using spoofed session");
        if (!spoofSession) {
            spoofSession = [[LCSpoofCaptureSession alloc] init];
        }
        [spoofSession startRunning];
        return;
    }
    [self lc_startRunning]; // Call original
}

- (void)lc_stopRunning {
    NSLog(@"[LC] AVCaptureSession stopRunning called");
    if (spoofCameraEnabled && spoofSession) {
        [spoofSession stopRunning];
    }
    [self lc_stopRunning]; // Always call original
}

- (void)lc_addInput:(AVCaptureInput *)input {
    NSLog(@"[LC] AVCaptureSession addInput called: %@", input);
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
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
        if (!spoofSession) {
            spoofSession = [[LCSpoofCaptureSession alloc] init];
        }
        [spoofSession addOutput:output];
        NSLog(@"[LC] Output added to spoofed session");
        return; // Don't add to real session
    }
    
    [self lc_addOutput:output]; // Call original
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
                
                // Load spoofed image if available
                if (spoofCameraImagePath.length > 0) {
                    spoofImage = [UIImage imageWithContentsOfFile:spoofCameraImagePath];
                    if (spoofImage) {
                        NSLog(@"[LC] Loaded spoof image: %@", spoofCameraImagePath);
                    } else {
                        NSLog(@"[LC] Failed to load spoof image: %@", spoofCameraImagePath);
                    }
                }
                
                // Initialize active outputs array
                if (!activeOutputs) {
                    activeOutputs = [[NSMutableArray alloc] init];
                }
                
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