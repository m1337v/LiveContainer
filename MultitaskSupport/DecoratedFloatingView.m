#import "DecoratedFloatingView.h"
#import "ResizeHandleView.h"
#import "utils.h"

@implementation DecoratedFloatingView

- (instancetype)initWithFrame:(CGRect)frame {
    // Navigation bar
    UINavigationBar *navigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 44)];
    navigationBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UINavigationItem *navigationItem = [[UINavigationItem alloc] initWithTitle:@"Unnamed window"];
    navigationBar.items = @[navigationItem];
    return [self initWithFrame:frame navigationBar:navigationBar];
}

- (instancetype)initWithFrame:(CGRect)frame navigationBar:(UINavigationBar *)navigationBar {
    self = [super initWithFrame:frame];
    self.axis = UILayoutConstraintAxisVertical;
    self.backgroundColor = UIColor.systemBackgroundColor;
    self.layer.cornerRadius = 10;
    self.layer.masksToBounds = YES;

    self.navigationBar = navigationBar;
    self.navigationItem = navigationBar.items.firstObject;
    if (!self.navigationBar.superview) {
        [self addArrangedSubview:self.navigationBar];
    }
    
    CGFloat navBarHeight = self.navigationBar.frame.size.height;
    CGRect contentFrame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height - navBarHeight);
    UIView *fixedPositionContentView = [[UIView alloc] initWithFrame:contentFrame];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"]) {
        [self insertArrangedSubview:fixedPositionContentView atIndex:0];
    } else {
        [self addArrangedSubview:fixedPositionContentView];
    }
    [self sendSubviewToBack:fixedPositionContentView];
    
    self.contentView = [[UIView alloc] initWithFrame:contentFrame];
    self.contentView.layer.anchorPoint = self.contentView.layer.position = CGPointMake(0, 0);
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [fixedPositionContentView addSubview:self.contentView];
    
    UIPanGestureRecognizer *moveGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveWindow:)];
    moveGesture.minimumNumberOfTouches = 1;
    moveGesture.maximumNumberOfTouches = 1;
    [self.navigationBar addGestureRecognizer:moveGesture];

    // Resize handle (idea stolen from Notes debugging window)
    UIPanGestureRecognizer *resizeGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizeWindow:)];
    resizeGesture.minimumNumberOfTouches = 1;
    resizeGesture.maximumNumberOfTouches = 1;
    self.resizeHandle = [[ResizeHandleView alloc] initWithFrame:CGRectMake(self.frame.size.width - navBarHeight, self.frame.size.height - navBarHeight, navBarHeight, navBarHeight)];
    [self.resizeHandle addGestureRecognizer:resizeGesture];
    [self addSubview:self.resizeHandle];
    
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = UIColor.secondarySystemBackgroundColor.CGColor;
    
    return self;
}

- (void)moveWindow:(UIPanGestureRecognizer*)sender {
    CGPoint point = [sender translationInView:self];
    [sender setTranslation:CGPointZero inView:self];

    self.center = CGPointMake(self.center.x + point.x, self.center.y + point.y);
}

- (void)resizeWindow:(UIPanGestureRecognizer*)sender {
    CGPoint point = [sender translationInView:self];
    [sender setTranslation:CGPointZero inView:self];

    CGRect frame = self.frame;
    frame.size.width = MAX(50, frame.size.width + point.x);
    frame.size.height = MAX(50, frame.size.height + point.y);
    self.frame = frame;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    // FIXME: how to bring view to front when touching the passthrough view?
    [self.superview bringSubviewToFront:self];
}

@end
