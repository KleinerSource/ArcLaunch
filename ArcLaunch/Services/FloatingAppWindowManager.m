#import "FloatingAppWindowManager.h"
#import "FloatingAppSceneHost.h"
#import "FloatingAppWindowView.h"
#import "ArcLaunchFloatingWindowLayout.h"
#import "ArcLaunchLayerHitTesting.h"
#import "ArcLaunchSettings.h"
#import "SystemApplicationBridge.h"

static const CGFloat ArcLaunchFloatingDockPlateCornerRadius = 14.0;
static const CGFloat ArcLaunchFloatingDockHandleTouchWidth = 28.0;
static const CGFloat ArcLaunchFloatingDockHandleHeight = 50.0;
static const CGFloat ArcLaunchFloatingDockHandleVisibleWidth = 14.0;
static const CGFloat ArcLaunchFloatingDockHandleVisibleHeight = 46.0;
// 应用退出后先显示提示，停留片刻再关闭窗口。
static const NSTimeInterval ArcLaunchFloatingExitNoticeDuration = 1.2;

@interface ArcLaunchFloatingWindowEntry : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, strong) FloatingAppWindowView *windowView;
@property (nonatomic, strong, nullable) FloatingAppSceneHost *host;
/// 收起前的窗口位置，恢复时回到这里。
@property (nonatomic) CGRect restoredFrame;
/// 为显示全屏键盘临时铺满屏幕前的窗口位置，键盘收起后回到这里。
@property (nonatomic) CGRect frameBeforeKeyboard;
@end

@implementation ArcLaunchFloatingWindowEntry
@end

@interface FloatingAppWindowManager () <FloatingAppWindowViewDelegate>
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, weak) UIViewController *parentViewController;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong) NSMutableArray<ArcLaunchFloatingWindowEntry *> *entries;
/// 收纳区中的窗口，按收起的先后顺序从上往下排列。
@property (nonatomic, strong) NSMutableArray<ArcLaunchFloatingWindowEntry *> *minimizedEntries;
@property (nonatomic, strong) UIView *backgroundTapView;
@property (nonatomic, strong) UIVisualEffectView *dockPlateView;
@property (nonatomic, strong) UIView *dockHandleView;
@property (nonatomic, strong) UIView *dockHandlePillView;
@property (nonatomic, strong) UIImageView *dockHandleIconView;
@property (nonatomic) ArcLaunchEdge dockEdge;
@property (nonatomic) BOOL windowsHidden;
@property (nonatomic) BOOL dockCollapsed;
@property (nonatomic) CGFloat dockHandleCenterY;
- (void)minimizeExpandedEntriesExcept:(nullable ArcLaunchFloatingWindowEntry *)focusedEntry;
- (void)backgroundTapped;
- (void)collapseDock;
- (void)expandDock;
- (void)layoutDockHandle;
- (void)updateDockHandleAppearance;
@end

@implementation FloatingAppWindowManager

- (instancetype)initWithContainerView:(UIView *)containerView parentViewController:(UIViewController *)parentViewController applicationBridge:(SystemApplicationBridge *)applicationBridge {
    self = [super init];
    if (self) {
        _containerView = containerView;
        _parentViewController = parentViewController;
        _applicationBridge = applicationBridge;
        _entries = [NSMutableArray array];
        _minimizedEntries = [NSMutableArray array];
        _dockEdge = ArcLaunchEdgeRight;
        _userInterfaceStyle = UIUserInterfaceStyleLight;
        _handleStyle = ArcLaunchHandleStyleAutomatic;

        _backgroundTapView = [[UIView alloc] initWithFrame:containerView.bounds];
        _backgroundTapView.backgroundColor = UIColor.clearColor;
        _backgroundTapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        ArcLaunchSetLayerHitTestsAsOpaque(_backgroundTapView.layer, YES);
        UITapGestureRecognizer *backgroundTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped)];
        backgroundTapRecognizer.cancelsTouchesInView = YES;
        [_backgroundTapView addGestureRecognizer:backgroundTapRecognizer];
        [containerView addSubview:_backgroundTapView];

        // 收纳区底板只包住缩略图，不占满整条屏幕边缘；缩略图之间的缝隙也不能漏触摸到下层应用。
        _dockPlateView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        _dockPlateView.layer.cornerRadius = ArcLaunchFloatingDockPlateCornerRadius;
        _dockPlateView.layer.cornerCurve = kCACornerCurveContinuous;
        _dockPlateView.clipsToBounds = YES;
        _dockPlateView.hidden = YES;
        _dockPlateView.alpha = 0.0;
        ArcLaunchSetLayerHitTestsAsOpaque(_dockPlateView.layer, YES);
        [containerView addSubview:_dockPlateView];

        _dockHandleView = [UIView new];
        _dockHandleView.backgroundColor = UIColor.clearColor;
        _dockHandleView.isAccessibilityElement = YES;
        _dockHandleView.accessibilityLabel = @"显示悬浮应用边栏";
        _dockHandleView.accessibilityTraits = UIAccessibilityTraitButton;
        _dockHandleView.hidden = YES;
        ArcLaunchSetLayerHitTestsAsOpaque(_dockHandleView.layer, YES);
        _dockHandlePillView = [UIView new];
        _dockHandlePillView.userInteractionEnabled = NO;
        _dockHandlePillView.layer.cornerRadius = ArcLaunchFloatingDockHandleVisibleWidth / 2.0;
        _dockHandlePillView.layer.cornerCurve = kCACornerCurveContinuous;
        _dockHandlePillView.layer.borderWidth = 0.5;
        _dockHandlePillView.layer.shadowColor = UIColor.blackColor.CGColor;
        _dockHandlePillView.layer.shadowOpacity = 0.3;
        _dockHandlePillView.layer.shadowRadius = 3.0;
        _dockHandlePillView.layer.shadowOffset = CGSizeZero;
        [_dockHandleView addSubview:_dockHandlePillView];
        _dockHandleIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]];
        _dockHandleIconView.contentMode = UIViewContentModeScaleAspectFit;
        _dockHandleIconView.userInteractionEnabled = NO;
        [_dockHandlePillView addSubview:_dockHandleIconView];
        UITapGestureRecognizer *showDockRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(expandDock)];
        showDockRecognizer.cancelsTouchesInView = NO;
        [_dockHandleView addGestureRecognizer:showDockRecognizer];
        [containerView addSubview:_dockHandleView];
        [self updateDockHandleAppearance];
    }
    return self;
}

- (void)dealloc {
    for (ArcLaunchFloatingWindowEntry *entry in _entries) {
        [entry.host invalidate];
    }
}

#pragma mark - 几何

- (CGSize)screenSize {
    return UIScreen.mainScreen.bounds.size;
}

- (CGRect)bounds {
    return self.containerView.bounds;
}

- (UIEdgeInsets)safeAreaInsets {
    return self.containerView.safeAreaInsets;
}

- (CGRect)clampedFrame:(CGRect)frame {
    return [ArcLaunchFloatingWindowLayout clampedFrame:frame inBounds:[self bounds] safeAreaInsets:[self safeAreaInsets]];
}

#pragma mark - 查询

- (NSArray<UIView *> *)interactiveViews {
    if (self.windowsHidden) {
        return @[];
    }
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithCapacity:self.entries.count + 1];
    BOOL hasExpandedEntry = NO;
    for (ArcLaunchFloatingWindowEntry *entry in self.entries) {
        BOOL minimized = [self isEntryMinimized:entry];
        if (self.dockCollapsed && minimized) {
            continue;
        }
        [views addObject:entry.windowView];
        hasExpandedEntry = hasExpandedEntry || !minimized;
    }
    if (hasExpandedEntry) {
        [views addObject:self.backgroundTapView];
    }
    if (self.minimizedEntries.count > 0) {
        [views addObject:self.dockCollapsed ? self.dockHandleView : self.dockPlateView];
    }
    return views;
}

- (nullable ArcLaunchFloatingWindowEntry *)entryForWindowView:(FloatingAppWindowView *)windowView {
    for (ArcLaunchFloatingWindowEntry *entry in self.entries) {
        if (entry.windowView == windowView) {
            return entry;
        }
    }
    return nil;
}

- (nullable ArcLaunchFloatingWindowEntry *)entryForBundleIdentifier:(NSString *)bundleIdentifier {
    for (ArcLaunchFloatingWindowEntry *entry in self.entries) {
        if ([entry.bundleIdentifier caseInsensitiveCompare:bundleIdentifier] == NSOrderedSame) {
            return entry;
        }
    }
    return nil;
}

- (BOOL)isEntryMinimized:(ArcLaunchFloatingWindowEntry *)entry {
    return [self.minimizedEntries indexOfObjectIdenticalTo:entry] != NSNotFound;
}

- (void)notifyInteractiveViewsDidChange {
    if (self.interactiveViewsDidChangeHandler) {
        self.interactiveViewsDidChangeHandler();
    }
}

- (void)showFeedback:(NSString *)message {
    if (self.feedbackHandler) {
        self.feedbackHandler(message);
    }
}

#pragma mark - 打开

- (void)openShortcut:(ArcLaunchShortcut *)shortcut icon:(UIImage *)icon fromPoint:(CGPoint)point {
    ArcLaunchFloatingWindowEntry *existingEntry = [self entryForBundleIdentifier:shortcut.bundleIdentifier];
    if (existingEntry) {
        if ([self isEntryMinimized:existingEntry]) {
            [self restoreEntry:existingEntry];
        } else {
            [self bringEntryToFront:existingEntry];
        }
        return;
    }
    if (self.entries.count >= ArcLaunchMaximumFloatingWindows) {
        [self showFeedback:[NSString stringWithFormat:@"最多同时悬浮 %lu 个应用", (unsigned long)ArcLaunchMaximumFloatingWindows]];
        return;
    }
    [self minimizeExpandedEntriesExcept:nil];

    CGSize screenSize = [self screenSize];
    FloatingAppWindowView *windowView = [[FloatingAppWindowView alloc] initWithDisplayName:shortcut.displayName icon:icon screenSize:screenSize];
    windowView.delegate = self;
    windowView.overrideUserInterfaceStyle = self.userInterfaceStyle;
    NSUInteger expandedCount = self.entries.count - self.minimizedEntries.count;
    windowView.frame = [ArcLaunchFloatingWindowLayout defaultFrameForIndex:expandedCount scale:ArcLaunchFloatingWindowDefaultScale screenSize:screenSize bounds:[self bounds] safeAreaInsets:[self safeAreaInsets]];
    [self.containerView insertSubview:windowView belowSubview:self.dockPlateView];

    ArcLaunchFloatingWindowEntry *entry = [ArcLaunchFloatingWindowEntry new];
    entry.bundleIdentifier = shortcut.bundleIdentifier;
    entry.windowView = windowView;
    entry.restoredFrame = windowView.frame;
    [self.entries addObject:entry];
    [self notifyInteractiveViewsDidChange];

    // 从悬浮条的位置放大弹出。
    CGPoint center = windowView.center;
    CGAffineTransform startTransform = CGAffineTransformMakeTranslation(point.x - center.x, point.y - center.y);
    windowView.transform = CGAffineTransformScale(startTransform, 0.1, 0.1);
    windowView.alpha = 0.0;
    [UIView animateWithDuration:0.42 delay:0.0 usingSpringWithDamping:0.82 initialSpringVelocity:0.0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        windowView.transform = CGAffineTransformIdentity;
        windowView.alpha = 1.0;
    } completion:nil];

    [self startHostForEntry:entry];
}

- (void)startHostForEntry:(ArcLaunchFloatingWindowEntry *)entry {
    FloatingAppSceneHost *host = [[FloatingAppSceneHost alloc] initWithBundleIdentifier:entry.bundleIdentifier parentViewController:self.parentViewController];
    host.sceneSafeAreaInsets = [self safeAreaInsets];
    host.userInterfaceStyle = self.userInterfaceStyle;
    __weak typeof(self) weakSelf = self;
    __weak ArcLaunchFloatingWindowEntry *weakEntry = entry;
    host.processExitHandler = ^{
        [weakSelf handleProcessExitForEntry:weakEntry];
    };
    host.keyboardVisibilityHandler = ^(BOOL visible) {
        [weakSelf handleKeyboardVisible:visible forEntry:weakEntry];
    };
    entry.host = host;
    [host startWithCompletion:^(BOOL success, NSString * _Nullable failureReason) {
        ArcLaunchFloatingWindowEntry *strongEntry = weakEntry;
        if (!strongEntry || [weakSelf.entries indexOfObjectIdenticalTo:strongEntry] == NSNotFound) {
            return;
        }
        if (success) {
            [strongEntry.windowView setPresentationView:host.presentationView];
            [host didAttachPresentationView];
            return;
        }
        NSString *message = [NSString stringWithFormat:@"无法打开：%@", failureReason ?: @"未知原因"];
        [strongEntry.windowView showStatusMessage:message];
        [weakSelf showFeedback:message];
    }];
}

- (void)handleProcessExitForEntry:(ArcLaunchFloatingWindowEntry *)entry {
    if (!entry || [self.entries indexOfObjectIdenticalTo:entry] == NSNotFound) {
        return;
    }
    [entry.windowView setPresentationView:nil];
    [entry.host invalidate];
    entry.host = nil;
    [entry.windowView showStatusMessage:@"应用已退出"];
    __weak typeof(self) weakSelf = self;
    __weak ArcLaunchFloatingWindowEntry *weakEntry = entry;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ArcLaunchFloatingExitNoticeDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ArcLaunchFloatingWindowEntry *strongEntry = weakEntry;
        if (strongEntry) {
            [weakSelf closeEntry:strongEntry animated:YES];
        }
    });
}

#pragma mark - 关闭

- (void)closeEntry:(ArcLaunchFloatingWindowEntry *)entry animated:(BOOL)animated {
    if ([self.entries indexOfObjectIdenticalTo:entry] == NSNotFound) {
        return;
    }
    [entry.host invalidate];
    entry.host = nil;
    BOOL wasMinimized = [self isEntryMinimized:entry];
    [self.entries removeObjectIdenticalTo:entry];
    [self.minimizedEntries removeObjectIdenticalTo:entry];

    FloatingAppWindowView *windowView = entry.windowView;
    windowView.delegate = nil;
    windowView.userInteractionEnabled = NO;
    // 关闭动画期间窗口可能仍按不透明拦截触摸，先从命中区域中移除。
    [self notifyInteractiveViewsDidChange];
    void (^changes)(void) = ^{
        windowView.alpha = 0.0;
        windowView.transform = CGAffineTransformScale(windowView.transform, 0.9, 0.9);
        if (wasMinimized) {
            [self layoutDock];
        }
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        [windowView removeFromSuperview];
        [self updateDockPlateVisibility];
    };
    if (animated) {
        [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

- (void)closeAllWindows {
    for (ArcLaunchFloatingWindowEntry *entry in [self.entries copy]) {
        [self closeEntry:entry animated:NO];
    }
}

- (void)openEntryFullScreen:(ArcLaunchFloatingWindowEntry *)entry {
    NSString *bundleIdentifier = entry.bundleIdentifier;
    // 只收回悬浮场景、保留进程，SpringBoard 会为同一进程创建全屏场景，应用状态得以保留。
    [entry.host detachForFullScreenLaunch];
    entry.host = nil;
    [self closeEntry:entry animated:YES];
    if (![self.applicationBridge launchBundleIdentifier:bundleIdentifier]) {
        [self showFeedback:@"应用不可用或无法启动"];
    }
}

#pragma mark - 收纳区

- (void)minimizeEntry:(ArcLaunchFloatingWindowEntry *)entry toEdge:(ArcLaunchEdge)edge {
    if ([self isEntryMinimized:entry]) {
        return;
    }
    // 第一个收起的窗口决定收纳区在哪一侧，之后的窗口都排进同一列。
    if (self.minimizedEntries.count == 0) {
        self.dockEdge = edge;
    }
    // 键盘全屏期间被收起时，恢复后应回到铺满屏幕之前的小窗位置。
    CGRect frame = entry.windowView.keyboardFullScreen ? entry.frameBeforeKeyboard : entry.windowView.frame;
    entry.windowView.keyboardFullScreen = NO;
    entry.restoredFrame = [self clampedFrame:frame];
    [self.minimizedEntries addObject:entry];
    entry.windowView.minimizedEdge = self.dockEdge;
    [self.containerView bringSubviewToFront:entry.windowView];
    if (self.dockCollapsed) {
        [self.containerView bringSubviewToFront:self.dockHandleView];
    }
    [self updateDockPlateVisibility];
    [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.85 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        entry.windowView.minimized = YES;
        [self layoutDock];
        [entry.windowView layoutIfNeeded];
    } completion:nil];
    [self notifyInteractiveViewsDidChange];
}

- (void)minimizeExpandedEntriesExcept:(nullable ArcLaunchFloatingWindowEntry *)focusedEntry {
    ArcLaunchEdge edge = self.dockEdge;
    BOOL hasDockEdge = self.minimizedEntries.count > 0;
    for (ArcLaunchFloatingWindowEntry *entry in [self.entries copy]) {
        if (entry == focusedEntry || [self isEntryMinimized:entry]) {
            continue;
        }
        if (!hasDockEdge) {
            edge = entry.windowView.center.x < CGRectGetMidX([self bounds]) ? ArcLaunchEdgeLeft : ArcLaunchEdgeRight;
            hasDockEdge = YES;
        }
        [self minimizeEntry:entry toEdge:edge];
    }
}

- (void)backgroundTapped {
    [self minimizeExpandedEntriesExcept:nil];
}

- (void)restoreEntry:(ArcLaunchFloatingWindowEntry *)entry {
    if (![self isEntryMinimized:entry]) {
        return;
    }
    [self minimizeExpandedEntriesExcept:entry];
    [self.minimizedEntries removeObjectIdenticalTo:entry];
    if (self.minimizedEntries.count == 0) {
        self.dockCollapsed = NO;
        self.dockHandleView.hidden = YES;
    }
    [self.containerView insertSubview:entry.windowView belowSubview:self.dockPlateView];
    CGRect frame = [self clampedFrame:entry.restoredFrame];
    [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.85 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        entry.windowView.minimized = NO;
        entry.windowView.frame = frame;
        [entry.windowView layoutIfNeeded];
        [self layoutDock];
    } completion:^(BOOL finished) {
        [self updateDockPlateVisibility];
    }];
    [self notifyInteractiveViewsDidChange];
}

// 在动画块中调用：把收纳区中的缩略图依次排好，底板随之伸缩。
- (void)layoutDock {
    CGSize screenSize = [self screenSize];
    CGRect bounds = [self bounds];
    UIEdgeInsets safeAreaInsets = [self safeAreaInsets];
    [self.minimizedEntries enumerateObjectsUsingBlock:^(ArcLaunchFloatingWindowEntry * _Nonnull entry, NSUInteger index, BOOL * _Nonnull stop) {
        CGRect frame = [ArcLaunchFloatingWindowLayout dockSlotFrameAtIndex:index edge:self.dockEdge screenSize:screenSize bounds:bounds safeAreaInsets:safeAreaInsets];
        if (self.dockCollapsed) {
            frame.origin.x = self.dockEdge == ArcLaunchEdgeLeft ? CGRectGetMinX(bounds) - CGRectGetWidth(frame) : CGRectGetMaxX(bounds);
        }
        entry.windowView.frame = frame;
    }];
    NSUInteger count = self.minimizedEntries.count;
    if (count > 0) {
        CGRect frame = [ArcLaunchFloatingWindowLayout dockPlateFrameForCount:count edge:self.dockEdge screenSize:screenSize bounds:bounds safeAreaInsets:safeAreaInsets];
        if (self.dockCollapsed) {
            frame.origin.x = self.dockEdge == ArcLaunchEdgeLeft ? CGRectGetMinX(bounds) - CGRectGetWidth(frame) : CGRectGetMaxX(bounds);
        }
        self.dockPlateView.frame = frame;
    }
    self.dockPlateView.alpha = count > 0 && !self.dockCollapsed ? 1.0 : 0.0;
}

- (void)layoutDockHandle {
    CGRect bounds = [self bounds];
    CGRect safeBounds = UIEdgeInsetsInsetRect(bounds, [self safeAreaInsets]);
    CGFloat minY = CGRectGetMinY(safeBounds);
    CGFloat maxY = MAX(minY, CGRectGetMaxY(safeBounds) - ArcLaunchFloatingDockHandleHeight);
    CGFloat y = self.dockHandleCenterY - ArcLaunchFloatingDockHandleHeight / 2.0;
    y = MIN(MAX(y, minY), maxY);
    CGFloat x = self.dockEdge == ArcLaunchEdgeLeft ? CGRectGetMinX(bounds) : CGRectGetMaxX(bounds) - ArcLaunchFloatingDockHandleTouchWidth;
    self.dockHandleView.frame = CGRectMake(x, y, ArcLaunchFloatingDockHandleTouchWidth, ArcLaunchFloatingDockHandleHeight);
    CGFloat pillX = self.dockEdge == ArcLaunchEdgeLeft ? 0.0 : ArcLaunchFloatingDockHandleTouchWidth - ArcLaunchFloatingDockHandleVisibleWidth;
    CGFloat pillY = (ArcLaunchFloatingDockHandleHeight - ArcLaunchFloatingDockHandleVisibleHeight) / 2.0;
    self.dockHandlePillView.frame = CGRectMake(pillX, pillY, ArcLaunchFloatingDockHandleVisibleWidth, ArcLaunchFloatingDockHandleVisibleHeight);
    self.dockHandleIconView.frame = CGRectMake(3.0, (ArcLaunchFloatingDockHandleVisibleHeight - 12.0) / 2.0, 8.0, 12.0);
    NSString *symbol = self.dockEdge == ArcLaunchEdgeLeft ? @"chevron.right" : @"chevron.left";
    self.dockHandleIconView.image = [UIImage systemImageNamed:symbol];
}

- (void)collapseDock {
    if (self.dockCollapsed || self.minimizedEntries.count == 0) {
        return;
    }
    self.dockHandleCenterY = CGRectGetMidY(self.dockPlateView.frame);
    self.dockCollapsed = YES;
    self.dockHandleView.hidden = NO;
    [self layoutDockHandle];
    [self.containerView bringSubviewToFront:self.dockHandleView];
    [self notifyInteractiveViewsDidChange];
    [UIView animateWithDuration:0.28 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        for (ArcLaunchFloatingWindowEntry *entry in self.minimizedEntries) {
            entry.windowView.transform = CGAffineTransformIdentity;
        }
        [self layoutDock];
    } completion:nil];
}

- (void)expandDock {
    if (!self.dockCollapsed || self.minimizedEntries.count == 0) {
        return;
    }
    self.dockCollapsed = NO;
    self.dockHandleView.hidden = YES;
    self.dockPlateView.hidden = NO;
    [self notifyInteractiveViewsDidChange];
    [UIView animateWithDuration:0.28 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        [self layoutDock];
    } completion:nil];
}

// 底板按不透明拦截触摸，透明度为 0 时也会挡住下层，必须真正隐藏。
- (void)updateDockPlateVisibility {
    BOOL visible = self.minimizedEntries.count > 0;
    if (!visible) {
        self.dockCollapsed = NO;
        self.dockHandleView.hidden = YES;
    }
    if (visible && self.dockPlateView.hidden) {
        CGSize screenSize = [self screenSize];
        self.dockPlateView.frame = [ArcLaunchFloatingWindowLayout dockPlateFrameForCount:1 edge:self.dockEdge screenSize:screenSize bounds:[self bounds] safeAreaInsets:[self safeAreaInsets]];
        self.dockPlateView.alpha = 0.0;
    }
    self.dockPlateView.hidden = !visible;
    self.dockHandleView.hidden = !visible || !self.dockCollapsed;
    [self notifyInteractiveViewsDidChange];
}

#pragma mark - 状态

- (void)bringEntryToFront:(ArcLaunchFloatingWindowEntry *)entry {
    if ([self isEntryMinimized:entry]) {
        return;
    }
    [self minimizeExpandedEntriesExcept:entry];
    [self.containerView insertSubview:entry.windowView belowSubview:self.dockPlateView];
}

- (void)setWindowsHidden:(BOOL)hidden {
    if (_windowsHidden == hidden) {
        return;
    }
    _windowsHidden = hidden;
    self.containerView.hidden = hidden;
    [self notifyInteractiveViewsDidChange];
}

#pragma mark - 键盘

- (void)setKeyboardDisplayMode:(ArcLaunchKeyboardDisplayMode)keyboardDisplayMode {
    if (_keyboardDisplayMode == keyboardDisplayMode) {
        return;
    }
    _keyboardDisplayMode = keyboardDisplayMode;
    if (keyboardDisplayMode == ArcLaunchKeyboardDisplayModeInWindow) {
        for (ArcLaunchFloatingWindowEntry *entry in self.entries) {
            [self exitKeyboardFullScreenForEntry:entry];
        }
    }
}

- (void)handleKeyboardVisible:(BOOL)visible forEntry:(nullable ArcLaunchFloatingWindowEntry *)entry {
    if (!entry || [self.entries indexOfObjectIdenticalTo:entry] == NSNotFound) {
        return;
    }
    if (!visible) {
        [self exitKeyboardFullScreenForEntry:entry];
        return;
    }
    if (self.keyboardDisplayMode != ArcLaunchKeyboardDisplayModeFullScreen || [self isEntryMinimized:entry] || entry.windowView.keyboardFullScreen) {
        return;
    }
    [self bringEntryToFront:entry];
    entry.frameBeforeKeyboard = entry.windowView.frame;
    // 窗口内容按窗口宽度等比缩放；去掉标题条后与屏幕等大，应用与键盘都按原尺寸显示。
    // 放到收纳区之上，避免底板盖住应用画面。
    [self.containerView bringSubviewToFront:entry.windowView];
    CGRect frame = [self bounds];
    [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        entry.windowView.keyboardFullScreen = YES;
        entry.windowView.frame = frame;
        [entry.windowView layoutIfNeeded];
    } completion:nil];
}

- (void)exitKeyboardFullScreenForEntry:(ArcLaunchFloatingWindowEntry *)entry {
    if (!entry.windowView.keyboardFullScreen || [self isEntryMinimized:entry]) {
        return;
    }
    [self.containerView insertSubview:entry.windowView belowSubview:self.dockPlateView];
    CGRect frame = [self clampedFrame:entry.frameBeforeKeyboard];
    [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        entry.windowView.keyboardFullScreen = NO;
        entry.windowView.frame = frame;
        [entry.windowView layoutIfNeeded];
    } completion:nil];
}

- (void)setUserInterfaceStyle:(UIUserInterfaceStyle)userInterfaceStyle {
    if (_userInterfaceStyle == userInterfaceStyle) {
        return;
    }
    _userInterfaceStyle = userInterfaceStyle;
    self.dockPlateView.overrideUserInterfaceStyle = userInterfaceStyle;
    self.dockHandleView.overrideUserInterfaceStyle = userInterfaceStyle;
    [self updateDockHandleAppearance];
    for (ArcLaunchFloatingWindowEntry *entry in self.entries) {
        entry.windowView.overrideUserInterfaceStyle = userInterfaceStyle;
        [entry.host updateUserInterfaceStyle:userInterfaceStyle];
    }
}

#pragma mark - FloatingAppWindowViewDelegate

- (void)floatingAppWindowViewDidRequestClose:(FloatingAppWindowView *)windowView {
    ArcLaunchFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry) {
        [self closeEntry:entry animated:YES];
    }
}

- (void)floatingAppWindowViewDidRequestMinimize:(FloatingAppWindowView *)windowView {
    ArcLaunchFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (!entry) {
        return;
    }
    ArcLaunchEdge edge = windowView.center.x < CGRectGetMidX([self bounds]) ? ArcLaunchEdgeLeft : ArcLaunchEdgeRight;
    [self minimizeEntry:entry toEdge:edge];
}

- (void)floatingAppWindowViewDidRequestFullScreen:(FloatingAppWindowView *)windowView {
    ArcLaunchFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry) {
        [self openEntryFullScreen:entry];
    }
}

- (void)floatingAppWindowViewDidRequestRestore:(FloatingAppWindowView *)windowView {
    ArcLaunchFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry) {
        [self restoreEntry:entry];
    }
}

- (void)setHandleStyle:(ArcLaunchHandleStyle)handleStyle {
    if (_handleStyle == handleStyle) {
        return;
    }
    _handleStyle = handleStyle;
    [self updateDockHandleAppearance];
}

- (void)updateDockHandleAppearance {
    // “隐藏”只隐藏主悬浮条；边栏把手仍须可见以便重新打开。
    BOOL dark = self.handleStyle == ArcLaunchHandleStyleDark ||
        ((self.handleStyle == ArcLaunchHandleStyleAutomatic || self.handleStyle == ArcLaunchHandleStyleHidden) && self.userInterfaceStyle == UIUserInterfaceStyleDark);
    if (dark) {
        self.dockHandlePillView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
        self.dockHandlePillView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        self.dockHandleIconView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    } else {
        self.dockHandlePillView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.8];
        self.dockHandlePillView.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.18].CGColor;
        self.dockHandleIconView.tintColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    }
}

- (void)floatingAppWindowViewDidRequestHideDock:(FloatingAppWindowView *)windowView {
    ArcLaunchFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry && [self isEntryMinimized:entry]) {
        [self collapseDock];
    }
}

- (void)floatingAppWindowViewDidBeginInteraction:(FloatingAppWindowView *)windowView {
    ArcLaunchFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry) {
        [self bringEntryToFront:entry];
    }
}

- (void)floatingAppWindowViewDidEndMoving:(FloatingAppWindowView *)windowView {
    ArcLaunchFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (!entry || [self isEntryMinimized:entry]) {
        return;
    }
    ArcLaunchEdge edge = ArcLaunchEdgeRight;
    if ([ArcLaunchFloatingWindowLayout shouldMinimizeFrame:windowView.frame inBounds:[self bounds] edge:&edge]) {
        [self minimizeEntry:entry toEdge:edge];
        return;
    }
    CGRect frame = [self clampedFrame:windowView.frame];
    [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.85 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        windowView.frame = frame;
        [windowView layoutIfNeeded];
    } completion:nil];
}

@end
