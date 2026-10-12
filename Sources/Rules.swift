import Foundation
import CryptoKit

struct RouterError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { UIStrings.error(message) }
}

enum ClientID: String, CaseIterable {
    case chatgpt, claude, trae_cn, workbuddy
    var name: String {
        switch self { case .chatgpt: return "ChatGPT"; case .claude: return "Claude"
        case .trae_cn: return tr("TRAE 国内版", "TRAE CN"); case .workbuddy: return "WorkBuddy" }
    }
    var isChina: Bool { self == .trae_cn || self == .workbuddy }
    var surfaces: Set<String> {
        switch self { case .chatgpt: return ["work", "codex"]
        case .claude: return ["chat", "cowork", "code"]
        case .trae_cn: return ["work", "code"]
        case .workbuddy: return ["office", "code"] }
    }
    func surface(for need: String) -> String {
        switch self {
        case .chatgpt: return need == "code" ? "codex" : "work"
        case .claude: return need == "code" ? "code" : need == "discussion" ? "chat" : "cowork"
        case .trae_cn: return need == "code" ? "code" : "work"
        case .workbuddy: return need == "code" ? "code" : "office"
        }
    }
}

enum Effort: String, CaseIterable {
    case low, medium, high, xhigh, max, client_default
    static func parse(_ value: String) -> Effort? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if ["Extra", "Extra high", "XHigh", "极高"].contains(text) { return .xhigh }
        return Effort(rawValue: text.lowercased())
    }
    var title: String {
        switch self { case .low: return tr("低", "Low"); case .medium: return tr("中", "Medium")
        case .high: return tr("高", "High"); case .xhigh: return tr("极高", "Extra / XHigh")
        case .max: return tr("最高", "Max"); case .client_default: return tr("客户端设置", "App setting") }
    }
}

struct ModelSpec: Equatable {
    let key: String
    let client: ClientID
    let name: String
    let surfaces: Set<String>
    let efforts: [Effort]
}
struct RuleTarget { let model: String; let efforts: [Effort] }
struct TaskRule {
    let id: String; let name: String; let include: String; let exclude: String
    let example: String; let reason: String; let primary: RuleTarget; let backup: RuleTarget
}
struct ChinaRule { let primary: String; let backup: String; let reason: String }
struct OfflineRule: Equatable {
    let id: String; let nameEN: String; let reasonEN: String
    let any: [String]; let all: [String]; let exclusions: [String]
    let surface: String; let complexity: Int; let priority: Int
    let demanding: [String]; let light: [String]
}

struct RuleBook {
    let markdown: String
    let version: String
    let classifier: String
    let fingerprint: String
    let models: [String: ModelSpec]
    let tasks: [TaskRule]
    let china: [String: ChinaRule]
    let thresholds: [String: Double]
    let classificationInstructions: String
    let surfaceInstructions: String
    let complexityCriteria: [String]
    let clarificationInstructions: String
    let offline: [String: OfflineRule]
    var supportsOfflineMatching: Bool { !offline.isEmpty }
    func name(for id: String) -> String {
        let original = tasks.first(where: { $0.id == id })?.name ?? id
        return UIStrings.language == .en ? (offline[id]?.nameEN ?? original) : original
    }
    func reason(for id: String, original: String) -> String { UIStrings.language == .en ? (offline[id]?.reasonEN ?? original) : original }

    func request(for task: String) throws -> [String: Any] {
        guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RouterError("请先输入任务。") }
        // Conservative local size guard, not a claim to reproduce the provider's tokenizer.
        guard task.utf8.count <= 12_000 else { throw RouterError("这段需求较长，请缩短描述或使用本地选类；原文已保留。") }
        var criteria: [String: Any] = [:]
        for rule in tasks {
            criteria[rule.id] = ["name": rule.name, "include": rule.include, "exclude": rule.exclude, "example": rule.example]
        }
        criteria["needs_choice"] = "目标超出规则，多个目标无法确定主次，或缺少决定任务类别的必要信息。"
        let questions: [String: Any] = [
            "task_type": ["type": "choice", "instructions": classificationInstructions, "criteria": criteria] as [String: Any],
            "surface_need": ["type": "choice", "instructions": surfaceInstructions, "criteria": [
                "discussion": "只讨论、解释或设计方案，不要求实际修改代码、生成文件或操作系统。",
                "files": "需要处理或生成文件、研究检索、使用浏览器或业务工具执行任务。",
                "code": "明确要求在真实代码项目修改文件、运行程序或测试。",
                "unknown": "缺少会改变执行环境的信息。"]] as [String: Any],
            "complexity": ["type": "score", "instructions": "评价任务所需判断与执行复杂度，不以文本长短、用户身份或品牌作为难度。", "criteria": complexityCriteria] as [String: Any],
            "needs_clarification": ["type": "noul", "instructions": clarificationInstructions,
                                    "criteria": ["true": "缺少会改变路由的必要信息。", "false": "目标足以分类，即使尚未提供实际附件。"]] as [String: Any]
        ]
        let payload: [String: Any] = ["model": classifier, "state": ["task": task], "questions": questions]
        guard try JSONSerialization.data(withJSONObject: payload).count <= 48_000 else {
            throw RouterError("规则与需求合计较长，请精简分类规则或使用本地选类。")
        }
        return payload
    }

    func changes(from old: RuleBook) -> String {
        let oldIDs = Set(old.tasks.map(\.id)), newIDs = Set(tasks.map(\.id))
        let added = newIDs.subtracting(oldIDs).count, removed = oldIDs.subtracting(newIDs).count
        let changed = tasks.filter { rule in
            guard let previous = old.tasks.first(where: { $0.id == rule.id }) else { return false }
            return rule.primary.model != previous.primary.model || rule.backup.model != previous.backup.model ||
                rule.primary.efforts != previous.primary.efforts || rule.backup.efforts != previous.backup.efforts ||
                offline[rule.id] != old.offline[rule.id] || rule.include != previous.include || rule.exclude != previous.exclude || rule.reason != previous.reason ||
                china[rule.id]?.primary != old.china[rule.id]?.primary || china[rule.id]?.backup != old.china[rule.id]?.backup
        }
        var lines = ["\(old.version) → \(version)", tr("新增 \(added) 类，删除 \(removed) 类，任务规则变化 \(changed.count) 类。", "Added: \(added); removed: \(removed); changed routes: \(changed.count).")]
        let addedModels = Set(models.keys).subtracting(old.models.keys).count
        let removedModels = Set(old.models.keys).subtracting(models.keys).count
        let changedModels = models.keys.filter { old.models[$0] != nil && models[$0] != old.models[$0] }.count
        lines.append(tr("模型目录：新增 \(addedModels)，删除 \(removedModels)，修改 \(changedModels)。", "Models: \(addedModels) added, \(removedModels) removed, \(changedModels) changed."))
        lines += changed.prefix(16).map { "• \(name(for: $0.id))" }
        if classifier != old.classifier { lines.append(tr("分类器：", "Classifier: ") + "\(old.classifier) → \(classifier)") }
        if fingerprint != old.fingerprint && version == old.version { lines.append(tr("版本号相同但内容不同，建议修改规则版本号。", "The version is unchanged but the content differs. Update the version label.")) }
        if supportsOfflineMatching != old.supportsOfflineMatching { lines.append(tr("离线匹配条件已变化。", "Offline matching support has changed.")) }
        lines.append(tr("应用后可回退。模型可用性仍以每台电脑的客户端为准。", "You can roll back after applying. Available models depend on each computer and account."))
        return lines.joined(separator: "\n")
    }
}

enum MarkdownRules {
    static let aliases: [String: String] = [
        "Metadata":"元信息", "JEV strategy":"JEV分类策略", "Classification":"分类说明", "Surface":"模式说明",
        "Complexity":"复杂度", "Clarification":"澄清说明", "Thresholds":"本地门槛", "Models":"模型目录",
        "International routes":"路由规则", "China routes":"中国客户端路由", "Offline matching":"离线匹配",
        "Field":"字段", "Value":"值", "Format":"格式", "Version":"规则版本", "Classifier":"分类器型号",
        "Scope":"适用范围", "Status":"状态", "Evidence":"依据", "Model key":"模型键", "App":"应用",
        "Display name":"显示名称", "Surfaces":"候选模式", "Efforts":"档位", "Task ID":"任务ID",
        "Primary":"首选", "Backup":"备用", "Effort":"档位", "Reason":"理由", "Include":"适用", "Exclude":"排除",
        "Primary efforts":"首选档位", "Backup efforts":"备用档位", "Example":"示例",
        "Category confidence":"分类最低置信度", "Category margin":"分类前两项最低差值", "Complexity confidence":"复杂度最低置信度",
        "Surface confidence":"模式最低置信度", "Clarification threshold":"需要澄清阈值",
        "English name":"英文名称", "Match any":"命中词", "Match all":"同时命中", "Exclude any":"排除词",
        "Default surface":"默认方式", "Default complexity":"默认复杂度", "Priority":"优先级",
        "Demanding terms":"升档词", "Light terms":"降档词", "English reason":"英文理由"
    ]
    static func canonical(_ raw: String) -> String {
        raw.components(separatedBy: "\n").map { line in
            if line.hasPrefix("#") {
                let hashes = line.prefix(while: { $0 == "#" })
                let title = String(line.dropFirst(hashes.count)).trimmingCharacters(in: .whitespaces)
                return String(hashes) + " " + (aliases[title] ?? title)
            }
            if line.hasPrefix("|") {
                let parts = line.components(separatedBy: "|").map { value -> String in
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    return aliases[trimmed].map { " " + $0 + " " } ?? value
                }
                return parts.joined(separator: "|")
            }
            if line.hasPrefix("- "), let split = line.range(of: ": ") {
                let key = String(line.dropFirst(2).prefix(upTo: split.lowerBound))
                if let translated = aliases[key] { return "- " + translated + "：" + String(line[split.upperBound...]) }
            }
            return line
        }.joined(separator: "\n")
    }
    static func section(_ text: String, _ title: String, level: Int = 2) throws -> String {
        let marker = String(repeating: "#", count: level) + " " + title
        let lines = text.components(separatedBy: "\n")
        guard let begin = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == marker }) else {
            throw RouterError("缺少章节：\(title)")
        }
        var result: [String] = []
        for line in lines.dropFirst(begin + 1) {
            let hashes = line.prefix(while: { $0 == "#" }).count
            if hashes > 0 && hashes <= level && line.dropFirst(hashes).hasPrefix(" ") { break }
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func table(_ text: String, headers: [String]) throws -> [[String: String]] {
        let lines = text.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
        func cells(_ line: String) -> [String] {
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("|") { s.removeFirst() }; if s.hasSuffix("|") { s.removeLast() }
            return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        guard lines.count >= 2, cells(lines[0]) == headers,
              cells(lines[1]).allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) else {
            throw RouterError("表头不正确，需要：\(headers.joined(separator: "、"))")
        }
        return try lines.dropFirst(2).map { line in
            let values = cells(line)
            guard values.count == headers.count, values.allSatisfy({ !$0.isEmpty }) else { throw RouterError("表格缺项或列数不符。") }
            return Dictionary(uniqueKeysWithValues: zip(headers, values))
        }
    }
    static func keyValues(_ text: String) throws -> [String: String] {
        var result: [String: String] = [:]
        for row in try table(text, headers: ["字段", "值"]) {
            let key = row["字段"]!
            guard result[key] == nil else { throw RouterError("字段重复：\(key)") }
            result[key] = row["值"]!
        }
        return result
    }
    static func list(_ value: String) -> [String] {
        value.replacingOccurrences(of: "，", with: ",").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    static func read(_ url: URL) throws -> RuleBook {
        let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= 262_144 else { throw RouterError("规则文件超过 256 KB，请精简后导入。") }
        let data = try Data(contentsOf: url)
        guard let raw = String(data: data, encoding: .utf8) else { throw RouterError("请使用 UTF-8 编码的 Markdown 文件。") }
        return try parse(raw)
    }
    static func parse(_ raw: String) throws -> RuleBook {
        guard raw.utf8.count <= 262_144 else { throw RouterError("规则文件超过 256 KB。") }
        let original = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")).precomposedStringWithCanonicalMapping
        let text = canonical(original)
        let meta = try keyValues(section(text, "元信息"))
        let allowedMeta: Set<String> = ["格式", "规则版本", "分类器型号", "适用范围", "状态", "依据"]
        guard Set(meta.keys) == allowedMeta, ["task-router-markdown/1", "task-router-markdown/2"].contains(meta["格式"] ?? ""),
              let version = meta["规则版本"], version.count <= 80,
              let classifier = meta["分类器型号"], classifier.range(of: "^jev-[a-zA-Z0-9.\\-]+$", options: .regularExpression) != nil else {
            throw RouterError("元信息缺失、存在未知字段，或规则格式不受支持。")
        }
        let limits = try keyValues(section(text, "本地门槛"))
        let expected: Set<String> = ["分类最低置信度", "分类前两项最低差值", "复杂度最低置信度", "模式最低置信度", "需要澄清阈值"]
        guard Set(limits.keys) == expected else { throw RouterError("本地门槛字段不完整或包含未知字段。") }
        var thresholds: [String: Double] = [:]
        for (key, value) in limits {
            guard let number = Double(value), number.isFinite, (0...1).contains(number) else { throw RouterError("门槛须在 0 到 1 之间：\(key)") }
            thresholds[key] = number
        }
        var models: [String: ModelSpec] = [:]
        for row in try table(section(text, "模型目录"), headers: ["模型键", "应用", "显示名称", "候选模式", "档位"]) {
            let key = row["模型键"]!, modes = Set(list(row["候选模式"]!)), values = list(row["档位"]!)
            guard key.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil, models[key] == nil,
                  let client = ClientID(rawValue: row["应用"]!), modes.isSubset(of: client.surfaces), !modes.isEmpty,
                  row["显示名称"]!.count <= 100 else { throw RouterError("模型重复、名称过长或应用/模式非法：\(key)") }
            let efforts = values.compactMap(Effort.parse)
            guard efforts.count == values.count, Set(efforts).count == efforts.count,
                  client.isChina ? efforts == [.client_default] : !efforts.contains(.client_default) else {
                throw RouterError("模型档位不合法：\(key)。国产模型首版只接受 client_default。")
            }
            models[key] = ModelSpec(key: key, client: client, name: row["显示名称"]!, surfaces: modes, efforts: efforts)
        }
        guard !models.isEmpty, models.count <= 100 else { throw RouterError("模型目录须为 1–100 项。") }
        let block = try section(text, "路由规则")
        let required: Set<String> = ["适用", "排除", "首选", "备用", "首选档位", "备用档位", "理由", "示例"]
        var tasks: [TaskRule] = [], id: String?, name = "", fields: [String: String] = [:]
        func commit() throws {
            guard let rid = id else { return }
            guard Set(fields.keys) == required else { throw RouterError("规则字段缺失或未知：\(rid)") }
            func target(_ label: String) throws -> RuleTarget {
                let key = fields[label]!, values = list(fields[label + "档位"]!)
                guard let model = models[key], !model.client.isChina else { throw RouterError("国际路线引用了未知或中国客户端模型：\(key)") }
                let levels = values.compactMap(Effort.parse)
                guard values.count == 3, levels.count == 3, Set(levels).isSubset(of: Set(model.efforts)) else {
                    throw RouterError("规则需要三个合法档位（轻量、常规、复杂）：\(rid)")
                }
                return RuleTarget(model: key, efforts: levels)
            }
            tasks.append(TaskRule(id: rid, name: name, include: fields["适用"]!, exclude: fields["排除"]!,
                                  example: fields["示例"]!, reason: fields["理由"]!, primary: try target("首选"), backup: try target("备用")))
        }
        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix("### ") {
                try commit()
                let pair = String(line.dropFirst(4)).components(separatedBy: "｜")
                guard pair.count == 2, pair[0].range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil,
                      !tasks.contains(where: { $0.id == pair[0] }), pair[0] != "needs_choice", !pair[1].isEmpty else {
                    throw RouterError("任务标题格式或ID不合法/重复：\(line)")
                }
                id = pair[0]; name = pair[1]; fields = [:]
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                guard id != nil, line.hasPrefix("- "), let split = line.range(of: "：") else { throw RouterError("路由规则中存在无法解析的行。") }
                let key = String(line[line.index(line.startIndex, offsetBy: 2)..<split.lowerBound])
                let value = String(line[split.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard required.contains(key), fields[key] == nil, !value.isEmpty, value.count <= 1800 else { throw RouterError("规则字段未知、重复或过长：\(key)") }
                fields[key] = value
            }
        }
        try commit()
        guard (1...200).contains(tasks.count) else { throw RouterError("任务类别须为 1–200 类。") }
        var china: [String: ChinaRule] = [:]
        for row in try table(section(text, "中国客户端路由"), headers: ["任务ID", "首选", "备用", "档位", "理由"]) {
            let rid = row["任务ID"]!, first = row["首选"]!, second = row["备用"]!
            guard tasks.contains(where: { $0.id == rid }), china[rid] == nil, row["档位"] == "client_default",
                  models[first]?.client.isChina == true, models[second]?.client.isChina == true else { throw RouterError("中国路线存在重复、未知引用或范围错误：\(rid)") }
            china[rid] = ChinaRule(primary: first, backup: second, reason: row["理由"]!)
        }
        guard china.count == tasks.count else { throw RouterError("中国路线与国际路线的类别未全部对应。") }
        let strategy = try section(text, "JEV分类策略")
        let levels = try section(strategy, "复杂度", level: 3).components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.map { String($0.dropFirst(2)) }
        guard levels.count == 3 else { throw RouterError("复杂度需要三个等级。") }
        var offline: [String: OfflineRule] = [:]
        if meta["格式"] == "task-router-markdown/2" {
            let headers = ["任务ID", "英文名称", "命中词", "同时命中", "排除词", "默认方式", "默认复杂度", "优先级", "升档词", "降档词", "英文理由"]
            func terms(_ value: String) throws -> [String] {
                if value == "-" { return [] }
                let result = list(value)
                guard result.count <= 40, result.allSatisfy({ !$0.isEmpty && $0.count <= 80 }) else { throw RouterError("离线规则不合法：关键词过多或过长。") }
                return result
            }
            for row in try table(section(text, "离线匹配"), headers: headers) {
                let rid = row["任务ID"]!
                guard tasks.contains(where: { $0.id == rid }), offline[rid] == nil,
                      ["discussion", "files", "code"].contains(row["默认方式"]!),
                      let complexity = Int(row["默认复杂度"]!), (0...2).contains(complexity),
                      let priority = Int(row["优先级"]!), (0...100).contains(priority), row["英文名称"]!.count <= 120,
                      row["英文理由"]!.count <= 600 else { throw RouterError("离线规则不合法：" + rid) }
                let any = try terms(row["命中词"]!), all = try terms(row["同时命中"]!)
                guard !any.isEmpty || !all.isEmpty else { throw RouterError("离线规则不合法：至少需要一个命中条件。") }
                offline[rid] = OfflineRule(id: rid, nameEN: row["英文名称"]!, reasonEN: row["英文理由"]!, any: any, all: all,
                    exclusions: try terms(row["排除词"]!), surface: row["默认方式"]!, complexity: complexity, priority: priority,
                    demanding: try terms(row["升档词"]!), light: try terms(row["降档词"]!))
            }
            guard offline.count == tasks.count else { throw RouterError("离线规则不合法：类别覆盖不完整。") }
        }
        return RuleBook(markdown: original, version: version, classifier: classifier,
                        fingerprint: SHA256.hash(data: Data(original.utf8)).map { String(format: "%02x", $0) }.joined(),
                        models: models, tasks: tasks, china: china, thresholds: thresholds,
                        classificationInstructions: try section(strategy, "分类说明", level: 3),
                        surfaceInstructions: try section(strategy, "模式说明", level: 3), complexityCriteria: levels,
                        clarificationInstructions: try section(strategy, "澄清说明", level: 3), offline: offline)
    }
}
