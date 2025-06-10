//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Enhanced camera spoofing implementation
//

#import "AVFoundation+GuestHooks.h"
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
static CMSampleBufferRef cachedSampleBuffer = NULL;

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

// Custom capture connection
@interface LCSpoofCaptureConnection : AVCaptureConnection
@end

@implementation LCSpoofCaptureConnection

- (instancetype)init {
    self = [super init];
    return self;
}

- (BOOL)isEnabled {
    return YES;
}

- (BOOL)isActive {
    return YES;
}

@end

// Custom capture session to handle spoofed data
@interface LCSpoofCaptureSession : NSObject
@property (nonatomic, strong) NSMutableArray *outputs;
@property (nonatomic, strong) NSMutableArray *connections;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) dispatch_queue_t frameQueue;
@end

@implementation LCSpoofCaptureSession

- (instancetype)init {
    self = [super init];
    if (self) {
        _outputs = [[NSMutableArray alloc] init];
        _connections = [[NSMutableArray alloc] init];
        _isRunning = NO;
        _frameQueue = dispatch_queue_create("com.livecontainer.cameraspoof", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)addOutput:(AVCaptureOutput *)output {
    [self.outputs addObject:output];
    
    // Create a connection for this output
    LCSpoofCaptureConnection *connection = [[LCSpoofCaptureConnection alloc] init];
    [self.connections addObject:connection];
    
    NSLog(@"[LC] Added spoofed output: %@ with connection: %@", output, connection);
    
    // If session is already running, start delivering frames to this output
    if (self.isRunning) {
        [self startFrameDeliveryForOutput:output withConnection:connection];
    }
}

- (void)startRunning {
    if (self.isRunning) return;
    
    self.isRunning = YES;
    NSLog(@"[LC] Starting spoofed camera session");
    
    // Prepare the sample buffer
    [self prepareSampleBuffer];
    
    // Start delivering frames to all outputs
    for (NSInteger i = 0; i < self.outputs.count; i++) {
        AVCaptureOutput *output = self.outputs[i];
        LCSpoofCaptureConnection *connection = self.connections[i];
        [self startFrameDeliveryForOutput:output withConnection:connection];
    }
}

- (void)stopRunning {
    self.isRunning = NO;
    NSLog(@"[LC] Stopping spoofed camera session");
    
    // Stop delivering frames
    [self stopFrameDelivery];
    
    // Clean up cached sample buffer
    if (cachedSampleBuffer) {
        CFRelease(cachedSampleBuffer);
        cachedSampleBuffer = NULL;
    }
}

- (void)prepareSampleBuffer {
    UIImage *imageToShow = [self getCurrentFrame];
    if (!imageToShow) return;
    
    // Create and cache the sample buffer
    if (cachedSampleBuffer) {
        CFRelease(cachedSampleBuffer);
    }
    cachedSampleBuffer = [self createSampleBufferFromImage:imageToShow];
    CFRetain(cachedSampleBuffer); // Keep it alive
}

- (void)startFrameDeliveryForOutput:(AVCaptureOutput *)output withConnection:(LCSpoofCaptureConnection *)connection {
    if (!self.isRunning) return;
    
    dispatch_async(self.frameQueue, ^{
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            [self deliverVideoFramesToOutput:(AVCaptureVideoDataOutput *)output withConnection:connection];
        } else if ([output isKindOfClass:[AVCaptureStillImageOutput class]]) {
            [self setupStillImageOutput:(AVCaptureStillImageOutput *)output withConnection:connection];
        }
    });
}

- (void)deliverVideoFramesToOutput:(AVCaptureVideoDataOutput *)output withConnection:(LCSpoofCaptureConnection *)connection {
    // Create a timer for this specific output
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.frameQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC / 30, NSEC_PER_SEC / 100); // 30 FPS
    
    dispatch_source_set_event_handler(timer, ^{
        if (!self.isRunning) {
            dispatch_source_cancel(timer);
            return;
        }
        
        if (cachedSampleBuffer) {
            id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = output.sampleBufferDelegate;
            dispatch_queue_t delegateQueue = output.sampleBufferCallbackQueue;
            
            if (delegate && delegateQueue) {
                dispatch_async(delegateQueue, ^{
                    if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                        [delegate captureOutput:output didOutputSampleBuffer:cachedSampleBuffer fromConnection:connection];
                    }
                });
            }
        }
    });
    
    dispatch_resume(timer);
}

- (void)setupStillImageOutput:(AVCaptureStillImageOutput *)output withConnection:(LCSpoofCaptureConnection *)connection {
    NSLog(@"[LC] Setting up still image output for spoofing");
    // Still image outputs are handled on-demand when the app calls captureStillImageAsynchronouslyFromConnection
}

- (void)stopFrameDelivery {
    // Frame delivery is handled by individual timers that check self.isRunning
}

- (UIImage *)getCurrentFrame {
    if ([spoofCameraType isEqualToString:@"video"] && spoofVideoPlayer) {
        return [self getCurrentVideoFrame];
    } else {
        return spoofImage ?: [self createDefaultTestImage];
    }
}

- (UIImage *)getCurrentVideoFrame {
    // Simplified - return static image for now
    return spoofImage ?: [self createDefaultTestImage];
}

- (CMSampleBufferRef)createSampleBufferFromImage:(UIImage *)image {
    // Use image actual size or common camera resolution
    CGSize imageSize = image.size;
    CGSize targetSize = CGSizeMake(
        MIN(imageSize.width, 1920),   // Max 1920 width
        MIN(imageSize.height, 1080)   // Max 1080 height
    );
    
    // Maintain aspect ratio
    CGFloat aspectRatio = imageSize.width / imageSize.height;
    if (targetSize.width / targetSize.height > aspectRatio) {
        targetSize.width = targetSize.height * aspectRatio;
    } else {
        targetSize.height = targetSize.width / aspectRatio;
    }
    
    // Ensure even dimensions (required for video formats)
    targetSize.width = floor(targetSize.width / 2) * 2;
    targetSize.height = floor(targetSize.height / 2) * 2;
    
    // Create pixel buffer with proper attributes
    NSDictionary *pixelBufferAttributes = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn result = CVPixelBufferCreate(
        kCFAllocatorDefault,
        targetSize.width,
        targetSize.height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)pixelBufferAttributes,
        &pixelBuffer
    );
    
    if (result != kCVReturnSuccess || !pixelBuffer) {
        NSLog(@"[LC] Failed to create pixel buffer: %d", result);
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    // Create graphics context
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        baseAddress,
        targetSize.width,
        targetSize.height,
        8,
        bytesPerRow,
        colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    );
    
    if (context) {
        // Clear the buffer
        CGContextClearRect(context, CGRectMake(0, 0, targetSize.width, targetSize.height));
        
        // Draw image scaled to fit
        CGRect drawRect = CGRectMake(0, 0, targetSize.width, targetSize.height);
        CGContextDrawImage(context, drawRect, image.CGImage);
        CGContextRelease(context);
    }
    
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    // Create format description
    CMVideoFormatDescriptionRef formatDescription = NULL;
    result = CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        &formatDescription
    );
    
    if (result != noErr || !formatDescription) {
        CVPixelBufferRelease(pixelBuffer);
        NSLog(@"[LC] Failed to create format description: %d", result);
        return NULL;
    }
    
    // Create timing info with proper timestamps
    CMTime currentTime = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    CMSampleTimingInfo timingInfo = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = currentTime,
        .decodeTimeStamp = kCMTimeInvalid
    };
    
    // Create sample buffer
    CMSampleBufferRef sampleBuffer = NULL;
    result = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        formatDescription,
        &timingInfo,
        &sampleBuffer
    );
    
    // Clean up
    CVPixelBufferRelease(pixelBuffer);
    CFRelease(formatDescription);
    
    if (result != noErr) {
        NSLog(@"[LC] Failed to create sample buffer: %d", result);
        return NULL;
    }
    
    return sampleBuffer;
}

- (UIImage *)createDefaultTestImage {
    CGSize size = CGSizeMake(640, 480);
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    
    // Create a more visible test pattern
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Draw checkerboard pattern
    CGFloat squareSize = 40.0;
    for (int x = 0; x < size.width / squareSize; x++) {
        for (int y = 0; y < size.height / squareSize; y++) {
            if ((x + y) % 2 == 0) {
                [[UIColor colorWithRed:0.8 green:0.2 blue:0.8 alpha:1.0] setFill];
            } else {
                [[UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0] setFill];
            }
            CGRect rect = CGRectMake(x * squareSize, y * squareSize, squareSize, squareSize);
            CGContextFillRect(context, rect);
        }
    }
    
    // Add text
    UIFont *font = [UIFont boldSystemFontOfSize:24];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSStrokeColorAttributeName: [UIColor blackColor],
        NSStrokeWidthAttributeName: @(-2)
    };
    
    NSString *text = @"LiveContainer\nCamera Spoof";
    CGRect textRect = CGRectMake(0, 0, size.width, size.height);
    [text drawInRect:textRect withAttributes:attributes];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

@end

static LCSpoofCaptureSession *spoofSession = nil;

// Hook AVCaptureStillImageOutput for still image capture
@interface AVCaptureStillImageOutput(LiveContainerHooks)
- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler;
@end

@implementation AVCaptureStillImageOutput(LiveContainerHooks)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    NSLog(@"[LC] AVCaptureStillImageOutput captureStillImageAsynchronouslyFromConnection called");
    
    if (spoofCameraEnabled && spoofSession) {
        NSLog(@"[LC] Returning spoofed still image");
        
        // Get current frame and create sample buffer
        UIImage *imageToShow = [spoofSession getCurrentFrame];
        if (imageToShow) {
            CMSampleBufferRef sampleBuffer = [spoofSession createSampleBufferFromImage:imageToShow];
            if (sampleBuffer) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(sampleBuffer, nil);
                    CFRelease(sampleBuffer);
                });
                return;
            }
        }
        
        // Fallback to error
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error = [NSError errorWithDomain:@"LiveContainerCameraSpoof" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create spoofed image"}];
            handler(NULL, error);
        });
        return;
    }
    
    // Call original method
    [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
}

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
        NSLog(@"[LC] Camera spoofing is enabled, using spoofed session");
        if (!spoofSession) {
            spoofSession = [[LCSpoofCaptureSession alloc] init];
        }
        [spoofSession startRunning];
        return; // Don't start real session
    }
    [self lc_startRunning]; // Call original
}

- (void)lc_stopRunning {
    NSLog(@"[LC] AVCaptureSession stopRunning called");
    if (spoofCameraEnabled && spoofSession) {
        [spoofSession stopRunning];
    }
    [self lc_stopRunning]; // Always call original for cleanup
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
                }
                
                // Hook AVCaptureStillImageOutput methods
                Class stillImageOutputClass = NSClassFromString(@"AVCaptureStillImageOutput");
                if (stillImageOutputClass) {
                    NSLog(@"[LC] Hooking AVCaptureStillImageOutput methods");
                    
                    swizzle(stillImageOutputClass,
                            @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:),
                            @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
                    
                    NSLog(@"[LC] AVCaptureStillImageOutput methods hooked successfully");
                }
                
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] Exception in AVFoundationGuestHooksInit: %@", exception);
    }
}