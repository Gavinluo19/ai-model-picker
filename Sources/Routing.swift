import Foundation
import CoreFoundation

struct Classification {
    let category: String
    let surface: String
    let complexity: Int
    let classifierModel: String
    let clarification: String?
    let confidence: Double?
    let source: String
}

enum ResponseValidator {
    static func number(_ value: Any?) throws -> Double {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { throw RouterError("JEV 响应包含无效数值。") }
        return value.doubleValue
    }
    static func unit(_ value: Any?) throws -> Double {
        let result = try number(value)
        guard (0...1).contains(result) else { throw RouterError("JEV 响应数值超出范围。") }
        return result
    }
    static func distribution(_ value: Any?, options: Set<String>) throws -> [String: Double] {
        guard let dict = value as? [String: Any], Set(dict.keys) == options else { throw RouterError("JEV 返回的候选集合与规则不一致。") }
        var result: [String: Double] = [:]
        for (key, val) in dict { result[key] = try unit(val) }
        guard abs(result.values.reduce(0, +) - 1) <= 0.015 else { throw RouterError("JEV 概率分布不完整。") }
        return result
    }
    static func choice(_ raw: Any?, options: Set<String>) throws -> (String, Double, [String: Double]) {
        guard let answer = raw as? [String: Any], answer["type"] as? String == "choice",
              let selected = answer["choice"] as? String, options.contains(selected) else { throw RouterError("JEV 分类格式错误或返回未知类别。") }
        let confidence = try unit(answer["confidence"]), probabilities = try distribution(answer["probabilities"], options: options)
        guard (probabilities[selected] ?? 0) + 0.001 >= (probabilities.values.max() ?? 1) else { throw RouterError("JEV 的选择与其概率分布不一致。") }
        return (selected, confidence, probabilities)
    }
    static func parse(_ data: Data, book: RuleBook) throws -> Classification {
        guard data.count <= 1_048_576, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? String, model.hasPrefix("jev-"),
              let answers = root["answers"] as? [String: Any] else { throw RouterError("JEV 响应格式不正确。") }
        let category = try choice(answers["task_type"], options: Set(book.tasks.map(\.id) + ["needs_choice"]))
        let surface = try choice(answers["surface_need"], options: ["discussion", "files", "code", "unknown"])
        guard let score = answers["complexity"] as? [String: Any], score["type"] as? String == "score",
              let noul = answers["needs_clarification"] as? [String: Any], noul["type"] as? String == "noul" else { throw RouterError("JEV 缺少复杂度或澄清结果。") }
        let average = try number(score["score"])
        guard (0...2).contains(average) else { throw RouterError("JEV 复杂度超出规则范围。") }
        let scores = try distribution(score["probabilities"], options: ["0", "1", "2"])
        let scoreConfidence = try unit(score["confidence"]), clarification = try unit(noul["noul"])
        let ranked = scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        let complexity = scoreConfidence >= book.thresholds["复杂度最低置信度"]! && ranked[0].value > ranked[1].value
            ? Int(ranked[0].key)! : 1
        let leaders = category.2.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        var reason: String?
        if category.0 == "needs_choice" || category.1 < book.thresholds["分类最低置信度"]! || leaders[0].value - leaders[1].value < book.thresholds["分类前两项最低差值"]! || clarification >= book.thresholds["需要澄清阈值"]! {
            let names = leaders.prefix(2).compactMap { item in book.tasks.first(where: { $0.id == item.key })?.name }
            reason = names.count == 2 ? "这次主要是“\(names[0])”还是“\(names[1])”？请在下方选定类型。" : "这次最主要的交付目标是什么？请在下方选定任务类型。"
        } else if surface.0 == "unknown" || surface.1 < book.thresholds["模式最低置信度"]! {
            reason = "这次只需要讨论，还是要处理文件或修改代码？请在下方选择工作方式。"
        }
        let codingIDs: Set<String> = ["coding", "debugging", "frontend", "testing_review"]
        if codingIDs.contains(category.0) && surface.0 != "code" { reason = "这次是否要实际修改代码或运行测试？请核对下方的工作方式。" }
        return Classification(category: category.0, surface: surface.0, complexity: complexity,
                              classifierModel: model, clarification: reason, confidence: category.1, source: "jev")
    }
}

struct Recommendation {
    let category: String
    let model: ModelSpec
    var effort: Effort
    var surface: String
    let reason: String
    let ruleVersion: String
    var summary: String { "\(model.client.name) · \(model.name) · \(effort.title)" }
}

enum RoutingEngine {
    static func recommendations(book: RuleBook, classification: Classification, scope: String,
                                enabled: Set<ClientID>, unavailableModels: Set<String> = []) throws -> [Recommendation] {
        guard classification.clarification == nil, let rule = book.tasks.first(where: { $0.id == classification.category }),
              ["discussion", "files", "code"].contains(classification.surface), (0...2).contains(classification.complexity),
              ["all", "international", "china"].contains(scope) else { throw RouterError("请先确认任务类型和工作方式。") }
        var candidates: [(String, Effort, String)] = []
        if scope != "china" {
            candidates += [rule.primary, rule.backup].map { ($0.model, $0.efforts[classification.complexity], rule.reason) }
        }
        if scope != "international", let cn = book.china[rule.id] {
            candidates += [(cn.primary, .client_default, cn.reason), (cn.backup, .client_default, cn.reason)]
        }
        var seen: Set<String> = []
        return candidates.compactMap { key, effort, reason in
            guard !seen.contains(key), let model = book.models[key], enabled.contains(model.client),
                  !unavailableModels.contains(key), model.efforts.contains(effort) else { return nil }
            let surface = model.client.surface(for: classification.surface)
            guard model.surfaces.contains(surface) else { return nil }
            seen.insert(key)
            return Recommendation(category: book.name(for: rule.id), model: model, effort: effort, surface: surface,
                reason: book.reason(for: rule.id, original: reason), ruleVersion: book.version)
        }
    }
}

final class RuleStore {
    let directory: URL
    let bundled: URL
    var currentURL: URL { directory.appendingPathComponent("current.md") }
    var previousURL: URL { directory.appendingPathComponent("previous.md") }
    init(directory: URL, bundled: URL) throws {
        self.directory = directory; self.bundled = bundled
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func load() throws -> RuleBook {
        try MarkdownRules.read(FileManager.default.fileExists(atPath: currentURL.path) ? currentURL : bundled)
    }
    func activate(_ book: RuleBook) throws {
        _ = try MarkdownRules.parse(book.markdown)
        let old = try load()
        try Data(old.markdown.utf8).write(to: previousURL, options: .atomic)
        try Data(book.markdown.utf8).write(to: currentURL, options: .atomic)
    }
    func rollback() throws -> RuleBook {
        let old = try MarkdownRules.read(previousURL)
        try activate(old)
        return old
    }
}
