import Foundation

enum UILanguage: String { case zh, en }
enum UIStrings {
    static var language: UILanguage = .zh
    static func choose(_ zh: String, _ en: String) -> String { language == .zh ? zh : en }
    static var appName: String { choose("AI 选模助手", "AI Model Picker") }
    static func error(_ text: String) -> String {
        guard language == .en else { return text }
        guard text.range(of: "\\p{Han}", options: .regularExpression) != nil else { return text }
        if let message = errors[text] { return message }
        for (prefix, translation) in prefixes where text.hasPrefix(prefix) {
            return translation + String(text.dropFirst(prefix.count))
        }
        // Imported rule names/content are user data. Preserve them rather than guessing a translation.
        return "Please check this detail: " + text
    }
    static let errors: [String: String] = [
        "请先输入任务。": "Describe your task first.",
        "请先确认任务类型和工作方式。": "Confirm the task type and work context first.",
        "这段需求较长，请缩短描述或使用本地选类；原文已保留。": "This task is long. Shorten it or use offline rules; your text is preserved.",
        "规则与需求合计较长，请精简分类规则或使用本地选类。": "The rules and task are too long. Simplify the rules or use offline mode.",
        "规则文件超过 256 KB，请精简后导入。": "The rule file exceeds 256 KB. Simplify it before importing.",
        "规则文件超过 256 KB。": "The rule file exceeds 256 KB.",
        "请使用 UTF-8 编码的 Markdown 文件。": "Use a UTF-8 Markdown file.",
        "元信息缺失、存在未知字段，或规则格式不受支持。": "Metadata is incomplete or the rule format is unsupported.",
        "本地门槛字段不完整或包含未知字段。": "The threshold fields are incomplete or contain unknown fields.",
        "模型目录须为 1–100 项。": "The model catalog must have 1–100 entries.",
        "路由规则中存在无法解析的行。": "A routing-rule line cannot be parsed.",
        "任务类别须为 1–200 类。": "There must be 1–200 task categories.",
        "中国路线与国际路线的类别未全部对应。": "The China and international routes do not cover the same categories.",
        "复杂度需要三个等级。": "Complexity requires three levels.",
        "JEV 响应包含无效数值。": "JEV returned an invalid number.",
        "JEV 响应数值超出范围。": "JEV returned a number outside the expected range.",
        "JEV 返回的候选集合与规则不一致。": "JEV returned options that differ from the rulebook.",
        "JEV 概率分布不完整。": "JEV returned an incomplete probability distribution.",
        "JEV 分类格式错误或返回未知类别。": "JEV returned an invalid or unknown category.",
        "JEV 的选择与其概率分布不一致。": "JEV's choice differs from its probability distribution.",
        "JEV 响应格式不正确。": "JEV returned an invalid response.",
        "JEV 缺少复杂度或澄清结果。": "JEV's response is missing complexity or clarification data.",
        "JEV 复杂度超出规则范围。": "JEV returned a complexity outside the rule range.",
        "无法读取本应用的钥匙串项目，请确认钥匙串已解锁。": "Unable to read this app's keychain item. Unlock your keychain and try again.",
        "请输入有效的单行 API Key。": "Enter a valid single-line API key.",
        "密钥未保存。请检查钥匙串权限。": "The key was not saved. Check keychain access.",
        "无法删除钥匙串中的密钥。": "Unable to remove the keychain item.",
        "请先在设置中保存 JEV API Key。": "Save your JEV API key in Settings first.",
        "不支持的接口。": "Unsupported endpoint.",
        "无法连接 JEV，请检查网络后重试；输入内容已保留。": "Unable to connect to JEV. Check your network; your text is preserved.",
        "JEV 响应过大，已停止处理。": "JEV's response was too large and was not processed.",
        "JEV 暂时无法连接。": "JEV is temporarily unavailable.",
        "已连接，但模型列表响应格式不正确。": "Connected, but the model-list response was invalid.",
        "JEV 密钥无效或已失效，请在设置中更新。": "Your JEV key is invalid or expired. Update it in Settings.",
        "当前 JEV 账户无访问权限，请检查账户。": "This JEV account does not have access.",
        "当前 JEV 型号或接口不可用，请检查规则版本。": "The JEV model or endpoint is unavailable. Check the rule version.",
        "JEV 未接受请求，可能是规则、输入长度或型号不匹配；可先使用本地选类。": "JEV did not accept the request. Check the rules, task length or model; offline mode is available.",
        "JEV 请求较多或账户额度受限，请稍后重试。": "JEV is rate-limited or your account has reached its allowance. Try later.",
        "JEV 暂时繁忙，请稍后重试。": "JEV is busy. Try again later.",
        "JEV 返回了重定向，已停止发送鉴权信息。": "JEV returned a redirect. Authentication was not forwarded.",
        "JEV 返回了无法识别的网络响应。": "JEV returned an unrecognized network response.",
        "找到控件，但它暂时不接受操作；请在原软件手动完成。": "The control cannot be operated. Complete this step in the destination app.",
        "准备超时，已停止；请在原软件完成当前步骤。": "Preparation timed out. Complete the current step in the destination app.",
        "窗口焦点已改变，自动准备已停止。原需求仍在启动器中。": "The active window changed. Preparation stopped; your task is preserved.",
        "客户端尚未就绪。": "The destination app is not ready.",
        "无法发送快捷键。": "Unable to send the shortcut.",
        "打开的应用身份不符，已停止。": "The opened app has a different identity. Preparation stopped.",
        "存在多个可能的输入区，已停止自动填写，请在原软件粘贴需求。": "More than one input area was found. Paste your task in the destination app.",
        "无法明确识别任务输入区，请在原软件粘贴需求。": "The task input could not be identified. Paste your task in the destination app.",
        "Claude 应用链接未注册到当前客户端，请先手动打开新任务。": "The Claude link is not registered to this app. Open a new task manually.",
        "无法打开 Claude 新任务。": "Unable to open a new Claude task.",
        "输入框已有草稿，已停止以免覆盖。请新建空任务后重试。": "The input already contains a draft. Open an empty task and try again.",
        "模型菜单存在多个近似选项，需在客户端确认内置/自定义来源。": "Similar model options were found. Confirm the built-in or custom source in the app.",
        "模型选择后的回读不一致，已停止。": "The selected model could not be verified. Preparation stopped.",
        "无法回读确认推理档位，请在原软件手动确认。": "The reasoning level could not be verified. Confirm it in the destination app.",
        "输入框已出现内容，已停止，避免覆盖你的输入。": "The input changed. Preparation stopped to preserve your text.",
        "输入区状态改变，未继续粘贴。": "The input changed. Your task was not pasted.",
        "无法确认输入焦点，已停止粘贴。请在原软件手动粘贴需求。": "Input focus could not be verified. Paste your task manually.",
        "输入内容无法完整回读。请在原软件检查；没有自动发送。": "The full input could not be verified. Check it in the destination app; it was not sent.",
        "请在设置中开启辅助功能权限；也可以先复制需求并手动打开客户端。": "Enable Accessibility access in Settings, or copy your task and open the app manually.",
        "任务为空。": "The task is empty.",
        "WorkBuddy 当前开启了产品 Max 模式，请先手动确认该设置；启动器没有修改它。": "WorkBuddy's product Max mode is enabled. Confirm that setting manually; it was not changed."
    ]
    static let prefixes: [(String,String)] = [
        ("缺少章节：", "Missing section: "), ("字段重复：", "Duplicate field: "),
        ("表头不正确，需要：", "Expected table columns: "), ("门槛须在 0 到 1 之间：", "Threshold must be between 0 and 1: "),
        ("规则字段缺失或未知：", "Missing or unknown rule field: "), ("规则字段未知、重复或过长：", "Unknown, duplicate or long field: "),
        ("任务标题格式或ID不合法/重复：", "Invalid or duplicate task title/ID: "),
        ("中国路线存在重复、未知引用或范围错误：", "Invalid China route: "),
        ("国际路线引用了未知或中国客户端模型：", "Invalid international model: "),
        ("规则需要三个合法档位（轻量、常规、复杂）：", "Three effort levels are required: "),
        ("模型重复、名称过长或应用/模式非法：", "Invalid model, application or surface: "),
        ("离线规则不合法：", "Invalid offline rule: "),
        ("无法核验当前工作模式为 ", "Cannot verify the working mode: "),
        ("菜单中没有可明确选择的 ", "Cannot identify this model in the menu: "),
        ("没有找到可核验的控件。", "The control could not be verified. ")
    ]
}
func tr(_ zh: String, _ en: String) -> String { UIStrings.choose(zh, en) }
