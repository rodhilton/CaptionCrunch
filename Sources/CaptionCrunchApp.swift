import AppKit
import SwiftUI

extension Notification.Name {
    static let saveTranscriptRequested = Notification.Name("saveTranscriptRequested")
    static let importAudioRequested = Notification.Name("importAudioRequested")
    static let copyAllRequested = Notification.Name("copyAllRequested")
    static let settingsRequested = Notification.Name("settingsRequested")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            self.installMainMenu()
        }
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

    @objc private func requestCopyAll(_ sender: Any?) {
        NotificationCenter.default.post(name: .copyAllRequested, object: nil)
    }

    @objc private func showSettings(_ sender: Any?) {
        NotificationCenter.default.post(name: .settingsRequested, object: nil)
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
        let importItem = fileMenu.addItem(withTitle: "Import Audio...", action: #selector(requestImportAudio(_:)), keyEquivalent: "i")
        importItem.target = self
        let saveItem = fileMenu.addItem(withTitle: "Save Transcript...", action: #selector(requestSaveTranscript(_:)), keyEquivalent: "s")
        saveItem.target = self
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
        helpMenu.addItem(withTitle: "\(appName) Help", action: nil, keyEquivalent: "")
            .isEnabled = false
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)

        NSApp.mainMenu = mainMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "Edit" {
            rebuildEditMenu(menu)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu.title == "Edit" {
            rebuildEditMenu(menu)
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
