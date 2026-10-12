# Privacy / 隐私说明

- Offline recommendations do not send task text over the network. 离线推荐不联网。
- AI recommendations send the current task and classification conditions to `https://api.typesafe.ai`; JEV account charges and policies apply. 智能推荐会发送本次任务与分类条件至 JEV。
- The JEV key is stored in macOS Keychain (`local.gavin.taskrouter.jev`), never in Markdown rules, logs or shared packages. 密钥独立保存在本机钥匙串。
- Personal preferences, active/previous rules and minimal event records stay in `~/Library/Application Support/TaskRouter` and macOS preferences. Event records contain action, rule/model identifiers and outcome, not task text or key. Settings do not synchronize automatically. 事件记录不含任务原文及密钥。
- With user-granted Accessibility permission, the assistant inspects the focused target window to identify menus and an empty composer, then selects and verifies controls and fills the task. It does not export conversation text. No auto-send action is implemented. 辅助功能用于准备任务，发送仍由用户完成。
- Explicit Copy replaces the clipboard with the task. Automatic paste temporarily uses the clipboard and restores it unless another app changes it meanwhile. 手动复制替换剪贴板；自动粘贴尽量恢复原内容。
- No analytics upload, account-balance scraping, browser credential extraction or network-safety scoring is included. 不上传分析埋点，不提取登录凭证。

- V0.4 public updates send unauthenticated GET requests to models.dev and api.frankfurter.dev, containing no task text or keys. Catalog/prices/FX are cached locally in market-state.json with one previous version. 公开更新不发送需求或密钥，仅缓存公开元数据。
