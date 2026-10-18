import AppKit

@discardableResult
func settingsLabel(_ value: String, in parent: NSView, frame: NSRect, size: CGFloat = 12, color: NSColor? = nil, weight: NSFont.Weight = .regular) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: value)
    label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color ?? .labelColor
    label.frame = frame; label.setAccessibilityLabel(value); parent.addSubview(label)
    return label
}
final class SettingsGroupView: FlippedView {
    let rows: Int
    init(frame: NSRect, rows: Int) { self.rows = rows; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func draw(_ dirtyRect: NSRect) {
        fill(bounds.insetBy(dx: 0.5, dy: 0.5), NSColor(white: Ink.dark ? 0.18 : 1, alpha: 0.9), radius: 9)
        Ink.line.setStroke(); NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9).stroke()
        for row in 1..<max(1, rows) { fill(NSRect(x: 12, y: CGFloat(row) * 44, width: bounds.width - 24, height: 0.5), Ink.line) }
    }
}
final class ActionSwitch: NSSwitch {
    var callback: ((Bool) -> Void)?
    init(frame: NSRect, label: String, enabled: Bool, action: @escaping (Bool) -> Void) {
        super.init(frame: frame); state = enabled ? .on : .off; callback = action; target = self; self.action = #selector(changed)
        controlSize = .small; identifier = NSUserInterfaceItemIdentifier(label); setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    @objc private func changed() { callback?(state == .on) }
}
final class ActionPopup: NSPopUpButton {
    var callback: ((String) -> Void)?
    init(frame: NSRect, label: String, choices: [(String, String)], selected: String, action: @escaping (String) -> Void) {
        super.init(frame: frame, pullsDown: false); font = .systemFont(ofSize: 12); callback = action
        for (value, title) in choices { addItem(withTitle: title); lastItem?.representedObject = value }
        if let item = itemArray.first(where: { $0.representedObject as? String == selected }) { select(item) }
        target = self; self.action = #selector(changed); identifier = NSUserInterfaceItemIdentifier(label); setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    @objc private func changed() { if let value = selectedItem?.representedObject as? String { callback?(value) } }
}
final class PinButton: NSButton {
    var callback: (() -> Void)?
    init(frame: NSRect, name: String, pinned: Bool, action: @escaping () -> Void) {
        super.init(frame: frame); isBordered = false; state = pinned ? .on : .off; callback = action; target = self; self.action = #selector(invoke)
        toolTip = pinned ? L("取消置顶 %@", name) : L("置顶 %@", name); setAccessibilityLabel(toolTip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    @objc private func invoke() { callback?() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        if state == .on { fill(bounds.insetBy(dx: 2, dy: 2), Ink.green.withAlphaComponent(0.07), radius: 5) }
        drawPin(in: NSRect(x: bounds.midX - 5, y: bounds.midY - 5.5, width: 10, height: 11), color: state == .on ? Ink.green : Ink.secondary)
    }
}

final class WebsiteDragHandle: FlippedView, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("app.umamibar.website-order")
    let website: Website
    var enabled = true
    init(website: Website, frame: NSRect) { self.website = website; super.init(frame: frame); setAccessibilityLabel(L("拖动调整 %@ 顺序", website.name)) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func draw(_ dirtyRect: NSRect) {
        for x in [bounds.midX - 2.0, bounds.midX + 2.0] {
            for y in [bounds.midY - 4.0, bounds.midY, bounds.midY + 4.0] { fill(NSRect(x: x, y: y, width: 1.5, height: 1.5), Ink.secondary.withAlphaComponent(enabled ? 0.5 : 0.18), radius: 0.75) }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        let item = NSPasteboardItem(); item.setString(website.id, forType: Self.pasteboardType)
        let drag = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: NSSize(width: 180, height: 32), flipped: true) { rect in
            fill(rect, NSColor.windowBackgroundColor, radius: 6)
            text(self.website.name, NSRect(x: 10, y: 7, width: 160, height: 18), size: 12)
            return true
        }
        drag.setDraggingFrame(NSRect(x: -150, y: -6, width: 180, height: 32), contents: image)
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
}

final class WebsiteSettingsRow: FlippedView {
    let website: Website
    var canDrop: ((String) -> Bool)?
    var onDrop: ((String, Bool) -> Void)?
    private var dropAfter: Bool?
    init(frame: NSRect, website: Website, selected: Bool, pinned: Bool, color: Int, draggable: Bool, canMoveUp: Bool, canMoveDown: Bool, onToggle: @escaping (Bool) -> Void, onPin: @escaping () -> Void, onMove: @escaping (Int) -> Void, onColor: @escaping (Int) -> Void) {
        self.website = website; super.init(frame: frame)
        let check = CallbackCheckbox(frame: NSRect(x: 10, y: 17, width: 18, height: 20), label: L("关注 %@", website.name), checked: selected, action: onToggle)
        addSubview(check)
        let name = settingsLabel(website.name, in: self, frame: NSRect(x: 36, y: 8, width: bounds.width - 154, height: 18), size: 12, weight: .medium)
        name.toolTip = website.name
        let domain = settingsLabel(website.domain, in: self, frame: NSRect(x: 36, y: 28, width: bounds.width - 132, height: 16), size: 10, color: .secondaryLabelColor)
        domain.toolTip = website.domain
        if selected {
            let nameWidth = min(bounds.width - 154, ceil((website.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width))
            let swatch = ColorSwatch(color: color, frame: NSRect(x: 39 + nameWidth, y: 7, width: 18, height: 18)); swatch.diameter = 6; swatch.onPick = onColor; addSubview(swatch)
            addSubview(PinButton(frame: NSRect(x: bounds.width - 84, y: 13, width: 28, height: 28), name: website.name, pinned: pinned, action: onPin))
            let up = PaintedButton("⌃", frame: NSRect(x: bounds.width - 52, y: 8, width: 20, height: 18)) { onMove(-1) }
            up.isEnabled = canMoveUp; up.setAccessibilityLabel(L("向上移动 %@", website.name)); addSubview(up)
            let down = PaintedButton("⌄", frame: NSRect(x: bounds.width - 52, y: 28, width: 20, height: 18)) { onMove(1) }
            down.isEnabled = canMoveDown; down.setAccessibilityLabel(L("向下移动 %@", website.name)); addSubview(down)
            let handle = WebsiteDragHandle(website: website, frame: NSRect(x: bounds.width - 26, y: 9, width: 18, height: 36)); handle.enabled = draggable; addSubview(handle)
        }
        registerForDraggedTypes([WebsiteDragHandle.pasteboardType])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let id = sender.draggingPasteboard.string(forType: WebsiteDragHandle.pasteboardType), canDrop?(id) == true else { return [] }
        dropAfter = convert(sender.draggingLocation, from: nil).y >= bounds.midY; needsDisplay = true
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropAfter = nil; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let id = sender.draggingPasteboard.string(forType: WebsiteDragHandle.pasteboardType), canDrop?(id) == true else { return false }
        let after = dropAfter ?? false; dropAfter = nil; needsDisplay = true; onDrop?(id, after); return true
    }
    override func draw(_ dirtyRect: NSRect) {
        fill(NSRect(x: 12, y: bounds.height - 0.5, width: bounds.width - 24, height: 0.5), Ink.line)
        if let after = dropAfter { fill(NSRect(x: 8, y: after ? bounds.height - 2 : 0, width: bounds.width - 16, height: 2), Ink.green, radius: 1) }
    }
}
final class CallbackCheckbox: NSButton {
    var callback: ((Bool) -> Void)?
    init(frame: NSRect, label: String, checked: Bool, action: @escaping (Bool) -> Void) {
        super.init(frame: frame); setButtonType(.switch); title = ""; state = checked ? .on : .off
        setAccessibilityLabel(label); target = self; self.action = #selector(changed); callback = action
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    @objc private func changed() { callback?(state == .on) }
}
