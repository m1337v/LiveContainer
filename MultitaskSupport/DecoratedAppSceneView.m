#import "DecoratedAppSceneView.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "AppSceneViewController.h"
#import "UIKitPrivate+MultitaskSupport.h"
#import "PiPManager.h"
#import "../LiveContainer/Localization.h"
#import "utils.h"

@implementation RBSTarget(hook)
+ (instancetype)hook_targetWithPid:(pid_t)pid environmentIdentifier:(NSString *)environmentIdentifier {
    if([environmentIdentifier containsString:@"LiveProcess"]) {
        environmentIdentifier = [NSString stringWithFormat:@"LiveProcess:%d", pid];
    }
    return [self hook_targetWithPid:pid environmentIdentifier:environmentIdentifier];
}
@end
static int hook_return_2(void) {
    return 2;
}
__attribute__((constructor))
void UIKitFixesInit(void) {
    // Fix _UIPrototypingMenuSlider not continually updating its value on iOS 17+
    Class _UIFluidSliderInteraction = objc_getClass("_UIFluidSliderInteraction");
    if(_UIFluidSliderInteraction) {
        method_setImplementation(class_getInstanceMethod(_UIFluidSliderInteraction, @selector(_state)), (IMP)hook_return_2);
    }
    // Fix physical keyboard focus on iOS 17+
    if(@available(iOS 17.0, *)) {
        method_exchangeImplementations(class_getClassMethod(RBSTarget.class, @selector(targetWithPid:environmentIdentifier:)), class_getClassMethod(RBSTarget.class, @selector(hook_targetWithPid:environmentIdentifier:)));
    }
}

@interface DecoratedAppSceneView()
@property(nonatomic) AppSceneViewController* appSceneView;
@property(nonatomic) NSString *sceneID;
@property(nonatomic) NSString* dataUUID;
@property(nonatomic) NSString* windowName;
@property(nonatomic) int pid;
@property(nonatomic) CGFloat scaleRatio;
@property(nonatomic) BOOL isMaximized;
@property(nonatomic) CGRect originalFrame;
@property(nonatomic) UIBarButtonItem *maximizeButton;

@end

@implementation DecoratedAppSceneView
- (instancetype)initWithExtension:(NSExtension *)extension identifier:(NSUUID *)identifier windowName:(NSString*)windowName dataUUID:(NSString*)dataUUID {
    self = [super initWithFrame:CGRectMake(0, 100, 320, 480 + 44)];
    AppSceneViewController* appSceneView = [[AppSceneViewController alloc] initWithExtension:extension frame:CGRectMake(0, 0, self.contentView.bounds.size.width, self.contentView.bounds.size.height) identifier:identifier dataUUID:dataUUID delegate:self];
    appSceneView.view.layer.anchorPoint = CGPointMake(0, 0);
    appSceneView.view.layer.position = CGPointMake(0, 0);
    self.appSceneView = appSceneView;
    int pid = appSceneView.pid;
    self.dataUUID = dataUUID;
    self.pid = pid;

    NSLog(@"Presenting app scene from PID %d", pid);
    
    self.scaleRatio = 1.0;
    self.isMaximized = NO;
    self.originalFrame = CGRectZero;
    NSArray *menuItems = @[
        [UIAction actionWithTitle:@"lc.multitask.copyPid".loc image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction * _Nonnull action) {
            UIPasteboard.generalPasteboard.string = @(pid).stringValue;
        }],
        [UIAction actionWithTitle:@"lc.multitask.enablePip".loc image:[UIImage systemImageNamed:@"pip.enter"] identifier:nil handler:^(UIAction * _Nonnull action) {
            if ([PiPManager.shared isPiPWithView:self.appSceneView.view]) {
                [PiPManager.shared stopPiP];
            } else {
                [PiPManager.shared startPiPWithView:self.appSceneView.view contentView:self.contentView extension:extension];
            }
        }],
        [UICustomViewMenuElement elementWithViewProvider:^UIView *(UICustomViewMenuElement *element) {
            return [self scaleSliderViewWithTitle:@"lc.multitask.scale".loc min:0.5 max:2.0 value:self.scaleRatio stepInterval:0.01];
        }]
    ];
    
    NSString *pidText = [NSString stringWithFormat:@"PID: %d", pid];
    __weak typeof(self) weakSelf = self;
    [self.navigationItem setTitleMenuProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions){
        if(!weakSelf.appSceneView.isAppRunning) {
            return [UIMenu menuWithTitle:NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", nil) children:@[]];
        } else {
            return [UIMenu menuWithTitle:pidText children:menuItems];
        }
    }];
    
    UIImage *minimizeImage = [UIImage systemImageNamed:@"minus.circle"];
    UIImageConfiguration *minimizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    minimizeImage = [minimizeImage imageWithConfiguration:minimizeConfig];
    UIBarButtonItem *minimizeButton = [[UIBarButtonItem alloc] initWithImage:minimizeImage style:UIBarButtonItemStylePlain target:self action:@selector(minimizeWindow)];
    minimizeButton.tintColor = [UIColor systemYellowColor];
    
    UIImage *maximizeImage = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right.circle"];
    UIImageConfiguration *maximizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    maximizeImage = [maximizeImage imageWithConfiguration:maximizeConfig];
    self.maximizeButton = [[UIBarButtonItem alloc] initWithImage:maximizeImage style:UIBarButtonItemStylePlain target:self action:@selector(maximizeWindow)];
    self.maximizeButton.tintColor = [UIColor systemGreenColor];
    
    UIImage *closeImage = [UIImage systemImageNamed:@"xmark.circle"];
    UIImageConfiguration *closeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    closeImage = [closeImage imageWithConfiguration:closeConfig];
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithImage:closeImage style:UIBarButtonItemStylePlain target:self action:@selector(closeWindow)];
    closeButton.tintColor = [UIColor systemRedColor];
    
    NSArray *barButtonItems = @[closeButton, self.maximizeButton, minimizeButton];
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"]) {
        // resize handle overlaps the close button, so put the buttons on the left
        self.navigationItem.leftBarButtonItems = barButtonItems;
    } else {
        self.navigationItem.rightBarButtonItems = barButtonItems;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self adjustNavigationBarButtonSpacingWithNegativeSpacing:-8.0 rightMargin:-4.0];
    });
    
    self.windowName = windowName;
    self.navigationItem.title = windowName;
    
    [self.contentView insertSubview:appSceneView.view atIndex:0];

    
    return self;
}

// Stolen from UIKitester
- (UIView *)scaleSliderViewWithTitle:(NSString *)title min:(CGFloat)minValue max:(CGFloat)maxValue value:(CGFloat)initialValue stepInterval:(CGFloat)step {
    UIView *containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.exclusiveTouch = YES;
    
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 0.0;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:stackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:10.0],
        [stackView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-8.0],
        [stackView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16.0],
        [stackView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16.0]
    ]];
    
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont boldSystemFontOfSize:12.0];
    [stackView addArrangedSubview:label];
    
    _UIPrototypingMenuSlider *slider = [[_UIPrototypingMenuSlider alloc] init];
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = initialValue;
    slider.stepSize = step;
    
    NSLayoutConstraint *sliderHeight = [slider.heightAnchor constraintEqualToConstant:40.0];
    sliderHeight.active = YES;
    
    [stackView addArrangedSubview:slider];
    
    [slider addTarget:self action:@selector(scaleSliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    return containerView;
}

- (void)scaleSliderChanged:(_UIPrototypingMenuSlider *)slider {
    self.scaleRatio = slider.value;
    CGSize size = self.contentView.bounds.size;
    self.contentView.layer.sublayerTransform = CATransform3DMakeScale(_scaleRatio, _scaleRatio, 1.0);
    [self.appSceneView resizeWindowWithFrame:CGRectMake(0, 0, size.width / _scaleRatio, size.height / _scaleRatio)];
}

- (void)closeWindow {
    [self.appSceneView closeWindow];
}

- (void)minimizeWindow {
    [UIView animateWithDuration:0.3 
                          delay:0 
                        options:UIViewAnimationOptionCurveEaseInOut 
                     animations:^{
                         self.alpha = 0;
                         self.transform = CGAffineTransformMakeScale(0.1, 0.1);
                     } 
                     completion:^(BOOL finished) {
                         self.hidden = YES;
                     }];
}

- (void)maximizeWindow {
    if (self.isMaximized) {
        [UIView animateWithDuration:0.3 
                              delay:0 
                            options:UIViewAnimationOptionCurveEaseInOut 
                         animations:^{
                             self.frame = self.originalFrame;
                         } 
                         completion:^(BOOL finished) {
                             self.isMaximized = NO;
                             UIImage *maximizeImage = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right.circle"];
                             UIImageConfiguration *maximizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
                             self.maximizeButton.image = [maximizeImage imageWithConfiguration:maximizeConfig];
                             CGSize size = self.contentView.bounds.size;
                             [self.appSceneView resizeWindowWithFrame:CGRectMake(0, 0, size.width / self.scaleRatio, size.height / self.scaleRatio)];
                         }];
    } else {
        self.originalFrame = self.frame;
        
        UIEdgeInsets safeAreaInsets = UIApplication.sharedApplication.keyWindow.safeAreaInsets;
        CGRect maxFrame = UIEdgeInsetsInsetRect(UIScreen.mainScreen.bounds, safeAreaInsets);
        
        [UIView animateWithDuration:0.3 
                              delay:0 
                            options:UIViewAnimationOptionCurveEaseInOut 
                         animations:^{
                             self.frame = maxFrame;
                         } 
                         completion:^(BOOL finished) {
                             self.isMaximized = YES;
                             UIImage *restoreImage = [UIImage systemImageNamed:@"arrow.down.right.and.arrow.up.left.circle"];
                             UIImageConfiguration *restoreConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
                             self.maximizeButton.image = [restoreImage imageWithConfiguration:restoreConfig];
                             CGSize size = self.contentView.bounds.size;
                             [self.appSceneView resizeWindowWithFrame:CGRectMake(0, 0, size.width / self.scaleRatio, size.height / self.scaleRatio)];
                         }];
    }
}

- (void)resizeWindow:(UIPanGestureRecognizer*)sender {
    [super resizeWindow:sender];
    CGSize size = self.contentView.bounds.size;
    [self.appSceneView resizeWindowWithFrame:CGRectMake(0, 0, size.width / _scaleRatio, size.height / _scaleRatio)];
}

- (void)appDidExit {
    MultitaskDockManager *dock = [MultitaskDockManager shared];
    [dock removeRunningApp:self.dataUUID];
    
    self.layer.masksToBounds = NO;
    [UIView transitionWithView:self duration:0.4 options:UIViewAnimationOptionTransitionCurlUp animations:^{
        self.hidden = YES;
    } completion:^(BOOL b){
        [self removeFromSuperview];
    }];
}

- (void)adjustNavigationBarButtonSpacingWithNegativeSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    if (!self.navigationBar) return;
    
    [self findAndAdjustButtonBarStackView:self.navigationBar withSpacing:spacing rightMargin:margin];
}

- (void)findAndAdjustButtonBarStackView:(UIView *)view withSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"_UIButtonBarStackView")]) {
            if ([subview respondsToSelector:@selector(setSpacing:)]) {
                [(_UIButtonBarStackView *)subview setSpacing:spacing];
            }
            
            if (subview.superview) {
                for (NSLayoutConstraint *constraint in subview.superview.constraints) {
                    if ((constraint.firstItem == subview && constraint.firstAttribute == NSLayoutAttributeTrailing) ||
                        (constraint.secondItem == subview && constraint.secondAttribute == NSLayoutAttributeTrailing)) {
                        constraint.constant = (constraint.firstItem == subview) ? -margin : margin;
                        break;
                    }
                }
                
                [subview setNeedsLayout];
                [subview.superview setNeedsLayout];
            }
            
            return;
        }
        
        [self findAndAdjustButtonBarStackView:subview withSpacing:spacing rightMargin:margin];
    }
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
    [super willMoveToSuperview:newSuperview];
    NSUserDefaults *defaults = NSUserDefaults.lcSharedDefaults;
    if(newSuperview) {
        [defaults addObserver:self forKeyPath:@"LCMultitaskBottomWindowBar" options:NSKeyValueObservingOptionNew context:NULL];
    } else {
        [defaults removeObserver:self forKeyPath:@"LCMultitaskBottomWindowBar"];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    BOOL bottomWindowBar = [change[NSKeyValueChangeNewKey] boolValue];
    [UIView animateWithDuration:0.3 animations:^{
        if(bottomWindowBar) {
            self.navigationItem.leftBarButtonItems = self.navigationItem.rightBarButtonItems;
            self.navigationItem.rightBarButtonItems = nil;
            [self addArrangedSubview:self.navigationBar];
        } else {
            self.navigationItem.rightBarButtonItems = self.navigationItem.leftBarButtonItems;
            self.navigationItem.leftBarButtonItems = nil;
            [self insertArrangedSubview:self.navigationBar atIndex:0];
        }
        [self adjustNavigationBarButtonSpacingWithNegativeSpacing:-8.0 rightMargin:-4.0];
    }];
}
@end
