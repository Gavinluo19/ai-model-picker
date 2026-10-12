# API 参考价 — 2026-10-01 核对

口径：每百万 Token 普通输入（缓存未命中）/输出单价；不计缓存、批量、Fast、工具或其它模式。仅帮助比较，不等于订阅扣费。参考币种转换固定为 1 USD≈7 CNY，是比较假设，不是实时汇率。

| 型号 | 原币种 | 输入 / 输出 | 官方来源与范围 |
|---|---|---|---|
| GPT-6.1 Sol | USD | 2 / 10 | [模型页](https://developers.openai.com/api/docs/models/gpt-6.1-sol)，Standard 短上下文 |
| GPT-6 Astra | USD | 10 / 50 | [API 定价](https://developers.openai.com/api/docs/pricing)，Standard 短上下文 |
| Sonnet 5.5 | USD | 2 / 10 | [官方发布页](https://www.anthropic.com/claude-sonnet-5-5) |
| Opus 5.5 | USD | 4 / 20 | [官方发布页](https://www.anthropic.com/claude-sonnet-5-5)中的对照表 |
| Kimi K3 | CNY | 20 / 100 | [开放平台首页](https://platform.kimi.com/)，中国平台，不包含缓存写入 |
| GLM-5.3 | CNY | 8 / 28 | [BigModel 定价](https://open.bigmodel.cn/pricing)，浏览器展开详细价格核对 |
| GLM-5.3-Flash | CNY | 0.8 / 2.8 | [BigModel 定价](https://open.bigmodel.cn/pricing)，标准价，排除临时五折促销 |
| DeepSeek-V4.1-Flash | USD | 0.3 / 1.2 | [DeepSeek 定价](https://api-docs.deepseek.com/quick_start/pricing/)，高峰、缓存未命中；低峰更低 |

每个执行端指向的同名模型使用以上厂商价格作参考，不推定执行端服务与厂商 API 的实际计费一致。原币种和口径在 `Resources/APIPrices.json` 保留，更新 JSON 后可在设置导入；导入前验证并预览。各档推理会改变实际 Token 用量，这里不据 API 单价推算订阅剩余次数。

## V0.4 在线更新

[Models.dev 数据规范](https://github.com/anomalyco/models.dev/blob/dev/README.md)提供社区维护的厂商规范化 USD/百万 Token 价格；[Frankfurter](https://frankfurter.dev/)提供日参考汇率。在线刷新采用前者的直接厂商身份精确匹配，并标注社区来源，不声称已核验各地区厂商账单。表格换算 USD/CNY 用于比较，不代表美国与中国实际售价。初始官方基线与刷新后的社区参考要分别理解。
