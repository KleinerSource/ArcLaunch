#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

FOUNDATION_EXPORT BOOL ArcLaunchRegisterHUDEventCallback(void);
/// 以只读方式监听全局触摸，识别到轻点时在主线程回调抬起位置（UIScreen.fixedCoordinateSpace 坐标）。
/// 监听不拦截触摸，下层应用照常响应；传 nil 停止回调。
FOUNDATION_EXPORT void ArcLaunchSetGlobalTapHandler(void (^ _Nullable handler)(CGPoint fixedLocation));
