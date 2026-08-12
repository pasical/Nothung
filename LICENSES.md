# 许可证与来源说明

## Nothung

除下述 GPL 规则包外，本仓库中的 Nothung Swift 代码、界面文案和原创素材目前未授予开源许可证，版权默认保留。公开 GitHub 仓库不等于允许复制、修改或再分发；若未来选择 MIT、Apache-2.0 或其他许可证，应在根目录加入相应 `LICENSE` 文件并更新本说明。

Nothung 根据产品需求和 Tarnhelm 的公开行为独立实现。项目开发者研究过 Tarnhelm，因此不主张严格隔离式 clean-room；但 Nothung 没有翻译或复制 Tarnhelm 的 Kotlin 源码、图标和界面资源。

App 默认携带的通用追踪参数、X/Twitter、Bilibili 和 `b23.tv` 行为是为 Nothung 单独编写的少量互操作规则，不是 Tarnhelm 完整规则库的副本。

原项目 [lz233/Tarnhelm](https://github.com/lz233/Tarnhelm) 使用 GPL-3.0。把其代码翻译成另一种语言仍属于 GPL 所称的修改；本项目采用独立实现，是为了避免把代码翻译误称为重新授权。

## 可选 Tarnhelm 规则包

[`RulePacks/Tarnhelm-GPL-3.0`](RulePacks/Tarnhelm-GPL-3.0) 是从 [lz233/TarnhelmDocument](https://github.com/lz233/TarnhelmDocument) 转换的完整规则包。TarnhelmDocument 使用 GPL-3.0；因此该目录中的原始规则源、转换数据和分发材料按 **GPL-3.0-only** 单独提供。

该目录包含完整 GPL 文本、固定上游提交号、原始规则源和生成清单。规则包不会被编译进 Nothung，也不会自动导入；用户需要在 App 中明确选择文件。

这种目录级隔离不改变 Nothung 自有代码当前的许可证状态，也不解除转载 GPL 规则包时应保留许可证和源文件的义务。
