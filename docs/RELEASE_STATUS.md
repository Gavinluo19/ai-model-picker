# V0.4 open-source alpha: verification and limitations

[简体中文说明在下方](#中文说明)

Publication review: **2026-10-12**. Product V0.4 uses internal macOS version **1.3.0, build 4**. This is a prerelease for developers and early testers.

| Evidence | What it establishes | What it does not establish |
|---|---|---|
| Local core/native-component checks, rerun before publication | Markdown validation, deterministic routing, privacy of mock HTTP requests, update merging/failure/cancellation, price ordering, attributed-text behavior, shortcut registration logic | Real JEV accuracy, current subscription access, or successful desktop task execution |
| Universal2 build and ad hoc signature / DMG verification | arm64 + x86_64 binary compilation and package integrity | Apple notarization or runtime compatibility across machines |
| Earlier local UI observations | Offline recommendations, four priorities, client-choice changes, input/price display | Full V0.4 window behavior and every adapter |
| Earlier live public-metadata request | Public catalog/FX transport worked at the recorded test time | Perpetual availability, correctness of all registry data, JEV connectivity or desktop-account availability |

**Pending:** live JEV account classification, latest four-client end-to-end preparation, V0.4 Dock/minimize/settings foreground behavior, Intel/minimum-OS runtime acceptance, another-Mac acceptance, Developer ID signing and Apple notarization.

The initial bundled model and price data are dated **2026-10-01**. Current client/market availability may differ. Public refresh updates discovery and API references; routing remains in Markdown and needs manual validation before new models are promoted.

Manual **Offline → Open + Copy** is the recommended alpha workflow. If macOS blocks the downloaded unnotarized binary, use a local source build or wait for a signed release; do not disable system protections. Important unsent text should be preserved before quitting/upgrading.

This repository does not claim measured savings, best-model correctness, quota expansion, account safety, or unattended cross-client task completion. Publishing the repository and Release is distinct from completing the pending acceptance tests.

An optional CI template is included outside `.github/workflows`. No green hosted-CI badge is asserted for this initial release. The local release check results and hashes are provided with the Release assets.

## 中文说明

公开发布审阅日期为 **2026-10-12**，产品 V0.4，系统内部版本 1.3.0 build 4。定位是面向开发者与早期测试者的 Alpha，不是已经全面验收的稳定产品。

本地检查与双架构构建可以证明规则、数据协议及包的完整性，不能代替真实 JEV、账户模型可用性或桌面交接验收。先前实机观察覆盖了离线推荐、四级选择、客户端改选和部分输入/价格展示；V0.4 的窗口行为及四端完整准备仍待验证。

仍未完成：真实 JEV 分类、当前四客户端端到端准备、V0.4 Dock/最小化/设置置前、Intel 与最低支持系统运行、另一台 Mac、正式签名与 Apple 公证。

初始内置目录/价格日期为 2026-10-01；不是发布当天已核实的账户能力。公共更新不自动改业务路由。推荐先用离线→打开与复制；未公证包若被拦截，采用本地构建或等待正式版本，不关闭安全保护。

没有已测节省比例、模型选择成功率或真实订阅节省金额。不扩充额度，不检测安全网络，不保证无人值守跨客户端完成。公开仓库/Release 成功与完成这些验收是两回事。
