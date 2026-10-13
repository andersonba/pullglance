import AppKit

/// The address field with its own suggestions list, every key handled explicitly, the way browsers do it.
/// Rules taken from DuckDuckGo's address bar (Apache-2.0, behaviour reimplemented, not copied):
///
/// - inline completion only when the user *appends at the end* of the text and the text has no space; the
///   added part is selected, so typing replaces it, Backspace removes it, and nothing re-completes because
///   the insertion is no longer at the end. Pasting in the middle, moving the caret or deleting never completes.
/// - ↓/↑ move the highlight and put that item in the field; past the end or the top they return to "none"
///   and restore what was typed; → and Tab accept and keep editing; Enter opens (ignored while an input
///   method has marked text); ⌘Enter opens in the default browser; Esc closes the list, then restores.
/// - ranking: URL prefix first (root of the site higher), then title prefix, then substring; visits break ties.
/// - the field editor turns off everything AppKit does on its own (smart quotes, predictions, spelling).
@MainActor
final class AddressBarController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let field: NSTextField
    /// Visited pages with counts; the completion and ranking source.
    var history: [String: HistoryEntry] = [:] { didSet { if isEditing { refresh() } } }
    /// What the app knows: owners and repositories (play the role of bookmarks).
    var known: [String] = [] { didSet { if isEditing { refresh() } } }
    /// The pull requests on screen, with their titles.
    var pullRequests: [(url: String, title: String)] = [] { didSet { if isEditing { refresh() } } }
    /// What the page really is; shown when not editing, restored on Esc or click away.
    var pageURL: String = "" { didSet { if !isEditing { showPageURL() } } }
    private let navigate: (String, _ inBrowser: Bool) -> Void

    struct HistoryEntry: Codable {
        var visits: Int
        var lastVisit: Date
        var title: String?
    }

    private struct Row { let section: String; let value: String; let title: String?; var display: String { AddressBarController.display(value) } }
    private var rows: [Row] = []
    private var highlighted: Int? = nil
    /// The text as typed by the user, before any completion or highlight replaced it.
    private var typedText = ""
    private var inlineRange: NSRange? = nil
    private var isEditing: Bool { field.currentEditor() != nil }
    /// Set by the field editor around each insertion: was it appended at the end of the text?
    fileprivate var appendingAtEnd = false

    private let panel: NSPanel
    private let table = NSTableView()
    private var frameObservation: NSObjectProtocol?

    init(field: NSTextField, navigate: @escaping (String, Bool) -> Void) {
        self.field = field
        self.navigate = navigate
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        field.delegate = self
        (field.cell as? AddressFieldCell)?.editor.controller = self
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        let column = NSTableColumn(identifier: .init("suggestion"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 26
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        effect.addSubview(scroll)
        scroll.frame = effect.bounds
        scroll.autoresizingMask = [.width, .height]
        panel.contentView = effect
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        table.addTrackingArea(tracking)
    }

    nonisolated static func display(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "www.", with: "")
    }

    // MARK: history

    func recordVisit(_ url: String, title: String?) {
        var entry = history[url] ?? HistoryEntry(visits: 0, lastVisit: .distantPast, title: nil)
        entry.visits += 1
        entry.lastVisit = Date()
        if let title, !title.isEmpty { entry.title = title }
        history[url] = entry
        // Keep it bounded: three months, like browsers prune.
        let cutoff = Date().addingTimeInterval(-90 * 86_400)
        history = history.filter { $0.value.lastVisit > cutoff }
    }

    // MARK: display

    /// The scheme-less form, the same text the user edits. The field never swaps its text when editing
    /// begins: a longer string under an unchanged caret made Backspace delete eight characters early.
    /// (Host/path coloring needs a second, passive field, as DuckDuckGo does; later.)
    private func showPageURL() {
        field.stringValue = Self.display(pageURL)
    }

    // MARK: suggestions

    /// DuckDuckGo-style score: URL prefix (+300, root of the site +2000), title prefix (+200), domain or
    /// title substring (+150/+100); visits break ties. Zero means no match.
    private func score(url: String, title: String?, query: String, visits: Int) -> Int {
        let naked = Self.display(url).lowercased()
        let q = query.lowercased()
        var score = 0
        let isRoot = !naked.dropFirst("github.com/".count).contains("/") || naked.hasSuffix("/")
        if naked.hasPrefix(q) || naked.dropFirst("github.com/".count).hasPrefix(q) {
            score += 300; if isRoot { score += 2000 }
        } else if let title, title.lowercased().hasPrefix(q) {
            score += 200
        } else if q.count > 2, naked.contains(q) {
            score += 150
        } else if q.count > 2, let title, title.lowercased().contains(" " + q) {
            score += 100
        }
        if score > 0 { score = (score << 10) + visits }
        return score
    }

    private func compute(for query: String) -> [Row] {
        let needle = Self.display(query)
        func ranked(_ candidates: [(url: String, title: String?, visits: Int)], _ section: String, _ limit: Int) -> [Row] {
            candidates
                .map { ($0, needle.isEmpty ? $0.visits : score(url: $0.url, title: $0.title, query: needle, visits: $0.visits)) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map { Row(section: section, value: $0.0.url, title: $0.0.title) }
        }
        let recent = ranked(history.map { ($0.key, $0.value.title, $0.value.visits) }, String(localized: "Recent", bundle: .app), 6)
        let prs = ranked(pullRequests.map { ($0.url, $0.title, 0) }, String(localized: "Pull request", bundle: .app), 6)
        let owners = ranked(known.filter { $0.split(separator: "/").count == 3 }.map { ($0, nil, 0) }, String(localized: "Owner", bundle: .app), 4)
        let repos = ranked(known.filter { $0.split(separator: "/").count > 3 && !$0.hasSuffix("/pulls") }.map { ($0, nil, 0) }, String(localized: "Repository", bundle: .app), 6)
        var seen = Set<String>()
        return (recent + prs + owners + repos).filter { seen.insert(Self.display($0.value).lowercased()).inserted }
    }

    private func refresh() {
        rows = compute(for: typedText)
        highlighted = nil
        table.reloadData()
        rows.isEmpty ? hidePanel() : showPanel()
    }

    /// The part of `candidate` beyond what was typed, when typed is a prefix (scheme aside, or of the path).
    private func completion(of candidate: String, typed: String) -> String? {
        let t = Self.display(typed).lowercased()
        guard !t.isEmpty else { return nil }
        let c = Self.display(candidate)
        if c.lowercased().hasPrefix(t) { return String(c.dropFirst(t.count)) }
        let path = String(c.dropFirst("github.com/".count))
        if path.lowercased().hasPrefix(t) { return String(path.dropFirst(t.count)) }
        return nil
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        typedText = field.stringValue
        inlineRange = nil
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let editor = field.currentEditor() else { return }
        typedText = field.stringValue
        inlineRange = nil
        refresh()
        // Complete only when the user appended at the end and the text has no space (DuckDuckGo's rule).
        guard appendingAtEnd, !typedText.contains(" "), let first = rows.first,
              let extra = completion(of: first.value, typed: typedText), !extra.isEmpty else { return }
        let caret = typedText.count
        field.stringValue = typedText + extra
        inlineRange = NSRange(location: caret, length: extra.count)
        editor.selectedRange = inlineRange!
        highlighted = 0
        table.selectRowIndexes([0], byExtendingSelection: false)
    }

    /// Clicking away restores the page address; Return and Tab are handled in `doCommandBy` and never get here.
    func controlTextDidEndEditing(_ notification: Notification) {
        hidePanel()
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        if movement != NSTextMovement.return.rawValue { showPageURL() }
    }

    // MARK: keys

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            guard panel.isVisible, !rows.isEmpty else { return false }
            let next = (highlighted ?? -1) + 1
            next < rows.count ? highlight(next, textView: textView) : clearHighlight(textView: textView)
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard panel.isVisible, !rows.isEmpty else { return false }
            if let highlighted, highlighted > 0 { highlight(highlighted - 1, textView: textView) }
            else if highlighted == 0 { clearHighlight(textView: textView) }
            else { highlight(rows.count - 1, textView: textView) }
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveToEndOfLine(_:)):
            // Accept what is inline-completed (or, for Tab, highlighted); stay in the field, caret at the end.
            if let inlineRange, textView.selectedRange() == inlineRange {
                acceptCompletion(textView: textView)
                return true
            }
            if selector == #selector(NSResponder.insertTab(_:)) {
                if let highlighted, rows.indices.contains(highlighted) { field.stringValue = rows[highlighted].value }
                textView.setSelectedRange(NSRange(location: field.stringValue.count, length: 0))
                return true
            }
            return false
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            guard !textView.hasMarkedText() else { return false }   // an input method is composing
            // Enter opens what is in the field: typed text, inline completion, or the highlighted row.
            let inBrowser = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
            let target = field.stringValue
            hidePanel()
            field.window?.makeFirstResponder(nil)
            navigate(target, inBrowser)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if panel.isVisible { hidePanel(); return true }
            showPageURL()
            field.window?.makeFirstResponder(nil)
            return true
        case #selector(NSResponder.deleteToEndOfParagraph(_:)):
            // ⌘⌦ clears to the end and drops any highlight.
            let caret = textView.selectedRange().location
            field.stringValue = String(field.stringValue.prefix(caret))
            typedText = field.stringValue
            inlineRange = nil
            clearHighlight(textView: textView)
            return true
        default:
            return false
        }
    }

    private func acceptCompletion(textView: NSTextView) {
        textView.setSelectedRange(NSRange(location: field.stringValue.count, length: 0))
        typedText = field.stringValue
        inlineRange = nil
    }

    private func highlight(_ index: Int, textView: NSTextView) {
        highlighted = index
        inlineRange = nil
        table.selectRowIndexes([index], byExtendingSelection: false)
        table.scrollRowToVisible(index)
        field.stringValue = rows[index].value
        textView.setSelectedRange(NSRange(location: field.stringValue.count, length: 0))
    }

    /// Past the end of the list: nothing highlighted and the typed text back in the field.
    private func clearHighlight(textView: NSTextView) {
        highlighted = nil
        inlineRange = nil
        table.deselectAll(nil)
        field.stringValue = typedText
        textView.setSelectedRange(NSRange(location: typedText.count, length: 0))
    }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard rows.indices.contains(row) else { return }
        hidePanel()
        field.stringValue = rows[row].value
        field.window?.makeFirstResponder(nil)
        navigate(rows[row].value, false)
    }

    @objc func mouseMoved(with event: NSEvent) {
        let point = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: point)
        guard row >= 0, row != highlighted else { return }
        highlighted = row
        table.selectRowIndexes([row], byExtendingSelection: false)
    }

    // MARK: panel

    private func showPanel() {
        guard let window = field.window else { return }
        let height = min(CGFloat(rows.count) * 28 + 8, 340)
        let fieldFrame = field.convert(field.bounds, to: nil)
        var origin = window.convertPoint(toScreen: NSPoint(x: fieldFrame.minX, y: fieldFrame.minY))
        origin.y -= height + 4
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: fieldFrame.width, height: height), display: true)
        if !panel.isVisible { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
        if frameObservation == nil {
            // Follow the window while the list is open.
            frameObservation = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in if self?.panel.isVisible == true { self?.showPanel() } }
            }
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        highlighted = nil
        if let frameObservation { NotificationCenter.default.removeObserver(frameObservation) }
        frameObservation = nil
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let item = rows[row]
        // The part that matches what was typed stays regular; the rest is bold, like browsers do.
        let text = item.display
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        let typed = Self.display(typedText).lowercased()
        if !typed.isEmpty, let range = text.lowercased().range(of: typed) {
            attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: NSRange(range, in: text))
        }
        let title = NSTextField(labelWithAttributedString: attributed)
        title.lineBreakMode = .byTruncatingMiddle
        let secondary = NSTextField(labelWithString: item.title.map { String($0.prefix(60)) } ?? item.section)
        secondary.font = .systemFont(ofSize: 11)
        secondary.textColor = .secondaryLabelColor
        secondary.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, secondary])
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        secondary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.topAnchor),
            stack.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}

/// The field editor that tells the controller where text is inserted and keeps AppKit's automatic text
/// features out of an address (smart quotes, dashes, spelling, inline predictions).
final class AddressFieldEditor: NSTextView {
    weak var controller: AddressBarController?

    override var smartInsertDeleteEnabled: Bool { get { false } set {} }
    override var isAutomaticQuoteSubstitutionEnabled: Bool { get { false } set {} }
    override var isAutomaticDashSubstitutionEnabled: Bool { get { false } set {} }
    override var isAutomaticTextReplacementEnabled: Bool { get { false } set {} }
    override var isAutomaticSpellingCorrectionEnabled: Bool { get { false } set {} }
    override var isAutomaticTextCompletionEnabled: Bool { get { false } set {} }
    override var isContinuousSpellCheckingEnabled: Bool { get { false } set {} }
    override var isAutomaticLinkDetectionEnabled: Bool { get { false } set {} }
    override var inlinePredictionType: NSTextInputTraitType { get { .no } set {} }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        controller?.appendingAtEnd = range.upperBound >= (self.string as NSString).length
        super.insertText(string, replacementRange: replacementRange)
        controller?.appendingAtEnd = false
    }

    /// A URL on the pasteboard pastes as its plain string, never as a styled link.
    override func paste(_ sender: Any?) {
        if let url = NSPasteboard.general.readObjects(forClasses: [NSURL.self])?.first as? URL {
            insertText(url.absoluteString, replacementRange: selectedRange())
        } else {
            super.pasteAsPlainText(sender)
        }
    }
}

final class AddressFieldCell: NSTextFieldCell {
    let editor = AddressFieldEditor()
    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

/// An `NSTextField` whose cell is `AddressFieldCell` (the cell class must be set before the cell exists).
final class AddressField: NSTextField {
    override class var cellClass: AnyClass? { get { AddressFieldCell.self } set {} }
}
