import AppKit
import ApplicationServices

struct ClientInstallation {
    let client: ClientID
    let url: URL
    let bundleID: String
    let version: String
}

enum ClientCatalog {
    static let identifiers: [ClientID: [String]] = [
        .chatgpt: ["com.openai.codex", "com.openai.chat"],
        .claude: ["com.anthropic.claudefordesktop"],
        .trae_cn: ["cn.trae.solo.app"], .workbuddy: ["com.tencent.workbuddy.mac"]]
    static let filenames: [ClientID: [String]] = [
        .chatgpt: ["ChatGPT.app", "Codex.app"], .claude: ["Claude.app"],
        .trae_cn: ["TRAE SOLO CN.app", "TraeWork CN.app"], .workbuddy: ["WorkBuddy.app"]]
    static func discover() -> [ClientID: ClientInstallation] {
        var result: [ClientID: ClientInstallation] = [:]
        for client in ClientID.allCases {
            var urls = identifiers[client]!.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            for base in [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
                urls += filenames[client]!.map { base.appendingPathComponent($0) }
            }
            for url in urls {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, identifiers[client]!.contains(id) else { continue }
                result[client] = ClientInstallation(client: client, url: url, bundleID: id,
                                                   version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知版本")
                break
            }
        }
        return result
    }
}

enum MenuMatcher {
    static func aliases(for name: String) -> [String] {
        var result = [name]
        if name == "GPT-6.1 Sol" { result += ["Sol 6.1", "GPT-6.1-Sol"] }
        if name == "GPT-6 Astra" { result += ["Astra", "GPT-6-Astra"] }
        return result
    }
    static func containsModel(_ text: String, name: String) -> Bool {
        let s = text.replacingOccurrences(of: "‑", with: "-").replacingOccurrences(of: "–", with: "-")
        return aliases(for: name).contains { alias in
            let pattern = "(?<![A-Za-z0-9._:-])" + NSRegularExpression.escapedPattern(for: alias) + "(?![A-Za-z0-9._:-])"
            return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
    static func effortLabels(_ value: Effort) -> [String] {
        switch value { case .low: return ["Low", "Light", "低", "轻"]
        case .medium: return ["Medium", "中", "中等"]
        case .high: return ["High", "高"]
        case .xhigh: return ["Extra high", "Extra", "XHigh", "极高"]
        case .max: return ["Max", "最高"]
        case .client_default: return [] }
    }
    static func containsEffort(_ text: String, value: Effort) -> Bool {
        effortLabels(value).contains { label in
            let pattern = "(?<![A-Za-z\\p{Han}])" + NSRegularExpression.escapedPattern(for: label) + "(?![A-Za-z\\p{Han}])"
            return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        } && !(value == .high && ["Extra", "XHigh", "极高"].contains(where: { text.localizedCaseInsensitiveContains($0) }))
    }
}

struct AXNode {
    let element: AXUIElement
    let role: String
    let label: String
    let value: String
    let ancestors: [AXUIElement]
    let customModel: Bool
}

enum AXAccess {
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    static func string(_ element: AXUIElement, _ key: String) -> String { attribute(element, key) as? String ?? "" }
    static func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    static func label(_ element: AXUIElement) -> String {
        let values = [string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute)]
        return values.filter { !$0.isEmpty }.joined(separator: " ").prefix(300).description
    }
    static func shortLabel(_ element: AXUIElement) -> String {
        let direct = label(element)
        if !direct.isEmpty { return direct }
        return children(element).prefix(8).compactMap { child -> String? in
            let role = string(child, kAXRoleAttribute)
            if role == kAXStaticTextRole { return String(string(child, kAXValueAttribute).prefix(100)) }
            let name = label(child); return name.isEmpty ? nil : name
        }.joined(separator: " ").prefix(300).description
    }
    static func actions(_ element: AXUIElement) -> [String] {
        var values: CFArray?
        if AXUIElementCopyActionNames(element, &values) == .success { return values as? [String] ?? [] }
        return []
    }
    static func press(_ node: AXNode) throws {
        for element in [node.element] + node.ancestors.reversed() {
            let role = string(element, kAXRoleAttribute)
            if role == kAXWindowRole || role == kAXApplicationRole { break }
            let supported = actions(element)
            for action in [kAXPressAction, kAXShowMenuAction] where supported.contains(action) {
                if AXUIElementPerformAction(element, action as CFString) == .success { return }
            }
        }
        throw RouterError("找到控件，但它暂时不接受操作；请在原软件手动完成。")
    }
    static func snapshot(_ application: AXUIElement) -> [AXNode] {
        // Only inspect the focused application window; never export UI text or conversation history.
        let window = attribute(application, kAXFocusedWindowAttribute)
        let root = window.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil } ?? application
        var result: [AXNode] = [], count = 0
        func visit(_ element: AXUIElement, ancestors: [AXUIElement], depth: Int, custom: Bool) {
            guard count < 4500, depth < 38 else { return }; count += 1
            let role = string(element, kAXRoleAttribute)
            let title = shortLabel(element)
            let ownCustom = custom || title == "自定义模型" || title == "Custom models"
            // Editable content is read only when it is the verified task composer.
            let value: String
            if [kAXTextAreaRole, kAXTextFieldRole].contains(role) { value = "" }
            else { value = String(string(element, kAXValueAttribute).prefix(180)) }
            result.append(AXNode(element: element, role: role, label: title, value: value, ancestors: ancestors, customModel: ownCustom))
            // Prune document output and editable fields; no need to inspect their descendants.
            if [kAXTextAreaRole, kAXTextFieldRole, kAXStaticTextRole].contains(role) { return }
            var customSection = ownCustom
            for child in children(element) {
                let name = shortLabel(child)
                if name == "自定义模型" || name == "Custom models" { customSection = true }
                if name == "内置模型" || name == "Built-in models" { customSection = false }
                visit(child, ancestors: ancestors + [element], depth: depth + 1, custom: customSection)
            }
        }
        visit(root, ancestors: [], depth: 0, custom: false)
        // Menus may be siblings of the focused window.
        for child in children(application) where string(child, kAXRoleAttribute) == kAXMenuRole {
            visit(child, ancestors: [], depth: 0, custom: false)
        }
        return result
    }
    static func selected(_ node: AXNode) -> Bool {
        if let b = attribute(node.element, kAXSelectedAttribute) as? Bool, b { return true }
        if let number = attribute(node.element, kAXValueAttribute) as? NSNumber, number.intValue == 1 { return true }
        return false
    }
    static func isActionable(_ node: AXNode) -> Bool {
        let excluded = [kAXWindowRole, kAXApplicationRole, kAXMenuRole, kAXMenuBarRole, kAXGroupRole, kAXScrollAreaRole, kAXTextAreaRole]
        return !excluded.contains(node.role) && actions(node.element).contains(kAXPressAction)
    }
}

struct PreparationResult {
    let ready: Bool
    let message: String
    let stage: String
}

@MainActor final class DesktopPreparer {
    private var application: AXUIElement?
    private var process: NSRunningApplication?
    private var deadline = Date()
    var progress: ((String) -> Void)?
    var stage = "未开始"
    private func step(_ value: String) { stage = value; progress?(value) }
    private func check() throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw RouterError("准备超时，已停止；请在原软件完成当前步骤。") }
        guard let process = process, NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier else {
            throw RouterError("窗口焦点已改变，自动准备已停止。原需求仍在启动器中。")
        }
    }
    private func pause(_ seconds: Double = 0.2) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); try check()
    }
    private func nodes() throws -> [AXNode] {
        try check(); guard let app = application else { throw RouterError("客户端尚未就绪。") }; return AXAccess.snapshot(app)
    }
    private func waitFor(_ predicate: (AXNode) -> Bool, seconds: Double = 3) async throws -> AXNode {
        let until = min(deadline, Date().addingTimeInterval(seconds))
        while Date() < until {
            if let node = try nodes().first(where: predicate) { return node }
            try await pause()
        }
        throw RouterError(tr("没有找到可核验的控件。请在原软件完成“\(stage)”。", "A required control could not be verified. Complete preparation in the destination app."))
    }
    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws {
        try check()
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { throw RouterError("无法发送快捷键。") }
        down.flags = flags; up.flags = flags; down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    private func press(_ node: AXNode) throws { try check(); try AXAccess.press(node) }
    private func launch(_ installation: ClientInstallation) async throws {
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        process = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: installation.url, configuration: config) { app, error in
                if let app = app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: RouterError("无法打开 \(installation.client.name)，请检查安装。")) }
            }
        }
        guard process?.bundleIdentifier == installation.bundleID else { throw RouterError("打开的应用身份不符，已停止。") }
        application = AXUIElementCreateApplication(process!.processIdentifier)
        AXUIElementSetMessagingTimeout(application!, 0.6)
        try await pause(0.35)
    }
    nonisolated private func isModelControl(_ element: AXUIElement) -> Bool {
        let role = AXAccess.string(element, kAXRoleAttribute)
        guard [kAXComboBoxRole, kAXPopUpButtonRole, kAXButtonRole].contains(role) else { return false }
        let name = AXAccess.shortLabel(element) + " " + AXAccess.string(element, kAXValueAttribute)
        return ["Model:", "Select model", "模型", "Sonnet", "Opus", "Astra", "Sol", "GLM", "DeepSeek", "Kimi", "Auto Mode"].contains { name.localizedCaseInsensitiveContains($0) }
    }
    private func composer() async throws -> AXNode {
        let until = min(deadline, Date().addingTimeInterval(3))
        while Date() < until {
            let candidates = try nodes().filter { node in
                guard node.role == kAXTextAreaRole else { return false }
                let text = node.label + " " + AXAccess.string(node.element, "AXPlaceholderValue")
                if ["prompt", "message", "输入你的", "输入消息", "今天帮你", "任务需求"].contains(where: { text.localizedCaseInsensitiveContains($0) }) { return true }
                // An unlabeled text area must share a close container with a model picker.
                // This avoids treating a source-code editor as the chat composer.
                func nearbyModel(_ e: AXUIElement, depth: Int) -> Bool {
                    if isModelControl(e) { return true }
                    guard depth > 0, AXAccess.string(e, kAXRoleAttribute) != kAXTextAreaRole else { return false }
                    return AXAccess.children(e).prefix(30).contains { nearbyModel($0, depth: depth - 1) }
                }
                return node.ancestors.suffix(3).contains { nearbyModel($0, depth: 3) }
            }
            if candidates.count == 1 { return candidates[0] }
            if candidates.count > 1 { throw RouterError("存在多个可能的输入区，已停止自动填写，请在原软件粘贴需求。") }
            try await pause()
        }
        throw RouterError("无法明确识别任务输入区，请在原软件粘贴需求。")
    }
    private func isEmpty(_ node: AXNode) -> Bool {
        AXAccess.string(node.element, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}\u{200B}"))).isEmpty
    }
    private func navigate(client: ClientID, surface: String, installation: ClientInstallation) async throws {
        step("打开新任务")
        if client == .claude {
            let path = surface == "chat" ? "claude.ai/new" : surface == "code" ? "code/new" : "cowork/new"
            let url = URL(string: "claude://" + path)!
            guard let handler = NSWorkspace.shared.urlForApplication(toOpen: url), Bundle(url: handler)?.bundleIdentifier == installation.bundleID else {
                throw RouterError("Claude 应用链接未注册到当前客户端，请先手动打开新任务。")
            }
            guard NSWorkspace.shared.open(url) else { throw RouterError("无法打开 Claude 新任务。") }
            try await pause(0.4)
        } else if client == .chatgpt {
            // Documented shortcuts only. No private endpoints, app injection or hidden credentials.
            try key(surface == "codex" ? 20 : 19, flags: .maskControl); try await pause()
            try key(45, flags: .maskCommand); try await pause(0.3)
        } else {
            let newTask = try await waitFor({ $0.label == "新建任务" || $0.label == "New task" })
            try press(newTask); try await pause(0.3)
            let labels = client == .workbuddy ? (surface == "code" ? ["代码开发", "Code"] : ["日常办公", "Work"]) : (surface == "code" ? ["Code", "代码"] : ["Work", "工作"])
            let mode = try await waitFor({ labels.contains($0.label) && [kAXRadioButtonRole, "AXTab", kAXButtonRole].contains($0.role) })
            if !AXAccess.selected(mode) { try press(mode); try await pause() }
        }
        let box = try await composer()
        guard isEmpty(box) else { throw RouterError("输入框已有草稿，已停止以免覆盖。请新建空任务后重试。") }
    }
    private func modelButton(client: ClientID) async throws -> AXNode {
        try await waitFor({ node in
            if client == .claude { return [kAXPopUpButtonRole, kAXButtonRole, kAXComboBoxRole].contains(node.role) && self.isModelControl(node.element) }
            if client.isChina { return node.role == kAXComboBoxRole && self.isModelControl(node.element) }
            return [kAXPopUpButtonRole, kAXButtonRole, kAXComboBoxRole].contains(node.role) &&
                (["model", "模型", "Power", "Sol", "Astra"].contains(where: { node.label.localizedCaseInsensitiveContains($0) }))
        })
    }
    private func selectModel(_ recommendation: Recommendation) async throws {
        step("选择模型")
        let client = recommendation.model.client
        if client == .chatgpt { try key(46, flags: [.maskControl, .maskShift]) }
        else { try press(try await modelButton(client: client)) }
        try await pause()
        if client == .workbuddy {
            // WorkBuddy's product Max is separate from model effort. Never enable it implicitly.
            let maxCheckbox = try nodes().first { node in
                node.role == kAXCheckBoxRole && (node.label.contains("Max") || node.ancestors.suffix(2).contains(where: { AXAccess.shortLabel($0).contains("Max") }))
            }
            if let toggle = maxCheckbox, AXAccess.selected(toggle) {
                try key(53); throw RouterError("WorkBuddy 当前开启了产品 Max 模式，请先手动确认该设置；启动器没有修改它。")
            }
        }
        let until = Date().addingTimeInterval(2.5)
        var matches: [AXNode] = []
        repeat {
            matches = try nodes().filter { node in
                AXAccess.isActionable(node) && !node.customModel &&
                    ![kAXComboBoxRole, kAXPopUpButtonRole].contains(node.role) &&
                    MenuMatcher.containsModel(node.label, name: recommendation.model.name) &&
                    !["Requires usage credits", "需要使用积分", "需要用量积分"].contains(where: { node.label.localizedCaseInsensitiveContains($0) })
            }
            if !matches.isEmpty { break }; try await pause()
        } while Date() < until
        guard matches.count == 1 else {
            try? key(53)
            throw RouterError(matches.isEmpty ? tr("菜单中没有可明确选择的 \(recommendation.model.name)。请选择可用备用，或在客户端手动设置。", "Cannot identify \(recommendation.model.name) in the menu. Choose an available backup or set it manually.") : "模型菜单存在多个近似选项，需在客户端确认内置/自定义来源。")
        }
        try press(matches[0]); try await pause()
        let button = try await modelButton(client: client)
        guard MenuMatcher.containsModel(button.label + " " + button.value, name: recommendation.model.name) else {
            throw RouterError("模型选择后的回读不一致，已停止。")
        }
    }
    private func selectEffort(_ recommendation: Recommendation) async throws {
        guard recommendation.effort != .client_default else { return }
        step("选择推理档位")
        let client = recommendation.model.client
        if client == .claude {
            try press(try await modelButton(client: client)); try await pause()
            let effort = try await waitFor({ $0.label.hasPrefix("Effort") || $0.label.hasPrefix("推理") || $0.label.hasPrefix("思考强度") })
            try press(effort); try key(124); try await pause()
        } else {
            try key(46, flags: [.maskControl, .maskShift]); try await pause()
        }
        let option = try await waitFor({ AXAccess.isActionable($0) && MenuMatcher.containsEffort($0.label, value: recommendation.effort) })
        try press(option); try await pause()
        // Escape closes any remaining menu; it never submits a task.
        try key(53); try await pause()
        let button = try await modelButton(client: client)
        guard MenuMatcher.containsEffort(button.label + " " + button.value, value: recommendation.effort) else {
            throw RouterError("无法回读确认推理档位，请在原软件手动确认。")
        }
    }
    private func verifySurface(_ recommendation: Recommendation) throws {
        step("核验工作模式")
        let expected = ["chat": ["Chat", "聊天", "对话"], "cowork": ["Cowork", "工作"], "code": ["Code", "代码", "代码开发"], "codex": ["Codex", "代码"], "work": ["Work", "工作"], "office": ["日常办公", "Work"]]
        let labels = expected[recommendation.surface] ?? []; let label = labels.first ?? recommendation.surface
        let matches = try nodes().filter { labels.contains($0.label) && ["AXTab", kAXRadioButtonRole, kAXButtonRole].contains($0.role) }
        guard matches.contains(where: AXAccess.selected) else { throw RouterError(tr("无法核验当前工作模式为 \(label)，请在原软件确认后继续。", "Cannot verify the \(label) context. Confirm it in the destination app.")) }
    }
    private func fill(_ text: String) async throws {
        step("填入需求并核验")
        let box = try await composer(); guard isEmpty(box) else { throw RouterError("输入框已出现内容，已停止，避免覆盖你的输入。") }
        try check()
        let set = AXUIElementSetAttributeValue(box.element, kAXValueAttribute as CFString, text as CFTypeRef)
        if set != .success {
            guard isEmpty(box) else { throw RouterError("输入区状态改变，未继续粘贴。") }
            guard AXUIElementSetAttributeValue(box.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
                  let app = application, let focused = AXAccess.attribute(app, kAXFocusedUIElementAttribute), CFEqual(focused, box.element) else {
                throw RouterError("无法确认输入焦点，已停止粘贴。请在原软件手动粘贴需求。")
            }
            let board = NSPasteboard.general
            let old = board.pasteboardItems?.map { item -> [(NSPasteboard.PasteboardType, Data)] in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
            board.clearContents(); board.setString(text, forType: .string); let ownCount = board.changeCount
            defer {
                if board.changeCount == ownCount {
                    board.clearContents()
                    let items = old.map { pairs -> NSPasteboardItem in let item = NSPasteboardItem(); pairs.forEach { item.setData($0.1, forType: $0.0) }; return item }
                    board.writeObjects(items)
                }
            }
            try key(9, flags: .maskCommand); try await pause(0.35)
        }
        try await pause()
        let readback = AXAccess.string(box.element, kAXValueAttribute).replacingOccurrences(of: "\r\n", with: "\n")
        guard readback == text.replacingOccurrences(of: "\r\n", with: "\n") else {
            throw RouterError("输入内容无法完整回读。请在原软件检查；没有自动发送。")
        }
    }
    func prepare(_ recommendation: Recommendation, text: String, installation: ClientInstallation) async throws -> PreparationResult {
        guard AXIsProcessTrusted() else { throw RouterError("请在设置中开启辅助功能权限；也可以先复制需求并手动打开客户端。") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RouterError("任务为空。") }
        deadline = Date().addingTimeInterval(22)
        step("呼出 " + recommendation.model.client.name)
        try await launch(installation)
        try await navigate(client: recommendation.model.client, surface: recommendation.surface, installation: installation)
        try await selectModel(recommendation)
        try await selectEffort(recommendation)
        try verifySurface(recommendation)
        try await fill(text)
        return PreparationResult(ready: true, message: "已核验并填入需求，请在 \(recommendation.model.client.name) 中发送。" + (recommendation.effort == .client_default ? "原有客户端档位未更改。" : ""), stage: "已准备")
    }
    static func openOnly(_ installation: ClientInstallation) {
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        NSWorkspace.shared.openApplication(at: installation.url, configuration: config, completionHandler: nil)
    }
}
