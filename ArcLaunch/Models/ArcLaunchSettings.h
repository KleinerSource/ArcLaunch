#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSUInteger ArcLaunchMaximumShortcuts;
FOUNDATION_EXPORT const CGFloat ArcLaunchMinimumIconSize;
FOUNDATION_EXPORT const CGFloat ArcLaunchMaximumIconSize;
FOUNDATION_EXPORT const CGFloat ArcLaunchDefaultIconSize;
FOUNDATION_EXPORT const CGFloat ArcLaunchMinimumIconSpacing;
FOUNDATION_EXPORT const CGFloat ArcLaunchMaximumIconSpacing;
FOUNDATION_EXPORT const CGFloat ArcLaunchDefaultIconSpacing;
FOUNDATION_EXPORT const CGFloat ArcLaunchMinimumRingSpacing;
FOUNDATION_EXPORT const CGFloat ArcLaunchMaximumRingSpacing;
FOUNDATION_EXPORT const CGFloat ArcLaunchDefaultRingSpacing;
FOUNDATION_EXPORT const CGFloat ArcLaunchMinimumBackdropBlur;
FOUNDATION_EXPORT const CGFloat ArcLaunchDefaultBackdropBlur;
FOUNDATION_EXPORT const CGFloat ArcLaunchMinimumHandleTouchRadius;
FOUNDATION_EXPORT const CGFloat ArcLaunchMaximumHandleTouchRadius;
FOUNDATION_EXPORT const CGFloat ArcLaunchDefaultHandleTouchRadius;
FOUNDATION_EXPORT const CGFloat ArcLaunchMinimumFloatingWindowDwellDuration;
FOUNDATION_EXPORT const CGFloat ArcLaunchMaximumFloatingWindowDwellDuration;
FOUNDATION_EXPORT const CGFloat ArcLaunchDefaultFloatingWindowDwellDuration;
FOUNDATION_EXPORT const CGFloat ArcLaunchMinimumFixedTriggerInset;
FOUNDATION_EXPORT const CGFloat ArcLaunchMaximumFixedTriggerInset;

typedef NS_ENUM(NSInteger, ArcLaunchEdge) {
    ArcLaunchEdgeLeft = 0,
    ArcLaunchEdgeRight = 1,
};

typedef NS_ENUM(NSInteger, ArcLaunchMenuTriggerMode) {
    ArcLaunchMenuTriggerModeHandle = 0,
    ArcLaunchMenuTriggerModeFixedCorners = 1,
};

typedef NS_OPTIONS(NSUInteger, ArcLaunchFixedTriggerCorner) {
    ArcLaunchFixedTriggerCornerTopLeft = 1 << 0,
    ArcLaunchFixedTriggerCornerTopRight = 1 << 1,
    ArcLaunchFixedTriggerCornerBottomLeft = 1 << 2,
    ArcLaunchFixedTriggerCornerBottomRight = 1 << 3,
    ArcLaunchFixedTriggerCornerAll = (1 << 4) - 1,
};

// 数值与已保存的设置兼容，新增的“自动”放在末尾。
typedef NS_ENUM(NSInteger, ArcLaunchHandleStyle) {
    ArcLaunchHandleStyleLight = 0,
    ArcLaunchHandleStyleDark = 1,
    /// 不绘制悬浮条，但边缘热区仍可滑出菜单。
    ArcLaunchHandleStyleHidden = 2,
    /// 跟随系统深色模式。
    ArcLaunchHandleStyleAutomatic = 3,
};

typedef NS_ENUM(NSInteger, ArcLaunchBackdropStyle) {
    ArcLaunchBackdropStyleLight = 0,
    ArcLaunchBackdropStyleDark = 1,
    ArcLaunchBackdropStyleNone = 2,
    /// 跟随系统深色模式。
    ArcLaunchBackdropStyleAutomatic = 3,
};

/// 悬浮窗中的应用弹出软键盘时的显示方式。
typedef NS_ENUM(NSInteger, ArcLaunchKeyboardDisplayMode) {
    /// 键盘随应用画面一起等比缩放，显示在小窗内。
    ArcLaunchKeyboardDisplayModeInWindow = 0,
    /// 让系统键盘按设备屏幕布局显示；旧版场景通过临时铺满悬浮窗实现。
    ArcLaunchKeyboardDisplayModeFullScreen = 1,
};

@interface ArcLaunchShortcut : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSUUID *identifier;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
/// 兼容旧版本逐应用开关数据；新版本不再读取此值来决定启动方式。
@property (nonatomic) BOOL opensInFloatingWindow;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (nullable instancetype)shortcutFromDictionary:(NSDictionary<NSString *, id> *)dictionary;

@end

@interface ArcLaunchSettings : NSObject <NSCopying>

@property (nonatomic) BOOL enabled;
/// 总开关关闭时，悬浮应用快捷项改为全屏打开，不初始化悬浮分屏宿主。
@property (nonatomic) BOOL floatingSplitEnabled;
/// 在扇形菜单中悬停选中应用后，达到该时长再松手则以悬浮窗打开。
@property (nonatomic) CGFloat floatingWindowDwellDuration;
@property (nonatomic) ArcLaunchKeyboardDisplayMode keyboardDisplayMode;
@property (nonatomic) ArcLaunchMenuTriggerMode menuTriggerMode;
@property (nonatomic) ArcLaunchFixedTriggerCorner fixedTriggerCorners;
@property (nonatomic) BOOL landscapeTriggerEnabled;
@property (nonatomic) CGFloat fixedTriggerHorizontalInset;
@property (nonatomic) CGFloat fixedTriggerVerticalInset;
@property (nonatomic) ArcLaunchEdge edge;
@property (nonatomic) CGFloat normalizedVerticalPosition;
@property (nonatomic) CGFloat iconSize;
/// 同一圈内相邻图标之间的间距。
@property (nonatomic) CGFloat iconSpacing;
/// 相邻两圈之间的间距。
@property (nonatomic) CGFloat ringSpacing;
@property (nonatomic) ArcLaunchHandleStyle handleStyle;
/// 悬浮条触摸热区在可见条四周向外扩展的距离。
@property (nonatomic) CGFloat handleTouchRadius;
@property (nonatomic) ArcLaunchBackdropStyle backdropStyle;
/// 毛玻璃的模糊程度，1 为系统材质的完整模糊。
@property (nonatomic) CGFloat backdropBlur;
@property (nonatomic, strong) NSMutableArray<ArcLaunchShortcut *> *shortcuts;

/// 兼容旧版本逐应用开关数据；不再用于决定悬浮窗口模式。
@property (nonatomic, readonly) BOOL hasFloatingWindowShortcuts;
/// 悬浮分屏总开关开启时，HUD 子进程初始化宿主。
@property (nonatomic, readonly) BOOL shouldEnableFloatingAppHosting;

+ (instancetype)defaultSettings;
- (void)normalize;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (instancetype)settingsFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
