#import "ArcLaunchFloatingWindowLayout.h"
#import <math.h>

const NSUInteger ArcLaunchMaximumFloatingWindows = 3;
const CGFloat ArcLaunchFloatingWindowDefaultScale = 0.8;
const CGFloat ArcLaunchFloatingWindowMinimumScale = 0.35;
const CGFloat ArcLaunchFloatingWindowMaximumScale = 0.9;
const CGFloat ArcLaunchFloatingWindowThumbnailScale = 0.16;
const CGFloat ArcLaunchFloatingWindowTitleBarHeight = 28.0;
const CGFloat ArcLaunchFloatingWindowCornerRadius = 18.0;
const CGFloat ArcLaunchFloatingWindowThumbnailCornerRadius = 10.0;
const CGFloat ArcLaunchFloatingDockPadding = 6.0;
static const CGFloat ArcLaunchFloatingWindowCascadeOffset = 24.0;
static const CGFloat ArcLaunchFloatingMinimizeOverhangRatio = 0.35;
// 收纳区缩略图与屏幕边缘、安全区顶部以及彼此之间的距离。
static const CGFloat ArcLaunchFloatingDockEdgeInset = 8.0;
static const CGFloat ArcLaunchFloatingDockTopInset = 12.0;
static const CGFloat ArcLaunchFloatingDockSpacing = 10.0;

@implementation ArcLaunchFloatingWindowLayout

+ (CGFloat)clampedScale:(CGFloat)scale {
    if (!isfinite(scale)) {
        return ArcLaunchFloatingWindowDefaultScale;
    }
    return MIN(MAX(scale, ArcLaunchFloatingWindowMinimumScale), ArcLaunchFloatingWindowMaximumScale);
}

+ (CGSize)windowSizeForScale:(CGFloat)scale screenSize:(CGSize)screenSize {
    CGFloat clampedScale = [self clampedScale:scale];
    return CGSizeMake(round(screenSize.width * clampedScale), round(screenSize.height * clampedScale) + ArcLaunchFloatingWindowTitleBarHeight);
}

+ (CGFloat)scaleForWindowWidth:(CGFloat)width screenSize:(CGSize)screenSize {
    if (screenSize.width <= 0.0) {
        return ArcLaunchFloatingWindowDefaultScale;
    }
    return [self clampedScale:width / screenSize.width];
}

+ (CGSize)thumbnailSizeForScreenSize:(CGSize)screenSize {
    return CGSizeMake(round(screenSize.width * ArcLaunchFloatingWindowThumbnailScale), round(screenSize.height * ArcLaunchFloatingWindowThumbnailScale));
}

+ (CGRect)safeBoundsForBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    return UIEdgeInsetsInsetRect(bounds, safeAreaInsets);
}

+ (CGRect)defaultFrameForIndex:(NSUInteger)index scale:(CGFloat)scale screenSize:(CGSize)screenSize bounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    CGSize size = [self windowSizeForScale:scale screenSize:screenSize];
    CGRect safeBounds = [self safeBoundsForBounds:bounds safeAreaInsets:safeAreaInsets];
    CGFloat offset = ArcLaunchFloatingWindowCascadeOffset * index;
    CGRect frame = CGRectMake(CGRectGetMidX(safeBounds) - size.width / 2.0 + offset, CGRectGetMidY(safeBounds) - size.height / 2.0 + offset, size.width, size.height);
    return [self clampedFrame:frame inBounds:bounds safeAreaInsets:safeAreaInsets];
}

+ (CGRect)clampedFrame:(CGRect)frame inBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    CGRect safeBounds = [self safeBoundsForBounds:bounds safeAreaInsets:safeAreaInsets];
    CGFloat minX = CGRectGetMinX(bounds);
    CGFloat maxX = MAX(minX, CGRectGetMaxX(bounds) - CGRectGetWidth(frame));
    CGFloat minY = CGRectGetMinY(safeBounds);
    CGFloat maxY = MAX(minY, CGRectGetMaxY(safeBounds) - CGRectGetHeight(frame));
    frame.origin.x = MIN(MAX(CGRectGetMinX(frame), minX), maxX);
    frame.origin.y = MIN(MAX(CGRectGetMinY(frame), minY), maxY);
    return frame;
}

+ (BOOL)shouldMinimizeFrame:(CGRect)frame inBounds:(CGRect)bounds edge:(ArcLaunchEdge *)edge {
    CGFloat threshold = CGRectGetWidth(frame) * ArcLaunchFloatingMinimizeOverhangRatio;
    CGFloat leftOverhang = CGRectGetMinX(bounds) - CGRectGetMinX(frame);
    CGFloat rightOverhang = CGRectGetMaxX(frame) - CGRectGetMaxX(bounds);
    if (leftOverhang <= threshold && rightOverhang <= threshold) {
        return NO;
    }
    if (edge) {
        *edge = leftOverhang > rightOverhang ? ArcLaunchEdgeLeft : ArcLaunchEdgeRight;
    }
    return YES;
}

+ (CGRect)dockSlotFrameAtIndex:(NSUInteger)index edge:(ArcLaunchEdge)edge screenSize:(CGSize)screenSize bounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    CGSize size = [self thumbnailSizeForScreenSize:screenSize];
    CGRect safeBounds = [self safeBoundsForBounds:bounds safeAreaInsets:safeAreaInsets];
    CGFloat x = edge == ArcLaunchEdgeLeft ? CGRectGetMinX(bounds) + ArcLaunchFloatingDockEdgeInset : CGRectGetMaxX(bounds) - ArcLaunchFloatingDockEdgeInset - size.width;
    CGFloat y = CGRectGetMinY(safeBounds) + ArcLaunchFloatingDockTopInset + index * (size.height + ArcLaunchFloatingDockSpacing);
    return CGRectMake(x, y, size.width, size.height);
}

+ (CGRect)dockPlateFrameForCount:(NSUInteger)count edge:(ArcLaunchEdge)edge screenSize:(CGSize)screenSize bounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    if (count == 0) {
        return CGRectZero;
    }
    CGRect first = [self dockSlotFrameAtIndex:0 edge:edge screenSize:screenSize bounds:bounds safeAreaInsets:safeAreaInsets];
    CGRect last = [self dockSlotFrameAtIndex:count - 1 edge:edge screenSize:screenSize bounds:bounds safeAreaInsets:safeAreaInsets];
    return CGRectInset(CGRectUnion(first, last), -ArcLaunchFloatingDockPadding, -ArcLaunchFloatingDockPadding);
}

@end
