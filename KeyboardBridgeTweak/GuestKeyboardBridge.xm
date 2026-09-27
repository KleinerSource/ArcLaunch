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

static os_unfair_lock ArcLaunchKeyboardBridgeStateLock = OS_UNFAIR_LOCK_INIT;
static uint64_t ArcLaunchKeyboardBridgeHostPID;

static void ArcLaunchKeyboardBridgeReadState(int token) {
    uint64_t hostPID = 0;
    uint32_t status = notify_get_state(token, &hostPID);
    if (status != NOTIFY_STATUS_OK) {
        NSLog(@"[ArcLaunchKeyboardBridge] Could not read keyboard host state (%u)", status);
    }
    os_unfair_lock_lock(&ArcLaunchKeyboardBridgeStateLock);
    ArcLaunchKeyboardBridgeHostPID = status == NOTIFY_STATUS_OK ? hostPID : 0;
    os_unfair_lock_unlock(&ArcLaunchKeyboardBridgeStateLock);
    if (hostPID > 0) {
        NSLog(@"[ArcLaunchKeyboardBridge] Active keyboard host for %@ (HUD PID %llu)", NSBundle.mainBundle.bundleIdentifier, (unsigned long long)hostPID);
    }
}

static BOOL ArcLaunchKeyboardBridgeIsActive(void) {
    os_unfair_lock_lock(&ArcLaunchKeyboardBridgeStateLock);
    pid_t hostPID = (pid_t)ArcLaunchKeyboardBridgeHostPID;
    os_unfair_lock_unlock(&ArcLaunchKeyboardBridgeStateLock);
    if (hostPID <= 0) {
        return NO;
    }
    return kill(hostPID, 0) == 0 || errno == EPERM;
}

%group ArcLaunchGuestKeyboard

%hook UIKeyboardVisualModeManager

- (BOOL)windowingModeEnabled {
    return ArcLaunchKeyboardBridgeIsActive() ? YES : %orig;
}

- (BOOL)useVisualModeWindowed {
    return ArcLaunchKeyboardBridgeIsActive() ? YES : %orig;
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
        int token = NOTIFY_TOKEN_INVALID;
        uint32_t status = notify_register_dispatch(notificationName.UTF8String, &token, dispatch_get_main_queue(), ^(int updatedToken) {
            ArcLaunchKeyboardBridgeReadState(updatedToken);
        });
        if (status != NOTIFY_STATUS_OK) {
            NSLog(@"[ArcLaunchKeyboardBridge] Could not monitor %@ (%u)", notificationName, status);
            return;
        }

        ArcLaunchKeyboardBridgeReadState(token);
        %init(ArcLaunchGuestKeyboard);
    }
}
