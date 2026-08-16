# Nothung

Nothung 是一个本地优先的 iOS 分享链接清理工具，用于移除跟踪参数、按规则改写链接和展开短链。

本项目参考了 Android 应用 [Tarnhelm](https://github.com/lz233/Tarnhelm) 的公开功能，但 Swift 代码、界面和图标均为独立实现；Nothung 不是 Tarnhelm 官方移植版，也不隶属于 Tarnhelm。

## 功能

- 在 App 中粘贴、清理、复制或分享链接
- 从其他 App 的分享面板使用“使用 Nothung 复制”
- 使用 Nothung 输入法浏览最近的清理记录，轻点插入，长按查看原文
- 自定义参数、正则和重定向规则
- 快捷指令支持（URL 输入、URL 输出）
- 默认清理常见追踪参数、X/Twitter 和 Bilibili 分享链接
- 默认展开 `b23.tv`；键盘仅在可见且获完全访问时自动捕捉剪贴板变化，不在后台运行，不包含广告或分析 SDK

最低支持 iOS 17。

## 构建

```sh
open iOS/Nothung.xcodeproj
```

在 Xcode 中选择 `Nothung` Scheme 和自己的开发团队即可运行。其他开发者进行真机测试时，可能需要替换 `dev.nothung.*` Bundle ID 和 `group.dev.nothung.shared` App Group。

工程文件由 XcodeGen 2.46.0 生成；修改 `iOS/project.yml` 后运行：

```sh
xcodegen generate --spec iOS/project.yml
```

核心测试：

```sh
cd Packages/NothungCore
swift test
```

当前基线为 Xcode 26.6、iOS 26.5 SDK；45 项核心测试通过，另包含 40 项 iOS 集成/安全测试。

## 规则与许可证

Nothung 默认不包含 Tarnhelm 的完整规则库。可选转换包位于 [`RulePacks/Tarnhelm-GPL-3.0`](RulePacks/Tarnhelm-GPL-3.0)，由 [TarnhelmDocument](https://github.com/lz233/TarnhelmDocument) 规则转换而来，按 GPL-3.0-only 单独分发并由用户手动导入。

Nothung 自有代码目前未授予开源许可证，默认保留全部权利。详见 [许可证与来源说明](LICENSES.md) 和 [隐私政策](PRIVACY.md)。
