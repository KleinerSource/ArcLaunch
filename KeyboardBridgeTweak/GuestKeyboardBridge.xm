#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <errno.h>
#import <notify.h>
#import <os/lock.h>
#import <signal.h>

@interface UIKeyboardVisualModeManager : NSObject
+ (BOOL)windowingSoftwareKeyboardAllowed;
+ (BOOL)softwareKeyboardAllowedForActiveKeyboardSceneDelegate;
- (BOOL)windowingModeEnabled;
- (BOOL)useVisualModeWindowed;
@end

// 与 FloatingAppSceneHost 约定的状态格式：低 32 位为 HUD PID；高位分别标记 UIKit 托管和全屏键盘模式。
static const uint64_t ArcLaunchKeyboardBridgeHostPIDMask = 0xFFFFFFFFull;
static const uint64_t ArcLaunchKeyboardBridgeNativeHostingFlag = 1ull << 32;
static const uint64_t ArcLaunchKeyboardBridgeFullScreenKeyboardFlag = 1ull << 33;

static os_unfair_lock ArcLaunchKeyboardBridgeStateLock = OS_UNFAIR_LOCK_INIT;
static uint64_t ArcLaunchKeyboardBridgeState;
static int ArcLaunchKeyboardBridgeStateToken = NOTIFY_TOKEN_INVALID;
static NSString *ArcLaunchKeyboardBridgeNotificationName;

// hook 中直接读取最新状态，不依赖主队列投递通知：guest 启动期间主线程忙于初始化，
// UIKit 可能在通知回调执行前就查询并确定键盘策略。notify_check 走共享内存，状态变化时才向 notifyd 取值。
static uint64_t ArcLaunchKeyboardBridgeReadState(void) {
    static BOOL loggedFailure;
    os_unfair_lock_lock(&ArcLaunchKeyboardBridgeStateLock);
    int changed = 0;
    uint32_t status = notify_check(ArcLaunchKeyboardBridgeStateToken, &changed);
    uint64_t previousState = ArcLaunchKeyboardBridgeState;
    if (status == NOTIFY_STATUS_OK && changed) {
        uint64_t state = 0;
        status = notify_get_state(ArcLaunchKeyboardBridgeStateToken, &state);
        ArcLaunchKeyboardBridgeState = status == NOTIFY_STATUS_OK ? state : 0;
    }
    uint64_t state = ArcLaunchKeyboardBridgeState;
    BOOL logFailure = status != NOTIFY_STATUS_OK && !loggedFailure;
    loggedFailure = loggedFailure || logFailure;
    os_unfair_lock_unlock(&ArcLaunchKeyboardBridgeStateLock);

    if (logFailure) {
        NSLog(@"[ArcLaunchKeyboardBridge] Could not read keyboard host state (%u)", status);
    }
    if (state != previousState) {
        NSLog(@"[ArcLaunchKeyboardBridge] Keyboard host for %@ changed (HUD PID %llu, native=%d, fullscreen=%d)", NSBundle.mainBundle.bundleIdentifier, (unsigned long long)(state & ArcLaunchKeyboardBridgeHostPIDMask), (state & ArcLaunchKeyboardBridgeNativeHostingFlag) != 0, (state & ArcLaunchKeyboardBridgeFullScreenKeyboardFlag) != 0);
    }
    return state;
}

static uint64_t ArcLaunchKeyboardBridgeActiveState(void) {
    uint64_t state = ArcLaunchKeyboardBridgeReadState();
    pid_t hostPID = (pid_t)(state & ArcLaunchKeyboardBridgeHostPIDMask);
    if (hostPID <= 0) {
        return 0;
    }
    return kill(hostPID, 0) == 0 || errno == EPERM ? state : 0;
}

// 当前由 ArcLaunch 悬浮托管，且宿主需要 guest 自行以窗口化方式显示键盘。
static BOOL ArcLaunchKeyboardBridgeIsActive(void) {
    uint64_t state = ArcLaunchKeyboardBridgeActiveState();
    return state != 0 && (state & ArcLaunchKeyboardBridgeNativeHostingFlag) == 0;
}

// 键盘视觉模式变化时同步通知 HUD；旧版 FrontBoard presenter 仍需要窗口扩展补足系统键盘的大小。
static void ArcLaunchKeyboardBridgeObserveKeyboard(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    void (^post)(BOOL) = ^(BOOL visible) {
        if (ArcLaunchKeyboardBridgeActiveState() == 0) {
            return;
        }
        NSString *name = [ArcLaunchKeyboardBridgeNotificationName stringByAppendingString:visible ? @".keyboard.shown" : @".keyboard.hidden"];
        notify_post(name.UTF8String);
    };
    [center addObserverForName:UIKeyboardWillShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        post(YES);
    }];
    [center addObserverForName:UIKeyboardWillHideNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        post(NO);
    }];
    [center addObserverForName:UIKeyboardWillChangeFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        // 窗口化/浮动键盘常报告空的结束帧，这不代表键盘收起；真正收起时仍会有 WillHide。
        CGRect endFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        if (CGRectIsEmpty(endFrame)) {
            return;
        }
        post(CGRectIntersectsRect(UIScreen.mainScreen.bounds, endFrame));
    }];
}

%group ArcLaunchGuestKeyboard

// 应用先全屏运行、再被悬浮附加时，进程里还留着 SpringBoard 的原场景，key window 仍在那里，
// 键盘会跟随原场景而不在悬浮窗里弹出。输入控件成为第一响应者前先让它所在的窗口成为 key window。
%hook UIResponder

- (BOOL)becomeFirstResponder {
    if ([self isKindOfClass:UIView.class] && [self conformsToProtocol:@protocol(UIKeyInput)] && ArcLaunchKeyboardBridgeActiveState() != 0) {
        UIWindow *window = ((UIView *)self).window;
        UISceneActivationState activationState = window.windowScene.activationState;
        BOOL foreground = activationState == UISceneActivationStateForegroundActive || activationState == UISceneActivationStateForegroundInactive;
        if (window && !window.isKeyWindow && foreground) {
            NSLog(@"[ArcLaunchKeyboardBridge] Making %@ key for text input in scene %@", window, window.windowScene.session.persistentIdentifier);
            [window makeKeyWindow];
        }
    }
    return %orig;
}

%end

%hook UIKeyboardVisualModeManager

- (BOOL)windowingModeEnabled {
    uint64_t state = ArcLaunchKeyboardBridgeActiveState();
    if ((state & ArcLaunchKeyboardBridgeFullScreenKeyboardFlag) && (state & ArcLaunchKeyboardBridgeNativeHostingFlag)) {
        return NO;
    }
    return (state != 0 && (state & ArcLaunchKeyboardBridgeNativeHostingFlag) == 0) ? YES : %orig;
}

- (BOOL)useVisualModeWindowed {
    uint64_t state = ArcLaunchKeyboardBridgeActiveState();
    if ((state & ArcLaunchKeyboardBridgeFullScreenKeyboardFlag) && (state & ArcLaunchKeyboardBridgeNativeHostingFlag)) {
        return NO;
    }
    return (state != 0 && (state & ArcLaunchKeyboardBridgeNativeHostingFlag) == 0) ? YES : %orig;
}

+ (BOOL)windowingSoftwareKeyboardAllowed {
    return ArcLaunchKeyboardBridgeIsActive() ? YES : %orig;
}

+ (BOOL)softwareKeyboardAllowedForActiveKeyboardSceneDelegate {
    return ArcLaunchKeyboardBridgeIsActive() ? YES : %orig;
}

%end

%end

%ctor {
    @autoreleasepool {
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
        if (bundleIdentifier.length == 0 || [bundleIdentifier isEqualToString:@"com.kleinersource.arclaunch"]) {
            return;
        }

        NSString *notificationName = [NSString stringWithFormat:@"com.kleinersource.arclaunch.keyboardbridge.%@", bundleIdentifier];
        ArcLaunchKeyboardBridgeNotificationName = notificationName;
        // 注册一直保持，HUD 注销自己的注册后 notifyd 仍为该名称保留状态。
        int token = NOTIFY_TOKEN_INVALID;
        uint32_t status = notify_register_check(notificationName.UTF8String, &token);
        if (status != NOTIFY_STATUS_OK) {
            NSLog(@"[ArcLaunchKeyboardBridge] Could not monitor %@ (%u)", notificationName, status);
            return;
        }
        ArcLaunchKeyboardBridgeStateToken = token;

        // HUD 在启动 guest 前就已发布状态，这里同步读到，赶在 UIKit 初始化键盘之前。
        ArcLaunchKeyboardBridgeReadState();
        ArcLaunchKeyboardBridgeObserveKeyboard();
        %init(ArcLaunchGuestKeyboard);
    }
}
