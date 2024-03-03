import Cocoa
import RFSupport
import SwiftUI

struct QDTextStyle: OptionSet {
    typealias RawValue = UInt8
    
    var rawValue: UInt8
    
    mutating func formUnion(_ other: QDTextStyle) {
        rawValue |= other.rawValue
    }
    
    mutating func formIntersection(_ other: QDTextStyle) {
        rawValue &= other.rawValue
    }
    
    mutating func formSymmetricDifference(_ other: QDTextStyle) {
        rawValue &= ~(rawValue & other.rawValue)
    }
    
    static let plain: QDTextStyle = []
    static let bold = QDTextStyle(rawValue: 1)
    static let italic = QDTextStyle(rawValue: 2)
    static let underline = QDTextStyle(rawValue: 4)
    static let outline = QDTextStyle(rawValue: 8)
    static let shadow = QDTextStyle(rawValue: 16)
    static let condense = QDTextStyle(rawValue: 32)
    static let extend = QDTextStyle(rawValue: 64)
}


class TextEditorWindowController: AbstractEditor, ResourceEditor {
    static let supportedTypes = [
        "TEXT"
    ]
    
    @IBOutlet weak var textView: NSTextView!
    let resource: Resource
    private let manager: RFEditorManager
        
    override var windowNibName: String {
        return "TextEditorWindow"
    }
    
    required init(resource: Resource, manager: RFEditorManager) {
        self.resource = resource
        self.manager = manager
        super.init(window: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func fontFamilyIDToName(_ id: Int16) -> String {
        let fontsTable: [Int16:String] = [
            0: "Silom",
            2: "New York",
            3: "Geneva",
            4: "Monaco",
            5: "Venice",
            6: "London",
            7: "Athens",
            8: "San Francisco",
            9: "Toronto",
            11: "Cairo",
            12: "Los Angeles",
            20: "Times",
            21: "Helvetica",
            22: "Courier",
            23: "Symbol",
            24: "Mobile",
            2003: "Copperplate" // Capitals
        ]
        return fontsTable[id] ?? "Geneva"
    }
    
    func loadResourceIntoView() {
        self.textView.string = String(data: resource.data, encoding: .macOSRoman) ?? ""
        
        do {
            if let styleResource = manager.findResource(type: ResourceType("styl"), id: resource.id, currentDocumentOnly: true) {
                let styleReader = BinaryDataReader(styleResource.data)
                let numRuns: Int16 = try styleReader.read()
                for _ in 1...numRuns {
                    let startOffset: Int32 = try styleReader.read()
                    let lineHeight: Int16 = try styleReader.read()
                    let fontAscent: Int16 = try styleReader.read()
                    let fontFamilyID: Int16 = try styleReader.read()
                    let fontName = fontFamilyIDToName(fontFamilyID)
                    let characterStyle = QDTextStyle(rawValue: try styleReader.read())
                    try styleReader.advance(1)
                    let fontSize: UInt16 = try styleReader.read()
                    let redComponent: UInt16 = try styleReader.read()
                    let greenComponent: UInt16 = try styleReader.read()
                    let blueComponent: UInt16 = try styleReader.read()
                    let color = NSColor(calibratedRed: CGFloat(redComponent) / 65535.0,
                                        green: CGFloat(greenComponent) / 65535.0,
                                        blue: CGFloat(blueComponent) / 65535.0,
                                        alpha: 1.0)
                    styleReader.pushPosition()
                    var endOffset: Int32 = 0
                    if let nextStartOffset: Int32 = try? styleReader.read() {
                        endOffset = nextStartOffset
                    } else {
                        endOffset = Int32(resource.data.count)
                    }
                    styleReader.popPosition()
                    
                    // TODO: Convert MacRoman byte offsets to UTF8 offsets.
                    var font = NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)
                    if characterStyle.contains(.bold) {
                        font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    }
                    if characterStyle.contains(.italic) {
                        let newFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                        if NSFontManager.shared.traits(of: newFont).contains(.italicFontMask) {
                            font = newFont
                        } else {
                            let obliqueTransform = AffineTransform(m11: 1, m12: tan(Angle(degrees: 0.0).radians), m21: tan(Angle(degrees: 20.0).radians), m22: 1, tX: 0, tY: 0)
                            font = NSFont(descriptor: font.fontDescriptor, textTransform: obliqueTransform) ?? font
                        }
                    }
                    if characterStyle.contains(.underline) {
                        self.textView.textStorage?.addAttribute(.underlineStyle, value: 1, range: NSRange(location: Int(startOffset), length: Int(endOffset - startOffset)))
                    }
                    if characterStyle.contains(.condense) {
                        font = NSFontManager.shared.convert(font, toHaveTrait: .condensedFontMask)
                    }
                    if characterStyle.contains(.extend) {
                        font = NSFontManager.shared.convert(font, toHaveTrait: .expandedFontMask)
                    }
                    self.textView.textStorage?.addAttribute(.font, value: font, range: NSRange(location: Int(startOffset), length: Int(endOffset - startOffset)))
                }
            }
        } catch {
            self.window?.presentError(error)
        }

        self.setDocumentEdited(false)
    }
    
    override func windowDidLoad() {
        NotificationCenter.default.addObserver(self, selector: #selector(textFieldDidChange(_:)), name: NSTextStorage.didProcessEditingNotification, object: self.textView.textStorage)
        
        loadResourceIntoView()
    }
        
    @IBAction func saveResource(_ sender: Any) {
//        do {
            resource.data = textView.string.data(using: .macOSRoman, allowLossyConversion: true) ?? Data()
//        } catch {
//            self.window?.presentError(error)
//        }
        
        self.setDocumentEdited(false)
    }
    
    /// Revert the resource to its on-disk state.
    @IBAction func revertResource(_ sender: Any) {
        self.window?.contentView?.undoManager?.removeAllActions()
        loadResourceIntoView()
    }
    
    @objc func textFieldDidChange(_ notification: Notification) {
        self.setDocumentEdited(true)
    }
}
