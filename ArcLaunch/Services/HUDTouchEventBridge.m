#import "HUDTouchEventBridge.h"
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/utsname.h>
#import "PassthroughHUDWindow.h"

typedef struct __IOHIDEvent *ArcLaunchIOHIDEventRef;
typedef struct __IOHIDService *ArcLaunchIOHIDServiceRef;
// 与小端平台上 MacTypes 的 AbsoluteTime（UnsignedWide）布局一致：低 32 位在前。
typedef struct {
    uint32_t lo;
    uint32_t hi;
} ArcLaunchAbsoluteTime;

typedef ArcLaunchIOHIDEventRef (*ArcLaunchCreateDigitizerEventFunction)(CFAllocatorRef, ArcLaunchAbsoluteTime, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef ArcLaunchIOHIDEventRef (*ArcLaunchCreateFingerEventFunction)(CFAllocatorRef, ArcLaunchAbsoluteTime, uint32_t, uint32_t, uint32_t, double, double, double, double, double, double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef void (*ArcLaunchAppendHIDEventFunction)(ArcLaunchIOHIDEventRef, ArcLaunchIOHIDEventRef);
typedef void (*ArcLaunchSetHIDIntegerFunction)(ArcLaunchIOHIDEventRef, uint32_t, int);
typedef void (*ArcLaunchHIDEventCallback)(void *, void *, ArcLaunchIOHIDServiceRef, ArcLaunchIOHIDEventRef);
typedef void *(*ArcLaunchRegisterHIDEventCallbackFunction)(ArcLaunchHIDEventCallback);

@interface UIApplication (ArcLaunchHUDTouchPrivate)
- (UIEvent *)_touchesEvent;
- (void)_enqueueHIDEvent:(ArcLaunchIOHIDEventRef)event;
@end

@interface UIEvent (ArcLaunchHUDTouchPrivate)
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_clearTouches;
@end

@interface UITouch (ArcLaunchHUDPrivateAPIs)
- (void)setWindow:(UIWindow *)window;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)setView:(UIView *)view;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)_setIsTapToClick:(BOOL)value;
- (void)setGestureView:(UIView *)view;
- (void)_setHidEvent:(ArcLaunchIOHIDEventRef)event;
@end

@interface UITouch (ArcLaunchTouchEventBridge)
- (instancetype)initArcLaunchAtPoint:(CGPoint)point inWindow:(UIWindow *)window onView:(UIView *)view;
- (void)setLocationInWindow:(CGPoint)location;
- (void)setPhaseAndUpdateTimestamp:(UITouchPhase)phase;
@end

@implementation UITouch (ArcLaunchTouchEventBridge)

- (instancetype)initArcLaunchAtPoint:(CGPoint)point inWindow:(UIWindow *)window onView:(UIView *)view {
    self = [super init];
    if (!self) {
        return nil;
    }

    [self setWindow:window];
    [self _setLocationInWindow:point resetPrevious:YES];
    [self setView:view];
    [self setPhase:UITouchPhaseBegan];
    [self _setIsTapToClick:NO];
    [self setTimestamp:NSProcessInfo.processInfo.systemUptime];
    SEL gestureViewSelector = NSSelectorFromString(@"setGestureView:");
    if ([self respondsToSelector:gestureViewSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, gestureViewSelector, view);
    }
    return self;
}

- (void)setLocationInWindow:(CGPoint)location {
    [self setTimestamp:NSProcessInfo.processInfo.systemUptime];
    [self _setLocationInWindow:location resetPrevious:NO];
}

- (void)setPhaseAndUpdateTimestamp:(UITouchPhase)phase {
    [self setTimestamp:NSProcessInfo.processInfo.systemUptime];
    [self setPhase:phase];
}

@end

static NSMutableDictionary<NSNumber *, UITouch *> *ArcLaunchActiveTouches;
static NSMutableArray<UITouch *> *ArcLaunchLivingTouches;
static NSMutableArray<UITouch *> *ArcLaunchTouchesToRemove;
static NSMutableArray<UITouch *> *ArcLaunchTouchesToStationarify;
static NSArray<UITouch *> *ArcLaunchSafeTouches;
static CFRunLoopSourceRef ArcLaunchTouchEventSource;
static void *ArcLaunchIOKitHandle;
static ArcLaunchCreateDigitizerEventFunction ArcLaunchCreateDigitizerEvent;
static ArcLaunchCreateFingerEventFunction ArcLaunchCreateFingerEvent;
static ArcLaunchAppendHIDEventFunction ArcLaunchAppendHIDEvent;
static ArcLaunchSetHIDIntegerFunction ArcLaunchSetHIDInteger;

static void ArcLaunchLoadHIDEventFunctions(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ArcLaunchIOKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        ArcLaunchCreateDigitizerEvent = (ArcLaunchCreateDigitizerEventFunction)dlsym(ArcLaunchIOKitHandle ?: RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
        ArcLaunchCreateFingerEvent = (ArcLaunchCreateFingerEventFunction)dlsym(ArcLaunchIOKitHandle ?: RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEventWithQuality");
        ArcLaunchAppendHIDEvent = (ArcLaunchAppendHIDEventFunction)dlsym(ArcLaunchIOKitHandle ?: RTLD_DEFAULT, "IOHIDEventAppendEvent");
        ArcLaunchSetHIDInteger = (ArcLaunchSetHIDIntegerFunction)dlsym(ArcLaunchIOKitHandle ?: RTLD_DEFAULT, "IOHIDEventSetIntegerValue");
    });
}

static ArcLaunchIOHIDEventRef ArcLaunchCreateHIDEventForTouch(UITouch *touch) {
    ArcLaunchLoadHIDEventFunctions();
    if (!ArcLaunchCreateDigitizerEvent || !ArcLaunchCreateFingerEvent || !ArcLaunchAppendHIDEvent || !ArcLaunchSetHIDInteger) {
        return NULL;
    }

    uint64_t absoluteTime = mach_absolute_time();
    ArcLaunchAbsoluteTime timestamp;
    timestamp.hi = (uint32_t)(absoluteTime >> 32);
    timestamp.lo = (uint32_t)absoluteTime;
    ArcLaunchIOHIDEventRef handEvent = ArcLaunchCreateDigitizerEvent(kCFAllocatorDefault, timestamp, 3, 0, 0, 1 << 1, 0, 0, 0, 0, 0, 0, false, true, 0);
    if (!handEvent) {
        return NULL;
    }

    const uint32_t digitizerIsDisplayIntegratedField = (11 << 16) + 25;
    ArcLaunchSetHIDInteger(handEvent, digitizerIsDisplayIntegratedField, 1);
    CGPoint location = [touch locationInView:touch.window];
    ArcLaunchIOHIDEventRef fingerEvent = ArcLaunchCreateFingerEvent(kCFAllocatorDefault, timestamp, 1, 2, (1 << 0) | (1 << 1), location.x, location.y, 0, 0, 0, 5, 5, 1, 1, 1, true, true, 0);
    if (!fingerEvent) {
        CFRelease(handEvent);
        return NULL;
    }
    ArcLaunchSetHIDInteger(fingerEvent, digitizerIsDisplayIntegratedField, 1);
    ArcLaunchAppendHIDEvent(handEvent, fingerEvent);
    CFRelease(fingerEvent);
    return handEvent;
}

static void ArcLaunchTouchEventSourceCallback(void *context) {
    UIApplication *application = UIApplication.sharedApplication;
    UIEvent *event = [application _touchesEvent];
    if (!event) {
        return;
    }

    // 已结束的触摸与刚开始的触摸在下一次 HID 事件到达时再处理，确保 UIKit 至少完整看到一次每个阶段。
    [event _clearTouches];
    NSArray<UITouch *> *touches = ArcLaunchSafeTouches;
    for (UITouch *touch in touches) {
        switch (touch.phase) {
            case UITouchPhaseEnded:
            case UITouchPhaseCancelled:
                [ArcLaunchTouchesToRemove addObject:touch];
                break;
            case UITouchPhaseBegan:
                [ArcLaunchTouchesToStationarify addObject:touch];
                break;
            default:
                break;
        }
        [event _addTouch:touch forDelayedDelivery:NO];
    }
    [application sendEvent:event];
}

static void ArcLaunchReceiveTouch(NSInteger identifier, CGPoint location, UITouchPhase phase, UIWindow *window, UIView *view) {
    BOOL touchesChanged = NO;
    for (UITouch *touch in ArcLaunchTouchesToRemove) {
        [ArcLaunchLivingTouches removeObjectIdenticalTo:touch];
        for (NSNumber *touchKey in ArcLaunchActiveTouches.allKeys) {
            if (ArcLaunchActiveTouches[touchKey] == touch) {
                [ArcLaunchActiveTouches removeObjectForKey:touchKey];
            }
        }
        touchesChanged = YES;
    }
    [ArcLaunchTouchesToRemove removeAllObjects];
    for (UITouch *touch in ArcLaunchTouchesToStationarify) {
        if (touch.phase == UITouchPhaseBegan) {
            [touch setPhaseAndUpdateTimestamp:UITouchPhaseStationary];
        }
    }
    [ArcLaunchTouchesToStationarify removeAllObjects];

    NSNumber *touchKey = @(identifier);
    UITouch *touch = ArcLaunchActiveTouches[touchKey];
    BOOL living = touch && [ArcLaunchLivingTouches indexOfObjectIdenticalTo:touch] != NSNotFound;
    if (!living) {
        // 只在按下时建立新触摸；从 HUD 外滑入的手指不应在悬浮条上凭空产生点击。
        if (phase != UITouchPhaseBegan || !view) {
            return;
        }
        touch = [[UITouch alloc] initArcLaunchAtPoint:location inWindow:window onView:view];
        if (!touch) {
            return;
        }
        ArcLaunchIOHIDEventRef hidEvent = ArcLaunchCreateHIDEventForTouch(touch);
        if (hidEvent) {
            [touch _setHidEvent:hidEvent];
            CFRelease(hidEvent);
        }
        [ArcLaunchLivingTouches addObject:touch];
        ArcLaunchActiveTouches[touchKey] = touch;
        touchesChanged = YES;
    } else {
        // Began 尚未派发时丢弃移动事件，否则 UIKit 永远收不到 Began，手势识别会失效。
        if (touch.phase == UITouchPhaseBegan && phase == UITouchPhaseMoved) {
            return;
        }
        [touch setLocationInWindow:location];
    }
    [touch setPhaseAndUpdateTimestamp:phase];

    if (touchesChanged) {
        ArcLaunchSafeTouches = [ArcLaunchLivingTouches copy];
    }
    if (ArcLaunchTouchEventSource) {
        CFRunLoopSourceSignal(ArcLaunchTouchEventSource);
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

static void ArcLaunchHandleHIDEvent(void *target, void *refcon, ArcLaunchIOHIDServiceRef service, ArcLaunchIOHIDEventRef event) {
    @autoreleasepool {
        UIApplication *application = UIApplication.sharedApplication;
        if (!event) {
            return;
        }

        NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
        if (version.majorVersion < 15 || (version.majorVersion == 15 && version.minorVersion == 0)) {
            SEL enqueueSelector = NSSelectorFromString(@"_enqueueHIDEvent:");
            if ([application respondsToSelector:enqueueSelector]) {
                ((void (*)(id, SEL, ArcLaunchIOHIDEventRef))objc_msgSend)(application, enqueueSelector, event);
            }
        }

        BOOL useAXRepresentation = version.majorVersion >= 15;
        if (version.majorVersion == 15 && version.minorVersion == 0 && version.patchVersion == 0) {
            struct utsname systemInfo;
            uname(&systemInfo);
            NSString *deviceModel = [NSString stringWithUTF8String:systemInfo.machine];
            useAXRepresentation = [deviceModel hasPrefix:@"iPhone13,"] || [deviceModel hasPrefix:@"iPhone14,"];
        }
        if (!useAXRepresentation) {
            return;
        }

        static Class representationClass;
        static dispatch_once_t representationToken;
        dispatch_once(&representationToken, ^{
            [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework"] load];
            representationClass = objc_getClass("AXEventRepresentation");
        });
        SEL representationSelector = NSSelectorFromString(@"representationWithHIDEvent:hidStreamIdentifier:");
        if (!representationClass || ![representationClass respondsToSelector:representationSelector]) {
            return;
        }
        id representation = ((id (*)(id, SEL, ArcLaunchIOHIDEventRef, id))objc_msgSend)(representationClass, representationSelector, event, @"UIApplicationEvents");
        if (!representation) {
            return;
        }

        SEL locationSelector = NSSelectorFromString(@"location");
        SEL handInfoSelector = NSSelectorFromString(@"handInfo");
        CGPoint location = ((CGPoint (*)(id, SEL))objc_msgSend)(representation, locationSelector);
        id handInfo = ((id (*)(id, SEL))objc_msgSend)(representation, handInfoSelector);
        NSArray *paths = ((id (*)(id, SEL))objc_msgSend)(handInfo, NSSelectorFromString(@"paths"));
        id path = paths.firstObject;
        NSInteger identifier = ((unsigned char (*)(id, SEL))objc_msgSend)(path, NSSelectorFromString(@"pathIdentity"));
        if (identifier <= 0) {
            return;
        }

        UITouchPhase phase = UITouchPhaseEnded;
        if (((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isTouchDown"))) {
            phase = UITouchPhaseBegan;
        } else if (((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isMove"))) {
            phase = UITouchPhaseMoved;
        } else if (((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isCancel"))) {
            phase = UITouchPhaseCancelled;
        } else if (((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isLift")) ||
                   ((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isInRange")) ||
                   ((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isInRangeLift"))) {
            phase = UITouchPhaseEnded;
        } else {
            return;
        }

        identifier = MIN(MAX(identifier, 1), 98);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *window = nil;
            for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
                if ([candidate isKindOfClass:PassthroughHUDWindow.class] && !candidate.hidden) {
                    window = candidate;
                    break;
                }
            }
            if (!window) {
                return;
            }
            UIView *view = [window hitTest:location withEvent:nil];
            ArcLaunchReceiveTouch(identifier, location, phase, window, view);
        });
    }
}

BOOL ArcLaunchRegisterHUDEventCallback(void) {
    if (![NSThread isMainThread]) {
        return NO;
    }

    static BOOL registered;
    if (registered) {
        return YES;
    }

    ArcLaunchActiveTouches = [NSMutableDictionary dictionary];
    ArcLaunchLivingTouches = [NSMutableArray array];
    ArcLaunchTouchesToRemove = [NSMutableArray array];
    ArcLaunchTouchesToStationarify = [NSMutableArray array];
    ArcLaunchSafeTouches = @[];
    CFRunLoopSourceContext context = {0};
    context.perform = ArcLaunchTouchEventSourceCallback;
    ArcLaunchTouchEventSource = CFRunLoopSourceCreate(kCFAllocatorDefault, -2, &context);
    if (!ArcLaunchTouchEventSource) {
        return NO;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), ArcLaunchTouchEventSource, kCFRunLoopCommonModes);

    void *backBoardServices = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY | RTLD_GLOBAL);
    ArcLaunchRegisterHIDEventCallbackFunction registerCallback = (ArcLaunchRegisterHIDEventCallbackFunction)dlsym(backBoardServices, "BKSHIDEventRegisterEventCallback");
    if (!registerCallback) {
        return NO;
    }
    registerCallback(ArcLaunchHandleHIDEvent);

    void *graphicsServices = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY | RTLD_GLOBAL);
    typedef void (*ArcLaunchGSEventInitializeFunction)(Boolean);
    typedef void (*ArcLaunchGSEventPushRunLoopModeFunction)(CFStringRef);
    ArcLaunchGSEventInitializeFunction initializeEvents = (ArcLaunchGSEventInitializeFunction)dlsym(graphicsServices, "GSEventInitialize");
    ArcLaunchGSEventPushRunLoopModeFunction pushRunLoopMode = (ArcLaunchGSEventPushRunLoopModeFunction)dlsym(graphicsServices, "GSEventPushRunLoopMode");
    if (initializeEvents) {
        initializeEvents(false);
    }
    if (pushRunLoopMode) {
        pushRunLoopMode(kCFRunLoopDefaultMode);
    }

    registered = YES;
    return YES;
}
