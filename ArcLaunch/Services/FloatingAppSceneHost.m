#import "FloatingAppSceneHost.h"
#import "ArcLaunchFrontBoardPrivate.h"
#import <errno.h>
#import <notify.h>
#import <signal.h>

static NSString * const ArcLaunchFloatingScenePrefix = @"ArcLaunch.floating";
// FrontBoard 的后台启动意图：进程启动后不会被 SpringBoard 拉到前台，只显示我们创建的场景。
static const long long ArcLaunchFloatingLaunchIntentBackground = 4;
static const NSTimeInterval ArcLaunchFloatingTerminationGracePeriod = 3.0;
static const NSUInteger ArcLaunchFloatingPresentationAppearanceStyle = 2;
// 与键盘桥接插件约定的状态格式：低 32 位为 HUD PID；高位分别标记 UIKit 托管和全屏键盘模式。
static const uint64_t ArcLaunchKeyboardBridgeNativeHostingFlag = 1ull << 32;
static const uint64_t ArcLaunchKeyboardBridgeFullScreenKeyboardFlag = 1ull << 33;

// HUD 可能以 mobile 身份运行，向其它用户的进程探测会得到 EPERM，这同样说明进程存在。
static BOOL ArcLaunchProcessIsAlive(pid_t processIdentifier) {
    return kill(processIdentifier, 0) == 0 || errno == EPERM;
}

@interface FloatingAppSceneHost ()
@property (nonatomic, copy, readwrite) NSString *bundleIdentifier;
@property (nonatomic, weak) UIViewController *parentViewController;
@property (nonatomic, strong, readwrite, nullable) UIView *presentationView;
@property (nonatomic, strong, nullable) _UIScenePresenter *presenter;
@property (nonatomic, strong, nullable) _UISceneHostingController *hostingController;
@property (nonatomic, strong, nullable) UIViewController *hostingViewController;
@property (nonatomic, strong, nullable) FBApplicationProcessLaunchTransaction *launchTransaction;
@property (nonatomic, copy, nullable) NSString *sceneIdentifier;
@property (nonatomic, strong, nullable) dispatch_source_t processExitSource;
@property (nonatomic) pid_t processIdentifier;
@property (nonatomic) BOOL launchedByHost;
@property (nonatomic) BOOL processExited;
@property (nonatomic) BOOL invalidated;
@property (nonatomic) BOOL keyboardBridgeActive;
@property (nonatomic) int keyboardShownToken;
@property (nonatomic) int keyboardHiddenToken;
- (BOOL)createHostedSceneForProcessHandle:(RBSProcessHandle *)handle failureReason:(NSString **)failureReason API_AVAILABLE(ios(17.4));
- (void)applyInitialSettingsToHostedScene:(FBScene *)scene;
- (void)configureEventDeferringForHostingController:(_UISceneHostingController *)hostingController viewController:(UIViewController *)viewController;
- (void)setKeyboardBridgeActive:(BOOL)active;
- (void)publishKeyboardBridgeStateForActive:(BOOL)active;
- (void)observeGuestKeyboard;
- (void)stopObservingGuestKeyboard;
- (void)handleGuestKeyboardVisible:(BOOL)visible;
@end

@implementation FloatingAppSceneHost

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier parentViewController:(UIViewController *)parentViewController {
    self = [super init];
    if (self) {
        _bundleIdentifier = [bundleIdentifier copy];
        _parentViewController = parentViewController;
        _userInterfaceStyle = UIUserInterfaceStyleLight;
        _keyboardShownToken = NOTIFY_TOKEN_INVALID;
        _keyboardHiddenToken = NOTIFY_TOKEN_INVALID;
    }
    return self;
}

- (void)dealloc {
    if (_processExitSource) {
        dispatch_source_cancel(_processExitSource);
    }
    if (_keyboardShownToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(_keyboardShownToken);
    }
    if (_keyboardHiddenToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(_keyboardHiddenToken);
    }
}

#pragma mark - 启动

- (void)startWithCompletion:(ArcLaunchFloatingSceneCompletion)completion {
    RBSProcessHandle *handle = [self runningProcessHandle];
    if (handle) {
        self.launchedByHost = NO;
        [self finishStartWithProcessHandle:handle completion:completion];
        return;
    }

    RBSProcessIdentity *identity = [self processIdentity];
    Class transactionClass = ArcLaunchPrivateClass(FBApplicationProcessLaunchTransaction);
    FBProcessManager *processManager = [ArcLaunchPrivateClass(FBProcessManager) sharedInstance];
    if (!identity || !transactionClass || !processManager) {
        completion(NO, @"系统缺少 FrontBoard 启动接口");
        return;
    }

    FBApplicationProcessLaunchTransaction *transaction = nil;
    @try {
        transaction = [[transactionClass alloc] initWithProcessIdentity:identity executionContextProvider:^id{
            FBMutableProcessExecutionContext *context = [ArcLaunchPrivateClass(FBMutableProcessExecutionContext) new];
            context.identity = identity;
            context.environment = @{};
            context.launchIntent = ArcLaunchFloatingLaunchIntentBackground;
            return [processManager launchProcessWithContext:context];
        }];
    } @catch (NSException *exception) {
        completion(NO, [NSString stringWithFormat:@"无法创建启动任务：%@", exception.reason]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [transaction setCompletionBlock:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.invalidated) {
                return;
            }
            strongSelf.launchTransaction = nil;
            RBSProcessHandle *launchedHandle = [strongSelf runningProcessHandle];
            if (!launchedHandle) {
                completion(NO, @"应用进程未能启动");
                return;
            }
            strongSelf.launchedByHost = YES;
            [strongSelf finishStartWithProcessHandle:launchedHandle completion:completion];
        });
    }];
    self.launchTransaction = transaction;
    [transaction begin];
}

- (void)finishStartWithProcessHandle:(RBSProcessHandle *)handle completion:(ArcLaunchFloatingSceneCompletion)completion {
    NSString *failureReason = nil;
    if (![self createSceneForProcessHandle:handle failureReason:&failureReason]) {
        completion(NO, failureReason);
        return;
    }
    // iOS 17.0–17.3 使用裸 FrontBoard presenter，tweak 在 guest 进程中开启 windowed keyboard；
    // UIKit 场景托管由系统处理键盘布局，同时接收全屏模式标志。
    [self observeGuestKeyboard];
    [self setKeyboardBridgeActive:YES];
    [self monitorProcessExit];
    completion(YES, nil);
}

- (void)setKeyboardBridgeActive:(BOOL)active {
    if (self.keyboardBridgeActive == active) {
        return;
    }

    [self publishKeyboardBridgeStateForActive:active];
}

- (void)setFullScreenKeyboardEnabled:(BOOL)fullScreenKeyboardEnabled {
    if (_fullScreenKeyboardEnabled == fullScreenKeyboardEnabled) {
        return;
    }
    _fullScreenKeyboardEnabled = fullScreenKeyboardEnabled;
    if (self.keyboardBridgeActive) {
        [self publishKeyboardBridgeStateForActive:YES];
    }
}

- (void)publishKeyboardBridgeStateForActive:(BOOL)active {
    NSString *notificationName = [NSString stringWithFormat:@"com.kleinersource.arclaunch.keyboardbridge.%@", self.bundleIdentifier];
    int token = NOTIFY_TOKEN_INVALID;
    if (notify_register_check(notificationName.UTF8String, &token) != NOTIFY_STATUS_OK) {
        NSLog(@"[ArcLaunchKeyboardBridge] Could not register %@", notificationName);
        return;
    }
    uint64_t state = 0;
    if (active) {
        state = (uint64_t)getpid();
        if (self.hostingController) {
            state |= ArcLaunchKeyboardBridgeNativeHostingFlag;
        }
        if (self.fullScreenKeyboardEnabled) {
            state |= ArcLaunchKeyboardBridgeFullScreenKeyboardFlag;
        }
    }
    uint32_t stateStatus = notify_set_state(token, state);
    if (stateStatus == NOTIFY_STATUS_OK) {
        _keyboardBridgeActive = active;
    }
    uint32_t postStatus = stateStatus == NOTIFY_STATUS_OK ? notify_post(notificationName.UTF8String) : stateStatus;
    notify_cancel(token);
    if (stateStatus != NOTIFY_STATUS_OK || postStatus != NOTIFY_STATUS_OK) {
        NSLog(@"[ArcLaunchKeyboardBridge] Could not publish %@ (state=%u, post=%u)", notificationName, stateStatus, postStatus);
        return;
    }

    NSLog(@"[ArcLaunchKeyboardBridge] %@ keyboard bridge for %@ (HUD PID %d, fullscreen=%d, native=%d)", active ? @"Enabled" : @"Disabled", self.bundleIdentifier, getpid(), self.fullScreenKeyboardEnabled, self.hostingController != nil);
}

- (void)observeGuestKeyboard {
    if (self.keyboardShownToken != NOTIFY_TOKEN_INVALID) {
        return;
    }
    NSString *baseName = [NSString stringWithFormat:@"com.kleinersource.arclaunch.keyboardbridge.%@", self.bundleIdentifier];
    __weak typeof(self) weakSelf = self;
    int shownToken = NOTIFY_TOKEN_INVALID;
    int hiddenToken = NOTIFY_TOKEN_INVALID;
    uint32_t shownStatus = notify_register_dispatch([baseName stringByAppendingString:@".keyboard.shown"].UTF8String, &shownToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf handleGuestKeyboardVisible:YES];
    });
    uint32_t hiddenStatus = notify_register_dispatch([baseName stringByAppendingString:@".keyboard.hidden"].UTF8String, &hiddenToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf handleGuestKeyboardVisible:NO];
    });
    self.keyboardShownToken = shownStatus == NOTIFY_STATUS_OK ? shownToken : NOTIFY_TOKEN_INVALID;
    self.keyboardHiddenToken = hiddenStatus == NOTIFY_STATUS_OK ? hiddenToken : NOTIFY_TOKEN_INVALID;
    if (shownStatus != NOTIFY_STATUS_OK || hiddenStatus != NOTIFY_STATUS_OK) {
        NSLog(@"[ArcLaunchKeyboardBridge] Could not observe keyboard of %@ (shown=%u, hidden=%u)", self.bundleIdentifier, shownStatus, hiddenStatus);
    }
}

- (void)stopObservingGuestKeyboard {
    if (self.keyboardShownToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(self.keyboardShownToken);
        self.keyboardShownToken = NOTIFY_TOKEN_INVALID;
    }
    if (self.keyboardHiddenToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(self.keyboardHiddenToken);
        self.keyboardHiddenToken = NOTIFY_TOKEN_INVALID;
    }
}

- (void)handleGuestKeyboardVisible:(BOOL)visible {
    if (!self.invalidated && self.keyboardVisibilityHandler) {
        self.keyboardVisibilityHandler(visible);
    }
}

- (BOOL)usesUIKitSceneHosting {
    return self.hostingController != nil;
}

- (nullable RBSProcessIdentity *)processIdentity {
    return [ArcLaunchPrivateClass(RBSProcessIdentity) identityForEmbeddedApplicationIdentifier:self.bundleIdentifier];
}

- (nullable RBSProcessHandle *)runningProcessHandle {
    RBSProcessIdentity *identity = [self processIdentity];
    Class predicateClass = ArcLaunchPrivateClass(RBSProcessPredicate);
    Class handleClass = ArcLaunchPrivateClass(RBSProcessHandle);
    if (!identity || !predicateClass || !handleClass) {
        return nil;
    }
    RBSProcessPredicate *predicate = [predicateClass predicateMatchingIdentity:identity];
    RBSProcessHandle *handle = [handleClass handleForPredicate:predicate error:nil];
    pid_t processIdentifier = handle ? handle.pid : 0;
    return processIdentifier > 0 && ArcLaunchProcessIsAlive(processIdentifier) ? handle : nil;
}

#pragma mark - 场景

- (BOOL)createSceneForProcessHandle:(RBSProcessHandle *)handle failureReason:(NSString **)failureReason {
    @try {
        self.processIdentifier = handle.pid;
        [[ArcLaunchPrivateClass(FBProcessManager) sharedInstance] registerProcessForAuditToken:handle.auditToken];

        if (@available(iOS 17.4, *)) {
            NSString *hostingFailureReason = nil;
            if ([self createHostedSceneForProcessHandle:handle failureReason:&hostingFailureReason]) {
                return YES;
            }
            NSLog(@"ArcLaunch keyboard-aware scene hosting unavailable; falling back to FrontBoard presenter: %@", hostingFailureReason);
        }

        // 每次打开都用新的场景标识，多窗口与关闭后重开互不干扰。
        NSString *sceneIdentifier = [NSString stringWithFormat:@"%@:%@:%@", ArcLaunchFloatingScenePrefix, self.bundleIdentifier, NSUUID.UUID.UUIDString];
        FBSMutableSceneDefinition *definition = [ArcLaunchPrivateClass(FBSMutableSceneDefinition) definition];
        definition.identity = [ArcLaunchPrivateClass(FBSSceneIdentity) identityForIdentifier:sceneIdentifier];
        definition.clientIdentity = [ArcLaunchPrivateClass(FBSSceneClientIdentity) identityForProcessIdentity:handle.identity];
        definition.specification = [ArcLaunchPrivateClass(UIApplicationSceneSpecification) specification];
        FBSMutableSceneParameters *parameters = [ArcLaunchPrivateClass(FBSMutableSceneParameters) parametersForSpecification:definition.specification];
        parameters.settings = [self initialSceneSettings];

        UIMutableApplicationSceneClientSettings *clientSettings = [ArcLaunchPrivateClass(UIMutableApplicationSceneClientSettings) new];
        clientSettings.interfaceOrientation = UIInterfaceOrientationPortrait;
        clientSettings.statusBarStyle = 0;
        parameters.clientSettings = clientSettings;

        FBScene *scene = [[ArcLaunchPrivateClass(FBSceneManager) sharedInstance] createSceneWithDefinition:definition initialParameters:parameters];
        if (!scene) {
            *failureReason = @"FrontBoard 未能创建场景";
            return NO;
        }
        self.sceneIdentifier = sceneIdentifier;

        _UIScenePresenter *presenter = [scene.uiPresentationManager createPresenterWithIdentifier:sceneIdentifier];
        [presenter modifyPresentationContext:^(UIMutableScenePresentationContext *context) {
            context.appearanceStyle = ArcLaunchFloatingPresentationAppearanceStyle;
        }];
        [presenter activate];
        self.presenter = presenter;
        self.presentationView = presenter.presentationView;
        if (!self.presentationView) {
            *failureReason = @"场景没有可显示的画面";
            [self destroyScene];
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        *failureReason = [NSString stringWithFormat:@"创建场景失败：%@", exception.reason];
        [self destroyScene];
        return NO;
    }
}

- (BOOL)createHostedSceneForProcessHandle:(RBSProcessHandle *)handle failureReason:(NSString **)failureReason {
    Class configurationClass = ArcLaunchPrivateClass(_UISceneHostingControllerAdvancedConfiguration);
    Class hostingControllerClass = ArcLaunchPrivateClass(_UISceneHostingController);
    if (!configurationClass || !hostingControllerClass || !self.parentViewController) {
        if (failureReason) {
            *failureReason = @"UIKit 场景托管接口或父控制器不可用";
        }
        return NO;
    }

    _UISceneHostingController *hostingController = nil;
    UIViewController *hostedViewController = nil;
    BOOL addedToParent = NO;
    @try {
        _UISceneHostingControllerAdvancedConfiguration *configuration = [[configurationClass alloc] initWithProcessIdentity:handle.identity];
        configuration.sceneSpecification = [ArcLaunchPrivateClass(UIApplicationSceneSpecification) specification];
        if (@available(iOS 18.0, *)) {
            Class eventDeferringExtensionClass = NSClassFromString(@"_UISceneHostingEventDeferringExtension");
            SEL setExtensionsSelector = NSSelectorFromString(@"setAdditionalExtensions:");
            if (eventDeferringExtensionClass && [configuration respondsToSelector:setExtensionsSelector]) {
                configuration.additionalExtensions = [NSOrderedSet orderedSetWithObject:[eventDeferringExtensionClass new]];
            }
        }

        hostingController = [[hostingControllerClass alloc] initWithAdvancedConfiguration:configuration];
        hostedViewController = [hostingController sceneViewController];
        if (!hostingController || !hostedViewController) {
            @throw [NSException exceptionWithName:@"ArcLaunchSceneHostingFailure" reason:@"UIKit 未创建托管场景控制器" userInfo:nil];
        }

        [self.parentViewController addChildViewController:hostedViewController];
        addedToParent = YES;
        UIView *hostedView = hostedViewController.view;
        _UIScenePresenter *presenter = [hostedView valueForKey:@"_scenePresenter"];
        if (!hostedView || !presenter) {
            @throw [NSException exceptionWithName:@"ArcLaunchSceneHostingFailure" reason:@"UIKit 托管场景未提供场景 presenter" userInfo:nil];
        }

        [presenter modifyPresentationContext:^(UIMutableScenePresentationContext *context) {
            context.appearanceStyle = ArcLaunchFloatingPresentationAppearanceStyle;
        }];
        [self applyInitialSettingsToHostedScene:presenter.scene];
        [self configureEventDeferringForHostingController:hostingController viewController:hostedViewController];

        self.hostingController = hostingController;
        self.hostingViewController = hostedViewController;
        self.presenter = presenter;
        self.presentationView = hostedView;
        return YES;
    } @catch (NSException *exception) {
        if (failureReason) {
            *failureReason = exception.reason ?: @"创建 UIKit 托管场景失败";
        }
        @try {
            [hostingController invalidate];
        } @catch (NSException *cleanupException) {
            NSLog(@"ArcLaunch hosted scene cleanup failed: %@", cleanupException);
        }
        if (addedToParent) {
            [hostedViewController willMoveToParentViewController:nil];
            [hostedViewController.view removeFromSuperview];
            [hostedViewController removeFromParentViewController];
        }
        return NO;
    }
}

- (void)applyInitialSettingsToHostedScene:(FBScene *)scene {
    UIMutableApplicationSceneSettings *initialSettings = [self initialSceneSettings];
    [scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
        settings.canShowAlerts = initialSettings.canShowAlerts;
        settings.displayConfiguration = initialSettings.displayConfiguration;
        settings.foreground = initialSettings.foreground;
        settings.frame = initialSettings.frame;
        settings.interfaceOrientation = initialSettings.interfaceOrientation;
        if ([initialSettings respondsToSelector:@selector(deviceOrientation)] && [settings respondsToSelector:@selector(setDeviceOrientation:)]) {
            settings.deviceOrientation = initialSettings.deviceOrientation;
        }
        settings.level = initialSettings.level;
        settings.persistenceIdentifier = initialSettings.persistenceIdentifier;
        settings.peripheryInsets = initialSettings.peripheryInsets;
        settings.safeAreaInsetsPortrait = initialSettings.safeAreaInsetsPortrait;
        settings.statusBarDisabled = initialSettings.statusBarDisabled;
        settings.userInterfaceStyle = initialSettings.userInterfaceStyle;
    }];
}

- (void)configureEventDeferringForHostingController:(_UISceneHostingController *)hostingController viewController:(UIViewController *)viewController {
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    if (version.majorVersion < 27 || ![hostingController respondsToSelector:NSSelectorFromString(@"_eventDeferringComponent")]) {
        return;
    }
    @try {
        id component = [hostingController valueForKey:@"_eventDeferringComponent"];
        [component setValue:viewController forKey:@"_firstResponderTrackingSelectionPath"];
        [component setValue:@2 forKey:@"grantBehavior"];
        [component setValue:@2 forKey:@"selectionRequestBehavior"];
    } @catch (NSException *exception) {
        NSLog(@"ArcLaunch event-deferring setup failed: %@", exception);
    }
}

- (void)didAttachPresentationView {
    UIViewController *viewController = self.hostingViewController;
    if (viewController.parentViewController == self.parentViewController && self.presentationView.superview) {
        [viewController didMoveToParentViewController:self.parentViewController];
    }
}

// 应用按竖屏全屏尺寸与安全区布局，窗口只做等比缩放，与全屏打开时的界面完全一致。
- (UIMutableApplicationSceneSettings *)initialSceneSettings {
    UIMutableApplicationSceneSettings *settings = [ArcLaunchPrivateClass(UIMutableApplicationSceneSettings) new];
    UIScreen *screen = UIScreen.mainScreen;
    settings.canShowAlerts = YES;
    settings.foreground = YES;
    settings.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(screen.bounds), CGRectGetHeight(screen.bounds));
    settings.interfaceOrientation = UIInterfaceOrientationPortrait;
    settings.level = 1;
    settings.persistenceIdentifier = NSUUID.UUID.UUIDString;
    settings.statusBarDisabled = YES;
    settings.safeAreaInsetsPortrait = self.sceneSafeAreaInsets;
    settings.peripheryInsets = self.sceneSafeAreaInsets;
    if ([screen respondsToSelector:@selector(displayConfiguration)]) {
        settings.displayConfiguration = screen.displayConfiguration;
    }
    if ([settings respondsToSelector:@selector(setDeviceOrientation:)]) {
        settings.deviceOrientation = UIDeviceOrientationPortrait;
    }
    if ([settings respondsToSelector:@selector(setUserInterfaceStyle:)]) {
        settings.userInterfaceStyle = self.userInterfaceStyle;
    }
    return settings;
}

- (void)updateUserInterfaceStyle:(UIUserInterfaceStyle)userInterfaceStyle {
    if (self.userInterfaceStyle == userInterfaceStyle) {
        return;
    }
    self.userInterfaceStyle = userInterfaceStyle;
    FBScene *scene = self.presenter.scene;
    if (![scene respondsToSelector:@selector(updateSettingsWithBlock:)]) {
        return;
    }
    @try {
        [scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
            if ([settings respondsToSelector:@selector(setUserInterfaceStyle:)]) {
                settings.userInterfaceStyle = userInterfaceStyle;
            }
        }];
    } @catch (NSException *exception) {
        NSLog(@"ArcLaunch floating scene appearance update failed: %@", exception);
    }
}

#pragma mark - 进程

- (void)monitorProcessExit {
    if (self.processExitSource || self.processIdentifier <= 0) {
        return;
    }
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)self.processIdentifier, DISPATCH_PROC_EXIT, dispatch_get_main_queue());
    if (!source) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        [weakSelf handleProcessExit];
    });
    dispatch_resume(source);
    self.processExitSource = source;
}

- (void)handleProcessExit {
    self.processExited = YES;
    if (self.processExitSource) {
        dispatch_source_cancel(self.processExitSource);
        self.processExitSource = nil;
    }
    if (!self.invalidated && self.processExitHandler) {
        self.processExitHandler();
    }
}

#pragma mark - 结束

- (void)invalidate {
    [self invalidateTerminatingProcess:YES];
}

- (void)detachForFullScreenLaunch {
    [self invalidateTerminatingProcess:NO];
}

- (void)invalidateTerminatingProcess:(BOOL)terminateProcess {
    if (self.invalidated) {
        return;
    }
    self.invalidated = YES;
    self.launchTransaction = nil;
    [self destroyScene];

    pid_t processIdentifier = self.processIdentifier;
    // 附加到已在运行的应用时不结束它，只收回我们创建的场景。
    if (!terminateProcess || !self.launchedByHost || self.processExited || processIdentifier <= 0) {
        return;
    }
    kill(processIdentifier, SIGTERM);
    // 保留退出监听以判断进程是否已结束，避免宽限期后误杀复用了同一 PID 的其它进程。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ArcLaunchFloatingTerminationGracePeriod * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.processExited && ArcLaunchProcessIsAlive(processIdentifier)) {
            kill(processIdentifier, SIGKILL);
        }
    });
}

- (void)destroyScene {
    [self stopObservingGuestKeyboard];
    [self setKeyboardBridgeActive:NO];
    if (self.hostingController) {
        _UISceneHostingController *hostingController = self.hostingController;
        UIViewController *viewController = self.hostingViewController;
        self.hostingController = nil;
        self.hostingViewController = nil;
        self.presenter = nil;
        [self.presentationView removeFromSuperview];
        self.presentationView = nil;
        @try {
            [hostingController invalidate];
        } @catch (NSException *exception) {
            NSLog(@"ArcLaunch hosted scene invalidation failed: %@", exception);
        }
        if (viewController.parentViewController) {
            [viewController willMoveToParentViewController:nil];
            [viewController removeFromParentViewController];
        }
        return;
    }

    _UIScenePresenter *presenter = self.presenter;
    self.presenter = nil;
    [self.presentationView removeFromSuperview];
    self.presentationView = nil;
    @try {
        [presenter deactivate];
        [presenter invalidate];
        if (self.sceneIdentifier) {
            [[ArcLaunchPrivateClass(FBSceneManager) sharedInstance] destroyScene:self.sceneIdentifier withTransitionContext:nil];
        }
    } @catch (NSException *exception) {
        NSLog(@"ArcLaunch floating scene teardown failed: %@", exception);
    }
    self.sceneIdentifier = nil;
}

@end
