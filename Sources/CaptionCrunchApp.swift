import AppKit
import SwiftUI

extension Notification.Name {
    static let saveTranscriptRequested = Notification.Name("saveTranscriptRequested")
    static let importAudioRequested = Notification.Name("importAudioRequested")
    static let recordRequested = Notification.Name("recordRequested")
    static let copyAllRequested = Notification.Name("copyAllRequested")
    static let settingsRequested = Notification.Name("settingsRequested")
    static let runTranscriptActionRequested = Notification.Name("runTranscriptActionRequested")
    static let transcriptActionsChanged = Notification.Name("transcriptActionsChanged")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            self.installMainMenu()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(transcriptActionsDidChange(_:)),
            name: .transcriptActionsChanged,
            object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        installMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func requestSaveTranscript(_ sender: Any?) {
        NotificationCenter.default.post(name: .saveTranscriptRequested, object: nil)
    }

    @objc private func requestImportAudio(_ sender: Any?) {
        NotificationCenter.default.post(name: .importAudioRequested, object: nil)
    }

    @objc private func requestRecord(_ sender: Any?) {
        NotificationCenter.default.post(name: .recordRequested, object: nil)
    }

    @objc private func requestCopyAll(_ sender: Any?) {
        NotificationCenter.default.post(name: .copyAllRequested, object: nil)
    }

    @objc private func requestTranscriptAction(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID {
            NotificationCenter.default.post(name: .runTranscriptActionRequested, object: id)
        }
    }

    @objc private func showSettings(_ sender: Any?) {
        NotificationCenter.default.post(name: .settingsRequested, object: nil)
    }

    @objc private func showTranscriptActionsHelp(_ sender: Any?) {
        Task { @MainActor in
            TranscriptActionsHelpWindowController.shared.show()
        }
    }

    @objc private func transcriptActionsDidChange(_ notification: Notification) {
        installMainMenu()
    }

    private func installMainMenu() {
        let appName = "Caption Crunch"
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings...", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.delegate = self
        let recordItem = fileMenu.addItem(withTitle: "Record", action: #selector(requestRecord(_:)), keyEquivalent: "r")
        recordItem.target = self
        let importItem = fileMenu.addItem(withTitle: "Import Audio...", action: #selector(requestImportAudio(_:)), keyEquivalent: "i")
        importItem.target = self
        let saveItem = fileMenu.addItem(withTitle: "Save Transcript...", action: #selector(requestSaveTranscript(_:)), keyEquivalent: "s")
        saveItem.target = self
        addTranscriptActions(to: fileMenu)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.delegate = self
        rebuildEditMenu(editMenu)
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let actionsHelp = helpMenu.addItem(withTitle: "Transcript Actions Help", action: #selector(showTranscriptActionsHelp(_:)), keyEquivalent: "")
        actionsHelp.target = self
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)

        NSApp.mainMenu = mainMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "Edit" {
            rebuildEditMenu(menu)
        } else if menu.title == "File" {
            rebuildFileMenu(menu)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu.title == "Edit" {
            rebuildEditMenu(menu)
        } else if menu.title == "File" {
            rebuildFileMenu(menu)
        }
    }

    private func rebuildFileMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let recordItem = menu.addItem(withTitle: "Record", action: #selector(requestRecord(_:)), keyEquivalent: "r")
        recordItem.target = self
        let importItem = menu.addItem(withTitle: "Import Audio...", action: #selector(requestImportAudio(_:)), keyEquivalent: "i")
        importItem.target = self
        let saveItem = menu.addItem(withTitle: "Save Transcript...", action: #selector(requestSaveTranscript(_:)), keyEquivalent: "s")
        saveItem.target = self
        addTranscriptActions(to: menu)
    }

    private func addTranscriptActions(to menu: NSMenu) {
        let actions = TranscriptActionStore.load()
        guard !actions.isEmpty else { return }

        menu.addItem(NSMenuItem.separator())
        for action in actions {
            let item = menu.addItem(withTitle: action.displayName, action: #selector(requestTranscriptAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
            if let symbolName = action.displaySymbolName {
                item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: action.displayName)
            }
        }
    }

    private func rebuildEditMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let copyItem = menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.target = nil

        let copyAllItem = menu.addItem(withTitle: "Copy All", action: #selector(requestCopyAll(_:)), keyEquivalent: "c")
        copyAllItem.keyEquivalentModifierMask = [.command, .shift]
        copyAllItem.target = self

        let selectAllItem = menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.target = nil
    }
}

@main
struct CaptionCrunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var transcriber = CaptionTranscriber()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        Window("Caption Crunch", id: "main") {
            ContentView()
                .environmentObject(transcriber)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.titleBar)
    }
}
