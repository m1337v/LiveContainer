//
//  AppSceneView.h
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
#import "UIKitPrivate+MultitaskSupport.h"
#import "FoundationPrivate.h"
@import UIKit;
@import Foundation;

@protocol AppSceneViewDelegate <NSObject>
- (void)appDidExit;
@end

API_AVAILABLE(ios(16.0))
@interface AppSceneViewController : UIViewController<_UISceneSettingsDiffAction>
@property(nonatomic) UIWindowScene *hostScene;
@property(nonatomic) _UIScenePresenter *presenter;
@property(nonatomic) UIMutableApplicationSceneSettings *settings;
@property(nonatomic) NSString *sceneID;
@property(nonatomic) NSExtension* extension;
@property(nonatomic) NSString* dataUUID;
@property(nonatomic) int pid;
@property(nonatomic) id<AppSceneViewDelegate> delegate;
@property(nonatomic) BOOL isAppRunning;

- (instancetype)initWithExtension:(NSExtension *)extension  frame:(CGRect)frame identifier:(NSUUID *)identifier dataUUID:(NSString*)dataUUID delegate:(id<AppSceneViewDelegate>)delegate;

- (void)resizeWindowWithFrame:(CGRect)frame;
- (void)closeWindow;
@end

