import AppKit
import Carbon

struct ShortcutSpec: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String
    static let presets = [ShortcutSpec(keyCode:49, modifiers:UInt32(controlKey | optionKey), keyLabel:"Space"), ShortcutSpec(keyCode:38, modifiers:UInt32(controlKey | optionKey), keyLabel:"J"), ShortcutSpec(keyCode:38, modifiers:UInt32(controlKey | shiftKey), keyLabel:"J")]
    var title: String {
        var prefix = ""
        if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { prefix += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { prefix += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { prefix += "⌘" }
        return prefix + " " + (keyCode == 49 ? tr("空格","Space"):keyLabel)
    }
    var isValid: Bool {
        let allowed = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let count = [controlKey,optionKey,shiftKey,cmdKey].filter { modifiers & UInt32($0) != 0 }.count
        return (1...2).contains(count) && modifiers & ~allowed == 0 && modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 && keyCode <= 126 && ![54,55,56,57,58,59,60,61,62,63].contains(keyCode) && !keyLabel.isEmpty && keyLabel.count <= 24
    }
    static func from(_ event:NSEvent) -> ShortcutSpec? {
        var flags:UInt32 = 0
        if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
        let labels:[UInt16:String] = [49:"Space",36:"Return",48:"Tab",51:"Delete",53:"Escape",123:"←",124:"→",125:"↓",126:"↑"]
        let result = ShortcutSpec(keyCode:UInt32(event.keyCode),modifiers:flags,keyLabel:labels[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "")
        return result.isValid ? result:nil
    }
    static func load(_ defaults:UserDefaults) -> ShortcutSpec {
        if let data = defaults.data(forKey:"customShortcut"), let value = try? JSONDecoder().decode(Self.self,from:data), value.isValid { return value }
        return presets[max(0,min(2,defaults.integer(forKey:"hotkeyIndex")))]
    }
}
final class Hotkey {
    var handler:EventHandlerRef?; var reference:EventHotKeyRef?; var callback:(() -> Void)?
    private(set) var current:ShortcutSpec?
    init() {
        var event = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _,_,context in
            guard let context = context else { return noErr }
            let owner = Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { owner.callback?() }; return noErr
        },1,&event,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    func register(_ spec:ShortcutSpec) -> Bool {
        guard spec.isValid else { return false }
        if current == spec && reference != nil { return true }
        var next:EventHotKeyRef?
        guard RegisterEventHotKey(spec.keyCode,spec.modifiers,EventHotKeyID(signature:0x4A455652,id:1),GetApplicationEventTarget(),0,&next) == noErr else { return false }
        if let old = reference { UnregisterEventHotKey(old) }; reference = next; current = spec; return true
    }
    deinit { if let reference = reference { UnregisterEventHotKey(reference) }; if let handler = handler { RemoveEventHandler(handler) } }
}
final class ShortcutRecorder:NSButton {
    var recording = false
    private var monitor:Any?
    func beginRecording() {
        endRecording(); recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self = self, self.recording, event.window == self.window else { return event }
            self.keyDown(with:event); return nil
        }
    }
    func endRecording() { recording = false; if let monitor = monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
    deinit { if let monitor = monitor { NSEvent.removeMonitor(monitor) } }
     var recorded:((ShortcutSpec) -> Void)?; var canceled:(() -> Void)?; var invalid:(() -> Void)?
    override var acceptsFirstResponder:Bool { true }
    override func keyDown(with event:NSEvent) {
        guard recording else { super.keyDown(with:event); return }
        if event.keyCode == 53 && event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty { endRecording(); canceled?(); return }
        if let spec = ShortcutSpec.from(event) { endRecording(); recorded?(spec) } else { invalid?() }
    }
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with:event) }; keyDown(with:event); return true
    }
}
