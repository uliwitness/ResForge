/*
 This is a registry where all our resource-editor plugins are looked
 up and entered in a list, so you can ask for the editor for a specific
 resource type and it is returned immediately. This registry reads the
 types a plugin handles from their info.plist.
 */

import Foundation
import RKSupport

class PluginManager: NSObject, NSWindowDelegate, ResKnifePluginManager {
    private static var registry: [String: ResKnifePlugin.Type] = [:]
    private var editorWindows: [String: ResKnifePlugin] = [:]
    private var document: ResourceDocument
    
    @objc static func editor(for type: String) -> ResKnifePlugin.Type? {
        return registry[type]
    }
    
    static func scanForPlugins() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .allDomainsMask)
        if let plugins = Bundle.main.builtInPlugInsURL {
            self.scan(folder: plugins)
        }
        for url in appSupport {
            self.scan(folder: url.appendingPathComponent("ResKnife/Plugins"))
        }
    }
    
    private static func scan(folder: URL) {
        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        } catch {
            return
        }
        for item in items where item.pathExtension == "plugin" {
            guard
                let plugin = Bundle(url: item),
                let pluginClass = plugin.principalClass as? ResKnifePlugin.Type,
                let supportedTypes = plugin.infoDictionary?["RKEditedTypes"] as? [String]
            else {
                continue
            }
            SupportRegistry.scanForResources(in: plugin)
            for type in supportedTypes {
                registry[type] = pluginClass
            }
        }
    }
    
    // MARK: -
    
    @objc init(_ document: ResourceDocument) {
        self.document = document
    }
    
    @objc func closeAll() -> Bool {
        for (_, value) in editorWindows {
            if let plug = value as? NSWindowController {
                plug.window?.performClose(self)
                if plug.window?.isVisible ?? false {
                    return false
                }
            }
        }
        return true
    }
    
    // This is called when closing editor windows. It provides a common save process, with confirmation
    // according to the user preferences, so that plugins don't have to handle this themselves.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.makeFirstResponder(nil) // Ensure any controls have ended editing
        if sender.isDocumentEdited {
            let plug = sender.windowController as! ResKnifePlugin
            if UserDefaults.standard.bool(forKey: kConfirmChanges) {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Do you want to keep the changes you made to this resource?", comment: "")
                alert.informativeText = NSLocalizedString("Your changes cannot be saved later if you don't keep them.", comment: "")
                alert.addButton(withTitle: NSLocalizedString("Keep", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("Don't Keep", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                alert.beginSheetModal(for: sender) { returnCode in
                    switch (returnCode) {
                    case .alertFirstButtonReturn: // keep
                        plug.saveResource?(alert)
                        sender.close()
                    case .alertSecondButtonReturn: // don't keep
                        sender.close()
                    default:
                        break
                    }
                }
                return false
            }
            plug.saveResource?(sender)
        }
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        let plug = (notification.object as! NSWindow).windowController as! ResKnifePlugin
        for (key, value) in editorWindows where value === plug {
            editorWindows.removeValue(forKey: key)
        }
    }
    
    // MARK: - Protocol functions
    
    @objc func open(resource: Resource, using editor: ResKnifePlugin.Type? = nil, template: String? = nil) {
        // Work out editor to use
        var editor = editor ?? Self.editor(for: resource.type) ?? Self.editor(for: "Template Editor")
        var tmplResource: Resource!
        if editor is ResKnifeTemplatePlugin.Type {
            // If template editor, find the template to use
            tmplResource = self.findResource(ofType: "TMPL", name: template ?? resource.type)
            // If no template, switch to hex editor
            if tmplResource == nil {
                editor = Self.editor(for: "Hexadecimal Editor")
            }
        }
        
        // Keep track of opened resources so we don't open them multiple times
        let key = String(describing: resource).appending(String(describing: editor))
        var plug = editorWindows[key]
        if plug == nil {
            // Set a reference to the manager on the resource. This allows the plugin to access the manager and call the protocol functions.
            resource.manager = self
            if let editor = editor as? ResKnifeTemplatePlugin.Type {
                plug = editor.init(resource: resource, template: tmplResource)
            } else {
                plug = editor!.init(resource: resource)
            }
            editorWindows[key] = plug
        }
        if let plug = plug as? NSWindowController {
            // We want to control the windowShouldClose function
            plug.window?.delegate = self
            plug.showWindow(self)
        }
    }
    
    func allResources(ofType type: String, currentDocumentOnly: Bool = false) -> [Resource] {
        var resources = document.dataSource().allResources(ofType: type)
        if !currentDocumentOnly {
            let docs = NSDocumentController.shared.documents as! [ResourceDocument]
            for doc in docs where doc !== document {
                resources.append(contentsOf: doc.dataSource().allResources(ofType: type))
            }
        }
        return resources
    }

    func findResource(ofType type: String, id: Int, currentDocumentOnly: Bool = false) -> Resource? {
        if let resource = document.dataSource().findResource(type: type, id: id) {
            return resource
        }
        if !currentDocumentOnly {
            let docs = NSDocumentController.shared.documents as! [ResourceDocument]
            for doc in docs where doc !== document {
                if let resource = doc.dataSource().findResource(type: type, id: id) {
                    return resource
                }
            }
        }
        return SupportRegistry.dataSource.findResource(type: type, id: id)
    }

    func findResource(ofType type: String, name: String, currentDocumentOnly: Bool = false) -> Resource? {
        if let resource = document.dataSource().findResource(type: type, name: name) {
            return resource
        }
        if !currentDocumentOnly {
            let docs = NSDocumentController.shared.documents as! [ResourceDocument]
            for doc in docs where doc !== document {
                if let resource = doc.dataSource().findResource(type: type, name: name) {
                    return resource
                }
            }
        }
        return SupportRegistry.dataSource.findResource(type: type, name: name)
    }
}