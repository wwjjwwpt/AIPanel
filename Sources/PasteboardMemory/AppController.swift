import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate, ObservableObject {
    let store = HistoryStore()
    lazy var clipboardMonitor = ClipboardMonitor(store: store)
    lazy var screenshotMonitor = ScreenshotMonitor(store: store)
    let pasteService = PasteService()
    let launchAtLogin = LaunchAtLoginManager()
    let hotKey = GlobalHotKeyManager()
    lazy var screenshotCapture = ScreenshotCaptureManager(store: store, clipboardMonitor: clipboardMonitor)

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        clipboardMonitor.start()
        screenshotMonitor.start()
        pasteService.clipboardMonitor = clipboardMonitor
        configureStatusItem()
        configurePanel()
        hotKey.onPressed = { [weak self] id in
            switch id {
            case 1: self?.togglePanel()
            case 2:
                self?.hidePanel()
                self?.screenshotCapture.startCapture()
            default: break
            }
        }
        hotKey.register(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), id: 1)
        hotKey.register(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | shiftKey), id: 2)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.screenshotMonitor.needsArchiveWorkspace {
                NSApp.activate(ignoringOtherApps: true)
                _ = self.screenshotMonitor.chooseArchiveWorkspace()
            }
            self.showPanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        screenshotMonitor.stop()
        hotKey.unregisterAll()
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "剪贴板历史")
        item.button?.toolTip = "瞬贴 · ⌘⇧V 历史 · ⌃⇧A 截图"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.addItem(withTitle: "显示瞬贴", action: #selector(showFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出瞬贴", action: #selector(quitApp), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        statusMenu = menu
        statusItem = item
    }

    private func configurePanel() {
        let content = HistoryPanelView(
            store: store,
            pasteService: pasteService,
            onPaste: { [weak self] item in self?.paste(item) },
            onClose: { [weak self] in self?.hidePanel() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        let hosting = NSHostingController(rootView: content)
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 650),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentViewController = hosting
        self.panel = panel

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.panel?.isVisible == true else { return event }
            switch event.keyCode {
            case 53:
                self?.hidePanel()
                return nil
            case 126:
                NotificationCenter.default.post(name: .moveHistorySelectionUp, object: nil)
                return nil
            case 125:
                NotificationCenter.default.post(name: .moveHistorySelectionDown, object: nil)
                return nil
            case 36, 76:
                NotificationCenter.default.post(name: .pasteHistorySelection, object: nil)
                return nil
            case 51, 117:
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                    NotificationCenter.default.post(name: .deleteHistorySelection, object: nil)
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let statusMenu {
            statusItem?.menu = statusMenu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            togglePanel()
        }
    }

    @objc private func showFromMenu() { showPanel() }
    @objc private func openSettingsFromMenu() { openSettings() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func togglePanel() {
        if panel?.isVisible == true { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        guard let panel else { return }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        positionPanel(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .focusHistorySearch, object: nil)
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    func paste(_ item: HistoryItem) {
        pasteService.copy(item, returnTo: previousApplication) { [weak self] in self?.hidePanel() }
    }

    func openSettings() {
        hidePanel()
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(
            screenshotMonitor: screenshotMonitor,
            launchAtLogin: launchAtLogin,
            pasteService: pasteService,
            store: store
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "瞬贴设置"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 430))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - panel.frame.width / 2
        let y = frame.maxY - panel.frame.height - 26
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension Notification.Name {
    static let focusHistorySearch = Notification.Name("focusHistorySearch")
    static let moveHistorySelectionUp = Notification.Name("moveHistorySelectionUp")
    static let moveHistorySelectionDown = Notification.Name("moveHistorySelectionDown")
    static let pasteHistorySelection = Notification.Name("pasteHistorySelection")
    static let deleteHistorySelection = Notification.Name("deleteHistorySelection")
}
