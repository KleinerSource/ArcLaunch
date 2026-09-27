#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ArcLaunchSettingsStore;
@class SystemApplicationBridge;
@class HUDSceneCoordinator;
@class ArcLaunchUpdateChecker;

@interface ConfigurationViewController : UITableViewController

- (instancetype)initWithSettingsStore:(ArcLaunchSettingsStore *)settingsStore
                    applicationBridge:(SystemApplicationBridge *)applicationBridge
                 hudSceneCoordinator:(HUDSceneCoordinator *)hudSceneCoordinator
                        updateChecker:(ArcLaunchUpdateChecker *)updateChecker;

@end

NS_ASSUME_NONNULL_END
