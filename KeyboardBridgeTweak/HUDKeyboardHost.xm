#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static BOOL ArcLaunchIsHUDProcess(void) {
    return [NSProcessInfo.processInfo.arguments containsObject:@"-hud"];
}

%group ArcLaunchHUDWindow

%hook PassthroughHUDWindow

- (BOOL)canBecomeKeyWindow {
    return NO;
}

%end

%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.kleinersource.arclaunch"] || !ArcLaunchIsHUDProcess()) {
            return;
        }
        if (NSClassFromString(@"PassthroughHUDWindow")) {
            %init(ArcLaunchHUDWindow);
            NSLog(@"[ArcLaunchKeyboardBridge] HUD key-window disabled.");
        }
    }
}
