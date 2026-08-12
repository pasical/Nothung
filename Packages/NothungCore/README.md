# NothungCore

`NothungCore` 是 Nothung 的纯 Swift 链接清理引擎，不访问网络，也没有第三方运行时依赖。

```swift
let cleaner = NothungCleaner()
let result = try cleaner.clean(
    url: URL(string: "https://example.com/article?id=42&utm_source=newsletter")!
)

result.cleanedURL // https://example.com/article?id=42
```

引擎支持：

- 全局及域名限定的参数前缀/精确匹配
- 参数白名单覆盖黑名单
- 按顺序执行的正则替换
- 保留未删除参数的顺序、重复项、空值、百分号编码和 fragment
- 拒绝非 HTTP(S)、缺少 host 或带有 userinfo 的 URL
- 对规则数量、正则长度、替换长度和最终 URL 长度设限

运行 45 项测试：

```sh
swift test
```
