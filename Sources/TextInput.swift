import AppKit

final class FlippedDocumentView:NSView { override var isFlipped:Bool { true } }

final class TaskInput:NSTextView {
    var placeholder = ""
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty { (placeholder as NSString).draw(in:NSRect(x:10,y:10,width:bounds.width-22,height:60),withAttributes:[.font:NSFont.systemFont(ofSize:15),.foregroundColor:NSColor.placeholderTextColor]) }
    }
    func normalizeParagraphs() {
        guard let storage = textStorage else { return }
        let range = NSRange(location:0,length:storage.length)
        var paragraphs:[(NSRange,NSMutableParagraphStyle)] = []
        storage.enumerateAttribute(.paragraphStyle,in:range) { value,range,_ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping; paragraphs.append((range,style))
        }
        for (range,style) in paragraphs { storage.addAttribute(.paragraphStyle,value:style,range:range) }
        storage.addAttribute(.foregroundColor,value:NSColor.textColor,range:range)
        let typing = NSMutableParagraphStyle(); typing.lineBreakMode = .byWordWrapping
        typingAttributes[.paragraphStyle] = typing; typingAttributes[.foregroundColor] = NSColor.textColor
    }
    override func paste(_ sender:Any?) { super.paste(sender); normalizeParagraphs(); enclosingScrollView?.tile() }
    func toggleTrait(_ trait:NSFontTraitMask) {
        guard let storage = textStorage else { return }
        let selected = selectedRange(), manager = NSFontManager.shared
        func hasTrait(_ font:NSFont,attributes:[NSAttributedString.Key:Any]) -> Bool {
            manager.traits(of:font).contains(trait) || (trait == .italicFontMask && ((attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0)
        }
        if selected.length == 0 {
            let base = typingAttributes[.font] as? NSFont ?? .systemFont(ofSize:15)
            let remove = hasTrait(base,attributes:typingAttributes)
            let font = remove ? manager.convert(base,toNotHaveTrait:trait):manager.convert(base,toHaveTrait:trait)
            typingAttributes[.font] = font
            if trait == .italicFontMask { typingAttributes[.obliqueness] = !remove && !manager.traits(of:font).contains(trait) ? 0.2:0.0 }
        } else {
            var runs:[(NSRange,NSFont,[NSAttributedString.Key:Any])] = []
            storage.enumerateAttributes(in:selected) { attributes,range,_ in runs.append((range,attributes[.font] as? NSFont ?? .systemFont(ofSize:15),attributes)) }
            let remove = runs.allSatisfy { hasTrait($0.1,attributes:$0.2) }
            for (range,font,_) in runs {
                let converted = remove ? manager.convert(font,toNotHaveTrait:trait):manager.convert(font,toHaveTrait:trait)
                storage.addAttribute(.font,value:converted,range:range)
                if trait == .italicFontMask { storage.addAttribute(.obliqueness,value:!remove && !manager.traits(of:converted).contains(trait) ? 0.2:0.0,range:range) }
            }
        }
        needsDisplay = true
    }

}
final class TaskScrollView:NSScrollView {
    override func tile() {
        super.tile()
        guard let text = documentView as? NSTextView, let container = text.textContainer else { return }
        let width = max(80,contentSize.width)
        text.minSize = NSSize(width:width,height:contentSize.height)
        text.maxSize = NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)
        if abs(text.frame.width-width) > 0.5 { text.setFrameSize(NSSize(width:width,height:max(text.frame.height,contentSize.height))) }
        let lineWidth = max(60,width - text.textContainerInset.width * 2)
        container.widthTracksTextView = true; container.heightTracksTextView = false
        if abs(container.containerSize.width-lineWidth) > 0.5 { container.containerSize = NSSize(width:lineWidth,height:CGFloat.greatestFiniteMagnitude) }
    }
}
final class RecommendationCard:NSBox {
    let index:Int
    let chooseButton:NSButton
    let modelLabel:NSTextField
    let costLabel:NSTextField
    let isClaude:Bool
    init(index:Int,recommendation:Recommendation,price:String,selected:Bool,availability:String?,target:AnyObject,action:Selector) {
        self.index = index; isClaude = recommendation.model.client == .claude
        let priorities = [tr("第一优先级","1st priority"),tr("第二优先级","2nd priority"),tr("第三优先级","3rd priority"),tr("第四优先级","4th priority")]
        chooseButton = NSButton(radioButtonWithTitle:priorities[min(3,index)],target:target,action:action); chooseButton.tag = index; chooseButton.state = selected ? .on:.off
        chooseButton.setAccessibilityLabel(chooseButton.title + " · " + recommendation.model.name)
        modelLabel = NSTextField(wrappingLabelWithString:recommendation.model.name + " · " + recommendation.effort.title)
        costLabel = NSTextField(wrappingLabelWithString:price)
        super.init(frame:.zero); boxType = .custom; cornerRadius = 8; borderWidth = selected ? 2:1
        borderColor = isClaude ? .systemOrange:(selected ? .controlAccentColor:.separatorColor)
        fillColor = isClaude ? NSColor.systemOrange.withAlphaComponent(selected ? 0.12:0.06):NSColor.controlBackgroundColor
        guard let host = contentView else { return }
        modelLabel.font = .systemFont(ofSize:15,weight:.semibold); costLabel.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular)
        let contexts = ["chat":tr("讨论","Chat"),"office":tr("日常办公","Office"),"work":"Work","cowork":"Cowork","code":"Code","codex":"Codex"]
        let context = NSTextField(wrappingLabelWithString:recommendation.model.client.name + " · " + (contexts[recommendation.surface] ?? recommendation.surface))
        context.font = .systemFont(ofSize:12); context.textColor = .secondaryLabelColor
        let note = NSTextField(wrappingLabelWithString:availability ?? (isClaude ? tr("⚠ 网络与账号提醒","⚠ Account / access notice"):""))
        note.font = .systemFont(ofSize:11); note.textColor = isClaude ? .systemOrange:.secondaryLabelColor; note.isHidden = note.stringValue.isEmpty
        let stack = NSStackView(views:[chooseButton,modelLabel,context,costLabel,note]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:10),stack.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-10),stack.topAnchor.constraint(equalTo:host.topAnchor,constant:8),stack.bottomAnchor.constraint(equalTo:host.bottomAnchor,constant:-8)])
        for label in [modelLabel,context,costLabel,note] { label.translatesAutoresizingMaskIntoConstraints = false; label.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true }
    }
    required init?(coder:NSCoder) { fatalError() }
}
