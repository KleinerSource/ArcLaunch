#import "ArcLaunchSettingsStore.h"
#import "ArcLaunchSharedStorage.h"
#import <notify.h>

NSNotificationName const ArcLaunchSettingsDidChangeNotification = @"ArcLaunchSettingsDidChangeNotification";
static NSString * const ArcLaunchSettingsDefaultsKey = @"ArcLaunch.Settings";
// 主程序与 HUD 子进程通过共享文件保存设置，用 Darwin 通知互相告知变更。
static const char * const ArcLaunchSettingsDarwinNotification = "com.kleinersource.arclaunch.settings-changed";

@interface ArcLaunchSettingsStore ()
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, copy) NSString *defaultsKey;
@property (nonatomic, copy, nullable) NSString *sharedStorageKey;
@property (nonatomic, copy, readwrite) ArcLaunchSettings *settings;
@property (nonatomic, copy, nullable) NSData *lastSyncedData;
@property (nonatomic) int externalChangeToken;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults key:(NSString *)key sharedStorageKey:(nullable NSString *)sharedStorageKey;
@end

@implementation ArcLaunchSettingsStore

+ (instancetype)sharedStore {
    static ArcLaunchSettingsStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] initWithUserDefaults:NSUserDefaults.standardUserDefaults key:ArcLaunchSettingsDefaultsKey sharedStorageKey:@"settings.json"];
    });
    return store;
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults key:(NSString *)key {
    return [self initWithUserDefaults:userDefaults key:key sharedStorageKey:nil];
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults key:(NSString *)key sharedStorageKey:(NSString *)sharedStorageKey {
    self = [super init];
    if (self) {
        _userDefaults = userDefaults;
        _defaultsKey = [key copy];
        _sharedStorageKey = [sharedStorageKey copy];
        _externalChangeToken = NOTIFY_TOKEN_INVALID;
        [self reload];
        if (_sharedStorageKey) {
            __weak typeof(self) weakSelf = self;
            notify_register_dispatch(ArcLaunchSettingsDarwinNotification, &_externalChangeToken, dispatch_get_main_queue(), ^(int token) {
                [weakSelf handleExternalChange];
            });
        }
    }
    return self;
}

- (void)dealloc {
    if (_externalChangeToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(_externalChangeToken);
    }
}

- (void)handleExternalChange {
    NSData *data = [ArcLaunchSharedStorage dataForKey:self.sharedStorageKey];
    // 自己写入后也会收到通知；内容未变化时忽略，避免重复刷新界面。
    if (!data || [data isEqualToData:self.lastSyncedData]) {
        return;
    }
    [self reload];
    [[NSNotificationCenter defaultCenter] postNotificationName:ArcLaunchSettingsDidChangeNotification object:self];
}

- (void)reload {
    NSData *data = self.sharedStorageKey ? [ArcLaunchSharedStorage dataForKey:self.sharedStorageKey] : nil;
    BOOL hasSharedData = data != nil;
    if (!data) {
        data = [self.userDefaults dataForKey:self.defaultsKey];
    }
    NSDictionary *dictionary = nil;
    if (data) {
        id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([value isKindOfClass:NSDictionary.class]) {
            dictionary = value;
        }
    }
    self.settings = [ArcLaunchSettings settingsFromDictionary:dictionary];
    if (hasSharedData) {
        self.lastSyncedData = data;
    } else if (self.sharedStorageKey) {
        NSData *sharedData = [NSJSONSerialization dataWithJSONObject:self.settings.dictionaryRepresentation options:0 error:nil];
        if (sharedData) {
            [ArcLaunchSharedStorage setData:sharedData forKey:self.sharedStorageKey];
            self.lastSyncedData = sharedData;
        }
    }
}

- (void)mutateSettings:(void (NS_NOESCAPE ^)(ArcLaunchSettings *settings))mutation {
    [self reload];
    mutation(self.settings);
    [self.settings normalize];
    NSDictionary *dictionary = self.settings.dictionaryRepresentation;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    if (data) {
        [self.userDefaults setObject:data forKey:self.defaultsKey];
        if (self.sharedStorageKey && [ArcLaunchSharedStorage setData:data forKey:self.sharedStorageKey]) {
            self.lastSyncedData = data;
            notify_post(ArcLaunchSettingsDarwinNotification);
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ArcLaunchSettingsDidChangeNotification object:self];
}

- (BOOL)addShortcut:(ArcLaunchShortcut *)shortcut {
    [self reload];
    if (shortcut.bundleIdentifier.length == 0 || self.settings.shortcuts.count >= ArcLaunchMaximumShortcuts) {
        return NO;
    }
    for (ArcLaunchShortcut *existingShortcut in self.settings.shortcuts) {
        if ([existingShortcut.bundleIdentifier caseInsensitiveCompare:shortcut.bundleIdentifier] == NSOrderedSame) {
            return NO;
        }
    }
    [self mutateSettings:^(ArcLaunchSettings *settings) {
        [settings.shortcuts addObject:shortcut];
    }];
    return YES;
}

- (void)removeShortcutAtIndex:(NSUInteger)index {
    if (index >= self.settings.shortcuts.count) {
        return;
    }
    [self mutateSettings:^(ArcLaunchSettings *settings) {
        [settings.shortcuts removeObjectAtIndex:index];
    }];
}

- (void)moveShortcutFromIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex {
    if (fromIndex >= self.settings.shortcuts.count || toIndex >= self.settings.shortcuts.count || fromIndex == toIndex) {
        return;
    }
    [self mutateSettings:^(ArcLaunchSettings *settings) {
        ArcLaunchShortcut *shortcut = settings.shortcuts[fromIndex];
        [settings.shortcuts removeObjectAtIndex:fromIndex];
        [settings.shortcuts insertObject:shortcut atIndex:toIndex];
    }];
}

- (void)setShortcutAtIndex:(NSUInteger)index opensInFloatingWindow:(BOOL)opensInFloatingWindow {
    if (index >= self.settings.shortcuts.count || self.settings.shortcuts[index].opensInFloatingWindow == opensInFloatingWindow) {
        return;
    }
    [self mutateSettings:^(ArcLaunchSettings *settings) {
        if (index < settings.shortcuts.count) {
            settings.shortcuts[index].opensInFloatingWindow = opensInFloatingWindow;
        }
    }];
}

@end
