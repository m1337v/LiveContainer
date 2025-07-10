#import "FoundationPrivate.h"
#import "DecoratedFloatingView.h"
#import "AppSceneViewController.h"

API_AVAILABLE(ios(16.0))
@interface DecoratedAppSceneView : DecoratedFloatingView<AppSceneViewDelegate>
@property(nonatomic) BOOL isMaximized;
@property(nonatomic) CGFloat scaleRatio;
- (instancetype)initWithExtension:(NSExtension *)extension identifier:(NSUUID *)identifier windowName:(NSString*)windowName dataUUID:(NSString*)dataUUID;
@end

