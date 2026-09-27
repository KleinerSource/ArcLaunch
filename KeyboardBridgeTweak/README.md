# ArcLaunch 键盘桥接插件

这是一个 rootless Theos 插件，针对 ArcLaunch 通过 FrontBoard 悬浮托管的应用启用 UIKit 窗口化软键盘策略。插件只在被托管应用中运行；ArcLaunch HUD 窗口保留系统默认的 key-window 行为，以保证悬浮菜单和触摸事件正常工作。

插件支持 `arm64` 和 `arm64e`。GitHub Actions 会构建 rootless `.deb`，并检查包内 dylib 的两个架构切片。

## 安装

1. 在 GitHub Actions 的 `ArcLaunchKeyboardBridge` artifact 下载 `.deb`，用 Relaxin 的包管理器安装。
2. 确认 ElleKit 对 ArcLaunch 和需要悬浮运行的应用启用了 tweak 注入。
3. 重启 ArcLaunch 和已运行的 guest 应用。

## 验收

在 Relaxin 支持的 iOS 17.0–17.3.1 设备上，测试悬浮应用中的键盘显示、输入和再次唤起；同时确认扇形菜单、悬浮条拖动与窗口缩放正常。用系统日志筛选 `ArcLaunchKeyboardBridge`，应能看到 guest 应用收到活动 HUD PID 的记录。

## 构建

需要安装 Theos 与 patched iOS SDK：

```sh
gmake package THEOS_PACKAGE_SCHEME=rootless
```

生成的 rootless `.deb` 位于 `packages/`。
