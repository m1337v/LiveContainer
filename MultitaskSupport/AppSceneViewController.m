//
//  AppSceneView.m
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
#import "AppSceneViewController.h"
#import "DecoratedAppSceneView.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "../LiveContainerSwiftUI/LCUtils.h"
#import "PiPManager.h"

@implementation AppSceneViewController {
    int resizeDebounceToken;
    CGRect currentFrame;
    CGPoint normalizedOrigin;
    bool isNativeWindow;
    NSUUID* identifier;
}

- (instancetype)initWithExtension:(NSExtension *)extension frame:(CGRect)frame identifier:(NSUUID *)identifier dataUUID:(NSString*)dataUUID delegate:(id<AppSceneViewDelegate>)delegate {
    self = [super initWithNibName:nil bundle:nil];
    int pid = [extension pidForRequestIdentifier:identifier];
    currentFrame = frame;
    self.delegate = delegate;
    self.extension = extension;
    self.dataUUID = dataUUID;
    self.pid = pid;
    self->identifier = identifier;
    isNativeWindow = [[[NSUserDefaults alloc] initWithSuiteName:[LCUtils appGroupID]] integerForKey:@"LCMultitaskMode" ] == 1;
    RBSProcessPredicate* predicate = [PrivClass(RBSProcessPredicate) predicateMatchingIdentifier:@(pid)];
    
    FBProcessManager *manager = [PrivClass(FBProcessManager) sharedInstance];
    // At this point, the process is spawned and we're ready to create a scene to render in our app
    RBSProcessHandle* processHandle = [PrivClass(RBSProcessHandle) handleForPredicate:predicate error:nil];
    [manager registerProcessForAuditToken:processHandle.auditToken];
    // NSString *identifier = [NSString stringWithFormat:@"sceneID:%@-%@", bundleID, @"default"];
    self.sceneID = [NSString stringWithFormat:@"sceneID:%@-%@", @"LiveProcess", NSUUID.UUID.UUIDString];
    
    FBSMutableSceneDefinition *definition = [PrivClass(FBSMutableSceneDefinition) definition];
    definition.identity = [PrivClass(FBSSceneIdentity) identityForIdentifier:self.sceneID];
    definition.clientIdentity = [PrivClass(FBSSceneClientIdentity) identityForProcessIdentity:processHandle.identity];
    definition.specification = [UIApplicationSceneSpecification specification];
    FBSMutableSceneParameters *parameters = [PrivClass(FBSMutableSceneParameters) parametersForSpecification:definition.specification];
    
    UIMutableApplicationSceneSettings *settings = [UIMutableApplicationSceneSettings new];
    settings.canShowAlerts = YES;
    settings.cornerRadiusConfiguration = [[PrivClass(BSCornerRadiusConfiguration) alloc] initWithTopLeft:self.view.layer.cornerRadius bottomLeft:self.view.layer.cornerRadius bottomRight:self.view.layer.cornerRadius topRight:self.view.layer.cornerRadius];
    settings.displayConfiguration = UIScreen.mainScreen.displayConfiguration;
    settings.foreground = YES;

    settings.deviceOrientation = UIDevice.currentDevice.orientation;
    settings.interfaceOrientation = UIApplication.sharedApplication.statusBarOrientation;
    if(UIInterfaceOrientationIsLandscape(settings.interfaceOrientation)) {
        settings.frame = CGRectMake(0, 0, frame.size.height, frame.size.width);
    } else {
        settings.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
    }
    //settings.interruptionPolicy = 2; // reconnect
    settings.level = 1;
    settings.persistenceIdentifier = NSUUID.UUID.UUIDString;
    if(isNativeWindow) {
        UIEdgeInsets defaultInsets = UIApplication.sharedApplication.keyWindow.safeAreaInsets;
        settings.peripheryInsets = defaultInsets;
        settings.safeAreaInsetsPortrait = defaultInsets;
    } else {
        // it seems some apps don't honor these settings so we don't cover the top of the app
        settings.peripheryInsets = UIEdgeInsetsMake(0, 0, 0, 0);
        settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(0, 0, 0, 0);
    }


    settings.statusBarDisabled = !isNativeWindow;
    //settings.previewMaximumSize =
    //settings.deviceOrientationEventsEnabled = YES;
    self.settings = settings;
    parameters.settings = settings;
    
    UIMutableApplicationSceneClientSettings *clientSettings = [UIMutableApplicationSceneClientSettings new];
    clientSettings.interfaceOrientation = UIInterfaceOrientationPortrait;
    clientSettings.statusBarStyle = 0;
    parameters.clientSettings = clientSettings;
    
    FBScene *scene = [[PrivClass(FBSceneManager) sharedInstance] createSceneWithDefinition:definition initialParameters:parameters];
    
    self.presenter = [scene.uiPresentationManager createPresenterWithIdentifier:self.sceneID];
    [self.presenter modifyPresentationContext:^(UIMutableScenePresentationContext *context) {
        context.appearanceStyle = 2;
    }];
    [self.presenter activate];
    __weak typeof(self) weakSelf = self;
    [extension setRequestInterruptionBlock:^(NSUUID *uuid) {
        NSLog(@"Request %@ interrupted.", uuid);
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf displayAppTerminatedTextIfNeeded];
        });
    }];
    
    self.view = self.presenter.presentationView;
    [MultitaskManager registerMultitaskContainerWithContainer:dataUUID];
    return self;
}

// this method should not be called in native window mode
- (void)resizeWindowWithFrame:(CGRect)frame {
    __block int currentDebounceToken = self->resizeDebounceToken + 1;
    self->resizeDebounceToken = currentDebounceToken;
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC));
    dispatch_after(delay, dispatch_get_main_queue(), ^{
        if(currentDebounceToken != self->resizeDebounceToken) {
            return;
        }
        self->currentFrame = frame;
        [self.presenter.scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
            settings.deviceOrientation = UIDevice.currentDevice.orientation;
            settings.interfaceOrientation = self.view.window.windowScene.interfaceOrientation;
            if(UIInterfaceOrientationIsLandscape(settings.interfaceOrientation)) {
                CGRect frame2 = CGRectMake(frame.origin.x, frame.origin.y, frame.size.height, frame.size.width);
                settings.frame = frame2;
            } else {
                settings.frame = frame;
            }
        }];
    });
}

- (void)closeWindow {
    __weak typeof(self) weakSelf = self;
    [self.extension setRequestInterruptionBlock:^(NSUUID *uuid) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf closeWindow];
        });
    }];
    [self.view.window.windowScene _unregisterSettingsDiffActionArrayForKey:self.sceneID];
    [[PrivClass(FBSceneManager) sharedInstance] destroyScene:self.sceneID withTransitionContext:nil];
    if(self.presenter){
        [self.presenter deactivate];
        [self.presenter invalidate];
        self.presenter = nil;
    }
    if(self.isAppRunning) {
        [self.extension _kill:SIGTERM];
        NSLog(@"sent sigterm");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.extension _kill:SIGKILL];
        });
    } else {
        [self.delegate appDidExit];
        self.delegate = nil;
        [MultitaskManager unregisterMultitaskContainerWithContainer:self.dataUUID];
        
        MultitaskDockManager *dock = [MultitaskDockManager shared];
        [dock removeRunningApp:self.dataUUID];
    }
}

- (void)_performActionsForUIScene:(UIScene *)scene withUpdatedFBSScene:(id)fbsScene settingsDiff:(FBSSceneSettingsDiff *)diff fromSettings:(UIApplicationSceneSettings *)settings transitionContext:(id)context lifecycleActionType:(uint32_t)actionType {
    [self displayAppTerminatedTextIfNeeded];
    if(!diff) return;
    
    UIMutableApplicationSceneSettings *baseSettings = [diff settingsByApplyingToMutableCopyOfSettings:settings];
    UIApplicationSceneTransitionContext *newContext = [context copy];
    newContext.actions = nil;
    if(isNativeWindow) {
        // directly update the settings
        baseSettings.interruptionPolicy = 0;
        baseSettings.safeAreaInsetsPortrait = self.view.window.safeAreaInsets;
        baseSettings.peripheryInsets = self.view.window.safeAreaInsets;
        [self.presenter.scene updateSettings:baseSettings withTransitionContext:newContext completion:nil];
    } else {
        UIMutableApplicationSceneSettings *newSettings = [self.presenter.scene.settings mutableCopy];
        newSettings.userInterfaceStyle = baseSettings.userInterfaceStyle;
        newSettings.interfaceOrientation = baseSettings.interfaceOrientation;
        newSettings.deviceOrientation = baseSettings.deviceOrientation;
        newSettings.foreground = YES;
        
        DecoratedAppSceneView *sceneView = (id)self.delegate;
        CGRect windowFrame = self.view.window.frame;
        CGRect newFrame = currentFrame;
        if(sceneView.isMaximized) {
            UIEdgeInsets safeAreaInsets = self.view.window.safeAreaInsets;
            CGRect maxFrame = UIEdgeInsetsInsetRect(windowFrame, safeAreaInsets);
            sceneView.frame = maxFrame;
            newFrame = CGRectMake(0, 0, maxFrame.size.width/sceneView.scaleRatio, (maxFrame.size.height - sceneView.navigationBar.frame.size.height)/sceneView.scaleRatio);
        }
        if(UIInterfaceOrientationIsLandscape(baseSettings.interfaceOrientation)) {
            newSettings.frame = CGRectMake(0, 0, newFrame.size.height, newFrame.size.width);
        } else {
            newSettings.frame = CGRectMake(0, 0, newFrame.size.width, newFrame.size.height);
        }
        [self.presenter.scene updateSettings:newSettings withTransitionContext:newContext completion:nil];
    }
}

- (void)displayAppTerminatedTextIfNeeded {
    if(!self.isAppRunning) {
        [MultitaskManager unregisterMultitaskContainerWithContainer:self.dataUUID];
        if(!isNativeWindow) {
            UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
            label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            label.lineBreakMode = NSLineBreakByWordWrapping;
            label.numberOfLines = 0;
            label.text = NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", @"");
            label.textAlignment = NSTextAlignmentCenter;
            [self.view.superview addSubview:label];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.view.window.windowScene _registerSettingsDiffActionArray:@[self] forKey:self.sceneID];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self displayAppTerminatedTextIfNeeded];
    [self.view.window.windowScene _registerSettingsDiffActionArray:@[self] forKey:self.sceneID];
}

- (BOOL)isAppRunning {
    return _pid > 0 && getpgid(_pid) > 0;
}

@end
 
