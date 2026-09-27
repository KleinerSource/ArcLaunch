#import <UIKit/UIKit.h>
#import "ArcLaunchSettings.h"

NS_ASSUME_NONNULL_BEGIN

@class ArcLaunchShortcut;
@class SystemApplicationBridge;

/// 管理 HUD 中最多 3 个悬浮窗及屏幕边缘的收纳区，只在 HUD 子进程且悬浮分屏宿主可用时创建。
@interface FloatingAppWindowManager : NSObject

@property (nonatomic, copy, nullable) void (^feedbackHandler)(NSString *message);
/// 窗口增删、收起、恢复、边栏隐藏或整体隐藏后回调，HUD 据此刷新可接收触摸的区域。
@property (nonatomic, copy, nullable) dispatch_block_t interactiveViewsDidChangeHandler;
/// 需要接收触摸的窗口与收纳区底板；整体隐藏时为空。
@property (nonatomic, copy, readonly) NSArray<UIView *> *interactiveViews;
@property (nonatomic) UIUserInterfaceStyle userInterfaceStyle;
@property (nonatomic) ArcLaunchHandleStyle handleStyle;
/// 悬浮应用弹出软键盘时的显示方式；切回小窗内模式会立即恢复正在全屏显示键盘的窗口。
@property (nonatomic) ArcLaunchKeyboardDisplayMode keyboardDisplayMode;

- (instancetype)initWithContainerView:(UIView *)containerView parentViewController:(UIViewController *)parentViewController applicationBridge:(SystemApplicationBridge *)applicationBridge;
- (instancetype)init NS_UNAVAILABLE;
/// 以悬浮窗打开或切换应用；切换时当前展开的应用自动收进边栏。point 为弹出动画的起点（悬浮条位置）。
- (void)openShortcut:(ArcLaunchShortcut *)shortcut icon:(nullable UIImage *)icon fromPoint:(CGPoint)point;
/// 锁屏时隐藏全部窗口，场景保持运行。
- (void)setWindowsHidden:(BOOL)hidden;
/// 将当前展开的窗口收进边栏。
- (void)minimizeExpandedWindows;
- (void)closeAllWindows;

@end

NS_ASSUME_NONNULL_END
