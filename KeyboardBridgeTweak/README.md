# ArcLaunch 键盘桥接插件

此 RootHide/ElleKit 插件为 iOS 17.0–17.3.1 上由 FrontBoard presenter 悬浮托管的应用，尝试启用 UIKit 的窗口化软键盘路径。它包含两个 Theos tweak：HUD 侧避免覆盖层成为键盘 key window；guest 侧只在 ArcLaunch 正在悬浮托管该 bundle 时修改 `UIKeyboardVisualModeManager` 的键盘策略。

这是针对旧版 FrontBoard 路径的缓解方案。它不注册 KeyboardManagement hosted 服务；参考分析指出，窗口化 hook 未必能单独解决键盘焦点或位置问题，需在设备上验证。

## 安装

1. 在 GitHub Actions 的 `ArcLaunchKeyboardBridge` artifact 下载 `.deb`，用 Relaxin 的包管理器安装。
2. 确认 ElleKit 对 ArcLaunch 和需要悬浮运行的应用启用了 tweak 注入。
3. 重启 ArcLaunch 和已运行的 guest 应用。

## 验收

在 Relaxin 支持的 iOS 17.0–17.3.1 设备上，分别测试悬浮与全屏运行：点按文本框、确认键盘显示且位置正确、输入文本、收起后再次唤起；同时确认 HUD 的触摸、拖动和缩放正常。用系统日志筛选 `ArcLaunchKeyboardBridge`，应能看到 HUD 发布状态及 guest 收到活动宿主 PID 的记录。

## 构建

需要安装 Theos 与 patched iOS SDK：

```sh
gmake package THEOS_PACKAGE_SCHEME=rootless
```

生成的 rootless `.deb` 位于 `packages/`。GitHub Actions 会构建并检查包内的两个 dylib 和对应过滤 plist。
