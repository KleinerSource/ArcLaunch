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

@interface ArcLaunchShortcut : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSUUID *identifier;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (nullable instancetype)shortcutFromDictionary:(NSDictionary<NSString *, id> *)dictionary;

@end

@interface ArcLaunchSettings : NSObject <NSCopying>

@property (nonatomic) BOOL enabled;
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

+ (instancetype)defaultSettings;
- (void)normalize;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (instancetype)settingsFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
