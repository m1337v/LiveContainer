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
    @try {
        NSDictionary *guestAppInfo = NSUserDefaults.guestAppInfo;
        
        NSLog(@"[LC] CoreLocationGuestHooksInit: guestAppInfo = %@", guestAppInfo);
        
        if (guestAppInfo) {
            spoofGPSEnabled = [guestAppInfo[@"spoofGPS"] boolValue];
            NSLog(@"[LC] spoofGPS from guestAppInfo: %@", guestAppInfo[@"spoofGPS"]);
            NSLog(@"[LC] spoofGPSEnabled: %d", spoofGPSEnabled);
            
            if (spoofGPSEnabled) {
                // Ensure we're getting the right values with explicit type conversion
                NSNumber *latNum = guestAppInfo[@"spoofLatitude"];
                NSNumber *lonNum = guestAppInfo[@"spoofLongitude"];
                NSNumber *altNum = guestAppInfo[@"spoofAltitude"];
                
                if (latNum && [latNum isKindOfClass:[NSNumber class]]) {
                    spoofedCoordinate.latitude = [latNum doubleValue];
                } else {
                    spoofedCoordinate.latitude = 37.7749; // Default
                    NSLog(@"[LC] Warning: spoofLatitude not found or invalid, using default");
                }
                
                if (lonNum && [lonNum isKindOfClass:[NSNumber class]]) {
                    spoofedCoordinate.longitude = [lonNum doubleValue];
                } else {
                    spoofedCoordinate.longitude = -122.4194; // Default
                    NSLog(@"[LC] Warning: spoofLongitude not found or invalid, using default");
                }
                
                if (altNum && [altNum isKindOfClass:[NSNumber class]]) {
                    spoofedAltitude = [altNum doubleValue];
                } else {
                    spoofedAltitude = 0.0; // Default
                    NSLog(@"[LC] Warning: spoofAltitude not found or invalid, using default");
                }
                
                NSLog(@"[LC] GPS coordinates from guestAppInfo:");
                NSLog(@"[LC] - spoofLatitude: %@ -> %f", latNum, spoofedCoordinate.latitude);
                NSLog(@"[LC] - spoofLongitude: %@ -> %f", lonNum, spoofedCoordinate.longitude);
                NSLog(@"[LC] - spoofAltitude: %@ -> %f", altNum, spoofedAltitude);
                
                NSLog(@"[LC] Final GPS spoofing coordinates: %f, %f, %f", 
                      spoofedCoordinate.latitude, 
                      spoofedCoordinate.longitude, 
                      spoofedAltitude);
                
                // Only hook if CoreLocation is available and GPS spoofing is enabled
                Class clLocationManagerClass = NSClassFromString(@"CLLocationManager");
                if (clLocationManagerClass) {
                    NSLog(@"[LC] Hooking CLLocationManager methods");
                    // Hook CLLocationManager methods
                    swizzle(clLocationManagerClass, 
                            @selector(startUpdatingLocation), 
                            @selector(lc_startUpdatingLocation));
                    
                    swizzle(clLocationManagerClass, 
                            @selector(requestLocation), 
                            @selector(lc_requestLocation));
                    
                    swizzle(clLocationManagerClass, 
                            @selector(location), 
                            @selector(lc_location));
                } else {
                    NSLog(@"[LC] Warning: CLLocationManager class not found");
                }
            }
        } else {
            NSLog(@"[LC] No guestAppInfo available for GPS spoofing");
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] Error initializing GPS hooks: %@", exception);
    }
}