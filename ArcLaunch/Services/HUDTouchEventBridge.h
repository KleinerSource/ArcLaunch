#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

FOUNDATION_EXPORT BOOL ArcLaunchRegisterHUDEventCallback(void);
/// 以只读方式监听全局触摸，识别到轻点时在主线程回调抬起位置（UIScreen.fixedCoordinateSpace 坐标）。
/// shouldTrack 在手指按下时调用，返回 NO 的触摸不再判定为轻点；必须在按下时判断，
/// 抬起时界面可能已被这次点击改变（例如边栏缩略图已开始展开）。
/// 监听不拦截触摸，下层应用照常响应；handler 传 nil 停止回调。
FOUNDATION_EXPORT void ArcLaunchSetGlobalTapHandler(BOOL (^ _Nullable shouldTrack)(CGPoint fixedLocation), void (^ _Nullable handler)(CGPoint fixedLocation));
/// 全部手指离开后，在主线程补取消未结束的 HUD 触摸并回调；不拦截系统手势。
/// 正常结束事件优先派发，期间若有新触摸则取消本次清理；handler 传 nil 停止回调。
FOUNDATION_EXPORT void ArcLaunchSetGlobalTouchEndHandler(void (^ _Nullable handler)(void));
