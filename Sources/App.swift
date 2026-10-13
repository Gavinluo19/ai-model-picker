import AppKit
import Carbon
import UniformTypeIdentifiers

final class RuleDropView: NSView {
    var onFile: ((URL) -> Void)?
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], urls.count == 1,
              ["md", "markdown"].contains(urls[0].pathExtension.lowercased()) else { return false }
        onFile?(urls[0]); return true
    }
}

enum AppearanceChoice: String { case system, light, dark }
@MainActor final class AppController: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate {
    let defaults = UserDefaults.standard
    var book: RuleBook!; var store: RuleStore!; var audit: AuditLog!
    var panel: NSWindow!; var settings: NSWindow?; var statusItem: NSStatusItem!; var hotkey: Hotkey!
    var installations: [ClientID:ClientInstallation] = [:]; var enabled: Set<ClientID> = []
    var language: UILanguage = .zh; var appearance: AppearanceChoice = .system
    var mode: RecommendationMode = .offline
    var recommendations: [Recommendation] = []; var lastClassification: Classification?
    var activeTask = ""; var richTask = NSAttributedString(string:""); var selectionRange = NSRange(location:0,length:0); var selectedIndex = 0; var overrideEffort: Effort?; var overrideSurface: String?
    var fallback = false; var evidenceTerms: [String] = []; var detailsExpanded = false
    var choices: [String] = []; var asking = false; var question = ""; var pendingClassification: Classification?; var fallbackReason = ""
    var busy = false; var rebuilding = false; var operationID = UUID(); var operation: Task<Void,Never>?
    enum Notice { case clarification, none, setup, working, fallback, copied, canceled, ready, problem, rules, manual, opening }
    var notice: Notice = .none; var detail = ""; var lastClient: ClientID?
    let preparer = DesktopPreparer(); let cloud = JevClient()
    var market:MarketSnapshot?; var modelsStatus:NSTextField?; var modelTable:DataTable?; var priceTable:DataTable?
    let updater = PublicUpdateClient(); var refreshing = false; var updateTask:Task<Void,Never>?; var updateID = UUID(); var updateMessage = ""; var updateButtons:[NSButton] = []
    var rootStack: NSStackView?; var contentScroll: NSScrollView?; var cards:[RecommendationCard] = []; var priceBook = PriceBook.load(nil); var priceStatus:NSTextField?; var shortcutRecorder:ShortcutRecorder?; var input = TaskInput(); var modeControl = NSSegmentedControl()
    var primary = NSButton(); var cancelButton = NSButton()
    var status = NSTextField(); var spinner = NSProgressIndicator()
    var manualChoice = NSPopUpButton()
    var modelLabel = NSTextField(); var reasonLabel = NSTextField(); var sourceLabel = NSTextField()
    var mainButton = NSButton(); var openButton = NSButton(); var copyButton = NSButton(); var detailsButton = NSButton(); var surfaceSegments = NSSegmentedControl(); var effortSegments = NSSegmentedControl(); var detailLabel = NSTextField(); var manualGroup = NSStackView()
    var resultGroup = NSStackView(); var adjustmentGroup = NSStackView(); var warning = NSBox()
    var keyField: NSSecureTextField?; var keyStatus: NSTextField?; var ruleStatus: NSTextField?
    var accessStatus: NSTextField?; var clientButtons: [ClientID:NSButton] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let saved = defaults.string(forKey:"interfaceLanguage")
            if let saved = saved, let selected = UILanguage(rawValue:saved) { language = selected }
            else if defaults.object(forKey:"scope") != nil { language = .zh }
            else { language = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en }
            UIStrings.language = language
            appearance = AppearanceChoice(rawValue:defaults.string(forKey:"appearance") ?? "system") ?? .system
            let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("TaskRouter")
            guard let bundled = Bundle.main.url(forResource:"DefaultRules",withExtension:"md") else { throw RouterError("应用缺少默认规则，请重新安装完整应用。") }
            store = try RuleStore(directory:directory,bundled:bundled)
            do { book = try store.load() } catch { book = try MarkdownRules.read(bundled); notice = .problem; detail = tr("已加载内置规则，请重新检查自定义规则。","Built-in rules were loaded. Check your custom rule file.") }
            audit = AuditLog(directory:directory); installations = ClientCatalog.discover()
            enabled = defaults.stringArray(forKey:"enabledClients").map { Set($0.compactMap(ClientID.init(rawValue:))) } ?? Set(installations.keys)
            let hasKey = ((try? KeyVault.load()) ?? nil) != nil
            mode = RecommendationMode(rawValue:defaults.string(forKey:"recommendationMode") ?? (hasKey ? "ai":"offline")) ?? .offline
            let savedPrices = directory.appendingPathComponent("prices.json")
            priceBook = PriceBook.load(FileManager.default.fileExists(atPath:savedPrices.path) ? savedPrices:Bundle.main.url(forResource:"APIPrices",withExtension:"json"))
            if let url = Bundle.main.url(forResource:"ModelCatalog",withExtension:"json"), let data = try? Data(contentsOf:url) { market = try? JSONDecoder().decode(MarketSnapshot.self,from:data) }
            let state = directory.appendingPathComponent("market-state.json")
            if let data = try? Data(contentsOf:state), let cached = try? JSONDecoder().decode(MarketCache.self,from:data) { market = cached.market; priceBook = cached.prices }
            if let icon = Bundle.main.url(forResource:"AppIcon",withExtension:"icns"), let image = NSImage(contentsOf:icon) { NSApp.applicationIconImage = image }
            makePanel(); buildMenu(); applyAppearance(); rebuildMain()
            hotkey = Hotkey(); hotkey.callback = { [weak self] in guard self?.shortcutRecorder?.recording != true else { return }; self?.showPanel() }
            if !hotkey.register(ShortcutSpec.load(defaults)) { notice = .problem; detail = tr("快捷键被占用，请在设置中更换。","The shortcut is in use. Choose another in Settings.") }

            showPanel()
        } catch { alert(tr("无法启动","Unable to start"),error.localizedDescription); NSApp.terminate(nil) }
    }
    func label(_ text:String,size:CGFloat=13,secondary:Bool=false) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString:text); l.font = .systemFont(ofSize:size); l.textColor = secondary ? .secondaryLabelColor:.labelColor
        l.setContentCompressionResistancePriority(.defaultLow,for:.horizontal); return l
    }
    func button(_ title:String,_ action:Selector,primary:Bool=false) -> NSButton {
        let b = NSButton(title:title,target:self,action:action); b.bezelStyle = .rounded; if primary { b.bezelColor = .controlAccentColor }; return b
    }
    func row(_ views:[NSView]) -> NSStackView { let s = NSStackView(views:views); s.orientation = .horizontal; s.spacing = 8; s.alignment = .centerY; return s }
    func column(_ views:[NSView]=[],spacing:CGFloat=12) -> NSStackView { let s = NSStackView(views:views); s.orientation = .vertical; s.spacing = spacing; s.alignment = .leading; return s }
    func full(_ v:NSView,_ s:NSStackView,height:CGFloat?=nil) { s.addArrangedSubview(v); v.translatesAutoresizingMaskIntoConstraints = false; v.widthAnchor.constraint(equalTo:s.widthAnchor).isActive = true; if let height = height { v.heightAnchor.constraint(equalToConstant:height).isActive = true } }
    func makePanel() {
        NSApp.setActivationPolicy(.regular)
        panel = NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:640),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        panel.titlebarAppearsTransparent = true; panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.level = .normal; panel.collectionBehavior = [.moveToActiveSpace,.fullScreenPrimary]; panel.minSize = NSSize(width:640,height:480); panel.center()
    }
    func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle:UIStrings.appName,action:#selector(showPanel),keyEquivalent:"n").target = self
        menu.addItem(withTitle:tr("设置…","Settings…"),action:#selector(showSettings),keyEquivalent:",").target = self
        menu.addItem(.separator()); menu.addItem(withTitle:tr("退出","Quit"),action:#selector(quit),keyEquivalent:"q").target = self
        let main = NSMenu(); let root = NSMenuItem(); root.submenu = menu; main.addItem(root)
        let editRoot = NSMenuItem(title:tr("编辑","Edit"),action:nil,keyEquivalent:""); let edit = NSMenu(); editRoot.submenu = edit; main.addItem(editRoot)
        for (zh,en,action,key) in [("撤销","Undo",Selector(("undo:")),"z"),("剪切","Cut",#selector(NSText.cut(_:)),"x"),("复制","Copy",#selector(NSText.copy(_:)),"c"),("粘贴","Paste",#selector(NSText.paste(_:)),"v"),("全选","Select All",#selector(NSText.selectAll(_:)),"a")] { edit.addItem(withTitle:tr(zh,en),action:action,keyEquivalent:key) }
        edit.addItem(.separator()); edit.addItem(withTitle:tr("加粗","Bold"),action:#selector(boldText),keyEquivalent:"b").target = self; edit.addItem(withTitle:tr("斜体","Italic"),action:#selector(italicText),keyEquivalent:"i").target = self
        let windowRoot = NSMenuItem(title:tr("窗口","Window"),action:nil,keyEquivalent:""); let windowMenu = NSMenu(); windowRoot.submenu = windowMenu; main.addItem(windowRoot)
        windowMenu.addItem(withTitle:tr("最小化","Minimize"),action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        windowMenu.addItem(withTitle:tr("显示主窗口","Show main window"),action:#selector(showPanel),keyEquivalent:"1").target = self
        NSApp.windowsMenu = windowMenu; NSApp.mainMenu = main
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength) }
        statusItem.button?.image = NSImage(systemSymbolName:"arrow.triangle.branch",accessibilityDescription:UIStrings.appName)
        statusItem.button?.image?.isTemplate = true; statusItem.button?.image?.size = NSSize(width:18,height:18)
        statusItem.menu = menu.copy() as? NSMenu
    }
    func snapshotInput() { if !rebuilding { activeTask = input.string; richTask = input.attributedString(); selectionRange = input.selectedRange() } }
    func rebuildMain() {
        rebuilding = true; defer { rebuilding = false }
        panel.title = UIStrings.appName + " · V0.4.1"
        let outer = NSScrollView(); outer.hasVerticalScroller = true; outer.hasHorizontalScroller = false; outer.drawsBackground = false
        panel.contentView = outer; contentScroll = outer
        let content = FlippedDocumentView(); content.translatesAutoresizingMaskIntoConstraints = false; outer.documentView = content
        NSLayoutConstraint.activate([content.widthAnchor.constraint(equalTo:outer.contentView.widthAnchor)])
        let s = column(spacing:12); rootStack = s; s.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(s)
        NSLayoutConstraint.activate([s.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:20),s.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-20),s.topAnchor.constraint(equalTo:content.topAnchor,constant:38),s.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-16)])
        let title = label(UIStrings.appName,size:20); title.font = .systemFont(ofSize:20,weight:.semibold)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let lang = button(language == .zh ? "EN":"中文",#selector(toggleLanguage)); lang.toolTip = tr("切换为英文","Switch to Chinese")
        let theme = button("",#selector(toggleTheme)); theme.image = NSImage(systemSymbolName:panel.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? "sun.max":"moon",accessibilityDescription:tr("切换外观","Switch appearance")); theme.toolTip = tr("切换浅色或深色","Switch light or dark appearance")
        full(row([title,label("V0.4.1",size:11,secondary:true),spacer,lang,theme,button(tr("设置","Settings"),#selector(showSettings))]),s)
        full(label(tr("按任务选对模型，用好已付费的 AI 订阅。","Pick the right model for your task. Make the most of your AI subscriptions."),secondary:true),s)
        let scroll = TaskScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        input = TaskInput(frame:NSRect(x:0,y:0,width:520,height:90)); input.minSize = NSSize(width:0,height:90); input.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude); input.isRichText = true; input.importsGraphics = false; input.allowsUndo = true; input.font = .systemFont(ofSize:15); input.textContainerInset = NSSize(width:10,height:10)
        input.isVerticallyResizable = true; input.isHorizontallyResizable = false; input.autoresizingMask = [.width]; input.textContainer?.widthTracksTextView = true
        input.placeholder = tr("描述你这次要完成的任务…","Describe what you want to accomplish…"); if richTask.string == activeTask { input.textStorage?.setAttributedString(richTask) } else { input.string = activeTask }; input.normalizeParagraphs(); input.setSelectedRange(NSRange(location:min(selectionRange.location,input.string.utf16.count),length:min(selectionRange.length,max(0,input.string.utf16.count-selectionRange.location)))); input.delegate = self
        input.setAccessibilityLabel(tr("任务需求","Task")); scroll.documentView = input; full(scroll,s,height:110)
        let bold = button("B",#selector(boldText)); bold.font = .boldSystemFont(ofSize:12); bold.toolTip = tr("加粗 ⌘B","Bold ⌘B")
        let italic = button("I",#selector(italicText)); italic.toolTip = tr("斜体 ⌘I","Italic ⌘I")
        full(row([bold,italic,button(tr("列表","List"),#selector(listText)),label(tr("支持富文本粘贴 · 自动换行","Rich-text paste · Word wrap"),size:11,secondary:true)]),s)
        modeControl = NSSegmentedControl(labels:[tr("智能推荐","AI recommendation"),tr("离线推荐","Offline rules")],trackingMode:.selectOne,target:self,action:#selector(modeChanged))
        modeControl.selectedSegment = mode == .ai ? 0:1
        full(modeControl,s)
        primary = button(tr("推荐模型","Recommend"),#selector(recommend),primary:true)
        cancelButton = button(tr("取消","Cancel"),#selector(cancel)); cancelButton.isHidden = !busy
        spinner = NSProgressIndicator(); spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        full(row([primary,spinner,cancelButton]),s)
        status = label("",size:12,secondary:true); full(status,s)
        manualGroup = column(spacing:8)
        full(label(question,size:13),manualGroup)
        manualChoice = NSPopUpButton(); manualChoice.addItem(withTitle:tr("选择主要任务","Choose the main task"))
        let ids = pendingClassification?.clarifySurface == true ? ["discussion","files","code"] : choices.isEmpty ? book.tasks.map(\.id):choices
        for id in ids {
            let title = pendingClassification?.clarifySurface == true ? (id == "discussion" ? tr("讨论与建议","Discussion & advice") : id == "files" ? tr("研究或文件处理","Research or files") : tr("修改代码与测试","Code & tests")) : book.name(for:id)
            manualChoice.addItem(withTitle:title); manualChoice.lastItem?.representedObject = id
        }
        if !choices.isEmpty && pendingClassification?.clarifySurface != true { manualChoice.addItem(withTitle:tr("其他任务…","Other task…")); manualChoice.lastItem?.representedObject = "__other" }
        full(row([manualChoice,button(tr("采用选择","Use selection"),#selector(confirmChoice))]),manualGroup); full(manualGroup,s); manualGroup.isHidden = !asking
        resultGroup = column(spacing:9)
        sourceLabel = label("",size:11,secondary:true); full(sourceLabel,resultGroup)
        cards = []
        for start in stride(from:0,to:recommendations.count,by:2) {
            var views:[NSView] = []
            for index in start..<min(start+2,recommendations.count) {
                let visibleRecommendation = index == selectedIndex ? selected ?? recommendations[index]:recommendations[index]
                let card = RecommendationCard(index:index,recommendation:visibleRecommendation,price:priceBook.summary(for:recommendations[index].model),selected:index == selectedIndex,availability:availabilityMessage(recommendations[index]),target:self,action:#selector(selectCard(_:)))
                cards.append(card); views.append(card)
            }
            if views.count == 1 { views.append(NSView()) }
            let pair = row(views); pair.distribution = .fillEqually; pair.alignment = .top; full(pair,resultGroup)
            views[0].widthAnchor.constraint(equalTo:views[1].widthAnchor).isActive = true
        }
        full(label(priceBook.disclaimer,size:10,secondary:true),resultGroup)
        modelLabel = label("",size:20); modelLabel.font = .systemFont(ofSize:15,weight:.semibold); modelLabel.isHidden = true
        reasonLabel = label("",size:12,secondary:true); full(reasonLabel,resultGroup)
        adjustmentGroup = column(spacing:8)
        full(label(tr("在哪个工作区处理？","Where should this task run?"),size:12,secondary:true),adjustmentGroup)
        surfaceSegments = NSSegmentedControl(labels:[""],trackingMode:.selectOne,target:self,action:#selector(surfaceSelected(_:))); full(surfaceSegments,adjustmentGroup)
        full(label(tr("思考强度","Reasoning effort"),size:12,secondary:true),adjustmentGroup)
        effortSegments = NSSegmentedControl(labels:[""],trackingMode:.selectOne,target:self,action:#selector(effortSelected(_:))); full(effortSegments,adjustmentGroup)
        full(adjustmentGroup,resultGroup)
        detailLabel = label("",size:12,secondary:true); full(detailLabel,resultGroup); detailLabel.isHidden = !detailsExpanded
        warning = NSBox(); warning.boxType = .custom; warning.cornerRadius = 8; warning.borderWidth = 1; warning.borderColor = .systemOrange; warning.fillColor = NSColor.systemOrange.withAlphaComponent(0.12)
        let w = column(spacing:5); w.translatesAutoresizingMaskIntoConstraints = false; warning.contentView?.addSubview(w)
        if let c = warning.contentView { NSLayoutConstraint.activate([w.leadingAnchor.constraint(equalTo:c.leadingAnchor,constant:10),w.trailingAnchor.constraint(equalTo:c.trailingAnchor,constant:-10),w.topAnchor.constraint(equalTo:c.topAnchor,constant:8)]) }
        full(label(tr("⚠ 网络与账号提醒","⚠ Network and account reminder"),size:12),w)
        full(label(tr("请确认当前所在地及访问方式符合 Claude 服务要求。违规使用可能导致账号受限或停用。","Check that your location and access comply with Claude’s service requirements. Violations may lead to account restrictions or suspension."),size:12),w)
        full(warning,resultGroup,height:language == .zh ? 78:98)
        mainButton = button("",#selector(prepare),primary:true)
        openButton = button("",#selector(openClient)); copyButton = button(tr("复制需求","Copy task"),#selector(copyTask)); detailsButton = button(tr("推荐依据","Why this model"),#selector(toggleDetails))
        full(row([mainButton,openButton,copyButton,detailsButton]),resultGroup); full(resultGroup,s); resultGroup.isHidden = recommendations.isEmpty
        refreshResult(); renderStatus(); setControls(); fitPanel()
    }
    func spacerView() -> NSView { let v = NSView(); v.setContentHuggingPriority(.defaultLow,for:.horizontal); return v }
    var selected: Recommendation? {
        guard recommendations.indices.contains(selectedIndex) else { return nil }; var r = recommendations[selectedIndex]
        if let effort = overrideEffort, r.model.efforts.contains(effort) { r.effort = effort }
        if let surface = overrideSurface, r.model.surfaces.contains(surface) { r.surface = surface }; return r
    }
    func refreshResult() {
        guard let r = selected else { return }
        modelLabel.stringValue = r.model.name + " · " + r.effort.title
        let id = lastClassification?.category ?? ""
        let original = r.model.client.isChina ? (book.china[id]?.reason ?? r.reason):(book.tasks.first(where:{$0.id == id})?.reason ?? r.reason)
        reasonLabel.stringValue = r.model.client.name + " · " + surfaceName(r.surface)
        detailLabel.stringValue = book.reason(for:id,original:original)
        if !evidenceTerms.isEmpty { detailLabel.stringValue += "\n" + tr("命中：","Matched: ") + evidenceTerms.joined(separator:", ") }
        sourceLabel.stringValue = lastClassification?.source == "jev" ? tr("智能推荐","AI recommendation") : lastClassification?.source == "manual" ? tr("按你的选择推荐","Based on your choice") : tr("离线规则推荐","Offline rule recommendation")
        if fallback { sourceLabel.stringValue += tr(" · 智能服务暂不可用"," · AI service unavailable") }
        let surfaces = r.model.surfaces.sorted(); surfaceSegments.segmentCount = surfaces.count
        for (index,surface) in surfaces.enumerated() { surfaceSegments.setLabel(surfaceName(surface),forSegment:index); surfaceSegments.setWidth(0,forSegment:index) }
        surfaceSegments.selectedSegment = surfaces.firstIndex(of:r.surface) ?? 0
        effortSegments.segmentCount = r.model.efforts.count
        for (index,effort) in r.model.efforts.enumerated() { effortSegments.setLabel(effort.title,forSegment:index); effortSegments.setWidth(0,forSegment:index) }
        effortSegments.selectedSegment = r.model.efforts.firstIndex(of:r.effort) ?? 0
        for card in cards { card.chooseButton.state = card.index == selectedIndex ? .on:.off; if card.index == selectedIndex { card.modelLabel.stringValue = r.model.name + " · " + r.effort.title } }
        let claude = r.model.client == .claude
        warning.isHidden = !claude; mainButton.bezelColor = claude ? .systemOrange:.controlAccentColor
        mainButton.title = claude ? tr("知悉并准备到 Claude","Continue with Claude") : tr("准备到 ","Prepare in ") + r.model.client.name
        openButton.title = claude ? tr("知悉并打开 Claude","Continue: open Claude only"):tr("仅打开 ","Open only: ") + r.model.client.name
    }
    func surfaceName(_ value:String) -> String { switch value { case "chat":return tr("对话","Chat"); case "work":return tr("工作 · Work","Work"); case "cowork":return tr("协作 · Cowork","Cowork"); case "codex":return tr("编程 · Codex","Codex"); case "code":return tr("编程 · Code","Code"); case "office":return tr("日常办公","Office"); default:return value } }
    func renderStatus() {
        let text:String
        switch notice {
        case .clarification: text = pendingClassification?.source == "jev" ? tr("JEV 已分析，请补充一个选择。","JEV analyzed your task. Confirm one choice.") : tr("离线规则需要补充一个选择。","Offline rules need one choice.")
        case .none: text = ""
        case .setup: text = tr("设置个人 JEV Key 后可用智能推荐；现在可用离线规则。","Set your JEV key for AI recommendations. Offline rules are available now.")
        case .working: text = tr("处理中…","Working…")
        case .fallback: text = tr("JEV 未完成，已转用离线规则：","JEV failed; using offline rules: ") + fallbackReason
        case .copied: text = tr("需求已复制。","Task copied.")
        case .canceled: text = tr("已取消，输入已保留。","Canceled. Your text is preserved.")
        case .ready: text = tr("准备好了，可在 ","Ready in ") + (lastClient?.name ?? "") + tr(" 中发送。",". Send the task there.")
        case .problem: text = UIStrings.error(detail)
        case .rules: text = tr("规则已更新，下一次推荐使用新版本。","Rules updated. The next recommendation will use this version.")
        case .manual: text = tr("推荐依据已调整。","Recommendation adjusted.")
        case .opening: text = tr("请在 ","Complete the setup in ") + (lastClient?.name ?? "") + tr(" 中手动准备任务。",".")
        }
        status.stringValue = text; status.isHidden = text.isEmpty
    }
    func setControls() { for card in cards { card.chooseButton.isEnabled = !busy }; for c in [primary,mainButton,openButton,copyButton,detailsButton,modeControl,surfaceSegments,effortSegments] as [NSControl] { c.isEnabled = !busy }; mainButton.isEnabled = !busy && (selected.map { availabilityMessage($0) == nil } ?? false); openButton.isEnabled = !busy && (selected.map { installations[$0.model.client] != nil } ?? false); cancelButton.isHidden = !busy; if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) } }
    func setBusy(_ value:Bool) { busy = value; setControls(); renderStatus(); fitPanel(); refreshTables() }
    func fitPanel() {
        guard let panel = panel, let s = rootStack else { return }; panel.contentView?.layoutSubtreeIfNeeded(); if panel.styleMask.contains(.fullScreen) { return }
        let maxHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let height = min(maxHeight-35,max(480,s.fittingSize.height+62)); var frame = panel.frame
        frame.origin.y -= height-frame.height; frame.size.height = height; if let visible = panel.screen?.visibleFrame { frame.origin.y = max(visible.minY,min(frame.origin.y,visible.maxY-height)) }; panel.setFrame(frame,display:true); contentScroll?.documentView?.layoutSubtreeIfNeeded()
    }
    @objc func showPanel() { NSApp.activate(ignoringOtherApps:true); if panel.isMiniaturized { panel.deminiaturize(nil) }; panel.makeKeyAndOrderFront(nil); fitPanel(); panel.makeFirstResponder(input) }
    @objc func quit() { operation?.cancel(); updateTask?.cancel(); NSApp.terminate(nil) }
    @objc func cancel() { operation?.cancel(); operationID = UUID(); notice = .canceled; setBusy(false) }
    func invalidate() { operation?.cancel(); operationID = UUID(); busy = false; recommendations = []; lastClassification = nil; asking = false; notice = .none; overrideEffort = nil; overrideSurface = nil; resultGroup.isHidden = true; manualGroup.isHidden = true; setControls(); renderStatus(); input.needsDisplay = true; fitPanel() }
    func textDidChange(_ notification:Notification) { guard !rebuilding else { return }; snapshotInput(); invalidate() }
    @objc func modeChanged() { snapshotInput(); mode = modeControl.selectedSegment == 0 ? .ai:.offline; defaults.set(mode.rawValue,forKey:"recommendationMode"); invalidate() }
    @objc func toggleLanguage() { snapshotInput(); language = language == .zh ? .en:.zh; UIStrings.language = language; defaults.set(language.rawValue,forKey:"interfaceLanguage"); settings?.close(); settings = nil; keyField = nil; keyStatus = nil; ruleStatus = nil; accessStatus = nil; buildMenu(); rebuildMain() }
    @objc func toggleTheme() { snapshotInput(); appearance = panel.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? .light:.dark; defaults.set(appearance.rawValue,forKey:"appearance"); applyAppearance(); rebuildMain() }
    func applyAppearance() { let value:NSAppearance? = appearance == .system ? nil : NSAppearance(named:appearance == .dark ? .darkAqua:.aqua); NSApp.appearance = value; panel?.appearance = value; settings?.appearance = value }
    func availabilityMessage(_ r:Recommendation) -> String? {
        if installations[r.model.client] == nil { return tr("未安装 · 可查看建议","Not installed · Reference only") }
        if !enabled.contains(r.model.client) { return tr("客户端未启用","App disabled") }
        if Set(defaults.stringArray(forKey:"unavailableModels") ?? []).contains(r.model.key) { return tr("账户未启用此型号","Model disabled for this account") }
        return nil
    }
    @objc func selectCard(_ button:NSButton) { guard !busy else { return }; snapshotInput(); selectedIndex = button.tag; overrideEffort = nil; overrideSurface = nil; notice = .none; rebuildMain() }
    @objc func boldText() { input.toggleTrait(.boldFontMask); snapshotInput(); panel.makeFirstResponder(input) }
    @objc func italicText() { input.toggleTrait(.italicFontMask); snapshotInput(); panel.makeFirstResponder(input) }
    @objc func listText() { let range = input.selectedRange(); let selected = (input.string as NSString).substring(with:range); let lines = selected.components(separatedBy:"\n").map { "• " + $0 }.joined(separator:"\n"); input.insertText(lines,replacementRange:range); snapshotInput(); panel.makeFirstResponder(input) }
    @objc func surfaceSelected(_ control:NSSegmentedControl) { guard !busy, let r = selected else { return }; let values = r.model.surfaces.sorted(); guard values.indices.contains(control.selectedSegment) else { return }; overrideSurface = values[control.selectedSegment]; notice = .manual; snapshotInput(); rebuildMain() }
    @objc func effortSelected(_ control:NSSegmentedControl) { guard !busy, let r = selected, r.model.efforts.indices.contains(control.selectedSegment) else { return }; overrideEffort = r.model.efforts[control.selectedSegment]; notice = .manual; snapshotInput(); rebuildMain() }
    @objc func toggleDetails() { snapshotInput(); detailsExpanded.toggle(); rebuildMain() }
    @objc func recommend() {
        guard !busy else { return }; snapshotInput(); guard !activeTask.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { notice = .problem; detail = tr("请先描述任务。","Describe your task first."); renderStatus(); return }
        let capturedTask = activeTask, snapshot = book!, token = UUID(); operationID = token
        installations = ClientCatalog.discover(); asking = false; recommendations = []; fallback = false; evidenceTerms = []; overrideEffort = nil; overrideSurface = nil
        notice = .working; busy = true; rebuildMain()
        let chosenMode = mode
        operation = Task { [weak self] in
            guard let self = self else { return }
            defer { if self.operationID == token { self.setBusy(false) } }
            do {
                let result = try await RecommendationCoordinator.decide(task:capturedTask,book:snapshot,mode:chosenMode) {
                    guard let key = try KeyVault.load() else { throw RouterError("请先在设置中保存 JEV API Key。") }
                    return try await self.cloud.classify(task:capturedTask,book:snapshot,key:key)
                }
                try Task.checkCancellation(); guard self.operationID == token else { return }
                self.fallback = result.didFallback; self.fallbackReason = result.error ?? ""; self.pendingClassification = result.classification
                if let local = result.offline { self.evidenceTerms = local.matchedTerms }
                if let answer = result.classification, answer.clarification == nil { self.apply(answer) }
                else {
                    self.choices = result.offline?.candidates ?? result.classification?.clarificationCandidates ?? []; self.asking = true
                    self.question = result.classification?.clarifySurface == true ? tr("这次需要哪种工作方式？","What kind of work is needed?") : result.offline?.message ?? tr("请选择这次的主要任务。","Choose the main task for this request.")
                    self.notice = result.didFallback ? .fallback:.clarification
                    if !snapshot.supportsOfflineMatching && chosenMode == .offline { self.notice = .problem; self.detail = tr("旧规则没有离线匹配条件，请选类型或导入新版规则。","The old rulebook has no offline conditions. Choose a category or import newer rules.") }
                    self.audit.record(action: "clarify_" + (result.classification?.source ?? "offline"), version: snapshot.version, outcome: result.didFallback ? "fallback" : result.classification?.clarifySurface == true ? "needs_surface" : "needs_category")
                    self.rebuildMain()
                }
            } catch is CancellationError { if self.operationID == token { self.notice = .canceled; self.renderStatus() } }
            catch { if self.operationID == token { self.notice = .problem; self.detail = error.localizedDescription; self.renderStatus() } }
        }
    }
    @objc func confirmChoice() {
        guard !busy else { return }
        guard let id = manualChoice.selectedItem?.representedObject as? String else { return }
        if id == "__other" { choices = []; pendingClassification = nil; snapshotInput(); rebuildMain(); return }
        if let pending = pendingClassification, pending.clarifySurface {
            asking = false
            apply(Classification(category:pending.category,surface:id,complexity:pending.complexity,classifierModel:pending.classifierModel,clarification:nil,confidence:pending.confidence,source:"manual"))
            return
        }
        let local = book.offline[id]
        let context = local?.surface ?? (["coding","debugging","frontend","testing_review"].contains(id) ? "code" : ["strategy","architecture","simple"].contains(id) ? "discussion":"files")
        let answer = Classification(category:id,surface:pendingClassification?.surface == "unknown" ? context : pendingClassification?.surface ?? context,complexity:pendingClassification?.complexity ?? local?.complexity ?? 1,classifierModel:"",clarification:nil,confidence:nil,source:"manual")
        asking = false; apply(answer)
    }
    func apply(_ classification:Classification) {
        do {
            lastClassification = classification
            recommendations = try RoutingEngine.recommendations(book:book,classification:classification,scope:"all",enabled:Set(ClientID.allCases))
            guard !recommendations.isEmpty else { throw RouterError(tr("当前范围没有可用客户端，请在设置中启用已安装的软件。","No enabled app matches this scope. Enable an installed app in Settings.")) }
            selectedIndex = recommendations.firstIndex(where: { availabilityMessage($0) == nil }) ?? 0; asking = false; overrideEffort = nil; overrideSurface = nil
            notice = fallback ? .fallback:.none; rebuildMain()
            audit.record(action:"recommend_"+classification.source,version:book.version,recommendation:recommendations.first,outcome:fallback ? "fallback":"candidate")
        } catch { notice = .problem; detail = error.localizedDescription; rebuildMain() }
    }
    @objc func prepare() {
        guard !busy, let r = selected, availabilityMessage(r) == nil, let installation = installations[r.model.client] else { return }
        guard input.string == activeTask else { invalidate(); return }
        if !AXIsProcessTrusted() { notice = .problem; detail = tr("请在设置中开启辅助功能，或使用“更多”里的打开与复制。","Enable Accessibility in Settings, or use Open and Copy under More."); renderStatus(); showSettings(); return }
        let task = activeTask, token = UUID(); operationID = token; notice = .working; setBusy(true)
        preparer.progress = { [weak self] _ in guard let self = self, self.operationID == token else { return }; self.notice = .working; self.renderStatus() }
        operation = Task { [weak self] in
            guard let self = self else { return }; defer { if self.operationID == token { self.setBusy(false) } }
            do {
                self.panel.orderOut(nil)
                _ = try await self.preparer.prepare(r,text:task,installation:installation)
                try Task.checkCancellation(); guard self.operationID == token else { return }
                self.notice = .ready; self.lastClient = r.model.client; self.renderStatus()
                self.audit.record(action:"prepare",version:r.ruleVersion,recommendation:r,outcome:"verified")
            } catch {
                guard self.operationID == token else { return }
                self.notice = error is CancellationError ? .canceled:.problem; self.detail = error.localizedDescription
                self.audit.record(action:"prepare",version:r.ruleVersion,recommendation:r,outcome:"manual_required"); self.showPanel()
            }
        }
    }
    @objc func openClient() { guard let r = selected, let installation = installations[r.model.client] else { return }; DesktopPreparer.openOnly(installation); lastClient = r.model.client; notice = .opening; renderStatus() }
    @objc func copyTask() { snapshotInput(); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(activeTask,forType:.string); notice = .copied; renderStatus() }
    func alert(_ title:String,_ message:String) { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.runModal() }

    @objc func showSettings() { if settings == nil { buildSettings() }; updateSettings(); NSApp.activate(ignoringOtherApps:true); settings?.level = .normal; if settings?.isMiniaturized == true { settings?.deminiaturize(nil) }; settings?.makeKeyAndOrderFront(nil); settings?.orderFrontRegardless() }
    func page(_ title:String,_ views:[NSView],_ tabs:NSTabView) {
        let item = NSTabViewItem(identifier:title); item.label = title; let host = NSView(); let s = column(views,spacing:13); s.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(s)
        NSLayoutConstraint.activate([s.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:18),s.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-18),s.topAnchor.constraint(equalTo:host.topAnchor,constant:18),s.bottomAnchor.constraint(lessThanOrEqualTo:host.bottomAnchor,constant:-12)])
        for v in views { v.translatesAutoresizingMaskIntoConstraints = false; v.widthAnchor.constraint(equalTo:s.widthAnchor).isActive = true }; item.view = host; tabs.addTabViewItem(item)
    }
    func buildSettings() {
        let w = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:660),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        w.title = UIStrings.appName + " · " + tr("设置","Settings"); w.isReleasedWhenClosed = false; w.minSize = NSSize(width:800,height:600); w.delegate = self; w.center(); settings = w; applyAppearance()
        let tabs = NSTabView(frame:NSRect(x:12,y:12,width:976,height:625)); tabs.autoresizingMask = [.width,.height]; w.contentView?.addSubview(tabs)
        let key = NSSecureTextField(); key.placeholderString = tr("填写自己的 JEV API Key","Enter your personal JEV API key"); key.setAccessibilityLabel("JEV API Key"); keyField = key; keyStatus = label("",secondary:true)
        page(tr("JEV 连接","JEV connection"),[label(tr("个人 API Key","Personal API key"),size:18),key,row([button(tr("保存","Save"),#selector(saveKey)),button(tr("测试连接","Test connection"),#selector(testKey)),button(tr("删除","Remove"),#selector(deleteKey))]),keyStatus!,label(tr("密钥保存在本机钥匙串，不进入规则或分享包。每个人使用自己的 JEV 账户。","Your key stays in this Mac's keychain, outside shared rules and packages. Each person uses their own JEV account."),secondary:true),label("https://api.typesafe.ai",size:12,secondary:true),label(tr("智能推荐会把本次任务和分类规则发给 JEV，产生你的 API 用量。离线推荐不联网。","AI recommendations send the current task and classification rules to JEV and use your API allowance. Offline rules do not connect."),size:12,secondary:true)],tabs)
        updateButtons = []; clientButtons = [:]; var clients:[NSView] = [label(tr("启用要使用的软件","Enable your apps"),size:18)]
        for c in ClientID.allCases { let b = NSButton(checkboxWithTitle:c.name,target:self,action:#selector(clientToggled(_:))); b.identifier = NSUserInterfaceItemIdentifier(c.rawValue); clientButtons[c] = b; clients.append(b) }
        accessStatus = label("",secondary:true)
        let hk = ShortcutRecorder(title:ShortcutSpec.load(defaults).title,target:self,action:#selector(recordShortcut)); hk.bezelStyle = .rounded; shortcutRecorder = hk
        hk.recorded = { [weak self] spec in self?.saveShortcut(spec) }
        hk.canceled = { [weak self] in guard let self = self else { return }; self.shortcutRecorder?.title = ShortcutSpec.load(self.defaults).title; self.accessStatus?.stringValue = tr("已取消录制，保留原快捷键。","Recording canceled; shortcut unchanged.") }
        hk.invalid = { [weak self] in self?.accessStatus?.stringValue = tr("按一个或两个修饰键，加一个字母、数字或功能键。","Press one or two modifiers plus a letter, number or function key.") }
        let theme = NSPopUpButton(); theme.addItems(withTitles:[tr("跟随系统","System"),tr("浅色","Light"),tr("深色","Dark")]); theme.selectItem(at:[AppearanceChoice.system,.light,.dark].firstIndex(of:appearance) ?? 0); theme.target = self; theme.action = #selector(themeChanged(_:))
        clients += [row([button(tr("重新检测","Refresh"),#selector(detectClients)),button(tr("辅助功能授权…","Accessibility…"),#selector(openAccessibility))]),accessStatus!,row([label(tr("快捷键","Shortcut")),hk,button(tr("恢复默认","Reset"),#selector(resetShortcut)),label(tr("外观","Appearance")),theme]),label(tr("仅打开和复制无需辅助功能。自动准备要在原软件核验型号和档位；随后由你发送。","Open and Copy need no Accessibility access. Automatic preparation verifies the model and effort, then leaves sending to you."),size:12,secondary:true)]
        page(tr("客户端","Apps"),clients,tabs)
        modelsStatus = label("",size:12,secondary:true)
        let modelRefresh = button(tr("更新模型库","Update models"),#selector(refreshPublicData)); updateButtons.append(modelRefresh)
        modelTable = DataTable(columns:[("enabled",tr("启用","Use"),50),("model",tr("模型","Model"),265),("client",tr("客户端 / 厂商","App / provider"),150),("state",tr("状态","Status"),220),("released",tr("发布日期","Released"),100)],height:380)
        modelTable?.toggled = { [weak self] key,on in self?.setModel(key,on:on) }
        page(tr("模型库","Models"),[row([label(tr("账户候选与最新公开模型","Account choices and public models"),size:18),spacerView(),modelRefresh]),modelsStatus!,label(tr("勾选项用于账户可用性。在线新发现不自动进入推荐；需先核验客户端菜单并更新 Markdown 规则。","Checkboxes describe your account. Newly discovered models require app-menu verification and a Markdown rule update before routing."),size:12,secondary:true),modelTable!],tabs)
        priceStatus = label("",size:12,secondary:true)
        let priceRefresh = button(tr("更新价格与汇率","Update prices & FX"),#selector(refreshPublicData)); updateButtons.append(priceRefresh)
        let primaryCurrency = language == .zh ? "CNY":"USD", secondaryCurrency = language == .zh ? "USD":"CNY"
        priceTable = DataTable(columns:[("model",tr("模型","Model"),205),("client",tr("客户端 / 厂商","App / provider"),120),("in1",tr("人民币输入","USD input"),105),("out1",tr("人民币输出 ↓","USD output ↓"),110),("in2",secondaryCurrency + tr(" 输入"," input"),95),("out2",secondaryCurrency + tr(" 输出"," output"),100),("updated",tr("更新 / 核价日","Updated / checked"),120),("source",tr("来源","Source"),120)],height:350)
        _ = primaryCurrency
        page(tr("价格表","Prices"),[row([label(tr("API 参考价格表","API reference prices"),size:18),spacerView(),priceRefresh]),priceStatus!,label(tr("每百万 Token，按输出价格降序、同价按输入价格。两种币种对照，非订阅扣费；换算价不等于各地区实际报价。","Per 1M tokens, output price descending, then input. Currency equivalents are references, not subscription charges or regional offers."),size:12,secondary:true),priceTable!,row([button(tr("导入价格表…","Import prices…"),#selector(importPrices)),button(tr("恢复内置价格","Restore bundled prices"),#selector(restorePrices)),button(tr("撤销上次更新","Undo last update"),#selector(undoPublicUpdate))])],tabs)
        ruleStatus = label("",secondary:true)
        let drop = RuleDropView(frame:.zero); let dl = label(tr("把 Markdown 规则拖到这里","Drop a Markdown rule file here"),secondary:true); dl.translatesAutoresizingMaskIntoConstraints = false; drop.addSubview(dl)
        NSLayoutConstraint.activate([drop.heightAnchor.constraint(equalToConstant:55),dl.centerXAnchor.constraint(equalTo:drop.centerXAnchor),dl.centerYAnchor.constraint(equalTo:drop.centerYAnchor)])
        drop.onFile = { [weak self] u in self?.reviewImport(u) }
        page(tr("规则","Rules"),[label(tr("可分享的 Markdown 规则","Shareable Markdown rules"),size:18),ruleStatus!,drop,row([button(tr("导入","Import"),#selector(importRules)),button(tr("导出","Export"),#selector(exportRules)),button(tr("回退上一版","Roll back"),#selector(rollback))]),button(tr("采用内置新版规则","Use bundled rules"),#selector(restoreBundled)),label(tr("V2 规则包含中英文匹配条件，支持离线推荐。旧规则可以读取，但需要手选类别。先预览变化再应用，密钥与个人设置独立保存。","V2 rules include bilingual matching conditions for offline recommendations. Older rules remain readable but require category selection. Preview changes before applying; keys and preferences are separate."),size:12,secondary:true)],tabs)
    }
    func updateSettings() {
        let hasKey = ((try? KeyVault.load()) ?? nil) != nil
        keyStatus?.stringValue = hasKey ? tr("已保存密钥，填写新值可替换。","A key is saved. Enter a new one to replace it."):tr("尚未配置；离线推荐可以直接使用。","No key configured. Offline rules are available.")
        accessStatus?.stringValue = AXIsProcessTrusted() ? tr("辅助功能已授权，准备时仍会核验。","Accessibility enabled. Preparation still verifies each step."):tr("辅助功能待授权，当前可打开或复制。","Accessibility not enabled. Open and Copy remain available.")
        for (c,b) in clientButtons { b.state = enabled.contains(c) ? .on:.off; b.isEnabled = installations[c] != nil; b.title = c.name + (installations[c].map { " · " + $0.version } ?? tr(" · 未安装"," · Not installed")) }
        refreshTables()
        ruleStatus?.stringValue = tr("当前 ","Current ") + book.version + "\n" + String(book.tasks.count) + tr(" 类任务 · "," categories · ") + (book.supportsOfflineMatching ? tr("支持自动离线匹配","Automatic offline matching"):tr("旧版：按类别推荐","Legacy: category selection"))
    }
    @objc func saveKey() { guard !busy else { return }; do { try KeyVault.save(keyField?.stringValue ?? ""); keyField?.stringValue = ""; mode = .ai; defaults.set(mode.rawValue,forKey:"recommendationMode"); invalidate(); rebuildMain(); updateSettings(); keyStatus?.stringValue = tr("已保存到钥匙串。","Saved to keychain.") } catch { keyStatus?.stringValue = error.localizedDescription } }
    @objc func deleteKey() { guard !busy else { return }; do { try KeyVault.delete(); keyField?.stringValue = ""; mode = .offline; defaults.set(mode.rawValue,forKey:"recommendationMode"); invalidate(); rebuildMain(); updateSettings() } catch { keyStatus?.stringValue = error.localizedDescription } }
    @objc func testKey() {
        guard !busy else { return }; let typed = keyField?.stringValue.trimmingCharacters(in:.whitespacesAndNewlines) ?? "", token = UUID(); operationID = token
        notice = .working; setBusy(true); keyStatus?.stringValue = tr("测试认证…","Testing authentication…")
        operation = Task { [weak self] in
            guard let self = self else { return }; defer { if self.operationID == token { self.notice = .none; self.setBusy(false) } }
            do { let key = typed.isEmpty ? (try KeyVault.load() ?? ""):typed; _ = try await self.cloud.testConnection(key:key); guard self.operationID == token else { return }; self.keyStatus?.stringValue = tr("认证成功；尚未运行真实任务分类。","Authentication succeeded. A real task has not been classified yet.") }
            catch { if self.operationID == token { self.keyStatus?.stringValue = error is CancellationError ? tr("已取消。","Canceled."):error.localizedDescription } }
        }
    }
    @objc func modelToggled(_ b:NSButton) {
        guard !busy else { return }; guard let key = b.identifier?.rawValue else { return }
        var unavailable = Set(defaults.stringArray(forKey:"unavailableModels") ?? [])
        if b.state == .on { unavailable.remove(key) } else { unavailable.insert(key) }
        defaults.set(Array(unavailable),forKey:"unavailableModels"); if let last = lastClassification { apply(last) }
    }
    @objc func importPrices() {
        guard !busy else { return }; let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.title = tr("导入 API 参考价","Import API references")
        guard panel.runModal() == .OK, let url = panel.url else { return }; reviewPrices(url)
    }
    @objc func restorePrices() { guard let url = Bundle.main.url(forResource:"APIPrices",withExtension:"json") else { return }; reviewPrices(url) }
    func reviewPrices(_ url:URL) {
        guard !busy, !refreshing else { return }
        do {
            let next = try PriceBook.read(url); try saveMarket(prices:next,catalog:market)
            priceBook = next; updateMessage = tr("价格已更新，可撤销。","Prices updated. Undo is available."); snapshotInput(); rebuildMain(); refreshTables()
        } catch { updateMessage = error.localizedDescription; refreshTables() }
    }
    func setModel(_ key:String,on:Bool) {
        guard !busy else { return }; var unavailable = Set(defaults.stringArray(forKey:"unavailableModels") ?? [])
        if on { unavailable.remove(key) } else { unavailable.insert(key) }; defaults.set(Array(unavailable),forKey:"unavailableModels")
        if let last = lastClassification { apply(last) }; refreshTables()
    }
    func refreshTables() {
        let unavailable = Set(defaults.stringArray(forKey:"unavailableModels") ?? [])
        var configured:[DataRow] = []; let exact = Dictionary(uniqueKeysWithValues:(market?.models ?? []).map { ($0.key,$0) })
        for model in book.models.values.sorted(by: { $0.client.rawValue == $1.client.rawValue ? $0.key < $1.key:$0.client.rawValue < $1.client.rawValue }) {
            let item = PublicCatalog.bindings[model.key].flatMap { exact[$0] }
            configured.append(DataRow(id:model.key,cells:["model":model.name,"client":model.client.name,"state":tr("已纳入任务规则","In task rules"),"released":item?.released ?? "—"],checked:!unavailable.contains(model.key),canToggle:!busy))
        }
        let known = Set(PublicCatalog.bindings.values)
        configured += (market?.models ?? []).filter { !known.contains($0.key) }.map { DataRow(id:$0.key,cells:["model":$0.name,"client":$0.provider,"state":tr("新发现 · 需菜单与规则核验","Discovered · Verify app and rules"),"released":$0.released.isEmpty ? "—":$0.released]) }
        modelTable?.setRows(configured)
        modelsStatus?.stringValue = (refreshing ? tr("更新中…","Updating…"):updateMessage) + "\n" + tr("目录拉取：","Catalog fetched: ") + (market?.fetchedAt ?? tr("尚未获取","Not fetched")) + tr(" · 来源 Models.dev 社区目录"," · Models.dev community catalog")
        let first = language == .zh ? "CNY":"USD", second = language == .zh ? "USD":"CNY"
        priceTable?.setRows(priceBook.listing(book:book,market:market).map { row in
            let source = row.price?.source.contains("models.dev") == true ? "Models.dev":row.price == nil ? "—":tr("内置/导入参考","Bundled/imported ref")
            return DataRow(id:row.key,cells:["model":row.name,"client":row.client,"in1":row.amount(input:true,currency:first,fx:priceBook.cnyPerUSD),"out1":row.amount(input:false,currency:first,fx:priceBook.cnyPerUSD),"in2":row.amount(input:true,currency:second,fx:priceBook.cnyPerUSD),"out2":row.amount(input:false,currency:second,fx:priceBook.cnyPerUSD),"updated":String(row.date.prefix(10)),"source":source,"sourceURL":row.price?.source ?? ""])
        })
        let fx = String(format:"%.4f",priceBook.cnyPerUSD)
        priceStatus?.stringValue = (refreshing ? tr("更新中…","Updating…"):updateMessage) + "\n" + tr("目录/价格拉取：","Catalog/prices fetched: ") + (priceBook.fetchedAt ?? market?.fetchedAt ?? priceBook.checked) + "\n" + tr("汇率 $1≈¥","FX $1≈¥") + fx + " · " + (priceBook.fxDate ?? tr("固定参考值","Fixed reference")) + " · " + (priceBook.fxSource == nil ? tr("非实时汇率","Not live FX"):"Frankfurter")
        for button in updateButtons { button.isEnabled = !refreshing && !busy }
    }
    func saveMarket(prices:PriceBook,catalog:MarketSnapshot?) throws {
        let path = store.directory.appendingPathComponent("market-state.json"), previous = store.directory.appendingPathComponent("previous-market-state.json")
        let old = MarketCache(market:market,prices:priceBook); try JSONEncoder().encode(old).write(to:previous,options:.atomic)
        try JSONEncoder().encode(MarketCache(market:catalog,prices:prices)).write(to:path,options:.atomic)
    }
    @objc func refreshPublicData() {
        guard !busy, !refreshing else { return }; let token = UUID(); updateID = token; refreshing = true; updateMessage = ""; refreshTables()
        updateTask = Task { [weak self] in
            guard let self = self else { return }; defer { if self.updateID == token { self.refreshing = false; self.refreshTables() } }
            do {
                let result = try await self.updater.fetch(); try Task.checkCancellation(); guard self.updateID == token else { return }
                if result.market == nil && result.fx == nil { self.updateMessage = tr("更新失败，已保留原目录、价格和汇率。","Update failed; previous models, prices and FX were retained."); return }
                let next = PublicCatalog.merge(prices:self.priceBook,market:result.market,fx:result.fx)
                try self.saveMarket(prices:next,catalog:result.market ?? self.market); self.priceBook = next; self.market = result.market ?? self.market
                self.updateMessage = result.failures.isEmpty ? tr("模型、价格与汇率已更新，可撤销。","Models, prices and FX updated. Undo is available."):tr("部分更新成功：","Partial update: ") + result.failures.joined(separator:" · ")
                self.snapshotInput(); self.rebuildMain(); self.audit.record(action:"public_update",version:self.book.version,outcome:result.failures.isEmpty ? "updated":"partial")
            } catch { if self.updateID == token { self.updateMessage = tr("未更新，原数据已保留。","Not updated; previous data retained.") } }
        }
    }
    @objc func undoPublicUpdate() {
        guard !refreshing, !busy else { return }
        do {
            let data = try Data(contentsOf:store.directory.appendingPathComponent("previous-market-state.json")), previous = try JSONDecoder().decode(MarketCache.self,from:data)
            try saveMarket(prices:previous.prices,catalog:previous.market); priceBook = previous.prices; market = previous.market; snapshotInput(); rebuildMain(); updateMessage = tr("已恢复上一次数据。","Previous data restored."); refreshTables()
        } catch { updateMessage = tr("暂无可撤销的更新。","No previous update to restore."); refreshTables() }
    }
    @objc func detectClients() { guard !busy else { return }; installations = ClientCatalog.discover(); updateSettings() }
    @objc func clientToggled(_ b:NSButton) { guard !busy else { return }; guard let raw = b.identifier?.rawValue, let c = ClientID(rawValue:raw) else { return }; if b.state == .on { enabled.insert(c) } else { enabled.remove(c) }; defaults.set(enabled.map(\.rawValue),forKey:"enabledClients"); if let last = lastClassification { apply(last) } }
    @objc func openAccessibility() { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary); NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    @objc func recordShortcut() {
        guard !busy, let recorder = shortcutRecorder else { return }
        recorder.beginRecording(); recorder.title = tr("按下新快捷键…","Press new shortcut…"); settings?.makeFirstResponder(recorder)
        accessStatus?.stringValue = tr("两个或三个键同时按下；Esc 取消。","Press two or three keys together; Esc cancels.")
    }
    @objc func resetShortcut() { shortcutRecorder?.endRecording(); saveShortcut(ShortcutSpec.presets[0]) }
    func saveShortcut(_ spec:ShortcutSpec) {
        if hotkey.register(spec) { defaults.set(try? JSONEncoder().encode(spec),forKey:"customShortcut"); accessStatus?.stringValue = tr("快捷键已更新。","Shortcut updated.") }
        else { accessStatus?.stringValue = tr("快捷键被占用，保留原设置。","Shortcut unavailable; previous setting retained.") }
        shortcutRecorder?.title = ShortcutSpec.load(defaults).title
    }
    @objc func themeChanged(_ p:NSPopUpButton) { snapshotInput(); appearance = [AppearanceChoice.system,.light,.dark][max(0,p.indexOfSelectedItem)]; defaults.set(appearance.rawValue,forKey:"appearance"); applyAppearance(); rebuildMain() }
    @objc func importRules() { guard !busy else { return }; let p = NSOpenPanel(); p.title = tr("导入规则","Import rules"); p.allowedContentTypes = [UTType(filenameExtension:"md") ?? .plainText]; if p.runModal() == .OK, let u = p.url { reviewImport(u) } }
    func reviewImport(_ u:URL) {
        guard !busy else { return }
        do {
            let imported = try MarkdownRules.read(u), a = NSAlert(); a.messageText = tr("规则检查通过","Rules validated"); a.informativeText = imported.changes(from:book)
            a.addButton(withTitle:tr("应用更新","Apply update")); a.addButton(withTitle:tr("取消","Cancel"))
            if a.runModal() == .alertFirstButtonReturn { try store.activate(imported); book = imported; invalidate(); notice = .rules; rebuildMain(); refreshRuleSettings(); audit.record(action:"rule_import",version:book.version,outcome:"activated") }
        } catch { alert(tr("规则未导入","Rules not imported"),error.localizedDescription) }
    }
    @objc func exportRules() { let p = NSSavePanel(); p.title = tr("导出规则","Export rules"); p.allowedContentTypes = [UTType(filenameExtension:"md") ?? .plainText]; p.nameFieldStringValue = "ModelPickerRules-" + book.version + ".md"; if p.runModal() == .OK, let u = p.url { do { try Data(book.markdown.utf8).write(to:u,options:.atomic); ruleStatus?.stringValue = tr("已导出，文件不含密钥或任务内容。","Exported without keys or task content.") } catch { alert(tr("导出失败","Export failed"),error.localizedDescription) } } }
    func refreshRuleSettings() {
        guard let window = settings else { return }
        let wasVisible = window.isVisible, typedKey = keyField?.stringValue ?? ""
        window.close(); settings = nil; buildSettings(); keyField?.stringValue = typedKey; updateSettings()
        if wasVisible { settings?.makeKeyAndOrderFront(nil) }
    }
    @objc func rollback() { guard !busy else { return }; do { book = try store.rollback(); invalidate(); notice = .rules; rebuildMain(); refreshRuleSettings() } catch { ruleStatus?.stringValue = tr("暂无可用的上一版规则。","No previous valid rulebook is available.") } }
    @objc func restoreBundled() { reviewImport(store.bundled) }
    func windowWillClose(_ n:Notification) { if let w = n.object as? NSWindow, w == settings { shortcutRecorder?.endRecording(); shortcutRecorder?.title = ShortcutSpec.load(defaults).title } }
    func windowDidBecomeKey(_ n:Notification) { if settings != nil { updateSettings() } }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool { if panel != nil { showPanel() }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func application(_ sender:NSApplication,openFiles files:[String]) { guard book != nil,files.count == 1 else { return }; showSettings(); reviewImport(URL(fileURLWithPath:files[0])) }
}
@main struct TaskRouterApp {
    @MainActor static func main() { let app = NSApplication.shared; let controller = AppController(); app.delegate = controller; withExtendedLifetime(controller) { app.run() } }
}
