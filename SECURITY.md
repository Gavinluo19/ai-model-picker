# Security / 安全说明

V0.4 is experimental. Accessibility preparation can manipulate destination-app controls, so grant it only after understanding the source and intended behavior. The software is designed to avoid replacing nonempty drafts or sending tasks automatically; current client versions must still be verified.

JEV mode sends the current task/classification conditions to the configured fixed service; offline mode does not. Public model/FX updates send no task or key. Keys remain in macOS Keychain. See PRIVACY.md.

Do not upload credentials, transcripts, customer data or account screenshots to public issues. If you find a sensitive vulnerability, use the repository's **Security → Report a vulnerability** private reporting entry. If that entry is unavailable, request a private contact method with a non-sensitive issue; do not post exploit details or secrets publicly.

The downloaded alpha binary is ad hoc signed and not notarized. If blocked by macOS, build locally or wait for a signed distribution. Do not disable system protections or strip quarantine to make a release appear trusted.

There is no promised response SLA, no account-safety certification, and no mechanism to bypass vendor terms or subscription limits.

中文：不要在公开 Issue 上传密钥、聊天、客户资料或账户截图。敏感漏洞先用 GitHub 私密报告入口；没有入口时只请求私下联系方式，不公开敏感细节。未公证包若被拦截，使用本地构建或等待正式分发，不关闭安全保护。
