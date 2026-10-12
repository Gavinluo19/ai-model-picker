# Product value and related projects / 产品价值与相近项目

Research date / 检索日期：2026-10-12. Based on vendor pages, repository READMEs and authenticated GitHub repository metadata. These projects were not installed or benchmarked in this review. / 基于官方页面、README 和 GitHub 仓库信息，未安装竞品或付费实测。仓库存在及文档能力不代表端到端体验或市场成功。

## Our value hypothesis / 我们的价值假设

For someone who already uses several AI desktop subscriptions, the friction is often choosing and starting the task, not finding another place to chat. A readable task policy, a small set of choices and a manual handoff can reduce repeated deliberation while retaining the original products. This is a hypothesis; measured time savings, quality uplift and subscription savings are not available yet.

多订阅用户的具体摩擦往往是“开始之前选哪个、用什么档位、怎么把需求送过去”。产品的价值在于把经验变成可查看的政策，减少反复选择并保留原客户端工作方式。这个假设仍需用户实验，不应宣传为已证明节省费用。

Useful fit / 适用：多工具咨询、研究、报告制作与软件任务；反复出现、需要一致选型的团队培训。Weak fit / 弱适用：单一助手已足够；已有固定偏好无需选择；需要大规模 API 调度或自动运行编码 Agent。

## What we found / 找到了什么

| Project / 产品 | Documented focus / 文档定位 | Relation to this project / 关系 |
|---|---|---|
| [AiAx Router](https://github.com/aiaxagents/aiax-router) | Subscription-aware task/model/effort routing through vendor CLIs / 基于官方 CLI 的订阅任务分流 | Close problem-level alternative; execution pipeline rather than original-desktop handoff / 问题接近，执行形态不同 |
| [Alloy'd](https://github.com/SeanL128/alloyd) | Workload distribution across Claude/ChatGPT subscriptions / 两类订阅的负载分配 | Related subscription-use goal; not our four-client consulting policy UI / 订阅利用目标相近 |
| [Claude Model Router](https://github.com/alexei-led/claude-router) | Claude Code model/effort plugin with JEV and other classifiers / 支持 JEV 等分类器的 Claude Code 插件 | Very relevant technical reference; JEV routing is not unique to this product / JEV 路由并非独创 |
| [Claude Code Router](https://github.com/musistudio/claude-code-router) | Local agent/model control plane / Agent 与模型本地控制面 | Broader execution and integration scope / 更广的执行控制范围 |
| [relay-ai](https://github.com/jacob-bd/relay-ai) | Model access inside coding agents / 为编码 Agent 接入模型 | Developer execution substitute, not the same user flow / 开发执行侧替代方案 |
| [RouteLLM](https://github.com/lm-sys/RouteLLM) | Serving/evaluating API routers / API 路由服务与评估框架 | Relevant routing research; not a desktop subscription picker / 路由技术参考 |
| [Cherry Studio](https://github.com/CherryHQ/cherry-studio), [official overview](https://www.cherryai.com/docs/en/) | Multi-model conversations, assistants and workspace features / 多模型聊天与工作台 | Alternative if users want a new unified workspace / 更适合希望统一工作台的人 |
| [Chatbox](https://github.com/chatboxai/chatbox), [help center](https://api.chatboxai.app/en/help-center) | AI client with cloud/BYOK options / AI 客户端与云服务/自带 Key | Aggregation-client alternative / 聚合客户端替代 |
| [TypingMind](https://docs.typingmind.com/other-resources/how-tos/how-to-access-gpt-4) | API-based frontend; its docs distinguish API access from ChatGPT Plus / API 前端，文档区分 API 与订阅 | Useful contrast in billing/entry point, not a reuse of original desktop subscriptions / 费用和使用入口不同 |

Do not read this as a recommendation to install or as a security certification. The comparison follows published descriptions, not independent performance tests. No competitor code was incorporated into this release. / 此表不是安装推荐或安全认证；未集成这些项目的代码。

## Differentiation we can honestly claim / 可以诚实主张的特色

- A native Mac entry point for choosing the first model/context/effort and keeping work in original desktop clients. / 原生 Mac 首次选模与原端交接。
- Readable, exportable Markdown task policy, including consulting/research/report delivery as well as coding. / 可审阅、可分享的咨询与编程任务规则。
- Bilingual offline matching as a fallback, and optional JEV classification. / 双语离线兜底、可选 JEV。
- Four explicit policy priorities spanning international and China-model client choices. / 国际与中国地区客户端四级选择。
- Separate metadata discovery, account verification and routing policy; no credential proxy or subscription-balance scraping. / 将发现、账户核验、业务路由分开，不代理登录凭证。

These are a particular combination of product choices, not evidence that no competitor can reproduce them. / 是功能组合与取舍，不是“全网唯一”。

## Product-manager assessment / 产品判断

Worth releasing as a small free open-source utility and learning asset. It is not yet justified as a standalone commercial platform. The strongest immediate audience is users who already feel selection friction, not all AI consumers. More UI features are unlikely to fix weak rule quality or unreliable handoff.

值得作为免费开源的小工具发布，但还不支持“独立商业平台”的结论。最先验证选择摩擦明确的人，核心约束是规则是否适合真实任务、交接是否可靠，而不是再加功能。界面与代码容易复制；长期差异更可能来自维护良好的任务规则、匿名验证案例和适配器贡献。

## A small validation before expanding / 扩张前的验证

Invite 10–15 users with at least two existing AI tools to try it for one week. Compare their existing workflow with the picker on anonymized repeated tasks. Record decision-to-start time, manual changes, first-result rework, handoff failures and voluntary repeat use. Suggested, not proven, continuation criteria: most participants find it useful on at least three tasks, median start time improves without more rework, and failures have a usable manual fallback. If it adds steps or recommendations are ignored, simplify the policy and interaction before broadening automation.

建议找 10–15 名已有至少两种 AI 工具的用户试用一周，比较原流程与助手的选型到开始时间、改选、返工、交接失败和主动复用。上述人数和继续条件是试验设计建议，不是已有用户数据；未达到就先简化规则与交互，不扩大自动化。
