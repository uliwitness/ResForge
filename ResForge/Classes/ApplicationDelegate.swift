import Cocoa
import RFSupport

@NSApplicationMain
class ApplicationDelegate: NSObject, NSApplicationDelegate {
    // Don't configure prefs controller until needed
    private lazy var prefsController: NSWindowController = {
        ValueTransformer.setValueTransformer(LaunchActionTransformer(), forName: .launchActionTransformerName)
        let prefs = NSWindowController(windowNibName: "PrefsWindow")
        prefs.window?.center()
        return prefs
    }()
    
    override init() {
        NSApp.registerServicesMenuSendTypes([.string], returnTypes: [.string])
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            kConfirmChanges: false,
            kDeleteResourceWarning: true,
            kLaunchAction: kDisplayOpenPanel,
            kShowSidebar: true
        ])
        
        SupportRegistry.scanForResources()
        // Load plugins
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .allDomainsMask)
        if let plugins = Bundle.main.builtInPlugInsURL {
            self.scanForPlugins(folder: plugins)
        }
        for url in appSupport {
            self.scanForPlugins(folder: url.appendingPathComponent("ResForge/Plugins"))
        }
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        let launchAction = UserDefaults.standard.string(forKey: kLaunchAction)
        switch launchAction {
        case kOpenUntitledFile:
            return true
        case kDisplayOpenPanel:
            NSDocumentController.shared.openDocument(sender)
            return false
        default:
            return false
        }
    }
    
    @IBAction func showInfo(_ sender: Any) {
        InfoWindowController.shared.showWindow(sender)
    }
    
    @IBAction func showPrefs(_ sender: Any) {
        self.prefsController.showWindow(sender)
    }
    
    private func scanForPlugins(folder: URL) {
        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        } catch {
            return
        }
        for item in items where item.pathExtension == "plugin" {
            guard let plugin = Bundle(url: item) else {
                continue
            }
            SupportRegistry.scanForResources(in: plugin)
            PluginRegistry.register(plugin)
        }
    }
}