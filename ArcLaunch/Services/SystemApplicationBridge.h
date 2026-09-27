#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ArcLaunchApplicationCategory) {
    ArcLaunchApplicationCategoryUser = 0,
    ArcLaunchApplicationCategoryTrollStore = 1,
    ArcLaunchApplicationCategorySystem = 2,
};

@interface ArcLaunchApplication : NSObject

@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, strong, readonly, nullable) UIImage *icon;
@property (nonatomic, readonly) ArcLaunchApplicationCategory category;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName icon:(nullable UIImage *)icon;
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName icon:(nullable UIImage *)icon category:(ArcLaunchApplicationCategory)category;

@end

typedef NSArray<ArcLaunchApplication *> * _Nonnull (^ArcLaunchApplicationProvider)(void);
typedef BOOL (^ArcLaunchApplicationLauncher)(NSString *bundleIdentifier);

/// 设置页列表统一使用的 29pt 圆形图标，与悬浮菜单中的圆形图标保持一致；icon 为空时返回占位图标。
FOUNDATION_EXPORT UIImage *ArcLaunchListIconImage(UIImage * _Nullable icon);

@protocol ArcLaunchSystemApplicationBridging <NSObject>
- (NSArray<ArcLaunchApplication *> *)availableApplications;
- (nullable UIImage *)iconForBundleIdentifier:(NSString *)bundleIdentifier;
- (BOOL)launchBundleIdentifier:(NSString *)bundleIdentifier;
- (BOOL)isAvailable;
- (NSString *)unavailabilityReason;
@end

@interface SystemApplicationBridge : NSObject <ArcLaunchSystemApplicationBridging>

- (instancetype)init;
- (instancetype)initWithApplicationProvider:(nullable ArcLaunchApplicationProvider)applicationProvider launcher:(nullable ArcLaunchApplicationLauncher)launcher;

@end

NS_ASSUME_NONNULL_END
