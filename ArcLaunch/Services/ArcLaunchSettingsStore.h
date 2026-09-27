#import <Foundation/Foundation.h>
#import "ArcLaunchSettings.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const ArcLaunchSettingsDidChangeNotification;

@interface ArcLaunchSettingsStore : NSObject

@property (nonatomic, copy, readonly) ArcLaunchSettings *settings;

+ (instancetype)sharedStore;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults key:(NSString *)key;
- (void)mutateSettings:(void (NS_NOESCAPE ^)(ArcLaunchSettings *settings))mutation;
- (BOOL)addShortcut:(ArcLaunchShortcut *)shortcut;
- (void)removeShortcutAtIndex:(NSUInteger)index;
- (void)moveShortcutFromIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex;
- (void)reload;

@end

NS_ASSUME_NONNULL_END
