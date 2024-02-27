import Cocoa
import RFSupport

class MenuItem: NSObject {
    
    enum CommandsSize {
        case none
        case int16
        case int32
    }
    
    static let nameDidChangeNotification = Notification.Name("MENUItemNameDidChangeNotification")
    static let keyEquivalentDidChangeNotification = Notification.Name("MENUItemKeyEquivalentDidChangeNotification")
    static let markCharacterDidChangeNotification = Notification.Name("MENUItemMarkCharacterDidChangeNotification")
    static let styleByteDidChangeNotification = Notification.Name("MENUItemStyleByteDidChangeNotification")
    static let menuCommandDidChangeNotification = Notification.Name("MENUItemCommandByteDidChangeNotification")
    static let enabledDidChangeNotification = Notification.Name("MENUItemEnabledDidChangeNotification")
    static let iconDidChangeNotification = Notification.Name("MENUItemIconDidChangeNotification")
    static let submenuIDDidChangeNotification = Notification.Name("MENUItemSubmenuIDDidChangeNotification")

    @objc dynamic var name = "" {
        didSet {
            NotificationCenter.default.post(name: MenuItem.nameDidChangeNotification, object: self)
        }
    }
    @objc dynamic var iconID = Int(0) {
        didSet {
            if iconID != 0,
               let res = manager.findResource(type: ResourceType("ICON"), id: iconID, currentDocumentOnly: false) {
                res.preview({ img in
                    self.iconImage = img
                })
                NotificationCenter.default.post(name: MenuItem.iconDidChangeNotification, object: self) // This is *only* the change of the icon ID. Image loading isn't a change (otherwise every resource would open and immediately be edited)
            } else {
                self.iconImage = nil
                NotificationCenter.default.post(name: MenuItem.iconDidChangeNotification, object: self)
            }
        }
    }
    @objc dynamic var submenuID = Int(0) {
        didSet {
            NotificationCenter.default.post(name: MenuItem.submenuIDDidChangeNotification, object: self)
        }
    }
    @objc dynamic var keyEquivalent = "" {
        didSet {
            NotificationCenter.default.post(name: MenuItem.keyEquivalentDidChangeNotification, object: self)
        }
    }
    @objc dynamic var markCharacter = "" {
        didSet {
            NotificationCenter.default.post(name: MenuItem.markCharacterDidChangeNotification, object: self)
        }
    }
    @objc dynamic var styleByte = UInt8(0) {
        didSet {
            NotificationCenter.default.post(name: MenuItem.styleByteDidChangeNotification, object: self)
        }
    }
    @objc dynamic var menuCommand = UInt32(0) {
        didSet {
            NotificationCenter.default.post(name: MenuItem.menuCommandDidChangeNotification, object: self)
        }
    }
    let commandsSize: CommandsSize
    
    @objc dynamic var isEnabled: Bool = true {
        didSet {
            NotificationCenter.default.post(name: MenuItem.enabledDidChangeNotification, object: self)
        }
    }
    
    @objc dynamic var iconImage: NSImage?
    @objc dynamic var iconType: UInt8

    @objc dynamic var hasKeyEquivalent: Bool {
        return !keyEquivalent.isEmpty
    }
    
    @objc dynamic var has4CCCommand: Bool {
        return commandsSize == .int32
    }

    @objc dynamic var hasInt16Command: Bool {
        return commandsSize == .int16
    }

    let manager: RFEditorManager
    
    internal init(name: String = "", iconID: Int = Int(0), iconType: UInt8 = 0, keyEquivalent: String = "", markCharacter: String = "", styleByte: UInt8 = UInt8(0), menuCommand: UInt32 = UInt32(0), isEnabled: Bool = true, submenuID: Int = 0, commandsSize: CommandsSize, manager: RFEditorManager) {
        self.name = name
        self.iconID = iconID
        self.iconType = iconType
        self.keyEquivalent = keyEquivalent
        self.markCharacter = markCharacter
        self.styleByte = styleByte
        self.menuCommand = menuCommand
        self.isEnabled = isEnabled
        self.submenuID = submenuID
        self.commandsSize = commandsSize
        self.manager = manager
        
        super.init()
        
        if iconID != 0,
           let res = manager.findResource(type: ResourceType("ICON"), id: iconID, currentDocumentOnly: false) {
            res.preview({ img in
                self.iconImage = img
            })
        }

    }
    
    @objc dynamic var menu4CCCommand: String {
        set {
            if commandsSize == .int32 {
                menuCommand = UInt32(fourCharString: newValue)
            }
        }
        get {
            if commandsSize == .int32 {
                return menuCommand.fourCharString
            } else {
                return ""
            }
        }
    }
    @objc dynamic var menuInt16Command: UInt16 {
        set {
            if commandsSize == .int16 {
                menuCommand = UInt32(newValue)
            }
        }
        get {
            if commandsSize == .int16 {
                return UInt16(menuCommand)
            } else {
                return 0
            }
        }
    }
    
    @objc dynamic var textColor: NSColor {
        isEnabled ? NSColor.textColor : NSColor.disabledControlTextColor
    }
}

// So menu and menu item can be treated identically by UI.
extension MenuItem {
    @objc dynamic var menuID: Int16 { return 0 }
    @objc dynamic var mdefID: Int16 { return 0 }
    
    @objc dynamic var isItem: Bool { return true }
    
    override func setNilValueForKey(_ key: String) {
        if key == "submenuID" {
            submenuID = 0
        } else if key == "iconID" {
            iconID = 0
        } else if key == "menuCommand" {
            menuCommand = 0
        } else {
            super.setNilValueForKey(key)
        }
    }
}

extension MenuItem {
    override var description: String {
        return "\(self.className)(name = \"\(name)\", keyEquivalent = \"\(keyEquivalent)\", markCharacter = \"\(markCharacter)\")"
    }
}
