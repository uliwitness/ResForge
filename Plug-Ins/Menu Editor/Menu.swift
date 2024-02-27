import Cocoa

class Menu: NSObject {
    static let nameDidChangeNotification = Notification.Name("MENUNameDidChangeNotification")
    static let enabledDidChangeNotification = Notification.Name("MENUEnabledDidChangeNotification")

    @objc dynamic var menuID: Int16 = 128
    @objc dynamic var mdefID: Int16 = 0
    var enableFlags: UInt32 = UInt32.max
    @objc dynamic var isEnabled: Bool {
        set(newValue) {
            setEnabled(newValue, at: -1)
            NotificationCenter.default.post(name: Menu.nameDidChangeNotification, object: self)
        }
        get {
            return isEnabled(at: -1)
        }
    }
    @objc dynamic var name = "New Menu" {
        didSet {
            NotificationCenter.default.post(name: Menu.nameDidChangeNotification, object: self)
        }
    }
    var items = [MenuItem]()
    
    internal init(menuID: Int16 = 128, mdefID: Int16 = 0, enableFlags: UInt32 = UInt32.max, name: String = "New Menu", items: [MenuItem] = [MenuItem]()) {
        self.menuID = menuID
        self.mdefID = mdefID
        self.enableFlags = enableFlags
        self.name = name
        self.items = items
    }
    
    /// Change the enable state of the given item. -1 changes the menu itself, as does ``isEnabled``.
    /// - warning: This doesn't send notifications.
    func setEnabled(_ state: Bool, at index: Int) {
        guard index < 32 else { return }
        if state {
            enableFlags |= (1 << (index + 1))
        } else {
            enableFlags &= ~(1 << (index + 1))
        }
    }
    
    /// Is the given item enabled? -1 gives the menu itself, as does ``isEnabled``.
    func isEnabled(at index: Int) -> Bool {
        guard index < 32 else { return isEnabled(at: -1) }
        return (enableFlags & (1 << (index + 1))) != 0
    }
    
}

// So Key-value-coding from an NSTableView can treat the menu (title) object same as any item.
extension Menu {
    @objc dynamic var keyEquivalent: String {
        get {
            return ""
        }
        set {
            
        }
    }
    @objc dynamic var markCharacter: String {
        get {
            return ""
        }
        set {
            
        }
    }
    
    @objc dynamic var hasKeyEquivalent: Bool {
        return false
    }
    @objc dynamic var menuInt16Command: UInt16 { return 0 }
    @objc dynamic var menu4CCCommand: String { "" }
    @objc dynamic var styleByte: UInt8 { return 0 }
    @objc dynamic var iconID: Int { return 0 }
    @objc dynamic var iconImage: NSImage? { return nil }
    @objc dynamic var submenuID: Int { return 0 }

    @objc dynamic var isItem: Bool { return false }
    @objc dynamic var has4CCCommand: Bool { return false }
    @objc dynamic var hasInt16Command: Bool { return false }
    @objc dynamic var iconType: UInt8 { return 0 }
    
    @objc dynamic var textColor: NSColor {
        isEnabled ? NSColor.textBackgroundColor : NSColor.systemGray
    }
    
    override var description: String {
        return "\(self.className)(name = \"\(name)\", id = \(menuID)){" + items.map({ $0.description }).joined(separator: ", ") + "}"
    }
    
    override func setNilValueForKey(_ key: String) {
        if key == "menuID" {
            menuID = 0
        } else if key == "mdefID" {
            mdefID = 0
        } else {
            super.setNilValueForKey(key)
        }
    }

}
