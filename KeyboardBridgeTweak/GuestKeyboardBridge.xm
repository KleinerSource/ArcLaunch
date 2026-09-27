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
static NSString *ArcLaunchKeyboardBridgeNotificationName;

static void ArcLaunchKeyboardBridgeReadState(int token) {
    uint64_t state = 0;
    uint32_t status = notify_get_state(token, &state);
    if (status != NOTIFY_STATUS_OK) {
        NSLog(@"[ArcLaunchKeyboardBridge] Could not read keyboard host state (%u)", status);
        state = 0;
    }
    os_unfair_lock_lock(&ArcLaunchKeyboardBridgeStateLock);
    ArcLaunchKeyboardBridgeState = state;
    os_unfair_lock_unlock(&ArcLaunchKeyboardBridgeStateLock);
    uint64_t hostPID = state & ArcLaunchKeyboardBridgeHostPIDMask;
    if (hostPID > 0) {
        NSLog(@"[ArcLaunchKeyboardBridge] Active keyboard host for %@ (HUD PID %llu, native=%d, fullscreen=%d)", NSBundle.mainBundle.bundleIdentifier, (unsigned long long)hostPID, (state & ArcLaunchKeyboardBridgeNativeHostingFlag) != 0, (state & ArcLaunchKeyboardBridgeFullScreenKeyboardFlag) != 0);
    }
}

static uint64_t ArcLaunchKeyboardBridgeActiveState(void) {
    os_unfair_lock_lock(&ArcLaunchKeyboardBridgeStateLock);
    uint64_t state = ArcLaunchKeyboardBridgeState;
    os_unfair_lock_unlock(&ArcLaunchKeyboardBridgeStateLock);
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
        CGRect endFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        post(!CGRectIsEmpty(endFrame) && CGRectIntersectsRect(UIScreen.mainScreen.bounds, endFrame));
    }];
}

%group ArcLaunchGuestKeyboard

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
        int token = NOTIFY_TOKEN_INVALID;
        uint32_t status = notify_register_dispatch(notificationName.UTF8String, &token, dispatch_get_main_queue(), ^(int updatedToken) {
            ArcLaunchKeyboardBridgeReadState(updatedToken);
        });
        if (status != NOTIFY_STATUS_OK) {
            NSLog(@"[ArcLaunchKeyboardBridge] Could not monitor %@ (%u)", notificationName, status);
            return;
        }

        ArcLaunchKeyboardBridgeReadState(token);
        ArcLaunchKeyboardBridgeObserveKeyboard();
        %init(ArcLaunchGuestKeyboard);
    }
}
