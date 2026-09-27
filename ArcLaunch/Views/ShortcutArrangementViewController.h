#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ArcLaunchSettingsStore;
@class SystemApplicationBridge;

/// 全屏展示与悬浮条完全相同的扇形菜单，长按图标拖动即可调整顺序，松手立即保存。
@interface ShortcutArrangementViewController : UIViewController

- (instancetype)initWithSettingsStore:(ArcLaunchSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge;

@end

NS_ASSUME_NONNULL_END
