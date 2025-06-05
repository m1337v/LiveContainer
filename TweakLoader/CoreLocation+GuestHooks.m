#import "CoreLocation+GuestHooks.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import "utils.h"

static BOOL spoofGPSEnabled = NO;
static CLLocationCoordinate2D spoofedCoordinate = {37.7749, -122.4194};
static CLLocationDistance spoofedAltitude = 0.0;

@interface CLLocationManager (GuestHooks)
- (void)lc_startUpdatingLocation;
- (void)lc_requestLocation;
- (CLLocation *)lc_location;
@end

@implementation CLLocationManager (GuestHooks)

- (void)lc_startUpdatingLocation {
    if (spoofGPSEnabled && self.delegate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CLLocation *spoofedLocation = [[CLLocation alloc] 
                initWithCoordinate:spoofedCoordinate
                altitude:spoofedAltitude
                horizontalAccuracy:5.0
                verticalAccuracy:5.0
                timestamp:[NSDate date]];
            
            if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                [self.delegate locationManager:self didUpdateLocations:@[spoofedLocation]];
            }
        });
        return;
    }
    
    [self lc_startUpdatingLocation];
}

- (void)lc_requestLocation {
    if (spoofGPSEnabled && self.delegate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CLLocation *spoofedLocation = [[CLLocation alloc] 
                initWithCoordinate:spoofedCoordinate
                altitude:spoofedAltitude
                horizontalAccuracy:5.0
                verticalAccuracy:5.0
                timestamp:[NSDate date]];
            
            if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                [self.delegate locationManager:self didUpdateLocations:@[spoofedLocation]];
            }
        });
        return;
    }
    
    [self lc_requestLocation];
}

- (CLLocation *)lc_location {
    if (spoofGPSEnabled) {
        return [[CLLocation alloc] 
            initWithCoordinate:spoofedCoordinate
            altitude:spoofedAltitude
            horizontalAccuracy:5.0
            verticalAccuracy:5.0
            timestamp:[NSDate date]];
    }
    
    return [self lc_location];
}

@end

void CoreLocationGuestHooksInit(void) {
    // Load GPS spoofing settings from container info
    NSString *containerInfoPath = [NSString stringWithFormat:@"%@/LCContainerInfo.plist", getenv("HOME")];
    NSDictionary *containerInfo = [NSDictionary dictionaryWithContentsOfFile:containerInfoPath];
    
    if (containerInfo) {
        spoofGPSEnabled = [containerInfo[@"spoofGPS"] boolValue];
        if (spoofGPSEnabled) {
            spoofedCoordinate.latitude = [containerInfo[@"spoofLatitude"] doubleValue];
            spoofedCoordinate.longitude = [containerInfo[@"spoofLongitude"] doubleValue];
            spoofedAltitude = [containerInfo[@"spoofAltitude"] doubleValue];
            
            NSLog(@"[LC] Container GPS spoofing enabled: %f, %f, %f", 
                  spoofedCoordinate.latitude, 
                  spoofedCoordinate.longitude, 
                  spoofedAltitude);
            
            // Hook CLLocationManager methods
            swizzle([CLLocationManager class], 
                    @selector(startUpdatingLocation), 
                    @selector(lc_startUpdatingLocation));
            
            swizzle([CLLocationManager class], 
                    @selector(requestLocation), 
                    @selector(lc_requestLocation));
            
            swizzle([CLLocationManager class], 
                    @selector(location), 
                    @selector(lc_location));
        }
    }
}