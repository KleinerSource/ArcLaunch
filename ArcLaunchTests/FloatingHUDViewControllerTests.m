@import XCTest;

#import "FloatingHUDViewController.h"
#import "ArcLaunchSettingsStore.h"
#import "SystemApplicationBridge.h"

@interface FloatingHUDViewController (GestureTesting)
@property (nonatomic, strong) ArcLaunchSettingsStore *settingsStore;
@property (nonatomic, strong) UIView *handleView;
@property (nonatomic, strong) UIVisualEffectView *backdropView;
@property (nonatomic, strong) NSMutableArray<UIView *> *menuItemViews;
@property (nonatomic, copy) NSArray<ArcLaunchShortcut *> *menuShortcuts;
@property (nonatomic, strong) UIView *hoveredItemView;
@property (nonatomic, strong) UIPanGestureRecognizer *activeMenuPanRecognizer;
@property (nonatomic, strong) NSTimer *floatingModeTimer;
@property (nonatomic) BOOL menuVisible;
@property (nonatomic) BOOL previewingMenu;
@property (nonatomic) BOOL floatingOpenReady;
@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL dragMoved;
- (void)handlePan:(UIPanGestureRecognizer *)recognizer;
- (void)globalTouchSequenceDidEnd;
- (BOOL)showMenu;
@end

@interface ArcLaunchTestPanRecognizer : UIPanGestureRecognizer
@property (nonatomic) UIGestureRecognizerState testState;
@property (nonatomic) NSUInteger cancellationCount;
@end

@implementation ArcLaunchTestPanRecognizer
- (UIGestureRecognizerState)state { return self.testState; }
- (CGPoint)locationInView:(UIView *)view { return CGPointMake(100.0, 100.0); }
- (void)setEnabled:(BOOL)enabled {
    if (!enabled) {
        self.cancellationCount += 1;
    }
    [super setEnabled:enabled];
}
@end

// 仅替换菜单绘制与应用启动，保留实际手势分发和关闭逻辑，不启动 HUD 私有服务。
@interface ArcLaunchTestHUDController : FloatingHUDViewController
@property (nonatomic) NSUInteger launchCount;
@end

@implementation ArcLaunchTestHUDController
- (void)loadView { self.view = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 390.0, 844.0)]; }
- (void)viewDidLoad {
    self.handleView = [UIView new];
    [self.view addSubview:self.handleView];
    self.backdropView = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.backdropView.hidden = YES;
    [self.view addSubview:self.backdropView];
}
- (void)layoutHandle {}
- (void)layoutBar {}
- (CGPoint)barCenter { return CGPointMake(0.0, 100.0); }
- (BOOL)showMenu {
    UIView *itemView = [[UIView alloc] initWithFrame:CGRectMake(80.0, 80.0, 40.0, 40.0)];
    [self.view addSubview:itemView];
    [self.menuItemViews addObject:itemView];
    self.menuShortcuts = self.settingsStore.settings.shortcuts;
    self.menuVisible = YES;
    self.backdropView.hidden = NO;
    self.backdropView.alpha = 1.0;
    return YES;
}
- (void)updateHoveredItemView:(UIView *)itemView { self.hoveredItemView = itemView; }
- (void)launchShortcut:(ArcLaunchShortcut *)shortcut inFloatingWindow:(BOOL)inFloatingWindow { self.launchCount += 1; }
@end

@interface FloatingHUDViewControllerTests : XCTestCase
@property (nonatomic, strong) ArcLaunchTestHUDController *controller;
@property (nonatomic) BOOL animationsEnabled;
@end

@implementation FloatingHUDViewControllerTests

- (void)setUp {
    [super setUp];
    self.animationsEnabled = UIView.areAnimationsEnabled;
    [UIView setAnimationsEnabled:NO];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:NSUUID.UUID.UUIDString];
    ArcLaunchSettingsStore *store = [[ArcLaunchSettingsStore alloc] initWithUserDefaults:defaults key:@"settings"];
    [store addShortcut:[[ArcLaunchShortcut alloc] initWithBundleIdentifier:@"com.example.app" displayName:@"App"]];
    self.controller = [[ArcLaunchTestHUDController alloc] initWithSettingsStore:store applicationBridge:[SystemApplicationBridge new]];
    [self.controller loadViewIfNeeded];
}

- (void)tearDown {
    [self.controller dismissMenuAnimated:NO];
    self.controller = nil;
    [UIView setAnimationsEnabled:self.animationsEnabled];
    [super tearDown];
}

- (ArcLaunchTestPanRecognizer *)beginPan {
    ArcLaunchTestPanRecognizer *pan = [ArcLaunchTestPanRecognizer new];
    [self.controller.handleView addGestureRecognizer:pan];
    pan.testState = UIGestureRecognizerStateBegan;
    [self.controller handlePan:pan];
    return pan;
}

- (void)testLostEndClosesMenuAndAllowsReopening {
    ArcLaunchTestPanRecognizer *pan = [self beginPan];
    UIView *itemView = self.controller.menuItemViews.firstObject;
    NSTimer *timer = [NSTimer timerWithTimeInterval:10.0 repeats:NO block:^(NSTimer *firedTimer) {}];
    self.controller.floatingModeTimer = timer;
    self.controller.floatingOpenReady = YES;
    self.controller.dragging = YES;
    self.controller.dragMoved = YES;

    // 没有 Ended/Cancelled 回调时，直接模拟全部手指离开的兜底通知。
    [self.controller globalTouchSequenceDidEnd];

    XCTAssertFalse(self.controller.menuVisible);
    XCTAssertNil(itemView.superview);
    XCTAssertEqual(self.controller.menuItemViews.count, 0);
    XCTAssertEqual(self.controller.menuShortcuts.count, 0);
    XCTAssertNil(self.controller.hoveredItemView);
    XCTAssertNil(self.controller.activeMenuPanRecognizer);
    XCTAssertNil(self.controller.floatingModeTimer);
    XCTAssertFalse(timer.valid);
    XCTAssertFalse(self.controller.floatingOpenReady);
    XCTAssertFalse(self.controller.dragging);
    XCTAssertFalse(self.controller.dragMoved);
    XCTAssertTrue(self.controller.backdropView.hidden);
    XCTAssertGreaterThan(pan.cancellationCount, 0);
    XCTAssertEqual(self.controller.launchCount, 0);

    [self beginPan];
    XCTAssertTrue(self.controller.menuVisible);
}

- (void)testNormalEndLaunchesOnlyOnce {
    ArcLaunchTestPanRecognizer *pan = [self beginPan];
    pan.testState = UIGestureRecognizerStateEnded;
    [self.controller handlePan:pan];
    [self.controller globalTouchSequenceDidEnd];
    [self.controller handlePan:pan];
    XCTAssertFalse(self.controller.menuVisible);
    XCTAssertEqual(self.controller.launchCount, 1);
}

- (void)testCancelledAndFailedGesturesDoNotLaunch {
    for (NSNumber *state in @[@(UIGestureRecognizerStateCancelled), @(UIGestureRecognizerStateFailed)]) {
        ArcLaunchTestPanRecognizer *pan = [self beginPan];
        pan.testState = state.integerValue;
        [self.controller handlePan:pan];
        XCTAssertFalse(self.controller.menuVisible);
        XCTAssertEqual(self.controller.launchCount, 0);
    }
}

- (void)testOldGestureCallbacksDoNotAffectNewMenu {
    ArcLaunchTestPanRecognizer *oldPan = [self beginPan];
    ArcLaunchTestPanRecognizer *newPan = [self beginPan];
    UIView *itemView = self.controller.menuItemViews.firstObject;
    for (NSNumber *state in @[@(UIGestureRecognizerStateChanged), @(UIGestureRecognizerStateCancelled), @(UIGestureRecognizerStateEnded)]) {
        oldPan.testState = state.integerValue;
        [self.controller handlePan:oldPan];
        XCTAssertTrue(self.controller.menuVisible);
        XCTAssertEqual(self.controller.activeMenuPanRecognizer, newPan);
        XCTAssertEqual(self.controller.menuItemViews.firstObject, itemView);
        XCTAssertEqual(self.controller.launchCount, 0);
    }
}

- (void)testTouchEndPreservesSettingsPreview {
    [self.controller showMenu];
    self.controller.previewingMenu = YES;
    [self.controller globalTouchSequenceDidEnd];
    XCTAssertTrue(self.controller.menuVisible);
    XCTAssertTrue(self.controller.previewingMenu);
    XCTAssertEqual(self.controller.launchCount, 0);
}

@end
