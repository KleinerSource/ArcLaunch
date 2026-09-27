#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ArcLaunchSettingsStore;
@class SystemApplicationBridge;

FOUNDATION_EXPORT BOOL ArcLaunchIsHUDProcess(void);
/// HUD 子进程是否已成功初始化为悬浮分屏宿主。
FOUNDATION_EXPORT BOOL ArcLaunchFloatingAppHostingAvailable(void);
FOUNDATION_EXPORT int ArcLaunchRunHUDProcess(void);
FOUNDATION_EXPORT int ArcLaunchStopHUDProcessMain(pid_t processIdentifier);

@interface HUDSceneCoordinator : NSObject

/// HUD 子进程是否存活，不代表窗口已完成注册。
@property (nonatomic, readonly, getter=isHUDActive) BOOL HUDActive;
@property (nonatomic, copy, readonly) NSString *statusDescription;
/// 根据开关说明悬浮分屏宿主的初始化与回退行为。
@property (nonatomic, copy, readonly) NSString *floatingHostDescription;

+ (instancetype)sharedCoordinator;
- (instancetype)initWithSettingsStore:(ArcLaunchSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge;
- (void)activateHUD;
- (void)deactivateHUD;
- (void)openConfiguration;

@end

NS_ASSUME_NONNULL_END
