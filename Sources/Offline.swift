import Foundation

struct OfflineOutcome {
    let classification: Classification?
    let candidates: [String]
    let matchedTerms: [String]
    let message: String?
}

enum OfflineEngine {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "'").lowercased()
    }
    static func matches(_ term: String, in text: String, respectNegation: Bool = true) -> Bool {
        let needle = normalized(term), value = normalized(text)
        guard !needle.isEmpty else { return false }
        let latin = needle.unicodeScalars.allSatisfy { $0.value < 128 }
        var pattern = NSRegularExpression.escapedPattern(for: needle)
        pattern = pattern.replacingOccurrences(of: " ", with: "\\s+")
        if latin { pattern = "(?<![a-z0-9])" + pattern + "(?![a-z0-9])" }
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = value as NSString
        for match in expression.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            if !respectNegation { return true }
            let start = max(0, match.range.location - 36)
            var prefix = ns.substring(with: NSRange(location: start, length: match.range.location - start))
            if let split = prefix.range(of: "[，,。.;；:\\n]", options: [.regularExpression, .backwards]) { prefix = String(prefix[split.upperBound...]) }
            let englishNegation = "(?:do not|don't|no|not|without)(?:\\s+[a-z]+){0,2}\\s*$"
            let chineseNegation = "(?:不要|无需|不需要|不用|不做|不写|不进行)[^，。；\\n]{0,8}$"
            if prefix.range(of: englishNegation, options: .regularExpression) != nil || prefix.range(of: chineseNegation, options: .regularExpression) != nil { continue }
            return true
        }
        return false
    }
    static func classify(_ task: String, book: RuleBook) -> OfflineOutcome {
        guard book.supportsOfflineMatching else {
            return OfflineOutcome(classification: nil, candidates: [], matchedTerms: [], message: tr("当前旧规则没有离线匹配条件，请选任务类型或导入新版规则。", "This older rulebook has no offline matching conditions. Choose a category or import newer rules."))
        }
        guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return OfflineOutcome(classification: nil, candidates: [], matchedTerms: [], message: tr("请先描述任务。", "Describe your task first."))
        }
        guard task.utf8.count <= 48_000 else {
            return OfflineOutcome(classification: nil, candidates: [], matchedTerms: [], message: tr("这段需求较长，请选择主要任务类型。", "This task is long. Choose its main category."))
        }
        // Purpose clauses describe downstream use, not the requested action.
        // Match only the requested work, keeping independent compound goals intact.
        let matchText = task.replacingOccurrences(of: "(?:用于|用来|以便)(?:我)?(?:开发产品|产品开发|产品设计)", with: "", options: .regularExpression)
        var ranked: [(OfflineRule, [String], Double)] = []
        for rule in book.offline.values {
            if rule.exclusions.contains(where: { matches($0, in: task, respectNegation: false) }) { continue }
            guard rule.all.allSatisfy({ matches($0, in: matchText) }) else { continue }
            let hit = rule.any.filter { matches($0, in: matchText) }
            guard !hit.isEmpty || !rule.all.isEmpty else { continue }
            let effectiveHit = rule.id == "architecture" && matches("竞品网站", in: matchText) && matchText.range(of: "(?:形成|整理|产出)[^，。；]{0,8}产品需求", options: .regularExpression) != nil
                ? hit.filter { $0 != "产品需求" && $0 != "product requirements" } : hit
            guard !effectiveHit.isEmpty || !rule.all.isEmpty else { continue }
            let terms = Array(Set(effectiveHit + rule.all)).sorted()
            let score = terms.reduce(0.0) { result, term in
                let phrase = term.contains(" ") || term.unicodeScalars.contains(where: { $0.value > 127 }) && term.count >= 4
                return result + (phrase ? 20 : 10)
            } + Double(rule.priority) / 100
            ranked.append((rule, terms, score))
        }
        ranked.sort { $0.2 == $1.2 ? $0.0.id < $1.0.id : $0.2 > $1.2 }
        guard let winner = ranked.first else {
            return OfflineOutcome(classification: nil, candidates: [], matchedTerms: [], message: tr("没有明确匹配。你主要想完成哪类任务？", "No clear rule match. What is the main task?"))
        }
        if ranked.count > 1 {
            let compound = normalized(task).range(of: "\\band\\b|同时|以及|并且", options: .regularExpression) != nil
            let tied = winner.2 - ranked[1].2 < 3
            if tied || compound && ranked[1].2 >= 10 {
                return OfflineOutcome(classification: nil, candidates: ranked.prefix(3).map { $0.0.id }, matchedTerms: winner.1,
                    message: tr("匹配到多个目标。哪一个是这次的主要任务？", "Several goals matched. Which is the main task?"))
            }
        }
        var level = winner.0.complexity
        if winner.0.demanding.contains(where: { matches($0, in: task) }) { level = 2 }
        else if winner.0.light.contains(where: { matches($0, in: task) }) { level = 0 }
        let answer = Classification(category: winner.0.id, surface: winner.0.surface, complexity: level,
            classifierModel: "", clarification: nil, confidence: nil, source: "offline")
        return OfflineOutcome(classification: answer, candidates: [], matchedTerms: winner.1, message: nil)
    }
}

/// One coordinator enforces engine choice and makes network failure an explicit local fallback.
struct RecommendationDecision {
    let classification: Classification?
    let offline: OfflineOutcome?
    let didFallback: Bool
    let error: String?
}
enum RecommendationMode: String { case ai, offline }
enum RecommendationCoordinator {
    static func decide(task: String, book: RuleBook, mode: RecommendationMode,
                       cloud: () async throws -> Classification) async throws -> RecommendationDecision {
        try Task.checkCancellation()
        if mode == .offline {
            let result = OfflineEngine.classify(task, book: book)
            return RecommendationDecision(classification: result.classification, offline: result, didFallback: false, error: nil)
        }
        do {
            let result = try await cloud(); try Task.checkCancellation()
            return RecommendationDecision(classification: result, offline: nil, didFallback: false, error: nil)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            let result = OfflineEngine.classify(task, book: book)
            return RecommendationDecision(classification: result.classification, offline: result, didFallback: true, error: error.localizedDescription)
        }
    }
}
