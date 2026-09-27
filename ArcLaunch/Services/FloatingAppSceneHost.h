#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ArcLaunchFloatingSceneCompletion)(BOOL success, NSString * _Nullable failureReason);

/// 在 HUD 进程中托管另一个应用的一个 FrontBoard 场景，只能在悬浮分屏宿主已初始化后使用。
/// 应用未运行时由本进程启动；已在运行时直接附加一个新场景，不结束原有进程。
@interface FloatingAppSceneHost : NSObject

@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
/// 场景就绪后可用的应用画面（CALayerHost），始终按竖屏全屏尺寸布局。
@property (nonatomic, strong, readonly, nullable) UIView *presentationView;
/// 应用按全屏布局时使用的安全区，需在 start 之前设置。
@property (nonatomic) UIEdgeInsets sceneSafeAreaInsets;
@property (nonatomic) UIUserInterfaceStyle userInterfaceStyle;
/// 被托管的应用进程退出时在主线程回调。
@property (nonatomic, copy, nullable) dispatch_block_t processExitHandler;
/// 被托管应用的软键盘弹出或收起时在主线程回调；需安装键盘桥接插件。
@property (nonatomic, copy, nullable) void (^keyboardVisibilityHandler)(BOOL visible);

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier parentViewController:(UIViewController *)parentViewController;
- (instancetype)init NS_UNAVAILABLE;
- (void)startWithCompletion:(ArcLaunchFloatingSceneCompletion)completion;
/// 将 scene view 挂到宿主窗口后调用，完成 UIKit 子控制器关系。
- (void)didAttachPresentationView;
- (void)updateUserInterfaceStyle:(UIUserInterfaceStyle)userInterfaceStyle;
/// 销毁场景；应用是由本宿主启动的则一并结束进程。
- (void)invalidate;
/// 只销毁场景、保留进程，随后交给 SpringBoard 全屏打开。
- (void)detachForFullScreenLaunch;

@end

NS_ASSUME_NONNULL_END
