#import "ArcLaunchSettings.h"
#import <math.h>

const NSUInteger ArcLaunchMaximumShortcuts = 48;
const CGFloat ArcLaunchMinimumIconSize = 32.0;
const CGFloat ArcLaunchMaximumIconSize = 64.0;
const CGFloat ArcLaunchDefaultIconSize = 50.0;
const CGFloat ArcLaunchMinimumIconSpacing = 0.0;
const CGFloat ArcLaunchMaximumIconSpacing = 32.0;
const CGFloat ArcLaunchDefaultIconSpacing = 12.0;
const CGFloat ArcLaunchMinimumRingSpacing = 0.0;
const CGFloat ArcLaunchMaximumRingSpacing = 32.0;
const CGFloat ArcLaunchDefaultRingSpacing = 12.0;
const CGFloat ArcLaunchMinimumBackdropBlur = 0.1;
const CGFloat ArcLaunchDefaultBackdropBlur = 1.0;
const CGFloat ArcLaunchMinimumHandleTouchRadius = 4.0;
const CGFloat ArcLaunchMaximumHandleTouchRadius = 60.0;
const CGFloat ArcLaunchDefaultHandleTouchRadius = 38.0;
const CGFloat ArcLaunchMaximumFixedTriggerInset = 120.0;
const CGFloat ArcLaunchMinimumFixedTriggerInset = -30.0;
static NSInteger const ArcLaunchSettingsSchemaVersion = 1;

@implementation ArcLaunchShortcut

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName {
    self = [super init];
    if (self) {
        _identifier = [NSUUID UUID];
        _bundleIdentifier = [bundleIdentifier copy];
        _displayName = [displayName copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    ArcLaunchShortcut *copy = [[[self class] allocWithZone:zone] initWithBundleIdentifier:self.bundleIdentifier displayName:self.displayName];
    [copy setValue:self.identifier forKey:@"_identifier"];
    return copy;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    return @{
        @"id": self.identifier.UUIDString,
        @"bundleIdentifier": self.bundleIdentifier ?: @"",
        @"displayName": self.displayName ?: @"",
    };
}

+ (instancetype)shortcutFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    NSString *bundleIdentifier = [dictionary[@"bundleIdentifier"] isKindOfClass:NSString.class] ? dictionary[@"bundleIdentifier"] : nil;
    NSString *displayName = [dictionary[@"displayName"] isKindOfClass:NSString.class] ? dictionary[@"displayName"] : bundleIdentifier;
    if (bundleIdentifier.length == 0 || displayName.length == 0) {
        return nil;
    }

    ArcLaunchShortcut *shortcut = [[self alloc] initWithBundleIdentifier:bundleIdentifier displayName:displayName];
    NSString *identifier = [dictionary[@"id"] isKindOfClass:NSString.class] ? dictionary[@"id"] : nil;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:identifier];
    if (uuid) {
        [shortcut setValue:uuid forKey:@"_identifier"];
    }
    return shortcut;
}

@end

@implementation ArcLaunchSettings

+ (instancetype)defaultSettings {
    ArcLaunchSettings *settings = [self new];
    settings.enabled = YES;
    settings.menuTriggerMode = ArcLaunchMenuTriggerModeHandle;
    settings.fixedTriggerCorners = ArcLaunchFixedTriggerCornerBottomRight;
    settings.landscapeTriggerEnabled = YES;
    settings.fixedTriggerHorizontalInset = 0.0;
    settings.fixedTriggerVerticalInset = 0.0;
    settings.edge = ArcLaunchEdgeRight;
    settings.normalizedVerticalPosition = 0.5;
    settings.shortcuts = [NSMutableArray array];
    return settings;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _iconSize = ArcLaunchDefaultIconSize;
        _iconSpacing = ArcLaunchDefaultIconSpacing;
        _ringSpacing = ArcLaunchDefaultRingSpacing;
        _handleStyle = ArcLaunchHandleStyleAutomatic;
        _handleTouchRadius = ArcLaunchDefaultHandleTouchRadius;
        _backdropStyle = ArcLaunchBackdropStyleAutomatic;
        _backdropBlur = ArcLaunchDefaultBackdropBlur;
        _shortcuts = [NSMutableArray array];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    ArcLaunchSettings *copy = [[[self class] allocWithZone:zone] init];
    copy.enabled = self.enabled;
    copy.menuTriggerMode = self.menuTriggerMode;
    copy.fixedTriggerCorners = self.fixedTriggerCorners;
    copy.landscapeTriggerEnabled = self.landscapeTriggerEnabled;
    copy.fixedTriggerHorizontalInset = self.fixedTriggerHorizontalInset;
    copy.fixedTriggerVerticalInset = self.fixedTriggerVerticalInset;
    copy.edge = self.edge;
    copy.normalizedVerticalPosition = self.normalizedVerticalPosition;
    copy.iconSize = self.iconSize;
    copy.iconSpacing = self.iconSpacing;
    copy.ringSpacing = self.ringSpacing;
    copy.handleStyle = self.handleStyle;
    copy.handleTouchRadius = self.handleTouchRadius;
    copy.backdropStyle = self.backdropStyle;
    copy.backdropBlur = self.backdropBlur;
    for (ArcLaunchShortcut *shortcut in self.shortcuts) {
        [copy.shortcuts addObject:[shortcut copy]];
    }
    return copy;
}

- (void)normalize {
    if (self.menuTriggerMode != ArcLaunchMenuTriggerModeHandle && self.menuTriggerMode != ArcLaunchMenuTriggerModeFixedCorners) {
        self.menuTriggerMode = ArcLaunchMenuTriggerModeHandle;
    }
    self.fixedTriggerCorners &= ArcLaunchFixedTriggerCornerAll;
    if (self.fixedTriggerCorners == 0) {
        self.fixedTriggerCorners = ArcLaunchFixedTriggerCornerBottomRight;
    }
    self.fixedTriggerHorizontalInset = isfinite(self.fixedTriggerHorizontalInset) ? MIN(MAX(self.fixedTriggerHorizontalInset, ArcLaunchMinimumFixedTriggerInset), ArcLaunchMaximumFixedTriggerInset) : 0.0;
    self.fixedTriggerVerticalInset = isfinite(self.fixedTriggerVerticalInset) ? MIN(MAX(self.fixedTriggerVerticalInset, ArcLaunchMinimumFixedTriggerInset), ArcLaunchMaximumFixedTriggerInset) : 0.0;
    self.normalizedVerticalPosition = MIN(MAX(self.normalizedVerticalPosition, 0.0), 1.0);
    self.edge = self.edge == ArcLaunchEdgeLeft ? ArcLaunchEdgeLeft : ArcLaunchEdgeRight;
    self.iconSize = isfinite(self.iconSize) ? MIN(MAX(self.iconSize, ArcLaunchMinimumIconSize), ArcLaunchMaximumIconSize) : ArcLaunchDefaultIconSize;
    self.iconSpacing = isfinite(self.iconSpacing) ? MIN(MAX(self.iconSpacing, ArcLaunchMinimumIconSpacing), ArcLaunchMaximumIconSpacing) : ArcLaunchDefaultIconSpacing;
    self.ringSpacing = isfinite(self.ringSpacing) ? MIN(MAX(self.ringSpacing, ArcLaunchMinimumRingSpacing), ArcLaunchMaximumRingSpacing) : ArcLaunchDefaultRingSpacing;
    self.backdropBlur = isfinite(self.backdropBlur) ? MIN(MAX(self.backdropBlur, ArcLaunchMinimumBackdropBlur), 1.0) : ArcLaunchDefaultBackdropBlur;
    self.handleTouchRadius = isfinite(self.handleTouchRadius) ? MIN(MAX(self.handleTouchRadius, ArcLaunchMinimumHandleTouchRadius), ArcLaunchMaximumHandleTouchRadius) : ArcLaunchDefaultHandleTouchRadius;
    if (self.handleStyle < ArcLaunchHandleStyleLight || self.handleStyle > ArcLaunchHandleStyleAutomatic) {
        self.handleStyle = ArcLaunchHandleStyleAutomatic;
    }
    if (self.backdropStyle < ArcLaunchBackdropStyleLight || self.backdropStyle > ArcLaunchBackdropStyleAutomatic) {
        self.backdropStyle = ArcLaunchBackdropStyleAutomatic;
    }

    NSMutableArray<ArcLaunchShortcut *> *validShortcuts = [NSMutableArray array];
    NSMutableSet<NSString *> *bundleIdentifiers = [NSMutableSet set];
    for (ArcLaunchShortcut *shortcut in self.shortcuts) {
        NSString *identifier = shortcut.bundleIdentifier.lowercaseString;
        if (identifier.length == 0 || [bundleIdentifiers containsObject:identifier]) {
            continue;
        }
        [bundleIdentifiers addObject:identifier];
        [validShortcuts addObject:shortcut];
        if (validShortcuts.count == ArcLaunchMaximumShortcuts) {
            break;
        }
    }
    self.shortcuts = validShortcuts;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    [self normalize];
    NSMutableArray<NSDictionary<NSString *, id> *> *shortcuts = [NSMutableArray arrayWithCapacity:self.shortcuts.count];
    for (ArcLaunchShortcut *shortcut in self.shortcuts) {
        [shortcuts addObject:shortcut.dictionaryRepresentation];
    }
    return @{
        @"schemaVersion": @(ArcLaunchSettingsSchemaVersion),
        @"enabled": @(self.enabled),
        @"menuTriggerMode": @(self.menuTriggerMode),
        @"fixedTriggerCorners": @(self.fixedTriggerCorners),
        @"landscapeTriggerEnabled": @(self.landscapeTriggerEnabled),
        @"fixedTriggerHorizontalInset": @(self.fixedTriggerHorizontalInset),
        @"fixedTriggerVerticalInset": @(self.fixedTriggerVerticalInset),
        @"edge": @(self.edge),
        @"normalizedVerticalPosition": @(self.normalizedVerticalPosition),
        @"iconSize": @(self.iconSize),
        @"iconSpacing": @(self.iconSpacing),
        @"ringSpacing": @(self.ringSpacing),
        @"handleStyle": @(self.handleStyle),
        @"handleTouchRadius": @(self.handleTouchRadius),
        @"backdropStyle": @(self.backdropStyle),
        @"backdropBlur": @(self.backdropBlur),
        @"shortcuts": shortcuts,
    };
}

+ (instancetype)settingsFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        return [self defaultSettings];
    }

    ArcLaunchSettings *settings = [self defaultSettings];
    NSNumber *(^number)(NSString *) = ^NSNumber *(NSString *key) {
        return [dictionary[key] isKindOfClass:NSNumber.class] ? dictionary[key] : nil;
    };
    NSNumber *enabled = number(@"enabled");
    NSNumber *menuTriggerMode = number(@"menuTriggerMode");
    NSNumber *fixedTriggerCorners = number(@"fixedTriggerCorners");
    NSNumber *landscapeTriggerEnabled = number(@"landscapeTriggerEnabled");
    NSNumber *fixedTriggerHorizontalInset = number(@"fixedTriggerHorizontalInset");
    NSNumber *fixedTriggerVerticalInset = number(@"fixedTriggerVerticalInset");
    NSNumber *edge = number(@"edge");
    NSNumber *verticalPosition = number(@"normalizedVerticalPosition");
    NSNumber *iconSize = number(@"iconSize");
    NSNumber *iconSpacing = number(@"iconSpacing");
    // 圈间距是独立的布局配置；旧设置中没有这一项时使用它自己的默认值。
    NSNumber *ringSpacing = number(@"ringSpacing");
    NSNumber *handleStyle = number(@"handleStyle");
    NSNumber *handleTouchRadius = number(@"handleTouchRadius");
    NSNumber *backdropStyle = number(@"backdropStyle");
    NSNumber *backdropBlur = number(@"backdropBlur");
    if (enabled) settings.enabled = enabled.boolValue;
    if (menuTriggerMode) settings.menuTriggerMode = menuTriggerMode.integerValue;
    if (fixedTriggerCorners) settings.fixedTriggerCorners = fixedTriggerCorners.unsignedIntegerValue;
    if (landscapeTriggerEnabled) settings.landscapeTriggerEnabled = landscapeTriggerEnabled.boolValue;
    if (fixedTriggerHorizontalInset) settings.fixedTriggerHorizontalInset = fixedTriggerHorizontalInset.doubleValue;
    if (fixedTriggerVerticalInset) settings.fixedTriggerVerticalInset = fixedTriggerVerticalInset.doubleValue;
    if (edge) settings.edge = edge.integerValue;
    if (verticalPosition) settings.normalizedVerticalPosition = verticalPosition.doubleValue;
    if (iconSize) settings.iconSize = iconSize.doubleValue;
    if (iconSpacing) settings.iconSpacing = iconSpacing.doubleValue;
    if (ringSpacing) settings.ringSpacing = ringSpacing.doubleValue;
    if (handleStyle) settings.handleStyle = handleStyle.integerValue;
    if (handleTouchRadius) settings.handleTouchRadius = handleTouchRadius.doubleValue;
    if (backdropStyle) settings.backdropStyle = backdropStyle.integerValue;
    if (backdropBlur) settings.backdropBlur = backdropBlur.doubleValue;

    NSArray *shortcutDictionaries = [dictionary[@"shortcuts"] isKindOfClass:NSArray.class] ? dictionary[@"shortcuts"] : @[];
    for (id item in shortcutDictionaries) {
        if (![item isKindOfClass:NSDictionary.class]) {
            continue;
        }
        ArcLaunchShortcut *shortcut = [ArcLaunchShortcut shortcutFromDictionary:item];
        if (shortcut) {
            [settings.shortcuts addObject:shortcut];
        }
    }
    [settings normalize];
    return settings;
}

@end
