# Features / 功能与边界

| Area / 能力 | Implemented / 已实现 | Important boundary / 边界 |
|---|---|---|
| Task input / 输入 | Rich-text paste, bold/italic/list, wrapping, locale/theme preservation / 富文本、列表、换行、切换保留 | Handoff is text only, no attachment upload / 交接只用文字，不上传附件 |
| Offline selection / 离线 | Bilingual deterministic Markdown V2 conditions, category fallback / 双语条件匹配与类别兜底 | No universal semantic understanding / 不理解任意语义 |
| JEV / 智能分类 | Optional keychain key, fixed endpoint, response validation, cancellation and offline fallback / 可选Key、响应校验与离线回退 | Live connectivity and accuracy pending / 真实连通与准确率待验收 |
| Recommendations / 推荐 | Four policy priorities, direct selection, workspace/effort controls, reason / 四卡、横向调整、依据 | Trial rules, not measured rankings / 试行政策，不是实测排名 |
| Client discovery / 客户端 | App/bundle identity checks and opt-in app/model settings / 应用身份检测及可用项设置 | No subscription-balance or account-entitlement lookup / 不读取余额或权限 |
| Manual handoff / 手动交接 | Open destination and copy task / 打开与复制 | User selects and sends in original app / 用户在原端选择并发送 |
| Preparation / 自动准备 | Prototype accessibility adapters, empty-draft/focus/readback guards / 实验适配器与空草稿、焦点、回读保护 | Four-client end-to-end acceptance pending; no auto-send / 四端待验收，不自动发送 |
| Claude notice / 提醒 | Amber label and one acknowledgement for open/prepare / 橙色标签与一次知悉 | No network/account safety detector / 不检测网络或账号安全 |
| Public model library / 目录 | Supported-provider text metadata, cached snapshots / 支持厂商文字模型与缓存 | Discovery is not account access or route promotion / 发现不等于权限或推荐 |
| Prices / 价格 | Input/output references, sorted table, USD/CNY, sources, timestamps / 输入输出价、排序、双币种、日期来源 | API references, not bills or country offers / 非账单或地区报价 |
| Refresh / 更新 | Unauthenticated public GET, independent streams, partial failures, local Undo / 公共GET、独立失败与撤销 | Community metadata can lag; retain old values / 社区数据可能滞后 |
| Rules / 规则 | Import/validate/preview/export/rollback; V1 readable / 导入、预览、导出、回退 | News text is not a valid rulebook / 新闻文章不能直接当规则 |
| Mac / 使用体验 | Native Swift/AppKit, Dock/status item, minimize/reopen, custom hotkey / 原生窗口、Dock、菜单栏、自定义快捷键 | Latest window behavior and other-Mac runtime pending / 新窗口及其它Mac待验收 |
| Privacy / 隐私 | No uploaded analytics, minimal local event records, Keychain / 不上传分析日志，Keychain | JEV mode and target apps still have their own data policies / 云分类与目标客户端有各自数据政策 |

## Deliberately absent / 不做什么

No hidden credential extraction, quota expansion, automatic purchase, subscription resale, auto-send, unified chat history, guaranteed best-model ranking, or unattended cross-app task completion.

不提取隐藏凭证、不扩充额度、不自动购买、不转售订阅、不自动发送、不统一托管聊天历史，不保证“最佳模型”或无人值守跨应用完成。

These boundaries are product choices or unvalidated capabilities, not assertions that alternatives cannot offer them. / 这些是本产品的选择与验证边界，不表示竞品做不到。
