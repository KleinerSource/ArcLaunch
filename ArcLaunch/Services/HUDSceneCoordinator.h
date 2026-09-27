#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ArcLaunchSettingsStore;
@class SystemApplicationBridge;

FOUNDATION_EXPORT BOOL ArcLaunchIsHUDProcess(void);
FOUNDATION_EXPORT int ArcLaunchRunHUDProcess(void);
FOUNDATION_EXPORT int ArcLaunchStopHUDProcessMain(pid_t processIdentifier);

@interface HUDSceneCoordinator : NSObject

@property (nonatomic, readonly, getter=isHUDActive) BOOL HUDActive;
@property (nonatomic, copy, readonly) NSString *statusDescription;

+ (instancetype)sharedCoordinator;
- (instancetype)initWithSettingsStore:(ArcLaunchSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge;
- (void)activateHUD;
- (void)deactivateHUD;
- (void)openConfiguration;

@end

NS_ASSUME_NONNULL_END
