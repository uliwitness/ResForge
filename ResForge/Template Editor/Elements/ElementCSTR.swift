import Cocoa
import RFSupport

enum StringPadding {
    case none
    case odd
    case even
    case fixed(_ count: Int)

    func length(_ currentLength: Int) -> Int {
        switch self {
        case .none:
            return 0
        case .odd:
            return (currentLength+1) % 2
        case .even:
            return currentLength % 2
        case let .fixed(count):
            return count - currentLength
        }
    }
}

// Implements CSTR, OCST, ECST, Cnnn
class ElementCSTR: CasedElement {
    @objc var value = ""
    var maxLength = Int(UInt32.max)
    var padding = StringPadding.none
    var insertLineBreaks = false

    required init(type: String, label: String) {
        super.init(type: type, label: label)
        self.configurePadding()
        width = 240
        insertLineBreaks = maxLength > 256
    }

    override func configure() throws {
        try super.configure()
        if cases.isEmpty && maxLength > 32 {
            width = 0
        }
    }

    func configurePadding() {
        switch type {
        case "CSTR":
            padding = .none
        case "OCST":
            padding = .odd
        case "ECST":
            padding = .even
        default:
            // Assume Xnnn for anything else
            let nnn = BaseElement.variableTypeValue(type)
            // Use resorcerer's more consistent n = datalength rather than resedit's n = stringlength
            padding = .fixed(nnn)
            maxLength = nnn-1
        }
    }

    override func configure(view: NSView) {
        super.configure(view: view)
        let textField = view.subviews.last as! NSTextField
        if maxLength < UInt32.max {
            textField.placeholderString = "\(type) (\(maxLength) characters)"
        }
        if width == 0 {
            textField.lineBreakMode = .byWordWrapping
            DispatchQueue.main.async {
                textField.autoresizingMask = [.width, .height]
                self.autoRowHeight(textField)
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if width == 0, let field = obj.object as? NSTextField {
            self.autoRowHeight(field)
        }
    }

    // Insert new line with return key instead of ending editing (this would otherwise require opt+return)
    override func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if insertLineBreaks && commandSelector == #selector(NSTextView.insertNewline(_:)) {
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        }
        return super.control(control, textView: textView, doCommandBy: commandSelector)
    }

    private func autoRowHeight(_ field: NSTextField) {
        guard let outline = parentList?.controller?.dataList else {
            return
        }
        let index = outline.row(for: field)
        if index != -1 {
            let frame = field.cell!.expansionFrame(withFrame: NSRect(x: 0, y: 0, width: field.frame.size.width-4, height: 0), in: field)
            let height = Double(frame.height) + 7
            if height != rowHeight {
                rowHeight = height
                // In case we're not our own row...
                (outline.item(atRow: index) as? BaseElement)?.rowHeight = height
                // Notify the outline view without animating
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0
                outline.noteHeightOfRows(withIndexesChanged: [index])
                NSAnimationContext.endGrouping()
            }
        }
    }

    override func readData(from reader: BinaryDataReader) throws {
        // Get offset to null
        let end = reader.data[reader.position...].firstIndex(of: 0) ?? reader.data.endIndex
        let length = min(end - reader.position, maxLength)

        value = try reader.readString(length: length, encoding: .macOSRoman)
        // Advance over null-terminator and any additional padding
        try reader.advance(1 + padding.length(length + 1))
    }

    override func writeData(to writer: BinaryDataWriter) {
        if value.count > maxLength {
            value = String(value.prefix(maxLength))
        }

        // Error shouldn't happen because the formatter won't allow non-MacRoman characters
        try? writer.writeString(value, encoding: .macOSRoman)
        writer.advance(1 + padding.length(value.count + 1))
    }

    override var formatter: Formatter {
        self.sharedFormatter {
            MacRomanFormatter(stringLength: maxLength, convertLineEndings: insertLineBreaks)
        }
    }
}
