@import XCTest;

#import "ArcLaunchFloatingWindowLayout.h"

@interface ArcLaunchFloatingWindowLayoutTests : XCTestCase
@end

@implementation ArcLaunchFloatingWindowLayoutTests

static const CGSize ArcLaunchTestScreenSize = {390.0, 844.0};
static const CGRect ArcLaunchTestBounds = {{0.0, 0.0}, {390.0, 844.0}};
static const UIEdgeInsets ArcLaunchTestSafeAreaInsets = {47.0, 0.0, 34.0, 0.0};

- (void)testScaleIsClamped {
    XCTAssertEqualWithAccuracy([ArcLaunchFloatingWindowLayout clampedScale:0.1], ArcLaunchFloatingWindowMinimumScale, 0.0001);
    XCTAssertEqualWithAccuracy([ArcLaunchFloatingWindowLayout clampedScale:2.0], ArcLaunchFloatingWindowMaximumScale, 0.0001);
    XCTAssertEqualWithAccuracy([ArcLaunchFloatingWindowLayout clampedScale:NAN], ArcLaunchFloatingWindowDefaultScale, 0.0001);
    XCTAssertEqualWithAccuracy([ArcLaunchFloatingWindowLayout scaleForWindowWidth:1000.0 screenSize:ArcLaunchTestScreenSize], ArcLaunchFloatingWindowMaximumScale, 0.0001);
}

- (void)testWindowKeepsScreenAspectRatioBelowTitleBar {
    for (NSNumber *scale in @[@0.35, @0.5, @0.8, @0.9]) {
        CGSize size = [ArcLaunchFloatingWindowLayout windowSizeForScale:scale.doubleValue screenSize:ArcLaunchTestScreenSize];
        CGFloat contentHeight = size.height - ArcLaunchFloatingWindowTitleBarHeight;
        XCTAssertEqualWithAccuracy(size.width / contentHeight, ArcLaunchTestScreenSize.width / ArcLaunchTestScreenSize.height, 0.01);
        XCTAssertEqualWithAccuracy([ArcLaunchFloatingWindowLayout scaleForWindowWidth:size.width screenSize:ArcLaunchTestScreenSize], scale.doubleValue, 0.01);
    }
}

- (void)testClampedFrameKeepsWindowInsideSafeArea {
    CGSize size = [ArcLaunchFloatingWindowLayout windowSizeForScale:0.5 screenSize:ArcLaunchTestScreenSize];
    CGRect offscreen = CGRectMake(-300.0, 900.0, size.width, size.height);
    CGRect clamped = [ArcLaunchFloatingWindowLayout clampedFrame:offscreen inBounds:ArcLaunchTestBounds safeAreaInsets:ArcLaunchTestSafeAreaInsets];
    XCTAssertGreaterThanOrEqual(CGRectGetMinX(clamped), 0.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(clamped), CGRectGetHeight(ArcLaunchTestBounds) - ArcLaunchTestSafeAreaInsets.bottom + 0.001);

    CGRect aboveTop = [ArcLaunchFloatingWindowLayout clampedFrame:CGRectMake(20.0, -200.0, size.width, size.height) inBounds:ArcLaunchTestBounds safeAreaInsets:ArcLaunchTestSafeAreaInsets];
    XCTAssertEqualWithAccuracy(CGRectGetMinY(aboveTop), ArcLaunchTestSafeAreaInsets.top, 0.001);
}

- (void)testTallWindowIsPinnedBelowSafeAreaTop {
    // 最大比例下窗口比安全区更高，此时标题条必须贴住安全区顶部而不是被推出屏幕。
    CGSize size = [ArcLaunchFloatingWindowLayout windowSizeForScale:ArcLaunchFloatingWindowMaximumScale screenSize:ArcLaunchTestScreenSize];
    XCTAssertGreaterThan(size.height, CGRectGetHeight(ArcLaunchTestBounds) - ArcLaunchTestSafeAreaInsets.top - ArcLaunchTestSafeAreaInsets.bottom);
    CGRect clamped = [ArcLaunchFloatingWindowLayout clampedFrame:CGRectMake(0.0, 400.0, size.width, size.height) inBounds:ArcLaunchTestBounds safeAreaInsets:ArcLaunchTestSafeAreaInsets];
    XCTAssertEqualWithAccuracy(CGRectGetMinY(clamped), ArcLaunchTestSafeAreaInsets.top, 0.001);
}

- (void)testDefaultFramesCascadeInsideSafeArea {
    CGRect previous = CGRectNull;
    for (NSUInteger index = 0; index < ArcLaunchMaximumFloatingWindows; index++) {
        CGRect frame = [ArcLaunchFloatingWindowLayout defaultFrameForIndex:index scale:ArcLaunchFloatingWindowDefaultScale screenSize:ArcLaunchTestScreenSize bounds:ArcLaunchTestBounds safeAreaInsets:ArcLaunchTestSafeAreaInsets];
        XCTAssertGreaterThanOrEqual(CGRectGetMinY(frame), ArcLaunchTestSafeAreaInsets.top - 0.001);
        XCTAssertGreaterThanOrEqual(CGRectGetMinX(frame), 0.0);
        XCTAssertLessThanOrEqual(CGRectGetMaxX(frame), CGRectGetWidth(ArcLaunchTestBounds) + 0.001);
        if (!CGRectIsNull(previous)) {
            XCTAssertFalse(CGPointEqualToPoint(frame.origin, previous.origin));
        }
        previous = frame;
    }
}

- (void)testMinimizeRequiresDraggingPastEdge {
    CGSize size = [ArcLaunchFloatingWindowLayout windowSizeForScale:0.5 screenSize:ArcLaunchTestScreenSize];
    ArcLaunchEdge edge = ArcLaunchEdgeLeft;
    CGRect slightlyOut = CGRectMake(CGRectGetWidth(ArcLaunchTestBounds) - size.width + size.width * 0.2, 200.0, size.width, size.height);
    XCTAssertFalse([ArcLaunchFloatingWindowLayout shouldMinimizeFrame:slightlyOut inBounds:ArcLaunchTestBounds edge:&edge]);

    CGRect farRight = CGRectMake(CGRectGetWidth(ArcLaunchTestBounds) - size.width * 0.5, 200.0, size.width, size.height);
    XCTAssertTrue([ArcLaunchFloatingWindowLayout shouldMinimizeFrame:farRight inBounds:ArcLaunchTestBounds edge:&edge]);
    XCTAssertEqual(edge, ArcLaunchEdgeRight);

    CGRect farLeft = CGRectMake(-size.width * 0.5, 200.0, size.width, size.height);
    XCTAssertTrue([ArcLaunchFloatingWindowLayout shouldMinimizeFrame:farLeft inBounds:ArcLaunchTestBounds edge:&edge]);
    XCTAssertEqual(edge, ArcLaunchEdgeLeft);
}

- (void)testDockSlotsStackWithoutOverlapInsidePlate {
    for (NSNumber *edgeValue in @[@(ArcLaunchEdgeLeft), @(ArcLaunchEdgeRight)]) {
        ArcLaunchEdge edge = edgeValue.integerValue;
        CGRect plate = [ArcLaunchFloatingWindowLayout dockPlateFrameForCount:ArcLaunchMaximumFloatingWindows edge:edge screenSize:ArcLaunchTestScreenSize bounds:ArcLaunchTestBounds safeAreaInsets:ArcLaunchTestSafeAreaInsets];
        XCTAssertTrue(CGRectContainsRect(ArcLaunchTestBounds, plate));
        CGRect previous = CGRectNull;
        for (NSUInteger index = 0; index < ArcLaunchMaximumFloatingWindows; index++) {
            CGRect slot = [ArcLaunchFloatingWindowLayout dockSlotFrameAtIndex:index edge:edge screenSize:ArcLaunchTestScreenSize bounds:ArcLaunchTestBounds safeAreaInsets:ArcLaunchTestSafeAreaInsets];
            XCTAssertGreaterThanOrEqual(CGRectGetMinY(slot), ArcLaunchTestSafeAreaInsets.top);
            XCTAssertTrue(CGRectContainsRect(plate, slot));
            if (!CGRectIsNull(previous)) {
                XCTAssertFalse(CGRectIntersectsRect(previous, slot));
            }
            previous = slot;
        }
    }
    XCTAssertTrue(CGRectEqualToRect([ArcLaunchFloatingWindowLayout dockPlateFrameForCount:0 edge:ArcLaunchEdgeRight screenSize:ArcLaunchTestScreenSize bounds:ArcLaunchTestBounds safeAreaInsets:ArcLaunchTestSafeAreaInsets], CGRectZero));
}

@end
