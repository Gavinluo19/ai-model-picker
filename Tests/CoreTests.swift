import Foundation
import AppKit
import Carbon

@main struct CoreTests {
    static var count = 0
    static let countLock = NSLock()
    static func counted() { countLock.lock(); count += 1; countLock.unlock() }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        guard try condition() else { throw RouterError("FAIL: " + label) }; counted(); print("PASS " + label)
    }
    static func rejects(_ label: String, _ body: () throws -> Void) throws {
        do { try body() } catch { counted(); print("PASS " + label); return }
        throw RouterError("FAIL: accepted " + label)
    }
    static func response(_ book: RuleBook, category: String = "consulting_delivery", confidence: Double = 0.96,
                         surface: String = "files", complexity: [String: Double] = ["0": 0.0, "1": 1.0, "2": 0.0], clarify: Double = 0.0) -> [String: Any] {
        var categories = Dictionary(uniqueKeysWithValues: (book.tasks.map(\.id) + ["needs_choice"]).map { ($0, 0.0) })
        categories[category] = 1
        var surfaces = Dictionary(uniqueKeysWithValues: ["discussion", "files", "code", "unknown"].map { ($0, 0.0) }); surfaces[surface] = 1
        return ["model": "jev-1.13.0", "answers": [
            "task_type": ["type": "choice", "choice": category, "confidence": confidence, "probabilities": categories] as [String: Any],
            "surface_need": ["type": "choice", "choice": surface, "confidence": 0.96, "probabilities": surfaces] as [String: Any],
            "complexity": ["type": "score", "score": complexity["1"]! + 2 * complexity["2"]!, "confidence": 0.9, "probabilities": complexity] as [String: Any],
            "needs_clarification": ["type": "noul", "noul": clarify] as [String: Any]
        ] as [String: Any]]
    }
    static func parse(_ root: [String: Any], book: RuleBook) throws -> Classification { try ResponseValidator.parse(JSONSerialization.data(withJSONObject: root), book: book) }
    static func offlineTests(book: RuleBook, source: URL) async throws {
        let pairs: [(String,String)] = [
            ("制定新的商业模式", "strategy"), ("Review our business model", "strategy"),
            ("请分析本季度的经营复盘", "consulting_delivery"), ("Prepare an operating review", "consulting_delivery"),
            ("核对三份材料中的数字", "document_verification"), ("Reconcile figures in the attached PDFs", "document_verification"),
            ("整理行业研究的来源", "research"), ("Research the competitor landscape", "research"),
            ("整理客户报告的排版", "presentation"), ("Polish report formatting", "presentation"),
            ("查询飞书记录", "workflow"), ("Run workflow execution in Lark", "workflow"),
            ("完成浏览器操作", "computer"), ("Perform browser automation", "computer"),
            ("梳理软件架构及模块边界", "architecture"), ("Define system architecture", "architecture"),
            ("实现导入功能", "coding"), ("Implement a file importer", "coding"),
            ("定位并修复错误", "debugging"), ("Fix the crash root cause", "debugging"),
            ("调整前端页面布局", "frontend"), ("Create a frontend prototype", "frontend"),
            ("给项目补测试", "testing_review"), ("Improve unit test coverage", "testing_review"),
            ("翻译这段话", "simple"), ("Translate this paragraph", "simple")]
        for (text,id) in pairs { try expect(OfflineEngine.classify(text,book:book).classification?.category == id, "offline: " + text) }
        try expect(OfflineEngine.classify("Research competitors and create slides",book:book).classification == nil, "compound task asks for main goal")
        try expect(OfflineEngine.classify("无需写代码，请梳理软件架构",book:book).classification?.category == "architecture", "Chinese negation avoids coding")
        try expect(OfflineEngine.classify("Do not implement; define system architecture",book:book).classification?.category == "architecture", "English negation avoids coding")
        try expect(OfflineEngine.classify("你好",book:book).classification == nil, "unmatched task asks instead of guessing")
        try expect(!OfflineEngine.matches("bug",in:"debugger"), "Latin token boundary")
        try expect(OfflineEngine.classify("简单翻译",book:book).classification?.complexity == 0, "light task stays low")
        try expect(OfflineEngine.classify("复杂软件架构，多约束",book:book).classification?.complexity == 2, "complexity escalates")
        let legacy = try MarkdownRules.read(source.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/LegacyRules.md"))
        try expect(!legacy.supportsOfflineMatching && OfflineEngine.classify("翻译",book:legacy).classification == nil, "legacy rules remain readable without guessing")
        let english = try MarkdownRules.read(source.deletingLastPathComponent().appendingPathComponent("DefaultRules.en.md"))
        try expect(english.tasks.map(\.id) == book.tasks.map(\.id) && english.offline.count == 13, "English Markdown schema")
        var calls = 0
        let offline = try await RecommendationCoordinator.decide(task:"翻译",book:book,mode:.offline) { calls += 1; throw RouterError("unexpected") }
        try expect(calls == 0 && offline.classification?.category == "simple", "offline makes zero cloud calls")
        let fallback = try await RecommendationCoordinator.decide(task:"翻译",book:book,mode:.ai) { throw URLError(.timedOut) }
        try expect(fallback.didFallback && fallback.classification?.source == "offline", "timeout clearly falls back to offline")
        do {
            _ = try await RecommendationCoordinator.decide(task:"翻译",book:book,mode:.ai) { throw CancellationError() }
            throw RouterError("cancellation swallowed")
        } catch is CancellationError { counted(); print("PASS cancellation never falls back") }
        try expect(!MenuMatcher.containsEffort("高效",value:.high), "Chinese adjective is not an effort")
        try expect(MenuMatcher.containsModel("GPT-6.1 Sol 中",name:"GPT-6.1 Sol"), "latest Sol readback")
        try expect(!MenuMatcher.containsModel("GPT-6 Sol",name:"GPT-6.1 Sol"), "old Sol is not latest Sol")
        UIStrings.language = .en
        try expect(book.name(for:"strategy") != book.tasks.first?.name, "English category label")
        try expect(Effort.high.title == "High", "English effort label")
        try expect(UIStrings.error("English status.") == "English status.", "English status is not wrapped as an error")
        try expect(legacy.changes(from:book).contains("Models:"), "English model catalog preview")
        UIStrings.language = .zh
        let renamed = try MarkdownRules.parse(book.markdown.replacingOccurrences(of:"GPT-6.1 Sol",with:"GPT-6.1 Sol Updated"))
        try expect(renamed.changes(from:book).contains("修改 1"), "renamed model appears in import preview")
        let edited = try MarkdownRules.parse(book.markdown.replacingOccurrences(of:"商业模式,",with:"新业务模式,"))
        try expect(edited.changes(from:book).contains("任务规则变化 1 类"), "offline condition edits appear in import preview")
    }
    @MainActor static func nativeChecks(book:RuleBook,source:URL) throws {
        _ = NSApplication.shared
        let text = TaskInput(frame:NSRect(x:0,y:0,width:600,height:110)); text.isRichText = true; text.isHorizontallyResizable = false; text.isVerticallyResizable = true; text.textContainerInset = NSSize(width:10,height:10)
        let scroll = TaskScrollView(frame:NSRect(x:0,y:0,width:380,height:110)); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.documentView = text
        let original = String(repeating:"测试自动换行内容，包含中英文和 verylongwordswithoutspaces。",count:10)
        let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.boldSystemFont(ofSize:17)]
        text.textStorage?.setAttributedString(NSAttributedString(string:original,attributes:attrs)); text.normalizeParagraphs(); scroll.tile()
        let container = text.textContainer!, layout = text.layoutManager!; layout.ensureLayout(for:container)
        func lines() -> Int { var total = 0; layout.enumerateLineFragments(forGlyphRange:NSRange(location:0,length:layout.numberOfGlyphs)) { _,_,_,_,_ in total += 1 }; return total }
        let narrow = lines()
        try expect(container.containerSize.width < 380 && narrow > 5, "long text wraps inside the visible viewport")
        scroll.setFrameSize(NSSize(width:640,height:110)); scroll.tile(); layout.ensureLayout(for:container)
        try expect(lines() < narrow && text.string == original, "resizing reflows without losing text")
        try expect(NSFontManager.shared.traits(of:text.textStorage?.attribute(.font,at:0,effectiveRange:nil) as! NSFont).contains(.boldFontMask), "rich paste keeps bold after normalization")
        text.setSelectedRange(NSRange(location:0,length:5)); text.toggleTrait(.italicFontMask)
        try expect(NSFontManager.shared.traits(of:text.textStorage?.attribute(.font,at:0,effectiveRange:nil) as! NSFont).contains(.italicFontMask) || ((text.textStorage?.attribute(.obliqueness,at:0,effectiveRange:nil) as? NSNumber)?.doubleValue ?? 0) > 0, "selected rich text accepts italic formatting")
        let copied = text.attributedString(); let rebuilt = TaskInput(frame:.zero); rebuilt.textStorage?.setAttributedString(copied)
        try expect(rebuilt.string == original && rebuilt.attributedString().isEqual(to:copied), "attributed task survives a view rebuild")
        let prices = PriceBook.load(source.deletingLastPathComponent().appendingPathComponent("APIPrices.json"))
        try expect(prices.models.count == book.models.count, "all routed models have an exact price reference")
        UIStrings.language = .zh; try expect(prices.summary(for:book.models["sol61"]!).contains("¥14.00") && prices.summary(for:book.models["wb_glm53"]!).contains("¥8.00"), "Chinese prices use CNY")
        UIStrings.language = .en; try expect(prices.summary(for:book.models["sol61"]!).contains("$2.00") && prices.summary(for:book.models["wb_glm53"]!).contains("$1.14"), "English prices use USD equivalents")
        let missing = PriceBook.load(nil); try expect(missing.summary(for:book.models["sol61"]!).contains("unverified"), "missing price is not fabricated as zero")
        UIStrings.language = .zh
        let pricePath = source.deletingLastPathComponent().appendingPathComponent("APIPrices.json")
        let tempPrices = FileManager.default.temporaryDirectory.appendingPathComponent("AIModelPrices-"+UUID().uuidString+".json")
        defer { try? FileManager.default.removeItem(at:tempPrices) }
        var json = try JSONSerialization.jsonObject(with:Data(contentsOf:pricePath)) as! [String:Any]
        json["cnyPerUSD"] = -1; try JSONSerialization.data(withJSONObject:json).write(to:tempPrices)
        try rejects("negative FX reference") { _ = try PriceBook.read(tempPrices) }
        json["cnyPerUSD"] = 7; var entries = json["models"] as! [String:[String:Any]]; entries["sol61"]!["currency"] = "EUR"; json["models"] = entries
        try JSONSerialization.data(withJSONObject:json).write(to:tempPrices); try rejects("unsupported price currency") { _ = try PriceBook.read(tempPrices) }
        entries["sol61"]!["currency"] = "USD"; entries["sol61"]!["source"] = "file:///etc/passwd"; json["models"] = entries
        try JSONSerialization.data(withJSONObject:json).write(to:tempPrices); try rejects("non-HTTPS price source") { _ = try PriceBook.read(tempPrices) }
        try expect(ShortcutSpec(keyCode:40,modifiers:UInt32(cmdKey),keyLabel:"K").isValid, "two-key custom shortcut")
        try expect(ShortcutSpec(keyCode:40,modifiers:UInt32(controlKey|optionKey),keyLabel:"K").isValid, "three-key custom shortcut")
        try expect(!ShortcutSpec(keyCode:40,modifiers:0,keyLabel:"K").isValid && !ShortcutSpec(keyCode:40,modifiers:UInt32(cmdKey|controlKey|optionKey),keyLabel:"K").isValid, "reject bare and four-key shortcuts")
        let spaceEvent = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.control,.option],timestamp:0,windowNumber:0,context:nil,characters:" ",charactersIgnoringModifiers:" ",isARepeat:false,keyCode:49)!
        try expect(ShortcutSpec.from(spaceEvent) == ShortcutSpec.presets[0], "modifier-space is a recordable shortcut")
        do {
            let holder = Hotkey(), changing = Hotkey()
            let held = ShortcutSpec(keyCode:80,modifiers:UInt32(controlKey|optionKey),keyLabel:"F19")
            let retained = ShortcutSpec(keyCode:79,modifiers:UInt32(controlKey|optionKey),keyLabel:"F18")
            try expect(holder.register(held), "register isolated shortcut for conflict check")
            try expect(changing.register(retained), "register shortcut before replacement")
            try expect(!changing.register(held), "occupied shortcut rejects replacement")
            try expect(changing.current == retained && changing.reference != nil, "failed replacement retains live old registration")
        }
        let preference = UserDefaults(suiteName:"TaskRouterTests-"+UUID().uuidString)!
        preference.set(2,forKey:"hotkeyIndex"); try expect(ShortcutSpec.load(preference) == ShortcutSpec.presets[2], "old preset shortcut migrates")
        let spec = ShortcutSpec(keyCode:40,modifiers:UInt32(cmdKey|shiftKey),keyLabel:"K"); preference.set(try JSONEncoder().encode(spec),forKey:"customShortcut")
        try expect(ShortcutSpec.load(preference) == spec, "custom shortcut persists")
        for rule in book.tasks {
            let classification = Classification(category:rule.id,surface:book.offline[rule.id]?.surface ?? "files",complexity:1,classifierModel:"",clarification:nil,confidence:nil,source:"offline")
            let candidates = try RoutingEngine.recommendations(book:book,classification:classification,scope:"all",enabled:Set(ClientID.allCases))
            try expect(candidates.count == 4 && candidates.prefix(2).allSatisfy { !$0.model.client.isChina } && candidates.suffix(2).allSatisfy { $0.model.client.isChina }, "four ordered choices: "+rule.id)
        }
    }
    static func catalogFixture() throws -> Data {
        func model(_ name:String,input:Double,output:Double,release:String="") -> [String:Any] { ["name":name,"release_date":release,"modalities":["output":["text"]],"cost":["input":input,"output":output]] }
        let root:[String:Any] = ["openai":["models":["gpt-6.1-sol":model("GPT-6.1 Sol",input:2,output:10,release:"2026-09-29"),"future-sol":model("Future Sol",input:0,output:0,release:"2026-11-01"),"embedding-sample":model("Embed",input:1,output:1)]],"aggregator":["models":["gpt-6.1-sol":model("Not direct",input:99,output:99)]]]
        return try JSONSerialization.data(withJSONObject:root)
    }
    static func updateChecks(book:RuleBook,source:URL) async throws {
        let data = try catalogFixture(), snapshot = try PublicCatalog.parse(data,at:"2026-10-01T00:00:00Z")
        try expect(snapshot.models.count == 2 && snapshot.models.first?.id == "future-sol", "public catalog filters providers/types and orders release")
        try expect(snapshot.models.first?.input == nil, "zero registry rate is not advertised as free")
        try rejects("empty supported public catalog") { _ = try PublicCatalog.parse(Data("{}".utf8),at:"test") }
        let fxData = Data("{\"date\":\"2026-10-01\",\"base\":\"USD\",\"quote\":\"CNY\",\"rate\":6.7}".utf8)
        let fx = try PublicCatalog.parseFX(fxData)
        try expect(fx.rate == 6.7 && fx.date == "2026-10-01", "FX preserves observation date")
        try rejects("reversed currency quote") { _ = try PublicCatalog.parseFX(Data("{\"date\":\"2026-10-01\",\"base\":\"CNY\",\"quote\":\"USD\",\"rate\":0.15}".utf8)) }
        let old = PriceBook.load(source.deletingLastPathComponent().appendingPathComponent("APIPrices.json"))
        let merged = PublicCatalog.merge(prices:old,market:snapshot,fx:fx)
        try expect(merged.models["sol61"]?.input == 2 && merged.models["sol61"]?.updated == snapshot.fetchedAt && merged.cnyPerUSD == 6.7, "exact-ID price merge and FX update")
        try expect(merged.models["opus55"]?.output == old.models["opus55"]?.output, "missing remote models retain their prices")
        try expect(book.models["future-sol"] == nil, "new discovery does not alter routing rules")
        let list = merged.listing(book:book,market:snapshot)
        try expect(zip(list,list.dropFirst()).allSatisfy { $0.outputUSD(fx:6.7) >= $1.outputUSD(fx:6.7) }, "price table sorts output descending across currencies")
        try expect(list.last?.price == nil, "unknown prices sort after known prices")
        let client = PublicUpdateClient(transport:{ request in
            try expect(request.httpMethod == "GET" && request.httpBody == nil && request.value(forHTTPHeaderField:"Authorization") == nil, "metadata refresh sends no task/key/body")
            let body = request.url == PublicUpdateClient.catalogURL ? data:fxData
            return (body,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        })
        let result = try await client.fetch()
        try expect(result.market != nil && result.fx != nil && result.failures.isEmpty, "both public update streams succeed")
        let partial = PublicUpdateClient(transport:{ request in
            if request.url == PublicUpdateClient.fxURL { throw URLError(.timedOut) }
            return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        })
        let partly = try await partial.fetch(); try expect(partly.market != nil && partly.fx == nil && partly.failures.count == 1, "partial update keeps old FX")
        let failure = PublicUpdateClient(transport:{ _ in throw URLError(.notConnectedToInternet) })
        let failed = try await failure.fetch(); try expect(failed.market == nil && failed.fx == nil && failed.failures.count == 2, "offline update makes no fake freshness claim")
        let unchanged = PublicCatalog.merge(prices:old,market:nil,fx:nil)
        try expect(unchanged.cnyPerUSD == old.cnyPerUSD && unchanged.models["sol61"]?.output == old.models["sol61"]?.output, "failed streams leave values unchanged")
        let task = Task { try await PublicUpdateClient(transport:{ _ in try await Task.sleep(nanoseconds:200_000_000); throw CancellationError() }).fetch() }
        task.cancel(); do { _ = try await task.value; throw RouterError("cancellation swallowed") } catch is CancellationError { counted(); print("PASS canceled catalog refresh never applies results") }
    }
    static func main() async throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let raw = try String(contentsOf: source, encoding: .utf8), book = try MarkdownRules.parse(raw)
        try expect(book.tasks.count == 13 && book.models.count == 11 && book.china.count == 13, "full Markdown import")
        let clean = try MarkdownRules.parse("\u{FEFF}" + raw.replacingOccurrences(of: "\n", with: "\r\n"))
        try expect(clean.fingerprint == book.fingerprint, "BOM and newline normalization")
        try rejects("unknown model") { _ = try MarkdownRules.parse(raw.replacingOccurrences(of: "- 首选：opus55", with: "- 首选：missing")) }
        try rejects("invalid effort") { _ = try MarkdownRules.parse(raw.replacingOccurrences(of: "high,high,xhigh", with: "high,high,ultra")) }
        try rejects("duplicate task") { _ = try MarkdownRules.parse(raw.replacingOccurrences(of: "### consulting_delivery｜", with: "### strategy｜")) }
        try rejects("duplicate metadata") { _ = try MarkdownRules.parse(raw.replacingOccurrences(of: "| 状态 | 试行 |", with: "| 状态 | 试行 |\n| 状态 | 重复 |")) }
        try rejects("regional model mismatch") { _ = try MarkdownRules.parse(raw.replacingOccurrences(of: "| strategy | wb_k3 | trae_glm53", with: "| strategy | opus55 | trae_glm53")) }
        try rejects("unknown app") { _ = try MarkdownRules.parse(raw.replacingOccurrences(of: "| sol61 | chatgpt |", with: "| sol61 | terminal |")) }
        try rejects("oversize rulebook") { _ = try MarkdownRules.parse(String(repeating: "a", count: 262_145)) }
        let request = try book.request(for: "请核对三份经营报告")
        try expect((request["questions"] as? [String: Any])?.count == 4, "four independent JEV questions")
        try expect((request["state"] as? [String: String])?["task"] == "请核对三份经营报告", "task text preserved")
        try rejects("oversize task without truncation") { _ = try book.request(for: String(repeating: "中", count: 5000)) }
        let answer = try parse(response(book), book: book)
        try expect(answer.category == "consulting_delivery" && answer.complexity == 1 && answer.clarification == nil, "valid JEV response")
        try expect(try parse(response(book, confidence: 0.2), book: book).clarification != nil, "low confidence asks for input")
        try expect(try parse(response(book, clarify: 0.9), book: book).clarification != nil, "Noul clarification gate")
        try expect(try parse(response(book, category: "needs_choice"), book: book).clarification != nil, "unknown category path")
        try expect(try parse(response(book, category: "coding", surface: "discussion"), book: book).clarification != nil, "inconsistent code mode gate")
        let tied = try parse(response(book, complexity: ["0":0.5,"1":0.0,"2":0.5]), book: book)
        try expect(tied.complexity == 1, "complexity tie stays regular")
        try rejects("boolean probability") { _ = try ResponseValidator.unit(true) }
        try rejects("probability distribution missing options") { _ = try ResponseValidator.distribution(["0": 1], options: ["0", "1"]) }
        let china = try RoutingEngine.recommendations(book: book, classification: answer, scope: "china", enabled: Set(ClientID.allCases))
        try expect(china.allSatisfy { $0.model.client.isChina && $0.effort == .client_default }, "China scope never crosses provider boundary")
        let international = try RoutingEngine.recommendations(book: book, classification: answer, scope: "international", enabled: Set(ClientID.allCases))
        try expect(international.first?.model.key == "sonnet55" && international.first?.effort == .xhigh, "consulting route matches rulebook")
        let missing = try RoutingEngine.recommendations(book: book, classification: answer, scope: "china", enabled: [.claude])
        try expect(missing.isEmpty, "missing regional apps do not silently fall back")
        let disabled = try RoutingEngine.recommendations(book: book, classification: answer, scope: "all", enabled: [.claude], unavailableModels: ["sonnet55"])
        try expect(disabled.isEmpty, "disabled models excluded")
        try expect(MenuMatcher.containsModel("Model: Sonnet 5.5 Medium", name: "Sonnet 5.5"), "model button readback matching")
        try expect(!MenuMatcher.containsModel("GLM-5.3-Flash 0.06x", name: "GLM-5.3"), "Flash cannot match standard GLM")
        try expect(!MenuMatcher.containsModel("GLM-5.3:glm-5.3", name: "GLM-5.3"), "custom model label not silently treated as builtin")
        try expect(!MenuMatcher.containsEffort("Extra high", value: .high), "High cannot match Extra High")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("TaskRouterTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = try RuleStore(directory: temp, bundled: source)
        let updated = try MarkdownRules.parse(raw.replacingOccurrences(of: book.version, with: "test-v2"))
        try store.activate(updated); try expect(try store.load().version == "test-v2", "rule activation persists")
        try expect(try store.rollback().version == book.version, "rollback restores last valid rulebook")
        var requests = 0
        let client = JevClient(transport: { request in
            requests += 1
            try expect(request.url?.host == "api.typesafe.ai" && request.url?.path == "/v1/models", "connection test uses fixed official host")
            return (Data("{\"models\":[]}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await client.testConnection(key: "synthetic-not-a-secret")
        try expect(requests == 1, "connection test does not classify")
        let authFailure = JevClient(transport: { request in
            (Data("secret echoed in server body".utf8), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        })
        do { _ = try await authFailure.testConnection(key: "synthetic-not-a-secret"); throw RouterError("accepted 401") }
        catch { try expect(!error.localizedDescription.contains("secret") && error.localizedDescription.contains("密钥"), "remote body redacted from auth errors") }
        let api = JevClient(transport: { request in
            let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            try expect(request.httpMethod == "POST" && payload["model"] as? String == book.classifier, "classification request shape")
            return (try JSONSerialization.data(withJSONObject: response(book)), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let final = try await api.classify(task: "整理经营复盘", book: book, key: "synthetic-not-a-secret")
        try expect(final.category == "consulting_delivery", "network contract through response validation")
        try await offlineTests(book: book, source: source)
        try nativeChecks(book:book,source:source)
        try await updateChecks(book:book,source:source)
        print("RESULT: \(count) checks passed. No live API or desktop automation invoked.")
    }
}
