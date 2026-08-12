# Tarnhelm 完整规则转换包

本目录把 [TarnhelmDocument](https://github.com/lz233/TarnhelmDocument) 的规则转换为 Nothung 可导入 JSON。规则、原始源文件和转换结果按 **GPL-3.0-only** 单独分发，不会自动包含在 Nothung App 中。

- 上游提交：见 `MANIFEST.json`
- 原始规则源：`SOURCE-rules.md`
- 转换结果：`tarnhelm-complete.nothung.json`
- GPL 全文：`LICENSE`
- 转换工具：`../../Tools/convert_tarnhelm_rules.rb`

## 导入

1. 把 `tarnhelm-complete.nothung.json` 保存到 iPhone 的“文件”。
2. 打开 Nothung 设置，进入“导入与导出”。
3. 选择“从文件导入规则包”，检查数量后保存。

导入会替换当前规则配置；需要保留现有配置时请先导出。向他人分发该转换包时，应同时保留本目录中的许可证和源文件。

## 重新生成

在仓库根目录运行：

```sh
ruby Tools/convert_tarnhelm_rules.rb \
  RulePacks/Tarnhelm-GPL-3.0/SOURCE-rules.md \
  RulePacks/Tarnhelm-GPL-3.0/tarnhelm-complete.nothung.json \
  RulePacks/Tarnhelm-GPL-3.0/MANIFEST.json \
  "cdf1fee3e6d47db4c8ec0aa64726ef51b8247422"
```
