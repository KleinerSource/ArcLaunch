@import XCTest;

#import "ArcLaunchSettingsStore.h"

@interface ArcLaunchSettingsStoreTests : XCTestCase
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, copy) NSString *key;
@end

@implementation ArcLaunchSettingsStoreTests

- (void)setUp {
    [super setUp];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"ArcLaunchTests.%@", [[NSUUID UUID] UUIDString]]];
    self.key = @"settings";
}

- (void)tearDown {
    [super tearDown];
}

- (void)testDefaultsAreStable {
    ArcLaunchSettingsStore *store = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertTrue(store.settings.enabled);
    XCTAssertEqual(store.settings.shortcuts.count, 0);
    XCTAssertEqual(store.settings.edge, ArcLaunchEdgeRight);
}

- (void)testMalformedJSONFallsBackToDefaults {
    [self.defaults setObject:[@"not-json" dataUsingEncoding:NSUTF8StringEncoding] forKey:self.key];
    ArcLaunchSettingsStore *store = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqual(store.settings.shortcuts.count, 0);
    XCTAssertEqualWithAccuracy(store.settings.normalizedVerticalPosition, 0.5, 0.001);
}

- (void)testAddCapsAtMaximumAndRejectsDuplicates {
    ArcLaunchSettingsStore *store = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    for (NSUInteger index = 0; index < ArcLaunchMaximumShortcuts; index++) {
        ArcLaunchShortcut *shortcut = [[ArcLaunchShortcut alloc] initWithBundleIdentifier:[NSString stringWithFormat:@"com.example.%lu", (unsigned long)index] displayName:@"App"];
        XCTAssertTrue([store addShortcut:shortcut]);
    }
    XCTAssertFalse([store addShortcut:[[ArcLaunchShortcut alloc] initWithBundleIdentifier:@"com.example.extra" displayName:@"Extra"]]);
    XCTAssertFalse([store addShortcut:[[ArcLaunchShortcut alloc] initWithBundleIdentifier:@"com.example.0" displayName:@"Duplicate"]]);
    XCTAssertEqual(store.settings.shortcuts.count, ArcLaunchMaximumShortcuts);
}

- (void)testOrderPersistsAfterMove {
    ArcLaunchSettingsStore *store = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    [store addShortcut:[[ArcLaunchShortcut alloc] initWithBundleIdentifier:@"com.example.first" displayName:@"First"]];
    [store addShortcut:[[ArcLaunchShortcut alloc] initWithBundleIdentifier:@"com.example.second" displayName:@"Second"]];
    [store moveShortcutFromIndex:0 toIndex:1];

    ArcLaunchSettingsStore *reloadedStore = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqualObjects(reloadedStore.settings.shortcuts.firstObject.bundleIdentifier, @"com.example.second");
}

- (void)testIconMetricsPersistAndClamp {
    ArcLaunchSettingsStore *store = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqualWithAccuracy(store.settings.iconSize, ArcLaunchDefaultIconSize, 0.001);
    XCTAssertEqualWithAccuracy(store.settings.iconSpacing, ArcLaunchDefaultIconSpacing, 0.001);
    XCTAssertEqualWithAccuracy(store.settings.ringSpacing, ArcLaunchDefaultRingSpacing, 0.001);

    [store mutateSettings:^(ArcLaunchSettings *settings) {
        settings.iconSize = 58.0;
        settings.iconSpacing = 1000.0;
        settings.ringSpacing = 6.0;
    }];
    ArcLaunchSettingsStore *reloadedStore = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqualWithAccuracy(reloadedStore.settings.iconSize, 58.0, 0.001);
    XCTAssertEqualWithAccuracy(reloadedStore.settings.iconSpacing, ArcLaunchMaximumIconSpacing, 0.001);
    XCTAssertEqualWithAccuracy(reloadedStore.settings.ringSpacing, 6.0, 0.001);
}

- (void)testRingSpacingDoesNotInheritIconSpacing {
    NSDictionary *legacySettings = @{@"iconSpacing": @20};
    ArcLaunchSettings *settings = [ArcLaunchSettings settingsFromDictionary:legacySettings];
    XCTAssertEqualWithAccuracy(settings.iconSpacing, 20.0, 0.001);
    XCTAssertEqualWithAccuracy(settings.ringSpacing, ArcLaunchDefaultRingSpacing, 0.001);
}

- (void)testAppearancePersistsAndRejectsUnknownStyles {
    ArcLaunchSettingsStore *store = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqual(store.settings.handleStyle, ArcLaunchHandleStyleAutomatic);
    XCTAssertEqual(store.settings.backdropStyle, ArcLaunchBackdropStyleAutomatic);
    [store mutateSettings:^(ArcLaunchSettings *settings) {
        settings.handleStyle = ArcLaunchHandleStyleHidden;
        settings.backdropStyle = ArcLaunchBackdropStyleLight;
        settings.backdropBlur = 0.0;
        settings.handleTouchRadius = 500.0;
    }];
    ArcLaunchSettingsStore *reloadedStore = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqual(reloadedStore.settings.handleStyle, ArcLaunchHandleStyleHidden);
    XCTAssertEqual(reloadedStore.settings.backdropStyle, ArcLaunchBackdropStyleLight);
    XCTAssertEqualWithAccuracy(reloadedStore.settings.backdropBlur, ArcLaunchMinimumBackdropBlur, 0.001);
    XCTAssertEqualWithAccuracy(reloadedStore.settings.handleTouchRadius, ArcLaunchMaximumHandleTouchRadius, 0.001);

    ArcLaunchSettings *invalid = [ArcLaunchSettings settingsFromDictionary:@{@"handleStyle": @9, @"backdropStyle": @-3}];
    XCTAssertEqual(invalid.handleStyle, ArcLaunchHandleStyleAutomatic);
    XCTAssertEqual(invalid.backdropStyle, ArcLaunchBackdropStyleAutomatic);
}

- (void)testFloatingWindowDwellDurationClampsAndRoundsToTenths {
    XCTAssertEqualWithAccuracy([ArcLaunchSettings settingsFromDictionary:@{}].floatingWindowDwellDuration, ArcLaunchDefaultFloatingWindowDwellDuration, 0.001);
    XCTAssertEqualWithAccuracy([ArcLaunchSettings settingsFromDictionary:@{@"floatingWindowDwellDuration": @0.26}].floatingWindowDwellDuration, 0.3, 0.001);
    XCTAssertEqualWithAccuracy([ArcLaunchSettings settingsFromDictionary:@{@"floatingWindowDwellDuration": @0.01}].floatingWindowDwellDuration, 0.1, 0.001);
    // 旧版本允许最长 5 秒，读取后收紧到新的上限。
    XCTAssertEqualWithAccuracy([ArcLaunchSettings settingsFromDictionary:@{@"floatingWindowDwellDuration": @5}].floatingWindowDwellDuration, 3.0, 0.001);
}

- (void)testKeyboardDisplayModePersistsAndDefaultsToInWindow {
    ArcLaunchSettingsStore *store = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqual(store.settings.keyboardDisplayMode, ArcLaunchKeyboardDisplayModeInWindow);
    [store mutateSettings:^(ArcLaunchSettings *settings) {
        settings.keyboardDisplayMode = ArcLaunchKeyboardDisplayModeFullScreen;
    }];
    ArcLaunchSettingsStore *reloadedStore = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqual(reloadedStore.settings.keyboardDisplayMode, ArcLaunchKeyboardDisplayModeFullScreen);

    XCTAssertEqual([ArcLaunchSettings settingsFromDictionary:@{}].keyboardDisplayMode, ArcLaunchKeyboardDisplayModeInWindow);
    XCTAssertEqual([ArcLaunchSettings settingsFromDictionary:@{@"keyboardDisplayMode": @7}].keyboardDisplayMode, ArcLaunchKeyboardDisplayModeInWindow);
}

@end
