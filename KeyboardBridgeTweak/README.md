# ArcLaunch 键盘桥接插件

这是一个 Theos 插件，针对 ArcLaunch 通过 FrontBoard 悬浮托管的应用启用 UIKit 窗口化软键盘策略。插件只在被托管应用中运行；ArcLaunch HUD 窗口保留系统默认的 key-window 行为，以保证悬浮菜单和触摸事件正常工作。

GitHub Actions 只产出 `arm64` 和 `arm64e` 两个 `.deb`。两个包的 Debian 架构都标为 `iphoneos-arm64`，文件名对应包内 dylib 的实际切片，方便 rootful、rootless 和 RootHide 的包管理器安装 arm64e 变体。安装脚本会选择注入目录：rootless 使用 `/var/jb/Library/MobileSubstrate/DynamicLibraries`，rootful 和 RootHide 使用 `/Library/MobileSubstrate/DynamicLibraries`。

ArcLaunch 通过 Darwin 通知 `com.kleinersource.arclaunch.keyboardbridge.<bundle>` 将当前键盘显示模式传给 guest。iOS 17.0–17.3 的 FrontBoard presenter 需要 windowed 视觉模式保证键盘可用；选“全屏”后 HUD 临时铺满屏幕，并在键盘收起后恢复小窗。iOS 17.4 及以上使用 UIKit 场景托管；选“全屏”时插件关闭 windowed 视觉模式，让系统键盘按设备屏幕布局显示而悬浮应用保持小窗，选“小窗内”则沿用系统视觉模式。

## 安装

1. 在 GitHub Actions 中只按设备架构下载 `ArcLaunchKeyboardBridge-arm64` 或 `ArcLaunchKeyboardBridge-arm64e` artifact；越狱类型由安装脚本处理。用 Relaxin 的包管理器安装。
2. 确认 ElleKit 对 ArcLaunch 和需要悬浮运行的应用启用了 tweak 注入。
3. 重启 ArcLaunch 和已运行的 guest 应用。

## 验收

在 iOS 17.0–17.3.1 设备上，测试键盘弹出后悬浮窗是否铺满屏幕、输入及收起后是否恢复；在 iOS 17.4 及以上设备上，测试全屏模式的键盘是否按设备屏幕布局显示且悬浮应用仍保持小窗。确认扇形菜单、悬浮条拖动与窗口缩放正常。用系统日志筛选 `ArcLaunchKeyboardBridge`，应能看到 guest 应用收到 HUD PID 与 fullscreen 模式位的记录。

## 构建

需要安装 Theos 与 patched iOS SDK：

```sh
gmake package THEOS_PACKAGE_SCHEME=rootless
```

这条命令生成用于本地调试的 rootless 包。跨越 rootful、rootless 和 RootHide 的 `arm64`、`arm64e` 正式包由 GitHub Actions 分别打包。
